import AppKit
import XCTest
@testable import QuartzTeachers

/// The REAL menu bar, read out of `NSApp.mainMenu` in the hosted app (#457):
/// its menus in order, and every title, key equivalent and divider in File,
/// View's own group, Course, Section and Help, against
/// `mac-app/Tests/Goldens/menu-bar.txt` — plain indented text a reviewer
/// reads without running anything.
///
/// Three things the plan review measured, and this test does:
///
/// - **Items are stale until asked.** SwiftUI fills a menu's items when the
///   menu is about to open; reading them cold showed old values. Each menu
///   is sent `menuNeedsUpdate` and `update()` before it is read.
/// - **Hidden items are skipped**: Edit carries hidden Start Dictation and
///   Emoji & Symbols alternates, and Help a hidden ⌥⌘S "Toggle Sidebar".
/// - **Titles, keys and dividers only** — never enablement, which follows the
///   selection and is `SubjectMenuRules`' to pin; and the title that
///   changes with state (Stop Preview; Remove Scheduled Deploy… no longer
///   carries the time since #987) is read
///   back in their resting form — and so are Preview and its Option
///   alternate (#504), which the teacher's setting swaps.
///
/// Every Revise With item is in the golden untagged since #990 (D11): one
/// this Mac does not have is drawn dimmed, not left out, so the menu bar is
/// the same on every Mac.
@MainActor
final class MenuBarTreeTests: XCTestCase {

    // MARK: - Functions

