import XCTest
@testable import QuartzTeachers

/// The files in `contracts/` are what the Windows suite tests against, so this
/// asks the only question that matters about them: **are they still true?**
///
/// It regenerates them in memory from the app's own types and compares against
/// what is committed. A sentence changed in `AssistWording` and not regenerated
/// fails HERE, in the same run that changed it, with the command to fix it —
/// rather than three weeks later on a Windows machine, as behaviour that was
/// implemented faithfully from a file that had quietly stopped being true.
///
/// Comparison is of PARSED JSON, deliberately, not of bytes. Whitespace and
/// key order are a formatting argument between two JSON writers; the contract
/// is the content.
@MainActor
final class AssistContractTests: XCTestCase {

    // MARK: - Stored properties

    /// How to put it right, said the same way in every failure here.
    private static let howToFix: String =
        "\n\nThe contract in contracts/ is out of date. Regenerate it:\n"
      + "    Plantoir --write-contracts contracts\n"
      + "…or, from a build tree:\n"
      + "    <DerivedData>/Build/Products/Debug/Plantoir.app/Contents/MacOS/Plantoir "
      + "--write-contracts contracts\n"
      + "Then commit the diff — that diff is how the Windows side finds out."

    // MARK: - Functions

    /// Every sentence in the committed wording file is one the app really says.
    func testTheCommittedWordingIsWhatTheAppSays() throws {
        let committed: [String: Any] = try readContract(named: AssistContract.wordingFileName)
        let generated: [String: Any] = AssistContract.wording()

        let committedWording: [String: String] = try XCTUnwrap(committed["wording"] as? [String: String])
        let generatedWording: [String: String] = try XCTUnwrap(generated["wording"] as? [String: String])

        // Named one at a time. A whole-dictionary assertion prints both
        // dictionaries and leaves you to find the difference by eye.
        for (key, sentence) in generatedWording {
            XCTAssertEqual(
                committedWording[key], sentence,
                "contracts/assist-wording.json disagrees about \"\(key)\"." + AssistContractTests.howToFix
            )
        }
        for key in committedWording.keys where generatedWording[key] == nil {
            XCTFail(
                "contracts/assist-wording.json still carries \"\(key)\", which the app no longer says."
                + AssistContractTests.howToFix
            )
        }
    }

    /// The generated half of the cases file matches the tool surface and the
    /// card shapes as they stand.
    func testTheCommittedCasesMatchTheToolSurface() throws {
        let committed: [String: Any] = try readContract(named: AssistContract.casesFileName)
        let generated: [String: Any] = AssistContract.generatedCases()

        for key in AssistContract.generatedCaseKeys {
            let left: Data = try AssistContract.encode(
                ["value": try XCTUnwrap(generated[key], "Nothing generated for \(key)")]
            )
            let right: Data = try AssistContract.encode(
                ["value": try XCTUnwrap(committed[key], "contracts/assist-cases.json has no \(key)")]
            )
            XCTAssertEqual(
                String(decoding: right, as: UTF8.self), String(decoding: left, as: UTF8.self),
                "contracts/assist-cases.json disagrees about \"\(key)\"." + AssistContractTests.howToFix
            )
        }
    }

