import XCTest
@testable import QuartzTeachers

/// The one liveness reader every work lease shares (`ProcessLiveness`), the
/// shape a lease is written in, and the claim a staging folder is taken with
/// (#245).
///
/// Runs three contract lists by key — `shared-rules.json` →
/// `workLeases.liveness.cases`, `file-formats.json` → `workLease.bodyCases`
/// and `shared-rules.json` → `referenceCourses.importing.
/// oneImportPerCourseAtATime.cases` — and fails a case it does not know how
/// to run rather than skipping it. The rest ask real processes: this one,
/// launchd (another account's), a child that has finished and not been
/// collected, and one that has gone.
///
/// Touches `ReferenceStaging.claimedStagingKeys`, a process-wide set, and
/// empties it around every test; that is safe only because the scheme runs
/// test classes one at a time (`parallelizable = "NO"` — see CLAUDE.md).
@MainActor
final class WorkLeaseLivenessTests: XCTestCase {

    // MARK: - Stored properties

    var rootURL: URL = URL(fileURLWithPath: "/")
    var coursesDirectoryURL: URL = URL(fileURLWithPath: "/")

    // MARK: - Setting up

    override func setUp() async throws {
        ReferenceStaging.claimedStagingKeys = []
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("work-lease-\(UUID().uuidString)")
        coursesDirectoryURL = rootURL.appendingPathComponent("Workspace").appendingPathComponent("courses")
        try FileManager.default.createDirectory(at: coursesDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        ReferenceStaging.claimedStagingKeys = []
        ReferenceLock.clearLock(at: rootURL)
        try? FileManager.default.removeItem(at: rootURL)
    }

    // MARK: - The rule, as the contract writes it

    func testTheLivenessRuleIsTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["workLeases", "liveness"])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 19, "Cases went missing from the contract.")

        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            let pid: Int32 = Int32(try XCTUnwrap(item["pid"] as? Int, name))
            let signal: ProcessLiveness.SignalAnswer = try XCTUnwrap(
                ProcessLiveness.SignalAnswer(rawValue: item["signal"] as? String ?? ""),
                "Unknown signal answer in: \(name)"
            )
            var table: ProcessLiveness.TableAnswer = .couldNotAsk
            if let found = item["table"] as? [String: Any] {
                table = .found(
                    name: try XCTUnwrap(found["name"] as? String, name),
                    isZombie: try XCTUnwrap(found["zombie"] as? Bool, name),
                    startTime: try XCTUnwrap(found["start"] as? String, name)
                )
            } else if let word = item["table"] as? String {
                if word == "noSuchProcess" {
                    table = .noSuchProcess
                } else if word == "couldNotAsk" {
                    table = .couldNotAsk
                } else {
                    XCTFail("Unknown table answer '\(word)' in: \(name)")
                    continue
                }
            } else if !(item["table"] is NSNull) {
                XCTFail("No table answer in: \(name)")
                continue
            }
            let lease: [String: Any] = try XCTUnwrap(item["lease"] as? [String: Any], name)
            let expect: String = try XCTUnwrap(item["expect"] as? String, name)
            XCTAssertTrue(expect == "alive" || expect == "gone", "Unknown expectation in: \(name)")

            let alive: Bool = ProcessLiveness.decide(
                pid: pid,
                signal: signal,
                table: table,
                recordedName: ProcessLiveness.nameToCompare(
                    recorded: lease["name"] as? String, kind: item["kind"] as? String ?? ""
                ),
                recordedStart: lease["start"] as? String
            )
            XCTAssertEqual(alive ? "alive" : "gone", expect, name)
        }
    }

    func testALeaseIsReadTheContractsWay() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.contract("file-formats.json", ["workLease"])
        let cases: [[String: Any]] = try XCTUnwrap(block["bodyCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7)
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            let body: String = try XCTUnwrap(item["body"] as? String, name)
            let expect: [String: Any] = try XCTUnwrap(item["expect"] as? [String: Any], name)
            let read: (name: String?, start: String?) = ProcessLiveness.recordedFacts(inLeaseText: body)
            XCTAssertEqual(read.name, expect["name"] as? String, name)
            XCTAssertEqual(read.start, expect["start"] as? String, name)
        }
    }

    // MARK: - Real processes

    /// launchd is another account's process: the signal is refused, the
    /// process table still answers, and it is alive.
    func testAnotherAccountsProcessIsAlive() {
        XCTAssertEqual(ProcessLiveness.askTheProcessTable(pid: 1) == .noSuchProcess, false)
        XCTAssertTrue(ProcessLiveness.ownerIsAlive(pid: 1, recordedName: nil, recordedStart: nil))
        XCTAssertTrue(ProcessLiveness.ownerIsAlive(pid: 1, recordedName: "launchd", recordedStart: nil))
        XCTAssertFalse(
            ProcessLiveness.ownerIsAlive(pid: 1, recordedName: "Plantoir", recordedStart: nil),
            "A recorded name that is not the running one is a recycled id."
        )
        XCTAssertFalse(
            ProcessLiveness.ownerIsAlive(pid: 1, recordedName: "launchd", recordedStart: "1.000000"),
            "A recorded start that is not the running one is a recycled id."
        )
    }

    /// This process, as it writes itself into a lease, reads as alive.
    func testThisProcessReadsAsAliveFromItsOwnLease() {
        let facts: (name: String?, start: String?) = ProcessLiveness.recordedFacts(
            inLeaseText: ProcessLiveness.leaseBody()
        )
        XCTAssertNotNil(facts.name)
        XCTAssertNotNil(facts.start)
        XCTAssertTrue(
            ProcessLiveness.ownerIsAlive(pid: getpid(), recordedName: facts.name, recordedStart: facts.start),
            "The name or the start this process writes is not what the system reports for it."
        )
    }

    /// A child that has finished and not been collected still answers the
    /// signal — the table says it is a zombie, and it is gone.
    func testAFinishedProcessNotYetCollectedIsGone() throws {
        var child: pid_t = 0
        let argument: UnsafeMutablePointer<CChar>? = strdup("true")
        defer {
            free(argument)
        }
        var arguments: [UnsafeMutablePointer<CChar>?] = [argument, nil]
        let spawned: Int32 = posix_spawn(&child, "/usr/bin/true", nil, nil, &arguments, nil)
        XCTAssertEqual(spawned, 0)
        defer {
            var status: Int32 = 0
            waitpid(child, &status, 0)
        }
        // Wait on the real condition — the table saying it has finished —
        // rather than on a guessed duration. Bounded, so a broken machine
        // fails the test instead of hanging it.
        var becameAZombie: Bool = false
        for _ in 1...5000 {
            if case .found(_, let isZombie, _) = ProcessLiveness.askTheProcessTable(pid: child), isZombie {
                becameAZombie = true
                break
            }
            usleep(1000)
        }
        XCTAssertTrue(becameAZombie, "The child never finished.")
        XCTAssertEqual(ProcessLiveness.askBySignal(pid: child), .exists, "The signal check cannot see it.")
        XCTAssertFalse(ProcessLiveness.ownerIsAlive(pid: child, recordedName: nil, recordedStart: nil))
    }

    /// A process with its real name and start is alive; once it has gone,
    /// it is not.
    func testALiveProcessWithItsRealStartHoldsItsLease() throws {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        addTeardownBlock {
            process.terminate()
            process.waitUntilExit()
        }
        let pid: Int32 = process.processIdentifier
        let start: String? = ProcessLiveness.startTime(ofProcess: pid)
        XCTAssertNotNil(start)
        XCTAssertTrue(ProcessLiveness.ownerIsAlive(pid: pid, recordedName: "sleep", recordedStart: start))

        process.terminate()
        process.waitUntilExit()
        XCTAssertFalse(ProcessLiveness.ownerIsAlive(pid: pid, recordedName: "sleep", recordedStart: start))
    }

    func testTheStartTimeIsSpelledOneWay() {
        XCTAssertEqual(ProcessLiveness.startTimeText(seconds: 1790345209, microseconds: 42), "1790345209.000042")
        XCTAssertEqual(ProcessLiveness.startTimeText(seconds: 5, microseconds: 999999), "5.999999")
        XCTAssertEqual(ProcessLiveness.startTimeText(seconds: 5, microseconds: 0), "5.000000")
    }

    // MARK: - What a lease is written as

    /// The import's lease keeps its NAME (so an older Plantoir still reads
    /// it) and is written in Windows' three lines plus the start.
    func testTheImportLeaseIsWrittenInTheSharedShape() throws {
        ReferenceStaging.takeLease(for: "ICS4U-2025", inCoursesDirectory: coursesDirectoryURL)
        let lease: URL = ReferenceStaging.activityDirectory(inCoursesDirectory: coursesDirectoryURL)
            .appendingPathComponent("ICS4U-2025.import.\(getpid()).lease")
        let data: Data = try Data(contentsOf: lease)
        XCTAssertFalse(data.starts(with: [0xEF, 0xBB, 0xBF]), "A byte-order mark was written.")
        let text: String = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertFalse(text.contains("\r"))
        let lines: [Substring] = text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 5, "Four lines, each ending in a line feed: \(text)")
        XCTAssertEqual(String(lines[0]), "\(getpid())")
        XCTAssertEqual(String(lines[1]), ProcessInfo.processInfo.processName)
        XCTAssertNotNil(
            String(lines[2]).range(
                of: #"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{7}Z$"#, options: .regularExpression
            ),
            "The moment is not in .NET's round-trip shape: \(lines[2])"
        )
        XCTAssertEqual(String(lines[3]), ProcessLiveness.startTime(ofProcess: getpid()))
    }

    // MARK: - The sweep

    /// A lease naming a live process whose recorded name or start is not
    /// that process's holds nothing — and a one-line import lease is read as
    /// Plantoir's, so one naming launchd's id holds nothing either (L2 of
    /// #245's review: after a restart a crashed import's id can belong to
    /// anything, and since #245 a live lease refuses the import).
    func testARecycledProcessIdDoesNotHoldALeftover() throws {
        let names: [String] = ["ICS4U-2025", "ICS3U-2025", "MPM2D-2025"]
        for name in names {
            try FileManager.default.createDirectory(
                at: coursesDirectoryURL.appendingPathComponent(ReferenceStaging.stagingName(for: name)),
                withIntermediateDirectories: true
            )
        }
        try writeLease(for: "ICS4U-2025", pid: 1, body: "1\nPlantoir\n2026-09-25T13:59:23.8960000Z\n")
        try writeLease(for: "ICS3U-2025", pid: 1, body: "1\nlaunchd\n2026-09-25T13:59:23.8960000Z\n1.000000\n")
        try writeLease(for: "MPM2D-2025", pid: 1, body: "1")
        try FileManager.default.createDirectory(
            at: coursesDirectoryURL.appendingPathComponent(ReferenceStaging.stagingName(for: "ICD2O-2025")),
            withIntermediateDirectories: true
        )
        try writeLease(for: "ICD2O-2025", pid: 1, body: "1\nlaunchd\n2026-09-25T13:59:23.8960000Z\n")

        var swept: [String] = ReferenceStaging.sweepLeftovers(inCoursesDirectory: coursesDirectoryURL)
        swept.sort()
        XCTAssertEqual(swept, ["ICS3U-2025", "ICS4U-2025", "MPM2D-2025"])
    }

    // MARK: - The claim, as the contract writes it

    func testTheClaimIsTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(
            ["referenceCourses", "importing", "oneImportPerCourseAtATime"]
        )
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 9)
        let wording: [String: Any] = try WorkLeaseLivenessTests.sharedRules(
            ["referenceCourses", "importing", "wording"]
        )

        var number: Int = 0
        for item in cases {
            number += 1
            let name: String = item["name"] as? String ?? "?"
            let given: [String: Any] = try XCTUnwrap(item["given"] as? [String: Any], name)
            let expect: [String: Any] = try XCTUnwrap(item["expect"] as? [String: Any], name)
            ReferenceStaging.claimedStagingKeys = []

            // A folder of its own per case, so one case cannot see another's.
            let courses: URL = rootURL.appendingPathComponent("case\(number)").appendingPathComponent("courses")
            try FileManager.default.createDirectory(at: courses, withIntermediateDirectories: true)
            let folderName: String = "ICS4U-2025"
            let staging: URL = courses.appendingPathComponent(ReferenceStaging.stagingName(for: folderName))
            let activity: URL = ReferenceStaging.activityDirectory(inCoursesDirectory: courses)

            if given["claimedInThisApp"] as? Bool == true {
                ReferenceStaging.claimedStagingKeys.insert(
                    ReferenceStaging.claimKey(for: folderName, inCoursesDirectory: courses)
                )
            }
            if given["anotherLiveLease"] as? Bool == true {
                try FileManager.default.createDirectory(at: activity, withIntermediateDirectories: true)
                try Data("1\nlaunchd\n".utf8).write(
                    to: activity.appendingPathComponent("\(folderName).import.1.lease")
                )
            }
            let leftover: String = try XCTUnwrap(given["leftover"] as? String, name)
            var removalFails: Bool = false
            let sentinel: URL = staging.appendingPathComponent("half-made.md")
            if leftover == "removable" || leftover == "cannotBeRemoved" {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                try Data("work".utf8).write(to: sentinel)
                removalFails = leftover == "cannotBeRemoved"
            } else if leftover != "none" {
                XCTFail("Unknown leftover '\(leftover)' in: \(name)")
                continue
            }
            let create: String = try XCTUnwrap(given["create"] as? String, name)
            var createAnswer: ReferenceStaging.CreateAnswer? = nil
            if create == "alreadyThere" {
                createAnswer = .alreadyThere
            } else if create == "failed" {
                createAnswer = .failed("the create step's own sentence")
            } else if create != "made" {
                XCTFail("Unknown create '\(create)' in: \(name)")
                continue
            }

            let claim: ReferenceStaging.Claim = ReferenceStaging.claim(
                folderName,
                inCoursesDirectory: courses,
                removingLeftover: { stagingURL in
                    if removalFails {
                        return false
                    }
                    return ReferenceStaging.remove(at: stagingURL)
                },
                creating: { stagingURL in
                    if let answer = createAnswer {
                        return answer
                    }
                    return ReferenceStaging.createExclusively(at: stagingURL)
                }
            )

            let outcome: String = try XCTUnwrap(expect["outcome"] as? String, name)
            let reasonKey: String? = expect["reason"] as? String
            var expectedReason: String? = nil
            if let reasonKey = reasonKey {
                if reasonKey == "theCreateFailure" {
                    expectedReason = "the create step's own sentence"
                } else if reasonKey.hasPrefix("wording.") {
                    expectedReason = wording[String(reasonKey.dropFirst("wording.".count))] as? String
                    XCTAssertNotNil(expectedReason, "No sentence \(reasonKey) in the contract: \(name)")
                } else {
                    XCTFail("Unknown reason '\(reasonKey)' in: \(name)")
                }
            }
            switch outcome {
            case "claimed":
                XCTAssertEqual(claim, .claimed, name)
                XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path), "Not made: \(name)")
            case "refused":
                XCTAssertEqual(claim, .someoneElseIsMakingIt, name)
                XCTAssertEqual(expectedReason, ReferenceImportWording.alreadyBeingImported, name)
            case "couldNotStart":
                XCTAssertEqual(claim, .couldNotStart(expectedReason ?? "?"), name)
            default:
                XCTFail("Unknown outcome '\(outcome)' in: \(name)")
            }

            let leftoverAfterwards: String = try XCTUnwrap(expect["leftover"] as? String, name)
            if leftoverAfterwards == "removed" {
                XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path), "Not cleared: \(name)")
            } else if leftoverAfterwards == "leftAlone" {
                XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path), "Removed: \(name)")
            } else {
                XCTAssertEqual(leftoverAfterwards, "none", name)
            }

            let ours: URL = activity.appendingPathComponent(ReferenceStaging.leaseName(for: folderName))
            XCTAssertEqual(
                FileManager.default.fileExists(atPath: ours.path),
                try XCTUnwrap(expect["leaseKept"] as? Bool, name),
                "Our own lease: \(name)"
            )
            if given["anotherLiveLease"] as? Bool == true {
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath: activity.appendingPathComponent("\(folderName).import.1.lease").path
                    ),
                    "Another process's live lease was removed: \(name)"
                )
            }
        }
    }

    /// Claimed once, refused until given back, claimed again after.
    func testASecondClaimInThisAppIsRefusedUntilGivenBack() throws {
        XCTAssertEqual(ReferenceStaging.claim("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL), .claimed)
        let staging: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: "ICS4U-2025")
        )
        let sentinel: URL = staging.appendingPathComponent("half-made.md")
        try Data("window A's work".utf8).write(to: sentinel)

        XCTAssertEqual(
            ReferenceStaging.claim("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL),
            .someoneElseIsMakingIt
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))

        ReferenceStaging.giveBack("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL)
        XCTAssertEqual(
            ReferenceStaging.claim("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL), .claimed,
            "Once given back, what is left is an ordinary leftover and the next claim clears it."
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
        ReferenceStaging.giveBack("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL)
    }

    /// A folder this app has claimed is never swept by this app, even if its
    /// lease file could not be written (the write is best-effort).
    func testTheSweepLeavesThisAppsOwnClaimAloneWithoutItsLease() throws {
        XCTAssertEqual(ReferenceStaging.claim("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL), .claimed)
        ReferenceStaging.releaseLease(for: "ICS4U-2025", inCoursesDirectory: coursesDirectoryURL)
        XCTAssertEqual(ReferenceStaging.sweepLeftovers(inCoursesDirectory: coursesDirectoryURL), [])
        ReferenceStaging.giveBack("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL)
        XCTAssertEqual(
            ReferenceStaging.sweepLeftovers(inCoursesDirectory: coursesDirectoryURL), ["ICS4U-2025"],
            "Once given back it is ordinary litter."
        )
    }

    /// Two windows that reached one working folder by different spellings —
    /// through a link, and in another case — are still one claim. A set that
    /// missed would let the second window clear the first one's copy away
    /// as a leftover.
    func testAClaimIsKnownHoweverTheFolderIsSpelled() throws {
        let link: URL = rootURL.appendingPathComponent("Shortcut")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: rootURL.appendingPathComponent("Workspace")
        )
        let throughTheLink: URL = link.appendingPathComponent("courses")
        let inAnotherCase: URL = rootURL.appendingPathComponent("WORKSPACE").appendingPathComponent("Courses")

        XCTAssertEqual(ReferenceStaging.claim("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL), .claimed)
        let sentinel: URL = coursesDirectoryURL
            .appendingPathComponent(ReferenceStaging.stagingName(for: "ICS4U-2025"))
            .appendingPathComponent("half-made.md")
        try Data("window A's work".utf8).write(to: sentinel)

        XCTAssertEqual(
            ReferenceStaging.claim("ICS4U-2025", inCoursesDirectory: throughTheLink), .someoneElseIsMakingIt
        )
        XCTAssertEqual(
            ReferenceStaging.claim("ICS4U-2025", inCoursesDirectory: inAnotherCase), .someoneElseIsMakingIt,
            "Only meaningful on a case-insensitive disk, which is every Mac's default."
        )
        XCTAssertEqual(
            ReferenceStaging.claim("ics4u-2025", inCoursesDirectory: coursesDirectoryURL), .someoneElseIsMakingIt
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        ReferenceStaging.giveBack("ICS4U-2025", inCoursesDirectory: coursesDirectoryURL)
    }

    // MARK: - Helpers

    func writeLease(for folderName: String, pid: Int32, body: String) throws {
        let activity: URL = ReferenceStaging.activityDirectory(inCoursesDirectory: coursesDirectoryURL)
        try FileManager.default.createDirectory(at: activity, withIntermediateDirectories: true)
        try Data(body.utf8).write(
            to: activity.appendingPathComponent(ReferenceStaging.leaseName(for: folderName, pid: pid))
        )
    }

    static func sharedRules(_ path: [String]) throws -> [String: Any] {
        return try WorkLeaseLivenessTests.contract("shared-rules.json", path)
    }

    static func contract(_ fileName: String, _ path: [String]) throws -> [String: Any] {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts").appendingPathComponent(fileName)
        var node: [String: Any] = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        for key in path {
            node = try XCTUnwrap(node[key] as? [String: Any], "No \(key) in \(fileName)")
        }
        return node
    }
}
