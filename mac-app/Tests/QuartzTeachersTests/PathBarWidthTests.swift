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

    /// A path too long for the space still takes the whole space — that is
    /// the scrolling form doing its job, and the rule the trailing anchor
    /// exists for. Without this, "ask for less" could be satisfied by a bar
    /// that never scrolls and clips instead.
    @MainActor
    func testALongPathStillFillsTheSpaceItIsGiven() {
        let longPath: String = "/Users/teacher/Library/Mobile Documents/com~apple~CloudDocs/Teaching/Course Notes/Semester Two"
        let bar: FinderPathBarView = FinderPathBarView(folderURL: URL(fileURLWithPath: longPath))
        let measured: CGFloat = measuredWidth(of: bar, proposing: 320)

        XCTAssertEqual(
            measured, 320, accuracy: 1,
            "Squeezed to 320 points, a long path claimed \(measured) — it should take the "
            + "space it is given and scroll inside it, showing its END."
        )
    }
}
