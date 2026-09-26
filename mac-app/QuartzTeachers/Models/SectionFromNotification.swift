import AppKit
import Foundation

/// Opens the section a clicked scheduled-publish notification names (#306).
///
/// The rule is data: `contracts/shared-rules.json` →
/// `scheduledPublishStopped.notification.onClick`, played against `decide`
/// and then through the router below. In one sentence: show THAT section, in
/// a window already on its working folder if there is one (the one nearest
/// the front), else in a window still choosing a folder, else in a NEW
/// window — and never point a window that is on another working folder
/// somewhere else.
///
/// **Decided at an event, never after a delay.** A click can launch Plantoir,
/// and a launching window takes its folder a moment after it appears
/// (`WindowStartRule`, `WindowRootView.attemptClaim`). Deciding before then
/// would put the section's folder into a window about to be given another. So
/// a click that arrives while any window is still deciding — or before the
/// first window exists — is PARKED, and decided again each time a window's
/// folder becomes final: `WindowSettling.windowSettled`, #311's one decision
/// per window. A window opened for the click is told its folder BEFORE it
/// decides (`WorkspaceModel.folderForNextNewWindow`), so it never shows the
/// key window's folder first, and never claims a remembered one.
///
/// Every outcome leaves one line on the trail
/// (`ActivityTrail.Event.scheduledPublishNotification`), so "I clicked it and
/// nothing happened" can be told apart from a folder gone, a window busy, or
/// a section gone. Never the path.
@MainActor
enum SectionFromNotification {

    // MARK: - Types

    /// How one open window stands to the notification's working folder.
    enum FolderRelation: Equatable, Sendable {
        /// On the notification's working folder.
        case this
        /// On another working folder.
        case other
        /// Choosing a folder (the picker), or not decided yet.
        case none
    }

    /// One window, as `decide` sees it.
    struct WindowState: Equatable, Sendable {

        // MARK: - Stored properties

        var folder: FolderRelation
        /// False while the window is still finding its folder at launch.
        var hasSettled: Bool
        /// A dialog in front of it, or a course being renamed in place.
        var isBusy: Bool
    }

    /// Why a click only brought a window, or the app, forward.
    enum Reason: Equatable, Sendable {
        case namesNothing
        case folderGone
        case busy
    }

    /// What a click does. `Int` is an index into the windows, front to back.
    enum Decision: Equatable, Sendable {
        /// Wait until every window has decided its folder.
        case wait
        /// Bring this window (or, with none, the app) forward; select nothing.
        case bringForwardOnly(Reason, window: Int?)
        /// Use this window on the folder, selecting the section when it is there.
        case useWindow(Int, selects: Bool)
        /// This window is choosing a folder: it takes the notification's.
        case adoptInto(Int)
        /// Open a new window on the notification's folder.
        case openNewWindow
    }

    /// The line each outcome leaves on the trail — the contract's `trailSays`.
    enum Outcome: Equatable, Sendable {
        case shown
        case shownInNewWindow
        case shownInChooser
        case busy
        case sectionGone
        case folderGone
        case namesNothing

        // MARK: - Computed properties

        var line: String {
            switch self {
            case .shown:
                return "opened the section from its scheduled publish notification"
            case .shownInNewWindow:
                return "opened the section from its scheduled publish notification, in a new window"
            case .shownInChooser:
                return "opened the section from its scheduled publish notification, "
                    + "in the window that was choosing a working folder"
            case .busy:
                return "brought the working folder's window forward from a scheduled publish notification, "
                    + "and left it as it was because it was in the middle of something"
            case .sectionGone:
                return "showed the working folder from a scheduled publish notification; "
                    + "that section is no longer in it"
            case .folderGone:
                return "a scheduled publish notification was clicked, but its working folder is no longer "
                    + "where it was, so Plantoir was only brought forward"
            case .namesNothing:
                return "a scheduled publish notification was clicked, but it did not say which section it was about"
            }
        }
    }

    // MARK: - Stored properties

    /// The click still being answered: parked until the windows settle, or
    /// waiting for the window opened for it. Nil once answered or dropped.
    static private(set) var request: NotificationClickTarget?

    /// True once a window has been opened for `request` and not yet settled.
    static private(set) var isWaitingForNewWindow: Bool = false

    /// False until the first window of this launch has decided its folder.
    /// A click that launches Plantoir can arrive before any window exists,
    /// and "no windows yet" is not "no windows open" (review H2).
    static private(set) var hasSeenAWindowSettle: Bool = false

    /// Opens a new main window. Installed by every `WindowRootView`.
    static var openMainWindow: (@MainActor () -> Void)?

    /// The open windows' models, front to back. A seam for the tests: the
    /// hosted suite's own window is always open.
    static var windowsFrontToBack: @MainActor () -> [WorkspaceModel] = SectionFromNotification.defaultWindowsFrontToBack

    /// Whether a folder is there to be worked in. A seam for the tests.
    static var folderExists: @MainActor (String) -> Bool = SectionFromNotification.defaultFolderExists

