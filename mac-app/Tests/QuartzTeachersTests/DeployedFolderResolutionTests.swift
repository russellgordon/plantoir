import Darwin
import XCTest
@testable import QuartzTeachers

/// A deployed folder answered to a browser (#850): every case in
/// `contracts/shared-rules.json` → `deployedFolderInBrowser.resolution.cases`,
/// run twice, through `DeployedFolderResolver` directly and through the REAL
/// listener over a socket; the limits and `connectionCases` through the
/// listener alone; and the content-type table held against the contract
/// both ways.
@MainActor
final class DeployedFolderResolutionTests: XCTestCase {

    // MARK: - Stored properties

    static let outsideSecret: String = "SECRET-FROM-OUTSIDE-THE-FOLDER"

    // MARK: - Functions: the contract

    static func section() throws -> [String: Any] {
        return try SharedRulesContractTests.section("deployedFolderInBrowser")
    }

    static func cases() throws -> [[String: Any]] {
        let section: [String: Any] = try DeployedFolderResolutionTests.section()
        let resolution: [String: Any] = try XCTUnwrap(section["resolution"] as? [String: Any])
        return try XCTUnwrap(resolution["cases"] as? [[String: Any]])
    }

    // MARK: - Functions: fixtures

    /// A folder made from a case's `files`, and the folder outside it.
    static func makeFixture(files: [String: Any]) throws -> (root: URL, outside: URL, top: URL) {
        let fileManager: FileManager = FileManager.default
        let top: URL = fileManager.temporaryDirectory
            .appendingPathComponent("deployed-folder-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let root: URL = top.appendingPathComponent("site")
        let outside: URL = top.appendingPathComponent("outside")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(outsideSecret.utf8).write(to: outside.appendingPathComponent("secret.html"))
        for (path, value) in files {
            let url: URL = root.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let text = value as? String {
                try content(for: text).write(to: url)
            } else if let link = value as? [String: Any], let target = link["symlinkTo"] as? String {
                let resolved: String = target.replacingOccurrences(of: "@OUTSIDE@", with: outside.path)
                try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: resolved)
            } else {
                XCTFail("a file the test cannot make: \(path)")
            }
        }
        return (root: root, outside: outside, top: top)
    }

    /// A file's bytes: the text, or that many bytes for `@BYTES200@`.
    static func content(for text: String) -> Data {
        if text.hasPrefix("@BYTES") && text.hasSuffix("@") {
            let count: Int = Int(text.dropFirst("@BYTES".count).dropLast()) ?? 0
            var bytes: [UInt8] = []
            var index: Int = 0
            while index < count {
                bytes.append(UInt8(index % 251))
                index += 1
            }
            return Data(bytes)
        }
        return Data(text.utf8)
    }

    /// A case's request: its method, target and headers with the port filled.
    static func request(from testCase: [String: Any], port: Int) throws -> DeployedFolderResolver.Request {
        let request: [String: Any] = try XCTUnwrap(testCase["request"] as? [String: Any])
        let method: String = try XCTUnwrap(request["method"] as? String)
        let target: String = try XCTUnwrap(request["target"] as? String)
        var headers: [(name: String, value: String)] = []
        if let given = request["headers"] as? [String: String] {
            for name in given.keys.sorted() {
                headers.append((name: name.lowercased(), value: filled(given[name] ?? "", port: port)))
            }
        } else {
            headers.append((name: "host", value: "127.0.0.1:\(port)"))
        }
        return DeployedFolderResolver.Request(method: method, target: filled(target, port: port), headers: headers)
    }

    static func filled(_ text: String, port: Int) -> String {
        return text
            .replacingOccurrences(of: "@OTHERPORT@", with: String(port + 1))
            .replacingOccurrences(of: "@PORT@", with: String(port))
    }

    // MARK: - Functions: checking one answer

