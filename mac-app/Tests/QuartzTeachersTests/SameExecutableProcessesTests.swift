import XCTest
@testable import QuartzTeachers

/// The scan the install gate falls back on (#204), against real processes:
/// a copy of `/bin/bash` renamed `Plantoir` in a scratch folder, started the
/// way launchd starts a scheduled publish and the way an assistant working
/// from another app starts the server. Every child is ended by its own
/// process id in `tearDown`.
///
/// Why bash, re-signed, waiting on `read` (#341, measured on an M4 Pro,
/// macOS 26.6): an unsigned copy of a system binary run from a temporary
/// folder is SIGKILLed by the system within about 1–100 ms (60 of 60 copies
/// of `/bin/sh`, 10 of 10 of `/bin/bash`), so these tests used to pass only
/// by scanning before the kill. Re-signed ad hoc, a copy of bash stays alive
/// (20 of 20 seen at 500 ms); a re-signed copy of `/bin/sh` stays alive but is
/// never seen (0 of 10), because `/bin/sh` is a trampoline that execs bash and
/// stops being "Plantoir". `read` forks nothing, where `sleep` would briefly
/// fork a second "Plantoir"; it waits on a pipe the test holds until
/// `tearDown`, since a released pipe is end-of-file and bash exits.
@MainActor
final class SameExecutableProcessesTests: XCTestCase {

    // MARK: - Stored properties

    private var folder: URL?
    private var children: [Process] = []
    /// Each child's standard input. Held so `read` keeps waiting (#341).
    private var inputs: [Pipe] = []

    // MARK: - Set up

    override func tearDown() async throws {
        for child in children {
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
                child.waitUntilExit()
            }
        }
        children = []
        inputs = []
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: - Tests

    func testFindsAndClassifiesOtherCopiesOfTheSameExecutable() throws {
        let executable: URL = try makeFakePlantoir()
        let scheduled: Process = try start(executable, [
            "-c", "read -t 30 _", ScheduledDeploy.runFlag, "/w/.scheduled/deploy.sh",
            ScheduledDeploy.sectionFlag, "/w", "EXC2O", "1"
        ])
        let server: Process = try start(executable, ["-c", "read -t 30 _", AssistMCPServer.flag, "/f"])

        let sightings: [SameExecutableProcesses.Sighting] = SameExecutableProcesses.sightings(
            ofExecutableAt: executable.path
        )
        var byPID: [Int32: UpdateGate.OtherCopy] = [:]
        for sighting in sightings {
            byPID[sighting.pid] = UpdateGate.classify(pid: sighting.pid, arguments: sighting.arguments)
        }
        XCTAssertEqual(sightings.count, 2)
        assertStillRunning(scheduled)
        assertStillRunning(server)

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
        let child: Process = try start(executable, ["-c", "read -t 30 _"])
        let resolved: String = SameExecutableProcesses.resolved(executable.path)
        for spelling in [executable.path, resolved] {
            var pids: [Int32] = []
            for sighting in SameExecutableProcesses.sightings(ofExecutableAt: spelling) {
                pids.append(sighting.pid)
            }
            XCTAssertEqual(pids, [child.processIdentifier], spelling)
        }
        assertStillRunning(child)
    }

    /// A different copy of Plantoir is never this one: installing this copy
    /// does not touch it.
    func testADifferentExecutableIsNotSeen() throws {
        let executable: URL = try makeFakePlantoir()
        let child: Process = try start(executable, ["-c", "read -t 30 _", ScheduledDeploy.runFlag, "s"])
        let elsewhere: URL = try makeFakePlantoir(named: "Elsewhere")
        XCTAssertEqual(SameExecutableProcesses.sightings(ofExecutableAt: elsewhere.path), [])
        assertStillRunning(child)
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
        let child: Process = try start(executable, ["-c", "read -t 30 _"])
        let ends: AsyncStream<Void> = ProcessEnding.ends(of: child.processIdentifier)
        assertStillRunning(child)
        kill(child.processIdentifier, SIGTERM)
        var heard: Bool = false
        for await _ in ends {
            heard = true
        }
        XCTAssertTrue(heard)
    }

    func testAProcessAlreadyGoneIsHeardAtOnce() async throws {
        let executable: URL = try makeFakePlantoir()
        let child: Process = try start(executable, ["-c", ":"], waitUntilSeen: false)
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
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/bash"), to: executable)
            try signAdHoc(executable)
        }
        return executable
    }

    /// Without a fresh signature the copy is killed within milliseconds (#341).
    private func signAdHoc(_ executable: URL) throws {
        let codesign: Process = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", executable.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        if codesign.terminationStatus != 0 {
            throw NSError(
                domain: "SameExecutableProcessesTests", code: Int(codesign.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "codesign could not re-sign the copy at \(executable.path)"]
            )
        }
    }

    /// Starts a child and, unless it is meant to end at once, waits until the
    /// scan sees it: every 10 ms, for at most 2 s. This waits for the very
    /// condition the test then asserts, not for anything to settle.
    private func start(
        _ executable: URL, _ arguments: [String], waitUntilSeen: Bool = true
    ) throws -> Process {
        let process: Process = Process()
        let input: Pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        children.append(process)
        inputs.append(input)
        if waitUntilSeen {
            let deadline: Date = Date().addingTimeInterval(2)
            var seen: Bool = false
            while !seen && Date() < deadline {
                for sighting in SameExecutableProcesses.sightings(ofExecutableAt: executable.path) {
                    if sighting.pid == process.processIdentifier {
                        seen = true
                    }
                }
                if !seen {
                    usleep(10_000)
                }
            }
            if !seen {
                XCTFail("the scan never saw the child \(process.processIdentifier) within 2 s")
            }
        }
        return process
    }

    /// Every scan that relies on a live child checks it is still alive, so a
    /// test can never pass by finding nothing because the child died (#341).
    private func assertStillRunning(_ child: Process, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            child.isRunning,
            "the child \(child.processIdentifier) is no longer running, so the scan proved nothing",
            file: file, line: line
        )
    }
}
