import XCTest
@testable import QuartzTeachers

/// Runs `contracts/course-management.json` → `backups.restoreWholeCourse`
/// (#909): every fault case through the real engine on the fixture the
/// contract describes, every recovery case through the rule, every refusal,
/// space, summary, disk-full and reason case, the names kept in place, and
/// every sentence. Windows runs the same cases against its own code.
final class RestoreWholeCourseContractTests: XCTestCase {

    // MARK: - Functions: the fault cases, through the engine

    /// Every `faultCases` case on a fresh fixture.
    @MainActor
    func testEveryFaultCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try RestoreWholeCourseContractTests.block()["faultCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 17, "faultCases has shrunk")
        for testCase in cases {
            try runFaultCase(testCase)
        }
    }

    @MainActor
    private func runFaultCase(_ testCase: [String: Any]) throws {
        let name: String = try XCTUnwrap(testCase["name"] as? String)
        let fault: [String: Any] = (testCase["fault"] as? [String: Any]) ?? [:]
        let fixture: WholeCourseFixture = try WholeCourseFixture(
            smallBackupMarker: fault["smallBackupMarker"] as? Bool ?? false,
            backupSettingsUnreadable: fault["backupSettingsUnreadable"] as? Bool ?? false
        )
        defer { fixture.tearDown() }
        if fault["noCourse"] as? Bool == true {
            try FileManager.default.removeItem(at: fixture.courseURL)
        }
        if let locked = fault["lockedAtTop"] as? String {
            XCTAssertEqual(lchflags(fixture.courseURL.appendingPathComponent(locked).path, UInt32(UF_IMMUTABLE)), 0, name)
        }
        if let readOnly = fault["readOnlyAtTop"] as? String {
            XCTAssertEqual(chmod(fixture.courseURL.appendingPathComponent(readOnly).path, 0o555), 0, name)
        }
        if fault["readOnlyCourseFolder"] as? Bool == true {
            XCTAssertEqual(chmod(fixture.courseURL.path, 0o555), 0, name)
        }
        if let lockedInside = fault["lockedInside"] as? String {
            XCTAssertEqual(lchflags(fixture.courseURL.appendingPathComponent(lockedInside).path, UInt32(UF_IMMUTABLE)), 0, name)
        }
        let live: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)

        var moves: [String] = []
        let hooks: RestoreSwap.Hooks = fixture.hooks(
            failForward: fault["failForward"] as? Int,
            failBack: fault["failBack"] as? Int,
            intruder: fault["intruder"] as? String,
            seen: { (move: String) in
                moves.append(move)
            }
        )
        var thrown: Error?
        do {
            try WholeCourseRestore.restore(
                fromZipAt: fixture.zipURL,
                courseCode: "ICS3U",
                coursesDirectoryURL: fixture.coursesDirectoryURL,
                beforeTheSwap: { (_: URL) throws in
                    if fault["refusedBeforeTheSwap"] as? Bool == true {
                        throw CourseRestorer.Problem.refused("REFUSED BEFORE THE SWAP")
                    }
                },
                hooks: hooks
            )
        } catch {
            thrown = error
        }

        if let expectMoves = testCase["expectMoves"] as? [String] {
            XCTAssertEqual(moves, expectMoves, name)
        }
        if fault["readOnlyCourseFolder"] as? Bool == true {
            XCTAssertEqual(chmod(fixture.courseURL.path, 0o755), 0, name)
        }
        let now: [String: Data] = try WholeCourseFixture.snapshot(of: fixture.courseURL)
        if let settingsInTheCourse = testCase["settingsInTheCourse"] as? Bool {
            // The implementation review's I1: a course that is a mix never
            // has its settings, so nothing builds or deploys it.
            XCTAssertEqual(
                RestoreSwap.itemExists(at: fixture.courseURL.appendingPathComponent("course_config.json")),
                settingsInTheCourse, "\(name): the course's settings"
            )
        }
        let expectedCourse: String = try XCTUnwrap(testCase["course"] as? String, name)
        switch expectedCourse {
        case "asItWas":
            XCTAssertEqual(now, live, "\(name): the course is not as it was")
        case "theBackup":
            XCTAssertEqual(now, fixture.backupWithWhatIsKeptInPlace(liveGit: live[".git/HEAD"]), "\(name): the course is not the backup's")
        case "mix":
            XCTAssertNotEqual(now, live, name)
            XCTAssertNotEqual(now, fixture.backupWithWhatIsKeptInPlace(liveGit: live[".git/HEAD"]), name)
            // Nothing lost: every original is in the course or kept.
            let kept: [String: Data] = try fixture.everythingKept()
            for (path, bytes) in live where now[path] != bytes && kept[path] != bytes {
                XCTFail("\(name): \(path) is in neither the course nor the kept folder")
            }
        default:
            XCTFail("\(name): unknown course \(expectedCourse)")
        }
        XCTAssertEqual(fixture.somethingWasKept(), try XCTUnwrap(testCase["kept"] as? Bool, name), "\(name): kept")
        let staging: String = try XCTUnwrap(testCase["staging"] as? String, name)
        XCTAssertEqual(fixture.leftInRestoring() == 0, staging == "removed", "\(name): staging")

