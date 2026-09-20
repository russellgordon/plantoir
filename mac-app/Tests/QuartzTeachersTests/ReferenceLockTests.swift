import XCTest
@testable import QuartzTeachers

/// The lock on a reference course's pages, against a REAL temporary folder.
///
/// Nothing here is mocked, deliberately: what is being pinned is what the file
/// system does, and a stand-in for the file system would pin what somebody
/// believed it does. Every test clears the flags it set in its own teardown —
/// a locked tree cannot be removed, so a test that forgot would leave an
/// undeletable folder behind in the temporary directory.
@MainActor
final class ReferenceLockTests: XCTestCase {

    // MARK: - Stored properties

    var workingFolderURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")
    var trailFolderURL: URL = URL(fileURLWithPath: "/")
    var launchControl: FakeLaunchControl = FakeLaunchControl()
    var agentsDirectory: URL = URL(fileURLWithPath: "/")

    // MARK: - Setting up

    func prepare() throws {
        let root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reference-lock-\(UUID().uuidString)")
        workingFolderURL = root.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        trailFolderURL = root.appendingPathComponent("trail")
        agentsDirectory = root.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)

        ScheduledDeploy.launchAgentsDirectoryOverride = agentsDirectory
        ScheduledDeploy.scheduledScriptsDirectoryOverride = root.appendingPathComponent("scheduled")
        launchControl = FakeLaunchControl()
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolderURL)

        addTeardownBlock {
            MainActor.assumeIsolated {
                ScheduledDeploy.launchAgentsDirectoryOverride = nil
                ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
                ActivityTrail.store = previousStore
                // Everything this test locked, unlocked — or the temporary
                // tree outlives the run and the next one meets it.
                ReferenceLock.clearLock(at: root)
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A course on disk, kept for reference unless told otherwise, with a
    /// page, an image, a settings file and an `.obsidian` folder.
    @discardableResult
    func makeCourse(
        folderName: String = "ICS3U-2025",
        code: String = "ICS3U",
        keptForReference: Bool = true,
        schoolYear: Int? = 2025,
        sections: [Int] = [1, 2]
    ) throws -> Course {
        let fileManager: FileManager = FileManager.default
        let courseURL: URL = coursesDirectoryURL.appendingPathComponent(folderName)
        for sectionNumber in sections {
            let sectionURL: URL = courseURL.appendingPathComponent("section\(sectionNumber)")
            try fileManager.createDirectory(at: sectionURL, withIntermediateDirectories: true)
            try Data("# lesson\n".utf8).write(to: sectionURL.appendingPathComponent("index.md"))
        }
        let mediaURL: URL = courseURL.appendingPathComponent("Media")
        try fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        try Data("not really a picture".utf8).write(to: mediaURL.appendingPathComponent("diagram.png"))
        let obsidianURL: URL = courseURL.appendingPathComponent(".obsidian")
        try fileManager.createDirectory(at: obsidianURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: obsidianURL.appendingPathComponent("workspace.json"))

        var values: [String: Any] = [
            "course_code": code,
            "course_name": "Introduction to Computer Science",
            "section_numbers": sections,
            "num_sections": sections.count,
        ]
        if keptForReference {
            values["kept_for_reference"] = true
            if let schoolYear {
                values["reference_school_year"] = schoolYear
            }
        }
        let data: Data = try JSONSerialization.data(withJSONObject: values)
        try data.write(to: courseURL.appendingPathComponent("course_config.json"))
        let configuration: CourseConfiguration = CourseConfiguration(values: values, lastSavedData: data)
        return Course(code: folderName, directoryURL: courseURL, configuration: configuration)
    }

    // MARK: - What a locked page refuses

    /// The four things an editor, a terminal or an agent would do to a page —
    /// and the second is the one permissions alone would have let through.
    func testALockedPageRefusesEveryOrdinaryWrite() throws {
        try prepare()
        let course: Course = try makeCourse()
        ReferenceLock.ensureLocked(course)

        let page: URL = course.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("index.md")
        XCTAssertTrue(ReferenceLock.isLocked(page))

        // 1. Writing in place.
        XCTAssertThrowsError(try Data("changed".utf8).write(to: page))

        // 2. Renaming a new file OVER it — how every serious editor saves,
        //    and what read-only permissions alone do NOT stop.
        let replacement: URL = course.directoryURL.appendingPathComponent("replacement.md")
        try Data("replaced".utf8).write(to: replacement)
        XCTAssertThrowsError(try FileManager.default.moveItem(at: replacement, to: page))

        // 3. Renaming it away.
        XCTAssertThrowsError(
            try FileManager.default.moveItem(
                at: page, to: page.deletingLastPathComponent().appendingPathComponent("moved.md")
            )
        )

        // 4. Deleting it.
        XCTAssertThrowsError(try FileManager.default.removeItem(at: page))

        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "# lesson\n",
                       "The page is exactly what it was.")
    }

    /// Modes are left alone. 444 was measured to break the preview build —
    /// the frontmatter rewrite fails on the bind mount and every HIDDEN page
    /// appears in the built site — so the lock must not reach for it.
    func testTheLockLeavesPermissionsExactlyAsTheyWere() throws {
        try prepare()
        let course: Course = try makeCourse()
        let page: URL = course.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("index.md")
        let before: Any? = try FileManager.default.attributesOfItem(atPath: page.path)[.posixPermissions]
        ReferenceLock.ensureLocked(course)
        let after: Any? = try FileManager.default.attributesOfItem(atPath: page.path)[.posixPermissions]
        XCTAssertEqual(before as? NSNumber, after as? NSNumber,
                       "Mode 444 makes the build publish pages the teacher had hidden.")
    }

    // MARK: - What is deliberately left writable

    func testTheThingsThatHaveToStayWritableDo() throws {
        try prepare()
        let course: Course = try makeCourse()
        ReferenceLock.ensureLocked(course)

        // The school year can be changed later, and the build's preflight
        // rewrites this file.
        let configURL: URL = course.configFileURL
        XCTAssertFalse(ReferenceLock.isLocked(configURL))
        course.configuration.referenceSchoolYear = 2024
        XCTAssertNoThrow(try course.configuration.write(to: configURL))

        // Obsidian writes this the moment a vault opens.
        let workspaceJSON: URL = course.directoryURL
            .appendingPathComponent(".obsidian").appendingPathComponent("workspace.json")
        XCTAssertFalse(ReferenceLock.isLocked(workspaceJSON))
        XCTAssertNoThrow(try Data("{\"open\": true}".utf8).write(to: workspaceJSON))

        // And the one that would kill the preview: the build-output link has
        // to be CREATED inside the course folder on every reload.
        let link: URL = course.directoryURL.appendingPathComponent(".merged_output")
        XCTAssertNoThrow(
            try FileManager.default.createSymbolicLink(
                at: link, withDestinationURL: workingFolderURL.appendingPathComponent("builds")
            )
        )
    }

    /// A course a teacher teaches is never touched, however often this runs.
    func testAnOrdinaryCourseIsLeftAlone() throws {
        try prepare()
        let course: Course = try makeCourse(folderName: "ICS4U", code: "ICS4U", keptForReference: false)
        let outcome: ReferenceLock.Outcome = ReferenceLock.ensureLocked(course)
        XCTAssertTrue(outcome.isQuiet)
        let page: URL = course.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("index.md")
        XCTAssertFalse(ReferenceLock.isLocked(page))
        XCTAssertNoThrow(try Data("ordinary".utf8).write(to: page))
    }

    // MARK: - Asserted, verified, re-asserted

    func testLockingIsIdempotentAndReportsOnlyWhatItHadToDo() throws {
        try prepare()
        let course: Course = try makeCourse()

        let first: ReferenceLock.Outcome = ReferenceLock.ensureLocked(course)
        XCTAssertGreaterThan(first.locked, 0)
        XCTAssertEqual(first.didNotTake, 0)

        let second: ReferenceLock.Outcome = ReferenceLock.ensureLocked(course)
        XCTAssertTrue(second.isQuiet, "A course already frozen costs a stat per file and says nothing.")
    }

    /// The re-assertion: a folder read again locks whatever came back
    /// unlocked, and leaves a line saying how many.
    func testReadingTheFolderLocksAReferenceCourseThatCameBackUnlocked() throws {
        try prepare()
        let course: Course = try makeCourse()
        let page: URL = course.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("index.md")
        XCTAssertFalse(ReferenceLock.isLocked(page), "It starts as an ordinary folder.")

        let outcome: ReferenceLock.Outcome = ReferenceCourseUpkeep.bringUpToDate(
            [course], inWorkingFolder: workingFolderURL, runner: launchControl
        )
        XCTAssertGreaterThan(outcome.locked, 0)
        XCTAssertTrue(ReferenceLock.isLocked(page))
        XCTAssertTrue(
            ActivityTrail.store.activityText(includingPrompts: true).contains("kept for reference"),
            "The count on the trail is what explains a report of 'it let me edit a page'."
        )
    }

    func testAQuietPassLeavesNoLineAtAll() throws {
        try prepare()
        let course: Course = try makeCourse()
        ReferenceCourseUpkeep.bringUpToDate([course], inWorkingFolder: workingFolderURL, runner: launchControl)
        let afterFirst: String = ActivityTrail.store.activityText(includingPrompts: true)
        ReferenceCourseUpkeep.bringUpToDate([course], inWorkingFolder: workingFolderURL, runner: launchControl)
        XCTAssertEqual(
            ActivityTrail.store.activityText(includingPrompts: true), afterFirst,
            "A folder in a steady state writes nothing, or the trail is noise."
        )
    }

    /// A course marked by hand, with an alarm it set while it was live.
    func testAReferenceCourseLosesAScheduledDeployItStillOwned() throws {
        try prepare()
        let course: Course = try makeCourse(folderName: "ICS3U-2025", code: "ICS3U")
        try writeAgent(courseCode: "ICS3U-2025", sectionNumber: 1)
        XCTAssertTrue(agentExists(courseCode: "ICS3U-2025", sectionNumber: 1))

        ReferenceCourseUpkeep.bringUpToDate(
            [course], inWorkingFolder: workingFolderURL, runner: launchControl
        )
        XCTAssertFalse(
            agentExists(courseCode: "ICS3U-2025", sectionNumber: 1),
            "A deploy set for a course that is never deployed would be refused at half six with nobody there."
        )
        XCTAssertTrue(
            ActivityTrail.store.activityText(includingPrompts: true)
                .contains("because the course is kept for reference")
        )
    }

    // MARK: - The flag travels, which is the trap

    /// Anything copied OUT arrives locked. A page a teacher cannot edit, with
    /// no explanation, reads as "the app is broken".
    func testACopyTakenOutArrivesLockedUntilTheLockIsCleared() throws {
        try prepare()
        let course: Course = try makeCourse()
        ReferenceLock.ensureLocked(course)

        let source: URL = course.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("index.md")
        let borrowed: URL = coursesDirectoryURL.appendingPathComponent("borrowed.md")
        try FileManager.default.copyItem(at: source, to: borrowed)

        XCTAssertTrue(
            ReferenceLock.isLocked(borrowed),
            "FileManager.copyItem carries the flag — whatever copies pages between courses must clear it."
        )
        XCTAssertThrowsError(try Data("mine now".utf8).write(to: borrowed))

        ReferenceLock.clearLock(at: borrowed)
        XCTAssertFalse(ReferenceLock.isLocked(borrowed))
        XCTAssertNoThrow(try Data("mine now".utf8).write(to: borrowed))
    }

    // MARK: - Removing, backing up and restoring

    /// Removal works, and it is the unlock that makes it work: a locked tree
    /// refuses `removeItem` outright.
    func testRemovingAReferenceCourseUnlocksItFirst() throws {
        try prepare()
        let course: Course = try makeCourse()
        ReferenceLock.ensureLocked(course)

        let result: ScheduledDeployCleanup.RemovalResult = ScheduledDeployCleanup.removeCourse(
            course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
        )
        XCTAssertNil(result.problem)
        XCTAssertTrue(result.didRemove)
        XCTAssertFalse(FileManager.default.fileExists(atPath: course.directoryURL.path))
    }

    /// Removing a SECTION changes the course, so it is refused — in a
    /// sentence, never in the file system's own words.
    func testRemovingOneSectionOfAReferenceCourseIsRefused() throws {
        try prepare()
        let course: Course = try makeCourse()
        ReferenceLock.ensureLocked(course)

        let result: ScheduledDeployCleanup.RemovalResult = ScheduledDeployCleanup.removeSection(
            2, from: course, coursesDirectoryURL: coursesDirectoryURL, runner: launchControl
        )
        XCTAssertFalse(result.didRemove)
        XCTAssertEqual(result.problem, ReferenceWording.staysAsItIs(course: "ICS3U"))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: course.directoryURL.appendingPathComponent("section2").path
            )
        )
    }

    /// A backup round trip loses the flag, and the marker in the restored
    /// config is what puts it back.
    func testARestoredReferenceCourseComesBackLocked() throws {
        try prepare()
        let course: Course = try makeCourse()
        ReferenceLock.ensureLocked(course)

        let backupURL: URL = try CourseArchiver.backUpCourse(
            course, coursesDirectoryURL: coursesDirectoryURL
        )
        let item: BackupItem = try XCTUnwrap(
            BackupItem.from(fileURL: backupURL, courseCode: course.code)
        )
        try CourseRestorer.restoreBackup(item, coursesDirectoryURL: coursesDirectoryURL)

        let page: URL = course.directoryURL
            .appendingPathComponent("section1").appendingPathComponent("index.md")
        XCTAssertTrue(
            ReferenceLock.isLocked(page),
            "A zip carries the mode and not the flag, so a restore that did not re-lock would thaw the course."
        )
    }

    // MARK: - Helpers

    func writeAgent(courseCode: String, sectionNumber: Int) throws {
        let label: String = ScheduledDeploy.agentLabel(
            courseCode: courseCode, sectionNumber: sectionNumber
        )
        let plist: [String: Any] = [
            "Label": label,
            "WorkingDirectory": workingFolderURL.path,
            "ProgramArguments": [
                "/Applications/Plantoir.app/Contents/MacOS/Plantoir",
                ScheduledDeploy.runFlag,
                "/tmp/\(label).sh",
                ScheduledDeploy.sectionFlag,
                workingFolderURL.path,
                courseCode,
                String(sectionNumber),
            ],
        ]
        let data: Data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try data.write(to: agentsDirectory.appendingPathComponent("\(label).plist"))
    }

    func agentExists(courseCode: String, sectionNumber: Int) -> Bool {
        let label: String = ScheduledDeploy.agentLabel(
            courseCode: courseCode, sectionNumber: sectionNumber
        )
        return FileManager.default.fileExists(
            atPath: agentsDirectory.appendingPathComponent("\(label).plist").path
        )
    }
}
