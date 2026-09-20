import Foundation
import XCTest
@testable import QuartzTeachers

/// The quit script, actually RUN.
///
/// Everything else about this path is a value comparison, and a value
/// comparison cannot tell whether the text is valid `sh`, whether the
/// quoting survives a folder called `Comm Tech 26:27`, or whether a gate
/// written to fail closed actually does. These tests run the real generated
/// script under a scratch home folder with STAND-IN programs in the very
/// folder `HelperPrograms` looks in first — so the real `docker` and the real
/// `colima` on the machine running the suite are shadowed and cannot be
/// reached, and nothing of anybody's is stopped.
final class QuitScriptRunsTests: XCTestCase {

    // MARK: - Types

    /// One run's scratch world: a home folder, a working folder, a place the
    /// stand-in programs write down what they were asked to do.
    struct Scratch {
        let root: URL
        let home: URL
        let workingFolder: URL
        let callsFile: URL
        let trailFile: URL
    }

    // MARK: - A container that is running and idle

    /// The whole point of the piece: quitting stops the folder's website
    /// builder, and says so.
    @MainActor
    func testAnIdleBuilderIsStoppedAndTheTrailSaysSo() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(in: scratch, running: true, processesInside: 1, psExitCode: 0)

        let trail: String = try run(in: scratch, includingTheSharedSetup: false)

