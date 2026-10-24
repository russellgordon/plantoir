import XCTest
@testable import QuartzTeachers

/// The sentences that reach the assistant's Open in Obsidian (#610), read
/// from `contracts/assist-cases.json` → `openInObsidian`, never retyped.
///
/// The tool was MEASURED against the local model and kept off its list
/// (research/ai-assist/open-in-obsidian-610-results.txt), so the window
/// reaches it only through phrasings matched in code. Every `accepted`
/// sentence must therefore be one — or a teacher typing it reaches a model
/// that has never heard of the verb — and no `nearMisses` or `recordedOnly`
/// sentence may be, or "Open Unit 2, Day 3" would open whatever page the
/// preview happens to show.
@MainActor
final class OpenInObsidianPhrasingsTests: XCTestCase {

    // MARK: - Functions

    func testEveryAcceptedSentenceIsAnsweredInCodeWithNoArguments() throws {
        let family: [String: Any] = try OpenInObsidianPhrasingsTests.family()
        let accepted: [String] = try XCTUnwrap(family["accepted"] as? [String])
        XCTAssertGreaterThanOrEqual(accepted.count, 7, "openInObsidian.accepted has lost sentences")
        for sentence in accepted {
            let command: AssistCardCommand = try XCTUnwrap(
                AssistCardCommand.matching(sentence), "\"\(sentence)\" goes to a model that is not shown the verb"
            )
            XCTAssertEqual(command.toolName, "open_in_obsidian", sentence)
            XCTAssertEqual(command.arguments, [:], "\(sentence): the page is the window's, never named")
        }
    }

    func testNoNearMissIsAnsweredAsOpenInObsidian() throws {
        let family: [String: Any] = try OpenInObsidianPhrasingsTests.family()
        var sentences: [String] = try XCTUnwrap(family["nearMisses"] as? [String])
        for sentence in family["recordedOnly"] as? [String] ?? [] {
            sentences.append(sentence)
        }
        for sentence in sentences {
            let command: AssistCardCommand? = AssistCardCommand.matching(sentence)
            XCTAssertNotEqual(command?.toolName, "open_in_obsidian", sentence)
        }
    }

    /// Shown to no local model, served to an MCP client — where it refuses.
    func testTheVerbIsHiddenFromTheLocalModelAndServedOverMCP() {
        var local: Set<String> = []
        for tool in AssistToolRunner.localTools {
            local.insert(tool.name)
        }
        var overMCP: Set<String> = []
        for tool in AssistToolRunner.mcpTools {
            overMCP.insert(tool.name)
        }
        XCTAssertFalse(local.contains("open_in_obsidian"))
        XCTAssertTrue(overMCP.contains("open_in_obsidian"))
        XCTAssertTrue(AssistToolRunner.hiddenFromTheLocalModel.contains("open_in_obsidian"))
    }

    // MARK: - Reading the contract

    private static func family() throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts").appendingPathComponent("assist-cases.json")
        )
        let cases: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(cases["openInObsidian"] as? [String: Any])
    }
}
