import AppKit
import SwiftUI

/// The About panel: the app icon beside the name, version, what the app
/// is, support details, credits, and copyright — replacing the stock
/// About box.
///
/// Every size below is a `@ScaledMetric`, so the whole panel — artwork,
/// type, and width together — grows with the system's Accessibility ▸
/// Display ▸ Text size, instead of leaving someone who enlarges text
/// with the same small panel they had before.
struct AboutView: View {

    // MARK: - Stored properties

    /// Where teachers go to learn more about the app. Set to nil to omit
    /// the row — it and its spacing disappear together.
    let websiteURL: URL? = URL(string: "https://plantoir.app")

    /// Where teachers write in for help. Set to nil to omit the row —
    /// it and its spacing disappear together.
    let supportEmailAddress: String? = "support@plantoir.app"

    /// Shown at the very bottom. Set to nil to omit the line.
    let copyrightNotice: String? = "Copyright 2026 Russell Gordon"

    /// What the app is, in one line.
    let tagline: String = "Turns a folder of Markdown notes into a fast, searchable class website."

    /// Where the name comes from — and what the app promises to do.
    let namesake: String = "A plantoir is a dibber — the simple hand tool that opens a hole at the right depth so a seedling can be set in and take root. This app does the same for teaching materials. Write in Obsidian, preview locally, deploy when you’re ready."

    /// The case for Jacky, in a callout — arranged as plantoir.app's
    /// footer arranges it. No separate "Built on Quartz" credit line:
    /// this already says whose work the app stands on.
    ///
    /// Plain words, no inline links (#993, D46): SwiftUI hands an inline
    /// Markdown link in a `Text` to VoiceOver as a disabled link that Tab
    /// cannot reach. The two places the sentence points to are separate
    /// `Link` views beneath it (`sponsorLinks`), as Russell ruled
    /// (option A of `vm-tools/reference/993-about-window-design.md`).
    let sponsorMessage: LocalizedStringKey = "Plantoir is a friendly wrapper around Quartz, which Jacky Zhao builds and gives away for free. If you end up using Plantoir regularly, please consider sponsoring him on GitHub — it is his work that makes all of this possible."

    /// The two links beneath the sponsor sentence. The second starts with
    /// a verb, as the HIG's Writing page asks of a link's label.
    let quartzLinkTitle: String = "Quartz"
    let quartzURL: URL? = URL(string: "https://quartz.jzhao.xyz")
    let sponsorLinkTitle: String = "Sponsor Jacky Zhao on GitHub"
    let sponsorURL: URL? = URL(string: "https://github.com/sponsors/jackyzha0")

    /// The credits beneath the callout, as label-and-value rows in the
    /// shape of the Website and Email rows.
    let iconCreditLabel: String = "Icon"
    let iconCreditName: String = "Phosphor Icons"
    let iconCreditURL: URL? = URL(string: "https://phosphoricons.com")
    let iconCreditLicence: String = "(MIT)"
    let designCreditLabel: String = "Design"
    let designCreditName: String = "Russell Gordon"
    let designCreditURL: URL? = URL(string: "https://www.russellgordon.ca")
    let madeWithLabel: String = "Made with"
    let madeWithName: String = "Claude"

