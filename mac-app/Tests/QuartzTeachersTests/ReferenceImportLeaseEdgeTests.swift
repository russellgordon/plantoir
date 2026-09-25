import XCTest
@testable import QuartzTeachers

/// The two edges of the import's live-process lease (#245), asked of the
/// real import, the real Keep a Copy for Reference… and the real sweep.
///
/// **Written against names the code had BEFORE #245, on purpose.** Each of
/// these was proven to fail on that code by copying the old source files back
/// in and running this file (see `GUI-IMPROVEMENTS.md` row 551 for the
/// counts), so nothing here may reach for an API #245 added — the sentences
/// are read from the contract by their keys rather than from the Swift
/// constants, which is also how they stay unquoted.
extension ReferenceImportTests {

    // MARK: - Functions

    /// Another account's LIVE process holds its staging folder.
    ///
    /// Pid 1 — launchd — is alive and belongs to root, so `kill(1, 0)`
    /// answers `EPERM` (measured). Until #245 every answer but 0 read as
    /// "gone", so this folder was swept out from under a live import. If the
    /// suite is ever run as root the signal answers 0 and this still passes,
    /// for the same reason the rule gives.
    func testAnotherAccountsLiveImportIsNotSwept() throws {
        try prepare()
        let staging: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: "ICS4U-2025")
        )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        // Named, because an import lease with no name line is read as
        // Plantoir's (#245's review, L2), and launchd is not Plantoir.
        let lease: URL = try writeLease(for: "ICS4U-2025", pid: 1, body: "1\nlaunchd\n")

        let swept: [String] = ReferenceStaging.sweepLeftovers(inCoursesDirectory: coursesDirectoryURL)

        XCTAssertEqual(
            swept, [],
            "Another account's import was read as abandoned — the system said the process exists "
            + "and is not ours to signal, and that is not 'gone'."
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lease.path))
    }

    /// A lease naming process 0 holds nothing: `kill(0, 0)` answers 0 for
    /// the caller's own process group (measured), so the old check read such
    /// a lease as alive for ever and the leftover was never tidied away.
    func testALeaseNamingProcessZeroDoesNotHoldALeftover() throws {
        try prepare()
        let staging: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: "ICS4U-2025")
        )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        _ = try writeLease(for: "ICS4U-2025", pid: 0, body: "0")

        XCTAssertEqual(
            ReferenceStaging.sweepLeftovers(inCoursesDirectory: coursesDirectoryURL),
            ["ICS4U-2025"],
            "Process 0 is not a process; a lease naming it kept a leftover for ever."
        )
    }

    /// Another copy of Plantoir is importing ICS4U-2025 right now: its lease
    /// names a live process, and its half-made copy is in the staging folder.
    /// This import is REFUSED with its own sentence, and removes nothing.
    ///
    /// Before #245 the second import skipped the leftover removal (a live
    /// owner), took its own lease, failed to make the folder that was already
    /// there — and its catch tidied the OTHER copy's work away.
    func testAnImportAnotherCopyOfPlantoirIsMakingIsLeftAlone() async throws {
        try prepare()
        try makeOldCourse(code: "ICS4U", sections: [1])
        let otherCopy: Process = try startALiveProcess()

        let staging: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: "ICS4U-2025")
        )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let sentinel: URL = staging.appendingPathComponent("half-made.md")
        try Data("the other copy's work".utf8).write(to: sentinel)
        let theirLease: URL = try writeLease(
            for: "ICS4U-2025", pid: otherCopy.processIdentifier, body: "\(otherCopy.processIdentifier)\nsleep\n"
        )

        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        let outcomes: [ReferenceImporter.Outcome] = await importEverything(from: source)

        let wording: [String: Any] = try importingWording()
        let sentence: String = try XCTUnwrap(wording["alreadyBeingImported"] as? String)
        XCTAssertEqual(outcomes, [.notImported(course: "ICS4U", reason: sentence)])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sentinel.path),
            "The other copy's half-made course was removed by this one's tidy-up."
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: theirLease.path), "Their lease was taken away.")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: activityURL().appendingPathComponent(
                    ReferenceStaging.leaseName(for: "ICS4U-2025", pid: getpid())
                ).path
            ),
            "The refused import left its own lease behind."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: coursesDirectoryURL.appendingPathComponent("ICS4U-2025").path)
        )
        XCTAssertTrue(
            ActivityTrail.store.activityText(includingPrompts: true).contains(
                "could not import ICS4U for reference from \(source.rootURL.lastPathComponent) — \(sentence)"
            ),
            "The refusal left no line on the trail."
        )
    }

    /// Keep a Copy for Reference… meets another copy of Plantoir making the
    /// same folder: refused, and the other copy's work is left alone. Its
    /// catch removed the staging folder unconditionally before #245.
    func testKeepACopyLeavesAnotherCopysWorkAlone() throws {
        try prepare()
        let course: Course = try makeTeachingCourse(code: "ICS3U")
        let otherCopy: Process = try startALiveProcess()

        let staging: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: "ICS3U-2025")
        )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let sentinel: URL = staging.appendingPathComponent("half-made.md")
        try Data("the other copy's work".utf8).write(to: sentinel)
        _ = try writeLease(
            for: "ICS3U-2025", pid: otherCopy.processIdentifier, body: "\(otherCopy.processIdentifier)\nsleep\n"
        )

        var refusal: String? = nil
        do {
            _ = try ReferenceCopier.keepACopy(
                of: course, named: "ICS3U-2025", schoolYear: 2025,
                coursesDirectoryURL: coursesDirectoryURL
            )
            XCTFail("A copy was made over another copy of Plantoir's work in progress.")
        } catch {
            refusal = (error as? LocalizedError)?.errorDescription
        }

        let wording: [String: Any] = try referenceWording()
        let pattern: String = try XCTUnwrap(wording["copyAlreadyBeingMade"] as? String)
        XCTAssertEqual(refusal, pattern.replacingOccurrences(of: "{folder}", with: "ICS3U-2025"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sentinel.path),
            "Keep a Copy's tidy-up removed the other copy's half-made course."
        )
    }

    /// The same app, two acts: an import of ICS4U-2025 is under way, and
    /// Keep a Copy for Reference… is asked for a folder of the same name in
    /// the middle of it.
    ///
    /// Keep a Copy is synchronous, so it runs between the importer's
    /// suspension points — here, from inside the import's first progress
    /// report, which is a real point in the import rather than a guessed
    /// moment. One process means one process id, so before #245 it read the
    /// import's lease as its OWN and went ahead, made the copy, renamed it
    /// into place and released the lease the import depended on; the import
    /// then failed. Now it is refused, and the import finishes.
    func testKeepACopyDuringAnImportInThisAppIsRefused() async throws {
        try prepare()
        try makeOldCourse(code: "ICS4U", sections: [1])
        let course: Course = try makeTeachingCourse(code: "ICS4U")
        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }
        let found: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)
        let coursesDirectoryURL: URL = self.coursesDirectoryURL

        let refusal: RefusalBox = RefusalBox()
        let outcomes: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
            [ReferenceImporter.Request(course: found, schoolYear: 2025)],
            into: coursesDirectoryURL,
            existingFolderNames: [],
            alreadyShelved: [],
            from: source.rootURL,
            progress: { _ in
                if refusal.asked {
                    return
                }
                refusal.asked = true
                do {
                    _ = try ReferenceCopier.keepACopy(
                        of: course, named: "ICS4U-2025", schoolYear: 2025,
                        coursesDirectoryURL: coursesDirectoryURL
                    )
                    refusal.sentence = nil
                } catch {
                    refusal.sentence = (error as? LocalizedError)?.errorDescription
                }
            }
        )

        XCTAssertTrue(refusal.asked, "The import never reported progress, so nothing was tried.")
        let wording: [String: Any] = try referenceWording()
        let pattern: String = try XCTUnwrap(wording["copyAlreadyBeingMade"] as? String)
        XCTAssertEqual(
            refusal.sentence, pattern.replacingOccurrences(of: "{folder}", with: "ICS4U-2025"),
            "Keep a Copy went ahead in the middle of an import of the same folder."
        )
        guard case .imported(let made) = outcomes.first, outcomes.count == 1 else {
            return XCTFail("The import did not finish: \(outcomes)")
        }
        XCTAssertEqual(made.folderName, "ICS4U-2025")
        let arrived: URL = coursesDirectoryURL.appendingPathComponent("ICS4U-2025")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: arrived.appendingPathComponent("Media").appendingPathComponent("diagram.png").path
            ),
            "What is at ICS4U-2025 is not the imported course."
        )
        XCTAssertEqual(leftoverStagingAndLeases(), [])
    }

    /// Two windows on one working folder import the same course at once.
    ///
    /// Two windows are one process, and before #245 the second read the
    /// first's lease as a live owner, went on, and its failure to make the
    /// folder tidied the first one's copy away. Exactly one now imports; the
    /// other is refused with the sentence — or, if the first had already
    /// finished, told the folder is there. Either way nothing is left
    /// half-made and no lease outlives the run.
    func testTwoWindowsImportingTheSameCourseAtOnce() async throws {
        try prepare()
        let courseURL: URL = try makeOldCourse(code: "ICS4U", sections: [1])
        // Enough files that the two copies overlap rather than one finishing
        // before the other begins.
        let many: URL = courseURL.appendingPathComponent("section1").appendingPathComponent("Many")
        try FileManager.default.createDirectory(at: many, withIntermediateDirectories: true)
        for number in 1...200 {
            try Data("# page \(number)\n".utf8).write(to: many.appendingPathComponent("Page \(number).md"))
        }
        guard case .found(let source) = read(oldFolderURL) else {
            return XCTFail("The old folder was refused.")
        }

        let found: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)
        let coursesDirectoryURL: URL = self.coursesDirectoryURL
        let rootURL: URL = source.rootURL
        // Two windows: two runs on the main actor, each giving way to the
        // other wherever the import itself waits.
        var runs: [Task<[ReferenceImporter.Outcome], Never>] = []
        for _ in 1...2 {
            runs.append(Task { @MainActor in
                return await ReferenceImporter.importCourses(
                    [ReferenceImporter.Request(course: found, schoolYear: 2025)],
                    into: coursesDirectoryURL,
                    existingFolderNames: [],
                    alreadyShelved: [],
                    from: rootURL,
                    progress: { _ in }
                )
            })
        }
        var both: [[ReferenceImporter.Outcome]] = []
        for run in runs {
            both.append(await run.value)
        }

        let wording: [String: Any] = try importingWording()
        let busy: String = try XCTUnwrap(wording["alreadyBeingImported"] as? String)
        let exists: String = ReferenceCopier.Problem.folderAlreadyExists("ICS4U-2025").errorDescription ?? ""
        var importedCount: Int = 0
        var refusedCount: Int = 0
        for outcomes in both {
            for outcome in outcomes {
                switch outcome {
                case .imported:
                    importedCount += 1
                case .notImported(let course, let reason):
                    XCTAssertEqual(course, "ICS4U")
                    XCTAssertTrue(
                        reason == busy || reason == exists,
                        "The second window was told something else: \(reason)"
                    )
                    refusedCount += 1
                default:
                    XCTFail("Unexpected outcome \(outcome)")
                }
            }
        }
        XCTAssertEqual(importedCount, 1, "Exactly one window imports the course: \(both)")
        XCTAssertEqual(refusedCount, 1, "The other window is told why it did not: \(both)")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: coursesDirectoryURL.appendingPathComponent("ICS4U-2025")
                    .appendingPathComponent("course_config.json").path
            )
        )
        XCTAssertEqual(leftoverStagingAndLeases(), [])
    }

    // MARK: - Helpers for these tests

    /// A course being taught in THIS working folder, for Keep a Copy.
    func makeTeachingCourse(code: String) throws -> Course {
        let courseURL: URL = coursesDirectoryURL.appendingPathComponent(code)
        try FileManager.default.createDirectory(
            at: courseURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        try Data("# kept\n".utf8).write(
            to: courseURL.appendingPathComponent("section1").appendingPathComponent("kept.md")
        )
        try JSONSerialization.data(withJSONObject: [
            "course_code": code, "section_numbers": [1],
        ]).write(to: courseURL.appendingPathComponent("course_config.json"))
        return Course(
            code: code,
            directoryURL: courseURL,
            configuration: try CourseConfiguration(
                contentsOf: courseURL.appendingPathComponent("course_config.json")
            )
        )
    }

    /// A real process that stays alive, standing in for another copy of
    /// Plantoir. Stopped — by the process id this test started, and by
    /// nothing else — as soon as the test ends, pass or fail.
    func startALiveProcess() throws -> Process {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        addTeardownBlock {
            process.terminate()
            process.waitUntilExit()
        }
        return process
    }

    /// `courses/.internal/activity/`.
    func activityURL() -> URL {
        return coursesDirectoryURL.appendingPathComponent(".internal").appendingPathComponent("activity")
    }

    /// Writes an import lease with exactly this body.
    @discardableResult
    func writeLease(for folderName: String, pid: Int32, body: String) throws -> URL {
        let activity: URL = activityURL()
        try FileManager.default.createDirectory(at: activity, withIntermediateDirectories: true)
        let lease: URL = activity.appendingPathComponent(
            ReferenceStaging.leaseName(for: folderName, pid: pid)
        )
        try Data(body.utf8).write(to: lease)
        return lease
    }

    /// Every staging folder under `courses/` and every import lease, by name
    /// — what a finished run must not leave behind.
    func leftoverStagingAndLeases() -> [String] {
        var left: [String] = []
        let courses: [String] = (try? FileManager.default.contentsOfDirectory(
            atPath: coursesDirectoryURL.path
        )) ?? []
        for name in courses {
            if ReferenceStaging.isStagingName(name) {
                left.append(name)
            }
        }
        let leases: [String] = (try? FileManager.default.contentsOfDirectory(
            atPath: activityURL().path
        )) ?? []
        for name in leases {
            if name.contains(".import.") {
                left.append(name)
            }
        }
        return left
    }

    /// `referenceCourses.importing.wording`.
    func importingWording() throws -> [String: Any] {
        let reference: [String: Any] = try referenceRules()
        let importing: [String: Any] = try XCTUnwrap(reference["importing"] as? [String: Any])
        return try XCTUnwrap(importing["wording"] as? [String: Any])
    }

    /// `referenceCourses.wording`.
    func referenceWording() throws -> [String: Any] {
        let reference: [String: Any] = try referenceRules()
        return try XCTUnwrap(reference["wording"] as? [String: Any])
    }

    /// `referenceCourses` in `contracts/shared-rules.json`.
    func referenceRules() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/shared-rules.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        return try XCTUnwrap(all["referenceCourses"] as? [String: Any])
    }
}

/// What Keep a Copy said from inside the import's progress report.
@MainActor
final class RefusalBox {

    // MARK: - Stored properties

    var asked: Bool = false
    var sentence: String? = nil
}
