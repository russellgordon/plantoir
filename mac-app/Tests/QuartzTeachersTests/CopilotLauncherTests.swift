import Security
import XCTest
@testable import QuartzTeachers

/// The third outside door: handing a course to GitHub Copilot (#783).
///
/// The tests that matter most here are the ones the plan review raised:
/// the connection file is real JSON whatever the folder is called (it is
/// written with a JSON writer, never by joining strings), it carries the
/// 30-minute timeout Copilot would otherwise replace with 60 seconds, the
/// door passes no flag an older Copilot does not know and no permission flag
/// at all, a Copilot that stops at once is explained in plain words, and a
/// `copilot` that is not GitHub's is never offered.
///
/// `testTheRenderedArgumentsSurviveTheShell` RUNS the script the app wrote
/// against a stub standing in for `copilot`, and reads the arguments that
/// arrived. No test starts the real Copilot.
final class CopilotLauncherTests: XCTestCase {

    // MARK: - Stored properties

    /// A path with no character the shell or JSON has to escape, used
    /// wherever the test is about something other than escaping.
    private let plainFolder: String = "/Users/teacher/Teaching"

    private let plainServer: String = "/Applications/Plantoir.app/Contents/MacOS/Plantoir"

    /// Folders and files a test made, removed in `tearDown`.
    private var madePaths: [String] = []

    // MARK: - Functions

    override func tearDown() {
        for path in madePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        madePaths = []
        super.tearDown()
    }

