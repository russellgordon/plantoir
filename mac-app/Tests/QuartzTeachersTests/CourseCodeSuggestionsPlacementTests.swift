import XCTest
@testable import QuartzTeachers

/// The New Course wizard's course-code suggestions open BELOW the sentence
/// under the field (#832): a code already taken said so in an orange line
/// that the open list covered until focus left the field.
final class CourseCodeSuggestionsPlacementTests: XCTestCase {

    // MARK: - Tests

    func testTheListOpensBelowTheSentenceUnderTheField() {
        let field: CGRect = CGRect(x: 120, y: 80, width: 300, height: 22)
        // The field's row with the taken-code sentence under it.
        let rowBottom: CGFloat = 132
        let top: CGFloat = CourseCodeSuggestionsOverlay.top(fieldFrame: field, rowBottom: rowBottom)
        XCTAssertGreaterThanOrEqual(top, rowBottom, "the list's top \(top) is above the sentence's bottom \(rowBottom), so it covers it")
        XCTAssertEqual(top, rowBottom + 4)
    }

    func testWithNoRowYetTheListOpensUnderTheField() {
        let field: CGRect = CGRect(x: 120, y: 80, width: 300, height: 22)
        XCTAssertEqual(CourseCodeSuggestionsOverlay.top(fieldFrame: field, rowBottom: nil), field.maxY + 4)
        // A row reported above the field's bottom never lifts the list
        // onto the field.
        XCTAssertEqual(CourseCodeSuggestionsOverlay.top(fieldFrame: field, rowBottom: 90), field.maxY + 4)
    }

    /// The wizard hands the overlay its row, published around the field
    /// AND the sentence, by a transform that keeps the field's own anchor.
    func testTheWizardPositionsTheListFromTheWholeRow() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views/Wizard/NewCourseWizardView.swift")
        let text: String = try String(contentsOf: url, encoding: .utf8)
        XCTAssertNotNil(text.range(of: "rowBottom: rowBottom(of: anchors, in: proxy)"), "the overlay is not given the row")
        let warning: Range<String.Index> = try XCTUnwrap(text.range(of: ".accessibilityIdentifier(\"courseCodeWarning\")"))
        let transform: Range<String.Index> = try XCTUnwrap(
            text.range(of: ".transformAnchorPreference(key: CourseCodeFieldAnchorKey.self, value: .bounds)")
        )
        XCTAssertLessThan(warning.lowerBound, transform.lowerBound, "the row's anchor must be taken around the taken-code sentence")
    }
}
