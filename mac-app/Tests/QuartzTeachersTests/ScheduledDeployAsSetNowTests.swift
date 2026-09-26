import XCTest
@testable import QuartzTeachers

/// A scheduled deploy goes where the course deploys WHEN IT RUNS, not where
/// it deployed when it was set (GitHub #323).
///
/// Until #323 the wrapper launchd runs had every destination's `deploy.sh`
/// arguments written into it at scheduling, so a course moved to a folder
/// afterwards published to the OLD place at half six and reported success.
/// Now the run reads the course's settings after its lateness check and its
/// wait for the course, re-applies everything the schedule sheet refuses, and
/// writes its wrapper afresh — or stands down.
///
/// `runScheduled` never returns, so the run's pieces are tested one by one:
/// the reading (`readAtTheRun`), whether the job still stands, the write, the
/// decision (`whatTheRunDoes`), the trail line, and the order they are called
/// in (a source scan). Wrappers are EXECUTED against stand-in launchers that
/// record what `deploy.sh` was handed.
@MainActor
final class ScheduledDeployAsSetNowTests: XCTestCase {

    // MARK: - Stored properties

    private var root: URL = FileManager.default.temporaryDirectory
    private var home: URL = FileManager.default.temporaryDirectory
    private var workspace: URL = FileManager.default.temporaryDirectory
    private var deployCalls: URL = FileManager.default.temporaryDirectory
    private var previousStore: ProblemReportStore = ActivityTrail.store

    // MARK: - Computed properties

    private var courseURL: URL {
        return workspace.appendingPathComponent("courses/ICS3U")
    }

    private var configURL: URL {
        return courseURL.appendingPathComponent("course_config.json")
    }

    private var section: (courseDirectory: URL, courseCode: String, sectionNumber: Int) {
        return (courseDirectory: courseURL, courseCode: "ICS3U", sectionNumber: 1)
    }

