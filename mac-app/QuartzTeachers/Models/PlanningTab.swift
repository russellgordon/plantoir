import Foundation

/// The two tabs on a course's page (#708): Settings, which is what the page
/// has always shown, and Planning, which shows the course's unit plans.
enum CourseDetailTab: Hashable {
    case settings
    case planning
}

/// The course page's Planning tab (#708), as rules a test can run without a
/// window: when the tabs are there at all, which plans the unit popup
/// offers, which one it starts on, and what a click in the plan does.
///
/// Every rule is a case in `contracts/shared-rules.json` →
/// `unitPlanning.tab` (`tabCases`, `choiceCases`, `navigationCases`), and
/// every sentence is in its `words`, pinned by `PlanningTabTests`. The views
/// (`CourseDetailView`, `PlanningTabView`, `PlanWebView`) only draw what
/// these functions answer.
nonisolated enum PlanningTab {

    /// One entry in the unit popup.
    enum Choice: Hashable {
        /// The course's list of plans, the planning folder's own `index.html`.
        case allPlans
        /// One unit's plan page, by its folder name.
        case unit(String)
    }

    // MARK: - Stored properties

    /// The page every choice opens, inside its folder.
    static let pageName: String = "index.html"

    // MARK: - Functions

    /// `tabCases`: the Settings | Planning tabs are on a course's page only
    /// while Claude Code or Codex is installed, and never on a course kept
    /// for reference. With neither installed the course page is exactly what
    /// it was before #708: no tabs, no hint (Russell, 2026-11-01: absent,
    /// never disabled).
    static func isShown(claudeIsInstalled: Bool, codexIsInstalled: Bool, courseIsKeptForReference: Bool) -> Bool {
        if courseIsKeptForReference {
            return false
        }
        return claudeIsInstalled || codexIsInstalled
    }

    /// `choiceCases` → `choices`: what the unit popup offers, in order. All
    /// Plans first when the planning folder has its own page, then each plan
    /// that has a page of its own, in the order `UnitPlans.read` gives them
    /// (dated plans by their first class, then the undated). A plan whose
    /// folder has no `index.html` is not offered, because choosing it would
    /// show nothing. An empty list is the empty tab, with its offer.
    static func choices(
        plans: [UnitPlans.Plan], coursePageExists: Bool, unitsWithAPage: Set<String>
    ) -> [Choice] {
        var result: [Choice] = []
        if coursePageExists {
            result.append(.allPlans)
        }
        for plan in plans {
            if unitsWithAPage.contains(plan.slug) {
                result.append(.unit(plan.slug))
            }
        }
        return result
    }

    /// `choiceCases` → `startsOn`: the choice the popup starts on. The plans
    /// are put in `UnitPlans.namedFirst` order for `today` (the plan covering
    /// today, then the next to start, then the last to end; the greeting's
    /// own order, so there is one ordering and not two), and the first of
    /// them is chosen when it has a date. A course whose offered plans have
    /// no dates starts on All Plans, or on its first plan when there is no
    /// All Plans. Nil only when there is nothing to offer.
    static func startingChoice(plans: [UnitPlans.Plan], choices: [Choice], today: CalendarDay) -> Choice? {
        var offered: [UnitPlans.Plan] = []
        for plan in plans {
            if choices.contains(.unit(plan.slug)) {
                offered.append(plan)
            }
        }
        let ordered: [UnitPlans.Plan] = UnitPlans.namedFirst(offered, today: today)
        if let first = ordered.first, first.firstClass != nil || first.lastClass != nil {
            return .unit(first.slug)
        }
        if choices.contains(.allPlans) {
            return .allPlans
        }
        return choices.first
    }

    /// The page a choice opens.
    static func page(for choice: Choice, planningFolder: URL) -> URL {
        switch choice {
        case .allPlans:
            return planningFolder.appendingPathComponent(pageName, isDirectory: false)
        case .unit(let slug):
            return planningFolder
                .appendingPathComponent(slug, isDirectory: true)
                .appendingPathComponent(pageName, isDirectory: false)
        }
    }

    /// The words a choice shows in the popup: All Plans, or the plan's name
    /// as the greeting says it (`UnitPlans.nameInTheGreeting`: "{unit}:
    /// {title}" on one line, cut at 60 characters).
    static func title(for choice: Choice, plans: [UnitPlans.Plan]) -> String {
        switch choice {
        case .allPlans:
            return PlanningWording.allPlans
        case .unit(let slug):
            for plan in plans {
                if plan.slug == slug {
                    return UnitPlans.nameInTheGreeting(plan)
                }
            }
            return slug
        }
    }

    /// The popup entry a page belongs to, so the popup follows a link inside
    /// the plan to another unit (708 implementation review L4): the
    /// planning folder's own `index.html` is All Plans, and any page in a
    /// unit's folder is that unit when the popup offers it. Nil for a page
    /// that is neither, and the popup then keeps what it showed.
    static func choice(forPage page: URL, planningFolder: URL, choices: [Choice]) -> Choice? {
        let pageParts: [String] = PlanNavigation.pathComponents(of: page.standardizedFileURL.path)
        let folderParts: [String] = PlanNavigation.pathComponents(of: planningFolder.standardizedFileURL.path)
        if pageParts.count <= folderParts.count {
            return nil
        }
        for index in 0..<folderParts.count {
            if pageParts[index] != folderParts[index] {
                return nil
            }
        }
        let rest: [String] = Array(pageParts[folderParts.count...])
        if rest == [pageName] {
            if choices.contains(.allPlans) {
                return .allPlans
            }
            return nil
        }
        let unit: Choice = .unit(rest[0])
        if rest.count > 1 && choices.contains(unit) {
            return unit
        }
        return nil
    }

    /// The trail's line when the tab is opened (`activityTrail.mustRecord`
    /// → "looked at a course's unit plans"): the course and how many plans
    /// it could choose from, never a plan's title or anything in it.
    static func openedTrailText(courseCode: String, choices: [Choice]) -> String {
        var units: Int = 0
        for choice in choices {
            if choice != .allPlans {
                units += 1
            }
        }
        var what: String = PlanningTrail.nothingToShow
        if units == 1 {
            what = PlanningTrail.oneUnitPlan
        } else if units > 1 {
            what = PlanningTrail.unitPlans.replacingOccurrences(of: "{n}", with: String(units))
        } else if choices.contains(.allPlans) {
            what = PlanningTrail.listOnly
        }
        return courseCode + UnitPlans.trailSeparator + PlanningTrail.opened.replacingOccurrences(of: "{what}", with: what)
    }

    /// What the planning folder holds right now, read from the disk: the
    /// plans, whether the folder has its own page, and which units have one.
    static func look(in planningFolder: URL, courseDirectory: URL) -> Look {
        let fileManager: FileManager = FileManager.default
        let reading: UnitPlans.Reading = UnitPlans.read(courseDirectory: courseDirectory)
        var unitsWithAPage: Set<String> = []
        for plan in reading.plans {
            let page: URL = PlanningTab.page(for: .unit(plan.slug), planningFolder: planningFolder)
            if fileManager.fileExists(atPath: page.path) {
                unitsWithAPage.insert(plan.slug)
            }
        }
        let coursePage: URL = PlanningTab.page(for: .allPlans, planningFolder: planningFolder)
        let found: [Choice] = choices(
            plans: reading.plans,
            coursePageExists: fileManager.fileExists(atPath: coursePage.path),
            unitsWithAPage: unitsWithAPage
        )
        return Look(plans: reading.plans, choices: found)
    }

    // MARK: - Types

    /// One reading of the planning folder.
    struct Look: Equatable {

        // MARK: - Stored properties

        let plans: [UnitPlans.Plan]
        let choices: [Choice]
    }
}

