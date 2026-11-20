import XCTest
@testable import QuartzTeachers

/// #990, the menus' piece of the HIG review (#975): what the Course and
/// Section menus draw that `MenuBarTreeTests` cannot see on one Mac.
///
/// - **D11 (Russell's ruling Q9):** every Revise With item is drawn on every
///   Mac, and one this Mac does not have is dimmed. `MenuBarTreeTests` reads
///   the real menu bar, but on a Mac that has every assistant it cannot tell
///   a dimmed item from a hidden one, so the rule is pinned here on
///   `ReviseWithMenu.entries`, the function the submenu draws from.
/// - **Ruling Q14:** no grey explanatory text rows in the Course and Section
///   menus. A row appears only in particular states (a deploy running, the
///   Planning tab, a session open elsewhere), which a hosted test cannot set
///   up through the focused values, so the menus' source is read: a `Text`
///   anywhere in `SubjectMenus.swift` is a text row in a menu.
@MainActor
final class SubjectMenusHIGTests: XCTestCase {

    // MARK: - Functions

    static func everyItemEnabled() -> Set<SubjectMenuRules.Item> {
        var items: Set<SubjectMenuRules.Item> = []
        for item in SubjectMenuRules.Item.allCases {
            items.insert(item)
        }
        return items
    }

    static func entries(claude: Bool, codex: Bool, copilot: Bool, local: Bool, enabled: Set<SubjectMenuRules.Item>) -> [ReviseWithMenu.Entry] {
        return ReviseWithMenu.entries(
            claudeIsInstalled: claude,
            codexIsInstalled: codex,
            copilotIsInstalled: copilot,
            localAssistantCanRun: local,
            claude: .sectionReviseWithClaude,
            codex: .sectionReviseWithCodex,
            copilot: .sectionReviseWithCopilot,
            localAssistant: .sectionReviseWithLocalAssistant,
            enabled: enabled
        )
    }

    static func titles(_ entries: [ReviseWithMenu.Entry]) -> [String] {
        var titles: [String] = []
        for entry in entries {
            titles.append(entry.title)
        }
        return titles
    }

    // MARK: - Tests

    /// A Mac with no assistant at all still shows all four, each dimmed.
    /// MUST FAIL if an item is left out for an assistant this Mac lacks.
    func testEveryAssistantIsDrawnAndDimmedWhenThisMacLacksIt() {
        let entries: [ReviseWithMenu.Entry] = SubjectMenusHIGTests.entries(
            claude: false, codex: false, copilot: false, local: false,
            enabled: SubjectMenusHIGTests.everyItemEnabled()
        )
        XCTAssertEqual(SubjectMenusHIGTests.titles(entries), [
            ClaudeCodeLauncher.menuItemTitle,
            CodexLauncher.menuItemTitle,
            CopilotLauncher.menuItemTitle,
            ReviseWithMenu.localAssistantTitle,
        ])
        for entry in entries {
            XCTAssertFalse(entry.isEnabled, "\(entry.title) is dimmed on a Mac without it")
        }
    }

    /// Each item is enabled only when this Mac has it AND the rule allows it
    /// (#458's greying stays). MUST FAIL if installing one enables another.
    func testAnItemIsEnabledOnlyWhenInstalledAndAllowed() {
        let onlyCodex: [ReviseWithMenu.Entry] = SubjectMenusHIGTests.entries(
            claude: false, codex: true, copilot: false, local: false,
            enabled: SubjectMenusHIGTests.everyItemEnabled()
        )
        var enabledTitles: [String] = []
        for entry in onlyCodex where entry.isEnabled {
            enabledTitles.append(entry.title)
        }
        XCTAssertEqual(enabledTitles, [CodexLauncher.menuItemTitle])

        let everythingButBlocked: [ReviseWithMenu.Entry] = SubjectMenusHIGTests.entries(
            claude: true, codex: true, copilot: true, local: true,
            enabled: [.sectionReviseWithCopilot]
        )
        var allowed: [String] = []
        for entry in everythingButBlocked where entry.isEnabled {
            allowed.append(entry.title)
        }
        XCTAssertEqual(allowed, [CopilotLauncher.menuItemTitle], "the rule still greys an installed one")
    }

    /// Ruling Q14: the Course and Section menus hold commands only — no
    /// `Text` row under Rename, Revert, Open in Browser, the start-of-year
    /// group or inside Revise With. MUST FAIL on `dev` before #990, which
    /// drew five.
    func testTheSubjectMenusHoldNoTextRows() throws {
        let source: String = try String(contentsOf: SubjectMenusHIGTests.subjectMenusURL(), encoding: .utf8)
        var rows: [String] = []
        for line in source.components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                continue
            }
            if trimmed.contains("Text(") {
                rows.append(trimmed)
            }
        }
        XCTAssertEqual(rows, [], "a Text in a menu is a grey text row")
    }

    /// #990 review (MEDIUM): with the grey row gone, Revert dimmed on the
    /// Planning tab still says why — as the item's help tag (HIG, Offering
    /// help: "Consider offering context-sensitive tooltips … different text
    /// for a control's different states"), which AppKit also hands
    /// VoiceOver as the item's help. The words come from the page in front
    /// (`CourseSettingsCommands.revertHelp`: `PlanningWording.revertOnPlanning`
    /// on Planning, nothing on Settings). The focused value cannot be set up
    /// in a hosted test, so the source is read; the running app was measured
    /// (documentation/09 → "No grey text rows"). MUST FAIL on 23b554773,
    /// where nothing said why.
    func testRevertSaysWhyItIsDimmedOnPlanning() throws {
        let source: String = try String(contentsOf: SubjectMenusHIGTests.subjectMenusURL(), encoding: .utf8)
        XCTAssertTrue(source.contains(
            "item(\"Revert Course Settings\", .revertCourseSettings, enabled)\n                .help(settings?.revertHelp ?? \"\")"
        ), "Revert carries the page's reason as its help tag")
    }

    static func subjectMenusURL() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/App/SubjectMenus.swift")
    }
}
