import XCTest
@testable import QuartzTeachers

/// Laying down class pages a teacher has not written yet, and making room for
/// one part-way through a unit that is already built out.
final class ClassPlanningTests: XCTestCase {

    // MARK: - Functions

    /// A course with one section, an "All Classes" folder, and a remembered
    /// timetable of six meeting days.
    @MainActor
    func makeWorkspace(
        meetingDates: [String] = ["2026-09-08", "2026-09-10", "2026-09-14", "2026-09-16", "2026-09-18", "2026-09-22"]
    ) throws -> (root: URL, coursesURL: URL, course: Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("class-planning-\(UUID().uuidString)")
        let coursesURL: URL = root.appendingPathComponent("courses")
        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )

        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "per_section_folders": ["All Classes"],
            "per_section_files": ["Snippets.md"],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))

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

    /// Writes one class page, dated, with a body of the caller's choosing so
    /// it can be told apart from every other page after a rename.
    @MainActor
    func writeClass(_ title: String, on date: String, body: String, in course: Course) throws {
        let page: String = """
        ---
        title: \(title)
        publish: true
        created: \(date)T07:00:00.000-0400
        ---

        \(body)
        """
        let url: URL = ClassPages.folderURL(forSection: 1, in: course)
            .appendingPathComponent(title + ".md")
        try page.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    func text(ofClass title: String, in course: Course) throws -> String {
        let url: URL = ClassPages.folderURL(forSection: 1, in: course)
            .appendingPathComponent(title + ".md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Placeholder class pages

    /// "Add three days to the next unit." They land on the days this class
    /// actually meets, and they step over the days a class already sits on —
    /// which is what makes a reshuffled course still get the right answer.
    @MainActor
    func testPlaceholdersSkipTheDaysAnExistingClassSitsOn() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        // A course that has already been reshuffled: Unit 1 sits on the 1st
        // and the 3rd meeting days, leaving a gap in the middle.
        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "loops", in: course)
        try writeClass("Unit 1, Day 2", on: "2026-09-14", body: "arrays", in: course)

        let plan: PlaceholderClassPlan = try PlaceholderClassPlanner.plan(
            unit: 2, firstDay: 1, count: 3, forSection: 1, in: course
        )

        var landedOn: [String] = []
        for planned in plan.classes {
            landedOn.append(planned.date.text)
        }
        XCTAssertEqual(landedOn, ["2026-09-10", "2026-09-16", "2026-09-18"],
                       "The 8th and the 14th are taken, so they are stepped over")
        XCTAssertEqual(plan.spareDatesLeft, 1)
        XCTAssertTrue(plan.description.contains("Unit 2, Day 1  (2026-09-10 Thursday)"),
                      "The plan reads the day of the week out, because that is how a teacher checks a date")
        XCTAssertTrue(plan.description.contains("unpublished"))

        // Planning alone writes nothing.
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.classes[0].fileURL.path))

        let outcome: ClassChangeOutcome = try PlaceholderClassPlanner.apply(plan, in: course)
        XCTAssertTrue(outcome.message.contains("Created 3 class pages"))

        let created: String = try text(ofClass: "Unit 2, Day 1", in: course)
        XCTAssertTrue(created.contains("publish: false"),
                      "A page nobody has written yet has no business on the site")
        XCTAssertTrue(created.contains("created: 2026-09-10T07:00:00.000-0400"),
                      "And it joins the time of day its siblings already use")
        XCTAssertTrue(created.contains("- unit-2"))
    }

    /// A page with the wanted name may be a lesson written months ago. It is
    /// never written over — and that is checked TWICE, because Obsidian is
    /// open in the other window and a page can appear while the teacher is
    /// still deciding.
    @MainActor
    func testAnExistingPageIsNeverWrittenOverEvenIfItAppearsAfterThePlan() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeClass("Unit 2, Day 2", on: "2026-09-08", body: "a lesson written in July", in: course)

        // First check: the plan itself leaves it out.
        let plan: PlaceholderClassPlan = try PlaceholderClassPlanner.plan(
            unit: 2, firstDay: 1, count: 3, forSection: 1, in: course
        )
        XCTAssertEqual(plan.alreadyThere, ["Unit 2, Day 2"])
        XCTAssertEqual(plan.classes.count, 2)
        XCTAssertTrue(plan.description.contains("left alone: Unit 2, Day 2"))

        // Second check: a page appears between the plan and the yes.
        try writeClass("Unit 2, Day 3", on: "2026-09-22", body: "started in Obsidian just now", in: course)

        let outcome: ClassChangeOutcome = try PlaceholderClassPlanner.apply(plan, in: course)
        XCTAssertTrue(outcome.message.contains("appeared while you were deciding"))

        XCTAssertTrue(try text(ofClass: "Unit 2, Day 2", in: course).contains("a lesson written in July"),
                      "A lesson written months ago is never written over")
        XCTAssertTrue(try text(ofClass: "Unit 2, Day 3", in: course).contains("started in Obsidian just now"),
                      "The page created between plan and apply must survive untouched")
        XCTAssertTrue(try text(ofClass: "Unit 2, Day 1", in: course).contains("publish: false"),
                      "The one page that was genuinely missing still gets made")
    }

    @MainActor
    func testPlaceholdersAreRefusedWithoutARememberedTimetable() throws {
        let (root, _, course) = try makeWorkspace(meetingDates: [])
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try PlaceholderClassPlanner.plan(unit: 1, firstDay: 1, count: 3, forSection: 1, in: course)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("don’t know when"))
        }
    }

    @MainActor
    func testAskingForMoreClassesThanThereAreDaysSaysSoRatherThanGuessing() throws {
        let (root, _, course) = try makeWorkspace(meetingDates: ["2026-09-08", "2026-09-10"])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan: PlaceholderClassPlan = try PlaceholderClassPlanner.plan(
            unit: 1, firstDay: 1, count: 5, forSection: 1, in: course
        )
        XCTAssertEqual(plan.classes.count, 2)
        XCTAssertEqual(plan.problems.count, 1)
        XCTAssertTrue(plan.problems[0].contains("Only 2 unused class dates"))
    }

    // MARK: - Insert a class and push the rest back

    /// The order the renames run in is not an implementation detail — it is
    /// the difference between a course that survives and one that loses a
    /// lesson. Working UP from Day 2 would try to make Day 2 into Day 3 while
    /// a real Day 3 is still called that.
    /// A page moved to a later day whose settings have no place for a new
    /// date is NAMED, with a sentence about the DATE — not "stays exactly as
    /// it is", which is false of a page just renamed and moved — and the
    /// trail counts it (#186's review, B3).
    @MainActor
    func testMakingRoomNamesAPageWhoseNewDateCouldNotBeSet() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))
        defer { ActivityTrail.store = previousStore }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "day one", in: course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "day two", in: course)
        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: course
        )
        // Edited in Obsidian after the plan was made: no column-0 line at all.
        let noRoom: URL = ClassPages.folderURL(forSection: 1, in: course)
            .appendingPathComponent("Unit 1, Day 2.md")
        try "---\n  a: 1\n---\nday two\n".write(to: noRoom, atomically: true, encoding: .utf8)

        let outcome: ClassChangeOutcome = try ClassInsertionPlanner.apply(plan, in: course)
        let said: String = AssistPublishPlan.sayingPagesWhoseNewDateCouldNotBeSet(named: ["Unit 1, Day 3"])
        XCTAssertTrue(outcome.message.hasSuffix(said), outcome.message)
        XCTAssertFalse(outcome.message.contains("exactly as"), "The page WAS renamed: \(outcome.message)")
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(
            trail.contains(ActivityTrail.pageSettingsLeftAsTheyWereLine(act: "making room for a class", pages: 1)),
            trail
        )
        XCTAssertFalse(trail.contains("Day 3"), "never which page: \(trail)")
    }

    @MainActor
    func testRenamesRunHighestDayFirst() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "day one", in: course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "day two", in: course)
        try writeClass("Unit 1, Day 3", on: "2026-09-14", body: "day three", in: course)

        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: course
        )

        var order: [String] = []
        for rename in plan.renames {
            order.append("\(rename.from) → \(rename.to)")
        }
        XCTAssertEqual(order, ["Unit 1, Day 3 → Unit 1, Day 4", "Unit 1, Day 2 → Unit 1, Day 3"],
                       "Highest day first, so every destination has been vacated before it is needed")

        // What the other order would cost, spelled out. Renaming in ASCENDING
        // day order, with the same "never write over a name in use" guard the
        // real code has, silently drops the first rename — Day 2 cannot become
        // Day 3 while a real Day 3 is still called that.
        var namesOnDisk: [String: String] = [
            "Unit 1, Day 2": "day two",
            "Unit 1, Day 3": "day three",
        ]
        var ascending: [ClassRename] = plan.renames
        ascending.reverse()
        for rename in ascending {
            if namesOnDisk[rename.to] != nil {
                continue                       // the guard: refuse to overwrite
            }
            namesOnDisk[rename.to] = namesOnDisk[rename.from]
            namesOnDisk[rename.from] = nil
        }
        XCTAssertEqual(namesOnDisk["Unit 1, Day 2"], "day two",
                       "Ascending order left Day 2's lesson under its old name…")
        XCTAssertNil(namesOnDisk["Unit 1, Day 3"],
                     "…so the course is left with a HOLE where Day 3 should be…")
        XCTAssertEqual(namesOnDisk["Unit 1, Day 4"], "day three")
        // …and the new blank class, which wants to be written as "Unit 1, Day
        // 2", would find that name taken and be skipped by the never-overwrite
        // guard. The teacher would get no new class, a missing day, and a Day 2
        // page holding the lesson that should now be Day 3. Without the guard
        // it is worse still: a real lesson overwritten.
        XCTAssertEqual(plan.added[0].title, "Unit 1, Day 2")

        // Now the real thing, in the plan's order.
        try ClassInsertionPlanner.apply(plan, in: course)

        XCTAssertTrue(try text(ofClass: "Unit 1, Day 4", in: course).contains("day three"),
                      "Day 3's lesson is now Day 4")
        XCTAssertTrue(try text(ofClass: "Unit 1, Day 3", in: course).contains("day two"),
                      "Day 2's lesson is now Day 3")
        XCTAssertTrue(try text(ofClass: "Unit 1, Day 1", in: course).contains("day one"),
                      "Everything before the insertion point is untouched")

        // Titles inside the files follow the file names.
        XCTAssertTrue(try text(ofClass: "Unit 1, Day 4", in: course).contains("title: Unit 1, Day 4"))
        XCTAssertTrue(try text(ofClass: "Unit 1, Day 3", in: course).contains("title: Unit 1, Day 3"))

        // And the new, blank class sits where the room was made.
        let inserted: String = try text(ofClass: "Unit 1, Day 2", in: course)
        XCTAssertTrue(inserted.contains("publish: false"))
        XCTAssertTrue(inserted.contains("created: 2026-09-10T07:00:00.000-0400"))
    }

    /// Later units move to later meeting days and KEEP their names — a later
    /// unit's Day 1 is still its Day 1; it simply happens later in the year.
    @MainActor
    func testLaterUnitsMoveButAreNotRenumbered() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one one", in: course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "one two", in: course)
        try writeClass("Unit 2, Day 1", on: "2026-09-14", body: "two one", in: course)
        try writeClass("Unit 2, Day 2", on: "2026-09-16", body: "two two", in: course)

        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: course
        )
        XCTAssertEqual(plan.renames.count, 1, "Only the unit being changed is renumbered")
        XCTAssertEqual(plan.renames[0].to, "Unit 1, Day 3")
        XCTAssertEqual(plan.moves.count, 3, "Day 2 of Unit 1 and both days of Unit 2 all slide along")
        XCTAssertTrue(plan.description.contains("Moved to later class days — 3:"))

        try ClassInsertionPlanner.apply(plan, in: course)

        XCTAssertTrue(try text(ofClass: "Unit 2, Day 1", in: course).contains("two one"),
                      "A later unit keeps its own numbering")
        XCTAssertTrue(try text(ofClass: "Unit 2, Day 1", in: course).contains("created: 2026-09-16"),
                      "…and moves onto the next meeting day")
        XCTAssertTrue(try text(ofClass: "Unit 2, Day 2", in: course).contains("created: 2026-09-18"))
        XCTAssertTrue(try text(ofClass: "Unit 1, Day 3", in: course).contains("created: 2026-09-14"))
    }

    /// How many OTHER classes a plan disturbs, counted once each.
    ///
    /// **The union of the two lists, and this is the case that shows why.** A
    /// page inside the unit being changed is BOTH renamed and re-dated, so it
    /// is in `renames` and in `moves`; a later unit's page is only re-dated.
    /// Adding the counts would tell a teacher five classes move when three
    /// do. The union works on titles because `moves` carries each page under
    /// the name it will HAVE, which is what makes the two lists comparable at
    /// all. `AssistWording.otherClassesWouldMove` is what reads it, and the
    /// card it goes on is what a teacher agrees to.
    @MainActor
    func testOtherClassesMovingCountsAPageRenamedAndReDatedOnce() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one one", in: course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "one two", in: course)
        try writeClass("Unit 1, Day 3", on: "2026-09-14", body: "one three", in: course)
        try writeClass("Unit 2, Day 1", on: "2026-09-16", body: "two one", in: course)

        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: course
        )
        XCTAssertEqual(plan.renames.count, 2, "Both later days of unit 1 are renumbered")
        XCTAssertEqual(plan.moves.count, 3, "…and both, plus unit 2's day, are re-dated")
        XCTAssertEqual(
            plan.otherClassesMoving, 3,
            "Three pages move; adding the two lists together would say five"
        )

        // And nothing moves when nothing else is there — the case where the
        // copy really can be taken back.
        let atTheEnd: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 2, atDay: 2, count: 1, forSection: 1, in: course
        )
        XCTAssertEqual(atTheEnd.otherClassesMoving, 0)
        XCTAssertFalse(atTheEnd.movesAnythingElse, "The new page is not an OTHER class")
    }

    /// Obsidian only rewrites links when OBSIDIAN performs the rename. A
    /// rename on disk from another process reads to it as a delete plus a
    /// create, so the links are ours to follow.
    @MainActor
    func testEveryWikilinkFormFollowsTheRename() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one", in: course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "two", in: course)

        // A course-level page pointing at the class in every form Obsidian
        // writes — plus a Markdown-style link, which is NOT handled.
        let keyLinks: String = """
        ---
        title: Key Links
        ---

        - Plain: [[Unit 1, Day 2]]
        - Aliased: [[Unit 1, Day 2|the lesson on loops]]
        - Embedded: ![[Unit 1, Day 2]]
        - Heading: [[Unit 1, Day 2#Agenda]]
        - Block: [[Unit 1, Day 2#^a1b2c3]]
        - Heading and alias: [[Unit 1, Day 2#Agenda|what we did]]
        - Markdown style: [what we did](Unit%201,%20Day%202.md)
        - Someone else: [[Unit 1, Day 1]]
        """
        let keyLinksURL: URL = course.directoryURL.appendingPathComponent("Key Links.md")
        try keyLinks.write(to: keyLinksURL, atomically: true, encoding: .utf8)

        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: course
        )
        XCTAssertEqual(plan.linksToRewrite, 6, "Six wikilinks point at the page being renamed")
        XCTAssertTrue(plan.description.contains("6 links point at those names"))

        try ClassInsertionPlanner.apply(plan, in: course)

        let updated: String = try String(contentsOf: keyLinksURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("- Plain: [[Unit 1, Day 3]]"))
        XCTAssertTrue(updated.contains("- Aliased: [[Unit 1, Day 3|the lesson on loops]]"),
                      "The alias is the teacher's own words and must not change")
        XCTAssertTrue(updated.contains("- Embedded: ![[Unit 1, Day 3]]"))
        XCTAssertTrue(updated.contains("- Heading: [[Unit 1, Day 3#Agenda]]"))
        XCTAssertTrue(updated.contains("- Block: [[Unit 1, Day 3#^a1b2c3]]"))
        XCTAssertTrue(updated.contains("- Heading and alias: [[Unit 1, Day 3#Agenda|what we did]]"))
        XCTAssertTrue(updated.contains("- Someone else: [[Unit 1, Day 1]]"),
                      "A link to a page that did not move is left exactly as it was")

        // The documented gap, pinned so it cannot change without somebody
        // noticing: Markdown-style links are NOT rewritten.
        XCTAssertTrue(updated.contains("[what we did](Unit%201,%20Day%202.md)"),
                      "Markdown-style links are a known, written-down limitation")
    }

    @MainActor
    func testWikilinkRewritingIsCaseInsensitiveAndForgivesSpacing() {
        let renamed: [String: String] = ["Unit 1, Day 2": "Unit 1, Day 3"]
        XCTAssertEqual(
            WikiLinkRewriter.rewriting("see [[unit 1, day 2]] and [[ Unit 1, Day 2 |x]]", renamedPages: renamed),
            "see [[Unit 1, Day 3]] and [[Unit 1, Day 3|x]]"
        )
        XCTAssertEqual(
            WikiLinkRewriter.rewriting("nothing here", renamedPages: renamed),
            "nothing here"
        )
    }

    @MainActor
    func testInsertionIsRefusedWhenTheTimetableRunsOut() throws {
        let (root, _, course) = try makeWorkspace(meetingDates: ["2026-09-08", "2026-09-10"])
        defer { try? FileManager.default.removeItem(at: root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one", in: course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "two", in: course)

        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: course
        )
        XCTAssertTrue(plan.changesNothing)
        XCTAssertTrue(plan.problems[0].contains("Add 1 more class date"))
        XCTAssertTrue(plan.description.contains("Nothing would change"))

        // And nothing on disk moved.
        try ClassInsertionPlanner.apply(plan, in: course)
        XCTAssertTrue(try text(ofClass: "Unit 1, Day 2", in: course).contains("two"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: ClassPages.folderURL(forSection: 1, in: course)
                    .appendingPathComponent("Unit 1, Day 3.md").path
            )
        )
    }

    /// A teacher's "Field Trip" has no unit and no day. Renumbering it would
    /// mean inventing one, so it is left exactly where it is — and the plan
    /// says so, rather than letting the teacher discover it.
    @MainActor
    func testPagesNotNamedUnitAndDayAreLeftWhereTheyAre() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one", in: course)
        try writeClass("Unit 1, Day 2", on: "2026-09-10", body: "two", in: course)
        try writeClass("Field Trip", on: "2026-09-14", body: "the museum", in: course)

        let plan: ClassInsertionPlan = try ClassInsertionPlanner.plan(
            unit: 1, atDay: 2, count: 1, forSection: 1, in: course
        )
        XCTAssertTrue(plan.problems[0].contains("1 class page is not named"))

        try ClassInsertionPlanner.apply(plan, in: course)
        XCTAssertTrue(try text(ofClass: "Field Trip", in: course).contains("created: 2026-09-14"),
                      "Its date is left alone along with its name")
    }

    @MainActor
    func testAPlanFromAnotherCourseIsRefused() throws {
        let (root, _, course) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeClass("Unit 1, Day 1", on: "2026-09-08", body: "one", in: course)
        let plan: PlaceholderClassPlan = try PlaceholderClassPlanner.plan(
            unit: 2, firstDay: 1, count: 1, forSection: 1, in: course
        )

        let otherURL: URL = course.directoryURL.deletingLastPathComponent().appendingPathComponent("SNC1W")
        let other: Course = Course(code: "SNC1W", directoryURL: otherURL, configuration: course.configuration)
        XCTAssertThrowsError(try PlaceholderClassPlanner.apply(plan, in: other)) { error in
            XCTAssertTrue(error.localizedDescription.contains("That plan is for ICS3U"))
        }
    }

    // MARK: - The pieces underneath

    @MainActor
    func testAPageNameIsReadAsAUnitAndADay() {
        XCTAssertEqual(UnitDay(pageTitle: "Unit 2, Day 3"), UnitDay(unit: 2, day: 3))
        XCTAssertEqual(UnitDay(pageTitle: "unit 12,  day 7"), UnitDay(unit: 12, day: 7))
        XCTAssertNil(UnitDay(pageTitle: "Field Trip"))
        XCTAssertNil(UnitDay(pageTitle: "Unit 2, Day 3 (revised)"))
        XCTAssertEqual(UnitDay(unit: 2, day: 3).title, "Unit 2, Day 3")
    }

    @MainActor
    func testChangingADateKeepsTheTimeAndOffsetThePageAlreadyHad() {
        let page: String = """
        ---
        title: Unit 1, Day 1
        created: 2026-09-08T09:15:00.000-0500
        tags:
          - unit-1
        ---
        Body.
        """
        let result: (text: String, outcome: FrontmatterWriteOutcome) = PageFrontmatter.settingCreated(
            in: page, key: "created", to: CalendarDay(year: 2026, month: 9, day: 22)!
        )
        XCTAssertEqual(result.outcome, .written)
        XCTAssertTrue(result.text.contains("created: 2026-09-22T09:15:00.000-0500"),
                      "Only the date in front of the time moves")
        XCTAssertTrue(result.text.contains("- unit-1"), "Every other byte is left alone")

        let again: (text: String, outcome: FrontmatterWriteOutcome) = PageFrontmatter.settingCreated(
            in: result.text, key: "created", to: CalendarDay(year: 2026, month: 9, day: 22)!
        )
        XCTAssertEqual(again.outcome, .alreadyRight, "Setting the date it already has is not a change")
    }
}
