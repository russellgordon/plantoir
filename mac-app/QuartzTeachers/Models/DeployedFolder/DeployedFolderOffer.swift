import Foundation

/// Whether a section's deployed folder can be opened in the browser, and if
/// not, why (#850). Pure: the facts are gathered by `facts(for:...)` when the
/// menu opens, the section shows, a deploy ends, or the pointer reaches the
/// button (events, never a clock), and the decision is
/// `contracts/shared-rules.json` → `deployedFolderInBrowser.offeredCases`.
nonisolated enum DeployedFolderOffer {

    // MARK: - Types

    /// The facts the decision reads.
    struct Facts: Equatable, Sendable {
        /// The course deploys to a folder, as its first destination or
        /// another one.
        var hasFolderDestination: Bool = false
        /// The course is kept for reference: never deployed, so nothing to show.
        var keptForReference: Bool = false
        /// A deploy of this section is running, from this app or another
        /// program, so the folder is half copied.
        var deployIsRunning: Bool = false
        /// The folder the course deploys into is there.
        var folderExists: Bool = false
        /// `<folder>/section<N>/index.html` is there.
        var sectionIndexExists: Bool = false
    }

    /// What the decision is.
    enum Decision: Equatable, Sendable {
        case offered
        /// Greyed, with the wording key that says why, or nil for no reason
        /// shown.
        case greyed(reasonKey: String?)
        /// Not offered at all: the result panel has no button, and the menu
        /// greys its item with no reason.
        case absent
    }

    // MARK: - Functions

    /// The decision for a set of facts.
    static func decide(_ facts: Facts) -> Decision {
        if facts.keptForReference || !facts.hasFolderDestination {
            return .absent
        }
        if facts.deployIsRunning {
            return .greyed(reasonKey: "deployIsRunning")
        }
        if !facts.folderExists {
            return .greyed(reasonKey: "folderNotFound")
        }
        if !facts.sectionIndexExists {
            return .greyed(reasonKey: "notDeployedYet")
        }
        return .offered
    }

    /// The sentence a reason key stands for.
    @MainActor
    static func sentence(forReasonKey key: String) -> String? {
        switch key {
        case "deployIsRunning":
            return CourseActivity.availableOnceDeployCompleted
        case "folderNotFound":
            return DeployedFolderWording.folderNotFound
        case "notDeployedYet":
            return DeployedFolderWording.notDeployedYet
        default:
            return nil
        }
    }

    /// The folder a course deploys into, as written in its settings: the
    /// first destination when that is a folder, otherwise the first other
    /// destination that is. A course has at most one (`PublishingChoiceView`
    /// offers another folder only when the first is not one). Nil when it
    /// has none.
    static func folderSetting(deployTarget: String, deployFolderPath: String, additional: [(type: String, path: String)]) -> String? {
        if deployTarget == "local_folder" && !deployFolderPath.trimmingCharacters(in: .whitespaces).isEmpty {
            return deployFolderPath
        }
        for target in additional {
            if target.type == "local_folder" && !target.path.trimmingCharacters(in: .whitespaces).isEmpty {
                return target.path
            }
        }
        return nil
    }

    /// Where `deploy.sh --to-folder` puts a section, resolved exactly as it
    /// resolves it (`folderPublishTarget.cases`, which the tests run against
    /// this too): a relative folder is taken from the working folder, one
    /// trailing slash is dropped, and `section<N>` is added.
    static func sectionFolderPath(setting: String, workingFolderPath: String, sectionNumber: Int) -> String {
        var folder: String = setting
        if !folder.hasPrefix("/") {
            folder = workingFolderPath + "/" + folder
        }
        if folder.hasSuffix("/") {
            folder.removeLast()
        }
        return folder + "/section\(sectionNumber)"
    }

    /// The folder itself, resolved the same way without the section.
    static func deployFolderPath(setting: String, workingFolderPath: String) -> String {
        var folder: String = setting
        if !folder.hasPrefix("/") {
            folder = workingFolderPath + "/" + folder
        }
        if folder.hasSuffix("/") {
            folder.removeLast()
        }
        return folder
    }
}
