import Foundation
import Observation
import OSLog

/// Runs one of the toolchain's shell scripts and streams its output.
///
/// The app never re-implements toolchain behaviour: everything happens by
/// running the same `setup.sh` / `preview.sh` / `deploy.sh` a teacher would
/// run in Terminal, attached to a pseudo-terminal so interactive steps
/// (like `docker exec -it`) behave exactly as they do on the command line.
@Observable
class ScriptRunner {

    // MARK: - Stored properties

    /// Clean, display-ready output of the running (or finished) script.
    var transcript: TranscriptBuilder = TranscriptBuilder()

    /// True from launch until the script exits.
    var isRunning: Bool = false

    /// The exit code of the most recent run, once it has finished.
    var lastExitCode: Int32?

    /// A launch failure message, if the script could not start at all.
    var launchProblem: String?

    /// When output last arrived — used to sense a stalled prompt.
    var lastOutputAt: Date = Date()

    /// True when the script appears to be waiting for an answer, with the
    /// question it is waiting on. Maintained HERE rather than in a view,
    /// so nothing decides it while a view body is being evaluated.
    var isAwaitingInput: Bool = false
    var pendingQuestion: String = ""

    /// When this runner last began a task. Lets the interface tell which
    /// of several tasks is the current one once they have all finished.
    var startedAt: Date?

    /// What the script itself accepts as "cancel" at this question, when
    /// it offered one. Sending it lets the script wind itself down and
    /// tidy up, rather than being killed mid-step.
    var pendingCancelToken: String = ""

    /// True when the teacher backed out of a question and the script was
    /// told to stop the way it stops itself.
    var wasCancelled: Bool = false

    /// How far through the current step the task has reported getting —
    /// "125 of 234" while pages are uploading. A slow connection can sit on
    /// one step for minutes, and a bar that does not move reads as a hang.
    var stepDetail: String = ""

    /// True when the teacher stopped the task themselves. Ending a task
    /// on purpose makes it exit non-zero, which is not a failure and
    /// must not be reported as one.
    var wasStoppedByUser: Bool = false

    /// True for the moment a caller has this runner finish one script and
    /// immediately start another on it — a multi-destination deploy that
    /// needs a fresh build runs "preview.sh --build-only" then `deploy.sh`
    /// back to back on the SAME runner, so the build's own real exit code
    /// briefly leaves `isRunning == false` with `lastExitCode == 0` before
    /// the deploy script starts. Read literally, that is indistinguishable
    /// from the whole leg being done — `TaskProgressView` treats this flag
    /// as "still running" so the console keeps showing progress instead of
    /// flashing "Done" for a leg that has a second script still to run.
    /// Set by the caller before it waits on the first script's exit; reset
    /// by `run()` itself, so starting anything new always clears it.
    var isBetweenPhases: Bool = false

    /// Set when the pending question is a launcher asking for a
    /// publishing credential, so the interface can explain how to get one
    /// rather than repeating the launcher's one-line prompt. Nil for every
    /// ordinary question.
    var pendingCredentialRequest: CredentialRequest?

    /// The answer the script would use if the teacher simply agreed —
    /// what it showed in square brackets. Offered in the answer field
    /// rather than left in the wording of the question.
    var suggestedAnswer: String = ""

    /// What the current (or most recent) run was, kept so that a record of
    /// it can be written once it finishes. Held here rather than passed
    /// through the termination handler because the handler runs on whatever
    /// thread the process died on, and this is read on the main actor.
    private var runScriptName: String = ""
    private var runArguments: [String] = []
    private var runWorkingFolderPath: String = ""

    /// When this run's record was last written to disk, so a long task
    /// refreshes its record occasionally rather than on every chunk.
    private var recordWrittenAt: Date?

    /// The pending "output has gone quiet, write the record" work.
    private var recordWrite: DispatchWorkItem?

    /// Where a finished task's record is written. Replaceable so a test can
    /// point it at a folder of its own rather than at the real one.
    var reportStore: ProblemReportStore = ProblemReportStore.standard

    private var promptCheck: DispatchWorkItem?

    private var process: Process?
    private var terminal: PseudoTerminal?

    /// Callers of `waitUntilFinished()` parked here until the script
    /// actually exits — see that function for why this replaced polling.
    private var finishedContinuations: [CheckedContinuation<Bool, Never>] = []

    /// Output that has arrived but not yet been shown. Chunks land on a
    /// background queue and reach the interface at a fixed, modest rate.
    nonisolated private let outputBuffer: OutputBuffer = OutputBuffer()

    /// How often buffered output reaches the interface.
    nonisolated private static let flushInterval: TimeInterval = 0.15

    // MARK: - Computed properties

    /// True when the last run finished with exit code 0.
    var lastRunSucceeded: Bool {
        if let lastExitCode {
            return lastExitCode == 0
        }
        return false
    }

    // MARK: - Functions

