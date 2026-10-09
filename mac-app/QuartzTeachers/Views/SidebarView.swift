import AppKit
import SwiftUI

/// The "Courses & Clubs" sidebar: each course expands to show its
/// sections, with the add/remove/filter bar macOS lists conventionally
/// carry along their bottom edge.
struct SidebarView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    /// Opens the assistant, which is a window of its own rather than a sheet.
    @Environment(\.openWindow) var openWindow

    /// The courses list's accessibility identifier, named here because
    /// `SidebarReturnKey` looks for it to decide whether Return belongs to
    /// this list. Two spellings of it would be two features, one of which
    /// silently does nothing.
    static let listIdentifier: String = "coursesSidebar"

    /// Watches for Return, which SwiftUI cannot see here — the type says
    /// why.
    @State var returnKey: SidebarReturnKey = SidebarReturnKey()

    /// The item the remove button is asking about, if any.
    @State var removalRequest: RemovalRequest?

    /// A failure while archiving, shown as an alert.
    @State var removalProblem: String?

    /// The footer's height, growing with the system text size so the bar
    /// and the path bar opposite it stay the same height.
    @ScaledMetric(relativeTo: .body) var scaledFooterHeight: CGFloat = WindowChrome.footerHeight

    // The Archived group and the course disclosure triangles keep their
    // open/closed state on the WINDOW's model, not view-locally: the
    // window remembers them with its folder, so a restored window shows
    // the same courses unfolded that were being worked on.

    /// The course "Add Section…" was chosen on, while its sheet is up.
    @State var addSectionCourse: Course?

    /// Why "Add Section…" refused at the click (#458), shown as an alert.
    @State var addSectionRefusal: String?

    /// The course a "Keep a Copy for Reference…" sheet is open for.
    @State var keepACopyCourse: Course?

    /// The course a "Copy a Page from This Course…" sheet is open for.
    ///
    /// Any course — live or kept for reference. It is the SOURCE, and the
    /// sheet only ever reads it: a reference course is kept to be read, so
    /// copying a page OUT of one is the point of having it rather than an
    /// exception to its being frozen.
    @State var copyPageCourse: Course?


    /// The section "Schedule Deploy…" was chosen on, while its sheet is up.
    @State var scheduleRequest: ScheduledDeployRequest?

    /// The section "Get Ready for the Start of the Year…" (or its undo) was
    /// chosen on, while its sheet is up (#96).
    @State var startOfYearRequest: StartOfYearRequest?

    /// The links checklist opened from the section's menu (#379), so Not Now
    /// is not a one-way door.
    @State var linksChecklistFromTheMenu: LinksChecklistSheetModel?

    /// The scheduled deploy the teacher is being asked about cancelling.
    @State var cancelScheduleRequest: ScheduledDeployRequest?

    /// Bumped whenever a deploy is scheduled or cancelled. The rows read
    /// launchd rather than a stored list, and nothing about a file in
    /// `~/Library/LaunchAgents` is observable, so this is what tells the
    /// sidebar its answer has gone stale.
    @State var scheduleGeneration: Int = 0

    /// Why a scheduled deploy could not be cancelled, shown as an alert.
    @State var scheduleProblem: String?

    /// Why a Claude session could not be started, shown as an alert.
    @State var claudeProblem: String?

    /// Why a Codex session could not be started, shown as an alert.
    ///
    /// A second property rather than one shared "outside assistant" one,
    /// because the alert TITLE names the assistant, and a teacher who has both
    /// installed should be told which of them did not open.
    @State var codexProblem: String?

    /// Why a Revise item refused at the click (#458) — a Claude or Codex session open
    /// on the course elsewhere, or the in-app assistant open on it — shown
    /// as an alert.
    @State var reviseRefusal: WorkspaceModel.ReviseRefusal?

    // MARK: - Body

    var body: some View {
        @Bindable var workspace = workspace

        // Read HERE, in the sidebar's own body, and handed to each row as a
        // plain `Bool`. The rows a `List` builds are lazy, so keeping the
        // dependency on the model at this level — where the body is plainly
        // re-evaluated — leaves nothing about the redraw to work out.
        let renamingCourseCode: String? = workspace.renamingCourseCode

        VStack(spacing: 0) {
            List(selection: $workspace.selection) {
                Section("Courses & Clubs") {
                    ForEach(workspace.teachingCourses) { course in
                        DisclosureGroup(isExpanded: expansionBinding(for: course.code)) {
                            ForEach(course.sectionNumbers, id: \.self) { sectionNumber in
                                // Asked of launchd during the row's render,
                                // not kept as a note of ours: the teacher can
                                // delete the agent themselves, and a clock
                                // promising a deploy that will never happen is
                                // worse than no clock. `scheduleGeneration`
                                // makes the row read it again after a change.
                                let scheduledFor: Date? = scheduledDeployTime(
                                    courseCode: course.code,
                                    sectionNumber: sectionNumber,
                                    generation: scheduleGeneration
                                )
                                // Read from disk during the row's render, the
                                // same way the clock is asked of launchd: a
                                // teacher who fixes the problem or dismisses
                                // the notice should see the badge go without
                                // the sidebar being rebuilt.
                                //
                                // The counter is the WATCHER's, which is what
                                // makes this badge and the section's own band
                                // move together in both directions: it moves
                                // when a run finishes (the folder changed) as
                                // well as when the teacher dismisses a notice.
                                let stoppedPublish: ScheduledPublishOutcome.Stopped? =
                                    stoppedPublishBadge(
                                        courseCode: course.code,
                                        sectionNumber: sectionNumber,
                                        generation: ScheduledPublishWatcher.shared.generation
                                    )
                                sectionRowLabel(
                                    sectionNumber: sectionNumber,
                                    scheduledFor: scheduledFor,
                                    stoppedPublish: stoppedPublish
                                )
                                    .tag(SidebarSelection.section(course.code, sectionNumber))
                                    .accessibilityIdentifier("sidebar-\(course.code)-section\(sectionNumber)")
                                    .contextMenu {
                                        sectionRowMenu(course: course, sectionNumber: sectionNumber, scheduledFor: scheduledFor)
                                    }
                            }
                        } label: {
                            // Read the busy state HERE, during the row's
                            // render: the registries are observable, so
                            // the row redraws — menu included — the
                            // moment a preview or publish starts or
                            // stops. Reading it only inside the menu
                            // closure left the menu showing the state
                            // from whenever the row last drew.
                            let busyReason: String? = busyReason(for: course)
                            // Rename and Add Section… wait for a Claude or
                            // Codex session open on the course as well (#458);
                            // Keep a Copy only reads it, so it does not.
                            let structuralReason: String? = structuralHoldReason(for: course)
                            CourseRowLabel(
                                course: course,
                                isBeingRenamed: renamingCourseCode == course.code,
                                isBeingCopied: workspace.isBeingCopied(course.code)
                            )
                                .tag(SidebarSelection.course(course.code))
                                .accessibilityIdentifier("sidebar-\(course.code)")
                                .contextMenu {
                                    courseRowMenu(course: course, busyReason: busyReason, structuralReason: structuralReason)
                                }
                        }
                    }
                }

                referenceCoursesSection

                if !workspace.backupItems.isEmpty {
                    // Saved copies of whole courses, above Archived: these
                    // are safety nets the teacher made on purpose, not
                    // things put away.
                    Section(isExpanded: $workspace.isShowingBackups) {
                        // Every backup at once: what they take, and a way to
                        // delete several (#242). First, so it is found before
                        // the list it summarises.
                        Label("All Backups", systemImage: "square.stack.3d.up")
                            .tag(SidebarSelection.allBackups)
                            .accessibilityIdentifier("allBackups")
                        ForEach(workspace.backupItems) { item in
                            Label(item.title, systemImage: item.symbolName)
                                .help(backupHelp(for: item))
                                .tag(SidebarSelection.backup(item.id))
                                .accessibilityIdentifier("backup-\(item.id)")
                                .contextMenu {
                                    Button("Restore…", systemImage: "arrow.uturn.backward") {
                                        select(SidebarSelection.backup(item.id))
                                        workspace.backupRestoreRequest = item
                                    }
                                    .disabled(workspace.isBeingCopied(item.courseCode))
                                    Button("Show in Finder", systemImage: "finder") {
                                        select(SidebarSelection.backup(item.id))
                                        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                                    }
                                    Divider()
                                    Button("Delete Backup…", systemImage: "trash", role: .destructive) {
                                        select(SidebarSelection.backup(item.id))
                                        workspace.requestDeleteBackup(item)
                                    }
                                }
                        }
                    } header: {
                        // The total beside the name, once every backup has
                        // been measured — the space is what a teacher could
                        // not see before (#242).
                        HStack {
                            Text("Backups")
                            Spacer()
                            if workspace.backupSpace.isComplete {
                                Text(BackupSizes.description(ofBytes: workspace.backupSpace.totalBytes))
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("backupsTotal")
                            }
                        }
                        // `.contain` (#353). A List section's header is merged into ONE
                        // static text, so two identifiers cannot both reach the tree:
                        // with an identifier on the header as well, the text read
                        // "backupsGroup-backupsGroup" and `backupsTotal` was dead (read
                        // off the real tree, 2026-09-26). The header's own was dropped;
                        // nothing read it.
                        .accessibilityElement(children: .contain)
                    }
                }

                if !workspace.archivedItems.isEmpty {
                    // A collapsible section header, the way Finder's
                    // "Locations" behaves: the chevron appears on hover, and
                    // the rows beneath read like any other sidebar row.
                    Section(isExpanded: $workspace.isShowingArchived) {
                        ForEach(workspace.archivedItems) { item in
                            Label(item.title, systemImage: item.symbolName)
                                .help(item.subtitle)
                                .tag(SidebarSelection.archived(item.id))
                                .accessibilityIdentifier("archived-\(item.id)")
                                .contextMenu {
                                    Button("Restore…", systemImage: "arrow.uturn.backward") {
                                        select(SidebarSelection.archived(item.id))
                                        workspace.restoreRequest = item
                                    }
                                    Button("Show in Finder", systemImage: "finder") {
                                        select(SidebarSelection.archived(item.id))
                                        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                                    }
                                    Divider()
                                    Button("Delete Archive…", systemImage: "trash", role: .destructive) {
                                        select(SidebarSelection.archived(item.id))
                                        workspace.archiveDeleteRequest = item
                                    }
                                }
                        }
                    } header: {
                        Text("Archived")
                            .accessibilityIdentifier("archivedGroup")
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier(SidebarView.listIdentifier)
            // Delete asks to remove the selected row, through the menu
            // item's own rule and closure (#457, the HIG sweep).
            .onDeleteCommand(perform: deleteKeyPressed)
            // Return renames the selected course, as it does in Finder.
            // `.onKeyPress(.return)` was tried here first and is never
            // called — see `SidebarReturnKey` for what actually happens to
            // the key and why the menu item has no shortcut.
            .background(WindowAccessor { window in
                returnKey.window = window
            })
            .onAppear {
                returnKey.start {
                    return beginRenamingFromTheKeyboard()
                }
            }
            .onDisappear {
                returnKey.stop()
            }
            .onChange(of: workspace.expandedCourseCodes) {
                WorkspaceModel.rememberOpenFolders()
            }
            .onChange(of: workspace.isShowingArchived) {
                WorkspaceModel.rememberOpenFolders()
            }
            .onChange(of: workspace.isShowingBackups) {
                WorkspaceModel.rememberOpenFolders()
            }
            .onChange(of: workspace.selection) {
                WorkspaceModel.rememberOpenFolders()
                // Clicking a row moves the keyboard to the sidebar, the way
                // a source list behaves everywhere else on this platform.
                //
                // Deferred one turn, and that deferral papers over a FOCUS
                // RACE rather than fixing one: the detail pane rebuilds for
                // the newly selected course and its first text field takes
                // SwiftUI's initial focus on the way up, so this waits for
                // that to land and then takes the keyboard back. It is a
                // Task on the main actor rather than a main-queue block only
                // because that is the house style — the two run at the same
                // point, and the race is unchanged (never `Task.immediate`,
                // which runs inline and would lose to the detail pane).
                //
                // The race has a second loser, measured in #293: a rename
                // field opened in the SAME turn as a selection change takes
                // focus first and then loses it to this, and with the app
                // active it commits the unchanged code and closes (2 of 2
                // runs with the test host frontmost; 4 of 4 passed with it
                // in the background). The trace was the rename test's own
                // selection-then-open in one turn. No teacher path does both
                // in one turn — a click and the Return or menu item that
                // opens the field are separate events — so the test was
                // changed rather than this.
                Task { @MainActor in
                    returnKey.focusTheCoursesList()
                }
            }
            .overlay {
                if showsNoFilterMatches {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "magnifyingglass")
                    } description: {
                        Text("No course or club matches “\(workspace.filterText)”.")
                    }
                    .accessibilityIdentifier("noFilterMatchesMessage")
                }
            }

            // The one line the background warm-up ever shows (bundle B): no
            // window, no progress bar, nothing to press. It goes when the
            // builder is ready, or when getting it ready did not work out —
            // then the first preview does it the old way, saying nothing here.
            if BuilderWarmUp.shared.isGettingReady {
                gettingReadyLine
            }

            Divider()

            bottomBar
                // What the menu bar's Course and Section menus read (#457).
                // Here rather than on the stack, whose modifier chain is
                // already as long as the type checker will take.
                .focusedSceneValue(\.sidebarMenu, menuCommands)
        }
        .alert(
            removalRequest?.title ?? "",
            isPresented: removalRequestIsPresented,
            presenting: removalRequest
        ) { request in
            Button("Remove", role: .destructive) {
                Task { await performRemoval(request) }
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { request in
            Text(request.message)
        }
        .alert(
            "Restore \(workspace.restoreRequest?.title ?? "")?",
            isPresented: restoreRequestIsPresented,
            presenting: workspace.restoreRequest
        ) { item in
            Button("Restore") {
                workspace.restore(item)
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { item in
            Text(restoreMessage(for: item))
        }
        .alert(
            "Restore \(workspace.backupRestoreRequest?.courseCode ?? "") from this backup?",
            isPresented: backupRestoreRequestIsPresented,
            presenting: workspace.backupRestoreRequest
        ) { item in
            Button("Restore") {
                Task { await workspace.restoreBackup(item) }
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { item in
            Text("""
                \(item.courseCode) goes back to how it was when this backup was made:

                \(item.whenDescription)

                Anything added since then isn’t in the backup.

                Nothing is lost, though: the version you have right now moves to Archived, at the bottom of the sidebar, where you can get it back.

                This backup is kept.
                """)
        }
        .alert(
            "Delete this backup of \(workspace.backupDeleteRequest?.courseCode ?? "")?",
            isPresented: backupDeleteRequestIsPresented,
            presenting: workspace.backupDeleteRequest
        ) { item in
            Button("Delete", role: .destructive) {
                workspace.deleteBackup(item)
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { item in
            Text(singleBackupDeleteMessage(for: item))
        }
        .alert(
            "Delete this archive of \(workspace.archiveDeleteRequest?.title ?? "")?",
            isPresented: archiveDeleteRequestIsPresented,
            presenting: workspace.archiveDeleteRequest
        ) { item in
            Button("Delete", role: .destructive) {
                workspace.deleteArchive(item)
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { item in
            // The app knows what deleting would leave behind — the live
            // course, another archive or backup, or nothing at all — so
            // the warning states a fact, not an "if".
            switch workspace.archiveStanding(item) {
            case .liveInCourses:
                Text("""
                    This deletes the archive for good — nothing is kept.

                    \(item.title) itself is not touched — it’s still in Courses & Clubs.
                    """)
            case .otherCopiesRemain:
                Text("""
                    This deletes the archive for good — nothing is kept.

                    \(item.title) isn’t in Courses & Clubs any more, but this isn’t its only copy — another archive or backup of it remains.
                    """)
            case .onlyRemainingCopy:
                Text("""
                    This deletes the archive for good — nothing is kept.

                    \(item.title) isn’t in Courses & Clubs any more, and this archive is its only remaining copy.
                    """)
            }
        }
        .alert("Could not do that", isPresented: backupProblemBinding) {
            Button("OK") {
                workspace.backupProblem = nil
            }
        } message: {
            Text(workspace.backupProblem ?? "")
        }
        .alert("Could not restore", isPresented: restoreProblemBinding) {
            Button("OK") {
                workspace.restoreProblem = nil
            }
        } message: {
            Text(workspace.restoreProblem ?? "")
        }
        .alert("Could not remove", isPresented: removalProblemBinding) {
            Button("OK") {
                removalProblem = nil
            }
        } message: {
            Text(removalProblem ?? "")
        }
        .modifier(OutsideAgentAlerts(
            claudeProblem: $claudeProblem, codexProblem: $codexProblem, reviseRefusal: $reviseRefusal
        ))
        .modifier(OutsideSessionHolds(workspace: workspace, addSectionRefusal: $addSectionRefusal))
        .sheet(item: $keepACopyCourse) { course in
            KeepACopyForReferenceSheet(course: course) { folderName in
                workspace.reloadCourses()
                workspace.isShowingReferenceCourses = true
                workspace.selection = SidebarSelection.course(folderName)
            }
        }
        // Importing last year's courses starts with a folder chooser, and the
        // sheet that follows it sits here rather than in the window's own
        // view because it is the same act as "Keep a Copy for Reference…"
        // above, from a different source. It is also a second `.fileImporter`
        // in the app, and two of them on one view is a shape SwiftUI has been
        // known to present only the first of — so this one lives on its own
        // view, which the window's folder chooser does too.
        .modifier(ImportCoursesForReferencePresenter())
        .sheet(isPresented: schoolYearSheetIsPresented) {
            if let course = schoolYearCourse {
                SetSchoolYearSheet(course: course) {
                    workspace.reloadCourses()
                }
            }
        }
        .sheet(item: $copyPageCourse) { course in
            CopyPageSheet(source: course)
        }
        .sheet(item: $addSectionCourse) { course in
            AddSectionSheet(course: course) { sectionNumber in
                workspace.reloadCourses()
                workspace.selection = SidebarSelection.section(course.code, sectionNumber)
            }
        }
        .sheet(item: $linksChecklistFromTheMenu) { model in
            LinksChecklistSheet(model: model)
        }
        .sheet(item: $startOfYearRequest) { request in
            if let workspaceURL = workspace.workspaceURL {
                StartOfYearSheet(model: StartOfYearSheetModel(
                    course: request.course,
                    sectionNumber: request.sectionNumber,
                    workspaceURL: workspaceURL,
                    mode: request.mode
                ))
            }
        }
        .sheet(item: $scheduleRequest) { request in
            if let workspaceURL = workspace.workspaceURL {
                ScheduleDeploySheet(
                    course: request.course,
                    sectionNumber: request.sectionNumber,
                    workspaceURL: workspaceURL
                ) {
                    scheduleGeneration += 1
                }
            }
        }
        .alert(
            "Cancel this scheduled deploy?",
            isPresented: cancelScheduleRequestIsPresented,
            presenting: cancelScheduleRequest
        ) { request in
            Button("Cancel It", role: .destructive) {
                cancelScheduledDeploy(request)
            }
            Button("Leave It Scheduled", role: .cancel) {
            }
        } message: { request in
            Text(cancelMessage(for: request))
        }
        .alert("Could not change the scheduled deploy", isPresented: scheduleProblemBinding) {
            Button("OK") {
                scheduleProblem = nil
            }
        } message: {
            Text(scheduleProblem ?? "")
        }
        // Asked BEFORE the rename, because the answer decides whether
        // Obsidian is closed first. Two buttons on purpose: there is no
        // third answer that leaves Obsidian showing the truth.
        .alert(
            "\(workspace.obsidianRenameRequest?.course.code ?? "") is open in Obsidian",
            isPresented: obsidianRenameRequestIsPresented,
            presenting: workspace.obsidianRenameRequest
        ) { request in
            Button("Close Obsidian and Rename") {
                workspace.obsidianRenameRequest = nil
                Task {
                    await workspace.renameClosingObsidian(request)
                }
            }
            Button("Cancel", role: .cancel) {
                workspace.obsidianRenameRequest = nil
            }
        } message: { request in
            Text(CourseRenamer.obsidianQuestion(openVaultCount: request.openVaultPaths.count))
        }
        .alert("Could not rename", isPresented: renameProblemBinding) {
            Button("OK") {
                workspace.renameProblem = nil
            }
        } message: {
            Text(workspace.renameProblem ?? "")
        }
        // Shown only when the rename had a consequence beyond itself. An
        // ordinary rename says nothing at all: a teacher who has just watched
        // the row change does not need an alert to confirm it.
        .alert(
            workspace.renameNotice?.title ?? "",
            isPresented: renameNoticeIsPresented,
            presenting: workspace.renameNotice
        ) { _ in
            Button("OK") {
                workspace.renameNotice = nil
            }
        } message: { notice in
            Text(notice.message)
        }
    }



    /// Whether this section has a stopped scheduled publish to warn about.
    ///
    /// `generation` is unused inside and that is the point: naming it as an
    /// argument is what makes SwiftUI re-read the disk when it changes, which
    /// is how the badge disappears the moment the teacher dismisses the notice
    /// in the section view. `scheduledDeployTime` beside it takes one for the
    /// identical reason.
    func stoppedPublishBadge(
        courseCode: String,
        sectionNumber: Int,
        generation: Int
    ) -> ScheduledPublishOutcome.Stopped? {
        // THIS working folder's record only (#237): the same section in
        // another working folder keeps its own, and its failure is not this
        // folder's to show.
        guard let workingFolderURL = workspace.workspaceURL else {
            return nil
        }
        let outcome: ScheduledPublishOutcome.Stopped? = ScheduledPublishOutcome.stopped(
            inHomeFolder: ScheduledDeploy.homeForScheduledNotes,
            course: courseCode,
            section: sectionNumber,
            workingFolder: workingFolderURL
        )
        // Only a failure earns a badge. A success is news rather than a
        // problem, and a badge beside every section that published fine
        // overnight is a badge nobody reads by Wednesday. The sentence inside
        // the section still says so.
        guard let outcome, outcome.kind.needsAttention else {
            return nil
        }
        return outcome
    }

    /// A section's row, wearing a clock when it is set to deploy on its own
    /// and a warning when a publish that was set to happen on its own did not
    /// get through.
    ///
    /// The warning is here rather than only inside the section because a
    /// teacher who does not know which section failed cannot open the right
    /// one — and not knowing is the entire problem this feature exists for.
    @ViewBuilder
    func sectionRowLabel(
        sectionNumber: Int,
        scheduledFor: Date?,
        stoppedPublish: ScheduledPublishOutcome.Stopped? = nil
    ) -> some View {
        if scheduledFor != nil || stoppedPublish != nil {
            HStack {
                Label("Section \(sectionNumber)", systemImage: "doc.richtext")
                Spacer()
                if stoppedPublish != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier(
                            "stoppedPublishBadge-section\(sectionNumber)"
                        )
                        // The same sentence twice, on purpose: hovering and
                        // hearing the row should tell a teacher the same thing.
                        // An orange triangle alone says "something", and a
                        // teacher who cannot find out what without clicking is
                        // being asked to guess.
                        .help(SidebarView.stoppedPublishTooltip())
                        .accessibilityLabel(Text(SidebarView.stoppedPublishTooltip()))
                }
                if let scheduledFor {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "scheduledDeployBadge-section\(sectionNumber)"
                        )
                        .help(SidebarView.scheduledDeployTooltip(for: scheduledFor))
                }
            }
        } else {
            Label("Section \(sectionNumber)", systemImage: "doc.richtext")
        }
    }

    /// How big the footer's +/- targets are. Named so a test can check the
    /// buttons really are this size on screen.
    static let footerButtonSize: CGSize = CGSize(width: 26, height: 24)

    /// The glyph and its target at the SYSTEM text size, scaled from the
    /// base sizes above. A fixed point size ignores Accessibility ▸ Display
    /// ▸ Text size entirely, which would leave someone who enlarges text
    /// with the same small target they had before.
    @ScaledMetric(relativeTo: .body) var scaledGlyphSize: CGFloat = SidebarView.footerGlyphSize
    @ScaledMetric(relativeTo: .body) var scaledButtonWidth: CGFloat = SidebarView.footerButtonSize.width
    @ScaledMetric(relativeTo: .body) var scaledButtonHeight: CGFloat = SidebarView.footerButtonSize.height

    /// How large the +/- glyphs are drawn. SwiftUI's default renders these a
    /// little smaller than the same buttons elsewhere on the system — Xcode's
    /// list footers, for one — so the size is stated rather than inherited.
    static let footerGlyphSize: CGFloat = 15

    /// The background warm-up's status line (`builderWarmUp.wording.statusLine`).
    var gettingReadyLine: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(BuilderWarmUp.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("builderWarmUpStatusLine")
    }

    /// Add, remove, and filter — the standard macOS list footer.
    var bottomBar: some View {
        @Bindable var workspace = workspace

        return HStack(spacing: 0) {
            // A bare glyph is a tiny target — the minus is barely a few
            // pixels tall. The frame gives each button a real area and
            // contentShape makes the whole of it clickable.
            //
            // Both must be INSIDE the button's label: applied to the button
            // itself, contentShape only reshapes bounds that are already
            // just the glyph, which is why it appeared to do nothing.
            Button {
                workspace.isShowingNewCourseWizard = true
            } label: {
                Label("Add Course or Club", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: scaledGlyphSize))
                    .frame(width: scaledButtonWidth, height: scaledButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // Greyed while the folder's tools are being copied, or that copy
            // failed (#476), with the reason as its help; the creator refuses
            // too, before anything is written, for every other way in.
            .disabled(workspace.folderIsGettingReady)
            .help(workspace.folderReadinessReason ?? "Add a course or club")
            .accessibilityIdentifier("addCourseButton")

            Button {
                prepareRemoval()
            } label: {
                Label("Remove Selected", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: scaledGlyphSize))
                    .frame(width: scaledButtonWidth, height: scaledButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // An archived item is already put away, so there is nothing
            // for this button to do while one is selected.
            // Nor while the course is being copied (#351): a second archive of
            // a folder already being put away.
            .disabled(workspace.selectedCourse == nil
                      || workspace.isBeingCopied(workspace.selectedCourse?.code ?? ""))
            .help("Remove the selected course or section")
            .accessibilityIdentifier("removeSelectedButton")
            .padding(.trailing, 5)

            TextField("Filter", text: $workspace.filterText)
                .borderedTextField()
                .controlSize(.small)
                .accessibilityIdentifier("courseFilterField")
        }
        .padding(.horizontal, 8)
        .frame(height: scaledFooterHeight)
    }

    // MARK: - Computed properties

    /// True when the filter has hidden everything — as against there being
    /// nothing to show in the first place, which the window's own empty
    /// state already explains.
    var showsNoFilterMatches: Bool {
        return SidebarView.showsNoFilterMatches(
            courseCount: workspace.courses.count,
            matchCount: workspace.filteredCourses.count,
            filterText: workspace.filterText
        )
    }

    static func showsNoFilterMatches(courseCount: Int, matchCount: Int, filterText: String) -> Bool {
        if filterText.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        if courseCount == 0 {
            return false
        }
        return matchCount == 0
    }

    /// What restoring this item will do, said plainly.
    func restoreMessage(for item: ArchivedItem) -> String {
        if let sectionNumber = item.sectionNumber {
            return "Section \(sectionNumber) will be put back into \(item.courseCode), and will no longer be listed as archived."
        }
        return "\(item.courseCode) will be put back into Courses & Clubs, and will no longer be listed as archived."
    }

    var removalRequestIsPresented: Binding<Bool> {
        return Binding(
            get: { removalRequest != nil },
            set: { isPresented in
                if !isPresented {
                    removalRequest = nil
                }
            }
        )
    }

    var restoreRequestIsPresented: Binding<Bool> {
        return Binding(
            get: { workspace.restoreRequest != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.restoreRequest = nil
                }
            }
        )
    }

    var restoreProblemBinding: Binding<Bool> {
        return Binding(
            get: { workspace.restoreProblem != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.restoreProblem = nil
                }
            }
        )
    }

    var backupRestoreRequestIsPresented: Binding<Bool> {
        return Binding(
            get: { workspace.backupRestoreRequest != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.backupRestoreRequest = nil
                }
            }
        )
    }

    /// A backup's tooltip: when, who, and — once measured — what it takes.
    func backupHelp(for item: BackupItem) -> String {
        guard let size = workspace.sizeDescription(of: item) else {
            return item.subtitle
        }
        return item.subtitle + " · " + size
    }

    /// The single delete's confirmation, with what the backup takes once it
    /// has been measured.
    func singleBackupDeleteMessage(for item: BackupItem) -> String {
        var message: String = "This deletes the backup for good — unlike removing a course, nothing is kept."
        if let size = workspace.backupSizes[item.id] {
            message += " It takes \(BackupSizes.description(ofBytes: size))."
        }
        message += "\n\n\(item.courseCode) itself is not touched."
        return message
    }

    var backupDeleteRequestIsPresented: Binding<Bool> {
        return Binding(
            get: { workspace.backupDeleteRequest != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.backupDeleteRequest = nil
                }
            }
        )
    }

    var archiveDeleteRequestIsPresented: Binding<Bool> {
        return Binding(
            get: { workspace.archiveDeleteRequest != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.archiveDeleteRequest = nil
                }
            }
        )
    }

    var backupProblemBinding: Binding<Bool> {
        return Binding(
            get: { workspace.backupProblem != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.backupProblem = nil
                }
            }
        )
    }

    var removalProblemBinding: Binding<Bool> {
        return Binding(
            get: { removalProblem != nil },
            set: { isPresented in
                if !isPresented {
                    removalProblem = nil
                }
            }
        )
    }

    var cancelScheduleRequestIsPresented: Binding<Bool> {
        return Binding(
            get: { cancelScheduleRequest != nil },
            set: { isPresented in
                if !isPresented {
                    cancelScheduleRequest = nil
                }
            }
        )
    }

    var obsidianRenameRequestIsPresented: Binding<Bool> {
        return Binding(
            get: { workspace.obsidianRenameRequest != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.obsidianRenameRequest = nil
                }
            }
        )
    }

    var renameProblemBinding: Binding<Bool> {
        return Binding(
            get: { workspace.renameProblem != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.renameProblem = nil
                }
            }
        )
    }

    var renameNoticeIsPresented: Binding<Bool> {
        return Binding(
            get: { workspace.renameNotice != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.renameNotice = nil
                }
            }
        )
    }

    var scheduleProblemBinding: Binding<Bool> {
        return Binding(
            get: { scheduleProblem != nil },
            set: { isPresented in
                if !isPresented {
                    scheduleProblem = nil
                }
            }
        )
    }

    // MARK: - Functions

    /// When this section next deploys on its own, or nil when nothing is
    /// scheduled.
    ///
    /// `generation` is not used: it is here so that reading it during the
    /// row's render makes SwiftUI redraw the row when a deploy is
    /// scheduled or cancelled. Without it the clock would appear only
    /// after something else happened to redraw the sidebar.
    func scheduledDeployTime(courseCode: String, sectionNumber: Int, generation: Int) -> Date? {
        _ = generation
        guard let workingFolderURL = workspace.workspaceURL else {
            return nil
        }
        return ScheduledDeploy.nextRun(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            inWorkingFolder: workingFolderURL
        )
    }

    /// What the orange triangle beside a section means, said in full on hover
    /// — and the same sentence again for anyone listening rather than looking.
    ///
    /// One sentence for all three ways a scheduled publish can stop: from the
    /// sidebar they mean the same thing to a teacher, which is that the site
    /// is not what they think it is. WHICH way it stopped, and when, is in the
    /// section itself, which is where the sentence sends them.
    ///
    /// It names no date deliberately. The badge can stand for days if nobody
    /// dismisses it, and a hover that said "on Tuesday" would have to be right
    /// about WHICH Tuesday; the section's own notice carries the date in full.
    static func stoppedPublishTooltip() -> String {
        return "A deploy that was set to happen on its own did not get through. "
             + "Open this section to see what happened."
    }

    /// What the clock beside a section means, said in full on hover.
    static func scheduledDeployTooltip(for when: Date) -> String {
        return "Deploying on its own at \(ScheduledDeploy.timeText(when)) on \(ScheduledDeploy.dayText(when)). Right-click to cancel. This Mac must be on and awake."
    }

    /// What cancelling would mean, stated rather than implied.
    func cancelMessage(for request: ScheduledDeployRequest) -> String {
        guard let when = request.when else {
            return "This section will no longer deploy on its own."
        }
        return "\(request.course.displayCode) Section \(request.sectionNumber) is set to deploy on its own at \(ScheduledDeploy.timeText(when)) on \(ScheduledDeploy.dayText(when)). Cancelling means it will not go out then, and the site stays as it is until you deploy it yourself."
    }

    func cancelScheduledDeploy(_ request: ScheduledDeployRequest) {
        guard let workspaceURL = workspace.workspaceURL else {
            return
        }
        if let problem = ScheduledDeploy.cancelScheduledDeploy(
            courseCode: request.course.code,
            sectionNumber: request.sectionNumber,
            inWorkingFolder: workspaceURL
        ) {
            scheduleProblem = problem
        }
        scheduleGeneration += 1
    }

    /// "Copy a Page from This Course…" — on EVERY course row, live and kept
    /// for reference alike.
    ///
    /// It is the one act a frozen course still offers that produces
    /// something, and it is allowed for the same reason Preview and Back Up
    /// Now are: it READS this course and writes nothing to it. What it writes
    /// goes into a course the teacher teaches, which is chosen inside the
    /// sheet and is never a reference course.
    ///
    /// Drawn even when this course has no pages to copy: the sheet says so
    /// in its own words, and a menu item that appears and disappears with the
    /// contents of a folder is harder to find again than one that is always
    /// there.
    @ViewBuilder
    func copyAPageItem(course: Course, row: SidebarSelection) -> some View {
        Button(CopyPageWording.menuItem, systemImage: "doc.on.doc") {
            select(row)
            copyPageCourse = course
        }
        .accessibilityIdentifier("copyAPage-\(course.code)")
    }

    /// Opens the links checklist from the menu. An offer older than the
    /// course's newest change may be wrong, so the sheet says a preview is
    /// needed first rather than showing it (plan review, finding 15).
    func openTheLinksChecklist(course: Course, sectionNumber: Int) {
        guard let workspaceURL = workspace.workspaceURL,
              let read = LinksChecklistOffer.read(courseDirectory: course.directoryURL, section: sectionNumber) else {
            return
        }
        let answered: LinksChecklistAnswered? = LinksChecklistAnswered.read(
            courseDirectory: course.directoryURL, section: sectionNumber
        )
        var problem: String? = nil
        if CourseActivity.coursePublishIsRunning(folderPath: workspaceURL.path, courseCode: course.code) {
            problem = LinksChecklistWording.deployUnderWay(course: course.displayCode)
        } else if !LinksChecklistGate.isFresh(
            writtenAt: read.writtenAt, newestContentChange: BuildFreshness.newestContentDate(course: course)
        ) {
            problem = LinksChecklistWording.needsAPreviewFirst(
                course: course.displayCode, section: String(sectionNumber)
            )
        }
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: course, sectionNumber: sectionNumber, workspaceURL: workspaceURL,
            offer: read.offer, answered: answered, occasion: .fromTheMenu, problem: problem
        )
        if problem == nil && !model.rows.isEmpty {
            ActivityTrail.note(
                .linksChecklistOffered,
                LinksChecklistPublisher.offeredLine(model: model),
                course: course.code, section: sectionNumber
            )
        }
        linksChecklistFromTheMenu = model
    }

    /// "Get Ready for the Start of the Year…", and its undo while one is
    /// held (#96).
    @ViewBuilder
    func startOfYearItems(course: Course, sectionNumber: Int) -> some View {
        let deploying: Bool = isBeingDeployed(course)
        let row: SidebarSelection = SidebarSelection.section(course.code, sectionNumber)
        Button(StartOfYearWording.menuItem, systemImage: "moon.zzz") {
            select(row)
            startOfYearRequest = StartOfYearRequest(course: course, sectionNumber: sectionNumber, mode: .getReady)
        }
        .disabled(deploying)
        .accessibilityIdentifier("startOfYear-\(course.code)-section\(sectionNumber)")
        if let folder = workspace.workspaceURL,
           StartOfYearUndoRegistry.shared.entry(
               folderPath: folder.path, courseCode: course.code, sectionNumber: sectionNumber
           ) != nil {
            Button(StartOfYearWording.undoMenuItem, systemImage: "arrow.uturn.backward") {
                select(row)
                startOfYearRequest = StartOfYearRequest(course: course, sectionNumber: sectionNumber, mode: .undo)
            }
            .disabled(deploying)
            .accessibilityIdentifier("startOfYearUndo-\(course.code)-section\(sectionNumber)")
        }
        // The links checklist, on demand (#379): whenever the last build left
        // an offer. A course kept for reference never has one.
        if LinksChecklistOffer.read(courseDirectory: course.directoryURL, section: sectionNumber) != nil {
            Button(LinksChecklistWording.menuItem, systemImage: "link") {
                select(row)
                openTheLinksChecklist(course: course, sectionNumber: sectionNumber)
            }
            .disabled(deploying)
            .accessibilityIdentifier("linksChecklist-\(course.code)-section\(sectionNumber)")
        }
        if deploying {
            Text(CourseActivity.availableOnceDeployCompleted)
        }
    }

    /// Whether a deploy of this course is running from this app.
    func isBeingDeployed(_ course: Course) -> Bool {
        guard let folder = workspace.workspaceURL else {
            return false
        }
        return CourseActivity.coursePublishIsRunning(folderPath: folder.path, courseCode: course.code)
    }

    /// Why the course is busy — previewing or publishing, in any window
    /// showing this working folder — or nil when it isn't.
    func busyReason(for course: Course) -> String? {
        guard let workspaceURL = workspace.workspaceURL else {
            return nil
        }
        return CourseActivity.busyDescription(folderPath: workspaceURL.path, courseCode: course.code)
    }

    /// Why structural work on the course — Rename Course, Add Section… —
    /// must wait: `busyReason`, or a Claude or Codex session open on the course in
    /// another program (#458), read from the window's snapshot.
    func structuralHoldReason(for course: Course) -> String? {
        guard let workspaceURL = workspace.workspaceURL else {
            return nil
        }
        return CourseActivity.structuralHoldReason(
            folderPath: workspaceURL.path,
            courseCode: course.code,
            revisedElsewhere: workspace.isRevisedElsewhere(course.code)
        )
    }

    /// Why one Revise item cannot be used on this course right now, or nil
    /// (#458) — from the window's snapshot of other programs' sessions and
    /// the in-app assistant's claim, both observable.
    func reviseReason(_ item: CourseActivity.ReviseItem, course: Course, sectionNumber: Int?) -> String? {
        guard let folder = workspace.workspaceURL else {
            return nil
        }
        return CourseActivity.reviseUnavailableReason(
            item: item,
            folderPath: folder.path,
            courseCode: course.code,
            sectionNumber: sectionNumber,
            revisedElsewhere: workspace.isRevisedElsewhere(course.code),
            active: AssistActivity.active
        )
    }

    /// The line (or lines) under the Revise items saying why they are greyed
    /// — each distinct reason ONCE, for the items actually drawn, so a Claude or
    /// Codex session greying all three is one line rather than three (#458).
    @ViewBuilder
    func reviseNotes(course: Course, sectionNumber: Int?) -> some View {
        let notes: [String] = reviseNoteLines(course: course, sectionNumber: sectionNumber)
        ForEach(notes, id: \.self) { note in
            Text(note)
        }
    }

    /// The distinct reasons behind `reviseNotes`, in the items' order.
    func reviseNoteLines(course: Course, sectionNumber: Int?) -> [String] {
        var lines: [String] = []
        if course.isKeptForReference {
            return lines
        }
        var asked: [CourseActivity.ReviseItem] = []
        if ClaudeCodeLauncher.isAvailable {
            asked.append(.claude)
        }
        if CodexLauncher.isAvailable {
            asked.append(.codex)
        }
        if sectionNumber != nil && AssistHardwareBudget.current().canRunAssistant {
            asked.append(.localAssistant)
        }
        for item in asked {
            if let reason = reviseReason(item, course: course, sectionNumber: sectionNumber),
               !lines.contains(reason) {
                lines.append(reason)
            }
        }
        return lines
    }

    /// The open/closed state of one course's disclosure triangle, living
    /// on the window's model so restoration can bring it back.
    /// The "Reference Courses" group: courses kept to be read, never
    /// deployed, filed by the school year they were taught in.
    ///
    /// **Two levels of folding, and nothing is drawn that is empty.** The
    /// outer group appears only when there is at least one reference course;
    /// a year group appears only when it holds one. An empty "2023–24" is a
    /// row that teaches a teacher to stop reading the sidebar.
    ///
    /// The rows are deliberately plainer than a live course's: no scheduled
    /// deploy clock and no stopped-publish badge, because neither can exist
    /// on a course that is never deployed. That is not a simplification — it
    /// is the absence of two things this kind of course does not have.
    @ViewBuilder
    var referenceCoursesSection: some View {
        let groups: [WorkspaceModel.ReferenceYearGroup] = workspace.referenceYearGroups()
        if !groups.isEmpty {
            Section(isExpanded: referenceGroupBinding) {
                ForEach(groups) { group in
                    DisclosureGroup(isExpanded: referenceYearBinding(for: group.id)) {
                        ForEach(group.courses) { course in
                            referenceCourseRow(course)
                        }
                    } label: {
                        Label(group.title, systemImage: "calendar")
                            .accessibilityIdentifier("referenceYear-\(group.id)")
                    }
                }
            } header: {
                Text(ReferenceWording.groupTitle)
            }
        }
    }

    @ViewBuilder
    func referenceCourseRow(_ course: Course) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: course.code)) {
            ForEach(course.sectionNumbers, id: \.self) { sectionNumber in
                Label("Section \(sectionNumber)", systemImage: "book")
                    .tag(SidebarSelection.section(course.code, sectionNumber))
                    .accessibilityIdentifier("sidebar-\(course.code)-section\(sectionNumber)")
                    .contextMenu {
                        let row: SidebarSelection = SidebarSelection.section(course.code, sectionNumber)
                        openInObsidianItem(forReferenceCourse: course, sectionNumber: sectionNumber, row: row)
                        Divider()
                        folderMenuItems(for: course.sectionDirectoryURL(forSection: sectionNumber), row: row)
                    }
            }
        } label: {
            CourseRowLabel(course: course, isBeingRenamed: false, isBeingCopied: workspace.isBeingCopied(course.code))
                .tag(SidebarSelection.course(course.code))
                .accessibilityIdentifier("sidebar-\(course.code)")
                .contextMenu {
                    let row: SidebarSelection = SidebarSelection.course(course.code)
                    openInObsidianItem(forReferenceCourse: course, sectionNumber: nil, row: row)
                    Divider()
                    Button(ReferenceWording.setSchoolYearMenuItem, systemImage: "calendar") {
                        select(row)
                        workspace.schoolYearRequestCode = course.code
                    }
                    .accessibilityIdentifier("setSchoolYear-\(course.code)")
                    Divider()
                    copyAPageItem(course: course, row: row)
                    Divider()
                    // Backing up only READS the course, and a reference
                    // course restores as a reference course — the marker
                    // travels in its settings, and the restore locks it
                    // again.
                    Button("Back Up Now", systemImage: "clock.arrow.circlepath") {
                        select(row)
                        Task { await workspace.backUp(course) }
                    }
                    .disabled(workspace.isBeingCopied(course.code))
                    Divider()
                    folderMenuItems(for: course.directoryURL, row: row)
                    Divider()
                    removeItem("Remove Course…", course: course, row: row)
                }
        }
    }

    /// The reference course the "Set School Year…" sheet is for, looked up
    /// from the model's request.
    var schoolYearCourse: Course? {
        guard let code = workspace.schoolYearRequestCode else {
            return nil
        }
        for candidate in workspace.courses where candidate.code == code {
            return candidate
        }
        return nil
    }

    var schoolYearSheetIsPresented: Binding<Bool> {
        return Binding(
            get: { return schoolYearCourse != nil },
            set: { showing in
                if !showing {
                    workspace.schoolYearRequestCode = nil
                }
            }
        )
    }

    var referenceGroupBinding: Binding<Bool> {
        return Binding(
            get: { return workspace.isShowingReferenceCourses },
            set: { isOpen in
                workspace.isShowingReferenceCourses = isOpen
                WorkspaceModel.rememberOpenFolders()
            }
        )
    }

    func referenceYearBinding(for identifier: Int) -> Binding<Bool> {
        return Binding(
            get: { return workspace.expandedReferenceYears.contains(identifier) },
            set: { isOpen in
                if isOpen {
                    workspace.expandedReferenceYears.insert(identifier)
                } else {
                    workspace.expandedReferenceYears.remove(identifier)
                }
                WorkspaceModel.rememberOpenFolders()
            }
        )
    }

    func expansionBinding(for courseCode: String) -> Binding<Bool> {
        return Binding(
            get: { workspace.expandedCourseCodes.contains(courseCode) },
            set: { isOpen in
                if isOpen {
                    workspace.expandedCourseCodes.insert(courseCode)
                } else {
                    workspace.expandedCourseCodes.remove(courseCode)
                }
            }
        )
    }

    /// The editing action, set apart in its own menu section. The Obsidian
    /// vault is the COURSE folder even for a section row — the section is a
    /// subfolder within it, and Obsidian lands there. Through the one route
    /// every Open in Obsidian takes (`WorkspaceModel.openInObsidian`).
    @ViewBuilder
    func openInObsidianItem(course: Course, sectionNumber: Int?, row: SidebarSelection) -> some View {
        Button("Open in Obsidian", systemImage: "square.and.pencil") {
            select(row)
            workspace.openInObsidian(course: course, sectionNumber: sectionNumber)
        }
        .disabled(!FolderActions.obsidianIsInstalled)
    }

    /// The same item on a course kept for reference, with the calm note in
    /// front of it the first time.
    ///
    /// **In front of it, not after it**, which is the placement decision the
    /// Obsidian measurement forced: what Obsidian SHOWS a teacher who types
    /// into a locked page could not be measured, so silent loss is not ruled
    /// out — and a note that arrives only after they have typed would be the
    /// worst of both. Once per course is enough; after that the item opens
    /// Obsidian directly, like any other course's.
    @ViewBuilder
    func openInObsidianItem(forReferenceCourse course: Course, sectionNumber: Int?, row: SidebarSelection) -> some View {
        Button("Open in Obsidian", systemImage: "square.and.pencil") {
            select(row)
            // The one route (`WorkspaceModel.openInObsidian`), which locks
            // the pages again and asks for the note the first time.
            workspace.openInObsidian(course: course, sectionNumber: sectionNumber)
        }
        .disabled(!FolderActions.obsidianIsInstalled)
        .accessibilityIdentifier("openInObsidian-\(course.code)")
    }


    /// Opens a Claude Code session in a terminal, connected to this course
    /// through Plantoir's MCP server.
    ///
    /// Hidden when Claude Code is not installed — a teacher who does not have
    /// Claude should not be shown a menu item that opens onto an error.
    @ViewBuilder
    func reviseWithClaudeItem(course: Course, row: SidebarSelection) -> some View {
        // NOT offered on a reference course (decision s). The door's whole
        // purpose is changing a course, and a session opened on one that
        // cannot change would be an invitation to find that out by trying.
        // A LIVE course's session is told the reference courses exist
        // instead — see the greeting.
        if ClaudeCodeLauncher.isAvailable,
           !course.isKeptForReference,
           let folder = workspace.workspaceURL {
            Button(ClaudeCodeLauncher.menuItemTitle, systemImage: "sparkles") {
                select(row)
                reviseWithClaude(course: course, folder: folder)
            }
            .disabled(reviseReason(.claude, course: course, sectionNumber: nil) != nil)
            .accessibilityIdentifier("reviseWithClaude-\(course.code)")
        }
    }

    func reviseWithClaude(course: Course, folder: URL) {
        if let refusal = workspace.reviseRefusal(item: .claude, courseCode: course.code, sectionNumber: nil) {
            reviseRefusal = refusal
            return
        }
        if ClaudeCodeLauncher.open(
            workspacePath: folder.path,
            courseCode: course.code,
            courseName: course.configuration.courseName,
            referenceCourses: ClaudeCodeLauncher.referenceCoursesToMention(
                for: course, among: workspace.courses
            )
        ) {
            return
        }
        claudeProblem = ClaudeCodeLauncher.couldNotStartSentence(courseCode: course.code)
    }

    /// Opens a Codex session in a terminal, connected to this course through
    /// Plantoir's MCP server — the same door as the one above, for the other
    /// assistant a teacher may already have.
    ///
    /// Hidden when Codex is not installed, and hidden INDEPENDENTLY of the
    /// Claude item: a teacher with one of the two sees one item, a teacher
    /// with both sees both, and a teacher with neither sees no sign that
    /// either exists. Plantoir never installs an assistant, and never offers
    /// to — this is a door onto something the teacher chose to put on their
    /// own Mac.
    @ViewBuilder
    func reviseWithCodexItem(course: Course, row: SidebarSelection) -> some View {
        if CodexLauncher.isAvailable,
           !course.isKeptForReference,
           let folder = workspace.workspaceURL {
            Button(CodexLauncher.menuItemTitle, systemImage: "sparkles") {
                select(row)
                reviseWithCodex(course: course, folder: folder)
            }
            .disabled(reviseReason(.codex, course: course, sectionNumber: nil) != nil)
            .accessibilityIdentifier("reviseWithCodex-\(course.code)")
        }
    }

    func reviseWithCodex(course: Course, folder: URL) {
        if let refusal = workspace.reviseRefusal(item: .codex, courseCode: course.code, sectionNumber: nil) {
            reviseRefusal = refusal
            return
        }
        if CodexLauncher.open(
            workspacePath: folder.path,
            courseCode: course.code,
            courseName: course.configuration.courseName,
            referenceCourses: ClaudeCodeLauncher.referenceCoursesToMention(
                for: course, among: workspace.courses
            )
        ) {
            return
        }
        codexProblem = CodexLauncher.couldNotStartSentence(courseCode: course.code)
    }

    /// Opens the assistant for one section, in a window of its own.
    ///
    /// Offered per SECTION rather than per course because that is the scope
    /// the assistant actually works in: its tools take a course and a section,
    /// and its window names them. A course-level entry point would have to ask
    /// which section first, which is a question the menu has already answered.
    ///
    /// Hidden rather than disabled on a Mac that cannot run it — an Intel Mac
    /// is not going to grow a Metal GPU, so a permanently greyed item would be
    /// a standing invitation to wonder what is wrong.
    @ViewBuilder
    func reviseWithAIItem(course: Course, sectionNumber: Int) -> some View {
        // HIDDEN on a reference course, not disabled — the same rule already
        // written here for a Mac that cannot run the assistant, and decision
        // (d): the local assistant is not offered on one at all, and is told
        // nothing about one. A greyed line would be a menu teaching a teacher
        // to stop reading it.
        if AssistHardwareBudget.current().canRunAssistant,
           !course.isKeptForReference,
           let folder = workspace.workspaceURL {
            // Read HERE, during the row's render, not inside the button's
            // closure — the registry is observable, so the row redraws and
            // the menu is right the moment an assistant opens or closes.
            // Reading it in the closure would show the answer from whenever
            // the row last drew, which is the staleness bug the course
            // activity registry already taught us.
            //
            // Since #458 a Claude or Codex session open on the course elsewhere greys
            // it too; the line saying why is drawn once under all three
            // Revise items (`reviseNotes`), so the same reason is not said
            // three times.
            let blocked: String? = reviseReason(.localAssistant, course: course, sectionNumber: sectionNumber)
            Button("Revise with Local AI Assistant…", systemImage: "sparkles") {
                select(SidebarSelection.section(course.code, sectionNumber))
                reviseWithLocalAssistant(course: course, sectionNumber: sectionNumber, folder: folder)
            }
            .disabled(blocked != nil)
            .accessibilityIdentifier("reviseWithAI-\(course.code)-section\(sectionNumber)")
        }
    }

    /// The shared context-menu items for a course or section folder.
    @ViewBuilder
    func folderMenuItems(for folderURL: URL, row: SidebarSelection) -> some View {
        Button("Show in Finder", systemImage: "finder") {
            select(row)
            FolderActions.showInFinder(folderURL)
        }
        Button("New Terminal at Folder", systemImage: "terminal") {
            select(row)
            FolderActions.openTerminal(at: folderURL)
        }
    }

    /// A live section row's context menu.
    @ViewBuilder
    func sectionRowMenu(course: Course, sectionNumber: Int, scheduledFor: Date?) -> some View {
        // The assistant sits at the TOP, in a
        // group of its own. It is the item a
        // teacher comes to this menu for most
        // often, and burying it under the
        // editing and folder actions made it
        // read as an afterthought.
        let row: SidebarSelection = SidebarSelection.section(course.code, sectionNumber)
        reviseWithClaudeItem(course: course, row: row)
        reviseWithCodexItem(course: course, row: row)
        reviseWithAIItem(course: course, sectionNumber: sectionNumber)
        reviseNotes(course: course, sectionNumber: sectionNumber)
        Divider()
        openInObsidianItem(course: course, sectionNumber: sectionNumber, row: row)
        Divider()
        // One item or the other, never a
        // greyed-out line — a menu that
        // teaches teachers to stop reading it
        // is worse than a shorter menu.
        // Gate by DIRECTION: "Schedule
        // Deploy…" is not offered on a
        // reference course, and "Cancel
        // Deploy at…" always is — an alarm
        // set before the course was kept
        // must still be turnable off.
        if let scheduledFor {
            Button("Cancel Deploy at \(ScheduledDeploy.timeText(scheduledFor))…", systemImage: "clock") {
                select(row)
                cancelScheduleRequest = ScheduledDeployRequest(
                    course: course,
                    sectionNumber: sectionNumber,
                    when: scheduledFor
                )
            }
            .accessibilityIdentifier("cancelScheduledDeploy-\(course.code)-section\(sectionNumber)")
        } else if !course.isKeptForReference {
            Button("Schedule Deploy…", systemImage: "clock") {
                select(row)
                scheduleRequest = ScheduledDeployRequest(
                    course: course,
                    sectionNumber: sectionNumber,
                    when: nil
                )
            }
            .accessibilityIdentifier("scheduleDeploy-\(course.code)-section\(sectionNumber)")
        }
        // Getting ready for the start of the
        // year only HIDES pages, and nothing
        // reaches students until a deploy
        // (#96). Never on a reference course;
        // not while this course is being
        // deployed. Its undo sits BESIDE it,
        // never in its place, while one is
        // held for this section.
        if !course.isKeptForReference {
            startOfYearItems(course: course, sectionNumber: sectionNumber)
        }
        Divider()
        folderMenuItems(for: course.sectionDirectoryURL(forSection: sectionNumber), row: row)
        Divider()
        removeItem("Remove Section…", course: course, row: row)
    }

    /// A live course row's context menu.
    @ViewBuilder
    func courseRowMenu(course: Course, busyReason: String?, structuralReason: String?) -> some View {
        let row: SidebarSelection = SidebarSelection.course(course.code)
        reviseWithClaudeItem(course: course, row: row)
        reviseWithCodexItem(course: course, row: row)
        reviseNotes(course: course, sectionNumber: nil)
        if course.isKeptForReference {
            openInObsidianItem(forReferenceCourse: course, sectionNumber: nil, row: row)
        } else {
            openInObsidianItem(course: course, sectionNumber: nil, row: row)
        }
        Divider()
        // Renaming moves the folder a preview is
        // serving out of, so it waits for the
        // same quiet moment adding a section
        // does — and says so in the same words.
        // A course kept for reference is FROZEN,
        // so every item that would change it is
        // not drawn at all — hidden rather than
        // greyed, which is the rule this menu
        // already follows for Schedule/Cancel:
        // a menu that teaches a teacher to stop
        // reading it is worse than a short one.
        // What it gains instead is the one thing
        // it CAN change, which is a label on the
        // shelf rather than a page.
        if course.isKeptForReference {
            Button(ReferenceWording.setSchoolYearMenuItem, systemImage: "calendar") {
                select(row)
                workspace.schoolYearRequestCode = course.code
            }
            .accessibilityIdentifier("setSchoolYear-\(course.code)")
            Divider()
        } else {
            Button(ReferenceWording.keepACopyMenuItem, systemImage: "books.vertical") {
                select(row)
                keepACopyCourse = course
            }
            .disabled(busyReason != nil)
            .accessibilityIdentifier("keepACopy-\(course.code)")
            Divider()
            // The one item here that does NOT select its row
            // first: a rename field opened in the same turn as a
            // selection change loses focus to the sidebar and
            // closes (#293, measured — see the selection's
            // onChange). The field works on an unselected row.
            Button("Rename Course", systemImage: "pencil") {
                workspace.renamingCourseCode = course.code
            }
            .disabled(structuralReason != nil)
            .accessibilityIdentifier("renameCourse-\(course.code)")
            Divider()
            // Adding a section re-runs the course
            // setup, which rewrites the course's
            // folders — never while a preview or
            // publish could be reading them.
            Button("Add Section…", systemImage: "doc.badge.plus") {
                select(row)
                addSection(to: course)
            }
            .disabled(structuralReason != nil)
            if let structuralReason {
                Text(structuralReason)
            }
            Divider()
        }
        copyAPageItem(course: course, row: row)
        Divider()
        // Backing up only READS the course, so
        // it stays available even mid-preview —
        // the moment before risky editing is
        // exactly when it's wanted.
        Button("Back Up Now", systemImage: "clock.arrow.circlepath") {
            select(row)
            Task { await workspace.backUp(course) }
        }
        // One copy at a time (#351): the zip runs
        // off the main actor now, so a second press
        // is possible while the first is saving.
        .disabled(workspace.isBeingCopied(course.code))
        Divider()
        folderMenuItems(for: course.directoryURL, row: row)
        Divider()
        removeItem("Remove Course…", course: course, row: row)
    }

    /// The row's Remove item: LAST, behind a divider, destructive (#457, the
    /// HIG sweep; Backups and Archived already ended this way). It selects
    /// its row and asks the question the − button and the menu bar ask —
    /// archiving, never deleting. Greyed while a copy of the course is being
    /// zipped, as the menu item is. A section of a course kept for reference
    /// has no Remove Section… (`interface.whatIsWithheld`); its course keeps
    /// Remove Course….
    func removeItem(_ title: String, course: Course, row: SidebarSelection) -> some View {
        return Button(title, systemImage: "archivebox", role: .destructive) {
            select(row)
            prepareRemoval()
        }
        .disabled(workspace.isBeingCopied(course.code))
    }

    // MARK: - The menu bar's Course and Section menus (#457)

    /// A context-menu item acts on the row under the pointer and SELECTS it
    /// first, the way Finder does (#457 item 4) — so what the teacher sees
    /// selected afterwards is what the item acted on, and the menu bar's
    /// Course and Section menus then name the same thing. Rename is the one
    /// exception; see its item.
    func select(_ row: SidebarSelection) {
        if workspace.selection != row {
            workspace.selection = row
        }
    }

    /// Add Section…, from the context menu or Course ▸ Add Section….
    func addSection(to course: Course) {
        // Asked again at the click (#458): a session can start between the
        // menu opening and this.
        if let refusal = workspace.structuralRefusal(
            courseCode: course.code,
            act: "add the section",
            whenBusy: "\(course.code) is previewing or deploying right now. "
                + "Stop that first, then add the section."
        ) {
            addSectionRefusal = refusal
            return
        }
        addSectionCourse = course
    }

    /// Opens the local assistant for one section — the ONLY way it opens
    /// since #457 removed File's "New Assistant Window".
    func reviseWithLocalAssistant(course: Course, sectionNumber: Int, folder: URL) {
        if let refusal = workspace.reviseRefusal(
            item: .localAssistant, courseCode: course.code, sectionNumber: sectionNumber
        ) {
            reviseRefusal = refusal
            return
        }
        openWindow(value: AssistWindowRequest(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            workingFolder: folder
        ))
    }

    /// What the sidebar tells the menu bar about the selected row.
    ///
    /// Read during the sidebar's own render, as the context menus' states
    /// are, so it follows the observable registries. The only disk reads are
    /// for the ONE selected section — its schedule and its links checklist —
    /// the same reads its context menu makes.
    var menuCommands: SidebarMenuCommands {
        var situation: SubjectMenuRules.Situation = SubjectMenuRules.Situation()
        situation.obsidianInstalled = FolderActions.obsidianIsInstalled
        var structuralReason: String? = nil
        var notes: [String] = []
        var scheduledFor: Date? = nil
        var sectionNumber: Int? = nil
        switch workspace.selection {
        case .course:
            situation.row = .course
        case .section(let code, let number):
            situation.row = .section
            sectionNumber = number
            scheduledFor = scheduledDeployTime(courseCode: code, sectionNumber: number, generation: scheduleGeneration)
            situation.hasSchedule = scheduledFor != nil
        case .backup:
            situation.row = .backup
            if let item = workspace.selectedBackupItem {
                situation.copying = workspace.isBeingCopied(item.courseCode)
            }
        case .archived:
            situation.row = .archived
        case .allBackups:
            situation.row = .allBackups
        case nil:
            situation.row = .none
        }
        if let course = workspace.selectedCourse {
            situation.keptForReference = course.isKeptForReference
            structuralReason = structuralHoldReason(for: course)
            situation.structuralHold = structuralReason != nil
            situation.busy = busyReason(for: course) != nil
            situation.copying = workspace.isBeingCopied(course.code)
            situation.deploying = isBeingDeployed(course)
            var blocked: Set<SubjectMenuRules.ReviseTarget> = []
            if reviseReason(.claude, course: course, sectionNumber: nil) != nil {
                blocked.insert(.claude)
            }
            if reviseReason(.codex, course: course, sectionNumber: nil) != nil {
                blocked.insert(.codex)
            }
            if let sectionNumber,
               reviseReason(.localAssistant, course: course, sectionNumber: sectionNumber) != nil {
                blocked.insert(.localAssistant)
            }
            situation.reviseBlocked = blocked
            notes = reviseNoteLines(course: course, sectionNumber: sectionNumber)
            if let sectionNumber, let folder = workspace.workspaceURL {
                situation.hasStartOfYearUndo = StartOfYearUndoRegistry.shared.entry(
                    folderPath: folder.path, courseCode: course.code, sectionNumber: sectionNumber
                ) != nil
                if !course.isKeptForReference {
                    situation.hasLinksOffer = LinksChecklistOffer.read(
                        courseDirectory: course.directoryURL, section: sectionNumber
                    ) != nil
                }
            }
        }
        return SidebarMenuCommands(
            situation: situation,
            structuralReason: structuralReason,
            reviseNotes: notes,
            scheduledFor: scheduledFor,
            perform: performMenuItem
        )
    }

    /// Runs a Course or Section menu item on whatever is selected NOW — the
    /// same functions the context menus call, so the two routes cannot
    /// disagree. Asks the rule again first: the menu may have been drawn
    /// before something started.
    func performMenuItem(_ item: SubjectMenuRules.Item) {
        if !SubjectMenuRules.enabledItems(menuCommands.situation).contains(item) {
            NSSound.beep()
            return
        }
        let course: Course? = workspace.selectedCourse
        var sectionNumber: Int? = nil
        if case .section(_, let number) = workspace.selection {
            sectionNumber = number
        }
        switch item {
        case .addSection:
            if let course {
                addSection(to: course)
            }
        case .copyAPage:
            copyPageCourse = course
        case .rename:
            workspace.beginRenamingSelectedCourse()
        case .setSchoolYear:
            if let course {
                workspace.schoolYearRequestCode = course.code
            }
        case .keepACopyForReference:
            keepACopyCourse = course
        case .backUpNow:
            if let course {
                Task { await workspace.backUp(course) }
            }
        case .restoreFromBackup:
            workspace.backupRestoreRequest = workspace.selectedBackupItem
        case .courseReviseWithClaude, .sectionReviseWithClaude:
            if let course, let folder = workspace.workspaceURL {
                reviseWithClaude(course: course, folder: folder)
            }
        case .courseReviseWithCodex, .sectionReviseWithCodex:
            if let course, let folder = workspace.workspaceURL {
                reviseWithCodex(course: course, folder: folder)
            }
        case .sectionReviseWithLocalAssistant:
            if let course, let sectionNumber, let folder = workspace.workspaceURL {
                reviseWithLocalAssistant(course: course, sectionNumber: sectionNumber, folder: folder)
            }
        case .courseOpenInObsidian, .sectionOpenInObsidian:
            if let course {
                workspace.openInObsidian(course: course, sectionNumber: sectionNumber)
            }
        case .courseShowInFinder:
            if let backup = workspace.selectedBackupItem {
                NSWorkspace.shared.activateFileViewerSelecting([backup.fileURL])
            } else if let archived = workspace.selectedArchivedItem {
                NSWorkspace.shared.activateFileViewerSelecting([archived.fileURL])
            } else if let course {
                FolderActions.showInFinder(course.directoryURL)
            }
        case .courseNewTerminalAtFolder:
            if let course {
                FolderActions.openTerminal(at: course.directoryURL)
            }
        case .sectionShowInFinder:
            if let course, let sectionNumber {
                FolderActions.showInFinder(course.sectionDirectoryURL(forSection: sectionNumber))
            }
        case .sectionNewTerminalAtFolder:
            if let course, let sectionNumber {
                FolderActions.openTerminal(at: course.sectionDirectoryURL(forSection: sectionNumber))
            }
        case .deleteBackup:
            if let backup = workspace.selectedBackupItem {
                workspace.requestDeleteBackup(backup)
            }
        case .deleteArchive:
            workspace.archiveDeleteRequest = workspace.selectedArchivedItem
        case .removeCourse, .removeSection:
            prepareRemoval()
        case .scheduleDeploy:
            if let course, let sectionNumber {
                scheduleRequest = ScheduledDeployRequest(course: course, sectionNumber: sectionNumber, when: nil)
            }
        case .cancelScheduledDeploy:
            if let course, let sectionNumber,
               let when = scheduledDeployTime(courseCode: course.code, sectionNumber: sectionNumber, generation: scheduleGeneration) {
                cancelScheduleRequest = ScheduledDeployRequest(course: course, sectionNumber: sectionNumber, when: when)
            }
        case .getReadyForTheStartOfTheYear:
            if let course, let sectionNumber {
                startOfYearRequest = StartOfYearRequest(course: course, sectionNumber: sectionNumber, mode: .getReady)
            }
        case .undoGettingReady:
            if let course, let sectionNumber {
                startOfYearRequest = StartOfYearRequest(course: course, sectionNumber: sectionNumber, mode: .undo)
            }
        case .publishPagesLinksLeadTo:
            if let course, let sectionNumber {
                openTheLinksChecklist(course: course, sectionNumber: sectionNumber)
            }
        case .openWorkingFolder, .openRecent, .newCourse, .importCoursesForReference, .restoreFromArchive, .reloadCourses,
             .saveCourseSettings, .revertCourseSettings, .courseReviseWithLocalAssistant,
             .preview, .deploy, .openInBrowser, .back, .forward, .reloadPage:
            // Not the sidebar's: File, Course Settings and the section
            // window own these. Local AI Assistant is never live on a course.
            break
        }
    }

    /// Return, pressed on a course in the sidebar. True when it has been
    /// dealt with and the key should go no further.
    ///
    /// Only a COURSE row answers. A section's row is a different thing to
    /// have selected, and renaming the course it belongs to because Return
    /// was pressed on Section 2 is not what anybody meant — Course ▸ Rename…
    /// is there for that, in the menu named for what it acts on (#457).
    func beginRenamingFromTheKeyboard() -> Bool {
        if workspace.renamingCourseCode != nil {
            return false
        }
        guard case .course = workspace.selection else {
            return false
        }
        if workspace.courseThatCanBeRenamed == nil {
            return false
        }
        if workspace.renameIsUnavailableReason != nil {
            // Refused audibly rather than silently — the course's own menu
            // says why, and a key that does nothing at all reads as broken.
            NSSound.beep()
            return true
        }
        workspace.beginRenamingSelectedCourse()
        return true
    }

    /// Delete, pressed with a sidebar row selected: runs the item the menu
    /// bar would — Remove Course…, Remove Section…, Delete Backup… or Delete
    /// Archive… — through `performMenuItem`, which asks the same rule the
    /// menu greys by (so nothing on a reference section, nothing under a
    /// sheet: a beep, as for any greyed item) and then asks the same question.
    func deleteKeyPressed() {
        guard let item = SubjectMenuRules.deleteKeyItem(for: menuCommands.situation.row) else {
            return
        }
        performMenuItem(item)
    }

    /// Works out what the remove button would do and asks first.
    func prepareRemoval() {
        guard let selection = workspace.selection else {
            return
        }
        guard let course = workspace.selectedCourse else {
            return
        }

        switch selection {
        case .course:
            removalRequest = RemovalRequest(
                courseCode: course.code,
                sectionNumber: nil,
                title: "Remove \(course.displayCode)?",
                message: withScheduledDeployWarning(
                    "Nothing is deleted. \(course.displayCode) and all of its sections move to Archived, at the bottom of the sidebar, where you can get them back.",
                    courseCode: course.code,
                    sectionNumber: nil
                )
            )
        case .archived:
            // The minus button removes live courses; an archived item is
            // already put away.
            return
        case .backup, .allBackups:
            // Deleting a backup is a real deletion, so it happens only
            // through its own explicit menu item, never the minus button.
            // The Delete key asks through that item (Course ▸ Delete
            // Backup…), not through here (#457, the HIG sweep).
            return
        case .section(_, let sectionNumber):
            if course.sectionNumbers.count <= 1 {
                // Removing the only section leaves nothing behind, so be
                // explicit that this removes the whole course.
                removalRequest = RemovalRequest(
                    courseCode: course.code,
                    sectionNumber: nil,
                    title: "Remove \(course.displayCode)?",
                    message: withScheduledDeployWarning(
                        "Section \(sectionNumber) is the only section of \(course.displayCode), so the whole course moves to Archived. Nothing is deleted — you can get it back from the bottom of the sidebar.",
                        courseCode: course.code,
                        sectionNumber: nil
                    )
                )
            } else {
                removalRequest = RemovalRequest(
                    courseCode: course.code,
                    sectionNumber: sectionNumber,
                    title: "Remove Section \(sectionNumber) of \(course.displayCode)?",
                    message: withScheduledDeployWarning(
                        "Nothing is deleted. This section moves to Archived, at the bottom of the sidebar, where you can get it back.",
                        courseCode: course.code,
                        sectionNumber: sectionNumber
                    )
                )
            }
        }
    }

    /// The confirmation's own sentence, with the scheduled-deploy warning
    /// appended when there is one to give.
    ///
    /// Only when something really is scheduled IN THIS WORKING FOLDER: a
    /// promise about another folder's deploy would be a promise Plantoir is
    /// not going to keep.
    func withScheduledDeployWarning(
        _ message: String, courseCode: String, sectionNumber: Int?
    ) -> String {
        guard let workspaceURL = workspace.workspaceURL else {
            return message
        }
        guard let warning = ScheduledDeployCleanup.warningForConfirmation(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            inWorkingFolder: workspaceURL
        ) else {
            return message
        }
        return message + "\n\n" + warning
    }

    /// Carries the teacher's "Remove" through to the model, which turns the
    /// scheduled deploy off FIRST and archives second.
    ///
    /// The view keeps one call and the alert; the order, the reporting and the
    /// trail line live in `ScheduledDeployCleanup`, where a test can drive
    /// them — nothing in the suite constructs this view. Async since #351:
    /// the archive made before a removal is a zip, run off the main actor.
    func performRemoval(_ request: RemovalRequest) async {
        guard let coursesDirectoryURL = workspace.coursesDirectoryURL else {
            return
        }
        var courseToRemove: Course?
        for course in workspace.courses {
            if course.code == request.courseCode {
                courseToRemove = course
            }
        }
        guard let courseToRemove else {
            return
        }
        // One archive at a time (#351); the button is greyed then too.
        if workspace.isBeingCopied(courseToRemove.code) {
            return
        }

        var result: ScheduledDeployCleanup.RemovalResult
        if let sectionNumber = request.sectionNumber {
            result = await ScheduledDeployCleanup.removeSection(
                sectionNumber,
                from: courseToRemove,
                coursesDirectoryURL: coursesDirectoryURL
            )
        } else {
            result = await ScheduledDeployCleanup.removeCourse(
                courseToRemove,
                coursesDirectoryURL: coursesDirectoryURL
            )
        }

        if let problem = result.problem {
            removalProblem = problem
        }
        // Redraws the clocks: a deploy turned off on the way out must not
        // leave its badge behind on a section that is still here.
        scheduleGeneration += 1
        if !result.didRemove {
            return
        }

        workspace.selection = nil
        workspace.reloadCourses()
    }
}

