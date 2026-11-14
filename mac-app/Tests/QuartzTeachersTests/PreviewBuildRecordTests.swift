import XCTest
@testable import QuartzTeachers

/// The record ⌘Q reads of a preview being built, kept per start (#812):
/// `contracts/shared-rules.json` → `quittingWhileWorkIsUnderWay.previewBuildRecord`,
/// walked through the real `PreviewBuildWait`, `CourseActivity`,
/// `PreviewLeases` and `PreviewStartRecords`, the steps
/// `SectionDetailView.startPreview` takes, in its order.
///
/// Resets `CourseActivity` and `PreviewLeases` around every method, the
/// pattern `CourseActivityPublishOnlyTests` and `PreviewLeaseTests` follow;
/// the scheme runs test classes one at a time, which is what makes that safe.
@MainActor
final class PreviewBuildRecordTests: XCTestCase {

    // MARK: - Types

    /// One section window, as far as its record and lease go.
    @MainActor
    final class Window {

        // MARK: - Stored properties

        let wait: PreviewBuildWait = PreviewBuildWait()
        var lease: PreviewLeases.Lease?
    }

    /// What a run of steps counted.
    struct Counted {
        var refusals: Int = 0
        var alreadyStarting: Int = 0
    }

    // MARK: - Stored properties

    static let folder: String = "/tmp/plantoir-preview-build-record"
    static let courseCode: String = "ICS3U"
    static let section: Int = 1

    // MARK: - Functions

    override func setUp() {
        super.setUp()
        CourseActivity.reset()
        PreviewLeases.reset()
    }

    override func tearDown() {
        CourseActivity.reset()
        PreviewLeases.reset()
        super.tearDown()
    }

