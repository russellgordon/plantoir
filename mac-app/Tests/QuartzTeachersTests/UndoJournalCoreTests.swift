import XCTest
@testable import QuartzTeachers

/// The journal core's own pieces (#899, U1, after its two reviews): the fold
/// read on from where it stopped, the identifier file, and the lock. The
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

    func testTheLockWaitsForTheGrant() throws {
        XCTAssertEqual(try UndoCoreChecks.lockWaitsForTheGrant(under: scratchURL), [])
    }
}
