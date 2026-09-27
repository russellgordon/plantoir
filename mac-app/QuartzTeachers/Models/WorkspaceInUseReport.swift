import Foundation

/// A launcher's report that a working folder's workspace was in use when it
/// needed remaking (GitHub #94), as the launcher printed it.
///
/// Before a launcher removes a folder's workspace to make it again, it looks
/// at what is running inside it: it waits for a build or a publish, and it
/// refuses while a preview from the folder is open (`contracts/app-rules.json`
/// → `previewPorts.whenTheWorkspaceIsInUse`). When it waited or refused it
/// prints one `PLANTOIR_WORKSPACE_IN_USE:` line, and this reads it so the app
/// can write the trail line — from the console of a run it started
/// (`ScriptRunner`) and from the log of a publish launchd ran
/// (`ScheduledDeploy`), the two readers `PagesDatedByTheBuild` has for the
/// same reason. The line is machinery: the console a teacher reads leaves it
/// out (`TranscriptBuilder`), and the launcher prints a plain sentence too.
///
/// Read by the app rather than written onto the trail by the launcher itself
/// so that the event has ONE writer for its words, and a real call site. The
/// cost, stated in the contract: a run typed at the command line leaves its
/// console sentence and no trail line.
struct WorkspaceInUseReport: Equatable {

    /// What happened, by the word the launcher prints for it.
    enum Outcome: String {
        case waited = "waited"
        case aPreviewWasOpen = "preview"
        case workDidNotFinish = "work"
    }

    // MARK: - Stored properties

    /// The marker the launchers print. Pinned by the contract's `marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_WORKSPACE_IN_USE:"

    /// The three lines, pinned by the contract's `lineWhen…` fields.
    nonisolated static let lineWhenItWaited: String =
        "{place} · waited {seconds} s for something in this working folder to finish before updating its workspace, then went ahead"
    nonisolated static let lineWhenAPreviewWasOpen: String =
        "{place} · stopped before starting — this working folder's workspace needed updating and the preview of {preview} was still open"
    nonisolated static let lineWhenWorkDidNotFinish: String =
        "{place} · stopped before starting — this working folder's workspace needed updating and something in it was still being built or published after {seconds} s"

    /// Which of the three things happened.
    let outcome: Outcome

    /// How many seconds the launcher had waited when it went ahead or stopped.
    let seconds: Int

    /// Where the run was for: `COURSE/SECTION`, or the word `setup`.
    let place: String

    /// The open preview a refusal names, as `COURSE/SECTION`; empty otherwise.
    let openPreview: String

    // MARK: - Computed properties

    /// The trail line, in the words `contracts/shared-rules.json` →
    /// `activityTrail.mustRecord."workspace was in use"` pins.
    nonisolated var trailSentence: String {
        var sentence: String = ""
        switch outcome {
        case .waited:
            sentence = WorkspaceInUseReport.lineWhenItWaited
        case .aPreviewWasOpen:
            sentence = WorkspaceInUseReport.lineWhenAPreviewWasOpen
        case .workDidNotFinish:
            sentence = WorkspaceInUseReport.lineWhenWorkDidNotFinish
        }
        sentence = sentence.replacingOccurrences(of: "{place}", with: place)
        sentence = sentence.replacingOccurrences(of: "{seconds}", with: String(seconds))
        sentence = sentence.replacingOccurrences(of: "{preview}", with: openPreview)
        return sentence
    }

    // MARK: - Functions

    /// Every report in a stretch of output, read line by line as it arrives.
    /// A line that does not have the marker's shape reports nothing.
    nonisolated static func reports(in text: String) -> [WorkspaceInUseReport] {
        var found: [WorkspaceInUseReport] = []
        for line in SiteHealthFinding.linesOf(text) {
            // From the prefix onward, as `PagesDatedByTheBuild.reports(in:)`
            // reads its own: a marker glued to the tail of somebody else's
            // half line must still be read (#153).
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
            var words: [String] = []
            for word in payload.split(separator: " ", omittingEmptySubsequences: true) {
                words.append(String(word))
            }
            guard words.count == 3 || words.count == 4,
                  let outcome = Outcome(rawValue: words[0]),
                  let seconds = Int(words[1]) else {
                continue
            }
            var openPreview: String = ""
            if words.count == 4 {
                openPreview = words[3]
            }
            if outcome == .aPreviewWasOpen && openPreview.isEmpty {
                continue
            }
            found.append(
                WorkspaceInUseReport(outcome: outcome, seconds: seconds, place: words[2], openPreview: openPreview)
            )
        }
        return found
    }

    /// Notes every report in a stretch of output on the activity trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(.workspaceWasInUse, report.trailSentence)
        }
    }

    /// Whether a line is this machine-readable one, so the console can keep it
    /// out of what a teacher reads (rule 1). A line CARRYING the prefix
    /// anywhere is hidden whole, and never offered as a question — the rule
    /// #153 set for every marker: the prefix ends in a colon, so a line cut
    /// just after it would otherwise look like a prompt.
    nonisolated static func isMarkerLine(_ line: String) -> Bool {
        return line.contains(markerPrefix)
    }
}
