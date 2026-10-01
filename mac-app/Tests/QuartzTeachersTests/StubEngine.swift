import Foundation

/// A stand-in for `llama-server`: it answers whatever the test tells it to.
///
/// A real socket rather than a stubbed `URLProtocol`, deliberately:
/// `URLSession.shared` is what `AssistModelClient` uses, and whether a
/// globally registered protocol class is consulted there is a documented
/// grey area. A socket is not a grey area — it either accepts the connection
/// or it does not.
///
/// It lives in a file of its own, beside `AssistFixture` and `FakePreview`,
/// because two things need it now: the warm-up tests, which care about WHEN
/// the answer comes back, and the cut-off tests, which care about WHAT it
/// says and what the app put on the wire to get it.
///
/// Port collisions are impossible by construction: it binds port 0 and reads
/// the kernel's answer back with `getsockname`, so a real engine on 8080 or
/// 8099 cannot clash with it.
nonisolated final class StubEngine: @unchecked Sendable {

    // MARK: - Stored properties

    /// The listening socket.
    private let listener: Int32

    /// The port the kernel gave us.
    let port: Int

    private let lock: NSLock = NSLock()

    /// How many whole requests have been read off the wire.
    private var requestsRead: Int = 0

    /// The body of each request, decoded. The whole point of a socket stub is
    /// that what the app SENT can be read back, rather than inferred.
    private var bodiesReceived: [[String: Any]] = []

    /// What to answer with, one entry per lap. Settable so a test can serve a
    /// reply the real engine would only produce under a cap — and so a test
    /// about a SECOND lap can say what comes back the second time. The last
    /// entry answers every request after it.
    private var replies: [String] = [StubEngine.readyReply]

    /// Whether the answer goes out as soon as the request arrives.
    ///
    /// Off by default, because the warm-up tests exist to assert what is true
    /// WHILE a request is in flight. A test that only cares about the answer
    /// turns it on and never has to call `answer()`.
    private var answersImmediately: Bool = false

    /// Held until the test says the engine may answer.
    private let permissionToAnswer: DispatchSemaphore = DispatchSemaphore(value: 0)

    /// The reply every warm-up test has always been served.
    static let readyReply: String =
        #"{"choices":[{"message":{"role":"assistant","content":"ready"}}],"usage":{"completion_tokens":2}}"#

    // MARK: - Computed properties

    var baseURL: URL {
        return URL(string: "http://127.0.0.1:\(port)")!
    }

    /// Every request body the app has sent, oldest first.
    var requestBodies: [[String: Any]] {
        return lock.withLock { return bodiesReceived }
    }

    /// How many requests arrived. A test that expects one asserts on this
    /// rather than discovering a second lap as a hung suite — see
    /// `serveRequests`.
    var requestCount: Int {
        return lock.withLock { return requestsRead }
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
        // A thread of its own rather than a queue: `accept` and `recv` block,
        // and something that sits blocked for the length of a test has no
        // business on a shared pool.
        Thread.detachNewThread { [self] in
            serveRequests()
        }
    }

    // MARK: - Functions

    /// What to answer with, and whether to answer without being asked twice.
    ///
    /// Set before the request arrives. A test that wants the hold — the whole
    /// subject of `AssistWarmUpTests` — leaves `immediately` false and calls
    /// `answer()`.
    func serve(_ json: String, immediately: Bool = true) {
        serve([json], immediately: immediately)
    }

    /// One reply per lap, in order. The last one answers everything after it,
    /// so a test that expects two laps and gets three fails on `requestCount`
    /// rather than hanging.
    func serve(_ json: [String], immediately: Bool = true) {
        lock.withLock {
            replies = json
            answersImmediately = immediately
        }
        if immediately {
            // Signalled up front so the answer cannot race a request that
            // arrives before this call lands: a semaphore already signalled is
            // a wait that returns at once.
            permissionToAnswer.signal()
        }
    }

    /// Waits until the engine has a whole request in hand.
    ///
    /// Polls rather than blocking, because the caller is on the main actor
    /// and the conversation it is waiting for runs there too — a blocking
    /// wait here would stop the very work it is waiting for.
    func waitForARequest(within seconds: Double = 10) async throws {
        let deadline: Date = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if requestCount > 0 {
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
        // `shutdown` FIRST, and it is not decoration: the serve loop is
        // usually parked in `accept`, and closing a socket from another
        // thread is not guaranteed to wake a pending `accept` on Darwin.
        // Without this, every engine in the suite leaves a thread and a
        // socket parked for the life of the test process.
        shutdown(listener, SHUT_RDWR)
        close(listener)
    }

    /// Read a request, wait for permission, write the canned reply — and then
    /// go round again.
    ///
    /// **A loop rather than one connection**, which is the difference between
    /// a test failing and a test hanging: a change that provokes a SECOND lap
    /// round the model would otherwise leave the client waiting on its own
    /// 180-second timeout, which reads as a stuck suite rather than as the
    /// regression it is. Serving the second request lets the test assert
    /// `requestCount` and fail in a second.
    private func serveRequests() {
        while true {
            let connection: Int32 = accept(listener, nil, nil)
            if connection < 0 {
                return
            }
            let asked: [String: Any] = readWholeRequest(from: connection)

            let lap: Int = lock.withLock {
                requestsRead += 1
                bodiesReceived.append(asked)
                return requestsRead - 1
            }

            _ = permissionToAnswer.wait(timeout: .now() + 20)
            let answering: Bool = lock.withLock { return answersImmediately }
            if answering {
                // Put it back for the next lap, so a loop is served without
                // the test having to guess how many requests to allow.
                permissionToAnswer.signal()
            }

            let body: String = lock.withLock {
                if replies.isEmpty {
                    return StubEngine.readyReply
                }
                return replies[min(lap, replies.count - 1)]
            }
            let bodyBytes: [UInt8] = Array(body.utf8)
            let head: String = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(bodyBytes.count)\r\n"
                + "Connection: close\r\n\r\n"
            writeAll(Array(head.utf8), to: connection)
            writeAll(bodyBytes, to: connection)
            close(connection)
        }
    }

    /// Drains the request head and its body, so the client is never left
    /// blocked on a write nobody is reading — and hands back what it read.
    private func readWholeRequest(from connection: Int32) -> [String: Any] {
        var received: [UInt8] = []
        var buffer: [UInt8] = [UInt8](repeating: 0, count: 16384)
        var headEndsAt: Int = -1
        var bodyLength: Int = -1

        while true {
            let count: Int = recv(connection, &buffer, buffer.count, 0)
            if count <= 0 {
                return StubEngine.decode(body: received, after: headEndsAt)
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
                    return StubEngine.decode(body: received, after: headEndsAt)
                }
            }
        }
    }

    /// The JSON the request carried, or an empty dictionary when it carried
    /// none.
    private static func decode(body bytes: [UInt8], after headEndsAt: Int) -> [String: Any] {
        if headEndsAt < 0 || headEndsAt > bytes.count {
            return [:]
        }
        let data: Data = Data(bytes[headEndsAt...])
        let parsed: Any? = try? JSONSerialization.jsonObject(with: data)
        return (parsed as? [String: Any]) ?? [:]
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

enum StubEngineProblem: Error {
    case couldNotListen
    case noRequestArrived
}
