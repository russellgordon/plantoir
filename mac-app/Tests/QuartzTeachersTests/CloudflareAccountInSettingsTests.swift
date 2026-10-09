import XCTest
@testable import QuartzTeachers

/// The Cloudflare Account ID is edited in Plantoir ▸ Settings ▸ Deploying,
/// and only there (#457 item 4, the HIG sweep; Russell, 2026-10-08). A
/// course's Deploying section and the new-course wizard SHOW it, read-only,
/// with Open Settings… beside it.
@MainActor
final class CloudflareAccountInSettingsTests: XCTestCase {

    // MARK: - Tests

    /// The one field is in the Settings pane; the view a course and the
    /// wizard share has none. Until the sweep the shared view held the field,
    /// so editing it in one course changed it for every course.
    func testTheFieldIsInSettingsAndNowhereElse() throws {
        let views: URL = TextFieldStyleScanTests.viewsURL()
        let shared: String = TextFieldStyleScanTests.codeWithoutComments(try String(
            contentsOf: views.appendingPathComponent("CourseSettings/PublishingChoiceView.swift"), encoding: .utf8
        ))
        XCTAssertFalse(shared.contains("TextField(\"Cloudflare Account ID\""), "the course's view has no field for the ID")
        XCTAssertFalse(shared.contains("\"cloudflareAccountField\""), "the field's identifier belongs to the Settings pane")
        XCTAssertTrue(shared.contains("Button(\"Open Settings…\")"), "the course and the wizard offer the way to Settings")
        let pane: String = try String(
            contentsOf: views.appendingPathComponent("Settings/DeployingSettingsView.swift"), encoding: .utf8
        )
        XCTAssertTrue(pane.contains("text: $settings.cloudflareAccountID"))
        XCTAssertTrue(pane.contains(".accessibilityIdentifier(\"cloudflareAccountField\")"))
        let settings: String = try String(
            contentsOf: views.appendingPathComponent("Settings/PlantoirSettingsView.swift"), encoding: .utf8
        )
        XCTAssertTrue(settings.contains("DeployingSettingsView()"), "Settings has the Deploying pane")
    }

    /// The trail says what happened to the ID, never the ID.
    func testTheTrailLineNeverCarriesTheID() {
        let valid: String = "0123456789abcdef0123456789abcdef"
        XCTAssertNil(DeployingSettingsView.trailLine(before: valid, after: valid), "a visit is not a change")
        XCTAssertNil(DeployingSettingsView.trailLine(before: valid, after: " " + valid + " "), "spaces are not a change")
        let set: String? = DeployingSettingsView.trailLine(before: "", after: valid)
        XCTAssertEqual(set, "Settings ▸ Deploying — the Cloudflare Account ID was changed")
        XCTAssertEqual(DeployingSettingsView.trailLine(before: valid, after: ""), "Settings ▸ Deploying — the Cloudflare Account ID was cleared")
        XCTAssertEqual(
            DeployingSettingsView.trailLine(before: "", after: "0123"),
            "Settings ▸ Deploying — the Cloudflare Account ID was changed, and is not a valid ID yet"
        )
        for line in [set ?? "", DeployingSettingsView.trailLine(before: "", after: "0123") ?? ""] {
            XCTAssertFalse(line.contains("0123"), "the ID never reaches the trail")
        }
    }

    /// An empty ID is not wrong on the Settings pane (a teacher who never
    /// deploys to Cloudflare has no reason to give one); a typed one that is
    /// not an ID is, in the contract's own words.
    func testThePaneObjectsOnlyToWhatWasTyped() {
        XCTAssertNil(DeployingSettingsView.problem(with: ""))
        XCTAssertNil(DeployingSettingsView.problem(with: "0123456789abcdef0123456789abcdef"))
        XCTAssertEqual(
            DeployingSettingsView.problem(with: "0123"),
            CourseConfiguration.cloudflareAccountProblem(forID: "0123")
        )
    }
}
