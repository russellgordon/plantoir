import Observation
import SwiftUI

/// The progress panel's stop question while it is being asked (#988, the
/// fourth review): whether it is open, and its "Don't ask again" box. The
/// alert's two buttons call `chooseStop()` and `chooseCancel()`, so what each
/// button remembers is tested in every suite (`StopQuestionTests`), not only
/// by the opt-in pressed-key tests.
///
/// Russell's rulings of 2026-11-19: the box counts only when the teacher goes
/// on to stop; Cancel remembers nothing; each question has its own setting;
/// while a question is off, Cancel stops that task at once, as a preview's
/// does. Alerts, https://developer.apple.com/design/human-interface-guidelines/alerts:
/// the stopping button is the default, so Return stops.
@Observable
final class StopQuestionAsking {

    // MARK: - Stored properties

    /// The question this panel asks before stopping its task; `nil` for a
    /// preview, which stops at once.
    let question: StopQuestion?

    /// Where whether the question is still asked is read and remembered.
    let settings: AppSettings

    /// True while the question is showing.
    var isAsking: Bool = false

    /// The question's "Don't ask again" box. Unticked each time the question
    /// opens, and read only by `chooseStop()`.
    var dontAskAgain: Bool = false

    /// The stopping button's key: Return, as the default button.
    let stopButtonShortcut: KeyboardShortcut = KeyboardShortcut.defaultAction

    /// Cancel's keys in the question: Escape and Command-Period.
    let cancelButtonShortcut: KeyboardShortcut = KeyboardShortcut.cancelAction

    // MARK: - Computed properties

    /// Whether stopping asks first now: there is a question, and the teacher
    /// has not turned it off.
    var asksBeforeStopping: Bool {
        if let question {
            return question.isAsked(in: settings)
        }
        return false
    }

    // MARK: - Initializer

    init(question: StopQuestion?, settings: AppSettings) {
        self.question = question
        self.settings = settings
    }

    // MARK: - Functions

    /// The panel's Cancel was pressed, by click or by key. Says whether the
    /// task should stop now: true when nothing is asked. Otherwise the
    /// question opens with its box unticked, if the task can still be
    /// stopped, and nothing stops yet.
    func pressCancel(taskCanStillBeStopped: Bool) -> Bool {
        if !asksBeforeStopping {
            return true
        }
        if taskCanStillBeStopped {
            dontAskAgain = false
            isAsking = true
        }
        return false
    }

    /// The stopping button (Stop Deploy or Stop Share). A ticked box turns
    /// this question off, and only this one, writing its trail line; an
    /// unticked one changes nothing. The caller then stops the task.
    func chooseStop() {
        if let question {
            question.stopWasChosen(dontAskAgainTicked: dontAskAgain, in: settings)
        }
        isAsking = false
        dontAskAgain = false
    }

    /// The question's Cancel: the question closes, the task runs on, and
    /// nothing is remembered, the box included.
    func chooseCancel() {
        isAsking = false
        dontAskAgain = false
    }

    /// The task ended while the question was open: nothing is left to stop,
    /// so the question goes.
    func taskEnded() {
        isAsking = false
    }
}
