import Foundation

/// Making room in a course that is already built out — the one a teacher
/// called "a huge hassle".
///
/// A teacher discovers in November that Unit 2 needs another day on a task.
/// Doing that by hand means renaming every class after it, re-dating every one
/// of them onto the days the class actually meets, and finding every link that
/// pointed at a page whose name has just changed — across a course that might
/// hold two hundred pages.
///
/// Two separate things happen, and the plan keeps them apart because they read
/// differently to a teacher:
///
/// * Later days of the SAME unit are **renamed** — Day 3 becomes Day 4.
/// * Every class from the insertion point onwards, later units included,
///   **moves to a later meeting day and keeps its name**. A later unit's Day 1
///   is still its Day 1; it simply happens later in the year.
///
/// This is also the most dangerous thing here, because it renames pages the
/// teacher's links point at. So the plan names the renames, counts the links
/// and says how the dates move, before anything happens at all.
enum ClassInsertionPlanner {

    // MARK: - Types

    /// Why an insertion could not be planned or carried out.
    enum Problem: LocalizedError {
        case unitOutOfRange
        case dayOutOfRange
        case countOutOfRange
        case noTimetable(String, Int)
        case noNumberedClasses(String, Int)
        case wouldNotFit(String)
        case wrongCourse(String, String)

        var errorDescription: String? {
            switch self {
            case .unitOutOfRange, .dayOutOfRange:
                return "Unit and day numbers start at 1."
            case .countOutOfRange:
                return "Ask for at least one class."
            case .noTimetable(let code, let number):
                return "I don’t know when \(code) Section \(number) meets, so I can’t move classes onto real days. Ask for the class dates, then record them first."
            case .noNumberedClasses(let code, let number):
                return "\(code) Section \(number) has no pages named “Unit N, Day N”, so there is nothing to make room in."
            case .wouldNotFit(let reason):
                return reason
            case .wrongCourse(let planned, let given):
                return "That plan is for \(planned), not \(given)."
            }
        }
    }

    // MARK: - Functions

