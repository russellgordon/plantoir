import Foundation

/// One page whose date would move, and why.
struct ReDatedPage: Equatable {

    // MARK: - Types

    /// Why this page is moving. Shown to the teacher, because a list of
    /// dates with no reasons is a list nobody can check.
    enum Reason: Equatable {

        /// A class, taking the date in its own position in the timetable.
        case aClass

        /// Material a class brings with it, taking that class's day.
        case broughtBy(String)

        /// A page the section uses all year, taking the first day of class.
        case yearRound
    }

    // MARK: - Stored properties

    let title: String
    let fileURL: URL
    let isSectionLocal: Bool
    let from: CalendarDay?
    let to: CalendarDay
    let reason: Reason

    /// Whether this page is being unpublished (e.g. overflow classes with no
    /// schedule date of their own that are set to draft).
    let unpublishes: Bool
}

/// Re-dating a whole section onto a new list of class dates.
///
/// **What a teacher is doing when they ask for this.** They have copied last
/// year's course, they have this year's timetable, and every page in the
/// section is dated to days that have been and gone. Doing it by hand means
/// opening two hundred files.
///
/// **Position, and only position.** The first class takes the first recorded
/// date, the second takes the second, and so on. Not the unit and day numbers
/// — a course where a unit ran long, or that has a page called "Field Trip"
/// rather than Unit 2, Day 4, would be dated wrongly by counting numbers. And
/// not by matching old dates to new ones, which sounds cleverer and breaks the
/// moment a year has a different number of PA days. Counting is the one rule
/// that cannot be wrong about a course it has never seen.
///
/// **Three kinds of page move, and the order they are decided in matters.**
///
/// 1. **Classes** take their position's date.
/// 2. **What a class brings with it** — every page it links to, and what those
///    link to — takes that class's new day. Where several classes share a page
///    the EARLIEST claims it, which is the same first-use rule the course
///    installer follows and the same one publishing uses.
/// 3. **Pages the section uses all year** take the first day of class. That is
///    what this section's Key Links points at: the pages a teacher wants
///    reachable from the first week rather than buried under a day in March.
///
/// **Curriculum pages are deliberately NOT here.** `build_site.py` already
/// dates them, on every build, to the LATEST date in the section so they sort
/// to the top of a listing — and it does it to the copy it publishes, so
/// anything written to the source would be overwritten on the way out. Moving
/// them here would be work that does nothing, fighting a rule that already
/// exists.
///
/// Nothing here writes. `apply` does, once the teacher has seen the list.
@MainActor
enum SectionReDatePlanner {

    // MARK: - Types

    enum Problem: LocalizedError {
        case noTimetable(String, Int)
        case noClasses(String, Int)

        var errorDescription: String? {
            switch self {
            case .noTimetable(let code, let number):
                return "I don’t know when \(code) Section \(number) meets, so I can’t re-date it. "
                     + AssistWording.mayIAskForYourDates
            case .noClasses(let code, let number):
                return "\(code) Section \(number) has no numbered class pages, so there is nothing "
                     + "to re-date."
            }
        }
    }

    // There is deliberately NO "not enough dates" refusal, and this is the
    // most important comment in the file.
    //
    // It used to refuse outright when a section had more classes than the new
    // year has days: 78 classes, 75 dates, nothing written. That reads as
    // careful and is the opposite — it leaves EVERY page on last year's dates,
    // which is the state the teacher asked to be rid of, over three pages at
    // the end they had not thought about yet.
    //
    // A year is rarely the same length twice. Coming up short is the ordinary
    // case, not the error case, and what a teacher does about it is ordinary
    // too: move things around, merge two lessons, drop the ones that no longer
    // fit. That is planning, and planning is theirs.
    //
    // So the overflow classes all land on the LAST class date as drafts, where
    // they are impossible to miss — they sit together on the final day of the
    // course — and the plan says how many and what to do about them. Every
    // other page is correct meanwhile, which is the whole point of asking.

    // MARK: - Functions

