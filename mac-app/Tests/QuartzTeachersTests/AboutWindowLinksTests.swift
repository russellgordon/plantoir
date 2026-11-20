import AppKit
import SwiftUI
import XCTest
@testable import QuartzTeachers

/// The About window's links, read from the real `AboutView` through the
/// accessibility API an assistive app uses (#993, D46). Before this piece
/// the credits were inline Markdown links in a `Text`, which SwiftUI hands
/// to VoiceOver as links that are NOT enabled (measured 2026-11-19:
/// "Quartz", "sponsoring him on GitHub", "Phosphor Icons" and "Russell
/// Gordon" each read AXEnabled 0) and which Tab does not reach. Russell
/// ruled option A of `vm-tools/reference/993-about-window-design.md`: every
/// link a `Link` view of its own.
///
/// Apple's VoiceOver guidance: "Support the VoiceOver rotor when possible.
/// People can use an interface element called the VoiceOver rotor to
/// navigate a document or webpage by headings, links, and other content
/// types." Its Writing guidance: "For links, avoid using 'Click here' in
/// favor of more descriptive words or phrases."
@MainActor
final class AboutWindowLinksTests: XCTestCase {

    // MARK: - Stored properties

    /// Each link's identifier and the words VoiceOver must read for it,
    /// top to bottom, as the window draws them.
    /// The address each press must open is written out here rather than
    /// read from `AboutView`, so a link pointed at the wrong page fails
    /// (#1012); these are the addresses the window's links have always had
    /// (checked by hand against the inline links they replaced, 993b).
    let expectedLinks: [(identifier: String, words: String, address: String)] = [
        (identifier: "aboutWebsiteLink", words: "https://plantoir.app", address: "https://plantoir.app"),
        (identifier: "aboutEmailLink", words: "support@plantoir.app", address: "mailto:support@plantoir.app"),
        (identifier: "aboutQuartzLink", words: "Quartz", address: "https://quartz.jzhao.xyz"),
        (identifier: "aboutSponsorLink", words: "Sponsor Jacky Zhao on GitHub", address: "https://github.com/sponsors/jackyzha0"),
        (identifier: "aboutIconCreditLink", words: "Phosphor Icons", address: "https://phosphoricons.com"),
        (identifier: "aboutDesignCreditLink", words: "Russell Gordon", address: "https://www.russellgordon.ca"),
    ]

    /// The About window's size when drawn, with room to spare.
    let windowSize: NSSize = NSSize(width: 540, height: 760)

    // MARK: - Functions

    /// Hosts the real About view off screen, in a window with a title no
    /// other window has, and hands it back with that title.
    func hostTheAboutView() throws -> (host: TableHost, title: String) {
        let host: TableHost = TableHost(AboutView(), size: windowSize)
        let title: String = "about-links-\(UUID().uuidString)"
        host.window.title = title
        host.pump(0.4)
        do {
            try AccessibilityInspector.skipUnlessTheWindowCanBeRead(host.window)
        } catch {
            host.close()
            throw error
        }
        return (host: host, title: title)
    }

    /// Every link is one element of its own that VoiceOver reads as an
    /// enabled link with its own words. With the inline Markdown links put
    /// back, the four credit links read as disabled and have no identifier
    /// of their own, so this fails.
    func testEveryAboutLinkIsAnEnabledLinkWithItsOwnWords() throws {
        let hosted = try hostTheAboutView()
        defer {
            hosted.host.close()
        }
        let read: AccessibilityTree = AccessibilityTree(ofWindowTitled: hosted.title)
        XCTAssertTrue(read.foundTheWindow, "the hosted About window is not in the accessibility tree")

        for expected in expectedLinks {
            guard let link = read.element(identifiedAs: expected.identifier) else {
                continue
            }
            XCTAssertEqual(link.role, "AXLink", "\(expected.words) is not a link:\n\(read.described())")
            XCTAssertEqual(link.enabled, "1", "VoiceOver reads \(expected.words) as a disabled link")
            XCTAssertEqual(link.names, [expected.words], "VoiceOver does not read \(expected.words) by its own words")
        }
    }