    static func goldenURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Goldens/menu-bar.txt")
    }

    static func keyText(_ item: NSMenuItem) -> String {
        if item.keyEquivalent.isEmpty {
            return ""
        }
        var modifiers: String = ""
        let mask: NSEvent.ModifierFlags = item.keyEquivalentModifierMask
        if mask.contains(.control) {
            modifiers += "⌃"
        }
        if mask.contains(.option) {
            modifiers += "⌥"
        }
        if mask.contains(.shift) {
            modifiers += "⇧"
        }
        if mask.contains(.command) {
            modifiers += "⌘"
        }
        return modifiers + item.keyEquivalent.uppercased()
    }

    /// The menu's items, freshly updated, without the hidden ones.
    static func visibleItems(of menu: NSMenu) -> [NSMenuItem] {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        var items: [NSMenuItem] = []
        for item in menu.items where !item.isHidden {
            items.append(item)
        }
        return items
    }

    static func describe(_ menu: NSMenu, depth: Int, into lines: inout [String]) {
        let pad: String = String(repeating: "  ", count: depth)
        for item in visibleItems(of: menu) {
            if item.isSeparatorItem {
                lines.append(pad + "----")
                continue
            }
            var title: String = item.title
            if title == "Stop Preview" {
                title = "Preview"
            }
            // #504: the setting swaps Preview and its Option alternate, and
            // the setting is the teacher's — read back as the front-page
            // default whatever it says (the golden's header).
            if title == PreviewStartPageWording.previewAtLastViewed && !item.isAlternate {
                title = PreviewStartPageWording.preview
            } else if title == PreviewStartPageWording.preview && item.isAlternate {
                title = PreviewStartPageWording.previewAtLastViewed
            }
            var line: String = pad + title
            let key: String = keyText(item)
            // ⇧⌘O sits on whichever Open in Obsidian is live, so it is
            // checked on its own (`testOpenInObsidianHasItsKeyOnExactlyOneItem`).
            if !key.isEmpty && !(title == "Open in Obsidian" && key == "⇧⌘O") {
                line += "  [" + key + "]"
            }
            if item.isAlternate {
                line += "  (alternate)"
            }
            lines.append(line)
            if let submenu = item.submenu {
                describe(submenu, depth: depth + 1, into: &lines)
            }
        }
    }

    static func topMenu(named title: String) -> NSMenu? {
        guard let mainMenu = NSApp.mainMenu else {
            return nil
        }
        for item in mainMenu.items where item.title == title {
            return item.submenu
        }
        return nil
    }

    /// The menu bar as the golden spells it.
    static func actualText() throws -> String {
        let mainMenu: NSMenu = try XCTUnwrap(NSApp.mainMenu)
        var lines: [String] = []
        var titles: [String] = []
        for item in mainMenu.items {
            titles.append(item.title)
        }
        lines.append("menus: " + titles.joined(separator: " · "))
        for name in ["File", "View", "Course", "Section", "Help"] {
            lines.append("== " + name)
            let menu: NSMenu = try XCTUnwrap(topMenu(named: name), name)
            var menuLines: [String] = []
            describe(menu, depth: 1, into: &menuLines)
            if name == "View" {
                // Only View's own group, from Back to the divider after
                // Reload Page: the system puts tab, toolbar and full-screen
                // items around it that depend on the window in front
                // (measured: "Show Tab Bar" and "Show All Tabs" come FIRST
                // once a window has been key).
                var ownGroup: [String] = []
                var isInGroup: Bool = false
                for line in menuLines {
                    if line.hasPrefix("  Back") {
                        isInGroup = true
                    }
                    if isInGroup && line == "  ----" {
                        break
                    }
                    if isInGroup {
                        ownGroup.append(line)
                    }
                }
                menuLines = ownGroup
            }
            if name == "Help" {
                // The system's own Help item carries ⌘? in some states and
                // not in others (measured in one run of the suite); only
                // its title is Plantoir's to pin.
                var titlesOnly: [String] = []
                for line in menuLines {
                    if line.hasPrefix("  Plantoir Help") {
                        titlesOnly.append("  Plantoir Help")
                    } else {
                        titlesOnly.append(line)
                    }
                }
                menuLines = titlesOnly
            }
            for line in menuLines {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The golden, without its comment lines.
    static func expectedText() throws -> String {
        let golden: String = try String(contentsOf: goldenURL(), encoding: .utf8)
        var lines: [String] = []
        for line in golden.components(separatedBy: "\n") {
            if line.hasPrefix("#") || line.isEmpty {
                continue
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Tests

    func testTheMenuBarMatchesTheGolden() throws {
        OutsideAssistantPresence.shared.refresh()
        let actual: String = try MenuBarTreeTests.actualText()
        let expected: String = try MenuBarTreeTests.expectedText()
        XCTAssertEqual(actual, expected, "the real menu bar against Tests/Goldens/menu-bar.txt — actual:\n\(actual)")
    }

    /// Russell, 2026-10-08: no "New Assistant Window" (the assistant is
    /// always for a section), no File ▸ New submenu of window kinds, no
    /// Rename in Edit (Course ▸ Rename now), and the Window menu manages
    /// windows only — no second "About Plantoir" in it.
    func testNoAssistantWindowNoNewSubmenuAndNothingMisplaced() throws {
        let mainMenu: NSMenu = try XCTUnwrap(NSApp.mainMenu)
        var everyTitle: [String] = []
        var stack: [NSMenu] = [mainMenu]
        while let menu = stack.popLast() {
            for item in MenuBarTreeTests.visibleItems(of: menu) {
                everyTitle.append(item.title)
                if let submenu = item.submenu {
                    stack.append(submenu)
                }
            }
        }
        for title in everyTitle {
            XCTAssertFalse(title.localizedCaseInsensitiveContains("Assistant Window"), title)
        }
        let file: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: "File"))
        for item in MenuBarTreeTests.visibleItems(of: file) {
            XCTAssertNotEqual(item.title, "New", "File ▸ New ▸ is gone")
        }
        let edit: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: "Edit"))
        for item in MenuBarTreeTests.visibleItems(of: edit) {
            XCTAssertFalse(item.title.hasPrefix("Rename"), "Rename lives in Course now: \(item.title)")
        }
        let window: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: "Window"))
        for item in MenuBarTreeTests.visibleItems(of: window) {
            XCTAssertNotEqual(item.title, "About Plantoir", "the Window menu manages windows only")
        }
    }

    /// Each key equivalent means one thing: no two visible items share one.
    /// (⇧⌘O moves between the two Open in Obsidian items rather than sitting
    /// on both — measured: a key on a DISABLED item earlier in the bar
    /// swallows it — so it is not an exception here either.)
    func testEachKeyEquivalentMeansOneThing() throws {
        let mainMenu: NSMenu = try XCTUnwrap(NSApp.mainMenu)
        var owners: [String: [String]] = [:]
        var stack: [(NSMenu, String)] = [(mainMenu, "")]
        while let (menu, path) = stack.popLast() {
            for item in MenuBarTreeTests.visibleItems(of: menu) {
                let key: String = MenuBarTreeTests.keyText(item)
                if !key.isEmpty && !item.isAlternate {
                    owners[key, default: []].append(path + item.title)
                }
                if let submenu = item.submenu {
                    stack.append((submenu, path + item.title + " ▸ "))
                }
            }
        }
        for (key, items) in owners {
            XCTAssertEqual(items.count, 1, "\(key) is on \(items)")
        }
        XCTAssertEqual(owners["⌘N"], ["File ▸ New Window"])
    }

    /// #990 (D24, D25): no Plantoir item takes a shortcut the HIG's
    /// Keyboards table gives to another command — ⇧⌘P is Page Setup, ⇧⌘C
    /// Show Colors. The ruled keys (Russell, 2026-11-18) sit where they were
    /// ruled, Rebuild Preview's ⇧⌘Y among them: a Services key such as
    /// Stickies' ⇧⌘Y is not a standard shortcut, and inside Plantoir the
    /// app's own item wins over it (Apple's Services Implementation Guide;
    /// measured in the running app, documentation/09 → "Mac conventions").
    /// MUST FAIL on `dev` before #990, where Preview held ⇧⌘P and Copy a
    /// Page ⇧⌘C, and on 23b554773, where Rebuild Preview held ⇧⌘B.
    func testNoItemTakesAStandardShortcut() throws {
        var keys: [String: String] = [:]
        for name in ["File", "Course", "Section", "Help"] {
            let menu: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: name))
            var stack: [NSMenu] = [menu]
            while let current = stack.popLast() {
                for item in MenuBarTreeTests.visibleItems(of: current) {
                    let key: String = MenuBarTreeTests.keyText(item)
                    if !key.isEmpty && !item.isAlternate {
                        keys[key] = name + " ▸ " + item.title
                    }
                    if let submenu = item.submenu {
                        stack.append(submenu)
                    }
                }
            }
        }
        for standard in ["⇧⌘P", "⇧⌘C"] {
            XCTAssertNil(keys[standard], "\(standard) is a standard or system shortcut, taken by \(keys[standard] ?? "")")
        }
        XCTAssertNil(keys["⇧⌘B"], "⇧⌘B adds Shift to ⌘B, Bold, for an unrelated command; taken by \(keys["⇧⌘B"] ?? "")")
        XCTAssertEqual(keys["⌘Y"], "Section ▸ " + PreviewStartPage.title(for: AppSettings.shared.previewOpensAt))
        XCTAssertEqual(keys["⇧⌘Y"], "Section ▸ Rebuild Preview")
        XCTAssertEqual(keys["⇧⌘K"], "Course ▸ " + CopyPageWording.menuItem)
        XCTAssertEqual(keys["⇧⌘D"], "Section ▸ Deploy…")
    }

    /// #990 (Russell's ruling Q10): Set Up an Assistant… is in Revise With
    /// only, never in the Help menu as well.
    func testSetUpAnAssistantIsInReviseWithOnly() throws {
        let help: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: "Help"))
        for item in MenuBarTreeTests.visibleItems(of: help) {
            XCTAssertNotEqual(item.title, AssistantSetUpWording.menuItem, "not in Help")
        }
        for name in ["Course", "Section"] {
            let menu: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: name))
            var found: Bool = false
            for item in MenuBarTreeTests.visibleItems(of: menu) where item.title == "Revise With" {
                let submenu: NSMenu = try XCTUnwrap(item.submenu)
                let last: NSMenuItem? = MenuBarTreeTests.visibleItems(of: submenu).last
                found = last?.title == AssistantSetUpWording.menuItem
            }
            XCTAssertTrue(found, "\(name) ▸ Revise With ends with Set Up an Assistant…")
        }
    }

    func testOpenInObsidianHasItsKeyOnExactlyOneItem() throws {
        var keyed: [String] = []
        for name in ["Course", "Section"] {
            let menu: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: name))
            for item in MenuBarTreeTests.visibleItems(of: menu) where item.title == "Open in Obsidian" {
                if MenuBarTreeTests.keyText(item) == "⇧⌘O" {
                    keyed.append(name)
                }
            }
        }
        XCTAssertEqual(keyed.count, 1, "⇧⌘O on \(keyed)")
    }

    /// The plan review's finding 8, a bug fixed in passing: a notification
    /// clicked with no window open opens one through File's ⌘N item
    /// (#306), and the lookup found nothing while ⌘N sat in File ▸ New ▸.
    func testTheNotificationsNewWindowOpenerFindsNewWindow() throws {
        let found: (menu: NSMenu, index: Int)? = SectionFromNotification.newWindowMenuItem(in: NSApp.mainMenu)
        let unwrapped: (menu: NSMenu, index: Int) = try XCTUnwrap(found, "⌘N must be an item of a top-level menu")
        XCTAssertEqual(unwrapped.menu.items[unwrapped.index].title, "New Window")
        XCTAssertEqual(unwrapped.menu.title, "File")
    }
}
