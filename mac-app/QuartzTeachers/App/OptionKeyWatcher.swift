import AppKit
import Observation

/// Whether Option is held down, for the Preview button's TITLE (#504).
///
/// The title has to change while Option is held — Russell's comment on #504:
/// the button says what a press will do — and a toolbar item has no native
/// alternate the way a menu item does. Whether SwiftUI's
/// `modifierKeyAlternate` swaps a TOOLBAR label could not be measured
/// without activating a window on a Mac in use (504 plan review M-b), so the
/// title reads this instead: one `flagsChanged` monitor for the app,
/// installed at launch, cleared when the app goes to the background (a key
/// let go elsewhere sends Plantoir no event) and read afresh when it comes
/// back.
///
/// **Only the KEY window's toolbar reads it** (implementation review, 4):
/// Option typed for é or for word movement in the assistant or Course
/// Settings must not flip every open section window's button, a threefold
/// width change on a toolbar this app already handles with care. The
/// section view reads `controlActiveState` FIRST, so a window that is not
/// key never reads this value and is not redrawn when it changes.
///
/// **This is for the title only.** The press itself reads
/// `NSEvent.modifierFlags` at the moment it happens, which is the authority:
/// a first click on a window that was not active, with Option already held,
/// had no `flagsChanged` to swap the title on, and still does what Option
/// says (documented as a known limit in doc 09).
@Observable
final class OptionKeyWatcher {

    // MARK: - Stored properties

    /// The app's one watcher.
    static let shared: OptionKeyWatcher = OptionKeyWatcher()

    /// True while Option is held and Plantoir is the active app.
    var optionIsHeld: Bool = false

    /// The local event monitor, once installed.
    @ObservationIgnored private var monitor: Any?

    /// The observer of menus closing, once installed.
    @ObservationIgnored private var menuObserver: (any NSObjectProtocol)?

    // MARK: - Functions

    /// Installs the monitor, once.
    func start() {
        if monitor != nil {
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            OptionKeyWatcher.shared.note(event.modifierFlags)
            return event
        }
        // A menu's tracking loop does not pass `flagsChanged` through the
        // monitor: Option let go inside an open Section menu would otherwise
        // leave the toolbar saying "Preview at Last Viewed" after the menu
        // closed (implementation review, 3). Ask the keyboard when it closes.
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                OptionKeyWatcher.shared.note(NSEvent.modifierFlags)
            }
        }
        note(NSEvent.modifierFlags)
    }

    /// Records what the flags say, writing only a change so the views that
    /// read it are not redrawn for Shift or Command.
    func note(_ flags: NSEvent.ModifierFlags) {
        let held: Bool = PreviewStartPage.optionIsHeld(flags)
        if held != optionIsHeld {
            optionIsHeld = held
        }
    }

    /// The app went to the background: a key let go there is never seen.
    func appResignedActive() {
        if optionIsHeld {
            optionIsHeld = false
        }
    }

    /// The app came back: ask the keyboard rather than assume.
    func appBecameActive() {
        note(NSEvent.modifierFlags)
    }
}
