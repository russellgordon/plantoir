import Observation
import SwiftUI

/// Remembers that Cancel was pressed for one run of a task, so Cancel acts
/// once per run however it is pressed: a click, Escape, Command-Period, or a
/// held key repeating faster than the panel redraws (#988 review). A new run
/// (a different `startedAt`) can be cancelled again.
@Observable
final class CancelOncePerRun {

    // MARK: - Stored properties

    /// The run Cancel was pressed for, keyed by when it started. `nil`
    /// before any press. A runner with no start time (a test's) is keyed by
    /// `Date.distantPast`.
    var pressedForRunStartedAt: Date?

    // MARK: - Functions

    /// Whether Cancel has already been pressed for the run that started at
    /// `startedAt`.
    func hasBeenPressed(forRunStartedAt startedAt: Date?) -> Bool {
        let thisRun: Date = startedAt ?? Date.distantPast
        return pressedForRunStartedAt == thisRun
    }

    /// Records the press and says whether it is the first for this run.
    func pressOnce(forRunStartedAt startedAt: Date?) -> Bool {
        if hasBeenPressed(forRunStartedAt: startedAt) {
            return false
        }
        pressedForRunStartedAt = startedAt ?? Date.distantPast
        return true
    }
}
