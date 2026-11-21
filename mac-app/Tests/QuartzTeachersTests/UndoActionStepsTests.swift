import XCTest
@testable import QuartzTeachers

/// U3 of #899: every daily page action writes through the door as ONE step,
/// recorded in shadow while the switch is off.
///
/// - Each action is run through its REAL code (the runner's tools, the
///   sheets' planners) on a fixture, and the one step it leaves on the list
///   is read back: its action key, who made it, its ops, and the bytes each
///   file it names held before and holds after. Those are
///   `contracts/undo-action-steps.json`, from which
///   `scripts/make_undo_traces.py` makes the `actionTraces` both apps
///   replay. With `PLANTOIR_WRITE_UNDO_ACTION_STEPS=1` (through xcodebuild:
///   `TEST_RUNNER_PLANTOIR_WRITE_UNDO_ACTION_STEPS=1`) the file is written;
///   otherwise it must be what the actions record now, or this is red.
/// - The action traces are replayed through the live door.
/// - Today's in-memory undo answers exactly as before (`AssistChangeHistory`).
/// - A step killed part way is put back whole by recovery (live), and in
///   shadow nothing of the journal's is left in the course.
@MainActor
final class UndoActionStepsTests: XCTestCase {

    // MARK: - Stored properties

    var listFolders: [URL] = []

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        JournaledStep.modeOverride = nil
        UndoKillPoints.hook = nil
        UndoKillPoints.beforeTheRename = nil
        UndoKillPoints.stagingWriteFailsAt = nil
        ActivityTrail.store = previousTrail
        for folder in listFolders {
            try? FileManager.default.removeItem(at: folder)
        }
        listFolders = []
    }

    // MARK: - A recorded step

    /// One action's step as the list holds it.
    struct Recorded {

        // MARK: - Stored properties

        let name: String

        let action: String

        let madeBy: String

        /// Each content file, in op order: path, bytes before (nil: absent)
        /// and after.
        let files: [(path: String, before: Data?, after: Data?)]

        let recomputes: [(path: String, maintainer: String, section: Int?)]

        /// Each file moved (U3b: a rollover's record fragments, `move`, and
        /// its site markers, `moveApart`), in op order: where from, where
        /// to, its bytes, and whether it stands apart from its step.
        let moves: [(from: String, to: String, content: Data, standsApart: Bool)]

        let opKinds: [String]

        let phase: UndoStepPhase

        /// Each `editJSON` op (U4a: a Save of Course Settings, Set School
        /// Year), in op order: its file, key path and values (nil: absent).
        var members: [(path: String, keyPath: [String], before: UndoJSON?, after: UndoJSON?)] = []

        /// Each folder made (U4a: Add folder's `createTree`), in op order:
        /// where, the folders inside it and every file's bytes.
        var trees: [(path: String, folders: [String], files: [String: Data])] = []
    }

    /// Points the list at a folder of its own, snapshots the working folder,
    /// runs the action, and reads back the ONE step it left.
    func record(_ name: String, root: URL, run: () async throws -> Void) async throws -> Recorded {
        let list: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-action-steps-\(UUID().uuidString)", isDirectory: true)
        listFolders.append(list)
        UndoJournalLocation.folderOverride = list
        defer {
            UndoJournalLocation.folderOverride = nil
        }
        let before: [String: Data] = UndoActionStepsTests.snapshot(of: root)
        try await run()
        let fold: UndoFold = try UndoJournal(folderURL: list).read()
        XCTAssertEqual(fold.records.count, 1, "\(name): \(fold.records.count) steps, not one")
        var newest: UndoStepRecord? = nil
        for (_, record) in fold.records {
            if newest == nil || record.step.seq > (newest?.step.seq ?? 0) {
                newest = record
            }
        }
        let record: UndoStepRecord = try XCTUnwrap(newest, "\(name): no step on the list")
        var paths: [String] = []
        var kinds: [String] = []
        var recomputes: [(path: String, maintainer: String, section: Int?)] = []
        var moves: [(from: String, to: String, content: Data, standsApart: Bool)] = []
        var members: [(path: String, keyPath: [String], before: UndoJSON?, after: UndoJSON?)] = []
        var trees: [(path: String, folders: [String], files: [String: Data])] = []
        for op in record.step.ops {
            kinds.append(op.kind)
            if op.knownKind == .createTree, let path = op.path {
                if case .tree(let listing, let contents) = UndoTreeReading.read(at: root.appendingPathComponent(path), keepingContents: true) {
                    trees.append((path: path, folders: listing.folders, files: contents))
                }
                continue
            }
            if op.knownKind == .editJSON, let path = op.path {
                members.append((path: path, keyPath: op.keyPath ?? [], before: op.valueBefore, after: op.valueAfter))
            }
            if op.knownKind == .move || op.knownKind == .moveApart {
                let from: String = op.from ?? ""
                moves.append((
                    from: from, to: op.to ?? "", content: before[from] ?? Data(),
                    standsApart: op.knownKind == .moveApart
                ))
                continue
            }
            if op.knownKind == .recompute {
                recomputes.append((path: op.path ?? "", maintainer: op.maintainer ?? "", section: op.section))
                continue
            }
            if let path = op.path, !paths.contains(path) {
                paths.append(path)
            }
        }
        var files: [(path: String, before: Data?, after: Data?)] = []
        for path in paths {
            files.append((
                path: path,
                before: before[path],
                after: UndoItem.read(at: root.appendingPathComponent(path)).data
            ))
        }
        var recorded: Recorded = Recorded(
            name: name, action: record.step.action?.key ?? "", madeBy: record.step.madeBy ?? "",
            files: files, recomputes: recomputes, moves: moves, opKinds: kinds, phase: record.phase
        )
        recorded.members = members
        recorded.trees = trees
        return recorded
    }

    /// Every file under the folder, by its path inside it.
    static func snapshot(of root: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        let rootPath: String = UndoFolderPlaces.canonicalPath(of: root) + "/"
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return result
        }
        while let url = walker.nextObject() as? URL {
            let path: String = UndoFolderPlaces.canonicalPath(of: url)
            guard path.hasPrefix(rootPath), let data = UndoItem.read(at: url).data else {
                continue
            }
            result[String(path.dropFirst(rootPath.count))] = data
        }
        return result
    }

    // MARK: - The fixtures

    /// The shared assistant fixture with a section worth acting on: Unit 1
    /// Day 1 published, Day 2 and Day 3 hidden, Unit 2 Day 1 hidden and
    /// linking to Day 2, class dates on file, and a curriculum expectation
    /// with a Concepts page to point at it.
    func section(surface: AssistToolRunner.Surface) throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(hasDeployedBefore: true, surface: surface)
        try AssistFixture.keepScheduledPublishingInside(made.root, for: self)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let pages: [(title: String, publish: String, date: String, body: String)] = [
            ("Unit 1, Day 1", "true", "2026-09-08", "One."),
            ("Unit 1, Day 2", "false", "2026-09-10", "Two."),
            ("Unit 1, Day 3", "false", "2026-09-14", "Three."),
            ("Unit 2, Day 1", "false", "2026-09-16", "See [[Unit 1, Day 2]]."),
        ]
        for page in pages {
            try AssistFixture.write(page: page.title, publish: page.publish, date: page.date, body: page.body, in: made.course)
        }
        try DuplicateAsNextClassTests.rememberTimetable(
            ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16", "2026-09-18", "2026-09-21", "2026-09-23"],
            in: made.course
        )
        let curriculumURL: URL = made.course.directoryURL.appendingPathComponent("Curriculum")
        try FileManager.default.createDirectory(at: curriculumURL, withIntermediateDirectories: true)
        try "---\ntranscludeTitleSize: h4\ntags:\n  - A1\n---\nuse a variety of problem-solving strategies to solve programming problems ^text\n"
            .write(to: curriculumURL.appendingPathComponent("A1.1.md"), atomically: true, encoding: .utf8)
        try "---\ntitle: Loops\npublishForSection1: true\ncreatedSection1: 2026-09-08T07:00:00.000-0400\n---\n\nA loop repeats work.\n"
            .write(to: made.course.directoryURL.appendingPathComponent("Concepts/Loops.md"), atomically: true, encoding: .utf8)
        try "---\ntitle: Section 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\n# Most Recent Class\n\n![[Unit 1, Day 1]]\n"
            .write(to: SectionIndexPointer.indexURL(forSection: 1, in: made.course), atomically: true, encoding: .utf8)
        return made
    }

    /// A section the start of the year has work in: last year's classes
    /// published, the course's year-round page published for the section.
    func startOfYearSection() throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try section(surface: .local)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "true", date: "2026-09-10", body: "Two.", in: made.course)
        return made
    }

    /// The contract's ordinary morning (`todaysClassOnTheFrontPage`): today's
    /// class published, the front page showing yesterday's.
    func morning() throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: .menu)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let classes: [(title: String, created: String, publish: String)] = [
            ("Unit 2, Day 3", "2026-09-28T07:00:00.000-0400", "true"),
            ("Unit 2, Day 4", "2026-09-29T07:00:00.000-0400", "true"),
            ("Unit 2, Day 5", "2026-09-30T07:00:00.000-0400", "true"),
            ("Unit 2, Day 6", "2026-10-01T07:00:00.000-0400", "false"),
        ]
        for page in classes {
            try "---\ntitle: \(page.title)\npublish: \(page.publish)\ncreated: \(page.created)\n---\n"
                .write(to: AssistFixture.pageURL(of: page.title, in: made.course), atomically: true, encoding: .utf8)
        }
        try "---\ntitle: Section 1\npublish: true\ncreated: 2026-09-29T07:00:00.000-0400\nenableToc: false\nexcludeBacklinks: true\n---\n# Most Recent Class\n\n![[Unit 2, Day 4]]\n\n![[Help Sessions]]\n![[Key Links]]\n"
            .write(to: SectionIndexPointer.indexURL(forSection: 1, in: made.course), atomically: true, encoding: .utf8)
        return made
    }

    // MARK: - Every action, through its real code

    /// The steps, in a fixed order: the order of `undo-action-steps.json`.
    func recordEveryAction() async throws -> [Recorded] {
        var recorded: [Recorded] = []

        let publish: AssistFixture.Made = try section(surface: .menu)
        recorded.append(try await record("publishPages", root: publish.root) {
            _ = await AssistFixture.run("publish_pages", with: ["pages": ["Unit 1, Day 2"]], on: publish.runner)
        })

        let hide: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("hidePages", root: hide.root) {
            _ = await AssistFixture.run("unpublish_pages", with: ["pages": ["Unit 1, Day 1"]], on: hide.runner)
        })

        let unit: AssistFixture.Made = try section(surface: .menu)
        recorded.append(try await record("publishPagesAWholeUnit", root: unit.root) {
            _ = await AssistFixture.run("publish_pages", with: ["pages": ["Unit 1"]], on: unit.runner)
        })

        let onADate: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("publishClassForADate", root: onADate.root) {
            _ = await AssistFixture.run("publish_class_on", with: ["date": "2026-09-10"], on: onADate.runner)
        })

        let next: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("addNextClass", root: next.root) {
            _ = await AssistFixture.run("add_next_class", with: [:], on: next.runner)
        })

        let newUnit: AssistFixture.Made = try section(surface: .menu)
        recorded.append(try await record("addNextClassInANewUnit", root: newUnit.root) {
            _ = await AssistFixture.run("add_next_class", with: ["unit": "next"], on: newUnit.runner)
        })

        let classes: AssistFixture.Made = try section(surface: .mcp)
        recorded.append(try await record("addClasses", root: classes.root) {
            _ = await AssistFixture.run("add_classes", with: ["unit": 2, "howMany": 2], on: classes.runner)
        })

        let room: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("makeRoomForClasses", root: room.root) {
            _ = await AssistFixture.run("make_room_for_classes", with: ["unit": 1, "atDay": 2], on: room.runner)
        })

        let duplicate: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("duplicateClass", root: duplicate.root) {
            _ = await AssistFixture.run("add_next_class", with: ["duplicate": "Unit 1, Day 1"], on: duplicate.runner)
        })

        let fromTheMenu: AssistFixture.Made = try section(surface: .menu)
        recorded.append(try await record("duplicateAsTheNextClass", root: fromTheMenu.root) {
            _ = await fromTheMenu.runner.run(call: SectionVerbs.duplicateAsNextClass(
                course: "ICS3U", section: 1, sourcePath: "section1/All Classes/Unit 1, Day 1.md", planning: false
            ))
        })

        let reDate: AssistFixture.Made = try AssistFixture.makeSectionNeedingReDating(for: self)
        recorded.append(try await record("reDateClasses", root: reDate.root) {
            _ = await AssistFixture.run("re_date_classes", with: [:], on: reDate.runner)
        })

        let timetable: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("rememberTimetable", root: timetable.root) {
            _ = await AssistFixture.run(
                "remember_timetable", with: ["dates": "2026-09-08; 2026-09-10; 2026-09-14"], on: timetable.runner
            )
        })

        let mentions: AssistFixture.Made = try section(surface: .mcp)
        recorded.append(try await record("addCurriculumMentions", root: mentions.root) {
            _ = await AssistFixture.run(
                "add_curriculum_mentions", with: ["page": "Loops", "codes": "A1.1"], on: mentions.runner
            )
        })

        let howITeach: AssistFixture.Made = try section(surface: .mcp)
        recorded.append(try await record("writeHowITeach", root: howITeach.root) {
            _ = await AssistFixture.run(
                "write_how_i_teach", with: ["text": "I start every class with a question."], on: howITeach.runner
            )
        })

        let started: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("startHowITeachPage", root: started.root) {
            _ = try HowITeachPage.startOrFind(for: started.course)
        })

        let startOfYear: AssistFixture.Made = try startOfYearSection()
        recorded.append(try await record("getReadyForTheStartOfTheYear", root: startOfYear.root) {
            let planned: AssistToolOutcome = await AssistFixture.run(
                "plan_prepare_for_start_of_year", with: [:], on: startOfYear.runner
            )
            let code: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: planned.detail), planned.detail)
            _ = await AssistFixture.run("prepare_for_start_of_year", with: ["planCode": code], on: startOfYear.runner)
        })

        let today: AssistFixture.Made = try morning()
        recorded.append(try await record("showTodaysClassOnTheFrontPage", root: today.root) {
            let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-30"))
            let offer: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
                TodaysClassOnTheFrontPage.offer(forSection: 1, in: today.course, today: day)
            )
            XCTAssertEqual(TodaysClassOnTheFrontPage.show(offer, in: today.course), .shown(from: "Unit 2, Day 4", to: "Unit 2, Day 5"))
        })

        let notToday: AssistFixture.Made = try morning()
        recorded.append(try await record("notTodayOnTheFrontPage", root: notToday.root) {
            try TodaysClassOnTheFrontPage.NotToday(day: "2026-09-30", classTitle: "Unit 2, Day 5")
                .write(courseDirectory: notToday.course.directoryURL, section: 1)
        })

        let checklist: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("answerTheLinksChecklist", root: checklist.root) {
            let moment: Date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-08T11:00:00Z"))
            try LinksChecklistAnswered(offered: ["section1/All Classes/Unit 1, Day 2.md"], leftUnticked: [])
                .write(courseDirectory: checklist.course.directoryURL, section: 1, at: moment)
        })

        let kept: AssistFixture.Made = try section(surface: .local)
        recorded.append(try await record("keepClassesDatedLater", root: kept.root) {
            try ClassesDatedLater.KeptRecord(
                answeredAt: "2026-09-08T11:00:00Z",
                kept: [ClassesDatedLater.Kept(place: "section1/All Classes/Unit 1, Day 3.md", date: "2026-09-14")]
            ).write(courseDirectory: kept.course.directoryURL, section: 1)
        })

        // U3b: the rollover, ONE step, from the menu onto a new website (the
        // re-date, the record's fragment and answered checklist, the marker)
        // and from the window keeping its website (the re-date and the record).
        let newWebsite: AssistFixture.Made = try rolloverSection(surface: .menu)
        recorded.append(try await record("rollOverOntoANewWebsite", root: newWebsite.root) {
            _ = await newWebsite.runner.run(
                call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
            )
        })

        let sameWebsite: AssistFixture.Made = try rolloverSection(surface: .local)
        recorded.append(try await record("rollOverKeepingTheWebsite", root: sameWebsite.root) {
            _ = await AssistFixture.run("re_date_classes", with: ["rollover": "yes", "website": "same"], on: sameWebsite.runner)
        })

        // U4a: Course Settings' Save, Add folder and Set School Year.
        recorded.append(contentsOf: try await recordTheCourseSettingsActions())

        return recorded
    }

    /// A section to roll over: dates to move, a Netlify marker, last year's
    /// published-pages record and links checklist answered, the copy of the
    /// course saved first (`UndoRolloverStepTests`' world).
    func rolloverSection(surface: AssistToolRunner.Surface) throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: surface, for: self)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        _ = RollOverFromTheMenuTests.countCopies(of: made)
        try UndoRolloverStepTests.lastYear.write(
            to: made.root.appendingPathComponent(UndoRolloverStepTests.markerPath), atomically: true, encoding: .utf8
        )
        try RollOverFromTheMenuTests.writePublishedRecord(in: made.course)
        try "{\"offered\": [], \"leftUnticked\": []}\n".write(
            to: LinksChecklistAnswered.fileURL(courseDirectory: made.course.directoryURL, section: 1),
            atomically: true, encoding: .utf8
        )
        return made
    }

    // MARK: - Tests

    /// Every daily action leaves ONE step, recorded and closed, named for
    /// the action and its maker; and what the steps hold is the contract's
    /// `undo-action-steps.json` (written from here, never by hand).
    func testEveryDailyActionIsOneStepThroughTheDoor() async throws {
        let recorded: [Recorded] = try await recordEveryAction()
        XCTAssertEqual(recorded.count, 25)
        let expectedMakers: [String: String] = [
            "publishPages": "menu", "hidePages": "builtInAssistant:", "publishPagesAWholeUnit": "menu",
            "publishClassForADate": "builtInAssistant:", "addNextClass": "builtInAssistant:",
            "addNextClassInANewUnit": "menu", "addClasses": "outsideAssistant:",
            "makeRoomForClasses": "builtInAssistant:", "duplicateClass": "builtInAssistant:",
            "duplicateAsTheNextClass": "menu", "reDateClasses": "builtInAssistant:",
            "rememberTimetable": "builtInAssistant:", "addCurriculumMentions": "outsideAssistant:",
            "writeHowITeach": "outsideAssistant:", "startHowITeachPage": "sheet",
            "getReadyForTheStartOfTheYear": "builtInAssistant:", "showTodaysClassOnTheFrontPage": "sheet",
            "notTodayOnTheFrontPage": "sheet", "answerTheLinksChecklist": "sheet", "keepClassesDatedLater": "sheet",
            "rollOverOntoANewWebsite": "menu", "rollOverKeepingTheWebsite": "builtInAssistant:",
            "saveCourseSettings": "sheet", "addFolder": "sheet", "setSchoolYear": "sheet",
        ]
        let expectedKeys: [String: String] = [
            "publishPagesAWholeUnit": "publishPages",
            "rollOverOntoANewWebsite": "rollOver", "rollOverKeepingTheWebsite": "rollOver",
        ]
        for step in recorded {
            XCTAssertEqual(step.phase, .done, "\(step.name): the step was not closed applied")
            XCTAssertEqual(step.action, expectedKeys[step.name] ?? step.name, "\(step.name): action key")
            XCTAssertTrue(step.madeBy.hasPrefix(expectedMakers[step.name] ?? "?"), "\(step.name): made by \(step.madeBy)")
            XCTAssertFalse(step.files.isEmpty && step.trees.isEmpty, "\(step.name): no file")
            for file in step.files {
                XCTAssertNotEqual(file.before, file.after, "\(step.name): \(file.path) did not change")
            }
        }

        let written: Data = try UndoActionStepsTests.document(recorded)
        let url: URL = UndoContractReplay.repositoryURL()
            .appendingPathComponent("contracts").appendingPathComponent("undo-action-steps.json")
        if ProcessInfo.processInfo.environment["PLANTOIR_WRITE_UNDO_ACTION_STEPS"] == "1" {
            try written.write(to: url)
            return
        }
        let committed: Data = try Data(contentsOf: url)
        XCTAssertEqual(
            UndoActionStepsTests.masked(committed), UndoActionStepsTests.masked(written),
            "contracts/undo-action-steps.json is not what the actions record now: run this test with TEST_RUNNER_PLANTOIR_WRITE_UNDO_ACTION_STEPS=1, then python3 scripts/make_undo_traces.py"
        )
    }

    /// Every action trace, replayed through the live door.
    func testEveryActionTraceReplaysAsTheContractSays() async throws {
        let parent: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-action-traces-\(UUID().uuidString)", isDirectory: true)
        listFolders.append(parent)
        let result: (traces: Int, calls: Int, failures: [String]) = try await UndoActionStepsTests.replayActionTraces(under: parent)
        XCTAssertGreaterThanOrEqual(result.traces, 120)
        XCTAssertGreaterThan(result.calls, 600)
        XCTAssertEqual(result.failures, [])
    }

    /// Today's in-memory undo (`AssistChangeHistory`) answers exactly as it
    /// did before U3: each action through the runner gains the entries it
    /// always did (none for Make Room, Add Classes and the class dates), and
    /// Undo Last Change puts every page it wrote back, byte for byte. The
    /// first review of U3a (LOW 11) added re-date, Publish Class for a Date,
    /// How I Teach, the menu's Duplicate as Next Class and Undo Getting Ready
    /// (`StartOfYearUndoRegistry`, below).
    func testTodaysUndoAnswersExactlyAsBefore() async throws {
        let cases: [(tool: String, arguments: [String: Any], surface: AssistToolRunner.Surface, entries: Int)] = [
            ("publish_pages", ["pages": ["Unit 1, Day 2"]], .menu, 1),
            ("unpublish_pages", ["pages": ["Unit 1, Day 1"]], .local, 1),
            ("publish_pages", ["pages": ["Unit 1"]], .menu, 1),
            ("publish_class_on", ["date": "2026-09-10"], .local, 1),
            ("add_next_class", [:], .local, 1),
            ("add_next_class", ["duplicate": "Unit 1, Day 1"], .local, 0),
            ("make_room_for_classes", ["unit": 1, "atDay": 2], .local, 0),
            ("add_classes", ["unit": 2, "howMany": 2], .mcp, 1),
            ("remember_timetable", ["dates": "2026-09-08; 2026-09-10"], .local, 0),
            ("add_curriculum_mentions", ["page": "Loops", "codes": "A1.1"], .mcp, 1),
            ("write_how_i_teach", ["text": "I start every class with a question."], .mcp, 1),
        ]
        for testCase in cases {
            let made: AssistFixture.Made = try section(surface: testCase.surface)
            try await expectTodaysUndo(
                on: made, "\(testCase.tool) \(testCase.arguments)", entries: testCase.entries
            ) {
                return await AssistFixture.run(testCase.tool, with: testCase.arguments, on: made.runner)
            }
        }

        let reDate: AssistFixture.Made = try AssistFixture.makeSectionNeedingReDating(for: self)
        try await expectTodaysUndo(on: reDate, "re_date_classes", entries: 1) {
            return await AssistFixture.run("re_date_classes", with: [:], on: reDate.runner)
        }

        let fromTheMenu: AssistFixture.Made = try section(surface: .menu)
        try await expectTodaysUndo(on: fromTheMenu, "the menu's Duplicate as Next Class", entries: 1) {
            return await fromTheMenu.runner.run(call: SectionVerbs.duplicateAsNextClass(
                course: "ICS3U", section: 1, sourcePath: "section1/All Classes/Unit 1, Day 1.md", planning: false
            ))
        }

        // Undo Getting Ready: the sheet's own registry, not the runner's.
        StartOfYearUndoRegistry.shared.forgetAll()
        defer {
            StartOfYearUndoRegistry.shared.forgetAll()
        }
        let startOfYear: AssistFixture.Made = try startOfYearSection()
        let pagesBefore: [String: Data] = UndoActionStepsTests.pages(of: startOfYear.course)
        let go: StartOfYearSheetModel = StartOfYearSheetModel(
            course: startOfYear.course, sectionNumber: 1, workspaceURL: startOfYear.root, mode: .getReady
        )
        go.load()
        await go.goAhead()
        guard case .done = go.stage else {
            return XCTFail("getting ready was not done: \(go.stage)")
        }
        XCTAssertNotEqual(UndoActionStepsTests.pages(of: startOfYear.course), pagesBefore, "getting ready changed nothing")
        let back: StartOfYearSheetModel = StartOfYearSheetModel(
            course: startOfYear.course, sectionNumber: 1, workspaceURL: startOfYear.root, mode: .undo
        )
        back.load()
        guard case .undoReady(_, _, let skipped) = back.stage else {
            return XCTFail("no Undo Getting Ready offered: \(back.stage)")
        }
        XCTAssertEqual(skipped.count, 0)
        await back.undo()
        XCTAssertEqual(
            UndoActionStepsTests.pages(of: startOfYear.course), pagesBefore,
            "Undo Getting Ready did not put every page back"
        )
        XCTAssertNil(StartOfYearUndoRegistry.shared.entry(
            folderPath: startOfYear.root.path, courseCode: "ICS3U", sectionNumber: 1
        ))
    }

    /// Runs an action, counts the undo entries it gains, and, when it gains
    /// one, runs Undo Last Change, which must put every page back byte for
    /// byte.
    func expectTodaysUndo(
        on made: AssistFixture.Made, _ name: String, entries: Int,
        _ action: () async throws -> AssistToolOutcome
    ) async throws {
        let pagesBefore: [String: Data] = UndoActionStepsTests.pages(of: made.course)
        let depth: Int = made.runner.changeCount
        let said: AssistToolOutcome = try await action()
        XCTAssertEqual(made.runner.changeCount - depth, entries, "\(name): undo entries — \(said.summary)")
        if entries == 0 {
            return
        }
        XCTAssertNotEqual(UndoActionStepsTests.pages(of: made.course), pagesBefore, "\(name) changed nothing: \(said.summary)")
        let undone: AssistToolOutcome = await AssistFixture.run("undo_last_change", with: [:], on: made.runner)
        XCTAssertEqual(made.runner.changeCount, depth, "\(name): \(undone.summary)")
        XCTAssertEqual(UndoActionStepsTests.pages(of: made.course), pagesBefore, "\(name): the undo did not put every page back")
    }

    /// THE worst case of documentation 09's "if the app dies": Make Room
    /// renames, rewrites a link, re-dates and makes a page, so its step
    /// holds the most files of any daily action. Killed between its second
    /// and third swap with the door live, it leaves two files new and the
    /// rest old; recovery, once the process is gone, puts every file back
    /// where it was before the step and closes it, with nothing of the
    /// journal's left beside a page. MUST FAIL with recovery taken out (the
    /// files stay half made).
    func testAMakeRoomKilledPartWayIsPutBackWholeByRecovery() async throws {
        let made: AssistFixture.Made = try section(surface: .local)
        let list: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-killed-\(UUID().uuidString)", isDirectory: true)
        listFolders.append(list)
        UndoJournalLocation.folderOverride = list
        let before: [String: Data] = UndoActionStepsTests.pages(of: made.course)
        JournaledStep.modeOverride = .live
        UndoKillPoints.hook = { point in point == .beforeSwap(2) }
        let said: AssistToolOutcome = await AssistFixture.run(
            "make_room_for_classes", with: ["unit": 1, "atDay": 2], on: made.runner
        )
        UndoKillPoints.hook = nil
        JournaledStep.modeOverride = nil
        XCTAssertNotEqual(UndoActionStepsTests.pages(of: made.course), before, "the kill came before any swap: \(said.summary)")
        let fold: UndoFold = try UndoJournal(folderURL: list).read()
        let step: UndoStepRecord = try XCTUnwrap(fold.records[1])
        XCTAssertGreaterThanOrEqual(step.step.ops.count, 4, "Make Room's step holds too few files to be the worst case")

        let later: UndoJournal = UndoJournal(folderURL: list, processIsAlive: { _ in false })
        await UndoRecovery.recoverAndRederive(later, resolveRoot: { _ in made.root })

        XCTAssertEqual(UndoActionStepsTests.pages(of: made.course), before, "recovery did not put the step back whole")
        XCTAssertFalse(UndoContractReplay.staysBeside(made.root), "a staged file was left in the course")
        XCTAssertEqual(try later.read().records[1]?.phase, .rolledBack)
    }

    /// A kill in SHADOW (the switch off, today), Add Classes between its two
    /// new pages: recovery never writes the teacher's files, so they stay as
    /// the process left them, the step is recorded interrupted and the list
    /// cleared, and the journal's own staged files are removed (U3's change
    /// to `rule.recovery`). MUST FAIL on the recovery before U3, which left
    /// the dot-files in the course until a live recovery.
    func testAShadowStepKilledPartWayLeavesNothingOfTheJournalsInTheCourse() async throws {
        let made: AssistFixture.Made = try section(surface: .local)
        let list: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-killed-shadow-\(UUID().uuidString)", isDirectory: true)
        listFolders.append(list)
        UndoJournalLocation.folderOverride = list
        UndoKillPoints.hook = { point in point == .beforeSwap(1) }
        _ = await AssistFixture.run("add_classes", with: ["unit": 2, "howMany": 2], on: made.runner)
        UndoKillPoints.hook = nil
        var left: [String: Data] = [:]
        var stagedBeforeRecovery: Int = 0
        for (path, data) in UndoActionStepsTests.pages(of: made.course) {
            if path.contains(UndoSwap.stagedMarker) {
                stagedBeforeRecovery += 1
                continue
            }
            left[path] = data
        }
        XCTAssertGreaterThan(stagedBeforeRecovery, 0, "the kill left nothing staged, so this proves nothing")

        let later: UndoJournal = UndoJournal(folderURL: list, processIsAlive: { _ in false })
        try later.withLock(waitingAtMost: 2, inShadow: true) { writer in
            UndoRecovery.run(writer, mode: .shadow, trySwapsNow: true, resolveRoot: { _ in made.root })
        }

        XCTAssertEqual(UndoActionStepsTests.pages(of: made.course), left, "shadow recovery wrote into the course")
        XCTAssertFalse(UndoContractReplay.staysBeside(made.root), "a staged file was left in the course")
        XCTAssertEqual(try later.read().records[1]?.phase, .interrupted)
    }

    /// A list that cannot be written changes nothing about a daily action
    /// in shadow: the same pages and the same answer as with one that can.
    func testAListThatCannotBeWrittenChangesNothingAboutAnAction() async throws {
        let well: AssistFixture.Made = try section(surface: .local)
        let wellList: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-well-\(UUID().uuidString)", isDirectory: true)
        listFolders.append(wellList)
        UndoJournalLocation.folderOverride = wellList
        let saidWell: AssistToolOutcome = await AssistFixture.run("add_classes", with: ["unit": 2, "howMany": 2], on: well.runner)

        let broken: AssistFixture.Made = try section(surface: .local)
        let brokenList: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-broken-\(UUID().uuidString)")
        listFolders.append(brokenList)
        try Data("a file, not a folder".utf8).write(to: brokenList)
        UndoJournalLocation.folderOverride = brokenList.appendingPathComponent("undo", isDirectory: true)
        let saidBroken: AssistToolOutcome = await AssistFixture.run("add_classes", with: ["unit": 2, "howMany": 2], on: broken.runner)

        XCTAssertEqual(saidBroken.summary, saidWell.summary)
        XCTAssertEqual(saidBroken.detail, saidWell.detail)
        let wellPages: [String: Data] = UndoActionStepsTests.pages(of: well.course)
        let brokenPages: [String: Data] = UndoActionStepsTests.pages(of: broken.course)
        var differing: [String] = []
        for (path, data) in wellPages where brokenPages[path] != data {
            differing.append(path + ": " + (String(data: brokenPages[path] ?? Data(), encoding: .utf8) ?? "?")
                             + " | " + (String(data: data, encoding: .utf8) ?? "?"))
        }
        for (path, _) in brokenPages where wellPages[path] == nil {
            differing.append(path + ": only with the broken list")
        }
        differing.sort()
        XCTAssertEqual(differing, [])
    }

    // MARK: - Tests: reading through the plan

    /// The day a number of days from today, by the Mac's own clock (the
    /// links checklist reads it).
    static func day(fromToday days: Int) throws -> CalendarDay {
        let moment: Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: days, to: Date()))
        return CalendarDay.today(moment)
    }

    /// The section with a Concepts page both Unit 1, Day 2 and Day 3 use.
    func sectionSharingAPage(surface: AssistToolRunner.Surface) throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try section(surface: surface)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "false", date: "2026-09-10", body: "Two, see [[Notes]].", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 3", publish: "false", date: "2026-09-14", body: "Three, see [[Notes]].", in: made.course)
        try "---\ntitle: Notes\npublishForSection1: false\ncreatedSection1: 2026-02-01T07:00:00.000-0400\n---\n\nNotes.\n"
            .write(to: made.course.directoryURL.appendingPathComponent("Concepts/Notes.md"), atomically: true, encoding: .utf8)
        return made
    }

    /// A whole unit is ONE step planned class by class: each class's plan
    /// reads the pages as the classes before it left them in the step, so
    /// the unit writes exactly what publishing its classes one by one wrote
    /// before U3 (a page two classes use keeps the first one's date). MUST
    /// FAIL with `JournaledStep.textAsPlanned` reading the disk (the first
    /// review of U3a, LOW 4): Day 3's plan then saw Notes still hidden and
    /// published it again with its own date.
    func testAWholeUnitReadsWhatItsEarlierClassesPlanned() async throws {
        let unit: AssistFixture.Made = try sectionSharingAPage(surface: .menu)
        _ = await AssistFixture.run("publish_pages", with: ["pages": ["Unit 1"]], on: unit.runner)

        let oneByOne: AssistFixture.Made = try sectionSharingAPage(surface: .menu)
        _ = await AssistFixture.run("publish_pages", with: ["pages": ["Unit 1, Day 2"]], on: oneByOne.runner)
        _ = await AssistFixture.run("publish_pages", with: ["pages": ["Unit 1, Day 3"]], on: oneByOne.runner)

        let notes: String = try String(
            contentsOf: unit.course.directoryURL.appendingPathComponent("Concepts/Notes.md"), encoding: .utf8
        )
        XCTAssertTrue(notes.contains("publishForSection1: true"), notes)
        XCTAssertEqual(UndoActionStepsTests.pages(of: unit.course), UndoActionStepsTests.pages(of: oneByOne.course))
    }

    /// A section whose runner reads 2026-09-08 as today: Day 2 (09-10) is
    /// the next class, so a visible Day 3 (09-14) is one the Deploy
    /// question asks about.
    func sectionOnTheEighth() throws -> AssistFixture.Made {
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-08"))
        let made: AssistFixture.Made = try AssistFixture.makeRunner(
            hasDeployedBefore: true, clock: AssistFixture.TestClock(today), surface: .local
        )
        try AssistFixture.keepScheduledPublishingInside(made.root, for: self)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08", body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "false", date: "2026-09-10", body: "Two.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 3", publish: "false", date: "2026-09-14", body: "Three, see [[Notes]].", in: made.course)
        try "---\ntitle: Notes\npublishForSection1: false\ncreatedSection1: 2026-02-01T07:00:00.000-0400\n---\n\nNotes.\n"
            .write(to: made.course.directoryURL.appendingPathComponent("Concepts/Notes.md"), atomically: true, encoding: .utf8)
        return made
    }

    /// Publish Class for a Date keeps the class it publishes, when the
    /// Deploy question would ask about it, in the publish's own step: the
    /// question is asked of the pages AS THE STEP LEAVES THEM, where the
    /// class is visible. MUST FAIL with `JournaledStep.textAsPlanned`
    /// reading the disk (LOW 4), where the class is still hidden and
    /// nothing is kept.
    func testPublishClassForADateKeepsTheClassItPublishesInTheSameStep() async throws {
        let made: AssistFixture.Made = try sectionOnTheEighth()
        let list: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-on-a-date-\(UUID().uuidString)", isDirectory: true)
        listFolders.append(list)
        UndoJournalLocation.folderOverride = list
        let said: AssistToolOutcome = await AssistFixture.run("publish_class_on", with: ["date": "2026-09-14"], on: made.runner)
        let kept: ClassesDatedLater.KeptRecord? = ClassesDatedLater.KeptRecord.read(
            courseDirectory: made.course.directoryURL, section: 1
        )
        XCTAssertEqual(
            kept?.kept, [ClassesDatedLater.Kept(place: "section1/All Classes/Unit 1, Day 3", date: "2026-09-14")],
            said.summary
        )
        let fold: UndoFold = try UndoJournal(folderURL: list).read()
        XCTAssertEqual(fold.records.count, 1, "not one step")
        var paths: [String] = []
        for op in try XCTUnwrap(fold.records[1]).step.ops {
            if let path = op.path {
                paths.append(path)
            }
        }
        XCTAssertTrue(paths.contains("courses/ICS3U/.publish_state/section1.later-classes-kept.json"), "\(paths)")
        XCTAssertTrue(paths.contains("courses/ICS3U/section1/All Classes/Unit 1, Day 3.md"), "\(paths)")
    }

    /// The kept record of Publish Class for a Date is written only inside a
    /// step that goes in (LOW 10). Before U3 it was written AFTER the
    /// publish, whatever came of it, so a publish that could not be written
    /// still recorded the class as kept when it was already visible: the
    /// Deploy question was then silenced for a class the teacher's request
    /// never reached. MUST FAIL on the order before U3.
    func testAPublishClassForADateThatIsRefusedKeepsNothing() async throws {
        let made: AssistFixture.Made = try sectionOnTheEighth()
        try AssistFixture.write(page: "Unit 1, Day 3", publish: "true", date: "2026-09-14", body: "Three, see [[Notes]].", in: made.course)
        let concepts: URL = made.course.directoryURL.appendingPathComponent("Concepts")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: concepts.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: concepts.path)
        }
        let depth: Int = made.runner.changeCount
        let said: AssistToolOutcome = await AssistFixture.run("publish_class_on", with: ["date": "2026-09-14"], on: made.runner)
        XCTAssertTrue(said.detail.hasPrefix("Nothing was changed: "), said.detail)
        XCTAssertNil(
            ClassesDatedLater.KeptRecord.read(courseDirectory: made.course.directoryURL, section: 1),
            "a refused publish kept the class"
        )
        XCTAssertEqual(made.runner.changeCount, depth, "a refused publish gained an undo entry")
    }

    /// The links checklist keeps the later classes it publishes, read as
    /// its step leaves the pages. MUST FAIL with `JournaledStep.textAsPlanned`
    /// reading the disk (LOW 4).
    func testTheLinksChecklistKeepsTheLaterClassItPublishes() async throws {
        let pressed = try checklistToPress()
        let made: AssistFixture.Made = pressed.made
        let offer: LinksChecklistOffer = pressed.offer
        let later: CalendarDay = try UndoActionStepsTests.day(fromToday: 10)
        let result: LinksChecklistPublisher.Result = LinksChecklistPublisher.publish(
            offer: offer, ticked: ["section1/All Classes/Unit 2, Day 5"], course: made.course, sectionNumber: 1,
            workspaceURL: made.root, shownComingWith: []
        )
        guard case .published = result else {
            return XCTFail("Publish did not publish: \(result)")
        }
        let kept: ClassesDatedLater.KeptRecord? = ClassesDatedLater.KeptRecord.read(
            courseDirectory: made.course.directoryURL, section: 1
        )
        XCTAssertEqual(kept?.kept, [ClassesDatedLater.Kept(place: "section1/All Classes/Unit 2, Day 5", date: later.text)])
    }

    /// The links checklist with one class row ticked, the class dated
    /// later and using a hidden page: the case both refusals below press.
    func checklistToPress() throws -> (made: AssistFixture.Made, offer: LinksChecklistOffer) {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: .local)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let next: CalendarDay = try UndoActionStepsTests.day(fromToday: 1)
        let later: CalendarDay = try UndoActionStepsTests.day(fromToday: 10)
        let testCase: [String: Any] = [
            "pages": [
                ["title": "Unit 1, Day 1", "kind": "class", "visible": true, "date": next.text, "links": ["How Marks Work"]],
                ["title": "Unit 2, Day 5", "kind": "class", "visible": false, "date": later.text, "links": ["Class Notes"]],
                ["title": "How Marks Work", "kind": "page", "visible": true, "date": next.text],
                ["title": "Class Notes", "kind": "page", "visible": false, "date": "2026-02-01"],
            ],
        ]
        _ = try LinksChecklistTests.layOut(testCase, made: made)
        let offer: LinksChecklistOffer = try LinksChecklistTests.offer(from: [
            [
                "place": "section1/All Classes/Unit 2, Day 5", "group": "class", "ticked": false, "step": NSNull(),
                "claimedBy": NSNull(), "date": NSNull(), "why": "classNeverDated", "firstUsedIn": NSNull(),
            ],
        ])
        return (made: made, offer: offer)
    }

    /// A press the door refuses says what is true of that refusal (the
    /// first review of U3a, LOW 7), never "could not be read" for a page
    /// that was read: a page changed by another program while the step
    /// went in is `linksChecklist.wording.pageChangedSince`, naming it; a
    /// full disk is "Nothing was changed: …" with the file that could not
    /// be saved. Nothing is written either way. MUST FAIL on U3a's first
    /// round, which said the unreadable-page sentence for both.
    func testARefusedLinksChecklistPressSaysWhatIsTrue() throws {
        let raced = try checklistToPress()
        let classURL: URL = AssistFixture.pageURL(of: "Unit 2, Day 5", in: raced.made.course)
        UndoKillPoints.beforeTheRename = { _, url in
            if url.lastPathComponent != classURL.lastPathComponent {
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else {
                return
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("Edited in Obsidian.\n".utf8))
            try? handle.close()
        }
        let racedResult: LinksChecklistPublisher.Result = LinksChecklistPublisher.publish(
            offer: raced.offer, ticked: ["section1/All Classes/Unit 2, Day 5"], course: raced.made.course,
            sectionNumber: 1, workspaceURL: raced.made.root, shownComingWith: []
        )
        UndoKillPoints.beforeTheRename = nil
        guard case .refused(let racedSentence) = racedResult else {
            return XCTFail("the raced press was not refused: \(racedResult)")
        }
        XCTAssertEqual(
            racedSentence, LinksChecklistWording.pageChangedSince(name: StartOfYearWording.pageName(page: "Unit 2, Day 5"))
        )
        XCTAssertTrue(try String(contentsOf: classURL, encoding: .utf8).contains("publish: false"))

        let full = try checklistToPress()
        UndoKillPoints.stagingWriteFailsAt = { index in index == 0 }
        let fullResult: LinksChecklistPublisher.Result = LinksChecklistPublisher.publish(
            offer: full.offer, ticked: ["section1/All Classes/Unit 2, Day 5"], course: full.made.course,
            sectionNumber: 1, workspaceURL: full.made.root, shownComingWith: []
        )
        UndoKillPoints.stagingWriteFailsAt = nil
        guard case .refused(let fullSentence) = fullResult else {
            return XCTFail("the press on a full disk was not refused: \(fullResult)")
        }
        XCTAssertTrue(fullSentence.hasPrefix("Nothing was changed: "), fullSentence)
        XCTAssertNotEqual(fullSentence, AssistToolRefusal.unreadablePage("ICS3U").message)
    }

    /// Yes to today's class, when the front page went in and could not be
    /// put back (an edit raced the swap, and the put-back failed): the page
    /// DOES name the class now, so the answer is read back from the page,
    /// never "could not save", which was false (the second review of U3a,
    /// MEDIUM a). MUST FAIL with `leftPartWay` answered as `couldNotSave`.
    func testTodaysClassLeftPartWayIsAnsweredByWhatThePageShows() throws {
        let today: AssistFixture.Made = try morning()
        let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-30"))
        let offer: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
            TodaysClassOnTheFrontPage.offer(forSection: 1, in: today.course, today: day)
        )
        let indexURL: URL = SectionIndexPointer.indexURL(forSection: 1, in: today.course)
        UndoKillPoints.beforeTheRename = { _, url in
            if url.lastPathComponent != indexURL.lastPathComponent {
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else {
                return
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("Edited in Obsidian.\n".utf8))
            try? handle.close()
        }
        UndoKillPoints.putBackFailsAt = { index in index == 0 }
        defer {
            UndoKillPoints.beforeTheRename = nil
            UndoKillPoints.putBackFailsAt = nil
        }
        let outcome: TodaysClassOnTheFrontPage.Outcome = TodaysClassOnTheFrontPage.show(offer, in: today.course)
        let after: String = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(after.contains("Unit 2, Day 5"), "the page was put back, so this proves nothing: \(after)")
        // What the page held just before is named, never a silent `.shown`
        // (the third review of U3a, LOW 3; MUST FAIL answering `.shown`).
        guard case .shownKeepingWhatItHeld(let from, let to, let kept, let folder) = outcome else {
            XCTFail("said as \(outcome)")
            return
        }
        // Where the alert's Show in Finder looks: beside the front page.
        XCTAssertEqual(folder.standardizedFileURL.path, indexURL.deletingLastPathComponent().standardizedFileURL.path)
        XCTAssertEqual(from, "Unit 2, Day 4")
        XCTAssertEqual(to, "Unit 2, Day 5")
        XCTAssertEqual(kept.count, 1)
        let keptURL: URL = indexURL.deletingLastPathComponent().appendingPathComponent(kept.first ?? "")
        let keptText: String = try String(contentsOf: keptURL, encoding: .utf8)
        XCTAssertTrue(keptText.contains("Edited in Obsidian."), "the named file does not hold the edit: \(keptText)")
        let line: String = TodaysClassOnTheFrontPage.trailLine(for: outcome, offer: offer).what
        XCTAssertTrue(line.contains(kept.first ?? "?"), line)
    }

    /// Class dates left part way (an edit raced the swap and the put-back
    /// failed) are in the file, so they are said as remembered, naming where
    /// what the file held is kept, never "NOT remembered" (the third review
    /// of U3a, LOW 2). MUST FAIL with the error wrapped into
    /// `Problem.couldNotWrite`.
    func testClassDatesLeftPartWayAreSaidAsRemembered() throws {
        let today: AssistFixture.Made = try morning()
        let firstPlan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08"], source: "", forSection: 1, in: today.course,
            today: try XCTUnwrap(CalendarDay(text: "2026-09-01"))
        )
        try SectionTimetableStore.applyRememberTimetable(firstPlan)
        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08", "2026-09-10"], source: "", forSection: 1, in: today.course,
            today: try XCTUnwrap(CalendarDay(text: "2026-09-01"))
        )
        let fileName: String = plan.fileURL.lastPathComponent
        UndoKillPoints.beforeTheRename = { _, url in
            guard url.lastPathComponent == fileName, let handle = try? FileHandle(forWritingTo: url) else {
                return
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(" ".utf8))
            try? handle.close()
        }
        UndoKillPoints.putBackFailsAt = { index in index == 0 }
        defer {
            UndoKillPoints.beforeTheRename = nil
            UndoKillPoints.putBackFailsAt = nil
        }
        var thrown: Error? = nil
        do {
            try SectionTimetableStore.applyRememberTimetable(plan)
        } catch {
            thrown = error
        }
        guard case JournaledStepError.leftPartWay(_, _, let kept)? = thrown else {
            XCTFail("thrown: \(String(describing: thrown))")
            return
        }
        let onDisk: String = try String(contentsOf: plan.fileURL, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("2026-09-10"), "the dates are not in the file, so this proves nothing: \(onDisk)")
        let said: String = SectionTimetableStore.Problem.savedWithWhatItHeldKept(plan.courseCode, plan.sectionNumber, kept).localizedDescription
        XCTAssertTrue(said.contains("are remembered"), said)
        XCTAssertTrue(said.contains(kept.first ?? "?"), said)
    }

    /// The Class Dates sheet, on dates that went in part way, carries on as
    /// a plain save does: it hands back the remembered timetable (so a verb
    /// waiting on the dates continues once the alert closes) and its one
    /// alert names the kept file, never a blocking line (the first review of
    /// U3c, LOW 6). MUST FAIL with the part-way case answered as
    /// `.notRemembered`, as the sheet's blocking line was.
    func testTheClassDatesSheetCarriesOnWhenTheDatesWentInPartWay() throws {
        let today: AssistFixture.Made = try morning()
        let firstPlan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08"], source: "", forSection: 1, in: today.course,
            today: try XCTUnwrap(CalendarDay(text: "2026-09-01"))
        )
        try SectionTimetableStore.applyRememberTimetable(firstPlan)
        let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: ["2026-09-08", "2026-09-10"], source: "", forSection: 1, in: today.course,
            today: try XCTUnwrap(CalendarDay(text: "2026-09-01"))
        )
        let fileName: String = plan.fileURL.lastPathComponent
        UndoKillPoints.beforeTheRename = { _, url in
            guard url.lastPathComponent == fileName, let handle = try? FileHandle(forWritingTo: url) else {
                return
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(" ".utf8))
            try? handle.close()
        }
        UndoKillPoints.putBackFailsAt = { index in index == 0 }
        defer {
            UndoKillPoints.beforeTheRename = nil
            UndoKillPoints.putBackFailsAt = nil
        }
        guard case .rememberedKeeping(let remembered) = SectionScheduleSheet.save(plan, noun: .class) else {
            XCTFail("the part-way save was not carried on as remembered")
            return
        }
        XCTAssertEqual(remembered.timetable.dates, plan.dates)
        XCTAssertEqual(remembered.title, "The class dates for \(plan.courseCode) Section \(plan.sectionNumber) are remembered.")
        var keptOnDisk: [String] = []
        let folder: URL = plan.fileURL.deletingLastPathComponent()
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) where name.hasSuffix("-orig") {
            keptOnDisk.append(name)
        }
        XCTAssertEqual(keptOnDisk.count, 1, "\(keptOnDisk)")
        XCTAssertTrue(remembered.message.contains(keptOnDisk.first ?? "?"), remembered.message)
        // The alert's Show in Finder shows exactly the kept file on the disk.
        XCTAssertEqual(remembered.keptFiles, [folder.appendingPathComponent(keptOnDisk.first ?? "?")])
    }

    /// A press that went in part way (a page could not be put back after the
    /// step was refused) says so, `publishStoppedPartWay`, naming where the
    /// page's earlier content is kept, never "Nothing was changed" (the
    /// second review of U3a, MEDIUM a). MUST FAIL without the part-way case
    /// in `LinksChecklistPublisher.sentence(forRefused:)`.
    func testAChecklistPressLeftPartWaySaysOnlyPartWasChanged() throws {
        let pressed = try checklistToPress()
        let course: Course = pressed.made.course
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: 1, in: course, workspaceURL: pressed.made.root
        )
        let step: JournaledStep = JournaledStep(
            course: course, section: 1, maker: UndoStepMaker.sheet("answerTheLinksChecklist")
        )
        let kept: String = ".Unit 2, Day 5.md" + UndoSwap.stagedMarker + "1-apply-orig"
        let error: JournaledStepError = JournaledStepError.leftPartWay(
            .fileIsInUse(path: "courses/ICS3U/section1/All Classes/Unit 2, Day 6.md"),
            fileName: "Unit 2, Day 6.md", keptOriginals: [kept]
        )
        let said: String = LinksChecklistPublisher.sentence(
            forRefused: error, of: step, graph: graph, offer: pressed.offer, in: course
        )
        XCTAssertEqual(
            said, AssistWording.publishStoppedPartWay(what: "the pages you ticked", problem: error.localizedDescription)
        )
        XCTAssertTrue(said.contains(kept), said)
        XCTAssertFalse(said.hasPrefix("Nothing was changed"), said)
    }

    /// A press the door could not check (`cannotTellNow`) says "could not
    /// be read" only for a file that really cannot be read now; a place
    /// that is a folder, not a page, is the could-not-be-saved sentence (the
    /// second review of U3a, LOW 3). MUST FAIL with the unreadable-page
    /// sentence said for every `cannotTellNow`.
    func testAPressThatCannotBeCheckedSaysUnreadableOnlyForAFileThatCannotBeRead() throws {
        let pressed = try checklistToPress()
        let course: Course = pressed.made.course
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: 1, in: course, workspaceURL: pressed.made.root
        )
        let step: JournaledStep = JournaledStep(
            course: course, section: 1, maker: UndoStepMaker.sheet("answerTheLinksChecklist")
        )
        let unreadableSentence: String = AssistToolRefusal.unreadablePage(pressed.offer.course).message

        let classURL: URL = AssistFixture.pageURL(of: "Unit 2, Day 5", in: course)
        let folderURL: URL = classURL.deletingLastPathComponent().appendingPathComponent("A folder.md", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let atAFolder: String = LinksChecklistPublisher.sentence(
            forRefused: JournaledStepError.refused(.cannotTellNow(path: folderURL.path), fileName: "A folder.md"),
            of: step, graph: graph, offer: pressed.offer, in: course
        )
        XCTAssertTrue(atAFolder.hasPrefix("Nothing was changed: "), atAFolder)
        XCTAssertNotEqual(atAFolder, unreadableSentence)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: classURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: classURL.path)
        }
        let atAnUnreadableFile: String = LinksChecklistPublisher.sentence(
            forRefused: JournaledStepError.refused(.cannotTellNow(path: classURL.path), fileName: "Unit 2, Day 5.md"),
            of: step, graph: graph, offer: pressed.offer, in: course
        )
        XCTAssertEqual(atAnUnreadableFile, unreadableSentence)
    }

    /// The fixture's course settings list their keys in sorted order, so
    /// two fixture courses hold the same bytes (the second review of U3a,
    /// LOW 1: written without `.sortedKeys`, a dictionary's order made
    /// `testAListThatCannotBeWrittenChangesNothingAboutAnAction` fail now
    /// and then). MUST FAIL without `.sortedKeys` (the order is then sorted
    /// only by chance).
    func testTheFixtureWritesItsSettingsInOneOrder() throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: .local)
        let text: String = try String(contentsOf: made.course.configFileURL, encoding: .utf8)
        var keys: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("  \""), let close = trimmed.dropFirst().firstIndex(of: "\"") {
                keys.append(String(trimmed[trimmed.index(after: trimmed.startIndex)..<close]))
            }
        }
        XCTAssertGreaterThan(keys.count, 3, text)
        XCTAssertEqual(keys, keys.sorted(), text)
    }

    // MARK: - Functions

    /// Every page and record of a course, by its path inside the course,
    /// leaving out what is not the teacher's (backups, the folder's id).
    static func pages(of course: Course) -> [String: Data] {
        var result: [String: Data] = [:]
        for (path, data) in snapshot(of: course.directoryURL) {
            if path.hasPrefix("_backups/") || path.contains(".internal/") {
                continue
            }
            result[path] = data
        }
        return result
    }

    /// `undo-action-steps.json`'s bytes.
    static func document(_ recorded: [Recorded]) throws -> Data {
        var steps: [[String: Any]] = []
        for step in recorded {
            var files: [[String: Any]] = []
            for file in step.files {
                files.append([
                    "path": file.path,
                    "before": text(file.before),
                    "after": text(file.after),
                ])
            }
            var recomputes: [[String: Any]] = []
            for kept in step.recomputes {
                var entry: [String: Any] = ["path": kept.path, "maintainer": kept.maintainer]
                if let section = kept.section {
                    entry["section"] = section
                }
                recomputes.append(entry)
            }
            var entry: [String: Any] = [
                "name": step.name,
                "action": step.action,
                "madeBy": UndoActionStepsTests.maker(step.madeBy),
                "files": files,
                "recomputes": recomputes,
                "ops": step.opKinds,
            ]
            if !step.moves.isEmpty {
                var moves: [[String: Any]] = []
                for moved in step.moves {
                    moves.append([
                        "from": UndoActionStepsTests.stampless(moved.from),
                        "to": UndoActionStepsTests.stampless(moved.to),
                        "content": text(moved.content),
                        "standsApart": moved.standsApart,
                    ])
                }
                entry["moves"] = moves
            }
            if !step.members.isEmpty {
                var members: [[String: Any]] = []
                for member in step.members {
                    var written: [String: Any] = ["path": member.path, "keyPath": member.keyPath]
                    if let before = member.before {
                        written["before"] = before.foundation()
                    }
                    if let after = member.after {
                        written["after"] = after.foundation()
                    }
                    members.append(written)
                }
                entry["members"] = members
            }
            if !step.trees.isEmpty {
                var trees: [[String: Any]] = []
                for tree in step.trees {
                    var files: [String: Any] = [:]
                    for (path, data) in tree.files {
                        files[path] = text(data)
                    }
                    trees.append(["path": tree.path, "folders": tree.folders, "files": files])
                }
                entry["trees"] = trees
            }
            steps.append(entry)
        }
        let object: [String: Any] = [
            "note": "Written by the mac's UndoActionStepsTests from the REAL action code (#899, U3), never by hand: each daily page action run once on a fixture, and the one step it left on the list read back. `files` is every file its content ops name, in op order, with its whole text before and after (null: absent); `moves` (U3b, only when there are any) every file it moved, in op order, from and to (the moment in a kept copy's name set to one fixed moment), its text, and whether it stands apart from the step (moveApart) or not (move); `members` (U4a, only when there are any) every editJSON op, in op order, its file, keyPath and before and after (left out: absent); `trees` (U4a, only when there are any) every folder made (createTree), in op order, its path, the folders inside it and every file's text by its path inside it; `recomputes` its recompute ops; `ops` the op kinds the door chose, in order. `madeBy` is the word before the first colon. scripts/make_undo_traces.py makes contracts/undo-traces.json -> actionTraces from it. Regenerate: TEST_RUNNER_PLANTOIR_WRITE_UNDO_ACTION_STEPS=1 xcodebuild test -only-testing:QuartzTeachersTests/UndoActionStepsTests/testEveryDailyActionIsOneStepThroughTheDoor, then python3 scripts/make_undo_traces.py.",
            "steps": steps,
        ]
        var data: Data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    /// A path with the moment a rollover names its kept copies by
    /// (`previous-yyyy-MM-dd_HHmmss`) set to one fixed moment, so the
    /// document is the same on every run.
    static func stampless(_ path: String) -> String {
        guard let found = path.range(of: "previous-") else {
            return path
        }
        let rest: Substring = path[found.upperBound...]
        if rest.count < 17 {
            return path
        }
        let stamp: Substring = rest.prefix(17)
        var shape: String = ""
        for character in stamp {
            shape.append(character.isNumber ? "9" : character)
        }
        if shape != "9999-99-99_999999" {
            return path
        }
        return String(path[path.startIndex..<found.upperBound]) + "2026-09-08_070000" + String(rest.dropFirst(17))
    }

    static func text(_ data: Data?) -> Any {
        guard let data, let text = String(data: data, encoding: .utf8) else {
            return NSNull()
        }
        return text
    }

    /// Who made it, without the session's own id.
    static func maker(_ madeBy: String) -> String {
        guard let colon = madeBy.firstIndex(of: ":") else {
            return madeBy
        }
        return String(madeBy[madeBy.startIndex..<colon])
    }

    /// The document with every moment a record carries (`answeredAt`,
    /// `recorded`) blanked, so a run on another day still compares.
    static func masked(_ data: Data) -> String {
        let text: String = String(decoding: data, as: UTF8.self)
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            lines.append(maskedLine(line))
        }
        return lines.joined(separator: "\n")
    }

    /// A line with the value after `"answeredAt" : "` or `"recorded" : "`
    /// (or their escaped forms inside a page's text) blanked up to its
    /// closing quote.
    static func maskedLine(_ line: String) -> String {
        var result: String = line
        for key in ["answeredAt", "recorded"] {
            for quote in ["\\\"", "\""] {
                let opening: String = quote + key + quote + " : " + quote
                guard let found = result.range(of: opening) else {
                    continue
                }
                let rest: Substring = result[found.upperBound...]
                guard let closing = rest.range(of: quote) else {
                    continue
                }
                result = String(result[result.startIndex..<found.upperBound]) + "…" + String(result[closing.lowerBound...])
            }
        }
        return result
    }

    // MARK: - Replaying contracts/undo-traces.json -> actionTraces

    static func replayActionTraces(under parent: URL) async throws -> (traces: Int, calls: Int, failures: [String]) {
        UndoContractReplay.registerTheFrontPageMaintainer()
        let document: [String: Any] = try UndoContractReplay.contract("undo-traces.json")
        let stepsDocument: [String: Any] = try UndoContractReplay.contract("undo-action-steps.json")
        var stepNamed: [String: [String: Any]] = [:]
        for step in stepsDocument["steps"] as? [[String: Any]] ?? [] {
            if let name = step["name"] as? String {
                stepNamed[name] = step
            }
        }
        let traces: [[String: Any]] = document["actionTraces"] as? [[String: Any]] ?? []
        var failures: [String] = []
        var callCount: Int = 0
        for trace in traces {
            let name: String = trace["name"] as? String ?? "?"
            guard let step = stepNamed[trace["step"] as? String ?? ""] else {
                failures.append("\(name): no recorded step \(trace["step"] as? String ?? "?")")
                continue
            }
            let place: (root: URL, journalFolder: URL) = try UndoContractReplay.scratch(under: parent, named: name)
            let root: URL = place.root
            var changes: [UndoFileChange] = []
            var paths: [String] = []
            for file in step["files"] as? [[String: Any]] ?? [] {
                let path: String = file["path"] as? String ?? ""
                paths.append(path)
                var before: Data? = nil
                if let text = file["before"] as? String {
                    before = Data(text.utf8)
                    try UndoContractReplay.write(text, to: path, in: root)
                }
                var after: Data? = nil
                if let text = file["after"] as? String {
                    after = Data(text.utf8)
                }
                changes.append(UndoFileChange(relativePath: path, before: before, after: after))
            }
            // U4a: a JSON file planned member by member, and folders made.
            var memberOps: [String: [UndoOp]] = [:]
            for member in step["members"] as? [[String: Any]] ?? [] {
                let path: String = member["path"] as? String ?? ""
                var before: UndoJSON? = nil
                if let value = member["before"] {
                    before = UndoJSON.from(foundation: value)
                }
                var after: UndoJSON? = nil
                if let value = member["after"] {
                    after = UndoJSON.from(foundation: value)
                }
                memberOps[path, default: []].append(UndoOp.editJSON(
                    path: path, keyPath: member["keyPath"] as? [String] ?? [], before: before, after: after
                ))
            }
            var treeOps: [UndoOp] = []
            var treeBlobs: [Data] = []
            for tree in step["trees"] as? [[String: Any]] ?? [] {
                let path: String = tree["path"] as? String ?? ""
                var files: [UndoTreeListing.File] = []
                for (inside, value) in tree["files"] as? [String: Any] ?? [:] {
                    let data: Data = Data((value as? String ?? "").utf8)
                    files.append(UndoTreeListing.File(path: inside, sha: UndoHash.sha256(of: data)))
                    treeBlobs.append(data)
                }
                let listing: UndoTreeListing = UndoTreeListing(folders: tree["folders"] as? [String] ?? [], files: files)
                treeBlobs.append(listing.data)
                treeOps.append(UndoOp.tree(.createTree, path: path, listing: listing))
                paths.append(path)
            }
            var moveOps: [UndoOp] = []
            for moved in step["moves"] as? [[String: Any]] ?? [] {
                let from: String = moved["from"] as? String ?? ""
                let to: String = moved["to"] as? String ?? ""
                let content: String = moved["content"] as? String ?? ""
                try UndoContractReplay.write(content, to: from, in: root)
                paths.append(from)
                paths.append(to)
                let sha: String = UndoHash.sha256(of: Data(content.utf8))
                if moved["standsApart"] as? Bool == true {
                    moveOps.append(UndoOp.moveFileApart(from: from, to: to, sha: sha))
                } else {
                    moveOps.append(UndoOp.moveFile(from: from, to: to, sha: sha))
                }
            }
            var recomputes: [UndoOp] = []
            for kept in step["recomputes"] as? [[String: Any]] ?? [] {
                recomputes.append(UndoOp.recompute(
                    path: kept["path"] as? String ?? "", maintainer: kept["maintainer"] as? String ?? "",
                    section: UndoContractReplay.int(kept["section"])
                ))
            }
            let journal: UndoJournal = UndoJournal(folderURL: place.journalFolder)
            let calls: [[String: Any]] = trace["calls"] as? [[String: Any]] ?? []
            var lastUndoIndex: Int = -1
            var index: Int = 0
            while index < calls.count {
                if calls[index]["call"] as? String == "undo" {
                    lastUndoIndex = index
                }
                index += 1
            }
            var afterUndoingAll: [String: String?] = [:]
            index = 0
            for call in calls {
                callCount += 1
                let where_: String = "\(name) call \(index + 1)"
                let kind: String = call["call"] as? String ?? ""
                let expect: String? = call["expect"] as? String
                switch kind {
                case "action":
                    let draft: UndoStepDraft = UndoStepDraft(
                        action: UndoAction(key: step["action"] as? String ?? "", arguments: [:]),
                        madeBy: step["madeBy"] as? String ?? "menu",
                        workingFolderURL: root, workingFolderPath: root.path,
                        course: "ICS3U", section: 1, actionClass: "A", holds: "section",
                        changes: changes, recomputes: recomputes
                    )
                    let outcome: JournaledWriteOutcome
                    if moveOps.isEmpty && memberOps.isEmpty && treeOps.isEmpty {
                        outcome = JournaledWrite.perform(draft, in: journal, mode: .live)
                    } else {
                        // U3b: a step with moves goes through the door that
                        // takes every kind, as `JournaledStep` makes it.
                        var ops: [UndoOp] = []
                        var blobs: [Data] = []
                        for change in changes where change.before != change.after {
                            if let members = memberOps[change.relativePath] {
                                for op in members {
                                    ops.append(op)
                                }
                                continue
                            }
                            for op in JournaledWrite.ops(for: change) {
                                ops.append(op)
                                if op.knownKind == .writeFile {
                                    if let before = change.before {
                                        blobs.append(before)
                                    }
                                    if let after = change.after {
                                        blobs.append(after)
                                    }
                                }
                            }
                        }
                        for op in moveOps {
                            ops.append(op)
                        }
                        for op in treeOps {
                            ops.append(op)
                        }
                        for blob in treeBlobs {
                            blobs.append(blob)
                        }
                        for op in recomputes {
                            ops.append(op)
                        }
                        outcome = JournaledWrite.perform(
                            ops: UndoOpsDraft(
                                action: draft.action, madeBy: draft.madeBy, workingFolderURL: root,
                                workingFolderPath: root.path, course: "ICS3U", section: 1, actionClass: "A",
                                holds: "section", ops: ops, blobs: blobs
                            ),
                            in: journal, mode: .live
                        )
                    }
                    if expect == "applied" {
                        let seq: Int = UndoContractReplay.int(call["seq"]) ?? -1
                        if outcome != .applied(seq: seq) {
                            failures.append("\(where_): the step came to \(outcome), not applied \(seq)")
                        } else {
                            var kinds: [String] = []
                            for op in try journal.read().records[seq]?.step.ops ?? [] {
                                kinds.append(op.kind)
                            }
                            if kinds != (call["ops"] as? [String] ?? []) {
                                failures.append("\(where_): the door chose \(kinds), not \(call["ops"] as? [String] ?? [])")
                            }
                        }
                    } else if outcome != .changedNothing {
                        failures.append("\(where_): the step came to \(outcome), not changedNothing")
                    }
                case "undo", "redo":
                    let outcome: UndoOutcome = kind == "undo"
                        ? await journal.undoNewestAndRederive(resolveRoot: { _ in root })
                        : await journal.redoNewestAndRederive(resolveRoot: { _ in root })
                    let word: String = UndoContractReplay.outcomeWord(outcome)
                    if word != expect {
                        failures.append("\(where_): \(kind) came to \(word), not \(expect ?? "?")")
                    }
                    if case .undone(let seq, _, _) = outcome, seq != UndoContractReplay.int(call["seq"]) {
                        failures.append("\(where_): undid \(seq)")
                    }
                    let leftApart: [String] = UndoContractReplay.leftApart(of: outcome)
                    if leftApart != (call["leftApart"] as? [String] ?? []) {
                        failures.append("\(where_): left apart \(leftApart), not \(call["leftApart"] as? [String] ?? [])")
                    }
                    if case .redone(let seq, _, _) = outcome, seq != UndoContractReplay.int(call["seq"]) {
                        failures.append("\(where_): redid \(seq)")
                    }
                    if case .refused(.changedSince(let first, let others), let cleared) = outcome {
                        if first != call["path"] as? String {
                            failures.append("\(where_): named \(first), not \(call["path"] as? String ?? "?")")
                        }
                        if others != UndoContractReplay.int(call["others"]) {
                            failures.append("\(where_): \(others) others")
                        }
                        if (kind == "undo") != cleared {
                            failures.append("\(where_): cleared \(cleared) on a refused \(kind)")
                        }
                    }
                case "handEdit":
                    try UndoContractReplay.handEdit(call["kind"] as? String ?? "", at: call["path"] as? String ?? "", in: root)
                case "note":
                    try UndoContractReplay.appendNote(to: journal)
                case "deploy":
                    // U3b: a deploy writes a new marker in the place a
                    // rollover's marker left, and nothing to the list.
                    try UndoContractReplay.write(call["text"] as? String ?? "", to: call["path"] as? String ?? "", in: root)
                default:
                    failures.append("\(where_): unknown call \(kind)")
                }
                let offer: UndoOffer = try journal.offer()
                if offer.head?.step.seq != UndoContractReplay.int(call["head"]) {
                    failures.append("\(where_): head \(String(describing: offer.head?.step.seq))")
                }
                if offer.redoCandidate?.step.seq != UndoContractReplay.int(call["redo"]) {
                    failures.append("\(where_): redo \(String(describing: offer.redoCandidate?.step.seq))")
                }
                if index == lastUndoIndex {
                    for path in paths {
                        afterUndoingAll[path] = UndoContractReplay.hash(of: path, in: root)
                    }
                }
                index += 1
            }
            let wantedAfterUndoing: [String: Any] = trace["afterUndoingAll"] as? [String: Any] ?? [:]
            let wantedFinal: [String: Any] = trace["final"] as? [String: Any] ?? [:]
            for path in paths {
                if (wantedAfterUndoing[path] as? String) != (afterUndoingAll[path] ?? nil) {
                    failures.append("\(name): \(path) after undoing everything is not the contract's")
                }
                if (wantedFinal[path] as? String) != UndoContractReplay.hash(of: path, in: root) {
                    failures.append("\(name): \(path) at the end is not the contract's")
                }
            }
            if UndoContractReplay.staysBeside(root) {
                failures.append("\(name): a staged file was left beside a page")
            }
        }
        return (traces: traces.count, calls: callCount, failures: failures)
    }
}