    /// Starts a script (e.g. "preview.sh") from the working folder.
    ///
    /// `keepingTranscript` continues an earlier run's output, so a task
    /// made of two scripts (build, then publish) reads as one job.
    func run(
        scriptNamed scriptName: String,
        arguments: [String],
        workingDirectory: URL,
        keepingTranscript: Bool = false
    ) {
        if isRunning {
            return
        }

        if !keepingTranscript {
            transcript = TranscriptBuilder()
        }
        lastExitCode = nil
        launchProblem = nil
        // Every run answers for itself. This runner is `@State` on the section
        // window and is reused for every preview in it, so keeping findings
        // across runs meant a teacher who fixed the problem in Obsidian and
        // previewed again was shown the SAME dialog — the nagging this whole
        // feature is supposed to avoid, produced by the feature itself.
        //
        // Guarded exactly as the transcript above is, and for the same reason:
        // a deploy runs `preview.sh --build-only` and then `deploy.sh` on THIS
        // runner with `keepingTranscript: true`, and only the build phase
        // announces health. Clearing unconditionally emptied the array between
        // the two, so a deploy threw away the findings it had just collected.
        resetHealthFindings(keepingTranscript: keepingTranscript)
        wasCancelled = false
        wasStoppedByUser = false
        isBetweenPhases = false
        stepDetail = ""

        let scriptURL: URL = workingDirectory.appendingPathComponent(scriptName)
        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            launchProblem = "This working folder is missing a piece it needs (\(scriptName)). Try choosing your working folder again from the File menu."
            return
        }

        var newTerminal: PseudoTerminal
        do {
            newTerminal = try PseudoTerminal()
        } catch {
            launchProblem = "Could not get started: \(error.localizedDescription)"
            return
        }

        let newProcess: Process = Process()
        newProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        var fullArguments: [String] = [scriptURL.path]
        for argument in arguments {
            fullArguments.append(argument)
        }
        newProcess.arguments = fullArguments
        newProcess.currentDirectoryURL = workingDirectory

        // GUI apps inherit a minimal PATH; the scripts need Homebrew's
        // programs (docker, colima) the same way a Terminal session has them.
        var environment: [String: String] = ProcessInfo.processInfo.environment
        let existingPath: String = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + existingPath
        environment["TERM"] = "xterm-256color"
        newProcess.environment = environment

        newProcess.standardInput = newTerminal.slaveHandle
        newProcess.standardOutput = newTerminal.slaveHandle
        newProcess.standardError = newTerminal.slaveHandle

        newTerminal.masterHandle.readabilityHandler = { handle in
            let data: Data = handle.availableData
            if data.isEmpty {
                return
            }
            let text: String = String(decoding: data, as: UTF8.self)
            self.bufferOutput(text)
        }

        newProcess.terminationHandler = { finishedProcess in
            let exitCode: Int32 = finishedProcess.terminationStatus
            Task { @MainActor in
                self.finishRun(exitCode: exitCode)
            }
        }

        do {
            try newProcess.run()
        } catch {
            launchProblem = "Could not get started: \(error.localizedDescription)"
            return
        }

