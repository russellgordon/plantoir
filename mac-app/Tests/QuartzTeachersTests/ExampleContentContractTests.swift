import XCTest
@testable import QuartzTeachers

/// Runs `contracts/example-content.json` against every payload in
/// `support/example_content/`.
///
/// Neither app writes these, and both apps OFFER them — the wizard asks no
/// structure questions when a payload exists, because the manifest IS the
/// course's entire structure. So a manifest that names a folder which is not
/// there does not fail: the course installs without that part of itself, and
/// the teacher finds out weeks later.
///
/// Thirty-seven payloads is too many to check by eye, and adding a code is
/// deliberately pure content — no code review is involved. This is the review.
final class ExampleContentContractTests: XCTestCase {

    // MARK: - Every payload, against the documented shape

    func testEveryPayloadMatchesTheContract() throws {
        let contract: [String: Any] = try ExampleContentContractTests.contract()
        let required: [String] = try ExampleContentContractTests.requiredKeys(in: contract)
        let payloads: URL = ExampleContentContractTests.repositoryRoot()
            .appendingPathComponent("support/example_content")

        var checked: Int = 0
        for code in try FileManager.default.contentsOfDirectory(atPath: payloads.path).sorted()
        where !code.hasPrefix(".") {
            let payload: URL = payloads.appendingPathComponent(code)
            let manifestURL: URL = payload.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                XCTFail("\(code) has no manifest.json, so nothing will ever offer it. Either finish it "
                        + "or take the folder out — a half-payload is invisible to the wizard and "
                        + "confusing to everyone else.")
                continue
            }
            checked += 1

            let manifest: [String: Any] = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: try Data(contentsOf: manifestURL)) as? [String: Any],
                "\(code)/manifest.json is not a JSON object"
            )
            for key in required {
                XCTAssertNotNil(manifest[key], "\(code)/manifest.json is missing \"\(key)\"")
            }

            // The two trees the installer copies from.
            for tree in ["shared", "per_section"] {
                var isDirectory: ObjCBool = false
                let exists: Bool = FileManager.default.fileExists(
                    atPath: payload.appendingPathComponent(tree).path, isDirectory: &isDirectory
                )
                XCTAssertTrue(exists && isDirectory.boolValue, "\(code) has no \(tree)/ to install from")
            }

            // The direction that fails SILENTLY. `setup_course.py` filters
            // the copy by the manifest's lists (`top_level_allowed`), so
            // anything sitting in the payload that the manifest does not name
            // is never installed: the work is in the repository, looks
            // finished, and reaches no teacher.
            //
            // The opposite direction is NOT an error, and a first draft of
            // this test asserted it and failed against nine payloads: a
            // manifest may name "Private Notes.md" without shipping one,
            // because the ordinary course scaffolding creates it empty, which
            // is what a private notes page should be.
            try assertNothingIsStranded(
                in: payload, tree: "shared", manifest: manifest,
                keys: ["shared_folders", "shared_files"], code: code
            )
            try assertNothingIsStranded(
                in: payload, tree: "per_section", manifest: manifest,
                keys: ["per_section_folders", "per_section_files"], code: code
            )

            // A named curriculum folder must be one of the folders it ships.
            if let curriculum = manifest["curriculum_folder"] as? String, !curriculum.isEmpty {
                let shared: [String] = manifest["shared_folders"] as? [String] ?? []
                XCTAssertTrue(
                    shared.contains(curriculum),
                    "\(code) names \"\(curriculum)\" as its curriculum folder and does not ship it in "
                    + "shared_folders, so the installer has nothing to date or link."
                )
            }
        }

        XCTAssertGreaterThanOrEqual(checked, 30, "Far fewer payloads than expected — is the path right?")
    }

    /// The default that bites: a course meeting DAILY must say so, or the
    /// installer dates its classes every other weekday.
    func testADailyCourseSaysSoRatherThanTakingTheDefault() throws {
        let contract: [String: Any] = try ExampleContentContractTests.contract()
        var documentedDefault: Int = 0
        for key in try XCTUnwrap(contract["manifestKeys"] as? [[String: Any]])
        where key["key"] as? String == "class_weekday_step" {
            documentedDefault = try XCTUnwrap(key["default"] as? Int)
        }

        let python: String = try String(
            contentsOf: ExampleContentContractTests.repositoryRoot()
                .appendingPathComponent("scripts/setup_course.py"),
            encoding: .utf8
        )
        XCTAssertTrue(
            python.contains("DEFAULT_CLASS_WEEKDAY_STEP = \(documentedDefault)"),
            "The contract says the default weekday step is \(documentedDefault) and setup_course.py no "
            + "longer agrees. Every payload that relies on the default would silently re-date its classes."
        )
    }

    // MARK: - Sentinels, not dates

    /// Every payload's class pages carry a sentinel rather than a literal
    /// date. The failure this catches is invisible rather than loud: the
    /// course installs, the pages open, and every class claims a date from
    /// whenever the payload happened to be authored.
    func testNoPayloadShipsAHardCodedClassDate() throws {
        let payloads: URL = ExampleContentContractTests.repositoryRoot()
            .appendingPathComponent("support/example_content")
        let sentinel: String = "__CREATED"

        for code in try FileManager.default.contentsOfDirectory(atPath: payloads.path).sorted()
        where !code.hasPrefix(".") {
            let classes: URL = payloads.appendingPathComponent(code)
                .appendingPathComponent("per_section/All Classes")
            guard let pages = try? FileManager.default.contentsOfDirectory(atPath: classes.path) else {
                continue
            }
            for page in pages where page.hasSuffix(".md") {
                let text: String = try String(
                    contentsOf: classes.appendingPathComponent(page), encoding: .utf8
                )
                guard let created = text.range(of: "created:") else {
                    continue
                }
                let line: String = String(text[created.upperBound...].prefix(40))
                XCTAssertTrue(
                    line.contains(sentinel),
                    "\(code)/per_section/All Classes/\(page) has a literal created date (\(line.trimmingCharacters(in: .whitespacesAndNewlines))). "
                    + "It must carry a sentinel, or every teacher who installs this course gets classes "
                    + "dated from whenever the payload was written."
                )
            }
        }
    }

    // MARK: - Private

    /// Nothing in the payload tree is missing from the manifest's lists.
    private func assertNothingIsStranded(
        in payload: URL, tree: String, manifest: [String: Any], keys: [String], code: String
    ) throws {
        var allowed: Set<String> = []
        for key in keys {
            for named in manifest[key] as? [String] ?? [] {
                allowed.insert(named)
            }
        }
        let treeURL: URL = payload.appendingPathComponent(tree)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: treeURL.path) else {
            return
        }
        // `index.md` is always installed without being named — it is the
        // landing page of the folder it sits in, and setup_course.py says so
        // in its own words. The contract records it as an exception rather
        // than this test knowing it privately.
        var exceptions: Set<String> = []
        for rule in try ExampleContentContractTests.rules() {
            for exception in rule["exceptions"] as? [String] ?? [] {
                exceptions.insert(exception)
            }
        }

        for entry in entries where !entry.hasPrefix(".") && !exceptions.contains(entry) {
            XCTAssertTrue(
                allowed.contains(entry),
                "\(code)/\(tree)/\(entry) is in the payload and the manifest never names it, so "
                + "setup_course.py filters it out and no teacher ever sees it. Add it to the manifest, "
                + "or take it out of the payload."
            )
        }
    }

    private static func requiredKeys(in contract: [String: Any]) throws -> [String] {
        var required: [String] = []
        for key in try XCTUnwrap(contract["manifestKeys"] as? [[String: Any]])
        where key["required"] as? Bool == true {
            required.append(try XCTUnwrap(key["key"] as? String))
        }
        return required
    }

    // MARK: - The jurisdiction, which two languages derive the same way

    /// `jurisdiction` and `jurisdiction_name` are declared in the contract
    /// and read by BOTH `ExampleContentCatalog.jurisdictionName` here and
    /// `jurisdiction_name()` in `setup_course.py`. Two implementations of
    /// one rule drift the first time a third province appears, so each is
    /// pinned to the contract's own words; this is the mac's half.
    @MainActor
    func testTheJurisdictionIsDerivedTheWayTheContractSays() throws {
        let contract: [String: Any] = try ExampleContentContractTests.contract()
        let keys: [[String: Any]] = try XCTUnwrap(contract["manifestKeys"] as? [[String: Any]])
        var declared: [String: [String: Any]] = [:]
        for entry in keys {
            if let name = entry["key"] as? String {
                declared[name] = entry
            }
        }
        let jurisdiction: [String: Any] = try XCTUnwrap(
            declared["jurisdiction"],
            "The contract no longer declares `jurisdiction`, so nothing pins the two "
            + "implementations of it together."
        )
        XCTAssertNotNil(declared["jurisdiction_name"])
        XCTAssertEqual(jurisdiction["default"] as? String, "Ontario")
        let why: String = try XCTUnwrap(jurisdiction["why"] as? String)

        // The mapping, exactly as the contract states it.
        XCTAssertTrue(why.contains("\"BC\" to \"British Columbia\""))
        XCTAssertTrue(why.contains("an absent key to \"Ontario\""))

        // …and the app's own answers, against the real payloads.
        XCTAssertEqual(ExampleContentCatalog.jurisdictionName(forCode: "MCMPR11"),
                       "British Columbia")
        XCTAssertEqual(ExampleContentCatalog.jurisdictionName(forCode: "ICS4U"), "Ontario")
        XCTAssertEqual(ExampleContentCatalog.jurisdictionName(forCode: "ZZZ9Z"), "Ontario",
                       "A code with no payload at all still has to read as English on a "
                       + "toggle the teacher can see.")
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func rules() throws -> [[String: Any]] {
        return (try contract())["rules"] as? [[String: Any]] ?? []
    }

    private static func contract() throws -> [String: Any] {
        let url: URL = repositoryRoot().appendingPathComponent("contracts/example-content.json")
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
    }
}
