import Foundation
import Observation

/// Every section's record of its problems that this window has read, and
/// what the teacher has done about them in this app (#717).
///
/// The RECORDS are on disk, written by the shared Python; this store only
/// reads them, at the moments one can have changed: a `PLANTOIR_PROBLEMS:`
/// marker in a run this app watched, the section being opened, the app
/// coming to the front (an MCP server's or a terminal's build), the
/// scheduled-deploy watcher moving, and the window's courses loading. Never
/// from a view's `body`: the sidebar row reads `hasProblems`, which is memory
/// only (plan review, MED 7).
///
/// Keyed by `SectionRuns.key` — the canonical folder, the course code
/// lowercased and the section — so a folder typed two ways is one entry, and
/// there is no second spelling of the key (#706).
///
/// What a teacher has ANSWERED is kept on disk, by working folder, so a
/// relaunch does not raise yesterday's alert again (plan review, HIGH 2):
/// `ProblemsAcknowledgements`. Ticks are kept for the session only (the
/// director's ruling): a fixed row goes by itself on the next build.
@MainActor
@Observable
final class SectionProblems {

    /// A section's tabs: Website, Coverage (#793) and Problems. One type
    /// for all three, `SectionTab`; this store keeps which one the teacher
    /// chose, and `SectionTabs.showing` says which one shows.
    typealias Tab = SectionTab

    // MARK: - Stored properties

    static let shared: SectionProblems = SectionProblems()

    /// Every record read, by `SectionRuns.key`.
    private(set) var records: [String: SectionProblemsRecord] = [:]

    /// The tab each section shows, while the app is open. Kept here rather
    /// than in the view's state because `.id("code-section")` rebuilds the
    /// view when the selection moves, and Show must survive that.
    private(set) var tabs: [String: Tab] = [:]

    /// Rows the teacher has UNTICKED, by section. An absent row is ticked:
    /// ticked means included (the app's checklist rule).
    private(set) var unticked: [String: Set<String>] = [:]

    /// Moves whenever any run in this app prints a `PLANTOIR_PROBLEMS:`
    /// marker; the sidebar reads every record again when it does.
    private(set) var markersArrived: Int = 0

    /// Where answers are kept; a test points it somewhere of its own.
    @ObservationIgnored var acknowledgementFolder: URL = ProblemsAcknowledgements.folder()

    /// Keys already worked out, so a sidebar row asking does not reach the
    /// disk for the canonical folder on every redraw.
    @ObservationIgnored private var keys: [String: String] = [:]

    // MARK: - Functions

    /// The store's key for a section.
    func key(folder: URL, courseCode: String, sectionNumber: Int) -> String {
        let asked: String = "\(folder.path)\n\(courseCode)\n\(sectionNumber)"
        if let known = keys[asked] {
            return known
        }
        let made: String = SectionRuns.key(folderPath: folder.path, courseCode: courseCode, sectionNumber: sectionNumber)
        keys[asked] = made
        return made
    }

    /// A run printed a marker: something reading the records should read them.
    func noteAMarkerArrived() {
        markersArrived += 1
    }

