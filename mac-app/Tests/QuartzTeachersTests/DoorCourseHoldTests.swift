import XCTest
@testable import QuartzTeachers

/// The Claude door names its course to `Plantoir --mcp-stdio`, and the server
/// holds an `assist` lease on it without locking (#458, matching Windows'
/// #430) — which buys three protections in the app: the session's backup is
/// kept, a second session is refused, and structural work waits.
///
/// Runs `contracts/shared-rules.json` → `doorCourseHold` and
/// `contracts/file-formats.json` → `heldBackupRecord`. The "other program" is
/// a real `/bin/sleep` child whose leases are real files, as in
/// `OutsideAssistantWhilePreviewingTests`, so the liveness reader sees a real
/// process.
///
/// Resets `WorkLeaseRegistry`, `CourseActivity`, `AssistActivity` and
/// `AssistMCPServer.isServing` — process-wide state — so it relies on the
/// scheme running classes one at a time.
@MainActor
final class DoorCourseHoldTests: XCTestCase {

    // MARK: - Stored properties

    var other: Process?

    var previousTrail: ProblemReportStore = ActivityTrail.store

    var roots: [URL] = []

    // MARK: - Setting up

    override func setUp() async throws {
        CourseActivity.reset()
        PreviewLeases.reset()
        WorkLeaseRegistry.reset()
        AssistActivity.store.active = nil
        AssistActivity.store.heldBackups = nil
        AssistMCPServer.isServing = false
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        stopTheOtherProgram()
        ActivityTrail.store = previousTrail
        AssistMCPServer.isServing = false
        AssistActivity.store.active = nil
        AssistActivity.store.heldBackups = nil
        WorkLeaseRegistry.removalsSeenByTests = nil
        WorkLeaseRegistry.reset()
        CourseActivity.reset()
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots = []
    }

    // MARK: - Helpers

