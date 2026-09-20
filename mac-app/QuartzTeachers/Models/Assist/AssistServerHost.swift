import Foundation
import Observation

/// Runs `llama-server` beside the app and keeps it healthy.
///
/// **Why not in Colima.** The Windows build runs its model in a container
/// because that is what it has. Doing the same on a Mac would be the single
/// worst decision available: Colima is a Linux VM with no access to Metal, so
/// the model would run on two virtual CPU cores while an idle GPU sat beside
/// it. Measured on an M4 Pro, the same 1.5B model and the same 3,411-token
/// prompt: **175 seconds in a container, 2.1 seconds natively.** Everything
/// good about this feature comes from that one decision.
@Observable
final class AssistServerHost {

    // MARK: - Types

    enum State: Equatable {
        case stopped
        case starting
        case ready
        case failed(reason: String)
    }

    // MARK: - Stored properties

    /// Where the server is up to.
    private(set) var state: State = .stopped

    /// The port it answers on, chosen when it starts.
    private(set) var port: Int = 0

    /// What the machine is allowed to give it.
    let budget: AssistHardwareBudget

    /// Which assistant is being started.
    ///
    /// Passed in rather than read off `budget.tier`, because since the
    /// settings panel exists those two can differ: a teacher on a 48 GB Mac
    /// may have asked for the smaller one. The tier decides the CONTEXT SIZE,
    /// so taking it from the hardware would hand the small model the large
    /// model's 16k window — twice the memory it was chosen to save, and the
    /// saving was the whole reason for the choice.
    let tier: AssistModelTier

    /// The weights.
    private let modelURL: URL

    /// The running process, if any.
    private var process: Process?

    /// Where this launch's engine output is being kept, once it has one.
    ///
    /// **A FILE, and never a `Pipe`.** The engine is chatty, and the obvious
    /// way to read it — redirect both streams into a `Pipe` — is the exact
    /// arrangement that wedged the Windows server mid-request: a redirected
    /// pipe nobody drains fills up, and the next log write blocks inside the
    /// engine, looking precisely like a hung model. Windows had to add a
    /// reader to fix it. The mac never had the bug because it discarded the
    /// output into `nullDevice`, and that safety is what this keeps: a write
    /// to a file has no reader to wait for, so the engine can never block on
    /// anybody's attention. Nothing here reads on the engine's timetable —
    /// the tail is read when somebody asks, and never at all if nobody does.
    private(set) var engineLogURL: URL?

    /// The end of the file as of the last look, so a caller is shown what the
    /// engine has said SINCE, rather than the same lines over and over.
    private var engineLogOffset: UInt64 = 0

    /// Held open for the engine's lifetime — the process writes through it.
    private var engineLogHandle: FileHandle?

    // MARK: - Computed properties

    /// The bundled binary. It ships inside the app so a teacher installs
    /// nothing: 25 MB of llama.cpp, MIT licensed, signed with the app.
    ///
    /// It lives in `Resources/llama/` as a folder reference, with its dylibs
    /// beside it — the binary carries an `@loader_path` rpath, so it finds
    /// them itself and needs no `DYLD_LIBRARY_PATH`. That matters beyond
    /// tidiness: the hardened runtime strips `DYLD_*` from the environment,
    /// so an env-var arrangement would work here and fail the moment the app
    /// is notarised.
    static var executableURL: URL? {
        if let inFolder = Bundle.main.url(forResource: "llama-server", withExtension: nil, subdirectory: "llama") {
            return inFolder
        }
        return Bundle.main.url(forAuxiliaryExecutable: "llama-server")
            ?? Bundle.main.url(forResource: "llama-server", withExtension: nil)
    }

