import Foundation
import Network
import Observation

/// Getting the website builder ready in the BACKGROUND, at first launch and at
/// the first launch of each new version, so that a teacher's first preview is
/// fast (bundle B, Russell's change of 2026-09-26).
///
/// **What it costs a teacher otherwise.** A first course used to spend its
/// first preview installing the helper programs, starting the builder's
/// virtual machine (22–27 s from the disk the app carries, #312) and building
/// the website builder itself (~340 MB downloaded, 88–137 s in a fresh
/// 3-CPU virtual machine, 49 s on an M4 Pro) — minutes of "Building your
/// website builder…" before a single page appeared. The teacher spends
/// minutes in the wizard anyway; this does the work then.
///
/// **What it runs.** `setup.sh --prepare-builder`, the launcher's own mode,
/// from a folder of Plantoir's (`~/Library/Application Support/Plantoir/
/// getting-ready`) holding only that launcher and a copy of the recipe made
/// by the SAME function that mirrors a working folder's `.toolchain`
/// (`WorkspaceModel.copyToolchainFiles`). The image is named by a hash of the
/// recipe, so the one built here is exactly the one every working folder's
/// launchers look for. No course, no workspace, no builds folder is made; no
/// toolchain logic is written in Swift.
///
/// **Two launchers never get the builder ready at once**, and that rule lives
/// in the launchers, not here: a Create or a Preview that arrives mid-build
/// waits for this one's turn and then finds the builder ready
/// (`GETTING-READY TURN BLOCK`, `builderWarmUp.turnCases`). So nothing in the
/// app has to remember to wait, and a teacher at the command line gets the
/// same rule.
///
/// **When it does not run** — every case is `contracts/app-rules.json` →
/// `builderWarmUp.startsWhen`: not in the unit suite or a UI test, not when
/// this binary is the assistant's server, a scheduled publish or the contract
/// writer, not when the app carries no recipe, not when this version has
/// already got it ready, and not offline or in Low Data Mode — then it says
/// NOTHING to the teacher (a line on the trail only) and the builder is got
/// ready the old way, at the first preview.
///
/// Rejected: running it only once a working folder is chosen (the folder's
/// `.toolchain` is not there until a course exists, and the teacher's time in
/// the wizard is what this spends); a status window or a progress bar (it is
/// background work the teacher did not ask for, so it gets one plain line);
/// stopping it at quit (what was downloaded would be thrown away, and #220's
/// quit path already leaves the builder running while a launcher is).
@MainActor
@Observable
final class BuilderWarmUp {

    // MARK: - Nested types

    /// What the network allows, as the decision sees it.
    enum NetworkState: String, Sendable {
        case online
        case offline
        /// macOS Low Data Mode: the teacher has asked apps not to download
        /// what they were not asked for, and ~340 MB is exactly that.
        case lowDataMode
    }

    /// Everything the decision depends on, as plain values.
    struct Facts: Equatable, Sendable {

        // MARK: - Stored properties

        /// False in the unit suite, a UI test, or a headless run (the
        /// assistant's server, a scheduled publish, the contract writer).
        let isAnAppLaunch: Bool

        /// Whether this app carries the recipe (a test bundle does not).
        let carriesTheRecipe: Bool

        /// Whether a warm-up has already finished for this version.
        let readyForThisVersion: Bool

        let network: NetworkState
    }

    /// What to do, and whether the trail hears about a skip.
    enum Decision: Equatable, Sendable {
        case start
        case skip(reason: String, noteOnTheTrail: Bool)
    }

    // MARK: - Stored properties

    /// The one warm-up for the app.
    static let shared: BuilderWarmUp = BuilderWarmUp()

    /// The line the sidebar shows while this runs, and nothing else is ever
    /// said about it (`builderWarmUp.wording.statusLine`). Plain words only:
    /// no "image", no "container" (rule 1).
    nonisolated static let statusLine: String = "Getting this Mac ready to build your websites…"