    // The measurements, at the SYSTEM text size. Scaling from these keeps
    // the panel's proportions as the text grows.
    @ScaledMetric(relativeTo: .body) var iconSize: CGFloat = 128
    @ScaledMetric(relativeTo: .body) var nameSize: CGFloat = 26
    @ScaledMetric(relativeTo: .body) var versionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) var bodySize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) var creditsSize: CGFloat = 11
    @ScaledMetric(relativeTo: .body) var panelWidth: CGFloat = 540
    @ScaledMetric(relativeTo: .body) var outerPadding: CGFloat = 24
    @ScaledMetric(relativeTo: .body) var columnSpacing: CGFloat = 24

    // MARK: - Computed properties

    /// The application name, read from the bundle so it follows a rename.
    var applicationName: String {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return displayName ?? bundleName ?? "Plantoir"
    }

    /// Marketing version and build number, formatted as "Version 1.0 (1)".
    ///
    /// Info.plist must reference `$(MARKETING_VERSION)` and
    /// `$(CURRENT_PROJECT_VERSION)` rather than hardcoded literals, or this
    /// will not update when the build settings change.
    var versionSummary: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(shortVersion) (\(buildNumber))"
    }

    /// A mailto link built from the support address, when there is one.
    var supportEmailURL: URL? {
        guard let supportEmailAddress else {
            return nil
        }
        return URL(string: "mailto:\(supportEmailAddress)")
    }

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {

            icon

            VStack(alignment: .leading, spacing: 0) {

                Text(applicationName)
                    .font(.system(size: nameSize, weight: .bold))

                Text(versionSummary)
                    .font(.system(size: versionSize))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Text(tagline)
                    .font(.system(size: bodySize))
                    .padding(.top, 14)

                Text(namesake)
                    .font(.system(size: bodySize))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                contactDetails
                    .padding(.top, 18)

                sponsorCallout
                    .padding(.top, 18)

                creditLines
                    .padding(.top, 14)

                if let copyrightNotice {
                    Text(copyrightNotice)
                        .font(.system(size: creditsSize))
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(outerPadding)
        .frame(width: panelWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        // Without this, the window opens with a focus ring around the
        // support link — the panel has nothing else to focus. The links
        // still work; they just stop being haloed on arrival.
        .focusEffectDisabled()
    }

    /// The application icon itself — the compiled artwork macOS shows in
    /// the Dock, so the About panel can never drift from the real icon and
    /// no separate flattened asset is needed. It arrives already shaped
    /// with its margins, so no clipping is applied here.
    var icon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: iconSize, height: iconSize)
            .accessibilityLabel("\(applicationName) icon")
    }

    /// Label and value rows for website and support details, the values left-aligned
    /// to a common edge.
    var contactDetails: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            if let websiteURL {
                GridRow {
                    Text("Website")
                        .font(.system(size: bodySize))
                        .foregroundStyle(.secondary)
                    Link(destination: websiteURL) {
                        Text(websiteURL.absoluteString)
                            .font(.system(size: bodySize, weight: .semibold))
                    }
                    .accessibilityIdentifier("aboutWebsiteLink")
                }
            }

            if let supportEmailAddress, let supportEmailURL {
                GridRow {
                    Text("Email")
                        .font(.system(size: bodySize))
                        .foregroundStyle(.secondary)
                    Link(destination: supportEmailURL) {
                        Text(supportEmailAddress)
                            .font(.system(size: bodySize, weight: .semibold))
                    }
                    .accessibilityIdentifier("aboutEmailLink")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    /// The sponsor message in a rounded-rect callout, matching the
    /// Windows About panel and plantoir.app's footer: the sentence whole,
    /// then its two links on one line beneath it.
    var sponsorCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sponsorMessage)
                .font(.system(size: bodySize))
                .fixedSize(horizontal: false, vertical: true)

            sponsorLinks
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .tint(.accentColor)
    }

    /// Quartz and the sponsor page, each a `Link` of its own, so VoiceOver
    /// reads each as an enabled link with its own words and lists it in
    /// the rotor's Links, and Tab reaches it with Keyboard Navigation on.
    var sponsorLinks: some View {
        HStack(spacing: 16) {
            if let quartzURL {
                Link(quartzLinkTitle, destination: quartzURL)
                    .accessibilityIdentifier("aboutQuartzLink")
            }
            if let sponsorURL {
                Link(sponsorLinkTitle, destination: sponsorURL)
                    .accessibilityIdentifier("aboutSponsorLink")
            }
        }
        .font(.system(size: bodySize, weight: .semibold))
    }

    /// Who and what the app is built on: a label and its value on each
    /// row, the values left-aligned to a common edge, as the Website and
    /// Email rows are.
    var creditLines: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 3) {
            GridRow {
                Text(iconCreditLabel)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if let iconCreditURL {
                        Link(iconCreditName, destination: iconCreditURL)
                            .accessibilityIdentifier("aboutIconCreditLink")
                    } else {
                        Text(iconCreditName)
                            .foregroundStyle(.secondary)
                    }
                    Text(iconCreditLicence)
                        .foregroundStyle(.secondary)
                }
            }

            GridRow {
                Text(designCreditLabel)
                    .foregroundStyle(.secondary)
                if let designCreditURL {
                    Link(designCreditName, destination: designCreditURL)
                        .accessibilityIdentifier("aboutDesignCreditLink")
                } else {
                    Text(designCreditName)
                        .foregroundStyle(.secondary)
                }
            }

            GridRow {
                Text(madeWithLabel)
                    .foregroundStyle(.secondary)
                Text(madeWithName)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: creditsSize))
        .tint(.accentColor)
    }
}

// MARK: - Preview

#Preview {
    AboutView()
}
