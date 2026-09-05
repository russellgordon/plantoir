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

/// Edits a list of names (folders or files): shows the current entries with
/// remove buttons, and a field for adding a new entry.
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
    var renameProblem: ((_ oldName: String, _ newName: String) -> String?)? = nil

    /// Performs the rename. Supplying this is what puts the rename control on
    /// the rows — file lists and the New Course Wizard leave it nil, the
    /// wizard because its course does not exist on disk yet.
    var onRename: ((_ oldName: String, _ newName: String) -> RenameResult)? = nil

    /// Something to tell the teacher after the list changed. Returning nil
    /// says nothing.
    var noticeAfterChange: ((_ name: String, _ change: ListChange) -> String?)? = nil

    @State var newItemName: String = ""
    @State var pendingRemoval: PendingRemoval? = nil
    @State var activeExplanation: ActiveExplanation? = nil
    @State var pendingRename: PendingRename? = nil
    @State var proposedName: String = ""
    @State var renameFailure: String? = nil
    @State var notice: String? = nil

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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            }

            ForEach(items, id: \.self) { item in
                HStack {
                    Text(StringListEditorView.displayName(for: item, hidingMarkdownExtension: hidesMarkdownExtension))
                    Spacer()
                    // Offered even on a row whose REMOVAL is blocked: "All
                    // Classes" can never be removed and can perfectly well be
                    // called something else, and conflating the two would make
                    // the one folder every course has the only one a teacher
                    // cannot rename.
                    if onRename != nil {
                        Button("Rename \(item)", systemImage: "pencil") {
                            proposedName = item
                            renameFailure = nil
                            pendingRename = PendingRename(item: item)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("rename-\(item)")
                    }
                    let state: ItemProtection = protection?(item) ?? .ordinary
                    switch state {
                    case .blocked(let reason):
                        Button {
                            activeExplanation = ActiveExplanation(item: item, reason: reason)
                            ActivityTrail.note(.removalBlocked, "was told " + item + " cannot be removed from " + title + " — " + reason)
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("whyBlocked-\(item)")
                        .help(reason)
                        .popover(item: Binding(
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
                        ), arrowEdge: .trailing) { explanation in
                            // A fixed width plus fixedSize: a popover
                            // sizes itself to its content, and a Text
                            // with only a maxWidth was measured as one
                            // line and shown truncated ("…") when the
                            // real app was driven.
                            Text(explanation.reason)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 280, alignment: .leading)
                                .padding(12)
                        }

                    case .consequential(let alertTitle, let message):
                        Button("Remove \(item)", systemImage: "minus.circle") {
                            pendingRemoval = PendingRemoval(item: item, title: alertTitle, message: message)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("remove-\(item)")

                    case .ordinary:
                        Button("Remove \(item)", systemImage: "minus.circle") {
                            removeItem(named: item)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("remove-\(item)")
                    }
                }
            }

            HStack {
                TextField(addLabel, text: $newItemName, prompt: Text(promptText))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addNewItem()
                    }
                    .accessibilityIdentifier("addField-\(title)")
                Button(addLabel, systemImage: "plus.circle") {
                    addNewItem()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("addTo-\(title)")
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
        .alert(item: $pendingRemoval) { removal in
            Alert(
                title: Text(removal.title),
                message: Text(removal.message),
                primaryButton: .destructive(Text("Remove")) {
                    removeItem(named: removal.item)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $pendingRename) { rename in
            renameSheet(for: rename.item)
        }
    }

    // MARK: - The rename sheet

    @ViewBuilder
    func renameSheet(for item: String) -> some View {
        let problem: String? = renameProblem?(item, proposedName)
        VStack(alignment: .leading, spacing: 12) {
            Text(SpecialNames.renameFolderTitle(for: item))
                .font(.headline)
            TextField("New name", text: $proposedName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("renameField")
                .onSubmit {
                    performRename(of: item)
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
                Button("Rename") {
                    performRename(of: item)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Functions

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

    func addNewItem() {
        guard let normalized = StringListEditorView.normalizedItemName(newItemName, appendingMarkdownExtension: hidesMarkdownExtension) else {
            newItemName = ""
            return
        }
        if !items.contains(normalized) {
            items.append(normalized)
            onAdd?(normalized)
            notice = noticeAfterChange?(normalized, .added)
        }
        newItemName = ""
    }

    func removeItem(named name: String) {
        var result: [String] = []
        for item in items {
            if item != name {
                result.append(item)
            }
        }
        items = result
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
    func performRename(of item: String) {
        guard let onRename else {
            return
        }
        if renameProblem?(item, proposedName) != nil {
            return
        }
        let newName: String = proposedName.trimmingCharacters(in: .whitespaces)
        switch onRename(item, newName) {
        case .renamed(let sentence):
            pendingRename = nil
            renameFailure = nil
            notice = sentence
        case .failed(let sentence):
            renameFailure = sentence
        }
    }
}
