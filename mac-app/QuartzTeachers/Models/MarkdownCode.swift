import Foundation

/// Where a page's CODE is, so that a link written inside code is not read as a
/// link (#313).
///
/// A `[[…]]` or `![[…]]` whose opening brackets sit inside a fenced code block
/// or an inline code span is an EXAMPLE of a link — the Scavenger Hunt pages
/// teach the syntax that way — and Quartz v4.5.0 never draws one: `ofm.ts`
/// builds links with `mdast-util-find-and-replace` over text nodes only, so
/// `code` and `inlineCode` are never searched. Built in real Quartz and
/// checked, shape by shape:
///
/// | Shape | Quartz draws a link? |
/// |---|---|
/// | `` `[[X]]` ``, a double-backtick span holding a single one, a span across two lines of a paragraph, a span in a table cell | no |
/// | a ```` ``` ```` or `~~~` fence, ```` ```` ```` holding ```` ``` ````, a fence inside a `>` callout, a fence never closed | no |
/// | an indented line continuing a LIST item | **yes** |
/// | a lone, never-closed backtick before the link | **yes** |
/// | `<code>[[X]]</code>` (raw HTML) | **yes** |
///
/// **This is the only implementation of the rule on the mac.** Every reader
/// and rewriter reaches it through `WikiLinkRewriter.linkMatches` or
/// `matches(of:in:outside:offset:)`. The rule is written down, to be
/// implemented from, in `contracts/shared-rules.json` →
/// `readingALink.whatIsCode`, and `readingALink.cases` pins it; the build's
/// copy is `scripts/markdown_code.py`, and Windows is owed one.
///
/// ### The limits, stated rather than fixed
///
/// * Indented code (four spaces) is not code here. 0 of the 39,570 links in
///   `support/` sit in it, and getting it right needs list tracking: a
///   shortcut drops real links from nested lists, in the direction that
///   leaves pages unpublished while the plan looks right.
/// * A fence opened inside a list item whose lines fall back to column 0 runs
///   to its own closer here; CommonMark ends it with the item. TEJ2O's lab
///   page had that shape and was fixed; the payload linter refuses it.
/// * A paragraph breaks only at a blank line, a fence, a list marker, a
///   heading or a table row, so a span can run on past another kind of block.
///
/// Measured with Quartz's own parser, these disagree with Quartz on 0 of the
/// 39,570 shipped links.
///
/// ### Rejected
///
/// * A real Markdown parser (swift-markdown, cmark). The Python build and the
///   C# app cannot share it, so the three would drift at exactly the edges the
///   contract pins, and it is a dependency to vendor and sign.
/// * Scanning `Character`s. `"\r\n"` is ONE grapheme in Swift, so a scan for
///   `"\n"` misses every line ending of a page written on Windows; and the
///   offsets have to be UTF-16 anyway, to line up with `NSRegularExpression`.
///   Everything the rule looks at is ASCII, so code units are enough.
///
/// `nonisolated`: pure over its arguments, and run off the main actor by every
/// rename and by the copy.
nonisolated enum MarkdownCode {

    // MARK: - Stored properties

    private static let newline: UInt16 = 0x0A
    private static let carriageReturn: UInt16 = 0x0D
    private static let space: UInt16 = 0x20
    private static let tab: UInt16 = 0x09
    private static let formFeed: UInt16 = 0x0C
    private static let verticalTab: UInt16 = 0x0B
    private static let backtick: UInt16 = 0x60
    private static let tilde: UInt16 = 0x7E
    private static let greaterThan: UInt16 = 0x3E
    private static let backslash: UInt16 = 0x5C
    private static let hash: UInt16 = 0x23
    private static let pipe: UInt16 = 0x7C
    private static let hyphen: UInt16 = 0x2D
    private static let asterisk: UInt16 = 0x2A
    private static let plus: UInt16 = 0x2B
    private static let period: UInt16 = 0x2E
    private static let closingParenthesis: UInt16 = 0x29
    private static let zero: UInt16 = 0x30
    private static let nine: UInt16 = 0x39

    // MARK: - Nested types

    /// A run of three or more fence characters at the start of a line's body.
    private struct FenceRun {
        let character: UInt16
        let length: Int
        /// Where whatever follows the run begins.
        let restStart: Int
    }

    // MARK: - Functions

    /// Every stretch of `text` that is code, sorted and non-overlapping, in
    /// UTF-16 offsets — the unit `NSRegularExpression` reports ranges in.
    static func ranges(in text: String) -> [NSRange] {
        let units: [UInt16] = Array(text.utf16)
        let length: Int = units.count
        var found: [NSRange] = []
        var fenceCharacter: UInt16 = 0
        var fenceLength: Int = 0
        var paragraphStart: Int = -1
        var paragraphEnd: Int = -1

        var lineStart: Int = 0
        while lineStart <= length {
            var lineEnd: Int = lineStart
            while lineEnd < length && units[lineEnd] != newline {
                lineEnd += 1
            }
            let nextStart: Int = lineEnd + 1
            var contentEnd: Int = lineEnd
            if contentEnd > lineStart && units[contentEnd - 1] == carriageReturn {
                contentEnd -= 1
            }
            let bodyStart: Int = MarkdownCode.afterQuoteMarkers(units, from: lineStart, to: contentEnd)
            let fence: FenceRun? = MarkdownCode.fenceRun(units, from: bodyStart, to: contentEnd)
            let wholeLine: NSRange = NSRange(location: lineStart, length: min(nextStart, length) - lineStart)

            if fenceCharacter != 0 {
                found.append(wholeLine)
                if let fence,
                   fence.character == fenceCharacter,
                   fence.length >= fenceLength,
                   MarkdownCode.isBlank(units, from: fence.restStart, to: contentEnd) {
                    fenceCharacter = 0
                }
            } else if let fence,
                      !(fence.character == backtick
                        && MarkdownCode.holds(backtick, in: units, from: fence.restStart, to: contentEnd)) {
                MarkdownCode.addSpans(units, from: paragraphStart, to: paragraphEnd, into: &found)
                paragraphStart = -1
                fenceCharacter = fence.character
                fenceLength = fence.length
                found.append(wholeLine)
            } else if MarkdownCode.isBlank(units, from: bodyStart, to: contentEnd) {
                MarkdownCode.addSpans(units, from: paragraphStart, to: paragraphEnd, into: &found)
                paragraphStart = -1
            } else {
                if MarkdownCode.startsABlock(units, from: bodyStart, to: contentEnd) {
                    MarkdownCode.addSpans(units, from: paragraphStart, to: paragraphEnd, into: &found)
                    paragraphStart = -1
                }
                if paragraphStart < 0 {
                    paragraphStart = lineStart
                }
                paragraphEnd = lineEnd
            }

            if lineEnd >= length {
                break
            }
            lineStart = nextStart
        }
        MarkdownCode.addSpans(units, from: paragraphStart, to: paragraphEnd, into: &found)

        return MarkdownCode.sortedAndMerged(found)
    }

    /// Whether `location` falls inside one of `ranges`.
    static func contains(_ location: Int, in ranges: [NSRange]) -> Bool {
        return MarkdownCode.range(holding: location, in: ranges) != nil
    }

    /// The matches of `expression` in `text` that do not START inside code —
    /// the one mask every link reader and rewriter applies
    /// (`readingALink.whatIsCode`, rule 5). The text is never changed, so a
    /// rewriter can use the ranges as they are.
    ///
    /// A match that starts in code is not merely dropped: the search starts
    /// again where that code ENDS. Dropping it alone would lose the real link
    /// after an example, because the link pattern crosses a `[`: in
    /// "Type `[[` to start one: [[Real Page]]" it matches from the example's
    /// brackets on to "Real Page", and the real link would never be seen
    /// (the contract case "a stray [[ inside code does not swallow the link
    /// after it").
    ///
    /// `offset` is where `text` sits in the page `ranges` was taken over, for
    /// a reader that works a line at a time.
    static func matches(
        of expression: NSRegularExpression,
        in text: String,
        outside ranges: [NSRange],
        offset: Int = 0
    ) -> [NSTextCheckingResult] {
        let length: Int = text.utf16.count
        var found: [NSTextCheckingResult] = []
        var position: Int = 0
        while position <= length {
            let rest: NSRange = NSRange(location: position, length: length - position)
            guard let match = expression.firstMatch(in: text, options: [], range: rest) else {
                break
            }
            if let holding = MarkdownCode.range(holding: offset + match.range.location, in: ranges) {
                position = NSMaxRange(holding) - offset
                continue
            }
            found.append(match)
            if match.range.length > 0 {
                position = NSMaxRange(match.range)
            } else {
                position = match.range.location + 1
            }
        }
        return found
    }

    // MARK: - Private helpers

    private static func range(holding location: Int, in ranges: [NSRange]) -> NSRange? {
        var low: Int = 0
        var high: Int = ranges.count - 1
        while low <= high {
            let middle: Int = (low + high) / 2
            let candidate: NSRange = ranges[middle]
            if location < candidate.location {
                high = middle - 1
            } else if location >= NSMaxRange(candidate) {
                low = middle + 1
            } else {
                return candidate
            }
        }
        return nil
    }

    private static func isSpaceOrTab(_ unit: UInt16) -> Bool {
        return unit == space || unit == tab
    }

    /// Whitespace, for the rule: ASCII only, so every language agrees.
    private static func isWhitespace(_ unit: UInt16) -> Bool {
        return unit == space || unit == tab || unit == carriageReturn
            || unit == formFeed || unit == verticalTab
    }

    private static func isBlank(_ units: [UInt16], from start: Int, to end: Int) -> Bool {
        var index: Int = start
        while index < end {
            if !MarkdownCode.isWhitespace(units[index]) {
                return false
            }
            index += 1
        }
        return true
    }

    private static func holds(_ unit: UInt16, in units: [UInt16], from start: Int, to end: Int) -> Bool {
        var index: Int = start
        while index < end {
            if units[index] == unit {
                return true
            }
            index += 1
        }
        return false
    }

    private static func afterSpacesAndTabs(_ units: [UInt16], from start: Int, to end: Int) -> Int {
        var index: Int = start
        while index < end && MarkdownCode.isSpaceOrTab(units[index]) {
            index += 1
        }
        return index
    }

    /// Where a line's body begins: past any blockquote markers — spaces or
    /// tabs then `>`, repeated — and one optional space after the last.
    private static func afterQuoteMarkers(_ units: [UInt16], from start: Int, to end: Int) -> Int {
        var position: Int = start
        var sawAMarker: Bool = false
        while true {
            let candidate: Int = MarkdownCode.afterSpacesAndTabs(units, from: position, to: end)
            if candidate < end && units[candidate] == greaterThan {
                position = candidate + 1
                sawAMarker = true
            } else {
                break
            }
        }
        if sawAMarker && position < end && units[position] == space {
            position += 1
        }
        return sawAMarker ? position : start
    }

    /// A fence run at the start of a body (after spaces and tabs), if any.
    private static func fenceRun(_ units: [UInt16], from start: Int, to end: Int) -> FenceRun? {
        let first: Int = MarkdownCode.afterSpacesAndTabs(units, from: start, to: end)
        if first >= end {
            return nil
        }
        let character: UInt16 = units[first]
        if character != backtick && character != tilde {
            return nil
        }
        var runEnd: Int = first
        while runEnd < end && units[runEnd] == character {
            runEnd += 1
        }
        if runEnd - first < 3 {
            return nil
        }
        return FenceRun(character: character, length: runEnd - first, restStart: runEnd)
    }

    /// Whether a body begins a list item, a heading or a table row — the
    /// block starts that end a paragraph, so a span cannot reach past them.
    private static func startsABlock(_ units: [UInt16], from start: Int, to end: Int) -> Bool {
        let first: Int = MarkdownCode.afterSpacesAndTabs(units, from: start, to: end)
        if first >= end {
            return false
        }
        let character: UInt16 = units[first]
        if character == hyphen || character == asterisk || character == plus {
            return first + 1 < end && MarkdownCode.isSpaceOrTab(units[first + 1])
        }
        if character == pipe {
            return true
        }
        if character == hash {
            var runEnd: Int = first
            while runEnd < end && units[runEnd] == hash {
                runEnd += 1
            }
            let count: Int = runEnd - first
            if count > 6 {
                return false
            }
            return runEnd == end || MarkdownCode.isSpaceOrTab(units[runEnd])
        }
        if character >= zero && character <= nine {
            var runEnd: Int = first
            while runEnd < end && units[runEnd] >= zero && units[runEnd] <= nine {
                runEnd += 1
            }
            let count: Int = runEnd - first
            if count > 9 || runEnd + 1 >= end {
                return false
            }
            let marker: UInt16 = units[runEnd]
            if marker != period && marker != closingParenthesis {
                return false
            }
            return MarkdownCode.isSpaceOrTab(units[runEnd + 1])
        }
        return false
    }

    /// The inline code spans in one paragraph, `units[start..<end]`.
    private static func addSpans(_ units: [UInt16], from start: Int, to end: Int, into found: inout [NSRange]) {
        if start < 0 {
            return
        }
        var position: Int = start
        while position < end {
            let unit: UInt16 = units[position]
            if unit == backslash && position + 1 < end {
                position += 2
                continue
            }
            if unit != backtick {
                position += 1
                continue
            }
            var runEnd: Int = position
            while runEnd < end && units[runEnd] == backtick {
                runEnd += 1
            }
            let runLength: Int = runEnd - position
            var closingEnd: Int = -1
            var scan: Int = runEnd
            while scan < end {
                if units[scan] != backtick {
                    scan += 1
                    continue
                }
                var otherEnd: Int = scan
                while otherEnd < end && units[otherEnd] == backtick {
                    otherEnd += 1
                }
                if otherEnd - scan == runLength {
                    closingEnd = otherEnd
                    break
                }
                scan = otherEnd
            }
            if closingEnd < 0 {
                // Never closed: the run is plain text, and so is what follows.
                position = runEnd
                continue
            }
            found.append(NSRange(location: position, length: closingEnd - position))
            position = closingEnd
        }
    }

    private static func sortedAndMerged(_ ranges: [NSRange]) -> [NSRange] {
        let sorted: [NSRange] = ranges.sorted { first, second in
            return first.location < second.location
        }
        var merged: [NSRange] = []
        for range in sorted {
            if range.length <= 0 {
                continue
            }
            if let last = merged.last, range.location <= NSMaxRange(last) {
                if NSMaxRange(range) > NSMaxRange(last) {
                    merged[merged.count - 1] = NSRange(
                        location: last.location,
                        length: NSMaxRange(range) - last.location
                    )
                }
                continue
            }
            merged.append(range)
        }
        return merged
    }
}
