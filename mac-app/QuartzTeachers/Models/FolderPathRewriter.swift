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
/// A Markdown destination ends at the first space, so a new name that has one
/// is percent-encoded on the way in and a wikilink's is not. That rule, and
/// what it is measured against, is in `spelled(_:likeThe:in:)`.
///
/// ## What is NOT handled, on purpose
///
/// A segment is replaced only when it matches the whole folder name. A folder
/// called `Tasks` does not rewrite `Extra Tasks/`, and a page whose own NAME is
/// `Tasks.md` is left alone — the match stops at the last `/`, so a file name
/// is never a candidate.
///
/// **Links to the web and absolute paths are refused explicitly**, by
/// `pointsOutsideTheCourse`, and NOT because "nothing in them is a segment of
/// this course's tree" — which is what this comment used to claim and is
/// exactly wrong. `https://example.com/Tasks/handout.pdf` has `Tasks` sitting
/// in it as an ordinary segment, and the walk below is blind to what a path
/// means, so a rename used to repoint that link at a page on somebody else's
/// website. Found by adversarial review, 2026-09-01.
enum FolderPathRewriter {

    // MARK: - Nested types

    /// Which of the two link styles a target was written in.
    ///
    /// The rewriter has to know, because the two spell the SAME folder name
    /// differently. `[[All Tasks/Quiz 1]]` is exactly how Obsidian writes a
    /// wikilink whose folder has a space in it, while `](All Tasks/Quiz 1.md)`
    /// is not a link at all — a Markdown destination ends at the first space.
    /// See `spelled(_:likeThe:in:)`, where the difference is decided.
    nonisolated enum LinkStyle {

        case wikiLink
        case markdown

        // MARK: - Computed properties

        /// The pattern that finds this style's targets.
        var pattern: String {
            switch self {
            case .wikiLink:
                return FolderPathRewriter.wikiLinkPattern
            case .markdown:
                return FolderPathRewriter.markdownLinkPattern
            }
        }

        /// The compiled form of that pattern, built once for the whole run.
        var expression: NSRegularExpression? {
            switch self {
            case .wikiLink:
                return FolderPathRewriter.wikiLinkExpression
            case .markdown:
                return FolderPathRewriter.markdownLinkExpression
            }
        }
    }

    // MARK: - Stored properties

    /// An optional `!`, the opening brackets, then the target — which runs up
    /// to the first `]`, `|` or `#`, so an alias, a heading and a block
    /// reference stay where they are. `WikiLinkRewriter`'s pattern, and the
    /// same one on purpose: two link finders that disagreed about what a link
    /// is would rewrite different halves of the same vault.
    nonisolated static let wikiLinkPattern: String = #"(!?\[\[)([^\]|#]+)"#

    /// A Markdown link or embed's target: everything between `](` and the
    /// closing bracket. Titles (`](path "title")`) are left in place because
    /// the path is taken only up to the first space.
    nonisolated static let markdownLinkPattern: String = #"(\]\()([^)\s]+)"#

    /// Compiled ONCE, not per file. A rename walks every page in the course
    /// and each page used to build four of these; the cost is small but it is
    /// the kind of per-file work that makes an O(files) walk worse than it
    /// needs to be, and these patterns are constants.
    nonisolated private static let wikiLinkExpression: NSRegularExpression? =
        try? NSRegularExpression(pattern: wikiLinkPattern)

    nonisolated private static let markdownLinkExpression: NSRegularExpression? =
        try? NSRegularExpression(pattern: markdownLinkPattern)

