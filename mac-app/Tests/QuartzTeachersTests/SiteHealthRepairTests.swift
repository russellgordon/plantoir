import XCTest
@testable import QuartzTeachers

/// Putting right the folder problems that can be put right.
@MainActor
final class SiteHealthRepairTests: XCTestCase {

    // MARK: - Functions

    private func makeCourse() throws -> (URL, Course) {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("health-repair-\(UUID().uuidString)")
        let courseURL: URL = root.appendingPathComponent("courses/ICS3U")
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        let configuration: [String: Any] = [
            "course_code": "ICS3U", "course_name": "Introduction to Computer Science",
            "section_numbers": [1], "num_sections": 1,
            "shared_folders": [], "per_section_folders": ["All Classes"],
            "shared_files": [], "per_section_files": [],
        ]
        let configURL: URL = courseURL.appendingPathComponent("course_config.json")
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: configURL)
        return (root, Course(
            code: "ICS3U", directoryURL: courseURL,
            configuration: try CourseConfiguration(contentsOf: configURL)
        ))
    }

    private func finding(_ name: String, fixable: Bool, section: Int = 1) -> SiteHealthFinding {
        return SiteHealthFinding(
            name: name, sentence: "Something is wrong.", detail: "More about it.",
            fixable: fixable, course: "ICS3U", section: section
        )
    }

    /// The line that matters most: a fix must restore the FEATURE, not merely
    /// satisfy the check. Recreating an empty curriculum folder would silence
    /// the warning and leave the map missing.
    func testTheUnfixableFindingsAreNeverOffered() {
        for name in ["curriculumCoverageFoundNothing", "courseTeachesNothing",
                     "handWrittenCoveragePage"] {
            XCTAssertFalse(
                SiteHealthRepair.canRepair(finding(name, fixable: true)),
                "\(name) must never grow a fix button, even if the toolchain calls it fixable"
            )
        }
        XCTAssertNil(SiteHealthRepair.buttonTitle(
            for: [finding("curriculumCoverageFoundNothing", fixable: true)]
        ))
    }

    func testAMissingMediaFolderIsPutBack() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        let media: URL = course.directoryURL.appendingPathComponent("Media")
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.path))

        let repaired = SiteHealthRepair.repair(
            [finding("mediaFolderMissing", fixable: true)], in: course
        )
        XCTAssertEqual(repaired["mediaFolderMissing"], .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.path))
    }

    func testAMissingFrontPageIsPutBackWithATitle() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        SiteHealthRepair.repair([finding("sectionIndexMissing", fixable: true)], in: course)

        let index: URL = course.sectionDirectoryURL(forSection: 1)
            .appendingPathComponent("index.md")
        let written: String = try String(contentsOf: index, encoding: .utf8)
        XCTAssertTrue(written.contains("title: Introduction to Computer Science"), written)
    }

    /// A repair whose outcome is invisible is one nobody trusts the second
    /// time — and the Media folder is somewhere a teacher cannot see from this
    /// app, so silence after pressing the button is indistinguishable from
    /// nothing having happened.
    func testARepairSaysWhatItPutBack() {
        XCTAssertEqual(
            SiteHealthRepair.whatWasPutBack(["mediaFolderMissing"]),
            "Put the Media folder back."
        )
        XCTAssertEqual(
            SiteHealthRepair.whatWasPutBack(["mediaFolderMissing", "sectionIndexMissing"]),
            "Put the Media folder and the front page back."
        )
        XCTAssertNil(SiteHealthRepair.whatWasPutBack([]),
                     "nothing repaired means nothing to announce")
        XCTAssertNil(SiteHealthRepair.whatWasPutBack(["curriculumCoverageFoundNothing"]),
                     "a finding with no repair has nothing to report")
    }

    /// The site still shows how things were until it is built again, and saying
    /// so is the difference between a button that fixed the folder and one a
    /// teacher believes fixed their site.
    func testTheTeacherIsToldTheSiteHasNotChangedYet() {
        let said: String = SiteHealthRepair.notOnTheSiteYet
        XCTAssertTrue(said.lowercased().contains("build"), said)
        for word in ["container", "script", "toolchain", "quartz", "config", "rebuild the toolchain"] {
            XCTAssertFalse(said.lowercased().contains(word), "says \"\(word)\" to a teacher")
        }
    }

    /// Pressing Fix twice — or pressing it after putting the folder back in
    /// Obsidian — must not be reported as a permissions problem. Both restores
    /// return "already there", which folding into "failed" turned into
    /// "Plantoir could not put that back… check the folder isn't locked".
    func testNothingToDoIsNotReportedAsAFailure() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: course.directoryURL.appendingPathComponent("Media"),
            withIntermediateDirectories: true
        )
        let outcome = SiteHealthRepair.outcome(
            ofRepairing: [finding("mediaFolderMissing", fixable: true)], in: course
        )
        XCTAssertEqual(outcome?.headline, "That is already put right.")
        XCTAssertFalse(outcome?.detail.lowercased().contains("read-only") ?? true,
                       "a no-op must not read as a permissions failure")
    }

    /// A PARTIAL failure said nothing about the half that did not come back —
    /// silence whenever anything else succeeded, in the type added so failure
    /// would not be silent.
    func testAPartialFailureNamesWhatDidNotComeBack() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        // Media can be restored; the front page cannot, because section 9 is
        // not one this course has.
        let outcome = SiteHealthRepair.outcome(
            ofRepairing: [
                finding("mediaFolderMissing", fixable: true),
                finding("sectionIndexMissing", fixable: true, section: 9),
            ],
            in: course
        )
        XCTAssertEqual(outcome?.headline, "Put the Media folder back.")
        XCTAssertTrue(outcome?.detail.contains("Could not put the front page back") ?? false,
                      outcome?.detail ?? "")
        XCTAssertEqual(outcome?.canRebuild, false,
                       "something is still wrong, so do not send them to look at it")
    }

    /// A repair that FAILED must say so. Both restore functions can return
    /// false — a read-only volume, a permissions problem, a file where the
    /// folder should be — and reporting only success made a failed repair
    /// indistinguishable from a successful one: the alert closed either way.
    func testAFailedRepairIsReportedRatherThanPassedOverInSilence() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        // A FILE where the Media folder should be: creating the directory
        // cannot succeed.
        try "not a folder".write(
            to: course.directoryURL.appendingPathComponent("Media"),
            atomically: true, encoding: .utf8
        )

        let outcome = SiteHealthRepair.outcome(
            ofRepairing: [finding("mediaFolderMissing", fixable: true)], in: course
        )
        XCTAssertNotNil(outcome, "a failed repair must still produce something to show")
        XCTAssertTrue(outcome?.headline.contains("could not") ?? false, outcome?.headline ?? "")
        XCTAssertEqual(outcome?.canRebuild, false,
                       "there is nothing to see, so do not offer to build")
    }

    /// A fresh preview is no use to somebody whose site is published: only
    /// publishing again changes what students look at.
    func testAPublishedSiteIsNotOfferedAPreview() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = SiteHealthRepair.outcome(
            ofRepairing: [finding("mediaFolderMissing", fixable: true)], in: course,
            occasion: .publishing
        )
        XCTAssertEqual(outcome?.canRebuild, false)
        XCTAssertTrue(outcome?.detail.lowercased().contains("publish") ?? false,
                      outcome?.detail ?? "")
    }

    /// A finding's section number is parsed from output and falls back to 0.
    /// Creating a `section0` folder because a line was malformed would invent
    /// structure the course does not have.
    func testARepairRefusesASectionTheCourseDoesNotHave() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(SiteHealthRepair.restoreSectionIndex(forSection: 0, in: course))
        XCTAssertFalse(SiteHealthRepair.restoreSectionIndex(forSection: 7, in: course))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: course.directoryURL.appendingPathComponent("section0").path
            ),
            "no section0 folder may be conjured up"
        )
    }

    /// Pressing it twice, or pressing it after fixing the problem in Obsidian,
    /// must change nothing — a repair that overwrote would destroy the very
    /// page the teacher had just written.
    func testARepairNeverOverwritesWhatIsAlreadyThere() throws {
        let (root, course) = try makeCourse()
        defer { try? FileManager.default.removeItem(at: root) }

        let index: URL = course.sectionDirectoryURL(forSection: 1)
            .appendingPathComponent("index.md")
        try FileManager.default.createDirectory(
            at: index.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "---\ntitle: My own front page\n---\nWelcome!\n"
            .write(to: index, atomically: true, encoding: .utf8)

        let repaired = SiteHealthRepair.repair(
            [finding("sectionIndexMissing", fixable: true)], in: course
        )
        XCTAssertEqual(repaired["sectionIndexMissing"], .alreadyFine,
                       "already there is not a failure")
        XCTAssertTrue(
            try String(contentsOf: index, encoding: .utf8).contains("Welcome!"),
            "the teacher's own page must survive"
        )
    }
}
