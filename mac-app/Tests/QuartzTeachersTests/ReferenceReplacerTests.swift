import XCTest
@testable import QuartzTeachers

/// Runs `contracts/shared-rules.json` → `referenceCourses.replacing` (#572,
/// second piece): replacing a course on the Reference Courses shelf after a
/// warning and a checked backup, the roll-back sweep that puts the old
/// course back after a quit part way, and the trail line every whole-course
/// restore now leaves.
///
/// Every list is data from the contract. The act runs on REAL folders under
/// a temporary working folder: a live ICS3U that no step may touch, and a
/// reference ICS3U-2025, locked, whose pages say "old". The new course is
/// made under the hidden staging name and says "new". The seams in
/// `ReferenceReplacer.World` record the order the steps ran in and make one
/// step fail on cue; every step that is not made to fail is the real one.
@MainActor
final class ReferenceReplacerTests: XCTestCase {

    // MARK: - Types

    /// The steps a case ran, in order.
    final class Recorder {

        // MARK: - Stored properties

        var steps: [String] = []
        var obsidianAsked: Int = 0
    }

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")
    var workingFolderURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")

    var oldURL: URL {
        return coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
    }

    var asideURL: URL {
        return coursesDirectoryURL.appendingPathComponent(ReferenceReplacer.asideName(for: "ICS3U-2025"))
    }

    var stagingURL: URL {
        return coursesDirectoryURL.appendingPathComponent(ReferenceStaging.stagingName(for: "ICS3U-2025"))
    }

    var liveURL: URL {
        return coursesDirectoryURL.appendingPathComponent("ICS3U")
    }

    // MARK: - Setting up

