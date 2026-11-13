import Foundation

/// The tabs on a section's page: Website always, Coverage while the course
/// has curriculum expectations (#793), Problems while the last build found
/// something (#717). `contracts/shared-rules.json` → `coverageTab.tabCases`.
nonisolated enum SectionTab: String, Hashable, Sendable {
    case website
    case coverage
    case problems
}

/// Which of a section's tabs are in the bar, and which one shows
/// (`coverageTab.tabCases`). The views only draw what these answer.
nonisolated enum SectionTabs {

    // MARK: - Functions

    /// The tabs in the bar, in order: Website, then Coverage, then Problems.
    /// The tab that comes and goes most is last, so Coverage never moves
    /// under the teacher's pointer. Empty when Website would be the only
    /// one: a section with neither shows what it always has, with no bar.
    ///
    /// Coverage is there when the course has a curriculum folder holding an
    /// expectation page (the build's own rule, `CurriculumFolderRule`), or
    /// when the section's last map names at least one map (which catches a
    /// curriculum folder the course root does not show). It is there
    /// whatever the section's WEBSITE says about its own coverage map
    /// (Russell, 2026-11-12: that setting decides what students see).
    static func shown(hasCurriculum: Bool, recordHasMaps: Bool, hasProblems: Bool) -> [SectionTab] {
        var tabs: [SectionTab] = [.website]
        if hasCurriculum || recordHasMaps {
            tabs.append(.coverage)
        }
        if hasProblems {
            tabs.append(.problems)
        }
        if tabs.count == 1 {
            return []
        }
        return tabs
    }

    /// The tab that shows: the one chosen while it is in the bar, otherwise
    /// Website, never a neighbour, so the teacher is never moved somewhere
    /// they did not choose.
    static func showing(chosen: SectionTab, shown: [SectionTab]) -> SectionTab {
        if shown.contains(chosen) {
            return chosen
        }
        return .website
    }

    /// Whether the section's preview takes the browser commands (Back,
    /// Forward, Reload Page) and the keyboard: only while Website shows,
    /// because only then is it in the window at all (the plan review's H1).
    static func previewTakesCommands(showing: SectionTab) -> Bool {
        return showing == .website
    }

    /// Whether the section's alerts and sheets that a build can raise (the
    /// Problems alert, the links checklist, a preview's refusal) wait: while
    /// the Coverage tab shows, nothing pops up over it (Russell's ruling,
    /// 2026-11-12). They are raised when the teacher next shows Website or
    /// Problems.
    static func alertsWait(showing: SectionTab) -> Bool {
        return showing == .coverage
    }

    /// Whether a preview's refusal belongs to the Coverage tab's own refresh,
    /// and so is said in the tab rather than as an alert: only while that
    /// refresh is starting or waiting for its map. A refusal of the teacher's
    /// own Preview press is never taken, whichever tab shows (the 793b
    /// review's M2): the press is the teacher's act, and so is its answer.
    ///
    /// Only while the tab's OWN start runs (`ownStartRunning`, set around
    /// the synchronous start in `SectionCoverage.makeAgain`): every refusal
    /// of that start is synchronous. A refusal while the press is still
    /// starting, or while its build runs, is somebody else's press, in this
    /// window or another, and is delivered to them (the fix review's M1, M2).
    static func refusalIsTheTabs(refresh: CoverageRefresh, ownStartRunning: Bool) -> Bool {
        return ownStartRunning && refresh == .pending
    }
}

