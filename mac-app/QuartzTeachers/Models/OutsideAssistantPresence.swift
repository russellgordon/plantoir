import Foundation
import Observation

/// Whether each Revise With item EXISTS on this Mac — Claude installed, Codex
/// installed, the local assistant able to run — asked at launch and whenever
/// Plantoir becomes the active app, and read by the menu bar (#457).
///
/// **Presence follows the Mac, enablement follows the selection.** The plan
/// first carried these flags in the window's focused value; the review found
/// that makes the menu's SHAPE depend on focus — with no Plantoir window key
/// (no window, or the assistant, Settings or About in front) there is no
/// value, so the menu could not know whether to draw the items at all. So
/// presence is app-level, here, and the focused value carries enablement
/// only.
///
/// Never asked while the menu bar is drawn: `isAvailable` looks on the disk,
/// and the commands tree is re-evaluated far more often than a teacher opens
/// a menu (Canopy's "no I/O in the commands tree"). Each property is assigned
/// only when it changes, so a refresh that finds nothing new does not rebuild
/// the menu bar.
@Observable
final class OutsideAssistantPresence {

    // MARK: - Stored properties

    static let shared: OutsideAssistantPresence = OutsideAssistantPresence()

    private(set) var claudeIsInstalled: Bool = false
    private(set) var codexIsInstalled: Bool = false
    private(set) var localAssistantCanRun: Bool = false

    // MARK: - Functions

    /// Asks the Mac again.
    func refresh() {
        let claude: Bool = ClaudeCodeLauncher.isAvailable
        let codex: Bool = CodexLauncher.isAvailable
        let local: Bool = AssistHardwareBudget.current().canRunAssistant
        if claude != claudeIsInstalled {
            claudeIsInstalled = claude
        }
        if codex != codexIsInstalled {
            codexIsInstalled = codex
        }
        if local != localAssistantCanRun {
            localAssistantCanRun = local
        }
    }

    /// Whether the Revise With submenu has anything in it at all.
    var anyReviseTargetExists: Bool {
        return claudeIsInstalled || codexIsInstalled || localAssistantCanRun
    }
}