    /// A throwaway working folder holding a live ICS3U and a reference
    /// ICS3U-2025 (locked), and a trail of its own.
    func prepareWorkingFolder() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reference-replace-\(UUID().uuidString)")
        workingFolderURL = rootURL.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        try ReferenceReplacerTests.writeCourse(at: liveURL, reference: false, says: "live")
        // What makes a folder a working folder to `reloadCourses`.
        try Data("#!/bin/bash\n".utf8).write(to: workingFolderURL.appendingPathComponent("preview.sh"))
        try ReferenceReplacerTests.writeCourse(at: oldURL, reference: true, says: "old")
        ReferenceLock.lock(courseDirectory: oldURL)

        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail"))
        let root: URL = rootURL
        addTeardownBlock {
            MainActor.assumeIsolated {
                ActivityTrail.store = previousStore
                ReferenceStaging.claimedStagingKeys = []
                ReferenceLock.clearLock(at: root)
            }
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A course folder whose pages say `says`.
    static func writeCourse(at folderURL: URL, reference: Bool, says: String) throws {
        let fileManager: FileManager = FileManager.default
        try fileManager.createDirectory(
            at: folderURL.appendingPathComponent("section1"), withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: folderURL.appendingPathComponent("Lessons"), withIntermediateDirectories: true
        )
        var settings: String = "{\"course_code\": \"ICS3U\", \"section_numbers\": [1]"
        if reference {
            settings += ", \"kept_for_reference\": true, \"reference_school_year\": 2025, \"deploy_target\": \"local_folder\""
        }
        settings += "}\n"
        try Data(settings.utf8).write(to: folderURL.appendingPathComponent("course_config.json"))
        try Data("---\ntitle: Front\n---\n\(says)\n".utf8)
            .write(to: folderURL.appendingPathComponent("section1").appendingPathComponent("index.md"))
        try Data("---\ntitle: Lesson\n---\n\(says)\n".utf8)
            .write(to: folderURL.appendingPathComponent("Lessons").appendingPathComponent("Lesson.md"))
    }

    /// The new course, made under the old course's hidden name and CLAIMED,
    /// as every door makes it.
    func stageTheNewCourse() throws {
        XCTAssertEqual(
            ReferenceStaging.claim("ICS3U-2025", inCoursesDirectory: coursesDirectoryURL), .claimed
        )
        try ReferenceReplacerTests.writeCourse(at: stagingURL, reference: true, says: "new")
        ReferenceLock.lock(courseDirectory: stagingURL)
    }

    /// What a page in a folder says, or nil when there is no page.
    static func whatItSays(_ folderURL: URL) -> String? {
        let page: URL = folderURL.appendingPathComponent("section1").appendingPathComponent("index.md")
        guard let text = try? String(contentsOf: page, encoding: .utf8) else {
            return nil
        }
        for word in ["old", "new", "live"] where text.contains("\n\(word)\n") {
            return word
        }
        return "?"
    }

    var trail: String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    /// The contract block.
    static func replacingRules() throws -> [String: Any] {
        return try XCTUnwrap(try ReferenceCreationTests.referenceRules(["replacing"]))
    }

    /// A world where nothing is busy and Obsidian holds nothing, with the
    /// real backup, check, rename and removal.
    static func quietWorld() -> ReferenceReplacer.World {
        var world: ReferenceReplacer.World = ReferenceReplacer.World()
        world.isBusy = { _, _, _ in
            return false
        }
        world.obsidianHoldsIt = { _ in
            return false
        }
        return world
    }

    // MARK: - Wording

    func testTheSentencesAreTheContracts() throws {
        let wording: [String: Any] = try XCTUnwrap(try ReferenceReplacerTests.replacingRules()["wording"] as? [String: Any])
        XCTAssertEqual(ReferenceReplaceWording.replaceButton, wording["replaceButton"] as? String)
        XCTAssertEqual(
            ReferenceReplaceWording.title(course: "{course}", group: "{group}"), wording["title"] as? String
        )
        // #834: one sentence, then the facts as rows; the one-paragraph
        // body and bodyWithoutADate are retired.
        XCTAssertEqual(ReferenceReplaceWording.message, wording["message"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.beingReplacedLabel, wording["beingReplacedLabel"] as? String)
        XCTAssertEqual(
            ReferenceReplaceWording.beingReplacedValue(sections: "{sections}", pages: "{pages}", size: "{size}"),
            wording["beingReplacedValue"] as? String
        )
        XCTAssertEqual(ReferenceReplaceWording.keptOnLabel, wording["keptOnLabel"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.backedUpLabel, wording["backedUpLabel"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.backedUpValue(folder: "{folder}"), wording["backedUpValue"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.toUndoLabel, wording["toUndoLabel"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.toUndoValue, wording["toUndoValue"] as? String)
        XCTAssertNil(wording["body"], "retired by #834")
        XCTAssertNil(wording["bodyWithoutADate"], "retired by #834")
        XCTAssertEqual(ReferenceReplaceWording.confirmButton, wording["confirmButton"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.cancelButton, wording["cancelButton"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.replaceWhileBusy(course: "{course}"), wording["replaceWhileBusy"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.openInObsidian(course: "{course}"), wording["openInObsidian"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.notOnTheShelf(course: "{course}"), wording["notOnTheShelf"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.couldNotBackUp(course: "{course}"), wording["couldNotBackUp"] as? String)
        XCTAssertEqual(ReferenceReplaceWording.couldNotReplace(course: "{course}"), wording["couldNotReplace"] as? String)
        XCTAssertEqual(
            ReferenceReplaceWording.backupIsIncomplete(course: "{course}", folder: "{folder}"),
            wording["backupIsIncomplete"] as? String
        )
        XCTAssertEqual(
            ReferenceReplaceWording.notTheCourseInTheWay(folder: "{folder}"), wording["notTheCourseInTheWay"] as? String
        )
        XCTAssertEqual(
            ReferenceReplaceWording.couldNotPutBackYet(course: "{course}"), wording["couldNotPutBackYet"] as? String
        )
        XCTAssertEqual(
            ReferenceReplaceWording.replacedNote(course: "{course}", group: "{group}", folder: "{folder}"),
            wording["replacedNote"] as? String
        )
        XCTAssertEqual(ReferenceReplaceWording.sections(1), "1 section")
        XCTAssertEqual(ReferenceReplaceWording.sections(3), "3 sections")
        XCTAssertEqual(ReferenceReplaceWording.pages(1), "1 page")
        XCTAssertEqual(ReferenceReplaceWording.pages(40), "40 pages")
    }

    /// The warning says what the course holds, what the backup is called in
    /// Backups, and what restoring it does (plan review M9).
    func testTheWarningNamesTheCourseTheBackupAndTheWayBack() async throws {
        try prepareWorkingFolder()
        let offer: ReferenceReplacer.Offer = await ReferenceReplacer.offer(
            toReplace: "ICS3U-2025", coursesDirectoryURL: coursesDirectoryURL, world: ReferenceReplacerTests.quietWorld()
        )
        guard case .warn(let warning) = offer else {
            return XCTFail("Replace It… was refused: \(offer)")
        }
        XCTAssertEqual(warning.title, ReferenceReplaceWording.title(course: "ICS3U", group: "2025–26"))
        // #834: the message, then the rows in the contract's order.
        XCTAssertEqual(warning.question.title, warning.title)
        XCTAssertEqual(warning.question.message, ReferenceReplaceWording.message)
        var labels: [String] = []
        for row in warning.question.rows {
            labels.append(row.label)
        }
        XCTAssertEqual(labels, [
            ReferenceReplaceWording.beingReplacedLabel, ReferenceReplaceWording.keptOnLabel,
            ReferenceReplaceWording.backedUpLabel, ReferenceReplaceWording.toUndoLabel,
        ])
        XCTAssertTrue(warning.question.rows[0].value.hasPrefix("1 section, 2 pages, "), warning.question.rows[0].value)
        XCTAssertEqual(warning.question.rows[2].value, ReferenceReplaceWording.backedUpValue(folder: "ICS3U-2025"))
        XCTAssertEqual(warning.question.rows[3].value, ReferenceReplaceWording.toUndoValue)
        XCTAssertEqual(warning.question.action, ReferenceReplaceWording.confirmButton)

        let live: ReferenceReplacer.Offer = await ReferenceReplacer.offer(
            toReplace: "ICS3U", coursesDirectoryURL: coursesDirectoryURL, world: ReferenceReplacerTests.quietWorld()
        )
        XCTAssertEqual(live, .refused(ReferenceReplaceWording.notOnTheShelf(course: "ICS3U")))
    }

    /// With no day to say, the "Kept on" row is absent, never blank (#834).
    func testWithNoDateTheKeptOnRowIsAbsent() {
        let rows: [FactsQuestionRow] = ReferenceReplaceWording.rows(
            sections: "1 section", pages: "2 pages", size: "4 KB", date: nil, folder: "ICS3U-2025"
        )
        var labels: [String] = []
        for row in rows {
            labels.append(row.label)
            XCTAssertFalse(row.value.isEmpty, row.label)
        }
        XCTAssertEqual(labels, [
            ReferenceReplaceWording.beingReplacedLabel, ReferenceReplaceWording.backedUpLabel, ReferenceReplaceWording.toUndoLabel,
        ])
    }

    // MARK: - Only a reference course

    func testOnlyAReferenceCourseIsReplaced() throws {
        try prepareWorkingFolder()
        try FileManager.default.createDirectory(
            at: coursesDirectoryURL.appendingPathComponent("_backups"), withIntermediateDirectories: true
        )
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceReplacerTests.replacingRules()["onlyAReferenceCourse"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5, "The contract's cases did not load.")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let folder: String = try XCTUnwrap(testCase["folder"] as? String)
            if folder.hasPrefix(".") {
                try ReferenceReplacerTests.writeCourse(
                    at: coursesDirectoryURL.appendingPathComponent(folder), reference: true, says: "new"
                )
            }
            let expect: String = try XCTUnwrap(testCase["expect"] as? String)
            let refusal: ReferenceReplacer.Problem? = ReferenceReplacer.refusal(
                toReplace: folder, coursesDirectoryURL: coursesDirectoryURL, world: ReferenceReplacerTests.quietWorld()
            )
            if expect == "replaces" {
                XCTAssertNil(refusal, "\(name): refused.")
            } else {
                XCTAssertEqual(refusal?.wordingKey, expect, "\(name): \(String(describing: refusal))")
            }
        }
    }

    // MARK: - Obsidian

    func testObsidianHoldsTheCourseAsTheContractSays() throws {
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceReplacerTests.replacingRules()["obsidianCases"] as? [String: Any]
        )
        let coursePath: String = try XCTUnwrap(rules["coursePath"] as? String)
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8, "The contract's cases did not load.")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var registryData: Data?
            if let registry = testCase["registry"] as? [String: Any] {
                registryData = try JSONSerialization.data(withJSONObject: registry)
            } else if testCase["registry"] as? String == "unreadable" {
                registryData = Data("{\"vaults\": {".utf8)
            }
            let holds: Bool = ReferenceReplacer.obsidianHoldsIt(
                coursePath: coursePath,
                obsidianRunning: try XCTUnwrap(testCase["obsidianRunning"] as? Bool),
                registryData: registryData
            )
            XCTAssertEqual(holds, try XCTUnwrap(testCase["expect"] as? Bool), name)
        }
    }

    // MARK: - The backup, checked

    func testTheBackupCheckFollowsTheContract() throws {
        try prepareWorkingFolder()
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceReplacerTests.replacingRules()["backupCheck"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6, "The contract's cases did not load.")
        var number: Int = 0
        for testCase in cases {
            number += 1
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let courseURL: URL = rootURL.appendingPathComponent("check-\(number)").appendingPathComponent("ICS3U-2025")
            try FileManager.default.createDirectory(at: courseURL, withIntermediateDirectories: true)
            for entry in try XCTUnwrap(testCase["onDisk"] as? [String]) {
                let entryURL: URL = courseURL.appendingPathComponent(entry)
                if entry.hasSuffix("/") {
                    try FileManager.default.createDirectory(at: entryURL, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(
                        at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try Data("x".utf8).write(to: entryURL)
                }
            }
            let check: ReferenceReplacer.BackupCheck = ReferenceReplacer.compare(
                zipNames: try XCTUnwrap(testCase["inZip"] as? [String]),
                courseDirectoryURL: courseURL,
                mayBeMissing: []
            )
            var kind: String = "couldNotBeRead"
            switch check {
            case .holdsTheCourse:
                kind = "holdsTheCourse"
            case .isMissing:
                kind = "isMissing"
            case .couldNotBeRead:
                kind = "couldNotBeRead"
            }
            XCTAssertEqual(kind, try XCTUnwrap(testCase["expect"] as? String), "\(name): \(check)")
        }
    }

    /// Through the REAL backup: an ordinary reference course is held, and a
    /// course holding a teacher's own folder called `build`, which every zip
    /// of a course leaves out, is not (plan review M3). MUST FAIL if the
    /// check accepts every name the archiver leaves out.
    func testTheRealBackupOfAFolderCalledBuildIsCaught() async throws {
        try prepareWorkingFolder()
        let old: Course = try XCTUnwrap(
            ReferenceReplacer.courseOnTheShelf(folderName: "ICS3U-2025", coursesDirectoryURL: coursesDirectoryURL)
        )
        ReferenceLock.clearLock(at: oldURL)
        try Data("x".utf8).write(to: oldURL.appendingPathComponent(".DS_Store"))
        let plain: URL = try await CourseArchiver.backUpCourse(old, coursesDirectoryURL: coursesDirectoryURL)
        let plainCheck: ReferenceReplacer.BackupCheck = await ReferenceReplacer.checkTheBackUp(plain, against: oldURL)
        guard case .holdsTheCourse(let files, let pages, _) = plainCheck else {
            return XCTFail("An ordinary backup was not taken as holding the course: \(plainCheck)")
        }
        XCTAssertEqual(files, 3, "course_config.json and two pages; .DS_Store is not counted.")
        XCTAssertEqual(pages, 2)

        let build: URL = oldURL.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("A teacher's notes.\n".utf8).write(to: build.appendingPathComponent("Notes.md"))
        let second: URL = try await CourseArchiver.backUpCourse(old, coursesDirectoryURL: coursesDirectoryURL)
        let check: ReferenceReplacer.BackupCheck = await ReferenceReplacer.checkTheBackUp(second, against: oldURL)
        XCTAssertEqual(check, .isMissing(count: 1))
    }

    /// Through the REAL archiver and the DEFAULT check (`World()`'s wiring,
    /// implementation review L2): a course whose pages carry each of the
    /// contract's `realNames` is held by its backup. MUST FAIL with the
    /// listing read from `zipinfo` alone, which prints every byte outside
    /// ASCII as `?` (implementation review H1).
    func testRealNamesOutsideASCIIAreHeldByTheRealBackup() async throws {
        try prepareWorkingFolder()
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceReplacerTests.replacingRules()["backupCheck"] as? [String: Any]
        )
        let names: [String] = try XCTUnwrap(rules["realNames"] as? [String])
        XCTAssertGreaterThanOrEqual(names.count, 6, "The contract's names did not load.")
        ReferenceLock.clearLock(at: oldURL)
        let old: Course = try XCTUnwrap(
            ReferenceReplacer.courseOnTheShelf(folderName: "ICS3U-2025", coursesDirectoryURL: coursesDirectoryURL)
        )
        for name in names {
            let pageURL: URL = oldURL.appendingPathComponent("Lessons").appendingPathComponent(name)
            try Data("A page.\n".utf8).write(to: pageURL)
            let backupURL: URL = try await CourseArchiver.backUpCourse(old, coursesDirectoryURL: coursesDirectoryURL)
            let check: ReferenceReplacer.BackupCheck = await ReferenceReplacer.World().checkTheBackUp(backupURL, oldURL)
            guard case .holdsTheCourse = check else {
                XCTFail("\(name): its real backup was not taken as holding the course: \(check)")
                continue
            }
            try FileManager.default.removeItem(at: pageURL)
        }
    }

    /// An empty file and a real backup cut short are never taken as a
    /// backup (`unreadableZips`); `tar` alone listed the cut one as whole.
    func testAnUnreadableZipIsNeverABackup() async throws {
        try prepareWorkingFolder()
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceReplacerTests.replacingRules()["backupCheck"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(rules["unreadableZips"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 2, "The contract's cases did not load.")
        ReferenceLock.clearLock(at: oldURL)
        let old: Course = try XCTUnwrap(
            ReferenceReplacer.courseOnTheShelf(folderName: "ICS3U-2025", coursesDirectoryURL: coursesDirectoryURL)
        )
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let backupURL: URL = try await CourseArchiver.backUpCourse(old, coursesDirectoryURL: coursesDirectoryURL)
            let whole: Data = try Data(contentsOf: backupURL)
            var kept: Data = Data()
            if let cutTo = testCase["cutTo"] as? Int {
                kept = whole.prefix(cutTo)
            }
            try kept.write(to: backupURL)
            let check: ReferenceReplacer.BackupCheck = await ReferenceReplacer.World().checkTheBackUp(backupURL, oldURL)
            XCTAssertEqual(check, .couldNotBeRead, name)
        }
    }

    /// A Copy a Page pass reading from the course makes it busy to a
    /// replace, and to nothing else (implementation review L3).
    func testACopyAPagePassReadingFromItIsBusy() throws {
        try prepareWorkingFolder()
        let folder: String = workingFolderURL.path
        XCTAssertFalse(ReferenceReplacer.courseIsBusy(workingFolderPath: folder, folderName: "ICS3U-2025", countingCopies: true))
        PageCopySourceReads.begin(oldURL)
        XCTAssertTrue(ReferenceReplacer.courseIsBusy(workingFolderPath: folder, folderName: "ICS3U-2025", countingCopies: true))
        XCTAssertTrue(ReferenceReplacer.courseIsBusy(workingFolderPath: folder, folderName: "ICS3U-2025", countingCopies: false))
        XCTAssertFalse(CourseActivity.courseIsBusy(folderPath: folder, courseCode: "ICS3U-2025"), "It made a preview wait.")
        PageCopySourceReads.end(oldURL)
        XCTAssertFalse(ReferenceReplacer.courseIsBusy(workingFolderPath: folder, folderName: "ICS3U-2025", countingCopies: true))
    }

    /// Keep a Copy asks the shelf rule again at Replace (implementation
    /// review L4): a course no longer in the way is not replaced.
    func testKeepACopyRefusesACourseNoLongerInTheWay() async throws {
        try prepareWorkingFolder()
        let live: Course = Course(
            code: "ICS3U", directoryURL: liveURL,
            configuration: try CourseConfiguration(contentsOf: liveURL.appendingPathComponent("course_config.json"))
        )
        let movedAway: [ReferenceCourseRule.Shelved] = [
            ReferenceCourseRule.Shelved(displayCode: "ICS3U", schoolYear: 2024, folderName: "ICS3U-2025"),
        ]
        do {
            _ = try await ReferenceCopier.keepACopy(
                of: live, replacing: "ICS3U-2025", schoolYear: 2025, coursesDirectoryURL: coursesDirectoryURL,
                shelved: movedAway, world: ReferenceReplacerTests.quietWorld()
            )
            XCTFail("A course no longer in the way was replaced.")
        } catch {
            XCTAssertEqual(error.localizedDescription, ReferenceReplaceWording.notTheCourseInTheWay(folder: "ICS3U-2025"))
        }
        XCTAssertEqual(ReferenceReplacerTests.whatItSays(oldURL), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: coursesDirectoryURL.appendingPathComponent("_backups/ICS3U-2025").path
        ), "A backup was made.")
    }

    // MARK: - The order of the act

    func testEverySequenceCase() async throws {
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceReplacerTests.replacingRules()["sequence"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12, "The contract's cases did not load.")
        for testCase in cases {
            try await run(sequenceCase: testCase)
        }
    }

    func run(sequenceCase testCase: [String: Any]) async throws {
        try prepareWorkingFolder()
        let name: String = try XCTUnwrap(testCase["name"] as? String)
        let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
        let failAt: String? = testCase["failAt"] as? String
        let busy: String? = testCase["busy"] as? String
        let obsidian: String? = testCase["obsidian"] as? String
        let live: Bool = testCase["live"] as? Bool ?? false
        let leavesTheShelf: Bool = testCase["leavesTheShelf"] as? String == "afterTheBackUp"
        if testCase["asideAlreadyThere"] as? Bool ?? false {
            try FileManager.default.createDirectory(at: asideURL, withIntermediateDirectories: true)
        }
        let liveBefore: [String: String] = try ReferenceCreationTests.digest(of: liveURL)

        try stageTheNewCourse()
        let recorder: Recorder = Recorder()
        let old: URL = oldURL
        let aside: URL = asideURL
        let staging: URL = stagingURL

        var world: ReferenceReplacer.World = ReferenceReplacer.World()
        world.isBusy = { _, _, countingCopies in
            if busy == "atTheStart" && countingCopies {
                return true
            }
            return busy == "afterTheBackUp" && !countingCopies
        }
        world.obsidianHoldsIt = { _ in
            recorder.obsidianAsked += 1
            if obsidian == "atTheStart" && recorder.obsidianAsked == 1 {
                return true
            }
            return obsidian == "afterTheBackUp" && recorder.obsidianAsked == 2
        }
        world.backUp = { course, coursesDirectoryURL in
            if failAt == "backUp" {
                recorder.steps.append("backUp:fails")
                throw NSError(domain: "test", code: 28, userInfo: [NSLocalizedDescriptionKey: "The disk is full."])
            }
            recorder.steps.append("backUp")
            let made: URL = try await CourseArchiver.backUpCourse(
                course, coursesDirectoryURL: coursesDirectoryURL, madeBy: .teacher
            )
            if leavesTheShelf {
                // Its settings, which are never locked, edited to say it is
                // not kept for reference while the backup was made.
                try Data("{\"course_code\": \"ICS3U\", \"section_numbers\": [1]}\n".utf8)
                    .write(to: old.appendingPathComponent("course_config.json"))
            }
            return made
        }
        world.checkTheBackUp = { backupURL, courseURL in
            if failAt == "checkTheBackUp" {
                recorder.steps.append("checkTheBackUp:fails")
                return .isMissing(count: 1)
            }
            recorder.steps.append("checkTheBackUp")
            return await ReferenceReplacer.checkTheBackUp(backupURL, against: courseURL)
        }
        world.move = { from, to in
            var step: String = "move"
            if from == old && to == aside {
                step = "asideOld"
            } else if from == staging && to == old {
                step = "renameNew"
            } else if from == aside && to == old {
                step = "putAsideBack"
            }
            let fails: Bool = failAt == step
                || (failAt == "renameNewAndPutAsideBack" && (step == "renameNew" || step == "putAsideBack"))
            if fails {
                recorder.steps.append(step + ":fails")
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "The rename was refused."])
            }
            recorder.steps.append(step)
            try FileManager.default.moveItem(at: from, to: to)
        }
        world.removeTree = { folderURL in
            var step: String = "remove"
            if folderURL == aside {
                step = "removeAside"
            } else if folderURL == staging {
                step = "removeStaged"
            }
            if failAt == step {
                recorder.steps.append(step + ":fails")
                return false
            }
            recorder.steps.append(step)
            return ReferenceStaging.remove(at: folderURL)
        }

        var said: String?
        do {
            _ = try await ReferenceReplacer.replace(
                ReferenceReplacer.Asked(folderName: live ? "ICS3U" : "ICS3U-2025", source: "a test course"),
                withStagedAt: stagingURL,
                coursesDirectoryURL: coursesDirectoryURL,
                world: world
            )
        } catch let problem as ReferenceReplacer.Problem {
            said = problem.wordingKey
        }
        ReferenceStaging.giveBack("ICS3U-2025", inCoursesDirectory: coursesDirectoryURL)

        XCTAssertEqual(recorder.steps, try XCTUnwrap(expect["steps"] as? [String]), "\(name): the steps")
        XCTAssertEqual(said, expect["said"] as? String, "\(name): what was said")

        // Where the old course is now.
        let oldIs: String = try XCTUnwrap(expect["old"] as? String)
        switch oldIs {
        case "inPlace":
            XCTAssertEqual(ReferenceReplacerTests.whatItSays(oldURL), "old", "\(name): the old course is not in place.")
            if !(testCase["asideAlreadyThere"] as? Bool ?? false) {
                XCTAssertFalse(FileManager.default.fileExists(atPath: asideURL.path), "\(name): an aside folder is left.")
            }
        case "aside":
            XCTAssertEqual(ReferenceReplacerTests.whatItSays(asideURL), "old", "\(name): the old course is not aside.")
        default:
            XCTAssertEqual(oldIs, "backupOnly")
            XCTAssertFalse(FileManager.default.fileExists(atPath: asideURL.path), "\(name): an aside folder is left.")
        }
        // Wherever it is, a backup that holds it, unless no backup was made.
        let backups: URL = coursesDirectoryURL.appendingPathComponent("_backups").appendingPathComponent("ICS3U-2025")
        let made: [String] = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
        let steps: [String] = try XCTUnwrap(expect["steps"] as? [String])
        if steps.contains("backUp") {
            XCTAssertEqual(made.count, 1, "\(name): \(made)")
            let listing: [String] = try XCTUnwrap(
                ReferenceReplacer.zipListing(atPath: backups.appendingPathComponent(made[0]).path)
            )
            XCTAssertTrue(listing.contains("ICS3U-2025/section1/index.md"), "\(name): the backup does not hold it.")
        } else {
            XCTAssertTrue(made.isEmpty, "\(name): a backup was made: \(made)")
        }

        // Where the new course is now.
        if try XCTUnwrap(expect["new"] as? String) == "inPlace" {
            XCTAssertEqual(ReferenceReplacerTests.whatItSays(oldURL), "new", "\(name): the new course is not in place.")
            let page: URL = oldURL.appendingPathComponent("Lessons").appendingPathComponent("Lesson.md")
            XCTAssertTrue(ReferenceLock.isLocked(page), "\(name): the new course is not locked.")
        } else {
            XCTAssertNotEqual(ReferenceReplacerTests.whatItSays(oldURL), "new", "\(name): the new course is in place.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path), "\(name): the staged course is left.")

        // The live course is never touched.
        XCTAssertEqual(try ReferenceCreationTests.digest(of: liveURL), liveBefore, "\(name): the LIVE course changed.")

        // One line, the right one.
        let event: String = try XCTUnwrap(expect["trail"] as? String)
        if event == ActivityTrail.Event.referenceCourseReplaced.rawValue {
            XCTAssertTrue(
                trail.contains("replaced ICS3U-2025 on the reference shelf (ICS3U, 2025–26) with a test course"),
                "\(name): \(trail)"
            )
            XCTAssertFalse(trail.contains("could not replace"), "\(name): \(trail)")
        } else {
            XCTAssertEqual(event, ActivityTrail.Event.referenceCourseCouldNotBeReplaced.rawValue)
            XCTAssertTrue(trail.contains("could not replace "), "\(name): \(trail)")
        }
        ReferenceLock.clearLock(at: rootURL)
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// Two replaces of one course at once: the second is refused at its
    /// claim and makes nothing (`twoAtOnce`).
    func testASecondReplaceOfTheSameCourseIsRefused() async throws {
        try prepareWorkingFolder()
        try stageTheNewCourse()
        let live: Course = Course(
            code: "ICS3U", directoryURL: liveURL,
            configuration: try CourseConfiguration(contentsOf: liveURL.appendingPathComponent("course_config.json"))
        )
        do {
            _ = try await ReferenceCopier.keepACopy(
                of: live, replacing: "ICS3U-2025", schoolYear: 2025,
                coursesDirectoryURL: coursesDirectoryURL, shelved: ReferenceReplacerTests.shelf,
                world: ReferenceReplacerTests.quietWorld()
            )
            XCTFail("A second replace of the same course went ahead.")
        } catch {
            XCTAssertEqual(error.localizedDescription, ReferenceWording.copyAlreadyBeingMade(folder: "ICS3U-2025"))
        }
        XCTAssertEqual(ReferenceReplacerTests.whatItSays(oldURL), "old")
        XCTAssertEqual(ReferenceReplacerTests.whatItSays(stagingURL), "new", "The first replace's course was touched.")
        ReferenceStaging.giveBack("ICS3U-2025", inCoursesDirectory: coursesDirectoryURL)
    }

    // MARK: - The three doors

    /// Keep a Copy for Reference… in place of the course on the shelf, then
    /// the ordinary Restore from Backup on the backup it made: the old
    /// course is back under its own folder, locked, and the replacement is
    /// in Archived. One "course restored from a backup" line.
    func testKeepACopyReplacesAndRestoreBringsTheOldOneBack() async throws {
        try prepareWorkingFolder()
        let live: Course = Course(
            code: "ICS3U", directoryURL: liveURL,
            configuration: try CourseConfiguration(contentsOf: liveURL.appendingPathComponent("course_config.json"))
        )
        let made: ReferenceCopier.Made = try await ReferenceCopier.keepACopy(
            of: live, replacing: "ICS3U-2025", schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL, shelved: ReferenceReplacerTests.shelf,
            world: ReferenceReplacerTests.quietWorld()
        )
        XCTAssertEqual(made.folderName, "ICS3U-2025")
        XCTAssertEqual(ReferenceReplacerTests.whatItSays(oldURL), "live", "The copy is not in the old course's place.")
        let replaced: CourseConfiguration = try CourseConfiguration(
            contentsOf: oldURL.appendingPathComponent("course_config.json")
        )
        XCTAssertTrue(replaced.keptForReference)
        XCTAssertEqual(replaced.referenceSchoolYear, 2025)
        XCTAssertTrue(trail.contains("kept a copy of ICS3U for reference as ICS3U-2025"), trail)
        XCTAssertTrue(trail.contains("replaced ICS3U-2025 on the reference shelf (ICS3U, 2025–26) with a copy of ICS3U"), trail)

        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: workingFolderURL)
        workspace.reloadCourses()
        var backup: BackupItem?
        for item in workspace.backupItems where item.courseCode == "ICS3U-2025" {
            backup = item
        }
        await workspace.restoreBackup(try XCTUnwrap(backup, "The replace left no backup in Backups."))
        XCTAssertNil(workspace.backupProblem)
        XCTAssertEqual(ReferenceReplacerTests.whatItSays(oldURL), "old", "Restore did not put the old course back.")
        let page: URL = oldURL.appendingPathComponent("Lessons").appendingPathComponent("Lesson.md")
        XCTAssertTrue(ReferenceLock.isLocked(page), "The restored reference course is not locked again.")
        var archived: Bool = false
        for item in workspace.archivedItems where item.courseCode == "ICS3U-2025" {
            archived = true
        }
        XCTAssertTrue(archived, "The replacement is not in Archived.")
        let restoredLines: [String] = ReferenceReplacerTests.lines(in: trail, containing: "restored ICS3U (ICS3U-2025) from ICS3U-2025_backup_")
        XCTAssertEqual(restoredLines.count, 1, trail)
        XCTAssertTrue(restoredLines.first?.contains("; kept for reference") ?? false, trail)
        XCTAssertTrue(restoredLines.first?.contains("is in Archived as ICS3U-2025_") ?? false, trail)
    }

    /// The wizard's door: a course made by setup in the old course's hidden
    /// folder replaces it, and a replace asked for a DIFFERENT course than
    /// the one in the way is refused like any clash.
    func testTheWizardReplacesOnlyTheCourseInTheWay() async throws {
        try prepareWorkingFolder()
        let shelved: [ReferenceCourseRule.Shelved] = [
            ReferenceCourseRule.Shelved(displayCode: "ICS3U", schoolYear: 2025, folderName: "ICS3U-2025"),
        ]
        XCTAssertThrowsError(try ReferenceCreation.prepare(
            configuration: ["course_code": "ICS3U"], schoolYear: 2025, coursesDirectoryURL: coursesDirectoryURL,
            existingFolderNames: ["ICS3U", "ICS3U-2025"], shelved: shelved, replacing: "ICS3U-2024"
        ))
        let prepared: ReferenceCreation.Prepared = try ReferenceCreation.prepare(
            configuration: ["course_code": "ICS3U", "section_numbers": [1, 2]], schoolYear: 2025,
            coursesDirectoryURL: coursesDirectoryURL,
            existingFolderNames: ["ICS3U", "ICS3U-2025"], shelved: shelved, replacing: "ICS3U-2025"
        )
        XCTAssertEqual(prepared.folderName, "ICS3U-2025")
        XCTAssertEqual(prepared.stagingURL.lastPathComponent, ReferenceStaging.stagingName(for: "ICS3U-2025"))
        try ReferenceCreationTests.writeWhatSetupWrites(into: prepared.stagingURL, withPages: true)
        let made: ReferenceCopier.Made = try await ReferenceCreation.finishByReplacing(
            prepared, setupSucceeded: true, wasStopped: false,
            transcript: "📖 \(ReferenceCreation.pagesInstalledMarker): 1 page",
            world: ReferenceReplacerTests.quietWorld()
        )
        XCTAssertEqual(made.folderName, "ICS3U-2025")
        let page: URL = oldURL.appendingPathComponent("Lessons").appendingPathComponent("Variables.md")
        XCTAssertTrue(ReferenceLock.isLocked(page), "The new course is not in place, locked.")
        XCTAssertNotEqual(ReferenceReplacerTests.whatItSays(oldURL), "old", "The old course is still there.")
        XCTAssertTrue(trail.contains("created ICS3U for reference as ICS3U-2025"), trail)
        XCTAssertTrue(trail.contains("with \(ReferenceCreation.replacementSource)"), trail)
        XCTAssertFalse(ReferenceStaging.claimedStagingKeys.contains(
            ReferenceStaging.claimKey(for: "ICS3U-2025", inCoursesDirectory: coursesDirectoryURL)
        ), "The claim was not given back.")
    }

    /// The replacement keeps the replaced course's group (#572, third
    /// piece): it takes the old folder name, and the group is the folder's.
    /// The warning names the group the teacher made, and a course chosen
    /// for that group in the wizard replaces the one in it.
    func testTheReplacementKeepsTheReplacedCoursesGroup() async throws {
        try prepareWorkingFolder()
        try FileManager.default.createDirectory(
            at: coursesDirectoryURL.appendingPathComponent(".internal"), withIntermediateDirectories: true
        )
        try Data((
            "{\"version\": 1, \"groups\": [{\"id\": \"g-00000001\", \"name\": \"From colleagues\"}], "
            + "\"placements\": {\"ICS3U-2025\": \"g-00000001\"}}"
        ).utf8).write(to: ReferenceShelfStore.fileURL(inCoursesDirectory: coursesDirectoryURL))

        let offer: ReferenceReplacer.Offer = await ReferenceReplacer.offer(
            toReplace: "ICS3U-2025", coursesDirectoryURL: coursesDirectoryURL, world: ReferenceReplacerTests.quietWorld()
        )
        guard case .warn(let warning) = offer else {
            return XCTFail("Replace It… was refused: \(offer)")
        }
        XCTAssertEqual(warning.title, ReferenceReplaceWording.title(course: "ICS3U", group: "From colleagues"))

        let shelved: [ReferenceCourseRule.Shelved] = [ReferenceCourseRule.Shelved(
            displayCode: "ICS3U", schoolYear: 2025, folderName: "ICS3U-2025", madeGroupID: "g-00000001"
        )]
        // In its YEAR nothing is in the way: the course in From colleagues
        // is in no year group.
        XCTAssertNil(ReferenceCourseRule.courseInTheWay(placing: "ICS3U", inYear: 2025, among: shelved))
        let prepared: ReferenceCreation.Prepared = try ReferenceCreation.prepare(
            configuration: ["course_code": "ICS3U", "section_numbers": [1]], schoolYear: 2026,
            coursesDirectoryURL: coursesDirectoryURL,
            existingFolderNames: ["ICS3U", "ICS3U-2025"], shelved: shelved, replacing: "ICS3U-2025",
            madeGroupID: "g-00000001"
        )
        XCTAssertEqual(prepared.folderName, "ICS3U-2025")
        try ReferenceCreationTests.writeWhatSetupWrites(into: prepared.stagingURL, withPages: true)
        _ = try await ReferenceCreation.finishByReplacing(
            prepared, setupSucceeded: true, wasStopped: false,
            transcript: "📖 \(ReferenceCreation.pagesInstalledMarker): 1 page",
            world: ReferenceReplacerTests.quietWorld()
        )
        XCTAssertNotEqual(ReferenceReplacerTests.whatItSays(oldURL), "old", "The old course is still there.")
        let arrangement: ReferenceShelf.Arrangement = ReferenceShelfStore.read(
            inCoursesDirectory: coursesDirectoryURL
        ).arrangement
        XCTAssertEqual(arrangement.placements["ICS3U-2025"], "g-00000001", "The replacement left the group.")
        XCTAssertTrue(trail.contains("(ICS3U, From colleagues)"), trail)
    }

    /// An import of one course replaces only the course it was told to; the
    /// same import without the teacher's Replace is refused as before.
    func testAnImportReplacesOnlyWhenAskedAndOnlyThatCourse() async throws {
        try prepareWorkingFolder()
        let elsewhere: URL = rootURL.appendingPathComponent("Last year").appendingPathComponent("ICS3U")
        try ReferenceReplacerTests.writeCourse(at: elsewhere, reference: false, says: "new")
        let outcome: ReferenceImportSource.Outcome = ReferenceImportSource.resolve(
            chosen: elsewhere, workingFolderURL: workingFolderURL, leavingBehind: ReferenceImporter.leftBehindNames
        )
        guard case .found(let source) = outcome else {
            return XCTFail("The folder was refused: \(outcome)")
        }
        let row: ReferenceImportSource.FoundCourse = try XCTUnwrap(source.courses.first)
        let shelved: [ReferenceCourseRule.Shelved] = [
            ReferenceCourseRule.Shelved(displayCode: "ICS3U", schoolYear: 2025, folderName: "ICS3U-2025"),
        ]

        for asked in [nil, "ICS3U-2024"] as [String?] {
            let results: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
                [ReferenceImporter.Request(course: row, schoolYear: 2025, replacing: asked)],
                into: coursesDirectoryURL, existingFolderNames: ["ICS3U", "ICS3U-2025"], alreadyShelved: shelved,
                from: source.rootURL, replaceWorld: ReferenceReplacerTests.quietWorld(), progress: { _ in }
            )
            guard case .notImported = results.first else {
                return XCTFail("\(String(describing: asked)): imported without a replace of the course in the way.")
            }
            XCTAssertEqual(ReferenceReplacerTests.whatItSays(oldURL), "old")
        }

        let results: [ReferenceImporter.Outcome] = await ReferenceImporter.importCourses(
            [ReferenceImporter.Request(course: row, schoolYear: 2025, replacing: "ICS3U-2025")],
            into: coursesDirectoryURL, existingFolderNames: ["ICS3U", "ICS3U-2025"], alreadyShelved: shelved,
            from: source.rootURL, replaceWorld: ReferenceReplacerTests.quietWorld(), progress: { _ in }
        )
        guard case .imported(let made) = results.first else {
            return XCTFail("Not imported: \(results)")
        }
        XCTAssertEqual(made.folderName, "ICS3U-2025")
        XCTAssertEqual(ReferenceReplacerTests.whatItSays(oldURL), "new")
        XCTAssertEqual(ReferenceReplacerTests.whatItSays(elsewhere), "new", "The source was touched.")
        XCTAssertTrue(trail.contains("with a course imported from ICS3U"), trail)
    }

    // MARK: - Settling a replace that did not finish

    func testEverySweepCase() throws {
        let rules: [String: Any] = try XCTUnwrap(
            try ReferenceReplacerTests.replacingRules()["sweepCases"] as? [String: Any]
        )
        let cases: [[String: Any]] = try XCTUnwrap(rules["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5, "The contract's cases did not load.")
        for testCase in cases {
            try run(sweepCase: testCase)
        }
    }

    func run(sweepCase testCase: [String: Any]) throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reference-sweep-\(UUID().uuidString)")
        workingFolderURL = rootURL.appendingPathComponent("workspace")
        coursesDirectoryURL = workingFolderURL.appendingPathComponent("courses")
        let previousStore: ProblemReportStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail"))
        defer {
            ActivityTrail.store = previousStore
            ReferenceStaging.claimedStagingKeys = []
            ReferenceLock.clearLock(at: rootURL)
            try? FileManager.default.removeItem(at: rootURL)
        }

        let name: String = try XCTUnwrap(testCase["name"] as? String)
        for entry in try XCTUnwrap(testCase["before"] as? [String]) {
            let says: String = entry.hasPrefix(ReferenceReplacer.asidePrefix) ? "old" : "new"
            try ReferenceReplacerTests.writeCourse(
                at: coursesDirectoryURL.appendingPathComponent(entry), reference: true, says: says
            )
        }
        // A REAL backup: of the old copy, under the course's own name, or
        // of something else under a backup's name (implementation review L1).
        let backupKind: String = try XCTUnwrap(testCase["backup"] as? String)
        if backupKind != "none" {
            let backups: URL = coursesDirectoryURL.appendingPathComponent("_backups").appendingPathComponent("ICS3U-2025")
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            let source: URL = rootURL.appendingPathComponent("zip-source").appendingPathComponent("ICS3U-2025")
            if backupKind == "holdsIt" {
                try FileManager.default.createDirectory(
                    at: source.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: asideURL, to: source)
            } else {
                try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
                try Data("Something else.\n".utf8).write(to: source.appendingPathComponent("README.md"))
            }
            let zipper: Process = Process()
            zipper.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zipper.arguments = ["-r", "-q", "-X", backups.appendingPathComponent("ICS3U-2025_backup_2026-11-13_010000.zip").path, "ICS3U-2025"]
            zipper.currentDirectoryURL = source.deletingLastPathComponent()
            try zipper.run()
            zipper.waitUntilExit()
            XCTAssertEqual(zipper.terminationStatus, 0, name)
        }
        for entry in try XCTUnwrap(testCase["before"] as? [String]) {
            ReferenceLock.lock(courseDirectory: coursesDirectoryURL.appendingPathComponent(entry))
        }
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)
        try Data("#!/bin/bash\n".utf8).write(to: workingFolderURL.appendingPathComponent("preview.sh"))
        if try XCTUnwrap(testCase["someoneIsReplacingIt"] as? Bool) {
            ReferenceStaging.claimedStagingKeys.insert(
                ReferenceStaging.claimKey(for: "ICS3U-2025", inCoursesDirectory: coursesDirectoryURL)
            )
        }

        // The reading a window makes of the folder, sweeps and all.
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: workingFolderURL)
        workspace.reloadCourses()

        let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
        var after: [String] = []
        for child in try FileManager.default.contentsOfDirectory(atPath: coursesDirectoryURL.path) {
            if child == "_backups" || child == ".internal" {
                continue
            }
            after.append(child)
        }
        after.sort()
        var expected: [String] = try XCTUnwrap(expect["after"] as? [String])
        expected.sort()
        XCTAssertEqual(after, expected, "\(name): what is in courses/ afterwards")

        let oldIsBack: Bool = ReferenceReplacerTests.whatItSays(
            coursesDirectoryURL.appendingPathComponent("ICS3U-2025")
        ) == "old"
        XCTAssertEqual(oldIsBack, try XCTUnwrap(expect["theOldCourseIsBack"] as? Bool), name)
        if oldIsBack {
            var listed: Bool = false
            for course in workspace.courses where course.code == "ICS3U-2025" {
                listed = true
            }
            XCTAssertTrue(listed, "\(name): the course put back is not in the list this reading made.")
        }

        let text: String = ActivityTrail.store.activityText(includingPrompts: true)
        let events: [String] = try XCTUnwrap(expect["trail"] as? [String])
        let putRight: Bool = text.contains("back on the reference shelf — a replace of it did not finish")
            || text.contains("tidied away the old copy of ICS3U-2025 left by a replace — the backup ICS3U-2025_backup_2026-11-13_010000.zip was opened and holds it")
        XCTAssertEqual(
            putRight, events.contains(ActivityTrail.Event.unfinishedReplaceOfAReferenceCoursePutRight.rawValue),
            "\(name): \(text)"
        )
        XCTAssertEqual(
            text.contains("tidied away an unfinished import"),
            events.contains(ActivityTrail.Event.unfinishedImportForReferenceTidiedAway.rawValue),
            "\(name): \(text)"
        )
    }

    // MARK: - Every whole-course restore leaves a line

    /// A LIVE course restored from its backup leaves one line; a refused
    /// restore leaves none. MUST FAIL without the line in `restoreBackup`.
    func testEveryWholeCourseRestoreLeavesOneLine() async throws {
        try prepareWorkingFolder()
        let workspace: WorkspaceModel = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: workingFolderURL)
        workspace.reloadCourses()
        var live: Course?
        for course in workspace.courses where course.code == "ICS3U" {
            live = course
        }
        let backupURL: URL = try await CourseArchiver.backUpCourse(
            try XCTUnwrap(live), coursesDirectoryURL: coursesDirectoryURL
        )
        workspace.reloadCourses()
        var item: BackupItem?
        for candidate in workspace.backupItems where candidate.fileURL.lastPathComponent == backupURL.lastPathComponent {
            item = candidate
        }
        let backup: BackupItem = try XCTUnwrap(item)

        // Refused: a preview of the course is running.
        _ = try PreviewLeases.lease(folderPath: workingFolderURL.path, courseCode: "ICS3U", sectionNumber: 1)
        await workspace.restoreBackup(backup)
        PreviewLeases.reset()
        XCTAssertNotNil(workspace.backupProblem)
        XCTAssertTrue(ReferenceReplacerTests.lines(in: trail, containing: "restored ICS3U").isEmpty, trail)

        workspace.backupProblem = nil
        await workspace.restoreBackup(backup)
        XCTAssertNil(workspace.backupProblem)
        let lines: [String] = ReferenceReplacerTests.lines(in: trail, containing: "restored ICS3U (ICS3U) from \(backupURL.lastPathComponent)")
        XCTAssertEqual(lines.count, 1, trail)
        XCTAssertTrue(lines.first?.hasSuffix("; a course you teach") ?? false, trail)

        // A whole course put back from Archived leaves the line too
        // (implementation review L5). MUST FAIL without it in `restore`.
        try FileManager.default.removeItem(at: liveURL)
        workspace.reloadCourses()
        var archived: ArchivedItem?
        for candidate in workspace.archivedItems where candidate.courseCode == "ICS3U" && candidate.sectionNumber == nil {
            archived = candidate
        }
        let archive: ArchivedItem = try XCTUnwrap(archived, "The restore made no archive.")
        workspace.restore(archive)
        XCTAssertNil(workspace.restoreProblem)
        XCTAssertEqual(ReferenceReplacerTests.whatItSays(liveURL), "live")
        let fromArchived: [String] = ReferenceReplacerTests.lines(
            in: trail, containing: "restored ICS3U (ICS3U) from Archived, \(archive.fileURL.lastPathComponent)"
        )
        XCTAssertEqual(fromArchived.count, 1, trail)
    }

    // MARK: - Helpers

    /// The shelf as the fixture has it: ICS3U-2025 in 2025–26.
    static let shelf: [ReferenceCourseRule.Shelved] = [
        ReferenceCourseRule.Shelved(displayCode: "ICS3U", schoolYear: 2025, folderName: "ICS3U-2025"),
    ]

    static func lines(in text: String, containing fragment: String) -> [String] {
        var found: [String] = []
        for line in text.components(separatedBy: "\n") where line.contains(fragment) {
            found.append(line)
        }
        return found
    }
}
