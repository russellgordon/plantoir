import XCTest
@testable import QuartzTeachers

/// The teacher's How I Teach page (#209): recognised by the contract's name
/// cases, left out of the assistant's page listings (and NOT out of the walk
/// link rewriting uses), read and written by three MCP-only tools that keep a
/// teacher's own page safe, and briefed to an outside session.
///
/// The rule is `contracts/shared-rules.json` → `howITeachPage`; every name
/// case is read FROM it, never retyped. The build's half — that the page never
/// reaches a website — is shared Python (`scripts/test_how_i_teach.py`, and
/// `verify.sh` against the real image).
@MainActor
final class HowITeachTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")
    var workspace: WorkspaceModel = WorkspaceModel()
    var siteWork: StubSiteWork = StubSiteWork()
    var runner: AssistToolRunner = AssistToolRunner(workspace: WorkspaceModel())
    var live: Course = HowITeachTests.placeholder()
    var reference: Course = HowITeachTests.placeholder()

    static func placeholder() -> Course {
        return Course(
            code: "", directoryURL: URL(fileURLWithPath: "/"),
            configuration: CourseConfiguration(values: [:], lastSavedData: Data())
        )
    }

    // MARK: - Setting up

    /// A working folder with ICS4U (live, sections 1 and 2) and, when asked,
    /// ICS4U-2025 kept for reference — the trail pointed at a scratch folder.
    func prepare(withReference: Bool = false, surface: AssistToolRunner.Surface = .mcp,
                 beforeLoading: ((URL) throws -> Void)? = nil) throws {
        let fileManager: FileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent("how-i-teach-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root.appendingPathComponent("courses"), withIntermediateDirectories: true)
        for launcher in ["preview.sh", "deploy.sh"] {
            try "#!/bin/bash\n".write(to: root.appendingPathComponent(launcher), atomically: true, encoding: .utf8)
        }
        let previousTrail: ProblemReportStore = ActivityTrail.store
        let trailFolder: URL = root.appendingPathComponent("trail")
        try fileManager.createDirectory(at: trailFolder, withIntermediateDirectories: true)
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)

        try writeCourse(folder: "ICS4U", code: "ICS4U", keptForReference: false)
        if withReference {
            try writeCourse(folder: "ICS4U-2025", code: "ICS4U", keptForReference: true)
        }
        if let beforeLoading {
            try beforeLoading(root.appendingPathComponent("courses"))
        }

        workspace = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        for candidate in workspace.courses {
            if candidate.code == "ICS4U" { live = candidate }
            if candidate.code == "ICS4U-2025" { reference = candidate }
        }
        siteWork = StubSiteWork()
        runner = AssistToolRunner(
            workspace: workspace,
            siteWork: siteWork,
            today: { return CalendarDay(year: 2026, month: 9, day: 26)! },
            launchControl: SilentLaunchControl(),
            surface: surface
        )

        let treeRoot: URL = root
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousTrail
                ReferenceLock.clearLock(at: treeRoot)
            }
            try? FileManager.default.removeItem(at: treeRoot)
        }
    }

    private func writeCourse(folder: String, code: String, keptForReference: Bool) throws {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent(folder)
        for section in ["section1/All Classes", "section2/All Classes", "Concepts"] {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent(section), withIntermediateDirectories: true
            )
        }
        try "# Welcome\n".write(
            to: courseURL.appendingPathComponent("section1/index.md"), atomically: true, encoding: .utf8
        )
        var values: [String: Any] = [
            "course_code": code,
            "course_name": "Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        if keptForReference {
            values["kept_for_reference"] = true
            values["reference_school_year"] = 2025
        }
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
    }

    private func run(_ tool: String, _ arguments: [String: Any]) async -> AssistToolOutcome {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return await runner.run(call: AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(name: tool, arguments: String(decoding: encoded, as: UTF8.self))
        ))
    }

    private var pageURL: URL {
        return live.directoryURL.appendingPathComponent(HowITeachPage.fileName)
    }

    private func bytes(_ url: URL) -> Data? {
        return try? Data(contentsOf: url)
    }

    private func trail() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    private static func contractRule() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["howITeachPage"] as? [String: Any])
    }

    // MARK: - The name, from the contract

    func testTheNameAndTheLimitAreTheContracts() throws {
        let rule: [String: Any] = try HowITeachTests.contractRule()
        XCTAssertEqual(rule["fileName"] as? String, HowITeachPage.fileName)
        let tools: [String: Any] = try XCTUnwrap(rule["tools"] as? [String: Any])
        XCTAssertEqual(tools["mostCharacters"] as? Int, HowITeachPage.mostCharacters)
        var names: [String] = []
        for tool in AssistToolRunner.mcpOnlyTools {
            names.append(tool.name)
        }
        for name in try XCTUnwrap(tools["names"] as? [String]) {
            XCTAssertTrue(names.contains(name), "\(name) is not an MCP-only tool")
        }
    }

    /// Every `nameCases` case: whether it is reserved, whether the assistant
    /// lists it for section 1 — and that the walk link rewriting uses still
    /// sees every page, reserved or not (#209 plan review, item 2).
    func testEveryNameCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try HowITeachTests.contractRule()["nameCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for one in cases {
            let path: String = try XCTUnwrap(one["path"] as? String)
            let reserved: Bool = try XCTUnwrap(one["reserved"] as? Bool)
            let listed: Bool = try XCTUnwrap(one["listedAsAPage"] as? Bool)
            // A fresh course per case: "How I Teach.md" and "how i teach.md"
            // are the same file on this volume.
            try prepare()
            let fileURL: URL = live.directoryURL.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try "words\n".write(to: fileURL, atomically: true, encoding: .utf8)

            XCTAssertEqual(HowITeachPage.isTheHowITeachPage(fileURL, in: live), reserved, "reserved: \(path)")
            var listedPaths: [String] = []
            for page in ClassPages.pagesTheAssistantLists(forSection: 1, in: live) {
                listedPaths.append(page.standardizedFileURL.path)
            }
            XCTAssertEqual(listedPaths.contains(fileURL.standardizedFileURL.path), listed, "listed: \(path)")
            if fileURL.pathExtension.lowercased() == "md" && !path.hasPrefix("section2/") {
                var walked: [String] = []
                for page in ClassPages.pagesOfSection(1, in: live) {
                    walked.append(page.standardizedFileURL.path)
                }
                XCTAssertTrue(walked.contains(fileURL.standardizedFileURL.path),
                              "the link-rewriting walk must still see \(path)")
            }
        }
    }

    /// Making room renames classes, and a How I Teach page that links to one
    /// must follow it — Obsidian rewrites links only when IT does the rename.
    func testMakingRoomRewritesALinkOnTheHowITeachPage() async throws {
        try prepare()
        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08", "2026-09-10", "2026-09-15", "2026-09-17", "2026-09-22"],
            source: "timetable.xlsx, block H", forSection: 1, in: live
        )
        try SectionTimetableStore.applyRememberTimetable(plan)
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", date: "2026-09-08", body: "one", in: live)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "false", date: "2026-09-10", body: "two", in: live)
        try "I start with [[Unit 1, Day 2]].\n".write(to: pageURL, atomically: true, encoding: .utf8)

        _ = await run("make_room_for_classes", ["course": "ICS4U", "section": 1, "unit": 1, "atDay": 2])

        let after: String = try String(contentsOf: pageURL, encoding: .utf8)
        XCTAssertTrue(after.contains("[[Unit 1, Day 3]]"), "the How I Teach page's link did not follow: \(after)")
    }

    // MARK: - Reading it

    func testReadingAPageGivesItsWordsAndLeavesACountOnTheTrail() async throws {
        try prepare()
        try "---\npublish: false\n---\n\nWe never give notes before the exploration zebraquill.\n"
            .write(to: pageURL, atomically: true, encoding: .utf8)

        let outcome: AssistToolOutcome = await run("read_how_i_teach", ["course": "ICS4U"])

        XCTAssertTrue(outcome.detail.contains("zebraquill"), outcome.detail)
        XCTAssertTrue(outcome.detail.hasPrefix(AssistWording.howITeachRead(course: "ICS4U", text: "")))
        XCTAssertFalse(outcome.detail.contains("publish: false"), "the settings are Plantoir's, not the teacher's words")
        let trail: String = trail()
        XCTAssertTrue(trail.contains("ICS4U · an outside assistant read the How I Teach page (8 words)"), trail)
        XCTAssertFalse(trail.contains("zebraquill"), "the trail never carries the page's words")
    }

    func testReadingNoPageSaysWhereOneGoesAndHowToOfferADraft() async throws {
        try prepare()
        let outcome: AssistToolOutcome = await run("read_how_i_teach", ["course": "ICS4U"])
        XCTAssertEqual(
            outcome.detail,
            AssistWording.howITeachMissing(course: "ICS4U") + "\n\n" + AssistWording.howITeachDraftingBrief
        )
        XCTAssertTrue(trail().contains("ICS4U · an outside assistant found no How I Teach page yet"))
    }

    func testALongPageIsCutAndNamesItsFile() async throws {
        try prepare()
        let long: String = String(repeating: "word ", count: 2000)
        try long.write(to: pageURL, atomically: true, encoding: .utf8)
        let outcome: AssistToolOutcome = await run("read_how_i_teach", ["course": "ICS4U"])
        XCTAssertTrue(outcome.detail.contains(AssistWording.howITeachCutShort(
            course: "ICS4U", path: AssistSectionGraph.relativePath(of: pageURL, workspaceURL: workspace.workspaceURL)
        )), outcome.detail)
        XCTAssertTrue(trail().contains("2000 words, more than one answer carries"), trail())
    }

    func testTheTeachersOwnSpellingIsWhatIsRead() async throws {
        try prepare()
        let lower: URL = live.directoryURL.appendingPathComponent("how i teach.md")
        try "lowercase page\n".write(to: lower, atomically: true, encoding: .utf8)
        let outcome: AssistToolOutcome = await run("read_how_i_teach", ["course": "ICS4U"])
        XCTAssertTrue(outcome.detail.contains("lowercase page"), outcome.detail)
        XCTAssertEqual(HowITeachPage.existingURL(for: live)?.lastPathComponent, "how i teach.md")
    }

    func testAReferenceCoursesPageCanBeRead() async throws {
        try prepare(withReference: true) { courses in
            try "Last year I taught by pinecrest.\n".write(
                to: courses.appendingPathComponent("ICS4U-2025/How I Teach.md"), atomically: true, encoding: .utf8
            )
        }
        let outcome: AssistToolOutcome = await run("read_how_i_teach", ["course": "ICS4U-2025"])
        XCTAssertTrue(outcome.detail.contains("pinecrest"), outcome.detail)
    }

    // MARK: - Writing it

    func testANewPageIsWrittenHiddenWithTheExactBytes() async throws {
        try prepare()
        let outcome: AssistToolOutcome = await run(
            "write_how_i_teach", ["course": "ICS4U", "text": "\n  I teach by asking first.  \n\n"]
        )
        XCTAssertEqual(outcome.summary, AssistWording.howITeachSaved(course: "ICS4U"))
        XCTAssertEqual(
            try String(contentsOf: pageURL, encoding: .utf8),
            "---\npublish: false\n---\n\nI teach by asking first.\n"
        )
    }

    func testTheTeachersPageIsNeverReplacedWithoutTheMark() async throws {
        try prepare()
        let original: Data = Data("My own words.\n".utf8)
        try original.write(to: pageURL)

        let refused: AssistToolOutcome = await run("write_how_i_teach", ["course": "ICS4U", "text": "Theirs."])
        XCTAssertEqual(refused.summary, AssistWording.howITeachAlreadyWritten(course: "ICS4U"))
        XCTAssertEqual(bytes(pageURL), original)

        let wrongMark: AssistToolOutcome = await run(
            "write_how_i_teach", ["course": "ICS4U", "text": "Theirs.", "replacing": "00000000"]
        )
        XCTAssertEqual(wrongMark.summary, AssistWording.howITeachChangedSincePlanned(course: "ICS4U"))
        XCTAssertEqual(bytes(pageURL), original)
    }

    func testThePlanGivesTheMarkThatReplaces() async throws {
        try prepare()
        let original: Data = Data("My own words, all five.\n".utf8)
        try original.write(to: pageURL)
        let mark: String = HowITeachPage.mark(of: original)
        XCTAssertEqual(mark.count, 8)

        let plan: AssistToolOutcome = await run("plan_write_how_i_teach", ["course": "ICS4U", "text": "New."])
        XCTAssertTrue(plan.detail.contains("replacing: “\(mark)”"), plan.detail)
        XCTAssertTrue(plan.detail.contains("(5 words"), plan.detail)
        XCTAssertEqual(bytes(pageURL), original, "a plan changes nothing")

        _ = await run("write_how_i_teach", ["course": "ICS4U", "text": "New.", "replacing": mark])
        XCTAssertEqual(try String(contentsOf: pageURL, encoding: .utf8), "New.\n",
                       "a page with no settings is given none — the location is the guarantee")
    }

    func testReplacingKeepsTheirSettingsByteForByte() async throws {
        let shapes: [(existing: String, expected: String)] = [
            ("---\ntags: [mine]\npublish: false # keep\n---\nold body\n",
             "---\ntags: [mine]\npublish: false # keep\n---\n\nNew body.\n"),
            ("---\r\ntags: [mine]\r\n---\r\nold body\r\n",
             "---\r\ntags: [mine]\r\n---\r\n\r\nNew body.\r\n"),
            ("\u{FEFF}---\ntitle: x\n---\nold\n",
             "\u{FEFF}---\ntitle: x\n---\n\nNew body.\n"),
            // Opens a fence and never closes it: nothing to keep, and the old
            // text must NOT survive under a swallowed "block".
            ("---\nnever closed\nold body\n", "New body.\n"),
        ]
        for shape in shapes {
            try prepare()
            let data: Data = Data(shape.existing.utf8)
            try data.write(to: pageURL)
            let outcome: AssistToolOutcome = await run(
                "write_how_i_teach",
                ["course": "ICS4U", "text": "New body.", "replacing": HowITeachPage.mark(of: data)]
            )
            XCTAssertEqual(outcome.summary, AssistWording.howITeachSaved(course: "ICS4U"))
            XCTAssertEqual(bytes(pageURL), Data(shape.expected.utf8), "replacing \(shape.existing.debugDescription)")
        }
    }

    func testTextThatCannotBeSavedIsRefusedByThePlanAndTheWrite() async throws {
        try prepare()
        let refusals: [(text: String, said: String)] = [
            ("   \n ", AssistWording.howITeachNeedsWords),
            (String(repeating: "a", count: HowITeachPage.mostCharacters + 1), AssistWording.howITeachTooLong),
            ("---\npublish: true\n---\nhi", AssistWording.howITeachCarriesNoSettings),
            ("\u{FEFF}\n\n  ---  \npublish: true\n---\nhi", AssistWording.howITeachCarriesNoSettings),
        ]
        for refusal in refusals {
            let plan: AssistToolOutcome = await run("plan_write_how_i_teach", ["course": "ICS4U", "text": refusal.text])
            XCTAssertEqual(plan.summary, refusal.said)
            let write: AssistToolOutcome = await run("write_how_i_teach", ["course": "ICS4U", "text": refusal.text])
            XCTAssertEqual(write.summary, refusal.said)
            XCTAssertFalse(FileManager.default.fileExists(atPath: pageURL.path))
        }
        // Exactly the limit is allowed.
        let atTheLimit: AssistToolOutcome = await run(
            "write_how_i_teach", ["course": "ICS4U", "text": String(repeating: "a", count: HowITeachPage.mostCharacters)]
        )
        XCTAssertEqual(atTheLimit.summary, AssistWording.howITeachSaved(course: "ICS4U"))
    }

    func testAReferenceCourseIsNeverWrittenAndThePlanSaysSo() async throws {
        try prepare(withReference: true)
        let referencePage: URL = reference.directoryURL.appendingPathComponent(HowITeachPage.fileName)
        let expected: String = AssistToolRefusal.keptForReference(reference.displayCode).message
        let plan: AssistToolOutcome = await run("plan_write_how_i_teach", ["course": "ICS4U-2025", "text": "x"])
        XCTAssertEqual(plan.summary, expected)
        let write: AssistToolOutcome = await run("write_how_i_teach", ["course": "ICS4U-2025", "text": "x"])
        XCTAssertEqual(write.summary, expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: referencePage.path))
    }

    func testTheCourseIsBackedUpBeforeTheFirstWrite() async throws {
        try prepare()
        XCTAssertFalse(runner.hasConversationBackup)
        _ = await run("write_how_i_teach", ["course": "ICS4U", "text": "Hello."])
        XCTAssertTrue(runner.hasConversationBackup)
        let backups: [URL] = runner.backupsThisConversationMade
        XCTAssertEqual(backups.count, 1)
        let backup: URL = try XCTUnwrap(backups.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let trail: String = trail()
        XCTAssertTrue(trail.contains("ICS4U · an outside assistant wrote a new How I Teach page (1 word), "
                                     + "after backing up the course as \(backup.lastPathComponent)"), trail)
        XCTAssertFalse(trail.contains("Hello."), "the trail never carries the page's words")
    }

    func testUndoTakesBackTheWriteAndNeverTouchesAPreview() async throws {
        try prepare()
        let original: Data = Data("Mine.\n".utf8)
        try original.write(to: pageURL)
        _ = await run("write_how_i_teach",
                      ["course": "ICS4U", "text": "Replaced.", "replacing": HowITeachPage.mark(of: original)])
        XCTAssertNotEqual(bytes(pageURL), original)

        let undo: AssistToolOutcome = await run("undo_last_change", [:])
        XCTAssertEqual(undo.summary, AssistWording.undid("replaced the How I Teach page"))
        XCTAssertEqual(bytes(pageURL), original)
        XCTAssertEqual(siteWork.previewRebuilds, 0, "the page is never on the site, so no preview is rebuilt")
    }

    /// A page with a byte-order mark: Foundation's reading drops it, so a
    /// careless undo would either skip the page as "edited since" or put it
    /// back without the mark.
    func testUndoPutsBackAPageWithAByteOrderMarkExactly() async throws {
        try prepare()
        let original: Data = Data("\u{FEFF}---\ntitle: mine\n---\nMine.\n".utf8)
        try original.write(to: pageURL)
        _ = await run("write_how_i_teach",
                      ["course": "ICS4U", "text": "Replaced.", "replacing": HowITeachPage.mark(of: original)])
        XCTAssertEqual(bytes(pageURL), Data("\u{FEFF}---\ntitle: mine\n---\n\nReplaced.\n".utf8))
        let undo: AssistToolOutcome = await run("undo_last_change", [:])
        XCTAssertEqual(undo.summary, AssistWording.undid("replaced the How I Teach page"))
        XCTAssertEqual(bytes(pageURL), original)
    }

    func testUndoTakesAwayACreatedPage() async throws {
        try prepare()
        _ = await run("write_how_i_teach", ["course": "ICS4U", "text": "Fresh."])
        XCTAssertTrue(FileManager.default.fileExists(atPath: pageURL.path))
        _ = await run("undo_last_change", [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pageURL.path))
    }

    func testAWholeCourseChangeDoesNotNameASection() {
        let change: AssistChange = AssistChange(
            whatHappened: "wrote a new How I Teach page", courseCode: "ICS4U", sectionNumber: 1,
            rebuildsThePreview: false, files: [], appliesToTheWholeCourse: true
        )
        XCTAssertEqual(change.description, "wrote a new How I Teach page in ICS4U")
    }

    // MARK: - Never published

    func testPublishingOrHidingItByNameIsRefusedInPlainWords() async throws {
        for surface in [AssistToolRunner.Surface.local, AssistToolRunner.Surface.mcp] {
            try prepare(surface: surface)
            let original: Data = Data("Mine.\n".utf8)
            try original.write(to: pageURL)
            for tool in ["plan_publish_pages", "publish_pages", "plan_unpublish_pages", "unpublish_pages"] {
                let outcome: AssistToolOutcome = await run(
                    tool, ["course": "ICS4U", "section": 1, "pages": "how i teach"]
                )
                XCTAssertEqual(outcome.summary, AssistWording.howITeachIsNeverPublished(course: "ICS4U"), tool)
            }
            XCTAssertEqual(bytes(pageURL), original, "nothing was written into it")
        }
    }

    func testAnOrdinaryPageWithTheNameInAFolderPublishesLikeAnyOther() async throws {
        try prepare()
        let ordinary: URL = live.directoryURL.appendingPathComponent("Concepts/How I Teach.md")
        try "---\npublish: false\n---\nshared\n".write(to: ordinary, atomically: true, encoding: .utf8)
        try "Mine.\n".write(to: pageURL, atomically: true, encoding: .utf8)
        let outcome: AssistToolOutcome = await run(
            "plan_publish_pages", ["course": "ICS4U", "section": 1, "pages": "How I Teach"]
        )
        XCTAssertNotEqual(outcome.summary, AssistWording.howITeachIsNeverPublished(course: "ICS4U"))
    }

    func testListPagesLeavesItOut() async throws {
        try prepare()
        try "Mine.\n".write(to: pageURL, atomically: true, encoding: .utf8)
        try "Section.\n".write(to: live.directoryURL.appendingPathComponent("section1/HOW I TEACH.md"),
                               atomically: true, encoding: .utf8)
        let outcome: AssistToolOutcome = await run("list_pages", ["course": "ICS4U", "section": 1])
        XCTAssertFalse(outcome.detail.lowercased().contains("how i teach"), outcome.detail)
        XCTAssertTrue(outcome.detail.contains("index.md"), outcome.detail)
    }

    // MARK: - What a session is told

    func testListCoursesSaysWhetherThereIsAPageOnlyToAnOutsideSession() async throws {
        try prepare(surface: .mcp)
        let before: AssistToolOutcome = await run("list_courses", [:])
        XCTAssertTrue(before.detail.contains(AssistWording.howITeachListedAsNotWritten), before.detail)
        try "Mine.\n".write(to: pageURL, atomically: true, encoding: .utf8)
        let after: AssistToolOutcome = await run("list_courses", [:])
        XCTAssertTrue(after.detail.contains(AssistWording.howITeachListedAsWritten), after.detail)

        try prepare(surface: .local)
        let local: AssistToolOutcome = await run("list_courses", [:])
        XCTAssertFalse(local.detail.contains("How I Teach"),
                       "the local window reaches list_courses and shows the teacher the answer: \(local.detail)")
    }

    func testTheSessionBriefingNamesTheCoursesWithAPage() throws {
        // One live course, no page, no reference course: nothing to say.
        try prepare(surface: .mcp)
        XCTAssertNil(AssistMCPServer.instructions(for: runner))

        try "Mine.\n".write(to: pageURL, atomically: true, encoding: .utf8)
        let told: String = try XCTUnwrap(AssistMCPServer.instructions(for: runner))
        XCTAssertTrue(told.contains(AssistWording.howITeachBriefing(courses: ["ICS4U"])), told)
    }

    func testAReferenceCoursesPageIsNotInTheBriefing() throws {
        try prepare(withReference: true) { courses in
            try "Old.\n".write(to: courses.appendingPathComponent("ICS4U-2025/How I Teach.md"),
                               atomically: true, encoding: .utf8)
        }
        let told: String = try XCTUnwrap(AssistMCPServer.instructions(for: runner))
        XCTAssertFalse(told.contains("How I Teach"), told)
    }

    func testTheGreetingAsksForThePageOnBothDoors() {
        let greeting: String = ClaudeCodeLauncher.greeting(courseCode: "ICS4U", courseName: "Computer Science")
        XCTAssertTrue(greeting.contains(ClaudeCodeLauncher.howITeachGreetingSentence), greeting)
        let listing: String = "Start by listing its sections so we both know what's there. "
        XCTAssertTrue(greeting.contains(listing + ClaudeCodeLauncher.howITeachGreetingSentence), greeting)
    }

    // MARK: - The build's marker

    func testTheKeptOffMarkerIsReadAndKeptOutOfTheConsole() throws {
        let marker: [String: Any] = try XCTUnwrap(try HowITeachTests.contractRule()["keptOffMarker"] as? [String: Any])
        XCTAssertEqual(marker["prefix"] as? String, HowITeachKeptOffReport.markerPrefix)
        let example: String = try XCTUnwrap((marker["examples"] as? [String])?.first)
        let reports: [HowITeachKeptOffReport] = HowITeachKeptOffReport.reports(in: "building\n" + example + "\n")
        XCTAssertEqual(reports, [HowITeachKeptOffReport(course: "ICS4U", section: 1, pages: ["How I Teach"])])
        let line: String = try XCTUnwrap(try HowITeachTests.contractRule()["keptOffTrailLine"] as? String)
        XCTAssertEqual(
            reports.first?.trailSentence,
            line.replacingOccurrences(of: "{count}", with: "1")
                .replacingOccurrences(of: "page(s)", with: "page")
                .replacingOccurrences(of: "{names}", with: "How I Teach")
        )
        XCTAssertFalse(ScriptRunner.looksLikeQuestion(example))
    }

    /// Through the real runner, with real line endings: the line lands on the
    /// trail and never in the console a teacher reads.
    func testARunRecordsTheKeptOffPageAndHidesTheMarker() throws {
        try prepare()
        let scriptRunner: ScriptRunner = ScriptRunner()
        scriptRunner.receiveOutput("🔒 Kept your How I Teach page off the website.\r\n")
        scriptRunner.receiveOutput(
            "PLANTOIR_KEPT_OFF: {\"course\": \"ICS4U\", \"section\": 2, \"pages\": [\"section2/How I Teach\"]}\r\n"
        )
        let shown: String = scriptRunner.transcript.displayText
        XCTAssertFalse(shown.contains("PLANTOIR_KEPT_OFF"), shown)
        XCTAssertTrue(shown.contains("Kept your How I Teach page"), shown)
        XCTAssertTrue(trail().contains(
            "ICS4U/2 · the build kept 1 page named How I Teach off the website that the course's settings "
            + "had listed for it: section2/How I Teach"
        ), trail())
    }
}
