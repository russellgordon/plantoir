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

    /// The course a "Keep a Copy for Reference…" sheet is open for.
    @State var keepACopyCourse: Course?

    /// The course a "Copy a Page from This Course…" sheet is open for.
    ///
    /// Any course — live or kept for reference. It is the SOURCE, and the
    /// sheet only ever reads it: a reference course is kept to be read, so
    /// copying a page OUT of one is the point of having it rather than an
    /// exception to its being frozen.
    @State var copyPageCourse: Course?


    /// The reference course whose calm locked-pages note is showing, before
    /// the teacher goes into Obsidian.
    @State var lockedPagesNoteCourse: Course?

    /// The section "Schedule Deploy…" was chosen on, while its sheet is up.
    @State var scheduleRequest: ScheduledDeployRequest?

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
                                        // The assistant sits at the TOP, in a
                                        // group of its own. It is the item a
                                        // teacher comes to this menu for most
                                        // often, and burying it under the
                                        // editing and folder actions made it
                                        // read as an afterthought.
                                        reviseWithClaudeItem(course: course)
                                        reviseWithCodexItem(course: course)
                                        reviseWithAIItem(course: course, sectionNumber: sectionNumber)
                                        Divider()
                                        openInObsidianItem(
                                            revealing: course.sectionDirectoryURL(forSection: sectionNumber),
                                            vaultURL: course.directoryURL
                                        )
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
                                                cancelScheduleRequest = ScheduledDeployRequest(
                                                    course: course,
                                                    sectionNumber: sectionNumber,
                                                    when: scheduledFor
                                                )
                                            }
                                            .accessibilityIdentifier("cancelScheduledDeploy-\(course.code)-section\(sectionNumber)")
                                        } else if !course.isKeptForReference {
                                            Button("Schedule Deploy…", systemImage: "clock") {
                                                scheduleRequest = ScheduledDeployRequest(
                                                    course: course,
                                                    sectionNumber: sectionNumber,
                                                    when: nil
                                                )
                                            }
                                            .accessibilityIdentifier("scheduleDeploy-\(course.code)-section\(sectionNumber)")
                                        }
                                        Divider()
                                        folderMenuItems(for: course.sectionDirectoryURL(forSection: sectionNumber))
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
                            CourseRowLabel(
                                course: course,
                                isBeingRenamed: renamingCourseCode == course.code
                            )
                                .tag(SidebarSelection.course(course.code))
                                .accessibilityIdentifier("sidebar-\(course.code)")
                                .contextMenu {
                                    reviseWithClaudeItem(course: course)
                                    reviseWithCodexItem(course: course)
                                    if course.isKeptForReference {
                                        openInObsidianItem(forReferenceCourse: course)
                                    } else {
                                        openInObsidianItem(
                                            revealing: course.directoryURL, vaultURL: course.directoryURL
                                        )
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
                                            workspace.schoolYearRequestCode = course.code
                                        }
                                        .accessibilityIdentifier("setSchoolYear-\(course.code)")
                                        Divider()
                                    } else {
                                        Button(ReferenceWording.keepACopyMenuItem, systemImage: "books.vertical") {
                                            keepACopyCourse = course
                                        }
                                        .disabled(busyReason != nil)
                                        .accessibilityIdentifier("keepACopy-\(course.code)")
                                        Divider()
                                        Button("Rename Course", systemImage: "pencil") {
                                            workspace.renamingCourseCode = course.code
                                        }
                                        .disabled(busyReason != nil)
                                        .accessibilityIdentifier("renameCourse-\(course.code)")
                                        Divider()
                                        // Adding a section re-runs the course
                                        // setup, which rewrites the course's
                                        // folders — never while a preview or
                                        // publish could be reading them.
                                        Button("Add Section…", systemImage: "doc.badge.plus") {
                                            addSectionCourse = course
                                        }
                                        .disabled(busyReason != nil)
                                        if let busyReason {
                                            Text(busyReason)
                                        }
                                        Divider()
                                    }
                                    copyAPageItem(course: course)
                                    Divider()
                                    // Backing up only READS the course, so
                                    // it stays available even mid-preview —
                                    // the moment before risky editing is
                                    // exactly when it's wanted.
                                    Button("Back Up Now", systemImage: "clock.arrow.circlepath") {
                                        workspace.backUp(course)
                                    }
                                    Divider()
                                    folderMenuItems(for: course.directoryURL)
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
                                        workspace.backupRestoreRequest = item
                                    }
                                    Button("Show in Finder", systemImage: "finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                                    }
                                    Divider()
                                    Button("Delete Backup…", systemImage: "trash", role: .destructive) {
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
                        .accessibilityIdentifier("backupsGroup")
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
                                        workspace.restoreRequest = item
                                    }
                                    Button("Show in Finder", systemImage: "finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                                    }
                                    Divider()
                                    Button("Delete Archive…", systemImage: "trash", role: .destructive) {
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

            Divider()

            bottomBar
        }
        .alert(
            removalRequest?.title ?? "",
            isPresented: removalRequestIsPresented,
            presenting: removalRequest
        ) { request in
            Button("Remove", role: .destructive) {
                performRemoval(request)
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
                workspace.restoreBackup(item)
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
        .modifier(OutsideAgentAlerts(claudeProblem: $claudeProblem, codexProblem: $codexProblem))
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
        .modifier(LockedPagesNoteAlert(course: $lockedPagesNoteCourse))
        .sheet(item: $addSectionCourse) { course in
            AddSectionSheet(course: course) { sectionNumber in
                workspace.reloadCourses()
                workspace.selection = SidebarSelection.section(course.code, sectionNumber)
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
        let outcome: ScheduledPublishOutcome.Stopped? = ScheduledPublishOutcome.stopped(
            inHomeFolder: ScheduledDeploy.homeForScheduledNotes,
            course: courseCode,
            section: sectionNumber
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
            .help("Add a course or club")
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
            .disabled(workspace.selectedCourse == nil)
            .help("Remove the selected course or section")
            .accessibilityIdentifier("removeSelectedButton")
            .padding(.trailing, 5)

            TextField("Filter", text: $workspace.filterText)
                .textFieldStyle(.roundedBorder)
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
        return ScheduledDeploy.nextRun(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            inWorkingFolder: workspace.workspaceURL
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
        return "A publish that was set to happen on its own did not get through. "
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
    func copyAPageItem(course: Course) -> some View {
        Button(CopyPageWording.menuItem, systemImage: "doc.on.doc") {
            copyPageCourse = course
        }
        .accessibilityIdentifier("copyAPage-\(course.code)")
    }

    /// Why the course is busy — previewing or publishing, in any window
    /// showing this working folder — or nil when it isn't.
    func busyReason(for course: Course) -> String? {
        guard let workspaceURL = workspace.workspaceURL else {
            return nil
        }
        return CourseActivity.busyDescription(folderPath: workspaceURL.path, courseCode: course.code)
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
                        openInObsidianItem(forReferenceCourse: course)
                        Divider()
                        folderMenuItems(for: course.sectionDirectoryURL(forSection: sectionNumber))
                    }
            }
        } label: {
            CourseRowLabel(course: course, isBeingRenamed: false)
                .tag(SidebarSelection.course(course.code))
                .accessibilityIdentifier("sidebar-\(course.code)")
                .contextMenu {
                    openInObsidianItem(forReferenceCourse: course)
                    Divider()
                    Button(ReferenceWording.setSchoolYearMenuItem, systemImage: "calendar") {
                        workspace.schoolYearRequestCode = course.code
                    }
                    .accessibilityIdentifier("setSchoolYear-\(course.code)")
                    Divider()
                    copyAPageItem(course: course)
                    Divider()
                    // Backing up only READS the course, and a reference
                    // course restores as a reference course — the marker
                    // travels in its settings, and the restore locks it
                    // again.
                    Button("Back Up Now", systemImage: "clock.arrow.circlepath") {
                        workspace.backUp(course)
                    }
                    Divider()
                    folderMenuItems(for: course.directoryURL)
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
    /// subfolder within it, and Obsidian lands there.
    @ViewBuilder
    func openInObsidianItem(revealing folderURL: URL, vaultURL: URL) -> some View {
        Button("Open in Obsidian", systemImage: "square.and.pencil") {
            FolderActions.openInObsidian(revealing: folderURL, vaultURL: vaultURL)
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
    func openInObsidianItem(forReferenceCourse course: Course) -> some View {
        Button("Open in Obsidian", systemImage: "square.and.pencil") {
            // Locked again first: this is one of the moments the teacher
            // ACTS on a reference course, and a folder that came back from a
            // second Mac, or from a backup, is not locked until somebody
            // asks.
            ReferenceLock.ensureLockedInBackground(course)
            if LockedPagesNote.hasBeenShown(courseCode: course.code) {
                FolderActions.openInObsidian(revealing: course.directoryURL, vaultURL: course.directoryURL)
                return
            }
            lockedPagesNoteCourse = course
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
    func reviseWithClaudeItem(course: Course) -> some View {
        // NOT offered on a reference course (decision s). The door's whole
        // purpose is changing a course, and a session opened on one that
        // cannot change would be an invitation to find that out by trying.
        // A LIVE course's session is told the reference courses exist
        // instead — see the greeting.
        if ClaudeCodeLauncher.isAvailable,
           !course.isKeptForReference,
           let folder = workspace.workspaceURL {
            Button(ClaudeCodeLauncher.menuItemTitle, systemImage: "sparkles") {
                reviseWithClaude(course: course, folder: folder)
            }
            .accessibilityIdentifier("reviseWithClaude-\(course.code)")
        }
    }

    func reviseWithClaude(course: Course, folder: URL) {
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
    func reviseWithCodexItem(course: Course) -> some View {
        if CodexLauncher.isAvailable,
           !course.isKeptForReference,
           let folder = workspace.workspaceURL {
            Button(CodexLauncher.menuItemTitle, systemImage: "sparkles") {
                reviseWithCodex(course: course, folder: folder)
            }
            .accessibilityIdentifier("reviseWithCodex-\(course.code)")
        }
    }

    func reviseWithCodex(course: Course, folder: URL) {
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
            let blocked: String? = AssistActivity.reasonItIsUnavailable(
                folderPath: folder.path,
                courseCode: course.code,
                sectionNumber: sectionNumber
            )
            Button("Revise with Local AI Assistant…", systemImage: "sparkles") {
                openWindow(value: AssistWindowRequest(
                    courseCode: course.code,
                    sectionNumber: sectionNumber,
                    workingFolder: folder
                ))
            }
            .disabled(blocked != nil)
            .accessibilityIdentifier("reviseWithAI-\(course.code)-section\(sectionNumber)")
            // Dimmed alone says "no"; the line under it says what to do
            // about it — the same shape "Add Section…" uses when a course is
            // busy.
            if let blocked {
                Text(blocked)
            }
        }
    }

    /// The shared context-menu items for a course or section folder.
    @ViewBuilder
    func folderMenuItems(for folderURL: URL) -> some View {
        Button("Show in Finder", systemImage: "finder") {
            FolderActions.showInFinder(folderURL)
        }
        Button("New Terminal at Folder", systemImage: "terminal") {
            FolderActions.openTerminal(at: folderURL)
        }
    }

    /// Return, pressed on a course in the sidebar. True when it has been
    /// dealt with and the key should go no further.
    ///
    /// Only a COURSE row answers. A section's row is a different thing to
    /// have selected, and renaming the course it belongs to because Return
    /// was pressed on Section 2 is not what anybody meant — the Edit menu is
    /// there for that, where the item says which course it will rename.
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
    /// them — nothing in the suite constructs this view.
    func performRemoval(_ request: RemovalRequest) {
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

        var result: ScheduledDeployCleanup.RemovalResult
        if let sectionNumber = request.sectionNumber {
            result = ScheduledDeployCleanup.removeSection(
                sectionNumber,
                from: courseToRemove,
                coursesDirectoryURL: coursesDirectoryURL
            )
        } else {
            result = ScheduledDeployCleanup.removeCourse(
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

    // MARK: - Body

    var body: some View {
        if isBeingRenamed {
            CourseCodeField(course: course)
        } else {
            // `displayCode`, not `code`: decision (h) — a teacher reads
            // ICS3U, never the folder name. The year group above this row
            // already says 2025–26, so the suffix would be redundant as
            // well as wrong.
            Label(course.displayCode, systemImage: "books.vertical")
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
            // what makes them readable.
            //
            // A course renamed from Return or the Edit menu is SELECTED
            // while it is being renamed, so this row is drawing on the
            // selection colour — and everything inside a selected sidebar
            // row is tinted to sit on it. (The context menu can open the
            // field on a row that is NOT selected — driven for #293, where
            // the card read the same on a plain row, so it is harmless
            // there.) Black-on-blue
            // for the field and red-on-blue for the message were the result.
            // Painting a card in the system's own text-background colour
            // takes the content off the selection entirely, and because that
            // colour is semantic it is white in Light Mode and near-black in
            // Dark without a second code path.
            VStack(alignment: .leading, spacing: 2) {
                TextField("Course code", text: $text)
                    .textFieldStyle(.plain)
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
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(nsColor: .separatorColor))
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
/// The calm note about a reference course's pages, shown once per course
/// BEFORE the teacher goes into Obsidian.
///
/// A modifier rather than three more lines on the sidebar's body, for a
/// reason worth writing down: the body reached the point where the Swift
/// compiler gave up type-checking it ("unable to type-check this expression
/// in reasonable time"), which is what every other alert here was eventually
/// pulled out for.
private struct LockedPagesNoteAlert: ViewModifier {

    // MARK: - Stored properties

    @Binding var course: Course?

    // MARK: - Functions

    func body(content: Content) -> some View {
        content.alert(
            ReferenceWording.pagesAreLockedTitle,
            isPresented: isPresented,
            presenting: course
        ) { shown in
            Button("Open in Obsidian") {
                LockedPagesNote.remember(courseCode: shown.code)
                course = nil
                FolderActions.openInObsidian(
                    revealing: shown.directoryURL, vaultURL: shown.directoryURL
                )
            }
            Button("Not Now", role: .cancel) {
                course = nil
            }
        } message: { _ in
            // No warning icon and no "cannot": a teacher who kept this course
            // for reference asked for it, so it reads as a fact.
            Text(ReferenceWording.pagesAreLocked + "\n\n" + ReferenceWording.obsidianOpensThemForReading)
        }
    }

    private var isPresented: Binding<Bool> {
        return Binding(
            get: { return course != nil },
            set: { showing in
                if !showing {
                    course = nil
                }
            }
        )
    }
}

private struct OutsideAgentAlerts: ViewModifier {

    // MARK: - Stored properties

    @Binding var claudeProblem: String?

    @Binding var codexProblem: String?

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
