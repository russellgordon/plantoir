import Foundation

/// What may sit on the reference shelf, and under what name.
///
/// Two rules live here, and they are different questions:
///
/// 1. **A folder name is unique in `courses/`**, which `CourseCodeRule`
///    already decides for every course — a reference course is a folder like
///    any other, so it borrows that rule rather than inventing a second one.
/// 2. **Within one group, no two reference courses share a course code** —
///    a school-year group, the no-year group, or a group the teacher made
///    (#572, third piece). That is this file's own rule, and it is the one that makes the
///    shelf readable: three rows all saying "ICS3U" under one year is a
///    teacher's mistake made permanent, while the same three under 2024–25,
///    2025–26 and "Other" is exactly what they meant.
///
/// The LIVE course a teacher is teaching sits in no group at all, so this
/// year's ICS3U never collides with a reference ICS3U. That is the ordinary
/// case, not an exception.
nonisolated enum ReferenceCourseRule {

    // MARK: - Types

    /// One course already on the shelf, as the rule needs to see it.
    struct Shelved: Equatable {
        /// The code a teacher reads — `ICS3U`, not the folder name.
        let displayCode: String

        /// The school year it is filed under, or nil for "Other".
        let schoolYear: Int?

        /// The folder it lives in, which is what identifies it. A course
        /// being re-filed must not be found clashing with itself.
        let folderName: String

        /// The made group the shelf's arrangement puts it in (#572, third
        /// piece), or nil when it sits in its school year or the no-year
        /// group. A course in a made group is in NO year group, so it never
        /// blocks a course of its code from its year.
        let madeGroupID: String?

        // MARK: - Computed properties

        /// The group it sits in.
        var place: ReferenceShelf.Place {
            if let madeGroupID {
                return .made(madeGroupID)
            }
            return ReferenceShelf.Place.forYear(schoolYear)
        }

        // MARK: - Initializer

        init(displayCode: String, schoolYear: Int?, folderName: String, madeGroupID: String? = nil) {
            self.displayCode = displayCode
            self.schoolYear = schoolYear
            self.folderName = folderName
            self.madeGroupID = madeGroupID
        }
    }

    /// Why a course cannot be put on the shelf under that code and year.
    enum Trouble: Equatable {
        case codeAlreadyInThatYear(code: String, schoolYear: Int?)

        /// The group is one the teacher made (#572, third piece), named as
        /// the shelf shows it.
        case codeAlreadyInThatGroup(code: String, group: String)

        // MARK: - Computed properties

        /// The sentence a teacher reads. Says which shelf is full and what
        /// they can do about it — never why the app cannot.
        var sentence: String {
            switch self {
            case .codeAlreadyInThatGroup(let code, let group):
                return "You already have a \(code) kept for reference in \(group). "
                     + "Choose a different group."
            case .codeAlreadyInThatYear(let code, let schoolYear):
                guard let schoolYear else {
                    return "You already have a \(code) kept for reference with no school year. "
                         + "Choose a school year for this one."
                }
                return "You already have a \(code) kept for reference from "
                     + "\(SchoolYear.label(forStartingYear: schoolYear)). "
                     + "Choose a different school year."
            }
        }
    }

    // MARK: - Functions

    /// Why `code` cannot join the shelf under `schoolYear`, or nil when it
    /// can.
    ///
    /// `ignoring` is the folder of the course being re-filed, when there is
    /// one: changing a course's year must not find the course itself sitting
    /// where it is about to move from.
    ///
    /// The year group means the group the year puts a course in: a course
    /// the teacher has put in a group of their own is not in it (#572, third
    /// piece), so every door that lands a course by its year asks this.
    static func trouble(
        placing code: String,
        inYear schoolYear: Int?,
        among shelved: [Shelved],
        ignoring folderName: String? = nil
    ) -> Trouble? {
        return ReferenceCourseRule.trouble(
            placing: code, in: ReferenceShelf.Place.forYear(schoolYear), named: nil,
            among: shelved, ignoring: folderName
        )
    }

    /// Why `code` cannot join the shelf in `place`, or nil when it can — the
    /// rule for every kind of group (`codeUniqueWithinAGroup`). `groupName`
    /// is what a MADE group is called, for its sentence; a year group and
    /// the no-year group keep the sentences they have always had.
    static func trouble(
        placing code: String,
        in place: ReferenceShelf.Place,
        named groupName: String?,
        among shelved: [Shelved],
        ignoring folderName: String? = nil
    ) -> Trouble? {
        guard let existing = ReferenceCourseRule.courseInTheWay(
            placing: code, in: place, among: shelved, ignoring: folderName
        ) else {
            return nil
        }
        let wanted: String = CourseCodeRule.normalized(existing.displayCode)
        switch place {
        case .year(let year):
            return .codeAlreadyInThatYear(code: wanted, schoolYear: year)
        case .noYear:
            return .codeAlreadyInThatYear(code: wanted, schoolYear: nil)
        case .made:
            return .codeAlreadyInThatGroup(code: wanted, group: groupName ?? "")
        }
    }

    /// The course on the shelf that `trouble` would refuse `code` because
    /// of, or nil when there is none: the one a Replace It… beside the
    /// refusal would replace (#572). The same walk as `trouble`, so the two
    /// can never name different courses.
    static func courseInTheWay(
        placing code: String,
        inYear schoolYear: Int?,
        among shelved: [Shelved]
    ) -> Shelved? {
        return ReferenceCourseRule.courseInTheWay(
            placing: code, in: ReferenceShelf.Place.forYear(schoolYear), among: shelved
        )
    }

    /// The same, for any kind of group.
    static func courseInTheWay(
        placing code: String,
        in place: ReferenceShelf.Place,
        among shelved: [Shelved],
        ignoring folderName: String? = nil
    ) -> Shelved? {
        let wanted: String = CourseCodeRule.normalized(code)
        if wanted.isEmpty {
            return nil
        }
        for existing in shelved {
            if let folderName, existing.folderName == folderName {
                continue
            }
            if existing.place != place {
                continue
            }
            if CourseCodeRule.normalized(existing.displayCode) == wanted {
                return existing
            }
        }
        return nil
    }

    /// A folder name to offer for a new reference course: `ICS3U-2025`, or
    /// `ICS3U-REF` for one with no school year.
    ///
    /// **All upper case, and that is not a style choice.** `preview.sh` and
    /// `deploy.sh` both put their course argument through
    /// `tr '[:lower:]' '[:upper:]'` before building `courses/<CODE>`, so a
    /// folder named `ICS3U-examples` would be looked for as `ICS3U-EXAMPLES`
    /// and simply not found. `CourseCodeRule.normalized` is what guarantees
    /// it, and a test pins that the proposal survives being normalised again.
    ///
    /// The result fits `CourseCodeRule.mostCharacters`, shortening the CODE
    /// rather than the year when it has to: the year is what tells two rows
    /// apart, and the teacher can edit the whole thing anyway.
    static func proposedFolderName(
        forCode code: String,
        schoolYear: Int?,
        existingFolderNames: [String]
    ) -> String {
        let base: String = CourseCodeRule.normalized(code)
        var suffixes: [String] = []
        if let schoolYear {
            suffixes.append("-\(schoolYear)")
            for attempt in 2...9 {
                suffixes.append("-\(schoolYear)-\(attempt)")
            }
        } else {
            suffixes.append("-REF")
            for attempt in 2...9 {
                suffixes.append("-REF\(attempt)")
            }
        }

        for suffix in suffixes {
            let candidate: String = ReferenceCourseRule.fitting(base: base, suffix: suffix)
            if CourseCodeRule.trouble(candidate, existingCodes: existingFolderNames) == nil {
                return candidate
            }
        }
        // Nine tries all taken is not a state a teacher can reach by
        // accident. Hand back the first proposal anyway rather than an empty
        // field: the sheet validates what is in it and says what is wrong.
        return ReferenceCourseRule.fitting(base: base, suffix: suffixes[0])
    }

    /// `base` + `suffix`, shortened to fit a course code and normalised.
    private static func fitting(base: String, suffix: String) -> String {
        let room: Int = CourseCodeRule.mostCharacters - suffix.count
        if room < 1 {
            return CourseCodeRule.normalized(String(suffix.dropFirst()))
        }
        var shortened: String = base
        if shortened.count > room {
            shortened = String(shortened.prefix(room))
        }
        return CourseCodeRule.normalized(shortened + suffix)
    }
}
