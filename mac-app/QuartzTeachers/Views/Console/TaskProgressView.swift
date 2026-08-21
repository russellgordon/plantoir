import AppKit
import OSLog
import SwiftUI

/// The friendly face of a running task: an indeterminate progress bar
/// with a plain-language phase description, and the detailed output
/// tucked behind a "Show details" toggle.
///
/// Layout contract: the header is pinned and fixed; the output area is
/// a FIXED-HEIGHT scroll view that is clipped, so no amount of output
/// can ever push the header (or anything else) out of reach.
struct TaskProgressView: View {

    // MARK: - Stored properties

    let runner: ScriptRunner
    let title: String
    let canCancel: Bool
    /// True only for a multi-destination deploy, where this view is bound
    /// to whichever leg ran LAST — showing that one leg's own "Your website
    /// is live" link would read as though it were the whole story.
    /// `DeployDestinationLinks` shows every succeeded destination's own
    /// link instead; a single-destination deploy (the overwhelming
    /// majority) never sets this and looks exactly as it always has.
    let hidesSiteLink: Bool
    let onCancel: (() -> Void)?

    @State var isShowingDetails: Bool = false
    @State var isShowingWhyTakingLong: Bool = false

    // MARK: - Initializer

    init(
        runner: ScriptRunner,
        title: String,
        showingDetailsForTesting: Bool = false,
        canCancel: Bool = true,
        hidesSiteLink: Bool = false,
        onCancel: (() -> Void)? = nil
    ) {
        self.runner = runner
        self.title = title
        self.canCancel = canCancel
        self.hidesSiteLink = hidesSiteLink
        self.onCancel = onCancel
        _isShowingDetails = State(initialValue: showingDetailsForTesting)
    }

    /// The answer being typed into the question alert.
    @State var answer: String = ""

    /// When the header last refreshed, so a stalled main thread shows up
    /// in the log as a gap rather than only as a blank window.
    ///
    /// Held in a plain class, NOT in @State: writing observed state while
    /// a body is being evaluated invalidates the view and re-evaluates
    /// the body, which spins the main thread forever.
    @State var refreshTracker: RefreshTracker = RefreshTracker()

    // MARK: - Computed properties

    /// Drives the question alert without writing state during a body.
    ///
    /// A request for a publishing credential is deliberately excluded: it
    /// gets a sheet of its own, because "Paste Netlify token:" is not a
    /// question anybody can answer without being told where tokens come
    /// from.
    var awaitingInputBinding: Binding<Bool> {
        return Binding(
            get: { runner.isAwaitingInput && runner.pendingCredentialRequest == nil },
            set: { isPresented in
                if !isPresented {
                    runner.isAwaitingInput = false
                }
            }
        )
    }

    /// Drives the credential sheet, on the same terms.
    var awaitingCredentialBinding: Binding<Bool> {
        return Binding(
            get: { runner.isAwaitingInput && runner.pendingCredentialRequest != nil },
            set: { isPresented in
                if !isPresented {
                    runner.isAwaitingInput = false
                }
            }
        )
    }

    // MARK: - Functions

