import Foundation

// The op kinds U2 defines (#899): what each one's content is, how it is
// checked against what is there now, and how it is moved one way or the
// other. The rule is `contracts/file-formats.json` → `undoJournal.opKinds`;
// the cases are `contracts/shared-rules.json` → `undo.checkCases` and
// `undo.listingCases`. Content, never times (ruling 4): every check here
// reads what is there and compares it with what the op recorded.

/// Any JSON value, as `editJSON` and `external` record it.
///
/// Compared as JSON: numbers by value (1 and 1.0 are one number), strings
/// code point for code point (never Unicode equivalence, as everywhere in
/// the journal), objects by their members whatever their order, arrays in
/// order. `true` is never the number 1.
nonisolated indirect enum UndoJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([UndoJSON])
    case object([String: UndoJSON])

    // MARK: - Initializer

    init(from decoder: Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let list = try? container.decode([UndoJSON].self) {
            self = .array(list)
        } else {
            self = .object(try container.decode([String: UndoJSON].self))
        }
    }

    // MARK: - Functions

    func encode(to encoder: Encoder) throws {
        var container: SingleValueEncodingContainer = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let flag):
            try container.encode(flag)
        case .number(let number):
            try container.encode(number)
        case .string(let text):
            try container.encode(text)
        case .array(let list):
            try container.encode(list)
        case .object(let members):
            try container.encode(members)
        }
    }

    static func == (first: UndoJSON, second: UndoJSON) -> Bool {
        switch (first, second) {
        case (.null, .null):
            return true
        case (.bool(let one), .bool(let other)):
            return one == other
        case (.number(let one), .number(let other)):
            return one == other
        case (.string(let one), .string(let other)):
            return UndoText.same(one, other)
        case (.array(let one), .array(let other)):
            if one.count != other.count {
                return false
            }
            var index: Int = 0
            while index < one.count {
                if one[index] != other[index] {
                    return false
                }
                index += 1
            }
            return true
        case (.object(let one), .object(let other)):
            if one.count != other.count {
                return false
            }
            for (name, value) in one {
                guard let match = other[name], match == value else {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }

    /// A value from `JSONSerialization` or a property list, or nil when it
    /// holds something JSON cannot (a date, raw data).
    static func from(foundation value: Any) -> UndoJSON? {
        if value is NSNull {
            return .null
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        }
        if let text = value as? String {
            return .string(text)
        }
        if let list = value as? [Any] {
            var converted: [UndoJSON] = []
            for element in list {
                guard let one = UndoJSON.from(foundation: element) else {
                    return nil
                }
                converted.append(one)
            }
            return .array(converted)
        }
        if let members = value as? [String: Any] {
            var converted: [String: UndoJSON] = [:]
            for (name, element) in members {
                guard let one = UndoJSON.from(foundation: element) else {
                    return nil
                }
                converted[name] = one
            }
            return .object(converted)
        }
        return nil
    }

    /// The value as `JSONSerialization` and `UserDefaults` take it.
    func foundation() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let flag):
            return NSNumber(value: flag)
        case .number(let number):
            if number.rounded() == number && abs(number) < 9_000_000_000_000_000 {
                return NSNumber(value: Int64(number))
            }
            return NSNumber(value: number)
        case .string(let text):
            return text
        case .array(let list):
            var converted: [Any] = []
            for element in list {
                converted.append(element.foundation())
            }
            return converted
        case .object(let members):
            var converted: [String: Any] = [:]
            for (name, element) in members {
                converted[name] = element.foundation()
            }
            return converted
        }
    }
}

// MARK: - replaceText

