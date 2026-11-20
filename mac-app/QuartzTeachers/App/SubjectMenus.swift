import SwiftUI

/// The Course, Section and Classes menus (#457; Classes since #990): every
/// action a teacher can take on a course or a section, in the menu bar,
/// between View and Window.
///
/// The context menus and the windows' own buttons stay as second routes and
/// call the SAME code — the sidebar's `performMenuItem`, the section window's
/// `previewButtonPressed`/`startDeploy`, Course Settings' `save` — so a menu
/// item and the button beside it cannot disagree. What can be used is decided
/// by `SubjectMenuRules`; this file only draws it. Items GREY rather than
/// disappear, a Revise target this Mac does not have included (#990, D11:
/// "If a menu bar item isn't actionable, disable the action instead of
/// hiding it from the menu", The menu bar). No grey explanatory text rows
/// (#990, Russell's ruling Q14): a menu holds commands only.
///
/// Rejected, and why, in `documentation/09-mac-app.md` → "Mac conventions":
/// one "Actions" menu, a menu per window, hiding what does not apply, and
/// the same words in two menus.
struct CourseMenu: Commands {

    // MARK: - Stored properties

    @FocusedValue(\.workspace) var workspace: WorkspaceModel?
    @FocusedValue(\.sidebarMenu) var sidebar: SidebarMenuCommands?
    @FocusedValue(\.courseSettingsMenu) var settings: CourseSettingsCommands?

    var presence: OutsideAssistantPresence = OutsideAssistantPresence.shared

    // MARK: - Computed properties

    var situation: SubjectMenuRules.Situation {
        return MenuSituation.assemble(
            workspace: workspace, sidebar: sidebar, site: nil, settings: settings, previewController: nil
        )
    }

    // MARK: - Body

    var body: some Commands {
        CommandMenu("Course") {
            let current: SubjectMenuRules.Situation = situation
            let enabled: Set<SubjectMenuRules.Item> = SubjectMenuRules.enabledItems(current)

            item("Add Section…", .addSection, enabled)
                .keyboardShortcut("n", modifiers: [.command, .option])
            // ⇧⌘K (#990, D25, Russell 2026-11-18): it was ⇧⌘C, the
            // system's Show Colors, and Shift added to ⌘C (Copy) for a
            // command that is not a clipboard copy. ⇧⌘K is in no row of the
            // HIG's standard table and in no system or Services shortcut of
            // a stock Mac (checked 2026-11-19, macOS 26.7.3).
            item(CopyPageWording.menuItem, .copyAPage, enabled)
                .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            item("Save Course Settings", .saveCourseSettings, enabled)
                .keyboardShortcut("s", modifiers: [.command])
            // Dimmed on the Planning tab, whose help tag says why
            // (`CourseSettingsCommands.revertHelp`, #990 review): no grey
            // text row under it, ruling Q14.
            item("Revert Course Settings", .revertCourseSettings, enabled)
                .help(settings?.revertHelp ?? "")

            Divider()

            // No key equivalent, and that is deliberate: Return starts a
            // rename in the sidebar, as it does in Finder, but a bare Return
            // as a menu key equivalent is matched by AppKit before the key
            // reaches the responder chain — it would be taken from every
            // text field and default button in the window. Finder's own
            // Rename has none for the same reason.
            // No ellipsis: it edits the name in place and asks nothing
            // more, as Finder's Rename does (#457, the HIG sweep).
            item("Rename", .rename, enabled)
            item(ReferenceWording.setSchoolYearMenuItem, .setSchoolYear, enabled)
            moveToGroupMenu(enabled)
            item(ReferenceWording.keepACopyMenuItem, .keepACopyForReference, enabled)

            Divider()

            item("Back Up Now", .backUpNow, enabled)
            // Not "Restore…": File ▸ Restore from Archive… restores an
            // archived row, and two items saying the same words is what
            // #457 item 4 rules out.
            item("Restore from Backup…", .restoreFromBackup, enabled)

            Divider()

            ReviseWithMenu(
                presence: presence,
                claude: .courseReviseWithClaude,
                codex: .courseReviseWithCodex,
                copilot: .courseReviseWithCopilot,
                localAssistant: .courseReviseWithLocalAssistant,
                enabled: enabled,
                run: run
            )

            Divider()

            // ⇧⌘O sits on whichever Open in Obsidian is live: this one
            // unless a SECTION row is selected. Measured: a key equivalent on
            // a DISABLED item that comes earlier in the menu bar swallows the
            // key — AppKit reports it handled and runs nothing — so the same
            // key on both items would do nothing at all on a section row.
            item("Open in Obsidian", .courseOpenInObsidian, enabled)
                .keyboardShortcut(current.row == .section ? nil : KeyboardShortcut("o", modifiers: [.command, .shift]))
            item("Show in Finder", .courseShowInFinder, enabled)
            item("New Terminal at Folder", .courseNewTerminalAtFolder, enabled)

            Divider()

            // Destructive items last, behind a divider (#457 item 4).
            item("Delete Backup…", .deleteBackup, enabled)
            item("Delete Archive…", .deleteArchive, enabled)
            item("Remove Course…", .removeCourse, enabled)
        }
    }

