import XCTest
@testable import QuartzTeachers

/// One container per working folder, resting when unused.
final class FolderContainerTests: XCTestCase {

    // MARK: - Functions

    /// The app and the launchers must derive the SAME name, or the app
    /// would stop a container that does not exist while the real one runs
    /// on. The launchers use `pwd -P | shasum -a 256 | cut -c1-8`.
    @MainActor
    func testTheNameMatchesWhatTheLaunchersDerive() throws {
        let folder: String = NSTemporaryDirectory() + "fc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }

        let shell: Process = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/bash")
        shell.arguments = ["-c", "cd '\(folder)' && pwd -P | shasum -a 256 | cut -c1-8"]
        let output: Pipe = Pipe()
        shell.standardOutput = output
        try shell.run()
        shell.waitUntilExit()
        let launcherHash: String = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )!.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(
            FolderContainers.containerName(forFolder: folder),
            "teaching-quartz-" + launcherHash,
            "The app must name the container exactly as the launchers do"
        )
    }

    @MainActor
    func testDifferentFoldersGetDifferentContainers() {
        XCTAssertNotEqual(
            FolderContainers.containerName(forFolder: "/Users/t/ThisYear"),
            FolderContainers.containerName(forFolder: "/Users/t/LastYear")
        )
    }

    @MainActor
    func testAFolderIsInUseWhileAnyWindowIsOnIt() throws {
        let folder: String = NSTemporaryDirectory() + "fc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }

        let first: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let second: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        first.chooseWorkspace(at: URL(fileURLWithPath: folder))
        second.chooseWorkspace(at: URL(fileURLWithPath: folder))
        WorkspaceModel.registerWindowModel(first)
        WorkspaceModel.registerWindowModel(second)
        defer {
            WorkspaceModel.unregisterWindowModel(first)
            WorkspaceModel.unregisterWindowModel(second)
        }

        XCTAssertTrue(WorkspaceModel.folderIsInUse(folder))
        WorkspaceModel.unregisterWindowModel(second)
        XCTAssertTrue(WorkspaceModel.folderIsInUse(folder), "One window still has it open")
        WorkspaceModel.unregisterWindowModel(first)
        XCTAssertFalse(WorkspaceModel.folderIsInUse(folder), "Now nobody does — the container can rest")
    }
}

/// What happens to a folder's container, and to the shared VM, at quit.
final class QuitScriptTests: XCTestCase {

    // MARK: - Stored properties

    static let pretendHome: URL = URL(fileURLWithPath: "/Users/pretend")
    static let pretendFolder: String = "/Users/pretend/Desktop/Comm Tech 26:27"

    // MARK: - What is handed to Process

    /// `/bin/sh`, never a login shell, and never a terminal.
    ///
    /// The login shell was chosen so that "docker is on PATH wherever it was
    /// installed", which was never true on a teacher's Mac; and `zsh -l`
    /// handed a pty whose other end has gone blocks in its own terminal
    /// setup, before it reads the script at all. Two such shells had been
    /// asleep on this Mac for 27 days.
    @MainActor
    func testTheQuitShellIsNotALoginShell() {
        let command: HelperPrograms.Command = FolderContainers.quitCommand(
            folderPaths: [QuitScriptTests.pretendFolder],
            inheriting: [:],
            inHomeFolder: QuitScriptTests.pretendHome
        )
        XCTAssertEqual(command.executablePath, "/bin/sh")
        XCTAssertEqual(command.arguments.first, "-c")
        XCTAssertFalse(
            command.arguments.contains("-l"),
            "A login shell reads the teacher's whole profile to decide a two-line script, and can hang before it reads the script at all"
        )
        XCTAssertEqual(command.arguments.count, 2)
    }

    /// The fault itself: the quit path is told where Plantoir's own programs
    /// are, both in the environment and in the script's first line.
    @MainActor
    func testTheQuitPathIsToldWhereTheProgramsAre() {
        let command: HelperPrograms.Command = FolderContainers.quitCommand(
            folderPaths: [QuitScriptTests.pretendFolder],
            inheriting: ["HOME": "/Users/pretend", "PATH": "/usr/bin:/bin"],
            inHomeFolder: QuitScriptTests.pretendHome
        )
        let expected: String = HelperPrograms.binDirectory(inHomeFolder: QuitScriptTests.pretendHome)
        XCTAssertEqual(command.environment["PATH"]?.components(separatedBy: ":").first, expected)
        XCTAssertEqual(
            command.environment["HOME"], "/Users/pretend",
            "docker keeps its context store in ~/.docker and colima its state in ~/.colima — a stripped environment reaches neither"
        )
        let script: String = command.arguments[1]
        XCTAssertEqual(
            script.components(separatedBy: "\n").first,
            HelperPrograms.exportLine(inHomeFolder: QuitScriptTests.pretendHome)
        )
    }

