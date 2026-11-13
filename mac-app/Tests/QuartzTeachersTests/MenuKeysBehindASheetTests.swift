import AppKit
import ApplicationServices
import XCTest
@testable import QuartzTeachers

/// A menu key equivalent must not act behind a sheet (#457, the plan
/// review's blocker): a real ⇧⌘D, sent through `NSApp.sendEvent` to the real
/// window with a section selected, reaches Section ▸ Deploy… — and with a
/// sheet attached to that window it must NOT.
///
/// The review measured the failure on a model app: with a sheet up, the
/// window's focused values are still there, the item reads enabled, and the
/// key fires its closure. Two guards stop it here — the item greys while
/// `sheetIsUp`, and `MenuRoute` asks the window again when the item runs —
/// and this test fails if both are taken away.
///
/// Nothing is deployed: `MenuRoute.interceptForTests` reports an item that
/// would run instead of running it. The CONTROL press, with no sheet, is
/// what proves the key reaches the item at all; without it a pass would
/// mean nothing. When the hosted app cannot be made frontmost (a locked
/// screen, another Space, another account using the Mac — #315), the
/// window's focused values never arrive and the control cannot pass, so the
/// test skips and says so.
///
/// **Another app taking the front midway skips too (#846).** The menu bar
/// reads its focused values from the key window of the ACTIVE app, and an
/// app that is not active has no key window at all. MEASURED on 2026-11-13:
/// when another app came forward after the sheet went up (Russell at the Mac
/// during a gate, or another program activating itself), the host was no
/// longer active, `NSApp.keyWindow` was nil, the File menu saw no Plantoir
/// window and showed its NO-window rule (Open Working Folder… and Open
/// Recent live, because with no window they open one), and the test failed
/// on exactly those three items while Deploy… stayed grey. That is the
/// product behaving correctly for an app that is not in front: its menu
/// cannot be used then, and is validated again when it comes back. So the
/// rule for THIS window is asserted directly from the window's own model,
/// whatever is in front, and the real menu is read only while the host has
/// stayed active with the sheet as its key window; if anything took the
/// front at any point after the control, the test skips and says so. It
/// never takes the front back to pass.
@MainActor
final class MenuKeysBehindASheetTests: XCTestCase {

    // MARK: - Functions

