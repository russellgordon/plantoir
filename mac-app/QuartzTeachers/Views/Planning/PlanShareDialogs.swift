import SwiftUI

/// The facts of a dialog as labelled rows in the system's own form styling
/// (#834): VoiceOver reads each as "label, value", and a row whose fact is
/// missing is not in `rows` at all.
struct PlanShareRowsForm: View {

    // MARK: - Stored properties

    let rows: [PlanShareRow]

    // MARK: - Body

    var body: some View {
        Form {
            ForEach(rows, id: \.label) { (row: PlanShareRow) in
                LabeledContent(row.label) {
                    Text(row.value)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

/// The public-address warning before unit plans are shared without a
/// password (unitPlanning.share.warningSheet; #834's shape): the title asks,
/// one short sentence says what happens, the facts are rows, and Cancel is
/// the default and Escape. It comes after the two tables, so its rows give
/// their counts.
struct PlanSharePublicWarningSheet: View {

    // MARK: - Stored properties

    let rows: [PlanShareRow]
    let onShare: () -> Void
    let onCancel: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlanShareRowsForm(rows: rows)
                .frame(minHeight: CGFloat(rows.count) * 44 + 24)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .defaultButton(isEnabled: true)
                .accessibilityIdentifier("planShareWarningCancel")
                Button(PlanSharingWording.shareAnyway, role: .destructive) {
                    onShare()
                }
                .accessibilityIdentifier("planShareWarningShare")
            }
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle(PlanSharingWording.crawlerWarningTitle, explanation: {
            Text(PlanSharingWording.crawlerWarningMessage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        })
        .frame(width: 520)
        .interactiveDismissDisabled()
        .onExitCommand {
            onCancel()
        }
    }
}

/// After Change Password saved a new password for plans that are shared
/// (unitPlanning.share.changePasswordCases): the teacher must answer.
/// Share Again, the default, goes through the bar's own path, the two tables
/// first; Later, and Escape, leave the bar saying the new password is not in
/// use yet.
struct PlanShareNewPasswordSheet: View {

    // MARK: - Stored properties

    let earlierYearShared: Bool
    let onShareAgain: () -> Void
    let onLater: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let rows: [PlanShareRow] = PlanSharing.newPasswordRows(earlierYearShared: earlierYearShared)
            PlanShareRowsForm(rows: rows)
                .frame(minHeight: CGFloat(rows.count) * 44 + 24)
            HStack {
                Spacer()
                Button(PlanSharingWording.later) {
                    onLater()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("planShareNewPasswordLater")
                Button(PlanSharingWording.shareAgain) {
                    onShareAgain()
                }
                .defaultButton(isEnabled: true)
                .accessibilityIdentifier("planShareNewPasswordShareAgain")
            }
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle(PlanSharingWording.newPasswordSavedTitle, explanation: {
            Text(PlanSharingWording.newPasswordSavedMessage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        })
        .frame(width: 520)
        .interactiveDismissDisabled()
    }
}
