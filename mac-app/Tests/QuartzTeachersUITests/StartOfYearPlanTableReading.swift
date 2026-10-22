import XCTest

/// Reading and sorting the Start of Year sheet's table of pages going into
/// draft (#589) off the real tree — shared by the opt-in identifier test and
/// the marketing capture, so the capture's sort is the one the opt-in test
/// has seen work.
extension XCTestCase {

    // MARK: - Functions

    /// A sentence of `contracts/shared-rules.json` → `startOfYear.wording`,
    /// read rather than retyped: a copy of a contract sentence in a test is
    /// the copy that keeps passing after the product's words change.
    func startOfYearWording(_ key: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let startOfYear: [String: Any] = try XCTUnwrap(all["startOfYear"] as? [String: Any])
        let wording: [String: Any] = try XCTUnwrap(startOfYear["wording"] as? [String: Any])
        return try XCTUnwrap(wording[key] as? String, "startOfYear.wording has no \(key)")
    }

    /// The plan's table, by its identifier.
    func startOfYearPlanTable(in application: XCUIApplication) -> XCUIElement {
        return application.descendants(matching: .any).matching(identifier: "startOfYearPlanTable").firstMatch
    }

    /// The words in the first row's last cell — the Why column — as drawn
    /// now, in whatever order the table is sorted. A SwiftUI `Table` may
    /// reach the tree as a table or as an outline, so both are asked.
    func firstRowReason(in table: XCUIElement) -> String {
        var row: XCUIElement = table.tableRows.firstMatch
        if !row.exists {
            row = table.outlineRows.firstMatch
        }
        let texts: XCUIElementQuery = row.staticTexts
        var words: [String] = []
        var index: Int = 0
        while index < texts.count {
            let text: XCUIElement = texts.element(boundBy: index)
            if let value = text.value as? String, !value.isEmpty {
                words.append(value)
            } else {
                words.append(text.label)
            }
            index += 1
        }
        return words.last ?? ""
    }

    /// Clicks the Why column's header twice: the first click sorts by it
    /// ascending, the second descending — which puts the pages' reasons
    /// ("only … links to it", "nothing links to it", "first used in …")
    /// above the classes' "comes after …". The header is asked for by its
    /// title; where the tree does not offer it as a button, the click goes
    /// to the header row over the Why column, which is the right-hand half
    /// of the table.
    func sortStartOfYearPlanByReasonDescending(_ table: XCUIElement, whyTitle: String) {
        for _ in 0..<2 {
            let header: XCUIElement = table.buttons[whyTitle]
            if header.exists && header.isHittable {
                header.click()
            } else {
                table.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.0))
                    .withOffset(CGVector(dx: 0, dy: 14)).click()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }
}
