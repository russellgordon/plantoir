import AppKit
import SwiftUI
import Observation

/// What the start-of-the-year sheet is for: getting a section ready, or
/// taking that back (#96). The undo is a preview sheet too, never one click.
enum StartOfYearSheetMode: Equatable {
    case getReady
    case undo
}

/// A request to open the sheet, from the section's context menu.
struct StartOfYearRequest: Identifiable {

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int
    let mode: StartOfYearSheetMode

    // MARK: - Computed properties

    var id: String {
        return "\(course.code)-section\(sectionNumber)-\(mode == .undo ? "undo" : "ready")"
    }
}

/// Everything the sheet shows and does, apart from the drawing — so it can be
/// tested without a window (`StartOfYearSheetModelTests`).
@Observable
@MainActor
final class StartOfYearSheetModel {

    // MARK: - Types

    enum Stage {
        case reading
        case ready(StartOfYearPlan)
        case working
        case done(StartOfYearPreparation.Done)
        case undoReady(StartOfYearUndoRegistry.Entry, putBack: [URL], skipped: [URL])
        case undone(StartOfYearPreparation.Undone, backupFileName: String)
        case problem(String)
    }

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int
    let workspaceURL: URL
    private(set) var mode: StartOfYearSheetMode

    /// Said above the list when Go found the section had changed.
    var notice: String?

    private(set) var stage: Stage = .reading

    /// The day "already taught" is counted from. Injectable for tests.
    private let readToday: () -> CalendarDay

    /// How the backup is made. Injectable so a test can make it fail.
    private let backUp: (Course, URL) async throws -> URL

    /// When this section's own scheduled deploy will run, if one is set.
    /// Injectable so a test can show the sheet with that warning (#589's
    /// worst case) without setting a real one.
    private let readScheduledDeploy: (Course, Int, URL) -> Date?

    // MARK: - Computed properties

    var title: String {
        switch mode {
        case .getReady:
            return StartOfYearWording.sheetTitle(course: course.displayCode, section: String(sectionNumber))
        case .undo:
            return StartOfYearWording.undoTitle(course: course.displayCode, section: String(sectionNumber))
        }
    }

    // MARK: - Initializer

