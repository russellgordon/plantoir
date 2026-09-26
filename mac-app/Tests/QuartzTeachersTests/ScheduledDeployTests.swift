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
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            agentsDirectory.deletingLastPathComponent().appendingPathComponent("scheduled")
        addTeardownBlock {
            MainActor.assumeIsolated {
                ScheduledDeploy.launchAgentsDirectoryOverride = nil
                ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
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

    /// A publish that runs at half six has to find the same programs the app
    /// does, and the list it was given left out the only place they exist on
    /// a Mac that has never had Homebrew.
    ///
    /// This was `"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"`
    /// — three copies of the same hand-maintained list lived in this app, and
    /// not one of them named `~/Library/Application Support/Plantoir/tools/bin`,
    /// which is where the launchers download the pinned `docker` and `colima`
    /// into. The scheduled publish survived only because the launcher exports
    /// that folder again from inside itself; the quit path, which runs no
    /// launcher, did not (issue #220).
    func testTheScheduledJobCanFindTheProgramsPlantoirDownloaded() throws {
        try prepare()
        let course: Course = try makeCourse()
        let plist: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: course.code,
            sectionNumber: 1,
            when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL,
            scheduledTo: []
        )
        let environment: [String: String] = try XCTUnwrap(
            plist["EnvironmentVariables"] as? [String: String]
        )
        let path: String = try XCTUnwrap(environment["PATH"])
        XCTAssertEqual(
            path.components(separatedBy: ":").first,
            HelperPrograms.binDirectory(),
            "The scheduled publish is looking everywhere except where Plantoir put the programs"
        )
        XCTAssertEqual(path, HelperPrograms.pathValue(inheriting: nil))
    }

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
            scheduledTo: ["Netlify"]
        )

        // Well-formed means launchd could really read it: round-tripped
        // through the XML property-list format rather than merely inspected
        // as a dictionary in memory.
        let data: Data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let decoded: Any = try PropertyListSerialization.propertyList(from: data, format: nil)
        let reread: [String: Any] = try XCTUnwrap(decoded as? [String: Any])

        XCTAssertEqual(
            reread["Label"] as? String,
            "ca.russellgordon.Plantoir.deploy.ICS3U.section1."
                + BuildOutputLocation.folderIdentifier(forWorkingFolder: workspaceURL.path)
        )
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
            ScheduledDeploy.scriptURL(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL).path
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

    /// Scheduling a section that already has a deploy set IN THIS WORKING
    /// FOLDER says so in the plan — the schedule sheet's own text — and leaves
    /// a line on the trail once it has replaced it (issue #195).
    ///
    /// **Inverted by #237, not merely updated.** #195 read the old one
    /// Mac-wide on purpose, because scheduling then overwrote the one job a
    /// section had on the whole Mac, whichever folder had set it. Now another
    /// folder's job is a different alarm that scheduling here leaves standing,
    /// so naming it as "replaced" would be false: the first half below fails
    /// against the Mac-wide reading.
    @MainActor
    func testSchedulingAgainSaysWhatItReplacesAndRecordsIt() throws {
        try prepare()
        let course: Course = try makeCourse()
        let scratch: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        let newMoment: Date = sixThirtyTomorrow()
        let alreadySet: Date = newMoment.addingTimeInterval(36 * 60 * 60)

        // Another working folder's deploy of the same section: not replaced,
        // not named, and still standing afterwards.
        let lastYear: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("last-year")
        let theirs: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: course.code, sectionNumber: 1, when: alreadySet.addingTimeInterval(60 * 60),
            workspaceURL: lastYear, scheduledTo: []
        )
        let theirPlist: URL = ScheduledDeploy.plistURL(
            courseCode: course.code, sectionNumber: 1, inWorkingFolder: lastYear
        )
        try PropertyListSerialization.data(fromPropertyList: theirs, format: .xml, options: 0)
            .write(to: theirPlist)
        XCTAssertNil(
            ScheduledDeploy.momentBeingReplaced(
                courseCode: course.code, sectionNumber: 1, by: newMoment, inWorkingFolder: workspaceURL
            ),
            "Another working folder's deploy is not replaced by scheduling here"
        )

        // This folder's own.
        let old: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: course.code, sectionNumber: 1, when: alreadySet,
            workspaceURL: workspaceURL,
            scheduledTo: []
        )
        try PropertyListSerialization.data(fromPropertyList: old, format: .xml, options: 0)
            .write(to: ScheduledDeploy.plistURL(courseCode: course.code, sectionNumber: 1, inWorkingFolder: workspaceURL))

        XCTAssertEqual(
            ScheduledDeploy.momentBeingReplaced(courseCode: course.code, sectionNumber: 1, by: newMoment, inWorkingFolder: workspaceURL),
            alreadySet
        )
        XCTAssertNil(
            ScheduledDeploy.momentBeingReplaced(courseCode: course.code, sectionNumber: 1, by: alreadySet, inWorkingFolder: workspaceURL),
            "Setting it again for the same moment replaces nothing a teacher would notice"
        )

        let sentence: String = AssistWording.scheduleReplaces(
            moment: ScheduledDeploy.dayAndTimeText(alreadySet)
        )
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: course, sectionNumber: 1, when: newMoment, now: Date(), cloudflareAccountID: "", inWorkingFolder: workspaceURL
        )
        XCTAssertTrue(plan.description.contains(sentence), plan.description)

        let runner: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: newMoment,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("\(course.code)/1"), trail)
        XCTAssertTrue(trail.contains(ScheduledDeploy.dayAndTimeText(alreadySet)), trail)
        XCTAssertTrue(trail.contains(ScheduledDeploy.dayAndTimeText(newMoment)), trail)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: theirPlist.path),
            "Scheduling here removed another working folder's deploy"
        )
        XCTAssertFalse(runner.bootedOutLabels.contains(theirs["Label"] as? String ?? ""))

        // Now that it is set, the sheet says it would replace THIS one — and
        // scheduling the same moment again says nothing and records nothing.
        let again: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: course, sectionNumber: 1, when: newMoment, now: Date(), cloudflareAccountID: "", inWorkingFolder: workspaceURL
        )
        XCTAssertFalse(again.description.contains(sentence), again.description)
        let linesBefore: Int = trail.components(separatedBy: "\n").count
        XCTAssertNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: newMoment,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))
        XCTAssertEqual(
            ActivityTrail.store.activityText(includingPrompts: true).components(separatedBy: "\n").count,
            linesBefore
        )
    }

    /// A replacement that FAILS has still removed the old deploy — booted out
    /// and overwritten before macOS refused the new one — so the teacher has
    /// neither, and the refusal speaks only of the new one. The trail says the
    /// old one was turned off, and when it had been set for.
    @MainActor
    func testAReplacementThatFailsRecordsTheDeployItTurnedOff() throws {
        try prepare()
        let course: Course = try makeCourse()
        let scratch: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        let newMoment: Date = sixThirtyTomorrow()
        let alreadySet: Date = newMoment.addingTimeInterval(36 * 60 * 60)
        let old: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: course.code, sectionNumber: 1, when: alreadySet,
            workspaceURL: workspaceURL, scheduledTo: []
        )
        try PropertyListSerialization.data(fromPropertyList: old, format: .xml, options: 0)
            .write(to: ScheduledDeploy.plistURL(courseCode: course.code, sectionNumber: 1, inWorkingFolder: workspaceURL))

        let runner: FakeLaunchControl = FakeLaunchControl()
        runner.bootstrapFailure = "Bootstrap failed: 5: Input/output error"
        XCTAssertNotNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: newMoment,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))
        XCTAssertEqual(runner.bootedOutLabels.count, 1, "The old deploy was booted out before the new one was refused")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(ScheduledDeploy.dayAndTimeText(alreadySet)), trail)
        XCTAssertTrue(trail.contains("turned off"), trail)
        XCTAssertTrue(
            trail.contains("could not set a scheduled deploy for \(ScheduledDeploy.dayAndTimeText(newMoment))"),
            "The trail must say the new one was not set: \(trail)"
        )
    }

    /// The SAME minute, refused by macOS: the card rightly said nothing about
    /// replacing it, but the old one's plist was overwritten before macOS was
    /// asked, so it is gone — and that loss is recorded (#195 fix review).
    @MainActor
    func testARefusedReScheduleForTheSameMinuteRecordsWhatWasLost() throws {
        try prepare()
        let course: Course = try makeCourse()
        let scratch: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        let moment: Date = sixThirtyTomorrow()
        let old: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: course.code, sectionNumber: 1, when: moment,
            workspaceURL: workspaceURL, scheduledTo: []
        )
        try PropertyListSerialization.data(fromPropertyList: old, format: .xml, options: 0)
            .write(to: ScheduledDeploy.plistURL(courseCode: course.code, sectionNumber: 1, inWorkingFolder: workspaceURL))
        XCTAssertNil(
            ScheduledDeploy.momentBeingReplaced(courseCode: course.code, sectionNumber: 1, by: moment, inWorkingFolder: workspaceURL),
            "The card says nothing for the same minute"
        )

        let runner: FakeLaunchControl = FakeLaunchControl()
        runner.bootstrapFailure = "Bootstrap failed: 5: Input/output error"
        XCTAssertNotNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: moment,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("turned off the scheduled deploy set for \(ScheduledDeploy.dayAndTimeText(moment))"),
            "A same-minute deploy was lost and nothing says so: \(trail)"
        )
    }

    /// A failed WRITE is not a loss: the old plist is still on disk, so it is
    /// handed back to macOS and the trail says it still stands — never "turned
    /// off", which would be false, since it would still fire (#195 fix review).
    @MainActor
    func testAFailedWriteLeavesTheOldDeployStandingAndSaysSo() throws {
        try prepare()
        let course: Course = try makeCourse()
        let scratch: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        let newMoment: Date = sixThirtyTomorrow()
        let alreadySet: Date = newMoment.addingTimeInterval(36 * 60 * 60)
        let old: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: course.code, sectionNumber: 1, when: alreadySet,
            workspaceURL: workspaceURL, scheduledTo: []
        )
        let plist: URL = ScheduledDeploy.plistURL(courseCode: course.code, sectionNumber: 1, inWorkingFolder: workspaceURL)
        let oldBytes: Data = try PropertyListSerialization.data(fromPropertyList: old, format: .xml, options: 0)
        try oldBytes.write(to: plist)

        // The scripts folder sits under a FILE, so creating it throws — the
        // first write in the attempt fails before the plist is touched.
        let blocker: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        ScheduledDeploy.scheduledScriptsDirectoryOverride = blocker.appendingPathComponent("scheduled")

        let runner: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNotNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: newMoment,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))
        XCTAssertEqual(try Data(contentsOf: plist), oldBytes, "The old plist must be untouched by a failed write")
        XCTAssertEqual(runner.bootstrappedURLs, [plist], "The old deploy was not handed back to macOS")

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("still stands"), trail)
        XCTAssertTrue(trail.contains(ScheduledDeploy.dayAndTimeText(alreadySet)), trail)
        XCTAssertFalse(trail.contains("turned off"), "The old deploy still stands, so nothing was turned off: \(trail)")
    }

    /// With nothing set, the plan says nothing about replacing anything.
    @MainActor
    func testSchedulingAFreeSectionMentionsNoReplacement() throws {
        try prepare()
        let course: Course = try makeCourse()
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(), now: Date(), cloudflareAccountID: "", inWorkingFolder: workspaceURL
        )
        XCTAssertNil(plan.replacing)
        XCTAssertNil(ScheduledDeploy.momentBeingReplaced(
            courseCode: course.code, sectionNumber: 1, by: sixThirtyTomorrow(), inWorkingFolder: workspaceURL
        ))
    }

    /// Scheduling writes the script the agent runs, and cancelling takes it
    /// away — a cancelled deploy must not leave a runnable copy of itself.
    @MainActor
    func testTheScriptIsWrittenAndRemovedWithTheAlarm() throws {
        try prepare()
        let course: Course = try makeCourse()
        let commandURL: URL = ScheduledDeploy.scriptURL(courseCode: course.code, sectionNumber: 1, inWorkingFolder: workspaceURL)
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
            courseCode: course.code, sectionNumber: 1,
            inWorkingFolder: workspaceURL, runner: runner
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: commandURL.path),
                       "A cancelled deploy left a runnable copy of itself behind")
    }

    /// A scheduled deploy tells the launcher that nobody is at the Mac,
    /// and the Deploy button does not.
    ///
    /// The two run the identical launcher through the identical machinery,
    /// and only this flag tells them apart. Pressing Deploy attaches a
    /// pseudo-terminal, so a question from the publishing step comes back
    /// as a dialog somebody answers — that must keep working. At half six
    /// in the morning the same question either waits forever (measured at
    /// 45 minutes on Windows) or is answered with a default nobody chose,
    /// and the website goes to an address nobody picked.
    @MainActor
    func testAScheduledDeployTellsTheLauncherNobodyIsHere() throws {
        try prepare()
        let course: Course = try makeCourse()
        let commandURL: URL = ScheduledDeploy.scriptURL(courseCode: course.code, sectionNumber: 1, inWorkingFolder: workspaceURL)
        try? FileManager.default.removeItem(at: commandURL)

        let runner: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))

        let written: String = try String(contentsOf: commandURL, encoding: .utf8)
        XCTAssertTrue(
            written.contains("'--non-interactive'"),
            "The scheduled deploy must tell the launcher nobody can answer a question: \(written)"
        )

        // The BUILD leg carries it too, in that order.
        //
        // The order is asserted, not just the presence, because it is what
        // `scripts/test_preview_sh_questions.py` drives: that file runs the
        // launcher with the flag LAST, after another flag, since that is the
        // shape a parser bug would hide (the flag's `case` arm must not
        // shift, or it eats what follows). Assert only that the flag appears
        // somewhere and these two can drift apart in silence — the Python
        // would go on testing a command line nothing writes any more.
        XCTAssertTrue(
            written.contains("--build-only --non-interactive"),
            "The build leg must pass --build-only --non-interactive, in that "
            + "order, which is the command line the launcher's own tests "
            + "drive: \(written)"
        )

        // And the button does not, so the dialog a teacher answers stays.
        let buttonArguments: [String] = DeployCommand.arguments(
            courseCode: course.code,
            sectionNumber: 1,
            configuration: course.configuration,
            cloudflareAccountID: ""
        )
        XCTAssertFalse(
            buttonArguments.contains("--non-interactive"),
            "Pressing Deploy must still be able to ask the teacher a question"
        )
    }

    func testTwoSectionsOfOneCourseGetDifferentAgents() throws {
        try prepare()
        let first: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspaceURL)
        let second: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 2, workingFolder: workspaceURL)
        let otherCourse: String = ScheduledDeploy.agentLabel(courseCode: "MCV4U", sectionNumber: 1, workingFolder: workspaceURL)

        XCTAssertNotEqual(first, second, "Two sections must never share one agent")
        XCTAssertNotEqual(first, otherCourse)
        XCTAssertTrue(first.contains(".ICS3U.section1."))
        XCTAssertTrue(second.contains(".ICS3U.section2."))

        XCTAssertNotEqual(
            ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL),
            ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 2, inWorkingFolder: workspaceURL)
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
        let plistPath: String = ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL).path
        let label: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspaceURL)

        let removalIndex: String.Index = try XCTUnwrap(command.range(of: "/bin/rm -f '\(plistPath)'")?.lowerBound)
        let deployIndex: String.Index = try XCTUnwrap(command.range(of: "deploy.sh'")?.lowerBound)

        XCTAssertTrue(removalIndex < deployIndex,
                      "The plist goes first, so a Mac restarting mid-deploy comes back with nothing pending")

        // The SCRIPT must not boot the job out, and this is a fix rather than
        // a relaxed assertion. The agent runs the APP, which runs this script
        // and then records the publish, reads folder problems out of the log,
        // and writes the trail line for a run that stopped. Booting out from
        // inside the script ends the job — and the app IS the job — so none
        // of that ever ran. Measured with a real scheduled deploy on
        // 2026-09-09: the wrapper wrote its stopped record and the trail got
        // nothing. The app boots the agent out itself now, once its work is
        // done, in ScheduledDeploy.bootOutAgent.
        XCTAssertFalse(
            command.contains("bootout"),
            "The generated script must not boot the job out: it would kill the app that is "
            + "running it, before the app can record what happened."
        )
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
        let plistURL: URL = ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertEqual(launchControl.bootstrappedURLs, [plistURL])
        XCTAssertNotNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL))
    }

    func testSchedulingTwiceLeavesOneAgent() throws {
        try prepare()
        let course: Course = try makeCourse()
        let launchControl: FakeLaunchControl = FakeLaunchControl()
        let label: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspaceURL)

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

        let nextRun: Date = try XCTUnwrap(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL))
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
        let plistURL: URL = ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))

        let problem: String? = ScheduledDeploy.cancelScheduledDeploy(
            courseCode: "ICS3U", sectionNumber: 1,
            inWorkingFolder: workspaceURL, runner: launchControl
        )

        XCTAssertNil(problem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL))
        XCTAssertEqual(
            launchControl.bootedOutLabels.last,
            ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspaceURL)
        )
    }

    func testCancellingSomethingAlreadyGoneIsNotAFailure() throws {
        try prepare()
        let launchControl: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduledDeploy.cancelScheduledDeploy(
            courseCode: "ICS3U", sectionNumber: 4,
            inWorkingFolder: workspaceURL, runner: launchControl
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

        XCTAssertNotNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, now: Date(), inWorkingFolder: workspaceURL))
        XCTAssertNil(
            ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, now: when.addingTimeInterval(60), inWorkingFolder: workspaceURL),
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
            contentsOf: ScheduledDeploy.scriptURL(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL),
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
                atPath: ScheduledDeploy.plistURL(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL).path
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
            cloudflareAccountID: "", inWorkingFolder: workspaceURL
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

        // Nothing pending after a failed build either — but the plist is what
        // guarantees that, and it is removed at the TOP, before anything runs.
        // The job's own removal from launchd moved into the app (bootOutAgent)
        // when a real scheduled run showed that booting out from the script
        // killed the app before it could record anything.
        XCTAssertFalse(command.contains("bootout"))
        let plistRemoval: String = "/bin/rm -f '"
            + ScheduledDeploy.plistURL(
                courseCode: "ICS3U", sectionNumber: 1,
                inWorkingFolder: URL(fileURLWithPath: "/Users/someone/Class Websites")
            ).path + "'"
        XCTAssertTrue(
            command.contains(plistRemoval),
            "A failed build must still leave nothing pending, or the agent fires again "
            + "tomorrow with nobody expecting it."
        )

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
            cloudflareAccountID: "0123456789abcdef0123456789abcdef", inWorkingFolder: workspaceURL
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
            cloudflareAccountID: "", inWorkingFolder: workspaceURL
        )

        XCTAssertEqual(plan.unpublishedClasses, ["Unit 2, Day 3"])
        let text: String = plan.description
        XCTAssertTrue(text.contains("not published yet"))
        XCTAssertTrue(text.contains("Unit 2, Day 3"))
        XCTAssertFalse(text.contains("Unit 2, Day 2"))
        XCTAssertTrue(text.contains("Publish first"))
    }

    /// A teacher who annotates the flag with a reason has still published the
    /// page: the build strips the comment before Quartz sees it. Warning them
    /// that this class is "not published yet", at half six the night before a
    /// deploy, is a warning about something that is not true — and the page
    /// students are already reading is the one it names.
    func testAClassWhoseFlagCarriesAReasonIsNotReportedHeldBack() throws {
        try prepare()
        let course: Course = try makeCourse()
        let page: String = """
        ---
        title: Unit 2, Day 4
        publish: true # covered on Tuesday
        created: 2026-09-08T07:00:00.000-0400
        ---

        Body.
        """
        try page.write(
            to: course.directoryURL
                .appendingPathComponent("section1/All Classes")
                .appendingPathComponent("Unit 2, Day 4.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            ScheduledDeploy.unpublishedClasses(course: course, sectionNumber: 1),
            [],
            "The build publishes this page, so nothing should say it is held back"
        )
    }

    func testAFullyPublishedSectionSaysNothingAboutHeldBackClasses() throws {
        try prepare()
        let course: Course = try makeCourse(publishedClassTitles: ["Unit 2, Day 2"])
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: course, sectionNumber: 1,
            when: sixThirtyTomorrow(), now: Date(),
            cloudflareAccountID: "", inWorkingFolder: workspaceURL
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
            cloudflareAccountID: "", inWorkingFolder: workspaceURL
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

    /// The orange triangle has to say what it means, both on hover and to
    /// anyone listening to the row rather than looking at it.
    ///
    /// What this pins is the SENTENCE. That the sentence is attached to the
    /// triangle is not something a unit test can see; taking the hover text
    /// off the image would leave this green.
    ///
    /// Asked for by Russell on 2026-09-19: the clock beside it has had hover
    /// text since it shipped, and a warning mark that says nothing leaves a
    /// teacher to guess which of the two badges is the bad one.
    func testTheWarningBesideASectionSaysWhatItMeans() throws {
        let tooltip: String = SidebarView.stoppedPublishTooltip()
        XCTAssertTrue(
            tooltip.contains("did not get through"),
            "The hover text has to say what went wrong in words a teacher would use"
        )
        XCTAssertTrue(
            tooltip.contains("Open this section"),
            "And it has to say what to do about it"
        )
        // Rule 1: nothing in the interface names the machinery.
        for word in ["script", "toolchain", "Docker", "container", "launchd", "agent"] {
            XCTAssertFalse(
                tooltip.localizedCaseInsensitiveContains(word),
                "The hover text must not mention \(word)"
            )
        }
    }

    /// Every record the wrapper writes has to LAND in one move.
    ///
    /// The app watches the record folder so a run that finishes while the
    /// teacher is looking at that section shows its notice there and then. A
    /// folder watch sees an entry arrive; it does not see a second line
    /// appended to a file that is already there — measured, 0 of 40 first
    /// events carried a readable record when the wrapper wrote with two
    /// `echo`s, and the completing line produced no event at all. So the record
    /// is assembled in a temporary file beside the folder and moved in.
    ///
    /// **An assertion on generated TEXT, which this file's neighbours rightly
    /// distrust**: `ScheduledPublishOutcomeTests` RUNS the same generated bash
    /// for every kind, and that is what proves the record still says the right
    /// thing. What cannot be tested from here is the timing of the events, and
    /// the behavioural half of that would need a delay injected into the
    /// wrapper — which is the very thing being removed.
    func testTheWrapperWritesEveryRecordInOneMove() throws {
        let home: URL = URL(fileURLWithPath: "/Users/someone")
        let command: String = ScheduledDeploy.oneShotCommand(
            courseCode: "ICS3U",
            sectionNumber: 2,
            workspaceURL: URL(fileURLWithPath: "/Users/someone/Class Websites"),
            deployArgumentsList: [["ICS3U", "2", "--to", "Netlify"]],
            destinationTypes: ["netlify"],
            destinationDescriptions: ["Netlify"],
            homeFolder: home
        )
        let folderID: String = BuildOutputLocation.folderIdentifier(
            forWorkingFolder: "/Users/someone/Class Websites"
        )
        let record: String = ScheduledPublishOutcome.recordURL(
            inHomeFolder: home, course: "ICS3U", section: 2, folderID: folderID
        ).path
        let partial: String = ScheduledPublishOutcome.partialRecordURL(
            inHomeFolder: home, course: "ICS3U", section: 2, folderID: folderID
        ).path

        XCTAssertFalse(
            command.contains(">> '\(record)'"),
            "Nothing may be appended to the record itself — the line that completes it reaches no watcher"
        )
        XCTAssertFalse(
            command.contains("> '\(record)'"),
            "The record must be MOVED into place rather than written there"
        )
        XCTAssertTrue(
            command.contains("/bin/mv '\(partial)' '\(record)'"),
            "The finished record has to be moved into the watched folder in one step"
        )
        // Three places write a record: a build that failed, a destination that
        // failed, and a run that got all the way through.
        var moves: Int = 0
        for line in command.components(separatedBy: "\n") {
            if line.contains("/bin/mv '\(partial)' '\(record)'") {
                moves += 1
            }
        }
        XCTAssertEqual(moves, 3, "Every one of the three record-writing branches must end in the move")
        // The temporary file sits BESIDE the watched folder, not in it: a
        // temporary file inside it is three events, two of them carrying no
        // readable record. See ScheduledPublishOutcome.partialRecordURL.
        XCTAssertEqual(
            URL(fileURLWithPath: partial).deletingLastPathComponent().path,
            URL(fileURLWithPath: record).deletingLastPathComponent()
                .deletingLastPathComponent().path
        )
    }

    // MARK: - One alarm per working folder (#237)

    /// A second working folder beside this test's own, holding the same course.
    func makeSecondWorkingFolder() throws -> URL {
        let second: URL = workspaceURL.deletingLastPathComponent().appendingPathComponent("last-year")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try "#!/usr/bin/env bash\nexit 0\n".write(
            to: second.appendingPathComponent("deploy.sh"), atomically: true, encoding: .utf8
        )
        return second
    }

    /// A course with the same code in another working folder.
    func makeCourse(inWorkingFolder folder: URL) throws -> Course {
        let courseURL: URL = folder.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        let values: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "deploy_target": "netlify",
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let configuration: CourseConfiguration = CourseConfiguration(values: values, lastSavedData: data)
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: configuration)
    }

    /// A job exactly as a release BEFORE #237 wrote it (dev 68214a6c's
    /// `propertyList`): the label with no folder id, and its wrapper beside it.
    @discardableResult
    func writeAgentSetBeforeTheUpdate(
        sectionNumber: Int = 1,
        workingFolder: URL,
        when: Date
    ) throws -> URL {
        let label: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: sectionNumber)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
                ScheduledDeploy.runFlag,
                ScheduledDeploy.scriptURL(label: label).path,
                ScheduledDeploy.sectionFlag,
                workingFolder.path,
                "ICS3U",
                String(sectionNumber),
            ],
            "WorkingDirectory": workingFolder.path,
            "EnvironmentVariables": [
                ScheduledDeploy.scheduledForKey: ISO8601DateFormatter().string(from: when)
            ],
            "StandardOutPath": ScheduledDeploy.logURL(label: label).path,
            "RunAtLoad": false,
        ]
        let plistURL: URL = ScheduledDeploy.plistURL(label: label)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: plistURL)
        let script: URL = ScheduledDeploy.scriptURL(label: label)
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "#!/bin/bash\n".write(to: script, atomically: true, encoding: .utf8)
        return plistURL
    }

    /// THE issue test: the same section scheduled in two working folders is
    /// two alarms, each with its own clock, and scheduling in one boots out
    /// nothing of the other's. Fails with `agentLabel` answering the old
    /// spelling (one file per section for the whole Mac).
    func testTwoWorkingFoldersKeepTheirOwnScheduledDeploy() throws {
        try prepare()
        let thisYear: Course = try makeCourse()
        let second: URL = try makeSecondWorkingFolder()
        let lastYear: Course = try makeCourse(inWorkingFolder: second)
        let early: Date = sixThirtyTomorrow()
        let late: Date = early.addingTimeInterval(2 * 60 * 60)

        XCTAssertNil(ScheduledDeploy.scheduleDeploy(
            course: lastYear, sectionNumber: 1, when: early,
            workspaceURL: second, cloudflareAccountID: "", runner: FakeLaunchControl()
        ))
        let runner: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduledDeploy.scheduleDeploy(
            course: thisYear, sectionNumber: 1, when: late,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))

        let thisLabel: String = ScheduledDeploy.agentLabel(
            courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspaceURL
        )
        let lastLabel: String = ScheduledDeploy.agentLabel(
            courseCode: "ICS3U", sectionNumber: 1, workingFolder: second
        )
        XCTAssertNotEqual(thisLabel, lastLabel)
        let plists: [URL] = try FileManager.default.contentsOfDirectory(
            at: agentsDirectory, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(plists.count, 2, "Scheduling in one folder replaced the other folder's deploy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ScheduledDeploy.scriptURL(label: thisLabel).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ScheduledDeploy.scriptURL(label: lastLabel).path))

        let thisClock: Date = try XCTUnwrap(ScheduledDeploy.nextRun(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL
        ))
        let lastClock: Date = try XCTUnwrap(ScheduledDeploy.nextRun(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: second
        ))
        XCTAssertEqual(thisClock.timeIntervalSince1970, late.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(lastClock.timeIntervalSince1970, early.timeIntervalSince1970, accuracy: 1)
        XCTAssertFalse(
            runner.bootedOutLabels.contains(lastLabel),
            "Scheduling in this folder booted out the other folder's job"
        )

        // Cancelling in one leaves the other.
        XCTAssertNil(ScheduledDeploy.cancelScheduledDeploy(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL, runner: runner
        ))
        XCTAssertNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL))
        XCTAssertNotNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: second))
    }

    /// The label ends with the folder's id — the builds folder's own — and
    /// every path the job carries carries it. Two spellings of one folder
    /// (through a link, and `/var` for `/private/var`) give one label.
    func testTheLabelIsTheFolderItWasSetFrom() throws {
        try prepare()
        let label: String = ScheduledDeploy.agentLabel(
            courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspaceURL
        )
        let folderID: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: workspaceURL.path)
        XCTAssertEqual(
            label, ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1) + "." + folderID
        )
        XCTAssertTrue(label.hasSuffix(".ICS3U.section1.\(folderID)"), label)

        // A link to the folder, and the folder without `/private`.
        let link: URL = workspaceURL.deletingLastPathComponent().appendingPathComponent("a-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: workspaceURL)
        XCTAssertEqual(ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: link), label)
        if workspaceURL.path.hasPrefix("/private/") {
            let short: URL = URL(fileURLWithPath: String(workspaceURL.path.dropFirst("/private".count)))
            XCTAssertEqual(ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: short), label)
        } else if workspaceURL.path.hasPrefix("/var/") {
            let long: URL = URL(fileURLWithPath: "/private" + workspaceURL.path)
            XCTAssertEqual(ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: long), label)
        }

        let home: URL = URL(fileURLWithPath: "/Users/teacher")
        let plist: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: "ICS3U", sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, scheduledTo: []
        )
        XCTAssertEqual(plist["Label"] as? String, label)
        let arguments: [String] = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertTrue(arguments[2].hasSuffix("/\(label).sh"), arguments[2])
        XCTAssertTrue((plist["StandardOutPath"] as? String ?? "").hasSuffix("/\(label).log"))

        let wrapper: String = ScheduledDeploy.oneShotCommand(
            courseCode: "ICS3U", sectionNumber: 1, workspaceURL: workspaceURL,
            deployArgumentsList: [["ICS3U", "1"]], homeFolder: home
        )
        XCTAssertTrue(wrapper.contains(ScheduledDeploy.plistURL(label: label).path))
        XCTAssertTrue(wrapper.contains(ScheduledDeploy.successSentinelURL(label: label, inHomeFolder: home).path))
        XCTAssertTrue(wrapper.contains(ScheduledPublishOutcome.recordURL(
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: folderID
        ).path))
    }

    /// Both spellings of a label read back: before #237 (no id) and after.
    /// The table measured when the plan was written (scratchpad probe, run).
    func testLabelsAreReadBothWays() {
        let prefix: String = ScheduledDeploy.labelPrefix
        let rows: [(label: String, id: String?, code: String?, section: Int?)] = [
            ("\(prefix).ICS3U.section1", nil, "ICS3U", 1),
            ("\(prefix).ICS3U.section1.0a1b2c3d", "0a1b2c3d", "ICS3U", 1),
            ("\(prefix).ICS3U.section12.12345678", "12345678", "ICS3U", 12),
            ("\(prefix).CODING-CLUB.section2.deadbeef", "deadbeef", "CODING-CLUB", 2),
            // Not an id: upper-case hex, seven characters, a non-hex letter.
            ("\(prefix).ICS3U.section1.0A1B2C3D", nil, nil, nil),
            ("\(prefix).ICS3U.section1.0a1b2c3", nil, nil, nil),
            ("\(prefix).ICS3U.section1.0a1b2c3z", nil, nil, nil),
        ]
        for row in rows {
            XCTAssertEqual(ScheduledDeploy.folderID(fromLabel: row.label), row.id, row.label)
            let read = ScheduledDeploy.codeAndSection(fromLabel: row.label)
            XCTAssertEqual(read?.courseCode, row.code, row.label)
            XCTAssertEqual(read?.sectionNumber, row.section, row.label)
        }
    }

    /// A folder the disk cannot be asked about — gone, or on a disk that is
    /// not plugged in — still gets ONE id, the same every time it is asked,
    /// because scheduling and every later reading go through the same
    /// `folderIdentifier`: `FolderIdentity.canonicalPath` falls back to
    /// `realpath`, then to the text as it came in (#237 review, M2).
    func testAFolderThatCannotBeOpenedGetsTheSameIdEveryTime() throws {
        let gone: String = "/Volumes/Not Plugged In \(UUID().uuidString)/Teaching"
        let first: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: gone)
        let second: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: gone)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 8)
        XCTAssertEqual(
            ScheduledDeploy.folderID(fromLabel: ScheduledDeploy.agentLabel(
                courseCode: "ICS3U", sectionNumber: 1, workingFolder: URL(fileURLWithPath: gone)
            )),
            first
        )
    }

    /// A deploy set before the update is left as it is and keeps working:
    /// this folder shows it and cancels it, by the name it really has;
    /// another folder neither shows it nor cancels it. Fails without the
    /// folder scan (a lookup by today's label finds nothing).
    func testADeploySetBeforeTheUpdateStillShowsAndCancels() throws {
        try prepare()
        let second: URL = try makeSecondWorkingFolder()
        let when: Date = sixThirtyTomorrow()
        let plistURL: URL = try writeAgentSetBeforeTheUpdate(workingFolder: workspaceURL, when: when)
        let legacyLabel: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1)

        let shown: Date = try XCTUnwrap(ScheduledDeploy.nextRun(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL
        ))
        XCTAssertEqual(shown.timeIntervalSince1970, when.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: second))

        let runner: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduledDeploy.cancelScheduledDeploy(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: second, runner: runner
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path), "Another folder cancelled it")
        XCTAssertFalse(runner.bootedOutLabels.contains(legacyLabel))

        XCTAssertNil(ScheduledDeploy.cancelScheduledDeploy(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL, runner: runner
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ScheduledDeploy.scriptURL(label: legacyLabel).path))
        XCTAssertEqual(runner.bootedOutLabels.last, legacyLabel, "Booted out by the name it really has")
    }

    /// Rescheduling in the folder that set a deploy before the update retires
    /// that one — or the section would publish twice — and says it replaced
    /// it. The same section's old deploy in ANOTHER folder is left standing.
    func testReschedulingRetiresThisFoldersOldDeployAndNotAnothers() throws {
        try prepare()
        let course: Course = try makeCourse()
        let scratch: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        let old: Date = sixThirtyTomorrow().addingTimeInterval(24 * 60 * 60)
        let legacyPlist: URL = try writeAgentSetBeforeTheUpdate(workingFolder: workspaceURL, when: old)
        let legacyLabel: String = ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1)
        let runner: FakeLaunchControl = FakeLaunchControl()
        let newMoment: Date = sixThirtyTomorrow()

        XCTAssertNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: newMoment,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPlist.path), "Two alarms for one section")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ScheduledDeploy.scriptURL(label: legacyLabel).path))
        XCTAssertTrue(runner.bootedOutLabels.contains(legacyLabel))
        let remaining: [ScheduledDeploy.Agent] = ScheduledDeploy.agents(
            inWorkingFolder: workspaceURL, courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(
            remaining.first?.label,
            ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspaceURL)
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains(ScheduledDeploy.dayAndTimeText(old)), trail)

        // Another folder's old deploy: untouched by scheduling here.
        try FileManager.default.removeItem(at: agentsDirectory)
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        let second: URL = try makeSecondWorkingFolder()
        let theirs: URL = try writeAgentSetBeforeTheUpdate(workingFolder: second, when: old)
        let runner2: FakeLaunchControl = FakeLaunchControl()
        XCTAssertNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: newMoment,
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner2
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: theirs.path))
        XCTAssertFalse(runner2.bootedOutLabels.contains(legacyLabel))
        XCTAssertNotNil(ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: second))
    }

    /// macOS refuses the new job: the old one under the OLD name is handed back,
    /// because its plist is deleted only once the new job is accepted (#237
    /// review, M1). Fails if the retire step deletes before the bootstrap.
    func testARefusedRescheduleHandsTheOldNamedDeployBack() throws {
        try prepare()
        let course: Course = try makeCourse()
        let scratch: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        let old: Date = sixThirtyTomorrow().addingTimeInterval(24 * 60 * 60)
        let legacyPlist: URL = try writeAgentSetBeforeTheUpdate(workingFolder: workspaceURL, when: old)
        let legacyBytes: Data = try Data(contentsOf: legacyPlist)
        let newPlist: URL = ScheduledDeploy.plistURL(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL
        )
        let runner: FakeLaunchControl = FakeLaunchControl()
        runner.refusedPlists = [newPlist]

        XCTAssertNotNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))
        XCTAssertEqual(try Data(contentsOf: legacyPlist), legacyBytes, "The old deploy's plist was lost")
        XCTAssertEqual(runner.bootstrappedURLs, [legacyPlist], "The old deploy was not handed back to macOS")
        XCTAssertFalse(FileManager.default.fileExists(atPath: newPlist.path))
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("still stands"), trail)
        XCTAssertFalse(trail.contains("turned off"), trail)
    }

    /// The rare folder holding BOTH an old-name and a new-name job for one
    /// section (an older copy of the app still running), and macOS refuses
    /// the new one: the new-name job was overwritten and is lost, the
    /// old-name one is handed back. Each trail line names the job it is
    /// about — "still stands" the one that STANDS, "turned off" the one lost —
    /// even when the lost one is the earlier (#237 review, L3).
    func testARefusalInAFolderHoldingBothNamesSaysWhichStands() throws {
        try prepare()
        let course: Course = try makeCourse()
        let scratch: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("trail")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        let lostMoment: Date = sixThirtyTomorrow().addingTimeInterval(12 * 60 * 60)
        let standingMoment: Date = sixThirtyTomorrow().addingTimeInterval(48 * 60 * 60)
        try writeAgentSetBeforeTheUpdate(workingFolder: workspaceURL, when: standingMoment)
        let newPlist: URL = ScheduledDeploy.plistURL(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL
        )
        let current: [String: Any] = ScheduledDeploy.propertyList(
            courseCode: "ICS3U", sectionNumber: 1, when: lostMoment,
            workspaceURL: workspaceURL, scheduledTo: []
        )
        try PropertyListSerialization.data(fromPropertyList: current, format: .xml, options: 0)
            .write(to: newPlist)

        let runner: FakeLaunchControl = FakeLaunchControl()
        runner.refusedPlists = [newPlist]
        XCTAssertNotNil(ScheduledDeploy.scheduleDeploy(
            course: course, sectionNumber: 1, when: sixThirtyTomorrow(),
            workspaceURL: workspaceURL, cloudflareAccountID: "", runner: runner
        ))

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("the one set for \(ScheduledDeploy.dayAndTimeText(standingMoment)) still stands"),
            "The line must name the job that stands: \(trail)"
        )
        XCTAssertFalse(
            trail.contains("the one set for \(ScheduledDeploy.dayAndTimeText(lostMoment)) still stands"),
            "It named the lost job as standing: \(trail)"
        )
        XCTAssertTrue(
            trail.contains("turned off the scheduled deploy set for \(ScheduledDeploy.dayAndTimeText(lostMoment))"),
            "The lost job must be recorded as turned off: \(trail)"
        )
        XCTAssertEqual(
            ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL)?
                .timeIntervalSince1970 ?? 0,
            standingMoment.timeIntervalSince1970, accuracy: 1
        )
    }

    /// The run keys its notes by the label of the script it was started with,
    /// never a rebuilt one: a job set before the update has the OLD label's
    /// log and success note baked in. Its findings are filed under this
    /// folder, where this folder's window reads them and another's does not.
    /// Fails if `recordScheduledPublish` rebuilds today's label.
    func testTheRunReadsTheNotesOfTheLabelItWasStartedWith() throws {
        try prepare()
        let course: Course = try makeCourse()
        let second: URL = try makeSecondWorkingFolder()
        let home: URL = agentsDirectory.deletingLastPathComponent().appendingPathComponent("home")
        let section: (courseDirectory: URL, courseCode: String, sectionNumber: Int) =
            (course.directoryURL, "ICS3U", 1)
        let marker: String = "PLANTOIR_HEALTH: {\"name\": \"mediaFolderMissing\", \"sentence\": \"s\", "
            + "\"detail\": \"d\", \"fixable\": false, \"course\": \"ICS3U\", \"section\": 1}\n"

        let labels: [String] = [
            ScheduledDeploy.legacyAgentLabel(courseCode: "ICS3U", sectionNumber: 1),
            ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: workspaceURL),
        ]
        for label in labels {
            let sentinel: URL = ScheduledDeploy.successSentinelURL(label: label, inHomeFolder: home)
            try FileManager.default.createDirectory(
                at: sentinel.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try "netlify\n".write(to: sentinel, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(
                at: SectionPublishState.stampURL(courseDirectory: course.directoryURL, sectionNumber: 1)
            )
            ScheduledDeploy.recordScheduledPublish(
                label: label, section: section, fingerprint: "abc", inHomeFolder: home
            )
            XCTAssertEqual(
                SectionPublishState.stamp(courseDirectory: course.directoryURL, sectionNumber: 1)?.fingerprint,
                "abc", "A good run of \(label) was not recorded as published"
            )

            let log: URL = ScheduledDeploy.logURL(label: label, inHomeFolder: home)
            try FileManager.default.createDirectory(
                at: log.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try ("last night\n").write(to: log, atomically: true, encoding: .utf8)
            let before: UInt64 = ScheduledDeploy.logSize(label: label, inHomeFolder: home)
            XCTAssertEqual(before, UInt64("last night\n".utf8.count))
            try ("last night\n" + marker).write(to: log, atomically: true, encoding: .utf8)
            ScheduledDeploy.recordFolderProblems(
                label: label, section: section, fromByteOffset: before, inHomeFolder: home
            )
            XCTAssertTrue(ScheduledDeploy.takeFolderProblems(
                courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: second, inHomeFolder: home
            ).isEmpty, "Another working folder took this folder's findings")
            XCTAssertEqual(ScheduledDeploy.takeFolderProblems(
                courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workspaceURL, inHomeFolder: home
            ).count, 1, "The findings of \(label) did not reach this folder")
        }
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

    /// Plists it refuses whatever `bootstrapFailure` says, so a test can have
    /// macOS turn down the NEW job and take an old one back (#237).
    var refusedPlists: [URL] = []

    // MARK: - Functions

    func bootstrap(plistURL: URL) -> String? {
        if let bootstrapFailure {
            return bootstrapFailure
        }
        if refusedPlists.contains(plistURL) {
            return "Bootstrap failed: 5: Input/output error"
        }
        bootstrappedURLs.append(plistURL)
        return nil
    }

    func bootOut(label: String) {
        bootedOutLabels.append(label)
    }
}
