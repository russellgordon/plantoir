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
///   selection and is `SubjectMenuRules`' to pin; and the two titles that
///   change with state (Stop Preview, "Cancel Deploy at 6:30 AM…") are read
///   back in their resting form.
///
/// A Revise With item is in the golden with a tag — `[if claude]`, `[if
/// codex]`, `[if local]`, `[if any reviser]` — and is expected only when
/// this Mac has it (`OutsideAssistantPresence`): presence follows the Mac.
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
            if title.hasPrefix("Cancel Deploy at ") {
                title = "Cancel Deploy at…"
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

    /// The golden, with each tagged line kept or dropped by what this Mac has.
    static func expectedText() throws -> String {
        let golden: String = try String(contentsOf: goldenURL(), encoding: .utf8)
        let presence: OutsideAssistantPresence = OutsideAssistantPresence.shared
        var lines: [String] = []
        for rawLine in golden.components(separatedBy: "\n") {
            if rawLine.hasPrefix("#") || rawLine.isEmpty {
                continue
            }
            var line: String = rawLine
            var keep: Bool = true
            let tags: [(String, Bool)] = [
                ("  [if claude]", presence.claudeIsInstalled),
                ("  [if codex]", presence.codexIsInstalled),
                ("  [if local]", presence.localAssistantCanRun),
                ("  [if any reviser]", presence.anyReviseTargetExists),
            ]
            for (tag, present) in tags where line.hasSuffix(tag) {
                line = String(line.dropLast(tag.count))
                keep = present
            }
            if keep {
                lines.append(line)
            }
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
