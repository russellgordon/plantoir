import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The "Course Settings has changes you have not saved" line above a section's
/// preview must never claim a height the window cannot give — the failure
/// class `documentation/09-mac-app.md` → "A blank window: when a child claims
/// a size the window cannot give" records, and that this line arrived with
/// (`.fixedSize` on its sentence, #265). Measured the same way as
/// `ProgressViewSizeTests`, for the same reasons.
final class UnsavedSettingsNoticeLayoutTests: XCTestCase {

    // MARK: - Functions

    /// Proposes a narrow width and NO height — how a split view measures a
    /// column — and reports the height claimed. See
    /// `ProgressViewSizeTests.heightClaimedWhenSqueezed` for why not
    /// `fittingSize`.
    @MainActor
    func heightClaimedWhenSqueezed(of view: some View, width: CGFloat = 1) -> CGFloat {
        let controller: NSHostingController = NSHostingController(rootView: AnyView(view))
        return controller.sizeThatFits(in: NSSize(width: width, height: 0)).height
    }

    /// The height rendered at a real column width with room to spare.
    @MainActor
    func heightRendered(of view: some View, width: CGFloat) -> CGFloat {
        let controller: NSHostingController = NSHostingController(rootView: AnyView(view))
        return controller.sizeThatFits(in: NSSize(width: width, height: 850)).height
    }

    /// One of this project's own source files, read as text.
    func readSource(_ relativePath: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Tests

    @MainActor
    func testTheNoticeDoesNotBalloonWhenSqueezed() {
        let claimed: CGFloat = heightClaimedWhenSqueezed(
            of: UnsavedSettingsNoticeView(sentence: SpecialNames.previewUsesSavedSettings)
        )
        XCTAssertLessThanOrEqual(
            claimed,
            ProgressViewSizeTests.squeezedHeightBound,
            "Squeezed, the unsaved-settings notice claimed \(claimed) points — the window's content will grow past the window and the whole interface slides out of view"
        )
    }

    /// Removing the rigidity must not cost the teacher the sentence: at a
    /// narrow real width it renders TALLER than at a wide one, which is what
    /// wrapping in full looks like.
    @MainActor
    func testTheNoticeStillWrapsInFullAtRealWidths() {
        let atNineHundred: CGFloat = heightRendered(
            of: UnsavedSettingsNoticeView(sentence: SpecialNames.previewUsesSavedSettings), width: 900
        )
        let atThreeTwenty: CGFloat = heightRendered(
            of: UnsavedSettingsNoticeView(sentence: SpecialNames.previewUsesSavedSettings), width: 320
        )
        XCTAssertGreaterThan(
            atThreeTwenty,
            atNineHundred,
            "The notice rendered \(atThreeTwenty) points at 320 wide and \(atNineHundred) at 900 — its sentence is not wrapping, so it is being truncated"
        )
    }

    /// The section view shows the notice through this view, and nothing in
    /// the section's detail column is made rigid — the structural half, since
    /// `SectionDetailView` itself cannot be mounted in a unit test.
    func testTheSectionShowsTheNoticeThroughItsOwnViewAndNothingThereIsRigid() throws {
        let section: String = try readSource("QuartzTeachers/Views/Section/SectionDetailView.swift")
        XCTAssertNotNil(
            section.range(of: "UnsavedSettingsNoticeView(sentence:"),
            "SectionDetailView no longer shows the unsaved-settings notice through its measured view"
        )
        XCTAssertNil(
            section.range(of: ".fixedSize("),
            "SectionDetailView makes something rigid in the detail column — the #211 failure class"
        )
        let notice: String = try readSource("QuartzTeachers/Views/Section/UnsavedSettingsNoticeView.swift")
        XCTAssertNil(notice.range(of: ".fixedSize("), "the unsaved-settings notice was made rigid again")
    }
}
