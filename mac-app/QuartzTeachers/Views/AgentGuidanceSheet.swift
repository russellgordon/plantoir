import SwiftUI

/// Asks before Plantoir adds its section to a teacher's own AGENTS.md or
/// CLAUDE.md at the working folder's root (#454, Russell's P1 addendum 2):
/// which file, what would be added (behind a disclosure), and that their own
/// text stays above it. Add or Not Now; Escape is Not Now and Return is Add,
/// as on every sheet since #457. The answer is remembered and recorded
/// (`ToolchainReadiness.answer`).
struct AgentGuidanceSheet: View {

    // MARK: - Stored properties

    let pending: AgentGuidance.PendingAppend
    let workspaceURL: URL

    @State var isShowingText: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AgentGuidanceWording.askWhat)
                .fixedSize(horizontal: false, vertical: true)
            Text(AgentGuidanceWording.askYoursStays)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(AgentGuidanceWording.showWhatIsAdded, isExpanded: $isShowingText) {
                ScrollView {
                    Text(pending.section)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 220)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
            }
            .accessibilityIdentifier("agentGuidanceShowText")

            HStack {
                Spacer()
                Button(AgentGuidanceWording.notNow) {
                    ToolchainReadiness.shared.answer(pending, add: false, in: workspaceURL)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("agentGuidanceNotNow")
                Button(AgentGuidanceWording.add) {
                    ToolchainReadiness.shared.answer(pending, add: true, in: workspaceURL)
                }
                .defaultButton(isEnabled: true)
                .accessibilityIdentifier("agentGuidanceAdd")
            }
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle(AgentGuidanceWording.askTitle(file: pending.fileName), identifier: "agentGuidanceTitle") {
            Text(AgentGuidanceWording.askFound(file: pending.fileName))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 480)
    }
}

/// The quiet notice when the guidance could not be written (#454 review S1):
/// above the path bar with the folder's other notices, dismissable, and never
/// in the way of Preview or Deploy.
struct AgentGuidanceNoticeView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Body

    var body: some View {
        if let workspaceURL = workspace.workspaceURL,
           let message = ToolchainReadiness.shared.guidanceNotices[FolderIdentity.canonicalPath(workspaceURL.path)] {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button(AgentGuidanceWording.dismiss) {
                    ToolchainReadiness.shared.dismissGuidanceNotice(for: workspaceURL)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("agentGuidanceNotice")
        }
    }
}
