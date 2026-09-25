import Foundation
import XCTest
@testable import QuartzTeachers

/// A scheduled publish tells the teacher how it went with a macOS
/// notification (#212).
///
/// Nothing here reaches the real notification centre. The test host IS
/// Plantoir.app, the same bundle whose permission the feature reads, so every
/// test either uses `RecordingNotifications` or checks that the suite's own
/// default does nothing.
@MainActor
final class ScheduledPublishNoticeTests: XCTestCase {

    // MARK: - Stored properties

    private var home: URL = URL(fileURLWithPath: "/nonexistent")

    /// The working folder every record and notification here belongs to
    /// (#237). One fixed id: these cases are about sections and runs, and
    /// the per-folder key is pinned in `ScheduledDeployTests`.
    private static let folderID: String = "0a1b2c3d"
    private var trailFolder: URL = URL(fileURLWithPath: "/nonexistent")
    private var previousStore: ProblemReportStore = ActivityTrail.store

    // MARK: - Set up and tear down

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("notice-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        trailFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("notice-trail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: trailFolder, withIntermediateDirectories: true)
        previousStore = ActivityTrail.store
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder)
    }

    override func tearDownWithError() throws {
        ActivityTrail.store = previousStore
        ScheduledPublishNotice.poster = QuietNotifications()
        try? FileManager.default.removeItem(at: home)
        try? FileManager.default.removeItem(at: trailFolder)
        try super.tearDownWithError()
    }

    // MARK: - The suite never reaches the real notification centre

    /// The suite starts with a poster that does nothing, and the real one
    /// refuses under the suite whatever it is asked — so no test, including one
    /// that forgets its fake, can put a permission question on the screen of
    /// the Mac running it.
    func testTheSuiteNeverReachesTheRealNotificationCentre() async throws {
        XCTAssertTrue(ScheduledPublishNotice.defaultPoster() is QuietNotifications)

        let real: SystemNotifications = SystemNotifications()
        let permission: ScheduledPublishNotice.Permission = await real.permission()
        XCTAssertEqual(permission, .notAllowed)
        let allowed: Bool = await real.askPermission()
        XCTAssertFalse(allowed)
        do {
            try await real.post(identifier: "never", body: "never")
            XCTFail("The real poster posted from inside the suite")
        } catch {
            // Refused, as it must be.
        }
    }

    // MARK: - The contract: announcing

    /// Every row of `notification.announcing`, played once per kind the
    /// contract names when the row says `everyKind` — walked from
    /// `Kind.allCases`, so a kind added later is covered without touching this.
    func testEveryAnnouncingCaseHolds() async throws {
        let cases: [[String: Any]] = try Self.cases("announcing")
        XCTAssertFalse(cases.isEmpty)
        for oneCase in cases {
            let name: String = try XCTUnwrap(oneCase["name"] as? String)
            let record: String = try XCTUnwrap(oneCase["record"] as? String)
            if record == "everyKind" {
                for kind in ScheduledPublishOutcome.Kind.allCases {
                    try await play(announcing: oneCase, name: name, kind: kind)
                }
            } else {
                XCTAssertEqual(record, "none", name)
                try await play(announcing: oneCase, name: name, kind: nil)
            }
        }
    }

    /// The body is the section's own sentence for every kind, and none of them
    /// mentions the machinery (rule 1).
    func testTheBodyIsTheSectionsOwnSentence() {
        let machineryWords: [String] = [
            "toolchain", "script", "docker", "container", "colima", "symlink", "vault", "launchd",
        ]
        for kind in ScheduledPublishOutcome.Kind.allCases {
            let stopped: ScheduledPublishOutcome.Stopped = ScheduledPublishOutcome.Stopped(
                kind: kind, destination: "Netlify", when: Date()
            )
            let body: String = ScheduledPublishNotice.body(for: stopped, course: "ICS4U", section: 3)
            XCTAssertEqual(
                body, ScheduledPublishOutcome.sentence(for: stopped, course: "ICS4U", section: 3), "\(kind)"
            )
            XCTAssertTrue(body.hasPrefix("ICS4U Section 3"), "\(kind): the section must lead, so a cut-short banner still names it")
            for word in machineryWords {
                XCTAssertFalse(body.lowercased().contains(word), "\(kind) says \(word)")
            }
        }
    }

    // MARK: - The contract: what stays on show

    /// Two working folders holding the same section (#237) each have their
    /// own alarm and record, and so their own notification: one folder's run
    /// does not replace the other's news, and one folder's Dismiss does not
    /// withdraw it. Fails with the folder id taken out of `identifier`.
    func testTwoWorkingFoldersKeepTheirOwnNotification() async throws {
        let fake: RecordingNotifications = RecordingNotifications(permission: .allowed)
        ScheduledPublishNotice.poster = fake
        let folders: [String] = ["0a1b2c3d", "deadbeef"]
        for folder in folders {
            XCTAssertTrue(ScheduledPublishOutcome.recordStopped(
                ScheduledPublishOutcome.Stopped(kind: .didNotFinish, destination: Self.destination, when: Date()),
                inHomeFolder: home, course: "ICS3U", section: 1, folderID: folder
            ))
            let announcement: ScheduledPublishNotice.Announcement = await ScheduledPublishNotice.announce(
                inHomeFolder: home, course: "ICS3U", section: 1, folderID: folder, poster: fake
            )
            XCTAssertEqual(announcement, .posted)
        }
        XCTAssertEqual(fake.shown.count, 2, "One folder's run replaced the other folder's notification")

        ScheduledPublishNotice.teacherDismissed(
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: "0a1b2c3d"
        )
        XCTAssertEqual(
            Array(fake.shown.keys),
            [ScheduledPublishNotice.identifier(course: "ICS3U", section: 1, folderID: "deadbeef")],
            "Dismissing in one folder withdrew the other folder's notification"
        )
        XCTAssertNotNil(ScheduledPublishOutcome.stopped(
            inHomeFolder: home, course: "ICS3U", section: 1, folderID: "deadbeef"
        ))
    }

    /// Every row of `notification.onShow`: a later run replaces, sections are
    /// kept apart, and dismissing the band withdraws exactly that section's.
    func testEveryOnShowCaseHolds() async throws {
        let cases: [[String: Any]] = try Self.cases("onShow")
        XCTAssertFalse(cases.isEmpty)
        for oneCase in cases {
            let name: String = try XCTUnwrap(oneCase["name"] as? String)
            let fake: RecordingNotifications = RecordingNotifications(permission: .allowed)
            ScheduledPublishNotice.poster = fake
            let steps: [[String: Any]] = try XCTUnwrap(oneCase["steps"] as? [[String: Any]])
            for step in steps {
                if let post = step["post"] as? [String: Any] {
                    let course: String = try XCTUnwrap(post["course"] as? String)
                    let section: Int = try XCTUnwrap(post["section"] as? Int)
                    let kind: ScheduledPublishOutcome.Kind = try Self.kind(named: try XCTUnwrap(post["kind"] as? String))
                    try writeRecord(kind: kind, course: course, section: section)
                    let announcement: ScheduledPublishNotice.Announcement = await ScheduledPublishNotice.announce(
                        inHomeFolder: home, course: course, section: section, folderID: Self.folderID, poster: fake
                    )
                    XCTAssertEqual(announcement, .posted, name)
                } else {
                    let dismiss: [String: Any] = try XCTUnwrap(step["dismiss"] as? [String: Any], name)
                    ScheduledPublishNotice.teacherDismissed(
                        inHomeFolder: home,
                        course: try XCTUnwrap(dismiss["course"] as? String),
                        section: try XCTUnwrap(dismiss["section"] as? Int),
                        folderID: Self.folderID
                    )
                }
            }
            var expected: [String: String] = [:]
            for shown in try XCTUnwrap(oneCase["stillShown"] as? [[String: Any]]) {
                let course: String = try XCTUnwrap(shown["course"] as? String)
                let section: Int = try XCTUnwrap(shown["section"] as? Int)
                let kind: ScheduledPublishOutcome.Kind = try Self.kind(named: try XCTUnwrap(shown["kind"] as? String))
                let identifier: String = ScheduledPublishNotice.identifier(course: course, section: section, folderID: Self.folderID)
                expected[identifier] = ScheduledPublishOutcome.sentence(
                    for: ScheduledPublishOutcome.Stopped(kind: kind, destination: Self.destination, when: Date()),
                    course: course, section: section
                )
            }
            XCTAssertEqual(fake.shown, expected, name)
            try? FileManager.default.removeItem(at: ScheduledPublishOutcome.directory(inHomeFolder: home))
        }
    }

    /// The Dismiss button goes through the one function that withdraws the
    /// notification, rather than clearing the record on its own.
    func testTheDismissButtonWithdrawsTheNotification() throws {
        let source: String = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("mac-app/QuartzTeachers/Views/Section/SectionDetailView.swift"),
            encoding: .utf8
        )
        let start: Range<String.Index> = try XCTUnwrap(source.range(of: "func dismissScheduledPublishNotice()"))
        let rest: Substring = source[start.upperBound...]
        let end: String.Index = rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex
        let body: Substring = rest[..<end]
        XCTAssertTrue(body.contains("ScheduledPublishNotice.teacherDismissed("), String(body))
        XCTAssertFalse(body.contains("ScheduledPublishOutcome.clear("), "Dismiss clears the record without withdrawing the notification")
    }

    // MARK: - The ceiling

    /// A notification service that never answers — and ignores being
    /// cancelled, as `UNUserNotificationCenter.add` does — must not hold a
    /// finished run alive. A task group racing the post against a sleep fails
    /// this: the group waits for the post however long it takes.
    func testAPostThatNeverAnswersIsLeftBehindAtTheCeiling() async throws {
        try writeRecord(kind: .succeeded, course: "ICS4U", section: 1)
        let fake: RecordingNotifications = RecordingNotifications(permission: .allowed)
        fake.neverAnswers = true
        let finished: XCTestExpectation = expectation(description: "the announcement came back")
        let home: URL = self.home
        let result: ResultBox = ResultBox()
        Task {
            let announcement: ScheduledPublishNotice.Announcement = await ScheduledPublishNotice.announce(
                inHomeFolder: home, course: "ICS4U", section: 1, folderID: Self.folderID, poster: fake, ceiling: .milliseconds(50)
            )
            result.announcement = announcement
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(result.announcement, .couldNotBeSent)
        XCTAssertEqual(fake.postsAttempted, 1)
        let trail: String = ActivityTrail.store.activityText(includingPrompts: true)
        XCTAssertTrue(trail.contains("a notification about a scheduled publish could not be sent"), trail)
    }

    /// A permission check that never answers is bounded by the same ceiling.
    func testAPermissionCheckThatNeverAnswersIsLeftBehindToo() async throws {
        try writeRecord(kind: .didNotFinish, course: "ICS4U", section: 1)
        let fake: RecordingNotifications = RecordingNotifications(permission: .allowed)
        fake.permissionNeverAnswers = true
        let finished: XCTestExpectation = expectation(description: "the announcement came back")
        let home: URL = self.home
        Task {
            _ = await ScheduledPublishNotice.announce(
                inHomeFolder: home, course: "ICS4U", section: 1, folderID: Self.folderID, poster: fake, ceiling: .milliseconds(50)
            )
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(fake.postsAttempted, 0)
    }

    // MARK: - The contract: asking

    /// Every row of `notification.asking`, played from where the row says the
    /// publish was scheduled.
    @MainActor
    func testEveryAskingCaseHolds() async throws {
        let cases: [[String: Any]] = try Self.cases("asking")
        XCTAssertFalse(cases.isEmpty)
        for oneCase in cases {
            let from: String = try XCTUnwrap(oneCase["from"] as? String)
            let permission: ScheduledPublishNotice.Permission = try XCTUnwrap(
                ScheduledPublishNotice.Permission(rawValue: try XCTUnwrap(oneCase["permission"] as? String))
            )
            let asks: Bool = try XCTUnwrap(oneCase["asks"] as? Bool)
            let trailSays: [String] = try XCTUnwrap(oneCase["trailSays"] as? [String])
            let answer: String = (oneCase["answer"] as? String) ?? "notAllowed"
            let label: String = "\(from), \(permission)"

            ActivityTrail.store = ProblemReportStore(folderURL: trailFolder.appendingPathComponent(UUID().uuidString))
            let fake: RecordingNotifications = RecordingNotifications(permission: permission)
            fake.answer = answer == "allowed"
            ScheduledPublishNotice.poster = fake

            switch from {
            case "window":
                await ScheduledPublishNotice.askPermissionIfNotAskedYet(course: "ICS3U", section: 1)
            case "scheduledRun":
                try writeRecord(kind: .succeeded, course: "ICS3U", section: 1)
                _ = await ScheduledPublishNotice.announce(inHomeFolder: home, course: "ICS3U", section: 1, folderID: Self.folderID)
            case "appAssistant", "outsideAssistant":
                try await schedule(from: from == "appAssistant" ? .local : .mcp, fake: fake, expectAsking: asks)
            default:
                XCTFail("A row schedules from somewhere this test does not know: \(from)")
            }

            XCTAssertEqual(fake.questionsAsked, asks ? 1 : 0, label)
            let lines: [String] = linesOnTheTrail()
            XCTAssertEqual(lines, trailSays, label)
        }
    }

    // MARK: - What macOS's answer means

    /// `.provisional` is allowed, an unanswered question is
    /// not-asked-yet, and anything this build does not know is not allowed.
    func testTheSystemsAnswerIsReadAsTheContractSpellsIt() {
        XCTAssertEqual(ScheduledPublishNotice.permission(from: .authorized), .allowed)
        XCTAssertEqual(ScheduledPublishNotice.permission(from: .provisional), .allowed)
        XCTAssertEqual(ScheduledPublishNotice.permission(from: .notDetermined), .notAskedYet)
        XCTAssertEqual(ScheduledPublishNotice.permission(from: .denied), .notAllowed)
    }

    /// The contract's one spelling of permission is this enum's, both ways.
    func testTheContractSpellsPermissionTheOneWay() throws {
        var spellings: Set<String> = []
        for group in ["announcing", "asking"] {
            for oneCase in try Self.cases(group) {
                spellings.insert(try XCTUnwrap(oneCase["permission"] as? String))
            }
        }
        var known: Set<String> = []
        for permission in ScheduledPublishNotice.Permission.allCases {
            known.insert(permission.rawValue)
        }
        XCTAssertEqual(spellings, known)
    }

    // MARK: - Functions

    private static let destination: String = "Netlify"

    /// Play one `announcing` row for one kind (or for no record at all).
    private func play(announcing oneCase: [String: Any], name: String, kind: ScheduledPublishOutcome.Kind?) async throws {
        try? FileManager.default.removeItem(at: ScheduledPublishOutcome.directory(inHomeFolder: home))
        ActivityTrail.store = ProblemReportStore(folderURL: trailFolder.appendingPathComponent(UUID().uuidString))

        let permission: ScheduledPublishNotice.Permission = try XCTUnwrap(
            ScheduledPublishNotice.Permission(rawValue: try XCTUnwrap(oneCase["permission"] as? String)), name
        )
        let fake: RecordingNotifications = RecordingNotifications(permission: permission)
        fake.postFails = try XCTUnwrap(oneCase["postFails"] as? Bool, name)
        if let kind {
            try writeRecord(kind: kind, course: "ICS4U", section: 2)
        }

        _ = await ScheduledPublishNotice.announce(inHomeFolder: home, course: "ICS4U", section: 2, folderID: Self.folderID, poster: fake)

        let label: String = "\(name) — \(kind?.rawValue ?? "no record")"
        let posts: Bool = try XCTUnwrap(oneCase["posts"] as? Bool, name)
        if posts, let kind {
            let expected: String = ScheduledPublishOutcome.sentence(
                for: ScheduledPublishOutcome.Stopped(kind: kind, destination: Self.destination, when: Date()),
                course: "ICS4U", section: 2
            )
            XCTAssertEqual(fake.shown, [ScheduledPublishNotice.identifier(course: "ICS4U", section: 2, folderID: Self.folderID): expected], label)
        } else {
            XCTAssertEqual(fake.shown, [:], label)
        }
        let asksForPermission: Bool = try XCTUnwrap(oneCase["asksForPermission"] as? Bool, name)
        XCTAssertEqual(fake.questionsAsked, asksForPermission ? 1 : 0, label)

        let lines: [String] = linesOnTheTrail()
        if let trailSays = oneCase["trailSays"] as? String {
            XCTAssertEqual(lines, [trailSays], label)
        } else {
            XCTAssertEqual(lines, [], label)
        }
    }

    /// Schedule ICS3U Section 1 through the assistant on one surface, and wait
    /// until the permission question has been dealt with.
    ///
    /// For the outside assistant, which must NOT ask, the proof is ordering:
    /// the app's own assistant schedules straight after it, and both would ask
    /// on the main actor in the order they were scheduled — so by the time the
    /// second has asked, the first has had every chance to.
    @MainActor
    private func schedule(from surface: AssistToolRunner.Surface, fake: RecordingNotifications, expectAsking: Bool) async throws {
        let agents: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notice-agents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        ScheduledDeploy.launchAgentsDirectoryOverride = agents.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(
            at: agents.appendingPathComponent("LaunchAgents"), withIntermediateDirectories: true
        )
        ScheduledDeploy.scheduledScriptsDirectoryOverride = agents.appendingPathComponent("scheduled")
        var roots: [URL] = [agents]
        defer {
            ScheduledDeploy.launchAgentsDirectoryOverride = nil
            ScheduledDeploy.scheduledScriptsDirectoryOverride = nil
            for root in roots {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let asked: XCTestExpectation = expectation(description: "the question was dealt with")
        fake.onQuestionAnswered = {
            asked.fulfill()
        }

        let made = try AssistFixture.makeRunner(hasDeployedBefore: true, surface: surface)
        roots.append(made.root)
        let set: AssistToolOutcome = await made.runner.run(call: Self.call(
            "schedule_deploy", arguments: ["course": "ICS3U", "section": 1, "when": "2030-09-09 06:30"]
        ))
        XCTAssertTrue(set.summary.hasPrefix("Scheduled:"), set.summary)

        if !expectAsking {
            // The app's own assistant, straight after: it asks, and anything the
            // outside assistant started has run before it by then.
            let local = try AssistFixture.makeRunner(hasDeployedBefore: true, surface: .local)
            roots.append(local.root)
            let again: AssistToolOutcome = await local.runner.run(call: Self.call(
                "schedule_deploy", arguments: ["course": "ICS3U", "section": 1, "when": "2030-09-10 06:30"]
            ))
            XCTAssertTrue(again.summary.hasPrefix("Scheduled:"), again.summary)
        }
        await fulfillment(of: [asked], timeout: 5)

        if !expectAsking {
            // Only the app's own assistant looked at all.
            XCTAssertEqual(fake.permissionChecks, 1, "The outside assistant asked about permission")
            // Undo the app assistant's own question so the row reads as the
            // outside assistant's alone.
            fake.forgetQuestions()
            ActivityTrail.store = ProblemReportStore(folderURL: trailFolder.appendingPathComponent(UUID().uuidString))
        }
    }

    /// The lines on the trail about a section, without their time and
    /// course prefix. Lines about nothing in particular — the fixture's own
    /// "opened the working folder" — are not this feature's.
    private func linesOnTheTrail() -> [String] {
        let text: String = ActivityTrail.store.activityText(includingPrompts: true)
        var lines: [String] = []
        for rawLine in text.split(separator: "\n") {
            let line: String = String(rawLine)
            for prefix in ["ICS3U/1 · ", "ICS4U/2 · ", "ICS4U/1 · "] {
                if let marker = line.range(of: prefix) {
                    lines.append(String(line[marker.upperBound...]))
                }
            }
        }
        return lines
    }

    private func writeRecord(kind: ScheduledPublishOutcome.Kind, course: String, section: Int) throws {
        ScheduledPublishOutcome.clear(inHomeFolder: home, course: course, section: section, folderID: Self.folderID)
        let written: Bool = ScheduledPublishOutcome.recordStopped(
            ScheduledPublishOutcome.Stopped(kind: kind, destination: Self.destination, when: Date()),
            inHomeFolder: home, course: course, section: section, folderID: Self.folderID
        )
        XCTAssertTrue(written)
    }

    private static func cases(_ group: String) throws -> [[String: Any]] {
        let section: [String: Any] = try SharedRulesContractTests.section("scheduledPublishStopped")
        let notification: [String: Any] = try XCTUnwrap(section["notification"] as? [String: Any])
        let rows: [String: Any] = try XCTUnwrap(notification[group] as? [String: Any], "No notification.\(group)")
        XCTAssertNotNil(rows["note"] as? String, "notification.\(group) does not say how to play it")
        return try XCTUnwrap(rows["cases"] as? [[String: Any]])
    }

    private static func kind(named key: String) throws -> ScheduledPublishOutcome.Kind {
        var found: ScheduledPublishOutcome.Kind? = nil
        for kind in ScheduledPublishOutcome.Kind.allCases where SharedRulesContractTests.contractKey(for: kind) == key {
            found = kind
        }
        return try XCTUnwrap(found, "The contract names a kind this app does not have: \(key)")
    }

    private static func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func call(_ name: String, arguments: [String: Any]) -> AssistToolCall {
        let encoded: Data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return AssistToolCall(
            id: UUID().uuidString,
            type: "function",
            function: AssistToolCall.Function(name: name, arguments: String(decoding: encoded, as: UTF8.self))
        )
    }
}

/// Holds one answer across a task boundary.
private nonisolated final class ResultBox: @unchecked Sendable {

    // MARK: - Stored properties

    var announcement: ScheduledPublishNotice.Announcement?
}

/// Stands in for macOS's notification centre: records what it was asked, and
/// keeps what is on show by identifier — a post replaces, a withdraw removes.
nonisolated final class RecordingNotifications: NotificationPosting, @unchecked Sendable {

    // MARK: - Stored properties

    private let lock: NSLock = NSLock()
    private var current: ScheduledPublishNotice.Permission
    private var shownByIdentifier: [String: String] = [:]
    private var asked: Int = 0
    private var checks: Int = 0
    private var attempts: Int = 0
    /// Continuations a never-answering post or check is parked on. Kept, never
    /// resumed, and deliberately not cancellable — that is the point.
    private var parked: [Any] = []

    var postFails: Bool = false
    var answer: Bool = true
    var neverAnswers: Bool = false
    var permissionNeverAnswers: Bool = false
    var onQuestionAnswered: (@Sendable () -> Void)?

    // MARK: - Computed properties

    var shown: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return shownByIdentifier
    }

    var questionsAsked: Int {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    var permissionChecks: Int {
        lock.lock()
        defer { lock.unlock() }
        return checks
    }

    var postsAttempted: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    // MARK: - Initializer

    init(permission: ScheduledPublishNotice.Permission) {
        current = permission
    }

    // MARK: - Functions

    func forgetQuestions() {
        lock.lock()
        asked = 0
        lock.unlock()
    }

    func permission() async -> ScheduledPublishNotice.Permission {
        let (parks, answerNow): (Bool, ScheduledPublishNotice.Permission) = lock.withLock {
            checks += 1
            return (permissionNeverAnswers, current)
        }
        if parks {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.park(continuation)
            }
        }
        return answerNow
    }

    func askPermission() async -> Bool {
        let (given, tell): (Bool, (@Sendable () -> Void)?) = lock.withLock {
            asked += 1
            current = answer ? .allowed : .notAllowed
            return (answer, onQuestionAnswered)
        }
        // Told after the answer is back with the caller, so the caller's
        // second trail line is written before a waiting test looks.
        Task { @MainActor in
            tell?()
        }
        return given
    }

    func post(identifier: String, body: String) async throws {
        let (parks, fails): (Bool, Bool) = lock.withLock {
            attempts += 1
            return (neverAnswers, postFails)
        }
        if parks {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.park(continuation)
            }
        }
        if fails {
            throw SystemNotifications.Refusal.insideTheTestSuite
        }
        lock.withLock {
            shownByIdentifier[identifier] = body
        }
    }

    func withdraw(identifier: String) {
        lock.lock()
        shownByIdentifier[identifier] = nil
        lock.unlock()
    }

    private func park(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        parked.append(continuation)
        lock.unlock()
    }
}
