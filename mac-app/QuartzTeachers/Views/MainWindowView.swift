import SwiftUI

/// The app's single window: a collapsible sidebar of courses and sections,
/// with either course settings or a section's preview/deploy view beside it.
struct MainWindowView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    /// The band the contents sit in — the same height as the sidebar's
    /// footer, so "Working folder" lines up with the Filter field.
    @ScaledMetric(relativeTo: .body) var scaledContentHeight: CGFloat = WindowChrome.footerHeight

    /// The extra height below that band, which is what brings this rule
    /// level with the sidebar's.
    @ScaledMetric(relativeTo: .body) var scaledBottomInset: CGFloat = WindowChrome.sidebarBottomInset

    // MARK: - Body

    var body: some View {
        @Bindable var workspace = workspace

        Group {
            if workspace.isResolvingRestoredFolder && workspace.workspaceURL == nil {
                // A restored window whose folder claim has not resolved
                // yet — a beat of quiet, never the picker it is about to
                // replace.
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("restoringFolderPlaceholder")
            } else if workspace.isShowingPicker {
                WorkspacePickerView()
            } else {
                NavigationSplitView {
                    // At most 320 wide (#213): see `WindowChrome.sidebarMaximumWidth`.
                    SidebarView()
                        .plantoirSidebarColumnWidth()
                } detail: {
                    // The path bar sits under the content, spanning the
                    // detail column, exactly where Finder puts its own.
                    VStack(spacing: 0) {
                        detailView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // The note about a synced folder the window
                        // restored, when there is one to show — above the
                        // path bar, which is where the folder it is about
                        // is named.
                        // And, while the folder's tools are being copied in
                        // after an update (#476), the notice saying so.
                        ToolchainReadinessNoticeView()
                        AgentGuidanceNoticeView()
                        CloudSyncNoticeView()
                        workingFolderPathBar
                    }
                }
            }
        }
        // Adding a course lives on the sidebar's own +/- bar, where
        // macOS list interfaces conventionally put it.
        .sheet(isPresented: $workspace.isShowingNewCourseWizard) {
            NewCourseWizardView()
        }
        // A teacher's own AGENTS.md or CLAUDE.md: asked before Plantoir adds
        // its section (#454). One file at a time; answering moves to the next.
        .sheet(item: pendingGuidanceAppend) { pending in
            if let workspaceURL = workspace.workspaceURL {
                AgentGuidanceSheet(pending: pending, workspaceURL: workspaceURL)
            }
        }
        // A chosen folder the website builder cannot reach, refused while
        // this window goes on showing its own folder (#290): said over the
        // folder the teacher is still in, which stays exactly as it was.
        .modifier(RefusedFolderAlert())
        // The calm note about a reference course's locked pages, asked for
        // by whichever route opened Obsidian. On the WINDOW, not the
        // sidebar: the section window's toolbar button is reachable with the
        // sidebar collapsed (#457, the HIG sweep).
        .modifier(LockedPagesNoteAlert())
        .fileImporter(
            isPresented: $workspace.isChoosingWorkspace,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                workspace.chooseWorkspace(at: url)
            case .failure:
                break
            }
        }
    }

    // MARK: - Computed properties

    /// The teacher's own root file waiting for a yes in this window's folder
    /// (#454). Setting it to nil (a sheet closed some other way) answers
    /// nothing: the file is asked about again on the next pass.
    private var pendingGuidanceAppend: Binding<AgentGuidance.PendingAppend?> {
        return Binding<AgentGuidance.PendingAppend?>(
            get: {
                guard let workspaceURL = workspace.workspaceURL else {
                    return nil
                }
                return ToolchainReadiness.shared.nextPendingAppend(in: workspaceURL)
            },
            set: { _ in }
        )
    }

    /// A footer showing which folder this window is working in, in the
    /// same form Finder's Path Bar uses.
    @ViewBuilder
    var workingFolderPathBar: some View {
        if let workspaceURL = workspace.workspaceURL {
            Divider()
            HStack(spacing: 8) {
                Text("Working folder:")
                    .font(.body.bold())
                FinderPathBarView(folderURL: workspaceURL)
            }
            .padding(.horizontal, 8)
            // Centred in the same band the sidebar's footer occupies, with
            // the extra height below it. The strip has to be taller for the
            // two rules to meet, but centring the contents in the whole
            // strip would sit them lower than the Filter field opposite.
            .frame(maxWidth: .infinity, minHeight: scaledContentHeight, maxHeight: scaledContentHeight, alignment: .leading)
            .padding(.bottom, scaledBottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            // No menu on the strip itself: only the folders in the path
            // carry context menus, so a right-click on a chevron or the
            // blank space offers nothing rather than something surprising.
                .help(workspaceURL.path)
                .accessibilityIdentifier("windowPathBar")
        }
    }

    @ViewBuilder
    var detailView: some View {
        switch workspace.selection {
        case .course(let code):
            if let course = course(withCode: code) {
                // A course kept for reference gets FACTS, never the settings
                // form: the form would ask it to choose a deploy folder, grey
                // Save for ever, and let every other setting be changed on a
                // course the app has called frozen.
                if course.isKeptForReference {
                    ReferenceCourseSummaryView(course: course) {
                        workspace.schoolYearRequestCode = course.code
                    }
                    .id(code)
                } else {
                    CourseSettingsView(course: course)
                        .id(code)
                }
            } else {
                missingSelectionView
            }
        case .section(let code, let sectionNumber):
            if let course = course(withCode: code) {
                SectionDetailView(course: course, sectionNumber: sectionNumber)
                    .id("\(code)-\(sectionNumber)")
            } else {
                // Nothing here can take a Section menu request, so one waiting
                // for this row is dropped rather than left to run later.
                missingSelectionView
                    .onAppear {
                        workspace.sectionVerbRequest = nil
                    }
            }
        case .archived(let identifier):
            if let item = archivedItem(withIdentifier: identifier) {
                ContentUnavailableView {
                    Label(item.title, systemImage: item.symbolName)
                } description: {
                    Text("\(item.subtitle). It is not part of your courses until you restore it.")
                } actions: {
                    Button("Restore…") {
                        workspace.restoreRequest = item
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("restoreArchivedButton")
                    Button("Delete Archive…") {
                        workspace.archiveDeleteRequest = item
                    }
                    .accessibilityIdentifier("deleteArchivedButton")
                }
            } else {
                missingSelectionView
            }
        case .backup(let identifier):
            if let item = backupItem(withIdentifier: identifier) {
                ContentUnavailableView {
                    Label(item.title, systemImage: item.symbolName)
                } description: {
                    Text("\(item.subtitle)\(backupSizeClause(for: item)). A saved copy of \(item.courseCode) — restore it to put the course back the way it was then. \(item.keptDescription) You can delete any of them yourself.")
                } actions: {
                    Button("Restore…") {
                        workspace.backupRestoreRequest = item
                    }
                    // The accent only while it can be pressed (#457).
                    .prominentButton(isEnabled: !workspace.isBeingCopied(item.courseCode))
                    .accessibilityIdentifier("restoreBackupButton")
                    Button("Delete Backup…") {
                        workspace.requestDeleteBackup(item)
                    }
                    .accessibilityIdentifier("deleteBackupButton")
                }
            } else {
                missingSelectionView
            }
        case .allBackups:
            AllBackupsView()
        case nil:
            // Telling someone to choose from an empty list is a dead end.
            if workspace.courses.isEmpty {
                ContentUnavailableView {
                    Label("No Courses Yet", systemImage: "books.vertical")
                } description: {
                    Text("Add your first course, or start from the example course to see how everything fits together.")
                } actions: {
                    // File ▸ New Course…'s own name (#457, the HIG sweep):
                    // one command, one name everywhere.
                    Button("New Course…") {
                        workspace.isShowingNewCourseWizard = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("emptyStateAddCourseButton")
                }
            } else {
                ContentUnavailableView(
                    "Select a Course or Section",
                    systemImage: "sidebar.left",
                    description: Text("Choose a course to edit its settings, or a section to preview and deploy its website.")
                )
            }
        }
    }

    /// " · 15.9 MB" once a backup has been measured, and nothing before.
    func backupSizeClause(for item: BackupItem) -> String {
        guard let size = workspace.sizeDescription(of: item) else {
            return ""
        }
        return " · " + size
    }

    var missingSelectionView: some View {
        ContentUnavailableView(
            "Course Not Found",
            systemImage: "questionmark.folder",
            description: Text("Reload courses from the File menu, or choose a different working folder.")
        )
    }

    // MARK: - Functions

    func archivedItem(withIdentifier identifier: String) -> ArchivedItem? {
        for item in workspace.archivedItems {
            if item.id == identifier {
                return item
            }
        }
        return nil
    }

    func backupItem(withIdentifier identifier: String) -> BackupItem? {
        for item in workspace.backupItems {
            if item.id == identifier {
                return item
            }
        }
        return nil
    }

    func course(withCode code: String) -> Course? {
        for course in workspace.courses {
            if course.code == code {
                return course
            }
        }
        return nil
    }
}

/// The alert for a chosen folder that was refused while the window kept its
/// own folder (#290). A modifier of its own to keep `body` within what the
/// type-checker takes in one go.
struct RefusedFolderAlert: ViewModifier {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Computed properties

    var isPresented: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return workspace.folderNotOpened?.isShownAsAlert == true
            },
            set: { newValue in
                if !newValue && workspace.folderNotOpened?.isShownAsAlert == true {
                    workspace.folderNotOpened = nil
                }
            }
        )
    }

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .alert(
                workspace.folderNotOpened?.headline ?? "",
                isPresented: isPresented
            ) {
                Button(CloudSyncWording.chooseDifferentFolderButton) {
                    workspace.folderNotOpened = nil
                    workspace.isChoosingWorkspace = true
                }
                Button(WorkingFolderReachWording.alertOKButton, role: .cancel) {
                    workspace.folderNotOpened = nil
                }
            } message: {
                Text(workspace.folderNotOpened?.detail ?? "")
            }
    }
}