/// `about.json`, the record of the map a section's Coverage tab shows
/// (`contracts/file-formats.json` → `coverageTabMap`), as far as the app
/// needs it. Written by the shared Python on every build; read here as
/// content this app did not write (793b-must-do, item 1).
nonisolated struct CoverageTabRecord: Equatable, Sendable {

    /// One map on the page, in the page's order.
    struct Map: Equatable, Sendable {

        // MARK: - Stored properties

        let title: String
        let folder: String
        let expectations: Int
        let notYetAddressed: Int

        /// Each code whose page the build could name → that page, a POSIX
        /// path below the course folder with its `.md`, taken literally.
        let pages: [String: String]
    }

    // MARK: - Stored properties

    /// The only version this app reads; any other is no map.
    static let version: Int = 1

    let buildId: String?

    /// When the build that made the map STARTED, in nanoseconds since 1970;
    /// nil when it could not be noted, and then the map is always said to
    /// be possibly out of date.
    let startedNs: Int64?

    /// The page's file name in the folder, or nil when there is no map.
    let page: String?

    let siteMapSwitchedOn: Bool
    let hiddenPagesCounted: Int
    let maps: [Map]

    // MARK: - Computed properties

    /// `startedNs` as a moment.
    var startedAt: Date? {
        guard let startedNs else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(startedNs) / 1_000_000_000)
    }

    // MARK: - Functions

    /// The record in `data` when it is version 1 and readable, else nil.
    static func parse(_ data: Data) -> CoverageTabRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if !CoverageTabRecord.isTheVersionNumber(object["version"], CoverageTabRecord.version) {
            return nil
        }
        var startedNs: Int64? = nil
        if let number = object["startedNs"] as? NSNumber {
            startedNs = number.int64Value
        }
        var maps: [Map] = []
        if let mapObjects = object["maps"] as? [[String: Any]] {
            for mapObject in mapObjects {
                var pages: [String: String] = [:]
                if let pageObjects = mapObject["pages"] as? [String: Any] {
                    for (code, value) in pageObjects {
                        if let path = value as? String {
                            pages[code] = path
                        }
                    }
                }
                maps.append(Map(
                    title: (mapObject["title"] as? String) ?? "",
                    folder: (mapObject["folder"] as? String) ?? "",
                    expectations: (mapObject["expectations"] as? Int) ?? 0,
                    notYetAddressed: (mapObject["notYetAddressed"] as? Int) ?? 0,
                    pages: pages
                ))
            }
        }
        return CoverageTabRecord(
            buildId: object["buildId"] as? String,
            startedNs: startedNs,
            page: object["page"] as? String,
            siteMapSwitchedOn: (object["siteMapSwitchedOn"] as? Bool) ?? true,
            hiddenPagesCounted: (object["hiddenPagesCounted"] as? Int) ?? 0,
            maps: maps
        )
    }

    /// Whether `version` in `data` is there and is not this app's: the map
    /// was made by another version of Plantoir.
    static func isAnotherVersion(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard let number = object["version"] as? NSNumber, !CoverageTabRecord.isABoolean(number) else {
            return false
        }
        return number.intValue != CoverageTabRecord.version
    }

    /// Whether `value` is the JSON NUMBER `wanted`: `true` bridges to an
    /// `NSNumber` that reads as 1, and is not version 1 (the 793b review's
    /// LOW 6).
    static func isTheVersionNumber(_ value: Any?, _ wanted: Int) -> Bool {
        guard let number = value as? NSNumber, !CoverageTabRecord.isABoolean(number) else {
            return false
        }
        return number.intValue == wanted && number.doubleValue == Double(wanted)
    }

    /// Whether an `NSNumber` from `JSONSerialization` was a JSON boolean.
    static func isABoolean(_ number: NSNumber) -> Bool {
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}

