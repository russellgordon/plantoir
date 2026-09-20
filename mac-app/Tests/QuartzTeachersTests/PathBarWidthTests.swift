import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The path bar sits beside its label, not at the far end of the window.
///
/// A horizontal `ScrollView` fills whatever width it is given, and since
/// 2026-09-05 this one anchors its content at the TRAILING edge — added for a
/// real defect, an iCloud Drive path cut off before the folder's own name, and
/// recorded as `contracts/shared-rules.json` →
/// `workingFolderPathBar.tooLongForTheSpace`. The two together pushed a SHORT
/// path to the opposite end of the bar from the "Working folder:" label that
/// introduces it, with a window's width of blank between them. Long paths were
/// fixed and short ones broke, because nothing said where a short path goes.
///
/// Measured rather than eyeballed: the defect IS "the view claims all the
/// width offered", so the test proposes a wide space and reads back the width
/// the bar asks for. Checked by putting the fault back — a plain
/// `ScrollView` in place of the `ViewThatFits` — and watching
/// `testAShortPathAsksForOnlyTheRoomItNeeds` fail with the full 1,400.
final class PathBarWidthTests: XCTestCase {

    // MARK: - Stored properties

    /// A path short enough to fit any ordinary window.
    let shortPath: String = "/Users"

    // MARK: - Functions

    /// Proposes a width to the view and reports the width it claims in it.
    ///
    /// The width, where `CloudSyncNoticeLayoutTests` reads the height: the
    /// same `NSHostingController.sizeThatFits(in:)` measurement, asking the
    /// other question. `fittingSize` would not do — it proposes nothing, and
    /// a view that greedily fills a proposal answers a proposal of nothing
    /// with its natural size, which is exactly what a faulty bar and a
    /// correct one have in common.
    @MainActor
    func measuredWidth(of view: some View, proposing width: CGFloat) -> CGFloat {
        let controller: NSHostingController = NSHostingController(rootView: AnyView(view))
        return controller.sizeThatFits(in: NSSize(width: width, height: 40)).width
    }

    /// The fault itself, in the terms it actually occurs in.
    @MainActor
    func testAShortPathAsksForOnlyTheRoomItNeeds() {
        let bar: FinderPathBarView = FinderPathBarView(folderURL: URL(fileURLWithPath: shortPath))
        let measured: CGFloat = measuredWidth(of: bar, proposing: 1400)

        XCTAssertLessThan(
            measured, 700,
            "Offered 1,400 points, a two-crumb path claimed \(measured) — the bar is filling "
            + "the width it is given, so with its content anchored at the trailing edge a short "
            + "path sits at the far end of the window from the “Working folder:” label."
        )
    }

    /// And it is not merely small: it is the size of the row it draws.
    ///
    /// A bar that claimed a fixed small width would pass the test above while
    /// truncating every path, so the claim is checked against the row's own
    /// natural width rather than against a number chosen here.
    @MainActor
    func testTheWidthItAsksForIsTheWidthOfItsCrumbs() {
        let bar: FinderPathBarView = FinderPathBarView(folderURL: URL(fileURLWithPath: shortPath))
        let measured: CGFloat = measuredWidth(of: bar, proposing: 1400)
        let rowWidth: CGFloat = measuredWidth(of: bar.pathRow, proposing: 1400)

        XCTAssertEqual(
            measured, rowWidth, accuracy: 1,
            "The bar claimed \(measured) points for a row that draws in \(rowWidth)."
        )
    }

    /// Too long for the space, and the bar does what FINDER does: the
    /// ancestors lose their NAMES, not the path its end, and nothing is
    /// replaced by an ellipsis.
    ///
    /// The check is indirect on purpose, and stronger for it: a row that
    /// draws no ancestor names cannot change width when those names change
    /// length. Two paths of the same depth, one with very long ancestor
    /// names and one with short, must collapse to the SAME width while their
    /// full rows differ — which no amount of truncating or ellipsising would
    /// satisfy, since a truncated name still occupies the room it was given.
    @MainActor
    func testCollapsingDropsTheAncestorsNamesRatherThanShorteningThem() {
        let shortNames: FinderPathBarView = FinderPathBarView(
            folderURL: URL(fileURLWithPath: "/a/b/c/Folder")
        )
        let longNames: FinderPathBarView = FinderPathBarView(
            folderURL: URL(fileURLWithPath: "/an extremely long ancestor name/another very long one/a third long one/Folder")
        )

        let shortFull: CGFloat = measuredWidth(of: shortNames.pathRow, proposing: 4000)
        let longFull: CGFloat = measuredWidth(of: longNames.pathRow, proposing: 4000)
        XCTAssertGreaterThan(
            longFull, shortFull,
            "The two full rows should differ — if they do not, this test proves nothing below."
        )

        let shortCollapsed: CGFloat = measuredWidth(of: shortNames.collapsedRow, proposing: 4000)
        let longCollapsed: CGFloat = measuredWidth(of: longNames.collapsedRow, proposing: 4000)
        XCTAssertEqual(
            shortCollapsed, longCollapsed, accuracy: 1,
            "Collapsed, a path with long ancestor names claimed \(longCollapsed) against "
            + "\(shortCollapsed) for short ones — so the ancestors' names are still being "
            + "drawn in some shortened form rather than dropped, which is the ellipsis "
            + "behaviour this deliberately does not have."
        )
    }

