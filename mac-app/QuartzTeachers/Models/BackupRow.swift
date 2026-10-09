import Foundation

/// One row of All Backups' table, carrying what its columns sort by (#457,
/// the HIG sweep: clicking Course, Made or Size sorts the table).
///
/// A row rather than `BackupItem` itself because Size is not the item's: it
/// is measured off the main thread and kept on the window's model
/// (`WorkspaceModel.backupSizes`), so a key path on the item could not reach
/// it. "Made By" does not sort: two values, and the column reads as a label.
nonisolated struct BackupRow: Identifiable {

    // MARK: - Stored properties

    let item: BackupItem

    /// Copied from the item as STORED properties, so the table's sort key
    /// paths are to stored values (a key path to a computed, actor-isolated
    /// property is not `Sendable`, which `KeyPathComparator` needs).
    let id: String
    let courseCode: String
    let backedUpAt: Date

    /// The backup's size in bytes, or -1 while it has not been measured (or
    /// could not be), so unmeasured rows sort together below the smallest.
    let bytesForSorting: Int64

    // MARK: - Computed properties

    /// The order the table opens in: newest first, the order the list has
    /// always had.
    static var newestFirst: [KeyPathComparator<BackupRow>] {
        return [KeyPathComparator(\BackupRow.backedUpAt, order: .reverse)]
    }

    // MARK: - Functions

    /// The rows for `items`, sorted by the table's sort order. A sort order
    /// with no comparators leaves the list's own order (newest first).
    @MainActor
    static func rows(
        of items: [BackupItem],
        sizes: [String: Int64],
        sortedBy sortOrder: [KeyPathComparator<BackupRow>]
    ) -> [BackupRow] {
        var rows: [BackupRow] = []
        for item in items {
            rows.append(BackupRow(
                item: item,
                id: item.id,
                courseCode: item.courseCode,
                backedUpAt: item.backedUpAt,
                bytesForSorting: sizes[item.id] ?? -1
            ))
        }
        if sortOrder.isEmpty {
            return rows
        }
        rows.sort(using: sortOrder)
        return rows
    }
}
