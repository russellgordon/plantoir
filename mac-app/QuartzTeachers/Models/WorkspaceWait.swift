import Foundation

/// The words for work a launcher finds in a folder's workspace, shared by the
/// status line, the trail and the launchers' own console sentences (GitHub
/// #378).
///
/// The launchers print their sentences in bash and the app renders the status
/// line and the trail lines in Swift, so both halves are pinned against ONE
/// copy of the words: `contracts/app-rules.json` →
/// `previewPorts.whenTheWorkspaceIsInUse.sentences` (`origins`, `doing`,
/// `leftovers`, `statusLine`). A test deserialises that block and compares it
/// with these, and `scripts/test_port_blocks.py` runs the launchers' words
/// against the same block — so neither side can be retyped on its own.
///
/// None of them says "workspace": Russell, who wrote the product, did not know
/// what it meant (#378's decisions).
enum WorkspaceWords {

    // MARK: - Stored properties

    /// Who started a piece of work, by the word the launcher prints for it.
    nonisolated static let originWords: [String: String] = [
        "claude": "Revise with Claude",
        "codex": "Revise with Codex",
        "assistant": "an assistant",
        "window": "another Plantoir window",
        "scheduled": "a scheduled deploy",
        "terminal": "a command in Terminal",
        "-": "Plantoir",
    ]

    /// What a piece of work is doing, for the waiting sentences.
    nonisolated static let doingWords: [String: String] = [
        "build": "building {course} section {section}",
        "publish": "deploying {course} section {section}",
        "setup": "setting up a course",
    ]

    /// What a stopped piece of work was, for the leftover sentence and line.
    nonisolated static let leftoverWords: [String: String] = [
        "build": "a build of {course} section {section}",
        "publish": "a deploy of {course} section {section}",
        "preview": "a preview of {course} section {section}",
        "setup": "the setting up of a course",
        "other": "something else",
    ]

    /// The status line while a launcher waits (decision 3).
    nonisolated static let statusLineForWork: String = "Waiting for {origin} to finish {doing}…"
    nonisolated static let statusLineForAPreview: String = "Waiting for the preview of {course} section {section} to close…"
    nonisolated static let statusLineForSomethingElse: String = "Waiting for something else in this folder to finish…"
    nonisolated static let statusLineCounter: String = " ({seconds}s)"

    // MARK: - Functions

    /// "Revise with Claude" for "claude"; the unknown and "-" read as
    /// "Plantoir", as the launchers say it.
    nonisolated static func origin(_ word: String) -> String {
        if let words = originWords[word] {
            return words
        }
        return originWords["-"] ?? "Plantoir"
    }

    /// Splits "MPM2D/2" into its course and section; "-" and anything else
    /// without a slash has neither.
    nonisolated static func courseAndSection(of place: String) -> (course: String, section: String) {
        guard let slash = place.firstIndex(of: "/") else {
            return ("", "")
        }
        let course: String = String(place[place.startIndex..<slash])
        let section: String = String(place[place.index(after: slash)...])
        return (course, section)
    }

    /// Fills {course} and {section} in one of the templates above.
    nonisolated static func filling(_ template: String, place: String) -> String {
        let parts: (course: String, section: String) = courseAndSection(of: place)
        var filled: String = template.replacingOccurrences(of: "{course}", with: parts.course)
        filled = filled.replacingOccurrences(of: "{section}", with: parts.section)
        return filled
    }

    /// "deploying MPM2D section 2" for ("publish", "MPM2D/2").
    nonisolated static func doing(kind: String, place: String) -> String {
        let template: String = doingWords[kind] ?? doingWords["setup"] ?? ""
        return filling(template, place: place)
    }

    /// "a deploy of MPM2D section 2" for "publish:MPM2D/2", "the setting up
    /// of a course" for "setup", and "something else" for anything else.
    nonisolated static func leftover(_ item: String) -> String {
        var kind: String = item
        var place: String = ""
        if let colon = item.firstIndex(of: ":") {
            kind = String(item[item.startIndex..<colon])
            place = String(item[item.index(after: colon)...])
        }
        guard let template = leftoverWords[kind] else {
            return leftoverWords["other"] ?? "something else"
        }
        return filling(template, place: place)
    }

