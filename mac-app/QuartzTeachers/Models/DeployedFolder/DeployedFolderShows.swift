import AppKit
import Foundation
import Observation

/// Every deployed folder this app is showing in the web browser (#850), one
/// per section's folder, app-wide: the result panel, the Section menu, the
/// toolbar and the sidebar all open through here, so pressing Open again
/// while one runs reopens the same address and starts nothing.
///
/// **It runs until Stop or quitting Plantoir** (Russell, 2026-11-13), never
/// until a window closes: the browser tab outlives the window. A deploy to
/// the same folder does not stop it, because nothing here copies or builds:
/// the folder is read at each request, and the next reload shows the new
/// site. So it takes no preview lease and no work lease.
///
/// **Quit never asks about it** (`quittingWhileWorkIsUnderWay.cases`): nothing
/// can be lost.
@MainActor
@Observable
final class DeployedFolderShows {

    // MARK: - Types

    /// One folder being shown.
    struct Show: Identifiable {
        /// The served folder's canonical path.
        let id: String
        let courseCode: String
        let sectionNumber: Int
        let workingFolderPath: String
        let root: URL
        let port: Int
        let server: DeployedFolderServer

        var address: URL {
            return URL(string: "http://127.0.0.1:\(port)/")!
        }
    }

    /// Where Open in Browser was pressed, for the trail.
    enum From: String {
        case result = "from the deploy's result"
        case sectionMenu = "from the Section menu"
        case toolbar = "from the toolbar"
        case sidebar = "from the sidebar"
    }

    /// Why a show ended, for the trail.
    enum StopReason: String {
        case stopPressed = "Stop was pressed"
        case plantoirQuit = "Plantoir quit"
        case folderGone = "the folder was gone"
        /// The listener ended without being asked (the implementation
        /// review's L4).
        case endedOnItsOwn = "it stopped on its own"
    }

    /// Why opening did not happen, for the trail.
    enum CouldNotOpen: String {
        case folderNotFound = "the folder was not found"
        case nothingDeployed = "nothing deployed there"
        case noFreeAddress = "no address on this computer was free"
        case browserDidNotOpen = "the browser did not open it"
    }

    /// What a section's Open in Browser can do right now.
    struct Lookup {
        var facts: DeployedFolderOffer.Facts
        var decision: DeployedFolderOffer.Decision
        /// `<folder>/section<N>`, when the course deploys to a folder.
        var sectionFolder: URL?
    }

    // MARK: - Stored properties

    static let shared: DeployedFolderShows = DeployedFolderShows()

    private(set) var shows: [Show] = []

    /// Sections whose folder went away while shown ("course/section/working
    /// folder"), so their window can say so until it is dismissed.
    private(set) var stoppedBecauseTheFolderWentAway: Set<String> = []

    /// Starts not yet finished, by canonical folder path: a second press
    /// joins the first.
    private var startsUnderWay: [String: Task<Show?, Never>] = [:]

    /// Which section each start under way is for ("course/section/working
    /// folder"), so Stop on a section reaches its start too.
    private var startingFor: [String: String] = [:]

    /// Folders whose Stop was pressed while their start was still under way.
    private var stopsAskedForWhileStarting: Set<String> = []

    /// Stops not yet finished, by canonical folder path: each ends when its
    /// listener has let the address go (#1013). An Open of the same folder
    /// waits for it, so it gets its usual address back rather than finding
    /// it still held and moving.
    private var stopsUnderWay: [String: Task<Void, Never>] = [:]

    /// Tests only: told, with the folder's canonical path, when a Stop has
    /// asked its listener to cancel and is waiting for it to let go.
    var stopIsWaitingForTests: ((String) -> Void)? = nil

    // MARK: - Functions: looking

    /// The show for a section, if one is running.
    func show(courseCode: String, sectionNumber: Int, workingFolderPath: String) -> Show? {
        for show in shows {
            if show.courseCode == courseCode && show.sectionNumber == sectionNumber
                && FolderIdentity.isSameFolder(show.workingFolderPath, workingFolderPath) {
                return show
            }
        }
        return nil
    }

