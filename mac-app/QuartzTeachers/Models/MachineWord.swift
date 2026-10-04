import Foundation

/// The word for the teacher's computer, in the sentences that name it (#418, #410).
///
/// A handful of sentences both apps say name the machine — "somewhere else on
/// this Mac", "restart this Mac", "restarting your Mac". Windows says the same
/// sentences with "PC". Rather than each such sentence carrying a second,
/// Windows-only copy in the contract (which is what Windows had to do as a
/// stop-gap: `elsewhereWorkOnWindows`, `sentenceOnWindows`), the contract
/// writes the sentence ONCE with a `{machine}` placeholder, and each app fills
/// it with its own word from `contracts/shared-rules.json` →
/// `specialNames.platformWording.machine`.
///
/// The placeholder holds the bare NOUN, not "this Mac" or "your Mac", on
/// purpose: the sentences that name the machine use both determiners, and
/// Windows' own wording of every one of them kept the determiner and swapped
/// only the noun. A noun placeholder changes no sentence on either side.
///
/// `SharedRulesContractTests.testTheMachineWordIsTheContracts` pins the word
/// against the contract, and `testEveryMachinePlaceholderIsRecorded` holds the
/// record's `usedIn` list to the sentences that really carry it.
nonisolated enum MachineWord {

    // MARK: - Stored properties

    /// What the contract writes where the machine's name goes.
    static let placeholder: String = "{machine}"

    /// This platform's word for the teacher's computer.
    static let onThisPlatform: String = "Mac"

    // MARK: - Functions

    /// A contract sentence with this platform's word put in.
    static func filling(_ template: String) -> String {
        return template.replacingOccurrences(of: placeholder, with: onThisPlatform)
    }
}