    /// Whether a dialog is in front of the model's window. A seam for the tests.
    static var sheetIsUp: @MainActor (WorkspaceModel) -> Bool = SectionFromNotification.defaultSheetIsUp

    /// Brings a window (or, given nil, the app) to the front. A seam for the
    /// tests, which must never activate the app hosting them.
    static var bringForward: @MainActor (WorkspaceModel?) -> Void = SectionFromNotification.defaultBringForward

    // MARK: - Functions

    /// What a click does, given the windows front to back. Pure — the
    /// contract's cases are played against it.
    ///
    /// - `isLaunching`: no window of this launch has decided its folder yet.
    /// - `sectionInFolder`: the section is in the notification's folder. Only
    ///   decides whether a window already on the folder selects it; a window
    ///   that takes the folder checks again once it has read its courses.
    static func decide(
        target: NotificationClickTarget?,
        windows: [WindowState],
        isLaunching: Bool,
        folderExists: Bool,
        sectionInFolder: Bool
    ) -> Decision {
        if target == nil {
            return .bringForwardOnly(.namesNothing, window: nil)
        }
        if !folderExists {
            return .bringForwardOnly(.folderGone, window: nil)
        }
        if isLaunching {
            return .wait
        }
        for window in windows {
            if !window.hasSettled {
                return .wait
            }
        }
        var firstBusyWindowOnTheFolder: Int?
        var index: Int = 0
        while index < windows.count {
            let window: WindowState = windows[index]
            if window.folder == .this {
                if !window.isBusy {
                    return .useWindow(index, selects: sectionInFolder)
                }
                if firstBusyWindowOnTheFolder == nil {
                    firstBusyWindowOnTheFolder = index
                }
            }
            index += 1
        }
        if let firstBusyWindowOnTheFolder {
            return .bringForwardOnly(.busy, window: firstBusyWindowOnTheFolder)
        }
        index = 0
        while index < windows.count {
            let window: WindowState = windows[index]
            if window.folder == .none && !window.isBusy {
                return .adoptInto(index)
            }
            index += 1
        }
        return .openNewWindow
    }

    /// A click arrived (from `AppDelegate`). Nil when the notification names
    /// no section. A newer click replaces one still waiting.
    static func receive(_ target: NotificationClickTarget?) {
        finishRequest()
        guard let target else {
            bringForward(nil)
            ActivityTrail.note(.scheduledPublishNotification, Outcome.namesNothing.line)
            return
        }
        request = target
        decideNow()
    }

    /// A window's folder is final (`WindowSettling.windowSettled`, once per
    /// window). Answers a parked click, or the one this window was opened for.
    static func windowSettled(_ model: WorkspaceModel) {
        hasSeenAWindowSettle = true
        guard let target = request else {
            return
        }
        if !isWaitingForNewWindow {
            decideNow()
            return
        }
        var isOnTheFolder: Bool = false
        if let path = model.workspaceURL?.path {
            isOnTheFolder = FolderIdentity.isSameFolder(path, target.workingFolderPath)
        }
        if isOnTheFolder {
            let selects: Bool = sectionIsInFolder(model, course: target.course, section: target.section)
            if selects {
                select(target, in: model)
            }
            bringForward(model)
            note(selects ? .shownInNewWindow : .sectionGone, for: target)
            finishRequest()
            return
        }
        // The folder was taken, and the window that took it did not end on
        // it (the folder went between the click and the window): the click
        // is over. A window that settled without taking it (a sibling
        // restored at launch) changes nothing; the new one is still coming.
        if WorkspaceModel.folderForNextNewWindow == nil {
            bringForward(model)
            note(.folderGone, for: target)
            finishRequest()
        }
    }

    /// The app went to the background with a click still waiting: drop it,
    /// and the folder it set aside for a new window, so a window the teacher
    /// opens an hour later is not captured by a stale click (review H1).
    static func forgetPendingRequest() {
        if request == nil {
            return
        }
        finishRequest()
    }

    /// True when the model's folder holds that course with that section.
    static func sectionIsInFolder(_ model: WorkspaceModel, course: String, section: Int) -> Bool {
        for candidate in model.courses {
            if candidate.code != course {
                continue
            }
            for number in candidate.sectionNumbers {
                if number == section {
                    return true
                }
            }
        }
        return false
    }

    /// Puts everything back as a fresh launch has it. Tests only.
    static func resetForTests() {
        request = nil
        isWaitingForNewWindow = false
        hasSeenAWindowSettle = false
        openMainWindow = nil
        windowsFrontToBack = SectionFromNotification.defaultWindowsFrontToBack
        folderExists = SectionFromNotification.defaultFolderExists
        sheetIsUp = SectionFromNotification.defaultSheetIsUp
        bringForward = SectionFromNotification.defaultBringForward
    }

