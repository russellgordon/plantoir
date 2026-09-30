import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Copy a Page's checklist, and the result screen after it, fit on the
/// screen whatever they list (#365).
///
/// With "Also copy the pages this page links to" ticked, a well-linked
/// lesson brought about seventy sentences under the rows — one per page that
/// would be skipped — and only the rows were capped, so the sheet grew past
/// the bottom of the screen and Cancel and Copy went with it.
///
/// **Both directions are pinned, on purpose.** A cap alone is a test that
/// passes when the scroll area collapses to nothing: "at most 620 pt" is true
/// of an empty sheet. So every test here asserts a LOWER bound as well —
/// the area really is showing its rows — and the layout is forced before it
/// is read (plan review of #379/#365, finding 18).
final class CopyPageChecklistSizeTests: XCTestCase {

    // MARK: - Functions

    /// Lays the view out in a host at the sheet's width and reports the
    /// height its content claims — after forcing a layout pass, so nothing
    /// is read from a first frame that has not yet learned its size.
    @MainActor
    func measuredHeight(of view: some View) -> CGFloat {
        let hostingView: NSHostingView = NSHostingView(rootView: AnyView(view))
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 2000)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    /// The Copy a Page sheet's own frame around a body: title, the body, the
    /// button row, 20 pt padding, 480 pt wide — `CopyPageSheet.body`'s shape.
    @MainActor
    func inTheSheet(_ content: some View) -> some View {
        return VStack(alignment: .leading, spacing: 16) {
            Text(CopyPageWording.sheetTitle(course: "ICS3U"))
                .font(.headline)
            content
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                }
                Button("Copy") {
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    func linkedPages(count: Int) -> [CopiedPagePlacement] {
        var result: [CopiedPagePlacement] = []
        if count == 0 {
            return result
        }
        for index in 1...count {
            result.append(CopiedPagePlacement(
                sourceFolderName: "Concepts",
                fileName: ExactName("Linked Page \(index).md"),
                destinationFolderName: "Concepts",
                isTheNamedPage: false
            ))
        }
        return result
    }

    /// Skips of the kind Russell's case was made of: a page already in the
    /// destination, whose sentence wraps to two lines at this width.
    func skips(count: Int) -> [CopySkip] {
        var result: [CopySkip] = []
        if count == 0 {
            return result
        }
        for index in 1...count {
            result.append(CopySkip(
                name: "Writing Code Others Can Read, Part \(index)",
                reason: .aPageOfThatNameIsAlreadyHere
            ))
        }
        return result
    }

    @MainActor
    func checklist(rows: Int, sentences: Int) -> some View {
        let linked: [CopiedPagePlacement] = linkedPages(count: rows)
        var pages: [CopiedPagePlacement] = [CopiedPagePlacement(
            sourceFolderName: "Concepts",
            fileName: ExactName("The Unplugged Algorithm.md"),
            destinationFolderName: "Concepts"
        )]
        for page in linked {
            pages.append(page)
        }
        let plan: CoursePageCopyPlan = CoursePageCopyPlan(
            pages: pages, media: [], skipped: skips(count: sentences), linksLeadingNowhere: []
        )
        var kept: Set<String> = []
        for page in linked {
            kept.insert(page.pageName.lowercased())
        }
        return inTheSheet(CopyPageChecklist(
            candidates: linked,
            chosenPage: "The Unplugged Algorithm",
            plan: plan,
            courseName: "ICS4U",
            folderName: "Concepts",
            kept: .constant(kept)
        ))
    }

    @MainActor
    func result(pages: Int, sentences: Int) -> some View {
        var created: [String] = []
        for index in 0..<pages {
            created.append("Page \(index)")
        }
        let outcome: CoursePageCopyOutcome = CoursePageCopyOutcome(
            pagesCreated: created, mediaCreated: 0, mediaReused: 0, renamed: [],
            skipped: skips(count: sentences), linksLeadingNowhere: [], bytesCopied: 0,
            couldNotBeRemoved: []
        )
        return inTheSheet(CopyPageResultView(
            outcome: outcome, courseCode: "ICS4U", folderName: "Concepts",
            backupFileName: "ICS4U backup.zip", folderURL: URL(fileURLWithPath: "/tmp/Concepts")
        ))
    }

    // MARK: - The capped area on its own

    /// The area is as tall as what it holds while that is under the cap, and
    /// exactly the cap beyond it — never zero, never a reserved hole.
    @MainActor
    func testTheAreaIsAsTallAsItsContentUpToTheCap() {
        let few: CGFloat = measuredHeight(of: CappedScrollArea(cap: 380) {
            Color.clear.frame(height: 120)
        })
        XCTAssertEqual(few, 120, accuracy: 1, "120 pt of content should make a 120 pt area, not \(few)")

        let many: CGFloat = measuredHeight(of: CappedScrollArea(cap: 380) {
            Color.clear.frame(height: 3000)
        })
        XCTAssertEqual(many, 380, accuracy: 1, "3,000 pt of content should stop at the 380 pt cap, not \(many)")
    }

    // MARK: - The checklist

    /// Russell's case: eleven rows and about seventy sentences under them.
    @MainActor
    func testTheChecklistStaysOnTheScreenWithElevenRowsAndSeventySentences() {
        let height: CGFloat = measuredHeight(of: checklist(rows: 11, sentences: 70))
        XCTAssertLessThanOrEqual(
            height, CopyPageChecklist.tallestSheet,
            "The checklist sheet is \(height) pt tall; Cancel and Copy go off a 1280 × 800 screen past \(CopyPageChecklist.tallestSheet)"
        )
        // The lower bound: the scroll area is really there at its cap, with
        // the title, heading, "Copies start hidden" and buttons around it.
        XCTAssertGreaterThanOrEqual(
            height, CopyPageChecklist.tallestList + 120,
            "The sheet is only \(height) pt: the scroll area has collapsed and the rows are not showing"
        )
    }

    /// One row and nothing under it: the sheet is small, with no empty hole
    /// where a reserved cap would be.
    @MainActor
    func testAShortChecklistReservesNoEmptySpace() {
        let height: CGFloat = measuredHeight(of: checklist(rows: 0, sentences: 0))
        XCTAssertLessThanOrEqual(height, 260, "A one-row checklist is \(height) pt tall — it is reserving space it does not use")
        XCTAssertGreaterThanOrEqual(
            height, 150,
            "A one-row checklist is only \(height) pt tall: its row is not showing"
        )
    }

    // MARK: - The result screen

    @MainActor
    func testTheResultScreenStaysOnTheScreenWithSeventySkips() {
        let height: CGFloat = measuredHeight(of: result(pages: 11, sentences: 70))
        XCTAssertLessThanOrEqual(
            height, CopyPageChecklist.tallestSheet,
            "The result sheet is \(height) pt tall; Done goes off a 1280 × 800 screen past \(CopyPageChecklist.tallestSheet)"
        )
        XCTAssertGreaterThanOrEqual(
            height, CopyPageResultView.tallestSentenceList + 100,
            "The result sheet is only \(height) pt: its sentences are not showing"
        )
    }

    @MainActor
    func testAResultWithNothingToReportIsShort() {
        let height: CGFloat = measuredHeight(of: result(pages: 1, sentences: 0))
        XCTAssertLessThanOrEqual(height, 250, "A one-page result with no skips is \(height) pt tall")
        XCTAssertGreaterThanOrEqual(height, 100, "A one-page result is only \(height) pt tall")
    }
}
