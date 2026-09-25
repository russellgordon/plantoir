import Foundation
import Observation

/// What is on this Mac, what the teacher has chosen, and what they are allowed
/// to do about it right now.
///
/// The settings panel is a view over three things that did not previously know
/// about each other: the stored choice (`AppSettings`), the files on disk
/// (`AssistModelStore`, one per rung), and whether an assistant window is open
/// (`AssistActivity`). Putting the answers here rather than in the view is
/// what lets the rules be tested without standing a window up — and the rule
/// that matters most, "you cannot remove it out from under a conversation", is
/// exactly the one nobody would test through a view.
@Observable
@MainActor
final class AssistModelLibrary {

    // MARK: - Stored properties

    /// What this Mac can give the assistant. Injectable so a test can ask what
    /// an 8 GB laptop would be told without owning one.
    let budget: AssistHardwareBudget

    /// Where the settings are remembered.
    @ObservationIgnored private let settings: AppSettings

    /// Bumped whenever this panel changes what is on disk.
    ///
    /// See `diskState` for why an observable counter is needed at all when the
    /// answers are read straight off the file system.
    private(set) var revision: Int = 0

    // MARK: - Computed properties

    /// Touched by every answer that is read off the DISK rather than out of a
    /// property, so that SwiftUI has something observable to depend on.
    ///
    /// **This is not ceremony, and leaving it out produces a bug that survives
    /// closing and reopening the window.** SwiftUI's observation notices a
    /// view read an `@Observable` property; it cannot notice a view read the
    /// file system. `bytesOnDisk` and `isDownloaded` call `FileManager`, so
    /// removing a model changed the answers and invalidated nothing.
    ///
    /// What made it worth a comment rather than a one-line fix is WHERE it
    /// showed. A `Section`'s `content`, `header` and `footer` closures are
    /// tracked SEPARATELY, so the rows — which read a store's observable
    /// `state` — redrew correctly while the two summary sentences in the
    /// footers, which read only the disk, kept describing a model that had
    /// just been deleted. Half a panel updating is far more convincing than
    /// none of it updating, and it was found by pressing the button in the
    /// real app rather than by any test.
    private var diskState: Int {
        return revision
    }

    /// Which assistant the teacher has asked for.
    var choice: AssistModelChoice {
        get {
            return settings.assistantModelChoice
        }
        set {
            guard newValue != settings.assistantModelChoice else {
                return
            }
            settings.assistantModelChoice = newValue
            ActivityTrail.note(
                .assistantModelChosen,
                "chose \(describe(newValue)) in Settings"
            )
            revision += 1
        }
    }

    /// Whether the assistant asks before it changes anything.
    var asksBeforeChanging: Bool {
        get {
            return settings.assistantAsksBeforeChanging
        }
        set {
            guard newValue != settings.assistantAsksBeforeChanging else {
                return
            }
            settings.assistantAsksBeforeChanging = newValue
            ActivityTrail.note(
                .assistantConfirmationChanged,
                newValue
                    ? "turned ON asking before the assistant changes anything"
                    : "turned OFF asking before the assistant changes anything — "
                      + "it will now act straight away"
            )
            revision += 1
        }
    }

    /// Said when confirmation is off and the smaller assistant is the one
    /// running, or nil when there is nothing to caution about.
    ///
    /// A caution rather than a locked switch: which assistant is running
    /// changes the ODDS, not whose decision it is. What a teacher is owed is
    /// the measured number, in a sentence, at the moment they turn it off.
    var confirmationCaution: String? {
        guard !asksBeforeChanging, chosenTier == .small else {
            return nil
        }
        return "The smaller assistant misreads about one request in five, so it will sometimes "
             + "do the wrong thing without asking first. “Undo that” takes back whatever it did."
    }

    /// Which assistant actually runs, once the choice has been applied.
    var chosenTier: AssistModelTier {
        return choice.resolved(for: budget)
    }

    /// What every rung costs on this Mac's disk, in the order they are shown.
    var tiers: [AssistModelTier] {
        return AssistModelTier.allCases
    }

    /// The space all downloaded assistants take together, or nil when none
    /// are here. Shown as one figure because that is the question being asked
    /// — "what is this costing me?" — and it is not the sum of the two
    /// advertised sizes unless both happen to be present.
    var bytesOnDisk: Int64? {
        _ = diskState
        var total: Int64 = 0
        var found: Bool = false
        for tier in AssistModelTier.allCases {
            if let size = AssistModelStore.bytesOnDisk(for: tier) {
                total += size
                found = true
            }
        }
        if !found {
            return nil
        }
        return total
    }

    // MARK: - Initializer

    init(budget: AssistHardwareBudget = AssistHardwareBudget.current(),
         settings: AppSettings? = nil) {
        self.budget = budget
        self.settings = settings ?? AppSettings.shared
    }