    /// The last line `setup.sh --prepare-builder` prints when the builder is
    /// ready (`builderWarmUp.readyLine`).
    nonisolated static let readyLinePrefix: String = "BUILDER_READY="

    /// The launcher's flag for this mode.
    nonisolated static let launcherFlag: String = "--prepare-builder"

    /// True while the background run is under way; the sidebar's status line
    /// follows it.
    private(set) var isGettingReady: Bool = false

    // MARK: - Functions

    /// The whole rule, pure over its facts (`builderWarmUp.startsWhen`).
    nonisolated static func decide(_ facts: Facts) -> Decision {
        if !facts.isAnAppLaunch {
            return .skip(reason: "not an app launch", noteOnTheTrail: false)
        }
        if !facts.carriesTheRecipe {
            return .skip(reason: "no recipe", noteOnTheTrail: false)
        }
        if facts.readyForThisVersion {
            return .skip(reason: "already ready", noteOnTheTrail: false)
        }
        if facts.network == .offline {
            return .skip(reason: "no internet connection", noteOnTheTrail: true)
        }
        if facts.network == .lowDataMode {
            return .skip(reason: "Low Data Mode is on", noteOnTheTrail: true)
        }
        return .start
    }

    /// Plantoir's own folder for this, beside the helper programs.
    nonisolated static func folder(inHomeFolder homeFolder: URL = RealHome.forFiles) -> URL {
        return homeFolder
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("getting-ready", isDirectory: true)
    }

    /// Where a finished warm-up writes down the version it was for.
    nonisolated static func recordURL(inHomeFolder homeFolder: URL = RealHome.forFiles) -> URL {
        return folder(inHomeFolder: homeFolder).appendingPathComponent("ready-for.txt")
    }

