import SwiftUI

/// The open share's question (#709): before unit plans go out with no
/// password, every file that will be shared and every file left out, in
/// full, and a choice. The ONLY place that question is answered in the app
/// (fix review H1): the plain question alert showed the [y/N] line alone,
/// with the lists out of sight behind Show Details.
///
/// The lists are what the launcher printed as its marker lines
/// (`PlanShareLists`), never re-read from disk, so the teacher answers about
/// exactly what the share holds. Cancel is the default: a share that goes
/// out by a stray Return is the one that cannot be taken back.
struct PlanShareListsSheet: View {

    // MARK: - Stored properties

    let lists: PlanShareLists

    let onShare: () -> Void
    let onCancel: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    list(PlanSharingWording.listsSharedHeading, lists.shared, identifier: "planShareListShared")
                    list(PlanSharingWording.listsLeftOutHeading, lists.leftOut, identifier: "planShareListLeftOut")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200, maxHeight: 420)
            HStack {
                Spacer()
                Button(PlanSharingWording.listsShareButton) {
                    onShare()
                }
                .accessibilityIdentifier("planShareListsShare")
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("planShareListsCancel")
            }
        }
        .padding([.horizontal, .bottom], 20)
        // The by-name sentence under the title, read before either list.
        .sheetTitle(PlanSharingWording.listsSheetTitle, explanation: {
            Text(PlanSharingWording.listsByName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        })
        .frame(width: 560)
        .interactiveDismissDisabled()
    }

    // MARK: - Functions

    func list(_ heading: String, _ names: [String], identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading)
                .font(.subheadline.weight(.semibold))
            if names.isEmpty {
                Text(PlanSharingWording.listsNone)
                    .foregroundStyle(.secondary)
            }
            ForEach(names, id: \.self) { (name: String) in
                Text(name)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}
