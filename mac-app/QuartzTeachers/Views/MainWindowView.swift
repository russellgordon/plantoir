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
            } else if workspace.workspaceURL == nil || workspace.workspaceProblem != nil || workspace.workspaceCanBeInitialized || workspace.workspaceIsUnrecognized || workspace.needsCloudSyncDecision {
                WorkspacePickerView()
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
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
                CourseSettingsView(course: course)
                    .id(code)
            } else {
                missingSelectionView
            }
        case .section(let code, let sectionNumber):
            if let course = course(withCode: code) {
                SectionDetailView(course: course, sectionNumber: sectionNumber)
                    .id("\(code)-\(sectionNumber)")
            } else {
                missingSelectionView
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
                    Text("\(item.subtitle). A saved copy of \(item.courseCode) — restore it to put the course back the way it was then. \(item.keptDescription) You can delete any of them yourself.")
                } actions: {
                    Button("Restore…") {
                        workspace.backupRestoreRequest = item
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("restoreBackupButton")
                    Button("Delete Backup…") {
                        workspace.backupDeleteRequest = item
                    }
                    .accessibilityIdentifier("deleteBackupButton")
                }
            } else {
                missingSelectionView
            }
        case nil:
            // Telling someone to choose from an empty list is a dead end.
            if workspace.courses.isEmpty {
                ContentUnavailableView {
                    Label("No Courses Yet", systemImage: "books.vertical")
                } description: {
                    Text("Add your first course, or start from the example course to see how everything fits together.")
                } actions: {
                    Button("Add a Course…") {
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
