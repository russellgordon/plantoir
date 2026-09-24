import SwiftUI

/// A table of checkboxes controlling membership in a string list — the
/// folders whose work counts for marks, in Course Settings and the New Course
/// wizard, with protection for the folder that must stay ticked.
///
/// A standard macOS table since issue #266: the box sits beside the name it
/// belongs to. It used to be a `Toggle` inside a grouped `Form`, which draws a
/// SWITCH at the far trailing edge, hundreds of points from its label.
///
/// No add or remove control, on purpose: the rows come from the course's
/// folders, and the caption under this list promises only "tick".
struct MembershipToggleListView: View {

    // MARK: - Stored properties

    let title: String

    /// Everything that can be toggled.
    let allItems: [String]

    /// The current members (a subset of `allItems`, possibly plus legacy
    /// entries that no longer exist — those are preserved untouched).
    @Binding var members: [String]

    var protection: ((String) -> ItemProtection)? = nil

    @State var activeExplanation: ActiveExplanation? = nil
    @State var selectedRowID: String? = nil

    /// Read so the keyboard obeys a disabled section. MEASURED: a SwiftUI
    /// `Table` under `.disabled(true)` still takes arrow keys, and its
    /// `.onKeyPress` handler still fires — the wizard's Structure section is
    /// disabled until a course is chosen, and Space would have ticked there.
    @Environment(\.isEnabled) var isEnabled: Bool

    // MARK: - Computed properties

    var rows: [ListTableRow] {
        return ListTableMetrics.uniqueRows(from: allItems)
    }

    // MARK: - Body

