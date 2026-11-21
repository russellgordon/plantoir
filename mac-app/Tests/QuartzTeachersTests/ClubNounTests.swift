import XCTest
@testable import QuartzTeachers

/// "meeting" in a club's assistant (#267), and the rule that makes it safe to
/// ship without a routing measurement: the course's noun reaches what the
/// TEACHER reads and never what the MODEL reads.
///
/// A tool's outcome has two audiences (`AssistToolOutcome`). The model is
/// given `detail`; the teacher is shown `summary`, `forTheCard` and the lines
/// the window writes itself. Everything here holds the first of those
/// byte-for-byte whatever the course calls its pages, and checks the second
/// says the course's own word.
@MainActor
final class ClubNounTests: XCTestCase {

    // MARK: - Stored properties

    /// The plan tools a club teacher reaches, with arguments that make each
    /// plan say every sentence it has in the course's noun.
    private let plans: [(String, [String: Any])] = [
        ("plan_make_room_for_classes", ["course": "ICS3U", "section": 1, "unit": 2]),
        ("plan_add_next_class", ["course": "ICS3U", "section": 1]),
        ("plan_add_next_class", ["course": "ICS3U", "section": 1, "duplicate": "Week 2"]),
        ("plan_publish_class_on", ["course": "ICS3U", "section": 1, "date": "2026-09-09"]),
        ("plan_publish_pages", ["course": "ICS3U", "section": 1, "pages": "Week 2"]),
        ("plan_re_date_classes", ["course": "ICS3U", "section": 1]),
    ]

    // MARK: - Functions

    /// A numbered course with four hidden weeks, Week 2 linking to Week 3,
    /// and a timetable the pages do not sit on — so re-dating moves them.
    private func makeClub(noun: ClassNoun) throws -> (root: URL, course: Course, runner: AssistToolRunner) {
        let made: AssistFixture.Made = try AssistFixture.makeClub(noun: noun)
        return (made.root, made.course, made.runner)
    }

    /// Writes the course's naming to disk, which is where the runner reads it.
    private func setNoun(_ noun: ClassNoun, in course: Course) throws {
        try AssistFixture.setClubNaming(noun, in: course)
    }

    private func run(
        _ runner: AssistToolRunner, _ tool: String, _ arguments: [String: Any]
    ) async -> AssistToolOutcome {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return await runner.run(
            call: AssistToolCall(
                id: UUID().uuidString,
                type: "function",
                function: AssistToolCall.Function(
                    name: tool, arguments: String(decoding: encoded, as: UTF8.self)
                )
            )
        )
    }

