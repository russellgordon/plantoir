import XCTest
@testable import QuartzTeachers

/// Built websites live OUTSIDE the working folder, and `.merged_output` is a
/// symlink to where they really are.
///
/// The rule is written down in `contracts/shared-rules.json` →
/// `buildOutputLocation` and implemented twice on this platform — here and in
/// the three launchers — so these tests pin the SHAPE (where it goes, what is
/// migrated, what is never adopted) rather than any one caller's use of it.
final class BuildOutputLocationTests: XCTestCase {

    // MARK: - Stored properties

    /// A builds root of this test's own, so nothing here reaches into the
    /// teacher's real Application Support.
    var buildsRoot: URL = URL(fileURLWithPath: "/")

    /// The pretend working folder.
    var workingFolder: URL = URL(fileURLWithPath: "/")

    // MARK: - Functions

    override func setUpWithError() throws {
        let base: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cq4t-builds-\(UUID().uuidString)")
        buildsRoot = base.appendingPathComponent("builds")
        workingFolder = base.appendingPathComponent("Course Notes")
        try FileManager.default.createDirectory(
            at: workingFolder.appendingPathComponent("courses"), withIntermediateDirectories: true
        )
        BuildOutputLocation.buildsRootOverride = buildsRoot
    }

    override func tearDownWithError() throws {
        BuildOutputLocation.buildsRootOverride = nil
    }

    /// A course folder, with an optional real `.merged_output` holding a
    /// built page — the state every folder is in before this change.
    @discardableResult
    func makeCourse(_ code: String, withBuiltSiteSaying page: String? = nil) throws -> URL {
        let courseURL: URL = workingFolder.appendingPathComponent("courses").appendingPathComponent(code)
        try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
        if let page {
            let publicURL: URL = courseURL
                .appendingPathComponent(".merged_output")
                .appendingPathComponent("section1")
                .appendingPathComponent("public")
            try FileManager.default.createDirectory(at: publicURL, withIntermediateDirectories: true)
            try Data(page.utf8).write(to: publicURL.appendingPathComponent("index.html"))
        }
        return courseURL
    }

    /// What the built landing page says, read the way every reader in the app
    /// reads it: through `.merged_output`, without knowing it is a link.
    func builtPage(inCourse courseURL: URL) -> String? {
        let index: URL = courseURL
            .appendingPathComponent(".merged_output")
            .appendingPathComponent("section1")
            .appendingPathComponent("public")
            .appendingPathComponent("index.html")
        return try? String(contentsOf: index, encoding: .utf8)
    }

    // MARK: - Where it goes

    /// The folder identifier is the one the launchers derive with
    /// `pwd -P | shasum -a 256 | cut -c1-8`, which is also the container's
    /// name — one derivation, so a folder's container and its builds folder
    /// cannot disagree about which folder they belong to.
    @MainActor
    func testTheFolderIdentifierIsTheOneTheLaunchersUse() throws {
        let path: String = workingFolder.path
        let identifier: String = BuildOutputLocation.folderIdentifier(forWorkingFolder: path)
        XCTAssertEqual(identifier.count, 8)

        let shell: Process = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/bash")
        shell.arguments = ["-c", "cd \"$1\" && pwd -P | shasum -a 256 | cut -c1-8", "bash", path]
        let output: Pipe = Pipe()
        shell.standardOutput = output
        try shell.run()
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        let fromShell: String = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(identifier, fromShell, "the app and the launchers must name the same folder")
        XCTAssertEqual(FolderContainers.containerName(forFolder: path), "teaching-quartz-" + identifier)
    }

    /// The real location is under Application Support, because the container
    /// VM mounts only the home folder. Asked as a pure function of the home
    /// folder: the live `buildsRoot` answers a temporary folder while the
    /// suite runs, on purpose, so that a test archiving or renaming a course
    /// cannot reach into the teacher's own.
    func testTheRealLocationIsUnderTheHomeFolder() {
        let home: URL = URL(fileURLWithPath: "/Users/teacher")
        XCTAssertEqual(
            BuildOutputLocation.buildsRoot(inHomeFolder: home).path,
            "/Users/teacher/Library/Application Support/Plantoir/builds"
        )
    }