    /// What making room would do. Changes nothing.
    static func plan(
        unit: Int,
        atDay: Int,
        count: Int,
        forSection sectionNumber: Int,
        in course: Course
    ) throws -> ClassInsertionPlan {
        if unit < 1 {
            throw Problem.unitOutOfRange
        }
        if atDay < 1 {
            throw Problem.dayOutOfRange
        }
        if count < 1 {
            throw Problem.countOutOfRange
        }

        guard let remembered = try SectionTimetableStore.read(forSection: sectionNumber, in: course) else {
            throw Problem.noTimetable(course.code, sectionNumber)
        }

        let allPages: [ClassPageSummary] = ClassPages.list(forSection: sectionNumber, in: course)
        let numbered: [ClassPageSummary] = numberedClasses(among: allPages)
        if numbered.isEmpty {
            throw Problem.noNumberedClasses(course.code, sectionNumber)
        }

        var problems: [String] = []
        let unnumbered: Int = allPages.count - numbered.count
        if unnumbered > 0 {
            problems.append("\(unnumbered) class page\(unnumbered == 1 ? " is" : "s are") not named “Unit N, Day N”, so \(unnumbered == 1 ? "it was" : "they were") left where \(unnumbered == 1 ? "it is" : "they are") — including \(unnumbered == 1 ? "its" : "their") date.")
        }

        // Everything at or after the insertion point moves along: later days
        // of this unit, and every class of every later unit.
        var shifted: [ClassPageSummary] = []
        var untouched: [ClassPageSummary] = []
        for page in numbered {
            guard let numbers = page.unitAndDay else {
                continue
            }
            if numbers.unit > unit || (numbers.unit == unit && numbers.day >= atDay) {
                shifted.append(page)
            } else {
                untouched.append(page)
            }
        }

        // Days already spoken for by classes that are NOT moving.
        var held: [CalendarDay] = []
        for page in untouched {
            if let date = page.date {
                held.append(date)
            }
        }
        var available: [CalendarDay] = []
        for date in remembered.dates {
            if !held.contains(date) {
                available.append(date)
            }
        }
        available.sort()

        // The first day the new classes may take: where the insertion point
        // sits today, or the next free day when this unit ends here.
        var firstFree: CalendarDay? = shifted.first?.date
        if firstFree == nil {
            let lastHeld: CalendarDay? = untouched.last?.date
            for date in available {
                if lastHeld == nil || date > lastHeld! {
                    firstFree = date
                    break
                }
            }
        }
        var runway: [CalendarDay] = []
        if let firstFree {
            for date in available {
                if date >= firstFree {
                    runway.append(date)
                }
            }
        }

        let needed: Int = count + shifted.count
        if runway.count < needed {
            let missing: Int = needed - runway.count
            let from: String = firstFree?.text ?? "the end of the course"
            problems.append("This needs \(needed) class days from \(from) onwards and the timetable only has \(runway.count). Add \(missing) more class date\(missing == 1 ? "" : "s") and ask again.")
            return ClassInsertionPlan(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                unit: unit,
                atDay: atDay,
                added: [],
                renames: [],
                moves: [],
                linksToRewrite: 0,
                problems: problems
            )
        }

        let folderURL: URL = ClassPages.folderURL(forSection: sectionNumber, in: course)

        var added: [PlannedClass] = []
        for offset in 0..<count {
            let day: Int = atDay + offset
            let title: String = UnitDay(
                unit: unit, day: day, term: course.configuration.unitWord
            ).title
            added.append(PlannedClass(
                title: title,
                fileURL: folderURL.appendingPathComponent(title + ".md"),
                day: day,
                date: runway[offset]
            ))
        }

        // Renames, HIGHEST DAY FIRST — see `apply` for why the order is part
        // of the plan rather than an implementation detail.
        var withinUnit: [ClassPageSummary] = []
        for page in shifted {
            if page.unitAndDay?.unit == unit {
                withinUnit.append(page)
            }
        }
        withinUnit.sort { first, second in
            return (first.unitAndDay?.day ?? 0) > (second.unitAndDay?.day ?? 0)
        }
        var renames: [ClassRename] = []
        for page in withinUnit {
            guard let numbers = page.unitAndDay else {
                continue
            }
            let newTitle: String = UnitDay(
                unit: unit, day: numbers.day + count, term: course.configuration.unitWord
            ).title
            renames.append(ClassRename(
                from: page.title,
                to: newTitle,
                fromURL: page.fileURL,
                toURL: folderURL.appendingPathComponent(newTitle + ".md")
            ))
        }

        // Dates: the new classes take the first slots, then everything shifted
        // follows in the order it was already in.
        var moves: [ClassDateMove] = []
        for index in 0..<shifted.count {
            let moving: ClassPageSummary = shifted[index]
            let destination: CalendarDay = runway[count + index]
            if moving.date == destination {
                continue
            }
            var name: String = moving.title
            if let numbers = moving.unitAndDay, numbers.unit == unit {
                name = UnitDay(
                    unit: unit, day: numbers.day + count, term: course.configuration.unitWord
                ).title
            }
            moves.append(ClassDateMove(
                title: name,
                fileURL: moving.fileURL,
                from: moving.date,
                to: destination
            ))
        }

        var renamedFrom: [String] = []
        for rename in renames {
            renamedFrom.append(rename.from)
        }

        return ClassInsertionPlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            unit: unit,
            atDay: atDay,
            added: added,
            renames: renames,
            moves: moves,
            linksToRewrite: countLinks(to: renamedFrom, forSection: sectionNumber, in: course),
            problems: problems
        )
    }

    /// Carry the insertion out: rename, follow the links, move the dates, then
    /// create the blanks.
    ///
    /// **The renames run in the plan's order, which is highest day first.** In
    /// any other order a rename lands on a name that is still in use: turning
    /// Day 2 into Day 3 while a real Day 3 is still called that either
    /// overwrites a lesson or — with the guard below — silently skips, leaving
    /// two pages claiming to be Day 3. Working down from the top means every
    /// destination has already been vacated.
    @discardableResult
    static func apply(
        _ plan: ClassInsertionPlan,
        in course: Course,
        backingUpInto coursesDirectoryURL: URL? = nil
    ) throws -> ClassChangeOutcome {
        if plan.courseCode != course.code {
            throw Problem.wrongCourse(plan.courseCode, course.code)
        }
        if plan.changesNothing {
            return ClassChangeOutcome(message: "Nothing needed moving.", backupURL: nil)
        }
        if plan.added.isEmpty {
            throw Problem.wouldNotFit(plan.problems.joined(separator: " "))
        }

        var backupURL: URL? = nil
        if let coursesDirectoryURL {
            backupURL = try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL)
        }

        let fileManager: FileManager = FileManager.default
        let folderURL: URL = ClassPages.folderURL(forSection: plan.sectionNumber, in: course)
        let tail: String = ClassPages.siblingTimeAndOffset(
            from: ClassPages.list(forSection: plan.sectionNumber, in: course),
            forSection: plan.sectionNumber
        )

        // 1. The renames, highest day first.
        var renamed: [String: String] = [:]
        for rename in plan.renames {
            guard fileManager.fileExists(atPath: rename.fromURL.path),
                  !fileManager.fileExists(atPath: rename.toURL.path),
                  let text = try? String(contentsOf: rename.fromURL, encoding: .utf8) else {
                continue
            }
            // The title inside the file follows the file name: a page whose
            // name and title disagree is worse than either being wrong alone.
            let retitled: String = PageFrontmatter.settingTitle(in: text, to: rename.to)
            try retitled.write(to: rename.toURL, atomically: true, encoding: .utf8)
            try? fileManager.removeItem(at: rename.fromURL)
            renamed[rename.from] = rename.to
        }

        // 2. The links that pointed at the old names. Ours to do — Obsidian
        //    only rewrites links when Obsidian performs the rename.
        var linksRewritten: Int = 0
        if !renamed.isEmpty {
            var oldNames: [String] = []
            for (from, _) in renamed {
                oldNames.append(from)
            }
            for pageURL in ClassPages.pagesOfSection(plan.sectionNumber, in: course) {
                guard let text = try? String(contentsOf: pageURL, encoding: .utf8) else {
                    continue
                }
                let here: Int = WikiLinkRewriter.countLinks(to: oldNames, in: text)
                if here == 0 {
                    continue
                }
                let updated: String = WikiLinkRewriter.rewriting(text, renamedPages: renamed)
                if updated != text {
                    try updated.write(to: pageURL, atomically: true, encoding: .utf8)
                    linksRewritten += here
                }
            }
        }

        // 3. The dates.
        let createdKey: String = PageFrontmatter.createdKey(forSection: plan.sectionNumber, isSectionLocal: true)
        var moved: Int = 0
        for move in plan.moves {
            // A renamed page is found under its NEW name by now.
            var pageURL: URL = folderURL.appendingPathComponent(move.title + ".md")
            if !fileManager.fileExists(atPath: pageURL.path) {
                pageURL = move.fileURL
            }
            guard fileManager.fileExists(atPath: pageURL.path),
                  let text = try? String(contentsOf: pageURL, encoding: .utf8) else {
                continue
            }
            let result: (text: String, changed: Bool) = PageFrontmatter.settingCreated(
                in: text, key: createdKey, to: move.to, fallbackTail: tail
            )
            if result.changed {
                try result.text.write(to: pageURL, atomically: true, encoding: .utf8)
                moved += 1
            }
        }

        // 4. The blank pages the room was made for. Checked a second time,
        //    because the plan may be minutes old and Obsidian is open.
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var created: Int = 0
        for planned in plan.added {
            if fileManager.fileExists(atPath: planned.fileURL.path) {
                continue
            }
            let body: String = ClassPages.skeleton(
                title: planned.title,
                unit: plan.unit,
                date: planned.date,
                howMany: plan.added.count,
                tail: tail
            )
            try body.write(to: planned.fileURL, atomically: true, encoding: .utf8)
            created += 1
        }

        let message: String = "Made room for \(created) class\(created == 1 ? "" : "es") at Unit \(plan.unit), Day \(plan.atDay). Renamed \(renamed.count), moved \(moved) onto later class days, and updated \(linksRewritten) link\(linksRewritten == 1 ? "" : "s"). The new pages are unpublished until you write them — look the section over before you deploy it."
        return ClassChangeOutcome(message: message, backupURL: backupURL)
    }

    /// Only the pages named "Unit N, Day N", in unit then day order.
    ///
    /// Anything named some other way is left out entirely rather than guessed
    /// at. Those pages keep their dates, which is the honest outcome — the plan
    /// says how many were skipped so nobody is surprised.
    static func numberedClasses(among pages: [ClassPageSummary]) -> [ClassPageSummary] {
        var numbered: [ClassPageSummary] = []
        for page in pages {
            if page.unitAndDay != nil {
                numbered.append(page)
            }
        }
        numbered.sort { first, second in
            guard let left = first.unitAndDay, let right = second.unitAndDay else {
                return false
            }
            if left.unit != right.unit {
                return left.unit < right.unit
            }
            return left.day < right.day
        }
        return numbered
    }

    /// How many links across the section point at any of these page names.
    static func countLinks(to names: [String], forSection sectionNumber: Int, in course: Course) -> Int {
        if names.isEmpty {
            return 0
        }
        var total: Int = 0
        for pageURL in ClassPages.pagesOfSection(sectionNumber, in: course) {
            guard let text = try? String(contentsOf: pageURL, encoding: .utf8) else {
                continue
            }
            total += WikiLinkRewriter.countLinks(to: names, in: text)
        }
        return total
    }
}