    /// Whether a section's folder stopped being shown because it went away.
    func folderWentAway(courseCode: String, sectionNumber: Int, workingFolderPath: String) -> Bool {
        return stoppedBecauseTheFolderWentAway.contains(
            DeployedFolderShows.key(courseCode: courseCode, sectionNumber: sectionNumber, workingFolderPath: workingFolderPath)
        )
    }

    /// Forgets that a section's folder went away (the notice was dismissed,
    /// or it was opened again).
    func dismissFolderWentAway(courseCode: String, sectionNumber: Int, workingFolderPath: String) {
        stoppedBecauseTheFolderWentAway.remove(
            DeployedFolderShows.key(courseCode: courseCode, sectionNumber: sectionNumber, workingFolderPath: workingFolderPath)
        )
    }

    /// Tests only: whether a start is under way for a folder.
    func isStartingForTests(_ canonicalRoot: String) -> Bool {
        return startsUnderWay[canonicalRoot] != nil
    }

    static func key(courseCode: String, sectionNumber: Int, workingFolderPath: String) -> String {
        return "\(courseCode)/\(sectionNumber)/\(FolderIdentity.canonicalPath(workingFolderPath))"
    }

    /// The facts and the decision for a section, read now from its SAVED
    /// settings (what a deploy uses) and the disk.
    static func lookUp(course: Course, sectionNumber: Int, workingFolderPath: String) -> Lookup {
        var facts: DeployedFolderOffer.Facts = DeployedFolderOffer.Facts()
        facts.keptForReference = course.isKeptForReference
        let configuration: CourseConfiguration = (try? CourseConfiguration(contentsOf: course.configFileURL)) ?? course.configuration
        var additional: [(type: String, path: String)] = []
        for target in configuration.additionalDeployTargets {
            additional.append((type: target.type, path: target.path))
        }
        guard let setting = DeployedFolderOffer.folderSetting(
            deployTarget: configuration.deployTarget,
            deployFolderPath: configuration.deployFolderPath,
            additional: additional
        ) else {
            return Lookup(facts: facts, decision: DeployedFolderOffer.decide(facts), sectionFolder: nil)
        }
        facts.hasFolderDestination = true
        let canonicalWorkingFolder: String = FolderIdentity.canonicalPath(workingFolderPath)
        let folderPath: String = DeployedFolderOffer.deployFolderPath(setting: setting, workingFolderPath: canonicalWorkingFolder)
        let sectionPath: String = DeployedFolderOffer.sectionFolderPath(
            setting: setting, workingFolderPath: canonicalWorkingFolder, sectionNumber: sectionNumber
        )
        facts.folderExists = DeployedFolderResolver.isFolder(URL(fileURLWithPath: folderPath))
        facts.sectionIndexExists = DeployedFolderResolver.isFile(
            URL(fileURLWithPath: sectionPath).appendingPathComponent("index.html")
        )
        var running: Bool = CourseActivity.sectionPublishIsRunning(
            folderPath: workingFolderPath, courseCode: course.code, sectionNumber: sectionNumber
        )
        // A scheduled deploy, an outside assistant or the command line: read
        // from their work leases (the plan review's L6). Leases are per
        // course, so another section's deploy greys this one too, briefly.
        let coursesDirectory: URL = course.directoryURL.deletingLastPathComponent()
        for holding in WorkLeaseFiles.heldElsewhere(courseCode: course.code, coursesDirectory: coursesDirectory) {
            if holding.kind == WorkLeaseFiles.publishKind {
                running = true
            }
        }
        facts.deployIsRunning = running
        return Lookup(facts: facts, decision: DeployedFolderOffer.decide(facts), sectionFolder: URL(fileURLWithPath: sectionPath))
    }

    // MARK: - Functions: opening and stopping

