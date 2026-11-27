import XCTest
@testable import QuartzTeachers

/// #899 (Russell's ruling of 2026-11-26): a one-file settings step that
/// stopped part way is judged AT ONCE by content, with recovery's own check,
/// and closed: the file holding the new value closes it as made, the old
/// value as put back; a file the check cannot read leaves it in flight and
/// the caller offers Put It Back. Every test runs the door LIVE.
@MainActor
final class UndoStoppedStepTests: XCTestCase {

    // MARK: - Stored properties

    var listFolder: URL = FileManager.default.temporaryDirectory

    var root: URL = FileManager.default.temporaryDirectory

    var previousTrail: ProblemReportStore = ActivityTrail.store

    let day: CalendarDay = CalendarDay(text: "2026-11-20")!

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
        let unique: String = UUID().uuidString
        listFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-stopped-list-\(unique)", isDirectory: true)
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-stopped-\(unique)", isDirectory: true)
        UndoJournalLocation.folderOverride = listFolder
        JournaledStep.modeOverride = .live
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent(".trail"))
    }

    override func tearDown() async throws {
        UndoJournalLocation.folderOverride = nil
        JournaledStep.modeOverride = nil
        UndoKillPoints.hook = nil
        UndoKillPoints.beforeTheRename = nil
        UndoKillPoints.putBackFailsAt = nil
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: listFolder)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    func journal() -> UndoJournal {
        return UndoJournal(folderURL: listFolder)
    }

    /// The gesture script's course, filed under 2026–2027 first (a step of
    /// its own, so the step under test is step 2).
    func courseIn2026() throws -> Course {
        let course: Course = try CourseSettingsGestureScript.makeCourse(in: root)
        XCTAssertNil(SetSchoolYearSheet.write(2026, to: course, on: day))
        return course
    }

    func yearOnDisk(_ course: Course) throws -> Int? {
        let data: Data = try Data(contentsOf: course.configFileURL)
        let settings: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return settings["reference_school_year"] as? Int
    }

    func inFlightCount() throws -> Int {
        return try journal().read().inFlight.count
    }

    /// Makes the swap of the settings file stop part way while this process
    /// runs on: another program edits the file in place as the new content
    /// goes in, and the put-back fails, so the door gets `notPutBack` with
    /// the file holding the whole new value. `unreadable` also leaves the
    /// file unreadable once it is in, so the check cannot judge it.
    func stopTheSwapPartWay(unreadable: Bool) {
        UndoKillPoints.beforeTheRename = { _, place in
            let kept: Data = (try? Data(contentsOf: place)) ?? Data()
            var edited: Data = kept
            edited.append(contentsOf: Array(" ".utf8))
            try? edited.write(to: place)
            if unreadable {
                let parent: URL = place.deletingLastPathComponent()
                let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
                for name in names where name.hasSuffix("-new") {
                    chmod(parent.appendingPathComponent(name).path, 0o000)
                }
            }
        }
        UndoKillPoints.putBackFailsAt = { _ in true }
    }

    func clearTheStop() {
        UndoKillPoints.beforeTheRename = nil
        UndoKillPoints.putBackFailsAt = nil
    }

    // MARK: - The door, at every stop point

    /// Killed at each stop point the door has for a one-file `editJSON`
    /// step, then judged at once while this process runs: the file holding
    /// the new value is closed as made and offered by Undo; the old value
    /// as put back, offered by nothing; nothing in flight either way, and
    /// the next change is not refused. MUST FAIL without `judgeAtOnce`.
    func testAStepStoppedAtEveryPointIsJudgedAtOnceByContent() throws {
        let points: [(point: UndoKillPoint, holdsNew: Bool)] = [
            (point: .afterBegin, holdsNew: false),
            (point: .beforeSwap(0), holdsNew: false),
            (point: .beforeApplied, holdsNew: true),
        ]
        for entry in points {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: listFolder)
            let course: Course = try courseIn2026()
            let stopAt: UndoKillPoint = entry.point
            UndoKillPoints.hook = { point in point == stopAt }
            XCTAssertNotNil(SetSchoolYearSheet.write(2027, to: course, on: day), "\(stopAt): not stopped")
            UndoKillPoints.hook = nil
            XCTAssertEqual(try inFlightCount(), 1, "\(stopAt)")

            let verdict: UndoStoppedStepVerdict = UndoStoppedStep.judgeAtOnce(seq: 2, in: journal())

            XCTAssertEqual(try inFlightCount(), 0, "\(stopAt): left in flight")
            XCTAssertFalse(UndoContractReplay.staysBeside(root), "\(stopAt): a leftover copy stayed")
            if entry.holdsNew {
                XCTAssertEqual(verdict, .finished(seq: 2), "\(stopAt)")
                XCTAssertEqual(try yearOnDisk(course), 2027)
                XCTAssertEqual(try journal().read().records[2]?.phase, .done)
            } else {
                XCTAssertEqual(verdict, .putBack, "\(stopAt)")
                XCTAssertEqual(try yearOnDisk(course), 2026)
                XCTAssertNotEqual(try journal().read().records[2]?.phase, .done)
            }
            try course.configuration.reloadFromDisk(url: course.configFileURL)
            XCTAssertNil(SetSchoolYearSheet.write(2025, to: course, on: day), "\(stopAt): the next change was refused")
        }
    }

    /// A file the check cannot read is left in flight, and the door says
    /// so with the step's number to offer Put It Back.
    func testAStepWhoseFileCannotBeReadIsLeftInFlightForTheOffer() throws {
        let course: Course = try courseIn2026()
        UndoKillPoints.hook = { point in point == .beforeApplied }
        XCTAssertNotNil(SetSchoolYearSheet.write(2027, to: course, on: day))
        UndoKillPoints.hook = nil
        chmod(course.configFileURL.path, 0o000)

        let verdict: UndoStoppedStepVerdict = UndoStoppedStep.judgeAtOnce(seq: 2, in: journal())

        chmod(course.configFileURL.path, 0o644)
        XCTAssertEqual(verdict, .couldNotFinish(seq: 2))
        XCTAssertEqual(try inFlightCount(), 1)
    }

    // MARK: - Set School Year

    /// Stopped part way with the file holding 2027–2028 whole: the sheet
    /// closes as on success and nothing is said; nothing in flight; Undo
    /// then puts 2026–2027 back as one step. MUST FAIL before #899 (the
    /// sheet said "could not be saved" and the step stayed in flight).
    func testSetSchoolYearStoppedWithTheNewYearSavesAndSaysNothing() throws {
        let course: Course = try courseIn2026()
        stopTheSwapPartWay(unreadable: false)

        let result: SettingWriteResult = SetSchoolYearSheet.writeJudged(2027, to: course, on: day)

        clearTheStop()
        XCTAssertEqual(result, .saved)
        XCTAssertEqual(try yearOnDisk(course), 2027)
        XCTAssertEqual(try inFlightCount(), 0)
        XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .undone(seq: 2))
        XCTAssertEqual(try yearOnDisk(course), 2026)
    }

    /// Stopped part way with the file unreadable: the offer, with exactly
    /// the ruled words; Put It Back writes 2026–2027 back, closes the step,
    /// and the next change is not refused. MUST FAIL before #899.
    func testSetSchoolYearThatCannotFinishOffersPutItBack() throws {
        let course: Course = try courseIn2026()
        stopTheSwapPartWay(unreadable: true)

        let result: SettingWriteResult = SetSchoolYearSheet.writeJudged(2027, to: course, on: day)

        clearTheStop()
        chmod(course.configFileURL.path, 0o644)
        XCTAssertEqual(result, .couldNotFinish(seq: 2))
        XCTAssertEqual(try inFlightCount(), 1)
        XCTAssertEqual(ReferenceWording.settingCouldNotBeChanged(setting: "school year"), "The school year could not be changed.")
        XCTAssertEqual(ReferenceWording.settingCanBePutBack(value: SchoolYear.label(forStartingYear: 2026)), "Plantoir can put it back to 2026\u{2013}2027.")

        let offer: SettingPutBackOffer = SettingPutBackOffer(seq: 2, setting: "school year", valueBefore: "2026\u{2013}2027")
        XCTAssertNil(SetSchoolYearSheet.putBack(offer, course: course))

        XCTAssertEqual(try yearOnDisk(course), 2026)
        XCTAssertEqual(try inFlightCount(), 0)
        XCTAssertNil(SetSchoolYearSheet.write(2025, to: course, on: day), "the next change was refused")
    }

    /// Not Now leaves the step in flight, as today: recovery settles it at
    /// the next launch.
    func testNotNowLeavesTheStepForRecovery() throws {
        let course: Course = try courseIn2026()
        stopTheSwapPartWay(unreadable: true)
        let result: SettingWriteResult = SetSchoolYearSheet.writeJudged(2027, to: course, on: day)
        clearTheStop()
        chmod(course.configFileURL.path, 0o644)
        XCTAssertEqual(result, .couldNotFinish(seq: 2))
        XCTAssertEqual(try inFlightCount(), 1)
    }

    // MARK: - Contract

    /// The ruled words, run from the JSON.
    func testTheOfferSaysTheContractsWords() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let data: Data = try Data(contentsOf: url)
        let text: String = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"settingCouldNotBeChanged\": \"" + ReferenceWording.settingCouldNotBeChanged(setting: "{setting}") + "\""))
        XCTAssertTrue(text.contains("\"settingCanBePutBack\": \"" + ReferenceWording.settingCanBePutBack(value: "{value}") + "\""))
        XCTAssertTrue(text.contains("\"settingCouldNotBeChangedButtons\": [\"" + ReferenceWording.notNowButton + "\", \"" + ReferenceWording.putItBackButton + "\"]"))
    }
}
