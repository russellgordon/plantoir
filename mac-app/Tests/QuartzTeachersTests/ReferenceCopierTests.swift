import XCTest
@testable import QuartzTeachers

/// "Keep a Copy for Reference…" — the act, without the sheet.
@MainActor
final class ReferenceCopierTests: XCTestCase {

    // MARK: - Stored properties

    var workingFolderURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")
    var trailFolderURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Setting up

    func prepare() throws {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reference-copier-\(UUID().uuidString)")
        workingFolderURL = root.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        trailFolderURL = root.appendingPathComponent("trail")
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolderURL)
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousStore
                ReferenceLock.clearLock(at: root)
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A live course, with everything a real one has that the copy must or
    /// must not take: pages, media, a built-site symlink, a site marker, a
    /// stale config backup and a lease.
    @discardableResult
    func makeLiveCourse(code: String = "ICS3U", sections: [Int] = [1, 2]) throws -> Course {
        let fileManager: FileManager = FileManager.default
        let courseURL: URL = coursesDirectoryURL.appendingPathComponent(code)
        for sectionNumber in sections {
            let sectionURL: URL = courseURL.appendingPathComponent("section\(sectionNumber)")
            try fileManager.createDirectory(at: sectionURL, withIntermediateDirectories: true)
            try Data("---\ndraft: true\n---\n# private\n".utf8)
                .write(to: sectionURL.appendingPathComponent("Private Notes.md"))
            try Data("# lesson\n".utf8).write(to: sectionURL.appendingPathComponent("index.md"))
        }
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("Media"), withIntermediateDirectories: true
        )
        try Data("picture".utf8).write(
            to: courseURL.appendingPathComponent("Media").appendingPathComponent("diagram.png")
        )

        // Last year's real class sites.
        let markers: URL = courseURL.appendingPathComponent(".netlify_sites")
        try fileManager.createDirectory(at: markers, withIntermediateDirectories: true)
        for sectionNumber in sections {
            try Data("{\"site_id\": \"real-site\"}".utf8)
                .write(to: markers.appendingPathComponent("section\(sectionNumber).json"))
        }

        // Things the copy leaves behind.
        try Data("{\"course_code\": \"ICS3U\"}".utf8)
            .write(to: courseURL.appendingPathComponent("course_config.backup.json"))
        let leases: URL = courseURL.appendingPathComponent(".internal").appendingPathComponent("activity")
        try fileManager.createDirectory(at: leases, withIntermediateDirectories: true)
        try Data("1234".utf8).write(to: leases.appendingPathComponent("ICS3U.preview.1234.lease"))
        let timetable: URL = courseURL.appendingPathComponent(".internal").appendingPathComponent("timetable")
        try fileManager.createDirectory(at: timetable, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: timetable.appendingPathComponent("section1.json"))

        // The built website: a symlink OUT of the folder, holding something
        // enormous. Following it is the mistake this guards.
        let buildsURL: URL = workingFolderURL.appendingPathComponent("builds")
        try fileManager.createDirectory(at: buildsURL, withIntermediateDirectories: true)
        try Data("a whole built site".utf8).write(to: buildsURL.appendingPathComponent("public.html"))
        try fileManager.createSymbolicLink(
            at: courseURL.appendingPathComponent(".merged_output"), withDestinationURL: buildsURL
        )