    /// Whether `text` says "class" or "classes" as a word of its own.
    private func saysClass(_ text: String) -> Bool {
        return text.range(of: #"\b[Cc]lass(es)?\b"#, options: .regularExpression) != nil
    }

    // MARK: - The model reads the same bytes

    /// THE rule. Every plan a club teacher reaches gives the model exactly
    /// the text it would give in a course that says "class" — and the card
    /// the teacher reads says "meeting" instead.
    func testTheNounNeverReachesWhatTheModelReads() async throws {
        let club = try makeClub(noun: .meeting)
        defer { try? FileManager.default.removeItem(at: club.root) }

        for (tool, arguments) in plans {
            try setNoun(.class, in: club.course)
            let asClass: AssistToolOutcome = await run(club.runner, tool, arguments)
            try setNoun(.meeting, in: club.course)
            let asMeeting: AssistToolOutcome = await run(club.runner, tool, arguments)

            XCTAssertTrue(asClass.isPlan, "\(tool): \(asClass.summary)")
            XCTAssertEqual(asMeeting.detail, asClass.detail, "\(tool): the model was given the noun")
            XCTAssertEqual(asMeeting.summary, asClass.summary, "\(tool)")
            XCTAssertNotEqual(asMeeting.forTheCard, asClass.forTheCard, "\(tool): the card did not change")
            XCTAssertTrue(asMeeting.forTheCard.contains("meeting"), "\(tool): \(asMeeting.forTheCard)")
            XCTAssertFalse(
                saysClass(asMeeting.forTheCard), "\(tool) still says class:\n\(asMeeting.forTheCard)"
            )
            XCTAssertFalse(asMeeting.detail.contains("meeting"), "\(tool): \(asMeeting.detail)")
        }
    }

    /// An unpublish that stops at a linked meeting (#201) names it on the
    /// card as "a meeting of its own", and tells the model "a class of its
    /// own" — the reason is decided when the plan is made and put into words
    /// only for its reader, so the noun never reaches the model.
    func testAClubsUnpublishCardSaysMeetingAndTheModelIsToldClass() async throws {
        let club = try makeClub(noun: .meeting)
        defer { try? FileManager.default.removeItem(at: club.root) }

        try AssistFixture.write(page: "Week 3", publish: "true", date: "2026-09-10",
                                body: "Carry on in [[Week 4]].", in: club.course)
        try AssistFixture.write(page: "Week 4", publish: "true", date: "2026-09-11",
                                body: "The words of Week 4.", in: club.course)

        let planned: AssistToolOutcome = await run(
            club.runner, "plan_unpublish_pages", ["course": "ICS3U", "section": 1, "pages": "Week 3"]
        )

        // The card says the contract's own sentence.
        let wording: [String: Any] = try XCTUnwrap(
            AssistContract.wording()["wording"] as? [String: Any]
        )
        let forAMeeting: String = try XCTUnwrap(wording["linkedClassStaysVisibleForAMeeting"] as? String)
        XCTAssertTrue(planned.forTheCard.contains(forAMeeting), planned.forTheCard)

        let forTheModel: String = AssistPublishPlan.stayingVisibleLine(
            title: "Week 4", reason: .aClassOfItsOwn, noun: .class
        )
        XCTAssertTrue(planned.detail.contains(forTheModel), planned.detail)
        XCTAssertFalse(planned.detail.contains("meeting"), planned.detail)
    }

    /// The writes: the line the teacher reads says "meeting", the model's
    /// copy does not.
    func testAWriteTellsTheTeacherInTheCoursesNounAndTheModelInTheOrdinaryOne() async throws {
        let writes: [(String, [String: Any], String)] = [
            ("publish_class_on", ["course": "ICS3U", "section": 1, "date": "2026-09-09"],
             AssistWording.publishedTheClassOn("2026-09-09", noun: .meeting)),
            ("make_room_for_classes", ["course": "ICS3U", "section": 1, "unit": 2],
             AssistWording.madeRoom(count: 1, at: "Week 2", noun: .meeting)),
            ("re_date_classes", ["course": "ICS3U", "section": 1], "meetings"),
        ]
        for (tool, arguments, expected) in writes {
            let club = try makeClub(noun: .meeting)
            defer { try? FileManager.default.removeItem(at: club.root) }

            let outcome: AssistToolOutcome = await run(club.runner, tool, arguments)
            XCTAssertTrue(outcome.summary.contains(expected), "\(tool): \(outcome.summary)")
            XCTAssertFalse(saysClass(outcome.summary), "\(tool): \(outcome.summary)")
            XCTAssertFalse(outcome.detail.contains("meeting"), "\(tool): \(outcome.detail)")
        }
    }

    /// "When are my next meetings?" — the answer the teacher reads is in the
    /// course's noun, and the copy the model keeps in its history is not.
    func testTheDatesAnswerIsInTheCoursesNounForTheTeacherOnly() async throws {
        let club = try makeClub(noun: .meeting)
        defer { try? FileManager.default.removeItem(at: club.root) }
        let arguments: [String: Any] = ["course": "ICS3U", "section": 1]

        try setNoun(.class, in: club.course)
        let asClass: AssistToolOutcome = await run(club.runner, "read_remembered_timetable", arguments)
        try setNoun(.meeting, in: club.course)
        let asMeeting: AssistToolOutcome = await run(club.runner, "read_remembered_timetable", arguments)

        XCTAssertEqual(asMeeting.detail, asClass.detail)
        XCTAssertEqual(asClass.summary, asClass.detail)
        XCTAssertTrue(asMeeting.summary.contains("meeting"), asMeeting.summary)
        XCTAssertFalse(saysClass(asMeeting.summary), asMeeting.summary)
    }

    /// A course that says nothing hears exactly what it heard before #267.
    func testAnOrdinaryCourseHearsTheSameSentences() {
        XCTAssertEqual(
            AssistWording.otherClassesWouldMove(moving: 2, renaming: 1),
            "2 later classes move a day along to make room, and the links that point at them are "
            + "rewritten to match."
        )
        XCTAssertEqual(AssistWording.mayIAskForYourDates(for: .class), AssistWording.mayIAskForYourDates)
        XCTAssertEqual(AssistWording.datesNotGivenYet(for: .class), AssistWording.datesNotGivenYet)
    }

    // MARK: - The contract

    /// Every `…ForAMeeting` key has its "class" twin, says "meeting", and
    /// never says "class"; the twin says "class".
    func testEveryMeetingKeyHasItsClassTwin() throws {
        let wording: [String: Any] = try XCTUnwrap(AssistContract.wording()["wording"] as? [String: Any])
        var meetingKeys: [String] = []
        for key in wording.keys where key.hasSuffix("ForAMeeting") {
            meetingKeys.append(key)
        }
        XCTAssertGreaterThanOrEqual(meetingKeys.count, 20)
        for key in meetingKeys {
            let twinKey: String = String(key.dropLast("ForAMeeting".count))
            let meeting: String = try XCTUnwrap(wording[key] as? String, key)
            let twin: String = try XCTUnwrap(wording[twinKey] as? String, "\(key) has no \(twinKey)")
            XCTAssertTrue(meeting.contains("meeting"), "\(key): \(meeting)")
            XCTAssertFalse(saysClass(meeting), "\(key): \(meeting)")
            XCTAssertFalse(meeting.contains(", Day "), "\(key): \(meeting)")
            XCTAssertTrue(saysClass(twin), "\(twinKey): \(twin)")
        }
    }

    /// A club's menu bar titles the Classes menu Meetings (Russell's ruling
    /// on #990, 2026-11-20 evening: "in a club the menu itself is titled
    /// Meetings, on both platforms, so no sentence a club's teacher reads
    /// says 'class'"), so the sentence that names both menus for a club says
    /// neither "class" nor "Classes", and its ordinary twin says Classes.
    func testTheSentenceNamingBothMenusSaysMeetingsInAClub() throws {
        let wording: [String: Any] = try XCTUnwrap(AssistContract.wording()["wording"] as? [String: Any])
        let club: String = try XCTUnwrap(wording["sectionIsChangingFromTheMeetingsMenu"] as? String)
        XCTAssertFalse(saysClass(club), club)
        XCTAssertTrue(club.contains("the Section or Meetings menu"), club)
        let ordinary: String = try XCTUnwrap(wording["sectionIsChangingFromTheMenu"] as? String)
        XCTAssertTrue(ordinary.contains("the Section or Classes menu"), ordinary)
    }

    // MARK: - The menus' items in a club (#1027)

    /// `subjectMenus.layout.itemTitles` → `items`: each item whose title
    /// says class, as a course titles it and as a club does.
    private func itemTitlesInTheContract() throws -> [String: [String: String]] {
        let layout: [String: Any] = try SubjectMenuLayoutTests.layout()
        let itemTitles: [String: Any] = try XCTUnwrap(layout["itemTitles"] as? [String: Any])
        return try XCTUnwrap(itemTitles["items"] as? [String: [String: String]])
    }

    /// Every item of Section ▸ and Classes ▸, the submenu's included.
    private func everyItemOfTheTwoMenus() -> [SubjectMenuRules.Item] {
        var items: [SubjectMenuRules.Item] = []
        for menu in SubjectMenuLayout.Menu.allCases {
            for group in SubjectMenuLayout.groups(of: menu) {
                for entry in group {
                    switch entry {
                    case .item(let item):
                        items.append(item)
                    case .submenu(let submenu):
                        items.append(contentsOf: SubjectMenuLayout.items(of: submenu))
                    }
                }
            }
        }
        return items
    }

    /// Russell's ruling on #1027 (2026-11-20, night): in a club the
    /// Meetings menu's items say meeting. Each item the contract lists is
    /// drawn with its `title` in a course and its `titleForAMeeting` in a
    /// club, in the menu bar and in a section row's menu (both read
    /// `SectionMenu.title`); every other item of the two menus says neither
    /// class nor meeting and has one title in every course, so the list is
    /// complete. MUST FAIL with any club title put back to its class words,
    /// or a new item that says class left out of the list.
    func testEveryItemTitleSaysMeetingInAClub() throws {
        let listed: [String: [String: String]] = try itemTitlesInTheContract()
        XCTAssertEqual(listed.count, 5)
        for item in everyItemOfTheTwoMenus() {
            let asAClass: String? = SectionMenu.title(for: item, noun: .class)
            let asAMeeting: String? = SectionMenu.title(for: item, noun: .meeting)
            if let titles = listed[item.rawValue] {
                XCTAssertEqual(asAClass, titles["title"], item.rawValue)
                XCTAssertEqual(asAMeeting, titles["titleForAMeeting"], item.rawValue)
                XCTAssertEqual(SubjectMenuLayout.titleSayingTheNoun(of: item, noun: .meeting), titles["titleForAMeeting"])
                XCTAssertEqual(SubjectMenuLayout.titleSayingTheNoun(of: item, noun: .class), titles["title"])
                XCTAssertTrue(saysClass(asAClass ?? ""), item.rawValue)
                XCTAssertTrue((asAMeeting ?? "").contains("Meeting"), item.rawValue)
                XCTAssertTrue((asAMeeting ?? "").hasSuffix("…"), "\(item.rawValue) lost its ellipsis")
            } else {
                XCTAssertEqual(asAMeeting, asAClass, "\(item.rawValue) changes with the noun and is not in the contract")
                XCTAssertNil(SubjectMenuLayout.titleSayingTheNoun(of: item, noun: .meeting), item.rawValue)
            }
            XCTAssertFalse(saysClass(asAMeeting ?? ""), "\(item.rawValue) says class in a club: \(asAMeeting ?? "")")
        }
        for name in listed.keys {
            let item: SubjectMenuRules.Item? = SubjectMenuRules.Item(rawValue: name)
            XCTAssertNotNil(item, "\(name) is no item")
            if let item {
                XCTAssertNotNil(SubjectMenuLayout.menu(containing: item), "\(name) is in neither menu")
            }
        }
    }

    /// The contract's sentence for a key, with the place filled in.
    private func contractSentence(_ key: String, course: String, section: Int) throws -> String {
        let wording: [String: Any] = try XCTUnwrap(AssistContract.wording()["wording"] as? [String: Any])
        let template: String = try XCTUnwrap(wording[key] as? String, key)
        return template
            .replacingOccurrences(of: "{course}", with: course)
            .replacingOccurrences(of: "{section}", with: String(section))
    }

    /// #1027's review, MEDIUM 1: Meetings ▸ Meeting Dates… opens the Class
    /// Dates sheet, and in a club every sentence it says itself is the
    /// contract's `…ForAMeeting` twin — the purpose line, each refusal, the
    /// proposal, the part-way alert's title, the missing-course line, and
    /// the trail line when remembered dates are set aside. MUST FAIL with
    /// any of them said in the ordinary noun.
    func testTheClassDatesSheetSaysMeetingInAClub() throws {
        let club = try makeClub(noun: .meeting)
        defer { try? FileManager.default.removeItem(at: club.root) }
        let code: String = club.course.code
        let sheet: SectionScheduleSheet = SectionScheduleSheet(course: club.course, sectionNumber: 1)

        XCTAssertEqual(sheet.purposeLine, try contractSentence("classDatesPurposeForAMeeting", course: code, section: 1))

        let refusals: [(Error, String)] = [
            (SectionTimetableStore.Problem.noDatesGiven(code, 1), "classDatesNoneGivenForAMeeting"),
            (SectionTimetableStore.Problem.unreadableDates(code, 1, ["2026-13-01"]), "classDatesNotWrittenAsDatesForAMeeting"),
            (SectionTimetableStore.Problem.halfRemembered(code, 1, ["the file is not readable JSON"]),
             "classDatesOnFileUnreadableForAMeeting"),
            (SectionTimetableStore.Problem.cannotBeClassDates(code, 1, ["2569-09-08"]), "classDatesTooFarFromTodayForAMeeting"),
            (SectionTimetableStore.Problem.couldNotWrite(code, 1, "{reason}"), "classDatesCouldNotBeSavedForAMeeting"),
            (SectionScheduleSource.Problem.unreadableEntries("the pasted dates", ["2026-13-01"]), "classDatesHalfReadForAMeeting"),
        ]
        for (error, key) in refusals {
            let said: String = SectionScheduleSheet.sentence(for: error, noun: sheet.noun)
            XCTAssertEqual(said, try contractSentence(key, course: code, section: 1), key)
            // What the model is told stays in the ordinary noun.
            XCTAssertTrue(saysClass(error.localizedDescription), "\(key): \(error.localizedDescription)")
        }

        XCTAssertEqual(
            SectionTimetableStore.Problem.rememberedTitle(code, 1, noun: sheet.noun),
            try contractSentence("classDatesAreRememberedForAMeeting", course: code, section: 1)
        )

        // The proposal, as the sheet draws it: a fresh list, then the same one.
        var tuesdays: [String] = []
        for day in ["09-08", "09-15", "09-22", "09-29", "10-06", "10-13", "10-20", "10-27",
                    "11-03", "11-10", "11-17", "11-24"] {
            tuesdays.append("2026-" + day)
        }
        let fresh: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: tuesdays, source: "block H", forSection: 1, in: club.course
        )
        let freshLine: String = fresh.description(noun: sheet.noun).components(separatedBy: "\n")[0]
        let expectedFresh: String = try contractSentence("classDatesToRememberForAMeeting", course: code, section: 1)
            .replacingOccurrences(of: "2026-12-15 (Tuesday)", with: "2026-11-24 (Tuesday)")
        XCTAssertEqual(freshLine, expectedFresh)
        XCTAssertFalse(saysClass(fresh.description(noun: sheet.noun)), fresh.description(noun: sheet.noun))
        XCTAssertTrue(saysClass(fresh.description), fresh.description)

        try SectionTimetableStore.applyRememberTimetable(fresh)
        let same: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
            dates: tuesdays, source: "block H", forSection: 1, in: club.course
        )
        XCTAssertTrue(same.changesNothing)
        XCTAssertEqual(
            same.description(noun: sheet.noun),
            try contractSentence("classDatesAlreadyRecordedForAMeeting", course: code, section: 1)
        )