    // MARK: - What the script refuses to do

    @MainActor
    func testTheVMStopsOnlyWhenNothingElseRuns() {
        let script: String = FolderContainers.quitScript(
            folderPaths: [QuitScriptTests.pretendFolder],
            inHomeFolder: QuitScriptTests.pretendHome
        )
        XCTAssertTrue(script.contains("docker stop -t 2"))
        // The folder the app is releasing must be THIS folder's container.
        // Pinning only "docker stop -t 2" would pass on a wrong hash, and a
        // wrong hash stops somebody else's folder and leaves this one up.
        XCTAssertTrue(
            script.contains(HelperPrograms.shellQuoted(
                FolderContainers.containerName(forFolder: QuitScriptTests.pretendFolder)
            )),
            "The script does not name this folder's own container"
        )
        XCTAssertTrue(script.contains("docker ps -q"), "The emptiness check is the safety: Colima is shared")
        XCTAssertTrue(script.contains("colima stop"))
        let releaseIndex = script.range(of: "release ")!.lowerBound
        let checkIndex = script.range(of: "docker ps -q")!.lowerBound
        XCTAssertLessThan(
            releaseIndex, checkIndex,
            "Our containers stop BEFORE the emptiness check, or the check always fails"
        )
    }

    /// A `docker ps` that FAILED is not a Mac with nothing running on it.
    ///
    /// `DOCKER_CONTEXT=default docker ps -q` exits 1 and prints nothing; so
    /// does a daemon that did not answer. The old expression read both as
    /// permission to stop the shared VM, which on this Mac holds thirteen
    /// containers belonging to another project.
    @MainActor
    func testAFailedQuestionIsNotAnEmptyAnswer() {
        let script: String = FolderContainers.quitScript(
            folderPaths: [],
            inHomeFolder: QuitScriptTests.pretendHome
        )
        XCTAssertTrue(script.contains("asked=$?"), "Nothing reads whether the question succeeded")
        XCTAssertTrue(script.contains("[ \"$asked\" -ne 0 ]"))
        XCTAssertTrue(
            script.contains("DOCKER_HOST='unix:///Users/pretend/.colima/default/docker.sock'"),
            "The question must be put to the socket Colima owns, not to whatever context happens to be current"
        )
        XCTAssertTrue(
            script.contains("[ -S '/Users/pretend/.colima/default/docker.sock' ]"),
            "No socket, no answer, nothing stopped"
        )
    }

    /// Nothing of ours is stopped while a launcher for that folder is running
    /// on the host — the window the container-side check cannot see, because
    /// building an image or starting the machine adds no container at all.
    @MainActor
    func testWorkRunningOnTheHostIsLeftAlone() {
        let script: String = FolderContainers.quitScript(
            folderPaths: [QuitScriptTests.pretendFolder],
            inHomeFolder: QuitScriptTests.pretendHome
        )
        XCTAssertTrue(script.contains("ps -Ao args="))
        XCTAssertTrue(
            script.contains("grep -F \"$1/$launcher\""),
            "A fixed-string match, because pgrep -f takes a REGULAR EXPRESSION and a folder called C++ 26(27) would fail OPEN"
        )
        XCTAssertTrue(script.contains("release '/Users/pretend/Desktop/Comm Tech 26:27'"))
        XCTAssertTrue(
            script.contains("grep -Fv -- ' --stop'"),
            "The app's own preview stops run a launcher too; counting them would make every quit-with-a-preview free nothing"
        )
        XCTAssertTrue(script.contains("docker top"), "A build inside the container is work too")
    }

    /// A stop that was asked for and REFUSED must not be written down as a
    /// stop. It is issue #220 one level down: `docker stop` succeeding and
    /// `docker stop` being refused look identical to a script that does not
    /// check, and "the memory it was holding is back" on a day it is not is a
    /// line that will be believed.
    @MainActor
    func testAStopThatFailedIsNotWrittenDownAsAStop() {
        let script: String = FolderContainers.quitScript(
            folderPaths: [QuitScriptTests.pretendFolder],
            inHomeFolder: QuitScriptTests.pretendHome
        )
        XCTAssertTrue(script.contains("if docker stop -t 2 \"$2\"; then")
            || script.contains("if docker stop -t 2 \"$2\" >/dev/null 2>&1; then"))
        XCTAssertTrue(script.contains("if colima stop >/dev/null 2>&1; then"))
        XCTAssertTrue(script.contains("and it would not stop"))
    }

