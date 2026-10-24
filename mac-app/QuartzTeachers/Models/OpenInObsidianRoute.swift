import Foundation

/// The note about a reference course's locked pages, asked for before
/// Obsidian opens: the course, and the folder Obsidian reveals once the note
/// is answered (the section's own when asked from a section) — or the page
/// the section's preview was showing at the press (#518), which opens
/// instead.
struct LockedPagesNoteRequest: Identifiable {

    // MARK: - Stored properties

    let course: Course
    let folder: URL
    var page: URL? = nil

    // MARK: - Computed properties

    var id: String {
        return course.code + "|" + folder.path
    }
}

/// Obsidian's add-ons question (#495), or the reopen question, waiting to
/// be shown before Obsidian opens: the course, the folder Obsidian reveals
/// afterwards, the add-ons the course needs, and whether the course is open
/// in Obsidian right now — and the page the section's preview was showing
/// at the press (#518), which opens instead of the folder once answered.
struct ObsidianAddOnsRequest: Identifiable {

    // MARK: - Stored properties

    let course: Course
    let folder: URL
    let needed: [ObsidianFigureAddOn]
    let courseIsOpen: Bool
    var page: URL? = nil

    // MARK: - Computed properties

    var id: String {
        return course.code + "|" + folder.path
    }
}

/// What one press of a section window's Open in Obsidian came to, for the
/// assistant's `open_in_obsidian` (#610), which has to SAY what happened.
///
/// The page in `.opened` is the answer read ONCE, at the press — the same
/// answer that chose what Obsidian was handed — so the reply can never name a
/// page other than the one that opened (a second read of the web view could).
enum OpenInObsidianPress: Equatable {

    /// Obsidian was handed the page the preview showed, or the section as
    /// before, and why.
    case opened(PreviewedPageSource.Answer)

    /// A question is up in the section window (the locked-pages note, the
    /// add-ons offer or the reopen question); Obsidian opens once it is
    /// answered.
    case waitingForAnAnswer

    /// An earlier press is still looking the course over; this one did
    /// nothing, as a second click on the button does.
    case alreadyOpening

    /// No window answered the press — the default for a window that does
    /// not register one.
    case noWindow
}

/// What the route did with one press, for its two callers (#610).
struct OpenInObsidianPressed {

    // MARK: - Stored properties

    /// Obsidian was handed something now.
    let opened: Bool

    /// The press went ahead (and left its trail line); false only for a
    /// second press while the add-ons scan of the first is running.
    let wentAhead: Bool

    /// The add-ons scan started, and decides once it is back.
    let scanStarted: Bool

    /// The page on screen at the press, or why the section opens; nil for a
    /// course press.
    let answer: PreviewedPageSource.Answer?
}

/// Everything Open in Obsidian asks of the world outside the app — Obsidian
/// itself, its registry, the disk — in one replaceable place, so a test can
/// drive the route without ever reaching the teacher's Obsidian (#495).
/// The defaults are the real thing.
struct ObsidianOpening {

    // MARK: - Stored properties

    /// Whether anything answers `obsidian://`.
    var isInstalled: @MainActor () -> Bool = {
        return FolderActions.obsidianIsInstalled
    }

    /// Whether Obsidian is running at all — hidden, minimised, full-screen
    /// or on another Space included.
    var isRunning: @MainActor () -> Bool = {
        return FolderActions.obsidianIsRunning
    }

    /// Obsidian's registry, as it is on disk now.
    var registryData: @MainActor () -> Data? = {
        return try? Data(contentsOf: FolderActions.obsidianRegistryFileURL)
    }

    /// Opens a folder in Obsidian — registering the course first when
    /// Obsidian has never seen it.
    var open: @MainActor (_ folder: URL, _ vault: URL) -> Void = { folder, vault in
        FolderActions.openInObsidian(revealing: folder, vaultURL: vault)
    }

    /// Opens one page in Obsidian (#518) — the page's own door, since the
    /// folder door looks for `<page>/index.md` and opens the vault instead.
    var openPage: @MainActor (_ page: URL, _ vault: URL) -> Void = { page, vault in
        FolderActions.openPageInObsidian(page, vaultURL: vault)
    }

