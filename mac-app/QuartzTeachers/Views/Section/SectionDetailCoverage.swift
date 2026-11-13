import SwiftUI

/// The section page's tabs and its Coverage tab (#793), kept apart from
/// `SectionDetailView`'s own file, whose chain is at the type checker's
/// limit.
extension SectionDetailView {

    // MARK: - Computed properties

    /// The tabs in the bar (`SectionTabs.shown`), empty when Website would
    /// be the only one.
    var shownTabs: [SectionTab] {
        guard let folder = workspace.workspaceURL else {
            return []
        }
        let sectionKey: String = SectionCoverage.shared.key(folder: folder, course: course, sectionNumber: sectionNumber)
        let entry: SectionCoverage.Entry = SectionCoverage.shared.entry(sectionKey)
        return SectionTabs.shown(
            hasCurriculum: entry.hasCurriculum,
            recordHasMaps: entry.reading?.hasMaps ?? false,
            hasProblems: showsTheProblemsTab
        )
    }

    /// Each tab in the bar with the word it shows.
    var tabsInTheBar: [(tab: SectionTab, title: String)] {
        var tabs: [(tab: SectionTab, title: String)] = []
        for tab in shownTabs {
            switch tab {
            case .website:
                tabs.append((tab: tab, title: SectionProblemsWording.tabWebsite))
            case .coverage:
                tabs.append((tab: tab, title: CoverageTabWording.tabCoverage))
            case .problems:
                tabs.append((tab: tab, title: SectionProblemsWording.tabProblems))
            }
        }
        return tabs
    }

    /// The tab showing: the one chosen while it is in the bar, otherwise
    /// Website (`SectionTabs.showing`).
    var selectedTab: SectionTab {
        guard let folder = workspace.workspaceURL else {
            return .website
        }
        let chosen: SectionTab = SectionProblems.shared.chosenTab(
            folder: folder, courseCode: course.code, sectionNumber: sectionNumber
        )
        return SectionTabs.showing(chosen: chosen, shown: shownTabs)
    }

