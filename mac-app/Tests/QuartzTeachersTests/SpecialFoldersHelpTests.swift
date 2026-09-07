import XCTest
@testable import QuartzTeachers

/// The in-app explanation of which folders Plantoir uses, driven from
/// `contracts/shared-rules.json` → `specialFoldersHelp` rather than retyped
/// here.
///
/// Two properties matter and neither is obvious from reading the view: it must
/// name the folders THIS course has rather than the rule that finds them, and
/// it must not describe the machinery. Both are contract keys, so a change to
/// either fails a test on BOTH platforms instead of drifting on one — the
/// Windows half is `SpecialFoldersHelpContractTests.cs`.
///
/// This file used to retype the sentences and invent its own cases. It could
/// not have caught what was actually wrong: its fixture always recorded a
/// `curriculum_folder`, so the branch that showed a teacher the placeholder
/// never ran once in a test.
@MainActor
final class SpecialFoldersHelpTests: XCTestCase {

    // MARK: - Functions

    /// A course built from a contract case's own inputs.
    ///
    /// `graded_folders` and `curriculum_folder` are written only when the case
    /// gives one, because an ABSENT key and an EMPTY list mean different
    /// things — see `gradedFolders.absentIsNotEmpty`, and the cases here that
    /// turn on exactly that. A JSON `null` arrives as `NSNull`, which the
    /// `as?` casts below read as nil, so "never recorded" simply writes no key.
    private func makeCourse(from figure: [String: Any]) throws -> (URL, Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folders-help-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)