    /// What every answer carries and never carries.
    func checkEveryAnswer(status: Int, headers: [(name: String, value: String)], name: String) throws {
        let section: [String: Any] = try DeployedFolderResolutionTests.section()
        let every: [String: Any] = try XCTUnwrap(section["everyAnswer"] as? [String: Any])
        let wanted: [String: String] = try XCTUnwrap(every["headers"] as? [String: String])
        for (header, value) in wanted {
            XCTAssertEqual(DeployedFolderResolutionTests.value(of: header, in: headers), value, "\(name): \(header)")
        }
        let never: String = try XCTUnwrap(every["never"] as? String)
        for header in headers {
            XCTAssertFalse(header.name.lowercased().hasPrefix(never.lowercased()), "\(name): \(header.name)")
        }
    }

    static func value(of name: String, in headers: [(name: String, value: String)]) -> String? {
        for header in headers where header.name.lowercased() == name.lowercased() {
            return header.value
        }
        return nil
    }

    /// One case's expectations against a status, headers and body.
    func check(
        _ testCase: [String: Any], status: Int, headers: [(name: String, value: String)], body: Data?,
        servedFile: String?, root: URL, how: String
    ) throws {
        let name: String = try XCTUnwrap(testCase["name"] as? String) + " (\(how))"
        let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
        try checkEveryAnswer(status: status, headers: headers, name: name)
        if expect["refused"] as? Bool == true {
            XCTAssertTrue(status == 400 || status == 404, "\(name): refused, but answered \(status)")
            if let body {
                let text: String = String(decoding: body, as: UTF8.self)
                XCTAssertFalse(text.contains(DeployedFolderResolutionTests.outsideSecret), "\(name): served a file from outside the folder")
            }
        }
        if let wanted = expect["status"] as? Int {
            XCTAssertEqual(status, wanted, name)
        }
        if let wantedType = expect["contentType"] as? String {
            XCTAssertEqual(DeployedFolderResolutionTests.value(of: "Content-Type", in: headers), wantedType, name)
        }
        if let location = expect["location"] as? String {
            XCTAssertEqual(DeployedFolderResolutionTests.value(of: "Location", in: headers), location, name)
        }
        if expect["noLocation"] as? Bool == true {
            XCTAssertNil(DeployedFolderResolutionTests.value(of: "Location", in: headers), name)
        }
        if let wantedHeaders = expect["headers"] as? [String: String] {
            for (header, value) in wantedHeaders {
                XCTAssertEqual(DeployedFolderResolutionTests.value(of: header, in: headers), value, "\(name): \(header)")
            }
        }
        if let prefix = expect["noHeaderStartingWith"] as? String {
            for header in headers {
                XCTAssertFalse(header.name.lowercased().hasPrefix(prefix.lowercased()), "\(name): \(header.name)")
            }
        }
        if let file = expect["file"] as? String {
            if let servedFile {
                XCTAssertEqual(servedFile, file, name)
            }
            if let body, expect["noBody"] as? Bool != true {
                let expected: Data = try Data(contentsOf: root.appendingPathComponent(file))
                XCTAssertEqual(body, expected, "\(name): the body is not \(file)")
            }
        }
        if expect["noBody"] as? Bool == true, let body {
            XCTAssertTrue(body.isEmpty, "\(name): a HEAD answer carried a body")
        }
        if let lacks = expect["bodyLacks"] as? String, let body {
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(lacks), "\(name): looks like a listing")
        }
    }

    // MARK: - Tests: the resolver

    func testEveryResolutionCaseThroughTheResolver() throws {
        let cases: [[String: Any]] = try DeployedFolderResolutionTests.cases()
        XCTAssertGreaterThanOrEqual(cases.count, 70, "the case list has shrunk")
        let port: Int = 41399
        for testCase in cases {
            let files: [String: Any] = try XCTUnwrap(testCase["files"] as? [String: Any])
            let fixture: (root: URL, outside: URL, top: URL) = try DeployedFolderResolutionTests.makeFixture(files: files)
            defer {
                try? FileManager.default.removeItem(at: fixture.top)
            }
            let request: DeployedFolderResolver.Request = try DeployedFolderResolutionTests.request(from: testCase, port: port)
            let answer: DeployedFolderResolver.Answer = DeployedFolderResolver.answer(to: request, root: fixture.root, port: port)
            var body: Data? = nil
            switch answer.body {
            case .none:
                body = Data()
            case .data(let data):
                body = data
            case .file(let url, let offset, let length):
                let all: Data = try Data(contentsOf: url)
                body = all.subdata(in: Int(offset)..<Int(offset + length))
            }
            var bodyToCheck: Data? = body
            if answer.status == 206 {
                bodyToCheck = nil
            }
            try check(testCase, status: answer.status, headers: answer.headers, body: bodyToCheck,
                      servedFile: answer.servedFile, root: fixture.root, how: "resolver")
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            if expect["closes"] as? Bool == true {
                XCTAssertTrue(answer.closesTheConnection, "\(testCase["name"] ?? ""): should close")
            }
        }
    }

    // MARK: - Tests: the real listener

    func testEveryResolutionCaseThroughTheListener() async throws {
        let cases: [[String: Any]] = try DeployedFolderResolutionTests.cases()
        for testCase in cases {
            let files: [String: Any] = try XCTUnwrap(testCase["files"] as? [String: Any])
            let fixture: (root: URL, outside: URL, top: URL) = try DeployedFolderResolutionTests.makeFixture(files: files)
            let started: (server: DeployedFolderServer, firstWasTaken: Bool) = try await DeployedFolderServer.start(
                root: fixture.root, candidates: DeployedFolderResolutionTests.testPorts(), onFolderGone: {}
            )
            let port: Int = started.server.port
            let request: DeployedFolderResolver.Request = try DeployedFolderResolutionTests.request(from: testCase, port: port)
            let answer: RawHTTP.Answer? = RawHTTP.exchange(port: port, request: request)
            await started.server.stop()
            try? FileManager.default.removeItem(at: fixture.top)
            let name: String = (testCase["name"] as? String) ?? ""
            guard let answer else {
                let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
                // A refusal may close before answering; never a page.
                XCTAssertEqual(expect["refused"] as? Bool, true, "\(name): no answer over the socket")
                continue
            }
            var body: Data? = answer.body
            if answer.status == 206 {
                body = nil
            }
            // A refusal's body is checked for the outside secret only.
            try check(testCase, status: answer.status, headers: answer.headers, body: body,
                      servedFile: nil, root: fixture.root, how: "listener")
            let expect: [String: Any] = try XCTUnwrap(testCase["expect"] as? [String: Any])
            if expect["closes"] as? Bool == true {
                XCTAssertTrue(answer.closedAfter, "\(name): the connection stayed open")
            }
        }
    }

    /// Ports for tests: the block, from its top, so a teacher's own show
    /// (which starts from its hash) is rarely in the way.
    static func testPorts() -> [Int] {
        var ports: [Int] = []
        var port: Int = DeployedFolderAddress.firstPort + DeployedFolderAddress.blockSize - 1
        while port >= DeployedFolderAddress.firstPort {
            ports.append(port)
            port -= 1
        }
        return ports
    }

    // MARK: - Tests: limits and connections

    func testTheLimitsAreTheContracts() throws {
        let section: [String: Any] = try DeployedFolderResolutionTests.section()
        let limits: [String: Any] = try XCTUnwrap(section["limits"] as? [String: Any])
        XCTAssertEqual(limits["maximumConnections"] as? Int, DeployedFolderServer.maximumConnections)
        XCTAssertEqual(limits["maximumRequestLineBytes"] as? Int, DeployedFolderServer.maximumRequestLineBytes)
        XCTAssertEqual(limits["maximumHeaderBytes"] as? Int, DeployedFolderServer.maximumHeaderBytes)
        XCTAssertEqual(limits["secondsToSendTheHeaders"] as? Int, DeployedFolderServer.secondsToSendTheHeaders)
        XCTAssertEqual(limits["secondsIdleBetweenRequests"] as? Int, DeployedFolderServer.secondsIdleBetweenRequests)
        XCTAssertEqual(limits["secondsToTakeAPiece"] as? Int, DeployedFolderServer.secondsToTakeAPiece)
    }

    func testEveryConnectionCase() async throws {
        let section: [String: Any] = try DeployedFolderResolutionTests.section()
        let cases: [[String: Any]] = try XCTUnwrap(section["connectionCases"] as? [[String: Any]])
        var kinds: [String] = []
        for testCase in cases {
            kinds.append(try XCTUnwrap(testCase["kind"] as? String))
        }
        XCTAssertEqual(kinds.sorted(), [
            "aConnectionPastTheMaximumMakesRoom", "headersNotSentInTime", "headersTooLarge",
            "readersThatStopReading", "requestLineTooLong", "theNetworkAddressIsRefused",
            "twoRequestsOnOneConnection",
        ], "a connection case this test does not know")

        let fixture: (root: URL, outside: URL, top: URL) = try DeployedFolderResolutionTests.makeFixture(files: ["index.html": "home"])
        defer {
            try? FileManager.default.removeItem(at: fixture.top)
        }
        let started: (server: DeployedFolderServer, firstWasTaken: Bool) = try await DeployedFolderServer.start(
            root: fixture.root, candidates: DeployedFolderResolutionTests.testPorts(), onFolderGone: {}
        )
        let port: Int = started.server.port
        let host: String = "Host: 127.0.0.1:\(port)\r\n"

        // requestLineTooLong
        let longTarget: String = "/" + String(repeating: "a", count: DeployedFolderServer.maximumRequestLineBytes + 100)
        let tooLong: RawHTTP.Answer? = RawHTTP.exchange(port: port, raw: Data("GET \(longTarget) HTTP/1.1\r\n\(host)\r\n".utf8))
        XCTAssertEqual(tooLong?.status, 414)
        XCTAssertEqual(tooLong?.closedAfter, true)

        // headersTooLarge
        let big: String = "X-Big: " + String(repeating: "b", count: DeployedFolderServer.maximumHeaderBytes + 100) + "\r\n"
        let tooLarge: RawHTTP.Answer? = RawHTTP.exchange(port: port, raw: Data("GET / HTTP/1.1\r\n\(host)\(big)\r\n".utf8))
        XCTAssertEqual(tooLarge?.status, 431)
        XCTAssertEqual(tooLarge?.closedAfter, true)

        // twoRequestsOnOneConnection
        let twice: String = "GET / HTTP/1.1\r\n\(host)\r\nGET / HTTP/1.1\r\n\(host)Connection: close\r\n\r\n"
        let both: [RawHTTP.Answer] = RawHTTP.exchangeMany(port: port, raw: Data(twice.utf8), count: 2)
        XCTAssertEqual(both.count, 2, "both requests on one connection were answered")
        for answer in both {
            XCTAssertEqual(answer.status, 200)
        }

        // theNetworkAddressIsRefused
        if let address = RawHTTP.thisComputersNetworkAddress() {
            XCTAssertFalse(RawHTTP.canConnect(address: address, port: port), "reached through \(address)")
        } else {
            print("No network address on this computer: the loopback-only check had nothing to try.")
        }

        // headersNotSentInTime
        let slow: Int32? = RawHTTP.connect(port: port)
        XCTAssertNotNil(slow)
        if let slow {
            RawHTTP.send(slow, Data("GET / HTTP/1.1\r\n".utf8))
            XCTAssertTrue(RawHTTP.closesWithin(slow, seconds: Double(DeployedFolderServer.secondsToSendTheHeaders + 5)),
                          "a connection that never finished its headers was kept open")
            close(slow)
        }

        // aConnectionPastTheMaximumMakesRoom
        var silent: [Int32] = []
        var index: Int = 0
        while index < DeployedFolderServer.maximumConnections {
            if let socket = RawHTTP.connect(port: port) {
                silent.append(socket)
            }
            index += 1
        }
        XCTAssertEqual(silent.count, DeployedFolderServer.maximumConnections)
        let newcomer: RawHTTP.Answer? = RawHTTP.exchange(port: port, raw: Data("GET / HTTP/1.1\r\n\(host)Connection: close\r\n\r\n".utf8))
        XCTAssertEqual(newcomer?.status, 200, "with every place taken by silent connections, a newcomer was not answered")
        var closed: Int = 0
        for socket in silent {
            if RawHTTP.closesWithin(socket, seconds: 0.2) {
                closed += 1
            }
        }
        XCTAssertGreaterThanOrEqual(closed, 1, "no quiet connection was closed to make room")
        for socket in silent {
            close(socket)
        }
        await started.server.stop()
    }

    /// The implementation review's M2, measured there: 64 readers that ask
    /// for a large file and never read held every place, and a normal
    /// request was refused at 2 s and at 47 s.
    func testReadersThatStopReadingDoNotShutTheSiteOut() async throws {
        let fixture: (root: URL, outside: URL, top: URL) = try DeployedFolderResolutionTests.makeFixture(files: ["index.html": "home"])
        defer {
            try? FileManager.default.removeItem(at: fixture.top)
        }
        // Larger than any buffer between the two ends.
        let big: Data = Data(count: 16 * 1024 * 1024)
        try big.write(to: fixture.root.appendingPathComponent("big.mp4"))
        let started: (server: DeployedFolderServer, firstWasTaken: Bool) = try await DeployedFolderServer.start(
            root: fixture.root, candidates: DeployedFolderResolutionTests.testPorts(), onFolderGone: {}
        )
        let port: Int = started.server.port
        var readers: [Int32] = []
        var index: Int = 0
        while index < DeployedFolderServer.maximumConnections {
            if let socket = RawHTTP.connect(port: port, receiveBuffer: 4096) {
                RawHTTP.send(socket, Data("GET /big.mp4 HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n".utf8))
                readers.append(socket)
            }
            index += 1
        }
        XCTAssertEqual(readers.count, DeployedFolderServer.maximumConnections)
        let normal: RawHTTP.Answer? = RawHTTP.exchange(
            port: port, raw: Data("GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n".utf8)
        )
        XCTAssertEqual(normal?.status, 200, "64 readers that stopped reading shut a normal request out")
        // The newcomer made room by resetting one reader. The others are
        // reset once a piece has gone untaken for long enough. Every reader
        // is watched at once, within ONE bound (the fix review's M-c: one
        // bound per reader could have run for 64 x 40 s).
        let displaced: Int = RawHTTP.countClosed(readers)
        let deadline: Date = Date().addingTimeInterval(Double(DeployedFolderServer.secondsToTakeAPiece + 15))
        var closedOne: Bool = false
        while Date() < deadline && !closedOne {
            if RawHTTP.countClosed(readers) > displaced {
                closedOne = true
            } else {
                // A socket's state from outside has no event to wait on.
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        XCTAssertTrue(closedOne, "a reader that stopped reading was never closed")
        for socket in readers {
            close(socket)
        }
        await started.server.stop()
    }

    // MARK: - Tests: content types and addresses

    func testTheContentTypesAreTheContractsBothWays() throws {
        let section: [String: Any] = try DeployedFolderResolutionTests.section()
        let table: [String: String] = try XCTUnwrap(section["contentTypes"] as? [String: String])
        XCTAssertEqual(table, DeployedFolderContentTypes.table)
        XCTAssertEqual(section["unknownContentType"] as? String, DeployedFolderContentTypes.unknown)
    }

    func testNoAddressIsInThePreviewWalkOrTheSystemsRange() {
        let candidates: [Int] = DeployedFolderAddress.candidates(forCanonicalPath: "/x", remembered: nil)
        XCTAssertEqual(candidates.count, DeployedFolderAddress.blockSize)
        var seen: Set<Int> = []
        for port in candidates {
            XCTAssertFalse(port >= 8081 && port <= 9474, "\(port) is in the preview walk")
            XCTAssertFalse(port >= 49152, "\(port) is in the system's range")
            XCTAssertFalse(seen.contains(port), "\(port) twice")
            seen.insert(port)
        }
    }
}

/// A plain blocking socket client, for asking the real listener.
nonisolated enum RawHTTP {

    // MARK: - Types

    struct Answer {
        var status: Int
        var headers: [(name: String, value: String)]
        var body: Data
        var closedAfter: Bool
    }

    // MARK: - Functions

    static func connect(port: Int, address: String = "127.0.0.1", receiveBuffer: Int32? = nil) -> Int32? {
        let socketHandle: Int32 = socket(AF_INET, SOCK_STREAM, 0)
        if socketHandle < 0 {
            return nil
        }
        if var size = receiveBuffer {
            setsockopt(socketHandle, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        }
        var where_: sockaddr_in = sockaddr_in()
        where_.sin_family = sa_family_t(AF_INET)
        where_.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, address, &where_.sin_addr)
        let result: Int32 = withUnsafePointer(to: &where_) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.connect(socketHandle, address, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            close(socketHandle)
            return nil
        }
        var timeout: timeval = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(socketHandle, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(socketHandle, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        return socketHandle
    }

    static func canConnect(address: String, port: Int) -> Bool {
        guard let socketHandle = connect(port: port, address: address) else {
            return false
        }
        close(socketHandle)
        return true
    }

    static func send(_ socketHandle: Int32, _ data: Data) {
        data.withUnsafeBytes { buffer in
            var sent: Int = 0
            while sent < buffer.count {
                let written: Int = Darwin.send(socketHandle, buffer.baseAddress! + sent, buffer.count - sent, 0)
                if written <= 0 {
                    return
                }
                sent += written
            }
        }
    }

    /// Reads into `buffer` until it holds `wanted` bytes or the peer closes;
    /// false when it closed or timed out first.
    static func readMore(_ socketHandle: Int32, into buffer: inout Data) -> Bool {
        var chunk: [UInt8] = [UInt8](repeating: 0, count: 65536)
        let count: Int = recv(socketHandle, &chunk, chunk.count, 0)
        if count <= 0 {
            return false
        }
        buffer.append(contentsOf: chunk[0..<count])
        return true
    }

    /// One answer from the front of `buffer`, reading more as needed.
    static func readAnswer(_ socketHandle: Int32, buffer: inout Data, isHead: Bool) -> Answer? {
        let ending: Data = Data("\r\n\r\n".utf8)
        while buffer.range(of: ending) == nil {
            if !readMore(socketHandle, into: &buffer) {
                return nil
            }
        }
        guard let end = buffer.range(of: ending) else {
            return nil
        }
        let head: String = String(decoding: buffer.subdata(in: buffer.startIndex..<end.lowerBound), as: UTF8.self)
        buffer.removeSubrange(buffer.startIndex..<end.upperBound)
        let lines: [String] = head.components(separatedBy: "\r\n")
        let statusWords: [String] = (lines.first ?? "").components(separatedBy: " ")
        guard statusWords.count >= 2, let status = Int(statusWords[1]) else {
            return nil
        }
        var headers: [(name: String, value: String)] = []
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                headers.append((
                    name: String(line[line.startIndex..<colon]),
                    value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                ))
            }
        }
        var length: Int = 0
        for header in headers where header.name.lowercased() == "content-length" {
            length = Int(header.value) ?? 0
        }
        if isHead || status == 304 {
            length = 0
        }
        while buffer.count < length {
            if !readMore(socketHandle, into: &buffer) {
                break
            }
        }
        let bodyLength: Int = min(length, buffer.count)
        let body: Data = buffer.subdata(in: buffer.startIndex..<(buffer.startIndex + bodyLength))
        buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + bodyLength))
        return Answer(status: status, headers: headers, body: body, closedAfter: false)
    }

    /// Whether the peer closes the socket within `seconds`.
    static func closesWithin(_ socketHandle: Int32, seconds: Double) -> Bool {
        var waiting: pollfd = pollfd(fd: socketHandle, events: Int16(POLLIN), revents: 0)
        let ready: Int32 = poll(&waiting, 1, Int32(seconds * 1000))
        if ready <= 0 {
            return false
        }
        var byte: UInt8 = 0
        let count: Int = recv(socketHandle, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return count <= 0
    }

    /// Whether the peer closes within `seconds`, reading nothing of what it
    /// sent: the bytes already waiting are left where they are, and the
    /// close is seen as an error or an end on a peek past them.
    static func closedEvenAfterData(_ socketHandle: Int32, seconds: Double) -> Bool {
        let deadline: Date = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            var error: Int32 = 0
            var length: socklen_t = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(socketHandle, SOL_SOCKET, SO_ERROR, &error, &length)
            if error != 0 {
                return true
            }
            var info: tcp_connection_info = tcp_connection_info()
            var infoLength: socklen_t = socklen_t(MemoryLayout<tcp_connection_info>.size)
            if getsockopt(socketHandle, IPPROTO_TCP, TCP_CONNECTION_INFO, &info, &infoLength) == 0 {
                // TCPS_CLOSE_WAIT (5) and later: the server has closed its end.
                if info.tcpi_state >= 5 {
                    return true
                }
            }
            var waiting: pollfd = pollfd(fd: socketHandle, events: Int16(POLLHUP), revents: 0)
            let remaining: Double = deadline.timeIntervalSinceNow * 1000
            _ = poll(&waiting, 1, Int32(max(0, min(500, remaining))))
            if (waiting.revents & Int16(POLLHUP)) != 0 {
                return true
            }
        }
        return false
    }

    /// How many of `sockets` the peer has closed or reset, looking at each
    /// once without waiting.
    static func countClosed(_ sockets: [Int32]) -> Int {
        var closed: Int = 0
        for socket in sockets {
            if closedEvenAfterData(socket, seconds: 0.001) {
                closed += 1
            }
        }
        return closed
    }

    /// Sends one request as the case writes it, with Connection: close
    /// added, and reads its answer.
    static func exchange(port: Int, request: DeployedFolderResolver.Request) -> Answer? {
        var text: String = "\(request.method) \(request.target) HTTP/1.1\r\n"
        for header in request.headers {
            text += "\(header.name): \(header.value)\r\n"
        }
        text += "connection: close\r\n\r\n"
        if request.value(of: "content-length") == "5" {
            text += "hello"
        }
        guard let socketHandle = connect(port: port) else {
            return nil
        }
        defer {
            close(socketHandle)
        }
        send(socketHandle, Data(text.utf8))
        var buffer: Data = Data()
        guard var answer = readAnswer(socketHandle, buffer: &buffer, isHead: request.method == "HEAD") else {
            return nil
        }
        answer.closedAfter = closesWithin(socketHandle, seconds: 2)
        return answer
    }

    static func exchange(port: Int, raw: Data) -> Answer? {
        guard let socketHandle = connect(port: port) else {
            return nil
        }
        defer {
            close(socketHandle)
        }
        send(socketHandle, raw)
        var buffer: Data = Data()
        guard var answer = readAnswer(socketHandle, buffer: &buffer, isHead: false) else {
            return nil
        }
        answer.closedAfter = closesWithin(socketHandle, seconds: 2)
        return answer
    }

    static func exchangeMany(port: Int, raw: Data, count: Int) -> [Answer] {
        var answers: [Answer] = []
        guard let socketHandle = connect(port: port) else {
            return answers
        }
        defer {
            close(socketHandle)
        }
        send(socketHandle, raw)
        var buffer: Data = Data()
        while answers.count < count {
            guard let answer = readAnswer(socketHandle, buffer: &buffer, isHead: false) else {
                break
            }
            answers.append(answer)
        }
        return answers
    }

    /// An IPv4 address of this computer that is not loopback, if it has one.
    static func thisComputersNetworkAddress() -> String? {
        var first: UnsafeMutablePointer<ifaddrs>? = nil
        if getifaddrs(&first) != 0 {
            return nil
        }
        defer {
            freeifaddrs(first)
        }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            if let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) {
                var host: [CChar] = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let text: String = String(cString: host)
                if !text.hasPrefix("127.") && !text.isEmpty {
                    return text
                }
            }
            cursor = entry.pointee.ifa_next
        }
        return nil
    }
}
