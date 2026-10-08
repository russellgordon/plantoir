import SwiftUI
import AppKit

/// The chevron a field with a list behind it wears at its trailing edge — a
/// real `NSButton`, not a SwiftUI `Button` in an overlay (#456).
///
/// Why AppKit: the field it sits on wears the real `.roundedBorder` bezel,
/// which is an `NSTextField` spanning the whole width, and AppKit hands a
/// click to the deepest NSView under the pointer — the text field — before
/// SwiftUI's own layer sees it. A chevron drawn as a plain `.overlay` on top
/// of that bezel was never clicked: the field took the click and placed its
/// caret (found by `testCourseCodeRevealButtonOpensThePopup` the first time
/// the real bezel was tried; a SwiftUI button inside an `NSHostingView` did
/// not fire either). The drawn 24pt chrome this replaced never met this,
/// because its `.plain` field was inset 34pt from the trailing edge, leaving
/// the chevron over nothing but a SwiftUI shape. A real `NSButton`, added to
/// the window after the field, is on top for hit-testing as it is for
/// drawing, and fires like any button.
///
/// The look is the one MEASURED off a real `NSComboBox` on 2026-08-23
/// (`CourseCodePickerView`'s reveal-button constants): 24 x 19pt, a 5pt
/// radius, an untinted fill a shade lighter than the field, the
/// `chevron.down` glyph at 8.5pt semibold in label colour.
struct RevealChevronButton: NSViewRepresentable {

    // MARK: - Stored properties

    /// Identifies the button to the UI tests and to VoiceOver.
    let accessibilityIdentifier: String

    let accessibilityLabel: String

    /// What a click does.
    let action: () -> Void

    // MARK: - Functions

    func makeNSView(context: Context) -> NSButton {
        let button: ChevronNSButton = ChevronNSButton(frame: NSRect(
            x: 0, y: 0,
            width: CourseCodePickerView.revealButtonWidth, height: CourseCodePickerView.revealButtonHeight
        ))
        button.target = context.coordinator
        button.action = #selector(Coordinator.pressed)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        return CGSize(width: CourseCodePickerView.revealButtonWidth, height: CourseCodePickerView.revealButtonHeight)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(action: action)
    }

    // MARK: - Types

    final class Coordinator: NSObject {

        // MARK: - Stored properties

        var action: () -> Void

        // MARK: - Initializer

        init(action: @escaping () -> Void) {
            self.action = action
        }

        // MARK: - Functions

        @objc func pressed() {
            action()
        }
    }
}

/// The button itself: borderless, drawing the measured pill and glyph.
final class ChevronNSButton: NSButton {

    // MARK: - Initializer

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        // The glyph, sized to the 7.5 x 4.5pt one AppKit draws.
        let configuration: NSImage.SymbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: CourseCodePickerView.revealButtonGlyphSize, weight: .semibold
        )
        image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        contentTintColor = NSColor.labelColor
        wantsLayer = true
        layer?.cornerRadius = CourseCodePickerView.revealButtonCornerRadius
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    // MARK: - Functions

    /// The fill, resolved per appearance — `tertiarySystemFill` in dark and
    /// `secondarySystemFill` in light are what match a real combo box's
    /// button (measured, see `CourseCodePickerView.revealButtonFillColor`).
    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor(CourseCodePickerView.revealButtonFillColor).cgColor
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: CourseCodePickerView.revealButtonWidth, height: CourseCodePickerView.revealButtonHeight)
    }

    /// Takes the click even when the window is not key, as a combo box's
    /// arrow does.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    /// The click, taken from the window before AppKit's hit-testing hands
    /// it to the text field underneath.
    ///
    /// Measured (#456, through `testCourseCodeRevealButtonOpensThePopup`):
    /// with the real bezel, a click at this button's own frame reached the
    /// `NSTextField` — it took focus and the button's action never ran —
    /// whether the button was a SwiftUI overlay, a SwiftUI button inside an
    /// `NSHostingView`, or this `NSButton`, and re-adding it above its
    /// siblings changed nothing, because SwiftUI hosts the field and the
    /// overlay in containers of its own whose order is not ours to set. So
    /// the button watches the window's mouse-downs itself: one inside its
    /// frame is its own, performed here and swallowed, so the field never
    /// sees it. Scoped to this window and removed with the button.
    nonisolated(unsafe) private var mouseDownMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        guard window != nil else {
            return
        }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window, self.isEnabled else {
                return event
            }
            let pointInButton: NSPoint = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(pointInButton) else {
                return event
            }
            self.performClick(nil)
            return nil
        }
    }

    deinit {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
    }
}
