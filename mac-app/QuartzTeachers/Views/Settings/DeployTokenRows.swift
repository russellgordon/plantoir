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
                Text(panel.statusLine())
                    .foregroundStyle(statusNeedsAttention ? Color.orange : Color.primary)
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
                // Closed only by its two buttons, each of which settles the
                // question itself, so the setter has nothing to do. Return is
                // the first button: `.cancel` with `.defaultAction` on one
                // button gives it Return and gives Escape to nothing, as
                // QuestionKeysTests records from #832, and Return is the
                // answer that changes nothing.
                isPresented: Binding(
                    get: { panel.isAskingAboutUnreachable },
                    set: { _ in }
                )
            ) {
                Button(panel.keepButtonTitle, role: .cancel) {
                    panel.keepTheOldToken()
                }
                .keyboardShortcut(.defaultAction)
                Button(DeployTokenWording.useNewToken) {
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
        } message: {
            Text(DeployTokenWording.filled(DeployTokenWording.removeMessage, ["service": service]))
        }
    }
}
