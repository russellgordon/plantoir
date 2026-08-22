import AppKit
import SwiftUI

/// Every configured destination's own live link (or published folder),
/// shown once a multi-destination deploy has finished.
///
/// Rendered INSIDE `TaskProgressView`, in the exact spot a single
/// destination's own "Your website is live." section would sit — above
/// "Show details", never pushed down past the (variable-height) console.
/// `TaskProgressView` itself is bound to `activeRunner` — whichever leg ran
/// LAST — so its OWN link section only ever names one destination; a
/// teacher who deployed to Netlify AND Cloudflare needs to see BOTH
/// addresses, not just whichever host happened to run last. That was the
/// actual bug reported ("only Cloudflare, the second deploy target, is
/// visible").
///
/// Only appears once a course has more than one destination — a course with
/// exactly one (the overwhelming majority) never sees this, and
/// `TaskProgressView`'s own single-link section already says everything
/// there is to say for it.
struct DeployDestinationLinks: View {

    // MARK: - Stored properties

    let legs: [MultiDestinationDeployRunner.Leg]

    // MARK: - Body

    var body: some View {
        let succeededLegs: [MultiDestinationDeployRunner.Leg] = DeployDestinationLinks.succeeded(from: legs)
        if !succeededLegs.isEmpty {
            // Centred as a GROUP within the window — each leg's own caption
            // and link stay left-aligned to each other, but the block of
            // destinations as a whole sits centred, which is what reads
            // right sitting directly above "Show details" rather than
            // pinned to one side of a wide window.
            VStack(spacing: 10) {
                ForEach(succeededLegs) { leg in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DeployCommand.destinationDescription(for: leg.destination))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let siteURL = leg.runner.publishedSiteURL {
                            Link(siteURL.absoluteString, destination: siteURL)
                                .accessibilityIdentifier("publishedSiteLink-\(leg.destination.type)")
                        } else if let folderURL = leg.runner.publishedFolderURL {
                            Button("Show in Finder", systemImage: "finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
                            }
                            .accessibilityIdentifier("publishedFolderButton-\(leg.destination.type)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Functions

    /// Only a leg that actually finished AND succeeded gets a link — a leg
    /// the run never reached (stopped early by a cancel, or a failed
    /// shared build) has no `ScriptRunner` output to show, and a leg that
    /// failed has no site to link to.
    static func succeeded(from legs: [MultiDestinationDeployRunner.Leg]) -> [MultiDestinationDeployRunner.Leg] {
        var result: [MultiDestinationDeployRunner.Leg] = []
        for leg in legs where leg.isFinished && leg.succeeded {
            result.append(leg)
        }
        return result
    }
}
