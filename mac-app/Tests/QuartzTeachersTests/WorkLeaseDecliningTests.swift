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
        XCTAssertGreaterThanOrEqual(cases.count, 32, "Cases went missing from the contract.")

        var ran: Int = 0
        var notForTheMac: Int = 0
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            // A case for another platform only (#413's copy lease) is skipped
            // here — but only when it says what the mac does instead, so a
            // skip is a recorded difference rather than a quiet gap.
            if let platforms = item["appliesOn"] as? [String], !platforms.contains("mac") {
                let onTheMac: String = item["onTheMac"] as? String ?? ""
                XCTAssertFalse(onTheMac.isEmpty, "Not run on the mac, and does not say what the mac does: \(name)")
                notForTheMac += 1
                continue
            }
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
        XCTAssertEqual(ran + notForTheMac, cases.count, "A case was not run.")
        XCTAssertGreaterThanOrEqual(ran, 30, "Cases the mac runs went missing from the contract.")
    }

    func testTheScheduledWaitIsTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(
            ["workLeases", "declining", "scheduledPublishWait"]
        )
        XCTAssertEqual(block["longestSeconds"] as? Int, Int(ScheduledDeploy.longestWaitForTheCourse))
        XCTAssertEqual(block["lookAgainEverySeconds"] as? Int, Int(ScheduledDeploy.lookAgainEvery))
        XCTAssertEqual(block["clock"] as? String, "wall")
    }

    /// `workLeases.declining.sections.cases` (#835): the asked section, the
    /// sections each lease names, and the claim, through the real rule. A
    /// case's `sectionsLine` is a literal sixth line read by the real reader.
    func testTheSectionRuleIsTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.sharedRules(["workLeases", "declining", "sections"])
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 14, "Cases went missing from the contract.")
        var ran: Int = 0
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            let askerWord: String = try XCTUnwrap(item["asker"] as? String, name)
            var asker: WorkLeaseFiles.Asker = .aBuild
            switch askerWord {
            case "aBuild":
                asker = .aBuild
            case "aScheduledPublish":
                asker = .aScheduledPublish
            case "anOutsideDeploy":
                asker = .anOutsideDeploy
            default:
                XCTFail("Unknown asker '\(askerWord)' in: \(name)")
                continue
            }
            let me: [String: Any] = try XCTUnwrap(item["me"] as? [String: Any], name)
            let myPID: Int32 = Int32(try XCTUnwrap(me["pid"] as? Int, name))
            XCTAssertTrue(me.keys.contains("section"), "No section (a number or null) in: \(name)")
            let section: Int? = me["section"] as? Int
            var claim: WorkLeaseFiles.Claim? = nil
            if let claimed = me["claim"] as? [String: Any] {
                claim = WorkLeaseFiles.Claim(
                    moment: try XCTUnwrap(claimed["moment"] as? String, name),
                    pid: Int32(try XCTUnwrap(claimed["pid"] as? Int, name))
                )
            }
            var holdings: [WorkLeaseFiles.Holding] = []
            for entry in try XCTUnwrap(item["others"] as? [[String: Any]], name) {
                let pid: Int32 = Int32(try XCTUnwrap(entry["pid"] as? Int, name))
                let alive: Bool = try XCTUnwrap(entry["alive"] as? Bool, name)
                let courseCode: String = try XCTUnwrap(entry["course"] as? String, name)
                if courseCode.lowercased() != "ics3u" || pid == myPID || !alive {
                    continue
                }
                let kind: String = try XCTUnwrap(entry["kind"] as? String, name)
                let moment: String? = entry["moment"] as? String
                var sections: [WorkLeaseFiles.SectionEntry]? = nil
                if let line = entry["sectionsLine"] as? String {
                    let body: String = "\(pid)\nsleep\n\(moment ?? "")\n\n\n\(line)\n"
                    sections = WorkLeaseFiles.sections(ofALeaseOfKind: kind, text: body)
                } else if let named = entry["sections"] as? [[String: Any]] {
                    var read: [WorkLeaseFiles.SectionEntry] = []
                    for one in named {
                        read.append(WorkLeaseFiles.SectionEntry(
                            section: try XCTUnwrap(one["section"] as? Int, name),
                            moment: try XCTUnwrap(one["moment"] as? String, name)
                        ))
                    }
                    sections = read
                }
                holdings.append(WorkLeaseFiles.Holding(kind: kind, pid: pid, moment: moment, sections: sections))
            }
            let expect: String = try XCTUnwrap(item["expect"] as? String, name)
            let blocking: WorkLeaseFiles.Holding? = WorkLeaseFiles.blocking(
                among: holdings, asker: asker, claim: claim, section: section
            )
            XCTAssertEqual(blocking == nil ? "allowed" : "declined", expect, name)
            ran += 1
        }
        XCTAssertEqual(ran, cases.count, "A case was not run.")
    }

    /// Two sections in one program keep ONE file per kind with an entry
    /// each, adding Section 2 keeps Section 1's moment and line 3, and each
    /// section's claim is its own moment (#835). A rewrite that restamped
    /// the file, or one moment per file, fails here.
    func testTwoSectionsInOneProgramShareAFileAndKeepTheirMoments() throws {
        let build: URL = leaseURL(kind: "build")
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        let first: String = String(decoding: try Data(contentsOf: build), as: UTF8.self)
        let firstEntries: [WorkLeaseFiles.SectionEntry] = try XCTUnwrap(
            WorkLeaseFiles.sections(ofALeaseOfKind: "build", text: first)
        )
        XCTAssertEqual(firstEntries.count, 1)
        // A different millisecond for Section 2's moment.
        Thread.sleep(forTimeInterval: 0.01)
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2)
        let second: String = String(decoding: try Data(contentsOf: build), as: UTF8.self)
        let entries: [WorkLeaseFiles.SectionEntry] = try XCTUnwrap(
            WorkLeaseFiles.sections(ofALeaseOfKind: "build", text: second)
        )
        XCTAssertEqual(entries.count, 2, "One file, two entries.")
        XCTAssertEqual(entries[0], firstEntries[0], "Adding Section 2 keeps Section 1's moment.")
        XCTAssertEqual(WorkLeaseFiles.momentLine(in: second), WorkLeaseFiles.momentLine(in: first), "Line 3 is written once.")
        XCTAssertGreaterThan(entries[1].moment, entries[0].moment, "Section 2 is stamped when it was taken.")
        XCTAssertEqual(
            WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U", section: 2)?.moment,
            entries[1].moment, "Section 2's claim is its own moment, not line 3."
        )
        XCTAssertEqual(
            WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U", section: 1)?.moment,
            entries[0].moment
        )
        XCTAssertNil(
            WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U", section: 3),
            "No claim for a section this program does not hold: its look counts every lease."
        )

        CourseActivity.endPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        let third: String = String(decoding: try Data(contentsOf: build), as: UTF8.self)
        let left: [WorkLeaseFiles.SectionEntry] = try XCTUnwrap(WorkLeaseFiles.sections(ofALeaseOfKind: "build", text: third))
        XCTAssertEqual(left, [entries[1]], "Ending Section 1 drops its entry and keeps Section 2's moment.")
        XCTAssertEqual(WorkLeaseFiles.momentLine(in: third), WorkLeaseFiles.momentLine(in: first))

        // Another program's question about Section 1 is now clear; about 2 is not.
        let mine: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(
            kind: "build", pid: getpid(), moment: WorkLeaseFiles.momentLine(in: third), sections: left
        )
        XCTAssertNil(WorkLeaseFiles.blocking(among: [mine], asker: .aBuild, claim: nil, section: 1))
        XCTAssertNotNil(WorkLeaseFiles.blocking(among: [mine], asker: .aBuild, claim: nil, section: 2))
    }

    /// Plan sharing publishes under `PlanSharing.leaseSection` (0): course-
    /// wide work, so the lease names no sections while it runs and holds
    /// every section, and the sections come back when it ends (#835).
    func testCourseWideWorkMakesTheLeaseHoldTheWholeCourse() throws {
        CourseActivity.beginPreviewBuild(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)
        XCTAssertNotNil(WorkLeaseRegistry.sectionsOnDisk(folderPath: root.path, courseCode: "ICS3U", kind: "build"))
        CourseActivity.beginPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: PlanSharing.leaseSection)
        let text: String = String(decoding: try Data(contentsOf: leaseURL(kind: "build")), as: UTF8.self)
        XCTAssertNil(WorkLeaseFiles.sections(ofALeaseOfKind: "build", text: text), "Course-wide: no sixth line.")
        XCTAssertNil(WorkLeaseFiles.sections(
            ofALeaseOfKind: "publish",
            text: String(decoding: try Data(contentsOf: leaseURL(kind: "publish")), as: UTF8.self)
        ))
        XCTAssertNotNil(
            WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U", section: nil),
            "The course-wide claim is the moment course-wide work began."
        )
        CourseActivity.endPublish(folderPath: root.path, courseCode: "ICS3U", sectionNumber: PlanSharing.leaseSection)
        let after: String = String(decoding: try Data(contentsOf: leaseURL(kind: "build")), as: UTF8.self)
        XCTAssertEqual(WorkLeaseFiles.sections(ofALeaseOfKind: "build", text: after)?.count, 1)
        XCTAssertNil(WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U", section: nil))
    }

    /// Another program building a SIBLING section leaves this section's
    /// build free, and the trail names the section when the lease does
    /// (#835). A lease that names no section still declines every section.
    func testASiblingBuiltElsewhereLeavesThisSectionFree() throws {
        let pid: Int32 = try startTheOtherProgram()
        let url: URL = try writeOthersLease(kind: "build", pid: pid)
        var text: String = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let moment: String = try XCTUnwrap(WorkLeaseFiles.momentLine(in: text))
        text += "\nsections 2=\(moment)\n"
        try Data(text.utf8).write(to: url, options: .atomic)

        XCTAssertNil(WorkLeaseRegistry.whatBlocksABuild(
            folderPath: root.path, courseCode: "ICS3U", afterTaking: false, section: 1
        ))
        let held: WorkLeaseFiles.Holding = try XCTUnwrap(WorkLeaseRegistry.whatBlocksABuild(
            folderPath: root.path, courseCode: "ICS3U", afterTaking: false, section: 2
        ))
        XCTAssertNotNil(WorkLeaseRegistry.whatBlocksABuild(
            folderPath: root.path, courseCode: "ICS3U", afterTaking: false
        ), "A course-wide question is held by any lease of the course.")
        XCTAssertEqual(
            WorkLeaseRegistry.declinedLine(act: "Preview", sectionNumber: 2, holding: held),
            "declined Preview — Section 2 of the course is being built by process \(pid) somewhere else on this Mac"
        )
        XCTAssertFalse(WorkLeaseRegistry.anotherProgramIsBuilding(folderPath: root.path, courseCode: "ICS3U", section: 1))
        XCTAssertTrue(WorkLeaseRegistry.anotherProgramIsBuilding(folderPath: root.path, courseCode: "ICS3U", section: 2))

        // The same lease with no sixth line: every section.
        try writeOthersLease(kind: "build", pid: pid)
        let wide: WorkLeaseFiles.Holding = try XCTUnwrap(WorkLeaseRegistry.whatBlocksABuild(
            folderPath: root.path, courseCode: "ICS3U", afterTaking: false, section: 1
        ))
        XCTAssertEqual(
            WorkLeaseRegistry.declinedLine(act: "Preview", sectionNumber: 1, holding: wide),
            "declined Preview — the course is being built by process \(pid) somewhere else on this Mac"
        )
    }

    /// A scheduled deploy waits only for its own section, and its leases
    /// name its section (#835, Q1).
    func testAScheduledPublishWaitsOnlyForItsOwnSection() throws {
        let sibling: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(
            kind: "build", pid: 4321, moment: "2026-11-13T12:00:00.1000000Z",
            sections: [WorkLeaseFiles.SectionEntry(section: 1, moment: "2026-11-13T12:00:00.1000000Z")]
        )
        var looks: Int = 0
        var pauses: Int = 0
        var firstClock: Date = Date()
        let answer: ScheduledDeploy.CourseWait = ScheduledDeploy.waitForTheCourse(
            courseCode: "ICS3U", coursesDirectory: coursesURL, section: 2,
            now: { return firstClock },
            // A pretend clock, so a wrong answer stands down at once rather
            // than spinning for ten real minutes.
            pause: { seconds in
                pauses += 1
                firstClock = firstClock.addingTimeInterval(seconds)
            },
            heldElsewhere: {
                looks += 1
                return [sibling]
            }
        )
        XCTAssertEqual(pauses, 0, "A sibling's build must not make it wait.")
        guard case .goAhead(let leases, _, let waitedFor) = answer else {
            return XCTFail("Expected to go ahead, got \(answer)")
        }
        XCTAssertNil(waitedFor)
        XCTAssertEqual(looks, 2, "Looked, took, looked again.")
        XCTAssertEqual(leases.count, 2)
        for url in leases {
            let text: String = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            let named: [WorkLeaseFiles.SectionEntry] = try XCTUnwrap(
                WorkLeaseFiles.sections(ofALeaseOfKind: url.lastPathComponent.contains(".build.") ? "build" : "publish", text: text)
            )
            XCTAssertEqual(named.count, 1)
            XCTAssertEqual(named[0].section, 2)
            XCTAssertEqual(named[0].moment, WorkLeaseFiles.momentLine(in: text), "One moment, one claim.")
            WorkLeaseFiles.remove(at: url)
        }

        var waits: Int = 0
        let own: WorkLeaseFiles.Holding = WorkLeaseFiles.Holding(
            kind: "build", pid: 4321, moment: "2026-11-13T12:00:00.1000000Z",
            sections: [WorkLeaseFiles.SectionEntry(section: 2, moment: "2026-11-13T12:00:00.1000000Z")]
        )
        var clock: Date = Date()
        let stood: ScheduledDeploy.CourseWait = ScheduledDeploy.waitForTheCourse(
            courseCode: "ICS3U", coursesDirectory: coursesURL, section: 2,
            now: { return clock },
            pause: { seconds in
                waits += 1
                clock = clock.addingTimeInterval(seconds)
            },
            heldElsewhere: { return [own] }
        )
        guard case .standDown = stood else {
            return XCTFail("Its own section held for ten minutes: it stands down, got \(stood)")
        }
        XCTAssertGreaterThan(waits, 0)
    }

    /// The window hands out an address another program's live preview in
    /// this folder is NOT serving (#835): two copies of Plantoir were both
    /// handed 8081, and the second ended the first (measured 3 of 3).
    func testAPreviewSkipsAnAddressAnotherProgramServes() throws {
        let pid: Int32 = try startTheOtherProgram()
        let url: URL = try writeOthersLease(kind: "preview", pid: pid)
        var text: String = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let moment: String = try XCTUnwrap(WorkLeaseFiles.momentLine(in: text))
        text += "\nsections 1=\(moment)@8081 3=\(moment)@8083\n"
        try Data(text.utf8).write(to: url, options: .atomic)

        let lease: PreviewLeases.Lease = try PreviewLeases.lease(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 2)
        XCTAssertEqual(lease.port, 8082)
        let next: PreviewLeases.Lease = try PreviewLeases.lease(folderPath: root.path, courseCode: "MPM2D", sectionNumber: 1)
        XCTAssertEqual(next.port, 8084, "Another course in the folder shares the builder's addresses too.")
        let mine: String = String(decoding: try Data(contentsOf: leaseURL(kind: "preview")), as: UTF8.self)
        XCTAssertEqual(
            WorkLeaseFiles.sections(ofALeaseOfKind: "preview", text: mine)?.first?.port, 8082,
            "This program's preview lease names its address, so the other program avoids it in turn."
        )
        XCTAssertThrowsError(try PreviewLeases.lease(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 4))
        PreviewLeases.release(lease)
        PreviewLeases.release(next)

        // Gone: its addresses are free again.
        other?.terminate()
        other?.waitUntilExit()
        let free: PreviewLeases.Lease = try PreviewLeases.lease(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 3)
        XCTAssertEqual(free.port, 8081)
        PreviewLeases.release(free)
    }

    /// `app-rules.json` → `previewPorts.anotherProgramsPreviews.cases`
    /// (#835): real lease files for the other programs (a live `/bin/sleep`
    /// each, or one that has ended), this program's own previews in the
    /// store, and the address `PreviewLeases.lease` hands out.
    func testThePreviewPortCasesAreTheContracts() throws {
        let block: [String: Any] = try WorkLeaseLivenessTests.contract(
            "app-rules.json", ["previewPorts", "anotherProgramsPreviews"]
        )
        let cases: [[String: Any]] = try XCTUnwrap(block["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 7, "Cases went missing from the contract.")
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesURL)
        for item in cases {
            let name: String = item["name"] as? String ?? "?"
            PreviewLeases.reset()
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var holders: [Process] = []
            for entry in try XCTUnwrap(item["others"] as? [[String: Any]], name) {
                let process: Process = Process()
                process.executableURL = URL(fileURLWithPath: entry["alive"] as? Bool == true ? "/bin/sleep" : "/usr/bin/true")
                process.arguments = entry["alive"] as? Bool == true ? ["60"] : []
                try process.run()
                if entry["alive"] as? Bool != true {
                    process.waitUntilExit()
                } else {
                    holders.append(process)
                }
                let pid: Int32 = process.processIdentifier
                var processName: String = "true"
                var started: String = "1.000000"
                if case .found(let tableName, _, let startTime) = ProcessLiveness.askTheProcessTable(pid: pid) {
                    processName = tableName
                    started = startTime
                }
                let moment: String = ProcessLiveness.leaseMomentText(Date().addingTimeInterval(-1))
                var body: String = "\(pid)\n\(processName)\n\(moment)\n\(started)\n"
                if let ports = entry["ports"] as? [Int] {
                    var entries: [WorkLeaseFiles.SectionEntry] = []
                    var section: Int = 1
                    for port in ports {
                        entries.append(WorkLeaseFiles.SectionEntry(section: section, moment: moment, port: port))
                        section += 1
                    }
                    body += "\n" + WorkLeaseFiles.sectionsLine(entries) + "\n"
                }
                let course: String = try XCTUnwrap(entry["course"] as? String, name)
                try Data(body.utf8).write(
                    to: directory.appendingPathComponent(WorkLeaseFiles.fileName(courseCode: course, kind: "preview", pid: pid)),
                    options: .atomic
                )
            }
            var section: Int = 10
            for port in try XCTUnwrap(item["mine"] as? [Int], name) {
                PreviewLeases.store.active.append(PreviewLeases.Lease(
                    port: port, folderPath: root.path, courseCode: "EXC2O", sectionNumber: section
                ))
                section += 1
            }
            var answer: String = ""
            do {
                let lease: PreviewLeases.Lease = try PreviewLeases.lease(
                    folderPath: root.path, courseCode: "EXC2O", sectionNumber: 4
                )
                answer = String(lease.port)
            } catch PreviewLeases.Problem.allPortsBusy {
                answer = "allPortsBusy"
            }
            var expected: String = ""
            if let port = item["expect"] as? Int {
                expected = String(port)
            } else {
                expected = try XCTUnwrap(item["expect"] as? String, name)
            }
            XCTAssertEqual(answer, expected, name)
            for holder in holders {
                holder.terminate()
                holder.waitUntilExit()
            }
        }
        PreviewLeases.reset()
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
        // Six lines since #835 (line 5 empty, the sections on line 6), and
        // the empty remainder after the last line feed.
        XCTAssertEqual(lines.count, 7, "Six lines and the empty remainder after the last line feed.")
        XCTAssertEqual(String(lines[4]), "", "Line 5 is empty: a build lease carries no door key.")
        XCTAssertEqual(String(lines[5]), "sections 1=\(lines[2])", "Line 6 names the section, taken at line 3's moment.")
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
            WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U", section: 1)
        )

        try writeOthersLease(kind: "build", pid: pid, moment: "2000-01-01T00:00:00.0000000Z")
        XCTAssertNotNil(
            WorkLeaseRegistry.whatBlocksABuild(folderPath: root.path, courseCode: "ICS3U", afterTaking: true, section: 1),
            "An earlier lease wins."
        )
        try writeOthersLease(kind: "build", pid: pid, moment: "2999-01-01T00:00:00.0000000Z")
        XCTAssertNil(
            WorkLeaseRegistry.whatBlocksABuild(folderPath: root.path, courseCode: "ICS3U", afterTaking: true, section: 1),
            "A later lease is the other program's to back off from (mine: \(mine.moment))."
        )
        XCTAssertNotNil(
            WorkLeaseRegistry.whatBlocksABuild(folderPath: root.path, courseCode: "ICS3U", afterTaking: false, section: 1),
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
            WorkLeaseRegistry.buildClaim(folderPath: root.path, courseCode: "ICS3U", section: 1)
        )
        // The outside build lands a millisecond after the window's build…
        let outsideMoment: String = try WorkLeaseDecliningTests.moment(windowsBuild.moment, plusMilliseconds: 1)
        try writeOthersLease(kind: "build", pid: pid, moment: outsideMoment)
        // …and the window's preview lease after that.
        _ = try PreviewLeases.lease(folderPath: root.path, courseCode: "ICS3U", sectionNumber: 1)

        let windowGoesAhead: Bool = WorkLeaseRegistry.whatBlocksABuild(
            folderPath: root.path, courseCode: "ICS3U", afterTaking: true, section: 1
        ) == nil

        // What the outside program sees: the window's two lease files, read
        // back from disk as that program would read them.
        var windowsLeases: [WorkLeaseFiles.Holding] = []
        for kind in ["build", "preview"] {
            let text: String = try String(contentsOf: leaseURL(kind: kind), encoding: .utf8)
            windowsLeases.append(WorkLeaseFiles.Holding(
                kind: kind, pid: getpid(), moment: WorkLeaseFiles.momentLine(in: text),
                sections: WorkLeaseFiles.sections(ofALeaseOfKind: kind, text: text)
            ))
        }
        let outsideGoesAhead: Bool = WorkLeaseFiles.blocking(
            among: windowsLeases, asker: .aBuild,
            claim: WorkLeaseFiles.Claim(moment: outsideMoment, pid: pid), section: 1
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

        let deploy: String = try WorkLeaseDecliningTests.body(of: "func deployAndWait(pressedByTheAssistant:", in: source)
        let claim: Range<String.Index> = try XCTUnwrap(deploy.range(of: "WorkLeaseRegistry.claimAPublish("))
        let stop: Range<String.Index> = try XCTUnwrap(deploy.range(of: "await stopPreviewAndWait()"))
        XCTAssertLessThan(claim.lowerBound, stop.lowerBound, "The Deploy stops the preview before claiming the course.")
        XCTAssertNil(deploy.range(of: "CourseActivity.beginPublish("), "A second, later bracket crept back.")

        // Since #812 the window records its build and takes its lease through
        // `PreviewStartRecords.begin`, so the two are read there, and the
        // window is read for the call and for the look that follows it.
        let preview: String = try WorkLeaseDecliningTests.body(of: "func startPreview(at request:", in: source)
        XCTAssertNil(preview.range(of: "previewBuildWait.begin("), "The Preview records its build outside PreviewStartRecords.begin.")
        XCTAssertNil(preview.range(of: "PreviewLeases.lease("), "The Preview takes its lease outside PreviewStartRecords.begin.")
        let taken: Range<String.Index> = try XCTUnwrap(preview.range(of: "PreviewStartRecords.begin("))
        let look: Range<String.Index> = try XCTUnwrap(preview.range(of: "WorkLeaseRegistry.whatBlocksABuild("))
        XCTAssertLessThan(taken.lowerBound, look.lowerBound, "The Preview looks before it has taken both.")

        let recordsURL: URL = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Models/PreviewStartRecords.swift")
        let records: String = try String(contentsOf: recordsURL, encoding: .utf8)
        let begin: String = try WorkLeaseDecliningTests.body(of: "static func begin(", in: records)
        let build: Range<String.Index> = try XCTUnwrap(begin.range(of: "wait.begin("))
        let lease: Range<String.Index> = try XCTUnwrap(begin.range(of: "PreviewLeases.lease("))
        XCTAssertLessThan(build.lowerBound, lease.lowerBound, "The preview lease goes down before the build lease.")
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

    /// An outside assistant is told `courseIsBeingBuilt` while another
    /// program BUILDS the course, and nothing reaches the launcher. MUST FAIL
    /// before #156 (and, for the sentence, before #433, when it was
    /// `courseIsBusy`).
    func testAnOutsideAssistantIsRefusedWhileAnotherProgramBuilds() async throws {
        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "build", pid: pid)
        let mcp: AssistToolRunner = runner(surface: .mcp)

        let deployed: AssistToolOutcome = await mcp.run(call: call("deploy_section", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(deployed.detail, AssistWording.courseIsBeingBuilt(course: "ICS3U"))
        XCTAssertEqual(siteWork.deploys, 0)

        let rebuilt: AssistToolOutcome = await mcp.run(call: call("rebuild_preview", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(rebuilt.detail, AssistWording.courseIsBeingBuilt(course: "ICS3U"))
        XCTAssertEqual(siteWork.previewRebuilds, 0)
        XCTAssertTrue(trailText().contains("declined the assistant's deploy"), trailText())
    }

    /// Another program's SERVED preview no longer refuses an outside
    /// assistant's deploy (#433, Russell 2026-10-03, reversing #156's M2
    /// ruling for Claude and Codex): it goes ahead, and the answer says the
    /// open preview may have closed. MUST FAIL before #433.
    func testAnotherProgramsServedPreviewLetsAnOutsideDeployGoAhead() async throws {
        let pid: Int32 = try startTheOtherProgram()
        try writeOthersLease(kind: "preview", pid: pid)
        let mcp: AssistToolRunner = runner(surface: .mcp)
        let deployed: AssistToolOutcome = await mcp.run(call: call("deploy_section", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(siteWork.deploys, 1, deployed.detail)
        XCTAssertTrue(
            deployed.detail.hasSuffix(AssistWording.deployClosedAnOpenPreview(course: "ICS3U", section: "1")),
            deployed.detail
        )
        XCTAssertTrue(trailText().contains(
            "an outside assistant deployed while a preview of the course was open in Plantoir"
        ), trailText())
    }

    /// The real headless deploy an outside assistant takes asks only about
    /// building (#433): past a served preview, held back by a build. The
    /// in-app assistant's (the default) is still held back by the preview.
    /// MUST FAIL with `.anOutsideDeploy` reading `kindsThatBlockABuild`.
    func testTheOutsideDeploysLeaseQuestionIsOnlyAboutBuilding() throws {
        let pid: Int32 = try startTheOtherProgram()
        let previewURL: URL = try writeOthersLease(kind: "preview", pid: pid)
        let folder: String = root.path
        XCTAssertNil(WorkLeaseRegistry.whatBlocksABuild(
            folderPath: folder, courseCode: "ICS3U", afterTaking: false, asker: .anOutsideDeploy
        ))
        XCTAssertNotNil(WorkLeaseRegistry.whatBlocksABuild(
            folderPath: folder, courseCode: "ICS3U", afterTaking: false
        ), "The window and the in-app assistant keep #156's rule.")
        try FileManager.default.removeItem(at: previewURL)
        try writeOthersLease(kind: "build", pid: pid)
        XCTAssertNotNil(WorkLeaseRegistry.whatBlocksABuild(
            folderPath: folder, courseCode: "ICS3U", afterTaking: false, asker: .anOutsideDeploy
        ))
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

    /// The in-app assistant asked for the preview of a section THIS app is
    /// deploying (#381's review, S1): refused with the section's sentence,
    /// before a window is opened, a preview stopped or a rebuild run — the
    /// window's own Preview refuses, so going on would tell the conversation
    /// a preview is on its way while none is. MUST FAIL without the check in
    /// `bringThePreviewUpToDate`.
    func testTheInAppAssistantsPreviewIsRefusedWhileThisAppDeploysTheSection() async throws {
        let folder: URL = try XCTUnwrap(workspace.workspaceURL)
        CourseActivity.beginPublish(folderPath: folder.path, courseCode: "ICS3U", sectionNumber: 1)
        let local: AssistToolRunner = runner(surface: .local)
        let rebuilt: AssistToolOutcome = await local.run(call: call("rebuild_preview", ["course": "ICS3U", "section": 1]))
        XCTAssertEqual(rebuilt.detail, AssistWording.sectionIsBeingDeployed(course: "ICS3U", section: "1"))
        XCTAssertEqual(siteWork.previewRebuilds, 0, "No rebuild may run.")
        XCTAssertTrue(trailText().contains(WorkLeaseRegistry.lineWhenItsSectionIsBeingDeployed), trailText())
        CourseActivity.endPublish(folderPath: folder.path, courseCode: "ICS3U", sectionNumber: 1)
    }

    /// The control: another section of the course deploying does not hold
    /// the assistant's preview back (the rule names the same section).
    func testTheInAppAssistantsPreviewOfAnotherSectionStillRebuilds() async throws {
        let folder: URL = try XCTUnwrap(workspace.workspaceURL)
        CourseActivity.beginPublish(folderPath: folder.path, courseCode: "ICS3U", sectionNumber: 2)
        let local: AssistToolRunner = runner(surface: .local)
        let rebuilt: AssistToolOutcome = await local.run(call: call("rebuild_preview", ["course": "ICS3U", "section": 1]))
        XCTAssertNotEqual(rebuilt.detail, AssistWording.sectionIsBeingDeployed(course: "ICS3U", section: "1"))
        CourseActivity.endPublish(folderPath: folder.path, courseCode: "ICS3U", sectionNumber: 2)
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
