import Foundation

/// Class pages that do not exist yet, laid down on the days the class actually
/// meets.
///
/// "Add seven days to the next unit." A teacher planning ahead knows two things
/// — which unit, and how many days they want in it — and neither of those is a
/// date. The dates come from the section's own remembered timetable, and the
/// days already spoken for by a class page are SKIPPED, so a course that has
/// been re-dated or reshuffled still gets the right answer. Nobody should have
/// to work out that the seventh class after today falls on a Thursday in
/// November.
///
/// Nothing is ever written over, and that is checked TWICE — once while
/// planning and again at the moment of writing. Obsidian is open in the other
/// window, and a page can appear between the teacher hearing the plan and
/// saying yes to it.
enum PlaceholderClassPlanner {

    // MARK: - Types

    /// Why placeholders could not be planned, in words a teacher can act on.
    enum Problem: LocalizedError {
        case unitOutOfRange
        case dayOutOfRange
        case countOutOfRange
        case noTimetable(String, Int)
        case wrongCourse(String, String)

        var errorDescription: String? {
            switch self {
            case .unitOutOfRange:
                return "A unit number starts at 1."
            case .dayOutOfRange:
                return "A day number starts at 1."
            case .countOutOfRange:
                return "Ask for at least one class."
            case .noTimetable(let code, let number):
                return "I don’t know when \(code) Section \(number) meets, so I can’t date new classes. Ask for the class dates, then record them first."
            case .wrongCourse(let planned, let given):
                return "That plan is for \(planned), not \(given)."
            }
        }
    }

    // MARK: - Functions

    /// What adding these classes would do. Changes nothing.
    static func plan(
        unit: Int,
        firstDay: Int,
        count: Int,
        forSection sectionNumber: Int,
        in course: Course
    ) throws -> PlaceholderClassPlan {
        if unit < 1 {
            throw Problem.unitOutOfRange
        }
        if firstDay < 1 {
            throw Problem.dayOutOfRange
        }
        if count < 1 {
            throw Problem.countOutOfRange
        }

        guard let remembered = try SectionTimetableStore.read(forSection: sectionNumber, in: course) else {
            throw Problem.noTimetable(course.code, sectionNumber)
        }

        let folderURL: URL = ClassPages.folderURL(forSection: sectionNumber, in: course)
        let existing: [ClassPageSummary] = ClassPages.list(forSection: sectionNumber, in: course)

        // A day a class page already sits on is spoken for. Working from what
        // the pages SAY, rather than counting from the start of the year,
        // means a course that has already been reshuffled still lands right.
        var taken: [CalendarDay] = []
        for page in existing {
            if let date = page.date, !taken.contains(date) {
                taken.append(date)
            }
        }
        var freeDates: [CalendarDay] = []
        for date in remembered.dates {
            if !taken.contains(date) {
                freeDates.append(date)
            }
        }

        var classes: [PlannedClass] = []
        var alreadyThere: [String] = []
        var problems: [String] = []

        let fileManager: FileManager = FileManager.default
        for offset in 0..<count {
            let day: Int = firstDay + offset
            let title: String = UnitDay(
                unit: unit, day: day, term: course.configuration.unitWord
            ).title
            let pageURL: URL = folderURL.appendingPathComponent(title + ".md")

            // Never written over. A page with this name may be a lesson the
            // teacher wrote months ago. (Checked again at write time.)
            if fileManager.fileExists(atPath: pageURL.path) {
                alreadyThere.append(title)
                continue
            }
            if classes.count >= freeDates.count {
                let undated: Int = count - alreadyThere.count - classes.count
                problems.append("Only \(freeDates.count) unused class date\(freeDates.count == 1 ? "" : "s") remain in the timetable, so the last \(undated) can’t be dated. Add more class dates and ask again.")
                break
            }
            classes.append(PlannedClass(
                title: title,
                fileURL: pageURL,
                day: day,
                date: freeDates[classes.count]
            ))
        }

        return PlaceholderClassPlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            unit: unit,
            classes: classes,
            alreadyThere: alreadyThere,
            problems: problems,
            spareDatesLeft: max(0, freeDates.count - classes.count),
            timetableSource: remembered.source
        )
    }

    /// Create the pages the plan describes.
    ///
    /// Every page is checked for a second time, immediately before it is
    /// written: the plan may be minutes old, Obsidian is open in the other
    /// window, and a teacher who started the page themselves in between must
    /// not lose it.
    @discardableResult
    static func apply(
        _ plan: PlaceholderClassPlan,
        in course: Course,
        backingUpInto coursesDirectoryURL: URL? = nil
    ) throws -> ClassChangeOutcome {
        if plan.courseCode != course.code {
            throw Problem.wrongCourse(plan.courseCode, course.code)
        }
        if plan.changesNothing {
            return ClassChangeOutcome(
                message: "Nothing to add — every class asked for already exists.", backupURL: nil
            )
        }

        var backupURL: URL? = nil
        if let coursesDirectoryURL {
            backupURL = try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL)
        }

        let fileManager: FileManager = FileManager.default
        let folderURL: URL = ClassPages.folderURL(forSection: plan.sectionNumber, in: course)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let tail: String = ClassPages.siblingTimeAndOffset(
            from: ClassPages.list(forSection: plan.sectionNumber, in: course),
            forSection: plan.sectionNumber
        )

        var written: [PlannedClass] = []
        var appearedInBetween: [String] = []
        for planned in plan.classes {
            if fileManager.fileExists(atPath: planned.fileURL.path) {
                appearedInBetween.append(planned.title)
                continue
            }
            let body: String = ClassPages.skeleton(
                title: planned.title,
                unit: plan.unit,
                date: planned.date,
                howMany: plan.classes.count,
                tail: tail
            )
            try body.write(to: planned.fileURL, atomically: true, encoding: .utf8)
            written.append(planned)
        }

        var message: String = ""
        if written.isEmpty {
            message = "Nothing was created — every one of those pages already exists."
        } else {
            var dated: String = "dated \(written[0].date.text)"
            if written.count > 1 {
                dated += " to \(written[written.count - 1].date.text)"
            }
            let they: String = written.count == 1 ? "It is" : "They are"
            let them: String = written.count == 1 ? "it" : "them"
            message = "Created \(written.count) class page\(written.count == 1 ? "" : "s") in Unit \(plan.unit) of \(plan.courseCode) Section \(plan.sectionNumber), \(dated). \(they) unpublished, so nothing changed on the site — write \(them), then publish when \(written.count == 1 ? "it is" : "they are") ready."
        }
        if !appearedInBetween.isEmpty {
            message += " \(SectionTimetableStore.list(appearedInBetween)) appeared while you were deciding and \(appearedInBetween.count == 1 ? "was" : "were") left exactly as \(appearedInBetween.count == 1 ? "it is" : "they are")."
        }
        var createdURLs: [URL] = []
        for planned in written {
            createdURLs.append(planned.fileURL)
        }
        return ClassChangeOutcome(message: message, backupURL: backupURL, created: createdURLs)
    }
}

