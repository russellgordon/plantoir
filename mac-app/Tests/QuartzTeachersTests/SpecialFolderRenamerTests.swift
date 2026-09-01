import XCTest
@testable import QuartzTeachers

/// Renaming a course folder: what is refused, what moves, and what the
/// configuration says afterwards.
///
/// Model tests only — the sheet that drives this is checked by hand, and the
/// rules below are the part that must not drift.
@MainActor
final class SpecialFolderRenamerTests: XCTestCase {

    // MARK: - Stored properties

    var temporaryDirectory: URL!

    // MARK: - Setup

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("renamer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    // MARK: - What a new name may not be

    func testAnEmptyNameIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "   ", existingNames: ["Tasks"], isTheClassFolder: false
            ),
            SpecialNames.renameFolderProblemEmpty
        )
    }

    func testTheSameNameIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Tasks", existingNames: ["Tasks"], isTheClassFolder: false
            ),
            SpecialNames.renameFolderProblemUnchanged
        )
    }

    func testASeparatorIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Work/Tasks", existingNames: ["Tasks"], isTheClassFolder: false
            ),
            SpecialNames.renameFolderProblemHasSeparator
        )
    }

    func testAHiddenNameIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: ".Tasks", existingNames: ["Tasks"], isTheClassFolder: false
            ),
            SpecialNames.renameFolderProblemIsHidden
        )
    }

    /// Plantoir links `Media` into every build itself, and the list editors
    /// already refuse it on ADD. Refusing it on rename too is what stops the
    /// same collision arriving by the back door.
    func testMediaIsRefusedInAnyCapitalisation() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "media", existingNames: ["Tasks"], isTheClassFolder: false
            ),
            SpecialNames.renameFolderProblemIsMedia
        )
    }

    func testASectionFolderNameIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "section3", existingNames: ["Tasks"], isTheClassFolder: false
            ),
            SpecialNames.renameFolderProblemLooksLikeASection(name: "section3")
        )
        XCTAssertNil(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Sections", existingNames: ["Tasks"], isTheClassFolder: false
            ),
            "\"Sections\" is an ordinary word, not the pattern Plantoir uses for a section folder"
        )
    }

    func testANameAlreadyInTheListIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "concepts",
                existingNames: ["Tasks", "Concepts"], isTheClassFolder: false
            ),
            SpecialNames.renameFolderProblemAlreadyUsed(name: "concepts"),
            "The filesystem is case-insensitive here, so the clash is real"
        )
    }

    /// The constraint that is not arbitrary: `ClassFolder` finds the class
    /// folder by looking for "class" in the name, so a rename that dropped the
    /// word would hand the curriculum map a different folder with nothing
    /// said.
    func testTheClassFolderMustKeepTheWordClass() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "All Classes", to: "Lessons",
                existingNames: ["All Classes"], isTheClassFolder: true
            ),
            SpecialNames.renameFolderProblemClassFolderMustSayClass
        )
        XCTAssertNil(
            SpecialFolderRenamer.problem(
                renaming: "All Classes", to: "Class Pages",
                existingNames: ["All Classes"], isTheClassFolder: true
            )
        )
        XCTAssertEqual(
            ClassFolder.name(inPerSectionFolders: ["Class Pages", "Tasks"]), "Class Pages",
            "The rule the refusal protects: this is why the word has to survive"
        )
    }

    /// The same name is fine on a folder that is not the class folder.
    func testAnOrdinaryFolderMayBeCalledLessons() {
        XCTAssertNil(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Lessons", existingNames: ["Tasks"], isTheClassFolder: false
            )
        )
    }

    // MARK: - Where a folder lives

    func testAPerSectionFolderLivesInEverySection() {
        let locations: [URL] = SpecialFolderRenamer.folderLocations(
            named: "Tasks", scope: .perSection,
            courseDirectory: URL(fileURLWithPath: "/courses/ICS3U"), sectionNumbers: [1, 4]
        )
        XCTAssertEqual(
            SpecialFolderRenamerTests.paths(of: locations),
            ["/courses/ICS3U/section1/Tasks", "/courses/ICS3U/section4/Tasks"]
        )
    }

    func testASharedFolderLivesBesideTheCourse() {
        let locations: [URL] = SpecialFolderRenamer.folderLocations(
            named: "Concepts", scope: .shared,
            courseDirectory: URL(fileURLWithPath: "/courses/ICS3U"), sectionNumbers: [1, 4]
        )
        XCTAssertEqual(SpecialFolderRenamerTests.paths(of: locations), ["/courses/ICS3U/Concepts"])
    }

    // MARK: - The move itself

    func testEverySectionsCopyMovesAndLinksFollow() throws {
        let course: URL = try makeCourse(sections: [1, 4], perSectionFolders: ["Tasks"])
        try "See [[Tasks/Quiz 1]] and [[Quiz 2]].".write(
            to: course.appendingPathComponent("section1/index.md"), atomically: true, encoding: .utf8
        )

        let outcome: FolderRenameOutcome = try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection,
            courseDirectory: course, sectionNumbers: [1, 4]
        )

        XCTAssertEqual(outcome.foldersMoved, 2)
        XCTAssertEqual(outcome.pagesRelinked, 1)
        XCTAssertTrue(exists(course.appendingPathComponent("section1/Assessments")))
        XCTAssertTrue(exists(course.appendingPathComponent("section4/Assessments")))
        XCTAssertFalse(exists(course.appendingPathComponent("section1/Tasks")))
        XCTAssertEqual(
            try String(contentsOf: course.appendingPathComponent("section1/index.md"), encoding: .utf8),
            "See [[Assessments/Quiz 1]] and [[Quiz 2]]."
        )
    }

    /// A section a teacher never filled in may not have the folder at all, and
    /// that is not a failure — it is counted rather than complained about.
    func testASectionWithoutTheFolderIsSkipped() throws {
        let course: URL = try makeCourse(sections: [1, 4], perSectionFolders: ["Tasks"])
        try FileManager.default.removeItem(at: course.appendingPathComponent("section4/Tasks"))

        let outcome: FolderRenameOutcome = try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection,
            courseDirectory: course, sectionNumbers: [1, 4]
        )

        XCTAssertEqual(outcome.foldersMoved, 1)
        XCTAssertTrue(exists(course.appendingPathComponent("section1/Assessments")))
    }

    /// Nothing moves until every destination has been checked, so a
    /// per-section rename cannot get half way through and stop.
    func testNothingMovesWhenOneSectionAlreadyHasThatName() throws {
        let course: URL = try makeCourse(sections: [1, 4], perSectionFolders: ["Tasks"])
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section4/Assessments"), withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try SpecialFolderRenamer.rename(
                "Tasks", to: "Assessments", scope: .perSection,
                courseDirectory: course, sectionNumbers: [1, 4]
            )
        ) { error in
            XCTAssertEqual(
                (error as? FolderRenameProblem)?.sentence,
                SpecialNames.renameFolderProblemDestinationExists(name: "Assessments")
            )
        }
        XCTAssertTrue(
            exists(course.appendingPathComponent("section1/Tasks")),
            "Section 1 must be untouched — a rename that half happened is worse than one that did not"
        )
    }

    /// A Mac's volume is case-insensitive, so "rename Tasks to tasks" asks the
    /// filesystem to move a folder onto itself. Refusing it as "already there"
    /// would refuse a perfectly reasonable rename.
    func testChangingOnlyCapitalisationIsAllowed() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["Tasks"])
        let outcome: FolderRenameOutcome = try SpecialFolderRenamer.rename(
            "Tasks", to: "TASKS", scope: .perSection, courseDirectory: course, sectionNumbers: [1]
        )
        XCTAssertEqual(outcome.foldersMoved, 1)
    }

    /// The build's own output is a second copy of the whole course; rewriting
    /// links in it would be pointless and slow, and it is thrown away and
    /// rebuilt anyway.
    func testTheBuildsOwnOutputIsNotRewritten() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["Tasks"])
        let generated: URL = course.appendingPathComponent(".merged_output/section1")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        let generatedPage: URL = generated.appendingPathComponent("index.md")
        try "[[Tasks/Quiz 1]]".write(to: generatedPage, atomically: true, encoding: .utf8)

        _ = try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1]
        )

        XCTAssertEqual(try String(contentsOf: generatedPage, encoding: .utf8), "[[Tasks/Quiz 1]]")
    }

    // MARK: - What the configuration says afterwards

    func testEveryKeyThatNamedTheFolderIsCarriedAcross() {
        let values: [String: Any] = [
            "per_section_folders": ["All Classes", "Tasks"],
            "shared_folders": ["Concepts", "Tasks"],
            "graded_folders": ["Tasks"],
            "curriculum_folder": "Ontario Curriculum",
            "excluded_items": ["per_section": ["Tasks"], "shared": ["Discussions"]],
        ]

        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "Tasks", to: "Assessments", scope: .perSection, in: values
        )

        XCTAssertEqual(updated["per_section_folders"] as? [String], ["All Classes", "Assessments"])
        XCTAssertEqual(
            updated["shared_folders"] as? [String], ["Concepts", "Tasks"],
            "A shared folder of the same name is a different folder on disk and must not move"
        )
        XCTAssertEqual(updated["graded_folders"] as? [String], ["Assessments"])
        XCTAssertEqual(updated["curriculum_folder"] as? String, "Ontario Curriculum")
        let excluded: [String: Any] = updated["excluded_items"] as? [String: Any] ?? [:]
        XCTAssertEqual(excluded["per_section"] as? [String], ["Assessments"])
        XCTAssertEqual(excluded["shared"] as? [String], ["Discussions"])
    }

    func testRenamingTheCurriculumFolderMovesTheKeyThatNamesIt() {
        let values: [String: Any] = [
            "shared_folders": ["Ontario Curriculum", "Concepts"],
            "curriculum_folder": "Ontario Curriculum",
        ]
        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "Ontario Curriculum", to: "Expectations", scope: .shared, in: values
        )
        XCTAssertEqual(updated["shared_folders"] as? [String], ["Expectations", "Concepts"])
        XCTAssertEqual(updated["curriculum_folder"] as? String, "Expectations")
    }

    /// A key the course does not have must not be invented — an absent
    /// `graded_folders` means "never asked", which is a different course from
    /// one whose pool is empty.
    func testAbsentKeysStayAbsent() {
        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "Tasks", to: "Assessments", scope: .perSection,
            in: ["per_section_folders": ["Tasks"]]
        )
        XCTAssertNil(updated["graded_folders"])
        XCTAssertNil(updated["curriculum_folder"])
        XCTAssertNil(updated["excluded_items"])
    }

    // MARK: - Helpers

    private func makeCourse(sections: [Int], perSectionFolders: [String]) throws -> URL {
        let course: URL = temporaryDirectory.appendingPathComponent("ICS3U")
        for number in sections {
            for folder in perSectionFolders {
                try FileManager.default.createDirectory(
                    at: course.appendingPathComponent("section\(number)/\(folder)"),
                    withIntermediateDirectories: true
                )
            }
        }
        return course
    }

    private static func paths(of urls: [URL]) -> [String] {
        var result: [String] = []
        for url in urls {
            result.append(url.path)
        }
        return result
    }

    private func exists(_ url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
}
