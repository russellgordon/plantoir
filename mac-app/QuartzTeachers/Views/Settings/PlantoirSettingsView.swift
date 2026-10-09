import SwiftUI

/// The app's own settings — the ones that belong to the teacher and their
/// Mac rather than to any one course.
///
/// Reached from Plantoir ▸ Settings… (⌘,), which is where every other Mac
/// application keeps them, so nobody has to be told where it is. Deliberately
/// separate from a course's settings, which live in the main window beside the
/// course they describe: mixing "how should this class's site look" with "how
/// much of this Mac may the assistant use" would put two different kinds of
/// answer in one list, and the teacher would have to work out which was which
/// every time they opened it.
///
/// **Two panes, Assistant and Deploying, in a `TabView`** since the HIG sweep
/// (#457 item 4; Russell, 2026-10-08: the Cloudflare Account ID moves here).
/// Until then this was one pane with NO `TabView`, and that was a decision:
/// macOS titles a settings window after the SELECTED TAB, so a one-tab window
/// came up called "Assistant", which reads as a window about the assistant a
/// teacher has ended up in by mistake. With two panes the tab bar is the
/// thing a teacher reads, and a window titled after the pane they chose is
/// how every multi-pane Mac settings window behaves — the reason against it
/// was the single tab, not the title.
///
/// Which pane shows is remembered (`SettingsPane`), so a course's Open
/// Settings… button can ask for Deploying before the window opens.
struct PlantoirSettingsView: View {

    // MARK: - Stored properties

    @AppStorage(SettingsPane.storageKey, store: PlantoirDefaults.shared)
    var pane: String = SettingsPane.assistant.rawValue

    // MARK: - Computed properties

    var body: some View {
        TabView(selection: $pane) {
            AssistantSettingsView()
                .tabItem {
                    Label("Assistant", systemImage: "sparkles")
                }
                .tag(SettingsPane.assistant.rawValue)
            DeployingSettingsView()
                .frame(minHeight: 240)
                .tabItem {
                    Label("Deploying", systemImage: "paperplane")
                }
                .tag(SettingsPane.deploying.rawValue)
        }
        // Fixed width, the way macOS settings windows are: the panel is a
        // column of sentences, and a resizable one lets the explanations
        // stretch into single lines that are far harder to read.
        .frame(width: 560)
        // `.contain` BEFORE the identifier (#353): without it SwiftUI puts
        // the container's identifier on every element inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plantoirSettings")
    }
}
