import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `workingFolderReach` (#290): a
/// working folder the website builder cannot reach is refused when it is
/// chosen — before anything is written into it — and the folder the window
/// had stays as it was.
final class WorkingFolderReachTests: XCTestCase {

    // MARK: - Stored properties

    var scratch: URL = URL(fileURLWithPath: "/")
    var previousStore: ProblemReportStore = ActivityTrail.store

    // MARK: - Functions

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("reach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("home"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("outside"), withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratch.appendingPathComponent("trail"))
        WorkingFolderReach.homeFolderOverride = scratch.appendingPathComponent("home")
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousStore
        WorkingFolderReach.homeFolderOverride = nil
        try? FileManager.default.removeItem(at: scratch)
    }

    var home: URL {
        return scratch.appendingPathComponent("home")
    }

    var outside: URL {
        return scratch.appendingPathComponent("outside")
    }

    @MainActor
    static func section() throws -> [String: Any] {
        return try SharedRulesContractTests.section("workingFolderReach")
    }

    func makeWorkingFolder(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("courses/ABC1O"), withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: url.appendingPathComponent("preview.sh"), atomically: true, encoding: .utf8)
        try "{}".write(to: url.appendingPathComponent("courses/ABC1O/course_config.json"), atomically: true, encoding: .utf8)
    }

    /// Every entry under a folder, hidden ones included, with its size and
    /// modification date — so "nothing was written" is measured, not assumed.
    func snapshot(of url: URL) -> [String] {
        var lines: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: url.path)
        while let item = enumerator?.nextObject() as? String {
            let attributes = (try? FileManager.default.attributesOfItem(atPath: url.appendingPathComponent(item).path)) ?? [:]
            let date: Date = attributes[FileAttributeKey.modificationDate] as? Date ?? Date.distantPast
            let size: Int = attributes[FileAttributeKey.size] as? Int ?? -1
            lines.append("\(item) \(size) \(date.timeIntervalSince1970)")
        }
        return lines.sorted()
    }

    // MARK: - The contract

    @MainActor
    func testEveryPathCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(WorkingFolderReachTests.section()["pathCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for pathCase in cases {
            let name: String = pathCase["name"] as? String ?? "?"
            let verdict: Bool = WorkingFolderReach.isInside(
                canonicalFolderPath: try XCTUnwrap(pathCase["folder"] as? String),
                canonicalHomePath: try XCTUnwrap(pathCase["home"] as? String)
            )
            XCTAssertEqual(verdict ? "inside" : "refused", pathCase["expect"] as? String, "path case “\(name)”")
        }
    }

    @MainActor
    func testEveryDiskCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(WorkingFolderReachTests.section()["diskCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        for diskCase in cases {
            let name: String = diskCase["name"] as? String ?? "?"
            let make: String = try XCTUnwrap(diskCase["make"] as? String)
            let slug: String = UUID().uuidString
            var folder: URL
            switch make {
            case "plainInside":
                folder = home.appendingPathComponent(slug)
                try makeWorkingFolder(at: folder)
            case "plainOutside":
                folder = outside.appendingPathComponent(slug)
                try makeWorkingFolder(at: folder)
            case "linkOutsideToInside":
                let real: URL = home.appendingPathComponent(slug)
                try makeWorkingFolder(at: real)
                folder = outside.appendingPathComponent(slug + "-link")
                try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: real)
            case "linkInsideToOutside":
                let real: URL = outside.appendingPathComponent(slug)
                try makeWorkingFolder(at: real)
                folder = home.appendingPathComponent(slug + "-link")
                try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: real)
            case "wrongCaseSpelling":
                let real: URL = home.appendingPathComponent(slug.lowercased())
                try makeWorkingFolder(at: real)
                folder = URL(fileURLWithPath: real.path.uppercased())
            case "coursesLinkedOutside":
                folder = home.appendingPathComponent(slug)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let courses: URL = outside.appendingPathComponent(slug + "-courses")
                try FileManager.default.createDirectory(at: courses, withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("courses"), withDestinationURL: courses)
            case "coursesRelativeLinkClimbingOut":
                // The home spelled as the disk spells it, so the link's raw
                // text BEGINS with the home's names: only taking the `..`
                // away (or asking the disk) makes it outside.
                folder = URL(fileURLWithPath: FolderIdentity.canonicalPath(home.path)).appendingPathComponent(slug)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var climb: String = ""
                for _ in 0..<(folder.pathComponents.count + 2) {
                    climb += "../"
                }
                try FileManager.default.createSymbolicLink(
                    atPath: folder.appendingPathComponent("courses").path,
                    withDestinationPath: climb + "Volumes/\(slug)/courses"
                )
            case "coursesLinkDangling":
                folder = home.appendingPathComponent(slug)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(
                    atPath: folder.appendingPathComponent("courses").path,
                    withDestinationPath: "/Volumes/\(slug)/courses"
                )
            default:
                XCTFail("disk case “\(name)” has a `make` this suite does not know: \(make)")
                continue
            }
            let refusal: WorkingFolderReach.Refusal? = WorkingFolderReach.refusal(forFolder: folder)
            var verdict: String = "inside"
            if let refusal {
                verdict = refusal.whichPath == .workingFolder ? "refused" : "refusedForCourses"
            }
            XCTAssertEqual(verdict, diskCase["expect"] as? String, "disk case “\(name)”")
        }
    }

    /// The Swift sentences are the contract's, and the guidance clause is the
    /// one `app-rules.json` → `failureExplanations` and the launchers say.
    @MainActor
    func testTheWordingMatchesTheContractAndTheBuildersOwnSentence() throws {
        let wording: [String: Any] = try XCTUnwrap(WorkingFolderReachTests.section()["wording"] as? [String: Any])
        XCTAssertEqual(WorkingFolderReachWording.headline(folderName: "N"),
                       (wording["headline"] as? String)?.replacingOccurrences(of: "{folderName}", with: "N"))
        XCTAssertEqual(WorkingFolderReachWording.coursesHeadline(folderName: "N"),
                       (wording["coursesHeadline"] as? String)?.replacingOccurrences(of: "{folderName}", with: "N"))
        XCTAssertEqual(WorkingFolderReachWording.whatToDo, wording["whatToDo"] as? String)
        XCTAssertEqual(WorkingFolderReachWording.whatToDoForCourses, wording["whatToDoForCourses"] as? String)
        XCTAssertEqual(WorkingFolderReachWording.alertOKButton, wording["alertOKButton"] as? String)
        let clause: String = try XCTUnwrap(wording["sharedClauseWithFailureExplanations"] as? String)
        XCTAssertEqual(WorkingFolderReachWording.sharedClause, clause)
        XCTAssertTrue(WorkingFolderReachWording.whatToDo.contains(clause))
        XCTAssertTrue(WorkingFolderReachWording.whatToDoForCourses.contains(clause))

        let appRulesURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/app-rules.json")
        let text: String = try String(contentsOf: appRulesURL, encoding: .utf8)
        let all: [String: Any] = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let explanations: [String: Any] = try XCTUnwrap(all["failureExplanations"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(explanations["cases"] as? [[String: Any]])
        var found: Bool = false
        for explanation in cases {
            let output: String = explanation["output"] as? String ?? ""
            if output.contains("bind source path does not exist") {
                found = true
                XCTAssertTrue((explanation["expect"] as? String ?? "").contains(clause),
                              "the picker's advice and the builder's own sentence must say the same thing")
            }
        }
        XCTAssertTrue(found)
    }

    // MARK: - Choosing a folder

    /// T3: a chosen folder outside the home folder is never adopted. The
    /// window keeps its folder, nothing is written into the refused one
    /// (measured by a snapshot of a REAL working folder), nothing is
    /// remembered, and the trail says refused — never opened.
    @MainActor
    func testAChosenFolderOutsideHomeIsNeverAdopted() throws {
        let defaults: UserDefaults = TestDefaults.make()
        let current: URL = home.appendingPathComponent("A")
        try makeWorkingFolder(at: current)
        let refused: URL = outside.appendingPathComponent("School Drive Notes")
        try makeWorkingFolder(at: refused)
        let model: WorkspaceModel = WorkspaceModel(defaults: defaults)
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        model.chooseWorkspace(at: current)
        let rememberedBefore: String? = defaults.string(forKey: WorkspaceModel.storedPathKey)
        let lastBefore: String? = model.lastWorkingFolder()?.path
        let before: [String] = snapshot(of: refused)

        model.chooseWorkspace(at: refused)

        XCTAssertEqual(model.workspaceURL?.path, current.path, "the window keeps the folder it had")
        XCTAssertEqual(model.folderNotOpened?.how, .chosen)
        XCTAssertEqual(model.folderNotOpened?.reason, .outsideHome)
        XCTAssertTrue(model.folderNotOpened?.isShownAsAlert ?? false, "a window showing courses says it in an alert")
        XCTAssertEqual(snapshot(of: refused), before, "nothing may be written into a refused folder")
        XCTAssertEqual(defaults.string(forKey: WorkspaceModel.storedPathKey), rememberedBefore)
        XCTAssertEqual(model.lastWorkingFolder()?.path, lastBefore)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("refused the working folder"))
        XCTAssertTrue(trail.contains("(chosen in the picker)"))
        XCTAssertFalse(trail.contains("opened the working folder " + refused.path), "a refused folder is never 'opened'")
    }

    /// #290 review M1: refused while the PICKER is up with a folder half
    /// chosen (an empty one waiting to be set up) — said on the picker, not
    /// in an alert over it, and the half-chosen folder stays.
    @MainActor
    func testRefusedOnThePickerIsSaidOnThePicker() throws {
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let empty: URL = home.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        model.chooseWorkspace(at: empty)
        XCTAssertTrue(model.workspaceCanBeInitialized)
        XCTAssertTrue(model.isShowingPicker)

        let refused: URL = outside.appendingPathComponent("Drive")
        try FileManager.default.createDirectory(at: refused, withIntermediateDirectories: true)
        model.chooseWorkspace(at: refused)
        XCTAssertEqual(model.workspaceURL?.path, empty.path)
        XCTAssertFalse(model.folderNotOpened?.isShownAsAlert ?? true)
        XCTAssertTrue(model.folderNotOpened?.showsPathBar ?? false)
        XCTAssertEqual(model.folderNotOpened?.headline, WorkingFolderReachWording.headline(folderName: "Drive"))
    }

    /// A folder whose courses lead outside gets the sentence that is true of
    /// it — the folder itself IS in the home folder.
    @MainActor
    func testACoursesLinkGetsItsOwnTrueSentence() throws {
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let folder: URL = home.appendingPathComponent("Linked")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("courses"), withDestinationURL: outside)
        model.chooseWorkspace(at: folder)
        XCTAssertNil(model.workspaceURL)
        XCTAssertEqual(model.folderNotOpened?.reason, .coursesOutsideHome)
        XCTAssertEqual(model.folderNotOpened?.headline, WorkingFolderReachWording.coursesHeadline(folderName: "Linked"))
        XCTAssertEqual(model.folderNotOpened?.detail, WorkingFolderReachWording.whatToDoForCourses)
    }

    /// T5: the assistant's and the MCP server's route is not refused (#290 §1a).
    @MainActor
    func testTheAssistantAndMCPRouteIsNotRefused() throws {
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        let folder: URL = outside.appendingPathComponent("Served")
        try makeWorkingFolder(at: folder)
        model.adoptRestoredPath(folder.path)
        XCTAssertEqual(model.workspaceURL?.path, folder.path)
    }

    /// A remembered folder out of reach: the picker and the reopen sentence.
    @MainActor
    func testARememberedFolderOutsideHomeFallsBackToThePicker() throws {
        let model: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        WorkspaceModel.registerWindowModel(model)
        defer { WorkspaceModel.unregisterWindowModel(model) }
        let folder: URL = outside.appendingPathComponent("Old Notes")
        try makeWorkingFolder(at: folder)
        XCTAssertFalse(model.reopen(RememberedFolder.make(for: folder), occasion: .rememberedWindow))
        XCTAssertNil(model.workspaceURL)
        XCTAssertEqual(model.folderNotOpened?.detail, ReopenWording.outsideHome(folderName: "Old Notes"))
        XCTAssertTrue(ActivityTrail.store.activityText(includingPrompts: true).contains("— outsideHome"))
    }
}