    /// Opens a section's deployed folder in the browser, starting to show it
    /// if it is not already. True when the browser was handed the address.
    @discardableResult
    func open(
        sectionFolder: URL, courseCode: String, sectionNumber: Int, workingFolderPath: String, from: From,
        defaults: UserDefaults = PlantoirDefaults.shared,
        openInBrowser: (URL) -> Bool = { address in NSWorkspace.shared.open(address) }
    ) async -> Bool {
        dismissFolderWentAway(courseCode: courseCode, sectionNumber: sectionNumber, workingFolderPath: workingFolderPath)
        let canonicalRoot: String = FolderIdentity.canonicalPath(sectionFolder.path)
        // Opened again straight after Stop: the old listener lets the
        // address go first (#1013).
        if let stopping = stopsUnderWay[canonicalRoot] {
            await stopping.value
        }
        for show in shows where show.id == canonicalRoot {
            ActivityTrail.note(
                .deployedFolderOpened, DeployedFolderShows.openedLine(from: from, alreadyOpen: true, moved: false),
                course: courseCode, section: sectionNumber
            )
            return handOver(show, courseCode: courseCode, sectionNumber: sectionNumber, openInBrowser: openInBrowser)
        }
        // A second press while the first is still starting joins it, so two
        // quick presses start ONE show (the implementation review's M1: both
        // passed the check above, both started, and Stop ended only one).
        if let starting = startsUnderWay[canonicalRoot] {
            guard let show = await starting.value else {
                return false
            }
            ActivityTrail.note(
                .deployedFolderOpened, DeployedFolderShows.openedLine(from: from, alreadyOpen: true, moved: false),
                course: courseCode, section: sectionNumber
            )
            return handOver(show, courseCode: courseCode, sectionNumber: sectionNumber, openInBrowser: openInBrowser)
        }
        if !DeployedFolderResolver.isFolder(sectionFolder) {
            noteCouldNotOpen(.folderNotFound, courseCode: courseCode, sectionNumber: sectionNumber)
            return false
        }
        if !DeployedFolderResolver.isFile(sectionFolder.appendingPathComponent("index.html")) {
            noteCouldNotOpen(.nothingDeployed, courseCode: courseCode, sectionNumber: sectionNumber)
            return false
        }
        let starting: Task<Show?, Never> = Task { @MainActor in
            return await self.startShowing(
                canonicalRoot: canonicalRoot, courseCode: courseCode, sectionNumber: sectionNumber,
                workingFolderPath: workingFolderPath, from: from, defaults: defaults
            )
        }
        startsUnderWay[canonicalRoot] = starting
        startingFor[canonicalRoot] = DeployedFolderShows.key(
            courseCode: courseCode, sectionNumber: sectionNumber, workingFolderPath: workingFolderPath
        )
        let started: Show? = await starting.value
        startsUnderWay.removeValue(forKey: canonicalRoot)
        startingFor.removeValue(forKey: canonicalRoot)
        stopsAskedForWhileStarting.remove(canonicalRoot)
        guard let show = started else {
            return false
        }
        return handOver(show, courseCode: courseCode, sectionNumber: sectionNumber, openInBrowser: openInBrowser)
    }

