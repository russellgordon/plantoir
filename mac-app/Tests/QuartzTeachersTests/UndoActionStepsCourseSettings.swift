import XCTest
@testable import QuartzTeachers

/// U4a of #899: the three Course Settings actions recorded from the real
/// code into `undo-action-steps.json`, after the daily page actions.
extension UndoActionStepsTests {

    // MARK: - Functions

    /// `saveCourseSettings` (several members, `graded_folders` absent
    /// before: the first Marks tick), `addFolder` (one `createTree`, its
    /// pages' moment fixed) and `setSchoolYear` (one `editJSON`).
    func recordTheCourseSettingsActions() async throws -> [Recorded] {
        var recorded: [Recorded] = []

        let saveRoot: URL = try UndoActionStepsTests.settingsRoot()
        let saved: Course = try CourseSettingsGestureScript.makeCourse(in: saveRoot)
        recorded.append(try await record("saveCourseSettings", root: saveRoot) {
            saved.configuration.gradedFolders = ["Tests"]
            saved.configuration.hiddenItems = ["Media"]
            CourseSettingsView(course: saved).save()
        })

        let folderRoot: URL = try UndoActionStepsTests.settingsRoot()
        let added: Course = try CourseSettingsGestureScript.makeCourse(in: folderRoot)
        recorded.append(try await record("addFolder", root: folderRoot) {
            let outcome: FolderScaffold.Outcome = CourseSettingsView(course: added).createFoldersOnDisk(
                named: "Labs", scope: .shared, created: "2026-09-08T07:00:00.000-0400"
            )
            XCTAssertEqual(outcome.foldersCreated, 1)
        })

        let yearRoot: URL = try UndoActionStepsTests.settingsRoot()
        let filed: Course = try CourseSettingsGestureScript.makeCourse(in: yearRoot)
        recorded.append(try await record("setSchoolYear", root: yearRoot) {
            let day: CalendarDay = try XCTUnwrap(CalendarDay(text: "2026-11-20"))
            XCTAssertNil(SetSchoolYearSheet.write(2025, to: filed, on: day))
        })

        // U4b2-11: Rename folder from the sheet's real path
        // (`CourseSettingsView.renameFolder`, as `UndoRenameFolderStepTests`
        // drives it), a per-course folder and a per-section one: one move
        // against one per section, and a different settings member.
        let sharedRoot: URL = try UndoActionStepsTests.settingsRoot()
        let shared: Course = try UndoActionStepsTests.renameCourse(in: sharedRoot)
        recorded.append(try await record("renameFolder", root: sharedRoot) {
            let result: RenameResult = await CourseSettingsView(course: shared).renameFolder("Concepts", to: "Ideas", scope: .shared)
            guard case .renamed = result else {
                return XCTFail("renameFolder: \(result)")
            }
        })

        let perSectionRoot: URL = try UndoActionStepsTests.settingsRoot()
        let perSection: Course = try UndoActionStepsTests.renameCourse(in: perSectionRoot)
        recorded.append(try await record("renameFolderPerSection", root: perSectionRoot) {
            let result: RenameResult = await CourseSettingsView(course: perSection).renameFolder("Tasks", to: "Assessments", scope: .perSection)
            guard case .renamed = result else {
                return XCTFail("renameFolderPerSection: \(result)")
            }
        })

        return recorded
    }

