import SwiftUI

/// The plain-words explanation of what a synced working folder costs — the
/// sentences in `CloudSyncWording`, one per line, in the order they are meant
/// to be read. Shown inside the picker beside the choice, and inside the
/// window's notice when it is expanded.
///
/// No `fixedSize` anywhere in here, on purpose. A text told to keep its
/// vertical size inside a stack that proposes it a narrow width wraps to a
/// word per line and becomes hundreds of points tall — which is what pushed
/// the window's path bar off the bottom of the screen the first time this
/// notice was shown. The texts take the width they are given and wrap in it;
/// `CloudSyncNoticeLayoutTests` measures the result.
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
            CloudSyncNoticeContentView(
                syncedFolder: syncedFolder,
                isShowingDetails: $isShowingDetails,
                dismiss: {
                    workspace.acknowledgeCloudSync()
                }
            )
        }
    }
}

/// The notice's own layout, with nothing read from the environment, so a
/// test can put it in a hosting view of a known width and measure it.
struct CloudSyncNoticeContentView: View {

    // MARK: - Stored properties

    var syncedFolder: CloudSyncedFolder

    @Binding var isShowingDetails: Bool

    /// What "Got It" does.
    var dismiss: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(CloudSyncWording.headline(service: syncedFolder.serviceName))
                        .bold()
                    Text(CloudSyncWording.summary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(isShowingDetails ? CloudSyncWording.hideDetailsButton : CloudSyncWording.showDetailsButton) {
                    isShowingDetails.toggle()
                }
                .accessibilityIdentifier("cloudSyncDetailsButton")
                Button(CloudSyncWording.dismissNoticeButton) {
                    dismiss()
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