/// One page that would be created, and the day it would land on.
struct PlannedClass {

    // MARK: - Stored properties

    let title: String
    let fileURL: URL

    /// Its day number within the unit.
    let day: Int

    /// The meeting date it takes.
    let date: CalendarDay

    // MARK: - Initializer

    init(title: String, fileURL: URL, day: Int, date: CalendarDay) {
        self.title = title
        self.fileURL = fileURL
        self.day = day
        self.date = date
    }
}

/// What adding placeholder class pages would do. Nothing here has happened yet.
struct PlaceholderClassPlan {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let unit: Int

    /// The pages that would be created, in order.
    let classes: [PlannedClass]

    /// Pages that already exist and would be left exactly as they are.
    let alreadyThere: [String]

    /// Anything the teacher should know before saying yes.
    let problems: [String]

    /// Meeting dates still spare once these classes take theirs.
    let spareDatesLeft: Int

    /// How many of these pages have no class date of their own and are
    /// sharing the last one.
    ///
    /// Adding a class used to REFUSE once every recorded date was spoken for.
    /// A teacher who has just finished teaching and wants tomorrow's page does
    /// not want to be sent away to record dates first — see the note in
    /// `NextClassPlanner`. So the page is made on the last day and this says
    /// how many are stacked there.
    var sharingTheLastDay: Int = 0

    /// Where the dates came from, so a stale timetable can be recognised.
    let timetableSource: String

    // MARK: - Computed properties

    var changesNothing: Bool {
        return classes.isEmpty
    }

    /// The proposal, as a teacher would hear it.
    var description: String {
        var lines: [String] = []

        if changesNothing {
            lines.append("Nothing to add — every class asked for in Unit \(unit) of \(courseCode) Section \(sectionNumber) already exists.")
            for problem in problems {
                lines.append("• " + problem)
            }
            return lines.joined(separator: "\n")
        }

        lines.append("Add \(classes.count) class page\(classes.count == 1 ? "" : "s") to Unit \(unit) of \(courseCode) Section \(sectionNumber), on the \(classes.count == 1 ? "day" : "days") this class actually meets:")
        lines.append("")
        for planned in classes {
            lines.append("  \(planned.title)  (\(planned.date.text) \(planned.date.weekdayName))")
        }

        if !alreadyThere.isEmpty {
            lines.append("")
            lines.append("\(alreadyThere.count) already exist\(alreadyThere.count == 1 ? "s" : "") and \(alreadyThere.count == 1 ? "is" : "are") left alone: \(SectionTimetableStore.list(alreadyThere)).")
        }

        for problem in problems {
            lines.append("• " + problem)
        }

        lines.append("")
        // Said plainly, because it is the difference between a teacher seeing
        // their new pages in the preview and wondering where they went.
        lines.append("They start unpublished, so they stay off the site until you publish them — write them first, publish when they are ready.")
        if sharingTheLastDay > 0 {
            // Said out loud, because a date shared with another class is the
            // one thing on this list a teacher has to go and fix.
            lines.append("\(sharingTheLastDay == 1 ? "This one has" : "\(sharingTheLastDay) of these have") "
                         + "no class date left, so \(sharingTheLastDay == 1 ? "it shares" : "they share") "
                         + "the last day with the class already on it. Give "
                         + "\(sharingTheLastDay == 1 ? "it a day" : "them days") of your own when you "
                         + "know what they are.")
        } else {
            lines.append("\(spareDatesLeft) more class date\(spareDatesLeft == 1 ? "" : "s") \(spareDatesLeft == 1 ? "is" : "are") spare after these, out of the timetable recorded from \(timetableSource).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Initializer

    init(
        courseCode: String,
        sectionNumber: Int,
        unit: Int,
        classes: [PlannedClass],
        alreadyThere: [String],
        problems: [String],
        spareDatesLeft: Int,
        sharingTheLastDay: Int = 0,
        timetableSource: String
    ) {
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.unit = unit
        self.classes = classes
        self.alreadyThere = alreadyThere
        self.problems = problems
        self.spareDatesLeft = spareDatesLeft
        self.sharingTheLastDay = sharingTheLastDay
        self.timetableSource = timetableSource
    }
}
