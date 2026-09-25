import XCTest
@testable import QuartzTeachers

/// The mac reads AND writes the build, preview and publish leases (#156), so
/// the window, the in-app assistant, a publish set for later and an assistant
/// working from another app (`--mcp-stdio`) never build one course at once.
///
/// Runs `contracts/shared-rules.json` → `workLeases.declining.cases` by key
/// and fails a case it does not know how to run. The rest is file-based and
/// starts no build: leases are real files in a throwaway working folder, the
/// "other program" is a real `/bin/sleep` child (so the liveness reader
/// answers for a real process), and the launchers are stand-ins that sleep.
///
/// Resets `CourseActivity`, `PreviewLeases`, `WorkLeaseRegistry` and
/// `ScriptRunner.refusesNewRuns` — process-wide state — around every test;
/// safe only because the scheme runs test classes one at a time
/// (`parallelizable = "NO"` — see CLAUDE.md).
@MainActor
final class WorkLeaseDecliningTests: XCTestCase {

    // MARK: - Stored properties

    var root: URL = URL(fileURLWithPath: "/")
    var coursesURL: URL = URL(fileURLWithPath: "/")
    var workspace: WorkspaceModel = WorkspaceModel()
    var course: Course = Course(
        code: "ICS3U", directoryURL: URL(fileURLWithPath: "/"),
        configuration: CourseConfiguration(values: [:], lastSavedData: Data())
    )
    var siteWork: StubSiteWork = StubSiteWork()

    /// The "other program": a real process, so `ProcessLiveness` reads it.
    var other: Process?

    var previousTrail: ProblemReportStore = ActivityTrail.store

    // MARK: - Setting up

    override func setUp() async throws {
        CourseActivity.reset()
        PreviewLeases.reset()
        WorkLeaseRegistry.reset()
        ScriptRunner.refusesNewRuns = false

        let fileManager: FileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent("work-lease-156-\(UUID().uuidString)")
        coursesURL = root.appendingPathComponent("courses")
        try fileManager.createDirectory(at: coursesURL, withIntermediateDirectories: true)
        let agentsDirectory: URL = root.appendingPathComponent("LaunchAgents")
        try fileManager.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = agentsDirectory
        ScheduledDeploy.scheduledScriptsDirectoryOverride = root.appendingPathComponent("scheduled")
        previousTrail = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: root.appendingPathComponent("trail"))
        for launcher in ["preview.sh", "deploy.sh"] {
            try "#!/bin/bash\n".write(
                to: root.appendingPathComponent(launcher), atomically: true, encoding: .utf8
            )
        }

