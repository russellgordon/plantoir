import XCTest
@testable import QuartzTeachers

/// A section's deploy outlives the view that started it (GitHub #706).
///
/// The defect: the section view is rebuilt for every selection, and its
/// deploy runner was the view's own state, so coming back to a section
/// mid-deploy showed a fresh, blank runner with Deploy enabled — and a press
/// then reached the launcher's "already being deployed" refusal, or during
/// the deploy's build started a second build that ended the first. The rule
/// is `contracts/shared-rules.json` → `returningToASectionMidDeploy`, walked
/// here as data; the view's half — that it binds to the store and never
/// deploys on appearing — is the source scan at the end, and the real
/// window is `QuartzTeachersUITests.testReturningToASectionMidDeployShowsTheDeploy`.
///
/// Serial with `CourseActivityTests` and the other classes that reset
/// process-wide statics: the scheme runs test classes one at a time.
@MainActor
final class SectionRunsTests: XCTestCase {

    // MARK: - Set up

    override func setUp() async throws {
        SectionRuns.shared.reset()
        CourseActivity.reset()
    }

    override func tearDown() async throws {
        SectionRuns.shared.reset()
        CourseActivity.reset()
    }

    // MARK: - The store

    /// The defect itself: the view that comes back must find the run the
    /// deploy is still writing — the same object, however the folder is
    /// spelled — and Deploy must be unavailable while it runs.
    func testReturningToASectionFindsItsDeployStillRunning() throws {
        let folder: URL = try makeFolder()
        let spelledWithPrivate: URL = URL(fileURLWithPath: FolderIdentity.canonicalPath(folder.path))
        var spelledWithoutPrivate: URL = spelledWithPrivate
        if spelledWithPrivate.path.hasPrefix("/private/var/") {
            spelledWithoutPrivate = URL(fileURLWithPath: String(spelledWithPrivate.path.dropFirst("/private".count)))
        }

        let leaving: SectionDeployRun = SectionRuns.shared.deploy(
            folder: spelledWithPrivate, courseCode: "EXC2O", sectionNumber: 1
        )
        leaving.runner.isRunning = true

        let returning: SectionDeployRun = SectionRuns.shared.deploy(
            folder: spelledWithoutPrivate, courseCode: "exc2o", sectionNumber: 1
        )
        XCTAssertTrue(
            leaving === returning,
            "The view that comes back must bind to the run the deploy is still writing, not a fresh one"
        )
        XCTAssertFalse(
            SectionDetailView.deployIsAvailable(
                run: returning, folderPath: spelledWithoutPrivate.path, courseCode: "EXC2O", sectionNumber: 1,
                isBeingCopied: false, folderIsGettingReady: false, heldElsewhere: false
            ),
            "Deploy must be unavailable while the section's deploy runs"
        )
        XCTAssertNil(
            SectionRuns.shared.existingDeploy(folder: spelledWithPrivate, courseCode: "EXC2O", sectionNumber: 2),
            "Another section has no run until it is asked for one"
        )
    }

    /// A deploy of the section this app has under way that the section's run
    /// cannot see — the assistant with no window, or a run whose view has
    /// gone — still makes Deploy unavailable; another section stays
    /// available.
    func testDeployIsUnavailableWhileThisAppDeploysTheSectionFromAnywhere() throws {
        let folder: URL = try makeFolder()
        CourseActivity.beginPublish(folderPath: folder.path, courseCode: "EXC2O", sectionNumber: 1)

        let sectionOne: SectionDeployRun = SectionRuns.shared.deploy(folder: folder, courseCode: "EXC2O", sectionNumber: 1)
        let sectionTwo: SectionDeployRun = SectionRuns.shared.deploy(folder: folder, courseCode: "EXC2O", sectionNumber: 2)
        XCTAssertFalse(sectionOne.isBusy, "the run itself knows nothing of the windowless deploy")
        XCTAssertFalse(
            SectionDetailView.deployIsAvailable(
                run: sectionOne, folderPath: folder.path, courseCode: "EXC2O", sectionNumber: 1,
                isBeingCopied: false, folderIsGettingReady: false, heldElsewhere: false
            ),
            "A deploy of this section anywhere in this app makes Deploy unavailable"
        )
        XCTAssertTrue(
            SectionDetailView.deployIsAvailable(
                run: sectionTwo, folderPath: folder.path, courseCode: "EXC2O", sectionNumber: 2,
                isBeingCopied: false, folderIsGettingReady: false, heldElsewhere: false
            ),
            "Another section's Deploy is left as it was"
        )

        CourseActivity.endPublish(folderPath: folder.path, courseCode: "EXC2O", sectionNumber: 1)
        XCTAssertTrue(
            SectionDetailView.deployIsAvailable(
                run: sectionOne, folderPath: folder.path, courseCode: "EXC2O", sectionNumber: 1,
                isBeingCopied: false, folderIsGettingReady: false, heldElsewhere: false
            ),
            "Once it has ended, Deploy is available again"
        )
    }

