import XCTest
@testable import QuartzTeachers

/// Renaming a course's word for a unit after the course is in use — against
/// real files, because the whole point of the piece is what happens on disk.
@MainActor
final class UnitWordRenamerTests: XCTestCase {

    // MARK: - Fixture

    /// A two-section course, a shared page that links at class pages, and a
    /// page that is nobody's class.
    func makeCourse(word: String? = nil) throws -> (course: Course, coursesURL: URL) {
        let coursesURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unit-word-\(UUID().uuidString)")
            .appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")
        for section in [1, 2] {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent("section\(section)/All Classes"),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("Concepts"), withIntermediateDirectories: true
        )
        var configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "per_section_folders": ["All Classes"],
            "shared_folders": ["Concepts"],
            "per_section_files": [],
        ]
        if let word {
            configuration["unit_word"] = word
        }
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)

        let term: String = word ?? "Unit"
        try writeClass("\(term) 1, Day 1", section: 1, in: course)
        try writeClass("\(term) 1, Day 2", section: 1, in: course)
        try writeClass("Field Trip", section: 1, in: course)
        try writeClass("\(term) 2, Day 1", section: 2, in: course)
        try """
        ---
        title: All Classes
        ---
        Start at [[\(term) 1, Day 1|the first day]], then ![[\(term) 1, Day 2#Agenda]].
        By the end of \(term) 3 you will have met [[\(term) 2, Day 1]].
        """.write(
            to: courseURL.appendingPathComponent("section1/All Classes/index.md"),
            atomically: true, encoding: .utf8
        )
        try """
        ---
        title: Loops
        ---
        Taught in [[\(term) 1, Day 2]]. See also [[\(term) 2 Test]].
        """.write(
            to: courseURL.appendingPathComponent("Concepts/Loops.md"),
            atomically: true, encoding: .utf8
        )
        return (course: course, coursesURL: coursesURL)
    }

    func writeClass(_ title: String, section: Int, in course: Course) throws {
        let page: String = """
        ---
        title: \(title)
        publish: true
        created: 2026-09-08T07:00:00.000-0400
        ---

        \(title)
        """
        try page.write(
            to: ClassPages.folderURL(forSection: section, in: course).appendingPathComponent(title + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    func text(of relativePath: String, in course: Course) -> String? {
        return try? String(contentsOf: course.directoryURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func exists(_ relativePath: String, in course: Course) -> Bool {
        return FileManager.default.fileExists(atPath: course.directoryURL.appendingPathComponent(relativePath).path)
    }

    func backups(in coursesURL: URL) -> [URL] {
        let folder: URL = coursesURL.appendingPathComponent("_backups/ICS3U")
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    // MARK: - What a word may not be

    func testTheIdenticalWordIsUnchangedButACapitalisationChangeIsNot() {
        XCTAssertEqual(UnitWordRenamer.problem(renaming: "Unit", to: "Unit"), UnitWordRenameWording.problemUnchanged)
        XCTAssertEqual(UnitWordRenamer.problem(renaming: "Unit", to: " Unit "), UnitWordRenameWording.problemUnchanged)
        XCTAssertNil(UnitWordRenamer.problem(renaming: "Unit", to: "unit"))
        XCTAssertEqual(UnitWordRenamer.problem(renaming: "Unit", to: "  "), UnitWordRenameWording.problemEmpty)
        XCTAssertNotNil(UnitWordRenamer.problem(renaming: "Unit", to: "Module2"))
        XCTAssertNotNil(UnitWordRenamer.problem(renaming: "Unit", to: "Mod,ule"))
        XCTAssertNil(UnitWordRenamer.problem(renaming: "Unit", to: "Module"))
    }

    // MARK: - The plan

    func testThePlanCountsPagesSectionsAndLinksAndLeavesOtherPagesAlone() throws {
        let (course, root) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let plan: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Unit", to: "Module", in: course)
        XCTAssertTrue(plan.canProceed)
        XCTAssertEqual(plan.renames.count, 3)
        XCTAssertEqual(plan.sectionsTouched, [1, 2])
        // Four links point at class pages: the alias, the transclusion, the
        // plain one on the index, and the one on the shared Concepts page.
        // "[[Unit 2 Test]]" is not a class page and does not count.
        XCTAssertEqual(plan.linksToRewrite, 4)
        var froms: [String] = []
        for rename in plan.renames {
            froms.append(rename.from)
        }
        XCTAssertFalse(froms.contains("Field Trip"))
        XCTAssertFalse(froms.contains("index"))
        XCTAssertEqual(
            plan.previewLines[0],
            UnitWordRenameWording.previewPages(courseCode: "ICS3U", pages: 3, sections: [1, 2], old: "Unit", new: "Module")
        )
    }

    // MARK: - Carrying it out

    func testRenamingMovesRetitlesRelinksBacksUpAndRecords() throws {
        let (course, root) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let plan: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Unit", to: "Module", in: course)
        let outcome: UnitWordRenameOutcome = try UnitWordRenamer.rename(plan, in: course, coursesDirectoryURL: root)
        try UnitWordRenamer.record(plan, in: course)

        XCTAssertEqual(outcome.pagesRenamed, 3)
        XCTAssertEqual(outcome.linksRewritten, 4)
        XCTAssertTrue(exists("section1/All Classes/Module 1, Day 1.md", in: course))
        XCTAssertTrue(exists("section1/All Classes/Module 1, Day 2.md", in: course))
        XCTAssertTrue(exists("section2/All Classes/Module 2, Day 1.md", in: course))
        XCTAssertFalse(exists("section1/All Classes/Unit 1, Day 1.md", in: course))
        XCTAssertTrue(exists("section1/All Classes/Field Trip.md", in: course))

        // The title inside follows the file name.
        let page: String = try XCTUnwrap(text(of: "section1/All Classes/Module 1, Day 1.md", in: course))
        XCTAssertTrue(page.hasPrefix("---\ntitle: Module 1, Day 1\n"), page)

        // Links follow; the alias, the heading and the prose do not change.
        let index: String = try XCTUnwrap(text(of: "section1/All Classes/index.md", in: course))
        XCTAssertTrue(index.contains("[[Module 1, Day 1|the first day]]"), index)
        XCTAssertTrue(index.contains("![[Module 1, Day 2#Agenda]]"), index)
        XCTAssertTrue(index.contains("By the end of Unit 3"), "Prose is the teacher's own and is left alone")
        let shared: String = try XCTUnwrap(text(of: "Concepts/Loops.md", in: course))
        XCTAssertTrue(shared.contains("[[Module 1, Day 2]]"), "A SHARED page's link follows too")
        XCTAssertTrue(shared.contains("[[Unit 2 Test]]"), "A link to a page that is not a class page is left alone")

        // The way back, and the record.
        XCTAssertEqual(backups(in: root).count, 1)
        XCTAssertEqual(outcome.backupURL.lastPathComponent, backups(in: root)[0].lastPathComponent)
        let onDisk: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: course.configFileURL)) as? [String: Any]
        )
        XCTAssertEqual(onDisk["unit_word"] as? String, "Module")
        XCTAssertEqual(course.configuration.unitWord, "Module", "The in-memory configuration follows the disk")
        XCTAssertFalse(course.configuration.hasUnsavedChanges)
        XCTAssertNil(UnitWordRenamer.interruptedRenameTarget(in: course), "The record is cleared once the settings are written")

        // And the course reads back as a Module course.
        let listed: [ClassPageSummary] = ClassPages.list(forSection: 1, in: course)
        var numbered: Int = 0
        for summary in listed where summary.unitAndDay != nil {
            numbered += 1
        }
        XCTAssertEqual(numbered, 2)
    }

    /// The operation is its own inverse — which is the undo.
    func testRenamingBackPutsEverythingAsItWas() throws {
        let (course, root) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let before: String = try XCTUnwrap(text(of: "section1/All Classes/index.md", in: course))

        let there: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Unit", to: "Module", in: course)
        try UnitWordRenamer.rename(there, in: course, coursesDirectoryURL: root)
        try UnitWordRenamer.record(there, in: course)
        let back: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Module", to: "Unit", in: course)
        let outcome: UnitWordRenameOutcome = try UnitWordRenamer.rename(back, in: course, coursesDirectoryURL: root)
        try UnitWordRenamer.record(back, in: course)

        XCTAssertEqual(outcome.pagesRenamed, 3)
        XCTAssertTrue(exists("section1/All Classes/Unit 1, Day 1.md", in: course))
        XCTAssertEqual(text(of: "section1/All Classes/index.md", in: course), before)
        XCTAssertEqual(course.configuration.unitWord, "Unit")
    }

    func testAChangeOfCapitalisationAloneIsCarriedOut() throws {
        let (course, root) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let plan: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Unit", to: "unit", in: course)
        XCTAssertTrue(plan.canProceed, plan.problems.joined(separator: " "))
        XCTAssertEqual(plan.renames.count, 3)
        let outcome: UnitWordRenameOutcome = try UnitWordRenamer.rename(plan, in: course, coursesDirectoryURL: root)
        try UnitWordRenamer.record(plan, in: course)
        XCTAssertEqual(outcome.pagesRenamed, 3)

        let listed: [URL] = try FileManager.default.contentsOfDirectory(
            at: course.directoryURL.appendingPathComponent("section1/All Classes"), includingPropertiesForKeys: nil
        )
        var names: [String] = []
        for url in listed {
            names.append(url.lastPathComponent)
        }
        names.sort()
        XCTAssertEqual(names, ["Field Trip.md", "index.md", "unit 1, Day 1.md", "unit 1, Day 2.md"])
        XCTAssertEqual(course.configuration.unitWord, "unit")
        let page: String = try XCTUnwrap(text(of: "section1/All Classes/unit 1, Day 1.md", in: course))
        XCTAssertTrue(page.hasPrefix("---\ntitle: unit 1, Day 1\n"), page)
    }

    // MARK: - What refuses it

    func testAPageAlreadyInTheWayRefusesTheWholeRenameAndTouchesNothing() throws {
        let (course, root) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try writeClass("Module 1, Day 2", section: 1, in: course)

        let plan: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Unit", to: "Module", in: course)
        XCTAssertFalse(plan.canProceed)
        XCTAssertTrue(plan.renames.isEmpty, "A refused plan lists no renames, so it cannot be carried out by accident")
        XCTAssertEqual(
            plan.problems,
            [UnitWordRenameWording.problemPageInTheWay(courseCode: "ICS3U", sectionNumber: 1, name: "Module 1, Day 2")]
        )
        XCTAssertThrowsError(try UnitWordRenamer.rename(plan, in: course, coursesDirectoryURL: root))
        XCTAssertTrue(exists("section1/All Classes/Unit 1, Day 1.md", in: course))
        XCTAssertEqual(backups(in: root).count, 0, "Nothing was backed up because nothing was about to change")
        XCTAssertNil(UnitWordRenamer.interruptedRenameTarget(in: course))
    }

    func testAPageThatCannotBeReadRefusesEverythingBeforeAnythingMoves() throws {
        let (course, root) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let locked: URL = course.directoryURL.appendingPathComponent("section2/All Classes/Unit 2, Day 1.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let plan: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Unit", to: "Module", in: course)
        XCTAssertTrue(plan.canProceed)
        XCTAssertThrowsError(try UnitWordRenamer.rename(plan, in: course, coursesDirectoryURL: root)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                UnitWordRenameWording.problemPageUnreadable(courseCode: "ICS3U", sectionNumber: 2, name: "Unit 2, Day 1")
            )
        }
        XCTAssertTrue(exists("section1/All Classes/Unit 1, Day 1.md", in: course), "Section 1 was not renamed while section 2 could not be")
        XCTAssertEqual(backups(in: root).count, 0)
        XCTAssertEqual(course.configuration.unitWord, "Unit")
    }

    // MARK: - A course with nothing to rename

    func testACourseWithNoClassPagesOnlyChangesItsSettings() throws {
        let (course, root) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        for name in ["section1/All Classes/Unit 1, Day 1.md", "section1/All Classes/Unit 1, Day 2.md", "section2/All Classes/Unit 2, Day 1.md"] {
            try FileManager.default.removeItem(at: course.directoryURL.appendingPathComponent(name))
        }

        let plan: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Unit", to: "Module", in: course)
        XCTAssertTrue(plan.canProceed)
        XCTAssertEqual(plan.renames.count, 0)
        XCTAssertEqual(plan.previewLines.count, 1)
        let outcome: UnitWordRenameOutcome = try UnitWordRenamer.rename(plan, in: course, coursesDirectoryURL: root)
        try UnitWordRenamer.record(plan, in: course)
        XCTAssertEqual(outcome.pagesRenamed, 0)
        XCTAssertEqual(course.configuration.unitWord, "Module")
        XCTAssertEqual(
            UnitWordRenameWording.doneSentence(from: "Unit", to: "Module", pages: 0, links: 0),
            UnitWordRenameWording.done(from: "Unit", to: "Module") + " " + UnitWordRenameWording.donePagesNone
            + " " + UnitWordRenameWording.doneBackup
        )
    }

    // MARK: - A rename that stopped part way

    func testAnInterruptedRenameIsRecognisedAndFinishedByRunningItAgain() throws {
        let (course, root) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        // As if the first page had moved and then the app quit: the record is
        // there, one page is under the new word, the settings say the old one
        // and a link still points at the old name.
        UnitWordRenamer.recordRenameStarting(from: "Unit", to: "Module", courseDirectory: course.directoryURL)
        try FileManager.default.moveItem(
            at: course.directoryURL.appendingPathComponent("section1/All Classes/Unit 1, Day 1.md"),
            to: course.directoryURL.appendingPathComponent("section1/All Classes/Module 1, Day 1.md")
        )
        XCTAssertEqual(UnitWordRenamer.interruptedRenameTarget(in: course), "Module")

        let plan: UnitWordRenamePlan = UnitWordRenamer.plan(from: "Unit", to: "Module", in: course)
        XCTAssertTrue(plan.canProceed)
        XCTAssertEqual(plan.renames.count, 2, "The page already moved is not planned again")
        XCTAssertEqual(plan.linkMap["Unit 1, Day 1"], "Module 1, Day 1", "…but links to its old name are still followed")
        XCTAssertEqual(plan.linksToRewrite, 4)

        let outcome: UnitWordRenameOutcome = try UnitWordRenamer.rename(plan, in: course, coursesDirectoryURL: root)
        try UnitWordRenamer.record(plan, in: course)
        XCTAssertEqual(outcome.pagesRenamed, 2)
        XCTAssertEqual(outcome.linksRewritten, 4)
        let index: String = try XCTUnwrap(text(of: "section1/All Classes/index.md", in: course))
        XCTAssertTrue(index.contains("[[Module 1, Day 1|the first day]]"), index)
        XCTAssertEqual(course.configuration.unitWord, "Module")
        XCTAssertNil(UnitWordRenamer.interruptedRenameTarget(in: course))
    }

    func testAStaleRecordIsClearedRatherThanBelieved() throws {
        let (course, root) = try makeCourse(word: "Module")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        // The settings were written and only the clearing failed.
        UnitWordRenamer.recordRenameStarting(from: "Unit", to: "Module", courseDirectory: course.directoryURL)
        XCTAssertNil(UnitWordRenamer.interruptedRenameTarget(in: course))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: UnitWordRenamer.renameMarkerURL(courseDirectory: course.directoryURL).path
        ))
    }
}
