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

    /// The tallest a pane may be on the shortest of `screens`, for a
    /// Settings window not yet in a window of its own: until it is, its
    /// screen is not known, and the shortest is the one cap that is never
    /// too tall for wherever Settings opens. On one screen it is that
    /// screen's cap. (The first version read `NSScreen.main`, the key
    /// window's screen, which is too tall when Settings was left on a
    /// shorter display.) Once the window is watched the cap is worked out
    /// again for its own screen.
    static func tallestOnTheShortestScreen(_ screens: [SettingsScreenArea]) -> CGFloat {
        var shortest: CGFloat?
        for screen in screens {
            let height: CGFloat = screen.visibleFrame.height
            if let found = shortest, found <= height {
                continue
            }
            shortest = height
        }
        return tallest(onScreenShowing: shortest ?? 800)
    }

    /// The screen a window of `frame` is on: the one that holds the most of
    /// it, which is how AppKit's `NSWindow.screen` decides, or the first
    /// (the one with the menu bar) when it is on none of them.
    static func screen(holding frame: NSRect, among screens: [SettingsScreenArea]) -> SettingsScreenArea? {
        var holdingTheMost: SettingsScreenArea?
        var mostHeld: CGFloat = 0
        for screen in screens {
            let shared: NSRect = frame.intersection(screen.frame)
            let held: CGFloat = shared.width * shared.height
            if !shared.isNull && held > mostHeld {
                mostHeld = held
                holdingTheMost = screen
            }
        }
        if let holdingTheMost {
            return holdingTheMost
        }
        return screens.first
    }

    /// Whether the bottom edge of a window of `frame` is on show: inside
    /// the visible area of ANY of the displays, not only the one holding
    /// most of the window. With two displays stacked one above the other,
    /// a window on the upper one can hang its bottom onto the lower one,
    /// where nothing of it is hidden (the fourth review).
    static func bottomIsShown(of frame: NSRect, on shownAreas: [NSRect]) -> Bool {
        for area in shownAreas {
            let reachesTheBottom: Bool = area.minY <= frame.minY + 0.5 && frame.minY < area.maxY
            let sharesItsWidth: Bool = area.minX < frame.maxX && frame.minX < area.maxX
            if reachesTheBottom && sharesItsWidth {
                return true
            }
        }
        return false
    }

    /// Where a window must move after AppKit resized it from `before` to
    /// `after`, on a screen whose visible area is `visible`, or nil when it
    /// stays where it is. `shownAreas` are the visible areas of every
    /// display.
    ///
    /// Only a resize that GREW the window and pushed its bottom down out of
    /// sight moves it: a taller pane grows the Settings window downward
    /// from its top edge, so a window that sat on the screen with a short
    /// pane runs past the bottom (past the Dock) with a tall one, its last
    /// controls out of reach. A bottom that lands on another display's
    /// visible area is not out of sight. It is moved up just far enough to
    /// undo what the growth hid: to the visible bottom, or, when the person
    /// had left its bottom lower than that, back to where they left it, so
    /// a taller pane never hides more than was hidden before. Never so far
    /// its title bar leaves the top. Where the person put the window is
    /// never, by itself, a reason to move it: the HIG's Windows page,
    /// "people can reposition them", and "the system remembers window
    /// size and placement".
    static func originAfterResize(from before: NSRect, to after: NSRect, visible: NSRect, shownAreas: [NSRect]) -> NSPoint? {
        if after.height <= before.height + 0.5 {
            return nil
        }
        if after.minY >= before.minY - 0.5 {
            return nil
        }
        if bottomIsShown(of: after, on: shownAreas) {
            return nil
        }
        var bottom: CGFloat = visible.minY
        if before.minY < bottom {
            bottom = before.minY
        }
        if bottom + after.height > visible.maxY {
            bottom = visible.maxY - after.height
        }
        if bottom <= after.minY + 0.5 {
            return nil
        }
        return NSPoint(x: after.minX, y: bottom)
    }

    /// Whether a move of the window from `known` to `now` is the person's
    /// own: the size is unchanged and the origin is not. A pane change
    /// moves the origin too (the top stays, the bottom moves) and changes
    /// the size, so it is never taken for the person's move, whichever of
    /// `didMove` and `didResize` AppKit posts first.
    static func isThePersonsMove(from known: NSRect, to now: NSRect) -> Bool {
        let sameSize: Bool = abs(now.width - known.width) < 0.5 && abs(now.height - known.height) < 0.5
        let moved: Bool = abs(now.minX - known.minX) >= 0.5 || abs(now.minY - known.minY) >= 0.5
        return sameSize && moved
    }
}