/// A page that changes name, and the file it becomes.
struct ClassRename {

    // MARK: - Stored properties

    let from: String
    let to: String
    let fromURL: URL
    let toURL: URL

    // MARK: - Initializer

    init(from: String, to: String, fromURL: URL, toURL: URL) {
        self.from = from
        self.to = to
        self.fromURL = fromURL
        self.toURL = toURL
    }
}

/// A class that keeps its name but moves to a different day.
struct ClassDateMove {

    // MARK: - Stored properties

    /// The name the page has AFTER any rename — which is how it is found.
    let title: String
    let fileURL: URL
    let from: CalendarDay?
    let to: CalendarDay

    // MARK: - Initializer

    init(title: String, fileURL: URL, from: CalendarDay?, to: CalendarDay) {
        self.title = title
        self.fileURL = fileURL
        self.from = from
        self.to = to
    }
}

/// What making room would do. Nothing here has happened yet.
struct ClassInsertionPlan {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let unit: Int
    let atDay: Int

    /// The blank classes that would be made room for.
    let added: [PlannedClass]

    /// Pages that would be renamed, **in the order the renames must happen** —
    /// highest day first.
    let renames: [ClassRename]

    /// Every class whose date would move, under the name it will have.
    let moves: [ClassDateMove]

    /// Links that would be rewritten to follow a renamed page.
    let linksToRewrite: Int

