import XCTest
@testable import QuartzTeachers

/// Every write into a working folder will go through ONE door,
/// `JournaledWrite`, before Undo and Redo are switched on (#899, plan 3.3,
/// review 22). This scan reads ALL the product source (`Models`, `Views`,
/// `Scripting` and `App`) and fails on any file-writing call in a file that
/// is not on the list below, with as many calls as the list says: a new
/// writer, or a new call beside an allowed one, is red until somebody
/// decides whether it is a step. An entry nothing matches any more is red as
/// stale.
///
/// Three kinds of reason:
/// - `door`: the list itself (`Models/Undo`).
/// - `notAStep`: writes that are not a teacher's change (plan 7: the trail,
///   leases, the toolchain mirror, model downloads, problem reports, world
///   records and so on).
/// - `waitsFor`: a teacher's change not yet journaled, and the piece of
///   #899 that wires it. **The switch cannot flip (U7) while any
///   `waitsFor` remains**: `testTheSwitchStaysOffWhileWritersWait` says so.
///
/// What counts as a writing call (widened after U1's reviews, and again
/// after its second, the director's ruling 7): Foundation's writes, moves,
/// removals, copies, attribute and resource-value changes, links and the
/// Trash (`trashItem`, `NSWorkspace`'s `recycle`); a `FileHandle` opened for
/// writing; the C calls that write (`rename`, `link`, `unlink`, `mkdir`,
/// `chmod`, `truncate` and the like, and `open` with a flag that writes); and
/// a tool that writes run as a process (`/usr/bin/ditto`, `/bin/mv`,
/// `/bin/cp`, `/bin/rm` and the others in `writingTools`, a shell among
/// them); and a launcher named in quotes (`setup.sh`, `preview.sh`,
/// `deploy.sh`), so whoever starts one is listed with what it waits for
/// (the director's ruling 9 on U1's third round, which also added `rmdir`,
/// `remove`, `mkstemp`, `utimes`, the extended-attribute calls and
/// NSWorkspace's `duplicate`). A call split
/// across lines counts too: a line that ends in `(` is read together with
/// the next. The count is per file, so a file can swap one write for
/// another and stay green: the list says WHO writes, and a new writer is
/// what it catches.
final class UndoWriterScanTests: XCTestCase {

    // MARK: - Stored properties

    /// The calls that write, move or remove a file, as the text a line holds.
    static let writingCalls: [String] = [
        "write(to:",
        "write(toFile:",
        // With its dot, so `removeItem(` is not counted twice (it holds
        // `moveItem(`; found in U1's third round: every removal had been
        // counted as two writes).
        ".moveItem(",
        "removeItem(",
        "copyItem(",
        "replaceItemAt(",
        "replaceItem(at:",
        "createDirectory(",
        "createFile(",
        "trashItem(",
        "setAttributes(",
        "createSymbolicLink(",
        "linkItem(",
        "FileHandle(forWritingTo",
        "FileHandle(forWritingAtPath",
        "FileHandle(forUpdating",
        ".truncate(atOffset:",
        "renamex_np(",
        "copyfile(",
        "removefile(",
        "Darwin.rename(",
        "Darwin.link(",
        "Darwin.unlink(",
        "setResourceValues(",
        "recycle(",
        // NSWorkspace's copy beside the original.
        ".duplicate(",
    ]

    /// Tools that write, counted once on a line that names one by its path
    /// (`"/usr/bin/ditto"`, or `/bin/rm ` inside a script the app writes).
    ///
    /// A SHELL counts as a tool that writes (`/bin/bash`, `/bin/sh`,
    /// `/bin/zsh`): whatever it runs can write a course (the director's
    /// ruling 9 on U1's third round, after `ScriptRunner` ran `setup.sh`
    /// through `/bin/bash` uncounted).
    static let writingTools: [String] = [
        "ditto", "mv", "cp", "rm", "rsync", "unzip", "zip", "chmod", "chflags", "ln", "mkdir", "touch", "tar",
        "bash", "sh", "zsh",
    ]

    /// The launchers, which write course files themselves (`setup.sh` makes
    /// a course, `preview.sh` rewrites a course's `course_config.json`,
    /// `deploy.sh` writes the published-pages record and the site markers),
    /// counted once on a line that names one in quotes: whoever starts one
    /// is on the list with what it waits for (ruling 9).
    static let launchers: [String] = ["setup.sh", "preview.sh", "deploy.sh"]

