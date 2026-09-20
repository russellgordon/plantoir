import Foundation

/// What a course code may be — asked by the New Course wizard and by
/// renaming, so a code one accepts is a code the other accepts.
///
/// This lives in one place because it used to live in two. The wizard had
/// the rule as a private idea of its own, which meant a code the wizard let
/// a teacher create could not necessarily be typed again anywhere else. A
/// second copy of a rule is a rule that will disagree with itself.
///
/// The rule is narrow on purpose — a single interior space and a dash are
/// the only concessions. A course code is not a label the app keeps
/// to itself: it **is** the folder name under `courses/`, it is written into
/// `course_config.json` for the shared Python to read, it rides in the name
/// of every backup and archive zip, and it becomes part of a launchd label
/// when a section is set to publish on its own. Each of those has its own
/// opinion about what characters it will carry. One narrow rule everywhere
/// beats four that disagree at the edges.
enum CourseCodeRule {

    // MARK: - Stored properties

    /// The most characters a course code may carry.
    ///
    /// Ontario codes are six (ICS3U). Clubs and locally-named courses are
    /// named by the teacher, and twelve leaves room for the ones that carry
    /// a word — "AP CALC", "ROBOTICS" — without letting a code grow into a
    /// sentence. The code has to stay readable as a sidebar row, a folder
    /// name and a zip's prefix all at once.
    static let mostCharacters: Int = 12

    // MARK: - Functions

    /// A code as it will be STORED: trimmed of surrounding whitespace and
    /// upper-cased.
    ///
    /// Settling the case here is what stops `ICS3U` and `ics3u` reading as
    /// two different courses. A Mac's disk is case-insensitive but
    /// case-preserving, so two folders differing only in case cannot both
    /// exist — and a clash check that missed it would offer the teacher a
    /// rename that then failed on the file system with a puzzling error.
    static func normalized(_ raw: String) -> String {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// What is wrong with a code, as a value rather than a sentence.
    ///
    /// The sentence comes off this in two lengths — see `sentence` and
    /// `short` — because the two places that ask have very different room.
    /// One enum keeps them from drifting into two rules.
    enum Trouble: Equatable {
        case twoSpacesInARow
        case charactersThatAreNotAllowed
        case tooLong
        case alreadyTaken(String)

        // MARK: - Computed properties

        /// The full sentence, for the New Course wizard, where the message
        /// sits under a wide field and can afford to explain itself.
        var sentence: String {
            switch self {
            case .twoSpacesInARow:
                return "A course code can’t have two spaces in a row."
            case .charactersThatAreNotAllowed:
                return "A course code can only use letters, numbers, spaces and dashes."
            case .tooLong:
                return "A course code can be at most \(CourseCodeRule.mostCharacters) characters."
            case .alreadyTaken(let code):
                return "A course named \(code) already exists — choose a different code."
            }
        }

        /// The short form, for the sidebar row, where the whole message has
        /// perhaps twenty-five characters before it is cut off mid-word — and
        /// a truncated explanation explains nothing.
        var short: String {
            switch self {
            case .twoSpacesInARow:
                return "No double spaces"
            case .charactersThatAreNotAllowed:
                // Says less than the full sentence does — spaces are
                // allowed too — because the sidebar cuts this off around
                // twenty-five characters and "Letters, numbers, spaces,
                // dashes" does not survive the trim. A teacher only ever
                // sees this after typing something that is NOT one of
                // these, so the shorter list still points the right way,
                // and the wizard's wide field carries the complete
                // sentence.
                return "Letters, numbers, dashes"
            case .tooLong:
                return "\(CourseCodeRule.mostCharacters) characters at most"
            case .alreadyTaken(let code):
                return "\(code) already exists"
            }
        }
    }

    /// What is wrong with a code as typed, or nil when it is fine.
    ///
    /// An EMPTY code is nil rather than a complaint: nothing has been said
    /// yet, so there is nothing to warn about, and a warning that appears
    /// before the teacher has typed anything is noise.
    ///
    /// `currentCode` is the code of the course being renamed, when there is
    /// one. A course does not clash with itself, so re-typing a course's own
    /// code — or only its capitalisation — is not an error.
    static func trouble(
        _ text: String,
        existingCodes: [String],
        currentCode: String? = nil
    ) -> Trouble? {
        let code: String = normalized(text)
        if code.isEmpty {
            return nil
        }

        // Spaces are allowed BETWEEN letters and numbers and nowhere else.
        // Leading and trailing ones never reach here — `normalized` trims
        // them, so a code typed with one simply has it dropped rather than
        // being refused for a mistake nobody meant to make. What is left to
        // catch is a run of them in the middle, which is a typo every time.
        if code.contains("  ") {
            return .twoSpacesInARow
        }
        for character in code {
            if !characterIsAllowed(character) {
                return .charactersThatAreNotAllowed
            }
        }
        if code.count > mostCharacters {
            return .tooLong
        }

        if let currentCode {
            if normalized(currentCode) == code {
                return nil
            }
        }
        for existingCode in existingCodes {
            if normalized(existingCode) == code {
                return .alreadyTaken(code)
            }
        }
        return nil
    }

    /// Why a code can't be used, said in full — the wizard's version.
    static func problem(
        _ text: String,
        existingCodes: [String],
        currentCode: String? = nil
    ) -> String? {
        return trouble(text, existingCodes: existingCodes, currentCode: currentCode)?.sentence
    }

    /// The same answer in the words a sidebar row has room for.
    static func shortProblem(
        _ text: String,
        existingCodes: [String],
        currentCode: String? = nil
    ) -> String? {
        return trouble(text, existingCodes: existingCodes, currentCode: currentCode)?.short
    }

    /// True when this character may appear in a course code: an ASCII letter
    /// or digit, a space, or a dash.
    ///
    /// Emoji fail here, and so does an accented letter and every piece of
    /// punctuation. They are refused for the same reason as anything else
    /// awkward: the code is a folder name, a file name and part of a
    /// scheduled publish's identifier, and each of those has its own opinion
    /// about what it will carry.
    ///
    /// Two exceptions. A SPACE, because teachers really do name a course
    /// "AP CALC" — and everything downstream already copes with one
    /// (`ScheduledDeploy.sanitizedCode` exists precisely so a club named
    /// with a space cannot produce a bad identifier).
    ///
    /// And a DASH, since 2026-08-23, because British Columbia's course
    /// codes contain them: 55 of the 117 codes in
    /// `support/british_columbia_secondary_courses.json` — MTEL-12,
    /// MFMP-10, MMA--09 — so the rule was refusing more than half of one
    /// province's real courses. Russell found it by trying to create one.
    /// A dash is safe everywhere a code travels: it is legal in a folder
    /// name, in a zip's name, and in a launchd label. This reverses the
    /// contract's old `CS-CLUB` case, which refused a hyphen "like any
    /// other punctuation" — written before BC codes existed here.
    private static func characterIsAllowed(_ character: Character) -> Bool {
        if character == " " || character == "-" {
            return true
        }
        if !character.isASCII {
            return false
        }
        return character.isLetter || character.isNumber
    }
}
