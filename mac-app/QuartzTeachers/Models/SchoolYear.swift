import Foundation

/// A school year — "2025–26" — stored as the calendar year it STARTS in.
///
/// A teacher who keeps three years of ICS3U on the shelf needs the rows told
/// apart, and the thing that tells them apart is the year each was taught. One
/// integer is the whole fact: `2025` means the year that began in September
/// 2025 and ended in June 2026. The label is DERIVED from it, here, so the en
/// dash in "2025–26" never reaches `course_config.json` and the two apps
/// cannot render the same year two ways.
///
/// **The rollover is 1 August, and it is inherited rather than invented.**
/// Windows already ships the rule — `Timetable.AcademicYearStarting(today) =>
/// today.Month >= 8 ? today.Year : today.Year - 1` — documented there as "a
/// school year is named for the calendar year it starts in, and starts in the
/// late summer". Ontario and BC both start in September, so 1 August leaves a
/// month of headroom for a teacher setting up over the summer. A second rule
/// on this side would be two answers to one question.
///
/// **Every function takes the day rather than reading the clock.** A list that
/// grows by itself as time passes cannot be pinned by a test that has no way
/// to move the day, and a rule nobody can pin is one that gets "simplified"
/// away. The callers pass `CalendarDay.today()`; the contract cases pass four
/// fixed days.
nonisolated enum SchoolYear {

    // MARK: - Stored properties

    /// The earliest year offered: 2022–23.
    ///
    /// A floor rather than a computed window, because the list is a shelf a
    /// teacher fills rather than a range with a meaning — and Russell set it
    /// at 2022–23. It never moves up: a course filed under 2022–23 stays in
    /// its own group for as long as the folder exists.
    static let earliestStartingYear: Int = 2022

    /// The month a new school year joins the list — August, so a teacher
    /// setting up in the summer files the year they are about to teach.
    static let rolloverMonth: Int = 8

    /// What a course with no school year is filed under. Not a year, and
    /// deliberately last in every list.
    static let otherGroupName: String = "Other"

    // MARK: - Functions

    /// The school year `day` falls in, as its starting calendar year.
    static func startingYear(on day: CalendarDay) -> Int {
        if day.month >= SchoolYear.rolloverMonth {
            return day.year
        }
        return day.year - 1
    }

    /// The years offered on `day`, NEWEST FIRST — the current school year down
    /// to `earliestStartingYear`.
    ///
    /// The top end is derived from the day and never written down, so the list
    /// grows by itself; the bottom end is the floor above. "No year" is not in
    /// here: it is an absence rather than a year, and the sheets that offer it
    /// draw it themselves as the last choice.
    static func offeredStartingYears(on day: CalendarDay) -> [Int] {
        let newest: Int = startingYear(on: day)
        if newest < SchoolYear.earliestStartingYear {
            return []
        }
        var years: [Int] = []
        var year: Int = newest
        while year >= SchoolYear.earliestStartingYear {
            years.append(year)
            year -= 1
        }
        return years
    }

    /// "2025–26", with an EN DASH (U+2013) — the one place the label is
    /// spelled, so the sidebar, the sheets and the MCP listing cannot disagree.
    static func label(forStartingYear startingYear: Int) -> String {
        let endsIn: Int = startingYear + 1
        let lastTwo: String = String(format: "%02d", ((endsIn % 100) + 100) % 100)
        return "\(startingYear)–\(lastTwo)"
    }

    /// How a stored `reference_school_year` READS: the year, or nil for
    /// "Other".
    ///
    /// Anything that is not a whole number within the offered range reads as
    /// "Other" — a missing key, a hand-edited `2019`, a `"last year"`, a
    /// `true`, or a `2031` written on a Mac whose clock was wrong. The
    /// direction this errs in is the safe one: a course lands in a group a
    /// teacher can see and can change, rather than inventing a group labelled
    /// "0000–01" out of a value that coerced to zero.
    ///
    /// A `true` needs no case of its own, and that is measured rather than
    /// assumed: JSON's `true` and JSON's `1` BOTH satisfy `is Bool` in Swift,
    /// so telling them apart takes `CFGetTypeID` — and it buys nothing here,
    /// because both read as the year 1, which is outside the range and lands
    /// in "Other" either way.
    ///
    /// A value ABOVE the range today joins its own group on the day that year
    /// arrives, because the range only ever grows at the top.
    static func offeredYear(storedYear: Int?, on day: CalendarDay) -> Int? {
        guard let storedYear else {
            return nil
        }
        for offered in offeredStartingYears(on: day) where offered == storedYear {
            return storedYear
        }
        return nil
    }
}
