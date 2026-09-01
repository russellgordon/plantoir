import Foundation

/// Pointing every link that names a FOLDER at that folder's new name.
///
/// The sibling of `WikiLinkRewriter`, and deliberately a separate type: that
/// one rewrites the name of a PAGE, which is what Obsidian's usual
/// `[[Unit 2, Day 3]]` carries. This one rewrites a path SEGMENT, which is
/// what appears when a link is qualified — `[[Tasks/Quiz 1]]`, a full vault
/// path, or a Markdown link written by Obsidian's other link style.
///
/// **Most links need nothing done to them, and that is the important fact.**
/// Obsidian resolves `[[Quiz 1]]` by searching the vault, so moving the folder
/// it lives in leaves the link working. The `TODO.md` entry that deferred this
/// feature worried that a folder rename would strand every link pointing into
/// it; it does not, and the cases that DO break are the qualified ones handled
/// here. That is why renaming a folder is a far smaller risk than renaming a
/// page, and why this could be built without the undo a page rename would
/// need.
///
/// ## What is handled
///
/// * `[[Tasks/Quiz 1]]` and `![[Tasks/diagram.png]]`
/// * `[[ICS3U/section1/Tasks/Quiz 1]]` — a full vault path, so ANY segment is
///   matched, not only the first
/// * `[[Tasks/Quiz 1#Marking|the quiz]]` — the alias and the heading are the
///   teacher's own words and are never touched
/// * `[the quiz](Tasks/Quiz%201.md)` and `![](Tasks/diagram.png)` — Markdown
///   style, with or without percent-encoded spaces, and with a leading `./`
///
/// ## What is NOT handled, on purpose
///
/// A segment is replaced only when it matches the whole folder name. A folder
/// called `Tasks` does not rewrite `Extra Tasks/`, and a page whose own NAME is
/// `Tasks.md` is left alone — the match stops at the last `/`, so a file name
/// is never a candidate. Absolute paths outside the course (`/Users/...`) and
/// links to the web are untouched for the same reason: nothing in them is a
/// segment of this course's tree.
enum FolderPathRewriter {

    // MARK: - Stored properties

    /// An optional `!`, the opening brackets, then the target — which runs up
    /// to the first `]`, `|` or `#`, so an alias, a heading and a block
    /// reference stay where they are. `WikiLinkRewriter`'s pattern, and the
    /// same one on purpose: two link finders that disagreed about what a link
    /// is would rewrite different halves of the same vault.
    static let wikiLinkPattern: String = #"(!?\[\[)([^\]|#]+)"#

    /// A Markdown link or embed's target: everything between `](` and the
    /// closing bracket. Titles (`](path "title")`) are left in place because
    /// the path is taken only up to the first space.
    static let markdownLinkPattern: String = #"(\]\()([^)\s]+)"#

    // MARK: - Functions

    /// The text with every qualified link to `oldName` pointing at `newName`.
    static func rewriting(_ text: String, folderNamed oldName: String, to newName: String) -> String {
        let trimmedOld: String = oldName.trimmingCharacters(in: .whitespaces)
        let trimmedNew: String = newName.trimmingCharacters(in: .whitespaces)
        if trimmedOld.isEmpty || trimmedNew.isEmpty || trimmedOld == trimmedNew {
            return text
        }
        let afterWikiLinks: String = rewritingTargets(
            in: text, matching: wikiLinkPattern, folderNamed: trimmedOld, to: trimmedNew
        )
        return rewritingTargets(
            in: afterWikiLinks, matching: markdownLinkPattern, folderNamed: trimmedOld, to: trimmedNew
        )
    }

