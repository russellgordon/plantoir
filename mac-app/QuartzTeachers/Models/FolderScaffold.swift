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
        text += "title: \(frontmatterTitle(name))\n"
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
        text += "title: \(frontmatterTitle(name))\n"
        text += "created: \(created)\n"
        text += "publish: true\n"
        text += "---\n"
        text += "This is the **\(name)** folder. Add Markdown files to this folder to build out your site.\n"
        return text
    }

    /// What follows `title: ` for a folder's or file's name: the name itself,
    /// or — when written plain it would not read back as the name — the name
    /// double-quoted with JSON's escapes, which YAML reads as the same text.
    ///
    /// Measured (#506's review): a folder called `Unit: One`, `'Tis the
    /// Season` or `& Friends` got an index page the build could not read, so
    /// the folder stayed out of the sidebar and the teacher was told to fix a
    /// page Plantoir had just written. Setup's `frontmatter_title` is the same
    /// rule, and `contracts/course-management.json` →
    /// `foldersAddedLater.titleQuoting` pins both.
    nonisolated static func frontmatterTitle(_ name: String) -> String {
        if !titleNeedsQuoting(name) {
            return name
        }
        var quoted: String = "\""
        for scalar in name.unicodeScalars {
            switch scalar {
            case "\"":
                quoted += "\\\""
            case "\\":
                quoted += "\\\\"
            case "\n":
                quoted += "\\n"
            case "\r":
                quoted += "\\r"
            case "\t":
                quoted += "\\t"
            case "\u{08}":
                quoted += "\\b"
            case "\u{0C}":
                quoted += "\\f"
            default:
                if scalar.value < 0x20 {
                    quoted += "\\u" + String(format: "%04x", scalar.value)
                } else {
                    quoted.unicodeScalars.append(scalar)
                }
            }
        }
        quoted += "\""
        return quoted
    }

    /// Setup's `title_needs_quoting`, the same rule character for character:
    /// empty; a first character that is neither an ASCII letter nor beyond
    /// ASCII (every YAML indicator, a space, a digit); a last character that
    /// is a space, a tab or a colon; `: `, ` #` or a control character
    /// anywhere; or one of YAML 1.1's plain words for true, false and null.
    /// Generous on purpose — a quoted title is still the same title.
    nonisolated static func titleNeedsQuoting(_ name: String) -> Bool {
        let scalars: [Unicode.Scalar] = Array(name.unicodeScalars)
        guard let first = scalars.first, let last = scalars.last else {
            return true
        }
        let firstIsASCIILetter: Bool = (first >= "A" && first <= "Z") || (first >= "a" && first <= "z")
        if !firstIsASCIILetter && first.value <= 127 {
            return true
        }
        if last == " " || last == "\t" || last == ":" {
            return true
        }
        // Read scalar by scalar, as Python reads code points: a `String`
        // search would miss ": " when a combining mark follows the space.
        var previous: Unicode.Scalar? = nil
        for scalar in scalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return true
            }
            if previous == ":" && scalar == " " {
                return true
            }
            if previous == " " && scalar == "#" {
                return true
            }
            previous = scalar
        }
        let plainNonTextWords: Set<String> = ["true", "false", "yes", "no", "on", "off", "y", "n", "null", "~"]
        return plainNonTextWords.contains(name.lowercased())
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

    /// Plans each folder Add folder makes, with the pages that go in it,
    /// into `step` as ONE `createTree` per folder (#899 U4a): the folder
    /// (and any folder above it inside the course that is not there yet)
    /// with exactly Plantoir's pages, made whole or not at all, never over
    /// anything. An Undo takes a folder out only while it still holds just
    /// what Plantoir put there (#986 ruling 7). Pages for a folder that is
    /// not new are left out: a folder already there is the teacher's.
    nonisolated static func planPages(
        _ pages: [Page],
        intoNewFolders newFolders: [URL],
        courseDirectory: URL,
        into step: JournaledStep
    ) -> Outcome {
        var outcome: Outcome = Outcome()
        outcome.foldersCreated = newFolders.count
        // Each tree by the folder it is made at: the highest folder of the
        // new one's path that is not there yet.
        var treeOrder: [String] = []
        var treeRoot: [String: URL] = [:]
        var treeFolders: [String: [String]] = [:]
        var treeFiles: [String: [String: Data]] = [:]
        var rootOfNewFolder: [String: (key: String, inside: String)] = [:]
        let coursePath: String = courseDirectory.standardizedFileURL.path
        for folder in newFolders {
            var root: URL = folder.standardizedFileURL
            var parent: URL = root.deletingLastPathComponent()
            while parent.path.hasPrefix(coursePath + "/") && !FileManager.default.fileExists(atPath: parent.path) {
                root = parent
                parent = root.deletingLastPathComponent()
            }
            let key: String = root.path
            if treeRoot[key] == nil {
                treeOrder.append(key)
                treeRoot[key] = root
                treeFolders[key] = []
                treeFiles[key] = [:]
            }
            var inside: String = ""
            let folderPath: String = folder.standardizedFileURL.path
            if folderPath != key {
                inside = String(folderPath.dropFirst(key.count + 1))
                var walked: String = ""
                for part in inside.split(separator: "/") {
                    walked = walked.isEmpty ? String(part) : walked + "/" + String(part)
                    if !(treeFolders[key] ?? []).contains(walked) {
                        treeFolders[key]?.append(walked)
                    }
                }
            }
            rootOfNewFolder[folderPath] = (key: key, inside: inside)
        }
        for page in pages {
            let pageURL: URL = courseDirectory.appendingPathComponent(page.relativePath)
            let folderPath: String = pageURL.deletingLastPathComponent().standardizedFileURL.path
            guard let place = rootOfNewFolder[folderPath] else {
                continue
            }
            let name: String = pageURL.lastPathComponent
            let pathInTree: String = place.inside.isEmpty ? name : place.inside + "/" + name
            treeFiles[place.key]?[pathInTree] = Data(page.text.utf8)
            if name == templateFileName {
                outcome.templatesWritten += 1
            } else {
                outcome.indexPagesWritten += 1
            }
        }
        for key in treeOrder {
            guard let root = treeRoot[key] else {
                continue
            }
            step.makeTree(at: root, folders: treeFolders[key] ?? [], files: treeFiles[key] ?? [:])
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
