import AppKit
import SwiftUI

/// A continuation that is resumed exactly once, whichever way the question
/// ends — the default button, Cancel, Escape, or the sheet going away.
@MainActor
final class LaterClassesAnswerOnce {

    // MARK: - Stored properties

    private var continuation: CheckedContinuation<LaterClassesAnswer, Never>?

    // MARK: - Initializer

    init(_ continuation: CheckedContinuation<LaterClassesAnswer, Never>) {
        self.continuation = continuation
    }

    // MARK: - Functions

    func give(_ answer: LaterClassesAnswer) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}

/// The section window's half of the Section menu's functions (#457 batch B)
/// and of #475's question at Deploy. In its own file because
/// `SectionDetailView.swift` is long enough already; the state it keeps is
/// declared there (`verbSheet`, `afterTheVerbSheet`).
extension SectionDetailView {

    // MARK: - Computed properties

    /// One of the assistant's functions is running on this section — from
    /// this window, from another window's menu, or in the assistant's own
    /// window. The menu greys them all while it is.
    var verbIsRunningHere: Bool {
        if workspace.sectionVerbsIfMade?.isRunning == true {
            return true
        }
        guard let folder = workspace.workspaceURL else {
            return false
        }
        if SectionMenuActivity.isChanging(folderPath: folder.path, courseCode: course.code, sectionNumber: sectionNumber) {
            return true
        }
        return AssistActivity.isWorking(folderPath: folder.path, courseCode: course.code, sectionNumber: sectionNumber)
    }

    /// Undo Last Change would act on this section: the last change made from
    /// the menu in this window was made here.
    var lastMenuChangeIsHere: Bool {
        return workspace.sectionVerbsIfMade?.lastChangeIsIn(courseCode: course.code, sectionNumber: sectionNumber) ?? false
    }

    /// Something is already on this window that a sheet may not go over.
    var somethingIsUpOnThisWindow: Bool {
        return verbSheet != nil || linksChecklist != nil || previewAlertIsUp || healthDialog != nil
            || deployRefusal != nil || workspace.sheetIsUp
    }

    // MARK: - Running a function

    /// A function asked for from this section's context menu, when it is
    /// this window's to answer.
    func takeAVerbRequestIfItIsMine() {
        guard let request = workspace.sectionVerbRequest else {
            return
        }
        if request.courseCode.lowercased() != course.code.lowercased() || request.sectionNumber != sectionNumber {
            return
        }
        workspace.sectionVerbRequest = nil
        performVerb(request.item)
    }

    /// Whether `item` may run now — asked again at the click, because the
    /// menu may have been drawn before something started (`MenuRoute`'s
    /// rule), and the context menu does not ask the rule at all.
    ///
    /// `afterTheDates` is the one call made as a sheet closes — the class
    /// dates, written down, running the function they were asked for — when
    /// the window may not yet have heard that its sheet has ended
    /// (`sheetIsUp` follows AppKit's own notification), so that one flag is
    /// not asked; everything else is.
    func verbMayRunNow(_ item: SubjectMenuRules.Item, afterTheDates: Bool = false) -> Bool {
        if verbIsRunningHere || workspace.isBeingCopied(course.code) {
            return false
        }
        if verbSheet != nil || linksChecklist != nil || previewAlertIsUp || healthDialog != nil || deployRefusal != nil {
            return false
        }
        if workspace.sheetIsUp && !afterTheDates {
            return false
        }
        if item == .rebuildPreview {
            return previewRunner.isRunning && previewButtonIsEnabled
        }
        if course.isKeptForReference {
            return false
        }
        if let folder = workspace.workspaceURL,
           CourseActivity.coursePublishIsRunning(folderPath: folder.path, courseCode: course.code) {
            return false
        }
        if item == .undoLastChange {
            return lastMenuChangeIsHere
        }
        return true
    }