    /// The whole script's deadline has to GROW with the number of folders, or
    /// it becomes the thing that stops the work: six folders each waiting
    /// twenty seconds is already two minutes, and a fixed two minutes would
    /// kill the sixth mid-way and tell the teacher nothing about any of them.
    @MainActor
    func testTheDeadlineGrowsWithTheWork() {
        XCTAssertGreaterThan(
            FolderContainers.secondsBeforeGivingUp(folderCount: 6, secondsToWaitForWork: 20),
            6 * 20,
            "Six busy folders would be killed before the last one had its turn"
        )
        XCTAssertGreaterThan(
            FolderContainers.secondsBeforeGivingUp(folderCount: 0, secondsToWaitForWork: 20),
            0,
            "A quit with no folders open still has a shared machine to ask about"
        )
        let script: String = FolderContainers.quitScript(
            folderPaths: [QuitScriptTests.pretendFolder],
            inHomeFolder: QuitScriptTests.pretendHome
        )
        XCTAssertTrue(
            script.contains("stopped waiting for an answer"),
            "The one ending that reported nothing is the fault this piece exists to fix"
        )
    }

    @MainActor
    func testAMachineWithoutColimaIsLeftAlone() {
        let script: String = FolderContainers.quitScript(
            folderPaths: [],
            inHomeFolder: QuitScriptTests.pretendHome
        )
        XCTAssertTrue(script.contains("command -v colima"), "Docker Desktop users have no colima to stop")
        XCTAssertFalse(script.contains("release '"), "No folders of ours, nothing of ours to stop")
    }

    /// One window closing says nothing about the rest of the Mac.
    @MainActor
    func testClosingTheLastWindowNeverTouchesTheSharedSetup() {
        let script: String = FolderContainers.quitScript(
            folderPaths: [QuitScriptTests.pretendFolder],
            occasion: .theLastWindowOnTheFolderClosed,
            includingTheSharedSetup: false,
            inHomeFolder: QuitScriptTests.pretendHome
        )
        XCTAssertFalse(script.contains("colima stop"))
        XCTAssertTrue(script.contains("release '/Users/pretend/Desktop/Comm Tech 26:27'"))
        XCTAssertTrue(script.contains("no window was working in that folder any more"))
    }

    // MARK: - The script is valid sh, whatever the folder is called

    /// A working folder's name is the teacher's, and the quit script carries
    /// it into shell source twice over — as an argument and inside a
    /// sentence. `sh -n` parses without running anything, so this asks the
    /// real shell whether the text it would be handed is a script at all.
    ///
    /// The names are the ones that have actually cost time here: a colon
    /// (issue #221), a space, an apostrophe, and the shell's own
    /// metacharacters.
    @MainActor
    func testTheScriptIsValidShellWhateverTheFolderIsCalled() throws {
        let awkwardNames: [String] = [
            "Comm Tech 26:27",
            "O'Brien's Class",
            "C++ 26(27)",
            "Rock & Roll; rm -rf /",
            "back\\slash \"quoted\" $PATH `date`"
        ]
        for name in awkwardNames {
            let script: String = FolderContainers.quitScript(
                folderPaths: ["/Users/o'brien/Desktop/" + name],
                inHomeFolder: URL(fileURLWithPath: "/Users/o'brien")
            )
            let shell: Process = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-n", "-c", script]
            let complaint: Pipe = Pipe()
            shell.standardError = complaint
            try shell.run()
            shell.waitUntilExit()
            let said: String = String(
                data: complaint.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
            ) ?? ""
            XCTAssertEqual(
                shell.terminationStatus, 0,
                "A folder called \"\(name)\" produces a script the shell cannot read: \(said)"
            )
        }
    }

    // MARK: - Every ending has a line on the trail

    /// Each outcome the script can reach is one of the contract's events, and
    /// says something a teacher would recognise rather than naming a program.
    @MainActor
    func testEveryEndingSaysSomethingATeacherWouldRecognise() {
        // `allCases`, not a hand-written list: a seventh ending added
        // without a sentence would otherwise be covered by nothing.
        XCTAssertGreaterThan(FolderContainers.Outcome.allCases.count, 5)
        for outcome in FolderContainers.Outcome.allCases {
            let sentence: String = FolderContainers.sentence(
                for: outcome,
                occasion: .quitting,
                folderName: "Comm Tech 26:27",
                reasonSomethingElseIsUsingIt: "other software on this Mac is still using it"
            )
            XCTAssertFalse(sentence.isEmpty)
            for word in ["container", "docker", "colima", "toolchain", "script", "virtual machine"] {
                XCTAssertFalse(
                    sentence.lowercased().contains(word),
                    "\"\(word)\" is machinery, and a teacher reads this: \(sentence)"
                )
            }
            XCTAssertFalse(
                sentence.contains("/Users/"),
                "A path would need redacting, and the script writes straight to the trail: \(sentence)"
            )
        }
    }
}
