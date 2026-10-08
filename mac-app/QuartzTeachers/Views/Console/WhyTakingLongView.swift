import SwiftUI

/// Explains in plain, jargon-free language why building a preview or
/// deploying a site can take longer than usual (such as on a first run).
struct WhyTakingLongView: View {

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Why might this take a while?")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                ExplanationRow(
                    title: "First-time setup",
                    description: "Getting everything ready for the first time takes a couple of minutes to set up your website builder. Future previews and deploys will be much faster (usually just a few seconds)."
                )

                ExplanationRow(
                    title: "First-time deploying",
                    description: "Uploading your entire website for the first time takes a bit longer. Future deploys only upload the pages you’ve changed."
                )

                ExplanationRow(
                    title: "Photos and attachments",
                    description: "Courses with many images, documents, or media files take extra time to prepare and upload."
                )

                ExplanationRow(
                    title: "Internet connection",
                    description: "When deploying online, upload speed depends on your current internet connection."
                )
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// A single titled explanation block inside the popover.
private struct ExplanationRow: View {

    // MARK: - Stored properties

    let title: String
    let description: String

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .bold()
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
