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
    static func matching(_ message: String) -> AssistCardCommand? {
        let tidied: String = message.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
            .lowercased()

        for (phrasing, command) in fixedShapes {
            if tidied == phrasing {
                return command
            }
        }
        if let unit = AssistCardCommand.wholeUnit(tidied) {
            return unit
        }
        if let more = AssistCardCommand.moreDays(tidied) {
            return more
        }
        if let room = AssistCardCommand.makeRoom(tidied) {
            return room
        }
        return AssistCardCommand.duplicateClass(tidied, original: message)
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
    private static func makeRoom(_ tidied: String) -> AssistCardCommand? {
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
        for ending in [" as my next class", " as the next class", " as my next lesson"]
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

    /// "Publish Unit 5" and "Unpublish Unit 4", for any unit number.
    ///
    /// Parsed rather than listed, because unlike the seven weekdays there is
    /// no fixed set of units to write down. It is still a FIXED SHAPE in every
    /// way that matters: the whole sentence is the request, the unit number is
    /// the only thing in it, and reading an integer off the end is not a
    /// judgement anybody needs a language model for.
    ///
    /// Deliberately strict. "Publish Unit 4, Day 3" has a comma and is one
    /// page, so it is not matched here and goes to the model, which is exactly
    /// right — that request has a page title in it to read out.
    private static func wholeUnit(_ tidied: String) -> AssistCardCommand? {
        for (prefix, tool) in [("unpublish unit ", "unpublish_pages"),
                               ("publish unit ", "publish_pages")]
        where tidied.hasPrefix(prefix) {
            let rest: String = String(tidied.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty, !rest.contains(","), Int(rest) != nil else {
                return nil
            }
            return AssistCardCommand(toolName: tool, arguments: ["pages": "Unit \(rest)"])
        }
        return nil
    }

    /// A phrasing the matcher PARSES rather than compares, described so the
    /// other app can implement the same thing.
    ///
    /// The literal shapes can be listed; these cannot, because the number in
    /// them is unbounded — any unit, any count of days, any page title. A
    /// contract that carried only the literals would say the assistant
    /// understands eleven sentences when it understands those plus three
    /// families, and Windows would build eleven.
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
    }

    /// Every parsed family, for the contract.
    static var everyParsedShape: [ParsedShape] {
        return [
            ParsedShape(
                shape: "publish unit <number>",
                tool: "publish_pages",
                fills: ["pages": "Unit <number>"],
                example: "publish unit 5",
                notThis: "publish unit 4, day 3",
                becauseNotThis: "A comma means one PAGE was named, which has a title in it for the "
                              + "model to read out. Only a bare unit number is a whole unit."
            ),
            ParsedShape(
                shape: "unpublish unit <number>",
                tool: "unpublish_pages",
                fills: ["pages": "Unit <number>"],
                example: "unpublish unit 4",
                notThis: "unpublish unit 4, day 3",
                becauseNotThis: "As above: a comma names a page, not a unit."
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

        // Re-dating a whole section onto the dates on file — the September
        // job. Matched in code because there is nothing in the sentence to
        // read out, and because it is far too big a change to reach through a
        // router that is right four times in five.
        ("re-date my classes",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
        ("redate my classes",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
        ("re-date this section",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
        ("roll this section over to a new year",
         AssistCardCommand(toolName: "re_date_classes", arguments: [:])),
    ]
}