/// How far the placement has lifted the Settings window since the person
/// last put it somewhere, so the lift is given back when a shorter pane
/// shrinks the window again (#997, D42, the fourth review). Without it the
/// person's placement survived only the first growth: Short at y = 30, then
/// Tall (lifted onto the screen), then Short again ended 451 pt higher than
/// it was put; and a window left low went back to a different place the
/// second time the same tall pane was chosen. With it, the same pane lands
/// in the same place every time, until the person moves the window, which
/// makes wherever it is theirs and clears what is owed.
struct SettingsWindowLift: Equatable {

    // MARK: - Stored properties

    /// Points the window has been raised by growing panes and not yet
    /// given back.
    private(set) var owed: CGFloat = 0

    // MARK: - Functions

    /// Where the window goes after AppKit resized it from `before` to
    /// `after`, or nil when it stays: lifted when a growth hid its bottom
    /// (`SettingsPaneHeight.originAfterResize`), or lowered again, by no
    /// more than is owed and no more than it shrank, when it shrinks.
    mutating func origin(afterResizeFrom before: NSRect, to after: NSRect, visible: NSRect, shownAreas: [NSRect]) -> NSPoint? {
        if let lifted = SettingsPaneHeight.originAfterResize(from: before, to: after, visible: visible, shownAreas: shownAreas) {
            owed += lifted.y - after.minY
            return lifted
        }
        let shrinkage: CGFloat = before.height - after.height
        if shrinkage > 0.5 && owed > 0.5 {
            var givenBack: CGFloat = shrinkage
            if owed < givenBack {
                givenBack = owed
            }
            owed -= givenBack
            return NSPoint(x: after.minX, y: after.minY - givenBack)
        }
        return nil
    }

    /// The person moved the window: where it is now is theirs, and nothing
    /// is owed.
    mutating func personMovedTheWindow() {
        owed = 0
    }
}

/// One display as `SettingsWindowPlacement` reads it: its whole frame, and
/// the part not under the menu bar or the Dock. A value, so a test can hand
/// the placement displays this Mac does not have.
struct SettingsScreenArea: Equatable {

    // MARK: - Stored properties

    var frame: NSRect

    var visibleFrame: NSRect
}

/// The Settings window's own screen, followed as it changes (#997, D42).
///
/// The first version worked the cap out once, when the pane was drawn,
/// from the key window's screen. When Settings first opens that is the
/// MAIN window's screen, and Settings reopens where it was left, so with
/// the main window on a tall display and Settings left on an 800 pt laptop
/// screen the Assistant pane opened 762 pt tall where about 705 show. This
/// is told the Settings window itself (`WindowAccessor`) and works the cap
/// out again from the screen that holds most of that window whenever AppKit
/// says something it depends on changed: the window moved to another
/// screen (`NSWindow.didChangeScreenNotification`), it became key again
/// (Settings reopened), it was resized, or a screen's arrangement or
/// visible area changed (`NSApplication.didChangeScreenParametersNotification`,
/// posted when the Dock is shown, hidden or moved). No timed delay: each is
/// a notification AppKit posts when the thing has happened.
///
/// The window is MOVED only after a resize that grew it and hid its
/// bottom on every display (`SettingsPaneHeight.originAfterResize`), judged
/// from its frame before and after that resize, and moved back down by
/// what it was lifted when a shorter pane shrinks it again
/// (`SettingsWindowLift`), until the person moves it themselves. Never on a
/// focus change or a screen change, so a window the person left low stays
/// where they put it, and one whose bottom hangs onto a display stacked
/// below is not lifted at all. (The second version moved it on every one
/// of those notifications, and the third review found it snapped back on
/// every click.)
@MainActor
@Observable
final class SettingsWindowPlacement {

    // MARK: - Stored properties

    /// The tallest a pane may be on the Settings window's screen.
    private(set) var tallest: CGFloat

    /// The Settings window, once it has been put in one.
    @ObservationIgnored weak var window: NSWindow?

    /// The displays, as they are now. `NSScreen.screens` in the app; a
    /// test hands in displays of its own, so the choice of screen below it
    /// is what the test checks.
    @ObservationIgnored let screens: @MainActor () -> [SettingsScreenArea]

    /// The window's frame as it was before the latest resize: kept on every
    /// resize and every move, so a resize is judged against where the
    /// window was, not against where it was first seen.
    @ObservationIgnored var frameBeforeResize: NSRect?

