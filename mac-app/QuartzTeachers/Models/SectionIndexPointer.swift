import Foundation

/// Keeps a section's landing page pointing at its most recent visible class.
///
/// **The chore this removes.** A section's `index.md` is what a student lands
/// on, and it opens by transcluding one class page under "Most Recent Class".
/// Until now the payloads carried a note telling the teacher to repoint it by
/// hand after every lesson — which is exactly the kind of frontmatter fussing
/// Plantoir exists to do for them, and exactly the kind of thing that goes
/// wrong quietly: unpublish the class the index points at, and the landing
/// page every student sees now transcludes a page that is not there.
///
/// **The invariant, in one sentence:** the section index transcludes the most
/// recent class page students can see, and carries that class's date.
///
/// Maintained rather than patched in one direction. It would have been enough
/// for the reported bug to fix up an unpublish, but the same invariant is what
/// publishing a NEWER class needs — and a rule stated once holds in cases
/// nobody thought to list.
///
/// The date moves with it because the landing page's date IS the class's date
/// to a reader: a section whose front page says August while its newest lesson
/// is in January reads as abandoned.
///
/// **The heading above the embed is never read and never written.** A course
/// writes "# Most Recent Class", a club "# Most Recent Meeting"
/// (`front_page_heading`, #267), and a course made by hand says whatever its
/// teacher typed — CODING's is an h2. The embed is found by the page it names,
/// so all of them repoint the same way, and an existing course keeps its
/// heading. Nor does this ever INSERT an embed into a page that has none;
/// Windows does, under the course's own heading, and
/// `contracts/class-planning.json` → `sectionIndexPointer` pins both.
///
/// **The class line is read outside code and `%%` comments, and only the
/// line found is rewritten (#397).** A class line a teacher parked in a
/// comment is not on the page students see; reading it as the embed made
/// the pointer "move" a line nobody sees and report success. The one link
/// mask (`MarkdownCode.notALinkRanges`) decides, as it does for every other
/// link reader, and the build's own reading of the same line
/// (`build_site._date_pages_from_their_classes`) uses the same mask. The new
/// line keeps the FORM the teacher wrote — `sectionIndexPointer.writtenAs`.
/// Preview's question about today's class (`TodaysClassOnTheFrontPage`)
/// finds the line and writes it through here, so there is one reader and
/// one writer of it.
enum SectionIndexPointer {

    // MARK: - Types

    /// What repointing an index came to.
    struct Result: Equatable {

        // MARK: - Stored properties

        /// The index as it should now read.
        let text: String

        /// The class it now points at.
        let nowPointsAt: String

        /// The class it used to point at, when that changed.
        let usedToPointAt: String?
    }

    /// The front page's class line, as found (`sectionIndexPointer.found`).
    struct ClassLine: Equatable {

        // MARK: - Stored properties

        /// Where it is: an index into the page's lines, split on "\n".
        let lineIndex: Int

        /// The class it names, as written, without a `.md`.
        let name: String

        /// How many folders the teacher wrote before the name.
        let folderDepth: Int

        /// The display name after `|`, as written, or nil.
        let displayName: String?

        /// Whether the teacher wrote the file's `.md`.
        let hasMarkdownExtension: Bool

        /// What surrounds the embed on its line — kept when it is rewritten.
        let before: String
        let after: String
    }

    // MARK: - Functions

    /// The most recent class page students can currently see.
    ///
    /// By date, because that is what "most recent" means to a teacher and to a
    /// student. Undated pages cannot be compared and are passed over rather
    /// than guessed at; a section with no dated visible class has no answer,
    /// and saying so is better than pointing somewhere arbitrary.
    ///
    /// When two visible classes sit on the same date (e.g. overflow lessons or
    /// multi-class days), the higher Unit x, Day y count wins.
    static func mostRecentVisibleClass(
        in graph: AssistSectionGraph, naming: ClassPageNaming
    ) -> AssistSectionPage? {
        var newest: AssistSectionPage?
        var newestDay: CalendarDay?
        var newestUnitDay: UnitDay?
        for page in graph.pages {
            if !page.isClassPage || !page.isVisibleToStudents {
                continue
            }
            guard let day = page.date else {
                continue
            }
            let unitDay: UnitDay? = UnitDay(pageTitle: page.title, naming: naming)
            if let soFarDay = newestDay {
                if day.text < soFarDay.text {
                    continue
                } else if day.text == soFarDay.text {
                    if !SectionIndexPointer.comesLater(unitDay, than: newestUnitDay) {
                        continue
                    }
                }
            }
            newest = page
            newestDay = day
            newestUnitDay = unitDay
        }
        return newest
    }