    /// A finished run keeps its outcome for the view that comes back, and its
    /// findings are taken by exactly one view.
    func testAFinishedRunKeepsItsOutcomeAndFindings() throws {
        let folder: URL = try makeFolder()
        let run: SectionDeployRun = SectionRuns.shared.deploy(folder: folder, courseCode: "EXC2O", sectionNumber: 1)
        let startedAt: Date = Date(timeIntervalSince1970: 1_790_000_000)
        run.runner.startedAt = startedAt
        let endingsBefore: Int = run.endings

        run.noteEnded()

        let returning: SectionDeployRun = SectionRuns.shared.deploy(folder: folder, courseCode: "EXC2O", sectionNumber: 1)
        XCTAssertTrue(run === returning)
        XCTAssertEqual(returning.runner.startedAt, startedAt, "the finished run is the one shown, not a fresh one")
        XCTAssertEqual(returning.endings, endingsBefore + 1, "a view showing the section is told it ended")
        XCTAssertTrue(returning.takeFindings(), "the first view to look takes the findings")
        XCTAssertFalse(returning.takeFindings(), "a second view on the same section does not raise them again")
        XCTAssertTrue(
            SectionDetailView.deployIsAvailable(
                run: returning, folderPath: folder.path, courseCode: "EXC2O", sectionNumber: 1,
                isBeingCopied: false, folderIsGettingReady: false, heldElsewhere: false
            ),
            "a finished deploy leaves Deploy available"
        )
    }

    /// A finished deploy is shown on return only until one view has
    /// displayed its ending (#706 review, M1): the view that came back and
    /// showed it counts, and the next one to come shows the section's
    /// ordinary state. A later deploy's ending is shown again.
    func testAnEndingOnceShownIsNotShownAgain() throws {
        let folder: URL = try makeFolder()
        let run: SectionDeployRun = SectionRuns.shared.deploy(folder: folder, courseCode: "EXC2O", sectionNumber: 1)
        run.runner.startedAt = Date(timeIntervalSince1970: 1_790_000_000)
        giveOutput(to: run)
        run.noteEnded()

        let firstToCome: Int? = run.endingToHideOnAppearing()
        XCTAssertNil(firstToCome, "an ending nobody has seen is not hidden")
        XCTAssertTrue(run.isShown(hidingEnding: firstToCome), "the first view back shows how it ended")
        run.noteEndingShown()
        XCTAssertTrue(run.isShown(hidingEnding: firstToCome), "and keeps showing it while it stays")

        let nextToCome: Int? = run.endingToHideOnAppearing()
        XCTAssertFalse(run.isShown(hidingEnding: nextToCome), "the next view back shows the section's ordinary state")

        run.runner.isRunning = true
        XCTAssertTrue(run.isShown(hidingEnding: nextToCome), "a new deploy is shown, live, in that same view")
        run.runner.isRunning = false
        run.noteEnded()
        XCTAssertTrue(run.isShown(hidingEnding: nextToCome), "and so is how that new deploy ended")
    }

