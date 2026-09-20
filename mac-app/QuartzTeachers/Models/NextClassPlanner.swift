import Foundation

/// The page for the next class: the one that comes after the last one a
/// section has, on the next day it meets.
///
/// This is the end of a lesson, in one sentence. A teacher has just finished
/// teaching, wants tomorrow's page to exist so they can start writing it, and
/// today opens frontmatter to do it — working out which number comes next and
/// which date that number falls on. Neither of those is a judgement; both are
/// arithmetic somebody keeps doing by hand.
///
/// **The number and the date are worked out separately, and that is the whole
/// design.** They answer different questions:
///
/// * The NUMBER continues the unit being taught. The highest unit any class
///   page names, then the highest day inside that unit, plus one: Unit 3,
///   Day 2 becomes Unit 3, Day 3. A new unit is a decision a teacher makes, not
///   one a tool should make for them — `PlaceholderClassPlanner` is how a unit
///   gets started.
/// * The DATE comes from POSITION IN THE TIMETABLE. Count the class pages the
///   section already has, add one, and take that many dates into the remembered
///   timetable: 15 class pages means the 16th recorded date. It is deliberately
///   NOT derived from the unit and day numbering — three units of five days are
///   fifteen classes whatever they are called, and a course where a unit ran
///   long, or where a page is called "Field Trip" rather than Unit 2, Day 4,
///   would date every later class wrongly if the numbers were trusted.
///
/// Nothing here writes. The plan it returns is a `PlaceholderClassPlan`, so the
/// page is created by `PlaceholderClassPlanner.apply` — which already refuses
/// to write over an existing page, checks that twice, and starts new pages
/// `publish: false`.
enum NextClassPlanner {

    // MARK: - Types

    /// Why a next class could not be planned, in words a teacher can act on.
    ///
    /// **Neither message names a tool.** They used to say "record them with
    /// `remember_timetable` first", which was a dead end the day that tool
    /// came off the local surface: the model was being sent to something it
    /// could no longer see, and would either give up or invent dates of its
    /// own. Asking for the dates is the APP's job now — `AssistToolRunner`
    /// opens the schedule sheet when it sees `noTimetable` — so these say what
    /// is missing and who is being asked, and leave the how alone. That also
    /// keeps them true on the MCP surface, where the client's tool list is
    /// different again.
    enum Problem: LocalizedError {
        case noTimetable(String, Int)

        var errorDescription: String? {
            switch self {
            case .noTimetable(let code, let number):
                return "I don’t know when \(code) Section \(number) meets, so I can’t date a new class. "
                     + AssistWording.mayIAskForYourDates
            }
        }
    }

    // There is deliberately NO "the timetable ran out" refusal.
    //
    // It used to refuse to add a class once every recorded date was spoken
    // for. The reasoning was that a page with a made-up date is worse than no
    // page — but that is not the choice a teacher faces. They have finished
    // teaching, they want tomorrow's page to exist so they can start writing
    // it, and being told to go and record more dates first is being sent away
    // to do admin at the one moment they were ready to write.
    //
    // Same answer as re-dating a section: the page is created on the LAST
    // class date, where it sits beside the final class and is impossible to
    // miss, and the plan says so. Fixing a date is a keystroke; recovering
    // the ten minutes they had is not.

    // MARK: - Functions

