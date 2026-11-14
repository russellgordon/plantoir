import XCTest
@testable import QuartzTeachers

/// The two things the Fable sweep of #866 found the contract writer doing
/// without a word: deleting an authored key that `generated.keys` named, and
/// re-sorting a whole file whose only fault was its whitespace. Both tests go
/// through calls that existed before the fix (`AppRulesContract.write(into:)`
/// and `ContractText.encode`), so each is red on the code before it.
@MainActor
final class ContractTextShapeTests: XCTestCase {

    // MARK: - Functions

    /// A `generated.keys` that names an AUTHORED key stops the run, names the
    /// key, and leaves the file as it was. Before the fix the key was deleted
    /// and the run answered as if it had written an ordinary file.
    func testAnAuthoredKeyNamedInGeneratedKeysIsRefusedAndKept() throws {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContractTextShapeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let committedText: String = """
        {
          "generated" : {
            "keys" : [
              "credentialRequests",
              "milestones",
              "linkRules"
            ]
          },
          "linkRules" : {
            "why" : "a rule written by hand"
          },
          "note" : "A test file."
        }

        """
        let url: URL = folder.appendingPathComponent(AppRulesContract.fileName)
        try Data(committedText.utf8).write(to: url)

        let answer: String = AppRulesContract.write(into: folder)

        XCTAssertTrue(answer.hasPrefix("Could not write the app rules"), answer)
        XCTAssertTrue(answer.contains("linkRules"), answer)
        XCTAssertEqual(String(decoding: try Data(contentsOf: url), as: UTF8.self), committedText)
    }

    /// A committed file with CRLF line ends, a blank line between members and
    /// a space after a member's comma keeps its authored keys in the committed
    /// order: only the stray whitespace goes. Before the fix any one of the
    /// three sent the whole file to the sorted encoding.
    func testStrayWhitespaceDoesNotReSortTheFile() throws {
        let committedLines: [String] = [
            "{",
            "  \"zebra\" : {",
            "    \"why\" : \"written first by its author\"",
            "  }, ",
            "",
            "  \"apple\" : [",
            "    \"written second\"",
            "  ]",
            "}",
            "",
        ]
        let committed: Data = Data(committedLines.joined(separator: "\r\n").utf8)
        let value: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: committed) as? [String: Any]
        )

        let written: String = String(
            decoding: try ContractText.encode(value, keepingTheTextOf: committed), as: UTF8.self
        )

        let expected: String = """
        {
          "zebra" : {
            "why" : "written first by its author"
          },
          "apple" : [
            "written second"
          ]
        }

        """
        XCTAssertEqual(written, expected)
    }
}
