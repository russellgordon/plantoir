import SwiftUI
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

    /// What the file holds once a stopped swap has put its new content in.
    enum StoppedWith: String {
        case theNewValue
        case theOldValue
        case aThirdValue
        case halfWritten
        case unreadable
    }

    /// Makes the swap of the settings file stop part way while this process
    /// runs on: another program edits the file in place as the new content
    /// goes in, and the put-back fails, so the door gets `notPutBack`. What
    /// goes in is the whole new value, or (`holding`) the old year, a third
    /// year another program wrote, half the bytes, or an unreadable file.
    func stopTheSwapPartWay(holding: StoppedWith, from oldYear: Int = 2026, to newYear: Int = 2027) {
        UndoKillPoints.beforeTheRename = { _, place in
            let kept: Data = (try? Data(contentsOf: place)) ?? Data()
            var edited: Data = kept
            edited.append(contentsOf: Array(" ".utf8))
            try? edited.write(to: place)
            let parent: URL = place.deletingLastPathComponent()
            let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
            for name in names where name.hasSuffix("-new") {
                let staged: URL = parent.appendingPathComponent(name)
                let text: String = (try? String(contentsOf: staged, encoding: .utf8)) ?? ""
                switch holding {
                case .theNewValue:
                    break
                case .theOldValue:
                    try? Data(text.replacingOccurrences(of: String(newYear), with: String(oldYear)).utf8).write(to: staged)
                case .aThirdValue:
                    try? Data(text.replacingOccurrences(of: String(newYear), with: "2030").utf8).write(to: staged)
                case .halfWritten:
                    let bytes: Data = Data(text.utf8)
                    try? bytes.prefix(bytes.count / 2).write(to: staged)
                case .unreadable:
                    chmod(staged.path, 0o000)
                }
            }
        }
        UndoKillPoints.putBackFailsAt = { _ in true }
    }

    func stopTheSwapPartWay(unreadable: Bool) {
        stopTheSwapPartWay(holding: unreadable ? .unreadable : .theNewValue)
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
            // A fresh course and list for each stop point.
            let unique: String = UUID().uuidString
            listFolder = FileManager.default.temporaryDirectory
                .appendingPathComponent("undo-stopped-list-\(unique)", isDirectory: true)
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("undo-stopped-\(unique)", isDirectory: true)
            UndoJournalLocation.folderOverride = listFolder
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
        // The old value as the picker shows it ("2026\u{2013}27").
        XCTAssertEqual(
            ReferenceWording.settingCanBePutBack(value: SchoolYear.label(forStartingYear: 2026)),
            "Plantoir can put it back to " + SchoolYear.label(forStartingYear: 2026) + "."
        )

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
        XCTAssertTrue(text.contains("\"settingsCanBePutBack\": \"" + ReferenceWording.settingsCanBePutBack + "\""))
    }

    // MARK: - Fix round one: the alert answers the offer it was handed

    /// HIGH 1 of review 1: the alert closing and the button's action may
    /// come in either order; Put It Back acts on the offer the alert was
    /// handed, so the old year is written back in both orders, even after
    /// the sheet's own offer has been cleared.
    func testPutItBackWritesTheOldYearWhicheverOrderTheAlertCloses() throws {
        let course: Course = try courseIn2026()
        for dismissFirst in [true, false] {
            stopTheSwapPartWay(unreadable: true)
            let result: SettingWriteResult = SetSchoolYearSheet.writeJudged(2027, to: course, on: day)
            clearTheStop()
            chmod(course.configFileURL.path, 0o644)
            guard case .couldNotFinish(let seq) = result else {
                return XCTFail("dismissFirst \(dismissFirst): no offer, \(result)")
            }
            let shown: SettingPutBackOffer = SettingPutBackOffer(
                seq: seq, setting: "school year", valueBefore: SchoolYear.label(forStartingYear: 2026)
            )
            let box: OfferBox = OfferBox(shown)
            let binding: Binding<SettingPutBackOffer?> = Binding(
                get: { return box.offer },
                set: { newOffer in box.offer = newOffer }
            )
            let answers: AnswerBox = AnswerBox()
            let alert: SettingPutBackAlert = SettingPutBackAlert(offer: binding) { answer, offer in
                answers.said.append(SetSchoolYearSheet.answer(answer, to: offer, course: course))
            }
            if dismissFirst {
                alert.alertClosed()
                XCTAssertNil(box.offer)
                alert.answered(.putItBack, with: shown)
            } else {
                alert.answered(.putItBack, with: shown)
                alert.alertClosed()
            }
            XCTAssertEqual(answers.said.count, 1, "dismissFirst \(dismissFirst): answered \(answers.said.count) times")
            XCTAssertNil(answers.said.first ?? "not answered", "dismissFirst \(dismissFirst): Put It Back did not work")
            XCTAssertNil(box.offer)
            XCTAssertEqual(try yearOnDisk(course), 2026, "dismissFirst \(dismissFirst)")
            XCTAssertEqual(try inFlightCount(), 0, "dismissFirst \(dismissFirst)")
        }
    }

    /// Closing the alert alone answers nothing: nothing written, the step
    /// left for recovery, as Not Now leaves it.
    func testClosingTheAlertAloneWritesNothing() throws {
        let course: Course = try courseIn2026()
        stopTheSwapPartWay(unreadable: true)
        let result: SettingWriteResult = SetSchoolYearSheet.writeJudged(2027, to: course, on: day)
        clearTheStop()
        chmod(course.configFileURL.path, 0o644)
        XCTAssertEqual(result, .couldNotFinish(seq: 2))
        let box: OfferBox = OfferBox(SettingPutBackOffer(seq: 2, setting: "school year", valueBefore: "2026\u{2013}27"))
        let binding: Binding<SettingPutBackOffer?> = Binding(
            get: { return box.offer },
            set: { newOffer in box.offer = newOffer }
        )
        let answers: AnswerBox = AnswerBox()
        let alert: SettingPutBackAlert = SettingPutBackAlert(offer: binding) { _, _ in
            answers.said.append("answered")
        }
        alert.alertClosed()
        XCTAssertEqual(answers.said.count, 0)
        XCTAssertNil(box.offer)
        XCTAssertEqual(try inFlightCount(), 1)
        XCTAssertNil(SetSchoolYearSheet.answer(.notNow, to: SettingPutBackOffer(seq: 2, setting: "school year", valueBefore: nil), course: course))
        XCTAssertEqual(try inFlightCount(), 1)
    }

    // MARK: - Fix round one: a file holding neither value

    /// MEDIUM 1 of review 1: another program wrote a third year, or the
    /// file is half written, between the swap and the judgement. The door's
    /// own rule for a hand edit closes the step and clears the list; no
    /// offer is made (it could not succeed), nothing is written over what
    /// the file holds, and the teacher reads the save's existing failure
    /// sentence. MUST FAIL with the `.interrupted` branch answered as made
    /// or as an offer.
    func testAStepWhoseFileHoldsNeitherValueIsClosedWithNoOffer() throws {
        for holding in [StoppedWith.aThirdValue, StoppedWith.halfWritten] {
            freshFolders()
            let course: Course = try courseIn2026()
            stopTheSwapPartWay(holding: holding)

            let result: SettingWriteResult = SetSchoolYearSheet.writeJudged(2027, to: course, on: day)

            clearTheStop()
            let onDisk: Data = try Data(contentsOf: course.configFileURL)
            XCTAssertEqual(result, .refused(ReferenceWording.couldNotSetSchoolYear(course: course.displayCode)), "\(holding)")
            XCTAssertEqual(try inFlightCount(), 0, "\(holding): left in flight")
            XCTAssertEqual(journal().undoNewest(resolveRoot: { _ in self.root }), .nothingToUndo, "\(holding): still on the list")
            XCTAssertEqual(try Data(contentsOf: course.configFileURL), onDisk, "\(holding): written over")
            if holding == .aThirdValue {
                XCTAssertEqual(try yearOnDisk(course), 2030)
            }
        }
    }

    /// The same judged directly: `.notMade`, never an offer.
    func testJudgedDirectlyAThirdValueIsNotMade() throws {
        let course: Course = try courseIn2026()
        UndoKillPoints.hook = { point in point == .beforeApplied }
        XCTAssertNotNil(SetSchoolYearSheet.write(2027, to: course, on: day))
        UndoKillPoints.hook = nil
        let text: String = try String(contentsOf: course.configFileURL, encoding: .utf8)
        try Data(text.replacingOccurrences(of: "2027", with: "2030").utf8).write(to: course.configFileURL)

        XCTAssertEqual(UndoStoppedStep.judgeAtOnce(seq: 2, in: journal()), .notMade)

        XCTAssertEqual(try inFlightCount(), 0)
        XCTAssertEqual(try yearOnDisk(course), 2030)
    }

    // MARK: - Fix round one: a step already closed, a lock not got

    /// LOW 1 of review 1: a step already closed without the change (here
    /// put back by an earlier judgement) is not offered and nothing is
    /// written. MUST FAIL with that branch answered as made or as an offer.
    func testAStepAlreadyClosedIsNotOffered() throws {
        let course: Course = try courseIn2026()
        UndoKillPoints.hook = { point in point == .afterBegin }
        XCTAssertNotNil(SetSchoolYearSheet.write(2027, to: course, on: day))
        UndoKillPoints.hook = nil
        XCTAssertEqual(UndoStoppedStep.judgeAtOnce(seq: 2, in: journal()), .putBack)
        let onDisk: Data = try Data(contentsOf: course.configFileURL)

        XCTAssertEqual(UndoStoppedStep.judgeAtOnce(seq: 2, in: journal()), .notMade)

        XCTAssertEqual(try Data(contentsOf: course.configFileURL), onDisk)
        XCTAssertEqual(try inFlightCount(), 0)
    }

    /// A step already closed as made is said as made, never offered.
    func testAStepAlreadyClosedAsMadeIsFinished() throws {
        let course: Course = try courseIn2026()
        UndoKillPoints.hook = { point in point == .beforeApplied }
        XCTAssertNotNil(SetSchoolYearSheet.write(2027, to: course, on: day))
        UndoKillPoints.hook = nil
        XCTAssertEqual(UndoStoppedStep.judgeAtOnce(seq: 2, in: journal()), .finished(seq: 2))
        XCTAssertEqual(UndoStoppedStep.judgeAtOnce(seq: 2, in: journal()), .finished(seq: 2))
    }

    /// LOW 1 of review 1: the list's lock cannot be got, so the step cannot
    /// be judged: it stays in flight and the caller offers Put It Back,
    /// which can succeed once the lock is free. MUST FAIL with that branch
    /// answered as made.
    func testALockNotGotLeavesTheStepInFlightForTheOffer() throws {
        let course: Course = try courseIn2026()
        UndoKillPoints.hook = { point in point == .beforeApplied }
        XCTAssertNotNil(SetSchoolYearSheet.write(2027, to: course, on: day))
        UndoKillPoints.hook = nil
        let lockFile: URL = journal().lockFileURL
        chmod(lockFile.path, 0o000)

        let verdict: UndoStoppedStepVerdict = UndoStoppedStep.judgeAtOnce(seq: 2, in: journal())

        chmod(lockFile.path, 0o644)
        XCTAssertEqual(verdict, .couldNotFinish(seq: 2))
        XCTAssertEqual(try inFlightCount(), 1)
        let offer: SettingPutBackOffer = SettingPutBackOffer(seq: 2, setting: "school year", valueBefore: "2026\u{2013}27")
        XCTAssertNil(SetSchoolYearSheet.putBack(offer, course: course))
        XCTAssertEqual(try yearOnDisk(course), 2026)
        XCTAssertEqual(try inFlightCount(), 0)
    }

    // MARK: - Fix round one: Save Course Settings

    /// MEDIUM 2 of review 1: Save Course Settings that stopped part way and
    /// could not finish offers Put It Back with the setting's own name and
    /// old value when one setting changed; no sentence names the file.
    func testSaveCourseSettingsOfOneFieldThatCannotFinishOffersPutItBack() throws {
        let course: Course = try courseIn2026()
        let before: Data = try Data(contentsOf: course.configFileURL)
        course.configuration.courseName = "Computer Science"
        stopTheSwapPartWay(holding: .unreadable)
        var thrown: Error? = nil
        do {
            _ = try course.configuration.writeAsOneStep(
                to: course.configFileURL, madeBy: UndoStepMaker.sheet("saveCourseSettings")
            )
        } catch {
            thrown = error
        }
        clearTheStop()
        chmod(course.configFileURL.path, 0o644)
        guard case .couldNotFinish(let seq, _)? = thrown as? JournaledStepError else {
            return XCTFail("not offered: \(String(describing: thrown))")
        }
        XCTAssertFalse((thrown?.localizedDescription ?? "").contains("course_config"))
        let offer: SettingPutBackOffer = CourseSettingsView.putBackOffer(
            seq: seq, before: before, wanted: course.configuration.values
        )
        XCTAssertEqual(offer, SettingPutBackOffer(seq: seq, setting: "course name", valueBefore: "Introduction to Computer Science"))
        XCTAssertEqual(offer.informativeText, "Plantoir can put it back to Introduction to Computer Science.")

        XCTAssertNil(CourseSettingsView.putBack(offer, course: course))

        XCTAssertEqual(try inFlightCount(), 0)
        XCTAssertEqual(course.configuration.courseName, "Introduction to Computer Science")
    }

    /// Several settings at once: the offer names the course settings and
    /// puts them back as they were (wording parked for the director).
    func testSaveCourseSettingsOfSeveralFieldsOffersThemBackTogether() throws {
        let course: Course = try courseIn2026()
        let before: Data = try Data(contentsOf: course.configFileURL)
        course.configuration.courseName = "Computer Science"
        course.configuration.customShortName = "CS"
        let offer: SettingPutBackOffer = CourseSettingsView.putBackOffer(
            seq: 7, before: before, wanted: course.configuration.values
        )
        XCTAssertEqual(offer, SettingPutBackOffer(seq: 7, setting: "course settings", valueBefore: nil))
        XCTAssertEqual(ReferenceWording.settingCouldNotBeChanged(setting: offer.setting), "The course settings could not be changed.")
        XCTAssertEqual(offer.informativeText, ReferenceWording.settingsCanBePutBack)
    }

    /// A step that could not finish, or was closed without the change,
    /// never names the file to a teacher.
    func testCouldNotFinishNamesNoFile() {
        let error: JournaledStepError = .couldNotFinish(seq: 2, fileName: "course_config.json")
        XCTAssertFalse((error.errorDescription ?? "").contains("course_config"))
        XCTAssertFalse((JournaledStepError.notMade.errorDescription ?? "").contains("course_config"))
    }

    // MARK: - Fix round one: the contract's cases

    /// `referenceCourses.settingStoppedCases`, run from the JSON through
    /// Set School Year: what the file holds once the swap stopped, and
    /// whether the step is left in flight, stays on the list, is offered,
    /// and what the teacher reads.
    func testTheContractsStoppedSettingCases() throws {
        let cases: [[String: Any]] = try XCTUnwrap(
            try referenceCoursesBlock()["settingStoppedCases"] as? [[String: Any]]
        )
        XCTAssertGreaterThanOrEqual(cases.count, 5)
        for testCase in cases {
            let name: String = testCase["name"] as? String ?? "?"
            let holding: StoppedWith = try XCTUnwrap(StoppedWith(rawValue: testCase["fileHolds"] as? String ?? ""), name)
            freshFolders()
            let course: Course = try courseIn2026()
            stopTheSwapPartWay(holding: holding)
            let result: SettingWriteResult = SetSchoolYearSheet.writeJudged(2027, to: course, on: day)
            clearTheStop()
            chmod(course.configFileURL.path, 0o644)

            let said: String = testCase["said"] as? String ?? ""
            switch said {
            case "nothing":
                XCTAssertEqual(result, .saved, name)
            case "couldNotSetSchoolYear":
                XCTAssertEqual(result, .refused(ReferenceWording.couldNotSetSchoolYear(course: course.displayCode)), name)
            case "settingCouldNotBeChanged":
                XCTAssertEqual(result, .couldNotFinish(seq: 2), name)
            default:
                XCTFail("\(name): said '\(said)' is not a value this test knows")
            }
            let inFlight: Bool = testCase["leftInFlight"] as? Bool ?? false
            XCTAssertEqual(try inFlightCount(), inFlight ? 1 : 0, name)
            if !inFlight {
                let undo: UndoOutcome = journal().undoNewest(resolveRoot: { _ in self.root })
                switch testCase["undoOffers"] as? String ?? "" {
                case "theChange":
                    XCTAssertEqual(undo, .undone(seq: 2), name)
                case "theStepBefore":
                    XCTAssertEqual(undo, .undone(seq: 1), name)
                case "nothing":
                    XCTAssertEqual(undo, .nothingToUndo, name)
                default:
                    XCTFail("\(name): undoOffers is not a value this test knows")
                }
            }
        }
    }

    func referenceCoursesBlock() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let data: Data = try Data(contentsOf: url)
        let contract: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(contract["referenceCourses"] as? [String: Any])
    }

    /// A fresh course and list, for a test that runs several cases.
    func freshFolders() {
        let unique: String = UUID().uuidString
        listFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-stopped-list-\(unique)", isDirectory: true)
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-stopped-\(unique)", isDirectory: true)
        UndoJournalLocation.folderOverride = listFolder
    }
}

/// The sheet's offer, held where a test's binding can read and clear it.
final class OfferBox {

    // MARK: - Stored properties

    var offer: SettingPutBackOffer?

    // MARK: - Initializer

    init(_ offer: SettingPutBackOffer?) {
        self.offer = offer
    }
}

/// What each answer said, in order.
final class AnswerBox {

    // MARK: - Stored properties

    var said: [String?] = []
}