/// A hunk of a page: the text it replaced and the text either side of it.
///
/// The op holds `before`, `after`, `contextBefore` and `contextAfter`. Its
/// BEFORE WINDOW is contextBefore + before + contextAfter and its AFTER
/// WINDOW contextBefore + after + contextAfter, compared as UTF-8 bytes. A
/// window is FOUND when it occurs exactly once in the file (overlapping
/// occurrences counted) and every occurrence of the other window lies
/// inside that one. The page is as the step left it when the after window is
/// found, as it was when the before window is; otherwise (neither found,
/// either one twice, the page gone, not UTF-8, a folder) it is changed since.
/// Never a guess: two places the hunk could go are a change since.
nonisolated enum UndoHunk {

    // MARK: - Functions

    static func window(_ op: UndoOp, after: Bool) -> [UInt8]? {
        guard let contextBefore = op.contextBefore, let contextAfter = op.contextAfter,
              let middle = after ? op.after : op.before else {
            return nil
        }
        return Array((contextBefore + middle + contextAfter).utf8)
    }

    /// Every index the needle starts at, overlapping ones included.
    static func occurrences(of needle: [UInt8], in haystack: [UInt8]) -> [Int] {
        var found: [Int] = []
        if needle.isEmpty || needle.count > haystack.count {
            return found
        }
        var start: Int = 0
        while start + needle.count <= haystack.count {
            var matches: Bool = true
            var offset: Int = 0
            while offset < needle.count {
                if haystack[start + offset] != needle[offset] {
                    matches = false
                    break
                }
                offset += 1
            }
            if matches {
                found.append(start)
            }
            start += 1
        }
        return found
    }

    /// Where the window is found (see the type's rule), or nil.
    static func place(of window: [UInt8], beside other: [UInt8], in bytes: [UInt8]) -> Int? {
        let mine: [Int] = occurrences(of: window, in: bytes)
        if mine.count != 1 {
            return nil
        }
        let start: Int = mine[0]
        let end: Int = start + window.count
        for otherStart in occurrences(of: other, in: bytes) {
            let otherEnd: Int = otherStart + other.count
            if otherStart < start || otherEnd > end {
                return nil
            }
        }
        return start
    }

    static func state(of op: UndoOp, in item: UndoItem) -> UndoOpState {
        guard let data = item.data, UndoText.decode(data) != nil,
              let beforeWindow = window(op, after: false), let afterWindow = window(op, after: true) else {
            return .neither
        }
        let bytes: [UInt8] = Array(data)
        if place(of: beforeWindow, beside: afterWindow, in: bytes) != nil {
            return .before
        }
        if place(of: afterWindow, beside: beforeWindow, in: bytes) != nil {
            return .after
        }
        return .neither
    }

    /// The file with the hunk moved one way, or nil when it cannot be found.
    static func moved(_ op: UndoOp, from item: UndoItem, direction: UndoDirection) -> UndoItem? {
        guard let data = item.data, let beforeWindow = window(op, after: false),
              let afterWindow = window(op, after: true) else {
            return nil
        }
        let source: [UInt8] = direction == .backward ? afterWindow : beforeWindow
        let target: [UInt8] = direction == .backward ? beforeWindow : afterWindow
        let bytes: [UInt8] = Array(data)
        guard let start = place(of: source, beside: target, in: bytes) else {
            return nil
        }
        var result: [UInt8] = []
        var index: Int = 0
        while index < start {
            result.append(bytes[index])
            index += 1
        }
        for byte in target {
            result.append(byte)
        }
        index = start + source.count
        while index < bytes.count {
            result.append(bytes[index])
            index += 1
        }
        return .file(Data(result))
    }
}

// MARK: - editJSON