        var configuration: [String: Any] = [
            "course_code": "ICS3U", "course_name": "Introduction to Computer Science",
            "section_numbers": [1], "num_sections": 1,
            "shared_folders": figure["sharedFolders"] as? [String] ?? [],
            "per_section_folders": figure["perSectionFolders"] as? [String] ?? [],
            "shared_files": [], "per_section_files": [],
        ]
        if let graded = figure["gradedFolders"] as? [String] {
            configuration["graded_folders"] = graded
        }
        if let curriculum = figure["curriculumFolder"] as? String {
            configuration["curriculum_folder"] = curriculum
        }

        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: configURL)
        return (root, Course(
            code: "ICS3U", directoryURL: courseURL,
            configuration: try CourseConfiguration(contentsOf: configURL)
        ))
    }

    /// The row a case is talking about, found by the contract's own `key`
    /// rather than by a position typed in here. A hard-coded index would go on
    /// passing after a row was inserted above it, testing the wrong row and
    /// saying nothing — which is the failure this whole file exists to catch.
    ///
    /// **Bounds-checked on purpose.** The whole point of this file is that a
    /// row Windows adds to the contract makes the mac suite go red until the
    /// mac builds it — and a Swift array subscript out of range is a fatal
    /// error, not a test failure. It would kill the test host, abandon the run
    /// and hide every other result, which reads as a broken machine rather
    /// than as the request it is.
    private func name(ofRow key: String, in course: Course) throws -> String {
        let rows: [[String: Any]] = try SpecialFoldersHelpTests.rows()
        let entries: [SpecialFolderEntry] = SpecialFoldersHelpView(course: course).entries
        for index in rows.indices {
            if rows[index]["key"] as? String == key {
                guard index < entries.count else {
                    XCTFail("the contract lists a row “\(key)” the sheet does not build")
                    return ""
                }
                return entries[index].name
            }
        }
        XCTFail("a case names a row the contract does not list: \(key)")
        return ""
    }

    // MARK: - The names a course is shown

    /// Every case in the contract, run against this app's own sheet.
    func testTheSheetNamesEachCoursesOwnFolders() throws {
        let section: [String: Any] = try SpecialFoldersHelpTests.section()
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(
            cases.count, 6,
            "the specialFoldersHelp case list has lost cases; two of them are the only "
                + "gate on naming the RESOLVED curriculum folder"
        )

        for figure in cases {
            let name: String = try XCTUnwrap(figure["name"] as? String)
            let (root, course) = try makeCourse(from: figure)
            defer { try? FileManager.default.removeItem(at: root) }

            let expected: [String: Any] = try XCTUnwrap(figure["expectNames"] as? [String: Any])
            for (key, value) in expected {
                XCTAssertEqual(
                    try self.name(ofRow: key, in: course), value as? String,
                    "case “\(name)”, row “\(key)”"
                )
            }

            // Scoped to the row NAMES, and compared as written: the contract's
            // own rule excludes a folder's name from the jargon sweep for the
            // opposite reason, and a case banning "Expectations" would fire
            // spuriously against the curriculum row's "Your curriculum
            // expectations" if this looked at the explanations too.
            if let banned = figure["mustNotAppear"] as? [String] {
                var shown: String = ""
                for entry in SpecialFoldersHelpView(course: course).entries {
                    shown += entry.name + " "
                }
                for word in banned {
                    XCTAssertFalse(
                        shown.contains(word),
                        "case “\(name)”: the sheet names “\(word)”, which this course "
                            + "does not have"
                    )
                }
            }
        }
    }

    // MARK: - The rows themselves

    /// Every row's explanation, in the contract's order. The sentences a
    /// teacher reads are the contract's, character for character.
    func testTheRowsAreTheContractsRowsInTheContractsOrder() throws {
        let rows: [[String: Any]] = try SpecialFoldersHelpTests.rows()
        let (root, course) = try makeCourse(from: [
            "perSectionFolders": ["All Classes"],
            "sharedFolders": ["Concepts", "Tasks", "Ontario Curriculum"],
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let entries: [SpecialFolderEntry] = SpecialFoldersHelpView(course: course).entries
        // Asserted AND enforced: a mismatch has to stop the loop below, or the
        // subscript traps and takes the whole run down with it rather than
        // failing this one test.
        XCTAssertEqual(entries.count, rows.count,
                       "no row is ever omitted — see rowsAreOrdered")
        guard entries.count == rows.count else {
            return
        }

        for index in rows.indices {
            let row: [String: Any] = rows[index]
            let key: String = try XCTUnwrap(row["key"] as? String)
            XCTAssertEqual(entries[index].what, row["what"] as? String, "row “\(key)”")
            XCTAssertEqual(entries[index].why, row["why"] as? String, "row “\(key)”")
            // A fixed row's name is the contract's; a course-named row's is
            // not, and asserting it here would only restate the cases above.
            if row["namedFrom"] as? String == "fixed" {
                XCTAssertEqual(entries[index].name, row["name"] as? String, "row “\(key)”")
            }
        }
    }

    /// The sentences that are not rows: the button that opens the sheet, its
    /// title, the line under it, the button that closes it, and the one name
    /// the product writes for itself.
    func testTheTitleAndIntroAreTheContractsOwn() throws {
        let section: [String: Any] = try SpecialFoldersHelpTests.section()
        XCTAssertEqual(SpecialFoldersHelpView.title, section["title"] as? String)
        XCTAssertEqual(SpecialFoldersHelpView.intro, section["intro"] as? String)
        XCTAssertEqual(SpecialFoldersHelpView.openedBy, section["openedBy"] as? String)
        XCTAssertEqual(SpecialFoldersHelpView.dismissedBy, section["dismissedBy"] as? String)

        // Found by key, not by position — the same trap as name(ofRow:in:).
        var checked: Bool = false
        for row in try SpecialFoldersHelpTests.rows() where row["key"] as? String == "curriculum" {
            XCTAssertEqual(
                SpecialFoldersHelpView.noCurriculumFolderYet,
                row["placeholderWhenNone"] as? String
            )
            checked = true
        }
        XCTAssertTrue(checked, "the contract lists no curriculum row to take the placeholder from")
    }

    // MARK: - How several names are said

    func testSeveralFoldersAreListedTheWayAPersonWouldSayThem() throws {
        let section: [String: Any] = try SpecialFoldersHelpTests.section()
        let listing: [String: Any] = try XCTUnwrap(section["listing"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(listing["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)

        for figure in cases {
            let names: [String] = try XCTUnwrap(figure["names"] as? [String])
            XCTAssertEqual(
                SpecialFoldersHelpView.listed(names), figure["expect"] as? String,
                "listing \(names)"
            )
        }
    }

    // MARK: - Rule 1

    /// The banned list carries "substring", "segment" and "case-insensitive"
    /// alongside "container", because publishing the matching rule in words is
    /// the same mistake as printing it in a row, by another route.
    ///
    /// **Scoped to the text the PRODUCT writes** — the title, the intro, both
    /// button labels, every row's what and why, and the row names Plantoir
    /// supplies ITSELF: the placeholder, "None chosen", and the four rows the
    /// contract marks `namedFrom: "fixed"`. A teacher's own folder called
    /// "Scripts" is their word shown back to them, not a wording bug, and
    /// sweeping the course's folder names would make it one — which is the
    /// only reason a name is ever left out.
    func testItNamesNoMachineryAndPublishesNoMatchingRule() throws {
        let section: [String: Any] = try SpecialFoldersHelpTests.section()
        let noMachinery: [String: Any] = try XCTUnwrap(section["saysNoMachinery"] as? [String: Any])
        let jargon: [String] = try XCTUnwrap(noMachinery["jargon"] as? [String])
        let rows: [[String: Any]] = try SpecialFoldersHelpTests.rows()

        // A course with no curriculum folder, so the placeholder branch — the
        // one that carried the offending sentence and never ran in a test —
        // is the branch being read here.
        let (root, course) = try makeCourse(from: [
            "perSectionFolders": ["All Classes"],
            "sharedFolders": ["Concepts", "Tasks"],
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var shown: String = SpecialFoldersHelpView.title + " "
            + SpecialFoldersHelpView.intro + " "
            + SpecialFoldersHelpView.openedBy + " "
            + SpecialFoldersHelpView.dismissedBy + " "
            + SpecialFoldersHelpView.noCurriculumFolderYet + " "
            + SpecialFoldersHelpView.noneChosen + " "
        let entries: [SpecialFolderEntry] = SpecialFoldersHelpView(course: course).entries
        for index in entries.indices {
            shown += entries[index].what + " " + entries[index].why + " "
            if index < rows.count, rows[index]["namedFrom"] as? String == "fixed" {
                shown += entries[index].name + " "
            }
        }
        let lowercased: String = shown.lowercased()

        for word in jargon {
            XCTAssertFalse(lowercased.contains(word.lowercased()),
                           "the folders help says “\(word)” to a teacher")
        }
    }

    // MARK: - Reading the contract

    private static func section() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["specialFoldersHelp"] as? [String: Any],
                             "No specialFoldersHelp in shared-rules.json")
    }

    private static func rows() throws -> [[String: Any]] {
        return try XCTUnwrap(try section()["rows"] as? [[String: Any]])
    }
}
