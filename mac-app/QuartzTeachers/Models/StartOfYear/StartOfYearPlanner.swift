import CryptoKit
import Foundation

/// Why one page goes into draft when a section is got ready for the start of
/// the year (#96).
nonisolated enum StartOfYearReason: Equatable {

    /// A class page after the first class (step 1, by position).
    case laterClass

    /// The earliest class that links to this page DIRECTLY is not the first
    /// class — the page is first used later (step 2). Carries that class's
    /// name as the teacher sees it.
    case firstUsedIn(String)

    /// Only pages students will not be able to see link to it (step 3).
    /// Carries one of them.
    case onlyHiddenPagesLinkToIt(String)

    /// Only a folder's own page lists it (step 3). Carries the folder.
    case onlyAFolderListsIt(String)

    /// Nothing links to it at all (step 3).
    case nothingLinksToIt

    // MARK: - Computed properties

    /// The contract's name for this reason, for the trail's counts and for a
    /// test to assert on without matching a sentence.
    var key: String {
        switch self {
        case .laterClass:
            return "laterClass"
        case .firstUsedIn:
            return "firstUsedLater"
        case .onlyHiddenPagesLinkToIt:
            return "onlyHiddenPagesLinkToIt"
        case .onlyAFolderListsIt:
            return "onlyAFolderListsIt"
        case .nothingLinksToIt:
            return "nothingLinksToIt"
        }
    }

    // MARK: - Functions

    /// The clause a teacher reads beside the page.
    func sentence(first: String) -> String {
        switch self {
        case .laterClass:
            return StartOfYearWording.reasonLaterClass(first: first)
        case .firstUsedIn(let page):
            return StartOfYearWording.reasonFirstUsedIn(page: page)
        case .onlyHiddenPagesLinkToIt(let page):
            return StartOfYearWording.reasonOnlyHiddenPagesLink(page: page)
        case .onlyAFolderListsIt(let folder):
            return StartOfYearWording.reasonOnlyAFolderLists(page: folder)
        case .nothingLinksToIt:
            return StartOfYearWording.reasonNothingLinks
        }
    }
}

/// One page the plan puts into draft, and why.
nonisolated struct StartOfYearDraft {

    // MARK: - Stored properties

    let page: AssistSectionPage
    let reason: StartOfYearReason
}

/// A page on which links will lead to hidden pages once the plan is applied,
/// and how many such links it carries.
nonisolated struct StartOfYearDanglingSource {

    // MARK: - Stored properties

    let page: AssistSectionPage
    let hiddenTargets: [String]
}

/// Why a section cannot be got ready.
enum StartOfYearProblem: Error, Equatable {
    case noFirstClass(course: String, section: Int, noun: ClassNoun)

    // MARK: - Computed properties

    var sentence: String {
        switch self {
        case .noFirstClass(let course, let section, let noun):
            return StartOfYearWording.noFirstClass(
                course: course, section: String(section), noun: noun.singular
            )
        }
    }

    var trailReason: String {
        switch self {
        case .noFirstClass:
            return "noFirstClass"
        }
    }
}

/// What getting one section ready for the start of the year would do, before
/// anything is done (#96).
///
/// Built once and read by both surfaces: the app's sheet shows it, and the
/// MCP plan tool describes it. The write re-plans from disk and compares
/// `fingerprint` with the one the teacher was shown, so what is written is
/// what was read or nothing at all.
struct StartOfYearPlan {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let noun: ClassNoun

    /// The first class by POSITION — never touched.
    let firstClass: AssistSectionPage

    /// Every page going into draft, classes first, each with its reason.
    let classDrafts: [StartOfYearDraft]
    let pageDrafts: [StartOfYearDraft]

    /// The write itself: `AssistPublishPlanner.planHiding` over exactly the
    /// pages above. Its `changes`, `alreadyRight` and `noRoomForAKey` are
    /// what will actually be written, already written, and declined.
    let publishPlan: AssistPublishPlan

    /// What stays, grouped: the pages the first class links to directly, and
    /// the pages Key Links lists (with Key Links itself).
    let firstClassPages: [AssistSectionPage]
    let keyLinksPages: [AssistSectionPage]

    /// Pages students will still see that will carry links to hidden pages,
    /// grouped by the page they are on.
    let danglingSources: [StartOfYearDanglingSource]

    /// Visible classes going into draft whose date is before today.
    let alreadyTaught: [AssistSectionPage]

