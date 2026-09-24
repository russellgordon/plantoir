import SwiftUI

/// Course Settings › Sidebar Visibility: one table, a row per folder or file,
/// with a Hide column and an Expandable column (issue #266, Russell's choice
/// on 2026-09-24 over two separate lists).
///
/// One table shows at a glance which folder is hidden and which expands, and
/// is half the height of the two lists it replaced. The two list titles
/// ("Hide from the site's sidebar", "Expandable in the site's sidebar") are
/// now short column headers under the section's own "Sidebar Visibility".
///
/// Each column writes its own list and nothing else. Both go through
/// `MembershipToggleListView.updatedMembers`, the one place a tick becomes a
/// list, so what is saved is byte for byte what the two lists saved
/// (`ListTableGoldenTests`). Neither column is protected: nothing depends on
/// a folder being shown or collapsed.
struct SidebarVisibilityTableView: View {

    // MARK: - Stored properties

    /// Column headers. Short, because they sit above a checkbox column; the
    /// section they are in is called "Sidebar Visibility", which says whose
    /// sidebar.
    static let hideHeader: String = "Hide"
    static let expandableHeader: String = "Expandable"
    static let nameHeader: String = "Folder or file"

    /// Wide enough for each header to be read in full.
    static let hideColumnWidth: CGFloat = 44
    static let expandableColumnWidth: CGFloat = 78

    /// Every folder and file the course declares, in the order of the four
    /// Content Structure lists. May name something twice — a shared and a
    /// per-section folder can share a name — and is shown once per name.
    let allItems: [String]

    @Binding var hidden: [String]
    @Binding var expandable: [String]

    @State var selectedRowID: String? = nil

    /// See `MembershipToggleListView.isEnabled`: a disabled table still takes
    /// keys, so the handlers ask.
    @Environment(\.isEnabled) var isEnabled: Bool

    // MARK: - Computed properties

    var rows: [ListTableRow] {
        return ListTableMetrics.uniqueRows(from: allItems)
    }

    // MARK: - Body

    var body: some View {
        if allItems.isEmpty {
            Text("No folders or files defined yet.")
                .foregroundStyle(.secondary)
        } else {
            Table(rows, selection: $selectedRowID) {
                TableColumn(SidebarVisibilityTableView.hideHeader) { (row: ListTableRow) in
                    Toggle(hideLabel(for: row.name), isOn: hideBinding(for: row.name))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("hideToggle-\(row.name)")
                }
                .width(SidebarVisibilityTableView.hideColumnWidth)
                TableColumn(SidebarVisibilityTableView.expandableHeader) { (row: ListTableRow) in
                    Toggle(expandableLabel(for: row.name), isOn: expandableBinding(for: row.name))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityIdentifier("expandToggle-\(row.name)")
                }
                .width(SidebarVisibilityTableView.expandableColumnWidth)
                TableColumn(SidebarVisibilityTableView.nameHeader) { (row: ListTableRow) in
                    Text(displayName(for: row.name))
                }
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: ListTableMetrics.height(forRowCount: rows.count, showsHeader: true))
            .contextMenu(forSelectionType: String.self) { rowIDs in
                // The keyboard's way to the Expandable column: a table is ONE
                // focusable control, so Space can serve only one column, and
                // with Full Keyboard Access this menu is how the other is
                // reached.
                if let item = ListTableMetrics.name(ofRowWithID: rowIDs.first, in: rows) {
                    Toggle("Hide in the Sidebar", isOn: hideBinding(for: item))
                    Toggle("Expandable in the Sidebar", isOn: expandableBinding(for: item))
                }
            }
            .onKeyPress(.space) {
                guard isEnabled else {
                    return .ignored
                }
                guard let item = ListTableMetrics.name(ofRowWithID: selectedRowID, in: rows) else {
                    return .ignored
                }
                toggleHidden(item)
                return .handled
            }
            .accessibilityIdentifier("sidebarVisibilityTable")
        }
    }

    // MARK: - Functions

    /// How a row's name is shown: files without their `.md`.
    func displayName(for item: String) -> String {
        return StringListEditorView.displayName(for: item, hidingMarkdownExtension: true)
    }

    /// What VoiceOver reads for each box. Each column has its OWN label —
    /// both boxes on a row labelled with the bare name would read "Tasks,
    /// checkbox" twice.
    func hideLabel(for item: String) -> String {
        return "Hide " + displayName(for: item)
    }

    func expandableLabel(for item: String) -> String {
        return "Expandable: " + displayName(for: item)
    }

    /// The Hide box for one row: draws from and writes to `hidden`, only.
    func hideBinding(for item: String) -> Binding<Bool> {
        return Binding(
            get: {
                return hidden.contains(item)
            },
            set: { isMember in
                hidden = MembershipToggleListView.updatedMembers(hidden, item: item, isMember: isMember)
            }
        )
    }

    /// The Expandable box for one row: draws from and writes to
    /// `expandable`, only.
    func expandableBinding(for item: String) -> Binding<Bool> {
        return Binding(
            get: {
                return expandable.contains(item)
            },
            set: { isMember in
                expandable = MembershipToggleListView.updatedMembers(expandable, item: item, isMember: isMember)
            }
        )
    }

    /// What Space does to the selected row: flips Hide, the column a teacher
    /// reaches for most. Expandable is a click or the row's menu.
    func toggleHidden(_ item: String) {
        let binding: Binding<Bool> = hideBinding(for: item)
        binding.wrappedValue = !binding.wrappedValue
    }
}
