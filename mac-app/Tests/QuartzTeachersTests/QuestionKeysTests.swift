import AppKit
import Observation
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Return and Escape on this release's questions and sheets (#832), pressed
/// for real: each one is drawn in an `NSWindow` that is never put on the
/// screen, a key-down is sent to the sheet the question opens, and the test
/// reads which button answered.
///
/// **What was measured first (#832).** In a SwiftUI alert each button gets
/// ONE key. The shape this release used for "Cancel is the default"
/// (`role: .cancel` and `.keyboardShortcut(.defaultAction)` on Cancel) gave
/// Cancel Return and NOTHING Escape, so Escape did not close the Remove
/// Group question, Start the Groups Again or Replace It…. The alternatives
/// measured: Cancel with `role: .cancel` alone takes Escape, and a plain
/// action button beside it then takes Return; given `role: .destructive`
/// the action takes no key. No arrangement gives one button both keys. So
/// each question's risky button is destructive and Cancel is the cancel
/// button: Escape closes the question, and a Return presses nothing at all.
/// A SHEET can have both, and the two-lists sheet does: Cancel keeps Return
/// and `.onExitCommand` gives the sheet Escape, which its
/// `.interactiveDismissDisabled()` had taken away. The share's console
/// already closed on Escape (SwiftUI closes a sheet that has no Cancel of
/// its own), measured, so it is pinned here and not changed.
///
/// **Since #834** Replace It…, Remove Group and Start the Groups Again are
/// `FactsQuestionSheet`s, and since #833 so are the public-address warning
/// and the dialog after Change Password. **Since #973 (Russell, 2026-11-15,
/// following Apple's Human Interface Guidelines)** the risky ones have no
/// default button: Return leaves the sheet showing and answers nothing, and
/// Escape runs the sheet's `cancel`. After Change Password, Share Again is
/// the default (Return) and Later is Escape. Each test checks which closure
/// answered, not only that the sheet closed: with Keyboard Navigation off
/// (the macOS default) `.onExitCommand` alone never fired, and SwiftUI
/// closed the sheet around `cancel` (#973, measured on the second Mac; the
/// main Mac has Keyboard Navigation on and hid it). Nothing here depends on
/// Keyboard Navigation being on.
///
/// Measured failing on the code before #832: put
/// `.keyboardShortcut(.defaultAction)` back under any question's Cancel
/// (Escape stops closing it), take `role: .destructive` off the public
/// warning's Share Without a Password (Return presses it), or delete the
/// `.onExitCommand` from `PlanShareListsSheet` (Escape does nothing).
@MainActor
final class QuestionKeysTests: XCTestCase {

    // MARK: - Types

    /// The keys a test sends.
    enum Key {
        case escape
        case returnKey
        case commandPeriod
    }

    /// A sheet's two possible answers, written by the sheet's closures.
    @Observable
    final class Answers {

        // MARK: - Stored properties

        var showing: Bool = true {
            didSet {
                if oldValue && !showing {
                    answerWhenClosed = answer
                }
            }
        }

        var answer: String = ""

        /// How many times `cancel` ran (#973: exactly once per question).
        var cancelCount: Int = 0

        /// The answer as it stood at the moment the presenter's state said
        /// the question was closed, or nil before it closed (#973 review:
        /// only the binding route answers before that moment).
        var answerWhenClosed: String?

        /// The item `ItemPage` asks about, or nil.
        var asked: Asked? {
            didSet {
                if oldValue != nil && asked == nil {
                    answerWhenClosed = answer
                }
            }
        }

        /// The ids of the items whose `cancel` ran, in order.
        var cancelled: [String] = []
    }

    /// An item a question is shown for, as Replace It… is shown for its
    /// warning.
    struct Asked: Identifiable {

        // MARK: - Stored properties

        let id: String
        let question: FactsQuestion
        let goAheadIsTheDefault: Bool
    }

    /// A question shown for an item, through `.factsQuestionSheet(item:)`
    /// as `ReplaceReferenceCourseAlert` shows Replace It… (#973 review).
    /// Its `cancel` clears only its own item, as that presenter's does.
    struct ItemPage: View {

        // MARK: - Stored properties

        let answers: Answers

        // MARK: - Body

