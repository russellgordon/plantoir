import Foundation

/// The days one section of a course actually meets, written down once and
/// reused.
///
/// A teacher answers "when does this class meet?" by finding a spreadsheet,
/// working out which column is their block, and reading it out. That is a
/// genuinely annoying five minutes, and without this every conversation asked
/// for it again — a new session, or simply tomorrow, and the teacher was back
/// in the timetable file.
///
/// So the answer is kept. Everything that needs to know when classes fall —
/// laying down placeholder pages for a unit nobody has written yet, inserting a
/// class and pushing the rest along — reads it from here rather than asking
/// again.
///
/// It lives INSIDE the course folder, under `.internal/timetable/`, for one
/// practical reason: it then travels with the course through backup, archive
/// and restore, all of which carry that folder along with everything else. A
/// file kept beside the app would come adrift from the course the first time a
/// teacher moved their work to another machine, and would then be silently
/// WRONG rather than missing — the worse of the two failures.
///
/// The Windows app writes and reads the same file. The two share a FILE
/// FORMAT, not code:
///
/// ```json
/// { "section": 1,
///   "dates": ["2026-09-08", "2026-09-10"],
///   "source": "timetable.xlsx, block H",
///   "recorded": "2026-08-14" }
/// ```
struct SectionTimetable {

    // MARK: - Stored properties

    /// Which section these days belong to.
    let sectionNumber: Int

    /// Every day this section meets, earliest first, with no repeats.
    /// Never empty: a timetable with no days in it is not a timetable.
    let dates: [CalendarDay]

    /// Where these came from, in the teacher's own words — "timetable.xlsx,
    /// block H", "typed in by hand". Read back whenever the dates are about to
    /// be used, so a teacher can recognise a stale answer and say so.
    let source: String

    /// The day this was written down, or nil when the file did not say.
    let recorded: CalendarDay?

    // MARK: - Computed properties

    /// The days as the file writes them.
    var datesText: [String] {
        var result: [String] = []
        for date in dates {
            result.append(date.text)
        }
        return result
    }

    var firstDate: CalendarDay {
        return dates[0]
    }

    var lastDate: CalendarDay {
        return dates[dates.count - 1]
    }

    // MARK: - Initializer

    init(sectionNumber: Int, dates: [CalendarDay], source: String, recorded: CalendarDay?) {
        self.sectionNumber = sectionNumber
        self.dates = dates
        self.source = source
        self.recorded = recorded
    }

    // MARK: - Functions

    /// The meeting days from a given day onwards — the ones still to come.
    func dates(onOrAfter day: CalendarDay) -> [CalendarDay] {
        var result: [CalendarDay] = []
        for date in dates {
            if date >= day {
                result.append(date)
            }
        }
        return result
    }

    /// Meeting days left over once this many have been spoken for. The
    /// insert-and-shift operations ask this before they touch anything, so
    /// "does this even fit?" is answered in the plan rather than half way
    /// through the work.
    func spareDates(after taken: Int) -> Int {
        return max(0, dates.count - taken)
    }
}

/// Reading and writing a section's remembered timetable.
///
/// The one rule worth stating out loud: **a partial list is refused, not
/// half-stored.** A half-remembered timetable does not announce itself — it
/// gets trusted, and then dates the wrong classes, which is a worse failure
/// than having no timetable at all. So a list containing anything unreadable is
/// turned away whole, and a file on disk that cannot be read whole is treated
/// as a refusal rather than as the dates that happened to parse.
///
/// On Windows two things write this file: the `remember_timetable` operation,
/// and a re-date being applied — a re-date has just been handed the whole
/// year's dates, so it would be perverse to throw them away. Only the first of
/// those exists here yet. When re-dating is ported it should call
/// `applyRememberTimetable` on the dates it used, and go through
/// `planRememberTimetable` to get there so the partial-list refusal applies to
/// it too.
enum SectionTimetableStore {

    // MARK: - Types

    /// Why a timetable could not be remembered or trusted, in words a teacher
    /// can act on.
    enum Problem: LocalizedError {
        case noDatesGiven(String, Int)
        case unreadableDates(String, Int, [String])
        case halfRemembered(String, Int, [String])
        case cannotBeClassDates(String, Int, [String])
        case couldNotWrite(String, Int, String)

