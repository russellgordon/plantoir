import XCTest
@testable import QuartzTeachers

/// The set-up runner (#855) against a STAND-IN set-up in a scratch home: no
/// network, no maker's program, no window. The stand-in is shaped like
/// Codex's (a package, links in `~/.local/bin`, a marked block in the
/// start-up file `$SHELL` picks, the terminal question) and records the
/// environment it was given. Its mode file says how it behaves.
final class SetUpRunnerTests: XCTestCase {

    // MARK: - Stored properties

    static let standIn: String = """
    #!/bin/sh
    set -eu
    env | sort > "$HOME/env-seen.txt"
    if ( : </dev/tty ) 2>/dev/null; then echo had-a-terminal > "$HOME/tty-seen.txt"; read -r a </dev/tty; else echo no-terminal > "$HOME/tty-seen.txt"; fi
    mode="$(cat "$HOME/mode" 2>/dev/null || echo succeed)"
    case "$mode" in
      slow) sleep 600 & sleep 600 ;;
      quick) exit 0 ;;
    esac
    mkdir -p "$HOME/.codex/packages/standalone/releases/9.9/bin" "$HOME/.local/bin"
    if [ "$mode" = "unsigned" ]; then printf '#!/bin/sh\\n' > "$HOME/.codex/packages/standalone/releases/9.9/bin/codex"; else printf '#!/bin/sh\\n# MAKER-OK\\n' > "$HOME/.codex/packages/standalone/releases/9.9/bin/codex"; fi
    chmod +x "$HOME/.codex/packages/standalone/releases/9.9/bin/codex"
    ln -sfn "$HOME/.codex/packages/standalone/releases/9.9" "$HOME/.codex/packages/standalone/current"
    ln -sf "$HOME/.codex/packages/standalone/current/bin/codex" "$HOME/.local/bin/codex"
    case "${SHELL:-}" in */zsh) p="$HOME/.zprofile" ;; */bash) p="$HOME/.bash_profile" ;; *) p="$HOME/.profile" ;; esac
    if [ -f "$p" ] && grep -F "# >>> Codex installer >>>" "$p" >/dev/null 2>&1; then :; else
      { printf '\\n%s\\n' "# >>> Codex installer >>>"; printf '%s\\n' "export PATH=\\"$HOME/.local/bin:\\$PATH\\""; printf '%s\\n' "# <<< Codex installer <<<"; } >> "$p"; fi
    if [ "$mode" = "fail" ]; then exit 1; fi
    exit 0
    """

    var homes: [URL] = []

    // MARK: - Types

    /// Accepts a file holding MAKER-OK: a stand-in program nobody signed.
    struct StandInCheck: ProgramIdentityChecking {

        // MARK: - Functions

        func isSigned(atPath path: String, identifier: String, team: String) -> Bool {
            let resolved: URL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard let text = try? String(contentsOf: resolved, encoding: .utf8) else {
                return false
            }
            return text.contains("MAKER-OK")
        }
    }

    // MARK: - Functions

    override func tearDown() {
        for home in homes {
            try? FileManager.default.removeItem(at: home)
        }
        homes = []
        unsetenv("GITHUB_TOKEN")
        unsetenv("PREFIX")
        unsetenv("VERSION")
        super.tearDown()
    }

