import XCTest
@testable import QuartzTeachers

/// Round-trip tests for the course configuration: the app must read and
/// write `course_config.json` without losing anything the command-line
/// scripts put there.
final class CourseConfigurationTests: XCTestCase {

    // MARK: - Functions

    /// A fixture matching what the setup wizard writes for a small course.
    @MainActor
    func makeFixtureDictionary() -> [String: Any] {
        return [
            "course_code": "EXC2O",
            "course_name": "Example Course",
            "locale": "en-US",
            "emojis": ["sections": ["section1": "📚", "section2": "📝"]],
            "num_sections": 2,
            "section_numbers": [1, 2],
            "shared_folders": ["Concepts", "Exercises"],
            "shared_files": ["Learning Goals.md"],
            "per_section_folders": ["All Classes"],
            "per_section_files": ["Key Links.md"],
            "hidden": ["Media"],
            "expandable": ["Concepts", "Exercises"],
            "expandOnFolderClick": false,
            "footer_html": "",
            "show_reading_time": false,
            "fonts": [
                "default": ["header": "Montserrat", "body": "Lora", "code": "JetBrains Mono"],
                "sections": [:],
            ],
            "show_section_marker": ["sections": ["section1": true]],
            "color_schemes": ["section1": "quartz-standard"],
            "some_future_key_the_app_does_not_know": ["keep": "me"],
        ]
    }