    /// Section ▸ Publish Pages… and the rest: what each one opens or does.
    func performVerb(_ item: SubjectMenuRules.Item, afterTheDates: Bool = false) {
        if !verbMayRunNow(item, afterTheDates: afterTheDates) {
            NSSound.beep()
            return
        }
        guard let verbs = workspace.sectionVerbs() else {
            return
        }
        switch item {
        case .publishPages, .hidePages:
            verbSheet = SectionVerbSheetModel.choosingPages(
                publishing: item == .publishPages, course: course, sectionNumber: sectionNumber,
                workspaceURL: workspace.workspaceURL
            )
        case .publishClassForADate:
            let model: SectionVerbSheetModel = SectionVerbSheetModel(
                kind: .publishClass, course: course, sectionNumber: sectionNumber,
                title: AssistWording.menuPublishClassTitle(
                    course: course.displayCode, section: String(sectionNumber), noun: course.configuration.classNoun
                ),
                item: item
            )
            let first: CalendarDay = SectionVerbSheetModel.firstDayOffered(
                course: course, sectionNumber: sectionNumber, today: CalendarDay.today()
            )
            model.day = SectionVerbSheetModel.noon(of: first)
            verbSheet = model
        case .reDateClasses:
            if askForDatesFirst(before: item) {
                return
            }
            let model: SectionVerbSheetModel = SectionVerbSheetModel(
                kind: .reDateClasses, course: course, sectionNumber: sectionNumber,
                title: AssistWording.menuReDateTitle(
                    course: course.displayCode, section: String(sectionNumber), noun: course.configuration.classNoun
                ),
                item: item, stage: .working
            )
            verbSheet = model
            planTheChoice(model)
        case .makeRoomForClasses:
            if askForDatesFirst(before: item) {
                return
            }
            let model: SectionVerbSheetModel = SectionVerbSheetModel(
                kind: .makeRoom, course: course, sectionNumber: sectionNumber,
                title: AssistWording.menuMakeRoomTitle(
                    course: course.displayCode, section: String(sectionNumber), noun: course.configuration.classNoun
                ),
                item: item
            )
            model.classRows = SectionVerbSheetModel.classRows(course: course, sectionNumber: sectionNumber)
            model.chosenClass = model.classRows.first?.title ?? ""
            verbSheet = model
        case .addNextClass:
            if askForDatesFirst(before: item) {
                return
            }
            runAtOnce(SectionVerbs.addNextClass(course: course.code, section: sectionNumber), item: item, verbs: verbs,
                      title: AssistWording.menuAddNextClassTitle(noun: course.configuration.classNoun))
        case .undoLastChange:
            runAtOnce(SectionVerbs.undoLastChange(), item: item, verbs: verbs, title: AssistWording.menuUndoLastChangeTitle)
        case .rebuildPreview:
            runAtOnce(SectionVerbs.rebuildPreview(course: course.code, section: sectionNumber), item: item, verbs: verbs,
                      title: AssistWording.menuRebuildPreviewTitle)
        case .classDates:
            SectionVerbs.noteRan(item, ending: "opened", counts: "", courseCode: course.code, sectionNumber: sectionNumber)
            let model: SectionVerbSheetModel = SectionVerbSheetModel(
                kind: .classDates, course: course, sectionNumber: sectionNumber, title: "", item: item
            )
            verbSheet = model
        default:
            break
        }
    }

    /// Add Next Class, Re-date Classes… and Make Room for Classes… need the
    /// section's class dates. With none on file, THIS window asks for them
    /// first — its own Class Dates sheet, never the assistant's prompt, which
    /// only the assistant's window shows (#457's plan review, blocker 1) —
    /// and the function runs once they are written down. True when it asked.
    func askForDatesFirst(before item: SubjectMenuRules.Item) -> Bool {
        if !SectionVerbs.hasNoTimetable(forSection: sectionNumber, in: course) {
            return false
        }
        let noun: ClassNoun = course.configuration.classNoun
        let model: SectionVerbSheetModel = SectionVerbSheetModel(
            kind: .classDates, course: course, sectionNumber: sectionNumber, title: "", item: .classDates
        )
        switch item {
        case .addNextClass:
            model.reason = AssistWording.datesForTheNextPage(noun: noun)
        case .reDateClasses:
            model.reason = AssistWording.datesToReDate(noun: noun)
        default:
            model.reason = AssistWording.datesToMakeRoom(noun: noun)
        }
        model.afterTheDates = {
            afterTheVerbSheet = {
                performVerb(item, afterTheDates: true)
            }
        }
        verbSheet = model
        return true
    }

    /// Undo Last Change, Rebuild Preview and Add Next Class: no plan, so they
    /// run at once, and what they said is shown — except a Rebuild Preview
    /// that is rebuilding, which the teacher is watching happen.
    func runAtOnce(_ call: AssistToolCall, item: SubjectMenuRules.Item, verbs: SectionVerbs, title: String) {
        Task { @MainActor in
            let outcome: AssistToolOutcome = await verbs.perform(
                call, item: item, courseCode: course.code, sectionNumber: sectionNumber
            )
            refreshEditedMarker()
            if item == .rebuildPreview
                && outcome.summary == AssistWording.previewIsRebuilding(course: course.code, section: String(sectionNumber)) {
                return
            }
            let model: SectionVerbSheetModel = SectionVerbSheetModel(
                kind: .result, course: course, sectionNumber: sectionNumber, title: title, item: item, stage: .finished
            )
            model.body = outcome.summary
            if somethingIsUpOnThisWindow {
                // The answer is on the trail; a sheet over another sheet is
                // not something SwiftUI will show.
                NSSound.beep()
                return
            }
            verbSheet = model
        }
    }

