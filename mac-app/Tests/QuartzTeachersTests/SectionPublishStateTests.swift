import XCTest
@testable import QuartzTeachers

/// Runs the `publishedFreshness` half of `contracts/app-rules.json` — the
/// " — Edited" marker a section window shows when its pages have changed
/// since it was last published.
///
/// The cases are data so the Windows suite runs the identical list; the
/// setup is Swift because only this side can make a course folder on disk.
/// Every `when` in the contract is answered by driving the REAL check
/// against a real folder rather than by asserting a helper in isolation —
/// the failure this feature must never have (telling a teacher a page went
/// out when it did not) lives in the walk, not in the arithmetic.
final class SectionPublishStateTests: XCTestCase {

    // MARK: - Stored properties

    private var courseDirectory: URL!

    // MARK: - Set-up

    override func setUpWithError() throws {
        courseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("publish-state-\(UUID().uuidString)")
            .appendingPathComponent("ICS3U")
        try write("{\"course_code\": \"ICS3U\"}", to: "course_config.json")
        try write("# Day one", to: "section1/Classes/Unit 1, Day 1.md")
        try write("# Day one, section two", to: "section2/Classes/Unit 1, Day 1.md")
        try write("# A shared lesson", to: "Unit 1/Lesson.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: courseDirectory.deletingLastPathComponent())
    }

    // MARK: - The marker itself

    func testTitleCarriesTheMarkerTheContractNames() throws {
        let marker: [String: Any] = try XCTUnwrap(
            try SectionPublishStateTests.rules()["marker"] as? [String: Any]
        )
        for testCase in try XCTUnwrap(marker["cases"] as? [[String: Any]]) {
            let base: String = try XCTUnwrap(testCase["base"] as? String)
            let edited: Bool = try XCTUnwrap(testCase["hasUnpublishedEdits"] as? Bool)
            XCTAssertEqual(
                SectionPublishState.windowTitle(base: base, hasUnpublishedEdits: edited),
                try XCTUnwrap(testCase["expectTitle"] as? String),
                "The title bar must say exactly what the contract says it says"
            )
        }
    }

    // MARK: - Which files count

    func testTheRightFilesCountTowardTheFingerprint() throws {
        let section: [String: Any] = try XCTUnwrap(
            try SectionPublishStateTests.rules()["filesCounted"] as? [String: Any]
        )
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let path: String = try XCTUnwrap(testCase["path"] as? String)
            XCTAssertEqual(
                SectionPublishState.countsTowardFingerprint(relativePath: path, sectionNumber: 1),
                try XCTUnwrap(testCase["counts"] as? Bool),
                "\(path): \(testCase["why"] as? String ?? "")"
            )
        }
    }

    /// `section3` is a section folder; `sections` and `section3b` are two
    /// folders a teacher is entirely free to make, and neither belongs to
    /// anybody. Getting this wrong would drop a real folder of pages out of
    /// every section's fingerprint.
    func testOnlyRealSectionFoldersAreTreatedAsOne() {
        XCTAssertTrue(SectionPublishState.isSectionFolderName("section3"))
        XCTAssertTrue(SectionPublishState.isSectionFolderName("section12"))
        XCTAssertFalse(SectionPublishState.isSectionFolderName("sections"))
        XCTAssertFalse(SectionPublishState.isSectionFolderName("section"))
        XCTAssertFalse(SectionPublishState.isSectionFolderName("section3b"))
        XCTAssertFalse(SectionPublishState.isSectionFolderName("Section 3"))
    }

    // MARK: - When the marker is shown

    func testEveryCaseTheContractNames() throws {
        var expectations: [String: Bool] = [:]
        for rule in try XCTUnwrap(
            try SectionPublishStateTests.rules()["whenShown"] as? [[String: Any]]
        ) {
            expectations[try XCTUnwrap(rule["when"] as? String)] =
                try XCTUnwrap(rule["expectEdited"] as? Bool)
        }

        // Never published.
        XCTAssertEqual(
            isEdited(), expectations["the section has never been published"],
            "A course nobody has published yet has not been edited since anything"
        )

        // Nothing changed since the last publish.
        publishNow()
        XCTAssertEqual(
            isEdited(), expectations["nothing has changed since the last publish"]
        )

        // A page this section alone uses.
        try write("# Day one, rewritten this morning", to: "section1/Classes/Unit 1, Day 1.md")
        XCTAssertEqual(
            isEdited(), expectations["a page this section alone uses has changed"]
        )

        // A page shared with the other sections.
        publishNow()
        try write("# A shared lesson, rewritten", to: "Unit 1/Lesson.md")
        XCTAssertEqual(
            isEdited(),
            expectations["a page this section SHARES with other sections has changed"]
        )

        // A page removed.
        publishNow()
        try FileManager.default.removeItem(
            at: courseDirectory.appendingPathComponent("Unit 1/Lesson.md")
        )
        XCTAssertEqual(
            isEdited(), expectations["a page has been DELETED since the last publish"],
            "A fingerprint of the file inventory is what makes a deletion visible"
        )

        // The configuration.
        publishNow()
        try write("{\"course_code\": \"ICS3U\", \"font\": \"Inter\"}", to: "course_config.json")
        XCTAssertEqual(
            isEdited(), expectations["course_config.json has changed"]
        )

        // An unreadable stamp.
        publishNow()
        try write("this is not JSON", to: ".publish_state/section1.json")
        XCTAssertEqual(
            isEdited(), expectations["the stamp file cannot be read"],
            "An unreadable stamp must never be able to claim a section is up to date"
        )
    }

    /// The other section's pages are not this section's site. Editing
    /// section 2 must leave section 1's window alone — the case that would
    /// make the marker meaningless in the courses that have most sections.
    func testAnotherSectionsPagesDoNotMarkThisOne() throws {
        publishNow()
        try write("# Rewritten for the other class", to: "section2/Classes/Unit 1, Day 1.md")
        XCTAssertFalse(isEdited())
    }

    /// The stamp lives in a hidden folder for exactly this reason: writing
    /// it must not itself count as an edit, or every publish would end by
    /// declaring the section edited.
    func testRecordingAPublishDoesNotItselfCountAsAnEdit() {
        publishNow()
        XCTAssertFalse(isEdited())
        publishNow()
        XCTAssertFalse(isEdited())
    }

    /// The stamp says where the pages went, because a course since pointed
    /// somewhere else has never published THERE.
    func testTheStampRecordsWhereItWent() {
        publishNow(destinations: ["netlify", "cloudflare_pages"])
        let stamp = SectionPublishState.stamp(courseDirectory: courseDirectory, sectionNumber: 1)
        XCTAssertEqual(stamp?.destinations, ["netlify", "cloudflare_pages"])
    }

    // MARK: - Helpers

    private func isEdited() -> Bool {
        return SectionPublishState.hasUnpublishedEdits(
            courseDirectory: courseDirectory,
            sectionNumber: 1
        )
    }

    private func publishNow(destinations: [String] = ["netlify"]) {
        SectionPublishState.recordPublish(
            courseDirectory: courseDirectory,
            sectionNumber: 1,
            fingerprint: SectionPublishState.fingerprint(
                courseDirectory: courseDirectory,
                sectionNumber: 1
            ),
            destinations: destinations
        )
    }

    private func write(_ text: String, to relativePath: String) throws {
        let url: URL = courseDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func rules() throws -> [String: Any] {
        let contracts: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts")
            .appendingPathComponent("app-rules.json")
        let whole: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: contracts)) as? [String: Any]
        )
        return try XCTUnwrap(whole["publishedFreshness"] as? [String: Any])
    }
}
