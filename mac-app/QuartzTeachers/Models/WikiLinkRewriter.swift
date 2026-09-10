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
/// * and the combinations of those
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
    /// reference are all left where they are.
    static let pattern: String = #"(!?\[\[)([^\]|#]+)"#

    // MARK: - Functions

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

        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let whole: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches: [NSTextCheckingResult] = expression.matches(in: text, range: whole)

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
    /// themselves without opening every page in the course.
    static func countLinks(to names: [String], in text: String) -> Int {
        if names.isEmpty {
            return 0
        }
        var wanted: [String] = []
        for name in names {
            wanted.append(name.trimmingCharacters(in: .whitespaces).lowercased())
        }

        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }
        let whole: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches: [NSTextCheckingResult] = expression.matches(in: text, range: whole)

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
