import Foundation

/// The teacher's one answer about Obsidian's add-ons for diagrams and graphs
/// (#495), app-wide: one yes covers every course (director ruling on #495).
///
/// Persisted raw values are the contract's `answer.values`
/// (`obsidianAddOnsForFigures.answer`): never rename a case, or a teacher's
/// answer reads as not asked.
nonisolated enum ObsidianFigureAddOnsAnswer: String, CaseIterable, Sendable {

    /// Never answered — or answered Not Now, which is remembered only for
    /// this run of Plantoir.
    case notAsked

    /// Add Them, or the Settings toggle turned on.
    case yes

    /// Not Now with "Don't ask again", or the Settings toggle turned off.
    case no

    // MARK: - Functions

    /// The stored text, read as the contract's `answer.cases` say: anything
    /// unreadable is `notAsked`.
    static func reading(stored: String?) -> ObsidianFigureAddOnsAnswer {
        guard let stored else {
            return .notAsked
        }
        return ObsidianFigureAddOnsAnswer(rawValue: stored) ?? .notAsked
    }
}

/// The words of #495, in one place. Pinned against
/// `obsidianAddOnsForFigures.wording` (ObsidianFigureAddOnsTests), with
/// rule 1's ban applied after Obsidian's own quoted labels are taken out.
///
/// Obsidian's labels are quoted exactly as 1.13.7 shows them in English
/// (plan review S9, read from its `i18n.js`): the trust question's two
/// buttons, the settings tab, and the button that leaves Restricted mode.
/// The trust question puts its focus on "Browse vault in Restricted Mode", so
/// a teacher who presses Return gets Restricted mode — the offer says so.
nonisolated enum ObsidianFigureAddOnsWording {

    // MARK: - Stored properties

    /// The offer, asked at Open in Obsidian before Obsidian opens.
    static let offerTitle: String = "Show diagrams and graphs in Obsidian too?"
    static let offerMessage: String = "{course} has diagrams or graphs that your class website draws. Plantoir can add the Obsidian add-ons that draw them, so you see the same pictures while you write. Your answer applies to every course that has them.\n\nThe first time each course opens with them, Obsidian asks whether you trust the author of its pages — that is you. Click “Trust author and enable plugins”: pressing Return chooses the other button. Obsidian then opens its settings to show the add-ons switched on; close them to go on writing."

    /// Added under the offer when the course is open in Obsidian now.
    static let offerWhileOpen: String = "{course} is open in Obsidian now, so Obsidian closes and opens it again to show them. What you've written is kept."

    /// The offer's answers.
    static let offerAdd: String = "Add Them"
    static let offerNotNow: String = "Not Now"
    static let dontAskAgain: String = "Don't ask again"

    /// Asked when the answer is yes and the course is open in Obsidian:
    /// nothing is written into an open course (plan review S3).
    static let reopenTitle: String = "Reopen Obsidian to show diagrams and graphs?"
    static let reopenMessage: String = "{course} has diagrams or graphs that Obsidian can't draw yet. Obsidian sees the add-ons that draw them only when it opens the course again, so it closes and opens again. What you've written is kept.\n\nIf Obsidian asks whether you trust the author, click “Trust author and enable plugins”."
    static let reopen: String = "Reopen Obsidian"
    static let later: String = "Later"

    /// Plantoir ▸ Settings ▸ Obsidian.
    static let paneTitle: String = "Obsidian"
    static let settingLabel: String = "Add the add-ons that draw diagrams and graphs to courses that have them"
    static let settingFooter: String = "Plantoir adds them when you open such a course in Obsidian from Plantoir, and after you preview it. The first time each course opens with them, Obsidian asks whether you trust its author: click “Trust author and enable plugins” — pressing Return chooses “Browse vault in Restricted Mode”. If a course still shows a drawing's text, open Obsidian's Settings ▸ “Community plugins” and click “Exit Restricted mode”. Turning this off adds nothing new and leaves what was added in place."

    // MARK: - Functions

    /// The offer's whole message: the sentence about closing Obsidian is
    /// added when the course is open in it now.
    static func offerText(course: String, courseIsOpen: Bool) -> String {
        var text: String = ObsidianFigureAddOnsWording.filling(ObsidianFigureAddOnsWording.offerMessage, course: course)
        if courseIsOpen {
            text += "\n\n" + ObsidianFigureAddOnsWording.filling(ObsidianFigureAddOnsWording.offerWhileOpen, course: course)
        }
        return text
    }

    /// A sentence with the course's code in it.
    static func filling(_ sentence: String, course: String) -> String {
        return sentence.replacingOccurrences(of: "{course}", with: course)
    }
}

