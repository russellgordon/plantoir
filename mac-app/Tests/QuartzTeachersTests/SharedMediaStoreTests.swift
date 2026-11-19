import CryptoKit
import Darwin
import XCTest
@testable import QuartzTeachers

/// The shared Media store through a real working folder (#785, piece 785a).
///
/// What matters most here, since a small backup may be a teacher's only copy
/// of last week's course: it must restore to exactly what a whole zip would
/// have restored; a store file is whole or absent; a missing or damaged one
/// is NAMED; the sweep never runs while a backup or a restore holds the
/// store, and never deletes what a backup or a step on the Undo list still
/// names.
final class SharedMediaStoreTests: XCTestCase {

    // MARK: - Stored properties

    private var topURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Functions

    override func setUpWithError() throws {
        topURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: topURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: topURL)
    }

    // MARK: - Byte for byte

    /// The REAL whole backup (`CourseArchiver.backingUp`) and a small backup
    /// of the same course, both unpacked as a restore unpacks them, and the
    /// two trees compared: names, kinds, bytes and permissions. Media dates
    /// are compared with the ORIGINAL files, which the small restore puts
    /// back exactly (a whole zip keeps DOS time in two-second steps).
    func testASmallBackupRestoresExactlyWhatAWholeZipRestores() async throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = try SharedMediaTestFiles.makeAwkwardCourse(in: courses)

        let wholeURL: URL = try await CourseArchiver.backingUp(
            courseDirectoryPath: course.path, code: "ICS3U", coursesDirectoryPath: courses.path
        )
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses)
        let name: String = "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip"
        let written: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U", zipName: name,
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        let entries: String = SharedMediaTestFiles.zipEntries(written.zipURL)
        XCTAssertFalse(entries.contains("ICS3U/Media/"), "a small backup holds no Media entry")
        XCTAssertTrue(entries.contains(SharedMediaList.nameInsideTheZip), "and holds its list")

        let wholeOut: URL = topURL.appendingPathComponent("whole-out")
        let smallOut: URL = topURL.appendingPathComponent("small-out")
        XCTAssertTrue(SharedMediaTestFiles.unpack(wholeURL, into: wholeOut))
        XCTAssertTrue(SharedMediaTestFiles.unpack(written.zipURL, into: smallOut))
        let list: SharedMediaList = try XCTUnwrap(try SharedMediaStore.list(inUnpackedBackupAt: smallOut))
        XCTAssertNil(try SharedMediaStore.list(inUnpackedBackupAt: wholeOut), "a whole zip carries no list")
        let payload: URL = smallOut.appendingPathComponent("ICS3U")
        let restore: SharedMediaRestore = store.beginRestore(of: list, currentCourseFolderURL: course)
        XCTAssertEqual(restore.missing, [])
        let filled: SharedMediaRestore.Filled = try restore.fill(intoCourseAt: payload, backupFileName: name)
        restore.end()
        XCTAssertEqual(filled.missing, [])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: payload.appendingPathComponent(SharedMediaList.nameInsideTheZip).path),
            "the restored course carries no file the teacher did not make"
        )

        // Keyed by the names' BYTES: Swift's String equality treats the two
        // Unicode forms of a name as one, and so could not see a precomposed
        // name come back decomposed (#785 implementation review, W2).
        let small: [[UInt8]: SharedMediaTestFiles.Node] = SharedMediaTestFiles.tree(payload)
        let whole: [[UInt8]: SharedMediaTestFiles.Node] = SharedMediaTestFiles.tree(wholeOut.appendingPathComponent("ICS3U"))
        XCTAssertEqual(SharedMediaTestFiles.differences(small, whole), [])
        XCTAssertEqual(small.count, whole.count)
        XCTAssertNotNil(small[Array("Media/empty folder".utf8)], "an empty folder comes back")
        XCTAssertNil(small[Array("Media/build/left out.png".utf8)], "what the whole zip leaves out, the small one leaves out")
        XCTAssertNil(small[Array("Media/sub/.DS_Store".utf8)])
        XCTAssertNotNil(small[Array("Media/.hidden".utf8)], "hidden files come back")
        XCTAssertNotNil(small[Array("Media/real folder/inner.png".utf8)], "a folder a link sorted before comes back (W1)")
        XCTAssertNotNil(small[Array("Media/a link to the real folder/inner.png".utf8)], "and the link's copy too, as the whole zip has it")
        XCTAssertNotNil(small[Array("Media/link to outside/far.png".utf8)], "a link to a folder outside the course")
        XCTAssertNotNil(small[Array("Media/caf\u{00E9}/cr\u{00E8}me.png".utf8)], "a precomposed name keeps its bytes (W2)")
        XCTAssertNil(small[Array("Media/cafe\u{0301}/cre\u{0300}me.png".utf8)], "and is not decomposed")
        XCTAssertNotNil(small[Array("Media/\u{0308}Bild.png".utf8)], "a name that begins with a combining mark comes back (N1)")
        XCTAssertNotNil(small[Array("Media/\u{0301}dir/\u{0301}lead.png".utf8)], "and so does a folder whose name does")
        XCTAssertGreaterThan(small.count, 100, "the comparison saw the awkward course, its loop included")

        let original: [[UInt8]: SharedMediaTestFiles.Node] = SharedMediaTestFiles.tree(course)
        for (path, node) in small where node.kind == "file" && path.starts(with: Array("Media/".utf8)) {
            if let restoredDate = node.modified, let originalNode = original[path], originalNode.kind == "file",
               let originalDate = originalNode.modified {
                XCTAssertEqual(
                    restoredDate.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 0.002,
                    "\(SharedMediaTestFiles.shown(path)) comes back with its own date"
                )
            }
        }
    }

    func testASecondBackupAddsOnlyWhatChanged() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = try SharedMediaTestFiles.makeAwkwardCourse(in: courses)
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses)
        let rules: SharedMediaStore.ArchiveRules = CourseArchiver.archiveRules(forFolderAt: course)
        let first: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip", rules: rules
        )
        XCTAssertGreaterThan(first.filesAdded, 5)
        XCTAssertGreaterThan(first.filesAlreadyKept + first.filesAdded, 0)
        let second: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183801_menu-section1_shared-media.zip", rules: rules
        )
        XCTAssertEqual(second.filesAdded, 0, "an unchanged course adds nothing to the store")
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(4000), to: course.appendingPathComponent("Media/sub/c.jpg"))
        let third: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183802_menu-section1_shared-media.zip", rules: rules
        )
        XCTAssertEqual(third.filesAdded, 1, "one changed picture adds one file")
        try FileManager.default.moveItem(
            at: course.appendingPathComponent("Media/private.png"), to: course.appendingPathComponent("Media/renamed.png")
        )
        let fourth: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183803_menu-section1_shared-media.zip", rules: rules
        )
        XCTAssertEqual(fourth.filesAdded, 0, "a renamed picture adds nothing")
        XCTAssertThrowsError(try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183803_menu-section1_shared-media.zip", rules: rules
        )) { (error: Error) in
            XCTAssertEqual(
                error as? SharedMediaStore.Problem,
                .nameAlreadyTaken("ICS3U_backup_2026-11-13_183803_menu-section1_shared-media.zip")
            )
        }
        XCTAssertThrowsError(try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183804_menu-section1.zip", rules: rules
        ), "a whole backup's name is never written small")
    }

    // MARK: - Interrupted writes

    /// A backup stopped at each point, as a crash stops it (nothing tidied),
    /// then swept again and again over four days: every published backup
    /// stays whole, and one that never published leaves nothing behind.
    func testACrashAtEveryPointLeavesEveryPublishedBackupWhole() throws {
        let points: [SharedMediaStore.WritePoint] = [.pendingWritten, .mediaStored, .zipWritten, .listCopied, .zipPublished]
        for point in points {
            let courses: URL = topURL.appendingPathComponent("crash-\(point)/courses")
            let course: URL = try SharedMediaTestFiles.makeAwkwardCourse(in: courses)
            let clock: SharedMediaTestClock = SharedMediaTestClock()
            let crashing: SharedMediaStore = SharedMediaStore(
                coursesDirectoryURL: courses,
                clock: { clock.now },
                processIsRunning: { (_: Int32, _: String?) -> Bool in false },
                hooks: SharedMediaStore.Hooks(
                    reached: { (reached: SharedMediaStore.WritePoint) throws in
                        if reached == point {
                            throw SharedMediaTestFiles.Stopped()
                        }
                    },
                    copiedIntoTheStore: { (_: URL) in },
                    tidiesUpAfterAFailure: false
                )
            )
            let name: String = "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip"
            XCTAssertThrowsError(try crashing.writeSmallBackup(
                courseFolderURL: course, courseCode: "ICS3U", zipName: name,
                rules: CourseArchiver.archiveRules(forFolderAt: course)
            ), "\(point): stopped")
            let sweeper: SharedMediaStore = SharedMediaStore(
                coursesDirectoryURL: courses, clock: { clock.now },
                processIsRunning: { (_: Int32, _: String?) -> Bool in false }
            )
            let zipURL: URL = courses.appendingPathComponent("_backups/ICS3U/\(name)")
            let published: Bool = FileManager.default.fileExists(atPath: zipURL.path)
            XCTAssertEqual(published, point == .zipPublished, "\(point)")
            let start: Date = clock.now
            for hours in [0.0, 25.0, 50.0, 75.0, 100.0] {
                clock.now = start.addingTimeInterval(hours * 3600)
                sweeper.sweep()
                XCTAssertTrue(
                    try SharedMediaTestFiles.everySmallBackupIsWhole(sweeper, course: "ICS3U"),
                    "\(point): every published backup is whole after the sweep \(hours) h on"
                )
            }
            if published {
                let list: SharedMediaList = try SharedMediaStore.list(insideZipAt: zipURL)
                XCTAssertEqual(sweeper.pathsNotHeld(by: list), [], "\(point): the published backup keeps every file")
            } else {
                XCTAssertEqual(SharedMediaTestFiles.storeEntryCount(sweeper), 0, "\(point): nothing is left behind")
                XCTAssertEqual(SharedMediaTestFiles.leftoverCount(sweeper, course: "ICS3U"), 0, "\(point): no unpublished zip or list folder")
            }
        }
    }

    func testACopyThatDoesNotMatchFailsTheBackupAndPublishesNothing() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = try SharedMediaTestFiles.makeAwkwardCourse(in: courses)
        let damaging: SharedMediaStore = SharedMediaStore(
            coursesDirectoryURL: courses,
            hooks: SharedMediaStore.Hooks(
                reached: { (_: SharedMediaStore.WritePoint) throws in },
                copiedIntoTheStore: { (temporary: URL) in
                    try? Data("damaged".utf8).write(to: temporary)
                },
                tidiesUpAfterAFailure: true
            )
        )
        XCTAssertThrowsError(try damaging.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )) { (error: Error) in
            guard case .storeCopyDidNotMatch = error as? SharedMediaStore.Problem else {
                XCTFail("expected storeCopyDidNotMatch, got \(error)")
                return
            }
        }
        XCTAssertEqual(SharedMediaTestFiles.storeEntryCount(damaging), 0, "nothing under a checksum's name")
        let folder: [String] = (try? FileManager.default.contentsOfDirectory(
            atPath: courses.appendingPathComponent("_backups/ICS3U").path
        )) ?? []
        XCTAssertEqual(folder, [], "no zip published")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: damaging.pendingURL.path)) ?? [], [])
    }

    func testAPictureThatChangesWhileBeingSavedIsNamed() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = courses.appendingPathComponent("ICS3U")
        try SharedMediaTestFiles.write(Data("{}".utf8), to: course.appendingPathComponent("course_config.json"))
        let picture: URL = course.appendingPathComponent("Media/sub/c.jpg")
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(5000), to: picture)
        let changing: SharedMediaStore = SharedMediaStore(
            coursesDirectoryURL: courses,
            hooks: SharedMediaStore.Hooks(
                reached: { (_: SharedMediaStore.WritePoint) throws in },
                copiedIntoTheStore: { (temporary: URL) in
                    try? Data("damaged".utf8).write(to: temporary)
                    try? Data("changed".utf8).write(to: picture)
                },
                tidiesUpAfterAFailure: true
            )
        )
        XCTAssertThrowsError(try changing.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )) { (error: Error) in
            XCTAssertEqual(error as? SharedMediaStore.Problem, .mediaChangedWhileBeingSaved("Media/sub/c.jpg"))
        }
    }

    /// A store file damaged after it was written (a power cut, a failing
    /// disk): a restore names it as missing rather than writing wrong bytes,
    /// takes the course's own copy when it has the same bytes, and the next
    /// backup replaces the damaged file.
    func testADamagedStoreFileIsNamedMissingAndTheNextBackupMendsIt() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = try SharedMediaTestFiles.makeAwkwardCourse(in: courses)
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses)
        let rules: SharedMediaStore.ArchiveRules = CourseArchiver.archiveRules(forFolderAt: course)
        let first: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip", rules: rules
        )
        var damagedFile: SharedMediaList.MediaFile? = nil
        for file in first.list.media where file.path == "Media/sub/c.jpg" {
            damagedFile = file
        }
        let target: SharedMediaList.MediaFile = try XCTUnwrap(damagedFile)
        try Data(count: Int(target.size)).write(to: store.fileURL(forChecksum: target.sha256))

        let noCourse: SharedMediaRestore = store.beginRestore(of: first.list, currentCourseFolderURL: nil)
        XCTAssertTrue(noCourse.missing.contains("Media/sub/c.jpg"), "named, by its path")
        for path in noCourse.missing {
            XCTAssertTrue(path.hasSuffix("/sub/c.jpg"), "only the damaged file, wherever a link also leads to it: \(path)")
        }
        XCTAssertTrue(noCourse.canBeRestored)
        let payload: URL = topURL.appendingPathComponent("staging/ICS3U")
        let filled: SharedMediaRestore.Filled = try noCourse.fill(intoCourseAt: payload, backupFileName: "x")
        noCourse.end()
        XCTAssertEqual(filled.missing, noCourse.missing, "named again, never skipped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: payload.appendingPathComponent("Media/sub/c.jpg").path))

        let withCourse: SharedMediaRestore = store.beginRestore(of: first.list, currentCourseFolderURL: course)
        XCTAssertEqual(withCourse.missing, [], "the course's own copy of the same bytes is used")
        withCourse.end()

        let mended: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183801_menu-section1_shared-media.zip", rules: rules
        )
        XCTAssertEqual(mended.filesAdded, 1)
        XCTAssertEqual(store.pathsNotHeld(by: first.list), [])
    }

    // MARK: - The sweep and Undo's seam (#899)

    /// Two pictures enter the store at the same moment. The backup naming
    /// both is deleted (to the Trash, by Undo); Undo keeps one of them. The
    /// one Undo names survives every sweep for 61 days by the Undo list's own
    /// written moment; the other, of the same age, goes a day after a sweep
    /// first finds it unneeded.
    func testAFileAnUndoStepNamesSurvivesASweepAndOneOfTheSameAgeDoesNot() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = courses.appendingPathComponent("ICS3U")
        try SharedMediaTestFiles.write(Data("{}".utf8), to: course.appendingPathComponent("course_config.json"))
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(10_000), to: course.appendingPathComponent("Media/kept for undo.png"))
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(10_000), to: course.appendingPathComponent("Media/not kept.png"))
        let clock: SharedMediaTestClock = SharedMediaTestClock()
        let start: Date = clock.now
        let store: SharedMediaStore = SharedMediaStore(
            coursesDirectoryURL: courses, clock: { clock.now }, computer: "THIS-MAC",
            processIsRunning: { (_: Int32, _: String?) -> Bool in false }
        )
        let written: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_assistant-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        var keptChecksum: String = ""
        var otherChecksum: String = ""
        for file in written.list.media {
            if file.path == "Media/kept for undo.png" {
                keptChecksum = file.sha256
            } else {
                otherChecksum = file.sha256
            }
        }
        try store.keepForUndo(stepID: "THIS-MAC-41", checksums: [keptChecksum], writtenAt: start)
        try FileManager.default.removeItem(at: written.zipURL)
        let kept: URL = store.fileURL(forChecksum: keptChecksum)
        let other: URL = store.fileURL(forChecksum: otherChecksum)

        clock.now = start.addingTimeInterval(2 * 86_400)
        XCTAssertEqual(store.sweep().filesDeleted, 0, "nothing goes the first time it is found unneeded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        clock.now = start.addingTimeInterval(3 * 86_400 + 3600)
        XCTAssertEqual(store.sweep().filesDeleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.path), "the unreferenced one of the same age is gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "the one an Undo step names survives")
        clock.now = start.addingTimeInterval(30 * 86_400)
        store.sweep()
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "and at 30 days")
        clock.now = start.addingTimeInterval(45 * 86_400)
        store.sweep()
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "and at 45 days, within the journal's grace (#899)")
        clock.now = start.addingTimeInterval(61 * 86_400 + 60)
        store.sweep()
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "found unneeded at 61 days, kept that day")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.listsURL.appendingPathComponent("undo-THIS-MAC-41.json").path
        ), "the expired Undo list is removed")
        clock.now = start.addingTimeInterval(62 * 86_400 + 120)
        store.sweep()
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path), "a day after its Undo list expired, it goes")
        XCTAssertThrowsError(try store.keepForUndo(stepID: "../escape", checksums: [], writtenAt: start))
    }

    func testAnotherComputersUndoListKeepsItsFilesHereUntilReleased() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = courses.appendingPathComponent("ICS3U")
        try SharedMediaTestFiles.write(Data("{}".utf8), to: course.appendingPathComponent("course_config.json"))
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(500), to: course.appendingPathComponent("Media/a.png"))
        let clock: SharedMediaTestClock = SharedMediaTestClock()
        let start: Date = clock.now
        let here: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses, clock: { clock.now }, computer: "THIS-MAC")
        let there: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses, clock: { clock.now }, computer: "OTHER-MAC")
        let written: SharedMediaStore.Written = try there.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_assistant-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        try there.keepForUndo(stepID: "OTHER-MAC-7", checksums: written.list.checksums, writtenAt: start)
        try FileManager.default.removeItem(at: written.zipURL)
        for days in [2.0, 4.0, 6.0] {
            clock.now = start.addingTimeInterval(days * 86_400)
            here.sweep()
        }
        XCTAssertEqual(here.pathsNotHeld(by: written.list), [], "another computer's Undo list keeps its files on this one")
        there.releaseForUndo(stepID: "OTHER-MAC-7")
        clock.now = start.addingTimeInterval(7 * 86_400)
        here.sweep()
        clock.now = start.addingTimeInterval(8 * 86_400 + 60)
        here.sweep()
        XCTAssertEqual(here.pathsNotHeld(by: written.list), [], "another computer has written here, so a day is not enough")
        clock.now = start.addingTimeInterval(21 * 86_400 + 120)
        here.sweep()
        XCTAssertEqual(here.pathsNotHeld(by: written.list).count, 1, "released, it goes fourteen days after it is found unneeded")
    }

    // MARK: - The lock

    /// A restore that holds the store through a symbolic link, or through
    /// the same path in another case, holds off a sweep through the real
    /// path; so does a backup in flight.
    func testTheSweepNeverRunsWhileARestoreOrABackupHoldsTheStore() throws {
        let courses: URL = topURL.appendingPathComponent("folder/courses")
        let course: URL = courses.appendingPathComponent("ICS3U")
        try SharedMediaTestFiles.write(Data("{}".utf8), to: course.appendingPathComponent("course_config.json"))
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(1000), to: course.appendingPathComponent("Media/a.png"))
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses)
        let written: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        let link: URL = topURL.appendingPathComponent("link")
        XCTAssertEqual(symlink(topURL.appendingPathComponent("folder").path, link.path), 0)
        let throughLink: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: link.appendingPathComponent("courses"))
        let otherCase: URL = URL(fileURLWithPath: courses.path.replacingOccurrences(of: "/folder/", with: "/FOLDER/"))
        let throughCase: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: otherCase)

        let holding: SharedMediaRestore = throughLink.beginRestore(of: written.list, currentCourseFolderURL: nil)
        XCTAssertEqual(store.sweep().keptEverything, .theStoreIsBusy)
        if FileManager.default.fileExists(atPath: otherCase.path) {
            XCTAssertEqual(throughCase.sweep().keptEverything, .theStoreIsBusy, "the same folder in another case")
        }
        holding.end()
        XCTAssertNil(store.sweep().keptEverything)

        let during: SharedMediaTestBox = SharedMediaTestBox()
        let writer: SharedMediaStore = SharedMediaStore(
            coursesDirectoryURL: throughLink.coursesDirectoryURL,
            hooks: SharedMediaStore.Hooks(
                reached: { (point: SharedMediaStore.WritePoint) throws in
                    if point == .mediaStored {
                        during.result = store.sweep()
                    }
                },
                copiedIntoTheStore: { (_: URL) in },
                tidiesUpAfterAFailure: true
            )
        )
        _ = try writer.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183801_menu-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        XCTAssertEqual(during.result?.keptEverything, .theStoreIsBusy, "a sweep during a backup deletes nothing")
    }

    // MARK: - What the sweep cannot read

    func testABackupInTheCloudOrDamagedStopsTheSweep() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = courses.appendingPathComponent("ICS3U")
        try SharedMediaTestFiles.write(Data("{}".utf8), to: course.appendingPathComponent("course_config.json"))
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(1000), to: course.appendingPathComponent("Media/a.png"))
        let clock: SharedMediaTestClock = SharedMediaTestClock()
        let start: Date = clock.now
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses, clock: { clock.now })
        let name: String = "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip"
        let written: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U", zipName: name,
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        let placeholder: URL = written.zipURL.deletingLastPathComponent().appendingPathComponent(".\(name).icloud")
        try FileManager.default.moveItem(at: written.zipURL, to: placeholder)
        for days in [2.0, 4.0, 6.0] {
            clock.now = start.addingTimeInterval(days * 86_400)
            store.sweep()
        }
        XCTAssertEqual(store.pathsNotHeld(by: written.list), [], "a backup in the cloud keeps its pictures through its list copy")
        try FileManager.default.removeItem(at: store.listsURL.appendingPathComponent("backup-\(name).json"))
        clock.now = start.addingTimeInterval(8 * 86_400)
        XCTAssertEqual(store.sweep().keptEverything, .aBackupCouldNotBeRead(name), "with no list copy, nothing is deleted")
        try FileManager.default.removeItem(at: placeholder)
        try Data("not a zip".utf8).write(to: written.zipURL)
        XCTAssertEqual(store.sweep().keptEverything, .aBackupCouldNotBeRead(name), "a damaged zip stops the sweep")
        try FileManager.default.removeItem(at: written.zipURL)
        try Data("{\"format\": 2}".utf8).write(to: store.listsURL.appendingPathComponent("undo-LATER-1.json"))
        XCTAssertEqual(store.sweep().keptEverything, .aListCouldNotBeRead("lists/undo-LATER-1.json"))
        XCTAssertEqual(store.pathsNotHeld(by: written.list), [])
    }

    func testAListThatPointsOutsideMediaIsRefused() {
        // The last is a backslash followed by a combining mark: one
        // Character, which a Character search for a backslash did not find
        // (#785 fix review, N1).
        let unsafe: [String] = [
            "Media/../course_config.json", "/etc/hosts", "Media//x.png", "Media\\x.png", "Pages/x.png", "Media",
            "Media/\\\u{0301}x.png",
        ]
        for path in unsafe {
            let text: String = "{\"format\":1,\"kind\":\"backup\",\"course\":\"X\",\"backup\":\"b\","
                + "\"writtenAt\":\"2026-11-13T18:38:00.000Z\",\"host\":\"h\",\"folders\":[],\"media\":[{\"path\":"
                + "\"\(path.replacingOccurrences(of: "\\", with: "\\\\"))\",\"sha256\":\"\(String(repeating: "a", count: 64))\","
                + "\"size\":1,\"modified\":\"2026-11-13T18:38:00.000Z\",\"mode\":420}]}"
            XCTAssertThrowsError(try SharedMediaList.decoded(from: Data(text.utf8)), path)
            if path != "Media" {
                XCTAssertFalse(SharedMediaList.isSafeMediaPath(path), path)
            }
        }
    }

    /// Paths are judged and split on the `/` BYTE (#785 fix review, N1): a
    /// `/` followed by a combining mark is one Character.
    func testAPathIsSplitOnTheSlashByte() {
        XCTAssertTrue(SharedMediaList.isSafeMediaPath("Media/\u{0308}Bild.png"))
        XCTAssertTrue(SharedMediaList.isSafeMediaPath("Media/combo/\u{0301}lead.png"))
        XCTAssertEqual(SharedMediaRestore.folderPart(of: "Media/sub/\u{0308}x.png"), "Media/sub")
        XCTAssertEqual(SharedMediaRestore.folderPart(of: "Media/\u{0308}x.png"), "Media")
        XCTAssertEqual(SharedMediaRestore.folderPart(of: "x.png"), "")
    }

    /// A list this version would refuse to read is never published as a
    /// backup that was made (#785 fix review, N1). A backslash in a Media
    /// name is legal on the mac and refused by the list's path rule, so a
    /// backup of such a course must fail in words and leave no zip, no list
    /// copy and no pending list. Before the fix it was published, and
    /// could not be restored.
    func testABackupWhoseListCouldNotBeReadIsNeverPublished() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = courses.appendingPathComponent("ICS3U")
        try SharedMediaTestFiles.write(Data("{}".utf8), to: course.appendingPathComponent("course_config.json"))
        try SharedMediaTestFiles.write(
            SharedMediaTestFiles.randomData(500), to: course.appendingPathComponent("Media/back\\slash.png")
        )
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses)
        XCTAssertThrowsError(try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        ))
        let fileManager: FileManager = FileManager.default
        let backupsFolder: URL = courses.appendingPathComponent("_backups/ICS3U")
        let inBackups: [String] = (try? fileManager.contentsOfDirectory(atPath: backupsFolder.path)) ?? []
        XCTAssertEqual(inBackups, [], "no zip, published or not")
        for folder in ["lists", "pending"] {
            let url: URL = courses.appendingPathComponent("_backups/.shared-media").appendingPathComponent(folder)
            let names: [String] = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
            XCTAssertEqual(names, [], "nothing left in \(folder)/")
        }
    }

    // MARK: - Two computers on one synced folder (#785 implementation review, W3)

    /// Computer A deletes the only backup naming a picture and finds it
    /// unneeded; a day later computer B makes a backup that lists the same
    /// picture again (copying nothing). An hour on, only B's pending list
    /// has synced to A. A's sweep must keep the picture, and B's restore
    /// find it. Before the fix A deleted it within the hour.
    func testAPictureAnotherComputerHasJustListedAgainIsKept() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = courses.appendingPathComponent("ICS3U")
        try SharedMediaTestFiles.write(Data("{}".utf8), to: course.appendingPathComponent("course_config.json"))
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(3000), to: course.appendingPathComponent("Media/picture.png"))
        let clock: SharedMediaTestClock = SharedMediaTestClock()
        let start: Date = clock.now
        let a: SharedMediaStore = SharedMediaStore(
            coursesDirectoryURL: courses, clock: { clock.now }, computer: "MAC-A",
            processIsRunning: { (_: Int32, _: String?) -> Bool in false }
        )
        let b: SharedMediaStore = SharedMediaStore(
            coursesDirectoryURL: courses, clock: { clock.now }, computer: "MAC-B",
            processIsRunning: { (_: Int32, _: String?) -> Bool in false }
        )
        let rules: SharedMediaStore.ArchiveRules = CourseArchiver.archiveRules(forFolderAt: course)
        let first: SharedMediaStore.Written = try a.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_090000_menu-section1_shared-media.zip", rules: rules
        )
        try FileManager.default.removeItem(at: first.zipURL)
        clock.now = start.addingTimeInterval(1.1 * 86_400)
        a.sweep()
        clock.now = start.addingTimeInterval(2.1 * 86_400)
        let again: SharedMediaStore.Written = try b.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-15_110000_menu-section1_shared-media.zip", rules: rules
        )
        XCTAssertEqual(again.filesAdded, 0)
        let aside: URL = topURL.appendingPathComponent("not yet synced")
        try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
        let copy: URL = a.listsURL.appendingPathComponent("backup-\(again.list.backupName).json")
        try FileManager.default.moveItem(at: again.zipURL, to: aside.appendingPathComponent("zip"))
        try FileManager.default.moveItem(at: copy, to: aside.appendingPathComponent("copy"))
        clock.now = start.addingTimeInterval(2.15 * 86_400)
        XCTAssertEqual(a.sweep().filesDeleted, 0, "the picture B relies on is kept")
        try FileManager.default.moveItem(at: aside.appendingPathComponent("zip"), to: again.zipURL)
        try FileManager.default.moveItem(at: aside.appendingPathComponent("copy"), to: copy)
        let restore: SharedMediaRestore = b.beginRestore(of: again.list, currentCourseFolderURL: nil)
        XCTAssertEqual(restore.missing, [], "and B's restore finds it")
        restore.end()
    }

    // MARK: - A crash's leftovers (#785 implementation review, I1)

    /// A backup stopped once its zip is whole under its temporary name and
    /// its list folder is still there, as a crash leaves them: a sweep the
    /// same day keeps both (a writer that young might still be live), a
    /// sweep two days later removes both, and the next backup is whole.
    func testWhatACrashMidZipLeavesIsRemovedAfterADay() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = try SharedMediaTestFiles.makeAwkwardCourse(in: courses)
        let clock: SharedMediaTestClock = SharedMediaTestClock()
        clock.now = Date()
        let start: Date = clock.now
        let crashing: SharedMediaStore = SharedMediaStore(
            coursesDirectoryURL: courses, clock: { clock.now },
            processIsRunning: { (_: Int32, _: String?) -> Bool in false },
            hooks: SharedMediaStore.Hooks(
                reached: { (point: SharedMediaStore.WritePoint) throws in
                    if point == .zipWritten {
                        throw SharedMediaTestFiles.Stopped()
                    }
                },
                copiedIntoTheStore: { (_: URL) in },
                tidiesUpAfterAFailure: false
            )
        )
        let rules: SharedMediaStore.ArchiveRules = CourseArchiver.archiveRules(forFolderAt: course)
        XCTAssertThrowsError(try crashing.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip", rules: rules
        ))
        try Data("{}".utf8).write(to: crashing.listsURL.appendingPathComponent(".writing-left-by-a-crash"))
        let left: Int = SharedMediaTestFiles.leftoverCount(crashing, course: "ICS3U")
        XCTAssertGreaterThanOrEqual(left, 3, "an unpublished zip, a list folder and a temporary list")
        let store: SharedMediaStore = SharedMediaStore(
            coursesDirectoryURL: courses, clock: { clock.now },
            processIsRunning: { (_: Int32, _: String?) -> Bool in false }
        )
        store.sweep()
        XCTAssertEqual(SharedMediaTestFiles.leftoverCount(store, course: "ICS3U"), left, "kept the same day")
        clock.now = start.addingTimeInterval(2 * 86_400)
        XCTAssertEqual(store.sweep().leftoversRemoved, left)
        XCTAssertEqual(SharedMediaTestFiles.leftoverCount(store, course: "ICS3U"), 0)
        let healthy: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-15_183800_menu-section1_shared-media.zip", rules: rules
        )
        XCTAssertEqual(store.pathsNotHeld(by: healthy.list), [])
    }

    // MARK: - The restore door's marker (#785 implementation review, I3)

    func testADoorThatDoesNotPutTheMediaBackIsRefused() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = try SharedMediaTestFiles.makeAwkwardCourse(in: courses)
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses)
        let written: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        let staging: URL = topURL.appendingPathComponent("staging")
        XCTAssertTrue(SharedMediaTestFiles.unpack(written.zipURL, into: staging), "unpacked as CourseRestorer.unpack does")
        XCTAssertThrowsError(try SharedMediaStore.refuseUnlessItsMediaWasPutBack(
            unpackedAt: staging, backupFileName: written.list.backupName
        )) { (error: Error) in
            XCTAssertEqual(error as? SharedMediaStore.Problem, .mediaNotPutBack(written.list.backupName))
        }
        let list: SharedMediaList = try XCTUnwrap(try SharedMediaStore.list(inUnpackedBackupAt: staging))
        let restore: SharedMediaRestore = store.beginRestore(of: list, currentCourseFolderURL: nil)
        _ = try restore.fill(intoCourseAt: staging.appendingPathComponent("ICS3U"), backupFileName: list.backupName)
        restore.end()
        XCTAssertNoThrow(try SharedMediaStore.refuseUnlessItsMediaWasPutBack(
            unpackedAt: staging, backupFileName: list.backupName
        ), "once the Media is back, the door goes ahead")

        let wholeURL: URL = try wholeZip(of: course, in: courses)
        let wholeStaging: URL = topURL.appendingPathComponent("whole staging")
        XCTAssertTrue(SharedMediaTestFiles.unpack(wholeURL, into: wholeStaging))
        XCTAssertNoThrow(try SharedMediaStore.refuseUnlessItsMediaWasPutBack(
            unpackedAt: wholeStaging, backupFileName: wholeURL.lastPathComponent
        ), "a whole zip carries no marker")
    }

    /// A whole zip of the course, by the same `zip` call `CourseArchiver`
    /// makes, for a test that is not async.
    private func wholeZip(of course: URL, in courses: URL) throws -> URL {
        let zipURL: URL = topURL.appendingPathComponent("whole.zip")
        var arguments: [String] = ["-r", "-q", "-X", zipURL.path, course.lastPathComponent, "-x"]
        arguments.append(contentsOf: CourseArchiver.archiveRules(forFolderAt: course).zipExclusions)
        let result: SharedMediaStore.ProgramResult = SharedMediaStore.run("/usr/bin/zip", arguments, in: courses)
        XCTAssertEqual(result.status, 0)
        return zipURL
    }

    // MARK: - Which folder is Media (#785 implementation review, I2)

    /// Only a folder listed as exactly `Media` is left out. A course whose
    /// folder is spelled `media` keeps it in the zip, as the whole zip's
    /// case-sensitive `zip -x` does, and its list names nothing.
    func testAFolderSpelledOtherwiseStaysInTheZip() throws {
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = courses.appendingPathComponent("ICS3U")
        try SharedMediaTestFiles.write(Data("{}".utf8), to: course.appendingPathComponent("course_config.json"))
        try SharedMediaTestFiles.write(SharedMediaTestFiles.randomData(500), to: course.appendingPathComponent("media/u/p.png"))
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses)
        let written: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        XCTAssertEqual(written.list.media.count, 0)
        XCTAssertEqual(written.filesAdded, 0)
        XCTAssertTrue(SharedMediaTestFiles.zipEntries(written.zipURL).contains("ICS3U/media/u/p.png"))
    }

    // MARK: - The trail

    func testNoTrailLineNamesAMediaFile() throws {
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: topURL.appendingPathComponent("trail"))
        defer {
            ActivityTrail.store = previous
        }
        let courses: URL = topURL.appendingPathComponent("courses")
        let course: URL = try SharedMediaTestFiles.makeAwkwardCourse(in: courses)
        let clock: SharedMediaTestClock = SharedMediaTestClock()
        let store: SharedMediaStore = SharedMediaStore(coursesDirectoryURL: courses, clock: { clock.now })
        let written: SharedMediaStore.Written = try store.writeSmallBackup(
            courseFolderURL: course, courseCode: "ICS3U",
            zipName: "ICS3U_backup_2026-11-13_183800_menu-section1_shared-media.zip",
            rules: CourseArchiver.archiveRules(forFolderAt: course)
        )
        try Data(count: 10).write(to: store.fileURL(forChecksum: written.list.media[0].sha256))
        let restore: SharedMediaRestore = store.beginRestore(of: written.list, currentCourseFolderURL: nil)
        _ = try restore.fill(intoCourseAt: topURL.appendingPathComponent("staging/ICS3U"), backupFileName: written.list.backupName)
        restore.end()
        try FileManager.default.removeItem(at: written.zipURL)
        clock.now = clock.now.addingTimeInterval(2 * 86_400)
        store.sweep()
        clock.now = clock.now.addingTimeInterval(2 * 86_400)
        store.sweep()

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("keeping its Media files once"), trail)
        XCTAssertTrue(trail.contains("could not be found"), trail)
        XCTAssertTrue(trail.contains("removed"), trail)
        for file in written.list.media {
            let lastName: String = (file.path as NSString).lastPathComponent
            XCTAssertFalse(trail.contains(lastName), "the trail names \(lastName)")
        }
        XCTAssertFalse(trail.contains("Media/"), "the trail names a path inside Media")
    }
}

