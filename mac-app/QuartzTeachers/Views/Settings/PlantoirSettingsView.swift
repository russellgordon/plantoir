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

    /// The screen the Settings window is on, and how tall a pane may be
    /// there (#997, D42).
    @State var placement: SettingsWindowPlacement = SettingsWindowPlacement()

    /// Every pane's width.
    static let paneWidth: CGFloat = 560

    // MARK: - Computed properties

    var body: some View {
        TabView(selection: $pane) {
            AssistantSettingsView()
                .settingsPaneFitsItsContent(tallest: placement.tallest)
                .tabItem {
                    Label("Assistant", systemImage: "sparkles")
                }
                .tag(SettingsPane.assistant.rawValue)
            // Where Preview opens (#504): its own pane, between the two that
            // were here, because it is neither about the assistant nor about
            // deploying (decision 504-5).
            PreviewSettingsView()
                .settingsPaneFitsItsContent(tallest: placement.tallest)
                .tabItem {
                    Label(PreviewStartPageWording.paneTitle, systemImage: "play.rectangle")
                }
                .tag(SettingsPane.preview.rawValue)
            // Obsidian's add-ons for diagrams and graphs (#495): after
            // Preview, the one way back from "Don't ask again".
            ObsidianSettingsView()
                .settingsPaneFitsItsContent(tallest: placement.tallest)
                .tabItem {
                    Label(ObsidianFigureAddOnsWording.paneTitle, systemImage: "square.and.pencil")
                }
                .tag(SettingsPane.obsidian.rawValue)
            DeployingSettingsView()
                .settingsPaneFitsItsContent(tallest: placement.tallest)
                .tabItem {
                    Label("Deploying", systemImage: "paperplane")
                }
                .tag(SettingsPane.deploying.rawValue)
            // The outside assistants Plantoir can set up (#855, ruling 3):
            // last, because Plantoir works without any of them.
            OtherAssistantsSettingsView()
                .settingsPaneFitsItsContent(tallest: placement.tallest)
                .tabItem {
                    Label(AssistantSetUpWording.paneTitle, systemImage: "person.2")
                }
                .tag(SettingsPane.otherAssistants.rawValue)
        }
        // Fixed width, the way macOS settings windows are: the panel is a
        // column of sentences, and a resizable one lets the explanations
        // stretch into single lines that are far harder to read.
        .frame(width: PlantoirSettingsView.paneWidth)
        // The Settings window itself, the moment the pane is put in it, so
        // the cap follows the window's OWN screen rather than whichever
        // window was key when Settings opened (the same accessor the
        // assistant's window uses to put itself back where it was left).
        .background(WindowAccessor { window in
            placement.watch(window)
        })
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

    /// The tallest a pane may be on the main screen, for a Settings window
    /// not yet in a window of its own.
    static func tallestOnTheMainScreen() -> CGFloat {
        guard let screen = NSScreen.main else {
            return tallest(onScreenShowing: 800)
        }
        return tallest(onScreenShowing: screen.visibleFrame.height)
    }

    /// Where a window of `frame` must move to stay on a screen whose
    /// visible area is `visible`, or nil when it already does. A taller
    /// pane grows the Settings window downward from its top edge, so a
    /// window left low on the screen would run past the bottom (past the
    /// Dock) with its last controls out of reach; it is moved up just far
    /// enough, and never so far that its title bar leaves the top.
    static func originKeepingOnScreen(_ frame: NSRect, visible: NSRect) -> NSPoint? {
        if frame.minY >= visible.minY - 0.5 {
            return nil
        }
        var bottom: CGFloat = visible.minY
        if bottom + frame.height > visible.maxY {
            bottom = visible.maxY - frame.height
        }
        return NSPoint(x: frame.minX, y: bottom)
    }
}

/// The Settings window's own screen, followed as it changes (#997, D42).
///
/// The first version worked the cap out once, when the pane was drawn,
/// from the key window's screen. When Settings first opens that is the
/// MAIN window's screen, and Settings reopens where it was left, so with
/// the main window on a tall display and Settings left on an 800 pt laptop
/// screen the Assistant pane opened 762 pt tall where about 705 show. This
/// is told the Settings window itself (`WindowAccessor`) and works the cap
/// out again from that window's screen whenever AppKit says something it
/// depends on changed: the window moved to another screen
/// (`NSWindow.didChangeScreenNotification`), it became key again (Settings
/// reopened), or a screen's arrangement or visible area changed
/// (`NSApplication.didChangeScreenParametersNotification`, which is posted
/// when the Dock is shown, hidden or moved). No timed delay: each is a
/// notification AppKit posts when the thing has happened.
@MainActor
@Observable
final class SettingsWindowPlacement {

    // MARK: - Stored properties

    /// The tallest a pane may be on the Settings window's screen.
    private(set) var tallest: CGFloat

    /// The Settings window, once it has been put in one.
    @ObservationIgnored weak var window: NSWindow?

    /// For tests: the visible frame to use instead of the window's screen's.
    @ObservationIgnored var visibleFrameOverride: NSRect?

    @ObservationIgnored let center: NotificationCenter

    @ObservationIgnored var observers: [NSObjectProtocol] = []

    // MARK: - Initializer

    init(center: NotificationCenter = .default, visibleFrame: NSRect? = nil) {
        self.center = center
        self.visibleFrameOverride = visibleFrame
        if let visibleFrame {
            self.tallest = SettingsPaneHeight.tallest(onScreenShowing: visibleFrame.height)
        } else {
            self.tallest = SettingsPaneHeight.tallestOnTheMainScreen()
        }
    }

    isolated deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    // MARK: - Functions

    /// Starts following `window`: its screen, and the screens' visible
    /// areas. Called once, the moment the pane joins the window.
    func watch(_ window: NSWindow) {
        self.window = window
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        let windowNames: [Notification.Name] = [
            NSWindow.didChangeScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResizeNotification,
        ]
        for name in windowNames {
            let observer: NSObjectProtocol = center.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            observers.append(observer)
        }
        let screens: NSObjectProtocol = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        observers.append(screens)
        refresh()
    }

    /// The visible area of the screen the Settings window is on.
    func visibleFrame() -> NSRect? {
        if let visibleFrameOverride {
            return visibleFrameOverride
        }
        if let screen = window?.screen {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }

    /// Works the cap out again for the window's screen, and keeps the
    /// window's bottom on that screen.
    func refresh() {
        guard let visible = visibleFrame() else {
            return
        }
        let cap: CGFloat = SettingsPaneHeight.tallest(onScreenShowing: visible.height)
        if cap != tallest {
            tallest = cap
        }
        guard let window, window.isVisible else {
            return
        }
        if let origin = SettingsPaneHeight.originKeepingOnScreen(window.frame, visible: visible) {
            window.setFrameOrigin(origin)
        }
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
    func settingsPaneFitsItsContent(tallest: CGFloat) -> some View {
        return self
            .frame(width: PlantoirSettingsView.paneWidth)
            .frame(maxHeight: tallest)
            .fixedSize(horizontal: false, vertical: true)
    }
}
