import Foundation

/// What the built website does with a page — the only question this reader is
/// trying to answer.
///
/// `cannotTell` is not a fourth kind of visibility. It is this reader saying
/// that a key IS on the page and it will not guess what the build makes of it.
/// What happens next depends on who asked: something REPORTING to a teacher
/// treats it as visible, because the one mistake that must never be made is
/// calling a page hidden while students are reading it; something WRITING to
/// the page never treats it as anything at all, and writes the flag out in
/// full instead.
nonisolated enum PageVisibilityAnswer: Equatable {

    /// The page carries no key this section's build would look at.
    case saysNothing

    /// The build publishes this page.
    case visible

    /// The build holds this page back.
    case hidden

    /// There is a key, and this reader will not claim to know what it means.
    case cannotTell
}

/// Whether the built site shows a page, read from the teacher's own text.
///
/// **The rule is the BUILD'S rule, not YAML's and not Quartz's.** A page never
/// reaches Quartz as the teacher typed it: `scripts/build_site.py` →
/// `process_frontmatter` loads it with python-frontmatter (PyYAML, YAML 1.1),
/// resolves this section's per-section keys onto a plain `publish:`, and
/// writes it back out. Quartz then parses THAT with js-yaml on its JSON
/// schema, and `patches/publish.ts` drops the page only when the value it gets
/// is the boolean false or the exact string `"false"`.
///
/// Three consequences fall out of the round trip, and each of them is a page a
/// hand-rolled reader gets wrong in the direction that matters:
///
/// * `publish: no` and `publish: off` HIDE the page — PyYAML reads YAML 1.1's
///   nine spellings of no as the boolean, and writes `false` back.
/// * `publish: true # why` PUBLISHES it, because the comment is gone by the
///   time Quartz looks. So does `publish: maybe`, and anything else PyYAML
///   cannot make a boolean of: it becomes a string, and a string that is not
///   `"false"` is not `"false"`.
/// * Case matters, and it matters in opposite directions on either side of the
///   round trip. `publish: FALSE` hides the page (PyYAML resolves it, and
///   writes lowercase `false`), while `publish: "False"` does NOT (the quotes
///   keep it a string, and `publish.ts` compares strings exactly).
///
/// The measured table, what was rejected, and the versions it was measured
/// against are in `documentation/08-course-config-reference.md`.
///
/// **Which key answers is decided by the BUILD ORDER, never by where the page
/// lives.** `process_frontmatter` consults `publishForSection<N>`, then
/// `publish`, then `draftSection<N>`, then `draft`, on every page it copies,
/// wherever that page came from. So this reader walks all four in that order
/// too. A page's folder decides which key is WRITTEN — that is
/// `AssistPageVisibility.setting`'s business — and nothing else.
nonisolated enum PageVisibilityReader {

    // One key's value, and one page's frontmatter — the two small shapes the
    // functions below pass between themselves.

    /// One key's value, as far as this reader is willing to read it.
    enum ScalarReading: Equatable {

        /// A plain value, with whether the teacher put quotes around it —
        /// which changes the answer, because quotes stop PyYAML resolving
        /// `no` or `false` into a boolean.
        case text(value: String, wasQuoted: Bool)

        /// YAML this reader will not guess at.
        case cannotTell
    }

    /// A page's frontmatter, or why there is none to read.
    enum FrontmatterBlock: Equatable {

        /// No opening fence: an ordinary Markdown page with no metadata.
        case noFrontmatter

        /// Where the fences are, and the lines between them.
        case lines(openIndex: Int, closeIndex: Int, inside: [String])

        /// There IS a fence, and what follows it is not something this reader
        /// should answer about — an opening fence with no closing one, or a
        /// block indented with tabs, which the build itself cannot parse (and,
        /// since #246, hides and names rather than stopping on).
        case unreadable
    }

    // MARK: - Functions

    /// YAML 1.1's nine spellings of yes, as PyYAML resolves them. Written out
    /// one per line so the table can be read off rather than inferred: these
    /// are exactly the spellings, and case matters — `tRue` is not here, and
    /// PyYAML leaves it an ordinary string.
    static func isYamlTrue(_ value: String) -> Bool {
        if value == "true" { return true }
        if value == "True" { return true }
        if value == "TRUE" { return true }
        if value == "yes" { return true }
        if value == "Yes" { return true }
        if value == "YES" { return true }
        if value == "on" { return true }
        if value == "On" { return true }
        if value == "ON" { return true }
        return false
    }

    /// YAML 1.1's nine spellings of no. Note what is NOT here: `n`, `N`, `0`
    /// and `off ` with anything after it. PyYAML deliberately does not read
    /// single-letter `y`/`n` as booleans, so `publish: n` is the string "n"
    /// and the page is published.
    static func isYamlFalse(_ value: String) -> Bool {
        if value == "false" { return true }
        if value == "False" { return true }
        if value == "FALSE" { return true }
        if value == "no" { return true }
        if value == "No" { return true }
        if value == "NO" { return true }
        if value == "off" { return true }
        if value == "Off" { return true }
        if value == "OFF" { return true }
        return false
    }

    /// What the build does with this page, in this section.
    static func answer(in pageText: String, forSection sectionNumber: Int) -> PageVisibilityAnswer {
        let block: FrontmatterBlock = frontmatterBlock(in: pageText)
        switch block {
        case .noFrontmatter:
            return .saysNothing
        case .unreadable:
            return .cannotTell
        case .lines(_, _, let inside):
            return answer(inFrontmatterLines: inside, forSection: sectionNumber)
        }
    }

    /// The same question, asked of the frontmatter lines on their own.
    static func answer(inFrontmatterLines lines: [String], forSection sectionNumber: Int) -> PageVisibilityAnswer {
        for key in keysInBuildOrder(forSection: sectionNumber) {
            guard let entry = lastTopLevelEntry(forKey: key.name, in: lines) else {
                continue
            }
            let scalar: ScalarReading = reading(ofValue: entry.value, followedBy: entry.nextLine)
            if key.isDraftFamily {
                return answerFromDraftFamily(scalar)
            }
            return answerFromPublishFamily(scalar)
        }

        // No key of this page's own, but one of the four names appears
        // indented — nested inside some other mapping, or inside a block of
        // text. It may be nothing to do with this page, and it may be
        // everything; either way this reader is not the one to decide.
        for key in keysInBuildOrder(forSection: sectionNumber) {
            if hasIndentedLine(forKey: key.name, in: lines) {
                return .cannotTell
            }
        }
        return .saysNothing
    }

    /// The four keys the build consults, in the order it consults them. A key
    /// naming ANOTHER section is not on this list, because the build deletes
    /// it without reading it.
    static func keysInBuildOrder(forSection sectionNumber: Int) -> [(name: String, isDraftFamily: Bool)] {
        return [
            (name: "publishForSection\(sectionNumber)", isDraftFamily: false),
            (name: "publish", isDraftFamily: false),
            (name: "draftSection\(sectionNumber)", isDraftFamily: true),
            (name: "draft", isDraftFamily: true),
        ]
    }

    /// What `publish:` and `publishForSection<N>:` mean.
    ///
    /// The value reaches Quartz as whatever PyYAML made of it, and
    /// `patches/publish.ts` holds the page back for exactly two of those: the
    /// boolean false, and the string `"false"` spelled that way and no other.
    static func answerFromPublishFamily(_ scalar: ScalarReading) -> PageVisibilityAnswer {
        switch scalar {
        case .cannotTell:
            return .cannotTell
        case .text(let value, let wasQuoted):
            if wasQuoted {
                // Quoted, so PyYAML keeps it a string and hands that string
                // on. `"false"` is the one string that hides a page;
                // `"False"` is a page students CAN see, which looks like a
                // typo and is the measured behaviour.
                if value == "false" {
                    return .hidden
                }
                return .visible
            }
            if isYamlFalse(value) {
                return .hidden
            }
            // Everything else — `true`, `maybe`, `0`, `oN`, nothing at all —
            // is published. Forgetting the flag, or writing something the
            // build cannot make a boolean of, leaves a page visible.
            return .visible
        }
    }

    /// What `draft:` and `draftSection<N>:` mean — the older spelling, with
    /// the OPPOSITE polarity.
    ///
    /// The build asks `build_site.py` → `_as_bool` whether the page is a
    /// draft: a real boolean counts as itself, and anything else is turned
    /// into text, trimmed and lowercased, and compared with "true". So an
    /// unquoted `yes` hides the page and a quoted `"yes"` does not, while
    /// `TrUe` hides it either way.
    static func answerFromDraftFamily(_ scalar: ScalarReading) -> PageVisibilityAnswer {
        switch scalar {
        case .cannotTell:
            return .cannotTell
        case .text(let value, let wasQuoted):
            if !wasQuoted && isYamlTrue(value) {
                return .hidden
            }
            let asText: String = value.trimmingCharacters(in: .whitespaces).lowercased()
            if asText == "true" {
                return .hidden
            }
            return .visible
        }
    }

    /// Can this value be copied onto another key's line exactly as written?
    ///
    /// Anything a teacher fits on one line can: copying the characters means
    /// the build makes the same thing of the copy as it made of the original,
    /// whatever that turns out to be, and no reader can invert it by
    /// misreading it. A value that CONTINUES onto the next line cannot — the
    /// copy would be a key with nothing after it, which is a different page,
    /// and for a block scalar it is YAML the build cannot read at all.
    static func isCompleteOnItsOwnLine(_ rawValue: String) -> Bool {
        let value: String = trimmingYAMLSpaces(rawValue)
        if value.isEmpty {
            return false
        }
        if value.hasPrefix("|") || value.hasPrefix(">") {
            return false
        }
        return true
    }

    /// A string without the spaces and tabs at either end of it, and without a
    /// Windows line ending's carriage return.
    ///
    /// Written out rather than using `trimmingCharacters(in: .whitespaces)`,
    /// which strips every Unicode space — including the non-breaking space
    /// Option-Space types on a Mac. YAML's whitespace is a space and a tab and
    /// nothing else, so `publish: false<NBSP>` is the STRING "false\u{00A0}"
    /// to the build and the page is published. Trimming it here would have
    /// called that page hidden.
    static func trimmingYAMLSpaces(_ text: String) -> String {
        var trimmed: Substring = Substring(PageFrontmatter.trimmingCarriageReturn(text))
        while trimmed.first == " " || trimmed.first == "\t" {
            trimmed = trimmed.dropFirst()
        }
        while trimmed.last == " " || trimmed.last == "\t" {
            trimmed = trimmed.dropLast()
        }
        return String(trimmed)
    }

    /// Everything after a key's colon, read.
    ///
    /// `nextLine` is the first line below the key that could be a VALUE — blank
    /// lines and `# note`s at any indent have already been stepped over by
    /// `firstNonBlankLine` — or nil when there is none before the end of the
    /// block. A value that CONTINUES onto that line is one this reader will not
    /// follow, **however complete the key's own line looks**.
    static func reading(ofValue rawValue: String, followedBy nextLine: String?) -> ScalarReading {
        let value: String = trimmingYAMLSpaces(rawValue)

        // A value CONTINUES onto the next line whenever the first line that
        // could be one is INDENTED — and that is true whatever is on the key's
        // own line.
        //
        // `publish:` alone is null, and null publishes the page, UNLESS the
        // value is sitting below it. But so is `publish: false` with an
        // indented `false` under it: YAML folds the two into the one plain
        // scalar "false false", a STRING that is not "false", and the page is
        // PUBLISHED. Measured 2026-09-19, python-frontmatter 1.3.0 / PyYAML
        // 6.0.3 — `no`, `off`, `FALSE` and `maybe` behave the same way, and so
        // does a blank line between the two.
        //
        // Reading the key's line alone called every one of those pages HIDDEN,
        // and called it CONFIDENTLY — which is the part that bit.
        // `AssistPageVisibility.setting`'s "already right, change nothing" gate
        // believed it and returned before the writer ran at all, so "hide this
        // page" was a no-op the teacher was told had worked while students went
        // on reading it. A sweep in the writer cannot save a page the writer is
        // never asked to write.
        if let below = nextLine, below.hasPrefix(" ") || below.hasPrefix("\t") {
            return .cannotTell
        }

        if value.isEmpty {
            // Nothing after the colon and nothing below it: a genuine null,
            // and a null publishes the page.
            return .text(value: "", wasQuoted: false)
        }

        // A tag (`!!str false`), an anchor (`&flag false`), an alias (`*flag`)
        // or a block scalar (`>-` and the value on the next line) all change
        // what the value IS, and a flow collection (`[false]`) can run over
        // several lines. Each of them has been measured, and each of them is
        // rarer than the chance of getting it wrong here.
        guard let first = value.first else {
            return .text(value: "", wasQuoted: false)
        }
        if first == "!" || first == "&" || first == "*" || first == "|" || first == ">" {
            return .cannotTell
        }
        if first == "[" || first == "{" {
            return .cannotTell
        }
        // Characters YAML reserves, and a sequence entry on the key's own
        // line. Measured: `publish: %`, `publish: @x`, `` publish: `x `` and
        // `publish: - false` each STOP THE BUILD, so there is no site verdict
        // to mirror and this reader must not offer one.
        if first == "%" || first == "@" || first == "`" {
            return .cannotTell
        }
        if value == "-" || value.hasPrefix("- ") {
            return .cannotTell
        }

        let withoutComment: String = trimmingYAMLSpaces(strippingComment(from: value))
        if withoutComment.isEmpty {
            // The whole value was a comment, so the key is null.
            return .text(value: "", wasQuoted: false)
        }

        if withoutComment.hasPrefix("\"") {
            guard withoutComment.count >= 2, withoutComment.hasSuffix("\"") else {
                return .cannotTell
            }
            let inside: String = String(withoutComment.dropFirst().dropLast())
            // A backslash is an escape and a second quote is a second string;
            // either way the characters here are not the value.
            if inside.contains("\\") || inside.contains("\"") {
                return .cannotTell
            }
            return .text(value: inside, wasQuoted: true)
        }

        if withoutComment.hasPrefix("'") {
            guard withoutComment.count >= 2, withoutComment.hasSuffix("'") else {
                return .cannotTell
            }
            let inside: String = String(withoutComment.dropFirst().dropLast())
            // `''` is how a single-quoted string spells one quote.
            if inside.contains("'") {
                return .cannotTell
            }
            return .text(value: inside, wasQuoted: true)
        }

        // An unquoted value carrying its own `key: value` is a second mapping
        // where YAML expects a scalar. Measured: `publish: false: true` stops
        // the build.
        if withoutComment.contains(": ") || withoutComment.hasSuffix(":") {
            return .cannotTell
        }

        return .text(value: withoutComment, wasQuoted: false)
    }

    /// A value with its trailing `# comment` taken off.
    ///
    /// A `#` only starts a comment when it is outside quotes and something
    /// other than text comes before it — `publish: true#x` is the string
    /// "true#x", which was measured rather than assumed.
    static func strippingComment(from value: String) -> String {
        var kept: String = ""
        var openingQuote: Character? = nil
        var previous: Character? = nil
        for character in value {
            if let quote = openingQuote {
                if character == quote {
                    openingQuote = nil
                }
                kept.append(character)
                previous = character
                continue
            }
            if character == "\"" || character == "'" {
                openingQuote = character
                kept.append(character)
                previous = character
                continue
            }
            if character == "#" {
                let atStart: Bool = previous == nil
                let afterSpace: Bool = previous == " " || previous == "\t"
                if atStart || afterSpace {
                    return kept
                }
            }
            kept.append(character)
            previous = character
        }
        return kept
    }

    // Finding the key.

    /// A key's line inside the block: where it is, the text after its colon,
    /// and the first non-blank line below it. The LAST such line wins, because
    /// that is the one PyYAML keeps when a page carries the same key twice.
    static func lastTopLevelEntry(
        forKey key: String, in lines: [String]
    ) -> (index: Int, value: String, nextLine: String?)? {
        var found: (index: Int, value: String, nextLine: String?)? = nil
        for (index, line) in lines.enumerated() {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(line)
            if bare.hasPrefix(" ") || bare.hasPrefix("\t") {
                continue
            }
            guard let value = valuePart(ofKey: key, inLine: bare) else {
                continue
            }
            found = (index: index, value: value, nextLine: firstNonBlankLine(after: index, in: lines))
        }
        return found
    }

    /// A line YAML steps over while it is looking for a key's value: a blank
    /// one, or a `# note` at ANY indent.
    ///
    /// Shared by `firstNonBlankLine` and by `continuationLineIndices`, because
    /// a reader and a writer that step differently are how this file's oldest
    /// bug class starts. Measured: `publish:` over a COLUMN-0 `# note` over an
    /// indented `false` is HIDDEN, and a sweeper that stopped at that comment
    /// orphaned the value and stopped the build. Windows shipped exactly that
    /// bug on 2026-09-19 and fixed it the same day.
    static func isSteppedOverLookingForAValue(_ line: String) -> Bool {
        let content: String = trimmingYAMLSpaces(PageFrontmatter.trimmingCarriageReturn(line))
        if content.isEmpty {
            return true
        }
        return content.hasPrefix("#")
    }

    /// The first line below this one that could be a VALUE, or nil when there
    /// is none before the end of the block.
    ///
    /// Blank lines and comment lines are skipped, because YAML skips them: a
    /// value indented under its key still belongs to that key with an empty
    /// line or a `# note` in between. Both measured — `publish:` followed by
    /// an indented comment is a null and PUBLISHES the page, while the same
    /// comment with an indented `false` under it hides it.
    ///
    /// The stepping itself is `isSteppedOverLookingForAValue`, which
    /// `continuationLineIndices` — the WRITER's half of the same question —
    /// also uses. The name is a small lie inherited from before comments were
    /// stepped over too; it is kept because four places name it and renaming
    /// it would buy nothing a teacher can see.
    static func firstNonBlankLine(after index: Int, in lines: [String]) -> String? {
        var position: Int = index + 1
        while position < lines.count {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(lines[position])
            if !isSteppedOverLookingForAValue(bare) {
                return bare
            }
            position += 1
        }
        return nil
    }

    /// The lines BELOW a key that are part of its value, and so have to go
    /// wherever the key's line goes.
    ///
    /// **Leaving them behind is the failure that reports success.**
    /// `publish: >-` with `  false` under it is HIDDEN on the site; rewriting
    /// the key's line alone orphans that `  false` onto the new value, and
    /// PyYAML folds the two into the multi-line plain scalar "false false" — a
    /// string that is not "false", so the page is PUBLISHED while the teacher
    /// is told it was hidden. When the orphan is a MAPPING, a column-0 comment
    /// or a column-0 sequence the build cannot parse the page instead — which
    /// stopped the build until #246 and hides the page since. All measured
    /// 2026-09-19, python-frontmatter 1.3.0 / PyYAML 6.0.3 / CPython 3.11.15,
    /// then js-yaml on `JSON_SCHEMA` and `patches/publish.ts`.
    ///
    /// The rule is `setup_course.per_section_frontmatter`'s and Windows'
    /// `PageFrontmatter.ContinuationLines`': walk forward, STEP OVER blank
    /// lines and `# note`s at any indent, stop at the first line that is not
    /// indented, and take everything up to the last indented line that was not
    /// a comment. So a complete value followed by an indented note keeps the
    /// note — nothing is taken, because no value line was found below it —
    /// while a note with a real value under it goes WITH the value, which is
    /// what the reader sees through it anyway.
    ///
    /// `keyValueWasEmpty` covers the one continuation that is NOT indented: a
    /// block sequence at column 0 under a key with no value of its own.
    /// Measured, `publish:` over `- a` is the list `['a']` and the page is
    /// published, and leaving the `- a` after a hide makes a block the build
    /// cannot parse (it stopped the build until #246, and hides the page and
    /// names it since). A sequence under a key that HAS a value is a page the
    /// build cannot parse either way, so there is nothing to rescue and sweeping a teacher's list
    /// on that guess would be the larger mistake.
    ///
    /// Ask it BEFORE the key's line is rewritten: the rewrite always puts a
    /// value there, so asking afterwards always answers false.
    ///
    /// This does NOT parse block scalars and must not start to: it only finds
    /// where a value ends.
    static func continuationLineIndices(
        belowKeyAt keyIndex: Int,
        in lines: [String],
        closeIndex: Int,
        keyValueWasEmpty: Bool
    ) -> [Int] {
        var lastValueLine: Int = keyIndex
        var position: Int = keyIndex + 1
        while position < closeIndex && position < lines.count {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(lines[position])
            if isSteppedOverLookingForAValue(bare) {
                position += 1
                continue
            }
            let isIndented: Bool = bare.hasPrefix(" ") || bare.hasPrefix("\t")
            if !isIndented {
                if !keyValueWasEmpty {
                    break
                }
                let content: String = trimmingYAMLSpaces(bare)
                if content != "-" && !content.hasPrefix("- ") {
                    break
                }
            }
            lastValueLine = position
            position += 1
        }

        var taken: [Int] = []
        var index: Int = keyIndex + 1
        while index <= lastValueLine {
            taken.append(index)
            index += 1
        }
        return taken
    }

    /// Does one of the four names appear INDENTED anywhere in the block?
    static func hasIndentedLine(forKey key: String, in lines: [String]) -> Bool {
        for line in lines {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(line)
            guard bare.hasPrefix(" ") || bare.hasPrefix("\t") else {
                continue
            }
            let withoutIndent: String = String(
                bare.drop(while: { character in character == " " || character == "\t" })
            )
            if valuePart(ofKey: key, inLine: withoutIndent) != nil {
                return true
            }
        }
        return false
    }

    /// Everything after this key's colon on this line, or nil when the line
    /// names some other key.
    ///
    /// Three spellings of the key itself are accepted, because all three are
    /// the same key to YAML and each is cheap to recognise: `publish:`,
    /// `publish :` and `"publish":`. `publishForSection1:` is NOT `publish:`,
    /// which is why the colon has to be found rather than assumed.
    ///
    /// And the colon must be FOLLOWED by a space, a tab or the end of the
    /// line, because that is what makes the line a mapping at all. Measured:
    /// `publish:false` is one plain scalar, so a page whose whole frontmatter
    /// is that line arrives at Quartz with no keys and is PUBLISHED — and a
    /// page with another key beside it cannot be parsed at all (it stopped
    /// the build until #246; since then the build hides it). Either way it is not
    /// this page's flag, and reading it as one called a live page hidden.
    static func valuePart(ofKey key: String, inLine line: String) -> String? {
        var rest: Substring = Substring(line)
        if rest.hasPrefix("\"" + key + "\"") {
            rest = rest.dropFirst(key.count + 2)
        } else if rest.hasPrefix("'" + key + "'") {
            rest = rest.dropFirst(key.count + 2)
        } else if rest.hasPrefix(key) {
            rest = rest.dropFirst(key.count)
        } else {
            return nil
        }
        while rest.first == " " || rest.first == "\t" {
            rest = rest.dropFirst()
        }
        guard rest.first == ":" else {
            return nil
        }
        rest = rest.dropFirst()
        if let afterColon = rest.first, afterColon != " ", afterColon != "\t" {
            return nil
        }
        return String(rest)
    }

    // Finding the block.

    /// Is this line the CLOSING fence of a page's frontmatter?
    ///
    /// Three dashes OR MORE, with nothing after them but spaces and tabs and
    /// **nothing before them at all**. That is python-frontmatter's own
    /// boundary, `^-{3,}\s*$`, matched with `re.MULTILINE` against the text of
    /// the whole page — so `^` is the start of a LINE, there is no room for
    /// whitespace in front of the dashes, and a line of INDENTED dashes is not
    /// a fence at all: it is part of the value above it. A page fenced with
    /// `----` really does have frontmatter, and reading it as an ordinary page
    /// said a hidden page was visible.
    ///
    /// Until issue #188 this trimmed LEADING spaces and tabs too. Measured:
    /// `publish: false` over `  ---` is the plain scalar `"false ---"` and the
    /// site PUBLISHES the page, while this reader ended the block at the
    /// `  ---`, saw a complete `false` and answered `hidden` — confidently, so
    /// `AssistPageVisibility.setting`'s already-right gate made "hide this
    /// page" a no-op while students went on reading it. On a course page the
    /// same shape let adding a section split section 1's key from its value.
    ///
    /// The whole argument in one number: `fenceIndices`, with this test for
    /// the close and `isOpeningFence` for the open, was compared page by page
    /// against python-frontmatter's own `detect`/`split` over 3,000 generated
    /// pages (indents, tabs, dash counts, trailing whitespace, CRLF, leading
    /// blank lines, dashes inside values) and **disagreed 0 times**; the
    /// version that trimmed both ends disagreed 1,316 times. The generator is
    /// `research/frontmatter-fences/fuzz_fences.py`.
    /// [Issue #188](https://github.com/russellgordon/plantoir/issues/188).
    static func isFence(_ line: String) -> Bool {
        let bare: String = trimmingTrailingYAMLSpaces(line)
        if bare.count < 3 {
            return false
        }
        for character in bare {
            if character != "-" {
                return false
            }
        }
        return true
    }

    /// A string without the spaces and tabs at the END of it, and without a
    /// Windows line ending's carriage return. The leading end is deliberately
    /// left alone — see `isFence`, which is the one caller that needs the
    /// difference.
    static func trimmingTrailingYAMLSpaces(_ text: String) -> String {
        var trimmed: Substring = Substring(PageFrontmatter.trimmingCarriageReturn(text))
        while trimmed.last == " " || trimmed.last == "\t" {
            trimmed = trimmed.dropLast()
        }
        return String(trimmed)
    }

    /// Is this the line that OPENS a page's frontmatter?
    ///
    /// The same dashes, but indentation IS allowed here, and the asymmetry is
    /// measured rather than chosen: `frontmatter.parse` does `text.strip()` on
    /// the WHOLE document before it tests anything, so the whitespace in front
    /// of the first line — blank lines and the indent of the fence itself — is
    /// gone by the time `^-{3,}\s*$` looks at it. Measured:
    /// `  ---` / `publish: false` / `---` is HIDDEN on the site, and so is the
    /// tab-indented form.
    ///
    /// Reading it the strict way would be worse than wrong. This app would see
    /// no block on such a page, and `AssistPageVisibility.setting` would
    /// PREPEND one of its own — leaving the teacher's real frontmatter behind
    /// it as body text printed to their students, which is the bug #140 fixed.
    /// A symmetric "never indented" finder was measured and REJECTED for
    /// exactly that reason.
    static func isOpeningFence(_ line: String) -> Bool {
        return isFence(trimmingYAMLSpaces(line))
    }

    /// Where this page's frontmatter is.
    ///
    /// Leading blank lines are skipped before the opening fence:
    /// python-frontmatter accepts them, so the build reads the block and this
    /// reader had better read the same one.
    static func frontmatterBlock(in pageText: String) -> FrontmatterBlock {
        guard let fences = fenceIndices(in: pageText) else {
            return pageTextOpensAFence(pageText) ? .unreadable : .noFrontmatter
        }
        let lines: [String] = pageText.components(separatedBy: "\n")
        var inside: [String] = []
        for position in (fences.openIndex + 1)..<fences.closeIndex {
            inside.append(lines[position])
        }
        // A tab used as INDENTATION is the one thing YAML forbids outright:
        // the build's own parser throws on it. Until #246 that stopped the
        // whole build; since #246 the build hides the page and names it, so
        // the site's verdict is hidden and reporting it visible is the mild
        // direction, announced by the build's own finding.
        for line in inside {
            if PageFrontmatter.trimmingCarriageReturn(line).hasPrefix("\t") {
                return .unreadable
            }
        }
        return .lines(openIndex: fences.openIndex, closeIndex: fences.closeIndex, inside: inside)
    }

    /// Where a page's two fences are, whatever is between them.
    ///
    /// Separate from `frontmatterBlock` because a WRITER still needs to find
    /// the block on a page the build cannot parse: editing the line in place
    /// leaves the teacher's own frontmatter where they put it, while treating
    /// the page as having none would prepend a second block and turn theirs
    /// into body text.
    static func fenceIndices(in pageText: String) -> (openIndex: Int, closeIndex: Int)? {
        let lines: [String] = pageText.components(separatedBy: "\n")
        var openIndex: Int = 0
        while openIndex < lines.count {
            if !trimmingYAMLSpaces(lines[openIndex]).isEmpty {
                break
            }
            openIndex += 1
        }
        guard openIndex < lines.count, isOpeningFence(lines[openIndex]) else {
            return nil
        }
        var index: Int = openIndex + 1
        while index < lines.count {
            if isFence(lines[index]) {
                return (openIndex: openIndex, closeIndex: index)
            }
            index += 1
        }
        return nil
    }

    /// True when the page starts with a fence that is never closed — there IS
    /// frontmatter here, and it is not something to answer about.
    static func pageTextOpensAFence(_ pageText: String) -> Bool {
        for line in pageText.components(separatedBy: "\n") {
            if trimmingYAMLSpaces(line).isEmpty {
                continue
            }
            return isOpeningFence(line)
        }
        return false
    }
}
