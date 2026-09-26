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
    private let backUp: (Course, URL) throws -> URL

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
         backUp: @escaping (Course, URL) throws -> URL = { course, coursesDirectoryURL in
             return try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL, madeBy: .teacher)
         }) {
        self.course = course
        self.sectionNumber = sectionNumber
        self.workspaceURL = workspaceURL
        self.mode = mode
        self.readToday = today
        self.backUp = backUp
    }

    // MARK: - Functions

    /// Read the section and show what would happen.
    func load() {
        switch mode {
        case .getReady:
            let scheduled: Date? = ScheduledDeploy.nextRun(
                courseCode: course.code, sectionNumber: sectionNumber, inWorkingFolder: workspaceURL
            )
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
struct StartOfYearSheet: View {

    // MARK: - Stored properties

    @State var model: StartOfYearSheetModel

    @Environment(\.dismiss) var dismiss

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title)
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200, maxHeight: 460)
            buttons
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            model.load()
        }
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
        case .ready(let plan):
            planView(plan)
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
            Text(StartOfYearWording.undoIntro(pages: StartOfYearWording.pages(putBack.count)))
            fileList(putBack)
            if !skipped.isEmpty {
                Text(StartOfYearWording.undoSkipped(pages: StartOfYearWording.pages(skipped.count)))
                    .foregroundStyle(.orange)
                fileList(skipped)
            }
            Text(StartOfYearWording.undoEndsWhenYouQuit)
                .foregroundStyle(.secondary)
        case .undone(let undone, let backup):
            if undone.skipped.isEmpty {
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

    @ViewBuilder
    func planView(_ plan: StartOfYearPlan) -> some View {
        let first: String = plan.firstClass.displayTitle
        if let notice = model.notice {
            Text(notice)
                .foregroundStyle(.orange)
        }
        Text(StartOfYearWording.intro(first: first, noun: plan.noun.singular, nouns: plan.noun.plural))
        ForEach(plan.warnings(), id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        if plan.changesNothing {
            Text(StartOfYearWording.nothingToDo(first: first, nouns: plan.noun.plural))
        }
        let classChanges: [StartOfYearDraft] = plan.draftsThatChange(plan.classDrafts)
        if !classChanges.isEmpty {
            DisclosureGroup(StartOfYearWording.classesHeading(
                classes: StartOfYearWording.counted(classChanges.count, noun: plan.noun)
            )) {
                draftList(classChanges, first: first, showingPath: false)
            }
        }
        let pageChanges: [StartOfYearDraft] = plan.draftsThatChange(plan.pageDrafts)
        if !pageChanges.isEmpty {
            DisclosureGroup(StartOfYearWording.pagesHeading(
                pages: StartOfYearWording.pages(pageChanges.count), nouns: plan.noun.plural
            )) {
                draftList(pageChanges, first: first, showingPath: true)
            }
        }
        if plan.classesAlreadyInDraft > 0 {
            Text(StartOfYearWording.alreadyInDraft(
                classes: StartOfYearWording.counted(plan.classesAlreadyInDraft, noun: plan.noun)
            ))
            .foregroundStyle(.secondary)
        }
        if !plan.publishPlan.noRoomForAKey.isEmpty {
            Text(AssistPublishPlan.sayingPagesWithNoRoomForAKey(plan.publishPlan.noRoomForAKey))
                .foregroundStyle(.orange)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !plan.danglingSources.isEmpty {
            DisclosureGroup(StartOfYearWording.linksLeftHeading) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.danglingSources, id: \.page.relativePath) { source in
                        Text("• " + StartOfYearWording.linksLeftLine(
                            page: source.page.displayTitle,
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
        Text(StartOfYearWording.undoEndsWhenYouQuit)
            .foregroundStyle(.secondary)
    }

    func draftList(_ drafts: [StartOfYearDraft], first: String, showingPath: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(drafts, id: \.page.relativePath) { draft in
                let name: String = showingPath
                    ? "“\(draft.page.displayTitle)” (\(draft.page.relativePath))"
                    : "“\(draft.page.displayTitle)”"
                Text("• \(name) — \(draft.reason.sentence(first: first))")
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func fileList(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(urls, id: \.path) { url in
                Text("• " + AssistSectionGraph.relativePath(of: url, workspaceURL: model.workspaceURL))
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
                .keyboardShortcut(.defaultAction)
                .disabled(plan.changesNothing)
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
                .keyboardShortcut(.defaultAction)
                .disabled(putBack.isEmpty)
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
}