    // MARK: - Functions

    func item(_ title: String, _ item: SubjectMenuRules.Item, _ enabled: Set<SubjectMenuRules.Item>) -> some View {
        return Button(title) {
            run(item)
        }
        .disabled(!enabled.contains(item))
    }

    /// Move to Group ▸ (#572, third piece): the keyboard's way to the same
    /// list as a reference course's row menu (menu search reaches it; no key
    /// equivalent). Greys where Set School Year greys, and while the shelf's
    /// arrangement cannot be changed.
    @ViewBuilder
    func moveToGroupMenu(_ enabled: Set<SubjectMenuRules.Item>) -> some View {
        let course: Course? = workspace?.selectedCourse
        let mayChange: Bool = workspace?.referenceGroupsMayChange ?? false
        Menu(ReferenceGroupWording.moveToGroupMenuItem) {
            if let workspace, let course, course.isKeptForReference {
                ForEach(workspace.referenceMoveTargets(for: course)) { target in
                    Toggle(target.title, isOn: Binding(
                        get: { return target.isCurrent },
                        set: { _ in
                            if target.isCurrent {
                                return
                            }
                            MenuRoute.run(.moveToGroup, in: workspace.window) {
                                workspace.moveReferenceCourse(course, to: target.place)
                            }
                        }
                    ))
                }
                Divider()
                Button(ReferenceGroupWording.newGroupMenuItem) {
                    MenuRoute.run(.moveToGroup, in: workspace.window) {
                        workspace.newGroupThenMove = course.code
                        workspace.isMakingAReferenceGroup = true
                    }
                }
            }
        }
        .disabled(!enabled.contains(.moveToGroup) || !mayChange)
    }

    func run(_ item: SubjectMenuRules.Item) {
        MenuRoute.run(item, in: workspace?.window) {
            switch item {
            case .saveCourseSettings, .revertCourseSettings:
                settings?.perform(item)
            default:
                sidebar?.perform(item)
            }
        }
    }
}

/// The Section menu and the Classes menu (#990, Russell's ruling of
/// 2026-11-20: grouping A). One type draws either, from
/// `SubjectMenuLayout`, which says which items each holds and in what groups
/// (`contracts/shared-rules.json` → `subjectMenus.layout`), so the split is
/// data both apps draw. Both act on the selected section. A separator goes
/// between groups; every item is drawn in every situation and dimmed when
/// `SubjectMenuRules` greys it, never hidden (The menu bar: "If a menu bar
/// item isn't actionable, disable the action instead of hiding it from the
/// menu").
struct SectionMenu: Commands {

    // MARK: - Stored properties

    /// Which of the two menus this one is.
    let layout: SubjectMenuLayout.Menu

    @FocusedValue(\.workspace) var workspace: WorkspaceModel?
    @FocusedValue(\.sidebarMenu) var sidebar: SidebarMenuCommands?
    @FocusedValue(\.sectionSiteMenu) var site: SectionSiteCommands?

    var presence: OutsideAssistantPresence = OutsideAssistantPresence.shared

    // MARK: - Computed properties

    var situation: SubjectMenuRules.Situation {
        return MenuSituation.assemble(
            workspace: workspace, sidebar: sidebar, site: site, settings: nil, previewController: nil
        )
    }

    /// Where Preview opens by default (#504): the section window's copy of
    /// the setting when one is in front, so the title moves with the
    /// window's own republish; otherwise the setting itself.
    var previewSetting: PreviewOpensAt {
        if let site {
            return site.previewOpensAt
        }
        return AppSettings.shared.previewOpensAt
    }

    /// The menu's groups, numbered so a separator can go before every group
    /// but the first.
    var numberedGroups: [NumberedGroup] {
        var numbered: [NumberedGroup] = []
        var position: Int = 0
        for group in SubjectMenuLayout.groups(of: layout) {
            numbered.append(NumberedGroup(position: position, entries: group))
            position += 1
        }
        return numbered
    }

    // MARK: - Types

    /// One group of the layout, with its place in the menu.
    struct NumberedGroup: Identifiable {