    func freshHome(mode: String) throws -> URL {
        let home: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-set-up-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try mode.write(to: home.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        homes.append(home)
        return home
    }

    static func dependencies(shell: String, reaches: Bool = true, limit: Duration = .seconds(60)) -> SetUpDependencies {
        let script: Data = Data(SetUpRunnerTests.standIn.utf8)
        return SetUpDependencies(
            reach: { (host: String) async -> Bool in
                return reaches
            },
            fetch: { (address: URL, allowedHosts: [String]) async -> SetUpDependencies.Fetched in
                return .script(script)
            },
            identity: StandInCheck(),
            accountShell: shell,
            userName: "teacher",
            longestRun: limit,
            stopGrace: .seconds(2)
        )
    }

    static func run(home: URL, _ dependencies: SetUpDependencies) async -> SetUpOutcome {
        let runner: SetUpRunner = SetUpRunner(
            recipe: AssistantSetUp.codex.recipe, home: home, kind: AssistantSetUp.recordKind, dependencies: dependencies
        )
        return await runner.perform(progress: { (phase: SetUpPhase) in
        })
    }

    static func text(_ url: URL) -> String {
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Tests

    /// The child gets the environment Plantoir builds and nothing it
    /// inherited (review H3), and no terminal.
    func testTheChildSeesOnlyWhatPlantoirGivesIt() async throws {
        setenv("GITHUB_TOKEN", "never-for-the-child", 1)
        setenv("PREFIX", "/tmp/elsewhere", 1)
        setenv("VERSION", "0.0.1", 1)
        let home: URL = try freshHome(mode: "succeed")
        let outcome: SetUpOutcome = await SetUpRunnerTests.run(home: home, SetUpRunnerTests.dependencies(shell: "/bin/zsh"))
        XCTAssertEqual(outcome, .finished)
        let seen: String = SetUpRunnerTests.text(home.appendingPathComponent("env-seen.txt"))
        XCTAssertFalse(seen.contains("GITHUB_TOKEN"))
        XCTAssertFalse(seen.contains("PREFIX="))
        XCTAssertFalse(seen.contains("VERSION="))
        XCTAssertTrue(seen.contains("HOME=\(home.path)\n"))
        XCTAssertTrue(seen.contains("SHELL=/bin/zsh\n"))
        XCTAssertTrue(seen.contains("PATH=\(SetUpRunner.childSearchPath)\n"))
        XCTAssertTrue(seen.contains("CODEX_NON_INTERACTIVE=1\n"))
        XCTAssertEqual(SetUpRunnerTests.text(home.appendingPathComponent("tty-seen.txt")), "no-terminal\n")
    }

    /// A finished set-up records what it created and the block it appended,
    /// and Remove puts the teacher's start-up file back byte for byte and
    /// keeps a folder that was already there.
    func testRemoveTakesAwayExactlyWhatWasAdded() async throws {
        let home: URL = try freshHome(mode: "succeed")
        let teachersLines: String = "# my own\nexport EDITOR=nano\n"
        try teachersLines.write(to: home.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/share"), withIntermediateDirectories: true)
        let outcome: SetUpOutcome = await SetUpRunnerTests.run(home: home, SetUpRunnerTests.dependencies(shell: "/bin/zsh"))
        XCTAssertEqual(outcome, .finished)
        let entry: SetUpRecordEntry = try XCTUnwrap(SetUpRecord.entry(for: "codex", home: home))
        XCTAssertEqual(entry.state, .installed)
        XCTAssertEqual(entry.created.sorted(), [".codex/packages/standalone", ".local/bin/codex"])
        XCTAssertEqual(entry.createdFolders.sorted(), [".codex", ".codex/packages", ".local/bin"])
        XCTAssertEqual(entry.profileChanges.count, 1)
        XCTAssertEqual(entry.profileChanges.first?.path, ".zprofile")
        let removal: SetUpRemoval = SetUpRecord.takeAway(entry, recipe: AssistantSetUp.codex.recipe, home: home)
        XCTAssertTrue(removal.finishedCleanly)
        XCTAssertEqual(SetUpRunnerTests.text(home.appendingPathComponent(".zprofile")), teachersLines)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".local/share").path))
    }