    /// Every `pressCases` case.
    func testEveryPressCase() throws {
        let block: [String: Any] = try PreviewBuildRecordTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["pressCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 11, "the contract's press cases were not found")
        for entry in cases {
            CourseActivity.reset()
            PreviewLeases.reset()
            let name: String = try XCTUnwrap(entry["name"] as? String)
            let steps: [String] = try XCTUnwrap(entry["steps"] as? [String], name)
            let expect: [String: Any] = try XCTUnwrap(entry["expect"] as? [String: Any], name)
            let windowA: Window = Window()
            let windowB: Window = Window()
            var assistantClaim: CourseActivity.PreviewBuildClaim? = nil
            var counted: Counted = Counted()
            for step in steps {
                switch step {
                case "A.start":
                    PreviewBuildRecordTests.start(windowA, counted: &counted)
                case "B.start":
                    PreviewBuildRecordTests.start(windowB, counted: &counted)
                case "A.runEnds":
                    PreviewBuildRecordTests.runEnds(windowA)
                case "B.runEnds":
                    PreviewBuildRecordTests.runEnds(windowB)
                case "A.couldNotStart":
                    PreviewBuildRecordTests.couldNotStart(windowA, counted: &counted)
                case "assistant.begins":
                    assistantClaim = CourseActivity.beginPreviewBuildClaim(
                        folderPath: PreviewBuildRecordTests.folder,
                        courseCode: PreviewBuildRecordTests.courseCode,
                        sectionNumber: PreviewBuildRecordTests.section
                    )
                case "assistant.ends":
                    if let claim = assistantClaim {
                        CourseActivity.endPreviewBuild(claim)
                    }
                    assistantClaim = nil
                default:
                    XCTFail("\(name): no step \(step)")
                }
            }
            XCTAssertEqual(CourseActivity.activePreviewBuilds.count, expect["records"] as? Int, "\(name): records")
            XCTAssertEqual(counted.refusals, expect["refusals"] as? Int, "\(name): refusals")
            XCTAssertEqual(counted.alreadyStarting, expect["alreadyStarting"] as? Int, "\(name): alreadyStarting")
            XCTAssertEqual(windowA.wait.isWaiting, expect["aIsWaiting"] as? Bool, "\(name): aIsWaiting")
            let quitAsks: Bool = QuitConfirmation.workUnderWay() != nil
            XCTAssertEqual(quitAsks, (expect["records"] as? Int ?? 0) > 0, "\(name): what a quit would ask")
        }
    }

    /// A claim ended twice, or one never held, changes nothing; ending the
    /// section as a whole ends every claim on it.
    func testClaimsEndOnlyThemselves() {
        let first: CourseActivity.PreviewBuildClaim = CourseActivity.beginPreviewBuildClaim(
            folderPath: "/f", courseCode: "ICS3U", sectionNumber: 1
        )
        let second: CourseActivity.PreviewBuildClaim = CourseActivity.beginPreviewBuildClaim(
            folderPath: "/f", courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertEqual(CourseActivity.activePreviewBuilds.count, 1, "one section is one fact to a quit")
        CourseActivity.endPreviewBuild(first)
        CourseActivity.endPreviewBuild(first)
        XCTAssertEqual(
            CourseActivity.activePreviewBuilds,
            [CourseActivity.PreviewBuildRecord(folderPath: "/f", courseCode: "ICS3U", sectionNumber: 1)],
            "the second claim still holds the record"
        )
        CourseActivity.endPreviewBuild(second)
        XCTAssertTrue(CourseActivity.activePreviewBuilds.isEmpty)

        _ = CourseActivity.beginPreviewBuildClaim(folderPath: "/f", courseCode: "ICS3U", sectionNumber: 1)
        _ = CourseActivity.beginPreviewBuildClaim(folderPath: "/f", courseCode: "ICS3U", sectionNumber: 1)
        CourseActivity.endPreviewBuild(folderPath: "/f", courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertTrue(CourseActivity.activePreviewBuilds.isEmpty)
    }

    /// The view takes these steps, in this order: the question about a start
    /// already under way FIRST, before anything is written, and the record
    /// and lease only through `PreviewStartRecords.begin`.
    func testStartPreviewAsksFirstAndRecordsThroughTheModel() throws {
        let source: String = try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"
        )
        let body: String = try DeployAsksAboutLaterClassesTests.body(
            of: "    func startPreview(at request: PreviewStartPage.Request = .frontPage) {", in: source
        )
        let asked: Range<String.Index> = try XCTUnwrap(
            body.range(of: "PreviewStartRecords.aStartIsUnderWay(wait: previewBuildWait, heldLease: previewLease)"),
            "startPreview no longer asks whether its own start is under way"
        )
        let copied: Range<String.Index> = try XCTUnwrap(body.range(of: "workspace.isBeingCopied(course.code)"))
        let begun: Range<String.Index> = try XCTUnwrap(
            body.range(of: "PreviewStartRecords.begin("),
            "startPreview no longer records through PreviewStartRecords.begin"
        )
        XCTAssertLessThan(asked.lowerBound, copied.lowerBound, "asked before anything else")
        XCTAssertLessThan(asked.lowerBound, begun.lowerBound)
        XCTAssertFalse(body.contains("previewBuildWait.begin("), "a second way to write the record")
        XCTAssertFalse(body.contains("PreviewLeases.lease("), "a second way to take the lease")
        XCTAssertTrue(body.contains(".previewAlreadyStarting"), "the trail line for a start that did nothing")

        let assistant: String = try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Models/Assist/AssistSiteWork.swift"
        )
        XCTAssertTrue(assistant.contains("CourseActivity.beginPreviewBuildClaim("), "the assistant's rebuild holds its own claim")
        XCTAssertFalse(assistant.contains("CourseActivity.endPreviewBuild(\n"), "nor ends the section's record as a whole")
        XCTAssertFalse(assistant.contains("CourseActivity.beginPreviewBuild("), "nor records with a claim nobody keeps")
    }

    /// The wait's first phase asks the model where the run stands, and a
    /// start parked while old stops finish asks the model whether it still
    /// belongs, so neither rule can go back to a check written in the view
    /// alone (#812's review).
    func testTheWaitAndTheParkedStartAskTheModel() throws {
        let source: String = try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"
        )
        let wait: String = try DeployAsksAboutLaterClassesTests.body(
            of: "    func waitForPreviewServer(port: Int, siteAsItWas: Date?, startRequest: PreviewStartPage.Request = .frontPage) async {",
            in: source
        )
        let firstPhase: Range<String.Index> = try XCTUnwrap(wait.range(of: "// Phase 1:"))
        let secondPhase: Range<String.Index> = try XCTUnwrap(wait.range(of: "// Phase 2:"))
        let phaseOne: Substring = wait[firstPhase.upperBound..<secondPhase.lowerBound]
        XCTAssertTrue(phaseOne.contains("PreviewStartRecords.howTheRunStands("), "phase 1 asks where the run stands")
        XCTAssertTrue(phaseOne.contains("case .couldNotStart(let problem) = standing"), "a run that never started ends the wait")
        XCTAssertTrue(phaseOne.contains(".previewCouldNotStart"), "and leaves its trail line")
        XCTAssertTrue(phaseOne.contains("showPreviewRefusal(title: \"Cannot Preview Yet\", sentence: problem)"), "and says why")
        let start: String = try DeployAsksAboutLaterClassesTests.body(
            of: "    func startPreview(at request: PreviewStartPage.Request = .frontPage) {", in: source
        )
        let parked: Range<String.Index> = try XCTUnwrap(start.range(of: "await PreviewStopper.waitForStopsToFinish("))
        let belongs: Range<String.Index> = try XCTUnwrap(
            start.range(of: "PreviewStartRecords.theStartStillBelongs("),
            "the parked start no longer asks whether it still belongs"
        )
        let launched: Range<String.Index> = try XCTUnwrap(start.range(of: "previewRunner.run("))
        XCTAssertLessThan(parked.lowerBound, belongs.lowerBound)
        XCTAssertLessThan(belongs.lowerBound, launched.lowerBound, "asked before the launcher runs")
        XCTAssertTrue(start.contains("appIsQuitting: WorkspaceModel.isTerminating"), "a quit that went ahead starts nothing")
    }

