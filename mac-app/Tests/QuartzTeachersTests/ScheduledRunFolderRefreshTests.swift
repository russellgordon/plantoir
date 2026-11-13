import XCTest
@testable import QuartzTeachers

/// A scheduled deploy brings its working folder's launchers and `.toolchain/`
/// up to date before it runs them (#748 part 4). The decision is
/// `contracts/shared-rules.json` → `scheduledRunGetsItsFolderReady`, and the
/// trail's words are `activityTrail.mustRecord` → "scheduled deploy got its
/// folder ready".
///
/// Real folders under the suite's made-up home (`RealHome.forFiles`), never the teacher's: a pretend bundle
/// and a pretend working folder, and the run's waits driven by a pretend
/// clock and a pretend list of other copies. Nothing is scheduled, and no
/// launcher runs.
@MainActor
final class ScheduledRunFolderRefreshTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")

    // MARK: - Set up

    override func setUp() {
        super.setUp()
        // The suite's own made-up home, never the teacher's (RealHomeTripwireTests).
        root = RealHome.forFiles
            .appendingPathComponent("plantoir-run-refresh-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let created: URL = root
        addTeardownBlock {
            try? FileManager.default.removeItem(at: created)
        }
    }

    // MARK: - The contract's table

    /// Every case, through the one decision the run makes; and the sentence it
    /// writes is the contract's, with exactly the clauses the case names.
    func testEveryCaseGoesAheadAndSaysWhatTheContractSays() throws {
        let rule: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["scheduledRunGetsItsFolderReady"])
        let cases: [[String: Any]] = try XCTUnwrap(rule["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 14)
        let lines: [String: String] = try ScheduledRunFolderRefreshTests.contractLines()
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = try XCTUnwrap(testCase["given"] as? [String: Any])
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let report: ScheduledRunFolderRefresh.Report = try ScheduledRunFolderRefreshTests.report(from: given)

            let decision: ScheduledRunFolderRefresh.Decision = ScheduledRunFolderRefresh.decide(report)
            XCTAssertEqual(decision.goesAhead, try XCTUnwrap(expect["goesAhead"] as? Bool), name)
            XCTAssertEqual(decision.line.rawValue, try XCTUnwrap(expect["line"] as? String), name)
            XCTAssertEqual(decision.saysItWaited, try XCTUnwrap(expect["saysItWaited"] as? Bool), name)
            XCTAssertEqual(decision.saysItStoppedWaiting, try XCTUnwrap(expect["saysItStoppedWaiting"] as? Bool), name)
            XCTAssertEqual(
                decision.saysTheBuilderIsBuiltAgain, try XCTUnwrap(expect["saysTheBuilderIsBuiltAgain"] as? Bool), name
            )

            let sentence: String? = ScheduledRunFolderRefresh.trailLine(for: report)
            if decision.line == .none {
                XCTAssertNil(sentence, name)
                continue
            }
            let written: String = try XCTUnwrap(sentence, name)
            let template: String = try XCTUnwrap(lines[decision.line.rawValue], name)
            let opening: String = String(template.prefix(while: { (character: Character) -> Bool in
                return character != "{"
            }))
            XCTAssertTrue(written.hasPrefix(opening), "\(name): \(written)")
            let builder: String = try XCTUnwrap(lines["builderClause"])
            XCTAssertEqual(written.contains(builder), decision.saysTheBuilderIsBuiltAgain, "\(name): \(written)")
            let waitedOpening: String = try ScheduledRunFolderRefreshTests.opening(of: "waitedClause", in: lines)
            let stoppedOpening: String = try ScheduledRunFolderRefreshTests.opening(of: "stoppedWaitingClause", in: lines)
            XCTAssertEqual(written.contains(waitedOpening), decision.saysItWaited, "\(name): \(written)")
            XCTAssertEqual(written.contains(stoppedOpening), decision.saysItStoppedWaiting, "\(name): \(written)")
            XCTAssertFalse(written.contains("{"), "\(name): a placeholder was left in \(written)")
            // MUST FAIL before the 748b fix round (LOW 4): a run that stopped
            // waiting for another copy cannot know the folder is up to date.
            if decision.saysItStoppedWaiting {
                XCTAssertFalse(written.contains("already up to date"), "\(name): \(written)")
                XCTAssertNotEqual(decision.line, .alreadyUpToDate, name)
            }
        }
    }

    /// The Swift's sentences are the contract's, word for word.
    func testTheSentencesAreTheContracts() throws {
        let lines: [String: String] = try ScheduledRunFolderRefreshTests.contractLines()
        XCTAssertEqual(lines["broughtUpToDate"], ScheduledRunFolderRefresh.broughtUpToDateLine)
        XCTAssertEqual(lines["builderClause"], ScheduledRunFolderRefresh.builderClause)
        XCTAssertEqual(lines["alreadyUpToDate"], ScheduledRunFolderRefresh.alreadyUpToDateLine)
        XCTAssertEqual(lines["foundNothingToChange"], ScheduledRunFolderRefresh.foundNothingToChangeLine)
        XCTAssertEqual(lines["couldNotFinish"], ScheduledRunFolderRefresh.couldNotFinishLine)
        XCTAssertEqual(lines["appCarriesNoTools"], ScheduledRunFolderRefresh.appCarriesNoToolsLine)
        XCTAssertEqual(lines["waitedClause"], ScheduledRunFolderRefresh.waitedClause)
        XCTAssertEqual(lines["stoppedWaitingClause"], ScheduledRunFolderRefresh.stoppedWaitingClause)
        XCTAssertEqual(lines.count, 8, "a sentence in the contract that the Swift does not write")
    }

    // MARK: - The refresh, on real folders

    /// MUST FAIL before #748: a folder last touched by an earlier version gets
    /// this version's launchers and recipe, a file the new recipe dropped is
    /// removed, and the folder's courses are not touched.
    func testAFolderAnEarlierVersionLeftIsBroughtUpToDate() throws {
        let bundle: URL = try makeBundle(version: "new")
        let folder: URL = try makeWorkingFolder(launcherVersion: "old")
        try write("old recipe", to: folder.appendingPathComponent(".toolchain/scripts/build_site.py"))
        try write("dropped", to: folder.appendingPathComponent(".toolchain/scripts/dropped.py"))
        try write("my page", to: folder.appendingPathComponent("courses/ICS3U/page.md"))

        let report: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.bringUpToDate(
            workingFolder: folder, from: bundle, indexFolder: root.appendingPathComponent("index"),
            othersCopying: { (url: URL) -> [ToolchainCopyMarker.Holding] in return [] }
        )

        XCTAssertEqual(report.launchersRefreshed, ["deploy.sh", "preview.sh", "setup.sh"])
        XCTAssertEqual(report.launchersFailed, [])
        XCTAssertEqual(report.tools.failed, 0)
        for name in ["setup.sh", "preview.sh", "deploy.sh"] {
            XCTAssertEqual(try read(folder.appendingPathComponent(name)), "# new \(name)\n", name)
            XCTAssertEqual(try read(folder.appendingPathComponent(".toolchain/\(name)")), "# new \(name)\n", name)
        }
        XCTAssertEqual(try read(folder.appendingPathComponent(".toolchain/Dockerfile")), "FROM new\n")
        XCTAssertEqual(try read(folder.appendingPathComponent(".toolchain/scripts/build_site.py")), "new recipe\n")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(".toolchain/scripts/dropped.py").path
        ))
        XCTAssertEqual(try read(folder.appendingPathComponent("courses/ICS3U/page.md")), "my page")
        let line: String = try XCTUnwrap(ScheduledRunFolderRefresh.trailLine(for: report))
        XCTAssertTrue(line.contains(ScheduledRunFolderRefresh.builderClause), line)

        // The next run finds nothing to do, says nothing, and leaves no marker.
        let again: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.bringUpToDate(
            workingFolder: folder, from: bundle, indexFolder: root.appendingPathComponent("index"),
            othersCopying: { (url: URL) -> [ToolchainCopyMarker.Holding] in return [] }
        )
        XCTAssertEqual(again.launchersRefreshed, [])
        XCTAssertEqual(again.tools.changed, 0)
        XCTAssertNil(ScheduledRunFolderRefresh.trailLine(for: again))
        XCTAssertEqual(ToolchainCopyMarker.othersCopying(inWorkingFolder: folder, ownPID: -1, ownerIsAlive: { (pid: Int32, name: String?, start: String?) -> Bool in
            return true
        }), [], "the run's marker was left behind")
    }

    /// A bundle with no recipe at its root copies nothing and removes
    /// nothing: the mirror deletes what its source lacks, so mirroring from it
    /// would empty the folder's tools.
    func testABundleWithNoRecipeLeavesTheFolderAlone() throws {
        let bundle: URL = root.appendingPathComponent("empty bundle")
        try write("# new deploy.sh\n", to: bundle.appendingPathComponent("deploy.sh"))
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        let folder: URL = try makeWorkingFolder(launcherVersion: "old")
        try write("old recipe", to: folder.appendingPathComponent(".toolchain/scripts/build_site.py"))

        let report: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.bringUpToDate(
            workingFolder: folder, from: bundle, indexFolder: root.appendingPathComponent("index"),
            othersCopying: { (url: URL) -> [ToolchainCopyMarker.Holding] in return [] }
        )
        XCTAssertFalse(report.appCarriesTheTools)
        XCTAssertEqual(try read(folder.appendingPathComponent("deploy.sh")), "# old deploy.sh\n")
        XCTAssertEqual(try read(folder.appendingPathComponent(".toolchain/scripts/build_site.py")), "old recipe")
        XCTAssertEqual(ScheduledRunFolderRefresh.decide(report).line, .appCarriesNoTools)

        let none: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.bringUpToDate(
            workingFolder: folder, from: nil, indexFolder: root.appendingPathComponent("index"),
            othersCopying: { (url: URL) -> [ToolchainCopyMarker.Holding] in return [] }
        )
        XCTAssertFalse(none.appCarriesTheTools)
    }

    /// A folder with no `preview.sh` is not a working folder: nothing is
    /// written into it.
    func testAFolderThatIsNotAWorkingFolderIsLeftAlone() throws {
        let bundle: URL = try makeBundle(version: "new")
        let folder: URL = root.appendingPathComponent("not a working folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let report: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.bringUpToDate(
            workingFolder: folder, from: bundle, indexFolder: root.appendingPathComponent("index"),
            othersCopying: { (url: URL) -> [ToolchainCopyMarker.Holding] in return [] }
        )
        XCTAssertFalse(report.isAWorkingFolder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".toolchain").path))
        XCTAssertNil(ScheduledRunFolderRefresh.trailLine(for: report))
    }

    /// A folder that will not take the files: the copy is counted as failed,
    /// the run still goes ahead, and the line says it went ahead with the
    /// tools as they were.
    func testAFolderThatCannotBeWrittenGoesAheadAndSaysSo() throws {
        let bundle: URL = try makeBundle(version: "new")
        let folder: URL = try makeWorkingFolder(launcherVersion: "old")
        try write("old recipe", to: folder.appendingPathComponent(".toolchain/scripts/build_site.py"))
        let locked: [URL] = [folder, folder.appendingPathComponent(".toolchain"), folder.appendingPathComponent(".toolchain/scripts")]
        for url in locked {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
        }
        addTeardownBlock {
            for url in locked {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }

        let report: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.bringUpToDate(
            workingFolder: folder, from: bundle, indexFolder: root.appendingPathComponent("index"),
            othersCopying: { (url: URL) -> [ToolchainCopyMarker.Holding] in return [] }
        )
        XCTAssertEqual(report.launchersFailed, ["deploy.sh", "preview.sh", "setup.sh"])
        XCTAssertGreaterThan(report.tools.failed, 0)
        let decision: ScheduledRunFolderRefresh.Decision = ScheduledRunFolderRefresh.decide(report)
        XCTAssertTrue(decision.goesAhead)
        XCTAssertEqual(decision.line, .couldNotFinish)
        XCTAssertEqual(try read(folder.appendingPathComponent("deploy.sh")), "# old deploy.sh\n", "the old launcher is still whole")
        let line: String = try XCTUnwrap(ScheduledRunFolderRefresh.trailLine(for: report))
        XCTAssertTrue(line.hasSuffix("and went ahead with them as they were"), line)
    }

    /// MUST FAIL before the 748b fix round (LOW 5): a launcher that cannot
    /// be read is counted as failed, not skipped, so the run never calls a
    /// folder it could not compare up to date.
    func testALauncherThatCannotBeReadIsCountedAsFailed() throws {
        let bundle: URL = try makeBundle(version: "new")
        let folder: URL = try makeWorkingFolder(launcherVersion: "old")
        let unreadable: URL = folder.appendingPathComponent("deploy.sh")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
        }
        var sources: [String: URL] = [:]
        for name in ["setup.sh", "preview.sh", "deploy.sh"] {
            sources[name] = bundle.appendingPathComponent(name)
        }
        let refresh: WorkspaceModel.LauncherRefresh = WorkspaceModel.refreshLaunchersReporting(in: folder, from: sources)
        XCTAssertEqual(refresh.failed, ["deploy.sh"])
        XCTAssertEqual(refresh.refreshed, ["preview.sh", "setup.sh"])
    }

    // MARK: - The guard

    /// Another program's copy is waited for BEFORE the run's own copy and
    /// AGAIN after it, and the run then goes ahead and says it waited.
    func testAnotherProgramsCopyIsWaitedForBeforeAndAfter() throws {
        let bundle: URL = try makeBundle(version: "new")
        let folder: URL = try makeWorkingFolder(launcherVersion: "old")
        var clock: TimeInterval = 0
        var looks: [String] = []
        let report: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.bringUpToDate(
            workingFolder: folder, from: bundle, indexFolder: root.appendingPathComponent("index"),
            now: { () -> Date in return Date(timeIntervalSince1970: clock) },
            pause: { (seconds: TimeInterval) -> Void in clock += seconds },
            othersCopying: { (url: URL) -> [ToolchainCopyMarker.Holding] in
                let copied: Bool = FileManager.default.fileExists(
                    atPath: folder.appendingPathComponent(".toolchain/Dockerfile").path
                )
                looks.append(copied ? "after" : "before")
                // Two looks see a copy before the run's own; one after.
                var beforeCount: Int = 0
                var afterCount: Int = 0
                for look in looks {
                    if look == "before" {
                        beforeCount += 1
                    } else {
                        afterCount += 1
                    }
                }
                if !copied && beforeCount <= 2 {
                    return [ToolchainCopyMarker.Holding(pid: 4711, moment: nil)]
                }
                if copied && afterCount <= 1 {
                    return [ToolchainCopyMarker.Holding(pid: 4712, moment: nil)]
                }
                return []
            }
        )
        XCTAssertEqual(looks, ["before", "before", "before", "after", "after"])
        XCTAssertEqual(report.waited, 3)
        XCTAssertEqual(report.waitedFor, 4712)
        XCTAssertFalse(report.stoppedWaiting)
        XCTAssertEqual(try read(folder.appendingPathComponent("deploy.sh")), "# new deploy.sh\n")
        let line: String = try XCTUnwrap(ScheduledRunFolderRefresh.trailLine(for: report))
        XCTAssertTrue(line.contains("waited 3 seconds for another program (process 4712)"), line)
    }

    /// A copy that never ends is waited for five minutes, no more, and then
    /// the run copies and goes ahead anyway.
    func testACopyThatNeverEndsIsWaitedForFiveMinutesThenTheRunGoesAhead() throws {
        XCTAssertEqual(ScheduledRunFolderRefresh.longestWaitForAnotherCopy, 300)
        let bundle: URL = try makeBundle(version: "new")
        let folder: URL = try makeWorkingFolder(launcherVersion: "old")
        var clock: TimeInterval = 0
        var lastPause: TimeInterval = -1
        let report: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.bringUpToDate(
            workingFolder: folder, from: bundle, indexFolder: root.appendingPathComponent("index"),
            now: { () -> Date in return Date(timeIntervalSince1970: clock) },
            pause: { (seconds: TimeInterval) -> Void in
                lastPause = clock
                clock += seconds
            },
            othersCopying: { (url: URL) -> [ToolchainCopyMarker.Holding] in
                return [ToolchainCopyMarker.Holding(pid: 4711, moment: nil)]
            }
        )
        XCTAssertTrue(report.stoppedWaiting)
        XCTAssertEqual(report.waited, 300)
        XCTAssertEqual(lastPause, 299, "it looked for the last time before five minutes were up")
        XCTAssertEqual(try read(folder.appendingPathComponent("deploy.sh")), "# new deploy.sh\n", "it copied anyway")
        let decision: ScheduledRunFolderRefresh.Decision = ScheduledRunFolderRefresh.decide(report)
        XCTAssertTrue(decision.goesAhead)
        XCTAssertTrue(decision.saysItStoppedWaiting)
    }

    /// The marker: written only where `courses/` exists, read back by another
    /// process as a live copy, never by its own writer, ignored once its
    /// writer is gone, and never confused with an atomic write's temporary
    /// file.
    func testTheMarkerIsWindowsAndIsReadAsWindowsReadsIt() throws {
        let folder: URL = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertNil(ToolchainCopyMarker.write(inWorkingFolder: folder), "no courses folder, no marker")

        try FileManager.default.createDirectory(at: folder.appendingPathComponent("courses"), withIntermediateDirectories: true)
        let marker: URL = try XCTUnwrap(ToolchainCopyMarker.write(inWorkingFolder: folder))
        XCTAssertEqual(
            marker.path,
            folder.appendingPathComponent("courses/.internal/activity/toolchain-copying.\(getpid())").path
        )
        XCTAssertEqual(ToolchainCopyMarker.othersCopying(inWorkingFolder: folder), [], "never in its own way")

        let seen: [ToolchainCopyMarker.Holding] = ToolchainCopyMarker.othersCopying(
            inWorkingFolder: folder, ownPID: -1,
            ownerIsAlive: { (pid: Int32, name: String?, start: String?) -> Bool in return pid == getpid() }
        )
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen.first?.pid, getpid())
        let gone: [ToolchainCopyMarker.Holding] = ToolchainCopyMarker.othersCopying(
            inWorkingFolder: folder, ownPID: -1,
            ownerIsAlive: { (pid: Int32, name: String?, start: String?) -> Bool in return false }
        )
        XCTAssertEqual(gone, [])

        XCTAssertNil(ToolchainCopyMarker.pid(ofMarkerNamed: "toolchain-copying.4711.sb-dab6e658-OsWVR7"))
        XCTAssertNil(ToolchainCopyMarker.pid(ofMarkerNamed: "toolchain-copying."))
        XCTAssertNil(ToolchainCopyMarker.pid(ofMarkerNamed: "ICS3U.build.4711.lease"))
        XCTAssertEqual(ToolchainCopyMarker.pid(ofMarkerNamed: "toolchain-copying.4711"), 4711)

        ToolchainCopyMarker.remove(at: marker)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    /// MUST FAIL before #748: a stray file another copy removed first is not
    /// a failure. Two copies started at once counted 18 or 19 of these as
    /// failed in every run after an update, and a failed copy greys Preview.
    func testAStrayFileAlreadyGoneIsNotAFailure() throws {
        let gone: URL = root.appendingPathComponent("never there.txt")
        XCTAssertEqual(WorkspaceModel.removeStrayFile(gone), .alreadyGone)

        let present: URL = root.appendingPathComponent("stray.txt")
        try write("stray", to: present)
        XCTAssertEqual(WorkspaceModel.removeStrayFile(present), .removed)

        let lockedFolder: URL = root.appendingPathComponent("locked")
        let kept: URL = lockedFolder.appendingPathComponent("kept.txt")
        try write("kept", to: kept)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedFolder.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedFolder.path)
        }
        guard case .failed = WorkspaceModel.removeStrayFile(kept) else {
            XCTFail("a file that is still there and will not go is a failure")
            return
        }
    }

    // MARK: - Where it sits in the run

    /// `runScheduled` never returns, so its order is read from the source:
    /// the refresh comes after the settings are read and the wrapper written,
    /// only on the branch that deploys, before the script runs; and its line
    /// is written under the event of its own.
    func testTheRunRefreshesOnlyWhenItWillDeployAndBeforeItsScriptRuns() throws {
        let body: String = try DeployWhileItsSectionDeploysTests.runScheduledSource()
        let reading: Range<String.Index> = try XCTUnwrap(body.range(of: "readAtTheRun("))
        let wrapper: Range<String.Index> = try XCTUnwrap(body.range(of: "writeTheRunsWrapper("))
        let runBranch: Range<String.Index> = try XCTUnwrap(body.range(of: "case .run:"))
        let refresh: Range<String.Index> = try XCTUnwrap(body.range(of: "ScheduledRunFolderRefresh.bringUpToDate("))
        let leave: Range<String.Index> = try XCTUnwrap(body.range(of: "case .leaveQuietly:"))
        let process: Range<String.Index> = try XCTUnwrap(body.range(of: "try process.run()"))
        XCTAssertLessThan(reading.lowerBound, wrapper.lowerBound)
        XCTAssertLessThan(wrapper.lowerBound, runBranch.lowerBound)
        XCTAssertLessThan(runBranch.lowerBound, refresh.lowerBound)
        XCTAssertLessThan(refresh.lowerBound, leave.lowerBound, "the refresh is on the deploying branch only")
        XCTAssertLessThan(refresh.lowerBound, process.lowerBound)
        let branch: String = String(body[refresh.lowerBound..<leave.lowerBound])
        XCTAssertTrue(branch.contains(".scheduledDeployGotItsFolderReady"), branch)
        var occurrences: Int = 0
        var searchRange: Range<String.Index> = body.startIndex..<body.endIndex
        while let found = body.range(of: "ScheduledRunFolderRefresh.bringUpToDate(", range: searchRange) {
            occurrences += 1
            searchRange = found.upperBound..<body.endIndex
        }
        XCTAssertEqual(occurrences, 1)
    }

    // MARK: - Helpers

    static func contractLines() throws -> [String: String] {
        let trail: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["activityTrail"])
        let events: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        for event in events {
            if event["event"] as? String == ActivityTrail.Event.scheduledDeployGotItsFolderReady.rawValue {
                return try XCTUnwrap(event["lines"] as? [String: String])
            }
        }
        XCTFail("no mustRecord entry for the event")
        return [:]
    }

    static func opening(of key: String, in lines: [String: String]) throws -> String {
        let template: String = try XCTUnwrap(lines[key])
        return String(template.prefix(while: { (character: Character) -> Bool in
            return character != "{"
        }))
    }

    static func report(from given: [String: Any]) throws -> ScheduledRunFolderRefresh.Report {
        var report: ScheduledRunFolderRefresh.Report = ScheduledRunFolderRefresh.Report()
        report.isAWorkingFolder = try XCTUnwrap(given["isAWorkingFolder"] as? Bool)
        report.appCarriesTheTools = try XCTUnwrap(given["appCarriesTheTools"] as? Bool)
        let refreshed: Int = try XCTUnwrap(given["launchersRefreshed"] as? Int)
        let failed: Int = try XCTUnwrap(given["launchersFailed"] as? Int)
        let names: [String] = ScheduledRunFolderRefresh.launcherNames
        var index: Int = 0
        while index < refreshed {
            report.launchersRefreshed.append(names[index])
            index += 1
        }
        index = 0
        while index < failed {
            report.launchersFailed.append(names[names.count - 1 - index])
            index += 1
        }
        report.tools.changed = try XCTUnwrap(given["toolsChanged"] as? Int)
        report.tools.failed = try XCTUnwrap(given["toolsFailed"] as? Int)
        if report.tools.failed > 0 {
            report.tools.firstFailure = "build_site.py: You don’t have permission."
        }
        report.seconds = 1.4
        if let pid = given["waitedFor"] as? Int {
            report.waitedFor = Int32(pid)
        }
        report.waited = try XCTUnwrap(given["waitedSeconds"] as? Double)
        report.stoppedWaiting = try XCTUnwrap(given["stoppedWaiting"] as? Bool)
        return report
    }

    /// A pretend app bundle: the three launchers and a small recipe.
    func makeBundle(version: String) throws -> URL {
        let bundle: URL = root.appendingPathComponent("bundle \(version)")
        for name in ["setup.sh", "preview.sh", "deploy.sh"] {
            try write("# \(version) \(name)\n", to: bundle.appendingPathComponent(name))
        }
        try write("FROM \(version)\n", to: bundle.appendingPathComponent("Dockerfile"))
        try write("\(version) recipe\n", to: bundle.appendingPathComponent("scripts/build_site.py"))
        try write("\(version) support\n", to: bundle.appendingPathComponent("support/readme.txt"))
        return bundle
    }

    /// A pretend working folder: launchers at its top and a courses folder.
    func makeWorkingFolder(launcherVersion: String) throws -> URL {
        let folder: URL = root.appendingPathComponent("working folder")
        for name in ["setup.sh", "preview.sh", "deploy.sh"] {
            try write("# \(launcherVersion) \(name)\n", to: folder.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("courses"), withIntermediateDirectories: true)
        return folder
    }

    func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }
}