    /// Where the assistant sends requests.
    var baseURL: URL? {
        guard port > 0 else {
            return nil
        }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    // MARK: - Initializer

    init(modelURL: URL, budget: AssistHardwareBudget, tier: AssistModelTier) {
        self.modelURL = modelURL
        self.budget = budget
        self.tier = tier
    }

    // MARK: - Functions

    /// Start the server and wait until it answers.
    func start() async {
        if case .ready = state {
            return
        }
        guard let executable = AssistServerHost.executableURL else {
            state = .failed(reason: "The assistant's engine is missing from the app. Reinstall Plantoir.")
            return
        }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            state = .failed(reason: "The model has not been downloaded yet.")
            return
        }

        state = .starting
        let chosenPort: Int = AssistServerHost.freePort()
        port = chosenPort

        let process: Process = Process()
        process.executableURL = executable
        process.arguments = AssistServerHost.serverArguments(
            modelPath: modelURL.path,
            port: chosenPort,
            tier: tier,
            threadCount: budget.threadCount
        )

        // The server is chatty and none of it is for the teacher — but a
        // problem report from a teacher whose assistant is misbehaving is the
        // one place it matters, and until this existed a mac report could
        // carry nothing the engine had said. Both streams go to one file so
        // they interleave in the order they were written; see `engineLogURL`
        // for why a file rather than a pipe.
        let logHandle: FileHandle? = openEngineLog()
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            state = .failed(reason: "The assistant's engine would not start: \(error.localizedDescription)")
            return
        }
        self.process = process

