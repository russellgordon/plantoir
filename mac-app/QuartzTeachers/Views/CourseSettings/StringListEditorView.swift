import SwiftUI

/// A removal waiting for confirmation from the teacher.
struct PendingRemoval: Identifiable {

    // MARK: - Stored properties

    let item: String
    let title: String
    let message: String

    // MARK: - Computed properties

    var id: String { return item }
}

/// A rename the teacher is part way through typing.
struct PendingRename: Identifiable {

    // MARK: - Stored properties

    let item: String

    /// The name a rename from this folder was heading for when it stopped, or
    /// nil when nothing was interrupted. Settled ONCE, when the sheet opens,
    /// because answering it touches the filesystem — asked from inside the
    /// view's body it would be a handful of `stat` calls per keystroke.
    ///
    /// The TARGET rather than a yes/no, so that the clash check can be relaxed
    /// for exactly the rename that was interrupted and for no other: a teacher
    /// who opens this sheet and types a different name gets the ordinary
    /// refusal back.
    let interruptedRenameTarget: String?

    // MARK: - Computed properties

    var id: String { return item }
}

/// What happened to a list, for the sake of what the teacher is told
/// afterwards. Adding a folder now creates it on disk and removing one
/// deliberately does not delete it, and neither is guessable from the button.
enum ListChange {
    case added
    case removed
}

/// What a caller made of an attempted rename.
enum RenameResult {

    /// It worked. The sentence is shown afterwards, and says what moved.
    case renamed(String)

    /// It did not. The sentence is shown inside the sheet, which stays open so
    /// the teacher can type a different name rather than start again.
    case failed(String)
}

/// An explanation of why an item cannot be removed.
struct ActiveExplanation: Identifiable {

    // MARK: - Stored properties

    let item: String
    let reason: String

    // MARK: - Computed properties

    var id: String { return item }
}

/// Edits a list of names (folders or files): a standard macOS table of the
/// entries with + and − at its lower left (issue #266). + opens a small
/// popover to type a new name into; − removes the selected entry, and so do
/// the Delete key and the row's menu — all three through `requestRemoval(of:)`,
/// the one place a removal asks the list's protection first.
///
/// For FILE lists, the ".md" extension is a storage detail the scripts
/// need but teachers should not have to think about: it is hidden in the
/// display and appended automatically when a new name is added.
struct StringListEditorView: View {

    // MARK: - Stored properties

    let title: String

    /// True for Markdown file lists: hide ".md" in the UI, append it in
    /// the stored value.
    var hidesMarkdownExtension: Bool = false

    @Binding var items: [String]

    var onRemove: ((String) -> Void)? = nil
    var onAdd: ((String) -> Void)? = nil
    var protection: ((String) -> ItemProtection)? = nil

    /// Why a proposed new name cannot be used, or nil when it can. Pure and
    /// asked on every keystroke, so the Rename button can be disabled with the
    /// reason showing rather than refusing after the fact.
    var renameProblem: ((_ oldName: String, _ newName: String, _ finishing: Bool) -> String?)? = nil

    /// Asked once when the rename sheet opens, not on every keystroke: it
    /// touches the filesystem.
    var interruptedRenameTarget: ((_ oldName: String) -> String?)? = nil

    /// Performs the rename. Supplying this is what puts the rename control on
    /// the rows — file lists and the New Course Wizard leave it nil, the
    /// wizard because its course does not exist on disk yet.
    /// Performs the rename. `async`, and that is not decoration: it moves
    /// folders and then reads every Markdown page in the course. On a local
    /// disk that is milliseconds, but Obsidian vaults commonly live in iCloud
    /// Drive, where reading a page that has been evicted downloads it first —
    /// so on the main thread this would freeze the whole app for as long as
    /// the network takes, once per page.
    var onRename: ((_ oldName: String, _ newName: String) async -> RenameResult)? = nil

    /// Something to tell the teacher after the list changed. Returning nil
    /// says nothing.
    var noticeAfterChange: ((_ name: String, _ change: ListChange) -> String?)? = nil

    @State var newItemName: String = ""
    @State var pendingRemoval: PendingRemoval? = nil
    @State var activeExplanation: ActiveExplanation? = nil
    @State var pendingRename: PendingRename? = nil
    @State var proposedName: String = ""
    @State var renameFailure: String? = nil
    @State var isRenaming: Bool = false
    @State var notice: String? = nil
    @State var selectedRowID: String? = nil
    @State var isAddingItem: Bool = false

    /// Why the selected entry cannot be removed, shown from the − button.
    /// Its OWN state, apart from `activeExplanation` (the row's info
    /// button): two popovers presented from one state were measured to
    /// open two popover windows, one of them silently unseen.
    @State var removalExplanation: ActiveExplanation? = nil

    @FocusState var addFieldIsFocused: Bool

