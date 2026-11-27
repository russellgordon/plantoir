import XCTest
@testable import QuartzTeachers

/// Get Ready for the Start of the Year, stopped part way, offers to restore
/// the course (#899, Russell's ruling of 2026-11-26): the same sheet says
/// what happened and offers the backup Go made, with Leave As It Is (Escape)
/// and Restore Course (Return). A stop that changed nothing stays
/// `writeFailed`. The cases are `shared-rules.json` →
/// `startOfYear.stoppedPartWayCases`, run from the JSON.
@MainActor
final class StartOfYearRestoreOfferTests: XCTestCase {

    // MARK: - Stored properties

    private var previousTrail: ProblemReportStore = ActivityTrail.store
    private var trailFolder: URL = URL(fileURLWithPath: "/")

    /// The Undo list of this test alone. A Get Ready stopped part way
    /// leaves its step in flight, and on the list the whole suite shares
    /// a later test's recovery would close it (day27-7).
    private var listFolder: URL = URL(fileURLWithPath: "/")

    // MARK: - Set up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        trailFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("start-of-year-offer-trail-\(UUID().uuidString)")
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
        listFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("start-of-year-offer-list-\(UUID().uuidString)", isDirectory: true)
        UndoJournalLocation.folderOverride = listFolder
        StartOfYearUndoRegistry.shared.forgetAll()
    }

    override func tearDown() async throws {
        UndoKillPoints.fileInUseAtSwap = nil
        UndoKillPoints.putBackFailsAt = nil
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: trailFolder)
        UndoJournalLocation.folderOverride = nil
        try? FileManager.default.removeItem(at: listFolder)
        StartOfYearUndoRegistry.shared.forgetAll()
        FakePreview.shared.forget()
        SectionWindowControllers.shared.forgetAll()
        PreviewLeases.reset()
        CourseActivity.reset()
    }

    // MARK: - The contract's cases

    func testStoppedPartWayCasesAsTheContractSays() async throws {
        let rules: [String: Any] = try StartOfYearTests.rules("startOfYear")
        let wording: [String: String] = try XCTUnwrap(rules["wording"] as? [String: String])
        let cases: [[String: Any]] = try XCTUnwrap(rules["stoppedPartWayCases"] as? [[String: Any]])
        let plainYear: [String: Any] = try XCTUnwrap((rules["cases"] as? [[String: Any]])?.first)
        XCTAssertEqual(plainYear["name"] as? String, "the plain year")
        let layout: [[String: Any]] = try XCTUnwrap(plainYear["pages"] as? [[String: Any]])
        let planned: [String] = try XCTUnwrap(plainYear["expectDraft"] as? [String])
        XCTAssertGreaterThanOrEqual(cases.count, 3)

        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let made = try AssistFixture.makeRunner(surface: .mcp)
            defer { try? FileManager.default.removeItem(at: made.root) }
            let urls: [String: URL] = try StartOfYearTests.layOut(layout, in: made.course)

            var restoredFrom: [BackupItem] = []
            let model: StartOfYearSheetModel = StartOfYearSheetModel(
                course: made.course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady,
                restoreWholeCourse: { (item: BackupItem) async in
                    restoredFrom.append(item)
                }
            )
            model.load()
            guard case .ready = model.stage else {
                XCTFail("\(name): no plan: \(model.stage)")
                continue
            }

            let door: [String: Int] = try XCTUnwrap(testCase["door"] as? [String: Int])
            let heldOpen: Int? = door["fileInUseAtSwap"]
            let cannotPutBack: Int? = door["putBackFailsAt"]
            UndoKillPoints.fileInUseAtSwap = { (index: Int) -> Bool in
                return index == heldOpen
            }
            UndoKillPoints.putBackFailsAt = { (index: Int) -> Bool in
                return index == cannotPutBack
            }
            await model.goAhead()
            UndoKillPoints.fileInUseAtSwap = nil
            UndoKillPoints.putBackFailsAt = nil

            var inDraft: Int = 0
            for title in planned {
                let url: URL = try XCTUnwrap(urls[title], "\(name): \(title) was not laid out")
                let text: String = try String(contentsOf: url, encoding: .utf8)
                if PageVisibilityReader.answer(in: text, forSection: 1) == .hidden {
                    inDraft += 1
                }
            }
            XCTAssertEqual(inDraft, testCase["expectInDraft"] as? Int, "\(name): pages in draft afterwards")

            let expect: String = try XCTUnwrap(testCase["expect"] as? String)
            if expect == "writeFailed" {
                guard case .problem(let sentence) = model.stage else {
                    XCTFail("\(name): not writeFailed: \(model.stage)")
                    continue
                }
                XCTAssertTrue(sentence.hasPrefix(try XCTUnwrap(wording["writeFailed"]?.components(separatedBy: "{backup}").first)), "\(name): \(sentence)")
                XCTAssertFalse(sentence.contains(UndoSwap.stagedMarker), "\(name) names a hidden file: \(sentence)")
                continue
            }

            XCTAssertEqual(expect, "stoppedPartWay")
            guard case .stoppedPartWay(let stopped) = model.stage else {
                XCTFail("\(name): no offer: \(model.stage)")
                continue
            }
            let sentences: [String] = StartOfYearSheetModel.stoppedPartWaySentences(stopped)
            let first: String = try XCTUnwrap(wording["stoppedPartWay"])
                .replacingOccurrences(of: "{section}", with: "1")
                .replacingOccurrences(of: "{course}", with: "ICS3U")
            let second: String = try XCTUnwrap(wording["restoreOffer"])
                .replacingOccurrences(of: "{course}", with: "ICS3U")
                .replacingOccurrences(of: "{backup}", with: stopped.backupFileName)
            XCTAssertEqual(sentences, [first, second], name)
            for sentence in sentences {
                XCTAssertFalse(sentence.contains(UndoSwap.stagedMarker), "\(name) names a hidden file: \(sentence)")
                XCTAssertFalse(sentence.contains("hidden file"), "\(name) names a hidden file: \(sentence)")
            }
            XCTAssertTrue(stopped.backupFileName.hasPrefix("ICS3U_backup_"), stopped.backupFileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stopped.backupURL.path), "\(name): no backup")
            XCTAssertFalse(stopped.keptOriginals.isEmpty, "\(name): nothing kept, so this was not part way")
            XCTAssertTrue(StartOfYearTests.trail().contains("stopped part way"), StartOfYearTests.trail())
            XCTAssertFalse(StartOfYearTests.trail().contains("nothing was changed (writeFailed)"), StartOfYearTests.trail())

            let then: String = try XCTUnwrap(testCase["then"] as? String)
            if then == "leaveAsItIs" {
                // Leave As It Is only closes the sheet: its action is
                // `dismiss()` alone (`testTheTwoButtonsTheirRolesAndTheirOrder`).
                // So nothing is restored, every file of the course is as
                // Go left it, and the backup stays in Backups.
                let afterGo: [String: Data] = try StartOfYearRestoreOfferTests.everyFile(under: made.root)
                XCTAssertEqual(restoredFrom.count, 0, name)
                XCTAssertNotNil(afterGo[stopped.backupURL.standardizedFileURL.path], "\(name): the backup is not in Backups")
                let lister: [BackupItem] = WorkspaceModel.findBackupItems(in: made.root.appendingPathComponent("courses"))
                var listed: Bool = false
                for item in lister {
                    if item.fileURL.standardizedFileURL == stopped.backupURL.standardizedFileURL {
                        listed = true
                    }
                }
                XCTAssertTrue(listed, "\(name): Restore from Backup… does not list the backup")
            } else {
                XCTAssertEqual(then, "restoreCourse")
                await model.restoreCourse()
                XCTAssertEqual(restoredFrom.count, 1, "\(name): Restore Course did not run the restore once")
                XCTAssertEqual(restoredFrom.first?.fileURL.standardizedFileURL, stopped.backupURL.standardizedFileURL, name)
                XCTAssertEqual(restoredFrom.first?.courseCode, "ICS3U", name)
            }
        }
    }

    // MARK: - The real restore, with previews running (review 1, HIGH 1)

    /// This section's preview was running when Go was pressed. Go stops it
    /// before it writes; after a part-way stop it is NOT started again
    /// while the offer is open, so the real whole-course restore
    /// (`WorkspaceModel.restoreBackup`) is not refused as busy; once the
    /// restore is done it is started again, once. MUST FAIL on aa991d513,
    /// where the part-way branch restarted the preview before the offer and
    /// the restore said "ICS3U is previewing or deploying right now".
    func testRestoreCourseRestoresWhileThisSectionWasPreviewing() async throws {
        let stopped: Stopped = try await stopPartWay(sections: [1])
        defer { try? FileManager.default.removeItem(at: stopped.root) }
        let preview: FakePreview = FakePreview.shared
        preview.register(folderPath: stopped.root.path, courseCode: "ICS3U", sectionNumber: 1, holdingALease: true)
        try await stopped.goAhead()

        XCTAssertFalse(preview.events.contains("start"), "the preview was started again before the offer was answered: \(preview.events)")
        await stopped.model.restoreCourse()

        XCTAssertNil(stopped.workspace.backupProblem, stopped.workspace.backupProblem ?? "")
        try stopped.assertEveryPlannedPageIsBackAsItWas()
        XCTAssertEqual(StartOfYearRestoreOfferTests.count("start", in: preview.events), 1, "started again once: \(preview.events)")
        await stopped.model.restoreCourse()
        stopped.model.leaveAsItIs()
        XCTAssertEqual(StartOfYearRestoreOfferTests.count("start", in: preview.events), 1, "nothing starts it twice: \(preview.events)")
    }

    /// Another section of the same course is previewing in its own window.
    /// Restore Course stops that preview itself (the director's reading of
    /// "It must offer an easy way to fix the problem for the user"),
    /// restores, and starts it again. MUST FAIL on aa991d513.
    func testRestoreCourseStopsAndRestartsAnotherSectionsPreview() async throws {
        let stopped: Stopped = try await stopPartWay(sections: [1, 2])
        defer { try? FileManager.default.removeItem(at: stopped.root) }
        let other: FakePreview = FakePreview()
        other.register(folderPath: stopped.root.path, courseCode: "ICS3U", sectionNumber: 2, holdingALease: true)
        defer { other.forget() }
        try await stopped.goAhead()
        XCTAssertEqual(other.events, [], "Go leaves another section's preview alone")

        await stopped.model.restoreCourse()

        XCTAssertNil(stopped.workspace.backupProblem, stopped.workspace.backupProblem ?? "")
        try stopped.assertEveryPlannedPageIsBackAsItWas()
        XCTAssertEqual(other.events, ["stop-begins", "stop-ends", "start"], "stopped before the restore, started once after")
    }

    /// Leave As It Is starts again the preview Go stopped, once, and
    /// changes no file of the working folder.
    func testLeaveAsItIsStartsThePreviewAgainOnceAndChangesNothing() async throws {
        let stopped: Stopped = try await stopPartWay(sections: [1])
        defer { try? FileManager.default.removeItem(at: stopped.root) }
        let preview: FakePreview = FakePreview.shared
        preview.register(folderPath: stopped.root.path, courseCode: "ICS3U", sectionNumber: 1, holdingALease: true)
        try await stopped.goAhead()
        XCTAssertEqual(preview.events, ["stop-begins", "stop-ends"], "not started again before the answer")
        // The course's own files: the preview's lease under `.internal` is
        // the preview starting again, not a change to the course.
        let before: [String: Data] = try StartOfYearRestoreOfferTests.everyFile(under: stopped.course.directoryURL)

        stopped.model.leaveAsItIs()
        stopped.model.leaveAsItIs()
        await stopped.model.restoreCourse()

        XCTAssertEqual(preview.events, ["stop-begins", "stop-ends", "start"], "started again once, and nothing restored")
        XCTAssertEqual(try StartOfYearRestoreOfferTests.everyFile(under: stopped.course.directoryURL), before)
    }

    /// A deploy of the course in flight cannot be stopped: Restore Course is
    /// held back with the restore's own busy sentence, nothing is stopped
    /// or restored, the offer stays; once the deploy ends it works.
    func testADeployHoldsRestoreCourseBackAndTheOfferStillWorksAfter() async throws {
        let stopped: Stopped = try await stopPartWay(sections: [1])
        defer { try? FileManager.default.removeItem(at: stopped.root) }
        let preview: FakePreview = FakePreview.shared
        preview.register(folderPath: stopped.root.path, courseCode: "ICS3U", sectionNumber: 1, holdingALease: true)
        try await stopped.goAhead()
        CourseActivity.beginPublish(folderPath: stopped.root.path, courseCode: "ICS3U", sectionNumber: 1)

        XCTAssertTrue(stopped.model.restoreIsHeldBackByADeploy())
        await stopped.model.restoreCourse()

        let busy: String = WholeCourseRestore.sentence(for: WholeCourseRestore.Refusal.busy, courseCode: "ICS3U", assistant: nil)
        XCTAssertEqual(stopped.model.restoreHeldBack, busy)
        XCTAssertEqual(stopped.model.restoreHeldBackTitle, BackupProblemTitle.restoring("ICS3U"))
        guard case .stoppedPartWay = stopped.model.stage else {
            return XCTFail("the offer is gone: \(stopped.model.stage)")
        }
        XCTAssertEqual(preview.events, ["stop-begins", "stop-ends"], "nothing started or stopped while the deploy runs")
        XCTAssertTrue(StartOfYearTests.trail().contains(WholeCourseRestore.DidNotGoAhead.busy.rawValue), StartOfYearTests.trail())

        CourseActivity.endPublish(folderPath: stopped.root.path, courseCode: "ICS3U", sectionNumber: 1)
        stopped.model.restoreHeldBack = nil
        XCTAssertFalse(stopped.model.restoreIsHeldBackByADeploy())
        await stopped.model.restoreCourse()

        XCTAssertNil(stopped.workspace.backupProblem, stopped.workspace.backupProblem ?? "")
        try stopped.assertEveryPlannedPageIsBackAsItWas()
        XCTAssertEqual(preview.events, ["stop-begins", "stop-ends", "start"])
    }

    // MARK: - Through the assistant

    /// `startOfYear.assistantStoppedPartWayCases`, run from the JSON, through
    /// the built-in assistant and over MCP: one reply, one function.
    func testAssistantStoppedPartWayCasesAsTheContractSays() async throws {
        let rules: [String: Any] = try StartOfYearTests.rules("startOfYear")
        let wording: [String: String] = try XCTUnwrap(rules["wording"] as? [String: String])
        let cases: [[String: Any]] = try XCTUnwrap(rules["assistantStoppedPartWayCases"] as? [[String: Any]])
        let plainYear: [String: Any] = try XCTUnwrap((rules["cases"] as? [[String: Any]])?.first)
        let layout: [[String: Any]] = try XCTUnwrap(plainYear["pages"] as? [[String: Any]])
        let planned: [String] = try XCTUnwrap(plainYear["expectDraft"] as? [String])
        XCTAssertGreaterThanOrEqual(cases.count, 2)
        let surfaces: [AssistToolRunner.Surface] = [.local, .mcp]

        for testCase in cases {
            for surface in surfaces {
                let name: String = try XCTUnwrap(testCase["name"] as? String) + " (\(surface))"
                let made = try AssistFixture.makeRunner(surface: surface)
                defer { try? FileManager.default.removeItem(at: made.root) }
                let urls: [String: URL] = try StartOfYearTests.layOut(layout, in: made.course)

                let shown: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
                    "plan_prepare_for_start_of_year", ["course": "ICS3U", "section": 1]
                ))
                let code: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: shown.detail), name)
                let rebuildsBefore: Int = made.siteWork.previewRebuilds

                let door: [String: Int] = try XCTUnwrap(testCase["door"] as? [String: Int])
                let heldOpen: Int? = door["fileInUseAtSwap"]
                let cannotPutBack: Int? = door["putBackFailsAt"]
                UndoKillPoints.fileInUseAtSwap = { (index: Int) -> Bool in
                    return index == heldOpen
                }
                UndoKillPoints.putBackFailsAt = { (index: Int) -> Bool in
                    return index == cannotPutBack
                }
                let reply: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
                    "prepare_for_start_of_year", ["course": "ICS3U", "section": 1, "planCode": code]
                ))
                UndoKillPoints.fileInUseAtSwap = nil
                UndoKillPoints.putBackFailsAt = nil

                var inDraft: Int = 0
                for title in planned {
                    let url: URL = try XCTUnwrap(urls[title], "\(name): \(title) was not laid out")
                    let text: String = try String(contentsOf: url, encoding: .utf8)
                    if PageVisibilityReader.answer(in: text, forSection: 1) == .hidden {
                        inDraft += 1
                    }
                }
                XCTAssertEqual(inDraft, testCase["expectInDraft"] as? Int, "\(name): pages in draft afterwards")
                XCTAssertFalse(reply.summary.contains(UndoSwap.stagedMarker), "\(name) names a hidden file: \(reply.summary)")
                XCTAssertFalse(reply.detail.contains(UndoSwap.stagedMarker), "\(name) names a hidden file: \(reply.detail)")
                let rebuilt: Bool = made.siteWork.previewRebuilds > rebuildsBefore
                XCTAssertEqual(rebuilt, testCase["expectPreviewRebuilt"] as? Bool, "\(name): the preview")

                let expect: String = try XCTUnwrap(testCase["expect"] as? String)
                if expect == "writeFailed" {
                    let before: String = try XCTUnwrap(wording["writeFailed"]?.components(separatedBy: "{backup}").first)
                    XCTAssertTrue(reply.summary.hasPrefix(before), "\(name): \(reply.summary)")
                    continue
                }
                XCTAssertEqual(expect, "stoppedPartWay")
                let backup: String = try Self.backupNamed(in: reply.summary, name: name)
                let partWay: String = try XCTUnwrap(wording["stoppedPartWay"])
                    .replacingOccurrences(of: "{section}", with: "1")
                    .replacingOccurrences(of: "{course}", with: made.course.displayCode)
                let offer: String = try XCTUnwrap(wording["restoreOfferThroughTheAssistant"])
                    .replacingOccurrences(of: "{backup}", with: backup)
                    .replacingOccurrences(of: "{course}", with: made.course.displayCode)
                XCTAssertEqual(reply.summary, partWay + " " + offer, name)
                XCTAssertTrue(reply.detail.hasPrefix(reply.summary + "\n\n"), "\(name): \(reply.detail)")
                let planText: String = shown.detail.components(separatedBy: "\n\nPlan code:").first ?? shown.detail
                XCTAssertTrue(reply.detail.contains(planText), "\(name): the reply keeps the plan: \(reply.detail)")
                XCTAssertTrue(StartOfYearTests.trail().contains("offered the backup " + backup), StartOfYearTests.trail())
                XCTAssertFalse(StartOfYearTests.trail().contains("(writeFailed)"), "\(name): \(StartOfYearTests.trail())")
            }
        }
    }

    /// A preview running before the assistant's Get Ready is running after
    /// it, whatever the outcome: done, nothing to do, write failed, stopped
    /// part way. Over MCP, with the section's window registered and its
    /// preview showing (a window the local assistant would open is not
    /// opened here).
    func testAPreviewRunningBeforeTheAssistantsGetReadyIsRunningAfterEveryOutcome() async throws {
        let rules: [String: Any] = try StartOfYearTests.rules("startOfYear")
        let plainYear: [String: Any] = try XCTUnwrap((rules["cases"] as? [[String: Any]])?.first)
        let layout: [[String: Any]] = try XCTUnwrap(plainYear["pages"] as? [[String: Any]])
        let outcomes: [String] = ["done", "nothingToDo", "writeFailed", "stoppedPartWay"]

        for outcome in outcomes {
            let made = try AssistFixture.makeRunner(registeringPreview: true, surface: .mcp)
            defer { try? FileManager.default.removeItem(at: made.root) }
            if outcome == "nothingToDo" {
                try AssistFixture.write(page: "Unit 1, Day 1", publish: "true", date: "2026-09-08",
                                        body: "One.", in: made.course)
            } else {
                _ = try StartOfYearTests.layOut(layout, in: made.course)
            }
            let shown: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
                "plan_prepare_for_start_of_year", ["course": "ICS3U", "section": 1]
            ))
            let code: String = try XCTUnwrap(StartOfYearPlanner.planCode(in: shown.detail), "\(outcome): \(shown.detail)")
            if outcome == "writeFailed" {
                UndoKillPoints.fileInUseAtSwap = { (index: Int) -> Bool in
                    return index == 0
                }
            }
            if outcome == "stoppedPartWay" {
                UndoKillPoints.fileInUseAtSwap = { (index: Int) -> Bool in
                    return index == 1
                }
                UndoKillPoints.putBackFailsAt = { (index: Int) -> Bool in
                    return index == 0
                }
            }
            let reply: AssistToolOutcome = await made.runner.run(call: StartOfYearTests.call(
                "prepare_for_start_of_year", ["course": "ICS3U", "section": 1, "planCode": code]
            ))
            UndoKillPoints.fileInUseAtSwap = nil
            UndoKillPoints.putBackFailsAt = nil

            if outcome == "writeFailed" {
                XCTAssertTrue(reply.summary.hasPrefix("Plantoir could not finish"), "\(outcome): \(reply.summary)")
            }
            if outcome == "stoppedPartWay" {
                XCTAssertTrue(reply.summary.hasPrefix(StartOfYearWording.stoppedPartWay(course: "ICS3U", section: "1")), "\(outcome): \(reply.summary)")
            }
            if outcome == "nothingToDo" {
                XCTAssertFalse(reply.summary.contains("Plantoir could not"), "\(outcome): \(reply.summary)")
            }
            let controller: SectionWindowControllers.Controller? = SectionWindowControllers.shared.controller(
                folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1
            )
            let running: Bool = controller?.isPreviewRunning() ?? false
            XCTAssertTrue(running, "\(outcome): the preview is not running again: \(FakePreview.shared.events) \(reply.summary)")
            FakePreview.shared.forget()
            SectionWindowControllers.shared.forgetAll()
        }
    }

    /// The offer through the assistant names the menu item as the menu
    /// titles it.
    func testTheAssistantsOfferNamesTheMenuItemAsItIsTitled() {
        let offer: String = StartOfYearWording.restoreOfferThroughTheAssistant(course: "SNC1W", backup: "SNC1W_backup_x.zip")
        XCTAssertTrue(offer.contains("Choose " + CourseMenu.restoreFromBackupMenuItem + " "), offer)
        XCTAssertEqual(CourseMenu.restoreFromBackupMenuItem, "Restore from Backup…")
    }

    /// The backup's name between the curly quotes of a sentence.
    static func backupNamed(in sentence: String, name: String) throws -> String {
        let opening: Range<String.Index> = try XCTUnwrap(sentence.range(of: "“"), "\(name): no backup named: \(sentence)")
        let rest: Substring = sentence[opening.upperBound...]
        let closing: Range<Substring.Index> = try XCTUnwrap(rest.range(of: "”"), "\(name): \(sentence)")
        return String(rest[..<closing.lowerBound])
    }

    /// The trail line after a part-way stop (review 1, LOW 2).
    func testTheStoppedPartWayLineCountsWhatWasKept() {
        let none: String = ActivityTrail.startOfYearStoppedPartWayLine(source: "app", keptCount: 0, backupFileName: "B.zip")
        let one: String = ActivityTrail.startOfYearStoppedPartWayLine(source: "app", keptCount: 1, backupFileName: "B.zip")
        let two: String = ActivityTrail.startOfYearStoppedPartWayLine(source: "app", keptCount: 2, backupFileName: "B.zip")
        XCTAssertFalse(none.contains("kept"), none)
        XCTAssertTrue(none.contains("some pages went into draft; offered the backup B.zip"), none)
        XCTAssertTrue(one.contains(", 1 file kept beside its page;"), one)
        XCTAssertTrue(two.contains(", 2 files kept beside their pages;"), two)
    }

    // MARK: - The sentences

    /// The offer names the buttons as they are titled.
    func testTheOfferNamesItsButtonsAsTheyAreTitled() {
        let offer: String = StartOfYearWording.restoreOffer(course: "SNC1W", backup: "SNC1W_backup_x.zip")
        XCTAssertTrue(offer.hasPrefix(StartOfYearWording.restoreCourseButton + " "), offer)
        XCTAssertTrue(offer.contains("you pressed " + StartOfYearWording.goButton + ","), offer)
    }

    // MARK: - The sheet as written

    /// Leave As It Is first (leading, Escape, the cancel role), Restore
    /// Course second (trailing, Return); Leave only closes, Restore closes
    /// and restores. A scan, as `SheetConventionScanTests`, since the sheet
    /// needs a whole course and a failing door to draw.
    func testTheTwoButtonsTheirRolesAndTheirOrder() throws {
        let views: URL = TextFieldStyleScanTests.viewsURL()
        let source: String = try String(contentsOf: views.appendingPathComponent("Section/StartOfYearSheet.swift"), encoding: .utf8)
        var leaveAt: Int? = nil
        var restoreAt: Int? = nil
        var leaveChain: String = ""
        var restoreChain: String = ""
        let buttons: [SheetConventionScanTests.Chain] = SheetConventionScanTests.chains(of: "Button(", in: source, file: "StartOfYearSheet.swift")
        var index: Int = 0
        for button in buttons {
            if button.arguments.contains("StartOfYearWording.leaveAsItIsButton") {
                leaveAt = index
                leaveChain = button.chain
            }
            if button.arguments.contains("StartOfYearWording.restoreCourseButton") {
                restoreAt = index
                restoreChain = button.chain
            }
            index += 1
        }
        let leave: Int = try XCTUnwrap(leaveAt, "no Leave As It Is button")
        let restore: Int = try XCTUnwrap(restoreAt, "no Restore Course button")
        XCTAssertEqual(restore, leave + 1, "Leave As It Is leads and Restore Course trails, side by side")
        XCTAssertTrue(buttons[leave].arguments.contains("role: .cancel"), leaveChain)
        XCTAssertTrue(leaveChain.contains(".keyboardShortcut(.cancelAction)"), leaveChain)
        XCTAssertTrue(restoreChain.contains(".keyboardShortcut(.defaultAction)"), restoreChain)

        // What each does: the source from each button to the next.
        let leaveStart: Range<String.Index> = try XCTUnwrap(source.range(of: "Button(StartOfYearWording.leaveAsItIsButton"))
        let restoreStart: Range<String.Index> = try XCTUnwrap(source.range(of: "Button(StartOfYearWording.restoreCourseButton"))
        let restoreEnd: Range<String.Index> = try XCTUnwrap(
            source.range(of: "case .undone, .problem:", range: restoreStart.upperBound..<source.endIndex)
        )
        let leaveDoes: String = String(source[leaveStart.upperBound..<restoreStart.lowerBound])
        let restoreDoes: String = String(source[restoreStart.upperBound..<restoreEnd.lowerBound])
        XCTAssertTrue(leaveDoes.contains("dismiss()"), leaveDoes)
        // Leave As It Is changes no file: it only starts again the preview
        // Go stopped (`testLeaveAsItIsStartsThePreviewAgainOnceAndChangesNothing`).
        XCTAssertTrue(leaveDoes.contains("model.leaveAsItIs()"), leaveDoes)
        XCTAssertFalse(leaveDoes.contains("restore"), "Leave As It Is restores nothing: \(leaveDoes)")
        XCTAssertFalse(leaveDoes.contains("Task"), "Leave As It Is changes nothing: \(leaveDoes)")
        // A deploy holds the restore back before the sheet closes.
        let heldAt: Range<String.Index>? = restoreDoes.range(of: "model.restoreCourseIsPressed()")
        let dismissAt: Range<String.Index>? = restoreDoes.range(of: "dismiss()")
        XCTAssertNotNil(heldAt, restoreDoes)
        if let heldAt, let dismissAt {
            XCTAssertTrue(heldAt.lowerBound < dismissAt.lowerBound, "asked before the sheet closes: \(restoreDoes)")
        }
        XCTAssertTrue(restoreDoes.contains("dismiss()"), restoreDoes)
        XCTAssertTrue(restoreDoes.contains("await model.restoreCourse(from: stopped)"), restoreDoes)
        XCTAssertFalse(buttons[restore].arguments.contains("role:"), "Restore Course is not destructive and not a cancel: \(restoreChain)")
    }

    /// The sidebar hands the sheet the restore Restore from Backup… runs,
    /// not a second one.
    func testTheSidebarHandsTheSheetTheOneRestore() throws {
        let views: URL = TextFieldStyleScanTests.viewsURL()
        let source: String = try String(contentsOf: views.appendingPathComponent("SidebarView.swift"), encoding: .utf8)
        guard let sheet = source.range(of: "StartOfYearSheet(model: StartOfYearSheetModel(") else {
            return XCTFail("the sidebar no longer opens the sheet this way")
        }
        let after: String = String(source[sheet.upperBound...].prefix(600))
        XCTAssertTrue(after.contains("restoreWholeCourse:"), after)
        XCTAssertTrue(after.contains("await workspace.restoreBackup(item)"), after)
    }

    // MARK: - Helpers

    /// A course laid out as the contract's plain year, a window's model on
    /// it, and the sheet's model wired to the REAL whole-course restore, as
    /// the sidebar wires it.
    struct Stopped {

        // MARK: - Stored properties

        let root: URL
        let course: Course
        let workspace: WorkspaceModel
        let model: StartOfYearSheetModel
        let urls: [String: URL]
        let planned: [String]
        let door: [String: Int]

        // MARK: - Functions

        /// Press Go with the door of the contract's "then restore" case.
        @MainActor
        func goAhead() async throws {
            let heldOpen: Int? = door["fileInUseAtSwap"]
            let cannotPutBack: Int? = door["putBackFailsAt"]
            UndoKillPoints.fileInUseAtSwap = { (index: Int) -> Bool in
                return index == heldOpen
            }
            UndoKillPoints.putBackFailsAt = { (index: Int) -> Bool in
                return index == cannotPutBack
            }
            await model.goAhead()
            UndoKillPoints.fileInUseAtSwap = nil
            UndoKillPoints.putBackFailsAt = nil
            guard case .stoppedPartWay = model.stage else {
                XCTFail("no offer: \(model.stage)")
                return
            }
        }

        /// Every page the plan put into draft is published again: the
        /// course is the backup's.
        func assertEveryPlannedPageIsBackAsItWas() throws {
            for title in planned {
                let url: URL = try XCTUnwrap(urls[title])
                let text: String = try String(contentsOf: url, encoding: .utf8)
                XCTAssertNotEqual(PageVisibilityReader.answer(in: text, forSection: 1), .hidden, "\(title) is still in draft")
            }
        }
    }

    func stopPartWay(sections: [Int]) async throws -> Stopped {
        let rules: [String: Any] = try StartOfYearTests.rules("startOfYear")
        let cases: [[String: Any]] = try XCTUnwrap(rules["stoppedPartWayCases"] as? [[String: Any]])
        var door: [String: Int]? = nil
        for testCase in cases where (testCase["then"] as? String) == "restoreCourse" {
            door = testCase["door"] as? [String: Int]
        }
        let plainYear: [String: Any] = try XCTUnwrap((rules["cases"] as? [[String: Any]])?.first)
        let layout: [[String: Any]] = try XCTUnwrap(plainYear["pages"] as? [[String: Any]])
        let planned: [String] = try XCTUnwrap(plainYear["expectDraft"] as? [String])
        let made = try AssistFixture.makeRunner(surface: .mcp)
        let urls: [String: URL] = try StartOfYearTests.layOut(layout, in: made.course)
        var course: Course = made.course
        if sections.count > 1 {
            let configURL: URL = made.course.configFileURL
            var config: [String: Any] = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
            )
            config["section_numbers"] = sections
            config["num_sections"] = sections.count
            try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]).write(to: configURL)
            for section in sections {
                try FileManager.default.createDirectory(
                    at: made.course.sectionDirectoryURL(forSection: section).appendingPathComponent("All Classes"),
                    withIntermediateDirectories: true
                )
            }
            course = try made.course.asSavedNow()
        }
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: made.root)
        workspace.reloadCourses()
        let model: StartOfYearSheetModel = StartOfYearSheetModel(
            course: course, sectionNumber: 1, workspaceURL: made.root, mode: .getReady,
            restoreWholeCourse: { (item: BackupItem) async in
                await workspace.restoreBackup(item)
            }
        )
        model.load()
        guard case .ready = model.stage else {
            _ = try XCTUnwrap(Optional<Int>.none, "no plan: \(model.stage)")
            throw CancellationError()
        }
        return Stopped(
            root: made.root, course: course, workspace: workspace, model: model,
            urls: urls, planned: planned, door: try XCTUnwrap(door)
        )
    }

    static func count(_ event: String, in events: [String]) -> Int {
        var found: Int = 0
        for each in events where each == event {
            found += 1
        }
        return found
    }

    /// Every regular file under `root`, by standardized path, with its bytes.
    static func everyFile(under root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values: URLResourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files[url.standardizedFileURL.path] = try Data(contentsOf: url)
            }
        }
        return files
    }
}
