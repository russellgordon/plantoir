import Foundation

/// The note about a reference course's locked pages, asked for before
/// Obsidian opens: the course, and the folder Obsidian reveals once the note
/// is answered (the section's own when asked from a section).
struct LockedPagesNoteRequest: Identifiable {

    // MARK: - Stored properties

    let course: Course
    let folder: URL

    // MARK: - Computed properties

    var id: String {
        return course.code + "|" + folder.path
    }
}

/// Obsidian's add-ons question (#495), or the reopen question, waiting to
/// be shown before Obsidian opens: the course, the folder Obsidian reveals
/// afterwards, the add-ons the course needs, and whether the course is open
/// in Obsidian right now.
struct ObsidianAddOnsRequest: Identifiable {

    // MARK: - Stored properties

    let course: Course
    let folder: URL
    let needed: [ObsidianFigureAddOn]
    let courseIsOpen: Bool

    // MARK: - Computed properties

    var id: String {
        return course.code + "|" + folder.path
    }
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
    /// context menu, and Course ▸ / Section ▸ Open in Obsidian (#457).
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
        lockAgain: @MainActor (Course) -> Void = ReferenceLock.ensureLockedInBackground
    ) -> Bool {
        let folder: URL = FolderActions.obsidianFolder(for: course, sectionNumber: sectionNumber)
        if course.isKeptForReference {
            lockAgain(course)
            if !LockedPagesNote.hasBeenShown(courseCode: course.code) {
                lockedPagesNoteRequest = LockedPagesNoteRequest(course: course, folder: folder)
                return false
            }
            obsidianOpening.open(folder, course.directoryURL)
            return true
        }
        let settings: AppSettings = obsidianOpening.settings ?? AppSettings.shared
        if !ObsidianFigureAddOnsOffer.scans(
            reference: false,
            obsidianInstalled: obsidianOpening.isInstalled(),
            answer: settings.obsidianFigureAddOns,
            suppressedThisRun: ObsidianFigureAddOnsThisRun.suppressed
        ) {
            obsidianOpening.open(folder, course.directoryURL)
            return true
        }
        let coursePath: String = course.directoryURL.path
        if ObsidianFigureAddOnsThisRun.beingOpened.contains(coursePath) {
            return false
        }
        ObsidianFigureAddOnsThisRun.beingOpened.insert(coursePath)
        let scan = obsidianOpening.scan
        obsidianAddOnsWork = Task { @MainActor in
            let scanned: (needed: [ObsidianFigureAddOn], wouldAdd: [ObsidianFigureAddOn]) = await scan(coursePath)
            await self.openInObsidian(course: course, folder: folder, needed: scanned.needed, wouldAdd: scanned.wouldAdd)
            ObsidianFigureAddOnsThisRun.beingOpened.remove(coursePath)
        }
        return false
    }

    /// The note was answered "Open in Obsidian": remember it was shown, and
    /// open the folder it was asked for.
    func openInObsidianAfterTheNote(_ request: LockedPagesNoteRequest) {
        LockedPagesNote.remember(courseCode: request.course.code)
        lockedPagesNoteRequest = nil
        obsidianOpening.open(request.folder, request.course.directoryURL)
    }

    /// The offer was answered (#495). Obsidian opens after every answer.
    func answerObsidianAddOnsOffer(_ request: ObsidianAddOnsRequest, _ answered: ObsidianFigureAddOnsTrail.Answered) async {
        obsidianAddOnsOfferRequest = nil
        ActivityTrail.note(.obsidianAddOnsOffered, ObsidianFigureAddOnsTrail.offered(course: request.course.code, answered: answered))
        let settings: AppSettings = obsidianOpening.settings ?? AppSettings.shared
        switch answered {
        case .addThem:
            settings.obsidianFigureAddOns = .yes
            if request.courseIsOpen {
                await reopenObsidianWithAddOns(request)
                return
            }
            await addObsidianAddOns(toCourse: request.course, request.needed, trigger: .openInObsidian)
        case .notNow:
            ObsidianFigureAddOnsThisRun.suppressed = true
        case .notNowDontAskAgain:
            settings.obsidianFigureAddOns = .no
        }
        obsidianOpening.open(request.folder, request.course.directoryURL)
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
        obsidianOpening.open(request.folder, request.course.directoryURL)
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
                courseOpenInObsidian: self.vaultsOpenInObsidian().contains(coursePath)
            )
            if decision == .install {
                await self.addObsidianAddOns(toCourse: course, scanned.needed, trigger: .afterAPreview)
            }
        }
    }

    // MARK: - Private helpers

    /// What Open in Obsidian does once the scan is back.
    private func openInObsidian(course: Course, folder: URL, needed: [ObsidianFigureAddOn], wouldAdd: [ObsidianFigureAddOn]) async {
        let settings: AppSettings = obsidianOpening.settings ?? AppSettings.shared
        let coursePath: String = course.directoryURL.path
        let target: URL = FolderActions.obsidianTarget(forFolder: folder, vaultURL: course.directoryURL)
        let situation: ObsidianFigureAddOnsOffer.Situation = ObsidianFigureAddOnsOffer.Situation(
            reference: course.isKeptForReference,
            obsidianInstalled: true,
            answer: settings.obsidianFigureAddOns,
            suppressedThisRun: ObsidianFigureAddOnsThisRun.suppressed,
            wouldAdd: !wouldAdd.isEmpty,
            vaultIsTheCourse: ObsidianFigureAddOnsOffer.vaultIsTheCourse(
                targetPath: target.path, coursePath: coursePath, registryData: obsidianOpening.registryData()
            ),
            courseOpenInObsidian: vaultsOpenInObsidian().contains(coursePath),
            reopenDeclinedThisRun: ObsidianFigureAddOnsThisRun.reopenDeclined.contains(coursePath)
        )
        switch ObsidianFigureAddOnsOffer.decision(situation) {
        case .justOpen:
            obsidianOpening.open(folder, course.directoryURL)
        case .notTheVault:
            let line: String = ObsidianFigureAddOnsTrail.notTheVault(course: course.code)
            if !ObsidianFigureAddOnsThisRun.linesWritten.contains(line) {
                ObsidianFigureAddOnsThisRun.linesWritten.insert(line)
                ActivityTrail.note(.obsidianAddOnsOffered, line)
            }
            obsidianOpening.open(folder, course.directoryURL)
        case .offer:
            obsidianAddOnsOfferRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: needed, courseIsOpen: false)
        case .offerWhileOpen:
            obsidianAddOnsOfferRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: needed, courseIsOpen: true)
        case .installThenOpen:
            await addObsidianAddOns(toCourse: course, needed, trigger: .openInObsidian)
            obsidianOpening.open(folder, course.directoryURL)
        case .askReopen:
            obsidianReopenRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: needed, courseIsOpen: true)
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
            obsidianOpening.open(request.folder, request.course.directoryURL)
            return
        }
        await addObsidianAddOns(toCourse: request.course, request.needed, trigger: .afterReopening)
        ActivityTrail.note(.obsidianReopenedForAddOns, ObsidianFigureAddOnsTrail.reopened(course: request.course.code))
        obsidianOpening.reopen(wereOpen)
        obsidianOpening.open(request.folder, request.course.directoryURL)
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