    /// A preview of the section that started after the deploy wins over the
    /// deploy's finished panel, even in a view whose own preview runner has
    /// no start time — a view that came back (#706 review, M1).
    func testALaterPreviewOfTheSectionWinsOverAFinishedDeploy() throws {
        let folder: URL = try makeFolder()
        let run: SectionDeployRun = SectionRuns.shared.deploy(folder: folder, courseCode: "EXC2O", sectionNumber: 1)
        let deployStart: Date = Date(timeIntervalSince1970: 1_790_000_000)
        run.runner.startedAt = deployStart
        giveOutput(to: run)
        run.noteEnded()
        XCTAssertTrue(run.isShown(hidingEnding: nil))

        let previewStart: Date = deployStart.addingTimeInterval(3 * 60 * 60)
        run.notePreviewStarted(at: previewStart)
        XCTAssertFalse(run.isShown(hidingEnding: nil), "a later preview means the deploy's panel does not come back")
        // What `showsDeployProgress` is given by a view that came back: its
        // own preview runner has never started.
        let thisViewsPreviewStart: Date? = nil
        XCTAssertFalse(
            SectionDetailView.showsDeployProgress(
                previewIsRunning: false, deployIsRunning: false,
                previewStartedAt: thisViewsPreviewStart ?? run.previewLastStartedAt,
                deployStartedAt: run.runner.startedAt
            ),
            "with no preview start of its own, the view compares against the section's"
        )
    }

    // MARK: - The contract

