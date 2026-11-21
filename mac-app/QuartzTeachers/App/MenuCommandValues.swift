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

    /// When the selected section deploys on its own, for the Cancel item's title.
    var scheduledFor: Date?

    /// What the selected course calls its class pages, for the Classes
    /// menu's title: Meetings in a club (#990, Russell, 2026-11-20 evening).
    /// It greys nothing, so it is not part of the situation the rules read.
    var classNoun: ClassNoun

    /// Runs an item on whatever is selected when it runs.
    var perform: (SubjectMenuRules.Item) -> Void

    // MARK: - Functions

    static func == (left: SidebarMenuCommands, right: SidebarMenuCommands) -> Bool {
        return left.situation == right.situation
            && left.scheduledFor == right.scheduledFor
            && left.classNoun == right.classNoun
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

    /// The deployed folder (#850): it can be opened, and it is shown. Why
    /// Open in Browser is greyed is no longer said under the item (#990,
    /// Russell's ruling Q14: no grey text rows in the menus).
    var deployedFolderReady: Bool = false
    var deployedFolderShown: Bool = false

    /// The assistant's functions (#457 batch B): Undo Last Change's target is
    /// this section, and one of them is running on it.
    var lastChangeIsHere: Bool = false
    var verbIsRunning: Bool = false

    /// Where a press of Preview opens by default (#504) — Settings ▸ Preview,
    /// read by the section window. In `==` because the menu item's TITLE
    /// follows it ("Preview" or "Preview at Last Viewed").
    var previewOpensAt: PreviewOpensAt = .frontPage

    /// Presses the button the item names, or runs the function.
    var perform: (SubjectMenuRules.Item) -> Void

    /// Presses Preview asking for one start page (#504): Section ▸ Preview
    /// asks for the setting, and its Option alternate for the opposite. Kept
    /// out of `==`, like `perform`.
    var preview: (PreviewOpensAt) -> Void = { _ in }

    // MARK: - Functions

    static func == (left: SectionSiteCommands, right: SectionSiteCommands) -> Bool {
        return left.previewIsRunning == right.previewIsRunning
            && left.previewButtonEnabled == right.previewButtonEnabled
            && left.deployButtonEnabled == right.deployButtonEnabled
            && left.previewIsShowing == right.previewIsShowing
            && left.deployedFolderReady == right.deployedFolderReady
            && left.deployedFolderShown == right.deployedFolderShown
            && left.lastChangeIsHere == right.lastChangeIsHere
            && left.verbIsRunning == right.verbIsRunning
            && left.previewOpensAt == right.previewOpensAt
    }
}

/// Course Settings' Save and Revert, for Course ▸ Save Course Settings (⌘S —
/// on the menu item since #457, no longer on the button) and Revert.
struct CourseSettingsCommands: Equatable {

    // MARK: - Stored properties

    var maySave: Bool
    var mayRevert: Bool

    var perform: (SubjectMenuRules.Item) -> Void

    /// Why Revert is dimmed, as the menu item's help tag, or nothing when
    /// the page in front has no reason to give. Revert is dimmed on the
    /// Planning tab; until #990 a grey line under it in the Course menu said
    /// why (#708's `PlanningWording.revertOnPlanning`). Russell's ruling Q14
    /// took the grey rows out of the menus, and the same sentence became
    /// this help tag (HIG, Offering help: "Consider offering
    /// context-sensitive tooltips"). Measured: the tag shows on the dimmed
    /// item, but a menu item's tag is not exposed to accessibility (no
    /// AXHelp, an accessibility hint included), so a VoiceOver user has the
    /// same sentence from Help's course-settings page.
    var revertHelp: String = ""

    // MARK: - Functions

    static func == (left: CourseSettingsCommands, right: CourseSettingsCommands) -> Bool {
        return left.maySave == right.maySave && left.mayRevert == right.mayRevert
            && left.revertHelp == right.revertHelp
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
            situation.deployedFolderReady = site.deployedFolderReady
            situation.deployedFolderShown = site.deployedFolderShown
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
