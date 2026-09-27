import XCTest
@testable import QuartzTeachers

/// Getting the website builder ready in the background (bundle B):
/// `contracts/app-rules.json` → `builderWarmUp`, run against the app's own
/// decision and words. The launchers' half — one at a time, and
/// `--prepare-builder` doing only that — is `scripts/test_getting_ready_turn.py`.
final class BuilderWarmUpTests: XCTestCase {

    // MARK: - Functions

    private static func rules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/app-rules.json")
        let whole: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(whole["builderWarmUp"] as? [String: Any])
    }

    private static func repositoryFile(_ name: String) throws -> String {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// `builderWarmUp.startsWhen.cases` through `BuilderWarmUp.decide`, and
    /// whether the trail hears about it.
    func testEveryCaseDecidesAsTheContractSays() throws {
        let startsWhen: [String: Any] = try XCTUnwrap(try BuilderWarmUpTests.rules()["startsWhen"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(startsWhen["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        for oneCase in cases {
            let name: String = try XCTUnwrap(oneCase["name"] as? String)
            let facts: [String: Any] = try XCTUnwrap(oneCase["facts"] as? [String: Any], name)
            let network: BuilderWarmUp.NetworkState = try XCTUnwrap(
                BuilderWarmUp.NetworkState(rawValue: try XCTUnwrap(facts["network"] as? String, name)), name
            )
            let decision: BuilderWarmUp.Decision = BuilderWarmUp.decide(BuilderWarmUp.Facts(
                isAnAppLaunch: try XCTUnwrap(facts["isAnAppLaunch"] as? Bool, name),
                carriesTheRecipe: try XCTUnwrap(facts["carriesTheRecipe"] as? Bool, name),
                readyForThisRecipe: try XCTUnwrap(facts["readyForThisRecipe"] as? Bool, name),
                network: network
            ))
            let expected: String = try XCTUnwrap(oneCase["expect"] as? String, name)
            let trail: String? = oneCase["expectTrail"] as? String
            switch decision {
            case .start:
                XCTAssertEqual(expected, "start", name)
                XCTAssertEqual(trail, ActivityTrail.Event.builderWarmUpStarted.rawValue, name)
            case .skip(_, let noteOnTheTrail):
                XCTAssertEqual(expected, "skip", name)
                if noteOnTheTrail {
                    XCTAssertEqual(trail, ActivityTrail.Event.builderWarmUpSkipped.rawValue, name)
                } else {
                    XCTAssertNil(trail, name)
                }
            }
        }
    }

    /// The status line is the contract's, and the waiting line the launchers
    /// print is the contract's too — and neither names the machinery.
    func testTheWordsAreTheContractsAndPlain() throws {
        let wording: [String: Any] = try XCTUnwrap(try BuilderWarmUpTests.rules()["wording"] as? [String: Any])
        XCTAssertEqual(BuilderWarmUp.statusLine, try XCTUnwrap(wording["statusLine"] as? String))
        let waiting: String = try XCTUnwrap(wording["waitingLine"] as? String)
        for launcher in ["setup.sh", "preview.sh", "deploy.sh"] {
            XCTAssertTrue(try BuilderWarmUpTests.repositoryFile(launcher).contains("echo \"\(waiting)\""), launcher)
        }
        // The waiting line carries the words the progress bar matches.
        XCTAssertTrue(waiting.contains("Building your website builder"))
        let forbidden: [String] = [
            "docker", "container", "colima", "image", "script", "toolchain", "virtual machine", "vm ",
        ]
        for sentence in [BuilderWarmUp.statusLine, waiting] {
            for word in forbidden {
                XCTAssertFalse(sentence.lowercased().contains(word), "\(sentence) says \(word)")
            }
        }
    }

    /// The launcher's flag and its last line are the ones the app runs and
    /// reads.
    func testTheLauncherFlagAndReadyLineAgree() throws {
        let rules: [String: Any] = try BuilderWarmUpTests.rules()
        XCTAssertEqual(BuilderWarmUp.readyLinePrefix, try XCTUnwrap(rules["readyLine"] as? String))
        XCTAssertEqual(BuilderWarmUp.tagLinePrefix, try XCTUnwrap(rules["tagLine"] as? String))
        let setup: String = try BuilderWarmUpTests.repositoryFile("setup.sh")
        XCTAssertTrue(setup.contains("\(BuilderWarmUp.launcherFlag)) PREPARE_BUILDER=1"))
        XCTAssertTrue(setup.contains("echo \"\(BuilderWarmUp.readyLinePrefix)${IMAGE}\""))
        XCTAssertTrue(setup.contains("\(BuilderWarmUp.tagFlag)) BUILDER_TAG_ONLY=1"))
        XCTAssertTrue(setup.contains("echo \"\(BuilderWarmUp.tagLinePrefix)${IMAGE}\""))
        XCTAssertEqual(
            BuilderWarmUp.value(after: BuilderWarmUp.tagLinePrefix, in: "noise\nBUILDER_TAG=teaching-quartz:src-1\n"),
            "teaching-quartz:src-1"
        )
        XCTAssertTrue(BuilderWarmUp.sawTheReadyLine(in: "🧱 Building…\nBUILDER_READY=teaching-quartz:src-1234abcd\n"))
        XCTAssertFalse(BuilderWarmUp.sawTheReadyLine(in: "❌ Could not build the website builder.\n"))
        XCTAssertFalse(BuilderWarmUp.sawTheReadyLine(in: "echo BUILDER_READY=\n"))
    }

    /// Only the builder a finished run wrote down counts as ready, and it is
    /// keyed on the recipe's name, not the app's version (review N2).
    func testTheRecordIsReadForThisRecipeOnly() throws {
        let scratch: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("warm-up-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let record: URL = BuilderWarmUp.recordURL(inHomeFolder: scratch)
        XCTAssertFalse(BuilderWarmUp.isReady(forRecipe: "teaching-quartz:src-1234abcd", recordURL: record))
        try FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "teaching-quartz:src-1234abcd\n".write(to: record, atomically: true, encoding: .utf8)
        XCTAssertTrue(BuilderWarmUp.isReady(forRecipe: "teaching-quartz:src-1234abcd", recordURL: record))
        XCTAssertFalse(BuilderWarmUp.isReady(forRecipe: "teaching-quartz:src-99999999", recordURL: record))
        XCTAssertFalse(BuilderWarmUp.isReady(forRecipe: "", recordURL: record), "an unknown recipe is never ready")
    }

    /// Never under the test suite, whatever the arguments say.
    @MainActor
    func testTheSuiteIsNeverAnAppLaunch() {
        XCTAssertFalse(BuilderWarmUp.isAnAppLaunch(arguments: ["Plantoir"]))
    }

    /// Its folder sits beside the helper programs, inside Plantoir's own
    /// Application Support, and in the home folder the VM can see.
    func testItsFolderIsPlantoirsOwn() {
        let home: URL = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(
            BuilderWarmUp.folder(inHomeFolder: home).path,
            "/Users/someone/Library/Application Support/Plantoir/getting-ready"
        )
    }
}
