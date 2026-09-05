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
                renaming: "Tasks", to: "   ", existingNames: ["Tasks"]
            ),
            SpecialNames.renameFolderProblemEmpty
        )
    }

    func testTheSameNameIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Tasks", existingNames: ["Tasks"]
            ),
            SpecialNames.renameFolderProblemUnchanged
        )
    }

    func testASeparatorIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Work/Tasks", existingNames: ["Tasks"]
            ),
            SpecialNames.renameFolderProblemHasSeparator
        )
    }

    func testAHiddenNameIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: ".Tasks", existingNames: ["Tasks"]
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
                renaming: "Tasks", to: "media", existingNames: ["Tasks"]
            ),
            SpecialNames.renameFolderProblemIsMedia
        )
    }

    func testASectionFolderNameIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "section3", existingNames: ["Tasks"]
            ),
            SpecialNames.renameFolderProblemLooksLikeASection(name: "section3")
        )
        XCTAssertNil(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Sections", existingNames: ["Tasks"]
            ),
            "\"Sections\" is an ordinary word, not the pattern Plantoir uses for a section folder"
        )
    }

    func testANameAlreadyInTheListIsRefused() {
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "concepts",
                existingNames: ["Tasks", "Concepts"]
            ),
            SpecialNames.renameFolderProblemAlreadyUsed(name: "concepts"),
            "The filesystem is case-insensitive here, so the clash is real"
        )
    }

    /// **A refusal that was deleted the day after it shipped, and the test is
    /// kept pointing the other way.** The class folder briefly had to keep the
    /// word "class" in its name, because `ClassFolder` found it by looking for
    /// that word. Russell's point (2026-09-01): that was Plantoir's vocabulary
    /// imposed on a teacher's — somebody who says "Thread 2, Day 3" would
    /// sensibly call the folder "All Days". The lookup was the thing at fault,
    /// and it was fixed instead.
    func testTheClassFolderMayBeCalledAnything() {
        XCTAssertNil(
            SpecialFolderRenamer.problem(
                renaming: "All Classes", to: "All Days", existingNames: ["All Classes"]
            )
        )
    }

    func testAnOrdinaryFolderMayBeCalledLessons() {
        XCTAssertNil(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Lessons", existingNames: ["Tasks"]
            )
        )
    }

    // MARK: - Recording which folder was which

    /// The heart of what replaced the refusal: renaming the class folder
    /// WRITES `class_folder`, so the answer no longer depends on the word.
    func testRenamingTheClassFolderRecordsIt() {
        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "All Classes", to: "All Days", scope: .perSection,
            in: ["per_section_folders": ["All Classes", "Tasks"]]
        )
        XCTAssertEqual(updated["class_folder"] as? String, "All Days")
        XCTAssertEqual(updated["per_section_folders"] as? [String], ["All Days", "Tasks"])
        XCTAssertEqual(
            ClassFolder.name(
                inPerSectionFolders: updated["per_section_folders"] as? [String] ?? [],
                configured: updated["class_folder"] as? String
            ),
            "All Days",
            "Without the recorded key this course's class pages would go to Tasks"
        )
    }

    /// Found by adversarial review: the same trap, unguarded, one folder over.
    /// A course made from scratch has `curriculum_folder: null`, so renaming
    /// `Curriculum` used to leave the map built from nothing with nobody told.
    func testRenamingTheCurriculumFolderRecordsItEvenWhenTheKeyWasNull() {
        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "Curriculum", to: "Expectations", scope: .shared,
            in: [
                "shared_folders": ["Curriculum", "Concepts"],
                "curriculum_folder": NSNull(),
            ]
        )
        XCTAssertEqual(updated["curriculum_folder"] as? String, "Expectations")
    }

    /// **The over-reach found by adversarial review.** `ClassFolder.name`
    /// always answers something, falling back to the FIRST per-section folder
    /// so a course is never without an answer. Freezing that guess of
    /// convenience into the configuration would make an unrelated rename
    /// decide, permanently, which folder holds class pages — after which a
    /// real "All Classes" added later would never take over, and the renamed
    /// folder could no longer be removed.
    func testRenamingAnOrdinaryFolderInACourseWithNoClassFolderRecordsNothing() {
        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "Tasks", to: "Assessments", scope: .perSection,
            in: ["per_section_folders": ["Tasks", "Homework"]]
        )
        XCTAssertNil(
            updated["class_folder"],
            "\"Tasks\" was only the class folder by being first in the list"
        )
    }

    /// The other half of the same rule: a course that HAS recorded one gets it
    /// carried across whatever the folder is called.
    func testARecordedClassFolderIsCarriedAcrossEvenWithoutTheWordClass() {
        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "All Days", to: "Every Day", scope: .perSection,
            in: ["per_section_folders": ["All Days", "Tasks"], "class_folder": "All Days"]
        )
        XCTAssertEqual(updated["class_folder"] as? String, "Every Day")
    }

    /// Renaming something ELSE must not invent either key — an absent key is a
    /// course that has never said, and saying for it is its own kind of wrong.
    func testRenamingAnOrdinaryFolderRecordsNothingExtra() {
        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "Tasks", to: "Assessments", scope: .perSection,
            in: ["per_section_folders": ["All Classes", "Tasks"]]
        )
        XCTAssertNil(updated["class_folder"])
        XCTAssertNil(updated["curriculum_folder"])
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

    // MARK: - Finishing a rename that was interrupted

    /// **The dead end this exists to open.** A rename moves the folders, then
    /// rewrites links, then writes the configuration. Interrupted after the
    /// move, the folders are under the new name and the configuration still
    /// says the old one — and the next build DISCOVERS the new folder and
    /// appends it, so the list holds both. Retrying was then refused as a
    /// clash, and if the folder was the class folder it could not be removed
    /// either: no way out but hand-editing the JSON.
    func testARenameLeftHalfDoneCanBeFinished() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: ["All Days"])
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )

        XCTAssertTrue(
            SpecialFolderRenamer.looksLikeAnInterruptedRename(
                from: "All Classes", to: "All Days", scope: .perSection,
                courseDirectory: course, sectionNumbers: [1, 2]
            ),
            "a rename recorded as started, and the disk agreeing it happened"
        )
        XCTAssertEqual(
            SpecialFolderRenamer.interruptedRenameTarget(
                from: "All Classes", scope: .perSection,
                courseDirectory: course, sectionNumbers: [1, 2]
            ),
            "All Days",
            "the sheet fills the field in with the rename that was interrupted"
        )
        XCTAssertNil(
            SpecialFolderRenamer.problem(
                renaming: "All Classes", to: "All Days",
                existingNames: ["All Classes", "All Days"],
                isFinishingAnInterruptedRename: true
            ),
            "a list holding both names is the half-done state, not two folders competing"
        )
    }

    /// And the refusal must still stand when it really is two folders.
    func testAGenuineClashIsStillRefused() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["Tasks", "Handouts"])

        XCTAssertFalse(
            SpecialFolderRenamer.looksLikeAnInterruptedRename(
                from: "Tasks", to: "Handouts", scope: .perSection,
                courseDirectory: course, sectionNumbers: [1]
            ),
            "both folders are on disk, and no rename was recorded"
        )
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Handouts", existingNames: ["Tasks", "Handouts"]
            ),
            SpecialNames.renameFolderProblemAlreadyUsed(name: "Handouts")
        )
    }

    /// **The case that decides whether the bypass is safe, and the reason the
    /// disk alone cannot be the evidence.** A configuration entry whose folder
    /// was never created — which this code explicitly allows — renamed onto a
    /// genuine second folder has EXACTLY the disk state of a half-done rename:
    /// old gone, new present. Bypassing there would hand the real folder the
    /// phantom's attributes, `hidden` among them, and take its pages off the
    /// next publish with nobody told. Only a recorded rename opens the bypass.
    func testAPhantomEntryRenamedOntoARealFolderIsStillRefused() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["Handouts"])
        // "Tasks" is in the configuration and on disk nowhere — a folder the
        // teacher deleted in Obsidian, or never filled in.
        XCTAssertFalse(
            SpecialFolderRenamer.looksLikeAnInterruptedRename(
                from: "Tasks", to: "Handouts", scope: .perSection,
                courseDirectory: course, sectionNumbers: [1]
            ),
            "no rename was ever recorded, so this is two folders, not one half-done rename"
        )
        XCTAssertEqual(
            SpecialFolderRenamer.problem(
                renaming: "Tasks", to: "Handouts", existingNames: ["Tasks", "Handouts"]
            ),
            SpecialNames.renameFolderProblemAlreadyUsed(name: "Handouts")
        )
    }

    /// A record for a DIFFERENT target must not open the bypass either.
    func testARecordForAnotherTargetDoesNotOpenTheBypass() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["Handouts"])
        SpecialFolderRenamer.recordRenameStarting(
            from: "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course
        )
        XCTAssertFalse(
            SpecialFolderRenamer.looksLikeAnInterruptedRename(
                from: "Tasks", to: "Handouts", scope: .perSection,
                courseDirectory: course, sectionNumbers: [1]
            ),
            "the interrupted rename was heading somewhere else"
        )
    }

    /// And a completed rename leaves no record, so nothing is bypassed after it.
    func testAFinishedRenameLeavesNoRecord() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["All Days"])
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )
        SpecialFolderRenamer.clearRenameRecord(courseDirectory: course)
        XCTAssertNil(
            SpecialFolderRenamer.interruptedRenameTarget(
                from: "All Classes", scope: .perSection,
                courseDirectory: course, sectionNumbers: [1]
            )
        )
    }

    /// A per-section rename moves EVERY section's copy, so a mixture means
    /// something other than an interrupted rename and the refusal should hold.
    func testAMixtureIsNotTreatedAsAnInterruptedRename() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: ["All Classes"])
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section1/All Days"), withIntermediateDirectories: true
        )
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )
        XCTAssertFalse(
            SpecialFolderRenamer.looksLikeAnInterruptedRename(
                from: "All Classes", to: "All Days", scope: .perSection,
                courseDirectory: course, sectionNumbers: [1, 2]
            ),
            "section 2 still has the old folder, so this is not a rename to finish"
        )
    }

    /// Finishing the rename must not leave the name in the list twice — the
    /// starting list holds both, and a `ForEach(id: \.self)` renders duplicate
    /// identities.
    func testFinishingARenameLeavesTheNameOnlyOnce() {
        let updated: [String: Any] = SpecialFolderRenamer.renaming(
            "All Classes", to: "All Days", scope: .perSection,
            in: ["per_section_folders": ["All Classes", "All Days", "Tasks"]]
        )
        XCTAssertEqual(updated["per_section_folders"] as? [String], ["All Days", "Tasks"])
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
