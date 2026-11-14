import SwiftUI

/// The Cloudflare token's end-date warning on a section's Deploy screen
/// (#696). Shown only when the course deploys to Cloudflare Pages and the
/// end date Plantoir last read is under 30 days away or past.
extension SectionDetailView {

    // MARK: - Computed properties

    /// The warning's sentence, or nil when there is nothing to warn about.
    var deployTokenEndWarning: String? {
        return SectionDetailView.deployTokenEndWarning(
            destinations: course.configuration.allDeployDestinations,
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

    // MARK: - Functions

    /// Whether any of a course's destinations is Cloudflare Pages.
    static func deploysToCloudflare(_ destinations: [CourseConfiguration.DeployDestination]) -> Bool {
        for destination in destinations {
            if destination.type == "cloudflare_pages" {
                return true
            }
        }
        return false
    }

    /// The warning for a course with these destinations: only when one of
    /// them is Cloudflare Pages, and only when the remembered end date is
    /// under 30 days away or past.
    static func deployTokenEndWarning(
        destinations: [CourseConfiguration.DeployDestination],
        rememberedEndsOn: String,
        now: Date,
        timeZone: TimeZone
    ) -> String? {
        if !deploysToCloudflare(destinations) {
            return nil
        }
        return DeployTokenWording.deployScreenWarning(
            rememberedEndsOn: rememberedEndsOn, now: now, timeZone: timeZone
        )
    }
}
