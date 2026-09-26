import Foundation

/// One page whose visibility would move.
struct AssistPublishChange {

    // MARK: - Stored properties

    let page: AssistSectionPage

    /// The frontmatter key that will decide it once the change is made —
    /// always the current spelling, since a page still written the old way is
    /// migrated as it is edited.
    let key: String

    let wasVisible: Bool
    let willBeVisible: Bool

    /// True when this page was reached by following a link rather than named.
    let becauseLinked: Bool
}

/// One page an unpublish reached by following a link and deliberately left
/// alone, and the reason it was left.
///
/// Said out loud in the plan, because "which pages did it NOT take down" is
/// exactly what a teacher wants to know: a concept page another class still
/// links to has to stay, or that other class is left pointing at nothing.
struct AssistPublishKept {

    /// Why a linked page stays: decided when the plan is made, and put into
    /// words only when the plan is DESCRIBED.
    ///
    /// A reason rather than a finished string because one of them names the
    /// course's noun (#201), and the noun belongs to the reader, not to the
    /// plan: the model is always given "class", while a club's card says
    /// "meeting" (#267, `AssistPublishPlan.describe(mostListed:noun:)`). A
    /// clause baked at plan time would put "meeting" in the model's text.
    ///
    /// The four clauses that were strings before #201 are byte-identical to
    /// what they were — the Windows suite pins the referrer line.
    enum Reason: Equatable {
        case folderLandingPage
        case keyLinks
        case curriculum
        case aClassOfItsOwn
        case stillLinkedFrom(String)

        // MARK: - Functions

        /// The clause that finishes "“Ohm's Law” stays visible, because …",
        /// ending with its own full stop.
        func finishing(noun: ClassNoun) -> String {
            switch self {
            case .folderLandingPage:
                return "it is a folder's landing page, which following links never takes down."
            case .keyLinks:
                return "it is in this section's Key Links."
            case .curriculum:
                return "it is a curriculum page."
            case .aClassOfItsOwn:
                return AssistWording.aLinkedClassStaysBecause(noun: noun)
            case .stillLinkedFrom(let referrer):
                return "“\(referrer)” still links to it."
            }
        }
    }

    // MARK: - Stored properties

    let page: AssistSectionPage

    /// Why it stays; `Reason.finishing(noun:)` puts it into words.
    let reason: Reason
}

/// One page whose date would move onto the class's day.
struct AssistPublishDateMove {

    // MARK: - Stored properties

    let page: AssistSectionPage
    let from: CalendarDay?
    let to: CalendarDay

    /// The class whose date this page is taking, as the teacher sees it named.
    ///
    /// Carried so the plan can say it in ONE sentence — "“Bananas” will become
    /// visible, with the same date as “Unit 4, Day 24”" — rather than making a
    /// teacher hold a page name in their head across two lists and a blank
    /// line to work out that the second is about the first.
    let takenFrom: String
}

/// What publishing (or unpublishing) would do, before anything is done.
///
/// The plan is the object BOTH halves work from: `plan_publish_pages` describes
/// it and stops, `publish_pages` describes it and applies it. One description
/// of the change, in one place — two would drift, and the day they drift is the
/// day a teacher agrees to one thing and gets another.
struct AssistPublishPlan {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int

    /// The verb. Not a setting the caller may flip afterwards: it is decided
    /// by WHICH TOOL RAN, and it travels with the plan so that nothing between
    /// the plan and the write can invert it.
    let publishes: Bool

    /// The pages the model named that matched nothing.
    let unknownNames: [String]

    /// The pages the teacher NAMED that were found — as distinct from
    /// everything publishing then swept in by following links.
    ///
    /// Kept so an answer can be about what they asked for. "Publish Unit 4,
    /// Day 23" on a class that is already published should say "It's already
    /// been published", and "it" is the class — not the five linked pages that
    /// were also already published and that nobody mentioned.
    let namedPages: [AssistSectionPage]

    let changes: [AssistPublishChange]

    /// Pages already the way they were asked to be.
    let alreadyRight: [AssistSectionPage]

    /// Pages the writer would DECLINE: their settings have no column-0 level
    /// for a new key to join, so nothing can be written to them safely.
    ///
    /// Asked at plan time by running the real writer over the page's own text
    /// — not by a second copy of its rule — so the card cannot promise
    /// something the writing step then quietly skips.
    /// [Issue #186](https://github.com/russellgordon/plantoir/issues/186).
    let noRoomForAKey: [AssistSectionPage]

    /// Pages an unpublish reached by following a link and left published, each
    /// with the reason. Always empty when publishing: publishing takes every
    /// page it reaches, and the one thing it does not reach is said in
    /// `linkedClassesLeftAlone` instead.
    ///
    /// Since #201 this includes a linked CLASS students can see, with the
    /// reason "it is a class of its own": an unpublish stops at a class the
    /// way publishing does, and says so here.
    let kept: [AssistPublishKept]

    /// The other classes this publish followed a link onto and left alone —
    /// only the ones students cannot already see.
    ///
    /// Always empty when unpublishing. An unpublish stops at a class too
    /// (#201, 2026-09-26), but a class it stopped at is said in `kept`, with
    /// its own reason, because the sentence this list is said with — "publish
    /// it when you get to that class" — would be false about it.
    ///
    /// A teacher is told about these because the alternative is a plan quietly
    /// smaller than the one they pictured: a link on the page they just
    /// published leads somewhere students cannot follow, and nothing else in
    /// the app would ever tell them so. A class already published needs no
    /// sentence — it is not a surprise, and "publish it when you get to that
    /// class" would be false about it — so `AssistPublishPlanner` leaves those
    /// out.
    let linkedClassesLeftAlone: [AssistSectionPage]

    let dateMoves: [AssistPublishDateMove]

    // MARK: - Computed properties

    var changesNothing: Bool {
        return changes.isEmpty && dateMoves.isEmpty
    }

    /// The whole answer, when the whole answer is that there was nothing to
    /// do — or nil when something else needs saying.
    ///
    /// A teacher who asks to publish a class that is already published wants
    /// four words back, not a plan with a heading and a count and a note that
    /// nothing was changed because nothing needed to be. The full description
    /// is still right for every other shape of "nothing changed": a name that
    /// matched no page has to say so, and a request that found nothing at all
    /// is not the same as one that found everything already done.
    var nothingToDoSentence: String? {
        guard changesNothing, unknownNames.isEmpty, !namedPages.isEmpty else {
            return nil
        }
        // A page the writer would decline is not a page that is "already
        // hidden". Without this, asking to hide such a page answered "It's
        // already hidden." about a page students can read.
        guard noRoomForAKey.isEmpty else {
            return nil
        }
        // Every page they named is already the way they asked for it — and
        // this app is SURE of that for every one of them. A page whose flag
        // cannot be read is not "already done"; it is a page to write.
        for page in namedPages where page.isVisibleToStudents != publishes || !page.visibilityIsCertain {
            return nil
        }
        let done: String = publishes ? "published" : "hidden"
        if namedPages.count == 1 {
            return publishes ? "It's already been published." : "It's already hidden."
        }
        return "They have already been \(done)."
    }