        var errorDescription: String? {
            switch self {
            case .noDatesGiven(let code, let number):
                return "No class dates were given for \(code) Section \(number), so there is nothing to remember."
            case .unreadableDates(let code, let number, let offenders):
                return "\(SectionTimetableStore.list(offenders)) \(offenders.count == 1 ? "isn’t a date" : "aren’t dates") written as 2026-09-08, so nothing was remembered for \(code) Section \(number). A half-remembered timetable would date the wrong classes, so the whole list is refused — send it again with those corrected."
            case .halfRemembered(let code, let number, let offenders):
                return "The remembered timetable for \(code) Section \(number) has \(offenders.count == 1 ? "an entry" : "entries") that cannot be read — \(SectionTimetableStore.list(offenders)). It is being ignored rather than half-trusted. Record the class dates again."
            case .cannotBeClassDates(let code, let number, let offenders):
                return "\(SectionTimetableStore.list(offenders)) \(offenders.count == 1 ? "is too far from today to be a class date" : "are too far from today to be class dates"), so nothing was remembered for \(code) Section \(number). A half-remembered timetable would date the wrong classes, so the whole list is refused — send it again with \(offenders.count == 1 ? "that date" : "those dates") corrected."
            case .couldNotWrite(let code, let number, let reason):
                return "The class dates for \(code) Section \(number) could not be saved, so they are NOT remembered: \(reason)"
            }
        }
    }

    // MARK: - Stored properties

    /// The earliest class date a remembered timetable can hold and be
    /// believed — `file-formats.json` → `sectionTimetable.believable.earliest`.
    /// Generous on purpose (last year's dates are fine), and still centuries
    /// clear of every wrong reading a calendar can produce: a Buddhist year
    /// read as Gregorian is 2569, a Gregorian one read as Buddhist 1483, an
    /// Umm al-Qura one 1448.
    static let earliestBelievable: CalendarDay = CalendarDay(year: 2000, month: 1, day: 1)!

    /// How many years past today a remembered class may fall and be believed
    /// — `sectionTimetable.believable.yearsAhead`. Future class dates are the
    /// point of the file; the nearest wrong reading is 543 years out.
    static let yearsAheadBelievable: Int = 3

    // MARK: - Functions

    /// The first of these dates that cannot be a class date — before
    /// `earliestBelievable`, or more than `yearsAheadBelievable` years past
    /// `today` — or nil when every one of them can (GitHub #377, from
    /// Windows #144).
    ///
    /// Asked by the reader AND the writer, so what one accepts the other
    /// believes: a list the writer saved and the reader then disbelieved
    /// would be a timetable remembered and, the next moment, missing.
    ///
    /// Why it exists: until #144 the Windows app wrote each year in the PC's
    /// own calendar, so a Thai-locale PC wrote `2569-09-08` for 2026-09-08.
    /// This file travels inside the course folder — through backups,
    /// archives, restores and shared working folders — so a mac can meet one,
    /// and read invariantly it is the Gregorian year 2569: "when is my next
    /// class?" answered from five centuries ahead, with nothing reporting a
    /// fault.
    static func firstDateThatCannotBeAClassDate(in dates: [CalendarDay], today: CalendarDay) -> CalendarDay? {
        for date in dates {
            if !canBeAClassDate(date, today: today) {
                return date
            }
        }
        return nil
    }

    /// Whether one date falls inside the window — both bounds inclusive.
    static func canBeAClassDate(_ date: CalendarDay, today: CalendarDay) -> Bool {
        if date < earliestBelievable {
            return false
        }
        if latestBelievable(after: today) < date {
            return false
        }
        return true
    }

    /// `today` moved `yearsAheadBelievable` years on. The 29th of February
    /// lands on the 28th in a year without one, as .NET's `AddYears` does on
    /// Windows, so both apps draw the ceiling on the same day.
    static func latestBelievable(after today: CalendarDay) -> CalendarDay {
        let year: Int = today.year + yearsAheadBelievable
        if let sameDay = CalendarDay(year: year, month: today.month, day: today.day) {
            return sameDay
        }
        return CalendarDay(year: year, month: today.month, day: 28)!
    }

    /// The trail's words when a remembered timetable is set aside — the date
    /// that could not be a class date, and what happens next. Never a page,
    /// never the teacher's description of where the dates came from.
    static func setAsideTrailLine(naming impossible: CalendarDay) -> String {
        return "remembered class dates set aside: they include \(impossible.text), which cannot be a class date, so they will be asked for again"
    }

    /// Where a section's remembered timetable lives.
    static func fileURL(forSection sectionNumber: Int, in course: Course) -> URL {
        return course.directoryURL
            .appendingPathComponent(".internal")
            .appendingPathComponent("timetable")
            .appendingPathComponent("section\(sectionNumber).json")
    }

