import AppKit
import SwiftUI

/// The Class Dates sheet's typing box (Class Dates, and Add Class, Make Room
/// and Roll Over, which open it): one date per line, where Tab and Shift-Tab
/// move to the next and previous control instead of typing a tab character
/// (#997; Russell's ruling Q-C on #975, 2026-11-18).
///
/// A plain `TextEditor` is a text view, and a text view types a tab, as the
/// HIG's Keyboards page expects of one (Control-Tab moves on from it). The
/// box only ever holds dates, so a tab in it is never wanted, and the Text
/// fields page asks that "tabbing between multiple fields flows as people
/// expect". The text view below is AppKit's own, so typing, Return, undo,
/// pasting and VoiceOver are the text view's; only the two tab commands are
/// answered here, through the delegate's `doCommandBy`, the way AppKit
/// documents a text view handing Tab to the key view loop. Control-Tab
/// still moves on as well, as it does from any text view.
struct ClassDatesTextBox: NSViewRepresentable {

    // MARK: - Stored properties

    @Binding var text: String

    /// What VoiceOver calls the box (#993, D41).
    let accessibilityName: String

    /// The box's identifier, for tests.
    let identifier: String

    // MARK: - Functions

    func makeCoordinator() -> Coordinator {
        return Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView: NSScrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        let textView: ClassDatesTextView = ClassDatesTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.setAccessibilityLabel(accessibilityName)
        textView.setAccessibilityIdentifier(identifier)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        // Only when the binding was changed from outside: writing the same
        // string back while the teacher types would move the insertion
        // point to the end.
        if textView.string != text {
            textView.string = text
        }
    }

    // MARK: - Coordinator

    /// Keeps the binding in step with the text view, and turns Tab and
    /// Shift-Tab into moves along the window's key view loop.
    final class Coordinator: NSObject, NSTextViewDelegate {

        // MARK: - Stored properties

        var text: Binding<String>

        // MARK: - Initializer

        init(text: Binding<String>) {
            self.text = text
        }

        // MARK: - Functions

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // From the scroll view first, which is the box's place in the
            // window's loop, as a text field's own Tab moves on from the
            // field rather than from the editor it borrows; from the text
            // view itself if that left the focus where it was.
            guard let window = textView.window else {
                return false
            }
            let box: NSView = textView.enclosingScrollView ?? textView
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                window.selectKeyView(following: box)
                if window.firstResponder === textView {
                    window.selectKeyView(following: textView)
                }
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                window.selectKeyView(preceding: box)
                if window.firstResponder === textView {
                    window.selectKeyView(preceding: textView)
                }
                return true
            }
            return false
        }
    }
}

/// The box's text view: AppKit's own, which takes the focus when the box
/// is put in a window, as the `TextEditor` before it did when the sheet
/// opened (the inventory's captures of 2026-11-18, with Keyboard Navigation
/// on and off). Without this the sheet opened with the focus on the route
/// picker (Keyboard Navigation on), measured in the running app on
/// 2026-11-20, and a teacher who pastes straight away pasted nowhere.
final class ClassDatesTextView: NSTextView {

    // MARK: - Stored properties

    /// Once only: a view moved again (as SwiftUI may) must not take the
    /// focus back from wherever Tab has put it since.
    var hasTakenTheFocus: Bool = false

    // MARK: - Functions

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !hasTakenTheFocus else {
            return
        }
        hasTakenTheFocus = true
        window.makeFirstResponder(self)
    }
}
