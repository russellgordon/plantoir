import SwiftUI

/// One fact in a question's sheet: a few words of label, a few of value
/// (#834).
nonisolated struct FactsQuestionRow: Identifiable, Equatable, Sendable {

    // MARK: - Stored properties

    let label: String
    let value: String

    // MARK: - Computed properties

    var id: String {
        return label
    }
}

/// A question that asks before something hard to take back (#834, Russell
/// 2026-11-13: "This dialog reads as a wall of text. Separate pertinent
/// information from the message the app is trying to convey."): a title that
/// asks, ONE short sentence saying what will happen, then the facts as
/// labelled rows, then the buttons.
nonisolated struct FactsQuestion: Equatable, Sendable {

    // MARK: - Stored properties

    let title: String
    let message: String

    /// Only the facts there are: a fact that is missing is no row at all,
    /// never a blank one.
    let rows: [FactsQuestionRow]

    /// The button that goes ahead.
    let action: String

    let cancel: String
}

/// The sheet every such question is shown in (#834): Replace It…, Remove
/// Group and Start the Groups Again.
///
/// **Cancel answers Return AND Escape.** In an alert a button carries one
/// key, so Cancel could have Return or Escape and not both (measured, #832:
/// `documentation/09-mac-app.md` → "Return and Escape in this release's
/// questions"). A sheet can have both: Cancel is the default button
/// (`.defaultButton(isEnabled:)`, Return) and the sheet's own Escape is
/// Cancel too (`.onExitCommand`). The button that goes ahead takes no key.
///
/// The facts are a grouped `Form`, the system's own form styling, with
/// scrolling off and its height its rows': `FactsQuestionTests` measures
/// that the form shows all of what it holds (a fixed height per row cut the
/// last row off whenever a value wrapped). VoiceOver reads the title, the message,
/// then each row as "label, value".
struct FactsQuestionSheet: View {

    // MARK: - Stored properties

    let question: FactsQuestion

    /// Prefixes the controls' accessibility identifiers.
    let identifier: String

    /// True only for a question whose going ahead is the safe and expected
    /// answer, so it is the default and takes Return (#833: after Change
    /// Password, Share Again sends the new password, and Russell made it the
    /// default). Cancel then answers Escape alone. False for every question
    /// before something hard to take back.
    var goAheadIsTheDefault: Bool = false

    let goAhead: () -> Void
    let cancel: () -> Void

    /// Wide enough for a backup's name on one line.
    static let width: CGFloat = 460

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    ForEach(question.rows) { (row: FactsQuestionRow) in
                        LabeledContent(row.label) {
                            Text(row.value)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("\(identifier)Row")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            // As tall as its rows: a sheet is hosted at the width it sets
            // itself, so this is not the detail column's rigid sentence
            // (`documentation/09-mac-app.md` → "A blank window").
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                // The default button sits on the right, as macOS places it.
                if goAheadIsTheDefault {
                    Button(question.cancel, role: .cancel) {
                        cancel()
                    }
                    .accessibilityIdentifier("\(identifier)Cancel")
                    Button(question.action) {
                        goAhead()
                    }
                    .defaultButton(isEnabled: true)
                    .accessibilityIdentifier("\(identifier)GoAhead")
                } else {
                    Button(question.action, role: .destructive) {
                        goAhead()
                    }
                    .accessibilityIdentifier("\(identifier)GoAhead")
                    Button(question.cancel, role: .cancel) {
                        cancel()
                    }
                    .defaultButton(isEnabled: true)
                    .accessibilityIdentifier("\(identifier)Cancel")
                }
            }
            .padding([.horizontal, .bottom], 20)
        }
        .sheetTitle(question.title, identifier: "\(identifier)Title", explanation: {
            Text(question.message)
                .accessibilityIdentifier("\(identifier)Message")
        })
        .frame(width: FactsQuestionSheet.width)
        .onExitCommand {
            cancel()
        }
    }
}