    /// What was remembered for this section, or nil when nothing was.
    ///
    /// Throws only when a file IS there and cannot be read whole — the caller
    /// then tells the teacher rather than silently working from a fraction of
    /// their timetable.
    ///
    /// A file holding a date that cannot be a class date
    /// (`firstDateThatCannotBeAClassDate`) is read as NOTHING remembered, and
    /// says so on the trail: the teacher is asked for the dates again, and the
    /// next write replaces the file. Not a throw, because there is nothing the
    /// teacher can fix in the file — it was written by an older Windows app,
    /// and asking again is the cure. `today` is for tests, which need an
    /// answer that does not move.
    static func read(
        forSection sectionNumber: Int,
        in course: Course,
        today: CalendarDay = CalendarDay.today()
    ) throws -> SectionTimetable? {
        let url: URL = fileURL(forSection: sectionNumber, in: course)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let remembered = try timetable(fromJSON: data, courseCode: course.code, sectionNumber: sectionNumber) else {
            return nil
        }
        if let impossible = firstDateThatCannotBeAClassDate(in: remembered.dates, today: today) {
            ActivityTrail.note(
                .rememberedTimetableSetAside,
                setAsideTrailLine(naming: impossible),
                course: course.code,
                section: sectionNumber
            )
            return nil
        }
        return remembered
    }

    /// The stored shape, read. Pure, so the refusal can be tested without a
    /// course folder on disk.
    static func timetable(fromJSON data: Data, courseCode: String, sectionNumber: Int) throws -> SectionTimetable? {
        guard let decoded = try? JSONSerialization.jsonObject(with: data),
              let values = decoded as? [String: Any] else {
            throw Problem.halfRemembered(courseCode, sectionNumber, ["the file is not readable JSON"])
        }
        guard let storedDates = values["dates"] as? [Any] else {
            throw Problem.halfRemembered(courseCode, sectionNumber, ["there are no dates in it"])
        }

        var dates: [CalendarDay] = []
        var offenders: [String] = []
        for entry in storedDates {
            let text: String = entry as? String ?? String(describing: entry)
            guard let day = CalendarDay(text: text) else {
                offenders.append("“\(text)”")
                continue
            }
            if !dates.contains(day) {
                dates.append(day)
            }
        }
        if !offenders.isEmpty {
            throw Problem.halfRemembered(courseCode, sectionNumber, offenders)
        }
        if dates.isEmpty {
            throw Problem.halfRemembered(courseCode, sectionNumber, ["the list of dates is empty"])
        }
        dates.sort()

        let source: String = values["source"] as? String ?? "not recorded"
        var recorded: CalendarDay? = nil
        if let recordedText = values["recorded"] as? String {
            recorded = CalendarDay(text: recordedText)
        }
        let storedSection: Int = values["section"] as? Int ?? sectionNumber
        return SectionTimetable(
            sectionNumber: storedSection,
            dates: dates,
            source: source,
            recorded: recorded
        )
    }

    /// Every given date read as a day, or a refusal naming the ones that could
    /// not be — never a shortened list. Pure.
    ///
    /// A list holding a date that cannot be a class date is refused too, and
    /// the refusal names every such date (#377): the reader would set that
    /// file aside, so saving it would tell the teacher their timetable was
    /// remembered and then ask for it again.
    static func checkedDates(
        _ given: [String],
        courseCode: String,
        sectionNumber: Int,
        today: CalendarDay = CalendarDay.today()
    ) throws -> [CalendarDay] {
        var dates: [CalendarDay] = []
        var offenders: [String] = []
        for text in given {
            let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            guard let day = CalendarDay(text: trimmed) else {
                offenders.append("“\(trimmed)”")
                continue
            }
            if !dates.contains(day) {
                dates.append(day)
            }
        }
        if !offenders.isEmpty {
            throw Problem.unreadableDates(courseCode, sectionNumber, offenders)
        }
        if dates.isEmpty {
            throw Problem.noDatesGiven(courseCode, sectionNumber)
        }
        dates.sort()

        var impossible: [String] = []
        for date in dates {
            if !canBeAClassDate(date, today: today) {
                impossible.append("“\(date.text)”")
            }
        }
        if !impossible.isEmpty {
            throw Problem.cannotBeClassDates(courseCode, sectionNumber, impossible)
        }
        return dates
    }