        // MARK: - Stored properties

        let position: Int
        let entries: [SubjectMenuLayout.Entry]

        // MARK: - Computed properties

        var id: Int {
            return position
        }
    }

    // MARK: - Body

    var body: some Commands {
        // The title follows the selected course: Classes, or Meetings in a
        // club (#990, Russell, 2026-11-20 evening), as the items follow it.
        CommandMenu(SubjectMenuLayout.title(of: layout, noun: situation.classNoun)) {
            let current: SubjectMenuRules.Situation = situation
            let enabled: Set<SubjectMenuRules.Item> = SubjectMenuRules.enabledItems(current)

            ForEach(numberedGroups) { group in
                if group.position > 0 {
                    Divider()
                }
                ForEach(group.entries, id: \.self) { entry in
                    line(for: entry, current: current, enabled: enabled)
                }
            }
        }
    }

    // MARK: - Functions

    /// The menu's title for an item (#990: Remove Section and Remove
    /// Scheduled Deploy carry no ellipsis, since a command that only asks
    /// for a confirmation takes none: "Append an ellipsis to a menu item's
    /// label when the action requires more information before it can
    /// complete", Menus). The menu draws Preview with `previewItem`, titled
    /// by the setting; this is its resting title, for a menu path.
    static func title(for item: SubjectMenuRules.Item) -> String? {
        switch item {
        case .preview:
            return PreviewStartPageWording.preview
        case .rebuildPreview:
            return "Rebuild Preview"
        case .openInBrowser:
            // One Open in Browser for both (#850): the preview while one
            // shows, the deployed folder otherwise.
            return DeployedFolderWording.menuItem
        case .stopShowingDeployedFolder:
            return DeployedFolderWording.stopMenuItem
        case .publishClassForADate:
            return "Publish Class for a Date…"
        case .publishPages:
            return "Publish Pages…"
        case .hidePages:
            return "Hide Pages…"
        case .publishPagesLinksLeadTo:
            return LinksChecklistWording.menuItem
        case .undoLastChange:
            return "Undo Last Change"
        case .undoGettingReady:
            return StartOfYearWording.undoMenuItem
        case .deploy:
            return "Deploy…"
        case .scheduleDeploy:
            return "Schedule Deploy…"
        case .cancelScheduledDeploy:
            // #987: Remove, not Cancel, and the same title whether or not it
            // can be used; the time is in the question it opens.
            return ScheduledDeployRemovalWording.menuItem
        case .sectionOpenInObsidian:
            return "Open in Obsidian"
        case .sectionShowInFinder:
            return "Show in Finder"
        case .sectionNewTerminalAtFolder:
            return "New Terminal at Folder"
        case .removeSection:
            return "Remove Section"
        case .addClass:
            // #897: ONE item whose sheet asks how the class is added. An
            // ellipsis: a choice follows.
            return "Add Class…"
        case .classDates:
            return "Class Dates…"
        case .reDateClasses:
            return "Re-date Classes…"
        case .makeRoomForClasses:
            return "Make Room for Classes…"
        case .rollOverToANewYear:
            // #897 piece B: an ellipsis (a choice and a plan follow); no key;
            // not on the row's right-click menu, being once a year.
            return "Roll Over to a New Year…"
        case .getReadyForTheStartOfTheYear:
            return StartOfYearWording.menuItem
        case .sectionReviseWithClaude, .sectionReviseWithCodex, .sectionReviseWithCopilot,
             .sectionReviseWithLocalAssistant:
            // Drawn inside Revise With ▸ by `ReviseWithMenu`, which titles them.
            return nil
        case .openWorkingFolder, .openRecent, .newCourse, .importCoursesForReference, .restoreFromArchive,
             .reloadCourses, .addSection, .copyAPage, .saveCourseSettings, .revertCourseSettings, .rename,
             .setSchoolYear, .moveToGroup, .keepACopyForReference, .backUpNow, .restoreFromBackup,
             .courseReviseWithClaude, .courseReviseWithCodex, .courseReviseWithCopilot,
             .courseReviseWithLocalAssistant, .courseOpenInObsidian, .courseShowInFinder,
             .courseNewTerminalAtFolder, .deleteBackup, .deleteArchive, .removeCourse,
             .back, .forward, .reloadPage:
            // File, Course and View items: not in Section or Classes. No
            // `default`, so a new item does not compile until it is placed
            // here or given its title (#990 review, LOW c).
            return nil
        }
    }

