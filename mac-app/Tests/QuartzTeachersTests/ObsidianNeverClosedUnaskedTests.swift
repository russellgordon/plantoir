import XCTest
@testable import QuartzTeachers

/// Plantoir never closes Obsidian without asking (#995, finding D21 of #975,
/// Russell's ruling Q13): the rule, the words and every route, against
/// `contracts/shared-rules.json` → `obsidianNeverClosedUnasked`.
///
/// No test here reaches the teacher's Obsidian: the route is driven through
/// `WorkspaceModel.obsidianOpening`, whose every door to Obsidian and its
/// list of vaults is replaced by a stand-in that writes in `Log`.
@MainActor
final class ObsidianNeverClosedUnaskedTests: XCTestCase {

    // MARK: - Setting up

    override func setUp() async throws {
        ObsidianFigureAddOnsThisRun.forget()
    }

    override func tearDown() async throws {
        ObsidianFigureAddOnsThisRun.forget()
    }

    // MARK: - The rule and the words

    func testEveryCloseCase() throws {
        let closeCases: [String: Any] = try XCTUnwrap(try ObsidianNeverClosedUnaskedTests.rules()["closeCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(closeCases["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let running: Bool = try XCTUnwrap(testCase["running"] as? Bool, name)
            let target: String = try XCTUnwrap(testCase["target"] as? String, name)
            let expected: Bool = try XCTUnwrap(testCase["ask"] as? Bool, name)
            var registryData: Data? = nil
            if let vaults = testCase["registryVaults"] as? [String] {
                registryData = try ObsidianFigureAddOnsTests.registry(vaults: vaults)
            }
            XCTAssertEqual(
                ObsidianClosingRule.mustAsk(targetPath: target, obsidianRunning: running, registryData: registryData),
                expected, name
            )
        }
    }

    func testTheWordsAreTheContracts() throws {
        let wording: [String: Any] = try XCTUnwrap(try ObsidianNeverClosedUnaskedTests.rules()["wording"] as? [String: Any])
        XCTAssertEqual(wording["title"] as? String, ObsidianClosingWording.title)
        XCTAssertEqual(wording["message"] as? String, ObsidianClosingWording.message)
        XCTAssertEqual(wording["closesLabel"] as? String, ObsidianClosingWording.closesLabel)
        XCTAssertEqual(wording["closesValue"] as? String, ObsidianClosingWording.closesValue)
        XCTAssertEqual(wording["opensAgainLabel"] as? String, ObsidianClosingWording.opensAgainLabel)
        XCTAssertEqual(wording["opensAgainValue"] as? String, ObsidianClosingWording.opensAgainValue)
        XCTAssertEqual(wording["keptLabel"] as? String, ObsidianClosingWording.keptLabel)
        XCTAssertEqual(wording["keptValue"] as? String, ObsidianClosingWording.keptValue)
        XCTAssertEqual(wording["closeAndOpen"] as? String, ObsidianClosingWording.closeAndOpen)
        XCTAssertEqual(wording["cancel"] as? String, ObsidianClosingWording.cancel)
        XCTAssertEqual(wording["offerAddClosingObsidian"] as? String, ObsidianClosingWording.offerAddClosingObsidian)

        XCTAssertEqual(ObsidianClosingWording.titleText(course: "MPM2D"), "Close Obsidian to open MPM2D?")
        let message: String = ObsidianClosingWording.messageText(course: "MPM2D")
        let expected: String = ObsidianClosingWording.filling(ObsidianClosingWording.message, course: "MPM2D")
            + "\n\nCloses: Obsidian, with every course open in it"
            + "\nOpens again: MPM2D, and each course Obsidian had on screen"
            + "\nKept: Everything you have written"
        XCTAssertEqual(message, expected)
        // The go-ahead buttons say Obsidian closes (ruling Q13), and Cancel
        // is the one that backs out (HIG, Alerts).
        XCTAssertTrue(ObsidianClosingWording.closeAndOpen.hasPrefix("Close Obsidian"))
        XCTAssertTrue(ObsidianClosingWording.offerAddClosingObsidian.hasPrefix("Close Obsidian"))
        XCTAssertEqual(ObsidianClosingWording.cancel, "Cancel")
    }

    /// The words never name the machinery (CLAUDE.md rule 1, and the add-ons
    /// offer's own list of banned words).
    func testTheWordsNeverNameTheMachinery() throws {
        let wording: [String: Any] = try XCTUnwrap(try ObsidianNeverClosedUnaskedTests.rules()["wording"] as? [String: Any])
        let banned: [String] = ["plugin", "vault", "json", "folder", "script", "toolchain", "registry", "docker", "container"]
        for (key, value) in wording {
            if key == "factsRule" {
                continue
            }
            let words: String = try XCTUnwrap(value as? String, key).lowercased()
            for word in banned {
                XCTAssertFalse(words.contains(word), "wording.\(key) says \(word)")
            }
        }
    }

    /// The offer's yes says Obsidian closes exactly when it does.
    func testTheOffersYesSaysWhenItClosesObsidian() throws {
        let course: Course = try drive().course
        let folder: URL = course.directoryURL
        let closed: ObsidianAddOnsRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: [], openState: .closed)
        let open: ObsidianAddOnsRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: [], openState: .open)
        let cannotTell: ObsidianAddOnsRequest = ObsidianAddOnsRequest(course: course, folder: folder, needed: [], openState: .cannotTell)
        XCTAssertEqual(closed.addButtonTitle, ObsidianFigureAddOnsWording.offerAdd)
        XCTAssertEqual(open.addButtonTitle, ObsidianClosingWording.offerAddClosingObsidian)
        XCTAssertEqual(cannotTell.addButtonTitle, ObsidianClosingWording.offerAddClosingObsidian)
    }

    // MARK: - The route

    /// The route D21 found: Obsidian running, the course not in its list.
    /// Nothing is closed or opened until the teacher answers; Cancel leaves
    /// both alone; Close Obsidian and Open closes, adds and opens.
    func testARunningObsidianIsNeverClosedForACourseItHasNeverSeen() async throws {
        let made: Driven = try drive()
        made.log.running = true
        made.log.registryVaults = ["/elsewhere/Other"]

        let opened: Bool = made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        XCTAssertFalse(opened, "opened while a question waits")
        XCTAssertEqual(made.log.opened, [])
        XCTAssertEqual(made.log.closes, [], "Obsidian closed without asking")
        let request: ObsidianClosingRequest = try XCTUnwrap(made.workspace.obsidianClosingRequest, "the question is waiting")
        XCTAssertEqual(request.course.code, made.course.code)

        await made.workspace.answerObsidianClosing(request, closeObsidian: false)
        XCTAssertNil(made.workspace.obsidianClosingRequest)
        XCTAssertEqual(made.log.opened, [], "Cancel opened something")
        XCTAssertEqual(made.log.closes, [], "Cancel closed Obsidian")

        made.workspace.openInObsidian(course: made.course, sectionNumber: 1)
        let second: ObsidianClosingRequest = try XCTUnwrap(made.workspace.obsidianClosingRequest)
        await made.workspace.answerObsidianClosing(second, closeObsidian: true)
        XCTAssertEqual(made.log.closes, [made.course.directoryURL.path], "closed once, for this course")
        XCTAssertEqual(made.log.opened, [made.course.sectionDirectoryURL(forSection: 1).path], "then the section opened")
        XCTAssertNil(made.workspace.obsidianClosingRequest)
    }

    /// The assistant's press waits for the answer like any other.
    func testTheAssistantsPressSaysItIsWaiting() async throws {
        let made: Driven = try drive()
        made.log.running = true
        made.log.registryVaults = []
        let press: OpenInObsidianPress = await made.workspace.openInObsidianAndWait(course: made.course, sectionNumber: 1) { _ in }
        XCTAssertEqual(press, .waitingForAnAnswer)
        XCTAssertEqual(made.log.closes, [])
        XCTAssertEqual(made.log.opened, [])
    }

    /// Nothing is asked where nothing closes: Obsidian not running, or the
    /// course already in its list.
    func testNothingIsAskedWhenNothingCloses() throws {
        let made: Driven = try drive()
        made.log.running = false
        made.log.registryVaults = []
        XCTAssertTrue(made.workspace.openInObsidian(course: made.course, sectionNumber: nil))
        XCTAssertNil(made.workspace.obsidianClosingRequest)

        made.log.running = true
        made.log.registryVaults = [made.course.directoryURL.path]
        XCTAssertTrue(made.workspace.openInObsidian(course: made.course, sectionNumber: nil))
        XCTAssertNil(made.workspace.obsidianClosingRequest)
        XCTAssertEqual(made.log.opened.count, 2)
        XCTAssertEqual(made.log.closes, [])
    }

    /// Course Settings' How I Teach row asks the same question.
    func testHowITeachAsksTheSameQuestion() throws {
        let made: Driven = try drive()
        made.log.running = true
        made.log.registryVaults = []
        let page: URL = made.course.directoryURL.appendingPathComponent(HowITeachPage.fileName)
        made.workspace.openHowITeachPageInObsidian(page, course: made.course)
        XCTAssertNotNil(made.workspace.obsidianClosingRequest)
        XCTAssertEqual(made.log.openedPages, [])
        XCTAssertEqual(made.log.closes, [])
    }

    // MARK: - Nothing else can close it

    /// The only code that closes Obsidian is the answer to a question that
    /// says so: the closing question's answer (through
    /// `FolderActions.closeObsidianAndRegister`), the add-ons offer's and
    /// the reopen question's (through `ObsidianOpening.quitAndWait`), and
    /// the rename's (`renameClosingObsidian`). Until #995
    /// `FolderActions.open` quit Obsidian itself, unasked.
    func testOnlyAnAnswerClosesObsidian() throws {
        let source: URL = UserFacingLabelWordsTests.macAppRoot().appendingPathComponent("QuartzTeachers")
        var callers: [String] = []
        var terminators: [String] = []
        var registrations: [String] = []
        var directPageOpens: [String] = []
        for file in UserFacingLabelWordsTests.swiftFiles(under: source) {
            let code: String = TextFieldStyleScanTests.codeWithoutComments(try String(contentsOf: file, encoding: .utf8))
            let quits: Int = SaveEnablesTests.occurrences(of: "quitObsidianAndWait()", in: code)
            if quits > 0 {
                callers.append(file.lastPathComponent + " x" + String(quits))
            }
            if code.contains("md.obsidian") && code.contains(".terminate()") {
                terminators.append(file.lastPathComponent)
            }
            let registers: Int = SaveEnablesTests.occurrences(of: "closeObsidianAndRegister(", in: code)
            if registers > 0 {
                registrations.append(file.lastPathComponent + " x" + String(registers))
            }
            let pageOpens: Int = SaveEnablesTests.occurrences(of: "FolderActions.openPageInObsidian(", in: code)
            if pageOpens > 0 {
                directPageOpens.append(file.lastPathComponent + " x" + String(pageOpens))
            }
        }
        // FolderActions: the definition and closeObsidianAndRegister's own
        // call. The route: ObsidianOpening.quitAndWait's default. The model:
        // renameClosingObsidian.
        XCTAssertEqual(callers.sorted(), ["FolderActions.swift x2", "OpenInObsidianRoute.swift x1", "WorkspaceModel.swift x1"])
        XCTAssertEqual(terminators, ["FolderActions.swift"], "only quitObsidianAndWait ends Obsidian")
        // The definition, and ObsidianOpening.closeAndRegister's default.
        XCTAssertEqual(registrations.sorted(), ["FolderActions.swift x1", "OpenInObsidianRoute.swift x1"])
        // Only the route's own door opens a page; How I Teach goes through it.
        XCTAssertEqual(directPageOpens, ["OpenInObsidianRoute.swift x1"])

        let folderActions: String = TextFieldStyleScanTests.codeWithoutComments(try String(
            contentsOf: source.appendingPathComponent("Views/Helpers/FolderActions.swift"), encoding: .utf8
        ))
        let openBody: String = try XCTUnwrap(ObsidianNeverClosedUnaskedTests.body(of: "private static func open(target", in: folderActions))
        XCTAssertFalse(openBody.contains("quitObsidianAndWait"), "FolderActions.open closes Obsidian")
        let answer: String = try XCTUnwrap(ObsidianNeverClosedUnaskedTests.body(
            of: "func answerObsidianClosing(", in: TextFieldStyleScanTests.codeWithoutComments(try String(
                contentsOf: source.appendingPathComponent("Models/OpenInObsidianRoute.swift"), encoding: .utf8
            ))
        ))
        XCTAssertTrue(answer.contains("closeAndRegister"))
    }

    // MARK: - Helpers

    @MainActor
    final class Log {
        var opened: [String] = []
        var openedPages: [String] = []
        var closes: [String] = []
        var running: Bool = false
        var registryVaults: [String] = []
    }

    struct Driven {
        let workspace: WorkspaceModel
        let course: Course
        let log: Log
    }

    /// A fixture course and a workspace whose every door to Obsidian is a
    /// stand-in. The add-ons answer is no, so no scan runs and the route
    /// opens at once: the question under test is the only one asked.
    func drive() throws -> Driven {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fixtureURL)
        }
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: fixtureURL.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: fixtureURL.appendingPathComponent("trail-\(UUID().uuidString)"))
        addTeardownBlock {
            ActivityTrail.store = previous
        }
        let settings: AppSettings = AppSettings(defaults: TestDefaults.make())
        settings.obsidianFigureAddOns = .no
        let log: Log = Log()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        var opening: ObsidianOpening = ObsidianOpening()
        opening.settings = settings
        opening.isInstalled = { return true }
        opening.isRunning = { return log.running }
        opening.registryData = {
            return try? ObsidianFigureAddOnsTests.registry(vaults: log.registryVaults, open: true)
        }
        opening.open = { folder, _ in
            log.opened.append(folder.path)
        }
        opening.openPage = { page, _ in
            log.openedPages.append(page.path)
        }
        opening.quitAndWait = {
            log.closes.append("quit")
        }
        opening.closeAndRegister = { vault in
            log.closes.append(vault.path)
            log.registryVaults.append(vault.path)
        }
        opening.reopen = { _ in }
        opening.previewedAddress = { _, _, _ in
            return nil
        }
        workspace.obsidianOpening = opening
        return Driven(workspace: workspace, course: course, log: log)
    }

    /// The text from `signature` to the brace that closes its body.
    static func body(of signature: String, in code: String) -> String? {
        guard let start = code.range(of: signature) else {
            return nil
        }
        var depth: Int = 0
        var opened: Bool = false
        var index: String.Index = start.lowerBound
        while index < code.endIndex {
            let character: Character = code[index]
            if character == "{" {
                depth += 1
                opened = true
            } else if character == "}" {
                depth -= 1
                if opened && depth == 0 {
                    return String(code[start.lowerBound...index])
                }
            }
            index = code.index(after: index)
        }
        return nil
    }

    static func rules() throws -> [String: Any] {
        return try SharedRulesContractTests.section("obsidianNeverClosedUnasked")
    }
}