/// One section's scheduled deploy, as the sidebar's sheet and alert pass it
/// around. `when` is nil while asking for a time, and carries the agent's own
/// moment while asking whether to cancel it.
struct ScheduledDeployRequest: Identifiable {

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int
    let when: Date?

    // MARK: - Computed properties

    var id: String {
        return "\(course.code)-section\(sectionNumber)"
    }
}

/// What the remove button is about to do, pending confirmation.
struct RemovalRequest: Identifiable {

    // MARK: - Stored properties

    let courseCode: String

    /// nil means the whole course.
    let sectionNumber: Int?

    let title: String
    let message: String

    // MARK: - Computed properties

    var id: String {
        if let sectionNumber {
            return "\(courseCode)-section\(sectionNumber)"
        }
        return courseCode
    }
}

/// One course's row: its code, or a field to type a new one into.
///
/// Which of the two it is arrives as a plain `Bool` rather than being read
/// from the window's model here, because a row inside a `List` cannot be
/// relied on to observe that model — see the note at the sidebar's own body,
/// where the read happens instead.
struct CourseRowLabel: View {

    // MARK: - Stored properties

    let course: Course

    /// Decided by the sidebar rather than read here — see the note where it
    /// is read.
    let isBeingRenamed: Bool

    /// Whether a copy of the course is being zipped right now (#351).
    var isBeingCopied: Bool = false