    @MainActor
    func makeFixtureConfiguration() throws -> (configuration: CourseConfiguration, fileURL: URL) {
        let dictionary: [String: Any] = makeFixtureDictionary()
        let data: Data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("course_config_test_\(UUID().uuidString).json")
        try data.write(to: fileURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        return (configuration: configuration, fileURL: fileURL)
    }

    @MainActor
    func testReadingKnownValues() throws {
        let fixture = try makeFixtureConfiguration()
        let configuration: CourseConfiguration = fixture.configuration

        XCTAssertEqual(configuration.courseCode, "EXC2O")
        XCTAssertEqual(configuration.courseName, "Example Course")
        XCTAssertEqual(configuration.sectionNumbers, [1, 2])
        XCTAssertEqual(configuration.emoji(forSection: 2), "📝")
        XCTAssertEqual(configuration.colourSchemeID(forSection: 1), "quartz-standard")
        XCTAssertTrue(configuration.showsSectionMarker(forSection: 1))
        XCTAssertFalse(configuration.showReadingTime)
        XCTAssertFalse(configuration.isClub)
        XCTAssertEqual(configuration.fontChoice(forSection: 1).header, "Montserrat")
    }

    @MainActor
    func testRoundTripPreservesUnknownKeys() throws {
        let fixture = try makeFixtureConfiguration()
        let configuration: CourseConfiguration = fixture.configuration

        // Change one value the way the settings form would.
        configuration.showReadingTime = true

        let outputURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("course_config_out_\(UUID().uuidString).json")
        try configuration.write(to: outputURL)

        let writtenData: Data = try Data(contentsOf: outputURL)
        let decoded: Any = try JSONSerialization.jsonObject(with: writtenData)
        guard let writtenDictionary = decoded as? [String: Any] else {
            XCTFail("Written file was not a JSON object")
            return
        }

        // The edited value changed…
        XCTAssertEqual(writtenDictionary["show_reading_time"] as? Bool, true)

        // …and every other key survived, including one the app knows
        // nothing about.
        let unknown: [String: Any]? = writtenDictionary["some_future_key_the_app_does_not_know"] as? [String: Any]
        XCTAssertEqual(unknown?["keep"] as? String, "me")

        var originalDictionary: [String: Any] = makeFixtureDictionary()
        originalDictionary["show_reading_time"] = true
        XCTAssertTrue(
            (writtenDictionary as NSDictionary).isEqual(to: originalDictionary),
            "Round-tripped configuration should be semantically identical apart from the one edit"
        )
    }

    @MainActor
    func testDiscardChangesRestoresSavedValues() throws {
        let fixture = try makeFixtureConfiguration()
        let configuration: CourseConfiguration = fixture.configuration

        configuration.courseName = "Renamed"
        XCTAssertTrue(configuration.hasUnsavedChanges)

        try configuration.discardChanges()
        XCTAssertEqual(configuration.courseName, "Example Course")
        XCTAssertFalse(configuration.hasUnsavedChanges)
    }

    @MainActor
    func testClubDetection() throws {
        var dictionary: [String: Any] = makeFixtureDictionary()
        dictionary["course_code"] = "CODING"
        let configuration: CourseConfiguration = CourseConfiguration(
            values: dictionary,
            lastSavedData: try JSONSerialization.data(withJSONObject: dictionary)
        )
        XCTAssertTrue(configuration.isClub)
    }

    // MARK: - Landing title mirrors the build

    @MainActor
    func testTheLandingTitleHonoursBothSwitches() {
        XCTAssertEqual(
            CourseConfiguration.landingTitle(
                courseName: "Drama", courseCode: "ADA1O",
                showsGrade: true, showsSectionMarker: true, sectionNumber: 2),
            "Grade 9 Drama, Section 2")
        XCTAssertEqual(
            CourseConfiguration.landingTitle(
                courseName: "Drama", courseCode: "ADA1O",
                showsGrade: false, showsSectionMarker: true, sectionNumber: 2),
            "Drama, Section 2")
        XCTAssertEqual(
            CourseConfiguration.landingTitle(
                courseName: "Drama", courseCode: "ADA1O",
                showsGrade: true, showsSectionMarker: false, sectionNumber: 2),
            "Grade 9 Drama")
    }

    @MainActor
    func testTheLandingTitleSkipsTheGradeForClubCodes() {
        // "CODING" has no grade digit in position four, exactly as the
        // build's rule reads it — no prefix, switch on or not.
        XCTAssertEqual(
            CourseConfiguration.landingTitle(
                courseName: "Coding Club", courseCode: "CODING",
                showsGrade: true, showsSectionMarker: false, sectionNumber: 1),
            "Coding Club")
    }

    // MARK: - Deploy target

    @MainActor
    func testNetlifyIsTheDeployDefault() {
        let configuration: CourseConfiguration = CourseConfiguration(values: [:], lastSavedData: Data())
        XCTAssertEqual(configuration.deployTarget, "netlify")
        XCTAssertFalse(configuration.deploysToLocalFolder)
    }

    @MainActor
    func testAFolderDeployNeedsBothTheTargetAndAPath() {
        let configuration: CourseConfiguration = CourseConfiguration(values: [:], lastSavedData: Data())
        configuration.deployTarget = "local_folder"
        XCTAssertFalse(configuration.deploysToLocalFolder,
                       "Choosing the folder target without a folder must not divert deploys")
        configuration.deployFolderPath = "/Users/someone/Sites/ics3u"
        XCTAssertTrue(configuration.deploysToLocalFolder)
        XCTAssertEqual(configuration.deployTarget, "local_folder")
    }

    @MainActor
    func testAnEmptyOrMissingPublishFolderIsAProblem() {
        XCTAssertNotNil(CourseConfiguration.deployFolderProblem(forPath: ""),
                        "An empty folder path must block saving")
        XCTAssertNotNil(CourseConfiguration.deployFolderProblem(forPath: "   "),
                        "A whitespace-only path is still empty")
        XCTAssertNotNil(CourseConfiguration.deployFolderProblem(forPath: "/no/such/folder/anywhere"),
                        "A folder that does not exist cannot receive a site")
    }

    @MainActor
    func testAWritableFolderIsNoProblemAndAFileOrReadOnlyFolderIs() throws {
        let fileManager: FileManager = FileManager.default
        let base: URL = fileManager.temporaryDirectory
            .appendingPathComponent("publish-folder-checks-\(UUID().uuidString)")
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base.path)
            try? fileManager.removeItem(at: base)
        }

        XCTAssertNil(CourseConfiguration.deployFolderProblem(forPath: base.path),
                     "A writable folder is a fine publish destination")

