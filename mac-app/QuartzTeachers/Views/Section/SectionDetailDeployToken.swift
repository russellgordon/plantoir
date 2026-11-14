import SwiftUI

/// The Cloudflare token's end-date warning on a section's Deploy screen
/// (#696). Shown only when the course deploys to Cloudflare Pages and the
/// end date Plantoir last read is under 30 days away or past.
extension SectionDetailView {

    // MARK: - Computed properties

    /// Whether any of the course's destinations is Cloudflare Pages.
    var deploysToCloudflare: Bool {
        for destination in course.configuration.allDeployDestinations {
            if destination.type == "cloudflare_pages" {
                return true
            }
        }
        return false
    }

    /// The warning's sentence, or nil when there is nothing to warn about.
    var deployTokenEndWarning: String? {
        if !deploysToCloudflare {
            return nil
        }
        return DeployTokenWording.deployScreenWarning(
            rememberedEndsOn: AppSettings.shared.cloudflareTokenEndsOn,
            now: Date(),
            timeZone: TimeZone.current
        )
    }

    /// The notice, when there is one.
    @ViewBuilder
    var deployTokenEndNotice: some View {
        if let sentence = deployTokenEndWarning {
            DeployTokenEndNoticeView(sentence: sentence) {
                SettingsPane.select(.deploying)
                openSettings()
            }
        }
    }
}
