import Foundation

/// What enables Course Settings' Save and Revert, and what is said when Save
/// is held back (#364, #373). One place, so the button's state, its look and
/// the sentence beside it can never disagree.
///
/// The rule, in `contracts/shared-rules.json` → `savingSettings.whatEnablesSave`:
/// Save is enabled exactly when this window's copy differs from what it last
/// read or wrote AND nothing holds it back; Revert exactly when it differs. A
/// destination problem holds Save back ONLY when the unsaved changes move
/// where the course publishes — a folder missing on this Mac is not made
/// worse by saving a section's colour scheme, and blocking that save was the
/// likeliest real cause of #373.
enum SaveEnablement {

    // MARK: - Stored properties

    /// Which check found a destination problem, for the trail — never the
    /// path and never the ID, which can carry a name.
    enum Check: String {
        case deployFolder = "deploy folder"
        case cloudflareAccountID = "cloudflare account id"
        case additionalDestination = "additional destination"
    }

    /// A destination problem: the sentence a teacher reads, and which check
    /// it came from.
    struct DestinationProblem: Equatable {
        var sentence: String
        var check: Check
    }

    // MARK: - Functions

    /// The first problem with where this course publishes, as it is set in
    /// this window now, or nil. The same checks Course Settings has always
    /// made, moved here unchanged so a test can reach them.
    static func destinationProblem(
        for configuration: CourseConfiguration,
        cloudflareAccountID: String
    ) -> DestinationProblem? {
        if configuration.deployTarget == "local_folder" {
            if let problem = CourseConfiguration.deployFolderProblem(forPath: configuration.deployFolderPath) {
                return DestinationProblem(sentence: problem, check: .deployFolder)
            }
        }
        if configuration.deploysToCloudflare {
            if let problem = CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID) {
                return DestinationProblem(sentence: problem, check: .cloudflareAccountID)
            }
        }
        // Every ADDITIONAL destination gets the same check — a redundancy
        // target with no valid folder or credential would otherwise only
        // fail the first time a deploy actually reached it.
        for target in configuration.additionalDeployTargets {
            if target.type == "local_folder" {
                if let problem = CourseConfiguration.deployFolderProblem(forPath: target.path) {
                    return DestinationProblem(sentence: problem, check: .additionalDestination)
                }
            }
            if target.type == "cloudflare_pages" {
                if let problem = CourseConfiguration.cloudflareAccountProblem(forID: cloudflareAccountID) {
                    return DestinationProblem(sentence: problem, check: .additionalDestination)
                }
            }
        }
        return nil
    }

    /// The problem that holds Save back, or nil. A destination problem holds
    /// it back only when the unsaved changes move the destination; otherwise
    /// Save proceeds and the problem stays reported where it always was,
    /// under Deploying.
    static func holdingProblem(
        destinationProblem: DestinationProblem?,
        destinationsChanged: Bool
    ) -> DestinationProblem? {
        guard destinationsChanged else {
            return nil
        }
        return destinationProblem
    }

    static func saveIsEnabled(hasUnsavedChanges: Bool, holdingProblem: DestinationProblem?) -> Bool {
        return hasUnsavedChanges && holdingProblem == nil
    }

    static func revertIsEnabled(hasUnsavedChanges: Bool) -> Bool {
        return hasUnsavedChanges
    }

    /// There is something to save and something stops it: the one state in
    /// which the reason is said beside Save.
    static func saveIsHeldBack(hasUnsavedChanges: Bool, holdingProblem: DestinationProblem?) -> Bool {
        return hasUnsavedChanges && holdingProblem != nil
    }

    /// Save wears the accent colour only when it can be pressed (#364). A
    /// disabled accent button, (17,70,126) on a dark window, read as enabled
    /// in v1.4.0's own marketing picture; a plain bordered button is the
    /// system's disabled look in both appearances.
    static func saveWearsTheAccent(hasUnsavedChanges: Bool, holdingProblem: DestinationProblem?) -> Bool {
        return saveIsEnabled(hasUnsavedChanges: hasUnsavedChanges, holdingProblem: holdingProblem)
    }

    /// Whether to write `settings save held back` now: on the change from
    /// not held back to held back, once per visit to the course.
    static func shouldNoteHeldBack(wasHeldBack: Bool, isHeldBack: Bool, alreadyNoted: Bool) -> Bool {
        return isHeldBack && !wasHeldBack && !alreadyNoted
    }

    /// The trail line. Says which check, never the path or the ID — and reads
    /// as a HOLD, not a failure: no Save was pressed (#373 review, N2).
    static func heldBackTrailLine(courseCode: String, check: Check) -> String {
        var what: String = ""
        switch check {
        case .deployFolder:
            what = "the publishing folder needs attention"
        case .cloudflareAccountID:
            what = "the Cloudflare account ID on this Mac needs attention"
        case .additionalDestination:
            what = "an additional publishing destination needs attention"
        }
        return "Save held back for " + courseCode + " (" + check.rawValue + ") — " + what
    }
}