        let courseURL: URL = coursesURL.appendingPathComponent("ICS3U")
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent("section1/All Classes"), withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: courseURL.appendingPathComponent(".netlify_sites"), withIntermediateDirectories: true
        )
        try "{}".write(
            to: courseURL.appendingPathComponent(".netlify_sites/section1.json"),
            atomically: true, encoding: .utf8
        )
        let configuration: [String: Any] = [
            "course_code": "ICS3U",
            "course_name": "Introduction to Computer Science",
            "section_numbers": [1],
            "num_sections": 1,
            "per_section_folders": ["All Classes"],
            "per_section_files": [],
        ]
        try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted])
            .write(to: courseURL.appendingPathComponent("course_config.json"))

        workspace = WorkspaceModel(defaults: TestDefaults.make())
        workspace.chooseWorkspace(at: root)
        var found: Course? = nil
        for candidate in workspace.courses where candidate.code == "ICS3U" {
            found = candidate
        }
        course = try XCTUnwrap(found)
        siteWork = StubSiteWork()
        SectionWindowControllers.shared.forgetAll()
    }

    override func tearDown() async throws {
        if let other, other.isRunning {
            other.terminate()
            other.waitUntilExit()
        }
        other = nil
        CourseActivity.reset()
        PreviewLeases.reset()
        WorkLeaseRegistry.reset()
        ScriptRunner.refusesNewRuns = false
        ScheduledDeploy.launchAgentsDirectoryOverride = nil
        ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
        ActivityTrail.store = previousTrail
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    /// Starts the "other program" and returns its process id.
    func startTheOtherProgram() throws -> Int32 {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        other = process
        return process.processIdentifier
    }

    /// Writes a lease the other program holds, the way a mac would write it,
    /// naming it as the process table does.
    @discardableResult
    func writeOthersLease(kind: String, pid: Int32, name: String = "sleep", moment: String? = nil) throws -> URL {
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url: URL = directory.appendingPathComponent(
            WorkLeaseFiles.fileName(courseCode: "ICS3U", kind: kind, pid: pid)
        )
        // A second BEFORE now by default: the other program took its lease
        // first. Taken at `Date()` it can share this process's millisecond,
        // and the tiebreak then goes by pid — the sleep child's is higher —
        // which is the rule working, and a test that flickers.
        let when: String = moment ?? ProcessLiveness.leaseMomentText(Date().addingTimeInterval(-1))
        let start: String = ProcessLiveness.startTime(ofProcess: pid) ?? ""
        try Data("\(pid)\n\(name)\n\(when)\n\(start)\n".utf8).write(to: url)
        return url
    }

    func leaseURL(kind: String) -> URL {
        return WorkLeaseFiles.activityDirectory(coursesDirectory: coursesURL)
            .appendingPathComponent(WorkLeaseFiles.fileName(courseCode: "ICS3U", kind: kind, pid: getpid()))
    }

    func exists(_ url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }

    func trailText() -> String {
        var text: String = ""
        let folder: URL = root.appendingPathComponent("trail")
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
                text += String(decoding: data, as: UTF8.self)
            }
        }
        return text
    }

    func call(_ name: String, _ arguments: [String: Any]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString, type: "function",
            function: AssistToolCall.Function(
                name: name, arguments: String(data: encoded, encoding: .utf8) ?? "{}"
            )
        )
    }

    func runner(surface: AssistToolRunner.Surface) -> AssistToolRunner {
        return AssistToolRunner(
            workspace: workspace,
            siteWork: siteWork,
            today: { return CalendarDay(year: 2026, month: 9, day: 8)! },
            launchControl: SilentLaunchControl(),
            surface: surface
        )
    }

    // MARK: - The rule, as the contract writes it

    func testTheDeclineRuleIsTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["workLeases", "declining"])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 29, "Cases went missing from the contract.")

        var ran: Int = 0
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            let askerWord: String = try XCTUnwrap(item["asker"] as? String, name)
            let asker: WorkLeaseFiles.Asker
            if askerWord == "aBuild" {
                asker = .aBuild
            } else if askerWord == "aScheduledPublish" {
                asker = .aScheduledPublish
            } else {
                XCTFail("Unknown asker '\(askerWord)' in: \(name)")
                continue
            }
            let me: [String: Any] = try XCTUnwrap(item["me"] as? [String: Any], name)
            let myPID: Int32 = Int32(try XCTUnwrap(me["pid"] as? Int, name))
            var claim: WorkLeaseFiles.Claim? = nil
            if let claimed = me["claim"] as? [String: Any] {
                claim = WorkLeaseFiles.Claim(
                    moment: try XCTUnwrap(claimed["moment"] as? String, name),
                    pid: Int32(try XCTUnwrap(claimed["pid"] as? Int, name))
                )
            } else if !(me["claim"] is NSNull) {
                XCTFail("No claim (null or an object) in: \(name)")
                continue
            }

            var holdings: [WorkLeaseFiles.Holding] = []
            for entry in try XCTUnwrap(item["others"] as? [[String: Any]], name) {
                let courseCode: String = try XCTUnwrap(entry["course"] as? String, name)
                let pid: Int32 = Int32(try XCTUnwrap(entry["pid"] as? Int, name))
                let alive: Bool = try XCTUnwrap(entry["alive"] as? Bool, name)
                let kind: String = try XCTUnwrap(entry["kind"] as? String, name)
                // A lease with no name line: what `heldElsewhere` asks
                // `ProcessLiveness.nameToCompare`, which names only an import.
                let hasANameLine: Bool = (entry["nameLine"] as? Bool) ?? true
                let recordedName: String? = hasANameLine ? "sleep" : nil
                let judgedName: String? = ProcessLiveness.nameToCompare(recorded: recordedName, kind: kind)
                // What `heldElsewhere` filters, applied to the case's files.
                if courseCode.lowercased() != "ics3u" || pid == myPID || !alive || judgedName == nil {
                    continue
                }
                holdings.append(WorkLeaseFiles.Holding(
                    kind: kind,
                    pid: pid,
                    moment: entry["moment"] as? String
                ))
            }

            let expect: String = try XCTUnwrap(item["expect"] as? String, name)
            XCTAssertTrue(expect == "declined" || expect == "allowed", "Unknown expectation in: \(name)")
            let blocking: WorkLeaseFiles.Holding? = WorkLeaseFiles.blocking(
                among: holdings, asker: asker, claim: claim
            )
            XCTAssertEqual(blocking == nil ? "allowed" : "declined", expect, name)
            ran += 1
        }
        XCTAssertEqual(ran, cases.count, "A case was not run.")
    }

    func testTheScheduledWaitIsTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(
            ["workLeases", "declining", "scheduledPublishWait"]
        )
        XCTAssertEqual(block["longestSeconds"] as? Int, Int(ScheduledDeploy.longestWaitForTheCourse))
        XCTAssertEqual(block["lookAgainEverySeconds"] as? Int, Int(ScheduledDeploy.lookAgainEvery))
        XCTAssertEqual(block["clock"] as? String, "wall")
    }

    func testEveryKindItBlocksOnIsOneTheFormatNames() throws {
        let format: [String: Any] = try WorkLeaseLivenessTests.contract("file-formats.json", ["workLease"])
        let kinds: [String: Any] = try XCTUnwrap(format["kinds"] as? [String: Any])
        for kind in WorkLeaseFiles.kindsThatBlockABuild {
            XCTAssertNotNil(kinds[kind], "\(kind) blocks a build and is not a kind the format names")
        }
        for kind in [WorkLeaseFiles.buildKind, WorkLeaseFiles.previewKind, WorkLeaseFiles.publishKind] {
            XCTAssertNotNil(kinds[kind], "\(kind) is written and is not a kind the format names")
        }
    }

    // MARK: - What this app writes

    /// The shape Windows' reader needs (it reads lines 1 and 2 and ignores the
    /// rest), plus #245's fourth line; line 2 is the process table's name.
    func testALeaseIsWrittenInTheSharedShape() throws {
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ics3u", sectionNumber: 1)
        let url: URL = leaseURL(kind: "build")
        XCTAssertTrue(exists(url), "The build lease is named with the course upper-cased.")

        let data: Data = try Data(contentsOf: url)
        XCTAssertFalse(data.starts(with: [0xEF, 0xBB, 0xBF]), "No byte-order mark.")
        let text: String = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("\n"), "The last line ends in a line feed too.")
        XCTAssertFalse(text.contains("\r"))
        let lines: [Substring] = text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 5, "Four lines and the empty remainder after the last line feed.")
        XCTAssertEqual(String(lines[0]), String(getpid()))
        guard case .found(let tableName, _, let startTime) = ProcessLiveness.askTheProcessTable(pid: getpid()) else {
            return XCTFail("The table could not be asked about this process.")
        }
        XCTAssertEqual(String(lines[1]), tableName, "Line 2 is the name every reader compares against.")
        XCTAssertTrue(WorkLeaseFiles.isAComparableMoment(String(lines[2])), "Line 3: \(lines[2])")
        XCTAssertEqual(String(lines[3]), startTime)

        // Windows' `IsAlive`, as written in WorkLease.cs: at least two lines,
        // and the second, trimmed, is the running process's name.
        XCTAssertGreaterThanOrEqual(lines.count - 1, 2)
        XCTAssertTrue(ProcessLiveness.namesMatch(recorded: String(lines[1]), running: tableName))
    }

    /// The leases follow what the app is doing: one file per course and kind,
    /// kept while any section needs it.
    func testTheLeasesFollowWhatThisAppIsDoing() throws {
        let build: URL = leaseURL(kind: "build")
        let publish: URL = leaseURL(kind: "publish")
        let preview: URL = leaseURL(kind: "preview")

        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2)
        XCTAssertTrue(exists(build))
        XCTAssertFalse(exists(publish), "A preview's build is not a publish.")
        CourseActivity.endPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertTrue(exists(build), "Section 2 is still being built.")
        CourseActivity.endPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2)
        XCTAssertFalse(exists(build))

        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertTrue(exists(build) && exists(publish), "A publish holds build beside publish, as Windows does.")
        CourseActivity.endPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertFalse(exists(build) || exists(publish))

        let lease: PreviewLeases.Lease = try PreviewLeases.lease(
            folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1
        )
        XCTAssertTrue(exists(preview))
        XCTAssertFalse(exists(build), "An open preview holds no build once its build is done.")
        PreviewLeases.release(lease)
        XCTAssertFalse(exists(preview))

        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        WorkLeaseRegistry.releaseEverything()
        XCTAssertFalse(exists(build) || exists(publish), "Quitting takes every lease down.")
    }

    /// The suite hands these stores pretend folders; nothing may be created.
    func testAFolderWithNoCoursesFolderGrowsNothing() throws {
        let pretend: String = root.appendingPathComponent("no-such-folder").path
        CourseActivity.beginPublish(folderPath: pretend, courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pretend))
        XCTAssertTrue(WorkLeaseRegistry.written.isEmpty)
    }

    // MARK: - What this app reads

    func testALiveOtherProgramIsHeldAndAGoneOneIsNot() throws {
        let pid: Int32 = try startTheOtherProgram()
        let url: URL = try writeOthersLease(kind: "build", pid: pid)
        var held: [WorkLeaseFiles.Holding] = WorkLeaseFiles.heldElsewhere(
            courseCode: "ICS3U", coursesDirectory: coursesURL
        )
        XCTAssertEqual(held.count, 1)
        XCTAssertEqual(held.first?.kind, "build")
        XCTAssertEqual(held.first?.pid, pid)

        // A lease with no name line is not one either app writes (Windows'
        // reader calls it stale too): ignored, even with a live owner.
        try Data("\(pid)\n".utf8).write(to: url)
        XCTAssertTrue(
            WorkLeaseFiles.heldElsewhere(courseCode: "ICS3U", coursesDirectory: coursesURL).isEmpty,
            "A one-line build lease blocked a course."
        )

        // The same pid under another name is a recycled id.
        try writeOthersLease(kind: "build", pid: pid, name: "Plantoir")
        held = WorkLeaseFiles.heldElsewhere(courseCode: "ICS3U", coursesDirectory: coursesURL)
        XCTAssertTrue(held.isEmpty, "A lease naming another program than the one with that id is stale.")

        try writeOthersLease(kind: "build", pid: pid)
        other?.terminate()
        other?.waitUntilExit()
        held = WorkLeaseFiles.heldElsewhere(courseCode: "ICS3U", coursesDirectory: coursesURL)
        XCTAssertTrue(held.isEmpty, "A lease whose owner has gone is ignored.")
        XCTAssertTrue(exists(url), "…and left where it is: no sweep.")

        // This process's own lease is never in its own way.
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        held = WorkLeaseFiles.heldElsewhere(courseCode: "ICS3U", coursesDirectory: coursesURL)
        XCTAssertTrue(held.isEmpty)
    }

    // MARK: - Take, then check: the race

    /// Two programs that write and then look at the same instant: exactly one
    /// of them goes ahead — never both, never neither. Every order of
    /// moments and ids, including a tie.
    func testTwoProgramsThatLookAtOnceCannotBothBackOffOrBothGoAhead() {
        let moments: [String] = [
            "2026-09-25T06:30:00.4000000Z", "2026-09-25T06:30:00.5000000Z",
        ]
        let pids: [Int32] = [100, 5000]
        for firstMoment in moments {
            for secondMoment in moments {
                for firstPID in pids {
                    let secondPID: Int32 = firstPID == 100 ? 5000 : 100
                    let first: WorkLeaseFiles.Claim = WorkLeaseFiles.Claim(moment: firstMoment, pid: firstPID)
                    let second: WorkLeaseFiles.Claim = WorkLeaseFiles.Claim(moment: secondMoment, pid: secondPID)
                    let firstSees: [WorkLeaseFiles.Holding] = [
                        WorkLeaseFiles.Holding(kind: "build", pid: secondPID, moment: secondMoment),
                    ]
                    let secondSees: [WorkLeaseFiles.Holding] = [
                        WorkLeaseFiles.Holding(kind: "build", pid: firstPID, moment: firstMoment),
                    ]
                    let firstGoes: Bool = WorkLeaseFiles.blocking(among: firstSees, asker: .aBuild, claim: first) == nil
                    let secondGoes: Bool = WorkLeaseFiles.blocking(among: secondSees, asker: .aBuild, claim: second) == nil
                    XCTAssertTrue(
                        firstGoes != secondGoes,
                        "\(firstMoment)/\(firstPID) against \(secondMoment)/\(secondPID): "
                        + "first goes \(firstGoes), second goes \(secondGoes)"
                    )
                }
            }
        }
    }

    /// The same race with real files: this app has written its build lease,
    /// and the other program's lease is earlier (it wins) or later (it backs
    /// off, so this one goes ahead).
    func testAfterTakingOnlyAnEarlierLeaseCounts() throws {
        let pid: Int32 = try startTheOtherProgram()
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        let mine: WorkLeaseFiles.Claim = try XCTUnwrap(
            WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U")
        )

        try writeOthersLease(kind: "build", pid: pid, moment: "2000-01-01T00:00:00.0000000Z")
        XCTAssertNotNil(
            WorkLeaseRegistry.whatBlocksABuild(folderPath: root.path, courseCode: "ICS3U", afterTaking: true),
            "An earlier lease wins."
        )
        try writeOthersLease(kind: "build", pid: pid, moment: "2999-01-01T00:00:00.0000000Z")
        XCTAssertNil(
            WorkLeaseRegistry.whatBlocksABuild(folderPath: root.path, courseCode: "ICS3U", afterTaking: true),
            "A later lease is the other program's to back off from (mine: \(mine.moment))."
        )
        XCTAssertNotNil(
            WorkLeaseRegistry.whatBlocksABuild(folderPath: root.path, courseCode: "ICS3U", afterTaking: false),
            "The early look, before anything is taken, counts every lease."
        )
    }

    /// The Preview door's order, measured on real files: its BUILD lease goes
    /// down before its preview lease, so an outside build that lands between
    /// the two loses to the window and exactly one of them goes ahead (#156's
    /// review, M2).
    func testAPreviewAndAnOutsideBuildThatRaceCannotBothBackOff() throws {
        let pid: Int32 = try startTheOtherProgram()
        // The window's press, in the order `startPreview` takes it.
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        let windowsBuild: WorkLeaseFiles.Claim = try XCTUnwrap(
            WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U")
        )
        // The outside build lands a millisecond after the window's build…
        let outsideMoment: String = try WorkLeaseDecliningTests.moment(windowsBuild.moment, plusMilliseconds: 1)
        try writeOthersLease(kind: "build", pid: pid, moment: outsideMoment)
        // …and the window's preview lease after that.
        _ = try PreviewLeases.lease(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)

        let windowGoesAhead: Bool = WorkLeaseRegistry.whatBlocksABuild(
            folderPath: root.path, courseCode: "ICS3U", afterTaking: true
        ) == nil

        // What the outside program sees: the window's two lease files, read
        // back from disk as that program would read them.
        var windowsLeases: [WorkLeaseFiles.Holding] = []
        for kind in ["build", "preview"] {
            let text: String = try String(contentsOf: leaseURL(kind: kind), encoding: .utf8)
            windowsLeases.append(WorkLeaseFiles.Holding(
                kind: kind, pid: getpid(), moment: WorkLeaseFiles.momentLine(in: text)
            ))
        }
        let outsideGoesAhead: Bool = WorkLeaseFiles.blocking(
            among: windowsLeases, asker: .aBuild,
            claim: WorkLeaseFiles.Claim(moment: outsideMoment, pid: pid)
        ) == nil

        XCTAssertTrue(windowGoesAhead, "The window's build was first.")
        XCTAssertFalse(outsideGoesAhead, "The outside build was second.")
    }

    /// The pair the review measured for a Deploy pressed with a preview
    /// already up (window preview < outside build < window build): both back
    /// off — and the claim that would stop that, the EARLIEST of the window's
    /// leases, lets a window build alongside a publish set for later, which
    /// does not wait for previews. Measured both ways on the real rule.
    func testWhyTheClaimIsTheBuildMomentAndNotTheEarliestLease() {
        let t1: String = "2026-09-25T06:30:00.1000000Z"
        let t2: String = "2026-09-25T06:30:00.2000000Z"
        let t3: String = "2026-09-25T06:30:00.3000000Z"

        // The window (claim = its build, t3) against an outside build at t2.
        let windowSees: [WorkLeaseFiles.Holding] = [WorkLeaseFiles.Holding(kind: "build", pid: 4321, moment: t2)]
        XCTAssertNotNil(WorkLeaseFiles.blocking(
            among: windowSees, asker: .aBuild, claim: WorkLeaseFiles.Claim(moment: t3, pid: 100)
        ))
        // The outside build (claim t2) against the window's preview t1 and build t3.
        let outsideSees: [WorkLeaseFiles.Holding] = [
            WorkLeaseFiles.Holding(kind: "preview", pid: 100, moment: t1),
            WorkLeaseFiles.Holding(kind: "build", pid: 100, moment: t3),
        ]
        XCTAssertNotNil(WorkLeaseFiles.blocking(
            among: outsideSees, asker: .aBuild, claim: WorkLeaseFiles.Claim(moment: t2, pid: 4321)
        ), "Both back off: nothing runs, a retry works.")

        // The same timeline with a publish set for later as the other
        // program: it does not wait for the preview, so it is running.
        let scheduledSees: [WorkLeaseFiles.Holding] = [WorkLeaseFiles.Holding(kind: "preview", pid: 100, moment: t1)]
        XCTAssertNil(WorkLeaseFiles.blocking(
            among: scheduledSees, asker: .aScheduledPublish, claim: WorkLeaseFiles.Claim(moment: t2, pid: 4321)
        ), "The scheduled publish goes ahead past a preview.")
        // The window must then decline its Deploy — and does, claimed from its build…
        XCTAssertNotNil(WorkLeaseFiles.blocking(
            among: windowSees, asker: .aBuild, claim: WorkLeaseFiles.Claim(moment: t3, pid: 100)
        ))
        // …where a claim from its earliest lease (the preview, t1) would let
        // it build alongside: the fault itself.
        XCTAssertNil(WorkLeaseFiles.blocking(
            among: windowSees, asker: .aBuild, claim: WorkLeaseFiles.Claim(moment: t1, pid: 100)
        ), "If this ever declines, the earliest-lease claim is safe and the note in takeThenCheck is stale.")
    }

    /// A moment `milliseconds` after another, in the lease's own shape.
    static func moment(_ text: String, plusMilliseconds milliseconds: Int) throws -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS'Z'"
        let date: Date = try XCTUnwrap(formatter.date(from: text), text)
        return ProcessLiveness.leaseMomentText(date.addingTimeInterval(Double(milliseconds) / 1000))
    }

    // MARK: - The Deploy's claim (#156's review, M1)

    /// The claim the window's Deploy takes: on success its build and publish
    /// leases are up (and the publish is recorded), on a refusal nothing of
    /// it is left behind.
    func testTheDeploysClaimHoldsTheBuildOrLeavesNothing() throws {
        XCTAssertNil(WorkLeaseRegistry.claimAPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1))
        XCTAssertTrue(exists(leaseURL(kind: "build")) && exists(leaseURL(kind: "publish")))
        XCTAssertEqual(CourseActivity.activePublishes.count, 1)
        CourseActivity.endPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)

        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "build", pid: pid)
        XCTAssertNotNil(WorkLeaseRegistry.claimAPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1))
        XCTAssertFalse(exists(leaseURL(kind: "build")) || exists(leaseURL(kind: "publish")))
        XCTAssertTrue(CourseActivity.activePublishes.isEmpty)
    }

    /// The ORDER inside the view, which the suite cannot construct: the
    /// Deploy claims before it stops the preview (so its build lease is up
    /// through a stop that ends builds by working directory), and the
    /// Preview records its build before it takes its preview lease. Read
    /// from the source, the way `ActivityTrailWiringTests` reads call sites.
    func testTheWindowTakesItsLeasesInTheOrderThatIsSafe() throws {
        let url: URL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("QuartzTeachers/Views/Section/SectionDetailView.swift")
        let source: String = try String(contentsOf: url, encoding: .utf8)

        let deploy: String = try WorkLeaseDecliningTests.body(of: "func deployAndWait()", in: source)
        let claim: Range<String.Index> = try XCTUnwrap(deploy.range(of: "WorkLeaseRegistry.claimAPublish("))
        let stop: Range<String.Index> = try XCTUnwrap(deploy.range(of: "await stopPreviewAndWait()"))
        XCTAssertLessThan(claim.lowerBound, stop.lowerBound, "The Deploy stops the preview before claiming the course.")
        XCTAssertNil(deploy.range(of: "CourseActivity.beginPublish("), "A second, later bracket crept back.")

        let preview: String = try WorkLeaseDecliningTests.body(of: "func startPreview()", in: source)
        let build: Range<String.Index> = try XCTUnwrap(preview.range(of: "previewBuildWait.begin("))
        let lease: Range<String.Index> = try XCTUnwrap(preview.range(of: "PreviewLeases.lease("))
        let look: Range<String.Index> = try XCTUnwrap(preview.range(of: "WorkLeaseRegistry.whatBlocksABuild("))
        XCTAssertLessThan(build.lowerBound, lease.lowerBound, "The preview lease goes down before the build lease.")
        XCTAssertLessThan(lease.lowerBound, look.lowerBound, "The Preview looks before it has taken both.")
    }

    /// The text of a function, from its signature to the next `    func `.
    static func body(of signature: String, in source: String) throws -> String {
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: signature), signature)
        let rest: Substring = source[start.upperBound...]
        if let next = rest.range(of: "\n    func ", options: .regularExpression) {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    // MARK: - The doors

    /// The headless rebuild — what an outside assistant's rebuild takes, and
    /// the in-app assistant's when no window is open. MUST FAIL before #156.
    func testTheHeadlessRebuildDeclinesWhileAnotherProgramBuilds() async throws {
        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "build", pid: pid)
        let work: AssistToolchainWork = AssistToolchainWork(workspace: workspace)
        let result: AssistSiteWorkResult = await work.rebuildPreview(course: course, sectionNumber: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, AssistWording.courseIsBeingBuiltElsewhere(course: "ICS3U"))
        XCTAssertNil(work.runner.startedAt, "No launcher may start.")
        XCTAssertFalse(exists(leaseURL(kind: "build")), "Its own lease came down with the refusal.")
        XCTAssertTrue(trailText().contains("declined the assistant's rebuild"), trailText())
    }

    /// The headless deploy. MUST FAIL before #156.
    func testTheHeadlessDeployDeclinesWhileAnotherProgramBuilds() async throws {
        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "build", pid: pid)
        let work: AssistToolchainWork = AssistToolchainWork(workspace: workspace)
        let result: AssistSiteWorkResult = await work.deploy(course: course, sectionNumber: 1)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.wasBuiltElsewhere)
        XCTAssertTrue(result.isAboutTheDestination, "The window raises it as its alert.")
        XCTAssertEqual(result.message, AssistWording.courseIsBeingBuiltElsewhere(course: "ICS3U"))
        XCTAssertTrue(work.deployRunner.legs.isEmpty, "No destination may be reached.")
        XCTAssertTrue(CourseActivity.activePublishes.isEmpty)
        XCTAssertFalse(exists(leaseURL(kind: "publish")))
    }

    /// An outside assistant is told `courseIsBusy`, and nothing reaches the
    /// launcher. MUST FAIL before #156.
    func testAnOutsideAssistantIsRefusedWithCourseIsBusy() async throws {
        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "build", pid: pid)
        let mcp: AssistToolRunner = runner(surface: .mcp)

        let deployed: AssistToolOutcome = await mcp.run(call: call("deploy_section", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(deployed.detail, AssistWording.courseIsBusy(course: "ICS3U"))
        XCTAssertEqual(siteWork.deploys, 0)

        let rebuilt: AssistToolOutcome = await mcp.run(call: call("rebuild_preview", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(rebuilt.detail, AssistWording.courseIsBusy(course: "ICS3U"))
        XCTAssertEqual(siteWork.previewRebuilds, 0)
        XCTAssertTrue(trailText().contains("declined the assistant's deploy"), trailText())
    }

    /// The window's own PREVIEW, held by another copy of Plantoir, refuses an
    /// outside assistant's build (#156's M2 ruling, stricter than Windows).
    /// MUST FAIL before #156.
    func testAnotherProgramsPreviewRefusesAnOutsideBuild() async throws {
        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "preview", pid: pid)
        let mcp: AssistToolRunner = runner(surface: .mcp)
        let deployed: AssistToolOutcome = await mcp.run(call: call("deploy_section", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(deployed.detail, AssistWording.courseIsBusy(course: "ICS3U"))
        XCTAssertEqual(siteWork.deploys, 0)
    }

    /// The in-app assistant says the teacher's sentence. MUST FAIL before #156.
    func testTheInAppAssistantSaysTheTeachersSentence() async throws {
        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "publish", pid: pid)
        let local: AssistToolRunner = runner(surface: .local)
        let deployed: AssistToolOutcome = await local.run(call: call("deploy_section", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(deployed.detail, AssistWording.courseIsBeingBuiltElsewhere(course: "ICS3U"))
        XCTAssertEqual(siteWork.deploys, 0)
    }

    /// The controls: an assist lease, a lease for another course and a
    /// lease whose owner is gone decline nothing — without these, declining
    /// everything would pass every test above.
    func testWhatDoesNotBlockStillDeploys() async throws {
        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "assist", pid: pid)
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesURL)
        try Data("\(pid)\nsleep\n".utf8).write(
            to: directory.appendingPathComponent(WorkLeaseFiles.fileName(courseCode: "MPM2D", kind: "build", pid: pid))
        )
        try Data("99999\nPlantoir\n".utf8).write(
            to: directory.appendingPathComponent(WorkLeaseFiles.fileName(courseCode: "ICS3U", kind: "build", pid: 99999))
        )
        let mcp: AssistToolRunner = runner(surface: .mcp)
        let deployed: AssistToolOutcome = await mcp.run(call: call("deploy_section", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(siteWork.deploys, 1, deployed.detail)
    }

    // MARK: - A publish set for later

    /// Busy for three looks, then free: it waits 45 seconds of the wall clock,
    /// takes its own leases, and goes ahead. No real time passes.
    func testAScheduledPublishWaitsThenGoesAhead() throws {
        var clock: Date = Date(timeIntervalSince1970: 1_790_000_000)
        var looks: Int = 0
        var pauses: [TimeInterval] = []
        let busy: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(kind: "build", pid: 4321, moment: nil)
        let answer: ScheduledDeploy.CourseWait = ScheduledDeploy.waitForTheCourse(
            courseCode: "ICS3U",
            coursesDirectory: coursesURL,
            now: { return clock },
            pause: { seconds in
                pauses.append(seconds)
                clock = clock.addingTimeInterval(seconds)
            },
            heldElsewhere: {
                looks += 1
                if looks <= 3 {
                    return [busy]
                }
                return []
            }
        )
        guard case .goAhead(let leases, let waited, let waitedFor) = answer else {
            return XCTFail("Expected to go ahead, got \(answer)")
        }
        XCTAssertEqual(waited, 45)
        XCTAssertEqual(pauses, [15, 15, 15])
        XCTAssertEqual(waitedFor, busy)
        XCTAssertEqual(leases.count, 2, "Its own build and publish leases, so the others wait for IT.")
        for lease in leases {
            XCTAssertTrue(exists(lease))
            WorkLeaseFiles.remove(at: lease)
        }
    }

    /// Still busy at ten minutes: it stands down, holding nothing.
    func testAScheduledPublishStandsDownAfterTenMinutes() throws {
        var clock: Date = Date(timeIntervalSince1970: 1_790_000_000)
        var pauses: Int = 0
        let busy: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(kind: "publish", pid: 4321, moment: nil)
        let answer: ScheduledDeploy.CourseWait = ScheduledDeploy.waitForTheCourse(
            courseCode: "ICS3U",
            coursesDirectory: coursesURL,
            now: { return clock },
            pause: { seconds in
                pauses += 1
                clock = clock.addingTimeInterval(seconds)
            },
            heldElsewhere: { return [busy] }
        )
        XCTAssertEqual(answer, .standDown(busy, waited: 600))
        XCTAssertEqual(pauses, 40, "Every fifteen seconds for ten minutes.")
        XCTAssertFalse(exists(leaseURL(kind: "build")), "Nothing of its own is held while it waits.")
    }

    /// Free at the first look, but a build taken EARLIER appears when it looks
    /// again after taking: it puts its own leases back and waits.
    func testAScheduledPublishThatLosesTheRaceWaitsAgain() throws {
        var clock: Date = Date(timeIntervalSince1970: 1_790_000_000)
        var looks: Int = 0
        let earlier: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(
            kind: "build", pid: 4321, moment: "2000-01-01T00:00:00.0000000Z"
        )
        var leaseWasTakenBack: Bool = false
        let answer: ScheduledDeploy.CourseWait = ScheduledDeploy.waitForTheCourse(
            courseCode: "ICS3U",
            coursesDirectory: coursesURL,
            now: { return clock },
            pause: { seconds in
                leaseWasTakenBack = !FileManager.default.fileExists(
                    atPath: WorkLeaseFiles.activityDirectory(coursesDirectory: self.coursesURL)
                        .appendingPathComponent(WorkLeaseFiles.fileName(courseCode: "ICS3U", kind: "build", pid: getpid()))
                        .path
                )
                clock = clock.addingTimeInterval(seconds)
            },
            heldElsewhere: {
                looks += 1
                if looks == 2 {
                    return [earlier]
                }
                return []
            }
        )
        XCTAssertTrue(leaseWasTakenBack, "Its own lease was not left on disk while it waited.")
        guard case .goAhead(let leases, _, let waitedFor) = answer else {
            return XCTFail("Expected to go ahead, got \(answer)")
        }
        XCTAssertEqual(waitedFor, earlier)
        for lease in leases {
            WorkLeaseFiles.remove(at: lease)
        }
    }

    /// A preview does not hold up a publish set for later.
    func testAPreviewDoesNotHoldUpAScheduledPublish() throws {
        let preview: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(kind: "preview", pid: 4321, moment: nil)
        let answer: ScheduledDeploy.CourseWait = ScheduledDeploy.waitForTheCourse(
            courseCode: "ICS3U",
            coursesDirectory: coursesURL,
            now: { return Date(timeIntervalSince1970: 1_790_000_000) },
            pause: { _ in XCTFail("It waited for a preview.") },
            heldElsewhere: { return [preview] }
        )
        guard case .goAhead(let leases, let waited, let waitedFor) = answer else {
            return XCTFail("Expected to go ahead, got \(answer)")
        }
        XCTAssertEqual(waited, 0)
        XCTAssertNil(waitedFor)
        for lease in leases {
            WorkLeaseFiles.remove(at: lease)
        }
    }

    func testTheStandDownIsReportedAndAsksForAttention() throws {
        XCTAssertTrue(ScheduledPublishOutcome.Kind.courseWasBusy.needsAttention)
        let home: URL = root.appendingPathComponent("home")
        ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(
                kind: .courseWasBusy,
                destination: ScheduledPublishOutcome.nothingWasDeployedName,
                when: Date()
            ),
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: "0a1b2c3d"
        )
        let stopped: ScheduledPublishOutcome.Stopped = try XCTUnwrap(
            ScheduledPublishOutcome.stopped(
                inHomeFolder: home, course: "ICS3U", section: 1, folderID: "0a1b2c3d"
            )
        )
        XCTAssertEqual(stopped.kind, .courseWasBusy, "The record reads back as the kind it was written as.")
        XCTAssertTrue(ScheduledPublishOutcome.noteOnTrail(
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: "0a1b2c3d"
        ))
        XCTAssertTrue(trailText().contains("still being built somewhere else"), trailText())
    }

    // MARK: - An outside assistant's process leaving

    /// When the client goes away mid-build, the MCP process stops the
    /// launcher it started BEFORE its lease comes down, and the lease stays
    /// up while the section is stopped inside the builder.
    func testLeavingStopsItsOwnLauncherBeforeTheLeaseComesDown() async throws {
        try Data("exec sleep 60\n".utf8).write(to: root.appendingPathComponent("preview.sh"))
        let launcher: ScriptRunner = ScriptRunner()
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        launcher.run(scriptNamed: "preview.sh", arguments: ["ICS3U", "1", "--build-only"], workingDirectory: root)
        let child: Int32 = try XCTUnwrap(launcher.processIdentifier, "The stand-in launcher did not start.")
        XCTAssertTrue(exists(leaseURL(kind: "build")))

        var leaseWasUpWhileStoppingInside: Bool = false
        var childWasGoneBeforeStoppingInside: Bool = false
        var stoppedInside: [String] = []
        await AssistMCPServer.stopOwnWorkBeforeLeaving(stopInsideTheBuilder: { courseCode, sectionNumber, _ in
            leaseWasUpWhileStoppingInside = self.exists(self.leaseURL(kind: "build"))
            childWasGoneBeforeStoppingInside = ProcessLiveness.askBySignal(pid: child) == .noSuchProcess
                || !ProcessLiveness.ownerIsAlive(pid: child, recordedName: nil, recordedStart: nil)
            stoppedInside.append("\(courseCode)/\(sectionNumber)")
        })

        XCTAssertEqual(stoppedInside, ["ICS3U/1"])
        XCTAssertTrue(childWasGoneBeforeStoppingInside, "The launcher was still running when its section was stopped inside.")
        XCTAssertTrue(leaseWasUpWhileStoppingInside, "The lease came down before the build inside was stopped.")
        XCTAssertFalse(exists(leaseURL(kind: "build")), "…and down once everything was stopped.")
        XCTAssertFalse(launcher.isRunning)

        launcher.run(scriptNamed: "preview.sh", arguments: ["ICS3U", "1"], workingDirectory: root)
        XCTAssertFalse(launcher.isRunning, "Nothing new starts once the process is leaving.")
    }
}
