import XCTest
@testable import QuartzTeachers

/// What goes in front of a trail line about one course (#879): the course
/// and section when a section was named, the course alone when none was,
/// and never "ICS3U/0", a section that does not exist.
///
/// The cases are `contracts/shared-rules.json` → `activityTrail.lineShape.
/// placeCases`, read rather than retyped, so Windows runs the same ones.
@MainActor
final class ActivityTrailPlaceTests: XCTestCase {

    // MARK: - Functions

    /// Every case in the contract, through the one function every line about
    /// a course goes through.
    func testEveryPlaceCaseIsWhatTheContractSays() throws {
        let trail: [String: Any] = try SharedRulesContractTests.section("activityTrail")
        let lineShape: [String: Any] = try XCTUnwrap(trail["lineShape"] as? [String: Any])
        let placeCases: [String: Any] = try XCTUnwrap(lineShape["placeCases"] as? [String: Any])
        let cases: [[String: Any]] = try XCTUnwrap(placeCases["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 4)
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let course: String = try XCTUnwrap(testCase["course"] as? String, name)
            let section: Int = try XCTUnwrap(testCase["section"] as? Int, name)
            let place: String = try XCTUnwrap(testCase["place"] as? String, name)
            XCTAssertEqual(ActivityTrail.place(course: course, section: section), place, name)
        }
    }

    /// The fault as it was met: an outside assistant's change that named no
    /// section, declined while the course was being built elsewhere, written
    /// through `WorkLeaseRegistry.noteDeclined` into a scratch trail. The
    /// line starts with the course alone and says "the course".
    func testADeclineThatNamedNoSectionNamesTheCourseAlone() throws {
        let scratchFolderURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trail-place-\(UUID().uuidString)", isDirectory: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: scratchFolderURL)
        defer {
            ActivityTrail.store = previousStore
            try? FileManager.default.removeItem(at: scratchFolderURL)
        }

        let holding: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(kind: "build", pid: 4242, moment: nil)
        WorkLeaseRegistry.noteDeclined(
            act: "an outside assistant's publish_pages", courseCode: "ICS3U",
            sectionNumber: 0, holding: holding
        )

        let trailText: String = ActivityTrail.store.activityText(includingPrompts: true)
        var writtenLines: [String] = []
        for line in trailText.components(separatedBy: "\n") {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                writtenLines.append(line)
            }
        }
        XCTAssertEqual(writtenLines.count, 1, trailText)
        let written: String = writtenLines.first ?? ""
        XCTAssertFalse(written.contains("ICS3U/0"), written)
        let sentence: String = WorkLeaseRegistry.declinedLine(
            act: "an outside assistant's publish_pages", sectionNumber: 0, holding: holding
        )
        XCTAssertTrue(sentence.contains("the course is being"), sentence)
        XCTAssertTrue(written.hasSuffix(" · ICS3U · " + sentence), written)
    }
}
