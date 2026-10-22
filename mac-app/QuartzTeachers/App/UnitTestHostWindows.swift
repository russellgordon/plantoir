import AppKit
import ObjectiveC

/// Keeps the unit suite's test host off every display, out of the Dock and
/// out of the menu bar (#633).
///
/// **Why this lives in the app and not in the tests.** The unit suite runs
/// INSIDE Plantoir: the test host is the real app, and it opens its real
/// window at launch. MEASURED on macOS 26.6 with two displays: the main
/// window is ordered in on a display at 449 ms after launch, and the test
/// bundle's principal class — the earliest code the test target can run —
/// only at 475 ms. So nothing in the test target can get there first.
/// `applicationWillFinishLaunching` can: there, no window exists yet and
/// XCTest is already loaded (true in every run measured).
///
/// **What it does, only inside the unit test host.**
/// - The host becomes an ACCESSORY app: no Dock tile and no menu bar of its
///   own. A teacher's Plantoir is untouched; see `quietsThisProcess`.
/// - `NSWindow`'s three placement methods — `constrainFrameRect(_:to:)`,
///   `setFrame(_:display:)` and `setFrameOrigin(_:)` — get an answer of their
///   own. A window that is not a sheet always sits at ONE origin beyond every
///   display; a sheet is moved only if it would overlap one, so it stays
///   beside its parent. The window is still ordered in, so the accessibility
///   tree, `isOnActiveSpace` and `cacheDisplay` screenshots all go on working,
///   which is what about twenty test classes rely on.
///
/// **Why one fixed origin and not "anywhere off screen".** Keeping windows
/// off the displays without pinning them was measured first: AppKit's sheet
/// helper shifts the parent after every sheet, and over 23 classes the main
/// window drifted from x = -5920 to x = -24070. Pinned, it stayed at
/// (-5920, -5711).
///
/// **Not in a release build.** The installer's body is `#if DEBUG`, so the
/// app a teacher downloads carries no swizzle at all; the pure decisions
/// below stay, because they do nothing on their own and the tests pin them.
nonisolated enum UnitTestHostWindows {

    // MARK: - Stored properties

    /// How far beyond the displays a window is put: room for a sheet hung
    /// under it and for the window growing.
    static let margin: CGFloat = 4000

    /// Set once, by `installIfThisIsTheUnitTestHost()`.
    nonisolated(unsafe) static var isInstalled: Bool = false

    // MARK: - Functions

    /// Whether this process is the one to keep quiet: ONLY the unit test
    /// host, whose XCTest is loaded into the app itself.
    ///
    /// Deliberately NOT `PlantoirDefaults.guardsAppKitBookkeeping`, which
    /// also arms for a UI test's `--state-dir` launch and for a marketing
    /// capture (`UITEST_WORKSPACE`). Those apps are DRIVEN through their
    /// windows from outside, by a runner or by `capture.py`, and they need
    /// those windows on a display. A pure function so a test pins every
    /// combination (`UnitTestHostWindowsTests`).
    static func quietsThisProcess(isInsideTestBundle: Bool, isUnderUITest: Bool,
                                  hasStateDirectory: Bool) -> Bool {
        if !isInsideTestBundle {
            return false
        }
        return true
    }

    /// A point at which a window of `size` overlaps none of `displays`:
    /// beyond the bottom-left corner of all of them together. The one copy
    /// of this formula; the tests' own off-screen hosts ask it too
    /// (`TableHost.offScreenOrigin(for:)`).
    static func offScreenOrigin(for size: NSSize, displays: [NSRect]) -> NSPoint {
        var left: CGFloat = 0
        var bottom: CGFloat = 0
        for display in displays {
            if display.minX < left {
                left = display.minX
            }
            if display.minY < bottom {
                bottom = display.minY
            }
        }
        return NSPoint(x: left - size.width - margin, y: bottom - size.height - margin)
    }

    /// Whether any part of `frame` is on one of `displays`.
    static func overlapsADisplay(_ frame: NSRect, displays: [NSRect]) -> Bool {
        for display in displays where display.intersects(frame) {
            return true
        }
        return false
    }

    /// Where a window asked to be at `frame` is put instead. A window that
    /// is not a sheet: the one origin beyond every display, whatever was
    /// asked. A sheet: where it was asked, unless that overlaps a display.
    static func placement(of frame: NSRect, isASheet: Bool, displays: [NSRect]) -> NSRect {
        if isASheet {
            if overlapsADisplay(frame, displays: displays) {
                return NSRect(origin: offScreenOrigin(for: frame.size, displays: displays), size: frame.size)
            }
            return frame
        }
        return NSRect(origin: offScreenOrigin(for: frame.size, displays: displays), size: frame.size)
    }

    /// The frames of this Mac's displays, as AppKit reports them.
    @MainActor
    static func displayFrames() -> [NSRect] {
        var frames: [NSRect] = []
        for screen in NSScreen.screens {
            frames.append(screen.frame)
        }
        return frames
    }

    /// Called first in `applicationWillFinishLaunching`, before any window
    /// exists. Does nothing in a release build, nothing outside the unit
    /// test host, and nothing the second time. Tests never call it: a
    /// second install would replace the chain `SheetHost` builds on top of
    /// it.
    @MainActor
    static func installIfThisIsTheUnitTestHost() {
        #if DEBUG
        if isInstalled {
            return
        }
        let wanted: Bool = quietsThisProcess(
            isInsideTestBundle: RealHome.isInsideTestBundle,
            isUnderUITest: RealHome.isUnderUITest,
            hasStateDirectory: RealHome.stateDirectory != nil
        )
        if !wanted {
            return
        }
        isInstalled = true
        NSApp.setActivationPolicy(.accessory)
        keepEveryWindowOffTheDisplays()
        #endif
    }

    #if DEBUG
    /// Where `window`, asked to be at `frame`, is put. Off the main thread it
    /// is left exactly as asked: AppKit's placement methods belong on the main
    /// thread, and an always-installed replacement that trapped there would
    /// take the whole test host down for one stray call.
    static func placedFrame(of window: NSWindow, asked frame: NSRect) -> NSRect {
        if !Thread.isMainThread {
            return frame
        }
        return MainActor.assumeIsolated {
            let isASheet: Bool = window.sheetParent != nil
            return placement(of: frame, isASheet: isASheet, displays: displayFrames())
        }
    }

    /// Gives `NSWindow`'s three placement methods the answer above. Every
    /// subclass that calls `super` — SwiftUI's window, alerts, sheets, the
    /// tests' `OffScreenWindow` — goes through them.
    static func keepEveryWindowOffTheDisplays() {
        let constrainSelector: Selector = #selector(NSWindow.constrainFrameRect(_:to:))
        if let method = class_getInstanceMethod(NSWindow.self, constrainSelector) {
            typealias Constrain = @convention(c) (NSWindow, Selector, NSRect, NSScreen?) -> NSRect
            let answerBefore: Constrain = unsafeBitCast(method_getImplementation(method), to: Constrain.self)
            // AppKit's own constraint is what pulls a window onto a display,
            // so on the main thread it is not asked at all.
            let replacement: @convention(block) (NSWindow, NSRect, NSScreen?) -> NSRect = { (window: NSWindow, frame: NSRect, screen: NSScreen?) in
                if !Thread.isMainThread {
                    return answerBefore(window, constrainSelector, frame, screen)
                }
                return placedFrame(of: window, asked: frame)
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }

        let setFrameSelector: Selector = #selector(NSWindow.setFrame(_:display:))
        if let method = class_getInstanceMethod(NSWindow.self, setFrameSelector) {
            typealias SetFrame = @convention(c) (NSWindow, Selector, NSRect, Bool) -> Void
            let original: SetFrame = unsafeBitCast(method_getImplementation(method), to: SetFrame.self)
            let replacement: @convention(block) (NSWindow, NSRect, Bool) -> Void = { (window: NSWindow, frame: NSRect, display: Bool) in
                original(window, setFrameSelector, placedFrame(of: window, asked: frame), display)
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }

        let originSelector: Selector = #selector(NSWindow.setFrameOrigin(_:))
        if let method = class_getInstanceMethod(NSWindow.self, originSelector) {
            typealias SetOrigin = @convention(c) (NSWindow, Selector, NSPoint) -> Void
            let original: SetOrigin = unsafeBitCast(method_getImplementation(method), to: SetOrigin.self)
            let replacement: @convention(block) (NSWindow, NSPoint) -> Void = { (window: NSWindow, point: NSPoint) in
                if !Thread.isMainThread {
                    original(window, originSelector, point)
                    return
                }
                let size: NSSize = MainActor.assumeIsolated {
                    return window.frame.size
                }
                let placed: NSRect = placedFrame(of: window, asked: NSRect(origin: point, size: size))
                original(window, originSelector, placed.origin)
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }
    }
    #endif
}
