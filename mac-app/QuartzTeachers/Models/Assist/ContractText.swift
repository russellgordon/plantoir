import Foundation

/// Writes a contract file so that what the generator did not change keeps
/// the exact text it was committed with (#866).
///
/// `Plantoir --write-contracts` reads a mixed file (`app-rules.json`,
/// `assist-cases.json`), overwrites its generated keys and writes the whole
/// thing back with `JSONSerialization`'s `.sortedKeys`. The AUTHORED keys
/// are edited as text, on both platforms and on many branches, and an
/// author's key order is not sorted order: on `dev` 86ae77e53 re-encoding
/// the committed `app-rules.json` changed 1,395 lines in 26 places, every
/// one inside an authored key (`outsideAgents.fixWith` among them), while
/// the other two generated files came back byte for byte. A generator that
/// re-sorts those keys turns every run into a reorder nobody wants to
/// commit, and committing it would conflict with every branch that edits
/// the same keys as text.
///
/// So the writer keeps the committed text of every top-level key whose
/// value it would write unchanged, in the committed order, and writes fresh
/// text only for a key whose value changed or that is new to the file (put
/// where the sorted order would put it). A run that changes nothing changes
/// no byte, and a second run is always byte for byte the first.
///
/// Anything it cannot read in that shape, or a result that does not mean
/// exactly what the generator meant, falls back to the plain sorted
/// encoding: keeping text is never allowed to change what the file says.
nonisolated enum ContractText {

    // MARK: - Types

    /// One top-level member of a pretty-printed JSON object: its key, and
    /// its text from the key's opening quote to the end of its value, with
    /// no trailing comma.
    struct Member {

        // MARK: - Stored properties

        let key: String
        let text: String
    }

    // MARK: - Functions

    /// `value` pretty-printed with sorted keys, as `AssistContract.encode`
    /// writes it: no escaped slashes, and a trailing newline.
    static func sortedEncoding(_ value: Any) throws -> Data {
        var data: Data = try JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(contentsOf: [0x0A])
        return data
    }

    /// `value` written over `existing` (the file as it is committed, or nil
    /// when there is none), keeping the committed text of every top-level
    /// key whose value is unchanged.
    static func encode(_ value: [String: Any], keepingTheTextOf existing: Data?) throws -> Data {
        let fresh: Data = try sortedEncoding(value)
        guard let existing,
              let oldText = String(data: existing, encoding: .utf8),
              let newText = String(data: fresh, encoding: .utf8),
              let oldMembers = members(of: oldText),
              let newMembers = members(of: newText) else {
            return fresh
        }

        var oldTextByKey: [String: String] = [:]
        var oldOrder: [String] = []
        for member in oldMembers {
            if oldTextByKey[member.key] != nil {
                // The same key twice: not a file to keep text from.
                return fresh
            }
            oldTextByKey[member.key] = member.text
            oldOrder.append(member.key)
        }
        var newTextByKey: [String: String] = [:]
        var sortedPosition: [String: Int] = [:]
        var sortedOrder: [String] = []
        for member in newMembers {
            newTextByKey[member.key] = member.text
            sortedPosition[member.key] = sortedOrder.count
            sortedOrder.append(member.key)
        }

        // The committed order for every key still written, then each key new
        // to the file before the first kept key the sorted order puts after it.
        var order: [String] = []
        for key in oldOrder where newTextByKey[key] != nil {
            order.append(key)
        }
        for key in sortedOrder where oldTextByKey[key] == nil {
            let position: Int = sortedPosition[key] ?? 0
            var insertAt: Int = order.count
            for (index, placed) in order.enumerated() {
                if let placedPosition = sortedPosition[placed], placedPosition > position {
                    insertAt = index
                    break
                }
            }
            order.insert(key, at: insertAt)
        }

        var pieces: [String] = []
        for key in order {
            var text: String = newTextByKey[key] ?? ""
            if let committed = oldTextByKey[key],
               let wanted = value[key],
               try means(committed, key: key, theSameAs: wanted) {
                text = committed
            }
            pieces.append(text)
        }
        let written: String = "{\n" + pieces.joined(separator: ",\n") + "\n}\n"
        let writtenData: Data = Data(written.utf8)

        // The whole file must mean exactly what the generator meant.
        guard let reread = try? JSONSerialization.jsonObject(with: writtenData),
              try sortedEncoding(reread) == fresh else {
            return fresh
        }
        return writtenData
    }

    /// The top-level members of a pretty-printed JSON object, or nil when the
    /// text is not in that shape. A member starts on a line that begins with
    /// exactly two spaces and a quote: deeper lines are indented further, and
    /// a JSON string cannot hold a raw line break.
    static func members(of text: String) -> [Member]? {
        var body: String = text
        while body.hasSuffix("\n") {
            body.removeLast()
        }
        guard body.hasPrefix("{\n"), body.hasSuffix("\n}") else {
            return nil
        }
        body.removeFirst(2)
        body.removeLast(2)

        var members: [Member] = []
        var currentKey: String? = nil
        var currentLines: [String] = []
        for line in body.components(separatedBy: "\n") {
            if let key = keyStarting(line) {
                if let currentKey {
                    members.append(Member(key: currentKey, text: withoutTrailingComma(currentLines)))
                }
                currentKey = key
                currentLines = [line]
            } else {
                if currentKey == nil {
                    return nil
                }
                currentLines.append(line)
            }
        }
        if let currentKey {
            members.append(Member(key: currentKey, text: withoutTrailingComma(currentLines)))
        }
        if members.isEmpty {
            return nil
        }
        return members
    }

    /// The key a top-level member's first line opens with, decoded, or nil
    /// when the line does not open one.
    static func keyStarting(_ line: String) -> String? {
        guard line.hasPrefix("  \"") else {
            return nil
        }
        let characters: [Character] = Array(line)
        var index: Int = 3
        var isEscaped: Bool = false
        while index < characters.count {
            let character: Character = characters[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                break
            }
            index += 1
        }
        if index >= characters.count {
            return nil
        }
        let literal: String = String(characters[2...index])
        guard let data = literal.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else {
            return nil
        }
        return decoded
    }

    /// Whether a committed member's text means exactly `wanted`, compared as
    /// the tests compare contract values: both written with sorted keys.
    static func means(_ committed: String, key: String, theSameAs wanted: Any) throws -> Bool {
        let wrapped: Data = Data(("{\n" + committed + "\n}").utf8)
        guard let parsed = try? JSONSerialization.jsonObject(with: wrapped) as? [String: Any],
              parsed.count == 1,
              let committedValue = parsed[key] else {
            return false
        }
        return try sortedEncoding(["value": committedValue]) == sortedEncoding(["value": wanted])
    }

    /// One member's lines joined, without the comma that separates it from
    /// the next.
    private static func withoutTrailingComma(_ lines: [String]) -> String {
        var text: String = lines.joined(separator: "\n")
        if text.hasSuffix(",") {
            text.removeLast()
        }
        return text
    }
}