    /// The sheet's default button, at whatever stage it is.
    func pressDefault(in model: SectionVerbSheetModel) {
        switch model.stage {
        case .choosing:
            if model.kind == .publishPages {
                var picked: [URL] = []
                for row in model.tickedRows {
                    picked.append(row.fileURL)
                }
                let today: CalendarDay = CalendarDay.today()
                let flagged: [ClassesDatedLater.Flagged] = ClassesDatedLater.flagged(
                    ifPublishing: picked, forSection: sectionNumber, in: course, today: today
                )
                if !flagged.isEmpty {
                    let nextDay: CalendarDay? = ClassesDatedLater.nextClassDay(
                        after: today, among: ClassesDatedLater.classPages(forSection: sectionNumber, in: course)
                    )
                    model.ask(about: flagged, nextDay: nextDay)
                    return
                }
            }
            planTheChoice(model)
        case .askingAboutLaterClasses:
            if model.kind == .laterClassesAtDeploy {
                answerAtDeploy(model)
                return
            }
            // Publish Pages…: the ticked classes are left OUT and stay hidden;
            // the unticked ones go ahead and are remembered as kept.
            ClassesDatedLater.keep(model.laterKept, forSection: sectionNumber, in: course)
            ActivityTrail.note(
                .laterClassesAsked,
                ClassesDatedLater.askedLine(
                    route: "Section ▸ Publish Pages…", flagged: model.laterClasses.count,
                    hidden: model.laterHidden.count, kept: model.laterKept.count, cancelled: false
                ),
                course: course.code, section: sectionNumber
            )
            for page in model.laterHidden {
                for row in model.pageRows
                where ClassesDatedLater.place(of: row.fileURL, courseDirectory: course.directoryURL) == page.place {
                    model.ticked.remove(row.name)
                }
            }
            if model.ticked.isEmpty {
                workspace.sectionVerbsIfMade?.noteCancelled(
                    .publishPages, courseCode: course.code, sectionNumber: sectionNumber,
                    counts: "every page ticked was a class dated later, left hidden"
                )
                verbSheet = nil
                return
            }
            planTheChoice(model)
        case .planned:
            goAhead(model)
        case .finished:
            verbSheet = nil
        case .working:
            break
        }
    }

    /// The plan twin, run with nothing written: its card is the sheet's body,
    /// and Go then runs the write with the same arguments. A twin that
    /// refuses, or finds nothing to do, ends the sheet with its sentence.
    func planTheChoice(_ model: SectionVerbSheetModel) {
        guard let verbs = workspace.sectionVerbs() else {
            return
        }
        var names: [String] = []
        for row in model.tickedRows {
            names.append(row.name)
        }
        let code: String = course.code
        var planCall: AssistToolCall
        switch model.kind {
        case .publishPages:
            planCall = SectionVerbs.publishPages(course: code, section: sectionNumber, names: names, planning: true)
            model.pendingCall = SectionVerbs.publishPages(course: code, section: sectionNumber, names: names, planning: false)
        case .hidePages:
            planCall = SectionVerbs.hidePages(course: code, section: sectionNumber, names: names, planning: true)
            model.pendingCall = SectionVerbs.hidePages(course: code, section: sectionNumber, names: names, planning: false)
        case .publishClass:
            let day: CalendarDay = CalendarDay.today(model.day)
            planCall = SectionVerbs.publishClass(course: code, section: sectionNumber, on: day, planning: true)
            model.pendingCall = SectionVerbs.publishClass(course: code, section: sectionNumber, on: day, planning: false)
        case .reDateClasses:
            planCall = SectionVerbs.reDateClasses(course: code, section: sectionNumber, planning: true)
            model.pendingCall = SectionVerbs.reDateClasses(course: code, section: sectionNumber, planning: false)
        case .makeRoom:
            var unit: Int = 1
            var atDay: Int = 1
            for row in model.classRows where row.title == model.chosenClass {
                unit = row.unit
                atDay = row.day
            }
            planCall = SectionVerbs.makeRoom(
                course: code, section: sectionNumber, unit: unit, atDay: atDay, howMany: model.howMany, planning: true
            )
            model.pendingCall = SectionVerbs.makeRoom(
                course: code, section: sectionNumber, unit: unit, atDay: atDay, howMany: model.howMany, planning: false
            )
        default:
            return
        }
        model.stage = .working
        Task { @MainActor in
            let outcome: AssistToolOutcome = await verbs.plan(planCall)
            if outcome.isPlan {
                model.body = outcome.forTheCard
                model.stage = .planned
                return
            }
            model.body = outcome.summary
            model.stage = .finished
            if let item = model.item {
                SectionVerbs.noteRan(item, ending: "changed nothing", counts: countsLine(model),
                                     courseCode: course.code, sectionNumber: sectionNumber)
            }
        }
    }

