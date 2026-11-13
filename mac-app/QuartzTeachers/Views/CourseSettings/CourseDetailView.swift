import SwiftUI

/// A course's page (#708): its settings, as always, and while Claude Code or
/// Codex is installed a Planning tab beside them, Settings | Planning in a
/// thin bar (`DetailTabs`, the switch #717 built for a section's
/// Website | Problems, Website | Coverage | Problems since #793).
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
/// **Undo is cleared on every switch** (`CourseDetailTabs.choose`), as a
/// guard. Measured (708 fix review 2, L1): with the form removed, the footer
/// box's own Undo leaves with it, so the clear is not what makes Undo safe
/// today; it is kept so a control added to the form later cannot leave an
/// action behind that ⌘Z on Planning would run on something not on screen
/// (fix review, M1, measured on the layered shape). The window's undo
/// manager has no other user (a grep for `registerUndo` and `undoManager`
/// finds none), so the clear costs the teacher nothing outside this page.
/// ⌘Z on Settings undoes what was typed since the teacher last came to it;
/// on Planning there is nothing to undo.
///
/// **⌘S on Planning saves the settings as the teacher left them**, the same
/// Save as the form's (`CourseDetailTabs.planningCommands`): only edits made
/// on Settings can be there, because nothing on Planning edits a setting.
/// It is never silent: a Save that worked says the form's "Saved ✓" on the
/// Planning tab; one refused, failed or with something to say takes the
/// teacher to Settings, where the form shows its own sentence by the field.
/// Revert is dimmed on Planning, with a line under it saying why: it would
/// discard edits the teacher cannot see.
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

    /// Course ▸ Save and Revert while Planning shows.
    var planningCommands: CourseSettingsCommands {
        let tabs: Binding<CourseDetailTab> = tabBinding
        return CourseDetailTabs.planningCommands(course: course, session: settingsSession, showSettings: {
            tabs.wrappedValue = .settings
        })
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
                        .overlay(alignment: .bottomTrailing) {
                            // ⌘S here said so, in the form's words, for as
                            // long as the form would (708 fix review 2, L3).
                            if settingsSession.didJustSave {
                                Text(CourseSettingsView.savedConfirmation)
                                    .padding(8)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .padding(12)
                                    .accessibilityIdentifier("planningSavedConfirmation")
                            }
                        }
                        .focusedSceneValue(\.courseSettingsMenu, planningCommands)
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
    /// is a change. A guard: the form's own controls take their Undo with
    /// them when they leave (measured, 708 fix review 2, L1), and this keeps
    /// a control added later from leaving an action behind.
    static func choose(_ chosen: CourseDetailTab, current: inout CourseDetailTab, undoManager: UndoManager?) {
        if chosen == current {
            return
        }
        undoManager?.removeAllActions()
        current = chosen
    }

    /// What the Planning tab does after a Save run there
    /// (`unitPlanning.tab.saveOnPlanningCases`).
    enum AfterASave: String {
        /// Saved, with nothing more to say: the tab says the form's
        /// `savedConfirmation` for as long as the form would.
        case staysOnPlanning
        /// Refused, failed, or saved with something to say (a preview
        /// running, another window's change replaced): the page goes to
        /// Settings, where the form shows its own sentence beside the field.
        case showsSettings
    }

    /// The rule, from what the form's Save left in the session. Never
    /// silent: a Save that said nothing on Planning would leave a refused
    /// or failed Save unseen (708 fix review 2, L3).
    static func afterASave(_ session: CourseSettingsSession) -> AfterASave {
        if session.saveProblem != nil || session.saveNotice != nil {
            return .showsSettings
        }
        return .staysOnPlanning
    }

    /// Course ▸ Save on the Planning tab: the settings form's own Save, run
    /// on the page's session, so its sentences are the form's. The form's
    /// Save reads only the course, the session and app-wide settings,
    /// nothing SwiftUI keeps for a drawn view. It is offered whenever there
    /// is something unsaved, held back or not, so a held-back Save is
    /// pressed, refused with the form's own reason, and shown on Settings
    /// rather than dimmed with none (`afterASave`). Revert is dimmed here
    /// with `PlanningWording.revertOnPlanning` under it: it would throw away
    /// edits the teacher cannot see.
    static func planningCommands(
        course: Course, session: CourseSettingsSession, showSettings: @escaping () -> Void
    ) -> CourseSettingsCommands {
        let form: CourseSettingsView = CourseSettingsView(course: course, session: session)
        return CourseSettingsCommands(
            maySave: course.configuration.hasUnsavedChanges,
            mayRevert: false,
            revertNote: PlanningWording.revertOnPlanning,
            perform: { (item: SubjectMenuRules.Item) in
                if item != .saveCourseSettings || !course.configuration.hasUnsavedChanges {
                    return
                }
                form.save()
                if afterASave(session) == .showsSettings {
                    showSettings()
                }
            }
        )
    }
}
