import AppKit
import SwiftUI

/// What the menu bar's File, Course and Section menus read from the window
/// in front (#457), and the one route every item's action takes.
///
/// **The shape is Canopy's**, which `PreviewCommands` already had: a window
/// publishes values through `focusedSceneValue`, the App's `.commands` reads
/// them with `@FocusedValue`, every item DISABLES rather than disappears, and
/// each value is Equatable on what the menu SHOWS and nothing else, so a
/// republish that changes nothing does not rebuild the menu bar.
///
/// **One value per OWNER of the state, not one per menu.** The Course and
/// Section menus need things three different views own: the sidebar (the
/// selection and every sheet a row's menu opens), the section window (its
/// preview and deploy runners), and Course Settings (Save and Revert). One
/// value per menu would have had to merge the three; moving all of that
/// state into the window's model was a refactor a teacher would never see.
/// So each owner publishes its own, and `MenuSituation` assembles them.
///
/// **Closures read the selection when they RUN**, not when they were
/// published: equality ignores the closure, so an "equal" republish keeps
/// the old one, and a closure that captured its target would act on a row
/// the teacher has since left.
struct SidebarMenuCommands: Equatable {

    // MARK: - Stored properties

    /// The sidebar's half of the situation: the selected row and what is
    /// true of it.
    var situation: SubjectMenuRules.Situation

    /// Why Rename and Add Section wait, said under Course ▸ Rename.
    var structuralReason: String?

    /// Why the Revise items are greyed, each reason once (#458).
    var reviseNotes: [String]

    /// When the selected section deploys on its own, for the Cancel item's title.
    var scheduledFor: Date?

    /// Runs an item on whatever is selected when it runs.
    var perform: (SubjectMenuRules.Item) -> Void

    // MARK: - Functions

    static func == (left: SidebarMenuCommands, right: SidebarMenuCommands) -> Bool {
        return left.situation == right.situation
            && left.structuralReason == right.structuralReason
            && left.reviseNotes == right.reviseNotes
            && left.scheduledFor == right.scheduledFor
    }
}

/// The section window's own buttons, for Section ▸ Preview, Deploy… and Open
/// in Browser — read off the SAME predicates the toolbar uses, so the menu
/// item and the button beside it cannot disagree.
struct SectionSiteCommands: Equatable {

    // MARK: - Stored properties

    var previewIsRunning: Bool
    var previewButtonEnabled: Bool
    var deployButtonEnabled: Bool
    var previewIsShowing: Bool

    /// The assistant's functions (#457 batch B): Undo Last Change's target is
    /// this section, and one of them is running on it.
    var lastChangeIsHere: Bool = false
    var verbIsRunning: Bool = false

    /// Presses the button the item names, or runs the function.
    var perform: (SubjectMenuRules.Item) -> Void

    // MARK: - Functions

    static func == (left: SectionSiteCommands, right: SectionSiteCommands) -> Bool {
        return left.previewIsRunning == right.previewIsRunning
            && left.previewButtonEnabled == right.previewButtonEnabled
            && left.deployButtonEnabled == right.deployButtonEnabled
            && left.previewIsShowing == right.previewIsShowing
            && left.lastChangeIsHere == right.lastChangeIsHere
            && left.verbIsRunning == right.verbIsRunning
    }
}

/// Course Settings' Save and Revert, for Course ▸ Save Course Settings (⌘S —
/// on the menu item since #457, no longer on the button) and Revert.
struct CourseSettingsCommands: Equatable {

    // MARK: - Stored properties

    var maySave: Bool
    var mayRevert: Bool
    var perform: (SubjectMenuRules.Item) -> Void

    // MARK: - Functions

    static func == (left: CourseSettingsCommands, right: CourseSettingsCommands) -> Bool {
        return left.maySave == right.maySave && left.mayRevert == right.mayRevert
    }
}

extension FocusedValues {

    /// The sidebar of the window in front.
    @Entry var sidebarMenu: SidebarMenuCommands?

    /// The section window in front, when a section is showing.
    @Entry var sectionSiteMenu: SectionSiteCommands?

    /// Course Settings, when a course is showing.
    @Entry var courseSettingsMenu: CourseSettingsCommands?
}

/// The whole situation, assembled from what the window in front publishes.
enum MenuSituation {

    // MARK: - Functions

    static func assemble(
        workspace: WorkspaceModel?,
        sidebar: SidebarMenuCommands?,
        site: SectionSiteCommands?,
        settings: CourseSettingsCommands?,
        previewController: WebPreviewController?
    ) -> SubjectMenuRules.Situation {
        guard let workspace else {
            return SubjectMenuRules.Situation()
        }
        var situation: SubjectMenuRules.Situation = sidebar?.situation ?? SubjectMenuRules.Situation()
        situation.hasFolder = workspace.workspaceURL != nil && !workspace.isShowingPicker
        situation.folderGettingReady = workspace.folderIsGettingReady
        situation.sheetIsUp = workspace.sheetIsUp
        if let settings {
            situation.settingsMaySave = settings.maySave
            situation.settingsMayRevert = settings.mayRevert
        }
        if let site {
            situation.previewButtonEnabled = site.previewButtonEnabled
            situation.deployButtonEnabled = site.deployButtonEnabled
            situation.previewIsShowing = site.previewIsShowing
            situation.previewIsRunning = site.previewIsRunning
            situation.lastChangeIsHere = site.lastChangeIsHere
            situation.verbIsRunning = site.verbIsRunning
        }
        if let previewController {
            situation.previewIsShowing = true
            situation.canGoBack = previewController.canGoBack
            situation.canGoForward = previewController.canGoForward
        }
        return situation
    }
}

/// The one way a menu item's action runs.
///
/// Greying an item is a convenience; THIS is the guard. A menu key
/// equivalent fires while a sheet or alert is attached to its window —
/// measured by the plan review, a real ⇧⌘D through `NSApp.sendEvent` ran
/// Deploy behind a sheet — so the window is asked again at the moment the
/// item runs, and nothing happens behind a sheet whatever the menu showed.
enum MenuRoute {

    // MARK: - Stored properties

    /// Tests only: when set, an item that would run is reported here
    /// instead, so a test can press a real key equivalent without starting
    /// a real deploy.
    static var interceptForTests: ((SubjectMenuRules.Item) -> Void)?

    // MARK: - Functions

    /// Whether `window` may act now: nothing attached to it, and the app is
    /// not in a modal session.
    static func windowIsFree(_ window: NSWindow?) -> Bool {
        if NSApp.modalWindow != nil {
            return false
        }
        if let window, window.attachedSheet != nil {
            return false
        }
        return true
    }

    /// Runs `item` in `window`, unless a sheet or modal window is up.
    static func run(_ item: SubjectMenuRules.Item, in window: NSWindow?, action: () -> Void) {
        if !windowIsFree(window) {
            NSSound.beep()
            return
        }
        if let interceptForTests {
            interceptForTests(item)
            return
        }
        action()
    }
}
