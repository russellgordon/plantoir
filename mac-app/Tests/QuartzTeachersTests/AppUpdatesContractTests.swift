import XCTest
@testable import QuartzTeachers

/// `contracts/shared-rules.json` → `appUpdates`, run rather than retyped
/// (#204): the install gate's cases, what a quit does to a prepared update,
/// and every sentence of ours, both ways.
@MainActor
final class AppUpdatesContractTests: XCTestCase {

    // MARK: - The install gate

    func testTheGateIsTheOneTheContractWritesDown() throws {
        let rules: [String: Any] = try AppUpdatesContractTests.appUpdates()
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12, "The case list has shrunk")

        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = try XCTUnwrap(testCase["given"] as? [String: Any], name)
            let expectHeld: Bool = try XCTUnwrap(testCase["expectHeld"] as? Bool, name)

            var publishes: [CourseActivity.PublishRecord] = []
            for pair in given["publishes"] as? [[Any]] ?? [] {
                publishes.append(CourseActivity.PublishRecord(
                    folderPath: "/pretend", courseCode: try XCTUnwrap(pair[0] as? String), sectionNumber: try XCTUnwrap(pair[1] as? Int)
                ))
            }
            var builds: [CourseActivity.PreviewBuildRecord] = []
            for pair in given["previewBuilds"] as? [[Any]] ?? [] {
                builds.append(CourseActivity.PreviewBuildRecord(
                    folderPath: "/pretend", courseCode: try XCTUnwrap(pair[0] as? String), sectionNumber: try XCTUnwrap(pair[1] as? Int)
                ))
            }
            var previews: [PreviewLeases.Lease] = []
            let openCount: Int = given["previewsOpen"] as? Int ?? 0
            PreviewLeases.reset()
            defer {
                PreviewLeases.reset()
            }
            var index: Int = 0
            while index < openCount {
                previews.append(try PreviewLeases.lease(folderPath: "/pretend", courseCode: "ICS3U", sectionNumber: index + 1))
                index += 1
            }
            var copies: [UpdateGate.OtherCopy] = []
            for copy in given["otherCopies"] as? [[String: Any]] ?? [] {
                let kindName: String = try XCTUnwrap(copy["kind"] as? String, name)
                copies.append(UpdateGate.OtherCopy(
                    pid: Int32(try XCTUnwrap(copy["pid"] as? Int)),
                    kind: try XCTUnwrap(UpdateGate.OtherCopy.Kind(rawValue: kindName), "\(name): no kind \(kindName)"),
                    folderPath: "/pretend",
                    courseCode: copy["course"] as? String,
                    sectionNumber: copy["section"] as? Int
                ))
            }
            var leases: [UpdateGate.LeaseSighting] = []
            for lease in given["leases"] as? [[String: Any]] ?? [] {
                leases.append(UpdateGate.LeaseSighting(
                    pid: Int32(try XCTUnwrap(lease["pid"] as? Int)),
                    kind: try XCTUnwrap(lease["kind"] as? String),
                    courseCode: try XCTUnwrap(lease["course"] as? String),
                    folderPath: "/pretend"
                ))
            }

            let underWay: String? = UpdateGate.workUnderWay(
                publishes: publishes, previewBuilds: builds, previews: previews, otherCopies: copies, leases: leases
            )
            XCTAssertEqual(underWay != nil, expectHeld, "\(name): the gate and the contract disagree")
            guard expectHeld, let underWay else {
                continue
            }

