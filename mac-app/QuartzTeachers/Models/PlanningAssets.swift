import Foundation

/// Keeps a course's plan stylesheets and fonts the app's own (#708,
/// `contracts/shared-rules.json` → `unitPlanning.tab.assetsMirror`).
///
/// `assets/` in a planning folder belongs to Plantoir, not to the plan
/// (`unitPlanning.assetsAreThePlantoirs`): the skill copies it whole from its
/// template. So whenever the Planning tab shows a plan, the folder's
/// `assets/` is first made the same as the template's in the app's bundle,
/// which the skill's copy came from, with `WorkspaceModel.syncDirectory`
/// (changed files copied, extra files removed). The preview then shows the
/// look this release ships, and sharing a plan (#709) uploads the same bytes,
/// because it refreshes the same folder from the same place.
///
/// It never MAKES a planning folder: a course with no plans keeps no empty
/// folder to be backed up for nothing. A failure is logged and changes
/// nothing on screen; the plan still shows with the copy it has. On the main
/// actor, where the tab asks for it: the folder is about twenty small files.
enum PlanningAssets {

    // MARK: - Stored properties

    /// Where the template's `assets/` sits inside the guidance for assistants.
    static let templateAssetsPath: String = "skills/plantoir-unit-planning/template/assets"

    /// The folder's name inside the planning folder.
    static let folderName: String = "assets"

    // MARK: - Functions

    /// The template's `assets/` in the app's bundle, or nil without one.
    static var bundledTemplateAssets: URL? {
        guard let guidance = ToolchainReadiness.bundledGuidanceURL else {
            return nil
        }
        return guidance.appendingPathComponent(templateAssetsPath, isDirectory: true)
    }

    /// Makes `planningFolder/assets` the same as `source`. Nil, having done
    /// nothing, when the planning folder does not exist or `source` is not
    /// there.
    @discardableResult
    static func refresh(
        planningFolder: URL, from source: URL? = PlanningAssets.bundledTemplateAssets
    ) -> WorkspaceModel.MirrorOutcome? {
        let fileManager: FileManager = FileManager.default
        var isFolder: ObjCBool = false
        if !fileManager.fileExists(atPath: planningFolder.path, isDirectory: &isFolder) || !isFolder.boolValue {
            return nil
        }
        guard let source else {
            return nil
        }
        var sourceIsFolder: ObjCBool = false
        if !fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsFolder) || !sourceIsFolder.boolValue {
            return nil
        }
        let destination: URL = planningFolder.appendingPathComponent(folderName, isDirectory: true)
        let outcome: WorkspaceModel.MirrorOutcome = WorkspaceModel.syncDirectory(from: source, to: destination)
        if outcome.failed > 0 {
            AppLog.interface.error(
                "could not refresh a unit plan's stylesheets in \(LogRedactor.redacting(destination.path), privacy: .public): \(outcome.failed) file(s), first: \(LogRedactor.redacting(outcome.firstFailure ?? ""), privacy: .public)"
            )
        }
        return outcome
    }
}