    /// Records each refresh; a long gap means the interface was stalled.
    /// Also reports window geometry, because a blank window with a
    /// RESPONSIVE app means the content is being laid out somewhere
    /// other than inside the window.
    func noteRefresh(at date: Date) {
        let gap: TimeInterval = date.timeIntervalSince(refreshTracker.lastRefreshAt)
        if gap > 3 {
            AppLog.interface.error("Interface stalled for \(gap, format: .fixed(precision: 1))s (task: \(title, privacy: .public))")
        }
        refreshTracker.lastRefreshAt = date
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let _ = noteRefresh(at: context.date)
                VStack(alignment: .leading, spacing: 10) {
                    if runner.isRunning {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.headline)
                            Spacer()
                            Text(runner.milestones.isEmpty ? runner.friendlyPhase : runner.stepDescription)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("taskPhaseLabel")
                        }
                        if runner.milestones.isEmpty {
                            ProgressView()
                                .progressViewStyle(.linear)
                        } else {
                            ProgressView(value: runner.progressFraction)
                                .progressViewStyle(.linear)
                                .animation(.easeInOut(duration: 0.4), value: runner.progressFraction)
                        }

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                if !runner.milestones.isEmpty {
                                    // The TimelineView above ticks once a second,
                                    // so the "still working… (Ns)" timer counts up
                                    // even while the script itself is quiet.
                                    Text(runner.milestoneText(asOf: context.date))
                                        .foregroundStyle(.secondary)
                                        .accessibilityIdentifier("taskMilestoneLabel")
                                }

                                Button {
                                    isShowingWhyTakingLong.toggle()
                                } label: {
                                    Label("Why might this take a while?", systemImage: "questionmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $isShowingWhyTakingLong, arrowEdge: .bottom) {
                                    WhyTakingLongView()
                                }
                                .accessibilityIdentifier("whyTakingLongButton")
                            }

                            Spacer()

                            if canCancel && !runner.wasCancelled {
                                Button("Cancel") {
                                    if let onCancel {
                                        onCancel()
                                    } else {
                                        runner.cancelByUser()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("taskCancelButton")
                            }
                        }
                    } else if let exitCode = runner.lastExitCode {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.headline)
                            Spacer()
                            if runner.wasCancelled {
                                Label("Cancelled", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .accessibilityIdentifier("cancelledNotice")
                            } else if runner.wasStoppedByUser {
                                Label("Stopped", systemImage: "stop.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("stoppedNotice")
                            } else if exitCode == 0 {
                                Label("Done", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Something went wrong", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }

                        if runner.wasCancelled {
                            Text("\(title) was cancelled.")
                                .foregroundStyle(.secondary)
                        }

                        // Say what went wrong in words, so the output
                        // underneath is there to consult, not to decode.
                        if !runner.wasCancelled, !runner.wasStoppedByUser, exitCode != 0, let explanation = runner.failureExplanation {
                            Text(explanation)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("failureExplanation")
                        }

                        // Finish with something to click: the live site,
                        // or — for folder deploys — the published folder.
                        // Skipped for a multi-destination deploy, where
                        // `hidesSiteLink` is set and `DeployDestinationLinks`
                        // shows every succeeded destination's own link
                        // instead of just this one (the last) leg's.
                        if hidesSiteLink {
                            // Nothing here — see DeployDestinationLinks.
                        } else if !runner.wasCancelled, exitCode == 0, let siteURL = runner.publishedSiteURL {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your website is live.")
                                Link(siteURL.absoluteString, destination: siteURL)
                                    .accessibilityIdentifier("publishedSiteLink")
                            }
                        } else if !runner.wasCancelled, exitCode == 0, let folderURL = runner.publishedFolderURL {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your website was deployed to a folder — upload it to your web host whenever you're ready.")
                                Text("One thing to know: the pages won’t look right if you open them straight from the folder — your website only displays properly once it’s on your web host.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("publishedFolderRenderNote")
                                Button("Show in Finder", systemImage: "finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([folderURL])
                                }
                                .accessibilityIdentifier("publishedFolderButton")
                            }
                        }
                    }

                    if runner.isAwaitingInput {
                        Label("Waiting for your answer…", systemImage: "questionmark.bubble")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("awaitingInputNotice")
                    }

                    // The task is stopping itself; say so while it does.
                    if runner.wasCancelled && runner.isRunning {
                        Label("Cancelling…", systemImage: "xmark.circle")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("cancellingNotice")
                    }

                    if let problem = runner.launchProblem {
                        Text(problem)
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
            }

            Divider()

            Button {
                isShowingDetails.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isShowingDetails ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text(isShowingDetails ? "Hide details" : "Show details")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityIdentifier("taskDetailsDisclosure")

            if isShowingDetails {
                // Fill the space below the pinned header — but declare a
                // small IDEAL height. Without it, an unbounded height
                // proposal resolves to the ideal size, and a scroll
                // view's ideal size is its entire content: a long
                // transcript then demanded tens of thousands of points,
                // growing the window's content past the window itself
                // and sliding the interface out of sight.
                TaskConsoleView(runner: runner)
                    .frame(minHeight: 200, idealHeight: 260, maxHeight: .infinity)
                    .clipped()
            }
        }
        // Ask the question outright rather than making a teacher open
        // the details and type into a console.
        // Neutral wording: a task may ask several questions in a row, so
        // the title must not promise how many are coming.
        .alert("Input required", isPresented: awaitingInputBinding) {
            TextField("Your answer", text: $answer)
            Button("Send") {
                runner.send(line: answer)
                answer = ""
            }
            Button("Cancel", role: .cancel) {
                // Let the task stop the way it stops itself, so its own
                // clean-up runs.
                runner.cancelPendingQuestion()
            }
        } message: {
            Text(runner.pendingQuestion)
        }
        // A launcher asking for a Netlify or Cloudflare credential gets a
        // dialog that explains where one comes from, with the page to make
        // it on offered as a link rather than opened for them.
        .sheet(isPresented: awaitingCredentialBinding) {
            if let request = runner.pendingCredentialRequest {
                CredentialRequestSheet(
                    request: request,
                    initialAnswer: runner.suggestedAnswer,
                    onSend: { typed in
                        runner.send(line: typed)
                    },
                    onCancel: {
                        runner.cancelPendingQuestion()
                    }
                )
            }
        }
        .onChange(of: runner.isAwaitingInput) {
            // Start from the answer the task would have used anyway, so
            // agreeing is one keystroke and changing it is still easy.
            if runner.isAwaitingInput {
                answer = runner.suggestedAnswer
            }
        }
        .onChange(of: runner.lastExitCode) {
            // A failure is worth reading about: open the details.
            if let exitCode = runner.lastExitCode {
                // Only fall back to the raw output when the app has
                // nothing better to say.
                if exitCode != 0 && !runner.wasCancelled && !runner.wasStoppedByUser && runner.failureExplanation == nil {
                    isShowingDetails = true
                }
            }
        }
    }
}