    // MARK: - Body

    var body: some View {
        if isBeingRenamed {
            CourseCodeField(course: course)
        } else {
            // `displayCode`, not `code`: decision (h) — a teacher reads
            // ICS3U, never the folder name. The year group above this row
            // already says 2025–26, so the suffix would be redundant as
            // well as wrong.
            HStack(spacing: 6) {
                Label(course.displayCode, systemImage: "books.vertical")
                // A copy of the course is being zipped (#351) — a backup, or
                // the archive before a restore or removal. The row says so
                // rather than the window going quiet for the minute it takes.
                if isBeingCopied {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving a copy")
                        .accessibilityIdentifier("courseBeingCopied-\(course.code)")
                }
            }
        }
    }
}

/// The in-place editor for a course's code, behaving the way Finder's own
/// rename does: the whole code arrives selected, Return commits it, Escape
/// puts it back, and clicking away commits — but only if what was typed can
/// actually be used.
///
/// The reason for a code being refused is shown UNDER the field rather than
/// in an alert. An alert would take focus off the field the moment the
/// teacher pressed Return, which is exactly when they most want to keep
/// typing; and the New Course wizard already explains a bad code this way,
/// so the two fields answer the same question in the same voice.
struct CourseCodeField: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    let course: Course

    /// What is in the field. Starts as the code the course already has, so
    /// pressing Return straight away is a no-op rather than a surprise.
    @State var text: String

    @FocusState var isFocused: Bool

    // MARK: - Computed properties

    /// Why what has been typed cannot be used, live — asked of the model,
    /// which asks the same question when Return is pressed, so what the
    /// field shows and what it refuses cannot come apart.
    var problem: String? {
        return workspace.renameFieldProblem(course, typed: text)
    }

    // MARK: - Initializer

    init(course: Course) {
        self.course = course
        _text = State(initialValue: course.code)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "books.vertical")

            // The field and its message share ONE solid card, and that is
            // what makes the MESSAGE readable.
            //
            // A course renamed from Return or Course ▸ Rename… is SELECTED
            // while it is being renamed, so this row is drawing on the
            // selection colour — and everything inside a selected sidebar
            // row is tinted to sit on it. (The context menu selects the row
            // first, Finder-style, since #457.) Red-on-blue for the message
            // was the result. Painting a card in the system's own
            // text-background colour takes it off the selection entirely, and
            // because that colour is semantic it is white in Light Mode and
            // near-black in Dark without a second code path.
            //
            // The FIELD wears the bordered style every field wears (#457:
            // no exemptions). It was `.plain` inside this card's own stroke
            // until then; the bezel draws its own text background, so the
            // field reads on the selection without the card, and the card
            // lost its stroke so the two borders do not nest.
            VStack(alignment: .leading, spacing: 2) {
                TextField("Course code", text: $text)
                    .borderedTextField()
                    .foregroundStyle(Color(nsColor: .textColor))
                    .focused($isFocused)
                    .accessibilityIdentifier("renameField")
                    .onSubmit {
                        commit()
                    }
                    .onExitCommand {
                        workspace.renamingCourseCode = nil
                    }
                    .onChange(of: isFocused) {
                        if !isFocused {
                            commitOnLeaving()
                        }
                    }

                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .systemRed))
                        // Short enough to fit, and allowed to wrap rather
                        // than truncate if a longer one ever arrives: half a
                        // sentence with an ellipsis explains nothing.
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("renameProblem")
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
        .onAppear {
            isFocused = true
            selectEverything()
        }
    }

    // MARK: - Functions

    /// Return: rename if the code can be used, and refuse audibly if it
    /// cannot. The reason is already on screen under the field, so saying it
    /// again in an alert would only take the field away.
    func commit() {
        let renamed: Bool = workspace.renameFromTheField(course, typed: text)
        if !renamed {
            NSSound.beep()
        }
    }

    /// Clicking away is a commit, as it is in Finder — but a code that
    /// cannot be used reverts instead, rather than putting an alert in front
    /// of a teacher who has already moved on to something else.
    func commitOnLeaving() {
        // SWITCHING APPS IS NOT CLICKING AWAY, and the difference is not
        // cosmetic: a focused field cannot hold focus while its app is
        // inactive, so without this check the field closes itself the moment
        // the teacher looks at Obsidian — or, on a Mac where Plantoir was
        // never brought to the front, the instant it opens. Found exactly
        // that way: the field appeared and vanished again before anything
        // could be typed into it.
        if !NSApplication.shared.isActive {
            return
        }
        // Only while this row is still the one being edited. The rename
        // itself clears that, and focus leaves immediately afterwards, so
        // without this check a successful rename would ask for a second one.
        if workspace.renamingCourseCode != course.code {
            return
        }
        if problem != nil {
            workspace.renamingCourseCode = nil
            return
        }
        workspace.rename(course, to: text)
    }

    /// Hands the field over with the whole code selected, the way Finder
    /// hands over a name — replacing it outright is the commonest edit, and
    /// a teacher who wants to keep part of it can still click into it.
    ///
    /// SwiftUI has no way to ask for this, so it is asked of the field
    /// editor — the shared NSTextView a text field borrows while it has
    /// focus — one pass of the run loop later, once focus has landed.
    ///
    /// That deferral papers over the same kind of focus race as the
    /// sidebar's `.onChange(of: workspace.selection)`: it waits for focus
    /// rather than being told focus arrived. A Task on the main actor, not
    /// a main-queue block, only for the house style — the two run at the
    /// same point (never `Task.immediate`, which would run before focus has
    /// landed and find no field editor). See #293 for where that race has
    /// already cost a test.
    func selectEverything() {
        Task { @MainActor in
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
                return
            }
            editor.selectAll(nil)
        }
    }
}

