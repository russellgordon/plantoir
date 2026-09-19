import XCTest
@testable import QuartzTeachers

/// "Hide Unit 4, Day 21" — the word the model could not answer, answered in
/// code.
///
/// **Why this file exists.** Measured on 2026-09-19 (issue #215): the smaller
/// assistant sent "unpublish unit 4, day 21" to `unpublish_pages` every time,
/// and answered "hide unit 4, day 21" with no tool at all, in five phrasings
/// out of five — it handed the teacher their own sentence back as text. The
/// fix is a widened parsed family that never reaches the model, and the half
/// that matters is the REFUSALS: a matched card binds this window's course and
/// section into the call unconditionally, so a frame that swallowed "hide unit
/// 4, day 21 in ICS3U" would act on the window's own course and report
/// success.
///
/// Every case is read from `contracts/assist-cases.json` → `hideIsUnpublish`,
/// which the Windows suite can run too. Nothing is typed here that could
/// disagree with it.
@MainActor
final class HideIsUnpublishCardTests: XCTestCase {

    // MARK: - The grammar

    /// Every spelling the contract says is answered in code, is — and reaches
    /// the tool and the page reference it names.
    func testEverySpellingTheContractAcceptsIsAnsweredInCode() throws {
        for row in try HideIsUnpublishCardTests.rows(named: "accepted") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is accepted for no stated reason")
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(input),
                "\"\(input)\" is in the contract as answered in code and matches nothing"
            )
            XCTAssertEqual(command.toolName, row["expectTool"] as? String, input)
            XCTAssertEqual(command.arguments["pages"], row["expectPages"] as? String, input)
            // A card cannot honour another course or another section, because
            // the agent writes this window's own into every card call — so a
            // card that appeared to carry one would be answering a different
            // question with total confidence.
            XCTAssertNil(command.arguments["course"], input)
            XCTAssertNil(command.arguments["section"], input)
        }
    }

    /// And every spelling it says goes to the model, does.
    ///
    /// The half that stops the family widening. A negation, a second page, a
    /// course named, a word this frame does not have — each must fall through,
    /// because answering the wrong question with total confidence is worse
    /// than routing it.
    func testEverySpellingTheContractRefusesGoesToTheModel() throws {
        for row in try HideIsUnpublishCardTests.rows(named: "refused") {
            let input: String = try XCTUnwrap(row["input"] as? String)
            XCTAssertNotNil(row["why"] as? String, "\(input) is refused for no stated reason")
            XCTAssertNil(
                AssistCardCommand.matching(input),
                "\"\(input)\" is in the contract as one that goes to the model and was matched in code"
            )
        }
    }

    // MARK: - The two verbs cannot drift apart

    /// One frame, one verb table: whatever "unpublish" answers, "hide"
    /// answers identically.
    ///
    /// Written as a property rather than as more rows, because the fault it
    /// guards against is a later edit teaching one verb something the other
    /// does not know — which no fixed list of spellings would catch.
    func testHideAndUnpublishAnswerTheSameThing() {
        for reference in ["unit 4", "unit 4, day 21", "unit 04", "unit 7 day 2"] {
            let hidden: AssistCardCommand? = AssistCardCommand.matching("hide \(reference)")
            let unpublished: AssistCardCommand? = AssistCardCommand.matching("unpublish \(reference)")
            XCTAssertEqual(hidden, unpublished, reference)
            XCTAssertNotNil(hidden, reference)
        }
    }

    /// And publishing keeps the narrower frame it has always had.
    ///
    /// The asymmetry is the decision, not an oversight: unpublishing errs safe
    /// — a page nobody can see — while publishing puts a page in front of
    /// students, and the smaller assistant answers "Publish Unit 2, Day 3"
    /// correctly anyway.
    func testPublishStillTakesAWholeUnitAndNoPage() throws {
        let whole: AssistCardCommand = try XCTUnwrap(AssistCardCommand.matching("publish unit 5"))
        XCTAssertEqual(whole.toolName, "publish_pages")
        XCTAssertEqual(whole.arguments["pages"], "Unit 5")

        XCTAssertNil(
            AssistCardCommand.matching("publish unit 4, day 3"),
            "The day arm is not gated on the verb, so the publish family widened too."
        )
        XCTAssertNil(AssistCardCommand.matching("publish unit 4 day 3"))
        XCTAssertNil(AssistCardCommand.matching("please publish unit 4, day 3 please"))
    }

    // MARK: - What the shelf promises

    /// The shelf's own card is answered in code now.
    ///
    /// Named here as well as in `AssistPromptShelfTests`, because "the card a
    /// teacher clicks does what it says" is the claim this family was added
    /// for, and it should fail in the file about the family too.
    func testTheShelfsUnpublishCardIsAnsweredInCode() throws {
        let command: AssistCardCommand = try XCTUnwrap(
            AssistCardCommand.matching("Unpublish Unit 2, Day 3")
        )
        XCTAssertEqual(command.toolName, "unpublish_pages")
        XCTAssertEqual(command.arguments["pages"], "Unit 2, Day 3")
    }

    // MARK: - Reading the contract

    private static func rows(named key: String) throws -> [[String: Any]] {
        let family: [String: Any] = try XCTUnwrap(
            contract()["hideIsUnpublish"] as? [String: Any],
            "contracts/assist-cases.json has no hideIsUnpublish"
        )
        XCTAssertNotNil(family["note"] as? String)
        let rows: [[String: Any]] = try XCTUnwrap(family[key] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty, "\(key) has been emptied out")
        return rows
    }

    private static func contract() throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts")
                .appendingPathComponent(AssistContract.casesFileName)
        )
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
