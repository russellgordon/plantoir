import Foundation

/// How a teacher's class dates get IN.
///
/// `SectionTimetable` remembers the days a section meets, and everything that
/// dates a class page reads them from there. What it does not say is where the
/// list came from in the first place. A teacher has one — in a shared Google
/// Sheet the office published, in a file they exported, or simply in front of
/// them ready to be pasted — and this turns any of those three into calendar
/// days.
///
/// **The reading happens here, in Swift, and never in the assistant's model.**
/// That is the whole point of this file. The assistant's job is to notice that
/// a timetable is missing and offer this; it never reads the column itself. So
/// the small model a teacher runs on their own Mac is exactly as capable at
/// this as any model in a data centre, and neither of them can invent a date
/// that was not in the file — the failure that would be hardest to catch,
/// because a plausible wrong date looks exactly like a right one.
///
/// The other thing worth stating out loud is about ordering. `08/09/2026` is
/// the 8th of September to a Canadian teacher reading a British colleague's
/// spreadsheet and the 9th of August to an American one, and there is no way
/// to tell from the value alone. Guessing puts a teacher's classes months from
/// where they belong, and they do not find out until a class page appears on
/// the wrong day in November.
///
/// So it is never guessed. But it is not refused either, because their
/// spreadsheet is not WRONG — it just does not say. First the column is asked:
/// one value anywhere in it with a number above 12 settles the whole thing,
/// and most columns have one. Only when nothing in the column can settle it
/// does this hand back a QUESTION for the teacher, quoting one of their own
/// dates read both ways. That is one click, and then the answer applies to
/// every row at once.
nonisolated enum SectionScheduleSource {

    // MARK: - Types

    /// Fetching a URL, injected so the Google Sheet route can be tested
    /// without a network — and without a shared sheet that might stop being
    /// shared.
    typealias Fetch = @Sendable (URL) async throws -> Data

    /// Which way round a column of `08/09/2026` values is written.
    enum ColumnOrdering: Equatable, Sendable {
        case dayThenMonth
        case monthThenDay

        /// How the choice is written into the remembered `source`, so months
        /// later a teacher squinting at a date can see which way it was read.
        var note: String {
            switch self {
            case .dayThenMonth:
                return "day first"
            case .monthThenDay:
                return "month first"
            }
        }
    }

    /// What came back from reading somewhere: either the dates, or the one
    /// question only the teacher can answer.
    enum Outcome {
        case dates(Reading)
        case question(OrderingQuestion)
    }

    /// Dates read from somewhere, with a first suggestion at how to describe
    /// where they came from.
    ///
    /// The suggestion is only ever a starting point. `SectionTimetable` stores
    /// the description in the teacher's own terms — "timetable.xlsx, block H"
    /// — because that string is what they read months later when they wonder
    /// where these dates came from, and "a Google Sheet" answers that question
    /// far less well than they can themselves.
    struct Reading {

        // MARK: - Stored properties

        let dates: [CalendarDay]

        /// What to put in the "where these came from" field before the teacher
        /// improves on it.
        let suggestedSource: String

        /// The ordering the teacher was asked for and chose, when they were
        /// asked at all. Nil when the column settled the question itself.
        let chosenOrdering: ColumnOrdering?

        // MARK: - Computed properties

        /// The dates as `SectionTimetableStore.planRememberTimetable` wants
        /// them.
        var datesText: [String] {
            var result: [String] = []
            for date in dates {
                result.append(date.text)
            }
            return result
        }

        // MARK: - Initializer

        init(dates: [CalendarDay], suggestedSource: String, chosenOrdering: ColumnOrdering? = nil) {
            self.dates = dates
            self.suggestedSource = suggestedSource
            self.chosenOrdering = chosenOrdering
        }
    }

    /// "Is 08/09/2026 the 8th of September, or the 9th of August?"
    ///
    /// Raised only when nothing in the whole column can answer it. It quotes a
    /// real value out of the teacher's own file, expanded both ways, because
    /// that is a question about their timetable and can be answered in a
    /// second — where "is this DD/MM or MM/DD?" is a question about notation
    /// and makes people stop and think about the wrong thing.
    ///
    /// It carries the column along with it, so answering re-reads what was
    /// already in hand rather than fetching the Google Sheet a second time.
    struct OrderingQuestion {

        // MARK: - Stored properties

        /// One of their own dates, exactly as their file writes it.
        let written: String

        /// "the 8th of September" and "the 9th of August" — for the question.
        let dayFirstSpoken: String
        let monthFirstSpoken: String

        /// "8 September" and "9 August" — for the two buttons.
        let dayFirstShort: String
        let monthFirstShort: String

        /// Everything needed to finish the job once the answer is in.
        let column: [String]
        let place: String
        let suggestedSource: String

        // MARK: - Computed properties

        /// The question, as a teacher reads it.
        var prompt: String {
            return "These dates can be read two ways, and nothing in \(place) settles which. Is “\(written)” \(dayFirstSpoken), or \(monthFirstSpoken)?"
        }

        // MARK: - Functions

        /// The teacher's answer, applied to the WHOLE column — every row, not
        /// only the ones that were ambiguous. A column read two different ways
        /// down its length is the failure this whole mechanism exists to
        /// prevent.
        func answered(_ ordering: ColumnOrdering) throws -> Reading {
            let outcome: Outcome = try SectionScheduleSource.read(
                column: column,
                describing: place,
                suggestedSource: suggestedSource,
                ordering: ordering
            )
            guard case .dates(let reading) = outcome else {
                // Unreachable: an answered question cannot ask again.
                throw Problem.nothingToRead(place)
            }
            return Reading(
                dates: reading.dates,
                suggestedSource: "\(suggestedSource), \(ordering.note)",
                chosenOrdering: ordering
            )
        }
    }

    /// One value from the column, as far as it can be read on its own —
    /// before the column as a whole has said which way round its numbers go.
    enum Entry {
        case day(CalendarDay)
        case numbersInEitherOrder(first: Int, second: Int, year: Int, written: String)
        case unreadable(String)
    }

    /// Why a list of dates was turned away, in words a teacher can act on.
    ///
    /// Every one of these refuses the WHOLE list. That matches
    /// `SectionTimetableStore`, and for the same reason: a timetable missing
    /// three days in February does not announce itself, it just quietly dates
    /// the wrong classes.
    ///
    /// Note what is NOT in here: a column whose day/month ordering cannot be
    /// worked out. That is not a mistake in the teacher's file, so it is a
    /// question rather than a refusal — see `OrderingQuestion`.
    enum Problem: LocalizedError {
        case nothingToRead(String)
        case unreadableEntries(String, [String])
        case contradictoryOrdering(String, String, String)
        case notAGoogleSheetLink(String)
        case aPublishedSheetLink
        case sheetIsNotShared
        case couldNotFetch(String)
        case unsupportedFile(String)
        case couldNotReadFile(String, String)
        case noStartDatesInCalendar(String)

        var errorDescription: String? {
            return sentence(noun: .class)
        }

        /// The refusal in a course's own noun: the Class Dates sheet says
        /// the one sentence naming classes as meetings in a club (#1027).
        func sentence(noun: ClassNoun) -> String {
            switch self {
            case .nothingToRead(let place):
                return "There are no dates in \(place), so there is nothing to remember."

            case .unreadableEntries(let place, let offenders):
                return AssistWording.classDatesHalfRead(
                    offenders: SectionTimetableStore.list(offenders), count: offenders.count, from: place, noun: noun
                )

            case .contradictoryOrdering(let place, let dayFirst, let monthFirst):
                return "\(place) is written both ways round: “\(dayFirst)” can only be day/month/year, and “\(monthFirst)” can only be month/day/year. Nothing was read, because either reading would be wrong for half the column. Write them all the same way, or as 2026-09-08."

            case .notAGoogleSheetLink(let link):
                return "“\(link)” is not a Google Sheet link. Open the sheet in your browser and copy the address from the address bar — it looks like https://docs.google.com/spreadsheets/d/…/edit."

            case .aPublishedSheetLink:
                return "That is a “published to the web” link, which Plantoir cannot read a column from. Open the sheet itself and copy the address from the address bar instead — it looks like https://docs.google.com/spreadsheets/d/…/edit."

            case .sheetIsNotShared:
                return "Google sent back a sign-in page instead of the sheet: that sheet is not shared, so Plantoir cannot read it. In the sheet, choose Share, and under General access pick “Anyone with the link”. Then try again."

            case .couldNotFetch(let reason):
                return "The Google Sheet could not be fetched: \(reason). Nothing was read."

            case .unsupportedFile(let name):
                return "Plantoir cannot read “\(name)”. It reads a .csv file with one column of dates, or a .ics calendar export."

            case .couldNotReadFile(let name, let reason):
                return "“\(name)” could not be opened: \(reason)"

            case .noStartDatesInCalendar(let name):
                return "There are no events in “\(name)” — Plantoir looked for the DTSTART lines a calendar export writes and found none. Nothing was read."
            }
        }
    }

    // MARK: - Functions — typed or pasted text

    /// A column a teacher typed or pasted, one date per line.
    ///
    /// A header row and blank lines are forgiven, because a teacher who
    /// selects a column in a spreadsheet and copies it brings both along and
    /// should not have to tidy up by hand.
    static func read(fromTypedText text: String, ordering: ColumnOrdering? = nil) throws -> Outcome {
        var column: [String] = []
        for line in text.components(separatedBy: .newlines) {
            column.append(line)
        }
        return try read(
            column: column,
            describing: "what you pasted",
            suggestedSource: "pasted by hand",
            ordering: ordering
        )
    }

    // MARK: - Functions — a file the teacher picks

    /// A `.csv` or `.ics` file, read by what it is rather than by asking.
    static func read(fromFileAt url: URL, ordering: ColumnOrdering? = nil) throws -> Outcome {
        let name: String = url.lastPathComponent
        let suffix: String = url.pathExtension.lowercased()
        if suffix != "csv" && suffix != "ics" {
            throw Problem.unsupportedFile(name)
        }

        var text: String = ""
        do {
            let data: Data = try Data(contentsOf: url)
            guard let decoded = decodedText(from: data) else {
                throw Problem.couldNotReadFile(name, "it is not text this app can read")
            }
            text = decoded
        } catch let problem as Problem {
            throw problem
        } catch {
            throw Problem.couldNotReadFile(name, error.localizedDescription)
        }

        var column: [String] = []
        if suffix == "csv" {
            column = self.column(fromCSV: text)
        } else {
            column = try self.column(fromCalendarExport: text, describing: name)
        }
        return try read(column: column, describing: name, suggestedSource: name, ordering: ordering)
    }

    /// One column of a comma-separated file.
    ///
    /// The first field on a row that has anything in it is taken as the date,
    /// so a leading empty column, a trailing comma, or a second column of
    /// notes beside the dates all read correctly.
    static func column(fromCSV text: String) -> [String] {
        var result: [String] = []
        for row in text.components(separatedBy: .newlines) {
            result.append(firstField(inCSVRow: row))
        }
        return result
    }

    /// A calendar export: every `DTSTART`, and nothing else in the file.
    ///
    /// A `.ics` is full of things that are not the date a class meets —
    /// creation stamps, alarm triggers, when the file was last changed. Only
    /// `DTSTART` says when an event begins, so only `DTSTART` is read.
    static func column(fromCalendarExport text: String, describing place: String) throws -> [String] {
        var result: [String] = []
        for line in unfolded(text) {
            let uppercased: String = line.uppercased()
            if !uppercased.hasPrefix("DTSTART") {
                continue
            }
            guard let colon = line.firstIndex(of: ":") else {
                continue
            }
            let value: String = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(calendarDayText(fromCalendarValue: value))
        }
        if result.isEmpty {
            throw Problem.noStartDatesInCalendar(place)
        }
        return result
    }

    /// `20260908T090000Z` and `20260908` both begin with the day. Anything
    /// else is handed on as it stands, so the column reader can name it in a
    /// refusal rather than this quietly dropping it.
    static func calendarDayText(fromCalendarValue value: String) -> String {
        let characters: [Character] = Array(value)
        if characters.count < 8 {
            return value
        }
        for position in 0..<8 where !characters[position].isASCII || !characters[position].isNumber {
            return value
        }
        let year: String = String(characters[0..<4])
        let month: String = String(characters[4..<6])
        let day: String = String(characters[6..<8])
        return "\(year)-\(month)-\(day)"
    }

    /// A calendar file wraps long lines, continuing them with a leading space
    /// or tab. Joining them back up first means a wrapped `DTSTART` is read
    /// rather than half-read.
    static func unfolded(_ text: String) -> [String] {
        var result: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line: String = raw.replacingOccurrences(of: "\r", with: "")
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if result.isEmpty {
                    continue
                }
                let continuation: String = String(line.dropFirst())
                result[result.count - 1] = result[result.count - 1] + continuation
                continue
            }
            result.append(line)
        }
        return result
    }

    /// The first field on a comma-separated row that has anything in it,
    /// with any quoting taken off.
    static func firstField(inCSVRow row: String) -> String {
        var fields: [String] = []
        var current: String = ""
        var insideQuotes: Bool = false
        for character in row {
            if character == "\"" {
                insideQuotes = !insideQuotes
                continue
            }
            if character == "," && !insideQuotes {
                fields.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        fields.append(current)

        for field in fields {
            let trimmed: String = field.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    // MARK: - Functions — a Google Sheet

    /// The address that hands back a shared sheet as plain CSV.
    ///
    /// A teacher pastes what is in their browser's address bar, which is the
    /// `/edit` form; Google will serve the same document as CSV from
    /// `/export`, so the conversion happens here rather than being something
    /// anybody has to know.
    static func csvURL(forGoogleSheetLink link: String) throws -> URL {
        let trimmed: String = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker: String = "/spreadsheets/d/"
        guard let markerRange = trimmed.range(of: marker) else {
            throw Problem.notAGoogleSheetLink(trimmed)
        }

        var identifier: String = ""
        for character in trimmed[markerRange.upperBound...] {
            if character == "/" || character == "?" || character == "#" {
                break
            }
            identifier.append(character)
        }
        if identifier == "e" {
            throw Problem.aPublishedSheetLink
        }
        if identifier.isEmpty || !isDocumentIdentifier(identifier) {
            throw Problem.notAGoogleSheetLink(trimmed)
        }

        var address: String = "https://docs.google.com/spreadsheets/d/\(identifier)/export?format=csv"
        // A sheet with several tabs opens on one of them, and the address
        // says which. Carrying the tab across means the teacher gets the
        // column they were looking at, not whichever tab happens to be first.
        if let tab = tabIdentifier(inGoogleSheetLink: trimmed) {
            address += "&gid=\(tab)"
        }
        guard let url = URL(string: address) else {
            throw Problem.notAGoogleSheetLink(trimmed)
        }
        return url
    }

    /// The `gid=…` a Google Sheet address carries, from either the query or
    /// the part after the `#`.
    static func tabIdentifier(inGoogleSheetLink link: String) -> String? {
        guard let marker = link.range(of: "gid=") else {
            return nil
        }
        var digits: String = ""
        for character in link[marker.upperBound...] {
            if character.isASCII && character.isNumber {
                digits.append(character)
                continue
            }
            break
        }
        if digits.isEmpty {
            return nil
        }
        return digits
    }

    static func isDocumentIdentifier(_ identifier: String) -> Bool {
        for character in identifier {
            if character.isASCII && (character.isLetter || character.isNumber) {
                continue
            }
            if character == "-" || character == "_" {
                continue
            }
            return false
        }
        return true
    }

    /// One column of dates out of a shared Google Sheet.
    ///
    /// **This is the one thing in the assistant that leaves the Mac.** The
    /// fetch is passed in rather than reached for, so that is visible at every
    /// call site, and so the failure below can be tested without a network.
    static func read(
        fromGoogleSheetLink link: String,
        fetch: Fetch = networkFetch,
        ordering: ColumnOrdering? = nil
    ) async throws -> Outcome {
        let url: URL = try csvURL(forGoogleSheetLink: link)

        var body: Data = Data()
        do {
            body = try await fetch(url)
        } catch {
            throw Problem.couldNotFetch(error.localizedDescription)
        }

        // The single most likely thing to go wrong, and the reason this check
        // exists at all: a sheet that has not been link-shared does not fail
        // the fetch. Google answers cheerfully with a sign-in page, so the
        // body is HTML where CSV was expected. Read as a column, that is one
        // enormous unreadable entry and a baffled teacher; named, it is a
        // sentence and thirty seconds in the Share menu.
        if looksLikeHTML(body) {
            throw Problem.sheetIsNotShared
        }

        guard let csv = decodedText(from: body) else {
            throw Problem.couldNotFetch("what came back was not text")
        }

        return try read(
            column: column(fromCSV: csv),
            describing: "that Google Sheet",
            suggestedSource: "a Google Sheet",
            ordering: ordering
        )
    }

    /// True when a body is a web page rather than the CSV that was asked for.
    static func looksLikeHTML(_ body: Data) -> Bool {
        guard let text = decodedText(from: body) else {
            return false
        }
        let start: String = String(
            text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)
        ).lowercased()
        if start.hasPrefix("<!doctype html") || start.hasPrefix("<html") {
            return true
        }
        if start.contains("<html") || start.contains("<head") {
            return true
        }
        return false
    }

    static func decodedText(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// The real fetch. Named separately so the injected one is the ordinary
    /// case rather than the test-only one.
    static let networkFetch: Fetch = { url in
        var request: URLRequest = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    // MARK: - Functions — reading a column

    /// A column of text read as calendar days — or the one question the column
    /// cannot answer for itself, or a refusal naming exactly what stopped it.
    /// Never a shortened list.
    ///
    /// Sorted, with repeats collapsed. A repeat is not an error: it is what a
    /// spreadsheet looks like when somebody has copied a week down twice.
    ///
    /// `ordering` is the teacher's answer to a question this raised earlier.
    /// It is used only where the column itself has nothing to say — a column
    /// containing `13/05/2026` has already settled the matter, and settles it
    /// for every row, so no answer can override it.
    static func read(
        column: [String],
        describing place: String,
        suggestedSource: String,
        ordering answered: ColumnOrdering? = nil
    ) throws -> Outcome {
        var values: [String] = []
        for line in column {
            let trimmed: String = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            values.append(trimmed)
        }
        if values.isEmpty {
            throw Problem.nothingToRead(place)
        }

        // A header row is forgiven, but only the first line and only when
        // there is something after it. Forgiving unreadable lines anywhere
        // would be exactly the half-read timetable this refuses to build.
        var entries: [Entry] = []
        for value in values {
            entries.append(entry(from: value))
        }
        if case .unreadable = entries[0], entries.count > 1 {
            entries.removeFirst()
        }

        var offenders: [String] = []
        var dayFirstProof: String? = nil
        var monthFirstProof: String? = nil
        var undecided: String? = nil

        for entry in entries {
            switch entry {
            case .day:
                continue
            case .unreadable(let written):
                offenders.append("“\(written)”")
            case .numbersInEitherOrder(let first, let second, _, let written):
                if first > 12 && second > 12 {
                    offenders.append("“\(written)”")
                    continue
                }
                if first > 12 {
                    dayFirstProof = dayFirstProof ?? written
                    continue
                }
                if second > 12 {
                    monthFirstProof = monthFirstProof ?? written
                    continue
                }
                // Both are 12 or under. `09/09/2026` still means one day
                // whichever way round it is read, so it is not a question
                // anybody needs to answer.
                if first != second {
                    undecided = undecided ?? written
                }
            }
        }
        if !offenders.isEmpty {
            throw Problem.unreadableEntries(place, offenders)
        }
        if let dayFirstProof, let monthFirstProof {
            throw Problem.contradictoryOrdering(place, dayFirstProof, monthFirstProof)
        }

        // The column speaks first: one value with a number above 12 anywhere
        // in it settles every row, and the teacher is never asked.
        var ordering: ColumnOrdering = .dayThenMonth
        if monthFirstProof != nil {
            ordering = .monthThenDay
        } else if dayFirstProof == nil {
            if let answer = answered {
                ordering = answer
            } else if let undecided {
                // Nothing in the whole column has a number above 12 in it, so
                // there is genuinely no way to tell. Ask, quoting one of their
                // own dates.
                return .question(question(about: undecided, column: column, place: place, suggestedSource: suggestedSource))
            }
        }

        var dates: [CalendarDay] = []
        for entry in entries {
            switch entry {
            case .day(let day):
                if !dates.contains(day) {
                    dates.append(day)
                }
            case .numbersInEitherOrder(let first, let second, let year, let written):
                // One ordering, applied to the whole column. Reading a column
                // row by row — "this one looks like a day, that one looks
                // like a month" — is exactly how a timetable ends up half
                // right, which is worse than wrong.
                var month: Int = second
                var dayOfMonth: Int = first
                if ordering == .monthThenDay {
                    month = first
                    dayOfMonth = second
                }
                guard let day = CalendarDay(year: year, month: month, day: dayOfMonth) else {
                    offenders.append("“\(written)”")
                    continue
                }
                if !dates.contains(day) {
                    dates.append(day)
                }
            case .unreadable(let written):
                offenders.append("“\(written)”")
            }
        }
        if !offenders.isEmpty {
            throw Problem.unreadableEntries(place, offenders)
        }
        if dates.isEmpty {
            throw Problem.nothingToRead(place)
        }
        dates.sort()
        return .dates(Reading(dates: dates, suggestedSource: suggestedSource, chosenOrdering: nil))
    }

    /// The question to put to the teacher, built around one of their own
    /// dates.
    static func question(
        about written: String,
        column: [String],
        place: String,
        suggestedSource: String
    ) -> OrderingQuestion {
        let parts: [Int] = numbers(inWritten: written)
        return OrderingQuestion(
            written: written,
            dayFirstSpoken: spoken(day: parts[0], month: parts[1]),
            monthFirstSpoken: spoken(day: parts[1], month: parts[0]),
            dayFirstShort: shortened(day: parts[0], month: parts[1]),
            monthFirstShort: shortened(day: parts[1], month: parts[0]),
            column: column,
            place: place,
            suggestedSource: suggestedSource
        )
    }

    /// One value, read as far as it can be on its own.
    static func entry(from written: String) -> Entry {
        let trimmed: String = written.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .unreadable(trimmed)
        }
        if let day = CalendarDay(text: trimmed) {
            return .day(day)
        }
        if let separated = entryFromSeparatedNumbers(trimmed) {
            return separated
        }
        if let named = dayFromMonthName(trimmed) {
            return .day(named)
        }
        return .unreadable(trimmed)
    }

    /// `2026-09-08`, `2026/9/8`, `08/09/2026`, `9-8-2026`.
    ///
    /// A four-digit year at the FRONT settles the whole question: nobody
    /// writes a year first and then reverses the two that follow. A four-digit
    /// year at the back leaves the two in front of it to the column.
    static func entryFromSeparatedNumbers(_ written: String) -> Entry? {
        var parts: [String] = []
        var current: String = ""
        for character in written {
            if character == "/" || character == "-" || character == "." {
                parts.append(current)
                current = ""
                continue
            }
            if !character.isASCII || !character.isNumber {
                return nil
            }
            current.append(character)
        }
        parts.append(current)

        if parts.count != 3 {
            return nil
        }
        for part in parts where part.isEmpty || part.count > 4 {
            return nil
        }
        guard let one = Int(parts[0]), let two = Int(parts[1]), let three = Int(parts[2]) else {
            return nil
        }

        if parts[0].count == 4 {
            guard let day = CalendarDay(year: one, month: two, day: three) else {
                return .unreadable(written)
            }
            return .day(day)
        }
        if parts[2].count == 4 {
            if one < 1 || two < 1 {
                return .unreadable(written)
            }
            return .numbersInEitherOrder(first: one, second: two, year: three, written: written)
        }
        // A two-digit year — 08/09/26 — is a guess about the century on top
        // of a guess about the ordering, so it is not read at all.
        return .unreadable(written)
    }

    /// `Sep 8, 2026`, `September 8 2026`, `8 September 2026`, `8 Sept. 2026`.
    ///
    /// Naming the month is the one thing that makes a date unambiguous
    /// without agreeing on an ordering first, so all of these read the same
    /// way the world over.
    static func dayFromMonthName(_ written: String) -> CalendarDay? {
        var tokens: [String] = []
        var current: String = ""
        for character in written {
            if character.isLetter || (character.isASCII && character.isNumber) {
                current.append(character)
                continue
            }
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        if tokens.count != 3 {
            return nil
        }

        var month: Int? = nil
        var numbers: [Int] = []
        for token in tokens {
            if let value = Int(token) {
                numbers.append(value)
                continue
            }
            guard let named = monthNumber(named: token), month == nil else {
                return nil
            }
            month = named
        }
        guard let month, numbers.count == 2 else {
            return nil
        }

        // Whichever number is the year is the one that cannot be a day.
        var year: Int? = nil
        var dayOfMonth: Int? = nil
        if numbers[0] > 31 {
            year = numbers[0]
            dayOfMonth = numbers[1]
        } else if numbers[1] > 31 {
            year = numbers[1]
            dayOfMonth = numbers[0]
        }
        guard let year, let dayOfMonth else {
            return nil
        }
        return CalendarDay(year: year, month: month, day: dayOfMonth)
    }

    /// "Sep", "Sept", "September" — three letters is the shortest that names
    /// one month and only one.
    static func monthNumber(named token: String) -> Int? {
        var cleaned: String = ""
        for character in token where character.isLetter {
            cleaned.append(character)
        }
        cleaned = cleaned.lowercased()
        if cleaned.count < 3 {
            return nil
        }
        for position in 0..<monthNames.count where monthNames[position].hasPrefix(cleaned) {
            return position + 1
        }
        return nil
    }

    /// The two numbers in front of the year, so the question can read them
    /// both ways round.
    static func numbers(inWritten written: String) -> [Int] {
        var parts: [Int] = []
        var current: String = ""
        for character in written {
            if character.isASCII && character.isNumber {
                current.append(character)
                continue
            }
            if let value = Int(current) {
                parts.append(value)
            }
            current = ""
        }
        if let value = Int(current) {
            parts.append(value)
        }
        while parts.count < 2 {
            parts.append(1)
        }
        return parts
    }

    /// "the 8th of September" — the reading a teacher can recognise or reject
    /// at a glance, which "day/month" alone does not give them.
    static func spoken(day: Int, month: Int) -> String {
        return "the \(day)\(ordinalSuffix(day)) of \(monthName(month))"
    }

    /// "8 September" — the same thing, short enough for a button.
    static func shortened(day: Int, month: Int) -> String {
        return "\(day) \(monthName(month))"
    }

    static func monthName(_ month: Int) -> String {
        if month >= 1 && month <= 12 {
            return monthNames[month - 1].capitalized
        }
        return "that month"
    }

    static func ordinalSuffix(_ number: Int) -> String {
        if number % 100 >= 11 && number % 100 <= 13 {
            return "th"
        }
        switch number % 10 {
        case 1:
            return "st"
        case 2:
            return "nd"
        case 3:
            return "rd"
        default:
            return "th"
        }
    }

    static let monthNames: [String] = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    ]
}