    /// `shared-rules.json` → `returningToASectionMidDeploy.cases`, each set up
    /// as its `startedBy` says and asked as a returning view asks.
    func testReturningToASectionMidDeployCases() throws {
        let section: [String: Any] = try SharedRulesContractTests.section("returningToASectionMidDeploy")
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 11)
        for testCase in cases {
            SectionRuns.shared.reset()
            CourseActivity.reset()
            let startedBy: String = try XCTUnwrap(testCase["startedBy"] as? String)
            let then: String = try XCTUnwrap(testCase["then"] as? String)
            let label: String = "\(startedBy) / \(then)"
            let folder: URL = try makeFolder()
            let otherFolder: URL = try makeFolder()

            // Who started it, and where — written the way the app writes it.
            var startedFolder: URL = folder
            var startedSection: Int = 1
            var startedWithTheRun: Bool = true
            switch startedBy {
            case "thisSectionBeforeLeaving":
                break
            case "anotherWindowSameFolder":
                // Another window's view, the folder reached by another name.
                startedFolder = URL(fileURLWithPath: FolderIdentity.canonicalPath(folder.path))
            case "theAssistantWithNoWindow":
                startedWithTheRun = false
            case "anotherSection":
                startedSection = 2
            case "anotherWorkingFolder":
                startedFolder = otherFolder
            default:
                XCTFail("\(label): a startedBy this test does not know")
            }
            var started: SectionDeployRun? = nil
            if startedWithTheRun {
                started = SectionRuns.shared.deploy(folder: startedFolder, courseCode: "EXC2O", sectionNumber: startedSection)
            }
            let deployStart: Date = Date(timeIntervalSince1970: 1_790_000_000)
            started?.runner.startedAt = deployStart
            switch then {
            case "returned":
                started?.runner.isRunning = true
                CourseActivity.beginPublish(folderPath: startedFolder.path, courseCode: "EXC2O", sectionNumber: startedSection)
            case "finishedWhileAway":
                if let started {
                    giveOutput(to: started)
                    started.noteEnded()
                }
            case "watchedToTheEndThenPreviewed":
                // The view that started it watched it end, and a preview of
                // the section started after it.
                if let started {
                    giveOutput(to: started)
                    started.noteEnded()
                    started.noteEndingShown()
                    started.notePreviewStarted(at: deployStart.addingTimeInterval(60))
                }
            case "watchedToTheEnd":
                // The view that started it watched it end; no preview since.
                if let started {
                    giveOutput(to: started)
                    started.noteEnded()
                    started.noteEndingShown()
                }
            case "finishedWhileAwayThenPreviewedFromAnotherWindow":
                // It ended with no view showing the section, and another
                // window then started a preview of the section.
                if let started {
                    giveOutput(to: started)
                    started.noteEnded()
                    started.notePreviewStarted(at: deployStart.addingTimeInterval(60))
                }
            default:
                XCTFail("\(label): a then this test does not know")
            }

            // The teacher comes back to section 1 of the first folder.
            let returning: SectionDeployRun = SectionRuns.shared.deploy(folder: folder, courseCode: "EXC2O", sectionNumber: 1)
            let available: Bool = SectionDetailView.deployIsAvailable(
                run: returning, folderPath: folder.path, courseCode: "EXC2O", sectionNumber: 1,
                isBeingCopied: false, folderIsGettingReady: false, heldElsewhere: false
            )
            let underWay: Bool = SectionDetailView.deployIsUnderWay(
                run: returning, folderPath: folder.path, courseCode: "EXC2O", sectionNumber: 1
            )
            // What a view coming back shows: the run it binds to, given its
            // console only when `isShown` says so, after hiding on appearing
            // whatever ending another view has already shown.
            var showsTheRun: Bool = false
            if let started, started === returning {
                showsTheRun = returning.isShown(hidingEnding: returning.endingToHideOnAppearing())
            }

            XCTAssertEqual(available, testCase["deployAvailable"] as? Bool, "\(label): deployAvailable")
            XCTAssertEqual(showsTheRun, testCase["showsTheRun"] as? Bool, "\(label): showsTheRun")
            // Coming back asks the store and nothing else; the source scan
            // below is what holds the view to that.
            XCTAssertEqual(testCase["selectingStartsALauncher"] as? Bool, false, "\(label): selecting never starts anything")
            // A press reaches a launcher only when `deployAndWait`'s first
            // busy check lets it through.
            XCTAssertEqual(!underWay, testCase["aPressStartsALauncher"] as? Bool, "\(label): aPressStartsALauncher")
        }
    }

    // MARK: - The view

    /// The view's half of the rule, which no model test can reach: its
    /// deploy state is the store's, nothing that runs on appearing deploys,
    /// and the deploy itself uses one run, taken once (#706 plan review, H1).
    /// Fails on the code before #706, which held `@State var deployRunner`.
    func testTheSectionViewBindsToTheStoreAndNeverDeploysOnAppearing() throws {
        let source: String = try readSource("QuartzTeachers/Views/Section/SectionDetailView.swift")
        XCTAssertFalse(source.contains("@State var deployRunner"), "the deploy runner must not be the view's own state")
        XCTAssertFalse(source.contains("@State var isPreparingDeploy"), "nor whether a deploy is being prepared")
        XCTAssertTrue(
            source.contains("SectionRuns.shared.deploy("),
            "the view must find its section's run in the store"
        )

        for opening in [".onAppear {", ".task {"] {
            var remaining: Substring = Substring(source)
            while let range = remaining.range(of: opening) {
                let body: String = bodyFrom(range.lowerBound, in: remaining)
                XCTAssertFalse(body.contains("startDeploy("), "\(opening) must never start a deploy")
                // The assistant's registration names `deployAndWait` as a
                // closure it may CALL later; calling it is what is forbidden.
                XCTAssertFalse(body.contains("await deployAndWait(pressedByTheAssistant: false)"), "\(opening) must never deploy")
                remaining = remaining[range.upperBound...]
            }
        }

        let deployBody: String = try XCTUnwrap(
            bodyOfFunction(startingWith: "func deployAndWait(", in: source)
        )
        XCTAssertFalse(deployBody.contains("deployRunner"), "deployAndWait must use the run it took once")
        XCTAssertFalse(deployBody.contains("isPreparingDeploy"), "deployAndWait must use the run it took once")
        XCTAssertFalse(deployBody.contains("deployRun."), "deployAndWait must not ask for the run again")
        XCTAssertTrue(deployBody.contains("let run: SectionDeployRun = SectionRuns.shared.deploy("))
        let cancelBody: String = try XCTUnwrap(bodyOfFunction(startingWith: "func cancelDeploy(", in: source))
        XCTAssertTrue(cancelBody.contains("run.folder"), "Cancel aims at the folder the deploy noted")

        // A view that came back has a preview runner with no start time, so
        // it must fall back on the section's last preview start (#706 fixes
        // review, L3).
        let progressBody: String = try XCTUnwrap(
            bodyOfFunction(startingWith: "var showsDeployProgress: Bool {", in: source)
        )
        XCTAssertTrue(
            progressBody.contains("previewRunner.startedAt ?? deployRun.previewLastStartedAt"),
            "showsDeployProgress must compare against the section's last preview when the view has none"
        )
        // And every preview started tells the section's run, so that view
        // has something to compare against.
        let previewBody: String = try XCTUnwrap(bodyOfFunction(startingWith: "func startPreview(", in: source))
        XCTAssertTrue(
            previewBody.contains(".notePreviewStarted(at:"),
            "startPreview must tell the section's run that a preview started"
        )
    }

    /// #729: Deploy greys while another program holds the course. The
    /// button, Section ▸ Deploy… and ⇧⌘D all read `deployButtonIsEnabled`,
    /// which asks the folder's `LeaseWatcher`; the help and hint come from
    /// one chooser; the leases are read again when the section appears, when
    /// the app or its window comes to the front, and when the pointer
    /// reaches the button; and every window's folder is watched. The cases
    /// themselves are `LeaseWatcherTests.testEveryHeldElsewhereCase`.
    func testDeployAsksWhetherAnotherProgramHoldsTheCourse() throws {
        let view: String = try readSource("QuartzTeachers/Views/Section/SectionDetailView.swift")
        XCTAssertTrue(view.contains("heldElsewhere: courseIsHeldElsewhere"), "deployButtonIsEnabled must ask the watcher")
        XCTAssertTrue(view.contains(".disabled(!deployButtonIsEnabled)"))
        XCTAssertTrue(view.contains("deployButtonEnabled: deployButtonIsEnabled && !course.isKeptForReference"),
                      "the Section menu and its shortcut read the same predicate")
        XCTAssertTrue(view.contains(".help(SectionDetailView.deployHelp("), "the help comes from the one chooser")
        XCTAssertTrue(view.contains(".accessibilityHint(courseIsHeldElsewhere"), "VoiceOver hears the same sentence")
        XCTAssertEqual(view.components(separatedBy: "leaseWatcher?.reread()").count - 1, 4,
                       "appearing, the app and the window coming to the front, and the pointer on the button")
        let workspace: String = try readSource("QuartzTeachers/Models/WorkspaceModel.swift")
        XCTAssertEqual(workspace.components(separatedBy: "watchTheLeasesOfTheOpenFolders()").count - 1, 4,
                       "its definition, and a window registering, leaving and pointing at a folder")
        XCTAssertTrue(workspace.contains("LeaseWatchers.shared.follow(folders)"))
    }

    /// The ordinary help is unchanged, and the folder not being ready still
    /// wins over everything else.
    func testTheDeployHelpChooser() {
        XCTAssertEqual(
            SectionDetailView.deployHelp(folderReadinessReason: nil, heldElsewhere: false, courseCode: "EXC2O"),
            "Deploy this section's website"
        )
        XCTAssertEqual(
            SectionDetailView.deployHelp(folderReadinessReason: "Not ready.", heldElsewhere: true, courseCode: "EXC2O"),
            "Not ready."
        )
        XCTAssertEqual(
            SectionDetailView.deployHelp(folderReadinessReason: nil, heldElsewhere: true, courseCode: "EXC2O"),
            SectionDetailView.deployIsHeldElsewhere(course: "EXC2O")
        )
    }

    // MARK: - Helpers

    /// A finished leg with a line in its console, as a deploy that ran leaves.
    private func giveOutput(to run: SectionDeployRun) {
        let leg: MultiDestinationDeployRunner.Leg = MultiDestinationDeployRunner.Leg(
            destination: CourseConfiguration.DeployDestination(type: "local_folder", path: "/tmp/site")
        )
        leg.runner.transcript.append(rawText: "Deployed.\n")
        run.runner.legs = [leg]
    }

    private func makeFolder() throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SectionRunsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
        }
        return folder
    }

    private func readSource(_ relativePath: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func bodyOfFunction(startingWith opening: String, in source: String) -> String? {
        guard let start = source.range(of: opening) else {
            return nil
        }
        return bodyFrom(start.lowerBound, in: Substring(source))
    }

    /// The text from the first opening brace at or after `start` to its
    /// matching closing brace.
    private func bodyFrom(_ start: Substring.Index, in source: Substring) -> String {
        guard let firstBrace = source[start...].firstIndex(of: "{") else {
            return ""
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
                    break
                }
            }
        }
        return body
    }
}
