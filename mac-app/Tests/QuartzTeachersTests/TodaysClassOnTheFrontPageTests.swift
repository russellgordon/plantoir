import XCTest
@testable import QuartzTeachers

/// #397: at Preview, the offer to show today's class on the section's front
/// page. The cases are `contracts/class-planning.json` →
/// `todaysClassOnTheFrontPage.cases`, run through the real readers on real
/// files in a temporary course — never retyped here.
@MainActor
final class TodaysClassOnTheFrontPageTests: XCTestCase {

    // MARK: - Stored properties

    private var roots: [URL] = []

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        for root in roots {
            TodaysClassOnTheFrontPageTests.unlockEverything(under: root)
            try? FileManager.default.removeItem(at: root)
        }
        roots = []
        try await super.tearDown()
    }

    // MARK: - The contract's cases

    /// T1: every case asks exactly as the contract says, and Yes leaves the
    /// page exactly as it says.
    func testEveryCaseAsksAsTheContractSays() throws {
        let section: [String: Any] = try TodaysClassOnTheFrontPageTests.contractSection()
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 42, "the contract lost question cases")

        var yesRuns: Int = 0
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: Course = try makeCourse(from: testCase)
            let sectionNumber: Int = (testCase["section"] as? Int) ?? 1
            let today: CalendarDay = try XCTUnwrap(CalendarDay(text: try XCTUnwrap(testCase["today"] as? String)))

            let offer: TodaysClassOnTheFrontPage.Offer? = TodaysClassOnTheFrontPage.offer(
                forSection: sectionNumber, in: course, today: today
            )
            guard let expected = testCase["expectAsk"] as? [String: Any] else {
                XCTAssertNil(offer, "\(name): asked \(String(describing: offer?.classTitle)) and should not have")
                continue
            }
            let asked: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(offer, "\(name): did not ask")
            XCTAssertEqual(asked.classTitle, expected["show"] as? String, name)
            XCTAssertEqual(asked.shownTitle, expected["shows"] as? String, name)
            XCTAssertEqual(asked.day, today, name)
            if let noun = testCase["noun"] as? String {
                XCTAssertEqual(asked.noun.singular, noun, name)
            }

            guard let after = testCase["expectAfterYes"] as? [String: Any] else {
                continue
            }
            let indexURL: URL = SectionIndexPointer.indexURL(forSection: sectionNumber, in: course)
            let outcome: TodaysClassOnTheFrontPage.Outcome = TodaysClassOnTheFrontPage.show(asked, in: course)
            XCTAssertEqual(outcome, .shown(from: asked.shownTitle, to: asked.classTitle), name)
            let text: String = try String(contentsOf: indexURL, encoding: .utf8)
            XCTAssertEqual(
                TodaysClassOnTheFrontPageTests.body(of: text), try XCTUnwrap(after["body"] as? String), name
            )
            let created: String = PageFrontmatter.rawValue(forKey: "created", in: text) ?? ""
            XCTAssertTrue(
                created.hasPrefix(try XCTUnwrap(after["createdDay"] as? String)),
                "\(name): the front page's date is \(created)"
            )
            // Asked again, the page now shows today's class: no question.
            XCTAssertNil(
                TodaysClassOnTheFrontPage.offer(forSection: sectionNumber, in: course, today: today),
                "\(name): asked again after Yes"
            )
            yesRuns += 1
        }
        XCTAssertGreaterThanOrEqual(yesRuns, 20, "the contract lost the cases that say what Yes leaves")
    }

    /// The pieces of the contract the cases lean on are there, and the rule
    /// is said in the same words the two apps read.
    func testTheContractSaysWhereItIsAskedAndWhereNot() throws {
        let section: [String: Any] = try TodaysClassOnTheFrontPageTests.contractSection()
        for key in ["note", "rule", "askedFrom", "neverAskedFrom", "yes", "notToday",
                    "whenNoClassIsTransclusion", "howTheCasesRun", "fill", "plainWordsCheck"] {
            XCTAssertNotNil(section[key] as? String, key)
        }
        XCTAssertGreaterThanOrEqual((section["rejected"] as? [String])?.count ?? 0, 5)
        for testCase in try XCTUnwrap(section["cases"] as? [[String: Any]]) {
            XCTAssertNil(testCase["expectAskOnWindows"], "one rule for both apps: \(testCase["name"] ?? "")")
        }
    }

    // MARK: - Wording

    /// T2: each key says what the contract says, placeholders and all.
    func testTheWordingIsTheContracts() throws {
        let wording: [String: String] = try TodaysClassOnTheFrontPageTests.contractWording()
        let ours: [String: String] = [
            "question": FrontPageWording.question(class: "{class}"),
            "because": FrontPageWording.because(noun: "{noun}", shown: "{shown}"),
            "show": FrontPageWording.show,
            "notToday": FrontPageWording.notToday,
            "notChangedTitle": FrontPageWording.notChangedTitle,
            "noLongerOffered": FrontPageWording.noLongerOffered(noun: "{noun}"),
            "couldNotSave": FrontPageWording.couldNotSave(shown: "{shown}")
        ]
        XCTAssertEqual(ours, wording)
    }

    /// T3: no sentence says a word the contract's `plainWordsCheck` rules
    /// out (R14) — checked on the FILLED sentences, since a whole-word scan
    /// of the templates cannot see what a filled one says.
    func testNoSentenceSaysATechnicalWord() throws {
        let words: [String] = ["transclude", "transcludes", "transcluded", "transclusion", "transclusions",
                               "embed", "embeds", "embedded", "index", "file", "frontmatter", "link"]
        let sentences: [String] = [
            FrontPageWording.question(class: "Unit 2, Day 5"),
            FrontPageWording.because(noun: "class", shown: "Unit 2, Day 4"),
            FrontPageWording.because(noun: "meeting", shown: "Week 3"),
            FrontPageWording.show,
            FrontPageWording.notToday,
            FrontPageWording.notChangedTitle,
            FrontPageWording.noLongerOffered(noun: "class"),
            FrontPageWording.couldNotSave(shown: "Unit 2, Day 4")
        ]
        for sentence in sentences {
            var sentenceWords: Set<String> = []
            for piece in sentence.lowercased().components(separatedBy: CharacterSet.letters.inverted) {
                if !piece.isEmpty {
                    sentenceWords.insert(piece)
                }
            }
            for word in words {
                XCTAssertFalse(sentenceWords.contains(word), "“\(sentence)” says “\(word)”")
            }
        }
        let plain: String = try XCTUnwrap(try TodaysClassOnTheFrontPageTests.contractSection()["plainWordsCheck"] as? String)
        XCTAssertTrue(plain.contains("transclude"))
        XCTAssertTrue(plain.contains("embed"))
    }

    /// The transclude family is on the label scan's list, and "embed" is
    /// deliberately not (a real label says it).
    func testTheTranscludeFamilyIsAForbiddenLabelWord() throws {
        let rules: [String: Any] = try TodaysClassOnTheFrontPageTests.contract("shared-rules.json")
        let labels: [String: Any] = try XCTUnwrap(rules["userFacingLabelWords"] as? [String: Any])
        let forbidden: [String] = try XCTUnwrap(labels["forbidden"] as? [String])
        for word in ["transclude", "transcludes", "transcluded", "transcluding", "transclusion", "transclusions"] {
            XCTAssertTrue(forbidden.contains(word), word)
        }
        XCTAssertFalse(forbidden.contains("embed"))
    }

    // MARK: - Not Today

    /// T4: remembered per section, day and class, in the keys the file
    /// format names — and another day or another class asks again.
    func testNotTodayIsRememberedForTheDayAndTheClass() throws {
        let course: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-30"))
        let offer: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
            TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today)
        )
        let record: TodaysClassOnTheFrontPage.NotToday = TodaysClassOnTheFrontPage.NotToday(
            day: offer.day.text, classTitle: offer.classTitle
        )
        try record.write(courseDirectory: course.directoryURL, section: 1)
        XCTAssertEqual(TodaysClassOnTheFrontPage.NotToday.read(courseDirectory: course.directoryURL, section: 1), record)

        let fileURL: URL = TodaysClassOnTheFrontPage.NotToday.fileURL(courseDirectory: course.directoryURL, section: 1)
        let object: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: fileURL)) as? [String: Any]
        )
        let formats: [String: Any] = try TodaysClassOnTheFrontPageTests.contract("file-formats.json")
        let format: [String: Any] = try XCTUnwrap(formats["frontPageNotToday"] as? [String: Any])
        let keys: [String: Any] = try XCTUnwrap(format["keys"] as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(keys.keys))
        XCTAssertEqual(
            "courses/<CODE>/.publish_state/section<N>.front-page-not-today.json",
            format["path"] as? String
        )
        XCTAssertEqual(fileURL.lastPathComponent, "section1.front-page-not-today.json")
        XCTAssertEqual(fileURL.deletingLastPathComponent().lastPathComponent, ".publish_state")

        XCTAssertNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today), "asked after Not Today")

        // The same record, for yesterday or for another class, stops nothing.
        try TodaysClassOnTheFrontPage.NotToday(day: "2026-09-29", classTitle: offer.classTitle)
            .write(courseDirectory: course.directoryURL, section: 1)
        XCTAssertNotNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today))
        try TodaysClassOnTheFrontPage.NotToday(day: offer.day.text, classTitle: "Unit 2, Day 4")
            .write(courseDirectory: course.directoryURL, section: 1)
        XCTAssertNotNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today))
    }

    /// Implementation review, finding 2: the answer SAVES Not Today, and the
    /// window's answer goes through the function that does.
    func testNotTodayIsSavedByTheAnswer() throws {
        let course: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-30"))
        let offer: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
            TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today)
        )
        let line: String = TodaysClassOnTheFrontPage.answerNotToday(offer, courseDirectory: course.directoryURL)
        XCTAssertEqual(line, TodaysClassOnTheFrontPage.notTodayTrailLine(offer: offer))
        XCTAssertEqual(
            TodaysClassOnTheFrontPage.NotToday.read(courseDirectory: course.directoryURL, section: 1),
            TodaysClassOnTheFrontPage.NotToday(day: "2026-09-30", classTitle: "Unit 2, Day 5")
        )
        XCTAssertNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today), "asked again after Not Today")

        let answer: String = try TodaysClassOnTheFrontPageTests.body(
            of: "func answerTodaysClass(", in: try TodaysClassOnTheFrontPageTests.sectionView()
        )
        XCTAssertTrue(answer.contains("TodaysClassOnTheFrontPage.answerNotToday(offer, courseDirectory: course.directoryURL)"))
        XCTAssertTrue(answer.contains(".frontPageLeftAsItWas"))
    }

    // MARK: - What waits behind the question

    /// Implementation review, note 4: a refusal held behind the question is
    /// not dropped when the button's own preview is refused too.
    func testTwoRefusalsAreBothSaid() throws {
        let earlier: SectionDetailView.PreviewAlert = .refusal(title: "Cannot Preview Yet", sentence: "First.")
        let later: SectionDetailView.PreviewAlert = .refusal(title: "The Preview Did Not Appear", sentence: "Second.")
        XCTAssertEqual(
            SectionDetailView.joining(earlier, then: later),
            .refusal(title: "The Preview Did Not Appear", sentence: "First.\n\nSecond.")
        )
        XCTAssertEqual(SectionDetailView.joining(later, then: later), later)
        let after: String = try TodaysClassOnTheFrontPageTests.body(
            of: "func afterThePreviewAlert()", in: try TodaysClassOnTheFrontPageTests.sectionView()
        )
        XCTAssertTrue(after.contains("SectionDetailView.joining(held, then: previewAlert)"))
    }

    /// Implementation review, note 5: folder findings wait behind the
    /// question as they wait behind the folder dialog, and are shown after it.
    func testFolderFindingsWaitBehindThePreviewAlert() throws {
        let view: String = TodaysClassOnTheFrontPageTests.codeOnly(try TodaysClassOnTheFrontPageTests.sectionView())
        XCTAssertEqual(view.components(separatedBy: "if healthDialog != nil || previewAlertIsUp {").count - 1, 3,
                       "findings (twice) and the links checklist are held behind the preview alert")
    }

    // MARK: - A front page that must not be written

    /// T5: a front page that is a symbolic link, or locked, is not asked
    /// about — and the file a link points at is left alone.
    func testALinkedOrLockedFrontPageIsNotAskedAbout() throws {
        let course: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-30"))
        let indexURL: URL = SectionIndexPointer.indexURL(forSection: 1, in: course)
        XCTAssertNotNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today))

        let elsewhere: URL = course.directoryURL.deletingLastPathComponent().appendingPathComponent("elsewhere.md")
        try FileManager.default.moveItem(at: indexURL, to: elsewhere)
        try FileManager.default.createSymbolicLink(at: indexURL, withDestinationURL: elsewhere)
        let linkedBefore: Data = try Data(contentsOf: elsewhere)
        XCTAssertNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today), "asked about a link")
        XCTAssertEqual(try Data(contentsOf: elsewhere), linkedBefore)

        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.moveItem(at: elsewhere, to: indexURL)
        XCTAssertNotNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today))
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: indexURL.path)
        XCTAssertNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today), "asked about a locked page")
    }

    // MARK: - Yes

    /// T6: Yes changes the one line and the date, and nothing else — and a
    /// page that changed while the question was up is decided again.
    func testYesChangesOneLineAndTheDate() throws {
        let course: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-30"))
        let indexURL: URL = SectionIndexPointer.indexURL(forSection: 1, in: course)
        let before: String = try String(contentsOf: indexURL, encoding: .utf8)
        let offer: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
            TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today)
        )
        XCTAssertEqual(TodaysClassOnTheFrontPage.show(offer, in: course), .shown(from: "Unit 2, Day 4", to: "Unit 2, Day 5"))
        let after: String = try String(contentsOf: indexURL, encoding: .utf8)
        let beforeLines: [String] = before.components(separatedBy: "\n")
        let afterLines: [String] = after.components(separatedBy: "\n")
        XCTAssertEqual(beforeLines.count, afterLines.count)
        var changed: [String] = []
        for index in 0..<beforeLines.count where beforeLines[index] != afterLines[index] {
            changed.append(afterLines[index])
        }
        XCTAssertEqual(changed, ["created: 2026-09-30T07:00:00.000-0400", "![[Unit 2, Day 5]]"])

        // Edited in Obsidian while the question was up: it already shows
        // today's class, so nothing is written.
        let course2: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let offer2: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
            TodaysClassOnTheFrontPage.offer(forSection: 1, in: course2, today: today)
        )
        let index2: URL = SectionIndexPointer.indexURL(forSection: 1, in: course2)
        let edited: String = try String(contentsOf: index2, encoding: .utf8)
            .replacingOccurrences(of: "![[Unit 2, Day 4]]", with: "![[Unit 2, Day 5]]")
        try edited.write(to: index2, atomically: true, encoding: .utf8)
        XCTAssertEqual(TodaysClassOnTheFrontPage.show(offer2, in: course2), .alreadyRight)
        XCTAssertEqual(try String(contentsOf: index2, encoding: .utf8), edited)

        // The later class published while the question was up: the answer
        // was about Day 5, so nothing is written (plan review, 4).
        let course3: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let offer3: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
            TodaysClassOnTheFrontPage.offer(forSection: 1, in: course3, today: today)
        )
        let index3: URL = SectionIndexPointer.indexURL(forSection: 1, in: course3)
        let untouched: Data = try Data(contentsOf: index3)
        try TodaysClassOnTheFrontPageTests.classPage(title: "Unit 2, Day 6", publish: "true",
                                                     created: "2026-09-30T13:00:00.000-0400")
            .write(to: ClassPages.folderURL(forSection: 1, in: course3).appendingPathComponent("Unit 2, Day 6.md"),
                   atomically: true, encoding: .utf8)
        XCTAssertEqual(TodaysClassOnTheFrontPage.show(offer3, in: course3), .noLongerOffered)
        XCTAssertEqual(try Data(contentsOf: index3), untouched)

        // Hidden while the question was up: nothing is written.
        let course4: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let offer4: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
            TodaysClassOnTheFrontPage.offer(forSection: 1, in: course4, today: today)
        )
        try TodaysClassOnTheFrontPageTests.classPage(title: "Unit 2, Day 5", publish: "false",
                                                     created: "2026-09-30T07:00:00.000-0400")
            .write(to: ClassPages.folderURL(forSection: 1, in: course4).appendingPathComponent("Unit 2, Day 5.md"),
                   atomically: true, encoding: .utf8)
        XCTAssertEqual(TodaysClassOnTheFrontPage.show(offer4, in: course4), .noLongerOffered)
    }

    /// Answered after midnight: decided for the day the question was asked,
    /// never for the new one (plan review, 4).
    func testAnAnswerAfterMidnightIsAboutTheDayItWasAsked() throws {
        // Moved to a spring day, so that the Mac's own "today" — whenever
        // this runs — is never the day asked about: an answer decided with
        // a fresh day would find no class and write nothing.
        var spring: [String: Any] = try TodaysClassOnTheFrontPageTests.ordinaryMorning()
        let moved: Data = try JSONSerialization.data(withJSONObject: spring)
        let movedText: String = try XCTUnwrap(String(data: moved, encoding: .utf8))
            .replacingOccurrences(of: "2026-09-", with: "2025-03-")
        spring = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(movedText.data(using: .utf8))) as? [String: Any]
        )
        let course: Course = try makeCourse(from: spring)
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2025-03-30"))
        let offer: TodaysClassOnTheFrontPage.Offer = try XCTUnwrap(
            TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today)
        )
        // Tomorrow there is no class dated tomorrow, so a fresh "today" would
        // find nothing to show; the question's own day still does.
        XCTAssertNil(TodaysClassOnTheFrontPage.offer(
            forSection: 1, in: course, today: try XCTUnwrap(CalendarDay(text: "2025-03-31"))
        ))
        XCTAssertEqual(TodaysClassOnTheFrontPage.show(offer, in: course), .shown(from: "Unit 2, Day 4", to: "Unit 2, Day 5"))
    }

    // MARK: - Today

    /// T7: today is the teacher's calendar day, not UTC's — at 23:30 in
    /// Toronto it is still the 30th — and the view asks with the Mac's own.
    func testTodayIsTheTeachersCalendarDay() throws {
        let toronto: TimeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let lateEvening: Date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-01T03:30:00Z"))
        let today: CalendarDay = CalendarDay.today(lateEvening, timeZone: toronto)
        XCTAssertEqual(today.text, "2026-09-30")
        let course: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        XCTAssertNotNil(TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today))

        let view: String = try TodaysClassOnTheFrontPageTests.body(
            of: "func todaysClassOffer()", in: try TodaysClassOnTheFrontPageTests.sectionView()
        )
        XCTAssertTrue(view.contains("today: CalendarDay.today()"), "the view no longer asks with the Mac's own day")
    }

    // MARK: - Where it is asked

    /// T8: only the Preview BUTTON asks. `startPreview()` is every other way
    /// in — the assistant, Start of the Year, Course Settings, a repair — and
    /// must never hold them up on a question.
    func testOnlyThePreviewButtonAsks() throws {
        let view: String = TodaysClassOnTheFrontPageTests.codeOnly(try TodaysClassOnTheFrontPageTests.sectionView())
        var callers: [String] = []
        for fileURL in try TodaysClassOnTheFrontPageTests.productSwiftFiles() {
            let source: String = TodaysClassOnTheFrontPageTests.codeOnly(try String(contentsOf: fileURL, encoding: .utf8))
            if source.contains("TodaysClassOnTheFrontPage.offer(") || source.contains("todaysClassOffer()") {
                callers.append(fileURL.lastPathComponent)
            }
        }
        XCTAssertEqual(callers, ["SectionDetailView.swift"])
        XCTAssertEqual(view.components(separatedBy: "TodaysClassOnTheFrontPage.offer(").count - 1, 1)

        let offerFunction: String = try TodaysClassOnTheFrontPageTests.body(of: "func todaysClassOffer()", in: view)
        XCTAssertTrue(offerFunction.contains("TodaysClassOnTheFrontPage.offer("))
        let press: String = try TodaysClassOnTheFrontPageTests.body(of: "func pressPreview()", in: view)
        XCTAssertTrue(press.contains("todaysClassOffer()"))
        XCTAssertEqual(view.components(separatedBy: "todaysClassOffer()").count - 1, 2,
                       "todaysClassOffer() is declared once and called only from pressPreview()")

        let start: String = try TodaysClassOnTheFrontPageTests.body(of: "    func startPreview() {", in: view)
        XCTAssertFalse(start.contains("todaysClass"), "startPreview() must never ask")
        XCTAssertFalse(start.contains("pressPreview"), "startPreview() must never ask")

        // The Preview button's not-running branch presses; nothing else
        // does. The button's action is `previewButtonPressed()`, which the
        // toolbar button and Section ▸ Preview both call — the menu item IS
        // the teacher pressing Preview (#457; class-planning.json →
        // askedFrom names both, and nothing else).
        XCTAssertEqual(view.components(separatedBy: "pressPreview()").count - 1, 2,
                       "pressPreview() is declared once and called only from previewButtonPressed()")
        let pressed: String = try TodaysClassOnTheFrontPageTests.body(of: "func previewButtonPressed()", in: view)
        let notRunning: String = try XCTUnwrap(pressed.components(separatedBy: "stopPreview()").dropFirst().first)
        XCTAssertTrue(notRunning.contains("pressPreview()"), "the not-running branch presses")
        XCTAssertEqual(view.components(separatedBy: "previewButtonPressed()").count - 1, 3,
                       "previewButtonPressed() is declared once and called by the toolbar button and the Section menu's route")
        let siteMenu: String = try TodaysClassOnTheFrontPageTests.body(of: "func performSiteMenuItem(", in: view)
        XCTAssertTrue(siteMenu.contains("previewButtonPressed()"), "Section ▸ Preview presses the same button")

        // Plan review, 1: the answer never starts the preview from inside the
        // alert's own action; `afterThePreviewAlert` does, once it has gone.
        let answer: String = try TodaysClassOnTheFrontPageTests.body(of: "func answerTodaysClass(", in: view)
        XCTAssertFalse(answer.contains("startPreview()"), "a refusal raised inside the alert's action is lost")
        XCTAssertTrue(answer.contains("startPreviewWhenTheQuestionHasGone = true"))
        let after: String = try TodaysClassOnTheFrontPageTests.body(of: "func afterThePreviewAlert()", in: view)
        XCTAssertTrue(after.contains("startPreview()"))
    }

    /// T9: the section window still carries three `.alert` modifiers — a
    /// fourth segfaulted SwiftUI's alert bridge (documentation/09-mac-app.md)
    /// — and the preview alert's words come from a value the dismissal does
    /// not clear (plan review, 2).
    func testTheSectionWindowStillHasThreeAlerts() throws {
        let view: String = try TodaysClassOnTheFrontPageTests.sectionView()
        var alerts: Int = 0
        for line in view.components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") {
                continue
            }
            alerts += line.components(separatedBy: ".alert(").count - 1
        }
        XCTAssertEqual(alerts, 3)
        XCTAssertTrue(view.contains(".alert(previewAlertTitle, isPresented: $previewAlertIsUp)"))
        for writer in ["previewAlert = nil", "previewAlert = .refusal(title: \"\"", "previewAlert: PreviewAlert?"] {
            XCTAssertFalse(view.contains(writer), "the preview alert's words are cleared somewhere: \(writer)")
        }
    }

    /// Plan review, 3: the links checklist waits behind the question and a
    /// refusal as it waits behind the folder dialog.
    func testTheLinksChecklistWaitsBehindThePreviewAlert() throws {
        let view: String = try TodaysClassOnTheFrontPageTests.sectionView()
        let request: String = try TodaysClassOnTheFrontPageTests.body(of: "func requestLinksChecklist(", in: view)
        XCTAssertTrue(request.contains("healthDialog != nil || previewAlertIsUp"))
        let waiting: String = try TodaysClassOnTheFrontPageTests.body(of: "func showAnythingWaiting()", in: view)
        let guardAt: Range<String.Index> = try XCTUnwrap(waiting.range(of: "if previewAlertIsUp {"))
        let presentAt: Range<String.Index> = try XCTUnwrap(waiting.range(of: "presentLinksChecklist("))
        XCTAssertLessThan(guardAt.lowerBound, presentAt.lowerBound)
        let after: String = try TodaysClassOnTheFrontPageTests.body(of: "func afterThePreviewAlert()", in: view)
        XCTAssertTrue(after.contains("showAnythingWaiting()"))
    }

    /// T10: a reference course, a course being copied, a busy window, a
    /// section being deployed or a course another program is building is
    /// never asked about.
    func testAReferenceCourseOrABusySectionIsNotAsked() {
        XCTAssertTrue(SectionDetailView.frontPageMayBeAskedAbout(
            isKeptForReference: false, isBeingCopied: false, isBusy: false,
            sectionIsDeploying: false, anotherProgramIsBuilding: false
        ))
        let each: [(Bool, Bool, Bool, Bool, Bool)] = [
            (true, false, false, false, false),
            (false, true, false, false, false),
            (false, false, true, false, false),
            (false, false, false, true, false),
            (false, false, false, false, true)
        ]
        for guardSet in each {
            XCTAssertFalse(SectionDetailView.frontPageMayBeAskedAbout(
                isKeptForReference: guardSet.0, isBeingCopied: guardSet.1, isBusy: guardSet.2,
                sectionIsDeploying: guardSet.3, anotherProgramIsBuilding: guardSet.4
            ), "\(guardSet)")
        }
    }

    // MARK: - Reading class pages only

    /// Plan review, 5: the question reads the class pages alone, and they
    /// are exactly the pages the pointer's graph calls class pages — on a
    /// course with a course-level class folder too.
    func testTheClassPagesAreThePointersClassPages() throws {
        let course: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let shared: URL = course.directoryURL.appendingPathComponent("Handouts")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try "---\ntitle: Rubric\n---\n[[Unit 2, Day 4]]\n".write(
            to: shared.appendingPathComponent("Rubric.md"), atomically: true, encoding: .utf8
        )
        let deeper: URL = ClassPages.folderURL(forSection: 1, in: course).appendingPathComponent("Unit 3")
        try FileManager.default.createDirectory(at: deeper, withIntermediateDirectories: true)
        try TodaysClassOnTheFrontPageTests.classPage(title: "Unit 3, Day 1", publish: "false", created: nil)
            .write(to: deeper.appendingPathComponent("Unit 3, Day 1.md"), atomically: true, encoding: .utf8)

        var fromTheGraph: [String] = []
        for page in AssistSectionGraph.read(forSection: 1, in: course, workspaceURL: nil).pages where page.isClassPage {
            fromTheGraph.append(page.fileURL.path)
        }
        var classesOnly: [String] = []
        for page in AssistSectionGraph.classPages(forSection: 1, in: course) {
            classesOnly.append(page.fileURL.path)
        }
        XCTAssertEqual(classesOnly.sorted(), fromTheGraph.sorted())
        XCTAssertEqual(classesOnly.count, 5)
    }

    /// Plan review, 5: what one press costs on a large section — measured on
    /// a synthetic 450-page section, never on a teacher's folder. The number
    /// is printed for the record; the bound is loose on purpose.
    func testAPressOnALargeSectionIsQuick() throws {
        let course: Course = try makeCourse(from: TodaysClassOnTheFrontPageTests.ordinaryMorning())
        let classes: URL = ClassPages.folderURL(forSection: 1, in: course)
        for number in 1...300 {
            let page: String = TodaysClassOnTheFrontPageTests.classPage(
                title: "Unit 9, Day \(number)", publish: "true", created: "2026-06-01T07:00:00.000-0400"
            ) + String(repeating: "Some notes with a [[Link \(number)]] in them.\n", count: 40)
            try page.write(to: classes.appendingPathComponent("Unit 9, Day \(number).md"), atomically: true, encoding: .utf8)
        }
        let other: URL = course.sectionDirectoryURL(forSection: 1).appendingPathComponent("Handouts")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        for number in 1...150 {
            try String(repeating: "A handout line with [[Link \(number)]].\n", count: 60)
                .write(to: other.appendingPathComponent("Handout \(number).md"), atomically: true, encoding: .utf8)
        }
        let today: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-09-30"))
        let clock: ContinuousClock = ContinuousClock()
        var offer: TodaysClassOnTheFrontPage.Offer?
        let elapsed: Duration = clock.measure {
            offer = TodaysClassOnTheFrontPage.offer(forSection: 1, in: course, today: today)
        }
        let graphElapsed: Duration = clock.measure {
            _ = AssistSectionGraph.read(forSection: 1, in: course, workspaceURL: nil)
        }
        print("#397 timing: one press over 454 pages took \(elapsed); the whole graph would take \(graphElapsed)")
        XCTAssertNotNil(offer)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    // MARK: - The trail

    /// The two lines follow the contract's `line` shapes.
    func testTheTrailLinesFollowTheContract() throws {
        let rules: [String: Any] = try TodaysClassOnTheFrontPageTests.contract("shared-rules.json")
        let trail: [String: Any] = try XCTUnwrap(rules["activityTrail"] as? [String: Any])
        var shapes: [String: String] = [:]
        for entry in try XCTUnwrap(trail["mustRecord"] as? [[String: Any]]) {
            if let event = entry["event"] as? String, let line = entry["line"] as? String {
                shapes[event] = line
            }
        }
        let offer: TodaysClassOnTheFrontPage.Offer = TodaysClassOnTheFrontPage.Offer(
            classTitle: "Unit 2, Day 5", shownTitle: "Unit 2, Day 4", courseCode: "TEST",
            sectionNumber: 1, day: try XCTUnwrap(CalendarDay(text: "2026-09-30")), noun: .class
        )
        let shown: (event: ActivityTrail.Event, what: String) = TodaysClassOnTheFrontPage.trailLine(
            for: .shown(from: "Unit 2, Day 4", to: "Unit 2, Day 5"), offer: offer
        )
        XCTAssertEqual(
            "{course}/{section} · " + shown.what,
            try XCTUnwrap(shapes[shown.event.rawValue])
                .replacingOccurrences(of: "{class}", with: "Unit 2, Day 5")
                .replacingOccurrences(of: "{shown}", with: "Unit 2, Day 4")
        )
        let leftShape: String = try XCTUnwrap(shapes[ActivityTrail.Event.frontPageLeftAsItWas.rawValue])
        let reasons: String = try XCTUnwrap(
            leftShape.components(separatedBy: "{").dropFirst(3).first?.components(separatedBy: "}").first
        )
        let outcomes: [TodaysClassOnTheFrontPage.Outcome] = [.alreadyRight, .noLongerOffered, .couldNotSave]
        var lines: [String] = [TodaysClassOnTheFrontPage.notTodayTrailLine(offer: offer)]
        for outcome in outcomes {
            let line: (event: ActivityTrail.Event, what: String) = TodaysClassOnTheFrontPage.trailLine(for: outcome, offer: offer)
            XCTAssertEqual(line.event, .frontPageLeftAsItWas)
            lines.append(line.what)
        }
        for (reason, line) in zip(reasons.components(separatedBy: "|"), lines) {
            let expected: String = leftShape
                .replacingOccurrences(of: "{" + reasons + "}", with: reason)
                .replacingOccurrences(of: "{class}", with: "Unit 2, Day 5")
                .replacingOccurrences(of: "{shown}", with: "Unit 2, Day 4")
            XCTAssertEqual("{course}/{section} · " + line, expected)
        }
    }

    // MARK: - Helpers

    private func makeCourse(from testCase: [String: Any]) throws -> Course {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("todays-class-\(UUID().uuidString)")
        roots.append(root)
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("TEST")
        let sectionNumber: Int = (testCase["section"] as? Int) ?? 1
        var sections: [Int] = [1]
        if sectionNumber != 1 {
            sections.append(sectionNumber)
        }
        for number in sections {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent("section\(number)/All Classes"),
                withIntermediateDirectories: true
            )
        }
        var configuration: [String: Any] = [
            "course_code": "TEST",
            "course_name": "A Test Course",
            "section_numbers": sections,
            "num_sections": sections.count,
            "per_section_folders": ["All Classes"],
            "per_section_files": []
        ]
        if let word = testCase["unitWord"] as? String {
            configuration["unit_word"] = word
        }
        if let scheme = testCase["classPageScheme"] as? String {
            configuration["class_page_scheme"] = scheme
        }
        if let noun = testCase["noun"] as? String {
            configuration["class_noun"] = noun
        }
        if let heading = testCase["frontPageHeading"] as? String {
            configuration["front_page_heading"] = heading
        }
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "TEST", directoryURL: courseURL, configuration: loaded)

        for pageClass in try XCTUnwrap(testCase["classes"] as? [[String: Any]]) {
            let title: String = try XCTUnwrap(pageClass["title"] as? String)
            let folderName: String = (pageClass["folder"] as? String) ?? "All Classes"
            let folder: URL = course.sectionDirectoryURL(forSection: sectionNumber).appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var publish: String = "true"
            if let flag = pageClass["publish"] as? Bool {
                publish = flag ? "true" : "false"
            } else if pageClass["publish"] as? String == "unreadable" {
                publish = "\"true"
            }
            let page: String = TodaysClassOnTheFrontPageTests.classPage(
                title: title, publish: publish, created: pageClass["created"] as? String
            )
            try page.write(to: folder.appendingPathComponent(title + ".md"), atomically: true, encoding: .utf8)
        }
        let indexText: String = try XCTUnwrap(testCase["indexText"] as? String)
        try indexText.write(
            to: SectionIndexPointer.indexURL(forSection: sectionNumber, in: course), atomically: true, encoding: .utf8
        )
        if let declined = testCase["declined"] as? [String: Any] {
            try TodaysClassOnTheFrontPage.NotToday(
                day: try XCTUnwrap(declined["day"] as? String),
                classTitle: try XCTUnwrap(declined["class"] as? String)
            ).write(courseDirectory: courseURL, section: sectionNumber)
        }
        return course
    }

    private static func classPage(title: String, publish: String, created: String?) -> String {
        var page: String = "---\ntitle: \(title)\npublish: \(publish)\n"
        if let created {
            page += "created: \(created)\n"
        }
        return page + "---\n"
    }

    /// The contract's first case, the ordinary morning, for the tests that
    /// need one course to act on.
    private static func ordinaryMorning() throws -> [String: Any] {
        let cases: [[String: Any]] = try XCTUnwrap(contractSection()["cases"] as? [[String: Any]])
        return try XCTUnwrap(cases.first)
    }

    /// The page below its frontmatter, as the contract's `body` is.
    private static func body(of text: String) -> String {
        guard let block = PageFrontmatter.block(in: text) else {
            return text
        }
        let lines: [String] = text.components(separatedBy: "\n")
        var below: [String] = []
        for index in (block.closeIndex + 1)..<lines.count {
            below.append(lines[index])
        }
        return below.joined(separator: "\n")
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func contract(_ name: String) throws -> [String: Any] {
        let url: URL = repositoryRoot().appendingPathComponent("contracts").appendingPathComponent(name)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
    }

    private static func contractSection() throws -> [String: Any] {
        return try XCTUnwrap(try contract("class-planning.json")["todaysClassOnTheFrontPage"] as? [String: Any])
    }

    private static func contractWording() throws -> [String: String] {
        return try XCTUnwrap(try contractSection()["wording"] as? [String: String])
    }

    private static func sectionView() throws -> String {
        let url: URL = repositoryRoot()
            .appendingPathComponent("mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func productSwiftFiles() throws -> [URL] {
        let root: URL = repositoryRoot().appendingPathComponent("mac-app/QuartzTeachers")
        var files: [URL] = []
        let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        )
        while let entry = enumerator?.nextObject() as? URL {
            if entry.pathExtension == "swift" && entry.lastPathComponent != "TodaysClassOnTheFrontPage.swift" {
                files.append(entry)
            }
        }
        return files
    }

    /// The text of a function, from its signature to the next `    func `.
    private static func body(of signature: String, in source: String) throws -> String {
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: signature), signature)
        let rest: Substring = source[start.upperBound...]
        if let next = rest.range(of: "\n    func ") {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    /// The source without its comment lines, so a doc comment naming a
    /// function is not counted as a call to it.
    private static func codeOnly(_ source: String) -> String {
        var kept: [String] = []
        for line in source.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    private static func unlockEverything(under root: URL) {
        let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        )
        while let entry = enumerator?.nextObject() as? URL {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: entry.path)
        }
    }
}