/// The two outside doors' failure alerts — "Claude didn't open" and "Codex
/// didn't open" — lifted out of `SidebarView.body`.
///
/// Not a tidy-up. Adding the second alert pushed the sidebar's modifier chain
/// past what the Swift type-checker will finish, and the build failed with
/// "the compiler is unable to type-check this expression in reasonable time"
/// pointing at an unrelated alert two hundred lines away. One modifier in the
/// chain, whose own body is type-checked on its own, is the smallest cut that
/// puts it back — and it keeps the two doors' failure paths side by side,
/// which is where they belong.
private struct OutsideAgentAlerts: ViewModifier {

    // MARK: - Stored properties

    @Binding var claudeProblem: String?

    @Binding var codexProblem: String?

    @Binding var reviseRefusal: WorkspaceModel.ReviseRefusal?

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .alert(ClaudeCodeLauncher.didNotOpenTitle, isPresented: presentation(of: $claudeProblem)) {
                Button("OK") {
                    claudeProblem = nil
                }
            } message: {
                Text(claudeProblem ?? "")
            }
            .alert(CodexLauncher.didNotOpenTitle, isPresented: presentation(of: $codexProblem)) {
                Button("OK") {
                    codexProblem = nil
                }
            } message: {
                Text(codexProblem ?? "")
            }
            .alert(
                reviseRefusal?.title ?? "",
                isPresented: Binding(
                    get: { reviseRefusal != nil },
                    set: { isPresented in
                        if !isPresented {
                            reviseRefusal = nil
                        }
                    }
                )
            ) {
                Button("OK") {
                    reviseRefusal = nil
                }
            } message: {
                Text(reviseRefusal?.message ?? "")
            }
    }

    /// An alert wants a `Bool`; what the sidebar holds is the sentence itself,
    /// or nothing.
    private func presentation(of problem: Binding<String?>) -> Binding<Bool> {
        return Binding(
            get: { problem.wrappedValue != nil },
            set: { isPresented in
                if !isPresented {
                    problem.wrappedValue = nil
                }
            }
        )
    }
}

/// What the sidebar does about a Claude or Codex session holding a course from another
/// program (#458): keeps the window's snapshot of held courses fresh, and
/// says why "Add Section…" refused at the click. A modifier of its own so
/// the sidebar's body stays small enough to type-check.
private struct OutsideSessionHolds: ViewModifier {

    // MARK: - Stored properties

    let workspace: WorkspaceModel

    @Binding var addSectionRefusal: String?

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .alert("Could not add a section", isPresented: Binding(
                get: { addSectionRefusal != nil },
                set: { isPresented in
                    if !isPresented {
                        addSectionRefusal = nil
                    }
                }
            )) {
                Button("OK") {
                    addSectionRefusal = nil
                }
            } message: {
                Text(addSectionRefusal ?? "")
            }
            // Which courses a Claude or Codex session elsewhere is holding: read when
            // the folder is shown, and again whenever Plantoir becomes the
            // active app — a session is opened and closed in Terminal, so
            // coming back is when the answer changes. Every click that acts
            // on it reads the disk itself.
            .task(id: workspace.workspaceURL) {
                workspace.refreshCoursesRevisedElsewhere()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                workspace.refreshCoursesRevisedElsewhere()
            }
    }
}
