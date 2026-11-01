import Foundation

/// A How I Teach page the build kept off the website although the course's
/// settings had LISTED it for the site (#209) — a page earlier builds
/// published, which is now kept back.
///
/// The build prints one `PLANTOIR_KEPT_OFF: {json}` line naming such pages
/// (`contracts/shared-rules.json` → `howITeachPage.keptOffMarker`), and this
/// reads it so the names can go on the activity trail — the same way, and
/// from the same two readers, as `PagesDatedByTheBuild`: the console of a run
/// the app started, and a scheduled publish's own log. The line is machinery,
/// so the console a teacher reads leaves it out (`TranscriptBuilder`); the
/// build prints a plain sentence beside it.
///
/// Printed only when a LISTED page was dropped, so a course whose page was
/// never on the site does not leave a line on every build.
struct HowITeachKeptOffReport: Equatable {

    // MARK: - Stored properties

    let course: String
    let section: Int

    /// Each page's place in the course folder, without `.md` — a name, never
    /// anything written on the page.
    let pages: [String]

    /// The build's own count of the pages it kept off, when it SHORTENED its
    /// line to stay under `contracts/shared-rules.json` → `machineLineLength`
    /// (#666, #704): the line then names only the first pages. `nil` for a
    /// whole line, which names every page.
    let count: Int?

    // MARK: - Computed properties

    /// How many pages were kept off: the line's `count` when it carries one,
    /// and never fewer than the names it carries, as
    /// `PagesDatedByTheBuild.total` reads its own.
    nonisolated var total: Int {
        let counted: Int = count ?? 0
        if counted > pages.count {
            return counted
        }
        return pages.count
    }

    /// `howITeachPage.keptOffTrailLine`, and
    /// `howITeachPage.keptOffTrailLineWhenShortened` when the line named
    /// fewer pages than it kept off.
    nonisolated var trailSentence: String {
        var names: String = pages.joined(separator: ", ")
        let notShown: Int = total - pages.count
        if notShown > 0 {
            if pages.isEmpty {
                names = "\(notShown) not named"
            } else {
                names += " and \(notShown) more"
            }
        }
        let noun: String = total == 1 ? "page" : "pages"
        return "the build kept \(total) \(noun) named How I Teach off the website that the "
             + "course's settings had listed for it: \(names)"
    }

    // MARK: - Initializer

    /// `count` is left out for a whole line.
    nonisolated init(course: String, section: Int, pages: [String], count: Int? = nil) {
        self.course = course
        self.section = section
        self.pages = pages
        self.count = count
    }

    // MARK: - Functions

    /// `howITeachPage.keptOffMarker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_KEPT_OFF:"

    /// Every report in a stretch of output, read from the prefix onward, as
    /// `PagesDatedByTheBuild.reports(in:)` reads its own.
    nonisolated static func reports(in text: String) -> [HowITeachKeptOffReport] {
        var found: [HowITeachKeptOffReport] = []
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
                  let pages = object["pages"] as? [String] else {
                continue
            }
            // An empty list WITH a count is a shortened line that named none
            // (k = 0); an empty list without one reports nothing.
            let count: Int? = object["count"] as? Int
            if pages.isEmpty && (count ?? 0) == 0 {
                continue
            }
            found.append(HowITeachKeptOffReport(course: course, section: section, pages: pages, count: count))
        }
        return found
    }

    /// Writes each report in the text on the trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(
                .howITeachPageKeptOff, report.trailSentence,
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
