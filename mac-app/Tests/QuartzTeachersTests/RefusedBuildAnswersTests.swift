import XCTest
@testable import QuartzTeachers

/// An outside assistant's `rebuild_preview`, `publish_pages` and
/// `unpublish_pages` rebuild the preview with the launcher's build leg, and
/// since #439 that leg refuses while the same section is still being
/// deployed. Their answers say the launcher's own line — the sentence a
/// teacher can act on — rather than "did not finish building" and a pointer
/// at a window this path has not got (GitHub #471). Runs
/// `shared-rules.json` → `deployWhileItsSectionDeploys.refusedBuildAnswers`
/// case for case through the real `AssistToolRunner`; nothing is retyped.
///
/// The fixture's stub hands the contract's raw output — the cross as it
/// arrived — to `AssistSiteWorkResult.previewDidNotBuild(course:section:output:)`,
/// which is exactly what the real headless path feeds its runner's text to.
@MainActor
final class RefusedBuildAnswersTests: XCTestCase {

    // MARK: - Stored properties

    private var root: URL?

    private var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Set up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousTrail
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    // MARK: - Helpers

    private func rule() throws -> [String: Any] {
        return try WorkLeaseLivenessTests.sharedRules(["deployWhileItsSectionDeploys"])
    }

    /// The contract's working folder: ICS4U with a section 2 holding
    /// "Unit 2, Day 3", published or not as the tool needs it.
    private func makeFolder(pagePublished: Bool) throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(alsoCourse: "ICS4U", surface: .mcp)
        root = made.root
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        let courseURL: URL = made.root.appendingPathComponent("courses").appendingPathComponent("ICS4U")
        let pageURL: URL = courseURL.appendingPathComponent("section2/All Classes/Unit 2, Day 3.md")
        let text: String = """
        ---
        title: Unit 2, Day 3
        publish: \(pagePublished ? "true" : "false")
        created: 2026-09-10T07:00:00.000-0400
        ---

        Three.
        """
        try text.write(to: pageURL, atomically: true, encoding: .utf8)
        return made
    }

    /// Every case, the single-page unpublish included: the mac rebuilds
    /// after hiding one page, which Windows holds open under #479.
    private func casesForTheMac() throws -> [[String: Any]] {
        return try XCTUnwrap(try rule()["refusedBuildAnswers"] as? [[String: Any]])
    }

    // MARK: - Tests

    /// The three tools and both cross forms are among the cases, so a
    /// trimmed contract cannot pass by covering less.
    func testEveryPathAndEveryCrossFormIsCovered() throws {
        let cases: [[String: Any]] = try casesForTheMac()
        var tools: Set<String> = []
        var crossForms: Set<String> = []
        var singlePageUnpublish: Bool = false
        for testCase in cases {
            tools.insert(try XCTUnwrap(testCase["tool"] as? String))
            if let cross = testCase["crossArrivesAs"] as? String {
                crossForms.insert(cross)
            }
            if testCase["tool"] as? String == "unpublish_pages",
               let arguments = testCase["arguments"] as? [String: Any],
               arguments["pages"] as? String == "Unit 2, Day 3" {
                singlePageUnpublish = true
            }
        }
        XCTAssertEqual(tools, ["rebuild_preview", "publish_pages", "unpublish_pages"])
        XCTAssertTrue(crossForms.contains("?"))
        XCTAssertTrue(crossForms.contains(where: { form in form.count > 1 }), "a mojibake form")
        XCTAssertTrue(singlePageUnpublish, "The mac rebuilds after hiding one page, so the contract has that case for it.")
    }

    /// Each case, through the real runner: the answer says the lifted line
    /// whole, never the cross as it arrived, and never points at a window.
    func testEachCaseSaysTheLaunchersOwnLine() async throws {
        let launcherCases: [[String: Any]] = try XCTUnwrap(try rule()["failureExplanationCases"] as? [[String: Any]])
        for testCase in try casesForTheMac() {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let tool: String = try XCTUnwrap(testCase["tool"] as? String)
            let index: Int = try XCTUnwrap(testCase["failureExplanationCase"] as? Int)
            let launcherCase: [String: Any] = launcherCases[index]
            let lifted: String = try XCTUnwrap(launcherCase["expect"] as? String)
            let cross: String = testCase["crossArrivesAs"] as? String ?? "❌"
            let output: String = try XCTUnwrap(launcherCase["output"] as? String)
                .replacingOccurrences(of: "❌", with: cross)

            let made: AssistFixture.Made = try makeFolder(pagePublished: tool == "unpublish_pages")
            made.siteWork.rebuildFailsWithOutput = output

            var arguments: [String: Any] = ["course": "ICS4U", "section": 2]
            if let given = testCase["arguments"] as? [String: Any], let pages = given["pages"] as? String {
                var titles: [String] = []
                for piece in pages.split(separator: ";") {
                    titles.append(piece.trimmingCharacters(in: .whitespaces))
                }
                arguments["pages"] = titles
            }
            let outcome: AssistToolOutcome = await AssistFixture.run(tool, with: arguments, on: made.runner)

            XCTAssertEqual(made.siteWork.previewRebuilds, 1, "\(name): the preview was never rebuilt, so nothing was refused. The answer was: \(outcome.detail)")
            XCTAssertTrue(outcome.detail.contains(lifted), "\(name): \(outcome.detail)")
            XCTAssertFalse(outcome.detail.contains(cross + " ICS4U"), "\(name): the cross as it arrived: \(outcome.detail)")
            XCTAssertFalse(outcome.detail.contains("❌"), "\(name): \(outcome.detail)")
            XCTAssertFalse(outcome.detail.contains(AssistWording.whereTheOutputIs), "\(name): \(outcome.detail)")
            if tool != "rebuild_preview" {
                // What was already done is said FIRST, then the refusal.
                let doneAt: String.Index = try XCTUnwrap(outcome.detail.range(of: "Done: ")?.lowerBound
                    ?? outcome.detail.range(of: " was published.")?.lowerBound
                    ?? outcome.detail.range(of: " was unpublished.")?.lowerBound, "\(name): \(outcome.detail)")
                let refusalAt: String.Index = try XCTUnwrap(outcome.detail.range(of: lifted)?.lowerBound)
                XCTAssertLessThan(doneAt, refusalAt, "\(name): \(outcome.detail)")
            }
            try? FileManager.default.removeItem(at: made.root)
            root = nil
        }
    }

    /// The lift takes off whatever arrived in front of the course code: the
    /// cross, a `?`, or three characters of mojibake.
    func testTheLiftTakesOffEveryFormOfTheCross() {
        let sentence: String = "ICS4U section 2 is already being deployed, so it cannot be built until that has finished."
        // The mojibake is the contract's own form (`crossArrivesAs`, read
        // on a Western code page), not retyped.
        for front in ["❌ ", "? ", "â\u{009D}Œ ", "   ❌   ", ""] {
            let refusal: FailureExplainer.SectionDeployRefusal? = FailureExplainer.sectionDeployRefusal(
                in: front + sentence + "\n   Nothing was changed."
            )
            XCTAssertEqual(refusal?.sentence, sentence, "in front: \(front.debugDescription)")
        }
    }

    /// An ordinary build failure on the headless path is not the refusal, and
    /// still does not point at a window.
    func testAnOrdinaryFailureSendsTheTeacherToTheWindow() {
        let result: AssistSiteWorkResult = AssistSiteWorkResult.previewDidNotBuild(
            course: "ICS4U", section: "2", output: "npm ERR! something broke\n"
        )
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(
            result.message, AssistWording.previewDidNotBuildForACallerWithNoWindow(course: "ICS4U", section: "2")
        )
        XCTAssertFalse(result.message.contains(AssistWording.whereTheOutputIs))
    }
}
