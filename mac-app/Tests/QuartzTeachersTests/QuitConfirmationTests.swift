import XCTest
@testable import QuartzTeachers

/// ⌘Q landing on work in flight.
///
/// The DECISION is tested, never the dialog: a modal cannot be put up in a
/// suite, and the part that can be got wrong is which facts count as work
/// under way and when the question must never be asked at all.
@MainActor
final class QuitConfirmationTests: XCTestCase {

    // MARK: - The contract's own cases

    /// `contracts/shared-rules.json` → `quittingWhileWorkIsUnderWay.cases`,
    /// run rather than retyped.
    func testTheRuleIsTheOneTheContractWritesDown() throws {
        let section: [String: Any] = try QuitConfirmationTests.section("quittingWhileWorkIsUnderWay")
        let cases: [[String: Any]] = try XCTUnwrap(section["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 3, "The case list has shrunk — a rule with no cases is a paragraph")

        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = try XCTUnwrap(testCase["given"] as? [String: Any])
            let expectAsk: Bool = try XCTUnwrap(testCase["expectAsk"] as? Bool)

            let publishCount: Int = try XCTUnwrap(given["publishesUnderWay"] as? Int)
            let previewCount: Int = try XCTUnwrap(given["previewsOpen"] as? Int)
            let reasonName: String = try XCTUnwrap(given["quitReason"] as? String)
            let reason: QuitConfirmation.Reason = reasonName == "theMacIsLoggingOutOrShuttingDown"
                ? .theMacIsLoggingOutOrShuttingDown
                : .theTeacherAskedToQuit

            CourseActivity.reset()
            PreviewLeases.reset()
            defer {
                CourseActivity.reset()
                PreviewLeases.reset()
            }
            for index in 0..<publishCount {
                CourseActivity.beginPublish(
                    folderPath: "/pretend", courseCode: "ADA1O", sectionNumber: index + 1
                )
            }
            for index in 0..<previewCount {
                _ = try PreviewLeases.lease(
                    folderPath: "/pretend", courseCode: "ICS3U", sectionNumber: index + 1
                )
            }

            // The no-argument form, on purpose: it is the one the delegate
            // calls and the one that chooses its own sources, so the case
            // below with previews open and nothing publishing can actually
            // fail. Handing it `activePublishes` here would make that case
            // pass for any implementation.
            let underWay: String? = QuitConfirmation.workUnderWay()
            XCTAssertEqual(
                QuitConfirmation.shouldAsk(reason: reason, workUnderWay: underWay),
                expectAsk,
                "\(name): the rule and the contract disagree"
            )
        }
    }

    // MARK: - What the teacher is shown

    /// The question names what is happening in the teacher's own terms, and
    /// never in the machinery's (rule 1).
    func testTheQuestionSaysWhatIsHappening() throws {
        let one: String = try XCTUnwrap(QuitConfirmation.workUnderWay(publishes: [
            CourseActivity.PublishRecord(folderPath: "/p", courseCode: "ADA1O", sectionNumber: 2)
        ], previews: []))
        XCTAssertEqual(one, "publishing Section 2 of ADA1O")

        let several: String = try XCTUnwrap(QuitConfirmation.workUnderWay(publishes: [
            CourseActivity.PublishRecord(folderPath: "/p", courseCode: "ADA1O", sectionNumber: 1),
            CourseActivity.PublishRecord(folderPath: "/p", courseCode: "ICS3U", sectionNumber: 1)
        ], previews: []))
        XCTAssertEqual(several, "publishing 2 sections")

        XCTAssertNil(QuitConfirmation.workUnderWay(publishes: [], previews: []))

        let shown: String = QuitConfirmation.question(about: one)
            + " " + QuitConfirmation.explanation()
            + " " + QuitConfirmation.keepWorkingButton
            + " " + QuitConfirmation.quitAnywayButton
        for word in ["container", "docker", "colima", "script", "toolchain", "process"] {
            XCTAssertFalse(
                shown.lowercased().contains(word),
                "\"\(word)\" is machinery and a teacher reads this: \(shown)"
            )
        }
    }

    /// Both answers reach the trail, and the line says which was chosen.
    func testBothAnswersAreWrittenDown() {
        let kept: String = QuitConfirmation.trailLine(
            workUnderWay: "publishing Section 1 of ADA1O", choice: .keepWorking
        )
        let went: String = QuitConfirmation.trailLine(
            workUnderWay: "publishing Section 1 of ADA1O", choice: .quitAnyway
        )
        XCTAssertNotEqual(kept, went)
        XCTAssertTrue(kept.contains("keep working"))
        XCTAssertTrue(went.contains("quit anyway"))
    }

    /// Keep Working is the DEFAULT button, and the contract says so rather
    /// than the code saying so alone.
    ///
    /// **The ORDER is what this pins, not a spelling.** `NSAlert` reports a
    /// POSITION — `.alertFirstButtonReturn` for whichever title went in
    /// first — so putting the two titles up as two separate lines meant a
    /// one-line reorder could swap what each answer MEANS and make Keep
    /// Working quit, with nothing red anywhere. Title and meaning now travel
    /// together in one ordered list that the alert builds itself from, and
    /// this reads the same list.
    func testTheSafeAnswerIsTheDefaultOne() throws {
        let section: [String: Any] = try QuitConfirmationTests.section("quittingWhileWorkIsUnderWay")
        let buttons: [String: Any] = try XCTUnwrap(section["buttons"] as? [String: Any])
        let defaultChoice: String = try XCTUnwrap(buttons["default"] as? String)
        XCTAssertEqual(defaultChoice, "keepWorking")
        XCTAssertNotNil(buttons["keepWorking"] as? String)
        XCTAssertNotNil(buttons["quitAnyway"] as? String)

        XCTAssertEqual(QuitConfirmation.buttonsInOrder.count, 2)
        XCTAssertEqual(
            QuitConfirmation.buttonsInOrder.first?.choice.rawValue, defaultChoice,
            "The first button is the default one, and the contract says which answer that has to be"
        )
        XCTAssertEqual(QuitConfirmation.buttonsInOrder.first?.title, QuitConfirmation.keepWorkingButton)
        XCTAssertEqual(QuitConfirmation.choice(atButtonIndex: 0), .keepWorking)
        XCTAssertEqual(QuitConfirmation.choice(atButtonIndex: 1), .quitAnyway)
        XCTAssertEqual(
            QuitConfirmation.choice(atButtonIndex: 7), .keepWorking,
            "An answer nobody recognises must be the safe one"
        )
    }

    // MARK: - What quitting stops, and what it deliberately does not

    /// Quitting ends a live PREVIEW the way the Stop button does, and leaves
    /// a PUBLISH alone — which is what the teacher was just told would
    /// happen. Without the first half the launcher outlives the app (a child
    /// on a pseudo-terminal is reparented, not killed), the quit script's
    /// host-side check sees it, and the quit frees nothing at all.
    ///
    /// Run against REAL launchers that sit there doing nothing, because the
    /// question is about runs that are actually in flight: a filter asserted
    /// against four runners that had already exited would pass saying
    /// nothing.
    func testQuittingEndsPreviewsAndLeavesPublishesAlone() async throws {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quit-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["preview.sh", "deploy.sh"] {
            // `exec`, so terminating the launcher terminates the sleep with
            // it. Without it bash exits in 0.06s and its foreground sleep is
            // reparented to launchd, leaving four strays per suite run.
            try Data("exec sleep 20\n".utf8).write(to: folder.appendingPathComponent(name))
        }

        let preview: ScriptRunner = ScriptRunner()
        let build: ScriptRunner = ScriptRunner()
        let publish: ScriptRunner = ScriptRunner()
        let stopping: ScriptRunner = ScriptRunner()
        XCTAssertFalse(preview.isALivePreview, "A runner that has run nothing is not a live preview")

        preview.run(scriptNamed: "preview.sh", arguments: ["ADA1O", "1"], workingDirectory: folder)
        build.run(
            scriptNamed: "preview.sh",
            arguments: ["ADA1O", "1", "--build-only"],
            workingDirectory: folder
        )
        publish.run(scriptNamed: "deploy.sh", arguments: ["ADA1O", "1"], workingDirectory: folder)
        stopping.run(
            scriptNamed: "preview.sh",
            arguments: ["ADA1O", "1", "--stop"],
            workingDirectory: folder
        )
        defer {
            preview.terminate()
            build.terminate()
            publish.terminate()
            stopping.terminate()
        }

        XCTAssertTrue(preview.isRunning, "The stand-in launcher did not start")
        XCTAssertTrue(preview.isALivePreview)
        XCTAssertFalse(
            build.isALivePreview,
            "A publish's own build wears preview.sh's name and must not be ended at quit"
        )
        XCTAssertFalse(publish.isALivePreview)
        XCTAssertFalse(stopping.isALivePreview, "A stop is the thing being asked for")

        var held: Int = 0
        for runner in ScriptRunner.runsInFlight where runner === preview || runner === publish {
            held += 1
        }
        XCTAssertEqual(held, 2, "A run in flight must be reachable from outside the window that started it")

        ScriptRunner.stopEveryLivePreview()
        var waitsLeft: Int = 100
        while preview.isRunning && waitsLeft > 0 {
            try await Task.sleep(for: .milliseconds(50))
            waitsLeft -= 1
        }
        XCTAssertFalse(preview.isRunning, "The preview was not ended")
        XCTAssertTrue(
            publish.isRunning,
            "Plantoir ended the teacher's publish. It may well stop on its own once the app's terminal goes — deploy.sh runs under set -euo pipefail — but the app must not be the thing that kills it."
        )
    }

    // MARK: - The Mac logging out

    /// A modal in the quit handler blocks a log out until macOS gives up and
    /// names the app as the one that would not go. The signal that tells the
    /// two apart is the quit reason on the Apple event being handled.
    func testTheMacLoggingOutIsNeverHeldUp() {
        for code in QuitConfirmation.systemQuitReasonCodes {
            XCTAssertEqual(
                QuitConfirmation.reason(forQuitReasonCode: code),
                .theMacIsLoggingOutOrShuttingDown,
                "A system quit was read as the teacher's own"
            )
            XCTAssertFalse(QuitConfirmation.shouldAsk(
                reason: .theMacIsLoggingOutOrShuttingDown,
                workUnderWay: "publishing Section 1 of ADA1O"
            ))
        }
        XCTAssertEqual(QuitConfirmation.reason(forQuitReasonCode: nil), .theTeacherAskedToQuit)
        XCTAssertEqual(
            QuitConfirmation.reason(forQuitReasonCode: OSType(0x7A7A7A7A)),
            .theTeacherAskedToQuit,
            "A reason code nobody recognises is an ordinary quit, not a log out"
        )
    }

    // MARK: - Functions

    private static func section(_ name: String) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in shared-rules.json")
    }
}