            let namedAs: String = try XCTUnwrap(testCase["expectNamedAs"] as? String, name)
            let expected: String
            switch namedAs {
            case "theQuitQuestionsWords":
                var phrase: String? = QuitConfirmation.workUnderWay(publishes: publishes, previews: previews)
                if phrase == nil {
                    phrase = QuitConfirmation.workUnderWay(publishes: [], previews: previews, previewBuilds: builds)
                }
                expected = try XCTUnwrap(phrase, name)
            case "scheduledWork":
                expected = UpdateWording.scheduledWork(
                    course: try XCTUnwrap(testCase["course"] as? String), section: try XCTUnwrap(testCase["section"] as? Int)
                )
            case "scheduledWorkUnnamed":
                expected = UpdateWording.scheduledWorkUnnamed
            case "elsewhereWork":
                expected = UpdateWording.elsewhereWork(course: try XCTUnwrap(testCase["course"] as? String))
            default:
                XCTFail("\(name): the contract names \(namedAs), which this test does not know")
                continue
            }
            XCTAssertEqual(underWay, expected, "\(name): named the wrong work")
        }
    }

    // MARK: - Quitting with an update prepared

    func testWhatAQuitDoesIsTheOneTheContractWritesDown() throws {
        let rules: [String: Any] = try AppUpdatesContractTests.appUpdates()
        let atQuit: [String: Any] = try XCTUnwrap(rules["atQuit"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(atQuit["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        var seen: [String] = []
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = try XCTUnwrap(testCase["given"] as? [String: Any])
            let preparedName: String = try XCTUnwrap(given["preparedUpdate"] as? String)
            let prepared: UpdateGate.PreparedUpdate = try XCTUnwrap(
                UpdateGate.PreparedUpdate(rawValue: preparedName), "\(name): \(preparedName)"
            )
            let work: Bool = try XCTUnwrap(given["workUnderWay"] as? Bool)
            let expected: String = try XCTUnwrap(testCase["expect"] as? String)
            XCTAssertEqual(
                UpdateGate.quitAction(prepared: prepared, workUnderWay: work).rawValue,
                expected,
                "\(name): the quit and the contract disagree"
            )
            seen.append(preparedName)
        }
        for state in ["none", "readyToInstall", "heldForWork", "postponedAtInstall"] {
            XCTAssertTrue(seen.contains(state), "No atQuit case for \(state)")
        }
    }

    func testHeldWorkEndsInAnInstallStraightAway() throws {
        let rules: [String: Any] = try AppUpdatesContractTests.appUpdates()
        XCTAssertEqual(rules["whenHeldWorkEnds"] as? String, "restartStraightAway")
    }

    // MARK: - The sentences

    /// Every sentence in `appUpdates.wording` is the app's, and every one of
    /// the app's is there — both ways, so a sentence added on either side
    /// alone is red.
    func testEverySentenceIsTheContractsBothWays() throws {
        let wording: [String: String] = try AppUpdatesContractTests.wording()
        let ours: [String: String] = AppUpdatesContractTests.ourSentencesAsTemplates()
        var contractKeys: [String] = []
        for key in wording.keys {
            if key != "rule" && key != "machineryCheck" {
                contractKeys.append(key)
            }
        }
        XCTAssertEqual(contractKeys.sorted(), ours.keys.sorted(), "A sentence is on one side only")
        for (key, sentence) in ours {
            XCTAssertEqual(wording[key], sentence, "appUpdates.wording.\(key) and UpdateWording disagree")
        }
    }

    /// Rule 1, with the list the contract itself writes down.
    func testNoSentenceNamesTheMachinery() throws {
        let wording: [String: String] = try AppUpdatesContractTests.wording()
        let check: String = try XCTUnwrap(wording["machineryCheck"])
        let listStart: Range<String.Index> = try XCTUnwrap(check.range(of: "contain:"))
        var banned: [String] = []
        for word in check[listStart.upperBound...].split(separator: ",") {
            banned.append(word.trimmingCharacters(in: CharacterSet(charactersIn: " .")).lowercased())
        }
        XCTAssertGreaterThan(banned.count, 5)
        for (key, sentence) in AppUpdatesContractTests.ourSentencesAsTemplates() {
            for word in banned {
                XCTAssertFalse(sentence.lowercased().contains(word), "\(key) says \(word)")
            }
        }
    }

    // MARK: - Helpers

    /// UpdateWording rendered back into the contract's template form.
    static func ourSentencesAsTemplates() -> [String: String] {
        return [
            "menuItem": UpdateWording.menuItem,
            "heldTitle": UpdateWording.heldTitle(work: "{work}"),
            "scheduledWork": UpdateWording.scheduledWork(course: "{course}", section: 9_999)
                .replacingOccurrences(of: "9999", with: "{section}"),
            "scheduledWorkUnnamed": UpdateWording.scheduledWorkUnnamed,
            "elsewhereWork": UpdateWording.elsewhereWork(course: "{course}"),
            "heldExplanation": UpdateWording.heldExplanation,
            "okButton": UpdateWording.okButton,
            "needsAdministratorTitle": UpdateWording.needsAdministratorTitle,
            "needsAdministratorExplanation": UpdateWording.needsAdministratorExplanation
        ]
    }

    static func appUpdates() throws -> [String: Any] {
        let url: URL = AppUpdatesStartTests.repositoryFile("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["appUpdates"] as? [String: Any], "No appUpdates in shared-rules.json")
    }

    static func wording() throws -> [String: String] {
        let rules: [String: Any] = try appUpdates()
        return try XCTUnwrap(rules["wording"] as? [String: String])
    }
}