    init(course: Course,
         sectionNumber: Int,
         workspaceURL: URL,
         mode: StartOfYearSheetMode,
         today: @escaping () -> CalendarDay = { return CalendarDay.today() },
         backUp: @escaping (Course, URL) async throws -> URL = { course, coursesDirectoryURL in
             return try await CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL, madeBy: .teacher)
         },
         scheduledDeploy: @escaping (Course, Int, URL) -> Date? = { course, sectionNumber, workspaceURL in
             return ScheduledDeploy.nextRun(
                 courseCode: course.code, sectionNumber: sectionNumber, inWorkingFolder: workspaceURL
             )
         }) {
        self.course = course
        self.sectionNumber = sectionNumber
        self.workspaceURL = workspaceURL
        self.mode = mode
        self.readToday = today
        self.backUp = backUp
        self.readScheduledDeploy = scheduledDeploy
    }

    // MARK: - Functions

    /// Read the section and show what would happen.
    func load() {
        switch mode {
        case .getReady:
            let scheduled: Date? = readScheduledDeploy(course, sectionNumber, workspaceURL)
            switch StartOfYearPlanner.plan(
                forSection: sectionNumber, in: course, workspaceURL: workspaceURL,
                today: readToday(), scheduledDeploy: scheduled
            ) {
            case .failure(let problem):
                stage = .problem(problem.sentence)
            case .success(let plan):
                stage = .ready(plan)
            }
        case .undo:
            let registry: StartOfYearUndoRegistry = StartOfYearUndoRegistry.shared
            guard let entry = registry.entry(
                folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber
            ) else {
                stage = .problem(StartOfYearWording.undoHasEnded)
                return
            }
            registry.refreshSchedule(
                folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber,
                workingFolder: workspaceURL
            )
            if registry.whyItEnded(entry, forSection: sectionNumber, in: course, workspaceURL: workspaceURL) != nil {
                registry.forget(folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber)
                stage = .problem(
                    StartOfYearWording.undoHasEnded + " "
                        + StartOfYearWording.backupHoldsIt(backup: entry.backupFileName)
                )
                return
            }
            let preview: (putBack: [URL], skipped: [URL]) = StartOfYearPreparation.whatAnUndoWouldDo(entry)
            stage = .undoReady(entry, putBack: preview.putBack, skipped: preview.skipped)
        }
    }

    /// Press Go.
    func goAhead() async {
        guard case .ready(let plan) = stage else {
            return
        }
        stage = .working
        let outcome: StartOfYearPreparation.Outcome = await StartOfYearPreparation.carryOut(
            shownFingerprint: plan.fingerprint,
            forSection: sectionNumber,
            in: course,
            workspaceURL: workspaceURL,
            today: readToday(),
            backUp: backUp
        )
        switch outcome {
        case .done(let done):
            stage = .done(done)
        case .changedSinceShown(let fresh):
            notice = StartOfYearWording.changedSinceShown
            stage = .ready(fresh)
        case .refused(let sentence):
            stage = .problem(sentence)
        }
    }

    /// Press "Put Them Back".
    func undo() async {
        guard case .undoReady(let entry, _, _) = stage else {
            return
        }
        // A deploy that began while this sheet was open ends the undo; the
        // sheet still holds the entry, so ask again rather than trusting it
        // (the review's L3).
        if CourseActivity.coursePublishIsRunning(folderPath: workspaceURL.path, courseCode: course.code)
            || StartOfYearUndoRegistry.shared.entry(
                folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber
            ) == nil {
            stage = .problem(
                StartOfYearWording.undoHasEnded + " " + StartOfYearWording.backupHoldsIt(backup: entry.backupFileName)
            )
            return
        }
        stage = .working
        let undone: StartOfYearPreparation.Undone = await StartOfYearPreparation.undo(
            entry, forSection: sectionNumber, in: course, workspaceURL: workspaceURL
        )
        stage = .undone(undone, backupFileName: entry.backupFileName)
    }

    /// Straight from the result to the undo sheet, in the same window.
    func offerUndo() {
        mode = .undo
        notice = nil
        load()
    }
}

/// The sheet: what getting a section ready would do, every page with its
/// reason, and the result — or, in undo mode, what would go back (#96).
///
/// The plan is a table since #589 — a row for every page going into draft,
/// with its folder and why, the look #524 gave Publish Pages — between two
/// capped areas: what must be read before Go above it, and what stays and
/// what follows below it. Its height budget is in `tallestPlanTable`.
struct StartOfYearSheet: View {

    // MARK: - Stored properties

    @State var model: StartOfYearSheetModel

    /// The table's order: plan order (classes, then pages) to begin with; a
    /// column header sorts by that column (#589, as #524).
    @State var planSortOrder: [KeyPathComparator<StartOfYearPlanRow>] = [KeyPathComparator(\.position)]

    @Environment(\.dismiss) var dismiss

    /// The one budget for the plan (#589): the whole sheet, in its worst case
    /// — the "changed since" notice, all three warnings, a page with no room
    /// for a key, links left pointing at hidden pages and more rows than fit —
    /// must stay within `CopyPageChecklist.tallestSheet` (620 pt, a 13-inch Air
    /// at "Larger Text"), or Cancel and Go go off the bottom of the screen.
    /// Measured with the real sheet (`StartOfYearPlanTableTests`): about 52
    /// for the title band, 20 for the bottom margin, 12 between each part,
    /// about 22 for the buttons and 36 for the two summary lines, which leaves
    /// about 440 for the three parts that grow. #524's twelve rows (318 pt)
    /// did not fit: they left about 120 for everything above and below.
    ///
    /// Seven rows on one line each; fewer when a reason takes two lines.
    static let mostPlanRowsShown: Int = 7

    /// The notice, the warnings and the intro, above the table. The warnings
    /// come FIRST, because they are what must be read before Go, and the cap
    /// is set so that in the worst case — the notice and all three warnings,
    /// the scheduled deploy's on two lines — every warning AND the first line
    /// of the intro are in view without scrolling; only the rest of the intro
    /// scrolls (#589's implementation review, S1: at 100 pt the third warning,
    /// the one about a scheduled deploy, was below the fold, and on a first
    /// showing with three warnings none of the intro was). Pinned by
    /// `StartOfYearPlanTableTests.testEveryWarningAndTheIntrosFirstLineAreInView`.
    static let tallestPlanIntro: CGFloat = 156