    /// The address below its root of the page a section's preview is
    /// showing right now, or nil when none is (#518) — asked of the section
    /// window itself, which owns the web view.
    var previewedAddress: @MainActor (_ workingFolderPath: String?, _ courseCode: String, _ sectionNumber: Int) -> String? = { workingFolderPath, courseCode, sectionNumber in
        guard let workingFolderPath else {
            return nil
        }
        let controller: SectionWindowControllers.Controller? = SectionWindowControllers.shared.controller(
            folderPath: workingFolderPath, courseCode: courseCode, sectionNumber: sectionNumber
        )
        return controller?.previewedPage()
    }

    /// Quits Obsidian and waits for it to be gone.
    var quitAndWait: @MainActor () async -> Void = {
        await FolderActions.quitObsidianAndWait()
    }

    /// Opens these vaults again, in order.
    var reopen: @MainActor (_ vaultPaths: [String]) -> Void = { vaultPaths in
        FolderActions.reopenVaults(vaultPaths)
    }

    /// Which add-ons a course needs and which a pass would add — off the
    /// main actor.
    var scan: @Sendable (_ coursePath: String) async -> (needed: [ObsidianFigureAddOn], wouldAdd: [ObsidianFigureAddOn]) = { coursePath in
        return await ObsidianFigureAddOns.scan(courseAt: coursePath)
    }

    /// Where the app carries the add-ons, and the course defaults.
    var carriedFolder: URL? = Bundle.main.resourceURL?.appendingPathComponent(ObsidianFigureAddOns.carriedFolderName)
    var defaultsFolder: URL? = Bundle.main.resourceURL?.appendingPathComponent("support/obsidian_defaults/.obsidian")

    /// The answer's home; nil is `AppSettings.shared`.
    var settings: AppSettings?
}

extension WorkspaceModel {

    // MARK: - Functions

    /// Open in Obsidian — the ONE function every route calls: the section
    /// window's toolbar button, Course Settings' toolbar button, a row's
    /// context menu, Course ▸ / Section ▸ Open in Obsidian (#457), and the
    /// in-app assistant's `open_in_obsidian` (#610), which presses the section
    /// window's own through `openInObsidianAndWait` below.
    ///
    /// `atThePreviewedPage` is true for a SECTION's press — the section
    /// window's button, Section ▸ Open in Obsidian and a section row's menu
    /// (#518, ruling 3): while that section's preview shows a page, the file
    /// behind it opens instead of the section's front page
    /// (`PreviewedPageSource`), and the press leaves a trail line either way
    /// (ruling 5). Course presses leave it false and open what they always
    /// did.
    ///
    /// On a course kept for reference it locks the pages again first (a
    /// folder back from another Mac or a backup is not locked until somebody
    /// asks) and, the first time, asks for the calm note BEFORE Obsidian
    /// opens rather than after the teacher has typed. Until the HIG sweep the
    /// toolbar called `FolderActions.openInObsidian` directly and skipped
    /// both — one command, two behaviours (deferred from batch A). A
    /// reference course is never scanned and never offered add-ons (#255's
    /// line, #495).
    ///
    /// Any other course may need Obsidian's add-ons for diagrams and graphs
    /// (#495): unless the answer is no (or Not Now this run, or there is no
    /// Obsidian), the course is scanned off the main actor and
    /// `ObsidianFigureAddOnsOffer.decision` says whether to ask, add them,
    /// ask to reopen Obsidian, or just open — all BEFORE Obsidian opens, so
    /// in the common case Obsidian reads them on its first load and nothing
    /// is reopened.
    ///
    /// Returns whether Obsidian was opened now; `false` means a question is
    /// waiting (`lockedPagesNoteRequest`, `obsidianAddOnsOfferRequest`,
    /// `obsidianReopenRequest`) or the scan is still running — a second
    /// click then does nothing (plan review N7). `lockAgain` is replaced
    /// only by a test, whose temporary course must stay deletable.
    @discardableResult
    func openInObsidian(
        course: Course,
        sectionNumber: Int?,
        atThePreviewedPage: Bool = false,
        lockAgain: @MainActor (Course) -> Void = ReferenceLock.ensureLockedInBackground
    ) -> Bool {
        let pressed: OpenInObsidianPressed = pressOpenInObsidian(
            course: course, sectionNumber: sectionNumber,
            atThePreviewedPage: atThePreviewedPage, lockAgain: lockAgain
        )
        return pressed.opened
    }

