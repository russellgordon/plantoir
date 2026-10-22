import AppKit
import SwiftUI

/// Makes a resizable sheet grow when what it shows needs more height than it
/// has — and never shrink (#621, the plan review's B1).
///
/// A sheet with `.presentationSizing(.fitted)` opens at its content's size
/// and can be resized, but it never fits itself AGAIN after it has opened:
/// MEASURED on macOS 26.6, a Publish Pages... sheet opened on a two-row
/// picker at 182 pt, and on the move to the plan its minimum rose to 422 pt
/// while the window stayed at 182, so the plan was centred in it and clipped
/// and the buttons sat 100 pt below the bottom edge — still so three seconds
/// later. `.fitted.sticky()` and an `.id` per stage behave the same way; the
/// default sizing does fit again, but the sheet is then not resizable.
///
/// So this watches the sheet's window: whenever its smallest allowed content
/// size rises past the size it has, the window is grown to that minimum.
/// Only grown: a teacher who made the sheet bigger keeps the size they made,
/// and a stage that needs less leaves the sheet where it is. The disclosure
/// under the plan table never raises the minimum (the table is counted with
/// it closed, #622), so opening it moves nothing.
///
/// It watches the window rather than a stage because Start of Year's stage is
/// not `Equatable`, and because a minimum can rise for reasons no stage names.
/// The growing is done on the next turn of the main actor, never inside the
/// notification itself, which arrives in the middle of SwiftUI's own layout.
struct SheetGrowsToItsMinimum: NSViewRepresentable {

    // MARK: - Functions

    func makeNSView(context: Context) -> SheetMinimumWatcher {
        return SheetMinimumWatcher()
    }

    func updateNSView(_ nsView: SheetMinimumWatcher, context: Context) {
    }
}

/// The view behind `SheetGrowsToItsMinimum`: it joins the sheet's window and
/// watches that window's `contentMinSize`.
final class SheetMinimumWatcher: NSView {

    // MARK: - Stored properties

    /// The watch on the window this view is in; replaced when it moves to
    /// another, and dropped with the view. One, held in a list so that
    /// moving to no window empties it.
    var observations: [NSKeyValueObservation] = []

    // MARK: - Functions

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observations = []
        guard let window else {
            return
        }
        // MEASURED: SwiftUI's change of the sheet's minimum is announced
        // for `contentMinSize`; `minSize` sends nothing.
        let watch: NSKeyValueObservation = window.observe(\.contentMinSize, options: [.new]) { [weak self] (_: NSWindow, _: NSKeyValueObservedChange<NSSize>) in
            Task { @MainActor in
                self?.growTheWindowToItsMinimum()
            }
        }
        observations = [watch]
    }

    /// Grows this view's window to its minimum content size, if it is smaller
    /// in either direction. Never shrinks it.
    func growTheWindowToItsMinimum() {
        guard let window else {
            return
        }
        let size: NSSize = SheetMinimumWatcher.sizeAtLeast(
            window.contentMinSize, from: window.contentLayoutRect.size
        )
        if size != window.contentLayoutRect.size {
            window.setContentSize(size)
        }
    }

    /// `current`, grown in each direction to `least` where it is smaller.
    static func sizeAtLeast(_ least: NSSize, from current: NSSize) -> NSSize {
        var grown: NSSize = current
        if grown.width < least.width {
            grown.width = least.width
        }
        if grown.height < least.height {
            grown.height = least.height
        }
        return grown
    }
}