        let file: URL = base.appendingPathComponent("not-a-folder.txt")
        try Data("hello".utf8).write(to: file)
        XCTAssertNotNil(CourseConfiguration.deployFolderProblem(forPath: file.path),
                        "A file is not a publish destination")

        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: base.path)
        XCTAssertNotNil(CourseConfiguration.deployFolderProblem(forPath: base.path),
                        "A read-only folder cannot receive a site")
    }

    @MainActor
    func testSectionNumbersAreSortedInAscendingOrder() throws {
        let dictionary: [String: Any] = [
            "course_code": "MCV4U",
            "section_numbers": [5, 4, 2, 9],
            "num_sections": 4
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("course_config_sorted_test_\(UUID().uuidString).json")
        try data.write(to: fileURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        XCTAssertEqual(configuration.sectionNumbers, [2, 4, 5, 9],
                       "Section numbers should always be sorted in ascending order")

        configuration.setSectionNumbers([8, 1, 6])
        XCTAssertEqual(configuration.sectionNumbers, [1, 6, 8])
    }

    // MARK: - Excluded items

    @MainActor
    func testExcludedItemsAbsentByDefault() {
        let configuration: CourseConfiguration = CourseConfiguration(values: [:], lastSavedData: Data())
        XCTAssertNil(configuration.excludedItems)
        XCTAssertEqual(configuration.excludedItems(forScope: "shared"), [])
        XCTAssertEqual(configuration.excludedItems(forScope: "per_section"), [])
        XCTAssertFalse(configuration.isExcluded("Tasks", inScope: "shared"))
    }

    @MainActor
    func testExcludingAndReincludingItems() {
        let configuration: CourseConfiguration = CourseConfiguration(values: [:], lastSavedData: Data())

        configuration.exclude("Tasks", inScope: "shared")
        XCTAssertTrue(configuration.isExcluded("Tasks", inScope: "shared"))
        XCTAssertFalse(configuration.isExcluded("Tasks", inScope: "per_section"))
        XCTAssertEqual(configuration.excludedItems(forScope: "shared"), ["Tasks"])

        // Duplicate exclusion is a no-op
        configuration.exclude("Tasks", inScope: "shared")
        XCTAssertEqual(configuration.excludedItems(forScope: "shared"), ["Tasks"])

        configuration.exclude("Handouts", inScope: "per_section")
        XCTAssertTrue(configuration.isExcluded("Handouts", inScope: "per_section"))

        // An ordinary add is not a re-inclusion: the trail must not say it was
        XCTAssertFalse(configuration.reinclude("Never Excluded", inScope: "shared"))
        XCTAssertFalse(configuration.reinclude("Handouts", inScope: "shared"))

        // Re-including shared Tasks cleans shared scope, and says so
        XCTAssertTrue(configuration.reinclude("Tasks", inScope: "shared"))
        XCTAssertFalse(configuration.isExcluded("Tasks", inScope: "shared"))
        XCTAssertEqual(configuration.excludedItems(forScope: "shared"), [])
        XCTAssertTrue(configuration.isExcluded("Handouts", inScope: "per_section"))

        // Re-including last item removes key entirely
        configuration.reinclude("Handouts", inScope: "per_section")
        XCTAssertNil(configuration.excludedItems)
        XCTAssertNil(configuration.values["excluded_items"])
    }

    @MainActor
    func testExcludedItemsRoundTrip() throws {
        var dictionary: [String: Any] = makeFixtureDictionary()
        dictionary["excluded_items"] = [
            "shared": ["Old Tasks"],
            "per_section": ["Drafts"]
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        let fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("course_config_excluded_test_\(UUID().uuidString).json")
        try data.write(to: fileURL)
        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        XCTAssertTrue(configuration.isExcluded("Old Tasks", inScope: "shared"))
        XCTAssertTrue(configuration.isExcluded("Drafts", inScope: "per_section"))

        let outputURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("course_config_excluded_out_\(UUID().uuidString).json")
        try configuration.write(to: outputURL)

        let writtenData: Data = try Data(contentsOf: outputURL)
        let decoded: Any = try JSONSerialization.jsonObject(with: writtenData)
        guard let writtenDictionary = decoded as? [String: Any] else {
            XCTFail("Written file was not a JSON object")
            return
        }
        guard let writtenExcluded = writtenDictionary["excluded_items"] as? [String: Any] else {
            XCTFail("excluded_items missing from written dictionary")
            return
        }
        XCTAssertEqual(writtenExcluded["shared"] as? [String], ["Old Tasks"])
        XCTAssertEqual(writtenExcluded["per_section"] as? [String], ["Drafts"])
    }
}
