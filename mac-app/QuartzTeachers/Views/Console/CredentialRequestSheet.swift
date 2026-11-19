import SwiftUI

/// Asks for a publishing credential the way a person would explain it:
/// what it is for, where to get it, and a field to paste it into.
///
/// It replaces a one-line alert that said "Paste Netlify token:" and
/// nothing else. The page that makes the token is offered as a LINK the
/// teacher clicks when they are ready — the launchers used to open it
/// themselves, and a browser tab appearing unasked reads as a fault.
struct CredentialRequestSheet: View {

    // MARK: - Stored properties

    let request: CredentialRequest

    /// What the field starts with. Empty for a secret — a token is never
    /// shown back — but the Account ID field is opened from a form that may
    /// already hold one, and clearing it on the way in would look like the
    /// dialog had thrown it away.
    var initialAnswer: String = ""

    /// What the button that accepts the answer says. "Continue" while a
    /// publish is waiting on it; something calmer when a teacher opened
    /// these instructions themselves and nothing is paused.
    var confirmTitle: String = "Continue"

    /// The title, when it is not the request's own: Settings ▸ Deploying's
    /// Change Token… says "Change the Netlify Token" rather than "Connect to
    /// Netlify" (#696).
    var title: String? = nil

    /// What is wrong with the last answer, said under the field: Settings'
    /// Change Token… keeps the sheet open with the reason when a new token
    /// was not saved (#696). Nil during a deploy, which says it in the
    /// console instead.
    var problem: String? = nil

    /// True while the answer is being checked: the buttons wait and
    /// `busyMessage` says what is happening (#696).
    var isBusy: Bool = false
    var busyMessage: String = ""

    /// The Help page a Help button at the foot of the sheet opens, or nil
    /// for none (#696, the plan's #839 P5 button on the settings sheet).
    var helpAnchor: String? = nil

    /// What to do with the finished answer, and with a change of mind.
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State var answer: String = ""

    // MARK: - Computed properties

    /// Whitespace either side of a pasted code is invisible and breaks the
    /// sign-in, so it never reaches the launcher.
    var tidiedAnswer: String {
        return CredentialRequestSheet.answerToSend(answer, for: request)
    }

    /// What is sent for an answer. A unit plan's password is sent exactly as
    /// typed, spaces at either end included, as the command line keeps it
    /// (#709); everything else is a code whose surrounding spaces are noise.
    static func answerToSend(_ typed: String, for request: CredentialRequest) -> String {
        if request.name == CredentialRequest.unitPlanPassword.name {
            return typed
        }
        return typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !request.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(request.steps.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(pair.offset + 1).")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(pair.element)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let linkAddress = request.linkAddress, !request.linkTitle.isEmpty {
                Link(destination: linkAddress) {
                    Label(request.linkTitle, systemImage: "safari")
                }
                .accessibilityIdentifier("credentialLink")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(request.fieldLabel)
                    .font(.callout)
                // The label above the field says what it is; the field's
                // own placeholder says what to do, rather than repeating
                // the label back.
                if request.isSecret {
                    SecureField(request.fieldPlaceholder, text: $answer)
                        .borderedTextField()
                        .labelsHidden()
                        .accessibilityIdentifier("credentialField")
                        .onSubmit {
                            sendAnswer()
                        }
                } else {
                    TextField(request.fieldPlaceholder, text: $answer)
                        .borderedTextField()
                        .labelsHidden()
                        .accessibilityIdentifier("credentialField")
                        .onSubmit {
                            sendAnswer()
                        }
                }
            }

            if isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(busyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("credentialBusy")
            } else if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("credentialProblem")
            }

            HStack {
                if let helpAnchor {
                    HelpLink {
                        PlantoirHelpPage.open(anchor: helpAnchor)
                    }
                    .accessibilityIdentifier("credentialHelpButton")
                }
                Spacer()
                // Waits while the answer is being checked (#696, review W2):
                // Settings' check may already have saved the token by the
                // time Cancel is pressed, and closing the sheet then would
                // hide a save that landed.
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isBusy)
                Button(confirmTitle) {
                    sendAnswer()
                }
                .defaultButton(isEnabled: !tidiedAnswer.isEmpty && !isBusy)
                .accessibilityIdentifier("credentialSendButton")
            }
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle(title ?? request.title, explanation: {
            Text(request.explanation)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        })
        .frame(width: 460)
        // A CONTAINER element with its own identifier (#353). Without
        // `.contain` SwiftUI applies an identifier on a stack to every element
        // inside it, so `credentialField` and `credentialSendButton` were
        // read off the real tree as "credentialSheet" and could not be found.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("credentialSheet")
        .interactiveDismissDisabled(isBusy)
        .onAppear {
            answer = initialAnswer
        }
    }

    // MARK: - Functions

    func sendAnswer() {
        if tidiedAnswer.isEmpty || isBusy {
            return
        }
        onSend(tidiedAnswer)
        answer = ""
    }
}