/// The rules of #495's asking, as pure functions, so the contract's cases run
/// against them without a window: `sequence`, `offerCases`, `previewCases`
/// and `whichVaultOpens.cases`.
nonisolated enum ObsidianFigureAddOnsOffer {

    // MARK: - Types

    /// Everything Open in Obsidian knows when it decides.
    struct Situation: Equatable, Sendable {

        // MARK: - Stored properties

        var reference: Bool
        var obsidianInstalled: Bool
        var answer: ObsidianFigureAddOnsAnswer
        /// Not Now was chosen earlier in this run of Plantoir.
        var suppressedThisRun: Bool
        /// A pass would add something to this course.
        var wouldAdd: Bool
        /// The vault Obsidian will open for this course IS the course
        /// (`whichVaultOpens`) — or none holds it yet and the course will be
        /// registered as one.
        var vaultIsTheCourse: Bool
        var courseOpenInObsidian: Bool
        /// Later was chosen for this course earlier in this run.
        var reopenDeclinedThisRun: Bool
    }

    /// What Open in Obsidian does.
    enum Decision: String, CaseIterable, Sendable {
        /// Open, as before #495.
        case justOpen
        /// Open, and say on the trail why nothing was offered: Obsidian
        /// opens the course inside a larger vault, which never reads the
        /// course's own settings (plan review S7).
        case notTheVault
        /// Ask the three-answer question, then open.
        case offer
        /// The same, while the course is open in Obsidian: Add Them closes
        /// Obsidian, adds them and opens it again — one dialog, not two
        /// (plan review N6).
        case offerWhileOpen
        /// Add them, then open.
        case installThenOpen
        /// Ask whether to reopen Obsidian; nothing is written into an open
        /// course.
        case askReopen
    }

    /// What a finished preview does (the second trigger).
    enum PreviewDecision: String, CaseIterable, Sendable {
        case nothing
        case install
    }

    // MARK: - Functions

    /// Whether Open in Obsidian scans the course at all: never for a
    /// reference course, without Obsidian, with the answer no, or after Not
    /// Now this run (`sequence` steps 1–3).
    static func scans(reference: Bool, obsidianInstalled: Bool, answer: ObsidianFigureAddOnsAnswer, suppressedThisRun: Bool) -> Bool {
        if reference || !obsidianInstalled {
            return false
        }
        if answer == .no {
            return false
        }
        if answer == .notAsked && suppressedThisRun {
            return false
        }
        return true
    }

    /// `offerCases`.
    static func decision(_ situation: Situation) -> Decision {
        if !ObsidianFigureAddOnsOffer.scans(
            reference: situation.reference,
            obsidianInstalled: situation.obsidianInstalled,
            answer: situation.answer,
            suppressedThisRun: situation.suppressedThisRun
        ) {
            return .justOpen
        }
        if !situation.wouldAdd {
            return .justOpen
        }
        if !situation.vaultIsTheCourse {
            return .notTheVault
        }
        if situation.answer == .notAsked {
            return situation.courseOpenInObsidian ? .offerWhileOpen : .offer
        }
        if !situation.courseOpenInObsidian {
            return .installThenOpen
        }
        if situation.reopenDeclinedThisRun {
            return .justOpen
        }
        return .askReopen
    }

    /// `previewCases`: only after the yes, never into a course open in
    /// Obsidian (S3), never without Obsidian (N8).
    static func afterAPreview(
        reference: Bool,
        obsidianInstalled: Bool,
        answer: ObsidianFigureAddOnsAnswer,
        wouldAdd: Bool,
        vaultIsTheCourse: Bool,
        courseOpenInObsidian: Bool
    ) -> PreviewDecision {
        if reference || !obsidianInstalled || answer != .yes {
            return .nothing
        }
        if !wouldAdd || !vaultIsTheCourse || courseOpenInObsidian {
            return .nothing
        }
        return .install
    }

    /// The vault Obsidian opens for a path: the longest registered vault
    /// that is the path or holds it (measured from 1.13.7's `main.js`), or
    /// nil when none does — and then Plantoir registers the course itself.
    static func vaultThatOpens(targetPath: String, registryData: Data?) -> String? {
        guard let registryData else {
            return nil
        }
        guard let registry = try? JSONSerialization.jsonObject(with: registryData) as? [String: Any] else {
            return nil
        }
        guard let vaults = registry["vaults"] as? [String: Any] else {
            return nil
        }
        var best: String?
        for vaultEntry in vaults.values {
            guard let vault = vaultEntry as? [String: Any] else {
                continue
            }
            guard let vaultPath = vault["path"] as? String else {
                continue
            }
            if targetPath == vaultPath || targetPath.hasPrefix(vaultPath + "/") {
                if vaultPath.count > (best?.count ?? -1) {
                    best = vaultPath
                }
            }
        }
        return best
    }

    /// Whether the vault that opens for `targetPath` is the course.
    static func vaultIsTheCourse(targetPath: String, coursePath: String, registryData: Data?) -> Bool {
        guard let vault = ObsidianFigureAddOnsOffer.vaultThatOpens(targetPath: targetPath, registryData: registryData) else {
            return true
        }
        return vault == coursePath
    }
}

