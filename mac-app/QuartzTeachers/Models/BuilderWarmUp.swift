import Foundation
import Network
import Observation

/// Getting the website builder ready in the BACKGROUND, at first launch and
/// whenever the app's recipe is new, so that a teacher's first preview is fast
/// (bundle B, Russell's change of 2026-09-26).
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
/// **Keyed on the recipe, not the version** (implementation review N2). The
/// launcher's own `--builder-tag` names the image for the recipe as it
/// stands — the same hash every launcher uses — and a finished run writes
/// that name down. So a development build whose version never changes still
/// gets a new recipe ready, and a release that changed no recipe does not
/// start the builder for nothing.
///
/// **Two launchers never get the builder ready at once**, and that rule lives
/// in the launchers, not here: a Create or a Preview that arrives mid-build
/// waits for this one's turn and then finds the builder ready
/// (`GETTING-READY TURN BLOCK`, `builderWarmUp.turn`). So nothing in the app
/// has to remember to wait, and a teacher at the command line gets the same
/// rule.
///
/// **When it does not run** — every case is `contracts/app-rules.json` →
/// `builderWarmUp.startsWhen`: not in the unit suite or a UI test, not when
/// this binary is the assistant's server, a scheduled publish or the contract
/// writer, not when the app carries no recipe, not when this recipe's builder
/// is already ready, and not offline or in Low Data Mode — then it says
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

    /// The line `setup.sh --builder-tag` prints (`builderWarmUp.tagLine`).
    nonisolated static let tagLinePrefix: String = "BUILDER_TAG="

    /// The launcher's flag for this mode.
    nonisolated static let launcherFlag: String = "--prepare-builder"

    /// The launcher's flag that names the builder for the recipe.
    nonisolated static let tagFlag: String = "--builder-tag"

    /// True while the background run is under way; the sidebar's status line
    /// follows it. Set only once the run is certain to start, so an offline
    /// launch never flashes it.
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
        if facts.readyForThisRecipe {
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

    /// Where a finished warm-up writes down the builder it got ready.
    nonisolated static func recordURL(inHomeFolder homeFolder: URL = RealHome.forFiles) -> URL {
        return folder(inHomeFolder: homeFolder).appendingPathComponent("ready-for.txt")
    }

    /// Whether the builder named `tag` has already been got ready.
    nonisolated static func isReady(forRecipe tag: String, recordURL: URL) -> Bool {
        if tag.isEmpty {
            return false
        }
        guard let recorded = try? String(contentsOf: recordURL, encoding: .utf8) else {
            return false
        }
        return recorded.trimmingCharacters(in: .whitespacesAndNewlines) == tag
    }

    /// The value after `prefix` on the last line that starts with it, or nil.
    nonisolated static func value(after prefix: String, in output: String) -> String? {
        var found: String?
        for line in output.split(separator: "\n") {
            if line.hasPrefix(prefix) {
                let value: String = String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    found = value
                }
            }
        }
        return found
    }

    /// Whether a run's output says the builder is ready.
    nonisolated static func sawTheReadyLine(in output: String) -> Bool {
        return value(after: readyLinePrefix, in: output) != nil
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
    /// window: the recipe's name, the network question and the run are all
    /// awaited off it.
    func startIfItShould(arguments: [String] = CommandLine.arguments) {
        if isGettingReady {
            return
        }
        let isAnApp: Bool = BuilderWarmUp.isAnAppLaunch(arguments: arguments)
        let carries: Bool = Bundle.main.url(forResource: "Dockerfile", withExtension: nil) != nil
            && Bundle.main.url(forResource: "setup.sh", withExtension: nil) != nil
        // Decided once with what costs nothing, so a launch that will never
        // warm up does not lay out its folder or ask the network.
        let before: Decision = BuilderWarmUp.decide(Facts(
            isAnAppLaunch: isAnApp, carriesTheRecipe: carries, readyForThisRecipe: false, network: .online
        ))
        if before != .start {
            return
        }
        Task { @MainActor in
            let tag: String = await BuilderWarmUp.recipeTag()
            let ready: Bool = BuilderWarmUp.isReady(forRecipe: tag, recordURL: BuilderWarmUp.recordURL())
            let network: NetworkState = ready ? .online : await BuilderWarmUp.currentNetwork()
            let decision: Decision = BuilderWarmUp.decide(Facts(
                isAnAppLaunch: isAnApp, carriesTheRecipe: carries, readyForThisRecipe: ready, network: network
            ))
            if case .skip(let reason, let noteOnTheTrail) = decision {
                if noteOnTheTrail {
                    ActivityTrail.note(
                        .builderWarmUpSkipped,
                        "did not get this Mac ready to build websites in the background: \(reason) — it will be done at the first preview"
                    )
                }
                return
            }
            isGettingReady = true
            ActivityTrail.note(
                .builderWarmUpStarted,
                "started getting this Mac ready to build websites, in the background, for \(tag.isEmpty ? "this recipe" : tag)"
            )
            let started: Date = Date()
            let outcome: LauncherOutcome = await BuilderWarmUp.runTheLauncher(flag: BuilderWarmUp.launcherFlag)
            let seconds: Int = Int(Date().timeIntervalSince(started).rounded())
            if outcome.status == 0, let built = BuilderWarmUp.value(after: BuilderWarmUp.readyLinePrefix, in: outcome.output) {
                BuilderWarmUp.record(built)
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

    nonisolated private static func record(_ tag: String) {
        let url: URL = recordURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? (tag + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// The name of the builder for the recipe this app carries, asked of the
    /// launcher itself (`setup.sh --builder-tag`, which starts nothing), after
    /// laying out the folder. Empty when it cannot be asked, which counts as
    /// "not ready".
    @concurrent
    nonisolated private static func recipeTag() async -> String {
        let outcome: LauncherOutcome = await runTheLauncher(flag: tagFlag)
        if outcome.status != 0 {
            return ""
        }
        return value(after: tagLinePrefix, in: outcome.output) ?? ""
    }

    /// Lays out the folder (the launcher and a mirror of the recipe) and runs
    /// `setup.sh <flag>` there, its output kept beside it (`last-run.log` for
    /// the warm-up) for anyone looking into a slow first preview.
    @concurrent
    nonisolated private static func runTheLauncher(flag: String) async -> LauncherOutcome {
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

        let logName: String = flag == launcherFlag ? "last-run.log" : "recipe-tag.log"
        let logURL: URL = place.appendingPathComponent(logName)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let log = FileHandle(forWritingAtPath: logURL.path) else {
            return LauncherOutcome(status: -1, output: "", why: "could not keep its notes")
        }
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [place.appendingPathComponent("setup.sh").path, flag]
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

/// The plain values `BuilderWarmUp` decides over and reports with, kept out
/// of the class so its sections are the four the house style names.
extension BuilderWarmUp {

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

        /// Whether the builder for this recipe has already been got ready.
        let readyForThisRecipe: Bool

        let network: NetworkState
    }

    /// What to do, and whether the trail hears about a skip.
    enum Decision: Equatable, Sendable {
        case start
        case skip(reason: String, noteOnTheTrail: Bool)
    }

    /// How a run ended, in words for the trail.
    struct LauncherOutcome: Sendable {

        // MARK: - Stored properties

        let status: Int32
        let output: String
        let why: String
    }
}