    func settle(seconds: Double = 0.8) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    func shiftCommandD(for window: NSWindow) throws -> NSEvent {
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            // What a real ⇧⌘D carries: the menu item's key is "d" with
            // Shift in its mask, and AppKit matches it on the unshifted
            // character (measured: "D" here matched nothing).
            characters: "D",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        ))
    }

    /// Section ▸ Deploy…, freshly updated.
    func deployItem() -> NSMenuItem? {
        return item(titled: "Deploy…", inMenu: "Section")
    }

    func item(titled title: String, inMenu menuName: String) -> NSMenuItem? {
        guard let menu = MenuBarTreeTests.topMenu(named: menuName) else {
            return nil
        }
        for item in MenuBarTreeTests.visibleItems(of: menu) where item.title == title {
            return item
        }
        return nil
    }

    /// What this test says when another app took the front (#846).
    static func frontWasTakenReason(at step: String) -> String {
        return "Another app came to the front " + step + ", so this app had no key window and its menu bar showed the rule for no Plantoir window, which is correct for an app that is not in front (#846). The rule for this window was still checked from its own model; the real menu could not be read for it in this run."
    }

    /// Skips when the host stopped being the active app at any point since
    /// `watch` started, or is not active with `keyWindow` as its key window
    /// now. Checked in the same main-actor turn as the menu read that
    /// follows it, so nothing can change in between.
    func skipIfTheFrontWasTaken(_ watch: ActiveAppWatch, keyWindow: NSWindow, at step: String) throws {
        if watch.resignedActive || !NSApp.isActive || !keyWindow.isKeyWindow {
            throw XCTSkip(MenuKeysBehindASheetTests.frontWasTakenReason(at: step))
        }
    }

    // MARK: - Tests

    func testShiftCommandDDoesNotDeployBehindASheet() async throws {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        guard let workspace = WorkspaceModel.windowModels.first, let window = workspace.window else {
            XCTFail("No window model registered; the interface is not on screen")
            return
        }
        workspace.chooseWorkspace(at: fixtureURL)
        await settle()
        let course: Course = try XCTUnwrap(workspace.teachingCourses.first)
        let sectionNumber: Int = try XCTUnwrap(course.sectionNumbers.first)
        workspace.selection = SidebarSelection.section(course.code, sectionNumber)
        // Frontmost, because a window's focused values reach the menu bar only
        // while it is the key window of the active app. The cooperative
        // `activate()` is refused while another app is in front, so this asks
        // the way a test host has to.
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.isActive {
            // Refused (macOS 14's cooperative activation, with another app in
            // front): asked through accessibility instead, which the suite's
            // window-reading tests already rely on.
            let application: AXUIElement = AXUIElementCreateApplication(getpid())
            AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        window.makeKeyAndOrderFront(nil)
        await settle()

        var ran: [SubjectMenuRules.Item] = []
        MenuRoute.interceptForTests = { item in
            ran.append(item)
        }
        // One folder in Open Recent, so the check below sees a real entry
        // and not only Clear Menu (which an empty list greys anyway).
        let recents: RecentWorkingFolders = RecentWorkingFolders.shared
        let recentsBefore: [RememberedFolder] = recents.entries
        recents.replaceEntriesForTests([RememberedFolder(path: fixtureURL.path, bookmark: nil)])
        defer {
            MenuRoute.interceptForTests = nil
            workspace.selection = nil
            recents.replaceEntriesForTests(recentsBefore)
        }

        // The control: no sheet, so the key reaches Deploy….
        guard deployItem()?.isEnabled == true else {
            throw XCTSkip("Section ▸ Deploy… is not enabled: the hosted window is not frontmost in this run (a locked screen, another Space or another account — #315), so its focused values never reached the menu bar and the key could not be shown to reach the item.")
        }
        // From here on, anything that takes the front is recorded (#846).
        // The press below is sent in the same main-actor turn as the check
        // above, so it reaches the menu while this app is active.
        let watch: ActiveAppWatch = ActiveAppWatch()
        defer { watch.stop() }
        NSApp.sendEvent(try shiftCommandD(for: window))
        await settle(seconds: 0.3)
        XCTAssertEqual(ran, [.deploy], "the control press must reach Section ▸ Deploy…")

        // The same key with a sheet attached.
        ran = []
        let sheet: NSWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.beginSheet(sheet, completionHandler: nil)
        defer {
            if sheet.sheetParent != nil {
                window.endSheet(sheet)
            }
        }
        await settle(seconds: 0.5)
        XCTAssertTrue(workspace.sheetIsUp, "the window knows a sheet is up")
        // The rule for THIS window, read from its own model, so it holds
        // whatever app is in front: with a sheet up, no menu verb is live
        // for it, File's Open items included.
        let enabledForThisWindow: Set<SubjectMenuRules.Item> = SubjectMenuRules.enabledItems(MenuSituation.assemble(
            workspace: workspace, sidebar: nil, site: nil, settings: nil, previewController: nil
        ))
        XCTAssertTrue(enabledForThisWindow.isEmpty, "no menu verb is live for a window with a sheet up: \(enabledForThisWindow)")
        // The real menu shows that rule only while the sheet is the key
        // window of the active app. From this check to the last key press
        // below there is no await, so the front cannot change in between.
        try skipIfTheFrontWasTaken(watch, keyWindow: sheet, at: "after the sheet went up")
        XCTAssertEqual(deployItem()?.isEnabled, false, "Deploy… greys while a sheet is up")
        // And File's Open items, which would otherwise open a SECOND window
        // behind the sheet (the director's ruling on #457's review).
        XCTAssertEqual(item(titled: "Open Working Folder…", inMenu: "File")?.isEnabled, false, "Open Working Folder… greys while a sheet is up")
        // Open Recent's own item stays enabled — SwiftUI keeps a submenu's
        // item live whatever `.disabled` says (measured) — so what greys is
        // every entry inside it.
        let openRecent: NSMenu = try XCTUnwrap(item(titled: "Open Recent", inMenu: "File")?.submenu)
        let entries: [NSMenuItem] = MenuBarTreeTests.visibleItems(of: openRecent)
        var folderEntries: Int = 0
        for entry in entries where !entry.isSeparatorItem && entry.title != "Clear Menu" {
            folderEntries += 1
        }
        XCTAssertEqual(folderEntries, 1, "the seeded folder is in Open Recent: \(entries)")
        for entry in entries where !entry.isSeparatorItem {
            XCTAssertFalse(entry.isEnabled, "Open Recent ▸ \(entry.title) greys while a sheet is up")
        }
        NSApp.sendEvent(try shiftCommandD(for: sheet))
        NSApp.sendEvent(try shiftCommandD(for: window))
        await settle(seconds: 0.3)
        window.endSheet(sheet)
        await settle(seconds: 0.3)
        XCTAssertEqual(ran, [], "⇧⌘D must not deploy behind a sheet")
        XCTAssertFalse(workspace.sheetIsUp)
    }
}

/// Records whether the host stopped being the active app (#846): another
/// app came to the front, even if this one came back afterwards.
@MainActor
final class ActiveAppWatch {

    // MARK: - Stored properties

    private(set) var resignedActive: Bool = false

    private var observer: NSObjectProtocol? = nil

    // MARK: - Initializer

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.resignedActive = true
            }
        }
    }

    // MARK: - Functions

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}
