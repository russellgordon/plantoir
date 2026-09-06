import Foundation

/// What a course calls the first half of a class page's name.
///
/// Class pages are named "Unit 2, Day 3". Until 2026-09-01 that first word was
/// not a preference but a structural assumption, built into the regex that
/// decides whether a page is a class page, into the page the next-class button
/// writes, and into the curriculum map's idea of what a course TEACHES. Some
/// teachers organise by "Module" or "Thread"; renaming the pages in Obsidian
/// used to lose them every feature that recognises a class page — and the
/// coverage map does not fail when it finds none, it falls back to counting
/// every published page, which is a wrong map that reports success.
///
/// A course records its word in `course_config.json` as `unit_word`. **ABSENT
/// means "Unit"**, which is what every course made before this key existed
/// says. The Python half of the rule is `scripts/class_pages.py`, and
/// `contracts/class-planning.json` → `pageNaming` carries the cases both
/// suites run.
///
/// **"Day" is deliberately fixed.** A teacher who says "Thread" almost
/// certainly still says "Day 3", and a second configurable word would double
/// the migration for something nobody asked for.
///
/// **The choice is offered at course creation and nowhere else.** The
/// ready-made pages are poured in the teacher's word as the course is made;
/// renaming three thousand pages and their wikilinks in a course already in
/// use is a different and far more dangerous piece of work, and it is not on
/// offer.
enum ClassPageTerm {

    // MARK: - Stored properties

    /// What a course says when it has not said otherwise.
    static let standard: String = "Unit"

    // MARK: - Functions

    /// A usable word from whatever was typed or stored.
    ///
    /// Empty and absent both mean the standard word. They are NOT
    /// distinguished the way `graded_folders` distinguishes absent from empty:
    /// there is no sensible reading of "the teacher cleared the word", and a
    /// course whose class pages had no name at all could not be built.
    static func cleaned(_ raw: String?) -> String {
        let trimmed: String = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return standard
        }
        return trimmed
    }

    /// Why this word cannot be used, or nil when it can.
    ///
    /// A digit would make "Module2 1, Day 1" and a comma would make a name no
    /// rule can read back — in both cases the pages would be built and then
    /// recognised by nothing, which is the silent failure this whole feature
    /// exists to end.
    static func problem(with raw: String) -> String? {
        let trimmed: String = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return nil
        }
        for character in trimmed {
            if character.isNumber {
                return "A unit's name cannot contain a number — the number after it is the unit's own."
            }
        }
        if trimmed.contains(",") {
            return "A unit's name cannot contain a comma; the comma separates the unit from the day."
        }
        return nil
    }

    /// The word a course uses, read from its configuration values.
    static func term(inConfigurationValues values: [String: Any]) -> String {
        return cleaned(values["unit_word"] as? String)
    }
}