    /// The suite must never write into the real Application Support, and the
    /// guard that stops it is easy to remove by accident.
    func testTheSuiteNeverBuildsIntoTheRealApplicationSupport() {
        BuildOutputLocation.buildsRootOverride = nil
        let real: URL = BuildOutputLocation.buildsRoot(
            inHomeFolder: FileManager.default.homeDirectoryForCurrentUser
        )
        XCTAssertNotEqual(BuildOutputLocation.buildsRoot, real)
    }

    // MARK: - Making the link

    /// A course that has never been built gets a link and an empty folder to
    /// build into.
    func testAFreshCourseIsLinked() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        let outcome: BuildOutputLocation.Outcome = try BuildOutputLocation.ensureLink(
            courseDirectory: courseURL, workingFolderURL: workingFolder
        )
        XCTAssertEqual(outcome, .linked)

        let link: URL = courseURL.appendingPathComponent(".merged_output")
        let target: String = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        XCTAssertEqual(
            target,
            BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U").path
        )
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    /// Asking again changes nothing — it runs before every build and on every
    /// reload of the courses.
    func testAskingAgainChangesNothing() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)
        let target: URL = BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U")
        try Data("<html>built</html>".utf8).write(
            to: target.appendingPathComponent("keep.html")
        )

        let outcome: BuildOutputLocation.Outcome = try BuildOutputLocation.ensureLink(
            courseDirectory: courseURL, workingFolderURL: workingFolder
        )
        XCTAssertEqual(outcome, .alreadyLinked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("keep.html").path))
    }

    /// The migration every existing folder meets once: a real
    /// `.merged_output` is MOVED, the page still reads through the link, and
    /// the working folder no longer carries the bytes.
    func testAnExistingBuiltSiteIsMovedOutOfTheWorkingFolder() throws {
        let courseURL: URL = try makeCourse("ICS3U", withBuiltSiteSaying: "<html>last week</html>")
        let outcome: BuildOutputLocation.Outcome = try BuildOutputLocation.ensureLink(
            courseDirectory: courseURL, workingFolderURL: workingFolder
        )
        XCTAssertEqual(outcome, .migrated)
        XCTAssertEqual(builtPage(inCourse: courseURL), "<html>last week</html>")

        let link: URL = courseURL.appendingPathComponent(".merged_output")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                        "what is left in the course folder is a link, not the site")

        // The bytes are outside the working folder, which is the whole point:
        // a zip, a Finder copy, a backup or a sync of the folder no longer
        // carries them.
        let insideTheFolder: URL = BuildOutputLocation.buildFolder(
            forWorkingFolder: workingFolder, courseCode: "ICS3U"
        )
        XCTAssertFalse(insideTheFolder.path.hasPrefix(workingFolder.path))
    }

    /// A course folder synced from a second Mac carries a link naming a home
    /// folder that is not there. It is replaced rather than left to fail a
    /// build on a path a teacher can see working in Finder.
    func testADanglingLinkIsReplaced() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        try FileManager.default.createSymbolicLink(
            at: courseURL.appendingPathComponent(".merged_output"),
            withDestinationURL: URL(fileURLWithPath: "/Users/somebody-else/builds/ICS3U")
        )
        let outcome: BuildOutputLocation.Outcome = try BuildOutputLocation.ensureLink(
            courseDirectory: courseURL, workingFolderURL: workingFolder
        )
        XCTAssertEqual(outcome, .relinked)
        let target: String = try FileManager.default.destinationOfSymbolicLink(
            atPath: courseURL.appendingPathComponent(".merged_output").path
        )
        XCTAssertEqual(
            target,
            BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U").path
        )
    }

    /// A course folder synced from a second Mac where THIS Mac already has a
    /// build of its own: the local build is adopted, not thrown away.
    ///
    /// The clearing rule is about a course whose link is GONE — archived,
    /// restored, contents replaced. A link naming another MACHINE's builds
    /// folder says nothing about this machine's, and treating it as evidence
    /// would mean a teacher with two Macs had each of them throw the other's
    /// work away and rebuild on every switch.
    func testALinkFromAnotherMacDoesNotThrowAwayThisMacsBuild() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        let mine: URL = BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U")
            .appendingPathComponent("section1")
            .appendingPathComponent("public")
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        try Data("<html>mine</html>".utf8).write(to: mine.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(
            at: courseURL.appendingPathComponent(".merged_output"),
            withDestinationURL: URL(fileURLWithPath: "/Users/somebody-else/builds/xxxx/ICS3U")
        )

        let outcome: BuildOutputLocation.Outcome = try BuildOutputLocation.ensureLink(
            courseDirectory: courseURL, workingFolderURL: workingFolder
        )
        XCTAssertEqual(outcome, .alreadyLinked)
        XCTAssertEqual(builtPage(inCourse: courseURL), "<html>mine</html>")
    }

    /// A link pointing at another course INSIDE this machine's builds root is
    /// a different matter — a rename done outside the app — and the build
    /// standing under the new name does not belong to this course.
    func testALinkAtAnotherCourseOfOursIsStillCleared() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        let stale: URL = BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U")
            .appendingPathComponent("section1")
            .appendingPathComponent("public")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("<html>not mine</html>".utf8).write(to: stale.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(
            at: courseURL.appendingPathComponent(".merged_output"),
            withDestinationURL: BuildOutputLocation.buildFolder(
                forWorkingFolder: workingFolder, courseCode: "ICS4U"
            )
        )

        let outcome: BuildOutputLocation.Outcome = try BuildOutputLocation.ensureLink(
            courseDirectory: courseURL, workingFolderURL: workingFolder
        )
        XCTAssertEqual(outcome, .relinked)
        XCTAssertNil(builtPage(inCourse: courseURL))
    }

    /// If the move succeeds and the link cannot be made, the move is put BACK.
    /// A course with its website in the old place still builds and still
    /// publishes; a course with neither has lost it for nothing — and the next
    /// reload would clear the orphan outside, because nothing points at it.
    func testAMoveThatCannotBeLinkedIsPutBack() throws {
        let courseURL: URL = try makeCourse("ICS3U", withBuiltSiteSaying: "<html>keep me</html>")
        // Nothing may be created in the course folder, so the link cannot be
        // made — but the folder can still be read out of, so the move can.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: courseURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: courseURL.path)
        }

        XCTAssertThrowsError(
            try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: courseURL.path)
        XCTAssertEqual(builtPage(inCourse: courseURL), "<html>keep me</html>",
                       "the built website is back where it was, not orphaned outside")
    }

    /// A stray FILE wearing the name is not a built site and is not a link.
    func testAFileWhereTheLinkBelongsIsReplaced() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        try Data("not a folder".utf8).write(to: courseURL.appendingPathComponent(".merged_output"))
        let outcome: BuildOutputLocation.Outcome = try BuildOutputLocation.ensureLink(
            courseDirectory: courseURL, workingFolderURL: workingFolder
        )
        XCTAssertEqual(outcome, .linked)
    }

    // MARK: - What is never adopted

    /// The rule that stops a restored course publishing last month's pages: a
    /// build folder with NO link pointing at it belongs to an earlier life of
    /// that course code and is cleared, not reused.
    ///
    /// Restoring a course, restoring a backup and replacing a course's
    /// contents all remove the link along with everything else in the folder,
    /// and each of them can leave content whose timestamps are OLDER than the
    /// site standing outside — so an adopted build would read as up to date.
    func testABuildWithNoLinkPointingAtItIsCleared() throws {
        let stale: URL = BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U")
            .appendingPathComponent("section1")
            .appendingPathComponent("public")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("<html>last month</html>".utf8).write(to: stale.appendingPathComponent("index.html"))

        let courseURL: URL = try makeCourse("ICS3U")
        try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)

        XCTAssertNil(builtPage(inCourse: courseURL), "the old build must not be adopted by the new course")
    }

    /// Archiving a course takes its built site with it, so nothing is left in
    /// Application Support that nothing will ever name again.
    func testDiscardingACourseTakesItsBuiltSite() throws {
        let courseURL: URL = try makeCourse("ICS3U", withBuiltSiteSaying: "<html>x</html>")
        try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)
        BuildOutputLocation.discardBuild(forWorkingFolder: workingFolder, courseCode: "ICS3U")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U").path
        ))
    }

    /// Archiving ONE section takes that section's built site and leaves the
    /// rest of the course's alone.
    func testDiscardingASectionLeavesTheOthers() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)
        let target: URL = BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U")
        for number in [1, 2] {
            try FileManager.default.createDirectory(
                at: target.appendingPathComponent("section\(number)"), withIntermediateDirectories: true
            )
        }
        BuildOutputLocation.discardSectionBuild(
            forWorkingFolder: workingFolder, courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("section1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("section2").path))
    }

    /// Putting a section's pages back must take that section's built website
    /// with them, or publishing ships the pages the teacher has just undone.
    ///
    /// Driven through `CourseRestorer` rather than the primitive, because the
    /// primitive was already right and the wiring was what was missing.
    @MainActor
    func testRestoringASectionThrowsAwayItsBuiltSite() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        let sectionURL: URL = courseURL.appendingPathComponent("section1")
        try FileManager.default.createDirectory(at: sectionURL, withIntermediateDirectories: true)
        try Data("# today\n".utf8).write(to: sectionURL.appendingPathComponent("index.md"))
        let values: [String: Any] = ["course_code": "ICS3U", "section_numbers": [1]]
        let configurationData: Data = try JSONSerialization.data(withJSONObject: values)
        try configurationData.write(to: courseURL.appendingPathComponent("course_config.json"))
        try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)

        let built: URL = BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U")
            .appendingPathComponent("section1")
            .appendingPathComponent("public")
        try FileManager.default.createDirectory(at: built, withIntermediateDirectories: true)
        try Data("<html>today</html>".utf8).write(to: built.appendingPathComponent("index.html"))

        // A backup of the section as it was, made the way the app makes one.
        let course: Course = Course(
            code: "ICS3U",
            directoryURL: courseURL,
            configuration: CourseConfiguration(values: values, lastSavedData: configurationData)
        )
        let coursesURL: URL = workingFolder.appendingPathComponent("courses")
        let backupURL: URL = try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesURL)
        let backup: BackupItem = try XCTUnwrap(BackupItem.from(fileURL: backupURL, courseCode: "ICS3U"))

        try CourseRestorer.restoreSection(1, from: backup, coursesDirectoryURL: coursesURL)

        XCTAssertNil(
            builtPage(inCourse: courseURL),
            "a restored section's pages can be OLDER than the site built from them, so a "
                + "built site left standing reads as up to date and publishes what was undone"
        )
    }

    // MARK: - Renaming

    /// A rename used to cost nothing, because the built site sat inside the
    /// folder that moved. It still costs nothing.
    func testRenamingACourseCarriesItsBuiltSite() throws {
        let oldURL: URL = try makeCourse("ICS3U", withBuiltSiteSaying: "<html>keep me</html>")
        try BuildOutputLocation.ensureLink(courseDirectory: oldURL, workingFolderURL: workingFolder)

        let newURL: URL = workingFolder.appendingPathComponent("courses").appendingPathComponent("ICS4U")
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        BuildOutputLocation.moveBuild(
            forWorkingFolder: workingFolder,
            fromCourseCode: "ICS3U",
            toCourseCode: "ICS4U",
            renamedCourseDirectory: newURL
        )

        XCTAssertEqual(builtPage(inCourse: newURL), "<html>keep me</html>")
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: newURL.appendingPathComponent(".merged_output").path
            ),
            BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS4U").path
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U").path
        ))
    }

    // MARK: - Sweeping up

    /// Builds belonging to courses this folder no longer has are removed; the
    /// ones it still has, and the marker naming the folder, are not.
    func testBuildsForCoursesThatAreGoneAreRemoved() throws {
        for code in ["ICS3U", "ICS4U"] {
            let courseURL: URL = try makeCourse(code)
            try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)
        }
        BuildOutputLocation.discardBuildsForMissingCourses(
            workingFolderURL: workingFolder, courseCodesPresent: ["ICS3U"]
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS3U").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: BuildOutputLocation.buildFolder(forWorkingFolder: workingFolder, courseCode: "ICS4U").path
        ))
        let marker: URL = BuildOutputLocation.buildsFolder(forWorkingFolder: workingFolder)
            .appendingPathComponent(BuildOutputLocation.workingFolderMarkerName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "the marker is not a course")
    }

    /// The marker says which working folder a builds folder serves, because
    /// the identifier is a hash and cannot be read backwards.
    func testTheBuildsFolderSaysWhichWorkingFolderItServes() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)
        let marker: URL = BuildOutputLocation.buildsFolder(forWorkingFolder: workingFolder)
            .appendingPathComponent(BuildOutputLocation.workingFolderMarkerName)
        let recorded: String = try String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // POSIX realpath, not Foundation's resolvingSymlinksInPath(): under
        // /var/folders the two disagree about the /private prefix, and the
        // launchers' `pwd -P` keeps it.
        var physical: String = workingFolder.path
        if let resolved = realpath(workingFolder.path, nil) {
            physical = String(cString: resolved)
            free(resolved)
        }
        XCTAssertEqual(recorded, physical)
    }

    /// A working folder that has been thrown away leaves its builds behind,
    /// and they are swept — but only when the folder was under the HOME
    /// folder, because "not there" and "the disk is not plugged in" look
    /// exactly alike from here and only the home volume is always mounted.
    func testOnlyBuildsForFoldersUnderTheHomeFolderAreSwept() throws {
        let home: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cq4t-home-\(UUID().uuidString)")
        let gone: URL = buildsRoot.appendingPathComponent("aaaaaaaa")
        let onAnotherDisk: URL = buildsRoot.appendingPathComponent("bbbbbbbb")
        let unmarked: URL = buildsRoot.appendingPathComponent("cccccccc")
        for folder in [gone, onAnotherDisk, unmarked] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try "\(home.path)/Course Notes\n".write(
            to: gone.appendingPathComponent(BuildOutputLocation.workingFolderMarkerName),
            atomically: true, encoding: .utf8
        )
        try "/Volumes/Teaching/Course Notes\n".write(
            to: onAnotherDisk.appendingPathComponent(BuildOutputLocation.workingFolderMarkerName),
            atomically: true, encoding: .utf8
        )

        BuildOutputLocation.discardBuildsForMissingWorkingFolders(homeDirectory: home)

        XCTAssertFalse(FileManager.default.fileExists(atPath: gone.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: onAnotherDisk.path), "the disk may be back tomorrow")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unmarked.path), "no marker is no evidence")
    }

    /// "The folder is not there" and "Plantoir is not allowed to look at it"
    /// are different answers, and only the first is deletion.
    ///
    /// A working folder on the Desktop or in Documents sits behind a macOS
    /// permission grant that can be absent at launch, denied, or reset by a
    /// re-signed build. Reading a refusal as "deleted" would throw away the
    /// built websites of a folder the teacher still has, at every launch.
    func testAFolderThatCannotBeLookedAtIsNotTreatedAsDeleted() throws {
        let home: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cq4t-home-\(UUID().uuidString)")
        let closed: URL = home.appendingPathComponent("closed")
        let inside: URL = closed.appendingPathComponent("Course Notes")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let builds: URL = buildsRoot.appendingPathComponent("dddddddd")
        try FileManager.default.createDirectory(at: builds, withIntermediateDirectories: true)
        try "\(inside.path)\n".write(
            to: builds.appendingPathComponent(BuildOutputLocation.workingFolderMarkerName),
            atomically: true, encoding: .utf8
        )

        // Nothing may be looked up inside `closed`, so asking about the folder
        // fails with a refusal rather than with "no such file".
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: closed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: closed.path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: inside.path),
                       "the state being tested: the folder is there and reads as absent")

        BuildOutputLocation.discardBuildsForMissingWorkingFolders(homeDirectory: home)

        XCTAssertTrue(FileManager.default.fileExists(atPath: builds.path),
                      "a folder Plantoir cannot look at is not a folder that is gone")
    }

    /// A working folder that is still there keeps its builds.
    func testBuildsForAFolderThatStillExistsAreKept() throws {
        let courseURL: URL = try makeCourse("ICS3U")
        try BuildOutputLocation.ensureLink(courseDirectory: courseURL, workingFolderURL: workingFolder)
        BuildOutputLocation.discardBuildsForMissingWorkingFolders(
            homeDirectory: workingFolder.deletingLastPathComponent()
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: BuildOutputLocation.buildsFolder(forWorkingFolder: workingFolder).path
        ))
    }
}
