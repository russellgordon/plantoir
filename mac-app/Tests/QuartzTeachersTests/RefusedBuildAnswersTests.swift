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

/// #522: a publish or a hide of named pages ends by saying it changed the
/// teacher's files — and "their PREVIEW" ONLY when the preview was restarted
/// in its window (`previewIsRebuilding`). Every other note the rebuild can
/// leave means the preview did not change: a headless rebuild that stopped at
/// a question (exit 3), a site rebuilt with no window to show it, a rebuild
/// declined because a copy of the course is being zipped or the section is
/// being deployed. The sentences are named (`AssistToolRunner.changedTheirFiles`
/// / `changedTheirFilesAndPreview`), never retyped.
@MainActor
final class PreviewClaimAfterAChangeTests: XCTestCase {

    // MARK: - Stored properties

    private var root: URL?

    // MARK: - Set up

    override func tearDown() async throws {
        CourseActivity.reset()
        FakePreview.shared.forget()
        SectionWindowControllers.shared.forgetAll()
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    // MARK: - Helpers

    private func makeCourse(surface: AssistToolRunner.Surface, registeringPreview: Bool = false) throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(
            registeringPreview: registeringPreview, surface: surface
        )
        root = made.root
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        return made
    }

    /// The detail's last paragraph: how the change ends.
    private func ending(of outcome: AssistToolOutcome) -> String {
        let paragraphs: [String] = outcome.detail.components(separatedBy: "\n\n")
        return paragraphs.last ?? ""
    }

    // MARK: - Tests

    /// The issue as it was: a page publish, and a hide, whose headless rebuild
    /// stopped at a question. MUST FAIL on the old `previewLeftAsItWas`, which
    /// did not count `previewBuildNeedsAnAnswer` and claimed the preview.
    func testARebuildThatStoppedAtAQuestionClaimsNoPreview() async throws {
        for surface in [AssistToolRunner.Surface.mcp, AssistToolRunner.Surface.local] {
            let made: AssistFixture.Made = try makeCourse(surface: surface)
            made.siteWork.rebuildMeetsAQuestion = true
            let question: String = AssistWording.previewBuildNeedsAnAnswer(course: "ICS3U", section: "1")

            let published: AssistToolOutcome = await AssistFixture.run(
                "publish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner
            )
            XCTAssertTrue(published.detail.contains("\n\n" + question + "\n\n"), "\(surface): \(published.detail)")
            XCTAssertEqual(ending(of: published), AssistToolRunner.changedTheirFiles, "\(surface)")

            let hidden: AssistToolOutcome = await AssistFixture.run(
                "unpublish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner
            )
            XCTAssertTrue(hidden.detail.contains("\n\n" + question + "\n\n"), "\(surface): \(hidden.detail)")
            XCTAssertEqual(ending(of: hidden), AssistToolRunner.changedTheirFiles, "\(surface)")
            XCTAssertEqual(made.siteWork.previewRebuilds, 2, "\(surface): both changes reached the rebuild")
            try? FileManager.default.removeItem(at: made.root)
        }
    }

    /// The site rebuilt with no window to show it: no preview exists, so none
    /// changed (`builtWithNoWindowOpen` says so). MUST FAIL on the old rule.
    func testASiteRebuiltWithNoWindowClaimsNoPreview() async throws {
        let made: AssistFixture.Made = try makeCourse(surface: .mcp)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner
        )
        XCTAssertTrue(
            outcome.detail.contains(AssistWording.builtWithNoWindowOpen(course: "ICS3U", section: "1")), outcome.detail
        )
        XCTAssertEqual(ending(of: outcome), AssistToolRunner.changedTheirFiles)
    }

    /// A rebuild declined because a copy of the course is being zipped. The
    /// change itself is written. MUST FAIL on the old rule.
    func testARebuildDeclinedWhileACopyIsZippedClaimsNoPreview() async throws {
        let made: AssistFixture.Made = try makeCourse(surface: .local)
        CourseActivity.beginCopy(folderPath: made.root.path, courseCode: "ICS3U")
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner
        )
        XCTAssertTrue(outcome.detail.contains("Done: "), "the change was refused before carryOut: \(outcome.detail)")
        XCTAssertTrue(outcome.detail.contains(AssistWording.courseIsBeingCopied(course: "ICS3U")), outcome.detail)
        XCTAssertEqual(ending(of: outcome), AssistToolRunner.changedTheirFiles)
    }

    /// A rebuild declined because this copy of Plantoir is deploying the
    /// section. MUST FAIL on the old rule, if the change reaches carryOut.
    func testARebuildDeclinedWhileTheSectionDeploysClaimsNoPreview() async throws {
        let made: AssistFixture.Made = try makeCourse(surface: .local)
        CourseActivity.beginPublish(folderPath: made.root.path, courseCode: "ICS3U", sectionNumber: 1)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner
        )
        XCTAssertTrue(outcome.detail.contains("Done: "), "the change was refused before carryOut: \(outcome.detail)")
        XCTAssertTrue(
            outcome.detail.contains(AssistWording.sectionIsBeingDeployed(course: "ICS3U", section: "1")), outcome.detail
        )
        XCTAssertEqual(ending(of: outcome), AssistToolRunner.changedTheirFiles)
    }

    /// The other half, so the rule cannot pass by never claiming: with the
    /// section's window open, its preview is restarted and the claim is made.
    func testAPreviewRestartedInItsWindowIsClaimed() async throws {
        let made: AssistFixture.Made = try makeCourse(surface: .local, registeringPreview: true)
        let outcome: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner
        )
        XCTAssertTrue(
            outcome.detail.contains(AssistWording.previewIsRebuilding(course: "ICS3U", section: "1")), outcome.detail
        )
        XCTAssertEqual(ending(of: outcome), AssistToolRunner.changedTheirFilesAndPreview)
    }
}
