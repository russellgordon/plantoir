import Foundation

/// Everything a page names that might be a file of the teacher's — and
/// pointing one of them at a new name.
///
/// **Why this is not `AssistSectionGraph.linkTargets`.** That reads wikilinks
/// and answers "which PAGE does this lead to", normalising the answer for an
/// index. This has a different job: it must find every place a page names a
/// PICTURE OR FILE, and it must be able to hand back the exact token so it can
/// be rewritten. Four shapes are read, and the list is measured rather than
/// assumed, across all 777 markdown files in four real courses:
///
/// | shape | count | why it is here |
/// |---|---|---|
/// | `![[x.png]]` embeds | 1,474 (1,274 of them media) | the ordinary case |
/// | `[[x.pdf]]` links at a FILE | 250, of which 235 PDFs | a link, not an embed — and the biggest single thing a scan of embeds alone would drop |
/// | `<img src="/Media/x.png">` | 5 | three of them on pages inside shared folders; one is a live 1.1 MB picture |
/// | `[text](x.png)` | 526, every one `https://` | nothing local to carry today, scanned anyway because the cost is nothing |
///
/// **Code is left alone** — a fenced block of either character, a fence
/// inside a callout, an inline span. A name inside code is prose about a file
/// rather than a use of one, and rewriting it would edit an example a teacher
/// wrote. Where code is comes from `MarkdownCode`, the one definition every
/// link reader and rewriter on the mac shares (#313,
/// `readingALink.whatIsCode`): a match of any of the three shapes that STARTS
/// in code is skipped. Until #313 this walker tracked ``` and ~~~ fences
/// itself and not inline spans, and saw no fence inside a `>` callout.
///
/// `nonisolated`: pure over its arguments, and run off the main actor by the
/// copy.
nonisolated enum PageReferences {

    // MARK: - Types

    /// One place a page names something.
    struct Reference: Sendable, Equatable {

        // MARK: - Types

        enum Kind: String, Sendable {
            /// `[[x]]` or `![[x]]` — written plainly, never percent-encoded.
            case wikilink
            /// An HTML attribute or a Markdown link — percent-encoded.
            case encoded
        }

        // MARK: - Stored properties

        let kind: Kind

        /// The token exactly as the page writes it, brackets excluded —
        /// `Media/diagram.png`, `/Media/x%20y.png`.
        let target: String

        /// What it names: the last path component, decoded, with any query
        /// or fragment taken off.
        let lastComponent: String
    }

    // MARK: - Functions

    /// Every reference on a page, in the order they appear, each one once per
    /// occurrence.
    static func references(in text: String) -> [Reference] {
        var found: [Reference] = []
        PageReferences.walk(text) { _, matches in
            for match in matches {
                found.append(match.reference)
            }
        }
        return found
    }

    /// The page with every reference to a renamed file pointing at its new
    /// name — and nothing else touched.
    ///
    /// Keyed by the OLD name's comparison key, so `Media/diagram.png`,
    /// `diagram.PNG` and a decomposed spelling of the same name are all
    /// rewritten. The folder in front of a target is kept: a page that said
    /// `Media/x.png` goes on saying `Media/…`, because changing the shape of
    /// a teacher's link is not this feature's business.
    ///
    /// The new name is written in the SOURCE's own byte form — never a
    /// normalised re-spelling — because the file it points at is written with
    /// those bytes too.
    static func rewriting(_ text: String, renaming: [String: ExactName]) -> String {
        if renaming.isEmpty {
            return text
        }
        var result: [String] = []
        PageReferences.walk(text) { line, matches in
            if matches.isEmpty {
                result.append(line)
                return
            }
            var rebuilt: String = ""
            var carriedTo: String.Index = line.startIndex
            for match in matches {
                guard let newName = renaming[ExactName(match.reference.lastComponent).comparisonKey] else {
                    continue
                }
                rebuilt.append(contentsOf: line[carriedTo..<match.range.lowerBound])
                rebuilt.append(PageReferences.retargeting(
                    match.reference, to: newName
                ))
                carriedTo = match.range.upperBound
            }
            rebuilt.append(contentsOf: line[carriedTo..<line.endIndex])
            result.append(rebuilt)
        }
        return result.joined(separator: "\n")
    }

    /// Whether this page still names any of these files — asked of the text
    /// AFTER a rewrite, with the same scanner that found them in the first
    /// place.
    ///
    /// The guard on the one direction this feature must never err in. A
    /// picture that came in under a new name, with one occurrence of the old
    /// name left behind, would show the teacher's OWN different picture under
    /// the name the copy wanted — silently. So the answer here decides
    /// whether the page is copied at all.
    static func stillNames(_ keys: Set<String>, in text: String) -> Bool {
        for reference in PageReferences.references(in: text) {
            if keys.contains(ExactName(reference.lastComponent).comparisonKey) {
                return true
            }
        }
        return false
    }

    // MARK: - Private helpers

    /// One match on one line.
    private struct Match {
        let range: Range<String.Index>
        let reference: Reference
    }

    /// The target with its last component replaced, keeping whatever the page
    /// wrote in front of it and re-encoding when the shape calls for it.
    private static func retargeting(_ reference: Reference, to newName: ExactName) -> String {
        var prefix: String = ""
        if let lastSlash = reference.target.lastIndex(of: "/") {
            prefix = String(reference.target[...lastSlash])
        }
        switch reference.kind {
        case .wikilink:
            return prefix + newName.text
        case .encoded:
            let encoded: String = newName.text.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.urlPathAllowed
            ) ?? newName.text
            return prefix + encoded
        }
    }

    /// Walks the page a line at a time and hands each line's matches — the
    /// ones that do not start in code — to `handle`. Code is found over the
    /// WHOLE page, since a fence or a span can cross lines, and applied to
    /// each line by its offset. Lines stay the unit so that no name is ever
    /// read across a line break.
    private static func walk(_ text: String, handle: (String, [Match]) -> Void) {
        let code: [NSRange] = MarkdownCode.ranges(in: text)
        let lines: [String] = PageReferences.lines(of: text)
        var lineOffset: Int = 0
        for line in lines {
            handle(line, PageReferences.matches(in: line, code: code, lineOffset: lineOffset))
            lineOffset += line.utf16.count + 1
        }
    }

    /// The page split at every `\n`, by UTF-16 code unit, so each line's
    /// length is exactly its share of the offsets `MarkdownCode` works in. A
    /// `\r` before the `\n` stays on its line, and joining with `\n` gives
    /// the page back byte for byte. (Not `split` over `Character`s, where
    /// `"\r\n"` is one character and never equal to `"\n"`.)
    private static func lines(of text: String) -> [String] {
        let units: [UInt16] = Array(text.utf16)
        var lines: [String] = []
        var start: Int = 0
        var index: Int = 0
        while index < units.count {
            if units[index] == 0x0A {
                lines.append(String(decoding: units[start..<index], as: UTF16.self))
                start = index + 1
            }
            index += 1
        }
        lines.append(String(decoding: units[start..<units.count], as: UTF16.self))
        return lines
    }

    /// The wikilink shape, `WikiLinkRewriter`'s own, so a target this reads is
    /// exactly a target a rename would rewrite. A picture sized inside a table,
    /// `![[circuit.png\|300]]`, reads as `circuit.png` and a rename writes
    /// only that range, leaving the backslash the table needs (#294).
    private static let wikilinkExpression: NSRegularExpression? =
        try? NSRegularExpression(pattern: WikiLinkRewriter.pattern)

    /// `src="…"` and `href="…"`, in either kind of quote.
    private static let attributeExpression: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:src|href)\s*=\s*(?:"([^"]*)"|'([^']*)')"#,
        options: [.caseInsensitive]
    )

    /// A Markdown link's destination: `](…)`, up to a space or the closing
    /// bracket, so a link carrying a title is still read.
    private static let markdownExpression: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"\]\(([^)\s]+)"#)

    private static func matches(in line: String, code: [NSRange], lineOffset: Int) -> [Match] {
        var found: [Match] = []
        PageReferences.collect(
            PageReferences.wikilinkExpression, in: line, groups: [2],
            kind: .wikilink, code: code, lineOffset: lineOffset, into: &found
        )
        PageReferences.collect(
            PageReferences.attributeExpression, in: line, groups: [1, 2],
            kind: .encoded, code: code, lineOffset: lineOffset, into: &found
        )
        PageReferences.collect(
            PageReferences.markdownExpression, in: line, groups: [1],
            kind: .encoded, code: code, lineOffset: lineOffset, into: &found
        )
        found.sort { first, second in
            return first.range.lowerBound < second.range.lowerBound
        }
        return found
    }

    private static func collect(
        _ expression: NSRegularExpression?,
        in line: String,
        groups: [Int],
        kind: Reference.Kind,
        code: [NSRange],
        lineOffset: Int,
        into found: inout [Match]
    ) {
        guard let expression else {
            return
        }
        let live: [NSTextCheckingResult] = MarkdownCode.matches(
            of: expression, in: line, outside: code, offset: lineOffset
        )
        for result in live {
            for group in groups {
                guard group < result.numberOfRanges,
                      let range = Range(result.range(at: group), in: line) else {
                    continue
                }
                let target: String = String(line[range])
                guard let lastComponent = PageReferences.fileNamed(by: target, kind: kind) else {
                    continue
                }
                found.append(Match(
                    range: range,
                    reference: Reference(kind: kind, target: target, lastComponent: lastComponent)
                ))
                break
            }
        }
    }

    /// What a target names, or nil when it names nothing local.
    ///
    /// Anything with a scheme is somewhere else entirely — `https://`,
    /// `mailto:`, `data:`, and Obsidian's own `app://obsidian.md/…`, of which
    /// two exist in the real courses and which are a known gap
    /// `WikiLinkRewriter`'s own documentation already records.
    private static func fileNamed(by target: String, kind: Reference.Kind) -> String? {
        var text: String = target.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text.hasPrefix("#") {
            return nil
        }
        if text.contains("://") || text.hasPrefix("mailto:") || text.hasPrefix("data:")
            || text.hasPrefix("//") {
            return nil
        }
        if let lastSlash = text.lastIndex(of: "/") {
            text = String(text[text.index(after: lastSlash)...])
        }
        if kind == .encoded {
            for separator in ["?", "#"] {
                if let cut = text.firstIndex(of: Character(separator)) {
                    text = String(text[..<cut])
                }
            }
            text = text.removingPercentEncoding ?? text
        }
        let tidied: String = text.trimmingCharacters(in: .whitespaces)
        if tidied.isEmpty {
            return nil
        }
        return tidied
    }
}