    var verb: String {
        return publishes ? "publish" : "unpublish"
    }

    // MARK: - Functions

    /// One line of the "N linked pages stay visible:" list — the single place
    /// that frame is written, so `AssistContract` renders the contract's
    /// `linkedClassStaysVisible` through the same code the plan uses. The
    /// reasons are written to finish this sentence, and each ends with its
    /// own full stop.
    static func stayingVisibleLine(title: String,
                                   reason: AssistPublishKept.Reason,
                                   noun: ClassNoun) -> String {
        return "“\(title)” stays visible, because \(reason.finishing(noun: noun))"
    }

    /// The plan in words, meant to be read aloud to a teacher.
    ///
    /// PLAIN TEXT. No markdown, and no bold. The headings used to be wrapped
    /// in asterisks so the counts stood out from the list underneath — a plan
    /// is scanned for "how much is about to change" before it is read, and that
    /// much is still true. But this is a chat, and a person answering a
    /// question does not reach for typography to make a sentence land. The
    /// heading already ends in a colon and the count is its first word, which
    /// is signal enough without the assistant sounding like a report
    /// generator. (The bubble still PARSES markdown, so a model's own reply
    /// renders normally — nothing written here emits any.)
    ///
    /// The list items are NOT indented: a chat bubble is narrow, every line of
    /// any length wraps, and the wrapped half returns to the left margin — so
    /// the indent marks only the first line of each item and makes the rest
    /// harder to follow rather than easier.
    ///
    /// Each item is ONE SENTENCE about one page. What is deliberately gone:
    /// the frontmatter key a change lands in, an arrow between two states, and
    /// a parenthetical saying a page was reached by a link. All were true and
    /// none of them is how a person says it — `publishForSection1` especially,
    /// which is the name of a line in a file, shown to somebody who asked to
    /// hide a lesson.
    ///
    /// `noun` is what the course calls one of its class pages (#267). The
    /// model is always given the `.class` form; a club's CARD says
    /// "meeting" — see `AssistToolOutcome.planned(_:plan:card:)`.
    func describe(mostListed: Int = 15, noun: ClassNoun = .class) -> String {
        var lines: [String] = []
        lines.append("\(courseCode) Section \(sectionNumber): \(verb)ing.")
        lines.append("")

        if changes.isEmpty {
            lines.append("No page's visibility would change.")
        } else {
            let word: String = changes.count == 1 ? "page" : "pages"
            lines.append("\(changes.count) \(word) would change:")
            var listed: Int = 0
            for change in changes {
                if listed == mostListed {
                    lines.append("…and \(changes.count - listed) more.")
                    break
                }
                // One short sentence per page, and nothing else on the line.
                //
                // It used to read `Bananas  —  publishForSection1: visible →
                // hidden  (linked from a page you named)`, which is four
                // pieces of bookkeeping wearing a page title: the frontmatter
                // KEY the change lands in, the state it came from, an arrow,
                // and a parenthetical. All four are true and none of them is
                // how a person says it. `publishForSection1` in particular is
                // the name of a line in a file — the teacher is being shown
                // the implementation of the thing they asked for.
                let becoming: String = change.willBeVisible ? "visible" : "hidden"
                var line: String = "“\(change.page.displayTitle)” will become \(becoming)"
                // The date, said here rather than in a list of its own.
                for move in dateMoves
                where move.page.lowercasedTitle == change.page.lowercasedTitle {
                    line += ", with the same date as “\(move.takenFrom)”"
                }
                lines.append(line + ".")
                listed += 1
            }
        }

        if !alreadyRight.isEmpty {
            let word: String = alreadyRight.count == 1 ? "page is" : "pages are"
            lines.append("\(alreadyRight.count) \(word) already \(publishes ? "visible" : "hidden").")
        }

        // The pages that will be left alone. Said on the card, BEFORE the
        // teacher presses Go, because a refusal they only hear about
        // afterwards is one they have already been told did not happen.
        if !noRoomForAKey.isEmpty {
            lines.append(AssistPublishPlan.sayingPagesWithNoRoomForAKey(noRoomForAKey))
        }

        // The classes a link landed on, which this publish left where they
        // are. Said once, here, so it appears on the plan card AND in the
        // reply afterwards — `describe()` is the text used for both.
        if !linkedClassesLeftAlone.isEmpty {
            lines.append("")
            var names: [String] = []
            for page in linkedClassesLeftAlone {
                names.append(page.displayTitle)
            }
            lines.append(AssistWording.linkedClassesWereLeftAlone(
                AssistPublishPlan.listing(names), count: names.count, noun: noun
            ))
        }

        // The pages that STAY. Every one of them is a page a student can still
        // reach, and a teacher who is told only what came down has no way to
        // tell whether the tool thought about the rest.
        if !kept.isEmpty {
            lines.append("")
            let word: String = kept.count == 1 ? "page stays" : "pages stay"
            lines.append("\(kept.count) linked \(word) visible:")
            var listed: Int = 0
            for staying in kept {
                if listed == mostListed {
                    lines.append("…and \(kept.count - listed) more.")
                    break
                }
                lines.append(AssistPublishPlan.stayingVisibleLine(
                    title: staying.page.displayTitle, reason: staying.reason, noun: noun
                ))
                listed += 1
            }
        }

        // A date move whose page is NOT in the list above has nowhere else to
        // be said. It should not arise — every page that takes a class's date
        // is a hidden page this publish is making visible, so it is always one
        // of the changes — but a silent drop is the wrong way to find out
        // otherwise.
        var namedAlready: Set<String> = []
        for change in changes {
            namedAlready.insert(change.page.lowercasedTitle)
        }
        var orphaned: [AssistPublishDateMove] = []
        for move in dateMoves where !namedAlready.contains(move.page.lowercasedTitle) {
            orphaned.append(move)
        }
        if !orphaned.isEmpty {
            lines.append("")
            for move in orphaned {
                lines.append("“\(move.page.displayTitle)” will take the same date as "
                             + "“\(move.takenFrom)”.")
            }
        }

        if !unknownNames.isEmpty {
            lines.append("")
            lines.append("No page in this section is called "
                         + AssistPublishPlan.listing(unknownNames) + ".")
        }

        return lines.joined(separator: "\n")
    }

