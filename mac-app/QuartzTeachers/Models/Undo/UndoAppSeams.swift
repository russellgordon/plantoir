import Foundation

/// Where the app keeps its list, and how the list reaches the trail.
///
/// The one file of `Models/Undo/` that knows about the rest of the app
/// (`RealHome`, `ActivityTrail`), so every other file there compiles on its
/// own: the U1 harness builds them without the app.
nonisolated enum UndoJournalLocation {

    // MARK: - Stored properties

    /// A test points the list somewhere of its own (an unwritable place, to
    /// prove a failing list never touches the action). Nil in the app.
    nonisolated(unsafe) static var folderOverride: URL?

    // MARK: - Computed properties

    /// `Library/Application Support/Plantoir/undo` under the home
    /// `RealHome.forFiles` answers: the real one in the app, the `--state-dir`
    /// folder in a UI-tested app, the throwaway home under the unit suite.
    static var folderURL: URL {
        if let folderOverride {
            return folderOverride
        }
        return RealHome.forFiles
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Plantoir", isDirectory: true)
            .appendingPathComponent("undo", isDirectory: true)
    }

    // MARK: - Functions

    /// The app's list, with its trail lines connected.
    static func standardJournal() -> UndoJournal {
        UndoTrail.install()
        return UndoJournal(folderURL: folderURL)
    }
}

/// The trail lines U1 writes (`activityTrail.mustRecord`). Counts and
/// codes only: the journal holds page text, the trail never does.
nonisolated enum UndoTrail {

    // MARK: - Stored properties

    /// Set once, the first time the app's list is made (the core review's M7:
    /// it used to be set again on every publish).
    nonisolated(unsafe) private static var installed: Bool = false

    private static let guardLock: NSLock = NSLock()

    // MARK: - Functions

    static func install() {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        if installed {
            return
        }
        installed = true
        UndoTrailHook.interruptedLine = { course, section, phase, putBack, inTheWay in
            ActivityTrail.note(
                .undoRolledBack,
                UndoTrail.interruptedLine(course: course, section: section, phase: phase, putBack: putBack, inTheWay: inTheWay)
            )
        }
        UndoTrailHook.couldNotRecordLine = { action, course, section, mode, why in
            ActivityTrail.note(
                .undoCouldNotRecordAStep,
                UndoTrail.couldNotRecordLine(action: action, course: course, section: section, mode: mode, why: why)
            )
        }
        UndoTrailHook.rolledBackLine = { course, section, phase, files in
            ActivityTrail.note(
                .undoRolledBack,
                UndoTrail.rolledBackLine(course: course, section: section, phase: phase, files: files)
            )
        }
    }

    /// `ICS3U/1 · the undo list could not record publishPages: the list was
    /// busy. The change went ahead (the list is not in use yet).`
    static func couldNotRecordLine(action: String, course: String, section: Int?, mode: UndoMode, why: String) -> String {
        var line: String = ""
        if !course.isEmpty {
            line = course
            if let section {
                line += "/\(section)"
            }
            line += " · "
        }
        line += "the undo list could not record \(action): \(why). "
        if mode == .shadow {
            line += "The change went ahead (the list is not in use yet)."
        } else {
            line += "Nothing was changed."
        }
        return line
    }

    /// `ICS3U/1 · the undo list put back 2 files left part way by a change
    /// that stopped, found 1 changed by hand since, and cleared the list`.
    static func interruptedLine(course: String, section: Int?, phase: UndoPhase, putBack: Int, inTheWay: Int) -> String {
        let counted: String = inTheWay == 1 ? "1 file" : "\(inTheWay) files"
        return rolledBackLine(course: course, section: section, phase: phase, files: putBack)
            + ", found \(counted) changed by hand since, and cleared the list"
    }

    /// `ICS3U/1 · the undo list put back 2 files left part way by a change
    /// that stopped`.
    static func rolledBackLine(course: String, section: Int?, phase: UndoPhase, files: Int) -> String {
        var line: String = course
        if let section {
            line += "/\(section)"
        }
        let counted: String = files == 1 ? "1 file" : "\(files) files"
        let what: String
        switch phase {
        case .begin:
            what = "a change"
        case .undoing:
            what = "an undo"
        case .redoing:
            what = "a redo"
        }
        return line + " · the undo list put back \(counted) left part way by \(what) that stopped"
    }
}
