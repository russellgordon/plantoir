import Foundation

/// A course's unit plans (#707): what the `plantoir-unit-planning` skill
/// writes into `courses/<CODE>/.internal/planning/`, as far as the app needs
/// to know about it today, which is to NAME the plans in the opening message
/// of a Revise door.
///
/// The app never writes a plan. The skill does, and each unit's folder holds
/// a small `plan.json` (`contracts/shared-rules.json` → `unitPlanning.planFile`)
/// so the app can say which units have a plan without reading an HTML page.
/// Every rule here is a contract case (`unitPlanning.planFileCases`, and
/// `app-rules.json` → `outsideAgents.greetingUnitPlansCases` for the sentence),
/// so Windows reads the same files the same way.
///
/// Reading never throws. A plan file that cannot be read, or that breaks a
/// rule, is left out and COUNTED, so the trail can say so: an opening message
/// is no place to report a broken file, and a door that refused to open over
/// one would be worse.
nonisolated enum UnitPlans {

    // MARK: - Stored properties

    /// The folder under a course, as `unitPlanning.folder` names it.
    static let folderPath: String = ".internal/planning"

    /// Each unit's facts file, `unitPlanning.planFile.name`.
    static let planFileName: String = "plan.json"

    /// `unitPlanning.slugRules.pattern`.
    static let slugPattern: String = "^[a-z][a-z0-9-]{0,39}$"

    /// `unitPlanning.neverSlugs`: folder names that are never a unit, the
    /// stylesheets' own folder first.
    static let neverSlugs: [String] = ["assets", "build", "dist", "node_modules", "out", "__pycache__"]

    /// `outsideAgents.greetingUnitPlans.unitNameMaxCharacters`.
    static let unitNameMaxCharacters: Int = 60

    /// `outsideAgents.greetingUnitPlans.mostUnitsNamed`.
    static let mostUnitsNamed: Int = 6

    /// The sentences, verbatim from `outsideAgents.greetingUnitPlans`. Since
    /// #708 `one` and `some` point at the course's Planning tab, which is
    /// there whenever a Revise door is (both need Claude Code or Codex). They
    /// are instructions to the assistant, in the teacher's voice, asking it
    /// to SAY one sentence in its first reply (plan review M3): a sentence
    /// the teacher seems to say to themselves is one the assistant was never
    /// asked to repeat.
    static let noneSentence: String =
        "In your first reply, also tell me in one sentence that you can help me plan a unit for this course, "
        + "from a calendar across my sections to a plan page with lesson cards and assessment drafts, "
        + "and that I start by asking you to plan one."

    static let oneSentence: String =
        "In your first reply, also remind me in one sentence that this course has a unit plan for {units}, "
        + "which I can see on the course's Planning tab in Plantoir, and do not describe what is in it."

    static let someSentence: String =
        "In your first reply, also remind me in one sentence that this course has unit plans for {units}, "
        + "which I can see on the course's Planning tab in Plantoir, and do not describe what is in them."

    /// `greetingUnitPlans.more`, after the last unit named.
    static let moreClause: String = ", and {n} more"

    /// The trail's clauses, `greetingUnitPlans.trail`.
    static let trailSeparator: String = " · "
    static let trailNone: String = "told about unit planning"
    static let trailOne: String = "reminded of 1 unit plan"
    static let trailSeveral: String = "reminded of {n} unit plans"
    static let trailUnreadable: String = "{n} plan.json could not be read"

    // MARK: - Functions

    /// The plans in a course folder, in the order the greeting names them,
    /// and how many plan files were left out because they could not be read
    /// or broke a rule.
    static func read(courseDirectory: URL) -> Reading {
        let fileManager: FileManager = FileManager.default
        let planning: URL = courseDirectory.appendingPathComponent(folderPath, isDirectory: true)
        var plans: [Plan] = []
        var unreadable: Int = 0
        guard let entries = try? fileManager.contentsOfDirectory(
            at: planning, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            return Reading(plans: [], unreadable: 0)
        }
        for entry in entries {
            let isFolder: Bool = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let slug: String = entry.lastPathComponent
            if !isFolder || !isUnitSlug(slug) {
                continue
            }
            let planFile: URL = entry.appendingPathComponent(planFileName)
            if !fileManager.fileExists(atPath: planFile.path) {
                continue
            }
            guard let data = try? Data(contentsOf: planFile),
                  let plan = plan(slug: slug, data: data) else {
                unreadable += 1
                continue
            }
            plans.append(plan)
        }
        return Reading(plans: sortedForTheGreeting(plans), unreadable: unreadable)
    }

    /// What a Revise door on this course should be told, or nil when it is
    /// told nothing: a course kept for reference has no door at all, so its
    /// plans are never announced. When there are more plans than the
    /// greeting names, they are put in `namedFirst` order for `today`, so the
    /// ones named are the ones that matter now (707a review M2).
    static func toMention(
        courseDirectory: URL, isKeptForReference: Bool, today: CalendarDay = CalendarDay.today()
    ) -> Reading? {
        if isKeptForReference {
            return nil
        }
        let reading: Reading = read(courseDirectory: courseDirectory)
        if reading.plans.count <= mostUnitsNamed {
            return reading
        }
        return Reading(plans: namedFirst(reading.plans, today: today), unreadable: reading.unreadable)
    }

    @MainActor
    static func toMention(for course: Course) -> Reading? {
        return toMention(courseDirectory: course.directoryURL, isKeptForReference: course.isKeptForReference)
    }

    /// Whether `plan` covers `today`: its first class is on or before
    /// today and its last class on or after, both days included. A plan
    /// with only one of its two dates is read as starting and ending on
    /// that day; a plan with neither covers no day. One rule for the
    /// greeting's order (`namedFirst`) and for the day the Planning tab
    /// starts on (`PlanningTab.startingChoice`, #803).
    static func covers(_ plan: Plan, today: CalendarDay) -> Bool {
        guard let start = plan.firstClass ?? plan.lastClass,
              let end = plan.lastClass ?? plan.firstClass else {
            return false
        }
        if today < start {
            return false
        }
        if end < today {
            return false
        }
        return true
    }

    /// The order for a course with more plans than the greeting names: the
    /// plans covering `today` first (by first class), then the upcoming ones
    /// soonest first, then the past ones most recent first, then the
    /// undated; a tie by folder name. A plan with only one of its two dates
    /// is read as starting and ending on that day.
    static func namedFirst(_ plans: [Plan], today: CalendarDay) -> [Plan] {
        var current: [Plan] = []
        var upcoming: [Plan] = []
        var past: [Plan] = []
        var undated: [Plan] = []
        for plan in plans {
            guard let start = plan.firstClass ?? plan.lastClass,
                  let end = plan.lastClass ?? plan.firstClass else {
                undated.append(plan)
                continue
            }
            if covers(plan, today: today) {
                current.append(plan)
            } else if end < today {
                past.append(plan)
            } else if today < start {
                upcoming.append(plan)
            }
        }
        var ordered: [Plan] = sortedForTheGreeting(current)
        ordered.append(contentsOf: sortedForTheGreeting(upcoming))
        past.sort { (left: Plan, right: Plan) -> Bool in
            let leftEnd: CalendarDay? = left.lastClass ?? left.firstClass
            let rightEnd: CalendarDay? = right.lastClass ?? right.firstClass
            if let leftEnd, let rightEnd, leftEnd != rightEnd {
                return rightEnd < leftEnd
            }
            return left.slug < right.slug
        }
        ordered.append(contentsOf: past)
        ordered.append(contentsOf: sortedForTheGreeting(undated))
        return ordered
    }

    /// A plan's `unit` or `title` on one line: every run of white space (a
    /// line break, a tab, several spaces) becomes one space, and the ends are
    /// trimmed, so the greeting and the trail stay one line on both
    /// platforms (707a review M1; Windows' `cmd /k` door cannot carry a line
    /// break). This is NOT a general clean of control characters: #780 does
    /// that for course names in this release, and the two should meet in one
    /// function when it lands.
    static func oneLine(_ text: String) -> String {
        var result: String = ""
        var lastWasSpace: Bool = false
        for character in text {
            if character.isWhitespace {
                if !lastWasSpace {
                    result.append(" ")
                }
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// A folder name the skill may give a unit, and the app reads as one.
    static func isUnitSlug(_ name: String) -> Bool {
        if neverSlugs.contains(name) {
            return false
        }
        return name.range(of: slugPattern, options: .regularExpression) != nil
    }

    /// One plan file read against `unitPlanning.planFile`, or nil when it
    /// breaks a rule: not a JSON object; `unit` or `title` present but not
    /// text, or both empty; a date present but not a real `yyyy-mm-dd` day;
    /// `sections` present but not a list of text. Unknown keys are ignored,
    /// so a later release can add one.
    static func plan(slug: String, data: Data) -> Plan? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let values = object as? [String: Any] else {
            return nil
        }
        guard let unit = optionalText(values["unit"]),
              let title = optionalText(values["title"]) else {
            return nil
        }
        let trimmedUnit: String = oneLine(unit)
        let trimmedTitle: String = oneLine(title)
        if trimmedUnit.isEmpty && trimmedTitle.isEmpty {
            return nil
        }
        guard let firstClass = optionalDay(values["firstClass"]),
              let lastClass = optionalDay(values["lastClass"]),
              optionalDay(values["updated"]) != nil else {
            return nil
        }
        var sections: [String] = []
        if let listed = values["sections"], !(listed is NSNull) {
            guard let items = listed as? [Any] else {
                return nil
            }
            for item in items {
                guard let section = item as? String else {
                    return nil
                }
                sections.append(section)
            }
        }
        return Plan(
            slug: slug, unit: trimmedUnit, title: trimmedTitle,
            firstClass: firstClass.day, lastClass: lastClass.day, sections: sections
        )
    }

    /// Dated plans first, by their first class; then the undated; a tie by
    /// folder name, so the order never depends on the disk's.
    static func sortedForTheGreeting(_ plans: [Plan]) -> [Plan] {
        var sorted: [Plan] = plans
        sorted.sort { (left: Plan, right: Plan) -> Bool in
            if let leftDay = left.firstClass, let rightDay = right.firstClass, leftDay != rightDay {
                return leftDay < rightDay
            }
            if left.firstClass != nil && right.firstClass == nil {
                return true
            }
            if left.firstClass == nil && right.firstClass != nil {
                return false
            }
            return left.slug < right.slug
        }
        return sorted
    }

    /// "Unit 3: Chemical Reactions", or whichever half is there, cut at
    /// `unitNameMaxCharacters` with "…" so the greeting has a bound whatever
    /// a plan is called.
    static func nameInTheGreeting(_ plan: Plan) -> String {
        var name: String = plan.title
        if !plan.unit.isEmpty && !plan.title.isEmpty {
            name = plan.unit + ": " + plan.title
        } else if !plan.unit.isEmpty {
            name = plan.unit
        }
        if name.count > unitNameMaxCharacters {
            name = String(name.prefix(unitNameMaxCharacters - 1)) + "…"
        }
        return name
    }

    /// "A", "A and B", "A, B and C"; past `mostUnitsNamed`, the first six
    /// with ", and 2 more".
    static func unitsInTheGreeting(_ plans: [Plan]) -> String {
        var names: [String] = []
        for plan in plans {
            if names.count == mostUnitsNamed {
                break
            }
            names.append(nameInTheGreeting(plan))
        }
        let left: Int = plans.count - names.count
        if left > 0 {
            return names.joined(separator: ", ")
                + moreClause.replacingOccurrences(of: "{n}", with: String(left))
        }
        if names.count <= 1 {
            return names.joined()
        }
        let allButLast: [String] = Array(names.dropLast())
        return allButLast.joined(separator: ", ") + " and " + (names.last ?? "")
    }

    /// The sentence the greeting ends with.
    static func greetingSentence(_ plans: [Plan], courseCode: String) -> String {
        if plans.isEmpty {
            return noneSentence
        }
        var sentence: String = someSentence
        if plans.count == 1 {
            sentence = oneSentence
        }
        return sentence
            .replacingOccurrences(of: "{course}", with: courseCode)
            .replacingOccurrences(of: "{units}", with: unitsInTheGreeting(plans))
    }

    /// What the "assistant opened" line gains on a Revise door: which of the
    /// two sentences was said, and how many plan files were left out.
    static func trailClause(_ reading: Reading) -> String {
        var clause: String = trailSeparator + trailNone
        if reading.plans.count == 1 {
            clause = trailSeparator + trailOne
        } else if reading.plans.count > 1 {
            clause = trailSeparator + trailSeveral.replacingOccurrences(of: "{n}", with: String(reading.plans.count))
        }
        if reading.unreadable > 0 {
            clause += trailSeparator + trailUnreadable.replacingOccurrences(of: "{n}", with: String(reading.unreadable))
        }
        return clause
    }

    /// A key that, when present and not null, must be text. Absent or null
    /// reads as empty text; anything else is nil, which breaks the rule.
    private static func optionalText(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else {
            return ""
        }
        return value as? String
    }

    /// A key that, when present and not null, must be a real day. The
    /// wrapper is nil when the rule is broken; its `day` is nil when the key
    /// is simply absent.
    private static func optionalDay(_ value: Any?) -> OptionalDay? {
        guard let value, !(value is NSNull) else {
            return OptionalDay(day: nil)
        }
        guard let text = value as? String, let day = CalendarDay(text: text), day.text == text else {
            return nil
        }
        return OptionalDay(day: day)
    }

    // MARK: - Types

    /// One unit's plan, as its `plan.json` describes it.
    struct Plan: Equatable {

        // MARK: - Stored properties

        let slug: String
        let unit: String
        let title: String
        let firstClass: CalendarDay?
        let lastClass: CalendarDay?
        let sections: [String]
    }

    /// The plans of one course, sorted, and how many files were left out.
    struct Reading: Equatable {

        // MARK: - Stored properties

        let plans: [Plan]
        let unreadable: Int
    }

    /// A date key read: present and real, or absent.
    private struct OptionalDay {

        // MARK: - Stored properties

        let day: CalendarDay?
    }
}