/// Where a click, a link or a page's own request may go from a plan shown
/// on the Planning tab (#708): `unitPlanning.tab.navigationCases`.
///
/// A plan is written by an outside assistant, so its pages are treated as
/// content Plantoir did not write. This rule is the first of three guards
/// (the documentation's "What stops a plan page reading other files"): a
/// page in the planning folder may open another page or file in it, a link
/// the teacher clicks to the web or to an email address opens in their own
/// browser or mail app, and everything else is refused without a word.
nonisolated enum PlanNavigation {

    /// What to do with one navigation.
    enum Decision: String {
        /// Let it load where it was going.
        case load
        /// It asked for a new window: load it in this view instead, so Back
        /// returns (a web view inside an app opens no new windows).
        case loadHere
        /// Hand it to the Mac's default browser or mail app.
        case openOutside
        /// Cancel it, silently.
        case refuse
    }

    // MARK: - Stored properties

    /// The schemes a click may hand to another app.
    static let schemesOpenedOutside: Set<String> = ["http", "https", "mailto"]

    // MARK: - Functions

    /// The decision for `url`, asked for by a click on a link when
    /// `byALinkClick`, in a new window when `isNewWindow`.
    ///
    /// Only a CLICK goes outside: a page that sends itself to the web
    /// without one (a `<meta http-equiv="refresh">`, a frame's `src`) is
    /// refused, or a plan could open the teacher's browser just by being
    /// shown.
    static func decide(url: URL, isNewWindow: Bool, byALinkClick: Bool, planningFolder: URL) -> Decision {
        let scheme: String = (url.scheme ?? "").lowercased()
        if schemesOpenedOutside.contains(scheme) {
            if byALinkClick {
                return .openOutside
            }
            return .refuse
        }
        if scheme != "file" {
            return .refuse
        }
        if !isInside(url, folder: planningFolder) {
            return .refuse
        }
        if isNewWindow {
            return .loadHere
        }
        return .load
    }

    /// Whether a `file:` address is the folder or something in it, once
    /// `..` is taken out and every link on the way is followed: a link
    /// inside the folder that points outside it is outside.
    static func isInside(_ url: URL, folder: URL) -> Bool {
        let target: [String] = pathComponents(of: resolvedPath(url.standardizedFileURL.path))
        let root: [String] = pathComponents(of: resolvedPath(folder.standardizedFileURL.path))
        if target.count < root.count {
            return false
        }
        for index in 0..<root.count {
            if target[index] != root[index] {
                return false
            }
        }
        return true
    }

    /// `path` with every link followed, as the system reads it
    /// (`realpath`, which keeps `/private`), for the part of it that exists;
    /// the rest, a file not there yet, is added back as written.
    static func resolvedPath(_ path: String) -> String {
        let fileManager: FileManager = FileManager.default
        var existing: String = path
        var missing: [String] = []
        while existing != "/" && !existing.isEmpty && !fileManager.fileExists(atPath: existing) {
            missing.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        guard let resolved = realpath(existing, nil) else {
            return path
        }
        defer {
            free(resolved)
        }
        var result: String = String(cString: resolved)
        for component in missing {
            result = (result as NSString).appendingPathComponent(component)
        }
        return result
    }

    /// A path's parts, without the empty ones a leading or doubled slash makes.
    static func pathComponents(of path: String) -> [String] {
        var parts: [String] = []
        for part in path.components(separatedBy: "/") {
            if !part.isEmpty {
                parts.append(part)
            }
        }
        return parts
    }
}

/// Plan a Unit with Claude… and Plan a Unit with Codex… on an empty Planning
/// tab (#708): the two doors Revise With ▸ opens, with an opening message of
/// their own (`contracts/app-rules.json` → `outsideAgents.planAUnit`), as
/// Fix with Claude… does for problems (#717).
nonisolated enum PlanAUnit {

    // MARK: - Stored properties

    /// `planAUnit.message`, with `{course}` and `{howITeach}` to fill. One
    /// line with no semicolon, for the reason `FixWithAssistant` gives
    /// (Windows' `cmd /k` and Windows Terminal).
    static let message: String =
        "I'm a teacher working on {course} in Plantoir, and I'd like to plan a unit with you. "
        + "Follow the plantoir-unit-planning guide, and use the plantoir tools for anything to do with this course. "
        + "Start by listing its sections so we both know what's there. "
        + "{howITeach} "
        + "After that, ask me which unit I want to plan, which sections it covers "
        + "and whether a colleague teaches it on other dates. "
        + "Do not build anything until I say go."

    /// `planAUnit.buttons`.
    static let claudeButtonTitle: String = "Plan a Unit with Claude…"
    static let codexButtonTitle: String = "Plan a Unit with Codex…"

    /// `planAUnit.trailLine`, after the course and the separator.
    static let trailLine: String = "asked {assistant} to plan a unit from the Planning tab"

    // MARK: - Functions

    /// The opening message for a course: its code, and its name in brackets
    /// when that differs, the name on one line and cut at
    /// `FixWithAssistant.courseNameMaxCharacters`; then
    /// `FixWithAssistant.replaceInTheMessage` over the whole message.
    static func openingMessage(courseCode: String, courseName: String) -> String {
        var courseNamed: String = courseCode
        var trimmedName: String = UnitPlans.oneLine(courseName)
        if trimmedName.count > FixWithAssistant.courseNameMaxCharacters {
            trimmedName = String(trimmedName.prefix(FixWithAssistant.courseNameMaxCharacters - 1)) + "…"
        }
        if !trimmedName.isEmpty && trimmedName != courseCode {
            courseNamed.append(" (\(trimmedName))")
        }
        var text: String = FixWithAssistant.fill(message, [
            "{course}": courseNamed,
            "{howITeach}": ClaudeCodeLauncher.howITeachGreetingSentence,
        ])
        for pair in FixWithAssistant.replaceInTheMessage {
            text = text.replacingOccurrences(of: pair[0], with: pair[1])
        }
        return text
    }

    /// The button's title for a door.
    static func buttonTitle(for assistant: FixWithAssistant.Assistant) -> String {
        switch assistant {
        case .claude:
            return claudeButtonTitle
        case .codex:
            return codexButtonTitle
        }
    }

    /// The trail's line for a door that opened: the course, then which
    /// assistant was asked. Nothing the teacher typed, and nothing from a plan.
    static func trailText(courseCode: String, assistant: FixWithAssistant.Assistant) -> String {
        return courseCode + UnitPlans.trailSeparator
            + FixWithAssistant.fill(trailLine, ["{assistant}": assistant.name])
    }

    /// Writes that line (`activityTrail.mustRecord` → "asked an assistant to
    /// plan a unit"), once the door has opened.
    static func noteOnTheTrail(courseCode: String, assistant: FixWithAssistant.Assistant) {
        ActivityTrail.note(.askedAnAssistantToPlanAUnit, trailText(courseCode: courseCode, assistant: assistant))
    }
}

/// The Planning tab's trail lines, verbatim from `contracts/shared-rules.json`
/// → `activityTrail.mustRecord` "looked at a course's unit plans". Written
/// once each time the tab appears, and once for each failure, so a report
/// of "the Planning tab is blank" finds something (708 implementation
/// review M1). No plan's title: it is the teacher's own words, and the count
/// says what support needs.
nonisolated enum PlanningTrail {

    // MARK: - Stored properties

    static let opened: String = "opened the Planning tab: {what}"
    static let oneUnitPlan: String = "1 unit plan to choose from"
    static let unitPlans: String = "{n} unit plans to choose from"
    static let listOnly: String = "only the list of plans"
    static let nothingToShow: String = "nothing to show yet, offered to plan a unit"
    static let couldNotShow: String =
        "the Planning tab showed nothing: Plantoir could not keep the plan's pages off the internet on this Mac"
    static let couldNotRefreshTheLook: String =
        "the Planning tab could not bring the plan's look up to date: {n} file(s) could not be copied"

    // MARK: - Functions

    static func couldNotShowText(courseCode: String) -> String {
        return courseCode + UnitPlans.trailSeparator + couldNotShow
    }

    static func couldNotRefreshTheLookText(courseCode: String, failed: Int) -> String {
        return courseCode + UnitPlans.trailSeparator
            + couldNotRefreshTheLook.replacingOccurrences(of: "{n}", with: String(failed))
    }
}

/// Every word the Planning tab shows a teacher, verbatim from
/// `contracts/shared-rules.json` → `unitPlanning.tab.words`
/// (`PlanningTabTests` pins them). Plain words only: what the teacher sees,
/// never how it is shown (rule 1).
nonisolated enum PlanningWording {

    // MARK: - Stored properties

    static let tabSettings: String = "Settings"
    static let tabPlanning: String = "Planning"
    static let allPlans: String = "All Plans"
    static let unitPopup: String = "Unit"
    static let back: String = "Back"
    static let forward: String = "Forward"
    static let reload: String = "Reload"
    static let emptyTitle: String = "No Unit Plans Yet"
    static let emptyDescription: String =
        "Plan a unit with an assistant: a calendar across your sections, lesson cards, each day's materials, "
        + "assessment drafts and a curriculum correlation. Once it is built, the plan shows here."
    static let revertOnPlanning: String = "Revert works on the Settings tab, where the changes are shown."
    static let cannotShowTitle: String = "Unit Plans Can’t Be Shown"
    static let cannotShowDescription: String =
        "Plantoir could not get ready to show unit plans on this Mac. Quitting Plantoir and opening it again may be enough."
}
