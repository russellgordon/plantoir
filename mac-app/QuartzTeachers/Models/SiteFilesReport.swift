import Foundation

/// Which of a course's files a build's site leaves off because no page
/// students can see uses them, and what the check after the build put right
/// (#901), as the shared Python printed it.
///
/// A build prints one `PLANTOIR_SITE_FILES: {json}` line after it has read
/// its finished site (`contracts/shared-rules.json` → `siteFiles.marker`):
/// counts only, never a file's name. This reads it so the app writes the
/// trail line, from the two places `KeptDownloadsReport` reads its own: the
/// console of a run the app started (`ScriptRunner`) and the log of a
/// deploy launchd ran (`ScheduledDeploy`). The line is machinery: the console
/// a teacher reads leaves it out, by the one rule for every `PLANTOIR_` line
/// (`BuildMarkerLine.isMachineLine`).
struct SiteFilesReport: Equatable {

    // MARK: - Stored properties

    /// `siteFiles.marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_SITE_FILES:"

    /// The emitter name that means Quartz's own copied every file and the
    /// check took off the rest (`siteFiles.marker.rule`, assetsEmitter).
    nonisolated static let quartzsOwnEmitter: String = "quartz"

    let course: String?
    let section: Int?
    let leftOff: Int
    let putBack: Int
    let putBackFailed: Int
    let takenOut: Int
    /// Course files found on the site that no built page names, those taken
    /// out included (`siteFiles.marker`, unreferenced).
    let unreferenced: Int
    let firstTime: Bool
    let changed: Bool
    let assetsEmitter: String

    // MARK: - Computed properties

    /// `siteFiles.marker.writtenWhen`: the first build that leaves files off,
    /// a build whose count changed, a build that put a file back, could not,
    /// took one out or found one no page names, and a build that used
    /// Quartz's own emitter. Nothing on a build that changed nothing.
    nonisolated var isWorthWriting: Bool {
        if firstTime || changed {
            return true
        }
        if putBack > 0 || putBackFailed > 0 || takenOut > 0 || unreferenced > 0 {
            return true
        }
        return assetsEmitter == SiteFilesReport.quartzsOwnEmitter
    }

    /// The files no page names that are still on the site because its text
    /// mentions them: `unreferenced` less `takenOut` (`activityTrail.mustRecord`
    /// → `notZero.keptRule`). `unreferenced` alone counts the files already
    /// taken out too, so it read as if they were still there (901a fix
    /// review, M2).
    nonisolated var keptBecauseMentioned: Int {
        let kept: Int = unreferenced - takenOut
        if kept < 0 {
            return 0
        }
        return kept
    }

    /// The parts of the line that are said only when their count is above
    /// zero (`activityTrail.mustRecord` → `notZero`), in the contract's order.
    nonisolated var countsSaidWhenNotZero: String {
        var parts: String = ""
        if putBackFailed > 0 {
            parts += ", \(putBackFailed) could not be put back"
        }
        if keptBecauseMentioned > 0 {
            parts += ", \(keptBecauseMentioned) kept because the website mentions them"
        }
        return parts
    }

    /// The trail line without the course and section, which `noteOnTheTrail`
    /// puts in front (`activityTrail.mustRecord` → `line`, and
    /// `lineWhenSortedAfterTheBuild` when Quartz's own emitter ran).
    nonisolated var trailSentence: String {
        let counts: String = "(\(putBack) put back, \(takenOut) taken out\(countsSaidWhenNotZero))"
        if assetsEmitter == SiteFilesReport.quartzsOwnEmitter {
            return "the website leaves off \(leftOff) files no published page uses, sorted after the build "
                + "because the website builder's settings had changed shape " + counts
        }
        return "the website leaves off \(leftOff) files no published page uses " + counts
    }

    // MARK: - Functions

    /// Every report in a stretch of output, read from the prefix onward, as
    /// `KeptDownloadsReport.reports(in:)` reads its own. A line without a
    /// count of files left off is not a report.
    nonisolated static func reports(in text: String) -> [SiteFilesReport] {
        var found: [SiteFilesReport] = []
        for line in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let leftOff = (object["leftOff"] as? NSNumber)?.intValue else {
                continue
            }
            var course: String? = object["course"] as? String
            if course?.isEmpty == true {
                course = nil
            }
            let section: Int? = object["section"] as? Int
            let putBack: Int = (object["putBack"] as? NSNumber)?.intValue ?? 0
            let putBackFailed: Int = (object["putBackFailed"] as? NSNumber)?.intValue ?? 0
            let takenOut: Int = (object["takenOut"] as? NSNumber)?.intValue ?? 0
            let unreferenced: Int = (object["unreferenced"] as? NSNumber)?.intValue ?? 0
            let firstTime: Bool = (object["firstTime"] as? Bool) ?? false
            let changed: Bool = (object["changed"] as? Bool) ?? false
            let emitter: String = (object["assetsEmitter"] as? String) ?? "plantoir"
            found.append(SiteFilesReport(
                course: course, section: section, leftOff: leftOff, putBack: putBack,
                putBackFailed: putBackFailed, takenOut: takenOut, unreferenced: unreferenced,
                firstTime: firstTime,
                changed: changed, assetsEmitter: emitter
            ))
        }
        return found
    }

    /// Writes each report worth writing onto the trail, under its course and
    /// section when the line names both.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            if !report.isWorthWriting {
                continue
            }
            let event: ActivityTrail.Event = .siteLeavesOffFilesNoPublishedPageUses
            if let course = report.course, let section = report.section {
                ActivityTrail.note(event, report.trailSentence, course: course, section: section)
            } else {
                ActivityTrail.note(event, report.trailSentence)
            }
        }
    }

    /// Whether a line is this machine-readable one.
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(markerPrefix)
    }
}
