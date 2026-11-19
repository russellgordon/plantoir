import XCTest
@testable import QuartzTeachers

/// Section ▸ Roll Over to a New Year… (#897 piece B), the two safety rules
/// the implementation review asked for, kept in a class of their own so
/// each can be proven red on the code before the fixes:
///
/// - an Undo Last Change after a deploy never deletes last year's kept
///   marker (the review's I1, its own reproduction);
/// - a rollover whose copy of the course cannot be saved first is refused
///   before anything changes (the director's ruling on the review's I2).
///
/// Only names that existed before the fixes are used here, so this file
/// compiles against either version.
@MainActor
final class RollOverFromTheMenuSafetyTests: XCTestCase {

    // MARK: - Set up and tear down

    override func tearDown() async throws {
        SectionMenuActivity.reset()
        try await super.tearDown()
    }

    // MARK: - An undo after a deploy (I1)

    /// The review's reproduction: a rollover onto a new website, then a
    /// deploy writes a new marker, then Undo Last Change. The new marker is
    /// left alone (it changed since), and last year's kept marker must still
    /// be there. Red before the fix: the kept copy matched its recorded
    /// half and was deleted, leaving only the new marker.
    func testAnUndoAfterADeployNeverDeletesTheKeptMarker() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        _ = RollOverFromTheMenuTests.countCopies(of: made)
        let folder: URL = made.course.directoryURL.appendingPathComponent(".netlify_sites")
        let marker: URL = folder.appendingPathComponent("section1.json")
        try "{\"site_id\": \"last-year\"}".write(to: marker, atomically: true, encoding: .utf8)

        _ = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
        )
        let kept: [String] = RollOverFromTheMenuSafetyTests.keptMarkers(in: folder)
        XCTAssertEqual(kept.count, 1, "the rollover kept last year's marker aside")

        // The deploy that follows names a new website.
        try "{\"site_id\": \"this-year\"}".write(to: marker, atomically: true, encoding: .utf8)

        _ = await made.runner.run(call: SectionVerbs.undoLastChange())
        XCTAssertEqual(
            RollOverFromTheMenuSafetyTests.keptMarkers(in: folder), kept,
            "Undo Last Change must never delete last year's kept marker"
        )
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "{\"site_id\": \"this-year\"}",
                       "the marker the deploy wrote is left alone")

        // A second press changes neither.
        _ = await made.runner.run(call: SectionVerbs.undoLastChange())
        XCTAssertEqual(RollOverFromTheMenuSafetyTests.keptMarkers(in: folder), kept)
    }

    /// With no deploy between, one undo puts the marker back where deploying
    /// reads it, and the kept copy is not deleted either.
    func testAnUndoWithNoDeployPutsTheMarkerBackAndKeepsTheCopy() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        _ = RollOverFromTheMenuTests.countCopies(of: made)
        let folder: URL = made.course.directoryURL.appendingPathComponent(".netlify_sites")
        let marker: URL = folder.appendingPathComponent("section1.json")
        try "{\"site_id\": \"last-year\"}".write(to: marker, atomically: true, encoding: .utf8)
        _ = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        _ = await made.runner.run(call: SectionVerbs.undoLastChange())
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "{\"site_id\": \"last-year\"}")
        XCTAssertEqual(RollOverFromTheMenuSafetyTests.keptMarkers(in: folder).count, 1)
    }

    // MARK: - No copy, no rollover (I2)

    /// The copy cannot be saved: refused with the sentence for that fact,
    /// and nothing changed (the page, the marker, the undo list). Red before
    /// the fix: the rollover went ahead with no copy and said nothing.
    func testARolloverWithNoCopyIsRefusedBeforeAnythingChanges() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        RollOverFromTheMenuSafetyTests.failEveryCopy(of: made)
        let marker: URL = made.course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        let page: URL = made.course.directoryURL.appendingPathComponent("section1/All Classes/Unit 1, Day 1.md")
        let pageBefore: String = try String(contentsOf: page, encoding: .utf8)
        let changesBefore: Int = made.runner.changeCount

        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
        )
        XCTAssertEqual(outcome.summary, AssistWording.startOfYearNeedsABackup(course: "ICS3U"))
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), pageBefore, "no page was re-dated")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "no marker was moved")
        XCTAssertEqual(made.runner.changeCount, changesBefore)
    }

    /// The same where the dates are already right: refused, the marker and
    /// the published-pages record where they were.
    func testARolloverWithTheDatesAlreadyRightAndNoCopyIsRefused() async throws {
        let made = try AssistFixture.makeSectionNeedingReDating(withMarker: true, surface: .menu, for: self)
        defer {
            try? FileManager.default.removeItem(at: made.root)
        }
        _ = RollOverFromTheMenuTests.countCopies(of: made)
        _ = await made.runner.run(call: SectionVerbs.reDateClasses(course: "ICS3U", section: 1, planning: false))
        try RollOverFromTheMenuTests.writePublishedRecord(in: made.course)
        RollOverFromTheMenuSafetyTests.failEveryCopy(of: made)
        let marker: URL = made.course.directoryURL.appendingPathComponent(".netlify_sites/section1.json")
        let changesBefore: Int = made.runner.changeCount

        let outcome: AssistToolOutcome = await made.runner.run(
            call: SectionVerbs.rollOver(course: "ICS3U", section: 1, website: "new", planning: false)
        )
        XCTAssertEqual(outcome.summary, AssistWording.startOfYearNeedsABackup(course: "ICS3U"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(PublishedPagesRecord.places(courseDirectory: made.course.directoryURL, section: 1), ["Concepts/Worksheet"])
        XCTAssertEqual(made.runner.changeCount, changesBefore)
    }

    // MARK: - Functions

    /// The kept copies of Section 1's marker, by name, sorted.
    static func keptMarkers(in folder: URL) -> [String] {
        let entries: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var kept: [String] = []
        for entry in entries where entry.hasPrefix("section1.previous-") {
            kept.append(entry)
        }
        kept.sort()
        return kept
    }

    /// Every copy of the course the runner tries to save fails, as on a full disk.
    static func failEveryCopy(of made: AssistFixture.Made) {
        made.runner.backUpACourse = { (course: Course, coursesDirectoryURL: URL, maker: BackupMaker) in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "the disk is full"])
        }
    }
}