/// One member of a JSON file, found by walking `keyPath` from the top-level
/// object (each part a member name; every part but the last must be an
/// object). The file must be one JSON object; anything else, or a part on
/// the way that is not an object, is a change since. A member that is not
/// there is "absent", which is what an op with no `before` (or no `after`)
/// means. The file is written back the way the app writes its own JSON
/// (`CourseConfiguration`: pretty-printed, keys sorted, slashes unescaped,
/// a line feed at the end when there was one), every other member kept as
/// it was read; and a write whose result does not read back as exactly the
/// file with that one member changed is refused (changed since), so a value
/// JSON's reader would change on the way through is never written.
nonisolated enum UndoJSONMember {

    // MARK: - Functions

    enum Reading: Equatable {
        case absent
        case value(UndoJSON)
        case cannotTell
    }

    static func topLevel(of data: Data) -> [String: Any]? {
        guard UndoText.decode(data) != nil,
              let object = try? JSONSerialization.jsonObject(with: data, options: [.mutableContainers]) as? [String: Any] else {
            return nil
        }
        return object
    }

    static func reading(_ keyPath: [String], in data: Data) -> Reading {
        guard let object = topLevel(of: data), let tree = UndoJSON.from(foundation: object) else {
            return .cannotTell
        }
        return reading(keyPath, in: tree)
    }

    static func reading(_ keyPath: [String], in tree: UndoJSON) -> Reading {
        var current: UndoJSON = tree
        var index: Int = 0
        while index < keyPath.count {
            guard case .object(let members) = current else {
                return .cannotTell
            }
            guard let next = members[keyPath[index]] else {
                return .absent
            }
            current = next
            index += 1
        }
        return .value(current)
    }

    static func state(of op: UndoOp, in item: UndoItem) -> UndoOpState {
        guard let data = item.data, let keyPath = op.keyPath else {
            return .neither
        }
        let found: Reading = reading(keyPath, in: data)
        if found == .cannotTell {
            return .neither
        }
        if matches(found, op.valueBefore) {
            return .before
        }
        if matches(found, op.valueAfter) {
            return .after
        }
        return .neither
    }

    static func matches(_ found: Reading, _ expected: UndoJSON?) -> Bool {
        switch found {
        case .absent:
            return expected == nil
        case .value(let value):
            guard let expected else {
                return false
            }
            return value == expected
        case .cannotTell:
            return false
        }
    }

    /// The tree with the member set (nil: taken out), or nil when a part on
    /// the way is missing or not an object.
    static func setting(_ keyPath: [String], to value: UndoJSON?, in tree: UndoJSON) -> UndoJSON? {
        guard case .object(var members) = tree, let first = keyPath.first else {
            return nil
        }
        if keyPath.count == 1 {
            members[first] = value
            return .object(members)
        }
        guard let inner = members[first] else {
            return nil
        }
        let rest: [String] = Array(keyPath.dropFirst())
        guard let changed = setting(rest, to: value, in: inner) else {
            return nil
        }
        members[first] = changed
        return .object(members)
    }

    /// The same, on the objects `JSONSerialization` read, so every other
    /// member keeps the number it was read as.
    static func setting(_ keyPath: [String], to value: UndoJSON?, in object: [String: Any]) -> [String: Any]? {
        guard let first = keyPath.first else {
            return nil
        }
        var members: [String: Any] = object
        if keyPath.count == 1 {
            if let value {
                members[first] = value.foundation()
            } else {
                members[first] = nil
            }
            return members
        }
        guard let inner = members[first] as? [String: Any] else {
            return nil
        }
        guard let changed = setting(Array(keyPath.dropFirst()), to: value, in: inner) else {
            return nil
        }
        members[first] = changed
        return members
    }

    static func moved(_ op: UndoOp, from item: UndoItem, direction: UndoDirection) -> UndoItem? {
        guard let data = item.data, let keyPath = op.keyPath,
              let object = topLevel(of: data), let tree = UndoJSON.from(foundation: object) else {
            return nil
        }
        let wanted: UndoJSON? = direction == .backward ? op.valueBefore : op.valueAfter
        guard let expected = setting(keyPath, to: wanted, in: tree),
              let changedObject = setting(keyPath, to: wanted, in: object) else {
            return nil
        }
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard var written = try? JSONSerialization.data(withJSONObject: changedObject, options: options) else {
            return nil
        }
        if data.last == 0x0A {
            written.append(0x0A)
        }
        // Read back: exactly the file with that one member changed, or no
        // write at all.
        guard let readBack = topLevel(of: written), let readTree = UndoJSON.from(foundation: readBack),
              readTree == expected else {
            return nil
        }
        return .file(written)
    }
}

// MARK: - Folders: createTree, removeTree, and a folder's move

