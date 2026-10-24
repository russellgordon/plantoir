import XCTest
@testable import QuartzTeachers

/// Open in Obsidian opens the file behind the page a section's preview shows
/// (#518): every case in `contracts/shared-rules.json` →
/// `obsidianOpensThePreviewedPage`, deserialised and run against
/// `PreviewedPageSource` — never retyped — plus the route itself with every
/// door to Obsidian faked (which press opens the page, the trail line each
/// press writes, the page carried through the locked-pages note and the
/// add-ons offer), and source scans of the wiring no unit test can build.
@MainActor
final class ObsidianOpensThePreviewedPageTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Setting up

    override func setUp() async throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("obsidian-previewed-page-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        ObsidianFigureAddOnsThisRun.forget()
    }

    override func tearDown() async throws {
        ObsidianFigureAddOnsThisRun.forget()
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func contract() throws -> [String: Any] {
        return try SharedRulesContractTests.section("obsidianOpensThePreviewedPage")
    }

    // MARK: - The cases

    /// The fixture's course folder: every listed file, 'Café Notes.md' in
    /// NFD, and the outside file beside the course folder.
    func makeFixtureCourse() throws -> URL {
        let fixture: [String: Any] = try XCTUnwrap(try ObsidianOpensThePreviewedPageTests.contract()["fixture"] as? [String: Any])
        let courseURL: URL = rootURL.appendingPathComponent("courses").appendingPathComponent("ICS3U")
        let files: [String] = try XCTUnwrap(fixture["files"] as? [String])
        var everyFile: [String] = files
        everyFile.append(try XCTUnwrap(fixture["outside"] as? String))
        for file in everyFile {
            var name: String = file
            if file.precomposedStringWithCanonicalMapping.hasSuffix("Café Notes.md") {
                name = file.decomposedStringWithCanonicalMapping
            }
            let url: URL = courseURL.appendingPathComponent(name).standardizedFileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("A page.\n".utf8).write(to: url)
        }
        return courseURL
    }

    func testEveryCase() throws {
        let contract: [String: Any] = try ObsidianOpensThePreviewedPageTests.contract()
        let fixture: [String: Any] = try XCTUnwrap(contract["fixture"] as? [String: Any])
        let fixturePages: [String: Any] = try XCTUnwrap(fixture["pages"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(contract["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 20)
        let courseURL: URL = try makeFixtureCourse()
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let address: String? = testCase["address"] as? String
            var listData: Data?
            if testCase.keys.contains("list") {
                if let list = testCase["list"] as? [String: Any] {
                    listData = try JSONSerialization.data(withJSONObject: list)
                }
            } else {
                let pages: [String: Any] = (testCase["pages"] as? [String: Any]) ?? fixturePages
                listData = try JSONSerialization.data(withJSONObject: ["version": 1, "course": "ICS3U", "section": 1, "pages": pages])
            }
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            let answer: PreviewedPageSource.Answer = PreviewedPageSource.resolve(
                address: address, listData: listData, courseFolder: courseURL
            )
            if let opens = expect["opens"] as? String {
                let hidden: Bool = try XCTUnwrap(expect["hidden"] as? Bool)
                guard case .page(let file, let place, let wasHidden) = answer else {
                    XCTFail("\(name): \(answer)")
                    continue
                }
                XCTAssertEqual(file.path.precomposedStringWithCanonicalMapping,
                               courseURL.appendingPathComponent(opens).path.precomposedStringWithCanonicalMapping, name)
                XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), name)
                XCTAssertEqual(place.precomposedStringWithCanonicalMapping,
                               String(opens.dropLast(3)).precomposedStringWithCanonicalMapping, name)
                XCTAssertEqual(wasHidden, hidden, name)
            } else {
                let reason: String = try XCTUnwrap(expect["fallback"] as? String, name)
                XCTAssertEqual(answer, .fallback(try XCTUnwrap(PreviewedPageSource.Fallback(rawValue: reason), reason)), name)
            }
        }
    }

    func testTheWordsAreTheContracts() throws {
        let contract: [String: Any] = try ObsidianOpensThePreviewedPageTests.contract()
        let fallbacks: [String: String] = try XCTUnwrap(contract["fallbacks"] as? [String: String])
        var ours: Set<String> = []
        for reason in PreviewedPageSource.Fallback.allCases {
            ours.insert(reason.rawValue)
            XCTAssertEqual(PreviewedPageSource.why(reason), fallbacks[reason.rawValue], reason.rawValue)
        }
        XCTAssertEqual(ours, Set(fallbacks.keys), "the contract and the app name the same reasons")
        let trail: [String: String] = try XCTUnwrap(contract["trail"] as? [String: String])
        let page: URL = URL(fileURLWithPath: "/x/Unit 1/Lesson 3.md")
        XCTAssertEqual(
            PreviewedPageSource.trailWords(.page(page, place: "Unit 1/Lesson 3", hidden: false)),
            trail["opened"]?.replacingOccurrences(of: "{place}", with: "Unit 1/Lesson 3")
        )
        XCTAssertEqual(
            PreviewedPageSource.trailWords(.page(page, place: "Unit 1/Lesson 3", hidden: true)),
            trail["openedHidden"]?.replacingOccurrences(of: "{place}", with: "Unit 1/Lesson 3")
        )
        for reason in PreviewedPageSource.Fallback.allCases {
            XCTAssertEqual(
                PreviewedPageSource.trailWords(.fallback(reason)),
                trail["fellBack"]?.replacingOccurrences(of: "{why}", with: try XCTUnwrap(fallbacks[reason.rawValue])),
                reason.rawValue
            )
        }
    }

    func testEveryLinkCase() throws {
        let link: [String: Any] = try XCTUnwrap(try ObsidianOpensThePreviewedPageTests.contract()["link"] as? [String: Any])
        let cases: [[String: String]] = try XCTUnwrap(link["cases"] as? [[String: String]])
        XCTAssertFalse(cases.isEmpty)
        for testCase in cases {
            let path: String = try XCTUnwrap(testCase["path"])
            XCTAssertEqual(FolderActions.obsidianURL(forFolder: URL(fileURLWithPath: path))?.absoluteString, testCase["link"], path)
        }
    }

    /// The list is read from the section's built output, through the
    /// course's `.merged_output` link (`pageSourcesList.path`).
    func testTheListIsWhereTheBuildWritesIt() {
        let course: URL = URL(fileURLWithPath: "/w/courses/ICS3U")
        XCTAssertEqual(
            PreviewedPageSource.listURL(courseFolder: course, sectionNumber: 2).path,
            "/w/courses/ICS3U/.merged_output/section2/.page-sources.json"
        )
    }

    // MARK: - The route

    @MainActor
    final class Log {
        var openedFolders: [String] = []
        var openedPages: [String] = []
        var addressAsked: Int = 0
    }

    struct Driven {
        let workspace: WorkspaceModel
        let course: Course
        let settings: AppSettings
        let log: Log
    }

    /// The fixture workspace's first course, its section 1's list written
    /// where the build writes it, and every door to Obsidian faked; the
    /// preview shows `address` (nil: none showing).
    func drive(address: String?, answer: ObsidianFigureAddOnsAnswer = .no, figures: Bool = false,
               pages: [String: Any] = ["Unit-1/Lesson-3": ["source": "Unit 1/Lesson 3.md", "hidden": false]]) throws -> Driven {
        let fixtureURL: URL = try FixtureWorkspace.materialize()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fixtureURL)
        }
        let courses: [Course] = try WorkspaceModel.discoverCourses(in: fixtureURL.appendingPathComponent("courses"))
        let course: Course = try XCTUnwrap(courses.first)
        let page: URL = course.directoryURL.appendingPathComponent("Unit 1/Lesson 3.md")
        try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("A lesson.\n".utf8).write(to: page)
        if figures {
            try Data("```tikz\n\\begin{document}\n\\end{document}\n```\n".utf8).write(to: page)
        }
        let list: URL = PreviewedPageSource.listURL(courseFolder: course.directoryURL, sectionNumber: 1)
        try FileManager.default.createDirectory(at: list.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 1, "course": course.code, "section": 1, "pages": pages]).write(to: list)

        let previous: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail-\(UUID().uuidString)"))
        addTeardownBlock {
            ActivityTrail.store = previous
        }
        let settings: AppSettings = AppSettings(defaults: TestDefaults.make())
        settings.obsidianFigureAddOns = answer
        let log: Log = Log()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        var opening: ObsidianOpening = ObsidianOpening()
        opening.settings = settings
        opening.isInstalled = { return true }
        opening.isRunning = { return false }
        opening.registryData = { return nil }
        opening.open = { folder, _ in
            log.openedFolders.append(folder.path)
        }
        opening.openPage = { page, _ in
            log.openedPages.append(page.path)
        }
        opening.quitAndWait = {}
        opening.reopen = { _ in }
        opening.previewedAddress = { _, _, _ in
            log.addressAsked += 1
            return address
        }
        opening.carriedFolder = Bundle.main.resourceURL?.appendingPathComponent(ObsidianFigureAddOns.carriedFolderName)
        opening.defaultsFolder = Bundle.main.resourceURL?.appendingPathComponent("support/obsidian_defaults/.obsidian")
        workspace.obsidianOpening = opening
        return Driven(workspace: workspace, course: course, settings: settings, log: log)
    }

    func trail() -> String {
        return ActivityTrail.store.activityText(includingPrompts: false)
    }

    func testASectionPressOpensThePageOnScreenAndSaysSo() throws {
        let made: Driven = try drive(address: "Unit-1/Lesson-3")
        XCTAssertTrue(made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true))
        XCTAssertEqual(made.log.openedPages, [made.course.directoryURL.appendingPathComponent("Unit 1/Lesson 3.md").path])
        XCTAssertEqual(made.log.openedFolders, [], "the page, not the section")
        XCTAssertTrue(trail().contains("\(made.course.code)/1 · " + PreviewedPageSource.trailWords(
            .page(URL(fileURLWithPath: "/"), place: "Unit 1/Lesson 3", hidden: false))), trail())
    }

    /// Ruling 5: the press with no page showing opens the section as before,
    /// and the trail says why.
    func testASectionPressWithNoPageShowingOpensTheSectionAndSaysWhy() throws {
        let made: Driven = try drive(address: nil)
        XCTAssertTrue(made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true))
        XCTAssertEqual(made.log.openedPages, [])
        XCTAssertEqual(made.log.openedFolders, [made.course.sectionDirectoryURL(forSection: 1).path])
        XCTAssertTrue(trail().contains(PreviewedPageSource.trailWords(.fallback(.noPageShowing))), trail())
    }

    /// A page the list cannot place falls back to today's target too.
    func testAnAddressTheListCannotPlaceOpensTheSection() throws {
        let made: Driven = try drive(address: "My-Progress")
        made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true)
        XCTAssertEqual(made.log.openedFolders, [made.course.sectionDirectoryURL(forSection: 1).path])
        XCTAssertTrue(trail().contains(PreviewedPageSource.trailWords(.fallback(.notInTheList))), trail())
    }

    /// Ruling 3: a course's press opens what it always did, asks the preview
    /// nothing and writes no line.
    func testACoursePressOpensTheCourseAndWritesNothing() throws {
        let made: Driven = try drive(address: "Unit-1/Lesson-3")
        made.workspace.openInObsidian(course: made.course, sectionNumber: nil)
        made.workspace.openInObsidian(course: made.course, sectionNumber: 1)
        XCTAssertEqual(made.log.openedPages, [])
        XCTAssertEqual(made.log.openedFolders, [made.course.directoryURL.path, made.course.sectionDirectoryURL(forSection: 1).path])
        XCTAssertEqual(made.log.addressAsked, 0)
        XCTAssertFalse(trail().contains("in Obsidian, the page the preview shows"), trail())
        XCTAssertFalse(trail().contains("not a page of the preview"), trail())
    }

    /// The locked-pages note of a reference course carries the page, and it
    /// is the page that opens once the note is answered.
    func testTheLockedPagesNoteCarriesThePage() throws {
        LockedPagesNote.defaults = TestDefaults.make()
        defer { LockedPagesNote.defaults = PlantoirDefaults.shared }
        let made: Driven = try drive(address: "Unit-1/Lesson-3")
        made.course.configuration.keptForReference = true
        let opened: Bool = made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true) { _ in }
        XCTAssertFalse(opened)
        let request: LockedPagesNoteRequest = try XCTUnwrap(made.workspace.lockedPagesNoteRequest)
        let page: String = made.course.directoryURL.appendingPathComponent("Unit 1/Lesson 3.md").path
        XCTAssertEqual(request.page?.path, page)
        made.workspace.openInObsidianAfterTheNote(request)
        XCTAssertEqual(made.log.openedPages, [page])
        XCTAssertEqual(made.log.openedFolders, [])
    }

    /// A visible front page that only embeds a HIDDEN class opens the class,
    /// and the line says it is hidden — the flag of the file that opens.
    func testAFrontPageShowingAHiddenClassSaysTheClassIsHidden() throws {
        let made: Driven = try drive(address: "", pages: [
            "index": ["source": "section1/index.md", "hidden": false,
                      "shows": "Unit 1/Lesson 3.md", "showsHidden": true]
        ])
        made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true)
        XCTAssertEqual(made.log.openedPages, [made.course.directoryURL.appendingPathComponent("Unit 1/Lesson 3.md").path])
        XCTAssertTrue(trail().contains("\(made.course.code)/1 · " + PreviewedPageSource.trailWords(
            .page(URL(fileURLWithPath: "/"), place: "Unit 1/Lesson 3", hidden: true))), trail())
    }

    /// A second press while the add-ons scan of the first is still running
    /// does nothing, so it writes nothing: one press, one line.
    func testASecondPressDuringTheScanWritesNoSecondLine() async throws {
        let made: Driven = try drive(address: "Unit-1/Lesson-3", answer: .notAsked, figures: true)
        XCTAssertFalse(made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true))
        XCTAssertFalse(made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true))
        await made.workspace.obsidianAddOnsWork?.value
        let line: String = PreviewedPageSource.trailWords(
            .page(URL(fileURLWithPath: "/"), place: "Unit 1/Lesson 3", hidden: false))
        XCTAssertEqual(SaveEnablesTests.occurrences(of: line, in: trail()), 1, trail())
    }

    /// The add-ons offer carries the page through its answer.
    func testTheAddOnsOfferCarriesThePage() async throws {
        let made: Driven = try drive(address: "Unit-1/Lesson-3", answer: .notAsked, figures: true)
        XCTAssertFalse(made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true))
        await made.workspace.obsidianAddOnsWork?.value
        let request: ObsidianAddOnsRequest = try XCTUnwrap(made.workspace.obsidianAddOnsOfferRequest, "the offer is waiting")
        let page: String = made.course.directoryURL.appendingPathComponent("Unit 1/Lesson 3.md").path
        XCTAssertEqual(request.page?.path, page)
        await made.workspace.answerObsidianAddOnsOffer(request, .notNow)
        XCTAssertEqual(made.log.openedPages, [page])
        XCTAssertEqual(made.log.openedFolders, [])
    }

    // MARK: - The assistant's press (#610)

    /// The address is read ONCE, at the press, and the press reports the
    /// answer that opened — so the reply can never name a page other than
    /// the one Obsidian was handed, even when the preview moves on at once.
    func testTheAssistantsPressReadsThePageOnceAndReportsThePageThatOpened() async throws {
        let made: Driven = try drive(address: "Unit-1/Lesson-3", pages: [
            "Unit-1/Lesson-3": ["source": "Unit 1/Lesson 3.md", "hidden": false],
            "Unit-1/Lesson-4": ["source": "Unit 1/Lesson 4.md", "hidden": false],
        ])
        try Data("Another lesson.\n".utf8).write(to: made.course.directoryURL.appendingPathComponent("Unit 1/Lesson 4.md"))
        // The preview shows Lesson 3 at the first look and Lesson 4 at any
        // later one.
        let log: Log = made.log
        made.workspace.obsidianOpening.previewedAddress = { _, _, _ in
            log.addressAsked += 1
            if log.addressAsked == 1 {
                return "Unit-1/Lesson-3"
            }
            return "Unit-1/Lesson-4"
        }
        let press: OpenInObsidianPress = await made.workspace.openInObsidianAndWait(
            course: made.course, sectionNumber: 1
        ) { _ in }
        XCTAssertEqual(made.log.openedPages, [made.course.directoryURL.appendingPathComponent("Unit 1/Lesson 3.md").path])
        guard case .opened(let answer) = press, case .page(_, let place, _) = answer else {
            XCTFail("the press did not report a page: \(press)")
            return
        }
        XCTAssertEqual(place, "Unit 1/Lesson 3", "the page that opened, not the page on screen now")
        XCTAssertEqual(
            AssistToolRunner.sentence(for: press, course: made.course.code, section: "1"),
            AssistWording.openedThePageInObsidian(page: "Lesson 3")
        )
        XCTAssertEqual(made.log.addressAsked, 1, "one look at the window per press")
    }

    /// One press, one trail line — the route's, never a second from the
    /// assistant's side.
    func testTheAssistantsPressLeavesOneTrailLine() async throws {
        let made: Driven = try drive(address: "Unit-1/Lesson-3")
        _ = await made.workspace.openInObsidianAndWait(course: made.course, sectionNumber: 1) { _ in }
        let line: String = PreviewedPageSource.trailWords(
            .page(URL(fileURLWithPath: "/"), place: "Unit 1/Lesson 3", hidden: false))
        XCTAssertEqual(SaveEnablesTests.occurrences(of: line, in: trail()), 1, trail())
    }

    /// The add-ons offer put up by the press: nothing has opened yet.
    func testTheAssistantsPressReportsTheOfferWaiting() async throws {
        let made: Driven = try drive(address: "Unit-1/Lesson-3", answer: .notAsked, figures: true)
        let press: OpenInObsidianPress = await made.workspace.openInObsidianAndWait(
            course: made.course, sectionNumber: 1
        ) { _ in }
        XCTAssertEqual(press, .waitingForAnAnswer)
        XCTAssertNotNil(made.workspace.obsidianAddOnsOfferRequest)
        XCTAssertEqual(made.log.openedPages, [])
        XCTAssertEqual(made.log.openedFolders, [])
    }

    /// A course kept for reference asks for the locked-pages note first, as
    /// the button does.
    func testTheAssistantsPressOnAReferenceCourseAsksForTheNoteFirst() async throws {
        LockedPagesNote.defaults = TestDefaults.make()
        defer { LockedPagesNote.defaults = PlantoirDefaults.shared }
        let made: Driven = try drive(address: "Unit-1/Lesson-3")
        made.course.configuration.keptForReference = true
        let press: OpenInObsidianPress = await made.workspace.openInObsidianAndWait(
            course: made.course, sectionNumber: 1
        ) { _ in }
        XCTAssertEqual(press, .waitingForAnAnswer)
        XCTAssertNotNil(made.workspace.lockedPagesNoteRequest)
        XCTAssertEqual(made.log.openedPages, [])
    }

    /// A press while an earlier one's scan runs does nothing, and says so.
    func testASecondAssistantPressDuringTheScanSaysItIsAlreadyOpening() async throws {
        let made: Driven = try drive(address: "Unit-1/Lesson-3", answer: .notAsked, figures: true)
        XCTAssertFalse(made.workspace.openInObsidian(course: made.course, sectionNumber: 1, atThePreviewedPage: true))
        let press: OpenInObsidianPress = await made.workspace.openInObsidianAndWait(
            course: made.course, sectionNumber: 1
        ) { _ in }
        XCTAssertEqual(press, .alreadyOpening)
        await made.workspace.obsidianAddOnsWork?.value
    }

    // MARK: - The wiring

    func testTheSectionPressesAskForThePageAndTheCoursePressDoesNot() throws {
        let views: URL = TextFieldStyleScanTests.viewsURL()
        let detail: String = try String(contentsOf: views.appendingPathComponent("Section/SectionDetailView.swift"), encoding: .utf8)
        XCTAssertTrue(detail.contains("workspace.openInObsidian(course: course, sectionNumber: sectionNumber, atThePreviewedPage: true)"),
                      "the section window's toolbar button")
        XCTAssertTrue(detail.contains("previewedPage: { previewedPagePath() }"), "the window says which page it shows")
        XCTAssertTrue(detail.contains("await workspace.openInObsidianAndWait(course: course, sectionNumber: sectionNumber)"),
                      "the assistant presses the window's own Open in Obsidian, on the window's model (#610)")
        XCTAssertTrue(detail.contains("PreviewStartPage.rememberedPath(page: previewController.webView.url, previewRoot: previewRoot)"),
                      "the page ON SCREEN, not the page last viewed")
        let sidebar: String = try String(contentsOf: views.appendingPathComponent("SidebarView.swift"), encoding: .utf8)
        let sectionItem: Range<String.Index> = try XCTUnwrap(sidebar.range(of: "case .sectionOpenInObsidian:"))
        let courseItem: Range<String.Index> = try XCTUnwrap(sidebar.range(of: "case .courseOpenInObsidian:"))
        let afterSection: Substring = sidebar[sectionItem.upperBound...].prefix(400)
        let afterCourse: Substring = sidebar[courseItem.upperBound...].prefix(200)
        XCTAssertTrue(afterSection.contains("atThePreviewedPage: true"), "Section ▸ Open in Obsidian")
        XCTAssertFalse(afterCourse.contains("atThePreviewedPage"), "Course ▸ Open in Obsidian keeps opening the course (ruling 3)")
        XCTAssertEqual(SaveEnablesTests.occurrences(of: "atThePreviewedPage: sectionNumber != nil", in: sidebar), 2,
                       "a section row's menu, for a course taught and a course kept for reference")
    }
}
