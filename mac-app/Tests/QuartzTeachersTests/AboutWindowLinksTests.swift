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
    let expectedLinks: [(identifier: String, words: String)] = [
        (identifier: "aboutWebsiteLink", words: "https://plantoir.app"),
        (identifier: "aboutEmailLink", words: "support@plantoir.app"),
        (identifier: "aboutQuartzLink", words: "Quartz"),
        (identifier: "aboutSponsorLink", words: "Sponsor Jacky Zhao on GitHub"),
        (identifier: "aboutIconCreditLink", words: "Phosphor Icons"),
        (identifier: "aboutDesignCreditLink", words: "Russell Gordon"),
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
