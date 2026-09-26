import XCTest
@testable import QuartzTeachers

/// The trail's lines about updating (#204), composed from fixed facts.
final class UpdateTrailTests: XCTestCase {

    // MARK: - Tests

    func testVersionsAreTheVersionAndTheBuild() {
        XCTAssertEqual(UpdateTrail.versionText(version: "1.3.2", build: "3120"), "1.3.2 (3120)")
    }

    func testFoundSaysWhoAskedAndWhetherItIsImportant() {
        let daily: String = UpdateTrail.foundLine(found: "1.3.2 (3120)", running: "1.3.1 (3100)", teacherAsked: false, important: false)
        let asked: String = UpdateTrail.foundLine(found: "1.3.2 (3120)", running: "1.3.1 (3100)", teacherAsked: true, important: true)
        XCTAssertTrue(daily.contains("1.3.2 (3120)") && daily.contains("1.3.1 (3100)"))
        XCTAssertNotEqual(daily, asked)
        XCTAssertFalse(daily.contains("important"))
        XCTAssertTrue(asked.contains("important"))
    }

    /// Every way an install happens says whether Plantoir opens again, and
    /// the one that cannot be prevented names the work still going on.
    func testInstallingSaysWhenAndWhetherItOpensAgain() {
        let now: String = UpdateTrail.installingLine(from: "1.3.1 (3100)", to: "1.3.2 (3120)", moment: .straightAway)
        let after: String = UpdateTrail.installingLine(
            from: "1.3.1 (3100)", to: "1.3.2 (3120)", moment: .afterHeldWork("publishing Section 2 of ICS3U")
        )
        let quitting: String = UpdateTrail.installingLine(
            from: "1.3.1 (3100)", to: "1.3.2 (3120)", moment: .asPlantoirQuits(workStillGoing: "publishing on its schedule")
        )
        XCTAssertTrue(now.contains("open again"))
        XCTAssertTrue(after.contains("publishing Section 2 of ICS3U") && after.contains("open again"))
        XCTAssertTrue(quitting.contains("publishing on its schedule") && quitting.contains("will not open again"))
    }

    func testStopsHaveAPlainCategoryAndTheirNumber() {
        XCTAssertEqual(UpdateTrail.stoppedCategory(code: 1003), UpdateTrail.stoppedCategory(code: 1005))
        XCTAssertEqual(UpdateTrail.stoppedCategory(code: 4007), UpdateTrail.stoppedCategory(code: 4001))
        XCTAssertEqual(UpdateTrail.stoppedCategory(code: 4008), UpdateTrail.stoppedCategory(code: 4012))
        XCTAssertEqual(UpdateTrail.stoppedCategory(code: 3001), UpdateTrail.stoppedCategory(code: 3002))
        XCTAssertNotEqual(UpdateTrail.stoppedCategory(code: 2001), UpdateTrail.stoppedCategory(code: 3001))
        XCTAssertNotEqual(UpdateTrail.stoppedCategory(code: 4007), UpdateTrail.stoppedCategory(code: 9999))
        XCTAssertTrue(UpdateTrail.stoppedLine(version: "1.3.2 (3120)", code: 4007).hasSuffix("[4007]"))
        XCTAssertTrue(UpdateTrail.needsAnAdministrator(code: 4007))
        XCTAssertFalse(UpdateTrail.needsAnAdministrator(code: 4001))
    }

    /// `app updated`: nothing on a first launch or the same version; "by its
    /// own updater" only when the old version left the note for THIS version.
    /// A scratch defaults domain — never the app's own.
    func testAppUpdatedTellsTheUpdaterFromAHand() throws {
        let suite: String = "UpdateTrailTests-\(UUID().uuidString)"
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        XCTAssertNil(UpdateTrail.appUpdatedLine(current: "1.3.1 (3100)", defaults: defaults), "a first launch")
        XCTAssertNil(UpdateTrail.appUpdatedLine(current: "1.3.1 (3100)", defaults: defaults), "the same version")

        defaults.set("1.3.2 (3120)", forKey: UpdateTrail.installingVersionKey)
        let byUpdater: String = try XCTUnwrap(UpdateTrail.appUpdatedLine(current: "1.3.2 (3120)", defaults: defaults))
        XCTAssertTrue(byUpdater.contains("1.3.1 (3100)") && byUpdater.contains("its own updater"))
        XCTAssertNil(defaults.string(forKey: UpdateTrail.installingVersionKey), "the note is read once")

        let byHand: String = try XCTUnwrap(UpdateTrail.appUpdatedLine(current: "1.3.3 (3200)", defaults: defaults))
        XCTAssertTrue(byHand.contains("by hand"))

        defaults.set("1.3.9 (3900)", forKey: UpdateTrail.installingVersionKey)
        let stale: String = try XCTUnwrap(UpdateTrail.appUpdatedLine(current: "1.3.4 (3300)", defaults: defaults))
        XCTAssertTrue(stale.contains("by hand"), "A note for another version is not this one's")
    }

    /// Nothing from the release notes, and no web address but none at all.
    func testNoLineCarriesAnAddress() {
        let lines: [String] = [
            UpdateTrail.foundLine(found: "a", running: "b", teacherAsked: true, important: true),
            UpdateTrail.nothingNewLine(running: "b"),
            UpdateTrail.answeredLine(answer: .notNow, version: "a"),
            UpdateTrail.heldLine(work: "w", version: "a"),
            UpdateTrail.setAsideLine(version: "a", work: "w"),
            UpdateTrail.stoppedLine(version: "a", code: 2001)
        ]
        for line in lines {
            XCTAssertFalse(line.contains("http"), line)
        }
    }
}
