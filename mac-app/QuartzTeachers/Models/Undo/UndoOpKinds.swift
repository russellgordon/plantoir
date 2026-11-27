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
        // A whole number beyond 2^53, in the file or in the record, cannot be
        // compared exactly through a double (2^53 + 1 reads as 2^53): cannot
        // tell, never a guess either way (the third hard review, LOW 5).
        if case .value(let value) = found, !UndoJSONBytes.isExact(value) {
            return .cannotTell
        }
        for recorded in [op.valueBefore, op.valueAfter] {
            if let recorded, !UndoJSONBytes.isExact(recorded) {
                return .cannotTell
            }
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

    /// Moves the member by changing ONLY its bytes: the value's bytes are
    /// replaced (or the member's are removed, or a member is added after the
    /// last one, spaced as that one is); every other byte of the file stays
    /// as it was (the hard review of U2b, LOW a: a rewrite changed 0.1 to
    /// 0.10000000000000001, key order, spellings, and dropped a duplicate).
    /// Refused (nil, which the plan reads as changed since) when that cannot
    /// be done safely: the file not UTF-8 or not one JSON object, a key
    /// written twice in any object on the path, a part on the way missing
    /// when a value must be set. The result must read back as exactly the
    /// file with that one member changed.
    static func moved(_ op: UndoOp, from item: UndoItem, direction: UndoDirection) -> UndoItem? {
        guard let data = item.data, let keyPath = op.keyPath, !keyPath.isEmpty,
              let object = topLevel(of: data), let tree = UndoJSON.from(foundation: object) else {
            return nil
        }
        let wanted: UndoJSON? = direction == .backward ? op.valueBefore : op.valueAfter
        guard let expected = setting(keyPath, to: wanted, in: tree) else {
            return nil
        }
        let bytes: [UInt8] = Array(data)
        guard let place = UndoJSONBytes.locate(keyPath, in: bytes) else {
            return nil
        }
        var result: [UInt8] = []
        switch (place, wanted) {
        case (.member(let member), .some(let value)):
            guard let spelled = UndoJSONBytes.spell(value) else {
                return nil
            }
            result = Array(bytes[0..<member.valueStart]) + spelled + Array(bytes[member.valueEnd..<bytes.count])
        case (.member(let member), .none):
            result = Array(bytes[0..<member.removeStart]) + Array(bytes[member.removeEnd..<bytes.count])
        case (.missing(let gap), .some(let value)):
            guard let spelled = UndoJSONBytes.spell(value), let name = UndoJSONBytes.spell(.string(keyPath[keyPath.count - 1])) else {
                return nil
            }
            let inserted: [UInt8] = gap.lead + name + gap.colon + spelled
            result = Array(bytes[0..<gap.at]) + inserted + Array(bytes[gap.at..<bytes.count])
        case (.missing, .none):
            return item
        }
        let written: Data = Data(result)
        guard let readBack = topLevel(of: written), let readTree = UndoJSON.from(foundation: readBack),
              readTree == expected else {
            return nil
        }
        return .file(written)
    }
}

