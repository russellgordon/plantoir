import Foundation

/// One curriculum expectation: its code, and what it actually says.
struct AssistCurriculumExpectation: Equatable {

    // MARK: - Stored properties

    /// The file name, which is the code: `A1.2`.
    let code: String

    /// The wording, with the frontmatter and the block anchor taken off.
    let text: String

    /// Where it sits, said the way a teacher would say it.
    let relativePath: String
}

/// Curriculum expectations that would be pointed at from a page.
///
/// Which expectations fit a lesson is a judgement about MEANING, and the
/// measurements say a small router model has no business making it — but a
/// capable one does it well. So the split is deliberate: the tools find the
/// expectations, read them out, know the transclusion syntax and where the
/// markers go, and the model driving decides which ones belong. The teacher
/// then says yes to a named list rather than to "some expectations".
struct AssistCurriculumMentionsPlan {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let pageTitle: String
    let fileURL: URL
    let relativePath: String

    /// The expectations that would be added, with their wording.
    let adding: [AssistCurriculumExpectation]

    /// Codes the page already points at, which are left alone.
    let alreadyThere: [String]

    /// Codes that match no expectation in this course.
    let unknown: [String]

    /// Whether the page already has a curriculum block to add to.
    let hasBlockAlready: Bool

    // MARK: - Computed properties

    var changesNothing: Bool {
        return adding.isEmpty
    }

    // MARK: - Functions

    /// The plan, written to be read aloud to a teacher.
    func describe() -> String {
        var lines: [String] = []

        if adding.isEmpty {
            if alreadyThere.isEmpty {
                lines.append("Nothing to add to “\(pageTitle)”.")
            } else {
                lines.append("Nothing to add — “\(pageTitle)” already points at "
                             + AssistCurriculumMentionsPlan.listed(alreadyThere) + ".")
            }
            appendUnknown(to: &lines)
            return lines.joined(separator: "\n")
        }

        let word: String = adding.count == 1 ? "expectation" : "expectations"
        lines.append("Add \(adding.count) curriculum \(word) to “\(pageTitle)” in "
                     + "\(courseCode) Section \(sectionNumber):")
        lines.append("")

        // The WORDING, not just the code. A teacher cannot check "A2.2" for
        // themselves without going and looking it up, and the whole point of
        // confirming is that they can tell whether it fits their lesson.
        for expectation in adding {
            lines.append("  \(expectation.code)")
            lines.append("    " + AssistCurriculumMentionsPlan.shortened(expectation.text))
        }

        if !alreadyThere.isEmpty {
            lines.append("")
            lines.append("Already there, left alone: "
                         + AssistCurriculumMentionsPlan.listed(alreadyThere) + ".")
        }

        appendUnknown(to: &lines)

        lines.append("")
        lines.append(hasBlockAlready
                     ? "They join the curriculum block already on the page."
                     : "A curriculum block is added for them, before the list of things to do.")
        lines.append("Nothing else on the page changes, and no page's visibility changes.")
        return lines.joined(separator: "\n")
    }

    /// Codes that matched nothing are NAMED rather than skipped: one usually
    /// means a typo or another course's numbering, and dropping it quietly
    /// would leave the teacher believing it was added.
    private func appendUnknown(to lines: inout [String]) {
        if unknown.isEmpty {
            return
        }
        lines.append("")
        let isOne: Bool = unknown.count == 1
        lines.append("• " + AssistCurriculumMentionsPlan.listed(unknown) + " "
                     + (isOne ? "is not an expectation" : "are not expectations")
                     + " in \(courseCode), so " + (isOne ? "it was" : "they were") + " left out.")
    }

    private static func listed(_ codes: [String]) -> String {
        return codes.joined(separator: ", ")
    }

    /// How much of an expectation's wording to quote before it stops being
    /// something a teacher reads and starts being something they skip.
    private static let mostWords: Int = 24

    private static func shortened(_ text: String) -> String {
        var words: [String] = []
        for piece in text.components(separatedBy: .whitespacesAndNewlines) where !piece.isEmpty {
            words.append(piece)
        }
        if words.count <= mostWords {
            return text
        }
        var kept: [String] = []
        for word in words {
            if kept.count == mostWords {
                break
            }
            kept.append(word)
        }
        return kept.joined(separator: " ") + "…"
    }
}

/// Finding a course's curriculum expectations, and pointing a page at them.
///
/// The transclusions go INSIDE the `%%curriculum-start%%` markers the payloads
/// use, and the markers are the whole point: a course installed without
/// curriculum has that block stripped at build time, so a transclusion outside
/// them would leave a dangling reference on a teacher's live site rather than
/// disappearing quietly.
enum AssistCurriculumMentions {

