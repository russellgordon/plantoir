import Foundation

/// What a build downloaded the first time its pages used it, or why it
/// stopped without it (#674), as the shared Python printed it.
///
/// A build prints one `PLANTOIR_DOWNLOADED: {json}` line per kind of file
/// (`contracts/shared-rules.json` → `keptDownloads.marker`) when it downloaded
/// something for its pages (a PhET simulation, #674; the sounds a tune names,
/// #679) or stopped because something was not on this computer and could not
/// be downloaded (`keptDownloads.stop`). This reads it so the app writes the
/// trail line, from the two places `SwiftGotReadyReport` reads its own: the
/// console of a run the app started (`ScriptRunner`) and the log of a publish
/// launchd ran (`ScheduledDeploy`). The line is machinery: the console a
/// teacher reads leaves it out, by the one rule for every `PLANTOIR_` line
/// (`BuildMarkerLine.isMachineLine`).
struct KeptDownloadsReport: Equatable {

    // MARK: - Stored properties

    /// `keptDownloads.marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_DOWNLOADED:"

    /// `keptDownloads.kinds`: how many of each kind are said, one and
    /// several. A kind this app does not know yet (a newer website
    /// builder's) is said as files (`marker.trailWords.unknownKind`), never
    /// dropped. Pinned to the contract by `KeptDownloadsReportTests`.
    nonisolated static let kindWords: [String: (one: String, several: String)] = [
        "phet": (one: "a science simulation", several: "science simulations")
    ]

    /// `keptDownloads.marker.trailWords.unknownKind`.
    nonisolated static let unknownKindWords: (one: String, several: String) = (one: "a file", several: "files")

    /// `keptDownloads.marker.trailWords.why`, pinned by the `files for the
    /// site could not be downloaded` event's `whyWords`.
    nonisolated static let whyWords: [String: String] = [
        "offline": "no internet connection, or the download stopped",
        "damaged": "what arrived was not what was asked for, and was thrown away"
    ]

    let kind: String
    let count: Int

    /// True when the build downloaded; false when it stopped without them.
    let downloaded: Bool
    let bytes: Int64
    let seconds: Double

    /// Why it stopped (offline or damaged), or nil when it downloaded.
    let reason: String?

    let course: String?
    let section: Int?

    // MARK: - Computed properties

    /// The event this report is written under.
    nonisolated var event: ActivityTrail.Event {
        if downloaded {
            return .filesForTheSiteDownloaded
        }
        return .filesForTheSiteCouldNotBeDownloaded
    }

    /// 'a science simulation' or '3 science simulations'.
    nonisolated var what: String {
        let words: (one: String, several: String) = KeptDownloadsReport.kindWords[kind]
            ?? KeptDownloadsReport.unknownKindWords
        if count == 1 {
            return words.one
        }
        return "\(count) \(words.several)"
    }

    /// The trail line without the course and section, which `noteOnTheTrail`
    /// puts in front. Megabytes are bytes / 10⁶ and seconds as given, each
    /// with one decimal and a full stop whatever the Mac's language.
    nonisolated var trailSentence: String {
        let posix: Locale = Locale(identifier: "en_US_POSIX")
        if downloaded {
            let megabytes: String = String(format: "%.1f", locale: posix, Double(bytes) / 1_000_000)
            let secondsText: String = String(format: "%.1f", locale: posix, seconds)
            return "downloaded \(what) for the site (\(megabytes) MB in \(secondsText) s), kept on this computer for later builds"
        }
        let key: String = reason ?? ""
        let why: String = KeptDownloadsReport.whyWords[key] ?? key
        return "could not download \(what) for the site, so it was not built: " + why
    }

    // MARK: - Functions

    /// Every report in a stretch of output, read from the prefix onward, as
    /// `SwiftGotReadyReport.reports(in:)` reads its own. A line with no kind,
    /// or with neither a count downloaded nor a count failed and its reason,
    /// is not a report.
    nonisolated static func reports(in text: String) -> [KeptDownloadsReport] {
        var found: [KeptDownloadsReport] = []
        for line in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let kind = object["kind"] as? String, !kind.isEmpty else {
                continue
            }
            var course: String? = object["course"] as? String
            if course?.isEmpty == true {
                course = nil
            }
            let section: Int? = object["section"] as? Int
            if let downloadedCount = (object["downloaded"] as? NSNumber)?.intValue {
                let bytes: Int64 = (object["bytes"] as? NSNumber)?.int64Value ?? 0
                let seconds: Double = (object["seconds"] as? NSNumber)?.doubleValue ?? 0
                found.append(KeptDownloadsReport(
                    kind: kind, count: downloadedCount, downloaded: true, bytes: bytes, seconds: seconds,
                    reason: nil, course: course, section: section
                ))
                continue
            }
            guard let failedCount = (object["failed"] as? NSNumber)?.intValue,
                  let reason = object["reason"] as? String, !reason.isEmpty else {
                continue
            }
            found.append(KeptDownloadsReport(
                kind: kind, count: failedCount, downloaded: false, bytes: 0, seconds: 0,
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

    /// Whether a line is this machine-readable one.
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(markerPrefix)
    }
}
