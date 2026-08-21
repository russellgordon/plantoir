import AppKit
import Foundation
import Observation

/// The twenty tools that exist — thirteen of them shown to the local model —
/// and what running one does.
///
/// Four rules shape this surface. They are inherited from the Windows work
/// rather than rediscovered, and every one of them is measured:
///
/// 1. **Nothing destructive exists.** No delete, no rename, no archive. In
///    testing the model reliably declined "delete the Unit 1 folder" — not from
///    judgement, but because it had no tool for it. Absence is the strongest
///    guardrail available, so it is the one relied on.
///
/// 2. **Publishing and unpublishing are separate tools, not a flag.** The one
///    genuinely dangerous failure ever observed was polarity inversion: asked
///    to HIDE a page, the model called publish with "include everything it
///    links to" set. A boolean is a coin flip under pressure; a verb is not. So
///    the verb is in the tool NAME, it is fixed at the point the tool is
///    routed, and it is carried by the plan all the way to the write — there is
///    no argument anywhere on this surface that could invert it. That boolean
///    is gone entirely now: how far each verb reaches is `AssistPublishPlanner`'s
///    rule, and no tool anywhere takes a boolean.
///
/// 3. **Every write that changes a page has a matching `plan_` tool that
///    changes nothing**, and the plan is written to be read aloud.
///
/// 4. **The coarse tools resolve their own links.** Given `resolve_links`,
///    `set_publish` and `publish_section` separately and asked to publish
///    tomorrow's class and everything it links to, the model chose
///    `publish_section` 8 times out of 8 — consistent, and wrong. Given one
///    `publish_class_on` that follows the links itself, it was right 8 out of
///    8.
///
/// Approval is declared by the tool, not kept in a list here. Only deploying
/// asks for a button: publishing is backed up and `undo_last_change` takes it
/// back, and a gate in front of every write teaches a teacher to click through
/// gates, which is worse than having no gate at all.
///
/// Observable for one property's sake: `conversationBackupURL` appears part way
/// through a conversation, the moment the first write saves a copy, and the
/// window's Restore banner has to appear with it rather than at whatever redraw
/// happens along next.
@Observable
@MainActor
final class AssistToolRunner {

    // MARK: - Stored properties

    /// Where the courses are.
    private let workspace: WorkspaceModel

    /// Building a preview and putting a site on the web.
    private let siteWork: AssistSiteWork

    /// What this conversation has changed, so `undo_last_change` can take it
    /// back.
    private let history: AssistChangeHistory = AssistChangeHistory()

    /// The day "tomorrow" is counted from. Injectable so a test is not a
    /// different test depending on when it runs.
    private let today: CalendarDay

    /// How a scheduled deploy reaches launchd. Injectable for the same reason
    /// the app's own schedule sheet injects it: a test that really bootstrapped
    /// an agent would leave one on the machine running the suite.
    private let launchControl: LaunchControlRunning

    /// Opens a new "Plantoir" window — present ONLY for the local in-app
    /// assistant (threaded in from `AssistWindowView`'s own `@Environment
    /// (\.openWindow)`), nil for every other caller.
    ///
    /// MCP (`Plantoir --mcp-stdio`) never constructs a Scene graph at all —
    /// `openWindow` would have nothing to act on — and a scheduled deploy
    /// runs with the app closed. Both keep the old silent fallback. Only
    /// the local assistant can make good on "do the same thing as pressing
    /// the Deploy button", because it alone is running inside a real,
    /// on-screen app session.
    private let openMainWindow: (@MainActor () -> Void)?

    /// The backup this conversation has already made of each course it has
    /// changed, by course code.
    ///
    /// One runner is built per assistant window, so this is per-conversation
    /// state — and that is the whole point: a course full of images makes a
    /// slow, fat zip, and a chat with six commands in it used to make six
    /// near-identical ones. The first write of a conversation saves a copy;
    /// every later write in the same conversation is covered by that copy and
    /// the undo history, so it makes none. A conversation that only reads
    /// makes none at all.
    private var conversationBackups: [String: URL] = [:]

    /// The most recent backup this conversation made, for a window that wants
    /// to offer the teacher a way back to where the chat started. Nil until
    /// the conversation changes something.
    private(set) var conversationBackupURL: URL?

    // MARK: - Computed properties

    /// Whether this conversation has saved a copy to go back to yet.
    var hasConversationBackup: Bool {
        return conversationBackupURL != nil
    }

    /// The tools, as the LOCAL model sees them.
    ///
    /// Thirteen of the twenty that exist. A small local model routes worse the
    /// more it is shown, so anything it never has to NAME is kept off the list:
    /// the six `plan_` twins, which plan mode calls in code, and
    /// `remember_timetable`, whose dates must come from a teacher rather than
    /// from a model. All of them still run when they are called.
    var definitions: [AssistToolDefinition] {
        return AssistToolRunner.localTools
    }

    /// The tools the MCP client sees: everything that exists, plus the ones
    /// that ask for judgement a small local model has no business making.
    var mcpDefinitions: [AssistToolDefinition] {
        return AssistToolRunner.mcpTools
    }

    // MARK: - Initializer

    init(workspace: WorkspaceModel,
         siteWork: AssistSiteWork? = nil,
         today: CalendarDay = CalendarDay.today(),
         launchControl: LaunchControlRunning = LaunchControl(),
         openMainWindow: (@MainActor () -> Void)? = nil) {
        self.workspace = workspace
        self.siteWork = siteWork ?? AssistToolchainWork(workspace: workspace)
        self.today = today
        self.launchControl = launchControl
        self.openMainWindow = openMainWindow
    }

    // MARK: - Functions

    /// The tool by that name, or nil when there is none.
    ///
    /// Looks through everything either client may call, because `run(call:)`
    /// runs everything either client may call — and the approval gate reads
    /// `needsApproval` off whatever this hands back. A name that does not look
    /// up is a write that never meets its gate.
    func definition(named name: String) -> AssistToolDefinition? {
        for tool in AssistToolRunner.mcpTools where tool.name == name {
            return tool
        }
        return nil
    }

    /// What pressing the button would do, for the two acts that ask for one.
    ///
    /// Said in the teacher's terms and naming the real destination: "publishes
    /// to the folder you chose" tells a teacher with two courses nothing at
    /// all.
    func explain(call: AssistToolCall) -> String {
        let arguments: [String: Any] = call.argumentValues
        let code: String = text("course", in: arguments)
        let number: Int = number("section", in: arguments) ?? 0

        var destination: String = "the web"
        for course in workspace.courses where course.code.lowercased() == code.lowercased() {
            destination = AssistToolRunner.destination(of: course)
        }

        switch call.function.name {
        case "deploy_section":
            // Two sentences, and neither of them restates the request.
            //
            // This has been cut twice. It began as a label with two paragraphs
            // of warning stapled to it — "the one thing that changes what
            // students see, and Plantoir cannot take it back for you" — which
            // announces a limitation of the app to somebody who has already
            // decided, and second-guesses their order of work. It then became
            // "OK, I'll deploy CIA4U Section 3 to Netlify." plus the same two
            // sentences, which read oddly against the "Shall I deploy?" that
            // the agent says next: agreeing to do a thing and then asking
            // permission for it.
            //
            // So what is left is the fact and the advice. The act itself is
            // named by the question that follows this, and the section is on
            // the window's own title bar.
            //
            // `code`, `number` and `destination` are deliberately unused here.
            // Leave them: `schedule_deploy` below needs all three, and the one
            // thing this text must never become is a description of a tool.
            return AssistWording.deployApproval
        case "schedule_deploy":
            let raw: String = text("when", in: arguments)
            let when: String = AssistToolRunner.moment(named: raw)
                .map { moment in ScheduledDeploy.dayAndTimeText(moment) } ?? raw
            return "Set this Mac to deploy \(code) Section \(number) to \(destination) at \(when). "
                 + "It has to be on and awake then — plugged in if it is a laptop, lid open. "
                 + "Plantoir cannot wake it up."
        default:
            return "Run \(call.function.name)."
        }
    }

    /// Run one tool.
    func run(call: AssistToolCall) async -> AssistToolOutcome {
        let arguments: [String: Any] = call.argumentValues
        switch call.function.name {
        case "list_pages":
            return listPages(arguments)
        case "read_page":
            return readPage(arguments)
        case "check_section":
            return checkSection(arguments)
        case "plan_publish_class_on":
            return planPublishClassOn(arguments)
        case "publish_class_on":
            return await publishClassOn(arguments)
        case "plan_publish_pages":
            return planPublishPages(arguments)
        case "publish_pages":
            return await publishPages(arguments)
        case "plan_unpublish_pages":
            return planUnpublishPages(arguments)
        case "unpublish_pages":
            return await unpublishPages(arguments)
        case "rebuild_preview":
            return await rebuildPreview(arguments)
        case "undo_last_change":
            return await undoLastChange()
        case "deploy_section":
            return await deploySection(arguments)
        case "plan_scheduled_deploy":
            return planScheduledDeploy(arguments)
        case "schedule_deploy":
            return scheduleDeploy(arguments)
        case "cancel_scheduled_deploy":
            return cancelScheduledDeploy(arguments)
        case "read_remembered_timetable":
            return readRememberedTimetable(arguments)
        case "plan_remember_timetable":
            return planRememberTimetable(arguments)
        case "remember_timetable":
            return rememberTimetable(arguments)
        case "plan_add_next_class":
            return planAddNextClass(arguments)
        case "plan_re_date_classes":
            return planReDateClasses(arguments)
        case "re_date_classes":
            return await reDateClasses(arguments)
        case "add_next_class":
            return addNextClass(arguments)
        case "list_curriculum_expectations":
            return listCurriculumExpectations(arguments)
        case "plan_curriculum_mentions":
            return planCurriculumMentions(arguments)
        case "add_curriculum_mentions":
            return addCurriculumMentions(arguments)
        default:
            return AssistToolOutcome.couldNotRead(
                "There is no tool called “\(call.function.name)”."
            )
        }
    }

    // MARK: - Looking around

    private func listPages(_ arguments: [String: Any]) -> AssistToolOutcome {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.couldNotRead(refusal(from: found).message)
        }

        let filter: String = text("matching", in: arguments).trimmingCharacters(in: .whitespaces)
        var paths: [String] = []
        for pageURL in ClassPages.pagesOfSection(located.sectionNumber, in: located.course) {
            let path: String = AssistSectionGraph.relativePath(
                of: pageURL, workspaceURL: workspace.workspaceURL
            )
            if filter.isEmpty || path.localizedCaseInsensitiveContains(filter) {
                paths.append(path)
            }
        }

        let where_: String = "\(located.course.code) Section \(located.sectionNumber)"
        if paths.isEmpty {
            let reason: String = filter.isEmpty
                ? "\(where_) has no pages."
                : "No page in \(where_) matches “\(filter)”."
            return AssistToolOutcome.read("Nothing matched in \(where_).", detail: reason)
        }

        var listed: [String] = []
        for path in paths {
            if listed.count == AssistToolRunner.mostPagesListed {
                break
            }
            listed.append(path)
        }
        var detail: String = listed.joined(separator: "\n")
        if paths.count > listed.count {
            detail += "\n\n…and \(paths.count - listed.count) more of \(paths.count). "
                    + "Pass `matching` to narrow this down."
        }