        let says: String? = testCase["says"] as? String
        guard let says else {
            XCTAssertNil(thrown, "\(name): \(String(describing: thrown))")
            return
        }
        let said: String = try XCTUnwrap(thrown, "\(name): nothing was said").localizedDescription
        switch says {
        case "leftAsItWas":
            XCTAssertTrue(said.hasPrefix("ICS3U was left as it was, because the restore could not finish: "), "\(name): \(said)")
            XCTAssertFalse(RestoreSwap.mentionsStaging(said), "\(name): a staging path was shown: \(said)")
        case "leftAsItWas+newcomersKept":
            XCTAssertTrue(said.hasPrefix("ICS3U was left as it was, because the restore could not finish: "), "\(name): \(said)")
            XCTAssertTrue(said.contains("Files made in ICS3U while the restore was unfinished are in the folder \"courses/_backups/ICS3U/ICS3U made while a restore was unfinished "), "\(name): \(said)")
        case "leftAsItWasLocked":
            let lockedName: String = try XCTUnwrap(testCase["lockedName"] as? String, name)
            XCTAssertEqual(
                said,
                RestoreWholeCourseWording.leftAsItWasLocked(course: "ICS3U", name: lockedName) + " " + RestoreWholeCourseWording.unlockIt,
                name
            )
        case "leftAsItWasFolderLocked":
            XCTAssertEqual(
                said,
                RestoreWholeCourseWording.leftAsItWasFolderLocked(course: "ICS3U") + " " + RestoreWholeCourseWording.unlockIt,
                name
            )
        case "stoppedPartWay":
            XCTAssertTrue(said.hasPrefix("The restore of ICS3U stopped part way"), "\(name): \(said)")
            XCTAssertFalse(said.contains(RestoreWholeCourseWording.notInTheSidebar(course: "ICS3U")), name)
        case "stoppedPartWay+notInTheSidebar":
            XCTAssertTrue(said.hasPrefix("The restore of ICS3U stopped part way"), "\(name): \(said)")
            XCTAssertTrue(
                said.contains(
                    RestoreWholeCourseWording.notInTheSidebar(course: "ICS3U") + " "
                    + RestoreWholeCourseWording.restoreAgainToPutItRight(course: "ICS3U")
                ),
                "\(name): \(said)"
            )
        case "backups.sharedMedia mediaNotPutBack":
            XCTAssertEqual(said, SharedMediaStore.Problem.mediaNotPutBack(fixture.zipURL.lastPathComponent).localizedDescription, name)
        case "archiveUnreadable":
            XCTAssertEqual(said, CourseRestorer.Problem.archiveUnreadable("its course settings could not be read").localizedDescription, name)
        case "the refusal":
            XCTAssertEqual(said, "REFUSED BEFORE THE SWAP", name)
        default:
            XCTFail("\(name): unknown says \(says)")
        }
        // A stop writes the stopped-part-way line; a restore left as it was
        // writes the left-as-it-was line (the implementation review's I4); a
        // refusal is noted by the door that refused, which knows which one.
        let stoppedLine: String = "a whole-course restore stopped part way and could not move every file back"
        let leftLine: String = "a whole-course restore from \(fixture.zipURL.lastPathComponent) did not go ahead, and the course was left as it was: "
        let trail: String? = testCase["trail"] as? String
        XCTAssertEqual(fixture.trailText().contains(stoppedLine), trail == "course restore stopped part way", "\(name): trail")
        XCTAssertEqual(fixture.trailText().contains(leftLine), trail == "course restore left as it was", "\(name): trail")
        for line in fixture.trailText().components(separatedBy: "\n") where line.contains("a whole-course restore") {
            XCTAssertEqual(LogRedactor.redacting(line), line, "\(name): the trail line passes the redactor unchanged")
        }
    }

    // MARK: - Functions: the rule and the pure cases

    /// Every `recoveryCases` case through `RestoreSettleRule.decide`.
    func testEveryRecoveryCase() throws {
        let block: [String: Any] = try RestoreWholeCourseContractTests.block()
        let cases: [[String: Any]] = try XCTUnwrap(block["recoveryCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 13, "recoveryCases has shrunk")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let facts: [String: Any] = try XCTUnwrap(testCase["facts"] as? [String: Any], name)
            var phase: RestoreSwap.Phase? = nil
            if let phaseName = facts["phase"] as? String {
                phase = try XCTUnwrap(RestoreSwap.Phase(rawValue: phaseName), name)
            }
            let decided: (action: RestoreSettleRule.Action, says: RestoreSettleRule.Saying?) = RestoreSettleRule.decide(
                RestoreSettleRule.Facts(
                    hasRecord: try XCTUnwrap(facts["hasRecord"] as? Bool, name),
                    phase: phase,
                    ownerIsAlive: try XCTUnwrap(facts["ownerIsAlive"] as? Bool, name),
                    claimedByALiveSettler: try XCTUnwrap(facts["claimedByALiveSettler"] as? Bool, name),
                    writtenHere: try XCTUnwrap(facts["writtenHere"] as? Bool, name),
                    ageSeconds: try XCTUnwrap(facts["ageSeconds"] as? Double, name),
                    holdsOnlyAnUnpack: try XCTUnwrap(facts["holdsOnlyAnUnpack"] as? Bool, name),
                    anOriginalIsAtNeitherEnd: try XCTUnwrap(facts["anOriginalIsAtNeitherEnd"] as? Bool, name)
                )
            )
            XCTAssertEqual(decided.action.rawValue, try XCTUnwrap(testCase["action"] as? String, name), name)
            XCTAssertEqual(decided.says?.rawValue, testCase["says"] as? String, name)
        }
        let waits: [String: Any] = try XCTUnwrap(block["recoveryWaits"] as? [String: Any])
        XCTAssertEqual(RestoreSettleRule.unrecordedWaitSeconds, waits["unrecordedSeconds"] as? Double)
        XCTAssertEqual(RestoreSettleRule.anotherComputersWaitSeconds, waits["anotherComputersSeconds"] as? Double)
    }

    /// Every `refusalCases` case through `WholeCourseRestore.refusal`.
    @MainActor
    func testEveryRefusalCase() throws {
        let cases: [[String: Any]] = try XCTUnwrap(try RestoreWholeCourseContractTests.block()["refusalCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7, "refusalCases has shrunk")
        for testCase in cases {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let facts: [String: Any] = try XCTUnwrap(testCase["facts"] as? [String: Any], name)
            var given: WholeCourseRestore.RefusalFacts = WholeCourseRestore.RefusalFacts()
            given.busyHere = try XCTUnwrap(facts["busyHere"] as? Bool, name)
            given.revisingAssistant = facts["revisingAssistant"] as? String
            given.unsettledRestore = try XCTUnwrap(facts["unsettledRestore"] as? Bool, name)
            given.earlierRestoreLeftOver = facts["earlierRestoreLeftOver"] as? Bool ?? false
            given.buildingElsewhere = try XCTUnwrap(facts["buildingElsewhere"] as? Bool, name)
            XCTAssertEqual(WholeCourseRestore.refusal(given)?.rawValue, testCase["refusal"] as? String, name)
        }
        // The sentences each refusal says are the ones the contract names.
        XCTAssertEqual(
            WholeCourseRestore.sentence(for: .courseIsBeingBuiltElsewhere, courseCode: "ICS3U", assistant: nil),
            AssistWording.courseIsBeingBuiltElsewhere(course: "ICS3U")
        )
        XCTAssertEqual(
            WholeCourseRestore.sentence(for: .claudeIsRevisingTheCourseRestore, courseCode: "ICS3U", assistant: "Claude"),
            AssistWording.sessionIsRevisingTheCourse(course: "ICS3U", then: "restore", assistant: "Claude")
        )
        XCTAssertEqual(
            WholeCourseRestore.sentence(for: .anotherRestoreUnderWay, courseCode: "ICS3U", assistant: nil),
            RestoreWholeCourseWording.anotherRestoreUnderWay(course: "ICS3U")
        )
        XCTAssertEqual(
            WholeCourseRestore.sentence(for: .anEarlierRestoreDidNotFinish, courseCode: "ICS3U", assistant: nil),
            RestoreWholeCourseWording.anEarlierRestoreDidNotFinish(course: "ICS3U")
        )
    }

    /// Every `spaceCases`, `summaryCases`, `diskFullCases` and `reasonCases`
    /// case.
    func testTheSpaceSummaryDiskFullAndReasonCases() throws {
        let block: [String: Any] = try RestoreWholeCourseContractTests.block()
        for testCase in try XCTUnwrap(block["spaceCases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            var courseBytes: Int64? = nil
            if let bytes = testCase["courseBytes"] as? Int {
                courseBytes = Int64(bytes)
            }
            let shortfall: Int64? = WholeCourseRestore.shortfall(
                courseBytes: courseBytes,
                unpackedBytes: Int64(try XCTUnwrap(testCase["unpackedBytes"] as? Int, name)),
                free: Int64(try XCTUnwrap(testCase["free"] as? Int, name))
            )
            var expected: Int64? = nil
            if let bytes = testCase["shortfall"] as? Int {
                expected = Int64(bytes)
            }
            XCTAssertEqual(shortfall, expected, name)
        }
        for testCase in try XCTUnwrap(block["summaryCases"] as? [[String: Any]]) {
            let summary: String = try XCTUnwrap(testCase["summary"] as? String)
            var expected: Int64? = nil
            if let bytes = testCase["bytes"] as? Int {
                expected = Int64(bytes)
            }
            XCTAssertEqual(WholeCourseRestore.uncompressedSize(inSummary: summary), expected, summary)
        }
        for testCase in try XCTUnwrap(block["diskFullCases"] as? [[String: Any]]) {
            let message: String = try XCTUnwrap(testCase["message"] as? String)
            XCTAssertEqual(RestoreSwap.saysTheDiskIsFull(message), try XCTUnwrap(testCase["diskFull"] as? Bool), message)
        }
        for testCase in try XCTUnwrap(block["reasonCases"] as? [[String: Any]]) {
            let name: String = try XCTUnwrap(testCase["name"] as? String)
            let given: [String: Any] = try XCTUnwrap(testCase["error"] as? [String: Any], name)
            var error: Error = NSError(domain: "test", code: 0)
            if let code = given["posix"] as? Int {
                error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
                    NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: code)
                ])
            } else if let message = given["message"] as? String {
                error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
            XCTAssertEqual(RestoreSwap.reasonWithoutStagingPaths(error), testCase["reason"] as? String, name)
        }
    }

    /// The names kept in place are the contract's, and every one of them is
    /// a name backups leave out.
    @MainActor
    func testTheNamesKeptInPlaceAreTheContracts() throws {
        let listed: [String] = try XCTUnwrap(try RestoreWholeCourseContractTests.block()["keptInPlace"] as? [String])
        XCTAssertEqual(WholeCourseRestore.keptInPlace, listed)
        for name in listed {
            XCTAssertTrue(CourseArchiver.excludedFromArchives.contains(name), name)
        }
        XCTAssertFalse(listed.contains(BuildOutputLocation.linkName), "the built site's link goes with the old copy")
    }

    /// Every sentence equals the contract's template, filled with the same
    /// values.
    func testEverySentenceIsTheContractsTemplate() throws {
        let block: [String: Any] = try RestoreWholeCourseContractTests.block()
        let wording: [String: Any] = try XCTUnwrap(block["wording"] as? [String: Any])
        // The per-platform words, as deployTokens.placeholders carries
        // {deployingSettings} (the implementation review's I6).
        let placeholders: [String: Any] = try XCTUnwrap(block["placeholders"] as? [String: Any])
        let unlockWords: [String: String] = try XCTUnwrap(placeholders["unlockInTheFileManager"] as? [String: String])
        XCTAssertEqual(unlockWords["mac"], RestoreWholeCourseWording.unlockInTheFileManagerOnThisPlatform)
        XCTAssertNotNil(unlockWords["windows"], "Windows has its own words")
        XCTAssertEqual(wording["unlockIt"] as? String, RestoreWholeCourseWording.unlockItTemplate)
        XCTAssertTrue(RestoreWholeCourseWording.unlockItTemplate.contains(RestoreWholeCourseWording.unlockInTheFileManagerPlaceholder))
        XCTAssertFalse(RestoreWholeCourseWording.unlockIt.contains(RestoreWholeCourseWording.unlockInTheFileManagerPlaceholder))
        let keptAt: String = "courses/_backups/ICS3U/ICS3U before a restore 2026-11-14_031500"
        func filled(_ key: String, reason: String = "", name: String = "", size: String = "") throws -> String {
            let template: String = try XCTUnwrap(wording[key] as? String, key)
            return template
                .replacingOccurrences(of: "{CODE}", with: "ICS3U")
                .replacingOccurrences(of: "{REASON}", with: reason)
                .replacingOccurrences(of: "{NAME}", with: name)
                .replacingOccurrences(of: "{SIZE}", with: size)
                .replacingOccurrences(of: "{KEPT}", with: keptAt)
                .replacingOccurrences(of: "{unlockInTheFileManager}", with: unlockWords["mac"] ?? "")
        }
        XCTAssertEqual(RestoreWholeCourseWording.leftAsItWas(course: "ICS3U", reason: "disk full"), try filled("leftAsItWas", reason: "disk full"))
        XCTAssertEqual(RestoreWholeCourseWording.leftAsItWasLocked(course: "ICS3U", name: "index.md"), try filled("leftAsItWasLocked", name: "index.md"))
        XCTAssertEqual(RestoreWholeCourseWording.unlockIt, try filled("unlockIt"))
        XCTAssertEqual(RestoreWholeCourseWording.leftAsItWasFolderLocked(course: "ICS3U"), try filled("leftAsItWasFolderLocked"))
        XCTAssertEqual(RestoreWholeCourseWording.restoreAgainToPutItRight(course: "ICS3U"), try filled("restoreAgainToPutItRight"))
        XCTAssertEqual(RestoreWholeCourseWording.didNotFinishFromArchived(course: "ICS3U"), try filled("didNotFinishFromArchived"))
        XCTAssertEqual(RestoreWholeCourseWording.anEarlierRestoreDidNotFinish(course: "ICS3U"), try filled("anEarlierRestoreDidNotFinish"))
        XCTAssertEqual(RestoreWholeCourseWording.unfinishedOnAnotherComputer(course: "ICS3U"), try filled("unfinishedOnAnotherComputer"))
        XCTAssertEqual(RestoreWholeCourseWording.leftAsItWasInUse(course: "ICS3U", name: "index.md"), try filled("leftAsItWasInUse", name: "index.md"))
        XCTAssertEqual(RestoreWholeCourseWording.notEnoughSpace(course: "ICS3U", size: "1.2 GB"), try filled("notEnoughSpace", size: "1.2 GB"))
        XCTAssertEqual(RestoreWholeCourseWording.ranOutOfSpace(course: "ICS3U"), try filled("ranOutOfSpace"))
        XCTAssertEqual(RestoreWholeCourseWording.stoppedPartWay(course: "ICS3U", keptAt: keptAt), try filled("stoppedPartWay"))
        XCTAssertEqual(RestoreWholeCourseWording.stoppedPartWayNothingToOpen(course: "ICS3U"), try filled("stoppedPartWayNothingToOpen"))
        XCTAssertEqual(RestoreWholeCourseWording.notInTheSidebar(course: "ICS3U"), try filled("notInTheSidebar"))
        XCTAssertEqual(RestoreWholeCourseWording.didNotFinishTitle, try filled("didNotFinishTitle"))
        XCTAssertEqual(RestoreWholeCourseWording.didNotFinish(course: "ICS3U"), try filled("didNotFinish"))
        XCTAssertEqual(RestoreWholeCourseWording.newcomersKept(course: "ICS3U", keptAt: keptAt), try filled("newcomersKept"))
        XCTAssertEqual(RestoreWholeCourseWording.setAsideFilesKept(keptAt: keptAt), try filled("setAsideFilesKept"))
        XCTAssertEqual(RestoreWholeCourseWording.anotherRestoreUnderWay(course: "ICS3U"), try filled("anotherRestoreUnderWay"))

        // The joins, as wording.joins says.
        XCTAssertEqual(
            CourseRestorer.Problem.courseRestoreStoppedPartWay("ICS3U", keptAt: keptAt, archived: true, settingsAreBack: false).localizedDescription,
            try filled("stoppedPartWay") + " " + filled("notInTheSidebar") + " " + filled("restoreAgainToPutItRight")
                + " " + OneSectionRestoreWording.stoppedPartWayArchived
        )
        XCTAssertEqual(
            CourseRestorer.Problem.courseRestoreStoppedPartWay("ICS3U", keptAt: nil, archived: false, settingsAreBack: true).localizedDescription,
            try filled("stoppedPartWayNothingToOpen")
        )
        XCTAssertEqual(
            CourseRestorer.Problem.courseLeftAsItWasLocked("ICS3U", "index.md").localizedDescription,
            try filled("leftAsItWasLocked", name: "index.md") + " " + filled("unlockIt")
        )
        XCTAssertEqual(
            CourseRestorer.Problem.courseFolderLocked("ICS3U").localizedDescription,
            try filled("leftAsItWasFolderLocked") + " " + filled("unlockIt")
        )
        XCTAssertEqual(
            CourseRestorer.Problem.courseLeftAsItWas("ICS3U", "disk full", newcomersKeptAt: keptAt).localizedDescription,
            try filled("leftAsItWas", reason: "disk full") + " " + filled("newcomersKept")
        )
        XCTAssertEqual(
            CourseRestorer.Problem.notEnoughSpace("ICS3U", 1_200_000_000).localizedDescription,
            try filled("notEnoughSpace", size: WholeCourseRestore.sizeText(1_200_000_000))
        )
    }

    // MARK: - Functions: the contract

    static func block() throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/course-management.json")
        let all: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let backups: [String: Any] = try XCTUnwrap(all["backups"] as? [String: Any])
        return try XCTUnwrap(backups["restoreWholeCourse"] as? [String: Any], "No backups.restoreWholeCourse")
    }
}

