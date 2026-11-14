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
        _ = try StagedRestore.make(fixture, phase: .done, movesMade: Int.max)

        let said: [String] = WholeCourseRestore.settleUnfinishedRestores(in: fixture.coursesDirectoryURL)

        XCTAssertEqual(
            try WholeCourseFixture.snapshot(of: fixture.courseURL),
            fixture.backupWithWhatIsKeptInPlace(liveGit: live[".git/HEAD"])
        )
        XCTAssertEqual(said, [])
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
        XCTAssertTrue(said[0].hasSuffix(RestoreWholeCourseWording.notInTheSidebar(course: "ICS3U")), said[0])
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
        writtenAt: Date = Date()
    ) throws -> StagedRestore {
        let fileManager: FileManager = FileManager.default
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
        let record: RestoreSwap.Record = RestoreSwap.Record(
            course: "ICS3U",
            backup: fixture.zipURL.lastPathComponent,
            archive: nil,
            phase: phase,
            moves: moves,
            computer: computer,
            owner: try StagedRestore.goneOwner(),
            writtenAt: RestoreSettle.momentText(writtenAt)
        )
        try RestoreSwap.writeRecord(record, to: staging.appendingPathComponent(RestoreSwap.recordName), flushes: false)
        var made: Int = 0
        for move in moves where made < movesMade {
            let to: URL = RestoreSwap.absolute(move.to, in: fixture.coursesDirectoryURL)
            try fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: RestoreSwap.absolute(move.from, in: fixture.coursesDirectoryURL), to: to)
            made += 1
        }
        return StagedRestore(stagingURL: staging, moves: moves)
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