    /// What re-dating this section would do. Changes nothing.
    static func plan(forSection sectionNumber: Int, in course: Course, workspaceURL: URL?) throws
        -> SectionReDatePlan {
        guard let remembered = try SectionTimetableStore.read(forSection: sectionNumber, in: course) else {
            throw Problem.noTimetable(course.code, sectionNumber)
        }

        let everyClass: [ClassPageSummary] = ClassPages.list(forSection: sectionNumber, in: course)
        let classes: [ClassPageSummary] = ClassInsertionPlanner.numberedClasses(among: everyClass)
        if classes.isEmpty {
            throw Problem.noClasses(course.code, sectionNumber)
        }
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: sectionNumber, in: course, workspaceURL: workspaceURL
        )
        let firstDay: CalendarDay = remembered.dates[0]

        var moves: [ReDatedPage] = []
        var spokenFor: Set<String> = []

        // 1. The classes themselves, by position.
        for (index, summary) in classes.enumerated() {
            spokenFor.insert(AssistSectionGraph.normalized(summary.title))
            let day: CalendarDay = SectionReDatePlanner.date(
                at: index, from: remembered.dates
            )
            guard let page = graph.page(titled: summary.title) else {
                continue
            }
            let isOverflow: Bool = index >= remembered.dates.count
            let unpublishes: Bool = isOverflow && page.isVisibleToStudents
            if page.date == day && !unpublishes {
                continue
            }
            moves.append(ReDatedPage(
                title: page.displayTitle, fileURL: page.fileURL,
                isSectionLocal: page.isSectionLocal,
                from: page.date, to: day, reason: .aClass,
                unpublishes: unpublishes
            ))
        }

        // 3. Year-round pages are settled BEFORE materials, so a page the
        //    section leans on all year is not claimed by whichever class
        //    happens to mention it first.
        let yearRound: Set<String> = AssistPublishPlanner.pagesThisSectionCannotDoWithout(graph: graph)
        for page in graph.pages {
            guard yearRound.contains(page.lowercasedTitle),
                  !spokenFor.contains(page.lowercasedTitle),
                  !page.isFolderIndex,
                  !AssistCurriculumMentions.isCurriculum(pageAt: page.fileURL, in: course) else {
                continue
            }
            spokenFor.insert(page.lowercasedTitle)
            if page.date == firstDay {
                continue
            }
            moves.append(ReDatedPage(
                title: page.displayTitle, fileURL: page.fileURL,
                isSectionLocal: page.isSectionLocal,
                from: page.date, to: firstDay, reason: .yearRound,
                unpublishes: false
            ))
        }

        // 2. What each class brings, earliest class first.
        for (index, summary) in classes.enumerated() {
            guard let classPage = graph.page(titled: summary.title) else {
                continue
            }
            let day: CalendarDay = SectionReDatePlanner.date(
                at: index, from: remembered.dates
            )
            // The reach stops at a class page (issue #173), so material
            // reachable only THROUGH another class is claimed by the class
            // that actually brings it rather than by whichever earlier class
            // could see it through that one. Class pages themselves are
            // unaffected: step 1 above dates every numbered class by position.
            for page in graph.reachFollowingLinks(from: [classPage]).pages {
                if spokenFor.contains(page.lowercasedTitle) || page.isClassPage || page.isFolderIndex {
                    continue
                }
                if AssistCurriculumMentions.isCurriculum(pageAt: page.fileURL, in: course) {
                    continue
                }
                spokenFor.insert(page.lowercasedTitle)
                if page.date == day {
                    continue
                }
                moves.append(ReDatedPage(
                    title: page.displayTitle, fileURL: page.fileURL,
                    isSectionLocal: page.isSectionLocal,
                    from: page.date, to: day, reason: .broughtBy(classPage.displayTitle),
                    unpublishes: false
                ))
            }
        }