/// The contract's `faultFixture`: a course ICS3U and a backup zip of it.
@MainActor
struct WholeCourseFixture {

    // MARK: - Stored properties

    let rootURL: URL
    let coursesDirectoryURL: URL
    let courseURL: URL
    let zipURL: URL

    /// The backup's own files, by path inside the course.
    let backupFiles: [String: Data]

    let previousTrail: ProblemReportStore

    // MARK: - Initializer

    init(smallBackupMarker: Bool = false, backupSettingsUnreadable: Bool = false, reference: Bool = false) throws {
        let fileManager: FileManager = FileManager.default
        rootURL = fileManager.temporaryDirectory.appendingPathComponent("restore-909-\(UUID().uuidString)")
        coursesDirectoryURL = rootURL.appendingPathComponent("courses")
        courseURL = coursesDirectoryURL.appendingPathComponent("ICS3U")
        zipURL = rootURL.appendingPathComponent("ICS3U_backup_2026-11-13_201500.zip")
        previousTrail = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: rootURL.appendingPathComponent("trail"))

        let then: URL = rootURL.appendingPathComponent("then")
        try WholeCourseFixture.writeCourse(at: then.appendingPathComponent("ICS3U"), tag: "BACKUP", reference: reference)
        if backupSettingsUnreadable {
            try Data("not settings".utf8).write(to: then.appendingPathComponent("ICS3U/course_config.json"))
        }
        backupFiles = try WholeCourseFixture.snapshot(of: then.appendingPathComponent("ICS3U"))
        var arguments: [String] = ["-r", "-q", "-X", zipURL.path, "ICS3U"]
        if smallBackupMarker {
            try Data("{}".utf8).write(to: then.appendingPathComponent(SharedMediaList.nameInsideTheZip))
            arguments.append(SharedMediaList.nameInsideTheZip)
        }
        let zip: Process = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = arguments
        zip.currentDirectoryURL = then
        try zip.run()
        zip.waitUntilExit()
        try fileManager.removeItem(at: then)

