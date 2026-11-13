import SwiftUI

/// The look before EVERY share of unit plans (#709, reshaped by #833): the
/// plan's documents in two standard tables, Shared and Not shared, with drag
/// and drop between them, a move button each way, a context menu on a row,
/// one search field, a Unit popup and Answer Keys Only. The ONLY place the
/// share's question is answered in the app (fix review H1).
///
/// The rows are what the launcher printed as its marker lines
/// (`PlanShareLists`), never re-read from disk, so the teacher answers about
/// exactly what the share holds. Cancel is the default and Escape: a share
/// that goes out by a stray Return is the one that cannot be taken back.
/// When the share owes the public-address warning (warningCases), Share
/// opens it here, with the tables' counts, before anything is answered.
struct PlanShareListsSheet: View {

    // MARK: - Stored properties

    /// Whether Share must show the public-address warning first.
    let warnsBeforeSharing: Bool

    /// The tables settled: the caller writes the choices, then answers yes.
    let onShare: (PlanShareTablesModel) -> Void
    let onCancel: () -> Void

    @State var model: PlanShareTablesModel

    @State var isShowingWarning: Bool = false

    // MARK: - Initializer

    init(
        lists: PlanShareLists,
        warnsBeforeSharing: Bool,
        onShare: @escaping (PlanShareTablesModel) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.warnsBeforeSharing = warnsBeforeSharing
        self.onShare = onShare
        self.onCancel = onCancel
        _model = State(initialValue: PlanShareTablesModel(lists: lists))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            filters
            HStack(alignment: .top, spacing: 8) {
                tableColumn(.shared)
                moveButtons
                tableColumn(.notShared)
            }
            Text(PlanShareTableWording.ownFilesLine.replacingOccurrences(of: "{n}", with: String(model.lists.ownFiles)))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Text(model.shareCountsSentence)
                    .font(.callout)
                    .accessibilityIdentifier("planShareCounts")
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .defaultButton(isEnabled: true)
                .accessibilityIdentifier("planShareListsCancel")
                Button(PlanSharingWording.listsShareButton) {
                    share()
                }
                .accessibilityIdentifier("planShareListsShare")
            }
        }
        .padding([.horizontal, .bottom], 20)
        // The by-name sentence under the title, read before either table.
        .sheetTitle(PlanSharingWording.listsSheetTitle, explanation: {
            Text(PlanSharingWording.listsByName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        })
        // Two tables of five columns fit side by side, and the sheet grows.
        .frame(minWidth: 900, idealWidth: 1040, maxWidth: .infinity, minHeight: 480, idealHeight: 580, maxHeight: .infinity)
        .interactiveDismissDisabled()
        // Escape is Cancel too: Cancel holds Return, and a button has one key.
        .onExitCommand {
            onCancel()
        }
        .sheet(isPresented: $isShowingWarning) {
            PlanSharePublicWarningSheet(
                rows: PlanSharing.warningRows(
                    shared: model.sharedCount,
                    heldBack: model.heldBackCount,
                    keysInShared: model.answerKeysInShared
                ),
                onShare: {
                    isShowingWarning = false
                    onShare(model)
                },
                onCancel: {
                    // Back to the tables, whose own Cancel shares nothing.
                    isShowingWarning = false
                }
            )
        }
    }

    /// The search field (⌘F), the Unit popup and Answer Keys Only: they
    /// change what both tables SHOW, never what is shared.
    var filters: some View {
        HStack(spacing: 12) {
            // ⌘F puts the cursor here, and ⌘→ and ⌘← move the selected
            // rows, while this sheet's window has the keys: the search
            // field's coordinator watches for them, since a shortcut is
            // never hung on a button in a view (#457).
            PlanShareSearchField(text: $model.query, onMove: { (toNotShared: Bool) in
                if toNotShared {
                    move(from: .shared, to: .notShared)
                } else {
                    move(from: .notShared, to: .shared)
                }
            })
            .frame(minWidth: 220, maxWidth: 320)
            Picker(PlanShareTableWording.unitPopup, selection: $model.unit) {
                Text(PlanShareTableWording.allUnits).tag(String?.none)
                ForEach(model.units, id: \.self) { (unit: String) in
                    Text(unit.isEmpty ? PlanShareTableWording.noUnit : unit).tag(String?.some(unit))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("planShareUnitPopup")
            Toggle(PlanShareTableWording.keysOnly, isOn: $model.keysOnly)
                .accessibilityIdentifier("planShareKeysOnly")
            Spacer()
        }
    }

    func tableColumn(_ table: PlanShareTable) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.header(for: table))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(table == .shared ? "planShareSharedHeader" : "planShareNotSharedHeader")
            PlanShareDocumentTable(
                model: model,
                table: table,
                rows: model.documents(in: table),
                selected: model.selection[table] ?? [],
                header: model.header(for: table)
            )
            .frame(minWidth: 380, minHeight: 260)
        }
    }

    /// A move each way, for the keyboard and VoiceOver, acting only on the
    /// selected rows that are showing.
    var moveButtons: some View {
        VStack(spacing: 8) {
            Spacer()
            Button {
                move(from: .shared, to: .notShared)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help(PlanShareTableWording.moveToNotSharedHelp + " (⌘→)")
            .accessibilityLabel(PlanShareTableWording.moveToNotShared)
            .accessibilityHint(PlanShareTableWording.moveToNotSharedHelp)
            .disabled(model.visibleSelection(in: .shared).isEmpty)
            .accessibilityIdentifier("planShareMoveToNotShared")
            Button {
                move(from: .notShared, to: .shared)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help(PlanShareTableWording.moveToSharedHelp + " (⌘←)")
            .accessibilityLabel(PlanShareTableWording.moveToShared)
            .accessibilityHint(PlanShareTableWording.moveToSharedHelp)
            .disabled(model.visibleSelection(in: .notShared).isEmpty)
            .accessibilityIdentifier("planShareMoveToShared")
            Spacer()
        }
        .frame(width: 36)
    }

    // MARK: - Functions

    func move(from source: PlanShareTable, to destination: PlanShareTable) {
        if model.move(model.visibleSelection(in: source), to: destination) > 0 {
            PlanShareAnnouncer.say(model.lastAnnouncement)
        }
    }

    func share() {
        if warnsBeforeSharing {
            isShowingWarning = true
            return
        }
        onShare(model)
    }
}