    /// Where those tools live.
    static let toolFolders: [String] = ["/bin/", "/usr/bin/", "/sbin/", "/usr/sbin/"]

    /// C calls that write, counted only as a call of their own: not after a
    /// dot (`CourseRenamer.rename(`), not inside a longer name, and not where
    /// a function or a case of that name is declared.
    static let bareWritingCalls: [String] = [
        "rename",
        "link",
        "unlink",
        "symlink",
        "mkdir",
        "chmod",
        "fchmod",
        "chflags",
        "fchflags",
        "truncate",
        "ftruncate",
        "fopen",
        "rmdir",
        "remove",
        "mkstemp",
        "mkdtemp",
        "utimes",
        "futimes",
        "lutimes",
        "setxattr",
        "fsetxattr",
        "removexattr",
        "fremovexattr",
    ]

    /// `open(` counts once on a line that also names one of these flags.
    static let openForWritingFlags: [String] = ["O_WRONLY", "O_RDWR", "O_CREAT"]

    /// The product source folders scanned: all of them.
    static let scannedFolders: [String] = ["Models", "Views", "Scripting", "App"]

    /// Every file allowed to write, with how many writing calls it holds and
    /// why. Paths are under `QuartzTeachers/`.
    static let allowed: [String: (calls: Int, reason: String)] = [
        "App/ProblemReportCommands.swift": (5, "notAStep: a problem report, built and saved outside every course"),
        "App/QuartzTeachersApp.swift": (1, "notAStep: the app's own state folder for `--state-dir`"),
        "Models/AgentGuidance.swift": (2, "waitsFor: U4"),
        "Models/Assist/AppRulesContract.swift": (1, "notAStep: writes the contract files for `--write-contracts`, a developer's command"),
        "Models/Assist/AssistChangeHistory.swift": (2, "waitsFor: U7 (today's undo itself; kept as an adapter when the switch flips)"),
        "Models/Assist/AssistContract.swift": (2, "notAStep: writes the contract files for `--write-contracts`, a developer's command"),
        "Models/Assist/AssistCurriculumMentions.swift": (1, "waitsFor: U3"),
        "Models/Assist/AssistModelStore.swift": (7, "notAStep: the assistant's model download and removal (class D, plan 7)"),
        "Models/Assist/AssistPublishPlan.swift": (1, "waitsFor: U3"),
        "Models/Assist/AssistServerHost.swift": (5, "notAStep: the assistant's own launch files"),
        "Models/Assist/AssistSiteWork.swift": (1, "waitsFor: U4 (starts preview.sh, whose preflight rewrites a course's course_config.json outside the door)"),
        "Models/Assist/AssistToolRunner.swift": (2, "waitsFor: U3"),
        "Models/Assist/ClaudeCodeLauncher.swift": (4, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/Assist/CodexLauncher.swift": (2, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/Assist/CopilotLauncher.swift": (3, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/BuildOutputLocation.swift": (25, "notAStep: the built websites' folder and its move out of the working folder"),
        "Models/BuilderWarmUp.swift": (10, "notAStep: the builder cache of #836 (class D), and the shell and launchers it warms the builder with"),
        "Models/ClassInsertionPlanner.swift": (6, "waitsFor: U3"),
        "Models/ClassesDatedLater.swift": (2, "waitsFor: U3"),
        "Models/CourseArchiver.swift": (6, "waitsFor: U5"),
        "Models/CourseConfiguration.swift": (2, "waitsFor: U4"),
        "Models/CoursePageCopier.swift": (3, "waitsFor: U4"),
        "Models/CourseRenamer.swift": (3, "waitsFor: U4"),
        "Models/CourseRestorer.swift": (29, "waitsFor: U5"),
        "Models/DeployCommand.swift": (3, "waitsFor: U4 (releaseSite: the rollover's cut loose, undone with it; the deploy.sh it names is not counted, rulings 17 and 18)"),
        "Models/FolderContainers.swift": (2, "notAStep: the website builder's containers, through a shell, outside every course"),
        "Models/FolderScaffold.swift": (1, "waitsFor: U4 (a new working folder's scaffold, made with New Course)"),
        "Models/HowITeachPage.swift": (1, "waitsFor: U3"),
        "Models/LinksChecklist/LinksChecklistOffer.swift": (2, "waitsFor: U3"),
        "Models/LinksChecklist/PublishedPagesRecord.swift": (4, "notAStep: the published-pages record, written by a deploy (rulings 17 and 18) and read by undo.rule.deployed"),
        "Models/ObsidianFigureAddOns.swift": (11, "waitsFor: U4"),
        "Models/OneSectionRestore.swift": (1, "notAStep: `unzip -p` reads a backup's course_config.json to its output and writes nothing; the restore itself is CourseRestorer's (U5)"),
        "Models/PlaceholderClassPlanner.swift": (2, "waitsFor: U3"),
        "Models/PlanSharing.swift": (7, "notAStep: sharing unit plans and stopping (ruling 18); its releasePlanMarkers runs inside a reference copy, which is U4's"),
        "Models/PlantoirDefaults.swift": (2, "notAStep: the preferences store's own note file under a state folder"),
        "Models/PreviewReachability.swift": (1, "notAStep: a shell that asks whether a preview answers; it writes no file"),
        "Models/RealHome.swift": (1, "notAStep: names the login shell; runs nothing"),
        "Models/ReferenceCopier.swift": (3, "waitsFor: U4"),
        "Models/ReferenceCreation.swift": (2, "waitsFor: U4"),
        "Models/ReferenceImporter.swift": (4, "waitsFor: U4"),
        "Models/ReferenceLock.swift": (1, "waitsFor: U4 (a reference course's locks, lifted and put back inside the step that changes it, plan 2.6)"),
        "Models/ReferenceReadingView.swift": (2, "waitsFor: U4"),
        "Models/ReferenceReplacer.swift": (3, "waitsFor: U5"),
        "Models/ReferenceShelfStore.swift": (3, "waitsFor: U4"),
        "Models/ReferenceStaging.swift": (6, "waitsFor: U4"),
        "Models/ReferenceTreeCopier.swift": (5, "waitsFor: U4"),
        "Models/ReferenceZipSource.swift": (6, "waitsFor: U4"),
        "Models/ScheduledDeploy.swift": (37, "notAStep: held for Russell (M10): whether setting or cancelling a deploy for later is a step; the deploy when it runs is not (rulings 17 and 18). launchd jobs and the scripts they run, outside every course"),
        "Models/ScheduledPublishOutcome.swift": (5, "notAStep: a scheduled run's outcome record, a world record"),
        "Models/ScheduledPublishWatcher.swift": (1, "notAStep: a scheduled run's outcome record, a world record"),
        "Models/ScheduledRunFolderRefresh.swift": (4, "notAStep: a deploy set for later refreshing its folder's launchers (rulings 17 and 18), outside every course"),
        "Models/SectionAdder.swift": (13, "waitsFor: U4"),
        "Models/SectionIndexPointer.swift": (1, "waitsFor: U3"),
        "Models/SectionProblems.swift": (2, "notAStep: folder-problem acknowledgements (plan 7: not steps)"),
        "Models/SectionPublishState.swift": (2, "notAStep: the site markers, written by a deploy (rulings 17 and 18) and read by undo.rule.deployed"),
        "Models/SectionReDatePlanner.swift": (1, "waitsFor: U3"),
        "Models/SectionTimetable.swift": (2, "waitsFor: U3"),
        "Models/SetUp/AssistantSetUp.swift": (3, "notAStep: setting up an outside assistant, outside every course (held question M8, as AssistantSetUpCentre)"),
        "Models/SetUp/AssistantSetUpCentre.swift": (5, "notAStep: setting up an outside assistant, outside every course (it changes no course: not on the list; ruling 16's reason, asked again under ruling 17)"),
        "Models/SetUp/SetUpRecord.swift": (8, "notAStep: the record of the assistants Plantoir set up, outside every course (as AssistantSetUpCentre)"),
        "Models/SetUp/SetUpRunner.swift": (3, "notAStep: a set-up's own work folder, outside every course (as AssistantSetUpCentre)"),
        "Models/SharedMedia/SharedMediaFiles.swift": (2, "waitsFor: U5 (the shared Media store of #785, written by a small backup; a step that deletes or moves one keeps its files through keepForUndo)"),
        "Models/SharedMedia/SharedMediaStore.swift": (36, "waitsFor: U5 (the shared Media store of #785 and its sweep, outside every course's pages, under _backups; Undo's seam keepForUndo and releaseForUndo is U5's)"),
        "Models/SiteHealthRepair.swift": (3, "waitsFor: U4"),
        "Models/SpecialFolderRenamer.swift": (5, "waitsFor: U4"),
        "Models/StartOfYear/StartOfYearPlanner.swift": (1, "waitsFor: U3"),
        "Models/TodaysClassOnTheFrontPage.swift": (3, "waitsFor: U3"),
        "Models/ToolchainCopyMarker.swift": (3, "notAStep: the toolchain mirror"),
        "Models/ToolchainFingerprints.swift": (7, "notAStep: the toolchain mirror's index"),
        "Models/Undo/UndoCheck.swift": (12, "door: the staged swaps of an undo, a redo and recovery"),
        "Models/Undo/UndoJournal.swift": (19, "door: the list itself, outside every working folder"),
        "Models/Undo/UndoLock.swift": (1, "door: the list's own lock file"),
        "Models/Undo/UndoRecovery.swift": (2, "door: pruning the list's own content and segments"),
        "Models/UnitWordRenamer.swift": (6, "waitsFor: U4"),
        "Models/WorkLeaseFiles.swift": (3, "notAStep: work leases"),
        "Models/WorkLeaseRegistry.swift": (3, "notAStep: work leases"),
        "Models/WorkspaceModel.swift": (25, "waitsFor: U4 and U5 (Add Section, New Course, restore, remove, archive, delete, and the launchers it copies into a working folder)"),
        "Scripting/MultiDestinationDeployRunner.swift": (1, "waitsFor: U4 (the build before a deploy is preview.sh, whose preflight rewrites course_config.json; the deploy itself is not counted, rulings 17 and 18)"),
        "Scripting/NewCourseCreator.swift": (5, "waitsFor: U4 (New Course from the command line: the course folder, its course_config.json, and setup.sh)"),
        "Scripting/PlanShareRunner.swift": (1, "notAStep: sharing unit plans through deploy.sh (ruling 18)"),
        "Scripting/PreviewStopper.swift": (4, "notAStep: stops a preview through preview.sh, which writes no course file when it stops"),
        "Scripting/ProblemReport.swift": (7, "notAStep: problem reports and their records, outside every course"),
        "Scripting/ProblemReportBuilder.swift": (6, "notAStep: a problem report's working folder, outside every course"),
        "Scripting/ScriptRunner.swift": (2, "waitsFor: U4 (runs the launchers through /bin/bash: setup.sh makes a course for New Course, preview.sh rewrites course_config.json in its preflight; deploy.sh is not counted, rulings 17 and 18)"),
        "Views/CourseSettings/CourseSettingsView.swift": (2, "waitsFor: U4"),
        "Views/CourseSettings/StringListEditorView.swift": (3, "waitsFor: U4"),
        "Views/Helpers/FolderActions.swift": (5, "waitsFor: U5"),
        "Views/Section/SectionDetailView.swift": (1, "waitsFor: U4 (starts preview.sh, as AssistSiteWork)"),
        "Views/SidebarView.swift": (4, "waitsFor: U5"),
        "Views/Wizard/SetSchoolYearSheet.swift": (1, "waitsFor: U4"),
    ]

    // MARK: - Tests

    func testEveryWriterIsTheDoorOrNamedWithAReason() throws {
        let productFolder: URL = ActivityTrailWiringTests.productSourceFolderURL()
        var found: [String: Int] = [:]
        var scanned: Int = 0
        for folderName in UndoWriterScanTests.scannedFolders {
            let folder: URL = productFolder.appendingPathComponent(folderName, isDirectory: true)
            for fileURL in ActivityTrailWiringTests.swiftFiles(under: folder) {
                scanned += 1
                let relativePath: String = RealHomeTripwireTests.path(of: fileURL, under: productFolder)
                let count: Int = try UndoWriterScanTests.writingCallCount(in: fileURL)
                if count > 0 {
                    found[relativePath] = count
                }
            }
        }
        XCTAssertGreaterThan(scanned, 100, "The scan read no product source, so it checked nothing.")

        var unexpected: [String] = []
        for (path, count) in found {
            guard let entry = UndoWriterScanTests.allowed[path] else {
                unexpected.append("\(path) writes files (\(count) calls) and is not on the list")
                continue
            }
            if entry.calls != count {
                unexpected.append("\(path) has \(count) writing calls; the list allows \(entry.calls)")
            }
        }
        for (path, _) in UndoWriterScanTests.allowed where found[path] == nil {
            unexpected.append("\(path) is on the list and writes nothing any more: remove the stale entry")
        }
        unexpected.sort()
        XCTAssertEqual(
            unexpected, [],
            "A write into a working folder must go through JournaledWrite once Undo is on. Route it through the door, or add the file here with its count and the reason it is not a step (or the piece of #899 that will wire it)."
        )
    }

    /// What the second core review found passed the scan. MUST FAIL on the
    /// scan before the director's ruling 7 (56b2b23a9), which read one line
    /// at a time and knew neither tools run as a process,
    /// `setResourceValues` nor `recycle`: it counts 1 of these 7.
    func testTheScanCountsSplitCallsToolsAndTheTrash() {
        let samples: [(source: String, calls: Int)] = [
            (source: "try data.write(\n    to: url, options: .atomic)", calls: 1),
            (source: "let handle = try FileHandle(\n    forWritingTo: url)", calls: 1),
            (source: "process.executableURL = URL(fileURLWithPath: \"/usr/bin/ditto\")", calls: 1),
            (source: "lines.append(\"/bin/rm -f \\(quoted)\")", calls: 1),
            (source: "try url.setResourceValues(values)", calls: 1),
            (source: "NSWorkspace.shared.recycle([url]) { _, _ in }", calls: 1),
            (source: "try FileManager.default.removeItem(at: url)", calls: 1),
            (source: "// try data.write(\n// to: url)", calls: 0),
            (source: "let listing = run(\"/usr/bin/zipinfo\", [path])", calls: 0),
        ]
        for sample in samples {
            var count: Int = 0
            for code in UndoWriterScanTests.codeLines(of: sample.source) {
                count += UndoWriterScanTests.writingCallCount(inCode: code)
            }
            XCTAssertEqual(count, sample.calls, sample.source)
        }
    }

    /// What the third core review found passed the scan, and a removal
    /// counted twice. MUST FAIL on the scan at a6796be95, which knew no
    /// shell or launcher run as a process and none of these C calls, and
    /// counted `removeItem(` twice because it holds `moveItem(`: it counts
    /// 2 where these samples hold 9 (the director's ruling 9 on U1's third
    /// round).
    func testTheScanCountsShellsLaunchersAndTheCCalls() {
        let samples: [(source: String, calls: Int)] = [
            (source: "newProcess.executableURL = URL(fileURLWithPath: \"/bin/bash\")", calls: 1),
            (source: "runner.run(scriptNamed: \"setup.sh\", arguments: [], workingDirectory: url)", calls: 1),
            (source: "_ = utimes(url.path, nil)", calls: 1),
            (source: "rmdir(path)", calls: 1),
            (source: "let descriptor = mkstemp(&template)", calls: 1),
            (source: "try remove(url)", calls: 1),
            (source: "setxattr(path, name, value, size, 0, 0)", calls: 1),
            (source: "NSWorkspace.shared.duplicate([url]) { _, _ in }", calls: 1),
            (source: "try FileManager.default.removeItem(at: url)", calls: 1),
            (source: "items.remove(at: 0)", calls: 0),
            (source: "let tool = \"/usr/bin/shasum\"", calls: 0),
        ]
        var total: Int = 0
        for sample in samples {
            var count: Int = 0
            for code in UndoWriterScanTests.codeLines(of: sample.source) {
                count += UndoWriterScanTests.writingCallCount(inCode: code)
            }
            XCTAssertEqual(count, sample.calls, sample.source)
            total += count
        }
        XCTAssertEqual(total, 9)
    }

    func testEveryReasonIsOneOfTheThreeKinds() {
        for (path, entry) in UndoWriterScanTests.allowed {
            let kind: String = String(entry.reason.prefix(while: { character in character != ":" }))
            XCTAssertTrue(["door", "notAStep", "waitsFor"].contains(kind), "\(path): \(entry.reason)")
            if kind == "door" {
                XCTAssertTrue(path.hasPrefix("Models/Undo/"), "\(path) calls itself the door")
            }
        }
    }

    /// U7 flips the switch only once no writer waits for a piece.
    func testTheSwitchStaysOffWhileWritersWait() {
        var waiting: Int = 0
        for (_, entry) in UndoWriterScanTests.allowed where entry.reason.hasPrefix("waitsFor") {
            waiting += 1
        }
        if waiting > 0 {
            XCTAssertFalse(UndoSwitch.undoJournalIsLive, "\(waiting) writers are not journaled yet; Undo cannot be switched on.")
        }
    }

    // MARK: - Functions

    static func writingCallCount(in fileURL: URL) throws -> Int {
        let contents: String = try String(contentsOf: fileURL, encoding: .utf8)
        var count: Int = 0
        for code in UndoWriterScanTests.codeLines(of: contents) {
            count += UndoWriterScanTests.writingCallCount(inCode: code)
        }
        return count
    }

    /// The code part of every line, a line that ends in `(` read together
    /// with the next, so `.write(` on one line and `to:` on the next is the
    /// one call it is (the core review's second I3).
    static func codeLines(of contents: String) -> [String] {
        var result: [String] = []
        var pending: String? = nil
        for rawLine in contents.components(separatedBy: "\n") {
            var code: String = RealHomeTripwireTests.codePart(of: rawLine)
            if let opened = pending {
                code = opened + code.trimmingCharacters(in: .whitespaces)
                pending = nil
            }
            let trimmedEnd: String = UndoWriterScanTests.trimmingTrailingSpace(code)
            if trimmedEnd.hasSuffix("(") {
                pending = trimmedEnd
                continue
            }
            result.append(code)
        }
        if let opened = pending {
            result.append(opened)
        }
        return result
    }

    static func trimmingTrailingSpace(_ text: String) -> String {
        var characters: [Character] = Array(text)
        while let last = characters.last, last == " " || last == "\t" {
            characters.removeLast()
        }
        return String(characters)
    }

    /// How many writing calls one line of source holds.
    static func writingCallCount(inLine rawLine: String) -> Int {
        return writingCallCount(inCode: RealHomeTripwireTests.codePart(of: rawLine))
    }

    /// Whether a line names a tool that writes by its path.
    static func runsAWritingTool(_ code: String) -> Bool {
        for tool in writingTools {
            for folder in toolFolders {
                if code.contains(folder + tool + "\"") || code.contains(folder + tool + " ") {
                    return true
                }
            }
        }
        return false
    }

    /// How many writing calls one line's code holds.
    static func writingCallCount(inCode code: String) -> Int {
        if code.isEmpty {
            return 0
        }
        var count: Int = 0
        for call in writingCalls where code.contains(call) {
            count += 1
        }
        for name in bareWritingCalls where UndoWriterScanTests.containsBareCall(name, in: code) {
            count += 1
        }
        if UndoWriterScanTests.containsBareCall("open", in: code) {
            for flag in openForWritingFlags where code.contains(flag) {
                count += 1
                break
            }
        }
        if UndoWriterScanTests.runsAWritingTool(code) {
            count += 1
        }
        for launcher in launchers where code.contains("\"" + launcher + "\"") {
            count += 1
        }
        return count
    }

    /// True when `name(` appears as a call of its own: the character before
    /// it is not a letter, digit, `_` or `.`, and it does not follow `func `
    /// or `case `.
    static func containsBareCall(_ name: String, in code: String) -> Bool {
        let target: String = name + "("
        var searchStart: String.Index = code.startIndex
        while let found = code.range(of: target, range: searchStart..<code.endIndex) {
            let before: String = String(code[code.startIndex..<found.lowerBound])
            var isACall: Bool = true
            if let previous = before.last {
                if previous.isLetter || previous.isNumber || previous == "_" || previous == "." {
                    isACall = false
                }
            }
            if before.hasSuffix("func ") || before.hasSuffix("case ") {
                isACall = false
            }
            if isACall {
                return true
            }
            searchStart = code.index(after: found.lowerBound)
        }
        return false
    }
}