    /// A SECTION's press of Open in Obsidian, for the assistant (#610): the
    /// same route the button takes (`openInObsidian` above, with
    /// `atThePreviewedPage`), and then — because the assistant has to say
    /// what happened — waits for the add-ons scan when one started, and
    /// reports what the press came to.
    ///
    /// Called by the section window's controller on the WINDOW's own model:
    /// the questions this route can ask are presented only by the window
    /// that owns the model, so a press on any other model would set a
    /// request nobody shows.
    func openInObsidianAndWait(
        course: Course,
        sectionNumber: Int,
        lockAgain: @MainActor (Course) -> Void = ReferenceLock.ensureLockedInBackground
    ) async -> OpenInObsidianPress {
        let pressed: OpenInObsidianPressed = pressOpenInObsidian(
            course: course, sectionNumber: sectionNumber,
            atThePreviewedPage: true, lockAgain: lockAgain
        )
        guard pressed.wentAhead, let answer = pressed.answer else {
            return .alreadyOpening
        }
        if pressed.opened {
            return .opened(answer)
        }
        if pressed.scanStarted, let work = obsidianAddOnsWork {
            await work.value
        }
        if lockedPagesNoteRequest != nil || obsidianAddOnsOfferRequest != nil || obsidianReopenRequest != nil {
            return .waitingForAnAnswer
        }
        return .opened(answer)
    }

    /// The route itself, shared by both callers above: what it did, and the
    /// answer read at the press.
    private func pressOpenInObsidian(
        course: Course,
        sectionNumber: Int?,
        atThePreviewedPage: Bool,
        lockAgain: @MainActor (Course) -> Void
    ) -> OpenInObsidianPressed {
        let folder: URL = FolderActions.obsidianFolder(for: course, sectionNumber: sectionNumber)
        // Read at the press (the page on screen now), but written to the
        // trail only once the press goes ahead: a second press while the
        // add-ons scan runs does nothing, so it says nothing.
        var answer: PreviewedPageSource.Answer? = nil
        if atThePreviewedPage, let sectionNumber {
            answer = previewedPageAnswer(course: course, sectionNumber: sectionNumber)
        }
        let page: URL? = WorkspaceModel.pageToOpen(answer)
        if course.isKeptForReference {
            notePreviewedPress(answer, course: course, sectionNumber: sectionNumber)
            lockAgain(course)
            if !LockedPagesNote.hasBeenShown(courseCode: course.code) {
                lockedPagesNoteRequest = LockedPagesNoteRequest(course: course, folder: folder, page: page)
                return OpenInObsidianPressed(opened: false, wentAhead: true, scanStarted: false, answer: answer)
            }
            openObsidian(folder, page: page, course: course)
            return OpenInObsidianPressed(opened: true, wentAhead: true, scanStarted: false, answer: answer)
        }
        let settings: AppSettings = obsidianOpening.settings ?? AppSettings.shared
        if !ObsidianFigureAddOnsOffer.scans(
            reference: false,
            obsidianInstalled: obsidianOpening.isInstalled(),
            answer: settings.obsidianFigureAddOns,
            suppressedThisRun: ObsidianFigureAddOnsThisRun.suppressed
        ) {
            notePreviewedPress(answer, course: course, sectionNumber: sectionNumber)
            openObsidian(folder, page: page, course: course)
            return OpenInObsidianPressed(opened: true, wentAhead: true, scanStarted: false, answer: answer)
        }
        let coursePath: String = course.directoryURL.path
        if ObsidianFigureAddOnsThisRun.beingOpened.contains(coursePath) {
            return OpenInObsidianPressed(opened: false, wentAhead: false, scanStarted: false, answer: answer)
        }
        notePreviewedPress(answer, course: course, sectionNumber: sectionNumber)
        ObsidianFigureAddOnsThisRun.beingOpened.insert(coursePath)
        let scan = obsidianOpening.scan
        obsidianAddOnsWork = Task { @MainActor in
            let scanned: (needed: [ObsidianFigureAddOn], wouldAdd: [ObsidianFigureAddOn]) = await scan(coursePath)
            await self.openInObsidian(course: course, folder: folder, page: page, needed: scanned.needed, wouldAdd: scanned.wouldAdd)
            ObsidianFigureAddOnsThisRun.beingOpened.remove(coursePath)
        }
        return OpenInObsidianPressed(opened: false, wentAhead: true, scanStarted: true, answer: answer)
    }

