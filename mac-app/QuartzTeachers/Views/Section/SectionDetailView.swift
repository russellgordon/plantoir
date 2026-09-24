import SwiftUI

/// One section of a course: Preview builds and serves the site with
/// `preview.sh` and shows it in an embedded web view; Deploy publishes it
/// with `deploy.sh`. All output streams into a console below.
struct SectionDetailView: View {

    // MARK: - Stored properties

    let course: Course
    let sectionNumber: Int

    @State var previewRunner = ScriptRunner()

    /// Runs every configured destination in sequence — see
    /// `MultiDestinationDeployRunner`. For the overwhelming majority of
    /// courses (exactly one destination) this behaves exactly like a
    /// single `ScriptRunner` always did.
    @State var deployRunner = MultiDestinationDeployRunner()

    /// True from the moment Deploy is pressed until `deployRunner` actually
    /// starts running — the span spent stopping any preview and doing the
    /// pre-flight checks below, before there is any real progress to show.
    /// `consoleArea` shows a plain "Preparing to deploy…" placeholder while
    /// this is true, instead of `TaskProgressView` bound to a `deployRunner`
    /// that has nothing to say yet — a fresh, idle runner renders as
    /// nothing at all (see `deployAndWait()`), and the PREVIOUS deploy's
    /// runner still holding last time's finished outcome is no better,
    /// since neither is what is actually happening right now.
    @State var isPreparingDeploy: Bool = false

    @State var previewController = WebPreviewController()
    @State var previewURL: URL?
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

    /// Why a preview could not start, or did not appear, shown as an alert.
    @State var previewRefusal: String?

    /// What that alert is CALLED, because two different things now arrive in
    /// it and one title cannot be true of both.
    ///
    /// "Cannot Preview Yet" is right for a refusal to start — another window
    /// holds the section, so wait and it will work. It is wrong in front of a
    /// preview that built, was served, and could not be reached: there the
    /// remedy is restarting the Mac and "Yet" quietly says otherwise. A
    /// SECOND `.alert` modifier was the obvious alternative and is the one
    /// thing this view must not have — four alerts on it segfaulted SwiftUI's
    /// bridge, which is why the folder dialogs share one.
    ///
    /// Every write of `previewRefusal` sets this beside it.
    @State var previewRefusalTitle: String = "Cannot Preview Yet"

    /// A publish that was set to happen on its own and did not get through.
    ///
    /// Read from disk rather than held in memory, because the run that wrote
    /// it happened at half six with this app closed. Nil when the last
    /// scheduled run got through, when there has never been one, or when the
    /// teacher has dismissed it.
    @State var stoppedScheduledPublish: ScheduledPublishOutcome.Stopped?

    /// Folder problems the last build reported, shown once when it finishes.
    ///
    /// Held here rather than read from the runner at render time so that the
    /// dialog appears ONCE per run: a teacher who dismisses it and carries on
    /// editing must not have it thrown at them again on every redraw.
    @State var healthFindings: [SiteHealthFinding] = []

    /// Drives the dialog separately from the findings themselves, so the title
    /// is not recomputed from an array that the dismissal is clearing.
    /// Findings that arrived while a dialog was already up, waiting their turn
    /// — each batch with the occasion it arrived on.
    ///
    /// The occasion travels WITH them because it decides what is offered next.
    /// Held findings used to be shown with whatever the flag happened to be
    /// from the previous batch, so a preview's findings held behind an
    /// overnight publish were given the publish sentence, and the reverse told
    /// somebody who had just published that only their preview was stale.
    @State var heldHealthFindings: [(findings: [SiteHealthFinding], cameFromPublishing: Bool)] = []

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

    /// Why a deploy could not start, shown as an alert.
    @State var deployRefusal: String?

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

    // MARK: - Body