    /// One line of the layout: an item, with its key where it has one, or
    /// a submenu.
    @ViewBuilder
    func line(
        for entry: SubjectMenuLayout.Entry,
        current: SubjectMenuRules.Situation,
        enabled: Set<SubjectMenuRules.Item>
    ) -> some View {
        switch entry {
        case .submenu(.sectionReviseWith):
            ReviseWithMenu(
                presence: presence,
                claude: .sectionReviseWithClaude,
                codex: .sectionReviseWithCodex,
                copilot: .sectionReviseWithCopilot,
                localAssistant: .sectionReviseWithLocalAssistant,
                enabled: enabled,
                run: run
            )
        case .item(.preview):
            // The menu item IS the teacher pressing the Preview button, so it
            // runs the button's own action — including the question about
            // today's class on the front page (#397; class-planning.json →
            // askedFrom).
            //
            // #504: titled by what it will do, the setting's start page, with
            // an Option ALTERNATE (⌥⌘Y) for the other one — a real
            // `NSMenuItem.isAlternate`, measured (504 plan M3), which inherits
            // the item's enablement, so no new `SubjectMenuRules.Item`. While
            // a preview runs the item stops it and has no alternate: Option
            // means nothing to Stop.
            //
            // ⌘Y (#990, D24, Russell 2026-11-18): it was ⇧⌘P, the system's
            // Page Setup. ⌘Y is Quick Look in Finder, the same idea (look
            // without committing); it is in no row of the HIG's standard
            // table and in no system or Services shortcut of a stock Mac
            // (checked 2026-11-19, macOS 26.7.3), and neither is ⌥⌘Y.
            if site?.previewIsRunning == true {
                item(PreviewStartPageWording.stopPreview, .preview, enabled)
                    .keyboardShortcut("y", modifiers: [.command])
            } else {
                previewItem(opensAt: previewSetting, enabled)
                    .modifierKeyAlternate(.option) {
                        previewItem(opensAt: previewSetting.opposite, enabled)
                    }
                    .keyboardShortcut("y", modifiers: [.command])
            }
        case .item(.rebuildPreview):
            // ⇧⌘Y (#990, Russell 2026-11-18): the Shift partner of Preview's
            // ⌘Y. It was ⇧⌘B, which added Shift to ⌘B (Bold) for an
            // unrelated command. ⇧⌘Y is in no row of the HIG's standard
            // table and in no symbolic hot key; a stock Mac's Services menu
            // gives it to Stickies' Make New Sticky Note, and inside
            // Plantoir the app's own item wins ("When an application already
            // has a shortcut with that key equivalent, the application's
            // shortcut wins", Services Implementation Guide), measured in
            // the running app (documentation/09 → "Mac conventions").
            item("Rebuild Preview", .rebuildPreview, enabled)
                .keyboardShortcut("y", modifiers: [.command, .shift])
        case .item(.deploy):
            item("Deploy…", .deploy, enabled)
                .keyboardShortcut("d", modifiers: [.command, .shift])
        case .item(.sectionOpenInObsidian):
            // ⇧⌘O sits on whichever Open in Obsidian is live: this one while
            // a SECTION row is selected (see CourseMenu).
            item("Open in Obsidian", .sectionOpenInObsidian, enabled)
                .keyboardShortcut(current.row == .section ? KeyboardShortcut("o", modifiers: [.command, .shift]) : nil)
        case .item(let plain):
            // No key on the rest. Undo Last Change in particular: ⌘Z
            // belongs to text editing in Edit, and a key that took back a
            // page change from inside a text field would be a surprise
            // nobody could undo.
            // A layout item with no title draws its raw name, and
            // `SubjectMenuLayoutTests` fails on it.
            item(SectionMenu.title(for: plain) ?? plain.rawValue, plain, enabled)
        }
    }

    /// Section ▸ Preview asking for one start page (#504). Titled by
    /// `PreviewStartPage` — the same function as the toolbar button.
    func previewItem(opensAt: PreviewOpensAt, _ enabled: Set<SubjectMenuRules.Item>) -> some View {
        return Button(PreviewStartPage.title(for: opensAt)) {
            MenuRoute.run(.preview, in: workspace?.window) {
                site?.preview(opensAt)
            }
        }
        .disabled(!enabled.contains(.preview))
    }

    func item(_ title: String, _ item: SubjectMenuRules.Item, _ enabled: Set<SubjectMenuRules.Item>) -> some View {
        return Button(title) {
            run(item)
        }
        .disabled(!enabled.contains(item))
    }

