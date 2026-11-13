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
/// `FactsQuestionSheet`s, where Cancel answers BOTH keys (`.defaultButton`
/// for Return, the sheet's `.onExitCommand` for Escape) and the action takes
/// none, as Russell first asked; only the public-address warning is still an
/// alert, with Escape alone.
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
    }

    /// A sheet's two possible answers, written by the sheet's closures.
    @Observable
    final class Answers {

        // MARK: - Stored properties

        var showing: Bool = true
        var answer: String = ""
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
                        lists: PlanShareLists(shared: ["index.html"], leftOut: ["unit-1/answers.html"]),
                        onShare: {
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
            question: FactsQuestion(
                title: "Replace EXC2O in 2025–26?",
                message: ReferenceReplaceWording.message,
                rows: ReferenceReplaceWording.rows(
                    sections: "1 section", pages: "2 pages", size: "4 KB", date: "12 November 2026", folder: "EXC2O"
                ),
                action: ReferenceReplaceWording.confirmButton,
                cancel: ReferenceReplaceWording.cancelButton
            )
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
        switch key {
        case .escape:
            characters = "\u{1b}"
            code = 53
        case .returnKey:
            characters = "\r"
            code = 36
        }
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
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

    /// A facts sheet's keys as a teacher meets them (#834): Return and
    /// Escape each close it through Cancel, and neither goes ahead. Each key
    /// is pressed on a question opened afresh by `open`, which hands back
    /// the window, whether it is still asked, and whether it went ahead.
    func checkCancelAnswersBothKeys(
        what: String,
        open: () throws -> (window: NSWindow, stillAsked: () -> Bool, wentAhead: () -> Bool)
    ) rethrows {
        for key in [Key.returnKey, Key.escape] {
            let shown: (window: NSWindow, stillAsked: () -> Bool, wentAhead: () -> Bool) = try open()
            XCTAssertTrue(shown.stillAsked(), "\(what): the question was not asked")
            press(key, in: shown.window)
            XCTAssertTrue(runUntil(timeout: 3) { !shown.stillAsked() }, "\(what): \(key) did not close the question")
            _ = runUntil(timeout: 0.3) { false }
            XCTAssertFalse(shown.wentAhead(), "\(what): \(key) went ahead instead of cancelling")
            close(shown.window)
        }
    }

    /// The trail as it stands, so a test can tell whether going ahead wrote
    /// its line.
    var trailNow: String {
        return ActivityTrail.store.activityText(includingPrompts: false)
    }

    // MARK: - Tests

    func testReturnAndEscapeAreCancelOnTheRemoveGroupQuestion() throws {
        let root: URL = try FixtureWorkspace.materialize()
        rootURL = root
        try checkCancelAnswersBothKeys(what: "Remove Group") {
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

    func testReturnAndEscapeAreCancelOnStartTheGroupsAgain() throws {
        let root: URL = try FixtureWorkspace.materialize()
        rootURL = root
        try checkCancelAnswersBothKeys(what: "Start the Groups Again") {
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

    func testReturnAndEscapeAreCancelOnTheReplaceWarning() {
        checkCancelAnswersBothKeys(what: "Replace It…") {
            let replaced: Answers = Answers()
            let page: ReplacePage = ReplacePage(replaced: replaced)
            let window: NSWindow = windowShowing(page)
            return (window: window,
                    stillAsked: { return window.attachedSheet != nil },
                    wentAhead: { return replaced.answer == "replace" })
        }
    }

    /// The facts sheet itself: its action button carries no key, and Cancel
    /// is the default, measured on the buttons AppKit draws for it.
    func testTheFactsSheetsActionTakesNoKey() {
        let replaced: Answers = Answers()
        let window: NSWindow = windowShowing(ReplacePage(replaced: replaced))
        defer {
            close(window)
        }
        let keys: [String: String] = buttonKeys(in: window)
        if let action = keys[ReferenceReplaceWording.confirmButton] {
            XCTAssertEqual(action, "", "Replace answers a key (\(keys))")
        }
        if let cancel = keys[ReferenceReplaceWording.cancelButton] {
            XCTAssertEqual(cancel, "\r", "Cancel is not the default (\(keys))")
        }
    }

    /// The public-address warning: Share Without a Password used to take
    /// Return (the note in #832).
    func testThePublicAddressWarningSharesNothingOnReturn() throws {
        let root: URL = try FixtureWorkspace.materialize()
        rootURL = root
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: root.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        let bar: PlanShareBar = PlanShareBar(course: course, folder: root, choiceAwaitingTheWarning: .shareOpen)
        let window: NSWindow = windowShowing(bar.frame(width: 640, height: 200))
        defer {
            close(window)
        }
        checkTheAlertKeys(
            in: window, action: PlanSharingWording.shareAnyway, cancel: "Cancel",
            stillAsked: { return window.attachedSheet != nil },
            // A share that started would open its console sheet in place
            // of the warning, and leave its marker in the course.
            actedOn: { return !PlanSharing.markers(courseDirectory: course.directoryURL).isEmpty },
            what: "the public-address warning"
        )
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