    var body: some View {
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
            ZStack {
                // Base layer: always laid out in the normal, safe-area
                // respecting flow. Keeping it mounted means its geometry is
                // never inherited from the full-bleed web view above it —
                // which is what dragged the progress header under the
                // window's toolbar when a preview was restarted.
                VStack(spacing: 0) {
                    if isWaitingForServer || isBusy || !previewRunner.transcript.lines.isEmpty || deployRunner.hasAnyOutput {
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
                if let previewURL {
                    WebPreviewView(controller: previewController, url: previewURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("previewWebView")
                }
            }
        }
        .navigationTitle(titleText)
        .task {
            refreshEditedMarker()
        }
        .onChange(of: isBusy) { _, nowBusy in
            // A publish clears the marker; a preview leaves the content
            // alone but is the other moment the folder has just been read.
            if !nowBusy {
                refreshEditedMarker()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshEditedMarker()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshEditedMarker()
        }
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
        .toolbar {
            // Every item is ALWAYS present (disabled when inapplicable):
            // conditionally inserting toolbar items makes macOS rebuild
            // the toolbar, which briefly mis-lays-out the title area.
            ToolbarItemGroup(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") {
                    previewController.goBack()
                }
                .disabled(previewURL == nil || !previewController.canGoBack)
                .help("Go back a page")
                .accessibilityIdentifier("previewBackButton")

                Button("Forward", systemImage: "chevron.right") {
                    previewController.goForward()
                }
                .disabled(previewURL == nil || !previewController.canGoForward)
                .help("Go forward a page")
                .accessibilityIdentifier("previewForwardButton")

                Button("Reload", systemImage: "arrow.clockwise") {
                    previewController.reload()
                }
                .disabled(previewURL == nil)
                .help("Reload this page")
                .accessibilityIdentifier("previewReloadButton")
            }
            ToolbarItemGroup {
                Button("Open in Obsidian", systemImage: "square.and.pencil") {
                    FolderActions.openInObsidian(
                        revealing: course.sectionDirectoryURL(forSection: sectionNumber),
                        vaultURL: course.directoryURL
                    )
                }
                .disabled(!FolderActions.obsidianIsInstalled)
                .help("Edit this section's pages in Obsidian")
                .accessibilityIdentifier("openInObsidianButton")

                // One stable item that changes face, not two swapped
                // items — swapping rebuilds the toolbar (same glitch).
                Button(
                    previewRunner.isRunning ? "Stop Preview" : "Preview",
                    systemImage: previewRunner.isRunning ? "stop.fill" : "play.fill"
                ) {
                    if previewRunner.isRunning {
                        stopPreview()
                    } else {
                        startPreview()
                    }
                }
                // The icon alone doesn't say what these two buttons do, so
                // they wear their titles; the neighbouring icons are the
                // familiar Obsidian and Safari actions and stay icon-only.
                .labelStyle(.titleAndIcon)
                .disabled(!previewRunner.isRunning && isBusy)
                .help(previewRunner.isRunning ? "Stop previewing this section" : "Preview this section's website")
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
                .disabled(deployRunner.isRunning || isPreparingDeploy)
                .help("Deploy this section's website")
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
        .focusedSceneValue(\.previewController, previewURL != nil ? previewController : nil)
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
                    deploy: { await deployAndWait() }
                )
            )
        }
        .task {
            // Anything the overnight publish found. It ran with the app
            // closed, so this is the first moment there is anywhere to say it
            // — and `takeFolderProblems` consumes the record, so it is
            // reported once rather than every time this window opens.
            // Guard BEFORE consuming: `takeFolderProblems` deletes the record
            // as it reads it, so taking it while a dialog is already up threw
            // the overnight findings away permanently.
            guard healthFindings.isEmpty else {
                return
            }
            let waiting: [SiteHealthFinding] = ScheduledDeploy.takeFolderProblems(
                courseCode: course.code, sectionNumber: sectionNumber
            )
            if !waiting.isEmpty {
                healthFindings = waiting
                // The overnight run PUBLISHED, so the sentence must say that
                // students are still seeing the old site.
                healthFindingsCameFromPublishing = true
                healthDialog = .findings
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
        }
        .alert(previewRefusalTitle, isPresented: previewRefusalBinding) {
            Button("OK") {
                previewRefusal = nil
            }
        } message: {
            Text(previewRefusal ?? "")
        }
        .alert("Cannot Deploy Yet", isPresented: deployRefusalBinding) {
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
                Button("OK") { }
            case .outcome:
                if repairOutcome?.canRebuild == true {
                    Button("Preview Again") {
                        rebuildAfterRepair()
                    }
                }
                Button("OK") { }
            case .none:
                Button("OK") { }
            }
        } message: {
            Text(healthAlertMessage)
        }
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
                repairOutcome = nil
                showAnythingWaiting()
            }
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
        if healthFindings.count == 1 {
            return healthFindings[0].sentence
        }
        if healthFindings.isEmpty {
            // Reached only while the alert is being torn down, after the
            // findings have been cleared. Saying "0 things need your attention"
            // there is the unreachable-by-design string made reachable, which
            // this view has now met twice.
            return ""
        }
        return "\(healthFindings.count) things need your attention"
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
        var paragraphs: [String] = []
        for finding in healthFindings {
            if healthFindings.count == 1 {
                paragraphs.append(finding.detail)
            } else {
                paragraphs.append(finding.sentence + "\n" + finding.detail)
            }
        }
        return paragraphs.joined(separator: "\n\n")
    }

