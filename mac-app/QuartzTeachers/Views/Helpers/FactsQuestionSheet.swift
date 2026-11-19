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
///   (`.keyboardShortcut(.cancelAction)`); the action carries no key, and
///   is not drawn red (#987, Russell's ruling Q1 on #975): the teacher chose
///   it deliberately, and Alerts says "Use the destructive style to identify
///   a button that performs a destructive action people didn't deliberately
///   choose." In a sheet a plain button takes no key of its own, so the
///   action is plain; in a SwiftUI `.alert` it would take Return (measured,
///   `AlertKeysTests`), which is why the alerts stay red until the question
///   sheet is redesigned (#1000).
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
/// **Closing without an answer is Cancel (#973, Russell 2026-11-16).** The
/// keys are not the whole story: with Keyboard Navigation off, Command-Period
/// closed the sheet through its binding and `cancel` never ran. So a question
/// is always presented with `.factsQuestionSheet(isPresented:)` or
/// `.factsQuestionSheet(item:)`, never a bare `.sheet`: if the sheet goes
/// away by any route before one of its buttons answered, its `cancel` runs,
/// exactly once. See `FactsQuestionPresentation`.
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
                    // Not red either (#987): the teacher chose this action
                    // on purpose. Alerts: "Use the destructive style to
                    // identify a button that performs a destructive action
                    // people didn't deliberately choose."
                    Button(question.action) {
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

/// Presents a `FactsQuestionSheet` so that closing it without an answer is
/// answering Cancel (#973, Russell 2026-11-16: "make it structural").
///
/// Escape, Command-Period, and whatever else macOS does to end a sheet all
/// close it by setting the presentation's binding to false; with Keyboard
/// Navigation off, Command-Period did only that, and the question was left
/// unanswered. So the binding handed to `.sheet` is this one: when the
/// system sets it to false while the question is still unanswered, the
/// sheet's `cancel` runs first, then the presenter's own state is cleared.
/// `onDismiss` checks the same fact, for a sheet that went away by any
/// other route, and then gets ready for the next time the question is
/// asked.
///
/// `answered` is what makes a second run impossible: both buttons (and
/// `.onExitCommand`) set it before their closure runs, and nothing runs
/// `cancel` once it is set. So Cancel or Escape followed by the sheet
/// closing runs `cancel` once, and going ahead followed by the sheet
/// closing runs nothing more. Nothing is timed. Nothing a teacher sees
/// changes: the sheet, its buttons and their keys are exactly as before.
struct FactsQuestionPresentation: ViewModifier {

    // MARK: - Stored properties

    /// The presenter's own state: true while the question is asked.
    @Binding var isPresented: Bool

    /// The question as the presenter writes it.
    let makeSheet: () -> FactsQuestionSheet

    /// True once this showing of the question has been answered, by one of
    /// its buttons or by Cancel run for it here.
    @State private var answered: Bool = false

    // MARK: - Computed properties

    /// The binding SwiftUI closes the sheet through. A close that arrives
    /// while the question is unanswered is Cancel.
    private var closingIsCancel: Binding<Bool> {
        return Binding(
            get: {
                return isPresented
            },
            set: { (showing: Bool) in
                if !showing && isPresented {
                    cancelIfUnanswered()
                }
                isPresented = showing
            }
        )
    }

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: closingIsCancel, onDismiss: {
                cancelIfUnanswered()
                // Ready for the next time the question is asked.
                answered = false
            }) {
                FactsQuestionSheet(answering: makeSheet(), answered: $answered)
            }
    }

    /// Runs the question's `cancel`, unless it has already been answered.
    private func cancelIfUnanswered() {
        if answered {
            return
        }
        answered = true
        makeSheet().cancel()
    }
}

extension FactsQuestionSheet {

    // MARK: - Initializer

    /// `sheet` with each of its answers first marking the question
    /// `answered` (#973), so the presentation never cancels it again.
    init(answering sheet: FactsQuestionSheet, answered: Binding<Bool>) {
        self.init(
            question: sheet.question,
            identifier: sheet.identifier,
            goAheadIsTheDefault: sheet.goAheadIsTheDefault,
            goAhead: {
                answered.wrappedValue = true
                sheet.goAhead()
            },
            cancel: {
                if answered.wrappedValue {
                    return
                }
                answered.wrappedValue = true
                sheet.cancel()
            }
        )
    }
}

