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

    /// What to do with the finished answer, and with a change of mind.
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State var answer: String = ""

    // MARK: - Computed properties

    /// Whitespace either side of a pasted code is invisible and breaks the
    /// sign-in, so it never reaches the launcher.
    var tidiedAnswer: String {
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.title)
                .font(.title2.bold())

            Text(request.explanation)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

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

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    sendAnswer()
                }
                .defaultButton(isEnabled: !tidiedAnswer.isEmpty)
                .accessibilityIdentifier("credentialSendButton")
            }
        }
        .padding(20)
        .frame(width: 460)
        // A CONTAINER element with its own identifier (#353). Without
        // `.contain` SwiftUI applies an identifier on a stack to every element
        // inside it, so `credentialField` and `credentialSendButton` were
        // read off the real tree as "credentialSheet" and could not be found.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("credentialSheet")
        .onAppear {
            answer = initialAnswer
        }
    }

    // MARK: - Functions

    func sendAnswer() {
        if tidiedAnswer.isEmpty {
            return
        }
        onSend(tidiedAnswer)
        answer = ""
    }
}