    /// The name percent-encoded so that Quartz gets the folder's real name
    /// back out of it.
    ///
    /// **The allowed set is not `urlPathAllowed`, and not .NET's
    /// `Uri.EscapeDataString` either — both were tried and both are wrong
    /// here.** Quartz v4.5.0 resolves an internal link with `decodeURI`
    /// (`quartz/util/path.ts`, `transformInternalLink`), and `decodeURI`
    /// deliberately leaves the reserved set `; / ? : @ & = + $ , #` still
    /// encoded. It then slugs what comes back, turning `&` into `-and-` and
    /// `%` into `-percent` (`sluggify`, same file). So a folder called
    /// `Tasks & Quizzes` written as `Tasks%20%26%20Quizzes` decodes to
    /// `Tasks %26 Quizzes` and slugs to `Tasks--percent26-Quizzes`, while the
    /// real folder slugs to `Tasks--and--Quizzes`: a 404 on the published
    /// site, and invisible in Obsidian, which decodes `%26` perfectly well.
    /// Measured against the running image on 2026-09-06.
    ///
    /// The set below is therefore what JavaScript's `encodeURI` leaves alone,
    /// minus the four that a Markdown destination or a slug cannot hold:
    /// `(` and `)` close the destination, `#` starts a heading and `?` a
    /// query. `/` and `:` are left out too — the rename sheet refuses both, so
    /// they cannot arrive, and encoding is the safer of the two ways to be
    /// wrong if that ever changes. Everything else — the space, `%`, the
    /// quotes and brackets, and every non-ASCII letter — is encoded, and
    /// `decodeURI` gives all of it back.
    nonisolated private static let charactersThatSurviveQuartzUndecoded: CharacterSet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789;,@&=+$-_.!~*'"
    )

    // MARK: - Functions

    /// The text with every qualified link to `oldName` pointing at `newName`.
    nonisolated static func rewriting(_ text: String, folderNamed oldName: String, to newName: String) -> String {
        let trimmedOld: String = oldName.trimmingCharacters(in: .whitespaces)
        let trimmedNew: String = newName.trimmingCharacters(in: .whitespaces)
        if trimmedOld.isEmpty || trimmedNew.isEmpty || trimmedOld == trimmedNew {
            return text
        }
        let afterWikiLinks: String = rewritingTargets(
            in: text, written: .wikiLink, folderNamed: trimmedOld, to: trimmedNew
        )
        return rewritingTargets(
            in: afterWikiLinks, written: .markdown, folderNamed: trimmedOld, to: trimmedNew
        )
    }

    /// How many qualified links in this text name the folder. Used to report
    /// what a rename touched, and to skip writing a file nothing changed in.
    nonisolated static func countReferences(to folderName: String, in text: String) -> Int {
        let trimmed: String = folderName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return 0
        }
        var total: Int = 0
        for style in [LinkStyle.wikiLink, LinkStyle.markdown] {
            for target in targets(in: text, written: style) {
                if pathNames(trimmed, in: target) {
                    total += 1
                }
            }
        }
        return total
    }

    // MARK: - Private helpers

    /// Every link target in the text, for one of the two link styles.
    nonisolated private static func targets(in text: String, written style: LinkStyle) -> [String] {
        guard let expression = style.expression else {
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
    nonisolated private static func rewritingTargets(
        in text: String, written style: LinkStyle, folderNamed oldName: String, to newName: String
    ) -> String {
        guard let expression = style.expression else {
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
            let rewritten: String = retargeting(target, folderNamed: oldName, to: newName, written: style)
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
    nonisolated private static func retargeting(
        _ target: String, folderNamed oldName: String, to newName: String, written style: LinkStyle
    ) -> String {
        if !target.contains("/") || pointsOutsideTheCourse(target) {
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
                rebuilt.append(spelled(newName, likeThe: segment, in: style))
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

    /// Whether a link target leads somewhere this rename has no business
    /// touching: the web, or an absolute path on the teacher's machine.
    ///
    /// **Found by review rather than by use, and it was a real bug.** The
    /// segment walk below is blind to what a path MEANS, so
    /// `https://example.com/Tasks/handout.pdf` had `Tasks` sitting in it as an
    /// ordinary segment, and renaming a folder called `Tasks` silently
    /// repointed the link at a page on somebody else's website. Folders called
    /// `Resources`, `Files`, `Notes` or `Assignments` make that likely rather
    /// than exotic. Nothing in a course's own tree is reached by an absolute
    /// path or a URL, so refusing both costs nothing.
    nonisolated private static func pointsOutsideTheCourse(_ target: String) -> Bool {
        if target.hasPrefix("/") || target.hasPrefix("#") {
            return true
        }
        // A scheme — http:, https:, mailto:, obsidian:, file: — is anything
        // before a colon that comes ahead of the first slash. Tested that way
        // rather than against a list of schemes, because the list is open and
        // a missed one silently rewrites somebody's link.
        guard let colon = target.firstIndex(of: ":") else {
            return false
        }
        if let slash = target.firstIndex(of: "/") {
            return colon < slash
        }
        return true
    }

    /// Whether a target names this folder in any segment but its last.
    nonisolated private static func pathNames(_ folderName: String, in target: String) -> Bool {
        if !target.contains("/") || pointsOutsideTheCourse(target) {
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
    nonisolated private static func matches(_ segment: String, name: String) -> Bool {
        let plain: String = segment.trimmingCharacters(in: .whitespaces)
        if plain.caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        if let decoded = plain.removingPercentEncoding {
            return decoded.caseInsensitiveCompare(name) == .orderedSame
        }
        return false
    }

    /// How the new name is spelled inside this particular link.
    ///
    /// **"Spell it the way the old segment was spelled" is the obvious rule
    /// and it is wrong**, which is what this used to do. A Markdown link's
    /// destination ends at the first SPACE — the pattern above is literally
    /// `[^)\s]+` — so renaming `Tasks` to `All Tasks` turned
    /// `[q](Tasks/Quiz%201.md)` into `[q](All Tasks/Quiz%201.md)`, which
    /// neither Obsidian nor Quartz can follow. The old segment `Tasks` carries
    /// no `%`, so nothing here escaped anything; the `%20` in that example
    /// belongs to the FILE name, which is what made it easy to miss by eye.
    /// Every Markdown-style link into the folder broke, in the teacher's own
    /// pages, and nothing said so. Found on Windows by adversarial review,
    /// 2026-09-06, and reported to this side as a shared defect rather than a
    /// port error — see `contracts/shared-rules.json` →
    /// `specialNames.renameFolder.linkRewriting`.
    ///
    /// So: **in a Markdown link, escape when the NEW name needs it, whatever
    /// the old segment looked like. In a wikilink, keep the plain spelling** —
    /// `[[All Tasks/Quiz 1]]` is how Obsidian writes a wikilink containing a
    /// space, and escaping there would be the mirror-image mistake.
    ///
    /// The old rule is kept as a second reason to escape rather than replaced
    /// by the new one: a segment that ARRIVED percent-encoded goes back
    /// percent-encoded, so a link a teacher already had keeps the shape it had.
    nonisolated private static func spelled(_ name: String, likeThe segment: String, in style: LinkStyle) -> String {
        if style == .markdown && wouldBreakAMarkdownTarget(name) {
            return percentEncoded(name)
        }
        if wasPercentEncoded(segment) {
            return percentEncoded(name)
        }
        return name
    }

    /// Whether this name, dropped into a Markdown destination as it stands,
    /// would end the destination early or fail to parse.
    ///
    /// Whitespace and round brackets are the two that close a destination.
    /// A lone `%` is the third and is less obvious: Quartz resolves an
    /// internal link by calling JavaScript's `decodeURI` on it, and
    /// `decodeURI("10%/Quiz.md")` throws rather than returning anything.
    nonisolated private static func wouldBreakAMarkdownTarget(_ name: String) -> Bool {
        for character in name {
            if character.isWhitespace || character == "(" || character == ")" || character == "%" {
                return true
            }
        }
        return false
    }

    /// The name percent-encoded so that Quartz gets the folder's real name
    /// back out of it. See `charactersThatSurviveQuartzUndecoded` above for
    /// why the allowed set is neither `urlPathAllowed` nor the whole reserved
    /// set — both were tried and both are wrong here.
    nonisolated private static func percentEncoded(_ name: String) -> String {
        if let encoded = name.addingPercentEncoding(
            withAllowedCharacters: charactersThatSurviveQuartzUndecoded
        ) {
            return encoded
        }
        return name
    }

    /// Whether this segment arrived percent-encoded.
    ///
    /// A segment with no `%` in it never is, and one whose `%` does not begin
    /// a valid escape is treated as plain text rather than as encoding —
    /// `removingPercentEncoding` answers `nil` there, and reading that as
    /// "encoded" would be the opposite of what it means.
    nonisolated private static func wasPercentEncoded(_ segment: String) -> Bool {
        if !segment.contains("%") {
            return false
        }
        guard let decoded = segment.removingPercentEncoding else {
            return false
        }
        return decoded != segment
    }
}
