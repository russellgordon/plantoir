import XCTest
@testable import QuartzTeachers

/// What a scheduled publish leaves behind when it does not get through — and
/// these tests RUN THE GENERATED SHELL rather than reading it.
///
/// That distinction is the point of the file. The wrapper is bash written by
/// Swift and executed by launchd at half six with nothing of ours loaded, so a
/// test that only asserts the generated TEXT proves the string is what we meant
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
        try FileManager.default.createDirectory(
            at: ScheduledDeploy.launchAgentsDirectoryOverride!, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
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
    func testABuildThatNeededAnAnswerIsRecorded() throws {
        try writeStubLaunchers(deployExit: 0, previewExit: 3)
        try runWrapper(
            course: "ZZQ7U", section: 1,
            destinations: ["netlify"], descriptions: ["Netlify"]
        )
        let stopped = ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ZZQ7U", section: 1
        )
        XCTAssertEqual(stopped?.kind, .neededAnAnswer)
        XCTAssertEqual(stopped?.destination, ScheduledPublishOutcome.buildDestinationName)
    }

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
            .didNotFinish
        )
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

    /// The two kinds go on the trail as two different events.
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

    // MARK: - What a teacher reads

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
}
