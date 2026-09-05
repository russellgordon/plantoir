import Foundation

/// One page whose visibility would move.
struct AssistPublishChange {

    // MARK: - Stored properties

    let page: AssistSectionPage

    /// The frontmatter key that decides it — named in the plan so a teacher
    /// reading the plan can go and look at the same line.
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

    // MARK: - Stored properties

    let page: AssistSectionPage

    /// The clause that finishes "“Ohm's Law” stays: …".
    let reason: String
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

    /// Pages an unpublish reached by following a link and left published, each
    /// with the reason. Always empty when publishing: publishing a page
    /// publishes everything it links to, with nothing held back.
    let kept: [AssistPublishKept]

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
        // Every page they named is already the way they asked for it.
        for page in namedPages where page.isVisibleToStudents != publishes {
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
    func describe(mostListed: Int = 15) -> String {
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
                // The reasons are written to finish this sentence, and each
                // ends with its own full stop.
                lines.append("“\(staying.page.displayTitle)” stays visible, "
                             + "because \(staying.reason)")
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
/// * **Publishing always takes the pages it links to.** Publishing a page whose
///   links lead somewhere students cannot see is the one thing publishing must
///   never do.
/// * **Unpublishing takes a linked page only when nothing else needs it** — no
///   other page links to it, and it is not one of the pages a section cannot do
///   without. Hiding a concept page that Unit 3, Day 2 also links to would
///   break that class to tidy this one.
enum AssistPublishPlanner {

    // MARK: - Functions

    /// What publishing these pages would do — along with everything they link
    /// to, always, so no published page points at a page students cannot see.
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
        if publishes {
            linked = graph.linkedPages(from: named)
        } else {
            let sweep: UnpublishSweep = pagesTakenDownAlongside(
                named: named, graph: graph, in: course
            )
            linked = sweep.alsoUnpublished
            kept = sweep.kept
        }

        var changes: [AssistPublishChange] = []
        var alreadyRight: [AssistSectionPage] = []
        appendChanges(
            for: named, becauseLinked: false, publishes: publishes,
            forSection: sectionNumber, into: &changes, alreadyRight: &alreadyRight
        )
        appendChanges(
            for: linked, becauseLinked: true, publishes: publishes,
            forSection: sectionNumber, into: &changes, alreadyRight: &alreadyRight
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
            kept: kept,
            dateMoves: dateMoves
        )
    }

    private static func appendChanges(
        for pages: [AssistSectionPage],
        becauseLinked: Bool,
        publishes: Bool,
        forSection sectionNumber: Int,
        into changes: inout [AssistPublishChange],
        alreadyRight: inout [AssistSectionPage]
    ) {
        for page in pages {
            if page.isVisibleToStudents == publishes {
                alreadyRight.append(page)
                continue
            }
            guard let text = try? String(contentsOf: page.fileURL, encoding: .utf8) else {
                continue
            }
            changes.append(AssistPublishChange(
                page: page,
                key: AssistPageVisibility.keyInUse(
                    in: text, forSection: sectionNumber, isSectionLocal: page.isSectionLocal
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
                let reason: String? = reasonToKeep(
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
    private static func reasonToKeep(
        _ page: AssistSectionPage,
        mustStay: Set<String>,
        referrers: [String: [AssistSectionPage]],
        goingDown: Set<String>,
        graph: AssistSectionGraph,
        in course: Course
    ) -> String? {
        if page.isFolderIndex {
            return "it is a folder's landing page, which following links never takes down."
        }
        if mustStay.contains(page.lowercasedTitle) {
            return "it is in this section's Key Links."
        }
        // `build_site.py`'s own rule: any FOLDER segment containing
        // "curriculum", so a course whose folder is called "Ontario
        // Curriculum" is covered exactly as a plain one is.
        if AssistCurriculumMentions.isCurriculum(pageAt: page.fileURL, in: course) {
            return "it is a curriculum page."
        }
        if let stillLinking = pageStillLinking(to: page, referrers: referrers,
                                               goingDown: goingDown, graph: graph) {
            return "“\(stillLinking)” still links to it."
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
    static func unitNamed(_ raw: String, term: String = ClassPageTerm.standard) -> Int? {
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
            for page in graph.linkedPages(from: [entry.page]) {
                if claimed.contains(page.lowercasedTitle) {
                    continue
                }
                // Already out where students can see it — leave it alone.
                if page.isVisibleToStudents {
                    continue
                }
                // A class's date is its place in the schedule.
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

    /// Carry the plan out. Returns the change record so it can be undone.
    static func apply(
        _ plan: AssistPublishPlan,
        forSection sectionNumber: Int,
        in course: Course
    ) throws -> AssistChange {
        // Every file this plan touches, gathered first, so a page that both
        // changes visibility and moves date is written once.
        var editsByPath: [String: (url: URL, isSectionLocal: Bool)] = [:]
        var publishByPath: [String: Bool] = [:]
        var dateByPath: [String: CalendarDay] = [:]

        for change in plan.changes {
            let path: String = change.page.fileURL.path
            editsByPath[path] = (change.page.fileURL, change.page.isSectionLocal)
            publishByPath[path] = change.willBeVisible
        }
        for move in plan.dateMoves {
            let path: String = move.page.fileURL.path
            editsByPath[path] = (move.page.fileURL, move.page.isSectionLocal)
            dateByPath[path] = move.to
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
        for path in paths {
            guard let edit = editsByPath[path] else {
                continue
            }
            let before: String = try String(contentsOf: edit.url, encoding: .utf8)
            var text: String = before

            if let published = publishByPath[path] {
                text = AssistPageVisibility.setting(
                    published: published, in: text,
                    forSection: sectionNumber, isSectionLocal: edit.isSectionLocal
                ).text
            }
            if let day = dateByPath[path] {
                text = PageFrontmatter.settingCreated(
                    in: text,
                    key: PageFrontmatter.createdKey(
                        forSection: sectionNumber, isSectionLocal: edit.isSectionLocal
                    ),
                    to: day,
                    fallbackTail: tail
                ).text
            }

            if text == before {
                continue
            }
            try text.write(to: edit.url, atomically: true, encoding: .utf8)
            saved.append(AssistSavedFile(fileURL: edit.url, before: before, after: text))
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

        return AssistChange(
            whatHappened: "\(plan.verb)ed \(AssistPublishPlanner.namingWhatMoved(in: plan, savedCount: saved.count))",
            courseCode: plan.courseCode,
            sectionNumber: sectionNumber,
            // Publishing and hiding rebuild the preview, so taking them back
            // has to rebuild it too — that was the whole complaint.
            rebuildsThePreview: true,
            files: saved
        )
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
    private static func namingWhatMoved(in plan: AssistPublishPlan, savedCount: Int) -> String {
        var names: [String] = []
        for change in plan.changes {
            names.append(change.page.displayTitle)
        }
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

    var errorDescription: String? {
        switch self {
        case .noWorkingFolder:
            return "No working folder is open, so there is nothing to look at."
        case .noSuchCourse(let code):
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
        }
    }

    /// The same words, never nil.
    var message: String {
        return errorDescription ?? "That could not be done."
    }
}
