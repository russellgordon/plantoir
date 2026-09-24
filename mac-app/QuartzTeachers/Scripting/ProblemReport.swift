import Foundation

/// What one task did, kept so it can still be read after the window that
/// showed it has gone.
///
/// This is the whole reason the feature exists. A teacher reports a problem
/// AFTER it has happened — the sheet is closed, the app may have been
/// restarted — so anything that asks them to turn something on and do it
/// again is a feature that will not be used. Records are written as tasks
/// finish, whether they succeeded or not, and the oldest are thrown away.
nonisolated struct RunRecord {

    // MARK: - Stored properties

    let startedAt: Date
    let finishedAt: Date

    /// The launcher that ran, and what it was asked to do.
    let scriptName: String
    let arguments: [String]

    /// The folder it ran in — redacted like everything else, so what
    /// survives is the shape of the path rather than who owns it.
    let workingFolderPath: String

    /// The outcome in the words the app itself used.
    let outcome: String

    /// Whether this counts as a failure at all.
    ///
    /// Kept as its own fact rather than read back out of `outcome`, because
    /// a task stopped on purpose also exits non-zero and reading the word
    /// "Failed" out of a sentence is the kind of test that passes until
    /// somebody rewords the sentence.
    let wasFailure: Bool

    /// What `FailureExplainer` made of it, when it recognised anything.
    /// Recorded because its SILENCE is the interesting case: a failure it
    /// could not explain is the one worth a person's attention.
    let explanation: String?

    /// Everything the task printed, already tidied by `TranscriptBuilder`.
    let transcript: String

    /// Which copy of the app wrote this, which machine it ran on, and which
    /// helper tools are in place. Filled from `ProblemReportEnvironment` in
    /// the app and passed as plain text so a test can render a record
    /// without a bundle.
    let appDescription: String
    let systemDescription: String
    let helperDescription: String

    // MARK: - Initializer

    init(
        startedAt: Date,
        finishedAt: Date,
        scriptName: String,
        arguments: [String],
        workingFolderPath: String,
        outcome: String,
        wasFailure: Bool,
        explanation: String?,
        transcript: String,
        appDescription: String,
        systemDescription: String,
        helperDescription: String = ProblemReportEnvironment.helperDescription
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.scriptName = scriptName
        self.arguments = arguments
        self.workingFolderPath = workingFolderPath
        self.outcome = outcome
        self.wasFailure = wasFailure
        self.explanation = explanation
        self.transcript = transcript
        self.appDescription = appDescription
        self.systemDescription = systemDescription
        self.helperDescription = helperDescription
    }

    /// The longest transcript kept in one record. A record is read from the
    /// END — that is where a failure is — so trimming takes from the front.
    static let mostTranscriptCharacters: Int = 250_000

    /// What stands in for the part that was not kept.
    static let trimmedMarker: String = "[earlier output not kept]"

    // MARK: - Computed properties

    /// How long the task took.
    var duration: TimeInterval {
        return finishedAt.timeIntervalSince(startedAt)
    }

    /// The launcher and its arguments as one line.
    var taskDescription: String {
        var parts: [String] = [scriptName]
        for argument in arguments {
            parts.append(argument)
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Functions

    /// The file this record is written to. Named so that sorting the folder
    /// by name is sorting it by time, which is what makes keeping "the
    /// newest twenty" a matter of dropping from one end of a sorted list.
    func fileName(timeZone: TimeZone = TimeZone.current) -> String {
        let stamp: String = RunRecord.stampFormatter(timeZone: timeZone).string(from: startedAt)
        var task: String = scriptName
        if let dot = task.firstIndex(of: ".") {
            task = String(task[task.startIndex..<dot])
        }
        return stamp + "-" + task + ".txt"
    }

    /// The record as it is written — redacted, in full, once.
    ///
    /// Redaction is applied HERE, to the finished text, rather than to each
    /// field on the way in: one call over one string is one place to be
    /// wrong, and a field added later is covered by it without anyone
    /// having to remember.
    func text(timeZone: TimeZone = TimeZone.current) -> String {
        var lines: [String] = []
        lines.append("Plantoir problem report")
        lines.append("=======================")
        lines.append(labelled("When", RunRecord.readableFormatter(timeZone: timeZone).string(from: startedAt)))
        lines.append(labelled("App", appDescription))
        lines.append(labelled("System", systemDescription))
        lines.append(labelled("Helpers", helperDescription))
        lines.append(labelled("Task", taskDescription))
        lines.append(labelled("Folder", workingFolderPath))
        lines.append(labelled("Outcome", outcome + " after " + String(format: "%.1f", duration) + "s"))
        // Only a failure gets this line. A task that was stopped on purpose
        // has nothing to explain, and telling somebody that nothing was
        // recognised about it reads as a fault where there was none.
        if wasFailure {
            lines.append(labelled("Explained", explanation ?? "nothing recognised — worth a look"))
        }
        lines.append("")
        lines.append("----- what the task printed -----")
        lines.append(trimmedTranscript)
        return LogRedactor.redacting(lines.joined(separator: "\n"))
    }

    /// The transcript, shortened from the front if it is very long.
    var trimmedTranscript: String {
        if transcript.count <= RunRecord.mostTranscriptCharacters {
            return transcript
        }
        let keptFrom: String.Index = transcript.index(
            transcript.endIndex, offsetBy: -RunRecord.mostTranscriptCharacters
        )
        return RunRecord.trimmedMarker + "\n" + String(transcript[keptFrom..<transcript.endIndex])
    }

    /// One header line, with the labels lined up.
    func labelled(_ label: String, _ value: String) -> String {
        var padded: String = label
        while padded.count < 10 {
            padded += " "
        }
        return padded + value
    }

    /// Sortable and filename-safe: 2026-08-16-143022.
    static func stampFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }

    /// Readable, and carrying the offset — a report sent across a time zone
    /// is otherwise an hour's confusion.
    static func readableFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter
    }
}

