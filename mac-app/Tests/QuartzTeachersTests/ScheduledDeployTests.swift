import XCTest
@testable import QuartzTeachers

/// "Deploy tomorrow's class at 6:30 AM" — the launchd agent that carries it
/// out, and every refusal that keeps a scheduled deploy from waiting on a
/// question nobody is there to answer.
///
/// Nothing here goes near the real launchd. The agents are written into a
/// temporary folder, and `launchctl` is stood in for by `FakeLaunchControl`,
/// which records what it was asked to do. Running one for real is a manual
/// check, described in the notes for whoever next touches this.
@MainActor
final class ScheduledDeployTests: XCTestCase {

    // MARK: - Stored properties

    /// The temporary stand-in for `~/Library/LaunchAgents`.
    var agentsDirectory: URL = URL(fileURLWithPath: "/")

    /// A working folder with a stub `deploy.sh` in it.
    var workspaceURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Functions

    /// A temporary stand-in for `~/Library/LaunchAgents`, and a working
    /// folder with a stub launcher in it.
    ///
    /// Called at the top of each test rather than from `setUpWithError()`:
    /// the overrides XCTest offers are nonisolated, and everything here is
    /// main-actor isolated by the project's default isolation.
    func prepare() throws {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scheduled-deploy-\(UUID().uuidString)")
        agentsDirectory = root.appendingPathComponent("LaunchAgents")
        workspaceURL = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "#!/usr/bin/env bash\nexit 0\n".write(
            to: workspaceURL.appendingPathComponent("deploy.sh"),
            atomically: true,
            encoding: .utf8
        )
        ScheduledDeploy.launchAgentsDirectoryOverride = agentsDirectory
        addTeardownBlock {
            MainActor.assumeIsolated {
                ScheduledDeploy.launchAgentsDirectoryOverride = nil
            }
        }
    }

    /// A course whose section 1 has already been deployed once, so nothing
    /// about deploying it asks the teacher anything.
    func makeCourse(
        deployTarget: String = "netlify",
        deployFolderPath: String = "",
        hasDeployedBefore: Bool = true,
        unpublishedClassTitles: [String] = [],
        publishedClassTitles: [String] = []
    ) throws -> Course {
        let courseURL: URL = workspaceURL
            .appendingPathComponent("courses")
            .appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"),
            withIntermediateDirectories: true
        )

