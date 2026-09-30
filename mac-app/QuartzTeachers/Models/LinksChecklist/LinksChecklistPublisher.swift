import Foundation

/// Publishes the pages a teacher ticked in the links checklist (#379).
///
/// **One plan for the whole press** (the director's ruling F2): the ticked
/// pages go through `AssistPublishPlanner.planPublishing(exactly:dateMoves:)`
/// with the dates the offer gave, each ticked class through the assistant's
/// own `planPublishing(titles:)` so it brings its pages the way publishing it
/// by name would (`followingLinks.publishing`, `bothRoutesAgree`), and the
/// two are merged BEFORE anything is written — one write per page. Where a
/// page is both a row and brought by a ticked class, the class's date wins:
/// it comes with that class. `apply` runs with `repointsTheFrontPage: false`
/// (ruling F1): a class published because a link leads to it does not become
/// the front page's class.
///
/// **A class is published by TITLE** (`graph.page(titled:)`, which keys on
/// the file name), so two class pages sharing a name in two folders would
/// resolve to the first. None of the 39 payloads has one; recorded, not fixed
/// (implementation review, N9).
///
/// **Every row is checked again first.** The offer was worked out by a build
/// that may be minutes or a night old. A page that is now visible, or gone, is
/// dropped; if nothing is left, nothing is written.
///
/// **Only rows that GO are written** (#385, `linksChecklist.followingARow`):
/// a row reached only through other rows is published only when one of them
/// is, whatever its own tick — `LinksChecklistGate.going`.
@MainActor
enum LinksChecklistPublisher {

    // MARK: - Types

    /// What one press did — the counts the trail line carries.
    struct Outcome: Equatable {

        // MARK: - Stored properties

        var publishedPlaces: [String] = []
        var datedFromAClass: Int = 0
        var datedAsTheFirstClass: Int = 0
        var keptTheirDate: Int = 0
        var classesPublished: Int = 0
        var broughtByClasses: Int = 0
        var leftUnticked: Int = 0
        /// The places left unticked AND not written by this press — a row a
        /// ticked class brings is published, so it is not left hidden
        /// (implementation review, S1).
        var leftUntickedPlaces: [String] = []
        /// Rows whose own tick was on but that did not go, because nothing
        /// they come under went (#385) — left hidden, and NOT remembered as
        /// unticked, so they come back with that row next time.
        var leftWithTheirPage: Int = 0
        var leftWithTheirPagePlaces: [String] = []
        /// Titles of pages the writer declined (#186).
        var declined: [String] = []
        /// Rows dropped because they changed since the sheet showed them,
        /// each NAMED the way a sentence names a page (`LinksChecklistNaming`,
        /// quotes included) — `wording.pageChangedSince`.
        var changedSince: [String] = []
    }

    enum Result: Equatable {
        case published(Outcome)
        case refused(String)
    }

    // MARK: - Functions

    /// A page's place in the course folder without `.md` — the name the offer
    /// uses. Compared composed, because a file name is bytes and the build may
    /// have read it in the other Unicode form (measured 2026-09-20).
    static func place(of url: URL, in course: Course) -> String {
        let full: String = url.standardizedFileURL.resolvingSymlinksInPath().path
        let root: String = course.directoryURL.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        var relative: String = full
        if full.hasPrefix(root) {
            relative = String(full.dropFirst(root.count))
        }
        if relative.lowercased().hasSuffix(".md") {
            relative = String(relative.dropLast(3))
        }
        return relative.precomposedStringWithCanonicalMapping
    }

    /// The section's pages by their place.
    static func pagesByPlace(_ graph: AssistSectionGraph, in course: Course) -> [String: AssistSectionPage] {
        var found: [String: AssistSectionPage] = [:]
        for page in graph.pages {
            found[place(of: page.fileURL, in: course)] = page
        }
        return found
    }

