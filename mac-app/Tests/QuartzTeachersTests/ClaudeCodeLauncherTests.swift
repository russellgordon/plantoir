import XCTest
@testable import QuartzTeachers

final class ClaudeCodeLauncherTests: XCTestCase {

    // MARK: - Functions

    func testGreetingWithDistinctCourseName() {
        let text: String = ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "Grade 11 Computer Science")
        XCTAssertTrue(text.contains("I'm a teacher working on ICS3U (Grade 11 Computer Science) in Plantoir."))
        XCTAssertTrue(text.contains("Use the plantoir tools for anything to do with this course."))
        XCTAssertTrue(text.contains("Start by listing its sections so we both know what's there."))
        XCTAssertTrue(text.contains("Before changing anything, use the matching plan tool first and show me what it says, in plain words, and wait for me to agree."))
        XCTAssertFalse(text.contains("\""))
    }

    func testGreetingWithIdenticalCourseName() {
        let text: String = ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "ICS3U")
        XCTAssertTrue(text.contains("I'm a teacher working on ICS3U in Plantoir."))
        XCTAssertFalse(text.contains("ICS3U (ICS3U)"))
    }

    func testGreetingWithEmptyCourseName() {
        let text: String = ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "   ")
        XCTAssertTrue(text.contains("I'm a teacher working on ICS3U in Plantoir."))
        XCTAssertFalse(text.contains("("))
    }

    func testWriteConfigCreatesValidJSON() throws {
        let tempWorkspace: String = "/Users/teacher/Teaching"
        let courseCode: String = "ICS3U_TEST"
        let dummyServer: String = "/Applications/Plantoir.app/Contents/MacOS/Plantoir"

        let configPath: String = try ClaudeCodeLauncher.writeConfig(
            workspacePath: tempWorkspace,
            courseCode: courseCode,
            serverPath: dummyServer
        )
        defer {
            try? FileManager.default.removeItem(atPath: configPath)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))

        let data: Data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let jsonObject: [String: Any]? = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(jsonObject)

        let mcpServers: [String: Any]? = jsonObject?["mcpServers"] as? [String: Any]
        XCTAssertNotNil(mcpServers)

        let plantoirServer: [String: Any]? = mcpServers?["plantoir"] as? [String: Any]
        XCTAssertNotNil(plantoirServer)
        XCTAssertEqual(plantoirServer?["command"] as? String, dummyServer)

        let args: [String]? = plantoirServer?["args"] as? [String]
        XCTAssertEqual(args, ["--mcp-stdio", tempWorkspace])
    }

    func testEscapeForShellSingleQuotes() {
        let simple: String = ClaudeCodeLauncher.escapeForShell("/path/to/folder")
        XCTAssertEqual(simple, "'/path/to/folder'")

        let withSpaces: String = ClaudeCodeLauncher.escapeForShell("/path/with space/folder")
        XCTAssertEqual(withSpaces, "'/path/with space/folder'")

        let withSingleQuotes: String = ClaudeCodeLauncher.escapeForShell("I'm a teacher")
        XCTAssertEqual(withSingleQuotes, "'I'\\''m a teacher'")
    }

    func testWriteLauncherScriptCreatesExecutableFile() throws {
        let tempWorkspace: String = "/Users/teacher/Teaching"
        let courseCode: String = "ICS3U_TEST"
        let dummyClaude: String = "/usr/local/bin/claude"
        let dummyConfig: String = "/path/to/mcp.json"
        let prompt: String = "Hello Claude"

        let scriptPath: String = try ClaudeCodeLauncher.writeLauncherScript(
            workspacePath: tempWorkspace,
            courseCode: courseCode,
            claudePath: dummyClaude,
            configPath: dummyConfig,
            prompt: prompt
        )
        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptPath))

        let content: String = try String(contentsOfFile: scriptPath, encoding: .utf8)
        XCTAssertTrue(content.contains("#!/bin/bash"))
        XCTAssertTrue(content.contains("cd '\(tempWorkspace)' || exit 1"))
        XCTAssertTrue(content.contains("'\(dummyClaude)' --mcp-config '\(dummyConfig)' --strict-mcp-config '\(prompt)'"))

        let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: scriptPath)
        let permissions: NSNumber? = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o755)
    }

    func testFindServerReturnsPath() {
        let server: String? = ClaudeCodeLauncher.findServer()
        XCTAssertNotNil(server)
        if let server {
            XCTAssertTrue(FileManager.default.fileExists(atPath: server))
        }
    }

    // MARK: - The golden tests: what this door writes, to the byte

    /// The three tests above this mark ask whether the script CONTAINS the
    /// right fragments, which is not enough to notice a line being added,
    /// dropped or reordered around them. These three pin the whole thing.
    ///
    /// They exist because a second door was added beside this one, and
    /// "nothing about the Claude session changed" has to be a measurement
    /// rather than a claim: the greeting, the script and the configuration
    /// file are compared against literals, so any edit to the shared helpers
    /// that moves a single byte of what a teacher's Claude session receives
    /// fails here by name.
    func testTheGreetingIsExactlyThis() {
        let text: String = ClaudeCodeLauncher.greeting(courseCode: "ICS3U", courseName: "Grade 11 Computer Science")
        XCTAssertEqual(
            text,
            "I'm a teacher working on ICS3U (Grade 11 Computer Science) in Plantoir. "
                + "Use the plantoir tools for anything to do with this course. "
                + "Start by listing its sections so we both know what's there. "
                + "Before changing anything, use the matching plan tool first and show me what it says, "
                + "in plain words, and wait for me to agree."
        )
    }

    func testTheLauncherScriptIsExactlyThis() throws {
        let scriptPath: String = try ClaudeCodeLauncher.writeLauncherScript(
            workspacePath: "/Users/teacher/Teaching",
            courseCode: "ICS3U_GOLDEN",
            claudePath: "/usr/local/bin/claude",
            configPath: "/Users/teacher/Library/Application Support/Plantoir/assist/mcp-ICS3U_GOLDEN.json",
            prompt: "I'm a teacher working on ICS3U in Plantoir."
        )
        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }

        let written: String = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let expected: String = """
        #!/bin/bash
        cd '/Users/teacher/Teaching' || exit 1
        '/usr/local/bin/claude' --mcp-config '/Users/teacher/Library/Application Support/Plantoir/assist/mcp-ICS3U_GOLDEN.json' --strict-mcp-config 'I'\\''m a teacher working on ICS3U in Plantoir.'
        """
        XCTAssertEqual(written, expected)
        XCTAssertTrue(scriptPath.hasSuffix("/launch-ICS3U_GOLDEN.command"), scriptPath)
    }

    func testTheConfigurationFileIsExactlyTheseBytes() throws {
        let configPath: String = try ClaudeCodeLauncher.writeConfig(
            workspacePath: "/Users/teacher/Teaching",
            courseCode: "ICS3U_GOLDEN",
            serverPath: "/Applications/Plantoir.app/Contents/MacOS/Plantoir"
        )
        defer {
            try? FileManager.default.removeItem(atPath: configPath)
        }

        let written: Data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let expected: String = """
        {
          "mcpServers" : {
            "plantoir" : {
              "args" : [
                "--mcp-stdio",
                "\\/Users\\/teacher\\/Teaching"
              ],
              "command" : "\\/Applications\\/Plantoir.app\\/Contents\\/MacOS\\/Plantoir"
            }
          }
        }
        """
        XCTAssertEqual(written, Data(expected.utf8))
        XCTAssertTrue(configPath.hasSuffix("/mcp-ICS3U_GOLDEN.json"), configPath)
    }
}
