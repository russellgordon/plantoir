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
/// What counts as a writing call (widened after U1's reviews): Foundation's
/// writes, moves, removals, copies, attribute changes and links; a
/// `FileHandle` opened for writing; and the C calls that write (`rename`,
/// `link`, `unlink`, `mkdir`, `chmod`, `truncate` and the like, and `open`
/// with a flag that writes). The count is per file, so a file can swap one
/// write for another and stay green: the list says WHO writes, and a new
/// writer is what it catches.
final class UndoWriterScanTests: XCTestCase {

    // MARK: - Stored properties

    /// The calls that write, move or remove a file, as the text a line holds.
    static let writingCalls: [String] = [
        "write(to:",
        "write(toFile:",
        "moveItem(",
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
    ]

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
    ]

    /// `open(` counts once on a line that also names one of these flags.
    static let openForWritingFlags: [String] = ["O_WRONLY", "O_RDWR", "O_CREAT"]

    /// The product source folders scanned: all of them.
    static let scannedFolders: [String] = ["Models", "Views", "Scripting", "App"]

    /// Every file allowed to write, with how many writing calls it holds and
    /// why. Paths are under `QuartzTeachers/`.
    static let allowed: [String: (calls: Int, reason: String)] = [
        "App/ProblemReportCommands.swift": (8, "notAStep: a problem report, built and saved outside every course"),
        "App/QuartzTeachersApp.swift": (1, "notAStep: the app's own state folder for `--state-dir`"),
        "Models/AgentGuidance.swift": (2, "waitsFor: U4"),
        "Models/Assist/AppRulesContract.swift": (1, "notAStep: writes the contract files for `--write-contracts`, a developer's command"),
        "Models/Assist/AssistChangeHistory.swift": (3, "waitsFor: U7 (today's undo itself; kept as an adapter when the switch flips)"),
        "Models/Assist/AssistContract.swift": (2, "notAStep: writes the contract files for `--write-contracts`, a developer's command"),
        "Models/Assist/AssistCurriculumMentions.swift": (1, "waitsFor: U3"),
        "Models/Assist/AssistModelStore.swift": (11, "notAStep: the assistant's model download and removal (class D, plan 7)"),
        "Models/Assist/AssistPublishPlan.swift": (1, "waitsFor: U3"),
        "Models/Assist/AssistServerHost.swift": (7, "notAStep: the assistant's own launch files"),
        "Models/Assist/AssistToolRunner.swift": (2, "waitsFor: U3"),
        "Models/Assist/ClaudeCodeLauncher.swift": (4, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/Assist/CodexLauncher.swift": (2, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/Assist/CopilotLauncher.swift": (3, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/BuildOutputLocation.swift": (37, "notAStep: the built websites' folder and its move out of the working folder"),
        "Models/BuilderWarmUp.swift": (5, "notAStep: the builder cache of #836 (class D)"),
        "Models/ClassInsertionPlanner.swift": (7, "waitsFor: U3"),
        "Models/ClassesDatedLater.swift": (2, "waitsFor: U3"),
        "Models/CourseArchiver.swift": (8, "waitsFor: U5"),
        "Models/CourseConfiguration.swift": (2, "waitsFor: U4"),
        "Models/CoursePageCopier.swift": (3, "waitsFor: U4"),
        "Models/CourseRenamer.swift": (3, "waitsFor: U4"),
        "Models/CourseRestorer.swift": (22, "waitsFor: U5"),
        "Models/DeployCommand.swift": (2, "waitsFor: U6"),
        "Models/FolderScaffold.swift": (1, "waitsFor: U4 (a new working folder's scaffold, made with New Course)"),
        "Models/HowITeachPage.swift": (1, "waitsFor: U3"),
        "Models/LinksChecklist/LinksChecklistOffer.swift": (2, "waitsFor: U3"),
        "Models/LinksChecklist/PublishedPagesRecord.swift": (6, "notAStep: the published-pages record is a world record (undo.worldRecords, U6)"),
        "Models/ObsidianFigureAddOns.swift": (14, "waitsFor: U4"),
        "Models/PlaceholderClassPlanner.swift": (2, "waitsFor: U3"),
        "Models/PlanSharing.swift": (9, "waitsFor: U6"),
        "Models/PlantoirDefaults.swift": (1, "notAStep: the preferences store's own note file under a state folder"),
        "Models/ReferenceCopier.swift": (4, "waitsFor: U4"),
        "Models/ReferenceCreation.swift": (2, "waitsFor: U4"),
        "Models/ReferenceImporter.swift": (5, "waitsFor: U4"),
        "Models/ReferenceLock.swift": (1, "waitsFor: U4 (a reference course's locks, lifted and put back inside the step that changes it, plan 2.6)"),
        "Models/ReferenceReadingView.swift": (2, "waitsFor: U4"),
        "Models/ReferenceReplacer.swift": (2, "waitsFor: U5"),
        "Models/ReferenceShelfStore.swift": (3, "waitsFor: U4"),
        "Models/ReferenceStaging.swift": (9, "waitsFor: U4"),
        "Models/ReferenceTreeCopier.swift": (5, "waitsFor: U4"),
        "Models/ReferenceZipSource.swift": (3, "waitsFor: U4"),
        "Models/ScheduledDeploy.swift": (33, "waitsFor: U6"),
        "Models/ScheduledPublishOutcome.swift": (7, "notAStep: a scheduled run's outcome record, a world record"),
        "Models/ScheduledPublishWatcher.swift": (1, "notAStep: a scheduled run's outcome record, a world record"),
        "Models/SectionAdder.swift": (13, "waitsFor: U4"),
        "Models/SectionIndexPointer.swift": (1, "waitsFor: U3"),
        "Models/SectionProblems.swift": (2, "notAStep: folder-problem acknowledgements (plan 7: not steps)"),
        "Models/SectionPublishState.swift": (2, "notAStep: deploy markers are world records (undo.worldRecords, U6)"),
        "Models/SectionReDatePlanner.swift": (1, "waitsFor: U3"),
        "Models/SectionTimetable.swift": (2, "waitsFor: U3"),
        "Models/SiteHealthRepair.swift": (3, "waitsFor: U4"),
        "Models/SpecialFolderRenamer.swift": (6, "waitsFor: U4"),
        "Models/StartOfYear/StartOfYearPlanner.swift": (1, "waitsFor: U3"),
        "Models/TodaysClassOnTheFrontPage.swift": (3, "waitsFor: U3"),
        "Models/ToolchainCopyMarker.swift": (4, "notAStep: the toolchain mirror"),
        "Models/ToolchainFingerprints.swift": (9, "notAStep: the toolchain mirror's index"),
        "Models/Undo/UndoCheck.swift": (20, "door: the staged swaps of an undo, a redo and recovery"),
        "Models/Undo/UndoJournal.swift": (20, "door: the list itself, outside every working folder"),
        "Models/Undo/UndoLock.swift": (1, "door: the list's own lock file"),
        "Models/Undo/UndoRecovery.swift": (4, "door: pruning the list's own content and segments"),
        "Models/UnitWordRenamer.swift": (7, "waitsFor: U4"),
        "Models/WorkLeaseFiles.swift": (4, "notAStep: work leases"),
        "Models/WorkLeaseRegistry.swift": (4, "notAStep: work leases"),
        "Models/WorkspaceModel.swift": (18, "waitsFor: U4 and U5 (Add Section, New Course, restore, remove, archive, delete)"),
        "Scripting/NewCourseCreator.swift": (2, "waitsFor: U4 (New Course from the command line: the course folder and its course_config.json)"),
        "Scripting/ProblemReport.swift": (7, "notAStep: problem reports and their records, outside every course"),
        "Scripting/ProblemReportBuilder.swift": (5, "notAStep: a problem report's working folder, outside every course"),
        "Views/CourseSettings/CourseSettingsView.swift": (2, "waitsFor: U4"),
        "Views/CourseSettings/StringListEditorView.swift": (6, "waitsFor: U4"),
        "Views/Helpers/FolderActions.swift": (5, "waitsFor: U5"),
        "Views/SidebarView.swift": (8, "waitsFor: U5"),
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
        for rawLine in contents.components(separatedBy: "\n") {
            count += UndoWriterScanTests.writingCallCount(inLine: rawLine)
        }
        return count
    }

    /// How many writing calls one line of source holds.
    static func writingCallCount(inLine rawLine: String) -> Int {
        let code: String = RealHomeTripwireTests.codePart(of: rawLine)
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