    /// Read so the keyboard obeys a disabled section — see
    /// `MembershipToggleListView.isEnabled`.
    @Environment(\.isEnabled) var isEnabled: Bool

    // MARK: - Computed properties

    /// The light grey prompt inside the empty Add field.
    var promptText: String {
        if hidesMarkdownExtension {
            return "Type new file name here"
        }
        return "Type new folder name here"
    }

    /// The label for the add control, keyed to the list's kind.
    var addLabel: String {
        if hidesMarkdownExtension {
            return "Add new file…"
        }
        return "Add new folder…"
    }

    /// The label for the − control, keyed to the list's kind.
    var removeLabel: String {
        if hidesMarkdownExtension {
            return "Remove Selected File"
        }
        return "Remove Selected Folder"
    }

    /// One row per entry, in the order stored.
    var rows: [ListTableRow] {
        return ListTableMetrics.positionedRows(from: items)
    }

    /// The stored name of the selected row, or nil when none is selected.
    var selectedItem: String? {
        return ListTableMetrics.name(ofRowWithID: selectedRowID, in: rows)
    }

    /// True when what is typed in the add popover would be added: not
    /// empty, not the reserved name, not already in the list.
    var canAdd: Bool {
        return StringListEditorView.addableName(
            newItemName, to: items, appendingMarkdownExtension: hidesMarkdownExtension
        ) != nil
    }

