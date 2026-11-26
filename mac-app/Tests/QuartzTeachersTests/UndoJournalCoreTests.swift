import XCTest
@testable import QuartzTeachers

/// The journal core's own pieces (#899, U1, after its reviews): the fold read
/// on from where it stopped, the identifier file, the lock, a closed step's
/// staged files, and a segment with no time. The
/// work is in `UndoCoreChecks`, which the standalone harness runs too.
///
/// Everything happens in folders under the temporary directory.
final class UndoJournalCoreTests: XCTestCase {

    // MARK: - Stored properties

    var scratchURL: URL = FileManager.default.temporaryDirectory

    // MARK: - Setting up

    override func setUp() {
        scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-core-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        // Given back even when a test failed before its own clean-up.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: UndoCoreChecks.unlistableParent(under: scratchURL).path
        )
        try? FileManager.default.removeItem(at: scratchURL)
    }

    // MARK: - Tests

    /// MUST FAIL on 96bcadbcc, which re-read every segment on every lock
    /// (it had no `UndoFoldCache` at all, so this does not compile there).
    func testTheFoldIsReadOnFromWhereItStopped() throws {
        XCTAssertEqual(try UndoCoreChecks.foldReadsOnFromWhereItStopped(under: scratchURL), [])
    }

    /// MUST FAIL on 96bcadbcc: a damaged `folder-id` threw for ever.
    func testTheIdentifierFileNeverBlocksForGood() throws {
        XCTAssertEqual(try UndoCoreChecks.identifierFileNeverBlocksForGood(under: scratchURL), [])
    }

    /// MUST FAIL on a6796be95, whose pruning closed the step and left its
    /// staged file in the course for good.
    func testAClosedStepLeavesNoStagedFile() throws {
        XCTAssertEqual(try UndoCoreChecks.aClosedStepLeavesNoStagedFile(under: scratchURL), [])
    }

    /// MUST FAIL on a6796be95, which kept a segment holding no time, and
    /// every segment after it, for good.
    func testASegmentWithNoTimeIsBounded() throws {
        XCTAssertEqual(try UndoCoreChecks.aSegmentWithNoTimeIsBounded(under: scratchURL), [])
    }

    func testTheLockWaitsForTheGrant() throws {
        XCTAssertEqual(try UndoCoreChecks.lockWaitsForTheGrant(under: scratchURL), [])
    }

    /// F1 of the Fable sweep of U1.
    func testAStagingWriteThatFailsLeavesNothing() throws {
        XCTAssertEqual(try UndoCoreChecks.aStagingWriteThatFailsLeavesNothing(under: scratchURL), [])
    }

    /// F4 of the Fable sweep of U1.
    func testAReadThatFailsIsAnUnreadableList() throws {
        XCTAssertEqual(try UndoCoreChecks.aReadThatFailsIsAnUnreadableList(under: scratchURL), [])
    }

    /// The review of U2a: MEDIUM, a segment that cannot be opened.
    func testASegmentThatCannotBeOpenedIsAnUnreadableList() throws {
        XCTAssertEqual(try UndoCoreChecks.aSegmentThatCannotBeOpenedIsAnUnreadableList(under: scratchURL), [])
    }

    /// The review of U2a's sweep: a blob that cannot be read.
    func testABlobThatCannotBeReadLeavesTheListAlone() throws {
        XCTAssertEqual(try UndoCoreChecks.aBlobThatCannotBeReadLeavesTheListAlone(under: scratchURL), [])
    }

    /// The review of U2a's sweep: the folder's identifier file.
    func testAnIdentifierThatCannotBeReadIsNotSetAside() throws {
        XCTAssertEqual(try UndoCoreChecks.anIdentifierThatCannotBeReadIsNotSetAside(under: scratchURL), [])
    }

    /// The review of U2a: LOW 1.
    func testKeepingTheOriginalWithNoRoomIsCouldNotWrite() throws {
        XCTAssertEqual(try UndoCoreChecks.keepingTheOriginalWithNoRoomIsCouldNotWrite(under: scratchURL), [])
    }

    /// The review of U2a: LOW 2.
    func testALaterOpOnAPathWithMissingContentIsNotJudgedStale() throws {
        XCTAssertEqual(try UndoCoreChecks.aLaterOpOnAPathWithMissingContentIsNotJudgedStale(under: scratchURL), [])
    }

    /// #1004-a, gap 1. MUST FAIL on 0e12bc8ac, which took the file number
    /// by a second look at the name and moved the good file aside.
    func testAFolderIDReplacedByAGoodOneIsNeverSetAside() throws {
        XCTAssertEqual(try UndoCoreChecks.aFolderIDReplacedByAGoodOneIsNeverSetAside(under: scratchURL), [])
    }

    /// #1004-a, gap 1: the file moved is confirmed to be the file read.
    func testAFileThatIsNotTheOneReadIsPutBack() throws {
        XCTAssertEqual(try UndoCoreChecks.aFileThatIsNotTheOneReadIsPutBack(under: scratchURL), [])
    }

    /// #1004-a, gap 2. MUST FAIL on 0e12bc8ac, which passed over the newest
    /// segment gone after the listing (the older half passes there).
    func testTheNewestSegmentGoneAfterTheListingIsAnUnreadableList() throws {
        XCTAssertEqual(try UndoCoreChecks.theNewestSegmentGoneAfterTheListingIsAnUnreadableList(under: scratchURL), [])
    }

    /// #1004-a, item 3. MUST FAIL on 0e12bc8ac, which asked fileExists and
    /// read an unlistable folder as no segments.
    func testAListFolderThatCannotBeListedIsUnreadable() throws {
        XCTAssertEqual(try UndoCoreChecks.aListFolderThatCannotBeListedIsUnreadable(under: scratchURL), [])
    }
}
