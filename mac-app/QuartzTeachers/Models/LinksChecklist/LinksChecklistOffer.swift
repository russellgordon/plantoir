import Foundation

/// What the build offers to publish for one section (#379): read from the file
/// the build writes, `courses/<CODE>/.publish_state/section<N>.links-checklist.json`
/// (`contracts/file-formats.json` → `linksChecklistOffer`).
///
/// **The build decides, the app reads.** The rule — two steps from a visible
/// class, the other group, the classes, the dates — is the shared Python's
/// (`scripts/build_site.py` → `_links_checklist_offer`), so Windows inherits it
/// by sharing it and the mac never has to run the Python outside the builder.
/// Nothing here works a row out; it only reads rows, and checks them again
/// against the pages as they are now before anything is written
/// (`LinksChecklistPublisher`).
nonisolated struct LinksChecklistOffer: Sendable, Equatable {

    // MARK: - Types

    enum Group: String, Sendable {
        case fromAClass
        case notReachedByAClass
        case aClass = "class"
    }

    /// Why a row carries the date it does — `linksChecklistOffer.whyValues`.
    enum Why: String, Sendable {
        case dated
        case datedAsTheFirstClass
        case datedByTheBuild
        case keepsItsDate
        case structuralNeverDated
        case classNeverDated
        case noClassToDateFrom
    }

    struct Row: Sendable, Equatable, Identifiable {

        // MARK: - Stored properties

        /// The page's place in the course folder, without `.md`.
        let place: String
        let title: String
        let group: Group
        let ticked: Bool
        let step: Int?
        let claimedBy: String?
        /// The day to write, or nil to write none.
        let date: CalendarDay?
        let why: Why
        let firstUsedIn: String?
        let linkedFrom: [String]
        /// The offered rows this page is reached through when no page
        /// students can see links it — nearest first; the first is the row it
        /// is listed under (#385). Empty for most rows, always for a class,
        /// and for every row of an offer an older builder wrote.
        let dependsOn: [String]

        // MARK: - Computed properties

        var id: String {
            return place
        }

        // MARK: - Functions

        /// The same row, reached through these rows instead (#385's re-read).
        func withDependsOn(_ places: [String]) -> Row {
            return Row(
                place: place, title: title, group: group, ticked: ticked, step: step,
                claimedBy: claimedBy, date: date, why: why, firstUsedIn: firstUsedIn,
                linkedFrom: linkedFrom, dependsOn: places
            )
        }
    }

    // MARK: - Stored properties

    let course: String
    let section: Int
    let buildId: String?
    let firstClassPlace: String?
    let rows: [Row]

    // MARK: - Functions

    /// Where the build writes the offer for a section.
    static func fileURL(courseDirectory: URL, section: Int) -> URL {
        return courseDirectory
            .appendingPathComponent(".publish_state")
            .appendingPathComponent("section\(section).links-checklist.json")
    }

    /// The last part of a place — what a teacher calls the page.
    static func name(ofPlace place: String) -> String {
        guard let slash = place.lastIndex(of: "/") else {
            return place
        }
        return String(place[place.index(after: slash)...])
    }

    /// The offer and when it was written, or nil when there is none or it
    /// cannot be read. An unreadable offer is no offer: the finding's alert is
    /// the floor, and it is still there.
    static func read(courseDirectory: URL, section: Int) -> (offer: LinksChecklistOffer, writtenAt: Date)? {
        let url: URL = fileURL(courseDirectory: courseDirectory, section: section)
        guard let data = try? Data(contentsOf: url),
              let offer = decode(data) else {
            return nil
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return (offer: offer, writtenAt: values?.contentModificationDate ?? Date.distantPast)
    }

    /// Reads the file's text. Unknown group or why values drop the row rather
    /// than guess at it.
    static func decode(_ data: Data) -> LinksChecklistOffer? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let course = object["course"] as? String,
              let section = object["section"] as? Int,
              let pages = object["pages"] as? [[String: Any]] else {
            return nil
        }
        var rows: [Row] = []
        for page in pages {
            guard let place = page["place"] as? String,
                  let groupText = page["group"] as? String,
                  let group = Group(rawValue: groupText),
                  let whyText = page["why"] as? String,
                  let why = Why(rawValue: whyText) else {
                continue
            }
            var day: CalendarDay? = nil
            if let dateText = page["date"] as? String {
                day = CalendarDay(text: dateText)
            }
            var linkedFrom: [String] = []
            for entry in (page["linkedFrom"] as? [Any]) ?? [] {
                if let text = entry as? String {
                    linkedFrom.append(text)
                }
            }
            var dependsOn: [String] = []
            for entry in (page["dependsOn"] as? [Any]) ?? [] {
                if let text = entry as? String {
                    dependsOn.append(text)
                }
            }
            rows.append(Row(
                place: place,
                title: (page["title"] as? String) ?? name(ofPlace: place),
                group: group,
                ticked: (page["ticked"] as? Bool) ?? false,
                step: page["step"] as? Int,
                claimedBy: page["claimedBy"] as? String,
                date: day,
                why: why,
                firstUsedIn: page["firstUsedIn"] as? String,
                linkedFrom: linkedFrom,
                dependsOn: dependsOn
            ))
        }
        var firstClassPlace: String? = nil
        if let firstClass = object["firstClass"] as? [String: Any] {
            firstClassPlace = firstClass["place"] as? String
        }
        return LinksChecklistOffer(
            course: course, section: section, buildId: object["buildId"] as? String,
            firstClassPlace: firstClassPlace, rows: rows
        )
    }

    /// Every place the offer holds.
    var places: Set<String> {
        var found: Set<String> = []
        for row in rows {
            found.insert(row.place)
        }
        return found
    }
}