    /// What adding the next class would do. Changes nothing.
    ///
    /// `startingANewUnit` is the teacher saying the next class begins a new
    /// unit — the one judgement this planner will not make for them, and the
    /// reason it is a separate request rather than something inferred from how
    /// long the current unit has run.
    static func plan(
        forSection sectionNumber: Int,
        in course: Course,
        startingANewUnit: Bool = false
    ) throws -> PlaceholderClassPlan {
        guard let remembered = try SectionTimetableStore.read(forSection: sectionNumber, in: course) else {
            throw Problem.noTimetable(course.code, sectionNumber)
        }

        let existing: [ClassPageSummary] = ClassPages.list(forSection: sectionNumber, in: course)
        let next: UnitDay = startingANewUnit
            ? firstDayOfANewUnit(after: existing, term: course.configuration.unitWord)
            : nextUnitAndDay(after: existing, term: course.configuration.unitWord)

        // Position, not numbering: the class after this section's 15th class
        // takes the 16th date, whatever the 15 pages happen to be called.
        let position: Int = existing.count
        let date: CalendarDay = try NextClassPlanner.date(
            at: position, from: remembered.dates, course: course, sectionNumber: sectionNumber
        )

        let pageURL: URL = ClassPages.folderURL(forSection: sectionNumber, in: course)
            .appendingPathComponent(next.title + ".md")

        // The first of the two checks that nothing is ever written over. The
        // second is in `PlaceholderClassPlanner.apply`, because Obsidian is
        // open in the other window and a page can appear in between.
        var classes: [PlannedClass] = []
        var alreadyThere: [String] = []
        if FileManager.default.fileExists(atPath: pageURL.path) {
            alreadyThere.append(next.title)
        } else {
            classes.append(PlannedClass(
                title: next.title, fileURL: pageURL, day: next.day, date: date
            ))
        }

        return PlaceholderClassPlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            unit: next.unit,
            classes: classes,
            alreadyThere: alreadyThere,
            problems: [],
            spareDatesLeft: max(0, remembered.dates.count - (position + 1)),
            sharingTheLastDay: position >= remembered.dates.count ? 1 : 0,
            timetableSource: remembered.source
        )
    }

    /// The unit and day a new class page would carry: the highest unit these
    /// pages name, and one past the highest day inside it.
    ///
    /// Pages named some other way — "Field Trip", "Exam Review" — carry no
    /// numbers and are passed over here, exactly as they are everywhere else
    /// that renumbers classes. A section with no numbered class at all starts
    /// at Unit 1, Day 1.
    static func nextUnitAndDay(
        after pages: [ClassPageSummary], term: String = ClassPageTerm.standard
    ) -> UnitDay {
        var highestUnit: Int = 0
        for page in pages {
            if let numbers = page.unitAndDay, numbers.unit > highestUnit {
                highestUnit = numbers.unit
            }
        }
        if highestUnit == 0 {
            return UnitDay(unit: 1, day: 1, term: term)
        }

        var highestDay: Int = 0
        for page in pages {
            guard let numbers = page.unitAndDay, numbers.unit == highestUnit else {
                continue
            }
            if numbers.day > highestDay {
                highestDay = numbers.day
            }
        }
        return UnitDay(unit: highestUnit, day: highestDay + 1, term: term)
    }

    /// Several more days on the end of a unit that already exists.
    ///
    /// "Add five more days to Unit 4" — the teacher knows the unit needs more
    /// room and does not want to ask five times. It continues from the last day
    /// that EXISTS in that unit, published or not: a page they have written but
    /// not yet shown anybody is still a day of the course, and numbering over
    /// the top of it would collide with a real file.
    ///
    /// The dates come from position in the timetable exactly as a single new
    /// class does — count the class pages the section has, and take the next
    /// dates along. That is why this can add days to Unit 4 while Unit 5 pages
    /// already exist and still date them correctly: the count is of PAGES, not
    /// of anything to do with unit numbering.
    static func plan(
        addingDays howMany: Int,
        toUnit unit: Int,
        forSection sectionNumber: Int,
        in course: Course
    ) throws -> PlaceholderClassPlan {
        guard let remembered = try SectionTimetableStore.read(forSection: sectionNumber, in: course) else {
            throw Problem.noTimetable(course.code, sectionNumber)
        }

        let existing: [ClassPageSummary] = ClassPages.list(forSection: sectionNumber, in: course)

        // The last day in THAT unit, whatever else the section has.
        var highestDay: Int = 0
        for page in existing {
            guard let numbers = page.unitAndDay, numbers.unit == unit else {
                continue
            }
            if numbers.day > highestDay {
                highestDay = numbers.day
            }
        }

        let folder: URL = ClassPages.folderURL(forSection: sectionNumber, in: course)
        var classes: [PlannedClass] = []
        var alreadyThere: [String] = []
        var position: Int = existing.count

        for step in 1...max(1, howMany) {
            let day: Int = highestDay + step
            let title: String = UnitDay(
                unit: unit, day: day, term: course.configuration.unitWord
            ).title
            let pageURL: URL = folder.appendingPathComponent(title + ".md")
            if FileManager.default.fileExists(atPath: pageURL.path) {
                alreadyThere.append(title)
                continue
            }
            classes.append(PlannedClass(
                title: title, fileURL: pageURL, day: day,
                date: try NextClassPlanner.date(
                    at: position, from: remembered.dates,
                    course: course, sectionNumber: sectionNumber
                )
            ))
            position += 1
        }

        return PlaceholderClassPlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            unit: unit,
            classes: classes,
            alreadyThere: alreadyThere,
            problems: [],
            spareDatesLeft: max(0, remembered.dates.count - position),
            sharingTheLastDay: max(0, position - remembered.dates.count),
            timetableSource: remembered.source
        )
    }

    /// The date for a class in this position — and the LAST recorded date for
    /// anything past the end of the list.
    ///
    /// See the note above `Problem`. An empty timetable is a different thing
    /// and still refuses: there is no last date to fall back to, and a class
    /// with no date at all would sort nowhere.
    private static func date(
        at position: Int,
        from dates: [CalendarDay],
        course: Course,
        sectionNumber: Int
    ) throws -> CalendarDay {
        if dates.isEmpty {
            throw Problem.noTimetable(course.code, sectionNumber)
        }
        if position < dates.count {
            return dates[position]
        }
        return dates[dates.count - 1]
    }

    /// The first class of the NEXT unit: one past the highest unit, Day 1.
    ///
    /// **Day starts again at 1, because that is what every course here does.**
    /// The day number counts within its unit — ADA1O runs Unit 1, Day 1…18 and
    /// then Unit 2, Day 1 — so a new unit begins at Day 1 however many days the
    /// last one ran to. It does not continue the previous unit's count.
    ///
    /// **Pages that are UNPUBLISHED still count.** A teacher with Unit 4,
    /// Day 12 published and Days 13 and 14 written but hidden gets Unit 5,
    /// Day 1: those two pages exist, so the new unit comes after them, and the
    /// date is the next one in the timetable with no class against it. Whether
    /// students can see a page has nothing to do with where the next one goes
    /// — that is decided by how many pages there are, which is the same rule
    /// the DATE has always used.
    ///
    /// A section with no numbered class at all gets Unit 1, Day 1: there is no
    /// unit yet, so there is none to move past.
    static func firstDayOfANewUnit(
        after pages: [ClassPageSummary], term: String = ClassPageTerm.standard
    ) -> UnitDay {
        var highestUnit: Int = 0
        for page in pages {
            if let numbers = page.unitAndDay, numbers.unit > highestUnit {
                highestUnit = numbers.unit
            }
        }
        if highestUnit == 0 {
            return UnitDay(unit: 1, day: 1, term: term)
        }
        return UnitDay(unit: highestUnit + 1, day: 1, term: term)
    }
}
