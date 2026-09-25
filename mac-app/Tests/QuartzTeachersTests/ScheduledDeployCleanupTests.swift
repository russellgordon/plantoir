import XCTest
@testable import QuartzTeachers

/// A scheduled deploy must not outlive the course it was set for.
///
/// Nothing here goes near the real launchd. Agents are written into a folder of
/// the test's own through `ScheduledDeploy.launchAgentsDirectoryOverride`, and
/// `launchctl` is stood in for by `FakeLaunchControl` — which, since
/// 2026-09-20, is no longer only a convention: `LaunchControl.run` refuses
/// outright while that override is set, so a test that forgot the stand-in
/// would fail rather than boot out and delete the ICS3U schedule of whoever
/// ran the suite. `testTheRealLaunchControlRefusesWhileATestIsDriving` pins
/// that.
@MainActor
final class ScheduledDeployCleanupTests: XCTestCase {

    // MARK: - Stored properties

    /// The temporary stand-in for `~/Library/LaunchAgents`.
    var agentsDirectory: URL = URL(fileURLWithPath: "/")

    /// A working folder with `courses/` inside it.
    var workingFolderURL: URL = URL(fileURLWithPath: "/")

    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")

    /// Where trail lines go while a test is running.
    var trailFolderURL: URL = URL(fileURLWithPath: "/")

    var launchControl: FakeLaunchControl = FakeLaunchControl()

    // MARK: - Computed properties

    /// The working folder's id, which its records and new labels carry (#237).
    var folderID: String {
        return BuildOutputLocation.folderIdentifier(forWorkingFolder: workingFolderURL.path)
    }

    // MARK: - Functions

    /// A working folder, an agents folder and a throwaway trail.
    ///
    /// Called at the top of each test rather than from `setUpWithError()`, the
    /// way `ScheduledDeployTests` does it and for the same reason: the
    /// overrides XCTest offers are nonisolated and everything here is
    /// main-actor isolated.
    func prepare() throws {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deploy-cleanup-\(UUID().uuidString)")
        agentsDirectory = root.appendingPathComponent("LaunchAgents")
        workingFolderURL = root.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        trailFolderURL = root.appendingPathComponent("trail")
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)