    // MARK: - The markers, and what goes between them

    static let startMarker: String = "%%curriculum-start%%"
    static let endMarker: String = "%%curriculum-end%%"

    /// The heading every payload puts inside the block.
    static let heading: String = "## Curriculum connection"

    /// The heading that closes a class page. A curriculum note belongs with the
    /// lesson rather than after the homework, so a new block goes in front of
    /// it when there is one.
    private static let thingsToDoHeading: String = "## Things to do"

    // MARK: - Reading the curriculum

    /// Every curriculum expectation in the course, with its wording.
    ///
    /// The point of returning the TEXT, not just the codes, is that matching an
    /// expectation to a lesson is a judgement about meaning — the one thing the
    /// tools cannot do and a capable model can. So this hands over everything
    /// needed to decide, and decides nothing itself.
    static func expectations(
        forSection sectionNumber: Int,
        in course: Course,
        workspaceURL: URL?
    ) -> [AssistCurriculumExpectation] {
        var found: [AssistCurriculumExpectation] = []
        for pageURL in ClassPages.pagesOfSection(sectionNumber, in: course) {
            if !isCurriculum(pageAt: pageURL, in: course) {
                continue
            }
            let code: String = pageURL.deletingPathExtension().lastPathComponent
            // Index and strand-heading pages are not expectations; an
            // expectation is a leaf, coded like A1.1 or B2.3.
            if !isExpectationCode(code) {
                continue
            }
            guard let body = try? String(contentsOf: pageURL, encoding: .utf8) else {
                continue
            }
            found.append(AssistCurriculumExpectation(
                code: code,
                text: wording(in: body),
                relativePath: AssistSectionGraph.relativePath(of: pageURL, workspaceURL: workspaceURL)
            ))
        }

        found.sort { first, second in
            return first.code.lowercased() < second.code.lowercased()
        }
        return found
    }

    /// True when a page is curriculum reference material.
    ///
    /// Matches `build_site.py`'s own rule exactly — any FOLDER segment
    /// containing "curriculum", case-insensitively, with the file name ignored.
    /// That is what makes it work for a course whose folders are called
    /// "Ontario Curriculum" and "College Board Curriculum" rather than plain
    /// "Curriculum", which is the normal case outside the example content.
    static func isCurriculum(pageAt pageURL: URL, in course: Course) -> Bool {
        let root: String = course.directoryURL.standardizedFileURL.path + "/"
        let full: String = pageURL.standardizedFileURL.path
        if !full.hasPrefix(root) {
            return false
        }
        var segments: [String] = String(full.dropFirst(root.count)).components(separatedBy: "/")
        if !segments.isEmpty {
            segments.removeLast()
        }
        for segment in segments where segment.lowercased().contains("curriculum") {
            return true
        }
        return false
    }

