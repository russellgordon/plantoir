import AppKit

/// Puts the typing focus in the "Input required" alert's answer field when
/// the alert opens (#1019 review).
///
/// Measured on screen on 2026-11-20 (`ProgressCancelKeysTests.
/// testTheQuestionsFieldHasTheFocusWhenTheAlertOpens`, and the opt-in UI
/// test typing with no click): SwiftUI's macOS alert opens with the focus on
/// a button (`_NSAlertButton`), so a teacher who typed at once typed into
/// nothing and Return sent the task an empty answer. `.focused` and
/// `.defaultFocus` on the field were tried and change nothing inside an
/// alert; neither does any accessibility modifier. AppKit's own way to say
/// where an alert's typing goes is the window's first responder (an
/// `NSAlert` with a field is given `initialFirstResponder`), so when the
/// alert's window becomes key this makes its one answer field the first
/// responder. A visible field, chosen by its placeholder; nothing hidden is
/// added, and nothing waits on a timer.
enum QuestionAlertFocus {

    // MARK: - Stored properties

    /// The answer field's placeholder: the alert's only means of naming it
    /// (the alert drops identifiers and labels), shared with the field.
    static let answerPlaceholder: String = "Your answer"

    // MARK: - Functions

    /// When `window` is an attached sheet holding exactly one editable field
    /// with the answer placeholder, and the focus is not already in it,
    /// makes that field the first responder. Returns whether the focus is in
    /// the field afterwards.
    @discardableResult
    static func putTheFocusInTheAnswerField(of window: NSWindow) -> Bool {
        if window.sheetParent == nil {
            return false
        }
        guard let content = window.contentView else {
            return false
        }
        var answerFields: [NSTextField] = []
        collectAnswerFields(in: content, into: &answerFields)
        if answerFields.count != 1 {
            return false
        }
        let field: NSTextField = answerFields[0]
        if fieldHasTheFocus(field, in: window) {
            return true
        }
        return window.makeFirstResponder(field)
    }

    /// Whether `field`, or the editor AppKit lends it while it is typed in,
    /// is `window`'s first responder.
    static func fieldHasTheFocus(_ field: NSTextField, in window: NSWindow) -> Bool {
        if window.firstResponder === field {
            return true
        }
        if let editor = window.firstResponder as? NSTextView, editor.delegate === field {
            return true
        }
        return false
    }

    static func collectAnswerFields(in view: NSView, into result: inout [NSTextField]) {
        if let field = view as? NSTextField, field.isEditable, !field.isHidden, field.placeholderString == answerPlaceholder {
            result.append(field)
        }
        for subview in view.subviews {
            collectAnswerFields(in: subview, into: &result)
        }
    }
}
