import XCTest
@testable import QuartzTeachers

/// One description per tool, pinned in the contract (#114).
///
/// **Why a hand-written copy is checked rather than the generated one.**
/// `toolSchemas` in the same file is a READOUT of the Swift: edit a measured
/// description, regenerate, and it agrees with itself and stays green — while
/// the only thing that goes red is the Windows suite, weeks later. That is how
/// #114 was found (28 of 32 descriptions differing by 2026-09-26).
/// `toolDescriptions` is written by hand, so an edit to a description here
/// fails HERE, in the run that made it, and says to measure first.
@MainActor
final class AssistToolDescriptionContractTests: XCTestCase {

    // MARK: - Functions

    /// Every tool the MCP server serves has its description in the contract,
    /// byte for byte — and the contract names no tool the mac does not serve,
    /// except the ones it says are another platform's alone.
    func testEveryServedToolsDescriptionIsTheContractsOwn() throws {
        let pinned: [String: Any] = try AssistToolDescriptionContractTests.pinned()
        let descriptions: [String: String] = try XCTUnwrap(pinned["descriptions"] as? [String: String])
        let made = try AssistFixture.makeRunner(surface: .mcp)
        defer { try? FileManager.default.removeItem(at: made.root) }

        var served: Set<String> = []
        for tool in made.runner.mcpDefinitions {
            served.insert(tool.name)
            let written: String? = descriptions[tool.name]
            XCTAssertNotNil(written, "\(tool.name) is served with no description in toolDescriptions")
            XCTAssertEqual(
                tool.description, written,
                "\(tool.name)'s description is not the contract's. A description is a routing change: "
                + "measure it (doc 10, 'One description per tool'), then change both."
            )
        }
        XCTAssertEqual(served.count, 32, "a tool was added or removed; toolDescriptions and doc 10 count them")

        let notShared: [String: Any] = try XCTUnwrap(pinned["notShared"] as? [String: Any])
        let windowsOnly: [String] = try XCTUnwrap(notShared["windows"] as? [String])
        for name in descriptions.keys {
            XCTAssertTrue(served.contains(name), "toolDescriptions pins \(name), which the mac does not serve")
        }
        for name in windowsOnly {
            XCTAssertFalse(served.contains(name), "\(name) is listed as Windows' alone and the mac serves it")
            XCTAssertNil(descriptions[name], "\(name) is listed as not shared and also pinned")
        }
    }

    /// The local model is shown the SAME text — only the example course is
    /// the window's — never a shortened copy (arm C of the measurement: the
    /// shortened text cost 40 control trials on teachers-say).
    func testTheLocalModelIsShownTheSameDescriptionAsTheServer() throws {
        let descriptions: [String: String] = try XCTUnwrap(
            try AssistToolDescriptionContractTests.pinned()["descriptions"] as? [String: String]
        )
        let made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        XCTAssertEqual(made.runner.definitions.count, 13)
        for tool in made.runner.definitions {
            let written: String = try XCTUnwrap(descriptions[tool.name], tool.name)
            XCTAssertEqual(tool.namingTheRealCourse("ICS3U").description, written, tool.name)
            XCTAssertEqual(
                tool.namingTheRealCourse("MCV4U").description,
                written.replacingOccurrences(of: "ICS3U", with: "MCV4U"),
                tool.name
            )
        }
    }

    /// A departure is kept only as a MEASURED one: numbers and an issue, or
    /// it is an argued sentence (Russell on #114, 2026-09-10). Vacuous on the
    /// mac today; it is here so an entry proposed from Windows cannot be a
    /// bare opinion.
    func testNoDepartureIsWithoutItsNumbers() throws {
        let pinned: [String: Any] = try AssistToolDescriptionContractTests.pinned()
        let departures: [[String: Any]] = try XCTUnwrap(pinned["measuredDepartures"] as? [[String: Any]])
        let descriptions: [String: String] = try XCTUnwrap(pinned["descriptions"] as? [String: String])
        for departure in departures {
            let tool: String = (departure["tool"] as? String) ?? ""
            XCTAssertNotNil(descriptions[tool], "a departure for \(tool), which is not a pinned tool")
            XCTAssertFalse(((departure["platform"] as? String) ?? "").isEmpty, "\(tool): no platform")
            XCTAssertFalse(((departure["description"] as? String) ?? "").isEmpty, "\(tool): no description")
            let measured: String = ((departure["measured"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(measured.isEmpty, "\(tool)'s departure carries no measurement")
            XCTAssertNotNil(departure["issue"] as? Int, "\(tool)'s departure names no issue")
            XCTAssertNotEqual(
                departure["platform"] as? String, "mac",
                "the mac serves the pinned text; a mac departure is a change to the pin"
            )
        }
        XCTAssertNotNil(pinned["rule"] as? String)
        XCTAssertNotNil(pinned["note"] as? String)
    }

    // MARK: - Helpers

    private static func pinned() throws -> [String: Any] {
        let repository: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data: Data = try Data(
            contentsOf: repository.appendingPathComponent("contracts")
                .appendingPathComponent(AssistContract.casesFileName)
        )
        let cases: [String: Any] = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(
            cases["toolDescriptions"] as? [String: Any], "contracts/assist-cases.json has no toolDescriptions"
        )
    }
}