    /// The window holds exactly these six links, every one enabled: no link
    /// is left inside a sentence, where VoiceOver would read it as
    /// disabled, and the rotor's Links list holds each once.
    func testTheAboutWindowHoldsOnlyItsSixEnabledLinks() throws {
        let hosted = try hostTheAboutView()
        defer {
            hosted.host.close()
        }
        let read: AccessibilityTree = AccessibilityTree(ofWindowTitled: hosted.title)
        let links: [AccessibilityTree.Element] = read.elements(withRole: "AXLink")

        var wordsRead: [String] = []
        var disabledLinks: [String] = []
        for link in links {
            wordsRead.append(link.label)
            if link.enabled != "1" {
                disabledLinks.append(link.label)
            }
        }
        var wordsExpected: [String] = []
        for expected in expectedLinks {
            wordsExpected.append(expected.words)
        }
        XCTAssertEqual(disabledLinks, [], "links VoiceOver reads as disabled:\n\(read.described())")
        XCTAssertEqual(wordsRead, wordsExpected, "the window's links, in order:\n\(read.described())")
    }

    /// The sponsor sentence is read whole, as plain words, with no link
    /// inside it.
    func testTheSponsorSentenceIsReadWhole() throws {
        let hosted = try hostTheAboutView()
        defer {
            hosted.host.close()
        }
        let read: AccessibilityTree = AccessibilityTree(ofWindowTitled: hosted.title)
        let sentence: String = "Plantoir is a friendly wrapper around Quartz, which Jacky Zhao builds and gives away for free. If you end up using Plantoir regularly, please consider sponsoring him on GitHub — it is his work that makes all of this possible."
        var found: Bool = false
        for element in read.elements(withRole: "AXStaticText") {
            if element.value == sentence {
                found = true
            }
        }
        XCTAssertTrue(found, "the sponsor sentence is not read whole:\n\(read.described())")
    }

    /// The credits are label-and-value rows: each label is read as its
    /// own words, beside its value.
    func testTheCreditsAreReadAsLabelsAndValues() throws {
        let hosted = try hostTheAboutView()
        defer {
            hosted.host.close()
        }
        let read: AccessibilityTree = AccessibilityTree(ofWindowTitled: hosted.title)
        var wordsShown: [String] = []
        for element in read.elements(withRole: "AXStaticText") {
            wordsShown.append(element.value)
        }
        for words in ["Icon", "(MIT)", "Design", "Made with", "Claude"] {
            XCTAssertTrue(wordsShown.contains(words), "\"\(words)\" is not read as words of its own:\n\(read.described())")
        }
    }

    /// Every link can be pressed by an assistive app, whether Keyboard
    /// Navigation is on or off, and the press opens that link's own page.
    /// With it off, macOS moves Tab only between text fields and lists in
    /// every app, so a person who cannot use the pointer reaches a link the
    /// way the HIG gives them: VoiceOver, whose rotor lists the window's
    /// links ("Support the VoiceOver rotor"), or Full Keyboard Access
    /// ("navigate and activate windows, menus, controls, and system
    /// features using only the keyboard"). Both activate a link through its
    /// press action, which this performs on each link in turn (#1012, the
    /// 993b review: reading that the action is offered did not show that
    /// pressing it opens anything). The view is given an `OpenURLAction`
    /// that records what it is asked to open instead of opening it, and
    /// each press must open exactly the address written here, so a link
    /// pointed at the wrong page fails. It does not skip with Keyboard
    /// Navigation off.
    func testEveryAboutLinkCanBePressedByAnAssistiveAppAndOpensItsOwnPage() throws {
        let recorder: OpenedAddresses = OpenedAddresses()
        let recording: some View = AboutView()
            .environment(\.openURL, OpenURLAction { address in
                recorder.record(address)
                return .handled
            })
        let host: TableHost = TableHost(recording, size: windowSize)
        defer {
            host.close()
        }
        let title: String = "about-links-\(UUID().uuidString)"
        host.window.title = title
        host.pump(0.4)
        try AccessibilityInspector.skipUnlessTheWindowCanBeRead(host.window)
        let read: AccessibilityTree = AccessibilityTree(ofWindowTitled: title)
        for expected in expectedLinks {
            guard let link = read.element(identifiedAs: expected.identifier) else {
                continue
            }
            XCTAssertTrue(link.actions.contains("AXPress"), "an assistive app cannot press \(expected.words): its actions are \(link.actions)")
            recorder.clear()
            let presses: [AXError] = AccessibilityTree.press(identifiedAs: expected.identifier, inWindowTitled: title)
            XCTAssertEqual(presses, [.success], "pressing \(expected.words) through the accessibility API was not accepted")
            host.pump(0.2)
            XCTAssertEqual(recorder.addresses(), [expected.address], "pressing \(expected.words) did not open its own page")
        }
    }