    var selectedTabBinding: Binding<SectionTab> {
        return Binding(
            get: { selectedTab },
            set: { chosen in
                if let folder = workspace.workspaceURL {
                    SectionProblems.shared.show(chosen, folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
                }
            }
        )
    }

    /// Whether the preview may take the browser commands: only while the
    /// Website tab shows, the only time it is in the window.
    var previewTakesCommands: Bool {
        return SectionTabs.previewTakesCommands(showing: selectedTab)
    }

    /// Whether what a build can raise waits: while Coverage shows.
    var alertsWaitForCoverage: Bool {
        return SectionTabs.alertsWait(showing: selectedTab)
    }

    /// This window's own preview is building: from the press until its site
    /// first answers.
    var ownBuildIsRunning: Bool {
        return previewRunner.isRunning && isWaitingForServer
    }

    /// The same, before the build has printed its problems line, which
    /// comes straight after the map is written.
    var ownBuildIsBeforeItsMap: Bool {
        return ownBuildIsRunning && previewRunner.problemsMarkers.isEmpty
    }

    /// Another window of this app holds this section's preview.
    var anotherWindowHoldsThePreview: Bool {
        guard previewLease == nil, let folder = workspace.workspaceURL else {
            return false
        }
        for lease in PreviewLeases.active {
            if lease.courseCode == course.code
                && lease.sectionNumber == sectionNumber
                && FolderIdentity.isSameFolder(lease.folderPath, folder.path) {
                return true
            }
        }
        return false
    }

    /// The Website tab: the console or the placeholder, and the site over
    /// them, exactly as the page always drew them.
    var websiteLayers: some View {
        ZStack {
            // Base layer: always laid out in the normal, safe-area
            // respecting flow. Keeping it mounted means its geometry is
            // never inherited from the full-bleed web view above it —
            // which is what dragged the progress header under the
            // window's toolbar when a preview was restarted.
            VStack(spacing: 0) {
                if isWaitingForServer || isBusy || !previewRunner.transcript.lines.isEmpty || deployRun.isShown(hidingEnding: deployEndingHiddenHere) {
                    consoleArea
                } else {
                    // Fills the height it is offered, which is what keeps
                    // the notice above it flush under the toolbar: a layer
                    // that claims less than the stack offers is CENTRED by
                    // it, and the notice floated mid-window. See the view's
                    // own comment for the measurement.
                    NoPreviewPlaceholderView(
                        deploysToLocalFolder: course.configuration.deploysToLocalFolder,
                        keptForReferenceCode: course.isKeptForReference ? course.displayCode : ""
                    )
                }
            }

            // Cover layer: the site itself, full-bleed within whatever
            // room the notice leaves. It stays in this one branch however
            // the notice comes and goes — the web view is a live WKWebView
            // with a page scrolled to where the teacher left it, and
            // moving it between containers is how that gets thrown away.
            // Leaving the WINDOW, when another tab is chosen, keeps both:
            // the controller owns the web view (#793).
            if let previewURL {
                WebPreviewView(controller: previewController, url: previewURL)
                    // The page the teacher navigated to, remembered for
                    // "Preview at Last Viewed" (#504). Here, on the site
                    // itself, so nothing is remembered while no site is
                    // showing; and only the TEACHER's navigations move
                    // the counter (`PreviewNavigationLedger`).
                    .onChange(of: previewController.teacherNavigations) { _, _ in
                        rememberWhereTheTeacherIs()
                    }
                    .task {
                        // A task rather than an appearance block: the section's
                        // registering appearance block is found by a source scan
                        // (WorkingFolderSelectionTests) as the view's first one.
                        notePagesHandedToTheBrowser()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("previewWebView")
            }
        }
    }

    /// The Coverage tab (#793).
    @ViewBuilder
    var coverageTab: some View {
        if let folder = workspace.workspaceURL {
            CoverageTabView(
                course: course,
                sectionNumber: sectionNumber,
                folder: folder,
                ownBuildBeforeItsMap: ownBuildIsBeforeItsMap,
                ownBuildRunning: ownBuildIsRunning,
                deploying: SectionDetailView.deployIsUnderWay(
                    run: deployRun, folderPath: folder.path, courseCode: course.code, sectionNumber: sectionNumber
                ),
                otherWindow: anotherWindowHoldsThePreview,
                folderIsReady: !(workspace.isBeingCopied(course.code) || workspace.folderIsGettingReady),
                folderNotReadyReason: workspace.folderReadinessReason,
                makeAgain: makeTheCoverageMapAgain,
                openCode: openCoverageCode
            )
        }
    }

    /// The Problems tab (#717), drawn instead of the site rather than over
    /// it since #793.
    @ViewBuilder
    var problemsTab: some View {
        if let folder = workspace.workspaceURL, let record = problemsRecord {
            ProblemsTableView(
                course: course,
                sectionNumber: sectionNumber,
                folder: folder,
                record: record,
                others: SectionProblems.shared.otherRecords(folder: folder, course: course, sectionNumber: sectionNumber),
                repair: repairFromTheProblemsTab
            )
        }
    }

    // MARK: - Functions

    /// What the section watches for its Coverage tab: a run starting or
    /// ending (the map is read again, and a refresh still waiting is settled
    /// when this window's build ends), the app coming to the front, and the
    /// teacher leaving the tab, which raises whatever waited while it showed.
    func watchingTheCoverageTab(_ content: some View) -> some View {
        content
            .onChange(of: isBusy) { _, _ in
                reloadTheCoverage(afterThisRunsMarker: false)
            }
            // The wait for this window's preview ends when its site first
            // answers, or when the run ends or is stopped. By the time a site
            // answers, its build has printed its problems line (the map is
            // written before Quartz), so a refresh still waiting then made no
            // map. Asked again at the callback: a stale end of the run before
            // a refresh's own build is not this build's end, and by then the
            // new wait has begun.
            .onChange(of: isWaitingForServer) { _, waiting in
                reloadTheCoverage(afterThisRunsMarker: false)
                if !waiting && !isWaitingForServer {
                    noteTheCoverageRunEnded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // A build this window did not watch (a scheduled deploy, an
                // outside assistant) may have made the map again.
                reloadTheCoverage(afterThisRunsMarker: false)
            }
            .onChange(of: selectedTab) { previous, now in
                if previous == .coverage && now != .coverage {
                    raiseWhatWaitedForCoverage()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                // Quitting while a refresh waits for the old preview to stop:
                // nothing may start after this.
                SectionCoverage.shared.abandonEveryRefresh()
            }
            .task {
                if let folder = workspace.workspaceURL {
                    SectionCoverage.shared.noteShown(
                        SectionCoverage.shared.key(folder: folder, course: course, sectionNumber: sectionNumber)
                    )
                }
                reloadTheCoverage(afterThisRunsMarker: false)
            }
    }

    /// Reads this section's map record again.
    func reloadTheCoverage(afterThisRunsMarker: Bool) {
        guard let folder = workspace.workspaceURL else {
            return
        }
        SectionCoverage.shared.reload(
            folder: folder, course: course, sectionNumber: sectionNumber, afterAMarker: afterThisRunsMarker
        )
    }

    /// This window's preview run ended or was stopped, or the view is going
    /// away: a refresh still waiting is settled now.
    func noteTheCoverageRunEnded() {
        guard let folder = folderThisSectionWorksIn ?? workspace.workspaceURL else {
            return
        }
        SectionCoverage.shared.noteOwnRunEnded(folder: folder, course: course, sectionNumber: sectionNumber)
    }

    /// Make the Map (Again): the section's ordinary preview build, started
    /// in the background (Russell's rulings, 2026-11-12). Not the Preview
    /// button's path (`pressPreview`), which can ask about today's class:
    /// `startPreview()`, as every other way in. A preview already running is
    /// stopped first and waited for, as a repair's rebuild does, since a
    /// second one cannot have its port. The teacher stays on this tab;
    /// nothing is opened and no alert is raised (`alertsWaitForCoverage`).
    ///
    /// The press is recorded at once, before anything is awaited
    /// (`SectionCoverage.makeAgain`; the 793b review's H1): from that instant
    /// the tab says the map is being made and the button is unavailable, a
    /// second press does nothing, and leaving the section, the course or the
    /// window during the stop (`onDisappear`) abandons the press, so the
    /// start never runs from a view that has gone.
    func makeTheCoverageMapAgain() {
        guard let folder = workspace.workspaceURL else {
            return
        }
        let previewIsRunning: Bool = previewLease != nil || previewRunner.isRunning
        Task { @MainActor in
            await SectionCoverage.makeAgain(
                store: SectionCoverage.shared,
                folder: folder,
                course: course,
                sectionNumber: sectionNumber,
                previewIsRunning: previewIsRunning,
                stop: {
                    await stopPreviewAndWait()
                },
                start: {
                    startPreview()
                    // `startPreview` returns without starting anything while
                    // the course is being copied, or when it refuses: then
                    // no lease is held.
                    return previewLease != nil
                }
            )
        }
    }

    /// The section's page is going away: a refresh still starting is
    /// abandoned, and the map's web view released when no other window
    /// shows the section.
    func letTheCoverageTabGo() {
        guard let folder = folderThisSectionRegisteredIn ?? workspace.workspaceURL else {
            return
        }
        let coverage: SectionCoverage = SectionCoverage.shared
        coverage.abandonRefresh(folder: folder, course: course, sectionNumber: sectionNumber)
        coverage.noteGone(coverage.key(folder: folder, course: course, sectionNumber: sectionNumber))
    }

    /// A click on a code in the map: the record read again, the file it
    /// names checked again (`CoverageItem.resolve`), then opened through
    /// Open in Obsidian's own route. Anything else says why in the tab and
    /// on the trail, and opens nothing.
    func openCoverageCode(_ url: URL) {
        guard let link = CoverageLink.parse(url), let folder = workspace.workspaceURL else {
            return
        }
        let coverage: SectionCoverage = SectionCoverage.shared
        let sectionKey: String = coverage.key(folder: folder, course: course, sectionNumber: sectionNumber)
        if !FolderActions.obsidianIsInstalled {
            ActivityTrail.note(
                .pageOpenedInObsidian,
                CoverageTabTrail.didNotOpenText(code: link.code, why: CoverageTabTrail.whyNoObsidian),
                course: course.code, section: sectionNumber
            )
            return
        }
        coverage.reload(folder: folder, course: course, sectionNumber: sectionNumber)
        let record: CoverageTabRecord? = coverage.entry(sectionKey).reading?.record
        let outcome: CoverageItem.Outcome = CoverageItem.resolve(link, record: record, courseFolder: course.directoryURL)
        let words: String = CoverageTabTrail.clickText(outcome, code: link.code)
        switch outcome {
        case .open(let file, _):
            workspace.openExpectationInObsidian(
                course: course, sectionNumber: sectionNumber, page: file, trailWords: words
            )
        case .gone:
            ActivityTrail.note(.pageOpenedInObsidian, words, course: course.code, section: sectionNumber)
            coverage.noteClickLine(CoverageTabWording.sentence("pageGone", code: link.code), key: sectionKey)
        case .outside:
            ActivityTrail.note(.pageOpenedInObsidian, words, course: course.code, section: sectionNumber)
            coverage.noteClickLine(CoverageTabWording.sentence("pageOutside", code: link.code), key: sectionKey)
        case .reload, .notListed:
            // The page on screen was older than its record (reading it
            // again above brings the newer page), or names a code the
            // record does not list: nothing opens.
            ActivityTrail.note(.pageOpenedInObsidian, words, course: course.code, section: sectionNumber)
        }
    }

    /// The teacher left the Coverage tab: what waited while it showed is
    /// raised now, one at a time, the way it would have been.
    func raiseWhatWaitedForCoverage() {
        showAnythingWaiting()
        offerTheLinksChecklistIfWaiting()
    }

    /// A preview's refusal: said in the tab, and not as an alert, only when
    /// it refuses the tab's OWN refresh (`SectionTabs.refusalIsTheTabs`). A
    /// refusal of the teacher's own Preview press is shown as ever, Coverage
    /// or not (the 793b review's M2). Answers whether it was taken.
    func takeARefusalOnCoverage(title: String, sentence: String) -> Bool {
        guard let folder = workspace.workspaceURL else {
            return false
        }
        let sectionKey: String = SectionCoverage.shared.key(folder: folder, course: course, sectionNumber: sectionNumber)
        if !SectionTabs.refusalIsTheTabs(refresh: SectionCoverage.shared.entry(sectionKey).refresh) {
            return false
        }
        SectionCoverage.shared.noteRefreshRefused(
            folder: folder, course: course, sectionNumber: sectionNumber, reason: sentence
        )
        return true
    }
}
