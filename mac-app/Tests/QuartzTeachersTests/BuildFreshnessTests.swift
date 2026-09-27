import XCTest
@testable import QuartzTeachers

/// Publishing must never send a stale site: the freshness check decides
/// whether a build has to run first.
final class BuildFreshnessTests: XCTestCase {

    // MARK: - Functions

    /// A course folder with one section and an optional built site.
    @MainActor
    func makeCourse(withBuiltSite hasBuiltSite: Bool) throws -> Course {
        let courseURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cq4t-fresh-\(UUID().uuidString)")
            .appendingPathComponent("ICS3U")
        let sectionURL: URL = courseURL.appendingPathComponent("section1")
        try FileManager.default.createDirectory(at: sectionURL, withIntermediateDirectories: true)
        try Data("# lesson\n".utf8).write(to: sectionURL.appendingPathComponent("index.md"))

        let values: [String: Any] = ["course_code": "ICS3U", "section_numbers": [1]]
        let data: Data = try JSONSerialization.data(withJSONObject: values)
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))

        if hasBuiltSite {
            let publicURL: URL = courseURL
                .appendingPathComponent(".merged_output")
                .appendingPathComponent("section1")
                .appendingPathComponent("public")
            try FileManager.default.createDirectory(at: publicURL, withIntermediateDirectories: true)
            try Data("<html></html>".utf8).write(to: publicURL.appendingPathComponent("index.html"))
        }

        let configuration: CourseConfiguration = CourseConfiguration(values: values, lastSavedData: data)
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
    }

    /// Stamps a file's modification date, for ordering tests.
    func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// Back-dates EVERY entry in the course (files and the folders that
    /// hold them — creating a file bumps its parent's date too), so a
    /// test can then make exactly one thing newer.
    func backdateEverything(in courseURL: URL, to date: Date) throws {
        var urls: [URL] = [courseURL]
        if let enumerator = FileManager.default.enumerator(at: courseURL, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                urls.append(url)
            }
        }
        // Deepest first, so stamping a child cannot re-dirty its parent.
        urls.sort { first, second in
            return first.pathComponents.count > second.pathComponents.count
        }
        for url in urls {
            try setModificationDate(date, of: url)
        }
    }

    @MainActor
    func testNeverBuiltMeansRebuild() throws {
        let course: Course = try makeCourse(withBuiltSite: false)
        XCTAssertTrue(BuildFreshness.needsRebuild(course: course, sectionNumber: 1))
        XCTAssertNil(BuildFreshness.builtSiteDate(course: course, sectionNumber: 1))
    }

    @MainActor
    func testAPreviewBuildIsNeverDeployFresh() throws {
        // Serve mode bakes a live-reload client into every page;
        // deploying it makes the public site knock on ws://localhost
        // and browsers prompt every visitor. Newer-than-content is not
        // enough — a preview's build always rebuilds before publishing.
        let course: Course = try makeCourse(withBuiltSite: true)
        let builtIndexURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output/section1/public/index.html")

        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        try Data(BuildFreshnessTests.clientAsQuartzWritesIt().utf8)
            .write(to: builtIndexURL)
        try setModificationDate(Date(timeIntervalSinceNow: 300), of: builtIndexURL)

        let builtPublicURL: URL = builtIndexURL.deletingLastPathComponent()
        XCTAssertTrue(BuildFreshness.builtForPreview(publicDirectory: builtPublicURL))
        XCTAssertTrue(BuildFreshness.needsRebuild(course: course, sectionNumber: 1),
                      "A preview's build is never deploy-fresh, however new it is")

        try Data("a clean production page".utf8).write(to: builtIndexURL)
        try setModificationDate(Date(timeIntervalSinceNow: 300), of: builtIndexURL)
        XCTAssertFalse(BuildFreshness.builtForPreview(publicDirectory: builtPublicURL))
        XCTAssertFalse(BuildFreshness.needsRebuild(course: course, sectionNumber: 1),
                       "A clean production build newer than the content is current")
    }

    @MainActor
    func testBuiltAfterContentIsUpToDate() throws {
        let course: Course = try makeCourse(withBuiltSite: true)
        let lessonURL: URL = course.directoryURL.appendingPathComponent("section1/index.md")
        let builtIndexURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output/section1/public/index.html")

        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        try setModificationDate(Date(timeIntervalSinceNow: -60), of: builtIndexURL)
        XCTAssertNotNil(lessonURL)

        XCTAssertFalse(BuildFreshness.needsRebuild(course: course, sectionNumber: 1), "A site built after the last edit is current")
    }

    @MainActor
    func testEditingContentAfterBuildingMeansRebuild() throws {
        let course: Course = try makeCourse(withBuiltSite: true)
        let lessonURL: URL = course.directoryURL.appendingPathComponent("section1/index.md")
        let builtIndexURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output/section1/public/index.html")

        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        try setModificationDate(Date(timeIntervalSinceNow: -300), of: builtIndexURL)
        try setModificationDate(Date(timeIntervalSinceNow: -10), of: lessonURL)

        XCTAssertTrue(BuildFreshness.needsRebuild(course: course, sectionNumber: 1), "An edit after the build must trigger a rebuild")
    }

    @MainActor
    func testChangingSettingsMeansRebuild() throws {
        let course: Course = try makeCourse(withBuiltSite: true)
        let configURL: URL = course.configFileURL
        let builtIndexURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output/section1/public/index.html")

        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        try setModificationDate(Date(timeIntervalSinceNow: -300), of: builtIndexURL)
        try setModificationDate(Date(timeIntervalSinceNow: -10), of: configURL)

        XCTAssertTrue(BuildFreshness.needsRebuild(course: course, sectionNumber: 1), "Saved settings must trigger a rebuild")
    }

    @MainActor
    func testGeneratedAndHiddenFilesDoNotTriggerRebuilds() throws {
        let course: Course = try makeCourse(withBuiltSite: true)
        let builtIndexURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output/section1/public/index.html")
        // Deploy markers and Obsidian settings churn constantly; they are
        // not content and must not force a rebuild. Create them BEFORE
        // back-dating so only their own (hidden) entries are recent.
        let markerURL: URL = course.directoryURL.appendingPathComponent(".netlify_sites")
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)
        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        try setModificationDate(Date(timeIntervalSinceNow: -300), of: builtIndexURL)
        try Data("{}".utf8).write(to: markerURL.appendingPathComponent("section1.json"))

        XCTAssertFalse(BuildFreshness.needsRebuild(course: course, sectionNumber: 1), "Hidden, generated files should be ignored")
    }
    // MARK: - A Save made while a publish was building (issue #265)

    /// The reviewer's H1: settings saved while a publish was BUILDING are
    /// older than the page that build writes at its end. Compared with the
    /// page alone, the site looked built and the next Publish sent the same
    /// old site. `contracts/app-rules.json` → `buildFreshness`, the rule
    /// about something saved after the build started.
    @MainActor
    func testSettingsSavedWhileThePublishWasBuildingMeanRebuild() throws {
        let course: Course = try makeCourse(withBuiltSite: true)
        let builtIndexURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output/section1/public/index.html")
        let markerURL: URL = BuildFreshness.buildStartedMarkerURL(course: course, sectionNumber: 1)
        try Data("started".utf8).write(to: markerURL)

        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        // The build started, the teacher saved, the build finished.
        try setModificationDate(Date(timeIntervalSinceNow: -400), of: markerURL)
        try setModificationDate(Date(timeIntervalSinceNow: -350), of: course.configFileURL)
        try setModificationDate(Date(timeIntervalSinceNow: -300), of: builtIndexURL)

        XCTAssertTrue(
            BuildFreshness.needsRebuild(course: course, sectionNumber: 1),
            "A Save after the build started was not in that build, however new the page is"
        )
    }

    /// The same for a page saved during the build — the start time covers
    /// every file, not only the settings.
    @MainActor
    func testAPageSavedWhileTheBuildRanMeansRebuild() throws {
        let course: Course = try makeCourse(withBuiltSite: true)
        let lessonURL: URL = course.directoryURL.appendingPathComponent("section1/index.md")
        let builtIndexURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output/section1/public/index.html")
        let markerURL: URL = BuildFreshness.buildStartedMarkerURL(course: course, sectionNumber: 1)
        try Data("started".utf8).write(to: markerURL)

        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        try setModificationDate(Date(timeIntervalSinceNow: -400), of: markerURL)
        try setModificationDate(Date(timeIntervalSinceNow: -350), of: lessonURL)
        try setModificationDate(Date(timeIntervalSinceNow: -300), of: builtIndexURL)

        XCTAssertTrue(BuildFreshness.needsRebuild(course: course, sectionNumber: 1))
    }

    /// Nothing saved after the build started: still up to date — the marker
    /// must not make every publish rebuild.
    @MainActor
    func testNothingSavedSinceTheBuildStartedIsUpToDate() throws {
        let course: Course = try makeCourse(withBuiltSite: true)
        let builtIndexURL: URL = course.directoryURL
            .appendingPathComponent(".merged_output/section1/public/index.html")
        let markerURL: URL = BuildFreshness.buildStartedMarkerURL(course: course, sectionNumber: 1)
        try Data("started".utf8).write(to: markerURL)

        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        try setModificationDate(Date(timeIntervalSinceNow: -400), of: markerURL)
        try setModificationDate(Date(timeIntervalSinceNow: -300), of: builtIndexURL)

        XCTAssertFalse(BuildFreshness.needsRebuild(course: course, sectionNumber: 1))
    }

    /// The earlier of the two times is the one compared with; with no marker
    /// the page's own time is, as before.
    @MainActor
    func testTheReferenceIsTheEarlierTime() {
        let page: Date = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(BuildFreshness.referenceDate(builtDate: page, buildStartedDate: nil), page)
        XCTAssertEqual(
            BuildFreshness.referenceDate(builtDate: page, buildStartedDate: Date(timeIntervalSince1970: 900)),
            Date(timeIntervalSince1970: 900)
        )
        XCTAssertEqual(
            BuildFreshness.referenceDate(builtDate: page, buildStartedDate: Date(timeIntervalSince1970: 1_100)),
            page,
            "A marker newer than the page is not believed: an early answer only costs a rebuild"
        )
    }

    /// The marker's name is the one the build writes and the contract gives.
    @MainActor
    func testTheMarkerIsTheOneTheContractNames() throws {
        let contractURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/app-rules.json")
        let data: Data = try Data(contentsOf: contractURL)
        let rules: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let freshness: [String: Any] = try XCTUnwrap(rules["buildFreshness"] as? [String: Any])
        let marker: [String: Any] = try XCTUnwrap(freshness["buildStartedMarker"] as? [String: Any])
        XCTAssertEqual(marker["file"] as? String, BuildFreshness.buildStartedMarkerName)

        var ruleNamed: Bool = false
        for rule in try XCTUnwrap(freshness["rules"] as? [[String: Any]]) {
            let when: String = rule["when"] as? String ?? ""
            if when.contains("AFTER the build that made the site started") {
                ruleNamed = rule["expectRebuild"] as? Bool == true
            }
        }
        XCTAssertTrue(ruleNamed, "The contract names the rule these tests pin")
    }

    // MARK: - Every page, not the front page alone (issue #136)

    /// The contract's cases for "this built site is a preview's":
    /// `app-rules.json` → `buildFreshness.previewBuild`. Shared with
    /// `ScheduledPublishOutcomeTests`, which runs the overnight check against
    /// the same list.
    static func previewBuildRule() throws -> [String: Any] {
        let contractURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/app-rules.json")
        let data: Data = try Data(contentsOf: contractURL)
        let rules: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let freshness: [String: Any] = try XCTUnwrap(rules["buildFreshness"] as? [String: Any])
        return try XCTUnwrap(freshness["previewBuild"] as? [String: Any])
    }

    /// The contract's `signature` object (issue #291).
    static func previewSignature() throws -> [String: Any] {
        let rule: [String: Any] = try previewBuildRule()
        return try XCTUnwrap(rule["signature"] as? [String: Any], "signature is an object since #291")
    }

    /// The live-reload client exactly as Quartz writes it into a preview's
    /// page, read from the contract rather than retyped: a retyped fixture
    /// could pass against a wrong constant.
    static func clientAsQuartzWritesIt() throws -> String {
        let signature: [String: Any] = try previewSignature()
        return try XCTUnwrap(signature["asQuartzWritesIt"] as? String)
    }

    /// Writes one case's pages under `publicURL` and makes the ones it names
    /// unreadable. A page named in `invalidUTF8Before` begins with the bytes
    /// FF 0A, which are not UTF-8. Returns those, so the caller can make them readable again
    /// and the temporary folder can be removed.
    static func writePages(of testCase: [String: Any], into publicURL: URL) throws -> [URL] {
        let pages: [String: String] = try XCTUnwrap(testCase["pages"] as? [String: String])
        for (relativePath, text) in pages {
            let pageURL: URL = publicURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: pageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: pageURL)
        }
        let invalidUTF8Pages: [String] = testCase["invalidUTF8Before"] as? [String] ?? []
        for relativePath in invalidUTF8Pages {
            let pageURL: URL = publicURL.appendingPathComponent(relativePath)
            var bytes: Data = Data([0xFF, 0x0A])
            bytes.append(try Data(contentsOf: pageURL))
            try bytes.write(to: pageURL)
        }
        var lockedURLs: [URL] = []
        let unreadable: [String] = testCase["unreadable"] as? [String] ?? []
        for relativePath in unreadable {
            let pageURL: URL = publicURL.appendingPathComponent(relativePath)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: pageURL.path)
            lockedURLs.append(pageURL)
        }
        return lockedURLs
    }

    /// Gives back what `writePages` took away, so the folder can be removed.
    static func makeReadable(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
    }

    /// Every case in the contract, against the app's own check.
    @MainActor
    func testEveryPreviewBuildCaseInTheContract() throws {
        let rule: [String: Any] = try BuildFreshnessTests.previewBuildRule()
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let expectPreview: Bool = try XCTUnwrap(testCase["expectPreview"] as? Bool)
            let publicURL: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cq4t-preview-\(UUID().uuidString)")
                .appendingPathComponent("public")
            let lockedURLs: [URL] = try BuildFreshnessTests.writePages(of: testCase, into: publicURL)
            defer {
                BuildFreshnessTests.makeReadable(lockedURLs)
                try? FileManager.default.removeItem(at: publicURL.deletingLastPathComponent())
            }
            XCTAssertEqual(BuildFreshness.builtForPreview(publicDirectory: publicURL), expectPreview, name)
        }
    }

    /// The signature the app looks for is the one the contract gives, so
    /// the launchers and the app cannot drift apart on the rule itself.
    @MainActor
    func testTheSignatureIsTheContracts() throws {
        let signature: [String: Any] = try BuildFreshnessTests.previewSignature()
        XCTAssertEqual(signature["scriptTag"] as? String, BuildFreshness.liveReloadScriptTag)
        XCTAssertEqual(signature["client"] as? String, BuildFreshness.liveReloadClient)
        XCTAssertEqual(signature["asABasicRegex"] as? String, BuildFreshness.liveReloadPattern)
        let between: [String] = try XCTUnwrap(signature["between"] as? [String])
        var betweenBytes: Set<UInt8> = []
        for character in between {
            let bytes: [UInt8] = Array(character.utf8)
            XCTAssertEqual(bytes.count, 1, "each `between` entry is one byte")
            for byte in bytes {
                betweenBytes.insert(byte)
            }
        }
        XCTAssertEqual(betweenBytes, BuildFreshness.liveReloadWhitespace)
        let asQuartzWritesIt: String = try XCTUnwrap(signature["asQuartzWritesIt"] as? String)
        XCTAssertTrue(BuildFreshness.carriesLiveReloadClient(Data(asQuartzWritesIt.utf8)))
    }

    /// The state issue #136 is about, as a course sees it: a clean front page
    /// newer than every edit, with a preview's page behind it. Laid out the
    /// way the app lays it out — `.merged_output` a link into a builds folder
    /// elsewhere — so the walk is shown to follow that link.
    @MainActor
    func testACleanFrontPageInFrontOfAPreviewPageIsNotDeployFresh() throws {
        let course: Course = try makeCourse(withBuiltSite: false)
        let buildsURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cq4t-builds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: buildsURL) }
        let publicURL: URL = buildsURL.appendingPathComponent("section1/public")
        try FileManager.default.createDirectory(
            at: publicURL.appendingPathComponent("notes"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: course.directoryURL.appendingPathComponent(".merged_output"),
            withDestinationURL: buildsURL
        )
        let indexURL: URL = publicURL.appendingPathComponent("index.html")
        let notesURL: URL = publicURL.appendingPathComponent("notes/day-1.html")
        try Data("<html><body>Welcome</body></html>".utf8).write(to: indexURL)
        try Data("<html><body>Day 1</body></html>".utf8).write(to: notesURL)

        try backdateEverything(in: course.directoryURL, to: Date(timeIntervalSinceNow: -600))
        try setModificationDate(Date(timeIntervalSinceNow: -60), of: indexURL)
        XCTAssertFalse(
            BuildFreshness.needsRebuild(course: course, sectionNumber: 1),
            "A clean site newer than every edit is current — the walk must not make every publish rebuild"
        )

        try Data(BuildFreshnessTests.clientAsQuartzWritesIt().utf8).write(to: notesURL)
        XCTAssertTrue(
            BuildFreshness.needsRebuild(course: course, sectionNumber: 1),
            "A preview's page behind a clean front page is still a preview's build"
        )
    }
}