/// The trail's words for #495 (`obsidianAddOnsForFigures.trail`): add-ons by
/// name and version, never a page's words.
nonisolated enum ObsidianFigureAddOnsTrail {

    // MARK: - Types

    /// How the offer was answered.
    enum Answered: String, CaseIterable, Sendable {
        case addThem
        case notNow
        case notNowDontAskAgain
    }

    /// What started a pass.
    enum Trigger: String, CaseIterable, Sendable {
        case openInObsidian
        case afterAPreview
        case afterReopening
    }

    // MARK: - Functions

    static func offered(course: String, answered: Answered) -> String {
        let answer: String
        switch answered {
        case .addThem:
            answer = ObsidianFigureAddOnsWording.offerAdd
        case .notNow:
            answer = ObsidianFigureAddOnsWording.offerNotNow
        case .notNowDontAskAgain:
            answer = ObsidianFigureAddOnsWording.offerNotNow + ", don't ask again"
        }
        return course + " · asked to add Obsidian's add-ons for diagrams and graphs — " + answer
    }

    static func notTheVault(course: String) -> String {
        return course + " · did not offer Obsidian's add-ons for diagrams and graphs: Obsidian opens this course as part of a larger vault, which never reads the course's own settings"
    }

    static func reopened(course: String) -> String {
        return course + " · reopened Obsidian to show the add-ons for diagrams and graphs"
    }

    static func reopenDeclined(course: String) -> String {
        return course + " · chose Later: Obsidian was not reopened and its add-ons for diagrams and graphs were not added"
    }

    static func didNotClose(course: String) -> String {
        return course + " · Obsidian did not close, so its add-ons for diagrams and graphs were not added"
    }

    static func settingChanged(on: Bool) -> String {
        return "Settings ▸ Obsidian — add-ons for diagrams and graphs " + (on ? "on" : "off")
    }

    static func triggerWords(_ trigger: Trigger) -> String {
        switch trigger {
        case .openInObsidian:
            return "at Open in Obsidian"
        case .afterAPreview:
            return "after a preview"
        case .afterReopening:
            return "after reopening Obsidian"
        }
    }

    /// The line for a pass, or nil when there is nothing worth a line: no
    /// results, or every add-on simply already there.
    static func pass(course: String, trigger: Trigger, results: [ObsidianFigureAddOns.Result]) -> String? {
        if results.isEmpty {
            return nil
        }
        var everyOneAlreadyThere: Bool = true
        for result in results where result.outcome != .alreadyThere {
            everyOneAlreadyThere = false
        }
        if everyOneAlreadyThere {
            return nil
        }
        let start: String = course + " · Obsidian add-ons for diagrams and graphs (" + ObsidianFigureAddOnsTrail.triggerWords(trigger) + "): "
        if let first = results.first, first.outcome.isARefusal {
            return start + ObsidianFigureAddOnsTrail.refusalWords(first.outcome)
        }
        var parts: [String] = []
        for result in results {
            parts.append(ObsidianFigureAddOnsTrail.words(for: result))
        }
        return start + parts.joined(separator: "; ")
    }

    /// One add-on's part of the line.
    static func words(for result: ObsidianFigureAddOns.Result) -> String {
        let named: String = result.addOn.name
        let pinned: String = result.addOn.version
        switch result.outcome {
        case .added:
            return named + " " + pinned + " added"
        case .alreadyThere:
            return named + " " + pinned + " already there"
        case .alreadyThereSwitchedOff:
            return named + " " + pinned + " already there and switched off in Obsidian, so left off"
        case .leftAloneTheirs(let version):
            return named + " left alone (the teacher's own copy, " + version + ")"
        case .leftAloneOtherVersion(let version):
            return named + " left alone (" + version + ", not the " + pinned + " Plantoir added)"
        case .leftAloneUnreadable:
            return named + " left alone (what is there could not be read)"
        case .couldNotWrite(let reason):
            return named + " could not be added: " + reason
        default:
            return named + " — " + ObsidianFigureAddOnsTrail.refusalWords(result.outcome)
        }
    }

    /// The words for a pass refused before any add-on was looked at.
    static func refusalWords(_ outcome: ObsidianFigureAddOns.Outcome) -> String {
        switch outcome {
        case .refusedListUnreadable:
            return "nothing added: Obsidian's list of add-ons could not be read"
        case .refusedLink:
            return "nothing added: Obsidian's settings folder or its add-ons folder is a link"
        case .refusedCarriedCopy:
            return "nothing added: this copy of Plantoir's add-ons is missing or does not match"
        case .refusedSettingsNotSeeded:
            return "nothing added: Obsidian's settings for the course could not be set up first"
        default:
            return "nothing added"
        }
    }
}