    /// And the folder's own name survives the collapse: it is the one crumb
    /// that differs between a teacher's folders.
    @MainActor
    func testTheFolderItselfKeepsItsNameWhenTheAncestorsLoseTheirs() {
        let bar: FinderPathBarView = FinderPathBarView(
            folderURL: URL(fileURLWithPath: "/a/b/c/A Distinctly Long Folder Name")
        )
        let shorterName: FinderPathBarView = FinderPathBarView(
            folderURL: URL(fileURLWithPath: "/a/b/c/X")
        )

        XCTAssertGreaterThan(
            measuredWidth(of: bar.collapsedRow, proposing: 4000),
            measuredWidth(of: shorterName.collapsedRow, proposing: 4000),
            "The collapsed row is the same width whatever the folder is called, so the "
            + "folder's own name is not being drawn either."
        )
    }

    /// The middle form is actually REACHED: offered a width between the two,
    /// the bar collapses rather than jumping straight to scrolling.
    @MainActor
    func testAPathThatFitsOnlyCollapsedIsDrawnCollapsed() {
        let bar: FinderPathBarView = FinderPathBarView(
            folderURL: URL(fileURLWithPath: "/Users/teacher/Library/Mobile Documents/com~apple~CloudDocs/Teaching/Course Notes")
        )
        let fullWidth: CGFloat = measuredWidth(of: bar.pathRow, proposing: 4000)
        let collapsedWidth: CGFloat = measuredWidth(of: bar.collapsedRow, proposing: 4000)
        XCTAssertGreaterThan(
            fullWidth, collapsedWidth + 10,
            "This path is not long enough for the two forms to differ meaningfully."
        )

        // Half way between the two: too narrow for every name, wide enough
        // for icons, chevrons and the folder's own name.
        let between: CGFloat = (fullWidth + collapsedWidth) / 2
        let measured: CGFloat = measuredWidth(of: bar, proposing: between)

        XCTAssertEqual(
            measured, collapsedWidth, accuracy: 1,
            "Offered \(between) points — between the full row's \(fullWidth) and the "
            + "collapsed row's \(collapsedWidth) — the bar claimed \(measured). It should "
            + "draw the collapsed row at its own width, not fall through to the scrolling "
            + "form and take everything offered."
        )
    }

    /// A path too long even to COLLAPSE still takes the whole space — that
    /// is the scrolling form doing its job, and the rule the trailing anchor
    /// exists for. Without this, "ask for less" could be satisfied by a bar
    /// that never scrolls and clips instead.
    ///
    /// The precondition is not decoration. This test was written when the
    /// form that had to overflow was the FULL row, hundreds of points over
    /// 320; the collapsed row added for issue #148 is much narrower, so the
    /// margin is now small enough that a change in icon or chevron metrics
    /// could let it fit — at which point `ViewThatFits` would rightly draw
    /// the collapsed row, this would fail, and the failure would read as a
    /// product bug rather than as a fixture that had gone stale.
    @MainActor
    func testAPathTooLongEvenToCollapseStillFillsTheSpaceItIsGiven() {
        let longPath: String = "/Users/teacher/Library/Mobile Documents/com~apple~CloudDocs/Teaching/Course Notes/Semester Two"
        let bar: FinderPathBarView = FinderPathBarView(folderURL: URL(fileURLWithPath: longPath))

        XCTAssertGreaterThan(
            measuredWidth(of: bar.collapsedRow, proposing: 4000), 320,
            "This fixture now COLLAPSES into 320 points, so it no longer reaches the "
            + "scrolling form and the assertion below would be testing the wrong form. "
            + "Deepen the path rather than relaxing the check."
        )

        let measured: CGFloat = measuredWidth(of: bar, proposing: 320)
        XCTAssertEqual(
            measured, 320, accuracy: 1,
            "Squeezed to 320 points, a path too long even to collapse claimed \(measured) — "
            + "it should take the space it is given and scroll inside it, showing its END."
        )
    }
}
