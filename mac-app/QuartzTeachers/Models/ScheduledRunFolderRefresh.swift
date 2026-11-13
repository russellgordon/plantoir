import Foundation

/// A scheduled deploy brings its working folder's launchers and `.toolchain/`
/// up to date before it runs them (#748 part 4).
///
/// The run is this app's own binary (`--run-scheduled-deploy`), so it carries
/// the tools of the version installed NOW. Until #748 it never copied them
/// into the folder: the window does that when it opens a folder
/// (`refreshLaunchersIfNeeded`), so after an update installed overnight a
/// 6:30 deploy in a folder nobody had opened since ran the launchers and the
/// recipe of the version that last touched it, and so built with the old
/// website builder.
///
/// **The decision is a table, and the table is the contract**
/// (`contracts/shared-rules.json` → `scheduledRunGetsItsFolderReady`): the
/// run goes ahead in EVERY case, and the trail says which case it was. A
/// deploy that silently does not happen at 6:30 is the worst outcome there
/// is; a deploy that goes ahead with the tools as they were, and says so, is
/// better, and its build and its destinations still record their own
/// failures and send the notification if they fail.
///
/// **The guard is Windows' marker** (`ToolchainCopyMarker`): this copy writes
/// one while it runs, and the run waits for another program's live copy
/// before its own and again before its launchers start, for up to five
/// minutes in all.
nonisolated enum ScheduledRunFolderRefresh {

    // MARK: - Types

    /// What the refresh found and did.
    struct Report: Equatable, Sendable {

        // MARK: - Stored properties

        /// The folder has `preview.sh`, so it is a working folder at all.
        var isAWorkingFolder: Bool = true

        /// The app's bundle has the recipe to copy (a `Dockerfile` at its
        /// root). Mirroring from a bundle without one would REMOVE the
        /// folder's tools, since the mirror deletes what its source lacks.
        var appCarriesTheTools: Bool = true

        /// The launchers at the folder's top that were replaced, and those
        /// that could not be.
        var launchersRefreshed: [String] = []
        var launchersFailed: [String] = []

        /// The `.toolchain/` mirror's own outcome.
        var tools: WorkspaceModel.MirrorOutcome = WorkspaceModel.MirrorOutcome()

        /// How long the copy itself took.
        var seconds: TimeInterval = 0

        /// How long the run waited for another program's copy, in all, and
        /// for which process (the last one seen).
        var waited: TimeInterval = 0
        var waitedFor: Int32? = nil

        /// Another program's copy was still running when the wait ran out.
        var stoppedWaiting: Bool = false
    }

    /// Which sentence the trail gets: the contract's `line` values.
    enum Line: String, Equatable, Sendable {
        case none
        case broughtUpToDate
        case alreadyUpToDate
        /// It stopped waiting for another program's copy and its own found
        /// nothing to change. Not "already up to date": the other copy may
        /// still be changing the folder (the 748b review's LOW 4).
        case foundNothingToChange
        case couldNotFinish
        case appCarriesNoTools
    }

    /// What the run does with a report.
    struct Decision: Equatable, Sendable {

        // MARK: - Stored properties

        let goesAhead: Bool
        let line: Line
        let saysItWaited: Bool
        let saysItStoppedWaiting: Bool
        let saysTheBuilderIsBuiltAgain: Bool
    }

    // MARK: - Stored properties

    /// The longest the run waits for other programs' copies, before and after
    /// its own together. A copy of the whole recipe into an empty folder took
    /// 4.1 to 4.7 s on an M4 Pro and 10.6 to 14.3 s at background priority
    /// (#748, documentation/09-mac-app.md), so five minutes is a copy that
    /// is stuck, not one that is slow.
    static let longestWaitForAnotherCopy: TimeInterval = 5 * 60

    /// How often the run looks again while it waits.
    static let lookEvery: TimeInterval = 1

    /// The launchers at a working folder's top that the run brings up to
    /// date, as the window does (`refreshLaunchersIfNeeded`).
    static let launcherNames: [String] = ["setup.sh", "preview.sh", "deploy.sh"]

    /// The trail's sentences, word for word the contract's
    /// (`activityTrail.mustRecord` → "scheduled deploy got its folder ready").
    static let broughtUpToDateLine: String = "a scheduled deploy copied {n} file(s) of Plantoir's tools into the working folder first, in {seconds} s{builder}, and went ahead"
    static let builderClause: String = ", so the website builder is built again for them unless this version of Plantoir has built it already"
    static let alreadyUpToDateLine: String = "a scheduled deploy found the working folder's tools already up to date, and went ahead"
    static let foundNothingToChangeLine: String = "a scheduled deploy found nothing of its own to change in the working folder's tools, and went ahead"
    static let couldNotFinishLine: String = "a scheduled deploy could not bring all of the working folder's tools up to date ({failed} file(s) could not be copied or removed, {n} brought up to date, first: {first}){builder}, and went ahead with them as they were"
    static let appCarriesNoToolsLine: String = "a scheduled deploy found none of Plantoir's own tools to bring the working folder up to date with, and went ahead with the folder's tools as they were"
    static let waitedClause: String = "; it first waited {waited} seconds for another program (process {pid}) to finish getting the working folder ready"
    static let stoppedWaitingClause: String = "; it stopped waiting after {waited} seconds for another program (process {pid}) that was still getting the working folder ready"

    // MARK: - Functions: the decision

    /// The table: what the run does, and which sentence it writes.
    static func decide(_ report: Report) -> Decision {
        var line: Line = .none
        let failed: Int = report.tools.failed + report.launchersFailed.count
        let changed: Int = report.tools.changed + report.launchersRefreshed.count
        let waitedAtAll: Bool = report.waitedFor != nil
        if !report.isAWorkingFolder {
            line = .none
        } else if !report.appCarriesTheTools {
            line = .appCarriesNoTools
        } else if failed > 0 {
            line = .couldNotFinish
        } else if changed > 0 {
            line = .broughtUpToDate
        } else if report.stoppedWaiting {
            line = .foundNothingToChange
        } else if waitedAtAll {
            line = .alreadyUpToDate
        }
        var saysItWaited: Bool = false
        var saysItStoppedWaiting: Bool = false
        if line != .none && waitedAtAll {
            if report.stoppedWaiting {
                saysItStoppedWaiting = true
            } else {
                saysItWaited = true
            }
        }
        return Decision(
            goesAhead: true,
            line: line,
            saysItWaited: saysItWaited,
            saysItStoppedWaiting: saysItStoppedWaiting,
            saysTheBuilderIsBuiltAgain: line != .none && report.tools.changed > 0
        )
    }

    /// The trail's sentence for a report, without the course and section, or
    /// nil when there is nothing to say: the folder was already up to date
    /// and nothing was waited for, which is every run but the first after an
    /// update.
    static func trailLine(for report: Report) -> String? {
        let decision: Decision = ScheduledRunFolderRefresh.decide(report)
        let changed: Int = report.tools.changed + report.launchersRefreshed.count
        let failed: Int = report.tools.failed + report.launchersFailed.count
        var builder: String = ""
        if decision.saysTheBuilderIsBuiltAgain {
            builder = builderClause
        }
        var sentence: String
        switch decision.line {
        case .none:
            return nil
        case .broughtUpToDate:
            sentence = broughtUpToDateLine
                .replacingOccurrences(of: "{n}", with: String(changed))
                .replacingOccurrences(of: "{seconds}", with: String(format: "%.1f", report.seconds))
                .replacingOccurrences(of: "{builder}", with: builder)
        case .alreadyUpToDate:
            sentence = alreadyUpToDateLine
        case .foundNothingToChange:
            sentence = foundNothingToChangeLine
        case .couldNotFinish:
            var first: String = report.tools.firstFailure ?? ""
            if first.isEmpty, let launcher = report.launchersFailed.first {
                first = launcher + ": could not be replaced"
            }
            sentence = couldNotFinishLine
                .replacingOccurrences(of: "{failed}", with: String(failed))
                .replacingOccurrences(of: "{n}", with: String(changed))
                .replacingOccurrences(of: "{first}", with: first)
                .replacingOccurrences(of: "{builder}", with: builder)
        case .appCarriesNoTools:
            sentence = appCarriesNoToolsLine
        }
        if let pid = report.waitedFor {
            let seconds: String = String(Int(report.waited.rounded()))
            if decision.saysItStoppedWaiting {
                sentence += stoppedWaitingClause
                    .replacingOccurrences(of: "{waited}", with: seconds)
                    .replacingOccurrences(of: "{pid}", with: String(pid))
            } else if decision.saysItWaited {
                sentence += waitedClause
                    .replacingOccurrences(of: "{waited}", with: seconds)
                    .replacingOccurrences(of: "{pid}", with: String(pid))
            }
        }
        return sentence
    }

    // MARK: - Functions: the refresh

    /// Brings the working folder's launchers and `.toolchain/` up to date
    /// from `resourcesURL` (the app's own bundle; the tests pass a folder),
    /// waiting for any other program's copy first and again afterwards.
    ///
    /// The order is the window's: the launchers, then the recipe. Never
    /// throws and never refuses: the report says what happened, and the run
    /// goes ahead whatever it says (`decide`).
    static func bringUpToDate(
        workingFolder workingFolderURL: URL,
        from resourcesURL: URL? = Bundle.main.resourceURL,
        indexFolder: URL = ToolchainFingerprints.indexFolder(),
        now: () -> Date = { () -> Date in return Date() },
        pause: (TimeInterval) -> Void = { (seconds: TimeInterval) -> Void in Thread.sleep(forTimeInterval: seconds) },
        othersCopying: ((URL) -> [ToolchainCopyMarker.Holding])? = nil
    ) -> Report {
        var report: Report = Report()
        let fileManager: FileManager = FileManager.default
        if !fileManager.fileExists(atPath: workingFolderURL.appendingPathComponent("preview.sh").path) {
            report.isAWorkingFolder = false
            return report
        }
        guard let resourcesURL,
              fileManager.fileExists(atPath: resourcesURL.appendingPathComponent("Dockerfile").path) else {
            report.appCarriesTheTools = false
            return report
        }

        let started: Date = now()
        ScheduledRunFolderRefresh.waitForOtherCopies(
            in: workingFolderURL, since: started, report: &report,
            now: now, pause: pause, othersCopying: othersCopying
        )

        let marker: URL? = ToolchainCopyMarker.write(inWorkingFolder: workingFolderURL)
        let copyStarted: Date = now()
        var sources: [String: URL] = [:]
        for name in launcherNames {
            let sourceURL: URL = resourcesURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: sourceURL.path) {
                sources[name] = sourceURL
            }
        }
        let launchers: WorkspaceModel.LauncherRefresh = WorkspaceModel.refreshLaunchersReporting(
            in: workingFolderURL, from: sources
        )
        report.launchersRefreshed = launchers.refreshed
        report.launchersFailed = launchers.failed
        report.tools = WorkspaceModel.copyToolchainFiles(
            into: workingFolderURL, from: resourcesURL, indexFolder: indexFolder
        )
        report.seconds = now().timeIntervalSince(copyStarted)
        ToolchainCopyMarker.remove(at: marker)

        // Again before the launchers start: a window opened during this copy
        // copies too, and its copy must be over before anything hashes the
        // recipe. It finds nothing to change, so this is usually a second.
        ScheduledRunFolderRefresh.waitForOtherCopies(
            in: workingFolderURL, since: started, report: &report,
            now: now, pause: pause, othersCopying: othersCopying
        )
        return report
    }

    /// Waits while another program's copy into the folder is live, until
    /// `longestWaitForAnotherCopy` has passed since `started`.
    private static func waitForOtherCopies(
        in workingFolderURL: URL,
        since started: Date,
        report: inout Report,
        now: () -> Date,
        pause: (TimeInterval) -> Void,
        othersCopying: ((URL) -> [ToolchainCopyMarker.Holding])?
    ) {
        if report.stoppedWaiting {
            return
        }
        while true {
            var others: [ToolchainCopyMarker.Holding]
            if let othersCopying {
                others = othersCopying(workingFolderURL)
            } else {
                others = ToolchainCopyMarker.othersCopying(inWorkingFolder: workingFolderURL)
            }
            guard let other = others.first else {
                return
            }
            let looked: Date = now()
            report.waitedFor = other.pid
            if looked.timeIntervalSince(started) >= longestWaitForAnotherCopy {
                report.stoppedWaiting = true
                return
            }
            pause(lookEvery)
            report.waited += now().timeIntervalSince(looked)
        }
    }
}
