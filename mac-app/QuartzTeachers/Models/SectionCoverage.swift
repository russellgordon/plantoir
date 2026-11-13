import Foundation
import Observation

/// Every section's Coverage tab as this window last read it (#793): the
/// map's record, whether the course has curriculum at all, whether pages
/// changed since the map was made, how a "make the map again" came out, and
/// the web view showing the map.
///
/// Kept here rather than in the view's state, for the reason
/// `SectionProblems.tabs` is: the section's view is rebuilt whenever the
/// selection moves, and both the map's scroll and a refresh still under way
/// must survive that (the plan review's H1 and H2). Keyed by `SectionRuns.key`
/// through `SectionProblems.key`, so a folder typed two ways is one entry.
///
/// Read at the moments the record can have changed, never from a view's
/// `body`: the tab appearing, a `PLANTOIR_PROBLEMS:` line in any run this app
/// watched (the map is written before it), a run starting or ending, and the
/// app coming to the front (a scheduled deploy's or an outside assistant's
/// build). No polling and no folder watch.
@MainActor
@Observable
final class SectionCoverage {

    /// One section's tab.
    struct Entry: Equatable {

        // MARK: - Stored properties

        var reading: CoverageTab.Reading?
        var hasCurriculum: Bool = false
        var changed: CoverageChange = .none
        var elsewhere: Bool = false
        var refresh: CoverageRefresh = .none

        /// The record's build id when the refresh was asked for: a record
        /// with another id, and this build's, is the map made again.
        var refreshFrom: String?

        /// What the last click on a code could not open, said above the
        /// map until the next reading.
        var clickLine: String?
    }

    // MARK: - Stored properties

    static let shared: SectionCoverage = SectionCoverage()

    private(set) var entries: [String: Entry] = [:]

    /// Whether the rule list for the map's page could be made: false only
    /// when it could not, and then no map is ever shown.
    private(set) var rulesFailed: Bool = false

    /// One web view per section, made the first time its tab shows and kept
    /// while the app is open, so a switch back finds the page and its scroll.
    @ObservationIgnored private var controllers: [String: PlanWebController] = [:]

    /// Which freshness walk is the current one, per section.
    @ObservationIgnored private var walkGenerations: [String: Int] = [:]

    // MARK: - Functions

    func key(folder: URL, course: Course, sectionNumber: Int) -> String {
        return SectionProblems.shared.key(folder: folder, courseCode: course.code, sectionNumber: sectionNumber)
    }

    func entry(_ key: String) -> Entry {
        return entries[key] ?? Entry()
    }

    /// Whether the section's bar carries Coverage (`SectionTabs.shown`).
    func showsTheTab(_ key: String) -> Bool {
        let found: Entry = entry(key)
        return found.hasCurriculum || (found.reading?.hasMaps ?? false)
    }

    /// The section's web view, made once. `open` is told of every click on a
    /// code; `cannotShow` once, when the rule list could not be made.
    func controller(
        _ key: String, open: @escaping (URL) -> Void, cannotShow: @escaping () -> Void
    ) -> PlanWebController {
        let made: PlanWebController
        if let kept = controllers[key] {
            made = kept
            made.navigationGuard.handToTheApp = open
        } else {
            made = PlanWebController.forCoverage(handToTheApp: open)
            controllers[key] = made
        }
        made.whenItCannotShow = { [weak self] in
            self?.rulesFailed = true
            cannotShow()
        }
        return made
    }

    /// Reads the section's record again, and whether the course has
    /// curriculum, then, off the main actor, whether pages changed since the
    /// map's build started (`BuildFreshness.changedSince`, #768's rule over
    /// the map's own `startedNs`; the plan review's M1).
    ///
    /// `afterAMarker` is true when a run has just printed its problems line,
    /// which means the map STEP has run: a refresh still waiting then either
    /// finds its map, or knows its build made none.
    func reload(folder: URL, course: Course, sectionNumber: Int, afterAMarker: Bool = false) {
        let sectionKey: String = key(folder: folder, course: course, sectionNumber: sectionNumber)
        let reading: CoverageTab.Reading = CoverageTab.read(
            folder: CoverageTab.folder(courseFolder: course.directoryURL, sectionNumber: sectionNumber),
            buildId: CoverageTab.sectionBuildId(courseFolder: course.directoryURL, sectionNumber: sectionNumber)
        )
        var updated: Entry = entry(sectionKey)
        updated.reading = reading
        updated.hasCurriculum = !CurriculumFolderRule.resolvedFolders(for: course).isEmpty
        updated.elsewhere = WorkLeaseRegistry.anotherProgramIsBuilding(folderPath: folder.path, courseCode: course.code)
        updated.clickLine = nil
        settle(&updated, reading: reading, afterAMarker: afterAMarker, runEnded: false, course: course, sectionNumber: sectionNumber)
        if updated != entry(sectionKey) {
            entries[sectionKey] = updated
        }
        walkForChanges(sectionKey, reading: reading, courseFolder: course.directoryURL)
    }