    /// The note was answered "Open in Obsidian": remember it was shown, and
    /// open the folder it was asked for.
    func openInObsidianAfterTheNote(_ request: LockedPagesNoteRequest) {
        LockedPagesNote.remember(courseCode: request.course.code)
        lockedPagesNoteRequest = nil
        openObsidian(request.folder, page: request.page, course: request.course)
    }

    /// The offer was answered (#495). Obsidian opens after every answer.
    func answerObsidianAddOnsOffer(_ request: ObsidianAddOnsRequest, _ answered: ObsidianFigureAddOnsTrail.Answered) async {
        obsidianAddOnsOfferRequest = nil
        ActivityTrail.note(.obsidianAddOnsOffered, ObsidianFigureAddOnsTrail.offered(course: request.course.code, answered: answered))
        let settings: AppSettings = obsidianOpening.settings ?? AppSettings.shared
        switch answered {
        case .addThem:
            settings.obsidianFigureAddOns = .yes
            // Asked again NOW: the teacher may have opened the course in
            // Obsidian while the question was up (fixes review N2).
            if request.courseIsOpen || courseIsOpenInObsidian(request.course.directoryURL.path) {
                await reopenObsidianWithAddOns(request)
                return
            }
            await addObsidianAddOns(toCourse: request.course, request.needed, trigger: .openInObsidian)
        case .notNow:
            ObsidianFigureAddOnsThisRun.suppressed = true
        case .notNowDontAskAgain:
            settings.obsidianFigureAddOns = .no
        }
        openObsidian(request.folder, page: request.page, course: request.course)
    }

    /// The reopen question was answered (#495): Reopen closes Obsidian, adds
    /// the add-ons while it is closed and opens it again; Later opens it as
    /// it is and asks no more about this course until Plantoir next starts.
    func answerObsidianReopen(_ request: ObsidianAddOnsRequest, reopen: Bool) async {
        obsidianReopenRequest = nil
        if reopen {
            await reopenObsidianWithAddOns(request)
            return
        }
        ObsidianFigureAddOnsThisRun.reopenDeclined.insert(request.course.directoryURL.path)
        ActivityTrail.note(.obsidianReopenedForAddOns, ObsidianFigureAddOnsTrail.reopenDeclined(course: request.course.code))
        openObsidian(request.folder, page: request.page, course: request.course)
    }

    /// A section's preview has just shown a fresh build (#495's second
    /// trigger): with the answer yes, add what the course needs, silently —
    /// unless the course is open in Obsidian, which is never written into
    /// (plan review S3); the next Open in Obsidian asks to reopen instead.
    /// This covers teachers who start Obsidian from the Dock.
    func addObsidianAddOnsAfterAPreview(course: Course) {
        if course.isKeptForReference {
            return
        }
        let settings: AppSettings = obsidianOpening.settings ?? AppSettings.shared
        if settings.obsidianFigureAddOns != .yes {
            return
        }
        if !obsidianOpening.isInstalled() {
            return
        }
        let coursePath: String = course.directoryURL.path
        let scan = obsidianOpening.scan
        obsidianAddOnsWork = Task { @MainActor in
            let scanned: (needed: [ObsidianFigureAddOn], wouldAdd: [ObsidianFigureAddOn]) = await scan(coursePath)
            let decision: ObsidianFigureAddOnsOffer.PreviewDecision = ObsidianFigureAddOnsOffer.afterAPreview(
                reference: course.isKeptForReference,
                obsidianInstalled: true,
                answer: settings.obsidianFigureAddOns,
                wouldAdd: !scanned.wouldAdd.isEmpty,
                vaultIsTheCourse: ObsidianFigureAddOnsOffer.vaultIsTheCourse(
                    targetPath: coursePath, coursePath: coursePath, registryData: self.obsidianOpening.registryData()
                ),
                courseOpenInObsidian: self.courseIsOpenInObsidian(coursePath)
            )
            if decision == .install {
                await self.addObsidianAddOns(toCourse: course, scanned.needed, trigger: .afterAPreview)
            }
        }
    }

