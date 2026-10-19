import Foundation

/// What a build did about the My Progress page (#545), as the build reported
/// it.
///
/// The build adds a page students see to every section whose pages have
/// success criteria to tick, so "my students have no My Progress page" is a
/// question somebody will ask. Every build whose section wants the page
/// prints one `PLANTOIR_MY_PROGRESS: {json}` line saying whether it made it,
/// how many pages count, and — when it made none — why; this reads it so the
/// answer is on the activity trail. The line is machinery: the console a
/// teacher reads leaves it out (`BuildMarkerLine`), and the build prints a
/// plain sentence above it. `contracts/shared-rules.json` →
/// `myProgressBuilt`, the `CoverageMapsBuilt` pattern.
struct MyProgressBuilt: Equatable {

    // MARK: - Stored properties

    let course: String
    let section: Int
    let built: Bool
    let pages: Int
    let reason: String

    /// The marker the build prints. Pinned by
    /// `contracts/shared-rules.json` → `myProgressBuilt.marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_MY_PROGRESS:"

    // MARK: - Computed properties

    /// The trail line, in the shapes `myProgressBuilt.trailLine.shapes`
    /// gives: what the build made, then the count or the reason, as a teacher
    /// would say it.
    nonisolated var trailSentence: String {
        if built {
            let noun: String = pages == 1 ? "page" : "pages"
            return "the build made the My Progress page: \(pages) \(noun) with success criteria to tick"
        }
        if reason == "teachersOwnPage" {
            return "the build made no My Progress page: the course has its own page called My Progress"
        }
        return "the build made no My Progress page: no page students can see has boxes to tick under a success-criteria heading"
    }

    // MARK: - Functions

    /// Every report in a stretch of output, read from the prefix onward — the
    /// way `CoverageMapsBuilt.reports(in:)` reads its own line, and for the
    /// same reason: a marker glued to the tail of somebody else's half line
    /// must still be read (#153).
    nonisolated static func reports(in text: String) -> [MyProgressBuilt] {
        var found: [MyProgressBuilt] = []
        for line in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let course = object["course"] as? String,
                  let section = object["section"] as? Int,
                  let built = object["built"] as? Bool,
                  let pages = object["pages"] as? Int,
                  let reason = object["reason"] as? String else {
                continue
            }
            found.append(MyProgressBuilt(course: course, section: section, built: built, pages: pages, reason: reason))
        }
        return found
    }

    /// Every report in `text`, on the activity trail. Called by the console
    /// reader of a run the app starts (`ScriptRunner`) and by the scheduled
    /// publish's log reader (`ScheduledDeploy.recordFolderProblems`).
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(
                .myProgressBuilt, report.trailSentence,
                course: report.course, section: report.section
            )
        }
    }
}