    /// Joins as a teacher would say it: "a, b and c".
    nonisolated static func joined(_ parts: [String]) -> String {
        var result: String = ""
        var index: Int = 0
        for part in parts {
            if index == 0 {
                result = part
            } else if index == parts.count - 1 {
                result += " and " + part
            } else {
                result += ", " + part
            }
            index += 1
        }
        return result
    }
}

/// A launcher's report of what it is waiting for before it sets a folder up
/// again (GitHub #378, decision 3), read from its `PLANTOIR_WAITING_FOR:` line.
///
/// `ScriptRunner` turns it into the line under the progress bar — "Waiting
/// for Revise with Claude to finish deploying MPM2D section 2… (59s)" — where
/// it used to say "Gathering your content… still working… (59s)" for up to ten
/// minutes. No alert, nothing to dismiss: the decision was the status line.
/// `PLANTOIR_WAITING_FOR: over` gives the line back. The line itself is
/// machinery and never reaches the console a teacher reads (any
/// `PLANTOIR_…:` line is hidden whole, `TranscriptBuilder`).
struct WorkspaceWait: Equatable {

    // MARK: - Stored properties

    /// The marker the launchers print, pinned by
    /// `scripts/test_port_blocks.py` against the launchers' own echo.
    nonisolated static let markerPrefix: String = "PLANTOIR_WAITING_FOR:"

    /// build, publish, setup, preview or work (something unnamed); "over"
    /// when the wait has ended.
    let kind: String

    /// "COURSE/SECTION", or "-" where there is none.
    let place: String

    /// Who started it, by the launcher's word ("claude", "scheduled"…).
    let origin: String

    // MARK: - Computed properties

    /// Whether this line ends the wait rather than naming one.
    nonisolated var isOver: Bool {
        return kind == "over"
    }

    /// The status line's sentence, without its counter.
    nonisolated var statusSentence: String {
        switch kind {
        case "preview":
            return WorkspaceWords.filling(WorkspaceWords.statusLineForAPreview, place: place)
        case "build", "publish", "setup":
            var sentence: String = WorkspaceWords.statusLineForWork
            sentence = sentence.replacingOccurrences(of: "{origin}", with: WorkspaceWords.origin(origin))
            sentence = sentence.replacingOccurrences(
                of: "{doing}", with: WorkspaceWords.doing(kind: kind, place: place)
            )
            return sentence
        default:
            return WorkspaceWords.statusLineForSomethingElse
        }
    }

    // MARK: - Functions

    /// The sentence with its counter, as the status line shows it.
    nonisolated static func withCounter(_ sentence: String, seconds: Int) -> String {
        return sentence + WorkspaceWords.statusLineCounter.replacingOccurrences(of: "{seconds}", with: String(seconds))
    }

