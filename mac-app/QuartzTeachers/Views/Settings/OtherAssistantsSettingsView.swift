import SwiftUI

/// Plantoir ▸ Settings ▸ Other Assistants (#855): GitHub Copilot, Claude Code
/// and Codex, each with what is true of it now and the one next step.
///
/// The pane's first line says Plantoir works without any of them (the
/// never-requires rule, 2026-11-12), and nothing here starts unasked: Set
/// Up… opens a confirmation that says what will be downloaded, from whom,
/// and where the course content goes, and only its Download and Set Up runs
/// anything. Every sentence is `AssistantSetUpWording`'s.
struct OtherAssistantsSettingsView: View {

    // MARK: - Stored properties

    var centre: AssistantSetUpCentre = AssistantSetUpCentre.shared

    /// The assistant whose confirmation is open.
    @State private var confirming: AssistantSetUpChoice?

    /// The assistant whose Remove question is open.
    @State private var removing: AssistantSetUpChoice?

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                Text(AssistantSetUpWording.paneIntro)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(AssistantSetUp.agents, id: \.key) { (agent: AssistantSetUpAgent) in
                Section(agent.displayName) {
                    row(for: agent)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            AssistantSetUpCentre.noteOpened(from: AssistantSetUpCentre.pendingOpenedFrom ?? .settings)
            AssistantSetUpCentre.pendingOpenedFrom = nil
            centre.refresh()
        }
        .sheet(item: $confirming) { (choice: AssistantSetUpChoice) in
            AssistantSetUpSheet(
                agent: choice.agent,
                setUp: {
                    confirming = nil
                    centre.setUp(choice.agent)
                },
                cancel: {
                    confirming = nil
                }
            )
        }
        .alert(
            removeTitle,
            isPresented: removeIsShown,
            presenting: removing
        ) { (choice: AssistantSetUpChoice) in
            Button(AssistantSetUpWording.removeConfirmButton, role: .destructive) {
                centre.remove(choice.agent)
            }
            Button(AssistantSetUpWording.cancelButton, role: .cancel) {
            }
        } message: { (choice: AssistantSetUpChoice) in
            Text(AssistantSetUpWording.filled(AssistantSetUpWording.removeBody, for: choice.agent))
        }
        // `.contain` BEFORE the identifier (#353).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("otherAssistantsSettings")
    }

    // MARK: - Computed properties

    private var removeTitle: String {
        guard let removing else {
            return ""
        }
        return AssistantSetUpWording.filled(AssistantSetUpWording.removeTitle, for: removing.agent)
    }

    private var removeIsShown: Binding<Bool> {
        return Binding(
            get: { return removing != nil },
            set: { (shown: Bool) in
                if !shown {
                    removing = nil
                }
            }
        )
    }

    // MARK: - Functions

    /// One assistant's sentence and buttons.
    @ViewBuilder
    func row(for agent: AssistantSetUpAgent) -> some View {
        let state: AssistantSetUpState = centre.state(of: agent)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if state == .downloading || state == .checking {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(centre.line(for: agent))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("otherAssistantLine-\(agent.key)")
            }
            if AssistantSetUpState.offersSetUp(state), let waiting = centre.waitingLine(for: agent) {
                Text(waiting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("otherAssistantWaiting-\(agent.key)")
            }
            HStack(spacing: 8) {
                buttons(for: agent, in: state)
            }
        }
        .padding(.vertical, 2)
    }

