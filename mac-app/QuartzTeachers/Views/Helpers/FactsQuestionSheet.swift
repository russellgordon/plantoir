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
/// **The keys follow Apple's Human Interface Guidelines (#973, Russell
/// 2026-11-15).** Each visible button carries at most one key, and there is
/// no hidden control.
///
/// - On a question before something hard to take back
///   (`goAheadIsTheDefault` false) there is NO default button, so Return
///   does nothing: the sheet stays open and nothing is answered. Alerts,
///   https://developer.apple.com/design/human-interface-guidelines/alerts:
///   "Note that you don't want to make a Cancel button the default button",
///   and "If you want to encourage people to read an alert and not just
///   automatically press Return to dismiss it, avoid making any button the
///   default button." The cancelling button carries Escape
///   (`.keyboardShortcut(.cancelAction)`); the action carries no key.
/// - Where going ahead is the default (`goAheadIsTheDefault` true), the
///   action is the default button (Return) and the cancelling button
///   carries Escape. Buttons,
///   https://developer.apple.com/design/human-interface-guidelines/buttons:
///   the primary button is "the button people are most likely to choose".
///
/// The cancelling button leads and the action trails in both: "Always place
/// the default button on the trailing side of a row"; "Cancel buttons are
/// typically on the leading side" (Alerts).
///
/// Escape is a key equivalent, not `.onExitCommand` alone (#973):
/// `.onExitCommand` fires only while something inside the sheet holds the
/// keys, and with Keyboard Navigation off, the macOS default, nothing does,
/// so SwiftUI closed the sheet through its binding without running `cancel`.
/// `QuestionKeysTests` presses each key on each question and checks which
/// closure answered.
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
    /// default). False for every question before something hard to take
    /// back, where no button is the default and Return does nothing (#973).
    /// The cancelling button answers Escape either way.
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
                // Cancel leads and the action trails, as the Alerts page
                // places them (#973). Cancel carries Escape and nothing else.
                Button(question.cancel, role: .cancel) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("\(identifier)Cancel")
                if goAheadIsTheDefault {
                    // The default button: Return, and nothing else.
                    Button(question.action) {
                        goAhead()
                    }
                    .defaultButton(isEnabled: true)
                    .accessibilityIdentifier("\(identifier)GoAhead")
                } else {
                    // No default button at all, so a Return typed out of
                    // habit answers nothing (Russell's ruling 1 on #973).
                    Button(question.action, role: .destructive) {
                        goAhead()
                    }
                    .accessibilityIdentifier("\(identifier)GoAhead")
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
