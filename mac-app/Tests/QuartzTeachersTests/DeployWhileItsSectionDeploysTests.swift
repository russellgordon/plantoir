import XCTest
@testable import QuartzTeachers

/// A deploy refuses while that same section is still being deployed (GitHub
/// #439, decided by Russell 2026-10-04). The contract is
/// `shared-rules.json` → `deployWhileItsSectionDeploys`.
///
/// The launchers' guard itself is `scripts/test_deploy_while_its_section_deploys.py`.
/// This class covers the app's halves:
/// - the window's failure explanation and the assistants' sentences, which
///   say the refusal as itself rather than "did not finish";
/// - a newly set run WAITING for its section's leftover run before it starts
///   its own (`theNewRunWaits`), and what counts as that leftover;
/// - a leftover run never replacing a newer run's outcome record
///   (`scheduledPublishStopped.newerRecordWins`).
///
/// Swaps `ActivityTrail.store` and `ScheduledDeploy.earlierDeployIsWorkingOverride`,
/// which are process-wide: safe only because the scheme runs test classes one
/// at a time (CLAUDE.md, "The mac suite runs its test classes one at a time").
@MainActor
final class DeployWhileItsSectionDeploysTests: XCTestCase {

    // MARK: - Stored properties

    /// A scratch folder whose path holds a space, as the real
    /// "Application Support" does.
    nonisolated(unsafe) private var root: URL = URL(fileURLWithPath: "/")
    nonisolated(unsafe) private var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Set up

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("deploy-while-it-deploys-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("trail"), withIntermediateDirectories: true
        )
        previousTrail = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))
        ScheduledDeploy.earlierDeployIsWorkingOverride = nil
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousTrail
        ScheduledDeploy.earlierDeployIsWorkingOverride = nil
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    // MARK: - The refusal, said as itself

    /// Every `failureExplanationCases` output reaches the window as the
    /// launcher's own first line, and says which assistant sentence it is.
    func testTheLaunchersRefusalIsExplainedInItsOwnWords() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["deployWhileItsSectionDeploys"])
        let cases: [[String: Any]] = try XCTUnwrap(rule["failureExplanationCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 4)
        for testCase in cases {
            let output: String = try XCTUnwrap(testCase["output"] as? String)
            let expected: String = try XCTUnwrap(testCase["expect"] as? String)
            let assistantKey: String = try XCTUnwrap(testCase["assistant"] as? String)
            XCTAssertEqual(FailureExplainer.explanation(in: output), expected)
            let refusal: FailureExplainer.SectionDeployRefusal = try XCTUnwrap(
                FailureExplainer.sectionDeployRefusal(in: output), output
            )
            XCTAssertEqual(refusal.sentence, expected)
            XCTAssertEqual(refusal.byALaterDeploy, assistantKey == "deployRefusedWhileALaterDeployWorks", output)
        }
    }

    /// The markers the app looks for are in every launcher sentence the
    /// contract names, so a launcher sentence reworded in the contract
    /// cannot leave the window saying nothing.
    func testEveryLauncherSentenceCarriesAMarker() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["deployWhileItsSectionDeploys"])
        let sentences: [String: Any] = try XCTUnwrap(rule["sentences"] as? [String: Any])
        let launcher: [String: Any] = try XCTUnwrap(sentences["launcher"] as? [String: Any])
        XCTAssertEqual(launcher.count, 4)
        for (name, value) in launcher {
            let lines: [String] = try XCTUnwrap(value as? [String])
            var found: Bool = false
            for marker in FailureExplainer.sectionDeployRefusalMarkers {
                if lines[0].contains(marker) {
                    found = true
                }
            }
            XCTAssertTrue(found, "\(name): no marker in \(lines[0])")
            XCTAssertEqual(
                lines[0].contains(FailureExplainer.laterDeployMarker), name.hasPrefix("later"),
                "\(name): the later-deploy marker must name exactly the later sentences"
            )
        }
    }

    /// A deploy failure that is NOT this refusal is not mistaken for it.
    func testAnOrdinaryFailureIsNotThisRefusal() {
        XCTAssertNil(FailureExplainer.sectionDeployRefusal(in: "❌ Deploy failed.\nnetwork unreachable"))
        XCTAssertNil(FailureExplainer.sectionDeployRefusal(
            in: "❌ ICS4U section 2 is being deployed right now, so it cannot be previewed until that has finished."
        ))
    }

    /// The assistants say the refusal, for one destination or several, when
    /// every leg that ran was refused this way.
    func testTheAssistantsSayTheRefusal() {
        let later: FailureExplainer.SectionDeployRefusal = FailureExplainer.SectionDeployRefusal(
            byALaterDeploy: true, sentence: "x"
        )
        let another: FailureExplainer.SectionDeployRefusal = FailureExplainer.SectionDeployRefusal(
            byALaterDeploy: false, sentence: "x"
        )
        for destinationCount in [1, 2] {
            let refusedByLater: MultiDestinationDeployRunner.Outcome = MultiDestinationDeployRunner.Outcome(
                anySucceeded: false,
                failedDestinations: [CourseConfiguration.DeployDestination(type: "netlify", path: "")],
                refusedWhileItsSectionDeploys: later
            )
            let saidForLater: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
                course: "ICS4U", section: "2", destinationCount: destinationCount, outcome: refusedByLater
            )
            XCTAssertFalse(saidForLater.succeeded)
            XCTAssertEqual(
                saidForLater.message,
                AssistWording.deployRefusedWhileALaterDeployWorks(course: "ICS4U", section: "2")
            )

            let refusedByAnother: MultiDestinationDeployRunner.Outcome = MultiDestinationDeployRunner.Outcome(
                anySucceeded: false,
                failedDestinations: [CourseConfiguration.DeployDestination(type: "netlify", path: "")],
                refusedWhileItsSectionDeploys: another
            )
            let saidForAnother: AssistSiteWorkResult = MultiDestinationDeployRunner.result(
                course: "ICS4U", section: "2", destinationCount: destinationCount, outcome: refusedByAnother
            )
            XCTAssertEqual(
                saidForAnother.message,
                AssistWording.deployRefusedWhileItsSectionDeploys(course: "ICS4U", section: "2")
            )
        }
    }

    /// The outcome carries the refusal only when EVERY leg that ran was
    /// refused this way: a leg that failed for another reason, or one that
    /// went out, is told the ordinary way.
    func testTheOutcomeCarriesTheRefusalOnlyWhenEveryLegWasRefused() {
        let refusal: FailureExplainer.SectionDeployRefusal = FailureExplainer.SectionDeployRefusal(
            byALaterDeploy: true, sentence: "x"
        )
        var refusedBuild: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "netlify", path: "")
        )
        refusedBuild.isFinished = true
        refusedBuild.buildFailed = true
        refusedBuild.refusedWhileItsSectionDeploys = refusal

        var refusedDeploy: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        )
        refusedDeploy.isFinished = true
        refusedDeploy.refusedWhileItsSectionDeploys = refusal

        var failedOtherwise: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        )
        failedOtherwise.isFinished = true

        var wentOut: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "cloudflare_pages", path: "")
        )
        wentOut.isFinished = true
        wentOut.succeeded = true

        let runner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()
        runner.legs = [refusedBuild]
        XCTAssertEqual(runner.outcome.refusedWhileItsSectionDeploys, refusal)
        runner.legs = [refusedDeploy, refusedDeploy]
        XCTAssertEqual(runner.outcome.refusedWhileItsSectionDeploys, refusal)
        runner.legs = [refusedDeploy, failedOtherwise]
        XCTAssertNil(runner.outcome.refusedWhileItsSectionDeploys)
        runner.legs = [refusedDeploy, wentOut]
        XCTAssertNil(runner.outcome.refusedWhileItsSectionDeploys)
    }

    /// Both assistant sentences are in the generated wording, under the keys
    /// the contract's cases name, and say nothing about the machinery.
    func testTheAssistantSentencesAreInTheWording() throws {
        let wording: [String: Any] = try XCTUnwrap(AssistContract.wording()["wording"] as? [String: Any])
        for key in ["deployRefusedWhileALaterDeployWorks", "deployRefusedWhileItsSectionDeploys"] {
            let sentence: String = try XCTUnwrap(wording[key] as? String, key)
            for word in ["script", "launcher", "container", "Docker", "toolchain", "publish"] {
                XCTAssertFalse(sentence.lowercased().contains(word.lowercased()), "\(key) says \(word)")
            }
        }
    }

    // MARK: - The new run waits for its leftover run

    /// Nothing working, which is nearly always: no wait, no line.
    func testTheRunGoesAheadAtOnceWhenNothingIsWorking() {
        var pauses: Int = 0
        let answer: ScheduledDeploy.EarlierDeployWait = ScheduledDeploy.waitForTheEarlierDeploy(
            script: "/x.sh",
            now: { () -> Date in return Date(timeIntervalSince1970: 0) },
            pause: { (seconds: TimeInterval) -> Void in pauses += 1 },
            isWorking: { (script: String) -> Bool in return false }
        )
        XCTAssertEqual(answer, .goAhead(waited: 0, didWait: false))
        XCTAssertEqual(pauses, 0)
    }

    /// The leftover finishes during the wait: the run goes ahead, and says it
    /// waited.
    func testTheRunGoesAheadOnceTheEarlierDeployHasFinished() {
        var clock: TimeInterval = 0
        var looks: Int = 0
        let answer: ScheduledDeploy.EarlierDeployWait = ScheduledDeploy.waitForTheEarlierDeploy(
            script: "/x.sh",
            now: { () -> Date in return Date(timeIntervalSince1970: clock) },
            pause: { (seconds: TimeInterval) -> Void in clock += seconds },
            isWorking: { (script: String) -> Bool in
                looks += 1
                return looks <= 3
            }
        )
        XCTAssertEqual(answer, .goAhead(waited: 45, didWait: true))
    }

    /// Still working after thirty minutes, and not one look sooner: the run
    /// stands down.
    func testTheRunStandsDownAfterThirtyMinutes() {
        XCTAssertEqual(ScheduledDeploy.longestWaitForTheEarlierDeploy, 30 * 60)
        var clock: TimeInterval = 0
        var lastLookStillWaiting: TimeInterval = -1
        let answer: ScheduledDeploy.EarlierDeployWait = ScheduledDeploy.waitForTheEarlierDeploy(
            script: "/x.sh",
            now: { () -> Date in return Date(timeIntervalSince1970: clock) },
            pause: { (seconds: TimeInterval) -> Void in
                lastLookStillWaiting = clock
                clock += seconds
            },
            isWorking: { (script: String) -> Bool in return true }
        )
        XCTAssertEqual(answer, .standDown(waited: 1800))
        XCTAssertEqual(lastLookStillWaiting, 1785, "it gave up before thirty minutes")
    }

    /// The stand-down kind asks for the teacher's attention, and its sentence
    /// names no destination (nothing was attempted).
    func testTheStandDownAsksForAttentionAndNamesNoDestination() {
        XCTAssertTrue(ScheduledPublishOutcome.Kind.earlierDeployStillWorking.needsAttention)
        let sentence: String = ScheduledPublishOutcome.sentence(
            for: ScheduledPublishOutcome.Stopped(
                kind: .earlierDeployStillWorking, destination: "Netlify", when: Date()
            ),
            course: "ICS4U",
            section: 2
        )
        XCTAssertFalse(sentence.contains("Netlify"))
        XCTAssertTrue(sentence.contains("thirty minutes"))
    }

    /// What counts as the leftover: a shell running THIS script as its
    /// program, the path with a space being one argument. Not `bash -x`, not
    /// an editor or a pager, not the app's own line, not another script.
    func testOnlyTheScriptRunningAsItsProgramCounts() throws {
        let script: URL = root.appendingPathComponent(
            "scheduled/ca.russellgordon.Plantoir.deploy.ICS4U.section2.abcd1234.sh"
        )
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "#!/bin/bash\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        let other: URL = root.appendingPathComponent(
            "scheduled/ca.russellgordon.Plantoir.deploy.ICS4U.section12.abcd1234.sh"
        )
        let path: String = script.path
        XCTAssertTrue(path.contains("Application Support"))

        XCTAssertTrue(ScheduledDeploy.isTheRunsScript(arguments: ["/bin/bash", path], script: path))
        XCTAssertTrue(ScheduledDeploy.isTheRunsScript(arguments: ["bash", path], script: path))
        XCTAssertFalse(ScheduledDeploy.isTheRunsScript(arguments: ["/bin/bash", "-x", path], script: path))
        XCTAssertFalse(ScheduledDeploy.isTheRunsScript(arguments: ["/usr/bin/vim", path], script: path))
        XCTAssertFalse(ScheduledDeploy.isTheRunsScript(arguments: ["/usr/bin/less", path], script: path))
        XCTAssertFalse(ScheduledDeploy.isTheRunsScript(
            arguments: [
                "/Applications/Plantoir.app/Contents/MacOS/Plantoir", "--run-scheduled-deploy", path,
                "--scheduled-section", "ICS4U", "2"
            ],
            script: path
        ))
        XCTAssertFalse(ScheduledDeploy.isTheRunsScript(arguments: ["/bin/bash", other.path], script: path))
        XCTAssertFalse(ScheduledDeploy.isTheRunsScript(arguments: ["/bin/bash"], script: path))
        XCTAssertFalse(ScheduledDeploy.isTheRunsScript(arguments: [], script: path))
        // The path split at its space, as a reader that joins words would see
        // it, is not the script.
        let split: [String] = ["/bin/bash"] + path.components(separatedBy: " ")
        XCTAssertFalse(ScheduledDeploy.isTheRunsScript(arguments: split, script: path))
    }

    /// The real process table: a shell running the script, started here, is
    /// found; once it has ended it is not.
    func testALeftoverRunIsFoundInTheRealProcessTable() throws {
        let script: URL = root.appendingPathComponent(
            "scheduled/ca.russellgordon.Plantoir.deploy.ICS4U.section2.abcd1234.sh"
        )
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "#!/bin/bash\n/bin/sleep 30\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertFalse(ScheduledDeploy.anEarlierDeployIsWorking(script: script.path))

        let leftover: Process = Process()
        leftover.executableURL = URL(fileURLWithPath: "/bin/bash")
        leftover.arguments = [script.path]
        try leftover.run()
        addTeardownBlock {
            if leftover.isRunning {
                leftover.terminate()
            }
        }
        var found: Bool = false
        for _ in 0..<50 {
            if ScheduledDeploy.anEarlierDeployIsWorking(script: script.path) {
                found = true
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(found, "a shell running the script was not seen")

        leftover.terminate()
        leftover.waitUntilExit()
        XCTAssertFalse(ScheduledDeploy.anEarlierDeployIsWorking(script: script.path))
    }

    /// `runScheduled` never returns, so its ORDER is read from the source:
    /// the lateness check, then this wait, then #156's wait for the course;
    /// and the wait's stand-down records `earlierDeployStillWorking`.
    func testTheRunWaitsForItsEarlierDeployBeforeTheCourse() throws {
        let body: String = try DeployWhileItsSectionDeploysTests.runScheduledSource()
        let lateness: Range<String.Index> = try XCTUnwrap(body.range(of: "ScheduledDeployLateness.mayStillRun("))
        let earlier: Range<String.Index> = try XCTUnwrap(body.range(of: "waitForTheEarlierDeploy(script: script)"))
        let course: Range<String.Index> = try XCTUnwrap(body.range(of: "waitForTheCourse("))
        XCTAssertLessThan(lateness.lowerBound, earlier.lowerBound)
        XCTAssertLessThan(earlier.lowerBound, course.lowerBound)
        // Asked whether or not the plist names a section (review finding 8):
        // nothing between the lateness check and the wait makes it depend on one.
        let beforeTheWait: String = String(body[lateness.upperBound..<earlier.lowerBound])
        XCTAssertFalse(beforeTheWait.contains("if let section"), beforeTheWait)
        let branch: String = String(body[earlier.lowerBound..<course.lowerBound])
        XCTAssertTrue(branch.contains("kind: .earlierDeployStillWorking"))
        XCTAssertTrue(branch.contains(".scheduledDeployWaitedForItsEarlierDeploy"))
    }

    // MARK: - A leftover run never replaces a newer record

    /// The wrapper's completion lines, run under `/bin/bash` in a folder whose
    /// path has a space: with a newer record in place it is left as it is and
    /// the partial file goes; with none, the partial record moves into place
    /// whole (`scheduledPublishStopped.newerRecordWins`).
    func testTheCompletionLinesNeverReplaceANewerRecord() throws {
        let folder: URL = root.appendingPathComponent("scheduled/stopped")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let record: URL = folder.appendingPathComponent("ICS4U-2-abcd1234")
        let partial: URL = root.appendingPathComponent("scheduled/.partial ICS4U-2-abcd1234")
        var lines: [String] = [
            "/bin/echo \(ScheduledDeploy.shellQuoted(ScheduledPublishOutcome.Kind.succeeded.rawValue))"
            + " > \(ScheduledDeploy.shellQuoted(partial.path))"
        ]
        for line in ScheduledDeploy.recordCompletionLines(
            indentedBy: "", destination: "Netlify", temporaryPath: partial.path, recordPath: record.path
        ) {
            lines.append(line)
        }
        let script: URL = root.appendingPathComponent("complete.sh")
        try (lines.joined(separator: "\n") + "\n").write(to: script, atomically: true, encoding: .utf8)

        let newer: String = ScheduledPublishOutcome.Kind.earlierDeployStillWorking.rawValue + "\nnothing\n"
        try newer.write(to: record, atomically: true, encoding: .utf8)
        try DeployWhileItsSectionDeploysTests.runInBash(script)
        XCTAssertEqual(try String(contentsOf: record, encoding: .utf8), newer, "a newer record was replaced")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path), "the partial record was left behind")

        try FileManager.default.removeItem(at: record)
        try DeployWhileItsSectionDeploysTests.runInBash(script)
        XCTAssertEqual(
            try String(contentsOf: record, encoding: .utf8),
            ScheduledPublishOutcome.Kind.succeeded.rawValue + "\nNetlify\n"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    // MARK: - Helpers

    static func runInBash(_ script: URL) throws {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    /// `runScheduled`'s body, from its signature to the next MARK.
    static func runScheduledSource() throws -> String {
        var sourceURL: URL?
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: ActivityTrailWiringTests.productSourceFolderURL()) {
            if fileURL.lastPathComponent == "ScheduledDeploy.swift" {
                sourceURL = fileURL
            }
        }
        let source: String = try String(contentsOf: try XCTUnwrap(sourceURL), encoding: .utf8)
        let start: String.Index = try XCTUnwrap(source.range(of: "nonisolated static func runScheduled(")?.lowerBound)
        let end: String.Index = try XCTUnwrap(
            source.range(of: "// MARK: - Waiting for this section's earlier deploy (#439)", range: start..<source.endIndex)?
                .lowerBound
        )
        return String(source[start..<end])
    }
}
