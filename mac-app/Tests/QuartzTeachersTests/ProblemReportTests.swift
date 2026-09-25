import XCTest
@testable import QuartzTeachers

/// The records Plantoir keeps so that a problem reported next week can still
/// be looked into.
///
/// The redaction RULES themselves are contract cases and are run from
/// `SharedRulesContractTests`; what is tested here is the machinery round
/// them — that redaction is actually applied on the way to disk, that the
/// oldest records are dropped, and that a teacher's own sentences do not
/// leave the machine unless they said so.
final class ProblemReportTests: XCTestCase {

    // MARK: - Stored properties

    private var folderURL: URL = URL(fileURLWithPath: "/")

    /// UTC everywhere, so a machine in another time zone reads the same
    /// expectations as this one.
    private let utc: TimeZone = TimeZone(identifier: "UTC") ?? TimeZone.current

    // MARK: - Set-up

    override func setUpWithError() throws {
        folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("problem-reports-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folderURL)
    }

    // MARK: - Functions

    private func record(
        startedAt: Date = Date(timeIntervalSince1970: 1_786_000_000),
        seconds: TimeInterval = 42.3,
        scriptName: String = "deploy.sh",
        arguments: [String] = ["ICS3U", "1", "--target", "cloudflare"],
        outcome: String = "Failed (exit 1)",
        wasFailure: Bool = true,
        explanation: String? = nil,
        transcript: String = "Publishing…"
    ) -> RunRecord {
        return RunRecord(
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(seconds),
            scriptName: scriptName,
            arguments: arguments,
            workingFolderPath: "/Users/jordanteacher/Documents/Teaching",
            outcome: outcome,
            wasFailure: wasFailure,
            explanation: explanation,
            transcript: transcript,
            appDescription: "Plantoir 1.0 (12) · pid 4711 · /Applications/Plantoir.app",
            systemDescription: "macOS 15.6.0 (24G84) · Darwin 24.6.0 · arm64 · 8 cores · 36 GB",
            helperDescription: "llama.cpp b10435 (Metal) · Colima v0.10.3 · Lima 2.2.0 · Docker CLI 29.7.2 · Buildx v0.36.1"
        )
    }

    // MARK: - One record

    func testARecordSaysWhatRanAndHowItWent() {
        let text: String = record(explanation: "Netlify is limiting how often websites can be deployed right now.")
            .text(timeZone: utc)
        XCTAssertTrue(text.contains("deploy.sh ICS3U 1 --target cloudflare"), text)
        XCTAssertTrue(text.contains("Failed (exit 1) after 42.3s"), text)
        XCTAssertTrue(text.contains("Netlify is limiting"), text)
        XCTAssertTrue(text.contains("Plantoir 1.0 (12)"), text)
        XCTAssertTrue(text.contains("macOS 15.6.0 (24G84)"), text)
        XCTAssertTrue(text.contains("llama.cpp b10435 (Metal)"), text)
    }

    /// A failure nothing recognised is the one worth a person's attention,
    /// so the record says so rather than leaving the line out.
    func testAnUnexplainedFailureSaysItIsUnexplained() {
        let text: String = record(explanation: nil).text(timeZone: utc)
        XCTAssertTrue(text.contains("nothing recognised"), text)
    }

    /// But a task that was STOPPED is not a failure, and saying nothing was
    /// recognised about it reads as a fault where there was none.
    func testATaskStoppedOnPurposeIsNotExplainedAtAll() {
        let text: String = record(
            outcome: "Stopped on purpose", wasFailure: false, explanation: nil
        ).text(timeZone: utc)
        XCTAssertTrue(text.contains("Stopped on purpose"), text)
        XCTAssertFalse(text.contains("Explained"), text)
    }

    /// The teacher's account name goes, from the header AND from anything
    /// the task printed — one redaction over the finished text, so a field
    /// added later is covered without anybody remembering to.
    func testTheWholeRecordIsRedactedNotJustTheTranscript() {
        let text: String = record(
            transcript: "reading /Users/jordanteacher/Documents/Teaching/ICS3U\nCLOUDFLARE_API_TOKEN=abc123XYZ_secret"
        ).text(timeZone: utc)
        XCTAssertFalse(text.contains("jordanteacher"), text)
        XCTAssertFalse(text.contains("abc123XYZ_secret"), text)
        XCTAssertTrue(text.contains("/Users/person/Documents/Teaching"), text)
        XCTAssertTrue(text.contains("CLOUDFLARE_API_TOKEN=" + LogRedactor.removedToken), text)
    }

    /// Named so that sorting the folder by name is sorting it by time.
    func testTheFileNameIsSortableAndNamesTheTask() {
        XCTAssertEqual(record().fileName(timeZone: utc), "2026-08-06-070640-deploy.txt")
    }

    /// A record is read from the END, because that is where a failure is.
    func testAVeryLongTranscriptIsTrimmedFromTheFront() {
        let long: String = String(repeating: "x", count: RunRecord.mostTranscriptCharacters + 500)
        let trimmed: String = record(transcript: long + "THE END").trimmedTranscript
        XCTAssertTrue(trimmed.hasPrefix(RunRecord.trimmedMarker), String(trimmed.prefix(60)))
        XCTAssertTrue(trimmed.hasSuffix("THE END"), String(trimmed.suffix(20)))
    }

    // MARK: - Which outcomes are failures and which are not

    /// Stopping a task on purpose makes it exit non-zero, and so does backing
    /// out of a question. Recording either as a failure would send somebody
    /// looking for a bug that is a teacher changing their mind.
    func testStoppingOnPurposeIsNotRecordedAsAFailure() {
        XCTAssertEqual(
            ScriptRunner.outcomeDescription(exitCode: 130, wasStoppedByUser: true, wasCancelled: false),
            "Stopped on purpose"
        )
        XCTAssertEqual(
            ScriptRunner.outcomeDescription(exitCode: 1, wasStoppedByUser: false, wasCancelled: true),
            "Backed out of a question"
        )
        XCTAssertEqual(
            ScriptRunner.outcomeDescription(exitCode: 0, wasStoppedByUser: false, wasCancelled: false),
            "Finished"
        )
        XCTAssertEqual(
            ScriptRunner.outcomeDescription(exitCode: 2, wasStoppedByUser: false, wasCancelled: false),
            "Failed (exit 2)"
        )
    }

    // MARK: - The breadcrumb trail

    /// A task that has not finished must still be recorded. A PREVIEW never
    /// finishes on its own — it serves until the teacher stops it — so
    /// waiting for the end meant the likeliest thing anybody reports ("the
    /// preview is stuck") was the one thing that left no trace.
    func testATaskThatHasNotFinishedIsStillRecorded() {
        XCTAssertEqual(
            ScriptRunner.outcomeDescription(exitCode: nil, wasStoppedByUser: false, wasCancelled: false),
            ScriptRunner.stillRunningOutcome
        )
        let text: String = record(
            outcome: ScriptRunner.stillRunningOutcome, wasFailure: false
        ).text(timeZone: utc)
        XCTAssertTrue(text.contains("Still running"), text)
        XCTAssertFalse(text.contains("Explained"), text)
    }

    /// The throttle is a CEILING for a chatty task, not the whole policy.
    func testARunningRecordIsRewrittenOnceItIsOldEnough() {
        let now: Date = Date(timeIntervalSince1970: 1_786_000_000)
        XCTAssertTrue(ScriptRunner.shouldWriteRecordNow(lastWrittenAt: nil, now: now))
        XCTAssertFalse(ScriptRunner.shouldWriteRecordNow(
            lastWrittenAt: now.addingTimeInterval(-1), now: now
        ))
        XCTAssertTrue(ScriptRunner.shouldWriteRecordNow(
            lastWrittenAt: now.addingTimeInterval(-ScriptRunner.recordRefreshInterval), now: now
        ))
    }

    /// The invariant that a real preview broke. A warm-container preview
    /// prints for about five seconds and then serves in silence — so if the
    /// quiet wait were the longer of the two, output would stop before the
    /// throttle expired and the record would keep its opening lines and
    /// nothing else. Measured before the fix: 19 flushes in 5.2s, zero
    /// refreshes, a 466-byte record of a preview that had built a whole site.
    func testTheRecordIsWrittenSoonerAfterQuietThanTheThrottleWouldAllow() {
        XCTAssertLessThan(ScriptRunner.recordQuietInterval, ScriptRunner.recordRefreshInterval)
    }

    /// The trail is read by somebody months later, so a line says what
    /// happened in words and carries the time it happened.
    func testATrailLineIsTimedAndReadable() {
        let moment: Date = Date(timeIntervalSince1970: 1_786_000_000)
        XCTAssertEqual(
            ActivityTrail.line("opened the working folder /Users/person/Teaching", at: moment, timeZone: utc),
            "2026-08-06 07:06:40 · opened the working folder /Users/person/Teaching"
        )
    }

    /// Everything lands in ONE file, in order — the whole point of a trail.
    /// Two files each holding half a story force whoever reads them to
    /// interleave by timestamp in their head.
    func testTheTrailAndTheAssistantShareOneFile() {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.appendActivityLine(
            ActivityTrail.line("started preview.sh COMP 1", at: Date(timeIntervalSince1970: 1_786_000_000), timeZone: utc)
        )
        store.appendActivityLine(
            AssistTurnRecord(
                at: Date(timeIntervalSince1970: 1_786_000_060),
                courseCode: "COMP", sectionNumber: 1,
                toolName: "publish_pages", argumentNames: ["course"],
                seconds: 1.0, completionTokens: 12, stoppedAtGate: false
            ).lines
        )
        let text: String = store.activityText(includingPrompts: true)
        let startedFirst: Bool = text.range(of: "started preview.sh")!.lowerBound
            < text.range(of: "chose publish_pages")!.lowerBound
        XCTAssertTrue(startedFirst, text)
    }

    // MARK: - The folder they are kept in

    func testRecordsAreWrittenAndListedNewestFirst() throws {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        let first: Date = Date(timeIntervalSince1970: 1_786_000_000)
        store.write(record(startedAt: first), timeZone: utc)
        store.write(record(startedAt: first.addingTimeInterval(3600), scriptName: "preview.sh"), timeZone: utc)

        let listed: [URL] = store.runFileURLs()
        XCTAssertEqual(listed.count, 2)
        XCTAssertTrue(listed[0].lastPathComponent.hasSuffix("preview.txt"), listed[0].lastPathComponent)
    }

    func testOnlyTheNewestRecordsAreKept() throws {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        let start: Date = Date(timeIntervalSince1970: 1_786_000_000)
        var index: Int = 0
        while index < ProblemReportStore.mostRetainedRuns + 6 {
            store.write(record(startedAt: start.addingTimeInterval(Double(index) * 60)), timeZone: utc)
            index += 1
        }
        XCTAssertEqual(store.runFileURLs().count, ProblemReportStore.mostRetainedRuns)
        // The newest survived, the oldest did not.
        let names: [URL] = store.runFileURLs()
        XCTAssertEqual(names[0].lastPathComponent, "2026-08-06-073140-deploy.txt")
    }

    // MARK: - The assistant's own record

    func testAnAssistantTurnSaysWhatWasChosenButNotWhatItWasGiven() {
        let record: AssistTurnRecord = AssistTurnRecord(
            at: Date(timeIntervalSince1970: 1_786_000_000),
            courseCode: "ICS3U",
            sectionNumber: 1,
            toolName: "publish_pages",
            argumentNames: ["course", "section", "titles"],
            seconds: 2.14,
            completionTokens: 44,
            stoppedAtGate: false
        )
        let text: String = record.lines
        XCTAssertTrue(text.contains("chose publish_pages(course, section, titles)"), text)
        XCTAssertTrue(text.contains("2.1s"), text)
        XCTAssertTrue(text.contains("44 tokens"), text)
    }

    /// What the teacher typed is recorded when the message is SENT, not when
    /// an answer comes back. Tying it to the reply meant an engine that
    /// failed — or one still thinking when they gave up — left no trace of
    /// the sentence that caused the trouble, and left the report's checkbox
    /// hidden from somebody who had plainly used the assistant.
    func testWhatWasAskedIsRecordedWhenItIsSent() {
        let text: String = AssistTurnRecord.askedLines(
            prompt: "What will students see?",
            courseCode: "COMP",
            sectionNumber: 1,
            at: Date(timeIntervalSince1970: 1_786_000_000),
            timeZone: utc
        )
        XCTAssertTrue(text.contains("COMP/1 · asked the local AI assistant"), text)
        XCTAssertTrue(
            text.contains(AssistTurnRecord.promptMarker + "What will students see?"), text
        )
        // And it is still droppable by prefix, which is what keeps it out of
        // a report the teacher did not tick the box for.
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.appendActivityLine(text)
        XCTAssertTrue(store.hasAssistantPrompts)
        XCTAssertFalse(
            store.activityText(includingPrompts: false).contains("What will students see?")
        )
    }

    /// The names of the arguments, never their values — a page title is the
    /// teacher's work, and which tool was called with which arguments filled
    /// in answers the routing question on its own.
    func testOnlyTheArgumentNamesAreTaken() {
        XCTAssertEqual(
            AssistTurnRecord.argumentNames(
                inJSON: "{\"titles\": [\"Unit 4, Day 12\"], \"course\": \"ICS3U\"}"
            ),
            ["course", "titles"]
        )
        XCTAssertEqual(AssistTurnRecord.argumentNames(inJSON: "not json"), [])
    }

    /// The default is that the teacher's own sentences stay on their machine.
    func testWhatTheTeacherTypedIsLeftOutOfAReportUnlessTheyAskForIt() {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.appendActivityLine(
            "2026-08-06 07:06:40 · ICS3U/1 · chose publish_pages(course, section)\n"
            + AssistTurnRecord.promptMarker + "publish tomorrow's class"
        )

        let withoutPrompts: String = store.activityText(includingPrompts: false)
        XCTAssertTrue(withoutPrompts.contains("chose publish_pages"), withoutPrompts)
        XCTAssertFalse(withoutPrompts.contains("publish tomorrow's class"), withoutPrompts)
        XCTAssertTrue(withoutPrompts.contains("was left out of this report"), withoutPrompts)

        let withPrompts: String = store.activityText(includingPrompts: true)
        XCTAssertTrue(withPrompts.contains("publish tomorrow's class"), withPrompts)
    }

    /// It is redacted on the way in, like everything else — the teacher's
    /// sentence is their words, not a licence to write their home folder out.
    func testTrailLinesAreRedactedOnTheWayIn() {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.appendActivityLine("looked in /Users/jordanteacher/Documents")
        XCTAssertFalse(store.activityText(includingPrompts: true).contains("jordanteacher"))
    }

    func testTheTrailStopsGrowing() {
        var lines: [String] = []
        var index: Int = 0
        while index < ProblemReportStore.mostActivityLines + 50 {
            lines.append("line \(index)")
            index += 1
        }
        let trimmed: String = ProblemReportStore.trimmed(lines.joined(separator: "\n"))
        XCTAssertEqual(trimmed.components(separatedBy: "\n").count, ProblemReportStore.keptActivityLines)
        XCTAssertTrue(trimmed.hasSuffix("line \(ProblemReportStore.mostActivityLines + 49)"), trimmed.suffix(20).description)
    }

    // MARK: - Two writers at once never lose a line (#238)

    /// Four writers in one process, all at once. A lock that belonged to the
    /// PROCESS would let these straight past each other; the folder lock is
    /// per open folder, so they wait exactly as four processes would. Before
    /// #238 every line rewrote the whole file and about three in four of
    /// these were lost. 400 lines stays under the trim, so every one of them
    /// must be there.
    func testWritersAtTheSameInstantEachKeepTheirLine() async {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<4 {
                group.addTask {
                    await ProblemReportTests.writeLines(to: store, writer: "writer \(writer)", count: 100)
                }
            }
        }
        let text: String = store.activityText(includingPrompts: true)
        XCTAssertEqual(ProblemReportTests.linesIn(text).count, 400)
        for writer in 0..<4 {
            for number in 0..<100 {
                XCTAssertTrue(
                    text.contains("writer \(writer) line \(number)\n"),
                    "writer \(writer) line \(number) was lost"
                )
            }
        }
    }