    /// Anything the teacher should know before saying yes.
    let problems: [String]

    // MARK: - Computed properties

    var changesNothing: Bool {
        return added.isEmpty && renames.isEmpty && moves.isEmpty
    }

    /// The proposal, as a teacher would hear it.
    var description: String {
        var lines: [String] = []

        if changesNothing {
            lines.append("Nothing would change in \(courseCode) Section \(sectionNumber).")
            for problem in problems {
                lines.append("• " + problem)
            }
            return lines.joined(separator: "\n")
        }

        let room: String = added.count == 1 ? "one new class" : "\(added.count) new classes"
        lines.append("Make room for \(room) at Unit \(unit), Day \(atDay) in \(courseCode) Section \(sectionNumber).")
        lines.append("")

        lines.append("New, and unpublished until you write \(added.count == 1 ? "it" : "them"):")
        for planned in added {
            lines.append("  \(planned.title)  (\(planned.date.text) \(planned.date.weekdayName))")
        }

        if !renames.isEmpty {
            lines.append("")
            lines.append("Renamed — \(renames.count) page\(renames.count == 1 ? "" : "s"):")
            var shown: Int = 0
            for rename in renames {
                if shown >= ClassInsertionPlan.mostShown {
                    break
                }
                lines.append("  \(rename.from) → \(rename.to)")
                shown += 1
            }
            if renames.count > ClassInsertionPlan.mostShown {
                lines.append("  …and \(renames.count - ClassInsertionPlan.mostShown) more.")
            }

            // The number that matters most, and the one a teacher cannot check
            // for themselves without opening every page in the course.
            lines.append("")
            if linksToRewrite == 0 {
                lines.append("No links point at any of those names, so nothing else needs changing.")
            } else {
                lines.append("\(linksToRewrite) link\(linksToRewrite == 1 ? "" : "s") point\(linksToRewrite == 1 ? "s" : "") at those names and would be updated to match.")
            }
        }

        if !moves.isEmpty {
            lines.append("")
            lines.append("Moved to later class days — \(moves.count):")
            var shown: Int = 0
            for move in moves {
                if shown >= ClassInsertionPlan.mostShown {
                    break
                }
                let fromText: String = move.from?.text ?? "no date"
                lines.append("  \(move.title)  \(fromText) → \(move.to.text)")
                shown += 1
            }
            if moves.count > ClassInsertionPlan.mostShown {
                lines.append("  …and \(moves.count - ClassInsertionPlan.mostShown) more.")
            }
        }

        for problem in problems {
            lines.append("• " + problem)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Initializer

    init(
        courseCode: String,
        sectionNumber: Int,
        unit: Int,
        atDay: Int,
        added: [PlannedClass],
        renames: [ClassRename],
        moves: [ClassDateMove],
        linksToRewrite: Int,
        problems: [String]
    ) {
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.unit = unit
        self.atDay = atDay
        self.added = added
        self.renames = renames
        self.moves = moves
        self.linksToRewrite = linksToRewrite
        self.problems = problems
    }

    /// How many renames or moves a plan spells out before summarising.
    static let mostShown: Int = 10
}