    /// A "make the map again" was asked for: noted before the build starts,
    /// with the record's id as it is now.
    func noteRefreshAsked(folder: URL, course: Course, sectionNumber: Int) {
        let sectionKey: String = key(folder: folder, course: course, sectionNumber: sectionNumber)
        var updated: Entry = entry(sectionKey)
        updated.refresh = .pending
        updated.refreshFrom = updated.reading?.record?.buildId
        updated.clickLine = nil
        entries[sectionKey] = updated
        ActivityTrail.note(.askedToMakeTheCoverageMapAgain, CoverageTabTrail.asked, course: course.code, section: sectionNumber)
    }

    /// The preview could not start: said in the tab, never in an alert.
    func noteRefreshRefused(folder: URL, course: Course, sectionNumber: Int, reason: String) {
        let sectionKey: String = key(folder: folder, course: course, sectionNumber: sectionNumber)
        var updated: Entry = entry(sectionKey)
        if updated.refresh != .pending {
            return
        }
        updated.refresh = .refused(reason)
        entries[sectionKey] = updated
        ActivityTrail.note(.askedToMakeTheCoverageMapAgain, CoverageTabTrail.refused, course: course.code, section: sectionNumber)
    }

    /// This window's preview run ended, was stopped, or the view is going
    /// away (a switch of section stops its build): a refresh still waiting
    /// is settled from what is on disk NOW, so nothing is left half-noted.
    func noteOwnRunEnded(folder: URL, course: Course, sectionNumber: Int) {
        let sectionKey: String = key(folder: folder, course: course, sectionNumber: sectionNumber)
        var updated: Entry = entry(sectionKey)
        if updated.refresh != .pending {
            return
        }
        let reading: CoverageTab.Reading = CoverageTab.read(
            folder: CoverageTab.folder(courseFolder: course.directoryURL, sectionNumber: sectionNumber),
            buildId: CoverageTab.sectionBuildId(courseFolder: course.directoryURL, sectionNumber: sectionNumber)
        )
        updated.reading = reading
        settle(&updated, reading: reading, afterAMarker: false, runEnded: true, course: course, sectionNumber: sectionNumber)
        entries[sectionKey] = updated
    }

    /// What a click on a code could not open, in words above the map.
    func noteClickLine(_ line: String?, key sectionKey: String) {
        var updated: Entry = entry(sectionKey)
        updated.clickLine = line
        entries[sectionKey] = updated
    }

    /// The rule for a waiting refresh, shared by every reading: the map made
    /// by a build other than the one the refresh started from, and this
    /// build's, is the map made again; a build that ran its map step and
    /// made none, or a run that ended first, did not finish.
    private func settle(
        _ updated: inout Entry, reading: CoverageTab.Reading, afterAMarker: Bool, runEnded: Bool,
        course: Course, sectionNumber: Int
    ) {
        if updated.refresh != .pending {
            if reading.kind == .thisBuild, let id = reading.record?.buildId, id != updated.refreshFrom,
               updated.refresh != .none {
                // A later build made the map: an older "could not" is no
                // longer true.
                updated.refresh = .none
                updated.refreshFrom = nil
            }
            return
        }
        let madeAgain: Bool = reading.kind == .thisBuild && reading.record?.buildId != updated.refreshFrom
        if madeAgain {
            updated.refresh = .none
            updated.refreshFrom = nil
            ActivityTrail.note(.askedToMakeTheCoverageMapAgain, CoverageTabTrail.madeAgain, course: course.code, section: sectionNumber)
            return
        }
        if afterAMarker || runEnded {
            updated.refresh = .didNotFinish
            ActivityTrail.note(.askedToMakeTheCoverageMapAgain, CoverageTabTrail.didNotFinish, course: course.code, section: sectionNumber)
        }
    }

    /// The freshness walk, off the main actor; only the latest one lands.
    private func walkForChanges(_ sectionKey: String, reading: CoverageTab.Reading, courseFolder: URL) {
        let generation: Int = (walkGenerations[sectionKey] ?? 0) + 1
        walkGenerations[sectionKey] = generation
        guard let record = reading.record, reading.kind == .thisBuild || reading.kind == .anotherBuild else {
            setChanged(.none, key: sectionKey)
            return
        }
        guard let startedAt = record.startedAt else {
            setChanged(.unknown, key: sectionKey)
            return
        }
        Task.detached(priority: .utility) {
            let reason: BuildFreshness.RebuildReason? = BuildFreshness.changedSince(
                reference: startedAt, courseFolder: courseFolder, now: Date()
            )
            let changed: CoverageChange = SectionCoverage.change(for: reason)
            await MainActor.run {
                if self.walkGenerations[sectionKey] == generation {
                    self.setChanged(changed, key: sectionKey)
                }
            }
        }
    }

    private func setChanged(_ changed: CoverageChange, key sectionKey: String) {
        var updated: Entry = entry(sectionKey)
        if updated.changed != changed {
            updated.changed = changed
            entries[sectionKey] = updated
        }
    }

    /// `changedSince`'s answer in the tab's words.
    nonisolated static func change(for reason: BuildFreshness.RebuildReason?) -> CoverageChange {
        guard let reason else {
            return .none
        }
        switch reason {
        case .clock:
            return .clock
        case .pages:
            return .pages
        case .neverBuilt, .frontPageUnreadable, .preview:
            return .none
        }
    }

    /// Starts from nothing — for tests.
    func reset() {
        entries = [:]
        controllers = [:]
        walkGenerations = [:]
        rulesFailed = false
    }
}
