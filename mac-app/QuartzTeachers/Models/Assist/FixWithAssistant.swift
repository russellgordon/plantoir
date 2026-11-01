import Foundation

/// Fix with Claude… and Fix with Codex… on a section's Problems tab (#717,
/// part two): handing the problems a teacher ticked to an outside assistant
/// they already have, through the same two doors as Revise With ▸
/// (`ClaudeCodeLauncher`, `CodexLauncher`), with an opening message that
/// lists the problems instead of the plain greeting.
///
/// Everything a teacher or an assistant reads here is
/// `contracts/app-rules.json` → `outsideAgents.fixWith`, retyped and pinned
/// against it key by key (`FixWithAssistantTests`), and its `buttonCases` and
/// `greetingCases` are run here and owed on Windows.
///
/// **What is decided here and what is not.** Which rows go, how the message
/// is put together and how long it may be are pure functions, so a test can
/// prove them without a terminal opening. Whether a door exists is
/// `OutsideAssistantPresence` (asked at launch and when the app becomes
/// active, never while a view draws), and opening it is the door's own
/// `open(…, greeting:)`.
///
/// **The message is ONE line.** Windows hands it to `cmd /k`, which cannot
/// carry a newline, so the rows are numbered `1) …; 2) …` rather than set one
/// per line (plan review, MED 9); each row's `prompt` is already one bounded
/// line (`shared-rules.json` → `sectionProblems.prompt`).
nonisolated enum FixWithAssistant {

    /// Which door a button opens.
    enum Assistant: String, CaseIterable, Sendable {
        case claude
        case codex

        // MARK: - Computed properties

        /// The button's title (`fixWith.buttons[].title`).
        var buttonTitle: String {
            switch self {
            case .claude:
                return FixWithAssistant.claudeButtonTitle
            case .codex:
                return FixWithAssistant.codexButtonTitle
            }
        }

        /// The product's name, as the trail line says it.
        var name: String {
            switch self {
            case .claude:
                return "Claude"
            case .codex:
                return "Codex"
            }
        }
    }

    /// The rows a press would hand over, and what it leaves out.
    struct Handover: Equatable, Sendable {

        // MARK: - Stored properties

        /// Ticked, and still this section's problem, in the record's order.
        let rows: [SectionProblemRow]

        /// How many rows the teacher unticked.
        let unticked: Int

        /// How many ticked rows were left out because another section's
        /// later build shows them fixed in the source: this section needs
        /// only a build, and an assistant asked to fix them would find
        /// nothing wrong.
        let fixedInTheSource: Int

        // MARK: - Computed properties

        /// Whether the buttons can be pressed.
        var hasRows: Bool {
            return !rows.isEmpty
        }
    }

    /// The message, and how many of the handed rows it carries.
    struct Greeting: Equatable, Sendable {

        // MARK: - Stored properties

        let text: String

        /// How many rows the message names.
        let rowsNamed: Int

        /// How many handed rows it does not name ("and N more on the
        /// Problems tab"), past `mostRowsInThePrompt` or past
        /// `greetingMaxCharacters`.
        let rowsNotNamed: Int
    }

    // MARK: - Stored properties

    static let claudeButtonTitle: String = "Fix with Claude…"

    static let codexButtonTitle: String = "Fix with Codex…"

    /// The most rows one message names (`fixWith.mostRowsInThePrompt`).
    static let mostRowsInThePrompt: Int = 10

    /// The longest the whole message may be (`fixWith.greetingMaxCharacters`):
    /// under `cmd`'s 8,191-character command line with room for the rest of
    /// it — the terminal, the assistant's path, the configuration's path.
    static let greetingMaxCharacters: Int = 6500

    /// The longest a page's place may be in a row (`fixWith.pagePlaceMaxCharacters`).
    static let pagePlaceMaxCharacters: Int = 300

    /// The skill that knows each kind (`fixWith.skillForKind`); every other
    /// kind gets `otherwiseSkill`.
    static let skillForKind: [String: String] = [
        "figuresCouldNotBeDrawn": "plantoir-math-graphs",
        "geogebraSketchesNotReady": "plantoir-math-graphs",
        "swiftCouldNotBePrepared": "plantoir-runnable-code",
        "runnableCodeShownAsPlainCode": "plantoir-runnable-code",
        "quizzesNotReady": "plantoir-quizzes",
        "quizzesReadDifferently": "plantoir-quizzes",
        "printPdfNotFound": "plantoir-printing",
    ]

    static let otherwiseSkill: String = "plantoir-page-authoring"

    // The message's pieces (`fixWith.fixGreeting`), templates with the
    // contract's own `{placeholders}` so the pin compares them as written.

    static let openingOne: String =
        "I'm a teacher working on {course} in Plantoir. The last {occasion} of Section {section} found a problem on its website that I'd like your help to fix: "

    static let openingSeveral: String =
        "I'm a teacher working on {course} in Plantoir. The last {occasion} of Section {section} found problems on its website that I'd like your help to fix: "

    static let rowWithAPage: String = "{number}) {prompt} (page: {file}{shared}; skill: {skill})"

    static let rowWithoutAPage: String = "{number}) {prompt} (skill: {skill})"

    static let sharedPage: String = "; this page is shared by every section"

    static let rowSeparator: String = "; "

    static let more: String = "; and {count} more on the Problems tab"

    static let afterTheRows: String =
        ". Use the plantoir tools for anything to do with this course, and the skill named for each problem, which knows what this site can show. "

    static let planFirst: String =
        " Before changing anything, show me in plain words what you will change, using the matching plan tool where there is one, and wait for me to agree. "

    static let closing: String = "When you are done, preview Section {section} so its Problems tab clears."

    // MARK: - Functions

    /// `fixWith.buttonCases` → `shown`: the door exists on this Mac and the
    /// course is not kept for reference. Hidden, never greyed, when the
    /// assistant is not installed (`outsideAgents.hiddenWhenNotInstalled`).
    static func buttonIsShown(assistantIsInstalled: Bool, courseIsKeptForReference: Bool) -> Bool {
        return assistantIsInstalled && !courseIsKeptForReference
    }

    /// The rows a press hands over: ticked (absent means ticked, #717 ruling
    /// 6), and not fixed in the source.
    static func handover(
        record: SectionProblemsRecord,
        others: [SectionProblemsRecord],
        isTicked: (String) -> Bool
    ) -> Handover {
        return handover(
            rows: record.rows,
            isTicked: isTicked,
            stateOf: { (row: SectionProblemRow) -> SectionProblemsRules.RowState in
                return SectionProblemsRules.state(of: row, in: record, others: others)
            }
        )
    }

    /// The same, given each row's state — `fixWith.buttonCases` names the
    /// state rather than building the other sections that would make it.
    static func handover(
        rows candidates: [SectionProblemRow],
        isTicked: (String) -> Bool,
        stateOf: (SectionProblemRow) -> SectionProblemsRules.RowState
    ) -> Handover {
        var rows: [SectionProblemRow] = []
        var unticked: Int = 0
        var fixedInTheSource: Int = 0
        for row in candidates {
            if !isTicked(row.id) {
                unticked += 1
                continue
            }
            if stateOf(row) == .fixedInTheSource {
                fixedInTheSource += 1
                continue
            }
            rows.append(row)
        }
        return Handover(rows: rows, unticked: unticked, fixedInTheSource: fixedInTheSource)
    }

    /// The skill named for a kind.
    static func skill(forKind kind: String) -> String {
        return skillForKind[kind] ?? otherwiseSkill
    }

    /// Whether a page is the course's own rather than one section's: a
    /// section's pages live under `section<N>/`.
    static func isSharedByEverySection(_ page: String) -> Bool {
        if page.isEmpty {
            return false
        }
        guard page.hasPrefix("section") else {
            return true
        }
        var sawADigit: Bool = false
        for character in page.dropFirst("section".count) {
            if character == "/" {
                return !sawADigit
            }
            if character.isASCII && character.isNumber {
                sawADigit = true
                continue
            }
            return true
        }
        return true
    }

    /// Where a page is, from the working folder the session opens in.
    static func file(ofPage page: String, courseCode: String) -> String {
        var place: String = page
        if place.count > pagePlaceMaxCharacters {
            place = String(place.prefix(pagePlaceMaxCharacters - 1)) + "…"
        }
        return "courses/\(courseCode)/\(place).md"
    }

    /// One numbered row.
    static func rowText(_ row: SectionProblemRow, number: Int, courseCode: String) -> String {
        var prompt: String = row.prompt
        if prompt.isEmpty {
            prompt = row.item.isEmpty ? row.sentence : row.item
        }
        if row.page.isEmpty {
            return fill(rowWithoutAPage, [
                "{number}": String(number),
                "{prompt}": prompt,
                "{skill}": skill(forKind: row.kind),
            ])
        }
        return fill(rowWithAPage, [
            "{number}": String(number),
            "{prompt}": prompt,
            "{file}": file(ofPage: row.page, courseCode: courseCode),
            "{shared}": isSharedByEverySection(row.page) ? sharedPage : "",
            "{skill}": skill(forKind: row.kind),
        ])
    }

    /// The opening message for `rows`, or nil when there are none — a
    /// session asked to fix nothing is not one the buttons ever open.
    ///
    /// Rows are named in order until `mostRowsInThePrompt` are, or until the
    /// next would take the message past `greetingMaxCharacters`; the rest are
    /// "and N more on the Problems tab". The first row is always named.
    static func greeting(
        rows: [SectionProblemRow],
        courseCode: String,
        courseName: String,
        sectionNumber: Int,
        occasion: String
    ) -> Greeting? {
        if rows.isEmpty {
            return nil
        }
        var courseNamed: String = courseCode
        let trimmedName: String = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != courseCode {
            courseNamed.append(" (\(trimmedName))")
        }
        let occasionWord: String = occasion == "deploy" ? "deploy" : "preview"
        let section: String = String(sectionNumber)
        let opening: String = fill(rows.count == 1 ? openingOne : openingSeveral, [
            "{course}": courseNamed,
            "{occasion}": occasionWord,
            "{section}": section,
        ])
        let ending: String = afterTheRows
            + ClaudeCodeLauncher.howITeachGreetingSentence
            + planFirst
            + fill(closing, ["{section}": section])

        var named: [String] = []
        var length: Int = opening.count + ending.count
        for row in rows {
            if named.count == mostRowsInThePrompt {
                break
            }
            let text: String = rowText(row, number: named.count + 1, courseCode: courseCode)
            let separatorLength: Int = named.isEmpty ? 0 : rowSeparator.count
            // Room for "; and N more on the Problems tab" whenever a row
            // would still be left over after this one.
            let remainingAfterThis: Int = rows.count - named.count - 1
            var moreLength: Int = 0
            if remainingAfterThis > 0 {
                moreLength = fill(more, ["{count}": String(remainingAfterThis)]).count
            }
            if !named.isEmpty && length + separatorLength + text.count + moreLength > greetingMaxCharacters {
                break
            }
            named.append(text)
            length += separatorLength + text.count
        }

        var message: String = opening + named.joined(separator: rowSeparator)
        let notNamed: Int = rows.count - named.count
        if notNamed > 0 {
            message.append(fill(more, ["{count}": String(notNamed)]))
        }
        message.append(ending)
        // `outsideAgents.greetingCarriesNoDoubleQuotes`: the message is one
        // shell argument on the mac and one quoted `cmd` argument on Windows.
        message = message.replacingOccurrences(of: "\"", with: "'")
        return Greeting(text: message, rowsNamed: named.count, rowsNotNamed: notNamed)
    }

    /// The trail's line (`activityTrail.mustRecord` → "asked an assistant to
    /// fix problems"): which assistant, how many rows went and of what
    /// kinds, and how many did not — never a page, which is the teacher's
    /// own name.
    static func trailLine(assistant: Assistant, handover: Handover, greeting: Greeting) -> String {
        var kinds: [String] = []
        for row in handover.rows {
            if !kinds.contains(row.kind) {
                kinds.append(row.kind)
            }
        }
        let count: Int = handover.rows.count
        let problems: String = count == 1 ? "1 problem" : "\(count) problems"
        return "asked \(assistant.name) to fix \(problems) (\(kinds.joined(separator: ", "))); "
            + "named in the message: \(greeting.rowsNamed); left out: \(handover.unticked) unticked, "
            + "\(handover.fixedInTheSource) fixed in the source"
    }

    /// Writes that line, for a door that opened.
    static func noteOnTheTrail(
        assistant: Assistant,
        handover: Handover,
        greeting: Greeting,
        courseCode: String,
        sectionNumber: Int
    ) {
        ActivityTrail.note(
            .askedAnAssistantToFixProblems,
            trailLine(assistant: assistant, handover: handover, greeting: greeting),
            course: courseCode,
            section: sectionNumber
        )
    }

    /// Each `{key}` in `template` replaced by its value, in ONE pass over the
    /// template: a value is never searched again, so a row whose own words
    /// carry `{section}` or `{skill}` (TeX has braces everywhere) is handed
    /// over exactly as the build wrote it.
    static func fill(_ template: String, _ values: [String: String]) -> String {
        var text: String = ""
        var rest: Substring = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            text.append(contentsOf: rest[rest.startIndex..<open])
            guard let close = rest[open...].firstIndex(of: "}") else {
                text.append(contentsOf: rest[open...])
                return text
            }
            let key: String = String(rest[open...close])
            if let value = values[key] {
                text.append(value)
            } else {
                text.append(key)
            }
            rest = rest[rest.index(after: close)...]
        }
        text.append(contentsOf: rest)
        return text
    }
}