    /// Reads every section of `course` again: one section's record decides
    /// another's rows (`rowState`), so a course is read whole.
    func reload(folder: URL, course: Course) {
        for sectionNumber in course.sectionNumbers {
            let url: URL = SectionProblemsRecord.url(courseFolder: course.directoryURL, sectionNumber: sectionNumber)
            let read: SectionProblemsRecord? = SectionProblemsRecord.read(url)
            let sectionKey: String = key(folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
            if records[sectionKey] != read {
                records[sectionKey] = read
            }
            if let read {
                noteOnTheTrailOnce(read, folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
            }
        }
    }

    /// Reads every course's records.
    func reloadAll(folder: URL, courses: [Course]) {
        for course in courses {
            reload(folder: folder, course: course)
        }
    }

    /// A section's record, when it has one.
    func record(folder: URL, courseCode: String, sectionNumber: Int) -> SectionProblemsRecord? {
        return records[key(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber)]
    }

    /// The records of the course's OTHER sections.
    func otherRecords(folder: URL, course: Course, sectionNumber: Int) -> [SectionProblemsRecord] {
        var others: [SectionProblemsRecord] = []
        for other in course.sectionNumbers where other != sectionNumber {
            if let found = record(folder: folder, courseCode: course.code, sectionNumber: other) {
                others.append(found)
            }
        }
        return others
    }

    /// Whether the section's sidebar row wears the warning.
    func hasProblems(folder: URL, courseCode: String, sectionNumber: Int) -> Bool {
        return SectionProblemsRules.markerShows(record(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber))
    }

    /// The section's record when its alert is due.
    func recordWithAnAlertDue(folder: URL, courseCode: String, sectionNumber: Int) -> SectionProblemsRecord? {
        guard let found = record(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber) else {
            return nil
        }
        let answered: Set<String> = ProblemsAcknowledgements.read(in: acknowledgementFolder, forWorkingFolder: folder)
            .answered(courseCode: courseCode, sectionNumber: sectionNumber)
        if !SectionProblemsRules.alertIsDue(found, answered: answered) {
            return nil
        }
        return found
    }

    /// The teacher answered the alert: remembered, so it is not raised again
    /// for this record, and written on the trail.
    func answer(_ record: SectionProblemsRecord, with answer: String, folder: URL, courseCode: String, sectionNumber: Int) {
        var kept: ProblemsAcknowledgements = ProblemsAcknowledgements.read(in: acknowledgementFolder, forWorkingFolder: folder)
        kept.remember(answered: record.alertKey, courseCode: courseCode, sectionNumber: sectionNumber)
        kept.write(in: acknowledgementFolder, forWorkingFolder: folder)
        ActivityTrail.note(.problemsChanged, SectionProblemsRules.answerLine(answer), course: courseCode, section: sectionNumber)
    }

    /// The tab a section shows, as far as this store can say: Problems only
    /// while it has rows. The section's page asks `SectionTabs.showing` with
    /// every tab its bar holds, Coverage included (#793).
    func tab(folder: URL, courseCode: String, sectionNumber: Int) -> Tab {
        let chosen: Tab = chosenTab(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber)
        if chosen == .problems && !hasProblems(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber) {
            return .website
        }
        return chosen
    }

    /// The tab the teacher last chose for a section, Website until then.
    func chosenTab(folder: URL, courseCode: String, sectionNumber: Int) -> Tab {
        return tabs[key(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber)] ?? .website
    }

    func show(_ tab: Tab, folder: URL, courseCode: String, sectionNumber: Int) {
        tabs[key(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber)] = tab
    }

    /// Whether a row is ticked. Ticked means included.
    func isTicked(_ rowID: String, folder: URL, courseCode: String, sectionNumber: Int) -> Bool {
        let sectionKey: String = key(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber)
        return !(unticked[sectionKey]?.contains(rowID) ?? false)
    }

    func setTicked(_ ticked: Bool, rowID: String, folder: URL, courseCode: String, sectionNumber: Int) {
        let sectionKey: String = key(folder: folder, courseCode: courseCode, sectionNumber: sectionNumber)
        var set: Set<String> = unticked[sectionKey] ?? []
        if ticked {
            set.remove(rowID)
        } else {
            set.insert(rowID)
        }
        unticked[sectionKey] = set
    }

    /// One "problems changed" line per alertKey whose set changed, the first
    /// time this app reads it — from a run it watched or later — and never
    /// again after a relaunch (the key is remembered beside the answers).
    func noteOnTheTrailOnce(_ record: SectionProblemsRecord, folder: URL, courseCode: String, sectionNumber: Int) {
        if !record.setChanged {
            return
        }
        var kept: ProblemsAcknowledgements = ProblemsAcknowledgements.read(in: acknowledgementFolder, forWorkingFolder: folder)
        if kept.noted(courseCode: courseCode, sectionNumber: sectionNumber).contains(record.alertKey) {
            return
        }
        kept.remember(noted: record.alertKey, courseCode: courseCode, sectionNumber: sectionNumber)
        kept.write(in: acknowledgementFolder, forWorkingFolder: folder)
        ActivityTrail.note(.problemsChanged, SectionProblemsRules.trailLine(for: record), course: courseCode, section: sectionNumber)
    }

    /// Starts from nothing — for tests.
    func reset() {
        records = [:]
        tabs = [:]
        unticked = [:]
        keys = [:]
    }
}

/// What a teacher has answered about each section's problems, and which
/// changes are already on the trail — one small file per working folder,
/// under the app's own Application Support beside `toolchain-index`
/// (`sectionProblems.alert`; plan review, HIGH 2). Never in the record,
/// which the build rewrites, and never in the teacher's folder.
nonisolated struct ProblemsAcknowledgements: Equatable, Sendable {

    // MARK: - Stored properties

    /// How many keys of each list are kept per section.
    static let kept: Int = 20

    /// `"<course lowercased>/<section>"` → the alert keys answered.
    var answeredKeys: [String: [String]] = [:]

    /// The same → the alert keys already on the trail.
    var notedKeys: [String: [String]] = [:]

    // MARK: - Functions

    static func folder(inHomeFolder homeFolder: URL = RealHome.forFiles) -> URL {
        return homeFolder
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("problems-acknowledged", isDirectory: true)
    }

    /// One working folder's file, named by the eight characters its builds
    /// folder and its index are (`BuildOutputLocation.folderIdentifier`).
    static func url(in folder: URL, forWorkingFolder workingFolderURL: URL) -> URL {
        let identifier: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: workingFolderURL.path)
        return folder.appendingPathComponent(identifier + ".json")
    }

    static func sectionKey(courseCode: String, sectionNumber: Int) -> String {
        return "\(courseCode.lowercased())/\(sectionNumber)"
    }

    static func read(in folder: URL, forWorkingFolder workingFolderURL: URL) -> ProblemsAcknowledgements {
        var read: ProblemsAcknowledgements = ProblemsAcknowledgements()
        guard let data = try? Data(contentsOf: url(in: folder, forWorkingFolder: workingFolderURL)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = object["sections"] as? [String: Any] else {
            return read
        }
        for (name, value) in sections {
            guard let entry = value as? [String: Any] else {
                continue
            }
            read.answeredKeys[name] = (entry["answered"] as? [String]) ?? []
            read.notedKeys[name] = (entry["noted"] as? [String]) ?? []
        }
        return read
    }

    func answered(courseCode: String, sectionNumber: Int) -> Set<String> {
        return Set(answeredKeys[ProblemsAcknowledgements.sectionKey(courseCode: courseCode, sectionNumber: sectionNumber)] ?? [])
    }

    func noted(courseCode: String, sectionNumber: Int) -> Set<String> {
        return Set(notedKeys[ProblemsAcknowledgements.sectionKey(courseCode: courseCode, sectionNumber: sectionNumber)] ?? [])
    }

    mutating func remember(answered alertKey: String, courseCode: String, sectionNumber: Int) {
        let name: String = ProblemsAcknowledgements.sectionKey(courseCode: courseCode, sectionNumber: sectionNumber)
        answeredKeys[name] = ProblemsAcknowledgements.adding(alertKey, to: answeredKeys[name] ?? [])
    }

    mutating func remember(noted alertKey: String, courseCode: String, sectionNumber: Int) {
        let name: String = ProblemsAcknowledgements.sectionKey(courseCode: courseCode, sectionNumber: sectionNumber)
        notedKeys[name] = ProblemsAcknowledgements.adding(alertKey, to: notedKeys[name] ?? [])
    }

    /// `list` with `key` last, at most `kept` long, oldest dropped.
    static func adding(_ key: String, to list: [String]) -> [String] {
        var kept: [String] = []
        for existing in list where existing != key {
            kept.append(existing)
        }
        kept.append(key)
        while kept.count > ProblemsAcknowledgements.kept {
            kept.removeFirst()
        }
        return kept
    }

    /// Written whole and atomically; a file that cannot be written costs at
    /// most one alert raised again.
    func write(in folder: URL, forWorkingFolder workingFolderURL: URL) {
        var sections: [String: Any] = [:]
        var names: Set<String> = Set(answeredKeys.keys)
        for name in notedKeys.keys {
            names.insert(name)
        }
        for name in names {
            sections[name] = ["answered": answeredKeys[name] ?? [], "noted": notedKeys[name] ?? []]
        }
        let object: [String: Any] = ["version": 1, "sections": sections]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: ProblemsAcknowledgements.url(in: folder, forWorkingFolder: workingFolderURL), options: .atomic)
    }
}