    /// Where a run stands: a run that never started is an ending, and the
    /// runner's launch problem is asked before an exit code an earlier run
    /// left behind.
    func testHowTheRunStands() {
        XCTAssertEqual(
            PreviewStartRecords.howTheRunStands(isRunning: true, lastExitCode: nil, launchProblem: nil), .underWay
        )
        XCTAssertEqual(
            PreviewStartRecords.howTheRunStands(isRunning: false, lastExitCode: nil, launchProblem: nil), .underWay
        )
        XCTAssertEqual(
            PreviewStartRecords.howTheRunStands(isRunning: false, lastExitCode: 1, launchProblem: nil), .ended
        )
        XCTAssertEqual(
            PreviewStartRecords.howTheRunStands(isRunning: false, lastExitCode: nil, launchProblem: "why"),
            .couldNotStart("why")
        )
        XCTAssertEqual(
            PreviewStartRecords.howTheRunStands(isRunning: false, lastExitCode: 0, launchProblem: "why"),
            .couldNotStart("why")
        )
    }

    /// A parked start runs only while it is still the window's latest and
    /// the quit has not gone ahead. Two starts can hold leases equal in
    /// every field, which is how both used to reach the launcher.
    func testAParkedStartRunsOnlyWhileItStillBelongs() {
        let lease: PreviewLeases.Lease = PreviewLeases.Lease(
            port: 8081, folderPath: "/f", courseCode: "ICS3U", sectionNumber: 1
        )
        let equalLease: PreviewLeases.Lease = PreviewLeases.Lease(
            port: 8081, folderPath: "/f", courseCode: "ICS3U", sectionNumber: 1
        )
        let first: UUID = UUID()
        let later: UUID = UUID()
        XCTAssertTrue(PreviewStartRecords.theStartStillBelongs(
            heldLease: lease, lease: lease, heldStart: first, start: first, appIsQuitting: false
        ))
        XCTAssertFalse(PreviewStartRecords.theStartStillBelongs(
            heldLease: nil, lease: lease, heldStart: first, start: first, appIsQuitting: false
        ), "stopped, or the view went away")
        XCTAssertFalse(PreviewStartRecords.theStartStillBelongs(
            heldLease: equalLease, lease: lease, heldStart: later, start: first, appIsQuitting: false
        ), "a later start holds an equal lease")
        XCTAssertTrue(PreviewStartRecords.theStartStillBelongs(
            heldLease: equalLease, lease: lease, heldStart: later, start: later, appIsQuitting: false
        ), "the later start itself runs")
        XCTAssertFalse(PreviewStartRecords.theStartStillBelongs(
            heldLease: lease, lease: lease, heldStart: first, start: first, appIsQuitting: true
        ), "the quit went ahead")
    }

