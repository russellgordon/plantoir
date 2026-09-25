import XCTest
@testable import QuartzTeachers

/// What a scheduled publish leaves behind when it does not get through — and
/// these tests RUN THE GENERATED SHELL rather than reading it.
///
/// That distinction is the point of the file. The wrapper is bash written by
/// Swift and run at half six by an agent nobody is watching, so a test that
/// only asserts the generated TEXT proves the string is what we meant
/// to write and nothing about what bash does with it. These build a stub
/// workspace, run the real script through `/bin/bash`, and look at the file it
/// left.
///
/// Nothing of the teacher's is touched, and that claim is load-bearing rather
/// than decorative: `oneShotCommand` takes a home folder, and the plist,
/// the log, the success sentinel and the stopped record all follow it.
/// `launchAgentsDirectoryOverride` is set too, or the generated script's
/// `rm -f <plist>` reaches the real folder.
///
/// An earlier version of this file made the same claim and was WRONG — it left
/// `…deploy.ZZQ4U.section1.succeeded` in the real Application Support, because
/// only the stopped record followed the test's home. Every course code here is
/// a fixture name no real course uses, which is what made the litter findable.
@MainActor
final class ScheduledPublishOutcomeTests: XCTestCase {

    // MARK: - Stored properties

    private var home: URL!
    private var workspace: URL!

    // MARK: - Functions

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scheduled-outcome-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        workspace = root.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        // Agents too. Without this the generated script's `rm -f <plist>` and
        // its `launchctl bootout` reach the teacher's REAL LaunchAgents folder
        // — and an earlier version of this file claimed nothing of theirs was
        // touched while leaving a sentinel in their Application Support.
        ScheduledDeploy.launchAgentsDirectoryOverride =
            home.appendingPathComponent("Library/LaunchAgents")
        // And the wrapper scripts, which `cancelScheduledDeploy` deletes
        // whatever runner it was handed — see ScheduledDeploy's own note.
        ScheduledDeploy.scheduledScriptsDirectoryOverride =
            home.appendingPathComponent("Library/Application Support/Plantoir/scheduled")
        try FileManager.default.createDirectory(
            at: ScheduledDeploy.launchAgentsDirectoryOverride!, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        let root: URL = home.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// Launchers that exit with the codes we want to test.
    ///
    /// `failingDestination` makes `deploy.sh` fail for ONE destination and
    /// succeed for the others, by looking at the `--to` argument the wrapper
    /// passes. Without that a "first destination wins" test can only fail both
    /// legs, which cannot tell a mixed run from a wholly failed one.
    private func writeStubLaunchers(
        deployExit: Int32,
        previewExit: Int32 = 0,
        failingDestination: String? = nil
    ) throws {
        let previewScript: String = "#!/bin/bash\nexit \(previewExit)\n"
        var deployScript: String = "#!/bin/bash\n"
        if let failingDestination {
            deployScript += """
            for argument in \"$@\"; do
              if [ \"$argument\" = \"\(failingDestination)\" ]; then exit \(deployExit); fi
            done
            exit 0
            """ + "\n"
        } else {
            deployScript += "exit \(deployExit)\n"
        }
        for (name, script) in [("preview.sh", previewScript), ("deploy.sh", deployScript)] {
            let url: URL = workspace.appendingPathComponent(name)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path
            )
        }
    }

