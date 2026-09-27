import Foundation

/// Pointing every link at a renamed page's new name.
///
/// Obsidian does this itself when OBSIDIAN performs the rename. Plantoir's
/// renames happen on disk, from another process — which Obsidian reads as a
/// delete and a create, leaving links exactly where they were — and Obsidian
/// may not be running at all. So it cannot be delegated: we rewrite the links,
/// or the teacher is left with a course full of links to pages that no longer
/// exist under those names.
///
/// What Obsidian IS good for is the list of forms that have to survive, and
/// all of them do, because the pattern stops at `#` and `|` and moves only the
/// page name between the brackets:
///
/// * `[[Unit 2, Day 3]]`
/// * `[[Unit 2, Day 3|the lesson on loops]]` — the alias is the teacher's own
///   words and is never touched
/// * `![[Unit 2, Day 3]]` — a transclusion
/// * `[[Unit 2, Day 3#Agenda]]`
/// * `[[Unit 2, Day 3#^a1b2c3]]`
/// * `[[Unit 2, Day 3\|Tuesday]]` — the alias pipe ESCAPED, which is how
///   Obsidian writes an alias inside a Markdown table, so that the cell does
///   not end at the pipe (#294). The same form turns up in prose too, and
///   Quartz reads it as a link wherever it is. The backslash is not part of
///   the name, and a rename leaves it exactly where it was: dropping it would
///   split the table cell in two
/// * and the combinations of those
///
/// ### Why the target stops BEFORE a backslash, and only there
///
/// The target is taken lazily up to — not including — an optional backslash
/// that sits immediately before `]`, `|` or `#`. The lookahead is zero-width,
/// so the backslash falls outside the match and every rewriter that replaces
/// the match (or group 2) carries it through untouched. Measured over the
/// 12,128 payload and skeleton pages: the same 38,659 links matched at the same offsets as
/// the old `([^\]|#]+)`, and 229 captures changed, every one a name that used
/// to end in the backslash of a `\|` (142 in tables, 87 in prose and in code
/// examples; 39,570 and 230 over all of `support/`).
///
/// Rejected:
/// * stripping the backslash in `AssistSectionGraph.linkTargets` alone —
///   publishing would follow the link, and a rename or a class insertion
///   would still leave it on the old name, which after an insertion is a
///   DIFFERENT lesson. Eight readers share this pattern; one fix covers them.
/// * excluding the backslash from names altogether (`[^\]|#\\]+`, closer to
///   Quartz's own `wikilinkRegex`) — `[[a\b]]` would then capture `a`, and a
///   rename of a page called `a` would rewrite it. The lookahead differs from
///   the old pattern only at a backslash right before `]`, `|` or `#`.
/// * skipping links inside code in the same change — decided since, by #313
///   (below), with its own measurement.
///
/// ### A link written inside code is not a link (#313)
///
/// A `[[…]]` whose opening brackets sit inside a fenced code block or an
/// inline code span is an EXAMPLE of a link, and Quartz draws none. So
/// `linkMatches(in:)` — the pattern's matches with the ones that start in
/// code taken out, by `MarkdownCode` — is THE one entry point: publishing,
/// the dates a class brings, the site check, "what does this page link to?",
/// copying, and this type's own `rewriting` and `countLinks`, which a page
/// rename, a unit-word rename and a class insertion all go through. The
/// REWRITERS skip code as well as the readers, on purpose: a rename plan
/// that counted a link publishing does not follow would promise something
/// untrue, and rewriting an example would edit what the teacher wrote.
/// Rejected: readers skip code and rewriters do not (two definitions of a
/// link again); each reader keeping its own stripper (how three came to
/// disagree — the links answer dropped 22 real ICS4U links on a `~~~` inside
/// a traceback). The rule is `contracts/shared-rules.json` →
/// `readingALink.whatIsCode`.
///
/// ## What is NOT handled
///
/// **Markdown-style links are not rewritten.** Obsidian can be set to write
/// `[the lesson on loops](Unit%202,%20Day%203.md)` instead of wikilinks, and a
/// link in that form will still point at the old name after a rename here.
/// Every page Plantoir ships uses wikilinks and the rest of the toolchain only
/// understands those, so a vault switched to Markdown links has larger problems
/// than this one — but it is a real gap, and it is written down here rather
/// than left to be discovered by whoever hits it.
///
/// `nonisolated`: pure over its arguments, and run off the main actor by the
/// unit-word rename, which rewrites every page of a course.
nonisolated enum WikiLinkRewriter {

    // MARK: - Stored properties

    /// An optional `!`, the opening brackets, then the target — which runs up
    /// to the first `]`, `|` or `#`, so an alias, a heading and a block
    /// reference are all left where they are. A backslash immediately before
    /// that character (the `\|` of an alias in a table) is not part of the
    /// target, and is not part of the match either. THE one definition of a
    /// link on the mac: `FolderPathRewriter`, `PageReferences` and
    /// `AssistSectionGraph` read this, not copies of it (#294).
    static let pattern: String = #"(!?\[\[)([^\]|#]+?)(?=\\?[\]|#])"#

    /// The pattern, compiled once.
    static let expression: NSRegularExpression? = try? NSRegularExpression(pattern: pattern)

    // MARK: - Functions

    /// Every link on a page, in order: the pattern's matches, less the ones
    /// that start inside code (#313). THE one entry point for every reader
    /// and rewriter of links on the mac — group 1 is `[[` or `![[`, group 2
    /// the name as written.
    static func linkMatches(in text: String) -> [NSTextCheckingResult] {
        guard let expression = WikiLinkRewriter.expression else {
            return []
        }
        return MarkdownCode.matches(of: expression, in: text, outside: MarkdownCode.ranges(in: text))
    }

    /// The text with every link to a renamed page pointing at its new name.
    /// Names are matched without regard to case, the way Obsidian resolves
    /// them, and after trimming the spaces some teachers leave inside the
    /// brackets.
    static func rewriting(_ text: String, renamedPages: [String: String]) -> String {
        if renamedPages.isEmpty {
            return text
        }

        var byLowercasedName: [String: String] = [:]
        for (from, to) in renamedPages {
            byLowercasedName[from.trimmingCharacters(in: .whitespaces).lowercased()] = to
        }

        let matches: [NSTextCheckingResult] = WikiLinkRewriter.linkMatches(in: text)

        var result: String = ""
        var carriedTo: String.Index = text.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let bracketsRange = Range(match.range(at: 1), in: text),
                  let targetRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            let target: String = String(text[targetRange]).trimmingCharacters(in: .whitespaces)
            guard let renamed = byLowercasedName[target.lowercased()] else {
                continue
            }
            result.append(contentsOf: text[carriedTo..<matchRange.lowerBound])
            result.append(String(text[bracketsRange]))
            result.append(renamed)
            carriedTo = matchRange.upperBound
        }
        result.append(contentsOf: text[carriedTo..<text.endIndex])
        return result
    }

    /// How many links in this text point at any of these page names. The
    /// number a plan reports, and the one a teacher could not check for
    /// themselves without opening every page in the course. Read with the
    /// same `linkMatches` as `rewriting`, so the count is exactly what the
    /// rewrite will move — a link shown inside code is neither (#313).
    static func countLinks(to names: [String], in text: String) -> Int {
        if names.isEmpty {
            return 0
        }
        var wanted: [String] = []
        for name in names {
            wanted.append(name.trimmingCharacters(in: .whitespaces).lowercased())
        }

        let matches: [NSTextCheckingResult] = WikiLinkRewriter.linkMatches(in: text)

        var total: Int = 0
        for match in matches {
            guard let targetRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            let target: String = String(text[targetRange]).trimmingCharacters(in: .whitespaces).lowercased()
            if wanted.contains(target) {
                total += 1
            }
        }
        return total
    }
}
