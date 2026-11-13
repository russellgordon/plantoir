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

    /// Tests only: shows counted as open without a listener, for the quit
    /// case.
    var pretendShownForTests: Int = 0

    // MARK: - Computed properties

    /// How many are shown, for the quit rule.
    var shownCount: Int {
        return shows.count + pretendShownForTests
    }

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
        for show in shows where show.id == canonicalRoot {
            ActivityTrail.note(
                .deployedFolderOpened, "opened the deployed folder in the web browser (\(from.rawValue), already open)",
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
        let remembered: Int? = DeployedFolderAddress.rememberedPort(forCanonicalPath: canonicalRoot, defaults: defaults)
        let candidates: [Int] = DeployedFolderAddress.candidates(forCanonicalPath: canonicalRoot, remembered: remembered)
        let root: URL = URL(fileURLWithPath: canonicalRoot)
        let started: (server: DeployedFolderServer, firstWasTaken: Bool)
        do {
            started = try await DeployedFolderServer.start(root: root, candidates: candidates) {
                Task { @MainActor in
                    DeployedFolderShows.shared.theFolderWentAway(canonicalRoot: canonicalRoot)
                }
            }
        } catch {
            noteCouldNotOpen(.noFreeAddress, courseCode: courseCode, sectionNumber: sectionNumber)
            return false
        }
        DeployedFolderAddress.remember(port: started.server.port, forCanonicalPath: canonicalRoot, defaults: defaults)
        let show: Show = Show(
            id: canonicalRoot, courseCode: courseCode, sectionNumber: sectionNumber,
            workingFolderPath: workingFolderPath, root: root, port: started.server.port, server: started.server
        )
        shows.append(show)
        var what: String = "opened the deployed folder in the web browser (\(from.rawValue))"
        if started.firstWasTaken {
            what = "opened the deployed folder in the web browser (\(from.rawValue), at a different address because its usual one was taken, so what the site remembered there is not shown)"
        }
        ActivityTrail.note(.deployedFolderOpened, what, course: courseCode, section: sectionNumber)
        return handOver(show, courseCode: courseCode, sectionNumber: sectionNumber, openInBrowser: openInBrowser)
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
            .deployedFolderCouldNotBeOpened, "could not open the deployed folder in the web browser — \(why.rawValue)",
            course: courseCode, section: sectionNumber
        )
    }

    /// Stops showing one folder.
    func stop(_ show: Show, reason: StopReason) {
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
        Task {
            let counts: (requests: Int, notFound: Int) = await server.counts()
            await server.stop()
            DeployedFolderShows.noteStopped(reason, counts: counts, courseCode: courseCode, sectionNumber: sectionNumber)
        }
    }

    /// Stop on a section: the notice's button and the menu item.
    func stop(courseCode: String, sectionNumber: Int, workingFolderPath: String) {
        if let show = show(courseCode: courseCode, sectionNumber: sectionNumber, workingFolderPath: workingFolderPath) {
            stop(show, reason: .stopPressed)
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

    /// The server found its folder gone.
    func theFolderWentAway(canonicalRoot: String) {
        for show in shows where show.id == canonicalRoot {
            stop(show, reason: .folderGone)
        }
    }

    static func noteStopped(_ reason: StopReason, counts: (requests: Int, notFound: Int), courseCode: String, sectionNumber: Int) {
        ActivityTrail.note(
            .deployedFolderNoLongerShown,
            "stopped showing the deployed folder in the web browser — \(reason.rawValue) (\(counts.requests) requests, \(counts.notFound) not found)",
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
        pretendShownForTests = 0
    }
}
