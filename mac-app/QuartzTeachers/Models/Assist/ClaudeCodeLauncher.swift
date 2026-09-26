import AppKit
import Foundation

/// Starting a Claude Code session already connected to this working folder's
/// Plantoir tools, locked to one course.
///
/// The teacher never types a command. Everything the connection needs is
/// written for them and thrown away with the session:
///
/// * **No global configuration is touched.** The connection is passed with
///   `--mcp-config`, and `--strict-mcp-config` means only that server is
///   loaded — so a teacher's own MCP servers are neither used nor disturbed,
///   and nothing is left behind when the session ends.
/// * **Nothing lands in the teacher's folder.** The config sits in the app's
///   own data directory, not in the vault Obsidian is watching.
/// * **The course is named in the opening message, and nowhere else.** This
///   used to claim the session was "locked to the course … passed to the
///   server rather than asked for in a prompt", and that was never true:
///   `--mcp-stdio` takes the WORKING FOLDER, so every course in it is
///   reachable, and the only thing that points the session at one course is
///   the greeting. Corrected 2026-09-19, when a second door made the
///   difference matter: a reader who believed the old sentence would have
///   given Codex a narrowing that neither door has.
///
/// The menu item only appears when this returns true from
/// `isAvailable` — a teacher without Claude Code should not be offered a
/// door that opens onto an error.
///
/// `CodexLauncher` is the same door for `codex`, and borrows the helpers
/// below rather than copying them.
nonisolated enum ClaudeCodeLauncher {

    // MARK: - Stored properties

    /// A folder a test can name for `supportDirectory` explicitly. Nil in the
    /// app, where the real folder is always the answer.
    nonisolated(unsafe) static var supportDirectoryOverride: URL?

    /// The one throwaway folder for a whole test run, so a test that writes
    /// through one door and reads back through the other still finds it.
    static let supportDirectoryWhileTesting: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("plantoir-assist-under-test-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    /// The three sentences this door shows a teacher, in one place, because
    /// `contracts/app-rules.json` → `outsideAgents` carries them and a test
    /// compares the two. A sentence typed into the view and again into the
    /// contract is a sentence that will disagree with itself.
    static let menuItemTitle: String = "Revise with Claude…"

    static let didNotOpenTitle: String = "Claude didn’t open"

    // MARK: - Computed properties

    /// Both halves have to be present: the assistant, and the tools for it to use.
    static var isAvailable: Bool {
        return findClaude() != nil && findServer() != nil
    }

    // MARK: - Functions

    /// Where Claude Code is, or nil.
    static func findClaude() -> String? {
        return findCommandLineTool(named: "claude")
    }

    /// Where a command-line assistant is, or nil. Checked on PATH first, then
    /// the places its own installers put it.
    ///
    /// The explicit list does nearly all of the work, and it is the first
    /// thing somebody will try to simplify away: an app launched from the Dock
    /// inherits launchd's minimal PATH, so `onPath` usually finds nothing even
    /// on a Mac where the teacher's own shell finds the tool immediately.
    ///
    /// The same directories serve both doors — Codex's official installer
    /// script uses `$HOME/.local/bin`, and Homebrew, npm-global and bun land
    /// where they always do — so the list is written once with the name as a
    /// parameter rather than copied with one word changed.
    static func findCommandLineTool(named name: String) -> String? {
        if let onPath = onPath(name) {
            return onPath
        }

        let homeDirectory: URL = RealHome.forFiles
        var candidates: [String] = [
            homeDirectory.appendingPathComponent(".local/bin/\(name)").path,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            homeDirectory.appendingPathComponent(".npm-global/bin/\(name)").path,
            homeDirectory.appendingPathComponent(".bun/bin/\(name)").path,
        ]

        let nvmNodeDirectory: URL = homeDirectory.appendingPathComponent(".nvm/versions/node")
        if let nodeVersions = try? FileManager.default.contentsOfDirectory(atPath: nvmNodeDirectory.path) {
            for version in nodeVersions {
                let nvmToolPath: String = nvmNodeDirectory.appendingPathComponent("\(version)/bin/\(name)").path
                candidates.append(nvmToolPath)
            }
        }

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// The MCP server, which is the Plantoir binary itself answering `--mcp-stdio`.
    static func findServer() -> String? {
        if let executablePath = Bundle.main.executablePath,
           FileManager.default.isExecutableFile(atPath: executablePath) {
            return executablePath
        }
        if let firstArgument = ProcessInfo.processInfo.arguments.first,
           FileManager.default.isExecutableFile(atPath: firstArgument) {
            return firstArgument
        }
        return nil
    }

    /// Check if a binary exists and is executable in any folder listed in PATH.
    static func onPath(_ name: String) -> String? {
        guard let pathVariable = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }
        let directories: [String] = pathVariable.components(separatedBy: ":")
        for directory in directories {
            let candidate: String = (directory.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
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
        guard let claude: String = findClaude(),
              let server: String = findServer() else {
            return false
        }

        let configPath: String
        do {
            configPath = try writeConfig(workspacePath: workspacePath, courseCode: courseCode, serverPath: server)
        } catch {
            return false
        }

        let prompt: String = greeting(
            courseCode: courseCode, courseName: courseName, referenceCourses: referenceCourses
        )

        let scriptPath: String
        do {
            scriptPath = try writeLauncherScript(
                workspacePath: workspacePath,
                courseCode: courseCode,
                claudePath: claude,
                configPath: configPath,
                prompt: prompt
            )
        } catch {
            return false
        }

        ActivityTrail.note(.assistantOpened, trailSentence(courseCode: courseCode))

        return launchTerminal(scriptPath: scriptPath)
    }

    /// What a teacher is told when the door did not open.
    static func couldNotStartSentence(courseCode: String) -> String {
        return "Plantoir couldn’t start a Claude session for \(courseCode). "
            + "If Claude Code was updated or moved recently, restarting Plantoir may be enough."
    }

    /// The line the trail carries. It names WHICH assistant was started.
    static func trailSentence(courseCode: String) -> String {
        return "started Claude Code for \(courseCode)"
    }

    /// The opening message. It names the course and points at the plan tools,
    /// because the safety of every write here depends on a plan being shown to
    /// the teacher first — and an assistant that starts by reading is far more
    /// useful than one that starts by asking what to do.
    /// - Parameter referenceCourses: courses kept for reference that show the
    ///   SAME code as this one, each as "ICS3U-2025 (2025–26)". Empty for the
    ///   overwhelming majority of courses, and then the greeting is exactly
    ///   the paragraph it has always been.
    static func greeting(
        courseCode: String,
        courseName: String,
        referenceCourses: [String] = []
    ) -> String {
        var text: String = "I'm a teacher working on \(courseCode)"
        let trimmedName: String = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != courseCode {
            text.append(" (\(trimmedName))")
        }
        text.append(" in Plantoir. Use the plantoir tools for anything to do with this course. ")
        text.append("Start by listing its sections so we both know what's there. ")
        text.append("Before changing anything, use the matching plan tool first and show me what it says, ")
        text.append("in plain words, and wait for me to agree.")
        // **Decision (s): the two Revise doors are NOT offered on a reference
        // course. Instead a LIVE course's session is told the reference
        // courses exist**, so the agent's first reply can tell the teacher
        // they may point it at last year's material. Named here rather than
        // left to `list_courses`, because this paragraph is the one thing the
        // teacher and the agent both read at launch.
        //
        // It promises nothing Plantoir does: the agent reads them with its
        // own file tools and with the read tools it already has. In v1.3.0
        // there is no copy feature, and a sentence pointing at one would be
        // pointing at #207.
        if !referenceCourses.isEmpty {
            let listed: String = referenceCourses.joined(separator: ", ")
            text.append(" I also keep earlier \(courseCode) courses for reference: \(listed). ")
            text.append("You can read them and build on what is there; they are never deployed, ")
            text.append("and nothing in them can be changed.")
        }
        return text.replacingOccurrences(of: "\"", with: "'")
    }

    /// The reference courses a session on `course` should be told about:
    /// those showing the SAME code, each as "ICS3U-2025 (2025–26)".
    ///
    /// Same code only. A teacher opening an assistant on ICS3U is not helped
    /// by being told about last year's MPM2D, and a greeting that lists a
    /// teacher's whole shelf is one they stop reading.
    @MainActor
    static func referenceCoursesToMention(
        for course: Course,
        among courses: [Course],
        today: CalendarDay = CalendarDay.today()
    ) -> [String] {
        if course.isKeptForReference {
            return []
        }
        var listed: [String] = []
        for candidate in courses
        where candidate.isKeptForReference
            && candidate.displayCode.lowercased() == course.displayCode.lowercased() {
            var year: String = SchoolYear.otherGroupName
            if let startingYear = candidate.schoolYear(on: today) {
                year = SchoolYear.label(forStartingYear: startingYear)
            }
            listed.append("\(candidate.code) (\(year))")
        }
        listed.sort()
        return listed
    }

    /// The connection, written per course into the app's own data directory.
    /// One file per course so two sessions on different courses do not
    /// overwrite each other's configuration mid-launch.
    static func writeConfig(workspacePath: String, courseCode: String, serverPath: String) throws -> String {
        let appSupportDirectory: URL = try supportDirectory()

        let configuration: [String: Any] = [
            "mcpServers": [
                "plantoir": [
                    "command": serverPath,
                    "args": [
                        "--mcp-stdio",
                        workspacePath
                    ]
                ]
            ]
        ]

        let data: Data = try JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys]
        )
        let targetFile: URL = appSupportDirectory.appendingPathComponent("mcp-\(courseCode).json")
        try data.write(to: targetFile)
        return targetFile.path
    }

    /// Writes an executable `.command` launcher script in the app's data directory.
    static func writeLauncherScript(
        workspacePath: String,
        courseCode: String,
        claudePath: String,
        configPath: String,
        prompt: String
    ) throws -> String {
        let appSupportDirectory: URL = try supportDirectory()

        let scriptContent: String = """
        #!/bin/bash
        cd \(escapeForShell(workspacePath)) || exit 1
        \(escapeForShell(claudePath)) --mcp-config \(escapeForShell(configPath)) --strict-mcp-config \(escapeForShell(prompt))
        """

        let scriptFile: URL = appSupportDirectory.appendingPathComponent("launch-\(courseCode).command")
        try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
        return scriptFile.path
    }

    /// The app's own data directory for these sessions, created if needed.
    /// Deliberately not the teacher's working folder: nothing either door
    /// writes should appear in the vault Obsidian is watching.
    ///
    /// **Under the test suite, a throwaway folder instead** (issue #240). The
    /// launcher tests write real `mcp-<CODE>.json` and `launch-<CODE>.command`
    /// files through both doors and delete them afterwards — into the
    /// teacher's own `…/Plantoir/assist`, beside the ones Plantoir wrote for
    /// their real courses, until this. One such file outlived its test:
    /// `launch-ICS3U_ROUNDTRIP_TEST.command` (826 bytes, 2026-09-19) was found
    /// there on 2026-09-23, left by an earlier shape of the round-trip test
    /// that nothing cleans up. It is Russell's to delete, not the suite's.
    static func supportDirectory() throws -> URL {
        let appSupportDirectory: URL
        if let supportDirectoryOverride {
            appSupportDirectory = supportDirectoryOverride
        } else {
            appSupportDirectory = supportDirectory(
                isInsideTestBundle: RealHome.isInsideTestBundle,
                isUnderUITest: RealHome.isUnderUITest,
                stateDirectory: RealHome.stateDirectory,
                homeForFiles: RealHome.forFiles
            )
        }
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        return appSupportDirectory
    }

    /// Where the launch files go, as a pure function: the throwaway folder
    /// while test state belongs in one, otherwise `…/Plantoir/assist` in the
    /// home `RealHome` resolves — a UI test's state folder (#154) included.
    /// `homeForFiles` is only consulted without a state folder.
    static func supportDirectory(
        isInsideTestBundle: Bool,
        isUnderUITest: Bool,
        stateDirectory: URL?,
        homeForFiles: URL
    ) -> URL {
        if RealHome.keepsTestStateInThrowawayFolders(
            isInsideTestBundle: isInsideTestBundle,
            isUnderUITest: isUnderUITest,
            stateDirectory: stateDirectory
        ) {
            return supportDirectoryWhileTesting
        }
        return (stateDirectory ?? homeForFiles)
            .appendingPathComponent("Library/Application Support/Plantoir/assist")
    }

    /// Single-quote a string safely for POSIX shell execution.
    static func escapeForShell(_ text: String) -> String {
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Launches a terminal emulator running the generated .command script.
    ///
    /// Uses LaunchServices via `NSWorkspace` instead of AppleScript/AppleEvents
    /// so macOS does not require Automation / AppleEvents permissions.
    static func launchTerminal(scriptPath: String) -> Bool {
        let itermBundleID: String = "com.googlecode.iterm2"
        let isITermRunning: Bool = !NSRunningApplication.runningApplications(
            withBundleIdentifier: itermBundleID
        ).isEmpty

        if isITermRunning {
            if NSWorkspace.shared.openFile(scriptPath, withApplication: "iTerm") {
                return true
            }
        }

        if NSWorkspace.shared.openFile(scriptPath, withApplication: "Terminal") {
            return true
        }

        let scriptURL: URL = URL(fileURLWithPath: scriptPath)
        return NSWorkspace.shared.open(scriptURL)
    }
}