    /// How many qualified links in this text name the folder. Used to report
    /// what a rename touched, and to skip writing a file nothing changed in.
    static func countReferences(to folderName: String, in text: String) -> Int {
        let trimmed: String = folderName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return 0
        }
        var total: Int = 0
        for pattern in [wikiLinkPattern, markdownLinkPattern] {
            for target in targets(in: text, matching: pattern) {
                if pathNames(trimmed, in: target) {
                    total += 1
                }
            }
        }
        return total
    }

    // MARK: - Private helpers

    /// Every link target in the text, for one of the two link styles.
    private static func targets(in text: String, matching pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let whole: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var found: [String] = []
        for match in expression.matches(in: text, range: whole) {
            if let targetRange = Range(match.range(at: 2), in: text) {
                found.append(String(text[targetRange]))
            }
        }
        return found
    }

    /// The text with one link style's targets rewritten.
    ///
    /// Walks the matches in order and copies the text between them, rather
    /// than replacing in place: a replacement changes the string's length, and
    /// ranges found beforehand would then point at the wrong characters.
    private static func rewritingTargets(
        in text: String, matching pattern: String, folderNamed oldName: String, to newName: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let whole: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches: [NSTextCheckingResult] = expression.matches(in: text, range: whole)
        if matches.isEmpty {
            return text
        }

        var result: String = ""
        var carriedTo: String.Index = text.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let openingRange = Range(match.range(at: 1), in: text),
                  let targetRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            let target: String = String(text[targetRange])
            let rewritten: String = retargeting(target, folderNamed: oldName, to: newName)
            if rewritten == target {
                continue
            }
            result.append(contentsOf: text[carriedTo..<matchRange.lowerBound])
            result.append(String(text[openingRange]))
            result.append(rewritten)
            carriedTo = matchRange.upperBound
        }
        result.append(contentsOf: text[carriedTo...])
        return result
    }

    /// One link target with any segment naming the folder replaced.
    ///
    /// The LAST segment is the page or file and is never a candidate, so a
    /// page called `Tasks.md` survives a rename of the `Tasks` folder.
    private static func retargeting(_ target: String, folderNamed oldName: String, to newName: String) -> String {
        if !target.contains("/") {
            return target
        }
        var segments: [String] = []
        for segment in target.split(separator: "/", omittingEmptySubsequences: false) {
            segments.append(String(segment))
        }
        var changed: Bool = false
        var rebuilt: [String] = []
        for index in 0..<segments.count {
            let segment: String = segments[index]
            let isLastSegment: Bool = (index == segments.count - 1)
            if !isLastSegment && matches(segment, name: oldName) {
                rebuilt.append(encoded(newName, likeThe: segment))
                changed = true
            } else {
                rebuilt.append(segment)
            }
        }
        if !changed {
            return target
        }
        return rebuilt.joined(separator: "/")
    }

    /// Whether a target names this folder in any segment but its last.
    private static func pathNames(_ folderName: String, in target: String) -> Bool {
        if !target.contains("/") {
            return false
        }
        var segments: [String] = []
        for segment in target.split(separator: "/", omittingEmptySubsequences: false) {
            segments.append(String(segment))
        }
        for index in 0..<(segments.count - 1) {
            if matches(segments[index], name: folderName) {
                return true
            }
        }
        return false
    }

    /// Whether one path segment IS this folder, allowing for the percent
    /// encoding Obsidian writes into Markdown-style links, and matching case
    /// insensitively the way Obsidian resolves names.
    private static func matches(_ segment: String, name: String) -> Bool {
        let plain: String = segment.trimmingCharacters(in: .whitespaces)
        if plain.caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        if let decoded = plain.removingPercentEncoding {
            return decoded.caseInsensitiveCompare(name) == .orderedSame
        }
        return false
    }

    /// The new name written the way the segment it replaces was written: a
    /// percent-encoded segment stays percent-encoded, so a Markdown link keeps
    /// working, and a wikilink keeps its plain spaces.
    private static func encoded(_ name: String, likeThe segment: String) -> String {
        let wasEncoded: Bool = segment.contains("%") && segment.removingPercentEncoding != segment
        if !wasEncoded {
            return name
        }
        let allowed: CharacterSet = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: " "))
        if let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) {
            return encoded
        }
        return name
    }
}
