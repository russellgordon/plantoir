import XCTest
@testable import QuartzTeachers

/// A whole-course restore through `CourseRestorer.restoreBackup`, the door
/// every whole-course restore goes through (#909). Each test is a fault the
/// old in-place restore reported, or reported as success, measured in the
/// #909 plan's 1.2; each is proven red on the old restore body.
final class CourseRestorerStagedTests: XCTestCase {

    // MARK: - Functions

    @MainActor
    func testAReadOnlyFolderAtTheTopLeavesTheCourseAsItWas() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        XCTAssertEqual(chmod(fixture.courseURL.appendingPathComponent("Concepts").path, 0o555), 0)
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                RestoreWholeCourseWording.leftAsItWasLocked(course: "ICS3U", name: "Concepts") + " " + RestoreWholeCourseWording.unlockIt
            )
        }
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live, "the old restore emptied the course up to Concepts")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    @MainActor
    func testALockedFileAtTheTopLeavesTheCourseAsItWas() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        XCTAssertEqual(lchflags(fixture.courseURL.appendingPathComponent("index.md").path, UInt32(UF_IMMUTABLE)), 0)
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL))
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertTrue(RestoreSwap.itemExists(at: fixture.courseURL.appendingPathComponent("course_config.json")),
                      "the course is still in the sidebar")
    }

    @MainActor
    func testALockedPageInsideStillRestoresAndLeavesNothingStaged() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let page: URL = fixture.courseURL.appendingPathComponent("section1/All Classes/Unit 1, Day 1.md")
        XCTAssertEqual(lchflags(page.path, UInt32(UF_IMMUTABLE)), 0)
        let liveGit: Data = try Data(contentsOf: fixture.courseURL.appendingPathComponent(".git/HEAD"))

        // As the door runs it, with the course archived first: without an
        // archive the old copy is kept rather than removed (the
        // implementation review's I1), and this is about the removal.
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()
        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )

        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), fixture.backupWithWhatIsKeptInPlace(liveGit: liveGit))
        XCTAssertEqual(fixture.leftInRestoring(), 0, "the old copy is unlocked on its way out")
        XCTAssertFalse(fixture.somethingWasKept(), "with an archive made first, the old copy is removed, not kept")
    }

    @MainActor
    func testWhatBackupsLeaveOutStaysWhereItIs() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)
        XCTAssertEqual(
            try String(contentsOf: fixture.courseURL.appendingPathComponent(".git/HEAD"), encoding: .utf8),
            "ref: refs/heads/main\n",
            "the old restore deleted .git, which is in neither the backup nor the archive"
        )
        XCTAssertEqual(try String(contentsOf: fixture.courseURL.appendingPathComponent("index.md"), encoding: .utf8), "BACKUP front page\n")
    }

    @MainActor
    func testARenameRecordSurvivesARestoreLeftAsItWas() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try UnitWordRenamer.recordRenameStarting(from: "Unit", to: "Module", courseDirectory: fixture.courseURL)
        let record: URL = UnitWordRenamer.renameMarkerURL(courseDirectory: fixture.courseURL)
        XCTAssertTrue(RestoreSwap.itemExists(at: record))
        XCTAssertEqual(chmod(fixture.courseURL.appendingPathComponent("section1").path, 0o555), 0)

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL))
        XCTAssertTrue(RestoreSwap.itemExists(at: record), "a restore that did not happen must not clear the record of a rename under way")
    }

    @MainActor
    func testASmallBackupIsRefusedUntilItsMediaIsPutBack() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture(smallBackupMarker: true)
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                SharedMediaStore.Problem.mediaNotPutBack(fixture.zipURL.lastPathComponent).localizedDescription
            )
        }
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live, "the old restore deleted Media and said nothing")
    }

    @MainActor
    func testAnArrivalIsStagedBesideTheCourses() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        try FileManager.default.removeItem(at: fixture.courseURL)
        var parents: [String] = []
        let hooks: RestoreSwap.Hooks = RestoreSwap.Hooks(
            step: { (_: String) throws in
            },
            move: { (source: URL, destination: URL) throws in
                parents.append(source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)
                try FileManager.default.moveItem(at: source, to: destination)
            },
            moveBack: { (source: URL, destination: URL) throws in
                try FileManager.default.moveItem(at: source, to: destination)
            },
            flushes: false
        )
        try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, hooks: hooks)
        XCTAssertEqual(parents, ["restoring"], "one move, from courses/.internal/restoring/<id>/backup/")
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), fixture.backupFiles)
    }

    /// The third case: a name backups leave out, found deeper than the top
    /// of the course (`section1/Sample App/.git`), is in neither the backup
    /// nor the archive, so it is kept when the copy set aside is removed.
    /// `.DS_Store` is not: Finder makes it again. MUST FAIL on db38ed112,
    /// which removed the `.git`, the `build` and the `out` with the copy.
    @MainActor
    func testNamesBackupsLeaveOutDeeperThanTheTopAreKept() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let deeper: [String: String] = [
            "section1/Sample App/.git/HEAD": "ref: refs/heads/sample\n",
            "section1/Sample App/build/app.o": "object\n",
            "Concepts/Unit 1/out/result.txt": "output\n",
        ]
        for (path, text) in deeper {
            try WholeCourseFixture.write(text, to: fixture.courseURL.appendingPathComponent(path))
        }
        try WholeCourseFixture.write("finder\n", to: fixture.courseURL.appendingPathComponent("section1/.DS_Store"))
        let liveGit: Data = try Data(contentsOf: fixture.courseURL.appendingPathComponent(".git/HEAD"))

        // As the door runs it, with the course archived first, after every
        // file above, so only their names can make them kept.
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()
        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )

        // Russell's ruling (2026-11-14): put back where it was when the
        // restored course has its folder (Concepts/Unit 1 is the backup's
        // too); kept aside when it does not (section1/Sample App is not).
        var restored: [String: Data] = fixture.backupWithWhatIsKeptInPlace(liveGit: liveGit)
        restored["Concepts/Unit 1/out/result.txt"] = Data("output\n".utf8)
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), restored)
        var expected: [String: Data] = [:]
        for (path, text) in deeper where !path.hasPrefix("Concepts/") {
            expected[path] = Data(text.utf8)
        }
        XCTAssertEqual(try fixture.keptIn(folderStartingWith: "ICS3U not in the archive "), expected)
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// Russell's ruling on #909 (2026-11-14): a `.git` deeper inside the
    /// course, in neither the backup nor the archive, is PUT BACK where it
    /// was in the restored course, not kept aside. MUST FAIL on 66f645649
    /// (and on the mutant with `putsDeeperLeftOutNamesBack` false), which
    /// kept it in "<CODE> not in the archive".
    @MainActor
    func testADeeperGitIsPutBackWhereItWas() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let git: String = "section1/All Classes/.git/HEAD"
        try WholeCourseFixture.write("ref: refs/heads/class\n", to: fixture.courseURL.appendingPathComponent(git))
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()

        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )

        XCTAssertEqual(
            try String(contentsOf: fixture.courseURL.appendingPathComponent(git), encoding: .utf8), "ref: refs/heads/class\n"
        )
        XCTAssertFalse(fixture.somethingWasKept(), "put back, so nothing is kept aside")
        XCTAssertEqual(
            try String(contentsOf: fixture.courseURL.appendingPathComponent("section1/All Classes/Unit 1, Day 1.md"), encoding: .utf8),
            "BACKUP class\n"
        )
    }

    /// The third case's other half: a page saved after zip read it is in
    /// the archive as it was before, so it is kept. MUST FAIL on
    /// db38ed112.
    @MainActor
    func testAPageSavedAfterTheArchiveBeganIsKept() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()
        let page: URL = fixture.courseURL.appendingPathComponent("Concepts/Unit 1/Concept 1.md")
        try WholeCourseFixture.write("LIVE concept, saved while the archive was made\n", to: page)

        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )

        XCTAssertEqual(
            try fixture.keptIn(folderStartingWith: "ICS3U not in the archive "),
            ["Concepts/Unit 1/Concept 1.md": Data("LIVE concept, saved while the archive was made\n".utf8)]
        )
    }

    /// The fix review's m-1: a restore of a course that another restore of
    /// it holds (another copy of Plantoir, at the same moment) is refused
    /// with nothing written and nothing moved, and the sentence is the one
    /// for another restore under way; once it lets go, a restore goes
    /// ahead. MUST FAIL on db38ed112, where both went to their records and
    /// either could refuse the other.
    @MainActor
    func testARestoreAnotherRestoreHoldsIsRefusedWithNothingWritten() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        let hold: RestoreSwap.CourseHold = RestoreSwap.holdTheCourse("ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL)
        guard case .held = hold else {
            XCTFail("the hold was not taken: \(hold)")
            return
        }

        XCTAssertThrowsError(try CourseRestorer.restoreBackup(try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL)) { error in
            XCTAssertEqual(error.localizedDescription, RestoreWholeCourseWording.anotherRestoreUnderWay(course: "ICS3U"))
        }
        XCTAssertEqual(try WholeCourseFixture.snapshot(of: fixture.courseURL), live)
        XCTAssertEqual(fixture.leftInRestoring(), 0, "nothing was written")
        XCTAssertTrue(fixture.trailText().contains(
            WholeCourseRestore.DidNotGoAhead.anotherRestore.rawValue + ", asked " + WholeCourseRestore.AskedWhen.whenItBegan.rawValue
        ), fixture.trailText())

        RestoreSwap.letGo(hold)
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()
        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )
        XCTAssertEqual(
            try String(contentsOf: fixture.courseURL.appendingPathComponent("index.md"), encoding: .utf8), "BACKUP front page\n"
        )
    }

    /// Round four, INCOMPLETE 1 of the round-three review: a file that
    /// ARRIVES after the zip's scan keeps its old dates (moved, `cp -p`,
    /// Finder's copy, a folder dragged in), so a rule of times alone found
    /// it in neither the archive nor a kept folder. Whether a file is in
    /// the archive is now read from the archive's own listing (path, size,
    /// recorded time). Each arrival below is dated an hour before the
    /// archive, and a page is replaced at its path by another of the same
    /// size and old dates. MUST FAIL on 66f645649, which lost all five.
    @MainActor
    func testFilesThatArriveWithOldDatesAfterTheArchiveAreKept() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()
        let hourBefore: Date = archive.began.addingTimeInterval(-3_600)
        let outside: URL = fixture.rootURL.appendingPathComponent("Downloads")
        var arrivals: [String: Data] = [:]
        func arrive(_ text: String, at inside: String) throws {
            let source: URL = outside.appendingPathComponent(UUID().uuidString)
            try WholeCourseFixture.write(text, to: source)
            try FileManager.default.setAttributes([.modificationDate: hourBefore, .creationDate: hourBefore], ofItemAtPath: source.path)
            let destination: URL = fixture.courseURL.appendingPathComponent(inside)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // rename(2): over a page that is there, a plain replace, as `mv` does.
            XCTAssertEqual(rename(source.path, destination.path), 0, inside)
            arrivals[inside] = Data(text.utf8)
        }
        try arrive("moved in from Downloads\n", at: "Concepts/Dropped.md")
        try arrive("a handout dragged to the top\n", at: "Handout.md")
        // A folder of old pages moved in whole.
        let folder: URL = outside.appendingPathComponent("Unit 9")
        for index in 1...2 {
            let page: URL = folder.appendingPathComponent("Lesson \(index).md")
            try WholeCourseFixture.write("lesson \(index)\n", to: page)
            try FileManager.default.setAttributes([.modificationDate: hourBefore, .creationDate: hourBefore], ofItemAtPath: page.path)
            arrivals["section1/Unit 9/Lesson \(index).md"] = Data("lesson \(index)\n".utf8)
        }
        try FileManager.default.moveItem(at: folder, to: fixture.courseURL.appendingPathComponent("section1/Unit 9"))
        // The same size as the page it replaces ("LIVE front page\n").
        try arrive("XXXX front page\n", at: "index.md")

        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )

        XCTAssertEqual(try fixture.keptIn(folderStartingWith: "ICS3U not in the archive "), arrivals)
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// Round four: a HIDDEN file changed after the archive began is the
    /// teacher's too (the timetable, Obsidian's settings), kept by the same
    /// rule. MUST FAIL on 66f645649, which left every hidden file out of
    /// the rule (the round-three review: the timetable edit was lost).
    @MainActor
    func testAHiddenFileChangedAfterTheArchiveIsKept() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let timetable: URL = fixture.courseURL.appendingPathComponent(".internal/timetable/section1.json")
        try WholeCourseFixture.write("{\"days\": 4}\n", to: timetable)
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()
        try WholeCourseFixture.write("{\"days\": 5, \"edited\": true}\n", to: timetable)

        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )

        XCTAssertEqual(
            try fixture.keptIn(folderStartingWith: "ICS3U not in the archive "),
            [".internal/timetable/section1.json": Data("{\"days\": 5, \"edited\": true}\n".utf8)]
        )
    }

    /// Round four: whether the old copy is kept whole is decided by the
    /// ENGINE, under its hold, in the step that writes the moves, not by
    /// the door a moment before (the round-three review forced a gap: no
    /// folder at the door, one page in it at the engine, the page lost).
    /// With no archive over a folder that is there, every file is kept.
    /// MUST FAIL on 66f645649, whose engine took the door's word (false).
    @MainActor
    func testTheEngineKeepsTheFolderWholeWhenNoArchiveWasMade() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        var live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        live[".git/HEAD"] = nil

        try WholeCourseRestore.restore(
            fromZipAt: fixture.zipURL, courseCode: "ICS3U", coursesDirectoryURL: fixture.coursesDirectoryURL
        )

        XCTAssertEqual(try fixture.keptIn(folderStartingWith: "ICS3U as it was before restoring again "), live)
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// Plantoir's own Obsidian add-ons are left out of an archive on
    /// purpose and put back by the next pass: removed with the old copy,
    /// never kept as files the archive does not hold (12.9 MB a restore).
    @MainActor
    func testAddOnsLeftOutOfTheArchiveOnPurposeAreNotKept() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let addOn: URL = fixture.courseURL.appendingPathComponent(".obsidian/plugins/tikzjax")
        try WholeCourseFixture.write("add-on\n", to: addOn.appendingPathComponent("main.js"))
        try WholeCourseFixture.write("marker\n", to: addOn.appendingPathComponent(ObsidianFigureAddOns.markerName))
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()

        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )

        XCTAssertFalse(fixture.somethingWasKept(), "nothing kept: the archive holds every other file as it is")
        XCTAssertEqual(fixture.leftInRestoring(), 0)
    }

    /// An archive whose listing cannot be read holds nothing that is
    /// known: every file of the old copy is kept, none removed.
    @MainActor
    func testAnArchiveThatCannotBeReadKeepsEveryFile() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        var live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        live[".git/HEAD"] = nil
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()
        try Data("not a zip".utf8).write(to: archive.url)
        XCTAssertNil(RestoreSwap.ArchiveListing.read(archive.url))

        try CourseRestorer.restoreBackup(
            try item(fixture), coursesDirectoryURL: fixture.coursesDirectoryURL, archiveURL: archive.url,
            archiveBegan: archive.began
        )

        XCTAssertEqual(try fixture.keptIn(folderStartingWith: "ICS3U not in the archive "), live)
    }

    /// The listing is read from the central directory: every file's path
    /// inside the course, in Unicode's composed form, with its size.
    @MainActor
    func testTheArchiveListingReadsPathsAndSizes() throws {
        let fixture: WholeCourseFixture = try WholeCourseFixture()
        defer { fixture.tearDown() }
        let decomposed: String = "Concepts/Cafe\u{0301}.md"
        try WholeCourseFixture.write("accent\n", to: fixture.courseURL.appendingPathComponent(decomposed))
        let archive: (url: URL, began: Date) = try fixture.archiveTheCourse()

        let listing: RestoreSwap.ArchiveListing = try XCTUnwrap(RestoreSwap.ArchiveListing.read(archive.url))

        XCTAssertEqual(listing.file(at: "index.md")?.size, UInt64("LIVE front page\n".utf8.count))
        XCTAssertEqual(listing.file(at: "Concepts/Caf\u{00E9}.md")?.size, 7, "found in either Unicode form")
        XCTAssertNil(listing.file(at: ".git/HEAD"), "left out by the archive")
        XCTAssertTrue(listing.holdsAnything(at: "section1/All Classes"))
        let recorded: Date = try XCTUnwrap(listing.file(at: "index.md")?.recordedTime)
        let changed: Date = try XCTUnwrap(
            try fixture.courseURL.appendingPathComponent("index.md").resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        )
        XCTAssertLessThanOrEqual(abs(recorded.timeIntervalSince(changed)), RestoreSwap.zipTimeRoundingSeconds)
    }

    /// The two lists of names a backup leaves out are together exactly
    /// `CourseArchiver.excludedFromArchives`.
    func testTheNamesLeftOutAreTheArchivesNames() {
        var names: Set<String> = Set(RestoreSwap.leftOutNamesKeptAtAnyDepth)
        for name in RestoreSwap.leftOutNamesMadeAgain {
            names.insert(name)
        }
        XCTAssertEqual(names, Set(CourseArchiver.excludedFromArchives))
        XCTAssertEqual(
            RestoreSwap.leftOutNamesKeptAtAnyDepth.count + RestoreSwap.leftOutNamesMadeAgain.count,
            CourseArchiver.excludedFromArchives.count
        )
    }

    /// The walk that unlocks the old copy before removing it never follows
    /// a link (the plan review, M7): a locked file in a folder OUTSIDE the
    /// course, reached through a link in the old copy, stays locked and in
    /// place.
    func testTheUnlockingRemovalNeverFollowsALink() throws {
        let root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("unlock-walk-\(UUID().uuidString)")
        let outside: URL = root.appendingPathComponent("outside")
        let old: URL = root.appendingPathComponent("as-it-was")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let precious: URL = outside.appendingPathComponent("precious.md")
        try Data("keep\n".utf8).write(to: precious)
        XCTAssertEqual(lchflags(precious.path, UInt32(UF_IMMUTABLE)), 0)
        try FileManager.default.createSymbolicLink(at: old.appendingPathComponent("link"), withDestinationURL: outside)
        defer {
            _ = lchflags(precious.path, 0)
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertTrue(RestoreSwap.removeUnlocking(old))

        var status: stat = stat()
        XCTAssertEqual(lstat(precious.path, &status), 0, "the file behind the link is still there")
        XCTAssertNotEqual(status.st_flags & UInt32(UF_IMMUTABLE), 0, "and still locked")
    }

    // MARK: - Helpers

    @MainActor
    private func item(_ fixture: WholeCourseFixture) throws -> BackupItem {
        return try XCTUnwrap(BackupItem.from(fileURL: fixture.zipURL, courseCode: "ICS3U"))
    }
}