        process = newProcess
        terminal = newTerminal
        isRunning = true
        startedAt = Date()
        // The quiet timer measures silence from THIS task's start, not
        // from whenever the runner happened to be created. A runner is
        // built when its window or sheet appears, so without this the
        // first "still working… (Ns)" counted the time the teacher spent
        // filling in the form — opening at 35s and reading like a stall.
        lastOutputAt = Date()
        runScriptName = scriptName
        runArguments = arguments
        runWorkingFolderPath = workingDirectory.path
        // Redacted even here. The arguments carry a Cloudflare Account ID
        // and a folder path with the teacher's account name in it, and
        // `.public` in a Logger means exactly that — written out in full,
        // to a log this app does not own and cannot clean up afterwards.
        let describedArguments: String = LogRedactor.redacting(arguments.joined(separator: " "))
        AppLog.output.info("Started \(scriptName, privacy: .public) \(describedArguments, privacy: .public)")
        // A record exists from the first moment, not only at the end. A
        // PREVIEW never ends on its own — it serves until the teacher stops
        // it — so waiting for the finish meant the likeliest thing anybody
        // reports ("the preview is stuck") was the one thing that left no
        // trace at all.
        recordWrittenAt = nil
        writeRecordOfRun(exitCode: nil)
        ActivityTrail.note(.taskStarted, "started " + LogRedactor.redacting(([scriptName] + arguments).joined(separator: " ")))
    }

    /// Waits for the current run to finish; true when it succeeded.
    /// Waits for the script to end. The result says whether it succeeded;
    /// callers that only need to sequence work after the script (whatever
    /// its outcome) are free to ignore it.
    ///
    /// Event-driven rather than polled: `finishRun()` resumes every parked
    /// caller the instant it sets `isRunning = false`, instead of a caller
    /// noticing only on its next poll. That gap used to be visible — a
    /// multi-destination deploy that builds before its first leg runs this
    /// TWICE on the same runner (build, then deploy), back to back with no
    /// suspension point between them; with polling at 300ms, the runner's
    /// freshly-"finished" state (a real exit code, nothing left running)
    /// could sit on screen for up to 300ms and render as "Done" before the
    /// very next line put it back to work — indistinguishable from the
    /// whole leg finishing early. Resuming immediately collapses that gap
    /// to effectively nothing.
    @discardableResult
    func waitUntilFinished() async -> Bool {
        if !isRunning {
            return lastExitCode == 0
        }
        return await withCheckedContinuation { continuation in
            finishedContinuations.append(continuation)
        }
    }

    /// Sends one line of input to the script, as if typed in Terminal.
    func send(line: String) {
        isAwaitingInput = false
        pendingCredentialRequest = nil
        guard let terminal else {
            return
        }
        let data: Data = Data((line + "\n").utf8)
        try? terminal.masterHandle.write(contentsOf: data)
    }

    /// Backs out of the question the way the script's own cancel option
    /// would, so its clean-up runs. Without such an option there is
    /// nothing safe to send, so the question is simply dismissed.
    func cancelPendingQuestion() {
        wasCancelled = true
        isAwaitingInput = false
        pendingCredentialRequest = nil
        if pendingCancelToken.isEmpty {
            // No option to decline, so the only way to honour Cancel is
            // to stop the task itself.
            terminate()
            return
        }
        send(line: pendingCancelToken)
    }

    /// Sends raw text (no newline added) to the script.
    func send(rawText: String) {
        guard let terminal else {
            return
        }
        let data: Data = Data(rawText.utf8)
        try? terminal.masterHandle.write(contentsOf: data)
    }

    /// Stops the task because the teacher asked it to stop.
    func stopByUser() {
        wasStoppedByUser = true
        terminate()
    }

    /// Cancels the task because the teacher asked to cancel it.
    ///
    /// Sends an interrupt signal (Control-C) through the pseudo-terminal
    /// so the foreground process group can handle signal traps and exit
    /// cleanly, falling back to a direct process termination after two seconds.
    func cancelByUser(onCleanup: (() -> Void)? = nil) {
        wasCancelled = true
        wasStoppedByUser = true
        onCleanup?()
        send(rawText: "\u{03}")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else {
                return
            }
            if self.isRunning {
                self.terminate()
            }
        }
    }

    /// Stops the running script.
    ///
    /// Note: this terminates the script process itself. A Quartz preview
    /// server left behind inside the container is cleaned up by the
    /// toolchain on the next preview run (it frees port 8081 first).
    func terminate() {
        guard let process else {
            return
        }
        if process.isRunning {
            process.terminate()
        }
    }

    /// The milestones for whatever this runner was started to do, set by
    /// the view that launches it. Drives the deterministic progress bar.
    var milestones: [TaskMilestone] = [] {
        didSet {
            reachedMilestoneCount = 0
            unscannedOutput = ""
        }
    }

    /// Milestones detected so far. Tracked as output ARRIVES rather than
    /// by re-reading the whole transcript on every refresh, which stalls
    /// the main thread once a long publish fills it.
    private var reachedMilestoneCount: Int = 0

    /// Output not yet scanned for markers (kept small).
    private var unscannedOutput: String = ""

    /// How many milestones have been reached (0…milestones.count).
    var milestonesReached: Int {
        if milestones.isEmpty {
            return 0
        }
        // A finished, successful task has completed everything.
        if !isRunning && lastExitCode == 0 {
            return milestones.count
        }
        return reachedMilestoneCount
    }

    /// Takes a chunk from the reading queue and schedules a flush.
    /// Runs OFF the main actor, so it must not touch observed state.
    nonisolated private func bufferOutput(_ text: String) {
        let needsScheduling: Bool = outputBuffer.add(text)
        if !needsScheduling {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ScriptRunner.flushInterval) {
            MainActor.assumeIsolated {
                self.flushBufferedOutput()
            }
        }
    }

    /// Hands everything buffered to the interface in one update.
    private func flushBufferedOutput() {
        let buffered: (text: String, chunkCount: Int) = outputBuffer.take()
        let text: String = buffered.text
        let chunkCount: Int = buffered.chunkCount

        if text.isEmpty {
            return
        }
        let started: Date = Date()
        receiveOutput(text)
        refreshRecordIfDue()
        let elapsed: TimeInterval = Date().timeIntervalSince(started)
        if elapsed > 0.05 || chunkCount > 200 {
            AppLog.output.warning("""
                Slow flush: \(chunkCount) chunks, \(text.count) characters, \
                \(elapsed, format: .fixed(precision: 3))s, transcript now \
                \(self.transcript.lines.count) lines
                """)
        }
    }

    /// The single entry point for output arriving from a running script:
    /// records it and folds it into the milestone count. (Tests feed
    /// simulated output through here too, so both paths behave alike.)
    func receiveOutput(_ text: String) {
        // Findings are read from the RAW text first: the transcript drops the
        // machine-readable lines on the way in (they are machinery, and a
        // teacher reads that console), so anything that wants them must take
        // them before they are filtered out.
        collectHealthFindings(in: text)
        transcript.append(rawText: text)
        advanceMilestones(with: text)
        lastOutputAt = Date()

        // Fresh output means the script is working, not waiting.
        isAwaitingInput = false
        pendingCredentialRequest = nil
        schedulePromptCheck()
    }

    /// After a quiet spell, decide whether the script is sitting at a
    /// question and, if so, publish it for the interface to ask.
    private func schedulePromptCheck() {
        promptCheck?.cancel()
        let check: DispatchWorkItem = DispatchWorkItem {
            MainActor.assumeIsolated {
                if !self.isRunning {
                    return
                }
                let line: String = self.transcript.currentLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    return
                }
                if ScriptRunner.looksLikeQuestion(line) {
                    let asked = ScriptRunner.separateDefaultAnswer(from: line)
                    self.pendingQuestion = asked.question
                    self.suggestedAnswer = asked.suggestedAnswer
                    self.pendingCancelToken = asked.cancelToken
                    self.pendingCredentialRequest = CredentialRequest.matching(asked.question)
                    if let request = self.pendingCredentialRequest {
                        // A first publish that "never finished" is usually
                        // this: a task waiting behind a dialog nobody saw.
                        // The line names WHICH credential; the answer to it
                        // is a secret and is never recorded.
                        ActivityTrail.note(.askedForACredential, "asked for the " + request.fieldLabel)
                    }
                    self.isAwaitingInput = true
                }
            }
        }
        promptCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: check)
    }

    /// A plain-language reason the task failed, when its output shows a
    /// trouble the app recognises. Nil means show the output instead.
    var failureExplanation: String? {
        return FailureExplainer.explanation(in: transcript.recentText(maximumCharacters: 8000))
    }

    /// The local address the preview will serve at, once the launcher has
    /// announced it. The host port belongs to this folder's container and
    /// is not knowable in advance, so the announcement is the truth.
    var previewAddress: URL? {
        return ScriptRunner.previewAddress(in: transcript.recentText(maximumCharacters: 8000))
    }

    /// Reads "Preview will be available at: http://localhost:8091/" from
    /// the output, taking the LAST announcement.
    static func previewAddress(in text: String) -> URL? {
        let marker: String = "Preview will be available at: "
        var found: URL?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(rawLine)
            guard let markerRange = line.range(of: marker) else {
                continue
            }
            let address: String = String(line[markerRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            // Poll by numeric address: Safari-style localhost/IPv6 quirks
            // do not apply to URLSession, but consistency costs nothing.
            let numeric: String = address.replacingOccurrences(of: "localhost", with: "127.0.0.1")
            if let url = URL(string: numeric), url.port != nil {
                found = url
            }
        }
        return found
    }

    /// The published site's address, if the output announced one.
    /// The teacher's own domain for the section being published, applied
    /// to the live-site link when set.
    var customDomainForLinks: String?

    var publishedSiteURL: URL? {
        guard let parsed = ScriptRunner.publishedSiteURL(in: transcript.recentText(maximumCharacters: 8000)) else {
            return nil
        }
        return ScriptRunner.applyingCustomDomain(customDomainForLinks, to: parsed)
    }

    /// What the build said was wrong with this course's folders.
    ///
    /// Collected as output ARRIVES rather than read back off the transcript,
    /// which is the one thing about this that is easy to get wrong: every
    /// other structured-line reader here works from
    /// `transcript.recentText(maximumCharacters: 8000)`, and that is a TAIL.
    /// The health lines are printed in the middle of a build — before Quartz
    /// runs — so on any real build they have scrolled well past the end of an
    /// 8,000-character window by the time anybody asks.
    private(set) var healthFindings: [SiteHealthFinding] = []

    /// Whatever arrived after the last newline, kept until the rest of the
    /// line turns up.
    ///
    /// Output arrives in PTY-sized chunks, not lines — which is why
    /// `TranscriptBuilder` keeps a `currentLine` at all. The health payload is
    /// the LONGEST line a build prints, so it is the likeliest of all to
    /// straddle a read boundary; without this, a split marker line failed both
    /// the prefix test and the JSON parse and was dropped silently, and the
    /// finding never reached the dialog, the assistant, or the trail.
    private var pendingHealthLine: String = ""

    /// Reads whatever is left in the carry-over buffer as a finished line.
    /// Seams for the tests, which cannot start a real script but must be able
    /// to prove that a finding survives the END of a run and the SECOND phase
    /// of a deploy — the two places findings were being silently dropped.
    func simulateFinishForTesting(exitCode: Int32) {
        flushPendingHealthLine()
        lastExitCode = exitCode
        isRunning = false
    }

    func prepareForContinuationForTesting(keepingTranscript: Bool) {
        resetHealthFindings(keepingTranscript: keepingTranscript)
    }

    /// The one implementation, so the test seam above exercises what `run()`
    /// actually does rather than a copy of it. A duplicated reset would pass
    /// while the real path regressed — which is precisely how the scheduled
    /// log's append bug got through its own test.
    private func resetHealthFindings(keepingTranscript: Bool) {
        if keepingTranscript {
            return
        }
        healthFindings = []
        pendingHealthLine = ""
    }

    private func flushPendingHealthLine() {
        let leftover: String = pendingHealthLine
        pendingHealthLine = ""
        if leftover.isEmpty {
            return
        }
        rememberHealthFindings(in: leftover)
    }

    private func rememberHealthFindings(in text: String) {
        for finding in SiteHealthFinding.findings(in: text) {
            if healthFindings.contains(finding) {
                continue
            }
            healthFindings.append(finding)
            // A sentence a teacher would recognise, carrying the stable check
            // NAME in brackets. Both halves earn their place: rule 5 says a
            // trail line must read as something that happened rather than as a
            // function name, while the name is what somebody reading the trail
            // months later can match against the contract — the product
            // wording will have been reworded by then.
            ActivityTrail.note(
                .folderProblemFound,
                "found a problem with this course's folders (\(finding.name))",
                course: finding.course, section: finding.section
            )
        }
    }

    private func collectHealthFindings(in text: String) {
        let combined: String = pendingHealthLine + text
        var completeLines: [String] = []
        var carried: String = ""
        var isFirst: Bool = true
        for piece in combined.components(separatedBy: "\n") {
            if !isFirst {
                completeLines.append(carried)
            }
            carried = piece
            isFirst = false
        }
        // `carried` is now whatever followed the final newline — an unfinished
        // line, unless the chunk happened to end on one.
        pendingHealthLine = carried
        rememberHealthFindings(in: completeLines.joined(separator: "\n"))
    }

    /// The folder a local-folder deploy published into, if the output
    /// announced one — the deployer prints `PUBLISHED_FOLDER=<path>`.
    var publishedFolderURL: URL? {
        return ScriptRunner.publishedFolderURL(in: transcript.recentText(maximumCharacters: 8000))
    }

    static func publishedFolderURL(in text: String) -> URL? {
        let marker: String = "PUBLISHED_FOLDER="
        var found: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(rawLine).trimmingCharacters(in: .whitespaces)
            if let markerRange = line.range(of: marker) {
                let path: String = String(line[markerRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty {
                    found = path
                }
            }
        }
        guard let found else {
            return nil
        }
        return URL(fileURLWithPath: found)
    }

    /// The same address on the teacher's own domain: the host swapped, the
    /// rest untouched. Without a domain the address passes through as-is.
    static func applyingCustomDomain(_ domain: String?, to url: URL) -> URL {
        guard let domain, !domain.isEmpty else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.host = domain
        components.scheme = "https"
        components.port = nil
        return components.url ?? url
    }

    /// Reads the site's address out of a publish's output.
    ///
    /// The deployer announces it under a label — "Live URL:" when it
    /// creates a site, "Site:" and "Site URL:" for one that already
    /// exists — so the label is what to look for. Judging by the address
    /// alone missed repeat publishes, which quote the site record's
    /// plain-http `url` rather than the `ssl_url` a new site reports.
    static func publishedSiteURL(in text: String) -> URL? {
        var announced: String?
        var anyNetlifyAddress: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(rawLine).trimmingCharacters(in: .whitespaces)
            // Netlify's own dashboard is not the teacher's website.
            if line.hasPrefix("Admin:") {
                continue
            }
            let namesTheSite: Bool = line.hasPrefix("Site URL:") || line.hasPrefix("Live URL:") || line.hasPrefix("Site:")
            for rawToken in line.split(whereSeparator: { character in character.isWhitespace }) {
                let token: String = ScriptRunner.tidiedAddress(String(rawToken))
                if !ScriptRunner.isWebAddress(token) {
                    continue
                }
                if token.contains("app.netlify.com") || token.contains("docs.netlify.com") {
                    continue
                }
                if namesTheSite {
                    announced = token
                } else if token.contains(".netlify.app") {
                    anyNetlifyAddress = token
                }
            }
        }
        guard let chosen = announced ?? anyNetlifyAddress else {
            return nil
        }
        return URL(string: ScriptRunner.preferringSecure(chosen))
    }

    /// Strips the punctuation that ends a sentence, not an address.
    static func tidiedAddress(_ token: String) -> String {
        var address: String = token
        while let last = address.last, last == "." || last == "," || last == ")" {
            address.removeLast()
        }
        return address
    }

    /// True when this looks like something a browser can open.
    static func isWebAddress(_ token: String) -> Bool {
        return token.hasPrefix("https://") || token.hasPrefix("http://")
    }

    /// Netlify serves every site over https and redirects plain http, so
    /// offer the secure address even when the record quotes the other.
    static func preferringSecure(_ address: String) -> String {
        let insecurePrefix: String = "http://"
        if address.hasPrefix(insecurePrefix) && address.contains(".netlify.app") {
            return "https://" + String(address.dropFirst(insecurePrefix.count))
        }
        return address
    }

    /// Prompt shapes the toolchain's scripts actually use.
    static func looksLikeQuestion(_ line: String) -> Bool {
        if line.hasSuffix(":") || line.hasSuffix("?") || line.hasSuffix(">") {
            return true
        }
        if line.contains("(y/n)") || line.contains("[Y/n]") || line.contains("[Default:") {
            return true
        }
        return false
    }

    /// Splits a question into the wording to show and the default answer
    /// to offer, when the script named one in square brackets.
    ///
    /// "Enter Netlify site name [ics3u-s3-2026-gordon]:" becomes
    /// "Enter Netlify site name:" with "ics3u-s3-2026-gordon" waiting in
    /// the answer field, ready to accept or type over. That reads as a
    /// filled-in form rather than as instructions to follow.
    static func separateDefaultAnswer(from question: String) -> AskedQuestion {
        guard let openIndex = question.lastIndex(of: "["), let closeIndex = question.lastIndex(of: "]") else {
            return AskedQuestion(question: ScriptRunner.asked(question), suggestedAnswer: "", cancelToken: ScriptRunner.cancelToken(in: question))
        }
        if openIndex >= closeIndex {
            return AskedQuestion(question: ScriptRunner.asked(question), suggestedAnswer: "", cancelToken: ScriptRunner.cancelToken(in: question))
        }
        var offered: String = String(question[question.index(after: openIndex)..<closeIndex]).trimmingCharacters(in: .whitespaces)

        // Some prompts name what they are offering: "[Default: foo]".
        let defaultLabel: String = "Default:"
        if offered.hasPrefix(defaultLabel) {
            offered = String(offered.dropFirst(defaultLabel.count)).trimmingCharacters(in: .whitespaces)
        }
        if offered.isEmpty {
            return AskedQuestion(question: ScriptRunner.asked(question), suggestedAnswer: "", cancelToken: ScriptRunner.cancelToken(in: question))
        }
        // "[Y/n]" lists choices rather than naming a value, so the
        // wording keeps it and nothing is filled in.
        if offered.contains("/") {
            return AskedQuestion(question: ScriptRunner.asked(question), suggestedAnswer: "", cancelToken: ScriptRunner.cancelToken(in: question))
        }

        var wording: String = String(question[question.startIndex..<openIndex]).trimmingCharacters(in: .whitespaces)
        let afterBracket: String = String(question[question.index(after: closeIndex)...]).trimmingCharacters(in: .whitespaces)
        wording += afterBracket
        return AskedQuestion(question: ScriptRunner.asked(wording), suggestedAnswer: offered, cancelToken: ScriptRunner.cancelToken(in: question))
    }

    /// The key the script offered as a way out, such as the "q" in
    /// "(or 'q' to cancel)". Empty when it offered none.
    static func cancelToken(in question: String) -> String {
        var token: String = ""
        var aside: String = ""
        var depth: Int = 0
        for character in question {
            if character == "(" {
                depth += 1
                if depth == 1 {
                    aside = ""
                    continue
                }
            }
            if character == ")" && depth > 0 {
                depth -= 1
                if depth == 0 {
                    if ScriptRunner.offersAWayOut(aside) {
                        let quoted: String = ScriptRunner.quotedText(in: aside)
                        if !quoted.isEmpty {
                            token = quoted
                        }
                    }
                    continue
                }
            }
            if depth > 0 {
                aside.append(character)
            }
        }
        return token
    }

    /// True when a parenthetical offers a way to abandon the task.
    static func offersAWayOut(_ aside: String) -> Bool {
        let wording: String = aside.lowercased()
        if wording.contains("cancel") || wording.contains("quit") {
            return true
        }
        return false
    }

    /// The text between the first pair of quotation marks.
    static func quotedText(in text: String) -> String {
        var collected: String = ""
        var isInsideQuotes: Bool = false
        for character in text {
            if character == "\'" || character == "\"" {
                if isInsideQuotes {
                    return collected
                }
                isInsideQuotes = true
                continue
            }
            if isInsideQuotes {
                collected.append(character)
            }
        }
        return ""
    }

    /// The wording as a dialog should ask it.
    static func asked(_ question: String) -> String {
        return ScriptRunner.tidyingSpacing(in: ScriptRunner.removingKeystrokeAside(from: question))
    }

    /// Removes a parenthetical that names a key to type, such as
    /// "(or 'q' to cancel)". The dialog has a Cancel button, so telling
    /// a teacher to type a letter is both wrong and puzzling here.
    static func removingKeystrokeAside(from question: String) -> String {
        var result: String = ""
        var aside: String = ""
        var depth: Int = 0
        for character in question {
            if character == "(" {
                depth += 1
                if depth == 1 {
                    aside = ""
                    continue
                }
            }
            if character == ")" && depth > 0 {
                depth -= 1
                if depth == 0 {
                    if !ScriptRunner.namesAKeyToType(aside) {
                        result += "(" + aside + ")"
                    }
                    continue
                }
            }
            if depth > 0 {
                aside.append(character)
            } else {
                result.append(character)
            }
        }
        // An unclosed bracket is not an aside; keep what was written.
        if depth > 0 {
            result += "(" + aside
        }
        return result
    }

    /// True when a parenthetical is an escape hatch for a typist, rather
    /// than information the question needs (such as "(y/n)").
    static func namesAKeyToType(_ aside: String) -> Bool {
        let wording: String = aside.lowercased()
        if wording.contains("cancel") || wording.contains("quit") || wording.contains("skip") {
            return true
        }
        return false
    }

    /// Closes up the gaps left behind by a removed aside.
    static func tidyingSpacing(in text: String) -> String {
        var result: String = ""
        var previousWasSpace: Bool = false
        for character in text {
            if character == " " {
                if previousWasSpace {
                    continue
                }
                previousWasSpace = true
                result.append(character)
                continue
            }
            let closesTheSentence: Bool = character == ":" || character == "?"
            if closesTheSentence && previousWasSpace {
                result.removeLast()
            }
            previousWasSpace = false
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Folds newly arrived output into the milestone count.
    private func advanceMilestones(with newText: String) {
        if milestones.isEmpty {
            return
        }
        unscannedOutput += newText

        // Take the HIGHEST milestone the new output reveals: a later
        // marker implies the earlier steps, so varying output never
        // stalls or reverses the bar.
        while reachedMilestoneCount < milestones.count {
            var matchedIndex: Int?
            var matchedEnd: String.Index?
            for index in reachedMilestoneCount..<milestones.count {
                if let range = unscannedOutput.range(of: milestones[index].marker) {
                    matchedIndex = index
                    matchedEnd = range.upperBound
                }
            }
            guard let matchedIndex, let matchedEnd else {
                break
            }
            reachedMilestoneCount = matchedIndex + 1
            unscannedOutput = String(unscannedOutput[matchedEnd...])
            // A count belongs to the step that reported it.
            stepDetail = ""
        }

        if let progress = ScriptRunner.uploadProgress(in: newText) {
            stepDetail = "\(progress.done) of \(progress.total)"
        } else if let total = ScriptRunner.uploadTotal(in: newText) {
            stepDetail = "0 of \(total)"
        } else if let step = ScriptRunner.buildStepProgress(in: newText) {
            stepDetail = "step \(step.done) of \(step.total)"
        }

        // Keep only enough tail for a marker split across two chunks.
        if unscannedOutput.count > 8000 {
            unscannedOutput = String(unscannedOutput.suffix(4000))
        }
    }

    /// Reads "uploaded 125/234 required files" from newly arrived output,
    /// taking the LAST such line: several may arrive in one chunk.
    static func uploadProgress(in text: String) -> (done: Int, total: Int)? {
        var found: (done: Int, total: Int)?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(rawLine)
            guard let marker = line.range(of: "uploaded ") else {
                continue
            }
            let rest: Substring = line[marker.upperBound...]
            guard let counts = rest.split(separator: " ").first else {
                continue
            }
            let parts: [Substring] = counts.split(separator: "/")
            if parts.count == 2, let done = Int(parts[0]), let total = Int(parts[1]) {
                found = (done, total)
            }
        }
        return found
    }

    /// Reads "[ 7/15]" from the image build's own output ("#12 [ 7/15]
    /// RUN …"), so the minutes-long first build shows movement.
    static func buildStepProgress(in text: String) -> (done: Int, total: Int)? {
        var found: (done: Int, total: Int)?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(rawLine)
            if !line.hasPrefix("#") {
                continue
            }
            guard let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]") else {
                continue
            }
            let inside: String = String(line[line.index(after: open)..<close]).replacingOccurrences(of: " ", with: "")
            let parts: [Substring] = inside.split(separator: "/")
            if parts.count == 2, let done = Int(parts[0]), let total = Int(parts[1]) {
                found = (done, total)
            }
        }
        return found
    }

    /// Reads the total from "Netlify requires 234 file(s) for this deploy."
    /// so the count appears before the first batch finishes.
    static func uploadTotal(in text: String) -> Int? {
        var found: Int?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: String = String(rawLine)
            guard let marker = line.range(of: "requires ") else {
                continue
            }
            let rest: Substring = line[marker.upperBound...]
            guard let word = rest.split(separator: " ").first else {
                continue
            }
            if let total = Int(word) {
                found = total
            }
        }
        return found
    }

    /// Progress from 0 to 1 for the bar.
    var progressFraction: Double {
        if milestones.isEmpty {
            return 0
        }
        return Double(milestonesReached) / Double(milestones.count)
    }

    /// The step currently under way, e.g. "Building your site" — the
    /// milestone AFTER the last one reached, or the final one when done.
    var currentMilestoneLabel: String {
        if milestones.isEmpty {
            return friendlyPhase
        }
        let reached: Int = milestonesReached
        if reached >= milestones.count {
            return milestones[milestones.count - 1].label
        }
        return milestones[reached].label
    }

    /// The milestone label with reassurance for slow, quiet steps. A
    /// step that reports its own count (uploads, build steps) shows that
    /// count — the count IS the movement. Otherwise, when the script has
    /// gone quiet for a few seconds — long npm installs are the usual
    /// culprit — a live "still working… (Ns)" timer counts up so the
    /// step never looks frozen. Mirrors the Windows app's behaviour.
    func milestoneText(asOf now: Date) -> String {
        if !stepDetail.isEmpty {
            return "\(currentMilestoneLabel) \(stepDetail)"
        }
        let quietSeconds: Int = Int(now.timeIntervalSince(lastOutputAt))
        if isRunning && quietSeconds >= 4 {
            return "\(currentMilestoneLabel) still working… (\(quietSeconds)s)"
        }
        return currentMilestoneLabel
    }

    /// "Step 2 of 6" for the label beside the bar.
    var stepDescription: String {
        if milestones.isEmpty {
            return ""
        }
        let currentStep: Int = min(milestonesReached + 1, milestones.count)
        return "Step \(currentStep) of \(milestones.count)"
    }

    /// A friendly description of what is happening right now, derived
    /// from markers in the output — used when no milestones are set.
    var friendlyPhase: String {
        let recentText: String = String(transcript.recentText(maximumCharacters: 4000))
        let phases: [(marker: String, label: String)] = [
            ("Launching Quartz preview", "Starting the preview…"),
            ("Building static site", "Building your site…"),
            ("Emitting files", "Building your site…"),
            ("Parsing input files", "Building your site…"),
            ("Installing dependencies", "Preparing your site (first time can take a few minutes)…"),
            ("Pulling", "Downloading components (first time can take a few minutes)…"),
            ("Starting Colima", "Starting up (first time can take a few minutes)…"),
            ("Waiting for the container runtime", "Starting up…"),
            ("delta deploy", "Deploying your site…"),
            ("Uploaded", "Deploying your site…"),
            ("Deploying", "Deploying your site…"),
        ]
        // The LAST marker to appear in the output is the current phase.
        var bestLabel: String = "Working…"
        var bestPosition: String.Index? = nil
        for phase in phases {
            var searchRange: Range<String.Index>? = nil
            // Find the last occurrence of this marker.
            var lastFound: Range<String.Index>? = nil
            while let found = recentText.range(of: phase.marker, options: [], range: searchRange) {
                lastFound = found
                searchRange = found.upperBound..<recentText.endIndex
            }
            if let lastFound {
                if bestPosition == nil || lastFound.lowerBound > bestPosition! {
                    bestPosition = lastFound.lowerBound
                    bestLabel = phase.label
                }
            }
        }
        return bestLabel
    }

    /// True when the task appears stuck at a question: the current line
    /// is prompt-shaped and no output has arrived for a few seconds.
    /// (Normally the app answers questions itself; this is the safety
    /// net that tells the teacher to look at the details.)
    func mayBeWaitingForInput(asOf now: Date) -> Bool {
        if !isRunning {
            return false
        }
        if now.timeIntervalSince(lastOutputAt) < 4 {
            return false
        }
        let line: String = transcript.currentLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            return false
        }
        if line.hasSuffix(":") || line.hasSuffix("?") || line.hasSuffix(">") {
            return true
        }
        if line.contains("(y/n)") || line.contains("[Y/n]") || line.contains("[Default:") {
            return true
        }
        return false
    }

    private func finishRun(exitCode: Int32) {
        promptCheck?.cancel()
        recordWrite?.cancel()
        isAwaitingInput = false
        // Show anything still buffered when the script ended.
        flushBufferedOutput()
        // And read the last line even if it never got a newline. The carry-over
        // buffer is only drained by a LATER chunk containing one, so a finding
        // printed as the very last output would otherwise be lost — the exact
        // failure the buffer was added to prevent, surviving at the end of the
        // run instead of in the middle of it.
        flushPendingHealthLine()
        AppLog.output.info("Finished with exit code \(exitCode), transcript \(self.transcript.lines.count) lines")
        lastExitCode = exitCode
        isRunning = false
        terminal?.masterHandle.readabilityHandler = nil
        process = nil
        terminal = nil
        writeRecordOfRun(exitCode: exitCode)
        ActivityTrail.note(
            .taskFinished,
            runScriptName + " — "
            + ScriptRunner.outcomeDescription(
                exitCode: exitCode,
                wasStoppedByUser: wasStoppedByUser,
                wasCancelled: wasCancelled
            ).lowercased()
            + String(format: " after %.1fs", Date().timeIntervalSince(startedAt ?? Date()))
        )

        // Wake every `waitUntilFinished()` caller now, on this same
        // synchronous step — not on their next poll. See that function's
        // comment for why the gap mattered.
        let outcome: Bool = exitCode == 0
        let waitingCallers: [CheckedContinuation<Bool, Never>] = finishedContinuations
        finishedContinuations = []
        for continuation in waitingCallers {
            continuation.resume(returning: outcome)
        }
    }

    /// Rewrites this run's record if enough time has passed.
    ///
    /// Tied to output arriving rather than to a timer, so a preview that has
    /// been sitting quietly for an hour costs nothing. The record is written
    /// under the same name each time — it is named after the task's START —
    /// so this replaces the file rather than filling the folder.
    private func refreshRecordIfDue(now: Date = Date()) {
        if ScriptRunner.shouldWriteRecordNow(lastWrittenAt: recordWrittenAt, now: now) {
            writeRecordOfRun(exitCode: nil)
        }
        scheduleRecordWriteWhenOutputGoesQuiet()
    }

    /// Whether a running task's record is old enough to be worth rewriting.
    ///
    /// This is the ceiling for a CHATTY task — one printing steadily for an
    /// hour still has a record no more than this far behind.
    nonisolated static func shouldWriteRecordNow(lastWrittenAt: Date?, now: Date) -> Bool {
        guard let lastWrittenAt else {
            return true
        }
        return now.timeIntervalSince(lastWrittenAt) >= ScriptRunner.recordRefreshInterval
    }

    /// Writes the record shortly after output STOPS.
    ///
    /// The throttle above is not enough on its own, and the reason is worth
    /// keeping because it took a real run to see. A preview with a warm
    /// container prints for about five seconds and then serves in silence
    /// for as long as the teacher leaves it open. Output therefore stopped
    /// BEFORE the ten-second throttle expired, every refresh declined, and
    /// the record kept its opening lines and nothing else — which is the
    /// exact case the whole feature exists for. Measured on a real preview:
    /// 19 flushes inside 5.2 seconds, zero refreshes, a 466-byte record.
    ///
    /// So the tail is caught by waiting for quiet instead: each flush pushes
    /// this back, and two seconds after the last one the record is written
    /// whole.
    private func scheduleRecordWriteWhenOutputGoesQuiet() {
        recordWrite?.cancel()
        let work: DispatchWorkItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else {
                    return
                }
                self.writeRecordOfRun(exitCode: nil)
            }
        }
        recordWrite = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ScriptRunner.recordQuietInterval, execute: work
        )
    }

    /// How often a running task's record is brought up to date. Ten seconds
    /// loses at most ten seconds of output if the app is force-quit, and a
    /// hang — the case this is for — is not usually decided in that window.
    nonisolated static let recordRefreshInterval: TimeInterval = 10

    /// How long output must be quiet before the record is written whole.
    /// MUST be shorter than the refresh interval, or a task whose output
    /// stops before the throttle expires keeps a record with nothing in it.
    nonisolated static let recordQuietInterval: TimeInterval = 2

    /// What a task that has not finished is called.
    nonisolated static let stillRunningOutcome: String = "Still running"

    /// Keeps a record of the task, so a problem can still be looked into
    /// after the window showing it has gone.
    ///
    /// Written for EVERY task, not only failures. Half of what makes a
    /// failure legible is the run before it that worked — and a task that
    /// "succeeded" while doing the wrong thing leaves no other trace at all.
    private func writeRecordOfRun(exitCode: Int32?) {
        if runScriptName.isEmpty {
            return
        }
        let transcriptText: String = transcript.displayText
        let wasFailure: Bool
        if let exitCode {
            wasFailure = exitCode != 0 && !wasStoppedByUser && !wasCancelled
        } else {
            wasFailure = false
        }
        var explanation: String?
        if wasFailure {
            explanation = FailureExplainer.explanation(in: transcriptText)
        }
        let record: RunRecord = RunRecord(
            startedAt: startedAt ?? Date(),
            finishedAt: Date(),
            scriptName: runScriptName,
            arguments: runArguments,
            workingFolderPath: runWorkingFolderPath,
            outcome: ScriptRunner.outcomeDescription(
                exitCode: exitCode,
                wasStoppedByUser: wasStoppedByUser,
                wasCancelled: wasCancelled
            ),
            wasFailure: wasFailure,
            explanation: explanation,
            transcript: transcriptText,
            appDescription: ProblemReportEnvironment.appDescription,
            systemDescription: ProblemReportEnvironment.systemDescription,
            helperDescription: ProblemReportEnvironment.helperDescription
        )
        reportStore.write(record)
        recordWrittenAt = Date()
    }

    /// How a finished task is described in its record.
    ///
    /// Stopping a task on purpose makes it exit non-zero, and so does
    /// backing out of a question. Neither is a failure, and a record that
    /// called them one would send somebody looking for a bug that is a
    /// teacher changing their mind.
    nonisolated static func outcomeDescription(
        exitCode: Int32?,
        wasStoppedByUser: Bool,
        wasCancelled: Bool
    ) -> String {
        guard let exitCode else {
            return ScriptRunner.stillRunningOutcome
        }
        if wasStoppedByUser {
            return "Stopped on purpose"
        }
        if wasCancelled {
            return "Backed out of a question"
        }
        if exitCode == 0 {
            return "Finished"
        }
        return "Failed (exit \(exitCode))"
    }
}
