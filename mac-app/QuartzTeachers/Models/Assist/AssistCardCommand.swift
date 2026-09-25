import Foundation

/// The fixed phrasings the assistant window offers, matched in CODE rather
/// than routed through the model.
///
/// This is the least obvious thing in the whole feature, and it was measured
/// rather than guessed. The promise card's phrasings are what the window
/// TELLS a teacher it is good at, so a teacher clicks one — or types it
/// verbatim — and the assistant had better be good at it. Word for word, the
/// model misrouted **five of the eleven, in every trial**, while filling in
/// the arguments perfectly (87 trials, zero wrong courses, dates or types).
///
/// So the shapes with no ambiguity in them are matched here and never reach
/// the model. The model keeps everything with a story in it — the requests a
/// teacher phrases their own way, which is what a language model is actually
/// for. This is the same principle as the coarse tools: reasoning moved out
/// of the model is reliability bought back.
nonisolated struct AssistCardCommand: Sendable, Equatable {

    // MARK: - The rollover answers

    /// The sentence that means "roll over, and start a new website".
    ///
    /// Named rather than typed, because the assistant's own reply offers it
    /// back to the teacher word for word — a phrasing a teacher is TOLD to say
    /// and a phrasing the matcher accepts must be the same string, or the
    /// feature invites a sentence it then does not understand.
    static let rollOverOntoANewWebsite: String =
        "roll this section over onto a new website"

    /// The sentence that means "roll over, and keep last year's website".
    static let rollOverKeepingTheSameWebsite: String =
        "roll this section over, keeping the same website"

    // MARK: - Stored properties

    /// The tool this phrasing always means.
    let toolName: String

    /// Arguments the phrasing itself determines.
    let arguments: [String: String]

    // MARK: - Functions

    /// The command a teacher's message is, if it is one of the fixed shapes.
    ///
    /// Matching is deliberately strict — trimmed and case-insensitive, but
    /// otherwise the exact phrasing. A loose match here would swallow
    /// requests that only LOOK like a card phrasing ("publish tomorrow's
    /// class, but not the linked pages") and answer the wrong question with
    /// total confidence, which is worse than routing it.
    ///
    /// `numberedPageWord` is the course's own page word ("Week") when the
    /// window's course names its pages with ONE number (#267), and nil
    /// otherwise. Only the one-number make-room frame reads it: that frame
    /// matches in a numbered course alone, and only on that word or a bare
    /// number — see `makeRoomAtOneNumber`.
    static func matching(_ message: String, numberedPageWord: String? = nil) -> AssistCardCommand? {
        let tidied: String = AssistCardCommand.tidied(message)

        for (phrasing, command) in fixedShapes {
            if tidied == phrasing {
                return command
            }
        }
        if let unit = AssistCardCommand.wholeUnitOrClassPage(tidied) {
            return unit
        }
        if let more = AssistCardCommand.moreDays(tidied) {
            return more
        }
        if let room = AssistCardCommand.makeRoom(tidied, numberedPageWord: numberedPageWord) {
            return room
        }
        if let scheduled = AssistCardCommand.deployAtATime(tidied) {
            return scheduled
        }
        return AssistCardCommand.duplicateClass(tidied, original: message)
    }

    /// "Deploy at 6:30 AM", and the same with a day word.
    ///
    /// **Measured, and it is the reason this family exists.** The shelf offers
    /// this sentence word for word, and the smaller assistant sent it to
    /// `deploy_section` ten trials out of ten — a deploy to students on the
    /// spot, in answer to a teacher who asked for half six tomorrow
    /// (`research/ai-assist/metal-routing-results.txt`, issue #168). The
    /// approval card it landed on named no time at all, so nothing in front of
    /// the teacher contradicted them.
    ///
    /// A time in a fixed frame is a NUMBER, not a judgement — the same
    /// argument `makeRoom` already won for "make room for two classes at Unit
    /// 3, Day 4". So it is read here and never reaches the model, which costs
    /// the router nothing because it never sees it.
    ///
    /// **Clock-free on purpose.** This hands back `"06:30"`, or
    /// `"tomorrow 06:30"` when a day word was said, and never a date. Which
    /// DAY a bare time means is settled once, where the call is made, against
    /// the runner's own clock — `AssistToolRunner.momentText(forTimeOfDay:…)`
    /// — so this stays a pure function of the sentence, which is what lets the
    /// contract describe it as input and output.
    ///
    /// Course and section words are refused deliberately. "Deploy section 2 at
    /// 6:30 am" falls through, because this window is about ONE section and
    /// `AssistAgent` binds that section whatever the sentence said: a card that
    /// appeared to honour another section would answer a different question
    /// with total confidence.
    private static func deployAtATime(_ tidied: String) -> AssistCardCommand? {
        guard let frame = AssistCardCommand.deployFrame(tidied) else {
            return nil
        }
        guard let time = AssistCardCommand.timeOfDay(frame.timeWords) else {
            return nil
        }
        guard let dayWord = frame.dayWord else {
            return AssistCardCommand(toolName: "schedule_deploy", arguments: ["when": time])
        }
        return AssistCardCommand(
            toolName: "schedule_deploy", arguments: ["when": "\(dayWord) \(time)"]
        )
    }

    /// "Deploy at 6:30" — a time that is morning or evening, and nobody can
    /// tell which. Answered with a QUESTION, in code, and never sent to the
    /// model (issue #194).
    ///
    /// **Measured, and it is the reason this exists.** The deploy-at-a-time
    /// family refuses a one-digit hour with no am or pm on purpose — a deploy
    /// set twelve hours wrong is a site that updates after the class it was
    /// meant for — and until this, the refusal handed the sentence to the
    /// model, which on the smaller assistant proposed an IMMEDIATE deploy for
    /// the same shape of sentence ten trials out of ten. Refusing to guess and
    /// then letting something else guess was the fault.
    ///
    /// **Stateless on purpose.** The question names two sentences the family
    /// ALREADY accepts, and the teacher types one of them; that turn matches
    /// in code like any other. There is no "waiting for an answer" state, so
    /// nothing has to survive or be cleared between turns, and there are no
    /// answer phrasings of its own to become a near-miss surface — the shape
    /// the rollover question already chose (`AssistWording.rolloverWebsiteQuestion`).
    ///
    /// The frame is `deployFrame`, the one `deployAtATime` reads, so the two
    /// cannot disagree about what counts as "deploy at a time". Everything the
    /// frame refuses still goes to the model, and so does every time that is
    /// not a one-digit hour 1–9 with two digits of minutes: "deploy at 7" (a
    /// bare number may not be a time at all), "deploy at 0:30" (0 is not an
    /// hour on a twelve-hour clock, so there is no morning-or-evening to ask
    /// about) and "deploy at half six" keep their written reasons in
    /// `contracts/assist-cases.json` → `deployAtATime.refused`.
    ///
    /// The answer sentences are built in their canonical form — "deploy
    /// tomorrow at 6:30 am" — never by echoing the teacher's words, because
    /// "please", "it" or a trailing "tomorrow" are spellings the frame reads
    /// but that a sentence rebuilt around them might not.
    static func morningOrEvening(_ message: String) -> AssistTimeQuestion? {
        guard let frame = AssistCardCommand.deployFrame(AssistCardCommand.tidied(message)) else {
            return nil
        }
        guard frame.timeWords.count == 1 else {
            return nil
        }
        // Two near-spellings are ASKED about too, rather than sent to the
        // model, because both still deployed on the spot there: "deploy at
        // 6.30" (a full stop between the hour and the minutes) and "deploy at
        // 6:30, please" (a comma after the time, left behind when the frame
        // takes "please" off). Measured on the smaller assistant, ten trials
        // each: deploy_section 10 of 10 for both. Asking costs nothing —
        // nothing is set, and the answers are rebuilt below in the one
        // canonical "6:30 am" form the family accepts, so neither spelling
        // is ever offered back. This widens what is ASKED only: "deploy at
        // 6.30 pm" is still not answered in code.
        var written: String = frame.timeWords[0]
        if written.hasSuffix(",") {
            written = String(written.dropLast())
        }
        var separator: String.Index? = written.firstIndex(of: ":")
        if separator == nil {
            separator = written.firstIndex(of: ".")
        }
        guard let separator else {
            return nil
        }
        let hourText: String = String(written[written.startIndex..<separator])
        let minuteText: String = String(written[written.index(after: separator)...])
        guard AssistCardCommand.isPlainDigits(hourText),
              AssistCardCommand.isPlainDigits(minuteText),
              hourText.count == 1,
              minuteText.count == 2,
              let hour = Int(hourText), hour >= 1,
              let minute = Int(minuteText), minute <= 59 else {
            return nil
        }
        // Always written with a colon, whatever separator the teacher typed.
        let clock: String = hourText + ":" + minuteText

        var opening: String = "deploy at "
        if let dayWord = frame.dayWord {
            opening = "deploy \(dayWord) at "
        }
        return AssistTimeQuestion(
            clock: clock,
            sayMorning: opening + clock + " am",
            sayEvening: opening + clock + " pm"
        )
    }

    /// A message trimmed, case-folded, and with a trailing full stop or
    /// exclamation mark taken off — the one tidying every shape is matched
    /// after.
    private static func tidied(_ message: String) -> String {
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
            .lowercased()
    }

    /// The day word and the time's words, read out of "[please] deploy
    /// [it|this section] [today|tomorrow] at <time> [today|tomorrow]
    /// [please]" — or nil when the sentence is not that frame.
    ///
    /// Shared by `deployAtATime` and `morningOrEvening`, so a sentence the
    /// family would answer and a sentence it would ask about are the same
    /// frame by construction rather than by two copies kept in step.
    private static func deployFrame(_ tidied: String) -> (dayWord: String?, timeWords: [String])? {
        // A question mark is dropped HERE rather than by the shared tidier at
        // the top of this file. Widening that would break the fixed shapes
        // whose literal carries one — "what courses do i have?" and "when are
        // my next classes?" are matched by EQUALITY, so a shared strip would
        // stop them matching at all.
        var frame: String = tidied
        while frame.hasSuffix("?") {
            frame = String(frame.dropLast())
        }

        var words: [String] = []
        for piece in frame.split(separator: " ") {
            words.append(String(piece))
        }
        // "Please" is courtesy rather than content, at either end. "Can you
        // deploy at 7 pm" is deliberately NOT accepted: it asks about ability
        // as much as it instructs, and everything this frame cannot read
        // without guessing goes to the model.
        if words.first == "please" {
            words.removeFirst()
        }
        if words.last == "please" {
            words.removeLast()
        }
        guard words.first == "deploy" else {
            return nil
        }
        words.removeFirst()
        // "deploy it at…" and "deploy this section at…" — both name the one
        // section this window is about, which is the only section a card can
        // reach. ("deploy this section now" is already a fixed shape above.)
        if words.first == "it" {
            words.removeFirst()
        } else if words.count >= 2, words[0] == "this", words[1] == "section" {
            words.removeFirst(2)
        }

        var dayWord: String? = nil
        if let opening = words.first, opening == "today" || opening == "tomorrow" {
            dayWord = opening
            words.removeFirst()
        }
        guard words.first == "at" else {
            return nil
        }
        words.removeFirst()
        if let closing = words.last, closing == "today" || closing == "tomorrow" {
            // A day word on BOTH sides is a sentence disagreeing with itself,
            // and choosing a half is exactly what this table exists to avoid.
            if dayWord != nil {
                return nil
            }
            dayWord = closing
            words.removeLast()
        }
        return (dayWord: dayWord, timeWords: words)
    }

    /// "6:30 am", "6:30am", "7 pm", "18:30", "noon", "midnight" — as `HH:mm`,
    /// or nil when the spelling leaves any doubt about which minute was meant.
    ///
    /// **The rule that carries the most weight, stated once so it can be
    /// argued with: a time with no am or pm must be written with two digits
    /// for the hour.** That is what 24-hour time looks like, and it is the
    /// form `schedule_deploy`'s own schema asks for. `06:30` and `18:30` are
    /// unambiguous; `6:30` is morning or evening and nobody can tell which, so
    /// it is not read here — `morningOrEvening` asks the teacher which, in
    /// code (issue #194). A deploy set twelve hours wrong is a site that
    /// updates after the class it was meant for.
    private static func timeOfDay(_ words: [String]) -> String? {
        guard words.count == 1 || words.count == 2 else {
            return nil
        }
        if words.count == 1 {
            // The two times a teacher writes with no digits in them. Both are
            // exact readings — 12:00 and 00:00 — and both are handled the same
            // way as "12 pm" and "12 am", which a teacher may equally type.
            // Neither is a silent guess about the DAY: the approval card names
            // the whole moment, weekday and date included, before anything is
            // set.
            if words[0] == "noon" {
                return "12:00"
            }
            if words[0] == "midnight" {
                return "00:00"
            }
        }

        var clock: String = words[0]
        var meridiem: String? = nil
        if words.count == 2 {
            guard let named = AssistCardCommand.meridiem(named: words[1]) else {
                return nil
            }
            meridiem = named
        } else {
            // Written up against the digits: "6:30am". The longest spellings
            // are tried first so "6:30a.m" does not lose only its last two
            // characters.
            for ending in ["a.m.", "p.m.", "a.m", "p.m", "am", "pm"]
            where meridiem == nil && clock.hasSuffix(ending) {
                meridiem = AssistCardCommand.meridiem(named: ending)
                clock = String(clock.dropLast(ending.count))
            }
        }

        var hourText: String = clock
        var minuteText: String = "00"
        if let colon = clock.firstIndex(of: ":") {
            hourText = String(clock[clock.startIndex..<colon])
            minuteText = String(clock[clock.index(after: colon)...])
        } else if meridiem == nil {
            // "deploy at 7" — a bare number is not a time anybody has spelled
            // out, and reading it as an hour would schedule a deploy off a
            // number that might have been a section or a unit.
            return nil
        }
        // One or two digits of hour, always. Without the upper bound "007:30
        // am" and "0007 pm" are read as 07:30 and 19:00, because `Int` does
        // not care how a number was padded — harmless in itself, since nobody
        // types that, but it is a boundary the other platform would implement
        // as one-or-two from reading the accepted rows, and a difference no
        // suite could see. So it is stated here and pinned by a refused row.
        guard AssistCardCommand.isPlainDigits(hourText),
              AssistCardCommand.isPlainDigits(minuteText),
              hourText.count <= 2,
              minuteText.count == 2,
              let hour = Int(hourText),
              let minute = Int(minuteText), minute <= 59 else {
            return nil
        }

        guard let meridiem else {
            guard hourText.count == 2, hour <= 23 else {
                return nil
            }
            return AssistCardCommand.twoDigits(hour) + ":" + minuteText
        }
        guard hour >= 1, hour <= 12 else {
            return nil
        }
        var onTheTwentyFourHourClock: Int = hour
        if meridiem == "pm", hour != 12 {
            onTheTwentyFourHourClock = hour + 12
        }
        if meridiem == "am", hour == 12 {
            onTheTwentyFourHourClock = 0
        }
        return AssistCardCommand.twoDigits(onTheTwentyFourHourClock) + ":" + minuteText
    }

    /// "am" or "pm", from "am", "a.m", "a.m." and their afternoon twins — nil
    /// for anything else. The message has already been case-folded.
    private static func meridiem(named raw: String) -> String? {
        let folded: String = raw.replacingOccurrences(of: ".", with: "")
        if folded == "am" || folded == "pm" {
            return folded
        }
        return nil
    }

    /// Whether every character is an ASCII digit.
    ///
    /// ASCII deliberately. `Character.isNumber` is true of Arabic-Indic digits
    /// and of several other scripts, so a laxer check would accept a "clock
    /// reading" that `Int` then cannot read, and the refusal would come from
    /// somewhere further down that was not thinking about spelling at all.
    private static func isPlainDigits(_ text: String) -> Bool {
        if text.isEmpty {
            return false
        }
        for character in text {
            if !character.isASCII || !character.isNumber {
                return false
            }
        }
        return true
    }

    /// 6 → "06", 18 → "18".
    private static func twoDigits(_ number: Int) -> String {
        if number < 10 {
            return "0\(number)"
        }
        return "\(number)"
    }

    /// "Make room for a class at Unit 3, Day 4", and the same with a count.
    ///
    /// **Parity with the MCP tool, which is the rule for these** — a teacher
    /// should be able to ask for whatever a Claude Code session can. Course
    /// and section come from the window, so the three things left to say are
    /// the unit, the day, and how many. Everything in the sentence is a number
    /// in a fixed frame; none of it is a judgement, so none of it needs a
    /// model.
    ///
    /// Deliberately strict, like the rest of this table. The shape is fixed
    /// and the parts are read out of it — it does not try to understand a
    /// sentence that merely resembles this one, because answering the wrong
    /// question with total confidence is worse than routing it.
    private static func makeRoom(_ tidied: String, numberedPageWord: String?) -> AssistCardCommand? {
        let spelled: [String: Int] = [
            "a": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        ]
        let opening: String = "make room for "
        guard tidied.hasPrefix(opening) else {
            return nil
        }
        // The comma in "Unit 3, Day 4" is punctuation in the frame rather than
        // part of any value, so it is dropped before the words are counted.
        let body: String = String(tidied.dropFirst(opening.count))
            .replacingOccurrences(of: ",", with: " ")
        var words: [String] = []
        for piece in body.split(separator: " ") {
            words.append(String(piece))
        }

        // <count> class|classes|meeting|meetings at [<word>] <number> — the
        // one-number shape a numbered course's pages have (#267).
        if words.count == 4 || words.count == 5 {
            return AssistCardCommand.makeRoomAtOneNumber(
                words, spelled: spelled, numberedPageWord: numberedPageWord
            )
        }

        // <count> class|classes at unit <unit> day <day>
        guard words.count == 7,
              words[2] == "at", words[3] == "unit", words[5] == "day" else {
            return nil
        }
        guard words[1] == "class" || words[1] == "classes" else {
            return nil
        }
        guard let howMany = spelled[words[0]] ?? Int(words[0]), howMany > 0,
              let unit = Int(words[4]), unit > 0,
              let day = Int(words[6]), day > 0 else {
            return nil
        }
        // A plural count with a singular noun, or the reverse, is a sentence
        // somebody typed carelessly rather than one of these shapes — and
        // guessing which half they meant is exactly what this table exists to
        // avoid.
        guard (howMany == 1) == (words[1] == "class") else {
            return nil
        }
        return AssistCardCommand(
            toolName: "make_room_for_classes",
            arguments: ["unit": "\(unit)", "atDay": "\(day)", "howMany": "\(howMany)"]
        )
    }

    /// "Make room for a meeting at Week 5" — one number, the way a club names
    /// its pages (#267) — or "at 5", the bare number.
    ///
    /// **Matched only in a numbered course, and only on that course's own
    /// word.** The first version could not know the word, so it took any
    /// single word: "make room for a meeting at period 3", "at block 2", "at
    /// section 2" were all read as positions in a club and planned as "Week 3"
    /// (measured by the #267 implementation review), and in a Unit/Day course
    /// the same sentences stopped reaching the model, which they always had.
    /// So the window's course says what its word is (`numberedPageWord`), and
    /// without one — every Unit/Day course — this frame matches nothing and
    /// the sentence goes to the model exactly as it did before #267. "at unit
    /// 3" and "at day 5" are therefore model sentences everywhere except a
    /// numbered course whose word IS "Unit".
    ///
    /// The number goes into `unit`, which a numbered course reads as its
    /// position (`ClassInsertionPlanner.numberedPosition`).
    private static func makeRoomAtOneNumber(
        _ words: [String], spelled: [String: Int], numberedPageWord: String?
    ) -> AssistCardCommand? {
        guard let numberedPageWord, words[2] == "at" else {
            return nil
        }
        if words.count == 5 {
            let word: String = numberedPageWord.lowercased()
            guard !word.isEmpty, words[3] == word else {
                return nil
            }
        }
        let nouns: [String: Bool] = ["class": true, "meeting": true, "classes": false, "meetings": false]
        guard let isSingular = nouns[words[1]] else {
            return nil
        }
        guard let howMany = spelled[words[0]] ?? Int(words[0]), howMany > 0,
              let position = Int(words[words.count - 1]), position > 0 else {
            return nil
        }
        guard (howMany == 1) == isSingular else {
            return nil
        }
        return AssistCardCommand(
            toolName: "make_room_for_classes",
            arguments: ["unit": "\(position)", "howMany": "\(howMany)"]
        )
    }

    /// "Duplicate Unit 3, Day 2 as my next class."
    ///
    /// The page title is the only thing in it, and it sits between two fixed
    /// halves — so it can be lifted out here rather than read out by a model.
    private static func duplicateClass(_ tidied: String, original: String) -> AssistCardCommand? {
        let opening: String = "duplicate "
        guard tidied.hasPrefix(opening) else {
            return nil
        }
        // Matched on the lower-cased copy and SLICED from the original, so the
        // page title travels on with the capitals the teacher typed. Lookup
        // folds case either way; what this protects is the title being read
        // back to them in a sentence.
        let typed: String = original.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        let body: String = String(tidied.dropFirst(opening.count))
        // "meeting" is a club's word for the same page (#267): the frame is
        // identical, so it is one more ending rather than another family.
        for ending in [" as my next class", " as the next class", " as my next lesson",
                       " as my next meeting", " as the next meeting"]
        where body.hasSuffix(ending) {
            let start: String.Index = typed.index(typed.startIndex, offsetBy: opening.count)
            let end: String.Index = typed.index(typed.endIndex, offsetBy: -ending.count)
            guard start < end else {
                return nil
            }
            let title: String = String(typed[start..<end])
                .trimmingCharacters(in: .whitespaces)
            if title.isEmpty {
                return nil
            }
            return AssistCardCommand(
                toolName: "add_next_class", arguments: ["duplicate": title]
            )
        }
        return nil
    }

    /// "Add five more days to Unit 4", and the same with a digit.
    ///
    /// Parsed for the same reason `wholeUnit` is: the whole sentence IS the
    /// request, and the two numbers in it are numbers rather than judgements.
    /// Words up to twelve are understood because a teacher asking for a few
    /// more days writes "five", not "5".
    private static func moreDays(_ tidied: String) -> AssistCardCommand? {
        let spelled: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        ]
        // add <count> more days to unit <number>
        var words: [String] = []
        for piece in tidied.split(separator: " ") {
            words.append(String(piece))
        }
        guard words.count >= 6, words[0] == "add", words[3] == "days",
              words[4] == "to", words[5] == "unit", words.count == 7 else {
            return nil
        }
        guard words[2] == "more" else {
            return nil
        }
        let howMany: Int? = spelled[words[1]] ?? Int(words[1])
        guard let howMany, howMany > 0, let unit = Int(words[6]) else {
            return nil
        }
        return AssistCardCommand(
            toolName: "add_next_class",
            arguments: ["unit": "\(unit)", "days": "\(howMany)"]
        )
    }

    /// "Publish Unit 5", "Unpublish Unit 4", and — since #215 — "Hide Unit 4,
    /// Day 21".
    ///
    /// Parsed rather than listed, because unlike the seven weekdays there is
    /// no fixed set of units to write down. It is still a FIXED SHAPE in every
    /// way that matters: the whole sentence is the request, the numbers in it
    /// are the only things in it, and reading an integer out of a frame is not
    /// a judgement anybody needs a language model for.
    ///
    /// **"Hide" is here because the model could not do it, and that was
    /// measured** (issue #215, 2026-09-19, Qwen2.5-1.5B Q4_K_M with the app's
    /// own flags, request body and system prompt, temperature 0). "Unpublish
    /// unit 4, day 21" reached `unpublish_pages` every time; "hide unit 4, day
    /// 21" reached NO tool at all in five phrasings out of five — the model
    /// handed the teacher their own sentence back as text, date line and all.
    /// It errs in the safe direction, and it reads as broken. The repository's
    /// own rule says to steer with code rather than with a tool description
    /// (one clarifying sentence added to `publish_pages`' description once took
    /// the promise-card score from 110/110 to 90/110), so the word is answered
    /// here and the router never sees it.
    ///
    /// **THE WHOLE VERB IS GATED, not only the day arm, and the asymmetry is
    /// deliberate.** `hide` and `unpublish` take a whole unit or one class
    /// page, and tolerate a "please" at either end, a trailing question mark,
    /// a stray comma and odd spacing. `publish` is read by
    /// `wholeUnitToPublish` below, which is the shipped code unchanged: the
    /// literal prefix `"publish unit "` and a bare number, so "publish unit 4,
    /// day 3" still goes to the model and so do "publish unit 4?", "please
    /// publish unit 4" and "publish  unit 5".
    ///
    /// The split was made deliberately rather than inherited. The first
    /// version of this frame read the verb AFTER stripping the courtesy words
    /// and the question mark, which widened publish as a side effect: an
    /// adversarial differential fuzz of 13,464 sentences across the two
    /// matchers found 0 matches lost and **141 new `publish_pages` matches**,
    /// none of them asked for. "publish unit 4?" is the case that decided it —
    /// a teacher typing a question mark is plausibly ASKING, and that sentence
    /// would have published a whole unit with no model in the loop, which is
    /// the exact ambiguity used two paragraphs down to reject "show unit 4".
    /// Unpublishing errs safe — a page nobody can see — while publishing puts
    /// a page in front of students, and "Publish Unit 2, Day 3" is 10/10 on
    /// the smaller assistant today, so there is nothing to buy by widening the
    /// dangerous direction on the same day. Five of those 141 are pinned as
    /// `refused` rows in `hideIsUnpublish`, so the gate is data rather than a
    /// comment somebody deletes. `show` and `unhide` are out for a nearer
    /// reason: "show unit 4" is at least as likely to mean "display it to me",
    /// and getting that wrong publishes.
    ///
    /// **Any extra word must fall through, and that is a safety rule rather
    /// than tidiness.** `AssistAgent.encode` writes this window's course and
    /// section into every card call, and the guard that refuses a request
    /// naming another course lives in `think()`, which a matched card never
    /// reaches. So "hide unit 4, day 21 in ICS3U", typed in an ICS4U window,
    /// would act on ICS4U and report success — the exact failure #202 exists
    /// to remove. The frame therefore reads a fixed number of words and
    /// refuses anything else.
    ///
    /// **Term-blind on purpose, for now.** Only the literal word "unit" is
    /// matched, because this is a pure function of the sentence and a course's
    /// own word for a unit is not in it. A Module course loses nothing: "hide
    /// module 4, day 21" falls through to the model exactly as it does today,
    /// and "hide unit 4" still works there because `AssistPublishPlanner`
    /// accepts "unit" alongside the course's own word.
    private static func wholeUnitOrClassPage(_ tidied: String) -> AssistCardCommand? {
        // The two arms are separate functions because they have to be read by
        // DIFFERENT rules — see "THE WHOLE VERB IS GATED" above. Hide and
        // unpublish first; a publish sentence falls through to the shipped
        // reading below, untouched.
        if let hidden = AssistCardCommand.hideOrUnpublish(tidied) {
            return hidden
        }
        return AssistCardCommand.wholeUnitToPublish(tidied)
    }

    /// "Publish Unit 5", read exactly as it has been read since the family
    /// shipped.
    ///
    /// **Kept as its own function so the publish surface cannot move by
    /// accident.** A literal prefix, a bare number, no comma — so "publish
    /// unit 4, day 3" goes to the model (it names one page, which has a title
    /// in it to read out), and so does every sentence the hide frame beside it
    /// now tolerates: a courtesy word, a question mark, a doubled space, a
    /// stray comma. Verified by differential fuzz rather than by reading:
    /// 36,864 generated sentences through this matcher and `dev`'s, **0
    /// matches gained and 0 lost on `publish_pages`**.
    ///
    /// The `.` and `!` a teacher types at the end are still accepted, because
    /// the shared tidier at the top of this file strips them before anything
    /// here runs, and that is shipped behaviour rather than a new tolerance.
    private static func wholeUnitToPublish(_ tidied: String) -> AssistCardCommand? {
        let opening: String = "publish unit "
        guard tidied.hasPrefix(opening) else {
            return nil
        }
        let rest: String = String(tidied.dropFirst(opening.count))
            .trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty, !rest.contains(","), Int(rest) != nil else {
            return nil
        }
        return AssistCardCommand(
            toolName: "publish_pages", arguments: ["pages": "Unit \(rest)"]
        )
    }

    /// "Hide Unit 4, Day 21" and "Unpublish Unit 4" — the widened arm, and the
    /// only one the new tolerance applies to.
    private static func hideOrUnpublish(_ tidied: String) -> AssistCardCommand? {
        // A question mark comes off HERE rather than in the shared tidier, for
        // the reason `deployAtATime` gives above: the fixed shapes are matched
        // by equality and two of them carry one.
        var frame: String = tidied
        while frame.hasSuffix("?") {
            frame = String(frame.dropLast())
        }

        // The comma in "Unit 4, Day 21" is punctuation in the frame rather
        // than part of any value — the same reading `makeRoom` already uses —
        // so it is dropped before the words are counted. That makes "unit 4 ,
        // day 21" and "unit 4 day 21" the same sentence, and leaves "day21"
        // refused, because that is not a word this frame has.
        var words: [String] = []
        for piece in frame.replacingOccurrences(of: ",", with: " ").split(separator: " ") {
            words.append(String(piece))
        }
        // "Please" is courtesy rather than content, at either end — the same
        // tolerance `deployAtATime` already has.
        if words.first == "please" {
            words.removeFirst()
        }
        if words.last == "please" {
            words.removeLast()
        }

        guard words.count >= 3, words[1] == "unit" else {
            return nil
        }
        // "publish" is deliberately absent, and its absence is the gate: a
        // publish sentence falls out of here unmatched and is read by
        // `wholeUnitToPublish`, which is the shipped code.
        guard words[0] == "hide" || words[0] == "unpublish" else {
            return nil
        }
        let toolName: String = "unpublish_pages"

        // Read exactly as it was before this family grew a second arm:
        // `Int(...) != nil` is the acceptance test, and the teacher's own
        // digits are what travels into the title. Tightening this to plain
        // digits would change a shipped behaviour for no reported fault, so
        // "unit 04" still becomes "Unit 04".
        let unit: String = words[2]
        guard Int(unit) != nil else {
            return nil
        }
        if words.count == 3 {
            return AssistCardCommand(toolName: toolName, arguments: ["pages": "Unit \(unit)"])
        }
        guard words.count == 5, words[3] == "day" else {
            return nil
        }
        let day: String = words[4]
        guard Int(day) != nil else {
            return nil
        }
        return AssistCardCommand(
            toolName: toolName, arguments: ["pages": "Unit \(unit), Day \(day)"]
        )
    }

    /// A phrasing the matcher PARSES rather than compares, described so the
    /// other app can implement the same thing.
    ///
    /// The literal shapes can be listed; these cannot, because the number in
    /// them is unbounded — any unit, any count of days, any page title, any
    /// time of day. A contract that carried only the literals would say the
    /// assistant understands eleven sentences when it understands those plus
    /// six families, and Windows would build eleven.
    ///
    /// One example and one near-miss is not enough to describe a family whose
    /// variable part is a TIME, because the spellings a teacher uses are the
    /// whole question. The deploy-at-a-time family therefore has its own
    /// authored table of accepted and refused spellings in
    /// `contracts/assist-cases.json` → `deployAtATime`; this entry is its
    /// summary, not its specification.
    struct ParsedShape: Sendable, Equatable {

        // MARK: - Stored properties

        /// What the sentence looks like, with the variable part in <angle
        /// brackets>.
        let shape: String

        /// The tool it always means.
        let tool: String

        /// The argument keys it fills, and where each comes from.
        let fills: [String: String]

        /// An example, so a test has something to run.
        let example: String

        /// A sentence that must NOT match, and why — the near-miss is the
        /// half that stops a family swallowing requests it should not.
        let notThis: String
        let becauseNotThis: String

        /// The page word of the numbered course the family is matched in,
        /// for the one family that reads the window's course (#267); nil for
        /// every family that matches the sentence alone. A runner passes it
        /// to the matcher for BOTH the example and the near miss.
        var numberedPageWord: String? = nil
    }

    /// Every parsed family, for the contract.
    static var everyParsedShape: [ParsedShape] {
        return [
            ParsedShape(
                shape: "make room for <count> class|classes at unit <unit>, day <day>",
                tool: "make_room_for_classes",
                fills: [
                    "unit": "<unit>", "atDay": "<day>",
                    "howMany": "<count>, as a number — words up to twelve are understood",
                ],
                example: "make room for two classes at Unit 3, Day 4",
                notThis: "make room for two class at Unit 3, Day 4",
                becauseNotThis: "The count and the noun disagree, so it is a sentence somebody typed "
                              + "carelessly rather than one of these shapes — and this tool renames "
                              + "pages the teacher's links point at. Guessing which half they meant is "
                              + "exactly what a fixed shape exists to avoid."
            ),
            ParsedShape(
                shape: "publish unit <number>",
                tool: "publish_pages",
                fills: ["pages": "Unit <number>"],
                example: "publish unit 5",
                notThis: "publish unit 4, day 3",
                becauseNotThis: "Publishing is the direction that reaches students, so this verb is "
                              + "read by a frame of its own that has not moved: the literal opening "
                              + "'publish unit ' and a bare number. A comma means one PAGE was named, "
                              + "and that request goes to the model — and so does every spelling the "
                              + "hide and unpublish family beside it tolerates, so 'publish unit 4?', "
                              + "'please publish unit 4' and 'publish  unit 5' are refused too, each "
                              + "pinned in hideIsUnpublish.refused. The asymmetry is the decision: "
                              + "unpublishing errs safe, a question mark on a publish request is "
                              + "plausibly a teacher ASKING, and this phrasing is answered correctly "
                              + "by the model anyway, so there is nothing to buy by widening it."
            ),
            ParsedShape(
                shape: "[please] hide|unpublish unit <number>[, day <number>] [please]",
                tool: "unpublish_pages",
                fills: ["pages": "Unit <number>, or Unit <number>, Day <number> when a day was named — "
                              + "always in these capitals, since the frame only fires on the literal "
                              + "word 'unit'. Every accepted and refused spelling is in hideIsUnpublish."],
                example: "hide unit 4, day 21",
                notThis: "hide unit 4, day 21 in ICS3U",
                becauseNotThis: "A matched card binds THIS window's course and section into the call "
                              + "unconditionally, and the guard that refuses a request naming another "
                              + "course only runs on the model's answers. So a frame that swallowed a "
                              + "sentence naming another course would act on this one and report "
                              + "success. Any extra word falls through."
            ),
            ParsedShape(
                shape: "add <count> more days to unit <number>",
                tool: "add_next_class",
                fills: ["days": "<count>, as a word up to twelve or a digit",
                        "unit": "<number>"],
                example: "add five more days to unit 4",
                notThis: "add more days to unit 4",
                becauseNotThis: "No count, so there is nothing to fill `days` with and guessing one "
                              + "would create a number of pages nobody asked for."
            ),
            ParsedShape(
                shape: "duplicate <page title> as my next class",
                tool: "add_next_class",
                fills: ["duplicate": "<page title>, with the capitals the teacher typed"],
                example: "duplicate Unit 3, Day 2 as my next class",
                notThis: "duplicate Unit 3, Day 2",
                becauseNotThis: "The closing half is what makes the sentence unambiguous. Without "
                              + "it, 'duplicate' could mean several things and belongs with the model."
            ),
            // A club's two (#267). Listed as families of their own rather than
            // by widening the two above, so the entries Windows already
            // implements are byte-for-byte what they were.
            ParsedShape(
                shape: "make room for <count> class|classes|meeting|meetings at [<word>] <number>",
                tool: "make_room_for_classes",
                fills: [
                    "unit": "<number> — the one number a numbered course's page names carry. "
                          + "Matched ONLY in a numbered course, and <word> must be that course's own "
                          + "page word (case-folded) or absent: 'at Week 5' and 'at 5' in a club whose "
                          + "pages are “Week N”. In a Unit/Day course this family matches nothing and "
                          + "the sentence goes to the model, as it did before #267",
                    "howMany": "<count>, as a number — words up to twelve are understood",
                ],
                example: "make room for one meeting at Week 5",
                notThis: "make room for one meeting at period 3",
                becauseNotThis: "'period' is not this course's page word. The first version took any "
                              + "single word, and 'at period 3', 'at block 2' and 'at section 2' were "
                              + "all planned in a club as “Week 3” or “Week 2” — renaming pages the "
                              + "teacher's links point at, from a sentence about something else. It "
                              + "goes to the model.",
                numberedPageWord: "Week"
            ),
            ParsedShape(
                shape: "duplicate <page title> as my next meeting",
                tool: "add_next_class",
                fills: ["duplicate": "<page title>, with the capitals the teacher typed"],
                example: "duplicate Week 3 as my next meeting",
                notThis: "duplicate Week 3",
                becauseNotThis: "The closing half is what makes the sentence unambiguous, exactly as "
                              + "in 'as my next class'."
            ),
            ParsedShape(
                shape: "[please] deploy [it|this section] [today|tomorrow] at <time> [today|tomorrow]",
                tool: "schedule_deploy",
                fills: [
                    "when": "<time> as HH:mm, with the day word in front of it when one was said — "
                          + "settled into a whole moment where the call is made, not here. Every "
                          + "accepted, asked and refused spelling is in deployAtATime.",
                ],
                example: "deploy at 6:30 am",
                notThis: "deploy at 6:30",
                becauseNotThis: "A one-digit hour with no am or pm is morning or evening and nobody "
                              + "can tell which. A deploy set twelve hours wrong is a site that "
                              + "updates after the class it was meant for, so nothing is scheduled: "
                              + "the app asks which, in code, naming the two sentences this family "
                              + "accepts, and the model is never sent it. Every sentence that is "
                              + "asked about rather than answered is in deployAtATime.asked."
            ),
        ]
    }

    /// One fixed shape, for anything that has to enumerate them — the
    /// contract generator does, and a tuple array cannot be handed out.
    struct FixedShape: Sendable, Equatable {

        // MARK: - Stored properties

        let phrasing: String
        let command: AssistCardCommand
    }

    /// Every shape, in the order they are matched.
    static var everyFixedShape: [FixedShape] {
        var shapes: [FixedShape] = []
        for (phrasing, command) in fixedShapes {
            shapes.append(FixedShape(phrasing: phrasing, command: command))
        }
        return shapes
    }

    /// The fixed shapes, worded exactly as the shelf offers them.
    ///
    /// Anything whose arguments depend on what the teacher said — a page
    /// title, a time — is NOT here: those need the model to read them out,
    /// and reading arguments out is the thing it does reliably.
    ///
    /// These have to be kept in step with `AssistPromptShelfView` BY HAND: a
    /// phrasing the shelf offers and this does not match is not broken, it
    /// simply goes to the model — but it goes to the model on a shape that was
    /// put here precisely because the model gets it wrong.
    private static let fixedShapes: [(String, AssistCardCommand)] = [
        // The app reaches `list_courses` too, even though the tool is MCP-only.
        // MCP-only means the local MODEL is not shown it — which is what keeps
        // routing accuracy intact — and says nothing about whether a teacher
        // can ask for it. A fixed phrasing is matched in code and never reaches
        // the model, so this costs the router nothing and still answers a
        // teacher who is looking at one section and wants to know what else is
        // in the folder.
        // The publish/deploy distinction, on demand. The local model is told
        // it in its system prompt and a teacher never was — the shelf explains
        // what the assistant can DO, not what its words mean.
        ("what does publishing mean?",
         AssistCardCommand(toolName: "explain_publishing", arguments: [:])),
        ("what is the difference between publishing and deploying?",
         AssistCardCommand(toolName: "explain_publishing", arguments: [:])),

        // A copy before a big edit. No arguments: the window is scoped to one
        // course, so the only course it could mean is that one.
        ("back up this course",
         AssistCardCommand(toolName: "back_up_course", arguments: [:])),

        ("what courses do i have?",
         AssistCardCommand(toolName: "list_courses", arguments: [:])),
        ("list my courses",
         AssistCardCommand(toolName: "list_courses", arguments: [:])),

        ("what would students see in this section right now?",
         AssistCardCommand(toolName: "check_section", arguments: [:])),

        ("what do students see right now?",
         AssistCardCommand(toolName: "check_section", arguments: [:])),

        // The shelf says "Preview" — one word, and the same word the button
        // in the section window wears, because they now do the same thing.
        // The older, longer wording is kept for a teacher who learned it.
        ("preview",
         AssistCardCommand(toolName: "rebuild_preview", arguments: [:])),

        ("rebuild the preview",
         AssistCardCommand(toolName: "rebuild_preview", arguments: [:])),

        ("undo that",
         AssistCardCommand(toolName: "undo_last_change", arguments: [:])),

        // The shelf says "Deploy now". The old, longer wording is kept as
        // well: a teacher who learned it from an earlier version and types it
        // should still be answered by the same tool.
        ("deploy now",
         AssistCardCommand(toolName: "deploy_section", arguments: [:])),

        ("deploy this section now",
         AssistCardCommand(toolName: "deploy_section", arguments: [:])),

        // The bare word, which the shelf does not offer and a teacher types
        // anyway — the button in the section window wears it, so it is the
        // word they have in front of them. On its own it means one thing and
        // there is nothing in it for the model to read out, which is the test
        // for belonging on this list. Sent to the model it came back as a
        // sentence about deploying rather than a deploy.
        ("deploy",
         AssistCardCommand(toolName: "deploy_section", arguments: [:])),

        ("publish tomorrow's class",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "tomorrow"])),
        // A club's word for the same page (#267). Every "class" phrasing a
        // club's shelf offers has its "meeting" twin here, matched in code
        // exactly like the original, so the club shelf promises nothing that
        // reaches the model.
        ("publish tomorrow's meeting",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "tomorrow"])),

        // "Publish Monday's class", and the other six. Same shape as
        // "tomorrow's class" above: the day is not read OUT of the sentence,
        // it IS the sentence, so each weekday is its own fixed phrasing with
        // the answer already written down. `AssistToolRunner.day(named:today:)`
        // turns "monday" into the next Monday, counting today when today is
        // one — the reading a person gives it while preparing.
        //
        // The model can still answer "publish the class on Monday" and phrasings
        // like it, and does so at 10/10 because every message carries the
        // date. These seven simply do not depend on that.
        ("publish monday's class",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "monday"])),
        ("publish tuesday's class",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "tuesday"])),
        ("publish wednesday's class",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "wednesday"])),
        ("publish thursday's class",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "thursday"])),
        ("publish friday's class",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "friday"])),
        ("publish saturday's class",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "saturday"])),
        ("publish sunday's class",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "sunday"])),
        ("publish monday's meeting",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "monday"])),
        ("publish tuesday's meeting",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "tuesday"])),
        ("publish wednesday's meeting",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "wednesday"])),
        ("publish thursday's meeting",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "thursday"])),
        ("publish friday's meeting",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "friday"])),
        ("publish saturday's meeting",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "saturday"])),
        ("publish sunday's meeting",
         AssistCardCommand(toolName: "publish_class_on", arguments: ["when": "sunday"])),

        // The three below arrived with the shelf being filled out to match
        // what the assistant can actually do. Each qualifies on the same test
        // as the rest of this list: one meaning, and NOTHING in the sentence
        // for the model to read out. A phrasing with an argument in it —
        // "Publish the class on Monday" — is deliberately not here; reading
        // arguments out is what the model does reliably, and it was measured
        // against the shipped surface before being offered.
        //
        // The first of them NO LONGER APPEARS ON THE SHELF, and that is on
        // purpose rather than drift. Listing a section's pages was taken off
        // as not worth a card — a teacher with Obsidian and the sidebar open
        // is not asking for a list of file names — but a teacher who types it
        // anyway deserves the reliable answer rather than a trip to the model.
        // Same reasoning as the bare word "deploy" further up: the shelf is
        // what is worth SUGGESTING, this list is what is worth MATCHING, and
        // they were never the same list.
        ("what pages are in this section?",
         AssistCardCommand(toolName: "list_pages", arguments: [:])),

        ("add the next class page",
         AssistCardCommand(toolName: "add_next_class", arguments: [:])),
        ("add the next meeting page",
         AssistCardCommand(toolName: "add_next_class", arguments: [:])),

        // The same tool, told to begin a new unit rather than carry the
        // current one on. Which unit a class belongs to is the one judgement
        // `NextClassPlanner` refuses to make on a teacher's behalf, so it is
        // asked for outright rather than guessed at from how long the unit has
        // run. `unit` is not in the tool's schema — see the note above.
        ("start a new unit for the next class",
         AssistCardCommand(toolName: "add_next_class", arguments: ["unit": "next"])),
        ("start a new unit",
         AssistCardCommand(toolName: "add_next_class", arguments: ["unit": "next"])),

        ("when are my next classes?",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when are my next classes",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when is my next class?",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when is my next class",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when are my next meetings?",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when are my next meetings",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when is my next meeting?",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when is my next meeting",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when do i teach next?",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("when do i teach next",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("what dates am i teaching?",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),
        ("what dates am i teaching",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: [:])),

        // Takes up the offer the answer above ends with. Matched in code, and
        // the `scope` key is deliberately absent from the tool's schema: the
        // model never needs to know it exists, so this adds a whole answer
        // without touching the surface routing was measured against.
        ("show me the rest of the dates",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: ["scope": "all"])),
        ("show me all the dates",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: ["scope": "all"])),

        // Replacing dates already given. The teacher is volunteering, so this
        // opens the sheet straight away rather than asking first — the
        // question "may I ask you for your dates?" has just been answered by
        // the sentence itself.
        ("i have a revised list of class dates",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: ["revise": "yes"])),
        ("i have a new list of class dates",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: ["revise": "yes"])),
        ("change my class dates",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: ["revise": "yes"])),
        // The first of these is the sentence `AssistWording.datesNotGivenYet(for:
        // .meeting)` tells a club's teacher to say, so it must match.
        ("i have a revised list of meeting dates",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: ["revise": "yes"])),
        ("i have a new list of meeting dates",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: ["revise": "yes"])),
        ("change my meeting dates",
         AssistCardCommand(toolName: "read_remembered_timetable", arguments: ["revise": "yes"])),

        // Re-dating a whole section onto the dates on file — the September
        // job. Matched in code because there is nothing in the sentence to
        // read out, and because it is far too big a change to reach through a
        // router that is right four times in five.
        ("re-date my classes",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
        ("redate my classes",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
        ("re-date my meetings",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
        ("redate my meetings",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
        ("re-date this section",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
        // A ROLLOVER, and the only one of these four that is. The other three
        // are ordinary re-dating — a snow day, a timetable that shifted — and
        // must never be asked about websites: answering "a new website" to a
        // mid-semester re-date abandons the address students are reading right
        // now. So the rollover carries the fact that it is one.
        //
        // `rollover` is deliberately absent from the tool's schema, the same
        // way `unit`, `scope` and `revise` are above: the model never needs to
        // know it exists, so this adds a whole answer without touching the
        // surface routing was measured against, and without changing the
        // argument set Windows pins as an exact departure list.
        ("roll this section over to a new year",
         AssistCardCommand(toolName: "re_date_classes", arguments: ["rollover": "yes"])),

        // The two answers to the website question, as whole sentences rather
        // than "a new website" — which is an exact match a teacher could type
        // meaning something else entirely. Each also works as a FIRST thing to
        // say, for a teacher who already knows which they want, because
        // re-dating a section that is already on its dates changes nothing.
        (AssistCardCommand.rollOverOntoANewWebsite,
         AssistCardCommand(toolName: "re_date_classes",
                           arguments: ["rollover": "yes", "website": "new"])),
        (AssistCardCommand.rollOverKeepingTheSameWebsite,
         AssistCardCommand(toolName: "re_date_classes",
                           arguments: ["rollover": "yes", "website": "same"])),
    ]
}

/// The question "deploy at 6:30" is answered with, and the two sentences that
/// answer it (issue #194).
///
/// Both sentences are ones `AssistCardCommand.matching` already accepts — the
/// "both halves or neither" rule the rollover question keeps too — and
/// `ScheduleDeployCardTests` runs every one of them through the matcher, so a
/// question can never invite a sentence the app then fails to understand.
nonisolated struct AssistTimeQuestion: Sendable, Equatable {

    // MARK: - Stored properties

    /// The time in its one spelling, "6:30" — written with a colon even
    /// when the teacher typed "6.30".
    let clock: String

    /// The sentence that means the morning: "deploy tomorrow at 6:30 am".
    let sayMorning: String

    /// The sentence that means the evening: "deploy tomorrow at 6:30 pm".
    let sayEvening: String
}