    /// With Keyboard Navigation on (System Settings ▸ Keyboard), Tab
    /// stops once on each of the six links and then comes round again.
    /// Inline Markdown links are never stops: with them back, Tab stops
    /// only on Website and Email. With Keyboard Navigation off, macOS moves
    /// Tab only between text fields and lists, so there is nothing of the
    /// window's own to test and the test says so.
    ///
    /// The window is off screen and the test host is not the active app,
    /// so the accessibility API names no focused element here (measured
    /// 2026-11-19); what Tab moves is the window's first responder, one
    /// view per stop. The words of each stop were read live, in an
    /// isolated debug build, through the accessibility API:
    /// `documentation/09-mac-app.md` → the About window's links.
    func testTabStopsOnceOnEachOfTheSixLinksWithKeyboardNavigationOn() throws {
        if !NSApp.isFullKeyboardAccessEnabled {
            throw XCTSkip("Keyboard Navigation is off on this Mac: Tab reaches no link in any app, so there is nothing of the About window's own to read.")
        }
        let hosted = try hostTheAboutView()
        defer {
            hosted.host.close()
        }
        let window: NSWindow = hosted.host.window
        window.makeFirstResponder(window.contentView)
        hosted.host.pump(0.2)

        var stops: [ObjectIdentifier] = []
        for _ in 0..<(expectedLinks.count * 2) {
            pressTab(in: window)
            hosted.host.pump(0.1)
            if let responder = window.firstResponder {
                stops.append(ObjectIdentifier(responder))
            }
        }

        var distinctStops: [ObjectIdentifier] = []
        for stop in stops {
            if !distinctStops.contains(stop) {
                distinctStops.append(stop)
            }
        }
        XCTAssertEqual(distinctStops.count, expectedLinks.count, "Tab does not stop once on each of the six links")
        if stops.count == expectedLinks.count * 2 {
            for index in 0..<expectedLinks.count {
                XCTAssertEqual(stops[index], stops[index + expectedLinks.count], "Tab does not come round to the same link after six presses")
            }
        }
    }

    /// Sends one press of Tab to `window`, as the keyboard would.
    func pressTab(in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, NSEvent.EventType.keyUp] {
            let event: NSEvent? = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48
            )
            if let event {
                window.sendEvent(event)
            }
        }
    }
}

/// What an `OpenURLAction` was asked to open, in order (#1012). Locked,
/// because SwiftUI does not promise which thread calls the action.
final class OpenedAddresses: @unchecked Sendable {

    // MARK: - Stored properties

    private let lock: NSLock = NSLock()
    private var opened: [String] = []

    // MARK: - Functions

    func record(_ address: URL) {
        lock.lock()
        opened.append(address.absoluteString)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        opened = []
        lock.unlock()
    }

    func addresses() -> [String] {
        lock.lock()
        let copy: [String] = opened
        lock.unlock()
        return copy
    }
}
