import AppKit
import XCTest
@testable import QuartzTeachers

/// #990 (Russell's ruling of 2026-11-20, grouping A): the Section menu splits
/// into Section and Classes, and both apps draw the split from
/// `contracts/shared-rules.json` → `subjectMenus.layout`.
///
/// - the mac's `SubjectMenuLayout` is the contract's lists, entry for entry;
/// - the REAL menu bar draws exactly those lists, a separator between groups
///   and nowhere else, in the contract's menu-bar order;
/// - every item is DRAWN and DIMMED when it cannot be used, never hidden
///   (HIG, The menu bar: "If a menu bar item isn't actionable, disable the
///   action instead of hiding it from the menu"): read with no Plantoir
///   window in front, where `subjectMenus.cases` greys every one of them;
/// - the keys of the two menus are the ruled ones and nothing else.
@MainActor
final class SubjectMenuLayoutTests: XCTestCase {

    // MARK: - Functions

    static func layout() throws -> [String: Any] {
        let rule: [String: Any] = try SharedRulesContractTests.section("subjectMenus")
        return try XCTUnwrap(rule["layout"] as? [String: Any], "subjectMenus.layout")
    }

    /// The contract's name for one line of the mac's layout.
    static func contractName(of entry: SubjectMenuLayout.Entry) -> String {
        switch entry {
        case .item(let item):
            return item.rawValue
        case .submenu(let submenu):
            return submenu.rawValue
        }
    }

    /// The mac's layout of one menu, as the contract spells it.
    static func macGroups(of menu: SubjectMenuLayout.Menu) -> [[String]] {
        var groups: [[String]] = []
        for group in SubjectMenuLayout.groups(of: menu) {
            var names: [String] = []
            for entry in group {
                names.append(contractName(of: entry))
            }
            groups.append(names)
        }
        return groups
    }

    /// What the real menu should read, line by line, from the layout: each
    /// item's title, "Revise With" for the submenu, and "----" between
    /// groups. Preview reads back in its resting form, as the golden does.
    /// The menu bar under test has no club selected, so its items are titled
    /// as a course titles them.
    static func expectedLines(of menu: SubjectMenuLayout.Menu) throws -> [String] {
        var lines: [String] = []
        var isFirstGroup: Bool = true
        for group in SubjectMenuLayout.groups(of: menu) {
            if !isFirstGroup {
                lines.append("----")
            }
            isFirstGroup = false
            for entry in group {
                switch entry {
                case .item(let item):
                    lines.append(try XCTUnwrap(SectionMenu.title(for: item, noun: .class), "\(item) is in the layout with no title"))
                case .submenu(let submenu):
                    lines.append(SubjectMenuLayout.title(of: submenu))
                }
            }
        }
        return lines
    }

    /// The real menu's lines: titles and separators, alternates left out.
    static func actualLines(of menu: NSMenu) -> [String] {
        var lines: [String] = []
        for item in MenuBarTreeTests.visibleItems(of: menu) {
            if item.isSeparatorItem {
                lines.append("----")
                continue
            }
            if item.isAlternate {
                continue
            }
            var title: String = item.title
            if title == PreviewStartPageWording.previewAtLastViewed || title == PreviewStartPageWording.stopPreview {
                title = PreviewStartPageWording.preview
            }
            lines.append(title)
        }
        return lines
    }

    // MARK: - Tests

    /// The mac's lists are the contract's, group for group. MUST FAIL with
    /// any item moved, any group split or joined, or the submenu's items
    /// reordered (proved by moving Class Dates… after Re-date Classes…).
    func testTheLayoutIsTheContracts() throws {
        let layout: [String: Any] = try SubjectMenuLayoutTests.layout()
        let menus: [[String: Any]] = try XCTUnwrap(layout["menus"] as? [[String: Any]])
        var contractMenus: [String] = []
        for menu in menus {
            let name: String = try XCTUnwrap(menu["menu"] as? String)
            contractMenus.append(name)
            let mac: SubjectMenuLayout.Menu = try XCTUnwrap(SubjectMenuLayout.Menu(rawValue: name), "no menu \(name) here")
            XCTAssertEqual(menu["title"] as? String, SubjectMenuLayout.title(of: mac, noun: .class))
            // #990, Russell, 2026-11-20 evening: Meetings in a club.
            XCTAssertEqual(menu["titleForAMeeting"] as? String, SubjectMenuLayout.title(of: mac, noun: .meeting), name)
            let groups: [[String]] = try XCTUnwrap(menu["groups"] as? [[String]])
            XCTAssertEqual(SubjectMenuLayoutTests.macGroups(of: mac), groups, "\(name)'s groups")
        }
        var macMenus: [String] = []
        for menu in SubjectMenuLayout.Menu.allCases {
            macMenus.append(menu.rawValue)
        }
        XCTAssertEqual(macMenus, contractMenus)

        let submenus: [String: Any] = try XCTUnwrap(layout["submenus"] as? [String: Any])
        XCTAssertEqual(submenus.count, SubjectMenuLayout.Submenu.allCases.count)
        for submenu in SubjectMenuLayout.Submenu.allCases {
            let entry: [String: Any] = try XCTUnwrap(submenus[submenu.rawValue] as? [String: Any], submenu.rawValue)
            XCTAssertEqual(entry["title"] as? String, SubjectMenuLayout.title(of: submenu))
            var names: [String] = []
            for item in SubjectMenuLayout.items(of: submenu) {
                names.append(item.rawValue)
            }
            XCTAssertEqual(entry["items"] as? [String], names, "\(submenu.rawValue)'s items")
        }
    }