/// Where a member is in a JSON file's bytes, found with a scanner of its own
/// so nothing else of the file is ever re-spelled (`UndoJSONMember.moved`).
nonisolated enum UndoJSONBytes {

    // MARK: - Stored properties

    struct Member: Equatable {
        /// Where the member's own bytes go from, when it is taken out:
        /// with the comma before it, or the one after it.
        let removeStart: Int
        let removeEnd: Int
        let valueStart: Int
        let valueEnd: Int
    }

    struct Gap: Equatable {
        /// Where a new member's bytes go.
        let at: Int
        /// What comes before the new member's name: a comma and the space
        /// the last member had before it, or nothing in an empty object.
        let lead: [UInt8]
        /// What goes between its name and its value, as the last member had.
        let colon: [UInt8]
    }

    enum Place: Equatable {
        case member(Member)
        case missing(Gap)
    }

    /// One member as scanned: where its name starts and its value ends, and
    /// the bytes between its name and value.
    struct Scanned {
        let name: String
        let nameStart: Int
        let colonBytes: [UInt8]
        let valueStart: Int
        let valueEnd: Int
        let leadBytes: [UInt8]
    }

    // MARK: - Functions

    static func isSpace(_ byte: UInt8) -> Bool {
        return byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    static func skipSpace(_ bytes: [UInt8], _ index: Int) -> Int {
        var at: Int = index
        while at < bytes.count && isSpace(bytes[at]) {
            at += 1
        }
        return at
    }

    /// The end of the string starting at `index` (its opening quote), and
    /// its text, or nil.
    static func scanString(_ bytes: [UInt8], _ index: Int) -> (end: Int, text: String)? {
        guard index < bytes.count, bytes[index] == 0x22 else {
            return nil
        }
        var at: Int = index + 1
        while at < bytes.count {
            if bytes[at] == 0x5C {
                at += 2
                continue
            }
            if bytes[at] == 0x22 {
                let raw: Data = Data(bytes[index...at])
                guard let text = (try? JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed])) as? String else {
                    return nil
                }
                return (end: at + 1, text: text)
            }
            at += 1
        }
        return nil
    }

    /// The end of the value starting at `index`, or nil.
    static func scanValue(_ bytes: [UInt8], _ index: Int) -> Int? {
        guard index < bytes.count else {
            return nil
        }
        let first: UInt8 = bytes[index]
        if first == 0x22 {
            return scanString(bytes, index)?.end
        }
        if first == 0x7B || first == 0x5B {
            // An object or an array: to its matching close, strings skipped.
            var depth: Int = 0
            var at: Int = index
            while at < bytes.count {
                let byte: UInt8 = bytes[at]
                if byte == 0x22 {
                    guard let end = scanString(bytes, at)?.end else {
                        return nil
                    }
                    at = end
                    continue
                }
                if byte == 0x7B || byte == 0x5B {
                    depth += 1
                } else if byte == 0x7D || byte == 0x5D {
                    depth -= 1
                    if depth == 0 {
                        return at + 1
                    }
                }
                at += 1
            }
            return nil
        }
        // A number, true, false or null: to the next delimiter.
        var at: Int = index
        while at < bytes.count {
            let byte: UInt8 = bytes[at]
            if isSpace(byte) || byte == 0x2C || byte == 0x7D || byte == 0x5D {
                break
            }
            at += 1
        }
        return at > index ? at : nil
    }

    /// Every member of the object starting at `index` (its `{`), and where
    /// its `}` is, or nil.
    static func scanObject(_ bytes: [UInt8], _ index: Int) -> (members: [Scanned], close: Int)? {
        guard index < bytes.count, bytes[index] == 0x7B else {
            return nil
        }
        var members: [Scanned] = []
        var at: Int = index + 1
        var leadStart: Int = at
        while true {
            at = skipSpace(bytes, at)
            guard at < bytes.count else {
                return nil
            }
            if bytes[at] == 0x7D {
                return (members: members, close: at)
            }
            let lead: [UInt8] = Array(bytes[leadStart..<at])
            guard let name = scanString(bytes, at) else {
                return nil
            }
            var colon: Int = skipSpace(bytes, name.end)
            guard colon < bytes.count, bytes[colon] == 0x3A else {
                return nil
            }
            colon += 1
            let valueStart: Int = skipSpace(bytes, colon)
            guard let valueEnd = scanValue(bytes, valueStart) else {
                return nil
            }
            members.append(Scanned(
                name: name.text, nameStart: at, colonBytes: Array(bytes[name.end..<valueStart]),
                valueStart: valueStart, valueEnd: valueEnd, leadBytes: lead
            ))
            at = skipSpace(bytes, valueEnd)
            guard at < bytes.count else {
                return nil
            }
            if bytes[at] == 0x2C {
                at += 1
                leadStart = at
                continue
            }
            if bytes[at] == 0x7D {
                return (members: members, close: at)
            }
            return nil
        }
    }

    /// Where the member at the key path is, or the gap where it would go,
    /// or nil when it cannot be found safely (a key twice on the path, a
    /// part on the way missing or not an object, bytes that do not scan).
    static func locate(_ keyPath: [String], in bytes: [UInt8]) -> Place? {
        var objectStart: Int = skipSpace(bytes, 0)
        var depth: Int = 0
        while depth < keyPath.count {
            guard let object = scanObject(bytes, objectStart) else {
                return nil
            }
            var found: [Scanned] = []
            for member in object.members where member.name == keyPath[depth] {
                found.append(member)
            }
            if found.count > 1 {
                // The key written twice on the path: never a guess at which.
                return nil
            }
            let isLast: Bool = depth == keyPath.count - 1
            guard let member = found.first else {
                if !isLast {
                    return nil
                }
                if let last = object.members.last {
                    return .missing(Gap(at: last.valueEnd, lead: [0x2C] + last.leadBytes, colon: last.colonBytes))
                }
                return .missing(Gap(at: object.close, lead: [], colon: Array(": ".utf8)))
            }
            if isLast {
                // Taken out with the comma after it, or else the one before.
                var index: Int = 0
                for (position, candidate) in object.members.enumerated() where candidate.nameStart == member.nameStart {
                    index = position
                }
                if index + 1 < object.members.count {
                    let next: Scanned = object.members[index + 1]
                    return .member(Member(removeStart: member.nameStart, removeEnd: next.nameStart, valueStart: member.valueStart, valueEnd: member.valueEnd))
                }
                if index > 0 {
                    let previous: Scanned = object.members[index - 1]
                    return .member(Member(removeStart: previous.valueEnd, removeEnd: member.valueEnd, valueStart: member.valueStart, valueEnd: member.valueEnd))
                }
                let inside: Int = skipSpace(bytes, objectStart + 1)
                return .member(Member(removeStart: inside, removeEnd: member.valueEnd, valueStart: member.valueStart, valueEnd: member.valueEnd))
            }
            objectStart = member.valueStart
            depth += 1
        }
        return nil
    }

    /// Whether every number in a value is one a double holds exactly as
    /// written: no whole number of 2^53 or more (the second hard review of U2b).
    static func isExact(_ value: UndoJSON) -> Bool {
        switch value {
        case .number(let number):
            return !(number.rounded() == number && abs(number) >= 9_007_199_254_740_992)
        case .array(let list):
            for element in list where !isExact(element) {
                return false
            }
            return true
        case .object(let members):
            for (_, element) in members where !isExact(element) {
                return false
            }
            return true
        default:
            return true
        }
    }

    /// A value's bytes, written compactly with keys sorted and slashes as
    /// they are: only the new value is ever spelled by the app.
    ///
    /// Nil for a whole number beyond 2^53, which a double cannot hold
    /// exactly: such a value is refused rather than written approximately.
    static func spell(_ value: UndoJSON) -> [UInt8]? {
        if !UndoJSONBytes.isExact(value) {
            return nil
        }
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        guard let data = try? JSONSerialization.data(withJSONObject: value.foundation(), options: options) else {
            return nil
        }
        return Array(data)
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

    /// Each symbolic link inside, by its path, with the SHA-256 of the
    /// bytes it holds (its target as written, never what it leads to): a
    /// link is listed, never followed (U4b part four's review, L4: a folder
    /// holding a link is renamed as before, the link moved as a link). A
    /// listing with a link is never made from its blobs (`make`).
    var links: [File] = []

    /// The one name a listing passes over, wherever it is: the Finder's
    /// `.DS_Store`.
    static let ignoredName: String = ".DS_Store"

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
        for link in links {
            entries.append((path: link.path, line: "link " + link.sha + " " + link.path + "\n"))
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
        var links: [File] = []
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
            } else if line.hasPrefix("link ") {
                let rest: Substring = line.dropFirst("link ".count)
                guard let space = rest.firstIndex(of: " ") else {
                    return nil
                }
                let sha: String = String(rest[rest.startIndex..<space])
                let path: String = String(rest[rest.index(after: space)...])
                if !UndoOp.isBlobName(sha) || !UndoOp.isSafeRelativePath(path) {
                    return nil
                }
                links.append(File(path: path, sha: sha))
            } else {
                return nil
            }
        }
        let listing: UndoTreeListing = UndoTreeListing(folders: folders, files: files, links: links)
        if listing.data != data {
            return nil
        }
        return listing
    }
}

