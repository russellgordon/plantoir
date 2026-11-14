import XCTest
@testable import QuartzTeachers

/// Every write into a working folder will go through ONE door,
/// `JournaledWrite`, before Undo and Redo are switched on (#899, plan 3.3,
/// review 22). This scan reads the product source under `Models` and
/// `Views` and fails on any file-writing call in a file that is not on the
/// list below, with as many calls as the list says: a new writer, or a new
/// call beside an allowed one, is red until somebody decides whether it is a
/// step. An entry nothing matches any more is red as stale.
///
/// Three kinds of reason:
/// - `door`: the list itself (`Models/Undo`).
/// - `notAStep`: writes that are not a teacher's change (plan 7: the trail,
///   leases, the toolchain mirror, model downloads, world records and so on).
/// - `waitsFor`: a teacher's change not yet journaled, and the piece of
///   #899 that wires it. **The switch cannot flip (U7) while any
///   `waitsFor` remains**: `testTheSwitchStaysOffWhileWritersWait` says so.
///
/// The `Scripting` and `App` folders are not scanned: the trail, problem
/// reports and the launchers' plumbing live there, and none of them writes a
/// course.
final class UndoWriterScanTests: XCTestCase {

    // MARK: - Stored properties

    /// The calls that write, move or remove a file, as the text a line holds.
    static let writingCalls: [String] = [
        "write(to:",
        "moveItem(",
        "removeItem(",
        "copyItem(",
        "replaceItemAt(",
        "createDirectory(",
        "createFile(",
        "trashItem(",
        "renamex_np(",
        "copyfile(",
    ]

    /// Every file allowed to write, with how many writing calls it holds and
    /// why. Paths are under `QuartzTeachers/`.
    static let allowed: [String: (calls: Int, reason: String)] = [
        "Models/AgentGuidance.swift": (2, "waitsFor: U4"),
        "Models/Assist/AppRulesContract.swift": (1, "notAStep: writes the contract files for `--write-contracts`, a developer's command"),
        "Models/Assist/AssistChangeHistory.swift": (3, "waitsFor: U7 (today's undo itself; kept as an adapter when the switch flips)"),
        "Models/Assist/AssistContract.swift": (2, "notAStep: writes the contract files for `--write-contracts`, a developer's command"),
        "Models/Assist/AssistCurriculumMentions.swift": (1, "waitsFor: U3"),
        "Models/Assist/AssistModelStore.swift": (11, "notAStep: the assistant's model download and removal (class D, plan 7)"),
        "Models/Assist/AssistPublishPlan.swift": (1, "waitsFor: U3"),
        "Models/Assist/AssistServerHost.swift": (6, "notAStep: the assistant's own launch files"),
        "Models/Assist/AssistToolRunner.swift": (2, "waitsFor: U3"),
        "Models/Assist/ClaudeCodeLauncher.swift": (3, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/Assist/CodexLauncher.swift": (1, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/Assist/CopilotLauncher.swift": (2, "notAStep: an outside assistant's launch files, outside any course"),
        "Models/BuildOutputLocation.swift": (34, "notAStep: the built websites' folder and its move out of the working folder"),
        "Models/BuilderWarmUp.swift": (4, "notAStep: the builder cache of #836 (class D)"),
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
        "Models/PlanSharing.swift": (7, "waitsFor: U6"),
        "Models/PlantoirDefaults.swift": (1, "notAStep: the preferences store's own note file under a state folder"),
        "Models/ReferenceCopier.swift": (4, "waitsFor: U4"),
        "Models/ReferenceCreation.swift": (2, "waitsFor: U4"),
        "Models/ReferenceImporter.swift": (5, "waitsFor: U4"),
        "Models/ReferenceReadingView.swift": (2, "waitsFor: U4"),
        "Models/ReferenceReplacer.swift": (2, "waitsFor: U5"),
        "Models/ReferenceShelfStore.swift": (3, "waitsFor: U4"),
        "Models/ReferenceStaging.swift": (9, "waitsFor: U4"),
        "Models/ReferenceTreeCopier.swift": (2, "waitsFor: U4"),
        "Models/ReferenceZipSource.swift": (3, "waitsFor: U4"),
        "Models/ScheduledDeploy.swift": (31, "waitsFor: U6"),
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
        "Models/ToolchainFingerprints.swift": (8, "notAStep: the toolchain mirror's index"),
        "Models/Undo/UndoCheck.swift": (18, "door: the staged swaps of an undo, a redo and recovery"),
        "Models/Undo/UndoJournal.swift": (12, "door: the list itself, outside every working folder"),
        "Models/Undo/UndoRecovery.swift": (4, "door: pruning the list's own content and segments"),
        "Models/UnitWordRenamer.swift": (7, "waitsFor: U4"),
        "Models/WorkLeaseFiles.swift": (4, "notAStep: work leases"),
        "Models/WorkLeaseRegistry.swift": (4, "notAStep: work leases"),
        "Models/WorkspaceModel.swift": (13, "waitsFor: U4 and U5 (Add Section, New Course, restore, remove, archive, delete)"),
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
        for folderName in ["Models", "Views"] {
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
            let code: String = RealHomeTripwireTests.codePart(of: rawLine)
            if code.isEmpty {
                continue
            }
            for call in writingCalls where code.contains(call) {
                count += 1
            }
        }
        return count
    }
}
