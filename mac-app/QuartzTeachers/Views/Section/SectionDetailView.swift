import SwiftUI

/// One section of a course: Preview builds and serves the site with
/// `preview.sh` and shows it in an embedded web view; Deploy publishes it
/// with `deploy.sh`. All output streams into a console below.
struct SectionDetailView: View {

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int

    @State var previewRunner = ScriptRunner()

    /// The run this view shows while the window has no working folder — a
    /// moment, not a state anyone deploys from (`deployAndWait` refuses
    /// without a folder). Every real deploy lives in `SectionRuns` (#706);
    /// see `deployRun`.
    @State var deployRunWithNoFolder: SectionDeployRun = SectionDeployRun()

    /// The section deploy's ending this view keeps off its console: set on
    /// appearing when some view has already shown that ending (#706 review,
    /// M1), so a finished deploy is shown on return only until one view has
    /// displayed it. A later ending is a different number, so the next
    /// deploy is shown as ever.
    @State var deployEndingHiddenHere: Int? = nil

    @State var previewController = WebPreviewController()
    @State var previewURL: URL?

    /// Whether this window is the key window, for the Preview button's
    /// Option title (#504).
    @Environment(\.controlActiveState) var controlActiveState

    /// The ROOT of the site this run serves, set beside `previewURL` when the
    /// server first answers and cleared wherever it is (#504). Kept apart
    /// because `previewURL` may now be the page last viewed rather than the
    /// root: what the teacher navigates to is remembered RELATIVE to the
    /// root, and measured against a page it would come out wrong (504 plan
    /// review, finding 7).
    @State var previewRoot: URL?

    /// What the teacher's press asked for (#504), held while the question
    /// about today's class is up and read once it has gone.
    @State var pendingPreviewRequest: PreviewStartPage.Request = .frontPage
    /// The wait for this window's preview, and the record ⌘Q reads while it
    /// lasts (issue #232). Cleared only through `previewBuildWait.end()`, so
    /// the record cannot outlive the wait — see `PreviewBuildWait`.
    @State var previewBuildWait: PreviewBuildWait = PreviewBuildWait()

    /// The port this window's preview holds, while it holds one.
    @State var previewLease: PreviewLeases.Lease?

    /// The folder this view REGISTERED itself under in
    /// `SectionWindowControllers`, and the only thing the unregister may read.
    ///
    /// Written in exactly one place — `.onAppear`, before the registration —
    /// and read in exactly one place, the unregister in `onDisappear`. That
    /// is what makes "a registration and its unregister name the same folder"
    /// true by construction rather than by everything happening to line up,
    /// and the registry has no other way to forget a key: nothing sweeps it,
    /// so an entry unregistered under the wrong folder is stranded for the
    /// life of the app.
    ///
    /// It is NOT `workspace.workspaceURL`, for the reason the piece was
    /// written: choosing a different working folder clears the selection,
    /// which tears this view down, and `onDisappear` runs on a later pass
    /// with the window already pointing somewhere else.
    ///
    /// And it is not the same property as `folderThisSectionWorksIn` below,
    /// which is the finding that split them. One property doing both jobs was
    /// wrong for a window one render pass wide: between the selection being
    /// cleared and `onDisappear` running, the assistant can still find this
    /// controller registered under the OLD folder and press Deploy — and a
    /// deploy notes the folder its work belongs to, which would have moved
    /// the key the unregister then used.
    @State var folderThisSectionRegisteredIn: URL?

    /// The working folder the work in flight belongs to — and the folder
    /// every stop and cancel must be aimed at, whatever the window points at
    /// by the time the stop runs.
    ///
    /// Written where a piece of work's folder is DECIDED: `startPreview()`,
    /// beside the lease, and `deployAndWait()`. Not on appearance, and not
    /// from the model at the moment of stopping — the first would say nothing
    /// about what is actually running, and the second is the bug: a stop read
    /// from the model during teardown runs the NEW folder's `preview.sh` for
    /// a section that folder may not even have, while the old folder's
    /// container-side build or server keeps going (which matters when another
    /// window still holds that folder — when the last one leaves, its
    /// container is already being stopped). Writing it where the work starts
    /// is what makes start and stop name one folder by construction.
    ///
    /// Nil means there is nothing to stop, and every reader is already
    /// guarded by `previewRunner.isRunning` or `deployRunner.isRunning`.
    ///
    /// **One note serves both a preview and a deploy, deliberately.** They
    /// never run at once for this section: `deployAndWait()` stops a running
    /// preview and waits for it before it notes anything of its own, and the
    /// Preview button is disabled while a deploy runs. Splitting this further
    /// would be two names for one folder.
    @State var folderThisSectionWorksIn: URL?

    /// What the preview alert says: why a preview could not start or did not
    /// appear, or — since #397 — the question about today's class on the
    /// front page.
    ///
    /// Each carries its own TITLE, because different things arrive in this
    /// one alert and one title cannot be true of all of them. "Cannot Preview
    /// Yet" is right for a refusal to start — another window holds the
    /// section, so wait and it will work. It is wrong in front of a preview
    /// that built, was served, and could not be reached: there the remedy is
    /// restarting the Mac and "Yet" quietly says otherwise. A SECOND `.alert`
    /// modifier was the obvious alternative and is the one thing this view
    /// must not have — four alerts on it segfaulted SwiftUI's bridge, which is
    /// why the folder dialogs share one, and why the #397 question rides this
    /// one rather than adding a fourth.
    ///
    /// **Held after the alert has gone, and replaced only by the next one.**
    /// Presentation is `previewAlertIsUp`; this is never cleared by the
    /// dismissal, so the title and buttons cannot change while the alert
    /// fades — clearing it there flashed "Cannot Preview Yet" behind a
    /// question the teacher had just answered (#397 plan review, 2).
    @State var previewAlert: PreviewAlert = .refusal(title: "", sentence: "")

    /// Whether the preview alert is up. Written true only through
    /// `showPreviewRefusal` and `pressPreview`; SwiftUI writes it false.
    @State var previewAlertIsUp: Bool = false

    enum PreviewAlert: Equatable {
        case refusal(title: String, sentence: String)
        case todaysClass(TodaysClassOnTheFrontPage.Offer)
    }

    /// A refusal that arrived while the question about today's class was up
    /// — the assistant can start a preview then — shown once it has gone.
    @State var heldPreviewRefusal: PreviewAlert?

    /// A late "preview did not appear" that arrived while the Coverage tab
    /// showed (#793, the 793b fix review's M2): shown when the teacher
    /// leaves the tab, never over it.
    @State var refusalHeldOnCoverage: PreviewAlert?

    /// This view, as the one that pressed Make the Map Again: another window
    /// on the same section settles nothing of its press (#793).
    @State var coverageOwner: UUID = UUID()

    /// Whether this section's preview was handed to the web browser (Open in
    /// Browser, or a link the preview opens there): a restart of the preview
    /// leaves that browser tab without its live reload, which the Coverage
    /// tab then says (#793, the 793b fix review 2's M1).
    @State var previewIsInTheBrowser: Bool = false


    /// Set by the question's answer, and acted on once the alert has GONE
    /// (`afterThePreviewAlert`): the preview starts then, never from inside
    /// the alert's own button, where a refusal it raised would be lost with
    /// the dismissal (#397 plan review, 1).
    @State var startPreviewWhenTheQuestionHasGone: Bool = false

    /// Why the front page was not changed after Show on Front Page, said once
    /// the question has gone — unless starting the preview had something to
    /// say first (the trail has both).
    @State var frontPageNotChanged: String?

    /// A deploy that was set to happen on its own and did not get through.
    ///
    /// Read from disk rather than held in memory, because the run that wrote
    /// it happened at half six with this app closed. Nil when the last
    /// scheduled run got through, when there has never been one, or when the
    /// teacher has dismissed it.
    @State var stoppedScheduledPublish: ScheduledPublishOutcome.Stopped?

    /// Said when a preview starts while Course Settings holds changes nobody
    /// saved (issue #265): the preview reads the saved settings, so the
    /// switches and the page can disagree. Cleared when the preview stops or
    /// starts again with nothing unsaved. Since #335 a deploy says its own
    /// sentence here too — see `unsavedSettingsNoticeOwner`.
    @State var unsavedSettingsNotice: String? = nil

    /// Whose sentence `unsavedSettingsNotice` is (#335, the implementation
    /// review's F3). A preview's end clears only the PREVIEW's sentence:
    /// `releasePreviewLease()` is also reached from the preview's wait loops,
    /// which poll once a second and can wake after a deploy has set its own
    /// sentence, so relying on the deploy setting it after the stop was a
    /// race that usually went the right way. A state, not an ordering.
    @State var unsavedSettingsNoticeOwner: UnsavedSettingsNoticeOwner? = nil

    /// The folder problems the alert about new problems offers to repair
    /// (#717): its NEW rows that have a repair, as the findings
    /// `SiteHealthRepair` acts on. Empty when nothing new can be repaired.
    @State var healthFindings: [SiteHealthFinding] = []

    /// The record the alert about new problems is about, while it is up
    /// (#717). The alert replaced the per-build folder-problem dialog: it is
    /// raised only when a build found something NEW, once per record's alert
    /// key (`sectionProblems.alert`), and points at the Problems tab. Nothing
    /// is queued behind another dialog: an alert that is due stays due in the
    /// store until it is answered, so whatever is in front of it going away
    /// is enough to raise it (`showAnythingWaiting`).
    @State var problemsAlert: SectionProblemsRecord?

    /// What a repair just did, while that is being shown.
    @State var repairOutcome: SiteHealthRepair.Outcome?

    /// The same, waiting for the alert it was requested from to go away.
    @State var pendingRepairOutcome: SiteHealthRepair.Outcome?

    /// Which of the two folder dialogs is up, if either. One alert modifier
    /// serves both — see the comment on it.
    @State var healthDialog: HealthDialog?

    enum HealthDialog {
        case findings
        case outcome
    }

    /// Whether the findings on screen came from PUBLISHING rather than from a
    /// preview — including an overnight publish reported the next morning.
    ///
    /// It chooses the SENTENCE and nothing else. The preview is offered either
    /// way; what differs is whether the teacher is also told that publishing
    /// again is what reaches students.
    @State var healthFindingsCameFromPublishing: Bool = false

    /// The links checklist on screen (#379), or waiting for the alert in
    /// front of it to go (`repair.oneAlertAtATime`).
    @State var linksChecklist: LinksChecklistSheetModel?
    @State var pendingLinksChecklist: LinksChecklistSheetModel?

    /// The #333 finding, held while the build that reported it has not yet
    /// said whether it wrote an offer — the finding is announced BEFORE the
    /// build's date passes, and the offer after them (plan review, F14).
    @State var heldLinksFinding: (finding: SiteHealthFinding, cameFromPublishing: Bool)?

    /// This view's own window, by identity only — never retained — so the
    /// links checklist is offered on the window that became key (#379).
    @State var ownWindowID: ObjectIdentifier?

    /// Offers already put in front of the teacher from this window, by build,
    /// so the second look at a build's findings does not ask twice.
    @State var linksChecklistBuildsHandled: Set<String> = []

    /// Why a deploy could not start, shown as an alert.
    @State var deployRefusal: String?

    /// For the deploy refusal's Open Settings… (#668).
    @Environment(\.openSettings) var openSettings

    /// Whether this section's pages have changed since it last published
    /// — the " — Edited" marker in the title bar.
    ///
    /// Held rather than computed on every redraw, and refreshed only at
    /// the moments a teacher could be LOOKING at the title bar: the window
    /// arriving, the app coming to the front, this window becoming the key
    /// one, and a publish or preview finishing. A body that recomputed it
    /// would walk the course folder every time a console line arrived.
    @State var hasUnpublishedEdits: Bool = false

    /// Which refresh is the current one. `NSWindow.didBecomeKeyNotification`
    /// fires for EVERY window and panel in the app — the assistant, a
    /// settings sheet, an alert — and app activation fires alongside it, so
    /// several walks can be in flight at once. Without this counter their
    /// results land in whatever order they finish, and a walk begun before
    /// a publish can overwrite the answer from one begun after it: the
    /// window says " — Edited" about a section that has just gone out.
    @State var refreshGeneration: Int = 0

    /// The Section menu's sheet (#457 batch B) — one of the assistant's
    /// functions, the class dates it needs first, or #475's question at
    /// Deploy. One sheet at a time; see `SectionVerbSheetModel`.
    @State var verbSheet: SectionVerbSheetModel?

    /// What runs once the sheet in front has gone: the function the class
    /// dates were asked for (#457's plan review, blocker 1).
    @State var afterTheVerbSheet: (() -> Void)?

    /// The answer of a function with no sheet of its own (Undo Last Change,
    /// a refused Rebuild Preview, Add Next Class) that arrived while
    /// something else was on the window — shown when that has gone, never
    /// dropped (#457 batch B's review, note 4).
    @State var pendingVerbResult: SectionVerbSheetModel?

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Computed properties

    /// True from the press until the preview's page first answers or the run
    /// ends — read through `previewBuildWait`, which is the only thing that
    /// can change it (issue #232).
    var isWaitingForServer: Bool {
        return previewBuildWait.isWaiting
    }

    /// What this section is CALLED — used wherever a sentence names it
    /// ("Deploying ICS3U-S1"). Deliberately without the " — Edited"
    /// marker: the marker is a statement about the window's contents, not
    /// part of the section's name, and "Deploying ICS3U-S1 — Edited" reads
    /// as though "Edited" were something being deployed.
    var sectionName: String {
        // `displayCode`: a reference course's window says "ICS3U-S1", never
        // "ICS3U-2025-S1". Identical to `code` for every course a teacher
        // teaches.
        return "\(course.displayCode)-S\(sectionNumber)"
    }

    /// What the window's title bar says — the name, plus the marker when
    /// there is something unpublished.
    var titleText: String {
        return SectionPublishState.windowTitle(
            base: sectionName,
            hasUnpublishedEdits: hasUnpublishedEdits
        )
    }

    var isBusy: Bool {
        return previewRunner.isRunning || deployRunner.isRunning
    }