    /// What growing panes have lifted the window by, to give back.
    @ObservationIgnored var lift: SettingsWindowLift = SettingsWindowLift()

    /// True while the placement moves the window itself, so the
    /// `didMoveNotification` that move posts is not taken for the person's.
    @ObservationIgnored var isMovingTheWindowItself: Bool = false

    @ObservationIgnored let center: NotificationCenter

    @ObservationIgnored var observers: [NSObjectProtocol] = []

    // MARK: - Initializer

    init(center: NotificationCenter = .default,
         screens: @escaping @MainActor () -> [SettingsScreenArea] = SettingsWindowPlacement.connectedScreens) {
        self.center = center
        self.screens = screens
        self.tallest = SettingsPaneHeight.tallestOnTheShortestScreen(screens())
    }

    isolated deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    // MARK: - Functions

    /// This Mac's displays, as AppKit has them now.
    static func connectedScreens() -> [SettingsScreenArea] {
        var areas: [SettingsScreenArea] = []
        for screen in NSScreen.screens {
            areas.append(SettingsScreenArea(frame: screen.frame, visibleFrame: screen.visibleFrame))
        }
        return areas
    }

    /// Starts following `window`: its screen, its size, and the screens'
    /// visible areas. Called once, the moment the pane joins the window.
    func watch(_ window: NSWindow) {
        self.window = window
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        frameBeforeResize = window.frame
        let capNames: [Notification.Name] = [
            NSWindow.didChangeScreenNotification,
            NSWindow.didBecomeKeyNotification,
        ]
        for name in capNames {
            let observer: NSObjectProtocol = center.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshCap()
                }
            }
            observers.append(observer)
        }
        let resized: NSObjectProtocol = center.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowWasResized()
            }
        }
        observers.append(resized)
        let moved: NSObjectProtocol = center.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowWasMoved()
            }
        }
        observers.append(moved)
        let screensChanged: NSObjectProtocol = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshCap()
            }
        }
        observers.append(screensChanged)
        refreshCap()
    }

    /// The visible area of the screen that holds most of the Settings
    /// window, or of the shortest screen before there is a window.
    func visibleFrame() -> NSRect? {
        let areas: [SettingsScreenArea] = screens()
        guard let window else {
            var shortest: SettingsScreenArea?
            for area in areas {
                if let found = shortest, found.visibleFrame.height <= area.visibleFrame.height {
                    continue
                }
                shortest = area
            }
            return shortest?.visibleFrame
        }
        return SettingsPaneHeight.screen(holding: window.frame, among: areas)?.visibleFrame
    }

    /// Works the cap out again for the window's screen. Never moves the
    /// window.
    func refreshCap() {
        guard let visible = visibleFrame() else {
            return
        }
        let cap: CGFloat = SettingsPaneHeight.tallest(onScreenShowing: visible.height)
        if cap != tallest {
            tallest = cap
        }
    }

    /// After AppKit moved the window. A move that kept the size is the
    /// person's (or the system's on their behalf), so the window's place
    /// is theirs and nothing lifted is given back; a move that came with a
    /// resize is left for `windowWasResized()` to judge.
    func windowWasMoved() {
        guard let window, !isMovingTheWindowItself else {
            return
        }
        let now: NSRect = window.frame
        guard let known = frameBeforeResize else {
            frameBeforeResize = now
            return
        }
        if SettingsPaneHeight.isThePersonsMove(from: known, to: now) {
            lift.personMovedTheWindow()
            frameBeforeResize = now
        }
    }

    /// After AppKit resized the window: moves it up if the resize grew it
    /// and hid its bottom, or back down by what it was lifted if a shorter
    /// pane shrank it, then works the cap out again.
    func windowWasResized() {
        guard let window else {
            return
        }
        let after: NSRect = window.frame
        let before: NSRect = frameBeforeResize ?? after
        frameBeforeResize = after
        // A person dragging an edge is placing the window themselves.
        if window.isVisible && !window.inLiveResize, let visible = visibleFrame() {
            var shownAreas: [NSRect] = []
            for area in screens() {
                shownAreas.append(area.visibleFrame)
            }
            if let origin = lift.origin(afterResizeFrom: before, to: after, visible: visible, shownAreas: shownAreas) {
                isMovingTheWindowItself = true
                window.setFrameOrigin(origin)
                isMovingTheWindowItself = false
                frameBeforeResize = window.frame
            }
        }
        refreshCap()
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