    /// The tie-break between two classes on the same day: the higher of the
    /// course's own numbering wins, a numbered class beats an unnumbered one,
    /// and between two unnumbered ones the later in the walk does. Shared with
    /// `TodaysClassOnTheFrontPage`, which chooses between today's classes the
    /// same way (#397) rather than keeping a copy of the rule.
    static func comesLater(_ candidate: UnitDay?, than current: UnitDay?) -> Bool {
        if let candidateNumbers = candidate, let currentNumbers = current {
            return candidateNumbers > currentNumbers
        }
        if candidate == nil && current != nil {
            return false
        }
        return true
    }

    /// The front page's class line (`sectionIndexPointer.found`), or nil when
    /// it has none.
    ///
    /// Read BELOW the frontmatter and OUTSIDE code and `%%` comments (#397).
    /// The mask is taken over the body alone, as the build takes it over the
    /// page's content, and positions are counted in UTF-16 because that is
    /// what the mask counts in — counted in characters, an emoji above a
    /// comment moves the embed inside it (the contract case "a long line of
    /// emoji above a comment").
    static func classLine(in text: String, classTitles: Set<String>) -> ClassLine? {
        let lines: [String] = text.components(separatedBy: "\n")
        var bodyStart: Int = 0
        if let block = PageFrontmatter.block(in: text) {
            bodyStart = block.closeIndex + 1
        }
        if bodyStart >= lines.count {
            return nil
        }
        var bodyLines: [String] = []
        for index in bodyStart..<lines.count {
            bodyLines.append(lines[index])
        }
        let notALink: [NSRange] = MarkdownCode.notALinkRanges(in: bodyLines.joined(separator: "\n"))

        let aroundTheEmbed: CharacterSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\r"))
        var lineStart: Int = 0
        for (offset, line) in bodyLines.enumerated() {
            let startOfThisLine: Int = lineStart
            lineStart += line.utf16.count + 1

            let trimmed: String = line.trimmingCharacters(in: aroundTheEmbed)
            guard trimmed.hasPrefix("![["), trimmed.hasSuffix("]]"), trimmed.count >= 5,
                  let opening = line.range(of: "![[") else {
                continue
            }
            let embedAt: Int = startOfThisLine + opening.lowerBound.utf16Offset(in: line)
            if MarkdownCode.contains(embedAt, in: notALink) {
                continue
            }

            let inside: String = String(trimmed.dropFirst(3).dropLast(2))
            // A transclusion may carry a display name or a heading; the target
            // is what comes before either.
            let beforeTheBar: String = inside.components(separatedBy: "|")[0]
            let target: String = beforeTheBar
                .components(separatedBy: "#")[0]
                .trimmingCharacters(in: .whitespaces)
            let pathParts: [String] = target.components(separatedBy: "/")
            var name: String = (pathParts.last ?? target).trimmingCharacters(in: .whitespaces)
            var hasMarkdownExtension: Bool = false
            if name.lowercased().hasSuffix(".md") {
                name = String(name.dropLast(3)).trimmingCharacters(in: .whitespaces)
                hasMarkdownExtension = true
            }
            if name.isEmpty || !classTitles.contains(name.lowercased()) {
                continue
            }

            var displayName: String?
            if let bar = inside.range(of: "|") {
                displayName = String(inside[bar.upperBound...])
            }
            let embedStart: String.Index = opening.lowerBound
            let embedEnd: String.Index = line.index(embedStart, offsetBy: trimmed.count)
            return ClassLine(
                lineIndex: bodyStart + offset,
                name: name,
                folderDepth: pathParts.count - 1,
                displayName: displayName,
                hasMarkdownExtension: hasMarkdownExtension,
                before: String(line[..<embedStart]),
                after: String(line[embedEnd...])
            )
        }
        return nil
    }

