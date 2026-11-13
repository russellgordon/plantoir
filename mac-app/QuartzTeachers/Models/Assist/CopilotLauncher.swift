import Foundation
import Security

/// Starting a GitHub Copilot session already connected to this working
/// folder's Plantoir tools (#783).
///
/// The third outside door, the same shape as `ClaudeCodeLauncher` and
/// `CodexLauncher`: find the tool, write what the connection needs and a
/// `.command` script into the app's own data folder, hand the script to a
/// terminal, write the line on the trail. It borrows `ClaudeCodeLauncher`'s
/// helpers rather than copying them. What is Copilot's own:
///
/// * **The connection is a FILE, passed with `--additional-mcp-config @file`.**
///   Copilot also takes the JSON inline, but that puts a string full of double
///   quotes inside a shell argument here and inside `cmd /k` quoting on
///   Windows, where #736 already spent a release on quoting. The file is
///   `mcp-<CODE>-copilot.json`, separate from Claude's `mcp-<CODE>.json` so a
///   Claude launch and a Copilot launch seconds apart cannot rewrite the file
///   the other's window has not read yet.
/// * **A 30-minute tool timeout is in the file.** Copilot 1.0.108 cuts a tool
///   call off at 60 seconds when the server's entry names no `timeout`
///   (`W0=6e4` in its bundle, read 2026-11-13), and `deploy_section` is
///   awaited and takes minutes. The same key covers tool discovery, which a
///   cold Plantoir binary needs.
/// * **A teacher's own servers come along**, as with Codex: Copilot has no
///   strict mode, and `--additional-mcp-config` ADDS to their own
///   configuration. The later source wins on a name, so Plantoir's `plantoir`
///   beats one of theirs. `--disable-builtin-mcps` turns off GitHub's own
///   built-in servers, and `--disable-mcp-server computer-use` its
///   desktop-control plugin, which the first leaves on; neither has any
///   business in a course session.
/// * **No permission flag at all** (Russell, 2026-11-13): Copilot asks the
///   teacher in its own window before each tool that changes something,
///   before the commands a printable handout needs, and before deploying.
/// * **No flag an older Copilot lacks.** An unknown flag makes Copilot exit 1
///   at once (measured, 1.0.108), and the door would already have said it
///   opened, so `-C` (added in 1.0.42) is not passed: the script's own `cd`
///   does that job. The script ends with a plain sentence when Copilot stops
///   within `stoppedAtOnceSeconds` of starting with a failure.
/// * **The `copilot` found must be GitHub's** (`isGitHubsCopilot`), because
///   `brew install copilot` installs AWS's tool of the same name at the same
///   path (measured 2026-11-13).
///
/// The menu item only appears when `isAvailable` is true. Plantoir never
/// installs Copilot here; #855 is where offering it is decided.
nonisolated enum CopilotLauncher {

    // MARK: - Stored properties

    /// The item's title inside Revise With ▸, as `ClaudeCodeLauncher.menuItemTitle`.
    /// "GitHub Copilot" rather than "Copilot" so it is not taken for
    /// Microsoft 365 Copilot, which many schools have (Russell, 2026-11-13).
    static let menuItemTitle: String = "GitHub Copilot…"

    static let didNotOpenTitle: String = "GitHub Copilot didn’t open"

    /// The name the trail and the sentences use for this assistant.
    static let displayName: String = "GitHub Copilot"

    /// How long one Plantoir tool may run, and how long Copilot may wait for
    /// the tools to be listed, in milliseconds: Copilot's `timeout` key on a
    /// local server. Thirty minutes, as `CodexLauncher.toolTimeoutSeconds`, so
    /// a real deploy is never cut off and a session that has genuinely wedged
    /// still ends.
    static let toolTimeoutMilliseconds: Int = 1_800_000

    /// How soon after starting a failure counts as "stopped at once": Copilot
    /// refusing an argument, or failing to start, exits within a second
    /// (measured: 0.07 s for an unknown flag, 1.0.108). Ten seconds is far
    /// longer than that and far shorter than any session a teacher used.
    static let stoppedAtOnceSeconds: Int = 10

    /// What the window says when Copilot stopped at once with a failure. It
    /// is the window's own text, so rule 1 applies to it.
    static let stoppedAtOnceSentence: String =
        "GitHub Copilot stopped as soon as it started. It may need updating: open it once on its own, or ask for help."

    /// The code signature GitHub's own `copilot` carries: identifier `copilot`,
    /// team `VEKTX9H2N7` (measured with `codesign -dv` on the Homebrew cask's
    /// binary, 1.0.105 and 1.0.108, 2026-11-13).
    static let signedIdentifier: String = "copilot"

    static let signedTeam: String = "VEKTX9H2N7"

    /// The npm package GitHub publishes the same tool as. An npm install is a
    /// Node script, not a signed program, so it is recognised by where it
    /// really lives.
    static let npmPackage: String = "@github/copilot"

    // MARK: - Computed properties

    /// Both halves have to be present: the assistant, and the tools for it to use.
    static var isAvailable: Bool {
        return findCopilot() != nil && ClaudeCodeLauncher.findServer() != nil
    }

    /// The code requirement a signed `copilot` must meet: GitHub's identifier
    /// and team, under an Apple-issued certificate.
    static var signatureRequirement: String {
        return "identifier \"\(signedIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(signedTeam)\""
    }

    // MARK: - Functions

    /// Where GitHub's Copilot is, or nil. The same places every door looks
    /// (`ClaudeCodeLauncher.commandLineToolCandidates`), unchanged: GitHub's
    /// install script writes `~/.local/bin`, the Homebrew cask `copilot-cli`
    /// writes Homebrew's folder, and npm its global folder. A `copilot` that
    /// is not GitHub's is passed over and the search goes on.
    ///
    /// Asked at launch and when Plantoir becomes active
    /// (`OutsideAssistantPresence`), and at the click, never while a menu
    /// draws. The signature check reads the signature and does not hash the
    /// whole program: 6 to 10 ms on the 196 MB binary, against 0.51 s for a
    /// full check (measured 2026-11-13), so it needs no cache.
    static func findCopilot() -> String? {
        return ClaudeCodeLauncher.firstCommandLineTool(
            among: ClaudeCodeLauncher.commandLineToolCandidates(named: "copilot"),
            accepting: { (candidate: String) -> Bool in
                return isGitHubsCopilot(atPath: candidate)
            }
        )
    }

    /// Whether the program at `path` is GitHub's Copilot: an npm install of
    /// `npmPackage` (the path, links followed, lies inside that package), or
    /// a program signed with GitHub's identifier and team.
    ///
    /// This checks WHICH program it is, never whether anybody is signed in to
    /// it (`outsideAgents.neverProbedForSignIn` holds for this door too). #855
    /// calls the same function after it installs Copilot.
    static func isGitHubsCopilot(atPath path: String) -> Bool {
        let resolvedPath: String = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolvedPath.contains("/node_modules/\(npmPackage)/") {
            return true
        }
        return carriesGitHubsSignature(atPath: resolvedPath)
    }

    /// Whether the program at `path` is signed as GitHub's `copilot`.
    ///
    /// The signature and the requirement are checked; the program's pages are
    /// not hashed (`kSecCSDoNotValidateExecutable`). The question is which
    /// maker's program this is, and a program that has been tampered with
    /// after signing is not a case this menu item has to answer.
    static func carriesGitHubsSignature(atPath path: String) -> Bool {
        return carriesSignature(atPath: path, meeting: signatureRequirement)
    }

    /// Whether the program at `path` meets `requirementText`, split out so a
    /// test can prove a requirement one character off refuses GitHub's own
    /// binary, and that the real one accepts it (review M3).
    static func carriesSignature(atPath path: String, meeting requirementText: String) -> Bool {
        var staticCode: SecStaticCode?
        let created: OSStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
        guard created == errSecSuccess, let staticCode else {
            return false
        }
        var requirement: SecRequirement?
        let parsed: OSStatus = SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
        guard parsed == errSecSuccess, let requirement else {
            return false
        }
        let flags: SecCSFlags = SecCSFlags(
            rawValue: kSecCSDoNotValidateExecutable | kSecCSDoNotValidateResources
        )
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }

    /// Open a session for one course. Returns false when it could not be
    /// started, so the caller can say so rather than leaving a teacher looking
    /// at nothing.
    /// - Parameter greeting: the opening message, when it is not the plain
    ///   one: Fix with GitHub Copilot… and Plan a Unit with GitHub Copilot…
    ///   hand over their own. Nil sends the plain greeting.
    @discardableResult
    static func open(
        workspacePath: String,
        courseCode: String,
        courseName: String,
        referenceCourses: [String] = [],
        unitPlans: UnitPlans.Reading? = nil,
        greeting openingMessage: String? = nil
    ) -> Bool {
        guard let copilot: String = findCopilot(),
              let server: String = ClaudeCodeLauncher.findServer() else {
            return false
        }

        let scriptPath: String
        do {
            scriptPath = try prepareSession(
                workspacePath: workspacePath,
                courseCode: courseCode,
                courseName: courseName,
                copilotPath: copilot,
                serverPath: server,
                referenceCourses: referenceCourses,
                unitPlans: unitPlans,
                greeting: openingMessage
            )
        } catch {
            return false
        }

        return ClaudeCodeLauncher.launchTerminal(scriptPath: scriptPath)
    }

    /// Everything the door does except hand the script to a terminal: writes
    /// the connection file and the script and records the line on the trail,
    /// returning the script's path. Split out so a test can read what is
    /// written without a terminal window opening on somebody's Mac.
    static func prepareSession(
        workspacePath: String,
        courseCode: String,
        courseName: String,
        copilotPath: String,
        serverPath: String,
        referenceCourses: [String] = [],
        unitPlans: UnitPlans.Reading? = nil,
        greeting openingMessage: String? = nil
    ) throws -> String {
        let configPath: String = try writeConfig(
            workspacePath: workspacePath, courseCode: courseCode, serverPath: serverPath
        )

        // The SAME greeting every door sends, and Fix with's or Plan a Unit's
        // message in its place when one is given (which says nothing about
        // unit planning, #707).
        var prompt: String = ClaudeCodeLauncher.greeting(
            courseCode: courseCode, courseName: courseName, referenceCourses: referenceCourses,
            unitPlans: unitPlans?.plans
        )
        var said: UnitPlans.Reading? = unitPlans
        if let openingMessage {
            prompt = openingMessage.replacingOccurrences(of: "\"", with: "'")
            said = nil
        }

        let scriptPath: String = try writeLauncherScript(
            workspacePath: workspacePath,
            courseCode: courseCode,
            copilotPath: copilotPath,
            configPath: configPath,
            prompt: prompt
        )

        ActivityTrail.note(.assistantOpened, trailSentence(courseCode: courseCode, unitPlans: said))

        return scriptPath
    }

    /// What a teacher is told when the door did not open.
    static func couldNotStartSentence(courseCode: String) -> String {
        return "Plantoir couldn’t start a GitHub Copilot session for \(courseCode). "
            + "If GitHub Copilot was updated or moved recently, restarting Plantoir may be enough."
    }

    /// The line the trail carries. It names WHICH assistant was started.
    static func trailSentence(courseCode: String) -> String {
        return "started GitHub Copilot for \(courseCode)"
    }

    /// The same line with what the greeting said about unit planning, as
    /// `ClaudeCodeLauncher.trailSentence(courseCode:unitPlans:)` does.
    static func trailSentence(courseCode: String, unitPlans: UnitPlans.Reading?) -> String {
        var line: String = trailSentence(courseCode: courseCode)
        if let unitPlans {
            line += UnitPlans.trailClause(unitPlans)
        }
        return line
    }

    /// The connection, as Copilot reads it: one local server named
    /// `plantoir`, the Plantoir binary answering `--mcp-stdio` for the working
    /// folder, the door's course in its environment for the server to HOLD
    /// (#458: never a narrowing), every tool, and the timeout.
    ///
    /// `"type": "local"` is the form the trial measured (2026-11-13, 38 of 38
    /// tools worked); 1.0.108's schema calls it a legacy alias of `"stdio"`,
    /// which older versions may not know.
    static func configuration(workspacePath: String, courseCode: String, serverPath: String) -> [String: Any] {
        let server: [String: Any] = [
            "type": "local",
            "command": serverPath,
            "args": [
                "--mcp-stdio",
                workspacePath
            ],
            "env": [
                AssistMCPServer.doorCourseVariable: courseCode,
                AssistMCPServer.doorAssistantVariable: "copilot"
            ],
            "tools": ["*"],
            "timeout": toolTimeoutMilliseconds
        ]
        return [
            "mcpServers": [
                "plantoir": server
            ]
        ]
    }

    /// Writes the connection file, per course and per door, into the app's
    /// own data folder (never the teacher's working folder), with
    /// `JSONSerialization` so a folder name holding a double quote or a
    /// backslash is written correctly.
    static func writeConfig(workspacePath: String, courseCode: String, serverPath: String) throws -> String {
        let appSupportDirectory: URL = try ClaudeCodeLauncher.supportDirectory()
        let data: Data = try JSONSerialization.data(
            withJSONObject: configuration(workspacePath: workspacePath, courseCode: courseCode, serverPath: serverPath),
            options: [.prettyPrinted, .sortedKeys]
        )
        let targetFile: URL = appSupportDirectory.appendingPathComponent("mcp-\(courseCode)-copilot.json")
        try data.write(to: targetFile)
        return targetFile.path
    }

    /// The command line, before the script wraps it: the program, the
    /// connection file (an absolute path after `@`, since a relative one would
    /// be read against Copilot's own folder), GitHub's own servers off, and
    /// the opening message sent as the first turn of an interactive session.
    static func commandLine(copilotPath: String, configPath: String, prompt: String) -> String {
        var line: String = ClaudeCodeLauncher.escapeForShell(copilotPath)
        line.append(" --additional-mcp-config ")
        line.append(ClaudeCodeLauncher.escapeForShell("@" + configPath))
        line.append(" --disable-builtin-mcps")
        // GitHub's desktop-control server (screenshots and clicks), a local
        // plugin that --disable-builtin-mcps leaves on: a course session has
        // no use for it, and a teacher's allow-all would let it act without
        // asking. Naming a server an older Copilot lacks does not stop it
        // (measured 2026-11-13: exit 0).
        line.append(" --disable-mcp-server computer-use")
        line.append(" -i ")
        line.append(ClaudeCodeLauncher.escapeForShell(prompt))
        return line
    }

    /// Writes an executable `.command` launcher script in the app's data
    /// directory, named `launch-<CODE>-copilot.command` so no two doors share
    /// a script (`outsideAgents.agents[codex].scriptNameCarriesTheAgentWhy`).
    ///
    /// After Copilot exits, a failure within `stoppedAtOnceSeconds` of the
    /// start prints `stoppedAtOnceSentence`, because the door has already said
    /// it opened, and Copilot's own "unexpected argument" error names its
    /// help, which tells a teacher nothing. Only an exit status of 1 to 127:
    /// 128 and above is a signal, such as the teacher's own Control-C, and a
    /// teacher who left is not told Copilot needs updating (review L1).
    static func writeLauncherScript(
        workspacePath: String,
        courseCode: String,
        copilotPath: String,
        configPath: String,
        prompt: String
    ) throws -> String {
        let appSupportDirectory: URL = try ClaudeCodeLauncher.supportDirectory()

        let scriptContent: String = """
        #!/bin/bash
        cd \(ClaudeCodeLauncher.escapeForShell(workspacePath)) || exit 1
        started=$SECONDS
        \(commandLine(copilotPath: copilotPath, configPath: configPath, prompt: prompt))
        status=$?
        if [ "$status" -ge 1 ] && [ "$status" -le 127 ] && [ $((SECONDS - started)) -lt \(stoppedAtOnceSeconds) ]; then
          echo
          echo \(ClaudeCodeLauncher.escapeForShell(stoppedAtOnceSentence))
        fi
        """

        let scriptFile: URL = appSupportDirectory.appendingPathComponent("launch-\(courseCode)-copilot.command")
        try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
        return scriptFile.path
    }
}