    /// Run the real generated wrapper.
    private func runWrapper(
        course: String,
        section: Int,
        destinations: [String],
        descriptions: [String]
    ) throws {
        var argumentsList: [[String]] = []
        for description in descriptions {
            argumentsList.append([course, String(section), "--to", description])
        }
        let script: String = ScheduledDeploy.oneShotCommand(
            courseCode: course,
            sectionNumber: section,
            workspaceURL: workspace,
            deployArgumentsList: argumentsList,
            destinationTypes: destinations,
            destinationDescriptions: descriptions,
            homeFolder: home
        )
        let scriptURL: URL = workspace.appendingPathComponent("wrapper.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    // MARK: - A run that stopped

    /// Exit 3 is "a question went unanswered", and the record says so.
    func testAPublishThatNeededAnAnswerLeavesARecordNamingTheDestination() throws {
        try writeStubLaunchers(deployExit: 3)
        try runWrapper(
            course: "ZZQ1U", section: 1,
            destinations: ["netlify"], descriptions: ["Netlify"]
        )

        let stopped = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ1U", section: 1
        )
        XCTAssertEqual(
            stopped?.kind, .neededAnAnswer,
            "A leg exiting 3 must be recorded as a question nobody answered, not as an "
            + "ordinary failure — the whole point of the distinct exit code."
        )
        XCTAssertEqual(stopped?.destination, "Netlify")
    }

    /// Anything else non-zero is recorded too, which is where this side goes
    /// further than Windows: the SILENCE is the teacher's complaint, not the
    /// cause, so a revoked token and a network that was down both leave a note.
    func testAnOrdinaryFailureIsRecordedAsWell() throws {
        try writeStubLaunchers(deployExit: 1)
        try runWrapper(
            course: "ZZQ2U", section: 3,
            destinations: ["netlify"], descriptions: ["Netlify"]
        )

        let stopped = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ2U", section: 3
        )
        XCTAssertEqual(stopped?.kind, .didNotFinish)
        XCTAssertEqual(stopped?.destination, "Netlify")
    }