    /// A working folder with ICS3U (one section) and MPM2D, its trail pointed
    /// inside it, and a window's model on it.
    func makeFolder() throws -> (root: URL, workspace: WorkspaceModel) {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(hasDeployedBefore: true, alsoCourse: "MPM2D")
        roots.append(made.root)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: made.root)
        return (made.root, workspace)
    }

    /// The other program, a real process the liveness reader can see.
    func otherProgram() throws -> Int32 {
        if let other, other.isRunning {
            return other.processIdentifier
        }
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        other = process
        return process.processIdentifier
    }

    func stopTheOtherProgram() {
        if let other, other.isRunning {
            other.terminate()
            other.waitUntilExit()
        }
        other = nil
    }

    func activityDirectory(_ root: URL) -> URL {
        return WorkLeaseFiles.activityDirectory(coursesDirectory: root.appendingPathComponent("courses"))
    }

    /// Writes the other program's leases on a course, as either app writes them.
    func writeOthersLeases(_ kinds: [String], course: String = "ICS3U", in root: URL) throws {
        let pid: Int32 = try otherProgram()
        let directory: URL = activityDirectory(root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let when: String = ProcessLiveness.leaseMomentText(Date().addingTimeInterval(-1))
        let start: String = ProcessLiveness.startTime(ofProcess: pid) ?? ""
        for kind in kinds {
            let url: URL = directory.appendingPathComponent(
                WorkLeaseFiles.fileName(courseCode: course, kind: kind, pid: pid)
            )
            try Data("\(pid)\nsleep\n\(when)\n\(start)\n".utf8).write(to: url)
        }
    }

    /// Writes the other program's held-backup record naming `backup`.
    func writeOthersRecord(course: String = "ICS3U", naming backup: URL, in root: URL) throws {
        let pid: Int32 = try otherProgram()
        let directory: URL = activityDirectory(root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(backup.path.utf8).write(
            to: directory.appendingPathComponent(WorkLeaseFiles.heldBackupRecordName(courseCode: course, pid: pid))
        )
    }

    func makeBackup(named name: String, course: String = "ICS3U", in root: URL) throws -> URL {
        let folder: URL = root.appendingPathComponent("courses/_backups/\(course)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url: URL = folder.appendingPathComponent(name)
        try Data("zip".utf8).write(to: url)
        return url
    }

    func item(_ url: URL, in workspace: WorkspaceModel) throws -> BackupItem {
        workspace.reloadCourses()
        var match: BackupItem? = nil
        for item in workspace.backupItems where item.fileURL.lastPathComponent == url.lastPathComponent {
            match = item
        }
        return try XCTUnwrap(match, "\(url.lastPathComponent) is not in the list")
    }

    func names(in directory: URL) -> [String] {
        let listed: [String] = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return listed.sorted()
    }

    func trailText(in root: URL) -> String {
        var text: String = ""
        let folder: URL = root.appendingPathComponent("trail")
        for name in names(in: folder) {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
                text += String(decoding: data, as: UTF8.self)
            }
        }
        return text
    }

    func course(_ code: String, in workspace: WorkspaceModel) throws -> Course {
        var found: Course? = nil
        for candidate in workspace.courses where candidate.code == code {
            found = candidate
        }
        return try XCTUnwrap(found, "No \(code)")
    }

    // MARK: - Which course is held

    /// MUST FAIL if the value is held unchecked ("NOPE1" would be held), or
    /// matched with case, or not trimmed.
    func testTheCourseToHoldIsTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["doorCourseHold", "courseToHold"])
        let courses: [String] = try XCTUnwrap(block["courses"] as? [String])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 8, "Cases went missing from the contract.")
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            let asked: String? = item["doorCourse"] as? String
            let expected: String? = item["expect"] as? String
            XCTAssertEqual(
                AssistMCPServer.courseToHoldForTheConversation(asked, among: courses), expected, name
            )
        }
        let doors: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["doorCourseHold", "whichDoors"])
        XCTAssertEqual(doors["claude"] as? Bool, true)
        XCTAssertEqual(doors["codex"] as? Bool, false)
    }

    /// The server takes the lease on the course the door named, as the folder
    /// spells it, and says so on the trail; a course the folder does not have
    /// holds nothing and writes nothing.
    func testTheServerHoldsTheDoorsCourseAndSaysSo() throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        AssistMCPServer.holdTheDoorsCourse(
            in: made.workspace, environment: [AssistMCPServer.doorCourseVariable: " ics3u "]
        )
        let pid: Int32 = getpid()
        XCTAssertEqual(names(in: activityDirectory(made.root)), ["ICS3U.assist.\(pid).lease"])
        XCTAssertTrue(trailText(in: made.root).contains(AssistMCPServer.holdingTrailLine(courseCode: "ICS3U")))

        WorkLeaseRegistry.reset()
        AssistMCPServer.holdTheDoorsCourse(
            in: made.workspace, environment: [AssistMCPServer.doorCourseVariable: "NOPE1"]
        )
        XCTAssertEqual(names(in: activityDirectory(made.root)), [])
        AssistMCPServer.holdTheDoorsCourse(in: made.workspace, environment: [:])
        XCTAssertEqual(names(in: activityDirectory(made.root)), [])
    }

    /// The trail's line is the contract's, and it names no machinery.
    func testTheTrailLineIsTheContracts() throws {
        let trail: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["activityTrail"])
        let events: [[String: Any]] = try XCTUnwrap(trail["mustRecord"] as? [[String: Any]])
        var line: String? = nil
        for event in events where (event["event"] as? String) == ActivityTrail.Event.outsideSessionHeldACourse.rawValue {
            line = event["line"] as? String
        }
        let expected: String = try XCTUnwrap(line)
        XCTAssertEqual(
            AssistMCPServer.holdingTrailLine(courseCode: "ICS3U"),
            expected.replacingOccurrences(of: "{course}", with: "ICS3U")
        )
    }

    // MARK: - The lease lasts the conversation

    /// MUST FAIL if the hold is not among what `reconcile` wants: the first
    /// reconcile after the session's own deploy ended would take it down.
    func testTheHoldSurvivesAReconcileAndTheLeavingWindow() throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        let leaseName: String = "ICS3U.assist.\(getpid()).lease"
        WorkLeaseRegistry.holdForTheConversation(folderPath: made.root.path, courseCode: "ICS3U")
        XCTAssertEqual(names(in: activityDirectory(made.root)), [leaseName])

        CourseActivity.beginPublish(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        CourseActivity.endPublish(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        WorkLeaseRegistry.reconcile()
        XCTAssertEqual(names(in: activityDirectory(made.root)), [leaseName], "A reconcile took the hold down.")

        WorkLeaseRegistry.isLeaving = true
        WorkLeaseRegistry.reconcile()
        XCTAssertEqual(names(in: activityDirectory(made.root)), [leaseName])
    }

    /// MUST FAIL if `releaseEverything` keeps the hold, or if the records go
    /// AFTER the lease (Windows' order: runs, records, leases).
    func testLeavingForgetsTheRecordsBeforeTheLeaseGoes() async throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        let backup: URL = try makeBackup(named: "ICS3U_backup_2026-10-07_120000_assistant-section1.zip", in: made.root)
        WorkLeaseRegistry.holdForTheConversation(folderPath: made.root.path, courseCode: "ICS3U")
        WorkLeaseRegistry.recordConversationBackup(folderPath: made.root.path, courseCode: "ICS3U", backupURL: backup)
        let pid: Int32 = getpid()
        XCTAssertEqual(
            names(in: activityDirectory(made.root)),
            ["ICS3U.assist.\(pid).lease", "ICS3U.held-backup.\(pid)"]
        )
        let recorded: String = try String(
            contentsOf: activityDirectory(made.root).appendingPathComponent("ICS3U.held-backup.\(pid)"),
            encoding: .utf8
        )
        XCTAssertEqual(recorded, backup.standardizedFileURL.path, "One line: the zip's full path.")

        WorkLeaseRegistry.removalsSeenByTests = []
        await AssistMCPServer.stopOwnWorkBeforeLeaving(stopInsideTheBuilder: { _, _, _ in })
        XCTAssertEqual(names(in: activityDirectory(made.root)), [], "Released on leaving.")
        XCTAssertNil(WorkLeaseRegistry.heldForTheConversation)
        XCTAssertEqual(
            WorkLeaseRegistry.removalsSeenByTests ?? [],
            ["ICS3U.held-backup.\(pid)", "ICS3U.assist.\(pid).lease"],
            "The records go first, then the lease."
        )
    }

    /// The server records the backup its conversation made; the app does not.
    /// MUST FAIL if the record is not written from the runner.
    func testTheServersRunnerRecordsItsBackupAndTheAppsDoesNot() async throws {
        for serving in [true, false] {
            WorkLeaseRegistry.reset()
            AssistMCPServer.isServing = serving
            let made: AssistFixture.Made = try AssistFixture.makeRunner(hasDeployedBefore: true, surface: .mcp)
            roots.append(made.root)
            ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
            try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
            _ = await AssistFixture.run("publish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner)

            let record: URL = activityDirectory(made.root)
                .appendingPathComponent(WorkLeaseFiles.heldBackupRecordName(courseCode: "ICS3U", pid: getpid()))
            if serving {
                let path: String = try String(contentsOf: record, encoding: .utf8)
                XCTAssertTrue(FileManager.default.fileExists(atPath: path), "The record names a real zip: \(path)")
                XCTAssertTrue(path.hasSuffix(".zip"), path)
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), "The app writes no record.")
            }
        }
    }

    // MARK: - Protection 1: the session's backup is kept

    func testHeldBackupRecordNamesAreTheContracts() throws {
        let block: [String: Any] = try FileFormatsContractTests.section("heldBackupRecord")
        let cases: [[String: Any]] = try XCTUnwrap(block["nameCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 4)
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            let file: String = try XCTUnwrap(item["file"] as? String)
            var expected: Int32? = nil
            if let pid = item["expectPid"] as? Int {
                expected = Int32(pid)
            }
            XCTAssertEqual(WorkLeaseFiles.pidOfHeldBackupRecord(named: file), expected, name)
        }
        XCTAssertEqual(WorkLeaseFiles.heldBackupRecordName(courseCode: "ics3u", pid: 4321), "ICS3U.held-backup.4321")
    }

    /// MUST FAIL if a record counts whose process holds no live `assist`
    /// lease — a killed session's record, or a Codex session's.
    func testARecordIsKeptOnlyWhileItsSessionHoldsALiveAssistLease() throws {
        let block: [String: Any] = try FileFormatsContractTests.section("heldBackupRecord")
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 3)
        for entry in cases {
            let name: String = entry["name"] as? String ?? "?"
            let holder: [String: Any] = try XCTUnwrap(entry["holder"] as? [String: Any])
            let leases: [String] = try XCTUnwrap(holder["leases"] as? [String])
            let alive: Bool = try XCTUnwrap(holder["alive"] as? Bool)
            let expectHeld: Bool = try XCTUnwrap(entry["expectHeld"] as? Bool)

            let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
            let backup: URL = try makeBackup(named: "ICS3U_backup_2026-10-07_120000_assistant-section1.zip", in: made.root)
            try writeOthersLeases(leases, in: made.root)
            try writeOthersRecord(naming: backup, in: made.root)
            if !alive {
                stopTheOtherProgram()
            }

            let held: Set<String> = WorkspaceModel.backupPathsHeldByOtherSessions(inWorkingFolder: made.root)
            let backupItem: BackupItem = try item(backup, in: made.workspace)
            XCTAssertEqual(held.contains(WorkspaceModel.comparablePath(of: backupItem)), expectHeld, name)

            let deletion: WorkspaceModel.BackupDeletion = made.workspace.deleteBackups([backupItem], following: [])
            XCTAssertEqual(FileManager.default.fileExists(atPath: backup.path), expectHeld, name)
            if expectHeld {
                XCTAssertEqual(deletion.keptForAClaudeSession.count, 1, name)
                XCTAssertTrue(deletion.keptForTheAssistant.isEmpty, "\(name): told as the in-app window's")
                XCTAssertEqual(
                    made.workspace.backupProblem,
                    AssistWording.finishTheClaudeSessionToDeleteItsBackup(course: "ICS3U", count: 1), name
                )
            }
            stopTheOtherProgram()
        }
    }

    /// The single "Delete Backup…" refuses at once, and the delete-several
    /// confirmation tells the two kinds of kept backup apart (ruling 7).
    func testKeptBackupsAreToldBySource() throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        let sessions: URL = try makeBackup(named: "ICS3U_backup_2026-10-07_120000_assistant-section1.zip", in: made.root)
        let windows: URL = try makeBackup(named: "ICS3U_backup_2026-10-07_130000_assistant-section1.zip", in: made.root)
        let ordinary: URL = try makeBackup(named: "ICS3U_backup_2026-10-01_090000.zip", in: made.root)
        try writeOthersLeases(["assist"], in: made.root)
        try writeOthersRecord(naming: sessions, in: made.root)
        AssistActivity.begin(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        AssistActivity.holdBackups(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1) {
            return [windows]
        }

        made.workspace.requestDeleteBackup(try item(sessions, in: made.workspace))
        XCTAssertNil(made.workspace.backupDeleteRequest)
        XCTAssertEqual(
            made.workspace.backupProblem,
            AssistWording.finishTheClaudeSessionToDeleteItsBackup(course: "ICS3U", count: 1)
        )

        let chosen: [BackupItem] = [
            try item(sessions, in: made.workspace),
            try item(windows, in: made.workspace),
            try item(ordinary, in: made.workspace),
        ]
        let message: String = WorkspaceModel.deleteConfirmation(
            for: chosen,
            sizes: [:],
            heldPaths: WorkspaceModel.heldBackupPaths(),
            active: AssistActivity.active,
            heldByOtherSessions: WorkspaceModel.backupPathsHeldByOtherSessions(inWorkingFolder: made.root)
        )
        XCTAssertTrue(message.contains("the assistant for ICS3U Section 1 is open"), message)
        XCTAssertTrue(message.contains(AssistWording.backupsKeptForAClaudeSession(course: "ICS3U", count: 1)), message)

        let deletion: WorkspaceModel.BackupDeletion = made.workspace.deleteBackups(chosen, following: [])
        XCTAssertEqual(deletion.deleted.count, 1)
        XCTAssertEqual(deletion.keptForTheAssistant.count, 1)
        XCTAssertEqual(deletion.keptForAClaudeSession.count, 1)
        let problem: String = try XCTUnwrap(made.workspace.backupProblem)
        XCTAssertTrue(problem.contains("Close the assistant for ICS3U Section 1 first"), problem)
        XCTAssertTrue(
            problem.contains(AssistWording.finishTheClaudeSessionToDeleteItsBackup(course: "ICS3U", count: 1)), problem
        )
        let trail: String = trailText(in: made.root)
        XCTAssertTrue(trail.contains("which a Claude session still open made"), trail)
    }

    // MARK: - Protection 2: a second session is refused

    /// MUST FAIL if the Revise items ignore the lease, or if the in-app
    /// window's cause is told with the outside session's sentence.
    func testTheReviseCasesAreTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["doorCourseHold"])
        let cases: [[String: Any]] = try XCTUnwrap(block["reviseCases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 9)
        let folder: String = "/folder"
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            if let platforms = item["appliesOn"] as? [String] {
                XCTAssertNotNil(item["onWindows"] as? String, "\(name): a case Windows skips says what it does instead")
                if !platforms.contains("mac") {
                    continue
                }
            }
            let which: CourseActivity.ReviseItem
            switch item["item"] as? String {
            case "claude":
                which = .claude
            case "codex":
                which = .codex
            case "local":
                which = .localAssistant
            default:
                XCTFail("Unknown item in: \(name)")
                continue
            }
            var active: AssistActivity.Session? = nil
            if let open = item["active"] as? [String: Any] {
                active = AssistActivity.Session(
                    folderPath: folder,
                    courseCode: try XCTUnwrap(open["course"] as? String),
                    sectionNumber: try XCTUnwrap(open["section"] as? Int)
                )
            }
            let reason: String? = CourseActivity.reviseUnavailableReason(
                item: which,
                folderPath: folder,
                courseCode: "ICS3U",
                sectionNumber: which == .localAssistant ? 1 : nil,
                revisedElsewhere: try XCTUnwrap(item["revisedElsewhere"] as? Bool),
                active: active
            )
            switch item["expect"] as? String {
            case nil:
                XCTAssertNil(reason, name)
            case "availableOnceYouFinishRevisingWithClaude":
                XCTAssertEqual(reason, AssistWording.availableOnceYouFinishRevisingWithClaude, name)
            case "closeTheAssistantFirst":
                XCTAssertEqual(reason, AssistActivity.closeTheAssistantFirst(try XCTUnwrap(active)), name)
            default:
                XCTFail("Unknown expect in: \(name)")
            }
        }
    }

    /// The click is checked against the DISK, not the menu's snapshot — a
    /// session can start between the menu opening and the click. MUST FAIL if
    /// the click-time re-check is removed.
    func testAClickIsRefusedWithTheMenuBypassed() throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        try writeOthersLeases(["assist"], in: made.root)
        XCTAssertFalse(made.workspace.isRevisedElsewhere("ICS3U"), "The snapshot was never refreshed.")

        for item in [CourseActivity.ReviseItem.claude, .codex, .localAssistant] {
            let refusal: WorkspaceModel.ReviseRefusal? = made.workspace.reviseRefusal(
                item: item, courseCode: "ICS3U", sectionNumber: item == .localAssistant ? 1 : nil
            )
            XCTAssertEqual(refusal, WorkspaceModel.ReviseRefusal(
                title: AssistWording.courseIsAlreadyBeingRevised(course: "ICS3U"),
                message: AssistWording.finishTheClaudeSessionFirst
            ), "\(item)")
        }
        XCTAssertTrue(made.workspace.isRevisedElsewhere("ICS3U"), "A click refreshes the snapshot.")
        XCTAssertNil(made.workspace.reviseRefusal(item: .claude, courseCode: "MPM2D", sectionNumber: nil))

        // The in-app window open on the course refuses the doors with its own
        // sentence, never the session's.
        stopTheOtherProgram()
        AssistActivity.begin(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        let refusal: WorkspaceModel.ReviseRefusal? = made.workspace.reviseRefusal(
            item: .codex, courseCode: "ICS3U", sectionNumber: nil
        )
        XCTAssertEqual(refusal?.message, AssistActivity.closeTheAssistantFirst(try XCTUnwrap(AssistActivity.active)) + ".")
        XCTAssertNil(made.workspace.reviseRefusal(item: .localAssistant, courseCode: "ICS3U", sectionNumber: 1))
    }

    /// The window's snapshot follows the disk when it is refreshed, and lets
    /// go of a session whose process has gone.
    func testTheSnapshotFollowsTheDisk() throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        made.workspace.refreshCoursesRevisedElsewhere()
        XCTAssertEqual(made.workspace.coursesRevisedElsewhere, [])
        try writeOthersLeases(["assist"], course: "mpm2d", in: made.root)
        made.workspace.refreshCoursesRevisedElsewhere()
        XCTAssertEqual(made.workspace.coursesRevisedElsewhere, ["MPM2D"])
        stopTheOtherProgram()
        made.workspace.refreshCoursesRevisedElsewhere()
        XCTAssertEqual(made.workspace.coursesRevisedElsewhere, [], "A dead owner holds nothing.")
    }

    // MARK: - Protection 3: structural work waits

    /// MUST FAIL if `structuralHoldReason` ignores the `assist` lease, or if
    /// the lease is put into `busyDescription` (a build would then refuse).
    func testStructuralWorkWaitsAndABuildDoesNot() throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        try writeOthersLeases(["assist"], in: made.root)
        let folder: String = made.root.path

        XCTAssertEqual(
            CourseActivity.structuralHoldReason(folderPath: folder, courseCode: "ICS3U"),
            AssistWording.availableOnceYouFinishRevisingWithClaude
        )
        XCTAssertNil(CourseActivity.structuralHoldReason(folderPath: folder, courseCode: "MPM2D"))
        XCTAssertNil(CourseActivity.busyDescription(folderPath: folder, courseCode: "ICS3U"),
                     "The question a build asks must not hear an assist lease.")
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: folder, courseCode: "ICS3U"))
        XCTAssertNil(
            WorkLeaseRegistry.whatBlocksABuild(folderPath: folder, courseCode: "ICS3U", afterTaking: false),
            "An assist lease never declines a build."
        )

        // The menu's snapshot, and the reason Rename reads from it.
        made.workspace.refreshCoursesRevisedElsewhere()
        made.workspace.selection = SidebarSelection.course("ICS3U")
        XCTAssertEqual(made.workspace.renameIsUnavailableReason, AssistWording.availableOnceYouFinishRevisingWithClaude)

        // A preview of the course is still said first: it is the one this
        // window started.
        _ = try PreviewLeases.lease(folderPath: folder, courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertEqual(
            CourseActivity.structuralHoldReason(folderPath: folder, courseCode: "ICS3U"),
            "Available once preview completed"
        )
        PreviewLeases.reset()
    }

    /// Rename, restore and Add Section are refused at the click with the
    /// session's own sentence. MUST FAIL if any of them goes ahead.
    func testRenameRestoreAndAddSectionAreRefusedAtTheClick() async throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        let backup: URL = try makeBackup(named: "ICS3U_backup_2026-10-01_090000.zip", in: made.root)
        try writeOthersLeases(["assist"], in: made.root)
        let ics3u: Course = try course("ICS3U", in: made.workspace)

        made.workspace.rename(ics3u, to: "ICS3X")
        XCTAssertEqual(made.workspace.renameProblem, AssistWording.claudeIsRevisingTheCourse(course: "ICS3U", then: "rename"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: made.root.appendingPathComponent("courses/ICS3U").path))

        await made.workspace.restoreBackup(try item(backup, in: made.workspace))
        XCTAssertEqual(made.workspace.backupProblem, AssistWording.claudeIsRevisingTheCourse(course: "ICS3U", then: "restore"))

        XCTAssertEqual(
            made.workspace.structuralRefusal(courseCode: "ICS3U", act: "add the section", whenBusy: "busy"),
            AssistWording.claudeIsRevisingTheCourse(course: "ICS3U", then: "add the section")
        )
        XCTAssertNil(made.workspace.structuralRefusal(courseCode: "MPM2D", act: "add the section", whenBusy: "busy"))
    }

    /// Removing a course is NOT held (Windows holds no removal; ruling 2).
    /// MUST FAIL if the hold widens to removal.
    func testRemovalIsNotHeld() async throws {
        let made: (root: URL, workspace: WorkspaceModel) = try makeFolder()
        try writeOthersLeases(["assist"], course: "MPM2D", in: made.root)
        let mpm2d: Course = try course("MPM2D", in: made.workspace)
        let result: ScheduledDeployCleanup.RemovalResult = await ScheduledDeployCleanup.removeCourse(
            mpm2d,
            coursesDirectoryURL: made.root.appendingPathComponent("courses"),
            runner: SilentLaunchControl()
        )
        XCTAssertTrue(result.didRemove, "\(String(describing: result.problem))")
    }

    // MARK: - The words

    /// None of the new sentences names the machinery (CLAUDE.md rule 1), and
    /// none uses deploy or publish (the v1.4.4 words).
    func testTheNewSentencesNameNoMachinery() {
        let every: [String] = [
            AssistWording.availableOnceYouFinishRevisingWithClaude,
            AssistWording.courseIsAlreadyBeingRevised(course: "ICS3U"),
            AssistWording.finishTheClaudeSessionFirst,
            AssistWording.claudeIsRevisingTheCourse(course: "ICS3U", then: "rename"),
            AssistWording.backupsKeptForAClaudeSession(course: "ICS3U", count: 1),
            AssistWording.backupsKeptForAClaudeSession(course: "ICS3U", count: 2),
            AssistWording.finishTheClaudeSessionToDeleteItsBackup(course: "ICS3U", count: 1),
            AssistWording.finishTheClaudeSessionToDeleteItsBackup(course: "ICS3U", count: 2),
            AssistMCPServer.holdingTrailLine(courseCode: "ICS3U"),
        ]
        for text in every {
            let lowered: String = text.lowercased()
            for word in ["toolchain", "script", "docker", "container", "lease", "process", "server", "mcp",
                         "deploy", "publish", "model", "token"] {
                XCTAssertFalse(lowered.contains(word), "'\(word)' in: \(text)")
            }
        }
    }
}