        try WholeCourseFixture.writeCourse(at: courseURL, tag: "LIVE", reference: reference)
        try WholeCourseFixture.write("ref: refs/heads/main\n", to: courseURL.appendingPathComponent(".git/HEAD"))
    }

    // MARK: - Functions

    /// A course whose every file says `tag`; `reference` makes it one kept
    /// for reference, as `ReferenceReplacerTests` writes one.
    static func writeCourse(at url: URL, tag: String, reference: Bool = false) throws {
        var settings: [String: Any] = ["course_code": "ICS3U", "course_name": "\(tag) course", "section_numbers": [1]]
        if reference {
            settings["kept_for_reference"] = true
            settings["reference_school_year"] = 2025
            settings["deploy_target"] = "local_folder"
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings).write(to: url.appendingPathComponent("course_config.json"))
        try write("{\"tag\": \"\(tag)\"}", to: url.appendingPathComponent(".obsidian/app.json"))
        try write("\(tag) concept\n", to: url.appendingPathComponent("Concepts/Unit 1/Concept 1.md"))
        try write("\(tag) front page\n", to: url.appendingPathComponent("index.md"))
        try write("\(tag) class\n", to: url.appendingPathComponent("section1/All Classes/Unit 1, Day 1.md"))
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Hooks that count moves (`seen` gets "out NAME" or "in NAME"), make
    /// the k-th forward move or the j-th move back fail, or write an
    /// intruder into the course just before the first move in.
    func hooks(failForward: Int?, failBack: Int?, intruder: String?, seen: @escaping (String) -> Void) -> RestoreSwap.Hooks {
        var forward: Int = 0
        var back: Int = 0
        var intruded: Bool = false
        let course: URL = courseURL
        return RestoreSwap.Hooks(
            step: { (_: String) throws in
            },
            move: { (source: URL, destination: URL) throws in
                forward += 1
                let isIn: Bool = source.path.contains("/backup/")
                seen((isIn ? "in " : "out ") + (isIn ? destination.lastPathComponent : source.lastPathComponent))
                if isIn, let intruder, !intruded {
                    intruded = true
                    try WholeCourseFixture.write("intruder\n", to: course.appendingPathComponent(intruder))
                }
                if forward == failForward {
                    throw CocoaError(.fileWriteUnknown)
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            moveBack: { (source: URL, destination: URL) throws in
                back += 1
                if back == failBack {
                    throw CocoaError(.fileWriteUnknown)
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            flushes: false
        )
    }

    /// What the course should hold after a restore that worked: the
    /// backup's files, and the live `.git` left where it was.
    func backupWithWhatIsKeptInPlace(liveGit: Data?) -> [String: Data] {
        var expected: [String: Data] = backupFiles
        if let liveGit {
            expected[".git/HEAD"] = liveGit
        }
        return expected
    }

    /// Whether anything was moved under `courses/_backups/ICS3U/`.
    func somethingWasKept() -> Bool {
        let shelf: URL = coursesDirectoryURL.appendingPathComponent("_backups/ICS3U")
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: shelf.path)) ?? []
        return !names.isEmpty
    }

    /// Every file kept under `courses/_backups/ICS3U/`, by its path inside
    /// the course.
    func everythingKept() throws -> [String: Data] {
        let shelf: URL = coursesDirectoryURL.appendingPathComponent("_backups/ICS3U")
        var all: [String: Data] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: shelf.path)) ?? [] {
            for (path, bytes) in try WholeCourseFixture.snapshot(of: shelf.appendingPathComponent(name)) {
                all[path] = bytes
            }
        }
        return all
    }

    /// How many entries `courses/.internal/restoring` holds.
    func leftInRestoring() -> Int {
        let folder: URL = RestoreSwap.restoringFolder(coursesDirectoryURL)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).count
    }

    func trailText() -> String {
        return ActivityTrail.store.activityText(includingPrompts: true)
    }

    func tearDown() {
        ActivityTrail.store = previousTrail
        _ = RestoreSwap.removeUnlocking(rootURL)
    }

    /// Every file under a folder, by relative path, with its bytes. Links
    /// are not followed.
    static func snapshot(of folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let rootPath: String = folder.standardizedFileURL.path + "/"
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return result
        }
        while let entry = walker.nextObject() as? URL {
            let values: URLResourceValues = try entry.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true || values.isSymbolicLink == true {
                continue
            }
            let path: String = entry.standardizedFileURL.path
            result[String(path.dropFirst(rootPath.count))] = try Data(contentsOf: entry)
        }
        return result
    }
}
