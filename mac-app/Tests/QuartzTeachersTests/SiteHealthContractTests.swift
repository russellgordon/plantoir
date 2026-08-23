import XCTest
@testable import QuartzTeachers

/// The site-health contract, run against this app's own reading of it.
///
/// Without this the contract's `siteHealth` section was exercised only by the
/// Python that WRITES those lines — so the marker prefix and the wording were
/// unpinned across exactly the boundary the contract exists to protect. A
/// toolchain that changed its prefix would have gone on printing findings that
/// neither app could see, and nothing would have failed.
@MainActor
final class SiteHealthContractTests: XCTestCase {

    // MARK: - Stored properties

    private var siteHealth: [String: Any] = [:]

    // MARK: - Functions

    override func setUpWithError() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        siteHealth = try XCTUnwrap(all["siteHealth"] as? [String: Any])
    }

    func testTheMarkerPrefixMatchesTheContract() throws {
        let marker: [String: Any] = try XCTUnwrap(siteHealth["marker"] as? [String: Any])
        let prefix: String = try XCTUnwrap(marker["prefix"] as? String)
        XCTAssertEqual(SiteHealthFinding.markerPrefix, prefix,
                       "the app would stop seeing findings the toolchain still prints")
    }

    /// Every sentence in the contract must survive the round trip the real
    /// path takes — printed as a marker line, read back by the app — with its
    /// placeholders filled in and nothing left showing.
    func testEveryContractSentenceSurvivesTheRoundTrip() throws {
        let checks: [[String: Any]] = try XCTUnwrap(siteHealth["checks"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(checks.count, 5, "the contract lost checks")

        for check in checks {
            let name: String = try XCTUnwrap(check["name"] as? String)
            let sentence: String = try XCTUnwrap(check["sentence"] as? String)
                .replacingOccurrences(of: "{course}", with: "ICS3U")
                .replacingOccurrences(of: "{section}", with: "1")
            let detail: String = try XCTUnwrap(check["detail"] as? String)
            let fixable: Bool = try XCTUnwrap(check["fixable"] as? Bool)

            let payload: [String: Any] = [
                "name": name, "sentence": sentence, "detail": detail,
                "fixable": fixable, "course": "ICS3U", "section": 1,
            ]
            let data: Data = try JSONSerialization.data(withJSONObject: payload)
            let line: String = SiteHealthFinding.markerPrefix + " "
                + (String(data: data, encoding: .utf8) ?? "")

            let found: [SiteHealthFinding] = SiteHealthFinding.findings(in: line)
            XCTAssertEqual(found.count, 1, name)
            XCTAssertEqual(found.first?.name, name)
            XCTAssertEqual(found.first?.sentence, sentence, name)
            XCTAssertEqual(found.first?.fixable, fixable, name)
        }
    }

    /// Rule 1: the interface never names the machinery. These sentences are
    /// shown to a teacher verbatim — in a dialog, and in the assistant's
    /// answer — so a stray "container" or "script" would reach them directly.
    func testNoCheckNamesTheMachinery() throws {
        let checks: [[String: Any]] = try XCTUnwrap(siteHealth["checks"] as? [[String: Any]])
        let forbidden: [String] = [
            "toolchain", "script", "docker", "container", "wsl", "python",
            "json", "stdout", "quartz", "repository", "config",
        ]
        for check in checks {
            let name: String = (check["name"] as? String) ?? "unnamed"
            let shown: String = ((check["sentence"] as? String) ?? "")
                + " " + ((check["detail"] as? String) ?? "")
            for word in forbidden {
                XCTAssertFalse(
                    shown.lowercased().contains(word),
                    "\(name) says \"\(word)\" to a teacher"
                )
            }
        }
    }

    /// The rule that must not be quietly softened later: a scheduled deploy
    /// publishes anyway. A slightly inaccurate map is a paper cut; a site
    /// update a teacher was counting on that silently did not happen is not.
    func testTheScheduledDeployRuleIsStillWrittenDown() throws {
        let rule: String = try XCTUnwrap(siteHealth["scheduledDeployPublishesAnyway"] as? String)
        XCTAssertTrue(rule.lowercased().contains("never refuses"), rule)
    }
}
