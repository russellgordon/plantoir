import SwiftUI

/// One destination's token in Plantoir ▸ Settings ▸ Deploying (#696): the
/// status line, Change Token…, Remove Token and Check Again, with the sheet
/// and the two questions they open. The words are `DeployTokenWording`.
struct DeployTokenRows: View {

    // MARK: - Stored properties

    @Bindable var panel: DeployTokenPanel

    // MARK: - Computed properties

    var service: String {
        return panel.destination.serviceName
    }

    /// The status line is orange when something needs doing.
    var statusNeedsAttention: Bool {
        guard case .answered(let answer) = panel.status else {
            return false
        }
        if answer.answer == "refused" {
            return true
        }
        if answer.answer == "accepted" {
            let reading: DeployTokenEndDate.Reading = DeployTokenEndDate.reading(
                endsOn: answer.endsOn, now: Date(), timeZone: TimeZone.current
            )
            return reading.state == .endsSoon || reading.state == .ended
        }
        return false
    }

    var isChecking: Bool {
        return panel.status == .checking
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
                StatusColour.sentence(panel.statusLine(), wornAs: statusNeedsAttention ? .warning : nil)
                    .foregroundStyle(statusNeedsAttention ? AnyShapeStyle(StatusColour.warning.style) : AnyShapeStyle(Color.primary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(panel.destination.rawValue)TokenStatus")
            }
            HStack {
                Button(DeployTokenWording.changeButton) {
                    panel.sheetProblem = nil
                    panel.isShowingChange = true
                }
                .disabled(panel.status == .noWorkingFolder)
                .accessibilityIdentifier("\(panel.destination.rawValue)ChangeTokenButton")
                Button(DeployTokenWording.removeButton) {
                    panel.isAskingToRemove = true
                }
                .disabled(!panel.hasSavedToken)
                .accessibilityIdentifier("\(panel.destination.rawValue)RemoveTokenButton")
                Spacer()
                Button(DeployTokenWording.checkAgainButton) {
                    Task { @MainActor in
                        await panel.check()
                    }
                }
                .buttonStyle(.link)
                .disabled(isChecking)
                .accessibilityIdentifier("\(panel.destination.rawValue)CheckTokenAgainButton")
            }
        }
        .sheet(isPresented: $panel.isShowingChange) {
            CredentialRequestSheet(
                request: panel.destination.credentialRequest,
                confirmTitle: DeployTokenWording.changeConfirm,
                title: DeployTokenWording.filled(DeployTokenWording.changeTitle, ["service": service]),
                problem: panel.sheetProblem,
                isBusy: panel.isSaving,
                busyMessage: DeployTokenWording.filled(DeployTokenWording.checkingNewToken, ["service": service]),
                helpAnchor: DeployTokenWording.helpAnchor,
                onSend: { pasted in
                    Task { @MainActor in
                        await panel.save(pasted: pasted)
                    }
                },
                onCancel: {
                    panel.cancelChange()
                }
            )
            .alert(
                DeployTokenWording.unreachableQuestionTitle(count: panel.unreachablePlaces.count),
                // Closed by its two buttons, each of which settles the
                // question itself. A close by any other route (Command-Period)
                // is Cancel, so the setter keeps the old token (#987).
                isPresented: Binding(
                    get: { panel.isAskingAboutUnreachable },
                    set: { (showing: Bool) in
                        if !showing && panel.isAskingAboutUnreachable {
                            panel.keepTheOldToken()
                        }
                    }
                )
            ) {
                // #987 (D2): Cancel answers Escape and Command-Period, and no
                // button is the default, because the new token would move
                // students' links. Alerts: "Note that you don't want to make
                // a Cancel button the default button"; "If you want to
                // encourage people to read an alert and not just
                // automatically press Return to dismiss it, avoid making any
                // button the default button." Use the New Token is red: the
                // teacher chose to change the token, not to break the links,
                // and Alerts asks for the destructive style on "a destructive
                // action people didn't deliberately choose". In a SwiftUI
                // alert that role is also the only way a button takes no
                // Return (`AlertKeysTests`).
                Button(DeployTokenWording.cancelButton, role: .cancel) {
                    panel.keepTheOldToken()
                }
                .keyboardShortcut(.cancelAction)
                Button(DeployTokenWording.useNewToken, role: .destructive) {
                    panel.useTheNewTokenAnyway()
                }
            } message: {
                Text(DeployTokenWording.unreachableQuestionMessage(
                    places: panel.unreachablePlaces, destination: panel.destination
                ))
            }
        }
        .alert(
            DeployTokenWording.filled(DeployTokenWording.removeTitle, ["service": service]),
            isPresented: $panel.isAskingToRemove
        ) {
            Button(DeployTokenWording.removeConfirm, role: .destructive) {
                Task { @MainActor in
                    await panel.remove()
                }
            }
            Button("Cancel", role: .cancel) {
            }
            .keyboardShortcut(.cancelAction)
        } message: {
            Text(DeployTokenWording.filled(DeployTokenWording.removeMessage, ["service": service]))
        }
    }
}
