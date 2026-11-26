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
        // `rename` makes a step through the door: its list goes in this
        // test's own folder, never the Mac's.
        UndoJournalLocation.folderOverride = temporaryDirectory.appendingPathComponent("undo-list")
    }

    override func tearDownWithError() throws {
        UndoJournalLocation.folderOverride = nil
        UndoKillPoints.hook = nil
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.putBackFailsAt = nil
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
        // Since #128 the name is written down as the LIST `curriculum_folders`,
        // and the primary folder in the legacy key as well, so an older
        // Plantoir on another Mac, which reads only that key, keeps its map.
        XCTAssertEqual(updated["curriculum_folders"] as? [String], ["Expectations"])
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

    // MARK: - The record `rename` writes is its own only while it is unfinished

    /// A rename that finished leaves no record (#899 U4b2-3, the final
    /// sweep's L5). MUST FAIL with `rename` never clearing the record.
    func testASuccessfulRenameLeavesNoRecord() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: ["Tasks"])

        try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        )

        XCTAssertTrue(exists(course.appendingPathComponent("section2/Assessments")))
        XCTAssertNil(SpecialFolderRenamer.interruptedRenameTarget(
            from: "Tasks", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        ))
        XCTAssertFalse(exists(SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)), "the record was left")
    }

    /// A rename refused at its second move, with everything put back,
    /// leaves no record either: nothing was changed.
    func testARenameRefusedWithNothingMovedLeavesNoRecord() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: ["Tasks"])
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 1 }

        XCTAssertThrowsError(try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        ))

        XCTAssertTrue(exists(course.appendingPathComponent("section1/Tasks")), "the refusal changed something")
        XCTAssertTrue(exists(course.appendingPathComponent("section2/Tasks")), "the refusal changed something")
        XCTAssertFalse(exists(SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)), "the record was left")
    }

    /// Refused at its second move with the first move unable to go back:
    /// stopped part way, so the record stays and names the new name.
    func testARenameStoppedPartWayKeepsItsRecord() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: ["Tasks"])
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 1 }
        UndoKillPoints.putBackFailsAt = { @Sendable (index: Int) in index == 0 }

        XCTAssertThrowsError(try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        )) { error in
            guard case .leftPartWay = error as? JournaledStepError else {
                XCTFail("not stopped part way: \(error)")
                return
            }
        }

        let record: Data? = try? Data(contentsOf: SpecialFolderRenamer.renameMarkerURL(courseDirectory: course))
        XCTAssertTrue(
            SpecialFolderRenamer.recordNames(record, from: "Tasks", to: "Assessments", scope: .perSection),
            "the record of a rename stopped part way is gone or names another rename"
        )
    }

    /// Killed between its two moves, as a process that died: the record
    /// stays, so the sheet can offer the name to finish with.
    func testARenameKilledPartWayKeepsItsRecord() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: ["Tasks"])
        UndoKillPoints.hook = { @Sendable (reached: UndoKillPoint) in reached == .beforeSwap(1) }

        XCTAssertThrowsError(try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        ))

        let record: Data? = try? Data(contentsOf: SpecialFolderRenamer.renameMarkerURL(courseDirectory: course))
        XCTAssertTrue(
            SpecialFolderRenamer.recordNames(record, from: "Tasks", to: "Assessments", scope: .perSection),
            "the record of a killed rename is gone or names another rename"
        )
    }

    /// An earlier run's record (another folder's interrupted rename) is
    /// still there, byte for byte, after a rename of another folder is
    /// refused at its make, where this run's own record had replaced it on
    /// disk. MUST FAIL with every refusal clearing the record.
    func testAnEarlierRunsRecordSurvivesARefusedRenameOfAnotherFolder() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: ["All Days", "Tasks"])
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )
        let marker: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)
        let earlier: Data = try Data(contentsOf: marker)
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 1 }

        XCTAssertThrowsError(try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        ))

        XCTAssertEqual(try? Data(contentsOf: marker), earlier, "the earlier run's record was not left as it was")
        XCTAssertEqual(
            SpecialFolderRenamer.interruptedRenameTarget(
                from: "All Classes", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
            ),
            "All Days"
        )
    }

    /// The same when the rename of another folder is refused before
    /// anything is planned (its destination is taken).
    func testAnEarlierRunsRecordSurvivesARenameRefusedAtItsPlan() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["All Days", "Tasks", "Assessments"])
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )
        let marker: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)
        let earlier: Data = try Data(contentsOf: marker)

        XCTAssertThrowsError(try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1]
        ))

        XCTAssertEqual(try? Data(contentsOf: marker), earlier, "the earlier run's record was not left as it was")
    }

    /// And after a SUCCESSFUL rename of another folder: this run's record
    /// goes, and the earlier run's is back as it was.
    func testAnEarlierRunsRecordSurvivesASuccessfulRenameOfAnotherFolder() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["All Days", "Tasks"])
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )
        let marker: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)
        let earlier: Data = try Data(contentsOf: marker)

        try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1]
        )

        XCTAssertTrue(exists(course.appendingPathComponent("section1/Assessments")))
        XCTAssertEqual(try? Data(contentsOf: marker), earlier, "the earlier run's record was not left as it was")
    }

    /// A rename that FINISHES the recorded one (the folder already at its
    /// new name, nothing left to move) clears that record: it is whole now.
    func testFinishingTheRecordedRenameClearsItsRecord() throws {
        let course: URL = try makeCourse(sections: [1], perSectionFolders: ["All Days"])
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )

        try SpecialFolderRenamer.rename(
            "All Classes", to: "All Days", scope: .perSection, courseDirectory: course, sectionNumbers: [1]
        )

        XCTAssertFalse(exists(SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)), "the finished rename's record was left")
    }

    /// A run FINISHING the recorded rename that is refused leaves that
    /// record byte for byte (review 1 of U4b2-3, L4). MUST FAIL with the
    /// refusal clearing a record that names this rename.
    func testARefusedFinishOfTheRecordedRenameKeepsItsRecord() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: [])
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section1/All Days"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section2/All Classes"), withIntermediateDirectories: true
        )
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )
        let marker: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)
        let earlier: Data = try Data(contentsOf: marker)
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in index == 0 }

        XCTAssertThrowsError(try SpecialFolderRenamer.rename(
            "All Classes", to: "All Days", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        ))

        XCTAssertTrue(exists(course.appendingPathComponent("section2/All Classes")), "the refusal changed something")
        XCTAssertEqual(try? Data(contentsOf: marker), earlier, "the record of the rename being finished was not left as it was")
    }

    /// A rename of the recorded folder to ANOTHER name that succeeds takes
    /// the old name away for good, so the earlier record goes rather than
    /// being put back for a rename nobody can finish (review 1, L3). MUST
    /// FAIL with the earlier record put back whenever its target differs.
    func testRenamingTheRecordedFolderElsewhereClearsItsRecord() throws {
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: [])
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section1/All Days"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section2/All Classes"), withIntermediateDirectories: true
        )
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .perSection, courseDirectory: course
        )

        try SpecialFolderRenamer.rename(
            "All Classes", to: "Every Class", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        )

        XCTAssertTrue(exists(course.appendingPathComponent("section2/Every Class")))
        XCTAssertFalse(exists(SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)), "a record nobody can finish was left")
    }

    /// The record cannot be tidied (its folder will not take a change):
    /// said on the trail, never kept quiet (review 1, L2). MUST FAIL with
    /// the failure silent.
    func testARecordThatCannotBeTidiedIsToldOnTheTrail() throws {
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: temporaryDirectory.appendingPathComponent(".trail"))
        let course: URL = try makeCourse(sections: [1, 2], perSectionFolders: ["Tasks"])
        let recordFolder: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course).deletingLastPathComponent()
        UndoKillPoints.fileInUseAtSwap = { @Sendable (index: Int) in
            // The record is written by now: its folder stops taking changes.
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: recordFolder.path)
            return index == 1
        }
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: recordFolder.path)
            ActivityTrail.store = previousTrail
        }

        XCTAssertThrowsError(try SpecialFolderRenamer.rename(
            "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2]
        ))

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        // Said as a refusal: nothing was renamed (review 2, L-B). MUST FAIL
        // with the line saying "renamed the folder".
        let expectedStart: String = SpecialFolderRenamer.renameNoteNotTidiedLine(
            renaming: "Tasks", to: "Assessments", course: "ICS3U", wasRenamed: false, said: ""
        )
        let withoutReason: String = String(expectedStart.dropLast(2))
        XCTAssertTrue(withoutReason.hasPrefix("did not rename the folder Tasks"), withoutReason)
        XCTAssertTrue(trail.contains(withoutReason), trail)
        XCTAssertFalse(trail.contains("· renamed the folder Tasks"), trail)
    }

    /// A `rename` of the recorded folder to ANOTHER name that moves nothing
    /// and changes no settings leaves the record: the settings still name
    /// the old folder, so the recorded rename can still be finished (review
    /// 2, L-A). MUST FAIL with any record of this folder cleared on success.
    func testARenameThatMovesNothingKeepsTheRecordOfThisFoldersUnfinishedRename() throws {
        let course: URL = temporaryDirectory.appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("All Days"), withIntermediateDirectories: true
        )
        SpecialFolderRenamer.recordRenameStarting(
            from: "All Classes", to: "All Days", scope: .shared, courseDirectory: course
        )
        let marker: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)
        let earlier: Data = try Data(contentsOf: marker)

        let outcome: FolderRenameOutcome = try SpecialFolderRenamer.rename(
            "All Classes", to: "Every Class", scope: .shared, courseDirectory: course, sectionNumbers: [1]
        )

        XCTAssertEqual(outcome.foldersMoved, 0)
        XCTAssertEqual(try? Data(contentsOf: marker), earlier, "the record of a rename that can still be finished was cleared")
        XCTAssertEqual(
            SpecialFolderRenamer.interruptedRenameTarget(
                from: "All Classes", scope: .shared, courseDirectory: course, sectionNumbers: [1]
            ),
            "All Days"
        )
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

    // MARK: - U4b2-5: which folders a stopped rename left at the new name

    /// A record of this rename naming `moved`, as its bytes.
    func recordBytes(from oldName: String, to newName: String, scope: FolderScope, moved: [String], in course: URL) throws -> Data {
        SpecialFolderRenamer.recordRenameStarting(from: oldName, to: newName, scope: scope, courseDirectory: course, moved: moved)
        return try Data(contentsOf: SpecialFolderRenamer.renameMarkerURL(courseDirectory: course))
    }

    /// A capitalisation-only FINISH run (review 1 of U4b2-5, L1 d): no
    /// planned move, the record names "concepts". Counted only when the
    /// directory lists the new spelling. MUST FAIL with presence read
    /// without the listing.
    func testACapitalisationOnlyFinishCountsTheFolderOnlyByItsNewSpelling() throws {
        let course: URL = temporaryDirectory.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(at: course.appendingPathComponent("concepts"), withIntermediateDirectories: true)
        let record: Data = try recordBytes(from: "Concepts", to: "concepts", scope: .shared, moved: ["concepts"], in: course)

        let renamed: SpecialFolderRenamer.LeftAtTheNewName = SpecialFolderRenamer.foldersAtTheirNewName(
            renaming: "Concepts", to: "concepts", scope: .shared, courseDirectory: course, sectionNumbers: [],
            planned: [], earlierRecord: record
        )
        XCTAssertEqual(renamed.places, ["concepts"])

        try FileManager.default.moveItem(at: course.appendingPathComponent("concepts"), to: course.appendingPathComponent("Concepts-x"))
        try FileManager.default.moveItem(at: course.appendingPathComponent("Concepts-x"), to: course.appendingPathComponent("Concepts"))
        let putBack: SpecialFolderRenamer.LeftAtTheNewName = SpecialFolderRenamer.foldersAtTheirNewName(
            renaming: "Concepts", to: "concepts", scope: .shared, courseDirectory: course, sectionNumbers: [],
            planned: [], earlierRecord: record
        )
        XCTAssertEqual(putBack.places, [], "the old spelling was read as the new one")
    }

    /// A place the disk refuses to read is neither counted nor taken as
    /// absent: it is returned as unreadable, and the trail line says so
    /// (review 1, L2). MUST FAIL with a refused `lstat` read as absent.
    func testAPlaceThatCannotBeReadIsToldNotTakenAsAbsent() throws {
        let course: URL = temporaryDirectory.appendingPathComponent("courses/ICS3U")
        let section1: URL = course.appendingPathComponent("section1")
        try FileManager.default.createDirectory(at: section1.appendingPathComponent("Assessments"), withIntermediateDirectories: true)
        let record: Data = try recordBytes(from: "Tasks", to: "Assessments", scope: .perSection, moved: ["section1/Assessments"], in: course)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: section1.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: section1.path)
        }

        let left: SpecialFolderRenamer.LeftAtTheNewName = SpecialFolderRenamer.foldersAtTheirNewName(
            renaming: "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1],
            planned: [], earlierRecord: record
        )

        XCTAssertEqual(left.places, [])
        XCTAssertEqual(left.unreadable.count, 1, "\(left)")
        XCTAssertTrue(left.unreadable.first?.hasPrefix("section1/Assessments (") == true, "\(left)")
        let ending: (line: String, sentence: String) = SpecialFolderRenamer.partWayEnding(
            renaming: "Tasks", to: "Assessments", course: "ICS3U", scope: .perSection, left: left,
            keptBeside: 0, said: "S."
        )
        XCTAssertTrue(ending.line.contains("; could not tell whether these are at the new name: section1/Assessments ("), ending.line)
        // Review 2 of U4b2-5, L4: never "was not renamed", which could not
        // be checked. MUST FAIL with the sheet said as stopped part way.
        XCTAssertTrue(ending.line.hasPrefix("may have renamed the folder Tasks to Assessments in ICS3U only in part"), ending.line)
        XCTAssertEqual(ending.sentence, SpecialFolderRenamer.mayBeRenamedInPart(
            renaming: "Tasks", to: "Assessments", places: ["section1/Assessments"], said: "S."
        ))
        XCTAssertFalse(ending.sentence.contains("was not renamed"), ending.sentence)
    }

    /// A link at the new name is this rename's folder only where this run
    /// moved a link there (review 1, L3). MUST FAIL with a link counted as
    /// a folder.
    func testALinkAtTheNewNameIsNotTheRenamedFolderUnlessALinkWasMoved() throws {
        let course: URL = temporaryDirectory.appendingPathComponent("courses/ICS3U")
        let elsewhere: URL = temporaryDirectory.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        let place: URL = course.appendingPathComponent("Ideas")
        try FileManager.default.createSymbolicLink(at: place, withDestinationURL: elsewhere)
        let record: Data = try recordBytes(from: "Concepts", to: "Ideas", scope: .shared, moved: ["Ideas"], in: course)

        let recordedOnly: SpecialFolderRenamer.LeftAtTheNewName = SpecialFolderRenamer.foldersAtTheirNewName(
            renaming: "Concepts", to: "Ideas", scope: .shared, courseDirectory: course, sectionNumbers: [],
            planned: [], earlierRecord: record
        )
        XCTAssertEqual(recordedOnly.places, [], "a link was named as the renamed folder")

        let movedALink: FolderRenamePlan.Move = FolderRenamePlan.Move(
            from: course.appendingPathComponent("Concepts"), to: place, listingSha: "", isALink: true
        )
        let moved: SpecialFolderRenamer.LeftAtTheNewName = SpecialFolderRenamer.foldersAtTheirNewName(
            renaming: "Concepts", to: "Ideas", scope: .shared, courseDirectory: course, sectionNumbers: [],
            planned: [movedALink], earlierRecord: nil
        )
        XCTAssertEqual(moved.places, ["Ideas"])
    }

    // MARK: - U4b2-6: a record that does not say what it moved

    /// What Windows writes today (`SpecialFolderRenamer.RecordRenameStarting`):
    /// from, to and scope, nothing else.
    func windowsRecord(from oldName: String, to newName: String, scope: String, in course: URL) throws -> Data {
        let data: Data = Data("{\n  \"from\": \"\(oldName)\",\n  \"to\": \"\(newName)\",\n  \"scope\": \"\(scope)\"\n}\n".utf8)
        let marker: URL = SpecialFolderRenamer.renameMarkerURL(courseDirectory: course)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: marker)
        return data
    }

    /// Review 2 of U4b2-5, L1: an earlier record without `moved` names no
    /// folder as still called the new name, since a hand-made one reads the
    /// same; it is told as one it cannot tell is this rename's. MUST FAIL
    /// with the old fallback (old name absent beside it) counting it.
    func testARecordWithoutItsPlacesNamesNoFolderAsThisRenames() throws {
        let course: URL = temporaryDirectory.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section1/Assessments"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section2/Tasks"), withIntermediateDirectories: true
        )
        let record: Data = try windowsRecord(from: "Tasks", to: "Assessments", scope: "per_section", in: course)

        let left: SpecialFolderRenamer.LeftAtTheNewName = SpecialFolderRenamer.foldersAtTheirNewName(
            renaming: "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2],
            planned: [], earlierRecord: record
        )

        XCTAssertEqual(left.places, [], "a folder that may be hand-made was named as this rename's")
        XCTAssertEqual(left.cannotTellWhose, ["section1/Assessments"])
        XCTAssertEqual(left.cannotTell, ["section1/Assessments"])
        let ending: (line: String, sentence: String) = SpecialFolderRenamer.partWayEnding(
            renaming: "Tasks", to: "Assessments", course: "ICS3U", scope: .perSection, left: left,
            keptBeside: 1, said: "S."
        )
        XCTAssertTrue(ending.line.hasSuffix("; could not tell whether this rename moved these: section1/Assessments)"), ending.line)
        XCTAssertFalse(ending.sentence.contains("was not renamed"), ending.sentence)
    }

    /// Review 2 of U4b2-5, L2: a start run after a record without `moved`
    /// carries the earlier run's possible places forward as `mayHaveMoved`,
    /// so a third run still says it cannot tell. MUST FAIL with the record
    /// this run writes holding only its own moves.
    func testAStartRunAfterARecordWithoutItsPlacesCarriesThemForward() throws {
        let course: URL = temporaryDirectory.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section1/Assessments"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: course.appendingPathComponent("section2/Tasks"), withIntermediateDirectories: true
        )
        _ = try windowsRecord(from: "Tasks", to: "Assessments", scope: "per_section", in: course)
        var claim: RenameRecordClaim = RenameRecordClaim(
            from: "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, changesTheSettings: true
        )
        let move: FolderRenamePlan.Move = FolderRenamePlan.Move(
            from: course.appendingPathComponent("section2/Tasks"),
            to: course.appendingPathComponent("section2/Assessments"), listingSha: "", isALink: false
        )

        claim.renameIsStarting(moving: [move], sectionNumbers: [1, 2])

        let written: Data = try Data(contentsOf: SpecialFolderRenamer.renameMarkerURL(courseDirectory: course))
        let note: SpecialFolderRenamer.RenameRecordNote = try XCTUnwrap(SpecialFolderRenamer.readRenameRecord(written))
        XCTAssertEqual(note.moved, ["section2/Assessments"])
        XCTAssertEqual(note.mayHaveMoved, ["section1/Assessments"])
        let third: SpecialFolderRenamer.LeftAtTheNewName = SpecialFolderRenamer.foldersAtTheirNewName(
            renaming: "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course, sectionNumbers: [1, 2],
            planned: [], earlierRecord: written
        )
        XCTAssertEqual(third.places, [])
        XCTAssertEqual(third.cannotTellWhose, ["section1/Assessments"])
    }

    /// Review 2 of U4b2-5, L3: a place holding a line break is one place.
    /// MUST FAIL with the places joined into one string by line breaks.
    func testAPlaceWithALineBreakInItsNameIsOnePlace() throws {
        let course: URL = temporaryDirectory.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        let record: Data = try recordBytes(
            from: "Tasks", to: "Two\nLines", scope: .perSection, moved: ["section1/Two\nLines"], in: course
        )
        XCTAssertEqual(
            SpecialFolderRenamer.placesMoved(byTheRecord: record, renaming: "Tasks", to: "Two\nLines", scope: .perSection),
            ["section1/Two\nLines"]
        )
    }

    /// Review 2 of U4b2-5, L5: the record's format is the contract's
    /// (`file-formats.json` → `folderRenameRecord`). Every example there,
    /// Windows' own among them, is read as a record; a record with a key in
    /// another shape is still read; and the keys the Mac writes are the
    /// contract's fields. MUST FAIL with the record read as a map of strings.
    func testTheRenameRecordIsTheContractsFormat() throws {
        let formats: [String: Any] = try UndoContractReplay.contract("file-formats.json")
        let entry: [String: Any] = try XCTUnwrap(formats["folderRenameRecord"] as? [String: Any])
        let examples: [[String: Any]] = try XCTUnwrap(entry["examples"] as? [[String: Any]])
        XCTAssertFalse(examples.isEmpty)
        for example in examples {
            let name: String = try XCTUnwrap(example["name"] as? String)
            let bytes: String = try XCTUnwrap(example["bytes"] as? String)
            let expect: [String: Any] = try XCTUnwrap(example["expect"] as? [String: Any])
            let note: SpecialFolderRenamer.RenameRecordNote? = SpecialFolderRenamer.readRenameRecord(Data(bytes.utf8))
            if expect["read"] as? Bool == false {
                XCTAssertNil(note, name)
                continue
            }
            let read: SpecialFolderRenamer.RenameRecordNote = try XCTUnwrap(note, name)
            XCTAssertEqual(read.from, expect["from"] as? String, name)
            XCTAssertEqual(read.to, expect["to"] as? String, name)
            XCTAssertEqual(read.scope, expect["scope"] as? String, name)
            XCTAssertEqual(read.moved, expect["moved"] as? [String], name)
            XCTAssertEqual(read.mayHaveMoved, expect["mayHaveMoved"] as? [String] ?? [], name)
        }

        var fields: Set<String> = []
        for field in try XCTUnwrap(entry["fields"] as? [[String: Any]]) {
            fields.insert(try XCTUnwrap(field["field"] as? String))
        }
        let course: URL = temporaryDirectory.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        SpecialFolderRenamer.recordRenameStarting(
            from: "Tasks", to: "Assessments", scope: .perSection, courseDirectory: course,
            moved: ["section1/Assessments"], mayHaveMoved: ["section2/Assessments"]
        )
        let written: Data = try Data(contentsOf: SpecialFolderRenamer.renameMarkerURL(courseDirectory: course))
        let object: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(Set(object.keys), fields)
        XCTAssertEqual(object["moved"] as? [String], ["section1/Assessments"])
        XCTAssertEqual(object["mayHaveMoved"] as? [String], ["section2/Assessments"])
    }

}
