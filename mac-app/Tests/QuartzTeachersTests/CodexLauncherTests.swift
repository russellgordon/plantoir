import XCTest
@testable import QuartzTeachers

/// The second outside door: handing a course to Codex.
///
/// The tests that matter here are the escaping ones. Codex takes its
/// configuration as `-c key=value` where the value is parsed as TOML, and the
/// values Plantoir interpolates are a path to the Plantoir binary and a path
/// to the teacher's working folder — both of which sit inside a TOML basic
/// string inside a shell-single-quoted argument. Two layers, and the inner one
/// fails QUIETLY when it is wrong: Codex does not reject a malformed value, it
/// falls back to treating it as a raw string, so `args` stops being a list and
/// the teacher meets a session that greets them and then cannot start its
/// server.
///
/// `testTheRenderedArgumentsSurviveTheShell` is the only test that proves both
/// layers at once, because it actually RUNS the script the app wrote, against
/// a stub standing in for `codex`, and reads the arguments that arrived.
final class CodexLauncherTests: XCTestCase {

    // MARK: - Stored properties

    /// A path with no character either layer has to escape, used wherever the
    /// test is about something other than escaping.
    private let plainFolder: String = "/Users/teacher/Teaching"

    private let plainServer: String = "/Applications/Plantoir.app/Contents/MacOS/Plantoir"

    // MARK: - What the door hands to Codex

    func testTheOverridesNameTheServerAndTheFolder() {
        let overrides: [String] = CodexLauncher.configurationOverrides(
            workspacePath: plainFolder,
            serverPath: plainServer
        )
        XCTAssertEqual(
            overrides,
            [
                "mcp_servers.plantoir.command=\"/Applications/Plantoir.app/Contents/MacOS/Plantoir\"",
                "mcp_servers.plantoir.args=[\"--mcp-stdio\",\"/Users/teacher/Teaching\"]",
                "mcp_servers.plantoir.startup_timeout_sec=60",
                "mcp_servers.plantoir.tool_timeout_sec=1800",
            ]
        )
    }

    /// Both timeouts are passed rather than left to Codex's own defaults,
    /// which differ between its source and its published reference and are in
    /// both cases shorter than a real publish. A future reader who deletes
    /// them as redundant should meet this test.
    func testBothTimeoutsArePassed() {
        let overrides: [String] = CodexLauncher.configurationOverrides(
            workspacePath: plainFolder,
            serverPath: plainServer
        )
        var sawStartup: Bool = false
        var sawTool: Bool = false
        for override in overrides {
            if override.hasPrefix("mcp_servers.plantoir.startup_timeout_sec=") {
                sawStartup = true
            }
            if override.hasPrefix("mcp_servers.plantoir.tool_timeout_sec=") {
                sawTool = true
            }
        }
        XCTAssertTrue(sawStartup, "Codex's startup timeout is version-dependent and shorter than a cold server start.")
        XCTAssertTrue(sawTool, "Codex's per-tool timeout would cut a real deploy, which is awaited and takes minutes.")
        XCTAssertGreaterThanOrEqual(CodexLauncher.toolTimeoutSeconds, 600)
    }

    /// No sandbox flag, no approval flag, no per-server approval mode. Codex
    /// asks the teacher itself before anything that changes a page, and
    /// passing a flag would quietly widen permissions they set for themselves.
    func testNoSandboxOrApprovalFlagsArePassed() throws {
        let script: String = try writtenScript(workspacePath: plainFolder, serverPath: plainServer)
        XCTAssertFalse(script.contains("--sandbox"), script)
        XCTAssertFalse(script.contains("--ask-for-approval"), script)
        XCTAssertFalse(script.contains("--full-auto"), script)
        XCTAssertFalse(script.contains("default_tools_approval_mode"), script)
        XCTAssertFalse(script.contains("--skip-git-repo-check"), script)
    }

