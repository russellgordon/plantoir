import XCTest
@testable import QuartzTeachers

/// Runs `contracts/class-planning.json` — naming, numbering, and making room
/// for a class in the middle of a unit.
///
/// **The highest-stakes data in these contracts.** Everything else describes a
/// sentence or an order of events; this describes renaming the files a
/// teacher's lessons live in. The rename ORDER in particular looks like an
/// implementation detail and is the difference between a course that survives
/// and one that loses a lesson, so it is written down where both platforms
/// read it rather than in a comment one of them will never see.
@MainActor
final class ClassPlanningContractTests: XCTestCase {

    // MARK: - Which titles carry numbers

    func testTitlesAreNumberedOrLeftAloneAsTheContractSays() throws {
        for testCase in try ClassPlanningContractTests.cases(in: "pageNaming") {
            let title: String = try XCTUnwrap(testCase["title"] as? String)
            // A case with no `term` uses the default word, which is what a
            // course says when `unit_word` is absent from its configuration.
            let term: String = ClassPageTerm.cleaned(testCase["term"] as? String)
            // A case with no `scheme` is the ordinary one — what a course
            // says when `class_page_scheme` is absent (#267).
            let scheme: ClassPageScheme = ClassPageScheme.reading(testCase["scheme"] as? String)
            let naming: ClassPageNaming = ClassPageNaming(word: term, scheme: scheme)
            let numbers: UnitDay? = UnitDay(pageTitle: title, naming: naming)
            if scheme == .numbered {
                // One number, and a runner asserts the NUMBER: that it is
                // held as unit 1 is this app's seam, not the contract's.
                XCTAssertTrue(testCase.keys.contains("expectNumber"), "\(term): \(title) names no expectNumber")
                XCTAssertEqual(numbers?.day, testCase["expectNumber"] as? Int, "\(term) (numbered): \(title)")
                if let numbers = numbers {
                    XCTAssertEqual(numbers.title.lowercased(), title.lowercased(), "\(term) (numbered): \(title)")
                }
            } else {
                XCTAssertEqual(numbers?.unit, testCase["expectUnit"] as? Int, "\(term): \(title)")
                XCTAssertEqual(numbers?.day, testCase["expectDay"] as? Int, "\(term): \(title)")
            }
        }
    }