/// The line the build prints when it has written (or removed) the offer:
/// `PLANTOIR_LINKS_CHECKLIST: {json}` (`shared-rules.json` →
/// `linksChecklist.marker`).
///
/// It exists because the #333 finding is announced BEFORE the build's date
/// passes run, so the offer cannot exist yet when the finding reaches the app
/// (plan review, finding 14). The window acts on this line instead: the file
/// is written before it is printed, and its `buildId` says which build the
/// file belongs to.
nonisolated struct LinksChecklistMarker: Sendable, Equatable {

    // MARK: - Stored properties

    let course: String
    let section: Int
    let buildId: String?
    let pages: Int

    // MARK: - Functions

    /// Pinned by `contracts/shared-rules.json` → `linksChecklist.marker.prefix`.
    static let markerPrefix: String = "PLANTOIR_LINKS_CHECKLIST:"

    static func markers(in text: String) -> [LinksChecklistMarker] {
        var found: [LinksChecklistMarker] = []
        for line in SiteHealthFinding.linesOf(text) {
            guard let prefixRange = line.range(of: markerPrefix) else {
                continue
            }
            let payload: String = String(line[prefixRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let course = object["course"] as? String,
                  let section = object["section"] as? Int,
                  let pages = object["pages"] as? Int else {
                continue
            }
            found.append(LinksChecklistMarker(
                course: course, section: section, buildId: object["buildId"] as? String, pages: pages
            ))
        }
        return found
    }
}

/// What the teacher last answered (`file-formats.json` →
/// `linksChecklistAnswered`): the app's own file, never the build's.
nonisolated struct LinksChecklistAnswered: Sendable, Equatable {

    // MARK: - Stored properties

    let offered: Set<String>
    let leftUnticked: Set<String>

    // MARK: - Functions

    static func fileURL(courseDirectory: URL, section: Int) -> URL {
        return courseDirectory
            .appendingPathComponent(".publish_state")
            .appendingPathComponent("section\(section).links-checklist-answered.json")
    }

    static func read(courseDirectory: URL, section: Int) -> LinksChecklistAnswered? {
        guard let data = try? Data(contentsOf: fileURL(courseDirectory: courseDirectory, section: section)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var offered: Set<String> = []
        for entry in (object["offered"] as? [Any]) ?? [] {
            if let text = entry as? String {
                offered.insert(text)
            }
        }
        var leftUnticked: Set<String> = []
        for entry in (object["leftUnticked"] as? [Any]) ?? [] {
            if let text = entry as? String {
                leftUnticked.insert(text)
            }
        }
        return LinksChecklistAnswered(offered: offered, leftUnticked: leftUnticked)
    }

    /// Written with a rename, so a reader never meets half a file. Last writer
    /// wins between two windows: the worst outcome is being asked once more.
    func write(courseDirectory: URL, section: Int, at moment: Date = Date()) throws {
        let url: URL = LinksChecklistAnswered.fileURL(courseDirectory: courseDirectory, section: section)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        let object: [String: Any] = [
            "version": 1,
            "answeredAt": formatter.string(from: moment),
            "offered": offered.sorted(),
            "leftUnticked": leftUnticked.sorted()
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

/// Whether, and how, the checklist is offered (`shared-rules.json` →
/// `linksChecklist.offeredWhen`). Pure, so every branch is a unit test.
nonisolated enum LinksChecklistGate {

    // MARK: - Types

    /// When the teacher is being offered it — also what the trail line says.
    enum Occasion: String, Sendable {
        case afterAPreview = "after a preview"
        case afterPublishing = "after deploying"
        case onOpening = "on opening, after a deploy Plantoir did not watch"
        case fromTheMenu = "from the menu"
    }

    // MARK: - Functions

    /// True when the offer holds a page the teacher has not already answered.
    static func holdsSomethingNew(_ offer: LinksChecklistOffer, answered: LinksChecklistAnswered?) -> Bool {
        guard let answered else {
            return !offer.rows.isEmpty
        }
        for row in offer.rows where !answered.offered.contains(row.place) {
            return true
        }
        return false
    }

    /// True when nothing in the course has changed since the offer was
    /// written — the `buildFreshness` rule, hidden entries skipped. An older
    /// offer may name a link the teacher has since removed, or a class that
    /// has since been hidden or moved (plan review, finding 15).
    static func isFresh(writtenAt: Date, newestContentChange: Date?) -> Bool {
        guard let newestContentChange else {
            return true
        }
        return newestContentChange <= writtenAt
    }

    /// Whether a watched build's marker points at the offer on disk.
    static func markerMatches(_ marker: LinksChecklistMarker, offer: LinksChecklistOffer) -> Bool {
        guard marker.pages > 0, let markerBuild = marker.buildId, let offerBuild = offer.buildId else {
            return false
        }
        return markerBuild == offerBuild && marker.section == offer.section
    }

    /// Where a row starts: the offer's own tick, unless the teacher unticked
    /// it last time and it is still offered.
    static func startsTicked(_ row: LinksChecklistOffer.Row, answered: LinksChecklistAnswered?) -> Bool {
        if let answered, answered.leftUnticked.contains(row.place) {
            return false
        }
        return row.ticked
    }

    // MARK: - Rows that come under another row (#385)

    /// The rows that GO — shown ticked, and published by Publish
    /// (`shared-rules.json` → `linksChecklist.followingARow`). A row goes when
    /// its OWN tick is on and it has no `dependsOn`, or at least one row in its
    /// `dependsOn` goes.
    ///
    /// Worked out from nothing upwards (the least fixed point): two hidden
    /// pages that link only each other never go through each other, only
    /// through a row that goes. NOT "a row it comes under is ticked" — that
    /// publishes such a pair with nothing students can see linking either.
    static func going(_ rows: [LinksChecklistOffer.Row], ticked: Set<String>) -> Set<String> {
        var going: Set<String> = []
        var somethingWasAdded: Bool = true
        while somethingWasAdded {
            somethingWasAdded = false
            for row in rows where !going.contains(row.place) && ticked.contains(row.place) {
                var canGo: Bool = row.dependsOn.isEmpty
                for parent in row.dependsOn where going.contains(parent) {
                    canGo = true
                }
                if canGo {
                    going.insert(row.place)
                    somethingWasAdded = true
                }
            }
        }
        return going
    }

    /// True when a row comes under other rows and none of them is going: it
    /// is shown unticked and cannot be ticked, whatever its own tick. A row a
    /// ticked class brings is never locked — it is shown coming with that
    /// class instead (#398, `linksChecklist.comingWithAClass`).
    static func isLocked(
        _ row: LinksChecklistOffer.Row, going: Set<String>, comingWith: [String: String]
    ) -> Bool {
        if comingWith[row.place] != nil {
            return false
        }
        if row.dependsOn.isEmpty {
            return false
        }
        for parent in row.dependsOn where going.contains(parent) {
            return false
        }
        return true
    }

    /// What the checkbox does: it changes the row's OWN tick and nothing
    /// else. The rows under it keep theirs — copying the tick down would tick
    /// ten pages of later units under SNC1W's Final Examination
    /// (`followingARow.whyItsOwnTickIsKept`).
    ///
    /// A row shown coming with a ticked class ignores it (#398): its checkbox
    /// is disabled, and its own tick is kept exactly as it was, so unticking
    /// the class brings the row back as it was.
    static func toggled(
        _ ticked: Set<String>, place: String, isOn: Bool, comingWith: [String: String]
    ) -> Set<String> {
        if comingWith[place] != nil {
            return ticked
        }
        var changed: Set<String> = ticked
        if isOn {
            changed.insert(place)
        } else {
            changed.remove(place)
        }
        return changed
    }

    // MARK: - Rows a ticked class brings (#398)

    /// The rows shown coming with a ticked class, each with the class that
    /// brings it (`shared-rules.json` → `linksChecklist.comingWithAClass`).
    ///
    /// `brings` is, for each class row, the rows publishing that class would
    /// publish because it links them — the class publish's own plan
    /// (`LinksChecklistPublisher.whatEachClassBrings`), never `firstUsedIn`.
    /// Only classes that GO bring anything. Where two ticked classes bring the
    /// same row, the FIRST class in the sheet's order is named. A class row is
    /// never brought.
    static func comingWith(
        _ rows: [LinksChecklistOffer.Row], going: Set<String>, brings: [String: [String]]
    ) -> [String: String] {
        var pagePlaces: Set<String> = []
        for row in rows where row.group != .aClass {
            pagePlaces.insert(row.place)
        }
        var found: [String: String] = [:]
        for row in rows where row.group == .aClass && going.contains(row.place) {
            for place in brings[row.place] ?? [] where pagePlaces.contains(place) && found[place] == nil {
                found[place] = row.place
            }
        }
        return found
    }

    /// The rows shown ticked: those that go, and those a ticked class brings.
    /// What the Publish button counts.
    static func shownTicked(going: Set<String>, comingWith: [String: String]) -> Set<String> {
        var shown: Set<String> = going
        for place in comingWith.keys {
            shown.insert(place)
        }
        return shown
    }

    /// One row as the sheet lists it: under which heading, and how far in.
    struct ShownRow: Equatable {

        // MARK: - Stored properties

        let row: LinksChecklistOffer.Row
        let depth: Int
        /// The heading it is listed under — its parent's group when it comes
        /// under a row of the other group.
        let group: LinksChecklistOffer.Group
    }

    /// The order the sheet lists rows in: each group in turn, a row followed
    /// by the rows listed under it (those whose FIRST `dependsOn` is it), in
    /// the offer's order, depth first. `dependsOn[0]` is strictly nearer to a
    /// page students can see, so this cannot loop on a file the build wrote;
    /// a row it never reaches (a hand-edited file) is listed at the end of its
    /// own group rather than lost.
    static func shownOrder(_ rows: [LinksChecklistOffer.Row]) -> [ShownRow] {
        var rowPlaces: Set<String> = []
        for row in rows {
            rowPlaces.insert(row.place)
        }
        var childrenOf: [String: [LinksChecklistOffer.Row]] = [:]
        var topRows: [LinksChecklistOffer.Row] = []
        for row in rows {
            if let first = row.dependsOn.first, first != row.place, rowPlaces.contains(first) {
                childrenOf[first, default: []].append(row)
            } else {
                topRows.append(row)
            }
        }
        var shown: [ShownRow] = []
        var visited: Set<String> = []
        let groups: [LinksChecklistOffer.Group] = [.fromAClass, .notReachedByAClass, .aClass]
        for group in groups {
            for top in topRows where top.group == group {
                appendShown(top, depth: 0, group: group, childrenOf: childrenOf, visited: &visited, into: &shown)
            }
        }
        for group in groups {
            for row in rows where row.group == group && !visited.contains(row.place) {
                appendShown(row, depth: 0, group: group, childrenOf: childrenOf, visited: &visited, into: &shown)
            }
        }
        return shown
    }

    private static func appendShown(
        _ row: LinksChecklistOffer.Row,
        depth: Int,
        group: LinksChecklistOffer.Group,
        childrenOf: [String: [LinksChecklistOffer.Row]],
        visited: inout Set<String>,
        into shown: inout [ShownRow]
    ) {
        if visited.contains(row.place) {
            return
        }
        visited.insert(row.place)
        shown.append(ShownRow(row: row, depth: depth, group: group))
        for child in childrenOf[row.place] ?? [] {
            appendShown(child, depth: depth + 1, group: group, childrenOf: childrenOf, visited: &visited, into: &shown)
        }
    }
}

/// What the section window does with the #333 finding when a build reports
/// it (`shared-rules.json` → `linksChecklist.offeredWhen` and
/// `fallbackWithNoOffer`). Pure, so every branch is a unit test.
nonisolated enum LinksChecklistRouting {

    // MARK: - Types

    enum Route: Equatable {
        /// List the finding in the folder-problem alert, exactly as before.
        case alert
        /// Leave it out of the alert and show the checklist instead.
        case checklist
        /// The build has not said yet whether it wrote an offer: hold it.
        case waitForTheBuild
    }

    // MARK: - Functions

    /// The check the checklist replaces.
    static let findingName: String = "linksIntoHiddenPages"

    /// For a build this window watched. The alert is the floor: a course
    /// kept for reference, a build that finished without saying it wrote an
    /// offer (a builder older than this app — Trap 1), or an offer that is
    /// not this build's, all get the alert as before.
    static func route(
        marker: LinksChecklistMarker?,
        offer: LinksChecklistOffer?,
        isKeptForReference: Bool,
        buildHasFinished: Bool
    ) -> Route {
        if isKeptForReference {
            return .alert
        }
        guard let marker else {
            return buildHasFinished ? .alert : .waitForTheBuild
        }
        guard let offer, LinksChecklistGate.markerMatches(marker, offer: offer) else {
            return .alert
        }
        return .checklist
    }

    /// For a publish this window did not watch (the scheduled run's findings,
    /// shown when the window next appears): the finding leaves the alert only
    /// when the checklist will really be shown.
    static func findingsForTheAlert(
        _ findings: [SiteHealthFinding], checklistWillBeShown: Bool
    ) -> [SiteHealthFinding] {
        if !checklistWillBeShown {
            return findings
        }
        var kept: [SiteHealthFinding] = []
        for finding in findings where finding.name != findingName {
            kept.append(finding)
        }
        return kept
    }
}
