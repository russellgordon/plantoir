import XCTest
@testable import QuartzTeachers

/// The U3 sweep's findings 2 to 5, fixed in U4a (#899):
///
/// 2. The `undo could not record a step` line said "The change went ahead"
///    before a write that could still refuse: it is now written from what
///    happened.
/// 3. With the switch off, a daily action whose page is a link was refused,
///    not written over the link; since Russell's ruling of 2026-11-25
///    (U4b2-1) it is written through the link and the link stays a link
///    (`undo.rule.shadow`).
/// 4. Duplicate Class's copy refused, its room then refused too: the reply
///    said a blank page was waiting on that day.
/// 5. Sentences that were in Swift alone are `undo.wording`'s.
@MainActor
final class UndoSweepFindingsTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = FileManager.default.temporaryDirectory

    var previousTrail: ProblemReportStore = ActivityTrail.store

    var previousHook: ((String, String, Int?, UndoUnrecordedChange, String) -> Void)?

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        previousHook = UndoTrailHook.couldNotRecordLine
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-sweep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        UndoTrailHook.couldNotRecordLine = previousHook
        JournaledStep.modeOverride = nil
        UndoJournalLocation.folderOverride = nil
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Findings 2 and 3

    /// Russell's ruling on #899, 2026-11-25: with the switch off, a page
    /// that is a link is written THROUGH the link, and the link stays a
    /// link, on both platforms (Windows'
    /// `WithTheSwitchOffALinkedPageIsWrittenThroughItsLinkAndStaysALink`).
    /// Run for a link to a file inside the course and for one to a file
    /// outside the working folder, as U4a's Save of a linked settings file
    /// is. Inside, the step is recorded at the file the link leads to and no
    /// trail line is written; outside, it cannot be named in a step and its
    /// one line says the change went ahead. Never "nothing was changed".
    /// MUST FAIL with the plan made at the link's own place (U3's rule: the
    /// Publish was refused and the page stayed a draft).
    func testAShadowStepOnALinkWritesThroughTheLinkAndTheLinkStaysALink() throws {
        JournaledStep.modeOverride = .shadow
        for outside in [false, true] {
            UndoJournalLocation.folderOverride = root.appendingPathComponent("undo-\(outside)", isDirectory: true)
            let made = try linkedPage(outside: outside)
            defer {
                try? FileManager.default.removeItem(at: made.outsideFolder)
            }
            var said: [UndoUnrecordedChange] = []
            UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
                said.append(change)
            }
            let step: JournaledStep = step(for: made.course)
            step.write(published, to: made.link)
            XCTAssertEqual(step.readText(made.link), published, "the plan does not read the link as it will be, outside: \(outside)")

            XCTAssertNoThrow(try step.make(), "the linked page was refused, outside: \(outside)")

            XCTAssertEqual(said, outside ? [.wentAhead] : [], "outside: \(outside)")
            XCTAssertEqual(try String(contentsOf: made.target, encoding: .utf8), published, "outside: \(outside)")
            XCTAssertEqual(
                try FileManager.default.destinationOfSymbolicLink(atPath: made.link.path), made.target.path,
                "the link is not still a link to the same file, outside: \(outside)"
            )
            try FileManager.default.removeItem(at: made.course.deletingLastPathComponent())
        }
    }

    /// The same, stopped part way (the U3 stop seam: the second page in use
    /// at its swap, and the linked page cannot be put back): the linked
    /// page's file holds the new content, the link is still a link, and what
    /// the file held is kept BESIDE THE FILE THE LINK LEADS TO, as Windows
    /// keeps it (`APlainWriteLeftPartWayIsSaidAsPartWayAndNamesTheKeptFile`,
    /// through a link). MUST FAIL with the plan made at the link's own place.
    func testAShadowStepOnALinkStoppedPartWayKeepsTheFileBesideTheFileTheLinkLeadsTo() throws {
        JournaledStep.modeOverride = .shadow
        defer {
            UndoKillPoints.fileInUseAtSwap = nil
            UndoKillPoints.putBackFailsAt = nil
        }
        for outside in [false, true] {
            UndoJournalLocation.folderOverride = root.appendingPathComponent("undo-\(outside)", isDirectory: true)
            let made = try linkedPage(outside: outside)
            defer {
                try? FileManager.default.removeItem(at: made.outsideFolder)
            }
            let second: URL = made.course.appendingPathComponent("Unit 1, Day 2.md")
            try Data(draft.utf8).write(to: second)
            let step: JournaledStep = step(for: made.course)
            step.write(published, to: made.link)
            step.write(published, to: second)
            UndoKillPoints.fileInUseAtSwap = { index in index == 1 }
            UndoKillPoints.putBackFailsAt = { index in index == 0 }
            var kept: [String] = []
            XCTAssertThrowsError(try step.make()) { error in
                guard case JournaledStepError.leftPartWay(_, _, let keptOriginals) = error else {
                    return XCTFail("not refused part way, outside: \(outside): \(error)")
                }
                kept = keptOriginals
            }
            UndoKillPoints.fileInUseAtSwap = nil
            UndoKillPoints.putBackFailsAt = nil

            XCTAssertEqual(kept.count, 1, "outside: \(outside)")
            let keptURL: URL = made.target.deletingLastPathComponent().appendingPathComponent(kept.first ?? "?")
            XCTAssertEqual(try? String(contentsOf: keptURL, encoding: .utf8), draft, "not kept beside the linked file, outside: \(outside)")
            XCTAssertEqual(try String(contentsOf: made.target, encoding: .utf8), published, "outside: \(outside)")
            XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), draft, "outside: \(outside)")
            XCTAssertEqual(
                try FileManager.default.destinationOfSymbolicLink(atPath: made.link.path), made.target.path,
                "the link is not still a link to the same file, outside: \(outside)"
            )
            try FileManager.default.removeItem(at: made.course.deletingLastPathComponent())
        }
    }

    /// A link to a FOLDER is still refused before anything changes, with
    /// the existing sentence (`cannotTellNow`), and its line says nothing
    /// was changed. MUST FAIL with the folder refusal dropped.
    func testAShadowStepOnALinkToAFolderIsStillRefusedBeforeAnythingChanges() throws {
        JournaledStep.modeOverride = .shadow
        UndoJournalLocation.folderOverride = root.appendingPathComponent("undo", isDirectory: true)
        let course: URL = root.appendingPathComponent("courses/ICS3U", isDirectory: true)
        let folder: URL = course.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link: URL = course.appendingPathComponent("Unit 1, Day 1.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        var said: [UndoUnrecordedChange] = []
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            said.append(change)
        }
        let step: JournaledStep = step(for: course)
        step.write(published, to: link)

        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.refused(.cannotTellNow, _) = error else {
                return XCTFail("not refused as cannot tell now: \(error)")
            }
        }

        XCTAssertEqual(said, [.nothingWasChanged])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), folder.path)
    }

    /// A link to a file that cannot be read is still refused before
    /// anything changes, with the existing sentence (`cannotTellNow`).
    func testAShadowStepOnALinkToAFileThatCannotBeReadIsStillRefused() throws {
        JournaledStep.modeOverride = .shadow
        UndoJournalLocation.folderOverride = root.appendingPathComponent("undo", isDirectory: true)
        let course: URL = root.appendingPathComponent("courses/ICS3U", isDirectory: true)
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        let target: URL = course.appendingPathComponent("locked.md")
        try Data(draft.utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: target.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        }
        let link: URL = course.appendingPathComponent("Unit 1, Day 1.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        var said: [UndoUnrecordedChange] = []
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            said.append(change)
        }
        let step: JournaledStep = step(for: course)
        step.write(published, to: link)

        XCTAssertThrowsError(try step.make()) { error in
            guard case JournaledStepError.refused(.cannotTellNow, _) = error else {
                return XCTFail("not refused as cannot tell now: \(error)")
            }
        }

        XCTAssertEqual(said, [.nothingWasChanged])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), draft)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
    }

    /// The line a step that cannot be named and is refused says.
    func testTheLineForARefusedStepSaysNothingWasChanged() {
        XCTAssertTrue(
            UndoTrail.couldNotRecordLine(action: "publishPages", course: "ICS3U", section: 1, change: .nothingWasChanged, why: "x")
                .hasSuffix(" Nothing was changed.")
        )
    }

    /// A step the list cannot take that is still made in shadow says it
    /// went ahead, once it has.
    func testAShadowStepTheListCannotTakeSaysItWentAheadOnceItHas() throws {
        JournaledStep.modeOverride = .shadow
        let broken: URL = root.appendingPathComponent("list-is-a-file")
        try Data("not a folder".utf8).write(to: broken)
        UndoJournalLocation.folderOverride = broken.appendingPathComponent("undo", isDirectory: true)
        let course: URL = root.appendingPathComponent("courses/ICS3U", isDirectory: true)
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        let page: URL = course.appendingPathComponent("a.md")
        try Data("one\n".utf8).write(to: page)
        let moved: URL = course.appendingPathComponent("b.md")
        var said: [UndoUnrecordedChange] = []
        UndoTrailHook.couldNotRecordLine = { _, _, _, change, _ in
            said.append(change)
        }
        let step: JournaledStep = JournaledStep(
            courseCode: "ICS3U", courseDirectory: course, section: 1, maker: UndoStepMaker.sheet("publishPages")
        )
        step.move(page, to: moved)

        try step.make()

        XCTAssertEqual(said, [.wentAhead])
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "one\n")
    }

    // MARK: - Finding 4

    /// A copy that cannot be made certainly hidden, and a room that then
    /// cannot be made either (live, the list cannot be written): the reply
    /// says nothing was changed, never that a blank page is waiting. MUST
    /// FAIL before the fix (`try?`): it said the blank page was waiting.
    func testACopyRefusedWhoseRoomCannotBeMadeSaysNothingWasChanged() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(surface: .local)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try "---\ntitle: Unit 1, Day 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\ntags:\n\t- lesson\n---\n\nThe lesson.\n"
            .write(to: AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course), atomically: true, encoding: .utf8)
        try DuplicateAsNextClassTests.rememberTimetable(["2026-09-08", "2026-09-10", "2026-09-14"], in: made.course)
        let before: [String: Data] = UndoActionStepsTests.pages(of: made.course)
        JournaledStep.modeOverride = .live
        let broken: URL = root.appendingPathComponent("list-is-a-file")
        try Data("not a folder".utf8).write(to: broken)
        UndoJournalLocation.folderOverride = broken.appendingPathComponent("undo", isDirectory: true)

        let outcome: AssistToolOutcome = await AssistFixture.run(
            "add_next_class", with: ["duplicate": "Unit 1, Day 1"], on: made.runner
        )

        XCTAssertTrue(outcome.summary.hasPrefix("Nothing was changed"), outcome.summary)
        XCTAssertFalse(outcome.summary.contains("is waiting on that day"), outcome.summary)
        XCTAssertEqual(UndoActionStepsTests.pages(of: made.course), before)
    }

    // MARK: - Finding 5

    /// Each sentence is the contract's, placeholders and all. MUST FAIL with
    /// any one of them changed in Swift.
    func testTheUndoLinesSentencesAreTheContracts() throws {
        let rules: [String: Any] = try UndoContractReplay.contract("shared-rules.json")
        let undo: [String: Any] = try XCTUnwrap(rules["undo"] as? [String: Any])
        var wording: [String: String] = [:]
        for (key, value) in try XCTUnwrap(undo["wording"] as? [String: Any]) where key != "note" {
            wording[key] = value as? String
        }
        let ours: [String: String] = [
            "keptBesideIt": JournaledStepError.keptSentence(place: "{place}", kept: "{kept}"),
            "classDatesRememberedTitle": SectionTimetableStore.Problem.rememberedTitle("{code}", 0)
                .replacingOccurrences(of: "Section 0", with: "Section {number}"),
            "classDatesKeptLead": SectionTimetableStore.Problem.keptLead,
            "classDatesKeptBesideIt": SectionTimetableStore.Problem.keptSentence(place: "{place}", kept: "{kept}"),
            "rolloverNothingElseWasChanged": AssistToolRunner.RolloverStoppedAfterARecordMoved.nothingElseWasChanged("{said}"),
            "rolloverRecordStillMoved": AssistToolRunner.RolloverStoppedAfterARecordMoved.recordStillMoved(legacy: "{legacy}", place: "{place}"),
            "rolloverLeftoverStillMoved": AssistToolRunner.RolloverStoppedAfterARecordMoved.leftoverStillMoved(legacy: "{legacy}", place: "{place}"),
            "rolloverUnreadableStillMoved": AssistToolRunner.RolloverStoppedAfterARecordMoved.unreadableStillMoved(current: "{current}", aside: "{aside}"),
            "renameFolderNothingWasChanged": SpecialFolderRenamer.nothingWasChanged(renaming: "{old}", said: "{said}"),
            "renameFolderStoppedPartWay": SpecialFolderRenamer.stoppedPartWay(renaming: "{old}", said: "{said}"),
            "renameFolderRenamedOnlyInPart": SpecialFolderRenamer.renamedOnlyInPart(renaming: "{old}", to: "{new}", places: ["{places}"], said: "{said}")
                .replacingOccurrences(of: "“{places}”", with: "{places}"),
        ]
        XCTAssertEqual(ours, wording)
    }

    // MARK: - Functions

    var draft: String {
        return "---\npublish: false\n---\n"
    }

    var published: String {
        return "---\npublish: true\n---\n"
    }

    func step(for course: URL) -> JournaledStep {
        return JournaledStep(
            courseCode: "ICS3U", courseDirectory: course, section: 1, maker: UndoStepMaker.sheet("publishPages")
        )
    }

    /// A course with a page that is a link: to a file in a folder inside
    /// the course, or to one in a folder outside the working folder.
    func linkedPage(outside: Bool) throws -> (course: URL, link: URL, target: URL, outsideFolder: URL) {
        let course: URL = root.appendingPathComponent("courses/ICS3U", isDirectory: true)
        let outsideFolder: URL = root.deletingLastPathComponent()
            .appendingPathComponent("undo-sweep-outside-\(UUID().uuidString)", isDirectory: true)
        let folder: URL = outside ? outsideFolder : course.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: course, withIntermediateDirectories: true)
        let target: URL = folder.appendingPathComponent("real.md")
        try Data(draft.utf8).write(to: target)
        let link: URL = course.appendingPathComponent("Unit 1, Day 1.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return (course: course, link: link, target: target, outsideFolder: outsideFolder)
    }
}
