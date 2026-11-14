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
        XCTAssertGreaterThanOrEqual(cases.count, 9, "the contract's press cases were not found")
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