    // MARK: - Private helpers

    /// The one place Open in Obsidian hands Obsidian something: the page the
    /// section's preview was showing when there is one (#518), the folder
    /// (its front page, or the course) otherwise.
    private func openObsidian(_ folder: URL, page: URL?, course: Course) {
        if let page {
            obsidianOpening.openPage(page, course.directoryURL)
            return
        }
        obsidianOpening.open(folder, course.directoryURL)
    }

    /// A section's press (#518): the file behind the page its preview is
    /// showing, or why the section opens as before. Writes nothing; the
    /// trail line is `notePreviewedPress`'s, once the press goes ahead.
    private func previewedPageAnswer(course: Course, sectionNumber: Int) -> PreviewedPageSource.Answer {
        let address: String? = obsidianOpening.previewedAddress(workspaceURL?.path, course.code, sectionNumber)
        var listData: Data? = nil
        if address != nil {
            listData = try? Data(contentsOf: PreviewedPageSource.listURL(
                courseFolder: course.directoryURL, sectionNumber: sectionNumber
            ))
        }
        return PreviewedPageSource.resolve(
            address: address, listData: listData, courseFolder: course.directoryURL
        )
    }

    /// The file a section's press opens, or nil for the section as before
    /// (and for every course press, which has no answer).
    private static func pageToOpen(_ answer: PreviewedPageSource.Answer?) -> URL? {
        guard let answer else {
            return nil
        }
        if case .page(let file, _, _) = answer {
            return file
        }
        return nil
    }

    /// The trail line for a section's press that goes ahead — the page, or
    /// why the section opened instead (ruling 5). A course press has no
    /// answer and writes nothing.
    private func notePreviewedPress(_ answer: PreviewedPageSource.Answer?, course: Course, sectionNumber: Int?) {
        guard let answer, let sectionNumber else {
            return
        }
        ActivityTrail.note(
            .pageOpenedInObsidian, PreviewedPageSource.trailWords(answer),
            course: course.code, section: sectionNumber
        )
    }

