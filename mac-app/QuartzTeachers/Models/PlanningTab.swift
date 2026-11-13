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

    /// `choiceCases` → `startsOn`: the choice the popup starts on (#803).
    /// The offered plan covering `today` (`UnitPlans.covers`, both ends
    /// included), the earliest first class when two do; otherwise All
    /// Plans, the list of every unit, because a teacher between units, before
    /// the first or after the last is better served by the list than by a
    /// guess at which unit they meant (#708 started on the next unit to
    /// begin). With no All Plans page, the plans in `UnitPlans.namedFirst`
    /// order for `today` (the greeting's own order, so there is one ordering
    /// and not two) and the first of them. Nil only when there is nothing to
    /// offer.
    static func startingChoice(plans: [UnitPlans.Plan], choices: [Choice], today: CalendarDay) -> Choice? {
        var offered: [UnitPlans.Plan] = []
        for plan in plans {
            if choices.contains(.unit(plan.slug)) {
                offered.append(plan)
            }
        }
        let ordered: [UnitPlans.Plan] = UnitPlans.namedFirst(offered, today: today)
        if let first = ordered.first, UnitPlans.covers(first, today: today) {
            return .unit(first.slug)
        }
        if choices.contains(.allPlans) {
            return .allPlans
        }
        if let first = ordered.first {
            return .unit(first.slug)
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
        /// Cancel it and hand it to the app itself: a click on a code in the
        /// Coverage tab's map (#793, `CoverageNavigation`). A plan never
        /// gets this answer.
        case handToTheApp
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

/// Open in Browser on the Planning tab (#803): the page the plan is showing,
/// opened in the teacher's default web browser from its `file:` address, so a
/// plan can be read, printed or kept open with Plantoir closed. The planning
/// folder is hidden in Finder, so this button is how a teacher reaches it.
///
/// `contracts/shared-rules.json` → `unitPlanning.tab.openInBrowser`: which
/// page is opened (`pageToOpen`), what kind of page the trail calls it
/// (`kind`), and the words, pinned by `PlanningTabTests`. Only a file inside
/// the course's planning folder is ever handed to the browser; anything else
/// is refused here, before the browser is asked.
nonisolated enum PlanInTheBrowser {

    /// Which kind of page was opened, for the trail: never its name or
    /// anything written on it.
    enum Kind: String {
        /// The planning folder's own `index.html`, All Plans.
        case allPlans
        /// A unit's plan page, `<unit>/index.html`.
        case plan
        /// A unit's curriculum correlation page, `<unit>/correlation.html`.
        case correlation
        /// Anything else in the planning folder: a PDF, a picture.
        case file
    }

    /// Why nothing can be opened.
    enum Refusal: String {
        /// No page is showing and none is chosen, or the address is a
        /// folder rather than a page.
        case nothingToOpen
        /// The address is not a file inside the course's planning folder.
        case outsideThePlan
        /// The page was inside the planning folder and is not there now.
        case pageIsGone
    }

    /// What the button would open, or why it cannot.
    struct Answer: Equatable {

        // MARK: - Stored properties

        let page: URL?
        let refusal: Refusal?
    }

    // MARK: - Stored properties

    /// A unit's correlation page, beside its plan.
    static let correlationPageName: String = "correlation.html"

    /// `words.openInBrowser` and its help and refusal sentences.
    static let buttonTitle: String = "Open in Browser"
    static let help: String = "Open this page in your web browser"
    static let nothingToOpen: String = "There is no page to open in your browser yet."
    static let outsideThePlan: String = "Only a page from this course’s unit plans can be opened in your browser."
    static let pageIsGone: String = "This page is no longer in the course’s unit plans. Reload to see what is there now."
    static let couldNotOpenTitle: String = "Can’t Open in Your Browser"
    static let couldNotOpen: String = "Your Mac could not open this page in your web browser."

    /// `activityTrail.mustRecord` → "opened a unit plan in the browser".
    static let trailLine: String = "opened {what} in the browser"
    static let couldNotOpenTrailLine: String = "could not open {what} in the browser"
    static let allPlansWhat: String = "the list of plans"
    static let planWhat: String = "a unit's plan"
    static let correlationWhat: String = "a unit's correlation page"
    static let fileWhat: String = "a file from a unit's plan"

    // MARK: - Functions

    /// `openInBrowser.cases`: the page the web view is ON (`onScreen`,
    /// which follows a link the teacher clicked inside the plan), or, before
    /// the first page has loaded, the page chosen in the popup. Opened only
    /// when it is a `file:` address inside `planningFolder` once `..` and
    /// every link on the way are followed (`PlanNavigation.isInside`), and
    /// a file that is there. Its `#` part is kept, so a correlation page
    /// opens where the plan was.
    static func pageToOpen(onScreen: URL?, chosen: URL?, planningFolder: URL) -> Answer {
        guard let candidate = onScreen ?? chosen else {
            return Answer(page: nil, refusal: .nothingToOpen)
        }
        if !candidate.isFileURL {
            return Answer(page: nil, refusal: .outsideThePlan)
        }
        if !PlanNavigation.isInside(candidate, folder: planningFolder) {
            return Answer(page: nil, refusal: .outsideThePlan)
        }
        let resolved: String = PlanNavigation.resolvedPath(candidate.standardizedFileURL.path)
        var isFolder: ObjCBool = false
        if !FileManager.default.fileExists(atPath: resolved, isDirectory: &isFolder) {
            return Answer(page: nil, refusal: .pageIsGone)
        }
        if isFolder.boolValue {
            return Answer(page: nil, refusal: .nothingToOpen)
        }
        return Answer(page: candidate, refusal: nil)
    }

    /// The kind of page `page` is, by where it sits in the planning folder.
    static func kind(of page: URL, planningFolder: URL) -> Kind {
        let pageParts: [String] = PlanNavigation.pathComponents(
            of: PlanNavigation.resolvedPath(page.standardizedFileURL.path)
        )
        let folderParts: [String] = PlanNavigation.pathComponents(
            of: PlanNavigation.resolvedPath(planningFolder.standardizedFileURL.path)
        )
        if pageParts.count <= folderParts.count {
            return .file
        }
        let rest: [String] = Array(pageParts[folderParts.count...])
        if rest == [PlanningTab.pageName] {
            return .allPlans
        }
        if rest.count == 2 && rest[1] == PlanningTab.pageName {
            return .plan
        }
        if rest.count == 2 && rest[1] == correlationPageName {
            return .correlation
        }
        return .file
    }

    /// The button's help: what it does, or why it is dimmed.
    static func helpText(for answer: Answer) -> String {
        guard let refusal = answer.refusal else {
            return help
        }
        return sentence(for: refusal)
    }

    /// The sentence a teacher reads for a refusal.
    static func sentence(for refusal: Refusal) -> String {
        switch refusal {
        case .nothingToOpen:
            return nothingToOpen
        case .outsideThePlan:
            return outsideThePlan
        case .pageIsGone:
            return pageIsGone
        }
    }

    /// The trail's words for a kind of page.
    static func what(_ kind: Kind) -> String {
        switch kind {
        case .allPlans:
            return allPlansWhat
        case .plan:
            return planWhat
        case .correlation:
            return correlationWhat
        case .file:
            return fileWhat
        }
    }

    /// The trail's line once the browser has the page: the course and the
    /// kind of page, never its name or anything on it.
    static func trailText(courseCode: String, kind: Kind) -> String {
        return courseCode + UnitPlans.trailSeparator + trailLine.replacingOccurrences(of: "{what}", with: what(kind))
    }

    /// The trail's line when the Mac could not open it.
    static func couldNotOpenTrailText(courseCode: String, kind: Kind) -> String {
        return courseCode + UnitPlans.trailSeparator
            + couldNotOpenTrailLine.replacingOccurrences(of: "{what}", with: what(kind))
    }
}

/// Acting on Open in Browser: the rule first, then the browser, then the
/// trail. `opener` is the Mac's default browser in the app
/// (`PlanBrowserOpener.openInTheDefaultBrowser`); a test hands in one that
/// records what it was given, so a refused page is proved never to reach it.
extension PlanInTheBrowser {

    // MARK: - Functions

    /// Opens what `pageToOpen` allows, and once the browser has answered
    /// writes the trail line and calls `finished` with whether it opened.
    /// Returns the answer, so a refusal can be shown at once.
    @MainActor
    @discardableResult
    static func open(
        onScreen: URL?,
        chosen: URL?,
        planningFolder: URL,
        courseCode: String,
        opener: @MainActor (URL, @escaping @MainActor (Bool) -> Void) -> Void,
        finished: @escaping @MainActor (Bool) -> Void
    ) -> Answer {
        let answer: Answer = pageToOpen(onScreen: onScreen, chosen: chosen, planningFolder: planningFolder)
        guard let page = answer.page else {
            return answer
        }
        let pageKind: Kind = kind(of: page, planningFolder: planningFolder)
        opener(page) { (opened: Bool) in
            if opened {
                ActivityTrail.note(.openedAUnitPlanInTheBrowser, trailText(courseCode: courseCode, kind: pageKind))
            } else {
                ActivityTrail.note(
                    .openedAUnitPlanInTheBrowser, couldNotOpenTrailText(courseCode: courseCode, kind: pageKind)
                )
            }
            finished(opened)
        }
        return answer
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