        // The trail line when a remembered list holds a date that cannot be one.
        let fileURL: URL = SectionTimetableStore.fileURL(forSection: 1, in: club.course)
        let stored: [String: Any] = ["section": 1, "dates": ["2569-09-08"], "source": "block H", "recorded": "2026-09-01"]
        try JSONSerialization.data(withJSONObject: stored).write(to: fileURL)
        let trailBefore: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertNil(try SectionTimetableStore.read(forSection: 1, in: club.course))
        let trailAfter: String = ActivityTrail.store.activityText(includingPrompts: true)
        let newTrail: String = String(trailAfter.dropFirst(trailBefore.count))
        XCTAssertTrue(
            newTrail.contains(try contractSentence("classDatesSetAsideForAMeeting", course: code, section: 1)),
            newTrail
        )

        // A course that cannot be found is known as a club by its code.
        XCTAssertEqual(
            SectionScheduleCourseMissingView(courseCode: "ROBOTICS").message,
            try contractSentence("classDatesCourseMissingForAMeeting", course: "ROBOTICS", section: 1)
        )
        XCTAssertEqual(
            SectionScheduleCourseMissingView(courseCode: "ICS3U").message,
            try contractSentence("classDatesCourseMissing", course: "ICS3U", section: 1)
        )
    }

    /// The trail's "ran from a menu" line names the item as the club's menu
    /// bar draws it (`itemTitles` → `ranFromAMenuCases`). MUST FAIL with the
    /// path's item title read in the ordinary noun.
    func testTheRanFromAMenuPathSaysMeetingInAClub() throws {
        let layout: [String: Any] = try SubjectMenuLayoutTests.layout()
        let itemTitles: [String: Any] = try XCTUnwrap(layout["itemTitles"] as? [String: Any])
        let cases: [[String: String]] = try XCTUnwrap(itemTitles["ranFromAMenuCases"] as? [[String: String]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)
        for testCase in cases {
            let item: SubjectMenuRules.Item = try XCTUnwrap(SubjectMenuRules.Item(rawValue: testCase["item"] ?? ""))
            let noun: ClassNoun = try XCTUnwrap(ClassNoun(rawValue: testCase["noun"] ?? ""))
            XCTAssertEqual(SectionVerbs.menuPath(of: item, noun: noun), testCase["path"])
            XCTAssertEqual(
                SectionVerbs.ranLine(item, ending: "carried out", counts: "", noun: noun),
                (testCase["path"] ?? "") + " — carried out"
            )
        }
    }

    /// Every club sentence that names one of the items names it as the
    /// club's menu bar does: where the ordinary twin says "Classes ▸ Class
    /// Dates…", the club's says "Meetings ▸ Meeting Dates…" (#1027). Walks
    /// every club key of the contract's wording, the `…ForAMeeting` keys and
    /// the two `…MeetingsMenu` ones. MUST FAIL with a club sentence that
    /// points at "the Meetings menu" without the item's title, as before
    /// #1027.
    func testEveryClubSentenceNamesTheItemAsTheClubsMenuBarDoes() throws {
        let wording: [String: Any] = try XCTUnwrap(AssistContract.wording()["wording"] as? [String: Any])
        let listed: [String: [String: String]] = try itemTitlesInTheContract()
        var pairs: [(club: String, ordinary: String)] = []
        for key in wording.keys {
            if key.hasSuffix("ForAMeeting") {
                pairs.append((key, String(key.dropLast("ForAMeeting".count))))
            } else if key.hasSuffix("FromTheMeetingsMenu") {
                pairs.append((key, String(key.dropLast("FromTheMeetingsMenu".count)) + "FromTheMenu"))
            }
        }
        XCTAssertTrue(pairs.contains { pair in pair.club == "nothingToUndoFromTheMeetingsMenu" })
        var namesAnItem: Int = 0
        for pair in pairs {
            let club: String = try XCTUnwrap(wording[pair.club] as? String, pair.club)
            let ordinary: String = try XCTUnwrap(wording[pair.ordinary] as? String, "\(pair.club) has no \(pair.ordinary)")
            for (name, titles) in listed {
                let item: SubjectMenuRules.Item = try XCTUnwrap(SubjectMenuRules.Item(rawValue: name))
                let ordinaryPath: String = SectionVerbs.menuPath(of: item, noun: .class)
                if ordinary.contains(ordinaryPath) {
                    namesAnItem += 1
                    let clubPath: String = SectionVerbs.menuPath(of: item, noun: .meeting)
                    XCTAssertTrue(clubPath.hasSuffix(titles["titleForAMeeting"] ?? "?"), clubPath)
                    XCTAssertTrue(club.contains(clubPath), "\(pair.club) does not say \(clubPath): \(club)")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(namesAnItem, 2)
        XCTAssertEqual(
            wording["nothingToUndoFromTheMeetingsMenu"] as? String, AssistWording.nothingToUndoFromTheMenu(noun: .meeting)
        )
    }

    /// Undo Last Change's "nothing to undo", from the menu on a club's
    /// section, names the menus as the club's menu bar titles them (#1027:
    /// named from the selected section's course, like the rest). MUST FAIL
    /// with the sentence read in the ordinary noun.
    func testNothingToUndoOnAClubsSectionNamesTheMeetingsMenu() async throws {
        let club = try makeClub(noun: .meeting)
        let previousTrail: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: club.root.appendingPathComponent("trail"))
        defer {
            ActivityTrail.store = previousTrail
            SectionMenuActivity.reset()
            try? FileManager.default.removeItem(at: club.root)
        }
        let verbs: SectionVerbs = SectionVerbs(folderPath: club.root.path, siteWork: StubSiteWork())
        let nothing: AssistToolOutcome = await verbs.perform(
            SectionVerbs.undoLastChange(), item: .undoLastChange, courseCode: club.course.code, sectionNumber: 1
        )
        XCTAssertEqual(nothing.summary, AssistWording.nothingToUndoFromTheMenu(noun: .meeting))
        XCTAssertTrue(nothing.summary.contains("the Section or Meetings menu"), nothing.summary)
        XCTAssertFalse(saysClass(nothing.summary), nothing.summary)
    }

    // MARK: - What the window offers a club

    /// The sentence the declined-dates answer tells a club to say is one the
    /// matcher understands.
    func testTheSentenceAClubIsToldToSayIsMatched() throws {
        let said: String = AssistWording.datesNotGivenYet(for: .meeting)
        let quoted: String = try XCTUnwrap(
            said.components(separatedBy: "“").last?.components(separatedBy: "”").first
        )
        XCTAssertEqual(AssistCardCommand.matching(quoted)?.toolName, "read_remembered_timetable")
    }

    /// Every card on a club's shelf is answered in code — the cancel card too
    /// since #449 — so the club shelf promises nothing no routing measurement
    /// has seen.
    func testEveryCardOnAClubsShelfIsMatchedInCode() {
        let naming: ClassPageNaming = ClassPageNaming(word: "Week", scheme: .numbered)
        for noun in [ClassNoun.meeting, ClassNoun.class] {
            var seen: Int = 0
            for (_, phrasings) in AssistPromptShelfView.groups(naming: naming, noun: noun) {
                for phrasing in phrasings {
                    seen += 1
                    XCTAssertNotNil(
                        AssistCardCommand.matching(phrasing, numberedPageWord: naming.word),
                        "“\(phrasing)” goes to the model"
                    )
                    XCTAssertFalse(phrasing.contains("Unit"), phrasing)
                    XCTAssertFalse(phrasing.contains(", Day"), phrasing)
                    if noun == .meeting {
                        XCTAssertFalse(saysClass(phrasing), phrasing)
                    }
                }
            }
            XCTAssertGreaterThan(seen, 10)
        }
    }

    /// An ordinary course's shelf is the shelf it always had.
    func testAnOrdinaryCourseKeepsItsShelf() {
        let shelf: [(String, [String])] = AssistPromptShelfView.groups(
            naming: ClassPageNaming.standard, noun: .class
        )
        XCTAssertEqual(shelf.count, AssistPromptShelfView.groups.count)
        for index in 0..<shelf.count {
            XCTAssertEqual(shelf[index].0, AssistPromptShelfView.groups[index].0)
            XCTAssertEqual(shelf[index].1, AssistPromptShelfView.groups[index].1)
        }
    }

    /// "Make room for a meeting at Week 5": one number, into `unit` — and
    /// only on the course's own word or a bare number (#267 review).
    func testMakeRoomAtOneNumberIsReadIntoTheUnitSlot() {
        let command: AssistCardCommand? = AssistCardCommand.matching(
            "Make room for one meeting at Week 5", numberedPageWord: "Week"
        )
        XCTAssertEqual(command?.toolName, "make_room_for_classes")
        XCTAssertEqual(command?.arguments, ["unit": "5", "howMany": "1"])
        XCTAssertEqual(
            AssistCardCommand.matching("make room for two meetings at week 3", numberedPageWord: "Week")?.arguments,
            ["unit": "3", "howMany": "2"]
        )
        // The bare number.
        XCTAssertEqual(
            AssistCardCommand.matching("make room for a meeting at 4", numberedPageWord: "Week")?.arguments,
            ["unit": "4", "howMany": "1"]
        )
        // The course's word, not any word.
        XCTAssertEqual(
            AssistCardCommand.matching("make room for one class at Session 2", numberedPageWord: "Session")?
                .arguments,
            ["unit": "2", "howMany": "1"]
        )
        for nearMiss in [
            "make room for a meeting at period 3",
            "make room for a meeting at block 2",
            "make room for one meeting at section 2",
            "make room for one meeting at day 5",
            "make room for a class at Unit 3",
            "make room for two meeting at week 5",
            "make room for one meeting at 5 5",
            "make room for one meeting at week",
        ] {
            XCTAssertNil(
                AssistCardCommand.matching(nearMiss, numberedPageWord: "Week"),
                "“\(nearMiss)” is not this club's page and goes to the model"
            )
        }
        // The two-number shape is untouched.
        XCTAssertEqual(
            AssistCardCommand.matching("make room for two classes at Unit 3, Day 4")?.arguments,
            ["unit": "3", "atDay": "4", "howMany": "2"]
        )
    }

    /// In a Unit/Day course the one-number shape matches NOTHING, so those
    /// sentences reach the model exactly as they did before #267 — and the
    /// window's course is what says which kind of course it is.
    func testTheOneNumberShapeInAnOrdinaryCourseGoesToTheModel() throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let word: String? = made.runner.numberedPageWord(forCourse: "ICS3U")
        XCTAssertNil(word)
        for sentence in [
            "make room for one class at week 5", "make room for a class at period 3",
            "make room for a class at 3", "make room for a meeting at Week 5",
        ] {
            XCTAssertNil(AssistCardCommand.matching(sentence, numberedPageWord: word), sentence)
        }

        let club = try makeClub(noun: .meeting)
        defer { try? FileManager.default.removeItem(at: club.root) }
        XCTAssertEqual(club.runner.numberedPageWord(forCourse: club.course.code), "Week")
    }

    /// "Duplicate Week 2 as my next meeting" is the duplicate family.
    func testDuplicateAsMyNextMeetingIsMatched() {
        let command: AssistCardCommand? = AssistCardCommand.matching("Duplicate Week 2 as my next meeting")
        XCTAssertEqual(command?.toolName, "add_next_class")
        XCTAssertEqual(command?.arguments, ["duplicate": "Week 2"])
    }
}
