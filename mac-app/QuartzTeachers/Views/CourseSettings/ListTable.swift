import SwiftUI

/// One row of a folder or file table.
///
/// Its `id` is what the table selects and what SwiftUI reuses rows by; its
/// `name` is the stored name every gesture acts on. The two are kept apart and
/// a row is always LOOKED UP by its id, never taken apart to recover a name —
/// a folder may be called anything, "|" included.
struct ListTableRow: Identifiable, Hashable {

    // MARK: - Stored properties

    let id: String
    let name: String
}

/// The sizes and row-building rules shared by every folder and file table in
/// Course Settings and the New Course wizard (issue #266).
enum ListTableMetrics {

    // MARK: - Stored properties

    /// The height of one row. MEASURED, not chosen: a bordered SwiftUI
    /// `Table` on macOS 26 draws 24-point rows, and stays at 24 at every
    /// Dynamic Type size and control size tried (`xxxLarge`,
    /// `accessibility3`, `.large`, `.small`). A scaled metric here would grow
    /// the frame while the rows stayed put, leaving an empty band.
    /// `ListTableLayoutTests` pins this against the real `NSTableView`, so an
    /// OS change fails a test instead of clipping the last row.
    static let rowHeight: CGFloat = 24

    /// The height of the column header row, where a table shows one. Measured
    /// and pinned the same way as `rowHeight`.
    static let headerHeight: CGFloat = 28

    /// The border drawn around a bordered table: one point at the top and
    /// one at the bottom.
    static let borderAllowance: CGFloat = 2

    /// How many rows are shown before the table scrolls inside itself. The
    /// longest list in any ready-made course or skeleton is 18 rows, so every
    /// real course shows all of its rows.
    static let mostRowsShown: Int = 20

    // MARK: - Functions

    /// The height that shows every row, up to `mostRowsShown`, with no inner
    /// scrolling and no empty band — so the table sits in the page like the
    /// list it replaced, and the page scrolls rather than the table.
    static func height(forRowCount rowCount: Int, showsHeader: Bool) -> CGFloat {
        var shownRows: Int = rowCount
        if shownRows < 1 {
            shownRows = 1
        }
        if shownRows > mostRowsShown {
            shownRows = mostRowsShown
        }
        var height: CGFloat = CGFloat(shownRows) * rowHeight + borderAllowance
        if showsHeader {
            height = height + headerHeight
        }
        return height
    }

    /// One row per distinct name, the first occurrence winning.
    ///
    /// For tick lists, whose choices are keyed by NAME: a shared folder and a
    /// per-section folder may share a name, and two rows for it could only
    /// ever tick together. Presentation only — what is written is by name, as
    /// it always was.
    static func uniqueRows(from names: [String]) -> [ListTableRow] {
        var seen: Set<String> = []
        var rows: [ListTableRow] = []
        for name in names {
            if seen.contains(name) {
                continue
            }
            seen.insert(name)
            rows.append(ListTableRow(id: name, name: name))
        }
        return rows
    }

    /// One row per entry, in order, for a list the teacher edits. The id
    /// carries the position so a hand-edited file that names something twice
    /// still has distinct rows; removing acts on the NAME, as it always did.
    static func positionedRows(from names: [String]) -> [ListTableRow] {
        var rows: [ListTableRow] = []
        var position: Int = 0
        for name in names {
            rows.append(ListTableRow(id: String(position) + "|" + name, name: name))
            position = position + 1
        }
        return rows
    }

    /// The name of the row with this id, or nil when no row has it — looked
    /// up, never parsed out of the id.
    static func name(ofRowWithID rowID: String?, in rows: [ListTableRow]) -> String? {
        guard let rowID else {
            return nil
        }
        for row in rows {
            if row.id == rowID {
                return row.name
            }
        }
        return nil
    }
}

/// The + and − under a folder or file table — the standard macOS list
/// footer, drawn exactly as the app's own sidebar draws its footer
/// (`SidebarView.bottomBar`), so the app has one +/− look.
///
/// SwiftUI has no gradient "small square" button style, and AppKit's has
/// looked like this borderless pair since Big Sur; bridging an
/// `NSSegmentedControl` for the old look was rejected.
struct ListAddRemoveFooter<AddContent: View>: View {

    // MARK: - Stored properties

    /// What VoiceOver reads for each button: "Add new folder…",
    /// "Remove Selected Folder", and so on.
    let addLabel: String
    let removeLabel: String

    /// The list's title, for the identifiers.
    let title: String

    /// False while nothing is selected. NOT false for a selection that
    /// cannot be removed: − on such a row says why, and a disabled button
    /// explains nothing.
    let canRemove: Bool

    let onAdd: () -> Void
    let onRemove: () -> Void

    /// The add popover, anchored to +, and why a removal was refused,
    /// anchored to − — each on its own button and its own state, so exactly
    /// one presenter answers to each.
    @Binding var isAdding: Bool
    @Binding var removalExplanation: ActiveExplanation?
    @ViewBuilder let addContent: () -> AddContent

    @ScaledMetric(relativeTo: .body) var glyphSize: CGFloat = SidebarView.footerGlyphSize
    @ScaledMetric(relativeTo: .body) var buttonWidth: CGFloat = SidebarView.footerButtonSize.width
    @ScaledMetric(relativeTo: .body) var buttonHeight: CGFloat = SidebarView.footerButtonSize.height

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            footerButton(addLabel, systemImage: "plus", action: onAdd)
                .accessibilityIdentifier("addTo-\(title)")
                .popover(isPresented: $isAdding, arrowEdge: .bottom) {
                    addContent()
                }
            Divider()
                .frame(height: buttonHeight - 8)
            footerButton(removeLabel, systemImage: "minus", action: onRemove)
                .disabled(!canRemove)
                .accessibilityIdentifier("removeFrom-\(title)")
                .popover(item: $removalExplanation, arrowEdge: .bottom) { explanation in
                    ExplanationPopoverText(reason: explanation.reason)
                }
            Divider()
                .frame(height: buttonHeight - 8)
            Spacer(minLength: 0)
        }
        .frame(height: buttonHeight)
        .background(.background.secondary)
        .overlay {
            Rectangle()
                .strokeBorder(.separator, lineWidth: 1)
        }
        // Shares the table's bottom border line rather than drawing a
        // second one beside it.
        .padding(.top, -1)
    }

    // MARK: - Functions

    /// A glyph with a real target: the frame and content shape are INSIDE
    /// the label, as `SidebarView.bottomBar` found they must be.
    func footerButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        return Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: glyphSize))
                .frame(width: buttonWidth, height: buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
    }
}
