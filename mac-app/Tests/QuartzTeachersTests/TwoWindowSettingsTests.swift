import XCTest
@testable import QuartzTeachers

/// Issue #265: two windows on one working folder each hold their own copy of
/// a course's settings. A Save in one must not put back the other's older
/// settings, and the other window must follow the Save.
///
/// The first test is the plan review's standalone reproduction, turned into a
/// test: window A saves three sidebar hides, window B — which never saw that
/// Save — saves an unrelated setting, and the three hides must survive. On the
/// old whole-file write the file went back to B's list.
final class TwoWindowSettingsTests: XCTestCase {

    // MARK: - Stored properties

    var folderURL: URL!

    // MARK: - Functions

    override func setUpWithError() throws {
        folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TwoWindowSettings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folderURL)
    }

    /// A course's settings with ten hides, the shape of the real course the
    /// reproduction was seeded from.
    @MainActor
    func writeSeedFile() throws -> URL {
        let seed: [String: Any] = [
            "course_code": "ICS4U",
            "course_name": "Computer Science",
            "section_numbers": [1],
            "shared_folders": ["College Board Curriculum", "Examples", "Portfolios", "Recaps", "Style", "Tasks", "Curriculum"],
            "shared_files": ["Grove Time.md", "Key Links.md"],
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
            "hidden": ["Media", "College Board Curriculum", "Examples", "Portfolios", "Recaps", "Style", "Tasks", "Curriculum", "Grove Time.md", "Key Links.md"],
            "show_reading_time": false,
        ]
        let courseURL: URL = folderURL.appendingPathComponent("courses/ICS4U")
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        let fileURL: URL = courseURL.appendingPathComponent("course_config.json")
        let data: Data = try JSONSerialization.data(withJSONObject: seed, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL)
        return fileURL
    }

    /// What `hidden` says in the file right now.
    @MainActor
    func hiddenOnDisk(at fileURL: URL) throws -> [String] {
        let reread: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        return reread.hiddenItems
    }

    @MainActor
    func testASaveInAStaleWindowKeepsTheOtherWindowsHides() throws {
        let fileURL: URL = try writeSeedFile()
        let windowA: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        let windowB: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        windowA.hiddenItems = ["Media", "All Classes", "College Board Curriculum"]
        try windowA.write(to: fileURL)

        windowB.showReadingTime = true
        let result: CourseConfiguration.WriteResult = try windowB.write(to: fileURL)

        XCTAssertEqual(try hiddenOnDisk(at: fileURL), ["Media", "All Classes", "College Board Curriculum"])
        XCTAssertTrue(try CourseConfiguration(contentsOf: fileURL).showReadingTime)
        // B's form now shows what was really saved, and has nothing unsaved.
        XCTAssertEqual(windowB.hiddenItems, ["Media", "All Classes", "College Board Curriculum"])
        XCTAssertFalse(windowB.hasUnsavedChanges)
        XCTAssertEqual(result.keptFromElsewhere, ["hidden"])
        XCTAssertEqual(result.replacedChangesFromElsewhere, [])
    }

    /// Both windows changed the same setting: the Save being made wins, and
    /// the write says the file had been changed elsewhere.
    @MainActor
    func testWhenBothWindowsChangedTheListTheLaterSaveWinsAndSaysSo() throws {
        let fileURL: URL = try writeSeedFile()
        let windowA: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        let windowB: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        windowA.hiddenItems = ["Media"]
        try windowA.write(to: fileURL)
        windowB.hiddenItems = ["Media", "Tasks"]
        let result: CourseConfiguration.WriteResult = try windowB.write(to: fileURL)

        XCTAssertEqual(try hiddenOnDisk(at: fileURL), ["Media", "Tasks"])
        XCTAssertEqual(result.replacedChangesFromElsewhere, ["hidden"])
        XCTAssertTrue(result.fileHadChangedElsewhere)
    }

    /// A folder the build added to the course's list while a window was open
    /// is kept when that window saves something else.
    @MainActor
    func testAFolderTheBuildAddedSurvivesASaveOfSomethingElse() throws {
        let fileURL: URL = try writeSeedFile()
        let window: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        let build: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        var folders: [String] = build.sharedFolders
        folders.append("Projects")
        build.sharedFolders = folders
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        try JSONSerialization.data(withJSONObject: build.values, options: options).write(to: fileURL)

        window.showReadingTime = true
        try window.write(to: fileURL)

        XCTAssertTrue(try CourseConfiguration(contentsOf: fileURL).sharedFolders.contains("Projects"))
    }

    /// Nothing written elsewhere: the write is exactly the old one.
    @MainActor
    func testAWriteWithNothingChangedElsewhereReportsNothing() throws {
        let fileURL: URL = try writeSeedFile()
        let window: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        window.hiddenItems = ["Media"]
        let result: CourseConfiguration.WriteResult = try window.write(to: fileURL)
        XCTAssertFalse(result.fileHadChangedElsewhere)
        XCTAssertEqual(try hiddenOnDisk(at: fileURL), ["Media"])
    }

    /// After a Save, the other window's copy of the course follows it —
    /// unless that copy has unsaved changes, which are never discarded.
    @MainActor
    func testTheOtherWindowFollowsASaveButNeverOverUnsavedChanges() throws {
        let fileURL: URL = try writeSeedFile()
        let suiteName: String = "TwoWindowSettingsTests-" + UUID().uuidString
        let defaults: UserDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let courseURL: URL = fileURL.deletingLastPathComponent()

        let windowA: Course = Course(code: "ICS4U", directoryURL: courseURL, configuration: try CourseConfiguration(contentsOf: fileURL))
        let windowB: Course = Course(code: "ICS4U", directoryURL: courseURL, configuration: try CourseConfiguration(contentsOf: fileURL))
        let modelA: WorkspaceModel = WorkspaceModel(defaults: defaults)
        let modelB: WorkspaceModel = WorkspaceModel(defaults: defaults)
        modelA.courses = [windowA]
        modelB.courses = [windowB]

        windowA.configuration.hiddenItems = ["Media"]
        try windowA.configuration.write(to: fileURL)
        let reloaded: Int = WorkspaceModel.followWrite(of: windowA.configuration, at: fileURL, in: [modelA, modelB])
        XCTAssertEqual(reloaded, 1)
        XCTAssertEqual(windowB.configuration.hiddenItems, ["Media"])
        XCTAssertFalse(windowB.configuration.hasUnsavedChanges)

        windowB.configuration.showReadingTime = true
        windowA.configuration.hiddenItems = ["Media", "Tasks"]
        try windowA.configuration.write(to: fileURL)
        let reloadedAgain: Int = WorkspaceModel.followWrite(of: windowA.configuration, at: fileURL, in: [modelA, modelB])
        XCTAssertEqual(reloadedAgain, 0)
        XCTAssertTrue(windowB.configuration.showReadingTime)
        XCTAssertTrue(windowB.configuration.hasUnsavedChanges)
    }

    /// Opening Course Settings reads the file again, so a folder a build
    /// discovered is offered without relaunching — but never over unsaved
    /// edits.
    @MainActor
    func testOpeningSettingsReadsTheFileAgainUnlessSomethingIsUnsaved() throws {
        let fileURL: URL = try writeSeedFile()
        let window: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)

        let build: CourseConfiguration = try CourseConfiguration(contentsOf: fileURL)
        var folders: [String] = build.sharedFolders
        folders.append("Projects")
        build.sharedFolders = folders
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        try JSONSerialization.data(withJSONObject: build.values, options: options).write(to: fileURL)

        XCTAssertTrue(window.reloadIfNothingUnsaved(url: fileURL))
        XCTAssertTrue(window.sharedFolders.contains("Projects"))

        folders.append("Labs")
        build.sharedFolders = folders
        try JSONSerialization.data(withJSONObject: build.values, options: options).write(to: fileURL)
        window.showReadingTime = true
        XCTAssertFalse(window.reloadIfNothingUnsaved(url: fileURL))
        XCTAssertTrue(window.showReadingTime)
        XCTAssertFalse(window.sharedFolders.contains("Labs"))
    }
}
