import Foundation

/// The teacher's pages a build rewrote with their class's date, as the build
/// reported them.
///
/// Every preview and every publish gives the section's front page the date of
/// the class it shows, and every page a visible class brings the date of the
/// earliest such class — in the teacher's own files (#275, #276;
/// `contracts/class-planning.json` → `sectionIndexPointer.dateCases` and
/// `datingPagesAClassBrings.atBuildTime`). When it rewrites any, the build
/// prints one `PLANTOIR_DATED: {json}` line naming them, and this reads it so
/// the names can go on the activity trail. The line is machinery: the console
/// a teacher reads leaves it out (`TranscriptBuilder`), and the build prints a
/// plain sentence beside it.
struct PagesDatedByTheBuild: Equatable {

    // MARK: - Stored properties

    let course: String
    let section: Int

    /// Each page's place in the course folder, without `.md` — a name, never
    /// anything written on the page.
    let pages: [String]

    // MARK: - Computed properties

    /// The trail line, in the shape `contracts/shared-rules.json` →
    /// `pagesDatedByTheBuild.trailLine` gives: the count first, so a long list
    /// can be shortened without losing how many there were.
    nonisolated var trailSentence: String {
        var shown: [String] = []
        for page in pages {
            if shown.count == PagesDatedByTheBuild.namesShownOnTheTrail {
                break
            }
            shown.append(page)
        }
        var names: String = shown.joined(separator: ", ")
        let notShown: Int = pages.count - shown.count
        if notShown > 0 {
            names += " and \(notShown) more"
        }
        let noun: String = pages.count == 1 ? "page" : "pages"
        return "the build gave \(pages.count) \(noun) the date of their class: \(names)"
    }

    // MARK: - Functions

    /// The marker the build prints. Pinned by
    /// `contracts/shared-rules.json` → `pagesDatedByTheBuild.marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_DATED:"

    /// How many names one trail line carries before it says "and N more". The
    /// first build of a course made before this can date a great many pages at
    /// once, and a trail line hundreds of names long is one nobody reads.
    nonisolated static let namesShownOnTheTrail: Int = 40

    /// Every report in a stretch of output, read as it arrives — the same way
    /// `SiteHealthFinding.findings(in:)` reads its lines, and for the same
    /// reason: the line is printed mid-build, long before the tail the app's
    /// other readers look at.
    nonisolated static func reports(in text: String) -> [PagesDatedByTheBuild] {
        var found: [PagesDatedByTheBuild] = []
        for line in SiteHealthFinding.linesOf(text) {
            // From the prefix onward, for the reason
            // `SiteHealthFinding.findings(in:)` gives: a marker glued to the
            // tail of somebody else's half line must still be read (#153).
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let course = object["course"] as? String,
                  let section = object["section"] as? Int,
                  let pages = object["pages"] as? [String],
                  !pages.isEmpty else {
                continue
            }
            found.append(PagesDatedByTheBuild(course: course, section: section, pages: pages))
        }
        return found
    }

    /// Whether a line is this machine-readable one, so the console can keep it
    /// out of what a teacher reads (rule 1: a raw JSON blob is machinery).
    ///
    /// A line CARRYING the prefix anywhere, hidden whole — the same rule as
    /// `SiteHealthFinding.isMarkerLine`, and for the same reason (#153).
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(markerPrefix)
    }
}
