import SwiftUI

/// A list of checkboxes controlling membership in a string list — used for
/// the "hidden" and "expandable" choices, mirroring the wizard's
/// multi-select prompts, and for graded folders with protection.
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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            if allItems.isEmpty {
                Text("No folders or files defined yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(allItems, id: \.self) { item in
                // File entries hide their ".md" storage extension, matching
                // the list editors.
                let isMember: Bool = members.contains(item)
                let itemProtection: ItemProtection = isMember ? (protection?(item) ?? .ordinary) : .ordinary

                HStack {
                    Toggle(
                        StringListEditorView.displayName(for: item, hidingMarkdownExtension: true),
                        isOn: membershipBinding(for: item, protection: itemProtection)
                    )
                    .accessibilityIdentifier("toggle-\(item)")

                    if case .blocked(let reason) = itemProtection {
                        Button {
                            activeExplanation = ActiveExplanation(item: item, reason: reason)
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("whyBlockedToggle-\(item)")
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
                            Text(explanation.reason)
                                .font(.callout)
                                .padding(12)
                                .frame(maxWidth: 280)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Functions

    func membershipBinding(for item: String, protection: ItemProtection) -> Binding<Bool> {
        return Binding(
            get: {
                return members.contains(item)
            },
            set: { isMember in
                if isMember {
                    if !members.contains(item) {
                        members.append(item)
                    }
                } else {
                    if case .blocked(let reason) = protection {
                        activeExplanation = ActiveExplanation(item: item, reason: reason)
                        return
                    }
                    var result: [String] = []
                    for member in members {
                        if member != item {
                            result.append(member)
                        }
                    }
                    members = result
                }
            }
        )
    }
}
