import SwiftUI

/// A region that is exactly as tall as what it holds, up to a cap, and
/// scrolls beyond it (#365).
///
/// **Why it exists.** Copy a Page's checklist capped only its ROWS; the
/// sentences under them — one per page that will be skipped, the links that
/// will lead nowhere, the pictures lines — sat outside the scroll area, so a
/// well-linked lesson (about seventy such sentences for The Unplugged
/// Algorithm) grew the sheet past the bottom of the screen and took Cancel
/// and Copy with it. Everything that grows with the number of pages now goes
/// INSIDE one of these, and the sheet around it has a height it cannot pass.
///
/// **Why a `Layout` and not a measured `@State` height.** The obvious shape
/// — measure the content with `.onGeometryChange` into a `@State` and frame
/// the scroll view at `min(measured, cap)` — starts at zero and only learns
/// the real height after a layout pass. A size test that reads the sheet
/// once then measures an empty area: "at most 620 pt" passes with every row
/// invisible, which is a test that cannot fail in the direction that
/// matters (plan review of #379/#365, finding 18). A `Layout` asks the
/// scroll view for its natural height at the width it is given in the SAME
/// pass — a scroll view's ideal height along its axis is its content's — so
/// there is no first frame at zero, and no state to fall out of step.
///
/// **Never `maxHeight` on a bare `ScrollView`.** A scroll view offered "up to
/// 380" takes all 380, so a one-row checklist reserved the cap and drew an
/// empty hole under its single row. That was the checklist's first attempt,
/// and its comment recorded it.
struct CappedScrollArea<Content: View>: View {

    // MARK: - Stored properties

    /// The tallest the area may be. Beyond this it scrolls.
    let cap: CGFloat

    /// Whether the area also takes any height it is OFFERED past its own
    /// (#621): it still opens at its content's height up to the cap, and
    /// that is still the least it is given, but in a sheet the teacher makes
    /// taller it grows with the sheet instead of leaving a band under it.
    /// Off by default, so every area made before keeps its fixed height.
    let growsWithItsSheet: Bool

    let content: Content

    // MARK: - Initializer

    init(cap: CGFloat, growsWithItsSheet: Bool = false, @ViewBuilder content: () -> Content) {
        self.cap = cap
        self.growsWithItsSheet = growsWithItsSheet
        self.content = content()
    }

    // MARK: - Body

    var body: some View {
        CappedHeightLayout(cap: cap, growsWithItsSheet: growsWithItsSheet) {
            ScrollView(.vertical) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Gives its one child the child's natural height at the offered width, but
/// never more than `cap`.
struct CappedHeightLayout: Layout {

    // MARK: - Stored properties

    let cap: CGFloat

    /// `CappedScrollArea.growsWithItsSheet`.
    var growsWithItsSheet: Bool = false

    // MARK: - Functions

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else {
            return .zero
        }
        // Ask for the height the child wants at this width — `nil` means
        // "as tall as you like" — and then refuse anything over the cap.
        let natural: CGSize = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let width: CGFloat = proposal.width ?? natural.width
        var height: CGFloat = min(natural.height, cap)
        // Offered more than that — the sheet made taller, or the largest a
        // sheet asks about (an infinite offer) — and allowed to grow: take
        // it. Offered less, or asked for its own size (nil), it is the
        // capped height, so that is both where it opens and its least.
        if growsWithItsSheet, let offered = proposal.height, offered > height {
            height = offered
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for child in subviews {
            child.place(
                at: bounds.origin,
                proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
            )
        }
    }
}