/// What is at a folder's place now.
nonisolated enum UndoTreeReading: Equatable, Sendable {
    case absent
    /// A file, a link, or a folder holding a link.
    case notATree
    /// Something there could not be read or listed just now: cannot tell.
    case cannotRead
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

    /// `keepingContents` keeps every file's bytes (a test, or a caller that
    /// will store them); otherwise each file is hashed as it is read, a
    /// megabyte at a time, and nothing is held (the hard review of U2b,
    /// LOW b: a check read the whole tree into memory twice).
    static func read(at url: URL, keepingContents: Bool = false) -> UndoTreeReading {
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
            return .cannotRead
        }
        if (information.st_mode & S_IFMT) != S_IFDIR {
            return .notATree
        }
        var folders: [String] = []
        var files: [UndoTreeListing.File] = []
        var links: [UndoTreeListing.File] = []
        var contents: [String: Data] = [:]
        var couldNotRead: Bool = false
        if !walk(url, prefix: "", keepingContents: keepingContents, folders: &folders, files: &files, links: &links, contents: &contents, couldNotRead: &couldNotRead) {
            return couldNotRead ? .cannotRead : .notATree
        }
        return .tree(UndoTreeListing(folders: folders, files: files, links: links), contents: contents)
    }

    private static func walk(
        _ folder: URL,
        prefix: String,
        keepingContents: Bool,
        folders: inout [String],
        files: inout [UndoTreeListing.File],
        links: inout [UndoTreeListing.File],
        contents: inout [String: Data],
        couldNotRead: inout Bool
    ) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            couldNotRead = true
            return false
        }
        for name in names {
            // The Finder's own record of a window it opened is not the
            // teacher's work: a folder looked at in the Finder must not
            // become one Undo cannot take back (the hard review of U2b,
            // LOW b). Never listed, and taken out with the folder.
            if name == UndoTreeListing.ignoredName {
                continue
            }
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
                couldNotRead = true
                return false
            }
            let type: mode_t = information.st_mode & S_IFMT
            if type == S_IFDIR {
                folders.append(path)
                if !walk(url, prefix: path, keepingContents: keepingContents, folders: &folders, files: &files, links: &links, contents: &contents, couldNotRead: &couldNotRead) {
                    return false
                }
            } else if type == S_IFREG {
                if keepingContents {
                    guard let data = try? Data(contentsOf: url) else {
                        couldNotRead = true
                        return false
                    }
                    files.append(UndoTreeListing.File(path: path, sha: UndoHash.sha256(of: data)))
                    contents[path] = data
                } else {
                    guard let sha = UndoHash.sha256(ofFileAt: url) else {
                        couldNotRead = true
                        return false
                    }
                    files.append(UndoTreeListing.File(path: path, sha: sha))
                }
            } else if type == S_IFLNK {
                // Listed by what it holds, never followed.
                guard let sha = linkSha(at: url) else {
                    couldNotRead = true
                    return false
                }
                links.append(UndoTreeListing.File(path: path, sha: sha))
            } else {
                return false
            }
        }
        return true
    }

    /// The bytes a symbolic link holds, read with `readlink`: the link
    /// itself, never what it leads to. Nil when it cannot be read.
    static func linkTarget(at url: URL) -> Data? {
        var buffer: [UInt8] = [UInt8](repeating: 0, count: Int(PATH_MAX) + 1)
        let count: Int = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return readlink(path, &buffer, buffer.count)
        }
        if count < 0 {
            return nil
        }
        return Data(buffer[0..<count])
    }

    /// A link's `linkSha` (`opKinds.move`, U4b2-14): the SHA-256 of the
    /// bytes it holds (`linkTarget`), never followed. Nil when it cannot be
    /// read. No teacher action calls this now (Rename folder refuses a link;
    /// #1055 M6 removes it). The one rule the
    /// door judges by (`UndoMoveSide.readLink`) and a folder's listing
    /// lists a link inside it by (`link` lines).
    static func linkSha(at url: URL) -> String? {
        guard let target = linkTarget(at: url) else {
            return nil
        }
        return UndoHash.sha256(of: target)
    }

    /// Makes the folder a listing describes at a NEW place, with every
    /// file's content as given. False, with whatever it made removed, when
    /// a file's content is missing or a write fails. A listing holding a
    /// link is never made: a link is moved, never written from a blob.
    static func make(_ listing: UndoTreeListing, contents: [String: Data], at url: URL) -> Bool {
        if !listing.links.isEmpty {
            return false
        }
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
    ///
    /// `overridingTo` and `overridingFrom` give, for paths inside the place
    /// on that side, what they would hold once the step's own edits there
    /// are taken back, and `.absent` for the step's own staged files and
    /// kept originals (U4b, opKinds.wholeOps): see `UndoMoveSide.read`.
    ///
    /// `toIsHandedOver` is true for a file's or a link's move that FILLS a
    /// place an earlier change of the same plan leaves (U4b3 door-1, a
    /// handed-over place): its `to` is judged free, whatever stands there
    /// now, because the leaver is swapped out before it. A flag of its own,
    /// never an `overridingTo` entry: those name paths inside a moved
    /// folder and what U4b's carried edits leave there, and an empty item
    /// at "" would read as a carried edit's file at the move's own place.
    ///
    /// `fromIsHandedOver` is its other half, going back (U4b3 door-2): a
    /// file's or a link's move that LEFT a handed-over place, taken back
    /// after the op that filled the place has been taken back by the same
    /// plan. Its `from` is judged free, whatever stands there now, because
    /// the filler's taking-back is swapped in before it.
    static func wholeState(
        of op: UndoOp, root: URL, places: UndoExternalPlaces,
        overridingTo: [String: UndoItem] = [:], overridingFrom: [String: UndoItem] = [:],
        toIsHandedOver: Bool = false, fromIsHandedOver: Bool = false
    ) -> UndoOpState {
        switch op.knownKind {
        case .move, .moveApart, .setAside:
            guard let from = op.from, let to = op.to else {
                return .neither
            }
            if op.isCaseOnlyMove, let spelled = UndoMoveSide.spellingListed(
                from: root.appendingPathComponent(from), to: root.appendingPathComponent(to)
            ) {
                // One place, two spellings (U4b): judged by the spelling its
                // folder lists, holding the content.
                switch spelled {
                case .cannotRead:
                    return .cannotTell
                case .another:
                    return .neither
                case .to, .from:
                    let side: UndoMoveSide = spelled == .to
                        ? UndoMoveSide.read(op, at: root.appendingPathComponent(to), isAtFrom: false, overriding: overridingTo)
                        : UndoMoveSide.read(op, at: root.appendingPathComponent(from), isAtFrom: true, overriding: overridingFrom)
                    if side == .cannotRead {
                        return .cannotTell
                    }
                    if side != .holdsTheContent {
                        return .neither
                    }
                    return spelled == .to ? .after : .before
                }
            }
            var atFrom: UndoMoveSide = .free
            if !fromIsHandedOver {
                atFrom = UndoMoveSide.read(op, at: root.appendingPathComponent(from), isAtFrom: true, overriding: overridingFrom)
            }
            var atTo: UndoMoveSide = .free
            if !toIsHandedOver {
                atTo = UndoMoveSide.read(op, at: root.appendingPathComponent(to), isAtFrom: false, overriding: overridingTo)
            }
            if atFrom == .cannotRead || atTo == .cannotRead {
                return .cannotTell
            }
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
            case .cannotRead:
                return .cannotTell
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
    /// Something there that could not be read just now.
    case cannotRead

    // MARK: - Functions

    /// `overriding` gives, for a path inside the place ("" for a file
    /// moved itself), what it would hold once the step's own edits there are
    /// taken back (U4b, opKinds.wholeOps): `.absent` leaves it out of the
    /// listing. A swap passes its own kept originals inside a moved folder
    /// as `.absent`, so the move's pair is judged without them.
    /// U4b, a capitalisation-only move: which spelling the folder holding
    /// `from` and `to` lists, when the two are ONE item there (a
    /// case-insensitive volume: the same device and file number at both
    /// spellings). Nil when they are not one item (a case-sensitive volume,
    /// or nothing there), so the move is judged as any move is.
    static func spellingListed(from: URL, to: URL) -> UndoCaseOnlySpelling? {
        var atFrom: stat = stat()
        var atTo: stat = stat()
        let foundFrom: Int32 = from.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &atFrom)
        }
        let foundTo: Int32 = to.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &atTo)
        }
        if foundFrom != 0 || foundTo != 0 || atFrom.st_dev != atTo.st_dev || atFrom.st_ino != atTo.st_ino {
            return nil
        }
        let folder: URL = from.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return .cannotRead
        }
        let wanted: String = from.lastPathComponent.lowercased()
        for name in names where name.lowercased() == wanted {
            if name == to.lastPathComponent {
                return .to
            }
            if name == from.lastPathComponent {
                return .from
            }
            return .another
        }
        return .another
    }

    /// `isAtFrom` names the side read: a relinking move (U4b3 relink-1)
    /// holds its `linkShaBefore` text at `from` and its `linkShaAfter`
    /// text at `to`; every other move holds the same content on both.
    static func read(_ op: UndoOp, at url: URL, isAtFrom: Bool = true, overriding: [String: UndoItem] = [:]) -> UndoMoveSide {
        return readNamingFoldersLeftOut(op, at: url, isAtFrom: isAtFrom, overriding: overriding).side
    }

    /// `read`, naming too each folder inside the place that was left out
    /// of the judgement (U4b2-10), deepest first, as the disk spells it.
    static func readNamingFoldersLeftOut(
        _ op: UndoOp, at url: URL, isAtFrom: Bool = true, overriding: [String: UndoItem] = [:]
    ) -> (side: UndoMoveSide, foldersLeftOut: [String]) {
        if op.isALinksMove {
            // U4b2-14: a link is the item; nothing inside it is the move's.
            // Each side by its own text (U4b3 relink-1).
            guard let linkSha = op.linkText(isAtFrom: isAtFrom) else {
                return (side: .holdsSomethingElse, foldersLeftOut: [])
            }
            return (side: UndoMoveSide.readLink(at: url, linkSha: linkSha), foldersLeftOut: [])
        }
        if let sha = op.sha {
            var item: UndoItem = UndoItem.read(at: url)
            if let given = overriding[""], item != .absent {
                item = given
            }
            switch item {
            case .absent:
                return (side: .free, foldersLeftOut: [])
            case .file(let data):
                return (side: UndoHash.sha256(of: data) == sha ? .holdsTheContent : .holdsSomethingElse, foldersLeftOut: [])
            case .notAFile:
                return (side: .holdsSomethingElse, foldersLeftOut: [])
            case .unreadable:
                return (side: .cannotRead, foldersLeftOut: [])
            }
        }
        switch UndoTreeReading.read(at: url) {
        case .absent:
            return (side: .free, foldersLeftOut: [])
        case .notATree:
            return (side: .holdsSomethingElse, foldersLeftOut: [])
        case .cannotRead:
            return (side: .cannotRead, foldersLeftOut: [])
        case .tree(let listing, _):
            if overriding.isEmpty {
                return (side: listing.sha == op.listingSha ? .holdsTheContent : .holdsSomethingElse, foldersLeftOut: [])
            }
            // An override names a file inside the place as a step names it;
            // the listing names it as the disk spells it. The two are matched
            // by the one comparison, `UndoOp.partInside`, without regard to
            // case, and the file keeps the disk's spelling (review 1 of
            // U4b2-9, L1).
            var files: [UndoTreeListing.File] = []
            var matched: Set<String> = []
            var filesLeftOut: [String] = []
            for file in listing.files {
                var given: UndoItem? = nil
                for (path, item) in overriding where UndoOp.partInside(path, of: file.path) == "" {
                    given = item
                    matched.insert(path)
                }
                guard let given else {
                    files.append(file)
                    continue
                }
                switch given {
                case .absent:
                    filesLeftOut.append(file.path)
                    continue
                case .file(let data):
                    files.append(UndoTreeListing.File(path: file.path, sha: UndoHash.sha256(of: data)))
                case .notAFile, .unreadable:
                    return (side: .holdsSomethingElse, foldersLeftOut: [])
                }
            }
            for (path, given) in overriding where !matched.contains(path) {
                switch given {
                case .absent:
                    continue
                case .file(let data):
                    files.append(UndoTreeListing.File(path: path, sha: UndoHash.sha256(of: data)))
                case .notAFile, .unreadable:
                    return (side: .holdsSomethingElse, foldersLeftOut: [])
                }
            }
            // U4b2-10: a folder that holds nothing but files left out (and
            // folders so left out) may be one the step's edits made for
            // those files, or one of the content's own that was empty. Each
            // is decided on its own (review 1 of U4b2-10, MEDIUM 1): see
            // `foldersTheContentLacks`.
            let candidates: [String] = UndoMoveSide.foldersHoldingOnly(filesLeftOut, in: listing, keeping: files)
            if let foldersLeftOut = UndoMoveSide.foldersTheContentLacks(
                candidates, listing: listing, files: files, listingSha: op.listingSha
            ) {
                return (side: .holdsTheContent, foldersLeftOut: foldersLeftOut)
            }
            return (side: .holdsSomethingElse, foldersLeftOut: [])
        }
    }

    /// U4b2-14, opKinds.move: one side of a link's move, read with `lstat`
    /// and `readlink` on the link itself and never followed, so what it
    /// leads to (outside the working folder, or nowhere) is never read. The
    /// content is a link holding exactly the bytes `linkSha` hashes; a
    /// folder, a file or a link with another target is something else.
    static func readLink(at url: URL, linkSha: String) -> UndoMoveSide {
        var information: stat = stat()
        let found: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lstat(path, &information)
        }
        if found != 0 {
            if errno == ENOENT || errno == ENOTDIR {
                return .free
            }
            return .cannotRead
        }
        if (information.st_mode & S_IFMT) != S_IFLNK {
            return .holdsSomethingElse
        }
        guard let now = UndoTreeReading.linkSha(at: url) else {
            return .cannotRead
        }
        return now == linkSha ? .holdsTheContent : .holdsSomethingElse
    }

    /// Review 1 of U4b2-10: the most candidate folders decided one by one.
    static let mostFoldersDecidedOneByOne: Int = 8

    /// Which of `candidates` (deepest first) the moved content did not
    /// hold: the set that, left out of the listing with the files left out,
    /// makes it match `listingSha`, or nil when none does. The list keeps
    /// only the listing's hash, so the sets are tried, never read: each set
    /// that leaves a folder out only with every candidate below it (a
    /// folder the step made holds only folders it made), from all of them
    /// down to none, in one fixed order. Two sets give two listings, so at
    /// most one matches. Up to `mostFoldersDecidedOneByOne` candidates
    /// every such set is tried (at most 256 hashes); beyond that only all
    /// or none, so a step with more, some of them the content's own, is
    /// refused as changed since, which takes nothing back and loses nothing.
    static func foldersTheContentLacks(
        _ candidates: [String], listing: UndoTreeListing, files: [UndoTreeListing.File], listingSha: String?
    ) -> [String]? {
        var setsToTry: [[String]] = []
        if candidates.count <= UndoMoveSide.mostFoldersDecidedOneByOne {
            var mask: Int = (1 << candidates.count) - 1
            while mask >= 0 {
                var leftOut: [String] = []
                var position: Int = 0
                while position < candidates.count {
                    if mask & (1 << position) != 0 {
                        leftOut.append(candidates[position])
                    }
                    position += 1
                }
                if UndoMoveSide.leavesOutEveryCandidateBelow(leftOut, candidates: candidates) {
                    setsToTry.append(leftOut)
                }
                mask -= 1
            }
        } else {
            setsToTry = [candidates, []]
        }
        for leftOut in setsToTry {
            var foldersKept: [String] = []
            for folder in listing.folders where !leftOut.contains(folder) {
                foldersKept.append(folder)
            }
            let judged: UndoTreeListing = UndoTreeListing(folders: foldersKept, files: files, links: listing.links)
            if judged.sha == listingSha {
                return leftOut
            }
        }
        return nil
    }

    /// Whether every candidate below a folder of `leftOut` is in it too.
    static func leavesOutEveryCandidateBelow(_ leftOut: [String], candidates: [String]) -> Bool {
        for folder in leftOut {
            for other in candidates where UndoMoveSide.isBelow(other, folder) && !leftOut.contains(other) {
                return false
            }
        }
        return true
    }

    /// U4b2-10: every folder of `listing` that holds at least one of
    /// `filesLeftOut` and nothing else but folders that are themselves
    /// left out: no file of `files`, no link, no other folder (an empty
    /// folder the teacher put there keeps it, and every folder above it).
    /// Deepest first, as the listing spells them; inside by the one
    /// comparison, `UndoOp.partInside`.
    static func foldersHoldingOnly(
        _ filesLeftOut: [String], in listing: UndoTreeListing, keeping files: [UndoTreeListing.File]
    ) -> [String] {
        var deepestFirst: [String] = listing.folders
        deepestFirst.sort { first, second in
            let firstDepth: Int = first.split(separator: "/").count
            let secondDepth: Int = second.split(separator: "/").count
            if firstDepth != secondDepth {
                return firstDepth > secondDepth
            }
            return first < second
        }
        var leftOut: [String] = []
        for folder in deepestFirst {
            var holdsAFileLeftOut: Bool = false
            for path in filesLeftOut where UndoMoveSide.isBelow(path, folder) {
                holdsAFileLeftOut = true
            }
            if !holdsAFileLeftOut {
                continue
            }
            var holdsSomethingKept: Bool = false
            for file in files where UndoMoveSide.isBelow(file.path, folder) {
                holdsSomethingKept = true
            }
            for link in listing.links where UndoMoveSide.isBelow(link.path, folder) {
                holdsSomethingKept = true
            }
            for other in listing.folders where UndoMoveSide.isBelow(other, folder) && !leftOut.contains(other) {
                holdsSomethingKept = true
            }
            if !holdsSomethingKept {
                leftOut.append(folder)
            }
        }
        return leftOut
    }

    /// Whether `path` is inside `folder`, below it (never the folder
    /// itself), by the one comparison.
    static func isBelow(_ path: String, _ folder: String) -> Bool {
        guard let inside = UndoOp.partInside(folder, of: path) else {
            return false
        }
        return !inside.isEmpty
    }
}

