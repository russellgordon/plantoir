import AppKit
import SwiftUI

/// Hands the hosting `NSWindow` to SwiftUI content once it is in a window.
///
/// The window is not available when a view appears, only once the view is
/// installed in a window, so the view this makes says so the moment that
/// happens (`viewDidMoveToWindow`), and only then.
struct WindowAccessor: NSViewRepresentable {

    // MARK: - Stored properties

    let onWindow: (NSWindow) -> Void

    // MARK: - Functions

    func makeNSView(context: Context) -> NSView {
        return WindowAccessor.makeWindowReadingView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }

    /// A view that speaks up the INSTANT it is put into a window.
    ///
    /// The moment matters, and it is visible. `viewDidMoveToWindow` is called
    /// as the view joins the window, before the window is ordered front, so
    /// anything that moves the window (putting a remembered window back where
    /// it was left) happens out of sight. A view that looked for its window
    /// later would find it already on screen, and the teacher would see it
    /// appear in the wrong place and snap.
    ///
    /// It is called for a view installed inside a hierarchy that is not yet
    /// in a window too: AppKit tells every view in a hierarchy when the
    /// hierarchy joins a window (`WindowAccessorTests` measures both). Until
    /// #998 a fifty-millisecond GCD poll stood behind it "as a fallback" for
    /// that case; the case never needed one, and the poll broke the house
    /// rule against timed retries.
    static func makeWindowReadingView(onWindow: @escaping (NSWindow) -> Void) -> NSView {
        let view: WindowReadingView = WindowReadingView()
        view.onWindow = onWindow
        return view
    }
}

/// An `NSView` that hands over its window the moment it has one.
private final class WindowReadingView: NSView {

    // MARK: - Stored properties

    var onWindow: ((NSWindow) -> Void)?

    /// Handed over once. Whatever is being done with the window (claiming a
    /// remembered folder, placing it) is rarely safe to do twice, and a view
    /// can be moved between windows.
    private(set) var hasReportedWindow: Bool = false

    // MARK: - Functions

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasReportedWindow, let window else {
            return
        }
        hasReportedWindow = true
        onWindow?(window)
    }
}