    /// What remembering these dates would do, in words meant to be read aloud.
    /// Changes nothing on disk.
    static func planRememberTimetable(
        dates given: [String],
        source: String,
        forSection sectionNumber: Int,
        in course: Course,
        today: CalendarDay = CalendarDay.today()
    ) throws -> RememberTimetablePlan {
        let dates: [CalendarDay] = try checkedDates(
            given, courseCode: course.code, sectionNumber: sectionNumber, today: today
        )
        let describedSource: String = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "not recorded"
            : source.trimmingCharacters(in: .whitespacesAndNewlines)

        // A timetable already on disk that cannot be read whole must not stop
        // a teacher replacing it — replacing it is exactly the cure.
        let existing: SectionTimetable? = try? read(forSection: sectionNumber, in: course)

        return RememberTimetablePlan(
            courseCode: course.code,
            sectionNumber: sectionNumber,
            dates: dates,
            source: describedSource,
            recorded: today,
            replacing: existing,
            fileURL: fileURL(forSection: sectionNumber, in: course)
        )
    }

    /// Write the dates down. The plan is trusted because the plan is the only
    /// thing that can make one — every list has already been through
    /// `checkedDates`.
    static func applyRememberTimetable(_ plan: RememberTimetablePlan) throws {
        var datesText: [String] = []
        for date in plan.dates {
            datesText.append(date.text)
        }

        var values: [String: Any] = [:]
        values["section"] = plan.sectionNumber
        values["dates"] = datesText
        values["source"] = plan.source
        values["recorded"] = plan.recorded.text

        let fileManager: FileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: plan.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // Key order is alphabetical, which neither reader minds — both
            // look keys up by name.
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data: Data = try JSONSerialization.data(withJSONObject: values, options: options)
            data.append(contentsOf: [0x0A])
            try data.write(to: plan.fileURL, options: [.atomic])
        } catch {
            throw Problem.couldNotWrite(plan.courseCode, plan.sectionNumber, error.localizedDescription)
        }
    }

    /// "“a”, “b” and “c”" — for refusals that name what went wrong.
    ///
    /// `nonisolated` because the refusal messages above are written inside
    /// `errorDescription`, which `LocalizedError` requires to be reachable
    /// from anywhere. Nothing here touches the main actor.
    nonisolated static func list(_ items: [String]) -> String {
        if items.isEmpty {
            return "nothing"
        }
        if items.count == 1 {
            return items[0]
        }
        var leading: [String] = items
        let last: String = leading.removeLast()
        return leading.joined(separator: ", ") + " and " + last
    }
}

/// What remembering a timetable would do. Nothing here has happened yet.
struct RememberTimetablePlan {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let dates: [CalendarDay]
    let source: String
    let recorded: CalendarDay

    /// What is already remembered, and would be replaced.
    let replacing: SectionTimetable?

    /// Where it would be written.
    let fileURL: URL

    // MARK: - Computed properties

    /// True when the same dates from the same place are already remembered.
    var changesNothing: Bool {
        guard let replacing else {
            return false
        }
        return replacing.dates == dates && replacing.source == source
    }

    /// The proposal, as a teacher would hear it.
    var description: String {
        var lines: [String] = []

        if changesNothing {
            lines.append("\(courseCode) Section \(sectionNumber) already has exactly these \(dates.count) class dates recorded, so nothing would change.")
            return lines.joined(separator: "\n")
        }

        lines.append("Remember \(dates.count) class date\(dates.count == 1 ? "" : "s") for \(courseCode) Section \(sectionNumber), from \(dates[0].text) (\(dates[0].weekdayName)) to \(dates[dates.count - 1].text) (\(dates[dates.count - 1].weekdayName)).")
        lines.append("")
        lines.append("Where they came from: \(source).")

        if let replacing {
            lines.append("")
            var recordedNote: String = ""
            if let when = replacing.recorded {
                recordedNote = ", recorded \(when.text)"
            }
            lines.append("This replaces the \(replacing.dates.count) date\(replacing.dates.count == 1 ? "" : "s") already remembered\(recordedNote) — from \(replacing.source).")
        }

        lines.append("")
        lines.append("They are kept inside the course folder, so they travel with it through backup, archive and restore.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Initializer

    init(
        courseCode: String,
        sectionNumber: Int,
        dates: [CalendarDay],
        source: String,
        recorded: CalendarDay,
        replacing: SectionTimetable?,
        fileURL: URL
    ) {
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.dates = dates
        self.source = source
        self.recorded = recorded
        self.replacing = replacing
        self.fileURL = fileURL
    }
}