    /// `UndoRenameFolderStepTests`' course: two sections, each with a
    /// per-section `Tasks`, a shared `Concepts`; a page inside section 1's
    /// `Tasks` and one inside `Concepts` that link within their folder, and
    /// section 1's index outside both, linking into each.
    static func renameCourse(in root: URL) throws -> Course {
        let courseURL: URL = root.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        for folder in ["section1/Tasks", "section2/Tasks", "Concepts"] {
            try FileManager.default.createDirectory(
                at: courseURL.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        let pages: [(path: String, text: String)] = [
            ("section1/Tasks/Quiz 1.md", "See [[Tasks/Quiz 2]].\n"),
            ("section1/index.md", "Start with [[Tasks/Quiz 1]] and [[Concepts/Arrays]].\n"),
            ("section2/Tasks/Quiz 2.md", "Quiz two.\n"),
            ("Concepts/Arrays.md", "See [[Concepts/Loops]].\n"),
            ("Concepts/Loops.md", "A loop repeats work.\n"),
        ]
        for page in pages {
            try page.text.write(to: courseURL.appendingPathComponent(page.path), atomically: true, encoding: .utf8)
        }
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1, 2],
            "num_sections": 2,
            "shared_folders": ["Concepts"],
            "per_section_folders": ["All Classes", "Tasks"],
            "per_section_files": ["index.md"],
            "hidden": ["Tasks"],
            "expandable": ["Concepts", "Tasks"],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try data.write(to: configURL)
        let loaded: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
        return Course(code: "ICS3U", directoryURL: courseURL, configuration: loaded)
    }

    /// The two rename steps' ops are, in order, the folder move(s), then the
    /// pages relinked in the order of their paths (each page a move carries
    /// named at the folder's NEW place; `ClassPages.isInPathOrder`, review 1
    /// of U4b2-11, M1: never the disk's directory order), then one
    /// `editJSON` per changed member (`opKinds.wholeOps`); the settings file
    /// is the last file named. MUST FAIL on the unsorted walk: on APFS it
    /// finds `section1/index.md` before `Ideas/Arrays.md`.
    static func assertTheRenameSteps(_ recorded: [Recorded]) {
        let expected: [String: (moves: [String], pages: [String], members: [String])] = [
            "renameFolder": (
                moves: ["courses/ICS3U/Concepts"],
                pages: ["courses/ICS3U/Ideas/Arrays.md", "courses/ICS3U/section1/index.md"],
                members: ["expandable", "shared_folders"]
            ),
            "renameFolderPerSection": (
                moves: ["courses/ICS3U/section1/Tasks", "courses/ICS3U/section2/Tasks"],
                pages: ["courses/ICS3U/section1/Assessments/Quiz 1.md", "courses/ICS3U/section1/index.md"],
                members: ["expandable", "hidden", "per_section_folders"]
            ),
        ]
        let settingsPath: String = "courses/ICS3U/course_config.json"
        var seen: Int = 0
        for step in recorded {
            guard let wanted = expected[step.name] else {
                continue
            }
            seen += 1
            var movedFrom: [String] = []
            for moved in step.folderMoves {
                movedFrom.append(moved.from)
            }
            XCTAssertEqual(movedFrom, wanted.moves, "\(step.name): the folders moved")
            var pagePaths: [String] = []
            for file in step.files {
                XCTAssertNotNil(file.before, "\(step.name): \(file.path) had no text before")
                if file.path != settingsPath {
                    pagePaths.append(file.path)
                }
            }
            XCTAssertEqual(pagePaths, wanted.pages, "\(step.name): the pages in path order, each carried one at the NEW place")
            XCTAssertEqual(step.files.last?.path, settingsPath, "\(step.name): the settings file last")
            var memberNames: [String] = []
            for member in step.members {
                memberNames.append(member.keyPath.first ?? "")
            }
            XCTAssertEqual(memberNames, wanted.members, "\(step.name): the settings members")
            var kinds: [String] = []
            for _ in step.folderMoves {
                kinds.append("move")
            }
            for _ in pagePaths {
                kinds.append("page")
            }
            for _ in step.members {
                kinds.append("editJSON")
            }
            var recordedKinds: [String] = []
            for kind in step.opKinds {
                if kind == "move" || kind == "editJSON" {
                    recordedKinds.append(kind)
                } else {
                    recordedKinds.append("page")
                }
            }
            XCTAssertEqual(recordedKinds, kinds, "\(step.name): op kinds in order \(step.opKinds)")
        }
        XCTAssertEqual(seen, 2, "both rename steps are recorded")
    }

    /// The committed `undo-action-steps.json` is READ for its folder moves:
    /// each `listingSha` is the listing its `folders` and `files` make, no
    /// file the step names is at or inside a moved folder's `from`, and each
    /// step names at least one page inside a `to` (carried, named at the
    /// NEW place): a step recorded with its carried pages at the OLD place,
    /// or a listing that is not the folder's, is red here.
    func testEveryRecordedFolderMoveHoldsTheListingItNames() throws {
        let document: [String: Any] = try UndoContractReplay.contract("undo-action-steps.json")
        var checked: Int = 0
        for step in document["steps"] as? [[String: Any]] ?? [] {
            let name: String = step["name"] as? String ?? "?"
            guard let folderMoves = step["folderMoves"] as? [[String: Any]] else {
                continue
            }
            for moved in folderMoves {
                let folders: [String] = moved["folders"] as? [String] ?? []
                var files: [String: Data] = [:]
                for (path, text) in moved["files"] as? [String: String] ?? [:] {
                    files[path] = Data(text.utf8)
                }
                XCTAssertEqual(
                    UndoActionStepsTests.listingSha(folders: folders, files: files), moved["listingSha"] as? String,
                    "\(name): \(moved["from"] as? String ?? "?")'s listing"
                )
                checked += 1
            }
            var carried: Int = 0
            for file in step["files"] as? [[String: Any]] ?? [] {
                let path: String = file["path"] as? String ?? ""
                for moved in folderMoves {
                    let from: String = moved["from"] as? String ?? ""
                    XCTAssertNil(UndoOp.partInside(from, of: path), "\(name): \(path) is named at the place the folder left")
                }
                for moved in folderMoves {
                    guard let rest = UndoOp.partInside(moved["to"] as? String ?? "", of: path) else {
                        continue
                    }
                    carried += 1
                    let listed: [String: String] = moved["files"] as? [String: String] ?? [:]
                    XCTAssertEqual(file["before"] as? String, listed[rest], "\(name): \(path)'s before is not its text in the folder before")
                }
            }
            XCTAssertGreaterThan(carried, 0, "\(name): no page named inside a moved folder's new place")
        }
        XCTAssertEqual(checked, 3, "the two rename steps' three folder moves")
    }

    /// A regeneration on another day keeps each committed moment of a line
    /// that is otherwise the same, and a new line as written (review 1 of
    /// U4b2-6, L4).
    func testARegenerationKeepsTheCommittedMomentOfALineOtherwiseTheSame() {
        let committed: Data = Data("{\n  \"recorded\" : \"2026-11-20\",\n  \"name\" : \"a\"\n}\n".utf8)
        let written: Data = Data("{\n  \"recorded\" : \"2026-11-26\",\n  \"name\" : \"a\",\n  \"answeredAt\" : \"2026-11-26T01:00:00Z\"\n}\n".utf8)
        let kept: String = String(decoding: UndoActionStepsTests.keepingTheCommittedMoments(written, committed: committed), as: UTF8.self)
        XCTAssertEqual(
            kept, "{\n  \"recorded\" : \"2026-11-20\",\n  \"name\" : \"a\",\n  \"answeredAt\" : \"2026-11-26T01:00:00Z\"\n}\n"
        )
    }

    /// An empty working folder of its own, removed when the test ends.
    static func settingsRoot() throws -> URL {
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("undo-action-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        TemporaryFolders.removeWhenThisTestEnds(root)
        return root
    }
}
