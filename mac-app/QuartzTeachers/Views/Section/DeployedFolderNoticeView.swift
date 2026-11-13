import SwiftUI

/// The line in a section's window while its deployed folder is open in the
/// web browser (#850), with Stop: Russell's ruling of 2026-11-13 put Stop
/// here and in the Section menu. When the folder went away while it was
/// shown, the same line says so instead, with a button to dismiss it.
///
/// Its own view with nothing read from the environment, and no `fixedSize`
/// on the sentence, for the reason `UnsavedSettingsNoticeView` gives: a split
/// view measures a column by proposing next to no width, and a rigid text
/// would claim its height at a character per line.
struct DeployedFolderNoticeView: View {

    // MARK: - Stored properties

    /// The sentence: `DeployedFolderWording.notice(section:)`, or
    /// `stoppedFolderGone`.
    let sentence: String

    /// True while it is shown (the button stops it); false when the line
    /// says the folder went away (the button dismisses the line).
    let isShowing: Bool

    let press: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: isShowing ? "safari" : "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(sentence)
                    .font(.callout)
                    .accessibilityIdentifier(isShowing ? "deployedFolderNotice" : "deployedFolderGoneNotice")
                Spacer()
                if isShowing {
                    Button(DeployedFolderWording.stopButton) {
                        press()
                    }
                    .accessibilityHint(DeployedFolderWording.stopHint)
                    .accessibilityIdentifier("deployedFolderStopButton")
                } else {
                    Button(DeployedFolderWording.dismissButton) {
                        press()
                    }
                    .accessibilityIdentifier("deployedFolderGoneDismissButton")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
        }
    }
}
