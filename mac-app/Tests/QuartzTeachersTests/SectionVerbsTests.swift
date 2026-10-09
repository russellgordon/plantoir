import XCTest
@testable import QuartzTeachers

/// The assistant's functions run from the Section menu (#457 batch B): the
/// SAME tool code, through `AssistToolRunner.run(call:)`, with a call built in
/// code — so the menu and the assistant cannot disagree about what a change
/// does, the reference-course gate is the tool's own, and the menu's own
/// differences (a copy before every change, named for the menu; pages named
/// by folder) are the only ones.
@MainActor
final class SectionVerbsTests: XCTestCase {

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        SectionMenuActivity.reset()
        SectionSchedulePrompt.shared.stopAsking()
        try await super.tearDown()
    }

    // MARK: - The same code

    /// Publishing a page from the menu leaves the page byte for byte as the
    /// assistant's publish does — and so does hiding it again.
    func testTheMenuWritesWhatTheAssistantWrites() async throws {
        let assistant = try AssistFixture.makeRunner(surface: .local)
        let menu = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: assistant.root)
            try? FileManager.default.removeItem(at: menu.root)
        }
        for made in [assistant, menu] {
            try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One links [[Notes]].", in: made.course)
            try "---\ntitle: Notes\npublish: false\n---\nNotes.\n".write(
                to: made.course.directoryURL.appendingPathComponent("Concepts/Notes.md"), atomically: true, encoding: .utf8
            )
        }
        // The assistant names a page by its title, as a teacher types it; the
        // menu names it by its folder as well (the plan review's finding 3).
        let said: AssistToolOutcome = await assistant.runner.run(call: SectionVerbs.call(
            "publish_pages", ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        let done: AssistToolOutcome = await menu.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: false
        ))
        XCTAssertEqual(said.summary, done.summary)
        XCTAssertEqual(
            try SectionVerbsTests.pages(in: assistant.course), try SectionVerbsTests.pages(in: menu.course),
            "the menu's publish wrote something the assistant's would not"
        )
        let hiddenByTheAssistant: AssistToolOutcome = await assistant.runner.run(call: SectionVerbs.call(
            "unpublish_pages", ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        let hiddenByTheMenu: AssistToolOutcome = await menu.runner.run(call: SectionVerbs.hidePages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: false
        ))
        XCTAssertEqual(hiddenByTheAssistant.summary, hiddenByTheMenu.summary)
        XCTAssertEqual(try SectionVerbsTests.pages(in: assistant.course), try SectionVerbsTests.pages(in: menu.course))
    }

    /// Two pages share a file name — every shipped course has five to nine
    /// `_DUPLICATE ME` pages — and one has a semicolon in its name. By title
    /// alone the first is refused as ambiguous and the second is split in
    /// two; by folder, as the menu sends them, each publishes exactly the
    /// page ticked.
    func testPagesAreNamedByTheirFolder() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let classes: URL = ClassPages.folderURL(forSection: 1, in: made.course)
        let concepts: URL = made.course.directoryURL.appendingPathComponent("Concepts")
        for folder in [classes, concepts] {
            try "---\ntitle: _DUPLICATE ME\npublish: false\n---\nCopy me.\n".write(
                to: folder.appendingPathComponent("_DUPLICATE ME.md"), atomically: true, encoding: .utf8
            )
        }
        try "---\ntitle: Q&A; review\npublish: false\n---\nQuestions.\n".write(
            to: concepts.appendingPathComponent("Q&A; review.md"), atomically: true, encoding: .utf8
        )

        let byTitle: AssistToolOutcome = await made.runner.run(call: SectionVerbs.call(
            "publish_pages", ["course": "ICS3U", "section": 1, "pages": "_DUPLICATE ME"]
        ))
        // Concepts is shared by every section, so a publish there writes
        // the section's own key (file-formats.json → pageVisibility).
        XCTAssertFalse(try String(contentsOf: concepts.appendingPathComponent("_DUPLICATE ME.md"), encoding: .utf8)
            .contains("publishForSection1"), "a bare title fits two pages and must not publish either: \(byTitle.summary)")

        let rows: [SectionVerbSheetModel.PageRow] = SectionVerbSheetModel.rows(
            publishing: true, course: made.course, sectionNumber: 1, workspaceURL: made.root
        )
        var names: [String] = []
        for row in rows where row.title == "_DUPLICATE ME" && row.folder == "Concepts" {
            names.append(row.name)
        }
        for row in rows where row.title == "Q&A; review" {
            names.append(row.name)
        }
        XCTAssertEqual(names, ["Concepts/_DUPLICATE ME", "Concepts/Q&A; review"])
        let byFolder: AssistToolOutcome = await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: names, planning: false
        ))
        XCTAssertTrue(try String(contentsOf: concepts.appendingPathComponent("_DUPLICATE ME.md"), encoding: .utf8)
            .contains("publishForSection1: true"), byFolder.summary)
        XCTAssertTrue(try String(contentsOf: concepts.appendingPathComponent("Q&A; review.md"), encoding: .utf8)
            .contains("publishForSection1: true"), byFolder.summary)
        XCTAssertTrue(try String(contentsOf: classes.appendingPathComponent("_DUPLICATE ME.md"), encoding: .utf8)
            .contains("publish: false"), "the class folder's copy was not ticked")
    }

    // MARK: - The menu's own differences

    /// A copy of the course before EVERY change, named for the menu
    /// (`_menu-section1`), never for the assistant — and listed as the menu's.
    func testEveryChangeFromTheMenuSavesItsOwnCopy() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        try AssistFixture.write(page: "Unit 1, Day 2", publish: "false", date: "2026-09-09", body: "Two.", in: made.course)
        _ = await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: false
        ))
        // No wait between them: two copies in one second take distinct names
        // (`CourseArchiver.unusedBackupName`), never one zip updated twice.
        _ = await made.runner.run(call: SectionVerbs.publishPages(
            course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 2"], planning: false
        ))
        let backups: URL = made.root.appendingPathComponent("courses/_backups/ICS3U")
        var menuCopies: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted() {
            XCTAssertFalse(name.contains("_assistant-section"), "the menu's copy is named for the assistant: \(name)")
            if name.hasSuffix("_menu-section1.zip") {
                menuCopies.append(name)
                let item: BackupItem? = BackupItem.from(fileURL: backups.appendingPathComponent(name), courseCode: "ICS3U")
                XCTAssertEqual(item?.maker, .menu(sectionNumber: 1))
                XCTAssertFalse(item?.subtitle.contains("assistant") ?? true)
            }
        }
        XCTAssertEqual(menuCopies.count, 2, "one copy per change: \(menuCopies)")
    }

    /// Undo Last Change takes back the last change made from the menu, and
    /// says which section it was in.
    func testUndoTakesBackTheMenusLastChange() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        let verbs: SectionVerbs = SectionVerbs(
            folderPath: made.root.path, siteWork: StubSiteWork(),
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! }
        )
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        let before: [String: String] = try SectionVerbsTests.pages(in: made.course)
        XCTAssertFalse(verbs.lastChangeIsIn(courseCode: "ICS3U", sectionNumber: 1))
        _ = await verbs.perform(
            SectionVerbs.publishPages(course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: false),
            item: .publishPages, courseCode: "ICS3U", sectionNumber: 1, counts: "1 page ticked"
        )
        XCTAssertTrue(verbs.lastChangeIsIn(courseCode: "ICS3U", sectionNumber: 1))
        XCTAssertNotEqual(try SectionVerbsTests.pages(in: made.course), before)
        let undone: AssistToolOutcome = await verbs.perform(
            SectionVerbs.undoLastChange(), item: .undoLastChange, courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertTrue(undone.summary.hasPrefix("Undone."), undone.summary)
        XCTAssertEqual(try SectionVerbsTests.pages(in: made.course), before)
        XCTAssertFalse(verbs.lastChangeIsIn(courseCode: "ICS3U", sectionNumber: 1))
    }

    // MARK: - The gate

    /// A course kept for reference: every writing call from the menu is
    /// refused by the tool's own gate, and nothing is written. (A guard that
    /// passes on the old code too — the gate is the runner's, and the menu
    /// reaching it at all is the point.)
    func testTheReferenceGateIsTheTools() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try SectionVerbsTests.layOutClassesWithDates(in: made.course)
        let configURL: URL = made.course.directoryURL.appendingPathComponent("course_config.json")
        var config: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: configURL)) as? [String: Any]
        )
        config["kept_for_reference"] = true
        try JSONSerialization.data(withJSONObject: config).write(to: configURL)
        let before: [String: String] = try SectionVerbsTests.pages(in: made.course)
        let calls: [AssistToolCall] = [
            SectionVerbs.publishPages(course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 2"], planning: false),
            SectionVerbs.hidePages(course: "ICS3U", section: 1, names: ["section1/All Classes/Unit 1, Day 1"], planning: false),
            SectionVerbs.publishClass(course: "ICS3U", section: 1, on: CalendarDay(year: 2026, month: 9, day: 9)!, planning: false),
            SectionVerbs.addNextClass(course: "ICS3U", section: 1),
            SectionVerbs.reDateClasses(course: "ICS3U", section: 1, planning: false),
            SectionVerbs.makeRoom(course: "ICS3U", section: 1, unit: 1, atDay: 2, howMany: 1, planning: false),
        ]
        for call in calls {
            let outcome: AssistToolOutcome = await made.runner.run(call: call)
            XCTAssertEqual(
                outcome.summary, AssistToolRefusal.keptForReference("ICS3U").message, call.function.name
            )
        }
        XCTAssertEqual(try SectionVerbsTests.pages(in: made.course), before, "something was written to a course kept for reference")
    }

    /// While the menu is changing a section, the in-app assistant's change to
    /// the same section is refused before anything is written — the menu's
    /// own claim, never the assistant window's hold (#242).
    func testTheMenusClaimHoldsTheAssistantBack() async throws {
        let made = try AssistFixture.makeRunner(surface: .local)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        let before: [String: String] = try SectionVerbsTests.pages(in: made.course)
        SectionMenuActivity.begin(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        let refused: AssistToolOutcome = await made.runner.run(call: SectionVerbs.call(
            "publish_pages", ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        XCTAssertEqual(refused.summary, AssistWording.sectionIsChangingFromTheMenu(course: "ICS3U", section: "1"))
        XCTAssertEqual(try SectionVerbsTests.pages(in: made.course), before)
        XCTAssertNil(AssistActivity.store.heldBackups, "the menu's claim took the assistant window's hold")
        SectionMenuActivity.end(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        let allowed: AssistToolOutcome = await made.runner.run(call: SectionVerbs.call(
            "publish_pages", ["course": "ICS3U", "section": 1, "pages": "Unit 1, Day 1"]
        ))
        XCTAssertNotEqual(allowed.summary, refused.summary)
    }

    // MARK: - #475 at the other doors

    /// Publish Class for a Date… names the day, so the class it publishes is
    /// recorded as kept: the next Deploy does not undo it.
    func testAClassPublishedByItsDateIsKept() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 2, Day 4", publish: "false", date: "2026-09-09", body: "Next.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 5", publish: "false", date: "2026-09-11", body: "Later.", in: made.course)
        let today: CalendarDay = CalendarDay(year: 2026, month: 9, day: 8)!
        _ = await made.runner.run(call: SectionVerbs.publishClass(
            course: "ICS3U", section: 1, on: CalendarDay(year: 2026, month: 9, day: 11)!, planning: false
        ))
        XCTAssertTrue(try String(contentsOf: AssistFixture.pageURL(of: "Unit 2, Day 5", in: made.course), encoding: .utf8)
            .contains("publish: true"))
        XCTAssertEqual(ClassesDatedLater.flagged(forSection: 1, in: made.course, today: today), [], "the class just published by its date would be asked about")
        let kept: ClassesDatedLater.KeptRecord? = ClassesDatedLater.KeptRecord.read(courseDirectory: made.course.directoryURL, section: 1)
        XCTAssertEqual(kept?.kept, [ClassesDatedLater.Kept(place: "section1/All Classes/Unit 2, Day 5", date: "2026-09-11")])

        // Tomorrow's class leaves no record: it would never be asked about.
        _ = await made.runner.run(call: SectionVerbs.publishClass(
            course: "ICS3U", section: 1, on: CalendarDay(year: 2026, month: 9, day: 9)!, planning: false
        ))
        XCTAssertEqual(
            ClassesDatedLater.KeptRecord.read(courseDirectory: made.course.directoryURL, section: 1)?.kept.count, 1
        )
    }

    /// The in-app assistant with no window showing the section is told, in
    /// the teacher's words, and nothing is stopped or deployed; a class kept
    /// at its date lets the deploy through.
    func testTheAssistantWithNoWindowIsHeldBackUntilItIsAnswered() async throws {
        let made = try AssistFixture.makeRunner(surface: .local)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 2, Day 3", publish: "true", date: "2026-09-08", body: "Today.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 4", publish: "true", date: "2026-09-09", body: "Next.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 5", publish: "true", date: "2026-09-11", body: "Later.", in: made.course)
        let held: AssistToolOutcome = await made.runner.run(call: SectionVerbs.call(
            "deploy_section", ["course": "ICS3U", "section": 1]
        ))
        XCTAssertEqual(held.summary, AssistWording.deployHasClassesDatedLaterAndNoWindow(
            course: "ICS3U", section: "1", pages: "“Unit 2, Day 5”", count: 1
        ))
        XCTAssertEqual(made.siteWork.deploys, 0)
        let today: CalendarDay = CalendarDay(year: 2026, month: 9, day: 8)!
        ClassesDatedLater.keep(ClassesDatedLater.flagged(forSection: 1, in: made.course, today: today), forSection: 1, in: made.course)
        _ = await made.runner.run(call: SectionVerbs.call("deploy_section", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(made.siteWork.deploys, 1, "kept at its date, the class no longer holds the deploy back")
    }

    // MARK: - Helpers

    /// Every page of the course, by path, with its text.
    static func pages(in course: Course) throws -> [String: String] {
        var found: [String: String] = [:]
        let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: course.directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        while let entry = enumerator?.nextObject() as? URL {
            if entry.pathExtension == "md" {
                found[entry.path.replacingOccurrences(of: course.directoryURL.path, with: "")] =
                    try String(contentsOf: entry, encoding: .utf8)
            }
        }
        return found
    }

    /// Unit 1, Days 1 to 3, and class dates from 2026-09-08.
    static func layOutClassesWithDates(in course: Course) throws {
        try MenuVoiceTests.layOutAUnitWithDates(in: course)
    }
}

/// The fixes round of batch B (#457, #475): the director's rulings on the
/// implementation review.
@MainActor
final class SectionVerbsFixesTests: XCTestCase {

    // MARK: - Tests

    /// Finding 1: Keep All records every listed class as kept, so the next
    /// question about the same section asks nothing.
    func testKeepAllAsksOnce() async throws {
        let made = try AssistFixture.makeRunner(surface: .menu)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 2, Day 3", publish: "true", date: "2026-09-08", body: "Today.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 4", publish: "true", date: "2026-09-09", body: "Next.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 5", publish: "true", date: "2026-09-11", body: "Later.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 6", publish: "true", date: "2026-09-14", body: "Later still.", in: made.course)
        let today: CalendarDay = CalendarDay(year: 2026, month: 9, day: 8)!
        let flagged: [ClassesDatedLater.Flagged] = ClassesDatedLater.flagged(forSection: 1, in: made.course, today: today)
        XCTAssertEqual(flagged.count, 2)
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .laterClassesAtDeploy, course: made.course, sectionNumber: 1, title: "", item: nil
        )
        model.ask(about: flagged, nextDay: CalendarDay(year: 2026, month: 9, day: 9))
        XCTAssertEqual(model.laterHidden.count, 2, "every class starts ticked to hide")
        XCTAssertEqual(model.defaultButtonTitle, AssistWording.hideTickedAndDeployButton)
        // What Keep All and Deploy does to the model, then records.
        model.laterTicked = []
        ClassesDatedLater.keep(model.laterKept, forSection: 1, in: made.course)
        XCTAssertEqual(ClassesDatedLater.flagged(forSection: 1, in: made.course, today: today), [], "asked again after Keep All")

        // The window's Keep All runs the same answer with nothing ticked.
        let verbs: String = try DeployAsksAboutLaterClassesTests.body(
            of: "    func keepAllAtDeploy(", in: try DeployAsksAboutLaterClassesTests.source(
                "mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift"
            )
        )
        XCTAssertTrue(verbs.contains("model.laterTicked = []"))
        XCTAssertTrue(verbs.contains("answerAtDeploy(model)"))
        let sheet: String = try DeployAsksAboutLaterClassesTests.source("mac-app/QuartzTeachers/Views/Section/SectionVerbSheet.swift")
        XCTAssertTrue(sheet.contains("Button(AssistWording.keepAllAndDeployButton)"), "Keep All is always beside the default")
    }

    /// Finding 2: a class published from the links checklist is kept at its
    /// date, so the next Deploy does not offer to hide it again.
    func testAClassPublishedFromTheLinksChecklistIsKept() async throws {
        let made = try AssistFixture.makeRunner(surface: .local)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        try AssistFixture.write(page: "Unit 2, Day 4", publish: "true", date: "2026-09-09", body: "Next.", in: made.course)
        try AssistFixture.write(page: "Unit 2, Day 5", publish: "true", date: "2026-09-11", body: "Later.", in: made.course)
        let today: CalendarDay = CalendarDay(year: 2026, month: 9, day: 8)!
        XCTAssertEqual(ClassesDatedLater.flagged(forSection: 1, in: made.course, today: today).count, 1)
        LinksChecklistPublisher.keepTheLaterClassesItPublished(
            [LinksChecklistPublisher.place(of: AssistFixture.pageURL(of: "Unit 2, Day 5", in: made.course), in: made.course)],
            course: made.course, sectionNumber: 1, today: today
        )
        XCTAssertEqual(ClassesDatedLater.flagged(forSection: 1, in: made.course, today: today), [])
        let publisher: String = try DeployAsksAboutLaterClassesTests.body(
            of: "    static func publish(", in: try DeployAsksAboutLaterClassesTests.source(
                "mac-app/QuartzTeachers/Models/LinksChecklist/LinksChecklistPublisher.swift"
            )
        )
        XCTAssertTrue(
            publisher.contains("keepTheLaterClassesItPublished(\n            outcome.publishedPlaces"),
            "Publish in the links checklist keeps what it published"
        )
    }

    /// Note 4: an answer that arrives while something else is up waits for
    /// it, and is shown when it goes — never dropped.
    func testAnAnswerIsNeverDropped() throws {
        XCTAssertEqual(SectionDetailView.whereAnAnswerGoes(ownSheetIsUp: true, somethingIsUp: true), .intoItsOwnSheet)
        XCTAssertEqual(SectionDetailView.whereAnAnswerGoes(ownSheetIsUp: false, somethingIsUp: true), .whenTheWindowIsFree)
        XCTAssertEqual(SectionDetailView.whereAnAnswerGoes(ownSheetIsUp: false, somethingIsUp: false), .now)
        let verbs: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailVerbs.swift"
        ))
        let run: String = try DeployAsksAboutLaterClassesTests.body(of: "    func runAtOnce(", in: verbs)
        XCTAssertFalse(run.contains("NSSound.beep()"), "an answer is never dropped with a beep")
        XCTAssertTrue(run.contains("pendingVerbResult = model"))
        let view: String = DeployAsksAboutLaterClassesTests.codeOnly(try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"
        ))
        // Shown when each thing that can be up has gone: the health alert,
        // the preview alert, the links checklist, the deploy refusal, and the
        // Section menu's own sheet.
        XCTAssertGreaterThanOrEqual(view.components(separatedBy: "showAVerbResultIfWaiting()").count - 1, 4)
        XCTAssertTrue(verbs.contains("showAnythingWaiting()\n        showAVerbResultIfWaiting()"))
    }

    /// Note 7: a context-menu request whose row is no longer selected is
    /// dropped, never run the next time the section is shown.
    func testARequestNotTakenIsDropped() throws {
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.selection = SidebarSelection.section("ICS3U", 1)
        workspace.sectionVerbRequest = SectionVerbRequest(item: .addNextClass, courseCode: "ICS3U", sectionNumber: 1)
        workspace.selection = SidebarSelection.section("ICS3U", 1)
        XCTAssertNotNil(workspace.sectionVerbRequest, "the same row: still waiting for its window")
        workspace.selection = SidebarSelection.section("ICS3U", 2)
        XCTAssertNil(workspace.sectionVerbRequest, "the row was left: the request is dropped")
        workspace.sectionVerbRequest = SectionVerbRequest(item: .publishPages, courseCode: "ICS3U", sectionNumber: 2)
        workspace.selection = nil
        XCTAssertNil(workspace.sectionVerbRequest)
    }

    /// Note 5: two copies in one second take distinct names, and the second
    /// is read as the same moment and the same maker.
    func testTwoCopiesInOneSecondDoNotShareAName() throws {
        let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let first: String = CourseArchiver.unusedBackupName(
            code: "ICS3U", stamp: "2026-08-11_221530", suffix: "_menu-section1", inFolder: folder.path
        )
        XCTAssertEqual(first, "ICS3U_backup_2026-08-11_221530_menu-section1.zip")
        try Data().write(to: folder.appendingPathComponent(first))
        let second: String = CourseArchiver.unusedBackupName(
            code: "ICS3U", stamp: "2026-08-11_221530", suffix: "_menu-section1", inFolder: folder.path
        )
        XCTAssertEqual(second, "ICS3U_backup_2026-08-11_221530-2_menu-section1.zip")
        let read: BackupItem? = BackupItem.from(fileURL: folder.appendingPathComponent(second), courseCode: "ICS3U")
        XCTAssertEqual(read?.maker, .menu(sectionNumber: 1))
        XCTAssertEqual(
            read?.backedUpAt,
            BackupItem.from(fileURL: folder.appendingPathComponent(first), courseCode: "ICS3U")?.backedUpAt
        )
    }

    /// Note 6: Make Room's pages left undone are said in the menu's voice.
    func testMakeRoomsLeftUndoneHasTheMenusVoice() {
        let outcome: ClassChangeOutcome = ClassChangeOutcome(
            message: "x", leftUndoneFromTheMenu: AssistWording.pagesAChangeCouldNotFinishFromTheMenu("“Unit 1, Day 3”", count: 1)
        )
        XCTAssertFalse(MenuVoiceTests.speaksAsAConversation(outcome.leftUndoneFromTheMenu))
        XCTAssertTrue(MenuVoiceTests.speaksAsAConversation(
            AssistWording.pagesAChangeCouldNotFinish("“Unit 1, Day 3”", count: 1)
        ))
    }
}