    /// The hand-written half is still there.
    ///
    /// This is the failure a careless regeneration produces, and it would
    /// otherwise look like a successful run: the scenarios and the near misses
    /// are the only things in `contracts/` that no code can reconstruct, so
    /// losing them loses the reasoning outright.
    func testTheHandWrittenHalfSurvives() throws {
        let committed: [String: Any] = try readContract(named: AssistContract.casesFileName)

        let scenarios: [String: Any] = try XCTUnwrap(committed["scenarios"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(scenarios["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8, "The scenarios have been thinned out")
        for scenario in cases {
            XCTAssertNotNil(scenario["name"], "A scenario with no name")
            XCTAssertNotNil(scenario["why"], "A scenario with no reason is a scenario that gets deleted")
        }

        let nearMisses: [String: Any] = try XCTUnwrap(committed["nearMisses"] as? [String: Any])
        let phrasings: [String] = try XCTUnwrap(nearMisses["phrasings"] as? [String])
        XCTAssertFalse(phrasings.isEmpty)
    }

    /// Every near miss really is one. The contract tells Windows these must
    /// not match; if one of them started matching here, the contract would be
    /// asking them to enforce something this app does not do.
    func testTheNearMissesDoNotMatch() throws {
        let committed: [String: Any] = try readContract(named: AssistContract.casesFileName)
        let nearMisses: [String: Any] = try XCTUnwrap(committed["nearMisses"] as? [String: Any])
        for phrasing in try XCTUnwrap(nearMisses["phrasings"] as? [String]) {
            XCTAssertNil(
                AssistCardCommand.matching(phrasing),
                "\"\(phrasing)\" is listed as a near miss and is being matched as a card."
            )
        }
    }

    /// And every scenario's `expectReply` names a sentence that exists. The
    /// two files refer to each other by NAME rather than by quoting, which
    /// only helps if the names are checked.
    func testEveryScenarioReplyNamesARealSentence() throws {
        let cases: [String: Any] = try readContract(named: AssistContract.casesFileName)
        let wording: [String: String] = try XCTUnwrap(
            (try readContract(named: AssistContract.wordingFileName))["wording"] as? [String: String]
        )
        let scenarios: [String: Any] = try XCTUnwrap(cases["scenarios"] as? [String: Any])

        for scenario in try XCTUnwrap(scenarios["cases"] as? [[String: Any]]) {
            var named: [String] = []
            if let reply = scenario["expectReply"] as? String {
                named.append(reply)
            }
            for line in (scenario["expectTranscript"] as? [String]) ?? [] {
                named.append(line)
            }
            for reference in named {
                // "assistant: wording.deployWasCancelled" → "deployWasCancelled"
                guard let range = reference.range(of: "wording.") else {
                    continue
                }
                let key: String = String(reference[range.upperBound...])
                XCTAssertNotNil(
                    wording[key],
                    "Scenario \"\(scenario["name"] ?? "?")\" names wording.\(key), which does not exist."
                )
            }
        }
    }

    /// The emitted schemas are the ones a client would really send.
    ///
    /// This is what makes a routing measurement honest: the suite reads these,
    /// so a score cannot be earned against a surface the app does not ship.
    func testTheEmittedSchemasAreWhatAClientWouldSend() throws {
        let committed: [String: Any] = try readContract(named: AssistContract.casesFileName)
        let schemas: [String: Any] = try XCTUnwrap(committed["toolSchemas"] as? [String: Any])

        let local: [[String: Any]] = try XCTUnwrap(schemas["local"] as? [[String: Any]])
        let mcp: [[String: Any]] = try XCTUnwrap(schemas["mcp"] as? [[String: Any]])
        XCTAssertEqual(local.count, AssistToolRunner.localTools.count)
        XCTAssertEqual(mcp.count, AssistToolRunner.mcpTools.count)

        // Name, description and parameters — all three, because the
        // DESCRIPTIONS are the measured part.
        for (index, definition) in AssistToolRunner.localTools.enumerated() {
            let function: [String: Any] = try XCTUnwrap(local[index]["function"] as? [String: Any])
            XCTAssertEqual(function["name"] as? String, definition.name)
            XCTAssertEqual(
                function["description"] as? String, definition.description,
                "\(definition.name): a changed description is a ROUTING change, and the contract must "
                + "carry the words the model is actually shown."
            )
            XCTAssertNotNil(function["parameters"], "\(definition.name) has no parameter schema")
        }
    }

    /// Every departure the contract names is a parameter that really is a
    /// list-shaped string on this surface — and there is at least one.
    ///
    /// The emitted list is derived from `Kind.separatedList`, so this cannot
    /// drift from the declaration. What it CAN do is go silently empty if the
    /// three call sites are changed back to plain `.string`, and an empty list
    /// would read to Windows as "the departures are resolved, delete them",
    /// which is the opposite of true. Hence the count assertion.
    func testTheDeparturesNameEveryListShapedParameter() throws {
        let committed: [String: Any] = try readContract(named: AssistContract.casesFileName)
        let schemas: [String: Any] = try XCTUnwrap(committed["toolSchemas"] as? [String: Any])
        let departures: [String: Any] = try XCTUnwrap(schemas["departures"] as? [String: Any])
        let listShaped: [[String: Any]] = try XCTUnwrap(
            departures["listShapedStringParameters"] as? [[String: Any]]
        )

        XCTAssertFalse(
            listShaped.isEmpty,
            "No list-shaped parameters were emitted. If the separated-list kind has been removed "
            + "this list goes empty, and Windows reads an empty list as \"these departures are "
            + "resolved, delete them\" — the opposite of what it would mean."
        )

        for entry in listShaped {
            let parameter: String = try XCTUnwrap(entry["parameter"] as? String)
            let separator: String = try XCTUnwrap(entry["separator"] as? String)
            XCTAssertFalse(separator.isEmpty, "\(parameter) is list-shaped with no separator")

            let parts: [String] = parameter.components(separatedBy: ".")
            XCTAssertEqual(parts.count, 2, "\(parameter) is not tool.parameter")
            let toolName: String = parts[0]
            let parameterName: String = parts[1]

            var found: Bool = false
            for definition in AssistToolRunner.mcpTools where definition.name == toolName {
                let property: AssistSchemaProperty? = definition.parameters[parameterName]
                XCTAssertNotNil(property, "\(parameter) is named as a departure and does not exist")
                XCTAssertEqual(
                    property?.kind.listSeparator, separator,
                    "\(parameter): the emitted separator is not the declared one"
                )
                XCTAssertEqual(
                    property?.json["type"] as? String, "string",
                    "\(parameter) must still render as a string — a departure that changed the "
                    + "emitted TYPE would be a routing change, not a record of one."
                )
                found = true
            }
            XCTAssertTrue(found, "\(parameter) names a tool this surface does not have")
        }
    }

    /// The `absentHere` claim is true: nothing on this surface is a `preview`
    /// flag, and nothing on it is a boolean at all.
    ///
    /// The contract says both, so both are checked here rather than trusted.
    /// The second is the load-bearing one — a boolean on a router is the shape
    /// that asks the MODEL a question the code should answer.
    func testNothingOnThisSurfaceIsAPreviewFlagOrAnyBoolean() throws {
        var everyTool: [AssistToolDefinition] = []
        for definition in AssistToolRunner.localTools {
            everyTool.append(definition)
        }
        for definition in AssistToolRunner.mcpTools {
            everyTool.append(definition)
        }

        for definition in everyTool {
            for (parameterName, property) in definition.parameters {
                XCTAssertNotEqual(
                    parameterName, "preview",
                    "\(definition.name) has a preview flag. The contract's departures say this "
                    + "surface has none, because every change rebuilds here."
                )
                XCTAssertNotEqual(
                    property.json["type"] as? String, "boolean",
                    "\(definition.name).\(parameterName) is a boolean. The contract records that "
                    + "there is no boolean anywhere on this surface; the last was includeLinked, "
                    + "which asked the model how far a publish should reach."
                )
            }
        }
    }

    // MARK: - Private

    /// The repository's `contracts/` folder, found from this source file's own
    /// path — the test bundle does not carry it, and it must not: the point of
    /// the file is that it is committed and reviewable, not shipped.
    private func readContract(named name: String) throws -> [String: Any] {
        let here: URL = URL(fileURLWithPath: #filePath)
        let repository: URL = here
            .deletingLastPathComponent()   // QuartzTeachersTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac-app
            .deletingLastPathComponent()   // the repository
        let url: URL = repository.appendingPathComponent("contracts").appendingPathComponent(name)
        let data: Data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