        var values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "per_section_folders": ["All Classes"],
            "deploy_target": deployTarget,
        ]
        if !deployFolderPath.isEmpty {
            values["deploy_folder_path"] = deployFolderPath
        }
        let data: Data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try data.write(to: configURL)

        let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)

        if hasDeployedBefore {
            if let markerURL = DeployCommand.firstDeployMarkerURL(forSection: 1, in: course) {
                try FileManager.default.createDirectory(
                    at: markerURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try "{\"name\": \"ics3u-s1-2026\"}".write(to: markerURL, atomically: true, encoding: .utf8)
            }
        }

        for title in unpublishedClassTitles {
            try writeClassPage(title: title, publishes: false, in: courseURL)
        }
        for title in publishedClassTitles {
            try writeClassPage(title: title, publishes: true, in: courseURL)
        }
        return course
    }

    func writeClassPage(title: String, publishes: Bool, in courseURL: URL) throws {
        let page: String = """
        ---
        title: \(title)
        publish: \(publishes)
        created: 2026-09-08T07:00:00.000-0400
        ---

        Body.
        """
        try page.write(
            to: courseURL
                .appendingPathComponent("section1/All Classes")
                .appendingPathComponent("\(title).md"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// 6:30 tomorrow morning, the time this feature was built for.
    func sixThirtyTomorrow(from now: Date = Date()) -> Date {
        return ScheduleDeploySheet.defaultMoment(from: now)
    }

    // MARK: - The plist

    func testThePlistNamesTheLauncherAndItsArguments() throws {
        try prepare()
        let course: Course = try makeCourse()
        let when: Date = sixThirtyTomorrow()
        let arguments: [String] = DeployCommand.arguments(
            courseCode: course.code,
            sectionNumber: 1,
            configuration: course.configuration,
            cloudflareAccountID: ""
        )
        let plist: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: course.code,
            sectionNumber: 1,
            when: when,
            workspaceURL: workspaceURL,
            deployArguments: arguments
        )

        // Well-formed means launchd could really read it: round-tripped
        // through the XML property-list format rather than merely inspected
        // as a dictionary in memory.
        let data: Data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let decoded: Any = try PropertyListSerialization.propertyList(from: data, format: nil)
        let reread: [String: Any] = try XCTUnwrap(decoded as? [String: Any])

        XCTAssertEqual(reread["Label"] as? String, "ca.russellgordon.Plantoir.deploy.ICS3U.section1")
        XCTAssertEqual(reread["WorkingDirectory"] as? String, workspaceURL.path)
        XCTAssertEqual(reread["RunAtLoad"] as? Bool, false,
                       "Loading the agent must not deploy on the spot")

        // **Launched through PLANTOIR, not through bash**, and the whole
        // scheduled deploy depends on it. Reported by a teacher: a 9:49 PM
        // deploy failed with "Operation not permitted" on every path — a
        // launchd agent running a bare interpreter has no application
        // identity, so macOS's privacy system grants it nothing, and a
        // working folder on the Desktop is protected. The same deploy from
        // the app minutes earlier took 144 seconds and worked.
        //
        // It also decides what macOS CALLS the thing: the Background Activity
        // notice said `"bash" can run in the background`, which names none of
        // the teacher's applications.
        let programArguments: [String] = try XCTUnwrap(reread["ProgramArguments"] as? [String])
        XCTAssertEqual(programArguments.count, 7)
        XCTAssertFalse(programArguments[0].hasSuffix("/bash"),
                       "A bare interpreter cannot read the teacher's files: \(programArguments[0])")
        XCTAssertTrue(programArguments[0].contains("Plantoir"),
                      "The agent must run the signed app: \(programArguments[0])")
        XCTAssertEqual(programArguments[1], ScheduledDeploy.runFlag)
        XCTAssertEqual(
            programArguments[2],
            ScheduledDeploy.scriptURL(courseCode: "ICS3U", sectionNumber: 1).path
        )
        // …and which section it is publishing, so the app can mark that
        // section's pages as published once the script has finished. A
        // scheduled deploy does not go through the deploy runner, so
        // without this it publishes and leaves the window saying
        // " — Edited" until somebody publishes again by hand.
        XCTAssertEqual(programArguments[3], ScheduledDeploy.sectionFlag)
        XCTAssertEqual(programArguments[5], "ICS3U")
        XCTAssertEqual(programArguments[6], "1")

        // The work itself is unchanged; it moved into a file the app runs.
        let command: String = ScheduledDeploy.oneShotCommand(
            courseCode: "ICS3U", sectionNumber: 1,
            workspaceURL: workspaceURL, deployArgumentsList: [arguments]
        )
        let scriptPath: String = workspaceURL.appendingPathComponent("deploy.sh").path
        XCTAssertTrue(command.contains("'\(scriptPath)'"), "The agent runs this folder's own deploy.sh")
        XCTAssertTrue(command.contains(" 'ICS3U' '1'"), "The course code and section ride as separate arguments")

        let schedule: [String: Any] = try XCTUnwrap(reread["StartCalendarInterval"] as? [String: Any])
        let components: DateComponents = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: when)
        XCTAssertEqual(schedule["Hour"] as? Int, components.hour)
        XCTAssertEqual(schedule["Minute"] as? Int, components.minute)
        XCTAssertEqual(schedule["Day"] as? Int, components.day)
        XCTAssertEqual(schedule["Month"] as? Int, components.month)

        // A launchd agent starts with a bare PATH, and the launcher has to
        // find docker and colima the way a Terminal session does.
        let environment: [String: String] = try XCTUnwrap(reread["EnvironmentVariables"] as? [String: String])
        XCTAssertTrue((environment["PATH"] ?? "").contains("/opt/homebrew/bin"))
        XCTAssertNotNil(environment[ScheduledDeploy.scheduledForKey],
                        "StartCalendarInterval has no year, so the moment rides in the environment")
    }

    /// The flag the agent uses is read back the way the app reads it, and an
    /// ordinary launch is not mistaken for one.
    @MainActor
    func testTheRunFlagIsRecognisedAndOrdinaryLaunchesAreNot() {
        XCTAssertEqual(
            ScheduledDeploy.requestedScript(from:
                ["/Applications/Plantoir.app", ScheduledDeploy.runFlag, "/tmp/one.sh"]),
            "/tmp/one.sh"
        )
        XCTAssertNil(ScheduledDeploy.requestedScript(from: ["/Applications/Plantoir.app"]))
        // A flag with nothing after it must not be read as a request, or the
        // app would try to run a script called nothing and never open.
        XCTAssertNil(ScheduledDeploy.requestedScript(from: ["/x", ScheduledDeploy.runFlag]))
    }

    /// Scheduling writes the script the agent runs, and cancelling takes it
    /// away — a cancelled deploy must not leave a runnable copy of itself.
    @MainActor
    func testTheScriptIsWrittenAndRemovedWithTheAlarm() throws {
        try prepare()
        let course: Course = try makeCourse()
        let commandURL: URL = ScheduledDeploy.scriptURL(courseCode: course.code, sectionNumber: 1)
        try? FileManager.default.removeItem(at: commandURL)

        let runner: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: commandURL.path),
                      "The agent has nothing to run")
        let written: String = try String(contentsOf: commandURL, encoding: .utf8)
        XCTAssertTrue(written.hasPrefix("#!/bin/bash"), written)
        XCTAssertTrue(written.contains("deploy.sh"), written)

        ScheduledDeploy.cancelScheduledDeploy(
            courseCode: course.code, sectionNumber: 1, runner: runner
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: commandURL.path),
                       "A cancelled deploy left a runnable copy of itself behind")
    }

    func testTwoSectionsOfOneCourseGetDifferentAgents() throws {
        try prepare()
        let first: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1)
        let second: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 2)
        let otherCourse: String = ScheduledDeploy.agentLabel(courseCode: "MCV4U", sectionNumber: 1)

        XCTAssertNotEqual(first, second, "Two sections must never share one agent")
        XCTAssertNotEqual(first, otherCourse)
        XCTAssertTrue(first.hasSuffix(".ICS3U.section1"))
        XCTAssertTrue(second.hasSuffix(".ICS3U.section2"))

        XCTAssertNotEqual(
            ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1),
            ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 2)
        )
    }

    func testTheAgentClearsItselfAwayOnceItHasFired() throws {
        try prepare()
        let command: String = ScheduledDeploy.oneShotCommand(
            courseCode: "ICS3U",
            sectionNumber: 1,
            workspaceURL: workspaceURL,
            deployArgumentsList: [["ICS3U", "1"]]
        )
        let plistPath: String = ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1).path
        let label: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1)

        let removalIndex: String.Index = try XCTUnwrap(command.range(of: "/bin/rm -f '\(plistPath)'")?.lowerBound)
        let deployIndex: String.Index = try XCTUnwrap(command.range(of: "deploy.sh'")?.lowerBound)
        let bootoutIndex: String.Index = try XCTUnwrap(command.range(of: "bootout gui/")?.lowerBound)

        XCTAssertTrue(removalIndex < deployIndex,
                      "The plist goes first, so a Mac restarting mid-deploy comes back with nothing pending")
        XCTAssertTrue(deployIndex < bootoutIndex,
                      "The agent boots itself out only once the deploy has finished")
        XCTAssertTrue(command.contains(label))
    }

    // MARK: - Scheduling and cancelling

    func testSchedulingWritesTheAgentAndBootstrapsIt() throws {
        try prepare()
        let course: Course = try makeCourse()
        let launchControl: FakeLaunchControl = FakeLaunchControl()

        let problem: String? = ScheduledDeploy.scheduleDeploy(
            course: course,
            sectionNumber: 1,
            when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL,
            cloudflareAccountID: "",
            runner: launchControl
        )

        XCTAssertNil(problem)
        let plistURL: URL = ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertEqual(launchControl.bootstrappedURLs, [plistURL])
        XCTAssertNotNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1))
    }

    func testSchedulingTwiceLeavesOneAgent() throws {
        try prepare()
        let course: Course = try makeCourse()
        let launchControl: FakeLaunchControl = FakeLaunchControl()
        let label: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1)

        ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: launchControl
        )
        let later: Date = sixThirtyTomorrow().addingTimeInterval(60 * 60)
        ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: later,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: launchControl
        )

        let contents: [URL] = try FileManager.default.contentsOfDirectory(
            at: agentsDirectory, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(contents.count, 1, "The label is fixed per section, so scheduling replaces")
        XCTAssertTrue(launchControl.bootedOutLabels.contains(label),
                      "The previous agent goes before the replacement is written")

        let nextRun: Date = try XCTUnwrap(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1))
        XCTAssertEqual(nextRun.timeIntervalSince1970, later.timeIntervalSince1970, accuracy: 1)
    }

    func testCancellingRemovesTheAgent() throws {
        try prepare()
        let course: Course = try makeCourse()
        let launchControl: FakeLaunchControl = FakeLaunchControl()
        ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: launchControl
        )
        let plistURL: URL = ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))

        let problem: String? = ScheduledDeploy.cancelScheduledDeploy(
            courseCode: "ICS3U", sectionNumber: 1, runner: launchControl
        )

        XCTAssertNil(problem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1))
        XCTAssertEqual(
            launchControl.bootedOutLabels.last,
            ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1)
        )
    }

    func testCancellingSomethingAlreadyGoneIsNotAFailure() throws {
        try prepare()
        let launchControl: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduledDeploy.cancelScheduledDeploy(
            courseCode: "ICS3U", sectionNumber: 4, runner: launchControl
        ))
    }

    func testAnAgentWhoseTimeHasPassedIsNotShownAsScheduled() throws {
        try prepare()
        let course: Course = try makeCourse()
        let launchControl: FakeLaunchControl = FakeLaunchControl()
        let when: Date = Date().addingTimeInterval(60 * 60)
        ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: when,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: launchControl
        )

        XCTAssertNotNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, now: Date()))
        XCTAssertNil(
            ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, now: when.addingTimeInterval(60)),
            "A promise whose moment has gone is not worth showing"
        )
    }

    // MARK: - Refusals

    func testATimeThatHasPassedIsRefused() throws {
        try prepare()
        let course: Course = try makeCourse()
        let now: Date = Date()
        let problem: String? = ScheduledDeploy.problem(
            course: course, sectionNumber: 1,
            when: now.addingTimeInterval(-60), now: now,
            cloudflareAccountID: ""
        )
        XCTAssertNotNil(problem)
        XCTAssertTrue((problem ?? "").contains("has already passed"))
    }

    func testASectionNeverDeployedCannotBeScheduled() throws {
        try prepare()
        let course: Course = try makeCourse(hasDeployedBefore: false)
        let problem: String? = ScheduledDeploy.problem(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: ""
        )
        let text: String = try XCTUnwrap(problem)
        XCTAssertTrue(text.contains("has never been deployed"))
        XCTAssertTrue(text.contains("Nobody would be there to answer"))
    }

    func testACloudflareCourseWithNoAccountIDCannotBeScheduled() throws {
        try prepare()
        let course: Course = try makeCourse(deployTarget: "cloudflare_pages")
        let problem: String? = ScheduledDeploy.problem(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: ""
        )
        let text: String = try XCTUnwrap(problem)
        XCTAssertTrue(text.contains("Cloudflare Pages"))
        XCTAssertTrue(text.contains("Account ID"))
    }

    /// Unlike the Windows app, the mac CAN hand a scheduled deploy the
    /// account ID — it is written into the agent as `--account` — so a
    /// Cloudflare course with the ID entered is schedulable rather than
    /// refused outright.
    func testACloudflareCourseWithAnAccountIDCanBeScheduled() throws {
        try prepare()
        let course: Course = try makeCourse(deployTarget: "cloudflare_pages")
        let account: String = "0123456789abcdef0123456789abcdef"
        XCTAssertNil(ScheduledDeploy.problem(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: account
        ))

        let launchControl: FakeLaunchControl = FakeLaunchControl()
        ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: account, runner: launchControl
        )
        // The command moved out of the plist and into the script the app
        // runs, so it is read from where it now lives.
        let command: String = try String(
            contentsOf: ScheduledDeploy.scriptURL(courseCode: "ICS3U", sectionNumber: 1),
            encoding: .utf8
        )
        XCTAssertTrue(command.contains("'--target' 'cloudflare'"))
        XCTAssertTrue(command.contains("'--account' '\(account)'"),
                      "The agent carries the account, so nothing is asked at half six")
    }

    func testAFolderCourseWithNoUsableFolderCannotBeScheduled() throws {
        try prepare()
        let course: Course = try makeCourse(
            deployTarget: "local_folder",
            deployFolderPath: "/nowhere/at/all"
        )
        let problem: String? = ScheduledDeploy.problem(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: ""
        )
        XCTAssertNotNil(problem)
    }

    func testSchedulingWithoutALauncherIsRefused() throws {
        try prepare()
        let course: Course = try makeCourse()
        try FileManager.default.removeItem(at: workspaceURL.appendingPathComponent("deploy.sh"))
        let problem: String? = ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: FakeLaunchControl()
        )
        XCTAssertNotNil(problem)
    }

    func testLaunchdRefusingLeavesNoAgentBehind() throws {
        try prepare()
        let course: Course = try makeCourse()
        let launchControl: FakeLaunchControl = FakeLaunchControl()
        launchControl.bootstrapFailure = "Load failed: 5: Input/output error"

        let problem: String? = ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: launchControl
        )

        XCTAssertNotNil(problem)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1).path
            ),
            "A plist launchd would not take must not sit there looking scheduled"
        )
    }

    // MARK: - The plan the teacher reads

    func testThePlanSaysWhatMustBeTrueOfTheMac() throws {
        try prepare()
        let course: Course = try makeCourse()
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: ""
        )

        XCTAssertTrue(plan.isSchedulable)
        let text: String = plan.description
        XCTAssertTrue(text.contains("ICS3U Section 1"))
        XCTAssertTrue(text.contains("Netlify"))
        XCTAssertTrue(text.contains("switched on, and awake"))
        XCTAssertTrue(text.contains("plugged in, if it is a laptop"))
        XCTAssertTrue(text.contains("lid open"))
        XCTAssertTrue(text.contains("Plantoir does not wake this Mac up"))
        // launchd really does run a missed calendar job at the next wake,
        // so the plan says that rather than promising nothing happens.
        XCTAssertTrue(text.contains("at the next wake"))
        // The agent rebuilds when something changed and then deploys,
        // which is what the Deploy button does — so work done after the
        // alarm is set does go out, and the teacher is told that rather
        // than previewing out of caution every night.
        XCTAssertTrue(text.contains("goes out with it"))
        XCTAssertTrue(text.contains("it is rebuilt first"))
        // And the failure case, because an unattended deploy that half
        // worked is worse than one that did not run.
        XCTAssertTrue(text.contains("nothing is deployed"))
    }

    /// The agent builds the section before deploying it, exactly as the
    /// Deploy button does.
    ///
    /// `deploy.sh` never builds — it refuses outright when there is no built
    /// site — so an agent that ran it alone would either fail at half six or
    /// send whatever was last previewed. Neither is what a teacher means by
    /// "deploy tomorrow's class at 6:30".
    func testTheAgentBuildsBeforeItDeploys() throws {
        let command: String = ScheduledDeploy.oneShotCommand(
            courseCode: "ICS3U",
            sectionNumber: 1,
            workspaceURL: URL(fileURLWithPath: "/Users/someone/Class Websites"),
            deployArgumentsList: [["ICS3U", "1"]]
        )

        guard let buildAt = command.range(of: "preview.sh"),
              let deployAt = command.range(of: "deploy.sh") else {
            return XCTFail("The agent must run both preview.sh and deploy.sh")
        }
        XCTAssertTrue(buildAt.lowerBound < deployAt.lowerBound, "The build has to come first")
        XCTAssertTrue(command.contains("--build-only"), "The build must not also start a server")

        // Only when something changed. Rebuilding an unchanged section at
        // half six costs a container start and a full Quartz run to produce
        // the bytes already on disk.
        XCTAssertTrue(command.contains("NEEDS_BUILD"), "The build has to be conditional")
        XCTAssertTrue(command.contains("-newer"), "Staleness is content newer than the built page")
        XCTAssertTrue(command.contains("-not -path '*/.*'"),
                      "Hidden entries are skipped, or .merged_output makes the site look stale the instant it is built")
        // A PREVIEW build is never deploy-fresh, however recent it looks:
        // serve mode bakes a ws://localhost client into every page.
        XCTAssertTrue(command.contains("ws://localhost:"),
                      "A preview build must force a rebuild rather than being deployed")

        // The deploy is gated, so a failed build deploys nothing — the
        // button returns early rather than sending the previous build, and
        // an unattended run must not be less careful than the teacher.
        XCTAssertTrue(command.contains("READY=0"), "A failed build has to stop the deploy")
        XCTAssertTrue(command.contains("if [ \"$READY\" = \"1\" ]; then"))

        // Cleanup sits outside the if: a failed build must still leave
        // nothing pending, or the agent fires again at the same time
        // tomorrow with nobody expecting it.
        guard let bootoutAt = command.range(of: "bootout"),
              let lastCloseAt = command.range(of: "fi", options: .backwards) else {
            return XCTFail("The agent must boot itself out when it is done")
        }
        XCTAssertTrue(lastCloseAt.lowerBound < bootoutAt.lowerBound,
                      "Cleanup runs whether or not the build worked")

        // A working folder with a space in its name is ordinary on a Mac —
        // "Class Websites" is what the documentation itself suggests.
        XCTAssertTrue(command.contains("'/Users/someone/Class Websites/preview.sh'"),
                      "Paths must survive a space in the folder name")
    }

    func testTheDestinationIsNamedInThePlan() throws {
        try prepare()
        let cloudflare: Course = try makeCourse(deployTarget: "cloudflare_pages")
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: cloudflare, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: "0123456789abcdef0123456789abcdef"
        )
        XCTAssertTrue(plan.description.contains("Cloudflare Pages"))
        XCTAssertFalse(plan.description.contains("Netlify"))
    }

    func testClassesStudentsCannotSeeYetAreNamed() throws {
        try prepare()
        let course: Course = try makeCourse(
            unpublishedClassTitles: ["Unit 2, Day 3"],
            publishedClassTitles: ["Unit 2, Day 2"]
        )
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: ""
        )

        XCTAssertEqual(plan.unpublishedClasses, ["Unit 2, Day 3"])
        let text: String = plan.description
        XCTAssertTrue(text.contains("not published yet"))
        XCTAssertTrue(text.contains("Unit 2, Day 3"))
        XCTAssertFalse(text.contains("Unit 2, Day 2"))
        XCTAssertTrue(text.contains("Publish first"))
    }

    func testAFullyPublishedSectionSaysNothingAboutHeldBackClasses() throws {
        try prepare()
        let course: Course = try makeCourse(publishedClassTitles: ["Unit 2, Day 2"])
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: ""
        )
        XCTAssertTrue(plan.unpublishedClasses.isEmpty)
        XCTAssertFalse(plan.description.contains("not published yet"))
    }

    func testPlanningChangesNothing() throws {
        try prepare()
        let course: Course = try makeCourse()
        _ = ScheduledDeploy.plan(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: ""
        )
        let contents: [URL] = try FileManager.default.contentsOfDirectory(
            at: agentsDirectory, includingPropertiesForKeys: nil
        )
        XCTAssertTrue(contents.isEmpty, "Describing a deploy must schedule nothing")
    }

    func testTheSheetOpensOnTomorrowAtHalfSix() throws {
        try prepare()
        var components: DateComponents = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 14
        components.minute = 12
        let now: Date = try XCTUnwrap(Calendar.current.date(from: components))

        let moment: Date = ScheduleDeploySheet.defaultMoment(from: now)
        let parts: DateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: moment)
        XCTAssertEqual(parts.day, 16)
        XCTAssertEqual(parts.hour, 6)
        XCTAssertEqual(parts.minute, 30)
    }

    func testTheTooltipSaysWhenAndWhatIsNeeded() throws {
        try prepare()
        let tooltip: String = SidebarView.scheduledDeployTooltip(for: sixThirtyTomorrow())
        XCTAssertTrue(tooltip.contains("Right-click to cancel"))
        XCTAssertTrue(tooltip.contains("on and awake"))
    }
}

/// `launchctl`, stood in for.
///
/// The suite must never bootstrap a real agent: it would leave a deploy
/// scheduled on whoever ran the tests. This records what would have been
/// asked instead, and can be told to refuse.
@MainActor
final class FakeLaunchControl: LaunchControlRunning {

    // MARK: - Stored properties

    var bootstrappedURLs: [URL] = []
    var bootedOutLabels: [String] = []

    /// What launchctl says when bootstrapping, or nil when it accepts.
    var bootstrapFailure: String?

    // MARK: - Functions

    func bootstrap(plistURL: URL) -> String? {
        if let bootstrapFailure {
            return bootstrapFailure
        }
        bootstrappedURLs.append(plistURL)
        return nil
    }

    func bootOut(label: String) {
        bootedOutLabels.append(label)
    }
}