    var pendingRemovalIsPresented: Binding<Bool> {
        return Binding(
            get: {
                return pendingRemoval != nil
            },
            set: { isPresented in
                if !isPresented {
                    pendingRemoval = nil
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            // The table and its +/− footer are one bordered unit, the way a
            // macOS list with add and remove buttons is drawn everywhere
            // else on the system.
            VStack(alignment: .leading, spacing: 0) {
                nameTable
                ListAddRemoveFooter(
                    addLabel: addLabel,
                    removeLabel: removeLabel,
                    title: title,
                    canRemove: selectedItem != nil,
                    onAdd: {
                        newItemName = ""
                        isAddingItem = true
                    },
                    onRemove: {
                        if let selectedItem {
                            requestRemoval(of: selectedItem)
                        }
                    },
                    isAdding: $isAddingItem,
                    removalExplanation: $removalExplanation
                ) {
                    addPopover
                }
            }

            // **Said in place, deliberately NOT in an alert.** This used to be
            // a second `.alert` on this same view, and it crashed the app: a
            // SwiftUI view presents one thing at a time, and `performRename`
            // dismissed the rename SHEET and raised the alert in the same
            // breath — `AppKitDialogBridge.updateExistingAlert` reconciling an
            // alert while `NSSheetMoveHelper closeSheet` was still animating,
            // EXC_BAD_ACCESS. Found by driving the real app on 2026-09-04;
            // every unit test passed. The project already had the rule written
            // down (`shared-rules.json` → `siteHealth.repair.oneAlertAtATime`)
            // and this broke it. Inline is also simply better here: what these
            // sentences say — that a folder was created, that a removed folder
            // is still on disk — is a note about the list the teacher is
            // looking at, not news that deserves to interrupt them.
            if let notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityIdentifier("listNotice-\(title)")
            }
        }
        .padding(.vertical, 4)
        .alert(
            pendingRemoval?.title ?? "",
            isPresented: pendingRemovalIsPresented,
            presenting: pendingRemoval
        ) { removal in
            Button("Remove", role: .destructive) {
                removeItem(named: removal.item)
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { removal in
            Text(removal.message)
        }
        .sheet(item: $pendingRename) { rename in
            renameSheet(for: rename.item, interruptedTarget: rename.interruptedRenameTarget)
        }
    }

    // MARK: - The table

    /// The names, one row each, in the order they are stored.
    ///
    /// Each row's protection is asked for HERE and handed to its cell as a
    /// value — never asked from inside the cell. See
    /// `MembershipToggleListView.protectionsAsDrawn()` for the crash that
    /// rule prevents (issue #266); this table survived it only because of
    /// which question it happened to be given.
    var nameTable: some View {
        let protections: [String: ItemProtection] = protectionsAsDrawn()
        return Table(rows, selection: $selectedRowID) {
            TableColumn(title) { (row: ListTableRow) in
                nameCell(for: row.name, protection: protections[row.name] ?? .ordinary)
            }
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .tableColumnHeaders(.hidden)
        .frame(height: ListTableMetrics.height(forRowCount: rows.count, showsHeader: false))
        .overlay(alignment: .leading) {
            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu(forSelectionType: String.self) { rowIDs in
            if let item = ListTableMetrics.contextMenuTarget(forRowIDs: rowIDs, in: rows, isEnabled: isEnabled) {
                if onRename != nil {
                    Button("Rename…") {
                        beginRename(of: item)
                    }
                }
                Button("Remove") {
                    requestRemoval(of: item)
                }
            }
        } primaryAction: { rowIDs in
            // A double-click renames, where renaming is offered.
            guard isEnabled, onRename != nil else {
                return
            }
            if let item = ListTableMetrics.name(ofRowWithID: rowIDs.first, in: rows) {
                beginRename(of: item)
            }
        }
        .onDeleteCommand {
            // See `isEnabled`: a disabled table still takes keys.
            guard isEnabled else {
                return
            }
            if let selectedItem {
                requestRemoval(of: selectedItem)
            }
        }
        .accessibilityIdentifier("table-\(title)")
    }

    /// One row: the name, then — as before the table — the rename pencil
    /// and, for a name that cannot be removed, the button that says why.
    @ViewBuilder
    func nameCell(for item: String, protection itemProtection: ItemProtection) -> some View {
        let displayName: String = StringListEditorView.displayName(for: item, hidingMarkdownExtension: hidesMarkdownExtension)
        HStack {
            Text(displayName)
            Spacer()
            // Offered even on a row whose REMOVAL is blocked: "All
            // Classes" can never be removed and can perfectly well be
            // called something else, and conflating the two would make
            // the one folder every course has the only one a teacher
            // cannot rename.
            if onRename != nil {
                Button("Rename \(item)", systemImage: "pencil") {
                    beginRename(of: item)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("rename-\(item)")
            }
            if case .blocked(let reason) = itemProtection {
                Button("Why \(displayName) can’t be removed", systemImage: "info.circle") {
                    activeExplanation = ActiveExplanation(item: item, reason: reason)
                    ActivityTrail.note(.removalBlocked, "was told " + item + " cannot be removed from " + title + " — " + reason)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("whyBlocked-\(item)")
                .help(reason)
                .popover(item: rowExplanationBinding(for: item), arrowEdge: .trailing) { explanation in
                    ExplanationPopoverText(reason: explanation.reason)
                }
            }
        }
    }

    // MARK: - The add popover

    /// What + opens: a field, Cancel and Add. A popover rather than an
    /// editable new row, because a popover is its own window and its field
    /// takes the keyboard at once, and a half-typed name never becomes a row
    /// that Space, Delete or a selection could act on.
    var addPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(addLabel, text: $newItemName, prompt: Text(promptText))
                .textFieldStyle(.roundedBorder)
                .focused($addFieldIsFocused)
                .onSubmit {
                    if canAdd {
                        addNewItem()
                        isAddingItem = false
                    }
                }
                .accessibilityIdentifier("addField-\(title)")
            HStack {
                Spacer()
                Button("Cancel") {
                    isAddingItem = false
                }
                .keyboardShortcut(.cancelAction)
                // Disabled rather than closing on a name that would not be
                // added: a popover that closed on "media" would read as if
                // the folder had been added.
                Button("Add") {
                    addNewItem()
                    isAddingItem = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
                .accessibilityIdentifier("addConfirm-\(title)")
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            addFieldIsFocused = true
        }
    }

    // MARK: - The rename sheet

    @ViewBuilder
    func renameSheet(for item: String, interruptedTarget: String?) -> some View {
        // Only the rename that was actually interrupted may skip the clash
        // check — a pure string comparison here, with the filesystem question
        // already answered when the sheet opened.
        let finishing: Bool = interruptedTarget?.caseInsensitiveCompare(
            proposedName.trimmingCharacters(in: .whitespaces)
        ) == .orderedSame
        let problem: String? = renameProblem?(item, proposedName, finishing)
        VStack(alignment: .leading, spacing: 12) {
            Text(SpecialNames.renameFolderTitle(for: item))
                .font(.headline)
            TextField("New name", text: $proposedName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("renameField")
                .onSubmit {
                    Task { await performRename(of: item, finishing: finishing) }
                }
            Text(SpecialNames.renameFolderExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let sentence = renameFailure ?? problem {
                Text(sentence)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("renameProblem")
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    pendingRename = nil
                }
                .keyboardShortcut(.cancelAction)
                if isRenaming {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                Button("Rename") {
                    Task { await performRename(of: item, finishing: finishing) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || isRenaming)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Functions

    /// The protection of every row, worked out once per drawing of the table
    /// and handed to the cells — the rule `nameTable` explains.
    func protectionsAsDrawn() -> [String: ItemProtection] {
        var protections: [String: ItemProtection] = [:]
        for row in rows {
            if protections[row.name] == nil {
                protections[row.name] = protection?(row.name) ?? .ordinary
            }
        }
        return protections
    }

    /// How one stored item appears in the list.
    static func displayName(for item: String, hidingMarkdownExtension: Bool) -> String {
        if hidingMarkdownExtension && item.hasSuffix(".md") {
            return String(item.dropLast(3))
        }
        return item
    }

    /// Turns what the teacher typed into the stored form: trimmed, with
    /// ".md" appended for file lists when it was not typed. Returns nil
    /// for names that must not be added.
    static func normalizedItemName(_ rawName: String, appendingMarkdownExtension: Bool) -> String? {
        var trimmed: String = rawName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return nil
        }
        if trimmed.lowercased() == "media" {
            // Plantoir manages the Media folder itself; the wizard refuses this
            // name too.
            //
            // Case-INSENSITIVELY, because the filesystem is: "media" typed here
            // was accepted, then collided with the folder Plantoir links in,
            // and the two were the same directory on disk with different names
            // in the config.
            return nil
        }
        if appendingMarkdownExtension && !trimmed.hasSuffix(".md") {
            trimmed = trimmed + ".md"
        }
        return trimmed
    }

    /// The stored form of a typed name when it would be ADDED to `items`,
    /// or nil when it would not: empty, the reserved name, or already there.
    /// What keeps the add popover's Add button disabled.
    static func addableName(_ rawName: String, to items: [String], appendingMarkdownExtension: Bool) -> String? {
        guard let normalized = StringListEditorView.normalizedItemName(rawName, appendingMarkdownExtension: appendingMarkdownExtension) else {
            return nil
        }
        if items.contains(normalized) {
            return nil
        }
        return normalized
    }

    /// Adds what is typed in the add popover, then clears the field.
    func addNewItem() {
        add(typedName: newItemName)
        newItemName = ""
    }

    /// Adds one typed name — the whole of what adding does, apart from the
    /// field it was typed into, so a test can run it with a name of its own.
    func add(typedName: String) {
        guard let normalized = StringListEditorView.normalizedItemName(typedName, appendingMarkdownExtension: hidesMarkdownExtension) else {
            return
        }
        if !items.contains(normalized) {
            items.append(normalized)
            onAdd?(normalized)
            notice = noticeAfterChange?(normalized, .added)
        }
    }

    /// Asks to remove one entry — what −, the Delete key and the row's
    /// Remove all do, and the ONLY way any of them removes anything, so no
    /// path can skip the list's protection.
    ///
    /// Ordinary: removed at once. Consequential: the question is asked, and
    /// returned so a caller outside a window can answer it. Blocked: nothing
    /// is removed, the reason is shown from the − button, and the trail
    /// records that the teacher was told — the same sentence and the same
    /// line as the row's info button.
    @discardableResult
    func requestRemoval(of item: String) -> PendingRemoval? {
        let state: ItemProtection = protection?(item) ?? .ordinary
        switch state {
        case .blocked(let reason):
            removalExplanation = ActiveExplanation(item: item, reason: reason)
            ActivityTrail.note(.removalBlocked, "was told " + item + " cannot be removed from " + title + " — " + reason)
            return nil
        case .consequential(let alertTitle, let message):
            let removal: PendingRemoval = PendingRemoval(item: item, title: alertTitle, message: message)
            pendingRemoval = removal
            return removal
        case .ordinary:
            removeItem(named: item)
            return nil
        }
    }

    /// Opens the rename sheet for one entry.
    func beginRename(of item: String) {
        renameFailure = nil
        let interrupted: String? = interruptedRenameTarget?(item)
        // Filled in with the rename that was interrupted, so finishing it is
        // one keypress rather than a remembered name.
        proposedName = interrupted ?? item
        pendingRename = PendingRename(item: item, interruptedRenameTarget: interrupted)
    }

    /// Presents one row's explanation, and only that row's.
    func rowExplanationBinding(for item: String) -> Binding<ActiveExplanation?> {
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

    func removeItem(named name: String) {
        var result: [String] = []
        for item in items {
            if item != name {
                result.append(item)
            }
        }
        items = result
        selectedRowID = nil
        onRemove?(name)
        notice = noticeAfterChange?(name, .removed)
    }

    /// Hands the rename to the caller and reports what came back.
    ///
    /// The list itself is NOT edited here. The caller renames the folder on
    /// disk and rewrites the configuration in one step, and this view's
    /// `items` binding reads that configuration — so editing the array here
    /// too would put the rename in twice, and would put it in even when the
    /// filesystem refused.
    func performRename(of item: String, finishing: Bool) async {
        guard let onRename, !isRenaming else {
            return
        }
        if renameProblem?(item, proposedName, finishing) != nil {
            return
        }
        let newName: String = proposedName.trimmingCharacters(in: .whitespaces)
        isRenaming = true
        defer { isRenaming = false }
        switch await onRename(item, newName) {
        case .renamed(let sentence):
            pendingRename = nil
            renameFailure = nil
            notice = sentence
        case .failed(let sentence):
            renameFailure = sentence
        }
    }
}
