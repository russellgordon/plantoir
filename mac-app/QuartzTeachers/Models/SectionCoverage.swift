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

        /// The press a refresh still starting belongs to (the 793b review's
        /// H1): its start goes ahead only while this is the press's own.
        /// Written by `beginRefresh`, `refreshMayStart` and `abandon` alone,
        /// never by a reading (the fix review's H1).
        var refreshToken: UUID?

        /// The section view that pressed, so another window's view leaving
        /// the section, or stopping its own preview, settles nothing of this
        /// press's (the fix review's LOW 1).
        var refreshOwner: UUID?

        /// The course and section the press was for, for the trail line of
        /// an abandon that has only the key (a quit).
        var refreshCourse: String?
        var refreshSection: Int?

        /// The press stopped a preview that was showing, which its build
        /// starts again (the fix review 2's M1).
        var restartsThePreview: Bool = false

        /// A late "the preview did not appear" that waited on Coverage when
        /// the section's page went away (the fix review 2's LOW 3): the next
        /// page of the section raises it.
        var heldLateRefusal: CoverageHeldRefusal?

        /// The build id the last freshness walk was for: a reading of a
        /// different map says nothing about change until its own walk is
        /// back (the 793b review's LOW 1).
        var walkedFor: String?

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

    /// The sections whose map web views are kept: for tests.
    var keptWebViews: Set<String> {
        return Set(controllers.keys)
    }

    /// Sections whose tab's OWN start is running right now: a preview
    /// refusal arriving then is the refresh's, said in the tab (the fix
    /// review's M1). Set only around the synchronous `start` in `makeAgain`.
    @ObservationIgnored private var ownStartRunning: Set<String> = []

    /// One web view per section being SHOWN, made the first time its tab
    /// shows and kept while the section is on screen, so a switch of tab
    /// finds the page and its scroll; released when no window shows the
    /// section any longer (the 793b review's LOW 2).
    @ObservationIgnored private var controllers: [String: PlanWebController] = [:]

    /// How many section views show each section now.
    @ObservationIgnored private var showing: [String: Int] = [:]

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

    /// A section's page appeared.
    func noteShown(_ key: String) {
        showing[key] = (showing[key] ?? 0) + 1
    }

    /// A section's page went away: its map's web view goes when no window
    /// shows the section.
    func noteGone(_ key: String) {
        let left: Int = (showing[key] ?? 1) - 1
        if left > 0 {
            showing[key] = left
            return
        }
        showing[key] = nil
        controllers[key] = nil
    }

    // MARK: - The refresh, from the press to the start (the 793b review's H1)

    /// Make the Map (Again), pressed: recorded AT ONCE, as `starting` with a
    /// token, so the tab says the map is being made and the button is
    /// unavailable from this instant. Nil, and nothing recorded, when a
    /// refresh is already starting or waiting for its map: a second press
    /// does nothing, so it can never end the running build's wait.
    func beginRefresh(folder: URL, course: Course, sectionNumber: Int, owner: UUID? = nil, restartsThePreview: Bool = false) -> UUID? {
        let sectionKey: String = key(folder: folder, course: course, sectionNumber: sectionNumber)
        var updated: Entry = entry(sectionKey)
        if updated.refresh == .starting || updated.refresh == .pending {
            return nil
        }
        let token: UUID = UUID()
        updated.refresh = .starting
        updated.refreshToken = token
        updated.refreshOwner = owner
        updated.refreshCourse = course.code
        updated.refreshSection = sectionNumber
        updated.restartsThePreview = restartsThePreview
        updated.clickLine = nil
        entries[sectionKey] = updated
        ActivityTrail.note(.askedToMakeTheCoverageMapAgain, CoverageTabTrail.asked, course: course.code, section: sectionNumber)
        return token
    }

    /// The old preview has stopped: whether the press's build may start now.
    /// Only while the press's token is still the section's (nobody left the
    /// section, the course or the window, and the app is not quitting); then
    /// the refresh waits for its map, from the record's id as it is now.
    func refreshMayStart(token: UUID, folder: URL, course: Course, sectionNumber: Int) -> Bool {
        let sectionKey: String = key(folder: folder, course: course, sectionNumber: sectionNumber)
        var updated: Entry = entry(sectionKey)
        if updated.refresh != .starting || updated.refreshToken != token {
            return false
        }
        updated.refresh = .pending
        updated.refreshToken = nil
        updated.refreshFrom = updated.reading?.record?.buildId
        entries[sectionKey] = updated
        return true
    }

    /// The section's page went away (a switch of section or course, the
    /// window closing): a refresh still starting is abandoned, so its start
    /// never runs from a view that has gone.
    ///
    /// Only the pressing view's own leaving counts: another window showing
    /// the same section may come and go (the fix review's LOW 1).
    func abandonRefresh(folder: URL, course: Course, sectionNumber: Int, owner: UUID? = nil) {
        let sectionKey: String = key(folder: folder, course: course, sectionNumber: sectionNumber)
        if entry(sectionKey).refreshOwner != owner {
            return
        }
        abandon(sectionKey)
    }

    /// The app is quitting: every refresh still starting is abandoned.
    func abandonEveryRefresh() {
        for (sectionKey, found) in entries where found.refresh == .starting {
            abandon(sectionKey)
        }
    }

    private func abandon(_ sectionKey: String) {
        var updated: Entry = entry(sectionKey)
        if updated.refresh != .starting {
            return
        }
        updated.refresh = .didNotFinish
        updated.refreshToken = nil
        entries[sectionKey] = updated
        if let course = updated.refreshCourse, let sectionNumber = updated.refreshSection {
            ActivityTrail.note(.askedToMakeTheCoverageMapAgain, CoverageTabTrail.leftBeforeItsBuild, course: course, section: sectionNumber)
        } else {
            ActivityTrail.note(.askedToMakeTheCoverageMapAgain, CoverageTabTrail.leftBeforeItsBuild)
        }
    }

    /// Keeps a late refusal for the section's next page.
    func holdALateRefusal(_ held: CoverageHeldRefusal, key sectionKey: String) {
        var updated: Entry = entry(sectionKey)
        updated.heldLateRefusal = held
        entries[sectionKey] = updated
    }

    /// The late refusal kept for this section, taken once.
    func takeTheHeldLateRefusal(_ sectionKey: String) -> CoverageHeldRefusal? {
        var updated: Entry = entry(sectionKey)
        guard let held = updated.heldLateRefusal else {
            return nil
        }
        updated.heldLateRefusal = nil
        entries[sectionKey] = updated
        return held
    }

    /// Whether the tab's own start is running for this section now.
    func isRunningTheTabsOwnStart(_ sectionKey: String) -> Bool {
        return ownStartRunning.contains(sectionKey)
    }

    /// The steps of one press, with the stop and the start handed in, so a
    /// test can run them with no window: record the press, stop a preview
    /// still running and wait for it, then start the build only if the press
    /// still holds, and settle at once a start that did not begin.
    /// `start` answers whether a build began.
    ///
    /// `aBuildIsRunning` is asked after the stop: a preview somebody started
    /// meanwhile (the teacher's own Preview, the assistant) is a build that
    /// writes the map, so the refresh waits for it and starts nothing of its
    /// own, which would end that build's wait and be refused (the fix
    /// review's M1).
    static func makeAgain(
        store: SectionCoverage,
        folder: URL,
        course: Course,
        sectionNumber: Int,
        owner: UUID? = nil,
        previewIsRunning: Bool,
        aBuildIsRunning: () -> Bool = { () -> Bool in return false },
        stop: () async -> Void,
        waitForTheOldRun: () async -> Void = { () async -> Void in },
        start: () -> Bool
    ) async {
        guard let token = store.beginRefresh(
            folder: folder, course: course, sectionNumber: sectionNumber, owner: owner, restartsThePreview: previewIsRunning
        ) else {
            return
        }
        if previewIsRunning {
            await stop()
            // The stop's own wait ends when the stop does, and the OLD run
            // may end a moment after it: until it has, "a build is already
            // running" would be that old run (the fix review 2's LOW 1).
            // Waited for its end, an event, never a delay.
            await waitForTheOldRun()
        }
        if !store.refreshMayStart(token: token, folder: folder, course: course, sectionNumber: sectionNumber) {
            return
        }
        if aBuildIsRunning() {
            return
        }
        let sectionKey: String = store.key(folder: folder, course: course, sectionNumber: sectionNumber)
        store.ownStartRunning.insert(sectionKey)
        let started: Bool = start()
        store.ownStartRunning.remove(sectionKey)
        if !started {
            store.noteOwnRunEnded(folder: folder, course: course, sectionNumber: sectionNumber, owner: owner)
        }
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
        let mapId: String? = reading.record?.buildId
        if mapId != updated.walkedFor {
            updated.changed = .notKnownYet
        }
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
    ///
    /// `owner` is the view whose run it was: another window's view stopping
    /// ITS preview settles nothing of this press's (the fix review's LOW 1).
    func noteOwnRunEnded(folder: URL, course: Course, sectionNumber: Int, owner: UUID? = nil) {
        let sectionKey: String = key(folder: folder, course: course, sectionNumber: sectionNumber)
        var updated: Entry = entry(sectionKey)
        if updated.refresh != .pending {
            return
        }
        if updated.refreshOwner != owner {
            return
        }
        let reading: CoverageTab.Reading = CoverageTab.read(
            folder: CoverageTab.folder(courseFolder: course.directoryURL, sectionNumber: sectionNumber),
            buildId: CoverageTab.sectionBuildId(courseFolder: course.directoryURL, sectionNumber: sectionNumber)
        )
        if reading.record?.buildId != updated.walkedFor {
            updated.changed = .notKnownYet
        }
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
        // A press still waiting for an old preview to stop is not an older
        // "could not": only its own start, or its abandon, moves it on. A
        // reading during the stop (the old run's end, the app coming to the
        // front, a click) must leave it alone (the fix review's H1).
        if updated.refresh == .starting {
            return
        }
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
        let mapId: String? = reading.record?.buildId
        guard let record = reading.record, reading.kind == .thisBuild || reading.kind == .anotherBuild else {
            setChanged(.none, key: sectionKey, walkedFor: mapId)
            return
        }
        guard let startedAt = record.startedAt else {
            setChanged(.unknown, key: sectionKey, walkedFor: mapId)
            return
        }
        Task.detached(priority: .utility) {
            let reason: BuildFreshness.RebuildReason? = BuildFreshness.changedSince(
                reference: startedAt, courseFolder: courseFolder, now: Date()
            )
            let changed: CoverageChange = SectionCoverage.change(for: reason)
            await MainActor.run {
                if self.walkGenerations[sectionKey] == generation {
                    self.setChanged(changed, key: sectionKey, walkedFor: mapId)
                }
            }
        }
    }

    private func setChanged(_ changed: CoverageChange, key sectionKey: String, walkedFor: String?) {
        var updated: Entry = entry(sectionKey)
        if updated.changed != changed || updated.walkedFor != walkedFor {
            updated.changed = changed
            updated.walkedFor = walkedFor
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
        showing = [:]
        walkGenerations = [:]
        rulesFailed = false
    }
}
