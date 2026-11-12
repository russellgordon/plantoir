import SwiftUI

/// A course's page (#708): its settings, as always, and while Claude Code or
/// Codex is installed a Planning tab beside them, Settings | Planning in a
/// thin bar (`DetailTabs`, the switch #717 built for a section's
/// Website | Problems).
///
/// **The settings stay MOUNTED.** The Planning tab is drawn OVER them in a
/// `ZStack` rather than instead of them, so a setting typed and not yet
/// saved is still there after a look at the plan, and Course ▸ Save keeps
/// working. A `TabView` would unmount the hidden tab and lose the edit.
///
/// **No assistant, no tab.** With neither installed the page is exactly
/// what it was before #708: no tabs and no word about planning (Russell,
/// 2026-11-01: absent, never disabled). The flags are
/// `OutsideAssistantPresence`'s, asked at launch and whenever Plantoir
/// becomes active, so installing or removing an assistant shows here the
/// next time the teacher comes back to Plantoir. A course kept for
/// reference never reaches this view (`MainWindowView` gives it its facts).
struct CourseDetailView: View {

    // MARK: - Stored properties

    let course: Course

    /// Which tab is chosen. Starts on Settings for every course
    /// (`.id(code)` in `MainWindowView` makes the view afresh per course).
    @State var selectedTab: CourseDetailTab = .settings

    /// The plan's web view and the unit chosen, kept while this course's
    /// page is open so a switch to Settings and back finds them.
    @State var planning: PlanningTabModel = PlanningTabModel()

    @Environment(WorkspaceModel.self) var workspace

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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if showsTheTabs {
                DetailTabs(
                    tabs: [
                        (tab: CourseDetailTab.settings, title: PlanningWording.tabSettings),
                        (tab: CourseDetailTab.planning, title: PlanningWording.tabPlanning),
                    ],
                    selection: $selectedTab,
                    identifier: "courseTabs"
                )
            }
            ZStack {
                // Base layer: the settings, always mounted.
                CourseSettingsView(course: course)
                    .accessibilityHidden(showsPlanning)

                // Top layer: the Planning tab, drawn over the settings.
                if showsPlanning, let folder = workspace.workspaceURL {
                    PlanningTabView(course: course, folder: folder, model: planning)
                }
            }
        }
        .onChange(of: showsTheTabs) { (_: Bool, nowShown: Bool) in
            if !nowShown {
                selectedTab = .settings
            }
        }
    }
}
