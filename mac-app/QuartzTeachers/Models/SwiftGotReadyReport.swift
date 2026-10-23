import Foundation

/// How getting Swift ready on this Mac ended (#635), as preview.sh printed it
/// after building the Swift image: built, in how many seconds and with how
/// much downloaded, or not, and why.
///
/// preview.sh prints one `PLANTOIR_SWIFT: {json}` line on every ending of its
/// Swift step but "already there" — the shape Windows' fetch prints
/// (`contracts/shared-rules.json` → `codeRunnerBlocks.swift.windows.marker`,
/// and `codeRunnerBlocks.swift.mac` for when the Mac prints it and how its
/// bytes and reason are worked out). This reads it so the app writes the trail
/// line, from the two places `HelperBootstrapReport` reads its own: the console
/// of a run the app started (`ScriptRunner`) and the log of a publish launchd
/// ran (`ScheduledDeploy`), since a scheduled publish's build gets Swift ready
/// too. The line is machinery: the console a teacher reads leaves it out
/// (`TranscriptBuilder`, by the one rule for every `PLANTOIR_` line); the
/// launcher prints a plain sentence before it.
struct SwiftGotReadyReport: Equatable {

    // MARK: - Stored properties

    /// `codeRunnerBlocks.swift.windows.marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_SWIFT:"

    /// The words for each reason, pinned by the `Swift could not be got
    /// ready` event's `whyWords`. `busy` is a Windows reason (another
    /// installation running); a Mac never prints it, but a line carrying it
    /// is still worded.
    nonisolated static let whyWords: [String: String] = [
        "offline": "no internet connection, or the download stopped",
        "noRoom": "not enough free space",
        "damaged": "the download was not what was expected and was thrown away",
        "busy": "another installation was running",
        "unpack": "it could not be unpacked",
        "waited": "another preview was still getting it ready after 20 minutes"
    ]

    let ready: Bool
    let seconds: Int
    let downloadedBytes: Int64

    /// Why it could not be got ready, or nil when it was.
    let reason: String?

    /// The course and section whose preview needed it, when the line names
    /// them.
    let course: String?
    let section: Int?

    // MARK: - Computed properties

    /// The event this report is written under.
    nonisolated var event: ActivityTrail.Event {
        if ready {
            return .swiftGotReady
        }
        return .swiftCouldNotBeGotReady
    }

    /// The trail line, without the course and section (`noteOnTheTrail` puts
    /// them in front, as every course-and-section line has them). Gigabytes
    /// are bytes / 10⁹ with one decimal, written with a full stop whatever the
    /// Mac's language, as Windows writes them. A reason this app does not know
    /// — a newer launcher's — is written as its own key rather than dropped:
    /// the failure is the line worth having, and a key is unworded, not wrong.
    nonisolated var trailSentence: String {
        if ready {
            let gigabytes: Double = Double(downloadedBytes) / 1_000_000_000
            let gigabytesText: String = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), gigabytes)
            return "got Swift ready on this computer in \(seconds) s (\(gigabytesText) GB downloaded, once)"
        }
        let key: String = reason ?? ""
        let why: String = SwiftGotReadyReport.whyWords[key] ?? key
        return "Swift could not be got ready on this computer: " + why
    }

    // MARK: - Functions

    /// Every report in a stretch of output, read from the prefix onward, as
    /// `PagesDatedByTheBuild.reports(in:)` reads its own: a marker glued to the
    /// tail of somebody else's half line must still be read (#153). A line
    /// with no `ready`, or a failure with no reason, is not a report.
    nonisolated static func reports(in text: String) -> [SwiftGotReadyReport] {
        var found: [SwiftGotReadyReport] = []
        for line in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ready = object["ready"] as? Bool else {
                continue
            }
            var reason: String? = nil
            if !ready {
                guard let said = object["reason"] as? String, !said.isEmpty else {
                    continue
                }
                reason = said
            }
            let seconds: Int = (object["seconds"] as? NSNumber)?.intValue ?? 0
            let downloadedBytes: Int64 = (object["downloadedBytes"] as? NSNumber)?.int64Value ?? 0
            var course: String? = object["course"] as? String
            if course?.isEmpty == true {
                course = nil
            }
            let section: Int? = object["section"] as? Int
            found.append(SwiftGotReadyReport(
                ready: ready, seconds: seconds, downloadedBytes: downloadedBytes,
                reason: reason, course: course, section: section
            ))
        }
        return found
    }

    /// Writes each report in the text onto the trail, under its course and
    /// section when the line names both.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            if let course = report.course, let section = report.section {
                ActivityTrail.note(report.event, report.trailSentence, course: course, section: section)
            } else {
                ActivityTrail.note(report.event, report.trailSentence)
            }
        }
    }

    /// Whether a line is this machine-readable one — a line CARRYING the
    /// prefix anywhere, hidden whole, as `SiteHealthFinding.isMarkerLine`.
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(markerPrefix)
    }
}