    /// A press replaced by a later press of the same page says so, even
    /// when the later press finished first (#812's review).
    func testAReplacedPressSaysItWasReplaced() async {
        let store: PreviewAgainPresses = PreviewAgainPresses()
        let owner: UUID = UUID()
        let first: UUID = store.press(owner: owner)
        var startsAsked: Int = 0
        let firstEnding: PreviewAgainPresses.Ending = await PreviewAgainPresses.carryOut(
            store: store,
            owner: owner,
            token: first,
            courseCode: PreviewBuildRecordTests.courseCode,
            sectionNumber: PreviewBuildRecordTests.section,
            previewIsRunning: true,
            stop: {
                let second: UUID = store.press(owner: owner)
                let secondEnding: PreviewAgainPresses.Ending = await PreviewAgainPresses.carryOut(
                    store: store,
                    owner: owner,
                    token: second,
                    courseCode: PreviewBuildRecordTests.courseCode,
                    sectionNumber: PreviewBuildRecordTests.section,
                    previewIsRunning: false,
                    stop: {},
                    start: {
                        startsAsked += 1
                    }
                )
                XCTAssertEqual(secondEnding, .started)
                store.finish(second, owner: owner)
            },
            start: {
                startsAsked += 1
            }
        )
        store.finish(first, owner: owner)
        XCTAssertEqual(firstEnding, .replaced, "the later press took its place; the page did not go")
        XCTAssertEqual(startsAsked, 1)
        XCTAssertTrue(store.replaced.isEmpty, "nothing is kept once both presses are over")

        let leaving: UUID = store.press(owner: owner)
        let leftEnding: PreviewAgainPresses.Ending = await PreviewAgainPresses.carryOut(
            store: store,
            owner: owner,
            token: leaving,
            courseCode: PreviewBuildRecordTests.courseCode,
            sectionNumber: PreviewBuildRecordTests.section,
            previewIsRunning: true,
            stop: {
                store.abandon(owner: owner)
            },
            start: {
                startsAsked += 1
            }
        )
        store.finish(leaving, owner: owner)
        XCTAssertEqual(leftEnding, .abandoned)
    }