    /// "a", "a and b", "a, b and c" — the way a sentence says a list.
    /// The sentence for pages the writer declined, naming a few of them.
    static func sayingPagesWithNoRoomForAKey(_ pages: [AssistSectionPage]) -> String {
        var names: [String] = []
        for page in pages {
            names.append(page.displayTitle)
        }
        return sayingPagesWithNoRoomForAKey(named: names)
    }

    /// The same, from titles already to hand.
    static func sayingPagesWithNoRoomForAKey(named names: [String]) -> String {
        return AssistWording.pagesWhoseSettingsCannotBeAddedTo(listingAFew(names), count: names.count)
    }

    /// The sentence for pages whose new date could not be set, naming a few.
    static func sayingPagesWhoseNewDateCouldNotBeSet(named names: [String]) -> String {
        return AssistWording.pagesWhoseNewDateCouldNotBeSet(listingAFew(names), count: names.count)
    }

    /// `listing`, naming at most `mostNamed` and counting the rest — "“a”,
    /// “b”, “c” and 2 more" — for a sentence that names a few pages without
    /// turning into a list. Always names at least one: "0 pages" with nothing
    /// named is the silence #186 closes.
    static func listingAFew(_ names: [String], mostNamed: Int = 3) -> String {
        if names.count <= mostNamed {
            return listing(names)
        }
        var quoted: [String] = []
        var position: Int = 0
        while position < mostNamed {
            quoted.append("“\(names[position])”")
            position += 1
        }
        return quoted.joined(separator: ", ") + " and \(names.count - mostNamed) more"
    }

    static func listing(_ names: [String]) -> String {
        var quoted: [String] = []
        for name in names {
            quoted.append("“\(name)”")
        }
        if quoted.count <= 1 {
            return quoted.first ?? ""
        }
        let last: String = quoted.removeLast()
        return quoted.joined(separator: ", ") + " and " + last
    }
}

/// Working out what a publish or an unpublish would do, and doing it.
///
/// Publishing and unpublishing come through here as two separate entry points
/// that each hard-code their own verb. There is no `publish: Bool` to pass in
/// from outside, because the one genuinely dangerous failure ever observed was
/// polarity inversion — asked to HIDE a page, the model called publish with
/// "include everything it links to" set. A boolean is a coin flip under
/// pressure; a verb is not.
///
/// **How far each verb reaches is settled HERE, not by whoever calls.** There
/// used to be an `includeLinked` flag, and the model chose it — which is
/// precisely the reasoning this design exists to keep out of a router. The two
/// rules are not mirror images of each other, and each is written down once:
///
/// * **Publishing takes the pages it links to, and stops at another class.**
///   Publishing a page whose links lead somewhere students cannot see is the
///   one thing publishing must never do — so it takes what it links to, and
///   what those link to in turn. The one stop is a link that lands on another
///   CLASS: a class goes up when the teacher names that class, and material
///   reachable only through it belongs to it (issue #173). The plan says which
///   classes were left alone.
/// * **Unpublishing takes a linked page only when nothing else needs it** — no
///   other page links to it, and it is not one of the pages a section cannot do
///   without. Hiding a concept page that Unit 3, Day 2 also links to would
///   break that class to tidy this one. And, since #201 (2026-09-26), it stops
///   at another class exactly as publishing does: a class comes down when the
///   teacher names it, and a linked class that stays is named in the plan.
enum AssistPublishPlanner {

    // MARK: - Functions

    /// What publishing these pages would do — along with everything they link
    /// to, so no published page points at a page students cannot see, and
    /// stopping wherever a link lands on another class.
    static func planPublishing(
        titles: [String],
        onOrAfter: CalendarDay?,
        before: CalendarDay?,
        graph: AssistSectionGraph,
        classPages: [ClassPageSummary],
        forSection sectionNumber: Int,
        in course: Course
    ) -> AssistPublishPlan {
        // Date moves belong on THIS path too, and their absence was the bug.
        // "Publish tomorrow's class" worked them out; "Publish Unit 2, Day 3" —
        // naming the very same class page — passed an empty list, so the pages
        // the class brought with it kept whatever day their file was created
        // on. Same teacher, same class, two different results depending on
        // which sentence they used.
        let moves: [AssistPublishDateMove] = dateMovesFollowingClasses(
            titles: titles, graph: graph, classPages: classPages
        )
        return plan(
            publishes: true, titles: titles,
            onOrAfter: onOrAfter, before: before, graph: graph, classPages: classPages,
            dateMoves: moves, forSection: sectionNumber, in: course
        )
    }

    /// What unpublishing these pages would do — along with the pages ONLY they
    /// link to, and nothing else.
    static func planUnpublishing(
        titles: [String],
        onOrAfter: CalendarDay?,
        before: CalendarDay?,
        graph: AssistSectionGraph,
        classPages: [ClassPageSummary],
        forSection sectionNumber: Int,
        in course: Course
    ) -> AssistPublishPlan {
        return plan(
            publishes: false, titles: titles,
            onOrAfter: onOrAfter, before: before, graph: graph, classPages: classPages,
            dateMoves: [], forSection: sectionNumber, in: course
        )
    }

    /// What publishing the class taught on a given day would do.
    ///
    /// The coarse one. It finds the class by date, follows its links, and works
    /// out which pages should take the class's date — all in ordinary code,
    /// rather than leaving the model to chain three calls and choose an order.
    /// That single decision took an 8-of-8 failure to 8-of-8 correct on
    /// Windows, and it is the reason this function exists at all.
    static func planPublishingClass(
        on day: CalendarDay,
        graph: AssistSectionGraph,
        classPages: [ClassPageSummary],
        forSection sectionNumber: Int,
        in course: Course
    ) -> Result<AssistPublishPlan, AssistToolRefusal> {
        var matching: [ClassPageSummary] = []
        for summary in classPages where summary.date == day {
            matching.append(summary)
        }
        if matching.isEmpty {
            return .failure(.noClassOn(day, course.code, sectionNumber))
        }

        var titles: [String] = []
        for summary in matching {
            titles.append(summary.title)
        }

        // The same one rule as the named-pages path above. It used to be a
        // second rule here with a different condition, which is how the two
        // routes to the same act came to disagree.
        let moves: [AssistPublishDateMove] = dateMovesFollowingClasses(
            titles: titles, graph: graph, classPages: classPages
        )
        return .success(plan(
            publishes: true, titles: titles,
            onOrAfter: nil, before: nil, graph: graph, classPages: classPages,
            dateMoves: moves, forSection: sectionNumber, in: course
        ))
    }

