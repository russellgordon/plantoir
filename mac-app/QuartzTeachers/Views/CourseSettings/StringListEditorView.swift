import SwiftUI

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

    @State var newItemName: String = ""

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
                    Button("Remove \(item)", systemImage: "minus.circle") {
                        removeItem(named: item)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
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
        }
        .padding(.vertical, 4)
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
    }
}
