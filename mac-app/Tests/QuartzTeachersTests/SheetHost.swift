import AppKit
import ObjectiveC
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// Presents a SwiftUI view as a REAL sheet, OFF screen, so a test can read
/// what only a presented sheet has (#621): whether it is resizable, the size
/// it opens at, the smallest it can be made, and what happens to them when
/// its content changes. `TableHost` cannot answer any of those: it frames
/// its content itself, so the sheet's own sizing never runs.
///
/// Kept off every display, in this order, because a sheet that reaches the
/// screen takes it from whoever is working at this Mac:
/// - the parent window is an `OffScreenWindow`, which AppKit cannot move
///   onto a display, neither as it orders it in nor when the sheet opens
///   (both MEASURED moving it, to (0, 0) and (-320, -239), until v1.8.6);
///   it is placed beyond every display (`TableHost.offScreenOrigin(for:)`)
///   and ordered in BEFORE the sheet is asked for;
/// - the sheet's own window is AppKit's, so `SheetsHungOffScreenStayThere`
///   keeps AppKit from constraining it onto a display;
/// - neither is made key, and the app is never activated;
/// - the sheet's animation is already skipped in this test host
///   (`SheetAnimationSuppressor`), so it moves straight to its place;
/// - and after every pump the sheet's frame is checked against the displays:
///   one that overlaps a display is ordered out at once and recorded in
///   `reachedAScreen`, which every test using this host asserts is false.
///
/// One window this cannot keep off the screen is the test host's own main
/// window: the unit suite runs inside Plantoir, which opens its window at
/// launch, before any test bundle code runs (`SheetAnimationSuppressor`
/// says the same of the alerts some tests raise on it).
@MainActor
final class SheetHost {

    // MARK: - Stored properties

    /// The window the sheet hangs from.
    let window: NSWindow

    /// Whether the sheet is asked for.
    let presentation: SheetHostPresentation

    /// True once the sheet, or the window it hangs from, overlapped a display
    /// and was ordered out.
    private(set) var reachedAScreen: Bool = false

    // MARK: - Computed properties

    /// The presented sheet's window.
    var sheet: NSWindow? {
        return window.attachedSheet
    }

    // MARK: - Initializer

    init<Content: View>(_ content: Content) {
        let size: NSSize = NSSize(width: 1200, height: 900)
        let origin: NSPoint = TableHost.offScreenOrigin(for: size)
        window = OffScreenWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        presentation = SheetHostPresentation()
        SheetsHungOffScreenStayThere.install()
        window.contentView = NSHostingView(rootView: SheetHostRoot(presentation: presentation, content: AnyView(content)))
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        pump()
        presentation.isShown = true
        pump(0.6)
    }

    // MARK: - Functions

    /// Lets SwiftUI and AppKit settle, then checks nothing reached a display.
    func pump(_ seconds: Double = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        keepOffTheScreens()
    }

    /// `pump`, letting the main actor's own queued work run in between —
    /// work started with `Task { @MainActor in }`, such as
    /// `SheetGrowsToItsMinimum`'s, which a run loop turned inside a test
    /// running on the main actor never reaches.
    func settle(turns: Int = 5) async {
        var turn: Int = 0
        while turn < turns {
            await Task.yield()
            pump(0.1)
            turn += 1
        }
    }

    /// Orders out the sheet and its window the moment either overlaps a
    /// display, and says so.
    func keepOffTheScreens() {
        var onAScreen: Bool = TableHost.isOnAScreen(window.frame)
        if let sheet, TableHost.isOnAScreen(sheet.frame) {
            onAScreen = true
        }
        if onAScreen {
            reachedAScreen = true
            sheet?.orderOut(nil)
            window.orderOut(nil)
        }
    }

    /// Resizes the sheet as a drag of its edge would, to `size` of content.
    func resizeSheet(to size: NSSize) {
        sheet?.setContentSize(size)
        pump()
    }

    func close() {
        presentation.isShown = false
        pump(0.1)
        if let sheet {
            window.endSheet(sheet)
            sheet.orderOut(nil)
        }
        window.orderOut(nil)
        window.close()
    }

    /// Every table in the sheet, top first.
    func tables() -> [NSTableView] {
        var found: [NSTableView] = []
        if let content = sheet?.contentView {
            SheetHost.collectTables(in: content, into: &found)
        }
        var ordered: [NSTableView] = []
        for table in found {
            var index: Int = 0
            let top: CGFloat = table.convert(table.bounds, to: nil).maxY
            while index < ordered.count && ordered[index].convert(ordered[index].bounds, to: nil).maxY >= top {
                index = index + 1
            }
            ordered.insert(table, at: index)
        }
        return ordered
    }

    static func collectTables(in view: NSView, into found: inout [NSTableView]) {
        if let table = view as? NSTableView {
            found.append(table)
        }
        for subview in view.subviews {
            collectTables(in: subview, into: &found)
        }
    }
}

/// Whether `SheetHost`'s sheet is asked for: false until the window it hangs
/// from is off screen and ordered in.
@MainActor
@Observable
final class SheetHostPresentation {

    // MARK: - Stored properties

    var isShown: Bool = false
}

/// The parent window's content: nothing, with the sheet hung from it.
struct SheetHostRoot: View {

    // MARK: - Stored properties

    var presentation: SheetHostPresentation
    let content: AnyView

    // MARK: - Body

    var body: some View {
        Color.clear
            .frame(width: 1200, height: 900)
            .sheet(isPresented: Binding(
                get: { return presentation.isShown },
                set: { isShown in presentation.isShown = isShown }
            )) {
                content
            }
    }
}

/// Keeps a sheet hung from an `OffScreenWindow` where AppKit puts it,
/// beside its parent, beyond every display (#621).
///
/// AppKit makes and orders the sheet's window, not this suite, so it cannot
/// be an `OffScreenWindow`, and it positions it through
/// `_positionSheetsConstrained:andDisplay:`, which constrains a titled
/// window onto a display through `constrainFrameRect(_:to:)`. So that one
/// method of `NSWindow` is given
/// an answer of its own for exactly one kind of window — one whose
/// `sheetParent` is an `OffScreenWindow` — and every other window in the
/// test host, the main window included, gets AppKit's own answer through
/// the original implementation. Installed once, from the first `SheetHost`.
enum SheetsHungOffScreenStayThere {

    // MARK: - Stored properties

    /// Whether the replacement is in place.
    nonisolated(unsafe) static var isInstalled: Bool = false

    // MARK: - Functions

    static func install() {
        if isInstalled {
            return
        }
        let selector: Selector = #selector(NSWindow.constrainFrameRect(_:to:))
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else {
            return
        }
        typealias Constrain = @convention(c) (NSWindow, Selector, NSRect, NSScreen?) -> NSRect
        let appKitsAnswer: Constrain = unsafeBitCast(method_getImplementation(method), to: Constrain.self)
        let answer: @convention(block) (NSWindow, NSRect, NSScreen?) -> NSRect = { (window: NSWindow, frame: NSRect, screen: NSScreen?) in
            let hungOffScreen: Bool = MainActor.assumeIsolated {
                return window.sheetParent is OffScreenWindow
            }
            if hungOffScreen {
                return frame
            }
            return appKitsAnswer(window, selector, frame, screen)
        }
        method_setImplementation(method, imp_implementationWithBlock(answer))
        isInstalled = true
    }
}