    /// This section's deploy, as the app holds it for the life of the app
    /// rather than for the life of this view (#706): the view is rebuilt on
    /// every selection, and a deploy outlives it. A view that comes back to
    /// the section finds the same object the deploy is still writing.
    ///
    /// For `body` only. Anything that AWAITS — `deployAndWait`,
    /// `cancelDeploy` — takes the run once, from the folder it has already
    /// checked, and keeps that object: this property is asked again on
    /// every read, and a window pointed at another folder mid-deploy would
    /// otherwise hand the second half of a deploy a different run (#706
    /// plan review, H1).
    var deployRun: SectionDeployRun {
        guard let folder = workspace.workspaceURL else {
            return deployRunWithNoFolder
        }
        return SectionRuns.shared.deploy(folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
    }

    /// Runs every configured destination in sequence — see
    /// `MultiDestinationDeployRunner`. For the overwhelming majority of
    /// courses (exactly one destination) this behaves exactly like a
    /// single `ScriptRunner` always did. Read through `deployRun`, so it is
    /// the section's runner, not this view's.
    var deployRunner: MultiDestinationDeployRunner {
        return deployRun.runner
    }

    /// True from the moment Deploy is pressed until `deployRunner` actually
    /// starts running — the span spent stopping any preview and doing the
    /// pre-flight checks below, before there is any real progress to show.
    /// `consoleArea` shows a plain "Preparing to deploy…" placeholder while
    /// this is true, instead of `TaskProgressView` bound to a `deployRunner`
    /// that has nothing to say yet — a fresh, idle runner renders as
    /// nothing at all (see `deployAndWait()`), and the PREVIOUS deploy's
    /// runner still holding last time's finished outcome is no better,
    /// since neither is what is actually happening right now.
    var isPreparingDeploy: Bool {
        return deployRun.isPreparing
    }

    /// Whether Option re-titles THIS window's Preview button (#504): only
    /// while the window is key. `controlActiveState` is read first, so a
    /// window that is not key never reads the watcher and is not redrawn as
    /// Option comes and goes elsewhere (implementation review, 4).
    var optionRetitlesThisWindow: Bool {
        if controlActiveState != .key {
            return false
        }
        return OptionKeyWatcher.shared.optionIsHeld
    }

    /// The Preview (or Stop Preview) button's enablement — read by the
    /// button and by Section ▸ Preview alike (#457).
    ///
    /// Not while a copy of the course is being zipped (#351): a restore or
    /// removal is waiting on that zip to replace the folder a preview would
    /// be serving from. Nor while the folder's tools are still being copied,
    /// or that copy failed (#476): the help says why, no dialog.
    var previewButtonIsEnabled: Bool {
        if previewRunner.isRunning {
            return true
        }
        return !(isBusy || workspace.isBeingCopied(course.code) || workspace.folderIsGettingReady)
    }

    /// The Deploy button's enablement — read by the button and by Section ▸
    /// Deploy… alike (#457). See the button for each clause's reason.
    var deployButtonIsEnabled: Bool {
        return SectionDetailView.deployIsAvailable(
            run: deployRun,
            folderPath: workspace.workspaceURL?.path,
            courseCode: course.code,
            sectionNumber: sectionNumber,
            isBeingCopied: workspace.isBeingCopied(course.code),
            folderIsGettingReady: workspace.folderIsGettingReady,
            heldElsewhere: courseIsHeldElsewhere
        )
    }

    /// The watcher for this window's folder's leases (#729), or nil when
    /// none runs (no folder yet, or the unit-test suite).
    var leaseWatcher: LeaseWatcher? {
        guard let folder = workspace.workspaceURL else {
            return nil
        }
        return LeaseWatchers.shared.watcher(forFolder: folder)
    }

    /// Whether another program holds this course in a way that would refuse
    /// a Deploy pressed here (#729). Read from the watcher, which is
    /// observable, so the button greys and un-greys when its answer moves.
    var courseIsHeldElsewhere: Bool {
        return leaseWatcher?.holding(forCourse: course.code) != nil
    }

    /// The Deploy button's help, and its accessibility hint (#729). The
    /// folder not being ready wins, as it does for every button; then
    /// another program holding the course; then the ordinary words.
    static func deployHelp(folderReadinessReason: String?, heldElsewhere: Bool, courseCode: String) -> String {
        if let folderReadinessReason {
            return folderReadinessReason
        }
        if heldElsewhere {
            return SectionDetailView.deployIsHeldElsewhere(course: courseCode)
        }
        return SectionDetailView.deployOrdinaryHelp
    }

    /// The Deploy button's help when nothing is in its way.
    static let deployOrdinaryHelp: String = "Deploy this section's website"

    /// Why Deploy is greyed while another program holds the course (#729):
    /// `shared-rules.json` → `returningToASectionMidDeploy.heldElsewhere
    /// .help`. Names the three programs a lease can come from, as
    /// `AssistWording.courseIsBeingBuiltElsewhere` does, and promises only
    /// the end each can reach: a preview ends when it is stopped (the plan
    /// review's M6).
    static func deployIsHeldElsewhere(course: String) -> String {
        return "\(course) is being previewed or deployed somewhere else on this computer, "
            + "by an assistant working from another app, another copy of Plantoir, or a deploy set for later. "
            + "Deploy will be available again once that preview is stopped or that deploy has finished."
    }

    /// Whether Deploy may be pressed for a section (#706) — the button,
    /// Section ▸ Deploy… and ⇧⌘D all ask this, and `deployAndWait` and
    /// `deployWillBeRefused` ask its first half, `deployIsUnderWay`.
    ///
    /// Not while a copy of the course is being zipped (#351): a removal
    /// waiting on that zip deletes what this would publish. Not while the
    /// folder's tools are still being copied (#476). Not while another
    /// program holds the course in a way that would refuse the press
    /// (`heldElsewhere`, #729: `LeaseWatcher`), on every section of it,
    /// because a lease names the course.
    static func deployIsAvailable(
        run: SectionDeployRun,
        folderPath: String?,
        courseCode: String,
        sectionNumber: Int,
        isBeingCopied: Bool,
        folderIsGettingReady: Bool,
        heldElsewhere: Bool
    ) -> Bool {
        if deployIsUnderWay(run: run, folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber) {
            return false
        }
        if heldElsewhere {
            return false
        }
        return !(isBeingCopied || folderIsGettingReady)
    }

    /// Whether this app is deploying the section already (#706): its run is
    /// preparing or running, or — from any window, or the assistant with no
    /// window at all — `CourseActivity` has the section publishing. The
    /// second clause is what a view that came back to the section cannot
    /// see in its run when the deploy was started by somebody else in this
    /// app. Another PROGRAM's work is not asked here: `deployIsAvailable`
    /// asks it separately, from `LeaseWatcher` (#729), and the press asks the
    /// leases again (`deployWillBeRefused`).
    static func deployIsUnderWay(
        run: SectionDeployRun,
        folderPath: String?,
        courseCode: String,
        sectionNumber: Int
    ) -> Bool {
        if run.isPreparing || run.runner.isRunning {
            return true
        }
        guard let folderPath else {
            return false
        }
        return CourseActivity.sectionPublishIsRunning(
            folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber
        )
    }

    // MARK: - Body

    var body: some View {
        // Built in stages, each a function below, applied in the order the
        // modifiers have always been applied — the same modifiers on the same
        // view, so nothing a teacher sees moved. One chain of all of them was
        // more than Xcode 26.6 would type-check, and 26.6 builds the releases
        // (#744, `documentation/09-mac-app.md` → "Building with two Xcodes").
        // A new modifier goes into the stage it belongs to, never back into
        // one long chain here.
        let layout: some View = sectionLayout
        let coverage: some View = watchingTheCoverageTab(layout)
        let watching: some View = watchingTheFolderAndTheWindow(coverage)
        let withToolbar: some View = addingTheToolbarAndTheSectionMenu(watching)
        let registered: some View = registeringWhileItShows(withToolbar)
        let alerting: some View = presentingTheAlerts(registered)
        let followingTheAlerts: some View = followingWhatTheAlertsLeave(alerting)
        let withSheets: some View = presentingTheSheets(followingTheAlerts)
        return followingRequestsAndDeployEndings(withSheets)
    }

    /// The notices, the tabs and the stack the site is laid over — what the
    /// stages below are applied to.
    var sectionLayout: some View {
        // The notice is ABOVE everything this section can show, including the
        // site — one band, in one place, in every state.
        //
        // It used to sit in the base layer of the ZStack below, under the
        // full-bleed web view: with a preview showing (the commonest state) a
        // teacher saw nothing but a green tint bleeding through the toolbar,
        // which is issue #219. Putting the band in the layer ABOVE the site
        // would have meant writing it twice — once for each state — so it is
        // here instead, outside the stack altogether. The site takes the room
        // that is left and gets it back the moment the notice is dismissed.
        //
        // REJECTED: `.safeAreaInset(edge: .top)` on the web view, and a second
        // copy of the band inside a cover-layer `VStack`. Both put the band
        // inside the branch that exists only while a preview is up, so the
        // no-preview case needs its own copy — two places to keep in step for
        // one sentence — and both move the band between containers as previews
        // start and stop.
        VStack(spacing: 0) {
            if let stoppedScheduledPublish {
                ScheduledPublishNoticeView(
                    outcome: stoppedScheduledPublish,
                    course: course.code,
                    sectionNumber: sectionNumber,
                    dismiss: dismissScheduledPublishNotice
                )
            }
            if let unsavedSettingsNotice {
                // Its own view, and never `fixedSize` — see the view. Since
                // #335 it may be a deploy's sentence, named for UI tests by
                // whose it is.
                UnsavedSettingsNoticeView(sentence: unsavedSettingsNotice, identifier: unsavedSettingsNoticeIdentifier)
            }
            // Website | Coverage | Problems (#717, #793): Coverage while the
            // course has curriculum expectations, Problems while the
            // section's last build found something. A section with neither
            // shows what it always has. Outside the content, like the
            // notices.
            if !shownTabs.isEmpty {
                DetailTabs(
                    tabs: tabsInTheBar,
                    selection: selectedTabBinding,
                    identifier: "sectionTabs"
                )
            }
            // Only the chosen tab's content is in the window (#793, the plan
            // review's H1): the preview is not under the Coverage or the
            // Problems tab, so no key can reach it. Its web view is owned by
            // `previewController`, so leaving the window keeps its page and
            // its scroll.
            SectionTabContent(showing: selectedTab) {
                websiteLayers
            } coverage: {
                coverageTab
            } problems: {
                problemsTab
            }
            // The build's word that this section's Problems record changed
            // (#717): mid-build, before Quartz, so the alert keeps the timing
            // the folder-problem dialog had (a missing front page stops the
            // preview finishing, #153). On the stack rather than the view's
            // own chain, which is at the type-checker's limit.
            .onChange(of: previewRunner.problemsMarkers.count) { previous, now in
                reloadTheProblems()
                // The map is written before this line, so a refresh waiting
                // on this run now finds its map or knows it made none (#793).
                // Only when a line ARRIVED: the count also falls to nought as
                // a run starts, which says nothing about its map.
                reloadTheCoverage(afterThisRunsMarker: now > previous)
                raiseTheProblemsAlertIfDue()
            }
            // Any other run in this app that printed one — the in-app
            // assistant's build of this section above all (implementation
            // review L5): the open section follows its record whoever built.
            .onChange(of: SectionProblems.shared.markersArrived) { _, _ in
                reloadTheProblems()
                reloadTheCoverage(afterThisRunsMarker: false)
                raiseTheProblemsAlertIfDue()
            }
        }
    }

    /// The title, and what the section watches while it shows: the folder
    /// being read, the app and its window coming to the front, and a
    /// scheduled run's record.
    func watchingTheFolderAndTheWindow(_ content: some View) -> some View {
        content
            .navigationTitle(titleText)
            .task {
                refreshEditedMarker()
                // Another program's leases, read again as the section appears
                // (#729): the watcher's events keep it current from here on.
                leaseWatcher?.reread()
            }
            .onChange(of: isBusy) { _, nowBusy in
                // A publish clears the marker; a preview leaves the content
                // alone but is the other moment the folder has just been read.
                if !nowBusy {
                    refreshEditedMarker()
                    offerTheLinksChecklistIfWaiting()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshEditedMarker()
                leaseWatcher?.reread()
                // A build this window did not watch — the MCP server's, a
                // terminal's — may have rewritten the Problems record (#717).
                reloadTheProblems()
                raiseTheProblemsAlertIfDue()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                refreshEditedMarker()
                leaseWatcher?.reread()
                // A publish this window did not watch — scheduled, the assistant,
                // the MCP server, a terminal — published as it is; the checklist
                // is offered now (Russell's decision 3 on #379). Only when THIS
                // window became key: the notification is app-wide, and the sheet
                // belongs on the window the teacher is looking at (review, N5).
                if let window = notification.object as? NSWindow, let ownWindowID,
                   ObjectIdentifier(window) != ownWindowID {
                    return
                }
                offerTheLinksChecklistIfWaiting()
            }
            .background(WindowAccessor { window in
                ownWindowID = ObjectIdentifier(window)
            })
            // A scheduled run is a separate process, so the FILE it writes is the
            // only event there is. Reading the watcher's counter here is what
            // registers this view as an observer of it; when it moves — a record
            // arrived, one was cleared, or the app came back to the front — the
            // section re-reads its own record and the band appears where the
            // teacher is already looking, instead of waiting for them to click away
            // and back. The sidebar's badge follows the same counter, so the two
            // move together.
            .onChange(of: ScheduledPublishWatcher.shared.generation) { _, _ in
                loadStoppedScheduledPublish()
            }
    }

    /// The toolbar, and what the Section menu and the browser commands read
    /// from this window.
    func addingTheToolbarAndTheSectionMenu(_ content: some View) -> some View {
        content
            .toolbar {
                // Every item is ALWAYS present (disabled when inapplicable):
                // conditionally inserting toolbar items makes macOS rebuild
                // the toolbar, which briefly mis-lays-out the title area.
                ToolbarItemGroup(placement: .navigation) {
                    Button("Back", systemImage: "chevron.left") {
                        previewController.goBack()
                    }
                    .disabled(previewURL == nil || !previewTakesCommands || !previewController.canGoBack)
                    .help("Go back a page")
                    .accessibilityIdentifier("previewBackButton")

                    Button("Forward", systemImage: "chevron.right") {
                        previewController.goForward()
                    }
                    .disabled(previewURL == nil || !previewTakesCommands || !previewController.canGoForward)
                    .help("Go forward a page")
                    .accessibilityIdentifier("previewForwardButton")

                    Button("Reload", systemImage: "arrow.clockwise") {
                        previewController.reload()
                    }
                    .disabled(previewURL == nil || !previewTakesCommands)
                    .help("Reload this page")
                    .accessibilityIdentifier("previewReloadButton")
                }
                ToolbarItemGroup {
                    Button("Open in Obsidian", systemImage: "square.and.pencil") {
                        // The one route (#457, the HIG sweep): on a course kept
                        // for reference it re-locks the pages and shows the note
                        // the first time, as the row and the menu bar do.
                        // #518: the page the preview shows, while it shows one.
                        workspace.openInObsidian(course: course, sectionNumber: sectionNumber, atThePreviewedPage: true)
                    }
                    .disabled(!FolderActions.obsidianIsInstalled)
                    .help("Edit this section's pages in Obsidian")
                    .accessibilityIdentifier("openInObsidianButton")

                    // One stable item that changes face, not two swapped
                    // items — swapping rebuilds the toolbar (same glitch).
                    //
                    // #504: the title says what a press will do — "Preview" or
                    // "Preview at Last Viewed", the setting's or, while Option is
                    // held, the other — from the one function Section ▸ Preview
                    // uses too. The watcher only TITLES it; the press reads the
                    // keyboard at the moment it happens, which is the authority.
                    Button(
                        PreviewStartPage.buttonTitle(
                            setting: AppSettings.shared.previewOpensAt,
                            optionHeld: optionRetitlesThisWindow,
                            previewIsRunning: previewRunner.isRunning
                        ),
                        systemImage: previewRunner.isRunning ? "stop.fill" : "play.fill"
                    ) {
                        previewButtonPressed(opensAt: PreviewStartPage.opensAt(
                            setting: AppSettings.shared.previewOpensAt,
                            optionHeld: PreviewStartPage.optionIsHeld(NSEvent.modifierFlags)
                        ))
                    }
                    // The icon alone doesn't say what these two buttons do, so
                    // they wear their titles; the neighbouring icons are the
                    // familiar Obsidian and Safari actions and stay icon-only.
                    .labelStyle(.titleAndIcon)
                    // Nor while a copy of the course is being zipped (#351): a
                    // restore or removal is waiting on that zip to replace the
                    // folder a preview would be serving from.
                    // Nor while the folder's tools are still being copied, or
                    // that copy failed (#476): the help says why, no dialog.
                    .disabled(!previewButtonIsEnabled)
                    .help(previewRunner.isRunning ? "Stop previewing this section" : (workspace.folderReadinessReason ?? "Preview this section's website"))
                    .accessibilityIdentifier(previewRunner.isRunning ? "stopPreviewButton" : "previewButton")

                    // "Deploy", NOT "Publish" — a page is published (the
                    // `publish:` flag decides whether students see it); the
                    // whole site is deployed. One word for both had the
                    // teacher and the assistant talking past each other.
                    // NOT DRAWN on a course kept for reference. The refusal
                    // behind it stays — every other way in still meets it — but a
                    // teacher meets this as a button that is not there, which is
                    // the same rule the sidebar follows for Schedule Deploy…: a
                    // greyed-out control that can never become available is a
                    // standing invitation to wonder what is wrong.
                    if !course.isKeptForReference {
                    Button("Deploy", systemImage: "paperplane.fill") {
                        startDeploy()
                    }
                    .labelStyle(.titleAndIcon)
                    // `isPreparingDeploy` closes a real window, not just a
                    // display one: `deployRunner.isRunning` alone stays false
                    // through `deployAndWait()`'s whole prep phase (stopping any
                    // preview, waiting for containers to clear), and the button
                    // was clickable again the instant that phase started — a
                    // second click there raced its own stop-preview-then-deploy
                    // sequence against the first's.
                    // Nor while a copy of the course is being zipped (#351): a
                    // removal waiting on that zip deletes what this would publish.
                    .disabled(!deployButtonIsEnabled)
                    .help(SectionDetailView.deployHelp(
                        folderReadinessReason: workspace.folderReadinessReason,
                        heldElsewhere: courseIsHeldElsewhere,
                        courseCode: course.code
                    ))
                    // The same sentence for VoiceOver while another program
                    // holds the course (#729); nothing extra otherwise.
                    .accessibilityHint(courseIsHeldElsewhere && workspace.folderReadinessReason == nil
                        ? SectionDetailView.deployIsHeldElsewhere(course: course.code)
                        : "")
                    // The pointer reaching for a greyed Deploy is the moment a
                    // stale answer would cost the teacher, so read the leases
                    // again then (#729, the plan review's M4). An event, not a
                    // clock.
                    .onHover { inside in
                        if inside {
                            leaseWatcher?.reread()
                        }
                    }
                    .accessibilityIdentifier("deployButton")
                    }

                    Button("Open in Browser", systemImage: "safari") {
                        openInBrowser()
                    }
                    .disabled(previewURL == nil)
                    .help("Open this preview in your web browser")
                    .accessibilityIdentifier("openInBrowserButton")

                }
            }
            // Only while the Website tab shows (#793, the plan review's H1):
            // on Coverage or Problems the preview is not in the window, so
            // ⌘R, ⌘[ and ⌘] must not reach it.
            .focusedSceneValue(\.previewController, previewURL != nil && previewTakesCommands ? previewController : nil)
            // Section ▸ Preview, Deploy… and Open in Browser (#457): the
            // toolbar's own actions and predicates, so the menu item and the
            // button beside it cannot disagree.
            .focusedSceneValue(\.sectionSiteMenu, SectionSiteCommands(
                previewIsRunning: previewRunner.isRunning,
                previewButtonEnabled: previewButtonIsEnabled,
                deployButtonEnabled: deployButtonIsEnabled && !course.isKeptForReference,
                previewIsShowing: previewURL != nil,
                lastChangeIsHere: lastMenuChangeIsHere,
                verbIsRunning: verbIsRunningHere,
                previewOpensAt: AppSettings.shared.previewOpensAt,
                perform: performSiteMenuItem,
                preview: previewFromTheSectionMenu
            ))
    }

    /// What appearing and going away do: the registration the assistant
    /// reaches this window through, the Problems record on opening, and
    /// the preview stopped on the way out.
    func registeringWhileItShows(_ content: some View) -> some View {
        content
            // The assistant cannot drive a preview itself — it holds neither the
            // port lease nor the web view — so this window hands it the things it
            // alone can do. Registered rather than observed: the assistant has to
            // stop the preview, change files, and start it again IN THAT ORDER,
            // and an observer that acts whenever SwiftUI next evaluates a body
            // cannot promise the stop happened before the writes.
            //
            // Deploy is here for a different reason and the same conclusion. The
            // assistant COULD run `deploy.sh` itself, and used to; what it cannot
            // do is show it happening. The console, the progress header and the
            // live-site link all belong to this window, so a deploy run anywhere
            // else is a teacher watching a spinner for four minutes beside a
            // window that says nothing is running.
            //
            // These are the same functions the toolbar buttons call, so the
            // assistant and the buttons can never drift apart.
            .onAppear {
                // Looked for on every appearance rather than once at launch: a
                // section opened after a run finished must show what it left, and
                // this is also what a window restored at launch reads. A run that
                // finishes while this section is ALREADY showing is the watcher's
                // job, above. The trail line belongs to the run, not to either of
                // these reads.
                loadStoppedScheduledPublish()
                // A deploy of this section that outlived the view before this one
                // (#706): what it left for whoever shows the section next. An
                // ending some view has already shown is kept off this console
                // first (#706 review, M1), before this view counts as showing it.
                deployEndingHiddenHere = deployRun.endingToHideOnAppearing()
                takeWhatTheDeployLeft(onAppearing: true)
                guard let folder = workspace.workspaceURL else {
                    return
                }
                // The key this section is about to register under, noted while
                // the window still points here — `onDisappear` runs when it may
                // not. This is the property's ONLY write; see its comment.
                folderThisSectionRegisteredIn = folder
                SectionWindowControllers.shared.register(
                    folderPath: folder.path,
                    courseCode: course.code,
                    sectionNumber: sectionNumber,
                    controller: SectionWindowControllers.Controller(
                        // `previewURL` is the honest signal for "on screen": it
                        // is cleared at the start of every build and set only when
                        // the server has answered.
                        previewState: {
                            if !previewRunner.isRunning {
                                return .notRunning
                            }
                            return previewURL == nil ? .building : .showing
                        },
                        startPreview: { startPreview() },
                        stopPreview: { await stopPreviewAndWait() },
                        deploy: { await deployAndWait(pressedByTheAssistant: true) },
                        // #475: the in-app assistant's deploy asks HERE, before
                        // it stops anything, as the Deploy button does.
                        askAboutClassesDatedLater: {
                            await askAboutClassesDatedLater(route: "the assistant's deploy", askedByTheAssistant: true)
                        },
                        // #518: what Open in Obsidian opens for this section.
                        previewedPage: { previewedPagePath() },
                        // #610: the assistant presses this window's own Open in
                        // Obsidian, on this window's model, as the button does.
                        openInObsidian: {
                            await workspace.openInObsidianAndWait(course: course, sectionNumber: sectionNumber)
                        },
                        // #793: the Coverage tab's own button.
                        makeTheCoverageMapAgain: { makeTheCoverageMapAgain() }
                    )
                )
                // A function asked for from this row's context menu before this
                // window was showing it (#457 batch B).
                takeAVerbRequestIfItIsMine()
            }
            .task {
                // What a build this window did not watch found — an overnight
                // deploy, the assistant, the MCP server, a terminal (#717). The
                // section's Problems record is the one list: it is read here, and
                // its alert raised when it found something new that nobody has
                // answered (`sectionProblems.alert`), which replaces showing the
                // overnight run's folder problems in a dialog of their own.
                guard let workingFolderURL = workspace.workspaceURL else {
                    return
                }
                // The overnight run's own copy of its findings is still TAKEN, so
                // it does not pile up; its trail line was written by the run. The
                // record holds the same problems, one row each.
                _ = ScheduledDeploy.takeFolderProblems(
                    courseCode: course.code, sectionNumber: sectionNumber,
                    inWorkingFolder: workingFolderURL
                )
                reloadTheProblems()
                let checklist: LinksChecklistSheetModel? = linksChecklistWaiting(occasion: .onOpening)
                raiseTheProblemsAlertIfDue()
                // After the alert is up, so it waits behind it.
                if let checklist {
                    requestLinksChecklist(checklist)
                }
            }
            .onDisappear {
                // FIRST, and unconditionally: the wait, and with it ⌘Q's record
                // of a preview being built (issue #232). `stopPreview()` below
                // ends it too; saying so here keeps a window that is going away
                // from depending on what that function happens to do today.
                previewBuildWait.end()
                // The key this section registered under, never the folder its
                // work belongs to and never the window's current one.
                if let folder = folderThisSectionRegisteredIn {
                    SectionWindowControllers.shared.unregister(
                        folderPath: folder.path,
                        courseCode: course.code,
                        sectionNumber: sectionNumber
                    )
                }
                stopPreview()
                // A Coverage tab refresh still waiting for the old preview to
                // stop is abandoned, so it starts nothing from a view that
                // has gone (#793, the 793b review's H1).
                letTheCoverageTabGo()
            }
    }

    /// The three alerts: the preview's, the deploy refusal, and the Problems
    /// alert (which also says what a repair did), in that order.
    func presentingTheAlerts(_ content: some View) -> some View {
        content
            .alert(previewAlertTitle, isPresented: $previewAlertIsUp) {
                switch previewAlert {
                case .todaysClass(let offer):
                    // Each answer only RECORDS; the preview starts from
                    // `afterThePreviewAlert`, once this alert has gone.
                    Button(FrontPageWording.show) {
                        answerTodaysClass(offer, show: true)
                    }
                    Button(FrontPageWording.notToday, role: .cancel) {
                        answerTodaysClass(offer, show: false)
                    }
                case .refusal:
                    Button("OK") { }
                }
            } message: {
                Text(previewAlertMessage)
            }
            .alert("Cannot Deploy Yet", isPresented: deployRefusalBinding) {
                // The Account ID is put right in Settings, so the refusal that
                // names it offers the way there (#668) — the refusal every new
                // course meets at its first deploy now that Cloudflare Pages is
                // the default. OK stays the default button.
                if PublishingDestinations.deployRefusalOpensSettings(
                    refusal: deployRefusal ?? "", cloudflareAccountID: AppSettings.shared.cloudflareAccountID
                ) {
                    Button("Open Settings…") {
                        deployRefusal = nil
                        SettingsPane.select(.deploying)
                        openSettings()
                    }
                }
                Button("OK") {
                    deployRefusal = nil
                }
            } message: {
                Text(deployRefusal ?? "")
            }
            // ONE alert for both the findings and what a repair did, switched by
            // `healthDialog`, rather than two `.alert` modifiers on the same view.
            //
            // Two was a crash, not a style preference: SwiftUI's alert bridge
            // segfaulted in `updateExistingAlert` while closing a sheet, reliably,
            // once this view carried four alerts. A view presents one alert at a
            // time anyway, so modelling that explicitly is both what SwiftUI wants
            // and what the sequencing needs.
            .alert(healthAlertTitle, isPresented: healthDialogBinding) {
                switch healthDialog {
                case .findings:
                    // The alert about new problems (#717): Show opens the
                    // section's Problems tab. Every answer is remembered by the
                    // record's alert key, so it is not raised again.
                    Button(SectionProblemsWording.show) {
                        answerTheProblemsAlert("Show")
                        if let folder = workspace.workspaceURL {
                            SectionProblems.shared.show(.problems, folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
                        }
                    }
                    // No repair on a course kept for reference. The findings
                    // themselves still REPORT — a teacher may want to know a
                    // folder is missing — but the button would have offered to
                    // fix it and then said "That is already put right. Nothing
                    // needed changing." about a folder that is really gone,
                    // because the repair returns no attempts and the zero-attempt
                    // branch reads as "nothing needed doing". Found by review,
                    // 2026-09-20.
                    if !course.isKeptForReference,
                       let title = SiteHealthRepair.buttonTitle(for: healthFindings) {
                        Button(title) {
                            // The marker is refreshed because a repair CHANGES the
                            // section's content on the teacher's behalf, and
                            // nothing else here would: `refreshEditedMarker` runs
                            // on appear, when the section stops being busy, and on
                            // window activation — the section stopped being busy
                            // before this alert appeared, and an alert on this
                            // window does not make it key again.
                            defer { refreshEditedMarker() }
                            answerTheProblemsAlert("the repair")
                            // Only REMEMBERED here: the outcome is shown once this
                            // alert has actually gone, from `onChange`. Raising a
                            // second alert from inside this action loses one of
                            // them, and the one lost is the report just asked for.
                            pendingRepairOutcome = SiteHealthRepair.outcome(
                                ofRepairing: healthFindings, in: course,
                                occasion: healthFindingsCameFromPublishing ? .publishing : .building
                            )
                        }
                    }
                    // "OK" only when it is the only answer: beside a verb it
                    // reads as "yes, do it" (#457, the HIG sweep) — and Show is
                    // always beside it.
                    Button(SiteHealthRepair.dismissTitle(
                        besideAnAction: true,
                        afterARepair: false
                    ), role: .cancel) {
                        answerTheProblemsAlert("Not Now")
                    }
                case .outcome:
                    if repairOutcome?.canRebuild == true {
                        Button("Preview Again") {
                            rebuildAfterRepair()
                        }
                    }
                    Button(SiteHealthRepair.dismissTitle(
                        besideAnAction: repairOutcome?.canRebuild == true,
                        afterARepair: true
                    ), role: .cancel) { }
                case .none:
                    Button("OK") { }
                }
            } message: {
                Text(healthAlertMessage)
            }
    }

    /// What follows an alert going up or going away, and the build's word
    /// about the links checklist.
    func followingWhatTheAlertsLeave(_ content: some View) -> some View {
        content
            // Findings go up as soon as the build reports them, NOT when the
            // preview finishes.
            //
            // Driving the real app is what found this. Deleting a section's
            // index.md produces the "no front page" finding — and also makes every
            // request 404, so `waitForPreviewServer` never succeeds and the call
            // after it is never reached. The dialog was gated behind a preview that
            // the very problem it reports prevents from completing: the worse the
            // course, the less likely the teacher was to be told.
            .onChange(of: previewRunner.healthFindings.count) { _, count in
                if count > 0 {
                    showHealthFindings(from: previewRunner)
                }
            }
            .onChange(of: healthDialog == nil) { _, isGone in
                if isGone {
                    healthFindings = []
                    problemsAlert = nil
                    repairOutcome = nil
                    showAnythingWaiting()
                    showAVerbResultIfWaiting()
                }
            }
            .onChange(of: previewAlertIsUp) { _, isUp in
                if !isUp {
                    afterThePreviewAlert()
                }
            }
            // The build's word that it wrote the links checklist offer (#379).
            // Printed after the date passes, so it follows the #333 finding.
            .onChange(of: previewRunner.linksChecklistMarkers.count) { _, _ in
                // The build has said whether it wrote an offer — mid-build, which
                // is enough: the file is written before the marker. So the held
                // finding is settled as though the build had finished.
                settleHeldLinksFinding(from: previewRunner, buildHasFinished: true)
            }
    }

    /// The links checklist and the Section menu's own sheet.
    func presentingTheSheets(_ content: some View) -> some View {
        content
            .sheet(item: $linksChecklist, onDismiss: {
                refreshEditedMarker()
                showAVerbResultIfWaiting()
                raiseTheProblemsAlertIfDue()
            }, content: { model in
                LinksChecklistSheet(model: model, onPublished: {
                    refreshEditedMarker()
                })
            })
            // The Section menu's functions (#457 batch B) and #475's question.
            .sheet(item: $verbSheet, onDismiss: {
                verbSheetWentAway()
            }, content: { model in
                SectionVerbSheet(
                    model: model,
                    pressDefault: { pressDefault(in: model) },
                    cancel: { cancelVerbSheet(model) },
                    verbs: workspace.sectionVerbsIfMade
                )
            })
    }

    /// A request from the Section menu, a deploy refusal answered, and a
    /// deploy of this section ending.
    func followingRequestsAndDeployEndings(_ content: some View) -> some View {
        content
            .onChange(of: workspace.sectionVerbRequest) { _, _ in
                takeAVerbRequestIfItIsMine()
            }
            .onChange(of: deployRefusal == nil) { _, isGone in
                if isGone {
                    showAVerbResultIfWaiting()
                }
            }
            // A deploy of this section ended — started here, or by a view of it
            // that has since gone (#706).
            .onChange(of: deployRun.endings) { _, _ in
                takeWhatTheDeployLeft(onAppearing: false)
            }
    }

    /// Takes what this section's deploy left for the view showing it
    /// (#706): its folder problems once it has ended, and — on appearing,
    /// while it still runs — the sentence it said about unsaved settings.
    ///
    /// The findings are TAKEN, read and cleared on the run, so exactly one
    /// view raises the dialog: the one showing the section when the deploy
    /// ended, or else the next one to appear. Two windows on one section
    /// would otherwise both raise it (#706 plan review, L5).
    func takeWhatTheDeployLeft(onAppearing: Bool) {
        let run: SectionDeployRun = deployRun
        if onAppearing, run.isBusy, unsavedSettingsNotice == nil, let notice = run.unsavedSettingsNotice {
            unsavedSettingsNotice = notice
            unsavedSettingsNoticeOwner = .deploy
        }
        // The findings a deploy left are routed for the links checklist
        // (#379) and nothing more: the alert about them is the Problems
        // record's, raised below once the deploy has ended — one dialog,
        // never a second beside it (#717, plan review MED 8).
        if run.takeFindings() {
            showHealthFindings(from: run.runner.legs.first?.runner, cameFromPublishing: true, buildHasFinished: true)
        }
        if !run.isBusy {
            reloadTheProblems()
            raiseTheProblemsAlertIfDue()
        }
        // This view is showing how it ended — live, or on appearing — so the
        // next view to come to the section shows its ordinary state.
        if !run.isBusy && run.endings > 0 {
            run.noteEndingShown()
        }
    }

    /// The title of the folder-problem dialog.
    ///
    /// Plain words, and never the machinery: a teacher is told what is wrong
    /// with THEIR course, not that a check failed. One problem names itself;
    /// several are counted, because a title listing three sentences is not a
    /// title.
    var healthAlertTitle: String {
        if healthDialog == .outcome {
            return repairOutcome?.headline ?? ""
        }
        guard let problemsAlert else {
            // Reached only while the alert is being torn down, after the
            // record has been let go — the unreachable-by-design string made
            // reachable, which this view met twice when it counted findings.
            return ""
        }
        return SectionProblemsWording.alertTitle(
            newCount: problemsAlert.newIDs.count, course: course.displayCode, section: sectionNumber
        )
    }

    var healthDialogBinding: Binding<Bool> {
        return Binding(
            get: { healthDialog != nil },
            set: { isPresented in
                if !isPresented {
                    healthDialog = nil
                }
            }
        )
    }

    var healthAlertMessage: String {
        if healthDialog == .outcome {
            return repairOutcome?.detail ?? ""
        }
        guard let problemsAlert else {
            return ""
        }
        return SectionProblemsWording.alertMessage(
            newRows: SectionDetailView.newRows(of: problemsAlert), goneCount: problemsAlert.goneIDs.count
        )
    }

    /// The rows a record found new, in the record's order.
    static func newRows(of record: SectionProblemsRecord) -> [SectionProblemRow] {
        var found: [SectionProblemRow] = []
        for row in record.rows where record.newIDs.contains(row.id) {
            found.append(row)
        }
        return found
    }

    // MARK: - The section's problems (#717)

    /// This section's Problems record, as the store last read it.
    var problemsRecord: SectionProblemsRecord? {
        guard let folder = workspace.workspaceURL else {
            return nil
        }
        return SectionProblems.shared.record(folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
    }

    /// Problems is in the section's bar only while the record has rows
    /// (`SectionTabs.shown`, beside Coverage since #793).
    var showsTheProblemsTab: Bool {
        return SectionProblemsRules.markerShows(problemsRecord)
    }

    /// Reads this course's records again — every section's, because one
    /// section's build decides what another's rows say (`rowState`).
    func reloadTheProblems() {
        guard let folder = workspace.workspaceURL else {
            return
        }
        SectionProblems.shared.reload(folder: folder, course: course)
    }

    /// Raises the alert about new problems when this section's record has
    /// one nobody has answered (`sectionProblems.alert`) and nothing else is
    /// in front of it. Answers whether it did. Not raised behind another
    /// dialog or a sheet: it stays due in the store, and each of those
    /// going away asks again.
    @discardableResult
    func raiseTheProblemsAlertIfDue() -> Bool {
        if healthDialog != nil || previewAlertIsUp {
            return false
        }
        // Nothing pops up over the Coverage tab (#793): the alert stays due
        // and is raised when the teacher leaves it.
        if alertsWaitForCoverage {
            return false
        }
        if linksChecklist != nil || verbSheet != nil {
            return false
        }
        guard let folder = workspace.workspaceURL,
              let due = SectionProblems.shared.recordWithAnAlertDue(
                folder: folder, courseCode: course.code, sectionNumber: sectionNumber
              ) else {
            return false
        }
        var repairable: [SiteHealthFinding] = []
        for row in SectionDetailView.newRows(of: due) where row.fixable {
            repairable.append(SiteHealthFinding(
                name: row.kind, sentence: row.sentence, detail: row.detail,
                fixable: true, course: course.code, section: sectionNumber
            ))
        }
        problemsAlert = due
        healthFindings = repairable
        // A deploy's record says students still see the old site.
        healthFindingsCameFromPublishing = due.occasion == "deploy"
        healthDialog = .findings
        return true
    }

    /// Remembers the answer to the alert on screen, and puts it on the trail.
    func answerTheProblemsAlert(_ answer: String) {
        guard let problemsAlert, let folder = workspace.workspaceURL else {
            return
        }
        SectionProblems.shared.answer(
            problemsAlert, with: answer, folder: folder, courseCode: course.code, sectionNumber: sectionNumber
        )
    }

    /// The Problems tab's own repair button: the alert's repair, for one
    /// problem, with its outcome shown the way the alert shows it.
    func repairFromTheProblemsTab(_ finding: SiteHealthFinding) {
        guard healthDialog == nil else {
            return
        }
        let occasion: SiteHealthRepair.Occasion = problemsRecord?.occasion == "deploy" ? .publishing : .building
        repairOutcome = SiteHealthRepair.outcome(ofRepairing: [finding], in: course, occasion: occasion)
        healthDialog = .outcome
        refreshEditedMarker()
    }

    /// Shows whatever is queued, now that the dialog it was queued behind has
    /// gone.
    ///
    /// One alert at a time: SwiftUI presents one per view, and asking for a
    /// second while the first is dismissing loses one of them. A repair's
    /// outcome goes first — it is the answer to something the teacher just
    /// pressed — and findings that arrived meanwhile follow.
    func showAnythingWaiting() {
        // Everything here waits while the Coverage tab shows (#793), and is
        // asked again when the teacher leaves it.
        if alertsWaitForCoverage {
            return
        }
        if let waiting = pendingRepairOutcome {
            pendingRepairOutcome = nil
            repairOutcome = waiting
            healthDialog = .outcome
            return
        }
        // The alert about new problems, when one is due (#717) — before the
        // links checklist, which follows it.
        if raiseTheProblemsAlertIfDue() {
            return
        }
        // The links checklist follows the alert (#379), never over it — nor
        // over the preview alert, which carries the #397 question.
        if previewAlertIsUp {
            return
        }
        if verbSheet != nil {
            return
        }
        if let waiting = pendingLinksChecklist {
            pendingLinksChecklist = nil
            presentLinksChecklist(waiting)
        }
    }

    /// Builds the site again after a repair, so the teacher can see it.
    ///
    /// A preview that is already up is stopped first and started again, which
    /// is the same order the Deploy button uses — starting a second one behind
    /// the first would take a port it then could not have.
    /// One consequence worth knowing, because nothing else says it: a preview
    /// build is never deploy-fresh (`app-rules.json` → `buildFreshness` — serve
    /// mode bakes a live-reload client into every page), so previewing after a
    /// successful publish means the NEXT publish rebuilds. That is correct
    /// rather than unfortunate, and largely moot anyway: the repair itself puts
    /// content back, which forces a rebuild regardless.
    func rebuildAfterRepair() {
        Task { @MainActor in
            // Every other way into a preview is gated — the toolbar button is
            // disabled while the section is busy, and Deploy while a deploy
            // runs. This was the one path with neither, so it could start a
            // build in the same working folder as a running deploy.
            // `CourseActivity` as well as this view's own runner. The
            // assistant publishes the same section, in this same process,
            // through `AssistSiteWork` — invisible to `deployRunner`. That did
            // not matter while publish-origin findings offered no button at
            // all; widening the offer is what made this reachable, so the guard
            // had to widen with it.
            // `coursePublishIsRunning`, NOT `courseIsBusy`: the latter is
            // "previewing OR publishing", so asking it here refused the preview
            // whenever one was already running — which is every time this
            // button is offered. Found by pressing it.
            //
            // Narrowing it gave something up, though, and this is where it
            // comes back: `courseIsBusy` also covered a preview held in ANOTHER
            // window, and without that check `startPreview` would be refused
            // the lease and raise an error alert out of a repair. So the lease
            // is asked directly.
            let somebodyElseIsPublishing: Bool = {
                guard let folder = workspace.workspaceURL else {
                    return false
                }
                return CourseActivity.coursePublishIsRunning(
                    folderPath: folder.path, courseCode: course.code
                )
            }()
            let anotherWindowHasThePreview: Bool = {
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
            }()
            if anotherWindowHasThePreview {
                pendingRepairOutcome = SiteHealthRepair.Outcome(
                    headline: "This section is open in another window.",
                    detail: "Preview it from there to see the change.",
                    canRebuild: false
                )
                showAnythingWaiting()
                return
            }
            if deployRunner.isRunning || isPreparingDeploy || somebodyElseIsPublishing {
                // Say so. Every other gated control here disables itself or
                // shows a refusal; swallowing the press is the silence this
                // whole feature exists to remove, arriving in the button meant
                // to end it.
                // "this course", not "this section": the check matches on the
                // folder and the course code, and deliberately ignores the
                // section number, so publishing section 2 would otherwise be
                // reported as section 1 publishing.
                pendingRepairOutcome = SiteHealthRepair.Outcome(
                    headline: "Plantoir is deploying this course just now.",
                    // Deliberately not "press Preview Again": this outcome is
                    // the one whose button is withheld, so naming a button that
                    // is not on screen would be worse than saying nothing.
                    detail: "You can preview it again once that has finished, "
                          + "and the change will be there.",
                    canRebuild: false
                )
                showAnythingWaiting()
                return
            }
            // The LEASE decides, not the window's appearance. A preview whose
            // wait ran out has cleared `isWaitingForServer` and never set
            // `previewURL`, while still holding the port — so asking those two
            // would have skipped the stop and then been refused the lease,
            // raising a refusal alert out of a repair.
            //
            // Still true, and now of ONE path rather than of every timeout.
            // A wait that ends because the builder said its server was up and
            // then went quiet stops the run and hands the port back itself
            // (`stopWaitingForThePreview`, issue #225); what is left holding a
            // port in silence is the outer ten-minute bound — a run that never
            // announced a server at all.
            if previewLease != nil || previewRunner.isRunning {
                await stopPreviewAndWait()
            }
            startPreview()
        }
    }

    /// Routes a run's #333 finding to the links checklist (#379).
    ///
    /// Before #717 this also put every finding in a dialog, on every build
    /// that had any. The section's Problems record is the list now, one row
    /// per problem, and its alert is raised only when the build found
    /// something NEW (`raiseTheProblemsAlertIfDue`), from the record's
    /// marker rather than from these findings. What is left here is the one
    /// thing a finding still decides: whether the checklist is offered.
    func showHealthFindings(
        from runner: ScriptRunner?, cameFromPublishing: Bool = false, buildHasFinished: Bool = false
    ) {
        guard let runner, !runner.healthFindings.isEmpty else {
            return
        }
        // The #333 finding goes to the links checklist when this build wrote
        // an offer for it (#379). The rest — and the finding itself when
        // there is no offer — are rows on the Problems tab.
        _ = routeTheLinksFinding(
            in: runner.healthFindings, from: runner,
            cameFromPublishing: cameFromPublishing, buildHasFinished: buildHasFinished
        )
    }

    // MARK: - The links checklist (#379)

    /// The findings that still belong in the alert, after the #333 one has
    /// gone to the checklist, been held for the build's marker, or stayed.
    func routeTheLinksFinding(
        in findings: [SiteHealthFinding], from runner: ScriptRunner,
        cameFromPublishing: Bool, buildHasFinished: Bool
    ) -> [SiteHealthFinding] {
        var forTheAlert: [SiteHealthFinding] = []
        for finding in findings {
            if finding.name != LinksChecklistRouting.findingName {
                forTheAlert.append(finding)
                continue
            }
            let marker: LinksChecklistMarker? = markerForThisSection(in: runner)
            if let buildId = marker?.buildId, linksChecklistBuildsHandled.contains(buildId) {
                continue
            }
            let offer: LinksChecklistOffer? = LinksChecklistOffer.read(
                courseDirectory: course.directoryURL, section: sectionNumber
            )?.offer
            let route: LinksChecklistRouting.Route = LinksChecklistRouting.route(
                marker: marker, offer: offer, isKeptForReference: course.isKeptForReference,
                buildHasFinished: buildHasFinished
            )
            switch route {
            case .alert:
                // The same finding held earlier goes to the alert once, not
                // again when it is settled (implementation review, N6).
                if heldLinksFinding?.finding == finding {
                    heldLinksFinding = nil
                }
                forTheAlert.append(finding)
            case .waitForTheBuild:
                heldLinksFinding = (finding: finding, cameFromPublishing: cameFromPublishing)
            case .checklist:
                guard let offer, let workspaceURL = workspace.workspaceURL else {
                    forTheAlert.append(finding)
                    continue
                }
                if let buildId = offer.buildId {
                    linksChecklistBuildsHandled.insert(buildId)
                }
                let answered: LinksChecklistAnswered? = LinksChecklistAnswered.read(
                    courseDirectory: course.directoryURL, section: sectionNumber
                )
                // An offer the teacher has already answered in full is not
                // asked again (`offeredWhen.onlyWhenSomethingNew`).
                if !LinksChecklistGate.holdsSomethingNew(offer, answered: answered) {
                    continue
                }
                let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
                    course: course, sectionNumber: sectionNumber, workspaceURL: workspaceURL,
                    offer: offer, answered: answered,
                    occasion: cameFromPublishing ? .afterPublishing : .afterAPreview
                )
                if model.rows.isEmpty {
                    continue
                }
                requestLinksChecklist(model)
            }
        }
        return forTheAlert
    }

    /// The build's last word about this section's offer, if it has said one.
    func markerForThisSection(in runner: ScriptRunner) -> LinksChecklistMarker? {
        var found: LinksChecklistMarker?
        for marker in runner.linksChecklistMarkers where marker.section == sectionNumber {
            found = marker
        }
        return found
    }

    /// The held finding, now that the build has said whether it wrote an
    /// offer — or has finished without saying, which means the alert.
    func settleHeldLinksFinding(from runner: ScriptRunner, buildHasFinished: Bool) {
        guard let held = heldLinksFinding else {
            return
        }
        heldLinksFinding = nil
        // Offered the checklist when the build wrote an offer; otherwise the
        // finding is a row on the Problems tab like every other (#717).
        _ = routeTheLinksFinding(
            in: [held.finding], from: runner,
            cameFromPublishing: held.cameFromPublishing, buildHasFinished: buildHasFinished
        )
    }

    /// Show it now, or after the alert in front of it.
    func requestLinksChecklist(_ model: LinksChecklistSheetModel) {
        if linksChecklist != nil {
            return
        }
        // Behind the Section menu's sheet too (#457 batch B): a publish made
        // from it starts a preview, whose build may offer the checklist while
        // the answer is still on screen. Shown when that sheet goes.
        if verbSheet != nil {
            pendingLinksChecklist = model
            return
        }
        // Not over the Coverage tab (#793): shown when the teacher leaves it.
        if alertsWaitForCoverage {
            pendingLinksChecklist = model
            return
        }
        // Behind the preview alert too (#397): the question about today's
        // class invites a look at the front page in Obsidian, and coming back
        // makes this window key, which offers the checklist — a sheet asked
        // for under an alert.
        if healthDialog != nil || previewAlertIsUp {
            pendingLinksChecklist = model
            return
        }
        presentLinksChecklist(model)
    }

    func presentLinksChecklist(_ model: LinksChecklistSheetModel) {
        if let buildId = model.offer.buildId {
            linksChecklistBuildsHandled.insert(buildId)
        }
        ActivityTrail.note(
            .linksChecklistOffered,
            LinksChecklistPublisher.offeredLine(model: model),
            course: course.code, section: sectionNumber
        )
        linksChecklist = model
    }

    /// The checklist for a publish this window did not watch, when one is
    /// waiting: an offer on disk, fresh, holding something the teacher has
    /// not answered, for a course that is not kept for reference, while
    /// nothing is publishing the course.
    func linksChecklistWaiting(occasion: LinksChecklistGate.Occasion) -> LinksChecklistSheetModel? {
        guard !course.isKeptForReference, let workspaceURL = workspace.workspaceURL else {
            return nil
        }
        if CourseActivity.coursePublishIsRunning(folderPath: workspaceURL.path, courseCode: course.code) {
            return nil
        }
        guard let read = LinksChecklistOffer.read(courseDirectory: course.directoryURL, section: sectionNumber) else {
            return nil
        }
        if let buildId = read.offer.buildId, linksChecklistBuildsHandled.contains(buildId) {
            return nil
        }
        let answered: LinksChecklistAnswered? = LinksChecklistAnswered.read(
            courseDirectory: course.directoryURL, section: sectionNumber
        )
        if !LinksChecklistGate.holdsSomethingNew(read.offer, answered: answered) {
            return nil
        }
        if !LinksChecklistGate.isFresh(
            writtenAt: read.writtenAt, newestContentChange: BuildFreshness.newestContentDate(course: course)
        ) {
            return nil
        }
        let model: LinksChecklistSheetModel = LinksChecklistSheetModel(
            course: course, sectionNumber: sectionNumber, workspaceURL: workspaceURL,
            offer: read.offer, answered: answered, occasion: occasion
        )
        if model.rows.isEmpty {
            return nil
        }
        return model
    }

    /// Called when the window appears, becomes key, or stops being busy.
    func offerTheLinksChecklistIfWaiting() {
        if isBusy || linksChecklist != nil || pendingLinksChecklist != nil || heldLinksFinding != nil {
            return
        }
        if alertsWaitForCoverage {
            return
        }
        guard let model = linksChecklistWaiting(occasion: .onOpening) else {
            return
        }
        requestLinksChecklist(model)
    }

    /// Why this section's deploy would not get anywhere, or nil when it
    /// would. EVERY configured destination is checked — the primary and
    /// every additional one — so a redundancy target with no valid folder
    /// or credential is caught here rather than discovered halfway
    /// through a run that already published to the others.
    ///
    /// Static only, and handed the SAVED settings (#335): the instance
    /// property that read the window's copy was deleted so nothing can reach
    /// the unsaved edits by it again.
    static func deployRefusalReason(configuration: CourseConfiguration, cloudflareAccountID: String) -> String? {
        return MultiDestinationDeployRunner.refusalReason(
            destinations: configuration.allDeployDestinations,
            cloudflareAccountID: cloudflareAccountID
        )
    }

    var deployRefusalBinding: Binding<Bool> {
        return Binding(
            get: { deployRefusal != nil },
            set: { isPresented in
                if !isPresented {
                    deployRefusal = nil
                }
            }
        )
    }

    var previewAlertTitle: String {
        switch previewAlert {
        case .refusal(let title, _):
            return title
        case .todaysClass(let offer):
            return FrontPageWording.question(class: offer.classTitle)
        }
    }

    var previewAlertMessage: String {
        switch previewAlert {
        case .refusal(_, let sentence):
            return sentence
        case .todaysClass(let offer):
            return FrontPageWording.because(noun: offer.noun.singular, shown: offer.shownTitle)
        }
    }

    /// Puts a refusal in the preview alert — or holds it while the question
    /// about today's class is up, so the question is not replaced under the
    /// teacher's pointer.
    func showPreviewRefusal(title: String, sentence: String) {
        // The refusal of a Coverage tab refresh is said in the tab, not as
        // an alert (#793); every other refusal is shown as ever.
        if takeARefusalOnCoverage(title: title, sentence: sentence) {
            return
        }
        if previewAlertIsUp, case .todaysClass = previewAlert {
            heldPreviewRefusal = .refusal(title: title, sentence: sentence)
            return
        }
        previewAlert = .refusal(title: title, sentence: sentence)
        previewAlertIsUp = true
    }

    /// Two refusals in one alert, the earlier first. The title is the later
    /// one's, since it is about the preview just asked for.
    static func joining(_ earlier: PreviewAlert, then later: PreviewAlert) -> PreviewAlert {
        guard case .refusal(_, let earlierSentence) = earlier,
              case .refusal(let laterTitle, let laterSentence) = later else {
            return later
        }
        if earlierSentence == laterSentence {
            return later
        }
        return .refusal(title: laterTitle, sentence: earlierSentence + "\n\n" + laterSentence)
    }

    /// Runs once the preview alert has gone: the preview the question's
    /// answer asked for, then whatever waited behind the alert.
    ///
    /// The preview starts FIRST, and whatever it has to say wins: a refusal
    /// from `startPreview()` is shown and the front-page sentence is left to
    /// the trail. The links checklist waits for both (#379, #397).
    func afterThePreviewAlert() {
        if startPreviewWhenTheQuestionHasGone {
            startPreviewWhenTheQuestionHasGone = false
            if !previewRunner.isRunning {
                startPreview(at: pendingPreviewRequest)
            }
        }
        if previewAlertIsUp, let held = heldPreviewRefusal {
            // The button's own preview was refused too: both are said, the
            // earlier first, rather than the held one dropped (implementation
            // review, note 4).
            previewAlert = SectionDetailView.joining(held, then: previewAlert)
        } else if !previewAlertIsUp, let held = heldPreviewRefusal {
            previewAlert = held
            previewAlertIsUp = true
        } else if !previewAlertIsUp, let sentence = frontPageNotChanged {
            previewAlert = .refusal(title: FrontPageWording.notChangedTitle, sentence: sentence)
            previewAlertIsUp = true
        }
        heldPreviewRefusal = nil
        frontPageNotChanged = nil
        if !previewAlertIsUp && healthDialog == nil {
            showAnythingWaiting()
            showAVerbResultIfWaiting()
        }
    }

    // MARK: - Today's class on the front page (#397)

    /// The Preview button, pressed — by the teacher at the toolbar, or by
    /// the teacher at Section ▸ Preview, which IS pressing it (#457). Stops
    /// a running preview; otherwise `pressPreview`, the one way in that may
    /// ask about today's class first.
    ///
    /// `opensAt` is the start page the press asked for (#504): the
    /// toolbar's from the setting and the keyboard at that moment, the menu's
    /// from which of its two items was chosen.
    func previewButtonPressed(opensAt: PreviewOpensAt) {
        if previewRunner.isRunning {
            stopPreview()
        } else {
            // The BUTTON, and only the button (from the toolbar or the
            // menu bar), may ask about today's class first (#397); every
            // other way in calls `startPreview()` and is never held up by a
            // question.
            pressPreview(opensAt: opensAt)
        }
    }

    /// Section ▸ Preview and its Option alternate (#504), each asking for its
    /// own start page. The button's predicate is asked again, as
    /// `performSiteMenuItem` does: the menu may have been drawn before
    /// something started.
    func previewFromTheSectionMenu(_ opensAt: PreviewOpensAt) {
        if previewButtonIsEnabled {
            previewButtonPressed(opensAt: opensAt)
        }
    }

    /// Section ▸ Preview, Deploy… and Open in Browser. Each asks the
    /// button's own predicate again: the menu may have been drawn before
    /// something started.
    func performSiteMenuItem(_ item: SubjectMenuRules.Item) {
        switch item {
        case .preview:
            if previewButtonIsEnabled {
                previewButtonPressed(opensAt: AppSettings.shared.previewOpensAt)
            }
        case .deploy:
            if deployButtonIsEnabled && !course.isKeptForReference {
                startDeploy()
            }
        case .openInBrowser:
            if previewURL != nil {
                openInBrowser()
            }
        case .publishPages, .hidePages, .publishClassForADate, .rebuildPreview, .undoLastChange,
             .addNextClass, .reDateClasses, .makeRoomForClasses, .classDates:
            performVerb(item)
        default:
            break
        }
    }

    /// The Preview button's action. Asks about today's class when there is
    /// something to ask; otherwise, and after the answer, previews.
    ///
    /// **The one caller of `todaysClassOffer()`.** `startPreview()` is the
    /// door every other way in uses — the assistant, Start of the Year,
    /// Course Settings, a repair's rebuild — and a question there would hold
    /// each of them up on a modal nobody may be watching
    /// (`TodaysClassOnTheFrontPageTests.testOnlyThePreviewButtonAsks`).
    func pressPreview(opensAt: PreviewOpensAt) {
        // Held through the question, which may change it (#504): a Show on
        // Front Page that wrote the page opens the front page.
        pendingPreviewRequest = PreviewStartPage.Request(opensAt: opensAt)
        if frontPageQuestionMayBeAsked(), let offer = todaysClassOffer() {
            previewAlert = .todaysClass(offer)
            previewAlertIsUp = true
            return
        }
        startPreview(at: PreviewStartPage.Request(opensAt: opensAt))
    }

    /// The question for this section today, or nil.
    func todaysClassOffer() -> TodaysClassOnTheFrontPage.Offer? {
        return TodaysClassOnTheFrontPage.offer(
            forSection: sectionNumber, in: course, today: CalendarDay.today()
        )
    }

    /// Whether the front page may be asked about — and, at Show on Front
    /// Page, still written. Not when the preview would be refused anyway (the
    /// teacher is told why, as before, with no question first), and never
    /// while this section is being deployed or another program is building
    /// the course: the build writes this same file.
    func frontPageQuestionMayBeAsked() -> Bool {
        guard let workspaceURL = workspace.workspaceURL else {
            return false
        }
        let sectionIsDeploying: Bool = SectionDetailView.refusalWhileThisSectionDeploys(
            folderPath: workspaceURL.path,
            courseCode: course.code,
            displayCode: course.displayCode,
            sectionNumber: sectionNumber
        ) != nil
        let anotherProgramIsBuilding: Bool = WorkLeaseRegistry.whatBlocksABuild(
            folderPath: workspaceURL.path, courseCode: course.code, afterTaking: false
        ) != nil
        return SectionDetailView.frontPageMayBeAskedAbout(
            isKeptForReference: course.isKeptForReference,
            isBeingCopied: workspace.isBeingCopied(course.code),
            isBusy: isBusy || isPreparingDeploy,
            sectionIsDeploying: sectionIsDeploying,
            anotherProgramIsBuilding: anotherProgramIsBuilding
        )
    }

    /// The guards of `frontPageQuestionMayBeAsked`, as a rule a test can run.
    static func frontPageMayBeAskedAbout(
        isKeptForReference: Bool,
        isBeingCopied: Bool,
        isBusy: Bool,
        sectionIsDeploying: Bool,
        anotherProgramIsBuilding: Bool
    ) -> Bool {
        if isKeptForReference || isBeingCopied || isBusy {
            return false
        }
        if sectionIsDeploying || anotherProgramIsBuilding {
            return false
        }
        return true
    }

    /// The teacher's answer. Records it — the page written, or Not Today —
    /// with its trail line, and asks for the preview once the alert has gone.
    func answerTodaysClass(_ offer: TodaysClassOnTheFrontPage.Offer, show: Bool) {
        startPreviewWhenTheQuestionHasGone = true
        if !show {
            ActivityTrail.note(
                .frontPageLeftAsItWas,
                TodaysClassOnTheFrontPage.answerNotToday(offer, courseDirectory: course.directoryURL),
                course: course.code, section: sectionNumber
            )
            return
        }
        // Decided again: the section may have become busy while the question
        // was up (a scheduled deploy, the assistant), and the build writes
        // this same file (#397 plan review, 4).
        var outcome: TodaysClassOnTheFrontPage.Outcome = .noLongerOffered
        if frontPageQuestionMayBeAsked() {
            outcome = TodaysClassOnTheFrontPage.show(offer, in: course)
        }
        let line: (event: ActivityTrail.Event, what: String) = TodaysClassOnTheFrontPage.trailLine(
            for: outcome, offer: offer
        )
        ActivityTrail.note(line.event, line.what, course: course.code, section: sectionNumber)
        switch outcome {
        case .shown:
            refreshEditedMarker()
            // The teacher has just asked to change the FRONT page, so that
            // is what they are shown, even when they asked for the page last
            // viewed (#504; 504 plan review, finding 6). Said on the trail
            // by the start-page line.
            pendingPreviewRequest.frontPageWasJustChanged = true
        case .alreadyRight:
            break
        case .noLongerOffered:
            frontPageNotChanged = FrontPageWording.noLongerOffered(noun: offer.noun.singular)
        case .couldNotSave:
            frontPageNotChanged = FrontPageWording.couldNotSave(shown: offer.shownTitle)
        }
    }

    var consoleArea: some View {
        VStack(spacing: 0) {
            if showsDeployProgress {
                // .leading: DeployDestinationChecklist is a compact HStack
                // with no content of its own that forces full width, so
                // under this VStack's default (.center) alignment it would
                // float centred while TaskProgressView's own text starts at
                // the left margin — two different leading edges for what
                // reads as one panel. Explicit .leading lines them up.
                VStack(alignment: .leading, spacing: 0) {
                    if isPreparingDeploy {
                        preparingToDeployPlaceholder
                    } else {
                        // Only appears once a course has more than one
                        // destination — the overwhelming majority never see
                        // this at all, and the progress panel beneath it
                        // looks exactly as it always has.
                        if deployRunner.legs.count > 1 {
                            DeployDestinationChecklist(legs: deployRunner.legs)
                        }
                        // DeployDestinationLinks renders INSIDE TaskProgressView
                        // itself, in the same spot a single destination's own
                        // "Your website is live" link would sit — above "Show
                        // details", never pushed down past the (variable-height)
                        // console.
                        TaskProgressView(
                            runner: deployRunner.activeRunner,
                            title: deployProgressTitle,
                            hidesSiteLink: deployRunner.legs.count > 1,
                            allLegs: deployRunner.legs.count > 1 ? deployRunner.legs : nil,
                            onCancel: {
                                cancelDeploy()
                            }
                        )
                    }
                }
            } else {
                TaskProgressView(
                    runner: previewRunner,
                    title: previewTaskTitle,
                    onCancel: {
                        cancelPreview()
                    }
                )
            }
            Spacer(minLength: 0)
        }
    }

    /// Stands in for the real deploy progress panel during `deployAndWait()`'s
    /// prep work — stopping any preview, waiting for containers to clear —
    /// before there is a real, running `deployRunner` to show. No "Show
    /// details" or Cancel here: there is genuinely nothing yet to look at
    /// or to stop, unlike once the real panel takes over a moment later.
    var preparingToDeployPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Deploying \(sectionName)")
                    .font(.headline)
                Spacer()
                Text("Preparing to deploy…")
                    .foregroundStyle(.secondary)
            }
            ProgressView()
                .progressViewStyle(.linear)
        }
        .padding(12)
    }

