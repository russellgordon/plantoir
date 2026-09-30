import XCTest
@testable import QuartzTeachers

/// How the start-of-year plan, its sheet and its undo name a page (#362): by
/// its title, with its folder within the course only when another page has
/// the same title — never a path to the file.
final class StartOfYearNamingTests: XCTestCase {

    // MARK: - Stored properties

    private var root: URL = URL(fileURLWithPath: "/")

    // MARK: - Set up

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("start-of-year-naming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Functions

    private func write(_ relative: String, title: String?) throws -> URL {
        let url: URL = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text: String = "About it."
        if let title {
            text = "---\ntitle: \(title)\n---\n\n" + text
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tests

    /// The undo sheet listed bare paths (`courses/ICS3U/Concepts/Watt.md`)
    /// with no title at all.
    func testTheUndoListNamesEachFileByItsTitle() throws {
        let course: URL = root.appendingPathComponent("courses/ICS3U")
        let watt: URL = try write("courses/ICS3U/Concepts/Watt.md", title: "Watt")
        let portfolios: URL = try write("courses/ICS3U/Portfolios/index.md", title: nil)
        let notesA: URL = try write("courses/ICS3U/Warm-Ups/Notes.md", title: "Notes")
        let notesB: URL = try write("courses/ICS3U/section1/Resources/My Notes.md", title: "notes ")
        let notesTop: URL = try write("courses/ICS3U/Notes Again.md", title: "Notes")
        let gone: URL = course.appendingPathComponent("Concepts/Gone Page.md")

        let names: [String] = StartOfYearPageNaming.names(
            ofFilesAt: [watt, portfolios, notesA, notesB, notesTop, gone],
            courseDirectoryURL: course, courseCode: "ICS3U"
        )
        XCTAssertEqual(names, [
            StartOfYearWording.pageName(page: "Watt"),
            StartOfYearWording.pageName(page: "Portfolios"),
            StartOfYearWording.pageNameInFolder(page: "Notes", folder: "Warm-Ups"),
            StartOfYearWording.pageNameInFolder(page: "notes", folder: "section1/Resources"),
            StartOfYearWording.pageNameInFolder(page: "Notes", folder: "ICS3U"),
            StartOfYearWording.pageName(page: "Gone Page"),
        ])
        for name in names {
            XCTAssertFalse(name.contains(".md") || name.contains("courses/"), name)
        }
    }

    /// Titles are compared as titles, not as link targets: "Input/Output"
    /// and "Output" are two titles (the graph's `normalized` would make them
    /// one), and a composed and a decomposed "Café" are one.
    func testTitlesAreComparedAsTitles() {
        XCTAssertEqual(StartOfYearPageNaming.titlesHeldByMoreThanOne(["Input/Output", "Output"]), [])
        let composed: String = "Caf\u{00E9}"
        let decomposed: String = "Cafe\u{0301}"
        XCTAssertEqual(StartOfYearPageNaming.titlesHeldByMoreThanOne([composed, decomposed]).count, 1)
        XCTAssertEqual(StartOfYearPageNaming.titlesHeldByMoreThanOne(["Notes", " notes", "Watt"]), ["notes"])
    }

    /// The folder is found from the URLs' components in one Unicode form, so
    /// a working folder stored decomposed on disk and typed composed still
    /// gives the folder within the course, not a path.
    func testTheFolderIsFoundWhateverFormTheWorkingFolderIsIn() {
        let composedCourse: URL = URL(fileURLWithPath: "/Users/t/Caf\u{00E9} Classes/courses/ICS3U")
        let decomposedPage: URL = URL(
            fileURLWithPath: "/Users/t/Cafe\u{0301} Classes/courses/ICS3U/Warm-Ups/Predict the Output.md"
        )
        XCTAssertEqual(
            StartOfYearPageNaming.folder(of: decomposedPage, courseDirectoryURL: composedCourse, courseCode: "ICS3U"),
            "Warm-Ups"
        )
    }

    /// The sheet builds its lines through the plan, the same builder
    /// `describe()` uses, and neither puts a path into a line: the risk is a
    /// fix in the MCP text that leaves the sheet printing paths.
    func testNeitherTheSheetNorThePlanBuildsALineFromAPath() throws {
        let appFolder: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers")
        let sheet: String = try String(
            contentsOf: appFolder.appendingPathComponent("Views/Section/StartOfYearSheet.swift"), encoding: .utf8
        )
        let planner: String = try String(
            contentsOf: appFolder.appendingPathComponent("Models/StartOfYear/StartOfYearPlanner.swift"),
            encoding: .utf8
        )
        for (fileName, text) in [("StartOfYearSheet.swift", sheet), ("StartOfYearPlanner.swift", planner)] {
            XCTAssertNil(
                text.range(of: #"\\\([^()]*relativePath\)"#, options: .regularExpression),
                "\(fileName) puts a page's path into the words it shows (#362)"
            )
            XCTAssertFalse(text.contains("relativePath(of:"), "\(fileName) shows a file's path (#362)")
        }
        // Positive controls: the lines come from the one builder.
        XCTAssertTrue(sheet.contains("plan.line(for: draft"), "The sheet should build its lines through the plan")
        XCTAssertTrue(sheet.contains("StartOfYearPageNaming.names("), "The undo should name by title")
        XCTAssertTrue(planner.contains("\"• \" + line(for: draft"), "describe() should use the plan's builder")
    }
}