    /// The buttons a state offers, the next step first.
    @ViewBuilder
    func buttons(for agent: AssistantSetUpAgent, in state: AssistantSetUpState) -> some View {
        switch state {
        case .notSetUp:
            Button(AssistantSetUpWording.setUpButton) {
                confirming = AssistantSetUpChoice(agent: agent)
            }
            .disabled(!centre.canStartSetUp(agent))
            .accessibilityIdentifier("otherAssistantSetUp-\(agent.key)")
        case .failedNoConnection, .failedNotFromMaker, .failedOther, .failedTookTooLong, .stopped, .interrupted:
            Button(AssistantSetUpWording.tryAgainButton) {
                confirming = AssistantSetUpChoice(agent: agent)
            }
            .disabled(!centre.canStartSetUp(agent))
            .accessibilityIdentifier("otherAssistantTryAgain-\(agent.key)")
            Button(AssistantSetUpWording.showMeHowButton) {
                PlantoirHelpPage.open(anchor: AssistantSetUp.helpAnchor)
            }
        case .downloading, .checking:
            Button(AssistantSetUpWording.stopButton) {
                centre.stop(agent)
            }
            .accessibilityIdentifier("otherAssistantStop-\(agent.key)")
        case .installedSignedOut:
            Button(AssistantSetUpWording.signInButton) {
                centre.signIn(agent)
            }
            Button(AssistantSetUpWording.checkAgainButton) {
                centre.checkAgain(agent)
            }
            removeButton(for: agent)
        case .signingIn:
            Button(AssistantSetUpWording.checkAgainButton) {
                centre.checkAgain(agent)
            }
            Button(AssistantSetUpWording.signInAgainButton) {
                centre.signIn(agent)
            }
            removeButton(for: agent)
        case .signInNotConfirmed:
            Button(AssistantSetUpWording.signInAgainButton) {
                centre.signIn(agent)
            }
            Button(AssistantSetUpWording.checkAgainButton) {
                centre.checkAgain(agent)
            }
            removeButton(for: agent)
        case .readySignedIn, .readySignInFinished:
            removeButton(for: agent)
        case .setUpElsewhere:
            EmptyView()
        case .recordUnreadable:
            Button(AssistantSetUpWording.showMeHowButton) {
                PlantoirHelpPage.open(anchor: AssistantSetUp.helpAnchor)
            }
        }
    }

    @ViewBuilder
    func removeButton(for agent: AssistantSetUpAgent) -> some View {
        if centre.canRemove(agent) {
            Button(AssistantSetUpWording.removeButton) {
                removing = AssistantSetUpChoice(agent: agent)
            }
            .accessibilityIdentifier("otherAssistantRemove-\(agent.key)")
        }
    }
}

/// One assistant chosen for a sheet or a question.
struct AssistantSetUpChoice: Identifiable {

    // MARK: - Stored properties

    let agent: AssistantSetUpAgent

    // MARK: - Computed properties

    var id: String {
        return agent.key
    }
}

/// The confirmation before anything is downloaded (#855): what Plantoir
/// downloads, from whom, where it goes, that it is checked once it is in
/// place, and where the course content goes; a link to the maker's page on
/// which accounts include it; and, for GitHub Copilot, Help's page on
/// GitHub's education benefits (Russell, 2026-11-13). Cancel is the default
/// answer: going ahead runs another company's program.
struct AssistantSetUpSheet: View {

    // MARK: - Stored properties

    let agent: AssistantSetUpAgent
    let setUp: () -> Void
    let cancel: () -> Void

    static let width: CGFloat = 460

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(
                AssistantSetUpWording.filled(AssistantSetUpWording.confirmPlansLink, for: agent),
                destination: agent.plansPage
            )
            .accessibilityIdentifier("assistantSetUpPlansLink")
            if let anchor = agent.educationHelpAnchor {
                Text(AssistantSetUpWording.confirmEducation)
                    .fixedSize(horizontal: false, vertical: true)
                Button(AssistantSetUpWording.confirmEducationLink) {
                    PlantoirHelpPage.open(anchor: anchor)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("assistantSetUpEducationLink")
            }
            HStack {
                Spacer()
                Button(AssistantSetUpWording.confirmButton) {
                    setUp()
                }
                .accessibilityIdentifier("assistantSetUpGoAhead")
                Button(AssistantSetUpWording.cancelButton, role: .cancel) {
                    cancel()
                }
                .defaultButton(isEnabled: true)
                .accessibilityIdentifier("assistantSetUpCancel")
            }
            .padding(.top, 8)
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle(
            AssistantSetUpWording.filled(AssistantSetUpWording.confirmTitle, for: agent),
            identifier: "assistantSetUpTitle",
            explanation: {
                Text(AssistantSetUpWording.filled(AssistantSetUpWording.confirmBody, for: agent))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("assistantSetUpMessage")
            }
        )
        .frame(width: AssistantSetUpSheet.width)
        .onExitCommand {
            cancel()
        }
    }
}