    /// Every entry names an item of `subjectMenus.items` or a submenu, and
    /// no item is in two places; Change Deploy Time… (#525) is reserved
    /// between Schedule Deploy… and Remove Scheduled Deploy, and is no item
    /// yet.
    func testEveryEntryIsAnItemOnceAndTheReservedPlaceIsBetweenItsNeighbours() throws {
        let rule: [String: Any] = try SharedRulesContractTests.section("subjectMenus")
        let items: [String] = try XCTUnwrap(rule["items"] as? [String])
        var seen: [String] = []
        for menu in SubjectMenuLayout.Menu.allCases {
            for group in SubjectMenuLayoutTests.macGroups(of: menu) {
                XCTAssertFalse(group.isEmpty, "an empty group in \(menu.rawValue)")
                for name in group {
                    if let submenu = SubjectMenuLayout.Submenu(rawValue: name) {
                        for item in SubjectMenuLayout.items(of: submenu) {
                            seen.append(item.rawValue)
                        }
                    } else {
                        seen.append(name)
                    }
                }
            }
        }
        for name in seen {
            XCTAssertTrue(items.contains(name), "\(name) is no item of subjectMenus.items")
        }
        XCTAssertEqual(Set(seen).count, seen.count, "an item is in two places: \(seen)")

        let reserved: [[String: Any]] = try XCTUnwrap(try SubjectMenuLayoutTests.layout()["reservedPlaces"] as? [[String: Any]])
        for place in reserved {
            let name: String = try XCTUnwrap(place["item"] as? String)
            XCTAssertFalse(items.contains(name), "\(name) is an item now: put it in the layout")
            let after: String = try XCTUnwrap(place["after"] as? String)
            let before: String = try XCTUnwrap(place["before"] as? String)
            let afterIndex: Int = try XCTUnwrap(seen.firstIndex(of: after))
            let beforeIndex: Int = try XCTUnwrap(seen.firstIndex(of: before))
            XCTAssertEqual(afterIndex + 1, beforeIndex, "\(name)'s neighbours are not next to each other")
        }
    }

    /// The real menu bar reads in the contract's order, Classes after
    /// Section. MUST FAIL on `dev` before #990, which had no Classes menu.
    func testTheMenuBarIsInTheContractsOrder() throws {
        let order: [String: Any] = try XCTUnwrap(try SubjectMenuLayoutTests.layout()["menuBar"] as? [String: Any])
        let mainMenu: NSMenu = try XCTUnwrap(NSApp.mainMenu)
        var titles: [String] = []
        for item in mainMenu.items {
            titles.append(item.title)
        }
        XCTAssertEqual(titles, order["mac"] as? [String])
    }

