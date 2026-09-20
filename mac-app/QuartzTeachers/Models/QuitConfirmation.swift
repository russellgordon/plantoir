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

    /// One button, and what pressing it means.
    ///
    /// The pair travels together for a reason. `NSAlert` has no notion of
    /// which button means what: it reports `.alertFirstButtonReturn` for
    /// whichever title was added first, so a one-line reorder of two
    /// `addButton` calls would silently swap the MEANINGS and make Keep
    /// Working quit. Keeping the title beside its answer, in one ordered
    /// list that the alert and the test both read, is what stops that being
    /// a one-line change with nothing in its way.
    struct Button {

        // MARK: - Stored properties

        let title: String
        let choice: Choice
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

    /// The buttons in the order they are put up. The FIRST is the default
    /// one, and the safe answer is the default answer: a teacher who presses
    /// Return without reading keeps their work.
    static let buttonsInOrder: [Button] = [
        Button(title: keepWorkingButton, choice: .keepWorking),
        Button(title: quitAnywayButton, choice: .quitAnyway)
    ]

    // MARK: - Functions

    /// What this app is in the middle of, in the words the teacher is shown —
    /// or nil when it is in the middle of nothing.
    ///
    /// **Reads its own facts, and that is the point.** It used to be handed
    /// `CourseActivity.activePublishes` by the delegate, which left the one
    /// decision worth pinning — publishes count, previews do not — outside
    /// anything a test could reach: the contract's "a preview is open" case
    /// passed for every implementation, and swapping `activePublishes` for
    /// `courseIsBusy` at the call site left the whole suite green. Now the
    /// choice of source is inside the function the contract cases run.
    static func workUnderWay() -> String? {
        return workUnderWay(publishes: CourseActivity.activePublishes, previews: PreviewLeases.active)
    }

    /// The same decision with both facts handed in, for a test that wants to
    /// build them rather than install them.
    ///
    /// `previews` is taken and deliberately NOT used — a parameter that
    /// exists to say so out loud. A lease is held for as long as a preview is
    /// OPEN, so it cannot tell a section still building from one that
    /// finished twenty minutes ago; asking on every lease would mean asking
    /// almost every quit, and the question exists for the publish. Quitting
    /// deals with previews by stopping them, not by asking about them.
    static func workUnderWay(
        publishes: [CourseActivity.PublishRecord],
        previews: [PreviewLeases.Lease]
    ) -> String? {
        _ = previews
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
    /// cautious — in both directions, which is why this comment is long.
    ///
    /// Plantoir does not END the publish: it is a separate program, and
    /// `ScriptRunner.stopEveryLivePreview` deliberately passes it over. But it
    /// is a program writing to a pseudo-terminal the APP owned, and
    /// `deploy.sh` runs under `set -euo pipefail` (line 3), so when the app
    /// goes its next line of output fails and the publish stops there.
    /// Measured 2026-09-19, twice independently: two children of identical
    /// shape orphaned on a dead pty — the plain one ran to the end, the
    /// `set -euo pipefail` one died at its next `echo`, three ticks in.
    ///
    /// So "could leave it unfinished" is the honest sentence, and neither
    /// "would be stopped" nor "carries on" is. What a teacher loses either way
    /// is the watching: the console is gone and a question the publish asks is
    /// asked of nobody.
    static func explanation() -> String {
        return "Quitting now could leave it unfinished, with the class website "
            + "part way updated."
    }

    /// What the button at a given position means — read from the same list
    /// the alert builds itself from, so the two cannot disagree.
    static func choice(atButtonIndex index: Int) -> Choice {
        if index >= 0 && index < buttonsInOrder.count {
            return buttonsInOrder[index].choice
        }
        // An answer nobody recognises is the safe one.
        return .keepWorking
    }

    /// The line the trail gets, whichever way it went.
    static func trailLine(workUnderWay: String, choice: Choice) -> String {
        let answer: String = choice == .quitAnyway
            ? "chose to quit anyway"
            : "chose to keep working"
        return "asked whether to quit while still \(workUnderWay), and the teacher \(answer)"
    }
}
