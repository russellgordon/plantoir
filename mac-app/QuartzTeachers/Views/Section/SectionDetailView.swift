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
    @State var isWaitingForServer: Bool = false

    /// The port this window's preview holds, while it holds one.
    @State var previewLease: PreviewLeases.Lease?

    /// Why a preview could not start, shown as an alert.
    @State var previewRefusal: String?

    /// Folder problems the last build reported, shown once when it finishes.
    ///
    /// Held here rather than read from the runner at render time so that the
    /// dialog appears ONCE per run: a teacher who dismisses it and carries on
    /// editing must not have it thrown at them again on every redraw.
    @State var healthFindings: [SiteHealthFinding] = []

    /// Drives the dialog separately from the findings themselves, so the title
    /// is not recomputed from an array that the dismissal is clearing.
    @State var isShowingHealthFindings: Bool = false

    /// Findings that arrived while a dialog was already up, waiting their turn.
    @State var heldHealthFindings: [SiteHealthFinding] = []

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

    /// What this section is CALLED — used wherever a sentence names it
    /// ("Deploying ICS3U-S1"). Deliberately without the " — Edited"
    /// marker: the marker is a statement about the window's contents, not
    /// part of the section's name, and "Deploying ICS3U-S1 — Edited" reads
    /// as though "Edited" were something being deployed.
    var sectionName: String {
        return "\(course.code)-S\(sectionNumber)"
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
                    ContentUnavailableView(
                        "No Preview Running",
                        systemImage: "globe",
                        description: Text(course.configuration.deploysToLocalFolder
                            ? "Click Preview to build this section's website and see it here, or Deploy to copy it to your deploy folder."
                            : "Click Preview to build this section's website and see it here, or Deploy to put it online.")
                    )
                }
            }

            // Cover layer: the site itself, deliberately full-bleed.
            if let previewURL {
                WebPreviewView(controller: previewController, url: previewURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("previewWebView")
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
            guard let folder = workspace.workspaceURL else {
                return
            }
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
                isShowingHealthFindings = true
            }
        }
        .onDisappear {
            if let folder = workspace.workspaceURL {
                SectionWindowControllers.shared.unregister(
                    folderPath: folder.path,
                    courseCode: course.code,
                    sectionNumber: sectionNumber
                )
            }
            stopPreview()
        }
        .alert("Cannot Preview Yet", isPresented: previewRefusalBinding) {
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
        .alert(healthAlertTitle, isPresented: $isShowingHealthFindings) {
            Button("OK") { }
        } message: {
            Text(healthAlertMessage)
        }
        .onChange(of: isShowingHealthFindings) { _, isShowing in
            // Cleared only once the alert is actually gone. Clearing inside the
            // button's action re-evaluated the title in the same update as the
            // dismissal, which made the unreachable-by-design
            // "0 things need your attention" string reachable.
            if !isShowing {
                healthFindings = []
                // Anything that arrived while this one was up gets its turn now
                // rather than being lost.
                if !heldHealthFindings.isEmpty {
                    healthFindings = heldHealthFindings
                    heldHealthFindings = []
                    isShowingHealthFindings = true
                }
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
        if healthFindings.count == 1 {
            return healthFindings[0].sentence
        }
        return "\(healthFindings.count) things need your attention"
    }

    var healthAlertMessage: String {
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

    /// Puts a finished run's folder problems in front of the teacher.
    ///
    /// Only when the run actually produced some — a healthy course must never
    /// see a dialog, which is the difference between a warning that gets read
    /// and one that gets dismissed by habit.
    func showHealthFindings(from runner: ScriptRunner?) {
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
        if isShowingHealthFindings {
            heldHealthFindings = runner.healthFindings
            return
        }
        healthFindings = runner.healthFindings
        isShowingHealthFindings = true
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
            previewRefusal = error.localizedDescription
            return
        }
        previewLease = lease
        previewURL = nil
        isWaitingForServer = true
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

            // Here rather than when the run "finishes": a preview does not
            // finish, it keeps serving. The folder checks print early, well
            // before Quartz starts, so by the time the server answers the
            // findings are already collected — and this is the moment the
            // teacher is actually looking at the preview.
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
        let folder: URL? = workspace.workspaceURL
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
        if previewRunner.isRunning, let workspaceURL = workspace.workspaceURL {
            PreviewStopper.stopSectionProcesses(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                workspaceURL: workspaceURL
            )
        }
        previewRunner.stopByUser()
        previewURL = nil
        isWaitingForServer = false
        // The next preview reuses this section's port, so its address will be
        // identical to the one already loaded. Without this the web view sees
        // a URL it has seen before and shows the pages it already had —
        // which is how a rebuilt site kept appearing unchanged.
        previewController.forgetLoadedPage()
        releasePreviewLease()
    }

    /// Cancels the running preview from the progress view.
    func cancelPreview() {
        if previewRunner.isRunning, let workspaceURL = workspace.workspaceURL {
            PreviewStopper.stopSectionProcesses(
                courseCode: course.code,
                sectionNumber: sectionNumber,
                workspaceURL: workspaceURL
            )
        }
        previewRunner.cancelByUser()
        previewURL = nil
        isWaitingForServer = false
        previewController.forgetLoadedPage()
        releasePreviewLease()
    }

    /// Cancels the running deploy from the progress view.
    func cancelDeploy() {
        if deployRunner.isRunning, let workspaceURL = workspace.workspaceURL {
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
            showHealthFindings(from: deployRunner.legs.first?.runner)
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
        showHealthFindings(from: deployRunner.legs.first?.runner)

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

        // Phase 1: wait for the script to announce ITS server is starting
        // (which happens right after it has freed the port).
        // Up to 10 minutes: a first-ever build may pull the Docker image
        // and install npm dependencies.
        var waitedSeconds: Int = 0
        while waitedSeconds < 600 {
            if !previewRunner.isRunning && previewRunner.lastExitCode != nil {
                // The script exited before the server came up: show output.
                isWaitingForServer = false
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
                isWaitingForServer = false
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
                isWaitingForServer = false
                releasePreviewLease()
                return
            }
            var request: URLRequest = URLRequest(url: serverURL)
            request.timeoutInterval = 2
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        isWaitingForServer = false
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
            try? await Task.sleep(for: .seconds(1))
            waitedSeconds += 1
        }
        isWaitingForServer = false
    }
}