/// The calm note about a reference course's pages, shown once per course
/// BEFORE the teacher goes into Obsidian.
///
/// **In front of it, not after it**, which is the placement decision the
/// Obsidian measurement forced: what Obsidian SHOWS a teacher who types into
/// a locked page could not be measured, so silent loss is not ruled out — and
/// a note that arrives only after they have typed would be the worst of both.
/// Once per course is enough; after that Open in Obsidian opens it directly,
/// like any other course's.
///
/// A modifier rather than lines on a body, because the sidebar's body
/// reached the point where the Swift compiler gave up type-checking it; it
/// moved here from the sidebar in the HIG sweep (#457), with the request on
/// `WorkspaceModel` so every route — the toolbar's included — asks it.
private struct LockedPagesNoteAlert: ViewModifier {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Functions

    func body(content: Content) -> some View {
        content.alert(
            ReferenceWording.pagesAreLockedTitle,
            isPresented: isPresented,
            presenting: workspace.lockedPagesNoteRequest
        ) { shown in
            Button("Open in Obsidian") {
                workspace.openInObsidianAfterTheNote(shown)
            }
            Button("Not Now", role: .cancel) {
                workspace.lockedPagesNoteRequest = nil
            }
        } message: { _ in
            // No warning icon and no "cannot": a teacher who kept this course
            // for reference asked for it, so it reads as a fact.
            Text(ReferenceWording.pagesAreLocked + "\n\n" + ReferenceWording.obsidianOpensThemForReading)
        }
    }

    private var isPresented: Binding<Bool> {
        return Binding(
            get: { return workspace.lockedPagesNoteRequest != nil },
            set: { showing in
                if !showing {
                    workspace.lockedPagesNoteRequest = nil
                }
            }
        )
    }
}