/// Which copy of the app is running, and on what.
///
/// The bundle path and the process id are here for a reason that is not
/// obvious: two copies of Plantoir can be running at once (Xcode's Run does
/// not stop a copy it did not start), and when they are, they take turns
/// rewriting the same working folder. Two process ids in one folder of
/// records is the fastest way that has ever been available to see it.
nonisolated enum ProblemReportEnvironment {

    // MARK: - Stored properties

    /// The assistant's engine is bundled inside the app, so its build IS
    /// known without asking anything.
    static let bundledEngineDescription: String = "llama.cpp b10435 (Metal)"

    /// The versions the launchers download when a program is missing
    /// (`setup.sh`, `COLIMA_VERSION` and its three neighbours — a test holds
    /// the two lists together). Shown only as what WOULD be installed, never
    /// as what is.
    static let pinnedHelpers: [PinnedHelper] = [
        PinnedHelper(displayName: "Colima", probeName: "colima", pinnedVersion: "v0.10.3", setupVariable: "COLIMA_VERSION"),
        PinnedHelper(displayName: "Lima", probeName: "limactl", pinnedVersion: "2.2.0", setupVariable: "LIMA_VERSION"),
        PinnedHelper(displayName: "Docker CLI", probeName: "docker", pinnedVersion: "29.7.2", setupVariable: "DOCKER_CLI_VERSION"),
        PinnedHelper(displayName: "Buildx", probeName: "buildx", pinnedVersion: "v0.36.1", setupVariable: "BUILDX_VERSION")
    ]

    /// One `sh` run asks all four, printing one tab-separated row each:
    /// the program, the first line of its version, and where it was found.
    /// Buildx has no path of its own to report (see `helperDescription`).
    static let helperProbeScript: String = """
    for tool in colima limactl docker; do
      where=$(command -v "$tool" 2>/dev/null)
      line=""
      if [ -n "$where" ]; then
        line=$("$tool" --version 2>/dev/null </dev/null | head -n 1 | tr -d '\t\r')
      fi
      printf '%s\t%s\t%s\n' "$tool" "$line" "$where"
    done
    line=""
    if command -v docker >/dev/null 2>&1; then
      line=$(docker buildx version 2>/dev/null </dev/null | head -n 1 | tr -d '\t\r')
    fi
    printf 'buildx\t%s\t\n' "$line"
    """

    /// Guards `storedHelperDescription`, which the background check writes
    /// and every record reads, from any thread.
    private static let measuredHelperLock: NSLock = NSLock()
    nonisolated(unsafe) private static var storedHelperDescription: String?

    // MARK: - Computed properties

    /// "Plantoir 1.0 (12) · pid 4711 · /Applications/Plantoir.app"
    static var appDescription: String {
        let shortVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
        return "Plantoir \(shortVersion) (\(buildNumber)) · pid \(processIdentifier) · \(Bundle.main.bundlePath)"
    }

    /// "macOS 15.6.0 (24G84) · Darwin 24.6.0 · arm64 · 8 cores · 36 GB"
    static var systemDescription: String {
        let information: ProcessInfo = ProcessInfo.processInfo
        let version: OperatingSystemVersion = information.operatingSystemVersion
        let memoryInGigabytes: Int = Int(information.physicalMemory / 1_073_741_824)
        var text: String = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        if let build = osBuildNumber {
            text += " (\(build))"
        }
        if let darwin = darwinRelease {
            text += " · Darwin \(darwin)"
        }
        text += " · \(machineArchitecture)"
            + " · \(information.processorCount) cores"
            + " · \(memoryInGigabytes) GB"
        return text
    }

    /// "llama.cpp b10435 (Metal) · Colima 0.10.3 (Homebrew) · Lima 2.2.0 (Homebrew) · …"
    ///
    /// What was MEASURED the last time this app asked the programs
    /// themselves, or — before it has asked — every helper marked "not
    /// checked yet" beside the version the launchers would download. Never a
    /// bare version it did not check: this line used to print the pinned
    /// versions as though they were installed, and on a Mac with Homebrew's
    /// Docker CLI 29.7.1 it said 29.7.2, which is how a report nearly sent a
    /// diagnosis the wrong way (issue #222).
    static var helperDescription: String {
        if let measured = measuredHelperDescription {
            return measured
        }
        var parts: [String] = [bundledEngineDescription]
        for helper in pinnedHelpers {
            parts.append(helper.displayName + " not checked yet (pinned " + helper.pinnedVersion + ")")
        }
        return parts.joined(separator: " · ")
    }

    /// The last measured description, shared by every record and trail line
    /// this process writes. Only `refreshHelpers` stores into it; a test that
    /// measures stub programs through `measureHelpers` leaves it alone, so a
    /// stub's made-up version cannot leak into a later test's record.
    static var measuredHelperDescription: String? {
        get {
            return measuredHelperLock.withLock {
                return storedHelperDescription
            }
        }
        set {
            measuredHelperLock.withLock {
                storedHelperDescription = newValue
            }
        }
    }

    // MARK: - Helper versions, measured

    /// Asks the helper programs which versions they are, and says where each
    /// was found.
    ///
    /// Synchronous and slow (about 0.3 s measured on a Mac with all four from
    /// Homebrew, 0.08 s with none), so it is only ever called off the main
    /// thread — see `refreshHelpers`. PURE apart from running the programs:
    /// it stores nothing, which is what lets a test point it at stub
    /// programs without the stubs' versions reaching any other test.
    ///
    /// `colima --version`, never `colima version`: the undashed form talks to
    /// the running virtual machine (0.256 s against 0.045 s measured, and it
    /// prints a second, server-side line), so a stopped machine would make
    /// the check slow and a wedged one would make it hang.
    ///
    /// The time limit is a backstop for a program that never answers. Every
    /// program's output is captured by the shell's own `$( … )`, so only the
    /// shell itself writes to the pipe read here; ending the shell ends the
    /// read, even if a helper it started is still stuck.
    static func measureHelpers(
        environment: [String: String] = HelperPrograms.environment(),
        toolsFolder: String = HelperPrograms.binDirectory(),
        timeLimit: Duration = .seconds(5)
    ) -> String {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", helperProbeScript]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let outputPipe: Pipe = Pipe()
        process.standardOutput = outputPipe
        do {
            try process.run()
        } catch {
            return helperDescription(fromProbeOutput: "", toolsFolder: toolsFolder)
        }
        let watchdog: Task<Void, Never> = Task.detached(priority: .utility) {
            try? await Task.sleep(for: timeLimit)
            if Task.isCancelled {
                return
            }
            if process.isRunning {
                process.terminate()
            }
        }
        let outputData: Data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let output: String = String(decoding: outputData, as: UTF8.self)
        return helperDescription(
            fromProbeOutput: output,
            toolsFolder: toolsFolder,
            resolvingLinks: { path in
                return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            }
        )
    }

    /// Measures in the background and remembers the answer for every record
    /// written after it.
    ///
    /// A DETACHED task, not a plain `nonisolated async` function: this
    /// project builds with approachable concurrency, under which a plain one
    /// runs on its caller's actor — here, the main one — and the 0.3 s
    /// check would stall the window it was meant to stay out of the way of.
    /// The result says which thread the check ran on so a test can hold the
    /// code to that, rather than to a belief about it.
    @discardableResult
    static func refreshHelpers(
        environment: [String: String] = HelperPrograms.environment(),
        toolsFolder: String = HelperPrograms.binDirectory()
    ) -> Task<HelperMeasurement, Never> {
        return Task.detached(priority: .utility) {
            let ranOnTheMainThread: Bool = pthread_main_np() != 0
            let description: String = ProblemReportEnvironment.measureHelpers(
                environment: environment,
                toolsFolder: toolsFolder
            )
            ProblemReportEnvironment.measuredHelperDescription = description
            return HelperMeasurement(description: description, ranOnTheMainThread: ranOnTheMainThread)
        }
    }

    /// Turns the check's output into the Helpers line. PURE — the part the
    /// rules live in, and the part a test feeds real machine output to.
    ///
    /// The output is one `name<TAB>first line of its version<TAB>where it was
    /// found` row per program. A program with no row (the check ran out of
    /// time before reaching it) is "not checked"; a row with no path, or
    /// with nothing that reads as a version, is "not found".
    static func helperDescription(
        fromProbeOutput output: String,
        toolsFolder: String,
        resolvingLinks resolve: (String) -> String = { path in return path }
    ) -> String {
        var rowsByName: [String: [String]] = [:]
        for line in output.components(separatedBy: "\n") {
            let fields: [String] = line.components(separatedBy: "\t")
            if fields.count < 2 || fields[0].isEmpty {
                continue
            }
            rowsByName[fields[0]] = fields
        }

        var parts: [String] = [bundledEngineDescription]
        for helper in pinnedHelpers {
            guard let fields = rowsByName[helper.probeName] else {
                parts.append(helper.displayName + " not checked (pinned " + helper.pinnedVersion + ")")
                continue
            }
            let versionLine: String = fields[1]
            let path: String = fields.count > 2 ? fields[2] : ""
            let isBuildx: Bool = helper.probeName == "buildx"
            if versionLine.isEmpty || (!isBuildx && path.isEmpty) {
                parts.append(helper.displayName + " not found (would install " + helper.pinnedVersion + ")")
                continue
            }
            guard let version = versionNumber(in: versionLine) else {
                if isBuildx {
                    parts.append(helper.displayName + " not found (would install " + helper.pinnedVersion + ")")
                } else {
                    parts.append(helper.displayName + " found, version unreadable" + sourceLabel(
                        path: path, resolvedPath: resolve(path), toolsFolder: toolsFolder
                    ))
                }
                continue
            }
            var text: String = helper.displayName + " " + version
            if isBuildx {
                // Buildx is a plug-in of the Docker CLI, found in
                // `~/.docker/cli-plugins` — the SAME folder Plantoir's own
                // download and Homebrew's link both use — so where `docker`
                // lives says nothing about where buildx came from. Only its
                // own words are trusted: Homebrew's build says "Homebrew".
                if versionLine.contains("Homebrew") {
                    text += " (Homebrew)"
                }
            } else {
                text += sourceLabel(path: path, resolvedPath: resolve(path), toolsFolder: toolsFolder)
            }
            parts.append(text)
        }
        return parts.joined(separator: " · ")
    }

    /// " (Plantoir's copy)", " (Homebrew)", or " (found in <folder>)".
    ///
    /// Plantoir's copy is recognised by the folder it was FOUND in, before
    /// any link is followed. Homebrew by where the link LEADS, because
    /// `/usr/local/bin` is also where Docker Desktop puts its own link, and
    /// calling that Homebrew would be the same kind of wrong answer this
    /// line exists to stop giving.
    static func sourceLabel(path: String, resolvedPath: String, toolsFolder: String) -> String {
        if path.hasPrefix(toolsFolder + "/") {
            return " (Plantoir's copy)"
        }
        if resolvedPath.hasPrefix("/opt/homebrew/")
            || resolvedPath.hasPrefix("/usr/local/Cellar/")
            || resolvedPath.hasPrefix("/usr/local/Homebrew/") {
            return " (Homebrew)"
        }
        let folder: String = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return " (found in " + folder + ")"
    }

    /// The first word that reads as a version: after an optional leading
    /// "v", it starts with a digit and has a dot in it. "Docker version
    /// 29.7.1, build e9452d6e78" gives "29.7.1"; "github.com/docker/buildx
    /// v0.36.1 Homebrew" gives "0.36.1".
    static func versionNumber(in line: String) -> String? {
        let separators: CharacterSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ","))
        for word in line.components(separatedBy: separators) {
            var candidate: String = word
            if candidate.hasPrefix("v") {
                candidate = String(candidate.dropFirst())
            }
            guard let first = candidate.first else {
                continue
            }
            if first.isASCII && first.isNumber && candidate.contains(".") {
                return candidate
            }
        }
        return nil
    }

    /// Exact OS build number (e.g. "24G84"), via sysctl kern.osversion.
    static var osBuildNumber: String? {
        var size: Int = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer: [CChar] = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    /// Darwin kernel release version (e.g. "24.6.0"), via sysctl kern.osrelease.
    static var darwinRelease: String? {
        var size: Int = 0
        guard sysctlbyname("kern.osrelease", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer: [CChar] = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osrelease", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    /// arm64 or x86_64 — which matters here, because the assistant runs
    /// natively on one and the whole toolchain emulates on the other.
    static var machineArchitecture: String {
        var information: utsname = utsname()
        if uname(&information) != 0 {
            return "unknown"
        }
        var bytes: [CChar] = []
        withUnsafeBytes(of: &information.machine) { raw in
            for byte in raw {
                bytes.append(CChar(bitPattern: byte))
            }
        }
        return String(cString: bytes)
    }
}

/// One helper program the launchers can download, and the version they
/// would download.
nonisolated struct PinnedHelper: Sendable {

    // MARK: - Stored properties

    /// What a report calls it: "Docker CLI".
    let displayName: String

    /// Its row in the check's output: "docker".
    let probeName: String

    /// The version `setup.sh` downloads when it is missing: "29.7.2".
    let pinnedVersion: String

    /// The `setup.sh` variable that pins it, for the test that keeps the two
    /// in step.
    let setupVariable: String
}

/// What one background check found, and whether it kept off the main thread.
nonisolated struct HelperMeasurement: Sendable {

    // MARK: - Stored properties

    let description: String
    let ranOnTheMainThread: Bool
}

/// Where records are kept, and how many.
///
/// `~/Library/Logs/Plantoir` — the folder macOS keeps application logs in,
/// which means Console.app lists it under Log Reports and a teacher who
/// goes looking finds it where they would expect to. Plain text, never a
/// bundle format: a file a teacher cannot open is a file they cannot decide
/// whether to send.
nonisolated struct ProblemReportStore {

    // MARK: - Stored properties

    /// The folder these records live in.
    let folderURL: URL

    /// Records older than the newest this many are deleted as each new one
    /// is written. Twenty covers a working session with room to spare; a
    /// teacher reporting something from last week is being asked about
    /// something they have since done twenty more tasks after.
    static let mostRetainedRuns: Int = 20

    /// The breadcrumb trail: one line per notable thing the teacher did, in
    /// the order it happened.
    ///
    /// ONE file rather than one per subject, because the question a report is
    /// read to answer is "what was going on when it broke", and that is a
    /// sequence. Two files, each half a story, forces whoever reads them to
    /// interleave by timestamp in their head.
    static let activityFileName: String = "activity.txt"
    static let mostActivityLines: Int = 1200
    static let keptActivityLines: Int = 600

    /// The folder for the running app.
    ///
    /// Under a test run this is a throwaway folder instead. The tests build
    /// real `ScriptRunner`s and real agents, and those write a record when
    /// they finish — which without this lands in the folder a REAL problem
    /// report is later gathered from, so a report would carry a handful of
    /// invented tasks alongside the teacher's own. Tests that care about the
    /// store pass their own folder in; this is only about the ones that do
    /// not know they have one.
    static var standard: ProblemReportStore {
        if ProblemReportStore.isRunningTests {
            return ProblemReportStore(folderURL: ProblemReportStore.throwawayFolderURL)
        }
        return ProblemReportStore(folderURL: ProblemReportStore.defaultFolderURL())
    }

    /// True while XCTest is hosting the app.
    static var isRunningTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// One folder per test RUN rather than per call, so that a test which
    /// writes and then reads back still finds what it wrote.
    static let throwawayFolderURL: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("Plantoir-tests-" + UUID().uuidString, isDirectory: true)

    // MARK: - Computed properties

    /// Where the per-task records sit.
    var runsFolderURL: URL {
        return folderURL.appendingPathComponent("runs", isDirectory: true)
    }

    // MARK: - Functions

    /// `~/Library/Logs/Plantoir`.
    static func defaultFolderURL() -> URL {
        let library: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return library.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Plantoir", isDirectory: true)
    }

    /// Writes one record and drops the oldest beyond the limit.
    ///
    /// Never throws to its caller: a task that has just finished must not
    /// be reported as having failed because a log could not be written.
    @discardableResult
    func write(_ record: RunRecord, timeZone: TimeZone = TimeZone.current) -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: runsFolderURL, withIntermediateDirectories: true
            )
            let url: URL = runsFolderURL.appendingPathComponent(record.fileName(timeZone: timeZone))
            try record.text(timeZone: timeZone).write(to: url, atomically: true, encoding: .utf8)
            pruneRuns()
            return url
        } catch {
            return nil
        }
    }

    /// Every kept record, newest first.
    func runFileURLs() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: runsFolderURL, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var records: [URL] = []
        for url in contents {
            if url.pathExtension == "txt" {
                records.append(url)
            }
        }
        // The names begin with a sortable timestamp, so sorting by name is
        // sorting by time — no file dates involved, and therefore nothing
        // that a copy or a restore from a backup could disturb.
        records.sort { first, second in
            return first.lastPathComponent > second.lastPathComponent
        }
        return records
    }

    /// Keeps the newest records and deletes the rest.
    func pruneRuns() {
        let records: [URL] = runFileURLs()
        if records.count <= ProblemReportStore.mostRetainedRuns {
            return
        }
        var index: Int = ProblemReportStore.mostRetainedRuns
        while index < records.count {
            try? FileManager.default.removeItem(at: records[index])
            index += 1
        }
    }

    /// Adds one line to the trail.
    ///
    /// Everything notable goes here — folders opened, sections chosen, tasks
    /// started and finished, the assistant answering — because the trail is
    /// what turns a pile of records into an account of what somebody was
    /// doing. The task records hold the DETAIL; this holds the order.
    func appendActivityLine(_ line: String) {
        let safeLine: String = LogRedactor.redacting(line)
        do {
            try FileManager.default.createDirectory(
                at: folderURL, withIntermediateDirectories: true
            )
        } catch {
            return
        }
        let url: URL = folderURL.appendingPathComponent(ProblemReportStore.activityFileName)
        var existing: String = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        existing += safeLine + "\n"
        try? ProblemReportStore.trimmed(existing).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Whether there is anything worth gathering.
    ///
    /// Asked BEFORE the teacher is asked anything, so that somebody who has
    /// just installed the app is told there is nothing to send rather than
    /// being walked through a choice and a save panel first and told
    /// afterwards.
    var hasAnythingToReport: Bool {
        if !runFileURLs().isEmpty {
            return true
        }
        return !activityText(includingPrompts: true).isEmpty
    }

    /// Whether the teacher has actually typed anything to the local AI
    /// assistant.
    ///
    /// The question the CHECKBOX asks is only meaningful if there is
    /// something to answer it about. Opening the assistant and closing it
    /// again leaves turns on the trail but no prompts, so this looks for the
    /// prompt lines themselves rather than for assistant events — the
    /// narrower test, and the one that matches what the box controls.
    var hasAssistantPrompts: Bool {
        for line in activityText(includingPrompts: true).components(separatedBy: "\n") {
            if line.hasPrefix(AssistTurnRecord.promptMarker) {
                return true
            }
        }
        return false
    }

    /// The trail as it should go into a report.
    ///
    /// The teacher's own sentences are the one thing here that is
    /// unmistakably theirs, so they are kept locally and left out unless the
    /// teacher ticks the box. Everything else — which tool was chosen, with
    /// which arguments filled in, how long it took — goes either way, and
    /// that is most of what a routing problem is diagnosed from.
    func activityText(includingPrompts: Bool) -> String {
        let url: URL = folderURL.appendingPathComponent(ProblemReportStore.activityFileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        if includingPrompts {
            return text
        }
        var kept: [String] = []
        var droppedAny: Bool = false
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix(AssistTurnRecord.promptMarker) {
                droppedAny = true
                continue
            }
            kept.append(line)
        }
        if droppedAny {
            kept.insert("(What the teacher typed was left out of this report.)", at: 0)
        }
        return kept.joined(separator: "\n")
    }

    /// Drops the oldest lines once the file has grown past its limit.
    ///
    /// Trimming to HALF rather than to the limit on purpose: trimming to
    /// the limit would rewrite the whole file on every single line once it
    /// filled up, which for a file this size is work nobody asked for.
    static func trimmed(_ text: String) -> String {
        var lines: [String] = text.components(separatedBy: "\n")
        if lines.count <= mostActivityLines {
            return text
        }
        lines.removeFirst(lines.count - keptActivityLines)
        return lines.joined(separator: "\n")
    }
}