        var body: some View {
            @Bindable var answers = answers
            Color.white
                .factsQuestionSheet(item: $answers.asked) { (shown: Asked) in
                    FactsQuestionSheet(
                        question: shown.question,
                        identifier: "test",
                        goAheadIsTheDefault: shown.goAheadIsTheDefault,
                        goAhead: {
                            answers.answer = "go"
                            answers.asked = nil
                        },
                        cancel: {
                            answers.answer = "cancel"
                            answers.cancelled.append(shown.id)
                            if answers.asked?.id == shown.id {
                                answers.asked = nil
                            }
                        }
                    )
                }
        }
    }

    /// The two-lists sheet, presented as `TaskProgressView` presents it.
    struct ListsPage: View {

        // MARK: - Stored properties

        let answers: Answers

        // MARK: - Body

        var body: some View {
            @Bindable var answers = answers
            Color.white
                .sheet(isPresented: $answers.showing) {
                    PlanShareListsSheet(
                        lists: QuestionKeysTests.oneDocument(),
                        warnsBeforeSharing: false,
                        onShare: { (_: PlanShareTablesModel) in
                            answers.answer = "share"
                            answers.showing = false
                        },
                        onCancel: {
                            answers.answer = "cancel"
                            answers.showing = false
                        }
                    )
                }
        }
    }

    /// A question with its facts, as the tables' sheet presents the
    /// public-address warning and the console presents the dialog after
    /// Change Password (#833, on #834's sheet), through
    /// `.factsQuestionSheet`, as every presenter does since #973.
    struct FactsPage: View {

        // MARK: - Stored properties

        let question: FactsQuestion
        let goAheadIsTheDefault: Bool
        let answers: Answers

        // MARK: - Body

        var body: some View {
            @Bindable var answers = answers
            Color.white
                .factsQuestionSheet(isPresented: $answers.showing) {
                    FactsQuestionSheet(
                        question: question,
                        identifier: "test",
                        goAheadIsTheDefault: goAheadIsTheDefault,
                        goAhead: {
                            answers.answer = "go"
                            answers.showing = false
                        },
                        cancel: {
                            answers.answer = "cancel"
                            answers.cancelCount += 1
                            answers.showing = false
                        }
                    )
                }
        }
    }

    /// The tables' rows, one document.
    static func oneDocument() -> PlanShareLists {
        var lists: PlanShareLists = PlanShareLists()
        lists.year = 2026
        lists.documents = [
            PlanShareDocument(place: "unit-1/pdfs/Quiz 1.pdf", name: "Quiz 1.pdf", unit: "unit-1", unitOrder: 0,
                              folder: "pdfs", kind: "PDF", answerKey: nil, movable: true, start: .shared),
        ]
        lists.isComplete = true
        return lists
    }

    /// Replace It…'s question, as `ReplacePage` asks it.
    static func replaceQuestion() -> FactsQuestion {
        return FactsQuestion(
            title: "Replace EXC2O in 2025–26?",
            message: ReferenceReplaceWording.message,
            rows: ReferenceReplaceWording.rows(
                sections: "1 section", pages: "2 pages", size: "4 KB", date: "12 November 2026", folder: "EXC2O"
            ),
            action: ReferenceReplaceWording.confirmButton,
            cancel: ReferenceReplaceWording.cancelButton
        )
    }

    /// The share's console, presented as `PlanShareBar` presents it.
    struct ConsolePage: View {

        // MARK: - Stored properties

        let planRunner: PlanShareRunner

        // MARK: - Body

        var body: some View {
            Color.white
                .sheet(isPresented: Binding(
                    get: { return planRunner.isShowingSheet },
                    set: { (showing: Bool) in
                        planRunner.isShowingSheet = showing
                    }
                )) {
                    PlanShareConsoleSheet(planRunner: planRunner)
                }
        }
    }

    /// Replace It…'s warning, through its own modifier.
    struct ReplacePage: View {

        // MARK: - Stored properties

        @State var warning: ReferenceReplacer.Warning? = ReferenceReplacer.Warning(
            folderName: "EXC2O", title: "Replace EXC2O in 2025–26?",
            question: QuestionKeysTests.replaceQuestion()
        )

        let replaced: Answers

        // MARK: - Body

        var body: some View {
            Color.white
                .replaceReferenceCourseAlert($warning) { (_: String) in
                    replaced.answer = "replace"
                }
        }
    }

    // MARK: - Stored properties

    nonisolated(unsafe) private var rootURL: URL?
    nonisolated(unsafe) private var previousStore: ProblemReportStore?

    // MARK: - Functions

