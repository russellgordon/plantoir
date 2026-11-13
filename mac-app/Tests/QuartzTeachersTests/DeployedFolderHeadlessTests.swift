import AppKit
import XCTest
@testable import QuartzTeachers

/// `Plantoir --serve-deployed-folder` never becomes an application (#850's
/// fix round, HIGH). It runs from `verify.sh` and other checks while the
/// teacher works, so it must show no Dock icon, never take the key window,
/// always print its one line, and leave when its input closes or it is told
/// to end. Proved from OUTSIDE the process: the test starts this very
/// binary (the test host is Plantoir) as a child and asks the system about
/// it.
///
/// On faac3da1b the flag was read inside `QuartzTeachersApp.init`, inside
/// SwiftUI's `App.main`, where an `NSApplication` MAY already exist; whether
/// it did is not yet measured (`browser-checks/check_headless_modes.py` on
/// that commit's bundle settles it). It is now decided in `PlantoirMain`
/// before any, so this test holds the fix whatever that measurement says.
///
/// The child is started with the test host's environment stripped of
/// everything XCTest and the loader put there (`childEnvironment()`): this
/// test host is the same executable, and `XCInjectBundleInto` names it, so
/// otherwise the child could load the test bundle and not be the process
/// `verify.sh` starts (the fix review's M-a). Every read of its output is
/// bounded, so a child that prints nothing fails the test in bounded time
/// rather than hanging it (M-b).
@MainActor
final class DeployedFolderHeadlessTests: XCTestCase {

    // MARK: - Types

    /// A started child and what it printed.
    struct Child {
        var process: Process
        var input: Pipe
        var firstLine: String?
    }

    // MARK: - Functions

    /// The app's own executable.
    static func executable() throws -> URL {
        let url: URL = try XCTUnwrap(Bundle.main.executableURL)
        XCTAssertEqual(url.lastPathComponent, "Plantoir", "the test host is not Plantoir")
        return url
    }

    /// A folder with a front page.
    static func makeFolder() throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deployed-folder-headless-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("home".utf8).write(to: folder.appendingPathComponent("index.html"))
        return folder
    }

    /// The environment the child is started with: the test host's, less
    /// every `DYLD_*`, `XC*` and `__XPC_*` key.
    static func childEnvironment() -> [String: String] {
        var environment: [String: String] = [:]
        for (key, value) in ProcessInfo.processInfo.environment {
            if key.hasPrefix("DYLD_") || key.hasPrefix("XC") || key.hasPrefix("__XPC_") || key.hasPrefix("OS_ACTIVITY_DT") {
                continue
            }
            environment[key] = value
        }
        return environment
    }

    /// Starts the child and waits at most `seconds` for its first line.
    static func start(serving folder: URL, seconds: Double) throws -> Child {
        let process: Process = Process()
        process.executableURL = try executable()
        process.arguments = [DeployedFolderCommandLine.flag, folder.path]
        process.environment = childEnvironment()
        let input: Pipe = Pipe()
        let output: Pipe = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let collected: LineCollector = LineCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            collected.add(handle.availableData)
        }
        try process.run()
        let deadline: Date = Date().addingTimeInterval(seconds)
        while Date() < deadline && collected.firstLine() == nil {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        output.fileHandleForReading.readabilityHandler = nil
        return Child(process: process, input: input, firstLine: collected.firstLine())
    }

    /// Whether the child has gone within `seconds`.
    static func ends(_ process: Process, within seconds: Double) -> Bool {
        let deadline: Date = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !process.isRunning {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return !process.isRunning
    }

    /// Whether the system knows the child as an application at all.
    static func isAnApplication(_ pid: pid_t) -> Bool {
        if NSRunningApplication(processIdentifier: pid) != nil {
            return true
        }
        for application in NSWorkspace.shared.runningApplications {
            if application.processIdentifier == pid {
                return true
            }
        }
        return false
    }

    // MARK: - Tests

    func testItPrintsItsLineIsNoApplicationAndLeavesWhenItsInputCloses() throws {
        let folder: URL = try DeployedFolderHeadlessTests.makeFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let frontBefore: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let child: Child = try DeployedFolderHeadlessTests.start(serving: folder, seconds: 15)
        defer {
            if child.process.isRunning {
                child.process.terminate()
            }
        }
        let line: String = try XCTUnwrap(child.firstLine, "it printed nothing within 15 s")
        XCTAssertTrue(line.hasPrefix(DeployedFolderCommandLine.readyPrefix), "it printed \(line)")
        let pid: pid_t = child.process.processIdentifier

        XCTAssertFalse(DeployedFolderHeadlessTests.isAnApplication(pid), "the headless server is a running application")
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, pid, "it took the front")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontBefore, "the front application changed")

        try child.input.fileHandleForWriting.close()
        XCTAssertTrue(DeployedFolderHeadlessTests.ends(child.process, within: 5), "it outlived its input")
    }

    func testItLeavesWhenToldToEnd() throws {
        let folder: URL = try DeployedFolderHeadlessTests.makeFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let child: Child = try DeployedFolderHeadlessTests.start(serving: folder, seconds: 15)
        XCTAssertNotNil(child.firstLine, "it printed nothing within 15 s")
        child.process.terminate()
        XCTAssertTrue(DeployedFolderHeadlessTests.ends(child.process, within: 5), "it did not end on TERM")
    }

    func testAFolderThatIsNotThereGetsItsFailedLineAndAnExit() throws {
        let missing: URL = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")
        let child: Child = try DeployedFolderHeadlessTests.start(serving: missing, seconds: 15)
        defer {
            if child.process.isRunning {
                child.process.terminate()
            }
        }
        let line: String = try XCTUnwrap(child.firstLine, "it printed nothing within 15 s")
        XCTAssertTrue(line.hasPrefix(DeployedFolderCommandLine.failedPrefix), "it printed \(line)")
        XCTAssertTrue(DeployedFolderHeadlessTests.ends(child.process, within: 5), "it stayed after failing")
        XCTAssertNotEqual(child.process.terminationStatus, 0)
    }
}

/// What the child printed, gathered on the pipe's own queue and read from
/// the test, so a read never blocks.
nonisolated final class LineCollector: @unchecked Sendable {

    // MARK: - Stored properties

    private let lock: NSLock = NSLock()
    private var data: Data = Data()

    // MARK: - Functions

    func add(_ more: Data) {
        lock.lock()
        data.append(more)
        lock.unlock()
    }

    /// The first whole line, or nil until one has arrived.
    func firstLine() -> String? {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard let end = data.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        return String(decoding: data[data.startIndex..<end], as: UTF8.self)
    }
}
