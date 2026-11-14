import Foundation

/// The one switch for Undo and Redo as one list for the whole app (#899).
///
/// **Off until every action is on the list.** Each piece of #899 merges on
/// its own behind this constant, and while it is off the list is written in
/// SHADOW: every step an action records is written down, and nothing is ever
/// offered back to the teacher from it. Section ▸ Undo Last Change and Undo
/// Getting Ready keep working exactly as they did, and no Edit ▸ Undo item
/// exists. The last piece (U7) flips it, and only once the source scan
/// (`UndoWriterScanTests`) has no "waits for" reason left and the contract's
/// `undo.classes` covers every action on both lists.
///
/// Why a constant and not a preference: a half-covered Undo is worse than
/// none, because the step it passes over silently is the one a teacher
/// needed back. Nobody should be able to turn it on early, from a test or
/// from the defaults command line.
nonisolated enum UndoSwitch {

    // MARK: - Stored properties

    /// False: the journal is written in shadow and never offered.
    static let undoJournalIsLive: Bool = false

    /// The list keeps the last fifty steps, counted across the whole app
    /// (Russell's rulings 3 and 5 on #899).
    static let stepsKept: Int = 50

    /// And keeps none older than thirty days, by the step's `madeAt`.
    static let daysKept: Int = 30

    /// A new journal segment starts once the current one passes this size.
    static let segmentBytes: Int = 4 * 1024 * 1024

    /// How long a reader or writer waits for the list's lock before it gives
    /// up: two seconds, the bound the contract's `undo.rule` names.
    static let lockWaitSeconds: Double = 2.0

    /// How long a live step's closing event waits for the lock.
    static let finishWaitSeconds: Double = 10.0

    /// How long a SHADOW write waits for the lock. Shorter on purpose: while
    /// the switch is off a busy lock must never make a teacher's action
    /// noticeably slower, and a step that is not written costs nothing
    /// anybody can see (plan 4.9).
    static let shadowLockWaitSeconds: Double = 0.25

    // MARK: - Computed properties

    /// The mode every caller records in, read from the switch.
    static var currentMode: UndoMode {
        if undoJournalIsLive {
            return .live
        }
        return .shadow
    }
}

/// Whether a failure to write the list may stop an action.
nonisolated enum UndoMode: String, Sendable {

    /// The list is offered. A step that cannot be written down is refused
    /// before anything changes, because an unrecorded change above the head
    /// would make the next Undo pass over it.
    case live

    /// The list is written and never offered. A failure to write it never
    /// blocks, slows or alters the action; it leaves one trail line. Recovery
    /// in this mode never writes into a working folder either: it only
    /// records what it found.
    case shadow
}