    override func setUp() async throws {
        previousStore = ActivityTrail.store
        let trail: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("question-keys-trail-\(UUID().uuidString)", isDirectory: true)
        ActivityTrail.store = ProblemReportStore(folderURL: trail)
    }

    override func tearDown() async throws {
        if let previousStore {
            ActivityTrail.store = previousStore
        }
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    private func runUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end: Date = Date(timeIntervalSinceNow: timeout)
        while Date() < end {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }

    /// A window off the screen holding `view`, with the question it opens
    /// attached and settled (the keys are given out after the sheet first
    /// appears: read at once, they came back empty).
    func windowShowing(_ view: some View) -> NSWindow {
        let window: NSWindow = NSWindow(
            contentRect: NSRect(x: -7000, y: -7000, width: 700, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        XCTAssertTrue(runUntil(timeout: 5) { window.attachedSheet != nil }, "the question opened")
        _ = runUntil(timeout: 0.7) { false }
        return window
    }

    func close(_ window: NSWindow) {
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Sends `key` to the window's question.
    func press(_ key: Key, in window: NSWindow) {
        guard let sheet = window.attachedSheet else {
            XCTFail("no question to press a key in")
            return
        }
        let characters: String
        let code: UInt16
        var modifiers: NSEvent.ModifierFlags = []
        switch key {
        case .escape:
            characters = "\u{1b}"
            code = 53
        case .returnKey:
            characters = "\r"
            code = 36
        case .commandPeriod:
            characters = "."
            code = 47
            modifiers = [.command]
        }
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: sheet.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        ) else {
            XCTFail("could not make the key")
            return
        }
        if !sheet.performKeyEquivalent(with: event) {
            sheet.sendEvent(event)
        }
    }

    func allViews(in view: NSView?) -> [NSView] {
        guard let view else {
            return []
        }
        var found: [NSView] = [view]
        for child in view.subviews {
            found.append(contentsOf: allViews(in: child))
        }
        return found
    }

    /// Each button in the window's alert, with the key it answers.
    func buttonKeys(in window: NSWindow) -> [String: String] {
        var keys: [String: String] = [:]
        for view in allViews(in: window.attachedSheet?.contentView) {
            if let button = view as? NSButton, !button.title.isEmpty {
                keys[button.title] = button.keyEquivalent
            }
        }
        return keys
    }

    /// The alert's keys as a teacher meets them: Cancel takes Escape, and
    /// no button takes Return. Then Return is pressed (nothing happens) and
    /// Escape (the question closes, through Cancel).
    func checkTheAlertKeys(
        in window: NSWindow, action: String, cancel: String,
        stillAsked: () -> Bool, actedOn: () -> Bool, what: String
    ) {
        let keys: [String: String] = buttonKeys(in: window)
        XCTAssertEqual(keys[cancel], "\u{1b}", "\(what): Cancel answers Escape (keys \(keys))")
        XCTAssertEqual(keys[action], "", "\(what): \(action) answers no key, so a stray Return never presses it (keys \(keys))")
        press(.returnKey, in: window)
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertTrue(stillAsked(), "\(what): Return closed the question")
        XCTAssertFalse(actedOn(), "\(what): Return pressed \(action)")
        press(.escape, in: window)
        XCTAssertTrue(runUntil(timeout: 3) { !stillAsked() }, "\(what): Escape did not close the question")
        XCTAssertFalse(actedOn(), "\(what): Escape pressed \(action)")
    }

    /// A risky facts sheet's keys as a teacher meets them (#973): Return
    /// leaves the question showing and goes ahead with nothing, and Escape
    /// closes it through Cancel without going ahead. Each key is pressed on
    /// a question opened afresh by `open`, which hands back the window,
    /// whether it is still asked, and whether it went ahead.
    ///
    /// Closing is not enough (#973): SwiftUI closes a sheet on Escape by
    /// itself, through its binding, without running `cancel`, and the real
    /// presenters' `cancel` clears the same state the binding does, so they
    /// cannot tell the two apart. So each key is pressed again on the same
    /// `question` in `FactsPage`, whose closures write their answer: Escape
    /// must answer `cancel`, and Return must answer nothing.
    func checkReturnDoesNothingAndEscapeCancels(
        what: String,
        question: FactsQuestion,
        open: () throws -> (window: NSWindow, stillAsked: () -> Bool, wentAhead: () -> Bool)
    ) rethrows {
        let afterReturn: (window: NSWindow, stillAsked: () -> Bool, wentAhead: () -> Bool) = try open()
        XCTAssertTrue(afterReturn.stillAsked(), "\(what): the question was not asked")
        press(.returnKey, in: afterReturn.window)
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertTrue(afterReturn.stillAsked(), "\(what): Return closed the question")
        XCTAssertFalse(afterReturn.wentAhead(), "\(what): Return went ahead")
        close(afterReturn.window)

        let afterEscape: (window: NSWindow, stillAsked: () -> Bool, wentAhead: () -> Bool) = try open()
        XCTAssertTrue(afterEscape.stillAsked(), "\(what): the question was not asked")
        press(.escape, in: afterEscape.window)
        XCTAssertTrue(runUntil(timeout: 3) { !afterEscape.stillAsked() }, "\(what): Escape did not close the question")
        _ = runUntil(timeout: 0.3) { false }
        XCTAssertFalse(afterEscape.wentAhead(), "\(what): Escape went ahead instead of cancelling")
        close(afterEscape.window)

        checkTheAnswer(to: question, goAheadIsTheDefault: false, key: Key.escape, is: "cancel", what: what)
        checkReturnAnswersNothing(to: question, what: what)
    }

    /// Presses Return on a risky `question` in `FactsPage`: the sheet must
    /// still be showing and neither closure may have answered (#973).
    func checkReturnAnswersNothing(to question: FactsQuestion, what: String) {
        let answers: Answers = Answers()
        let page: FactsPage = FactsPage(question: question, goAheadIsTheDefault: false, answers: answers)
        let window: NSWindow = windowShowing(page)
        press(.returnKey, in: window)
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertTrue(answers.showing, "\(what): Return closed the sheet")
        XCTAssertEqual(answers.answer, "", "\(what): Return answered the question")
        close(window)
    }

    /// Presses `key` on `question` in `FactsPage` and checks which of the
    /// sheet's closures answered: `go`, `cancel`, or nothing ("") when the
    /// sheet was closed around them (#973).
    func checkTheAnswer(
        to question: FactsQuestion, goAheadIsTheDefault: Bool, key: Key, is expected: String, what: String
    ) {
        let answers: Answers = Answers()
        let page: FactsPage = FactsPage(question: question, goAheadIsTheDefault: goAheadIsTheDefault, answers: answers)
        let window: NSWindow = windowShowing(page)
        press(key, in: window)
        XCTAssertTrue(runUntil(timeout: 3) { !answers.showing }, "\(what): \(key) did not answer the question")
        XCTAssertEqual(answers.answer, expected, "\(what): \(key)")
        close(window)
    }

    /// The trail as it stands, so a test can tell whether going ahead wrote
    /// its line.
    var trailNow: String {
        return ActivityTrail.store.activityText(includingPrompts: false)
    }

    // MARK: - Tests

    func testReturnDoesNothingAndEscapeIsCancelOnTheRemoveGroupQuestion() throws {
        let root: URL = try FixtureWorkspace.materialize()
        rootURL = root
        let question: FactsQuestion = ReferenceGroupWording.removeGroupQuestion(group: "Electives", courseCount: 0)
        try checkReturnDoesNothingAndEscapeCancels(what: "Remove Group", question: question) {
            let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
            workspace.workspaceURL = root
            workspace.removeGroupRequest = ReferenceShelfGroup(
                group: ReferenceShelf.Group(place: .made("g-0000a001"), title: "Electives", folderNames: []),
                courses: []
            )
            let before: String = trailNow
            let window: NSWindow = windowShowing(Color.white.modifier(ReferenceGroupPresenter()).environment(workspace))
            return (window: window,
                    stillAsked: { return workspace.removeGroupRequest != nil },
                    wentAhead: { return self.trailNow != before || workspace.referenceGroupProblem != nil })
        }
    }

    func testReturnDoesNothingAndEscapeIsCancelOnStartTheGroupsAgain() throws {
        let root: URL = try FixtureWorkspace.materialize()
        rootURL = root
        try checkReturnDoesNothingAndEscapeCancels(what: "Start the Groups Again", question: ReferenceGroupWording.startAgainQuestion) {
            let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
            workspace.workspaceURL = root
            workspace.isAskingToStartReferenceGroupsAgain = true
            let before: String = trailNow
            let window: NSWindow = windowShowing(Color.white.modifier(ReferenceGroupPresenter()).environment(workspace))
            return (window: window,
                    stillAsked: { return workspace.isAskingToStartReferenceGroupsAgain },
                    wentAhead: { return self.trailNow != before || workspace.referenceGroupProblem != nil })
        }
    }

    func testReturnDoesNothingAndEscapeIsCancelOnTheReplaceWarning() {
        checkReturnDoesNothingAndEscapeCancels(what: "Replace It…", question: QuestionKeysTests.replaceQuestion()) {
            let replaced: Answers = Answers()
            let page: ReplacePage = ReplacePage(replaced: replaced)
            let window: NSWindow = windowShowing(page)
            return (window: window,
                    stillAsked: { return window.attachedSheet != nil },
                    wentAhead: { return replaced.answer == "replace" })
        }
    }

    /// The facts sheet itself, measured on the buttons AppKit draws for it
    /// (#973): on a risky question the action carries no key and Cancel
    /// carries Escape alone, so no button is the default; after Change
    /// Password, Share Again carries Return and Later carries Escape.
    func testEachButtonCarriesAtMostOneKey() {
        let replaced: Answers = Answers()
        let window: NSWindow = windowShowing(ReplacePage(replaced: replaced))
        let keys: [String: String] = buttonKeys(in: window)
        close(window)
        if let action = keys[ReferenceReplaceWording.confirmButton] {
            XCTAssertEqual(action, "", "Replace answers a key (\(keys))")
        }
        if let cancel = keys[ReferenceReplaceWording.cancelButton] {
            XCTAssertEqual(cancel, "\u{1b}", "Cancel is not Escape alone (\(keys))")
        }
        for (title, key) in keys {
            XCTAssertNotEqual(key, "\r", "\(title) is a default button on a risky question (\(keys))")
        }

        let answers: Answers = Answers()
        let page: FactsPage = FactsPage(
            question: PlanSharing.newPasswordQuestion(earlierYearShared: false),
            goAheadIsTheDefault: true,
            answers: answers
        )
        let passwordWindow: NSWindow = windowShowing(page)
        let passwordKeys: [String: String] = buttonKeys(in: passwordWindow)
        close(passwordWindow)
        if let shareAgain = passwordKeys[PlanSharingWording.shareAgain] {
            XCTAssertEqual(shareAgain, "\r", "Share Again is not the default (\(passwordKeys))")
        }
        if let later = passwordKeys[PlanSharingWording.later] {
            XCTAssertEqual(later, "\u{1b}", "Later is not Escape (\(passwordKeys))")
        }
    }

    /// Command-Period is the other standard way to cancel (Alerts, Human
    /// Interface Guidelines). Measured, not assumed (#973): pressed on both
    /// layouts, it must run `cancel`.
    func testCommandPeriodIsCancelInBothLayouts() {
        let risky: FactsQuestion = QuestionKeysTests.replaceQuestion()
        checkTheAnswer(to: risky, goAheadIsTheDefault: false, key: Key.commandPeriod, is: "cancel", what: "Replace It…")
        let ordinary: FactsQuestion = PlanSharing.newPasswordQuestion(earlierYearShared: true)
        checkTheAnswer(to: ordinary, goAheadIsTheDefault: true, key: Key.commandPeriod, is: "cancel", what: "after Change Password")
    }

    /// A question that goes away without an answer has been cancelled, by
    /// whatever route it went away (#973, Russell 2026-11-16), and `cancel`
    /// runs exactly once: closed by its presenter with nothing pressed, by
    /// Command-Period, and by Escape (where Cancel itself answers first and
    /// the sheet's closing must not answer again), in both layouts.
    func testASheetClosedWithNoAnswerIsCancelledOnce() {
        let questions: [(question: FactsQuestion, goAheadIsTheDefault: Bool, what: String)] = [
            (question: QuestionKeysTests.replaceQuestion(), goAheadIsTheDefault: false, what: "Replace It…"),
            (question: PlanSharing.newPasswordQuestion(earlierYearShared: true), goAheadIsTheDefault: true, what: "after Change Password"),
        ]
        for asked in questions {
            for route in ["closed by its presenter", "Command-Period", "Escape"] {
                let answers: Answers = Answers()
                let page: FactsPage = FactsPage(question: asked.question, goAheadIsTheDefault: asked.goAheadIsTheDefault, answers: answers)
                let window: NSWindow = windowShowing(page)
                if route == "Command-Period" {
                    press(.commandPeriod, in: window)
                } else if route == "Escape" {
                    press(.escape, in: window)
                } else {
                    answers.showing = false
                }
                XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "\(asked.what), \(route): the sheet did not go away")
                // Long enough for the sheet's own dismissal to have finished
                // and reported, so a second `cancel` would be counted.
                _ = runUntil(timeout: 0.5) { false }
                XCTAssertEqual(answers.answer, "cancel", "\(asked.what), \(route): closing with no answer is not Cancel")
                XCTAssertEqual(answers.cancelCount, 1, "\(asked.what), \(route): cancel ran \(answers.cancelCount) times")
                close(window)
            }
        }
    }

    /// A question that was answered records nothing more when its sheet
    /// goes away (#973): after Change Password, Return is Share Again, the
    /// sheet closes, and `cancel` never runs. (A risky question's action
    /// carries no key, and SwiftUI draws its buttons without an `NSButton`
    /// to press, so going ahead is pressed here where it has a key.)
    func testAnAnsweredSheetRecordsNothingMoreWhenItCloses() {
        let ordinary: FactsQuestion = PlanSharing.newPasswordQuestion(earlierYearShared: true)
        let ordinaryAnswers: Answers = Answers()
        let ordinaryWindow: NSWindow = windowShowing(FactsPage(question: ordinary, goAheadIsTheDefault: true, answers: ordinaryAnswers))
        press(.returnKey, in: ordinaryWindow)
        XCTAssertTrue(runUntil(timeout: 3) { ordinaryWindow.attachedSheet == nil }, "after Change Password: Return did not close the sheet")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(ordinaryAnswers.answer, "go", "after Change Password: Return was not Share Again")
        XCTAssertEqual(ordinaryAnswers.cancelCount, 0, "after Change Password: the sheet closing after Share Again ran cancel")
        close(ordinaryWindow)
    }

    /// The same rule through `.factsQuestionSheet(item:)`, the presenter
    /// Replace It… uses (#973 review): closed with no answer, by its
    /// presenter, Command-Period or Escape, the question's `cancel` runs
    /// exactly once, for that item, in both layouts.
    func testAnItemQuestionClosedWithNoAnswerIsCancelledOnce() {
        let layouts: [(question: FactsQuestion, goAheadIsTheDefault: Bool, what: String)] = [
            (question: QuestionKeysTests.replaceQuestion(), goAheadIsTheDefault: false, what: "Replace It…"),
            (question: PlanSharing.newPasswordQuestion(earlierYearShared: true), goAheadIsTheDefault: true, what: "after Change Password"),
        ]
        for layout in layouts {
            for route in ["closed by its presenter", "Command-Period", "Escape"] {
                let answers: Answers = Answers()
                answers.asked = Asked(id: "A", question: layout.question, goAheadIsTheDefault: layout.goAheadIsTheDefault)
                let window: NSWindow = windowShowing(ItemPage(answers: answers))
                if route == "Command-Period" {
                    press(.commandPeriod, in: window)
                } else if route == "Escape" {
                    press(.escape, in: window)
                } else {
                    answers.asked = nil
                }
                XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "\(layout.what), \(route): the sheet did not go away")
                _ = runUntil(timeout: 0.5) { false }
                XCTAssertEqual(answers.cancelled, ["A"], "\(layout.what), \(route): cancel ran for \(answers.cancelled)")
                XCTAssertNil(answers.asked, "\(layout.what), \(route): the question is still asked")
                close(window)
            }
        }
    }

    /// An item question that was answered records nothing more when its
    /// sheet goes away (#973 review): Return is Share Again after Change
    /// Password, and `cancel` never runs.
    func testAnAnsweredItemQuestionRecordsNothingMoreWhenItCloses() {
        let answers: Answers = Answers()
        answers.asked = Asked(id: "A", question: PlanSharing.newPasswordQuestion(earlierYearShared: true), goAheadIsTheDefault: true)
        let window: NSWindow = windowShowing(ItemPage(answers: answers))
        press(.returnKey, in: window)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "Return did not close the sheet")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(answers.answer, "go", "Return was not Share Again")
        XCTAssertEqual(answers.cancelled, [], "the sheet closing after Share Again ran cancel")
        close(window)
    }

