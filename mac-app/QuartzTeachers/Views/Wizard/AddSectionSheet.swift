import SwiftUI

/// A small dialog for adding one section to an existing course: a number
/// field with a stepper, validated as you type in the same orange every
/// other warning wears, so a section that already exists is called out
/// before the Add button will do anything.
struct AddSectionSheet: View {

    // MARK: - Stored properties

    let course: Course

    /// Called after the section has been created, so the sidebar can reload
    /// and select it.
    let onAdd: (Int) -> Void

    @Environment(\.dismiss) var dismiss

    /// The typed section number. Text rather than Int so a half-typed or
    /// invalid entry can be seen, warned about, and corrected in place.
    @State var entry: String = ""

    /// A failure from the add itself (not the typing) — say it in the same
    /// warning slot and leave the sheet up so the entry can be corrected.
    @State var addProblem: String?

    // MARK: - Computed properties

    var existingSections: [Int] {
        return course.sectionNumbers
    }

    /// The live warning under the field, if the entry has earned one.
    var entryProblem: String? {
        if let addProblem {
            return addProblem
        }
        return SectionAdder.entryProblem(entry, existing: existingSections, courseCode: course.code)
    }

    var canAdd: Bool {
        return SectionAdder.entryIsAddable(entry, existing: existingSections)
    }

    /// The sections that already exist, listed so the choice is informed:
    /// "ICS3U already has sections 1 and 3."
    var existingSectionsSentence: String {
        let numbers: [Int] = existingSections
        var spelled: [String] = []
        for number in numbers {
            spelled.append("\(number)")
        }
        if spelled.isEmpty {
            return "\(course.code) has no sections yet."
        }
        if spelled.count == 1 {
            return "\(course.code) already has section \(spelled[0])."
        }
        let allButLast: String = spelled.dropLast().joined(separator: ", ")
        return "\(course.code) already has sections \(allButLast) and \(spelled[spelled.count - 1])."
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Section to \(course.displayCode)")
                .font(.headline)

            Text(existingSectionsSentence)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("Section number:")
                TextField("", text: $entry)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("addSectionNumberField")
                    .onChange(of: entry) {
                        // Integer entry only: anything that is not a digit
                        // never lands in the field.
                        var digitsOnly: String = ""
                        for character in entry {
                            if character.isNumber {
                                digitsOnly.append(character)
                            }
                        }
                        if digitsOnly != entry {
                            entry = digitsOnly
                        }
                        addProblem = nil
                    }
                Stepper("Section number", onIncrement: {
                    step(by: 1)
                }, onDecrement: {
                    step(by: -1)
                })
                .labelsHidden()
                .accessibilityIdentifier("addSectionStepper")
            }

            // The warning keeps a reserved line so the sheet does not jump
            // as it appears and disappears.
            Text(entryProblem ?? " ")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(minHeight: 26, alignment: .topLeading)
                .accessibilityIdentifier("addSectionWarning")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add Section") {
                    performAdd()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
                .accessibilityIdentifier("addSectionConfirmButton")
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            entry = "\(SectionAdder.suggestedNumber(existing: existingSections))"
        }
    }

    // MARK: - Functions

    /// The stepper walks the typed number up and down, never below 1. An
    /// empty field steps to the suggested number rather than from nowhere.
    func step(by amount: Int) {
        guard let current = Int(entry) else {
            entry = "\(SectionAdder.suggestedNumber(existing: existingSections))"
            return
        }
        let next: Int = max(current + amount, 1)
        entry = "\(next)"
        addProblem = nil
    }

    func performAdd() {
        guard let number = Int(entry) else {
            return
        }
        do {
            try SectionAdder.addSection(number, to: course)
        } catch {
            // Stay open with the reason in the warning slot — the whole
            // point is a chance to correct and try again.
            addProblem = error.localizedDescription
            return
        }
        dismiss()
        onAdd(number)
    }
}
