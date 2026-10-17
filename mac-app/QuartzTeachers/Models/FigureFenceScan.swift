import Foundation

/// Which figure fences a page holds (#495) — a Swift port of
/// `scripts/markdown_code.py` → `fenced_blocks`, the walker the build uses to
/// find ```` ```tikz ```` and ```` ```functionplot ```` (#485 E1), so the app,
/// the build and (when it is owed) Windows agree on the same data:
/// `contracts/shared-rules.json` → `figureFences.fences.cases`.
///
/// **Why a walker of its own, not `MarkdownCode.ranges(in:)`** (#495 plan
/// review S1). The #313 rule opens a fence only when the line's body STARTS
/// with the fence characters, so `- ```tikz` and `1. ```functionplot` — both
/// contract cases — are paragraph text there, and their closing ```` ``` ````
/// then OPENS a fence that runs to the end of the page, reading every later
/// fence inside out. The Python side has the same split: `code_ranges` keeps
/// its #313 rule, and `fenced_blocks` is a separate walker with the list
/// marker, tab columns, quote depth and `%%` removal. This is that walker;
/// `MarkdownCode` and its `readingALink` cases are untouched.
///
/// The rule, in the walker's order (each step is the Python's):
///
/// 1. Every `%%…%%` comment is removed first, as Quartz removes it — lazy,
///    left to right, across lines; a `%%` with no partner is text.
/// 2. A line's blockquote markers give its DEPTH; a fence belongs to its
///    opener's depth and a line at a smaller depth ends it.
/// 3. A fence opens on a line whose body starts with three or more backticks
///    or tildes (spaces and tabs first are allowed) — or does so after a list
///    marker (`- `, `1. `), or after further containers on that line
///    (`- - `, `1. > `), which marks the block NESTED. Backticks with another
///    backtick later on the line are inline code, not a fence.
/// 4. It closes on a line at its depth holding a run of the same character
///    at least as long with nothing but whitespace after it.
/// 5. The language is the info string's FIRST word, exactly. `TikZ` is not
///    `tikz`.
///
/// A nested block is read only so that the fences after it are read as the
/// site reads them; figures leave it alone (`figures.figures_on_page`), and so
/// does `kinds(in:among:)`.
///
/// Everything the rule looks at is ASCII, so it works on UTF-16 code units —
/// `MarkdownCode`'s reasoning: `"\r\n"` is ONE `Character` in Swift. The
/// first-word split is the one exception, and it uses Python's `str.split()`
/// whitespace set exactly.
nonisolated enum FigureFenceScan {

    // MARK: - Types

    /// One fenced block, as `fenced_blocks` reports the parts this needs.
    struct Block: Equatable, Sendable {

        // MARK: - Stored properties

        /// The info string's first word, as written.
        var lang: String

        /// The 1-based line of the opening fence, in the page as given.
        var line: Int

        /// Opened after a second container on a list marker's line.
        var nested: Bool
    }

    /// The fence a line opens or closes with.
    private struct FenceRun {
        var character: UInt16
        var length: Int
        var restStart: Int
    }

    /// A fence that is open, and what closes it.
    private struct OpenFence {
        var character: UInt16
        var length: Int
        var depth: Int
    }

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
    private static let hyphen: UInt16 = 0x2D
    private static let asterisk: UInt16 = 0x2A
    private static let plus: UInt16 = 0x2B
    private static let period: UInt16 = 0x2E
    private static let closingParenthesis: UInt16 = 0x29
    private static let zero: UInt16 = 0x30
    private static let nine: UInt16 = 0x39
    private static let percent: UInt16 = 0x25

    /// Python's `str.split()` whitespace: what `info.split(None, 1)` splits
    /// the info string's first word off at.
    private static let pythonWhitespace: Set<UInt32> = [
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0xA0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    ]

    // MARK: - Functions

    /// The figure kinds among `kinds` that the page holds, as fences that are
    /// not nested — what `figures_on_page` would draw.
    static func kinds(in text: String, among kinds: Set<String>) -> Set<String> {
        var found: Set<String> = []
        for block in FigureFenceScan.blocks(in: text) {
            if block.nested {
                continue
            }
            if kinds.contains(block.lang) {
                found.insert(block.lang)
            }
        }
        return found
    }

    /// Every fenced block on the page, in order.
    static func blocks(in text: String) -> [Block] {
        let original: [UInt16] = Array(text.utf16)
        let stripped: (units: [UInt16], origin: [Int]?) = FigureFenceScan.withoutComments(original)
        let units: [UInt16] = stripped.units
        var found: [Block] = []
        var open: OpenFence?

        var lineStart: Int = 0
        let length: Int = units.count
        while lineStart <= length {
            var newlineAt: Int = -1
            var scan: Int = lineStart
            while scan < length {
                if units[scan] == FigureFenceScan.newline {
                    newlineAt = scan
                    break
                }
                scan += 1
            }
            let lineEnd: Int = newlineAt < 0 ? length : newlineAt
            var end: Int = lineEnd
            if end > lineStart && units[end - 1] == FigureFenceScan.carriageReturn {
                end -= 1
            }
            let quote: (depth: Int, bodyStart: Int) = FigureFenceScan.quoteDepthAndBody(units, from: lineStart, to: end)

            if let fence = open, quote.depth < fence.depth {
                open = nil
            }

            if let fence = open {
                let contentStart: Int = FigureFenceScan.afterQuoteMarkers(units, from: lineStart, to: end, depth: fence.depth)
                if quote.depth == fence.depth,
                   let run = FigureFenceScan.fenceRun(units, from: contentStart, to: end),
                   run.character == fence.character,
                   run.length >= fence.length,
                   FigureFenceScan.isBlank(units, from: run.restStart, to: end) {
                    open = nil
                }
            } else {
                var run: FenceRun? = FigureFenceScan.fenceRun(units, from: quote.bodyStart, to: end)
                var nested: Bool = false
                var quotesAfterMarker: Int = 0
                if run == nil, let afterMarker = FigureFenceScan.listMarkerEnd(units, from: quote.bodyStart, to: end) {
                    var marker: Int = afterMarker
                    run = FigureFenceScan.fenceRun(units, from: marker, to: end)
                    while run == nil {
                        guard let container = FigureFenceScan.nestedContainer(units, from: marker, to: end) else {
                            break
                        }
                        nested = true
                        if container.isQuote {
                            quotesAfterMarker += 1
                        }
                        marker = container.end
                        run = FigureFenceScan.fenceRun(units, from: marker, to: end)
                    }
                }
                if let run, !(run.character == FigureFenceScan.backtick && FigureFenceScan.holdsABacktick(units, from: run.restStart, to: end)) {
                    let place: Int = stripped.origin?[lineStart] ?? lineStart
                    found.append(Block(
                        lang: FigureFenceScan.firstWord(units, from: run.restStart, to: end),
                        line: FigureFenceScan.lineNumber(of: place, in: original),
                        nested: nested
                    ))
                    open = OpenFence(character: run.character, length: run.length, depth: quote.depth + quotesAfterMarker)
                }
            }

            if newlineAt < 0 {
                break
            }
            lineStart = lineEnd + 1
        }
        return found
    }

    // MARK: - Private helpers

    /// The page with every `%%` comment removed, and for each code unit of
    /// the result its offset in the page (plus one past the end) — or nil
    /// for the origin when there was no comment.
    private static func withoutComments(_ units: [UInt16]) -> (units: [UInt16], origin: [Int]?) {
        var comments: [(start: Int, end: Int)] = []
        var position: Int = 0
        while true {
            guard let start = FigureFenceScan.doublePercent(in: units, from: position) else {
                break
            }
            guard let close = FigureFenceScan.doublePercent(in: units, from: start + 2) else {
                break
            }
            comments.append((start: start, end: close + 2))
            position = close + 2
        }
        if comments.isEmpty {
            return (units: units, origin: nil)
        }
        var kept: [UInt16] = []
        var origin: [Int] = []
        var last: Int = 0
        for comment in comments {
            var index: Int = last
            while index < comment.start {
                kept.append(units[index])
                origin.append(index)
                index += 1
            }
            last = comment.end
        }
        var index: Int = last
        while index < units.count {
            kept.append(units[index])
            origin.append(index)
            index += 1
        }
        origin.append(units.count)
        return (units: kept, origin: origin)
    }

    /// Where the next `%%` starts, at or after `start`.
    private static func doublePercent(in units: [UInt16], from start: Int) -> Int? {
        var index: Int = start
        while index + 1 < units.count {
            if units[index] == FigureFenceScan.percent && units[index + 1] == FigureFenceScan.percent {
                return index
            }
            index += 1
        }
        return nil
    }

    /// The 1-based line holding `offset` in the page as given.
    private static func lineNumber(of offset: Int, in units: [UInt16]) -> Int {
        var line: Int = 1
        var index: Int = 0
        while index < offset && index < units.count {
            if units[index] == FigureFenceScan.newline {
                line += 1
            }
            index += 1
        }
        return line
    }

    private static func isSpaceOrTab(_ unit: UInt16) -> Bool {
        return unit == FigureFenceScan.space || unit == FigureFenceScan.tab
    }

    /// `_WHITESPACE`: ASCII only, so every language agrees.
    private static func isRuleWhitespace(_ unit: UInt16) -> Bool {
        return unit == FigureFenceScan.space || unit == FigureFenceScan.tab || unit == FigureFenceScan.carriageReturn
            || unit == FigureFenceScan.formFeed || unit == FigureFenceScan.verticalTab
    }

    private static func isBlank(_ units: [UInt16], from start: Int, to end: Int) -> Bool {
        var index: Int = start
        while index < end {
            if !FigureFenceScan.isRuleWhitespace(units[index]) {
                return false
            }
            index += 1
        }
        return true
    }

    private static func holdsABacktick(_ units: [UInt16], from start: Int, to end: Int) -> Bool {
        var index: Int = start
        while index < end {
            if units[index] == FigureFenceScan.backtick {
                return true
            }
            index += 1
        }
        return false
    }

    private static func afterSpacesAndTabs(_ units: [UInt16], from start: Int, to end: Int) -> Int {
        var index: Int = start
        while index < end && FigureFenceScan.isSpaceOrTab(units[index]) {
            index += 1
        }
        return index
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        return unit >= FigureFenceScan.zero && unit <= FigureFenceScan.nine
    }

    /// `_QUOTE_MARKERS`: `^(?:[ \t]*>)+ ?` — how many `>` open the line, and
    /// where its body starts.
    private static func quoteDepthAndBody(_ units: [UInt16], from start: Int, to end: Int) -> (depth: Int, bodyStart: Int) {
        var depth: Int = 0
        var position: Int = start
        while true {
            let next: Int = FigureFenceScan.afterSpacesAndTabs(units, from: position, to: end)
            if next < end && units[next] == FigureFenceScan.greaterThan {
                depth += 1
                position = next + 1
                continue
            }
            break
        }
        if depth == 0 {
            return (depth: 0, bodyStart: start)
        }
        if position < end && units[position] == FigureFenceScan.space {
            position += 1
        }
        return (depth: depth, bodyStart: position)
    }

    /// `_strip_quote_markers`: the first `depth` markers (and one space after
    /// each) taken off; a deeper `>` is the code's own text.
    private static func afterQuoteMarkers(_ units: [UInt16], from start: Int, to end: Int, depth: Int) -> Int {
        var position: Int = start
        var taken: Int = 0
        while taken < depth {
            let scan: Int = FigureFenceScan.afterSpacesAndTabs(units, from: position, to: end)
            if scan >= end || units[scan] != FigureFenceScan.greaterThan {
                break
            }
            position = scan + 1
            if position < end && units[position] == FigureFenceScan.space {
                position += 1
            }
            taken += 1
        }
        return position
    }

    /// `_FENCE`: `^[ \t]*(`{3,}|~{3,})(.*)$`.
    private static func fenceRun(_ units: [UInt16], from start: Int, to end: Int) -> FenceRun? {
        let runStart: Int = FigureFenceScan.afterSpacesAndTabs(units, from: start, to: end)
        if runStart >= end {
            return nil
        }
        let character: UInt16 = units[runStart]
        if character != FigureFenceScan.backtick && character != FigureFenceScan.tilde {
            return nil
        }
        var runEnd: Int = runStart
        while runEnd < end && units[runEnd] == character {
            runEnd += 1
        }
        if runEnd - runStart < 3 {
            return nil
        }
        return FenceRun(character: character, length: runEnd - runStart, restStart: runEnd)
    }

    /// The end of a bullet or number marker and the spaces after it, when
    /// there is one: `[-*+]` or one to nine digits and `.` or `)`, then at
    /// least one space or tab. `leadingSpaces` allows `[ \t]*` first.
    private static func markerEnd(_ units: [UInt16], from start: Int, to end: Int, leadingSpaces: Bool) -> Int? {
        var position: Int = leadingSpaces ? FigureFenceScan.afterSpacesAndTabs(units, from: start, to: end) : start
        if position >= end {
            return nil
        }
        let first: UInt16 = units[position]
        if first == FigureFenceScan.hyphen || first == FigureFenceScan.asterisk || first == FigureFenceScan.plus {
            position += 1
        } else if FigureFenceScan.isDigit(first) {
            var digits: Int = 0
            while position < end && FigureFenceScan.isDigit(units[position]) {
                digits += 1
                position += 1
            }
            if digits > 9 || position >= end {
                return nil
            }
            if units[position] != FigureFenceScan.period && units[position] != FigureFenceScan.closingParenthesis {
                return nil
            }
            position += 1
        } else {
            return nil
        }
        if position >= end || !FigureFenceScan.isSpaceOrTab(units[position]) {
            return nil
        }
        return FigureFenceScan.afterSpacesAndTabs(units, from: position, to: end)
    }

    /// `_LIST_MARKER`, on a line's body.
    private static func listMarkerEnd(_ units: [UInt16], from start: Int, to end: Int) -> Int? {
        return FigureFenceScan.markerEnd(units, from: start, to: end, leadingSpaces: true)
    }

    /// `_NESTED_CONTAINER`: a second marker, or `>` and one optional space or
    /// tab, straight after the first marker.
    private static func nestedContainer(_ units: [UInt16], from start: Int, to end: Int) -> (end: Int, isQuote: Bool)? {
        if let afterMarker = FigureFenceScan.markerEnd(units, from: start, to: end, leadingSpaces: false) {
            return (end: afterMarker, isQuote: false)
        }
        if start < end && units[start] == FigureFenceScan.greaterThan {
            var position: Int = start + 1
            if position < end && FigureFenceScan.isSpaceOrTab(units[position]) {
                position += 1
            }
            return (end: position, isQuote: true)
        }
        return nil
    }

    /// The info string's first word: the rest of the fence line with ASCII
    /// whitespace trimmed (`strip(_WHITESPACE)`), then split at Python's
    /// whitespace (`split(None, 1)`).
    private static func firstWord(_ units: [UInt16], from start: Int, to end: Int) -> String {
        var first: Int = start
        var last: Int = end
        while first < last && FigureFenceScan.isRuleWhitespace(units[first]) {
            first += 1
        }
        while last > first && FigureFenceScan.isRuleWhitespace(units[last - 1]) {
            last -= 1
        }
        let info: String = String(decoding: units[first..<last], as: UTF16.self)
        var word: String.UnicodeScalarView = String.UnicodeScalarView()
        var started: Bool = false
        for scalar in info.unicodeScalars {
            let isSpace: Bool = FigureFenceScan.pythonWhitespace.contains(scalar.value)
            if isSpace {
                if started {
                    break
                }
                continue
            }
            started = true
            word.append(scalar)
        }
        return String(word)
    }
}
