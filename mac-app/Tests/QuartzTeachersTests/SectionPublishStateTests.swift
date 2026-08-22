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

    /// Driven through the REAL walk — every path in the contract is
    /// written to disk, changed, and the marker asked about — rather than
    /// through the filter function alone.
    ///
    /// The difference is not academic. Reviewed adversarially, the filter
    /// said `Media/diagram.png` counted, the contract said it counted, and
    /// the walk skipped the whole folder whenever `Media` was a symlink,
    /// which is how build_site.py itself sets it up. A test that asks the
    /// filter agrees with a bug; a test that asks the walk finds it.
    func testTheRightFilesCountTowardTheFingerprint() throws {
        let section: [String: Any] = try XCTUnwrap(
            try SectionPublishStateTests.rules()["filesCounted"] as? [String: Any]
        )
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            let path: String = try XCTUnwrap(testCase["path"] as? String)
            let counts: Bool = try XCTUnwrap(testCase["counts"] as? Bool)
            let why: String = testCase["why"] as? String ?? ""

            try write("first", to: path)
            let before: String = SectionPublishState.fingerprint(
                courseDirectory: courseDirectory, sectionNumber: 1
            )
            try write("second, and longer", to: path)
            let after: String = SectionPublishState.fingerprint(
                courseDirectory: courseDirectory, sectionNumber: 1
            )

            XCTAssertEqual(
                before != after, counts,
                "\(path) — the WALK must agree with the contract, not just the filter. \(why)"
            )
            XCTAssertEqual(
                SectionPublishState.countsTowardFingerprint(relativePath: path, sectionNumber: 1),
                counts,
                "\(path): \(why)"
            )
        }
    }

    /// A symlinked page, and a symlinked folder, are content the site is
    /// built from. Neither is a regular file, and `FileManager`'s
    /// enumerator follows neither — so both were invisible until this
    /// test existed.
    func testSymlinkedContentIsSeen() throws {
        let outside: URL = courseDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("vault")
        try FileManager.default.createDirectory(
            at: outside.appendingPathComponent("Media"), withIntermediateDirectories: true
        )
        try "diagram".write(
            to: outside.appendingPathComponent("Media/diagram.svg"),
            atomically: true, encoding: .utf8
        )
        try "linked page".write(
            to: outside.appendingPathComponent("Linked.md"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: courseDirectory.appendingPathComponent("Media"),
            withDestinationURL: outside.appendingPathComponent("Media")
        )
        try FileManager.default.createSymbolicLink(
            at: courseDirectory.appendingPathComponent("Unit 1/Linked.md"),
            withDestinationURL: outside.appendingPathComponent("Linked.md")
        )

        publishNow()
        XCTAssertFalse(isEdited())

        try "a completely different diagram".write(
            to: outside.appendingPathComponent("Media/diagram.svg"),
            atomically: true, encoding: .utf8
        )
        XCTAssertTrue(isEdited(), "A change inside a symlinked Media folder is a change to the site")

        publishNow()
        try "a completely different linked page".write(
            to: outside.appendingPathComponent("Linked.md"), atomically: true, encoding: .utf8
        )
        XCTAssertTrue(isEdited(), "A symlinked page is still a page")
    }

    /// A course that publishes into a folder inside itself must not feed
    /// its own marker — `deploy.py` writes the whole site there.
    func testACourseThatPublishesIntoItselfIsNotItsOwnEdit() throws {
        let excluded: [String] = SectionPublishState.selfPublishingSubpaths(
            courseDirectory: courseDirectory,
            destinations: [
                CourseConfiguration.DeployDestination(
                    type: "local_folder", path: courseDirectory.appendingPathComponent("site").path
                ),
            ]
        )
        XCTAssertEqual(excluded, ["site"])

        let before: String = SectionPublishState.fingerprint(
            courseDirectory: courseDirectory, sectionNumber: 1, excludingRelativePaths: excluded
        )
        try write("<html>the whole built site</html>", to: "site/index.html")
        XCTAssertEqual(
            SectionPublishState.fingerprint(
                courseDirectory: courseDirectory, sectionNumber: 1, excludingRelativePaths: excluded
            ),
            before,
            "Publishing into the course folder must not read as editing it"
        )
    }

    /// A destination somewhere else on the disk excludes nothing.
    func testAnOrdinaryPublishFolderExcludesNothing() {
        XCTAssertEqual(
            SectionPublishState.selfPublishingSubpaths(
                courseDirectory: courseDirectory,
                destinations: [
                    CourseConfiguration.DeployDestination(
                        type: "local_folder", path: "/Users/teacher/Sites/ICS3U"
                    ),
                ]
            ),
            []
        )
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

/// The other half of `publishedFreshness` — when a publish is RECORDED at
/// all. Every rule in `whenRecorded` was authored and pinned by nothing
/// until an adversarial review pointed out that a quarter of the contract
/// was decoration, which is how the fingerprint came to be taken at a
/// moment the contract said it was not.
@MainActor
final class SectionPublishRecordingTests: XCTestCase {

    // MARK: - Stored properties

    private var course: Course!

    // MARK: - Set-up

    override func setUpWithError() throws {
        let directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("publish-record-\(UUID().uuidString)")
            .appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        course = Course(
            code: "ICS3U",
            directoryURL: directory,
            configuration: CourseConfiguration(values: ["course_code": "ICS3U"], lastSavedData: Data())
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: course.directoryURL.deletingLastPathComponent())
    }

    // MARK: - Functions

    func testEveryRecordingRuleTheContractNames() throws {
        let netlify: CourseConfiguration.DeployDestination =
            CourseConfiguration.DeployDestination(type: "netlify", path: "")
        let cloudflare: CourseConfiguration.DeployDestination =
            CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")

        XCTAssertTrue(
            recorded(legs: [finished(netlify, succeeded: true)]),
            "every configured destination succeeded"
        )
        XCTAssertTrue(
            recorded(legs: [finished(netlify, succeeded: true), finished(cloudflare, succeeded: true)])
        )
        XCTAssertFalse(
            recorded(legs: [finished(netlify, succeeded: true), finished(cloudflare, succeeded: false)]),
            "one of two destinations failed — the section has NOT published"
        )
        XCTAssertFalse(
            recorded(legs: [finished(netlify, succeeded: false)]),
            "the publish was cancelled or stopped"
        )
        XCTAssertFalse(
            recorded(legs: [finished(netlify, succeeded: false, buildFailed: true)]),
            "the shared build failed"
        )
        XCTAssertFalse(recorded(legs: []), "no destination ran at all")
    }

    /// The fingerprint must be taken before the BUILD, not after it. The
    /// build is the longest part of a publish, so a page edited while it
    /// runs must leave the marker up rather than be stamped as published.
    func testAPageEditedDuringTheBuildIsNotMarkedAsPublished() throws {
        let page: URL = course.directoryURL.appendingPathComponent("section1/Classes/Day.md")
        try FileManager.default.createDirectory(
            at: page.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "before".write(to: page, atomically: true, encoding: .utf8)

        // What the runner does at the top of its loop, before the build.
        let atStart: String = SectionPublishState.fingerprint(
            courseDirectory: course.directoryURL, sectionNumber: 1
        )
        // …the build runs, and the teacher edits a page while it does.
        try "edited while the build was running".write(to: page, atomically: true, encoding: .utf8)

        let runner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        runner.legs = [
            finished(CourseConfiguration.DeployDestination(type: "netlify", path: ""), succeeded: true),
        ]
        runner.recordWhatWentOut(course: course, sectionNumber: 1, fingerprint: atStart)

        XCTAssertTrue(
            SectionPublishState.hasUnpublishedEdits(
                courseDirectory: course.directoryURL, sectionNumber: 1
            ),
            "An edit made during the publish did not go out, and must keep the marker up"
        )
    }

    /// A scheduled deploy never goes through the deploy runner — launchd
    /// runs a shell script — so it needs its own path to the same record.
    func testAScheduledDeployRecordsWhatWentOut() throws {
        let sentinel: URL = ScheduledDeploy.successSentinelURL(courseCode: "ICS3U", sectionNumber: 1)
        try FileManager.default.createDirectory(
            at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: sentinel) }

        let section: (courseDirectory: URL, courseCode: String, sectionNumber: Int) =
            (course.directoryURL, "ICS3U", 1)

        // No sentinel: the script did not say every destination worked.
        ScheduledDeploy.recordScheduledPublish(section: section, fingerprint: "abc")
        XCTAssertNil(SectionPublishState.stamp(courseDirectory: course.directoryURL, sectionNumber: 1))

        try "netlify cloudflare_pages\n".write(to: sentinel, atomically: true, encoding: .utf8)
        ScheduledDeploy.recordScheduledPublish(section: section, fingerprint: "abc")
        let stamp = SectionPublishState.stamp(courseDirectory: course.directoryURL, sectionNumber: 1)
        XCTAssertEqual(stamp?.fingerprint, "abc")
        XCTAssertEqual(stamp?.destinations, ["netlify", "cloudflare_pages"])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sentinel.path),
            "The sentinel is consumed, or tonight's failure reads as tomorrow's success"
        )
    }

    /// The agent has to tell the app which section it just published, or
    /// the app cannot record anything.
    func testTheScheduledScriptAndAgentCarryTheSection() {
        let workspace: URL = URL(fileURLWithPath: "/Users/teacher/Teaching")
        let named = ScheduledDeploy.requestedSection(from: [
            "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
            ScheduledDeploy.runFlag, "/tmp/script.sh",
            ScheduledDeploy.sectionFlag, workspace.path, "ICS3U", "2",
        ])
        XCTAssertEqual(named?.courseCode, "ICS3U")
        XCTAssertEqual(named?.sectionNumber, 2)
        XCTAssertEqual(
            named?.courseDirectory.path,
            workspace.appendingPathComponent("courses/ICS3U").path
        )
        XCTAssertNil(ScheduledDeploy.requestedSection(from: ["Plantoir"]))

        let script: String = ScheduledDeploy.oneShotCommand(
            courseCode: "ICS3U",
            sectionNumber: 1,
            workspaceURL: workspace,
            deployArgumentsList: [["ICS3U", "1"], ["ICS3U", "1", "--target", "cloudflare"]],
            destinationTypes: ["netlify", "cloudflare_pages"]
        )
        XCTAssertTrue(
            script.contains("ALL_OK=0"),
            "Each destination's own result must be tracked, not just the last one's"
        )
        XCTAssertTrue(script.contains("netlify cloudflare_pages"))
        XCTAssertTrue(
            script.contains(ScheduledDeploy.successSentinelURL(courseCode: "ICS3U", sectionNumber: 1).path)
        )
    }

    // MARK: - Helpers

    private func finished(
        _ destination: CourseConfiguration.DeployDestination,
        succeeded: Bool,
        buildFailed: Bool = false
    ) -> MultiDestinationDeployRunner.Leg {
        var leg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: destination
        )
        leg.isFinished = true
        leg.succeeded = succeeded
        leg.buildFailed = buildFailed
        return leg
    }

    private func recorded(legs: [MultiDestinationDeployRunner.Leg]) -> Bool {
        try? FileManager.default.removeItem(
            at: SectionPublishState.stampURL(courseDirectory: course.directoryURL, sectionNumber: 1)
        )
        let runner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        runner.legs = legs
        runner.recordWhatWentOut(course: course, sectionNumber: 1, fingerprint: "fingerprint")
        return SectionPublishState.stamp(
            courseDirectory: course.directoryURL, sectionNumber: 1
        ) != nil
    }
}
