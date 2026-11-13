import Foundation

/// What a share of a course's unit plans did (#709), read from the shared
/// `share_plan.py`'s `PLANTOIR_PLAN_SHARED:`, `PLANTOIR_PLAN_REFUSED:` and
/// `PLANTOIR_PLAN_STOPPED:` lines so the app can write the trail's three
/// events (contracts/shared-rules.json → activityTrail.mustRecord, "unit
/// plans shared", "unit plan share refused", "unit plan sharing stopped").
///
/// **Never the address.** The marker line carries it, and the trail does not:
/// the random suffix is a line of defence, and the trail goes into problem
/// reports (review L7). Nor a username or a password, which no marker carries.
nonisolated enum PlanShareReport {

    // MARK: - Stored properties

    /// The trail's words (activityTrail.mustRecord's three entries, `line`
    /// and their parts), pinned by `PlanSharingTests`.
    static let sharedLine: String = "{course} · unit plans for {year} shared to Cloudflare Pages, {units}, {how}{keys}{flood}{old}{documents}"
    /// How many documents went and how many were held back (#833), never a
    /// file's name.
    static let documentsCounted: String = ", {n} document(s) shared and {m} held back"
    static let passwordSavedLine: String = "{course} · new password saved for the {year} unit plans{how}"
    static let passwordWaiting: String = ", not in use until they are shared again"
    static let passwordNothingShared: String = ", nothing shared yet"
    static let unitsOne: String = "1 unit"
    static let unitsSeveral: String = "{n} units"
    static let howProtected: String = "with a password"
    static let howOpen: String = "open to anyone with the link"
    static let keysLeftOut: String = ", answer keys left out"
    static let floodClosed: String = ", the plans close if flooded"
    static let floodOpen: String = ", the plans would open if flooded"
    static let oldCopyLeft: String = ", an earlier copy could not be removed"
    static let refusedLine: String = "{course} · unit plans not shared: {reason}"
    static let stoppedLine: String = "{course} · stopped sharing the {year} unit plans ({outcome})"

    /// The reason a refusal gives, by its key (unitPlanning.share.refusals).
    static let reasons: [String: String] = [
        "checkFound": "{n} thing(s) in them needed fixing first",
        "tooLarge": "a file in them was larger than Cloudflare Pages takes",
        "noPassword": "no username and password were given",
        "notProtectedYet": "the address did not yet ask for the password",
        "notAnsweringYet": "the address did not answer yet",
        "cloudflareSaidNo": "Cloudflare did not take them",
        "referenceCourse": "the course is kept for reference",
        "stillSharing": "they were already being shared",
        "notConfirmed": "the teacher chose not to share them after reading the lists of files",
        "listNotShareable": "the list of files to share named a file Plantoir cannot share",
    ]

    /// How a Stop Sharing ended, by the marker's word.
    static let outcomes: [String: String] = [
        "deleted": "deleted",
        "alreadyGone": "already gone",
        "failed": "failed, so the address still works",
        "unconfirmed": "not confirmed, so the address may still work",
    ]

    // MARK: - Functions

    /// Every trail line in a stretch of output, with the event each is for.
    /// A line that is not exactly a marker's shape reports nothing.
    static func lines(in text: String) -> [(event: ActivityTrail.Event, line: String)] {
        var found: [(event: ActivityTrail.Event, line: String)] = []
        for textLine in SiteHealthFinding.linesOf(text) {
            if let words = words(after: PlanSharing.sharedPrefix, in: textLine), let line = sharedSentence(words) {
                found.append((event: .unitPlansShared, line: line))
            } else if let words = words(after: PlanSharing.refusedPrefix, in: textLine), let line = refusedSentence(words) {
                found.append((event: .unitPlanShareRefused, line: line))
            } else if let words = words(after: PlanSharing.stoppedPrefix, in: textLine), let line = stoppedSentence(words) {
                found.append((event: .unitPlanSharingStopped, line: line))
            } else if let words = words(after: PlanSharing.passwordSavedPrefix, in: textLine),
                      let line = passwordSavedSentence(words) {
                found.append((event: .unitPlanPasswordChanged, line: line))
            }
        }
        return found
    }

    /// Notes every line in a stretch of output on the activity trail.
    static func noteOnTheTrail(from text: String) {
        for found in lines(in: text) {
            ActivityTrail.note(found.event, found.line)
        }
    }

    static func words(after prefix: String, in line: String) -> [String]? {
        guard let range = line.range(of: prefix) else {
            return nil
        }
        var words: [String] = []
        for word in line[range.upperBound...].split(separator: " ", omittingEmptySubsequences: true) {
            words.append(String(word).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return words
    }

    /// A course code as the marker writes it, "+" for its one space, read
    /// back; nil for anything that could be a path.
    static func course(_ word: String) -> String? {
        if word.isEmpty || word.count > 40 {
            return nil
        }
        for character in word.unicodeScalars {
            let fits: Bool = (CharacterSet.alphanumerics.contains(character) && character.isASCII) || character == "+"
            if !fits {
                return nil
            }
        }
        return word.replacingOccurrences(of: "+", with: " ")
    }

    static func year(_ word: String) -> Int? {
        guard word.count == 4, let year = Int(word) else {
            return nil
        }
        return year
    }

    /// `<CODE+> <year> <address> protected:<yes|no> failClosed:<yes|no>
    /// answerKeys:<in|out> units:<n> oldCopies:<n>`, and since #833
    /// `documents:<n> heldBack:<n>` after them.
    static func sharedSentence(_ words: [String]) -> String? {
        guard words.count == 8 || words.count == 10, let course = course(words[0]), let year = year(words[1]) else {
            return nil
        }
        var values: [String: String] = [:]
        for word in words[3...] {
            let parts: [Substring] = word.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                values[String(parts[0])] = String(parts[1])
            }
        }
        guard let units = Int(values["units"] ?? ""), let oldCopies = Int(values["oldCopies"] ?? "") else {
            return nil
        }
        let isProtected: Bool = values["protected"] == "yes"
        let unitWords: String = units == 1 ? unitsOne : unitsSeveral.replacingOccurrences(of: "{n}", with: String(units))
        var sentence: String = sharedLine.replacingOccurrences(of: "{course}", with: course)
        sentence = sentence.replacingOccurrences(of: "{year}", with: PlanSharing.yearLabel(year))
        sentence = sentence.replacingOccurrences(of: "{units}", with: unitWords)
        sentence = sentence.replacingOccurrences(of: "{how}", with: isProtected ? howProtected : howOpen)
        sentence = sentence.replacingOccurrences(of: "{keys}", with: values["answerKeys"] == "out" ? keysLeftOut : "")
        var flood: String = ""
        if isProtected {
            flood = values["failClosed"] == "yes" ? floodClosed : floodOpen
        }
        sentence = sentence.replacingOccurrences(of: "{flood}", with: flood)
        sentence = sentence.replacingOccurrences(of: "{old}", with: oldCopies > 0 ? oldCopyLeft : "")
        var counted: String = ""
        if let shared = Int(values["documents"] ?? ""), let heldBack = Int(values["heldBack"] ?? "") {
            counted = documentsCounted
                .replacingOccurrences(of: "{n}", with: String(shared))
                .replacingOccurrences(of: "{m}", with: String(heldBack))
        }
        return sentence.replacingOccurrences(of: "{documents}", with: counted)
    }

    /// `<CODE+> <year> <waiting|notShared>` (#833).
    static func passwordSavedSentence(_ words: [String]) -> String? {
        guard words.count == 3, let course = course(words[0]), let year = year(words[1]) else {
            return nil
        }
        var how: String
        switch words[2] {
        case "waiting":
            how = passwordWaiting
        case "notShared":
            how = passwordNothingShared
        default:
            return nil
        }
        var sentence: String = passwordSavedLine.replacingOccurrences(of: "{course}", with: course)
        sentence = sentence.replacingOccurrences(of: "{year}", with: PlanSharing.yearLabel(year))
        return sentence.replacingOccurrences(of: "{how}", with: how)
    }

    /// `<CODE+> <key> [<count>]`.
    static func refusedSentence(_ words: [String]) -> String? {
        guard words.count == 2 || words.count == 3, let course = course(words[0]) else {
            return nil
        }
        guard var reason = reasons[words[1]] else {
            return nil
        }
        if words.count == 3 {
            guard let count = Int(words[2]) else {
                return nil
            }
            reason = reason.replacingOccurrences(of: "{n}", with: String(count))
        }
        let sentence: String = refusedLine.replacingOccurrences(of: "{course}", with: course)
        return sentence.replacingOccurrences(of: "{reason}", with: reason)
    }

    /// `<CODE+> <year> <address|none> <deleted|alreadyGone|failed>`.
    static func stoppedSentence(_ words: [String]) -> String? {
        guard words.count == 4, let course = course(words[0]), let year = year(words[1]) else {
            return nil
        }
        guard let outcome = outcomes[words[3]] else {
            return nil
        }
        var sentence: String = stoppedLine.replacingOccurrences(of: "{course}", with: course)
        sentence = sentence.replacingOccurrences(of: "{year}", with: PlanSharing.yearLabel(year))
        return sentence.replacingOccurrences(of: "{outcome}", with: outcome)
    }
}