/// A folder's listing: what `createTree`, `removeTree` and a folder's `move`
/// record by its SHA-256 (`listingSha`).
///
/// The listing is UTF-8 text, one line per item inside the folder (the
/// folder itself is not listed), each ending in a line feed, in the order of
/// their paths' UTF-8 bytes: `folder <path>` for a folder, `file <sha256>
/// <path>` for a file, where path is relative to the folder, with forward
/// slashes, spelled as the file system gives it. An empty folder's listing
/// is empty. Anything else inside (a link, an item that cannot be read)
/// means the folder has no listing: it is changed since, never guessed at
/// (`undo.listingCases`).
nonisolated struct UndoTreeListing: Equatable, Sendable {

    // MARK: - Stored properties

    struct File: Equatable, Sendable {
        let path: String
        let sha: String
    }

    let folders: [String]

    let files: [File]

    // MARK: - Computed properties

    /// The listing's text, in its one order.
    var text: String {
        var entries: [(path: String, line: String)] = []
        for folder in folders {
            entries.append((path: folder, line: "folder " + folder + "\n"))
        }
        for file in files {
            entries.append((path: file.path, line: "file " + file.sha + " " + file.path + "\n"))
        }
        entries.sort { first, second in
            return first.path.utf8.lexicographicallyPrecedes(second.path.utf8)
        }
        var result: String = ""
        for entry in entries {
            result += entry.line
        }
        return result
    }

    var data: Data {
        return Data(text.utf8)
    }

    var sha: String {
        return UndoHash.sha256(of: data)
    }

    // MARK: - Functions

    /// A listing read back from its blob, or nil.
    static func parse(_ data: Data) -> UndoTreeListing? {
        guard let text = UndoText.decode(data) else {
            return nil
        }
        var folders: [String] = []
        var files: [File] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("folder ") {
                let path: String = String(line.dropFirst("folder ".count))
                if !UndoOp.isSafeRelativePath(path) {
                    return nil
                }
                folders.append(path)
            } else if line.hasPrefix("file ") {
                let rest: Substring = line.dropFirst("file ".count)
                guard let space = rest.firstIndex(of: " ") else {
                    return nil
                }
                let sha: String = String(rest[rest.startIndex..<space])
                let path: String = String(rest[rest.index(after: space)...])
                if !UndoOp.isBlobName(sha) || !UndoOp.isSafeRelativePath(path) {
                    return nil
                }
                files.append(File(path: path, sha: sha))
            } else {
                return nil
            }
        }
        let listing: UndoTreeListing = UndoTreeListing(folders: folders, files: files)
        if listing.data != data {
            return nil
        }
        return listing
    }
}

/// What is at a folder's place now.
nonisolated enum UndoTreeReading: Equatable, Sendable {
    case absent
    /// A file, a link, or a folder holding something that cannot be listed.
    case notATree
    case tree(UndoTreeListing, contents: [String: Data])

    // MARK: - Computed properties

    /// The listing's hash, when there is a folder that can be listed.
    var listingSha: String? {
        if case .tree(let listing, _) = self {
            return listing.sha
        }
        return nil
    }

    // MARK: - Functions

    static func read(at url: URL) -> UndoTreeReading {
        var information: stat = stat()
        let result: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &information)
        }
        if result != 0 {
            if errno == ENOENT || errno == ENOTDIR {
                return .absent
            }
            return .notATree
        }
        if (information.st_mode & S_IFMT) != S_IFDIR {
            return .notATree
        }
        var folders: [String] = []
        var files: [UndoTreeListing.File] = []
        var contents: [String: Data] = [:]
        if !walk(url, prefix: "", folders: &folders, files: &files, contents: &contents) {
            return .notATree
        }
        return .tree(UndoTreeListing(folders: folders, files: files), contents: contents)
    }

    private static func walk(
        _ folder: URL,
        prefix: String,
        folders: inout [String],
        files: inout [UndoTreeListing.File],
        contents: inout [String: Data]
    ) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return false
        }
        for name in names {
            let url: URL = folder.appendingPathComponent(name)
            let path: String = prefix.isEmpty ? name : prefix + "/" + name
            var information: stat = stat()
            let found: Int32 = url.withUnsafeFileSystemRepresentation { fileSystemPath in
                guard let fileSystemPath else {
                    return -1
                }
                return lstat(fileSystemPath, &information)
            }
            if found != 0 {
                return false
            }
            let type: mode_t = information.st_mode & S_IFMT
            if type == S_IFDIR {
                folders.append(path)
                if !walk(url, prefix: path, folders: &folders, files: &files, contents: &contents) {
                    return false
                }
            } else if type == S_IFREG {
                guard let data = try? Data(contentsOf: url) else {
                    return false
                }
                files.append(UndoTreeListing.File(path: path, sha: UndoHash.sha256(of: data)))
                contents[path] = data
            } else {
                return false
            }
        }
        return true
    }

    /// Makes the folder a listing describes at a NEW place, with every
    /// file's content as given. False, with whatever it made removed, when
    /// a file's content is missing or a write fails.
    static func make(_ listing: UndoTreeListing, contents: [String: Data], at url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            return false
        }
        var made: Bool = true
        var sortedFolders: [String] = listing.folders
        sortedFolders.sort { first, second in
            return first.utf8.lexicographicallyPrecedes(second.utf8)
        }
        for folder in sortedFolders {
            if (try? FileManager.default.createDirectory(
                at: url.appendingPathComponent(folder), withIntermediateDirectories: true
            )) == nil {
                made = false
            }
        }
        for file in listing.files where made {
            guard let data = contents[file.path], UndoHash.sha256(of: data) == file.sha else {
                made = false
                break
            }
            let fileURL: URL = url.appendingPathComponent(file.path)
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try UndoFiles.writeDurably(data, to: fileURL)
            } catch {
                made = false
            }
        }
        if !made {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        UndoFiles.syncFolder(url)
        return true
    }
}

