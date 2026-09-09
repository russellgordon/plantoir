import XCTest
@testable import QuartzTeachers

/// Runs `contracts/file-formats.json` — the two files both apps WRITE and the
/// Python then reads.
///
/// Everything else in these contracts describes behaviour. This describes a
/// FORMAT, and the failure mode is different in kind: a behaviour that differs
/// is a bug someone reports, while a format that drifts is a setting the site
/// build silently ignores, or a page published that a teacher held back.
///
/// Both halves have already caused a real one. `SectionAdder` was found
/// writing the OLD frontmatter key on both platforms — a section added through
/// the app was born in a schema everything else had moved off — and it was
/// missed because the TEST agreed with the code. A contract read by both sides
/// is the answer to a test that agrees with the code.
@MainActor
final class FileFormatsContractTests: XCTestCase {

    // MARK: - course_config.json

    /// Every key the contract documents is one this app really reads.
    ///
    /// Not the reverse — the app may read a key the contract has not caught up
    /// with, and that failure is caught by the count check below rather than
    /// by pretending this list is exhaustive.
    func testEveryDocumentedConfigKeyIsOneTheAppReads() throws {
        let section: [String: Any] = try FileFormatsContractTests.section("courseConfigKeys")
        let source: String = try FileFormatsContractTests.readSource(
            "QuartzTeachers/Models/CourseConfiguration.swift"
        )
        for entry in try XCTUnwrap(section["keys"] as? [[String: Any]]) {
            let key: String = try XCTUnwrap(entry["key"] as? String)
            XCTAssertTrue(
                source.contains("\"\(key)\""),
                "contracts/file-formats.json documents \"\(key)\", which CourseConfiguration no longer "
                + "mentions. A key that has been renamed here and not there is a setting the Python "
                + "silently ignores."
            )
        }
    }

    /// And the reverse, as a count: if the app grows a key, this fails and
    /// somebody has to decide whether Windows needs to know about it.
    func testNoConfigKeyHasBeenAddedWithoutTellingWindows() throws {
        let section: [String: Any] = try FileFormatsContractTests.section("courseConfigKeys")
        let documented: Int = try XCTUnwrap(section["keys"] as? [[String: Any]]).count
        let source: String = try FileFormatsContractTests.readSource(
            "QuartzTeachers/Models/CourseConfiguration.swift"
        )

        var found: Set<String> = []
        var search: Substring = source[...]
        while let range = search.range(of: "forKey: \"") {
            let rest: Substring = search[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                found.insert(String(rest[rest.startIndex..<end]))
            }
            search = rest
        }
        // `section_numbers` is read through its own accessor rather than
        // `forKey:`, so it is counted here deliberately.
        found.insert("section_numbers")

        let difference: [String] = found.symmetricDifference(Set(try documentedKeys())).sorted()
        XCTAssertEqual(
            found.count, documented,
            "CourseConfiguration reads \(found.count) keys and the contract documents \(documented). "
            + "The difference: \(difference). "
            + "Add it to contracts/file-formats.json — Windows writes this file too."
        )
    }

    /// The wizard's own answer keys — the second group, which a first draft
    /// of this contract missed entirely because they are written at creation
    /// rather than round-tripped by the settings form.
    func testTheWizardStillWritesItsAnswerKeys() throws {
        let section: [String: Any] = try FileFormatsContractTests.section("courseConfigKeys")
        let group: [String: Any] = try XCTUnwrap(section["wizardAnswerKeys"] as? [String: Any])
        let wizard: String = try FileFormatsContractTests.readSource(
            "QuartzTeachers/Views/Wizard/NewCourseWizardView.swift"
        )
        for entry in try XCTUnwrap(group["keys"] as? [[String: Any]]) {
            let key: String = try XCTUnwrap(entry["key"] as? String)
            XCTAssertTrue(
                wizard.contains("\"\(key)\""),
                "The wizard no longer writes \"\(key)\". setup_course.py reads it as the default for a "
                + "question it would otherwise ASK, so dropping it hands the teacher's choice to the "
                + "Python's own default."
            )
        }
    }

    // MARK: - Frontmatter: who sees a page

    func testVisibilityIsReadAsTheContractSays() throws {
        let section: [String: Any] = try FileFormatsContractTests.section("pageVisibility")
        for testCase in try XCTUnwrap(section["readingCases"] as? [[String: Any]]) {
            let frontmatter: String = try XCTUnwrap(testCase["page"] as? String)
            let page: String = """
            ---
            \(frontmatter)
            ---

            The lesson.
            """
            let visible: Bool = AssistPageVisibility.publishes(
                in: page,
                forSection: testCase["section"] as? Int ?? 1,
                isSectionLocal: try XCTUnwrap(testCase["sectionLocal"] as? Bool)
            )
            XCTAssertEqual(visible, testCase["expectVisible"] as? Bool, frontmatter)
        }
    }