    /// The rows still worth offering when the sheet OPENS: the page is there
    /// and is not certainly visible already.
    ///
    /// And, since #385 (`followingARow.reRead`), what each row comes under is
    /// brought up to date: a row under a page made visible since is FREED (a
    /// page students can see now links it); a page gone since stops being a
    /// parent; and a row left with nothing it could go with is DROPPED, since
    /// it could only be published with nothing linking it — repeated until
    /// nothing more drops. Freeing happens here only, never at Publish
    /// (plan-review finding 2): a row the sheet showed locked stays unpublished.
    static func rowsStillOffered(
        _ offer: LinksChecklistOffer, pages: [String: AssistSectionPage]
    ) -> [LinksChecklistOffer.Row] {
        var present: [LinksChecklistOffer.Row] = []
        var madeVisible: Set<String> = []
        for row in offer.rows {
            guard let page = pages[row.place.precomposedStringWithCanonicalMapping] else {
                continue
            }
            if page.isVisibleToStudents && page.visibilityIsCertain {
                madeVisible.insert(row.place)
                continue
            }
            present.append(row)
        }
        var kept: [LinksChecklistOffer.Row] = []
        for row in present {
            var isFreed: Bool = false
            for parent in row.dependsOn where madeVisible.contains(parent) {
                isFreed = true
            }
            if isFreed {
                kept.append(row.withDependsOn([]))
            } else {
                kept.append(row)
            }
        }
        var somethingChanged: Bool = true
        while somethingChanged {
            somethingChanged = false
            var keptPlaces: Set<String> = []
            for row in kept {
                keptPlaces.insert(row.place)
            }
            var next: [LinksChecklistOffer.Row] = []
            for row in kept {
                if row.dependsOn.isEmpty {
                    next.append(row)
                    continue
                }
                var remaining: [String] = []
                for parent in row.dependsOn where keptPlaces.contains(parent) && parent != row.place {
                    remaining.append(parent)
                }
                if remaining.isEmpty {
                    somethingChanged = true
                    continue
                }
                if remaining.count != row.dependsOn.count {
                    somethingChanged = true
                }
                next.append(row.withDependsOn(remaining))
            }
            kept = next
        }
        return kept
    }

