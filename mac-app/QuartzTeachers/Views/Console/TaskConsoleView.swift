import SwiftUI

/// Shows a running script's streamed output, with an input field so any
/// interactive prompt (for example, pasting a Netlify token on first
/// deploy) can be answered right in the app.
struct TaskConsoleView: View {

    // MARK: - Stored properties

    let runner: ScriptRunner
    /// Every leg of a multi-destination deploy, in order — when set (and
    /// there is more than one), the console shows EVERY destination's own
    /// transcript that has produced output so far, each under its own
    /// heading, instead of just `runner`'s (which is only ever the
    /// CURRENT leg). Without this, the moment a second destination
    /// started, the first destination's own console output vanished from
    /// view entirely — exactly the moment a teacher most wants to check
    /// that BOTH went out cleanly, not just the one currently running.
    /// `runner` still drives the status header, the input field, and
    /// auto-scroll — exactly one leg is ever actually running at a time.
    let allLegs: [MultiDestinationDeployRunner.Leg]?

    init(runner: ScriptRunner, allLegs: [MultiDestinationDeployRunner.Leg]? = nil) {
        self.runner = runner
        self.allLegs = allLegs
    }

    @State var pendingInput: String = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // No title here: this console only ever sits beneath the
            // progress header, which already names the task. Only the
            // precise outcome — spinner, Finished, or the exit code —
            // is added at this level.
            HStack {
                Spacer()
                if runner.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else if let exitCode = runner.lastExitCode {
                    if exitCode == 0 {
                        Label("Finished", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Failed (exit \(exitCode))", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(transcriptText)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("consoleText")
                    Color.clear
                        .frame(height: 1)
                        .id("consoleBottom")
                }
                .onChange(of: runner.transcript.lines.count) {
                    proxy.scrollTo("consoleBottom", anchor: .bottom)
                }
            }
            .background(.background.secondary)

            if let problem = runner.launchProblem {
                Text(problem)
                    .foregroundStyle(.red)
                    .padding(8)
            }

            if runner.isRunning {
                Divider()
                HStack {
                    TextField("If you’re asked a question, type your answer here…", text: $pendingInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            sendPendingInput()
                        }
                        .accessibilityIdentifier("consoleInputField")
                    Button("Send") {
                        sendPendingInput()
                    }
                    Button("Stop", role: .destructive) {
                        runner.terminate()
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Computed properties

    var transcriptText: String {
        return TaskConsoleView.combinedTranscriptText(runner: runner, allLegs: allLegs)
    }

    /// Every leg that has produced any output yet, under its own heading,
    /// in deploy order — a leg the run has not reached at all is left out
    /// rather than shown as an empty, confusing section. Falls back to
    /// just `runner`'s own transcript whenever there is nothing to
    /// combine (a single destination, or a preview, where `allLegs` is
    /// `nil` or has only one entry), so that case looks byte-for-byte as
    /// it always has.
    static func combinedTranscriptText(runner: ScriptRunner, allLegs: [MultiDestinationDeployRunner.Leg]?) -> String {
        guard let allLegs, allLegs.count > 1 else {
            let text: String = runner.transcript.displayText
            return text.isEmpty ? "Starting…" : text
        }
        var sections: [String] = []
        for leg in allLegs where !leg.runner.transcript.lines.isEmpty {
            let heading: String = "── \(DeployCommand.destinationDescription(for: leg.destination)) ──"
            sections.append(heading + "\n" + leg.runner.transcript.displayText)
        }
        if sections.isEmpty {
            return "Starting…"
        }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Functions

    func sendPendingInput() {
        runner.send(line: pendingInput)
        pendingInput = ""
    }
}