    /// When this section's own scheduled deploy (in this working folder) will
    /// run, if one is set.
    let scheduledDeploy: Date?

    /// First 8 hex characters of a SHA-256 over what the plan would write.
    /// Guards staleness, not intent: it proves a write matches a plan that was
    /// MADE, never that a person read it.
    let fingerprint: String

    // MARK: - Computed properties

    var firstClassIsHidden: Bool {
        return !firstClass.isVisibleToStudents
    }

    /// The pages whose visibility will actually be written.
    var changeCount: Int {
        return publishPlan.changes.count
    }

    var changesNothing: Bool {
        return publishPlan.changes.isEmpty
    }

    /// Classes the plan names that are already in draft.
    var classesAlreadyInDraft: Int {
        var count: Int = 0
        for page in publishPlan.alreadyRight where page.isClassPage {
            count += 1
        }
        return count
    }

    /// How many of the changes are class pages, and how many are not.
    var classChangeCount: Int {
        var count: Int = 0
        for change in publishPlan.changes where change.page.isClassPage {
            count += 1
        }
        return count
    }

    var otherChangeCount: Int {
        return changeCount - classChangeCount
    }

    /// Counts of other pages going into draft by reason, for the trail line.
    var otherChangesByReason: [String: Int] {
        var changing: Set<String> = []
        for change in publishPlan.changes {
            changing.insert(change.page.fileURL.path)
        }
        var counts: [String: Int] = [:]
        for draft in pageDrafts where changing.contains(draft.page.fileURL.path) {
            counts[draft.reason.key, default: 0] += 1
        }
        return counts
    }

    // MARK: - Functions

    /// The sentences that must be read before Go, in the order they are shown.
    func warnings() -> [String] {
        var said: [String] = []
        if firstClassIsHidden {
            said.append(StartOfYearWording.firstClassIsHidden(
                first: firstClass.displayTitle, noun: noun.singular
            ))
        }
        if !alreadyTaught.isEmpty {
            said.append(StartOfYearWording.alreadyTaught(
                classes: StartOfYearWording.counted(alreadyTaught.count, noun: noun)
            ))
        }
        if let scheduledDeploy {
            said.append(StartOfYearWording.scheduledDeploy(
                moment: ScheduledDeploy.dayAndTimeText(scheduledDeploy)
            ))
        }
        return said
    }

    /// Whether this page is one the write will change.
    func willChange(_ page: AssistSectionPage) -> Bool {
        for change in publishPlan.changes where change.page.fileURL == page.fileURL {
            return true
        }
        return false
    }

    /// The whole plan in plain text, for an outside assistant to show a
    /// teacher. NOT truncated: a client agreeing to hide 170 pages must be
    /// able to see all 170. The plan code is on a line of its own, always in the
    /// same shape (`shared-rules.json` → `startOfYear.planCode.line`), so a
    /// client — or a test harness — finds it in one fixed place.
    func describe() -> String {
        let first: String = firstClass.displayTitle
        var lines: [String] = []
        lines.append("\(courseCode) Section \(sectionNumber): getting ready for the start of the year.")
        lines.append(StartOfYearWording.intro(first: first, noun: noun.singular, nouns: noun.plural))

        let warned: [String] = warnings()
        if !warned.isEmpty {
            lines.append("")
            for warning in warned {
                lines.append(warning)
            }
        }

        if changesNothing {
            lines.append("")
            lines.append(StartOfYearWording.nothingToDo(first: first, nouns: noun.plural))
        } else {
            let classChanges: [StartOfYearDraft] = draftsThatChange(classDrafts)
            if !classChanges.isEmpty {
                lines.append("")
                lines.append(StartOfYearWording.classesHeading(
                    classes: StartOfYearWording.counted(classChanges.count, noun: noun)
                ) + ":")
                for draft in classChanges {
                    lines.append("• “\(draft.page.displayTitle)” — \(draft.reason.sentence(first: first))")
                }
            }
            let pageChanges: [StartOfYearDraft] = draftsThatChange(pageDrafts)
            if !pageChanges.isEmpty {
                lines.append("")
                lines.append(StartOfYearWording.pagesHeading(
                    pages: StartOfYearWording.pages(pageChanges.count), nouns: noun.plural
                ) + ":")
                for draft in pageChanges {
                    lines.append("• “\(draft.page.displayTitle)” (\(draft.page.relativePath)) — "
                                 + draft.reason.sentence(first: first))
                }
            }
        }

        if classesAlreadyInDraft > 0 {
            lines.append("")
            lines.append(StartOfYearWording.alreadyInDraft(
                classes: StartOfYearWording.counted(classesAlreadyInDraft, noun: noun)
            ))
        }
        if !publishPlan.noRoomForAKey.isEmpty {
            lines.append("")
            lines.append(AssistPublishPlan.sayingPagesWithNoRoomForAKey(publishPlan.noRoomForAKey))
        }

        lines.append("")
        lines.append(StartOfYearWording.staysHeading(
            pages: StartOfYearWording.pages(1 + firstClassPages.count + keyLinksPages.count)
        ) + ":")
        lines.append("• " + StartOfYearWording.staysFirstClass(
            first: first, pages: StartOfYearWording.pages(firstClassPages.count)
        ))
        if !keyLinksPages.isEmpty {
            lines.append("• " + StartOfYearWording.staysKeyLinks(
                pages: StartOfYearWording.pages(max(0, keyLinksPages.count - 1))
            ))
        }
        lines.append("• " + StartOfYearWording.staysEverythingElse)

        if !danglingSources.isEmpty {
            lines.append("")
            lines.append(StartOfYearWording.linksLeftHeading)
            for source in danglingSources {
                let count: Int = source.hiddenTargets.count
                lines.append("• " + StartOfYearWording.linksLeftLine(
                    page: source.page.displayTitle,
                    links: count == 1 ? "1 link" : "\(count) links"
                ))
            }
        }

        lines.append("")
        lines.append(StartOfYearWording.publishingFromNowOn(noun: noun.singular))
        lines.append("")
        lines.append(StartOfYearPlanner.planCodeLine(fingerprint))
        return lines.joined(separator: "\n")
    }

