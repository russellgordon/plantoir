import SwiftUI

/// A course's page (#708): its settings, as always, and while Claude Code or
/// Codex is installed a Planning tab beside them, Settings | Planning in a
/// thin bar (`DetailTabs`, the switch #717 built for a section's
/// Website | Problems).
///
/// **Only the chosen tab is in the window.** With Planning chosen the
/// settings form is not drawn at all (`CourseDetailContent`), so nothing in
/// it can hold the keyboard, be reached by Tab, be read by VoiceOver or sit
/// in the responder chain. The first fix drew Planning OVER a disabled form,
/// and a disabled `TextEditor` (the footer box) still took keys (708 fix
/// review, H1); a form that is not there cannot take any. What the teacher
/// typed and has not saved is the course's `configuration`, which the course
/// owns, and the form's notices are its `CourseSettingsSession`, which this
/// page owns, so coming back to Settings shows the form exactly as it was
/// left, with nothing focused.
///
/// **Undo is cleared on every switch** (`CourseDetailTabs.choose`): the
/// window has one undo manager, and actions a field registered would
/// otherwise stay on it after the field is gone, so ⌘Z on Planning would
/// undo typing in a box that is not on screen (fix review, M1). ⌘Z on
/// Settings undoes what was typed since the teacher last came to it; on
/// Planning there is nothing to undo, since a plan cannot be edited there.
///
/// **⌘S on Planning saves the settings as the teacher left them**, the same
/// Save as the form's (`CourseDetailTabs.planningCommands`): only edits made
/// on Settings can be there, because nothing on Planning edits a setting.
/// Revert is not offered on Planning: it would discard edits the teacher
/// cannot see.
///
/// **No assistant, no tab.** With neither installed the page is exactly what
/// it was before #708: no tabs and no word about planning (Russell,
/// 2026-11-01: absent, never disabled). A course kept for reference never
/// reaches this view (`MainWindowView` gives it its facts).
struct CourseDetailView: View {

    // MARK: - Stored properties

    let course: Course

    /// Which tab is chosen. Starts on Settings for every course
    /// (`.id(code)` in `MainWindowView` makes the view afresh per course).
    @State var selectedTab: CourseDetailTab = .settings

    /// The plan's web view and the unit chosen, kept while this course's
    /// page is open so a switch to Settings and back finds them.
    @State var planning: PlanningTabModel = PlanningTabModel()

    /// The settings form's notices, kept while the form is not drawn.
    @State var settingsSession: CourseSettingsSession = CourseSettingsSession()

    @Environment(WorkspaceModel.self) var workspace

    @Environment(\.undoManager) var undoManager: UndoManager?

    // MARK: - Computed properties

    var presence: OutsideAssistantPresence {
        return OutsideAssistantPresence.shared
    }

    /// `unitPlanning.tab.tabCases`.
    var showsTheTabs: Bool {
        return PlanningTab.isShown(
            claudeIsInstalled: presence.claudeIsInstalled,
            codexIsInstalled: presence.codexIsInstalled,
            courseIsKeptForReference: course.isKeptForReference
        )
    }

    /// Whether the Planning tab is on screen: chosen, and still offered. A
    /// tab chosen and then taken away (the assistant removed) shows Settings.
    var showsPlanning: Bool {
        return showsTheTabs && selectedTab == .planning
    }

    /// The tab switch, clearing Undo before the tab changes.
    var tabBinding: Binding<CourseDetailTab> {
        return Binding(
            get: {
                return selectedTab
            },
            set: { (chosen: CourseDetailTab) in
                CourseDetailTabs.choose(chosen, current: &selectedTab, undoManager: undoManager)
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if showsTheTabs {
                DetailTabs(
                    tabs: [
                        (tab: CourseDetailTab.settings, title: PlanningWording.tabSettings),
                        (tab: CourseDetailTab.planning, title: PlanningWording.tabPlanning),
                    ],
                    selection: tabBinding,
                    identifier: "courseTabs"
                )
            }
            CourseDetailContent(course: course, session: settingsSession, showsPlanning: showsPlanning) {
                if let folder = workspace.workspaceURL {
                    PlanningTabView(course: course, folder: folder, model: planning)
                        .navigationTitle(course.displayCode)
                        .navigationSubtitle(course.configuration.courseName)
                        .focusedSceneValue(
                            \.courseSettingsMenu,
                            CourseDetailTabs.planningCommands(course: course, session: settingsSession)
                        )
                }
            }
        }
        .toolbar {
            // Here rather than in the form, so it stays on both tabs: a
            // toolbar item that comes and goes makes macOS rebuild the
            // toolbar (`DetailTabs`' comment).
            ToolbarItem {
                Button("Open in Obsidian", systemImage: "square.and.pencil") {
                    // The one route every Open in Obsidian takes (#457).
                    workspace.openInObsidian(course: course, sectionNumber: nil)
                }
                .disabled(!FolderActions.obsidianIsInstalled)
                .help("Edit this course's pages in Obsidian")
                .accessibilityIdentifier("openCourseInObsidianButton")
            }
        }
        .onChange(of: showsTheTabs) { (_: Bool, nowShown: Bool) in
            if !nowShown {
                CourseDetailTabs.choose(.settings, current: &selectedTab, undoManager: undoManager)
            }
        }
    }
}

/// The page under the tabs: the settings form, or the Planning tab, never
/// both. Its own view, with the Planning half handed in, so a test can draw
/// it with no window model and look at what is in the tree
/// (`CourseDetailStructureTests`).
struct CourseDetailContent<Planning: View>: View {

    // MARK: - Stored properties

    let course: Course
    let session: CourseSettingsSession
    let showsPlanning: Bool
    @ViewBuilder let planning: () -> Planning

    // MARK: - Body

    var body: some View {
        if showsPlanning {
            planning()
        } else {
            CourseSettingsView(course: course, session: session)
        }
    }
}

/// The two rules of the course page's tabs that are not drawing: what a
/// switch does to Undo, and what Course ▸ Save does on Planning.
enum CourseDetailTabs {

    // MARK: - Functions

    /// Moves to `chosen`, clearing the window's undo actions first when it
    /// is a change: an action left by a field that is about to leave the
    /// window would act on something not on screen (708 fix review, M1).
    static func choose(_ chosen: CourseDetailTab, current: inout CourseDetailTab, undoManager: UndoManager?) {
        if chosen == current {
            return
        }
        undoManager?.removeAllActions()
        current = chosen
    }

    /// Course ▸ Save on the Planning tab: the settings form's own Save, run
    /// on the page's session, so its notices are there when the teacher
    /// comes back. The form's Save reads only the course, the session and
    /// app-wide settings, nothing SwiftUI keeps for a drawn view. Revert is
    /// not offered here: it would throw away edits the teacher cannot see.
    static func planningCommands(course: Course, session: CourseSettingsSession) -> CourseSettingsCommands {
        let form: CourseSettingsView = CourseSettingsView(course: course, session: session)
        return CourseSettingsCommands(
            maySave: form.saveIsEnabled,
            mayRevert: false,
            perform: { (item: SubjectMenuRules.Item) in
                if item == .saveCourseSettings {
                    form.performSettingsMenuItem(item)
                }
            }
        )
    }
}
