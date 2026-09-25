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
/// proposed, and the plan review measured it followed by one Delete removing
/// the backup an open assistant conversation restores from; the delete itself
/// now refuses that one, and a shortcut that selects it is an invitation.
struct AllBackupsView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    /// The rows the teacher has selected, by `BackupItem.id`.
    @State var selectedIdentifiers: Set<BackupItem.ID> = []

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
                Table(workspace.backupItems, selection: $selectedIdentifiers) {
                    TableColumn("Course") { item in
                        Text(item.courseCode)
                    }
                    TableColumn("Made") { item in
                        Text(item.whenDescription)
                    }
                    TableColumn("Made By") { item in
                        Text(madeBy(item))
                    }
                    TableColumn("Size") { item in
                        Text(workspace.sizeDescription(of: item) ?? "—")
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("allBackupsTable")
                HStack {
                    Text("Plantoir never deletes a backup you made. The assistant keeps only its five most recent for each course. Select the ones you no longer need — ⌘-click or ⇧-click for several — and delete them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(deleteButtonTitle, role: .destructive) {
                        workspace.backupsDeleteRequest = selectedItems
                    }
                    .disabled(selectedItems.isEmpty)
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

    /// "ICS4U — 3 backups, 27.3 MB".
    func courseLine(for share: BackupSpace.CourseShare) -> String {
        let noun: String = share.count == 1 ? "backup" : "backups"
        return "\(share.courseCode) — \(share.count) \(noun), \(BackupSizes.description(ofBytes: share.bytes))"
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

    /// The same honesty as the single delete's confirmation — for good,
    /// nothing kept, the courses untouched — with how much is being deleted.
    func deleteConfirmationMessage(for items: [BackupItem]) -> String {
        var message: String = items.count == 1
            ? "This deletes the backup for good — unlike removing a course, nothing is kept."
            : "This deletes them for good — unlike removing a course, nothing is kept."
        var bytes: Int64 = 0
        var everySizeKnown: Bool = true
        for item in items {
            if let size = workspace.backupSizes[item.id] {
                bytes += size
            } else {
                everySizeKnown = false
            }
        }
        if everySizeKnown {
            let together: String = items.count == 1 ? "It takes" : "Together they take"
            message += " \(together) \(BackupSizes.description(ofBytes: bytes))."
        }
        message += "\n\nThe courses themselves are not touched."
        return message
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
