import Foundation

/// The SHAPE a course's class-page names take (#267).
///
/// `unitDay` is "Unit 2, Day 3" — every course made before the scheme
/// existed. `numbered` is "Week 3": ONE number, counting meetings, which is
/// how a club names its pages. Stored as `class_page_scheme`; absent, empty
/// and unknown all read as `unitDay`, so a scheme a newer app wrote, opened
/// here, is today's shape rather than an error — see
/// `contracts/file-formats.json` → `class_page_scheme`.
nonisolated enum ClassPageScheme: String {
    case unitDay = "unit_day"
    case numbered = "numbered"

    // MARK: - Functions

    /// The scheme a stored value means.
    static func reading(_ raw: String?) -> ClassPageScheme {
        let trimmed: String = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == ClassPageScheme.numbered.rawValue {
            return .numbered
        }
        return .unitDay
    }
}

/// What the assistant calls one of a course's class pages when it talks to
/// the teacher (#267). A closed pair rather than free text because the
/// sentences carry articles and plurals. Stored as `class_noun`; absent and
/// unknown read as `.class`.
nonisolated enum ClassNoun: String {
    case `class` = "class"
    case meeting = "meeting"

    // MARK: - Computed properties

    /// "class" or "meeting" — one of them, in the middle of a sentence.
    var singular: String {
        return rawValue
    }

    /// "classes" or "meetings".
    var plural: String {
        switch self {
        case .class:
            return "classes"
        case .meeting:
            return "meetings"
        }
    }

    // MARK: - Functions

    /// The singular or the plural, whichever `count` needs.
    func counted(_ count: Int) -> String {
        return count == 1 ? singular : plural
    }

    /// The noun a stored value means.
    static func reading(_ raw: String?) -> ClassNoun {
        let trimmed: String = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == ClassNoun.meeting.rawValue {
            return .meeting
        }
        return .class
    }
}

/// How one course names its class pages: its word and its scheme, together.
///
/// One value rather than a word passed beside a scheme, and with NO default
/// on any path that writes a page: every place that builds a class-page title
/// has to say which course's naming it is using, so none of them can quietly
/// fall back to "Unit 1, Day 10" inside a course whose pages are "Week 10".
/// (Found by the #267 plan review: with a default, a missed site writes the
/// wrong file and every test stays green.)
nonisolated struct ClassPageNaming: Equatable, Hashable {

    // MARK: - Stored properties

    /// What the course calls a unit — or, under `numbered`, the whole word of
    /// the name: "Week" in "Week 3".
    let word: String

    let scheme: ClassPageScheme

    // MARK: - Computed properties

    /// What a course says when it has said nothing: "Unit 2, Day 3".
    static var standard: ClassPageNaming {
        return ClassPageNaming(word: ClassPageTerm.standard, scheme: .unitDay)
    }

    /// True when a page name carries one number and there are no units.
    var isNumbered: Bool {
        return scheme == .numbered
    }

    /// The pattern a class page's name must match, with the numbers captured.
    var pattern: String {
        let escapedWord: String = NSRegularExpression.escapedPattern(for: word)
        switch scheme {
        case .unitDay:
            return "^" + escapedWord + #"\s+(\d+),\s*Day\s+(\d+)$"#
        case .numbered:
            return "^" + escapedWord + #"\s+(\d+)$"#
        }
    }

    /// The shape a class page's name takes, as a teacher would write it
    /// down: "Unit N, Day N", or "Week N". For sentences that say which
    /// pages were passed over, so a Module course and a club each hear their
    /// own shape rather than "Unit N, Day N" (#267, #268).
    var shapeDescription: String {
        switch scheme {
        case .unitDay:
            return "\(word) N, Day N"
        case .numbered:
            return "\(word) N"
        }
    }

    // MARK: - Initializer

    init(word: String, scheme: ClassPageScheme) {
        self.word = ClassPageTerm.cleaned(word)
        self.scheme = scheme
    }

    // MARK: - Functions

    /// A unit, named — "Unit 4", "Module 4" — or nil in a numbered course,
    /// which has no units to name. A sentence that would say "in Unit 1"
    /// about a club says nothing about a unit instead.
    func unitName(_ unit: Int) -> String? {
        switch scheme {
        case .unitDay:
            return "\(word) \(unit)"
        case .numbered:
            return nil
        }
    }

    /// The name a position makes: "Unit 2, Day 3", or "Week 3".
    ///
    /// Every sentence that names a position goes through here rather than
    /// spelling "\(word) \(unit), Day \(day)" out by hand — which is how
    /// "Make room … at Unit 3, Day 4" reached a Module course, and how
    /// "Week 1, Day 5" would have reached a club.
    ///
    /// Under `numbered` a position is `unit` 1 and the day IS the number; a
    /// numbered course has no other unit, and every path that would start one
    /// refuses before it gets here.
    func title(unit: Int, day: Int) -> String {
        switch scheme {
        case .unitDay:
            return "\(word) \(unit), Day \(day)"
        case .numbered:
            return "\(word) \(day)"
        }
    }
}
