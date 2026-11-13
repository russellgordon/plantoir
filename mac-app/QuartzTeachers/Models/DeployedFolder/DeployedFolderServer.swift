import Foundation
import Network
import Synchronization

/// Answers a web browser from a deployed folder on this computer (#850), so
/// the site's links and features work as they do from a web host: Quartz
/// writes every page link without `.html`, and opened straight from the
/// folder 0 of 3,369 page links worked (the measurement behind #850).
///
/// **The app does this itself**, rather than the website builder or a Python
/// on the host. It starts in milliseconds, needs nothing else running, reads
/// any folder the app can read on any drive, and stops when the app does.
/// The builder sees only its two mounts and takes 109 seconds to start cold
/// (#225); the Mac has no Python a teacher can rely on. Both rejected, with
/// the rest, in `documentation/09-mac-app.md` → "A deployed folder opened in
/// the browser (#850)".
///
/// **Bound to 127.0.0.1 and nothing else** (`requiredLocalEndpoint`), as
/// previews have been since #684: another computer cannot reach it. Another
/// account on this Mac can, as it can a preview; Russell accepted that on
/// 2026-11-13 and the documentation names it as a known limit.
///
/// **A permitted use of GCD in this app, and this comment is the
/// permission** (the others are `ScheduledPublishWatcher.changes(at:watching:)`
/// and `ProcessEnding`, for the same reason). `NWListener.start(queue:)` and
/// `NWConnection.start(queue:)` take a `DispatchQueue` as a required
/// parameter: it is where the framework delivers its callbacks, not
/// somewhere this code throws work. Every callback hops straight into this
/// actor with a `Task`, and nothing is deferred or delayed through Dispatch.
/// The async `NetworkListener` would avoid it, but it is macOS 26 and later
/// (`Network.swiftinterface`), and this app runs on 15. Rejected with it:
/// `URLProtocol`, which serves only the app's own web views and never the
/// teacher's browser, and SwiftNIO, a dependency for about 400 lines.
///
/// **Limits** (the plan review's M1, which held 300 of 300 half-sent
/// requests open against a server with none): `limits` below, pinned
/// against `deployedFolderInBrowser.limits` in the contract. When all the
/// places are taken, the connection that has been quiet longest is closed to
/// make room, and a piece of an answer left untaken for
/// `secondsToTakeAPiece` closes its connection, so readers that stop reading
/// cannot shut the teacher's own browser out (the implementation review's
/// M2).
actor DeployedFolderServer {

    // MARK: - Types

    /// What the server knows about one open connection.
    struct ConnectionState {
        var connection: NWConnection
        var buffer: Data = Data()
        /// Bumped whenever a deadline is set or cleared; a deadline that
        /// fires with an older token is ignored.
        var deadlineToken: Int = 0
        /// An answer is being sent; the header deadline does not apply
        /// while it is, the send deadline does.
        var isAnswering: Bool = false
        /// When the piece being sent must have been taken by, or nil while
        /// nothing is waiting to be taken.
        var sendDeadline: ContinuousClock.Instant? = nil
        /// Whether this connection's one send watcher is running (the fix
        /// review's L-c: one per connection, not one per piece).
        var hasSendWatcher: Bool = false
        /// When the connection last did anything: bytes arrived, or a piece
        /// was taken. The least recent makes room when the server is full.
        var lastActivity: ContinuousClock.Instant = ContinuousClock.now
        /// The order connections arrived in, to break a tie.
        var arrival: Int = 0
    }

    /// Why starting found no address.
    enum StartProblem: Error {
        case noFreeAddress
    }

    // MARK: - Stored properties

    /// The connection limits, in one place so the test can hold them
    /// against the contract.
    nonisolated static let maximumConnections: Int = 64
    nonisolated static let maximumRequestLineBytes: Int = 8 * 1024
    nonisolated static let maximumHeaderBytes: Int = 16 * 1024
    nonisolated static let secondsToSendTheHeaders: Int = 10
    nonisolated static let secondsIdleBetweenRequests: Int = 30
    /// How long a reader may leave a piece of an answer untaken before the
    /// connection closes (the implementation review's M2: 64 readers that
    /// never read held every place, and a normal request was refused at
    /// 2 s and at 47 s).
    nonisolated static let secondsToTakeAPiece: Int = 30
    nonisolated static let bytesPerPiece: Int = 256 * 1024

    /// The one queue the framework delivers on (see the header).
    nonisolated static let deliveryQueue: DispatchQueue = DispatchQueue(label: "ca.russellgordon.Plantoir.deployed-folder")

    nonisolated let root: URL
    nonisolated let port: Int
    nonisolated let listener: NWListener

    /// Called once, the first time a request finds the folder gone.
    private let onFolderGone: @Sendable () -> Void

    private var connections: [Int: ConnectionState] = [:]
    private var nextConnectionID: Int = 0
    private var isStopped: Bool = false
    private var folderGoneReported: Bool = false

    /// Counts for the trail line when it stops: never an address. Atomic,
    /// so a quit can read them at once without waiting on this actor.
    nonisolated let requestTally: Atomic<Int> = Atomic<Int>(0)
    nonisolated let notFoundTally: Atomic<Int> = Atomic<Int>(0)

    // MARK: - Initializer

    init(root: URL, port: Int, listener: NWListener, onFolderGone: @escaping @Sendable () -> Void) {
        self.root = root
        self.port = port
        self.listener = listener
        self.onFolderGone = onFolderGone
    }

    // MARK: - Functions: starting and stopping

    /// Starts on the first of `candidates` nothing else holds, or throws.
    /// `firstWasTaken` says whether the usual address was held, for the
    /// trail.
    static func start(
        root: URL, candidates: [Int], onFolderGone: @escaping @Sendable () -> Void,
        onEnded: @escaping @Sendable () -> Void = {}
    ) async throws -> (server: DeployedFolderServer, firstWasTaken: Bool) {
        var tried: Int = 0
        for candidate in candidates {
            guard let port = NWEndpoint.Port(rawValue: UInt16(candidate)) else {
                continue
            }
            let parameters: NWParameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: port)
            parameters.allowLocalEndpointReuse = false
            guard let listener = try? NWListener(using: parameters) else {
                tried += 1
                continue
            }
            let server: DeployedFolderServer = DeployedFolderServer(
                root: root, port: candidate, listener: listener, onFolderGone: onFolderGone
            )
            listener.newConnectionHandler = { [weak server] connection in
                guard let server else {
                    connection.cancel()
                    return
                }
                Task {
                    await server.accept(connection)
                }
            }
            let started: Bool = await DeployedFolderServer.waitUntilListening(listener)
            if started {
                // Still listening for its state once it is ready, so a
                // listener that fails later is noticed (the implementation
                // review's L4).
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .failed, .cancelled:
                        onEnded()
                    default:
                        break
                    }
                }
                return (server: server, firstWasTaken: tried > 0)
            }
            listener.cancel()
            tried += 1
        }
        throw StartProblem.noFreeAddress
    }

    /// Starts a listener and answers whether it is listening (false when the
    /// address is held, or it failed some other way).
    static func waitUntilListening(_ listener: NWListener) async -> Bool {
        let answered: OneAnswer = OneAnswer()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    answered.give(true, to: continuation)
                case .failed, .cancelled:
                    answered.give(false, to: continuation)
                case .waiting:
                    // Waiting means the address could not be had now.
                    answered.give(false, to: continuation)
                default:
                    break
                }
            }
            listener.start(queue: DeployedFolderServer.deliveryQueue)
        }
    }

    /// Stops listening and closes every connection.
    func stop() {
        if isStopped {
            return
        }
        isStopped = true
        listener.cancel()
        for (_, state) in connections {
            state.connection.cancel()
        }
        connections.removeAll()
    }

    /// The counts so far, for the trail.
    func counts() -> (requests: Int, notFound: Int) {
        return countsNow()
    }

    /// The same, read from anywhere.
    nonisolated func countsNow() -> (requests: Int, notFound: Int) {
        return (requests: requestTally.load(ordering: .relaxed), notFound: notFoundTally.load(ordering: .relaxed))
    }

    // MARK: - Functions: connections

    func accept(_ connection: NWConnection) {
        if isStopped {
            connection.cancel()
            return
        }
        // Full: the connection that has done nothing for longest makes room,
        // so a new one (the teacher's own browser) always gets in. A paused
        // video or a reader that stopped reading is the one that goes, not
        // the newcomer (the implementation review's M2).
        if connections.count >= DeployedFolderServer.maximumConnections {
            closeTheLeastRecentlyActive()
        }
        let identifier: Int = nextConnectionID
        nextConnectionID += 1
        var fresh: ConnectionState = ConnectionState(connection: connection)
        fresh.arrival = identifier
        connections[identifier] = fresh
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task {
                    await self?.forget(identifier)
                }
            default:
                break
            }
        }
        connection.start(queue: DeployedFolderServer.deliveryQueue)
        armDeadline(identifier, seconds: DeployedFolderServer.secondsToSendTheHeaders)
        receiveMore(identifier)
    }

    /// Closes the connection that has been quiet longest.
    func closeTheLeastRecentlyActive() {
        var chosen: Int? = nil
        var chosenState: ConnectionState? = nil
        for (identifier, state) in connections {
            if let current = chosenState {
                if state.lastActivity < current.lastActivity
                    || (state.lastActivity == current.lastActivity && state.arrival < current.arrival) {
                    chosen = identifier
                    chosenState = state
                }
            } else {
                chosen = identifier
                chosenState = state
            }
        }
        if let chosen {
            reset(chosen)
        }
    }

    /// A send deadline: the connection is reset if this piece has not been
    /// taken by then. A real timeout. One watcher per connection follows
    /// the deadline as it moves, rather than a sleeping task per piece,
    /// which a fast read of a large video would make thousands of.
    func armSendDeadline(_ identifier: Int) {
        guard var state = connections[identifier] else {
            return
        }
        state.sendDeadline = ContinuousClock.now + .seconds(DeployedFolderServer.secondsToTakeAPiece)
        let startWatcher: Bool = !state.hasSendWatcher
        state.hasSendWatcher = true
        connections[identifier] = state
        if startWatcher {
            Task { [weak self] in
                await self?.watchTheSendDeadline(identifier)
            }
        }
    }

    /// Sleeps until the connection's send deadline, then resets it if the
    /// piece is still untaken; follows a deadline that moved; ends when
    /// nothing is waiting to be taken.
    func watchTheSendDeadline(_ identifier: Int) async {
        while true {
            guard let state = connections[identifier] else {
                return
            }
            guard let deadline = state.sendDeadline else {
                var resting: ConnectionState = state
                resting.hasSendWatcher = false
                connections[identifier] = resting
                return
            }
            if ContinuousClock.now >= deadline {
                if state.isAnswering {
                    reset(identifier)
                    return
                }
                var resting: ConnectionState = state
                resting.sendDeadline = nil
                resting.hasSendWatcher = false
                connections[identifier] = resting
                return
            }
            try? await Task.sleep(until: deadline, clock: .continuous)
        }
    }

    /// A piece was taken: the send deadline is cleared until the next one.
    func pieceTaken(_ identifier: Int) {
        guard var state = connections[identifier] else {
            return
        }
        state.sendDeadline = nil
        state.lastActivity = ContinuousClock.now
        connections[identifier] = state
    }

    func forget(_ identifier: Int) {
        connections.removeValue(forKey: identifier)
    }

    func close(_ identifier: Int) {
        if let state = connections[identifier] {
            state.connection.cancel()
        }
        connections.removeValue(forKey: identifier)
    }

    /// Closes a connection whose peer is misbehaving, with a reset rather
    /// than a graceful close (the fix review's M-c): a graceful close waits
    /// behind bytes a stalled reader will never take, so the reader would
    /// see nothing and the kernel would hold the socket. Used for making
    /// room and for the send deadline.
    func reset(_ identifier: Int) {
        if let state = connections[identifier] {
            state.connection.forceCancel()
        }
        connections.removeValue(forKey: identifier)
    }

    func receiveMore(_ identifier: Int) {
        guard let state = connections[identifier] else {
            return
        }
        state.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task {
                await self?.received(identifier, data: data, isComplete: isComplete, failed: error != nil)
            }
        }
    }

    func received(_ identifier: Int, data: Data?, isComplete: Bool, failed: Bool) {
        guard var state = connections[identifier] else {
            return
        }
        if failed {
            close(identifier)
            return
        }
        let wasEmpty: Bool = state.buffer.isEmpty
        if let data {
            state.buffer.append(data)
            state.lastActivity = ContinuousClock.now
        }
        connections[identifier] = state
        if wasEmpty && !state.buffer.isEmpty {
            // A new request has begun: it has this long to finish its headers.
            armDeadline(identifier, seconds: DeployedFolderServer.secondsToSendTheHeaders)
        }
        if isComplete && (data == nil || data?.isEmpty == true) {
            close(identifier)
            return
        }
        readARequest(identifier)
    }

    /// A deadline: the connection closes if it is still waiting for headers
    /// when it passes. A real timeout, not a wait for something to settle.
    func armDeadline(_ identifier: Int, seconds: Int) {
        guard var state = connections[identifier] else {
            return
        }
        state.deadlineToken += 1
        let token: Int = state.deadlineToken
        connections[identifier] = state
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            await self?.deadlinePassed(identifier, token: token)
        }
    }

    func deadlinePassed(_ identifier: Int, token: Int) {
        guard let state = connections[identifier] else {
            return
        }
        if state.deadlineToken == token && !state.isAnswering {
            close(identifier)
        }
    }

    // MARK: - Functions: requests

    /// Reads one request from the buffer, if a whole one has arrived.
    func readARequest(_ identifier: Int) {
        guard var state = connections[identifier] else {
            return
        }
        let ending: Data = Data("\r\n\r\n".utf8)
        guard let end = state.buffer.range(of: ending) else {
            let lineEnd: Range<Data.Index>? = state.buffer.range(of: Data("\r\n".utf8))
            if lineEnd == nil && state.buffer.count > DeployedFolderServer.maximumRequestLineBytes {
                answerAndClose(identifier, status: 414)
                return
            }
            if state.buffer.count > DeployedFolderServer.maximumRequestLineBytes + DeployedFolderServer.maximumHeaderBytes {
                answerAndClose(identifier, status: 431)
                return
            }
            receiveMore(identifier)
            return
        }
        let head: Data = state.buffer.subdata(in: state.buffer.startIndex..<end.lowerBound)
        state.buffer.removeSubrange(state.buffer.startIndex..<end.upperBound)
        state.deadlineToken += 1
        state.isAnswering = true
        connections[identifier] = state

        let text: String = String(decoding: head, as: UTF8.self)
        let lines: [String] = text.components(separatedBy: "\r\n")
        let requestLine: String = lines.first ?? ""
        if requestLine.utf8.count > DeployedFolderServer.maximumRequestLineBytes {
            answerAndClose(identifier, status: 414)
            return
        }
        if head.count - requestLine.utf8.count > DeployedFolderServer.maximumHeaderBytes {
            answerAndClose(identifier, status: 431)
            return
        }
        guard let request = DeployedFolderServer.parse(lines: lines) else {
            answerAndClose(identifier, status: 400)
            return
        }

        requestTally.add(1, ordering: .relaxed)
        if !DeployedFolderResolver.isFolder(root) && !folderGoneReported {
            folderGoneReported = true
            onFolderGone()
        }
        var answer: DeployedFolderResolver.Answer = DeployedFolderResolver.answer(
            to: request.request, root: root, port: port
        )
        if answer.status == 404 {
            notFoundTally.add(1, ordering: .relaxed)
        }
        if !request.keepsAlive {
            answer.closesTheConnection = true
        }
        send(answer, on: identifier)
    }

    /// A parsed request and whether the connection stays open after it.
    struct Parsed {
        var request: DeployedFolderResolver.Request
        var keepsAlive: Bool
    }

    /// The request line and headers, or nil for something that is not an
    /// HTTP/1 request.
    static func parse(lines: [String]) -> Parsed? {
        guard let first = lines.first else {
            return nil
        }
        let words: [String] = first.components(separatedBy: " ")
        if words.count != 3 {
            return nil
        }
        let version: String = words[2]
        if version != "HTTP/1.1" && version != "HTTP/1.0" {
            return nil
        }
        var headers: [(name: String, value: String)] = []
        var index: Int = 1
        while index < lines.count {
            let line: String = lines[index]
            guard let colon = line.firstIndex(of: ":") else {
                return nil
            }
            let name: String = String(line[line.startIndex..<colon]).lowercased()
            if name.isEmpty || name.contains(" ") {
                return nil
            }
            let value: String = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers.append((name: name, value: value))
            index += 1
        }
        let request: DeployedFolderResolver.Request = DeployedFolderResolver.Request(
            method: words[0], target: words[1], headers: headers
        )
        let connectionHeader: String = (request.value(of: "connection") ?? "").lowercased()
        var keepsAlive: Bool = version == "HTTP/1.1"
        if connectionHeader.contains("close") {
            keepsAlive = false
        }
        return Parsed(request: request, keepsAlive: keepsAlive)
    }

    // MARK: - Functions: answers

    func answerAndClose(_ identifier: Int, status: Int) {
        var answer: DeployedFolderResolver.Answer = DeployedFolderResolver.refusal(status, closing: true)
        answer.closesTheConnection = true
        send(answer, on: identifier)
    }

    /// The status line and headers as bytes.
    static func headBytes(of answer: DeployedFolderResolver.Answer) -> Data {
        var text: String = "HTTP/1.1 \(answer.status) \(DeployedFolderResolver.reason(for: answer.status))\r\n"
        for header in answer.headers {
            text += "\(header.name): \(header.value)\r\n"
        }
        if answer.closesTheConnection {
            text += "Connection: close\r\n"
        }
        text += "\r\n"
        return Data(text.utf8)
    }

    func send(_ answer: DeployedFolderResolver.Answer, on identifier: Int) {
        guard let state = connections[identifier] else {
            return
        }
        var head: Data = DeployedFolderServer.headBytes(of: answer)
        switch answer.body {
        case .none:
            break
        case .data(let data):
            head.append(data)
        case .file:
            break
        }
        let closes: Bool = answer.closesTheConnection
        let body: DeployedFolderResolver.Body = answer.body
        armSendDeadline(identifier)
        state.connection.send(content: head, completion: .contentProcessed { [weak self] error in
            Task {
                await self?.pieceTaken(identifier)
                await self?.sentTheHead(identifier, body: body, closes: closes, failed: error != nil)
            }
        })
    }

    func sentTheHead(_ identifier: Int, body: DeployedFolderResolver.Body, closes: Bool, failed: Bool) {
        if failed {
            close(identifier)
            return
        }
        if case .file(let url, let offset, let length) = body, length > 0 {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                close(identifier)
                return
            }
            sendPiece(identifier, handle: handle, position: offset, remaining: length, closes: closes)
            return
        }
        finished(identifier, closes: closes)
    }

    /// Sends the file a piece at a time, so a long video never sits in
    /// memory whole.
    func sendPiece(_ identifier: Int, handle: FileHandle, position: UInt64, remaining: UInt64, closes: Bool) {
        guard let state = connections[identifier] else {
            try? handle.close()
            return
        }
        let wanted: Int = Int(min(UInt64(DeployedFolderServer.bytesPerPiece), remaining))
        var piece: Data = Data()
        do {
            try handle.seek(toOffset: position)
            piece = try handle.read(upToCount: wanted) ?? Data()
        } catch {
            try? handle.close()
            close(identifier)
            return
        }
        if piece.isEmpty {
            // The file shrank while it was being sent: the length promised
            // cannot be kept, so the connection closes.
            try? handle.close()
            close(identifier)
            return
        }
        let sent: UInt64 = UInt64(piece.count)
        armSendDeadline(identifier)
        state.connection.send(content: piece, completion: .contentProcessed { [weak self] error in
            Task {
                await self?.pieceTaken(identifier)
                await self?.sentAPiece(
                    identifier, handle: handle, position: position + sent,
                    remaining: remaining - sent, closes: closes, failed: error != nil
                )
            }
        })
    }

    func sentAPiece(
        _ identifier: Int, handle: FileHandle, position: UInt64, remaining: UInt64, closes: Bool, failed: Bool
    ) {
        if failed {
            try? handle.close()
            close(identifier)
            return
        }
        if remaining > 0 {
            sendPiece(identifier, handle: handle, position: position, remaining: remaining, closes: closes)
            return
        }
        try? handle.close()
        finished(identifier, closes: closes)
    }

    /// One answer is done: close, or wait for the next request.
    func finished(_ identifier: Int, closes: Bool) {
        if closes {
            close(identifier)
            return
        }
        guard var state = connections[identifier] else {
            return
        }
        state.isAnswering = false
        connections[identifier] = state
        if state.buffer.isEmpty {
            armDeadline(identifier, seconds: DeployedFolderServer.secondsIdleBetweenRequests)
            receiveMore(identifier)
        } else {
            armDeadline(identifier, seconds: DeployedFolderServer.secondsToSendTheHeaders)
            readARequest(identifier)
        }
    }
}

/// Resumes a continuation once, however many times the listener's state
/// changes. Its state is touched only on the delivery queue.
nonisolated final class OneAnswer: @unchecked Sendable {

    // MARK: - Stored properties

    private var given: Bool = false

    // MARK: - Functions

    func give(_ value: Bool, to continuation: CheckedContinuation<Bool, Never>) {
        if given {
            return
        }
        given = true
        continuation.resume(returning: value)
    }
}