        let word: String = paths.count == 1 ? "page" : "pages"
        return AssistToolOutcome.read("Found \(paths.count) \(word) in \(where_).", detail: detail)
    }

    private func readPage(_ arguments: [String: Any]) -> AssistToolOutcome {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.couldNotRead(refusal(from: found).message)
        }

        let title: String = text("page", in: arguments)
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: located.sectionNumber, in: located.course,
            workspaceURL: workspace.workspaceURL
        )
        guard let page = graph.page(titled: title) else {
            return AssistToolOutcome.couldNotRead(AssistToolRefusal.noSuchPage(
                title, located.course.code, located.sectionNumber
            ).message)
        }
        guard var body = try? String(contentsOf: page.fileURL, encoding: .utf8) else {
            return AssistToolOutcome.couldNotRead("“\(page.displayTitle)” could not be read.")
        }

        // A whole course does not fit in a small model's context, and a page
        // truncated with a note is far better than a question answered from
        // the half of the page that happened to fit.
        if body.count > AssistToolRunner.mostCharactersRead {
            body = String(body.prefix(AssistToolRunner.mostCharactersRead))
                 + "\n\n…the rest of this page was left out; it is longer than the assistant can read at once."
        }

        return AssistToolOutcome.read(
            "Read “\(page.displayTitle)”.",
            detail: "\(page.relativePath)\n\n\(body)"
        )
    }

    private func checkSection(_ arguments: [String: Any]) -> AssistToolOutcome {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.couldNotRead(refusal(from: found).message)
        }

        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: located.sectionNumber, in: located.course,
            workspaceURL: workspace.workspaceURL
        )
        let dangling: [AssistSectionLink] = graph.linksIntoHiddenPages()
        let orphans: [AssistSectionPage] = graph.visiblePagesNothingLinksTo()

        let visible: Int = graph.visiblePageCount
        let pageWord: String = visible == 1 ? "page" : "pages"
        var paragraphs: [String] = []
        paragraphs.append("Students would see \(visible) \(pageWord) in "
                          + "\(located.course.code) Section \(located.sectionNumber).")

        if dangling.isEmpty {
            paragraphs.append("None of the visible pages link to unpublished pages, ensuring "
                              + "that all links are functional and point to published content.")
        } else {
            var lines: [String] = []
            let word: String = dangling.count == 1 ? "link" : "links"
            lines.append("\(dangling.count) \(word) would take a student to a page that isn't there:")
            var listed: Int = 0
            for link in dangling {
                if listed == AssistToolRunner.mostListed {
                    lines.append("…and \(dangling.count - listed) more.")
                    break
                }
                lines.append("• \(link.fromRelativePath)  →  \(link.toTitle)  (hidden)")
                listed += 1
            }
            lines.append("Either publish the page each one points at, or take the link off "
                         + "the page that points at it.")
            paragraphs.append(lines.joined(separator: "\n"))
        }

        // Silence when nothing is stranded: the teacher asked what students
        // would see, and "every page is linked from somewhere" is only an
        // answer when it is bad news.
        if !orphans.isEmpty {
            var lines: [String] = []
            let word: String = orphans.count == 1 ? "page is" : "pages are"
            lines.append("\(orphans.count) visible \(word) linked from nowhere. Students can still "
                         + "reach these through the site's explorer, and no publish or hide rule "
                         + "that follows links will ever touch them:")
            var listed: Int = 0
            for page in orphans {
                if listed == AssistToolRunner.mostListed {
                    lines.append("…and \(orphans.count - listed) more.")
                    break
                }
                lines.append("• " + page.relativePath)
                listed += 1
            }
            paragraphs.append(lines.joined(separator: "\n"))
        }

        // What the preview is doing decides which of three things is worth
        // saying — and for one of them, that nothing is.
        //
        // This used to be one sentence behind one boolean, and the boolean was
        // "is the launcher running", which stays true for as long as the site
        // is SERVED. So a teacher looking at a finished preview was told their
        // pages would appear "once any rebuild in progress finishes", about a
        // rebuild that had finished minutes ago.
        let these: String = visible == 1 ? "this page" : "these \(visible) pages"
        let window = sectionWindow(for: located.course, sectionNumber: located.sectionNumber)
        switch window?.previewState() ?? .notRunning {
        case .building:
            paragraphs.append("The preview is building now, and will show \(these) when it finishes.")
        case .showing:
            // Nothing. They are looking at it.
            break
        case .notRunning:
            paragraphs.append("Nothing is being previewed at the moment. Say “Preview” if you "
                              + "would like to look the section over.")
        }

        let answer: String = paragraphs.joined(separator: "\n\n")

        // The whole answer, once, and the turn is over. This used to be a
        // read — a terse count for the transcript, a "Show me" disclosure
        // with the specifics, and then the model's own paraphrase of the same
        // facts as a second bubble. Three renderings of one answer, and the
        // only one a teacher actually read was the model's — which, being a
        // paraphrase, was also the only one that could get the facts wrong.
        // The answer is deterministic, so it is composed here and shown
        // as-is; a model lap after it could only restate it.
        return AssistToolOutcome(summary: answer, detail: answer, shouldContinue: false)
    }

    // MARK: - The commonest request of all

    private func planPublishClassOn(_ arguments: [String: Any]) -> AssistToolOutcome {
        switch classPlan(arguments) {
        case .failure(let refusal):
            return AssistToolOutcome.couldNotRead(refusal.message)
        case .success(let planned):
            return AssistToolOutcome.planned(
                "Worked out what publishing the class on \(planned.day.text) would do.",
                plan: planned.plan.describe()
            )
        }
    }

    private func publishClassOn(_ arguments: [String: Any]) async -> AssistToolOutcome {
        switch classPlan(arguments) {
        case .failure(let refusal):
            // "No class on that day" CAN mean the dates were never given. When
            // it does, the way forward is the sheet, not a better sentence.
            if case .noClassOn(_, let code, let number) = refusal,
               let course = course(withCode: code),
               hasNoTimetable(forSection: number, in: course) {
                askForTheTimetable(
                    courseCode: code, sectionNumber: number,
                    because: "Finding the class taught on a given day needs to know which days "
                           + "this section meets."
                )
            }
            return AssistToolOutcome.refused(refusal.message)
        case .success(let planned):
            return await carryOut(
                planned.plan,
                forSection: planned.located.sectionNumber,
                in: planned.located.course,
                summary: "Published the class on \(planned.day.text)."
            )
        }
    }

    /// A located class plan: everything the two halves of "publish tomorrow's
    /// class" both need.
    private struct PlannedClass {
        let located: Located
        let day: CalendarDay
        let plan: AssistPublishPlan
    }

    private func classPlan(_ arguments: [String: Any]) -> Result<PlannedClass, AssistToolRefusal> {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return .failure(refusal(from: found))
        }

        // `date` is what the schema asks for. `when` is what the assistant
        // window's fixed phrasings send — "publish tomorrow's class" never
        // reaches the model at all, so the word "tomorrow" arrives here
        // literally and has to be understood here.
        var raw: String = text("date", in: arguments)
        if raw.isEmpty {
            raw = text("when", in: arguments)
        }
        guard let day = AssistToolRunner.day(named: raw, today: today) else {
            return .failure(.unreadableDate(raw, "date"))
        }

        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: located.sectionNumber, in: located.course,
            workspaceURL: workspace.workspaceURL
        )
        let classPages: [ClassPageSummary] = ClassPages.list(
            forSection: located.sectionNumber, in: located.course
        )
        let planned = AssistPublishPlanner.planPublishingClass(
            on: day, graph: graph, classPages: classPages,
            forSection: located.sectionNumber, in: located.course
        )
        switch planned {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(let plan):
            return .success(PlannedClass(located: located, day: day, plan: plan))
        }
    }

    // MARK: - Publishing and unpublishing, which are two different verbs

    private func planPublishPages(_ arguments: [String: Any]) -> AssistToolOutcome {
        if let whole = wholeUnitPlan(arguments, publishing: true) {
            return whole
        }
        switch pagePlan(arguments, publishing: true) {
        case .failure(let refusal):
            return AssistToolOutcome.couldNotRead(refusal.message)
        case .success(let planned):
            // Nothing to agree to. A plan card asking "Shall I go ahead?"
            // about a page that is already published makes a teacher approve
            // a no-op, and then tells them nothing happened.
            if let already = planned.plan.nothingToDoSentence {
                return AssistToolOutcome.wrote(already, detail: already)
            }
            return AssistToolOutcome.planned(
                "Worked out what publishing those pages would do.",
                plan: planned.plan.describe()
            )
        }
    }

    private func publishPages(_ arguments: [String: Any]) async -> AssistToolOutcome {
        if let whole = await wholeUnitRequested(arguments, publishing: true) {
            return whole
        }
        switch pagePlan(arguments, publishing: true) {
        case .failure(let refusal):
            return AssistToolOutcome.refused(refusal.message)
        case .success(let planned):
            return await carryOut(
                planned.plan,
                forSection: planned.located.sectionNumber,
                in: planned.located.course,
                summary: "Published \(planned.plan.changes.count) "
                       + "\(planned.plan.changes.count == 1 ? "page" : "pages")."
            )
        }
    }

    private func planUnpublishPages(_ arguments: [String: Any]) -> AssistToolOutcome {
        if let whole = wholeUnitPlan(arguments, publishing: false) {
            return whole
        }
        switch pagePlan(arguments, publishing: false) {
        case .failure(let refusal):
            return AssistToolOutcome.couldNotRead(refusal.message)
        case .success(let planned):
            if let already = planned.plan.nothingToDoSentence {
                return AssistToolOutcome.wrote(already, detail: already)
            }
            return AssistToolOutcome.planned(
                "Worked out what unpublishing those pages would do.",
                plan: planned.plan.describe()
            )
        }
    }

    private func unpublishPages(_ arguments: [String: Any]) async -> AssistToolOutcome {
        if let whole = await wholeUnitRequested(arguments, publishing: false) {
            return whole
        }
        switch pagePlan(arguments, publishing: false) {
        case .failure(let refusal):
            return AssistToolOutcome.refused(refusal.message)
        case .success(let planned):
            return await carryOut(
                planned.plan,
                forSection: planned.located.sectionNumber,
                in: planned.located.course,
                summary: "Unpublished \(planned.plan.changes.count) "
                       + "\(planned.plan.changes.count == 1 ? "page" : "pages")."
            )
        }
    }

    private struct PlannedPages {
        let located: Located
        let plan: AssistPublishPlan
    }

    /// The shared reading of the arguments.
    ///
    /// `publishing` arrives from the CALLER — one of exactly four private
    /// functions above, each of which writes it down literally. It is never
    /// read out of the model's arguments, because that is the one place the
    /// polarity could be inverted.
    /// The card a teacher agrees to before a whole unit moves.
    ///
    /// Needed because plan mode runs the `plan_` twin with the SAME arguments,
    /// and "Unit 4" is not a page — without this the teacher would be told no
    /// page is called that, and the thing they asked for would look broken
    /// rather than pending.
    private func wholeUnitPlan(
        _ arguments: [String: Any],
        publishing: Bool
    ) -> AssistToolOutcome? {
        let titles: [String] = names("pages", in: arguments)
        guard titles.count == 1, let unit = AssistPublishPlanner.unitNamed(titles[0]) else {
            return nil
        }
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.couldNotRead(refusal(from: found).message)
        }

        let all: [ClassPageSummary] = ClassPages.list(
            forSection: located.sectionNumber, in: located.course
        )
        let pages: [ClassPageSummary] = AssistPublishPlanner.classPages(inUnit: unit, from: all)
        if pages.isEmpty {
            return AssistToolOutcome.couldNotRead(
                "I can't find any class pages in Unit \(unit) of \(located.course.code) "
                + "Section \(located.sectionNumber)."
            )
        }

        // Only the ones that would actually move.
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: located.sectionNumber, in: located.course,
            workspaceURL: workspace.workspaceURL
        )
        var moving: [String] = []
        for summary in pages {
            guard let page = graph.page(titled: summary.title) else {
                continue
            }
            if page.isVisibleToStudents != publishing {
                moving.append(page.displayTitle)
            }
        }
        if moving.isEmpty {
            let already: String = publishing
                ? "Unit \(unit) has already been published."
                : "Unit \(unit) is already hidden."
            return AssistToolOutcome.wrote(already, detail: already)
        }

        let word: String = moving.count == 1 ? "class" : "classes"
        let becoming: String = publishing ? "visible" : "hidden"
        var lines: [String] = []
        lines.append("\(located.course.code) Section \(located.sectionNumber): "
                     + "\(publishing ? "publishing" : "unpublishing") Unit \(unit).")
        lines.append("")
        lines.append("\(moving.count) \(word) would become \(becoming), "
                     + "\(publishing ? "starting at" : "starting from") "
                     + "“\(publishing ? moving[moving.count - 1] : moving[0])”.")
        if publishing {
            lines.append("Everything they link to becomes visible with them.")
        } else {
            lines.append("Pages only they use come down too; anything still needed stays.")
        }

        return AssistToolOutcome.planned(
            "Worked out what \(publishing ? "publishing" : "unpublishing") Unit \(unit) would do.",
            plan: lines.joined(separator: "\n")
        )
    }

    /// "Publish Unit 5" and "Unpublish Unit 4": a whole unit, one class page
    /// at a time, reported as one thing. Nil when a unit was not what was
    /// asked for, so every other request falls straight through.
    ///
    /// **One page at a time, in order, rather than one plan over all of
    /// them.** Publishing walks Day 1 forwards; unpublishing walks the highest
    /// day backwards. That is the order a teacher would do it by hand, and it
    /// is not only cosmetic: each step's rules — which linked pages come with
    /// it, which are left because something else still needs them, which take
    /// the class's date — are asked against the state as it actually is at
    /// that moment. Walking publish FORWARDS is what makes an earlier class
    /// claim a shared page's date, which is the same first-use rule the course
    /// installer follows.
    ///
    /// **The preview is stopped ONCE, not once per page.** Every page in the
    /// unit is one act as far as the teacher is concerned, so stopping and
    /// starting around each of twenty pages would be twenty rebuilds of a site
    /// nobody is looking at yet.
    ///
    /// **The undo list gets ONE entry.** Every file touched along the way is
    /// merged into a single change, so "undo that" takes the whole unit back
    /// rather than the last page of it.
    private func wholeUnitRequested(
        _ arguments: [String: Any],
        publishing: Bool
    ) async -> AssistToolOutcome? {
        let titles: [String] = names("pages", in: arguments)
        guard titles.count == 1, let unit = AssistPublishPlanner.unitNamed(titles[0]) else {
            return nil
        }
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.refused(refusal(from: found).message)
        }

        var pages: [ClassPageSummary] = AssistPublishPlanner.classPages(
            inUnit: unit,
            from: ClassPages.list(forSection: located.sectionNumber, in: located.course)
        )
        if pages.isEmpty {
            return AssistToolOutcome.refused(
                "I can't find any class pages in Unit \(unit) of \(located.course.code) "
                + "Section \(located.sectionNumber)."
            )
        }
        // Highest day first to take a unit down; Day 1 first to put it up.
        if publishing {
            pages.reverse()
        }

        let backedUp: Bool = backUpOnceForThisConversation(
            located.course, forSection: located.sectionNumber
        )
        _ = await stopThePreviewBeforeWriting(
            for: located.course, sectionNumber: located.sectionNumber
        )

        var touched: [AssistSavedFile] = []
        var changedAnything: Bool = false
        for summary in pages {
            let graph: AssistSectionGraph = AssistSectionGraph.read(
                forSection: located.sectionNumber, in: located.course,
                workspaceURL: workspace.workspaceURL
            )
            let classPages: [ClassPageSummary] = ClassPages.list(
                forSection: located.sectionNumber, in: located.course
            )
            let plan: AssistPublishPlan = publishing
                ? AssistPublishPlanner.planPublishing(
                    titles: [summary.title], onOrAfter: nil, before: nil,
                    graph: graph, classPages: classPages,
                    forSection: located.sectionNumber, in: located.course)
                : AssistPublishPlanner.planUnpublishing(
                    titles: [summary.title], onOrAfter: nil, before: nil,
                    graph: graph, classPages: classPages,
                    forSection: located.sectionNumber, in: located.course)
            if plan.changesNothing {
                continue
            }
            do {
                let change: AssistChange = try AssistPublishPlanner.apply(
                    plan, forSection: located.sectionNumber, in: located.course
                )
                touched = AssistToolRunner.merging(touched, with: change.files)
                changedAnything = true
            } catch {
                return AssistToolOutcome.refused(
                    "Unit \(unit) was only partly \(publishing ? "published" : "unpublished"): "
                    + error.localizedDescription
                )
            }
        }

        let done: String = publishing ? "published" : "unpublished"
        if !changedAnything {
            let already: String = publishing
                ? "Unit \(unit) has already been published."
                : "Unit \(unit) is already hidden."
            return AssistToolOutcome.wrote(already, detail: already)
        }

        history.record(AssistChange(
            whatHappened: "\(done) Unit \(unit)",
            courseCode: located.course.code,
            sectionNumber: located.sectionNumber,
            rebuildsThePreview: true,
            files: touched
        ))

        var detail: String = "Unit \(unit) was \(done)."
        if backedUp {
            detail += "\n\n" + AssistToolRunner.backedUpNote
        }
        detail += "\n\n" + (await bringThePreviewUpToDate(
            for: located.course, sectionNumber: located.sectionNumber
        ))

        return AssistToolOutcome.wrote("Unit \(unit) was \(done).", detail: detail)
    }

    /// Fold a step's files into what earlier steps touched.
    ///
    /// A page written more than once keeps the EARLIEST before and the LATEST
    /// after, so undoing the merged change puts it back the way it was before
    /// the whole unit was touched — not the way it was one step ago.
    private static func merging(
        _ soFar: [AssistSavedFile], with newer: [AssistSavedFile]
    ) -> [AssistSavedFile] {
        var merged: [AssistSavedFile] = soFar
        for file in newer {
            var replaced: Bool = false
            for index in merged.indices where merged[index].fileURL == file.fileURL {
                merged[index] = AssistSavedFile(
                    fileURL: file.fileURL, before: merged[index].before, after: file.after
                )
                replaced = true
            }
            if !replaced {
                merged.append(file)
            }
        }
        return merged
    }

    private func pagePlan(
        _ arguments: [String: Any],
        publishing: Bool
    ) -> Result<PlannedPages, AssistToolRefusal> {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return .failure(refusal(from: found))
        }

        let titles: [String] = names("pages", in: arguments)
        let onOrAfterText: String = text("onOrAfter", in: arguments)
        let beforeText: String = text("before", in: arguments)

        var onOrAfter: CalendarDay? = nil
        var before: CalendarDay? = nil

        // Dates are only evaluated when no specific pages were named. If pages
        // were named, date boundaries are ignored so dateline leakage from the
        // prompt cannot accidentally sweep other classes.
        if titles.isEmpty {
            if !onOrAfterText.isEmpty {
                guard let day = CalendarDay(text: onOrAfterText) else {
                    return .failure(.unreadableDate(onOrAfterText, "onOrAfter"))
                }
                onOrAfter = day
            }
            if !beforeText.isEmpty {
                guard let day = CalendarDay(text: beforeText) else {
                    return .failure(.unreadableDate(beforeText, "before"))
                }
                before = day
            }
        }

        if titles.isEmpty && onOrAfter == nil && before == nil {
            return .failure(.nothingNamed)
        }

        // An open-ended PUBLISH — no pages named, a start date and no end —
        // means "everything from this day to the end of the course", which is
        // not a thing a teacher asks for. It is, however, what a mistyped
        // request for a single lesson turns into: "publsh tomorows class …
        // and the stuff it links to" routed here 10 times out of 10 and filled
        // in `onOrAfter` alone, quietly offering to publish the rest of the
        // term.
        //
        // The rule lives HERE rather than in the tool's description because
        // the description was tried first and measured worse: naming
        // publish_class_on in the text fixed that probe and broke three
        // others, since a small model reads a sentence naming another tool as
        // a recommendation rather than a boundary. A refusal changes nothing
        // the model reads, so it cannot cost accuracy — and it comes back as
        // ordinary text the assistant reads out, so the model gets to correct
        // itself on the next turn.
        //
        // Publishing only. An open-ended UNPUBLISH hides work rather than
        // exposing it, is undone by the same backup, and a teacher clearing a
        // section down to a date is a real thing to want.
        if publishing && titles.isEmpty && before == nil, let from = onOrAfter {
            return .failure(.openEndedPublish(from))
        }

        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: located.sectionNumber, in: located.course,
            workspaceURL: workspace.workspaceURL
        )
        let classPages: [ClassPageSummary] = ClassPages.list(
            forSection: located.sectionNumber, in: located.course
        )

        // How far each verb reaches is the planner's rule, not an argument.
        // Publishing always takes the pages it links to; unpublishing takes
        // only the pages nothing else needs.
        let plan: AssistPublishPlan
        if publishing {
            plan = AssistPublishPlanner.planPublishing(
                titles: titles,
                onOrAfter: onOrAfter, before: before,
                graph: graph, classPages: classPages,
                forSection: located.sectionNumber, in: located.course
            )
        } else {
            plan = AssistPublishPlanner.planUnpublishing(
                titles: titles,
                onOrAfter: onOrAfter, before: before,
                graph: graph, classPages: classPages,
                forSection: located.sectionNumber, in: located.course
            )
        }
        return .success(PlannedPages(located: located, plan: plan))
    }

    // MARK: - Backing up, once per conversation

    /// Makes sure a copy of the course exists from before this conversation
    /// touched it, and says whether one does.
    ///
    /// Lazy and once: the first write saves the copy, and every later write in
    /// the same conversation reuses it rather than saving a near-identical one.
    /// The copy is named for the assistant and the section it was made for, so
    /// a teacher reading the Backups list knows what it was for.
    private func backUpOnceForThisConversation(
        _ course: Course,
        forSection sectionNumber: Int
    ) -> Bool {
        if conversationBackups[course.code] != nil {
            return true
        }
        guard let coursesDirectoryURL = workspace.coursesDirectoryURL else {
            return false
        }
        guard let backupURL = try? CourseArchiver.backUpCourse(
            course,
            coursesDirectoryURL: coursesDirectoryURL,
            madeBy: .assistant(sectionNumber: sectionNumber)
        ) else {
            return false
        }
        conversationBackups[course.code] = backupURL
        conversationBackupURL = backupURL
        return true
    }

    /// What the teacher is told about that copy. The same sentence whether the
    /// backup was made by this command or by an earlier one in the same chat,
    /// because what matters to them is only that there is a way back.
    private static let backedUpNote: String =
        "The course was backed up before this conversation changed anything, so this can also be "
      + "undone from Plantoir's Backups list."

    // MARK: - Writing pages

    /// Back the course up, write the change, remember it, rebuild the preview.
    private func carryOut(
        _ plan: AssistPublishPlan,
        forSection sectionNumber: Int,
        in course: Course,
        summary: String
    ) async -> AssistToolOutcome {
        if plan.changesNothing {
            // Four words, when four words are the whole answer. A teacher who
            // asks to publish a class that is already published does not want
            // a plan with a heading, a count, and a note that nothing was
            // changed because nothing needed to be.
            if let already = plan.nothingToDoSentence {
                return AssistToolOutcome.wrote(already, detail: already)
            }
            return AssistToolOutcome.wrote(
                "Nothing needed changing.",
                detail: plan.describe() + "\n\nNothing was changed, because nothing needed to be."
            )
        }

        // Before anything is touched — but only the first time in a
        // conversation. The undo history covers the rest of it; the backup
        // outlives the conversation.
        let backedUp: Bool = backUpOnceForThisConversation(course, forSection: sectionNumber)

        // Stop → write → start, and the stop is HERE rather than beside the
        // start for a reason. A preview left serving while the pages beneath
        // it are rewritten serves a half-changed site, and the teacher's next
        // refresh is a race they cannot see they are in.
        _ = await stopThePreviewBeforeWriting(for: course, sectionNumber: sectionNumber)

        let change: AssistChange
        do {
            change = try AssistPublishPlanner.apply(plan, forSection: sectionNumber, in: course)
        } catch {
            return AssistToolOutcome.refused(
                "Nothing was changed: \(error.localizedDescription)"
            )
        }
        history.record(change)

        var detail: String = plan.describe() + "\n\nDone: \(change.description)."
        if backedUp {
            detail += "\n\n" + AssistToolRunner.backedUpNote
        }

        let previewNote: String = await bringThePreviewUpToDate(
            for: course, sectionNumber: sectionNumber
        )
        detail += "\n\n" + previewNote
        detail += "\n\nThis changed the teacher's files and their PREVIEW. It did not put anything in front "
                + "of students — deploying does that, and only when they ask."

        return AssistToolOutcome.wrote(summary, detail: detail)
    }

    // MARK: - Preview, undo, deploy

    private func rebuildPreview(_ arguments: [String: Any]) async -> AssistToolOutcome {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.refused(refusal(from: found).message)
        }
        let message: String = await bringThePreviewUpToDate(
            for: located.course, sectionNumber: located.sectionNumber
        )
        return AssistToolOutcome.wrote(message, detail: message)
    }

    /// The window this section is open in, if one is on screen.
    private func sectionWindow(
        for course: Course, sectionNumber: Int
    ) -> SectionWindowControllers.Controller? {
        guard let folder = workspace.workspaceURL else {
            return nil
        }
        return SectionWindowControllers.shared.controller(
            folderPath: folder.path, courseCode: course.code, sectionNumber: sectionNumber
        )
    }

    /// Makes a real window show this section, for the LOCAL assistant only
    /// — `deploy_section` and `bring the preview up to date` both call this
    /// before falling back to running silently, so asking through the
    /// assistant does the same thing pressing the button would: a console,
    /// a progress header, a live-site link, all on screen.
    ///
    /// Reuses an already-open window on the same working folder if one
    /// exists — the common case, since the assistant is almost always
    /// opened FROM an already-open window's sidebar — rather than opening
    /// a new one every time. Only opens a fresh window when none is open
    /// at all (`openMainWindow`, present only for the local assistant).
    ///
    /// Returns once `SectionWindowControllers` has actually registered a
    /// controller for the section, or gives up after a short wait — moving
    /// `.selection` is not itself the section appearing: `SectionDetailView`
    /// still has to mount and run its own `.onAppear` on a real SwiftUI
    /// render pass before there is anything to press.
    /// Not private: `pollInterval`/`maxAttempts` let a test drive this
    /// without a multi-second real-time wait, and the "already-open window
    /// is reused, `openMainWindow` never called" behavior needs to be
    /// checked directly — the eventual `SectionWindowControllers`
    /// registration this waits for only ever happens from a REAL
    /// `SectionDetailView` mounting, which no unit test can produce.
    func revealSectionOnScreen(
        course: Course, sectionNumber: Int,
        pollInterval: Duration = .milliseconds(50), maxAttempts: Int = 40
    ) async -> Bool {
        guard let openMainWindow, let folder = workspace.workspaceURL else {
            return false
        }

        var target: WorkspaceModel? = AssistToolRunner.openWindowModel(forFolderPath: folder.path)

        if target == nil {
            // Snapshot who is already open, by identity — the NEW window's
            // model is whichever one appears in `windowModels` that was not
            // here before, not (yet) one we can find by folder path.
            let alreadyOpen: [ObjectIdentifier] = WorkspaceModel.windowModels.map { ObjectIdentifier($0) }
            openMainWindow()
            var freshModel: WorkspaceModel?
            for _ in 0..<maxAttempts {
                for model in WorkspaceModel.windowModels where !alreadyOpen.contains(ObjectIdentifier(model)) {
                    freshModel = model
                    break
                }
                if freshModel != nil {
                    break
                }
                try? await Task.sleep(for: pollInterval)
            }
            // A brand-new window's own WorkspaceModel starts with no
            // folder at all — `WindowRootView` creates it bare and its own
            // `onAppear` only GUESSES a folder (`adoptFolderForNewWindow`,
            // keyed off whichever window was most recently key in
            // AppKit's own terms). This assistant's workspace already
            // KNOWS the right folder — there is no reason to leave a
            // fresh window guessing at it, or to trust the guess when we
            // have the actual answer. Set it directly, unconditionally: a
            // mid-session window never goes through the launch-time
            // restoration-claim path this could otherwise race with (see
            // `WindowRootView.attemptClaim`'s own comment — "a mid-session
            // window inherits nothing" from that path), so nothing else
            // is going to set this window's folder out from under us.
            if let freshModel {
                freshModel.adoptRestoredPath(folder.path)
                target = freshModel
            }
        }

        guard let target else {
            return false
        }

        target.selection = SidebarSelection.section(course.code, sectionNumber)
        NSApp.activate(ignoringOtherApps: true)
        target.window?.makeKeyAndOrderFront(nil)

        for _ in 0..<maxAttempts {
            if sectionWindow(for: course, sectionNumber: sectionNumber) != nil {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return sectionWindow(for: course, sectionNumber: sectionNumber) != nil
    }

    /// An already-open window's model working in this folder, if one exists.
    static func openWindowModel(forFolderPath path: String) -> WorkspaceModel? {
        for model in WorkspaceModel.windowModels where model.workspaceURL?.path == path {
            return model
        }
        return nil
    }

    /// Stop the preview before changing files. Returns whether one was up.
    ///
    /// Called BEFORE the writes, which is the whole point of it being a
    /// separate step. A preview left serving while the pages underneath it are
    /// rewritten is serving a half-changed site, and the teacher's next
    /// refresh is a race they cannot see they are in.
    private func stopThePreviewBeforeWriting(
        for course: Course, sectionNumber: Int
    ) async -> Bool {
        guard let window = sectionWindow(for: course, sectionNumber: sectionNumber) else {
            return false
        }
        if !window.isPreviewRunning() {
            return false
        }
        // Awaited. A stop that is still finishing when the rebuild starts
        // kills the rebuild, and the teacher is left with no preview and a
        // site on disk from before their change.
        await window.stopPreview()
        return true
    }

    /// Put the section's preview back up, built from what is now on disk.
    ///
    /// Always a full stop and restart when one is running, never a quiet
    /// rebuild underneath it: "Preview" asks to be shown the section as it is
    /// NOW, and the running preview is precisely the stale thing being
    /// complained about.
    ///
    /// Two paths, and which one runs depends on whether a section window
    /// ends up open — not on a flag anyone passes. The LOCAL assistant
    /// tries `revealSectionOnScreen` first when none is open yet, exactly
    /// as `deploySection` does (see its own doc comment for why):
    ///
    /// * **A window is open** (already, or because the local assistant just
    ///   put one there). Its own Preview is started, which builds AND
    ///   serves. Nothing else builds, because starting it builds: doing a
    ///   `--build-only` pass first would build the same site twice and make a
    ///   teacher wait through both.
    /// * **No window is open**, and either nothing could open one (MCP, a
    ///   scheduled deploy) or the local assistant tried and it did not work
    ///   out in time. Nobody can be shown anything, so the site is brought
    ///   up to date on disk and the answer says so plainly rather than
    ///   claiming a preview that does not exist.
    private func bringThePreviewUpToDate(
        for course: Course, sectionNumber: Int
    ) async -> String {
        if sectionWindow(for: course, sectionNumber: sectionNumber) == nil {
            _ = await revealSectionOnScreen(course: course, sectionNumber: sectionNumber)
        }
        if let window = sectionWindow(for: course, sectionNumber: sectionNumber) {
            // Stop whatever is running first, and WAIT for it. "Preview" means
            // show me this section as it is now, so a preview already up is
            // the thing most in need of replacing — leaving it alone would
            // answer the request with the very page it was asked to refresh.
            //
            // The wait is not politeness. Stopping reaches into the container
            // and kills that section's processes, so a stop still finishing
            // when the rebuild starts kills the rebuild, and what gets served
            // is the last build allowed to complete — the site as it was
            // before.
            if window.isPreviewRunning() {
                await window.stopPreview()
            }
            window.startPreview()
            return AssistWording.previewIsRebuilding(
                course: course.code, section: String(sectionNumber)
            )
        }

        let rebuild: AssistSiteWorkResult = await siteWork.rebuildPreview(
            course: course, sectionNumber: sectionNumber
        )
        if !rebuild.succeeded {
            return rebuild.message
        }
        return AssistWording.builtWithNoWindowOpen(
            course: course.code, section: String(sectionNumber)
        )
    }

    /// Put the last change back — and put the section's preview back with it.
    ///
    /// **The order is stop → restore → start, and it is the same order
    /// `publishPages` uses.** It did not used to be: the undo wrote the files
    /// and stopped, so a teacher who had a preview up watched it go on serving
    /// the state they had just asked to leave. Worse than stale — a preview
    /// left running while the pages beneath it are rewritten is serving a
    /// half-changed site, and the next refresh is a race the teacher cannot see
    /// they are in.
    ///
    /// The stop is AWAITED, and that is load-bearing rather than tidy: stopping
    /// reaches into the container and kills that section's processes, so a stop
    /// still finishing when the next build starts kills the build too, and what
    /// gets served is the site as it was before. `stopThePreviewBeforeWriting`
    /// waits for the stop to actually finish rather than assuming it did.
    ///
    /// Restarting afterwards MATCHES PUBLISH rather than being conditional on a
    /// preview having been up. Undo is the inverse of a write and should leave
    /// the section in the same kind of state the write does; a version that
    /// restarted only when one had been running would make "unpublish" and
    /// "undo that" behave differently for no reason a teacher could see, which
    /// is exactly the sort of difference that gets reported months later.
    private func undoLastChange() async -> AssistToolOutcome {
        if history.isEmpty {
            return AssistToolOutcome.refused(AssistWording.nothingToUndo)
        }

        // Looked at before it is taken back, because the preview that has to
        // come down belongs to the section the change was made in, and a
        // change used to know only its files.
        guard let pending = history.nextToUndo else {
            return AssistToolOutcome.refused(AssistWording.nothingToUndo)
        }
        let course: Course? = course(withCode: pending.courseCode)

        // (a) Stop the preview, and wait until it has actually stopped.
        if let course, pending.rebuildsThePreview {
            _ = await stopThePreviewBeforeWriting(
                for: course, sectionNumber: pending.sectionNumber
            )
        }

        // (b) Put the files back.
        let result: AssistUndoResult = history.undo()

        if result.restored.isEmpty && result.skipped.isEmpty {
            return AssistToolOutcome.refused(result.description)
        }

        // Nothing went back, because every file has been edited since. This
        // must not read like a success, and it used to.
        if result.restored.isEmpty {
            var refusal: String = AssistWording.couldNotUndo(
                result.whatHappened, leftAlone: result.skipped.count
            )
            refusal += "\n\n" + listing(result.skipped)
            refusal += "\n\n" + AssistWording.undoIsStillAvailable
            return AssistToolOutcome.refused(refusal)
        }

        let summary: String
        if result.skipped.isEmpty {
            summary = AssistWording.undid(result.whatHappened)
        } else {
            summary = AssistWording.undidPartly(
                result.whatHappened, leftAlone: result.skipped.count
            )
        }

        var detail: String = summary
        if !result.skipped.isEmpty {
            detail += "\n\nThe ones I left alone:\n" + listing(result.skipped)
            detail += "\n\n" + AssistWording.undoIsStillAvailable
        }

        // (c) Put the preview back up, built from what is on disk now.
        if let course, pending.rebuildsThePreview {
            detail += "\n\n" + (await bringThePreviewUpToDate(
                for: course, sectionNumber: pending.sectionNumber
            ))
        }

        detail += "\n\n" + AssistWording.undoDoesNotReachTheLiveSite

        return AssistToolOutcome.wrote(summary, detail: detail)
    }

    /// What to call the pages a class-page add created, for the sentence an
    /// undo reads back later.
    private static func namingClassesCreated(_ urls: [URL]) -> String {
        var names: [String] = []
        for url in urls {
            names.append(url.deletingPathExtension().lastPathComponent)
        }
        if names.count == 1 {
            return "added the class page \(names[0])"
        }
        if names.count == 2 {
            return "added the class pages \(names[0]) and \(names[1])"
        }
        return "added \(names.count) class pages"
    }

    /// The files an undo left alone, as a list a teacher can go and look at.
    private func listing(_ urls: [URL]) -> String {
        var lines: [String] = []
        var listed: Int = 0
        for url in urls {
            if listed == AssistToolRunner.mostListed {
                lines.append("…and \(urls.count - listed) more.")
                break
            }
            lines.append("  " + AssistSectionGraph.relativePath(
                of: url, workspaceURL: workspace.workspaceURL
            ))
            listed += 1
        }
        return lines.joined(separator: "\n")
    }

    /// The course with this code, or nil when the working folder no longer has
    /// one — a course renamed or archived mid-conversation.
    private func course(withCode code: String) -> Course? {
        for candidate in workspace.courses where candidate.code.lowercased() == code.lowercased() {
            return candidate
        }
        return nil
    }

    /// Deploy the section — by doing exactly what the teacher would do with
    /// the two buttons in the section's window: Stop Preview, then Deploy.
    ///
    /// **Why the buttons rather than the toolchain directly.** The old version
    /// ran `deploy.sh` in a `ScriptRunner` the assistant made for itself, which
    /// nothing on screen was watching. Two things went wrong with that, and
    /// they compounded into "I pressed Deploy and nothing happened":
    ///
    /// * **Nothing showed.** No console, no progress header, no live-site link
    ///   at the end — a deploy is minutes long, and every visible sign of it
    ///   belongs to the section window. The teacher had a spinner in the chat
    ///   and a section window sitting there saying "No Preview Running".
    /// * **The preview blocked it.** A running preview is exactly when a
    ///   teacher asks for this, and it made the deploy REFUSE — with
    ///   `busyDescription`'s menu fragment, "Available once preview completed",
    ///   which reads like nothing at all. The window's own Deploy button is
    ///   greyed out then, so what a teacher does is press Stop Preview first.
    ///   The assistant now does the same thing, in the same order.
    ///
    /// Stopping is AWAITED before the deploy starts, for the reason it is
    /// awaited before a write: stop mode finds a section's processes by
    /// working directory, so a stop still finishing when the build begins
    /// kills the build.
    ///
    /// **With no window open, the LOCAL assistant opens one.** `openMainWindow`
    /// is present only on that path (never MCP, never a scheduled deploy —
    /// see its own doc comment); `revealSectionOnScreen` puts the section on
    /// screen exactly as if the teacher had clicked it in the sidebar, and
    /// this proceeds through the button's own path from there. Only when
    /// that genuinely cannot happen — MCP, a scheduled deploy, or the local
    /// assistant failing to get a window on screen in time — does `siteWork`
    /// run the launcher itself, silently: the path Claude Code and a 6:30
    /// a.m. alarm take.
    private func deploySection(_ arguments: [String: Any]) async -> AssistToolOutcome {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.refused(refusal(from: found).message)
        }

        _ = await stopThePreviewBeforeWriting(
            for: located.course, sectionNumber: located.sectionNumber
        )

        // The local assistant can put the section on screen itself, so a
        // deploy it starts looks exactly like one the button started —
        // console, progress header and live-site link included, not a
        // spinner in the chat beside a window saying nothing is running.
        if sectionWindow(for: located.course, sectionNumber: located.sectionNumber) == nil {
            _ = await revealSectionOnScreen(course: located.course, sectionNumber: located.sectionNumber)
        }

        let result: AssistSiteWorkResult
        if let window = sectionWindow(for: located.course, sectionNumber: located.sectionNumber) {
            result = await window.deploy()
        } else {
            result = await siteWork.deploy(
                course: located.course, sectionNumber: located.sectionNumber
            )
        }

        if !result.succeeded {
            return AssistToolOutcome.refused(result.message)
        }
        // The stopped preview is NOT mentioned, and that was a decision.
        //
        // A sentence explaining it was written first, on the theory that a
        // preview window going blank unasked is its own small alarm. Read in
        // place it was three lines of machinery after the one line that
        // mattered — "CIA4U Section 1 is deployed. Students can reach it now."
        // is the whole answer to what was asked, and the teacher can see the
        // window it happened in. Anything that explains what the assistant had
        // to do to obey is talking about itself.
        return AssistToolOutcome.wrote(result.message, detail: result.message)
    }

    // MARK: - Deploying later

    /// A moment and a section, both read.
    private struct ScheduleRequest {
        let located: Located
        let when: Date
        let plan: ScheduledDeployPlan
    }

    private func scheduleRequest(_ arguments: [String: Any]) -> Result<ScheduleRequest, AssistToolRefusal> {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return .failure(refusal(from: found))
        }
        let raw: String = text("when", in: arguments)
        guard let when = AssistToolRunner.moment(named: raw) else {
            return .failure(.unreadableTime(raw))
        }
        let plan: ScheduledDeployPlan = ScheduledDeploy.plan(
            course: located.course,
            sectionNumber: located.sectionNumber,
            when: when,
            now: Date(),
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID
        )
        return .success(ScheduleRequest(located: located, when: when, plan: plan))
    }

    private func planScheduledDeploy(_ arguments: [String: Any]) -> AssistToolOutcome {
        let request: Result<ScheduleRequest, AssistToolRefusal> = scheduleRequest(arguments)
        guard case .success(let asked) = request else {
            if case .failure(let refusal) = request {
                return AssistToolOutcome.couldNotRead(refusal.message)
            }
            return AssistToolOutcome.couldNotRead(AssistToolRefusal.noWorkingFolder.message)
        }

        // `ScheduledDeployPlan` already says what has to be true of the Mac,
        // and which of the section's classes are still held back. The classes
        // the TEACHER had in mind are checked here on top of that: a deploy
        // that runs perfectly and ships a site without tomorrow's class is the
        // failure worth catching while somebody is awake.
        var lines: [String] = [asked.plan.description]
        let classes: [String] = names("classes", in: arguments)
        if !classes.isEmpty {
            let graph: AssistSectionGraph = AssistSectionGraph.read(
                forSection: asked.located.sectionNumber, in: asked.located.course,
                workspaceURL: workspace.workspaceURL
            )
            lines.append("")
            lines.append("The classes this deploy is meant to carry:")
            for title in classes {
                guard let page = graph.page(titled: title) else {
                    lines.append("  \(title) — no page in this section is called that.")
                    continue
                }
                lines.append("  \(page.displayTitle) — "
                             + (page.isVisibleToStudents
                                ? "published, so the deploy would carry it."
                                : "NOT published, so the deploy would ship without it."))
            }
        }
        return AssistToolOutcome.planned(
            asked.plan.isSchedulable
                ? "Worked out what scheduling that deploy would mean."
                : "That deploy cannot be scheduled.",
            plan: lines.joined(separator: "\n")
        )
    }

    private func scheduleDeploy(_ arguments: [String: Any]) -> AssistToolOutcome {
        let request: Result<ScheduleRequest, AssistToolRefusal> = scheduleRequest(arguments)
        guard case .success(let asked) = request else {
            if case .failure(let refusal) = request {
                return AssistToolOutcome.refused(refusal.message)
            }
            return AssistToolOutcome.refused(AssistToolRefusal.noWorkingFolder.message)
        }
        guard let workspaceURL = workspace.workspaceURL else {
            return AssistToolOutcome.refused(AssistToolRefusal.noWorkingFolder.message)
        }

        // Everything the plan refuses is something that would ASK A QUESTION
        // at the scheduled moment, with nobody there to answer it.
        if let problem = asked.plan.problem {
            return AssistToolOutcome.refused("Nothing was scheduled. \(problem)")
        }

        if let problem = ScheduledDeploy.scheduleDeploy(
            course: asked.located.course,
            sectionNumber: asked.located.sectionNumber,
            when: asked.when,
            workspaceURL: workspaceURL,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID,
            runner: launchControl
        ) {
            return AssistToolOutcome.refused("Nothing was scheduled. \(problem)")
        }

        let moment: String = ScheduledDeploy.dayAndTimeText(asked.when)
        let summary: String = "Scheduled: \(asked.located.course.code) Section "
            + "\(asked.located.sectionNumber) deploys to \(asked.plan.destination) at \(moment)."
        return AssistToolOutcome.wrote(
            summary,
            detail: summary + "\n\nThis Mac has to be on and awake then — plugged in if it is a laptop, "
                  + "lid open. Plantoir cannot wake it up. Say the word and I'll cancel it."
        )
    }

    private func cancelScheduledDeploy(_ arguments: [String: Any]) -> AssistToolOutcome {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.refused(refusal(from: found).message)
        }

        let pending: Date? = ScheduledDeploy.nextRun(
            courseCode: located.course.code, sectionNumber: located.sectionNumber
        )
        if pending == nil {
            // Safe to call when nothing is scheduled — and it still tidies
            // away an agent left behind by a Mac that was off, which is why
            // this goes ahead rather than returning here.
            ScheduledDeploy.cancelScheduledDeploy(
                courseCode: located.course.code,
                sectionNumber: located.sectionNumber,
                runner: launchControl
            )
            return AssistToolOutcome.wrote(
                "There is no deploy scheduled for \(located.course.code) Section "
                + "\(located.sectionNumber).",
                detail: "There is no deploy scheduled for \(located.course.code) Section "
                      + "\(located.sectionNumber), so there was nothing to call off."
            )
        }

        if let problem = ScheduledDeploy.cancelScheduledDeploy(
            courseCode: located.course.code,
            sectionNumber: located.sectionNumber,
            runner: launchControl
        ) {
            return AssistToolOutcome.refused("That could not be cancelled: \(problem)")
        }
        let message: String = "Cancelled the scheduled deploy for \(located.course.code) Section "
            + "\(located.sectionNumber)."
        return AssistToolOutcome.wrote(message, detail: message)
    }

    // MARK: - When this class meets

    /// What is remembered about when a section meets, read back with WHERE IT
    /// CAME FROM — so a teacher can recognise a stale answer and say so.
    private func readRememberedTimetable(_ arguments: [String: Any]) -> AssistToolOutcome {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.couldNotRead(refusal(from: found).message)
        }
        let where_: String = "\(located.course.code) Section \(located.sectionNumber)"

        // "I have a revised list of class dates" — the teacher volunteered, so
        // the sheet opens on the spot. Asking "may I ask you for your dates?"
        // in reply to somebody offering them is the kind of politeness that
        // reads as not listening.
        if text("revise", in: arguments).lowercased() == "yes" {
            SectionSchedulePrompt.shared.ask(
                courseCode: located.course.code,
                sectionNumber: located.sectionNumber,
                workingFolder: workspace.workspaceURL ?? located.course.directoryURL,
                because: "Replacing the class dates on file for \(where_)."
            )
            let opening: String = "Here you are — the dates for \(where_) are open for editing. "
                                + "What you save replaces what was there."
            return AssistToolOutcome(summary: opening, detail: opening, shouldContinue: false)
        }

        let remembered: SectionTimetable?
        do {
            remembered = try SectionTimetableStore.read(
                forSection: located.sectionNumber, in: located.course
            )
        } catch {
            return AssistToolOutcome.couldNotRead(error.localizedDescription)
        }

        guard let remembered else {
            askForTheTimetable(
                courseCode: located.course.code,
                sectionNumber: located.sectionNumber,
                because: "Nothing on file says when \(where_) meets."
            )
            let asking: String = "I don't know when \(where_) meets yet. "
                               + AssistWording.mayIAskForYourDates
            return AssistToolOutcome(summary: asking, detail: asking, shouldContinue: false)
        }

        // "All of them" is asked for by a fixed phrasing the window offers
        // after the short answer — the model is never told this key exists, so
        // the tool's schema is unchanged and its routing is untouched.
        let wantsEveryDate: Bool = text("scope", in: arguments).lowercased() == "all"

        if wantsEveryDate {
            var every: [String] = ["Every date on file for \(where_):"]
            for date in remembered.dates {
                every.append("• \(date.weekdayName), \(date.text)")
            }
            let all: String = every.joined(separator: "\n")
            return AssistToolOutcome(
                summary: all,
                detail: all,
                shouldContinue: false
            )
        }

        var lines: [String] = []

        // What the dates are actually FOR: map existing class pages by date or schedule index.
        let existing: [ClassPageSummary] = ClassPages.list(
            forSection: located.sectionNumber, in: located.course
        )
        var classByDate: [String: String] = [:]
        for page in existing {
            if let date = page.date {
                classByDate[date.text] = page.title
            }
        }

        // Determine upcoming classes (up to 3) relative to today.
        var upcomingDates: [CalendarDay] = []
        if today < remembered.firstDate {
            for (idx, date) in remembered.dates.enumerated() {
                if idx < 3 {
                    upcomingDates.append(date)
                }
            }
            let countStr: String = upcomingDates.count == 1 ? "first class is" : "first \(upcomingDates.count) classes are"
            lines.append("The semester begins on \(remembered.firstDate.weekdayName), \(remembered.firstDate.text). The \(countStr):")
        } else {
            for date in remembered.dates {
                if date >= today && upcomingDates.count < 3 {
                    upcomingDates.append(date)
                }
            }
            if upcomingDates.isEmpty {
                lines.append("All \(remembered.dates.count) scheduled classes for \(where_) have concluded (last class was on \(remembered.lastDate.weekdayName), \(remembered.lastDate.text)).")
            } else {
                let countStr: String = upcomingDates.count == 1 ? "upcoming class" : "\(upcomingDates.count) upcoming classes"
                lines.append("Your next \(countStr) for \(where_):")
            }
        }

        for date in upcomingDates {
            var classTitle: String = ""
            if let title = classByDate[date.text] {
                classTitle = title
            } else if let idx = remembered.dates.firstIndex(of: date), idx < existing.count {
                classTitle = existing[idx].title
            } else {
                classTitle = "(page not yet created)"
            }
            lines.append("• \(date.weekdayName), \(date.text) — \(classTitle)")
        }

        lines.append("")
        let spare: Int = remembered.spareDates(after: existing.count)
        lines.append("\(where_) has \(existing.count) class \(existing.count == 1 ? "page" : "pages") across \(remembered.dates.count) recorded dates (\(spare) spare).")
        if spare == 0 {
            lines.append("Every recorded date is spoken for, so another class cannot be dated until more dates are recorded.")
        } else {
            let next: CalendarDay = remembered.dates[existing.count]
            lines.append("The next class would fall on \(next.text) (\(next.weekdayName)).")
        }

        var origin: String = "Where they came from: \(remembered.source)."
        if let when = remembered.recorded {
            origin += " Recorded \(when.text)."
        }
        lines.append("")
        lines.append(origin)

        if remembered.dates.count > upcomingDates.count {
            let rest: Int = remembered.dates.count - upcomingDates.count
            lines.append("")
            lines.append("There \(rest == 1 ? "is" : "are") \(rest) more. Say “show me all the dates” to see the full schedule.")
        }

        let fullAnswer: String = lines.joined(separator: "\n")
        return AssistToolOutcome(
            summary: fullAnswer,
            detail: fullAnswer,
            shouldContinue: false
        )
    }

    private struct PlannedTimetable {
        let located: Located
        let plan: RememberTimetablePlan
    }

    /// The shared reading of the arguments for both halves of remembering a
    /// timetable.
    ///
    /// The dates arrive ALREADY WORKED OUT, as `YYYY-MM-DD`. Nothing here reads
    /// a spreadsheet, a `.csv`, an `.ics` or a teacher's pasted paragraph, and
    /// the model is not asked to do it either — a date read loosely is a class
    /// scheduled on the wrong day.
    ///
    /// - Note: turning a Google Sheet link, a `.csv`, an `.ics` or pasted text
    ///   into `[CalendarDay]` belongs to `SectionScheduleSource`, and it plugs
    ///   in one step upstream of here rather than inside this tool: whatever
    ///   read the dates hands `SectionScheduleSource.Reading.datesText` on to
    ///   `planRememberTimetable`, exactly as this does. Reading a source can
    ///   need a question answered — "is 08/09/2026 the 8th of September or the
    ///   9th of August?" — and that is a question for the teacher, not
    ///   something to settle inside a tool call.
    private func timetablePlan(_ arguments: [String: Any]) -> Result<PlannedTimetable, Error> {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return .failure(refusal(from: found))
        }
        do {
            let plan: RememberTimetablePlan = try SectionTimetableStore.planRememberTimetable(
                dates: days("dates", in: arguments),
                source: text("source", in: arguments),
                forSection: located.sectionNumber,
                in: located.course,
                today: today
            )
            return .success(PlannedTimetable(located: located, plan: plan))
        } catch {
            return .failure(error)
        }
    }

    private func planRememberTimetable(_ arguments: [String: Any]) -> AssistToolOutcome {
        switch timetablePlan(arguments) {
        case .failure(let problem):
            return AssistToolOutcome.couldNotRead(problem.localizedDescription)
        case .success(let asked):
            return AssistToolOutcome.planned(
                asked.plan.changesNothing
                    ? "Those dates are already remembered."
                    : "Worked out what recording those class dates would do.",
                plan: asked.plan.description
            )
        }
    }

    private func rememberTimetable(_ arguments: [String: Any]) -> AssistToolOutcome {
        switch timetablePlan(arguments) {
        case .failure(let problem):
            return AssistToolOutcome.refused(problem.localizedDescription)
        case .success(let asked):
            if asked.plan.changesNothing {
                return AssistToolOutcome.wrote(
                    "Those dates were already remembered.",
                    detail: asked.plan.description
                          + "\n\nNothing was changed, because nothing needed to be."
                )
            }

            // Replacing a year's dates is worth having a way back from, and
            // the copy is made once per conversation however many writes
            // follow it.
            let backedUp: Bool = backUpOnceForThisConversation(
                asked.located.course, forSection: asked.located.sectionNumber
            )
            do {
                try SectionTimetableStore.applyRememberTimetable(asked.plan)
            } catch {
                return AssistToolOutcome.refused(
                    "Nothing was remembered: \(error.localizedDescription)"
                )
            }

            let summary: String = "Remembered \(asked.plan.dates.count) class "
                + "\(asked.plan.dates.count == 1 ? "date" : "dates") for "
                + "\(asked.plan.courseCode) Section \(asked.plan.sectionNumber)."
            var detail: String = asked.plan.description + "\n\nDone: \(summary)"
            detail += "\n\nNo page was touched and no student saw anything. New class pages take their "
                    + "dates from these, so this is worth reading back if a date ever looks wrong."
            if backedUp {
                detail += "\n\n" + AssistToolRunner.backedUpNote
            }
            return AssistToolOutcome.wrote(summary, detail: detail)
        }
    }

    // MARK: - The page for the next class

    private struct PlannedNextClass {
        let located: Located
        let plan: PlaceholderClassPlan
    }

    /// The shared reading of the arguments: which section, and what the next
    /// class page in it would be.
    ///
    /// The failure is carried as the error itself rather than as an
    /// `AssistToolRefusal`, because the two that matter here — no timetable at
    /// all, and a timetable that has run out — belong to `NextClassPlanner`,
    /// and each already says in its own words what to do about it.
    private func nextClassPlan(_ arguments: [String: Any]) -> Result<PlannedNextClass, Error> {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return .failure(refusal(from: found))
        }
        do {
            // "Start a new unit for the next class" is a fixed phrasing the
            // window offers, so the word arrives here literally. The model is
            // never told these keys exist, which keeps the tool's schema — and
            // the routing measured against it — unchanged.
            let unitAsked: String = text("unit", in: arguments).lowercased()
            let howMany: Int = number("days", in: arguments) ?? 0

            // "Add five more days to Unit 4": a unit NUMBER rather than the
            // word "next", and a count of days to put on the end of it.
            if howMany > 0, let unit = Int(unitAsked) {
                let plan: PlaceholderClassPlan = try NextClassPlanner.plan(
                    addingDays: howMany, toUnit: unit,
                    forSection: located.sectionNumber, in: located.course
                )
                return .success(PlannedNextClass(located: located, plan: plan))
            }

            let plan: PlaceholderClassPlan = try NextClassPlanner.plan(
                forSection: located.sectionNumber, in: located.course,
                startingANewUnit: unitAsked == "next"
            )
            return .success(PlannedNextClass(located: located, plan: plan))
        } catch {
            return .failure(error)
        }
    }

    /// When the only thing missing is the section's class dates, ASK for them.
    ///
    /// `remember_timetable` is no longer on the local surface — dates the
    /// model supplies are dates it may have invented, and a wrong one silently
    /// puts a class on the wrong day — so a refusal that says "record them
    /// first" is a dead end for the local model: it cannot see the tool it is
    /// being sent to. The sheet is the way a teacher gives dates, and this is
    /// the call that opens it. `SectionSchedulePrompt` exists precisely for
    /// this: the runner knows nothing about windows, so it leaves a request
    /// and whichever assistant window is showing that section presents it.
    ///
    /// Fire and forget on purpose. The tool still refuses THIS turn — the
    /// dates are not there yet — and the teacher answers the sheet and asks
    /// again. Waiting inside the tool would hold the conversation open across
    /// a file picker and a Google Sheets fetch.
    private func askForTheTimetableIfThatIsWhatIsMissing(_ problem: Error) {
        guard case NextClassPlanner.Problem.noTimetable(let code, let number) = problem else {
            return
        }
        askForTheTimetable(
            courseCode: code, sectionNumber: number,
            because: "Adding the next class page needs to know which days this section meets."
        )
    }

    /// Ask for the section's class dates, when a request needed them and there
    /// are none on file.
    ///
    /// **Every command that needs the schedule goes through here.** The sheet
    /// that collects the dates already existed and was wired to exactly two
    /// paths — adding a class, and reading the timetable back — so any OTHER
    /// request depending on the schedule failed with an explanation and no way
    /// forward. A teacher who has never given their dates cannot act on "I
    /// can't find a class on Monday": what they need is not a better sentence,
    /// it is the question nobody asked them.
    private func askForTheTimetable(courseCode: String, sectionNumber: Int, because: String) {
        guard let folder = workspace.workspaceURL else {
            return
        }
        // OFFERED, not opened. A form that appears on top of the sentence
        // explaining why it appeared is a demand; this asks first.
        SectionSchedulePrompt.shared.offerToAsk(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            workingFolder: folder,
            because: because
        )
    }

    /// Whether this section has any class dates recorded at all.
    ///
    /// Asked before prompting, so a request that failed for some OTHER reason
    /// does not open a sheet about dates — which would be answering a question
    /// nobody asked.
    private func hasNoTimetable(forSection sectionNumber: Int, in course: Course) -> Bool {
        let remembered: SectionTimetable? = try? SectionTimetableStore.read(
            forSection: sectionNumber, in: course
        )
        return remembered == nil
    }

    private func planAddNextClass(_ arguments: [String: Any]) -> AssistToolOutcome {
        // Duplicating renames pages the teacher's links point at, so it is
        // described rather than planned-then-described: one description, from
        // the machinery that will do it.
        if let duplicated = duplicateClassPlan(arguments) {
            return duplicated
        }
        switch nextClassPlan(arguments) {
        case .failure(let problem):
            askForTheTimetableIfThatIsWhatIsMissing(problem)
            return AssistToolOutcome.couldNotRead(problem.localizedDescription)
        case .success(let asked):
            return AssistToolOutcome.planned(
                asked.plan.changesNothing
                    ? "The next class page already exists."
                    : "Worked out what the next class page would be.",
                plan: asked.plan.description
            )
        }
    }

    /// "Duplicate Unit 3, Day 2 as my next class."
    ///
    /// The new page is the NEXT day of the same unit — Unit 3, Day 3 — with
    /// the source's content and a date of its own from the teacher's schedule.
    ///
    /// **Making room is `ClassInsertionPlanner`'s job, not a second copy of
    /// it.** When Unit 3, Day 3 already exists, everything from there on is
    /// renamed a day later, re-dated onto the days the class actually meets,
    /// and every wikilink that pointed at a renamed page is rewritten — which
    /// is the part a teacher called a huge hassle, and the part that is
    /// dangerous to get wrong. That planner renames HIGHEST DAY FIRST, so no
    /// page is ever written over one that has not moved yet. When nothing
    /// needs moving, the same call simply adds the page at the end.
    ///
    /// The copy starts UNPUBLISHED however the source was. A page created by
    /// duplicating a published lesson is a draft of next week's, and putting
    /// it in front of students the moment it is made is the one thing it must
    /// not do.
    private func duplicateClassRequested(_ arguments: [String: Any]) -> AssistToolOutcome? {
        guard let asked = duplicateAsked(arguments) else {
            return nil
        }
        guard case .success(let request) = asked else {
            if case .failure(let message) = asked {
                return AssistToolOutcome.refused(message)
            }
            return nil
        }

        let backedUp: Bool = backUpOnceForThisConversation(
            request.located.course, forSection: request.located.sectionNumber
        )

        let outcome: ClassChangeOutcome
        do {
            outcome = try ClassInsertionPlanner.apply(request.plan, in: request.located.course)
        } catch {
            return AssistToolOutcome.refused(
                "Nothing was changed: \(error.localizedDescription)"
            )
        }

        // The new page exists as a blank class page; give it the source's
        // content, its own title and date, and leave it hidden.
        var copied: String = PageFrontmatter.settingTitle(
            in: request.sourceText, to: request.newTitle
        )
        copied = PageFrontmatter.settingCreated(
            in: copied,
            key: PageFrontmatter.createdKey(forSection: request.located.sectionNumber,
                                            isSectionLocal: true),
            to: request.newDate,
            fallbackTail: ClassPages.siblingTimeAndOffset(
                from: ClassPages.list(forSection: request.located.sectionNumber,
                                      in: request.located.course),
                forSection: request.located.sectionNumber
            )
        ).text
        copied = AssistPageVisibility.setting(
            published: false, in: copied,
            forSection: request.located.sectionNumber, isSectionLocal: true
        ).text

        let before: String? = try? String(contentsOf: request.newURL, encoding: .utf8)
        do {
            try copied.write(to: request.newURL, atomically: true, encoding: .utf8)
        } catch {
            return AssistToolOutcome.refused(
                "The page was made but could not be filled in: \(error.localizedDescription)"
            )
        }

        // Undoable ONLY when nothing else moved. A partial undo that deleted
        // the new page and left every later class renamed would be worse than
        // no undo at all, so when classes were shuffled the way back is the
        // backup taken before any of it.
        let shuffled: Bool = !request.plan.renames.isEmpty
        if !shuffled {
            history.record(AssistChange(
                whatHappened: "duplicated “\(request.sourceTitle)” as “\(request.newTitle)”",
                courseCode: request.located.course.code,
                sectionNumber: request.located.sectionNumber,
                rebuildsThePreview: false,
                files: [AssistSavedFile(fileURL: request.newURL, before: before, after: copied)]
            ))
        }

        var detail: String = "“\(request.sourceTitle)” was copied to “\(request.newTitle)”, "
                           + "dated \(request.newDate.text). It is hidden, so nothing changed on "
                           + "the site — write it, then publish when it is ready."
        if shuffled {
            detail += "\n\n" + outcome.message
            detail += "\n\nBecause other classes moved, “Undo that” will not take this back. "
                    + "The copy made before any of it is in Plantoir's Backups list."
        }
        if backedUp {
            detail += "\n\n" + AssistToolRunner.backedUpNote
        }

        return AssistToolOutcome.wrote(
            "Duplicated “\(request.sourceTitle)” as “\(request.newTitle)”.", detail: detail
        )
    }

    /// The card a teacher agrees to before a duplicate, which may move other
    /// classes.
    private func duplicateClassPlan(_ arguments: [String: Any]) -> AssistToolOutcome? {
        guard let asked = duplicateAsked(arguments) else {
            return nil
        }
        guard case .success(let request) = asked else {
            if case .failure(let message) = asked {
                return AssistToolOutcome.couldNotRead(message)
            }
            return nil
        }
        var lines: [String] = []
        lines.append("“\(request.sourceTitle)” would be copied to “\(request.newTitle)”, "
                     + "dated \(request.newDate.text).")
        lines.append("The copy starts hidden, so nothing changes on the site until you publish it.")
        if !request.plan.renames.isEmpty {
            lines.append("")
            lines.append("\(request.plan.renames.count) later "
                         + "\(request.plan.renames.count == 1 ? "class moves" : "classes move") "
                         + "a day along to make room, and the links that point at them are "
                         + "rewritten to match.")
        }
        return AssistToolOutcome.planned(
            "Worked out what duplicating “\(request.sourceTitle)” would do.",
            plan: lines.joined(separator: "\n")
        )
    }

    /// Everything both halves of a duplicate need, or why it cannot be done.
    private enum DuplicateAsked {
        case success(DuplicateRequest)
        case failure(String)
    }

    private struct DuplicateRequest {
        let located: Located
        let plan: ClassInsertionPlan
        let sourceTitle: String
        let sourceText: String
        let newTitle: String
        let newURL: URL
        let newDate: CalendarDay
    }

    private func duplicateAsked(_ arguments: [String: Any]) -> DuplicateAsked? {
        let named: String = text("duplicate", in: arguments)
        guard !named.isEmpty else {
            return nil
        }
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return .failure(refusal(from: found).message)
        }

        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: located.sectionNumber, in: located.course,
            workspaceURL: workspace.workspaceURL
        )
        guard let source = graph.page(titled: named) else {
            return .failure(
                "No page in \(located.course.code) Section \(located.sectionNumber) is called "
                + "“\(named)”."
            )
        }
        guard let numbers = UnitDay(pageTitle: source.title) else {
            return .failure(
                "“\(source.displayTitle)” isn't a numbered class page, so there is no next day "
                + "for it to become."
            )
        }

        let plan: ClassInsertionPlan
        do {
            plan = try ClassInsertionPlanner.plan(
                unit: numbers.unit, atDay: numbers.day + 1, count: 1,
                forSection: located.sectionNumber, in: located.course
            )
        } catch {
            askForTheTimetableIfDuplicatingNeedsIt(error, located: located)
            return .failure(error.localizedDescription)
        }
        guard let added = plan.added.first else {
            return .failure("There is no class date left for another class.")
        }
        guard let sourceText = try? String(contentsOf: source.fileURL, encoding: .utf8) else {
            return .failure("“\(source.displayTitle)” could not be read, so nothing was changed.")
        }

        return .success(DuplicateRequest(
            located: located,
            plan: plan,
            sourceTitle: source.displayTitle,
            sourceText: sourceText,
            newTitle: added.title,
            newURL: added.fileURL,
            newDate: added.date
        ))
    }

    /// Duplicating needs the schedule too — it dates the copy.
    private func askForTheTimetableIfDuplicatingNeedsIt(_ problem: Error, located: Located) {
        guard case ClassInsertionPlanner.Problem.noTimetable = problem else {
            return
        }
        askForTheTimetable(
            courseCode: located.course.code, sectionNumber: located.sectionNumber,
            because: "Duplicating a class needs to know which days this section meets, "
                   + "so the copy can be given a date."
        )
    }

    // MARK: - Re-dating a whole section

    /// What re-dating would do. Changes nothing.
    private func planReDateClasses(_ arguments: [String: Any]) -> AssistToolOutcome {
        switch reDatePlan(arguments) {
        case .failure(let problem):
            askForTheTimetableIfReDatingNeedsIt(problem, arguments)
            return AssistToolOutcome.couldNotRead(problem.localizedDescription)
        case .success(let asked):
            if asked.plan.changesNothing {
                let already: String = "Every page in \(asked.located.course.code) Section "
                                    + "\(asked.located.sectionNumber) is already on the day it should be."
                return AssistToolOutcome.wrote(already, detail: already)
            }
            return AssistToolOutcome.planned(
                "Worked out what re-dating that section would do.",
                plan: asked.plan.describe()
            )
        }
    }

    /// Carry it out, then put the preview back.
    private func reDateClasses(_ arguments: [String: Any]) async -> AssistToolOutcome {
        switch reDatePlan(arguments) {
        case .failure(let problem):
            askForTheTimetableIfReDatingNeedsIt(problem, arguments)
            return AssistToolOutcome.refused(problem.localizedDescription)
        case .success(let asked):
            if asked.plan.changesNothing {
                let already: String = "Every page in \(asked.located.course.code) Section "
                                    + "\(asked.located.sectionNumber) is already on the day it should be."
                return AssistToolOutcome.wrote(already, detail: already)
            }

            let backedUp: Bool = backUpOnceForThisConversation(
                asked.located.course, forSection: asked.located.sectionNumber
            )
            _ = await stopThePreviewBeforeWriting(
                for: asked.located.course, sectionNumber: asked.located.sectionNumber
            )

            let change: AssistChange
            do {
                change = try SectionReDatePlanner.apply(
                    asked.plan, forSection: asked.located.sectionNumber, in: asked.located.course
                )
            } catch {
                return AssistToolOutcome.refused(
                    "Nothing was changed: \(error.localizedDescription)"
                )
            }
            history.record(change)

            let moved: Int = asked.plan.moves.count
            let summary: String = "Re-dated \(asked.plan.classCount) "
                                + "\(asked.plan.classCount == 1 ? "class" : "classes") and "
                                + "\(moved - asked.plan.classCount) "
                                + "\((moved - asked.plan.classCount) == 1 ? "page" : "pages") "
                                + "they use."
            var detail: String = summary
            if backedUp {
                detail += "\n\n" + AssistToolRunner.backedUpNote
            }
            detail += "\n\n" + (await bringThePreviewUpToDate(
                for: asked.located.course, sectionNumber: asked.located.sectionNumber
            ))
            detail += "\n\nNothing was published or hidden, so students see no change until you "
                    + "deploy."
            return AssistToolOutcome.wrote(summary, detail: detail)
        }
    }

    private struct PlannedReDate {
        let located: Located
        let plan: SectionReDatePlan
    }

    private func reDatePlan(_ arguments: [String: Any]) -> Result<PlannedReDate, Error> {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return .failure(refusal(from: found))
        }
        do {
            let plan: SectionReDatePlan = try SectionReDatePlanner.plan(
                forSection: located.sectionNumber,
                in: located.course,
                workspaceURL: workspace.workspaceURL
            )
            return .success(PlannedReDate(located: located, plan: plan))
        } catch {
            return .failure(error)
        }
    }

    /// Re-dating needs the schedule; it IS the schedule, applied.
    private func askForTheTimetableIfReDatingNeedsIt(_ problem: Error, _ arguments: [String: Any]) {
        guard case SectionReDatePlanner.Problem.noTimetable(let code, let number) = problem else {
            return
        }
        askForTheTimetable(
            courseCode: code, sectionNumber: number,
            because: "Re-dating a section puts its classes onto the days it meets, so it needs "
                   + "those days first."
        )
    }

    private func addNextClass(_ arguments: [String: Any]) -> AssistToolOutcome {
        if let duplicated = duplicateClassRequested(arguments) {
            return duplicated
        }
        switch nextClassPlan(arguments) {
        case .failure(let problem):
            askForTheTimetableIfThatIsWhatIsMissing(problem)
            return AssistToolOutcome.refused(problem.localizedDescription)
        case .success(let asked):
            if asked.plan.changesNothing {
                return AssistToolOutcome.wrote(
                    "Nothing needed adding — that page already exists.",
                    detail: asked.plan.description
                          + "\n\nNothing was created, because the page is already there. A page with that "
                          + "name is never written over: it may be a lesson written months ago."
                )
            }

            let backedUp: Bool = backUpOnceForThisConversation(
                asked.located.course, forSection: asked.located.sectionNumber
            )

            let outcome: ClassChangeOutcome
            do {
                // Checked a second time inside `apply`, immediately before the
                // file is written: Obsidian is open in the other window, and a
                // page can appear while the teacher is deciding.
                outcome = try PlaceholderClassPlanner.apply(asked.plan, in: asked.located.course)
            } catch {
                return AssistToolOutcome.refused(
                    "Nothing was created: \(error.localizedDescription)"
                )
            }

            // Undoable, which it did not use to be. The undo list holds a
            // before-and-after copy of each file, and a created page has no
            // "before" — so it recorded nothing, and "Undo that" afterwards
            // said the conversation had changed nothing, which was a lie about
            // a page sitting in the teacher's folder. A created file is now
            // recorded with no `before` at all, and taking it back deletes it.
            var createdFiles: [AssistSavedFile] = []
            for url in outcome.created {
                guard let written = try? String(contentsOf: url, encoding: .utf8) else {
                    continue
                }
                createdFiles.append(AssistSavedFile(fileURL: url, before: nil, after: written))
            }
            if !createdFiles.isEmpty {
                history.record(AssistChange(
                    whatHappened: AssistToolRunner.namingClassesCreated(outcome.created),
                    courseCode: asked.located.course.code,
                    sectionNumber: asked.located.sectionNumber,
                    // Matches what creating them did. The page arrives
                    // unpublished, so neither making it nor taking it away
                    // changes anything the preview shows.
                    rebuildsThePreview: false,
                    files: createdFiles
                ))
            }

            var detail: String = asked.plan.description + "\n\nDone: \(outcome.message)"
            // No preview rebuild: the page starts unpublished, so rebuilding
            // would take minutes to show exactly what is on screen already.
            detail += "\n\nThe preview was not rebuilt, because an unpublished page does not appear on the "
                    + "site. Publishing it when it is written rebuilds by itself."
            detail += "\n\n" + AssistWording.aCreatedPageCanBeTakenBack
            if backedUp {
                detail += "\n\n" + AssistToolRunner.backedUpNote
            }

            var summary: String = "Added the next class page."
            if let created = asked.plan.classes.first {
                summary = "Added \(created.title), dated \(created.date.text)."
            }
            return AssistToolOutcome.wrote(summary, detail: detail)
        }
    }

    // MARK: - Pointing a page at the curriculum

    /// Read out every expectation, wording and all, and decide nothing.
    ///
    /// Which expectations fit a lesson is a judgement about MEANING. Handing
    /// back the full wording is what makes that judgement possible for whoever
    /// is driving; making it here would put a teacher's name to a claim they
    /// never agreed to.
    private func listCurriculumExpectations(_ arguments: [String: Any]) -> AssistToolOutcome {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return AssistToolOutcome.couldNotRead(refusal(from: found).message)
        }

        let all: [AssistCurriculumExpectation] = AssistCurriculumMentions.expectations(
            forSection: located.sectionNumber, in: located.course,
            workspaceURL: workspace.workspaceURL
        )
        let filter: String = text("matching", in: arguments).trimmingCharacters(in: .whitespaces)

        var matching: [AssistCurriculumExpectation] = []
        for expectation in all {
            if filter.isEmpty
                || expectation.code.localizedCaseInsensitiveContains(filter)
                || expectation.text.localizedCaseInsensitiveContains(filter) {
                matching.append(expectation)
            }
        }

        if matching.isEmpty {
            var reason: String = "No curriculum expectation in \(located.course.code) "
                               + "matches “\(filter)”."
            if filter.isEmpty {
                reason = "\(located.course.code) has no curriculum expectations — this course was "
                       + "installed without them."
            }
            return AssistToolOutcome.read("Nothing matched in \(located.course.code).", detail: reason)
        }

        var lines: [String] = []
        for expectation in matching {
            lines.append("\(expectation.code)  \(expectation.text)")
        }
        let word: String = matching.count == 1 ? "expectation" : "expectations"
        return AssistToolOutcome.read(
            "Found \(matching.count) curriculum \(word) in \(located.course.code).",
            detail: lines.joined(separator: "\n")
        )
    }

    private struct PlannedMentions {
        let located: Located
        let plan: AssistCurriculumMentionsPlan
    }

    private func mentionsPlan(
        _ arguments: [String: Any]
    ) -> Result<PlannedMentions, AssistToolRefusal> {
        let found: Result<Located, AssistToolRefusal> = locate(arguments)
        guard case .success(let located) = found else {
            return .failure(refusal(from: found))
        }

        let title: String = text("page", in: arguments)
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: located.sectionNumber, in: located.course,
            workspaceURL: workspace.workspaceURL
        )
        guard let page = graph.page(titled: title) else {
            return .failure(.noSuchPage(title, located.course.code, located.sectionNumber))
        }
        guard let pageText = try? String(contentsOf: page.fileURL, encoding: .utf8) else {
            return .failure(.unreadablePage(page.displayTitle))
        }

        let plan: AssistCurriculumMentionsPlan = AssistCurriculumMentions.plan(
            codes: codes("codes", in: arguments),
            page: page,
            pageText: pageText,
            expectations: AssistCurriculumMentions.expectations(
                forSection: located.sectionNumber, in: located.course,
                workspaceURL: workspace.workspaceURL
            ),
            courseCode: located.course.code,
            sectionNumber: located.sectionNumber
        )
        return .success(PlannedMentions(located: located, plan: plan))
    }

    private func planCurriculumMentions(_ arguments: [String: Any]) -> AssistToolOutcome {
        switch mentionsPlan(arguments) {
        case .failure(let refusal):
            return AssistToolOutcome.couldNotRead(refusal.message)
        case .success(let asked):
            return AssistToolOutcome.planned(
                asked.plan.changesNothing
                    ? "Nothing needs adding to “\(asked.plan.pageTitle)”."
                    : "Worked out what pointing “\(asked.plan.pageTitle)” at those expectations would do.",
                plan: asked.plan.describe()
            )
        }
    }

    private func addCurriculumMentions(_ arguments: [String: Any]) -> AssistToolOutcome {
        switch mentionsPlan(arguments) {
        case .failure(let refusal):
            return AssistToolOutcome.refused(refusal.message)
        case .success(let asked):
            if asked.plan.changesNothing {
                return AssistToolOutcome.wrote(
                    "Nothing needed adding.",
                    detail: asked.plan.describe()
                          + "\n\nNothing was changed, because nothing needed to be."
                )
            }

            // Before anything is touched — but only the first time in a
            // conversation. The undo history covers the rest of it; the
            // backup outlives the conversation.
            let backedUp: Bool = backUpOnceForThisConversation(
                asked.located.course, forSection: asked.located.sectionNumber
            )

            let change: AssistChange
            do {
                change = try AssistCurriculumMentions.apply(asked.plan)
            } catch {
                return AssistToolOutcome.refused(
                    "Nothing was changed: \(error.localizedDescription)"
                )
            }
            history.record(change)

            let word: String = asked.plan.adding.count == 1 ? "expectation" : "expectations"
            let summary: String = "Added \(asked.plan.adding.count) curriculum \(word) to "
                + "“\(asked.plan.pageTitle)”."
            var detail: String = asked.plan.describe() + "\n\nDone: \(summary.dropLast()) — "
                + AssistCurriculumMentions.codeList(of: asked.plan.adding) + "."
            detail += "\n\nThey are wrapped in the curriculum markers, so a course installed without "
                    + "curriculum still builds. Look the page over in Plantoir."
            if backedUp {
                detail += "\n\n" + AssistToolRunner.backedUpNote
            }
            detail += "\n\nThis changed the teacher's files. It did not put anything in front of students — "
                    + "deploying does that, and only when they ask."

            return AssistToolOutcome.wrote(summary, detail: detail)
        }
    }

    // MARK: - Finding the course and section

    /// A course and section the model named, both found.
    private struct Located {
        let course: Course
        let sectionNumber: Int
    }

    private func locate(_ arguments: [String: Any]) -> Result<Located, AssistToolRefusal> {
        if workspace.workspaceURL == nil {
            return .failure(.noWorkingFolder)
        }

        let code: String = text("course", in: arguments).trimmingCharacters(in: .whitespaces)
        var course: Course? = nil
        for candidate in workspace.courses where candidate.code.lowercased() == code.lowercased() {
            course = candidate
        }
        guard let course else {
            return .failure(.noSuchCourse(code))
        }

        var numbers: [Int] = course.sectionNumbers
        numbers.sort()
        if let asked = number("section", in: arguments) {
            for candidate in numbers where candidate == asked {
                return .success(Located(course: course, sectionNumber: candidate))
            }
            return .failure(.noSuchSection(course.code, asked))
        }
        // No section given. A course with exactly one section has only one
        // answer, so that is not a guess; anything else is, and is refused.
        if numbers.count == 1, let only = numbers.first {
            return .success(Located(course: course, sectionNumber: only))
        }
        return .failure(.noSuchSection(course.code, 0))
    }

    private func refusal(from result: Result<Located, AssistToolRefusal>) -> AssistToolRefusal {
        switch result {
        case .failure(let refusal):
            return refusal
        case .success:
            return .noWorkingFolder
        }
    }

    /// Where a course's site goes, named rather than described.
    static func destination(of course: Course) -> String {
        if course.configuration.deploysToLocalFolder {
            return "a folder on this computer"
        }
        if course.configuration.deploysToCloudflare {
            return "Cloudflare Pages"
        }
        return "Netlify"
    }

    // MARK: - Reading the model's arguments

    /// The model sends numbers as numbers on a good day and as strings on
    /// another; both are read, because a dropped argument reads to a teacher as
    /// the assistant ignoring them.
    private func text(_ key: String, in arguments: [String: Any]) -> String {
        guard let value = arguments[key] else {
            return ""
        }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private func number(_ key: String, in arguments: [String: Any]) -> Int? {
        guard let value = arguments[key] else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // No `flag` reader lives here any more, and none should come back. The
    // last boolean on the surface was `includeLinked`, and reading a boolean
    // out of the model's arguments is how a verb gets inverted under pressure.

    /// A list of page names, however the model chose to send it.
    ///
    /// Semicolons, not commas: the class pages in these courses are called
    /// "Unit 2, Day 3", so a comma-separated list of them cuts every name in
    /// half. A JSON array is accepted too, because some builds send one whatever
    /// the schema says.
    private func names(_ key: String, in arguments: [String: Any]) -> [String] {
        var raw: [String] = []
        if let list = arguments[key] as? [Any] {
            for entry in list {
                if let string = entry as? String {
                    raw.append(string)
                }
            }
        } else if let string = arguments[key] as? String {
            for piece in string.components(separatedBy: CharacterSet(charactersIn: ";\n")) {
                raw.append(piece)
            }
        }

        var names: [String] = []
        for entry in raw {
            let tidied: String = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tidied.isEmpty {
                names.append(tidied)
            }
        }
        return names
    }

    /// A list of curriculum expectation codes, however the model chose to send
    /// it.
    ///
    /// Commas here, unlike the page lists, because `A1.1` has no comma in it
    /// and commas are what the Windows server's schema asks for. Semicolons and
    /// newlines are read too — a model that separated them another way still
    /// said exactly which expectations it meant.
    private func codes(_ key: String, in arguments: [String: Any]) -> [String] {
        var raw: [String] = []
        if let list = arguments[key] as? [Any] {
            for entry in list {
                if let string = entry as? String {
                    raw.append(string)
                }
            }
        } else if let string = arguments[key] as? String {
            for piece in string.components(separatedBy: CharacterSet(charactersIn: ",;\n")) {
                raw.append(piece)
            }
        }

        var found: [String] = []
        for entry in raw {
            let tidied: String = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tidied.isEmpty {
                found.append(tidied)
            }
        }
        return found
    }

    /// A list of dates, however the model chose to separate them.
    ///
    /// Deliberately forgiving about the SEPARATOR and not at all forgiving
    /// about the dates themselves. `2026-09-08` has no comma and no semicolon
    /// in it, so either can be read as a separator without risking a date being
    /// cut in half — and a whole year's timetable refused over a punctuation
    /// mark would cost a teacher the five minutes this is meant to save. What
    /// each piece MEANS is still read strictly, one form only, by
    /// `SectionTimetableStore`, which refuses a partial list whole.
    ///
    /// A space is NOT a separator, though a list of dates could be split on one
    /// safely enough. It is left out for the sake of the refusal: "next
    /// Tuesday" quoted back whole is something a teacher can correct, where
    /// "“next” and “Tuesday” aren't dates" reads like the tool misunderstanding
    /// them twice.
    private func days(_ key: String, in arguments: [String: Any]) -> [String] {
        var raw: [String] = []
        if let list = arguments[key] as? [Any] {
            for entry in list {
                if let string = entry as? String {
                    raw.append(string)
                }
            }
        } else if let string = arguments[key] as? String {
            let separators: CharacterSet = CharacterSet(charactersIn: ",;\n\t")
            for piece in string.components(separatedBy: separators) {
                raw.append(piece)
            }
        }

        var found: [String] = []
        for entry in raw {
            let tidied: String = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tidied.isEmpty {
                found.append(tidied)
            }
        }
        return found
    }

    /// A day the teacher named: `2026-09-15`, or the handful of words the
    /// assistant window's fixed phrasings send straight through.
    static func day(named raw: String, today: CalendarDay) -> CalendarDay? {
        let tidied: String = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch tidied {
        case "today":
            return today
        case "tomorrow":
            return shifting(today, byDays: 1)
        case "yesterday":
            return shifting(today, byDays: -1)
        default:
            if let named = AssistToolRunner.dayNamedByWeekday(tidied, from: today) {
                return named
            }
            return CalendarDay(text: raw)
        }
    }

    /// "monday" → the next Monday, counting today when today IS a Monday.
    ///
    /// **Resolved HERE rather than by the model**, which is the whole point of
    /// it existing. "Publish Monday's class" is one of the window's fixed
    /// phrasings, so the word "monday" arrives literally and never reaches the
    /// model — and a date worked out in code cannot be a date the model
    /// invented. The model can still do the conversion for a sentence a
    /// teacher phrases their own way; it is measured at 10/10 when it is told
    /// what today is, and this path does not depend on that.
    ///
    /// **Today counts as a match.** Asked on a Monday for "Monday's class", a
    /// teacher means the class they are about to teach, not the one a week
    /// away. The same reading a person would give it.
    ///
    /// Only forwards, within the next seven days. "Publish Monday's class" is
    /// said while preparing, and a teacher who means a class already taught
    /// has its Unit and Day in front of them and will say so.
    static func dayNamedByWeekday(_ lowercased: String, from today: CalendarDay) -> CalendarDay? {
        var wanted: String = lowercased
        // "monday's" and "monday" are the same request; the apostrophe belongs
        // to the phrasing, not to the day.
        for suffix in ["'s", "’s"] where wanted.hasSuffix(suffix) {
            wanted = String(wanted.dropLast(suffix.count))
        }
        var isAWeekday: Bool = false
        for name in ["monday", "tuesday", "wednesday", "thursday",
                     "friday", "saturday", "sunday"] where name == wanted {
            isAWeekday = true
        }
        if !isAWeekday {
            return nil
        }
        var candidate: CalendarDay = today
        for _ in 0...7 {
            if candidate.weekdayName.lowercased() == wanted {
                return candidate
            }
            guard let next = shifting(candidate, byDays: 1) else {
                return nil
            }
            candidate = next
        }
        return nil
    }

    /// A moment the teacher named: `2026-09-09 06:30`, in 24-hour time and in
    /// this Mac's own time zone.
    ///
    /// Deliberately strict about the FORM, and deliberately forgiving about the
    /// separator — a model that writes `T` between the date and the time has
    /// still said exactly which minute it meant, and refusing that would cost a
    /// teacher a scheduled deploy over a character.
    static func moment(named raw: String) -> Date? {
        let tidied: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if tidied.isEmpty {
            return nil
        }
        let patterns: [String] = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss"]
        for pattern in patterns {
            let formatter: DateFormatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = pattern
            if let moment = formatter.date(from: tidied) {
                return moment
            }
        }
        return nil
    }

    /// A day this many days along from another.
    static func shifting(_ day: CalendarDay, byDays offset: Int) -> CalendarDay? {
        var components: DateComponents = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        guard let moment = CalendarDay.calendar.date(from: components),
              let moved = CalendarDay.calendar.date(byAdding: .day, value: offset, to: moment) else {
            return nil
        }
        let parts: DateComponents = CalendarDay.calendar.dateComponents(
            [.year, .month, .day], from: moved
        )
        guard let year = parts.year, let month = parts.month, let dayNumber = parts.day else {
            return nil
        }
        return CalendarDay(year: year, month: month, day: dayNumber)
    }

    // MARK: - How much to say

    /// A course runs to a couple of hundred pages — the sample course alone has
    /// 198, most of them curriculum expectations nobody is asking about.
    /// Returning all of them buries the answer and, for a small local model,
    /// fills the context before the question is even considered.
    static let mostPagesListed: Int = 60

    /// How many of each kind to name before summarising.
    static let mostListed: Int = 15

    /// How much of one page to hand back.
    static let mostCharactersRead: Int = 8000
}