    /// A fresh folder under the temporary folder, removed afterwards.
    private func makeFolder(named name: String) throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        madePaths.append(folder.path)
        return folder
    }

    /// An executable shell script at `url`.
    private func writeExecutable(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Runs `scriptPath` with bash, returning what it printed.
    private func run(scriptPath: String) throws -> String {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        let output: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - The connection file

    /// The file is JSON that Copilot can read, and it names the folder, the
    /// course and the server exactly, for a folder whose name holds a space,
    /// an apostrophe, a double quote, a dollar sign, a backslash and an
    /// accented letter. MUST FAIL if the file is built by joining strings:
    /// the double quote ends the folder's string early.
    func testTheConnectionFileIsRealJSONWhateverTheFolderIsCalled() throws {
        let awkwardFolder: String = "/Users/teacher/My \"Classes\" 'été' $HOME \\ 2026"
        let configPath: String = try CopilotLauncher.writeConfig(
            workspacePath: awkwardFolder,
            courseCode: "ICS3U_COPILOT_JSON_TEST",
            serverPath: plainServer
        )
        madePaths.append(configPath)
        XCTAssertTrue(configPath.hasSuffix("/mcp-ICS3U_COPILOT_JSON_TEST-copilot.json"), configPath)

        let data: Data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let configuration: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let servers: [String: Any] = try XCTUnwrap(configuration["mcpServers"] as? [String: Any])
        XCTAssertEqual(Array(servers.keys), ["plantoir"], "one server, named as the greeting's 'plantoir tools'")
        let plantoir: [String: Any] = try XCTUnwrap(servers["plantoir"] as? [String: Any])
        XCTAssertEqual(plantoir["type"] as? String, "local")
        XCTAssertEqual(plantoir["command"] as? String, plainServer)
        XCTAssertEqual(plantoir["args"] as? [String], ["--mcp-stdio", awkwardFolder])
        XCTAssertEqual(plantoir["env"] as? [String: String], [
            AssistMCPServer.doorCourseVariable: "ICS3U_COPILOT_JSON_TEST",
            AssistMCPServer.doorAssistantVariable: "copilot",
        ])
        XCTAssertEqual(plantoir["tools"] as? [String], ["*"])
    }

    /// Copilot cuts a tool off at 60 seconds when the server names no
    /// timeout, and a deploy is awaited and takes minutes (plan review H1).
    /// MUST FAIL if the `timeout` key is dropped or shortened below ten
    /// minutes.
    func testTheTimeoutIsLongerThanAnyDeploy() throws {
        let configuration: [String: Any] = CopilotLauncher.configuration(
            workspacePath: plainFolder, courseCode: "ICS3U", serverPath: plainServer
        )
        let servers: [String: Any] = try XCTUnwrap(configuration["mcpServers"] as? [String: Any])
        let plantoir: [String: Any] = try XCTUnwrap(servers["plantoir"] as? [String: Any])
        let timeout: Int = try XCTUnwrap(plantoir["timeout"] as? Int, "no timeout: Copilot would use 60 seconds")
        XCTAssertEqual(timeout, CopilotLauncher.toolTimeoutMilliseconds)
        XCTAssertGreaterThanOrEqual(timeout, 600_000)
        XCTAssertEqual(timeout, CodexLauncher.toolTimeoutSeconds * 1000, "the same thirty minutes as the Codex door")
    }

    // MARK: - The script

    /// No permission flag of any kind (Russell, 2026-11-13), and no flag an
    /// older Copilot lacks (`-C` arrived in 1.0.42; `--enable-mcp-server` in
    /// 1.0.80). MUST FAIL if any is added.
    func testNoPermissionFlagAndNoFlagAnOlderCopilotLacks() throws {
        let configPath: String = "/tmp/mcp-ICS3U-copilot.json"
        let line: String = CopilotLauncher.commandLine(
            copilotPath: "/opt/homebrew/bin/copilot", configPath: configPath, prompt: "hello"
        )
        let refused: [String] = [
            "--allow-tool", "--deny-tool", "--allow-all", "--allow-all-tools", "--allow-all-paths",
            "--allow-all-urls", "--allow-all-mcp-server-instructions", "--yolo", "--no-ask-user",
            "--disallow-temp-dir", "--no-auto-update", " -C ", "--enable-mcp-server", "--no-custom-instructions",
            " -p ", "--secret-env-vars",
        ]
        for flag in refused {
            XCTAssertFalse(line.contains(flag), "\(flag) in: \(line)")
        }
        XCTAssertTrue(line.contains(" --disable-builtin-mcps"), line)
        // GitHub's desktop-control server is off in a session Plantoir opens
        // (review M2). MUST FAIL if the flag is dropped.
        XCTAssertTrue(line.contains(" --disable-mcp-server computer-use"), line)
    }

    /// The script's command line arrives at Copilot as exactly the contract's
    /// arguments, through a real shell, for an awkward folder, an awkward
    /// course code and the real greeting.
    func testTheRenderedArgumentsSurviveTheShell() throws {
        let awkwardFolder: URL = try makeFolder(named: "copilot round \"trip\" \\ ’s é")
        let stubFolder: URL = try makeFolder(named: "copilot-stub")
        let argumentsFile: URL = stubFolder.appendingPathComponent("arguments")
        let stub: URL = stubFolder.appendingPathComponent("copilot")
        try writeExecutable("""
        #!/bin/sh
        printf '%s\\0' "$@" > '\(argumentsFile.path)'
        """, to: stub)

        let configPath: String = try CopilotLauncher.writeConfig(
            workspacePath: awkwardFolder.path, courseCode: "-AP CALC-", serverPath: plainServer
        )
        madePaths.append(configPath)
        let greeting: String = ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "Grade 11 Computer Science")
        let scriptPath: String = try CopilotLauncher.writeLauncherScript(
            workspacePath: awkwardFolder.path,
            courseCode: "-AP CALC-",
            copilotPath: stub.path,
            configPath: configPath,
            prompt: greeting
        )
        madePaths.append(scriptPath)

        let printed: String = try run(scriptPath: scriptPath)
        XCTAssertFalse(printed.contains(CopilotLauncher.stoppedAtOnceSentence), "a stub that succeeded is not explained")

        let raw: String = try String(contentsOf: argumentsFile, encoding: .utf8)
        var arrived: [String] = raw.components(separatedBy: "\0")
        if arrived.last == "" {
            arrived.removeLast()
        }
        XCTAssertEqual(arrived, [
            "--additional-mcp-config", "@" + configPath, "--disable-builtin-mcps",
            "--disable-mcp-server", "computer-use", "-i", greeting,
        ])
        XCTAssertTrue(configPath.hasPrefix("/"), "the @ path is absolute, so it is not read against Copilot's folder")
    }

    /// A Copilot that stops at once with a failure is explained in plain
    /// words after it (plan review H2); one that ran and failed later is
    /// not, and neither is one that ended well. MUST FAIL if the check is
    /// removed from the script.
    func testACopilotThatStopsAtOnceIsExplained() throws {
        let folder: URL = try makeFolder(named: "copilot-stops")
        let stubFolder: URL = try makeFolder(named: "copilot-stub-fails")
        let stub: URL = stubFolder.appendingPathComponent("copilot")
        try writeExecutable("""
        #!/bin/sh
        echo "error: unexpected argument found" >&2
        exit 1
        """, to: stub)
        let scriptPath: String = try CopilotLauncher.writeLauncherScript(
            workspacePath: folder.path,
            courseCode: "ICS3U_COPILOT_STOPS_TEST",
            copilotPath: stub.path,
            configPath: "/tmp/mcp-ICS3U_COPILOT_STOPS_TEST-copilot.json",
            prompt: "hello"
        )
        madePaths.append(scriptPath)
        let printed: String = try run(scriptPath: scriptPath)
        XCTAssertTrue(printed.contains(CopilotLauncher.stoppedAtOnceSentence), printed)

        let script: String = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(script.contains("-lt \(CopilotLauncher.stoppedAtOnceSeconds)"), script)
    }

    /// The teacher's own Control-C in the first seconds is not "stopped as
    /// soon as it started" (review L1): a status of 128 or more is a signal.
    /// MUST FAIL if any non-zero status prints the sentence.
    func testAnInterruptInTheFirstSecondsIsNotExplainedAsAFailure() throws {
        let folder: URL = try makeFolder(named: "copilot-interrupted")
        let stubFolder: URL = try makeFolder(named: "copilot-stub-interrupted")
        let stub: URL = stubFolder.appendingPathComponent("copilot")
        try writeExecutable("""
        #!/bin/sh
        exit 130
        """, to: stub)
        let scriptPath: String = try CopilotLauncher.writeLauncherScript(
            workspacePath: folder.path,
            courseCode: "ICS3U_COPILOT_INTERRUPT_TEST",
            copilotPath: stub.path,
            configPath: "/tmp/mcp-ICS3U_COPILOT_INTERRUPT_TEST-copilot.json",
            prompt: "hello"
        )
        madePaths.append(scriptPath)
        let printed: String = try run(scriptPath: scriptPath)
        XCTAssertFalse(printed.contains(CopilotLauncher.stoppedAtOnceSentence), printed)
    }

    /// The doors must not share a script or a connection file: each is read
    /// after Plantoir hands it over, so a second launch seconds later would
    /// otherwise reach the first window.
    func testTheFilesAreNamedAfterTheCourseAndTheAgent() throws {
        let copilotScript: String = try CopilotLauncher.writeLauncherScript(
            workspacePath: plainFolder, courseCode: "ICS3U_COPILOT_NAME_TEST",
            copilotPath: "/opt/homebrew/bin/copilot", configPath: "/tmp/c.json", prompt: "hello"
        )
        madePaths.append(copilotScript)
        let codexScript: String = try CodexLauncher.writeLauncherScript(
            workspacePath: plainFolder, courseCode: "ICS3U_COPILOT_NAME_TEST",
            codexPath: "/opt/homebrew/bin/codex", serverPath: plainServer, prompt: "hello"
        )
        madePaths.append(codexScript)
        let claudeScript: String = try ClaudeCodeLauncher.writeLauncherScript(
            workspacePath: plainFolder, courseCode: "ICS3U_COPILOT_NAME_TEST",
            claudePath: "/usr/local/bin/claude", configPath: "/tmp/m.json", prompt: "hello"
        )
        madePaths.append(claudeScript)

        XCTAssertTrue(copilotScript.hasSuffix("/launch-ICS3U_COPILOT_NAME_TEST-copilot.command"), copilotScript)
        XCTAssertNotEqual(copilotScript, codexScript)
        XCTAssertNotEqual(copilotScript, claudeScript)

        let copilotConfig: String = try CopilotLauncher.writeConfig(
            workspacePath: plainFolder, courseCode: "ICS3U_COPILOT_NAME_TEST", serverPath: plainServer
        )
        madePaths.append(copilotConfig)
        let claudeConfig: String = try ClaudeCodeLauncher.writeConfig(
            workspacePath: plainFolder, courseCode: "ICS3U_COPILOT_NAME_TEST", serverPath: plainServer
        )
        madePaths.append(claudeConfig)
        XCTAssertNotEqual(copilotConfig, claudeConfig)
    }

    /// Nothing lands in the teacher's working folder, and the greeting is
    /// the one every door sends.
    func testNothingIsWrittenIntoTheWorkingFolderAndTheGreetingIsShared() throws {
        let workspace: URL = try makeFolder(named: "copilot-door")
        let trailFolder: URL = try makeFolder(named: "copilot-trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        defer {
            ActivityTrail.store = previousStore
        }

        let scriptPath: String = try CopilotLauncher.prepareSession(
            workspacePath: workspace.path,
            courseCode: "ICS3U_COPILOT_DOOR_TEST",
            courseName: "Grade 11 Computer Science",
            copilotPath: "/opt/homebrew/bin/copilot",
            serverPath: plainServer
        )
        madePaths.append(scriptPath)
        let supportDirectory: URL = try ClaudeCodeLauncher.supportDirectory()
        madePaths.append(supportDirectory.appendingPathComponent("mcp-ICS3U_COPILOT_DOOR_TEST-copilot.json").path)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.path), [])
        let greeting: String = ClaudeCodeLauncher.greeting(
            courseCode: "ICS3U_COPILOT_DOOR_TEST", courseName: "Grade 11 Computer Science"
        )
        let script: String = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(script.contains(" -i " + ClaudeCodeLauncher.escapeForShell(greeting) + "\n"), script)

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(CopilotLauncher.trailSentence(courseCode: "ICS3U_COPILOT_DOOR_TEST")), trail)
        XCTAssertFalse(trail.contains(CodexLauncher.trailSentence(courseCode: "ICS3U_COPILOT_DOOR_TEST")), trail)
    }

    /// Fix with's message replaces the greeting, double quotes become
    /// apostrophes, and the trail line carries no unit-planning clause.
    func testAnOpeningMessageReplacesTheGreeting() throws {
        let trailFolder: URL = try makeFolder(named: "copilot-trail-fix")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        defer {
            ActivityTrail.store = previousStore
        }
        let scriptPath: String = try CopilotLauncher.prepareSession(
            workspacePath: plainFolder,
            courseCode: "ICS3U_COPILOT_FIX_TEST",
            courseName: "",
            copilotPath: "/opt/homebrew/bin/copilot",
            serverPath: plainServer,
            unitPlans: UnitPlans.Reading(plans: [], unreadable: 0),
            greeting: "Fix \"this\" please"
        )
        madePaths.append(scriptPath)
        madePaths.append(try ClaudeCodeLauncher.supportDirectory()
            .appendingPathComponent("mcp-ICS3U_COPILOT_FIX_TEST-copilot.json").path)

        let script: String = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(script.contains(" -i " + ClaudeCodeLauncher.escapeForShell("Fix 'this' please") + "\n"), script)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        let plainLine: String = CopilotLauncher.trailSentence(courseCode: "ICS3U_COPILOT_FIX_TEST")
        XCTAssertTrue(trail.contains(plainLine), trail)
        XCTAssertFalse(trail.contains(plainLine + UnitPlans.trailSeparator), trail)
    }

    // MARK: - Which copilot is GitHub's

    /// An unsigned `copilot`, and a program signed by somebody else, are not
    /// GitHub's (plan review H3: Homebrew's own `copilot` is another
    /// vendor's tool at the same path). MUST FAIL if any executable called
    /// `copilot` is accepted.
    func testOnlyGitHubsCopilotIsAccepted() throws {
        let folder: URL = try makeFolder(named: "copilot-identity")
        let unsigned: URL = folder.appendingPathComponent("copilot")
        try writeExecutable("#!/bin/sh\necho other\n", to: unsigned)
        XCTAssertFalse(CopilotLauncher.isGitHubsCopilot(atPath: unsigned.path), "an unsigned script")
        XCTAssertFalse(CopilotLauncher.isGitHubsCopilot(atPath: "/bin/ls"), "a program Apple signed, not GitHub")
    }

    /// An npm install of GitHub's package is recognised by where it really
    /// lives: npm's `bin/copilot` is a link into
    /// `node_modules/@github/copilot/`.
    func testAnNpmInstallOfGitHubsPackageIsAccepted() throws {
        let prefix: URL = try makeFolder(named: "copilot-npm")
        let package: URL = prefix.appendingPathComponent("lib/node_modules/@github/copilot", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let loader: URL = package.appendingPathComponent("npm-loader.js")
        try writeExecutable("#!/usr/bin/env node\n", to: loader)
        let bin: URL = prefix.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link: URL = bin.appendingPathComponent("copilot")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../lib/node_modules/@github/copilot/npm-loader.js")
        XCTAssertTrue(CopilotLauncher.isGitHubsCopilot(atPath: link.path))

        // Another package's loader behind the same name is not.
        let other: URL = prefix.appendingPathComponent("lib/node_modules/copilot", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let otherLoader: URL = other.appendingPathComponent("index.js")
        try writeExecutable("#!/usr/bin/env node\n", to: otherLoader)
        XCTAssertFalse(CopilotLauncher.isGitHubsCopilot(atPath: otherLoader.path))
    }

    /// The search passes over a `copilot` that is not GitHub's and goes on
    /// down the list. MUST FAIL if the first executable is taken whatever it
    /// is.
    func testTheSearchPassesOverAnotherVendorsCopilot() throws {
        let first: URL = try makeFolder(named: "copilot-other-vendor")
        let awsCopilot: URL = first.appendingPathComponent("copilot")
        try writeExecutable("#!/bin/sh\necho other\n", to: awsCopilot)

        let prefix: URL = try makeFolder(named: "copilot-npm-later")
        let package: URL = prefix.appendingPathComponent("lib/node_modules/@github/copilot", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let loader: URL = package.appendingPathComponent("npm-loader.js")
        try writeExecutable("#!/usr/bin/env node\n", to: loader)
        let bin: URL = prefix.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let githubCopilot: URL = bin.appendingPathComponent("copilot")
        try FileManager.default.createSymbolicLink(atPath: githubCopilot.path, withDestinationPath: loader.path)

        let found: String? = ClaudeCodeLauncher.firstCommandLineTool(
            among: [first.appendingPathComponent("missing").path, awsCopilot.path, githubCopilot.path],
            accepting: { (candidate: String) -> Bool in
                return CopilotLauncher.isGitHubsCopilot(atPath: candidate)
            }
        )
        XCTAssertEqual(found, githubCopilot.path)

        let none: String? = ClaudeCodeLauncher.firstCommandLineTool(
            among: [awsCopilot.path],
            accepting: { (candidate: String) -> Bool in
                return CopilotLauncher.isGitHubsCopilot(atPath: candidate)
            }
        )
        XCTAssertNil(none, "only another vendor's copilot: no door")
    }

    /// The requirement ACCEPTS GitHub's real `copilot` when this Mac has one,
    /// and one character off it refuses that same binary (review M3): a
    /// requirement that refused everything would hide the door from every
    /// teacher and pass every refusal test. Skipped, saying so, on a Mac with
    /// no GitHub Copilot installed.
    func testTheRequirementAcceptsGitHubsRealCopilot() throws {
        var installed: String? = nil
        var places: [String] = [
            "/opt/homebrew/bin/copilot",
            "/usr/local/bin/copilot",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/copilot").path,
        ]
        if let casks = try? FileManager.default.contentsOfDirectory(atPath: "/opt/homebrew/Caskroom/copilot-cli") {
            for version in casks {
                places.append("/opt/homebrew/Caskroom/copilot-cli/\(version)/copilot")
            }
        }
        for place in places where installed == nil {
            let resolved: String = URL(fileURLWithPath: place).resolvingSymlinksInPath().path
            // Only where GitHub's own installs put it: Homebrew's `copilot`
            // formula is AWS's tool at the same link (review L1 of the fix
            // round), and an npm install is not a signed program.
            let isGitHubsInstall: Bool = resolved.contains("/Caskroom/copilot-cli/")
                || resolved.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/").path)
            if FileManager.default.isExecutableFile(atPath: resolved) && isGitHubsInstall {
                installed = resolved
            }
        }
        guard let binary = installed else {
            throw XCTSkip("No signed GitHub Copilot on this Mac, so the requirement's acceptance cannot be shown here.")
        }
        XCTAssertTrue(CopilotLauncher.carriesGitHubsSignature(atPath: binary), "GitHub's own \(binary) was refused")
        let teamOneOff: String = CopilotLauncher.signatureRequirement
            .replacingOccurrences(of: CopilotLauncher.signedTeam, with: "VEKTX9H2N8")
        XCTAssertFalse(CopilotLauncher.carriesSignature(atPath: binary, meeting: teamOneOff))
        let identifierOff: String = CopilotLauncher.signatureRequirement
            .replacingOccurrences(of: "identifier \"copilot\"", with: "identifier \"copilots\"")
        XCTAssertFalse(CopilotLauncher.carriesSignature(atPath: binary, meeting: identifierOff))
    }

    /// The requirement is one the system can read: a typo in it would make
    /// every check fail, which the door would show only as being missing.
    func testTheRequirementIsWellFormed() {
        var requirement: SecRequirement?
        XCTAssertEqual(
            SecRequirementCreateWithString(CopilotLauncher.signatureRequirement as CFString, [], &requirement),
            errSecSuccess
        )
        XCTAssertNotNil(requirement)
    }

    /// The requirement names GitHub's identifier and team, as the contract does.
    func testTheRequirementNamesGitHubsTeam() {
        XCTAssertTrue(CopilotLauncher.signatureRequirement.contains("identifier \"copilot\""))
        XCTAssertTrue(CopilotLauncher.signatureRequirement.contains("\"VEKTX9H2N7\""))
        XCTAssertTrue(CopilotLauncher.signatureRequirement.contains("anchor apple generic"))
    }

    // MARK: - Presence and the words

    /// GitHub Copilot alone is enough for Revise With ▸ to exist. MUST FAIL if
    /// `anyReviseTargetExists` leaves it out.
    func testCopilotAloneIsARevisingTarget() {
        XCTAssertTrue(OutsideAssistantPresence.anyReviseTargetExists(claude: false, codex: false, copilot: true, local: false))
        XCTAssertFalse(OutsideAssistantPresence.anyReviseTargetExists(claude: false, codex: false, copilot: false, local: false))
    }

    /// Rule 1: nothing a teacher reads from this door names the machinery,
    /// "CLI" included (GitHub's product is called "Copilot CLI"), and nothing
    /// says the assistant costs nothing (#783: not until it is confirmed).
    func testTheWordsNameNoMachineryAndPromiseNoPrice() {
        let every: [String] = [
            CopilotLauncher.menuItemTitle,
            CopilotLauncher.didNotOpenTitle,
            CopilotLauncher.couldNotStartSentence(courseCode: "ICS3U"),
            CopilotLauncher.stoppedAtOnceSentence,
            FixWithAssistant.copilotButtonTitle,
            PlanAUnit.copilotButtonTitle,
        ]
        for text in every {
            let words: [String] = text.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            for word in ["cli", "mcp", "terminal", "script", "toolchain", "docker", "container", "model", "token",
                         "server", "free"] {
                XCTAssertFalse(words.contains(word), "'\(word)' in: \(text)")
            }
            XCTAssertFalse(text.lowercased().contains("at no cost"), text)
            XCTAssertTrue(text.contains("GitHub Copilot"), "the full name, never bare Copilot: \(text)")
        }
    }
}