        let healthy: Bool = await waitUntilHealthy()
        if healthy {
            state = .ready
        } else {
            stop()
            state = .failed(reason: "The assistant's engine did not become ready.")
        }
    }

    /// Everything `llama-server` is asked to do, in one testable place.
    ///
    /// Separated from `start()` on purpose: one of these flags is the
    /// difference between a 97% router and a 39% one, and a flag that only
    /// exists inside a function that spawns a process cannot be checked
    /// without spawning one.
    nonisolated static func serverArguments(
        modelPath: String,
        port: Int,
        tier: AssistModelTier,
        threadCount: Int
    ) -> [String] {
        return [
            "--model", modelPath,
            "--port", String(port),
            "--host", "127.0.0.1",
            // Sized by tier: the context is most of what the model holds in
            // memory, so an 8 GB Mac and a 32 GB one should not be given the
            // same figure.
            "--ctx-size", String(tier.contextTokens),
            // THINKING OFF, and this is worth more than any other flag on the
            // line. Qwen3 with thinking enabled spends its token budget inside
            // <think> and never reaches the tool call: the SAME weights scored
            // 39% with it on and 97% with it off. Dropping it does not break
            // loudly — it quietly makes the assistant a worse router, which is
            // why a test asserts both flags are here.
            //
            // TWO flags, because they do different jobs and only the second
            // one actually stops the thinking. `--reasoning-budget 0` caps the
            // thinking; it does not prevent it, so the model still opens a
            // <think> block and fills it until the cap. Measured on the same
            // prompt and the same 20-tool surface: budget-alone reached the
            // right tool call in 512 completion tokens and 16.1 s, while
            // `--reasoning off` — which tells the chat template not to think
            // at all — reached the SAME call in 44 tokens and 8.4 s. Half the
            // wait, for a flag. The budget stays as a second line of defence
            // for any future model whose template ignores `--reasoning`.
            "--reasoning", "off",
            "--reasoning-budget", "0",
            "--threads", String(threadCount),
            // Every layer on the GPU. This is the whole point of running
            // natively; a partial offload would leave the slow path in play.
            "--n-gpu-layers", "999",
            // Chat templates and tool calls come from the model's own Jinja
            // template rather than a guess at its format.
            "--jinja",
            // One conversation per window, and each window has its own server.
            "--parallel", "1",
        ]
    }

    /// Stop the server. Called when the window closes — a model holding
    /// gigabytes of a teacher's RAM after they have finished with it is the
    /// kind of thing that gets an app a reputation.
    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        port = 0
        // The file itself is deliberately LEFT: `start()` calls this on the
        // path where the engine never became ready, and the reason it never
        // became ready is the last thing written to it. `discardEngineLog()`
        // is the separate step that throws it away.
        try? engineLogHandle?.close()
        engineLogHandle = nil
        if case .failed = state {
            return
        }
        state = .stopped
    }

    /// Poll `/health` until the server answers or we give up.
    ///
    /// Loading a 7B from a cold page cache is a few seconds of disk; from a
    /// warm one it is well under a second. Sixty seconds is generous enough
    /// that a slow disk never looks like a failure.
    private func waitUntilHealthy() async -> Bool {
        guard let baseURL else {
            return false
        }
        let health: URL = baseURL.appendingPathComponent("health")
        let deadline: Date = Date().addingTimeInterval(60)

        while Date() < deadline {
            if let process, !process.isRunning {
                return false
            }
            do {
                let (_, response) = try await URLSession.shared.data(from: health)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    return true
                }
            } catch {
                // Not up yet; that is the normal case for the first second.
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    /// What the engine has written since the last time anybody looked.
    ///
    /// Advancing the mark is the point: a caller that samples every so often
    /// wants the new lines, not the whole file again. When the engine has
    /// been running long enough to outrun the window below, the oldest part
    /// is skipped rather than read — the recent end is the diagnostic one.
    func engineLinesSinceLastLook(atMost limit: Int = 200) -> [String] {
        guard let engineLogURL else {
            return []
        }
        var mark: UInt64 = engineLogOffset
        let lines: [String] = AssistServerHost.lines(
            in: engineLogURL, since: &mark, atMost: limit
        )
        engineLogOffset = mark
        return lines
    }

    /// Throw the engine's log away. Called once nobody will want it again.
    func discardEngineLog() {
        try? engineLogHandle?.close()
        engineLogHandle = nil
        if let engineLogURL {
            try? FileManager.default.removeItem(at: engineLogURL)
        }
        engineLogURL = nil
        engineLogOffset = 0
    }

    /// The reading half, as a free function so a test can drive it against a
    /// file of its own rather than against a running engine.
    ///
    /// `mark` comes in as where the last look ended and goes out as where
    /// this one did. A file that has SHRUNK — which should not happen, but
    /// would leave every later read off the end — resets the mark instead of
    /// returning nothing forever.
    nonisolated static func lines(
        in fileURL: URL,
        since mark: inout UInt64,
        atMost limit: Int
    ) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer { try? handle.close() }

        let end: UInt64 = (try? handle.seekToEnd()) ?? 0
        if end <= mark {
            mark = end
            return []
        }

        // Never read more than the recent end, however long the engine has
        // been running: this is a sample for a report, not a log viewer.
        var start: UInt64 = mark
        let mostToRead: UInt64 = 64 * 1024
        var skippedAhead: Bool = false
        if end - start > mostToRead {
            start = end - mostToRead
            skippedAhead = true
        }
        try? handle.seek(toOffset: start)
        let data: Data = (try? handle.readToEnd()) ?? Data()
        mark = end

        var found: [String] = []
        for piece in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
            let line: String = piece.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                found.append(line)
            }
        }
        // Skipping ahead lands mid-line, so the first one is a fragment.
        if skippedAhead && !found.isEmpty {
            found.removeFirst()
        }
        if found.count <= limit {
            return found
        }
        var recent: [String] = []
        var index: Int = found.count - limit
        while index < found.count {
            recent.append(found[index])
            index += 1
        }
        return recent
    }

    /// Make this launch's log file and open it for the engine to write to.
    ///
    /// Lives in the temporary directory rather than beside the trail: what
    /// lands here is raw and unredacted, and the log folder is the one a
    /// problem report gathers. Only the sampled, redacted lines reach that.
    private func openEngineLog() -> FileHandle? {
        let folderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Plantoir-engine", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        AssistServerHost.sweepOldEngineLogs(in: folderURL)

        let fileURL: URL = folderURL.appendingPathComponent("engine-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            return nil
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return nil
        }
        engineLogURL = fileURL
        engineLogOffset = 0
        engineLogHandle = handle
        return handle
    }

    /// Clear out anything a crash left behind.
    ///
    /// A clean quit removes its own log; a force-kill cannot. Without this
    /// the folder would only ever grow, which is the sort of thing found
    /// years later as several gigabytes nobody can account for.
    private static func sweepOldEngineLogs(in folderURL: URL) {
        let aDayAgo: Date = Date().addingTimeInterval(-24 * 60 * 60)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            guard let changedAt = values?.contentModificationDate else {
                continue
            }
            if changedAt < aDayAgo {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    /// A free TCP port, by asking the kernel for one and letting it go.
    ///
    /// There is a race here in principle — something else could take the port
    /// between the close and the server's bind — and it is accepted rather
    /// than papered over: the alternative is a fixed port, which collides
    /// properly the moment a teacher opens a second section.
    private static func freePort() -> Int {
        let handle: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        if handle < 0 {
            return 8080
        }
        defer { close(handle) }

        var address: sockaddr_in = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound: Int32 = withUnsafePointer(to: &address) { pointer in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                return bind(handle, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 {
            return 8080
        }

        var assigned: sockaddr_in = sockaddr_in()
        var length: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named: Int32 = withUnsafeMutablePointer(to: &assigned) { pointer in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                return getsockname(handle, rebound, &length)
            }
        }
        if named != 0 {
            return 8080
        }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }
}