    /// Decide the waiting click against the windows as they are now, and act.
    private static func decideNow() {
        guard let target = request, !isWaitingForNewWindow else {
            return
        }
        let models: [WorkspaceModel] = windowsFrontToBack()
        var states: [WindowState] = []
        var sectionInFolder: Bool = true
        var hasCheckedTheSection: Bool = false
        for model in models {
            let state: WindowState = windowState(of: model, for: target)
            states.append(state)
            if state.folder == .this && state.hasSettled && !hasCheckedTheSection {
                sectionInFolder = sectionIsInFolder(model, course: target.course, section: target.section)
                hasCheckedTheSection = true
            }
        }
        let decision: Decision = decide(
            target: target,
            windows: states,
            isLaunching: !hasSeenAWindowSettle,
            folderExists: folderExists(target.workingFolderPath),
            sectionInFolder: sectionInFolder
        )
        switch decision {
        case .wait:
            return
        case .bringForwardOnly(let reason, let window):
            var model: WorkspaceModel?
            if let window {
                model = models[window]
            }
            bringForward(model)
            switch reason {
            case .busy:
                note(.busy, for: target)
            case .folderGone:
                note(.folderGone, for: target)
            case .namesNothing:
                ActivityTrail.note(.scheduledPublishNotification, Outcome.namesNothing.line)
            }
            finishRequest()
        case .useWindow(let window, let selects):
            let model: WorkspaceModel = models[window]
            if selects {
                select(target, in: model)
            }
            bringForward(model)
            note(selects ? .shown : .sectionGone, for: target)
            finishRequest()
        case .adoptInto(let window):
            let model: WorkspaceModel = models[window]
            // Through #311's one route for a window taking a folder it did
            // not choose in the picker, so a folder in the Trash or out of
            // the builder's reach is said the way a remembered one is.
            let opened: Bool = model.reopen(
                RememberedFolder(path: target.workingFolderPath, bookmark: nil),
                occasion: .scheduledPublishNotification
            )
            bringForward(model)
            if !opened {
                note(.folderGone, for: target)
            } else if sectionIsInFolder(model, course: target.course, section: target.section) {
                select(target, in: model)
                note(.shownInChooser, for: target)
            } else {
                note(.sectionGone, for: target)
            }
            finishRequest()
        case .openNewWindow:
            guard let openMainWindow else {
                // No window has ever installed the opener. Left parked: the
                // next window to appear takes it, or the app going to the
                // background drops it.
                return
            }
            WorkspaceModel.folderForNextNewWindow = target.workingFolderPath
            isWaitingForNewWindow = true
            openMainWindow()
        }
    }

    /// The click is over, answered or not.
    private static func finishRequest() {
        if isWaitingForNewWindow, let target = request,
           WorkspaceModel.folderForNextNewWindow == target.workingFolderPath {
            WorkspaceModel.folderForNextNewWindow = nil
        }
        request = nil
        isWaitingForNewWindow = false
    }

    /// One window, as `decide` sees it.
    private static func windowState(of model: WorkspaceModel, for target: NotificationClickTarget) -> WindowState {
        var relation: FolderRelation = .none
        if let path = model.workspaceURL?.path {
            if FolderIdentity.isSameFolder(path, target.workingFolderPath) {
                relation = .this
            } else {
                relation = .other
            }
        }
        let isBusy: Bool = model.renamingCourseCode != nil || sheetIsUp(model)
        return WindowState(folder: relation, hasSettled: model.hasSettledItsFolder, isBusy: isBusy)
    }

    /// Selects the section, with its course unfolded in the sidebar.
    private static func select(_ target: NotificationClickTarget, in model: WorkspaceModel) {
        model.expandedCourseCodes.insert(target.course)
        model.selection = .section(target.course, target.section)
    }

    /// The trail line for an outcome, after the course/section prefix.
    private static func note(_ outcome: Outcome, for target: NotificationClickTarget) {
        ActivityTrail.note(
            .scheduledPublishNotification,
            outcome.line,
            course: target.course, section: target.section
        )
    }

    /// The window models in the order the teacher sees their windows, front
    /// to back — not "the key window": when a notification is clicked
    /// Plantoir is not the active app, so none of its windows is key (review
    /// M3). A window not on screen (minimised, or not shown yet) goes last,
    /// in the order the windows appeared.
    private static func defaultWindowsFrontToBack() -> [WorkspaceModel] {
        var ordered: [WorkspaceModel] = []
        for window in NSApp.orderedWindows {
            for model in WorkspaceModel.windowModels {
                if model.window === window && !containsModel(ordered, model) {
                    ordered.append(model)
                }
            }
        }
        for model in WorkspaceModel.windowModels {
            if !containsModel(ordered, model) {
                ordered.append(model)
            }
        }
        return ordered
    }

    private static func containsModel(_ models: [WorkspaceModel], _ wanted: WorkspaceModel) -> Bool {
        for model in models {
            if model === wanted {
                return true
            }
        }
        return false
    }

    private static func defaultFolderExists(_ path: String) -> Bool {
        return WorkspaceModel.folderExists(atPath: path)
    }

    private static func defaultSheetIsUp(_ model: WorkspaceModel) -> Bool {
        return model.window?.attachedSheet != nil
    }

    private static func defaultBringForward(_ model: WorkspaceModel?) {
        if WorkspaceModel.isRunningTests {
            return
        }
        if let window = model?.window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }
}