    var body: some View {
        // Worked out HERE, in the list's own body, and handed to each cell as
        // a value: a cell must never ask the course a question while it is
        // being drawn. See `protectionsAsDrawn()` for why.
        let protections: [String: ItemProtection] = protectionsAsDrawn()

        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            if allItems.isEmpty {
                Text("No folders or files defined yet.")
                    .foregroundStyle(.secondary)
            } else {
                Table(rows, selection: $selectedRowID) {
                    TableColumn(title) { (row: ListTableRow) in
                        tickCell(for: row.name, protection: protections[row.name] ?? .ordinary)
                    }
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
                .tableColumnHeaders(.hidden)
                .frame(height: ListTableMetrics.height(forRowCount: rows.count, showsHeader: false))
                .onKeyPress(.space) {
                    guard isEnabled else {
                        return .ignored
                    }
                    guard let item = ListTableMetrics.name(ofRowWithID: selectedRowID, in: rows) else {
                        return .ignored
                    }
                    toggleMembership(of: item)
                    return .handled
                }
                .accessibilityIdentifier("table-\(title)")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Rows

    /// The checkbox WITH its name as its visible label, the way Xcode's
    /// target-membership list draws it: clicking the name ticks the box, as
    /// clicking the old toggle's label did.
    ///
    /// Built only from what it is given — the row's name and the protection
    /// the list worked out for it — never by calling back into the course.
    @ViewBuilder
    func tickCell(for item: String, protection itemProtection: ItemProtection) -> some View {
        // File entries hide their ".md" storage extension, matching the list
        // editors.
        let displayName: String = StringListEditorView.displayName(for: item, hidingMarkdownExtension: true)
        HStack {
            Toggle(displayName, isOn: membershipBinding(for: item, protection: itemProtection))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("toggle-\(item)")
                .accessibilityHint(title)
            Spacer()
            if case .blocked(let reason) = itemProtection {
                Button("Why \(displayName) can’t be unticked", systemImage: "info.circle") {
                    activeExplanation = ActiveExplanation(item: item, reason: reason)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("whyBlockedToggle-\(item)")
                .help(reason)
                .popover(item: explanationBinding(for: item), arrowEdge: .trailing) { explanation in
                    ExplanationPopoverText(reason: explanation.reason)
                }
            }
        }
    }

    // MARK: - Functions

    /// The protection of every row, worked out once per drawing of the list.
    ///
    /// **Why not in the cell (issue #266).** A `Table` builds each row in a
    /// part of the view graph of its own. The marks list's protection closure
    /// reads the course's configuration and walks its folders; called from
    /// the cell, that question was asked from inside the row. Leaving Course
    /// Settings for nothing, or for another working folder, then aborted the
    /// app with "precondition failure: no subgraph": the window's detail pane
    /// rebuilt the rows of the page it was removing, and the table updated a
    /// row whose part of the graph was already gone. Bisected on 2026-09-24 —
    /// the same cell given the same answer as a value survived, and the
    /// Shared folders table crashed the same way once its cells asked the
    /// marks question — so the rule for every folder table is: ask in the
    /// list's body, hand the cell the answer. `CourseSettingsTeardownTests`
    /// is the must-fail.
    func protectionsAsDrawn() -> [String: ItemProtection] {
        var protections: [String: ItemProtection] = [:]
        for row in rows {
            protections[row.name] = protectionAsDrawn(for: row.name)
        }
        return protections
    }

    /// The protection a row is drawn and ticked with: only a MEMBER can be
    /// protected, because only unticking can be refused.
    func protectionAsDrawn(for item: String) -> ItemProtection {
        if members.contains(item) {
            return protection?(item) ?? .ordinary
        }
        return .ordinary
    }

    /// The members with one item added or taken out — the ONE place a tick
    /// becomes a list, shared by every checkbox in the app's folder tables so
    /// no second copy can drift. Every other member is preserved in place,
    /// including names no row shows (a legacy `hidden` entry, say).
    static func updatedMembers(_ members: [String], item: String, isMember: Bool) -> [String] {
        if isMember {
            if members.contains(item) {
                return members
            }
            var result: [String] = members
            result.append(item)
            return result
        }
        var result: [String] = []
        for member in members {
            if member != item {
                result.append(member)
            }
        }
        return result
    }

    /// The binding a checkbox draws from AND writes through — one binding for
    /// both, so a box cannot show one thing and save another.
    func membershipBinding(for item: String, protection: ItemProtection) -> Binding<Bool> {
        return Binding(
            get: {
                return members.contains(item)
            },
            set: { isMember in
                if isMember {
                    // Nothing is written when the item is already there —
                    // which matters for the marks list, whose binding
                    // materialises the inferred pool on ANY write.
                    if members.contains(item) {
                        return
                    }
                } else if case .blocked(let reason) = protection {
                    activeExplanation = ActiveExplanation(item: item, reason: reason)
                    ActivityTrail.note(.removalBlocked, "was told " + item + " cannot be unticked under " + title + " — " + reason)
                    return
                }
                members = MembershipToggleListView.updatedMembers(members, item: item, isMember: isMember)
            }
        )
    }

    /// What Space does to the selected row: exactly what a click on its box
    /// does, through the same binding and with the protection worked out the
    /// same way — so a blocked untick by keyboard explains itself too.
    func toggleMembership(of item: String) {
        let binding: Binding<Bool> = membershipBinding(for: item, protection: protectionAsDrawn(for: item))
        binding.wrappedValue = !binding.wrappedValue
    }

    /// Presents this row's explanation, and only this row's.
    func explanationBinding(for item: String) -> Binding<ActiveExplanation?> {
        return Binding(
            get: {
                if activeExplanation?.item == item {
                    return activeExplanation
                }
                return nil
            },
            set: { newValue in
                if newValue == nil && activeExplanation?.item == item {
                    activeExplanation = nil
                }
            }
        )
    }
}

/// Why something cannot be removed or unticked, in a popover.
struct ExplanationPopoverText: View {

    // MARK: - Stored properties

    let reason: String

    // MARK: - Body

    var body: some View {
        // A fixed width plus fixedSize: a popover sizes itself to its
        // content, and a Text with only a maxWidth was measured as one line
        // and shown truncated ("…") when the real app was driven.
        Text(reason)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 280, alignment: .leading)
            .padding(12)
    }
}
