import Foundation

/// Starting a Codex session already connected to this working folder's
/// Plantoir tools.
///
/// The second of the two outside doors. It is the same shape as
/// `ClaudeCodeLauncher` — find the tool, write a `.command` script, hand it to
/// a terminal — and it borrows that type's helpers rather than copying them.
/// Only two things differ, and both are Codex's:
///
/// * **Nothing at all is written for the connection.** Claude takes a config
///   FILE (`--mcp-config`); Codex takes inline configuration on its own
///   command line (`-c key=value`, each value parsed as TOML), so the server
///   is described in the arguments and no JSON file exists to write or clean
///   up. That is better than Claude's route, not worse.
/// * **A teacher's own assistants come along.** Codex has no
///   `--strict-mcp-config`: the command-line layer is MERGED with whatever is
///   already in their `~/.codex/config.toml`, so their own servers load beside
///   Plantoir's. That cannot be fixed from this side — see
///   `documentation/10-local-ai-assistant.md`.
///
/// The values are interpolated into TOML strings that sit inside
/// shell-single-quoted arguments, which is **two** layers of escaping rather
/// than one. `escapeForTOMLString` is the inner one, and it is not optional:
/// Codex does not reject a malformed value, it falls back to treating it as a
/// raw string, so a working folder whose name contains a double quote would
/// quietly turn `args` from a list into one string — a door that greets the
/// teacher and then cannot start its server.
///
/// The menu item only appears when `isAvailable` is true. Plantoir never
/// installs Codex, and never offers to.
nonisolated enum CodexLauncher {

    // MARK: - Stored properties

    /// The sentences this door shows a teacher, in one place, because
    /// `contracts/app-rules.json` → `outsideAgents` carries them and a test
    /// compares the two.
    static let menuItemTitle: String = "Revise with Codex…"

    static let didNotOpenTitle: String = "Codex didn’t open"

    /// How long Codex may wait for the server to come up, in seconds.
    ///
    /// Passed rather than left to Codex's own default because that default is
    /// version-dependent — 30 seconds in the current source, 10 in the
    /// published reference — and the server is a whole app binary starting
    /// cold. The difference is a door that opens and a door that says it timed
    /// out.
    static let startupTimeoutSeconds: Int = 60

    /// How long a single Plantoir tool may run, in seconds.
    ///
    /// Codex's own default is 300 seconds in the current source and 60 in the
    /// published reference. Both are too short: `deploy_section` is awaited,
    /// and a first publish builds the image and uploads through wrangler, which
    /// is minutes. Thirty minutes is chosen to be longer than any real publish
    /// while still ending a session that has genuinely wedged.
    static let toolTimeoutSeconds: Int = 1800

    // MARK: - Computed properties

    /// Both halves have to be present: the assistant, and the tools for it to use.
    static var isAvailable: Bool {
        return findCodex() != nil && ClaudeCodeLauncher.findServer() != nil
    }

    // MARK: - Functions

    /// Where Codex is, or nil. The same search the Claude door uses, with the
    /// name swapped — Codex's own installer script writes into `~/.local/bin`,
    /// which is already the first place looked.
    static func findCodex() -> String? {
        return ClaudeCodeLauncher.findCommandLineTool(named: "codex")
    }

    /// Open a session for one course. Returns false when it could not be
    /// started, so the caller can say so rather than leaving a teacher looking
    /// at nothing.
    @discardableResult
    static func open(
        workspacePath: String,
        courseCode: String,
        courseName: String,
        referenceCourses: [String] = []
    ) -> Bool {
        guard let codex: String = findCodex(),
              let server: String = ClaudeCodeLauncher.findServer() else {
            return false
        }

        let scriptPath: String
        do {
            scriptPath = try prepareSession(
                workspacePath: workspacePath,
                courseCode: courseCode,
                courseName: courseName,
                codexPath: codex,
                serverPath: server,
                referenceCourses: referenceCourses
            )
        } catch {
            return false
        }

        return ClaudeCodeLauncher.launchTerminal(scriptPath: scriptPath)
    }

    /// Everything the door does except hand the script to a terminal: writes
    /// the script and records the line on the trail, returning the script's
    /// path.
    ///
    /// Split out so a test can prove what is written and what is recorded
    /// without a terminal window opening on somebody's Mac.
    static func prepareSession(
        workspacePath: String,
        courseCode: String,
        courseName: String,
        codexPath: String,
        serverPath: String,
        referenceCourses: [String] = []
    ) throws -> String {
        // The greeting is the SAME paragraph both doors send. It names no
        // product, and a teacher who tries both should get the same session.
        let prompt: String = ClaudeCodeLauncher.greeting(
            courseCode: courseCode, courseName: courseName, referenceCourses: referenceCourses
        )

        let scriptPath: String = try writeLauncherScript(
            workspacePath: workspacePath,
            courseCode: courseCode,
            codexPath: codexPath,
            serverPath: serverPath,
            prompt: prompt
        )

        ActivityTrail.note(.assistantOpened, trailSentence(courseCode: courseCode))

        return scriptPath
    }

    /// What a teacher is told when the door did not open.
    static func couldNotStartSentence(courseCode: String) -> String {
        return "Plantoir couldn’t start a Codex session for \(courseCode). "
            + "If Codex was updated or moved recently, restarting Plantoir may be enough."
    }

    /// The line the trail carries. It names WHICH assistant was started,
    /// because "assistant opened" with no name is the one thing a report of
    /// "I asked it to do something and it went wrong" cannot afford to leave
    /// out once there is more than one door.
    static func trailSentence(courseCode: String) -> String {
        return "started Codex for \(courseCode)"
    }

    /// The `-c` overrides that describe Plantoir's MCP server to Codex for
    /// this one invocation, before shell escaping.
    ///
    /// Four separate dotted overrides rather than one inline table
    /// (`mcp_servers.plantoir={command=…,args=[…]}`): dotted keys merge into a
    /// teacher's configuration one key at a time and are the form the published
    /// documentation shows, so a reader can check them against it. The inline
    /// table would halve the escaping surface, which is the argument for it —
    /// but the escaping is tested here and matching the documentation is not.
    ///
    /// Nothing is persisted by any of this: the overrides live for the length
    /// of the session, and `~/.codex/config.toml` is neither read from nor
    /// written to by Plantoir.
    static func configurationOverrides(workspacePath: String, serverPath: String) -> [String] {
        var overrides: [String] = []
        overrides.append("mcp_servers.plantoir.command=\"\(escapeForTOMLString(serverPath))\"")
        overrides.append(
            "mcp_servers.plantoir.args=[\"--mcp-stdio\",\"\(escapeForTOMLString(workspacePath))\"]"
        )
        overrides.append("mcp_servers.plantoir.startup_timeout_sec=\(startupTimeoutSeconds)")
        overrides.append("mcp_servers.plantoir.tool_timeout_sec=\(toolTimeoutSeconds)")
        return overrides
    }

    /// Writes an executable `.command` launcher script in the app's data
    /// directory.
    ///
    /// The name carries `-codex` so that the two doors cannot overwrite each
    /// other. That is not tidiness: the script is read by Terminal or iTerm
    /// AFTER the app has handed it over, so two launches seconds apart on the
    /// same course would otherwise let the second command line reach the first
    /// window.
    static func writeLauncherScript(
        workspacePath: String,
        courseCode: String,
        codexPath: String,
        serverPath: String,
        prompt: String
    ) throws -> String {
        let appSupportDirectory: URL = try ClaudeCodeLauncher.supportDirectory()

        var commandLine: String = ClaudeCodeLauncher.escapeForShell(codexPath)
        for override in configurationOverrides(workspacePath: workspacePath, serverPath: serverPath) {
            commandLine.append(" -c ")
            commandLine.append(ClaudeCodeLauncher.escapeForShell(override))
        }
        commandLine.append(" ")
        commandLine.append(ClaudeCodeLauncher.escapeForShell(prompt))

        let scriptContent: String = """
        #!/bin/bash
        cd \(ClaudeCodeLauncher.escapeForShell(workspacePath)) || exit 1
        \(commandLine)
        """

        let scriptFile: URL = appSupportDirectory.appendingPathComponent("launch-\(courseCode)-codex.command")
        try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
        return scriptFile.path
    }

    /// Escape a value for a TOML basic string — the INNER of the two layers.
    ///
    /// TOML requires a backslash, a double quote and every control character
    /// to be written as an escape inside `"…"`. An apostrophe needs nothing
    /// here (the outer shell layer handles it), and ordinary UTF-8 above
    /// U+007F is legal in TOML and is left alone.
    ///
    /// Getting this wrong fails QUIETLY, which is why it is a function with
    /// its own tests rather than an inline `replacingOccurrences`: Codex falls
    /// back to treating an unparseable value as a raw string instead of
    /// reporting an error.
    static func escapeForTOMLString(_ text: String) -> String {
        var escaped: String = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\":
                escaped.append("\\\\")
            case "\"":
                escaped.append("\\\"")
            case "\u{08}":
                escaped.append("\\b")
            case "\u{09}":
                escaped.append("\\t")
            case "\u{0A}":
                escaped.append("\\n")
            case "\u{0C}":
                escaped.append("\\f")
            case "\u{0D}":
                escaped.append("\\r")
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    escaped.append(String(format: "\\u%04X", scalar.value))
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }
}