    /// bash writes `.bash_profile`, an empty shell `.profile`; a start-up
    /// file the set-up created goes again on Remove.
    func testTheStartUpFileFollowsTheAccountsShell() async throws {
        let bashHome: URL = try freshHome(mode: "succeed")
        _ = await SetUpRunnerTests.run(home: bashHome, SetUpRunnerTests.dependencies(shell: "/bin/bash"))
        let bashEntry: SetUpRecordEntry = try XCTUnwrap(SetUpRecord.entry(for: "codex", home: bashHome))
        XCTAssertEqual(bashEntry.profileChanges.first?.path, ".bash_profile")
        XCTAssertEqual(bashEntry.profileChanges.first?.fileWasCreated, true)
        _ = SetUpRecord.takeAway(bashEntry, recipe: AssistantSetUp.codex.recipe, home: bashHome)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bashHome.appendingPathComponent(".bash_profile").path))

        let otherHome: URL = try freshHome(mode: "succeed")
        _ = await SetUpRunnerTests.run(home: otherHome, SetUpRunnerTests.dependencies(shell: ""))
        let otherEntry: SetUpRecordEntry = try XCTUnwrap(SetUpRecord.entry(for: "codex", home: otherHome))
        XCTAssertEqual(otherEntry.profileChanges.first?.path, ".profile")
    }

    /// A linked start-up file is written through, and the link kept.
    func testALinkedStartUpFileKeepsItsLink() async throws {
        let home: URL = try freshHome(mode: "succeed")
        let dotfiles: URL = home.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try "export A=1\n".write(to: dotfiles.appendingPathComponent("zprofile"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent(".zprofile"), withDestinationURL: dotfiles.appendingPathComponent("zprofile")
        )
        _ = await SetUpRunnerTests.run(home: home, SetUpRunnerTests.dependencies(shell: "/bin/zsh"))
        let entry: SetUpRecordEntry = try XCTUnwrap(SetUpRecord.entry(for: "codex", home: home))
        _ = SetUpRecord.takeAway(entry, recipe: AssistantSetUp.codex.recipe, home: home)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: home.appendingPathComponent(".zprofile").path))
        XCTAssertEqual(SetUpRunnerTests.text(dotfiles.appendingPathComponent("zprofile")), "export A=1\n")
    }

    /// A block that was already there is not recorded and not removed.
    func testABlockAlreadyThereIsTheTeachers() async throws {
        let home: URL = try freshHome(mode: "succeed")
        let existing: String = "\n# >>> Codex installer >>>\nexport PATH=\"x:$PATH\"\n# <<< Codex installer <<<\n"
        try existing.write(to: home.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
        _ = await SetUpRunnerTests.run(home: home, SetUpRunnerTests.dependencies(shell: "/bin/zsh"))
        let entry: SetUpRecordEntry = try XCTUnwrap(SetUpRecord.entry(for: "codex", home: home))
        XCTAssertEqual(entry.profileChanges, [])
        _ = SetUpRecord.takeAway(entry, recipe: AssistantSetUp.codex.recipe, home: home)
        XCTAssertEqual(SetUpRunnerTests.text(home.appendingPathComponent(".zprofile")), existing)
    }

    /// Each failure takes away what it added and leaves no record.
    func testEveryFailureLeavesNothingBehind() async throws {
        let cases: [(mode: String, expect: SetUpOutcome)] = [
            ("fail", .exited(status: 1)),
            ("unsigned", .notFromMaker(program: "codex")),
            ("quick", .leftNothing(program: "codex"))
        ]
        for testCase in cases {
            let home: URL = try freshHome(mode: testCase.mode)
            let outcome: SetUpOutcome = await SetUpRunnerTests.run(home: home, SetUpRunnerTests.dependencies(shell: "/bin/zsh"))
            XCTAssertEqual(outcome, testCase.expect, testCase.mode)
            XCTAssertNil(SetUpRecord.entry(for: "codex", home: home), testCase.mode)
            XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path), testCase.mode)
            XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".zprofile").path), testCase.mode)
        }
    }

    /// No connection runs nothing.
    func testNoConnectionRunsNothing() async throws {
        let home: URL = try freshHome(mode: "succeed")
        let outcome: SetUpOutcome = await SetUpRunnerTests.run(
            home: home, SetUpRunnerTests.dependencies(shell: "/bin/zsh", reaches: false)
        )
        XCTAssertEqual(outcome, .noConnection(host: "chatgpt.com"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("env-seen.txt").path))
    }

    /// A set-up past its limit is stopped, background children and all; so
    /// is one the teacher stops.
    func testALongSetUpAndAStoppedOneEnd() async throws {
        let slowHome: URL = try freshHome(mode: "slow")
        let started: Date = Date()
        let outcome: SetUpOutcome = await SetUpRunnerTests.run(
            home: slowHome, SetUpRunnerTests.dependencies(shell: "/bin/zsh", limit: .seconds(2))
        )
        XCTAssertEqual(outcome, .tookTooLong)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)

        let stopHome: URL = try freshHome(mode: "slow")
        let runner: SetUpRunner = SetUpRunner(
            recipe: AssistantSetUp.codex.recipe, home: stopHome, kind: AssistantSetUp.recordKind,
            dependencies: SetUpRunnerTests.dependencies(shell: "/bin/zsh")
        )
        let task: Task<SetUpOutcome, Never> = Task {
            return await runner.perform(progress: { (phase: SetUpPhase) in
            })
        }
        // Waiting until the stand-in is actually running, not for a guessed
        // length of time: it writes tty-seen.txt before it sleeps.
        while !FileManager.default.fileExists(atPath: stopHome.appendingPathComponent("tty-seen.txt").path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        runner.stop()
        let stopped: SetUpOutcome = await task.value
        XCTAssertEqual(stopped, .stopped)
        XCTAssertNil(SetUpRecord.entry(for: "codex", home: stopHome))
    }

    /// A damaged or edited record never deletes outside the recipe.
    func testADamagedRecordDeletesNothingElse() throws {
        let home: URL = try freshHome(mode: "succeed")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        let entry: SetUpRecordEntry = SetUpRecordEntry(
            key: "codex", kind: "assistant", state: .installed, started: Date(), finished: Date(), before: nil,
            created: ["Documents", "../outside"], createdFolders: ["Documents"], profileChanges: [], changedInPlace: []
        )
        let removal: SetUpRemoval = SetUpRecord.takeAway(entry, recipe: AssistantSetUp.codex.recipe, home: home)
        XCTAssertEqual(removal.refused, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Documents").path))
    }

    /// Redirects go only to HTTPS on the recipe's hosts.
    func testRedirectsStayWithTheMaker() {
        let hosts: [String] = AssistantSetUp.codex.recipe.allowedHosts
        XCTAssertTrue(SetUpRedirectGuard.follows(URL(string: "https://releases.openai.com/codex/install.sh"), allowedHosts: hosts))
        XCTAssertFalse(SetUpRedirectGuard.follows(URL(string: "https://example.org/install.sh"), allowedHosts: hosts))
        XCTAssertFalse(SetUpRedirectGuard.follows(URL(string: "http://releases.openai.com/codex/install.sh"), allowedHosts: hosts))
    }

    /// The real check refuses a script and Apple's own program, and the
    /// requirement names the identifier as well as the team (review M1).
    func testTheRealCheckRefusesWhatIsNotTheMakers() throws {
        let home: URL = try freshHome(mode: "succeed")
        let script: URL = home.appendingPathComponent("not-signed")
        try "#!/bin/sh\n".write(to: script, atomically: true, encoding: .utf8)
        let check: DeveloperIDCheck = DeveloperIDCheck()
        XCTAssertFalse(check.isSigned(atPath: script.path, identifier: "codex", team: "2DC432GLL2"))
        XCTAssertFalse(check.isSigned(atPath: "/bin/ls", identifier: "com.apple.ls", team: "2DC432GLL2"))
        let requirement: String = DeveloperIDCheck.requirement(identifier: "codex", team: "2DC432GLL2")
        XCTAssertTrue(requirement.contains("identifier \"codex\""))
        XCTAssertTrue(requirement.contains("leaf[subject.OU] = \"2DC432GLL2\""))
        XCTAssertTrue(requirement.contains("1.2.840.113635.100.6.1.13"))
    }
}