    /// The drafts whose page the write will actually change, in order.
    func draftsThatChange(_ drafts: [StartOfYearDraft]) -> [StartOfYearDraft] {
        var changing: Set<String> = []
        for change in publishPlan.changes {
            changing.insert(change.page.fileURL.path)
        }
        var kept: [StartOfYearDraft] = []
        for draft in drafts where changing.contains(draft.page.fileURL.path) {
            kept.append(draft)
        }
        return kept
    }
}

/// The rule for getting a section ready for the start of the year (#96), in
/// one place: `shared-rules.json` → `startOfYear` is the same rule as data,
/// and both apps run its cases.
///
/// **Only ever HIDES, and never part of a rollover.** Russell, 2026-09-08
/// ("leave visibility alone … hiding stays a separate deliberate act") and
/// 2026-09-26: this is that separate act.
///
/// The rule, for one section:
///
/// * **The first class** is the first NUMBERED class by position
///   (`ClassInsertionPlanner.numberedClasses`), the one a rollover gives the
///   first date to. It is left exactly as it is, published or not.
/// * **Never touched:** the first class; the pages it links to directly (not
///   class pages); the Key Links page and every page it lists (not class
///   pages); every folder's own page; every curriculum page. A CLASS page is
///   never in this set except the first — step 1 wins (the plan review's M3).
/// * **Step 1, classes:** every other class page goes into draft.
/// * **Step 2, first used later:** every other page that any class links to
///   DIRECTLY goes into draft. The first class's links are already in the
///   never set, so "the earliest class that links it directly is not the
///   first class" is the same thing. **From links, never from stored dates**
///   (plan review H1): straight after a rollover a page's date comes from a
///   transitive walk, and reading it left 53 (SNC1W) to 79 (ICS3U) concepts
///   published.
/// * **Step 3, leftovers, to a fixed point:** every visible page outside the
///   never set that no page students will still see links to goes into draft.
///   A folder's own page listing it is a LISTING, not a use, and a page's
///   link to itself does not count — but the section's front page (its own
///   `index.md`) is what students land on, so ITS links do count.
/// * **Per section**, through the existing writer: a course-level page gets
///   `publishForSection<N>: false`, so other sections are untouched. Dates
///   and bodies are never changed.
enum StartOfYearPlanner {

    // MARK: - Functions

    /// The fixed line an outside assistant finds the plan code on.
    nonisolated static func planCodeLine(_ code: String) -> String {
        return "Plan code: \(code)"
    }