    /// Shows whatever is queued, now that the dialog it was queued behind has
    /// gone.
    ///
    /// One alert at a time: SwiftUI presents one per view, and asking for a
    /// second while the first is dismissing loses one of them. A repair's
    /// outcome goes first — it is the answer to something the teacher just
    /// pressed — and findings that arrived meanwhile follow.
    func showAnythingWaiting() {
        if let waiting = pendingRepairOutcome {
            pendingRepairOutcome = nil
            repairOutcome = waiting
            healthDialog = .outcome
            return
        }
        if !heldHealthFindings.isEmpty {
            let next = heldHealthFindings.removeFirst()
            healthFindings = next.findings
            healthFindingsCameFromPublishing = next.cameFromPublishing
            healthDialog = .findings
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
                    if lease.folderPath == folder.path
                        && lease.courseCode == course.code
                        && lease.sectionNumber == sectionNumber {
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
                    headline: "Plantoir is publishing this course just now.",
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

    /// Puts a finished run's folder problems in front of the teacher.
    ///
    /// Only when the run actually produced some — a healthy course must never
    /// see a dialog, which is the difference between a warning that gets read
    /// and one that gets dismissed by habit.
    func showHealthFindings(from runner: ScriptRunner?, cameFromPublishing: Bool = false) {
        guard let runner, !runner.healthFindings.isEmpty else {
            return
        }
        // Never swap the contents of a dialog that is already up: the title
        // and the message would change under the teacher's cursor, and the
        // findings they were reading would vanish unacknowledged.
        //
        // But HELD, not dropped. Returning early discarded them — and the
        // failed-deploy path can arrive while the overnight findings are
        // already on screen, so this is reachable rather than theoretical.
        if healthDialog != nil {
            // Appended, not assigned: three arrivals during one dialog used to
            // lose the middle batch.
            heldHealthFindings.append(
                (findings: runner.healthFindings, cameFromPublishing: cameFromPublishing)
            )
            return
        }
        healthFindings = runner.healthFindings
        healthFindingsCameFromPublishing = cameFromPublishing
        healthDialog = .findings
    }

    /// Why this section's deploy would not get anywhere, or nil when it
    /// would. EVERY configured destination is checked — the primary and
    /// every additional one — so a redundancy target with no valid folder
    /// or credential is caught here rather than discovered halfway
    /// through a run that already published to the others.
    var deployRefusalReason: String? {
        return SectionDetailView.deployRefusalReason(
            configuration: course.configuration,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID
        )
    }

    /// The same check, free of the view, so it can be tested.
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

    var previewRefusalBinding: Binding<Bool> {
        return Binding(
            get: { previewRefusal != nil },
            set: { isPresented in
                if !isPresented {
                    previewRefusal = nil
                }
            }
        )
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
            previewStartedAt: previewRunner.startedAt,
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
        ScheduledPublishOutcome.clear(
            inHomeFolder: ScheduledDeploy.homeForScheduledNotes,
            course: course.code,
            section: sectionNumber
        )
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
        stoppedScheduledPublish = ScheduledPublishOutcome.stopped(
            inHomeFolder: ScheduledDeploy.homeForScheduledNotes,
            course: course.code,
            section: sectionNumber
        )
    }

    // MARK: - Functions

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

    func startPreview() {
        guard let workspaceURL = workspace.workspaceURL else {
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
            previewRefusalTitle = "Cannot Preview Yet"
            previewRefusal = error.localizedDescription
            return
        }
        previewLease = lease
        previewURL = nil
        previewBuildWait.begin(
            folderPath: workspaceURL.path,
            courseCode: course.code,
            sectionNumber: sectionNumber
        )
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
            previewRunner.run(
                scriptNamed: "preview.sh",
                arguments: [course.code, String(sectionNumber), "--port", String(lease.port)],
                workingDirectory: workspaceURL
            )
            await waitForPreviewServer(port: lease.port, siteAsItWas: siteAsItWas)

            // A second chance, for the ordinary case where the wait finished
            // quickly and the teacher is now looking at the preview. The
            // findings usually arrived long before this — see the onChange on
            // the body, which is what actually gets them on screen.
            showHealthFindings(from: previewRunner)
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
        previewBuildWait.end()
        // The next preview reuses this section's port, so its address will be
        // identical to the one already loaded. Without this the web view sees
        // a URL it has seen before and shows the pages it already had —
        // which is how a rebuilt site kept appearing unchanged.
        previewController.forgetLoadedPage()
        releasePreviewLease()
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
        previewBuildWait.end()
        previewController.forgetLoadedPage()
        releasePreviewLease()
    }

    /// Cancels the running deploy from the progress view.
    func cancelDeploy() {
        if deployRunner.isRunning, let workspaceURL = folderThisSectionWorksIn {
            PreviewStopper.stopSectionProcesses(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                workspaceURL: workspaceURL
            )
        }
        deployRunner.cancel()
    }

    /// Hands the port back, whatever ended the preview.
    func releasePreviewLease() {
        if let lease = previewLease {
            PreviewLeases.release(lease)
            previewLease = nil
        }
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

    /// The Deploy button. The work itself is `deployAndWait()`, so the
    /// assistant can press the same button and be told how it went.
    func startDeploy() {
        Task {
            let result: AssistSiteWorkResult = await deployAndWait()
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
    func deployAndWait() async -> AssistSiteWorkResult {
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
        // The toolbar button disables itself on `isPreparingDeploy`, but the
        // assistant reaches this function directly, with no button to have
        // disabled — guard here too, or two overlapping deploys can run at
        // once and stomp on `deployRunner`'s shared state (legs, startedAt)
        // as each writes over the other's.
        if isPreparingDeploy || deployRunner.isRunning {
            return AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.sectionIsBusy(
                    course: course.code, section: String(sectionNumber)
                )
            )
        }

        let destinations: [CourseConfiguration.DeployDestination] = course.configuration.allDeployDestinations

        // Whatever is wrong with ANY configured destination is said here,
        // before a build starts: discovering it partway through a
        // redundancy run would waste the teacher's time and let some
        // destinations quietly go out while others never got the chance.
        if let problem = deployRefusalReason {
            return AssistSiteWorkResult(
                succeeded: false, message: problem, isAboutTheDestination: true
            )
        }

        // Claim the console for the deploy panel before touching the preview
        // runner below. Stopping a running preview here sets its own
        // `wasStoppedByUser`, which — until `deployRunner.run()` gives this a
        // real timestamp a little further down — left `showsDeployProgress`
        // comparing stale timestamps and picking the just-stopped preview
        // panel, flashing "Stopped" for a beat before the deploy panel took
        // over. Marking the deploy as started immediately keeps the console
        // on the deploy panel through that whole window.
        //
        // `isPreparingDeploy` covers what that timestamp alone does not:
        // `deployRunner.legs` still holds the PREVIOUS deploy's runners
        // (finished, one way or another) until `run()` replaces them with
        // fresh ones a little further down, and `consoleArea` must not show
        // either that stale outcome or the flat-out blank a fresh, unstarted
        // runner renders as — neither is what is actually happening right
        // now, which is: getting ready to deploy.
        deployRunner.startedAt = Date()
        isPreparingDeploy = true

        // Stop any running or building preview before deploying, and wait for
        // container processes to exit so they cannot kill or race the deploy build.
        if previewRunner.isRunning {
            await stopPreviewAndWait()
        } else {
            await PreviewStopper.waitForStopsToFinish(
                courseCode: course.code, sectionNumber: sectionNumber
            )
        }

        // The note `startPreview()` makes, made here for the deploy —
        // AFTER any running preview has been stopped, never before. A
        // preview already running belongs to the folder IT started in, and
        // writing this first would have pointed that preview's own stop,
        // two lines up, at whatever the window happens to show now.
        // `cancelDeploy()` reclaims the container-side build against it.
        folderThisSectionWorksIn = workspaceURL

        // What the Deploy button's `disabled` says, said in words. The
        // assistant reaches this by pressing the button while a deploy is
        // already running in this window.
        if deployRunner.isRunning {
            isPreparingDeploy = false
            return AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.sectionIsBusy(
                    course: course.code, section: String(sectionNumber)
                )
            )
        }

        let needsBuild: Bool = BuildFreshness.needsRebuild(course: course, sectionNumber: sectionNumber)

        // Let the rest of the app know this course is mid-publish (so,
        // for example, Add Section… declines until it finishes) — ONE
        // bracket around the whole sequence of destinations, not one per
        // destination: from outside this window, the course is "busy
        // publishing" for the whole span.
        CourseActivity.beginPublish(
            folderPath: workspaceURL.path,
            courseCode: course.code,
            sectionNumber: sectionNumber
        )
        defer {
            CourseActivity.endPublish(
                folderPath: workspaceURL.path,
                courseCode: course.code,
                sectionNumber: sectionNumber
            )
        }

        // The real progress panel takes over from here — `deployRunner.run()`
        // is about to give `deployRunner.legs` fresh runners of its own and
        // start reporting real progress on them.
        isPreparingDeploy = false

        // What the launcher is asked to do, for each destination, is
        // decided in one place — shared with the scheduled deploy and the
        // assistant's headless path, so an alarm set for half six sends
        // the site to the same destinations this button does.
        await deployRunner.run(
            course: course,
            sectionNumber: sectionNumber,
            destinations: destinations,
            cloudflareAccountID: AppSettings.shared.cloudflareAccountID,
            workingDirectory: workspaceURL,
            needsBuild: needsBuild
        )

        // A failed shared build is reported the same way regardless of
        // how many destinations were configured — none of them were ever
        // reached, so the wording says "could not be built", not "did
        // not finish", which would wrongly suggest the upload failed.
        if deployRunner.legs.first?.buildFailed == true {
            // Show the folder problems HERE too. A build that failed because
            // the curriculum folder or Media is missing is the case where the
            // finding is most likely to be the cause, and moving the call
            // below the early return had quietly dropped it altogether —
            // de-headlining it was the intent, discarding it was not.
            showHealthFindings(from: deployRunner.legs.first?.runner, cameFromPublishing: true)
            return AssistSiteWorkResult(
                succeeded: false,
                message: AssistWording.couldNotBuildBeforeDeploying(
                    course: course.code, section: String(sectionNumber)
                )
            )
        }

        // What the build said about this course's folders — AFTER the failure
        // paths above, so a deploy that did not publish is not headlined by a
        // folder warning. Taken from the FIRST leg: every destination publishes
        // the same built site, so a second leg only repeats the findings.
        showHealthFindings(from: deployRunner.legs.first?.runner, cameFromPublishing: true)

        return MultiDestinationDeployRunner.result(
            course: course.code,
            section: String(sectionNumber),
            destinationCount: destinations.count,
            outcome: deployRunner.outcome
        )
    }

    /// Opens the page currently shown in the preview (not just the site
    /// root) in the teacher's default browser.
    func openInBrowser() {
        var urlToOpen: URL? = previewController.webView.url
        if urlToOpen == nil {
            urlToOpen = previewURL
        }
        if let urlToOpen {
            NSWorkspace.shared.open(SectionDetailView.browserSafeURL(for: urlToOpen))
        }
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

    func waitForPreviewServer(port: Int, siteAsItWas: Date?) async {
        // The launcher announces the real host address — the container's
        // ports map to a per-folder block, so the port cannot be assumed.
        var serverURL: URL = URL(string: "http://127.0.0.1:\(port)/")!

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
            // The address the teacher's Mac is asked about — the announced
            // one, unless this copy of Plantoir has been started with the
            // debug-only request to pretend it cannot be reached, which is
            // how the sentence below can be seen on a healthy Mac.
            var request: URLRequest = URLRequest(
                url: PreviewReachability.addressToTry(announced: serverURL)
            )
            request.timeoutInterval = 2
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        previewBuildWait.end()
                        previewURL = serverURL
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
                        previewController.showFreshBuild(serverURL)
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
        previewRefusalTitle = PreviewReachability.alertTitle
        previewRefusal = PreviewReachability.sentence(for: verdict)
    }
}