    /// Starts one show and records it, or nil (and a trail line) when no
    /// address was free. A Stop pressed while it started ends it at once.
    private func startShowing(
        canonicalRoot: String, courseCode: String, sectionNumber: Int, workingFolderPath: String,
        from: From, defaults: UserDefaults
    ) async -> Show? {
        let remembered: Int? = DeployedFolderAddress.rememberedPort(forCanonicalPath: canonicalRoot, defaults: defaults)
        let candidates: [Int] = DeployedFolderAddress.candidates(forCanonicalPath: canonicalRoot, remembered: remembered)
        let root: URL = URL(fileURLWithPath: canonicalRoot)
        let started: (server: DeployedFolderServer, firstWasTaken: Bool)
        do {
            started = try await DeployedFolderServer.start(root: root, candidates: candidates, onFolderGone: { server in
                Task { @MainActor in
                    await DeployedFolderShows.shared.theFolderWentAway(server: server)
                }
            }, onEnded: { server in
                Task { @MainActor in
                    await DeployedFolderShows.shared.theListenerEnded(server: server)
                }
            })
        } catch {
            // A Stop asked for while this failed must not stop the next
            // Open (the fix review's L-b).
            stopsAskedForWhileStarting.remove(canonicalRoot)
            noteCouldNotOpen(.noFreeAddress, courseCode: courseCode, sectionNumber: sectionNumber)
            return nil
        }
        DeployedFolderAddress.remember(port: started.server.port, forCanonicalPath: canonicalRoot, defaults: defaults)
        let show: Show = Show(
            id: canonicalRoot, courseCode: courseCode, sectionNumber: sectionNumber,
            workingFolderPath: workingFolderPath, root: root, port: started.server.port, server: started.server
        )
        shows.append(show)
        ActivityTrail.note(
            .deployedFolderOpened, DeployedFolderShows.openedLine(from: from, alreadyOpen: false, moved: started.firstWasTaken),
            course: courseCode, section: sectionNumber
        )
        if stopsAskedForWhileStarting.contains(canonicalRoot) {
            stopsAskedForWhileStarting.remove(canonicalRoot)
            await stop(show, reason: .stopPressed)
            return nil
        }
        return show
    }

    /// Hands the address to the browser; says so on the trail when it would
    /// not take it.
    private func handOver(_ show: Show, courseCode: String, sectionNumber: Int, openInBrowser: (URL) -> Bool) -> Bool {
        if openInBrowser(show.address) {
            return true
        }
        noteCouldNotOpen(.browserDidNotOpen, courseCode: courseCode, sectionNumber: sectionNumber)
        return false
    }

    private func noteCouldNotOpen(_ why: CouldNotOpen, courseCode: String, sectionNumber: Int) {
        ActivityTrail.note(
            .deployedFolderCouldNotBeOpened, DeployedFolderShows.couldNotOpenLine(why),
            course: courseCode, section: sectionNumber
        )
    }

    // MARK: - Functions: the trail's words

    /// "opened the deployed folder in the web browser (…)", as
    /// `activityTrail.mustRecord` writes it.
    static func openedLine(from: From, alreadyOpen: Bool, moved: Bool) -> String {
        if alreadyOpen {
            return "opened the deployed folder in the web browser (\(from.rawValue), already open)"
        }
        if moved {
            return "opened the deployed folder in the web browser (\(from.rawValue), at a different address because its usual one was taken, so what the site remembered there is not shown)"
        }
        return "opened the deployed folder in the web browser (\(from.rawValue))"
    }

    static func stoppedLine(_ reason: StopReason, requests: Int, notFound: Int) -> String {
        return "stopped showing the deployed folder in the web browser — \(reason.rawValue) (\(requests) requests, \(notFound) not found)"
    }

    static func couldNotOpenLine(_ why: CouldNotOpen) -> String {
        return "could not open the deployed folder in the web browser — \(why.rawValue)"
    }

    /// Stops showing one folder, and returns once nothing is listening at
    /// its address (#1013). The show leaves the list at once, before any
    /// wait, so the window says it has stopped as soon as Stop is pressed
    /// and a second Stop finds nothing to stop; the trail line is written
    /// once the address is free.
    ///
    /// Waits for the listener's own `.cancelled` (`DeployedFolderServer.stop`),
    /// never for a length of time: before #1013 this returned as soon as it
    /// had ASKED the listener to cancel, and under load the address went on
    /// answering afterwards (3 of 40 runs of `DeployedFolderOfferTests`
    /// failed, and with the framework's queue held back, 5 of 5).
    func stop(_ show: Show, reason: StopReason) async {
        var remaining: [Show] = []
        var found: Bool = false
        for each in shows {
            if each.id == show.id {
                found = true
            } else {
                remaining.append(each)
            }
        }
        if !found {
            // Already being stopped: wait for that Stop to finish.
            if let stopping = stopsUnderWay[show.id] {
                await stopping.value
            }
            return
        }
        shows = remaining
        if reason == .folderGone {
            stoppedBecauseTheFolderWentAway.insert(
                DeployedFolderShows.key(courseCode: show.courseCode, sectionNumber: show.sectionNumber, workingFolderPath: show.workingFolderPath)
            )
        }
        show.server.listener.cancel()
        let server: DeployedFolderServer = show.server
        let courseCode: String = show.courseCode
        let sectionNumber: Int = show.sectionNumber
        let stopping: Task<Void, Never> = Task { @MainActor in
            let counts: (requests: Int, notFound: Int) = await server.counts()
            await server.stop()
            DeployedFolderShows.noteStopped(reason, counts: counts, courseCode: courseCode, sectionNumber: sectionNumber)
        }
        stopsUnderWay[show.id] = stopping
        stopIsWaitingForTests?(show.id)
        await stopping.value
        // A later show of the same folder may have started its own Stop.
        if let current = stopsUnderWay[show.id], current == stopping {
            stopsUnderWay.removeValue(forKey: show.id)
        }
    }

