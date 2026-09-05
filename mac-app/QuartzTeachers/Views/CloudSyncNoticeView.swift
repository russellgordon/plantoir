import SwiftUI

/// The plain-words explanation of what a synced working folder costs — the
/// sentences in `CloudSyncWording`, one per line, in the order they are meant
/// to be read. Shown inside the picker beside the choice, and inside the
/// window's notice when it is expanded.
struct CloudSyncExplanationView: View {

    // MARK: - Stored properties

    /// The folder being explained.
    var syncedFolder: CloudSyncedFolder

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(CloudSyncWording.explanation(service: syncedFolder.serviceName), id: \.self) { sentence in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(sentence)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("cloudSyncExplanation")
    }
}

/// The quiet notice a window shows above its path bar when the folder it
/// RESTORED is synced and the teacher has not yet been told about it.
///
/// Not a dialog, and not a sheet: a folder that opens on every launch must
/// not interrupt every launch. It stays until "Got It", which remembers the
/// folder, and it can be opened out to the full explanation in place.
struct CloudSyncNoticeView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    /// Whether the full explanation is open under the one-line summary.
    @State var isShowingDetails: Bool = false

    // MARK: - Body

    var body: some View {
        if let syncedFolder = workspace.syncedFolder, workspace.isShowingCloudSyncNotice {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "icloud")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CloudSyncWording.headline(service: syncedFolder.serviceName))
                            .bold()
                        Text(CloudSyncWording.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    Button(isShowingDetails ? "Hide Details" : "Show Details") {
                        isShowingDetails.toggle()
                    }
                    .accessibilityIdentifier("cloudSyncDetailsButton")
                    Button(CloudSyncWording.dismissNoticeButton) {
                        workspace.acknowledgeCloudSync()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("cloudSyncGotItButton")
                }
                if isShowingDetails {
                    CloudSyncExplanationView(syncedFolder: syncedFolder)
                        .padding(.leading, 24)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
            .accessibilityIdentifier("cloudSyncNotice")
        }
    }
}
