import SwiftUI

/// The line above a section's site that says the Cloudflare token ends in
/// under 30 days, or has ended, with Open Settings… (#696, the first ruling:
/// the course's Deploy screen says so too).
///
/// Drawn from the end date the last check or deploy read and the app keeps
/// (`AppSettings.cloudflareTokenEndsOn`), never from a request made when the
/// screen opens (review MUST 2). No `fixedSize` on the sentence, for the
/// reason `UnsavedSettingsNoticeView` gives.
struct DeployTokenEndNoticeView: View {

    // MARK: - Stored properties

    /// `DeployTokenWording.deployScreenEndsSoon` or `.deployScreenEnded`.
    let sentence: String

    /// Opens Plantoir ▸ Settings ▸ Deploying.
    let openSettings: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(sentence)
                    .font(.callout)
                Spacer()
                Button(DeployTokenWording.openSettingsButton) {
                    openSettings()
                }
                .accessibilityIdentifier("deployTokenEndOpenSettings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("deployTokenEndNotice")
            Divider()
        }
    }
}
