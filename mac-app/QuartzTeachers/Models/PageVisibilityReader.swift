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
        case .lines(let inside):
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
        let value: String = PageFrontmatter
            .trimmingCarriageReturn(rawValue)
            .trimmingCharacters(in: .whitespaces)
        if value.isEmpty {
            return false
        }
        if value.hasPrefix("|") || value.hasPrefix(">") {
            return false
        }
        return true
    }

    // MARK: - Reading one value

    /// One key's value, as far as this reader is willing to read it.
    enum ScalarReading: Equatable {

        /// A plain value, with whether the teacher put quotes around it —
        /// which changes the answer, because quotes stop PyYAML resolving
        /// `no` or `false` into a boolean.
        case text(value: String, wasQuoted: Bool)

        /// YAML this reader will not guess at.
        case cannotTell
    }

    /// Everything after a key's colon, read.
    ///
    /// `nextLine` is the line below it inside the same block, or nil at the
    /// end of the block: a key with nothing after the colon takes its value
    /// from there, and this reader does not follow it.
    static func reading(ofValue rawValue: String, followedBy nextLine: String?) -> ScalarReading {
        let value: String = PageFrontmatter
            .trimmingCarriageReturn(rawValue)
            .trimmingCharacters(in: .whitespaces)

        if value.isEmpty {
            // `publish:` on its own is null, and null publishes the page —
            // UNLESS the value is on the next line, indented under it, which
            // this reader does not follow.
            if let below = nextLine, below.hasPrefix(" ") || below.hasPrefix("\t") {
                if !below.trimmingCharacters(in: .whitespaces).isEmpty {
                    return .cannotTell
                }
            }
            return .text(value: "", wasQuoted: false)
        }

        // A tag (`!!str false`), an anchor (`&flag false`), an alias (`*flag`)
        // or a block scalar (`>-` and the value on the next line) all change
        // what the value IS, and a flow collection (`[false]`) can run over
        // several lines. Each of them has been measured, and each of them is
        // rarer than the chance of getting it wrong here.
        let first: Character = value.first!
        if first == "!" || first == "&" || first == "*" || first == "|" || first == ">" {
            return .cannotTell
        }
        if first == "[" || first == "{" {
            return .cannotTell
        }

        let withoutComment: String = strippingComment(from: value)
            .trimmingCharacters(in: .whitespaces)
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

    // MARK: - Finding the key

    /// A key's line inside the block: the text after its colon, and the line
    /// below it. The LAST such line wins, because that is the one PyYAML keeps
    /// when a page carries the same key twice.
    static func lastTopLevelEntry(forKey key: String, in lines: [String]) -> (value: String, nextLine: String?)? {
        var found: (value: String, nextLine: String?)? = nil
        for (index, line) in lines.enumerated() {
            let bare: String = PageFrontmatter.trimmingCarriageReturn(line)
            if bare.hasPrefix(" ") || bare.hasPrefix("\t") {
                continue
            }
            guard let value = valuePart(ofKey: key, inLine: bare) else {
                continue
            }
            var below: String? = nil
            if index + 1 < lines.count {
                below = PageFrontmatter.trimmingCarriageReturn(lines[index + 1])
            }
            found = (value: value, nextLine: below)
        }
        return found
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
        return String(rest.dropFirst())
    }

    // MARK: - Finding the block

    /// A page's frontmatter, or why there is none to read.
    enum FrontmatterBlock: Equatable {

        /// No opening fence: an ordinary Markdown page with no metadata.
        case noFrontmatter

        /// The lines between the fences.
        case lines(inside: [String])

        /// There IS a fence, and what follows it is not something this reader
        /// should answer about — an opening fence with no closing one, or a
        /// block indented with tabs, which the build itself cannot parse.
        case unreadable
    }

    /// Where this page's frontmatter is.
    ///
    /// Leading blank lines are skipped before the opening fence:
    /// python-frontmatter accepts them, so the build reads the block and this
    /// reader had better read the same one.
    static func frontmatterBlock(in pageText: String) -> FrontmatterBlock {
        let lines: [String] = pageText.components(separatedBy: "\n")
        var openIndex: Int = 0
        while openIndex < lines.count {
            let bare: String = PageFrontmatter
                .trimmingCarriageReturn(lines[openIndex])
                .trimmingCharacters(in: .whitespaces)
            if !bare.isEmpty {
                break
            }
            openIndex += 1
        }
        guard openIndex < lines.count else {
            return .noFrontmatter
        }
        let opening: String = PageFrontmatter
            .trimmingCarriageReturn(lines[openIndex])
            .trimmingCharacters(in: .whitespaces)
        guard opening == "---" else {
            return .noFrontmatter
        }

        var index: Int = openIndex + 1
        while index < lines.count {
            let bare: String = PageFrontmatter
                .trimmingCarriageReturn(lines[index])
                .trimmingCharacters(in: .whitespaces)
            if bare == "---" {
                var inside: [String] = []
                for position in (openIndex + 1)..<index {
                    inside.append(lines[position])
                }
                // A tab used as INDENTATION is the one thing YAML forbids
                // outright: the build's own parser throws on it and stops the
                // whole build, so there is no site verdict to mirror.
                for line in inside {
                    if PageFrontmatter.trimmingCarriageReturn(line).hasPrefix("\t") {
                        return .unreadable
                    }
                }
                return .lines(inside: inside)
            }
            index += 1
        }
        return .unreadable
    }
}