    /// The real Section and Classes menus draw the layout line for line.
    /// MUST FAIL if either menu is drawn by hand in another order, an item
    /// is left out or added, or a separator moves (proved by drawing a
    /// Divider inside the publishing group).
    func testTheRealMenusDrawTheLayout() throws {
        OutsideAssistantPresence.shared.refresh()
        for menu in SubjectMenuLayout.Menu.allCases {
            // The hosted test has no window in front, so nothing is
            // selected and the menus carry an ordinary course's titles.
            let title: String = SubjectMenuLayout.title(of: menu, noun: .class)
            let real: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: title), "no \(title) menu in the menu bar")
            XCTAssertEqual(
                SubjectMenuLayoutTests.actualLines(of: real), try SubjectMenuLayoutTests.expectedLines(of: menu),
                "\(title) against subjectMenus.layout"
            )
        }
        let section: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: "Section"))
        for item in MenuBarTreeTests.visibleItems(of: section) where item.title == "Revise With" {
            let submenu: NSMenu = try XCTUnwrap(item.submenu)
            var titles: [String] = []
            for child in MenuBarTreeTests.visibleItems(of: submenu) where !child.isSeparatorItem {
                titles.append(child.title)
            }
            XCTAssertEqual(titles, [
                ClaudeCodeLauncher.menuItemTitle, CodexLauncher.menuItemTitle, CopilotLauncher.menuItemTitle,
                ReviseWithMenu.localAssistantTitle, AssistantSetUpWording.menuItem,
            ])
        }
    }

    /// With no Plantoir window in front, `subjectMenus.cases` greys every
    /// Section and Classes item, and every one is still DRAWN, dimmed: the
    /// two menus have every line of the layout, and none of them can be
    /// pressed (Set Up an Assistant… aside, which opens Settings). MUST FAIL
    /// if an item that cannot be used is hidden rather than dimmed (proved
    /// by drawing Classes ▸ Add Class… only when it is enabled).
    func testEveryItemIsDrawnAndDimmedWhenItCannotBeUsed() throws {
        let nothingInFront: Set<SubjectMenuRules.Item> = SubjectMenuRules.enabledItems(SubjectMenuRules.Situation())
        for menu in SubjectMenuLayout.Menu.allCases {
            for group in SubjectMenuLayout.groups(of: menu) {
                for entry in group {
                    if case .item(let item) = entry {
                        XCTAssertFalse(nothingInFront.contains(item), "\(item) is live with no window in front")
                    }
                }
            }
        }
        // The hosted test has no Plantoir window in front: the focused
        // values are empty, as with Settings or the assistant key.
        for menu in SubjectMenuLayout.Menu.allCases {
            // The hosted test has no window in front, so nothing is
            // selected and the menus carry an ordinary course's titles.
            let title: String = SubjectMenuLayout.title(of: menu, noun: .class)
            let real: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: title))
            let lines: [String] = SubjectMenuLayoutTests.actualLines(of: real)
            XCTAssertEqual(lines, try SubjectMenuLayoutTests.expectedLines(of: menu), "\(title) hides something")
            var live: [String] = []
            var stack: [NSMenu] = [real]
            while let current = stack.popLast() {
                for item in MenuBarTreeTests.visibleItems(of: current) where !item.isSeparatorItem {
                    if let submenu = item.submenu {
                        stack.append(submenu)
                        continue
                    }
                    if item.title == AssistantSetUpWording.menuItem {
                        continue
                    }
                    if item.isEnabled {
                        live.append(item.title)
                    }
                }
            }
            XCTAssertEqual(live, [], "\(title) items live with no window in front")
        }
    }

    /// The two menus' keys are the ruled ones (#990, 2026-11-18): ⌘Y and its
    /// Option alternate on Preview, ⇧⌘Y on Rebuild Preview, ⇧⌘D on Deploy…;
    /// Classes has none. (⇧⌘O moves between the Open in Obsidian items and
    /// is checked by `MenuBarTreeTests`.) MUST FAIL if the split moved a key
    /// or added one.
    func testTheSplitChangedNoKey() throws {
        var keys: [String: String] = [:]
        for menu in SubjectMenuLayout.Menu.allCases {
            // The hosted test has no window in front, so nothing is
            // selected and the menus carry an ordinary course's titles.
            let title: String = SubjectMenuLayout.title(of: menu, noun: .class)
            let real: NSMenu = try XCTUnwrap(MenuBarTreeTests.topMenu(named: title))
            for item in MenuBarTreeTests.visibleItems(of: real) {
                let key: String = MenuBarTreeTests.keyText(item)
                if key.isEmpty || key == "⇧⌘O" {
                    continue
                }
                var itemTitle: String = item.title
                if item.isAlternate {
                    itemTitle = "(alternate)"
                } else if itemTitle == PreviewStartPageWording.previewAtLastViewed {
                    itemTitle = PreviewStartPageWording.preview
                }
                keys[key] = title + " ▸ " + itemTitle
            }
        }
        XCTAssertEqual(keys, [
            "⌘Y": "Section ▸ Preview",
            "⌥⌘Y": "Section ▸ (alternate)",
            "⇧⌘Y": "Section ▸ Rebuild Preview",
            "⇧⌘D": "Section ▸ Deploy…",
        ])
    }

    /// Menu paths follow the split: a trail line names the menu the item is
    /// in now. MUST FAIL on `dev` before #990, where every one said Section.
    func testMenuPathsNameTheMenuTheItemIsIn() {
        XCTAssertEqual(SectionVerbs.menuPath(of: .addClass, noun: .class), "Classes ▸ Add Class…")
        XCTAssertEqual(SectionVerbs.menuPath(of: .classDates, noun: .class), "Classes ▸ Class Dates…")
        XCTAssertEqual(SectionVerbs.menuPath(of: .reDateClasses, noun: .class), "Classes ▸ Re-date Classes…")
        XCTAssertEqual(SectionVerbs.menuPath(of: .makeRoomForClasses, noun: .class), "Classes ▸ Make Room for Classes…")
        XCTAssertEqual(SectionVerbs.menuPath(of: .rollOverToANewYear, noun: .class), "Classes ▸ Roll Over to a New Year…")
        XCTAssertEqual(SectionVerbs.menuPath(of: .publishPages, noun: .class), "Section ▸ Publish Pages…")
        XCTAssertEqual(SectionVerbs.menuPath(of: .undoLastChange, noun: .class), "Section ▸ Undo Last Change")
        XCTAssertEqual(SectionVerbs.menuPath(of: .rebuildPreview, noun: .class), "Section ▸ Rebuild Preview")
        // A club's trail names its menus as its menu bar does (#990, 2026-11-20 evening).
        XCTAssertEqual(SectionVerbs.menuPath(of: .makeRoomForClasses, noun: .meeting), "Meetings ▸ Make Room for Meetings…")
        XCTAssertEqual(SectionVerbs.menuPath(of: .publishPages, noun: .meeting), "Section ▸ Publish Pages…")
    }

    /// Russell's ruling "name the real menu" (#990): the copy's trail line
    /// names the menu the item is in, as `activityTrail.mustRecord` →
    /// "section menu backed up a course" → `lineCases` says. MUST FAIL with
    /// the line's menu typed as Section.
    func testTheMenusCopyLineNamesTheRealMenu() throws {
        let trail: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        let events: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        var cases: [[String: Any]] = []
        for event in events where event["event"] as? String == "section menu backed up a course" {
            cases = try XCTUnwrap(event["lineCases"] as? [[String: Any]])
        }
        XCTAssertEqual(cases.count, 6)
        for testCase in cases {
            let inMenu: SubjectMenuLayout.Menu = try XCTUnwrap(SubjectMenuLayout.Menu(rawValue: try XCTUnwrap(testCase["menu"] as? String)))
            // A club's line names the Meetings menu (#990, 2026-11-20 evening).
            let noun: ClassNoun = try XCTUnwrap(ClassNoun(rawValue: testCase["noun"] as? String ?? "class"))
            if let file = testCase["file"] as? String {
                let line: String = ActivityTrail.sectionMenuBackedUpLine(
                    fileName: file, bytes: 1_000_000, seconds: 2, inMenu: inMenu, noun: noun
                )
                XCTAssertTrue(line.hasPrefix(try XCTUnwrap(testCase["startsWith"] as? String)), line)
            } else {
                let reason: String = try XCTUnwrap(testCase["reason"] as? String)
                XCTAssertEqual(
                    ActivityTrail.sectionMenuCouldNotBackUpLine(reason: reason, inMenu: inMenu, noun: noun),
                    testCase["line"] as? String
                )
            }
        }
        XCTAssertEqual(SubjectMenuLayout.eitherMenu(noun: .class), "Section or Classes")
        XCTAssertEqual(SubjectMenuLayout.eitherMenu(noun: .meeting), "Section or Meetings")
        XCTAssertTrue(AssistWording.nothingToUndoFromTheMenu(noun: .class).contains("the Section or Classes menu"))
        XCTAssertTrue(AssistWording.nothingToUndoFromTheMenu(noun: .meeting).contains("the Section or Meetings menu"))
    }

    /// The Backups list's column names the menu that made the copy.
    func testTheBackupsColumnNamesTheRealMenu() {
        let view: AllBackupsView = AllBackupsView()
        let classes: BackupItem = BackupItem(
            courseCode: "ICS3U", backedUpAt: Date(), fileURL: URL(fileURLWithPath: "/x/ICS3U_backup_2026-08-11_221530_classes-section2.zip"),
            maker: .menu(sectionNumber: 2, inMenu: .classes)
        )
        XCTAssertEqual(view.madeBy(classes, noun: .class), "The Classes menu, Section 2")
        // A club's says Meetings (#990, 2026-11-20 evening).
        XCTAssertEqual(view.madeBy(classes, noun: .meeting), "The Meetings menu, Section 2")
    }

    /// #990's ellipsis ruling: a command that only asks for a confirmation
    /// takes none. MUST FAIL with either ellipsis back.
    func testTheConfirmOnlyCommandsCarryNoEllipsis() throws {
        XCTAssertEqual(SectionMenu.title(for: .removeSection, noun: .class), "Remove Section")
        XCTAssertEqual(SectionMenu.title(for: .cancelScheduledDeploy, noun: .class), "Remove Scheduled Deploy")
        let words: [String: Any] = try XCTUnwrap(
            (try SharedRulesContractTests.section("scheduledDeployCancellation")["removingOne"] as? [String: Any])?["words"]
                as? [String: Any]
        )
        XCTAssertEqual(words["menuItem"] as? String, ScheduledDeployRemovalWording.menuItem)
        XCTAssertEqual(SectionMenu.title(for: .deploy, noun: .class), "Deploy…", "Deploy…'s ellipsis is #996's, not this piece's")
    }
}
