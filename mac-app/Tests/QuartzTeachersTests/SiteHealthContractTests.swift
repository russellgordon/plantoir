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

    /// Parses lines the TOOLCHAIN actually printed.
    ///
    /// The round-trip test above builds its own JSON, so it proves the app can
    /// read the app — it would not catch `section` emitted as a string, a
    /// renamed key, or a changed separator. These examples are captured from
    /// `site_health.announce` and re-checked against it by
    /// `scripts/test_site_health.py`, so the two halves cannot drift apart
    /// without one of the two suites failing.
    func testRealToolchainOutputIsUnderstood() throws {
        let marker: [String: Any] = try XCTUnwrap(siteHealth["marker"] as? [String: Any])
        let examples: [String] = try XCTUnwrap(marker["examples"] as? [String])
        XCTAssertFalse(examples.isEmpty, "the contract carries no example output")

        for example in examples {
            let found: [SiteHealthFinding] = SiteHealthFinding.findings(in: example)
            XCTAssertEqual(found.count, 1, example)
            let finding: SiteHealthFinding = try XCTUnwrap(found.first)
            XCTAssertFalse(finding.name.isEmpty)
            XCTAssertFalse(finding.sentence.isEmpty)
            XCTAssertFalse(finding.detail.isEmpty, "the dialog shows the detail too")
            XCTAssertEqual(finding.course, "ICS3U")
            XCTAssertEqual(finding.section, 1,
                           "section must arrive as a number, not fall back to 0")
        }
    }

    /// The repair lists in the contract must match what the app will actually
    /// offer.
    ///
    /// Nothing read `siteHealth.repair` when it was added, so the lists could
    /// have drifted from `canRepair` silently — a contract section that is
    /// documentation rather than a gate. The `neverOffered` half is the one
    /// that matters: those are the checks a fix would SATISFY without fixing.
    func testTheRepairListsMatchWhatTheAppWillOffer() throws {
        let repair: [String: Any] = try XCTUnwrap(siteHealth["repair"] as? [String: Any])

        let offered: [String] = try XCTUnwrap(
            (repair["offered"] as? [String: Any])?["checks"] as? [String]
        )
        let neverOffered: [String] = try XCTUnwrap(
            (repair["neverOffered"] as? [String: Any])?["checks"] as? [String]
        )

        for name in offered {
            XCTAssertTrue(
                SiteHealthRepair.canRepair(sample(named: name, fixable: true)),
                "\(name) is listed as repairable and the app will not offer it"
            )
        }
        for name in neverOffered {
            XCTAssertFalse(
                SiteHealthRepair.canRepair(sample(named: name, fixable: true)),
                "\(name) must never be offered a fix, even when the toolchain "
                + "marks it fixable — a fix that satisfies the check without "
                + "restoring the feature is worse than none"
            )
        }

        // And between them they must account for every check, or a new one
        // silently belongs to neither list.
        let checks: [[String: Any]] = try XCTUnwrap(siteHealth["checks"] as? [[String: Any]])
        var everyName: [String] = []
        for check in checks {
            everyName.append(try XCTUnwrap(check["name"] as? String))
        }
        XCTAssertEqual(
            Set(offered).union(Set(neverOffered)), Set(everyName),
            "every check must be in exactly one of the repair lists"
        )
    }

    private func sample(named name: String, fixable: Bool) -> SiteHealthFinding {
        return SiteHealthFinding(
            name: name, sentence: "s", detail: "d",
            fixable: fixable, course: "ICS3U", section: 1
        )
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
