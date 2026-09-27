import Foundation

/// `preview.sh`'s report that a preview's address was held by something
/// else on this Mac (GitHub #310), as the launcher printed it.
///
/// Found in the #204 rehearsal: with two macOS accounts signed in, the second
/// account's workspace was handed an address the first account's preview
/// held, its builder's forward failed without a word, and its Preview opened
/// the other person's site. `preview.sh` now looks before it starts a stopped
/// workspace and before it announces an address (`contracts/app-rules.json`
/// → `previewPorts.whenAnotherAccountHasTheAddress`), and prints one
/// `PLANTOIR_PREVIEW_ADDRESS_HELD:` line whenever the look found something —
/// or could not be made. This reads it so the app can write the trail line
/// from the console of a run it started (`ScriptRunner`). A scheduled publish
/// never prints it, because `deploy.sh` never serves a preview.
///
/// Read by the app rather than written onto the trail by the launcher, the
/// same arrangement as `WorkspaceInUseReport` and for the same reason: one
/// writer for the event's words, and a real call site. The line is
/// machinery, so the console a teacher reads leaves it out
/// (`TranscriptBuilder`); the launcher prints a plain sentence beside it.
struct PreviewAddressHeldReport: Equatable {

    /// What happened, by the word the launcher prints for it.
    enum Outcome: String {
        case remadeBeforeStarting = "before-start"
        case remade = "remade"
        case refused = "refused"
        case unchecked = "unchecked"
    }

    // MARK: - Stored properties

    /// The marker `preview.sh` prints. Pinned by the contract's `marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_PREVIEW_ADDRESS_HELD:"

    /// The four lines, pinned by the contract's `lineWhen…` fields.
    nonisolated static let lineWhenRemadeBeforeStarting: String =
        "{place} · something else on this Mac was using preview address {address} while this working folder's workspace was stopped, so it was set up again on free addresses before starting"
    nonisolated static let lineWhenRemade: String =
        "{place} · another account on this Mac, or macOS itself, was using preview address {address}, so this working folder's workspace was set up again on free addresses"
    nonisolated static let lineWhenRefused: String =
        "{place} · the preview stopped before building — another account on this Mac, or macOS itself, was still using its address {address} after this working folder's workspace was set up again on free addresses"
    nonisolated static let lineWhenUnchecked: String =
        "{place} · did not check whether another account on this Mac was using preview address {address}: this run was pointed at a website builder Plantoir did not set up"

    /// Which of the four things happened.
    let outcome: Outcome

    /// The preview address in question: a number on this Mac.
    let address: Int

    /// Where the run was for: `COURSE/SECTION`.
    let place: String

    // MARK: - Computed properties

    /// The trail line, in the words `contracts/shared-rules.json` →
    /// `activityTrail.mustRecord."preview address held by another account"`
    /// pins.
    nonisolated var trailSentence: String {
        var sentence: String = ""
        switch outcome {
        case .remadeBeforeStarting:
            sentence = PreviewAddressHeldReport.lineWhenRemadeBeforeStarting
        case .remade:
            sentence = PreviewAddressHeldReport.lineWhenRemade
        case .refused:
            sentence = PreviewAddressHeldReport.lineWhenRefused
        case .unchecked:
            sentence = PreviewAddressHeldReport.lineWhenUnchecked
        }
        sentence = sentence.replacingOccurrences(of: "{place}", with: place)
        sentence = sentence.replacingOccurrences(of: "{address}", with: String(address))
        return sentence
    }

    // MARK: - Functions

    /// Every report in a stretch of output, read line by line as it arrives.
    /// A line that does not have the marker's shape reports nothing.
    nonisolated static func reports(in text: String) -> [PreviewAddressHeldReport] {
        var found: [PreviewAddressHeldReport] = []
        for line in SiteHealthFinding.linesOf(text) {
            // From the prefix onward, so a marker glued to the tail of
            // somebody else's half line is still read (#153).
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
            var words: [String] = []
            for word in payload.split(separator: " ", omittingEmptySubsequences: true) {
                words.append(String(word))
            }
            guard words.count == 3,
                  let outcome = Outcome(rawValue: words[0]),
                  let address = Int(words[1]),
                  address > 0 else {
                continue
            }
            found.append(PreviewAddressHeldReport(outcome: outcome, address: address, place: words[2]))
        }
        return found
    }

    /// Notes every report in a stretch of output on the activity trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(.previewAddressHeldByAnotherAccount, report.trailSentence)
        }
    }

    /// Whether a line is this machine-readable one, so the console can keep it
    /// out of what a teacher reads (rule 1). A line CARRYING the prefix
    /// anywhere is hidden whole, and never offered as a question (#153).
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(markerPrefix)
    }
}
