import Foundation

/// Which items in the menu bar's File, Course and Section menus can be used
/// right now — decided in ONE pure place, from facts the window publishes
/// (#457).
///
/// **Presence follows the Mac, enablement follows the selection.** Whether
/// "Revise With ▸ Claude…" is DRAWN depends on whether Claude is installed
/// (`OutsideAssistantPresence`); whether it can be USED depends on what is
/// selected, and that is this type's whole job. The menu bar GREYS an item
/// that does not apply rather than hiding it, because a menu whose items come
/// and go with the selection is a menu a teacher cannot learn; the sidebar's
/// context menus keep HIDING what does not apply, because they are about one
/// row.
///
/// **A sheet or an alert greys everything** (`sheetIsUp`). A menu item's key
/// equivalent fires even while a sheet is attached to its window — measured
/// by the plan review: a real ⇧⌘D sent through `NSApp.sendEvent` with a sheet
/// up ran Deploy — so without this a teacher half-way through Add Section…
/// could start a deploy behind it. Greying is the first guard; `MenuRoute`
/// asks the window again at the click, which is the one that counts.
///
/// The cases live in `contracts/shared-rules.json` → `subjectMenus`, and
/// `SubjectMenuRulesTests` runs them; the raw values below are that
/// contract's item names.
nonisolated enum SubjectMenuRules {

    // MARK: - Types

    /// What kind of sidebar row is selected.
    enum Row: String, CaseIterable, Sendable {
        case none
        case course
        case section
        case backup
        case archived
        case allBackups
    }

    /// The outside assistants and the local one, for the Revise With items.
    enum ReviseTarget: String, CaseIterable, Sendable {
        case claude
        case codex
        case localAssistant
    }

    /// Every item whose enablement is decided here.
    enum Item: String, CaseIterable, Sendable {
        // File
        case newCourse
        case importCoursesForReference
        case restoreFromArchive
        case reloadCourses
        // Course
        case addSection
        case copyAPage
        case saveCourseSettings
        case revertCourseSettings
        case rename
        case setSchoolYear
        case keepACopyForReference
        case backUpNow
        case restoreFromBackup
        case courseReviseWithClaude
        case courseReviseWithCodex
        case courseReviseWithLocalAssistant
        case courseOpenInObsidian
        case courseShowInFinder
        case courseNewTerminalAtFolder
        case deleteBackup
        case deleteArchive
        case removeCourse
        // Section
        case preview
        case deploy
        case openInBrowser
        case scheduleDeploy
        case cancelScheduledDeploy
        case getReadyForTheStartOfTheYear
        case undoGettingReady
        case publishPagesLinksLeadTo
        case sectionReviseWithClaude
        case sectionReviseWithCodex
        case sectionReviseWithLocalAssistant
        case sectionOpenInObsidian
        case sectionShowInFinder
        case sectionNewTerminalAtFolder
        case removeSection
        // View
        case back
        case forward
        case reloadPage
    }

    /// Everything the rule needs to know, gathered from the window's
    /// publishers. Equatable so a republish that changes nothing the menu
    /// shows does not rebuild the menu bar.
    struct Situation: Equatable, Sendable {

        // MARK: - Stored properties

        /// A Plantoir window is in front with a working folder open.
        var hasFolder: Bool = false
        /// That folder's tools are still being copied, or the copy failed (#476).
        var folderGettingReady: Bool = false
        /// A sheet or alert is attached to the window, or the app is modal.
        var sheetIsUp: Bool = false

        var row: Row = .none
        /// The selected course (or the selected section's course) is kept
        /// for reference.
        var keptForReference: Bool = false
        /// Rename and Add Section must wait: previewing, deploying, or a
        /// Claude or Codex session open on the course (#458).
        var structuralHold: Bool = false
        /// The course is previewing or deploying (Keep a Copy waits).
        var busy: Bool = false
        /// A copy of the course is being zipped (#351).
        var copying: Bool = false
        /// A deploy of the course is running from this app.
        var deploying: Bool = false
        /// The selected section has a deploy scheduled.
        var hasSchedule: Bool = false
        /// The selected section holds a start-of-the-year undo (#96).
        var hasStartOfYearUndo: Bool = false
        /// The selected section's last build left a links checklist (#379).
        var hasLinksOffer: Bool = false
        /// Revise items greyed for a reason (#458).
        var reviseBlocked: Set<ReviseTarget> = []
        var obsidianInstalled: Bool = false

        /// Course Settings is showing and Save / Revert would do something.
        var settingsMaySave: Bool = false
        var settingsMayRevert: Bool = false

        /// The section window's own buttons, read off the same predicates
        /// the toolbar uses so the menu and the button cannot disagree.
        var previewButtonEnabled: Bool = false
        var deployButtonEnabled: Bool = false
        var previewIsShowing: Bool = false
        var canGoBack: Bool = false
        var canGoForward: Bool = false
    }

    // MARK: - Functions

    /// The items that can be used in `situation`.
    static func enabledItems(_ situation: Situation) -> Set<Item> {
        var enabled: Set<Item> = []
        if situation.sheetIsUp {
            return enabled
        }
        let isLive: Bool = !situation.keptForReference
        let isCourse: Bool = situation.row == .course
        let isSection: Bool = situation.row == .section
        let isCourseOrSection: Bool = isCourse || isSection

        // File
        if situation.hasFolder && !situation.folderGettingReady {
            enabled.insert(.newCourse)
        }
        if situation.hasFolder {
            enabled.insert(.importCoursesForReference)
            enabled.insert(.reloadCourses)
        }
        if situation.row == .archived {
            enabled.insert(.restoreFromArchive)
        }

        // Course: with a section selected these act on its course.
        if isCourseOrSection {
            enabled.insert(.copyAPage)
            if isLive && !situation.structuralHold {
                enabled.insert(.addSection)
                enabled.insert(.rename)
            }
            if !isLive {
                enabled.insert(.setSchoolYear)
            }
            if isLive && !situation.busy {
                enabled.insert(.keepACopyForReference)
            }
            if !situation.copying {
                enabled.insert(.backUpNow)
            }
        }
        if situation.settingsMaySave {
            enabled.insert(.saveCourseSettings)
        }
        if situation.settingsMayRevert {
            enabled.insert(.revertCourseSettings)
        }
        if situation.row == .backup && !situation.copying {
            enabled.insert(.restoreFromBackup)
        }
        // The Revise and folder group acts on the course ROW only: with a
        // section selected, the Section menu's copy of it is the live one,
        // so ⇧⌘O and its neighbours are never enabled in both menus at once.
        if isCourse && isLive {
            if !situation.reviseBlocked.contains(.claude) {
                enabled.insert(.courseReviseWithClaude)
            }
            if !situation.reviseBlocked.contains(.codex) {
                enabled.insert(.courseReviseWithCodex)
            }
            // The local assistant works per SECTION, so it is never live
            // on a course row (Russell, 2026-10-08: greyed, not hidden).
        }
        if isCourse && situation.obsidianInstalled {
            enabled.insert(.courseOpenInObsidian)
        }
        if isCourse || situation.row == .backup || situation.row == .archived {
            enabled.insert(.courseShowInFinder)
        }
        if isCourse {
            enabled.insert(.courseNewTerminalAtFolder)
        }
        if situation.row == .backup {
            enabled.insert(.deleteBackup)
        }
        if situation.row == .archived {
            enabled.insert(.deleteArchive)
        }
        if isCourse && !situation.copying {
            enabled.insert(.removeCourse)
        }

        // Section
        if isSection {
            if situation.previewButtonEnabled {
                enabled.insert(.preview)
            }
            if situation.deployButtonEnabled && isLive {
                enabled.insert(.deploy)
            }
            if situation.previewIsShowing {
                enabled.insert(.openInBrowser)
            }
            // Gated by DIRECTION, as the context menu is: a reference course
            // is never scheduled, but a schedule set before it was kept must
            // still be cancellable.
            if isLive && !situation.hasSchedule {
                enabled.insert(.scheduleDeploy)
            }
            if situation.hasSchedule {
                enabled.insert(.cancelScheduledDeploy)
            }
            if isLive && !situation.deploying {
                enabled.insert(.getReadyForTheStartOfTheYear)
                if situation.hasStartOfYearUndo {
                    enabled.insert(.undoGettingReady)
                }
                if situation.hasLinksOffer {
                    enabled.insert(.publishPagesLinksLeadTo)
                }
            }
            if isLive {
                if !situation.reviseBlocked.contains(.claude) {
                    enabled.insert(.sectionReviseWithClaude)
                }
                if !situation.reviseBlocked.contains(.codex) {
                    enabled.insert(.sectionReviseWithCodex)
                }
                if !situation.reviseBlocked.contains(.localAssistant) {
                    enabled.insert(.sectionReviseWithLocalAssistant)
                }
            }
            if situation.obsidianInstalled {
                enabled.insert(.sectionOpenInObsidian)
            }
            enabled.insert(.sectionShowInFinder)
            enabled.insert(.sectionNewTerminalAtFolder)
            if !situation.copying {
                enabled.insert(.removeSection)
            }
        }

        // View: the embedded preview's own navigation.
        if situation.previewIsShowing {
            enabled.insert(.reloadPage)
            if situation.canGoBack {
                enabled.insert(.back)
            }
            if situation.canGoForward {
                enabled.insert(.forward)
            }
        }
        return enabled
    }
}
