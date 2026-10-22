import XCTest

/// Finding the Start of Year sheet's table of pages going into draft (#589)
/// off the real tree — shared by the opt-in identifier test and the
/// marketing capture. (A sort by a coordinate click on its header lived here
/// too, and was dropped: in the capture it took on one pass of two.)
extension XCTestCase {

    // MARK: - Functions

    /// The plan's table, by its identifier.
    func startOfYearPlanTable(in application: XCUIApplication) -> XCUIElement {
        return application.descendants(matching: .any).matching(identifier: "startOfYearPlanTable").firstMatch
    }
}
