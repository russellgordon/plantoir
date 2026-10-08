import Foundation

/// What settler S3 reads about a course before it judges a model's
/// add_next_class (#440). Built by `AssistToolRunner.nextClassReading`.
nonisolated struct AssistNextClassReading: Equatable, Sendable {

    // MARK: - Stored properties

    /// The course's word for a unit ("Unit", "Module") — or, in a numbered
    /// course, its page word ("Week").
    let unitWord: String

    /// True when the course names its pages with one number and has no units.
    let isNumbered: Bool

    /// What the course calls one of its pages: class or meeting.
    let noun: ClassNoun

    /// The unit a plain "add the next class" would land in.
    let plainNextUnit: Int

    /// The day it would carry.
    let plainNextDay: Int
}

/// Settler S3 (#440): a teacher's sentence that the MODEL answered with a
/// plain add_next_class, read in code for the three things that tool cannot
/// carry on the local surface — a new unit, a unit or day other than the
/// next one, and more than one page.
///
/// **Why it exists.** Measured 2026-10-07 on the smaller assistant (Mac16,8
/// M4 Pro, llama.cpp b10435, Metal, the app's own flags): ten sentences
/// about units and counts — "The next class begins Unit 3", "Make the next
/// class the first day of a new unit", "Add the next two classes", and seven
/// more — reached add_next_class 50 times in 50 with only a course and a
/// section. Each added ONE page in the CURRENT unit and reported success. The
/// tool cannot be given `unit` and `days` on the local surface: #411
/// measured exactly that, and both models then read the NEXT in "add the next
/// class" as 'start a new unit' (6 of 6 and 5 of 6 phrasings). So the model
/// keeps its two arguments, the phrasings that do these things are answered
/// in code (`AssistCardCommand`), and a sentence that reaches the model
/// anyway is stopped here and pointed at them.
///
/// **It points; it never converts.** Turning "don't start a new unit yet"
/// into a new-unit call would be reading meaning out of words, which is what
/// the frames exist to avoid. Stopping costs a teacher one more sentence;
/// guessing wrong costs a page in the wrong unit, reported as done.
///
/// A pure function of the sentence and `AssistNextClassReading`, so the
/// contract's rows (assist-cases.json → nextClassUnits) pin it exactly.
nonisolated enum AssistNextClassUnits {

    // MARK: - Types

    /// Which of the three things the sentence asked for.
    enum Kind: String, Sendable {
        /// "new unit", "next unit", "another unit" — or the course's own word.
        case newUnit = "a"
        /// "Unit 3", or "Unit 3, Day 7", that is not where the next page goes.
        case anotherUnitOrDay = "b"
        /// A count above one right before the noun: "the next two classes".
        case several = "c"
    }

    // MARK: - Stored properties

    /// The nouns a count may stand right before.
    static let pageNouns: Set<String> = ["classes", "days", "lessons", "meetings", "pages", "periods"]

    /// The words that may stand between a count and the noun.
    static let beforeTheNoun: Set<String> = ["more", "extra", "new"]

    /// The verbs a count may follow (with "the", "next" or "another" between).
    static let addingVerbs: Set<String> = ["add", "create", "make", "plan"]

    /// The words that make the next word a NEW unit.
    static let newUnitWords: Set<String> = ["new", "next", "another", "fresh", "different"]

    /// Counts written as words. One is not here: one page is what the tool does.
    static let spelledCounts: [String: Int] = [
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "several": 2,
    ]

    /// Unit numbers written as words.
    static let spelledNumbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]

    // MARK: - Functions

    /// What the sentence asked for that a plain add_next_class would not do,
    /// or nil when the plain call is the request.
    ///
    /// nil, too, when there is no reading — no remembered dates, or the
    /// course gone — so the call runs and the runner asks for the dates.
    static func kind(of typed: String, reading: AssistNextClassReading?) -> Kind? {
        guard let reading else {
            return nil
        }
        let words: [String] = AssistNextClassUnits.words(of: typed)
        // In a numbered course the page word is not a unit ("Week 9" is a
        // page), so only the literal word "unit" is read there.
        var unitWords: Set<String> = ["unit", "units"]
        if !reading.isNumbered {
            let own: String = reading.unitWord.lowercased()
            unitWords.insert(own)
            unitWords.insert(own + "s")
        }

        if AssistNextClassUnits.asksForANewUnit(words, unitWords: unitWords) {
            return .newUnit
        }
        if AssistNextClassUnits.asksForSeveral(words) {
            return .several
        }
        guard let named = AssistNextClassUnits.unitNamed(in: words, unitWords: unitWords) else {
            return nil
        }
        // A numbered course has no units, so any unit named is not this one.
        if reading.isNumbered {
            return .anotherUnitOrDay
        }
        if named != reading.plainNextUnit {
            return .anotherUnitOrDay
        }
        // The DAY, too (ruling 4): "Unit 3, Day 7" when the next page is
        // Unit 3, Day 5 would otherwise make Day 5 and report success.
        if let day = AssistNextClassUnits.dayNamed(in: words), day != reading.plainNextDay {
            return .anotherUnitOrDay
        }
        return nil
    }

    /// The sentence as lower-case words: runs of letters, digits and
    /// apostrophes, so "Unit 3," is "unit", "3" and "tomorrow's" stays whole.
    static func words(of typed: String) -> [String] {
        let folded: String = typed.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        var words: [String] = []
        var word: String = ""
        for character in folded {
            let isLetter: Bool = character >= "a" && character <= "z"
            let isDigit: Bool = character >= "0" && character <= "9"
            if isLetter || isDigit || character == "'" {
                word.append(character)
                continue
            }
            if !word.isEmpty {
                words.append(word)
            }
            word = ""
        }
        if !word.isEmpty {
            words.append(word)
        }
        return words
    }

    /// "new unit", "next unit", "another module" — two words side by side.
    static func asksForANewUnit(_ words: [String], unitWords: Set<String>) -> Bool {
        var index: Int = 0
        while index + 1 < words.count {
            if newUnitWords.contains(words[index]) && unitWords.contains(words[index + 1]) {
                return true
            }
            index += 1
        }
        return false
    }

    /// A count above one IMMEDIATELY before a page noun (an optional "more",
    /// "extra" or "new" between them), where the count follows either an
    /// adding verb — "add", "create", "make", "plan", "set up", with "the",
    /// "next" or "another" allowed between — or the word "next".
    ///
    /// **Where the number may sit, and why it is that strict** (ruling 5):
    /// "Add tomorrow's class page, I teach two classes tomorrow" has "two
    /// classes" in it and asks for ONE page; "Add the next class for period
    /// 2" has a number and asks for one too. Requiring the count to belong to
    /// the request — right after the verb or after "next" — keeps both
    /// running, and both are `runs` rows.
    static func asksForSeveral(_ words: [String]) -> Bool {
        var index: Int = 0
        while index < words.count {
            var after: Int? = nil
            if addingVerbs.contains(words[index]) {
                after = index + 1
            } else if words[index] == "set", index + 1 < words.count, words[index + 1] == "up" {
                after = index + 2
            }
            if var position = after {
                for optional in ["the", "next", "another"]
                where position < words.count && words[position] == optional {
                    position += 1
                }
                if AssistNextClassUnits.countThenNoun(words, from: position) {
                    return true
                }
            }
            if words[index] == "next", AssistNextClassUnits.countThenNoun(words, from: index + 1) {
                return true
            }
            index += 1
        }
        return false
    }

    /// A count above one at `start`, then the noun.
    static func countThenNoun(_ words: [String], from start: Int) -> Bool {
        guard start < words.count else {
            return false
        }
        var position: Int = start
        var counted: Bool = false
        if let number = Int(words[position]), number >= 2 {
            counted = true
            position += 1
        } else if spelledCounts[words[position]] != nil {
            counted = true
            position += 1
        } else if words[position] == "a", position + 1 < words.count {
            // "a few", "a couple of".
            if words[position + 1] == "few" {
                counted = true
                position += 2
            } else if words[position + 1] == "couple" {
                counted = true
                position += 2
                if position < words.count && words[position] == "of" {
                    position += 1
                }
            }
        }
        guard counted, position < words.count else {
            return false
        }
        if beforeTheNoun.contains(words[position]) {
            position += 1
        }
        guard position < words.count else {
            return false
        }
        if pageNouns.contains(words[position]) {
            return true
        }
        // "two class pages", "three meeting pages".
        let pageKinds: Set<String> = ["class", "meeting", "lesson"]
        return pageKinds.contains(words[position])
            && position + 1 < words.count && words[position + 1] == "pages"
    }

    /// The number after the first unit word that has one: "Unit 3", "unit
    /// three", "Module 4".
    static func unitNamed(in words: [String], unitWords: Set<String>) -> Int? {
        var index: Int = 0
        while index + 1 < words.count {
            if unitWords.contains(words[index]) {
                if let number = Int(words[index + 1]) {
                    return number
                }
                if let number = spelledNumbers[words[index + 1]] {
                    return number
                }
            }
            index += 1
        }
        return nil
    }

    /// The number after the first "day" that has one — read only beside a
    /// unit, so a rotation's "it's a Day 2 tomorrow" alone never stops a call.
    static func dayNamed(in words: [String]) -> Int? {
        var index: Int = 0
        while index + 1 < words.count {
            if words[index] == "day" {
                if let number = Int(words[index + 1]) {
                    return number
                }
                if let number = spelledNumbers[words[index + 1]] {
                    return number
                }
            }
            index += 1
        }
        return nil
    }
}
