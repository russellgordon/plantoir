import SwiftUI

/// The quiet notice a window shows above its path bar while the folder's
/// tools are being copied in (#476; Windows' `gettingReadyNotice`, #473), and
/// the error it turns into when that copy could not finish.
///
/// Not a dialog, and not a sheet: the first launch after an update must not
/// interrupt itself. It appears only once the copy has actually WRITTEN a
/// file (`ToolchainReadiness.showsBanner`), so the ordinary launch, which
/// compares every file and writes nothing, never flashes it; Preview, Deploy
/// and New Course are greyed from the copy's first moment regardless.
struct ToolchainReadinessNoticeView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Body

    var body: some View {
        if let workspaceURL = workspace.workspaceURL {
            let state: ToolchainReadiness.State = ToolchainReadiness.shared.state(of: workspaceURL)
            if ToolchainReadiness.showsBanner(for: state) {
                ToolchainReadinessNoticeContentView(state: state)
            }
        }
    }
}

/// The notice itself, given its state — so a preview and a test can show it
/// without a registry.
struct ToolchainReadinessNoticeContentView: View {

    // MARK: - Stored properties

    let state: ToolchainReadiness.State

    // MARK: - Computed properties

    private var hasFailed: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private var title: String {
        return hasFailed ? "This folder is not ready" : ToolchainReadinessWording.gettingReadyTitle
    }

    private var message: String {
        if case .failed(let message) = state {
            return message
        }
        return ToolchainReadinessWording.gettingReadyMessage
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if hasFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(hasFailed ? "couldNotGetReadyNotice" : "gettingReadyNotice")
    }
}