    /// What the deploy panel is called. Names the destination currently
    /// running only once there is more than one to distinguish between —
    /// a course with a single destination keeps the plain title it has
    /// always had.
    var deployProgressTitle: String {
        return SectionDetailView.deployProgressTitle(
            sectionName: sectionName,
            isRunning: deployRunner.isRunning,
            legCount: deployRunner.legs.count,
            currentDestinationDescription: deployRunner.currentLeg.map { leg in
                DeployCommand.destinationDescription(for: leg.destination)
            }
        )
    }

    /// What the preview panel is called. While the preview is being made
    /// the title says so; once it has finished or been stopped, the panel
    /// is simply about the preview, so it must stop claiming to be
    /// preparing one.
    var previewTaskTitle: String {
        return SectionDetailView.previewTaskTitle(isPreparing: previewRunner.isRunning, sectionName: sectionName)
    }

    /// True when the console should be about publishing rather than
    /// previewing.
    var showsDeployProgress: Bool {
        return SectionDetailView.showsDeployProgress(
            previewIsRunning: previewRunner.isRunning,
            deployIsRunning: deployRunner.isRunning,
            previewStartedAt: previewRunner.startedAt ?? deployRun.previewLastStartedAt,
            deployStartedAt: deployRunner.startedAt
        )
    }

