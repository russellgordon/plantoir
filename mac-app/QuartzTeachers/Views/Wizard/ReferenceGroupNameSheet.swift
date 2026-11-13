import SwiftUI

/// New Group… and Rename Group… on the Reference Courses shelf (#572, third
/// piece): one Name field, the name rule's sentence under it as the teacher
/// types, and one button that checks it all again at the press.
///
/// Renaming touches nothing but the shelf's arrangement: no course folder is
/// renamed, and the courses in the group stay in it.
struct ReferenceGroupNameSheet: View {

    // MARK: - Types

    /// What the sheet is for.
    enum Purpose: Equatable {
        /// New Group….
        case make

        /// Rename Group… on a made group or the no-year group.
        case rename(ReferenceShelfGroup)
    }

    // MARK: - Stored properties

    let purpose: Purpose

    @Environment(\.dismiss) var dismiss
    @Environment(WorkspaceModel.self) var workspace

    @State var name: String

    /// A refusal from the press itself (the arrangement could not be read or
    /// saved), shown until the name changes.
    @State var pressProblem: String?

    // MARK: - Computed properties

    var renaming: ReferenceShelf.Place? {
        if case .rename(let group) = purpose {
            return group.place
        }
        return nil
    }

    var title: String {
        switch purpose {
        case .make:
            return ReferenceGroupWording.newGroupTitle
        case .rename:
            return ReferenceGroupWording.renameGroupTitle
        }
    }

    var buttonTitle: String {
        switch purpose {
        case .make:
            return ReferenceGroupWording.createButton
        case .rename:
            return ReferenceGroupWording.renameButton
        }
    }

    var problem: String? {
        if let pressProblem {
            return pressProblem
        }
        return workspace.referenceGroupNameProblem(name, renaming: renaming)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(ReferenceGroupWording.nameLabel, text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(ReferenceGroupWording.nameLabel)
                .accessibilityIdentifier("referenceGroupName")
                .onSubmit {
                    press()
                }
                .onChange(of: name) {
                    pressProblem = nil
                }

            if let problem, !name.isEmpty || pressProblem != nil {
                Text(problem)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("referenceGroupNameProblem")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(buttonTitle) {
                    press()
                }
                .defaultButton(isEnabled: problem == nil)
                .accessibilityIdentifier("referenceGroupNameButton")
            }
        }
        .padding([.horizontal, .bottom], 20)
        .sheetTitle(title)
        .frame(width: 380)
    }

    // MARK: - Initializer

    init(purpose: Purpose) {
        self.purpose = purpose
        switch purpose {
        case .make:
            _name = State(initialValue: "")
        case .rename(let group):
            _name = State(initialValue: group.title)
        }
    }

    // MARK: - Functions

    /// Checks the name again and makes or renames the group. The sheet stays
    /// up with the sentence when it could not be done.
    func press() {
        if problem != nil {
            return
        }
        var refusal: String?
        switch purpose {
        case .make:
            refusal = workspace.makeReferenceGroup(named: name)
        case .rename(let group):
            refusal = workspace.renameReferenceGroup(group, to: name)
        }
        if let refusal {
            pressProblem = refusal
            return
        }
        dismiss()
    }
}