/// A clock a test can move.
final class SharedMediaTestClock: @unchecked Sendable {

    // MARK: - Stored properties

    var now: Date = Date(timeIntervalSince1970: 1_800_000_000)
}

/// Somewhere a hook can leave a result.
final class SharedMediaTestBox: @unchecked Sendable {

    // MARK: - Stored properties

    var result: SharedMediaStore.SweepResult?
}

/// Building and reading the folders these tests need.
enum SharedMediaTestFiles {

    // MARK: - Types

    struct Stopped: Error {
    }

    struct Node: Equatable {

        // MARK: - Stored properties

        let kind: String
        let mode: Int
        let bytes: Data?
        let modified: Date?
    }

    // MARK: - Functions

    static func randomData(_ count: Int) -> Data {
        var bytes: [UInt8] = [UInt8](repeating: 0, count: count)
        arc4random_buf(&bytes, count)
        return Data(bytes)
    }

    static func checksum(of data: Data) -> String {
        var text: String = ""
        for byte in SHA256.hash(data: data) {
            text += String(format: "%02x", byte)
        }
        return text
    }

    static func write(_ data: Data, to url: URL, mode: Int = 0o644) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        chmod(url.path, mode_t(mode))
    }

    /// A course whose Media folder has every awkward thing a teacher's can:
    /// the same picture twice, names in both Unicode forms, hidden files,
    /// what a whole zip leaves out, odd permissions, an empty file and an
    /// empty folder, a closed folder, a link and a link to nowhere, a date
    /// from another season.
    static func makeAwkwardCourse(in courses: URL) throws -> URL {
        let course: URL = courses.appendingPathComponent("ICS3U")
        try write(Data("{\"courseCode\": \"ICS3U\"}".utf8), to: course.appendingPathComponent("course_config.json"))
        try write(Data("# Day 1\n".utf8), to: course.appendingPathComponent("section1/Unit 1/Day 1.md"))
        try write(Data("x".utf8), to: course.appendingPathComponent(".DS_Store"))
        try write(randomData(5000), to: course.appendingPathComponent(".merged_output/big.bin"))
        let media: URL = course.appendingPathComponent("Media")
        let picture: Data = randomData(200_000)
        try write(picture, to: media.appendingPathComponent("a.png"))
        try write(picture, to: media.appendingPathComponent("copy of a.png"))
        try write(randomData(150_000), to: media.appendingPathComponent("sub/c.jpg"))
        try write(randomData(1000), to: media.appendingPathComponent("unit 2/\u{00E9}-composed.png"))
        try write(randomData(1000), to: media.appendingPathComponent("unit 2/e\u{0301}-decomposed.png"))
        try write(Data("hidden".utf8), to: media.appendingPathComponent(".hidden"))
        try write(Data("ds".utf8), to: media.appendingPathComponent("sub/.DS_Store"))
        try write(randomData(800), to: media.appendingPathComponent("build/left out.png"))
        try write(randomData(300), to: media.appendingPathComponent("read only.png"), mode: 0o444)
        try write(randomData(300), to: media.appendingPathComponent("private.png"), mode: 0o600)
        try write(Data(), to: media.appendingPathComponent("empty file.txt"))
        try FileManager.default.createDirectory(at: media.appendingPathComponent("empty folder"), withIntermediateDirectories: true)
        try write(randomData(100), to: media.appendingPathComponent("closed/inner/deep.png"))
        chmod(media.appendingPathComponent("closed").path, 0o700)
        // #785 implementation review, W1: a link to a sibling folder that
        // sorts first, a link to a folder outside the course, and a loop
        // (zip follows it until the system refuses more links in a path).
        try write(randomData(400), to: media.appendingPathComponent("real folder/inner.png"))
        symlink("real folder", media.appendingPathComponent("a link to the real folder").path)
        let outside: URL = courses.deletingLastPathComponent().appendingPathComponent("outside")
        try write(randomData(300), to: outside.appendingPathComponent("far.png"))
        symlink(outside.path, media.appendingPathComponent("link to outside").path)
        try write(randomData(50), to: media.appendingPathComponent("loop/f.png"))
        symlink("..", media.appendingPathComponent("loop/back up").path)
        // W2: a precomposed folder and file, made by POSIX calls so their
        // bytes stay precomposed.
        let composedFolder: String = media.path + "/caf\u{00E9}"
        mkdir(composedFolder, 0o755)
        let composedFile: Int32 = open(composedFolder + "/cr\u{00E8}me.png", O_WRONLY | O_CREAT, 0o644)
        let creme: [UInt8] = Array("creme".utf8)
        _ = Darwin.write(composedFile, creme, creme.count)
        close(composedFile)
        // #785 fix review, N1: a picture and a folder whose names BEGIN with
        // a combining mark, directly inside Media. A `/` followed by one is a
        // single Character, so a Character split read `Media/\u{0308}Bild.png`
        // as one part and refused the list.
        for path in [media.path + "/\u{0308}Bild.png", media.path + "/\u{0301}dir/\u{0301}lead.png"] {
            mkdir((path as NSString).deletingLastPathComponent, 0o755)
            let markFirst: Int32 = open(path, O_WRONLY | O_CREAT, 0o644)
            let markBytes: [UInt8] = Array("mark first".utf8)
            _ = Darwin.write(markFirst, markBytes, markBytes.count)
            close(markFirst)
        }
        symlink("a.png", media.appendingPathComponent("link to a.png").path)
        symlink("/nonexistent/nowhere.png", media.appendingPathComponent("broken link.png").path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)],
            ofItemAtPath: media.appendingPathComponent("sub/c.jpg").path
        )
        return course
    }

    static func unpack(_ zipURL: URL, into folder: URL) -> Bool {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return SharedMediaStore.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, folder.path], in: folder).status == 0
    }

    static func zipEntries(_ zipURL: URL) -> String {
        let result: SharedMediaStore.ProgramResult = SharedMediaStore.run(
            "/usr/bin/unzip", ["-Z1", zipURL.path], in: zipURL.deletingLastPathComponent()
        )
        return String(data: result.output, encoding: .utf8) ?? ""
    }

    /// Every entry under `top`, keyed by its name BYTES, read with the
    /// folder's own listing.
    static func tree(_ top: URL) -> [[UInt8]: Node] {
        var found: [[UInt8]: Node] = [:]
        guard let folder = SharedMediaFiles.Folder(path: top.path) else {
            return found
        }
        var waiting: [String] = [""]
        while let relative = waiting.popLast() {
            let listing: String = relative.isEmpty ? "." : relative
            guard let names = SharedMediaFiles.names(in: folder, at: listing) else {
                continue
            }
            for name in names {
                let path: String = relative.isEmpty ? name : relative + "/" + name
                var status: stat = stat()
                if fstatat(folder.descriptor, path, &status, AT_SYMLINK_NOFOLLOW) != 0 {
                    continue
                }
                let kind: mode_t = status.st_mode & S_IFMT
                let mode: Int = Int(status.st_mode & 0o7777)
                if kind == S_IFDIR {
                    found[Array(path.utf8)] = Node(kind: "folder", mode: mode, bytes: nil, modified: nil)
                    waiting.append(path)
                } else if kind == S_IFLNK {
                    found[Array(path.utf8)] = Node(kind: "link", mode: mode, bytes: nil, modified: nil)
                } else {
                    var data: Data = Data()
                    let opened: Int32 = openat(folder.descriptor, path, O_RDONLY)
                    if opened >= 0 {
                        data = FileHandle(fileDescriptor: opened, closeOnDealloc: true).readDataToEndOfFile()
                    }
                    let facts: SharedMediaFiles.Facts? = SharedMediaFiles.facts(in: folder, at: path)
                    found[Array(path.utf8)] = Node(kind: "file", mode: mode, bytes: data, modified: facts?.modified)
                }
            }
        }
        return found
    }

    /// A name's bytes as text a failure message can show, every byte
    /// outside plain ASCII written as `\xNN`.
    static func shown(_ bytes: [UInt8]) -> String {
        var text: String = ""
        for byte in bytes {
            if byte >= 32 && byte < 127 {
                text.append(Character(UnicodeScalar(byte)))
            } else {
                text += String(format: "\\x%02x", byte)
            }
        }
        return text
    }

    /// Names (by their bytes), kinds, bytes and permissions that differ.
    /// Dates are compared apart, against the original files.
    static func differences(_ small: [[UInt8]: Node], _ whole: [[UInt8]: Node]) -> [String] {
        var found: [String] = []
        var names: Set<[UInt8]> = []
        for (name, _) in small {
            names.insert(name)
        }
        for (name, _) in whole {
            names.insert(name)
        }
        var ordered: [[UInt8]] = []
        for name in names {
            ordered.append(name)
        }
        ordered.sort { (first: [UInt8], second: [UInt8]) -> Bool in
            return first.lexicographicallyPrecedes(second)
        }
        for key in ordered {
            let name: String = shown(key)
            guard let mine = small[key] else {
                found.append("only in the whole restore: \(name)")
                continue
            }
            guard let theirs = whole[key] else {
                found.append("only in the small restore: \(name)")
                continue
            }
            if mine.kind != theirs.kind {
                found.append("\(name): \(mine.kind) against \(theirs.kind)")
            }
            if mine.mode != theirs.mode {
                found.append("\(name): mode \(String(mine.mode, radix: 8)) against \(String(theirs.mode, radix: 8))")
            }
            if mine.bytes != theirs.bytes {
                found.append("\(name): different bytes")
            }
        }
        return found
    }

    /// What a crash leaves that names nothing: unpublished zips in the
    /// course's backups folder, list folders and temporaries in the store.
    static func leftoverCount(_ store: SharedMediaStore, course: String) -> Int {
        var count: Int = 0
        let fileManager: FileManager = FileManager.default
        let folders: [URL] = [
            store.backupsURL.appendingPathComponent(course), store.storeURL, store.listsURL, store.pendingURL,
        ]
        for folder in folders {
            for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] {
                if name.hasPrefix(".writing-") || name.hasPrefix(".incoming-") {
                    count += 1
                }
            }
        }
        return count
    }

    static func everySmallBackupIsWhole(_ store: SharedMediaStore, course: String) throws -> Bool {
        let folder: URL = store.backupsURL.appendingPathComponent(course)
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where SharedMediaStore.isSmallBackupName(name) {
            let list: SharedMediaList = try SharedMediaStore.list(insideZipAt: folder.appendingPathComponent(name))
            if !store.pathsNotHeld(by: list).isEmpty {
                return false
            }
        }
        return true
    }

    static func storeEntryCount(_ store: SharedMediaStore) -> Int {
        var count: Int = 0
        let fileManager: FileManager = FileManager.default
        let groups: [String] = (try? fileManager.contentsOfDirectory(atPath: store.filesURL.path)) ?? []
        for group in groups {
            let names: [String] = (try? fileManager.contentsOfDirectory(
                atPath: store.filesURL.appendingPathComponent(group).path
            )) ?? []
            count += names.count
        }
        return count
    }
}
