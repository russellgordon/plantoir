import XCTest
@testable import QuartzTeachers

/// The scan the install gate falls back on (#204), against real processes:
/// a copy of `/bin/sh` renamed `Plantoir` in a scratch folder, started the
/// way launchd starts a scheduled publish and the way an assistant working
/// from another app starts the server. Every child is ended by its own
/// process id in `tearDown`.
@MainActor
final class SameExecutableProcessesTests: XCTestCase {

    // MARK: - Stored properties

    private var folder: URL?
    private var children: [Process] = []

    // MARK: - Set up

    override func tearDown() async throws {
        for child in children {
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
                child.waitUntilExit()
            }
        }
        children = []
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: - Tests

    func testFindsAndClassifiesOtherCopiesOfTheSameExecutable() throws {
        let executable: URL = try makeFakePlantoir()
        let scheduled: Process = try start(executable, [
            "-c", "sleep 30; :", ScheduledDeploy.runFlag, "/w/.scheduled/deploy.sh",
            ScheduledDeploy.sectionFlag, "/w", "EXC2O", "1"
        ])
        let server: Process = try start(executable, ["-c", "sleep 30; :", AssistMCPServer.flag, "/f"])

        let sightings: [SameExecutableProcesses.Sighting] = SameExecutableProcesses.sightings(
            ofExecutableAt: executable.path
        )
        var byPID: [Int32: UpdateGate.OtherCopy] = [:]
        for sighting in sightings {
            byPID[sighting.pid] = UpdateGate.classify(pid: sighting.pid, arguments: sighting.arguments)
        }
        XCTAssertEqual(sightings.count, 2)

        let asScheduled: UpdateGate.OtherCopy = try XCTUnwrap(byPID[scheduled.processIdentifier])
        XCTAssertEqual(asScheduled.kind, .scheduledPublish)
        XCTAssertEqual(asScheduled.courseCode, "EXC2O")
        XCTAssertEqual(asScheduled.sectionNumber, 1)
        XCTAssertEqual(asScheduled.folderPath, "/w")

        let asServer: UpdateGate.OtherCopy = try XCTUnwrap(byPID[server.processIdentifier])
        XCTAssertEqual(asServer.kind, .assistantFromAnotherApp)
        XCTAssertEqual(asServer.folderPath, "/f")
    }

    /// The scan compares resolved paths: a scratch folder under
    /// `/var/folders` is `/private/var/folders` to the kernel.
    func testOneExecutableIsNeverTwoSpellings() throws {
        let executable: URL = try makeFakePlantoir()
        let child: Process = try start(executable, ["-c", "sleep 30; :"])
        let resolved: String = SameExecutableProcesses.resolved(executable.path)
        for spelling in [executable.path, resolved] {
            var pids: [Int32] = []
            for sighting in SameExecutableProcesses.sightings(ofExecutableAt: spelling) {
                pids.append(sighting.pid)
            }
            XCTAssertEqual(pids, [child.processIdentifier], spelling)
        }
    }

    /// A different copy of Plantoir is never this one: installing this copy
    /// does not touch it.
    func testADifferentExecutableIsNotSeen() throws {
        let executable: URL = try makeFakePlantoir()
        _ = try start(executable, ["-c", "sleep 30; :", ScheduledDeploy.runFlag, "s"])
        let elsewhere: URL = try makeFakePlantoir(named: "Elsewhere")
        XCTAssertEqual(SameExecutableProcesses.sightings(ofExecutableAt: elsewhere.path), [])
    }

    func testThisProcessIsNeverReported() throws {
        let own: String = try XCTUnwrap(Bundle.main.executablePath)
        for sighting in SameExecutableProcesses.sightings(ofExecutableAt: own) {
            XCTAssertNotEqual(sighting.pid, getpid())
        }
    }

    /// A pre-v1.2.0 job names no section: still a scheduled publish, with no
    /// course to name.
    func testAScheduledPublishWithNoSectionIsStillOne() {
        let copy: UpdateGate.OtherCopy = UpdateGate.classify(
            pid: 42, arguments: ["Plantoir", ScheduledDeploy.runFlag, "/old/deploy.sh"]
        )
        XCTAssertEqual(copy.kind, .scheduledPublish)
        XCTAssertNil(copy.courseCode)
        XCTAssertNil(copy.sectionNumber)
    }

    // MARK: - When a process ends

    func testAnEndingIsHeard() async throws {
        let executable: URL = try makeFakePlantoir()
        let child: Process = try start(executable, ["-c", "sleep 30; :"])
        let ends: AsyncStream<Void> = ProcessEnding.ends(of: child.processIdentifier)
        kill(child.processIdentifier, SIGTERM)
        var heard: Bool = false
        for await _ in ends {
            heard = true
        }
        XCTAssertTrue(heard)
    }

    func testAProcessAlreadyGoneIsHeardAtOnce() async throws {
        let executable: URL = try makeFakePlantoir()
        let child: Process = try start(executable, ["-c", ":"])
        child.waitUntilExit()
        var heard: Bool = false
        for await _ in ProcessEnding.ends(of: child.processIdentifier) {
            heard = true
        }
        XCTAssertTrue(heard)
    }

    // MARK: - Helpers

    private func makeFakePlantoir(named name: String = "Plantoir") throws -> URL {
        let base: URL
        if let folder {
            base = folder
        } else {
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("same-executable-\(UUID().uuidString)", isDirectory: true)
            folder = base
        }
        let place: URL = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        let executable: URL = place.appendingPathComponent("Plantoir")
        if !FileManager.default.fileExists(atPath: executable.path) {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sh"), to: executable)
        }
        return executable
    }

    private func start(_ executable: URL, _ arguments: [String]) throws -> Process {
        let process: Process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        children.append(process)
        return process
    }
}
