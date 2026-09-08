import XCTest
@testable import QuartzTeachers

/// Rolling a section over to a new year, and the one question it asks.
///
/// The decision (Russell, 2026-09-08) is that a rollover ASKS whether this
/// should be a new website or last year's, and guesses neither. These pin the
/// two things that make that safe rather than dangerous: an ordinary re-date
/// must never be asked the question, and a section cut loose must not be left
/// with a publish scheduled to run overnight with nobody to answer it.
final class RolloverWebsiteTests: XCTestCase {

    // MARK: - The question is asked of rollovers only

    /// Three of the four phrasings that reach `re_date_classes` are NOT
    /// rollovers, and this is the regression that would hurt most.
    ///
    /// A teacher re-dating after a snow day is mid-semester. Asking them
    /// whether they want a new website — and worse, letting "a new website" be
    /// answered — abandons the address their students are reading right now.
    /// So the ordinary phrasings carry no `rollover`, and the tool must say
    /// nothing about websites when it is absent.
    @MainActor
    func testAnOrdinaryReDateCarriesNoRolloverFlagAndSoIsNeverAskedAboutWebsites() throws {
        let ordinary: [String] = [
            "re-date my classes", "redate my classes", "re-date this section",
        ]
        for phrasing in ordinary {
            let command: AssistCardCommand? = AssistCardCommand.matching(phrasing)
            XCTAssertEqual(command?.toolName, "re_date_classes", phrasing)
            XCTAssertNil(
                command?.arguments["rollover"],
                "“\(phrasing)” is an ordinary re-date. Marking it a rollover would ask a teacher "
                + "mid-semester whether to abandon the address students are reading."
            )
        }
    }

    /// The rollover phrasing carries the flag, and the two answers carry the
    /// answer as well.
    @MainActor
    func testTheRolloverPhrasingsCarryWhatTheyMean() throws {
        let bare: AssistCardCommand? = AssistCardCommand.matching("roll this section over to a new year")
        XCTAssertEqual(bare?.arguments["rollover"], "yes")
        XCTAssertNil(bare?.arguments["website"], "The bare phrasing has not answered anything yet.")

        let fresh: AssistCardCommand? = AssistCardCommand.matching(
            AssistCardCommand.rollOverOntoANewWebsite
        )
        XCTAssertEqual(fresh?.arguments["rollover"], "yes")
        XCTAssertEqual(fresh?.arguments["website"], "new")

        let same: AssistCardCommand? = AssistCardCommand.matching(
            AssistCardCommand.rollOverKeepingTheSameWebsite
        )
        XCTAssertEqual(same?.arguments["rollover"], "yes")
        XCTAssertEqual(same?.arguments["website"], "same")
    }

    /// The sentences the assistant offers back must be sentences it accepts.
    ///
    /// The reply tells a teacher to say one of two things word for word. If
    /// the matcher did not take those exact strings, the feature would invite
    /// a sentence it then failed to understand — which is worse than not
    /// offering one.
    @MainActor
    func testTheOfferedAnswersAreAcceptedVerbatim() throws {
        for offered in [AssistCardCommand.rollOverOntoANewWebsite,
                        AssistCardCommand.rollOverKeepingTheSameWebsite] {
            XCTAssertNotNil(
                AssistCardCommand.matching(offered),
                "The reply offers “\(offered)” — the matcher must accept it."
            )
        }
    }

    // MARK: - Cutting a section loose

