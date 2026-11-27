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
    enum Problem: LocalizedError, SaidInACoursesNoun {
        case unitOutOfRange
        case dayOutOfRange
        case countOutOfRange
        case noTimetable(String, Int)
        case noNumberedClasses(String, Int, String)
        case wouldNotFit(String)
        case wrongCourse(String, String)

        var errorDescription: String? {
            return sentence(noun: .class)
        }

        /// The refusal in a course's own noun (#1027): "meeting" in a club.
        /// The model is given `errorDescription`, the class form (#267).
        func sentence(noun: ClassNoun) -> String {
            switch self {
            case .unitOutOfRange, .dayOutOfRange:
                return "Unit and day numbers start at 1."
            case .countOutOfRange:
                return AssistWording.askForAtLeastOneClass(noun: noun)
            case .noTimetable(let code, let number):
                return AssistWording.cannotMoveClassesWithoutDates(code: code, number: number, noun: noun)
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

        var problems: [PlanProblem] = []
        let unnumbered: Int = allPages.count - numbered.count
        if unnumbered > 0 {
            let shape: String = naming.shapeDescription
            problems.append(PlanProblem { noun in
                AssistWording.pagesNotNamedTheCoursesWay(count: unnumbered, shape: shape, noun: noun)
            })
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
            let from: String = firstFree?.text ?? "the end of the course"
            let has: Int = runway.count
            problems.append(PlanProblem { noun in
                AssistWording.timetableTooShortFrom(needed: needed, from: from, has: has, noun: noun)
            })
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

    /// The pages making room could not finish, by kind (#425) — the reply
    /// names them, the trail counts them.
    struct NotFinished: Equatable {

        // MARK: - Stored properties

        var notRenamed: [String] = []
        var notReDated: [String] = []
        var linksNotUpdated: [String] = []
        var newNotAdded: [String] = []

        // MARK: - Computed properties

        /// Every page named once, in the order met.
        var pages: [String] {
            var named: [String] = []
            for list in [notRenamed, notReDated, linksNotUpdated, newNotAdded] {
                for name in list where !named.contains(name) {
                    named.append(name)
                }
            }
            return named
        }

        /// The contract's line: `activityTrail.mustRecord` → "making room did
        /// not finish every page" → `line`. Counts only, never names.
        var trailLine: String {
            let count: Int = pages.count
            let pageWord: String = count == 1 ? "page" : "pages"
            return "making room for a class did not finish \(count) \(pageWord): "
                 + "\(notRenamed.count) not renamed, \(notReDated.count) not re-dated, "
                 + "\(linksNotUpdated.count) with links not updated, \(newNotAdded.count) new not added"
        }
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
    ///
    /// **Makes no backup of its own** (#351): the parameter that could ask
    /// for one was passed by no caller, and it zipped on the main actor.
    /// The assistant — the only caller that changes a course this way —
    /// saves its copy first, once per conversation, off the main actor.
    @discardableResult
    static func apply(
        _ plan: ClassInsertionPlan,
        in course: Course,
        by maker: UndoStepMaker = UndoStepMaker.sheet("makeRoomForClasses"),
        into outerStep: JournaledStep? = nil
    ) throws -> ClassChangeOutcome {
        if plan.courseCode != course.code {
            throw Problem.wrongCourse(plan.courseCode, course.code)
        }
        if plan.changesNothing {
            return ClassChangeOutcome(message: "Nothing needed moving.")
        }
        if plan.added.isEmpty {
            throw Problem.wouldNotFit(plan.problems.joined(separator: " "))
        }
        // Where each later class that is a link leads, judged hop by hop on
        // the disk as it stands, before anything is planned (#899 U4b3
        // relink-5, `undo.rule.shadow`).
        let classPagePlaces: [ClassPagePlace] = classPagePlaces(of: plan, in: course)
        let workingFolder: URL? = workingFolderURL(of: course)

        // ONE step through the door (#899, U3): every rename, link, date and
        // new page planned first, each read as the step will leave it, then
        // written together, all or none. Given a step (Duplicate Class), the
        // caller adds to it and makes it.
        let step: JournaledStep = outerStep
            ?? JournaledStep(course: course, section: plan.sectionNumber, maker: maker)
        let folderURL: URL = ClassPages.folderURL(forSection: plan.sectionNumber, in: course)
        // The section's classes as they stand, before anything is planned:
        // who comes first among classes that lead to one file (#1048).
        let classesBefore: [ClassPageSummary] = ClassPages.list(forSection: plan.sectionNumber, in: course)
        let tail: String = ClassPages.siblingTimeAndOffset(
            from: classesBefore,
            forSection: plan.sectionNumber
        )

        // What could not be finished, by kind (#425, adopted from Windows'
        // #422). A write that fails part way used to THROW out of here with
        // the earlier renames already on disk and nothing said about which;
        // a rename whose new name was taken was skipped in silence, and so was
        // a new class whose name was still in use. Now each is carried past,
        // counted, named in the reply and recorded on the trail, and every
        // count in the reply is of what was WRITTEN.
        var notFinished: NotFinished = NotFinished()

        // 1. The renames, highest day first.
        var renamed: [String: String] = [:]
        // The in-between links inside the working folder already re-pointed
        // where they stand (mac-2): each once, however many classes reach it.
        var hopsRePointed: [HopEntry] = []
        for rename in plan.renames {
            // A later class that is a link leading to nothing is still a
            // class: its link is renamed as any other (Russell, 2026-11-26:
            // "Why would it refuse? Why does it care where a later class
            // links to?"), and nothing is written for it or through it.
            let reach: LinkedClassReach = reachOfALinkedClass(at: rename.fromURL, classPagePlaces: classPagePlaces)
            let isABrokenLink: Bool = isALinkToNothing(rename.fromURL)
            if reach == .elsewhere && !isABrokenLink && !step.fileExists(rename.fromURL) {
                continue
            }
            if step.fileExists(rename.toURL) {
                notFinished.notRenamed.append(rename.from)
                continue
            }
            if case .aRenamedPageThrough(let hop, let newPlace) = reach, isInside(workingFolder, hop) {
                // mac-2 (#899, ruling 6 of U4b3, Russell, 2026-11-26): the
                // class reaches a renamed class page only through a link
                // inside the working folder that is not a class page. The
                // class is renamed as itself, its text kept, and the link in
                // between is re-pointed WHERE IT STANDS at the page's new
                // name, so the chain still leads to the same lesson. Nothing
                // is written through either link.
                guard let linkSha = UndoTreeReading.linkSha(at: rename.fromURL),
                      rePointWhereItStands(hop, at: newPlace, in: step, done: &hopsRePointed) else {
                    notFinished.notRenamed.append(rename.from)
                    continue
                }
                step.moveLink(spelledAsItsNewPlace(rename.fromURL, beside: rename.toURL), to: rename.toURL, linkSha: linkSha)
            } else if reach != .elsewhere {
                // A later class whose link leads to another class page of
                // this section (Russell, 2026-11-26): renamed, kept leading
                // to the same lesson, and nothing written through it, no
                // title and no date (that lesson's page takes its own date
                // from its own move, or keeps its own when the plan leaves
                // it).
                guard let textAfter = textAfterTheMove(of: rename.fromURL, reach: reach) else {
                    notFinished.notRenamed.append(rename.from)
                    continue
                }
                let linkPlace: URL = spelledAsItsNewPlace(rename.fromURL, beside: rename.toURL)
                if !step.relinkLink(linkPlace, to: rename.toURL, textAfter: textAfter) {
                    notFinished.notRenamed.append(rename.from)
                    continue
                }
            } else if isABrokenLink || isALinkToAFile(rename.fromURL) {
                // A later class that is a symbolic link to a file (#899
                // U4b3, `undo.rule.shadow`): the LINK is moved as itself to
                // the new name, judged by the target it holds, never
                // followed, as Rename folder moves a linked folder. The
                // file it leads to is never moved, renamed or removed, and
                // never retitled: "Shared pages never have day “x” titles
                // in them" (Russell, 2026-11-26). Only the moved date is
                // written into it (step 3). The place the link leaves is
                // handed over, in this same step, to the class below it or
                // the new class. A broken link is moved the same way, and
                // as it leads to no file, no date is written for it.
                guard let linkSha = UndoTreeReading.linkSha(at: rename.fromURL) else {
                    notFinished.notRenamed.append(rename.from)
                    continue
                }
                step.moveLink(spelledAsItsNewPlace(rename.fromURL, beside: rename.toURL), to: rename.toURL, linkSha: linkSha)
            } else {
                guard let text = step.readText(rename.fromURL) else {
                    notFinished.notRenamed.append(rename.from)
                    continue
                }
                // The title inside the file follows the file name: a page
                // whose name and title disagree is worse than either being
                // wrong alone.
                let retitled: String = PageFrontmatter.settingTitle(in: text, to: rename.to)
                step.write(retitled, to: rename.toURL)
                step.remove(rename.fromURL)
            }
            renamed[rename.from] = rename.to
        }

        // 1b. A class the plan only re-dates, not renames, whose link reaches
        //     a renamed class page (mac-2): re-pointed where it stands by the
        //     same rules. Its own text when its text names the page; the
        //     in-between link when the hop is inside the working folder; its
        //     own link straight at the page's new place when the hop is
        //     outside, where Plantoir never writes. Nothing written through.
        var renamedPlaces: [String] = []
        for rename in plan.renames {
            renamedPlaces.append(rename.fromURL.standardizedFileURL.path)
        }
        for move in plan.moves {
            if renamedPlaces.contains(move.fileURL.standardizedFileURL.path) {
                continue
            }
            let reach: LinkedClassReach = reachOfALinkedClass(at: move.fileURL, classPagePlaces: classPagePlaces)
            switch reach {
            case .elsewhere, .aClassPageTheyLeave:
                continue
            case .aRenamedPageThrough(let hop, let newPlace) where isInside(workingFolder, hop):
                if !rePointWhereItStands(hop, at: newPlace, in: step, done: &hopsRePointed) {
                    notFinished.linksNotUpdated.append(move.title)
                }
            case .aRenamedPageByItsOwnText, .aRenamedPageThrough:
                guard let textAfter = textAfterTheMove(of: move.fileURL, reach: reach),
                      step.relinkLink(move.fileURL, to: move.fileURL, textAfter: textAfter) else {
                    notFinished.linksNotUpdated.append(move.title)
                    continue
                }
            }
        }

        // 2. The links that pointed at the old names. Ours to do — Obsidian
        //    only rewrites links when Obsidian performs the rename.
        var linksRewritten: Int = 0
        if !renamed.isEmpty {
            var oldNames: [String] = []
            for (from, _) in renamed {
                oldNames.append(from)
            }
            let pagesAsPlanned: [URL] = step.markdownFiles(
                under: course.directoryURL, onDisk: ClassPages.pagesOfSection(plan.sectionNumber, in: course)
            )
            for pageURL in pagesAsPlanned {
                guard let text = step.readText(pageURL) else {
                    continue
                }
                let here: Int = WikiLinkRewriter.countLinks(to: oldNames, in: text)
                if here == 0 {
                    continue
                }
                let updated: String = WikiLinkRewriter.rewriting(text, renamedPages: renamed)
                if updated != text {
                    step.write(updated, to: pageURL)
                    linksRewritten += here
                }
            }
        }

        // 3. The dates.
        // An ordinary class page lives in the section's folder: `created`.
        // A class that is a link takes the key its FILE's place calls for
        // (Russell, 2026-11-26): `createdSection<N>` for a course-level
        // page, every other section's line left as it is
        // (`ClassPages.dateKey`).
        var moved: Int = 0
        // Pages whose settings have no place a new date line can go (#186).
        // Named and carried on past: such a page had no date this app could
        // read before the rename either, so the class list is left exactly as
        // it was about it.
        var notDated: [String] = []
        for move in plan.moves {
            // A class that is a link leading to nothing has no file to date,
            // and nothing is ever written through it (Russell, 2026-11-26):
            // its new name would be read back through the place it leaves.
            if isALinkToNothing(move.fileURL) {
                continue
            }
            // Nor through a class that is a link to another class page of
            // this section (Russell, 2026-11-26): writing this class's date
            // through it would give that lesson another class's date.
            if reachOfALinkedClass(at: move.fileURL, classPagePlaces: classPagePlaces) != .elsewhere {
                continue
            }
            // A renamed page is found under its NEW name by now — but only if
            // THIS run renamed it (#425): when its rename could not be done,
            // the page under the new name is somebody else's, and re-dating it
            // would move a page the plan never meant.
            var wasRenamedHere: Bool = false
            for (_, to) in renamed where to == move.title {
                wasRenamedHere = true
            }
            // A page whose rename did not happen is re-dated at its OLD path,
            // as Windows does (#422): the move was planned for that page.
            var pageURL: URL = move.fileURL
            if wasRenamedHere {
                pageURL = folderURL.appendingPathComponent(move.title + ".md")
            }
            guard step.fileExists(pageURL), let text = step.readText(pageURL) else {
                continue
            }
            // The key from the place of the file the class IS (#1048), the
            // one rule every reader and writer of a class's date calls.
            guard let createdKey = ClassPages.dateKey(
                ofPageAt: move.fileURL, forSection: plan.sectionNumber, in: course
            ) else {
                continue
            }
            // A shared lesson several classes link to keeps the date of the
            // FIRST of them (Russell on #899, 2026-11-26): the plan keeps the
            // classes in order, so the first by the old names is the first
            // by the new ones, and a later class writes nothing through.
            if !ClassPages.isTheFirstClassLeadingToItsFile(move.fileURL, among: classesBefore) {
                continue
            }
            let result: (text: String, outcome: FrontmatterWriteOutcome) = PageFrontmatter.settingCreated(
                in: text, key: createdKey, to: move.to, fallbackTail: tail
            )
            if result.outcome == .written {
                step.write(result.text, to: pageURL)
                moved += 1
            }
            if result.outcome == .noRoomForAKey {
                notDated.append(pageURL.deletingPathExtension().lastPathComponent)
            }
        }
        if !notDated.isEmpty {
            ActivityTrail.note(
                .pageSettingsLeftAsTheyWere,
                ActivityTrail.pageSettingsLeftAsTheyWereLine(act: "making room for a class", pages: notDated.count),
                course: course.code,
                section: plan.sectionNumber
            )
        }

        // 4. The blank pages the room was made for. Checked a second time,
        //    because the plan may be minutes old and Obsidian is open.
        // The URLs, not just how many. A caller that is about to WRITE to one
        // of these pages has exactly one safe question — "did this run make
        // that page, or was it already somebody's lesson?" — and it cannot be
        // answered by comparing the file's text, because step 2 above rewrites
        // links inside pages it did not rename. `ClassChangeOutcome` has
        // carried the field since it was written; this planner was the one
        // that dropped it on the floor.
        var created: [URL] = []
        for planned in plan.added {
            if step.fileExists(planned.fileURL) {
                notFinished.newNotAdded.append(planned.title)
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
            step.write(body, to: planned.fileURL)
            created.append(planned.fileURL)
        }
        // The folder the new pages go in is made by the door with them.
        if outerStep == nil {
            try step.make()
        }

        var message: String = "Made room for \(created.count) class\(created.count == 1 ? "" : "es") at \(plan.positionTitle). Renamed \(renamed.count), moved \(moved) onto later class days, and updated \(linksRewritten) link\(linksRewritten == 1 ? "" : "s"). The new pages are unpublished until you write them — look the section over before you deploy it."
        var leftUndone: [String] = []
        if !notDated.isEmpty {
            message += " " + AssistPublishPlan.sayingPagesWhoseNewDateCouldNotBeSet(named: notDated)
            leftUndone.append(AssistPublishPlan.sayingPagesWhoseNewDateCouldNotBeSet(named: notDated, fromTheMenu: true))
        }
        let unfinished: [String] = notFinished.pages
        if !unfinished.isEmpty {
            ActivityTrail.note(
                .makingRoomDidNotFinishEveryPage,
                notFinished.trailLine,
                course: course.code,
                section: plan.sectionNumber
            )
            message += " " + AssistWording.pagesAChangeCouldNotFinish(
                AssistPublishPlan.listingAFew(unfinished), count: unfinished.count
            )
            leftUndone.append(AssistWording.pagesAChangeCouldNotFinishFromTheMenu(
                AssistPublishPlan.listingAFew(unfinished), count: unfinished.count
            ))
        }
        return ClassChangeOutcome(
            message: message, created: created, leftUndoneFromTheMenu: leftUndone.joined(separator: " "),
            wroteSomething: !created.isEmpty || !renamed.isEmpty || moved > 0 || linksRewritten > 0
        )
    }

    /// Whether the page at `url` is a symbolic link (read without following
    /// it, `lstat`) whose target is a regular file. A link to a folder, a
    /// dangling link or anything else is not, and is handled as before.
    static func isALinkToAFile(_ url: URL) -> Bool {
        var linkStatus: stat = stat()
        let linkResult: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &linkStatus)
        }
        if linkResult != 0 || (linkStatus.st_mode & S_IFMT) != S_IFLNK {
            return false
        }
        var targetStatus: stat = stat()
        let targetResult: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return stat(path, &targetStatus)
        }
        return targetResult == 0 && (targetStatus.st_mode & S_IFMT) == S_IFREG
    }

    /// The link's place spelled from the same folder as its new place, when
    /// the two are in one folder. The step finds a place by its spelling,
    /// and a listed page can carry a spelling of the folder its new name
    /// does not: the folder lister names `/private/var/...` where the plan
    /// names `/var/...`, and standardizing drops `/private` only from a path
    /// that leads somewhere, never from a link that leads to nothing. Spelled
    /// apart, the class below would not find the place the link leaves and
    /// would write THROUGH the link.
    static func spelledAsItsNewPlace(_ url: URL, beside newPlace: URL) -> URL {
        let folder: URL = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let newFolder: URL = newPlace.deletingLastPathComponent().resolvingSymlinksInPath()
        if folder.path != newFolder.path {
            return url
        }
        return newPlace.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent)
    }

    /// Whether the page at `url` is a symbolic link that leads to nothing:
    /// `lstat` sees the link, `stat` cannot follow it to anything (its
    /// target, or a link further along, is not there, or the links go
    /// round). Insert Class renames such a link as itself and writes
    /// nothing through it (Russell, 2026-11-26).
    static func isALinkToNothing(_ url: URL) -> Bool {
        return ResolvedFile.isALink(url) && ResolvedFile.throughLinks(at: url) == nil
    }

    /// The file a symbolic link at `url` leads to, followed link by link
    /// (each target read as written, a relative one against its link's
    /// folder), or nil when `url` is not a link or the chain does not end
    /// at a file within 32 links. The folders above keep the spelling the
    /// course uses, so the answer compares with the course's own paths.
    static func fileALinkLeadsTo(_ url: URL) -> URL? {
        if !ResolvedFile.isALink(url) {
            return nil
        }
        var here: URL = url
        var hops: Int = 0
        while ResolvedFile.isALink(here) {
            hops += 1
            guard hops <= 32, let written = try? FileManager.default.destinationOfSymbolicLink(atPath: here.path) else {
                return nil
            }
            if written.hasPrefix("/") {
                here = URL(fileURLWithPath: written).standardizedFileURL
            } else {
                here = URL(fileURLWithPath: written, relativeTo: here.deletingLastPathComponent()).standardizedFileURL
            }
        }
        return here
    }

    /// Every class page of the section as it stands (a plain page or a
    /// link), by its own `lstat` identity, with its new place when the plan
    /// renames it.
    static func classPagePlaces(of plan: ClassInsertionPlan, in course: Course) -> [ClassPagePlace] {
        var renamedPlaces: [(identity: ResolvedFile, newPlace: URL)] = []
        for rename in plan.renames {
            if let identity = ResolvedFile.ofThePlace(at: rename.fromURL) {
                renamedPlaces.append((identity: identity, newPlace: rename.toURL))
            }
        }
        var result: [ClassPagePlace] = []
        for page in ClassPages.list(forSection: plan.sectionNumber, in: course) {
            guard let identity = ResolvedFile.ofThePlace(at: page.fileURL) else {
                continue
            }
            var newPlace: URL? = nil
            for renamed in renamedPlaces where renamed.identity == identity {
                newPlace = renamed.newPlace
            }
            result.append(ClassPagePlace(identity: identity, newPlace: newPlace))
        }
        return result
    }

    /// The working folder holding the course's `courses` folder, or nil.
    static func workingFolderURL(of course: Course) -> URL? {
        let coursesFolder: URL = course.directoryURL.standardizedFileURL.deletingLastPathComponent()
        if coursesFolder.lastPathComponent != "courses" {
            return nil
        }
        return coursesFolder.deletingLastPathComponent()
    }

    /// Where the later class at `place` leads, when it is a symbolic link,
    /// judged hop by hop (review C of U4b3: "check every hop's own identity,
    /// not just the end"): each hop is the place the link before it names
    /// (a relative text read against that link's folder), compared by its
    /// own `lstat` identity, never by name or spelling, with every class
    /// page of the section as it stands, at most 32 hops. The first class
    /// page met decides. The link's own place is never counted, so a chain
    /// that comes round to it leads nowhere (`.elsewhere`).
    static func reachOfALinkedClass(at place: URL, classPagePlaces: [ClassPagePlace]) -> LinkedClassReach {
        if !ResolvedFile.isALink(place) {
            return .elsewhere
        }
        let ownPlace: ResolvedFile? = ResolvedFile.ofThePlace(at: place)
        var here: URL = place
        var hops: Int = 0
        while ResolvedFile.isALink(here) && hops < 32 {
            hops += 1
            guard let written = try? FileManager.default.destinationOfSymbolicLink(atPath: here.path) else {
                return .elsewhere
            }
            var next: URL = URL(fileURLWithPath: written)
            if !written.hasPrefix("/") {
                next = here.deletingLastPathComponent().appendingPathComponent(written)
            }
            guard let hop = ResolvedFile.ofThePlace(at: next) else {
                return .elsewhere
            }
            if hop == ownPlace {
                return .elsewhere
            }
            for classPage in classPagePlaces where classPage.identity == hop {
                guard let newPlace = classPage.newPlace else {
                    return .aClassPageTheyLeave
                }
                if hops == 1 {
                    return .aRenamedPageByItsOwnText(newName: newPlace.lastPathComponent)
                }
                return .aRenamedPageThrough(link: here, newPlace: newPlace)
            }
            here = next
        }
        return .elsewhere
    }

    /// The text the class's link at `place` holds after the step, for a
    /// link that leads to another class page of the section, or nil when it
    /// cannot be read now.
    ///
    /// * Its own text names a renamed page: that text with ONLY its last
    ///   path part replaced by the page's new file name. Insert Class
    ///   renames the page within its own folder and the link within its
    ///   own, so neither folder changes, and every other part of the text,
    ///   relative (`./`, `../Unit 1/`) or absolute, still leads to the
    ///   page's folder: the text keeps its own form.
    /// * It reaches a renamed page only through a link that is not a class
    ///   page, and that link is outside the working folder, where Plantoir
    ///   never writes: the class's own link is re-pointed straight at the
    ///   page's new place (relative to the link's own folder, as the
    ///   section's own links are written), so it still leads to the same
    ///   lesson; the link outside is left as it is.
    /// * It reaches a class page the plan leaves: its text as it is.
    static func textAfterTheMove(of place: URL, reach: LinkedClassReach) -> Data? {
        guard let written = try? FileManager.default.destinationOfSymbolicLink(atPath: place.path) else {
            return nil
        }
        switch reach {
        case .elsewhere, .aClassPageTheyLeave:
            return Data(written.utf8)
        case .aRenamedPageByItsOwnText(let newName):
            var folderPart: String = ""
            if let lastSlash = written.lastIndex(of: "/") {
                folderPart = String(written[...lastSlash])
            }
            return Data((folderPart + newName).utf8)
        case .aRenamedPageThrough(_, let newPlace):
            return Data(relativeText(from: place.deletingLastPathComponent(), to: newPlace).utf8)
        }
    }

    /// The text a link in `folder` holds to lead to `file`: the path from
    /// one to the other, `../` for each folder up, both read with the links
    /// above them resolved, so `/var` and `/private/var` are one.
    static func relativeText(from folder: URL, to file: URL) -> String {
        let fromParts: [String] = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let toParts: [String] = file.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var shared: Int = 0
        while shared < fromParts.count && shared < toParts.count && fromParts[shared] == toParts[shared] {
            shared += 1
        }
        var text: String = ""
        var up: Int = shared
        while up < fromParts.count {
            text += "../"
            up += 1
        }
        var down: Int = shared
        while down < toParts.count {
            text += toParts[down] + "/"
            down += 1
        }
        return text + file.lastPathComponent
    }

    /// mac-2 (#899, ruling 6 of U4b3): re-points the in-between link at
    /// `hop` (inside the working folder, not a class page) where it stands,
    /// its own text with only the last path part replaced by `newPlace`'s
    /// file name, planned once however many classes reach it. `done` holds
    /// the hops already planned, each by the DIRECTORY ENTRY it is
    /// (`HopEntry`: its folder's identity and its name as that folder holds
    /// it), because the exchange re-points one entry: two spellings of one
    /// entry, by letter case or through a linked folder, are one hop
    /// (review 1 of mac-2, LOW 2), and two names of one hard-linked link are
    /// two (review 2 of mac-2, LOW 1). False when its text cannot be read
    /// now or the step will not take the relink.
    static func rePointWhereItStands(_ hopAsReached: URL, at newPlace: URL, in step: JournaledStep, done: inout [HopEntry]) -> Bool {
        // Only the folders above are tidied (`..` taken out there): the
        // link itself is never followed, as tidying a whole path holding
        // `..` would follow it to the page it leads to.
        let hop: URL = hopAsReached.deletingLastPathComponent().standardizedFileURL
            .appendingPathComponent(hopAsReached.lastPathComponent)
        guard let entry = HopEntry.of(hop) else {
            return false
        }
        if done.contains(entry) {
            return true
        }
        guard let textAfter = textAfterTheMove(of: hop, reach: .aRenamedPageByItsOwnText(newName: newPlace.lastPathComponent)) else {
            return false
        }
        if !step.relinkLink(hop, to: hop, textAfter: textAfter) {
            return false
        }
        done.append(entry)
        return true
    }

    /// Whether the link at `place` is inside `workingFolder` (the folders
    /// above it resolved, the link itself never followed).
    static func isInside(_ workingFolder: URL?, _ place: URL) -> Bool {
        guard let workingFolder else {
            return false
        }
        return UndoFolderPlaces.placeResolvingOnlyAbove(workingFolder, of: place) != nil
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
        problems startingProblems: [PlanProblem],
        forSection sectionNumber: Int,
        in course: Course
    ) throws -> ClassInsertionPlan {
        let naming: ClassPageNaming = course.configuration.classPageNaming
        var problems: [PlanProblem] = startingProblems

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
            let from: String = latestKept?.text ?? "the start of the course"
            let has: Int = runway.count
            problems.append(PlanProblem { noun in
                AssistWording.timetableTooShortAfter(count: count, from: from, has: has, noun: noun)
            })
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
            problems.append(PlanProblem { noun in AssistWording.noDaysAfterTheLastPage(noun: noun) })
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

    /// Anything the teacher should know before saying yes, in both nouns
    /// (#1027): the card reads the course's, the model the class form.
    let plannedProblems: [PlanProblem]

    // MARK: - Computed properties

    /// The problems as the model reads them: always "class".
    var problems: [String] {
        return PlanProblem.sentences(plannedProblems, noun: .class)
    }

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
            for problem in PlanProblem.sentences(plannedProblems, noun: noun) {
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

        for problem in PlanProblem.sentences(plannedProblems, noun: noun) {
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
        problems: [PlanProblem]
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
        self.plannedProblems = problems
    }

    /// How many renames or moves a plan spells out before summarising.
    static let mostShown: Int = 10
}

/// One thing a plan's teacher should know, said in both nouns (#1027): the
/// card shows the course's own ("meeting" in a club), and the model reads the
/// class form, as it reads every detail (#267). Both come from one wording
/// function, called once for each noun, so the sentence is typed once.
/// A planner's refusal said in a course's own noun (#1027 round 4): the
/// teacher's copy of a refusal whose model copy is `localizedDescription`.
nonisolated protocol SaidInACoursesNoun {
    func sentence(noun: ClassNoun) -> String
}

struct PlanProblem: Equatable, Sendable {

    // MARK: - Stored properties

    let forAClass: String

    let forAMeeting: String

    // MARK: - Initializer

    init(_ sentence: (ClassNoun) -> String) {
        self.forAClass = sentence(.class)
        self.forAMeeting = sentence(.meeting)
    }

    // MARK: - Functions

    func sentence(noun: ClassNoun) -> String {
        return noun == .meeting ? forAMeeting : forAClass
    }

    static func sentences(_ problems: [PlanProblem], noun: ClassNoun) -> [String] {
        var sentences: [String] = []
        for problem in problems {
            sentences.append(problem.sentence(noun: noun))
        }
        return sentences
    }
}

/// Where a later class that is a symbolic link leads, among the class pages
/// of its own section (#899 U4b3 relink-5): the first class page its hops
/// reach decides.
enum LinkedClassReach: Equatable {
    /// Not a link, or a link that reaches no class page of the section at
    /// any hop: it leads to a file elsewhere, or nowhere.
    case elsewhere
    /// It reaches a class page of the section the plan leaves.
    case aClassPageTheyLeave
    /// Its own text names a class page the plan renames, to `newName`.
    case aRenamedPageByItsOwnText(newName: String)
    /// It reaches a class page the plan renames (to `newPlace`) only
    /// through `link`, a link that is not a class page and whose own text
    /// names that page.
    case aRenamedPageThrough(link: URL, newPlace: URL)
}

/// One class page of a section as it stands, by its own place's identity,
/// with its new place when the plan renames it (#899 U4b3 relink-5).
struct ClassPagePlace {

    // MARK: - Stored properties

    let identity: ResolvedFile

    let newPlace: URL?
}

/// One directory entry, as the exchange that re-points a link sees it: the
/// folder that holds it (by its identity, reached through any linked
/// folder) and its name as that folder holds it (review 2 of mac-2, LOW 1).
/// Two spellings of one entry (letter case, a linked folder) are one entry;
/// two names of one hard-linked link are two.
struct HopEntry: Equatable {

    // MARK: - Stored properties

    let folder: ResolvedFile

    let name: String

    // MARK: - Functions

    /// The entry at `url` (the entry itself never followed), or nil when
    /// nothing is there or its folder cannot be listed.
    static func of(_ url: URL) -> HopEntry? {
        guard let itself = ResolvedFile.ofThePlace(at: url) else {
            return nil
        }
        let folderURL: URL = url.deletingLastPathComponent()
        guard let folder = ResolvedFile.throughLinks(at: folderURL),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else {
            return nil
        }
        let asReached: String = url.lastPathComponent
        // The name byte for byte, when the folder holds it so.
        for name in names where name == asReached {
            return HopEntry(folder: folder, name: name)
        }
        // Otherwise the entry of this item the name was another spelling
        // of (letter case, Unicode form), as the volume matched it.
        let folded: String = HopEntry.folded(asReached)
        for name in names where HopEntry.folded(name) == folded {
            if ResolvedFile.ofThePlace(at: folderURL.appendingPathComponent(name)) == itself {
                return HopEntry(folder: folder, name: name)
            }
        }
        return nil
    }

    /// A name with letter case and Unicode form set aside.
    private static func folded(_ name: String) -> String {
        return name.precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// A file by its device and inode: one file under every name and every
/// link that leads to it (#899 U4b3).
struct ResolvedFile: Equatable {

    // MARK: - Stored properties

    let device: Int64

    let inode: UInt64

    // MARK: - Functions

    /// Whether `url` is itself a symbolic link (`lstat`, never followed).
    static func isALink(_ url: URL) -> Bool {
        guard let status = ResolvedFile.status(of: url, followingLinks: false) else {
            return false
        }
        return (status.st_mode & S_IFMT) == S_IFLNK
    }

    /// Whatever is at `url` itself, a link or a file or a folder, by its
    /// own `lstat` identity (never followed), or nil when nothing is there.
    static func ofThePlace(at url: URL) -> ResolvedFile? {
        guard let status = ResolvedFile.status(of: url, followingLinks: false) else {
            return nil
        }
        return ResolvedFile(device: Int64(status.st_dev), inode: UInt64(status.st_ino))
    }

    /// What `url` leads to through every link (`stat`), or nil when that
    /// is not there.
    static func throughLinks(at url: URL) -> ResolvedFile? {
        guard let status = ResolvedFile.status(of: url, followingLinks: true) else {
            return nil
        }
        return ResolvedFile(device: Int64(status.st_dev), inode: UInt64(status.st_ino))
    }

    private static func status(of url: URL, followingLinks: Bool) -> stat? {
        var status: stat = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            if followingLinks {
                return stat(path, &status)
            }
            return lstat(path, &status)
        }
        if result != 0 {
            return nil
        }
        return status
    }
}