        XCTAssertTrue(
            callsMade(in: scratch).contains(where: { call in call.hasPrefix("stop -t 2 teaching-quartz-") }),
            "Nothing was stopped. What was asked:\n\(callsMade(in: scratch).joined(separator: "\n"))"
        )
        XCTAssertTrue(
            trail.contains("stopped the website builder for “" + scratch.workingFolder.lastPathComponent + "”"),
            "The trail says: \(trail)"
        )
    }

    /// A builder with a build inside it is left alone, and the trail says
    /// which kind of "something else" it was.
    @MainActor
    func testABuilderWithWorkInsideItIsLeftRunning() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(in: scratch, running: true, processesInside: 3, psExitCode: 0)

        let trail: String = try run(in: scratch, includingTheSharedSetup: false, secondsToWaitForWork: 2)

        XCTAssertFalse(
            callsMade(in: scratch).contains(where: { call in call.hasPrefix("stop ") }),
            "A publish was running inside it and it was stopped anyway"
        )
        XCTAssertTrue(trail.contains("left the website builder for “"), "The trail says: \(trail)")
        XCTAssertTrue(trail.contains("still going"), "The trail says: \(trail)")
    }

    /// A builder that is not running says nothing at all. A line every quit
    /// reporting that there was nothing to stop would bury the one quit where
    /// something happened.
    @MainActor
    func testABuilderThatIsNotRunningIsNotReported() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(in: scratch, running: false, processesInside: 1, psExitCode: 0)

        let trail: String = try run(in: scratch, includingTheSharedSetup: false)

        XCTAssertFalse(callsMade(in: scratch).contains(where: { call in call.hasPrefix("stop ") }))
        XCTAssertEqual(trail.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    /// A stop that was asked for and REFUSED is reported as a refusal, not as
    /// a success. Issue #220 was a fault that reported nothing; a line saying
    /// the memory came back on a day it did not is the same fault with better
    /// manners.
    @MainActor
    func testAStopThatWasRefusedIsNotReportedAsASuccess() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(
            in: scratch, running: true, processesInside: 1, psExitCode: 0, stopExitCode: 1
        )

        let trail: String = try run(in: scratch, includingTheSharedSetup: false)

        XCTAssertTrue(
            callsMade(in: scratch).contains(where: { call in call.hasPrefix("stop -t 2 ") }),
            "The stop was never even attempted"
        )
        XCTAssertFalse(
            trail.contains("stopped the website builder for"),
            "A refused stop was written down as a stop. The trail says: \(trail)"
        )
        XCTAssertTrue(trail.contains("it would not stop"), "The trail says: \(trail)")
    }

    // MARK: - The shared machine (rule 7)

    /// The one that matters most. A question that FAILED is not an empty
    /// answer, and the shared machine is left alone.
    @MainActor
    func testTheSharedMachineIsLeftAloneWhenTheQuestionFails() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(in: scratch, running: false, processesInside: 1, psExitCode: 1)
        try writeColimaStandIn(in: scratch)
        try makeSocket(at: colimaSocketPath(in: scratch))

        let trail: String = try run(in: scratch, includingTheSharedSetup: true)

        XCTAssertFalse(
            callsMade(in: scratch).contains("colima stop"),
            "The shared machine was stopped on an answer nobody got. What was asked:\n\(callsMade(in: scratch).joined(separator: "\n"))"
        )
        XCTAssertTrue(trail.contains("could not check what else was using"), "The trail says: \(trail)")
    }

    /// Something else is running in it — thirteen of another project's
    /// containers, on the Mac this was written on — so it stays up.
    @MainActor
    func testTheSharedMachineIsLeftAloneWhenSomethingElseIsInIt() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(
            in: scratch, running: false, processesInside: 1, psExitCode: 0,
            psPrints: "6c9d1e2f3a4b\n5b4a3c2d1e0f"
        )
        try writeColimaStandIn(in: scratch)
        try makeSocket(at: colimaSocketPath(in: scratch))

        let trail: String = try run(in: scratch, includingTheSharedSetup: true)

        XCTAssertFalse(callsMade(in: scratch).contains("colima stop"))
        XCTAssertTrue(
            trail.contains("other software on this Mac is still using it"),
            "The trail says: \(trail)"
        )
    }

    /// The teacher's OWN builder, left running a moment earlier, must not be
    /// reported as "other software on this Mac".
    ///
    /// It is in `docker ps -q`'s answer like anything else, so the obvious
    /// order of questions produces a sentence that is false on every Mac that
    /// has nothing else in there — which is every teacher's.
    @MainActor
    func testOurOwnBuilderIsNotReportedAsSomebodyElsesSoftware() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(
            in: scratch, running: true, processesInside: 3, psExitCode: 0,
            psPrints: "6c9d1e2f3a4b"
        )
        try writeColimaStandIn(in: scratch)
        try makeSocket(at: colimaSocketPath(in: scratch))

        let trail: String = try run(
            in: scratch, includingTheSharedSetup: true, secondsToWaitForWork: 2
        )

        XCTAssertFalse(callsMade(in: scratch).contains("colima stop"))
        XCTAssertTrue(
            trail.contains("this folder’s own website builder is still running"),
            "The trail says: \(trail)"
        )
        XCTAssertFalse(
            trail.contains("other software on this Mac"),
            "A teacher's own unfinished publish was reported as somebody else's software: \(trail)"
        )
    }

    /// A stop that was REFUSED leaves our own builder running, and the
    /// shared-machine question must not then call it somebody else's
    /// software.
    ///
    /// The same falsehood `testOurOwnBuilderIsNotReportedAsSomebodyElses
    /// Software` exists to prevent, reached through the other door: the
    /// builder is still in the emptiness check's answer whether it was left
    /// alone deliberately or refused to stop, and only the first of those two
    /// used to tell the shared-machine question about itself.
    @MainActor
    func testARefusedStopStillCountsAsOurOwnBuilder() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(
            in: scratch, running: true, processesInside: 1, psExitCode: 0,
            psPrints: "abc123deadbeef", stopExitCode: 1
        )
        try writeColimaStandIn(in: scratch)
        try makeSocket(at: colimaSocketPath(in: scratch))

        let trail: String = try run(in: scratch, includingTheSharedSetup: true)

        XCTAssertFalse(callsMade(in: scratch).contains("colima stop"))
        XCTAssertTrue(trail.contains("it would not stop"), "The trail says: \(trail)")
        XCTAssertFalse(
            trail.contains("other software on this Mac"),
            "A builder of the teacher's own that refused to stop was reported as somebody else's software: \(trail)"
        )
        XCTAssertTrue(
            trail.contains("this folder’s own website builder is still running"),
            "The trail says: \(trail)"
        )
    }

    // MARK: - A launcher running on this Mac

    /// The most dangerous rule in the piece, RUN rather than read off the
    /// script's text: never stop a folder's builder while a launcher for that
    /// folder is running on this Mac.
    ///
    /// Real launchers, started by this test in the scratch folder, so their
    /// `ps` lines carry exactly the absolute paths `ScriptRunner` and a
    /// scheduled publish produce. Three folders at once, because the two ways
    /// this can go wrong are opposites: a launcher that is NOT matched (the
    /// gate fails open and a publish is stopped mid-flight), and one matched
    /// too eagerly — `Teach` is a prefix of `Teach 2`, and a neighbour's
    /// launcher must not hold a folder that has none. Nothing here needs
    /// Docker or Colima; the stand-ins are the only ones reachable.
    @MainActor
    func testNothingIsStoppedWhileThatFoldersLauncherIsRunning() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(in: scratch, running: true, processesInside: 1, psExitCode: 0)
        try writeColimaStandIn(in: scratch)
        try makeSocket(at: colimaSocketPath(in: scratch))

        let desktop: URL = scratch.home.appendingPathComponent("Desktop", isDirectory: true)
        let busy: URL = desktop.appendingPathComponent("Teach 2", isDirectory: true)
        let quiet: URL = desktop.appendingPathComponent("Teach", isDirectory: true)
        let stopping: URL = desktop.appendingPathComponent("O'Brien's Class", isDirectory: true)
        for folder in [busy, quiet, stopping] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ["preview.sh", "deploy.sh"] {
                let script: URL = folder.appendingPathComponent(name)
                // NOT `exec`: that replaces the process image, and with it
                // the very `ps` line the quit script matches on. The trap
                // takes the sleep with it so nothing is orphaned.
                try Data(
                    "sleep 25 &\nchild=$!\ntrap 'kill $child 2>/dev/null; exit 0' TERM\nwait $child\n".utf8
                ).write(to: script)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: script.path
                )
            }
        }

        // A publish for "Teach 2", and a STOP for the apostrophe folder —
        // which must not count, or the app's own preview stops would make
        // every quit-with-a-preview free nothing at all.
        let publishing: Process = launcher(
            at: busy.appendingPathComponent("deploy.sh"), arguments: ["COMP", "1"]
        )
        let stoppingRun: Process = launcher(
            at: stopping.appendingPathComponent("preview.sh"), arguments: ["COMP", "2", "--stop"]
        )
        defer {
            publishing.terminate()
            stoppingRun.terminate()
        }
        try publishing.run()
        try stoppingRun.run()
        XCTAssertTrue(publishing.isRunning && stoppingRun.isRunning, "The stand-in launchers did not start")

        let trail: String = try run(
            in: scratch,
            includingTheSharedSetup: true,
            secondsToWaitForWork: 2,
            folderPaths: [busy.path, quiet.path, stopping.path]
        )

        var stopped: [String] = []
        for call in callsMade(in: scratch) where call.hasPrefix("stop -t 2 ") {
            stopped.append(String(call.dropFirst("stop -t 2 ".count)))
        }
        XCTAssertFalse(
            stopped.contains(FolderContainers.containerName(forFolder: busy.path)),
            "A folder with a publish running on this Mac had its builder stopped. Stopped: \(stopped)"
        )
        XCTAssertTrue(
            stopped.contains(FolderContainers.containerName(forFolder: quiet.path)),
            "“Teach” has no launcher of its own — only its neighbour “Teach 2” does — and was held anyway. Stopped: \(stopped)"
        )
        XCTAssertTrue(
            stopped.contains(FolderContainers.containerName(forFolder: stopping.path)),
            "A --stop run held the folder. Stopped: \(stopped)"
        )
        XCTAssertFalse(
            callsMade(in: scratch).contains("colima stop"),
            "The shared machine was stopped while a publish was running on this Mac"
        )
        XCTAssertTrue(trail.contains("left the website builder for “Teach 2”"), "The trail says: \(trail)")
    }

    /// A stand-in launcher, run exactly the way the app runs a real one: by
    /// absolute path, through `/bin/bash`, so its `ps` line is the shape the
    /// quit script looks for.
    private func launcher(at scriptURL: URL, arguments: [String]) -> Process {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        var fullArguments: [String] = [scriptURL.path]
        for argument in arguments {
            fullArguments.append(argument)
        }
        process.arguments = fullArguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    /// No socket belonging to the shared machine, nothing touched — which is
    /// also what a Mac using Docker Desktop, or a differently named machine,
    /// looks like from here.
    @MainActor
    func testTheSharedMachineIsLeftAloneWhenItsSocketIsNotThere() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(in: scratch, running: false, processesInside: 1, psExitCode: 0)
        try writeColimaStandIn(in: scratch)

        let trail: String = try run(in: scratch, includingTheSharedSetup: true)

        XCTAssertFalse(callsMade(in: scratch).contains("colima stop"))
        XCTAssertEqual(trail.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    /// And the case the memory comes back in: asked, answered, empty, and
    /// nothing of ours running on the machine.
    @MainActor
    func testTheSharedMachineIsStoppedOnAClearAnswer() throws {
        try XCTSkipIf(
            aLauncherIsRunningOnThisMac(),
            "A launcher is running on this Mac right now, which is exactly what the script refuses to stop anything through — this case cannot be told apart from the refusal working."
        )
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try writeDockerStandIn(in: scratch, running: false, processesInside: 1, psExitCode: 0)
        try writeColimaStandIn(in: scratch)
        try makeSocket(at: colimaSocketPath(in: scratch))

        let trail: String = try run(in: scratch, includingTheSharedSetup: true)

        XCTAssertTrue(
            callsMade(in: scratch).contains("colima stop"),
            "What was asked:\n\(callsMade(in: scratch).joined(separator: "\n"))"
        )
        XCTAssertTrue(trail.contains("the memory it was holding is back"), "The trail says: \(trail)")
    }

    // MARK: - A Mac that has never had Homebrew

    /// Issue #220 itself, and it must REPORT rather than exit 0 in silence.
    ///
    /// Nothing is written into the tools folder for this one: it exists and
    /// is empty, exactly as it is on a Mac where the launchers found
    /// everything already installed — and, because every run in this file
    /// stands Homebrew's two directories down (see `run`), there is then no
    /// `docker` anywhere the script can look.
    @MainActor
    func testAMacWithNoneOfTheProgramsSaysSoRatherThanNothing() throws {
        let scratch: Scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }

        let trail: String = try run(in: scratch, includingTheSharedSetup: true)

        XCTAssertTrue(
            trail.contains("could not find the programs that run your website builder"),
            "A fault that reports nothing is the fault this piece exists to fix. The trail says: \(trail)"
        )
    }

    // MARK: - Running it

    /// Runs the script the app would generate, with ONE substitution: the two
    /// directories a Mac WITH Homebrew keeps its copies in are pointed at an
    /// empty folder, in the script's own export line and in the environment
    /// it is handed.
    ///
    /// That substitution is doing two jobs at once and both are worth saying
    /// out loud. It stands in for a teacher's Mac, which is the machine this
    /// whole piece is about and is not the machine the suite runs on. And it
    /// makes these tests HERMETIC: with Homebrew stood down, the only `docker`
    /// and `colima` the script can reach are the stand-ins written into the
    /// scratch tools folder, so a suite run can never stop a container or a
    /// virtual machine belonging to the person running it. The substitution
    /// is asserted to have applied, so this cannot quietly stop being true.
    @MainActor
    private func run(
        in scratch: Scratch,
        includingTheSharedSetup: Bool,
        secondsToWaitForWork: Int = 20,
        folderPaths: [String]? = nil
    ) throws -> String {
        let script: String = FolderContainers.quitScript(
            folderPaths: folderPaths ?? [scratch.workingFolder.path],
            includingTheSharedSetup: includingTheSharedSetup,
            secondsToWaitForWork: secondsToWaitForWork,
            inHomeFolder: scratch.home
        )
        let nowhere: String = scratch.root.appendingPathComponent("no-homebrew-here").path
        try FileManager.default.createDirectory(
            atPath: nowhere, withIntermediateDirectories: true
        )
        let homebrew: String = HelperPrograms.sharedSearchDirectories.joined(separator: ":")
        let stoodDown: String = script.replacingOccurrences(of: homebrew, with: nowhere)
        XCTAssertNotEqual(
            script, stoodDown,
            "Homebrew was not stood down, so this run could have reached the real docker"
        )

        var environment: [String: String] = HelperPrograms.environment(
            basedOn: ["HOME": scratch.home.path, "PATH": HelperPrograms.pathWhenNothingWasInherited],
            inHomeFolder: scratch.home
        )
        let inherited: String = try XCTUnwrap(environment["PATH"])
        environment["PATH"] = inherited.replacingOccurrences(of: homebrew, with: nowhere)
        XCTAssertNotEqual(inherited, environment["PATH"])

        let shell: Process = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", stoodDown]
        shell.environment = environment
        shell.standardInput = FileHandle.nullDevice
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        try shell.run()
        shell.waitUntilExit()
        return (try? String(contentsOf: scratch.trailFile, encoding: .utf8)) ?? ""
    }

    // MARK: - The scratch world

    private func makeScratch() throws -> Scratch {
        // A SHORT root: a unix socket's whole path must fit in 104 bytes, and
        // the usual `Plantoir-tests-<uuid>` name under the per-user temporary
        // folder does not leave room for `.colima/default/docker.sock`.
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("q-" + String(UUID().uuidString.prefix(6)), isDirectory: true)
        let home: URL = root.appendingPathComponent("home", isDirectory: true)
        let workingFolder: URL = home
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("Comm Tech 26:27", isDirectory: true)
        let manager: FileManager = FileManager.default
        try manager.createDirectory(at: workingFolder, withIntermediateDirectories: true)
        try manager.createDirectory(
            atPath: HelperPrograms.binDirectory(inHomeFolder: home),
            withIntermediateDirectories: true
        )
        let scratch: Scratch = Scratch(
            root: root,
            home: home,
            workingFolder: workingFolder,
            callsFile: root.appendingPathComponent("calls.txt"),
            trailFile: home
                .appendingPathComponent("Library")
                .appendingPathComponent("Logs")
                .appendingPathComponent("Plantoir")
                .appendingPathComponent("activity.txt")
        )
        XCTAssertLessThan(
            colimaSocketPath(in: scratch).utf8.count, 100,
            "The scratch folder is too deep for a unix socket to live in it"
        )
        return scratch
    }

    private func colimaSocketPath(in scratch: Scratch) -> String {
        return scratch.home
            .appendingPathComponent(".colima")
            .appendingPathComponent("default")
            .appendingPathComponent("docker.sock")
            .path
    }

    private func callsMade(in scratch: Scratch) -> [String] {
        let text: String = (try? String(contentsOf: scratch.callsFile, encoding: .utf8)) ?? ""
        var result: [String] = []
        for line in text.components(separatedBy: "\n") {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append(line)
            }
        }
        return result
    }

    /// A stand-in `docker`, written where `HelperPrograms` looks FIRST, so
    /// the real one on this Mac is shadowed and cannot be reached.
    private func writeDockerStandIn(
        in scratch: Scratch,
        running: Bool,
        processesInside: Int,
        psExitCode: Int,
        psPrints: String = "",
        stopExitCode: Int = 0
    ) throws {
        var inside: String = "UID  PID  PPID  C  STIME  TTY  TIME  CMD"
        for index in 0..<processesInside {
            inside += "\nroot  \(1000 + index)  999  0  15:35  ?  00:00:00  tail -f /dev/null"
        }
        var lines: [String] = []
        lines.append("#!/bin/sh")
        lines.append("printf '%s\\n' \"$*\" >> " + HelperPrograms.shellQuoted(scratch.callsFile.path))
        lines.append("case \"$1\" in")
        lines.append("  inspect) printf '%s\\n' '\(running ? "true" : "false")' ;;")
        lines.append("  top) printf '%s\\n' \(HelperPrograms.shellQuoted(inside)) ;;")
        lines.append("  ps) printf '%s' \(HelperPrograms.shellQuoted(psPrints.isEmpty ? "" : psPrints + "\n"))"
            + "; exit \(psExitCode) ;;")
        lines.append("  stop) exit \(stopExitCode) ;;")
        lines.append("esac")
        lines.append("exit 0")
        try write(lines.joined(separator: "\n") + "\n", toProgramNamed: "docker", in: scratch)
    }

    /// A stand-in `colima` that records what it was asked and stops nothing.
    private func writeColimaStandIn(in scratch: Scratch) throws {
        let text: String = "#!/bin/sh\n"
            + "printf 'colima %s\\n' \"$*\" >> "
            + HelperPrograms.shellQuoted(scratch.callsFile.path) + "\n"
            + "exit 0\n"
        try write(text, toProgramNamed: "colima", in: scratch)
    }

    private func write(_ text: String, toProgramNamed name: String, in scratch: Scratch) throws {
        let path: String = HelperPrograms.binDirectory(inHomeFolder: scratch.home) + "/" + name
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: path
        )
    }

    /// A real unix socket file, because `[ -S ]` asks for one and nothing
    /// else will do.
    private func makeSocket(at path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let descriptor: Int32 = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        var address: sockaddr_un = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes: [UInt8] = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for index in 0..<bytes.count {
                buffer[index] = bytes[index]
            }
            buffer[bytes.count] = 0
        }
        let bound: Int32 = withUnsafePointer(to: &address) { pointer in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { asAddress in
                return Darwin.bind(descriptor, asAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(descriptor)
        XCTAssertEqual(bound, 0, "Could not make a socket at \(path)")
    }

    /// Is one of Plantoir's launchers running on this Mac at this moment?
    private func aLauncherIsRunningOnThisMac() -> Bool {
        let shell: Process = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = [
            "-c",
            "ps -Ao args= | grep -E '/(preview|deploy|setup)\\.sh( |$)' | grep -Fv -- ' --stop' | grep -Fv grep"
        ]
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        try? shell.run()
        shell.waitUntilExit()
        return shell.terminationStatus == 0
    }
}