/// `FactsQuestionPresentation` for a question shown for an item, as
/// Replace It… is shown for its warning: the same rule, that closing
/// without an answer is Cancel, exactly once (#973).
///
/// Two routes, each tested on its own (the #973 review):
///
/// - The system closes the sheet through the binding handed to `.sheet`:
///   the showing question's `cancel` runs first, as in
///   `FactsQuestionPresentation`.
/// - The presenter's own item changes, to nil or to another item: the
///   question that WAS showing went away, so `onChange` cancels that one,
///   if it is unanswered. SwiftUI swaps a sheet's content when the item
///   changes and does not dismiss it (measured), so no `onDismiss` comes
///   for the old one; and a dismissal by any route ends with the item nil,
///   so `onChange` sees every one. That makes an `onDismiss` here
///   redundant, and it was taken out rather than left untested.
///
/// The record of what is showing is replaced only in `onChange`, AFTER the
/// old one is settled, so a question can only ever be cancelled as itself:
/// when the item changes from A to B, A is cancelled, never B.
struct FactsQuestionItemPresentation<Item: Identifiable>: ViewModifier {

    // MARK: - Types

    /// The item a question is showing for, and whether that showing has
    /// been answered.
    struct Asking {

        // MARK: - Stored properties

        let item: Item
        var answered: Bool
    }

    // MARK: - Stored properties

    /// The presenter's own state: the item the question is asked about, or
    /// nil.
    @Binding var item: Item?

    /// The question as the presenter writes it for an item.
    let makeSheet: (Item) -> FactsQuestionSheet

    /// The showing now on screen, or nil.
    @State private var asking: Asking?

    // MARK: - Computed properties

    /// The binding SwiftUI closes the sheet through. A close that arrives
    /// while the question is unanswered is Cancel.
    private var closingIsCancel: Binding<Item?> {
        return Binding(
            get: {
                return item
            },
            set: { (shown: Item?) in
                if shown == nil {
                    cancelIfUnanswered()
                }
                item = shown
            }
        )
    }

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .sheet(item: closingIsCancel) { (shown: Item) in
                FactsQuestionSheet(answering: makeSheet(shown), answered: answered(for: shown))
            }
            .onChange(of: item?.id, initial: true) { (previous: Item.ID?, current: Item.ID?) in
                if previous != current {
                    // The question that was showing went away.
                    cancelIfUnanswered()
                }
                if let item {
                    asking = Asking(item: item, answered: false)
                } else {
                    asking = nil
                }
            }
    }

    /// Whether the showing for `shown` has been answered. Setting it marks
    /// that showing, and no other.
    private func answered(for shown: Item) -> Binding<Bool> {
        return Binding(
            get: {
                guard let asking, asking.item.id == shown.id else {
                    return false
                }
                return asking.answered
            },
            set: { (isAnswered: Bool) in
                if let current = asking, current.item.id == shown.id {
                    asking = Asking(item: current.item, answered: isAnswered)
                }
            }
        )
    }

    /// Runs `cancel` for the showing on record, unless it has been
    /// answered; it is then answered, so `cancel` never runs for it twice.
    private func cancelIfUnanswered() {
        guard let current = asking, !current.answered else {
            return
        }
        asking = Asking(item: current.item, answered: true)
        makeSheet(current.item).cancel()
    }
}

extension View {

    /// Shows a question with its facts while `isPresented` is true; closed
    /// without an answer, by any route, it is answered Cancel (#973).
    func factsQuestionSheet(
        isPresented: Binding<Bool>,
        content: @escaping () -> FactsQuestionSheet
    ) -> some View {
        return modifier(FactsQuestionPresentation(isPresented: isPresented, makeSheet: content))
    }

    /// Shows a question with its facts about `item` while it is set; closed
    /// without an answer, by any route, it is answered Cancel (#973).
    func factsQuestionSheet<Item: Identifiable>(
        item: Binding<Item?>,
        content: @escaping (Item) -> FactsQuestionSheet
    ) -> some View {
        return modifier(FactsQuestionItemPresentation(item: item, makeSheet: content))
    }
}