    // MARK: - A scheduled publish that stopped

    /// Forget the notice a scheduled run left behind.
    ///
    /// The notice itself is `ScheduledPublishNoticeView` — its own view, so
    /// that a test can measure it; what stays here is the part that touches
    /// this view's own state and the workspace.
    func dismissScheduledPublishNotice() {
        // The record AND the macOS notification about it (#212), so the two
        // never disagree about whether it is still news — THIS working
        // folder's only (#237): the same section's in another folder stays.
        if let workingFolderURL = workspace.workspaceURL {
            ScheduledPublishNotice.teacherDismissed(
                inHomeFolder: ScheduledDeploy.homeForScheduledNotes,
                course: course.code,
                section: sectionNumber,
                folderID: BuildOutputLocation.folderIdentifier(forWorkingFolder: workingFolderURL.path)
            )
        }
        stoppedScheduledPublish = nil
        // The sidebar's badge is read during a row's render, so it
        // needs telling that the answer changed — Dismiss happens
        // here, in a different view with its own state.
        //
        // Said out loud even though `clear` deletes the file and the watcher
        // would see that: a button must not wait on the filesystem to show what
        // the teacher just did, and the test suite runs with no watcher started.
        ScheduledPublishWatcher.shared.noteChanged()
    }

    /// Look for a stopped run. READ ONLY — the trail line is written by the
    /// run itself (`ScheduledDeploy.runScheduled`), not here.
    ///
    /// Nothing is written back to the record either, which matters: an earlier
    /// draft appended a "noted" marker, and rewriting the file changed its
    /// modification date, so the notice showed the morning the teacher opened
    /// it instead of the half six the run stopped at.
    func loadStoppedScheduledPublish() {
        guard let workingFolderURL = workspace.workspaceURL else {
            stoppedScheduledPublish = nil
            return
        }
        stoppedScheduledPublish = ScheduledPublishOutcome.stopped(
            inHomeFolder: ScheduledDeploy.homeForScheduledNotes,
            course: course.code,
            section: sectionNumber,
            workingFolder: workingFolderURL
        )
    }

