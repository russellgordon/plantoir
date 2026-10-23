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
/// Only grown, while a sheet is still being worked in: a teacher who made the
/// sheet bigger keeps the size they made, and a stage that needs less leaves
/// the sheet where it is. The checkbox under the plan table never raises the
/// minimum (the table is counted with it unticked, #622), so ticking it moves
/// nothing.
///
/// The one exception is the sheet's ANSWER (#654, `fitsItsContent`): the
/// sentence a tool said when it finished — "Published 5 pages.", a
/// cancellation, a failure — is shown in a sheet fitted to it, height and
/// all, keeping only the width the teacher made. Left to the rule above, the
/// answer kept the plan's height — MEASURED on macOS 26.6
/// (`PageTablesSheetTests.testTheAnswerAfterAPlanIsFittedToItsSentence`): a
/// Publish plan of twenty-one pages stayed 454 pt tall, and a Hide plan 292,
/// to show an answer that needs 124; the worst plan the budget allows
/// (`CopyPageChecklist.tallestSheet`, 609 pt measured) would leave some 485
/// pt of empty sheet over OK.
/// The answer is the last thing the sheet shows, so fitting it takes away
/// no size the teacher still needs. AppKit keeps the sheet centred on its
/// window through the change (measured), so nothing else has to move it.
/// Rejected: an `.id` per stage, or a smaller frame on the answer alone —
/// the window, not the view, keeps the height (#621's measurement above).
///
/// It watches the window rather than a stage because Start of Year's stage is
/// not `Equatable`, and because a minimum can rise for reasons no stage names.
/// The growing is done on the next turn of the main actor, never inside the
/// notification itself, which arrives in the middle of SwiftUI's own layout.
struct SheetGrowsToItsMinimum: NSViewRepresentable {

    // MARK: - Stored properties

    /// True while the sheet shows its answer (#654): the sheet is then fitted
    /// to its content's height, smaller as well as larger, rather than only
    /// grown.
    var fitsItsContent: Bool = false

    // MARK: - Functions

    func makeNSView(context: Context) -> SheetMinimumWatcher {
        return SheetMinimumWatcher()
    }

    func updateNSView(_ nsView: SheetMinimumWatcher, context: Context) {
        nsView.changeFitting(to: fitsItsContent)
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

    /// Whether the window is fitted to its minimum height, both ways, rather
    /// than only grown to it (`SheetGrowsToItsMinimum.fitsItsContent`).
    var fitsItsContent: Bool = false

    // MARK: - Functions

    /// Starts or stops fitting the window to its content (#654). Starting
    /// fits it on the next turn of the main actor — the new stage's minimum
    /// may already be in place — and again whenever the minimum changes
    /// after that, since it may not be yet.
    func changeFitting(to fits: Bool) {
        if fits == fitsItsContent {
            return
        }
        fitsItsContent = fits
        if fits {
            Task { @MainActor in
                self.sizeTheWindowToItsMinimum()
            }
        }
    }

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
                self?.sizeTheWindowToItsMinimum()
            }
        }
        observations = [watch]
    }

    /// Grows this view's window to its minimum content size, if it is smaller
    /// in either direction — or, while `fitsItsContent`, gives it exactly its
    /// minimum height, keeping the width it has.
    func sizeTheWindowToItsMinimum() {
        guard let window else {
            return
        }
        let current: NSSize = window.contentLayoutRect.size
        var size: NSSize = SheetMinimumWatcher.sizeAtLeast(window.contentMinSize, from: current)
        if fitsItsContent {
            size = SheetMinimumWatcher.sizeFitted(to: window.contentMinSize, from: current)
        }
        if size != current {
            window.setContentSize(size)
        }
    }

    /// `current`'s width, grown to `least` where it is narrower, and
    /// `least`'s height exactly (#654).
    static func sizeFitted(to least: NSSize, from current: NSSize) -> NSSize {
        var fitted: NSSize = sizeAtLeast(least, from: current)
        fitted.height = least.height
        return fitted
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