/// #290 review M2: `adoptRestoredPath` adopts with NO check, so a window
/// getting a remembered folder back must never call it. Its callers are held
/// to a named list; a new one fails here until somebody decides it.
final class AdoptRestoredPathCallersTests: XCTestCase {

    // MARK: - Functions

    func testOnlyTheNamedCallersAdoptWithoutACheck() throws {
        let allowed: [String: Int] = [
            "Models/WorkspaceModel.swift": 1,          // adoptFolderForNewWindow: a requested or sibling's folder
            "Models/Assist/AssistMCPServer.swift": 1,
            "Models/Assist/AssistSession.swift": 1,
            "Models/Assist/AssistToolRunner.swift": 1,
        ]
        let productURL: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers")
        var found: [String: Int] = [:]
        let enumerator = FileManager.default.enumerator(atPath: productURL.path)
        while let item = enumerator?.nextObject() as? String {
            if !item.hasSuffix(".swift") {
                continue
            }
            let text: String = try String(contentsOf: productURL.appendingPathComponent(item), encoding: .utf8)
            var count: Int = 0
            for line in text.components(separatedBy: "\n") {
                let trimmed: String = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("func adoptRestoredPath(") {
                    continue
                }
                if trimmed.contains("adoptRestoredPath(") {
                    count += 1
                }
            }
            if count > 0 {
                found[item] = count
            }
        }
        XCTAssertEqual(found, allowed,
                       "adoptRestoredPath adopts with no check. A window getting a remembered folder back must use reopen(_:occasion:); any other new caller is a decision to make here.")
    }
}