    /// When the item changes from A to B while A's question is open, A's
    /// dismissal cancels A, the question that was showing, and B stays
    /// asked (#973 review: the presenter once remembered only the newest
    /// item, so A's dismissal cancelled B). Then B, closed unanswered, is
    /// cancelled once as itself.
    func testChangingTheItemCancelsOnlyTheQuestionThatWasShowing() {
        let question: FactsQuestion = QuestionKeysTests.replaceQuestion()
        let answers: Answers = Answers()
        answers.asked = Asked(id: "A", question: question, goAheadIsTheDefault: false)
        let window: NSWindow = windowShowing(ItemPage(answers: answers))
        answers.asked = Asked(id: "B", question: question, goAheadIsTheDefault: false)
        XCTAssertTrue(runUntil(timeout: 3) { answers.cancelled == ["A"] }, "A's dismissal did not cancel A (cancelled \(answers.cancelled))")
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet != nil }, "B's question is not showing")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(answers.cancelled, ["A"], "A's dismissal cancelled \(answers.cancelled)")
        XCTAssertEqual(answers.asked?.id, "B", "B is no longer asked")
        XCTAssertNotNil(window.attachedSheet, "B's question closed with A's")
        answers.asked = nil
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "B's sheet did not go away")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(answers.cancelled, ["A", "B"], "closing B with no answer: cancel ran for \(answers.cancelled)")
        close(window)
    }

    /// The system closing a sheet answers Cancel BEFORE the presenter's
    /// state reads closed (#973 review). `cancelOperation` on the sheet's
    /// window is the route Command-Period took on the second Mac, measured:
    /// SwiftUI sets the presentation's binding to false and runs no button.
    /// The binding route answers at that moment; `onDismiss` alone would
    /// answer only after the presenter's state already read closed with no
    /// answer (measured with the setter's `cancel` taken out: the answer
    /// read at closing was ""). Checked for both presenters.
    func testTheSystemClosingASheetAnswersCancelBeforeThePresenterSeesItClosed() {
        let question: FactsQuestion = QuestionKeysTests.replaceQuestion()

        let answers: Answers = Answers()
        let window: NSWindow = windowShowing(FactsPage(question: question, goAheadIsTheDefault: false, answers: answers))
        window.attachedSheet?.cancelOperation(nil)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "isPresented: the system did not close the sheet")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(answers.answerWhenClosed, "cancel", "isPresented: the presenter saw the question closed before it was answered")
        XCTAssertEqual(answers.cancelCount, 1, "isPresented: cancel ran \(answers.cancelCount) times")
        close(window)

        let itemAnswers: Answers = Answers()
        itemAnswers.asked = Asked(id: "A", question: question, goAheadIsTheDefault: false)
        let itemWindow: NSWindow = windowShowing(ItemPage(answers: itemAnswers))
        itemWindow.attachedSheet?.cancelOperation(nil)
        XCTAssertTrue(runUntil(timeout: 3) { itemWindow.attachedSheet == nil }, "item: the system did not close the sheet")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(itemAnswers.answerWhenClosed, "cancel", "item: the presenter saw the question closed before it was answered")
        XCTAssertEqual(itemAnswers.cancelled, ["A"], "item: cancel ran for \(itemAnswers.cancelled)")
        close(itemWindow)
    }

    /// A question asked again after it was answered is a new question
    /// (#973 review): its Cancel runs again, once. Checked for both
    /// presenters, since each keeps its "answered" fact per showing.
    func testAQuestionAskedAgainCanBeCancelledAgain() {
        let question: FactsQuestion = QuestionKeysTests.replaceQuestion()

        let answers: Answers = Answers()
        let window: NSWindow = windowShowing(FactsPage(question: question, goAheadIsTheDefault: false, answers: answers))
        press(.escape, in: window)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "isPresented: the first Escape did not close the question")
        _ = runUntil(timeout: 0.5) { false }
        answers.showing = true
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet != nil }, "isPresented: the question was not asked again")
        _ = runUntil(timeout: 0.7) { false }
        press(.escape, in: window)
        XCTAssertTrue(runUntil(timeout: 3) { window.attachedSheet == nil }, "isPresented: the second Escape did not close the question")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(answers.cancelCount, 2, "isPresented: cancel ran \(answers.cancelCount) times for two showings")
        close(window)

        let itemAnswers: Answers = Answers()
        itemAnswers.asked = Asked(id: "A", question: question, goAheadIsTheDefault: false)
        let itemWindow: NSWindow = windowShowing(ItemPage(answers: itemAnswers))
        press(.escape, in: itemWindow)
        XCTAssertTrue(runUntil(timeout: 3) { itemWindow.attachedSheet == nil }, "item: the first Escape did not close the question")
        _ = runUntil(timeout: 0.5) { false }
        itemAnswers.asked = Asked(id: "A", question: question, goAheadIsTheDefault: false)
        XCTAssertTrue(runUntil(timeout: 3) { itemWindow.attachedSheet != nil }, "item: the question was not asked again")
        _ = runUntil(timeout: 0.7) { false }
        press(.escape, in: itemWindow)
        XCTAssertTrue(runUntil(timeout: 3) { itemWindow.attachedSheet == nil }, "item: the second Escape did not close the question")
        _ = runUntil(timeout: 0.5) { false }
        XCTAssertEqual(itemAnswers.cancelled, ["A", "A"], "item: cancel ran for \(itemAnswers.cancelled) over two showings")
        close(itemWindow)
    }

    /// Every question with its facts is presented through
    /// `.factsQuestionSheet`, which makes closing without an answer Cancel
    /// (#973); a bare `.sheet` around one would lose that silently.
    func testEveryQuestionIsPresentedSoThatClosingIsCancel() throws {
        let app: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers")
        let sheetItself: String = app.appendingPathComponent("Views/Helpers/FactsQuestionSheet.swift").path
        var questionsFound: Int = 0
        var presentedSo: Int = 0
        let walker: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)
        while let file = walker?.nextObject() as? URL {
            if file.pathExtension != "swift" || file.path == sheetItself {
                continue
            }
            let text: String = try String(contentsOf: file, encoding: .utf8)
            questionsFound += text.components(separatedBy: "FactsQuestionSheet(").count - 1
            presentedSo += text.components(separatedBy: ".factsQuestionSheet(").count - 1
        }
        XCTAssertEqual(questionsFound, 5, "the five questions: Remove Group, Start the Groups Again, Replace It…, the public-address warning, after Change Password")
        XCTAssertEqual(presentedSo, questionsFound, "a question is presented with a bare .sheet")
    }

    /// The public-address warning: Share Without a Password used to take
    /// Return (the note in #832). Since #833 it comes after the two tables,
    /// on #834's sheet, and since #973 Return answers nothing there and
    /// Escape is Cancel.
    func testReturnDoesNothingAndEscapeIsCancelOnThePublicAddressWarning() {
        let question: FactsQuestion = PlanSharing.warningQuestion(shared: 3, heldBack: 1, keysInShared: 1)
        checkReturnDoesNothingAndEscapeCancels(what: "the public-address warning", question: question) {
            let answers: Answers = Answers()
            let page: FactsPage = FactsPage(
                question: question,
                goAheadIsTheDefault: false,
                answers: answers
            )
            let window: NSWindow = windowShowing(page)
            return (window: window,
                    stillAsked: { return window.attachedSheet != nil },
                    wentAhead: { return answers.answer == "go" })
        }
    }

    /// After Change Password (#833): Share Again is the default, Russell's
    /// choice, and Escape is Later.
    func testReturnIsShareAgainAndEscapeIsLaterAfterChangePassword() {
        let question: FactsQuestion = PlanSharing.newPasswordQuestion(earlierYearShared: true)
        checkTheAnswer(to: question, goAheadIsTheDefault: true, key: Key.returnKey, is: "go", what: "after Change Password")
        checkTheAnswer(to: question, goAheadIsTheDefault: true, key: Key.escape, is: "cancel", what: "after Change Password")
    }

    func testTheTwoListsSheetTakesReturnAndEscapeAsCancel() {
        for key in [Key.returnKey, Key.escape] {
            let answers: Answers = Answers()
            let window: NSWindow = windowShowing(ListsPage(answers: answers))
            press(key, in: window)
            XCTAssertTrue(runUntil(timeout: 3) { !answers.showing }, "\(key) did not close the two-lists sheet")
            XCTAssertEqual(answers.answer, "cancel", "\(key) on the two-lists sheet is Cancel")
            close(window)
        }
    }

    /// Already true before #832; kept so a Cancel added to the console
    /// later cannot take Escape away unnoticed.
    func testReturnAndEscapeCloseTheFinishedShareConsole() {
        for key in [Key.returnKey, Key.escape] {
            let planRunner: PlanShareRunner = PlanShareRunner()
            planRunner.isShowingSheet = true
            let window: NSWindow = windowShowing(ConsolePage(planRunner: planRunner))
            press(key, in: window)
            XCTAssertTrue(runUntil(timeout: 3) { !planRunner.isShowingSheet }, "\(key) did not close the finished share's console")
            close(window)
        }
    }
}
