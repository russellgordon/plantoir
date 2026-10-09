import SwiftUI

/// Every backup in the working folder at once: what they take, per course and
/// in total, and a way to delete several (issue #242).
///
/// **Why it exists.** A teacher's own backups are never pruned — Russell's
/// decision, 2026-09-21: a backup made on purpose before a risky change should
/// not vanish because ten more were made after it — and each one carries the
/// whole course, Media included (467 MB for a real course). So the space is
/// SHOWN, and deleting old ones is made easy; the teacher decides what goes.
///
/// A pane of its own rather than multi-selection in the sidebar: turning the
/// sidebar's list into a multiple-selection list would change how every
/// course and section row in the window is selected, to serve one group of
/// it. The table here uses the ordinary macOS idiom — ⌘-click and ⇧-click —
/// and the one Delete button says how many it will delete.
///
/// There is deliberately no "select the assistant's" shortcut. It was
/// proposed, and the plan review reasoned (from the code, not by measuring)
/// that it followed by one Delete would remove the backup an open assistant
/// conversation restores from; the delete itself
/// now refuses that one, and a shortcut that selects it is an invitation.
struct AllBackupsView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    /// The rows the teacher has selected, by `BackupItem.id`.
    @State var selectedIdentifiers: Set<BackupItem.ID> = []

    /// How the table is sorted: newest first until a column header is
    /// clicked (#457, the HIG sweep — Russell: yes, sort by column).
    @State var sortOrder: [KeyPathComparator<BackupRow>] = BackupRow.newestFirst

    // MARK: - Computed properties

    var body: some View {
        if workspace.backupItems.isEmpty {
            ContentUnavailableView(
                "No Backups",
                systemImage: "clock.arrow.circlepath",
                description: Text("Back Up Now, in a course’s menu, saves a copy of the whole course here.")
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                spaceSummary
                Table(sortedRows, selection: $selectedIdentifiers, sortOrder: $sortOrder) {
                    TableColumn("Course", value: \.courseCode) { row in
                        Text(row.item.courseCode)
                    }
                    TableColumn("Made", value: \.backedUpAt) { row in
                        Text(row.item.whenDescription)
                    }
                    TableColumn("Made By") { row in
                        Text(madeBy(row.item))
                    }
                    TableColumn("Size", value: \.bytesForSorting) { row in
                        Text(workspace.shortSizeDescription(of: row.item) ?? "—")
                            .monospacedDigit()
                            .help(workspace.sizeDescription(of: row.item) ?? "")
                    }
                }
                // Right-click acts on the rows under the pointer and selects
                // them first, as the sidebar's rows do (#457, the HIG sweep).
                .contextMenu(forSelectionType: String.self) { identifiers in
                    backupsMenu(for: identifiers)
                }
                // Delete asks the same "Delete N backups?" the button asks.
                .onDeleteCommand(perform: requestDeletingTheSelection)
                .accessibilityIdentifier("allBackupsTable")
                HStack {
                    Text("Plantoir never deletes a backup you made. The assistant keeps only its five most recent for each course. Select the ones you no longer need — ⌘-click or ⇧-click for several — and delete them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(deleteButtonTitle, role: .destructive) {
                        workspace.backupsDeleteRequest = selectedItems
                    }
                    // Disabled when nothing selected can go — including a
                    // selection of held backups only (the delete would keep
                    // them all, so there is nothing to confirm).
                    // Held includes a Claude or Codex session's backup elsewhere
                    // (#458), read when the pane draws: one listing of the
                    // activity folder, and the confirmation reads it again.
                    .disabled(!canDelete(selectedItems))
                    .accessibilityIdentifier("deleteSelectedBackupsButton")
                }
            }
            .padding()
            .onChange(of: workspace.backupItems) {
                keepOnlyListedSelections()
            }
            .alert(
                deleteConfirmationTitle,
                isPresented: deleteRequestIsPresented,
                presenting: workspace.backupsDeleteRequest
            ) { items in
                Button("Delete", role: .destructive) {
                    workspace.deleteBackups(items)
                    selectedIdentifiers = []
                }
                Button("Cancel", role: .cancel) {
                }
            } message: { items in
                Text(deleteConfirmationMessage(for: items))
            }
        }
    }

    /// "These backups take 29.3 MB.", then one line per course.
    var spaceSummary: some View {
        let space: BackupSpace = workspace.backupSpace
        return VStack(alignment: .leading, spacing: 4) {
            if space.isComplete {
                Text("These backups take \(BackupSizes.description(ofBytes: space.totalBytes)).")
                    .font(.title3)
                    .accessibilityIdentifier("allBackupsTotal")
                if space.unsizedCount > 0 {
                    Text(unsizedLine(space.unsizedCount))
                        .foregroundStyle(.secondary)
                }
                ForEach(space.courses, id: \.courseCode) { share in
                    Text(courseLine(for: share))
                        .foregroundStyle(.secondary)
                }
                if let synced = workspace.syncedFolder {
                    Text("Your working folder is kept in sync with \(synced.serviceName), so they take that much of its storage too.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Working out how much space these backups take…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The table's rows, in the order the teacher sorted them.
    var sortedRows: [BackupRow] {
        return BackupRow.rows(of: workspace.backupItems, sizes: workspace.backupSizes, sortedBy: sortOrder)
    }

    /// The backups selected, in the list's own order.
    var selectedItems: [BackupItem] {
        var items: [BackupItem] = []
        for item in workspace.backupItems {
            if selectedIdentifiers.contains(item.id) {
                items.append(item)
            }
        }
        return items
    }

    /// "Delete 3 Backups…" — the count in the label, so what one press will
    /// do is on the button itself.
    var deleteButtonTitle: String {
        let count: Int = selectedItems.count
        if count == 0 {
            return "Delete Backups…"
        }
        if count == 1 {
            return "Delete 1 Backup…"
        }
        return "Delete \(count) Backups…"
    }

    var deleteConfirmationTitle: String {
        let count: Int = workspace.backupsDeleteRequest?.count ?? 0
        if count == 1 {
            return "Delete this backup?"
        }
        return "Delete these \(count) backups?"
    }

    var deleteRequestIsPresented: Binding<Bool> {
        return Binding(
            get: { workspace.backupsDeleteRequest != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.backupsDeleteRequest = nil
                }
            }
        )
    }

    // MARK: - Functions

    /// Whether anything in `items` can be deleted: not a backup an open
    /// assistant conversation or a Claude or Codex session holds.
    func canDelete(_ items: [BackupItem]) -> Bool {
        return WorkspaceModel.deletableCount(
            of: items,
            heldPaths: WorkspaceModel.everyHeldBackupPath(inWorkingFolder: workspace.workspaceURL)
        ) > 0
    }

    /// The backups with these identifiers, in the list's own order.
    func items(withIdentifiers identifiers: Set<BackupItem.ID>) -> [BackupItem] {
        var items: [BackupItem] = []
        for item in workspace.backupItems {
            if identifiers.contains(item.id) {
                items.append(item)
            }
        }
        return items
    }

    /// The table's context menu: Restore… (one backup), Show in Finder, then
    /// Delete… last, behind a divider — the sidebar's backup row's menu, for
    /// one row or several.
    @ViewBuilder
    func backupsMenu(for identifiers: Set<BackupItem.ID>) -> some View {
        let chosen: [BackupItem] = items(withIdentifiers: identifiers)
        if !chosen.isEmpty {
            Button("Restore…", systemImage: "arrow.uturn.backward") {
                selectedIdentifiers = identifiers
                if let item = chosen.first {
                    workspace.backupRestoreRequest = item
                }
            }
            .disabled(chosen.count != 1 || workspace.isBeingCopied(chosen[0].courseCode))
            Button("Show in Finder", systemImage: "finder") {
                selectedIdentifiers = identifiers
                var urls: [URL] = []
                for item in chosen {
                    urls.append(item.fileURL)
                }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            Divider()
            Button(chosen.count == 1 ? "Delete Backup…" : "Delete \(chosen.count) Backups…", systemImage: "trash", role: .destructive) {
                selectedIdentifiers = identifiers
                workspace.backupsDeleteRequest = chosen
            }
            .disabled(!canDelete(chosen))
        }
    }

    /// Delete, pressed in the table: the Delete button's question, for what
    /// is selected — nothing when nothing selected can go.
    func requestDeletingTheSelection() {
        let chosen: [BackupItem] = selectedItems
        if canDelete(chosen) {
            workspace.backupsDeleteRequest = chosen
        } else {
            NSSound.beep()
        }
    }

    /// "ICS4U — 3 backups, 27.3 MB".
    func courseLine(for share: BackupSpace.CourseShare) -> String {
        let noun: String = share.count == 1 ? "backup" : "backups"
        return "\(share.courseCode) — \(share.count) \(noun), \(BackupSizes.description(ofBytes: share.bytes))"
    }

    /// "1 backup — Size could not be read, so it is not in the total". The
    /// wording key is rendered exactly as written, never re-cased.
    func unsizedLine(_ count: Int) -> String {
        let noun: String = count == 1 ? "backup" : "backups"
        return "\(count) \(noun) — " + AssistWording.backupSizeCouldNotBeRead
    }

    /// Who made a backup, short enough for a column.
    func madeBy(_ item: BackupItem) -> String {
        switch item.maker {
        case .teacher:
            return "You"
        case .assistant(let sectionNumber):
            return "The assistant, Section \(sectionNumber)"
        }
    }

    /// Built by `WorkspaceModel.deleteConfirmation`, which names a backup the
    /// open assistant conversation holds as kept and counts only what goes.
    func deleteConfirmationMessage(for items: [BackupItem]) -> String {
        return WorkspaceModel.deleteConfirmation(
            for: items,
            sizes: workspace.backupSizes,
            heldPaths: WorkspaceModel.heldBackupPaths(),
            active: AssistActivity.active,
            heldByOtherSessions: WorkspaceModel.backupPathsHeldByOtherSessions(
                inWorkingFolder: workspace.workspaceURL
            )
        )
    }

    /// Drops a selection whose backup is no longer listed — deleted here, or
    /// in another window on the same folder.
    func keepOnlyListedSelections() {
        var listed: Set<BackupItem.ID> = []
        for item in workspace.backupItems {
            listed.insert(item.id)
        }
        var stillListed: Set<BackupItem.ID> = []
        for identifier in selectedIdentifiers where listed.contains(identifier) {
            stillListed.insert(identifier)
        }
        selectedIdentifiers = stillListed
    }
}
