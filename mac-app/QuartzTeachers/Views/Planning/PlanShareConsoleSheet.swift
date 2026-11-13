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
    }
}
