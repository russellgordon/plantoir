import XCTest
@testable import QuartzTeachers

/// `contracts/shared-rules.json` → `publishPlanNaming` (#425, adopted from
/// Windows' parity bundle 10): publishing by name finds pages by FILE name,
/// asks rather than guesses when a name fits two, and names a page whose
/// title another page shares with its folder.
@MainActor
final class PublishPlanNamingContractTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL?

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        previousTrail = ActivityTrail.store
    }

    override func tearDown() async throws {
        ActivityTrail.store = previousTrail
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    // MARK: - Helpers

    func folderURL(_ folder: String, in course: Course) -> URL {
        if folder == "classes" {
            return ClassPages.folderURL(forSection: 1, in: course)
        }
        return course.directoryURL.appendingPathComponent(folder)
    }

    func folderWithinCourse(_ folder: String) -> String {
        if folder == "classes" {
            return "section1/All Classes"
        }
        return folder
    }

    // MARK: - Tests

    /// MUST FAIL before #425: "Notes" was published as whichever file came
    /// first in path order, and the plan named neither page with its folder.
    func testPublishPlanNamingIsWhatTheContractSays() async throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["publishPlanNaming"])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)

        var ran: Int = 0
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            let made: AssistFixture.Made = try AssistFixture.makeRunner()
            if let root {
                try? FileManager.default.removeItem(at: root)
            }
            root = made.root
            ActivityTrail.store = ProblemReportStore(folderURL: made.root.appendingPathComponent("trail"))

            var urls: [String: URL] = [:]
            var before: [String: Data] = [:]
            for page in try XCTUnwrap(item["pages"] as? [[String: Any]], name) {
                let file: String = try XCTUnwrap(page["file"] as? String, name)
                let folder: String = try XCTUnwrap(page["folder"] as? String, name)
                let shownAs: String = page["shownAs"] as? String ?? file
                let directory: URL = folderURL(folder, in: made.course)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url: URL = directory.appendingPathComponent(file + ".md")
                let text: String = "---\ntitle: \(shownAs)\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400\n---\n\n\(file)\n"
                try text.write(to: url, atomically: true, encoding: .utf8)
                let key: String = folderWithinCourse(folder) + "/" + file
                urls[key] = url
                before[key] = try Data(contentsOf: url)
            }
            // The fixture's course was read before these pages existed.
            let fresh: AssistFixture.Made = made

            let asked: String = try XCTUnwrap(item["asked"] as? String, name)
            let argument: String = try XCTUnwrap(item["pagesArgument"] as? String, name)
            let outcome: AssistToolOutcome = await AssistFixture.run(asked, with: ["pages": argument], on: fresh.runner)
            let expect: [String: Any] = try XCTUnwrap(item["expect"] as? [String: Any], name)

            var written: [String] = []
            for (key, url) in urls {
                if try Data(contentsOf: url) != before[key] {
                    written.append(key)
                }
            }
            written.sort()
            XCTAssertEqual(written, try XCTUnwrap(expect["written"] as? [String], name), "\(name): \(outcome.detail)")

            if try XCTUnwrap(expect["asks"] as? Bool, name) {
                let page: String = try XCTUnwrap(expect["name"] as? String, name)
                var wanted: [String] = [
                    AssistWording.morePagesThanOneAreCalled(page: page, course: "ICS3U", section: "1"),
                ]
                for line in try XCTUnwrap(expect["lines"] as? [String], name) {
                    wanted.append(line)
                }
                XCTAssertEqual(outcome.detail, wanted.joined(separator: "\n"), name)
            } else {
                for shown in try XCTUnwrap(expect["planNames"] as? [String], name) {
                    XCTAssertTrue(outcome.detail.contains(shown + " will become visible"), "\(name): \(outcome.detail)")
                }
            }
            ran += 1
        }
        XCTAssertEqual(ran, cases.count)
    }

    /// The question's list, given back line by line, fits one page each —
    /// the "name at the end" the sentence points at really is askable.
    func testEveryNameTheQuestionOffersFitsOnePage() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        root = made.root
        for folder in ["Concepts", "classes"] {
            let directory: URL = folderURL(folder, in: made.course)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "---\ntitle: Notes\npublish: false\n---\n\nx\n".write(
                to: directory.appendingPathComponent("Notes.md"), atomically: true, encoding: .utf8
            )
        }
        let asked: AssistToolOutcome = await AssistFixture.run("plan_publish_pages", with: ["pages": "Notes"], on: made.runner)
        var offered: [String] = []
        for line in asked.detail.components(separatedBy: "\n") where line.hasPrefix("• ") {
            if let dash = line.range(of: " — ") {
                offered.append(String(line[dash.upperBound...]))
            }
        }
        XCTAssertEqual(offered.count, 2, asked.detail)
        for name in offered {
            let planned: AssistToolOutcome = await AssistFixture.run("plan_publish_pages", with: ["pages": name], on: made.runner)
            XCTAssertTrue(planned.detail.contains("will become visible"), "\(name): \(planned.detail)")
            XCTAssertFalse(planned.detail.contains("More than one page"), "\(name): \(planned.detail)")
        }
    }
}