// MARK: - Checking a whole op against the disk

nonisolated extension UndoCheck {

    // MARK: - Functions

    /// Where a move, a tree or an external op stands now. Each is judged as
    /// a whole against what is there, on its own (`UndoStep.wholeOpsStandAlone`).
    ///
    /// A MOVE is judged as a PAIR, never by one place alone (#897 piece B,
    /// seam 1): the place it left (`from`) free and the place it went (`to`)
    /// holding its content is as the step left it; `from` holding the content
    /// and `to` free is as it was before; anything else (both full, both
    /// free, either holding something else) is a change since, so an undo
    /// leaves BOTH where they are and takes nothing back, and never deletes
    /// the destination alone.
    static func wholeState(of op: UndoOp, root: URL, places: UndoExternalPlaces) -> UndoOpState {
        switch op.knownKind {
        case .move:
            guard let from = op.from, let to = op.to else {
                return .neither
            }
            let atFrom: UndoMoveSide = UndoMoveSide.read(op, at: root.appendingPathComponent(from))
            let atTo: UndoMoveSide = UndoMoveSide.read(op, at: root.appendingPathComponent(to))
            if atFrom == .free && atTo == .holdsTheContent {
                return .after
            }
            if atFrom == .holdsTheContent && atTo == .free {
                return .before
            }
            return .neither
        case .createTree, .removeTree:
            guard let path = op.path, let listingSha = op.listingSha else {
                return .neither
            }
            let reading: UndoTreeReading = UndoTreeReading.read(at: root.appendingPathComponent(path))
            let present: Bool
            switch reading {
            case .absent:
                present = false
            case .notATree:
                return .neither
            case .tree(let listing, _):
                if listing.sha != listingSha {
                    return .neither
                }
                present = true
            }
            if op.knownKind == .createTree {
                return present ? .after : .before
            }
            return present ? .before : .after
        case .external:
            guard let target = op.target else {
                return .neither
            }
            let found: UndoExternalReading = places.read(target)
            if UndoCheck.externalMatches(found, op.valueBefore) {
                return .before
            }
            if UndoCheck.externalMatches(found, op.valueAfter) {
                return .after
            }
            return .neither
        default:
            return .neither
        }
    }

    static func externalMatches(_ found: UndoExternalReading, _ expected: UndoJSON?) -> Bool {
        switch found {
        case .notSet:
            return expected == nil
        case .value(let value):
            guard let expected else {
                return false
            }
            return value == expected
        case .cannotTell:
            return false
        }
    }
}

/// One side of a move, judged by content.
nonisolated enum UndoMoveSide: Equatable, Sendable {
    /// Nothing there.
    case free
    /// The very file (by its SHA-256) or folder (by its listing) moved.
    case holdsTheContent
    /// Something else.
    case holdsSomethingElse

    // MARK: - Functions

    static func read(_ op: UndoOp, at url: URL) -> UndoMoveSide {
        if let sha = op.sha {
            switch UndoItem.read(at: url) {
            case .absent:
                return .free
            case .file(let data):
                return UndoHash.sha256(of: data) == sha ? .holdsTheContent : .holdsSomethingElse
            case .notAFile:
                return .holdsSomethingElse
            }
        }
        switch UndoTreeReading.read(at: url) {
        case .absent:
            return .free
        case .notATree:
            return .holdsSomethingElse
        case .tree(let listing, _):
            return listing.sha == op.listingSha ? .holdsTheContent : .holdsSomethingElse
        }
    }
}

