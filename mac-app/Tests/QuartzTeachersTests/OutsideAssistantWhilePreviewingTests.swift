import XCTest
@testable import QuartzTeachers

/// An outside assistant (Claude or Codex, through `Plantoir --mcp-stdio`) is
/// held back only while a site of the course is being BUILT; a preview that is
/// only being served holds nothing back (#433, Russell 2026-10-03).
///
/// Runs `contracts/shared-rules.json` → `workLeases.declining.outsideChanges`
/// through the real tool runner on the `.mcp` surface, with the "other
/// program" a real `/bin/sleep` child whose leases are real files. The site
/// work is the stub, so nothing is built or deployed: what is checked is
/// whether the runner ASKED for a build or a deploy, whether the page changed,
/// and what the assistant is told.
///
/// Swaps `ActivityTrail.store` and resets `WorkLeaseRegistry` — process-wide
/// state — so it relies on the scheme running classes one at a time.
@MainActor
final class OutsideAssistantWhilePreviewingTests: XCTestCase {

    // MARK: - Stored properties

    var other: Process?

    var previousTrail: ProblemReportStore = ActivityTrail.store

    var roots: [URL] = []

    // MARK: - Setting up

    override func setUp() async throws {
        CourseActivity.reset()
        PreviewLeases.reset()
        WorkLeaseRegistry.reset()
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        if let other, other.isRunning {
            other.terminate()
            other.waitUntilExit()
        }
        other = nil
        ActivityTrail.store = previousTrail
        WorkLeaseRegistry.reset()
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
        roots = []
    }

    // MARK: - Helpers

