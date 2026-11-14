import XCTest
@testable import QuartzTeachers

/// The next reading of a folder settles a whole-course restore that did not
/// finish (#909): `contracts/course-management.json` →
/// `backups.restoreWholeCourse.settleCases`, each state built on disk the
/// way a kill leaves it (the record, and the files where the kill left
/// them), then `WholeCourseRestore.settleUnfinishedRestores`. A kill itself
/// cannot be made inside XCTest, which is hosted by the app; the kill matrix
/// is the standalone harness in documentation/09-mac-app.md.
final class RestoreRecoveryTests: XCTestCase {

    // MARK: - Functions: the cases

    @MainActor
    func testARestoreKilledAfterTwoMovesOutIsPutBackAndSaidOnce() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let staged: StagedRestore = try StagedRestore.make(fixture, phase: .swapping, movesMade: 2)
        XCTAssertFalse(RestoreSwap.itemExists(at: fixture.courseURL.appendingPathComponent("course_config.json")),
                       "the kill leaves the settings aside: the course reads as no course until it is settled")

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertEqual(said, [RestoreWholeCourseWording.didNotFinish(course: "ICS3U")])
        XCTAssertFalse(RestoreSwap.itemExists(at: staged.stagingURL))
        XCTAssertEqual(fixture.leftInRestoring(), 0)
        XCTAssertTrue(fixture.trailText().contains("that did not finish (swapping): put back as it was"), fixture.trailText())
        XCTAssertEqual(WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL), [], "said once")
    }

    @MainActor
    func testARestoreKilledAfterEveryMoveButBeforeDoneIsPutBack() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let staged: StagedRestore = try StagedRestore.make(fixture, phase: .swapping, movesMade: Int.max)
        XCTAssertGreaterThan(staged.moves.count, 0)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertEqual(said, [RestoreWholeCourseWording.didNotFinish(course: "ICS3U")])
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    @MainActor
    func testARestoreKilledAfterDoneIsFinishedAndNothingIsSaid() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        // Archived first, as the door does: the archive holds every file of
        // the old copy, so nothing is kept and nothing is said.
        _ = try StagedRestore.make(fixture, phase: .done, movesMade: Int.max, archived: true)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(
            try WholeCourseFixture.snapshot(of: fixture.courseURL),
            fixture.backupWithWhatIsKeptInPlace(liveGit: live[".git/HEAD"])
        )
        XCTAssertEqual(said, [])
        XCTAssertFalse(fixture.somethingWasKept())
        XCTAssertEqual(fixture.leftInRestoring(), 0, "the old copy and the staging folder are removed")
    }

    @MainActor
    func testANewcomerInAnOriginalsPlaceIsKeptAndTheOriginalGoesBack() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        _ = try StagedRestore.make(fixture, phase: .swapping, movesMade: 2)
        // Obsidian, open on the vault, recreates its folder before the next
        // reading.
        try WholeCourseFixture.write("{\"recreated\": true}", to: fixture.courseURL.appendingPathComponent(".obsidian/workspace.json"))

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said[0].hasPrefix(RestoreWholeCourseWording.didNotFinish(course: "ICS3U") + " Files made in ICS3U"), said[0])
        let kept: [String: Data] = try fixture.everythingKept()
        XCTAssertEqual(kept[".obsidian/workspace.json"], Data("{\"recreated\": true}".utf8), "the newcomer is kept, never deleted")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    @MainActor
    func testAnOriginalAtNeitherEndMovesNothingAndKeepsEverything() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let staged: StagedRestore = try StagedRestore.make(fixture, phase: .swapping, movesMade: 4)
        // index.md was the fourth move out; it is now at neither end.
        try FileManager.default.removeItem(at: staged.stagingURL.appendingPathComponent("as-it-was/index.md"))
        let before: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), before, "nothing moved back")
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said[0].hasPrefix("The restore of ICS3U stopped part way"), said[0])
        // As wording.joins says since round two: notInTheSidebar, then
        // restoreAgainToPutItRight (this read the first alone, written before
        // the second was joined; the bench found it on db38ed112).
        XCTAssertTrue(
            said[0].hasSuffix(
                RestoreWholeCourseWording.notInTheSidebar(course: "ICS3U") + " "
                + RestoreWholeCourseWording.restoreAgainToPutItRight(course: "ICS3U")
            ),
            said[0]
        )
        let kept: [String: Data] = try fixture.everythingKept()
        XCTAssertNotNil(kept["course_config.json"], "the set-aside originals are kept where a teacher can open them")
        XCTAssertNotNil(kept["Concepts/Unit 1/Concept 1.md"])
        XCTAssertTrue(fixture.trailText().contains("a whole-course restore stopped part way"), fixture.trailText())
    }

    @MainActor
    func testARecordAnotherLiveSettlerHoldsIsLeftAlone() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let staged: StagedRestore = try StagedRestore.make(fixture, phase: .swapping, movesMade: 2)
        // The test runner's parent is alive for the whole test.
        let settler: Int32 = getppid()
        let claimed: URL = staged.stagingURL.appendingPathComponent("restore.settling.\(settler).json")
        try FileManager.default.moveItem(at: staged.stagingURL.appendingPathComponent("restore.json"), to: claimed)
        try Data("\(settler)\n".utf8).write(to: staged.stagingURL.appendingPathComponent("settler.\(settler)"))

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(said, [])
        XCTAssertTrue(RestoreSwap.itemExists(at: claimed), "another live settler's claim is never taken")
        XCTAssertTrue(RestoreSettle.unsettledRecordExists(forCourse: "ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL),
                      "a restore of the course is refused meanwhile (anotherRestoreUnderWay)")
    }

    @MainActor
    func testASectionRestoresFolderWithNoRecordIsKeptNotRemovedForItsAge() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let staging: URL = RestoreSwap.restoringFolder(fixture.coursesDirectoryURL).appendingPathComponent(UUID().uuidString)
        try WholeCourseFixture.write("{}", to: staging.appendingPathComponent("backup/ICS3U/course_config.json"))
        try WholeCourseFixture.write("tonight's marking\n", to: staging.appendingPathComponent("as-it-was/section2/page.md"))
        let twoDaysAgo: Date = Date().addingTimeInterval(-2 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: staging.path)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said[0].hasPrefix("A restore that did not finish had set some files aside."), said[0])
        XCTAssertEqual(try fixture.everythingKept()["as-it-was/section2/page.md"], Data("tonight's marking\n".utf8),
                       "the only copy of a section's latest edits is kept, never removed by age alone")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    @MainActor
    func testAFolderWithNoRecordThatIsAnHourOldIsLeftAlone() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let staging: URL = RestoreSwap.restoringFolder(fixture.coursesDirectoryURL).appendingPathComponent(UUID().uuidString)
        try WholeCourseFixture.write("live\n", to: staging.appendingPathComponent("as-it-was/section2/page.md"))

        XCTAssertEqual(WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL), [])
        XCTAssertTrue(RestoreSwap.itemExists(at: staging.appendingPathComponent("as-it-was/section2/page.md")))
    }

    @MainActor
    func testAnotherComputersRecordIsNeverMovedBy() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let staged: StagedRestore = try StagedRestore.make(
            fixture, phase: .swapping, movesMade: 2, computer: "ANOTHER-COMPUTER",
            writtenAt: Date().addingTimeInterval(-3 * 86_400)
        )
        let before: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        XCTAssertEqual(WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL), [])
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), before)
        XCTAssertTrue(RestoreSwap.itemExists(at: staged.stagingURL.appendingPathComponent("restore.json")))
    }

    @MainActor
    func testSettlingOneCourseLeavesAnothersRecordAlone() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let staged: StagedRestore = try StagedRestore.make(fixture, phase: .swapping, movesMade: 2)

        XCTAssertEqual(WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL, onlyCourse: "MPM2D"), [])
        XCTAssertTrue(RestoreSwap.itemExists(at: staged.stagingURL.appendingPathComponent("restore.json")))
        XCTAssertEqual(
            WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL, onlyCourse: "ICS3U"),
            [RestoreWholeCourseWording.didNotFinish(course: "ICS3U")]
        )
    }

    // MARK: - Functions: after the implementation review (#909, round 2)

    /// I3: a reference course a crash left part way through its swap is
    /// LOCKED again once the settle puts it back, as a live failure locks
    /// it. MUST FAIL on the settle without `afterPuttingBack`: its pages
    /// stay unlocked, because `justBeforeTheSwap` unlocked them.
    @MainActor
    func testAReferenceCoursePutBackByTheSettleIsLockedAgain() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture(reference: true)
        defer { fixture.tearDown() }
        let page: URL = fixture.courseURL.appendingPathComponent("Concepts/Unit 1/Concept 1.md")
        _ = ReferenceLock.lock(courseDirectory: fixture.courseURL)
        XCTAssertTrue(ReferenceLock.isLocked(page), "the fixture's reference course starts locked")
        // What `justBeforeTheSwap` does, then a kill after two moves out.
        CourseRestorer.unlockForARestore(courseAt: fixture.courseURL)
        XCTAssertFalse(ReferenceLock.isLocked(page))
        _ = try StagedRestore.make(fixture, phase: .swapping, movesMade: 2)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(said, [RestoreWholeCourseWording.didNotFinish(course: "ICS3U")])
        XCTAssertTrue(RestoreSwap.itemExists(at: fixture.courseURL.appendingPathComponent("course_config.json")))
        XCTAssertTrue(ReferenceLock.isLocked(page), "a reference course put back is a reference course: locked again")
    }

    /// M-a: a Restore from Archive that did not finish names Archived, not
    /// Backups, where its zip still is.
    @MainActor
    func testARestoreFromArchivedThatDidNotFinishNamesArchived() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        _ = try StagedRestore.make(fixture, phase: .swapping, movesMade: 2, from: .archived)

        XCTAssertEqual(
            WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL),
            [RestoreWholeCourseWording.didNotFinishFromArchived(course: "ICS3U")]
        )
    }

    /// I2: another computer's unfinished restore, with the course missing
    /// its settings here, is said once (per opening: `alreadyTold`), with a
    /// trail line, and nothing is moved by it.
    @MainActor
    func testAnotherComputersUnfinishedRestoreIsSaidOnceAndNothingMoves() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let staged: StagedRestore = try StagedRestore.make(
            fixture, phase: .swapping, movesMade: 2, computer: "ANOTHER-COMPUTER",
            writtenAt: Date().addingTimeInterval(-3 * 86_400)
        )
        let before: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        let first: (said: [String], told: [String]) = WholeCourseRestore.unfinishedOnAnotherComputer(
            in: fixture.coursesDirectoryURL, alreadyTold: []
        )
        XCTAssertEqual(first.said, [RestoreWholeCourseWording.unfinishedOnAnotherComputer(course: "ICS3U")])
        XCTAssertEqual(first.told, [staged.stagingURL.lastPathComponent])
        XCTAssertTrue(fixture.trailText().contains("left as it is, because another computer started it; nothing here was moved"), fixture.trailText())
        let again: (said: [String], told: [String]) = WholeCourseRestore.unfinishedOnAnotherComputer(
            in: fixture.coursesDirectoryURL, alreadyTold: Set(first.told)
        )
        XCTAssertEqual(again.said, [], "said once")
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), before, "nothing moved")
        XCTAssertTrue(RestoreSwap.itemExists(at: staged.stagingURL.appendingPathComponent("restore.json")))
    }

    /// I2: nothing is said while the course still has its settings here
    /// (the record is from the unpack, nothing moved): it is in the sidebar.
    @MainActor
    func testAnotherComputersRecordIsNotSaidWhileTheCourseHasItsSettings() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        _ = try StagedRestore.make(fixture, phase: .unpacking, movesMade: 0, computer: "ANOTHER-COMPUTER")

        XCTAssertEqual(WholeCourseRestore.unfinishedOnAnotherComputer(in: fixture.coursesDirectoryURL, alreadyTold: []).said, [])
    }

    /// W1 and M-d, through the reader the refusal asks: a restore's OWN
    /// record is never counted; another process's live record is
    /// `underWay`; one this computer wrote whose writer is gone is
    /// `leftOver`, never "being restored somewhere else".
    @MainActor
    func testTheRefusalCountsEveryRecordButTheRestoresOwn() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let thisProcess: String = ProcessLiveness.leaseBody()
        let own: StagedRestore = try StagedRestore.make(fixture, phase: .unpacking, movesMade: 0, owner: thisProcess)
        func ask(otherThan ownStaging: URL?) -> RestoreSettle.Unsettled? {
            return RestoreSettle.unsettledRecord(
                forCourse: "ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL, otherThan: ownStaging,
                computer: SharedMediaStore.thisComputer, owner: thisProcess,
                ownerIsAlive: { (body: String) -> Bool in
                    return WholeCourseRestore.ownerIsAlive(leaseBody: body)
                }
            )
        }
        XCTAssertNil(ask(otherThan: own.stagingURL), "a restore asking about itself finds nothing (W1)")
        XCTAssertEqual(ask(otherThan: nil), RestoreSettle.Unsettled.leftOver, "this process's own record is nothing restoring")

        let gone: StagedRestore = try StagedRestore.make(fixture, phase: .stopped, movesMade: 0)
        XCTAssertEqual(ask(otherThan: own.stagingURL), RestoreSettle.Unsettled.leftOver, "a record whose writer is gone (M-d)")
        try FileManager.default.removeItem(at: gone.stagingURL)

        _ = try StagedRestore.make(fixture, phase: .unpacking, movesMade: 0, computer: "ANOTHER-COMPUTER")
        XCTAssertEqual(ask(otherThan: own.stagingURL), RestoreSettle.Unsettled.underWay, "another computer's record")
    }

    // MARK: - Functions: nothing removed that is nowhere else (round three)

    /// The fix review's I-a, second case: a crash between `done` and the
    /// keep. The record says to keep what was replaced, so the next
    /// reading keeps it, every file byte for byte, and removes nothing.
    /// MUST FAIL on db38ed112, whose settle passed no keep: 45 of 45 files
    /// were removed in the harness. Since round four the settle SAYS where
    /// (`keptWhatWasInTheFolder`), once: the confirmation promised "you are
    /// told where". MUST FAIL on 66f645649, whose settle said nothing (the
    /// round-three review's INCOMPLETE 2).
    @MainActor
    func testACrashBeforeTheKeepIsKeptAtTheNextReading() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        _ = try StagedRestore.make(
            fixture, phase: .done, movesMade: Int.max, extraRecordKeys: ["keepsWhatWasReplaced": true]
        )

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        let keptName: String = try XCTUnwrap(fixture.keptFolderName(startingWith: "ICS3U as it was before restoring again "))
        XCTAssertEqual(said, [
            RestoreWholeCourseWording.keptWhatWasInTheFolder(course: "ICS3U", keptAt: "courses/_backups/ICS3U/" + keptName)
        ])
        XCTAssertTrue(fixture.trailText().contains(ActivityTrail.KeptBecause.noArchive.rawValue), fixture.trailText())
        XCTAssertEqual(WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL), [], "said once")
        XCTAssertEqual(
            try WholeCourseFixture.snapshot(of: fixture.courseURL),
            fixture.backupWithWhatIsKeptInPlace(liveGit: live[".git/HEAD"]),
            "the restore had happened"
        )
        let kept: [String: Data] = try fixture.keptIn(folderStartingWith: "ICS3U as it was before restoring again ")
        var expectedKept: [String: Data] = live
        expectedKept[".git/HEAD"] = nil
        XCTAssertEqual(kept, expectedKept, "every file that was in the folder is kept, none removed")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// The fix review's I-a, first case: the keep fails (the backups folder
    /// refuses). The copy is NOT removed: the restore has happened, the
    /// copy waits in staging with its `done` record, and the next reading
    /// that can keep it does. MUST FAIL on db38ed112, which removed it.
    @MainActor
    func testAKeepThatFailsLeavesTheCopyForTheNextReading() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try FileManager.default.removeItem(at: fixture.courseURL.appendingPathComponent("course_config.json"))
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let shelf: URL = fixture.coursesDirectoryURL.appendingPathComponent("_backups/ICS3U")
        try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        XCTAssertEqual(chmod(shelf.path, 0o555), 0)
        defer { _ = chmod(shelf.path, 0o755) }

        let item: BackupItem = try XCTUnwrap(BackupItem.from(fileURL: fixture.zipURL, courseCode: "ICS3U"))
        try CourseRestorer.restoreBackup(item, coursesDirectoryURL: fixture.coursesDirectoryURL)

        XCTAssertEqual(chmod(shelf.path, 0o755), 0)
        XCTAssertEqual(fixture.leftInRestoring(), 1, "the copy waits in staging")
        var waiting: [String: Data] = [:]
        let restoring: URL = RestoreSwap.restoringFolder(fixture.coursesDirectoryURL)
        for name in try FileManager.default.contentsOfDirectory(atPath: restoring.path) {
            waiting = try WholeCourseFixture.snapshot(of: restoring.appendingPathComponent(name).appendingPathComponent("as-it-was"))
        }
        var expected: [String: Data] = live
        expected[".git/HEAD"] = nil
        XCTAssertEqual(waiting, expected, "nothing of the folder was removed")

        // The next reading, once this process is gone and the folder takes it.
        try StagedRestore.giveTheRecordAGoneOwner(in: fixture)
        _ = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)
        XCTAssertEqual(try fixture.keptIn(folderStartingWith: "ICS3U as it was before restoring again "), expected)
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// The third case: a crash mid-swap leaves the backup's folders in the
    /// course; a page is added to one and a backup page edited before the
    /// next reading. The way back carries them to staging, and they are
    /// kept with the newcomers, never removed with it. MUST FAIL on
    /// db38ed112, which removed both (the harness: 3 of 5 and 3 of 5).
    @MainActor
    func testAPageWrittenIntoTheBackupsFolderAfterACrashIsKept() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        _ = try StagedRestore.make(fixture, phase: .swapping, movesMade: Int.max)
        // As the engine writes it, once the backup is unpacked.
        let writtenAfter: Date = try StagedRestore.recordWrittenAfter(in: fixture)
        let folder: URL = fixture.courseURL.appendingPathComponent("section1/All Classes")
        let edited: URL = folder.appendingPathComponent("Unit 1, Day 1.md")
        XCTAssertEqual(try String(contentsOf: edited, encoding: .utf8), "BACKUP class\n")
        let added: URL = folder.appendingPathComponent("Written after the crash.md")
        try WholeCourseFixture.write("written in Obsidian\n", to: added)
        try WholeCourseFixture.write("BACKUP class, edited in Obsidian\n", to: edited)
        // Written an hour later, as a teacher would: well past the zip's own
        // times, which a zip a test has just made cannot be.
        let later: Date = writtenAfter.addingTimeInterval(3_600)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: added.path)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: edited.path)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live, "put back as it was")
        let kept: [String: Data] = try fixture.keptIn(folderStartingWith: "ICS3U made while a restore was unfinished ")
        XCTAssertEqual(kept["section1/All Classes/Written after the crash.md"], Data("written in Obsidian\n".utf8))
        XCTAssertEqual(kept["section1/All Classes/Unit 1, Day 1.md"], Data("BACKUP class, edited in Obsidian\n".utf8))
        XCTAssertEqual(kept.count, 2, "only what was written is kept, never the backup's untouched files")
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said.first?.contains(RestoreWholeCourseWording.didNotFinish(course: "ICS3U")) == true, said.first ?? "")
        XCTAssertTrue(said.first?.contains("Files made in ICS3U while the restore was unfinished") == true, said.first ?? "")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// Round four: a settle that finishes a restore and keeps files the
    /// archive does not hold says where, once
    /// (`keptWhatTheArchiveMayNotHold`). Here a page arrived in the course
    /// after the archive was made, and the crash came between `done` and
    /// the keep. MUST FAIL on 66f645649, whose settle kept it and said
    /// nothing.
    @MainActor
    func testASettleThatKeepsWhatTheArchiveDoesNotHoldSaysWhere() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let staged: StagedRestore = try StagedRestore.make(fixture, phase: .done, movesMade: Int.max, archived: true)
        let arrived: URL = staged.stagingURL.appendingPathComponent("as-it-was/Concepts/Arrived after the archive.md")
        try WholeCourseFixture.write("arrived\n", to: arrived)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        let keptName: String = try XCTUnwrap(fixture.keptFolderName(startingWith: "ICS3U not in the archive "))
        XCTAssertEqual(said, [
            RestoreWholeCourseWording.keptWhatTheArchiveMayNotHold(course: "ICS3U", keptAt: "courses/_backups/ICS3U/" + keptName)
        ])
        XCTAssertEqual(
            try fixture.keptIn(folderStartingWith: "ICS3U not in the archive "),
            ["Concepts/Arrived after the archive.md": Data("arrived\n".utf8)]
        )
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// The same way back with nothing written: the backup's own files,
    /// unpacked from a zip made a moment ago (whose times can be two
    /// seconds ahead), are never taken for a teacher's.
    @MainActor
    func testTheBackupsUntouchedFilesAreNeverTakenForWrittenOnes() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        _ = try StagedRestore.make(fixture, phase: .swapping, movesMade: Int.max)
        _ = try StagedRestore.recordWrittenAfter(in: fixture)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertEqual(said, [RestoreWholeCourseWording.didNotFinish(course: "ICS3U")])
        XCTAssertFalse(fixture.somethingWasKept())
    }
}