        ScheduledDeploy.launchAgentsDirectoryOverride = agentsDirectory
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            agentsDirectory.deletingLastPathComponent().appendingPathComponent("scheduled")
        launchControl = FakeLaunchControl()
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolderURL)
        let agentsPath: String = agentsDirectory.path
        addTeardownBlock {
            MainActor.assumeIsolated {
                ScheduledDeploy.launchAgentsDirectoryOverride = nil
                ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
                ActivityTrail.store = previousStore
            }
            // Put a folder this test made read-only back, or the whole
            // temporary tree survives the run.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: agentsPath
            )
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A course on disk, with a settings file the real readers can read.
    @discardableResult
    func makeCourse(
        code: String = "ICS3U",
        sections: [Int] = [1, 2],
        mayRunLateDays: Int? = nil,
        in coursesURL: URL? = nil
    ) throws -> Course {
        let root: URL = coursesURL ?? coursesDirectoryURL
        let courseURL: URL = root.appendingPathComponent(code)
        for sectionNumber in sections {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent("section\(sectionNumber)"),
                withIntermediateDirectories: true
            )
            try Data("# lesson\n".utf8).write(
                to: courseURL
                    .appendingPathComponent("section\(sectionNumber)")
                    .appendingPathComponent("index.md")
            )
        }
        var values: [String: Any] = [
            "course_code": code,
            "course_name": "Introduction to Computer Science",
            "section_numbers": sections,
            "num_sections": sections.count,
        ]
        if let mayRunLateDays {
            values["scheduled_deploy_may_run_late_days"] = mayRunLateDays
        }
        let data: Data = try JSONSerialization.data(withJSONObject: values)
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let configuration: CourseConfiguration = CourseConfiguration(values: values, lastSavedData: data)
        return Course(code: code, directoryURL: courseURL, configuration: configuration)
    }

    /// Which label an agent a test writes carries.
    enum Labelled {
        /// `…section<N>.<folder id>`, what this release writes (#237).
        case current
        /// `…section<N>`, what every release before #237 wrote — still on
        /// teachers' Macs, recognised and never migrated.
        case beforeFolderScoping
    }

    /// The label a test agent carries.
    func labelFor(
        courseCode: String = "ICS3U",
        sectionNumber: Int,
        workingFolder: URL? = nil,
        labelled: Labelled = .current
    ) -> String {
        switch labelled {
        case .current:
            return ScheduledDeploy.agentLabel(
                courseCode: courseCode, sectionNumber: sectionNumber,
                workingFolder: workingFolder ?? workingFolderURL
            )
        case .beforeFolderScoping:
            return ScheduledDeploy.legacyAgentLabel(courseCode: courseCode, sectionNumber: sectionNumber)
        }
    }

    /// One agent on disk, exactly as `propertyList` writes one.
    ///
    /// `legacy` writes what a v1.1.0 build wrote: three `ProgramArguments`, no
    /// `--scheduled-section`, so the course code can only come back out of the
    /// label. `labelled` chooses the label spelling (#237) — a v1.1.0 plist is
    /// necessarily `.beforeFolderScoping` too.
    func writeAgent(
        courseCode: String = "ICS3U",
        sectionNumber: Int,
        workingFolder: URL? = nil,
        when: Date? = Date().addingTimeInterval(3600),
        legacy: Bool = false,
        labelled: Labelled = .current
    ) throws {
        let folder: URL = workingFolder ?? workingFolderURL
        let label: String = labelFor(
            courseCode: courseCode, sectionNumber: sectionNumber, workingFolder: folder,
            labelled: legacy ? .beforeFolderScoping : labelled
        )
        var plist: [String: Any] = [:]
        plist["Label"] = label
        plist["WorkingDirectory"] = folder.path
        if legacy {
            plist["ProgramArguments"] = ["/Applications/Plantoir.app/Contents/MacOS/Plantoir", ScheduledDeploy.runFlag, "/tmp/\(label).sh"]
        } else {
            plist["ProgramArguments"] = [
                "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
                ScheduledDeploy.runFlag,
                "/tmp/\(label).sh",
                ScheduledDeploy.sectionFlag,
                folder.path,
                courseCode,
                String(sectionNumber),
            ]
        }
        if let when {
            plist["EnvironmentVariables"] = [
                ScheduledDeploy.scheduledForKey: ISO8601DateFormatter().string(from: when)
            ]
        }
        let data: Data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try data.write(to: agentsDirectory.appendingPathComponent("\(label).plist"))
    }

    func agentExists(
        courseCode: String = "ICS3U",
        sectionNumber: Int,
        workingFolder: URL? = nil,
        labelled: Labelled = .current
    ) -> Bool {
        let label: String = labelFor(
            courseCode: courseCode, sectionNumber: sectionNumber, workingFolder: workingFolder,
            labelled: labelled
        )
        return FileManager.default.fileExists(
            atPath: agentsDirectory.appendingPathComponent("\(label).plist").path
        )
    }

    /// A second working folder beside this test's own.
    func makeOtherWorkingFolder() throws -> URL {
        let otherFolder: URL = workingFolderURL
            .deletingLastPathComponent()
            .appendingPathComponent("other-workspace")
        try FileManager.default.createDirectory(
            at: otherFolder.appendingPathComponent("courses"), withIntermediateDirectories: true
        )
        return otherFolder
    }

    func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    // MARK: - The contract's cases, run

    /// Every case in `scheduledDeployCancellation.cases`, played through the
    /// real removal or rename.
    ///
    /// An unknown `act` FAILS rather than being skipped: a case added to the
    /// contract — from either platform — has to be implemented here or said to
    /// be unrunnable, never quietly walked past.
    func testEveryCancellationCaseInTheContractHolds() throws {
        let rule: [String: Any] = try Self.section("scheduledDeployCancellation")
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15, "The case list has lost cases.")

        for oneCase in cases {
            let act: String = try XCTUnwrap(oneCase["act"] as? String)
            let cancels: String = try XCTUnwrap(oneCase["cancels"] as? String)
            let provedBy: String = try XCTUnwrap(oneCase["provedBy"] as? String)
            XCTAssertNotNil(oneCase["why"] as? String, "\(act) has no 'why'")

            if provedBy == "sourceHasNoCancel" {
                let source: String = try XCTUnwrap(oneCase["source"] as? String)
                let symbol: String = try XCTUnwrap(oneCase["symbol"] as? String)
                XCTAssertEqual(cancels, "nothing", "\(act) is proved by a source scan and must cancel nothing")
                try assertNoCancelAfter(symbol: symbol, inSource: source, forCase: act)
                continue
            }
            XCTAssertEqual(provedBy, "run", "Unknown provedBy for: \(act)")
            try run(cancellationCase: act, expecting: cancels)
        }
    }

    /// One `provedBy: "run"` case.
    private func run(cancellationCase act: String, expecting cancels: String) throws {
        try prepare()
        switch act {
        case "remove one section of a course that has more than one":
            let course: Course = try makeCourse()
            try writeAgent(sectionNumber: 1)
            try writeAgent(sectionNumber: 2)
            let result = ScheduledDeployCleanup.removeSection(
                2, from: course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
            )
            XCTAssertTrue(result.didRemove, act)
            XCTAssertEqual(result.stoppedSections, [2], act)
            XCTAssertTrue(agentExists(sectionNumber: 1), "\(act): section 1's deploy must stand")
            XCTAssertFalse(agentExists(sectionNumber: 2), act)
            XCTAssertEqual(cancels, "thatSectionOnly")

        case "a course kept for reference is met when the working folder is read":
            // The marker can arrive by hand, or from another Mac, on a course
            // that was live yesterday and still owns its alarms.
            let course: Course = try makeCourse()
            course.configuration.keptForReference = true
            try course.configuration.write(to: course.configFileURL)
            try writeAgent(sectionNumber: 1)
            try writeAgent(sectionNumber: 2)
            ReferenceCourseUpkeep.bringUpToDate(
                [course], inWorkingFolder: workingFolderURL, runner: launchControl
            )
            XCTAssertFalse(agentExists(sectionNumber: 1), act)
            XCTAssertFalse(agentExists(sectionNumber: 2), act)
            XCTAssertTrue(
                trailText().contains("because the course is kept for reference"),
                "\(act): the trail has to say why the alarm went."
            )
            XCTAssertEqual(cancels, "everyAlarmThisFolderHasForTheCourse")
            ReferenceLock.unlock(courseDirectory: course.directoryURL)

        case "remove a whole course":
            let course: Course = try makeCourse()
            try writeAgent(sectionNumber: 1)
            try writeAgent(sectionNumber: 2)
            let result = ScheduledDeployCleanup.removeCourse(
                course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
            )
            XCTAssertTrue(result.didRemove, act)
            XCTAssertEqual(result.stoppedSections, [1, 2], act)
            XCTAssertFalse(agentExists(sectionNumber: 1), act)
            XCTAssertFalse(agentExists(sectionNumber: 2), act)
            XCTAssertEqual(cancels, "everyAlarmThisFolderHasForTheCourse")

        case "remove the only section of a course":
            // The sidebar turns this into a course removal, and it is that
            // call the test makes — the same one `prepareRemoval` builds a
            // course-shaped `RemovalRequest` for.
            let course: Course = try makeCourse(sections: [1])
            try writeAgent(sectionNumber: 1)
            let result = ScheduledDeployCleanup.removeCourse(
                course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
            )
            XCTAssertTrue(result.didRemove, act)
            XCTAssertEqual(result.stoppedSections, [1], act)
            XCTAssertFalse(agentExists(sectionNumber: 1), act)
            XCTAssertEqual(cancels, "everyAlarmThisFolderHasForTheCourse")

        case "remove a course whose code also exists in another working folder":
            // THE ONE THAT MUST NOT REGRESS. One alarm exists Mac-wide for
            // ICS3U section 1, and it belongs to the OTHER folder. Written
            // under the label every release before #237 used — the one name a
            // section had for the whole Mac, which is where a lookup by NAME
            // would find it from this folder too.
            let otherFolder: URL = workingFolderURL
                .deletingLastPathComponent()
                .appendingPathComponent("other-workspace")
            try FileManager.default.createDirectory(
                at: otherFolder.appendingPathComponent("courses"), withIntermediateDirectories: true
            )
            let course: Course = try makeCourse(sections: [1])
            try writeAgent(sectionNumber: 1, workingFolder: otherFolder, labelled: .beforeFolderScoping)
            let result = ScheduledDeployCleanup.removeCourse(
                course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
            )
            XCTAssertTrue(result.didRemove, act)
            XCTAssertEqual(result.stoppedSections, [], act)
            XCTAssertTrue(
                agentExists(sectionNumber: 1, labelled: .beforeFolderScoping),
                "\(act): the other folder's live deploy was destroyed"
            )
            XCTAssertEqual(launchControl.bootedOutLabels, [], act)
            XCTAssertEqual(cancels, "nothing")

        case "roll a section over onto a new website":
            // Driven at the seam the rollover itself uses — the gate that
            // decides whether anything of THIS folder's is there to turn off.
            // The tool end to end is
            // `RolloverWebsiteTests.testStartingANewWebsiteTurnsOffAScheduledPublish`
            // and its other-folder twin; what is pinned here is that the
            // contract's case has something behind it at all, which is what
            // this path lacked when the rule first landed.
            _ = try makeCourse(sections: [1, 2])
            try writeAgent(sectionNumber: 1)
            try writeAgent(sectionNumber: 2)
            let owned: [ScheduledDeploy.Agent] = ScheduledDeployCleanup.agentsOwnedBy(
                courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workingFolderURL
            )
            XCTAssertEqual(owned.count, 1, act)
            XCTAssertNil(
                ScheduledDeploy.cancelScheduledDeploy(
                    courseCode: "ICS3U",
                    sectionNumber: 1,
                    inWorkingFolder: workingFolderURL,
                    runner: launchControl
                ),
                act
            )
            XCTAssertFalse(agentExists(sectionNumber: 1), act)
            XCTAssertTrue(agentExists(sectionNumber: 2), "\(act): only that section's")
            XCTAssertEqual(cancels, "thatSectionOnly")

        case "rename a course":
            let course: Course = try makeCourse()
            try writeAgent(sectionNumber: 1)
            try writeAgent(sectionNumber: 2)
            let outcome = try CourseRenamer.rename(
                course,
                to: "ICS4U",
                coursesDirectoryURL: coursesDirectoryURL,
                existingCodes: ["ICS3U"],
                runner: launchControl
            )
            XCTAssertEqual(outcome.stoppedScheduledSections, [1, 2], act)
            XCTAssertFalse(agentExists(sectionNumber: 1), act)
            XCTAssertFalse(agentExists(sectionNumber: 2), act)
            XCTAssertEqual(cancels, "everyAlarmThisFolderHasForTheCourse")

        case "schedule a section whose code and number another working folder has also scheduled":
            let course: Course = try makeCourse(sections: [1])
            try Data("#!/bin/bash\n".utf8).write(to: workingFolderURL.appendingPathComponent("deploy.sh"))
            let otherFolder: URL = try makeOtherWorkingFolder()
            try writeAgent(sectionNumber: 1, workingFolder: otherFolder)
            XCTAssertNil(ScheduledDeploy.scheduleDeploy(
                course: course, sectionNumber: 1, when: Date().addingTimeInterval(7200),
                workspaceURL: workingFolderURL, cloudflareAccountID: "", runner: launchControl
            ), act)
            XCTAssertTrue(agentExists(sectionNumber: 1, workingFolder: otherFolder), "\(act): theirs went")
            XCTAssertTrue(agentExists(sectionNumber: 1), "\(act): ours was not set")
            XCTAssertFalse(
                launchControl.bootedOutLabels.contains(labelFor(sectionNumber: 1, workingFolder: otherFolder)), act
            )
            XCTAssertEqual(cancels, "nothing")

        case "schedule a section this working folder has already scheduled":
            let course: Course = try makeCourse(sections: [1, 2])
            try Data("#!/bin/bash\n".utf8).write(to: workingFolderURL.appendingPathComponent("deploy.sh"))
            try writeAgent(sectionNumber: 1)
            try writeAgent(sectionNumber: 2)
            let later: Date = Date().addingTimeInterval(7200)
            XCTAssertNil(ScheduledDeploy.scheduleDeploy(
                course: course, sectionNumber: 1, when: later,
                workspaceURL: workingFolderURL, cloudflareAccountID: "", runner: launchControl
            ), act)
            XCTAssertEqual(
                ScheduledDeploy.agents(inWorkingFolder: workingFolderURL, courseCode: "ICS3U", sectionNumber: 1).count,
                1, "\(act): two alarms for one section"
            )
            XCTAssertTrue(agentExists(sectionNumber: 2), "\(act): only that section's")
            XCTAssertEqual(
                ScheduledDeploy.nextRun(courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workingFolderURL)?
                    .timeIntervalSince1970 ?? 0,
                later.timeIntervalSince1970, accuracy: 1, act
            )
            XCTAssertEqual(cancels, "thatSectionOnly")

        case "schedule a section this working folder scheduled before deploys were kept per working folder":
            let course: Course = try makeCourse(sections: [1, 2])
            try Data("#!/bin/bash\n".utf8).write(to: workingFolderURL.appendingPathComponent("deploy.sh"))
            try writeAgent(sectionNumber: 1, labelled: .beforeFolderScoping)
            try writeAgent(sectionNumber: 2, labelled: .beforeFolderScoping)
            let otherFolder: URL = try makeOtherWorkingFolder()
            try writeAgent(courseCode: "MCV4U", sectionNumber: 1, workingFolder: otherFolder, labelled: .beforeFolderScoping)
            XCTAssertNil(ScheduledDeploy.scheduleDeploy(
                course: course, sectionNumber: 1, when: Date().addingTimeInterval(7200),
                workspaceURL: workingFolderURL, cloudflareAccountID: "", runner: launchControl
            ), act)
            XCTAssertFalse(agentExists(sectionNumber: 1, labelled: .beforeFolderScoping), "\(act): two alarms")
            XCTAssertTrue(agentExists(sectionNumber: 1), act)
            XCTAssertTrue(agentExists(sectionNumber: 2, labelled: .beforeFolderScoping), "\(act): only that section's")
            XCTAssertTrue(
                agentExists(courseCode: "MCV4U", sectionNumber: 1, workingFolder: otherFolder, labelled: .beforeFolderScoping),
                act
            )
            XCTAssertEqual(cancels, "thatSectionOnly")

        case "remove a course that another working folder has also scheduled":
            let course: Course = try makeCourse(sections: [1])
            let otherFolder: URL = try makeOtherWorkingFolder()
            try writeAgent(sectionNumber: 1)
            try writeAgent(sectionNumber: 1, workingFolder: otherFolder)
            let result = ScheduledDeployCleanup.removeCourse(
                course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
            )
            XCTAssertTrue(result.didRemove, act)
            XCTAssertEqual(result.stoppedSections, [1], act)
            XCTAssertFalse(agentExists(sectionNumber: 1), act)
            XCTAssertTrue(agentExists(sectionNumber: 1, workingFolder: otherFolder), "\(act): theirs went")
            XCTAssertEqual(cancels, "everyAlarmThisFolderHasForTheCourse")

        case "remove a course whose deploy was scheduled before deploys were kept per working folder":
            let course: Course = try makeCourse(sections: [1, 2])
            try writeAgent(sectionNumber: 1, labelled: .beforeFolderScoping)
            try writeAgent(sectionNumber: 2)
            let result = ScheduledDeployCleanup.removeCourse(
                course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
            )
            XCTAssertTrue(result.didRemove, act)
            XCTAssertEqual(result.stoppedSections, [1, 2], act)
            XCTAssertFalse(agentExists(sectionNumber: 1, labelled: .beforeFolderScoping), act)
            XCTAssertFalse(agentExists(sectionNumber: 2), act)
            XCTAssertTrue(
                launchControl.bootedOutLabels.contains(labelFor(sectionNumber: 1, labelled: .beforeFolderScoping)),
                "\(act): booted out by the name it really has"
            )
            XCTAssertEqual(cancels, "everyAlarmThisFolderHasForTheCourse")

        default:
            XCTFail(
                "contracts/shared-rules.json → scheduledDeployCancellation.cases has a case this "
                + "suite does not run: \"\(act)\". Implement it here, or mark it "
                + "provedBy: \"sourceHasNoCancel\" — a case nobody runs is documentation with a "
                + ".json extension."
            )
        }
    }

    /// A `provedBy: "sourceHasNoCancel"` case: the named symbol's own file
    /// must not have learned to cancel a scheduled deploy.
    ///
    /// It cannot prove the act is harmless — only that nobody has since taught
    /// it to cancel, which is the regression worth catching. Restoring a
    /// backup replaces a course's CONTENTS in place, so its schedule still
    /// means what it meant, and a cancel appearing there would be a silent
    /// loss.
    private func assertNoCancelAfter(symbol: String, inSource source: String, forCase act: String) throws {
        let fileURL: URL = Self.productSourceFolderURL().appendingPathComponent("Models/\(source)")
        let text: String = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(
            text.contains(symbol),
            "\(act): \(source) no longer contains \(symbol) — the contract names something that "
            + "has moved."
        )
        XCTAssertFalse(
            text.contains("cancelScheduledDeploy") || text.contains("ScheduledDeployCleanup.cancel"),
            "\(act): \(source) has learned to cancel a scheduled deploy. The contract says it "
            + "cancels nothing, and gives the reason."
        )
    }

    // MARK: - How late is too late

    func testEveryLatenessCaseInTheContractHolds() throws {
        let rule: [String: Any] = try Self.section("scheduledDeployCancellation")
        let lateness: [String: Any] = try XCTUnwrap(rule["howLateIsTooLate"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(lateness["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10, "The lateness case list has lost cases.")

        let now: Date = Date()
        for oneCase in cases {
            let name: String = try XCTUnwrap(oneCase["name"] as? String)
            let chosenDays: Int = try XCTUnwrap(oneCase["chosenDays"] as? Int)
            let expectRuns: Bool = try XCTUnwrap(oneCase["expectRuns"] as? Bool)

            var moment: Date?
            if oneCase["momentIsUnknown"] as? Bool != true {
                let lateBy: NSNumber = try XCTUnwrap(oneCase["lateBySeconds"] as? NSNumber)
                moment = now.addingTimeInterval(-lateBy.doubleValue)
            }
            XCTAssertEqual(
                ScheduledDeployLateness.mayStillRun(
                    intendedMoment: moment, now: now, allowedDays: chosenDays
                ),
                expectRuns,
                "\(name): the contract says this \(expectRuns ? "runs" : "stands down")."
            )
        }
    }

    /// Exactly at the window is still allowed, and one second past it is not.
    ///
    /// The boundary rather than the middle: every case in the contract is
    /// comfortably one side or the other, and a `<` written where `<=` was
    /// meant would pass all of them.
    func testTheWindowsOwnBoundary() {
        let now: Date = Date()
        let week: TimeInterval = ScheduledDeployLateness.allowedLateness(days: 7)
        XCTAssertTrue(ScheduledDeployLateness.mayStillRun(
            intendedMoment: now.addingTimeInterval(-week), now: now, allowedDays: 7
        ))
        XCTAssertFalse(ScheduledDeployLateness.mayStillRun(
            intendedMoment: now.addingTimeInterval(-week - 1), now: now, allowedDays: 7
        ))
    }

    // MARK: - The setting

    func testEveryStoredValueCaseInTheContractHolds() throws {
        let rule: [String: Any] = try Self.section("scheduledDeployCancellation")
        let setting: [String: Any] = try XCTUnwrap(rule["theSetting"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(setting["storedValueCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7, "The stored-value case list has lost cases.")

        for oneCase in cases {
            let means: Int = try XCTUnwrap(oneCase["means"] as? Int)
            let stored: Int? = oneCase["stored"] as? Int
            XCTAssertEqual(
                ScheduledDeployLateness.days(fromStoredValue: stored),
                means,
                "A stored \(String(describing: stored)) must mean \(means)."
            )
        }
    }

    /// The key, the offered values and the default are the contract's, in both
    /// of the two places the app spells them.
    func testTheSettingMatchesTheContract() throws {
        let rule: [String: Any] = try Self.section("scheduledDeployCancellation")
        let setting: [String: Any] = try XCTUnwrap(rule["theSetting"] as? [String: Any])
        XCTAssertEqual(
            ScheduledDeployLateness.configurationKey, setting["key"] as? String
        )
        XCTAssertEqual(
            ScheduledDeployLateness.offeredDays, setting["offered"] as? [Int]
        )
        XCTAssertEqual(
            ScheduledDeployLateness.defaultDays, setting["default"] as? Int
        )
        // The OTHER spelling: `CourseConfiguration` reads the key as a literal
        // so the config-key scanner can see it, and the two must agree.
        let source: String = try String(
            contentsOf: Self.productSourceFolderURL()
                .appendingPathComponent("Models/CourseConfiguration.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("forKey: \"\(ScheduledDeployLateness.configurationKey)\""),
            "CourseConfiguration must read the key by its literal name, or "
            + "FileFormatsContractTests cannot count it."
        )
    }

    /// It round-trips through the settings object, and an out-of-range value
    /// is normalised on the way IN as well as on the way out.
    func testTheSettingRoundTripsAndNormalises() throws {
        try prepare()
        let course: Course = try makeCourse()
        XCTAssertEqual(course.configuration.scheduledDeployMayRunLateDays, 7)
        course.configuration.scheduledDeployMayRunLateDays = 3
        XCTAssertEqual(course.configuration.scheduledDeployMayRunLateDays, 3)
        course.configuration.scheduledDeployMayRunLateDays = 99
        XCTAssertEqual(course.configuration.scheduledDeployMayRunLateDays, 7)
        try course.configuration.write(to: course.configFileURL)

        // And the value written is what the FIRE-TIME reader, which loads no
        // CourseConfiguration at all, reads back.
        XCTAssertEqual(
            ScheduledDeployLateness.days(forCourseCode: "ICS3U", inWorkingFolder: workingFolderURL),
            7
        )
    }

    /// The window comes out of the course's own file, and a course that is not
    /// there means the default rather than a refusal.
    func testTheWindowIsReadFromTheCoursesOwnFile() throws {
        try prepare()
        try makeCourse(code: "ICS3U", sections: [1], mayRunLateDays: 1)
        XCTAssertEqual(
            ScheduledDeployLateness.days(forCourseCode: "ICS3U", inWorkingFolder: workingFolderURL), 1
        )
        XCTAssertEqual(
            ScheduledDeployLateness.days(forCourseCode: "GONE", inWorkingFolder: workingFolderURL),
            ScheduledDeployLateness.defaultDays
        )
    }

    // MARK: - The sentences

    /// Every sentence a teacher reads here is the contract's, filled in.
    func testTheSentencesAreTheContractsOwn() throws {
        let rule: [String: Any] = try Self.section("scheduledDeployCancellation")
        let wording: [String: Any] = try XCTUnwrap(rule["wording"] as? [String: Any])

        func filled(_ key: String) throws -> String {
            let template: String = try XCTUnwrap(
                wording[key] as? String, "No wording.\(key) in the contract"
            )
            return template
                .replacingOccurrences(of: "{course}", with: "ICS3U")
                .replacingOccurrences(of: "{section}", with: "1")
                .replacingOccurrences(of: "{reason}", with: "the disk is full")
        }

        XCTAssertEqual(
            ScheduledDeployCleanup.warningForRemovingASection(sectionNumber: 1),
            try filled("confirmationSectionRemoved")
        )
        XCTAssertEqual(
            ScheduledDeployCleanup.warningForRemovingACourse(courseCode: "ICS3U", sections: [1]),
            try filled("confirmationCourseRemovedOneSection")
                .replacingOccurrences(of: "{sections}", with: "Section 1")
        )
        XCTAssertEqual(
            ScheduledDeployCleanup.warningForRemovingACourse(courseCode: "ICS3U", sections: [1, 2]),
            try filled("confirmationCourseRemovedSeveralSections")
                .replacingOccurrences(of: "{sections}", with: "Sections 1 and 2")
        )
        XCTAssertEqual(
            ScheduledDeployCleanup.couldNotTurnItOff(courseCode: "ICS3U", sections: [1]),
            try filled("couldNotTurnItOffOneSection")
                .replacingOccurrences(of: "{sections}", with: "Section 1")
        )
        XCTAssertEqual(
            ScheduledDeployCleanup.couldNotTurnItOff(courseCode: "ICS3U", sections: [1, 2]),
            try filled("couldNotTurnItOffSeveralSections")
                .replacingOccurrences(of: "{sections}", with: "Sections 1 and 2")
        )
        XCTAssertEqual(
            ScheduledDeployCleanup.removalFailedAfterTurningItOff(
                courseCode: "ICS3U", sections: [1], reason: "the disk is full"
            ),
            try filled("removalFailedAfterTurningItOffOneSection")
                .replacingOccurrences(of: "{sections}", with: "Section 1")
        )
        XCTAssertEqual(
            ScheduledDeployCleanup.removalFailedAfterTurningItOff(
                courseCode: "ICS3U", sections: [1, 2], reason: "the disk is full"
            ),
            try filled("removalFailedAfterTurningItOffSeveralSections")
                .replacingOccurrences(of: "{sections}", with: "Sections 1 and 2")
        )
        XCTAssertEqual(ScheduledDeployLateness.settingTitle, wording["settingTitle"] as? String)
        XCTAssertEqual(ScheduledDeployLateness.settingCaption, wording["settingCaption"] as? String)

        let choices: [String: Any] = try XCTUnwrap(wording["settingChoices"] as? [String: Any])
        for offered in ScheduledDeployLateness.offeredDays {
            XCTAssertEqual(
                ScheduledDeployLateness.choiceLabel(days: offered),
                choices["\(offered)"] as? String,
                "The label for \(offered) days and the contract disagree."
            )
        }
    }

    /// Rule 1: none of these sentences names the machinery behind them.
    func testNoSentenceNamesTheMachinery() throws {
        let rule: [String: Any] = try Self.section("scheduledDeployCancellation")
        let wording: [String: Any] = try XCTUnwrap(rule["wording"] as? [String: Any])
        let banned: [String] = ["launchd", "plist", "agent", "launchctl", "scheduler", "job"]
        for (key, value) in wording {
            guard let sentence = value as? String else {
                continue
            }
            if key == "rule" || key == "machineryCheck" {
                // Notes to whoever implements this, not sentences a teacher
                // reads — they are allowed to name the machinery.
                continue
            }
            for word in banned {
                XCTAssertFalse(
                    sentence.lowercased().contains(word),
                    "wording.\(key) says “\(word)”, which is machinery a teacher never sees."
                )
            }
        }
        // And the sentence the stand-down shows, which lives with the other
        // scheduled-publish sentences rather than here.
        let stopped: [String: Any] = try Self.section("scheduledPublishStopped")
        let sentences: [String: Any] = try XCTUnwrap(stopped["sentences"] as? [String: Any])
        let standDown: String = try XCTUnwrap(sentences["tooLateToRun"] as? String)
        for word in banned {
            XCTAssertFalse(standDown.lowercased().contains(word), "tooLateToRun says “\(word)”")
        }
    }

    // MARK: - The confirmation

    /// The extra sentence appears only when something really IS scheduled in
    /// THIS working folder.
    func testTheConfirmationWarnsOnlyWhenThereIsSomethingToWarnAbout() throws {
        try prepare()
        try makeCourse()
        XCTAssertNil(ScheduledDeployCleanup.warningForConfirmation(
            courseCode: "ICS3U", sectionNumber: nil, inWorkingFolder: workingFolderURL
        ))

        try writeAgent(sectionNumber: 2)
        XCTAssertEqual(
            ScheduledDeployCleanup.warningForConfirmation(
                courseCode: "ICS3U", sectionNumber: 2, inWorkingFolder: workingFolderURL
            ),
            ScheduledDeployCleanup.warningForRemovingASection(sectionNumber: 2)
        )
        XCTAssertEqual(
            ScheduledDeployCleanup.warningForConfirmation(
                courseCode: "ICS3U", sectionNumber: nil, inWorkingFolder: workingFolderURL
            ),
            ScheduledDeployCleanup.warningForRemovingACourse(courseCode: "ICS3U", sections: [2])
        )
        // Section 1 has nothing scheduled, so removing it promises nothing.
        XCTAssertNil(ScheduledDeployCleanup.warningForConfirmation(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workingFolderURL
        ))
    }

    /// A promise about ANOTHER working folder's deploy is a promise Plantoir
    /// will not keep, so it is never made.
    func testTheConfirmationSaysNothingAboutAnotherFoldersDeploy() throws {
        try prepare()
        try makeCourse()
        let otherFolder: URL = workingFolderURL
            .deletingLastPathComponent().appendingPathComponent("other-workspace")
        try writeAgent(sectionNumber: 1, workingFolder: otherFolder)
        XCTAssertNil(ScheduledDeployCleanup.warningForConfirmation(
            courseCode: "ICS3U", sectionNumber: nil, inWorkingFolder: workingFolderURL
        ))
    }

    // MARK: - When it goes wrong

    /// A cancel that fails stops the removal, and says so.
    ///
    /// The course is still there afterwards, and that is the whole point: a
    /// course that is gone with a live alarm still addressed to it is the
    /// fault this piece exists to close, so the removal must not proceed past
    /// a cancel it could not make.
    func testAFailedCancelStopsTheRemovalAndIsReported() throws {
        try prepare()
        let course: Course = try makeCourse()
        try writeAgent(sectionNumber: 1)
        // A folder the plist cannot be deleted from.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: agentsDirectory.path
        )

        let result = ScheduledDeployCleanup.removeCourse(
            course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
        )

        XCTAssertFalse(result.didRemove)
        XCTAssertEqual(
            result.problem,
            ScheduledDeployCleanup.couldNotTurnItOff(courseCode: "ICS3U", sections: [1])
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: course.directoryURL.path),
            "The course must still be here — its deploy is still live."
        )
        XCTAssertFalse(
            trailText().contains("turned off a scheduled deploy"),
            "Nothing was turned off, so nothing may say it was."
        )
    }

    /// A removal that fails AFTER the cancel worked says the deploy stays off.
    func testARemovalThatFailsAfterTheCancelSaysTheDeployStaysOff() throws {
        try prepare()
        let course: Course = try makeCourse()
        try writeAgent(sectionNumber: 1)
        // `_backups` as a FILE, so the archive cannot be written.
        try Data("not a folder".utf8).write(
            to: coursesDirectoryURL.appendingPathComponent("_backups")
        )

        let result = ScheduledDeployCleanup.removeCourse(
            course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
        )

        XCTAssertFalse(result.didRemove)
        XCTAssertEqual(result.stoppedSections, [1])
        let problem: String = try XCTUnwrap(result.problem)
        XCTAssertTrue(
            problem.hasPrefix("Section 1 of ICS3U will no longer deploy on its own"),
            "The sentence must say the deploy is off as well as that the removal failed: \(problem)"
        )
        XCTAssertFalse(agentExists(sectionNumber: 1))
    }

    /// A removal that fails with nothing scheduled says only what went wrong,
    /// exactly as it did before any of this existed.
    func testARemovalThatFailsWithNothingScheduledSaysOnlyTheReason() throws {
        try prepare()
        let course: Course = try makeCourse()
        try Data("not a folder".utf8).write(
            to: coursesDirectoryURL.appendingPathComponent("_backups")
        )
        let result = ScheduledDeployCleanup.removeCourse(
            course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
        )
        XCTAssertFalse(result.didRemove)
        let problem: String = try XCTUnwrap(result.problem)
        XCTAssertFalse(problem.contains("will no longer deploy"))
    }

    // MARK: - The trail

    /// One line per section turned off, carrying the course, the section and
    /// the reason.
    func testTheTrailCarriesOneLinePerSectionWithItsReason() throws {
        try prepare()
        let course: Course = try makeCourse()
        try writeAgent(sectionNumber: 1)
        try writeAgent(sectionNumber: 2)

        _ = ScheduledDeployCleanup.removeCourse(
            course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
        )

        var lines: [String] = []
        for line in trailText().components(separatedBy: "\n") {
            if line.contains("turned off a scheduled deploy") {
                lines.append(line)
            }
        }
        XCTAssertEqual(lines.count, 2, "One line per section: \(trailText())")
        XCTAssertTrue(lines[0].contains("ICS3U/1"))
        XCTAssertTrue(lines[1].contains("ICS3U/2"))
        for line in lines {
            XCTAssertTrue(
                line.contains(ScheduledDeployCleanup.Reason.courseWasRemoved.trailPhrase),
                "The line must say WHY: \(line)"
            )
        }
    }

    /// Removing a SECTION says so, rather than saying the course went.
    func testTheTrailSaysWhichKindOfRemovalItWas() throws {
        try prepare()
        let course: Course = try makeCourse()
        try writeAgent(sectionNumber: 2)
        _ = ScheduledDeployCleanup.removeSection(
            2, from: course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
        )
        XCTAssertTrue(trailText().contains(
            ScheduledDeployCleanup.Reason.sectionWasRemoved.trailPhrase
        ), trailText())
    }

    // MARK: - Reading the agents back

    func testTheAgentListReadsCodeSectionFolderAndMomentBack() throws {
        try prepare()
        let when: Date = Date().addingTimeInterval(7200)
        try writeAgent(courseCode: "ICS3U", sectionNumber: 1, when: when)
        // Not one of ours, and never touched.
        try Data("{}".utf8).write(
            to: agentsDirectory.appendingPathComponent("com.example.something.plist")
        )

        let agents: [ScheduledDeploy.Agent] = ScheduledDeploy.agents(
            inWorkingFolder: workingFolderURL
        )
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].courseCode, "ICS3U")
        XCTAssertEqual(agents[0].sectionNumber, 1)
        XCTAssertEqual(
            ScheduledDeploy.physicalPath(agents[0].workingFolderPath),
            ScheduledDeploy.physicalPath(workingFolderURL.path)
        )
        XCTAssertEqual(
            agents[0].scheduledFor.map { moment in Int(moment.timeIntervalSince1970) },
            Int(when.timeIntervalSince1970)
        )
    }

    /// A plist written before v1.2.0 carries no course code of its own, so it
    /// comes back out of the LABEL.
    ///
    /// Those are exactly the jobs that have been sitting on teachers' Macs
    /// since before this was fixed, so a reader that could not name them would
    /// leave the whole problem population untouched.
    func testALegacyPlistStillNamesItsCourseAndSection() throws {
        try prepare()
        try writeAgent(courseCode: "ICS3U", sectionNumber: 2, when: nil, legacy: true)
        let agents: [ScheduledDeploy.Agent] = ScheduledDeploy.agents(
            inWorkingFolder: workingFolderURL
        )
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents[0].courseCode, "ICS3U")
        XCTAssertEqual(agents[0].sectionNumber, 2)
        XCTAssertNil(agents[0].scheduledFor, "A legacy plist may carry no moment at all")
    }

    /// A course code with a character a label cannot carry comes back
    /// sanitised from a legacy plist, and the comparison still matches.
    func testASanitisedCodeStillMatchesTheCourseItNames() throws {
        try prepare()
        try writeAgent(courseCode: "Chess Club", sectionNumber: 1, legacy: true)
        let owned: [ScheduledDeploy.Agent] = ScheduledDeployCleanup.agentsOwnedBy(
            courseCode: "Chess Club", sectionNumber: nil, inWorkingFolder: workingFolderURL
        )
        XCTAssertEqual(owned.count, 1, "A raw comparison would have missed this one")
        XCTAssertEqual(owned[0].courseCode, "CHESS-CLUB")
    }

    func testAnAgentNamingAnotherFolderIsNotInThisFoldersList() throws {
        try prepare()
        let otherFolder: URL = workingFolderURL
            .deletingLastPathComponent().appendingPathComponent("other-workspace")
        try writeAgent(sectionNumber: 1, workingFolder: otherFolder)
        XCTAssertEqual(ScheduledDeploy.agents(inWorkingFolder: workingFolderURL).count, 0)
        XCTAssertEqual(ScheduledDeploy.agents(inWorkingFolder: otherFolder).count, 1)
    }

    /// The clock, and the Cancel item beside it, follow the same scoping.
    func testTheClockIsNotShownForAnotherFoldersDeploy() throws {
        try prepare()
        let otherFolder: URL = workingFolderURL
            .deletingLastPathComponent().appendingPathComponent("other-workspace")
        try writeAgent(sectionNumber: 1, workingFolder: otherFolder)
        XCTAssertNil(ScheduledDeploy.nextRun(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workingFolderURL
        ))
        XCTAssertNotNil(ScheduledDeploy.nextRun(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: otherFolder
        ))
    }

    // MARK: - The sweep

    func testTheSweepClearsAnOverdueDeployAndLeavesTheRestAlone() throws {
        try prepare()
        try makeCourse(sections: [1, 2, 3])
        let now: Date = Date()
        try writeAgent(sectionNumber: 1, when: now.addingTimeInterval(-8 * 24 * 3600))
        try writeAgent(sectionNumber: 2, when: now.addingTimeInterval(-2 * 24 * 3600))
        try writeAgent(sectionNumber: 3, when: now.addingTimeInterval(21 * 24 * 3600))

        let outcome = ScheduledDeployCleanup.sweepDeploysThatAreTooLate(
            inWorkingFolder: workingFolderURL, now: now, runner: launchControl
        )

        XCTAssertEqual(outcome.stopped, [1])
        XCTAssertFalse(agentExists(sectionNumber: 1))
        XCTAssertTrue(agentExists(sectionNumber: 2), "Two days late is inside the week")
        XCTAssertTrue(agentExists(sectionNumber: 3), "A deploy three weeks AHEAD is not overdue")
    }

    /// The sweep uses the course's own window, not a fixed one.
    func testTheSweepHonoursTheCoursesOwnWindow() throws {
        try prepare()
        try makeCourse(sections: [1], mayRunLateDays: 1)
        let now: Date = Date()
        try writeAgent(sectionNumber: 1, when: now.addingTimeInterval(-2 * 24 * 3600))

        let outcome = ScheduledDeployCleanup.sweepDeploysThatAreTooLate(
            inWorkingFolder: workingFolderURL, now: now, runner: launchControl
        )
        XCTAssertEqual(outcome.stopped, [1], "One day chosen, two days late")
    }

    /// A job with no recorded moment is left alone whatever its age — the run
    /// fails open on one of those, so sweeping it would destroy a deploy that
    /// would otherwise still happen.
    func testTheSweepLeavesAJobWithNoMomentAlone() throws {
        try prepare()
        try makeCourse(sections: [1])
        try writeAgent(sectionNumber: 1, when: nil, legacy: true)
        let outcome = ScheduledDeployCleanup.sweepDeploysThatAreTooLate(
            inWorkingFolder: workingFolderURL, now: Date(), runner: launchControl
        )
        XCTAssertTrue(outcome.isQuiet)
        XCTAssertTrue(agentExists(sectionNumber: 1, labelled: .beforeFolderScoping))
    }

    /// An OVERDUE job this folder set before #237, under the old label, is
    /// swept like any other of this folder's — found by the folder scan and
    /// cancelled by the name it really has (#237 review, L5).
    func testTheSweepClearsAnOverdueDeploySetBeforeTheUpdate() throws {
        try prepare()
        try makeCourse(sections: [1])
        let now: Date = Date()
        try writeAgent(
            sectionNumber: 1, when: now.addingTimeInterval(-8 * 24 * 3600), labelled: .beforeFolderScoping
        )
        let outcome = ScheduledDeployCleanup.sweepDeploysThatAreTooLate(
            inWorkingFolder: workingFolderURL, now: now, runner: launchControl
        )
        XCTAssertFalse(outcome.isQuiet, "\(outcome)")
        XCTAssertFalse(agentExists(sectionNumber: 1, labelled: .beforeFolderScoping))
        XCTAssertTrue(
            launchControl.bootedOutLabels.contains(labelFor(sectionNumber: 1, labelled: .beforeFolderScoping)),
            "Booted out by the name it really has"
        )
    }

    /// And it never reaches into another working folder, however overdue that
    /// folder's job is.
    func testTheSweepNeverTouchesAnotherFoldersDeploy() throws {
        try prepare()
        let otherFolder: URL = workingFolderURL
            .deletingLastPathComponent().appendingPathComponent("other-workspace")
        // Under the label every release before #237 wrote, which a job of
        // this folder's could share by name.
        try writeAgent(
            sectionNumber: 1,
            workingFolder: otherFolder,
            when: Date().addingTimeInterval(-365 * 24 * 3600),
            labelled: .beforeFolderScoping
        )
        let outcome = ScheduledDeployCleanup.sweepDeploysThatAreTooLate(
            inWorkingFolder: workingFolderURL, now: Date(), runner: launchControl
        )
        XCTAssertTrue(outcome.isQuiet)
        XCTAssertTrue(agentExists(sectionNumber: 1, labelled: .beforeFolderScoping))
    }

    // MARK: - Standing down at fire time

    /// The moment comes from the environment the scheduler handed over, and
    /// from the job itself when it does not.
    func testTheIntendedMomentIsReadFromTheEnvironmentThenFromTheJob() throws {
        try prepare()
        let when: Date = Date().addingTimeInterval(-3600)
        try writeAgent(sectionNumber: 1, when: when)
        let label: String = labelFor(sectionNumber: 1)
        let script: String = "/tmp/\(label).sh"

        let fromEnvironment: Date? = ScheduledDeploy.intendedMoment(
            forScript: script,
            environment: [ScheduledDeploy.scheduledForKey: ISO8601DateFormatter().string(from: when)]
        )
        XCTAssertEqual(
            fromEnvironment.map { moment in Int(moment.timeIntervalSince1970) },
            Int(when.timeIntervalSince1970)
        )

        let fromTheJob: Date? = ScheduledDeploy.intendedMoment(
            forScript: script, environment: [:]
        )
        XCTAssertEqual(
            fromTheJob.map { moment in Int(moment.timeIntervalSince1970) },
            Int(when.timeIntervalSince1970),
            "The job is still on disk at that instant — only the wrapper deletes it."
        )
    }

    /// Neither says, so it FAILS OPEN.
    func testAnUnknownMomentRuns() throws {
        try prepare()
        let label: String = labelFor(sectionNumber: 1)
        XCTAssertNil(ScheduledDeploy.intendedMoment(
            forScript: "/tmp/\(label).sh", environment: [:]
        ))
        XCTAssertTrue(ScheduledDeployLateness.mayStillRun(
            intendedMoment: nil, now: Date(), allowedDays: 1
        ))
    }

    /// The label comes out of the wrapper script's own path — the only route a
    /// pre-v1.2.0 job leaves, since it names no course and no section.
    func testTheLabelComesOutOfTheScriptPath() {
        let label: String = labelFor(sectionNumber: 1)
        XCTAssertEqual(
            ScheduledDeploy.label(
                fromScriptPath: "/Users/x/Library/Application Support/Plantoir/scheduled/\(label).sh"
            ),
            label
        )
        XCTAssertNil(ScheduledDeploy.label(fromScriptPath: "/tmp/something-else.sh"))
        XCTAssertNil(ScheduledDeploy.label(fromScriptPath: "/tmp/\(label).plist"))
    }

    /// At fire time the window comes from the course the job named.
    func testTheFireTimeWindowComesFromTheCourseTheJobNamed() throws {
        try prepare()
        let course: Course = try makeCourse(sections: [1], mayRunLateDays: 14)
        XCTAssertEqual(
            ScheduledDeploy.allowedLatenessDays(
                forSection: (courseDirectory: course.directoryURL, courseCode: "ICS3U", sectionNumber: 1)
            ),
            14
        )
        // A job that names no section — everything written before v1.2.0 —
        // gets the default.
        XCTAssertEqual(
            ScheduledDeploy.allowedLatenessDays(forSection: nil),
            ScheduledDeployLateness.defaultDays
        )
    }

    // MARK: - What the teacher is told when a run stands down

    func testStandingDownIsItsOwnOutcomeAndAsksForAttention() {
        XCTAssertTrue(ScheduledPublishOutcome.Kind.tooLateToRun.needsAttention)
        let sentence: String = ScheduledPublishOutcome.sentence(
            for: ScheduledPublishOutcome.Stopped(
                kind: .tooLateToRun,
                destination: ScheduledPublishOutcome.nothingWasDeployedName,
                when: Date()
            ),
            course: "ICS3U",
            section: 1
        )
        XCTAssertTrue(sentence.contains("ICS3U Section 1"))
        XCTAssertFalse(
            sentence.contains(ScheduledPublishOutcome.nothingWasDeployedName),
            "The stand-in destination is written into the record and never shown."
        )
    }

    /// It writes the SAME trail line a removal writes, because the same thing
    /// happened to the teacher's alarm.
    func testStandingDownWritesTheDeployTurnedOffLine() throws {
        try prepare()
        let home: URL = workingFolderURL.appendingPathComponent("home")
        ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(
                kind: .tooLateToRun,
                destination: ScheduledPublishOutcome.nothingWasDeployedName,
                when: Date()
            ),
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: folderID
        )
        XCTAssertTrue(ScheduledPublishOutcome.noteOnTrail(
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: folderID
        ))
        XCTAssertTrue(trailText().contains(
            "turned off a scheduled deploy "
            + ScheduledDeployCleanup.Reason.theDayItWasSetForHadGoneBy.trailPhrase
        ), trailText())
    }

    // MARK: - A course code that came back out of a label

    /// A MODERN job for a course whose code has a space gets the window its
    /// teacher chose.
    ///
    /// Everything written since the course code went into the job itself
    /// carries the teacher's own spelling, so `courses/Chess Club/` is found
    /// by name.
    func testASpacedCourseCodeKeepsItsOwnWindowWhenTheJobRecordsIt() throws {
        try prepare()
        try makeCourse(code: "Chess Club", sections: [1], mayRunLateDays: 14)
        let now: Date = Date()
        try writeAgent(
            courseCode: "Chess Club", sectionNumber: 1,
            when: now.addingTimeInterval(-8 * 24 * 3600)
        )
        let outcome = ScheduledDeployCleanup.sweepDeploysThatAreTooLate(
            inWorkingFolder: workingFolderURL, now: now, runner: launchControl
        )
        XCTAssertTrue(
            outcome.isQuiet,
            "Eight days late with two weeks chosen must stand: \(outcome)"
        )
        XCTAssertTrue(agentExists(courseCode: "Chess Club", sectionNumber: 1))
    }

    /// And a LEGACY job for the same course does too, although its code came
    /// back uppercased and hyphenated.
    ///
    /// Without the sanitised match the config path `courses/CHESS-CLUB/` does
    /// not exist, the default window applies, and a job eight days late is
    /// swept although the run itself would have let it go ahead — a deploy
    /// dropped, which is the direction that matters.
    func testASpacedCourseCodeKeepsItsOwnWindowEvenFromALegacyJob() throws {
        try prepare()
        try makeCourse(code: "Chess Club", sections: [1], mayRunLateDays: 14)
        let now: Date = Date()
        try writeAgent(
            courseCode: "Chess Club", sectionNumber: 1,
            when: now.addingTimeInterval(-8 * 24 * 3600), legacy: true
        )
        XCTAssertEqual(
            ScheduledDeployLateness.days(
                forCourseCode: "CHESS-CLUB", inWorkingFolder: workingFolderURL
            ),
            14,
            "A lossy code must still find the folder it names"
        )
        let outcome = ScheduledDeployCleanup.sweepDeploysThatAreTooLate(
            inWorkingFolder: workingFolderURL, now: now, runner: launchControl
        )
        XCTAssertTrue(outcome.isQuiet, "\(outcome)")
        XCTAssertTrue(agentExists(courseCode: "Chess Club", sectionNumber: 1, labelled: .beforeFolderScoping))
    }

    /// Two codes that sanitise the same way are ambiguous, and the default is
    /// what an ambiguous answer gets — never one course's setting read for
    /// another course's job.
    func testAnAmbiguousSanitisedCodeGetsTheDefault() throws {
        try prepare()
        try makeCourse(code: "Chess Club", sections: [1], mayRunLateDays: 14)
        try makeCourse(code: "Chess-Club", sections: [1], mayRunLateDays: 1)
        XCTAssertEqual(
            ScheduledDeployLateness.days(
                forCourseCode: "CHESS-CLUB", inWorkingFolder: workingFolderURL
            ),
            ScheduledDeployLateness.defaultDays
        )
    }

    // MARK: - The cancel's own backstop

    /// The cancel takes the working folder as a REQUIRED argument and leaves
    /// alone a job belonging to another one.
    ///
    /// Every caller asks `agentsOwnedBy` or a folder-scoped `nextRun` first,
    /// so nothing reaches this today — it is the backstop under those, and it
    /// is what makes the unscoped form impossible to write by accident.
    func testTheCancelItselfLeavesAnotherFoldersJobAlone() throws {
        try prepare()
        let otherFolder: URL = workingFolderURL
            .deletingLastPathComponent().appendingPathComponent("other-workspace")
        // Under the label every release before #237 wrote — the one name the
        // section had on the whole Mac, so the one a cancel by NAME would hit.
        try writeAgent(sectionNumber: 1, workingFolder: otherFolder, labelled: .beforeFolderScoping)

        XCTAssertNil(ScheduledDeploy.cancelScheduledDeploy(
            courseCode: "ICS3U",
            sectionNumber: 1,
            inWorkingFolder: workingFolderURL,
            runner: launchControl
        ))
        XCTAssertTrue(agentExists(sectionNumber: 1, labelled: .beforeFolderScoping))
        // Nothing of this folder's is on disk, so the only label it may boot
        // out is THIS folder's own (a job still loaded with its plist gone),
        // which since #237 cannot name another folder's job.
        XCTAssertFalse(
            launchControl.bootedOutLabels.contains(labelFor(sectionNumber: 1, labelled: .beforeFolderScoping)),
            "It must not even boot it out"
        )
        XCTAssertEqual(launchControl.bootedOutLabels, [labelFor(sectionNumber: 1)])
    }

    // MARK: - The wrapper scripts live inside the test's own tree

    /// A test can never delete a real scheduled deploy's wrapper script.
    ///
    /// `cancelScheduledDeploy` removes the wrapper whatever runner it was
    /// handed, and until 2026-09-20 `scriptURL` had no override at all — so a
    /// test that moved only the AGENTS folder deleted
    /// `~/Library/Application Support/Plantoir/scheduled/<label>.sh` for real.
    /// The teacher's alarm survived in their own folder and would fire at a
    /// script that was gone. ICS3U is the fixture code precisely because it is
    /// a course a teacher plausibly has.
    func testTheWrapperScriptPathStaysInsideTheTestsOwnFolder() throws {
        try prepare()
        let scriptPath: String = ScheduledDeploy.scriptURL(
            courseCode: "ICS3U", sectionNumber: 1, inWorkingFolder: workingFolderURL
        ).path
        let realPath: String = ("~/Library/Application Support/Plantoir/scheduled" as NSString)
            .expandingTildeInPath
        XCTAssertFalse(
            scriptPath.hasPrefix(realPath),
            "A test is about to write or delete inside the teacher's own scheduled folder: "
            + scriptPath
        )
        XCTAssertTrue(
            scriptPath.hasPrefix(workingFolderURL.deletingLastPathComponent().path),
            scriptPath
        )
    }

    // MARK: - The structural guard

    /// The real `launchctl` refuses while a test is driving.
    ///
    /// Measured by asking it: every test that can reach an agent is supposed
    /// to pass `FakeLaunchControl`, and that was a rule for whoever writes the
    /// test — the kind that holds until somebody adds the eleventh one. The
    /// cost of forgetting is not a red test but a REAL ICS3U schedule deleted
    /// on the machine running the suite, because that is the fixture course.
    func testTheRealLaunchControlRefusesWhileATestIsDriving() throws {
        try prepare()
        let result = LaunchControl.run(arguments: ["print", "gui/501"])
        XCTAssertEqual(result.exitCode, -1)
        XCTAssertEqual(result.output, LaunchControl.refusedUnderATestRun)
        XCTAssertNotNil(
            LaunchControl().bootstrap(plistURL: agentsDirectory.appendingPathComponent("x.plist")),
            "Bootstrapping must report the refusal rather than quietly doing nothing."
        )
    }

    // MARK: - Reading the contract

    private static func section(_ name: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in shared-rules.json")
    }

    private static func productSourceFolderURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .appendingPathComponent("QuartzTeachers", isDirectory: true)
    }
}
