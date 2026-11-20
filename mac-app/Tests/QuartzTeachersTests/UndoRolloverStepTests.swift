import XCTest
@testable import QuartzTeachers

/// U3b of #899: Roll Over to a New Year is ONE step through the door, from
/// the menu and from the assistant: the re-dated pages, the published-pages
/// record set aside, the website's markers moved aside (`moveApart`), and a
/// deploy set for later turned off (`external`, `scheduledDeploy:`).
///
/// - Russell's ruling of 2026-11-19 on Q3 (#959 in the journal's terms):
///   after a deploy has filled the place a marker left, Undo takes back the
///   rest, leaves both markers where they are, says which (`leftApart`), and
///   the step leaves the undo side, so an earlier step can still be undone.
/// - #897 piece B, seam 2: undoing it registers the deploy set for later
///   again while its moment is ahead, and otherwise leaves it off and says so.
/// - A step killed part way is whole in its old year or whole in its new
///   one once recovery has run, and the step's closing line says which.
///
/// Every test runs the door LIVE (`JournaledStep.modeOverride`), as U7 will.
@MainActor
final class UndoRolloverStepTests: XCTestCase {

    // MARK: - Stored properties

    var listFolder: URL = FileManager.default.temporaryDirectory

    var previousTrail: ProblemReportStore = ActivityTrail.store

    static let markerPath: String = "courses/ICS3U/.netlify_sites/section1.json"

    static let pagePath: String = "courses/ICS3U/section1/All Classes/Unit 1, Day 1.md"

    static let fragmentPath: String = "courses/ICS3U/.publish_state/section1.published-pages/20260601T120000Z-netlify.json"

    static let lastYear: String = "{\"site_id\": \"last-year\"}"

    static let thisYear: String = "{\"site_id\": \"this-year\"}"

    // MARK: - Setting up

    /// Every list folder a test used, removed when it ends.
    var listFolders: [URL] = []