    private var label: String {
        return ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspace)
    }

    /// A folder a course can deploy into.
    private var folder: URL {
        return root.appendingPathComponent("published-here")
    }

    // MARK: - Functions

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("as-set-now-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        workspace = root.appendingPathComponent("workspace")
        deployCalls = root.appendingPathComponent("deploy-calls.txt")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = home.appendingPathComponent("Library/LaunchAgents")
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            home.appendingPathComponent("Library/Application Support/Plantoir/scheduled")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/LaunchAgents"), withIntermediateDirectories: true
        )
        try writeStubLaunchers(deployExit: 0)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
    }

    /// `deploy.sh` writes each call's arguments on a line of its own, then
    /// exits with `deployExit`; `preview.sh` builds nothing and succeeds.
    private func writeStubLaunchers(deployExit: Int32) throws {
        let deployScript: String = "#!/bin/bash\n"
            + "echo \"$*\" >> \(HelperPrograms.shellQuoted(deployCalls.path))\n"
            + "exit \(deployExit)\n"
        for (name, script) in [("preview.sh", "#!/bin/bash\nexit 0\n"), ("deploy.sh", deployScript)] {
            let url: URL = workspace.appendingPathComponent(name)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    /// The course's settings file, as Course Settings would write it.
    private func writeSettings(_ extra: [String: Any]) throws {
        var values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "per_section_folders": ["All Classes"],
        ]
        for (key, value) in extra {
            values[key] = value
        }
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
            .write(to: configURL, options: [.atomic])
    }

    /// The marker `deploy.py` leaves the first time a section goes out to a
    /// destination type.
    private func markDeployedBefore(to folderName: String = ".netlify_sites") throws {
        let marker: URL = courseURL.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        try "{}".write(to: marker.appendingPathComponent("section1.json"), atomically: true, encoding: .utf8)
    }

    private func course() throws -> Course {
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: try CourseConfiguration(contentsOf: configURL))
    }

    /// Schedules the real way, with launchctl stood in for.
    private func schedule(accountID: String = "") throws {
        let problem: String? = ScheduledDeploy.scheduleDeploy(
            course: try course(), sectionNumber: 1, when: Date().addingTimeInterval(86_400),
            workspaceURL: workspace, cloudflareAccountID: accountID, runner: FakeLaunchControl()
        )
        XCTAssertNil(problem)
    }

    /// Runs a wrapper and returns the lines `deploy.sh` was called with.
    @discardableResult
    private func execute(_ command: String) throws -> [String] {
        try? FileManager.default.removeItem(at: deployCalls)
        let scriptURL: URL = root.appendingPathComponent("run-\(UUID().uuidString).sh")
        try command.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard let text = try? String(contentsOf: deployCalls, encoding: .utf8) else {
            return []
        }
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            lines.append(line)
        }
        return lines
    }

    // MARK: - The reading

    /// The issue: scheduled to Netlify, then moved to a folder. Before #323
    /// the wrapper still read `deploy.sh ICS3U 1 --non-interactive`.
    func testTheRunDeploysWhereTheCourseDeploysNow() throws {
        try writeSettings([:])
        try markDeployedBefore()
        try schedule()
        try writeSettings(["deploy_target": "local_folder", "deploy_folder_path": folder.path])

        let reading: ScheduledDeploy.RunReading = ScheduledDeploy.readAtTheRun(
            label: label, section: section, scheduledTo: ["Netlify"], cloudflareAccountID: "", homeFolder: home
        )
        guard case .deploy(let command, let destinations, _) = reading else {
            return XCTFail("should go ahead: \(reading)")
        }
        XCTAssertEqual(destinations, [folder.path])
        let calls: [String] = try execute(command)
        XCTAssertEqual(calls, ["ICS3U 1 --non-interactive --to-folder \(folder.path)"])
    }

    /// The fail-open the refusals close: `publish_to_cloudflare` never
    /// refuses a first deploy, so reading the destination alone would publish
    /// to a guessed project.
    func testANeverDeployedCloudflareDestinationStandsDown() throws {
        try writeSettings([:])
        try markDeployedBefore()
        try schedule()
        try writeSettings(["deploy_target": "cloudflare_pages"])

        let reading: ScheduledDeploy.RunReading = ScheduledDeploy.readAtTheRun(
            label: label, section: section, scheduledTo: ["Netlify"],
            cloudflareAccountID: "0123456789abcdef0123456789abcdef", homeFolder: home
        )
        XCTAssertEqual(reading, .refuse(
            .refused(.neverDeployed(destination: "Cloudflare Pages")),
            destinationsNow: ["Cloudflare Pages"], scheduledTo: ["Netlify"]
        ))
    }

    /// `PLANTOIR_SCHEDULED_TO` is a note of what the teacher was told, and
    /// never where the deploy goes.
    func testWhereItWasScheduledIsNeverUsedToDecide() throws {
        try writeSettings([:])
        try markDeployedBefore()

        let reading: ScheduledDeploy.RunReading = ScheduledDeploy.readAtTheRun(
            label: label, section: section, scheduledTo: [folder.path], cloudflareAccountID: "", homeFolder: home
        )
        guard case .deploy(let command, let destinations, let scheduledTo) = reading else {
            return XCTFail("should go ahead: \(reading)")
        }
        XCTAssertEqual(destinations, ["Netlify"])
        XCTAssertEqual(scheduledTo, [folder.path])
        XCTAssertEqual(try execute(command), ["ICS3U 1 --non-interactive"])
    }

    func testUnreadableSettingsStandDown() throws {
        try "{ not json".write(to: configURL, atomically: true, encoding: .utf8)
        let reading: ScheduledDeploy.RunReading = ScheduledDeploy.readAtTheRun(
            label: label, section: section, scheduledTo: ["Netlify"], cloudflareAccountID: "", homeFolder: home
        )
        XCTAssertEqual(reading, .refuse(.settingsCouldNotBeRead, destinationsNow: [], scheduledTo: ["Netlify"]))
    }

    /// Nothing changed: the wrapper written at the run is byte for byte the
    /// one written at scheduling. `deployPlan` really is the one path (plan
    /// review L5).
    func testAnUnchangedCourseGetsTheSameWrapperItWasScheduledWith() throws {
        try writeSettings([:])
        try markDeployedBefore()
        try schedule()
        let onDisk: String = try String(contentsOf: ScheduledDeploy.scriptURL(label: label), encoding: .utf8)

        let reading: ScheduledDeploy.RunReading = ScheduledDeploy.readAtTheRun(
            label: label, section: section, scheduledTo: ["Netlify"], cloudflareAccountID: ""
        )
        guard case .deploy(let command, _, _) = reading else {
            return XCTFail("should go ahead: \(reading)")
        }
        XCTAssertEqual(command, onDisk)
    }

    /// A job set before #237 keeps its OLD name for everything launchd and
    /// the app find it by, and files its record under the FOLDER's id — never
    /// `ICS3U-section1..txt`, a third spelling no badge reads.
    func testAnOldLabelKeepsItsOwnNamesWhenTheWrapperIsWrittenAgain() throws {
        try writeSettings([:])
        try markDeployedBefore()
        let legacy: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1)

        let reading: ScheduledDeploy.RunReading = ScheduledDeploy.readAtTheRun(
            label: legacy, section: section, scheduledTo: nil, cloudflareAccountID: "", homeFolder: home
        )
        guard case .deploy(let command, _, _) = reading else {
            return XCTFail("should go ahead: \(reading)")
        }
        XCTAssertTrue(command.contains(ScheduledDeploy.plistURL(label: legacy).path))
        XCTAssertTrue(command.contains(ScheduledDeploy.successSentinelURL(label: legacy, inHomeFolder: home).path))
        let folderID: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: workspace.path)
        XCTAssertTrue(command.contains(ScheduledPublishOutcome.recordURL(
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: folderID
        ).path))
        XCTAssertFalse(command.contains("ICS3U-section1..txt"))
    }

    /// The plan review's H1: a job set on v1.3.1 whose old-named record says
    /// last week SUCCEEDED. Tonight's run fails. Without clearing the old
    /// record first, `fileUnderTheFolder` moves last week's success over
    /// tonight's failure.
    func testAnOldJobsRunIsNotReportedAsLastWeeksSuccess() throws {
        try writeSettings([:])
        try markDeployedBefore()
        try writeStubLaunchers(deployExit: 1)
        let legacy: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1)
        let oldRecord: URL = ScheduledPublishOutcome.legacyRecordURL(inHomeFolder: home, course: "ICS3U", section: 1)
        try FileManager.default.createDirectory(at: oldRecord.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "succeeded\nNetlify\n".write(to: oldRecord, atomically: true, encoding: .utf8)

        let reading: ScheduledDeploy.RunReading = ScheduledDeploy.readAtTheRun(
            label: legacy, section: section, scheduledTo: nil, cloudflareAccountID: "", homeFolder: home
        )
        guard case .deploy(let command, _, _) = reading else {
            return XCTFail("should go ahead: \(reading)")
        }
        ScheduledDeploy.clearTheOldNamedRecord(label: legacy, section: section, homeFolder: home)
        try execute(command)
        let folderID: String = ScheduledDeploy.folderIDForRun(label: legacy, section: section)
        ScheduledPublishOutcome.fileUnderTheFolder(
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: folderID, jobLabel: legacy
        )

        let stopped: ScheduledPublishOutcome.Stopped? = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: folderID
        )
        XCTAssertEqual(stopped?.kind, .didNotFinish)
    }

    // MARK: - What scheduling records

    func testSchedulingRecordsWhereItWasSetToDeploy() throws {
        try writeSettings(["deploy_target": "local_folder", "deploy_folder_path": folder.path])
        try schedule()
        let plistData: Data = try Data(contentsOf: ScheduledDeploy.plistURL(label: label))
        let plist: [String: Any] = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let environment: [String: String] = try XCTUnwrap(plist["EnvironmentVariables"] as? [String: String])
        XCTAssertEqual(ScheduledDeploy.scheduledDestinations(from: environment), [folder.path])
    }

    func testAMissingOrUnreadableNoteMeansNothingWasRecorded() {
        XCTAssertNil(ScheduledDeploy.scheduledDestinations(from: [:]))
        XCTAssertNil(ScheduledDeploy.scheduledDestinations(from: [ScheduledDeploy.scheduledToKey: "Netlify"]))
    }

    // MARK: - Does the job still stand? (plan review M1)

    func testAJobCancelledWhileTheRunWaitedNoLongerStands() throws {
        try writeSettings([:])
        try markDeployedBefore()
        try schedule()
        let plistURL: URL = ScheduledDeploy.plistURL(label: label)
        let moment: Date = try XCTUnwrap(ScheduledDeploy.agent(readingPlistAt: plistURL)?.scheduledFor)
        let stamp: String = ISO8601DateFormatter().string(from: moment)

        XCTAssertTrue(ScheduledDeploy.jobStillStands(label: label, environment: [ScheduledDeploy.scheduledForKey: stamp]))
        XCTAssertTrue(ScheduledDeploy.jobStillStands(label: label, environment: [:]))
        let other: String = ISO8601DateFormatter().string(from: moment.addingTimeInterval(3600))
        XCTAssertFalse(
            ScheduledDeploy.jobStillStands(label: label, environment: [ScheduledDeploy.scheduledForKey: other]),
            "scheduled again under the same name for another moment"
        )
        try FileManager.default.removeItem(at: plistURL)
        XCTAssertFalse(ScheduledDeploy.jobStillStands(label: label, environment: [ScheduledDeploy.scheduledForKey: stamp]))
    }

    /// Write-if-exists: a wrapper a cancel deleted is not brought back.
    func testTheRunsWrapperIsWrittenOnlyOverOneStillThere() throws {
        let scriptURL: URL = root.appendingPathComponent("job.sh")
        XCTAssertEqual(ScheduledDeploy.writeTheRunsWrapper("#!/bin/bash\n", to: scriptURL), .wasGone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptURL.path))
        try "old".write(to: scriptURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(ScheduledDeploy.writeTheRunsWrapper("new", to: scriptURL), .written)
        XCTAssertEqual(try String(contentsOf: scriptURL, encoding: .utf8), "new")
    }

    // MARK: - The decision (plan review M2)

    /// The only way to `.run` is a wrapper written from the settings just
    /// read: nothing runs the wrapper left from scheduling.
    func testTheRunNeverRunsTheWrapperItWasScheduledWith() {
        let goAhead: ScheduledDeploy.RunReading = .deploy(command: "x", destinations: ["Netlify"], scheduledTo: nil)
        let refused: ScheduledDeploy.RunReading = .refuse(
            .refused(.neverDeployed(destination: "Netlify")), destinationsNow: ["Netlify"], scheduledTo: nil
        )
        XCTAssertEqual(ScheduledDeploy.whatTheRunDoes(reading: goAhead, jobStillStands: true, wrapper: .written), .run)
        XCTAssertEqual(
            ScheduledDeploy.whatTheRunDoes(reading: goAhead, jobStillStands: true, wrapper: nil),
            .standDown(.wrapperCouldNotBeWritten)
        )
        XCTAssertEqual(
            ScheduledDeploy.whatTheRunDoes(reading: goAhead, jobStillStands: true, wrapper: .failed),
            .standDown(.wrapperCouldNotBeWritten)
        )
        XCTAssertEqual(ScheduledDeploy.whatTheRunDoes(reading: goAhead, jobStillStands: true, wrapper: .wasGone), .leaveQuietly)
        XCTAssertEqual(ScheduledDeploy.whatTheRunDoes(reading: goAhead, jobStillStands: false, wrapper: .written), .leaveQuietly)
        XCTAssertEqual(
            ScheduledDeploy.whatTheRunDoes(reading: refused, jobStillStands: true, wrapper: nil),
            .standDown(.refused(.neverDeployed(destination: "Netlify")))
        )
        XCTAssertEqual(ScheduledDeploy.whatTheRunDoes(reading: refused, jobStillStands: false, wrapper: nil), .leaveQuietly)
    }

    // MARK: - The trail

    func testTheChangeIsNotedOnlyWhenItChanged() {
        let same: ScheduledDeploy.RunReading = .deploy(command: "x", destinations: ["Netlify"], scheduledTo: ["Netlify"])
        XCTAssertNil(ScheduledDeploy.trailLineAtTheRun(step: .run, reading: same))
        let old: ScheduledDeploy.RunReading = .deploy(command: "x", destinations: ["Netlify"], scheduledTo: nil)
        XCTAssertNil(ScheduledDeploy.trailLineAtTheRun(step: .run, reading: old))
        XCTAssertNil(ScheduledDeploy.trailLineAtTheRun(step: .leaveQuietly, reading: same))

        let moved: ScheduledDeploy.RunReading = .deploy(command: "x", destinations: ["/f"], scheduledTo: ["Netlify"])
        XCTAssertEqual(
            ScheduledDeploy.trailLineAtTheRun(step: .run, reading: moved),
            "a scheduled publish was set to deploy to Netlify; the course deploys to /f now, so it is deploying there"
        )
        let refusal: ScheduledDeploy.RunRefusal = .refused(.neverDeployed(destination: "Cloudflare Pages"))
        let refused: ScheduledDeploy.RunReading = .refuse(refusal, destinationsNow: ["Cloudflare Pages"], scheduledTo: ["Netlify"])
        XCTAssertEqual(
            ScheduledDeploy.trailLineAtTheRun(step: .standDown(refusal), reading: refused),
            "a scheduled publish could not deploy the way the course is set now (it has never been deployed to "
                + "Cloudflare Pages, and the first deploy there asks what to call the website); it was set to "
                + "deploy to Netlify, and the course deploys to Cloudflare Pages now"
        )
        let unchanged: ScheduledDeploy.RunReading = .refuse(refusal, destinationsNow: ["Netlify"], scheduledTo: ["Netlify"])
        XCTAssertFalse(
            ScheduledDeploy.trailLineAtTheRun(step: .standDown(refusal), reading: unchanged)?.contains("set to deploy to") ?? true
        )
    }

    /// The stand-down's record carries the reason, and the sentence is the
    /// contract's with {reason} filled from it.
    func testTheStandDownSentenceCarriesTheReason() throws {
        let reason: String = ScheduledDeployRefusal.neverDeployed(destination: "Netlify").reasonClause
        let sentence: String = ScheduledPublishOutcome.sentence(
            for: ScheduledPublishOutcome.Stopped(kind: .couldNotRunAsSetNow, destination: reason, when: Date()),
            course: "ICS3U", section: 1
        )
        let template: String = try XCTUnwrap(
            (try SharedRulesContractTests.section("scheduledPublishStopped")["sentences"] as? [String: String])?["couldNotRunAsSetNow"]
        )
        XCTAssertEqual(
            sentence,
            template.replacingOccurrences(of: "{course}", with: "ICS3U")
                .replacingOccurrences(of: "{section}", with: "1")
                .replacingOccurrences(of: "{reason}", with: reason)
        )
        XCTAssertTrue(ScheduledPublishOutcome.Kind.couldNotRunAsSetNow.needsAttention)
    }

    // MARK: - The order the run does things in

    /// Source scan of `runScheduled`, which never returns: the lateness check,
    /// then the wait, then the settings, then the run; a stand-down for the
    /// settings releases the leases first and records the REASON; the
    /// old-named record is cleared before the wrapper runs.
    func testTheRunReadsTheSettingsAfterWaitingAndBeforeRunning() throws {
        var sourceURL: URL?
        for fileURL in ActivityTrailWiringTests.swiftFiles(under: ActivityTrailWiringTests.productSourceFolderURL()) {
            if fileURL.lastPathComponent == "ScheduledDeploy.swift" {
                sourceURL = fileURL
            }
        }
        let source: String = try String(contentsOf: try XCTUnwrap(sourceURL), encoding: .utf8)
        let start: String.Index = try XCTUnwrap(source.range(of: "nonisolated static func runScheduled(")?.lowerBound)
        let end: String.Index = try XCTUnwrap(
            source.range(of: "// MARK: - Waiting for another build of the course (#156)", range: start..<source.endIndex)?.lowerBound
        )
        let body: String = String(source[start..<end])
        func position(_ needle: String, after: String.Index? = nil) throws -> String.Index {
            let from: String.Index = after ?? body.startIndex
            return try XCTUnwrap(body.range(of: needle, range: from..<body.endIndex)?.lowerBound, "no \(needle)")
        }
        let lateness: String.Index = try position("ScheduledDeployLateness.mayStillRun(")
        let wait: String.Index = try position("waitForTheCourse(")
        let read: String.Index = try position("readAtTheRun(")
        let clear: String.Index = try position("clearTheOldNamedRecord(")
        let run: String.Index = try position("try process.run()")
        XCTAssertLessThan(lateness, wait)
        XCTAssertLessThan(wait, read)
        XCTAssertLessThan(read, clear)
        XCTAssertLessThan(clear, run)

        let standDownBranch: String.Index = try position("case .standDown(let refusal):", after: read)
        let release: String.Index = try position("WorkLeaseFiles.remove(at: lease)", after: standDownBranch)
        let standDown: String.Index = try position("standDown(", after: release)
        XCTAssertLessThan(standDown, run)
        XCTAssertTrue(body.contains("kind: .couldNotRunAsSetNow, reason: refusal.reasonClause"))
    }

    // MARK: - The contract: scheduledDeployCancellation.theDestination

    /// Every case, played through the run's own reading; a case that goes
    /// ahead is EXECUTED and `deploy.sh`'s arguments read back as types.
    func testEveryTheDestinationCaseHolds() throws {
        let cancellation: [String: Any] = try SharedRulesContractTests.section("scheduledDeployCancellation")
        let rule: [String: Any] = try XCTUnwrap(cancellation["theDestination"] as? [String: Any])
        let clauses: [String: String] = try XCTUnwrap(rule["reasonClauses"] as? [String: String])
        let wording: [String: String] = try XCTUnwrap(rule["wording"] as? [String: String])
        XCTAssertEqual(wording["settingsCouldNotBeRead"], ScheduledDeployWording.settingsCouldNotBeRead)
        XCTAssertEqual(wording["wrapperCouldNotBeWritten"], ScheduledDeployWording.wrapperCouldNotBeWritten)
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 12)

        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            try? FileManager.default.removeItem(at: courseURL)
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let now: [String: Any] = try XCTUnwrap(testCase["now"] as? [String: Any])
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])

            var settings: [String: Any] = [:]
            if let target = now["target"] as? String {
                settings["deploy_target"] = target
                if target == "local_folder" {
                    settings["deploy_folder_path"] = (now["folderProblem"] as? Bool == true)
                        ? root.appendingPathComponent("no-such-folder").path : folder.path
                }
            }
            if let additional = now["additionalTarget"] as? String {
                var entry: [String: Any] = ["type": additional]
                if additional == "local_folder" {
                    entry["path"] = (now["additionalFolderProblem"] as? Bool == true)
                        ? root.appendingPathComponent("no-such-additional").path : folder.path
                }
                settings["additional_deploy_targets"] = [entry]
                if additional != "local_folder", now["additionalTargetHasDeployedBefore"] as? Bool ?? true {
                    try markDeployedBefore(to: additional == "cloudflare_pages" ? ".cloudflare_sites" : ".netlify_sites")
                }
            }
            if now["keptForReference"] as? Bool == true {
                settings["kept_for_reference"] = true
            }
            try writeSettings(settings)
            if now["unreadable"] as? Bool == true {
                try "{ not json".write(to: configURL, atomically: true, encoding: .utf8)
            }
            if now["hasDeployedBefore"] as? Bool == true {
                try markDeployedBefore()
            }
            if now["folderGone"] as? Bool == true {
                try FileManager.default.removeItem(at: folder)
            }
            var scheduledTo: [String]?
            if let listed = testCase["scheduledTo"] as? [String] {
                var filled: [String] = []
                for description in listed {
                    filled.append(description.replacingOccurrences(of: "{folder}", with: folder.path))
                }
                scheduledTo = filled
            }

            let reading: ScheduledDeploy.RunReading = ScheduledDeploy.readAtTheRun(
                label: label, section: section, scheduledTo: scheduledTo,
                cloudflareAccountID: now["cloudflareAccountID"] as? String ?? "", homeFolder: home
            )
            var step: ScheduledDeploy.RunStep = .run
            if case .refuse(let refusal, _, _) = reading {
                step = .standDown(refusal)
            }

            if let deploysTo = expect["deploysTo"] as? [String] {
                guard case .deploy(let command, _, _) = reading else {
                    XCTFail("\(name): should go ahead, but \(reading)")
                    continue
                }
                var types: [String] = []
                for call in try execute(command) {
                    if call.contains("--to-folder") {
                        types.append("local_folder")
                    } else if call.contains("--target cloudflare") {
                        types.append("cloudflare_pages")
                    } else {
                        types.append("netlify")
                    }
                }
                XCTAssertEqual(types, deploysTo, name)
            } else {
                guard case .refuse(let refusal, _, _) = reading else {
                    XCTFail("\(name): should stand down, but \(reading)")
                    continue
                }
                let key: String = try XCTUnwrap(expect["refusal"] as? String, name)
                switch refusal {
                case .settingsCouldNotBeRead:
                    XCTAssertEqual(key, "settingsCouldNotBeRead", name)
                case .wrapperCouldNotBeWritten:
                    XCTFail("\(name): no case expects a failed write")
                case .refused(let why):
                    XCTAssertEqual(why.contractKey, key, name)
                    let clause: String = try XCTUnwrap(clauses[key], "\(name): no reason clause for \(key)")
                    XCTAssertEqual(
                        why.reasonClause,
                        clause.replacingOccurrences(of: "{destination}", with: expect["destinationNamed"] as? String ?? ""),
                        name
                    )
                }
            }
            let notes: Bool = ScheduledDeploy.trailLineAtTheRun(step: step, reading: reading)?
                .contains("set to deploy to") ?? false
            XCTAssertEqual(notes, try XCTUnwrap(expect["notesTheChange"] as? Bool), name)
        }
    }
}

