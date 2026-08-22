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
            // Leading-aligned, matching every other line in this panel
            // (the title, the Done/Failed status, DeployDestinationChecklist
            // above it) — a teacher's eye already knows where that edge is;
            // centring only this one block read as visually disconnected
            // from everything around it.
            VStack(alignment: .leading, spacing: 10) {
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
