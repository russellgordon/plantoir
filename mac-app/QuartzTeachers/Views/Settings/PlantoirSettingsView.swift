import AppKit
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
/// **Five panes since #855 — Assistant, Preview, Obsidian, Deploying and
/// Other Assistants.** Four panes since #495 — Assistant, Preview, Obsidian
/// and Deploying.
/// Three panes since #504 — Assistant, Preview and Deploying. Two panes,
/// Assistant and Deploying, in a `TabView` since the HIG sweep
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

    /// Every pane's width.
    static let paneWidth: CGFloat = 560

    // MARK: - Computed properties

    var body: some View {
        TabView(selection: $pane) {
            AssistantSettingsView()
                .settingsPaneFitsItsContent()
                .tabItem {
                    Label("Assistant", systemImage: "sparkles")
                }
                .tag(SettingsPane.assistant.rawValue)
            // Where Preview opens (#504): its own pane, between the two that
            // were here, because it is neither about the assistant nor about
            // deploying (decision 504-5).
            PreviewSettingsView()
                .settingsPaneFitsItsContent()
                .tabItem {
                    Label(PreviewStartPageWording.paneTitle, systemImage: "play.rectangle")
                }
                .tag(SettingsPane.preview.rawValue)
            // Obsidian's add-ons for diagrams and graphs (#495): after
            // Preview, the one way back from "Don't ask again".
            ObsidianSettingsView()
                .settingsPaneFitsItsContent()
                .tabItem {
                    Label(ObsidianFigureAddOnsWording.paneTitle, systemImage: "square.and.pencil")
                }
                .tag(SettingsPane.obsidian.rawValue)
            DeployingSettingsView()
                .settingsPaneFitsItsContent()
                .tabItem {
                    Label("Deploying", systemImage: "paperplane")
                }
                .tag(SettingsPane.deploying.rawValue)
            // The outside assistants Plantoir can set up (#855, ruling 3):
            // last, because Plantoir works without any of them.
            OtherAssistantsSettingsView()
                .settingsPaneFitsItsContent()
                .tabItem {
                    Label(AssistantSetUpWording.paneTitle, systemImage: "person.2")
                }
                .tag(SettingsPane.otherAssistants.rawValue)
        }
        // Fixed width, the way macOS settings windows are: the panel is a
        // column of sentences, and a resizable one lets the explanations
        // stretch into single lines that are far harder to read.
        .frame(width: PlantoirSettingsView.paneWidth)
        // `.contain` BEFORE the identifier (#353): without it SwiftUI puts
        // the container's identifier on every element inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plantoirSettings")
    }
}

/// How tall a Settings pane may be on the screen it opens on (#997, D42).
///
/// A pane is as tall as what it holds, up to what the screen can show:
/// beyond that its form scrolls, so the bottom of a tall pane (the
/// Assistant pane's Remove…, 674 pt of content) is still reached on a
/// short screen (1280 x 800 with the Dock, or a scaled 1024 x 640).
enum SettingsPaneHeight {

    // MARK: - Stored properties

    /// The Settings window's frame above its pane: the title bar with the
    /// pane buttons under it. Measured on the running window on 2026-11-20
    /// (macOS 26): 648 pt tall around a pane held at 560.
    static let windowChrome: CGFloat = 88

    /// Kept clear above and below the window, so it never meets the menu
    /// bar or the Dock edge to edge.
    static let screenMargin: CGFloat = 20

    /// Below this a pane is not made smaller, however short the screen:
    /// a sliver of a form is no use to anyone.
    static let fewest: CGFloat = 240

    // MARK: - Functions

    /// The tallest a pane may be on a screen whose visible area (without
    /// the menu bar and the Dock) is `visibleHeight` points tall.
    static func tallest(onScreenShowing visibleHeight: CGFloat) -> CGFloat {
        let room: CGFloat = visibleHeight - windowChrome - screenMargin * 2
        if room < fewest {
            return fewest
        }
        return room
    }

    /// The tallest a pane may be on the screen the Settings window opens
    /// on: the key window's screen, else the main screen.
    static func tallestOnThisScreen() -> CGFloat {
        var screen: NSScreen? = NSApp.keyWindow?.screen
        if screen == nil {
            screen = NSScreen.main
        }
        guard let screen else {
            return tallest(onScreenShowing: 800)
        }
        return tallest(onScreenShowing: screen.visibleFrame.height)
    }
}

extension View {

    // MARK: - Functions

    /// A Settings pane as tall as what it holds, up to `tallest` (#997,
    /// D42), so the window takes each pane's own height as its tab is
    /// chosen, and a pane taller than the screen allows scrolls rather
    /// than running off it. Until #997 every pane opened at 560 x 648:
    /// Preview and Obsidian were mostly empty space, and Assistant, held
    /// at 560, scrolled. The HIG's Settings page: "a settings window
    /// accommodates the size of the current pane, people don't need to
    /// expand the window to see more."
    ///
    /// The cap comes BEFORE `fixedSize`: asked for its ideal height, the
    /// frame answers the content's own height or `tallest`, whichever is
    /// less, and the form inside, given that height, scrolls the rest.
    /// `fixedSize` alone (the first version) let a 674 pt pane run past a
    /// 640 pt screen with no way to its bottom.
    func settingsPaneFitsItsContent(tallest: CGFloat? = nil) -> some View {
        var cap: CGFloat = 0
        if let tallest {
            cap = tallest
        } else {
            cap = SettingsPaneHeight.tallestOnThisScreen()
        }
        return self
            .frame(width: PlantoirSettingsView.paneWidth)
            .frame(maxHeight: cap)
            .fixedSize(horizontal: false, vertical: true)
    }
}