    /// "1.4.0 (212)": the recipe changes only with the app, so the version
    /// and build name the recipe well enough to know it is new.
    nonisolated static func versionIdentity(infoDictionary: [String: Any]) -> String {
        let version: String = infoDictionary["CFBundleShortVersionString"] as? String ?? "?"
        let build: String = infoDictionary["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Whether a warm-up has already finished for this version.
    nonisolated static func isReady(forVersion identity: String, recordURL: URL) -> Bool {
        guard let recorded = try? String(contentsOf: recordURL, encoding: .utf8) else {
            return false
        }
        return recorded.trimmingCharacters(in: .whitespacesAndNewlines) == identity
    }

    /// Whether a run's output says the builder is ready.
    nonisolated static func sawTheReadyLine(in output: String) -> Bool {
        for line in output.split(separator: "\n") {
            if line.hasPrefix(readyLinePrefix) {
                return true
            }
        }
        return false
    }

    /// The flags that make this binary something other than an app.
    static func isAnAppLaunch(arguments: [String]) -> Bool {
        if WorkspaceModel.isRunningTests {
            return false
        }
        if ProcessInfo.processInfo.environment["UITEST_WORKSPACE"] != nil {
            return false
        }
        for flag in AppUpdates.headlessFlags {
            if arguments.contains(flag) {
                return false
            }
        }
        return true
    }

    /// Called once, from `applicationDidFinishLaunching`. Never blocks the
    /// window: the network question and the run are both awaited off it.
    func startIfItShould(arguments: [String] = CommandLine.arguments) {
        if isGettingReady {
            return
        }
        let identity: String = BuilderWarmUp.versionIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let isAnApp: Bool = BuilderWarmUp.isAnAppLaunch(arguments: arguments)
        let carries: Bool = Bundle.main.url(forResource: "Dockerfile", withExtension: nil) != nil
            && Bundle.main.url(forResource: "setup.sh", withExtension: nil) != nil
        let ready: Bool = BuilderWarmUp.isReady(forVersion: identity, recordURL: BuilderWarmUp.recordURL())
        // Decided once WITHOUT the network first, so a launch that will never
        // warm up does not even ask the network.
        let before: Decision = BuilderWarmUp.decide(Facts(
            isAnAppLaunch: isAnApp, carriesTheRecipe: carries, readyForThisVersion: ready, network: .online
        ))
        if before != .start {
            return
        }
        isGettingReady = true
        Task { @MainActor in
            let network: NetworkState = await BuilderWarmUp.currentNetwork()
            let decision: Decision = BuilderWarmUp.decide(Facts(
                isAnAppLaunch: isAnApp, carriesTheRecipe: carries, readyForThisVersion: ready, network: network
            ))
            if case .skip(let reason, let noteOnTheTrail) = decision {
                if noteOnTheTrail {
                    ActivityTrail.note(
                        .builderWarmUpSkipped,
                        "did not get this Mac ready to build websites in the background: \(reason) — it will be done at the first preview"
                    )
                }
                isGettingReady = false
                return
            }
            ActivityTrail.note(
                .builderWarmUpStarted,
                "started getting this Mac ready to build websites, in the background, for version \(identity)"
            )
            let started: Date = Date()
            let outcome: LauncherOutcome = await BuilderWarmUp.runTheLauncher()
            let seconds: Int = Int(Date().timeIntervalSince(started).rounded())
            if outcome.status == 0 && BuilderWarmUp.sawTheReadyLine(in: outcome.output) {
                BuilderWarmUp.record(identity)
                ActivityTrail.note(
                    .builderWarmUpFinished,
                    "this Mac is ready to build websites (got ready in the background in \(seconds)s)"
                )
            } else {
                ActivityTrail.note(
                    .builderWarmUpDidNotFinish,
                    "did not finish getting this Mac ready in the background (\(outcome.why), after \(seconds)s) — it will be done at the first preview"
                )
            }
            isGettingReady = false
        }
    }

    // MARK: - Private helpers

    /// How a run ended, in words for the trail.
    struct LauncherOutcome: Sendable {

        // MARK: - Stored properties

        let status: Int32
        let output: String
        let why: String
    }

    nonisolated private static func record(_ identity: String) {
        let url: URL = recordURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? (identity + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Asks the system once whether there is a network, and whether Low Data
    /// Mode is on. Three seconds without an answer counts as offline, which
    /// only ever means "do it at the first preview instead".
    nonisolated static func currentNetwork() async -> NetworkState {
        return await withTaskGroup(of: NetworkState?.self) { group in
            group.addTask {
                let monitor: NWPathMonitor = NWPathMonitor()
                for await path in monitor {
                    monitor.cancel()
                    if path.status != .satisfied {
                        return NetworkState.offline
                    }
                    if path.isConstrained {
                        return NetworkState.lowDataMode
                    }
                    return NetworkState.online
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            var answer: NetworkState = .offline
            if let first = await group.next(), let state = first {
                answer = state
            }
            group.cancelAll()
            return answer
        }
    }

    /// Lays out the folder (the launcher and a mirror of the recipe) and runs
    /// `setup.sh --prepare-builder` there, its output kept in `last-run.log`
    /// beside it for anyone looking into a slow first preview.
    @concurrent
    nonisolated private static func runTheLauncher() async -> LauncherOutcome {
        let place: URL = folder()
        do {
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        } catch {
            return LauncherOutcome(status: -1, output: "", why: "could not make its folder")
        }
        guard let launcher = Bundle.main.url(forResource: "setup.sh", withExtension: nil) else {
            return LauncherOutcome(status: -1, output: "", why: "no launcher in the app")
        }
        _ = WorkspaceModel.syncFile(from: launcher, to: place.appendingPathComponent("setup.sh"))
        _ = WorkspaceModel.copyToolchainFiles(into: place)

        let logURL: URL = place.appendingPathComponent("last-run.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let log = FileHandle(forWritingAtPath: logURL.path) else {
            return LauncherOutcome(status: -1, output: "", why: "could not keep its notes")
        }
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [place.appendingPathComponent("setup.sh").path, launcherFlag]
        process.currentDirectoryURL = place
        process.environment = HelperPrograms.environment()
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice

        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
        try? log.close()
        let output: String = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let why: String = status == -1 ? "could not start" : "stopped with \(status)"
        return LauncherOutcome(status: status, output: output, why: why)
    }
}