    /// A fresh course with one unpublished class, an outside assistant's
    /// runner over it, and the trail pointed inside the folder.
    func makeCourse(surface: AssistToolRunner.Surface = .mcp) throws -> AssistFixture.Made {
        let made: AssistFixture.Made = try AssistFixture.makeRunner(hasDeployedBefore: true, surface: surface)
        roots.append(made.root)
        ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))
        try AssistFixture.write(page: "Unit 1, Day 1", publish: "false", body: "One.", in: made.course)
        return made
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

    func writeOthersLeases(_ kinds: [String], in root: URL) throws {
        if kinds.isEmpty {
            return
        }
        let pid: Int32 = try otherProgram()
        let coursesURL: URL = root.appendingPathComponent("courses")
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let when: String = ProcessLiveness.leaseMomentText(Date().addingTimeInterval(-1))
        let start: String = ProcessLiveness.startTime(ofProcess: pid) ?? ""
        for kind in kinds {
            let url: URL = directory.appendingPathComponent(
                WorkLeaseFiles.fileName(courseCode: "ICS3U", kind: kind, pid: pid)
            )
            try Data("\(pid)\nsleep\n\(when)\n\(start)\n".utf8).write(to: url)
        }
    }

    func trailText(in root: URL) -> String {
        var text: String = ""
        let folder: URL = root.appendingPathComponent("trail")
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
                text += String(decoding: data, as: UTF8.self)
            }
        }
        return text
    }

    /// Every file under the course folder, with its bytes — leases and the
    /// app's own `.internal` bookkeeping left out.
    func snapshot(of courseURL: URL) -> [String: Data] {
        var files: [String: Data] = [:]
        guard let walker = FileManager.default.enumerator(at: courseURL, includingPropertiesForKeys: nil) else {
            return files
        }
        for case let url as URL in walker {
            if url.path.contains("/.internal/") {
                continue
            }
            if let data = try? Data(contentsOf: url) {
                files[url.path] = data
            }
        }
        return files
    }

    /// A key the contract names, as the product says it for ICS3U Section 1.
    func sentence(forKey key: String) -> String? {
        switch key {
        case "changesAreSavedPreviewShowsTheOldPages":
            return AssistWording.changesAreSavedPreviewShowsTheOldPages(course: "ICS3U", section: "1")
        case "courseIsBeingBuilt":
            return AssistWording.courseIsBeingBuilt(course: "ICS3U")
        case "deployClosedAnOpenPreview":
            return AssistWording.deployClosedAnOpenPreview(course: "ICS3U", section: "1")
        default:
            return nil
        }
    }

    // MARK: - The contract's cases

    /// MUST FAIL before #433: the served-preview change ended with
    /// `courseIsBusy`, the building-preview change was WRITTEN, and the
    /// served-preview deploy was refused.
    func testTheOutsideChangesCasesAreTheContracts() async throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(
            ["workLeases", "declining", "outsideChanges"]
        )
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10, "Cases went missing from the contract.")

        var ran: Int = 0
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            let others: [String] = try XCTUnwrap(item["others"] as? [String], name)
            let asked: String = try XCTUnwrap(item["asked"] as? String, name)
            let expect: [String: Any] = try XCTUnwrap(item["expect"] as? [String: Any], name)

            let made: AssistFixture.Made = try makeCourse()
            try writeOthersLeases(others, in: made.root)
            let pageURL: URL = AssistFixture.pageURL(of: "Unit 1, Day 1", in: made.course)
            let pageBefore: Data = try Data(contentsOf: pageURL)
            let courseBefore: [String: Data] = snapshot(of: made.course.directoryURL)

            let outcome: AssistToolOutcome
            switch asked {
            case "change":
                outcome = await AssistFixture.run("publish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner)
            case "rebuild":
                outcome = await AssistFixture.run("rebuild_preview", with: [:], on: made.runner)
            case "deploy":
                outcome = await AssistFixture.run("deploy_section", with: [:], on: made.runner)
            default:
                XCTFail("Unknown ask '\(asked)' in: \(name)")
                continue
            }

            let written: Bool = try Data(contentsOf: pageURL) != pageBefore
            XCTAssertEqual(written, try XCTUnwrap(expect["written"] as? Bool, name), "\(name): \(outcome.detail)")
            if !written {
                XCTAssertEqual(snapshot(of: made.course.directoryURL), courseBefore,
                               "\(name): a change that was held back touched the course.")
                XCTAssertFalse(trailText(in: made.root).contains("backed up the course"),
                               "\(name): a backup was made before the refusal.")
            }
            XCTAssertEqual(made.siteWork.previewRebuilds > 0, try XCTUnwrap(expect["built"] as? Bool, name),
                           "\(name): \(outcome.detail)")
            XCTAssertEqual(made.siteWork.deploys > 0, try XCTUnwrap(expect["deployed"] as? Bool, name),
                           "\(name): \(outcome.detail)")
            if let key = expect["said"] as? String {
                let said: String = try XCTUnwrap(sentence(forKey: key), "\(name): unknown key \(key)")
                XCTAssertTrue(outcome.detail.contains(said), "\(name): said \(outcome.detail)")
                if key == "courseIsBeingBuilt" {
                    XCTAssertEqual(outcome.detail, said, "\(name): a refusal is the whole answer")
                }
            }
            ran += 1
            if let other, other.isRunning {
                other.terminate()
                other.waitUntilExit()
            }
            other = nil
        }
        XCTAssertEqual(ran, cases.count, "A case was not run.")
    }

    // MARK: - The words

    /// Nothing said after a change that SUCCEEDED may read as a refusal
    /// (#433, ruling 3), and none of the new sentences names the machinery
    /// (CLAUDE.md rule 1).
    func testTheSavedSentencesCarryNoRefusalWord() {
        let saidAfterSuccess: [String] = [
            AssistWording.changesAreSavedPreviewShowsTheOldPages(course: "ICS3U", section: "1"),
            AssistWording.changesAreSavedWhileTheCourseIsBuilt(course: "ICS3U", section: "1"),
            AssistWording.deployClosedAnOpenPreview(course: "ICS3U", section: "1"),
        ]
        for text in saidAfterSuccess {
            let lowered: String = text.lowercased()
            for word in ["busy", "couldn't", "couldn’t", "could not", "wait", "refuse", "declin", "ask again"] {
                XCTAssertFalse(lowered.contains(word), "'\(word)' in a sentence said after a success: \(text)")
            }
        }
        var every: [String] = saidAfterSuccess
        every.append(AssistWording.courseIsBeingBuilt(course: "ICS3U"))
        for text in every {
            let lowered: String = text.lowercased()
            for word in ["toolchain", "script", "docker", "container", "lease", "process"] {
                XCTAssertFalse(lowered.contains(word), "'\(word)' names the machinery: \(text)")
            }
        }
        // The controls are named as the section window labels them.
        XCTAssertTrue(saidAfterSuccess[0].contains("Stop Preview, then Preview"))
    }

    // MARK: - The pure rule

    /// A building lease wins over a preview lease whichever is read first.
    /// MUST FAIL if the preview is allowed to answer first.
    func testABuildingLeaseWinsOverAPreviewLease() {
        let preview: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(kind: "preview", pid: 7, moment: nil)
        let build: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(kind: "build", pid: 7, moment: nil)
        let assist: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(kind: "assist", pid: 7, moment: nil)
        XCTAssertEqual(WorkLeaseFiles.whatAnOutsideChangeMeets(among: [preview, build]), .building(build))
        XCTAssertEqual(WorkLeaseFiles.whatAnOutsideChangeMeets(among: [build, preview]), .building(build))
        XCTAssertEqual(WorkLeaseFiles.whatAnOutsideChangeMeets(among: [preview]), .previewServed(preview))
        XCTAssertEqual(WorkLeaseFiles.whatAnOutsideChangeMeets(among: [assist]), .clear)
        XCTAssertEqual(WorkLeaseFiles.whatAnOutsideChangeMeets(among: []), .clear)
    }

    // MARK: - The in-app assistant is untouched

    /// #433 is for Claude and Codex only (Russell, 2026-10-03; ruling 4):
    /// the in-app assistant, meeting another program's served preview, says
    /// exactly what it said before. MUST FAIL if the outside rule leaks into
    /// `.local`.
    func testTheInAppAssistantSaysWhatItSaidBefore() async throws {
        let made: AssistFixture.Made = try makeCourse(surface: .local)
        try writeOthersLeases(["preview"], in: made.root)
        let before: String = AssistWording.courseIsBeingBuiltElsewhere(course: "ICS3U")

        let deployed: AssistToolOutcome = await AssistFixture.run("deploy_section", with: [:], on: made.runner)
        XCTAssertEqual(deployed.detail, before)
        XCTAssertEqual(made.siteWork.deploys, 0)

        let rebuilt: AssistToolOutcome = await AssistFixture.run("rebuild_preview", with: [:], on: made.runner)
        XCTAssertEqual(rebuilt.detail, before)
        XCTAssertEqual(made.siteWork.previewRebuilds, 0)

        let published: AssistToolOutcome = await AssistFixture.run(
            "publish_pages", with: ["pages": "Unit 1, Day 1"], on: made.runner
        )
        XCTAssertTrue(published.detail.contains("\n\n" + before + "\n\n"), published.detail)
        XCTAssertTrue(published.detail.contains("their PREVIEW"), published.detail)
        XCTAssertFalse(trailText(in: made.root).contains("left the preview open in Plantoir as it was"))
    }
}
