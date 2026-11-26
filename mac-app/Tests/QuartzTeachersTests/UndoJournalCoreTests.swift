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

    // MARK: - Computed properties

    /// A course folder for the published-pages record tests (#1004-b).
    var courseFolder: URL {
        return scratchURL.appendingPathComponent("courses/TST1O", isDirectory: true)
    }

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
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: recordFolder(ofCourse: courseFolder).path
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

    // MARK: - Functions

    /// `courses/TST1O/.publish_state/section1.published-pages`.
    func recordFolder(ofCourse course: URL) -> URL {
        return course
            .appendingPathComponent(".publish_state", isDirectory: true)
            .appendingPathComponent("section1.published-pages", isDirectory: true)
    }

    /// #1004-b, gap 3. MUST FAIL with `readRecord` back to `try?`, which
    /// read a folder that is there and cannot be listed as no fragments.
    func testAPublishedPagesFolderThatCannotBeListedIsNotNoFragments() throws {
        let folder: URL = recordFolder(ofCourse: courseFolder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{\"version\": 1, \"places\": [\"Section 1/index\"]}\n".utf8)
            .write(to: folder.appendingPathComponent("20261113T090000Z-netlify.json"))
        XCTAssertEqual(UndoWebsite.readRecord(courseFolder: courseFolder, section: 1)?.count, 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        XCTAssertNil(UndoWebsite.readRecord(courseFolder: courseFolder, section: 1), "a folder that cannot be listed is not []")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
    }

    /// #1004-b: a folder that is not there is no fragments, and so is a
    /// file where the folder would be (`ENOTDIR`). Passes on the base too.
    func testAPublishedPagesFolderThatIsNotThereIsNoFragments() throws {
        XCTAssertEqual(UndoWebsite.readRecord(courseFolder: courseFolder, section: 1), [])
        let folder: URL = recordFolder(ofCourse: courseFolder)
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: folder)
        XCTAssertEqual(UndoWebsite.readRecord(courseFolder: courseFolder, section: 1), [])
    }
}