    /// Every `previewAgainCases` case (#813): a repair's Preview Again with
    /// each event arriving inside the stop, through the real
    /// `PreviewAgainPresses.carryOut` and the press steps above.
    func testEveryPreviewAgainCase() async throws {
        let block: [String: Any] = try PreviewBuildRecordTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["previewAgainCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10, "the contract's Preview Again cases were not found")
        for entry in cases {
            CourseActivity.reset()
            PreviewLeases.reset()
            let name: String = try XCTUnwrap(entry["name"] as? String)
            let previewRunning: Bool = try XCTUnwrap(entry["previewRunning"] as? Bool, name)
            let duringTheStop: [String] = try XCTUnwrap(entry["duringTheStop"] as? [String], name)
            let expect: [String: Any] = try XCTUnwrap(entry["expect"] as? [String: Any], name)
            let store: PreviewAgainPresses = PreviewAgainPresses()
            let page: Window = Window()
            let owner: UUID = UUID()
            let otherPage: UUID = UUID()
            _ = store.press(owner: otherPage)
            var counted: Counted = Counted()
            var stops: Int = 0
            var startsAsked: Int = 0
            if previewRunning {
                // A preview showing: the lease held and the wait over.
                PreviewBuildRecordTests.start(page, counted: &counted)
                page.wait.end()
            }
            let token: UUID = store.press(owner: owner)
            _ = await PreviewAgainPresses.carryOut(
                store: store,
                owner: owner,
                token: token,
                courseCode: PreviewBuildRecordTests.courseCode,
                sectionNumber: PreviewBuildRecordTests.section,
                previewIsRunning: previewRunning,
                stop: {
                    stops += 1
                    PreviewBuildRecordTests.runEnds(page)
                    for event in duringTheStop {
                        switch event {
                        case "oldRunEnds":
                            page.wait.end()
                        case "anotherWindowLeaves":
                            store.abandon(owner: otherPage)
                        case "leave":
                            store.abandon(owner: owner)
                            PreviewBuildRecordTests.runEnds(page)
                        case "quit":
                            store.abandonEvery()
                            PreviewBuildRecordTests.runEnds(page)
                        case "pressAgain":
                            let second: UUID = store.press(owner: owner)
                            _ = await PreviewAgainPresses.carryOut(
                                store: store,
                                owner: owner,
                                token: second,
                                courseCode: PreviewBuildRecordTests.courseCode,
                                sectionNumber: PreviewBuildRecordTests.section,
                                previewIsRunning: false,
                                stop: {
                                    XCTFail("\(name): the second press had nothing to stop")
                                },
                                start: {
                                    startsAsked += 1
                                    PreviewBuildRecordTests.start(page, counted: &counted)
                                }
                            )
                            store.finish(second, owner: owner)
                        case "teacherStartsAPreview":
                            PreviewBuildRecordTests.start(page, counted: &counted)
                        default:
                            XCTFail("\(name): no event \(event)")
                        }
                    }
                },
                start: {
                    startsAsked += 1
                    PreviewBuildRecordTests.start(page, counted: &counted)
                }
            )
            store.finish(token, owner: owner)
            XCTAssertEqual(stops, expect["stops"] as? Int, "\(name): stops")
            XCTAssertEqual(startsAsked, expect["startsAsked"] as? Int, "\(name): startsAsked")
            XCTAssertEqual(CourseActivity.activePreviewBuilds.count, expect["records"] as? Int, "\(name): records")
            XCTAssertEqual(counted.alreadyStarting, expect["alreadyStarting"] as? Int, "\(name): alreadyStarting")
            XCTAssertEqual(counted.refusals, 0, "\(name): nothing is refused")
            XCTAssertNil(store.underWay[owner], "\(name): the press is over")
        }
    }

    /// The view records the press before anything is awaited, carries it
    /// out through the model, and abandons it when the page goes; the quit
    /// abandons every press.
    func testTheRepairPressIsRecordedAndAbandoned() throws {
        let source: String = try DeployAsksAboutLaterClassesTests.source(
            "mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"
        )
        let body: String = try DeployAsksAboutLaterClassesTests.body(of: "    func rebuildAfterRepair() {", in: source)
        let pressed: Range<String.Index> = try XCTUnwrap(
            body.range(of: "PreviewAgainPresses.shared.press(owner: owner)"),
            "the press is no longer recorded"
        )
        let task: Range<String.Index> = try XCTUnwrap(body.range(of: "Task { @MainActor in"))
        XCTAssertLessThan(pressed.lowerBound, task.lowerBound, "recorded before anything is awaited")
        XCTAssertTrue(body.contains("PreviewAgainPresses.carryOut("), "carried out through the model")
        XCTAssertFalse(body.contains("await stopPreviewAndWait()\n            }\n            startPreview()"), "the old unconditional start")
        let disappear: Range<String.Index> = try XCTUnwrap(source.range(of: ".onDisappear {"))
        let afterDisappear: Substring = source[disappear.upperBound...].prefix(600)
        XCTAssertTrue(
            afterDisappear.contains("PreviewAgainPresses.shared.abandon(owner: previewAgainOwner)"),
            "leaving the page abandons its press"
        )
        let delegate: String = try DeployAsksAboutLaterClassesTests.source("mac-app/QuartzTeachers/App/AppDelegate.swift")
        XCTAssertTrue(delegate.contains("PreviewAgainPresses.shared.abandonEvery()"), "quitting abandons every press")
    }

    // MARK: - Helpers

    /// `startPreview`'s record-keeping steps, in its order.
    static func start(_ window: Window, counted: inout Counted) {
        if PreviewStartRecords.aStartIsUnderWay(wait: window.wait, heldLease: window.lease) {
            counted.alreadyStarting += 1
            return
        }
        switch PreviewStartRecords.begin(
            wait: window.wait,
            folderPath: PreviewBuildRecordTests.folder,
            courseCode: PreviewBuildRecordTests.courseCode,
            sectionNumber: PreviewBuildRecordTests.section
        ) {
        case .began(let lease):
            window.lease = lease
        case .refused:
            counted.refusals += 1
        }
    }

    /// A run that returned without starting, as `waitForPreviewServer`'s
    /// first phase meets it: the model says where it stands, and a run that
    /// never started ends the start and shows a refusal.
    static func couldNotStart(_ window: Window, counted: inout Counted) {
        let standing: PreviewStartRecords.RunStanding = PreviewStartRecords.howTheRunStands(
            isRunning: false, lastExitCode: nil, launchProblem: "a launch problem invented for this test"
        )
        switch standing {
        case .couldNotStart:
            PreviewBuildRecordTests.runEnds(window)
            counted.refusals += 1
        case .ended:
            PreviewBuildRecordTests.runEnds(window)
        case .underWay:
            break
        }
    }

    /// A start ending however it ends: `stopPreview`'s two record steps.
    static func runEnds(_ window: Window) {
        window.wait.end()
        if let lease = window.lease {
            PreviewLeases.release(lease)
            window.lease = nil
        }
    }

    static func block() throws -> [String: Any] {
        let quit: [String: Any] = try SharedRulesContractTests.section("quittingWhileWorkIsUnderWay")
        return try XCTUnwrap(quit["previewBuildRecord"] as? [String: Any], "no previewBuildRecord in quittingWhileWorkIsUnderWay")
    }
}