    /// Every destination type, not just the course's primary one.
    ///
    /// Markers are keyed by destination TYPE, and a course can carry
    /// additional targets, so releasing only the primary would leave an
    /// additional destination still overwriting last year's site. This is the
    /// deliberate divergence from Windows, whose `ReleaseSite` returns inside
    /// the first folder that has a marker.
    @MainActor
    func testReleasingASectionReleasesEveryDestinationNotJustThePrimary() throws {
        let (root, course, _, _) = try makeCourseWithMarkers(netlify: true, cloudflare: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let release: DeployCommand.SiteRelease = DeployCommand.releaseSite(
            forSection: 1, in: course
        )

        XCTAssertEqual(release.keptFiles.count, 2, "Both destinations should have been released.")
        XCTAssertTrue(release.releasedAnything)
        for folder in [".netlify_sites", ".cloudflare_sites"] {
            let live: URL = course.directoryURL.appendingPathComponent("\(folder)/section1.json")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: live.path),
                "\(folder) is still pinned to last year's website."
            )
        }
    }

    /// Renamed aside, never deleted — the file holds the way back.
    @MainActor
    func testTheReleasedFileIsKeptRatherThanDeleted() throws {
        let (root, course, _, _) = try makeCourseWithMarkers(netlify: true, cloudflare: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let release: DeployCommand.SiteRelease = DeployCommand.releaseSite(
            forSection: 1, in: course
        )
        let kept: [URL] = try FileManager.default.contentsOfDirectory(
            at: course.directoryURL.appendingPathComponent(".netlify_sites"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(kept.count, 1, "The details must still be on disk somewhere.")
        XCTAssertTrue(kept[0].lastPathComponent.contains(".previous-"))
        XCTAssertEqual(
            try String(contentsOf: kept[0], encoding: .utf8), "{\"site\":\"last-year\"}",
            "The kept file must still hold last year's details."
        )
        XCTAssertEqual(release.keptFiles.count, 1)
    }

    /// A section nobody has published has nothing to be cut loose from, and
    /// that is not a failure.
    @MainActor
    func testReleasingASectionThatWasNeverPublishedDoesNothing() throws {
        let (root, course, _, _) = try makeCourseWithMarkers(netlify: false, cloudflare: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let release: DeployCommand.SiteRelease = DeployCommand.releaseSite(
            forSection: 1, in: course
        )
        XCTAssertFalse(release.releasedAnything)
        XCTAssertTrue(release.savedFiles.isEmpty)
    }

    /// The kept name is frozen and shared with Windows, so a teacher is told
    /// the same filename whichever app they are sitting at.
    @MainActor
    func testTheKeptNameMatchesTheNameWindowsWrites() throws {
        var parts: DateComponents = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 8
        parts.hour = 7; parts.minute = 15; parts.second = 0
        let moment: Date = Calendar.current.date(from: parts) ?? Date()

        XCTAssertEqual(
            DeployCommand.releasedMarkerName(forSection: 3, at: moment),
            "section3.previous-2026-09-08_071500.json"
        )
    }

    // MARK: - Undo

    /// A move is two entries, and until `after` was widened the source half
    /// could not be expressed at all.
    ///
    /// The file is gone from the source path, so it reads back as nil — which
    /// matched no `String`, so `undo()` skipped it every time and a release
    /// could never be taken back. Windows' undo has always put the section
    /// back on last year's site; this is the mac doing the same.
    @MainActor
    func testAReleaseCanBeUndone() throws {
        let (root, course, _, _) = try makeCourseWithMarkers(netlify: true, cloudflare: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let release: DeployCommand.SiteRelease = DeployCommand.releaseSite(
            forSection: 1, in: course
        )
        XCTAssertEqual(release.savedFiles.count, 2, "A move is recorded as two halves.")

        let history: AssistChangeHistory = AssistChangeHistory()
        history.record(
            AssistChange(
                whatHappened: "started a new website for Section 1",
                courseCode: course.code,
                sectionNumber: 1,
                rebuildsThePreview: false,
                files: release.savedFiles
            )
        )
        let undone: AssistUndoResult = history.undo()

        XCTAssertTrue(undone.succeeded, "The release should be undoable.")
        let live: URL = course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: live.path),
            "Undoing must put the section back on last year's website."
        )
        XCTAssertEqual(
            try String(contentsOf: live, encoding: .utf8), "{\"site\":\"last-year\"}"
        )
    }


    // MARK: - What the tool actually says and does

    /// An ordinary re-date must say NOTHING about websites.
    ///
    /// This is the wiring half of the first test above: the phrasing carries
    /// no `rollover`, and the tool must therefore stay silent on the subject
    /// rather than volunteering a question.
    @MainActor
    func testAnOrdinaryReDateSaysNothingAboutWebsites() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating()
        defer { try? FileManager.default.removeItem(at: root) }

        let said: String = await reDate(runner, course: course, arguments: [:])
        for fragment in ["website", "Website"] {
            XCTAssertFalse(
                said.contains(fragment),
                "An ordinary re-date must not raise websites at all: \(said)"
            )
        }
    }

    /// A rollover with no answer yet asks, offers both sentences, and says
    /// plainly that nothing about the website changed.
    ///
    /// The last part is what stops this feature quietly recreating the defect
    /// it was built to fix: the re-dating has already happened by now, so a
    /// teacher who ignores the question — or a Claude Code session, which can
    /// see no sheet at all — must not be left believing it was dealt with.
    @MainActor
    func testARolloverWithNoAnswerAsksAndChangesNoWebsite() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let said: String = await reDate(runner, course: course, arguments: ["rollover": "yes"])

        XCTAssertTrue(said.contains(AssistWording.rolloverWebsiteQuestion), said)
        XCTAssertTrue(said.contains(AssistCardCommand.rollOverOntoANewWebsite), said)
        XCTAssertTrue(said.contains(AssistCardCommand.rollOverKeepingTheSameWebsite), said)
        XCTAssertTrue(said.contains(AssistWording.rolloverWebsiteNotDecided), said)

        let live: URL = course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: live.path),
            "An unanswered question must not cut the section loose."
        )
    }

    /// Answering "the same one" changes nothing and says so.
    @MainActor
    func testKeepingTheSameWebsiteLeavesItAlone() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let said: String = await reDate(
            runner, course: course, arguments: ["rollover": "yes", "website": "same"]
        )
        XCTAssertTrue(said.contains(AssistWording.rolloverKeptTheSameWebsite), said)
        let live: URL = course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path))
    }

    /// Answering "a new website" cuts the section loose and names where last
    /// year's details went.
    @MainActor
    func testStartingANewWebsiteCutsTheSectionLoose() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let said: String = await reDate(
            runner, course: course, arguments: ["rollover": "yes", "website": "new"]
        )
        XCTAssertTrue(said.contains("no longer tied to last year"), said)
        XCTAssertTrue(said.contains(".previous-"), "It must say where the way back is: \(said)")

        let live: URL = course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))
    }

    /// A section that was never published is told so, rather than being told
    /// about a move that did not happen.
    @MainActor
    func testStartingANewWebsiteForASectionThatNeverHadOne() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let said: String = await reDate(
            runner, course: course, arguments: ["rollover": "yes", "website": "new"]
        )
        XCTAssertTrue(said.contains(AssistWording.rolloverHadNoWebsiteYet), said)
    }


    /// Cutting a section loose turns off a publish set to happen on its own,
    /// and says so.
    ///
    /// **The most consequential behaviour here and it had no test.** A section
    /// with no agreed website and a scheduled run has nobody to ask what the
    /// new one should be called — and `deploy.py`'s prompt returns its DEFAULT
    /// with no terminal rather than failing, so the overnight run would create
    /// a website nobody named while the address students read stopped updating.
    @MainActor
    func testStartingANewWebsiteTurnsOffAScheduledPublish() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plistURL: URL = ScheduledDeploy.plistURL(courseCode: course.code, sectionNumber: 1)
        try "<plist/>".write(to: plistURL, atomically: true, encoding: .utf8)

        let said: String = await reDate(
            runner, course: course, arguments: ["rollover": "yes", "website": "new"]
        )

        XCTAssertTrue(
            said.contains(AssistWording.rolloverTurnedOffTheScheduledPublish),
            "A teacher must be told their scheduled publish was turned off: \(said)"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: plistURL.path),
            "The scheduled publish must actually be gone, not just described as gone."
        )
    }

    /// A section with no scheduled publish is told nothing about one.
    @MainActor
    func testWithNoScheduledPublishNothingIsSaidAboutOne() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let said: String = await reDate(
            runner, course: course, arguments: ["rollover": "yes", "website": "new"]
        )
        XCTAssertFalse(said.contains("set to publish on its own"), said)
    }

    /// Answering the question is the SECOND turn, and by then the pages are
    /// already on their dates.
    ///
    /// The plan then changes nothing, and an early return on that made the
    /// whole answer a no-op: the reply talked about dates, never mentioned the
    /// website, and left the section pinned to last year's — with an offer that
    /// looked like it had worked.
    @MainActor
    func testAnsweringTheQuestionOnASecondTurnStillCutsTheSectionLoose() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // First turn: re-dates, and asks.
        let asked: String = await reDate(runner, course: course, arguments: ["rollover": "yes"])
        XCTAssertTrue(asked.contains(AssistWording.rolloverWebsiteQuestion), asked)

        // Second turn: the teacher says one of the two sentences back.
        let answered: String = await reDate(
            runner, course: course, arguments: ["rollover": "yes", "website": "new"]
        )
        XCTAssertTrue(
            answered.contains("no longer tied to last year"),
            "Answering must settle the website even though the re-date now changes nothing: \(answered)"
        )
        let live: URL = course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: live.path),
            "The section is still pinned — the answer did nothing."
        )
    }

    /// A destination that could not be released must not be reported as one
    /// that was never published.
    @MainActor
    func testAMarkerThatCannotBeReleasedIsNotCalledNeverPublished() throws {
        let (root, course, _, _) = try makeCourseWithMarkers(netlify: true, cloudflare: false)
        defer { try? FileManager.default.removeItem(at: root) }

        // A directory sitting where the kept file would go makes the move fail
        // without touching the marker.
        var parts: DateComponents = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 8
        parts.hour = 7; parts.minute = 15; parts.second = 0
        let moment: Date = try XCTUnwrap(Calendar.current.date(from: parts))
        let blocker: URL = course.directoryURL
            .appendingPathComponent(".netlify_sites")
            .appendingPathComponent(DeployCommand.releasedMarkerName(forSection: 1, at: moment))
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)

        let release: DeployCommand.SiteRelease = DeployCommand.releaseSite(
            forSection: 1, in: course, at: moment
        )
        XCTAssertFalse(release.releasedAnything)
        XCTAssertTrue(release.somethingIsStillPinned, "The section is still pinned and must say so.")
        XCTAssertEqual(release.stillPinned, [".netlify_sites/section1.json"])
    }


    // MARK: - The teacher has to be able to SEE it

    /// The question must be in the SUMMARY, not the detail.
    ///
    /// `AssistToolOutcome.wrote` leaves `teacherDetail` nil, and the window
    /// renders `entry.detail` from that — so anything put only in `detail` is
    /// invisible in the app and the feature works over MCP alone. The first
    /// version of this did exactly that: a teacher saw "Re-dated 3 classes…"
    /// and no question at all.
    @MainActor
    func testTheQuestionIsInWhatTheTeacherActuallyReads() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome: AssistToolOutcome = await runTool(
            runner, course: course, arguments: ["rollover": "yes"]
        )
        XCTAssertTrue(
            outcome.summary.contains(AssistWording.rolloverWebsiteQuestion),
            "The question must be in the summary, which is what a teacher reads: \(outcome.summary)"
        )
    }

    /// An MCP client has no card, so `website` alone must be enough.
    ///
    /// It is the one surface that cannot show a sheet — which is the whole
    /// stated reason this is answered in words — so a caller that could not
    /// say which website the teacher chose could not roll a section over at
    /// all. `website` is on the published schema for exactly this.
    @MainActor
    func testAnMCPCallerCanRollOverWithWebsiteAlone() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // No `rollover` key, as an MCP client would call it.
        let said: String = await reDate(runner, course: course, arguments: ["website": "new"])
        XCTAssertTrue(said.contains("no longer tied to last year"), said)
        let live: URL = course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))
    }

    /// `website` is on the schema so a Claude Code session can set it.
    @MainActor
    func testWebsiteIsOnThePublishedSchemaButRolloverIsNot() throws {
        let tool: AssistToolDefinition = try XCTUnwrap(
            AssistToolRunner.tools.first(where: { $0.name == "re_date_classes" })
        )
        XCTAssertNotNil(tool.parameters["website"], "An MCP client must be able to answer.")
        XCTAssertNil(
            tool.parameters["rollover"],
            "`rollover` stays off the schema: the app's card supplies it and no model needs it."
        )
    }

    /// Under plan mode — which is ON by default — the answer turn must still
    /// reach the real call.
    ///
    /// `showPlan` returns early whenever the twin hands back something that is
    /// not a plan. The twin's "already on the day it should be" is a write, so
    /// the answer turn dead-ended and the website was never settled: in the
    /// DEFAULT configuration the release was unreachable.
    @MainActor
    func testThePlanTwinStillPlansWhenOnlyTheWebsiteWouldChange() async throws {
        let (root, course, runner) = try makeSectionNeedingReDating(withMarker: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // First turn re-dates, so the pages are already right by the second.
        _ = await reDate(runner, course: course, arguments: ["rollover": "yes"])

        let outcome: AssistToolOutcome = await runTool(
            runner, course: course,
            arguments: ["rollover": "yes", "website": "new"],
            tool: "plan_re_date_classes"
        )
        XCTAssertTrue(
            outcome.isPlan,
            "The twin must still offer a PLAN, or plan mode swallows the answer and the "
            + "website is never settled: \(outcome.summary)"
        )
    }

    // MARK: - Helpers


    /// A section with class dates on file and one page sitting on the wrong
    /// day, built on the shared fixture so the course, its settings and its
    /// site marker are the ones every other assistant test uses.
    @MainActor
    private func makeSectionNeedingReDating(
        withMarker: Bool = false
    ) throws -> (root: URL, course: Course, runner: AssistToolRunner) {
        let made = try AssistFixture.makeRunner(hasDeployedBefore: withMarker)

        // Point scheduled-publish lookups at a throwaway folder. Without this
        // `plistURL` resolves to the REAL ~/Library/LaunchAgents, and the
        // fixture's course is ICS3U — a course a teacher plausibly has
        // scheduled — so a test could boot out and delete their agent.
        let agentsDirectory: URL = made.root.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(
            at: agentsDirectory, withIntermediateDirectories: true
        )
        ScheduledDeploy.launchAgentsDirectoryOverride = agentsDirectory
        addTeardownBlock {
            MainActor.assumeIsolated { ScheduledDeploy.launchAgentsDirectoryOverride = nil }
        }

        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08", "2026-09-10"], source: "timetable.xlsx, block H",
            forSection: 1, in: made.course
        )
        try SectionTimetableStore.applyRememberTimetable(plan)

        // Dated a day the section does not meet, so a re-date has something
        // real to move and does not stop at "already on the right day".
        let classesURL: URL = made.course.directoryURL
            .appendingPathComponent("section1/All Classes")
        try """
        ---
        title: Unit 1, Day 1
        date: 2020-01-15
        ---
        Something to move.
        """.write(
            to: classesURL.appendingPathComponent("Unit 1, Day 1.md"),
            atomically: true, encoding: .utf8
        )
        return (made.root, made.course, made.runner)
    }

    /// Run a tool and hand back the whole outcome.
    @MainActor
    private func runTool(
        _ runner: AssistToolRunner, course: Course, arguments: [String: Any],
        tool: String = "re_date_classes"
    ) async -> AssistToolOutcome {
        var full: [String: Any] = arguments
        full["course"] = course.code
        full["section"] = 1
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: full)) ?? Data("{}".utf8)
        return await runner.run(
            call: AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(
                    name: tool, arguments: String(decoding: encoded, as: UTF8.self)
                )
            )
        )
    }

    /// Run `re_date_classes` and hand back what the teacher would read.
    @MainActor
    private func reDate(
        _ runner: AssistToolRunner, course: Course, arguments: [String: Any]
    ) async -> String {
        var full: [String: Any] = arguments
        full["course"] = course.code
        full["section"] = 1
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: full)) ?? Data("{}".utf8)
        let outcome: AssistToolOutcome = await runner.run(
            call: AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(
                    name: "re_date_classes", arguments: String(decoding: encoded, as: UTF8.self)
                )
            )
        )
        return outcome.detail
    }

    /// A course with whichever site markers the test needs.
    @MainActor
    private func makeCourseWithMarkers(
        netlify: Bool, cloudflare: Bool
    ) throws -> (root: URL, course: Course, courseURL: URL, sectionURL: URL) {
        let fileManager: FileManager = FileManager.default
        let root: URL = fileManager.temporaryDirectory
            .appendingPathComponent("rollover-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        let sectionURL: URL = courseURL.appendingPathComponent("section1")
        try fileManager.createDirectory(at: sectionURL, withIntermediateDirectories: true)

        for (wanted, folder) in [(netlify, ".netlify_sites"), (cloudflare, ".cloudflare_sites")]
        where wanted {
            let markerFolder: URL = courseURL.appendingPathComponent(folder)
            try fileManager.createDirectory(at: markerFolder, withIntermediateDirectories: true)
            try "{\"site\":\"last-year\"}".write(
                to: markerFolder.appendingPathComponent("section1.json"),
                atomically: true, encoding: .utf8
            )
        }

        // Written and read back the way the app and the shared Python both
        // see it, rather than hand-built, so the destination types this walks
        // are the real ones.
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(
            withJSONObject: ["course_code": "ICS3U"], options: [.prettyPrinted, .sortedKeys]
        ).write(to: configURL)
        let course: Course = Course(
            code: "ICS3U",
            directoryURL: courseURL,
            configuration: try CourseConfiguration(contentsOf: configURL)
        )
        return (root, course, courseURL, sectionURL)
    }
}