    // MARK: - Functions

    /// A page the preview handed to the web browser goes on the trail with
    /// this section's name (#454; activityTrail → `preview page opened in the
    /// web browser`).
    func notePagesHandedToTheBrowser() {
        let code: String = course.code
        let section: Int = sectionNumber
        previewController.browserHandoff.whenHandedOver = { page, target, reason in
            previewIsInTheBrowser = true
            ActivityTrail.note(
                .previewPageOpenedInBrowser,
                PreviewBrowserHandoff.trailWords(page: page, target: target, reason: reason),
                course: code,
                section: section
            )
        }
    }

    /// Works out whether the title bar should say " — Edited", off the
    /// main thread: the check is a directory walk, and however brief, a
    /// course on a slow network volume must not be able to stutter a
    /// window that is being brought to the front.
    func refreshEditedMarker() {
        let courseDirectory: URL = course.directoryURL
        let sectionNumber: Int = self.sectionNumber
        // A course that publishes into a folder inside itself would
        // otherwise feed its own marker: `deploy.py` writes the whole
        // built site there, so every check after a publish would differ
        // from the one before it and the window would say " — Edited"
        // permanently.
        let excluded: [String] = SectionPublishState.selfPublishingSubpaths(
            courseDirectory: courseDirectory,
            destinations: course.configuration.allDeployDestinations
        )
        refreshGeneration += 1
        let generation: Int = refreshGeneration
        Task.detached(priority: .utility) {
            let edited: Bool = SectionPublishState.hasUnpublishedEdits(
                courseDirectory: courseDirectory,
                sectionNumber: sectionNumber,
                excludingRelativePaths: excluded
            )
            await MainActor.run {
                if generation == refreshGeneration {
                    hasUnpublishedEdits = edited
                }
            }
        }
    }

    /// Names the preview panel for what it is at the moment.
    static func previewTaskTitle(isPreparing: Bool, sectionName: String) -> String {
        if isPreparing {
            return "Preparing the preview of \(sectionName)"
        }
        return "Preview of \(sectionName)"
    }

    /// Names the destination CURRENTLY running only while the deploy is
    /// still going — once it has finished, naming just one destination in
    /// the title is misleading when every configured destination actually
    /// ran (a teacher who deployed to Netlify AND Cloudflare should not see
    /// a title that only mentions whichever one happened to run last). The
    /// checklist above already names each destination with its own
    /// checkmark, and `DeployDestinationLinks` below lists every live link,
    /// so the finished title reverts to the plain single-destination form.
    static func deployProgressTitle(
        sectionName: String,
        isRunning: Bool,
        legCount: Int,
        currentDestinationDescription: String?
    ) -> String {
        if isRunning, legCount > 1, let currentDestinationDescription {
            return "Deploying \(sectionName) — \(currentDestinationDescription)"
        }
        return "Deploying \(sectionName)"
    }