    /// What Open in Obsidian does once the scan is back.
    private func openInObsidian(course: Course, folder: URL, page: URL?, needed: [ObsidianFigureAddOn], wouldAdd: [ObsidianFigureAddOn]) async {
        let settings: AppSettings = obsidianOpening.settings ?? AppSettings.shared
        let coursePath: String = course.directoryURL.path
        // The file Obsidian is handed, which decides which vault opens it.
        var target: URL = FolderActions.obsidianTarget(forFolder: folder, vaultURL: course.directoryURL)
        if let page {
            target = FolderActions.pageTarget(page, vaultURL: course.directoryURL)
        }
        let situation: ObsidianFigureAddOnsOffer.Situation = ObsidianFigureAddOnsOffer.Situation(
            reference: course.isKeptForReference,
            obsidianInstalled: true,
            answer: settings.obsidianFigureAddOns,
            suppressedThisRun: ObsidianFigureAddOnsThisRun.suppressed,
            wouldAdd: !wouldAdd.isEmpty,
            vaultIsTheCourse: ObsidianFigureAddOnsOffer.vaultIsTheCourse(
                targetPath: target.path, coursePath: coursePath, registryData: obsidianOpening.registryData()
            ),
            courseOpenInObsidian: courseIsOpenInObsidian(coursePath),
            reopenDeclinedThisRun: ObsidianFigureAddOnsThisRun.reopenDeclined.contains(coursePath)
        )
        switch ObsidianFigureAddOnsOffer.decision(situation) {
        case .justOpen:
            openObsidian(folder, page: page, course: course)
        case .notTheVault:
            let line: String = ObsidianFigureAddOnsTrail.notTheVault(course: course.code)
            if !ObsidianFigureAddOnsThisRun.linesWritten.contains(line) {
                ObsidianFigureAddOnsThisRun.linesWritten.insert(line)
                ActivityTrail.note(.obsidianAddOnsOffered, line)
            }
            openObsidian(folder, page: page, course: course)
        case .offer:
            obsidianAddOnsOfferRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: needed, courseIsOpen: false, page: page)
        case .offerWhileOpen:
            obsidianAddOnsOfferRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: needed, courseIsOpen: true, page: page)
        case .installThenOpen:
            await addObsidianAddOns(toCourse: course, needed, trigger: .openInObsidian)
            openObsidian(folder, page: page, course: course)
        case .askReopen:
            obsidianReopenRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: needed, courseIsOpen: true, page: page)
        }
    }

    /// Closes Obsidian, adds the add-ons while it is closed, and opens every
    /// vault that was open again, this course last — the registration path's
    /// own quit-and-reopen (`FolderActions.open`). If Obsidian does not close
    /// (a question of its own on screen), nothing is written.
    private func reopenObsidianWithAddOns(_ request: ObsidianAddOnsRequest) async {
        let wereOpen: [String] = vaultsOpenInObsidian()
        await obsidianOpening.quitAndWait()
        // Write only once Obsidian is GONE — not merely without a window on
        // screen (#495 implementation review B1).
        if obsidianOpening.isRunning() {
            ActivityTrail.note(.obsidianReopenedForAddOns, ObsidianFigureAddOnsTrail.didNotClose(course: request.course.code))
            openObsidian(request.folder, page: request.page, course: request.course)
            return
        }
        await addObsidianAddOns(toCourse: request.course, request.needed, trigger: .afterReopening)
        ActivityTrail.note(.obsidianReopenedForAddOns, ObsidianFigureAddOnsTrail.reopened(course: request.course.code))
        obsidianOpening.reopen(wereOpen)
        openObsidian(request.folder, page: request.page, course: request.course)
    }

    /// The vaults #495 treats as open: Obsidian is running and its registry
    /// marks them open. Windows are NOT counted (implementation review B1,
    /// measured: Russell's hidden Obsidian had 16 vault windows and 0 on
    /// screen, so `FolderActions.openVaultPathsNow` — which needs a window on
    /// screen, for the rename feature's sake — read every course as closed).
    /// Over-reporting is the safe direction here: the preview pass waits and
    /// Open in Obsidian asks to reopen.
    private func vaultsOpenInObsidian() -> [String] {
        return ObsidianFigureAddOnsOffer.vaultsOpen(
            obsidianRunning: obsidianOpening.isRunning(),
            registryData: obsidianOpening.registryData()
        )
    }

    /// Whether this course counts as open in Obsidian right now
    /// (`ObsidianFigureAddOnsOffer.courseIsOpen`).
    private func courseIsOpenInObsidian(_ coursePath: String) -> Bool {
        return ObsidianFigureAddOnsOffer.courseIsOpen(
            coursePath: coursePath,
            obsidianRunning: obsidianOpening.isRunning(),
            registryData: obsidianOpening.registryData()
        )
    }

    /// One pass, through the queue, and its trail line.
    private func addObsidianAddOns(toCourse course: Course, _ needed: [ObsidianFigureAddOn], trigger: ObsidianFigureAddOnsTrail.Trigger) async {
        if course.isKeptForReference || needed.isEmpty {
            return
        }
        let results: [ObsidianFigureAddOns.Result] = await ObsidianFigureAddOnsQueue.shared.install(
            needed,
            inCourseAt: course.directoryURL.path,
            carriedFrom: obsidianOpening.carriedFolder,
            defaultsFrom: obsidianOpening.defaultsFolder
        )
        ObsidianFigureAddOnsThisRun.notePass(course: course.code, trigger: trigger, results: results)
    }
}
