import Foundation

/// The two pages a folder added in Course Settings starts with: its
/// `index.md`, so the site's sidebar shows it, and a `_DUPLICATE ME.md`, so a
/// teacher has a page to copy (GitHub issue #506).
///
/// A folder made with the course gets both from the course creator
/// (`scripts/setup_course.py`), which runs inside the website builder. A
/// folder added AFTERWARDS is made by the app itself, natively — nothing runs
/// the builder for a Settings click — and until #506 it was made empty: no
/// `index.md`, so the folder never appeared in the sidebar even though it was
/// not hidden, and no template, so there was nothing to duplicate.
///
/// Every text here is setup's own, word for word, so a folder added in March
/// reads exactly like one made in September. `SectionAdder` already mirrors
/// setup's per-section folder page the same way, and was the precedent.
/// `contracts/course-management.json` → `foldersAddedLater` carries the
/// cases, computed with setup's own functions; Windows'
/// `SpecialFolderRenamer.CreateFoldersOnDisk` owes the same.
///
/// The page to duplicate is the generic skeleton's template
/// (`SkeletonCatalog.duplicateMeTemplateURL()`), whatever the course was made
/// from. All 344 skeleton templates are one identical file, and a test pins
/// that; payload courses carry many different ones, and a SIBLING folder's
/// copy was rejected as the source because it may be a teacher's edited page
/// with stale dates.
enum FolderScaffold {

    // MARK: - Types

    /// One page to write, by its path inside the course folder.
    struct Page: Equatable {

        // MARK: - Stored properties

        let relativePath: String
        let text: String
    }

    /// What a folder added later was given, for the trail.
    struct Outcome: Equatable {

        // MARK: - Stored properties

        var foldersCreated: Int = 0
        var indexPagesWritten: Int = 0
        var templatesWritten: Int = 0
    }

    // MARK: - Stored properties

    /// The page every course creator's template is called.
    nonisolated static let templateFileName: String = "_DUPLICATE ME.md"

    /// The placeholder the template carries where its date goes — setup's
    /// `EXAMPLE_CONTENT_CREATED_SENTINEL`.
    nonisolated static let createdSentinel: String = "__CREATED__"

    /// The placeholder expectation the template's "Curriculum connection"
    /// embeds.
    nonisolated static let placeholderExpectation: String = "A1.1"

    /// The markers around content that only makes sense alongside curriculum
    /// pages — setup's `CURRICULUM_BLOCK_START` and `CURRICULUM_BLOCK_END`.
    nonisolated static let curriculumBlockStart: String = "%%curriculum-start%%"
    nonisolated static let curriculumBlockEnd: String = "%%curriculum-end%%"

    // MARK: - Functions

    /// Every page a folder added later starts with, by path inside the course
    /// folder: for a shared folder its `index.md` and template; for a
    /// per-section folder the same two in each section.
    ///
    /// `curriculumPageNames` are the file names at the top of the course's
    /// primary curriculum folder, or nil when it has none. `template` is the
    /// bundled template's text; nil leaves the template out.
    nonisolated static func pages(
        forFolderNamed name: String,
        scope: FolderScope,
        sectionNumbers: [Int],
        curriculumPageNames: [String]?,
        created: String,
        template: String?
    ) -> [Page] {
        let stems: [String] = specificExpectationStems(in: curriculumPageNames ?? [])
        var result: [Page] = []
        switch scope {
        case .shared:
            result.append(Page(
                relativePath: name + "/index.md",
                text: sharedIndexText(forFolderNamed: name, sectionNumbers: sectionNumbers, created: created)
            ))
            if let template {
                result.append(Page(
                    relativePath: name + "/" + templateFileName,
                    text: templateText(
                        from: template, sharedBy: sectionNumbers,
                        curriculumStems: stems, created: created
                    )
                ))
            }
        case .perSection:
            for number in sectionNumbers {
                let folderPath: String = "section\(number)/" + name
                result.append(Page(
                    relativePath: folderPath + "/index.md",
                    text: sectionIndexText(forFolderNamed: name, created: created)
                ))
                if let template {
                    result.append(Page(
                        relativePath: folderPath + "/" + templateFileName,
                        text: templateText(
                            from: template, sharedBy: nil,
                            curriculumStems: stems, created: created
                        )
                    ))
                }
            }
        }
        return result
    }