    /// Whichever task is running now, or — once both have finished — the
    /// one that started most recently.
    ///
    /// Judging by "has this task any output?" instead kept a finished
    /// publish on screen forever, so starting a preview afterwards left
    /// the publish's own summary sitting there as though nothing had
    /// happened.
    static func showsDeployProgress(previewIsRunning: Bool, deployIsRunning: Bool, previewStartedAt: Date?, deployStartedAt: Date?) -> Bool {
        if previewIsRunning {
            return false
        }
        if deployIsRunning {
            return true
        }
        let previewStart: Date = previewStartedAt ?? Date.distantPast
        let deployStart: Date = deployStartedAt ?? Date.distantPast
        return deployStart > previewStart
    }

    ///
    /// `request` says where the site opens once the server answers (#504):
    /// the front page unless the TEACHER's press asked for the page last
    /// viewed. Every other way in — the assistant, Rebuild Preview, Course
    /// Settings, Start of the Year, a repair — takes the default.
    func startPreview(at request: PreviewStartPage.Request = .frontPage) {
        guard let workspaceURL = workspace.workspaceURL else {
            return
        }
        // Every way in, not only the button (#351): see its `.disabled`.
        if workspace.isBeingCopied(course.code) {
            return
        }
        // A preview of this section cannot start while this same section is
        // being deployed by this copy of the app — from this window, another
        // window, or the assistant with no window (#381, Russell's decision 4
        // on #378). Asked HERE, first, before any lease is taken or anything
        // is stopped or started, because every way into a preview comes
        // through here: the button (whose `.disabled` is only a convenience),
        // the in-app assistant, and the restart path. Other programs are
        // refused by their leases below, and a deploy typed at a command line
        // by `preview.sh` itself.
        if let refusal = SectionDetailView.refusalWhileThisSectionDeploys(
            folderPath: workspaceURL.path,
            courseCode: course.code,
            displayCode: course.displayCode,
            sectionNumber: sectionNumber
        ) {
            WorkLeaseRegistry.noteDeclinedWhileItsSectionDeploys(
                courseCode: course.code, sectionNumber: sectionNumber
            )
            showPreviewRefusal(title: "Cannot Preview Yet", sentence: refusal)
            return
        }
        // One of the moments the teacher ACTS on a reference course, so the
        // lock is re-asserted here: a folder that came back from a backup, or
        // from a second Mac, is not locked until somebody asks. Cheap — a
        // stat per file, measured at ~23 ms on a 1,220-file course — and
        // quiet unless it actually had to lock something.
        ReferenceLock.ensureLockedInBackground(course)
        // The folder this preview belongs to, noted at the moment it is
        // decided — which is HERE, not at the appearance. The appearance
        // notes only the key this section registered under, and it can
        // return without a folder at all while this function goes on
        // working from the model — so a note made there would have let a
        // preview start that no stop was ever aimed at. Every stop reads
        // this, so writing it beside the lease is what makes start and
        // stop name one folder.
        folderThisSectionWorksIn = workspaceURL
        // The BUILD is recorded first — its lease on disk before the
        // preview's — and that order is load-bearing (#156's review, M2).
        // The take-then-check below compares other programs' leases against
        // this window's `build` moment, and they compare against every lease
        // this window holds, the `preview` included. Written the other way
        // round, an outside build could land between the two files: this
        // window would see it as earlier than its build and decline, and the
        // other program would see this window's preview as earlier than its
        // build and decline too. Build first, and exactly one goes ahead.
        previewBuildWait.begin(
            folderPath: workspaceURL.path,
            courseCode: course.code,
            sectionNumber: sectionNumber
        )
        // Each preview runs on its own port, so several windows can show
        // sections side by side without taking each other down.
        let lease: PreviewLeases.Lease
        do {
            lease = try PreviewLeases.lease(
                folderPath: workspaceURL.path,
                courseCode: course.code,
                sectionNumber: sectionNumber
            )
        } catch {
            previewBuildWait.end()
            showPreviewRefusal(title: "Cannot Preview Yet", sentence: error.localizedDescription)
            return
        }
        previewLease = lease
        previewURL = nil
        previewRoot = nil
        // ANOTHER program on this Mac — an assistant working from another
        // app, another copy of Plantoir, a deploy set for later — may be
        // building or previewing this course (#156). Asked only NOW, after
        // this window's own build and preview leases are on disk and with
        // nothing awaited since: only a lease taken before this window's
        // build counts, so two programs pressing at the same instant cannot
        // both go ahead. Nothing has been stopped or started yet, so
        // declining costs the teacher nothing but the sentence.
        if let holding = WorkLeaseRegistry.whatBlocksABuild(
            folderPath: workspaceURL.path, courseCode: course.code, afterTaking: true
        ) {
            previewBuildWait.end()
            releasePreviewLease()
            WorkLeaseRegistry.noteDeclined(
                act: "Preview", courseCode: course.code, sectionNumber: sectionNumber, holding: holding
            )
            showPreviewRefusal(
                title: "Cannot Preview Yet",
                sentence: AssistWording.courseIsBeingBuiltElsewhere(course: course.displayCode)
            )
            return
        }
        // Every window's copy of this course, not only this window's: the
        // unsaved switches may be in another window's Course Settings.
        let anyWindowHasUnsavedSettings: Bool = course.configuration.hasUnsavedChanges
            || WorkspaceModel.anyCopyHasUnsavedChanges(configFileURL: course.configFileURL)
        unsavedSettingsNotice = SettingsSaveNotice.whenPreviewStarts(
            settingsHaveUnsavedChanges: anyWindowHasUnsavedSettings
        )
        unsavedSettingsNoticeOwner = unsavedSettingsNotice == nil ? nil : .preview
        if unsavedSettingsNotice != nil {
            ActivityTrail.note(
                .previewStartedWithUnsavedSettings,
                "started a preview while Course Settings had changes nobody saved — told it uses the saved settings",
                course: course.code,
                section: sectionNumber
            )
        }
        previewRunner.milestones = TaskMilestones.preview

        Task { @MainActor in
            // Wait for any stop that is still finishing before building.
            //
            // Stop mode finds a section's processes BY WORKING DIRECTORY, so
            // it "catches builds as well as servers" — `preview.sh` says so
            // itself. A stop still running when this build starts kills the
            // build, and what gets served is the last `public/` that was
            // allowed to finish: the site as it was BEFORE the edit.
            //
            // That is why stopping and starting quickly showed stale content
            // while doing the same slowly worked. Nothing failed, nothing was
            // logged; the only symptom was a preview that looked like the
            // edit had not happened.
            //
            // The guard lives HERE, at the one place a preview begins, rather
            // than beside each caller — the button, the assistant, a window
            // being reopened. Somewhere there will always be a caller nobody
            // remembered.
            await PreviewStopper.waitForStopsToFinish(
                courseCode: course.code, sectionNumber: sectionNumber
            )
            // The lease is still this start's own: nobody stopped it while
            // the stops finished, and the view has not gone (a view going
            // away releases its lease). Otherwise this start belongs to no
            // one, and running it would leave a preview nothing stops
            // (#793, the 793b fix review 2's LOW 2).
            if previewLease != lease {
                return
            }
            // What the built page looked like BEFORE this build — so we can
            // wait for it to CHANGE rather than for it to look new.
            //
            // Comparing against a timestamp taken here does not work, and the
            // reason is easy to miss: this file is written inside the Linux
            // VM, whose clock is its own. If the VM is running ahead — which
            // it does after the Mac sleeps — the OLD file already looks newer
            // than any moment noted on the Mac, so the check passes at once
            // and the teacher is shown the previous build. Waiting for the
            // value to change asks nothing of either clock.
            let siteAsItWas: Date? = builtIndexWrittenAt()
            // A deploy another program runs — an outside assistant's, or one
            // set for later — ends this preview when it builds the section.
            // The teacher asked for that deploy, so the end is shown as
            // "Closed for a deploy", not as a failure (#433's stack review,
            // item 6). Asked of the leases at the moment the run ends.
            let folderPathForLeases: String = workspaceURL.path
            let courseCodeForLeases: String = course.code
            previewRunner.endedForAnotherProgramsBuild = {
                return WorkLeaseRegistry.anotherProgramIsBuilding(
                    folderPath: folderPathForLeases, courseCode: courseCodeForLeases
                )
            }
            previewRunner.run(
                scriptNamed: "preview.sh",
                arguments: [course.code, String(sectionNumber), "--port", String(lease.port)],
                workingDirectory: workspaceURL
            )
            // Said to the section's run, so a view that comes back later
            // knows this preview is newer than the last deploy (#706 review,
            // M1): its own preview runner will have no start time at all.
            if let previewStartedAt = previewRunner.startedAt {
                SectionRuns.shared.deploy(
                    folder: workspaceURL, courseCode: course.code, sectionNumber: sectionNumber
                ).notePreviewStarted(at: previewStartedAt)
            }
            await waitForPreviewServer(port: lease.port, siteAsItWas: siteAsItWas, startRequest: request)

            // A second chance, for the ordinary case where the wait finished
            // quickly and the teacher is now looking at the preview. The
            // findings usually arrived long before this — see the onChange on
            // the body, which is what actually gets them on screen.
            showHealthFindings(from: previewRunner, buildHasFinished: true)
            settleHeldLinksFinding(from: previewRunner, buildHasFinished: true)
        }
    }

    /// Stop, and do not come back until the container-side processes have
    /// actually gone.
    ///
    /// The button does not need this — the teacher has finished with the
    /// preview and nothing is racing it. The ASSISTANT does: it stops, writes
    /// the pages, and starts again, and if the stop is still running when the
    /// start begins it kills the new build. What a teacher then sees is not an
    /// error but something worse: no preview, and a site on disk still showing
    /// the last build that was allowed to finish.
    func stopPreviewAndWait() async {
        let courseCode: String = course.code
        let section: Int = sectionNumber
        let folder: URL? = folderThisSectionWorksIn
        stopPreview()
        if let folder {
            await PreviewStopper.stopSectionProcessesAndWait(
                courseCode: courseCode, sectionNumber: section, workspaceURL: folder
            )
        }
    }

    func stopPreview() {
        // Ending the host-side script leaves the build or server inside
        // the container running; the launcher's stop mode reclaims them.
        // Against the folder the work in flight belongs to — a preview's,
        // or a deploy's build when a cancel reaches this way — never the one
        // the window points at now. This also runs from `onDisappear`, which
        // is after a folder change has already moved the window on.
        if previewRunner.isRunning, let workspaceURL = folderThisSectionWorksIn {
            PreviewStopper.stopSectionProcesses(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                workspaceURL: workspaceURL
            )
        }
        previewRunner.stopByUser()
        previewURL = nil
        previewRoot = nil
        previewBuildWait.end()
        // The next preview reuses this section's port, so its address will be
        // identical to the one already loaded. Without this the web view sees
        // a URL it has seen before and shows the pages it already had —
        // which is how a rebuilt site kept appearing unchanged.
        previewController.forgetLoadedPage()
        releasePreviewLease()
        // A Coverage tab refresh this run was making is settled now (#793):
        // a switch of section stops its build through here.
        noteTheCoverageRunEnded()
    }

    /// Cancels the running preview from the progress view.
    func cancelPreview() {
        if previewRunner.isRunning, let workspaceURL = folderThisSectionWorksIn {
            PreviewStopper.stopSectionProcesses(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                workspaceURL: workspaceURL
            )
        }
        previewRunner.cancelByUser()
        previewURL = nil
        previewRoot = nil
        previewBuildWait.end()
        previewController.forgetLoadedPage()
        releasePreviewLease()
        noteTheCoverageRunEnded()
    }

    /// Cancels the running deploy from the progress view.
    ///
    /// Against the folder the DEPLOY noted (`SectionDeployRun.folder`), not
    /// this view's note: the view pressing Cancel may be one that came back
    /// to the section after the view that started the deploy had gone
    /// (#706), and it never noted anything.
    func cancelDeploy() {
        let run: SectionDeployRun = deployRun
        if run.runner.isRunning, let workspaceURL = run.folder {
            PreviewStopper.stopSectionProcesses(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                workspaceURL: workspaceURL
            )
        }
        run.runner.cancel()
    }

    /// Hands the port back, whatever ended the preview.
    func releasePreviewLease() {
        if let lease = previewLease {
            PreviewLeases.release(lease)
            previewLease = nil
        }
        // The notice was about the preview that just ended — unless it is a
        // deploy's, which a preview ending must not take away (#335, F3).
        if SectionDetailView.previewEndClearsTheNotice(owner: unsavedSettingsNoticeOwner) {
            unsavedSettingsNotice = nil
            unsavedSettingsNoticeOwner = nil
        }
    }

    /// Why a preview of this section cannot start now, or nil when nothing in
    /// this copy of the app is deploying it (GitHub #381).
    ///
    /// Static for the reason `refusalForAReferenceCourse` below is: nothing in
    /// the suite constructs this view, so the rule lives where a test can
    /// reach it, and `startPreview` asks it first. `displayCode` is what the
    /// sentence names; `courseCode` is the folder's, which the publish record
    /// holds.
    static func refusalWhileThisSectionDeploys(
        folderPath: String,
        courseCode: String,
        displayCode: String,
        sectionNumber: Int
    ) -> String? {
        let isDeploying: Bool = CourseActivity.sectionPublishIsRunning(
            folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber
        )
        if !isDeploying {
            return nil
        }
        return AssistWording.sectionIsBeingDeployed(course: displayCode, section: String(sectionNumber))
    }

    /// Why this course is never deployed, or nil when it is an ordinary one.
    ///
    /// **A static function rather than three lines inside `deployAndWait`**,
    /// for the reason `ScheduledDeployCleanup` exists: nothing in the suite
    /// constructs this view — every reference to it is to a static member — so
    /// a guard living inside an instance method could be proved only by
    /// proving something else, and an edit that dropped it would leave the
    /// suite green. A missed deploy door is a deploy that reports success.
    ///
    /// `isAboutTheDestination` so the window raises it as an alert: it is a
    /// fact about the course rather than something that went wrong while
    /// running, which is the same distinction the destination refusals make.
    /// A teacher never normally meets it — the Deploy button is not drawn on a
    /// reference course at all.
    static func refusalForAReferenceCourse(_ course: Course) -> AssistSiteWorkResult? {
        guard course.isKeptForReference else {
            return nil
        }
        return AssistSiteWorkResult(
            succeeded: false,
            message: AssistWording.deployRefusedForAReferenceCourse(course: course.displayCode),
            isAboutTheDestination: true
        )
    }

    /// What a deploy from this window uses (#335): the course as its settings
    /// file says it is at this moment, where that sends it, why it would be
    /// refused, and what to say when some window holds unsaved edits.
    ///
    /// **Read from the file, never from `windowCourse`'s settings.** The
    /// launcher's own deploy reads the file for everything but the
    /// destination, and since #322 the approval card names the saved one — so
    /// a destination taken from the window's unsaved edits published a site
    /// half from memory and half from disk, somewhere the card did not name.
    /// When the file cannot be read the deploy is refused with
    /// `settingsCouldNotBeReadToDeploy`: a destination has no safe default
    /// (#323's rule), so the window's copy is never used in its place.
    static func whatADeployUses(
        windowCourse: Course,
        anyCopyUnsaved: Bool,
        cloudflareAccountID: String
    ) -> (course: Course?, destinations: [CourseConfiguration.DeployDestination], refusal: String?, notice: String?) {
        let saved: Course
        do {
            saved = try windowCourse.asSavedNow()
        } catch {
            return (
                course: nil,
                destinations: [],
                refusal: SpecialNames.settingsCouldNotBeReadToDeploy(course: windowCourse.displayCode),
                notice: nil
            )
        }
        return (
            course: saved,
            destinations: saved.configuration.allDeployDestinations,
            refusal: SectionDetailView.deployRefusalReason(
                configuration: saved.configuration, cloudflareAccountID: cloudflareAccountID
            ),
            notice: SettingsSaveNotice.whenDeployStarts(settingsHaveUnsavedChanges: anyCopyUnsaved)
        )
    }

    /// What a deploy's caller is told (#335): when the assistant pressed the
    /// button and the deploy used the saved settings over unsaved edits, the
    /// window's sentence is added to the result it reads out, so the
    /// conversation says what the window says. The button's own result is
    /// never changed — the window already shows the sentence.
    static func whatTheAssistantIsTold(
        _ result: AssistSiteWorkResult, notice: String?, pressedByTheAssistant: Bool
    ) -> AssistSiteWorkResult {
        if !pressedByTheAssistant {
            return result
        }
        return AssistSiteWorkResult(
            succeeded: result.succeeded,
            message: SettingsSaveNotice.addingTheNotice(notice, to: result.message),
            isAboutTheDestination: result.isAboutTheDestination,
            wasBuiltElsewhere: result.wasBuiltElsewhere
        )
    }

