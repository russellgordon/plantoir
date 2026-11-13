import Foundation

/// How a request from the browser is answered from a deployed folder (#850):
/// which file, or which redirect, or which refusal. Pure apart from reading
/// the folder, so `DeployedFolderResolutionTests` runs every case in
/// `contracts/shared-rules.json` → `deployedFolderInBrowser.resolution.cases`
/// both through this function and through the real listener.
///
/// **The aim** (the plan review's M7): every link the build writes resolves,
/// and nothing a strict web host refuses is accepted here. It is not a copy
/// of any one host. A folder deploy is the one destination whose host is
/// unknown (#849), so this shows the site as Plantoir serves it.
///
/// **The name match reads the folder's own listing at EVERY level**, never
/// `fileExists`: APFS and NTFS ignore case, and a strict host does not, so
/// `/concepts/` must not find `Concepts/` here when it would not find it
/// there (the review's M4, measured: a last-component-only check served it).
nonisolated enum DeployedFolderResolver {

    // MARK: - Types

    /// One request, as the listener read it.
    struct Request: Sendable {
        var method: String
        var target: String
        /// Header names lower-cased, in the order they arrived.
        var headers: [(name: String, value: String)]

        /// The first value of a header, by its lower-cased name.
        func value(of name: String) -> String? {
            for header in headers {
                if header.name == name {
                    return header.value
                }
            }
            return nil
        }

        /// How many times a header arrived.
        func count(of name: String) -> Int {
            var total: Int = 0
            for header in headers {
                if header.name == name {
                    total += 1
                }
            }
            return total
        }
    }

    /// What the answer carries after its headers.
    enum Body: Sendable, Equatable {
        case none
        case data(Data)
        /// Part of a file: `length` bytes from `offset`.
        case file(URL, offset: UInt64, length: UInt64)
    }

    /// One answer.
    struct Answer: Sendable {
        var status: Int
        var headers: [(name: String, value: String)]
        var body: Body
        /// The connection closes after this answer.
        var closesTheConnection: Bool = false
        /// The file served, relative to the folder, for tests; nil when no
        /// file was served.
        var servedFile: String? = nil

        /// The first value of a header, by name, ignoring case.
        func value(of name: String) -> String? {
            let wanted: String = name.lowercased()
            for header in headers {
                if header.name.lowercased() == wanted {
                    return header.value
                }
            }
            return nil
        }
    }

    // MARK: - Stored properties

    /// Names that are never pages: the web hosts' own control files, and the
    /// names Windows reserves (refused on both platforms, so the two apps
    /// answer alike).
    static let refusedNames: [String] = [
        "_headers", "_redirects",
        "con", "prn", "aux", "nul",
        "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
        "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
    ]

    /// The page sent for a missing page when the site has no `404.html`.
    static let builtInNotFoundPage: String =
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>404</title></head><body><h1>404</h1></body></html>"

    // MARK: - Functions

    /// The answer to `request`, from the folder at `root`, for a listener on
    /// `port`.
    static func answer(to request: Request, root: URL, port: Int) -> Answer {
        // Only the one address this app hands out (the review's H3): a
        // prefix check let `127.0.0.1.evil.example` through, which is the
        // name a page rebinding itself to this computer would send.
        if request.count(of: "host") != 1 || request.value(of: "host") != "127.0.0.1:\(port)" {
            return refusal(400, closing: true)
        }
        if request.method != "GET" && request.method != "HEAD" {
            // A body this never reads would be taken for the next request,
            // so a request that says it has one closes the connection.
            let saysItHasABody: Bool = request.value(of: "transfer-encoding") != nil
                || (request.value(of: "content-length") ?? "0").trimmingCharacters(in: .whitespaces) != "0"
            var answer: Answer = refusal(405, closing: saysItHasABody)
            answer.headers.append((name: "Allow", value: "GET, HEAD"))
            return answer
        }
        // Only a path: an absolute address names another site.
        if !request.target.hasPrefix("/") {
            return refusal(400, closing: true)
        }
        // A GET carries no body; one that says it does is not one this
        // reads past, so the connection closes (the review's M1).
        if request.value(of: "transfer-encoding") != nil {
            return refusal(400, closing: true)
        }
        if let length = request.value(of: "content-length") {
            if length.trimmingCharacters(in: .whitespaces) != "0" {
                return refusal(400, closing: true)
            }
        }
        let isHead: Bool = request.method == "HEAD"

        let parts: TargetParts = split(target: request.target)
        guard let path = readPath(parts.path) else {
            return notFound(root: root, isHead: isHead)
        }

        let rootReal: URL = root.resolvingSymlinksInPath()
        var directory: URL = root
        var relative: [String] = []
        // Every folder on the way down, matched against its listing.
        var index: Int = 0
        while index < path.segments.count - 1 {
            let wanted: String = path.segments[index]
            guard let actual = entryName(matching: wanted, in: directory), isFolder(directory.appendingPathComponent(actual)) else {
                return notFound(root: root, isHead: isHead)
            }
            directory = directory.appendingPathComponent(actual)
            relative.append(actual)
            index += 1
        }

        let last: String = path.segments.isEmpty ? "" : path.segments[path.segments.count - 1]

        if path.segments.isEmpty || path.endsWithSlash {
            // A folder's address: its index page.
            var folder: URL = directory
            var folderRelative: [String] = relative
            if !last.isEmpty {
                if let actual = entryName(matching: last, in: directory), isFolder(directory.appendingPathComponent(actual)) {
                    folder = directory.appendingPathComponent(actual)
                    folderRelative.append(actual)
                } else if let page = entryName(matching: last + ".html", in: directory), isFile(directory.appendingPathComponent(page)) {
                    // `/a/` where only `a.html` exists: the page's own address.
                    return redirect(segments: path.segments, endsWithSlash: false, query: parts.query)
                } else {
                    return notFound(root: root, isHead: isHead)
                }
            }
            if let indexName = entryName(matching: "index.html", in: folder), isFile(folder.appendingPathComponent(indexName)) {
                folderRelative.append(indexName)
                return serve(file: folder.appendingPathComponent(indexName), relative: folderRelative,
                             rootReal: rootReal, request: request, root: root, isHead: isHead)
            }
            // Never a listing.
            return notFound(root: root, isHead: isHead)
        }

        // A name with no slash after it: the file itself, then the page
        // with `.html` added, then a folder (which needs its slash, so its
        // relative links work).
        if let actual = entryName(matching: last, in: directory), isFile(directory.appendingPathComponent(actual)) {
            var fileRelative: [String] = relative
            fileRelative.append(actual)
            return serve(file: directory.appendingPathComponent(actual), relative: fileRelative,
                         rootReal: rootReal, request: request, root: root, isHead: isHead)
        }
        if let page = entryName(matching: last + ".html", in: directory), isFile(directory.appendingPathComponent(page)) {
            var fileRelative: [String] = relative
            fileRelative.append(page)
            return serve(file: directory.appendingPathComponent(page), relative: fileRelative,
                         rootReal: rootReal, request: request, root: root, isHead: isHead)
        }
        if let actual = entryName(matching: last, in: directory), isFolder(directory.appendingPathComponent(actual)) {
            let folder: URL = directory.appendingPathComponent(actual)
            if let indexName = entryName(matching: "index.html", in: folder), isFile(folder.appendingPathComponent(indexName)) {
                return redirect(segments: path.segments, endsWithSlash: true, query: parts.query)
            }
        }
        return notFound(root: root, isHead: isHead)
    }

    // MARK: - Functions: reading the address

    /// A request target split at its query.
    struct TargetParts {
        var path: String
        var query: String?
    }

    /// Splits off the query, and anything after a `#` (a browser never
    /// sends one; a raw request might).
    static func split(target: String) -> TargetParts {
        var path: String = target
        var query: String? = nil
        if let hash = path.firstIndex(of: "#") {
            path = String(path[path.startIndex..<hash])
        }
        if let mark = path.firstIndex(of: "?") {
            query = String(path[path.index(after: mark)...])
            path = String(path[path.startIndex..<mark])
        }
        return TargetParts(path: path, query: query)
    }

    /// A path read into its decoded names.
    struct ReadPath {
        var segments: [String]
        var endsWithSlash: Bool
    }

    /// The path's names, decoded and checked, or nil for a path that can
    /// name nothing in the folder: `..`, a dot file, an encoded or raw
    /// separator, a drive or stream (`:`), a reserved name, an empty name
    /// in the middle (`//`), or broken percent-encoding.
    static func readPath(_ rawPath: String) -> ReadPath? {
        guard rawPath.hasPrefix("/") else {
            return nil
        }
        if rawPath.hasPrefix("//") {
            return nil
        }
        if rawPath.contains("\\") {
            return nil
        }
        let body: String = String(rawPath.dropFirst())
        if body.isEmpty {
            return ReadPath(segments: [], endsWithSlash: true)
        }
        var pieces: [String] = body.components(separatedBy: "/")
        var endsWithSlash: Bool = false
        if pieces.last == "" {
            endsWithSlash = true
            pieces.removeLast()
        }
        var segments: [String] = []
        for piece in pieces {
            guard let decoded = decodedName(piece) else {
                return nil
            }
            segments.append(decoded)
        }
        return ReadPath(segments: segments, endsWithSlash: endsWithSlash)
    }

    /// One raw name, decoded, or nil when it can name nothing here.
    static func decodedName(_ raw: String) -> String? {
        if raw.isEmpty {
            return nil
        }
        let lowered: String = raw.lowercased()
        if lowered.contains("%2f") || lowered.contains("%5c") || lowered.contains("%00") {
            return nil
        }
        // `+` is a plus in a path, never a space.
        guard let decoded = raw.removingPercentEncoding else {
            return nil
        }
        let name: String = decoded.precomposedStringWithCanonicalMapping
        if name.isEmpty || name.hasPrefix(".") || name.hasSuffix(".") || name.hasSuffix(" ") {
            return nil
        }
        for scalar in name.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return nil
            }
            if scalar == "/" || scalar == "\\" || scalar == ":" {
                return nil
            }
        }
        var stem: String = name.lowercased()
        if let dot = stem.firstIndex(of: ".") {
            stem = String(stem[stem.startIndex..<dot])
        }
        for refused in refusedNames {
            if stem == refused || name.lowercased() == refused {
                return nil
            }
        }
        return name
    }

    // MARK: - Functions: reading the folder

    /// The entry of `directory` whose name is `wanted` exactly (after both
    /// are put in the same Unicode form), or nil. Case counts.
    static func entryName(matching wanted: String, in directory: URL) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        for name in names {
            if name.precomposedStringWithCanonicalMapping == wanted {
                return name
            }
        }
        return nil
    }

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    static func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    /// Whether `url`, with every link followed, is still inside the folder.
    static func staysInside(_ url: URL, rootReal: URL) -> Bool {
        let real: String = url.resolvingSymlinksInPath().path
        let rootPath: String = rootReal.path
        return real == rootPath || real.hasPrefix(rootPath + "/")
    }

    // MARK: - Functions: the answers

    /// A file, whole or the part a range asks for.
    static func serve(
        file: URL, relative: [String], rootReal: URL, request: Request, root: URL, isHead: Bool
    ) -> Answer {
        if !staysInside(file, rootReal: rootReal) {
            return notFound(root: root, isHead: isHead)
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber else {
            return notFound(root: root, isHead: isHead)
        }
        let length: UInt64 = size.uint64Value
        let modified: Date = (attributes[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        let tag: String = "W/\"\(length)-\(Int(modified.timeIntervalSince1970 * 1000))\""

        var headers: [(name: String, value: String)] = commonHeaders()
        headers.append((name: "Content-Type", value: DeployedFolderContentTypes.type(forFileNamed: file.lastPathComponent)))
        headers.append((name: "Accept-Ranges", value: "bytes"))
        headers.append((name: "ETag", value: tag))
        headers.append((name: "Last-Modified", value: httpDate(modified)))
        let servedFile: String = relative.joined(separator: "/")

        if let condition = request.value(of: "if-none-match"), condition == tag {
            var answer: Answer = Answer(status: 304, headers: headers, body: .none)
            answer.servedFile = servedFile
            return answer
        }

        if let rangeHeader = request.value(of: "range") {
            switch byteRange(rangeHeader, length: length) {
            case .whole:
                break
            case .unsatisfiable:
                var refused: [(name: String, value: String)] = commonHeaders()
                refused.append((name: "Content-Range", value: "bytes */\(length)"))
                refused.append((name: "Content-Length", value: "0"))
                return Answer(status: 416, headers: refused, body: .none)
            case .part(let first, let lastByte):
                let partLength: UInt64 = lastByte - first + 1
                headers.append((name: "Content-Range", value: "bytes \(first)-\(lastByte)/\(length)"))
                headers.append((name: "Content-Length", value: String(partLength)))
                var answer: Answer = Answer(
                    status: 206, headers: headers,
                    body: isHead ? .none : .file(file, offset: first, length: partLength)
                )
                answer.servedFile = servedFile
                return answer
            }
        }
        headers.append((name: "Content-Length", value: String(length)))
        var answer: Answer = Answer(
            status: 200, headers: headers,
            body: isHead ? .none : .file(file, offset: 0, length: length)
        )
        answer.servedFile = servedFile
        return answer
    }

    /// What a `Range` header asks for.
    enum RangeRequest: Equatable {
        case whole
        case part(first: UInt64, last: UInt64)
        case unsatisfiable
    }

    /// One `bytes=` range read against a file of `length` bytes. Anything
    /// it cannot read, and several ranges, mean the whole file.
    static func byteRange(_ header: String, length: UInt64) -> RangeRequest {
        let trimmed: String = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("bytes=") else {
            return .whole
        }
        let spec: String = String(trimmed.dropFirst("bytes=".count))
        if spec.contains(",") {
            return .whole
        }
        let halves: [String] = spec.components(separatedBy: "-")
        if halves.count != 2 {
            return .whole
        }
        let startText: String = halves[0].trimmingCharacters(in: .whitespaces)
        let endText: String = halves[1].trimmingCharacters(in: .whitespaces)
        if startText.isEmpty {
            // The last N bytes.
            guard let suffix = UInt64(endText) else {
                return .whole
            }
            if suffix == 0 || length == 0 {
                return .unsatisfiable
            }
            let first: UInt64 = suffix >= length ? 0 : length - suffix
            return .part(first: first, last: length - 1)
        }
        guard let first = UInt64(startText) else {
            return .whole
        }
        if first >= length {
            return .unsatisfiable
        }
        if endText.isEmpty {
            return .part(first: first, last: length - 1)
        }
        guard let end = UInt64(endText) else {
            return .whole
        }
        if end < first {
            return .whole
        }
        let lastByte: UInt64 = end >= length ? length - 1 : end
        return .part(first: first, last: lastByte)
    }

    /// A redirect to the page's own address, built from the decoded names
    /// encoded again, so it is always single-slashed and percent-encoded.
    static func redirect(segments: [String], endsWithSlash: Bool, query: String?) -> Answer {
        var location: String = ""
        for segment in segments {
            location += "/" + encodedName(segment)
        }
        if endsWithSlash {
            location += "/"
        }
        if location.isEmpty {
            location = "/"
        }
        if let query, !query.isEmpty, queryIsSafe(query) {
            location += "?" + query
        }
        var headers: [(name: String, value: String)] = commonHeaders()
        headers.append((name: "Location", value: location))
        headers.append((name: "Content-Length", value: "0"))
        return Answer(status: 308, headers: headers, body: .none)
    }

    /// One name, percent-encoded for an address.
    static func encodedName(_ name: String) -> String {
        var allowed: CharacterSet = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!$&'()*+,;=@")
        var ascii: CharacterSet = CharacterSet()
        ascii.insert(charactersIn: Unicode.Scalar(0x21)!...Unicode.Scalar(0x7E)!)
        let safe: CharacterSet = allowed.intersection(ascii)
        return name.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
    }

    /// A query kept on a redirect only when it holds nothing that could end
    /// a header line.
    static func queryIsSafe(_ query: String) -> Bool {
        for scalar in query.unicodeScalars {
            if scalar.value < 0x21 || scalar.value > 0x7E {
                return false
            }
        }
        return true
    }

    /// The site's own `404.html` with a 404, or a short page of its own.
    static func notFound(root: URL, isHead: Bool) -> Answer {
        var headers: [(name: String, value: String)] = commonHeaders()
        headers.append((name: "Content-Type", value: "text/html; charset=utf-8"))
        let page: URL = root.appendingPathComponent("404.html")
        let rootReal: URL = root.resolvingSymlinksInPath()
        if entryName(matching: "404.html", in: root) != nil, isFile(page), staysInside(page, rootReal: rootReal),
           let attributes = try? FileManager.default.attributesOfItem(atPath: page.path),
           let size = attributes[.size] as? NSNumber {
            headers.append((name: "Content-Length", value: String(size.uint64Value)))
            var answer: Answer = Answer(
                status: 404, headers: headers,
                body: isHead ? .none : .file(page, offset: 0, length: size.uint64Value)
            )
            answer.servedFile = "404.html"
            return answer
        }
        let data: Data = Data(builtInNotFoundPage.utf8)
        headers.append((name: "Content-Length", value: String(data.count)))
        return Answer(status: 404, headers: headers, body: isHead ? .none : .data(data))
    }

    /// A refusal with no page.
    static func refusal(_ status: Int, closing: Bool) -> Answer {
        var headers: [(name: String, value: String)] = commonHeaders()
        headers.append((name: "Content-Length", value: "0"))
        var answer: Answer = Answer(status: status, headers: headers, body: .none)
        answer.closesTheConnection = closing
        return answer
    }

    /// On every answer. `no-cache` rather than `no-store` (the review's
    /// L1): the browser asks again each time, so a redeploy shows on
    /// reload, and the page can still use the back and forward cache.
    /// `nosniff`, so a wrong type fails here as it would on a strict host.
    /// Never an `Access-Control-*` header.
    static func commonHeaders() -> [(name: String, value: String)] {
        return [
            (name: "Cache-Control", value: "no-cache"),
            (name: "X-Content-Type-Options", value: "nosniff"),
            (name: "Cross-Origin-Resource-Policy", value: "same-origin"),
        ]
    }

    /// A date as HTTP writes it.
    static func httpDate(_ date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    /// The words after a status code.
    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 304: return "Not Modified"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 414: return "URI Too Long"
        case 416: return "Range Not Satisfiable"
        case 431: return "Request Header Fields Too Large"
        default: return "Error"
        }
    }
}
