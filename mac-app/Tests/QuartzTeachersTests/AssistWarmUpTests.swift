import XCTest
@testable import QuartzTeachers

/// Pins the one rule the warm-up has: **a turn cannot start before the
/// priming request has come back.**
///
/// The engine serves one request at a time (`--parallel 1`), and the window
/// announces itself ready as soon as `/health` answers — seconds before the
/// ~3,400-token warm-up has finished reading the tool definitions. A first
/// question sent into that gap queues behind the warm-up on the single slot
/// and arrives no sooner for having been asked sooner. Measured on an
/// M-series Mac, 48 GB, the small assistant, the same question twice: **1.7 s**
/// asked after the warm-up had returned, **3.1 s** asked the instant the field
/// enabled.
///
/// The measurement is the reason to do it; this file is the reason it stays
/// done. It drives `beginConversation(baseURL:)` against a stub engine that
/// holds its answer until the test lets go, so the gap is a whole second wide
/// and every assertion inside it is deterministic.
@MainActor
final class AssistWarmUpTests: XCTestCase {

    // MARK: - Types

    /// Something a background task can tick that the test can then read.
    /// A captured local `var` cannot be both.
    private final class Flag {
        var isSet: Bool = false
    }

    // MARK: - A turn cannot start before the warm-up returns

    func testATurnCannotStartBeforeTheWarmUpHasComeBack() async throws {
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let session: AssistSession = AssistSession(
            courseCode: "ICS3U", sectionNumber: 1, workingFolder: made.root
        )
        XCTAssertFalse(session.canSend, "A session that has not started an engine cannot send anything.")

        let conversation: Task<Void, Never> = Task {
            await session.beginConversation(baseURL: engine.baseURL)
        }
        try await engine.waitForARequest()

        // The warm-up is IN FLIGHT at this point: its request has reached the
        // engine and the engine is sitting on it.
        XCTAssertEqual(session.readiness, .ready)
        XCTAssertTrue(session.canAcceptTyping, "The box must accept the keyboard while the warm-up runs, or the teacher cannot start writing.")
        XCTAssertTrue(session.isWarmingUp)
        XCTAssertFalse(session.hasFinishedWarmUp)
        XCTAssertFalse(
            session.canSend,
            "A turn started here would queue behind the warm-up on the engine's single slot — which is the whole thing this gate exists to stop."
        )

        engine.answer()
        await conversation.value

        XCTAssertTrue(session.hasFinishedWarmUp)
        XCTAssertFalse(session.isWarmingUp)
        XCTAssertTrue(session.canSend, "Once the priming request is back, the first turn goes.")
        session.finish()
    }

    // MARK: - A held send is released, not swallowed

    /// What the composer does with a Return pressed during those seconds:
    /// it parks on `waitUntilWarmedUp()` rather than ignoring the keystroke.
    /// So the wait must last exactly as long as the warm-up does.
    func testWaitingForTheWarmUpEndsWhenTheWarmUpDoes() async throws {
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let session: AssistSession = AssistSession(
            courseCode: "ICS3U", sectionNumber: 1, workingFolder: made.root
        )
        let conversation: Task<Void, Never> = Task {
            await session.beginConversation(baseURL: engine.baseURL)
        }
        try await engine.waitForARequest()

        let hasStoppedWaiting: Flag = Flag()
        let waiting: Task<Void, Never> = Task {
            await session.waitUntilWarmedUp()
            hasStoppedWaiting.isSet = true
        }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(hasStoppedWaiting.isSet, "The wait ended while the priming request was still out.")

        engine.answer()
        await conversation.value
        await waiting.value
        XCTAssertTrue(hasStoppedWaiting.isSet)
        session.finish()
    }

    /// A window closed mid-warm-up must let go of anybody waiting on it.
    /// Otherwise a Return pressed a moment before the close waits forever.
    func testClosingTheWindowReleasesAnythingWaitingOnTheWarmUp() async throws {
        let engine: StubEngine = try StubEngine()
        defer { engine.stop() }
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let session: AssistSession = AssistSession(
            courseCode: "ICS3U", sectionNumber: 1, workingFolder: made.root
        )
        let conversation: Task<Void, Never> = Task {
            await session.beginConversation(baseURL: engine.baseURL)
        }
        try await engine.waitForARequest()

        let hasStoppedWaiting: Flag = Flag()
        let waiting: Task<Void, Never> = Task {
            await session.waitUntilWarmedUp()
            hasStoppedWaiting.isSet = true
        }
        session.finish()
        await waiting.value

        XCTAssertTrue(hasStoppedWaiting.isSet)
        XCTAssertFalse(session.canSend, "A closed window sends nothing, released wait or not.")
        engine.answer()
        await conversation.value
    }

    // MARK: - A warm-up that fails still opens the gate

    /// The warm-up's FAILURE is fire-and-forget, exactly as it was before the
    /// gate existed: the first real message pays the cost itself. What must
    /// not happen is the gate staying shut, which would leave a working
    /// assistant permanently unable to send.
    func testAWarmUpThatFailsStillLetsTheFirstTurnGo() async throws {
        let made: AssistFixture.Made = try AssistFixture.makeRunner()
        defer { try? FileManager.default.removeItem(at: made.root) }

        let session: AssistSession = AssistSession(
            courseCode: "ICS3U", sectionNumber: 1, workingFolder: made.root
        )
        // Nothing is listening on port 1, so the priming request comes back
        // an error almost at once.
        await session.beginConversation(baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")))

        XCTAssertTrue(session.hasFinishedWarmUp)
        XCTAssertTrue(session.canSend)
        session.finish()
    }
}
