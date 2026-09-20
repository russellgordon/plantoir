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

            let underWay: String? = QuitConfirmation.workUnderWay(
                publishes: CourseActivity.activePublishes
            )
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
        ]))
        XCTAssertEqual(one, "publishing Section 2 of ADA1O")

        let several: String = try XCTUnwrap(QuitConfirmation.workUnderWay(publishes: [
            CourseActivity.PublishRecord(folderPath: "/p", courseCode: "ADA1O", sectionNumber: 1),
            CourseActivity.PublishRecord(folderPath: "/p", courseCode: "ICS3U", sectionNumber: 1)
        ]))
        XCTAssertEqual(several, "publishing 2 sections")

        XCTAssertNil(QuitConfirmation.workUnderWay(publishes: []))

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
