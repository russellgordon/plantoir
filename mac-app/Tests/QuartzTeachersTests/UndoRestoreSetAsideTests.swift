import XCTest
@testable import QuartzTeachers

/// A whole-course restore settles every Undo step left in flight in that
/// course before it moves anything (#899, ahead of U5:
/// `UndoRestoreSetAside`), so recovery at a later launch never judges the
/// RESTORED course against a step that stopped before the restore.
@MainActor
final class UndoRestoreSetAsideTests: XCTestCase {

    // MARK: - Stored properties

    private let offerTests: StartOfYearRestoreOfferTests = StartOfYearRestoreOfferTests()

    // MARK: - Set up

    override func setUp() async throws {
        try await offerTests.setUp()
    }

    override func tearDown() async throws {
        try await offerTests.tearDown()
    }

    // MARK: - The case end to end

    /// Get Ready stops part way, Restore Course, Get Ready again, the app
    /// "dies", recovery runs as at the next launch: exactly one Get Ready on
    /// the list, and every file of the course as the second run left it.
    /// MUST FAIL on b76065661, where the restore left the first step in
    /// flight and recovery closed it as made over the second run's files.
    func testAStepStoppedBeforeARestoreIsNeverJudgedAgainstTheRestoredCourse() async throws {
        let stopped: StartOfYearRestoreOfferTests.Stopped = try await offerTests.stopPartWay(sections: [1])
        defer { try? FileManager.default.removeItem(at: stopped.root) }
        let journal: UndoJournal = UndoJournalLocation.standardJournal()
        let baseline: Int = UndoRestoreSetAsideTests.highestSeq(in: try journal.read())

        try await stopped.goAhead()
        let folderID: String = try XCTUnwrap(FolderIdentityFile.existingIdentifier(forWorkingFolder: stopped.root))
        let firstSteps: [UndoStepRecord] = UndoRestoreSetAsideTests.steps(in: try journal.read(), after: baseline, folderID: folderID)
        let inFlightBefore: Int = UndoRestoreSetAsideTests.countInFlight(firstSteps)
        XCTAssertEqual(inFlightBefore, 1, "Get Ready's stopped step is in flight before the restore")

        await stopped.model.restoreCourse()
        XCTAssertNil(stopped.workspace.backupProblem, stopped.workspace.backupProblem ?? "")
        let afterRestore: [UndoStepRecord] = UndoRestoreSetAsideTests.steps(in: try journal.read(), after: baseline, folderID: folderID)
        XCTAssertEqual(UndoRestoreSetAsideTests.countInFlight(afterRestore), 0, "the restore left a step in flight")
        let trail: String = ActivityTrail.store.activityText(includingPrompts: false)
        let pieces: [String] = trail.components(separatedBy: "because a restore is replacing the course; it is not judged again")
        XCTAssertEqual(pieces.count - 1, 1, "one trail line for the step set aside: \(trail)")

        // Get Ready again, all the way, on the restored course.
        stopped.workspace.reloadCourses()
        var restoredCourse: Course? = nil
        for course in stopped.workspace.courses where course.code == stopped.course.code {
            restoredCourse = course
        }
        let second: StartOfYearSheetModel = StartOfYearSheetModel(
            course: try XCTUnwrap(restoredCourse), sectionNumber: 1, workspaceURL: stopped.root, mode: .getReady,
            restoreWholeCourse: { (_: BackupItem) async in }
        )
        second.load()
        await second.goAhead()
        let courseFolder: URL = stopped.root.appendingPathComponent("courses").appendingPathComponent(stopped.course.code)
        let asTheSecondRunLeftIt: [String: Data] = try StartOfYearRestoreOfferTests.everyFile(under: courseFolder)

        // The app "dies": recovery runs as another process would at launch.
        let atLaunch: UndoJournal = UndoJournal(folderURL: journal.folderURL, processIsAlive: { (_: UndoProcess) -> Bool in false })
        let root: URL = stopped.root
        await UndoRecovery.recoverAndRederive(atLaunch, resolveRoot: { (_: UndoWorkingFolder) -> URL? in root })

        let settled: [UndoStepRecord] = UndoRestoreSetAsideTests.steps(in: try atLaunch.read(), after: baseline, folderID: folderID)
        var done: Int = 0
        for record in settled where record.phase == .done {
            done += 1
        }
        XCTAssertEqual(done, 1, "exactly one Get Ready on the list: \(UndoRestoreSetAsideTests.phases(settled))")
        XCTAssertEqual(UndoRestoreSetAsideTests.countInFlight(settled), 0)
        let afterRecovery: [String: Data] = try StartOfYearRestoreOfferTests.everyFile(under: courseFolder)
        XCTAssertEqual(afterRecovery.keys.sorted(), asTheSecondRunLeftIt.keys.sorted())
        for (path, bytes) in asTheSecondRunLeftIt {
            XCTAssertEqual(afterRecovery[path], bytes, "\(path) is not as the second Get Ready left it")
        }
    }

