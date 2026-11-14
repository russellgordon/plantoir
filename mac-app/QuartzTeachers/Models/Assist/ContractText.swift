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
/// Keeping text is for AUTHORED keys only (the batch review of #866). A
/// GENERATED key, one the caller names in `generatedKeys`, is always written
/// in the generator's own text, so a hand edit that changed only its spacing
/// or escaping is rewritten rather than kept; "generated, never hand-edited"
/// then holds for the form as well as the meaning. `withoutGeneratedKeys`
/// takes out every key the committed file's own `generated.keys` names
/// before the generator's values go in. A name there that the app does not
/// generate stops the run with a `Refusal` naming it (the Fable sweep of
/// #866): the writer cannot tell a retired readout from an authored key
/// named there by mistake, and deleting an authored key is the one thing it
/// must never do, so a person decides. A retired readout therefore cannot
/// stay behind looking authored: the run refuses until it is deleted.
///
/// A committed file whose only fault is its whitespace (CRLF line ends, a
/// blank line between members, a space or tab at the end of a line) is read
/// as if it had none: none of the three can be inside a JSON string, so
/// taking them out changes no value, and the authored keys keep their
/// committed order. Before the sweep each of those
/// sent the whole file to the sorted fallback without a word.
///
/// Anything it cannot read in that shape, or a result that does not mean
/// exactly what the generator meant, falls back to the plain sorted
/// encoding: keeping text is never allowed to change what the file says.
nonisolated enum ContractText {

    // MARK: - Types

    /// Why a committed file cannot be written over.
    struct Refusal: LocalizedError {

        // MARK: - Stored properties

        /// The key the committed `generated.keys` names and the app does not
        /// generate.
        let key: String

        // MARK: - Computed properties

        var errorDescription: String? {
            return "generated.keys names \(key), which the app does not generate, so nothing was written. "
                 + "If \(key) is hand-written, take its name out of generated.keys; if it is a readout "
                 + "the app no longer writes, delete \(key) and its name by hand."
        }
    }

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
    /// authored key whose value is unchanged. A key in `generatedKeys` is
    /// always written in the generator's own text.
    static func encode(
        _ value: [String: Any],
        keepingTheTextOf existing: Data?,
        generatedKeys: Set<String> = []
    ) throws -> Data {
        let fresh: Data = try sortedEncoding(value)
        guard let existing,
              let committedText = String(data: existing, encoding: .utf8),
              let newText = String(data: fresh, encoding: .utf8),
              let oldMembers = members(of: withoutStrayWhitespace(committedText)),
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
            if !generatedKeys.contains(key),
               let committed = oldTextByKey[key],
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

    /// `rules` (a committed file, read) without the keys its own
    /// `generated.keys` names; the generator then puts back every key it
    /// writes. A file with no `generated.keys` is returned as it is.
    ///
    /// A name there that is not in `generating`, the keys the app writes
    /// today, throws a `Refusal` naming it, and nothing is taken out: an
    /// authored key named there by mistake is never deleted.
    static func withoutGeneratedKeys(_ rules: [String: Any], generating: [String]) throws -> [String: Any] {
        guard let generated = rules["generated"] as? [String: Any],
              let keys = generated["keys"] as? [String] else {
            return rules
        }
        for key in keys {
            if !generating.contains(key) {
                throw Refusal(key: key)
            }
        }
        var kept: [String: Any] = rules
        for key in keys {
            kept.removeValue(forKey: key)
        }
        return kept
    }

    /// `text` with CRLF line ends made LF and every space or tab at the end of
    /// a line taken off. Neither can be inside a JSON string, so the result
    /// means what `text` means. Blank lines stay: the generator's own text
    /// has one inside every empty array, and `members(of:)` drops the ones
    /// between members.
    static func withoutStrayWhitespace(_ text: String) -> String {
        let unixText: String = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [String] = []
        for line in unixText.components(separatedBy: "\n") {
            var trimmed: String = line
            while trimmed.hasSuffix(" ") || trimmed.hasSuffix("\t") {
                trimmed.removeLast()
            }
            lines.append(trimmed)
        }
        return lines.joined(separator: "\n")
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
            } else if currentKey == nil {
                // A blank line before the first member is not part of one.
                if !line.isEmpty {
                    return nil
                }
            } else {
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

    /// One member's lines joined, without the blank lines after it and the
    /// comma that separates it from the next. A value never ends with a blank
    /// line, so those are always between members.
    private static func withoutTrailingComma(_ lines: [String]) -> String {
        var kept: [String] = lines
        while let last = kept.last, last.isEmpty {
            kept.removeLast()
        }
        var text: String = kept.joined(separator: "\n")
        if text.hasSuffix(",") {
            text.removeLast()
        }
        return text
    }
}