    /// The app and a launcher writing together — the pairing that happens
    /// every time the app starts a preview or a publish, because the launcher
    /// it just started notes its own lines while the app notes the app's. The
    /// launcher's append is the REAL one (`FolderContainers.trailFunction`,
    /// the same lines `note_on_the_trail` carries). Stays under the trim, so
    /// every line must be kept: 900 of 900. Before #238 the app's rewrite
    /// threw away most of the launcher's lines (52 of 300 kept, measured).
    @MainActor
    func testALauncherWritingAtTheSameTimeKeepsEveryLine() async throws {
        let home: URL = folderURL.appendingPathComponent("home", isDirectory: true)
        let store: ProblemReportStore = ProblemReportStore(folderURL: ProblemReportTests.trailFolder(inHome: home))
        let launcher: Process = try ProblemReportTests.startLauncherWriting(lines: 300, inHome: home)
        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<2 {
                group.addTask {
                    await ProblemReportTests.writeLines(to: store, writer: "writer \(writer)", count: 300)
                }
            }
            group.addTask {
                await ProblemReportTests.waitFor(launcher)
            }
        }
        XCTAssertEqual(launcher.terminationStatus, 0)
        let text: String = store.activityText(includingPrompts: true)
        var launcherLinesKept: Int = 0
        for line in ProblemReportTests.linesIn(text) {
            if line.contains("launcher line ") {
                launcherLinesKept += 1
            }
        }
        XCTAssertEqual(launcherLinesKept, 300, "the launcher's lines were lost")
        XCTAssertEqual(ProblemReportTests.linesIn(text).count, 900)
    }

    /// The trim is the one write that REPLACES the file, so it is the one a
    /// launcher's append could be lost under. Each round starts the trail one
    /// line short of the limit, starts a launcher writing, and — once its
    /// first line has landed — adds ONE line from the app, which trims while
    /// the launcher is still appending. After the trim every line of the
    /// round is inside the kept window, so each round must keep all of them.
    /// Forty rounds, forty trims raced.
    @MainActor
    func testTheTrimNeverLosesALauncherLine() async throws {
        let home: URL = folderURL.appendingPathComponent("home", isDirectory: true)
        let trailFolder: URL = ProblemReportTests.trailFolder(inHome: home)
        try FileManager.default.createDirectory(at: trailFolder, withIntermediateDirectories: true)
        let trailURL: URL = trailFolder.appendingPathComponent(ProblemReportStore.activityFileName)
        let store: ProblemReportStore = ProblemReportStore(folderURL: trailFolder)
        var seed: String = ""
        for number in 0..<(ProblemReportStore.mostActivityLines - 1) {
            seed += "seed line \(number)\n"
        }
        let launcherLines: Int = 6
        var linesLost: Int = 0
        var trims: Int = 0
        for round in 0..<40 {
            try seed.write(to: trailURL, atomically: true, encoding: .utf8)
            let launcher: Process = try ProblemReportTests.startLauncherWriting(
                lines: launcherLines, inHome: home, saying: "round \(round) launcher line"
            )
            await ProblemReportTests.writeOneLineAfterTheLauncherStarts(
                to: store, saying: "round \(round) app line", launcher: launcher
            )
            XCTAssertEqual(launcher.terminationStatus, 0)
            let text: String = store.activityText(includingPrompts: true)
            if !text.contains("seed line 0\n") {
                trims += 1
            }
            if !text.contains("round \(round) app line\n") {
                linesLost += 1
            }
            for number in 0..<launcherLines {
                if !text.contains("round \(round) launcher line \(number)\n") {
                    linesLost += 1
                }
            }
        }
        XCTAssertEqual(trims, 40, "a round did not trim, so it proved nothing")
        XCTAssertEqual(linesLost, 0, "lines lost to a trim across 40 rounds")
    }

    /// The generated script's append and the launchers' are the same lines,
    /// so the lock the tests above prove for one is the lock the other takes.
    @MainActor
    func testTheGeneratedScriptAppendsTheWayTheLaunchersDo() throws {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let setupText: String = try String(
            contentsOf: repository.appendingPathComponent("setup.sh"),
            encoding: .utf8
        )
        let generated: String = FolderContainers.trailFunction(inHomeFolder: folderURL)
        var comparedLines: Int = 0
        for line in generated.components(separatedBy: "\n") {
            if line.contains("lockf") || line.contains(">> \"$trail/activity.txt\"") {
                XCTAssertTrue(setupText.contains(line + "\n"), "setup.sh no longer carries: \(line)")
                comparedLines += 1
            }
        }
        XCTAssertEqual(comparedLines, 2)
    }

    /// `~/Library/Logs/Plantoir` under a scratch home.
    private static func trailFolder(inHome home: URL) -> URL {
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Plantoir", isDirectory: true)
    }

    /// Starts `/bin/sh` running the generated script's own `note` function
    /// `lines` times, writing under `home`.
    @MainActor
    private static func startLauncherWriting(
        lines: Int,
        inHome home: URL,
        saying sentence: String = "launcher line"
    ) throws -> Process {
        var script: String = FolderContainers.trailFunction(inHomeFolder: home) + "\n"
        script += "i=0\n"
        script += "while [ \"$i\" -lt \(lines) ]; do note \"\(sentence) $i\"; i=$((i + 1)); done\n"
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// Off the test's actor, so the writers really do run side by side.
    /// `@concurrent` is load-bearing: under approachable concurrency a plain
    /// `nonisolated async` function runs on its caller's actor, and four
    /// writers on one actor would take turns rather than race.
    @concurrent
    private nonisolated static func writeLines(to store: ProblemReportStore, writer: String, count: Int) async {
        for number in 0..<count {
            store.appendActivityLine("\(writer) line \(number)")
        }
    }

    /// Waits until the launcher's first line is in the file, writes one line
    /// — the one that trims — while the launcher is still going, then waits
    /// for the launcher to finish. Waits on the file, not on a clock.
    @concurrent
    private nonisolated static func writeOneLineAfterTheLauncherStarts(
        to store: ProblemReportStore,
        saying sentence: String,
        launcher: Process
    ) async {
        let trailURL: URL = store.folderURL.appendingPathComponent(ProblemReportStore.activityFileName)
        var launcherHasWritten: Bool = false
        while !launcherHasWritten && launcher.isRunning {
            let text: String = (try? String(contentsOf: trailURL, encoding: .utf8)) ?? ""
            launcherHasWritten = text.contains("launcher line 0\n")
            await Task.yield()
        }
        store.appendActivityLine(sentence)
        launcher.waitUntilExit()
    }

    @concurrent
    private nonisolated static func waitFor(_ process: Process) async {
        process.waitUntilExit()
    }

    /// The trail's lines, without the empty one after the last newline.
    private static func linesIn(_ text: String) -> [String] {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    // MARK: - Tests must not write into the real folder

    /// The suite builds real script runners and real agents, and those write
    /// a record when they finish. Without this they would land in the folder
    /// a genuine problem report is gathered from, and a teacher's report —
    /// or, in practice, a developer's — would carry invented tasks beside the
    /// real ones.
    func testTheRealFolderIsNotWrittenToByTests() {
        XCTAssertTrue(ProblemReportStore.isRunningTests)
        XCTAssertNotEqual(
            ProblemReportStore.standard.folderURL,
            ProblemReportStore.defaultFolderURL()
        )
    }

    // MARK: - The report a teacher sends

    func testThereIsNothingToReportBeforeAnythingHasHappened() {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        // Asked BEFORE the teacher is asked anything, so somebody who has just
        // installed the app is not walked through a choice and a save panel
        // and told afterwards that there was nothing to send.
        XCTAssertFalse(store.hasAnythingToReport)
        XCTAssertNil(
            ProblemReportBuilder(store: store)
                .assembleFolder(includingAssistantPrompts: false, in: folderURL)
        )
    }

    func testThereIsSomethingToReportAsSoonAsOneTaskHasRun() {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.write(record(), timeZone: utc)
        XCTAssertTrue(store.hasAnythingToReport)
    }

    func testTheReportCarriesEveryKeptRecordAndANoteAboutItself() throws {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.write(record(), timeZone: utc)
        store.appendActivityLine("2026-08-06 07:06:40 · ICS3U/1 · answered in words · 1.4s")

        let destination: URL = folderURL.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let builder: ProblemReportBuilder = ProblemReportBuilder(store: store)
        let assembled: URL = try XCTUnwrap(
            builder.assembleFolder(includingAssistantPrompts: false, in: destination)
        )

        let tasks: [String] = try FileManager.default.contentsOfDirectory(
            atPath: assembled.appendingPathComponent("tasks").path
        )
        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: assembled.appendingPathComponent(ProblemReportBuilder.aboutFileName).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: assembled.appendingPathComponent(ProblemReportBuilder.trailFileName).path
        ))
    }

    /// The note is written for the teacher who is deciding whether to send
    /// it, so it must say what is NOT in there as plainly as what is.
    func testTheNoteSaysWhatIsLeftOut() {
        let builder: ProblemReportBuilder = ProblemReportBuilder(
            store: ProblemReportStore(folderURL: folderURL)
        )
        let note: String = builder.about(
            recordCount: 3,
            assistantPrompts: .excluded,
            now: Date(timeIntervalSince1970: 1_786_000_000),
            timeZone: utc
        )
        XCTAssertTrue(note.contains("NOT IN THIS REPORT"), note)
        XCTAssertTrue(note.contains("what you have WRITTEN on your pages"), note)
        XCTAssertTrue(note.contains("what you typed to the local AI assistant"), note)
        // Page NAMES really do appear — the website builder lists every one
        // as it works. Promising otherwise would be a promise a teacher can
        // check and find false, which is worse than not making it.
        XCTAssertTrue(note.contains("NAMES of your pages"), note)

        let noteWithPrompts: String = builder.about(
            recordCount: 3,
            assistantPrompts: .included,
            now: Date(timeIntervalSince1970: 1_786_000_000),
            timeZone: utc
        )
        XCTAssertTrue(noteWithPrompts.contains("because you asked for it"), noteWithPrompts)
    }

    /// A teacher who has never used the local AI assistant is told nothing
    /// about it — not even that it was left out. Promising that something was
    /// withheld invites them to wonder what else the app thinks they did.
    func testTheNoteIsSilentAboutAnAssistantTheyNeverUsed() {
        let builder: ProblemReportBuilder = ProblemReportBuilder(
            store: ProblemReportStore(folderURL: folderURL)
        )
        let note: String = builder.about(
            recordCount: 1,
            assistantPrompts: .none,
            now: Date(timeIntervalSince1970: 1_786_000_000),
            timeZone: utc
        )
        XCTAssertFalse(note.lowercased().contains("assistant"), note)
        XCTAssertTrue(note.contains("NOT IN THIS REPORT"), note)
    }

    /// The question is only worth asking if there is something to answer it
    /// about. Opening the assistant and closing it again leaves turns on the
    /// trail but nothing the teacher typed.
    func testTheAssistantQuestionDependsOnPromptsNotOnTurns() {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.appendActivityLine("2026-08-06 07:06:40 · COMP/1 · opened the assistant")
        XCTAssertFalse(store.hasAssistantPrompts)

        store.appendActivityLine(
            "2026-08-06 07:07:00 · COMP/1 · chose check_section(course)\n"
            + AssistTurnRecord.promptMarker + "What will students see?"
        )
        XCTAssertTrue(store.hasAssistantPrompts)
    }

    /// "the last 1 task(s)" is the kind of sentence that tells a teacher the
    /// thing they are reading was written for somebody else.
    func testTheNoteCountsTasksInPlainEnglish() {
        XCTAssertEqual(ProblemReportBuilder.taskCountPhrase(1), "the last task Plantoir ran for you")
        XCTAssertEqual(ProblemReportBuilder.taskCountPhrase(6), "the last 6 tasks Plantoir ran for you")
    }

    /// Two reports in one afternoon must not be a pile of files that have to
    /// be opened to be told apart — nor may they overwrite one another.
    func testTheReportNameCarriesTheTimeAndNotJustTheDay() {
        let made: Date = Date(timeIntervalSince1970: 1_786_000_000)
        XCTAssertEqual(
            ProblemReportBuilder.suggestedFileName(now: made, timeZone: utc),
            "Plantoir problem report 2026-08-06 at 07.06.40.zip"
        )
        // A second report, minutes later, is a different file.
        XCTAssertNotEqual(
            ProblemReportBuilder.suggestedFileName(now: made, timeZone: utc),
            ProblemReportBuilder.suggestedFileName(now: made.addingTimeInterval(600), timeZone: utc)
        )
    }

    /// And the folder inside carries the same stamp, or two reports unzipped
    /// side by side collide on the machine of whoever is trying to help.
    func testTheFolderInsideTheReportIsStampedToo() throws {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        store.write(record(), timeZone: utc)
        let destination: URL = folderURL.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let made: Date = Date(timeIntervalSince1970: 1_786_000_000)
        let assembled: URL = try XCTUnwrap(
            ProblemReportBuilder(store: store).assembleFolder(
                includingAssistantPrompts: false, in: destination, now: made, timeZone: utc
            )
        )
        XCTAssertEqual(assembled.lastPathComponent, "Plantoir problem report 2026-08-06 at 07.06.40")
    }

    // MARK: - The words a teacher reads

    /// Rule one: the interface never mentions the machinery. A teacher being
    /// asked whether to send something is exactly where that slips.
    func testTheReportNeverMentionsTheMachinery() {
        let builder: ProblemReportBuilder = ProblemReportBuilder(
            store: ProblemReportStore(folderURL: folderURL)
        )
        let note: String = builder.about(
            recordCount: 1,
            assistantPrompts: .excluded,
            now: Date(timeIntervalSince1970: 1_786_000_000),
            timeZone: utc
        )
        for forbidden in ["toolchain", "script", "Docker", "container", "log file", "transcript"] {
            XCTAssertFalse(
                note.lowercased().contains(forbidden.lowercased()),
                "\"\(forbidden)\" appears in what a teacher reads:\n\(note)"
            )
        }
    }

    // MARK: - Environment and launch logging

    func testProblemReportEnvironmentCapturesOSAndHelpers() {
        let system: String = ProblemReportEnvironment.systemDescription
        XCTAssertTrue(system.contains("macOS"), system)
        XCTAssertTrue(system.contains("cores"), system)
        XCTAssertTrue(system.contains("GB"), system)

        // The suite never measures (every refresh is behind a test guard),
        // so what a record carries here is the unmeasured line — and that
        // line must say so of every helper rather than state a version.
        let helpers: String = ProblemReportEnvironment.helperDescription
        XCTAssertTrue(helpers.hasPrefix("llama.cpp b10435 (Metal) · "), helpers)
        for helper in ProblemReportEnvironment.pinnedHelpers {
            XCTAssertTrue(
                helpers.contains(helper.displayName + " not checked yet (pinned " + helper.pinnedVersion + ")"),
                helpers
            )
            XCTAssertFalse(
                helpers.contains(helper.displayName + " " + helper.pinnedVersion),
                "The Helpers line names a pinned version as though it were installed: \(helpers)"
            )
        }
    }

    func testNoteLaunchEmitsMachineAndHelpersOnTheTrail() {
        let store: ProblemReportStore = ProblemReportStore(folderURL: folderURL)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = store
        defer { ActivityTrail.store = previousStore }

        ActivityTrail.noteLaunch()
        ActivityTrail.noteHelpers("llama.cpp b10435 (Metal) · Colima 0.10.3 (Homebrew)")
        let trail: String = store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("Plantoir opened — Plantoir"), trail)
        XCTAssertTrue(trail.contains("running on macOS"), trail)
        XCTAssertTrue(trail.contains("using llama.cpp b10435 (Metal) · Colima 0.10.3 (Homebrew)"), trail)
    }
}
