import SwiftUI

/// The Course and Section menus (#457): every action a teacher can take on a
/// course or a section, in the menu bar, between View and Window.
///
/// The context menus and the windows' own buttons stay as second routes and
/// call the SAME code — the sidebar's `performMenuItem`, the section window's
/// `previewButtonPressed`/`startDeploy`, Course Settings' `save` — so a menu
/// item and the button beside it cannot disagree. What can be used is decided
/// by `SubjectMenuRules`; this file only draws it. Items GREY rather than
/// disappear; only a Revise target this Mac does not have is left out
/// (`OutsideAssistantPresence`).
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
            item(CopyPageWording.menuItem, .copyAPage, enabled)
                .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            item("Save Course Settings", .saveCourseSettings, enabled)
                .keyboardShortcut("s", modifiers: [.command])
            item("Revert Course Settings", .revertCourseSettings, enabled)

            Divider()

            // No key equivalent, and that is deliberate: Return starts a
            // rename in the sidebar, as it does in Finder, but a bare Return
            // as a menu key equivalent is matched by AppKit before the key
            // reaches the responder chain — it would be taken from every
            // text field and default button in the window. Finder's own
            // Rename has none for the same reason.
            item("Rename…", .rename, enabled)
            // Dimmed alone says "no"; the line under it says what to do
            // about it — the shape the course's own menu already used.
            if current.row == .course || current.row == .section, current.keptForReference == false,
               let reason = sidebar?.structuralReason {
                Text(reason)
            }
            item(ReferenceWording.setSchoolYearMenuItem, .setSchoolYear, enabled)
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
                localAssistant: .courseReviseWithLocalAssistant,
                enabled: enabled,
                notes: current.row == .course ? (sidebar?.reviseNotes ?? []) : [],
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

/// The Section menu.
struct SectionMenu: Commands {

    // MARK: - Stored properties

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

    /// "Cancel Deploy at 6:30 AM…" when it can be used — the context menu's
    /// own title — and "Cancel Deploy at…" whenever it is greyed, with no
    /// time (Russell's decision 4): a course kept for reference, a sheet up,
    /// or nothing scheduled.
    var cancelTitle: String {
        let canCancel: Bool = SubjectMenuRules.enabledItems(situation).contains(.cancelScheduledDeploy)
        if canCancel, let scheduledFor = sidebar?.scheduledFor, situation.row == .section {
            return "Cancel Deploy at \(ScheduledDeploy.timeText(scheduledFor))…"
        }
        return "Cancel Deploy at…"
    }

    // MARK: - Body

    var body: some Commands {
        CommandMenu("Section") {
            let current: SubjectMenuRules.Situation = situation
            let enabled: Set<SubjectMenuRules.Item> = SubjectMenuRules.enabledItems(current)

            // The menu item IS the teacher pressing the Preview button, so it
            // runs the button's own action — including the question about
            // today's class on the front page (#397; class-planning.json →
            // askedFrom).
            item(site?.previewIsRunning == true ? "Stop Preview" : "Preview", .preview, enabled)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            item("Deploy…", .deploy, enabled)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            item("Open in Browser", .openInBrowser, enabled)

            Divider()

            // Batch B (#457): the assistant's verbs go here, after Open in
            // Browser, as a group of their own.

            item("Schedule Deploy…", .scheduleDeploy, enabled)
            item(cancelTitle, .cancelScheduledDeploy, enabled)

            Divider()

            item(StartOfYearWording.menuItem, .getReadyForTheStartOfTheYear, enabled)
            item(StartOfYearWording.undoMenuItem, .undoGettingReady, enabled)
            item(LinksChecklistWording.menuItem, .publishPagesLinksLeadTo, enabled)
            if current.row == .section && current.deploying {
                Text(CourseActivity.availableOnceDeployCompleted)
            }

            Divider()

            ReviseWithMenu(
                presence: presence,
                claude: .sectionReviseWithClaude,
                codex: .sectionReviseWithCodex,
                localAssistant: .sectionReviseWithLocalAssistant,
                enabled: enabled,
                notes: current.row == .section ? (sidebar?.reviseNotes ?? []) : [],
                run: run
            )

            Divider()

            item("Open in Obsidian", .sectionOpenInObsidian, enabled)
                .keyboardShortcut(current.row == .section ? KeyboardShortcut("o", modifiers: [.command, .shift]) : nil)
            item("Show in Finder", .sectionShowInFinder, enabled)
            item("New Terminal at Folder", .sectionNewTerminalAtFolder, enabled)

            Divider()

            item("Remove Section…", .removeSection, enabled)
        }
    }

    // MARK: - Functions

    func item(_ title: String, _ item: SubjectMenuRules.Item, _ enabled: Set<SubjectMenuRules.Item>) -> some View {
        return Button(title) {
            run(item)
        }
        .disabled(!enabled.contains(item))
    }

    func run(_ item: SubjectMenuRules.Item) {
        MenuRoute.run(item, in: workspace?.window) {
            switch item {
            case .preview, .deploy, .openInBrowser:
                site?.perform(item)
            default:
                sidebar?.perform(item)
            }
        }
    }
}

/// Revise With ▸ Claude… / Codex… / Local AI Assistant…, in both subject
/// menus. Each target is DRAWN only when this Mac has it (presence) and
/// ENABLED by the rule; the submenu itself is left out when there is
/// nothing to put in it. The reasons an item is greyed (#458) follow it.
struct ReviseWithMenu: View {

    // MARK: - Stored properties

    var presence: OutsideAssistantPresence
    var claude: SubjectMenuRules.Item
    var codex: SubjectMenuRules.Item
    var localAssistant: SubjectMenuRules.Item
    var enabled: Set<SubjectMenuRules.Item>
    var notes: [String]
    var run: (SubjectMenuRules.Item) -> Void

    // MARK: - Body

    var body: some View {
        if presence.anyReviseTargetExists {
            Menu("Revise With") {
                if presence.claudeIsInstalled {
                    Button("Claude…") {
                        run(claude)
                    }
                    .disabled(!enabled.contains(claude))
                }
                if presence.codexIsInstalled {
                    Button("Codex…") {
                        run(codex)
                    }
                    .disabled(!enabled.contains(codex))
                }
                if presence.localAssistantCanRun {
                    Button("Local AI Assistant…") {
                        run(localAssistant)
                    }
                    .disabled(!enabled.contains(localAssistant))
                }
                ForEach(notes, id: \.self) { note in
                    Text(note)
                }
            }
        }
    }
}