    /// The notice's accessibility identifier, by whose sentence it is (#335).
    var unsavedSettingsNoticeIdentifier: String {
        if unsavedSettingsNoticeOwner == .deploy {
            return "deployUsesSavedSettingsNotice"
        }
        return "previewUsesSavedSettingsNotice"
    }

    /// Whether a preview ending takes the unsaved-settings sentence away:
    /// only when it is the preview's own, or nobody's (#335, F3).
    static func previewEndClearsTheNotice(owner: UnsavedSettingsNoticeOwner?) -> Bool {
        return owner != .deploy
    }

    /// The Deploy button. The work itself is `deployAndWait()`, so the
    /// assistant can press the same button and be told how it went.
    func startDeploy() {
        Task {
            // Classes dated after the next class (#475): asked AFTER the
            // deploy's own refusals — a refusal never follows a change — and
            // before anything is stopped or built (`askAboutClassesDatedLater`).
            let answer: LaterClassesAnswer = await askAboutClassesDatedLater(route: "Deploy")
            if answer == .cancelled || answer == .cannotAsk {
                return
            }
            let result: AssistSiteWorkResult = await deployAndWait(pressedByTheAssistant: false)
            // A refusal reaches the teacher as the alert this window has
            // always shown. The assistant's copy of the same sentence goes
            // into the conversation instead — see `deployAndWait()`.
            if !result.succeeded, result.isAboutTheDestination {
                deployRefusal = result.message
            }
        }
    }

    /// Publishes the section. If the built site is missing or older than
    /// the teacher's content, it is rebuilt first — quietly, without
    /// showing a preview — so what gets published is always current.
    ///
    /// **Why this returns a result rather than just doing it.** Two callers
    /// press Deploy now: the toolbar button, and the assistant when a teacher
    /// asks it to deploy. The button needs nothing back — the console and the
    /// progress header in front of the teacher ARE the answer. The assistant
    /// is in another window and has to say in words what happened, so the
    /// answer has to come back to it. Duplicating the deploy for the second
    /// caller is how a Cloudflare course quietly starts deploying to Netlify
    /// from one of the two paths, so there is only ever one.
    ///
    /// `pressedByTheAssistant` so the conversation says what the window says:
    /// when the deploy used the saved settings over unsaved edits (#335), the
    /// same sentence is added to the result the assistant reads out.
    func deployAndWait(pressedByTheAssistant: Bool) async -> AssistSiteWorkResult {
        // FIRST — before the busy check, before the destination check, before
        // any preview is stopped. A course kept for reference is never
        // deployed, and the teacher meets that as a missing button rather
        // than as a refusal; this is what catches every other way in.
        //
        // `isAboutTheDestination` so the window raises it as an alert: it is
        // a fact about the course rather than something that went wrong while
        // running, which is the same distinction the destination refusals make.
        if let refusal = SectionDetailView.refusalForAReferenceCourse(course) {
            return refusal
        }
        guard let workspaceURL = workspace.workspaceURL else {
            return AssistSiteWorkResult(
                succeeded: false, message: AssistToolRefusal.noWorkingFolder.message
            )
        }
        // The section's run, taken ONCE from the folder just checked, and the
        // only one this function touches from here on (#706 plan review, H1):
        // `deployRun` is asked again on every read, and a window pointed at
        // another folder during one of the awaits below would hand the rest
        // of this deploy a different section's run.
        let run: SectionDeployRun = SectionRuns.shared.deploy(
            folder: workspaceURL, courseCode: course.code, sectionNumber: sectionNumber
        )
        // The toolbar button disables itself while the section deploys, but
        // the assistant reaches this function directly, with no button to
        // have disabled — guard here too, or two overlapping deploys can run
        // at once and stomp on the runner's shared state (legs, startedAt) as
        // each writes over the other's. `deployIsUnderWay` also asks
        // `CourseActivity`, so a deploy of this section started from a view
        // that has since gone, another window, or the assistant with no
        // window is refused in words here rather than reaching the launcher
        // (#706).
        if SectionDetailView.deployIsUnderWay(
            run: run, folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber
        ) {
            return AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.sectionIsBusy(
                    course: course.code, section: String(sectionNumber)
                )
            )
        }
        // Every way in, the assistant's included (#351's second review, SF1).
        if CourseActivity.courseIsBeingCopied(folderPath: workspaceURL.path, courseCode: course.code) {
            return AssistSiteWorkResult(
                succeeded: false, message: AssistWording.courseIsBeingCopied(course: course.code)
            )
        }

        // Everything from here reads the settings as SAVED in the file at
        // this moment (#335), never this window's copy, which may hold Course
        // Settings edits nobody has saved. Every window's copy is asked about
        // unsaved edits, not only this one's, as the preview does.
        let anyWindowHasUnsavedSettings: Bool = course.configuration.hasUnsavedChanges
            || WorkspaceModel.anyCopyHasUnsavedChanges(configFileURL: course.configFileURL)
        let uses: (
            course: Course?, destinations: [CourseConfiguration.DeployDestination], refusal: String?, notice: String?
        ) = SectionDetailView.whatADeployUses(
            windowCourse: course,
            anyCopyUnsaved: anyWindowHasUnsavedSettings,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID
        )
        guard let saved = uses.course else {
            return AssistSiteWorkResult(
                succeeded: false,
                message: uses.refusal ?? SpecialNames.settingsCouldNotBeReadToDeploy(course: course.displayCode),
                isAboutTheDestination: true
            )
        }
        // The saved copy is checked too: `keptForReference` is not a Course
        // Settings field, so the two cannot differ in practice, and checking
        // costs nothing.
        if let refusal = SectionDetailView.refusalForAReferenceCourse(saved) {
            return refusal
        }
        let destinations: [CourseConfiguration.DeployDestination] = uses.destinations

        // Whatever is wrong with ANY configured destination is said here,
        // before a build starts: discovering it partway through a
        // redundancy run would waste the teacher's time and let some
        // destinations quietly go out while others never got the chance.
        if let problem = uses.refusal {
            // On the trail when it is the Account ID (#668): the refusal a
            // new course meets at its first deploy, by kind, never the ID.
            if let line = ActivityTrail.deployRefusedForTheAccountIDLine(
                destinations: destinations, cloudflareAccountID: AppSettings.shared.cloudflareAccountID
            ) {
                ActivityTrail.note(.deployRefusedForTheAccountID, line, course: saved.code, section: sectionNumber)
            }
            return AssistSiteWorkResult(
                succeeded: false, message: problem, isAboutTheDestination: true
            )
        }

        // Claim the course — `beginPublish`, which puts this window's own
        // `build` and `publish` leases on disk — and THEN look at the other
        // programs' leases, with nothing awaited in between (#156). Both
        // happen BEFORE the preview below is stopped, for two reasons. A
        // refusal placed any later would end the page the teacher was reading
        // for nothing. And the stop is `preview.sh --stop`, which finds a
        // section's processes by working directory and so ends BUILDS as well
        // as servers: holding the `build` lease through it means no other
        // program can be told the course is free and start a build that this
        // stop then kills (the review of #156, M1).
        //
        // ONE bracket around the whole sequence of destinations, not one per
        // destination: from outside this window — Add Section…, and every
        // other program — the course is "busy publishing" for the whole span.
        if let holding = WorkLeaseRegistry.claimAPublish(
            folderPath: workspaceURL.path, courseCode: course.code, sectionNumber: sectionNumber
        ) {
            WorkLeaseRegistry.noteDeclined(
                act: "Deploy", courseCode: course.code, sectionNumber: sectionNumber, holding: holding
            )
            return AssistSiteWorkResult.builtElsewhere(course: course)
        }
        defer {
            CourseActivity.endPublish(
                folderPath: workspaceURL.path,
                courseCode: course.code,
                sectionNumber: sectionNumber
            )
        }

        // Claim the console for the deploy panel before touching the preview
        // runner below. Stopping a running preview here sets its own
        // `wasStoppedByUser`, which — until `run.runner.run()` gives this a
        // real timestamp a little further down — left `showsDeployProgress`
        // comparing stale timestamps and picking the just-stopped preview
        // panel, flashing "Stopped" for a beat before the deploy panel took
        // over. Marking the deploy as started immediately keeps the console
        // on the deploy panel through that whole window.
        //
        // `run.isPreparing` covers what that timestamp alone does not:
        // `run.runner.legs` still holds the PREVIOUS deploy's runners
        // (finished, one way or another) until `run()` replaces them with
        // fresh ones a little further down, and `consoleArea` must not show
        // either that stale outcome or the flat-out blank a fresh, unstarted
        // runner renders as — neither is what is actually happening right
        // now, which is: getting ready to deploy.
        run.runner.startedAt = Date()
        run.isPreparing = true
        // Cleared on EVERY way out, not only the two this function names
        // below: nothing else resets it now that the run outlives the view
        // (#706 plan review, L5), and one left true would hold the section's
        // Deploy unavailable until quit.
        defer {
            run.isPreparing = false
        }
        // What the previous deploy left and nobody took is about that deploy.
        run.findingsAreWaiting = false

        // Stop any running or building preview before deploying, and wait for
        // container processes to exit so they cannot kill or race the deploy build.
        if previewRunner.isRunning {
            await stopPreviewAndWait()
        } else {
            await PreviewStopper.waitForStopsToFinish(
                courseCode: course.code, sectionNumber: sectionNumber
            )
        }

        // The unsaved-settings sentence, set AFTER the preview is stopped:
        // stopping it runs `releasePreviewLease()`, which clears the notice,
        // so setting it first would have the stop wipe it (#335). It stays
        // up after this deploy ends — a teacher reading the console must
        // still see why — and the next preview or deploy replaces it.
        unsavedSettingsNotice = uses.notice
        unsavedSettingsNoticeOwner = uses.notice == nil ? nil : .deploy
        run.unsavedSettingsNotice = uses.notice
        if uses.notice != nil {
            SettingsSaveNotice.noteDeployUsedTheSavedSettings(
                act: pressedByTheAssistant
                    ? "deployed by the assistant through the section window" : "deployed from the section window",
                saved: saved, windowCourse: course, sectionNumber: sectionNumber
            )
        }
        // What the assistant is told carries the same sentence.
        func said(_ result: AssistSiteWorkResult) -> AssistSiteWorkResult {
            return SectionDetailView.whatTheAssistantIsTold(
                result, notice: uses.notice, pressedByTheAssistant: pressedByTheAssistant
            )
        }

        // The note `startPreview()` makes, made here for the deploy —
        // AFTER any running preview has been stopped, never before. A
        // preview already running belongs to the folder IT started in, and
        // writing this first would have pointed that preview's own stop,
        // two lines up, at whatever the window happens to show now.
        // `cancelDeploy()` reclaims the container-side build against it.
        folderThisSectionWorksIn = workspaceURL
        run.folder = workspaceURL