    /// The gap between the notice, the warnings and the intro: 6 rather than
    /// 8, which is what lets the cap above hold them all.
    static let planIntroSpacing: CGFloat = 6

    /// Everything under the table: already in draft, no room for a key, what
    /// stays, the links left, publishing from now on, the undo's limit.
    static let tallestPlanNotes: CGFloat = 76

    /// A row whose reason takes two lines (#589's plan review: the longest
    /// reason, "only “…” links to it, and students will not see that page",
    /// is about 400 pt and was cut at its useful half on one line). MEASURED
    /// on the real bordered table, macOS 26: 24 pt on one line, 40 on two.
    static let twoLineRowHeight: CGFloat = 40

    /// The widest reason that still fits on one line in the Why column, in
    /// the system font. MEASURED: in the 560-point sheet the column is 254 pt
    /// wide (248.5 when the table shows a scroll bar), and text up to about
    /// 250 pt stays on one line. Set a little under the narrower case, so a
    /// misjudged row leaves a band of a few points rather than a scroll.
    static let widestOneLineReason: CGFloat = 244

    // MARK: - Computed properties

    static var tallestPlanTable: CGFloat {
        return ListTableMetrics.height(forRowCount: mostPlanRowsShown, showsHeader: true)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .ready(let plan) = model.stage {
                // No outer scroll view for the plan (#589): the table scrolls
                // inside itself, and a scroll inside a scroll is the shape
                // every list here has refused.
                planView(plan)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 200, maxHeight: 460)
            }
            buttons
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle(model.title)
        .frame(width: 560)
        .onAppear {
            model.load()
        }
        // `.contain` BEFORE the identifier, or not at all (#366, the rule of
        // #353): SwiftUI applies an identifier on a stack to every element
        // inside it, and the inner identifiers (startOfYearGo, startOfYearUndo,
        // startOfYearOfferUndo) never reach the tree — Cancel and Go both read
        // back as "startOfYearSheet". After the identifier it does nothing;
        // `ContainerIdentifierTripwireTests` checks the order.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startOfYearSheet")
    }

    // MARK: - Parts

    @ViewBuilder
    var content: some View {
        switch model.stage {
        case .reading, .working:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .problem(let sentence):
            Text(sentence)
        case .ready:
            // Drawn by `body`, outside the scroll view (#589).
            EmptyView()
        case .done(let done):
            Text(StartOfYearWording.done(pages: StartOfYearWording.pages(done.pagesWritten)))
            if !done.leftAlone.isEmpty {
                Text(AssistPublishPlan.sayingPagesWithNoRoomForAKey(named: done.leftAlone))
                    .foregroundStyle(.orange)
            }
            if let note = done.previewNote {
                Text(note)
                    .foregroundStyle(.secondary)
            }
            Text(StartOfYearWording.undoAvailable(backup: done.backupFileName))
                .foregroundStyle(.secondary)
            Text(StartOfYearWording.undoEndsWhenYouQuit)
                .foregroundStyle(.secondary)
        case .undoReady(_, let putBack, let skipped):
            if putBack.isEmpty && skipped.isEmpty {
                // Every page is already back (#555): neither list has anything.
                Text(StartOfYearWording.undoAllAlreadyBack)
            } else {
                Text(StartOfYearWording.undoIntro(pages: StartOfYearWording.pages(putBack.count)))
            }
            fileList(putBack)
            if !skipped.isEmpty {
                Text(StartOfYearWording.undoSkipped(pages: StartOfYearWording.pages(skipped.count)))
                    .foregroundStyle(.orange)
                fileList(skipped)
            }
            Text(StartOfYearWording.undoEndsWhenYouQuit)
                .foregroundStyle(.secondary)
        case .undone(let undone, let backup):
            if undone.skipped.isEmpty && undone.putBack == 0 {
                Text(StartOfYearWording.undoAllAlreadyBack)
            } else if undone.skipped.isEmpty {
                Text(StartOfYearWording.undone(pages: StartOfYearWording.pages(undone.putBack)))
            } else {
                Text(StartOfYearWording.undone(pages: StartOfYearWording.pages(undone.putBack)))
                Text(StartOfYearWording.undoLeftSome(
                    pages: StartOfYearWording.pages(undone.skipped.count), backup: backup
                ))
                .foregroundStyle(.orange)
            }
        }
    }

    /// The plan (#589): what must be read before Go; a summary over a
    /// read-only table with a row for every page going into draft; and the
    /// rest of what the plan says, under it. Every sentence is the one it
    /// was before the table; only the two lists of lines became rows.
    @ViewBuilder
    func planView(_ plan: StartOfYearPlan) -> some View {
        let first: String = plan.firstClass.displayTitle
        let rows: [StartOfYearPlanRow] = plan.tableRows()
        CappedScrollArea(cap: StartOfYearSheet.tallestPlanIntro) {
            VStack(alignment: .leading, spacing: StartOfYearSheet.planIntroSpacing) {
                StartOfYearSheet.mustBeReadBeforeGo(plan, notice: model.notice)
                Text(StartOfYearWording.intro(first: first, noun: plan.noun.singular))
                    .fixedSize(horizontal: false, vertical: true)
                if plan.changesNothing {
                    Text(StartOfYearWording.nothingToDo(first: first, nouns: plan.noun.plural))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("startOfYearPlanIntro")
        }
        if !rows.isEmpty {
            planSummary(plan)
            planTable(rows)
        }
        CappedScrollArea(cap: StartOfYearSheet.tallestPlanNotes) {
            planNotes(plan, first: first)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("startOfYearPlanNotes")
        }
    }

    /// The notice and the warnings, first in the area above the table. Its
    /// own function so a test can lay out exactly these and check they fit
    /// under the area's cap.
    @ViewBuilder
    static func mustBeReadBeforeGo(_ plan: StartOfYearPlan, notice: String?) -> some View {
        if let notice {
            Text(notice)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(plan.warnings(), id: \.self) { (warning: String) in
            Label(warning, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The two headings the lists had, as the lines over the table: how many
    /// classes, and how many other pages.
    func planSummary(_ plan: StartOfYearPlan) -> some View {
        let classChanges: Int = plan.draftsThatChange(plan.classDrafts).count
        let pageChanges: Int = plan.draftsThatChange(plan.pageDrafts).count
        return VStack(alignment: .leading, spacing: 4) {
            if classChanges > 0 {
                Text(StartOfYearWording.classesHeading(
                    classes: StartOfYearWording.counted(classChanges, noun: plan.noun)
                ))
            }
            if pageChanges > 0 {
                Text(StartOfYearWording.pagesHeading(pages: StartOfYearWording.pages(pageChanges)))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startOfYearPlanSummary")
    }

    /// The table: Page, Folder and Why, every page going into draft — not
    /// capped, it scrolls inside itself past `tallestPlanTable`. No
    /// `selection:`: the rows are read, not chosen.
    func planTable(_ rows: [StartOfYearPlanRow]) -> some View {
        return Table(rows.sorted(using: planSortOrder), sortOrder: $planSortOrder) {
            TableColumn(AssistWording.menuPlanPageColumn, value: \.title) { (row: StartOfYearPlanRow) in
                Text(row.title)
                    .help(row.title)
            }
            .width(min: 90, max: 140)
            TableColumn(AssistWording.menuPlanFolderColumn, value: \.folder) { (row: StartOfYearPlanRow) in
                Text(row.folder)
                    .foregroundStyle(.secondary)
                    .help(row.folder)
            }
            .width(min: 60, max: 100)
            TableColumn(StartOfYearWording.reasonColumn, value: \.why) { (row: StartOfYearPlanRow) in
                // Two lines, so the longest reason reads whole; the tooltip
                // has it whole when a long title makes it longer still.
                Text(row.why)
                    .lineLimit(2)
                    .help(row.why)
            }
            // The rest of the width: it carries the longest words.
            .width(min: 220, ideal: 300)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: StartOfYearSheet.planTableHeight(for: rows))
        .accessibilityIdentifier("startOfYearPlanTable")
    }

    /// Everything the plan says under its lists, word for word as before.
    @ViewBuilder
    func planNotes(_ plan: StartOfYearPlan, first: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if plan.classesAlreadyInDraft > 0 {
                Text(StartOfYearWording.alreadyInDraft(
                    classes: StartOfYearWording.counted(plan.classesAlreadyInDraft, noun: plan.noun)
                ))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !plan.publishPlan.noRoomForAKey.isEmpty {
                Text(AssistPublishPlan.sayingPagesWithNoRoomForAKey(plan.publishPlan.noRoomForAKey))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(StartOfYearWording.staysHeading(
                pages: StartOfYearWording.pages(1 + plan.firstClassPages.count + plan.keyLinksPages.count)
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• " + StartOfYearWording.staysFirstClass(
                        first: first, pages: StartOfYearWording.pages(plan.firstClassPages.count)
                    ))
                    if !plan.keyLinksPages.isEmpty {
                        Text("• " + StartOfYearWording.staysKeyLinks(
                            pages: StartOfYearWording.pages(max(0, plan.keyLinksPages.count - 1))
                        ))
                    }
                    Text("• " + StartOfYearWording.staysEverythingElse)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !plan.danglingSources.isEmpty {
                DisclosureGroup(StartOfYearWording.linksLeftHeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.danglingSources, id: \.page.relativePath) { (source: StartOfYearDanglingSource) in
                            Text("• " + StartOfYearWording.linksLeftLine(
                                name: plan.name(of: source.page),
                                links: source.hiddenTargets.count == 1
                                    ? "1 link" : "\(source.hiddenTargets.count) links"
                            ))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text(StartOfYearWording.publishingFromNowOn(noun: plan.noun.singular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(StartOfYearWording.undoEndsWhenYouQuit)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The undo's lists: each file by its title, never its path (#362).
    func fileList(_ urls: [URL]) -> some View {
        let names: [String] = StartOfYearPageNaming.names(
            ofFilesAt: urls, courseDirectoryURL: model.course.directoryURL, courseCode: model.course.code
        )
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(names.indices, id: \.self) { index in
                Text("• " + names[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var buttons: some View {
        HStack {
            Spacer()
            switch model.stage {
            case .ready(let plan):
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(StartOfYearWording.goButton) {
                    Task { @MainActor in
                        await model.goAhead()
                    }
                }
                .defaultButton(isEnabled: !plan.changesNothing)
                .accessibilityIdentifier("startOfYearGo")
            case .undoReady(_, let putBack, _):
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(StartOfYearWording.undoButton) {
                    Task { @MainActor in
                        await model.undo()
                    }
                }
                .defaultButton(isEnabled: !putBack.isEmpty)
                .accessibilityIdentifier("startOfYearUndo")
            case .reading, .working:
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .disabled(true)
            case .done:
                Button(StartOfYearWording.undoButtonAfterward) {
                    model.offerUndo()
                }
                .accessibilityIdentifier("startOfYearOfferUndo")
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            case .undone, .problem:
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Functions

    /// The table's height: every row, up to `tallestPlanTable`, then it
    /// scrolls inside itself. A `Table` has no natural height, and its rows
    /// are not all one height here — a reason over `widestOneLineReason`
    /// takes two lines — so each row is counted at the height it will draw.
    static func planTableHeight(for rows: [StartOfYearPlanRow]) -> CGFloat {
        var height: CGFloat = ListTableMetrics.headerHeight + ListTableMetrics.borderAllowance
        if rows.isEmpty {
            height += ListTableMetrics.rowHeight
        }
        for row in rows {
            if reasonFitsOnOneLine(row.why) {
                height += ListTableMetrics.rowHeight
            } else {
                height += twoLineRowHeight
            }
            if height >= tallestPlanTable {
                return tallestPlanTable
            }
        }
        return height
    }

    /// Whether a reason fits on one line of the Why column.
    static func reasonFitsOnOneLine(_ why: String) -> Bool {
        let font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let width: CGFloat = (why as NSString).size(withAttributes: [.font: font]).width
        return width <= widestOneLineReason
    }
}