    /// The writing rules, run as data rather than restated here.
    ///
    /// This test used to assert the OPPOSITE — that a page written as `draft:`
    /// kept that key, inverted — in sentences typed into this file. The
    /// contract said migrate, from 2026-09-07; the app kept inverting; and the
    /// suite stayed green for two days because the test agreed with the code
    /// instead of with the contract. Reading `writingCases` is what stops that
    /// happening again: Windows runs the same list.
    func testTheLegacySpellingIsMigratedToTheCurrentOne() throws {
        let section: [String: Any] = try FileFormatsContractTests.section("pageVisibility")
        let group: [String: Any] = try XCTUnwrap(section["writingCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(group["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty, "contracts/file-formats.json carries no writing cases to run")

        for testCase in cases {
            let before: String = try XCTUnwrap(testCase["before"] as? String)
            let why: String = (testCase["why"] as? String) ?? ""
            let result: (text: String, changed: Bool) = AssistPageVisibility.setting(
                published: try XCTUnwrap(testCase["setVisible"] as? Bool),
                in: before,
                forSection: testCase["section"] as? Int ?? 1,
                isSectionLocal: try XCTUnwrap(testCase["sectionLocal"] as? Bool)
            )
            XCTAssertEqual(result.text, try XCTUnwrap(testCase["after"] as? String), why)
            XCTAssertEqual(result.changed, try XCTUnwrap(testCase["expectChanged"] as? Bool), why)
        }
    }

    /// The two properties the case list cannot state as a before-and-after
    /// pair, both of them about a file this app did not write.
    func testMigrationLeavesAWindowsWrittenFileAsItFoundIt() throws {
        // A page saved on Windows carries CRLF. Migrating a line must put the
        // carriage return back, or that one line quietly becomes LF and the
        // teacher's next commit shows a whole-file change.
        let windowsWritten: String = "---\r\ntitle: Day one\r\ndraftSection1: true\r\n---\r\nBody.\r\n"
        let migrated = AssistPageVisibility.setting(
            published: true, in: windowsWritten, forSection: 1, isSectionLocal: false
        )
        XCTAssertTrue(migrated.changed)
        XCTAssertEqual(
            migrated.text,
            "---\r\ntitle: Day one\r\npublishForSection1: true\r\n---\r\nBody.\r\n"
        )

        // An INDENTED key belongs to some other mapping, not to the page. A
        // migration that touched it would change something the teacher never
        // asked about — so the page's own key is added instead.
        let nested: String = "---\nsomething:\n  draft: true\n---\nBody.\n"
        let added = AssistPageVisibility.setting(
            published: false, in: nested, forSection: 1, isSectionLocal: true
        )
        XCTAssertEqual(added.text, "---\npublish: false\nsomething:\n  draft: true\n---\nBody.\n")
    }

    // MARK: - Has this section ever been deployed to where it is going NOW?

    /// The marker is per DESTINATION, and that is the whole point of it.
    ///
    /// A course deployed to Netlify and then switched to Cloudflare has never
    /// been deployed to Cloudflare. Accepting the old marker as proof
    /// schedules the one deploy that will stop at a prompt at half six with
    /// nobody there.
    func testTheFirstDeployMarkerIsReadPerDestination() throws {
        let section: [String: Any] = try FileFormatsContractTests.section("firstDeployMarkers")
        let root: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markers-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        // A course configured for Cloudflare, carrying only a NETLIFY marker.
        let courseURL: URL = root.appendingPathComponent("courses/MCV4U")
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent(".netlify_sites"), withIntermediateDirectories: true
        )
        try "{}".write(
            to: courseURL.appendingPathComponent(".netlify_sites/section1.json"),
            atomically: true, encoding: .utf8
        )
        let values: [String: Any] = ["course_code": "MCV4U", "deploy_target": "cloudflare_pages"]
        try JSONSerialization.data(withJSONObject: values)
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        let course: Course = Course(
            code: "MCV4U",
            directoryURL: courseURL,
            configuration: try CourseConfiguration(
                contentsOf: courseURL.appendingPathComponent("course_config.json")
            )
        )

        XCTAssertFalse(
            DeployCommand.hasDeployedBefore(section: 1, in: course),
            "\((section["why"] as? String) ?? "")"
        )
        XCTAssertEqual(
            DeployCommand.firstDeployMarkerURL(forSection: 1, in: course)?.lastPathComponent,
            "section1.json"
        )
        XCTAssertTrue(
            DeployCommand.firstDeployMarkerURL(forSection: 1, in: course)?.path
                .contains(".cloudflare_sites") ?? false,
            "A Cloudflare course looks for its Cloudflare marker"
        )

        // A folder deploy keeps no marker and counts as always-deployed.
        let folderValues: [String: Any] = [
            "course_code": "MCV4U", "deploy_target": "local_folder", "deploy_folder_path": root.path,
        ]
        try JSONSerialization.data(withJSONObject: folderValues)
            .write(to: courseURL.appendingPathComponent("course_config.json"))
        let toFolder: Course = Course(
            code: "MCV4U",
            directoryURL: courseURL,
            configuration: try CourseConfiguration(
                contentsOf: courseURL.appendingPathComponent("course_config.json")
            )
        )
        XCTAssertNil(DeployCommand.firstDeployMarkerURL(forSection: 1, in: toFolder))
        XCTAssertTrue(DeployCommand.hasDeployedBefore(section: 1, in: toFolder))
    }

    // MARK: - Private

    private func documentedKeys() throws -> [String] {
        let section: [String: Any] = try FileFormatsContractTests.section("courseConfigKeys")
        var keys: [String] = []
        for entry in try XCTUnwrap(section["keys"] as? [[String: Any]]) {
            keys.append(try XCTUnwrap(entry["key"] as? String))
        }
        return keys
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func readSource(_ relativePath: String) throws -> String {
        return try String(
            contentsOf: repositoryRoot().appendingPathComponent("mac-app").appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static func section(_ name: String) throws -> [String: Any] {
        let url: URL = repositoryRoot().appendingPathComponent("contracts/file-formats.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all[name] as? [String: Any], "No \(name) in file-formats.json")
    }
}