    /// The embed that replaces `line`, naming `page` in the form the teacher
    /// wrote (`sectionIndexPointer.writtenAs`, #397): a folder path keeps its
    /// DEPTH and names where `page` actually is; a display name equal to the
    /// old class's name follows the class; any other display name, and any
    /// heading, is dropped; a typed `.md` stays.
    static func embed(replacing line: ClassLine, with page: AssistSectionPage) -> String {
        var written: String = page.title
        if line.hasMarkdownExtension {
            written += ".md"
        }
        if line.folderDepth > 0 {
            var folders: [String] = []
            for component in page.fileURL.deletingLastPathComponent().pathComponents where component != "/" {
                folders.append(component)
            }
            if folders.count >= line.folderDepth {
                var kept: [String] = []
                for index in (folders.count - line.folderDepth)..<folders.count {
                    kept.append(folders[index])
                }
                written = kept.joined(separator: "/") + "/" + written
            }
        }
        if let displayName = line.displayName,
           displayName.trimmingCharacters(in: .whitespaces).lowercased() == line.name.lowercased() {
            written += "|" + page.title
        }
        return "![[" + written + "]]"
    }

    /// The index rewritten to point at `page`, or nil when nothing needs to
    /// change.
    ///
    /// Only the transclusion that names a CLASS page is touched. A section
    /// index also transcludes things like Help Sessions and Key Links, and
    /// repointing one of those at a lesson would be a far worse bug than the
    /// one being fixed — so the replacement is made by matching against the
    /// section's actual class titles rather than by position.
    ///
    /// A page with no class transclusion at all is left exactly as it is —
    /// its date included (#275).
    static func repointing(
        _ text: String,
        at page: AssistSectionPage,
        classTitles: Set<String>,
        createdTail: String
    ) -> Result? {
        var updated: String = text
        var replaced: String?

        // A front page with no class embed is one the teacher made without
        // one, or emptied on purpose: it keeps its own date, because there is
        // no class on it for the date to follow (#275,
        // `contracts/class-planning.json` → `sectionIndexPointer.dateCases`).
        // This used to date it to the newest class anyway.
        guard let found = SectionIndexPointer.classLine(in: text, classTitles: classTitles) else {
            return nil
        }
        if found.name != page.title {
            // THAT line, by its position — never every line with its text: a
            // copy of it inside a comment is the teacher's note, and
            // `replacingOccurrences` rewrote it too until #397.
            var lines: [String] = text.components(separatedBy: "\n")
            lines[found.lineIndex] = found.before
                + SectionIndexPointer.embed(replacing: found, with: page)
                + found.after
            updated = lines.joined(separator: "\n")
            replaced = found.name
        }

        // The date follows the class it points at.
        if let day = page.date {
            updated = PageFrontmatter.settingCreated(
                in: updated,
                key: PageFrontmatter.createdKey(forSection: 0, isSectionLocal: true),
                to: day,
                fallbackTail: createdTail
            ).text
        }

        if updated == text {
            return nil
        }
        return Result(text: updated, nowPointsAt: page.title, usedToPointAt: replaced)
    }

    /// Where a section's landing page lives.
    static func indexURL(forSection sectionNumber: Int, in course: Course) -> URL {
        return course.sectionDirectoryURL(forSection: sectionNumber)
            .appendingPathComponent("index.md")
    }

    /// Repoints the section landing page at its newest visible class, returning
    /// the saved file record when modified.
    static func repointIndex(
        forSection sectionNumber: Int,
        in course: Course
    ) -> AssistSavedFile? {
        let graph: AssistSectionGraph = AssistSectionGraph.read(
            forSection: sectionNumber, in: course, workspaceURL: nil
        )
        guard let newest = SectionIndexPointer.mostRecentVisibleClass(
            in: graph, naming: course.configuration.classPageNaming
        ) else {
            return nil
        }

        let indexURL: URL = SectionIndexPointer.indexURL(forSection: sectionNumber, in: course)
        guard let before = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return nil
        }

        var classTitles: Set<String> = []
        for page in graph.pages where page.isClassPage {
            classTitles.insert(page.lowercasedTitle)
        }

        let tail: String = ClassPages.siblingTimeAndOffset(
            from: ClassPages.list(forSection: sectionNumber, in: course),
            forSection: sectionNumber
        )
        guard let result = SectionIndexPointer.repointing(
            before, at: newest, classTitles: classTitles, createdTail: tail
        ) else {
            return nil
        }
        guard (try? result.text.write(to: indexURL, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        return AssistSavedFile(fileURL: indexURL, before: before, after: result.text)
    }
}