    /// A shared folder's `index.md`: its title, a date and a published
    /// setting for every section, and setup's sentence word for word
    /// (`setup_course.py`, "Create shared structure").
    nonisolated static func sharedIndexText(forFolderNamed name: String, sectionNumbers: [Int], created: String) -> String {
        var text: String = "---\n"
        text += "title: \(name)\n"
        for number in sectionNumbers {
            text += "createdSection\(number): \(created)\n"
            text += "publishForSection\(number): true\n"
        }
        text += "---\n"
        text += "This is the **\(name)** folder. Add Markdown files to this folder to build out your site. "
            + "Optionally, you can remove this `index.md` file and Quartz will then show only a listing "
            + "of files that exist in this folder instead.\n"
        return text
    }

    /// A per-section folder's `index.md`: setup's per-section page, the same
    /// sentence `SectionAdder` writes when it has no sibling to copy.
    nonisolated static func sectionIndexText(forFolderNamed name: String, created: String) -> String {
        var text: String = "---\n"
        text += "title: \(name)\n"
        text += "created: \(created)\n"
        text += "publish: true\n"
        text += "---\n"
        text += "This is the **\(name)** folder. Add Markdown files to this folder to build out your site.\n"
        return text
    }

    /// The template as setup would pour it: the date filled in, the
    /// "Curriculum connection" kept (pointing at an expectation the course
    /// has) or taken out, and — in a SHARED folder — one date and one
    /// published setting per section, held back in every one.
    ///
    /// The steps are setup's own, in setup's order (`install_file`):
    /// `retargeted_expectation_references`, `strip_curriculum_blocks`,
    /// `per_section_frontmatter`. The template is pinned byte for byte to
    /// `foldersAddedLater.templateSource`, so each step reads the shape that
    /// file has rather than every shape a teacher's page could.
    nonisolated static func templateText(
        from template: String,
        sharedBy sectionNumbers: [Int]?,
        curriculumStems: [String],
        created: String
    ) -> String {
        var text: String = template.replacingOccurrences(of: createdSentinel, with: created)
        let keepsTheConnection: Bool = !curriculumStems.isEmpty
        if keepsTheConnection && !curriculumStems.contains(placeholderExpectation) {
            // The course has expectations but no A1.1 (a British Columbia
            // code starts at D1.1): an embed of A1.1 would be a broken
            // transclusion on every page duplicated from this one.
            text = text.replacingOccurrences(
                of: "[[" + placeholderExpectation + "]]",
                with: "[[" + curriculumStems[0] + "]]"
            )
        }
        text = removingCurriculumMarkers(from: text, keepingContent: keepsTheConnection)
        if let sectionNumbers {
            text = splittingKeysPerSection(text, sectionNumbers: sectionNumbers)
        }
        return text
    }

    /// The specific expectations among a curriculum folder's file names, in
    /// the order setup reads them: by FULL file name, as Python's
    /// `sorted(glob("*.md"))` does — so `B1.10` comes before `B1.2` — and
    /// only the letter-first `A1.1` shape (`specific_expectation_stems`).
    nonisolated static func specificExpectationStems(in fileNames: [String]) -> [String] {
        var markdownNames: [String] = []
        for fileName in fileNames {
            if fileName.hasSuffix(".md") {
                markdownNames.append(fileName)
            }
        }
        markdownNames.sort()
        var stems: [String] = []
        for fileName in markdownNames {
            let stem: String = String(fileName.dropLast(3))
            if isSpecificExpectationStem(stem) {
                stems.append(stem)
            }
        }
        return stems
    }

    /// `^[A-Z]\d+\.\d+$` — one capital letter, digits, a dot, digits.
    nonisolated static func isSpecificExpectationStem(_ stem: String) -> Bool {
        let pieces: [Substring] = stem.split(separator: ".", omittingEmptySubsequences: false)
        if pieces.count != 2 {
            return false
        }
        let head: Substring = pieces[0]
        let tail: Substring = pieces[1]
        guard let letter = head.first, letter.isASCII, letter.isUppercase else {
            return false
        }
        let headDigits: Substring = head.dropFirst()
        return isAllDigits(headDigits) && isAllDigits(tail)
    }