    func testNumberedClassesSortByUnitThenDay() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("numberedClassOrder")
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        for title in try XCTUnwrap(section["input"] as? [String]) {
            try writeClass(title, on: "2026-09-08", in: course)
        }
        let sorted: [ClassPageSummary] = ClassInsertionPlanner.numberedClasses(
            among: ClassPages.list(forSection: 1, in: course)
        )
        var titles: [String] = []
        for page in sorted {
            titles.append(page.title)
        }
        XCTAssertEqual(titles, try XCTUnwrap(section["expectOrder"] as? [String]))
    }

    /// The same order under the one-number scheme (#267).
    func testNumberedSchemeClassesSortByNumber() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("numberedClassOrder")
        let numbered: [String: Any] = try XCTUnwrap(section["numberedScheme"] as? [String: Any])
        let (root, _, course) = try makeWorkspace(
            word: numbered["word"] as? String, scheme: numbered["scheme"] as? String
        )
        defer { try? FileManager.default.removeItem(at: root) }

        for title in try XCTUnwrap(numbered["input"] as? [String]) {
            try writeClass(title, on: "2026-09-08", in: course)
        }
        let sorted: [ClassPageSummary] = ClassInsertionPlanner.numberedClasses(
            among: ClassPages.list(forSection: 1, in: course)
        )
        var titles: [String] = []
        for page in sorted {
            titles.append(page.title)
        }
        XCTAssertEqual(titles, try XCTUnwrap(numbered["expectOrder"] as? [String]))
    }

    // MARK: - What the next class would be called

    func testTheNextClassIsNamedAsTheContractSays() throws {
        for testCase in try ClassPlanningContractTests.cases(in: "nextClass") {
            let (root, _, course) = try makeWorkspace(
                word: testCase["word"] as? String, scheme: testCase["scheme"] as? String
            )
            defer { try? FileManager.default.removeItem(at: root) }

            for title in try XCTUnwrap(testCase["existing"] as? [String]) {
                try writeClass(title, on: "2026-09-08", in: course)
            }
            let naming: ClassPageNaming = course.configuration.classPageNaming
            let next: UnitDay = NextClassPlanner.nextUnitAndDay(
                after: ClassPages.list(forSection: 1, in: course), naming: naming
            )
            let what: String = (try XCTUnwrap(testCase["existing"] as? [String])).joined(separator: " / ")
            if naming.isNumbered {
                // One number (#267): assert it, and the title the course's
                // word makes of it — never a unit, and never a Day.
                let number: Int = try XCTUnwrap(testCase["expectNumber"] as? Int, "after [\(what)]")
                XCTAssertEqual(next.day, number, "after [\(what)]")
                XCTAssertEqual(next.title, "\(naming.word) \(number)", "after [\(what)]")
                continue
            }
            XCTAssertEqual(next.unit, testCase["expectUnit"] as? Int, "after [\(what)]")
            XCTAssertEqual(next.day, testCase["expectDay"] as? Int, "after [\(what)]")
        }
    }

    // MARK: - Making room

    func testInsertionPlansMatchTheContract() throws {
        for testCase in try ClassPlanningContractTests.cases(in: "insertion") {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let (root, _, course) = try makeWorkspace(
                meetingDates: try XCTUnwrap(testCase["timetable"] as? [String]),
                word: testCase["word"] as? String, scheme: testCase["scheme"] as? String
            )
            defer { try? FileManager.default.removeItem(at: root) }

            for existing in try XCTUnwrap(testCase["existingClasses"] as? [[String: String]]) {
                try writeClass(
                    try XCTUnwrap(existing["title"]), on: try XCTUnwrap(existing["date"]), in: course
                )
            }

            let position: (unit: Int, day: Int) = try ClassPlanningContractTests.position(of: testCase)
            let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
                unit: position.unit,
                atDay: position.day,
                count: try XCTUnwrap(testCase["count"] as? Int),
                forSection: 1,
                in: course
            )

            // The order is the assertion. Highest day first, so every
            // destination has been vacated before it is needed.
            var renames: [String] = []
            for rename in plan.renames {
                renames.append("\(rename.from) → \(rename.to)")
            }
            XCTAssertEqual(
                renames, try XCTUnwrap(testCase["expectRenamesInOrder"] as? [String]),
                "\(name): renames, in order"
            )

            if let expected = testCase["expectDateMoves"] as? [String] {
                var moved: [String] = []
                for move in plan.moves {
                    moved.append(move.title)
                }
                for title in expected {
                    XCTAssertTrue(moved.contains(title), "\(name): \(title) should have moved date")
                }
            }

            // Where a move lands, and what does not move at all (#267: a
            // numbered course keeps its date gaps).
            if let movedTo = testCase["expectMovedTo"] as? [String: String] {
                for (title, date) in movedTo {
                    var landed: String? = nil
                    for move in plan.moves where move.title == title {
                        landed = move.to.text
                    }
                    XCTAssertEqual(landed, date, "\(name): where \(title) moves to")
                }
            }
            if let notMoved = testCase["expectNotMoved"] as? [String] {
                for move in plan.moves {
                    XCTAssertFalse(
                        notMoved.contains(move.title),
                        "\(name): \(move.title) must keep its date, and was moved from "
                        + "\(move.from?.text ?? "none") to \(move.to.text)"
                    )
                }
            }

            if let mentions = testCase["expectProblemMentions"] as? String {
                let said: String = plan.problems.joined(separator: " ")
                XCTAssertTrue(
                    said.contains(mentions),
                    "\(name): the plan must warn about pages it left alone — it said \"\(said)\""
                )
            }
        }
    }

    func testTheRefusalsAreTheOnesTheContractNames() throws {
        for testCase in try ClassPlanningContractTests.cases(in: "refusals") {
            let (root, _, course) = try makeWorkspace(
                word: testCase["word"] as? String, scheme: testCase["scheme"] as? String
            )
            defer { try? FileManager.default.removeItem(at: root) }
            try writeClass(
                course.configuration.classPageNaming.title(unit: 1, day: 1), on: "2026-09-08", in: course
            )

            let expected: String = try XCTUnwrap(testCase["expectProblem"] as? String)
            do {
                if testCase["startANewUnit"] as? Bool == true {
                    _ = try NextClassPlanner.plan(forSection: 1, in: course, startingANewUnit: true)
                } else if let unit = testCase["addDaysToUnit"] as? Int {
                    _ = try NextClassPlanner.plan(
                        addingDays: try XCTUnwrap(testCase["count"] as? Int), toUnit: unit,
                        forSection: 1, in: course
                    )
                } else {
                    let position: (unit: Int, day: Int) = try ClassPlanningContractTests.position(of: testCase)
                    _ = try ClassInsertionPlanner.plan(
                        unit: position.unit,
                        atDay: position.day,
                        count: try XCTUnwrap(testCase["count"] as? Int),
                        forSection: 1,
                        in: course
                    )
                }
                XCTFail("Should have been refused as \(expected)")
            } catch let problem as ClassInsertionPlanner.Problem {
                XCTAssertEqual(ClassPlanningContractTests.name(of: problem), expected)
            } catch let problem as NextClassPlanner.Problem {
                XCTAssertEqual(ClassPlanningContractTests.name(of: problem), expected)
            }
        }
    }

    /// Where "make room" lands in a numbered course, read from the tool's
    /// two arguments (#267).
    func testTheNumberedMakeRoomPositionIsReadAsTheContractSays() throws {
        let insertion: [String: Any] = try ClassPlanningContractTests.section("insertion")
        let reading: [String: Any] = try XCTUnwrap(insertion["numberedPosition"] as? [String: Any])
        for testCase in try XCTUnwrap(reading["cases"] as? [[String: Any]]) {
            let unit: Int? = testCase["unit"] as? Int
            let atDay: Int? = testCase["atDay"] as? Int
            XCTAssertEqual(
                ClassInsertionPlanner.numberedPosition(unit: unit, atDay: atDay),
                testCase["expect"] as? Int,
                "unit \(String(describing: unit)), atDay \(String(describing: atDay))"
            )
        }
    }

    // MARK: - Duplicating a lesson as the next class

    /// The three `duplication` cases, run through the REAL tool.
    ///
    /// **Not through a re-implementation of the rule, and the undo is ASKED
    /// for rather than read off a list.** What the contract fixes is what a
    /// teacher gets when they say "undo that", and a test that inspected the
    /// history would pass on a change that recorded an entry the undo path
    /// then declined to honour. `MakeRoomForClassesTests` makes the same
    /// argument about the tool it covers.
    func testDuplicatingMatchesTheContract() async throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("duplication")
        // The rule the cases are cases OF, read rather than restated. A rule
        // nobody explained is a rule the next reader simplifies away.
        let undoRule: [String: Any] = try XCTUnwrap(section["undoRule"] as? [String: Any])
        let statedRule: String = try XCTUnwrap(undoRule["rule"] as? String)
        XCTAssertNotNil(undoRule["why"] as? String, "undoRule has no 'why'")
        let forcedUnpublished: Bool =
            (section["forcedUnpublished"] as? [String: Any])?["value"] as? Bool == true

        for testCase in try ClassPlanningContractTests.cases(in: "duplication") {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let made = try AssistFixture.makeRunner()
            defer { try? FileManager.default.removeItem(at: made.root) }
            try ClassPlanningContractTests.name(
                made.course, word: testCase["word"] as? String, scheme: testCase["scheme"] as? String
            )
            try rememberTimetable(
                try XCTUnwrap(testCase["timetable"] as? [String]), in: made.course
            )

            // Every page gets a body of its own, so a rename can be checked by
            // where the WORDS ended up rather than by trusting the planner to
            // have moved what it said it moved.
            for existing in try XCTUnwrap(testCase["existingClasses"] as? [[String: String]]) {
                let title: String = try XCTUnwrap(existing["title"])
                try AssistFixture.write(
                    page: title, publish: "true", date: try XCTUnwrap(existing["date"]),
                    body: "the words of \(title)", in: made.course
                )
            }

            // Asked of the plan BEFORE anything runs, because a plan changes
            // nothing: the rename order is the contract's highest-stakes
            // field and the number on the card is read from the same object.
            let source: String = try XCTUnwrap(testCase["duplicate"] as? String)
            let numbers: UnitDay = try XCTUnwrap(
                UnitDay(pageTitle: source, naming: made.course.configuration.classPageNaming), name
            )
            let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
                unit: numbers.unit, atDay: numbers.day + 1, count: 1,
                forSection: 1, in: made.course
            )
            var renames: [String] = []
            for rename in plan.renames {
                renames.append("\(rename.from) → \(rename.to)")
            }
            XCTAssertEqual(
                renames, try XCTUnwrap(testCase["expectRenamesInOrder"] as? [String]),
                "\(name): renames, in order"
            )
            XCTAssertEqual(
                plan.otherClassesMoving, testCase["expectOtherClassesMoving"] as? Int,
                "\(name): how many other classes the card says move"
            )
            // The gate itself, against the rule the contract states in words:
            // an undo is offered exactly when nothing else moves.
            let undoOffered: Bool = try XCTUnwrap(testCase["expectUndoOffered"] as? Bool)
            XCTAssertEqual(
                plan.movesAnythingElse, !undoOffered,
                "\(name): the contract's rule is “\(statedRule)” — this plan has "
                + "\(plan.renames.count) renames and \(plan.moves.count) date moves"
            )

            let said: String = await run(
                made.runner, "add_next_class",
                ["course": "ICS3U", "section": 1, "duplicate": source]
            )

            let newTitle: String = try XCTUnwrap(testCase["expectNewTitle"] as? String)
            let copyURL: URL = AssistFixture.pageURL(of: newTitle, in: made.course)
            let copy: String = try XCTUnwrap(
                try? String(contentsOf: copyURL, encoding: .utf8),
                "\(name): no copy was made at \(newTitle) — \(said)"
            )
            XCTAssertTrue(
                copy.contains("the words of \(source)"), "\(name): the copy is not a copy"
            )
            XCTAssertTrue(
                copy.contains("created: \(try XCTUnwrap(testCase["expectDate"] as? String))"),
                "\(name): the copy is dated for the wrong day — \(copy)"
            )
            if forcedUnpublished {
                XCTAssertFalse(
                    AssistPageVisibility.publishes(in: copy, forSection: 1),
                    "\(name): a copy of a published lesson must start hidden"
                )
            }

            // A rename really happened when the renamed page holds the words
            // the OLD name's page held.
            for step in try XCTUnwrap(testCase["expectRenamesInOrder"] as? [String]) {
                let parts: [String] = step.components(separatedBy: " → ")
                let from: String = try XCTUnwrap(parts.first)
                let to: String = try XCTUnwrap(parts.last)
                let moved: String = try XCTUnwrap(
                    try? String(contentsOf: AssistFixture.pageURL(of: to, in: made.course),
                                encoding: .utf8),
                    "\(name): \(to) is not there"
                )
                XCTAssertTrue(
                    moved.contains("the words of \(from)"), "\(name): \(from) did not become \(to)"
                )
            }

            let undone: String = await run(made.runner, "undo_last_change", [:])
            if undoOffered {
                XCTAssertNotEqual(
                    undone, AssistWording.nothingToUndo,
                    "\(name): nothing else moved, so the copy must be takeable back"
                )
                // Taken AWAY, not blanked. `aCreatedPageCanBeTakenBack` says
                // "takes the page away again", and a blank class page left
                // standing is a sentence a teacher would believe and that
                // would not be true.
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: copyURL.path),
                    "\(name): the undo left a blank class page where the copy was"
                )
            } else {
                XCTAssertEqual(
                    undone, AssistWording.nothingToUndo,
                    "\(name): a partial undo is worse than none — \(undone)"
                )
                XCTAssertTrue(
                    said.contains(AssistWording.otherClassesMoved),
                    "\(name): the reply must say where the way back is — \(said)"
                )
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: copyURL.path),
                    "\(name): nothing may have been half-undone"
                )
            }
        }
    }

    /// The copy starts hidden even when the page it was copied from carries a
    /// per-section publish key.
    ///
    /// The plain `publish: false` the copy is given is NOT the last word: the
    /// build consults `publishForSection<N>` first, so a source carrying
    /// `publishForSection1: true` — which the page a teacher names may well
    /// be, since a shared course-level page is nameable here — leaves the copy
    /// visible to students the moment it exists, with the FILE still reading
    /// `publish: false`. Measured through the real toolchain image; the table
    /// is in `documentation/10-local-ai-assistant.md`.
    func testTheCopyIsHiddenEvenWhenItsSourceCarriesAPerSectionKey() async throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("duplication")
        let forced: [String: Any] = try XCTUnwrap(section["forcedUnpublished"] as? [String: Any])
        try XCTSkipUnless(forced["value"] as? Bool == true)

        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try rememberTimetable(
            ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16"], in: made.course
        )
        // Written by hand: `AssistFixture.write` builds a fixed template of
        // title, publish and created, and the whole point here is the key it
        // does not have.
        try writeRawPage(
            """
            ---
            title: Unit 1, Day 1
            publish: true
            publishForSection1: true
            created: 2026-09-08T07:00:00.000-0400
            ---

            a lesson that started life as a shared page
            """,
            named: "Unit 1, Day 1", in: made.course
        )

        _ = await run(
            made.runner, "add_next_class",
            ["course": "ICS3U", "section": 1, "duplicate": "Unit 1, Day 1"]
        )

        let copy: String = try XCTUnwrap(try? String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 2", in: made.course), encoding: .utf8
        ))
        XCTAssertFalse(
            AssistPageVisibility.publishes(in: copy, forSection: 1),
            "The copy was visible to students the moment it was made: \(copy)"
        )
        XCTAssertEqual(
            AssistPageVisibility.answer(in: copy, forSection: 1), .hidden,
            "Hidden has to be CERTAIN here, not merely unsaid: \(copy)"
        )

        // **And the copy can still be PUBLISHED.** Hiding it by writing a
        // per-section key of its own would pass every assertion above and
        // leave a page nobody can ever publish: the publish path picks its key
        // from where the page LIVES, so it writes the plain one, and the
        // per-section key goes on beating it — while the teacher is told
        // "Published 1 page" every time they ask. A failure that reports
        // success is worse than the one it replaced.
        let said: String = await run(
            made.runner, "publish_pages",
            ["course": "ICS3U", "section": 1, "pages": ["Unit 1, Day 2"]]
        )
        let published: String = try XCTUnwrap(try? String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 2", in: made.course), encoding: .utf8
        ))
        XCTAssertTrue(
            AssistPageVisibility.publishes(in: published, forSection: 1),
            "The copy was hidden in a way that cannot be undone — \(said)\n\(published)"
        )
        // Asked of the frontmatter LINES, not of the whole file: a page shaped
        // like the example content's `_DUPLICATE ME.md` names the key in a
        // `%%` comment in its body, and a substring test would fail on the one
        // page most likely to be duplicated.
        XCTAssertTrue(
            ClassPlanningContractTests.perSectionKeys(in: published).isEmpty,
            "No per-section key belongs on a page inside one section's own folder: \(published)"
        )
    }

    /// A source this app cannot read well enough to be sure of is ABANDONED
    /// rather than copied.
    ///
    /// **A tab used as indentation reaches it**, which is not a corner: the
    /// reader answers `.unreadable` there because the build's own parser
    /// throws on the same page, so nothing this writes can make the copy
    /// certainly hidden. A copy of a lesson students can already see is the
    /// one thing that must not be written on a guess.
    ///
    /// The other half of the assertion is what the teacher is LEFT with. The
    /// room has been made by the time this is answered, so the planner's blank
    /// class page is standing on the copy's day — hidden, which is the safe
    /// end state — and nothing goes on the undo list, because taking back a
    /// page this never wrote is not something an undo can honour.
    func testASourceThisAppCannotReadIsNotCopiedAtAll() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let scratchFolderURL: URL = made.root.appendingPathComponent("trail")
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer { ActivityTrail.store = previousStore }

        try rememberTimetable(["2026-09-08", "2026-09-10", "2026-09-14"], in: made.course)
        // The tab is the whole fixture. Everything else about this page is
        // ordinary, and it is published, which is what makes the copy
        // dangerous.
        try writeRawPage(
            "---\ntitle: Unit 1, Day 1\ntags:\n\t- a\npublish: true\n"
            + "created: 2026-09-08T07:00:00.000-0400\n---\n\nthe words of Unit 1, Day 1\n",
            named: "Unit 1, Day 1", in: made.course
        )

        let said: String = await run(
            made.runner, "add_next_class",
            ["course": "ICS3U", "section": 1, "duplicate": "Unit 1, Day 1"]
        )

        XCTAssertEqual(
            said,
            AssistWording.theCopyCouldNotBeMadeHidden(
                page: "Unit 1, Day 1", as: "Unit 1, Day 2",
                backupNamed: ClassPlanningContractTests.backupName(in: said)
            ),
            "The refusal is the contract's sentence, not one of its own: \(said)"
        )

        let standing: String = try XCTUnwrap(try? String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 2", in: made.course), encoding: .utf8
        ), "The planner's blank page should still be there")
        XCTAssertFalse(
            standing.contains("the words of Unit 1, Day 1"),
            "The copy was written after all: \(standing)"
        )
        XCTAssertEqual(
            AssistPageVisibility.answer(in: standing, forSection: 1), .hidden,
            "What is left standing must be certainly hidden: \(standing)"
        )

        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("did not copy a class"),
            "A duplicate abandoned after the room was made must leave a line: \(trail)"
        )

        let undone: String = await run(made.runner, "undo_last_change", [:])
        XCTAssertEqual(
            undone, AssistWording.nothingToUndo,
            "Nothing was copied, so nothing may be offered back: \(undone)"
        )
    }

    /// A lesson still sitting where the copy would go is never written over.
    ///
    /// **Deterministic, and it has to be**, because the shape only arises when
    /// the planner skips a rename. A page it cannot read stops the rename
    /// above it, which leaves the next destination occupied, which stops that
    /// rename too — and the page the copy was meant to BECOME is still
    /// somebody's class when the copy is written. The refusal also has to
    /// survive the planner's link rewriting, which changes the destination's
    /// own text: a guard that asked "is this still the same words?" would
    /// answer no and take the lesson.
    func testALessonStillSittingWhereTheCopyWouldGoIsNeverWrittenOver() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        let scratchFolderURL: URL = made.root.appendingPathComponent("trail")
        try FileManager.default.createDirectory(at: scratchFolderURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer { ActivityTrail.store = previousStore }

        try rememberTimetable(
            ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16", "2026-09-18",
             "2026-09-22", "2026-09-24", "2026-09-28", "2026-09-30"],
            in: made.course
        )
        let dates: [String] = ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16",
                               "2026-09-18", "2026-09-22"]
        for day in 1...6 {
            try AssistFixture.write(
                page: "Unit 1, Day \(day)", publish: "true", date: dates[day - 1],
                body: day == 3
                    ? "a real lesson that links to [[Unit 1, Day 6]]"
                    : "the words of Unit 1, Day \(day)",
                in: made.course
            )
        }
        // Day 5 cannot be read at all, which is what stops the rename above it.
        try Data([0xFF, 0xFE, 0x41]).write(
            to: AssistFixture.pageURL(of: "Unit 1, Day 5", in: made.course)
        )

        let said: String = await run(
            made.runner, "add_next_class",
            ["course": "ICS3U", "section": 1, "duplicate": "Unit 1, Day 2"]
        )

        let lesson: String = try XCTUnwrap(try? String(
            contentsOf: AssistFixture.pageURL(of: "Unit 1, Day 3", in: made.course), encoding: .utf8
        ))
        XCTAssertTrue(
            lesson.contains("a real lesson that links to"),
            "The lesson was written over by the copy: \(lesson)"
        )
        XCTAssertTrue(said.contains("Unit 1, Day 3"), "The refusal must say which page: \(said)")
        XCTAssertEqual(
            said,
            AssistWording.thePlaceForTheCopyIsStillTaken(
                page: "Unit 1, Day 3",
                backupNamed: ClassPlanningContractTests.backupName(in: said)
            ),
            "The refusal is the contract's sentence, not one of its own: \(said)"
        )

        // The room HAD been made by the time it refused, so the trail carries
        // the one line that explains classes that moved with no copy to show
        // for it.
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains("did not copy a class"),
            "A refusal after a half-applied shuffle must leave a line: \(trail)"
        )
    }

    /// The plan card says how many classes move even when nothing is renamed.
    ///
    /// Contract case 2's shape. Keyed on the rename count the card said
    /// nothing at all here, and this is the card a teacher agrees to.
    func testThePlanSaysHowManyClassesMoveWhenNothingIsRenamed() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try rememberTimetable(
            ["2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14", "2026-09-16", "2026-09-18"],
            in: made.course
        )
        for existing in [("Unit 1, Day 1", "2026-09-08"), ("Unit 1, Day 2", "2026-09-10"),
                         ("Unit 2, Day 1", "2026-09-12"), ("Unit 2, Day 2", "2026-09-14")] {
            try AssistFixture.write(
                page: existing.0, publish: "true", date: existing.1,
                body: "the words of \(existing.0)", in: made.course
            )
        }

        let card: String = await card(
            made.runner, "plan_add_next_class",
            ["course": "ICS3U", "section": 1, "duplicate": "Unit 1, Day 2"]
        )
        XCTAssertTrue(
            card.contains(AssistWording.otherClassesWouldMove(moving: 2, renaming: 0)),
            "Two classes are about to be re-dated and the card did not say so: \(card)"
        )
    }

    /// And still says the links are rewritten when something IS renamed.
    ///
    /// Contract case 1's shape. True before this was touched; it is here so a
    /// refactor cannot lose the branch that was already right.
    func testThePlanStillSaysLinksAreRewrittenWhenSomethingIsRenamed() async throws {
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }
        try rememberTimetable(
            ["2026-09-08", "2026-09-10", "2026-09-12", "2026-09-14", "2026-09-16"], in: made.course
        )
        for existing in [("Unit 1, Day 1", "2026-09-08"), ("Unit 1, Day 2", "2026-09-10"),
                         ("Unit 2, Day 1", "2026-09-12")] {
            try AssistFixture.write(
                page: existing.0, publish: "true", date: existing.1,
                body: "the words of \(existing.0)", in: made.course
            )
        }

        let card: String = await card(
            made.runner, "plan_add_next_class",
            ["course": "ICS3U", "section": 1, "duplicate": "Unit 1, Day 1"]
        )
        XCTAssertTrue(
            card.contains(AssistWording.otherClassesWouldMove(moving: 2, renaming: 1)),
            "One page is renamed and two move, and the card must say both: \(card)"
        )
    }

    // MARK: - Private

    /// The backup's file name as the refusal names it, or nil when it names
    /// none — so the assertion above compares the whole sentence rather than
    /// re-deriving a path the test fixture chose.
    /// Every per-section key this page carries as a top-level frontmatter
    /// line, asked through the app's own matcher rather than by looking for
    /// the word anywhere in the file.
    private static func perSectionKeys(in pageText: String) -> [String] {
        guard let block = PageFrontmatter.block(in: pageText) else {
            return []
        }
        let lines: [String] = pageText.components(separatedBy: "\n")
        var found: [String] = []
        for index in (block.openIndex + 1)..<block.closeIndex {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(lines[index])
            if bare.hasPrefix(" ") || bare.hasPrefix("\t") {
                continue
            }
            if let key = AssistPageVisibility.perSectionKey(namedIn: bare) {
                found.append(key)
            }
        }
        return found
    }

    private static func backupName(in sentence: String) -> String? {
        for word in sentence.components(separatedBy: " ") {
            let bare: String = word.trimmingCharacters(in: CharacterSet(charactersIn: ",."))
            if bare.hasSuffix(".zip") {
                return bare
            }
        }
        return nil
    }

    @MainActor
    private func rememberTimetable(_ dates: [String], in course: Course) throws {
        try SectionTimetableStore.applyRememberTimetable(
            try SectionTimetableStore.planRememberTimetable(
                dates: dates, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
        )
    }

    @MainActor
    private func writeRawPage(_ text: String, named title: String, in course: Course) throws {
        try text.write(
            to: AssistFixture.pageURL(of: title, in: course), atomically: true, encoding: .utf8
        )
    }

    @MainActor
    private func run(
        _ runner: AssistToolRunner, _ tool: String, _ arguments: [String: Any]
    ) async -> String {
        return await outcome(runner, tool, arguments).detail
    }

    /// What a plan card actually shows, which is not the same string as the
    /// summary a caller reads back.
    @MainActor
    private func card(
        _ runner: AssistToolRunner, _ tool: String, _ arguments: [String: Any]
    ) async -> String {
        return await outcome(runner, tool, arguments).forTheCard
    }

    @MainActor
    private func outcome(
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

    private static func name(of problem: NextClassPlanner.Problem) -> String {
        switch problem {
        case .noTimetable:
            return "noTimetable"
        case .noUnitsInANumberedCourse:
            return "noUnitsInANumberedCourse"
        }
    }

    /// Where a case makes room: `insertAtNumber` for a numbered course
    /// (#267), which this app holds as unit 1 — the contract names only the
    /// number — or `insertAtUnit` and `insertAtDay`.
    private static func position(of testCase: [String: Any]) throws -> (unit: Int, day: Int) {
        if let number = testCase["insertAtNumber"] as? Int {
            return (1, number)
        }
        return (
            try XCTUnwrap(testCase["insertAtUnit"] as? Int),
            try XCTUnwrap(testCase["insertAtDay"] as? Int)
        )
    }

    /// Give a fixture course a case's word and scheme, on disk and in memory.
    @MainActor
    private static func name(_ course: Course, word: String?, scheme: String?) throws {
        if word == nil && scheme == nil {
            return
        }
        if let word {
            course.configuration.unitWord = word
        }
        if let scheme {
            course.configuration.classPageScheme = ClassPageScheme.reading(scheme)
        }
        try course.configuration.write(to: course.directoryURL.appendingPathComponent("course_config.json"))
    }

    private static func name(of problem: ClassInsertionPlanner.Problem) -> String {
        switch problem {
        case .unitOutOfRange:
            return "unitOutOfRange"
        case .dayOutOfRange:
            return "dayOutOfRange"
        case .countOutOfRange:
            return "countOutOfRange"
        case .noTimetable:
            return "noTimetable"
        case .noNumberedClasses:
            return "noNumberedClasses"
        default:
            return "other"
        }
    }

    private func makeWorkspace(
        meetingDates: [String] = ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16",
                                  "2026-09-18", "2026-09-22"],
        word: String? = nil,
        scheme: String? = nil,
        sectionNumbers: [Int] = [1]
    ) throws -> (root: URL, coursesURL: URL, course: Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("class-planning-contract-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")
        for sectionNumber in sectionNumbers {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent("section\(sectionNumber)/All Classes"),
                withIntermediateDirectories: true
            )
        }
        var configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": sectionNumbers,
            "num_sections": sectionNumbers.count,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        if let word {
            configuration["unit_word"] = word
        }
        if let scheme {
            configuration["class_page_scheme"] = scheme
        }
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        let loaded: CourseConfiguration = try CourseConfiguration(
            contentsOf: courseURL.appendingPathComponent("course_config.json")
        )
        let course: Course = Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
        if !meetingDates.isEmpty {
            let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
                dates: meetingDates, source: "timetable.xlsx, block H", forSection: 1, in: course
            )
            try SectionTimetableStore.applyRememberTimetable(plan)
        }
        return (root, coursesURL, course)
    }

    private func writeClass(_ title: String, on date: String, in course: Course, section: Int = 1) throws {
        let page: String = """
        ---
        title: \(title)
        publish: true
        created: \(date)T07:00:00.000-0400
        ---

        \(title)
        """
        try page.write(
            to: ClassPages.folderURL(forSection: section, in: course).appendingPathComponent(title + ".md"),
            atomically: true, encoding: .utf8
        )
    }

    // MARK: - Dating the pages a class brings

    /// The frontmatter key, which differs by where the page lives.
    ///
    /// A page inside the section's own folder carries `created`; a course-level
    /// page shared between sections carries one key PER SECTION. Getting this
    /// wrong dates the page for a section the teacher was not talking about.
    func testTheDateKeyIsTheOneTheContractNames() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("datingPagesAClassBrings")
        let keys: [String: Any] = try XCTUnwrap(section["frontmatterKey"] as? [String: Any])

        XCTAssertEqual(
            PageFrontmatter.createdKey(forSection: 1, isSectionLocal: true),
            keys["sectionLocalPage"] as? String
        )
        let shared: String = try XCTUnwrap(keys["courseLevelPage"] as? String)
        for number in [1, 2, 7] {
            XCTAssertEqual(
                PageFrontmatter.createdKey(forSection: number, isSectionLocal: false),
                shared.replacingOccurrences(of: "<N>", with: "\(number)")
            )
        }
    }

    /// The rule itself, run against the real planner: what moves, what does
    /// not, and which class claims a page several of them bring.
    @MainActor
    func testPagesAClassBringsMoveExactlyAsTheContractSays() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("datingPagesAClassBrings")

        let earlier: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-10-06"))
        let later: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-12-01"))
        let old: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-08-01"))

        func page(_ title: String, visible: Bool, day: CalendarDay?,
                  links: [String], folder: String) -> AssistSectionPage {
            return AssistSectionPage(
                title: title,
                displayTitle: title,
                fileURL: URL(fileURLWithPath: "/courses/ICS3U/\(folder)/\(title).md"),
                relativePath: "courses/ICS3U/\(folder)/\(title).md",
                isSectionLocal: folder.contains("Classes"),
                isVisibleToStudents: visible,
                visibilityIsCertain: true,
                date: day,
                linkedTitles: links.map { $0.lowercased() },
                classFolderNames: ["All Classes"],
                pathWithinSection: "\(folder)/\(title).md"
            )
        }

        let graph: AssistSectionGraph = AssistSectionGraph(
            courseCode: "ICS3U", sectionNumber: 1,
            pages: [
                page("Unit 2, Day 3", visible: false, day: earlier,
                     links: ["never seen", "already out"], folder: "section1/All Classes"),
                page("Unit 4, Day 2", visible: false, day: later,
                     links: ["never seen"], folder: "section1/All Classes"),
                page("never seen", visible: false, day: old, links: [], folder: "Concepts"),
                page("already out", visible: true, day: old, links: [], folder: "Concepts"),
            ]
        )
        func summary(_ title: String, _ day: CalendarDay) -> ClassPageSummary {
            return ClassPageSummary(
                title: title,
                fileURL: URL(fileURLWithPath: "/courses/ICS3U/section1/All Classes/\(title).md"),
                date: day
            )
        }
        let classes: [ClassPageSummary] = [
            summary("Unit 2, Day 3", earlier),
            summary("Unit 4, Day 2", later),
        ]

        // Named LATEST first — the earliest must still claim the shared page.
        let moves: [AssistPublishDateMove] = AssistPublishPlanner.dateMovesFollowingClasses(
            titles: ["Unit 4, Day 2", "Unit 2, Day 3"], graph: graph, classPages: classes
        )

        var moved: [String: String] = [:]
        for move in moves {
            moved[move.page.lowercasedTitle] = move.to.text
        }

        if (section["sharedPagesMoveToo"] as? [String: Any])?["value"] as? Bool == true {
            XCTAssertEqual(moved["never seen"], "2026-10-06",
                           "A never-seen page did not take the earliest class's date")
        }
        XCTAssertNil(moved["already out"],
                     "A page students can already see was re-dated underneath them")
        XCTAssertNil(moved["unit 2, day 3"], "A class was moved off its own day")
        XCTAssertNil(moved["unit 4, day 2"], "A class was moved off its own day")
    }

    /// The date half of the stop decided in issue #173.
    ///
    /// The CASES are run against a real course, through `publish_pages`, in
    /// `AssistToolRunnerTests.testTheDatesAClassBringsStopAtAClassAsTheContractSays`
    /// — the same split this file's sibling in `shared-rules.json` makes, and
    /// for the same reason: a synthetic page graph can be built to agree with
    /// whatever it is asked. What is pinned here is that the file says it, says
    /// why, and lists the stop among the reasons a page does not move.
    func testTheReachStopsAtAClassPageAndTheRuleSaysSo() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("datingPagesAClassBrings")
        let stop: [String: Any] = try XCTUnwrap(section["reachStopsAtAClassPage"] as? [String: Any])
        XCTAssertEqual(stop["value"] as? Bool, true)
        XCTAssertNotNil(stop["why"] as? String)

        var saysTheWalkStops: Bool = false
        for reason in try XCTUnwrap(section["doesNotMoveWhen"] as? [String]) {
            if reason.contains("only THROUGH another class page") {
                saysTheWalkStops = true
            }
        }
        XCTAssertTrue(
            saysTheWalkStops,
            "doesNotMoveWhen does not name the page a different class brings"
        )
    }

    // MARK: - Dating non-class pages

    func testNonClassPagesContractExistsAndIsDocumented() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("datingNonClassPages")
        XCTAssertNotNil(section["note"])
        let appliesTo: [String] = try XCTUnwrap(section["appliesTo"] as? [String])
        XCTAssertFalse(appliesTo.isEmpty)
        XCTAssertNotNil(section["dateInherited"])
        XCTAssertNotNil(section["why"])
    }

    // MARK: - Renaming the word for a unit

    /// Which pages a rename of the course's word moves, and what refuses it.
    /// Each case builds its own course, so the rule is run against real files
    /// rather than against a list of titles.
    func testRenamingTheUnitWordCases() throws {
        for testCase in try ClassPlanningContractTests.cases(in: "renamingTheUnitWord") {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let from: String = try XCTUnwrap(testCase["from"] as? String)
            let to: String = try XCTUnwrap(testCase["to"] as? String)
            let pages: [[String: Any]] = try XCTUnwrap(testCase["pages"] as? [[String: Any]])

            var sectionNumbers: [Int] = []
            for page in pages {
                let section: Int = try XCTUnwrap(page["section"] as? Int)
                if !sectionNumbers.contains(section) {
                    sectionNumbers.append(section)
                }
            }
            let (root, _, course) = try makeWorkspace(word: from, sectionNumbers: sectionNumbers)
            defer { try? FileManager.default.removeItem(at: root) }
            for page in pages {
                let section: Int = try XCTUnwrap(page["section"] as? Int)
                let title: String = try XCTUnwrap(page["title"] as? String)
                try writeClass(title, on: "2026-09-08", in: course, section: section)
            }

            let plan: UnitWordRenamePlan = UnitWordRenamer.plan(from: from, to: to, in: course)
            if testCase["expectRefused"] as? Bool == true {
                XCTAssertFalse(plan.canProceed, name)
                XCTAssertTrue(plan.renames.isEmpty, "\(name): a refused plan must list no renames")
                continue
            }
            XCTAssertTrue(plan.canProceed, "\(name): \(plan.problems)")
            var actual: [String] = []
            for rename in plan.renames {
                actual.append("\(rename.sectionNumber): \(rename.from) → \(rename.to)")
            }
            actual.sort()
            var expected: [String] = []
            for rename in try XCTUnwrap(testCase["expectRenames"] as? [[String: Any]]) {
                expected.append("\(try XCTUnwrap(rename["section"] as? Int)): \(try XCTUnwrap(rename["from"] as? String)) → \(try XCTUnwrap(rename["to"] as? String))")
            }
            expected.sort()
            XCTAssertEqual(actual, expected, name)
            XCTAssertEqual(plan.sectionsTouched, try XCTUnwrap(testCase["expectSections"] as? [Int]), name)
            if let linkMap = testCase["expectLinkMap"] as? [String: String] {
                XCTAssertEqual(plan.linkMap, linkMap, name)
            }
        }
    }

    /// How links follow the renamed pages — and, as much to the point, what
    /// does not: prose, and pages that merely start with the word.
    func testRenamingTheUnitWordLinkCases() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("renamingTheUnitWord")
        let linkCases: [String: Any] = try XCTUnwrap(section["linkCases"] as? [String: Any])
        for testCase in try XCTUnwrap(linkCases["cases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let from: String = try XCTUnwrap(testCase["from"] as? String)
            let to: String = try XCTUnwrap(testCase["to"] as? String)
            var renamedPages: [String: String] = [:]
            for title in try XCTUnwrap(testCase["pageTitles"] as? [String]) {
                let numbers: UnitDay = try XCTUnwrap(UnitDay(pageTitle: title, term: from), name)
                renamedPages[title] = UnitDay(unit: numbers.unit, day: numbers.day, term: to).title
            }
            let text: String = try XCTUnwrap(testCase["text"] as? String)
            XCTAssertEqual(
                WikiLinkRewriter.rewriting(text, renamedPages: renamedPages),
                try XCTUnwrap(testCase["expect"] as? String),
                name
            )
        }
    }

    /// The order the contract fixes is the order the code runs — pinned by
    /// name, because the reasoning for it ("disk first, configuration last")
    /// is the kind of thing a refactor simplifies away.
    func testRenamingTheUnitWordOrderIsDocumented() throws {
        let section: [String: Any] = try ClassPlanningContractTests.section("renamingTheUnitWord")
        let order: [String] = try XCTUnwrap(section["order"] as? [String])
        XCTAssertEqual(order.count, 7)
        XCTAssertTrue(order[0].contains("read every planned page"))
        XCTAssertTrue(order[1].contains("back up"))
        XCTAssertTrue(order[5].contains("unit_word"))
        XCTAssertNotNil(section["why"])
        XCTAssertNotNil(section["howAPageIsRenamed"])
    }

    private static func section(_ name: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/class-planning.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in class-planning.json")
    }

    private static func cases(in name: String) throws -> [[String: Any]] {
        return try XCTUnwrap(section(name)["cases"] as? [[String: Any]])
    }
}