// MARK: - Places inside the working folder

/// Whether a path a step names stays inside its working folder once every
/// link on the way is resolved: a path spelled inside that reaches outside
/// through a link is refused by the door (the hard review of U2b, HIGH 1).
nonisolated enum UndoPlaces {

    // MARK: - Functions

    static func resolved(_ path: String) -> String? {
        guard let real = realpath(path, nil) else {
            return nil
        }
        defer {
            free(real)
        }
        return String(cString: real)
    }

    static func staysInside(_ root: URL, _ relativePath: String) -> Bool {
        if !UndoOp.isSafeRelativePath(relativePath) {
            return false
        }
        guard let rootReal = resolved(root.path) else {
            return false
        }
        // The deepest part of the path that exists, the leaf included (a
        // link at the leaf is followed too).
        var existing: URL = root.appendingPathComponent(relativePath)
        while true {
            var information: stat = stat()
            let found: Int32 = existing.withUnsafeFileSystemRepresentation { fileSystemPath in
                guard let fileSystemPath else {
                    return -1
                }
                return lstat(fileSystemPath, &information)
            }
            if found == 0 {
                break
            }
            if existing.path.count <= root.path.count {
                return true
            }
            existing = existing.deletingLastPathComponent()
        }
        guard let real = resolved(existing.path) else {
            // A link that leads nowhere: refused rather than guessed at.
            return false
        }
        return real == rootReal || real.hasPrefix(rootReal + "/")
    }

    /// `staysInside` for a place `op` names. A link's move names the link
    /// itself at its `from` and `to` (U4b2-14, opKinds.move), so there the
    /// link is never followed: only the folders above it are resolved, and
    /// a link that leads out of the working folder, or nowhere, is moved as
    /// a link like any other.
    static func staysInside(_ root: URL, _ relativePath: String, namedBy op: UndoOp) -> Bool {
        if !op.isALinksMove || (relativePath != op.from && relativePath != op.to) {
            return staysInside(root, relativePath)
        }
        return staysInsideAbove(root, relativePath)
    }

    /// `staysInside` judged on the folders above the place only, its last
    /// part never followed: a link's own place (above), and a file change
    /// at a handed-over place while the link leaving it, or arriving, still
    /// stands there (U4b3 door-1), which is never written through.
    static func staysInsideAbove(_ root: URL, _ relativePath: String) -> Bool {
        if !UndoOp.isSafeRelativePath(relativePath) {
            return false
        }
        let above: String = (relativePath as NSString).deletingLastPathComponent
        if above.isEmpty {
            return true
        }
        return staysInside(root, above)
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
    /// Whether the target can be set to this value at all now, judged
    /// before anything is changed: false for a deploy set for later whose
    /// moment has gone by, which is never registered again (#897 piece B,
    /// seam 2). True for everything else.
    func canSet(_ target: String, _ value: UndoJSON?) -> Bool
    /// Sets the target as `write` does, and says how it went: written, not
    /// written, or written to start only at the next login (a deploy set
    /// for later whose plist is back in LaunchAgents but which launchd
    /// would not load now, and whose plist could not be taken away again:
    /// the re-review of U3b's fixes, LOW 2). Every family but a deploy set
    /// for later answers from `write`.
    func writeSaying(_ target: String, _ value: UndoJSON?) -> UndoExternalWrite
    /// Leaves the trail line for a target `writeSaying` answered
    /// `startsAtTheNextLogin`, once the WHOLE swap has gone in and its step
    /// is closed: never from inside the write, where a later target's
    /// failure would roll the swap back after the line was written (the
    /// review of U3b's fixes, round four, LOW 4). Nothing for every family
    /// but a deploy set for later.
    func noteItStartsAtTheNextLogin(_ target: String)
}

/// How setting an `external` target went (`UndoExternalPlaces.writeSaying`).
nonisolated enum UndoExternalWrite: Equatable, Sendable {
    case written
    case notWritten
    /// A deploy set for later is back on disk, its files as the value says,
    /// and launchd would not load it now: it starts at the next login, and
    /// will not run at its moment unless the teacher logs out and in first.
    case startsAtTheNextLogin
}

nonisolated extension UndoExternalPlaces {

    // MARK: - Functions

    func canSet(_ target: String, _ value: UndoJSON?) -> Bool {
        return true
    }

    func writeSaying(_ target: String, _ value: UndoJSON?) -> UndoExternalWrite {
        return write(target, value) ? .written : .notWritten
    }

    func noteItStartsAtTheNextLogin(_ target: String) {
    }
}

/// The app's own preferences (`PlantoirDefaults.shared`, the one store, which follows `--state-dir`), named
/// `preference:<key>`.
nonisolated struct UndoAppPreferences: UndoExternalPlaces, @unchecked Sendable {

    // MARK: - Stored properties

    /// The store it reads and writes: the app's one store, or a test's own.
    let store: UserDefaults

    // MARK: - Initializer

    init(store: UserDefaults = PlantoirDefaults.shared) {
        self.store = store
    }

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
        guard let stored = store.object(forKey: key) else {
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
            store.removeObject(forKey: key)
            return true
        }
        if !PropertyListSerialization.propertyList(value.foundation(), isValidFor: .binary) {
            // A JSON null, or an object holding one: no preference holds it.
            return false
        }
        store.set(value.foundation(), forKey: key)
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
/// step holding a `recompute` is NOT AVAILABLE to Undo or Redo, and
/// recovery holds such a step open: it is never undone or settled with its
/// re-derivation skipped. Only `recoverAndRederive` settles a live step that
/// keeps a file true by a rule, and it re-derives what it settles, outside
/// the lock; re-deriving is idempotent.
nonisolated enum UndoMaintainers {

    // MARK: - Stored properties

    /// Async, so a maintainer that lives on the main actor (the front
    /// page's) is awaited there, and never called synchronously from the
    /// list's thread or inside its lock (the hard review of U2b, MEDIUM 5).
    typealias Runner = @Sendable (UndoOp, URL) async -> Void

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
    static func rederive(_ ops: [UndoOp], root: URL) async {
        for op in ops where op.knownKind == .recompute {
            // Never through a link that leaves the working folder (the third
            // hard review of U2b, LOW 3).
            if let path = op.path, !UndoPlaces.staysInside(root, path) {
                continue
            }
            if let maintainer = op.maintainer, let run = runner(for: maintainer) {
                await run(op, root)
            }
        }
    }

    /// The same for a step on the list, found by its number.
    static func rederive(
        stepNumbered seq: Int,
        in journal: UndoJournal,
        resolveRoot: @escaping @Sendable (UndoWorkingFolder) -> URL?
    ) async {
        guard let record = (try? journal.read())?.records[seq],
              let root = UndoCheck.root(of: record.step, resolveRoot: resolveRoot) else {
            return
        }
        // Never a file a restore set aside (#899): recovery does not write it.
        let judged: UndoStep = UndoRestoreSetAside.stepWithout(record.setAsidePaths, record.step)
        await rederive(judged.ops, root: root)
    }
}

/// Which spelling a folder lists for a capitalisation-only move's one item
/// (U4b, `UndoMoveSide.spellingListed`).
nonisolated enum UndoCaseOnlySpelling: Equatable, Sendable {
    case from
    case to
    /// A third spelling (renamed by hand since), or no entry at all.
    case another
    case cannotRead
}