        let values: [String: Any] = [
            "course_code": code,
            "course_name": "Introduction to Computer Science",
            "section_numbers": sections,
            "num_sections": sections.count,
            "deploy_target": "netlify",
            "custom_domains": ["sections": ["section1": "ics3u.example.org"]],
            "additional_deploy_targets": [["type": "local_folder", "path": "/tmp/redundant"]],
        ]
        let data: Data = try JSONSerialization.data(withJSONObject: values)
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        return Course(
            code: code,
            directoryURL: courseURL,
            configuration: CourseConfiguration(values: values, lastSavedData: data)
        )
    }

    // MARK: - What the copy is

    func testTheCopyIsAReferenceCourseShowingTheRealCode() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        let made: ReferenceCopier.Made = try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL
        )
        XCTAssertEqual(made.displayCode, "ICS3U")
        XCTAssertEqual(made.sectionCount, 2)

        let copyURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
        let configuration: CourseConfiguration = try CourseConfiguration(
            contentsOf: copyURL.appendingPathComponent("course_config.json")
        )
        XCTAssertTrue(configuration.keptForReference)
        XCTAssertEqual(configuration.referenceSchoolYear, 2025)
        XCTAssertEqual(configuration.courseCode, "ICS3U", "The real code is what a teacher reads.")
    }

    func testTheCopyHasNowhereToDeployTo() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let copyURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
        let configuration: CourseConfiguration = try CourseConfiguration(
            contentsOf: copyURL.appendingPathComponent("course_config.json")
        )
        XCTAssertEqual(configuration.deployTarget, "local_folder")
        XCTAssertEqual(configuration.deployFolderPath, "")
        XCTAssertTrue(configuration.additionalDeployTargets.isEmpty)
        XCTAssertNil(configuration.values["custom_domains"])

        // And last year's site markers are renamed aside rather than
        // deleted — so a deploy that somehow ran would make a NEW site, and
        // a section that has never deployed cannot be scheduled.
        let markers: URL = copyURL.appendingPathComponent(".netlify_sites")
        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: markers.path)
        XCTAssertFalse(names.contains("section1.json"), "The live marker must not travel under its own name.")
        var keptOne: Bool = false
        for name in names where name.hasPrefix("section1.previous-") {
            keptOne = true
        }
        XCTAssertTrue(keptOne, "The site id and its admin address are kept, under the frozen name.")
    }

    func testTheOriginalIsNotTouched() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let original: CourseConfiguration = try CourseConfiguration(contentsOf: live.configFileURL)
        XCTAssertFalse(original.keptForReference, "The course they are teaching stays live.")
        XCTAssertEqual(original.deployTarget, "netlify")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: live.directoryURL
                    .appendingPathComponent(".netlify_sites")
                    .appendingPathComponent("section1.json").path
            ),
            "Its own website marker is where it was."
        )
        let page: URL = live.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("index.md")
        XCTAssertFalse(ReferenceLock.isLocked(page), "Nothing of theirs is locked.")
        XCTAssertNoThrow(try Data("still teaching this".utf8).write(to: page))
    }

    func testTheCopyIsLockedAndTheBuiltSiteIsNotFollowed() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let copyURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")

        let page: URL = copyURL.appendingPathComponent("section1").appendingPathComponent("index.md")
        XCTAssertTrue(ReferenceLock.isLocked(page))
        XCTAssertThrowsError(try Data("changed".utf8).write(to: page))

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: copyURL.appendingPathComponent(".merged_output").path),
            "Last year's built website is rebuilt on demand, never copied — it is a symlink out of the folder."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: copyURL.appendingPathComponent("course_config.backup.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: copyURL.appendingPathComponent(".internal")
                    .appendingPathComponent("activity").path
            ),
            "A lease names a process on whichever machine wrote it."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: copyURL.appendingPathComponent(".internal")
                    .appendingPathComponent("timetable")
                    .appendingPathComponent("section1.json").path
            ),
            "What the teacher told Plantoir about their timetable comes across."
        )
    }

    /// Last year's record of what students actually saw is kept exactly as it
    /// is — it is what makes a preview of a reference course sensible.
    func testHiddenPagesStayHiddenInTheCopy() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let copied: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
            .appendingPathComponent("section1").appendingPathComponent("Private Notes.md")
        let text: String = try String(contentsOf: copied, encoding: .utf8)
        XCTAssertTrue(text.contains("draft: true"))
        XCTAssertFalse(
            AssistPageVisibility.publishes(in: text, forSection: 1),
            "A page students could not see last year is not published by being kept."
        )
    }

    /// A copy taken FROM a course that is already frozen.
    ///
    /// The lock travels through `FileManager.copyItem`, so before the fix the
    /// copy arrived frozen — and then the two steps that follow could not
    /// happen: the site markers could not be renamed aside, and the
    /// half-written folder could not be removed. The teacher was left with a
    /// folder they could delete from neither the app nor Finder.
    ///
    /// Nothing offers this today — "Keep a Copy for Reference…" is withheld
    /// on a reference course — and it is fixed anyway, because a guard that
    /// depends on a menu item being withheld somewhere else is a guard one
    /// edit from being gone.
    func testACopyTakenFromAFrozenCourseIsMadeAndIsDeletable() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let frozenURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
        let frozen: Course = Course(
            code: "ICS3U-2025",
            directoryURL: frozenURL,
            configuration: try CourseConfiguration(
                contentsOf: frozenURL.appendingPathComponent("course_config.json")
            )
        )
        XCTAssertTrue(
            ReferenceLock.isLocked(
                frozenURL.appendingPathComponent("section1").appendingPathComponent("index.md")
            ),
            "The source has to be really locked, or this test proves nothing."
        )
        // Put a live site marker back on the frozen course, so the copy has
        // something to rename aside — the step that failed first.
        let markers: URL = frozenURL.appendingPathComponent(".netlify_sites")
        try Data("{\"site_id\": \"still-here\"}".utf8)
            .write(to: markers.appendingPathComponent("section1.json"))
        // Locked like everything else in the course, which is the whole
        // point: a LOCKED marker is what `moveItem` refuses.
        ReferenceLock.lock(courseDirectory: frozenURL)
        XCTAssertTrue(ReferenceLock.isLocked(markers.appendingPathComponent("section1.json")))

        // A minute later, because a released marker is named after the
        // SECOND it was released in — two releases inside one second would
        // collide on the file name, which is `DeployCommand.releaseSite`'s
        // own frozen naming and nothing to do with the lock.
        let second: ReferenceCopier.Made = try ReferenceCopier.keepACopy(
            of: frozen, named: "ICS3U-2024", schoolYear: 2024,
            coursesDirectoryURL: coursesDirectoryURL,
            at: Date().addingTimeInterval(60)
        )
        XCTAssertEqual(second.displayCode, "ICS3U")

        let secondURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2024")
        let names: [String] = try FileManager.default.contentsOfDirectory(
            atPath: secondURL.appendingPathComponent(".netlify_sites").path
        )
        XCTAssertFalse(
            names.contains("section1.json"),
            "The marker could not be renamed aside on a locked copy — the neutralisation half-happened."
        )

        // And the whole thing can be taken away again.
        ReferenceLock.unlock(courseDirectory: secondURL)
        XCTAssertNoThrow(try FileManager.default.removeItem(at: secondURL))
    }

    /// A copy that fails part-way leaves nothing undeletable.
    func testAFailedCopyLeavesNothingBehind() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let frozenURL: URL = coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
        let frozen: Course = Course(
            code: "ICS3U-2025",
            directoryURL: frozenURL,
            configuration: try CourseConfiguration(
                contentsOf: frozenURL.appendingPathComponent("course_config.json")
            )
        )
        // Make the copy fail AFTER the contents are in: the settings file is
        // gone, so reading the copy's config throws.
        ReferenceLock.unlock(courseDirectory: frozenURL)
        try FileManager.default.removeItem(at: frozen.configFileURL)
        ReferenceLock.lock(courseDirectory: frozenURL)

        XCTAssertThrowsError(
            try ReferenceCopier.keepACopy(
                of: frozen, named: "ICS3U-2024", schoolYear: 2024,
                coursesDirectoryURL: coursesDirectoryURL
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: coursesDirectoryURL.appendingPathComponent("ICS3U-2024").path
            ),
            "A half-written copy must be an ordinary folder that goes away cleanly."
        )
    }

    func testAFolderNameAlreadyTakenIsRefusedBeforeAnythingIsWritten() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        try FileManager.default.createDirectory(
            at: coursesDirectoryURL.appendingPathComponent("ICS3U-2025"),
            withIntermediateDirectories: true
        )
        XCTAssertThrowsError(
            try ReferenceCopier.keepACopy(
                of: live, named: "ICS3U-2025", schoolYear: 2025,
                coursesDirectoryURL: coursesDirectoryURL
            )
        ) { error in
            XCTAssertEqual(error as? ReferenceCopier.Problem, .folderAlreadyExists("ICS3U-2025"))
        }
    }

    func testTheTrailSaysWhatWasKeptAndWhereItCameFrom() throws {
        try prepare()
        let live: Course = try makeLiveCourse()
        try ReferenceCopier.keepACopy(
            of: live, named: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL
        )
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("ICS3U-2025"), trail)
        XCTAssertTrue(trail.contains("2025–26"), trail)
        XCTAssertTrue(trail.contains("2 sections"), trail)
    }

    /// A copy filed under no year is filed under "Other", and says so.
    func testACopyWithNoSchoolYearIsAllowed() throws {
        try prepare()
        let live: Course = try makeLiveCourse(code: "ADA1O", sections: [1])
        let made: ReferenceCopier.Made = try ReferenceCopier.keepACopy(
            of: live, named: "ADA1O-REF", schoolYear: nil,
            coursesDirectoryURL: coursesDirectoryURL
        )
        XCTAssertNil(made.schoolYear)
        let configuration: CourseConfiguration = try CourseConfiguration(
            contentsOf: coursesDirectoryURL.appendingPathComponent("ADA1O-REF")
                .appendingPathComponent("course_config.json")
        )
        XCTAssertNil(configuration.values["reference_school_year"])
        XCTAssertTrue(configuration.keptForReference)
    }
}