    /// Go: the write, with the arguments the plan was made from.
    func goAhead(_ model: SectionVerbSheetModel) {
        guard let verbs = workspace.sectionVerbs(), let call = model.pendingCall, let item = model.item else {
            verbSheet = nil
            return
        }
        model.stage = .working
        Task { @MainActor in
            let outcome: AssistToolOutcome = await verbs.perform(
                call, item: item, courseCode: course.code, sectionNumber: sectionNumber, counts: countsLine(model)
            )
            model.body = outcome.summary
            model.stage = .finished
            refreshEditedMarker()
        }
    }

    /// Cancel, at whatever stage — and for #475's question at Deploy, the
    /// answer that nothing goes.
    func cancelVerbSheet(_ model: SectionVerbSheetModel) {
        if model.kind == .laterClassesAtDeploy {
            if model.answerAtDeploy != nil {
                ActivityTrail.note(
                    .laterClassesAsked,
                    ClassesDatedLater.askedLine(
                        route: model.route, flagged: model.laterClasses.count, hidden: 0, kept: 0, cancelled: true
                    ),
                    course: course.code, section: sectionNumber
                )
            }
            model.answerAtDeploy?(.cancelled)
        } else if model.stage == .planned || model.stage == .askingAboutLaterClasses, let item = model.item {
            workspace.sectionVerbsIfMade?.noteCancelled(
                item, courseCode: course.code, sectionNumber: sectionNumber, counts: countsLine(model)
            )
        }
        verbSheet = nil
    }

    /// The sheet has gone: an unanswered #475 question is a Cancel, a
    /// function waiting on the class dates runs, and anything held behind
    /// the sheet is shown.
    func verbSheetWentAway() {
        refreshEditedMarker()
        if let next = afterTheVerbSheet {
            afterTheVerbSheet = nil
            next()
            return
        }
        showAnythingWaiting()
    }

    /// The counts for the trail line — never a title.
    func countsLine(_ model: SectionVerbSheetModel) -> String {
        switch model.kind {
        case .publishPages, .hidePages:
            let count: Int = model.ticked.count
            return count == 1 ? "1 page ticked" : "\(count) pages ticked"
        case .makeRoom:
            return model.howMany == 1 ? "room for 1" : "room for \(model.howMany)"
        default:
            return ""
        }
    }

    // MARK: - Classes dated after the next class (#475)

    /// What Deploy does first, decided purely (`shared-rules.json` →
    /// `classesDatedLater.order`): a deploy that is going to be REFUSED is
    /// refused with no question first — a refusal never follows a change,
    /// and hiding pages before a refusal would be one; with nothing flagged
    /// it goes straight on; with something on the window already the
    /// question cannot be put; otherwise it asks.
    enum DeployFirst: Equatable {
        case goStraightOn
        case ask
        case cannotAsk
    }

    static func whatDeployDoesFirst(willBeRefused: Bool, flagged: Int, somethingIsUp: Bool) -> DeployFirst {
        if willBeRefused || flagged == 0 {
            return .goStraightOn
        }
        if somethingIsUp {
            return .cannotAsk
        }
        return .ask
    }

    /// Whether `deployAndWait` would refuse before deploying — read, never
    /// claimed: the same checks in the same order, with nothing written and
    /// no lease taken, so the question is never asked of a deploy that is
    /// going to be refused.
    func deployWillBeRefused() -> Bool {
        if SectionDetailView.refusalForAReferenceCourse(course) != nil {
            return true
        }
        guard let workspaceURL = workspace.workspaceURL else {
            return true
        }
        if isPreparingDeploy || deployRunner.isRunning {
            return true
        }
        if CourseActivity.courseIsBeingCopied(folderPath: workspaceURL.path, courseCode: course.code) {
            return true
        }
        let anyWindowHasUnsavedSettings: Bool = course.configuration.hasUnsavedChanges
            || WorkspaceModel.anyCopyHasUnsavedChanges(configFileURL: course.configFileURL)
        let uses: (
            course: Course?, destinations: [CourseConfiguration.DeployDestination], refusal: String?, notice: String?
        ) = SectionDetailView.whatADeployUses(
            windowCourse: course,
            anyCopyUnsaved: anyWindowHasUnsavedSettings,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID
        )
        if uses.course == nil || uses.refusal != nil {
            return true
        }
        if WorkLeaseRegistry.whatBlocksABuild(
            folderPath: workspaceURL.path, courseCode: course.code, afterTaking: false
        ) != nil {
            return true
        }
        return false
    }