    /// The plan code on a plan's text, or nil — the reading a harness uses.
    nonisolated static func planCode(in text: String) -> String? {
        let prefix: String = planCodeLine("")
        for line in text.components(separatedBy: "\n") where line.hasPrefix(prefix) {
            let code: String = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !code.isEmpty {
                return code
            }
        }
        return nil
    }

    /// Work out what getting this section ready would do. Changes nothing.
    static func plan(
        forSection sectionNumber: Int,
        in course: Course,
        workspaceURL: URL?,
        today: CalendarDay,
        scheduledDeploy: Date? = nil
    ) -> Result<StartOfYearPlan, StartOfYearProblem> {
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: sectionNumber, in: course, workspaceURL: workspaceURL
        )
        let summaries: [ClassPageSummary] = ClassPages.list(forSection: sectionNumber, in: course)
        return plan(
            graph: graph, classSummaries: summaries, forSection: sectionNumber, in: course,
            today: today, scheduledDeploy: scheduledDeploy
        )
    }

    /// The same, from a graph already read.
    static func plan(
        graph: AssistSectionGraph,
        classSummaries: [ClassPageSummary],
        forSection sectionNumber: Int,
        in course: Course,
        today: CalendarDay,
        scheduledDeploy: Date? = nil
    ) -> Result<StartOfYearPlan, StartOfYearProblem> {
        let noun: ClassNoun = course.configuration.classNoun

        // The class pages, in POSITION order: numbered ones by unit and day,
        // then any other class page in path order.
        let numbered: [ClassPageSummary] = ClassInsertionPlanner.numberedClasses(among: classSummaries)
        var classesInOrder: [AssistSectionPage] = []
        var placed: Set<String> = []
        for summary in numbered {
            guard let page = pageAt(summary.fileURL, in: graph), page.isClassPage else {
                continue
            }
            if placed.contains(page.fileURL.path) {
                continue
            }
            placed.insert(page.fileURL.path)
            classesInOrder.append(page)
        }
        guard let firstClass = classesInOrder.first else {
            return .failure(.noFirstClass(course: course.code, section: sectionNumber, noun: noun))
        }
        for page in graph.pages where page.isClassPage && !placed.contains(page.fileURL.path) {
            placed.insert(page.fileURL.path)
            classesInOrder.append(page)
        }

        // The never set, by path.
        var never: Set<String> = [firstClass.fileURL.path]
        var firstClassPages: [AssistSectionPage] = []
        for target in firstClass.linkedTitles {
            guard let linked = graph.page(titled: target), !linked.isClassPage else {
                continue
            }
            if linked.fileURL == firstClass.fileURL || never.contains(linked.fileURL.path) {
                continue
            }
            never.insert(linked.fileURL.path)
            firstClassPages.append(linked)
        }
        var keyLinksPages: [AssistSectionPage] = []
        let keyLinkTitles: Set<String> = AssistPublishPlanner.pagesThisSectionCannotDoWithout(graph: graph)
        for page in graph.pages where keyLinkTitles.contains(page.lowercasedTitle) && !page.isClassPage {
            // Only the page a link resolves to — the first of two same-named
            // files — as everywhere else in the graph.
            guard let resolved = graph.page(titled: page.title), resolved.fileURL == page.fileURL else {
                continue
            }
            if !never.contains(page.fileURL.path) {
                keyLinksPages.append(page)
            }
            never.insert(page.fileURL.path)
        }
        for page in graph.pages {
            if page.isFolderIndex || AssistCurriculumMentions.isCurriculum(pageAt: page.fileURL, in: course) {
                never.insert(page.fileURL.path)
            }
        }

        var going: Set<String> = []
        var classDrafts: [StartOfYearDraft] = []
        var pageDrafts: [StartOfYearDraft] = []

        // Step 1: every class after the first, by position.
        for page in classesInOrder where page.fileURL != firstClass.fileURL {
            going.insert(page.fileURL.path)
            classDrafts.append(StartOfYearDraft(page: page, reason: .laterClass))
        }

        // Step 2: every page a later class links to directly. Classes are
        // walked in position order, so the reason names the EARLIEST.
        for classPage in classesInOrder where classPage.fileURL != firstClass.fileURL {
            for target in classPage.linkedTitles {
                guard let linked = graph.page(titled: target) else {
                    continue
                }
                if linked.isClassPage || never.contains(linked.fileURL.path) {
                    continue
                }
                if going.contains(linked.fileURL.path) || !linked.isVisibleToStudents {
                    continue
                }
                going.insert(linked.fileURL.path)
                pageDrafts.append(StartOfYearDraft(
                    page: linked, reason: .firstUsedIn(classPage.displayTitle)
                ))
            }
        }

        // Step 3: leftovers, to a fixed point. Monotone — it only ever adds
        // to `going` — over a finite set, so it ends, and which pages it
        // takes does not depend on the order it looks at them.
        let frontPage: URL = SectionIndexPointer.indexURL(forSection: sectionNumber, in: course)
            .standardizedFileURL
        let referrers: [String: [AssistSectionPage]] = pagesLinkingIn(graph)
        var foundMore: Bool = true
        while foundMore {
            foundMore = false
            for page in graph.pages {
                if !page.isVisibleToStudents || page.isClassPage {
                    continue
                }
                if never.contains(page.fileURL.path) || going.contains(page.fileURL.path) {
                    continue
                }
                guard let resolved = graph.page(titled: page.title), resolved.fileURL == page.fileURL else {
                    // A second file sharing a name no link can reach: nothing
                    // links to it, whatever the links say (R4).
                    going.insert(page.fileURL.path)
                    pageDrafts.append(StartOfYearDraft(page: page, reason: .nothingLinksToIt))
                    foundMore = true
                    continue
                }
                var aHiddenReferrer: String? = nil
                var aListingFolder: String? = nil
                var stillUsed: Bool = false
                for referrer in referrers[page.lowercasedTitle] ?? [] {
                    let isFrontPage: Bool = referrer.fileURL.standardizedFileURL == frontPage
                    let willBeSeen: Bool = referrer.isVisibleToStudents
                        && !going.contains(referrer.fileURL.path)
                    if referrer.isFolderIndex && !isFrontPage {
                        if aListingFolder == nil {
                            aListingFolder = referrer.fileURL.deletingLastPathComponent().lastPathComponent
                        }
                        continue
                    }
                    if willBeSeen {
                        stillUsed = true
                        break
                    }
                    if aHiddenReferrer == nil {
                        aHiddenReferrer = referrer.displayTitle
                    }
                }
                if stillUsed {
                    continue
                }
                let reason: StartOfYearReason
                if let aHiddenReferrer {
                    reason = .onlyHiddenPagesLinkToIt(aHiddenReferrer)
                } else if let aListingFolder {
                    reason = .onlyAFolderListsIt(aListingFolder)
                } else {
                    reason = .nothingLinksToIt
                }
                going.insert(page.fileURL.path)
                pageDrafts.append(StartOfYearDraft(page: page, reason: reason))
                foundMore = true
            }
        }

        // The write: exactly these pages, no sweep.
        var toHide: [AssistSectionPage] = []
        for draft in classDrafts {
            toHide.append(draft.page)
        }
        for draft in pageDrafts {
            toHide.append(draft.page)
        }
        let publishPlan: AssistPublishPlan = AssistPublishPlanner.planHiding(
            exactly: toHide, forSection: sectionNumber, in: course
        )

        // Links on staying, visible pages that will lead to hidden pages.
        var danglingSources: [StartOfYearDanglingSource] = []
        for page in graph.pages {
            if !page.isVisibleToStudents || going.contains(page.fileURL.path) {
                continue
            }
            var hiddenTargets: [String] = []
            for target in page.linkedTitles {
                guard let linked = graph.page(titled: target), linked.fileURL != page.fileURL else {
                    continue
                }
                if !linked.isVisibleToStudents || going.contains(linked.fileURL.path) {
                    hiddenTargets.append(linked.displayTitle)
                }
            }
            if !hiddenTargets.isEmpty {
                danglingSources.append(StartOfYearDanglingSource(page: page, hiddenTargets: hiddenTargets))
            }
        }
        danglingSources.sort { first, second in
            if first.hiddenTargets.count != second.hiddenTargets.count {
                return first.hiddenTargets.count > second.hiddenTargets.count
            }
            return first.page.relativePath < second.page.relativePath
        }

        var alreadyTaught: [AssistSectionPage] = []
        for draft in classDrafts where draft.page.isVisibleToStudents {
            if let date = draft.page.date, date < today {
                alreadyTaught.append(draft.page)
            }
        }

        return .success(StartOfYearPlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            noun: noun,
            firstClass: firstClass,
            classDrafts: classDrafts,
            pageDrafts: pageDrafts,
            publishPlan: publishPlan,
            firstClassPages: firstClassPages,
            keyLinksPages: keyLinksPages,
            danglingSources: danglingSources,
            alreadyTaught: alreadyTaught,
            scheduledDeploy: scheduledDeploy,
            fingerprint: fingerprint(
                course: course.code, section: sectionNumber,
                first: firstClass.title, changes: publishPlan.changes
            )
        ))
    }

    /// First 8 hex characters of a SHA-256 over the course, the section, the
    /// first class and each change's path and new visibility, sorted.
    ///
    /// The contract says what it GUARDS, not how it is made: each platform
    /// issues its own and only checks its own.
    nonisolated static func fingerprint(
        course: String, section: Int, first: String, changes: [AssistPublishChange]
    ) -> String {
        var lines: [String] = []
        for change in changes {
            lines.append(change.page.relativePath + "|" + (change.willBeVisible ? "visible" : "hidden"))
        }
        lines.sort()
        let text: String = ([course, String(section), first] + lines).joined(separator: "\n")
        let digest: SHA256.Digest = SHA256.hash(data: Data(text.utf8))
        var hex: String = ""
        for byte in digest {
            hex += String(format: "%02x", byte)
        }
        return String(hex.prefix(8))
    }

    /// Write the plan: every change it lists, through the existing writer.
    ///
    /// One step past `AssistPublishPlanner.apply`, and it is the plan's M10:
    /// a SECTION-LOCAL page (a class) carrying a stray `publishForSection<N>:
    /// true` is still published after `publish: false` is written, because
    /// the build reads the per-section key first. So any such page that the
    /// reader still calls visible has that key set to false as well — the
    /// answer asked of the BUILT SITE's reader, not assumed.
    static func apply(
        _ plan: StartOfYearPlan,
        in course: Course
    ) throws -> (change: AssistChange, leftAlone: [String]) {
        let applied: (change: AssistChange, leftAlone: [String]) = try AssistPublishPlanner.apply(
            plan.publishPlan, forSection: plan.sectionNumber, in: course
        )
        var files: [AssistSavedFile] = applied.change.files
        for planned in plan.publishPlan.changes {
            let url: URL = planned.page.fileURL
            guard let current = try? String(contentsOf: url, encoding: .utf8),
                  PageVisibilityReader.answer(in: current, forSection: plan.sectionNumber) != .hidden else {
                continue
            }
            let fixed: (text: String, outcome: FrontmatterWriteOutcome) = AssistPageVisibility.setting(
                published: false, in: current, forSection: plan.sectionNumber, isSectionLocal: false
            )
            if fixed.outcome != .written || fixed.text == current {
                continue
            }
            try fixed.text.write(to: url, atomically: true, encoding: .utf8)
            // The undo must put back the file as it was BEFORE either write,
            // and must know the file as it is now.
            var replaced: Bool = false
            var index: Int = 0
            while index < files.count {
                if files[index].fileURL.path == url.path {
                    files[index] = AssistSavedFile(fileURL: url, before: files[index].before, after: fixed.text)
                    replaced = true
                }
                index += 1
            }
            if !replaced {
                files.append(AssistSavedFile(fileURL: url, before: current, after: fixed.text))
            }
        }
        let change: AssistChange = AssistChange(
            whatHappened: "got Section \(plan.sectionNumber) ready for the start of the year",
            courseCode: plan.courseCode,
            sectionNumber: plan.sectionNumber,
            rebuildsThePreview: true,
            files: files,
            kind: .startOfYear
        )
        return (change: change, leftAlone: applied.leftAlone)
    }

    // MARK: - Private helpers

    private static func pageAt(_ url: URL, in graph: AssistSectionGraph) -> AssistSectionPage? {
        let wanted: String = url.standardizedFileURL.path
        for page in graph.pages where page.fileURL.standardizedFileURL.path == wanted {
            return page
        }
        return nil
    }

    /// Which pages link to each page, by lowercased title, leaving out a
    /// page's link to itself and counting each referring FILE once.
    private static func pagesLinkingIn(_ graph: AssistSectionGraph) -> [String: [AssistSectionPage]] {
        var referrers: [String: [AssistSectionPage]] = [:]
        for page in graph.pages {
            for target in page.linkedTitles {
                if target == page.lowercasedTitle {
                    continue
                }
                var linking: [AssistSectionPage] = referrers[target] ?? []
                var already: Bool = false
                for existing in linking where existing.fileURL == page.fileURL {
                    already = true
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
}