    /// The assistant's own functions (#457 batch B) and the window's own
    /// buttons run through the section window (`SectionVerbs`) — never
    /// through a model, so a teacher who declined the assistant has every
    /// one of them; the rest go to the sidebar's code, as the row's context
    /// menu does.
    func run(_ item: SubjectMenuRules.Item) {
        MenuRoute.run(item, in: workspace?.window) {
            switch item {
            case .preview, .deploy, .openInBrowser, .stopShowingDeployedFolder,
                 .publishPages, .hidePages, .publishClassForADate, .rebuildPreview, .undoLastChange,
                 .addClass,
                 .reDateClasses, .makeRoomForClasses, .classDates, .rollOverToANewYear:
                site?.perform(item)
            default:
                sidebar?.perform(item)
            }
        }
    }
}

/// Revise With ▸ Claude… / Codex… / GitHub Copilot… / Local AI Assistant…,
/// in both subject menus, then Set Up an Assistant… after a divider, which
/// opens Settings ▸ Other Assistants and installs nothing itself.
///
/// **Every target is drawn, on every Mac, since #990** (D11, Russell's
/// ruling Q9): one this Mac does not have is DIMMED, not left out — "Always
/// show the same set of menu items… If a menu bar item isn't actionable,
/// disable the action instead of hiding it from the menu" (The menu bar).
/// The row's context menu still HIDES one this Mac does not have: "Hide
/// unavailable menu items, don't dim them" (Context menus). Enabled means
/// installed AND allowed by the rule (`SubjectMenuRules`, #458). No grey
/// line says why an item is dimmed (Q14). Always drawn since #855
/// (Russell, 2026-11-13).
struct ReviseWithMenu: View {

    // MARK: - Stored properties

    var presence: OutsideAssistantPresence
    var claude: SubjectMenuRules.Item
    var codex: SubjectMenuRules.Item
    var copilot: SubjectMenuRules.Item
    var localAssistant: SubjectMenuRules.Item
    var enabled: Set<SubjectMenuRules.Item>
    var run: (SubjectMenuRules.Item) -> Void

    /// The local assistant's title inside Revise With ▸, shared with the
    /// rows' context menus (#457, the HIG sweep: one name everywhere).
    static let localAssistantTitle: String = "Local AI Assistant…"

    /// One item of the submenu: its title, the item it runs, and whether it
    /// can be pressed.
    struct Entry: Equatable, Identifiable {

        // MARK: - Stored properties

        let title: String
        let item: SubjectMenuRules.Item
        let isEnabled: Bool

        // MARK: - Computed properties

        var id: String {
            return item.rawValue
        }
    }

    // MARK: - Body

    var body: some View {
        Menu("Revise With") {
            let entries: [Entry] = ReviseWithMenu.entries(
                claudeIsInstalled: presence.claudeIsInstalled,
                codexIsInstalled: presence.codexIsInstalled,
                copilotIsInstalled: presence.copilotIsInstalled,
                localAssistantCanRun: presence.localAssistantCanRun,
                claude: claude,
                codex: codex,
                copilot: copilot,
                localAssistant: localAssistant,
                enabled: enabled
            )
            ForEach(entries) { entry in
                Button(entry.title) {
                    run(entry.item)
                }
                .disabled(!entry.isEnabled)
            }
            Divider()
            SetUpAnotherAssistantButton(title: AssistantSetUpWording.menuItem, from: .reviseWith)
        }
    }

    // MARK: - Functions

    /// The four items, in the order the doors are shown everywhere (Claude,
    /// Codex, GitHub Copilot, then the local assistant), whatever this Mac
    /// has; each enabled only when this Mac has it and the rule allows it.
    static func entries(
        claudeIsInstalled: Bool,
        codexIsInstalled: Bool,
        copilotIsInstalled: Bool,
        localAssistantCanRun: Bool,
        claude: SubjectMenuRules.Item,
        codex: SubjectMenuRules.Item,
        copilot: SubjectMenuRules.Item,
        localAssistant: SubjectMenuRules.Item,
        enabled: Set<SubjectMenuRules.Item>
    ) -> [Entry] {
        var entries: [Entry] = []
        entries.append(Entry(
            title: ClaudeCodeLauncher.menuItemTitle, item: claude,
            isEnabled: claudeIsInstalled && enabled.contains(claude)
        ))
        entries.append(Entry(
            title: CodexLauncher.menuItemTitle, item: codex,
            isEnabled: codexIsInstalled && enabled.contains(codex)
        ))
        entries.append(Entry(
            title: CopilotLauncher.menuItemTitle, item: copilot,
            isEnabled: copilotIsInstalled && enabled.contains(copilot)
        ))
        entries.append(Entry(
            title: localAssistantTitle, item: localAssistant,
            isEnabled: localAssistantCanRun && enabled.contains(localAssistant)
        ))
        return entries
    }
}