        return SectionReDatePlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            classCount: classes.count,
            firstDay: firstDay,
            lastDay: SectionReDatePlanner.date(at: classes.count - 1, from: remembered.dates),
            spareDates: max(0, remembered.dates.count - classes.count),
            overflowing: max(0, classes.count - remembered.dates.count),
            moves: moves
        )
    }

    /// The date for the class in this position — and the LAST date for every
    /// class past the end of the list.
    ///
    /// See the note above `Problem`: running out of days is the ordinary case,
    /// not an error, and stacking the leftovers on the final day puts them
    /// where a teacher cannot miss them.
    private static func date(at index: Int, from dates: [CalendarDay]) -> CalendarDay {
        if index < dates.count {
            return dates[index]
        }
        return dates[dates.count - 1]
    }

    /// Carry it out. Returns the change record so it can be undone.
    static func apply(_ plan: SectionReDatePlan, forSection sectionNumber: Int, in course: Course)
        throws -> AssistChange {
        let tail: String = ClassPages.siblingTimeAndOffset(
            from: ClassPages.list(forSection: sectionNumber, in: course),
            forSection: sectionNumber
        )

        var saved: [AssistSavedFile] = []
        for move in plan.moves {
            let before: String = try String(contentsOf: move.fileURL, encoding: .utf8)
            var after: String = PageFrontmatter.settingCreated(
                in: before,
                key: PageFrontmatter.createdKey(
                    forSection: sectionNumber, isSectionLocal: move.isSectionLocal
                ),
                to: move.to,
                fallbackTail: tail
            ).text
            if move.unpublishes {
                after = AssistPageVisibility.setting(
                    published: false,
                    in: after,
                    forSection: sectionNumber,
                    isSectionLocal: move.isSectionLocal
                ).text
            }
            if after == before {
                continue
            }
            try after.write(to: move.fileURL, atomically: true, encoding: .utf8)
            saved.append(AssistSavedFile(fileURL: move.fileURL, before: before, after: after))
        }

        if let repointed = SectionIndexPointer.repointIndex(forSection: sectionNumber, in: course) {
            saved.append(repointed)
        }

        return AssistChange(
            whatHappened: "re-dated \(plan.classCount) "
                        + "\(plan.classCount == 1 ? "class" : "classes") and what they use",
            courseCode: course.code,
            sectionNumber: sectionNumber,
            rebuildsThePreview: true,
            files: saved
        )
    }
}

/// What re-dating a section would do, in a form a teacher can check.
struct SectionReDatePlan {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let classCount: Int
    let firstDay: CalendarDay
    let lastDay: CalendarDay
    let spareDates: Int

    /// Classes with no day of their own, all sitting on the last one.
    let overflowing: Int

    let moves: [ReDatedPage]

    // MARK: - Computed properties

    var changesNothing: Bool {
        return moves.isEmpty
    }

    // MARK: - Functions

    /// The plan in words. Same shape as every other plan here: one sentence
    /// per page, no arrows, no markdown.
    func describe(mostListed: Int = 15) -> String {
        var lines: [String] = []
        lines.append("\(courseCode) Section \(sectionNumber): re-dating onto the class dates on file.")
        lines.append("")

        if changesNothing {
            lines.append("Every page is already on the day it should be.")
            return lines.joined(separator: "\n")
        }

        lines.append("\(classCount) \(classCount == 1 ? "class runs" : "classes run") from "
                     + "\(firstDay.text) (\(firstDay.weekdayName)) to "
                     + "\(lastDay.text) (\(lastDay.weekdayName)).")
        if spareDates > 0 {
            lines.append("\(spareDates) recorded \(spareDates == 1 ? "date is" : "dates are") "
                         + "left over at the end.")
        }
        if overflowing > 0 {
            lines.append("\(overflowing) \(overflowing == 1 ? "class has" : "classes have") no day "
                         + "of \(overflowing == 1 ? "its" : "their") own this year, so "
                         + "\(overflowing == 1 ? "it goes" : "they all go") on "
                         + "\(lastDay.text) with the last one as \(overflowing == 1 ? "a draft" : "drafts"). Move, publish or delete "
                         + "\(overflowing == 1 ? "it" : "them") when you have decided what to do.")
        }
        lines.append("")

        let word: String = moves.count == 1 ? "page" : "pages"
        lines.append("\(moves.count) \(word) would move:")
        var listed: Int = 0
        for move in moves {
            if listed == mostListed {
                lines.append("…and \(moves.count - listed) more.")
                break
            }
            switch move.reason {
            case .aClass:
                if move.unpublishes {
                    lines.append("“\(move.title)” moves to \(move.to.text) and becomes a draft because it has no class date.")
                } else {
                    lines.append("“\(move.title)” moves to \(move.to.text).")
                }
            case .broughtBy(let classTitle):
                lines.append("“\(move.title)” moves to \(move.to.text), with “\(classTitle)”.")
            case .yearRound:
                lines.append("“\(move.title)” moves to \(move.to.text), the first day of class, "
                             + "because Key Links points at it.")
            }
            listed += 1
        }

        lines.append("")
        lines.append("Curriculum pages are left alone — Plantoir dates those itself every time it "
                     + "builds the site.")
        return lines.joined(separator: "\n")
    }
}
