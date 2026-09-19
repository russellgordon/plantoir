import XCTest
@testable import QuartzTeachers

/// What a window lets go of when it is pointed at a different working
/// folder — GitHub issue #93.
///
/// The defect: with a course selected, choosing a different folder left
/// `selection` pointing at a course the new folder had never had, so the
/// detail pane read "Course Not Found" about a folder the teacher had only
/// just arrived in. The rule that replaced it is one sentence — anything
/// that names a course, an archive or a backup in the folder being left
/// goes — and it is written down in `contracts/shared-rules.json` →
/// `workingFolderSelection`, which `SharedRulesContractTests` runs as data.
/// These tests are the same rule exercised through the real model, plus the
/// two things the contract cannot carry: that nothing is chosen in the new
/// folder, and that every pending request and alert goes too.
@MainActor
final class WorkingFolderSelectionTests: XCTestCase {

    // MARK: - Choosing a different folder

    /// The defect itself. Fails on the old behaviour.
    func testChoosingADifferentFolderClearsTheSelection() throws {
        let firstFolder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: firstFolder) }
        let emptyFolder: URL = try makeFolderWithNoCourses()
        defer { try? FileManager.default.removeItem(at: emptyFolder) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: firstFolder)
        workspace.selection = .section("EXC2O", 1)
        XCTAssertNotNil(workspace.selectedCourse, "the fixture's course should be there to select")

        workspace.chooseWorkspace(at: emptyFolder)

        XCTAssertNil(
            workspace.selection,
            "A course in the folder that was left must not still be selected in the folder arrived in"
        )
        XCTAssertTrue(workspace.courses.isEmpty, "the second folder has no courses")
    }

    /// The same code in a different folder is a DIFFERENT course, and
    /// landing on it would be a guess dressed up as a memory. Fails on the
    /// old behaviour, and for a reason the obvious fix — checking the
    /// selection against the courses just loaded — would not have caught.
    func testADifferentFolderWithTheSameCourseCodeClearsTheSelectionToo() throws {
        let firstFolder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: firstFolder) }
        let secondFolder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: secondFolder) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: firstFolder)
        workspace.selection = .course("EXC2O")

        workspace.chooseWorkspace(at: secondFolder)

        XCTAssertEqual(workspace.courses.count, 1, "both fixtures carry a course of the same code")
        XCTAssertEqual(workspace.courses[0].code, "EXC2O")
        XCTAssertNil(
            workspace.selection,
            "A course wearing the same code in another folder is a different course"
        )
    }

    /// Nothing is chosen on the teacher's behalf in the folder they have
    /// just arrived in, even when there is an obvious candidate.
    func testANewFolderSelectsNothingByItself() throws {
        let folder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: folder) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folder)

        XCTAssertFalse(workspace.courses.isEmpty, "there is a course to have been chosen")
        XCTAssertNil(workspace.selection, "the empty state says what to do; guessing does not")
    }

    // MARK: - Choosing the SAME folder again

    /// Re-choosing the folder this window already shows is not a change of
    /// folder, and must cost the teacher nothing. It happens: the picker is
    /// reachable while a folder is open, and the cloud-sync note already
    /// treats this case separately for the same reason.
    func testChoosingTheSameFolderAgainKeepsEverything() throws {
        let folder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: folder) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folder)
        workspace.selection = .section("EXC2O", 2)
        workspace.filterText = "EXC"
        workspace.expandedCourseCodes = ["EXC2O"]

        workspace.chooseWorkspace(at: folder)

        XCTAssertEqual(workspace.selection, .section("EXC2O", 2))
        XCTAssertEqual(workspace.filterText, "EXC")
        XCTAssertEqual(workspace.expandedCourseCodes, ["EXC2O"])
    }

    // MARK: - A course that vanishes from the folder still in use

    /// "Course Not Found" is the right answer here and must survive. A
    /// teacher who deletes a course in Finder while its window is open is
    /// looking at a selection that genuinely no longer exists, and the
    /// sentence tells them so. This is what a selection validated inside
    /// `reloadCourses()` would have thrown away.
    func testACourseThatDisappearsFromThisFolderStillReadsAsNotFound() throws {
        let folder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: folder) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: folder)
        workspace.selection = .course("EXC2O")

        try FileManager.default.removeItem(
            at: folder.appendingPathComponent("courses").appendingPathComponent("EXC2O")
        )
        workspace.reloadCourses()

        XCTAssertEqual(
            workspace.selection, .course("EXC2O"),
            "The folder has not changed, so the selection is still the teacher's"
        )
        XCTAssertNil(workspace.selectedCourse, "and it names nothing, which is what the pane says")
    }

    // MARK: - Everything else that names something in the old folder

    /// The pending confirmations and the alerts. Each holds, or describes,
    /// something in the folder being left: answering one after the window
    /// has moved would act in a folder nobody is looking at.
    func testPendingRequestsAndAlertsGoWithTheOldFolder() throws {
        let firstFolder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: firstFolder) }
        let secondFolder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: secondFolder) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: firstFolder)
        let course: Course = try XCTUnwrap(workspace.courses.first)

        let archive: ArchivedItem = ArchivedItem(
            courseCode: "EXC2O",
            sectionNumber: 1,
            archivedAt: Date(timeIntervalSince1970: 1_786_000_000),
            fileURL: firstFolder.appendingPathComponent("courses/EXC2O-section1.zip")
        )
        let backup: BackupItem = BackupItem(
            courseCode: "EXC2O",
            backedUpAt: Date(timeIntervalSince1970: 1_786_000_000),
            fileURL: firstFolder.appendingPathComponent("courses/EXC2O-backup.zip"),
            maker: .teacher
        )
        workspace.renamingCourseCode = "EXC2O"
        workspace.restoreRequest = archive
        workspace.archiveDeleteRequest = archive
        workspace.backupRestoreRequest = backup
        workspace.backupDeleteRequest = backup
        workspace.obsidianRenameRequest = CourseRenamer.ObsidianRequest(
            course: course, requestedCode: "EXC3O", openVaultPaths: [course.directoryURL.path]
        )
        workspace.renameProblem = "Could not rename EXC2O."
        workspace.renameNotice = CourseRenamer.Notice(
            title: "Renamed", message: "The scheduled publish was turned off."
        )
        workspace.restoreProblem = "Could not restore that archive."
        workspace.backupProblem = "Could not restore that backup."

        workspace.chooseWorkspace(at: secondFolder)

        XCTAssertNil(workspace.renamingCourseCode)
        XCTAssertNil(workspace.restoreRequest)
        XCTAssertNil(workspace.archiveDeleteRequest)
        XCTAssertNil(workspace.backupRestoreRequest)
        XCTAssertNil(workspace.backupDeleteRequest)
        XCTAssertNil(workspace.obsidianRenameRequest)
        XCTAssertNil(workspace.renameProblem)
        XCTAssertNil(workspace.renameNotice)
        XCTAssertNil(workspace.restoreProblem)
        XCTAssertNil(workspace.backupProblem)
    }

    /// The filter field is a way of LOOKING rather than a thing named, so it
    /// survives the move. Pinned because it is the one field the rule above
    /// deliberately does not reach, and a later reading of "clear the
    /// window's state" would take it.
    func testTheFilterFieldSurvivesAFolderChange() throws {
        let firstFolder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: firstFolder) }
        let secondFolder: URL = try FixtureWorkspace.materialize()
        defer { try? FileManager.default.removeItem(at: secondFolder) }

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: firstFolder)
        workspace.filterText = "3U"

        workspace.chooseWorkspace(at: secondFolder)

        XCTAssertEqual(workspace.filterText, "3U")
    }

    // MARK: - Where the preview's stop is aimed

    /// A folder change tears the section view down, and its `onDisappear`
    /// runs when the window ALREADY points at the new folder. Anything that
    /// unwinds there must therefore use the folder the section's work
    /// belongs to, not the model's current one — or the old folder's
    /// container-side build is never reclaimed (when another window still
    /// holds that folder; see `documentation/09-mac-app.md`) and a stale
    /// entry is left in `SectionWindowControllers`, which is keyed by folder
    /// path and which no release of a container ever tidies.
    ///
    /// A source scan because there is no other seam: no real
    /// `SectionDetailView` ever mounts in a unit test (see
    /// `AssistRevealsSectionOnScreenTests`, which says the same of itself),
    /// so this is a deletion guard rather than a behavioural test. The
    /// behaviour itself was verified by reading the teardown path.
    ///
    /// It guards BOTH halves on purpose. A scan that only checked the stops
    /// would stay green if the line that CAPTURES the folder were deleted —
    /// every stop would then read a permanently nil property and quietly do
    /// nothing at all, which is the failure the fix exists to prevent
    /// wearing the shape of the fix working.
    func testTheSectionViewStopsAgainstTheFolderItsWorkBelongsTo() throws {
        let source: String = try readSource("QuartzTeachers/Views/Section/SectionDetailView.swift")

        // The stops, which must read the captured folder and never the model.
        let stops: [String] = [
            "func stopPreview()", "func stopPreviewAndWait()", "func cancelPreview()", "func cancelDeploy()",
        ]
        for function in stops {
            let body: String = try XCTUnwrap(
                bodyOfFunction(startingWith: function, in: source),
                "\(function) is no longer in SectionDetailView"
            )
            XCTAssertTrue(
                body.contains("folderThisSectionWorksIn"),
                "\(function) must stop against the folder this section's work belongs to"
            )
            XCTAssertFalse(
                body.contains("workspace.workspaceURL"),
                "\(function) runs after a folder change has moved the window on, so the model's "
                + "current folder is the wrong one to aim at"
            )
        }

        // The captures, without which every one of those stops is a no-op.
        // A folder is decided in three places and each has to write it down.
        let captures: [(where: String, why: String)] = [
            (
                ".onAppear {",
                "the unregister in onDisappear must name the folder this section registered under"
            ),
            (
                "func startPreview()",
                "a preview can start from the model on an appearance that had no folder, and "
                    + "nothing would ever reclaim it"
            ),
            (
                "func deployAndWait()",
                "cancelDeploy reclaims the container-side build against the folder noted here"
            ),
        ]
        for capture in captures {
            let body: String = try XCTUnwrap(
                bodyOfFunction(startingWith: capture.where, in: source),
                "\(capture.where) is no longer in SectionDetailView"
            )
            XCTAssertTrue(
                body.contains("folderThisSectionWorksIn = "),
                "\(capture.where) must note the folder it is working in — \(capture.why)"
            )
        }

        // And the appearance has to note it BEFORE it registers, or a
        // registration made under one folder could be unregistered under
        // another — the stale-key half of the same bug.
        let appearance: String = try XCTUnwrap(
            bodyOfFunction(startingWith: ".onAppear {", in: source)
        )
        let noted: Range<String.Index> = try XCTUnwrap(
            appearance.range(of: "folderThisSectionWorksIn = ")
        )
        let registered: Range<String.Index> = try XCTUnwrap(
            appearance.range(of: "SectionWindowControllers.shared.register("),
            "onAppear no longer registers this section"
        )
        XCTAssertTrue(
            noted.lowerBound < registered.lowerBound,
            "the folder must be noted before the section registers under it"
        )

        let teardown: String = try XCTUnwrap(
            bodyOfFunction(startingWith: ".onDisappear {", in: source),
            "SectionDetailView no longer has an onDisappear"
        )
        XCTAssertTrue(
            teardown.contains("folderThisSectionWorksIn"),
            "unregistering must name the folder the section registered under"
        )
        XCTAssertFalse(
            teardown.contains("workspace.workspaceURL"),
            "by onDisappear the window may already point somewhere else"
        )
    }

    // MARK: - Functions

    /// A real working folder with an empty `courses/` — the state a teacher
    /// meets when they set up a folder and have not added anything yet, and
    /// the folder the defect was first seen against.
    private func makeFolderWithNoCourses() throws -> URL {
        let folder: URL = try FixtureWorkspace.materialize()
        try FileManager.default.removeItem(
            at: folder.appendingPathComponent("courses").appendingPathComponent("EXC2O")
        )
        return folder
    }

    private func readSource(_ relativePath: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The text from an opening brace to the matching closing one, so a scan
    /// reads one function rather than the whole file.
    private func bodyOfFunction(startingWith opening: String, in source: String) -> String? {
        guard let start = source.range(of: opening) else {
            return nil
        }
        guard let firstBrace = source[start.lowerBound...].firstIndex(of: "{") else {
            return nil
        }
        var depth: Int = 0
        var body: String = ""
        for character in source[firstBrace...] {
            body.append(character)
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return body
                }
            }
        }
        return nil
    }
}
