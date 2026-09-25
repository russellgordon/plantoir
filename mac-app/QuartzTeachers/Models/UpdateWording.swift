import Foundation

/// Every sentence of OURS a teacher reads while Plantoir updates itself
/// (#204) — written once, here.
///
/// Retyped from `contracts/shared-rules.json` → `appUpdates.wording` and
/// pinned against it both ways by `UpdateWordingTests`, the arrangement
/// `CopyPageWording` and `ReferenceWording` already use. NOT in
/// `AssistWording`: the assistant never says any of these, and putting them
/// there would move a generated contract for no reason.
///
/// **Whose words these are not.** The update window itself — "A new version
/// of Plantoir is available!", its buttons, the progress and error windows —
/// is the updater's own, localized by it, and cannot be changed without
/// keeping a fork of it (`appUpdates.updatersOwnWords`). What is here is what
/// the updater has no words for: the menu item, why an update is waiting,
/// and the managed-Mac refusal it passes over in silence.
///
/// **The register.** A new version, updating, installing. Never the
/// updater's name, and never a word about how it is done (rule 1).
nonisolated enum UpdateWording {

    // MARK: - Stored properties

    /// Under "About Plantoir" in the application menu — the title every Mac
    /// application uses, so a teacher who has updated anything else finds it.
    static let menuItem: String = "Check for Updates…"

    /// The button that closes either of the two notices below.
    static let okButton: String = "OK"

    /// Said under the held notice's title, and TRUE on quit: before the
    /// plan review (H1) this promised that nothing changed until the work was
    /// done, while a quit installed the update anyway. A quit now sets it
    /// aside (`appUpdates.atQuit`), which is what the last sentence says.
    static let heldExplanation: String =
        "The new version is ready. Plantoir will close and open again by itself as soon as "
        + "that is finished. If you quit Plantoir before then, the update is set aside and "
        + "offered again later."

    /// When the updater asked for an administrator and nobody gave one — the
    /// managed school Mac. The updater itself says nothing at all (it drops
    /// error 4007 silently), so this is the only explanation there is.
    static let needsAdministratorTitle: String = "Plantoir could not install the new version."

    static let needsAdministratorExplanation: String =
        "Installing it on this Mac needs an administrator’s name and password. Whoever looks "
        + "after this Mac can install it for you, or choose Check for Updates… again when an "
        + "administrator is with you."

    // MARK: - Functions

    /// The held notice's title. `work` is one of the phrases below, or the
    /// quit question's own phrase for this app's work
    /// (`QuitConfirmation.workUnderWay`) — one description of the same facts,
    /// not two.
    static func heldTitle(work: String) -> String {
        return "Plantoir will finish updating once it is done \(work)."
    }

    /// A publish set for later that is running now, named from the run's own
    /// arguments.
    static func scheduledWork(course: String, section: Int) -> String {
        return "publishing Section \(section) of \(course) on its schedule"
    }

    /// The same, for a job set before v1.2.0, whose run names no course.
    static let scheduledWorkUnnamed: String = "publishing on its schedule"

    /// A build or publish another program holds a lease for. Names the
    /// COURSE and no program, the way
    /// `AssistWording.courseIsBeingBuiltElsewhere` does and for its reason:
    /// the lease names only the course, and the sentence has to be true
    /// whichever program holds it.
    static func elsewhereWork(course: String) -> String {
        return "building \(course) somewhere else on this Mac"
    }
}