    /// True for a leaf expectation's code, the WHOLE name: a letter, a strand
    /// number, a dot and an expectation number (`A1.1`, `b2.3`); the College
    /// Board's skills, digits, a dot and ONE letter (`1.A`); or its learning
    /// objectives, two to four capital letters, a hyphen, digits, a dot and
    /// one capital letter (`CRD-1.A`) — #128.
    /// `\A`…`\z` rather than `^`…`$`, which also match before a final newline.
    /// `contracts/shared-rules.json` → `curriculumRules.isExpectationCode`.
    nonisolated static func isExpectationCode(_ code: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: "\\A(?:[A-Za-z][0-9]+\\.[0-9]+|[0-9]+\\.[A-Za-z]|[A-Z]{2,4}-[0-9]+\\.[A-Z])\\z"
        ) else {
            return false
        }
        let whole: NSRange = NSRange(code.startIndex..<code.endIndex, in: code)
        return expression.firstMatch(in: code, range: whole) != nil
    }

    /// What an expectation page actually says: the body, without the
    /// frontmatter and without the `^text` block anchor on the end.
    static func wording(in pageText: String) -> String {
        var body: String = bodyAfterFrontmatter(pageText)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let anchor = body.range(of: " ^", options: .backwards) else {
            return body
        }
        // Only a bare word can be the anchor. Anything with a space in it is
        // the teacher's own prose, and cutting there would lose wording.
        let trailing: String = String(body[anchor.upperBound...])
        if trailing.isEmpty || trailing.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return body
        }
        body = String(body[body.startIndex..<anchor.lowerBound])
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Everything after the frontmatter fence, or the whole page when there is
    /// no frontmatter.
    static func bodyAfterFrontmatter(_ pageText: String) -> String {
        guard let block = PageFrontmatter.block(in: pageText) else {
            return pageText
        }
        let lines: [String] = pageText.components(separatedBy: "\n")
        var body: [String] = []
        var index: Int = block.closeIndex + 1
        while index < lines.count {
            body.append(lines[index])
            index += 1
        }
        return body.joined(separator: "\n")
    }

    // MARK: - Planning

    /// Work out what pointing a page at these expectations would do.
    ///
    /// Decides nothing about MEANING: the codes arrive already chosen, and all
    /// this does is tell the ones it knows from the ones it does not, and the
    /// ones the page already points at from the ones it does not.
    static func plan(
        codes: [String],
        page: AssistSectionPage,
        pageText: String,
        expectations: [AssistCurriculumExpectation],
        courseCode: String,
        sectionNumber: Int
    ) -> AssistCurriculumMentionsPlan {
        var known: [String: AssistCurriculumExpectation] = [:]
        for expectation in expectations {
            known[expectation.code.lowercased()] = expectation
        }

        var adding: [AssistCurriculumExpectation] = []
        var alreadyThere: [String] = []
        var unknown: [String] = []
        var seen: Set<String> = []

        for raw in codes {
            let code: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if code.isEmpty || seen.contains(code.lowercased()) {
                continue
            }
            seen.insert(code.lowercased())

            guard let expectation = known[code.lowercased()] else {
                unknown.append(code)
                continue
            }
            if pageText.range(of: "[[\(expectation.code)]]", options: .caseInsensitive) != nil {
                alreadyThere.append(expectation.code)
                continue
            }
            adding.append(expectation)
        }

        return AssistCurriculumMentionsPlan(
            courseCode: courseCode,
            sectionNumber: sectionNumber,
            pageTitle: page.displayTitle,
            fileURL: page.fileURL,
            relativePath: page.relativePath,
            adding: adding,
            alreadyThere: alreadyThere,
            unknown: unknown,
            hasBlockAlready: pageText.range(of: startMarker, options: .caseInsensitive) != nil
        )
    }

    // MARK: - Writing it down

    /// Write the transclusions the plan describes into the page, and hand back
    /// the whole file before and after so `undo_last_change` can take it back.
    static func apply(_ plan: AssistCurriculumMentionsPlan) throws -> AssistChange {
        let before: String = try String(contentsOf: plan.fileURL, encoding: .utf8)
        let lineEnd: String = before.contains("\r\n") ? "\r\n" : "\n"

        var transclusions: [String] = []
        for expectation in plan.adding {
            transclusions.append("![[\(expectation.code)]]")
        }
        // A blank line between them, which is the shape every payload uses.
        let added: String = transclusions.joined(separator: lineEnd + lineEnd)

        let after: String
        if let end = before.range(of: endMarker, options: .caseInsensitive) {
            // Inside the block that is already there, keeping what it holds.
            let head: String = String(before[before.startIndex..<end.lowerBound])
            let tail: String = String(before[end.lowerBound...])
            after = trimmedAtEnd(head) + lineEnd + lineEnd + added + lineEnd + tail
        } else {
            let block: String = startMarker + lineEnd + heading + lineEnd + lineEnd
                              + added + lineEnd + endMarker + lineEnd
            if let thingsToDo = before.range(of: thingsToDoHeading, options: .caseInsensitive) {
                let head: String = String(before[before.startIndex..<thingsToDo.lowerBound])
                let tail: String = String(before[thingsToDo.lowerBound...])
                after = head + block + lineEnd + tail
            } else {
                after = trimmedAtEnd(before) + lineEnd + lineEnd + block
            }
        }

        try after.write(to: plan.fileURL, atomically: true, encoding: .utf8)

        let word: String = plan.adding.count == 1 ? "expectation" : "expectations"
        return AssistChange(
            whatHappened: "added \(plan.adding.count) curriculum \(word) to “\(plan.pageTitle)”",
            courseCode: plan.courseCode,
            sectionNumber: plan.sectionNumber,
            // Matches what adding them did: this tool does not rebuild the
            // preview, so taking it back does not either. If that tool ever
            // starts rebuilding, this flips with it.
            rebuildsThePreview: false,
            files: [AssistSavedFile(fileURL: plan.fileURL, before: before, after: after)]
        )
    }

    /// The codes that were added, said the way the teacher asked for them.
    static func codeList(of expectations: [AssistCurriculumExpectation]) -> String {
        var codes: [String] = []
        for expectation in expectations {
            codes.append(expectation.code)
        }
        return codes.joined(separator: ", ")
    }

    private static func trimmedAtEnd(_ text: String) -> String {
        var trimmed: String = text
        while let last = trimmed.last, last.isWhitespace {
            trimmed.removeLast()
        }
        return trimmed
    }
}