    // MARK: - Which steps a restore sets aside

    /// Only a step made in this working folder and naming a file inside what
    /// the restore replaces: another course's step, or one made in another
    /// working folder, is never touched.
    func testOnlyStepsInsideWhatTheRestoreReplacesAreSetAside() {
        let here: UndoWorkingFolder = UndoWorkingFolder(id: "aaaa", pathAtTheTime: "/w")
        let elsewhere: UndoWorkingFolder = UndoWorkingFolder(id: "bbbb", pathAtTheTime: "/v")
        let inside: UndoStep = UndoRestoreSetAsideTests.step(writing: "courses/ICS3U/section1/a.md", in: here)
        let otherCourse: UndoStep = UndoRestoreSetAsideTests.step(writing: "courses/ICS3UX/section1/a.md", in: here)
        let otherFolder: UndoStep = UndoRestoreSetAsideTests.step(writing: "courses/ICS3U/section1/a.md", in: elsewhere)
        let replaced: [String] = ["courses/ICS3U"]
        XCTAssertTrue(UndoRestoreSetAside.isMade(inside, inWorkingFolder: "AAAA"))
        XCTAssertEqual(UndoRestoreSetAside.pathsInside(inside, replaced: replaced).inside, ["courses/ICS3U/section1/a.md"])
        XCTAssertEqual(UndoRestoreSetAside.pathsInside(otherCourse, replaced: replaced).inside, [])
        XCTAssertFalse(UndoRestoreSetAside.isMade(otherFolder, inWorkingFolder: "aaaa"))
    }

    // MARK: - Helpers

    static func step(writing path: String, in folder: UndoWorkingFolder) -> UndoStep {
        let op: UndoOp = UndoOp(kind: "writeFile", path: path)
        return UndoStep(
            seq: 1, madeAt: "2026-11-27T00:00:00Z", action: nil, madeBy: nil, workingFolder: folder,
            course: "ICS3U", section: 1, actionClass: nil, holds: nil, ops: [op]
        )
    }

    static func highestSeq(in fold: UndoFold) -> Int {
        var highest: Int = 0
        for seq in fold.orderedSeqs where seq > highest {
            highest = seq
        }
        return highest
    }

    static func steps(in fold: UndoFold, after baseline: Int, folderID: String) -> [UndoStepRecord] {
        var found: [UndoStepRecord] = []
        for seq in fold.orderedSeqs where seq > baseline {
            if let record = fold.records[seq], record.step.workingFolder?.id.lowercased() == folderID.lowercased() {
                found.append(record)
            }
        }
        return found
    }

    static func countInFlight(_ records: [UndoStepRecord]) -> Int {
        var count: Int = 0
        for record in records where record.phase.isInFlight {
            count += 1
        }
        return count
    }

    static func phases(_ records: [UndoStepRecord]) -> [String] {
        var result: [String] = []
        for record in records {
            result.append("\(record.step.seq):\(record.phase.rawValue)")
        }
        return result
    }
}
