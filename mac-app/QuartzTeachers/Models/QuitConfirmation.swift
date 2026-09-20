import Foundation

/// What ⌘Q does when Plantoir is in the middle of something.
///
/// **Why there is a question at all.** Until 2026-09-19 the quit path could
/// not find the programs it needed, so quitting did nothing to the website
/// builder and there was nothing to interrupt (issue #220). Making it work
/// means a quit can now genuinely stop a publish — and the one case where
/// that hurts is the one a teacher cannot see happening, so they are asked.
///
/// **What counts as "under way", and what deliberately does not.** A publish
/// recorded in `CourseActivity` does; a preview does not. The reason is what
/// each fact can actually tell us. `CourseActivity.activePublishes` is
/// process-wide and lasts exactly as long as the publish, so it means what it
/// says. A preview is known through `PreviewLeases`, and a lease is held for
/// the whole time a preview is OPEN — it cannot tell a section still building
/// from one that finished twenty minutes ago and is sitting there being
/// looked at. Asking on every lease would mean asking almost every quit,
/// which trains a teacher to dismiss the question before reading it, and the
/// one it exists for is the publish. (`CourseActivity.courseIsBusy` folds the
/// two together, which is right for greying out a menu item and wrong here;
/// asking it the wrong one of those questions has produced a bug in this app
/// before.) Previews are not left to their fate either: the quit path stops
/// the app's own previews cleanly on the way out rather than asking about
/// them.
///
/// **What is out of reach, and is therefore never asked about.** A scheduled
/// publish, an assistant driving Plantoir over MCP, and a teacher's own
/// Terminal run are all OTHER processes with their own memory of what they
/// are doing. Nothing here can see them — so nothing here asks about them,
/// and the quit script instead refuses to stop anything while a launcher for
/// the folder is running on this Mac.
@MainActor
enum QuitConfirmation {

    // MARK: - Types

    /// Why the app is being asked to go away.
    enum Reason {
        case theTeacherAskedToQuit
        case theMacIsLoggingOutOrShuttingDown
    }

    /// What the teacher answered.
    enum Choice: String {
        case keepWorking
        case quitAnyway
    }

    // MARK: - Stored properties

    /// The four-character codes macOS sends when the quit is the SYSTEM's
    /// idea rather than the teacher's: log out, restart, shut down, and the
    /// three "are you sure?" variants of the same.
    ///
    /// A modal put up in `applicationShouldTerminate` during a log out blocks
    /// the log out — the Mac sits there until macOS times the app out and
    /// reports it as the one that would not quit. So the question is skipped
    /// entirely and everything is left running instead, which is the same
    /// answer the quit script reaches by itself when it finds work in flight.
    static let systemQuitReasonCodes: [OSType] = [
        OSType(kAELogOut),
        OSType(kAEReallyLogOut),
        OSType(kAEShowRestartDialog),
        OSType(kAERestart),
        OSType(kAEShowShutdownDialog),
        OSType(kAEShutDown)
    ]

    static let keepWorkingButton: String = "Keep Working"
    static let quitAnywayButton: String = "Quit Anyway"

    // MARK: - Functions

    /// What this app is in the middle of, in the words the teacher is shown —
    /// or nil when it is in the middle of nothing.
    static func workUnderWay(publishes: [CourseActivity.PublishRecord]) -> String? {
        if publishes.isEmpty {
            return nil
        }
        if publishes.count == 1 {
            let only: CourseActivity.PublishRecord = publishes[0]
            return "publishing Section \(only.sectionNumber) of \(only.courseCode)"
        }
        return "publishing \(publishes.count) sections"
    }

    /// Whether to put the question up at all.
    static func shouldAsk(reason: Reason, workUnderWay: String?) -> Bool {
        if reason == .theMacIsLoggingOutOrShuttingDown {
            return false
        }
        return workUnderWay != nil
    }

    /// Which kind of quit a four-character reason code stands for. No code at
    /// all — the ordinary ⌘Q — is the teacher's own.
    static func reason(forQuitReasonCode code: OSType?) -> Reason {
        guard let code else {
            return .theTeacherAskedToQuit
        }
        for systemCode in systemQuitReasonCodes {
            if systemCode == code {
                return .theMacIsLoggingOutOrShuttingDown
            }
        }
        return .theTeacherAskedToQuit
    }

    /// The question itself.
    static func question(about workUnderWay: String) -> String {
        return "Plantoir is still \(workUnderWay)."
    }

    /// The sentence under it.
    ///
    /// "Could", not "would", and the difference is measured rather than
    /// cautious. A publish is a separate program on a pseudo-terminal, and it
    /// is NOT killed when the app goes — it is reparented and carries on
    /// (measured 2026-09-19, a job still running well after its parent had
    /// exited). What a teacher loses is the watching: the console is gone, a
    /// question the publish asks is asked of nobody, and the folder's website
    /// builder is then left running for as long as it lasts. Saying it would
    /// be stopped would be a sentence describing something that does not
    /// happen, which is worse than no sentence because it will be believed.
    static func explanation() -> String {
        return "Quitting now could leave it unfinished, with the class website "
            + "part way updated."
    }

    /// The line the trail gets, whichever way it went.
    static func trailLine(workUnderWay: String, choice: Choice) -> String {
        let answer: String = choice == .quitAnyway
            ? "chose to quit anyway"
            : "chose to keep working"
        return "asked whether to quit while still \(workUnderWay), and the teacher \(answer)"
    }
}