    /// Points the list at an empty folder of its own.
    func freshList() {
        listFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-rollover-\(UUID().uuidString)", isDirectory: true)
        listFolders.append(listFolder)
        UndoJournalLocation.folderOverride = listFolder
    }

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        freshList()
        JournaledStep.modeOverride = .live
        UndoContractReplay.registerTheFrontPageMaintainer()
    }

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        JournaledStep.modeOverride = nil
        UndoKillPoints.hook = nil
        ActivityTrail.store = previousTrail
        for folder in listFolders {
            try? FileManager.default.removeItem(at: folder)
        }
        listFolders = []
        SectionMenuActivity.reset()
    }

    // MARK: - The fixture

    /// A section needing re-dating, on a Netlify website (its marker), with
    /// last year's published-pages record and links checklist answered, and
    /// the copy of the course saved first.
    func section(surface: AssistToolRunner.Surface) throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: surface, for: self)
        // The fixture's own class dates are a step of their own: the list
        // starts empty after it, so the rollover's step is the first.
        freshList()
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        _ = RollOverFromTheMenuTests.countCopies(of: made)
        try UndoRolloverStepTests.lastYear.write(to: made.root.appendingPathComponent(UndoRolloverStepTests.markerPath), atomically: true, encoding: .utf8)
        try RollOverFromTheMenuTests.writePublishedRecord(in: made.course)
        try "{\"offered\": [], \"leftUnticked\": []}\n".write(
            to: LinksChecklistAnswered.fileURL(courseDirectory: made.course.directoryURL, section: 1),
            atomically: true, encoding: .utf8
        )
        return made
    }

    /// Rolls the section over onto a new website, from the surface the
    /// fixture was made for.
    func rollOver(_ made: AssistFixture.Made, surface: AssistToolRunner.Surface) async -> AssistToolOutcome {
        if surface == .menu {
            return await made.runner.run(
                call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
            )
        }
        return await AssistFixture.run("re_date_classes", with: ["rollover": "yes", "website": "new"], on: made.runner)
    }

    /// A deploy for later, set for `moment`, in this working folder, with
    /// its wrapper script: its label.
    func scheduleADeploy(in made: AssistFixture.Made, at moment: Date) throws -> String {
        let label: String = ScheduledDeploy.agentLabel(courseCode: "ICS3U", sectionNumber: 1, workingFolder: made.root)
        let plist: [String: Any] = [
            "Label": label,
            "WorkingDirectory": made.root.path,
            "ProgramArguments": [
                "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
                ScheduledDeploy.runFlag,
                ScheduledDeploy.scriptURL(label: label).path,
                ScheduledDeploy.sectionFlag,
                made.root.path,
                "ICS3U",
                "1",
            ],
            "EnvironmentVariables": [ScheduledDeploy.scheduledForKey: ISO8601DateFormatter().string(from: moment)],
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: ScheduledDeploy.plistURL(label: label))
        let script: URL = ScheduledDeploy.scriptURL(label: label)
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/bash\necho deploy\n".write(to: script, atomically: true, encoding: .utf8)
        return label
    }

    func text(_ path: String, in made: AssistFixture.Made) -> String? {
        return try? String(contentsOf: made.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The kept copies of Section 1's marker, by name.
    func keptMarkers(in made: AssistFixture.Made) -> [String] {
        return RollOverFromTheMenuSafetyTests.keptMarkers(in: made.course.directoryURL.appendingPathComponent(".netlify_sites"))
    }

    /// The fragments set aside, in any kept folder of the record.
    func fragmentsSetAside(in made: AssistFixture.Made) -> Int {
        let folder: URL = made.course.directoryURL.appendingPathComponent(".publish_state")
        var count: Int = 0
        let entries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for entry in entries where entry.hasPrefix("section1.published-pages.previous-") {
            let inside: [String] = (try? FileManager.default.contentsOfDirectory(
                atPath: folder.appendingPathComponent(entry).path
            )) ?? []
            count += inside.count
        }
        return count
    }

    func journal(processIsAlive: Bool = true) -> UndoJournal {
        if processIsAlive {
            return UndoJournal(folderURL: listFolder)
        }
        return UndoJournal(folderURL: listFolder, processIsAlive: { _ in false })
    }

    // MARK: - One step

    /// From the menu: ONE step on the list, closed applied, named rollOver,
    /// holding the re-dated page, the record's removal and its fragment's
    /// move, and the marker's `moveApart`. MUST FAIL before U3b, which left
    /// the re-date as one step and wrote the rest outside the door.
    func testARolloverFromTheMenuIsOneStep() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        let fold: UndoFold = try journal().read()
        XCTAssertEqual(fold.records.count, 1, said.summary)
        let record: UndoStepRecord = try XCTUnwrap(fold.records[1])
        XCTAssertEqual(record.phase, .done)
        XCTAssertEqual(record.step.action?.key, "rollOver")
        XCTAssertEqual(record.step.madeBy, "menu")
        var kinds: Set<String> = []
        var apart: [String] = []
        for op in record.step.ops {
            kinds.insert(op.kind)
            if op.knownKind == .moveApart {
                apart.append(op.from ?? "")
            }
        }
        XCTAssertTrue(kinds.isSuperset(of: ["move", "moveApart", "writeFile"]), "\(kinds)")
        XCTAssertEqual(apart, [UndoRolloverStepTests.markerPath])
        XCTAssertNil(text(UndoRolloverStepTests.markerPath, in: made))
        XCTAssertEqual(keptMarkers(in: made).count, 1)
        XCTAssertEqual(fragmentsSetAside(in: made), 1)
    }

    /// From the window too: one step, while today's in-memory undo keeps its
    /// two entries (the re-date and the website), as before.
    func testARolloverFromTheWindowIsOneStepAndTodaysUndoKeepsItsTwoEntries() async throws {
        let made: AssistFixture.Made = try section(surface: .local)
        let depth: Int = made.runner.changeCount
        let said: AssistToolOutcome = await rollOver(made, surface: .local)
        let fold: UndoFold = try journal().read()
        XCTAssertEqual(fold.records.count, 1, said.summary)
        XCTAssertEqual(fold.records[1]?.step.action?.key, "rollOver")
        XCTAssertEqual(made.runner.changeCount - depth, 2, said.summary)
        XCTAssertTrue(said.summary.contains(AssistWording.rolloverStartedANewWebsite(keptAs: "").prefix(20)), said.summary)
    }

    // MARK: - Q3: a deploy, then Undo

    /// Russell's ruling of 2026-11-19 on Q3: a rollover onto a new website,
    /// a deploy (a new marker in the emptied place, a new fragment), then
    /// Undo. The dates and the record come back, both markers stay, the
    /// marker is named as left apart, and the step moves to the redo side,
    /// so the step before it can be undone next. MUST FAIL with the markers
    /// recorded as plain `move` ops (refused changedSince, the list cleared:
    /// #959 in the journal).
    func testAnUndoAfterADeployTakesBackTheRestAndLeavesBothMarkers() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let earlier: JournaledStep = JournaledStep(course: made.course, section: 1, maker: UndoStepMaker.sheet("earlierStep"))
        earlier.write("An earlier change.\n", to: made.course.directoryURL.appendingPathComponent("notes.md"))
        try earlier.make()
        let pageBefore: String? = text(UndoRolloverStepTests.pagePath, in: made)
        let fragmentBefore: String? = text(UndoRolloverStepTests.fragmentPath, in: made)

        _ = await rollOver(made, surface: .menu)
        XCTAssertNotEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore)

        // The deploy: a new marker where the old one was, a new fragment.
        try UndoRolloverStepTests.thisYear.write(to: made.root.appendingPathComponent(UndoRolloverStepTests.markerPath), atomically: true, encoding: .utf8)
        let newFragment: String = "courses/ICS3U/.publish_state/section1.published-pages/20260910T120000Z-netlify.json"
        try "{\"places\": []}".write(to: made.root.appendingPathComponent(newFragment), atomically: true, encoding: .utf8)

        let list: UndoJournal = journal()
        let undone: UndoOutcome = list.undoNewest(resolveRoot: { _ in made.root })
        XCTAssertEqual(undone, .undone(seq: 2, leftApart: [UndoRolloverStepTests.markerPath]))
        XCTAssertEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore, "the dates came back")
        XCTAssertEqual(text(UndoRolloverStepTests.fragmentPath, in: made), fragmentBefore, "the record came back")
        XCTAssertNotNil(text("courses/ICS3U/.publish_state/section1.links-checklist-answered.json", in: made))
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.thisYear, "the new website's marker is left")
        XCTAssertEqual(keptMarkers(in: made).count, 1, "last year's kept marker is left")
        XCTAssertNotNil(text(newFragment, in: made), "the deploy's fragment is never touched")

        let offer: UndoOffer = try list.offer()
        XCTAssertEqual(offer.head?.step.seq, 1, "the step before the rollover is the one Undo offers now")
        XCTAssertEqual(offer.redoCandidate?.step.seq, 2)
        XCTAssertEqual(list.undoNewest(resolveRoot: { _ in made.root }), .undone(seq: 1))
        XCTAssertNil(text("courses/ICS3U/notes.md", in: made))

        // And Redo, both ways up the list: the marker is left apart again.
        XCTAssertEqual(list.redoNewest(resolveRoot: { _ in made.root }), .redone(seq: 1))
        XCTAssertEqual(list.redoNewest(resolveRoot: { _ in made.root }), .redone(seq: 2, leftApart: [UndoRolloverStepTests.markerPath]))
        XCTAssertNotEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore)
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.thisYear)
        XCTAssertFalse(UndoContractReplay.staysBeside(made.root))
    }

    /// With no deploy between, Undo puts the marker back in its place, from
    /// the kept copy (one rename), and leaves nothing apart.
    func testAnUndoWithNoDeployPutsTheMarkerBack() async throws {
        let made: AssistFixture.Made = try section(surface: .local)
        _ = await rollOver(made, surface: .local)
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in made.root }), .undone(seq: 1, leftApart: []))
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.lastYear)
        XCTAssertEqual(keptMarkers(in: made), [])
        XCTAssertEqual(fragmentsSetAside(in: made), 0)
    }

    // MARK: - A deploy set for later (seam 2)

    /// The rollover turns this folder's deploy set for later off inside its
    /// step; Undo registers it again, byte for byte, while its moment is
    /// still ahead.
    func testUndoSetsTheDeployForLaterAgainWhileItsMomentIsAhead() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let label: String = try scheduleADeploy(in: made, at: Date().addingTimeInterval(7 * 86_400))
        let plistURL: URL = ScheduledDeploy.plistURL(label: label)
        let plistBefore: Data = try Data(contentsOf: plistURL)
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        XCTAssertTrue(said.summary.contains(AssistWording.rolloverTurnedOffTheScheduledPublish), said.summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ScheduledDeploy.scriptURL(label: label).path))
        var targets: [String] = []
        for op in try journal().read().records[1]?.step.ops ?? [] where op.knownKind == .external {
            targets.append(op.target ?? "")
        }
        XCTAssertEqual(targets, [UndoScheduledDeploys.target(label: label)])

        let launchd: FakeLaunchControl = FakeLaunchControl()
        let places: UndoAppPlaces = UndoAppPlaces(schedules: UndoScheduledDeploys(runner: launchd))
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in made.root }, places: places), .undone(seq: 1, leftApart: []))
        XCTAssertEqual(try Data(contentsOf: plistURL), plistBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ScheduledDeploy.scriptURL(label: label).path))
        XCTAssertEqual(launchd.bootstrappedURLs, [plistURL])
    }

    /// Its moment gone by: the rest is undone, the deploy for later stays
    /// off, and the Undo names it as left apart. MUST FAIL with `canSet`
    /// left out (the job registered for a moment already past).
    func testADeployForLaterWhoseMomentHasGoneByStaysOffAndIsNamed() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let label: String = try scheduleADeploy(in: made, at: Date().addingTimeInterval(86_400))
        let pageBefore: String? = text(UndoRolloverStepTests.pagePath, in: made)
        _ = await rollOver(made, surface: .menu)
        let launchd: FakeLaunchControl = FakeLaunchControl()
        let later: Date = Date().addingTimeInterval(3 * 86_400)
        let places: UndoAppPlaces = UndoAppPlaces(schedules: UndoScheduledDeploys(runner: launchd, now: { later }))
        XCTAssertEqual(
            journal().undoNewest(resolveRoot: { _ in made.root }, places: places),
            .undone(seq: 1, leftApart: [UndoScheduledDeploys.target(label: label)])
        )
        XCTAssertEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ScheduledDeploy.plistURL(label: label).path))
        XCTAssertEqual(launchd.bootstrappedURLs, [])
    }

    /// A deploy for later that cannot be removed (its folder will not let
    /// the plist go): the rest of the rollover is made, ONE step without
    /// it, and the reply says it could not be turned off, which is true.
    func testADeployForLaterThatCannotBeRemovedIsLeftOutAndSaidSo() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let label: String = try scheduleADeploy(in: made, at: Date().addingTimeInterval(7 * 86_400))
        let agents: URL = ScheduledDeploy.plistURL(label: label).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: agents.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agents.path)
        }
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        XCTAssertTrue(said.summary.contains(AssistWording.rolloverCouldNotTurnOffTheScheduledPublish), said.summary)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ScheduledDeploy.plistURL(label: label).path))
        let fold: UndoFold = try journal().read()
        var applied: [UndoStepRecord] = []
        for (_, record) in fold.records where record.phase == .done {
            applied.append(record)
        }
        XCTAssertEqual(applied.count, 1)
        for op in applied.first?.step.ops ?? [] {
            XCTAssertNotEqual(op.knownKind, .external)
        }
        XCTAssertNil(text(UndoRolloverStepTests.markerPath, in: made), "the rest of the rollover was made")
    }

    // MARK: - Killed part way

    /// Killed between its swaps, live: the reply says nothing was changed,
    /// and recovery, once the process is gone, puts every file back. The
    /// section is whole in its OLD year (the page, the record, the marker),
    /// and the step reads `rolledBack`. MUST FAIL with recovery taken out.
    func testARolloverKilledBetweenItsSwapsIsWholeInItsOldYearAfterRecovery() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let before: [String: Data] = UndoActionStepsTests.pages(of: made.course)
        UndoKillPoints.hook = { point in point == .beforeSwap(2) }
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        UndoKillPoints.hook = nil
        XCTAssertTrue(said.summary.hasPrefix("Nothing was changed"), said.summary)
        XCTAssertNotEqual(UndoActionStepsTests.pages(of: made.course), before, "the kill came before any swap")

        let later: UndoJournal = journal(processIsAlive: false)
        await UndoRecovery.recoverAndRederive(later, resolveRoot: { _ in made.root })
        XCTAssertEqual(UndoActionStepsTests.pages(of: made.course), before, "not whole in its old year")
        XCTAssertFalse(UndoContractReplay.staysBeside(made.root))
        XCTAssertEqual(try later.read().records[1]?.phase, .rolledBack)
    }

    /// Killed after its last swap and before `applied`: recovery completes
    /// it. Whole in its NEW year, and the step reads done.
    func testARolloverKilledAfterItsLastSwapIsWholeInItsNewYearAfterRecovery() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        UndoKillPoints.hook = { point in point == .beforeApplied }
        _ = await rollOver(made, surface: .menu)
        UndoKillPoints.hook = nil
        let left: [String: Data] = UndoActionStepsTests.pages(of: made.course)
        XCTAssertNil(text(UndoRolloverStepTests.markerPath, in: made))

        let later: UndoJournal = journal(processIsAlive: false)
        await UndoRecovery.recoverAndRederive(later, resolveRoot: { _ in made.root })
        XCTAssertEqual(UndoActionStepsTests.pages(of: made.course), left)
        XCTAssertEqual(keptMarkers(in: made).count, 1)
        XCTAssertEqual(fragmentsSetAside(in: made), 1)
        XCTAssertEqual(try later.read().records[1]?.phase, .done)
    }

    // MARK: - In shadow, a list that cannot be written

    /// In shadow, a list that cannot be written changes nothing about the
    /// rollover: the same answer and the same course as with one that can,
    /// made all or none without a record (`makeWithoutARecord`).
    func testInShadowAListThatCannotBeWrittenChangesNothingAboutTheRollover() async throws {
        JournaledStep.modeOverride = .shadow
        let well: AssistFixture.Made = try section(surface: .menu)
        let saidWell: AssistToolOutcome = await rollOver(well, surface: .menu)

        let broken: AssistFixture.Made = try section(surface: .menu)
        let brokenList: URL = listFolder.appendingPathComponent("not-a-folder")
        try FileManager.default.createDirectory(at: listFolder, withIntermediateDirectories: true)
        try Data("a file".utf8).write(to: brokenList)
        UndoJournalLocation.folderOverride = brokenList.appendingPathComponent("undo", isDirectory: true)
        let saidBroken: AssistToolOutcome = await rollOver(broken, surface: .menu)

        XCTAssertEqual(saidBroken.summary, saidWell.summary)
        XCTAssertNil(text(UndoRolloverStepTests.markerPath, in: broken))
        XCTAssertEqual(keptMarkers(in: broken).count, 1)
        XCTAssertEqual(fragmentsSetAside(in: broken), 1)
        XCTAssertFalse(UndoContractReplay.staysBeside(broken.root))
    }
}