/// The on-disk state a kill leaves part way through a whole-course restore.
@MainActor
struct StagedRestore {

    // MARK: - Stored properties

    let stagingURL: URL
    let moves: [RestoreSwap.Move]

    // MARK: - Functions

    /// The backup unpacked, the moves planned and recorded with an owner
    /// that has gone, and the first `movesMade` of them made.
    static func make(
        _ fixture: WholeCourseFixture,
        phase: RestoreSwap.Phase,
        movesMade: Int,
        computer: String = SharedMediaStore.thisComputer,
        writtenAt: Date = Date(),
        from source: RestoreSwap.Source = RestoreSwap.Source.backups,
        owner: String? = nil,
        extraRecordKeys: [String: Any] = [:],
        archived: Bool = false
    ) throws -> StagedRestore {
        let fileManager: FileManager = FileManager.default
        // As the door makes it, before anything moves: the course archived
        // into its backups folder, named in the record with its moment.
        var archive: (url: URL, began: Date)? = nil
        if archived {
            archive = try fixture.archiveTheCourse()
        }
        let staging: URL = RestoreSwap.restoringFolder(fixture.coursesDirectoryURL).appendingPathComponent(UUID().uuidString)
        let unpacked: URL = staging.appendingPathComponent("backup")
        try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let payload: URL = try RestoreSwap.unpack(fixture.zipURL, named: "ICS3U", into: unpacked)
        let aside: URL = staging.appendingPathComponent("as-it-was")
        try fileManager.createDirectory(at: aside, withIntermediateDirectories: true)
        let moves: [RestoreSwap.Move] = try RestoreSwap.planCourseSwap(
            courseURL: fixture.courseURL,
            payloadURL: payload,
            asideURL: aside,
            coursesDirectoryURL: fixture.coursesDirectoryURL,
            keptInPlace: WholeCourseRestore.keptInPlace
        )
        var record: RestoreSwap.Record = RestoreSwap.Record(
            course: "ICS3U",
            backup: fixture.zipURL.lastPathComponent,
            from: source,
            archive: archive?.url.lastPathComponent,
            phase: phase,
            moves: moves,
            computer: computer,
            owner: try owner ?? StagedRestore.goneOwner(),
            writtenAt: RestoreSettle.momentText(writtenAt)
        )
        if let archive {
            record.archiveBegan = RestoreSwap.momentTextRoundedDown(archive.began)
        }
        try RestoreSwap.writeRecord(record, to: staging.appendingPathComponent(RestoreSwap.recordName), flushes: false)
        if !extraRecordKeys.isEmpty {
            // Written as keys of the file, as file-formats.json -> restoreRecord
            // names them, so a reader that does not know one ignores it.
            let recordURL: URL = staging.appendingPathComponent(RestoreSwap.recordName)
            var written: [String: Any] = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: try Data(contentsOf: recordURL)) as? [String: Any]
            )
            for (key, value) in extraRecordKeys {
                written[key] = value
            }
            try JSONSerialization.data(withJSONObject: written, options: [.sortedKeys]).write(to: recordURL)
        }
        var made: Int = 0
        for move in moves where made < movesMade {
            let to: URL = RestoreSwap.absolute(move.to, in: fixture.coursesDirectoryURL)
            try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: RestoreSwap.absolute(move.from, in: fixture.coursesDirectoryURL), to: to)
            made += 1
        }
        return StagedRestore(stagingURL: staging, moves: moves)
    }

    /// Gives every record in the fixture's staging folders the
    /// `writtenAfter` the engine writes at `swapping` (now, or the zip's own
    /// time plus the rounding), after the unpack, and returns it.
    static func recordWrittenAfter(in fixture: WholeCourseFixture) throws -> Date {
        let moment: String = RestoreSwap.writtenAfterMoment(swapping: RestoreSettle.momentText(Date()), zipURL: fixture.zipURL)
        let restoring: URL = RestoreSwap.restoringFolder(fixture.coursesDirectoryURL)
        for name in try FileManager.default.contentsOfDirectory(atPath: restoring.path) {
            let recordURL: URL = restoring.appendingPathComponent(name).appendingPathComponent(RestoreSwap.recordName)
            var record: RestoreSwap.Record = try XCTUnwrap(RestoreSwap.readRecord(at: recordURL))
            record.writtenAfter = moment
            try RestoreSwap.writeRecord(record, to: recordURL, flushes: false)
        }
        return try XCTUnwrap(RestoreSettle.parsedMoment(moment))
    }

    /// Rewrites every record in the fixture's staging folders so its owner
    /// is a process that has finished, as it is after a quit.
    static func giveTheRecordAGoneOwner(in fixture: WholeCourseFixture) throws {
        let restoring: URL = RestoreSwap.restoringFolder(fixture.coursesDirectoryURL)
        for name in try FileManager.default.contentsOfDirectory(atPath: restoring.path) {
            let recordURL: URL = restoring.appendingPathComponent(name).appendingPathComponent(RestoreSwap.recordName)
            var record: RestoreSwap.Record = try XCTUnwrap(RestoreSwap.readRecord(at: recordURL))
            record.owner = try goneOwner()
            try RestoreSwap.writeRecord(record, to: recordURL, flushes: false)
        }
    }

    /// The lease body of a process that has finished: `/usr/bin/true`, run
    /// and waited for.
    static func goneOwner() throws -> String {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return "\(process.processIdentifier)\ntrue\n\(RestoreSettle.momentText(Date()))\n\n"
    }
}