/// What a section's `.coverage-tab` folder holds, read from `about.json` and
/// the page it names alone, never from the HTML.
nonisolated enum CoverageTab {

    /// `coverageTab.mapOfThisBuild`'s three answers.
    enum MapState: String, Sendable {
        case none
        case thisBuild
        case anotherBuild
    }

    /// What the tab has to show: why there is no map, or the map and whose
    /// it is. `noRecord`, `otherVersion` and `noMaps` are all `mapOfThisBuild`
    /// → `none`; the tab says each in its own words.
    enum RecordKind: String, Sendable {
        case noRecord
        case otherVersion
        case noMaps
        case thisBuild
        case anotherBuild
    }

    /// One reading of the folder.
    struct Reading: Equatable, Sendable {

        // MARK: - Stored properties

        let kind: RecordKind

        /// The record, when it is one this app reads (`noMaps`, `thisBuild`,
        /// `anotherBuild`).
        let record: CoverageTabRecord?

        /// The page to show, when there is one.
        let page: URL?

        /// The folder the page may read, and nothing outside it.
        let folder: URL

        // MARK: - Computed properties

        var mapState: MapState {
            switch kind {
            case .thisBuild:
                return .thisBuild
            case .anotherBuild:
                return .anotherBuild
            case .noRecord, .otherVersion, .noMaps:
                return .none
            }
        }

        /// Whether the record names a map at all.
        var hasMaps: Bool {
            guard let record else {
                return false
            }
            return !record.maps.isEmpty && (kind == .thisBuild || kind == .anotherBuild)
        }
    }

    // MARK: - Stored properties

    static let folderName: String = ".coverage-tab"
    static let recordName: String = "about.json"
    static let buildIdName: String = ".build-id"

    // MARK: - Functions

    /// A section's built output, reached through the course's `.merged_output`
    /// link, where `.problems.json` and `.page-sources.json` are read from.
    static func sectionOutput(courseFolder: URL, sectionNumber: Int) -> URL {
        return courseFolder
            .appendingPathComponent(BuildOutputLocation.linkName, isDirectory: true)
            .appendingPathComponent("section\(sectionNumber)", isDirectory: true)
    }

    static func folder(courseFolder: URL, sectionNumber: Int) -> URL {
        return sectionOutput(courseFolder: courseFolder, sectionNumber: sectionNumber)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// The id in the section's `.build-id`: the build that started last.
    /// Nil when it cannot be read or is empty.
    static func sectionBuildId(courseFolder: URL, sectionNumber: Int) -> String? {
        let url: URL = sectionOutput(courseFolder: courseFolder, sectionNumber: sectionNumber)
            .appendingPathComponent(buildIdName, isDirectory: false)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        return trimmed
    }

    /// The page name a record may name: a plain file name in the folder.
    static func isAPlainFileName(_ name: String) -> Bool {
        if name.isEmpty || name == "." || name == ".." {
            return false
        }
        if name.contains("/") || name.contains("\\") || name.contains("\u{0}") {
            return false
        }
        return true
    }

    /// Reads `folder` against `buildId`, the section's `.build-id`. Build ids
    /// are compared for equality only, never ordered (`mapOfThisBuild`).
    static func read(folder: URL, buildId: String?) -> Reading {
        let recordURL: URL = folder.appendingPathComponent(recordName, isDirectory: false)
        guard let data = try? Data(contentsOf: recordURL) else {
            return Reading(kind: .noRecord, record: nil, page: nil, folder: folder)
        }
        guard let record = CoverageTabRecord.parse(data) else {
            if CoverageTabRecord.isAnotherVersion(data) {
                return Reading(kind: .otherVersion, record: nil, page: nil, folder: folder)
            }
            return Reading(kind: .noRecord, record: nil, page: nil, folder: folder)
        }
        guard let name = record.page else {
            return Reading(kind: .noMaps, record: record, page: nil, folder: folder)
        }
        if !isAPlainFileName(name) {
            return Reading(kind: .noRecord, record: nil, page: nil, folder: folder)
        }
        let page: URL = folder.appendingPathComponent(name, isDirectory: false)
        var isFolder: ObjCBool = false
        if !FileManager.default.fileExists(atPath: page.path, isDirectory: &isFolder) || isFolder.boolValue {
            return Reading(kind: .noRecord, record: nil, page: nil, folder: folder)
        }
        if let buildId, let recorded = record.buildId, recorded == buildId {
            return Reading(kind: .thisBuild, record: record, page: page, folder: folder)
        }
        return Reading(kind: .anotherBuild, record: record, page: page, folder: folder)
    }

    /// `coverageTab.mapOfThisBuild`, as the Python's
    /// `coverage_tab_map_state` answers it.
    static func mapState(folder: URL, buildId: String?) -> MapState {
        return read(folder: folder, buildId: buildId).mapState
    }
}

/// A click on a code in the map: `plantoir-coverage:open/<buildId>/<map>/<code>`
/// (`coverageTab.link`), read exactly (793b-must-do, item 3).
nonisolated struct CoverageLink: Equatable, Sendable {

    // MARK: - Stored properties

    static let scheme: String = "plantoir-coverage"

    let buildId: String
    let map: Int
    let code: String

    // MARK: - Functions

    /// The link in `url`, or nil unless it is exactly four parts, `open`
    /// first, each percent-decoded ONCE: a build id of letters, digits and
    /// hyphens, a map's place of digits alone, and a code of letters,
    /// digits, dots and hyphens (every code the build links: specific and
    /// overall expectations, College Board skills and objectives). A query,
    /// a fragment or a fifth part is not a link.
    static func parse(_ url: URL) -> CoverageLink? {
        if (url.scheme ?? "").lowercased() != scheme {
            return nil
        }
        let text: String = url.absoluteString
        guard let colon = text.firstIndex(of: ":") else {
            return nil
        }
        let rest: String = String(text[text.index(after: colon)...])
        let parts: [String] = rest.components(separatedBy: "/")
        if parts.count != 4 || parts[0] != "open" {
            return nil
        }
        guard let buildId = parts[1].removingPercentEncoding,
              let code = parts[3].removingPercentEncoding else {
            return nil
        }
        if !CoverageLink.isMadeOf(buildId, extra: "-") || !CoverageLink.isMadeOf(code, extra: ".-") {
            return nil
        }
        let place: String = parts[2]
        if place.isEmpty || place.count > 6 || !CoverageLink.isMadeOf(place, extra: "", lettersAllowed: false) {
            return nil
        }
        guard let map = Int(place) else {
            return nil
        }
        return CoverageLink(buildId: buildId, map: map, code: code)
    }

    /// Whether `text` is not empty and every character is an ASCII digit,
    /// an ASCII letter when `lettersAllowed`, or one of `extra`.
    static func isMadeOf(_ text: String, extra: String, lettersAllowed: Bool = true) -> Bool {
        if text.isEmpty {
            return false
        }
        for character in text.unicodeScalars {
            let value: UInt32 = character.value
            let isDigit: Bool = value >= 48 && value <= 57
            let isLetter: Bool = (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
            if isDigit {
                continue
            }
            if lettersAllowed && isLetter {
                continue
            }
            if extra.unicodeScalars.contains(character) {
                continue
            }
            return false
        }
        return true
    }
}

/// Where a click, a link or a page's own request may go from the map on the
/// Coverage tab (#793): `coverageTab.navigationCases`. The map is written by
/// the build, from course content, so it is treated as content Plantoir did
/// not write, as a plan is (`PlanNavigation`): the page may load itself and
/// files in its folder; a CLICK on a code is handed to the app, which looks
/// the code up in `about.json`; everything else is refused without a word,
/// web and email links included (the page has none).
nonisolated enum CoverageNavigation {

    // MARK: - Functions

    static func decide(url: URL, isNewWindow: Bool, byALinkClick: Bool, coverageFolder: URL) -> PlanNavigation.Decision {
        let scheme: String = (url.scheme ?? "").lowercased()
        if scheme == CoverageLink.scheme {
            if !byALinkClick {
                return .refuse
            }
            if CoverageLink.parse(url) == nil {
                return .refuse
            }
            return .handToTheApp
        }
        if scheme != "file" {
            return .refuse
        }
        if !PlanNavigation.isInside(url, folder: coverageFolder) {
            return .refuse
        }
        if isNewWindow {
            return .loadHere
        }
        return .load
    }
}

/// What a click on a code opens (`coverageTab.itemCases`): the file the
/// build named for it, checked again at the click, because the record was
/// written at build time and a file can be swapped for a link since
/// (793b-must-do, item 4).
nonisolated enum CoverageItem {

    /// What the click came to.
    enum Outcome: Equatable, Sendable {
        /// Open this file, at this place in the course folder (without `.md`).
        case open(file: URL, place: String)
        /// The page on screen is older than its record: reload, open nothing.
        case reload
        /// The record lists no page for this code on that map.
        case notListed
        /// The file is no longer there, or is not a page.
        case gone
        /// The file is not inside the course folder, once links are followed.
        case outside
    }

    // MARK: - Functions

    /// The file `link` names, through `record`, inside `courseFolder`.
    ///
    /// The record's path is taken LITERALLY: never percent-decoded, and any
    /// part that is empty, `.` or `..` refuses it (a folder may be NAMED
    /// `%2e%2e` or ` .. `, which are ordinary names). The joined path is
    /// resolved with every link followed and must then lie inside the course
    /// folder, resolved the same way, and be a plain file ending `.md`.
    static func resolve(_ link: CoverageLink, record: CoverageTabRecord?, courseFolder: URL) -> Outcome {
        guard let record, let recorded = record.buildId, recorded == link.buildId else {
            return .reload
        }
        if link.map < 0 || link.map >= record.maps.count {
            return .notListed
        }
        guard let source = record.maps[link.map].pages[link.code] else {
            return .notListed
        }
        if !source.hasSuffix(".md") || source.hasPrefix("/") || source.contains("\u{0}") {
            return .outside
        }
        var candidate: URL = courseFolder
        for part in source.components(separatedBy: "/") {
            if part.isEmpty || part == "." || part == ".." {
                return .outside
            }
            candidate = candidate.appendingPathComponent(part, isDirectory: false)
        }
        guard let resolved = CoverageItem.realPath(candidate.path) else {
            return .gone
        }
        guard let root = CoverageItem.realPath(courseFolder.path) else {
            return .gone
        }
        if !resolved.hasPrefix(root + "/") {
            return .outside
        }
        if !resolved.hasSuffix(".md") {
            return .outside
        }
        var isFolder: ObjCBool = false
        if !FileManager.default.fileExists(atPath: resolved, isDirectory: &isFolder) || isFolder.boolValue {
            return .gone
        }
        return .open(file: candidate, place: String(source.dropLast(".md".count)))
    }

    /// `path` with every link followed, or nil when it does not exist.
    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else {
            return nil
        }
        defer {
            free(resolved)
        }
        return String(cString: resolved)
    }
}

/// Whether the map may be out of date, from `BuildFreshness.changedSince`
/// over the map's own start (#768's rule, not a second one).
nonisolated enum CoverageChange: String, Sendable {
    /// Nothing in the course changed after the map's build started.
    case none
    /// Something did (`RebuildReason.pages`).
    case pages
    /// The map's build is dated later than now (`RebuildReason.clock`).
    case clock
    /// The record has no start time, so nobody can tell.
    case unknown
    /// A new map's walk has not come back yet: no line, and not a claim
    /// that it is current (the 793b review's LOW 1).
    case notKnownYet
}

/// How a "make the map again" from the Coverage tab came out, kept per
/// section in `SectionCoverage` so it survives a switch of tab or section.
nonisolated enum CoverageRefresh: Equatable, Sendable {
    case none
    /// Pressed: a preview still running is being stopped first. Recorded at
    /// the press, so the tab says the map is being made and the button is
    /// unavailable from that instant (the 793b review's H1). A run ending
    /// now is the OLD run's, and settles nothing.
    case starting
    /// Asked for; the build has not yet written the map, or ended.
    case pending
    /// The build ended, was stopped or never reached the map, or its map
    /// step failed: the last map is kept with its own date.
    case didNotFinish
    /// The preview could not start, for this reason.
    case refused(String)

    // MARK: - Computed properties

    /// The contract's name for it (`stateCases`' `refresh`).
    var name: String {
        switch self {
        case .none:
            return "none"
        case .starting:
            return "starting"
        case .pending:
            return "pending"
        case .didNotFinish:
            return "didNotFinish"
        case .refused:
            return "refused"
        }
    }
}

/// A late "the preview did not appear", kept for the section's next page.
nonisolated struct CoverageHeldRefusal: Equatable, Sendable {

    // MARK: - Stored properties

    let title: String
    let sentence: String
}

/// What the Coverage tab shows, from facts a test can give without a window:
/// `coverageTab.stateCases`. The view draws what this answers; every line is
/// a key of `coverageTab.words`.
nonisolated enum CoverageTabDisplay {

    /// The three faces of the tab.
    enum Kind: String, Sendable {
        case cannotShow
        case empty
        case map
    }

    /// Everything the face depends on.
    struct Facts: Equatable, Sendable {

        // MARK: - Stored properties

        var record: CoverageTab.RecordKind = .noRecord
        var refresh: CoverageRefresh = .none
        /// This window's own preview is building and has not yet reached the
        /// map step (no problems line yet in this run).
        var ownBuildBeforeItsMap: Bool = false
        /// This window's own preview is building at all (until its site
        /// first answers).
        var ownBuildRunning: Bool = false
        /// This app is deploying the section.
        var deploying: Bool = false
        /// Another program is building the course.
        var elsewhere: Bool = false
        /// Another window of this app holds the section's preview.
        var otherWindow: Bool = false
        var changed: CoverageChange = .none
        /// Whether the record says when its build started.
        var startKnown: Bool = true
        /// This window's preview is up and showing the site: a press stops
        /// it and starts it again, which the tab says before the press.
        var previewIsShowing: Bool = false
        /// The refresh under way stopped a preview that was showing, and
        /// starts it again with its build.
        var restartingThePreview: Bool = false
        /// This window handed the section's preview to the web browser: a
        /// restart leaves that browser tab without its live reload.
        var browserHasThePreview: Bool = false
        var rulesCompiled: Bool = true
        var obsidianInstalled: Bool = true
    }

    /// The face, its description when it is empty, its lines in order, and
    /// its one button.
    struct Display: Equatable, Sendable {

        // MARK: - Stored properties

        let kind: Kind
        let description: String?
        let lines: [String]
        let button: String?
        let buttonEnabled: Bool
    }

    // MARK: - Functions

    static func display(_ facts: Facts) -> Display {
        if !facts.rulesCompiled {
            return Display(kind: .cannotShow, description: "cannotShowDescription", lines: [], button: nil, buttonEnabled: false)
        }
        let hasAMap: Bool = facts.record == .thisBuild || facts.record == .anotherBuild
        let anyBuildRunning: Bool = facts.ownBuildRunning || facts.deploying || facts.elsewhere
        var making: Bool = false
        if facts.refresh == .pending || facts.refresh == .starting || facts.ownBuildBeforeItsMap {
            making = true
        }
        if facts.record == .anotherBuild && anyBuildRunning {
            making = true
        }
        var failed: Bool = false
        var refusedReason: Bool = false
        if !making {
            switch facts.refresh {
            case .didNotFinish:
                failed = true
            case .refused:
                failed = true
                refusedReason = true
            case .none, .pending, .starting:
                break
            }
            // Another window of this app holds the section's preview: its build
            // may be the one that moved .build-id, so the older map is not
            // said to be "not made again" (the fix review 2's LOW 4).
            if facts.record == .anotherBuild && !anyBuildRunning && !facts.otherWindow {
                failed = true
            }
        }

        // The first line is the map's own date, said only as far as it is
        // true (the 793b review's M1): "last built" only when the map IS the
        // latest build's, and never an empty date.
        // While a build is making the map, the record is another build's
        // because the new build has already written .build-id: "the latest
        // build made no map" would then be false (the fix review's M3).
        let hasATime: Bool = facts.startKnown
        var lines: [String] = []
        if facts.record == .thisBuild {
            lines.append(hasATime ? "asOf" : "asOfNoTime")
        } else if facts.record == .anotherBuild && (making || facts.otherWindow) {
            lines.append(hasATime ? "olderMapWhileBuilding" : "olderMapWhileBuildingNoTime")
        } else if facts.record == .anotherBuild {
            lines.append(hasATime ? "olderMap" : "olderMapNoTime")
        }
        if making {
            lines.append(facts.restartingThePreview ? "makingWithThePreview" : "making")
            if facts.restartingThePreview && facts.browserHasThePreview {
                lines.append("browserReload")
            }
        } else {
            if failed {
                lines.append(hasAMap ? "couldNotMakeAgain" : "couldNotMake")
                if refusedReason {
                    lines.append("refusedReason")
                }
            }
            if hasAMap {
                switch facts.changed {
                case .pages:
                    lines.append("changedSince")
                case .clock, .unknown:
                    lines.append("mayBeOutOfDate")
                case .none, .notKnownYet:
                    break
                }
            }
            if facts.deploying {
                lines.append("deploying")
            } else if facts.elsewhere {
                lines.append("elsewhere")
            } else if facts.otherWindow {
                lines.append("otherWindow")
            } else if facts.previewIsShowing && !facts.ownBuildRunning {
                // Said BEFORE the press (Russell's ruling on the fix review 2's
                // M1): making the map again restarts the preview.
                lines.append("previewRestarts")
            }
        }
        if hasAMap {
            lines.append(facts.obsidianInstalled ? "clickHint" : "noObsidian")
        }

        let enabled: Bool = !(making || facts.ownBuildRunning || facts.deploying || facts.elsewhere || facts.otherWindow)
        if hasAMap {
            return Display(kind: .map, description: nil, lines: lines, button: "makeTheMapAgain", buttonEnabled: enabled)
        }
        var description: String = "emptyDescription"
        if facts.record == .otherVersion {
            description = "emptyOtherVersion"
        } else if facts.record == .noMaps {
            description = "emptyNoCurriculum"
        }
        return Display(kind: .empty, description: description, lines: lines, button: "makeTheMap", buttonEnabled: enabled)
    }
}

/// Every word the Coverage tab shows a teacher, verbatim from
/// `contracts/shared-rules.json` → `coverageTab.words` (`CoverageTabTests`
/// pins them). Plain words only (rule 1). `{when}` is the map's start in the
/// app's own date and time style, `{code}` a code, `{reason}` a sentence the
/// preview's own refusal says, `{machine}` this platform's word.
nonisolated enum CoverageTabWording {

    // MARK: - Stored properties

    static let tabCoverage: String = "Coverage"
    static let asOf: String = "Made when this section was last built, {when}."
    static let asOfNoTime: String = "Made when this section was last built."
    static let olderMap: String = "Made by an earlier build of this section, {when}. The latest build made no map."
    static let olderMapNoTime: String = "Made by an earlier build of this section. The latest build made no map."
    static let olderMapWhileBuilding: String = "Made by an earlier build of this section, {when}."
    static let olderMapWhileBuildingNoTime: String = "Made by an earlier build of this section."
    static let making: String = "Making the map again with a new build of this section…"
    static let makingWithThePreview: String =
        "Making the map again with a new build of this section… Its preview starts again when the build is done, at the page you were last reading."
    static let previewRestarts: String =
        "Making the map again starts this section’s preview again, at the page you were last reading."
    static let browserReload: String =
        "If this section’s preview is open in your web browser, reload it there once the build is done."
    static let couldNotMakeAgain: String = "The map could not be made again this time."
    static let couldNotMake: String = "The map could not be made this time."
    static let changedSince: String = "Pages in the course have changed since then, so the map may be out of date."
    static let mayBeOutOfDate: String = "Plantoir cannot tell whether pages have changed since then, so the map may be out of date."
    static let deploying: String = "This section is being deployed. If its website is built again, the map is made again with it."
    static let elsewhere: String = "Another program is building this course just now. If it builds this section, the map is made again with it."
    static let otherWindow: String = "This section is being previewed in another window. Make the map again from there."
    static let clickHint: String = "Click a code to open its page in Obsidian."
    static let noObsidian: String = "Obsidian is not on this {machine}, so clicking a code opens nothing."
    static let pageGone: String = "The page for {code} is no longer in the course. Make the map again to bring it up to date."
    static let pageOutside: String = "The page for {code} is not inside the course folder, so it was not opened."
    static let makeTheMap: String = "Make the Map"
    static let makeTheMapAgain: String = "Make the Map Again"
    static let makeHelp: String = "Builds this section’s preview again, which makes the map again. You stay on this tab."
    static let emptyTitle: String = "No Coverage Map Yet"
    static let emptyDescription: String =
        "The map is made each time this section is previewed or deployed. Make it now to see what the course would cover once every page is published."
    static let emptyOtherVersion: String =
        "This section’s map was made by another version of Plantoir. Make it again to see it here."
    static let emptyNoCurriculum: String =
        "The last build of this section found no curriculum expectations to map. If you have added them since, make the map again."
    static let cannotShowTitle: String = "The Map Can’t Be Shown"
    static let cannotShowDescription: String =
        "Plantoir could not get ready to show the map on this {machine}. Quitting Plantoir and opening it again may be enough."

    // MARK: - Functions

    /// The sentence for a key of `coverageTab.words`, with its places filled.
    static func sentence(_ key: String, when: String = "", code: String = "", reason: String = "") -> String {
        var text: String = ""
        switch key {
        case "tabCoverage":
            text = tabCoverage
        case "asOf":
            text = asOf
        case "asOfNoTime":
            text = asOfNoTime
        case "olderMap":
            text = olderMap
        case "olderMapNoTime":
            text = olderMapNoTime
        case "olderMapWhileBuilding":
            text = olderMapWhileBuilding
        case "olderMapWhileBuildingNoTime":
            text = olderMapWhileBuildingNoTime
        case "making":
            text = making
        case "makingWithThePreview":
            text = makingWithThePreview
        case "previewRestarts":
            text = previewRestarts
        case "browserReload":
            text = browserReload
        case "couldNotMakeAgain":
            text = couldNotMakeAgain
        case "couldNotMake":
            text = couldNotMake
        case "refusedReason":
            text = reason
        case "changedSince":
            text = changedSince
        case "mayBeOutOfDate":
            text = mayBeOutOfDate
        case "deploying":
            text = deploying
        case "elsewhere":
            text = elsewhere
        case "otherWindow":
            text = otherWindow
        case "clickHint":
            text = clickHint
        case "noObsidian":
            text = noObsidian
        case "pageGone":
            text = pageGone
        case "pageOutside":
            text = pageOutside
        case "makeTheMap":
            text = makeTheMap
        case "makeTheMapAgain":
            text = makeTheMapAgain
        case "makeHelp":
            text = makeHelp
        case "emptyTitle":
            text = emptyTitle
        case "emptyDescription":
            text = emptyDescription
        case "emptyOtherVersion":
            text = emptyOtherVersion
        case "emptyNoCurriculum":
            text = emptyNoCurriculum
        case "cannotShowTitle":
            text = cannotShowTitle
        case "cannotShowDescription":
            text = cannotShowDescription
        default:
            text = ""
        }
        text = text.replacingOccurrences(of: "{when}", with: when)
        text = text.replacingOccurrences(of: "{code}", with: code)
        text = text.replacingOccurrences(of: MachineWord.placeholder, with: MachineWord.onThisPlatform)
        return text
    }

    /// `{when}`: the moment in the app's own date and time style.
    static func when(_ moment: Date?) -> String {
        guard let moment else {
            return ""
        }
        return moment.formatted(date: .abbreviated, time: .shortened)
    }
}

/// The Coverage tab's trail lines, verbatim from `contracts/shared-rules.json`
/// → `coverageTab.trailWords`, after the course and section, which
/// `ActivityTrail.note(_:_:course:section:)` adds. Counts and states only:
/// never an expectation's words, a page's words or a path, except the place
/// of the page a click opened, which the "page opened in Obsidian" line has
/// always named.
nonisolated enum CoverageTabTrail {

    // MARK: - Stored properties

    static let looked: String = "looked at the Coverage tab: {what}"
    static let oneMap: String = "1 map"
    static let maps: String = "{n} maps"
    static let counts: String = "{maps}, {e} expectations, {u} not yet addressed if every page were published; made {stamp}"
    static let changedSince: String = "; pages have changed since"
    static let notThisBuild: String = "; the latest build did not make it again"
    static let noMapYet: String = "no map made yet"
    static let otherVersion: String = "the map was made by another version of Plantoir"
    static let noCurriculum: String = "the last build found no curriculum to map"
    static let couldNotShow: String = "the Coverage tab showed nothing: Plantoir could not keep the map's page off the internet on this {machine}"
    static let asked: String = "asked to make the coverage map again from the Coverage tab"
    static let madeAgain: String = "the coverage map was made again"
    static let didNotFinish: String = "the coverage map could not be made again: the build ended before it was made"
    static let refused: String = "the coverage map could not be made again: the preview could not start"
    static let leftBeforeItsBuild: String = "the coverage map was not made again: the section was left before its build started"
    static let opened: String = "asked Obsidian to open {place}, curriculum expectation {code}, from the Coverage tab"
    static let didNotOpen: String = "did not open {code} from the Coverage tab: {why}"
    static let whyGone: String = "its page is no longer there"
    static let whyOutside: String = "its page is not inside the course folder"
    static let whyOlder: String = "the map on screen was older than its record"
    static let whyNotListed: String = "the map names no page for it"
    static let whyNoObsidian: String = "Obsidian is not on this {machine}"

    // MARK: - Functions

    /// A trail sentence with this platform's word for the computer.
    static func filled(_ text: String) -> String {
        return text.replacingOccurrences(of: MachineWord.placeholder, with: MachineWord.onThisPlatform)
    }

    /// The line for one look at the tab.
    static func lookedText(reading: CoverageTab.Reading, changed: CoverageChange, rulesCompiled: Bool) -> String {
        if !rulesCompiled {
            return filled(couldNotShow)
        }
        var what: String = noMapYet
        switch reading.kind {
        case .noRecord:
            what = noMapYet
        case .otherVersion:
            what = otherVersion
        case .noMaps:
            what = noCurriculum
        case .thisBuild, .anotherBuild:
            what = countsText(reading.record, kind: reading.kind, changed: changed)
        }
        return looked.replacingOccurrences(of: "{what}", with: what)
    }

    static func countsText(_ record: CoverageTabRecord?, kind: CoverageTab.RecordKind, changed: CoverageChange) -> String {
        guard let record else {
            return noMapYet
        }
        var expectations: Int = 0
        var notYet: Int = 0
        for map in record.maps {
            expectations += map.expectations
            notYet += map.notYetAddressed
        }
        var mapsWord: String = oneMap
        if record.maps.count != 1 {
            mapsWord = maps.replacingOccurrences(of: "{n}", with: String(record.maps.count))
        }
        var stamp: String = "at an unknown time"
        if let startedAt = record.startedAt {
            stamp = CoverageTabTrail.stamp(startedAt)
        }
        var text: String = counts
            .replacingOccurrences(of: "{maps}", with: mapsWord)
            .replacingOccurrences(of: "{e}", with: String(expectations))
            .replacingOccurrences(of: "{u}", with: String(notYet))
            .replacingOccurrences(of: "{stamp}", with: stamp)
        if changed == .pages {
            text += changedSince
        }
        if kind == .anotherBuild {
            text += notThisBuild
        }
        return text
    }

    /// `yyyy-MM-dd HH:mm`, in the Mac's own time zone.
    static func stamp(_ moment: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: moment)
    }

    /// The line for a click on a code.
    static func clickText(_ outcome: CoverageItem.Outcome, code: String) -> String {
        switch outcome {
        case .open(_, let place):
            return filled(opened.replacingOccurrences(of: "{place}", with: place).replacingOccurrences(of: "{code}", with: code))
        case .reload:
            return didNotOpenText(code: code, why: whyOlder)
        case .notListed:
            return didNotOpenText(code: code, why: whyNotListed)
        case .gone:
            return didNotOpenText(code: code, why: whyGone)
        case .outside:
            return didNotOpenText(code: code, why: whyOutside)
        }
    }

    static func didNotOpenText(code: String, why: String) -> String {
        return filled(didNotOpen.replacingOccurrences(of: "{code}", with: code).replacingOccurrences(of: "{why}", with: why))
    }
}
