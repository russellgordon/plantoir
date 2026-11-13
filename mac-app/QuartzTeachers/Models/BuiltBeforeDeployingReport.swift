import Foundation

/// The words for a deploy that built the section's site first (#768, #748
/// part 2), and the reader of the marker a scheduled deploy's wrapper prints
/// when its own build first succeeded.
///
/// A deploy that builds first takes a minute or more longer, and the line
/// answers "why was this morning's deploy slow?" days later. The words say
/// what the reason WAS: a first build, a preview's build, an update and a
/// changed page each say so, and only the last says that something in the
/// course changed.
///
/// Three writers, one build each: the app writes the line for its own build
/// first (`MultiDestinationDeployRunner`), deploy.sh writes its own lines for
/// a deploy typed in Terminal (`note_on_the_trail`), and the scheduled
/// deploy's wrapper prints the marker, which `ScheduledDeploy` reads from the
/// run's log. `contracts/shared-rules.json` → `activityTrail.mustRecord.
/// "site built again before deploying"` holds the words.
struct BuiltBeforeDeployingReport: Equatable {

    // MARK: - Stored properties

    /// The marker the scheduled wrapper prints. Pinned by the contract's `marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_BUILT_BEFORE_DEPLOYING:"

    /// The trail line, pinned by the contract's `line`.
    nonisolated static let line: String = "{course}/{section} · built the website again before deploying it — {why}"

    /// The trail line for a section that had not been built, pinned by
    /// `lineWhenItHadNotBeenBuilt`.
    nonisolated static let lineWhenItHadNotBeenBuilt: String =
        "{course}/{section} · built the website before deploying it — it had not been built yet"

    /// Why, by reason. Pinned by the contract's `whyWords`.
    nonisolated static let whyWords: [String: String] = [
        "pages": "something in the course had changed since it was last built",
        "toolchain": "Plantoir had been updated since it was last built",
        "preview": "the last build was made by a preview",
        "clock": "its last build was dated later than now, so the computer's clock had changed",
        "frontPageUnreadable": "its front page could not be read",
    ]

    /// The reason word the wrapper printed, such as `pages`.
    let reason: String

    /// Where the run was for: `COURSE/SECTION`, a space written `+`.
    let place: String

    // MARK: - Computed properties

    /// The trail line for this report, or nil for a reason with no words:
    /// a wrong reason is never written.
    nonisolated var trailSentence: String? {
        let readablePlace: String = place.replacingOccurrences(of: "+", with: " ")
        return BuiltBeforeDeployingReport.wholeLine(reason: reason, place: readablePlace)
    }

    // MARK: - Functions

    /// The line after its place, for `ActivityTrail.note(_:_:course:section:)`,
    /// which writes the place itself.
    nonisolated static func sentence(for reason: BuildFreshness.RebuildReason) -> String {
        let whole: String = wholeLine(reason: reason.rawValue, place: "{place}") ?? ""
        return whole.replacingOccurrences(of: "{place} · ", with: "")
    }

    /// The whole line for a reason and a place, or nil for a reason with no words.
    nonisolated static func wholeLine(reason: String, place: String) -> String? {
        var template: String = line
        if reason == BuildFreshness.RebuildReason.neverBuilt.rawValue {
            template = lineWhenItHadNotBeenBuilt
        } else if let why = whyWords[reason] {
            template = template.replacingOccurrences(of: "{why}", with: why)
        } else {
            return nil
        }
        return template.replacingOccurrences(of: "{course}/{section}", with: place)
    }

    /// Every report in a stretch of output. A line that does not have the
    /// marker's shape — a reason made of letters and a place — reports
    /// nothing, so a path or a command can never reach the trail.
    nonisolated static func reports(in text: String) -> [BuiltBeforeDeployingReport] {
        var found: [BuiltBeforeDeployingReport] = []
        for textLine in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = textLine.range(of: markerPrefix) else {
                continue
            }
            var words: [String] = []
            for word in textLine[prefixRange.upperBound...].split(separator: " ", omittingEmptySubsequences: true) {
                words.append(String(word).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard words.count == 2,
                  FolderSetUpAgainReport.isAReason(words[0]),
                  LeftoverWorkReport.isAPlace(words[1]) else {
                continue
            }
            found.append(BuiltBeforeDeployingReport(reason: words[0], place: words[1]))
        }
        return found
    }

    /// Notes every report in a stretch of output on the activity trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            guard let sentence = report.trailSentence else {
                continue
            }
            ActivityTrail.note(.siteBuiltAgainBeforeDeploying, sentence)
        }
    }
}