    /// The FIRST destination that stopped is the one kept. A course can publish
    /// to several and only one may have gone wrong, so overwriting would report
    /// the last thing that went wrong rather than the first.
    func testTheFirstDestinationThatStoppedIsTheOneKept() throws {
        try writeStubLaunchers(deployExit: 1)
        try runWrapper(
            course: "ZZQ3U", section: 2,
            destinations: ["netlify", "local_folder"],
            descriptions: ["Netlify", "your deploy folder"]
        )

        let stopped = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ3U", section: 2
        )
        XCTAssertEqual(
            stopped?.destination, "Netlify",
            "Both legs failed; the record must name the first, not the last."
        )
    }

    // MARK: - A run that got through

    /// Cleared only after every destination has run and every one succeeded.
    func testARunThatGotThroughClearsAnEarlierRecord() throws {
        ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(
                kind: .didNotFinish, destination: "Netlify", when: Date()
            ),
            inHomeFolder: home, course: "ZZQ4U", section: 1
        )
        XCTAssertNotNil(ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ4U", section: 1
        ), "the fixture record should exist before the run")

        try writeStubLaunchers(deployExit: 0)
        try runWrapper(
            course: "ZZQ4U", section: 1,
            destinations: ["netlify"], descriptions: ["Netlify"]
        )

        // It no longer merely CLEARS the failure — it replaces it with a
        // success, so the teacher is told what happened rather than shown
        // nothing. Either way the stale failure must not survive.
        let outcome = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ4U", section: 1
        )
        XCTAssertEqual(
            outcome?.kind, .succeeded,
            "A publish that got all the way through must replace the earlier failure, or a "
            + "teacher is told about one that has since been fixed."
        )
    }

    /// One leg failing while another SUCCEEDS must still leave a note, and the
    /// note must name the leg that failed.
    ///
    /// This is the case the earlier version of this test could not see: it
    /// failed every leg, so it proved nothing a single-destination test had
    /// not already proved.
    func testOneLegFailingAmongSeveralStillLeavesANoteNamingThatLeg() throws {
        try writeStubLaunchers(deployExit: 1, failingDestination: "your deploy folder")
        try runWrapper(
            course: "ZZQ5U", section: 1,
            destinations: ["netlify", "local_folder"],
            descriptions: ["Netlify", "your deploy folder"]
        )
        let stopped = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ5U", section: 1
        )
        XCTAssertEqual(
            stopped?.destination, "your deploy folder",
            "The SECOND leg failed and the first succeeded; the note must name the one that "
            + "stopped, and a run where anything stopped must not be cleared by the leg that "
            + "worked."
        )
    }

    // MARK: - A build that stopped

    /// A failed BUILD is a stopped scheduled publish too.
    ///
    /// This is the case `--non-interactive` itself created: `preview.sh`
    /// refuses the course-code guard and exits 3, and every deploy line is
    /// skipped when the build did not succeed — so without a record here the
    /// teacher would be told nothing at all about the one failure this change
    /// introduced.
    /// And it is its OWN kind, not the one a destination gets.
    ///
    /// Nothing was published, because nothing was reached — the stub deploy
    /// here exits 0, so a wrapper that ran it anyway would leave the success
    /// sentinel behind and the section would be marked published. Asserting
    /// the sentinel's absence is the property a teacher cares about; the kind
    /// is only how they are told.
    func testABuildThatNeededAnAnswerIsRecordedAndNothingIsPublished() throws {
        try writeStubLaunchers(deployExit: 0, previewExit: 3)
        try runWrapper(
            course: "ZZQ7U", section: 1,
            destinations: ["netlify"], descriptions: ["Netlify"]
        )
        let stopped = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ7U", section: 1
        )
        XCTAssertEqual(stopped?.kind, .buildNeededAnAnswer)
        // Written even though the sentence never shows it, so every record has
        // one shape. See ScheduledPublishOutcome.buildDestinationName.
        XCTAssertEqual(stopped?.destination, ScheduledPublishOutcome.buildDestinationName)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ScheduledDeploy.successSentinelURL(
                courseCode: "ZZQ7U", sectionNumber: 1, inHomeFolder: home
            ).path),
            "the build stopped, so nothing was published and nothing may say it was"
        )
    }

    /// A build that failed OUTRIGHT is recorded as its own kind (#137), not
    /// as a destination that stopped — and nothing is published.
    ///
    /// Until #137 this was `didNotFinish`, whose sentence named
    /// `buildDestinationName` as though it were a destination and sent the
    /// teacher to Publish.
    func testABuildThatFailedOutrightIsRecordedToo() throws {
        try writeStubLaunchers(deployExit: 0, previewExit: 1)
        try runWrapper(
            course: "ZZQ8U", section: 1,
            destinations: ["netlify"], descriptions: ["Netlify"]
        )
        XCTAssertEqual(
            ScheduledPublishOutcome.stopped(
                inHomeFolder: home, course: "ZZQ8U", section: 1
            )?.kind,
            .buildDidNotFinish
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ScheduledDeploy.successSentinelURL(
                courseCode: "ZZQ8U", sectionNumber: 1, inHomeFolder: home
            ).path),
            "the build failed, so nothing was published and nothing may say it was"
        )
    }

    /// The contract's own table of which LEG and which exit code give which
    /// kind, played through the REAL generated wrapper.
    ///
    /// `scheduledPublishStopped.whichKind.cases` is the list Windows runs
    /// against its own wrapper too, so the rule has one home. Each case gets a
    /// course code of its own (fixture names no real course uses), so one
    /// case's record or success mark cannot answer for another's. The kind
    /// named by the contract is found by walking `Kind.allCases` through
    /// `SharedRulesContractTests.contractKey(for:)` rather than a list retyped
    /// here.
    func testEveryLegAndExitCodeIsFiledAsTheContractSays() throws {
        let rule: [String: Any] = try SharedRulesContractTests.section("scheduledPublishStopped")
        let whichKind: [String: Any] = try XCTUnwrap(rule["whichKind"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(whichKind["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "the whichKind case list has lost cases")

        var buildKindsSeen: Set<String> = []
        var caseNumber: Int = 0
        for testCase in cases {
            let leg: String = try XCTUnwrap(testCase["leg"] as? String)
            let exitCode: Int = try XCTUnwrap(testCase["exitCode"] as? Int)
            let kindKey: String = try XCTUnwrap(testCase["kind"] as? String)
            let namesADestination: Bool = try XCTUnwrap(testCase["namesADestination"] as? Bool)
            let anythingPublished: Bool = try XCTUnwrap(testCase["anythingPublished"] as? Bool)
            let why: String = try XCTUnwrap(testCase["why"] as? String)
            let label: String = "\(leg) exit \(exitCode) — \(why)"

            var expectedKind: ScheduledPublishOutcome.Kind?
            for kind in ScheduledPublishOutcome.Kind.allCases {
                if SharedRulesContractTests.contractKey(for: kind) == kindKey {
                    expectedKind = kind
                }
            }
            let expected: ScheduledPublishOutcome.Kind = try XCTUnwrap(
                expectedKind, "the contract names a kind the app does not have: \(kindKey)"
            )

            var previewExit: Int32 = 0
            var deployExit: Int32 = 0
            if leg == "build" {
                previewExit = Int32(exitCode)
                buildKindsSeen.insert(kindKey)
            } else if leg == "destination" {
                deployExit = Int32(exitCode)
            } else {
                XCTAssertEqual(leg, "none", "unknown leg in \(label)")
                XCTAssertEqual(exitCode, 0, "a run where nothing stopped exits 0: \(label)")
            }

            let course: String = "ZZR\(caseNumber)U"
            caseNumber += 1
            try writeStubLaunchers(deployExit: deployExit, previewExit: previewExit)
            try runWrapper(
                course: course, section: 1,
                destinations: ["netlify"], descriptions: ["Netlify"]
            )

            let stopped: ScheduledPublishOutcome.Stopped = try XCTUnwrap(
                ScheduledPublishOutcome.stopped(inHomeFolder: home, course: course, section: 1),
                "no record at all for \(label)"
            )
            XCTAssertEqual(stopped.kind, expected, label)

            let sentence: String = ScheduledPublishOutcome.sentence(
                for: stopped, course: course, section: 1
            )
            XCTAssertEqual(
                sentence.contains(stopped.destination), namesADestination,
                "whether the sentence names the record's destination (\(stopped.destination)): \(label)"
            )

            let published: Bool = FileManager.default.fileExists(
                atPath: ScheduledDeploy.successSentinelURL(
                    courseCode: course, sectionNumber: 1, inHomeFolder: home
                ).path
            )
            XCTAssertEqual(published, anythingPublished, "whether it counts as published: \(label)")
        }

        // Both build kinds must stay in the table, so the list cannot quietly
        // shrink back to one that no longer tells them apart.
        XCTAssertTrue(buildKindsSeen.contains("buildNeededAnAnswer"))
        XCTAssertTrue(buildKindsSeen.contains("buildDidNotFinish"))
    }

    // MARK: - Last night's record

    /// A record nobody cleared must not suppress tonight's.
    ///
    /// "The first destination that stopped wins" is meant WITHIN a run. Across
    /// runs it silently became "the first that stopped since the last cleared
    /// run", so an uncleared record from last week blocked tonight's — a
    /// different destination, possibly a different kind — from being written
    /// at all.
    func testAnOldRecordDoesNotSuppressTonights() throws {
        ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(
                kind: .neededAnAnswer, destination: "Netlify", when: Date()
            ),
            inHomeFolder: home, course: "ZZQ9U", section: 1
        )
        try writeStubLaunchers(deployExit: 1)
        try runWrapper(
            course: "ZZQ9U", section: 1,
            destinations: ["local_folder"], descriptions: ["your deploy folder"]
        )
        let stopped = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ9U", section: 1
        )
        XCTAssertEqual(stopped?.kind, .didNotFinish, "tonight's kind, not last week's")
        XCTAssertEqual(
            stopped?.destination, "your deploy folder",
            "tonight's destination, not last week's"
        )
    }

    /// A run that got through records that it DID, not merely the absence of
    /// a failure.
    ///
    /// The silence this closes is the mirror of the failure one: a scheduled
    /// publish leaving no trace cannot be told from one that never happened,
    /// so the trail could answer "why did my site not update?" and could not
    /// answer "did it?".
    func testARunThatGotThroughRecordsThatItSucceeded() throws {
        try writeStubLaunchers(deployExit: 0)
        try runWrapper(
            course: "ZZQCU", section: 1,
            destinations: ["netlify"], descriptions: ["Netlify"]
        )
        let outcome = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQCU", section: 1
        )
        XCTAssertEqual(outcome?.kind, .succeeded)
        XCTAssertEqual(outcome?.destination, "Netlify")
        XCTAssertFalse(
            try XCTUnwrap(outcome?.kind.needsAttention),
            "A success is news, not a problem: it must not raise the sidebar's warning."
        )
    }

    /// Every destination is named when a publish went to several.
    func testASuccessNamesEveryDestination() throws {
        try writeStubLaunchers(deployExit: 0)
        try runWrapper(
            course: "ZZQDU", section: 1,
            destinations: ["netlify", "local_folder"],
            descriptions: ["Netlify", "your deploy folder"]
        )
        XCTAssertEqual(
            ScheduledPublishOutcome.stopped(
                inHomeFolder: home, course: "ZZQDU", section: 1
            )?.destination,
            "Netlify, your deploy folder"
        )
    }

    // MARK: - The trail

    /// The trail line is written by the RUN, and reading the record does not
    /// disturb it.
    ///
    /// The earlier design noted the trail when a teacher opened the section and
    /// appended a "noted" marker to the record. That was wrong three ways:
    /// rewriting the file changed its modification date, so the notice showed
    /// the morning rather than the half six the run stopped at; a teacher who
    /// never opened the section — the one who reports "my site did not update"
    /// — got no trail line at all; and it rested on the false premise that
    /// nothing of ours is loaded when the wrapper runs. Plantoir runs it.
    func testReadingTheRecordDoesNotChangeIt() throws {
        ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(
                kind: .neededAnAnswer, destination: "Netlify", when: Date()
            ),
            inHomeFolder: home, course: "ZZQ6U", section: 1
        )
        let url: URL = ScheduledPublishOutcome.recordURL(
            inHomeFolder: home, course: "ZZQ6U", section: 1
        )
        let before: Date = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: url.path))[.modificationDate] as? Date
        )

        for _ in 0..<3 {
            _ = ScheduledPublishOutcome.stopped(inHomeFolder: home, course: "ZZQ6U", section: 1)
        }

        let after: Date = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: url.path))[.modificationDate] as? Date
        )
        XCTAssertEqual(
            before, after,
            "Reading must not touch the file: the record's modification date is what the "
            + "notice shows a teacher, and it has to stay the moment the RUN stopped."
        )
    }

    /// A record is noted on the trail, and a section with none is not.
    func testTheTrailEventMatchesTheKind() throws {
        ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(
                kind: .didNotFinish, destination: "Netlify", when: Date()
            ),
            inHomeFolder: home, course: "ZZQAU", section: 1
        )
        XCTAssertTrue(ScheduledPublishOutcome.noteOnTrail(
            inHomeFolder: home, course: "ZZQAU", section: 1
        ))
        XCTAssertFalse(
            ScheduledPublishOutcome.noteOnTrail(
                inHomeFolder: home, course: "ZZQBU", section: 9
            ),
            "no record, nothing to note"
        )
    }

    /// A build that stopped for a question files under the EXISTING
    /// "needed an answer" event rather than a fourth one.
    ///
    /// Deliberate, and Windows' reasoning adopted: that event is about a
    /// question going unasked, which is what happened, and a fourth event
    /// would put a distinction on the trail that means nothing to the person
    /// reading it.
    ///
    /// This reads the trail FILE rather than trusting `noteOnTrail`'s return
    /// value, which is `true` for any record it could parse — so a version of
    /// this test that only checked the return would pass with the branch
    /// filed under the wrong event, or writing the destination line that this
    /// kind must never show. Both of those are what is asserted here.
    /// `ActivityTrail.note` never writes the event's own name, so the
    /// sentence is what there is to look for.
    func testABuildThatStoppedForAQuestionIsNotedOnTheTrail() throws {
        let scratch: URL = home.appendingPathComponent("trail", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(
                kind: .buildNeededAnAnswer,
                destination: ScheduledPublishOutcome.buildDestinationName,
                when: Date()
            ),
            inHomeFolder: home, course: "ZZQCU", section: 1
        )
        XCTAssertTrue(ScheduledPublishOutcome.noteOnTrail(
            inHomeFolder: home, course: "ZZQCU", section: 1
        ))

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("building the pages needed an answer"),
            "the line a teacher's problem report would carry: \(trail)"
        )
        XCTAssertFalse(
            trail.contains(ScheduledPublishOutcome.buildDestinationName),
            "no destination was reached, so the trail may not name one"
        )
    }

    /// A build that failed outright is noted under the EXISTING "did not
    /// finish" event, with a line naming no destination (#137).
    ///
    /// Reads the trail FILE, for the reason the test above does: the return
    /// value is `true` for any record that parses, so only the line itself
    /// can show that no destination was named.
    func testABuildThatFailedOutrightIsNotedOnTheTrailWithoutADestination() throws {
        let scratch: URL = home.appendingPathComponent("trail-build-failed", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch)
        defer { ActivityTrail.store = previousStore }

        ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(
                kind: .buildDidNotFinish,
                destination: ScheduledPublishOutcome.buildDestinationName,
                when: Date()
            ),
            inHomeFolder: home, course: "ZZQDU", section: 1
        )
        XCTAssertTrue(ScheduledPublishOutcome.noteOnTrail(
            inHomeFolder: home, course: "ZZQDU", section: 1
        ))

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("the pages could not be built"),
            "the line a teacher's problem report would carry: \(trail)"
        )
        XCTAssertFalse(
            trail.contains(ScheduledPublishOutcome.buildDestinationName),
            "no destination was reached, so the trail may not name one"
        )
    }

    // MARK: - What a teacher reads

    /// A build that failed outright names no destination, and is not the
    /// destination-failure sentence with a stand-in filled in (#137).
    ///
    /// The sentence itself is pinned whole against the contract by
    /// `SharedRulesContractTests`; what this pins is the SHAPE — the
    /// contract's template has no destination slot at all, and the rendered
    /// sentence does not carry the record's second line.
    func testTheSentenceForAFailedBuildNamesNoDestination() throws {
        let rule: [String: Any] = try SharedRulesContractTests.section("scheduledPublishStopped")
        let sentences: [String: Any] = try XCTUnwrap(rule["sentences"] as? [String: Any])
        let template: String = try XCTUnwrap(sentences["buildDidNotFinish"] as? String)
        XCTAssertFalse(template.contains("{destination}"))

        let failedBuild = ScheduledPublishOutcome.Stopped(
            kind: .buildDidNotFinish,
            destination: ScheduledPublishOutcome.buildDestinationName,
            when: Date()
        )
        let failedDestination = ScheduledPublishOutcome.Stopped(
            kind: .didNotFinish,
            destination: ScheduledPublishOutcome.buildDestinationName,
            when: Date()
        )
        let sentence: String = ScheduledPublishOutcome.sentence(
            for: failedBuild, course: "ICS3U", section: 2
        )
        XCTAssertFalse(
            sentence.contains(ScheduledPublishOutcome.buildDestinationName),
            "no destination was reached, so none may be named"
        )
        XCTAssertNotEqual(
            sentence,
            ScheduledPublishOutcome.sentence(for: failedDestination, course: "ICS3U", section: 2)
        )
        XCTAssertTrue(failedBuild.kind.needsAttention)
    }

    func testTheSentenceForAnUnansweredQuestionIsTheContractsOwn() throws {
        let stopped = ScheduledPublishOutcome.Stopped(
            kind: .neededAnAnswer, destination: "Netlify", when: Date()
        )
        let sentence: String = ScheduledPublishOutcome.sentence(
            for: stopped, course: "ICS3U", section: 2
        )
        XCTAssertTrue(sentence.contains("ICS3U Section 2"))
        XCTAssertTrue(sentence.contains("needed an answer nobody was there to give"))
        XCTAssertTrue(sentence.contains("Publish this section once yourself"))
    }

    /// A build that stopped for a question names no destination, and sends
    /// the teacher to PREVIEW.
    ///
    /// Both halves matter. The record still carries `buildDestinationName` on
    /// its second line, so asserting the sentence does NOT contain it is what
    /// pins "no destination is named" rather than a wish about the wording.
    /// And previewing is what asks the question, so "Publish this section" —
    /// which is what this case said until GitHub issue #132 — sent a teacher
    /// to the wrong button.
    func testTheSentenceForAStoppedBuildSendsTheTeacherToPreview() throws {
        let stopped = ScheduledPublishOutcome.Stopped(
            kind: .buildNeededAnAnswer,
            destination: ScheduledPublishOutcome.buildDestinationName,
            when: Date()
        )
        let sentence: String = ScheduledPublishOutcome.sentence(
            for: stopped, course: "ICS3U", section: 2
        )
        XCTAssertTrue(sentence.contains("ICS3U Section 2"))
        XCTAssertTrue(sentence.contains("building the pages needed an answer"))
        XCTAssertTrue(sentence.contains("Preview this section once yourself"))
        XCTAssertFalse(sentence.contains("Publish this section once yourself"))
        XCTAssertFalse(
            sentence.contains(ScheduledPublishOutcome.buildDestinationName),
            "no destination was reached, so none may be named"
        )
    }

    func testTheSentenceForAnOrdinaryFailureSaysNothingWentUp() throws {
        let stopped = ScheduledPublishOutcome.Stopped(
            kind: .didNotFinish, destination: "your deploy folder", when: Date()
        )
        let sentence: String = ScheduledPublishOutcome.sentence(
            for: stopped, course: "ICS3U", section: 2
        )
        XCTAssertTrue(sentence.contains("did not finish"))
        XCTAssertTrue(sentence.contains("your deploy folder"))
    }
    // MARK: - Whether the overnight run builds first (issue #265)

    /// A course whose site was built by a publish that STARTED at `started`
    /// and wrote its page at `pageWritten`, with the settings saved at
    /// `settingsSaved`; then the real wrapper, with a `preview.sh` that
    /// leaves a note when it is asked to build. Returns whether it was.
    private func overnightRunBuilt(
        course: String,
        started: TimeInterval,
        settingsSaved: TimeInterval,
        pageWritten: TimeInterval
    ) throws -> Bool {
        let buildNote: URL = workspace.appendingPathComponent("the-build-ran")
        let previewScript: String = "#!/bin/bash\n/usr/bin/touch \(buildNote.path)\nexit 0\n"
        for (name, script) in [("preview.sh", previewScript), ("deploy.sh", "#!/bin/bash\nexit 0\n")] {
            let url: URL = workspace.appendingPathComponent(name)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        let courseURL: URL = workspace.appendingPathComponent("courses").appendingPathComponent(course)
        let siteURL: URL = courseURL.appendingPathComponent(".merged_output/section1")
        try FileManager.default.createDirectory(at: siteURL.appendingPathComponent("public"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true)
        let page: URL = courseURL.appendingPathComponent("section1/index.md")
        let settings: URL = courseURL.appendingPathComponent("course_config.json")
        let builtPage: URL = siteURL.appendingPathComponent("public/index.html")
        let marker: URL = siteURL.appendingPathComponent(BuildFreshness.buildStartedMarkerName)
        try "# lesson\n".write(to: page, atomically: true, encoding: .utf8)
        try "{}\n".write(to: settings, atomically: true, encoding: .utf8)
        try "<html>a published build</html>".write(to: builtPage, atomically: true, encoding: .utf8)
        try "".write(to: marker, atomically: true, encoding: .utf8)

        let now: Date = Date()
        let stamps: [(URL, TimeInterval)] = [
            (page, -600), (marker, started), (settings, settingsSaved), (builtPage, pageWritten),
        ]
        for (url, offset) in stamps {
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(offset)], ofItemAtPath: url.path
            )
        }

        try runWrapper(course: course, section: 1, destinations: ["netlify"], descriptions: ["Netlify"])
        return FileManager.default.fileExists(atPath: buildNote.path)
    }

    /// The reviewer's H1, in the overnight run's own shell: settings saved
    /// while the last publish was building are older than its page, and the
    /// run must still build rather than send that publish's site again.
    func testTheOvernightRunBuildsWhenSettingsWereSavedDuringTheLastBuild() throws {
        XCTAssertTrue(
            try overnightRunBuilt(course: "ZZQ7U", started: -400, settingsSaved: -350, pageWritten: -300),
            "A Save after the last build started was not in it: the overnight run must build first"
        )
    }

    /// And the check still says "up to date" when nothing changed after the
    /// build started — the marker must not make every run rebuild.
    func testTheOvernightRunDoesNotBuildWhenNothingChangedSinceTheBuildStarted() throws {
        XCTAssertFalse(
            try overnightRunBuilt(course: "ZZQ8U", started: -400, settingsSaved: -500, pageWritten: -300)
        )
    }
}