/// The centre's own rules, with the door, the window and the record in a
/// scratch home.
@MainActor
final class AssistantSetUpCentreTests: XCTestCase {

    // MARK: - Tests

    /// Remove offers and does nothing for an assistant the record does not
    /// hold, and a copy the teacher has is never set up over.
    func testNothingIsDoneToTheTeachersOwnCopy() throws {
        let home: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-centre-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: home)
        }
        var opened: [String] = []
        let centre: AssistantSetUpCentre = AssistantSetUpCentre(
            home: home,
            dependencies: SetUpRunnerTests.dependencies(shell: "/bin/zsh"),
            doorFinds: { (key: String) -> Bool in
                return true
            },
            openWindow: { (path: String) -> Bool in
                opened.append(path)
                return true
            },
            windowFolder: { () throws -> URL in
                return home
            },
            presenceChanged: {
            }
        )
        centre.refresh()
        let codex: AssistantSetUpAgent = AssistantSetUp.codex
        XCTAssertEqual(centre.state(of: codex), .setUpElsewhere)
        XCTAssertFalse(centre.canRemove(codex))
        centre.setUp(codex)
        XCTAssertEqual(centre.state(of: codex), .setUpElsewhere, "never set up over the teacher's copy")
        XCTAssertTrue(SetUpsUnderWay.names.isEmpty)
        centre.remove(codex)
        XCTAssertEqual(opened, [])
    }

    /// The sign-in window's script runs the maker's own sign-in, writes the
    /// exit code alone, and ends with a plain line.
    func testTheSignInScriptKeepsOnlyTheExitCode() {
        let script: String = AssistantSetUpCentre.signInScript(
            agent: AssistantSetUp.claude, program: "/Users/t/.local/bin/claude", resultPath: "/tmp/r.result"
        )
        XCTAssertTrue(script.contains("'/Users/t/.local/bin/claude' 'auth' 'login'"))
        XCTAssertTrue(script.contains("printf '%s\\n' \"$status\" > '/tmp/r.result'"))
        XCTAssertTrue(script.contains(AssistantSetUpWording.signInWindowDone))
    }

    /// Trail lines carry no path and no account.
    func testTheTrailLinesNameNoPath() {
        let lines: [String] = [
            AssistantSetUpCentre.finishedLine(agent: AssistantSetUp.codex, outcome: .finished, seconds: 4),
            AssistantSetUpCentre.finishedLine(agent: AssistantSetUp.codex, outcome: .exited(status: 137), seconds: 4),
            AssistantSetUpCentre.removedLine(agent: AssistantSetUp.codex, removal: SetUpRemoval()),
            AssistantSetUpCentre.checkedLine(agent: AssistantSetUp.copilot, signIn: .finished(0), statusCode: nil, signedIn: true),
            AssistantSetUpCentre.settledLine(agent: AssistantSetUp.claude, finished: false),
            AssistantSetUpCentre.openedLine(from: .reviseWith)
        ]
        for line in lines {
            XCTAssertFalse(line.contains("/"), line)
        }
        XCTAssertEqual(lines[0], "set up Codex: in place and made by OpenAI, in 4 s")
    }
}