    /// The shared machinery. Private, and the verb arrives as an argument only
    /// here — the two public entry points above are the only callers, and each
    /// of them writes the verb down literally.
    private static func plan(
        publishes: Bool,
        titles: [String],
        onOrAfter: CalendarDay?,
        before: CalendarDay?,
        graph: AssistSectionGraph,
        classPages: [ClassPageSummary],
        dateMoves: [AssistPublishDateMove],
        forSection sectionNumber: Int,
        in course: Course
    ) -> AssistPublishPlan {
        var named: [AssistSectionPage] = []
        var unknownNames: [String] = []
        var chosen: Set<String> = []

        for title in titles {
            guard let page = graph.page(titled: title) else {
                unknownNames.append(title.trimmingCharacters(in: .whitespaces))
                continue
            }
            if chosen.contains(page.lowercasedTitle) {
                continue
            }
            chosen.insert(page.lowercasedTitle)
            named.append(page)
        }

        // The dates are compared here rather than by the model: "every class
        // from September 15th" is one call, and a comparison the model never
        // makes is a comparison it never gets wrong.
        if titles.isEmpty && (onOrAfter != nil || before != nil) {
            for summary in classPages {
                guard let date = summary.date else {
                    continue
                }
                if let onOrAfter, date < onOrAfter {
                    continue
                }
                if let before, !(date < before) {
                    continue
                }
                guard let page = graph.page(titled: summary.title) else {
                    continue
                }
                if chosen.contains(page.lowercasedTitle) {
                    continue
                }
                chosen.insert(page.lowercasedTitle)
                named.append(page)
            }
        }

        // How far the verb reaches, decided by the verb itself.
        var linked: [AssistSectionPage] = []
        var kept: [AssistPublishKept] = []
        var linkedClassesLeftAlone: [AssistSectionPage] = []
        if publishes {
            let reach: AssistLinkedReach = graph.reachFollowingLinks(from: named)
            linked = reach.pages
            linkedClassesLeftAlone = classesWorthTellingTheTeacherAbout(
                among: reach.classPagesStoppedAt
            )
        } else {
            let sweep: UnpublishSweep = pagesTakenDownAlongside(
                named: named, graph: graph, in: course
            )
            linked = sweep.alsoUnpublished
            kept = sweep.kept
        }

        var changes: [AssistPublishChange] = []
        var alreadyRight: [AssistSectionPage] = []
        var noRoomForAKey: [AssistSectionPage] = []
        appendChanges(
            for: named, becauseLinked: false, publishes: publishes,
            forSection: sectionNumber, into: &changes, alreadyRight: &alreadyRight,
            noRoomForAKey: &noRoomForAKey
        )
        appendChanges(
            for: linked, becauseLinked: true, publishes: publishes,
            forSection: sectionNumber, into: &changes, alreadyRight: &alreadyRight,
            noRoomForAKey: &noRoomForAKey
        )

        // A page whose date would move but whose visibility is already right
        // still has to be written, so the date moves are carried through whole
        // rather than filtered against the visibility changes.
        return AssistPublishPlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            publishes: publishes,
            unknownNames: unknownNames,
            namedPages: named,
            changes: changes,
            alreadyRight: alreadyRight,
            noRoomForAKey: noRoomForAKey,
            kept: kept,
            linkedClassesLeftAlone: linkedClassesLeftAlone,
            dateMoves: dateMoves
        )
    }

    /// Of the classes the walk stopped at, the ones worth a sentence.
    ///
    /// **Only the ones students cannot already see, and certainly cannot.** The
    /// sentence exists to explain a link students cannot follow yet; about a
    /// class that is already published it is false, and it would tell a teacher
    /// to go and publish a page that is already published. A class whose flag
    /// this app will not read is NOT left out: "already published" has to be
    /// something the app is sure of, the same requirement `appendChanges` makes
    /// of "already the way you asked".
    private static func classesWorthTellingTheTeacherAbout(
        among stoppedAt: [AssistSectionPage]
    ) -> [AssistSectionPage] {
        var worthSaying: [AssistSectionPage] = []
        for page in stoppedAt {
            if page.isVisibleToStudents && page.visibilityIsCertain {
                continue
            }
            worthSaying.append(page)
        }
        return worthSaying
    }

    private static func appendChanges(
        for pages: [AssistSectionPage],
        becauseLinked: Bool,
        publishes: Bool,
        forSection sectionNumber: Int,
        into changes: inout [AssistPublishChange],
        alreadyRight: inout [AssistSectionPage],
        noRoomForAKey: inout [AssistSectionPage]
    ) {
        for page in pages {
            // "Already the way you asked" needs CERTAINTY, not just a match.
            // A page whose flag this app will not read is reported visible,
            // and a plan that believed that would tell a teacher their page
            // was already published and write nothing, while the build was
            // holding it back. So an unreadable flag is always a change, and
            // `AssistPageVisibility.setting` writes it out in full.
            if page.isVisibleToStudents == publishes && page.visibilityIsCertain {
                alreadyRight.append(page)
                continue
            }
            // A page that cannot be read cannot be changed either, and
            // listing it would promise the teacher something the writing step
            // then quietly skips.
            guard let text = try? String(contentsOf: page.fileURL, encoding: .utf8) else {
                continue
            }
            // The same argument, one step further: a page the WRITER would
            // decline is not a change either. Asked by running the real
            // writer over the page's own text — this read was already being
            // made and thrown away — because a second copy of the rule here
            // is a second copy to keep in step (#186).
            let trial: (text: String, outcome: FrontmatterWriteOutcome) = AssistPageVisibility.setting(
                published: publishes, in: text,
                forSection: sectionNumber, isSectionLocal: page.isSectionLocal
            )
            if trial.outcome == .noRoomForAKey {
                noRoomForAKey.append(page)
                continue
            }
            changes.append(AssistPublishChange(
                page: page,
                key: AssistPageVisibility.publishKey(
                    forSection: sectionNumber, isSectionLocal: page.isSectionLocal
                ),
                wasVisible: page.isVisibleToStudents,
                willBeVisible: publishes,
                becauseLinked: becauseLinked
            ))
        }
    }

    // MARK: - How far an unpublish reaches

    /// What following an unpublish's links comes to: the pages that go with it,
    /// and the pages that stay, each with its reason.
    struct UnpublishSweep {

        // MARK: - Stored properties

        let alsoUnpublished: [AssistSectionPage]
        let kept: [AssistPublishKept]
    }

    /// The title of the panel every section carries, and whose entries are
    /// the section's way around itself.
    static let keyLinksTitle: String = "Key Links"

    /// The pages that come down alongside the ones the teacher named.
    ///
    /// The rule is deliberately NOT the mirror image of publishing. A linked
    /// page comes down only when the pages being taken down are the only ones
    /// that link to it; anything another page still points at stays, or hiding
    /// this week's lesson would leave last week's pointing at nothing.
    ///
    /// Three kinds of page never come down this way, whatever the link count:
    /// a folder's landing page (the way IN to a folder), anything the section's
    /// Key Links offers, and any curriculum page. Each is reached from
    /// somewhere other than a lesson, so a link count says nothing useful about
    /// whether it is still needed.
    ///
    /// A fourth never, of a different kind (#201): another CLASS page. It is
    /// not one of the contract's `neverTakenDownByFollowingLinks` — those are
    /// exclusions, pages reached from somewhere other than a lesson — but a
    /// STOP in the walk, the same stop publishing and date-moving make, so it
    /// is written once in `followingLinks.stopsAtAClassPage.appliesTo`. The
    /// walk still REACHES the class (`pagesLinkedFrom` does not filter it):
    /// it has to arrive at the `kept` pass, or the teacher is never told it
    /// stayed. `reasonToKeep` is where it stops, so a class is neither
    /// collected nor entered.
    ///
    /// Worked out to a fixed point rather than in one pass: when a page joins
    /// the ones coming down, the pages only IT linked to become free to follow
    /// as well, and stopping after one lap would leave half a chain published.
    static func pagesTakenDownAlongside(
        named: [AssistSectionPage],
        graph: AssistSectionGraph,
        in course: Course
    ) -> UnpublishSweep {
        var goingDown: Set<String> = []
        for page in named {
            goingDown.insert(page.lowercasedTitle)
        }

        let referrers: [String: [AssistSectionPage]] = pagesLinkingIn(graph: graph)
        let mustStay: Set<String> = pagesThisSectionCannotDoWithout(graph: graph)

        var alsoUnpublished: [AssistSectionPage] = []
        var foundMore: Bool = true
        while foundMore {
            foundMore = false
            for candidate in pagesLinkedFrom(goingDown, graph: graph) {
                if goingDown.contains(candidate.lowercasedTitle) {
                    continue
                }
                let reason: AssistPublishKept.Reason? = reasonToKeep(
                    candidate, mustStay: mustStay, referrers: referrers,
                    goingDown: goingDown, graph: graph, in: course
                )
                if reason != nil {
                    continue
                }
                goingDown.insert(candidate.lowercasedTitle)
                alsoUnpublished.append(candidate)
                foundMore = true
            }
        }

        var kept: [AssistPublishKept] = []
        for candidate in pagesLinkedFrom(goingDown, graph: graph) {
            // Only pages a student can see as things stand. A page already
            // hidden is not "staying published", and saying it is would be
            // noise in a plan meant to be read aloud.
            if !candidate.isVisibleToStudents {
                continue
            }
            guard let reason = reasonToKeep(
                candidate, mustStay: mustStay, referrers: referrers,
                goingDown: goingDown, graph: graph, in: course
            ) else {
                continue
            }
            kept.append(AssistPublishKept(page: candidate, reason: reason))
        }

        return UnpublishSweep(alsoUnpublished: alsoUnpublished, kept: kept)
    }

    /// Why this page is being left published, or nil when nothing stands in
    /// the way of taking it down with the rest.
    ///
    /// **An unpublish stops at another class** (issue #201, decided by
    /// Russell 2026-09-26 to mirror #173's publishing rule): a class is hidden
    /// when the teacher names it, and a link from the class coming down
    /// neither takes another class with it nor reaches THROUGH it to that
    /// class's own material. The pages the teacher named are never stopped —
    /// they are in `goingDown` before this is ever asked — so "unpublish Unit
    /// 4" and an unpublish by dates lose nothing. The rule is shared as
    /// `followingLinks.stopsAtAClassPage` in `contracts/shared-rules.json`.
    ///
    /// The order is load-bearing, both ways:
    /// - the class test sits BELOW the three exclusions, so a class Key Links
    ///   points at still says Key Links, and `theOrderIsLoadBearing` is
    ///   untouched;
    /// - and ABOVE the referrer test, because "a class of its own" is the
    ///   unconditional reason and "X still links to it" a contingent one: said
    ///   about a class, it tells the teacher the class would follow X down the
    ///   day X is hidden, and it would not.
    ///
    /// REJECTED: stopping in `pagesLinkedFrom` instead (right about what comes
    /// down, and SILENT — the class never reaches the `kept` pass, so nothing
    /// tells the teacher); walking past the class to the material beyond it
    /// (that material is the class's, and hiding it breaks a class nobody
    /// named); and a fourth entry in `neverTakenDownByFollowingLinks` (a class
    /// is a stop, not an exclusion). documentation/10-local-ai-assistant.md →
    /// "Unpublishing stops there too (#201)".
    private static func reasonToKeep(
        _ page: AssistSectionPage,
        mustStay: Set<String>,
        referrers: [String: [AssistSectionPage]],
        goingDown: Set<String>,
        graph: AssistSectionGraph,
        in course: Course
    ) -> AssistPublishKept.Reason? {
        if page.isFolderIndex {
            return .folderLandingPage
        }
        if mustStay.contains(page.lowercasedTitle) {
            return .keyLinks
        }
        // `build_site.py`'s own rule: any FOLDER segment containing
        // "curriculum", so a course whose folder is called "Ontario
        // Curriculum" is covered exactly as a plain one is.
        if AssistCurriculumMentions.isCurriculum(pageAt: page.fileURL, in: course) {
            return .curriculum
        }
        if page.isClassPage {
            return .aClassOfItsOwn
        }
        if let stillLinking = pageStillLinking(to: page, referrers: referrers,
                                               goingDown: goingDown, graph: graph) {
            return .stillLinkedFrom(stillLinking)
        }
        return nil
    }

    /// A page outside this unpublish that still links to the given one, named
    /// as the teacher would see it — or nil when the pages coming down are the
    /// only ones that point at it.
    ///
    /// The referrer is carried as a PAGE rather than as a name, and that is
    /// load-bearing rather than tidiness. A name would have to be looked back
    /// up through `graph.page(titled:)`, which keys on the file name — and
    /// every folder's landing page is called `index`, so eleven different
    /// pages share one key and the lookup returns whichever came first in path
    /// order. That was invisible while the answer was printed as "index"; the
    /// moment it is printed as "Portfolios" it becomes a confidently wrong
    /// name, which is worse than a useless one.
    private static func pageStillLinking(
        to page: AssistSectionPage,
        referrers: [String: [AssistSectionPage]],
        goingDown: Set<String>,
        graph: AssistSectionGraph
    ) -> String? {
        for referrer in referrers[page.lowercasedTitle] ?? [] {
            if goingDown.contains(referrer.lowercasedTitle) {
                continue
            }
            // **A HIDDEN page is not a reason to keep anything published.**
            // "X still links to it" was counted whether or not students could
            // see X — so a page could sit visible, reachable from nothing,
            // held up by a draft nobody has published. Kept alive by a page
            // that is not there.
            //
            // Safe in the other direction because publishing is transitive:
            // when that draft is published, everything it links to is
            // published with it, and the plan says so. So a page taken down
            // here comes back the moment anything visible needs it again.
            //
            // That held with one exception from #173 (publishing stops at a
            // class, so a CLASS this sweep took down did not come back by
            // publishing the page that referred to it) until #201 closed it
            // on 2026-09-26: this sweep no longer takes a class down at all,
            // so both reaches stop in the same place and the argument holds
            // without an exception.
            if !referrer.isVisibleToStudents {
                continue
            }
            return referrer.displayTitle
        }
        return nil
    }

    /// Which pages link to each page, by lowercased title. A page linking to
    /// itself is not a reason to keep it.
    private static func pagesLinkingIn(graph: AssistSectionGraph) -> [String: [AssistSectionPage]] {
        var referrers: [String: [AssistSectionPage]] = [:]
        for page in graph.pages {
            for target in page.linkedTitles {
                if target == page.lowercasedTitle {
                    continue
                }
                var linking: [AssistSectionPage] = referrers[target] ?? []
                // Compared by PATH, not by name. Two folders' landing pages
                // are both called `index`, and de-duplicating on the name
                // threw the second one away — so a page linked from both
                // Portfolios and Style recorded only one of them, and which
                // one depended on the order the folder was walked in.
                var already: Bool = false
                for existing in linking {
                    if existing.fileURL == page.fileURL {
                        already = true
                        break
                    }
                }
                if already {
                    continue
                }
                linking.append(page)
                referrers[target] = linking
            }
        }
        return referrers
    }

    /// The pages a section cannot do without: everything its Key Links panel
    /// offers, and the panel itself.
    static func pagesThisSectionCannotDoWithout(graph: AssistSectionGraph) -> Set<String> {
        var titles: Set<String> = []
        guard let keyLinks = graph.page(titled: keyLinksTitle) else {
            return titles
        }
        titles.insert(keyLinks.lowercasedTitle)
        for target in keyLinks.linkedTitles {
            titles.insert(target)
        }
        return titles
    }

    /// The pages these ones link to, one hop out, leaving out the ones already
    /// counted in.
    private static func pagesLinkedFrom(
        _ titles: Set<String>,
        graph: AssistSectionGraph
    ) -> [AssistSectionPage] {
        var found: [AssistSectionPage] = []
        var seen: Set<String> = []
        for page in graph.pages where titles.contains(page.lowercasedTitle) {
            for target in page.linkedTitles {
                if titles.contains(target) || seen.contains(target) {
                    continue
                }
                guard let linked = graph.page(titled: target) else {
                    // A link out of this section, or to a page nobody wrote.
                    continue
                }
                seen.insert(target)
                found.append(linked)
            }
        }
        return found
    }

    // MARK: - A whole unit

    /// The unit a teacher named, if that is what they named: "Unit 4",
    /// "unit 4", "Unit 4." — but never "Unit 4, Day 3", which is one page.
    ///
    /// **The course's own word is accepted, and so is "unit".** A course whose
    /// class pages are "Module 2, Day 3" gets asked to publish "Module 4", and
    /// reading only "unit" meant the request found nothing and the teacher was
    /// told no page is called that — a whole feature missing for that course,
    /// silently. "unit" is still accepted alongside it because a teacher types
    /// what they are used to and the model echoes what it was shown; the unit
    /// NUMBER is the answer either way, so accepting both cannot be ambiguous.
    ///
    /// **Nil, always, in a numbered course (#267).** A club's pages are
    /// "Week 1", "Week 2", held inside this app as unit 1 — so reading
    /// "Week 1" as a unit would make "publish Week 1", the most ordinary
    /// request a club has, publish EVERY meeting at once, and "Week 3" would
    /// find no unit and be refused instead of publishing the page. A numbered
    /// course has no units; its titles go to the page path, which acts on the
    /// one page named. No default naming, so a caller cannot forget this.
    static func unitNamed(_ raw: String, naming: ClassPageNaming) -> Int? {
        if naming.isNumbered {
            return nil
        }
        let term: String = naming.word
        let tidied: String = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
            .lowercased()
        var rest: String? = nil
        for word in [ClassPageTerm.cleaned(term).lowercased(), "unit"] {
            let prefix: String = word + " "
            if tidied.hasPrefix(prefix) {
                rest = String(tidied.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard let named = rest else {
            return nil
        }
        // A comma means they went on to name a day, which is a page.
        if named.isEmpty || named.contains(",") {
            return nil
        }
        return Int(named)
    }

    /// A unit's class pages, **highest day first**.
    ///
    /// The order is the request, not an implementation detail: unpublishing a
    /// unit walks backwards from its last day. Doing it that way means every
    /// step asks "is anything else still using this?" against the state as it
    /// actually is at that moment, which is the same question a teacher would
    /// ask taking the unit down by hand, one page at a time, from the end.
    static func classPages(inUnit unit: Int, from classPages: [ClassPageSummary]) -> [ClassPageSummary] {
        var found: [ClassPageSummary] = []
        for summary in classPages {
            // A numbered course has no units (see `unitNamed`): its pages
            // are never a unit's pages, whatever this app holds them as.
            if summary.naming.isNumbered {
                continue
            }
            guard let numbers = summary.unitAndDay, numbers.unit == unit else {
                continue
            }
            found.append(summary)
        }
        found.sort { first, second in
            let firstDay: Int = first.unitAndDay?.day ?? 0
            let secondDay: Int = second.unitAndDay?.day ?? 0
            return firstDay > secondDay
        }
        return found
    }

    // MARK: - Dates

    /// A page a class links to takes that class's date **when this publish is
    /// the first time students will ever see it**.
    ///
    /// The point of it, in a teacher's terms: everything a class brings with it
    /// should turn up under that class on the site. A worksheet written for
    /// Unit 2, Day 3 that has been sitting unpublished should appear on Unit 2,
    /// Day 3's day, not on whatever day it happened to be created.
    ///
    /// **Two conditions, and only two.**
    ///
    /// 1. The page is **hidden right now**, and this publish is what makes it
    ///    visible. A page students can already see keeps its date: it has a
    ///    place on the site that somebody may have linked to or looked at, and
    ///    republishing a class must not shuffle work that was already out.
    /// 2. It is **not itself a class page**. A class's date is its position in
    ///    the schedule; nothing may move it.
    ///
    /// **What is deliberately NOT a condition, and used to be.** This rule
    /// previously moved a page only when no OTHER class linked to it, reasoned
    /// as: "a concept page linked from three different lessons belongs to none
    /// of them and is left exactly where it is." That reasoning is sound for a
    /// page already on the site and beside the point for one that has never
    /// been seen. A page nobody can reach has no place to be left in — it has
    /// only the date it was created on, which is the day its FILE was made and
    /// means nothing to a student. Given the choice between "the day this
    /// material first appears" and "the day somebody happened to type it", the
    /// first is the answer a reader wants, even when three classes share it.
    ///
    /// Where several of the classes being published reach the same page, the
    /// EARLIEST one claims it. That is the convention the course installer
    /// already follows — `first_use_dates` in `setup_course.py` dates a shared
    /// page to the first class that references it — and matching it means a
    /// pre-populated course and a hand-published one date their pages the same
    /// way.
    ///
    /// "Never published" is inferred from the page being hidden now, because
    /// nothing on disk records a page's history. A page published once and
    /// later hidden therefore counts as never published, and would take a new
    /// date. Recording the truth would mean a new frontmatter key on every
    /// page, agreed with the Python and the Windows app; the inference costs
    /// nothing and is right in every case anybody has met.
    static func dateMovesFollowingClasses(
        titles: [String],
        graph: AssistSectionGraph,
        classPages: [ClassPageSummary]
    ) -> [AssistPublishDateMove] {
        // Only the NAMED pages that are really classes with a date. Publishing
        // an ordinary page moves nothing: there is no class day to inherit.
        var named: [(page: AssistSectionPage, day: CalendarDay)] = []
        for title in titles {
            guard let page = graph.page(titled: title), let day = page.date else {
                continue
            }
            var isAClass: Bool = page.isClassPage
            for summary in classPages
            where AssistSectionGraph.normalized(summary.title) == page.lowercasedTitle {
                isAClass = true
            }
            if isAClass {
                named.append((page: page, day: day))
            }
        }

        // Earliest first, so the first class to use a page is the one that
        // dates it. Title breaks a tie, so two classes on one day give the
        // same answer every run rather than depending on folder order.
        named.sort { first, second in
            if first.day.text != second.day.text {
                return first.day.text < second.day.text
            }
            return first.page.lowercasedTitle < second.page.lowercasedTitle
        }

        var claimed: Set<String> = []
        var moves: [AssistPublishDateMove] = []
        for entry in named {
            // The same reach publishing uses, so the two halves of one publish
            // cannot disagree about how far it went. It stops at a class, so a
            // page reachable only THROUGH another class is never offered a
            // date here — it takes the date of the class that actually brings
            // it, when that class is published.
            for page in graph.reachFollowingLinks(from: [entry.page]).pages {
                if claimed.contains(page.lowercasedTitle) {
                    continue
                }
                // Already out where students can see it — leave it alone.
                //
                // CERTAINLY out, that is. A page whose flag this app will not
                // read is reported visible, and it is about to be published
                // by the change list above; skipping it here would publish it
                // with whatever date it happened to have rather than the day
                // of the class that brought it.
                if page.isVisibleToStudents && page.visibilityIsCertain {
                    continue
                }
                // A class's date is its place in the schedule.
                //
                // Belt and braces since #173: the reach above no longer hands
                // back a class page at all. Kept because this is where
                // `class-planning.json` → `datingPagesAClassBrings` names the
                // rule, and a rule upheld only by the absence of a page is one
                // a later reader deletes without knowing they have.
                if page.isClassPage {
                    continue
                }
                claimed.insert(page.lowercasedTitle)
                if page.date == entry.day {
                    continue
                }
                moves.append(AssistPublishDateMove(
                    page: page, from: page.date, to: entry.day,
                    takenFrom: entry.page.displayTitle
                ))
            }
        }
        return moves
    }

    /// Carry the plan out. Returns the change record so it can be undone, and
    /// the titles of any pages the writer DECLINED as it went (#186).
    ///
    /// The plan asked the same question before the card was shown, so the
    /// second list is almost always empty. It is returned all the same,
    /// because "almost always" is a page the teacher edited in Obsidian
    /// between reading the card and pressing Go — and a reply that claimed
    /// that page would be claiming a write that did not happen.
    static func apply(
        _ plan: AssistPublishPlan,
        forSection sectionNumber: Int,
        in course: Course
    ) throws -> (change: AssistChange, leftAlone: [String]) {
        // Every file this plan touches, gathered first, so a page that both
        // changes visibility and moves date is written once.
        var editsByPath: [String: (url: URL, isSectionLocal: Bool)] = [:]
        var publishByPath: [String: Bool] = [:]
        var dateByPath: [String: CalendarDay] = [:]
        var titleByPath: [String: String] = [:]

        for change in plan.changes {
            let path: String = change.page.fileURL.path
            editsByPath[path] = (change.page.fileURL, change.page.isSectionLocal)
            publishByPath[path] = change.willBeVisible
            titleByPath[path] = change.page.displayTitle
        }
        for move in plan.dateMoves {
            let path: String = move.page.fileURL.path
            editsByPath[path] = (move.page.fileURL, move.page.isSectionLocal)
            dateByPath[path] = move.to
            titleByPath[path] = move.page.displayTitle
        }

        var paths: [String] = []
        for (path, _) in editsByPath {
            paths.append(path)
        }
        paths.sort()

        let tail: String = ClassPages.siblingTimeAndOffset(
            from: ClassPages.list(forSection: sectionNumber, in: course),
            forSection: sectionNumber
        )

        var saved: [AssistSavedFile] = []
        // Pages that were planned as changes and then declined at the moment
        // of writing, and the pages whose VISIBILITY actually moved — what the
        // teacher is told is built from these, not from the plan.
        var leftAlone: [String] = []
        var movedTitles: [String] = []
        for path in paths {
            guard let edit = editsByPath[path] else {
                continue
            }
            let before: String = try String(contentsOf: edit.url, encoding: .utf8)
            var text: String = before
            var declined: Bool = false
            var visibilityMoved: Bool = false

            if let published = publishByPath[path] {
                let result: (text: String, outcome: FrontmatterWriteOutcome) = AssistPageVisibility.setting(
                    published: published, in: text,
                    forSection: sectionNumber, isSectionLocal: edit.isSectionLocal
                )
                if result.outcome == .noRoomForAKey {
                    declined = true
                }
                if result.outcome == .written {
                    visibilityMoved = true
                }
                text = result.text
            }
            if let day = dateByPath[path] {
                let result: (text: String, outcome: FrontmatterWriteOutcome) = PageFrontmatter.settingCreated(
                    in: text,
                    key: PageFrontmatter.createdKey(
                        forSection: sectionNumber, isSectionLocal: edit.isSectionLocal
                    ),
                    to: day,
                    fallbackTail: tail
                )
                if result.outcome == .noRoomForAKey {
                    declined = true
                }
                text = result.text
            }

            let title: String = titleByPath[path] ?? edit.url.deletingPathExtension().lastPathComponent
            if declined {
                leftAlone.append(title)
            }
            if text == before {
                continue
            }
            try text.write(to: edit.url, atomically: true, encoding: .utf8)
            saved.append(AssistSavedFile(fileURL: edit.url, before: before, after: text))
            if visibilityMoved {
                movedTitles.append(title)
            }
        }

        // The section's landing page follows its most recent visible class.
        //
        // Done HERE rather than in the tool, so it lands inside the same
        // `AssistChange` as the pages themselves — which means "Undo that"
        // takes the index back with them. An undo that restored the lessons
        // and left the front page pointing at the wrong one would be a worse
        // state than either.
        if let repointed = SectionIndexPointer.repointIndex(forSection: sectionNumber, in: course) {
            saved.append(repointed)
        }

        let change: AssistChange = AssistChange(
            whatHappened: "\(plan.verb)ed "
                + AssistPublishPlanner.namingWhatMoved(movedTitles: movedTitles, savedCount: saved.count),
            courseCode: plan.courseCode,
            sectionNumber: sectionNumber,
            // Publishing and hiding rebuild the preview, so taking them back
            // has to rebuild it too — that was the whole complaint.
            rebuildsThePreview: true,
            files: saved
        )
        return (change: change, leftAlone: leftAlone)
    }

    /// What to call the thing that moved, for a sentence read back to the
    /// teacher a minute or an hour later.
    ///
    /// **Names the pages while there are few enough to name.** The count came
    /// first and was wrong in a way that only shows up at undo time: asking to
    /// unpublish one class writes TWO files, because the section's landing page
    /// is repointed in the same change — so "unpublished 2 pages" was both
    /// arithmetically right and unrecognisable to somebody who had asked for
    /// Unit 4, Day 23. The pages whose VISIBILITY moved are what the teacher
    /// asked about; the index following along is bookkeeping.
    ///
    /// Three or more falls back to a count, because a sentence listing nine
    /// class titles is not a sentence anybody reads.
    ///
    /// **Built from the pages actually WRITTEN, not from the plan** (#186).
    /// The two used to be the same list; they stopped being the same the day
    /// the writer learned to decline a page it cannot change safely, and an
    /// undo labelled "unpublished Unit 4, Day 23" about a page nothing was
    /// written to would be the claim this piece removes.
    private static func namingWhatMoved(movedTitles names: [String], savedCount: Int) -> String {
        if names.count == 1 {
            return names[0]
        }
        if names.count == 2 {
            return names[0] + " and " + names[1]
        }
        if names.count > 2 {
            return "\(names.count) pages"
        }
        // Nothing's visibility moved, so this was a date change alone.
        let word: String = savedCount == 1 ? "page" : "pages"
        return "\(savedCount) \(word)"
    }
}

/// A reason a tool did not go ahead, in words a teacher can act on.
///
/// A refusal is an ANSWER, not a crash: it comes back as ordinary text so the
/// assistant reads the reason out and can correct itself.
enum AssistToolRefusal: LocalizedError, Equatable {
    case noWorkingFolder
    case noSuchCourse(String)
    case noSuchSection(String, Int)
    case noSuchPage(String, String, Int)
    case unreadablePage(String)
    case noClassOn(CalendarDay, String, Int)
    case unreadableDate(String, String)
    case unreadableTime(String)
    case nothingNamed
    case openEndedPublish(CalendarDay)
    case notInThisBuild(String)
    /// The course named is kept for reference, so nothing may write to it and
    /// nothing may deploy it.
    ///
    /// A case of its own rather than another `notInThisBuild`, so the contract
    /// can pin it BY NAME: this is the refusal that must never quietly become
    /// a success, and a free-text refusal is one nothing can assert on.
    case keptForReference(String)
    /// A course was named by its CODE alone, no live course has that code,
    /// and one or more courses kept for reference show it.
    case askedForACourseByItsCodeAlone(String, [String])

    var errorDescription: String? {
        switch self {
        case .noWorkingFolder:
            return "No working folder is open, so there is nothing to look at."
        case .noSuchCourse(let code):
            // An EMPTY code is no course named at all (issue #198): only an
            // MCP caller can send one, and naming "“”" as a course that is
            // not here is false and reads as blaming the teacher.
            if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return AssistWording.noCourseNamed
            }
            return "There is no course called “\(code)” in this working folder."
        case .noSuchSection(let code, let number):
            return "\(code) has no Section \(number)."
        case .noSuchPage(let title, let code, let number):
            return "No page in \(code) Section \(number) is called “\(title)”. "
                 + "Use list_pages to find its exact title."
        case .unreadablePage(let title):
            return "“\(title)” could not be read, so nothing was changed."
        case .noClassOn(let day, let code, let number):
            // Named the tool — "Use list_pages to see what classes there are"
            // — in a sentence that goes straight to the teacher, since a
            // refusal ends the turn rather than going back to the model. The
            // way out is now said in the words the window already offers.
            return "I can't find a class on \(day.weekdayName), \(day.text), in \(code) "
                 + "Section \(number). Ask me what dates you are teaching to see the ones I know "
                 + "about, or tell me the name of the class page you meant."
        case .unreadableDate(let raw, let which):
            return "“\(raw)” isn't a date \(which) can use. Give it as YYYY-MM-DD, for example 2026-09-15."
        case .unreadableTime(let raw):
            return "“\(raw)” isn't a time I can read. Use YYYY-MM-DD HH:MM, for example 2026-09-09 06:30."
        case .nothingNamed:
            return "No pages and no dates were given, so there is nothing to change."
        case .openEndedPublish(let day):
            return "That asks to publish every class from \(day.text) to the end of the course, which is "
                 + "almost certainly not what was meant. For ONE day's class, use publish_class_on with "
                 + "that date. For a stretch of classes, give both onOrAfter and before. To publish "
                 + "particular pages, name them."
        case .notInThisBuild(let what):
            return what
        case .askedForACourseByItsCodeAlone(let code, let candidates):
            // Named rather than guessed. Two courses deliberately SHOW the
            // same code — that is what makes a reference course readable to a
            // teacher — so a guess here would look right every time and be
            // wrong half of it.
            let listed: String = candidates.joined(separator: ", ")
            if candidates.count == 1 {
                return "No course you are teaching is called \(code). "
                     + "\(listed) is kept for reference and shows that code — name it as \(listed)."
            }
            return "No course you are teaching is called \(code). "
                 + "These are kept for reference and show that code: \(listed). "
                 + "Name the one you mean."
        case .keptForReference(let code):
            // The FROZEN sentence, not the deploy one: this refusal covers
            // every write, and "it is never deployed" answers a question
            // nobody asked of "add a class to ICS3U".
            return ReferenceWording.staysAsItIs(course: code)
        }
    }

    /// The same words, never nil.
    var message: String {
        return errorDescription ?? "That could not be done."
    }
}