// MARK: - external

/// What an `external` target holds now.
nonisolated enum UndoExternalReading: Equatable, Sendable {
    case notSet
    case value(UndoJSON)
    /// Something JSON cannot hold, or a target that cannot be read.
    case cannotTell
}

/// The places outside every working folder an `external` op can change.
/// `preference:<name>` is one of the app's own preferences. A test passes a
/// place of its own; the app passes `UndoAppPreferences`.
nonisolated protocol UndoExternalPlaces: Sendable {
    func read(_ target: String) -> UndoExternalReading
    /// Sets the target (nil: removes it). False when it could not.
    func write(_ target: String, _ value: UndoJSON?) -> Bool
}

/// The app's own preferences (`PlantoirDefaults.shared`, the one store, which follows `--state-dir`), named
/// `preference:<key>`.
nonisolated struct UndoAppPreferences: UndoExternalPlaces {

    // MARK: - Functions

    static func preferenceKey(_ target: String) -> String? {
        let prefix: String = "preference:"
        if !target.hasPrefix(prefix) {
            return nil
        }
        let key: String = String(target.dropFirst(prefix.count))
        return key.isEmpty ? nil : key
    }

    func read(_ target: String) -> UndoExternalReading {
        guard let key = UndoAppPreferences.preferenceKey(target) else {
            return .cannotTell
        }
        guard let stored = PlantoirDefaults.shared.object(forKey: key) else {
            return .notSet
        }
        guard let value = UndoJSON.from(foundation: stored) else {
            return .cannotTell
        }
        return .value(value)
    }

    func write(_ target: String, _ value: UndoJSON?) -> Bool {
        guard let key = UndoAppPreferences.preferenceKey(target) else {
            return false
        }
        guard let value else {
            PlantoirDefaults.shared.removeObject(forKey: key)
            return true
        }
        if !PropertyListSerialization.propertyList(value.foundation(), isValidFor: .binary) {
            // A JSON null, or an object holding one: no preference holds it.
            return false
        }
        PlantoirDefaults.shared.set(value.foundation(), forKey: key)
        return true
    }
}

// MARK: - recompute

/// Who re-derives each `recompute` maintainer's file after an undo, a redo
/// or a recovery settles a step (`undo.laterPieces.U2`).
///
/// A runner is REGISTERED rather than called directly because the one
/// maintainer this version knows, `sectionFrontPage`, is the app's own
/// front-page rule (`SectionIndexPointer.repointIndex`, on the main actor:
/// `UndoSectionFrontPage.rederive`), while the list is moved off the main
/// actor. Until the app registers its runner (U7, with the switch), a
/// step holding a `recompute` is NOT AVAILABLE to Undo or Redo: it is never
/// undone with its re-derivation skipped. Recovery settles such a step's
/// content all the same (its files must never stay half done) and re-derives
/// whatever runner is registered; re-deriving is idempotent.
nonisolated enum UndoMaintainers {

    // MARK: - Stored properties

    typealias Runner = @Sendable (UndoOp, URL) -> Void

    nonisolated(unsafe) private static var runners: [String: Runner] = [:]

    private static let guardLock: NSLock = NSLock()

    // MARK: - Functions

    static func register(_ maintainer: String, _ runner: @escaping Runner) {
        guardLock.lock()
        runners[maintainer] = runner
        guardLock.unlock()
    }

    static func forget(_ maintainer: String) {
        guardLock.lock()
        runners[maintainer] = nil
        guardLock.unlock()
    }

    static func runner(for maintainer: String) -> Runner? {
        guardLock.lock()
        defer {
            guardLock.unlock()
        }
        return runners[maintainer]
    }

    /// Whether every one of these ops has a runner.
    static func canRun(_ ops: [UndoOp]) -> Bool {
        for op in ops where op.knownKind == .recompute {
            guard let maintainer = op.maintainer, runner(for: maintainer) != nil else {
                return false
            }
        }
        return true
    }

    /// Runs the runner of every `recompute` op among these, in order.
    static func rederive(_ ops: [UndoOp], root: URL) {
        for op in ops where op.knownKind == .recompute {
            if let maintainer = op.maintainer, let run = runner(for: maintainer) {
                run(op, root)
            }
        }
    }
}
