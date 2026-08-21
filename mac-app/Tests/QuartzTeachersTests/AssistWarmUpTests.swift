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

/// A stand-in for `llama-server` that answers one request, when told to.
///
/// A real socket rather than a stubbed `URLProtocol`, deliberately:
/// `URLSession.shared` is what `AssistModelClient` uses, and whether a
/// globally registered protocol class is consulted there is a documented
/// grey area. A socket is not a grey area — it either accepts the connection
/// or it does not.
private nonisolated final class StubEngine: @unchecked Sendable {

    // MARK: - Stored properties

    /// The listening socket.
    private let listener: Int32

    /// The port the kernel gave us.
    let port: Int

    /// Raised once a whole request has been read off the wire.
    private let lock: NSLock = NSLock()
    private var hasReceivedARequest: Bool = false

    /// Held until the test says the engine may answer.
    private let permissionToAnswer: DispatchSemaphore = DispatchSemaphore(value: 0)

    // MARK: - Computed properties

    var baseURL: URL {
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    // MARK: - Initializer

    init() throws {
        let handle: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        if handle < 0 {
            throw StubEngineProblem.couldNotListen
        }
        var reuse: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address: sockaddr_in = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound: Int32 = withUnsafePointer(to: &address) { pointer in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                return bind(handle, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 || listen(handle, 4) != 0 {
            close(handle)
            throw StubEngineProblem.couldNotListen
        }

        var assigned: sockaddr_in = sockaddr_in()
        var length: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named: Int32 = withUnsafeMutablePointer(to: &assigned) { pointer in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                return getsockname(handle, rebound, &length)
            }
        }
        if named != 0 {
            close(handle)
            throw StubEngineProblem.couldNotListen
        }

        self.listener = handle
        self.port = Int(UInt16(bigEndian: assigned.sin_port))
        DispatchQueue.global().async { [self] in
            serveOneRequest()
        }
    }

    // MARK: - Functions

    /// Waits until the engine has a whole request in hand.
    ///
    /// Polls rather than blocking, because the caller is on the main actor
    /// and the conversation it is waiting for runs there too — a blocking
    /// wait here would stop the very work it is waiting for.
    func waitForARequest(within seconds: Double = 10) async throws {
        let deadline: Date = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let arrived: Bool = lock.withLock { return hasReceivedARequest }
            if arrived {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw StubEngineProblem.noRequestArrived
    }

    /// Lets the held request go.
    func answer() {
        permissionToAnswer.signal()
    }

    func stop() {
        permissionToAnswer.signal()
        close(listener)
    }

    /// Read one request, wait for permission, write one canned reply.
    private func serveOneRequest() {
        let connection: Int32 = accept(listener, nil, nil)
        if connection < 0 {
            return
        }
        readWholeRequest(from: connection)

        lock.withLock { hasReceivedARequest = true }

        _ = permissionToAnswer.wait(timeout: .now() + 20)

        let body: String = #"{"choices":[{"message":{"role":"assistant","content":"ready"}}],"usage":{"completion_tokens":2}}"#
        let bodyBytes: [UInt8] = Array(body.utf8)
        let head: String = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(bodyBytes.count)\r\n"
            + "Connection: close\r\n\r\n"
        writeAll(Array(head.utf8), to: connection)
        writeAll(bodyBytes, to: connection)
        close(connection)
    }

    /// Drains the request head and its body, so the client is never left
    /// blocked on a write nobody is reading.
    private func readWholeRequest(from connection: Int32) {
        var received: [UInt8] = []
        var buffer: [UInt8] = [UInt8](repeating: 0, count: 16384)
        var headEndsAt: Int = -1
        var bodyLength: Int = -1

        while true {
            let count: Int = recv(connection, &buffer, buffer.count, 0)
            if count <= 0 {
                return
            }
            received.append(contentsOf: buffer[0..<count])

            if headEndsAt < 0 {
                if let end = StubEngine.endOfHead(in: received) {
                    headEndsAt = end
                    bodyLength = StubEngine.bodyLength(inHead: Array(received[0..<end]))
                }
            }
            if headEndsAt >= 0 {
                if bodyLength < 0 || received.count >= headEndsAt + bodyLength {
                    return
                }
            }
        }
    }

    /// Where the blank line after the headers ends, if it has arrived.
    private static func endOfHead(in bytes: [UInt8]) -> Int? {
        let marker: [UInt8] = Array("\r\n\r\n".utf8)
        if bytes.count < marker.count {
            return nil
        }
        var start: Int = 0
        while start <= bytes.count - marker.count {
            var matches: Bool = true
            var offset: Int = 0
            while offset < marker.count {
                if bytes[start + offset] != marker[offset] {
                    matches = false
                    break
                }
                offset += 1
            }
            if matches {
                return start + marker.count
            }
            start += 1
        }
        return nil
    }

    /// The `Content-Length` the head declares, or -1 when it declares none.
    private static func bodyLength(inHead bytes: [UInt8]) -> Int {
        let head: String = String(decoding: bytes, as: UTF8.self)
        for line in head.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value: String = String(line.dropFirst("content-length:".count))
                    .trimmingCharacters(in: .whitespaces)
                return Int(value) ?? -1
            }
        }
        return -1
    }

    private func writeAll(_ bytes: [UInt8], to connection: Int32) {
        var sent: Int = 0
        while sent < bytes.count {
            let written: Int = bytes.withUnsafeBufferPointer { pointer in
                return send(connection, pointer.baseAddress! + sent, bytes.count - sent, 0)
            }
            if written <= 0 {
                return
            }
            sent += written
        }
    }
}

private enum StubEngineProblem: Error {
    case couldNotListen
    case noRequestArrived
}