    // MARK: - Functions

    /// The store for one rung.
    ///
    /// Shared with every assistant window through `AssistModelStores`, rather
    /// than made here — see that type for the double-download this prevents.
    /// The panel deals with BOTH rungs, not only the chosen one: a teacher who
    /// switches down to save memory usually wants the larger file gone too,
    /// and they could not ask for that if the panel only knew about one.
    func store(for tier: AssistModelTier) -> AssistModelStore {
        return AssistModelStores.store(for: tier)
    }

    /// Look at the disk again.
    ///
    /// Needed because the panel's answers about what is downloaded come from
    /// `FileManager`, which nothing can observe. The window stays alive for
    /// the whole run of the app — macOS hides a settings window rather than
    /// destroying it — so without this, a panel opened once would describe the
    /// disk as it was that moment for the rest of the day.
    func refresh() {
        revision += 1
    }

    /// Is this one here and usable?
    func isDownloaded(_ tier: AssistModelTier) -> Bool {
        _ = diskState
        return store(for: tier).isReady
    }

    /// What this one takes on disk, in words, or nil when it is not here.
    func spaceDescription(for tier: AssistModelTier) -> String? {
        _ = diskState
        guard let bytes = AssistModelStore.bytesOnDisk(for: tier) else {
            return nil
        }
        let formatter: ByteCountFormatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Fetch one ahead of time, rather than at the moment a teacher first
    /// wants to ask something.
    ///
    /// Worth offering on its own: the download is gigabytes, and the moment
    /// it is otherwise triggered is the moment somebody has just opened the
    /// assistant because they wanted an answer NOW. Doing it from Settings on
    /// a free evening is the same bytes at a far better time.
    func download(_ tier: AssistModelTier) {
        store(for: tier).download()
        revision += 1
    }

    /// Why this one cannot be removed at the moment, in the teacher's words,
    /// or nil when it can be.
    ///
    /// Naming the section rather than saying "not available" is the same rule
    /// `AssistActivity.reasonItIsUnavailable` follows: somebody told they
    /// cannot do a thing needs to know what to close, and a Plantoir window
    /// can be behind three others.
    ///
    /// The guard is deliberately about ANY open assistant, not about whether
    /// that window happens to be using this particular rung. The window loaded
    /// whatever was chosen when it opened, and the choice can have been
    /// changed since; working out which file is genuinely mapped means
    /// tracking state the app does not keep, and getting it wrong deletes the
    /// weights out from under a running engine. One open assistant, no
    /// removals — a rule a teacher can hold in their head, and the same
    /// "assistant is a thing you have open" shape as everywhere else.
    func reasonItCannotBeRemoved(_ tier: AssistModelTier) -> String? {
        _ = diskState
        guard AssistModelStore.bytesOnDisk(for: tier) != nil else {
            return nil
        }
        guard let active = AssistActivity.active else {
            return nil
        }
        return AssistActivity.closeTheAssistant(active, "before removing this.")
    }

    /// Whether the Remove button does anything right now.
    func mayRemove(_ tier: AssistModelTier) -> Bool {
        _ = diskState
        if AssistModelStore.bytesOnDisk(for: tier) == nil {
            return false
        }
        return reasonItCannotBeRemoved(tier) == nil
    }

    /// Delete one to get the space back. Does nothing when it is not allowed,
    /// so a stale view cannot remove what the panel says it cannot.
    func remove(_ tier: AssistModelTier) {
        guard mayRemove(tier) else {
            return
        }
        store(for: tier).remove()
        revision += 1
    }

    /// What is next to happen if the teacher opens the assistant now.
    ///
    /// A settings panel that only lets somebody change a setting leaves them
    /// guessing what it did. This is the one line that answers it, and it is
    /// the sentence the removal case most needs: removing the model you use
    /// is fine, and a teacher should be able to see that the cost is a
    /// download next time rather than a broken assistant.
    var whatHappensNext: String {
        _ = diskState
        if isDownloaded(chosenTier) {
            return "\(chosenTier.choiceLabel) is ready. Opening the assistant will use it."
        }
        return "\(chosenTier.choiceLabel) is not on this Mac yet. Opening the assistant "
             + "will offer to download it — \(chosenTier.downloadDescription)."
    }

    /// One choice, for the trail. Says which assistant it landed on as well as
    /// which button was pressed, because "chose automatic" months later does
    /// not answer the question anybody is asking.
    private func describe(_ choice: AssistModelChoice) -> String {
        guard choice.namedTier != nil else {
            return "to have Plantoir choose — \(budget.tier.displayName) on this Mac"
        }
        return choice.resolved(for: budget).displayName
    }
}