    /// The question at Deploy — the button, Section ▸ Deploy…, and the
    /// in-app assistant's deploy — before anything is stopped, claimed or
    /// built. Decided for the day it was ASKED: an answer given after
    /// midnight hides the classes that were on the list.
    func askAboutClassesDatedLater(route: String) async -> LaterClassesAnswer {
        let today: CalendarDay = CalendarDay.today()
        let flagged: [ClassesDatedLater.Flagged] = ClassesDatedLater.flagged(
            forSection: sectionNumber, in: course, today: today
        )
        let first: DeployFirst = SectionDetailView.whatDeployDoesFirst(
            willBeRefused: deployWillBeRefused(), flagged: flagged.count, somethingIsUp: somethingIsUpOnThisWindow
        )
        switch first {
        case .goStraightOn:
            return .nothingToAsk
        case .cannotAsk:
            return .cannotAsk
        case .ask:
            break
        }
        let nextDay: CalendarDay? = ClassesDatedLater.nextClassDay(
            after: today, among: ClassesDatedLater.classPages(forSection: sectionNumber, in: course)
        )
        return await withCheckedContinuation { continuation in
            let once: LaterClassesAnswerOnce = LaterClassesAnswerOnce(continuation)
            let model: SectionVerbSheetModel = SectionVerbSheetModel(
                kind: .laterClassesAtDeploy, course: course, sectionNumber: sectionNumber,
                title: AssistWording.laterClassesTitle(noun: course.configuration.classNoun), item: nil
            )
            model.ask(about: flagged, nextDay: nextDay)
            model.route = route
            model.answerAtDeploy = { answer in
                once.give(answer)
                model.answerAtDeploy = nil
            }
            verbSheet = model
        }
    }

    /// Hide N and Deploy, or Deploy As It Is. The unticked classes are kept;
    /// the ticked ones are hidden through Hide Pages…'s own call
    /// (`unpublish_pages` on this window's runner: a copy of the course
    /// first, and Undo Last Change takes it back), without a preview first —
    /// the deploy builds the site itself straight after. If a ticked class is
    /// still visible afterwards, nothing is deployed and the sheet says why.
    func answerAtDeploy(_ model: SectionVerbSheetModel) {
        let hidden: [ClassesDatedLater.Flagged] = model.laterHidden
        let kept: [ClassesDatedLater.Flagged] = model.laterKept
        ClassesDatedLater.keep(kept, forSection: sectionNumber, in: course)
        ActivityTrail.note(
            .laterClassesAsked,
            ClassesDatedLater.askedLine(
                route: model.route, flagged: model.laterClasses.count,
                hidden: hidden.count, kept: kept.count, cancelled: false
            ),
            course: course.code, section: sectionNumber
        )
        if hidden.isEmpty {
            model.answerAtDeploy?(.goAhead)
            verbSheet = nil
            return
        }
        guard let verbs = workspace.sectionVerbs() else {
            model.answerAtDeploy?(.cancelled)
            verbSheet = nil
            return
        }
        var names: [String] = []
        var places: Set<String> = []
        for page in hidden {
            names.append(page.place)
            places.insert(page.place)
        }
        model.stage = .working
        Task { @MainActor in
            verbs.toolRunner.previewFollowsAChange = false
            let outcome: AssistToolOutcome = await verbs.perform(
                SectionVerbs.hidePages(course: course.code, section: sectionNumber, names: names, planning: false),
                item: .hidePages, courseCode: course.code, sectionNumber: sectionNumber,
                counts: hidden.count == 1 ? "1 class dated later, at Deploy" : "\(hidden.count) classes dated later, at Deploy"
            )
            verbs.toolRunner.previewFollowsAChange = true
            refreshEditedMarker()
            var stillShowing: Bool = false
            for page in ClassesDatedLater.flagged(forSection: sectionNumber, in: course, today: CalendarDay.today())
            where places.contains(page.place) {
                stillShowing = true
            }
            if stillShowing {
                model.body = outcome.summary
                model.stage = .finished
                model.answerAtDeploy?(.cancelled)
                return
            }
            model.answerAtDeploy?(.goAhead)
            verbSheet = nil
        }
    }
}
