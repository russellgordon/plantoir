import SwiftUI

/// The share's console (#709), as a section's deploy shows it, titled the
/// one way every sheet is (`SheetTitle`), with Done once the launcher has
/// finished: grey, and not the default, while it cannot be pressed.
struct PlanShareConsoleSheet: View {

    // MARK: - Stored properties

    let planRunner: PlanShareRunner

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TaskProgressView(
                runner: planRunner.runner,
                title: planRunner.title,
                // Stopping a share asks "Stop this share?" first, as a deploy
                // asks (Russell, 2026-11-19, on #988), and its Cancel holds
                // Escape and Command-Period as the deploy's does. With the
                // question turned off, they stop the share at once.
                stopQuestion: .share,
                hidesSiteLink: true,
                onCancel: {
                    planRunner.cancel()
                }
            )
            HStack {
                Spacer()
                Button("Done") {
                    planRunner.isShowingSheet = false
                }
                .defaultButton(isEnabled: !planRunner.runner.isRunning)
                .accessibilityIdentifier("planShareDone")
            }
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle(PlanSharingWording.consoleSheetTitle)
        .frame(minWidth: 520, minHeight: 320)
        // After Change Password (#833): the teacher must answer.
        .factsQuestionSheet(isPresented: Binding(
            get: { planRunner.isAskingAboutNewPassword },
            set: { (showing: Bool) in
                if !showing {
                    planRunner.isAskingAboutNewPassword = false
                }
            }
        )) {
            FactsQuestionSheet(
                question: PlanSharing.newPasswordQuestion(earlierYearShared: planRunner.earlierYearShared),
                identifier: "planShareNewPassword",
                goAheadIsTheDefault: true,
                goAhead: {
                    planRunner.shareAgain()
                },
                cancel: {
                    planRunner.isAskingAboutNewPassword = false
                }
            )
        }
    }
}
