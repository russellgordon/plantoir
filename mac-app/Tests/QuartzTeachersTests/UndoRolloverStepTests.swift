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
        UndoKillPoints.putBackFailsAt = nil
        UndoKillPoints.fileInUseAtSwap = nil
        DeployCommand.bringInDiesAfterWriting = nil
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

    /// Where the LEGACY Netlify marker lives: in the built output.
    func legacyURL(_ made: AssistFixture.Made) -> URL {
        return DeployCommand.legacyMarkerURL(forSection: 1, in: made.course)
    }

    /// A section whose ONLY website record is the legacy one, in the built
    /// output, as an older folder never deployed since has it.
    func sectionWithOnlyTheLegacyRecord() throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try section(surface: .menu)
        try FileManager.default.removeItem(at: made.root.appendingPathComponent(UndoRolloverStepTests.markerPath))
        try FileManager.default.createDirectory(at: legacyURL(made).deletingLastPathComponent(), withIntermediateDirectories: true)
        try UndoRolloverStepTests.lastYear.write(to: legacyURL(made), atomically: true, encoding: .utf8)
        return made
    }

    /// The site a deploy of Section 1 to Netlify would go to: deploy.py's
    /// `load_netlify_marker`, read for read (`scripts/deploy.py`): the
    /// current record when there is one that reads, otherwise the legacy
    /// one in the built output, otherwise none (a new website).
    func siteADeployReads(_ made: AssistFixture.Made) -> String? {
        let current: URL = made.root.appendingPathComponent(UndoRolloverStepTests.markerPath)
        for url in [current, legacyURL(made)] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if url == current {
                    continue
                }
                return nil
            }
            return object["site_id"] as? String
        }
        return nil
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
        // Redo re-dates and leaves BOTH website records alone (Russell's
        // ruling of 2026-11-20): the new one in its place, last year's kept.
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.thisYear)
        XCTAssertEqual(keptMarkers(in: made).count, 1, "Redo left last year's kept record alone")
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

    // MARK: - The legacy record (Russell's ruling of 2026-11-20)

    /// A folder whose only website record is the legacy one in the built
    /// output: it is brought into the working folder first, as a deploy
    /// would, so the step names it as a `moveApart`; Undo puts it back
    /// whole, and a deploy then goes to the SAME site, not a new one. MUST
    /// FAIL with the legacy marker moved aside outside the step (an Undo
    /// left it aside, and the next deploy made a new website).
    func testALegacyRecordAloneIsRolledOverUndoneAndDeploysToTheSameSite() async throws {
        let made: AssistFixture.Made = try sectionWithOnlyTheLegacyRecord()
        XCTAssertEqual(siteADeployReads(made), "last-year")
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        var apart: [String] = []
        for op in try journal().read().records[1]?.step.ops ?? [] where op.knownKind == .moveApart {
            apart.append(op.from ?? "")
        }
        XCTAssertEqual(apart, [UndoRolloverStepTests.markerPath], said.summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(made).path))
        XCTAssertNil(siteADeployReads(made), "a deploy now would start the new website")

        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in made.root }), .undone(seq: 1, leftApart: []))
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.lastYear)
        XCTAssertEqual(keptMarkers(in: made), [])
        XCTAssertEqual(siteADeployReads(made), "last-year", "after Undo a deploy goes to last year's site")
    }

    /// A process that dies after the legacy record was brought in and
    /// before the step went in leaves a folder a deploy still reads
    /// correctly: the record in its current place, the legacy one gone.
    /// MUST FAIL with the legacy marker moved aside outside the step (the
    /// deploy found no record and would have made a new website).
    func testACrashBetweenBringingInTheLegacyRecordAndTheStepLeavesAFolderADeployReads() async throws {
        let made: AssistFixture.Made = try sectionWithOnlyTheLegacyRecord()
        UndoKillPoints.hook = { point in point == .afterBegin }
        _ = await rollOver(made, surface: .menu)
        UndoKillPoints.hook = nil
        await UndoRecovery.recoverAndRederive(journal(processIsAlive: false), resolveRoot: { _ in made.root })
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.lastYear)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(made).path))
        XCTAssertEqual(siteADeployReads(made), "last-year")
    }

    /// A migration that died between its write and its removal leaves both
    /// records, the same bytes: the rollover finishes it (the legacy one
    /// removed) and goes on. MUST FAIL with the both-there case refused.
    func testALegacyRecordBesideTheSameCurrentOneIsFinishedAndTheRolloverGoesOn() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        try FileManager.default.createDirectory(at: legacyURL(made).deletingLastPathComponent(), withIntermediateDirectories: true)
        try UndoRolloverStepTests.lastYear.write(to: legacyURL(made), atomically: true, encoding: .utf8)
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        XCTAssertFalse(said.summary.hasPrefix("Nothing was changed"), said.summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(made).path))
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in made.root }), .undone(seq: 1, leftApart: []))
        XCTAssertEqual(siteADeployReads(made), "last-year")
    }

    /// A legacy record that cannot be brought in (its folder will not let
    /// it go) refuses the rollover before anything is changed, and says so
    /// truly; the current record this wrote is removed again. MUST FAIL
    /// with the conversion's refusal ignored.
    func testALegacyRecordThatCannotBeBroughtInRefusesTheRolloverBeforeAnythingChanges() async throws {
        let held: AssistFixture.Made = try sectionWithOnlyTheLegacyRecord()
        let folder: URL = legacyURL(held).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        let saidHeld: AssistToolOutcome = await rollOver(held, surface: .menu)
        XCTAssertTrue(saidHeld.summary.hasPrefix("Nothing was changed: the website record"), saidHeld.summary)
        XCTAssertNil(text(UndoRolloverStepTests.markerPath, in: held), "the current record written was removed again")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL(held).path))
        XCTAssertEqual(siteADeployReads(held), "last-year")
    }

    // MARK: - A stale leftover beside the current record (Russell, 2026-11-20 evening)

    /// Where a stale leftover is brought in: `.netlify_sites`, beside the
    /// current record, where a deploy never reads it.
    static let leftoverPath: String = "courses/ICS3U/.netlify_sites/section1.from-built-output.json"

    static let leftover: String = "{\"site_id\": \"a-stale-leftover\"}"

    /// A section on a Netlify website (its current record) with a DIFFERENT
    /// old-format leftover in the built output.
    func sectionWithADifferentLeftover() throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try section(surface: .menu)
        try FileManager.default.createDirectory(at: legacyURL(made).deletingLastPathComponent(), withIntermediateDirectories: true)
        try UndoRolloverStepTests.leftover.write(to: legacyURL(made), atomically: true, encoding: .utf8)
        return made
    }

    /// The kept copies of the leftover, by name.
    func keptLeftovers(in made: AssistFixture.Made) -> [String] {
        let folder: URL = made.course.directoryURL.appendingPathComponent(".netlify_sites")
        let entries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var kept: [String] = []
        for entry in entries where entry.hasPrefix("section1.from-built-output.previous-") {
            kept.append(entry)
        }
        return kept
    }

    /// Russell's ruling: a current record and a DIFFERENT leftover never
    /// refuse. The rollover goes on; the leftover is gone from the built
    /// output (a later deploy cannot migrate it back in) and set aside in
    /// the rollover's own step, a `moveApart` beside the current record's.
    /// Undo puts both back byte for byte (the leftover where the step found
    /// it, beside the current record); Redo sets both aside again. MUST FAIL
    /// with the refusal of the fix round.
    func testADifferentLeftoverIsSetAsideInTheStepAndUndoPutsBothBack() async throws {
        let made: AssistFixture.Made = try sectionWithADifferentLeftover()
        let pageBefore: String? = text(UndoRolloverStepTests.pagePath, in: made)
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        XCTAssertFalse(said.summary.hasPrefix("Nothing was changed"), said.summary)
        XCTAssertNotEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(made).path), "gone from the built output")
        XCTAssertNil(text(UndoRolloverStepTests.leftoverPath, in: made))
        XCTAssertNil(siteADeployReads(made), "a deploy now starts the new website")
        XCTAssertEqual(keptMarkers(in: made).count, 1)
        XCTAssertEqual(keptLeftovers(in: made).count, 1)
        var apart: [String] = []
        for op in try journal().read().records[1]?.step.ops ?? [] where op.knownKind == .moveApart {
            apart.append(op.from ?? "")
        }
        XCTAssertEqual(Set(apart), [UndoRolloverStepTests.markerPath, UndoRolloverStepTests.leftoverPath])

        let list: UndoJournal = journal()
        XCTAssertEqual(list.undoNewest(resolveRoot: { _ in made.root }), .undone(seq: 1, leftApart: []))
        XCTAssertEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore)
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.lastYear)
        XCTAssertEqual(text(UndoRolloverStepTests.leftoverPath, in: made), UndoRolloverStepTests.leftover)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(made).path))
        XCTAssertEqual(siteADeployReads(made), "last-year")

        XCTAssertEqual(list.redoNewest(resolveRoot: { _ in made.root }), .redone(seq: 1, leftApart: []))
        XCTAssertNotEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore)
        XCTAssertNil(text(UndoRolloverStepTests.markerPath, in: made))
        XCTAssertNil(text(UndoRolloverStepTests.leftoverPath, in: made))
        XCTAssertEqual(keptLeftovers(in: made).count, 1)
        XCTAssertFalse(UndoContractReplay.staysBeside(made.root))
    }

    /// A kill at each point, settled by recovery: after the leftover was
    /// brought in and before the step began, between the step's swaps, and
    /// after its last swap. Each leaves a folder a deploy reads correctly,
    /// the leftover never back in the built output. MUST FAIL with the
    /// refusal of the fix round (nothing brought in, no step to settle).
    func testADifferentLeftoverKilledAtEachPointIsSettledByRecovery() async throws {
        let points: [UndoKillPoint] = [.afterBegin, .beforeSwap(2), .beforeApplied]
        for point in points {
            freshList()
            let made: AssistFixture.Made = try sectionWithADifferentLeftover()
            UndoKillPoints.hook = { reached in reached == point }
            _ = await rollOver(made, surface: .menu)
            UndoKillPoints.hook = nil
            let later: UndoJournal = journal(processIsAlive: false)
            await UndoRecovery.recoverAndRederive(later, resolveRoot: { _ in made.root })
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL(made).path), "\(point)")
            XCTAssertFalse(UndoContractReplay.staysBeside(made.root), "\(point)")
            if point == .beforeApplied {
                XCTAssertEqual(try later.read().records[1]?.phase, .done, "\(point)")
                XCTAssertNil(siteADeployReads(made), "\(point): whole in its new year")
                XCTAssertEqual(keptLeftovers(in: made).count, 1, "\(point)")
            } else {
                // Nothing swapped yet closes `failed`; a swap made, `rolledBack`.
                let settled: UndoStepPhase = point == .afterBegin ? .failed : .rolledBack
                XCTAssertEqual(try later.read().records[1]?.phase, settled, "\(point)")
                XCTAssertEqual(siteADeployReads(made), "last-year", "\(point): whole in its old year")
                XCTAssertEqual(text(UndoRolloverStepTests.leftoverPath, in: made), UndoRolloverStepTests.leftover, "\(point)")
            }
        }
    }

    /// A step refused after the legacy record was brought in: the record
    /// is put back where it was, so "Nothing was changed" is true. MUST FAIL
    /// with no put-back (the record left in its current place while the
    /// reply said nothing was changed).
    func testARefusedStepPutsTheBroughtInRecordBackSoNothingWasChanged() async throws {
        let made: AssistFixture.Made = try sectionWithOnlyTheLegacyRecord()
        UndoKillPoints.fileInUseAtSwap = { index in index == 0 }
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        UndoKillPoints.fileInUseAtSwap = nil
        XCTAssertTrue(said.summary.hasPrefix("Nothing was changed"), said.summary)
        XCTAssertEqual(try String(contentsOf: legacyURL(made), encoding: .utf8), UndoRolloverStepTests.lastYear)
        XCTAssertNil(text(UndoRolloverStepTests.markerPath, in: made))

        let different: AssistFixture.Made = try sectionWithADifferentLeftover()
        UndoKillPoints.fileInUseAtSwap = { index in index == 0 }
        let saidDifferent: AssistToolOutcome = await rollOver(different, surface: .menu)
        UndoKillPoints.fileInUseAtSwap = nil
        XCTAssertTrue(saidDifferent.summary.hasPrefix("Nothing was changed"), saidDifferent.summary)
        XCTAssertEqual(try String(contentsOf: legacyURL(different), encoding: .utf8), UndoRolloverStepTests.leftover)
        XCTAssertNil(text(UndoRolloverStepTests.leftoverPath, in: different))
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: different), UndoRolloverStepTests.lastYear)
    }

    /// A refused step whose brought-in record cannot be put back (its old
    /// folder will no longer take it) never says "Nothing was changed": it
    /// says what moved, and that it names the same website. MUST FAIL with
    /// the plain "Nothing was changed".
    func testARefusedStepThatCannotPutTheRecordBackSaysWhatMoved() async throws {
        let made: AssistFixture.Made = try sectionWithOnlyTheLegacyRecord()
        let folder: URL = legacyURL(made).deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        }
        UndoKillPoints.fileInUseAtSwap = { index in
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
            return index == 0
        }
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        UndoKillPoints.fileInUseAtSwap = nil
        XCTAssertFalse(said.summary.hasPrefix("Nothing was changed"), said.summary)
        XCTAssertTrue(said.summary.hasPrefix("Nothing else was changed"), said.summary)
        XCTAssertTrue(said.summary.contains(".netlify_sites/section1.json"), said.summary)
        XCTAssertTrue(said.summary.contains("where a deploy reads it"), said.summary)
        XCTAssertEqual(siteADeployReads(made), "last-year")

        // A stale leftover that cannot go back: no deploy reads where it is.
        let different: AssistFixture.Made = try sectionWithADifferentLeftover()
        let differentFolder: URL = legacyURL(different).deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: differentFolder.path)
        }
        UndoKillPoints.fileInUseAtSwap = { index in
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: differentFolder.path)
            return index == 0
        }
        let saidDifferent: AssistToolOutcome = await rollOver(different, surface: .menu)
        UndoKillPoints.fileInUseAtSwap = nil
        XCTAssertTrue(saidDifferent.summary.hasPrefix("Nothing else was changed"), saidDifferent.summary)
        XCTAssertTrue(saidDifferent.summary.contains("section1.from-built-output.json”, where no deploy reads it"), saidDifferent.summary)
        XCTAssertEqual(siteADeployReads(different), "last-year")
    }

    // MARK: - Records as a group (the director's decision of 2026-11-20)

    /// Two hosts: a deploy reaches Netlify and not Cloudflare. Undo leaves
    /// BOTH records apart, never Cloudflare's back and Netlify's not, and
    /// takes the rest back. MUST FAIL without the group rule (Cloudflare's
    /// record went back, the section split across two websites).
    func testRecordsOnTwoHostsStayApartTogetherWhenOnlyOneWasDeployed() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let cloudflare: String = "courses/ICS3U/.cloudflare_sites/section1.json"
        try FileManager.default.createDirectory(
            at: made.root.appendingPathComponent(cloudflare).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "{\"project\": \"ics3u-s1-2025\"}".write(to: made.root.appendingPathComponent(cloudflare), atomically: true, encoding: .utf8)
        let pageBefore: String? = text(UndoRolloverStepTests.pagePath, in: made)
        _ = await rollOver(made, surface: .menu)
        XCTAssertNil(text(cloudflare, in: made))
        try UndoRolloverStepTests.thisYear.write(to: made.root.appendingPathComponent(UndoRolloverStepTests.markerPath), atomically: true, encoding: .utf8)

        XCTAssertEqual(
            journal().undoNewest(resolveRoot: { _ in made.root }),
            .undone(seq: 1, leftApart: [UndoRolloverStepTests.markerPath, cloudflare])
        )
        XCTAssertEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore)
        XCTAssertNil(text(cloudflare, in: made), "Cloudflare's record stays apart with Netlify's")
        let keptCloudflare: [String] = RollOverFromTheMenuSafetyTests.keptMarkers(
            in: made.course.directoryURL.appendingPathComponent(".cloudflare_sites")
        )
        XCTAssertEqual(keptCloudflare.count, 1)
    }

    // MARK: - The review's lows

    /// A step refused PART WAY (a file could not be put back after the
    /// schedule's removal was refused) is never tried again, and is said as
    /// part way, never "Nothing was changed". MUST FAIL with `notPutBack`
    /// read as a plain refusal (the rollover retried, a second step begun).
    func testAStepLeftPartWayIsNeverTriedAgainAndIsSaidAsPartWay() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let label: String = try scheduleADeploy(in: made, at: Date().addingTimeInterval(7 * 86_400))
        let agents: URL = ScheduledDeploy.plistURL(label: label).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: agents.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agents.path)
        }
        UndoKillPoints.putBackFailsAt = { index in index == 0 }
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        UndoKillPoints.putBackFailsAt = nil
        XCTAssertTrue(said.summary.hasPrefix("Only part of"), said.summary)
        XCTAssertFalse(said.summary.contains("Nothing was changed"), said.summary)
        XCTAssertEqual(try journal().read().records.count, 1, "never tried a second time")
    }

    /// A plist that does not say its moment (older jobs) is never set again:
    /// its calendar entry has no year. One whose moment is ahead is. MUST
    /// FAIL with an unknown moment read as ahead.
    func testADeployForLaterThatDoesNotSayItsMomentIsNeverSetAgain() throws {
        let places: UndoScheduledDeploys = UndoScheduledDeploys(runner: FakeLaunchControl())
        let target: String = UndoScheduledDeploys.target(label: ScheduledDeploy.labelPrefix + "undo-test")
        let older: [String: Any] = ["Label": "x", "StartCalendarInterval": ["Month": 9, "Day": 8, "Hour": 7, "Minute": 0]]
        let olderPlist: Data = try PropertyListSerialization.data(fromPropertyList: older, format: .xml, options: 0)
        XCTAssertFalse(places.canSet(target, .object(["plist": .string(olderPlist.base64EncodedString())])))
        let ahead: [String: Any] = [
            "Label": "x",
            "EnvironmentVariables": [ScheduledDeploy.scheduledForKey: ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400))],
        ]
        let aheadPlist: Data = try PropertyListSerialization.data(fromPropertyList: ahead, format: .xml, options: 0)
        XCTAssertTrue(places.canSet(target, .object(["plist": .string(aheadPlist.base64EncodedString())])))
    }

    /// launchd refuses the job at Undo: the schedule is left as it is and
    /// named as left apart, and the rest of the rollover is taken back, so
    /// the step never blocks the list. MUST FAIL with the refusal refusing
    /// the whole Undo (`couldNotWrite`).
    func testUndoLeavesADeployForLaterThatLaunchdRefusesApartAndTakesBackTheRest() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let label: String = try scheduleADeploy(in: made, at: Date().addingTimeInterval(7 * 86_400))
        let pageBefore: String? = text(UndoRolloverStepTests.pagePath, in: made)
        _ = await rollOver(made, surface: .menu)
        let launchd: FakeLaunchControl = FakeLaunchControl()
        launchd.bootstrapFailure = "Bootstrap failed: 5: Input/output error"
        let places: UndoAppPlaces = UndoAppPlaces(schedules: UndoScheduledDeploys(runner: launchd))
        XCTAssertEqual(
            journal().undoNewest(resolveRoot: { _ in made.root }, places: places),
            .undone(seq: 1, leftApart: [UndoScheduledDeploys.target(label: label)])
        )
        XCTAssertEqual(text(UndoRolloverStepTests.pagePath, in: made), pageBefore)
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.lastYear)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ScheduledDeploy.plistURL(label: label).path))
    }

    /// A refused swap removes the folder it made for a move (the record's
    /// kept folder, `published-pages.previous-<stamp>/`), and never a folder
    /// that was there before. MUST FAIL with the folders left.
    func testARefusedSwapRemovesTheFolderItMadeForAMove() throws {
        let root: URL = listFolder.appendingPathComponent("work", isDirectory: true)
        let state: URL = root.appendingPathComponent(".publish_state", isDirectory: true)
        let fragment: URL = state.appendingPathComponent("section1.published-pages/a.json")
        try FileManager.default.createDirectory(at: fragment.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: fragment)
        let kept: URL = state.appendingPathComponent("section1.published-pages.previous-2026-11-20_120000/a.json")
        let page: URL = root.appendingPathComponent("page.md")
        try Data("changed by hand\n".utf8).write(to: page)
        let move: UndoOp = UndoOp.moveFile(from: fragment.path, to: kept.path, sha: UndoHash.sha256(of: Data("{}".utf8)))
        let targets: [UndoSwapTarget] = [
            UndoSwapTarget(url: kept, relativePath: "kept", change: .moveHere(from: fragment, fromPath: "fragment", op: move)),
            UndoSwapTarget(url: page, relativePath: "page.md", expected: Data("as planned\n".utf8), replacement: Data("new\n".utf8)),
        ]
        XCTAssertEqual(UndoSwap.swap(targets, label: "test"), .refused(.changedSince(firstPath: "page.md", others: 0)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fragment.path), "the move was reversed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.deletingLastPathComponent().path), "the kept folder it made is gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.path), "a folder that was there before stays")
    }

    // MARK: - The re-review's lows

    /// A bring-in that dies part way through writing the record leaves no
    /// partial record where a deploy reads one; the next rollover brings the
    /// GOOD legacy record in, never setting it aside as stale beside a
    /// partial one. MUST FAIL with the record written in place.
    func testABringInKilledMidWriteLeavesNoPartialRecord() async throws {
        let made: AssistFixture.Made = try sectionWithOnlyTheLegacyRecord()
        DeployCommand.bringInDiesAfterWriting = { written in
            try? Data("{\"site_id\": \"la".utf8).write(to: written)
            return true
        }
        _ = await rollOver(made, surface: .menu)
        DeployCommand.bringInDiesAfterWriting = nil
        XCTAssertNil(text(UndoRolloverStepTests.markerPath, in: made), "no partial record where a deploy reads one")
        XCTAssertEqual(siteADeployReads(made), "last-year")

        _ = await rollOver(made, surface: .menu)
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in made.root }), .undone(seq: 1, leftApart: []))
        XCTAssertEqual(text(UndoRolloverStepTests.markerPath, in: made), UndoRolloverStepTests.lastYear)
        XCTAssertNil(text(UndoRolloverStepTests.leftoverPath, in: made), "the good record was never taken for a stale one")
        let entries: [String] = (try? FileManager.default.contentsOfDirectory(
            atPath: made.course.directoryURL.appendingPathComponent(".netlify_sites").path
        )) ?? []
        for entry in entries {
            XCTAssertFalse(entry.contains(".bringing-in-"), entry)
        }
    }

    /// A bring-in refused after it made `.netlify_sites` (the record could
    /// not be written whole) leaves no current record and no folder it
    /// made. MUST FAIL with the refusal leaving them.
    func testARefusedBringInLeavesNoRecordAndNoFolderItMade() async throws {
        let made: AssistFixture.Made = try sectionWithOnlyTheLegacyRecord()
        let folder: URL = made.course.directoryURL.appendingPathComponent(".netlify_sites")
        try FileManager.default.removeItem(at: folder)
        DeployCommand.bringInDiesAfterWriting = { written in
            try? FileManager.default.removeItem(at: written)
            return true
        }
        let said: AssistToolOutcome = await rollOver(made, surface: .menu)
        DeployCommand.bringInDiesAfterWriting = nil
        XCTAssertTrue(said.summary.hasPrefix("Nothing was changed: the website record"), said.summary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "the folder it made is gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL(made).path))
    }

    /// launchd refuses the job at Undo and its plist cannot be taken away
    /// again: it stays in LaunchAgents and loads at the next login, so the
    /// Undo never names it as left apart. MUST FAIL with the removal's
    /// failure ignored (named left apart while the plist is there).
    func testAScheduleWhosePlistCannotBeTakenAwayAgainIsNotSaidToBeLeftApart() async throws {
        let made: AssistFixture.Made = try section(surface: .menu)
        let label: String = try scheduleADeploy(in: made, at: Date().addingTimeInterval(7 * 86_400))
        _ = await rollOver(made, surface: .menu)
        let agents: URL = ScheduledDeploy.plistURL(label: label).deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agents.path)
        }
        let launchd: FakeLaunchControl = FakeLaunchControl()
        launchd.bootstrapFailure = "Bootstrap failed: 5: Input/output error"
        launchd.onBootstrap = { _ in
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: agents.path)
        }
        let places: UndoAppPlaces = UndoAppPlaces(schedules: UndoScheduledDeploys(runner: launchd))
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in made.root }, places: places), .undone(seq: 1, leftApart: []))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ScheduledDeploy.plistURL(label: label).path))
    }
}