    /// Stop on a section: the notice's button and the menu item. Returns
    /// once nothing of the section's is listening (#1013).
    ///
    /// Every show of the section, not only the first: one started before the
    /// course's deploy folder was changed is the section's too (the
    /// implementation review's L5). A start still under way for it is
    /// stopped as soon as it finishes, and this waits for that too.
    func stop(courseCode: String, sectionNumber: Int, workingFolderPath: String) async {
        var ending: [Show] = []
        for show in shows {
            if show.courseCode == courseCode && show.sectionNumber == sectionNumber
                && FolderIdentity.isSameFolder(show.workingFolderPath, workingFolderPath) {
                ending.append(show)
            }
        }
        let section: String = DeployedFolderShows.key(
            courseCode: courseCode, sectionNumber: sectionNumber, workingFolderPath: workingFolderPath
        )
        var startsToWaitFor: [Task<Show?, Never>] = []
        for (root, owner) in startingFor where owner == section {
            stopsAskedForWhileStarting.insert(root)
            if let starting = startsUnderWay[root] {
                startsToWaitFor.append(starting)
            }
        }
        for show in ending {
            await stop(show, reason: .stopPressed)
        }
        // A start under way stops itself, listener closed, before it ends.
        for starting in startsToWaitFor {
            _ = await starting.value
        }
    }

    /// Quitting: every show ends at once. The trail line is written here,
    /// synchronously, because the process is about to go; the counts are
    /// read without waiting for the listener's own work.
    func stopEverything() {
        let ending: [Show] = shows
        shows = []
        for show in ending {
            show.server.listener.cancel()
            let counts: (requests: Int, notFound: Int) = show.server.countsNow()
            DeployedFolderShows.noteStopped(.plantoirQuit, counts: counts, courseCode: show.courseCode, sectionNumber: show.sectionNumber)
        }
    }

    /// A listener ended without being asked. Our own Stop removes the
    /// show first, so this finds nothing then. Matched on the server, not
    /// the folder: a late word from an old listener of the folder must not
    /// stop a newer show of it (#1013's review).
    func theListenerEnded(server: DeployedFolderServer) async {
        for show in shows where show.server === server {
            await stop(show, reason: .endedOnItsOwn)
        }
    }

    /// A server found its folder gone; matched on the server, as above.
    func theFolderWentAway(server: DeployedFolderServer) async {
        for show in shows where show.server === server {
            await stop(show, reason: .folderGone)
        }
    }

    static func noteStopped(_ reason: StopReason, counts: (requests: Int, notFound: Int), courseCode: String, sectionNumber: Int) {
        ActivityTrail.note(
            .deployedFolderNoLongerShown,
            stoppedLine(reason, requests: counts.requests, notFound: counts.notFound),
            course: courseCode, section: sectionNumber
        )
    }

    /// Tests only: ends every show without a trail line.
    func resetForTests() {
        for show in shows {
            show.server.listener.cancel()
        }
        shows = []
        stoppedBecauseTheFolderWentAway = []
        stopsAskedForWhileStarting = []
        stopsUnderWay = [:]
        stopIsWaitingForTests = nil
    }
}