    /// Every waiting line in some finished lines of output, in order. A line
    /// that does not have the marker's shape says nothing.
    nonisolated static func waits(in lines: [String]) -> [WorkspaceWait] {
        var found: [WorkspaceWait] = []
        for line in lines {
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            var words: [String] = []
            for word in line[prefixRange.upperBound...].split(separator: " ", omittingEmptySubsequences: true) {
                words.append(String(word).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if words.count == 1 && words[0] == "over" {
                found.append(WorkspaceWait(kind: "over", place: "-", origin: "-"))
                continue
            }
            guard words.count == 3 else {
                continue
            }
            let known: [String] = ["build", "publish", "setup", "preview", "work"]
            guard known.contains(words[0]) else {
                continue
            }
            found.append(WorkspaceWait(kind: words[0], place: words[1], origin: words[2]))
        }
        return found
    }
}

/// A launcher's report that it ended work left running in a folder's
/// workspace by a program that had since closed (GitHub #378, decision 2),
/// read from its `PLANTOIR_LEFTOVER_STOPPED:` line so the app can write the
/// trail line — in the same two places, for the same reason, as
/// `WorkspaceInUseReport`: `ScriptRunner` from a run it started, and
/// `ScheduledDeploy` from the log of a publish launchd ran.
///
/// The words are `contracts/shared-rules.json` → `activityTrail.mustRecord.
/// "left-over work stopped"`. Never a command line, a path or a process
/// number: the launcher prints only kinds, courses and sections.
struct LeftoverWorkReport: Equatable {

    // MARK: - Stored properties

    /// The marker the launchers print. Pinned by the contract's `marker.prefix`.
    nonisolated static let markerPrefix: String = "PLANTOIR_LEFTOVER_STOPPED:"

    /// The trail line, pinned by the contract's `line`.
    nonisolated static let line: String =
        "{place} · stopped {what}, left running in this folder after the program that started it had closed, before setting the folder up again"

    /// Where the run was for: `COURSE/SECTION`, or the word `setup`.
    let place: String

    /// Each piece of work ended: `build:ICS4U/1`, `publish:MPM2D/2`,
    /// `preview:ICS4U/1`, `setup` or `other`.
    let items: [String]

    // MARK: - Computed properties

    /// The trail line for this report.
    nonisolated var trailSentence: String {
        var parts: [String] = []
        for item in items {
            parts.append(WorkspaceWords.leftover(item))
        }
        var sentence: String = LeftoverWorkReport.line.replacingOccurrences(of: "{place}", with: place)
        sentence = sentence.replacingOccurrences(of: "{what}", with: WorkspaceWords.joined(parts))
        return sentence
    }

    // MARK: - Functions

    /// Every report in a stretch of output. A line that does not have the
    /// marker's shape — or names anything but the kinds the launcher prints —
    /// reports nothing, so a command line or a path can never reach the trail.
    nonisolated static func reports(in text: String) -> [LeftoverWorkReport] {
        var found: [LeftoverWorkReport] = []
        for textLine in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = textLine.range(of: markerPrefix) else {
                continue
            }
            var words: [String] = []
            for word in textLine[prefixRange.upperBound...].split(separator: " ", omittingEmptySubsequences: true) {
                words.append(String(word).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard words.count >= 2, isAPlace(words[0]) else {
                continue
            }
            var items: [String] = []
            var allUnderstood: Bool = true
            for word in words.dropFirst() {
                if isAnItem(word) {
                    items.append(word)
                } else {
                    allUnderstood = false
                }
            }
            if !allUnderstood || items.isEmpty {
                continue
            }
            found.append(LeftoverWorkReport(place: words[0], items: items))
        }
        return found
    }

    /// Notes every report in a stretch of output on the activity trail.
    nonisolated static func noteOnTheTrail(from text: String) {
        for report in reports(in: text) {
            ActivityTrail.note(.leftoverWorkStopped, report.trailSentence)
        }
    }

    /// `setup`, or a course and section: letters, digits and a few joining
    /// characters, one slash, and a number.
    nonisolated static func isAPlace(_ word: String) -> Bool {
        if word == "setup" {
            return true
        }
        let parts: (course: String, section: String) = WorkspaceWords.courseAndSection(of: word)
        return isACourse(parts.course) && isASection(parts.section)
    }

    nonisolated static func isAnItem(_ word: String) -> Bool {
        if word == "setup" || word == "other" {
            return true
        }
        guard let colon = word.firstIndex(of: ":") else {
            return false
        }
        let kind: String = String(word[word.startIndex..<colon])
        let place: String = String(word[word.index(after: colon)...])
        let kinds: [String] = ["build", "publish", "preview"]
        return kinds.contains(kind) && place != "setup" && isAPlace(place)
    }

    nonisolated static func isACourse(_ text: String) -> Bool {
        if text.isEmpty || text.count > 24 {
            return false
        }
        for character in text.unicodeScalars {
            let allowed: Bool = CharacterSet.alphanumerics.contains(character) || character == "-" || character == "_" || character == "."
            if !allowed {
                return false
            }
        }
        return true
    }

    nonisolated static func isASection(_ text: String) -> Bool {
        if text.isEmpty || text.count > 4 {
            return false
        }
        return Int(text) != nil
    }
}
