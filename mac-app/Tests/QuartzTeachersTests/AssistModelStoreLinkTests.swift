import XCTest
@testable import QuartzTeachers

/// Weights reached through a symbolic link count as downloaded (#154): the
/// UI tests link the real weights into a state folder one file at a time,
/// and a check that measured the LINK saw a few bytes and called it a
/// truncated download — the assistant then never became ready.
@MainActor
final class AssistModelStoreLinkTests: XCTestCase {

    // MARK: - Stored properties

    private var savedOverride: URL?
    private var scratch: URL = URL(fileURLWithPath: "/")

    // MARK: - Set-up

    override func setUp() {
        super.setUp()
        savedOverride = AssistModelStore.directoryOverride
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-link-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        AssistModelStore.directoryOverride = savedOverride
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    // MARK: - The test

    func testALinkedFileOfTheRightSizeIsReady() throws {
        let tier: AssistModelTier = .small
        let realFolder: URL = scratch.appendingPathComponent("real", isDirectory: true)
        let linkFolder: URL = scratch.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkFolder, withIntermediateDirectories: true)
        // A sparse file of exactly the right size: costs no disk.
        let real: URL = realFolder.appendingPathComponent(tier.fileName)
        FileManager.default.createFile(atPath: real.path, contents: nil)
        let handle: FileHandle = try FileHandle(forWritingTo: real)
        try handle.truncate(atOffset: UInt64(tier.downloadBytes))
        try handle.close()
        try FileManager.default.createSymbolicLink(
            at: linkFolder.appendingPathComponent(tier.fileName), withDestinationURL: real
        )
        AssistModelStore.directoryOverride = linkFolder
        XCTAssertTrue(AssistModelStore(tier: tier).isReady)
        XCTAssertEqual(AssistModelStore.bytesOnDisk(for: tier), tier.downloadBytes)
    }
}