/// What #495 remembers for this run of Plantoir only: Not Now, Later, the
/// lines already written, and the courses being opened right now.
@MainActor
enum ObsidianFigureAddOnsThisRun {

    // MARK: - Stored properties

    /// Not Now was chosen: no question again until Plantoir next starts.
    static var suppressed: Bool = false

    /// Courses (by folder path) whose reopen question was answered Later.
    static var reopenDeclined: Set<String> = []

    /// Trail lines written already, so a refusal, a left-alone or a failed
    /// write is said once per course per run rather than at every preview
    /// (plan review N4).
    static var linesWritten: Set<String> = []

    /// Courses (by folder path) Open in Obsidian is working on — a second
    /// click while the first is scanning does nothing (plan review N7).
    static var beingOpened: Set<String> = []

    // MARK: - Functions

    /// Forgets everything — for a test.
    static func forget() {
        suppressed = false
        reopenDeclined = []
        linesWritten = []
        beingOpened = []
    }

    /// Writes a pass's line if it is worth one: always when something was
    /// added, otherwise once per run.
    static func notePass(course: String, trigger: ObsidianFigureAddOnsTrail.Trigger, results: [ObsidianFigureAddOns.Result]) {
        guard let line = ObsidianFigureAddOnsTrail.pass(course: course, trigger: trigger, results: results) else {
            return
        }
        var addedSomething: Bool = false
        for result in results where result.outcome == .added {
            addedSomething = true
        }
        if !addedSomething {
            let remembered: String = ObsidianFigureAddOnsTrail.pass(course: course, trigger: .openInObsidian, results: results) ?? line
            if linesWritten.contains(remembered) {
                return
            }
            linesWritten.insert(remembered)
        }
        ActivityTrail.note(.obsidianAddOnsAdded, line)
    }
}