    /// The one merged plan for a press, and the counts it will report.
    static func plan(
        offer: LinksChecklistOffer,
        ticked: Set<String>,
        graph: AssistSectionGraph,
        classPages: [ClassPageSummary],
        forSection sectionNumber: Int,
        in course: Course
    ) -> (plan: AssistPublishPlan, outcome: Outcome) {
        let pages: [String: AssistSectionPage] = pagesByPlace(graph, in: course)
        let naming: LinksChecklistNaming = LinksChecklistNaming(
            graph: graph, pagesByPlace: pages, rows: offer.rows,
            courseDirectoryURL: course.directoryURL, courseCode: course.code
        )
        var outcome: Outcome = Outcome()

        // What goes (#385): worked out from the rows AS THE SHEET SHOWED THEM,
        // less any page that has gone since — so a row under a gone page goes
        // only through another. A page made visible since stays in the
        // reckoning (it goes as it went), but nothing is FREED here: a row the
        // sheet showed locked is never written (plan-review finding 2).
        let goingAsShown: Set<String> = LinksChecklistGate.going(offer.rows, ticked: ticked)
        var rowsStillThere: [LinksChecklistOffer.Row] = []
        for row in offer.rows where pages[row.place.precomposedStringWithCanonicalMapping] != nil {
            rowsStillThere.append(row)
        }
        let going: Set<String> = LinksChecklistGate.going(rowsStillThere, ticked: ticked)

        var rowPages: [AssistSectionPage] = []
        var untickedPages: [(place: String, path: String)] = []
        var followingPages: [(place: String, path: String)] = []
        var rowMoves: [String: AssistPublishDateMove] = [:]
        var classTitles: [String] = []
        for row in offer.rows {
            let key: String = row.place.precomposedStringWithCanonicalMapping
            guard let page = pages[key] else {
                if goingAsShown.contains(row.place) {
                    outcome.changedSince.append(naming.name(ofPlace: row.place))
                }
                continue
            }
            if page.isVisibleToStudents && page.visibilityIsCertain {
                if goingAsShown.contains(row.place) {
                    outcome.changedSince.append(naming.name(ofPlace: row.place))
                }
                continue
            }
            if !ticked.contains(row.place) {
                // Counted only after the merge below: a ticked class may
                // bring this page with it.
                untickedPages.append((place: row.place, path: page.fileURL.path))
                continue
            }
            if !going.contains(row.place) {
                // Its own tick is on, but nothing it comes under goes.
                followingPages.append((place: row.place, path: page.fileURL.path))
                if goingAsShown.contains(row.place) {
                    outcome.changedSince.append(naming.name(ofPlace: row.place))
                }
                continue
            }
            if row.group == .aClass {
                classTitles.append(page.title)
                continue
            }
            rowPages.append(page)
            switch row.why {
            case .dated:
                outcome.datedFromAClass += 1
            case .datedAsTheFirstClass:
                outcome.datedAsTheFirstClass += 1
            case .keepsItsDate:
                outcome.keptTheirDate += 1
            case .datedByTheBuild, .structuralNeverDated, .classNeverDated, .noClassToDateFrom:
                break
            }
            if let day = row.date, page.date != day {
                let takenFrom: String = LinksChecklistOffer.name(
                    ofPlace: row.claimedBy ?? offer.firstClassPlace ?? ""
                )
                rowMoves[page.fileURL.path] = AssistPublishDateMove(
                    page: page, from: page.date, to: day, takenFrom: takenFrom
                )
            }
        }

        // Each ticked class, the way publishing it by name would.
        var classChanges: [AssistPublishChange] = []
        var classMoves: [AssistPublishDateMove] = []
        var classNoRoom: [AssistSectionPage] = []
        if !classTitles.isEmpty {
            let classPlan: AssistPublishPlan = AssistPublishPlanner.planPublishing(
                titles: classTitles, onOrAfter: nil, before: nil, graph: graph,
                classPages: classPages, forSection: sectionNumber, in: course
            )
            classChanges = classPlan.changes
            classMoves = classPlan.dateMoves
            classNoRoom = classPlan.noRoomForAKey
            for change in classPlan.changes {
                if change.becauseLinked {
                    outcome.broughtByClasses += 1
                } else {
                    outcome.classesPublished += 1
                }
            }
        }

        // The rows' own plan, then the classes' merged into it: one change
        // per page, and a class's date over a row's (ruling F2).
        let rowPlan: AssistPublishPlan = AssistPublishPlanner.planPublishing(
            exactly: rowPages, dateMoves: [], forSection: sectionNumber, in: course
        )
        var changes: [AssistPublishChange] = []
        var changedPaths: Set<String> = []
        for change in rowPlan.changes {
            changes.append(change)
            changedPaths.insert(change.page.fileURL.path)
        }
        for change in classChanges where !changedPaths.contains(change.page.fileURL.path) {
            changes.append(change)
            changedPaths.insert(change.page.fileURL.path)
        }
        var movesByPath: [String: AssistPublishDateMove] = rowMoves
        for move in classMoves {
            movesByPath[move.page.fileURL.path] = move
        }
        var moves: [AssistPublishDateMove] = []
        for path in movesByPath.keys.sorted() {
            if let move = movesByPath[path] {
                moves.append(move)
            }
        }
        var noRoom: [AssistSectionPage] = rowPlan.noRoomForAKey
        for page in classNoRoom {
            noRoom.append(page)
        }

        for change in changes {
            outcome.publishedPlaces.append(place(of: change.page.fileURL, in: course))
        }
        for unticked in untickedPages where !changedPaths.contains(unticked.path) {
            outcome.leftUntickedPlaces.append(unticked.place)
        }
        outcome.leftUnticked = outcome.leftUntickedPlaces.count
        for following in followingPages where !changedPaths.contains(following.path) {
            outcome.leftWithTheirPagePlaces.append(following.place)
        }
        outcome.leftWithTheirPage = outcome.leftWithTheirPagePlaces.count
        outcome.publishedPlaces.sort()
        for page in noRoom {
            outcome.declined.append(page.displayTitle)
        }

        let merged: AssistPublishPlan = AssistPublishPlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            publishes: true,
            unknownNames: [],
            namedPages: rowPages,
            changes: changes,
            alreadyRight: rowPlan.alreadyRight,
            noRoomForAKey: noRoom,
            kept: [],
            linkedClassesLeftAlone: [],
            dateMoves: moves
        )
        return (plan: merged, outcome: outcome)
    }

    /// Press Publish: check, plan, write, and say so on the trail.
    static func publish(
        offer: LinksChecklistOffer,
        ticked: Set<String>,
        course: Course,
        sectionNumber: Int,
        workspaceURL: URL
    ) -> Result {
        if CourseActivity.coursePublishIsRunning(folderPath: workspaceURL.path, courseCode: course.code) {
            return .refused(LinksChecklistWording.deployUnderWay(course: course.displayCode))
        }
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: sectionNumber, in: course, workspaceURL: workspaceURL
        )
        let planned: (plan: AssistPublishPlan, outcome: Outcome) = plan(
            offer: offer, ticked: ticked, graph: graph,
            classPages: ClassPages.list(forSection: sectionNumber, in: course),
            forSection: sectionNumber, in: course
        )
        var outcome: Outcome = planned.outcome
        if planned.plan.changes.isEmpty && planned.plan.dateMoves.isEmpty && outcome.declined.isEmpty {
            rememberTheAnswer(offer: offer, leftUnticked: Set(outcome.leftUntickedPlaces),
                              course: course, sectionNumber: sectionNumber)
            if outcome.leftUnticked + outcome.leftWithTheirPage > 0 {
                noteSetAside(course: course, sectionNumber: sectionNumber, notNow: false,
                             count: outcome.leftUnticked + outcome.leftWithTheirPage,
                             withTheirPage: outcome.leftWithTheirPage)
            }
            return .refused(LinksChecklistWording.nothingLeftToPublish)
        }
        do {
            let applied: (change: AssistChange, leftAlone: [String]) = try AssistPublishPlanner.apply(
                planned.plan, forSection: sectionNumber, in: course, repointsTheFrontPage: false
            )
            for title in applied.leftAlone where !outcome.declined.contains(title) {
                outcome.declined.append(title)
            }
        } catch {
            return .refused(AssistToolRefusal.unreadablePage(offer.course).message)
        }
        rememberTheAnswer(offer: offer, leftUnticked: Set(outcome.leftUntickedPlaces),
                          course: course, sectionNumber: sectionNumber)
        ActivityTrail.note(
            .pagesPublishedFromLinksChecklist, publishedLine(outcome),
            course: course.code, section: sectionNumber
        )
        if outcome.leftUnticked + outcome.leftWithTheirPage > 0 {
            noteSetAside(course: course, sectionNumber: sectionNumber, notNow: false,
                         count: outcome.leftUnticked + outcome.leftWithTheirPage,
                         withTheirPage: outcome.leftWithTheirPage)
        }
        if !outcome.declined.isEmpty {
            ActivityTrail.note(
                .pageSettingsLeftAsTheyWere,
                ActivityTrail.pageSettingsLeftAsTheyWereLine(
                    act: "publishing pages that links lead to", pages: outcome.declined.count
                ),
                course: course.code, section: sectionNumber
            )
        }
        return .published(outcome)
    }

    /// Press Not Now.
    static func setAside(offer: LinksChecklistOffer, ticked: Set<String>, course: Course, sectionNumber: Int) {
        var unticked: Set<String> = []
        for row in offer.rows where !ticked.contains(row.place) {
            unticked.insert(row.place)
        }
        rememberTheAnswer(offer: offer, leftUnticked: unticked, course: course, sectionNumber: sectionNumber)
        noteSetAside(course: course, sectionNumber: sectionNumber, notNow: true, count: offer.rows.count,
                     withTheirPage: 0)
    }

    /// Records the answer. `leftUnticked` is what the teacher left unticked:
    /// for Not Now every row whose own tick is off, for Publish only those no
    /// ticked class brought — never a row left only because the row it comes
    /// under was left (#385).
    static func rememberTheAnswer(offer: LinksChecklistOffer, leftUnticked unticked: Set<String>,
                                  course: Course, sectionNumber: Int) {
        let answered: LinksChecklistAnswered = LinksChecklistAnswered(offered: offer.places, leftUnticked: unticked)
        try? answered.write(courseDirectory: course.directoryURL, section: sectionNumber)
    }

    static func noteSetAside(course: Course, sectionNumber: Int, notNow: Bool, count: Int, withTheirPage: Int) {
        ActivityTrail.note(
            .linksChecklistSetAside,
            setAsideLine(notNow: notNow, count: count, withTheirPage: withTheirPage),
            course: course.code, section: sectionNumber
        )
    }

    /// `count` is EVERY page left hidden, of both kinds; `withTheirPage` how
    /// many of those were left only because the page they come under was
    /// (#385; 0 for Not Now, where the press itself leaves every row).
    static func setAsideLine(notNow: Bool, count: Int, withTheirPage: Int) -> String {
        let how: String = notNow ? "Not Now" : "some unticked"
        let pages: String = count == 1 ? "1 page" : "\(count) pages"
        return "left pages hidden that links lead to — \(how), \(pages) left hidden "
             + "(\(withTheirPage) with the page they come under)"
    }

    /// The trail line for a press that published: counts, then the places,
    /// at most ten — names, never anything written on a page.
    static func publishedLine(_ outcome: Outcome) -> String {
        let count: Int = outcome.publishedPlaces.count
        let pages: String = count == 1 ? "1 page" : "\(count) pages"
        let classes: String = outcome.classesPublished == 1 ? "1 class" : "\(outcome.classesPublished) classes"
        var shown: [String] = []
        for place in outcome.publishedPlaces where shown.count < 10 {
            shown.append(place)
        }
        var names: String = shown.joined(separator: ", ")
        if count > shown.count {
            names += " and \(count - shown.count) more"
        }
        return "published pages that links led to — \(pages) (\(outcome.datedFromAClass) dated from a class, "
             + "\(outcome.datedAsTheFirstClass) dated as the first class, \(outcome.keptTheirDate) kept their date), "
             + "\(classes) bringing \(outcome.broughtByClasses) more, \(outcome.leftUnticked) left unticked, "
             + "\(outcome.leftWithTheirPage) left with the page they come under: \(names)"
    }

    /// The trail line for putting the checklist in front of the teacher, from
    /// the sheet as it opens: `ticked` counts the rows that GO — what Publish
    /// would write as offered — not the rows whose own tick is on (#385).
    static func offeredLine(model: LinksChecklistSheetModel) -> String {
        var listedUnder: Int = 0
        for shown in LinksChecklistGate.shownOrder(model.rows) where shown.depth > 0 {
            listedUnder += 1
        }
        return offeredLine(model.rows, going: model.going.count, listedUnder: listedUnder, occasion: model.occasion)
    }

    static func offeredLine(
        _ rows: [LinksChecklistOffer.Row], going: Int, listedUnder: Int, occasion: LinksChecklistGate.Occasion
    ) -> String {
        var fromAClass: Int = 0
        var other: Int = 0
        var classes: Int = 0
        for row in rows {
            switch row.group {
            case .fromAClass:
                fromAClass += 1
            case .notReachedByAClass:
                other += 1
            case .aClass:
                classes += 1
            }
        }
        return "offered to publish pages that links lead to \(occasion.rawValue) — \(fromAClass) used by a class, "
             + "\(other) linked from other pages, \(classes) classes; \(listedUnder) listed under another page; "
             + "\(going) ticked"
    }
}