    /// Setup's `strip_curriculum_blocks`: the marker lines always go, and
    /// what is between them goes too unless it is kept.
    nonisolated static func removingCurriculumMarkers(from text: String, keepingContent: Bool) -> String {
        var kept: [String] = []
        var insideBlock: Bool = false
        for line in text.components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            if trimmed == curriculumBlockStart {
                insideBlock = true
                continue
            }
            if trimmed == curriculumBlockEnd {
                insideBlock = false
                continue
            }
            if insideBlock && !keepingContent {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    /// Setup's `per_section_frontmatter` over the template's frontmatter: the
    /// `created:` and `publish:` lines are replaced, where the first of them
    /// stood, by one `createdSectionN` / `publishForSectionN` pair per section
    /// — values copied as written. With no sections the page is unchanged,
    /// as setup leaves it.
    nonisolated static func splittingKeysPerSection(_ text: String, sectionNumbers: [Int]) -> String {
        if sectionNumbers.isEmpty || !text.hasPrefix("---\n") {
            return text
        }
        let afterOpening: String = String(text.dropFirst(4))
        guard let closing = afterOpening.range(of: "\n---") else {
            return text
        }
        let head: String = String(afterOpening[afterOpening.startIndex..<closing.lowerBound])
        let rest: String = String(afterOpening[closing.lowerBound...])
        var created: String? = nil
        var publish: String? = nil
        for line in head.components(separatedBy: "\n") {
            if line.hasPrefix("created:") {
                created = line.dropFirst("created:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("publish:") {
                publish = line.dropFirst("publish:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        if created == nil && publish == nil {
            return text
        }
        var block: [String] = []
        for number in sectionNumbers {
            if let created {
                block.append("createdSection\(number): \(created)")
            }
            if let publish {
                block.append("publishForSection\(number): \(publish)")
            }
        }
        var lines: [String] = []
        var blockPlaced: Bool = false
        for line in head.components(separatedBy: "\n") {
            if line.hasPrefix("created:") || line.hasPrefix("publish:") {
                if !blockPlaced {
                    lines.append(contentsOf: block)
                    blockPlaced = true
                }
                continue
            }
            lines.append(line)
        }
        return "---\n" + lines.joined(separator: "\n") + rest
    }

    /// Writes the pages for a folder added later — only into the folders in
    /// `newFolders`, the ones this click has just made, and never over a file
    /// that is already there (`.withoutOverwriting`, so even a page that
    /// appeared in between is left alone). A folder that already existed is
    /// a teacher's, and nothing is put into it.
    nonisolated static func writePages(
        _ pages: [Page],
        intoNewFolders newFolders: [URL],
        courseDirectory: URL
    ) -> Outcome {
        var outcome: Outcome = Outcome()
        outcome.foldersCreated = newFolders.count
        var newFolderPaths: Set<String> = []
        for folder in newFolders {
            newFolderPaths.insert(folder.standardizedFileURL.path)
        }
        for page in pages {
            let pageURL: URL = courseDirectory.appendingPathComponent(page.relativePath)
            let folderPath: String = pageURL.deletingLastPathComponent().standardizedFileURL.path
            if !newFolderPaths.contains(folderPath) {
                continue
            }
            do {
                try Data(page.text.utf8).write(to: pageURL, options: [.withoutOverwriting])
            } catch {
                // A page already there is the teacher's and stays; a genuine
                // failure leaves the folder as it was before #506 — empty —
                // which the build reports in its own words.
                continue
            }
            if pageURL.lastPathComponent == templateFileName {
                outcome.templatesWritten += 1
            } else {
                outcome.indexPagesWritten += 1
            }
        }
        return outcome
    }

    /// The file names at the top of the course's PRIMARY curriculum folder —
    /// the first one `CurriculumFolderRule` resolves (#128) — or nil when the
    /// course has none, or it is not on disk.
    static func curriculumPageNames(for course: Course) -> [String]? {
        guard let primary = CurriculumFolderRule.resolvedFolders(for: course).first else {
            return nil
        }
        let folder: URL = course.directoryURL.appendingPathComponent(primary, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return nil
        }
        return names
    }

    /// The bundled template's text, or nil when the bundle does not carry it.
    static func bundledTemplate() -> String? {
        guard let url = SkeletonCatalog.duplicateMeTemplateURL() else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Private helpers

    nonisolated private static func isAllDigits(_ text: Substring) -> Bool {
        if text.isEmpty {
            return false
        }
        for character in text {
            guard character.isASCII, character.isNumber else {
                return false
            }
        }
        return true
    }
}
