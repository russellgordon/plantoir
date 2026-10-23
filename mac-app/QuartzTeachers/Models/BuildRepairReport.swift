import Foundation

/// Something the build put right in the teacher's own files without being
/// asked, because Plantoir itself wrote it wrong (#584).
///
/// The build prints one `PLANTOIR_REPAIRED: {json}` line per repair it WROTE
/// into a teacher's page (`contracts/shared-rules.json` → `buildRepairs.marker`),
/// and this reads it so the repair can go on the activity trail as
/// `folder problem repaired` — the same event a repair the teacher asked for
/// leaves, since both record that something wrong was put right. Read from the
/// same two places as `PagesDatedByTheBuild`: the console of a run the app
/// started, and a scheduled publish's own log. The line is machinery, so the
/// console a teacher reads leaves it out (`TranscriptBuilder`, by the one rule
/// for every `PLANTOIR_` line); the build prints a plain sentence beside it.
///
/// Not printed when the build could quote only its own copy (a course kept for
/// reference, a linked page, a locked one), so such a course does not leave a
/// line on every build.
struct BuildRepairReport: Equatable {

    // MARK: - Stored properties

    /// `buildRepairs.marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_REPAIRED:"

    /// The key of the front page's title repair in `buildRepairs`.
    nonisolated static let frontPageTitleQuoted: String = "frontPageTitleQuoted"

    let course: String
    let section: Int

    /// The repair's key in `buildRepairs` — today only `frontPageTitleQuoted`.
    let repair: String

    /// The page's place in the course folder, without `.md` — a name, never
    /// anything written on the page.
    let page: String

    // MARK: - Computed properties

    /// The trail line for this repair, or nil for a repair this app does not
    /// know — a newer build's — which then leaves no line rather than a wrong
    /// one. `buildRepairs.frontPageTitleQuoted.trailLine`.
    nonisolated var trailSentence: String? {
        if repair == BuildRepairReport.frontPageTitleQuoted {
            return "the build put quotes around the title of the front page (\(page)) so it could be read"
        }
        return nil
    }

    // MARK: - Functions

    /// Every report in a stretch of output, read from the prefix onward, as
    /// `PagesDatedByTheBuild.reports(in:)` reads its own: a marker glued to
    /// the tail of somebody else's half line must still be read (#153).
    nonisolated static func reports(in text: String) -> [BuildRepairReport] {
        var found: [BuildRepairReport] = []
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
                  let repair = object["repair"] as? String,
                  let page = object["page"] as? String,
                  !page.isEmpty else {
                continue
            }
            found.append(BuildRepairReport(course: course, section: section, repair: repair, page: page))
        }
        return found
    }

    /// Writes each report in the text that this app knows how to word on the
    /// trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            guard let sentence = report.trailSentence else {
                continue
            }
            ActivityTrail.note(
                .folderProblemRepaired, sentence,
                course: report.course, section: report.section
            )
        }
    }

    /// Whether a line is this machine-readable one — a line CARRYING the
    /// prefix anywhere, hidden whole, as `SiteHealthFinding.isMarkerLine`.
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(markerPrefix)
    }
}