    func testTheGreetingIsTheOneBothDoorsSend() throws {
        let scriptPath: String = try CodexLauncher.prepareSession(
            workspacePath: plainFolder,
            courseCode: "ICS3U_CODEX_TEST",
            courseName: "Grade 11 Computer Science",
            codexPath: "/opt/homebrew/bin/codex",
            serverPath: plainServer
        )
        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }

        let greeting: String = ClaudeCodeLauncher.greeting(
            courseCode: "ICS3U_CODEX_TEST",
            courseName: "Grade 11 Computer Science"
        )
        let script: String = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(
            script.hasSuffix(" " + ClaudeCodeLauncher.escapeForShell(greeting)),
            "The greeting is the last argument, and it is the same paragraph the Claude door sends.\n\(script)"
        )
    }

    /// The two doors must not share one script file: the script is read by the
    /// terminal after Plantoir has handed it over, so a second launch seconds
    /// later would otherwise reach the first window.
    func testTheScriptIsNamedAfterTheCourseAndTheAgent() throws {
        let codexScriptPath: String = try CodexLauncher.writeLauncherScript(
            workspacePath: plainFolder,
            courseCode: "ICS3U_CODEX_TEST",
            codexPath: "/opt/homebrew/bin/codex",
            serverPath: plainServer,
            prompt: "hello"
        )
        defer {
            try? FileManager.default.removeItem(atPath: codexScriptPath)
        }
        let claudeScriptPath: String = try ClaudeCodeLauncher.writeLauncherScript(
            workspacePath: plainFolder,
            courseCode: "ICS3U_CODEX_TEST",
            claudePath: "/usr/local/bin/claude",
            configPath: "/tmp/mcp.json",
            prompt: "hello"
        )
        defer {
            try? FileManager.default.removeItem(atPath: claudeScriptPath)
        }

        XCTAssertTrue(codexScriptPath.hasSuffix("/launch-ICS3U_CODEX_TEST-codex.command"), codexScriptPath)
        XCTAssertNotEqual(codexScriptPath, claudeScriptPath)
    }

    /// Nothing is written for the connection, and nothing is written anywhere
    /// but the app's own data directory — in particular, nothing lands in the
    /// teacher's working folder and nothing touches their own Codex
    /// configuration.
    func testNothingIsWrittenOutsideTheAppsOwnFolder() throws {
        let workspaceURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-door-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }

        let scratchFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-trail-\(UUID().uuidString)", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: scratchFolderURL)
        }

        let scriptPath: String = try CodexLauncher.prepareSession(
            workspacePath: workspaceURL.path,
            courseCode: "ICS3U_NOTHING_WRITTEN_TEST",
            courseName: "Grade 11 Computer Science",
            codexPath: "/opt/homebrew/bin/codex",
            serverPath: plainServer
        )
        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }

        let leftBehind: [String] = try FileManager.default.contentsOfDirectory(atPath: workspaceURL.path)
        XCTAssertEqual(leftBehind, [], "The Codex door wrote into the teacher's working folder.")

        let supportDirectory: URL = try ClaudeCodeLauncher.supportDirectory()
        let configuration: URL = supportDirectory.appendingPathComponent("mcp-ICS3U_NOTHING_WRITTEN_TEST.json")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: configuration.path),
            "The Codex door writes no configuration file — the server is described in its arguments."
        )
    }

    // MARK: - The trail

    func testTheTrailLineNamesCodexAndTheCourse() throws {
        let scratchFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-trail-\(UUID().uuidString)", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: scratchFolderURL)
        }

        let scriptPath: String = try CodexLauncher.prepareSession(
            workspacePath: plainFolder,
            courseCode: "ICS3U_CODEX_TEST",
            courseName: "Grade 11 Computer Science",
            codexPath: "/opt/homebrew/bin/codex",
            serverPath: plainServer
        )
        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains(CodexLauncher.trailSentence(courseCode: "ICS3U_CODEX_TEST")),
            "The Codex door left no line naming which assistant was started.\n\(trail)"
        )
        XCTAssertFalse(
            trail.contains(ClaudeCodeLauncher.trailSentence(courseCode: "ICS3U_CODEX_TEST")),
            "The two doors' lines are indistinguishable, which is the whole reason the line names the assistant."
        )
    }

    // MARK: - Escaping: the inner TOML layer

    func testTOMLEscapingOfTheSixShapesThatMatter() {
        XCTAssertEqual(CodexLauncher.escapeForTOMLString("/Users/r/Teaching"), "/Users/r/Teaching")
        XCTAssertEqual(CodexLauncher.escapeForTOMLString("/Users/r/Class Notes"), "/Users/r/Class Notes")
        XCTAssertEqual(CodexLauncher.escapeForTOMLString("/Users/r/Russell's Courses"), "/Users/r/Russell's Courses")
        XCTAssertEqual(CodexLauncher.escapeForTOMLString("/Users/r/My \"Notes\""), "/Users/r/My \\\"Notes\\\"")
        XCTAssertEqual(CodexLauncher.escapeForTOMLString("/Users/r/back\\slash"), "/Users/r/back\\\\slash")
        XCTAssertEqual(CodexLauncher.escapeForTOMLString("/Users/r/Français 🎓"), "/Users/r/Français 🎓")
        XCTAssertEqual(CodexLauncher.escapeForTOMLString("a\tb\nc"), "a\\tb\\nc")
    }

    /// The six fixtures again, this time as the whole `-c` argument the script
    /// carries — both layers applied, in the right order.
    func testTheRenderedOverrideForTheSixShapesThatMatter() throws {
        let fixtures: [(folder: String, expected: String)] = [
            (
                "/Users/r/Teaching",
                "'mcp_servers.plantoir.args=[\"--mcp-stdio\",\"/Users/r/Teaching\"]'"
            ),
            (
                "/Users/r/Class Notes",
                "'mcp_servers.plantoir.args=[\"--mcp-stdio\",\"/Users/r/Class Notes\"]'"
            ),
            (
                "/Users/r/Russell's Courses",
                "'mcp_servers.plantoir.args=[\"--mcp-stdio\",\"/Users/r/Russell'\\''s Courses\"]'"
            ),
            (
                "/Users/r/My \"Notes\"",
                "'mcp_servers.plantoir.args=[\"--mcp-stdio\",\"/Users/r/My \\\"Notes\\\"\"]'"
            ),
            (
                "/Users/r/back\\slash",
                "'mcp_servers.plantoir.args=[\"--mcp-stdio\",\"/Users/r/back\\\\slash\"]'"
            ),
            (
                "/Users/r/Français 🎓",
                "'mcp_servers.plantoir.args=[\"--mcp-stdio\",\"/Users/r/Français 🎓\"]'"
            ),
        ]

        for fixture in fixtures {
            let script: String = try writtenScript(workspacePath: fixture.folder, serverPath: plainServer)
            XCTAssertTrue(
                script.contains(" -c " + fixture.expected + " "),
                "The rendered override for \(fixture.folder) is not what it should be.\n\(script)"
            )
        }
    }

    // MARK: - Escaping: both layers, proved by running the script

    /// Writes the real script, points it at a stub standing in for `codex`,
    /// runs it, and reads back the arguments that actually arrived. Nothing
    /// real is launched: the stub is a three-line shell script in a temporary
    /// folder, and no terminal window is opened.
    ///
    /// This is the only test that proves the OUTER layer, and it is the one
    /// that would have caught a path containing a quote or a backslash.
    func testTheRenderedArgumentsSurviveTheShell() throws {
        let awkwardFolder: String = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex round \"trip\" \\ ’s-\(UUID().uuidString)", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: awkwardFolder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: awkwardFolder)
        }

        let stubFolder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-stub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stubFolder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: stubFolder)
        }

        let argumentsFile: URL = stubFolder.appendingPathComponent("arguments")
        let stubPath: URL = stubFolder.appendingPathComponent("codex")
        let stub: String = """
        #!/bin/sh
        printf '%s\\0' "$@" > '\(argumentsFile.path)'
        """
        try stub.write(to: stubPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubPath.path)

        let scriptPath: String = try CodexLauncher.writeLauncherScript(
            workspacePath: awkwardFolder,
            courseCode: "ICS3U_ROUNDTRIP_TEST",
            codexPath: stubPath.path,
            serverPath: "/Applications/Plan \"toir\".app/Contents/MacOS/Plantoir",
            prompt: ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "Grade 11 Computer Science")
        )
        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }

        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let raw: String = try String(contentsOf: argumentsFile, encoding: .utf8)
        var arrived: [String] = []
        for piece in raw.components(separatedBy: "\0") {
            arrived.append(piece)
        }
        // `printf '%s\0'` leaves a trailing empty piece after the last NUL.
        if arrived.last == "" {
            arrived.removeLast()
        }

        XCTAssertEqual(arrived.count, 9, "Nine arguments: four -c pairs and the greeting.\n\(arrived)")
        XCTAssertEqual(arrived[0], "-c")
        XCTAssertEqual(arrived[1], "mcp_servers.plantoir.command=\"/Applications/Plan \\\"toir\\\".app/Contents/MacOS/Plantoir\"")
        XCTAssertEqual(arrived[2], "-c")
        XCTAssertEqual(arrived[4], "-c")
        XCTAssertEqual(arrived[6], "-c")
        XCTAssertEqual(arrived[8], ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "Grade 11 Computer Science"))

        // And the value Codex would parse really is an ARRAY of two strings,
        // not the raw string its parser falls back to.
        let argumentsOverride: String = arrived[3]
        let prefix: String = "mcp_servers.plantoir.args="
        XCTAssertTrue(argumentsOverride.hasPrefix(prefix), argumentsOverride)
        let parsed: [String]? = CodexLauncherTests.parseTOMLStringArray(String(argumentsOverride.dropFirst(prefix.count)))
        XCTAssertEqual(parsed, ["--mcp-stdio", awkwardFolder])

        // The command is a single TOML basic string that unescapes back to the
        // path the app meant.
        let commandOverride: String = arrived[1]
        let commandPrefix: String = "mcp_servers.plantoir.command="
        let parsedCommand: [String]? = CodexLauncherTests.parseTOMLStringArray(
            "[" + commandOverride.dropFirst(commandPrefix.count) + "]"
        )
        XCTAssertEqual(parsedCommand, ["/Applications/Plan \"toir\".app/Contents/MacOS/Plantoir"])
    }

    // MARK: - Functions

    /// Writes the real script for a plain course and returns its contents.
    private func writtenScript(workspacePath: String, serverPath: String) throws -> String {
        let scriptPath: String = try CodexLauncher.writeLauncherScript(
            workspacePath: workspacePath,
            courseCode: "ICS3U_CODEX_TEST",
            codexPath: "/opt/homebrew/bin/codex",
            serverPath: serverPath,
            prompt: "hello"
        )
        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }
        return try String(contentsOfFile: scriptPath, encoding: .utf8)
    }

    /// A deliberately small TOML reader: an array of basic strings, which is
    /// the only shape this door produces. Written here rather than pulled in,
    /// because the point is to read the text the way Codex's parser would
    /// rather than the way the app wrote it.
    static func parseTOMLStringArray(_ text: String) -> [String]? {
        var values: [String] = []
        var current: String = ""
        var isInsideString: Bool = false
        var isEscaped: Bool = false
        var sawOpeningBracket: Bool = false
        var sawClosingBracket: Bool = false

        for character in text {
            if isEscaped {
                switch character {
                case "\\": current.append("\\")
                case "\"": current.append("\"")
                case "n": current.append("\n")
                case "t": current.append("\t")
                case "r": current.append("\r")
                default: return nil
                }
                isEscaped = false
                continue
            }
            if isInsideString {
                if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                    values.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case "[": sawOpeningBracket = true
            case "]": sawClosingBracket = true
            case "\"": isInsideString = true
            case ",", " ": continue
            default: return nil
            }
        }

        if !sawOpeningBracket || !sawClosingBracket || isInsideString {
            return nil
        }
        return values
    }
}
