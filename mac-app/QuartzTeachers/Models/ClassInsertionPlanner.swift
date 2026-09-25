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
        case noNumberedClasses(String, Int, String)
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
            case .noNumberedClasses(let code, let number, let shape):
                return "\(code) Section \(number) has no pages named “\(shape)”, so there is nothing to make room in."
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

        let naming: ClassPageNaming = course.configuration.classPageNaming
        let allPages: [ClassPageSummary] = ClassPages.list(forSection: sectionNumber, in: course)
        let numbered: [ClassPageSummary] = numberedClasses(among: allPages)
        if numbered.isEmpty {
            throw Problem.noNumberedClasses(course.code, sectionNumber, naming.shapeDescription)
        }

        var problems: [String] = []
        let unnumbered: Int = allPages.count - numbered.count
        if unnumbered > 0 {
            problems.append("\(unnumbered) class page\(unnumbered == 1 ? " is" : "s are") not named “\(naming.shapeDescription)”, so \(unnumbered == 1 ? "it was" : "they were") left where \(unnumbered == 1 ? "it is" : "they are") — including \(unnumbered == 1 ? "its" : "their") date.")
        }

        if naming.isNumbered {
            return try ClassInsertionPlanner.planNumbered(
                atNumber: atDay, count: count, numbered: numbered,
                timetable: remembered.dates, problems: problems,
                forSection: sectionNumber, in: course
            )
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
                naming: naming,
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
                unit: unit, day: day, naming: course.configuration.classPageNaming
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
                unit: unit, day: numbers.day + count, naming: course.configuration.classPageNaming
            ).title
            renames.append(ClassRename(
                from: page.title,
                to: newTitle,
                fromURL: page.fileURL,
                toURL: folderURL.appendingPathComponent(newTitle + ".md")
            ))
        }

        // Dates: the new classes take the first slots, then everything shifted
        // follows in the order it was already in. (A numbered course keeps its
        // gaps instead, and never reaches here — see `planNumbered`.)
        var destinations: [CalendarDay] = []
        for index in 0..<shifted.count {
            destinations.append(runway[count + index])
        }
        var moves: [ClassDateMove] = []
        for index in 0..<shifted.count {
            let moving: ClassPageSummary = shifted[index]
            let destination: CalendarDay = destinations[index]
            if moving.date == destination {
                continue
            }
            var name: String = moving.title
            if let numbers = moving.unitAndDay, numbers.unit == unit {
                name = UnitDay(
                    unit: unit, day: numbers.day + count, naming: course.configuration.classPageNaming
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
            naming: naming,
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
        // The URLs, not just how many. A caller that is about to WRITE to one
        // of these pages has exactly one safe question — "did this run make
        // that page, or was it already somebody's lesson?" — and it cannot be
        // answered by comparing the file's text, because step 2 above rewrites
        // links inside pages it did not rename. `ClassChangeOutcome` has
        // carried the field since it was written; this planner was the one
        // that dropped it on the floor.
        var created: [URL] = []
        for planned in plan.added {
            if fileManager.fileExists(atPath: planned.fileURL.path) {
                continue
            }
            let body: String = ClassPages.skeleton(
                title: planned.title,
                unit: plan.unit,
                naming: plan.naming,
                folderName: folderURL.lastPathComponent,
                date: planned.date,
                howMany: plan.added.count,
                tail: tail
            )
            try body.write(to: planned.fileURL, atomically: true, encoding: .utf8)
            created.append(planned.fileURL)
        }

        let message: String = "Made room for \(created.count) class\(created.count == 1 ? "" : "es") at \(plan.positionTitle). Renamed \(renamed.count), moved \(moved) onto later class days, and updated \(linksRewritten) link\(linksRewritten == 1 ? "" : "s"). The new pages are unpublished until you write them — look the section over before you deploy it."
        return ClassChangeOutcome(message: message, backupURL: backupURL, created: created)
    }

    /// Making room in a numbered course (#267) — a club's "Week 1", "Week 2".
    ///
    /// **Pages order by DATE here, and the numbers may have gaps.** Russell's
    /// CODING club has Week 1, Week 2, Week 8 and Week 9 on weekly Thursdays,
    /// the pages between never written. The ordinary rule — the new page takes
    /// the day the page AT the insertion point sits on, and everything from
    /// there along is renamed one up and packed onto the next class days —
    /// was measured on that shape: "make room at Week 3" dated the new page
    /// 2025-11-20 (Week 8's day, with 10-02 free) and renamed two published
    /// meetings, Week 8 → 9 and Week 9 → 10, a week later each, to make room
    /// in a slot that was empty.
    ///
    /// So, here:
    /// * the new pages take the first free class days after the LATEST page
    ///   numbered below the insertion point — "after Week 2";
    /// * a page is renamed only when a new number would land on its name, and
    ///   the run stops at the first page whose number is already clear;
    /// * a later page keeps its date when it is already after the page before
    ///   it, and only a page whose date COLLIDES moves — to the first class
    ///   day after that page. Only then does the plan list a move.
    ///
    /// In a numbered course with no gaps (a club filled one page at a time)
    /// this gives the same answer as the ordinary rule.
    static func planNumbered(
        atNumber: Int,
        count: Int,
        numbered: [ClassPageSummary],
        timetable: [CalendarDay],
        problems startingProblems: [String],
        forSection sectionNumber: Int,
        in course: Course
    ) throws -> ClassInsertionPlan {
        let naming: ClassPageNaming = course.configuration.classPageNaming
        var problems: [String] = startingProblems

        // Below the insertion point stays; at or after it may move.
        var shifted: [ClassPageSummary] = []
        var untouched: [ClassPageSummary] = []
        for page in numbered {
            guard let numbers = page.unitAndDay else {
                continue
            }
            if numbers.day >= atNumber {
                shifted.append(page)
            } else {
                untouched.append(page)
            }
        }

        // The latest date among the pages that stay — "after Week 2", by
        // date, which is also after every other page below the insertion.
        var held: [CalendarDay] = []
        var latestKept: CalendarDay? = nil
        for page in untouched {
            guard let date = page.date else {
                continue
            }
            held.append(date)
            if let current = latestKept, current >= date {
                continue
            }
            latestKept = date
        }
        var runway: [CalendarDay] = []
        for date in timetable {
            if held.contains(date) {
                continue
            }
            if let latestKept, date <= latestKept {
                continue
            }
            runway.append(date)
        }
        runway.sort()

        if runway.count < count {
            let missing: Int = count - runway.count
            let from: String = latestKept?.text ?? "the start of the course"
            problems.append("This needs \(count) class day\(count == 1 ? "" : "s") after \(from) and the timetable only has \(runway.count). Add \(missing) more class date\(missing == 1 ? "" : "s") and ask again.")
            return ClassInsertionPlan(
                courseCode: course.code, sectionNumber: sectionNumber,
                unit: 1, atDay: atNumber, naming: naming,
                added: [], renames: [], moves: [], linksToRewrite: 0, problems: problems
            )
        }

        let folderURL: URL = ClassPages.folderURL(forSection: sectionNumber, in: course)
        var added: [PlannedClass] = []
        for offset in 0..<count {
            let number: Int = atNumber + offset
            let title: String = naming.title(unit: 1, day: number)
            added.append(PlannedClass(
                title: title,
                fileURL: folderURL.appendingPathComponent(title + ".md"),
                day: number,
                date: runway[offset]
            ))
        }

        // Renames: only the run whose numbers the new pages would land on.
        // `shifted` is in number order (see `numberedClasses`).
        var newNames: [String: String] = [:]
        var renamesUpward: [ClassRename] = []
        var firstClearNumber: Int = atNumber + count
        for page in shifted {
            guard let numbers = page.unitAndDay else {
                continue
            }
            if numbers.day >= firstClearNumber {
                break
            }
            let newTitle: String = naming.title(unit: 1, day: firstClearNumber)
            renamesUpward.append(ClassRename(
                from: page.title,
                to: newTitle,
                fromURL: page.fileURL,
                toURL: folderURL.appendingPathComponent(newTitle + ".md")
            ))
            newNames[page.title] = newTitle
            firstClearNumber += 1
        }
        // Highest number first — see `apply` for why the order is part of the
        // plan.
        var renames: [ClassRename] = []
        for rename in renamesUpward.reversed() {
            renames.append(rename)
        }

        // Dates, in DATE order: a page already after the one before it stays.
        let shiftedByDate: [ClassPageSummary] = ClassInsertionPlanner.inDateOrder(shifted)
        guard let destinations = ClassInsertionPlanner.destinationsKeepingGaps(
            for: shiftedByDate, after: runway, skippingFirst: count
        ) else {
            problems.append("There are not enough class days after the last page to move it onto. Add more class dates and ask again.")
            return ClassInsertionPlan(
                courseCode: course.code, sectionNumber: sectionNumber,
                unit: 1, atDay: atNumber, naming: naming,
                added: [], renames: [], moves: [], linksToRewrite: 0, problems: problems
            )
        }
        var moves: [ClassDateMove] = []
        for index in 0..<shiftedByDate.count {
            let moving: ClassPageSummary = shiftedByDate[index]
            // An undated page has no date to collide with, and is never
            // given one (see `destinationsKeepingGaps`).
            guard let destination = destinations[index] else {
                continue
            }
            if moving.date == destination {
                continue
            }
            moves.append(ClassDateMove(
                title: newNames[moving.title] ?? moving.title,
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
            unit: 1,
            atDay: atNumber,
            naming: naming,
            added: added,
            renames: renames,
            moves: moves,
            linksToRewrite: countLinks(to: renamedFrom, forSection: sectionNumber, in: course),
            problems: problems
        )
    }

    /// Pages by date, earliest first, the number deciding a tie — and a page
    /// with NO date placed by its NUMBER among its neighbours: just before the
    /// first dated page numbered above it. How a numbered course orders (#267).
    ///
    /// Not "undated last", which the fix round first did: the fix review
    /// measured Week 1 undated, Week 2 on 09-25, Week 8 on 11-20 and "make
    /// room at 1" giving the old Week 1 (now Week 2) the date 11-27 — after
    /// Week 8, so the front page, which follows the latest date, would have
    /// jumped to it.
    static func inDateOrder(_ pages: [ClassPageSummary]) -> [ClassPageSummary] {
        var dated: [ClassPageSummary] = []
        var undated: [ClassPageSummary] = []
        for page in pages {
            if page.date == nil {
                undated.append(page)
            } else {
                dated.append(page)
            }
        }
        dated.sort { first, second in
            if let left = first.date, let right = second.date, left != right {
                return left < right
            }
            return (first.unitAndDay?.day ?? 0) < (second.unitAndDay?.day ?? 0)
        }
        undated.sort { first, second in
            return (first.unitAndDay?.day ?? 0) < (second.unitAndDay?.day ?? 0)
        }
        var ordered: [ClassPageSummary] = []
        var nextUndated: Int = 0
        for page in dated {
            let number: Int = page.unitAndDay?.day ?? 0
            while nextUndated < undated.count && (undated[nextUndated].unitAndDay?.day ?? 0) < number {
                ordered.append(undated[nextUndated])
                nextUndated += 1
            }
            ordered.append(page)
        }
        while nextUndated < undated.count {
            ordered.append(undated[nextUndated])
            nextUndated += 1
        }
        return ordered
    }

    /// The one number a make-room request names in a numbered course
    /// (#267), read from the tool's two arguments.
    ///
    /// The schema still says `unit` and `atDay`, and is not changed (routing
    /// was measured against it), so "make room at Week 5" may arrive as
    /// `atDay: 5`, as `unit: 5`, as `unit: 1, atDay: 5`, or — the reading a
    /// Unit/Day habit produces — as `unit: 5, atDay: 1`. Every one of those
    /// names 5. Two DIFFERENT numbers neither of which is 1 cannot be read,
    /// and nil is returned so the teacher is asked rather than having pages
    /// renamed at a guess: making room renames pages the teacher's links
    /// point at, which is the wrong thing to be wrong about.
    static func numberedPosition(unit: Int?, atDay: Int?) -> Int? {
        guard let unit else {
            return atDay
        }
        guard let atDay else {
            return unit
        }
        if unit == atDay {
            return unit
        }
        if unit == 1 {
            return atDay
        }
        if atDay == 1 {
            return unit
        }
        return nil
    }

    /// Where each shifted page goes in a course that keeps its gaps. A page
    /// already dated after the page before it stays where it is; otherwise
    /// it takes the first runway day after that page (the new pages take the
    /// first `skippingFirst`), which is always later than its own date. A page
    /// with NO date stays undated (nil) and is passed over: it has no date to
    /// collide with, and giving it one would be a move nothing forced. Nil
    /// overall when a page has nowhere to go. Pure, so the rule can be tested
    /// alone.
    static func destinationsKeepingGaps(
        for shifted: [ClassPageSummary], after runway: [CalendarDay], skippingFirst: Int
    ) -> [CalendarDay?]? {
        var destinations: [CalendarDay?] = []
        var previous: CalendarDay? = nil
        if skippingFirst > 0 && skippingFirst <= runway.count {
            previous = runway[skippingFirst - 1]
        }
        for page in shifted {
            if page.date == nil {
                destinations.append(nil)
                continue
            }
            var chosen: CalendarDay? = nil
            // Already after the page before it: it does not move at all.
            if let own = page.date {
                if let previous {
                    if own > previous {
                        chosen = own
                    }
                } else {
                    chosen = own
                }
            }
            if chosen == nil {
                for date in runway {
                    if let previous, date <= previous {
                        continue
                    }
                    chosen = date
                    break
                }
            }
            guard let chosen else {
                return nil
            }
            destinations.append(chosen)
            previous = chosen
        }
        return destinations
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

    /// How the course names its pages, so the position is said the way the
    /// course writes it — "Unit 3, Day 4", "Module 3, Day 4", "Week 4" —
    /// rather than rebuilt as "Unit … Day …" by hand, which is how a Module
    /// course was told "at Unit 3, Day 4" (#268).
    let naming: ClassPageNaming

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

    /// Where the room is made, named as the course names a page.
    var positionTitle: String {
        return naming.title(unit: unit, day: atDay)
    }

    /// Whether anything OTHER than the new pages is disturbed.
    ///
    /// **Renames and date moves are equally irreversible, and only one of them
    /// is obvious.** A rename is inside the target unit; a move re-dates every
    /// class of every LATER unit. Making room in a short unit can therefore
    /// rename nothing and move a teacher's whole year — so a warning keyed on
    /// renames alone stays silent in exactly the case that hurts most.
    var movesAnythingElse: Bool {
        return renames.isEmpty == false || moves.isEmpty == false
    }

    /// How many OTHER class pages move, counted once each.
    ///
    /// **The union of the two lists, not either one of them.** A renamed page
    /// is usually re-dated as well, so the lists overlap; a LATER unit's pages
    /// are re-dated and never renamed. `moves` carries each page under the
    /// name it will HAVE — see the comment where `moves` is built — which is
    /// what makes a union on names dedupe a page that is in both lists. Adding
    /// the two counts instead would say 5 where three pages move.
    ///
    /// Counting renames alone is what made the duplicate's plan card silent in
    /// exactly the shape that moves a teacher's whole year, which is the
    /// reason this exists rather than a nicety. Mirrors Windows'
    /// `DuplicateClassPlan.OtherClassesMoving`.
    var otherClassesMoving: Int {
        var names: [String] = []
        for rename in renames {
            let name: String = rename.to.lowercased()
            if !names.contains(name) {
                names.append(name)
            }
        }
        for move in moves {
            let name: String = move.title.lowercased()
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names.count
    }

    /// The proposal, as a teacher would hear it — and as the model reads it,
    /// which is why this form always says "class".
    var description: String {
        return describe(noun: .class)
    }

    /// The proposal in the course's own noun (#267): "meeting" on a club's
    /// card. Only the card takes this; see `AssistToolOutcome.planned`.
    func describe(noun: ClassNoun) -> String {
        var lines: [String] = []

        if changesNothing {
            lines.append("Nothing would change in \(courseCode) Section \(sectionNumber).")
            for problem in problems {
                lines.append("• " + problem)
            }
            return lines.joined(separator: "\n")
        }

        lines.append(AssistWording.wouldMakeRoom(
            count: added.count, at: positionTitle,
            course: courseCode, section: "\(sectionNumber)", noun: noun
        ))
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
            lines.append(AssistWording.movedToLaterDays(count: moves.count, noun: noun))
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
        naming: ClassPageNaming,
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
        self.naming = naming
        self.added = added
        self.renames = renames
        self.moves = moves
        self.linksToRewrite = linksToRewrite
        self.problems = problems
    }

    /// How many renames or moves a plan spells out before summarising.
    static let mostShown: Int = 10
}