        // What the Deploy button's `disabled` says, said in words. The
        // assistant reaches this by pressing the button while a deploy is
        // already running in this window.
        if run.runner.isRunning {
            return said(AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.sectionIsBusy(
                    course: course.code, section: String(sectionNumber)
                )
            ))
        }

        let buildReason: BuildFreshness.RebuildReason? = BuildFreshness.whyRebuild(course: saved, sectionNumber: sectionNumber)

        // The real progress panel takes over from here — `run.runner.run()`
        // is about to give its legs fresh runners of their own and start
        // reporting real progress on them.
        run.isPreparing = false

        // What the launcher is asked to do, for each destination, is
        // decided in one place — shared with the scheduled deploy and the
        // assistant's headless path, so an alarm set for half six sends
        // the site to the same destinations this button does.
        await run.runner.run(
            course: saved,
            sectionNumber: sectionNumber,
            destinations: destinations,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID,
            workingDirectory: workspaceURL,
            buildReason: buildReason
        )

        // A failed shared build is reported the same way regardless of
        // how many destinations were configured — none of them were ever
        // reached, so the wording says "could not be built", not "did
        // not finish", which would wrongly suggest the upload failed.
        // A build refused because the section was still being deployed
        // (#439) is said as itself, not as "could not be built" — the shared
        // answer, which the windowless assistant asks too, decides which.
        if let buildAnswer = MultiDestinationDeployRunner.answerWhenTheBuildDidNotFinish(
            course: course.code, section: String(sectionNumber), firstLeg: run.runner.legs.first
        ) {
            // Show the folder problems HERE too. A build that failed because
            // the curriculum folder or Media is missing is the case where the
            // finding is most likely to be the cause, and moving the call
            // below the early return had quietly dropped it altogether —
            // de-headlining it was the intent, discarding it was not.
            // Through the run (#706): the view that pressed Deploy may have
            // gone, and whichever view shows the section takes them.
            run.noteEnded()
            return said(buildAnswer)
        }

        // What the build said about this course's folders — AFTER the failure
        // paths above, so a deploy that did not publish is not headlined by a
        // folder warning. Taken from the FIRST leg: every destination publishes
        // the same built site, so a second leg only repeats the findings.
        // Handed over through the run, as above (#706).
        run.noteEnded()

        return said(MultiDestinationDeployRunner.result(
            course: course.code,
            section: String(sectionNumber),
            destinationCount: destinations.count,
            outcome: run.runner.outcome
        ))
    }

    /// Opens the page currently shown in the preview (not just the site
    /// root) in the teacher's default browser.
    func openInBrowser() {
        var urlToOpen: URL? = previewController.webView.url
        if urlToOpen == nil {
            urlToOpen = previewURL
        }
        if let urlToOpen {
            previewIsInTheBrowser = true
            NSWorkspace.shared.open(SectionDetailView.browserSafeURL(for: urlToOpen))
        }
    }

    /// The page this window's preview is showing at this moment, as its path
    /// below the preview's root (#518) — the web view's own address, not the
    /// page last viewed (#504), which ignores the app's own loads and so can
    /// name a page that is no longer on screen. Nil unless a page is showing.
    func previewedPagePath() -> String? {
        guard previewURL != nil, let previewRoot else {
            return nil
        }
        return PreviewStartPage.rememberedPath(page: previewController.webView.url, previewRoot: previewRoot)
    }

    /// Rewrites "localhost" to "127.0.0.1" for hand-off to a browser.
    /// Safari tries IPv6 (::1) first for "localhost", and the container
    /// only publishes the port on IPv4 — which reads as "server dropped
    /// the connection". The numeric address sidesteps that entirely.
    static func browserSafeURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.host == "localhost" {
            components.host = "127.0.0.1"
        }
        if let rewritten = components.url {
            return rewritten
        }
        return url
    }

    // MARK: - The page last viewed (#504)

    /// The key this section's page last viewed is kept under: the folder the
    /// preview's work belongs to (canonical, `FolderIdentity`), the course
    /// and the section. Nil when no preview has started here.
    func lastViewedKey() -> String? {
        guard let folder = folderThisSectionWorksIn else {
            return nil
        }
        return LastViewedPages.key(
            folderPath: FolderIdentity.canonicalPath(folder.path),
            courseCode: course.code,
            sectionNumber: sectionNumber
        )
    }

    /// Remembers the page the teacher just navigated to — only while this
    /// run is showing, and only an address on this run's own site
    /// (`PreviewStartPage.rememberedPath`). Measured against `previewRoot`,
    /// NEVER `previewURL`, which may be a page (504 plan review, finding 7).
    func rememberWhereTheTeacherIs() {
        guard previewURL != nil, let previewRoot, let key = lastViewedKey() else {
            return
        }
        guard let path = PreviewStartPage.rememberedPath(
            page: previewController.teacherPage, previewRoot: previewRoot
        ) else {
            return
        }
        LastViewedPages.shared.remember(path, forKey: key)
    }

    /// The address the preview opens at once its server has answered — the
    /// root, or the page last viewed when the request asked for it, one was
    /// remembered, and it answers — and the decision, whose trail line the
    /// CALLER writes once it knows the run is still the one this was about
    /// (implementation review, 2: a line written before that check could
    /// describe a page a stopped preview never opened). A gone page falls
    /// back to the front page with NO dialog and no band (decision 504-3):
    /// the trail says why.
    func startPageToShow(root: URL, request: PreviewStartPage.Request) async -> (page: URL, decision: PreviewStartPage.Decision) {
        var remembered: String?
        if let key = lastViewedKey() {
            remembered = LastViewedPages.shared.page(forKey: key)
        }
        var answer: PreviewStartPage.PageAnswer?
        var pageAddress: URL?
        if PreviewStartPage.needsAsking(request, remembered: remembered), let remembered {
            pageAddress = PreviewStartPage.pageAddress(root: root, path: remembered)
            if let pageAddress {
                answer = await PreviewStartPage.askWhetherThePageIsThere(
                    pageAddress,
                    attempts: PreviewStartPage.attempts,
                    fetch: SectionDetailView.statusOfPage,
                    pause: {
                        try? await Task.sleep(for: .seconds(1))
                    }
                )
            } else {
                answer = .didNotAnswer
            }
        }
        let decision: PreviewStartPage.Decision = PreviewStartPage.decide(
            request, remembered: remembered, answer: answer
        )
        if decision.opensRememberedPage, let pageAddress {
            return (page: pageAddress, decision: decision)
        }
        return (page: root, decision: decision)
    }

    /// One try at a page's address: its status after redirects (a folder
    /// page answers 302, then 200 — measured), or nil for a timeout or an
    /// error.
    nonisolated static func statusOfPage(_ page: URL) async -> Int? {
        var request: URLRequest = URLRequest(url: page)
        request.timeoutInterval = PreviewStartPage.secondsPerAttempt
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Waits for THIS run's Quartz server, then switches the view from
    /// console output to the embedded website.
    ///
    /// A previous preview (possibly of a different course) can still be
    /// serving on port 8081 when this run starts — the toolchain only
    /// kills it partway through the build. Polling immediately would
    /// happily embed that stale site, so this waits for the script's own
    /// "Launching Quartz preview" line first and only then trusts a
    /// response from the port.
    /// When this section's built landing page was last written, or nil when
    /// it has never been built.
    func builtIndexWrittenAt() -> Date? {
        let builtIndex: URL = course.directoryURL
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section\(sectionNumber)")
            .appendingPathComponent("public")
            .appendingPathComponent("index.html")
        return (try? FileManager.default
            .attributesOfItem(atPath: builtIndex.path)[.modificationDate]) as? Date
    }

    func waitForPreviewServer(port: Int, siteAsItWas: Date?, startRequest: PreviewStartPage.Request = .frontPage) async {
        // The launcher announces the real host address — the builder's
        // ports map to a per-folder block, so the port cannot be assumed,
        // and until it has been announced there is NO address: not the
        // section's port, which is the one inside the builder and wrong for
        // every working folder after the first (GitHub #235).
        var serverURL: URL?

        // How long this run has said NOTHING since the builder announced its
        // server — and nil until it has announced one.
        //
        // The distinction is the whole of issue #225. A run that is still
        // printing is not stalled however long it has been going, and a first
        // preview legitimately takes minutes; a run that has said its server
        // is up, and then says nothing and answers nothing, cannot be
        // explained by a big course or a slow Mac. So the bound is on the
        // QUIET rather than on the run, and it starts at that line rather
        // than at the start, where `waitedSeconds` starts.
        var silence: PreviewReachability.Silence?

        /// How much has been said, and when — which starts the clock at the
        /// builder's line and restarts it every time more arrives.
        ///
        /// `utf8.count` rather than `count`, because the only question here is
        /// whether MORE has been said than last time and counting graphemes
        /// to answer it would be waste. Reading `displayText` at all is not
        /// free: the transcript caches its joined text but throws the cache
        /// away on every chunk of output, so a noisy run re-joins its lines
        /// here once a second. Phases 1 and 2 already read it every second for
        /// their own reasons; this adds that cost to phase 3, on a string of
        /// at most 4,000 lines, once a second.
        func noticeWhatTheRunIsSaying() {
            let saidSoFar: String = previewRunner.transcript.displayText
            if silence == nil {
                if saidSoFar.contains(PreviewReachability.theBuilderSaysItsServerStarted) {
                    silence = PreviewReachability.Silence(
                        charactersSoFar: saidSoFar.utf8.count, at: Date()
                    )
                }
                return
            }
            silence?.note(charactersSoFar: saidSoFar.utf8.count, at: Date())
        }

        /// How long it has said nothing, once that is longer than anything a
        /// working preview does — and nil while there is still nothing to
        /// explain.
        func silenceThatCannotBeExplained() -> Int? {
            guard let silence else {
                return nil
            }
            let moment: Date = Date()
            if !silence.hasGoneQuiet(
                forSeconds: PreviewReachability.secondsOfSilenceBeforeGivingUp, at: moment
            ) {
                return nil
            }
            return silence.secondsOfSilence(at: moment)
        }

        // Phase 1: wait for the script to announce ITS server is starting
        // (which happens right after it has freed the port).
        // Up to 10 minutes: a first-ever build may pull the Docker image
        // and install npm dependencies.
        var waitedSeconds: Int = 0
        while waitedSeconds < 600 {
            if !previewRunner.isRunning && previewRunner.lastExitCode != nil {
                // The script exited before the server came up: show output.
                previewBuildWait.end()
                releasePreviewLease()
                return
            }
            if let announced = previewRunner.previewAddress {
                serverURL = announced
            }
            if previewRunner.transcript.displayText.contains("Launching Quartz preview") {
                break
            }
            try? await Task.sleep(for: .seconds(1))
            waitedSeconds += 1
        }

        // Phase 2: wait for THIS build to have written the site.
        //
        // Quartz's own handlers.js does this, in this order:
        //
        //     server.listen(argv.port)
        //     "Started a Quartz server listening at ..."
        //     await build(clientRefresh)
        //
        // It SERVES THE EXISTING public/ BEFORE IT REBUILDS IT. So the server
        // answers 200 straight away with the previous build and the fresh one
        // lands seconds later — which is why previewing after an edit showed
        // the old page, why stopping and starting showed it too, why doing the
        // same thing slowly worked, and why pressing Reload fixed it.
        //
        // The signal is the OUTPUT FILE, not a line of console text: Quartz's
        // wording can change between versions and its progress lines are
        // written through a spinner.
        //
        // And it is the file CHANGING, not the file looking recent. The build
        // happens inside the Linux VM, whose clock is its own — run ahead,
        // which it does after the Mac sleeps, and the previous build's
        // index.html already looks newer than any moment noted here, so a
        // "is it newer than now?" test passes immediately and shows exactly
        // the stale page it was written to prevent. Waiting for the value to
        // differ from what it was asks nothing of either clock.
        //
        // Bounded, so a build that never lands cannot leave a teacher watching
        // a spinner: after 120 seconds we show it anyway, and that is the one
        // case the reload below exists for.
        var buildFinished: Bool = false
        var waitedForBuild: Int = 0
        while waitedSeconds < 600 && waitedForBuild < 120 {
            if !previewRunner.isRunning && previewRunner.lastExitCode != nil {
                previewBuildWait.end()
                releasePreviewLease()
                return
            }
            if let announced = previewRunner.previewAddress {
                serverURL = announced
            }
            if let written = builtIndexWrittenAt(), written != siteAsItWas {
                buildFinished = true
                break
            }
            // A run that has announced its server and then gone quiet has
            // nothing left to wait for HERE: whatever it was going to write
            // has been written. Going on to phase 3 rather than giving up at
            // this point is deliberate — the site may well be answering, and
            // that is the case this loop's own bound exists to hand on to
            // (`buildFinished` stays false, so the one reload still happens).
            noticeWhatTheRunIsSaying()
            if silenceThatCannotBeExplained() != nil {
                break
            }
            try? await Task.sleep(for: .seconds(1))
            waitedSeconds += 1
            waitedForBuild += 1
        }
        if !buildFinished {
            AppLog.interface.info("preview showed before its build landed; it will reload once")
        }

        // Phase 3: poll until it actually answers, so the web view is never
        // pointed at an address that is not ready.
        while waitedSeconds < 600 {
            if !previewRunner.isRunning && previewRunner.lastExitCode != nil {
                previewBuildWait.end()
                releasePreviewLease()
                return
            }
            if let announced = previewRunner.previewAddress {
                serverURL = announced
            }
            // Only needed to decide the no-address case, and reading what the
            // run has said is not free (see `noticeWhatTheRunIsSaying`), so
            // the ordinary path does not pay for it twice a second.
            if serverURL == nil {
                noticeWhatTheRunIsSaying()
            }
            let next: PreviewReachability.NextStep = PreviewReachability.nextStep(
                announced: serverURL,
                theBuilderSaysItsServerStarted: silence != nil,
                theTeacherStoppedIt: previewRunner.wasStoppedByUser
            )
            let addressToOpen: URL
            switch next {
            case .tryTheAddress(let announced):
                addressToOpen = announced
            case .keepWaiting:
                try? await Task.sleep(for: .seconds(1))
                waitedSeconds += 1
                continue
            case .stopBecauseNothingWasAnnounced:
                stopBecauseNoAddressWasAnnounced()
                return
            }
            // The address the teacher's Mac is asked about — the announced
            // one, unless this copy of Plantoir has been started with the
            // debug-only request to pretend it cannot be reached, which is
            // how the sentence below can be seen on a healthy Mac.
            var request: URLRequest = URLRequest(
                url: PreviewReachability.addressToTry(announced: addressToOpen)
            )
            request.timeoutInterval = 2
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        // Where the site opens (#504): the front page, or the
                        // page last viewed when the teacher asked for it and
                        // it is still there. Asked HERE, after the root has
                        // answered: Quartz builds before it listens, so a 200
                        // means the first build is done (504 plan review
                        // M-c), and the launcher is never told a page.
                        let theRunThisIsAbout: Date? = previewRunner.startedAt
                        let startPage: (page: URL, decision: PreviewStartPage.Decision) = await startPageToShow(
                            root: addressToOpen, request: startRequest
                        )
                        let pageToShow: URL = startPage.page
                        // The question may have taken seconds. A run the
                        // teacher stopped, or a new one, owns what happens
                        // now; the SAME run ending by itself is ended here,
                        // as the other "the run ended" returns are.
                        if !PreviewReachability.isStillTheSameWait(
                            startedAt: theRunThisIsAbout,
                            theRunNowStartedAt: previewRunner.startedAt,
                            theTeacherStoppedIt: previewRunner.wasStoppedByUser,
                            theRunIsStillGoing: previewRunner.isRunning
                        ) {
                            if PreviewReachability.theSameRunEndedByItself(
                                startedAt: theRunThisIsAbout,
                                theRunNowStartedAt: previewRunner.startedAt,
                                theTeacherStoppedIt: previewRunner.wasStoppedByUser,
                                theRunIsStillGoing: previewRunner.isRunning
                            ) {
                                previewBuildWait.end()
                                releasePreviewLease()
                            }
                            return
                        }
                        // Only now, with the run known to be this one, is
                        // the start page recorded (#504).
                        if let words = startPage.decision.trailWords {
                            ActivityTrail.note(
                                .previewStartedAtLastViewed, words,
                                course: course.code, section: sectionNumber
                            )
                        }
                        previewBuildWait.end()
                        // Obsidian's add-ons for diagrams and graphs (#495):
                        // after the teacher's yes, a finished preview adds
                        // what the course needs — silently, off the main
                        // actor, and never into a course open in Obsidian.
                        workspace.addObsidianAddOnsAfterAPreview(course: course)
                        // Serving from here: a later end may be a deploy
                        // elsewhere closing it (#433's stack review).
                        previewRunner.hasBeenServing = true
                        previewRoot = addressToOpen
                        // `previewURL` IS the page shown, not the root: the
                        // view's `updateNSView` asks for it on every redraw,
                        // and the root there would throw the teacher back to
                        // the front page.
                        previewURL = pageToShow
                        // Load the fresh site EXPLICITLY, rather than trusting
                        // the mounting web view's `loadIfNeeded` to do it.
                        //
                        // That trust was watched being betrayed: a stray
                        // SwiftUI update between the stop and this moment
                        // loaded the OLD server's site and re-armed the
                        // controller's last-requested URL — so when the view
                        // mounted here, at the same address (a section keeps
                        // its port), `loadIfNeeded` skipped and the teacher
                        // kept the page from before their change.
                        //
                        // This is still a single load per rebuild — the call
                        // marks the URL as requested, so the mounting view's
                        // own `loadIfNeeded` becomes the no-op instead — which
                        // is why it does not reintroduce the flicker that made
                        // an unconditional reload-after-load worse than the
                        // problem it addressed.
                        previewController.showFreshBuild(pageToShow)
                        // And a second, later reload ONLY when we never saw
                        // the build finish: the bounded Phase 2 wait ran out,
                        // so what was just loaded may itself predate the
                        // build that is still landing.
                        if !buildFinished {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(900))
                                previewController.reload()
                            }
                        }
                        return
                    }
                }
            } catch {
                // Server not up yet — keep waiting.
            }
            // It has said its server is up, it has said nothing since, and it
            // has just failed to answer. That is as much as waiting can find
            // out, so stop and say which of the two things happened.
            //
            // This sits AFTER the attempt above rather than at the top of the
            // loop, deliberately: a run that arrives here with the clock
            // already run out — phase 2 breaks out on the same signal — still
            // gets one real try at the address before anything is decided.
            noticeWhatTheRunIsSaying()
            if let seconds = silenceThatCannotBeExplained() {
                await stopWaitingForThePreview(
                    portInsideTheBuilder: port, secondsOfSilence: seconds
                )
                return
            }
            try? await Task.sleep(for: .seconds(1))
            waitedSeconds += 1
        }
        previewBuildWait.end()
    }

    /// Ends a preview whose website started without any address for it ever
    /// being announced — so there is nothing to open, and nothing to ask the
    /// builder about either.
    ///
    /// Ended the way `stopWaitingForThePreview` ends one (read its comment
    /// for why stopping is right rather than merely giving up), with the
    /// third sentence, and without its question: that question is about an
    /// address. Nothing is awaited here, so the run cannot change underneath
    /// it; the one thing that CAN have happened since the wait last slept —
    /// the teacher pressing Stop — is ruled out before this is reached
    /// (`PreviewReachability.nextStep`'s `theTeacherStoppedIt`).
    func stopBecauseNoAddressWasAnnounced() {
        ActivityTrail.note(
            .previewNeverAppeared,
            PreviewReachability.trailLineWhenNothingWasAnnounced,
            course: course.code,
            section: sectionNumber
        )
        stopPreview()
        showALateRefusal(
            title: PreviewReachability.alertTitle,
            sentence: PreviewReachability.sentence(for: PreviewReachability.verdictWhenNothingWasAnnounced)
        )
    }

    /// Ends a preview that announced its website and never showed it, and
    /// tells the teacher which of the two things happened.
    ///
    /// **The builder is asked first, and that order is load-bearing**:
    /// stopping the preview ends the very server the question is about, so
    /// asking afterwards would answer "nothing is serving it" every time and
    /// the teacher would be told their website had failed to build when it
    /// had not.
    ///
    /// **Then the run is STOPPED, the way the Stop Preview button stops it.**
    /// Three things follow from that and all three are wanted. Nothing is
    /// left serving a website nobody can see. The section stops reporting
    /// itself as building — `SectionWindowControllers` reads a running runner
    /// with no address as `.building`, so a wait that merely gave up would
    /// have every other window and the assistant saying it was still building
    /// for ever. And the port goes back through the one path that hands it
    /// back, rather than being freed under a server that still holds it.
    func stopWaitingForThePreview(portInsideTheBuilder: Int, secondsOfSilence: Int) async {
        // Which run this is about, noted before the question rather than
        // assumed after it — see `isStillTheSameWait`.
        let theRunThisIsAbout: Date? = previewRunner.startedAt

        var answer: PreviewReachability.Answer = .couldNotFindOut
        if let folder = folderThisSectionWorksIn {
            answer = await PreviewReachability.askTheBuilder(
                PreviewReachability.askTheBuilderCommand(
                    containerName: FolderContainers.containerName(forFolder: folder.path),
                    portInsideTheBuilder: portInsideTheBuilder
                )
            )
        }
        // The teacher may have pressed Stop, or closed the window, while the
        // question was being asked. Then there is nothing left to say: an
        // alert about a preview they have already ended, and a trail line
        // saying it never appeared, would both be about a run that stopped
        // because they wanted it to.
        if !PreviewReachability.isStillTheSameWait(
            startedAt: theRunThisIsAbout,
            theRunNowStartedAt: previewRunner.startedAt,
            theTeacherStoppedIt: previewRunner.wasStoppedByUser,
            theRunIsStillGoing: previewRunner.isRunning
        ) {
            // One of those endings is nobody's doing: the SAME run ended on
            // its own while the question was out. Stop, Cancel, a closed
            // window and a new run have each ended the wait already; this one
            // has not, and `waitForPreviewServer` returns straight after us —
            // so it is ended here, the way the other "the run ended" returns
            // do, or ⌘Q would go on asking about it (issue #232). Guarded,
            // not unconditional: when a NEW run has started, the wait belongs
            // to it.
            if PreviewReachability.theSameRunEndedByItself(
                startedAt: theRunThisIsAbout,
                theRunNowStartedAt: previewRunner.startedAt,
                theTeacherStoppedIt: previewRunner.wasStoppedByUser,
                theRunIsStillGoing: previewRunner.isRunning
            ) {
                previewBuildWait.end()
                releasePreviewLease()
            }
            return
        }
        let verdict: PreviewReachability.Verdict = PreviewReachability.verdict(for: answer)
        ActivityTrail.note(
            .previewNeverAppeared,
            PreviewReachability.trailLine(for: verdict, secondsOfSilence: secondsOfSilence),
            course: course.code,
            section: sectionNumber
        )
        stopPreview()
        showALateRefusal(
            title: PreviewReachability.alertTitle,
            sentence: PreviewReachability.sentence(for: verdict)
        )
    }
}
