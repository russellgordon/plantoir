import Foundation

/// Creates a brand-new section for an existing course — the reverse of
/// removing one. The scaffolding mirrors what the setup wizard builds for
/// each section: a `sectionN/` folder with its `index.md`, plus whichever
/// per-section folders and files the course's settings call for. Shared
/// folders and files already exist at the course level and are left alone.
enum SectionAdder {

    // MARK: - Types

    /// Why a section could not be added, in words a teacher can act on.
    enum Problem: LocalizedError {
        case sectionAlreadyListed(String, Int)
        case folderInTheWay(String, Int)

        var errorDescription: String? {
            switch self {
            case .sectionAlreadyListed(let code, let number):
                return "Section \(number) of \(code) already exists."
            case .folderInTheWay(let code, let number):
                return "A folder for section \(number) of \(code) is already on disk. Move it aside first — it may hold work you want to keep."
            }
        }
    }

    // MARK: - Functions

    /// Adds one section: scaffolds its folder and adds its number to the
    /// course's settings, keeping the numbers in order. Nothing is ever
    /// written over — a folder already at the destination stops the add,
    /// because whatever is in the way may be newer work.
    static func addSection(_ sectionNumber: Int, to course: Course) throws {
        if course.sectionNumbers.contains(sectionNumber) {
            throw Problem.sectionAlreadyListed(course.code, sectionNumber)
        }

        let fileManager: FileManager = FileManager.default
        let sectionURL: URL = course.sectionDirectoryURL(forSection: sectionNumber)
        if fileManager.fileExists(atPath: sectionURL.path) {
            throw Problem.folderInTheWay(course.code, sectionNumber)
        }

        let created: String = timestamp()
        try fileManager.createDirectory(at: sectionURL, withIntermediateDirectories: true)

        // A new section should behave like the sections beside it — the same
        // pages published, the same pages held back, the same display flags,
        // and the same unit/day class files and notes. When an existing sibling
        // section is present, replicate its folder and file tree.
        if let siblingURL = lowestExistingSiblingSectionURL(in: course) {
            try replicateSiblingSection(
                from: siblingURL,
                to: sectionURL,
                course: course,
                sectionNumber: sectionNumber,
                created: created
            )
        }

        // Ensure the landing page and any configured per-section folders and
        // files exist, falling back to templates if there was no sibling or
        // if the sibling was missing them.
        let indexURL: URL = sectionURL.appendingPathComponent("index.md")
        if !fileManager.fileExists(atPath: indexURL.path) {
            let indexFrontmatter: String = scaffoldFrontmatter(
                sibling: siblingFile(named: "index.md", in: course),
                replacingTitleWith: sectionTitle(for: course, sectionNumber: sectionNumber),
                created: created
            )
            let indexBody: String = """
            ---
            \(indexFrontmatter)
            ---
            """
            try indexBody.write(to: indexURL, atomically: true, encoding: .utf8)
        }

        for folderName in course.configuration.perSectionFolders {
            let folderURL: URL = sectionURL.appendingPathComponent(folderName)
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let folderIndexURL: URL = folderURL.appendingPathComponent("index.md")
            if !fileManager.fileExists(atPath: folderIndexURL.path) {
                let folderFrontmatter: String = scaffoldFrontmatter(
                    sibling: siblingFile(named: "\(folderName)/index.md", in: course),
                    replacingTitleWith: nil,
                    fallbackTitle: folderName,
                    created: created
                )
                let folderIndex: String = """
                ---
                \(folderFrontmatter)
                ---
                This is the **\(folderName)** folder. Add Markdown files to this folder to build out your site.
                """
                try folderIndex.write(to: folderIndexURL, atomically: true, encoding: .utf8)
            }
        }

        for fileName in course.configuration.perSectionFiles {
            let fileURL: URL = sectionURL.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: fileURL.path) {
                let isUnpublished: Bool = SectionAdder.unpublishedFileNames.contains(fileName)
                let fileFrontmatter: String = scaffoldFrontmatter(
                    sibling: siblingFile(named: fileName, in: course),
                    replacingTitleWith: nil,
                    fallbackTitle: fileName.replacingOccurrences(of: ".md", with: ""),
                    fallbackIsDraft: isUnpublished,
                    created: created
                )
                let bodyText: String = isUnpublished
                    ? "This is the per-section file **\(fileName)**. It is marked `publish: false`, so it stays out of the built site — a private place for your own notes."
                    : "This is the per-section file **\(fileName)**."
                let fileBody: String = """
                ---
                \(fileFrontmatter)
                ---
                \(bodyText)
                """
                try fileBody.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }

        // Course-level pages are shared by every section, but each section
        // decides for itself when a page appeared and whether it is
        // published — that is what `createdSectionN` / `publishForSectionN` are
        // for. A page that has those keys for the existing sections needs a
        // pair for this one too, or the new section builds it with no date
        // and no publishing state at all.
        extendCourseLevelPages(in: course, toInclude: sectionNumber, created: created)

        // Only once the folder is safely in place does the section join the
        // course's settings — the same order restore uses, so a failure
        // partway never leaves the settings pointing at nothing.
        var numbers: [Int] = course.sectionNumbers
        numbers.append(sectionNumber)
        numbers.sort()
        course.configuration.setSectionNumbers(numbers)
        try course.configuration.write(to: course.configFileURL)
    }

    /// Finds the directory of the lowest-numbered section in the course that exists on disk.
    static func lowestExistingSiblingSectionURL(in course: Course) -> URL? {
        var numbers: [Int] = course.sectionNumbers
        numbers.sort()
        let fileManager: FileManager = FileManager.default
        for number in numbers {
            let candidate: URL = course.sectionDirectoryURL(forSection: number)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    /// Recursively copies all directories and files from an existing sibling
    /// section into the new section's folder, adapting markdown frontmatter
    /// (title for index.md, refreshed created dates for top-level files) while
    /// preserving all body text, lesson notes, and frontmatter flags.
    static func replicateSiblingSection(
        from siblingURL: URL,
        to destinationURL: URL,
        course: Course,
        sectionNumber: Int,
        created: String
    ) throws {
        let fileManager: FileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: siblingURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let resolvedSiblingURL: URL = siblingURL.resolvingSymlinksInPath().standardizedFileURL
        let siblingPrefix: String = resolvedSiblingURL.path.hasSuffix("/")
            ? resolvedSiblingURL.path
            : resolvedSiblingURL.path + "/"

        while let itemURL = enumerator.nextObject() as? URL {
            let resolvedItemURL: URL = itemURL.resolvingSymlinksInPath().standardizedFileURL
            let itemPath: String = resolvedItemURL.path
            guard itemPath.hasPrefix(siblingPrefix) else {
                continue
            }
            let relativePath: String = String(itemPath.dropFirst(siblingPrefix.count))
            if relativePath.isEmpty {
                continue
            }

            let targetURL: URL = destinationURL.appendingPathComponent(relativePath)
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory: Bool = resourceValues?.isDirectory ?? false

            if isDirectory {
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if itemURL.pathExtension == "md" {
                    try replicateMarkdownFile(
                        from: itemURL,
                        to: targetURL,
                        relativePath: relativePath,
                        course: course,
                        sectionNumber: sectionNumber,
                        created: created
                    )
                } else {
                    try fileManager.copyItem(at: itemURL, to: targetURL)
                }
            }
        }
    }

    /// Replicates a single markdown file from a sibling section to the new section.
    /// Title is recomputed for the landing page (`index.md`), `created:` is freshened
    /// for top-level files (`index.md` and `perSectionFiles`), and all other metadata
    /// and body content are preserved verbatim.
    static func replicateMarkdownFile(
        from sourceURL: URL,
        to destinationURL: URL,
        relativePath: String,
        course: Course,
        sectionNumber: Int,
        created: String
    ) throws {
        guard let text = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        guard let lines = frontmatterLines(ofFileAt: sourceURL) else {
            try text.write(to: destinationURL, atomically: true, encoding: .utf8)
            return
        }

        let isRootIndex: Bool = relativePath == "index.md"
        let isTopLevelPerSectionFile: Bool = course.configuration.perSectionFiles.contains(relativePath)

        var newLines: [String] = []
        for line in lines {
            if isRootIndex && line.hasPrefix("title:") {
                let newTitle: String = sectionTitle(for: course, sectionNumber: sectionNumber)
                newLines.append("title: \(newTitle)")
            } else if (isRootIndex || isTopLevelPerSectionFile) && line.hasPrefix("created:") {
                newLines.append("created: \(created)")
            } else {
                newLines.append(line)
            }
        }

        let prefixToDrop: Int = ("---\n" + lines.joined(separator: "\n")).count
        let restOfText: String = String(text.dropFirst(prefixToDrop))
        let rewritten: String = "---\n" + newLines.joined(separator: "\n") + restOfText
        try rewritten.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    /// Every markdown page at the course level — the shared folders and
    /// files, everything outside the `sectionN` folders — gains a
    /// `createdSectionN` / `publishForSectionN` pair for the section being added.
    ///
    /// The new section takes the LOWEST existing section's publishing state,
    /// for the same reason the scaffolded files copy a sibling's: a section
    /// added later should behave like the sections beside it. The date is
    /// fresh, because the page did not appear in this section until now.
    /// Pages with no per-section keys are left alone — a plain `created:`
    /// already applies to every section, including this one.
    static func extendCourseLevelPages(in course: Course, toInclude sectionNumber: Int, created: String) {
        var sectionFolderNames: Set<String> = Set<String>()
        for number in course.sectionNumbers {
            sectionFolderNames.insert("section\(number)")
        }
        let fileManager: FileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: course.directoryURL, includingPropertiesForKeys: nil
        ) else {
            return
        }
        while let entry = enumerator.nextObject() as? URL {
            if sectionFolderNames.contains(entry.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if entry.pathExtension != "md" {
                continue
            }
            extendFrontmatter(ofPageAt: entry, toInclude: sectionNumber, created: created)
        }
    }

    /// One page's frontmatter, given a pair for the new section. Only the
    /// frontmatter block is read: a `publish: false` shown inside a fenced code
    /// block further down the page is documentation, not metadata.
    static func extendFrontmatter(ofPageAt url: URL, toInclude sectionNumber: Int, created: String) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let lines = frontmatterLines(ofFileAt: url) else {
            return
        }
        if alreadyHasKeys(for: sectionNumber, in: lines) {
            return
        }

        var lowestSection: Int? = nil
        for line in lines {
            guard let number = perSectionKeyNumber(in: line) else {
                continue
            }
            if lowestSection == nil || number < lowestSection! {
                lowestSection = number
            }
        }
        guard let source = lowestSection else {
            return
        }

        var addition: [String] = ["createdSection\(sectionNumber): \(created)"]
        if let publish = publishValue(forSection: source, in: lines) {
            addition.append("publishForSection\(sectionNumber): \(publish)")
        }

        // The pair goes after the last per-section key, so each section's
        // lines stay together and in order.
        var updated: [String] = []
        var lastKeyIndex: Int = -1
        for (index, line) in lines.enumerated() where perSectionKeyNumber(in: line) != nil {
            lastKeyIndex = index
        }
        for (index, line) in lines.enumerated() {
            updated.append(line)
            if index == lastKeyIndex {
                updated.append(contentsOf: addition)
            }
        }

        let body: String = String(text.dropFirst(("---\n" + lines.joined(separator: "\n")).count))
        let rewritten: String = "---\n" + updated.joined(separator: "\n") + body
        try? rewritten.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Does this page already carry the new section's keys?
    static func alreadyHasKeys(for sectionNumber: Int, in lines: [String]) -> Bool {
        let prefixes: [String] = [
            "createdSection\(sectionNumber):",
            "publishForSection\(sectionNumber):",
            "draftSection\(sectionNumber):",
        ]
        for line in lines {
            for prefix in prefixes {
                if line.hasPrefix(prefix) {
                    return true
                }
            }
        }
        return false
    }

    /// Whether a section publishes this page, as the string to write back.
    ///
    /// Visibility is `publishForSectionN`. `draftSectionN` is the older
    /// spelling with the OPPOSITE polarity, so a course written before the
    /// rename is read and inverted — carrying it across unchanged would
    /// publish a page the teacher had held back.
    static func publishValue(forSection sectionNumber: Int, in lines: [String]) -> String? {
        let publishPrefix: String = "publishForSection\(sectionNumber):"
        for line in lines where line.hasPrefix(publishPrefix) {
            return String(line.dropFirst(publishPrefix.count)).trimmingCharacters(in: .whitespaces)
        }

        let draftPrefix: String = "draftSection\(sectionNumber):"
        for line in lines where line.hasPrefix(draftPrefix) {
            let value: String = String(line.dropFirst(draftPrefix.count)).trimmingCharacters(in: .whitespaces)
            return value.lowercased() == "true" ? "false" : "true"
        }
        return nil
    }

    /// The section number in a per-section key.
    static func perSectionKeyNumber(in line: String) -> Int? {
        for prefix in ["createdSection", "publishForSection", "draftSection"] {
            guard line.hasPrefix(prefix) else {
                continue
            }
            let rest: Substring = line.dropFirst(prefix.count)
            guard let colon = rest.firstIndex(of: ":") else {
                continue
            }
            return Int(rest[rest.startIndex..<colon])
        }
        return nil
    }

    /// The same file in an existing section, if any section has it — the
    /// lowest-numbered one wins, so the choice is predictable.
    static func siblingFile(named relativePath: String, in course: Course) -> URL? {
        var numbers: [Int] = course.sectionNumbers
        numbers.sort()
        for number in numbers {
            let candidate: URL = course.sectionDirectoryURL(forSection: number).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Pages that exist for the teacher's own eyes — the wizard creates
    /// them held back so they are never published, and a section added
    /// with no sibling to imitate must do the same.
    static let unpublishedFileNames: Set<String> = ["Private Notes.md", "Scratch Page.md"]

    /// The frontmatter for one scaffolded file. A sibling's frontmatter is
    /// carried over whole — publish status, table-of-contents and backlink
    /// flags, anything else the teacher set — with only `created:` freshened
    /// and, when a new title is given, the title swapped. Without a sibling,
    /// the wizard's plain template stands in.
    static func scaffoldFrontmatter(
        sibling: URL?,
        replacingTitleWith newTitle: String?,
        fallbackTitle: String? = nil,
        fallbackIsDraft: Bool = false,
        created: String
    ) -> String {
        if let sibling, let siblingLines = frontmatterLines(ofFileAt: sibling) {
            var result: [String] = []
            for line in siblingLines {
                if line.hasPrefix("created:") {
                    result.append("created: \(created)")
                } else if line.hasPrefix("title:"), let newTitle {
                    result.append("title: \(newTitle)")
                } else {
                    result.append(line)
                }
            }
            return result.joined(separator: "\n")
        }
        let title: String = newTitle ?? fallbackTitle ?? ""
        let publish: String = fallbackIsDraft ? "false" : "true"
        return "title: \(title)\ncreated: \(created)\npublish: \(publish)"
    }

    /// The lines between a file's opening and closing `---` markers, or nil
    /// when the file has no frontmatter to speak of.
    static func frontmatterLines(ofFileAt url: URL) -> [String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let lines: [String] = text.components(separatedBy: "\n")
        guard lines.first == "---" else {
            return nil
        }
        var collected: [String] = []
        var index: Int = 1
        while index < lines.count {
            if lines[index] == "---" {
                return collected
            }
            collected.append(lines[index])
            index += 1
        }
        return nil
    }

    /// The new section's landing-page title. A sibling section's title with
    /// the section number swapped is the most faithful source — it keeps
    /// whatever wording the teacher chose. Failing that, the wizard's form,
    /// without doubling the grade when the course name already leads with it
    /// ("Grade 9 Science" must not become "Grade 9 Grade 9 Science").
    static func sectionTitle(for course: Course, sectionNumber: Int) -> String {
        if let siblingIndex = siblingFile(named: "index.md", in: course),
           let siblingLines = frontmatterLines(ofFileAt: siblingIndex) {
            for line in siblingLines {
                if line.hasPrefix("title:") {
                    let siblingTitle: String = String(line.dropFirst("title:".count)).trimmingCharacters(in: .whitespaces)
                    if let range = siblingTitle.range(of: #"Section \d+$"#, options: .regularExpression) {
                        return siblingTitle.replacingCharacters(in: range, with: "Section \(sectionNumber)")
                    }
                }
            }
        }
        let gradeLabel: String = SectionAdder.gradeLabel(forCourseCode: course.code)
        let courseName: String = course.configuration.courseName
        // Deliberately literal, matching the build: the switch alone
        // decides. The settings warn when the name already carries the
        // grade; resolving that is the teacher's call, never guessed.
        var titlePrefix: String = ""
        if course.configuration.showsGradeInTitle(forSection: sectionNumber) && !gradeLabel.isEmpty {
            titlePrefix = "\(gradeLabel) "
        }
        return "\(titlePrefix)\(courseName), Section \(sectionNumber)"
    }

    /// The grade named by the course code, matching the wizard:
    /// "ICS3U" → "Grade 11", "MCMPR11" → "Grade 11", "MMA--09" → "Grade 9".
    /// A club code like "CODING" has no grade, so no grade label at all.
    static func gradeLabel(forCourseCode code: String) -> String {
        let trimmed: String = code.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return ""
        }

        // 1. Check for trailing 2-digit grade numbers common in BC (e.g. MCMPR11, MFMP-10, MMA--09)
        if trimmed.hasSuffix("09") || trimmed.hasSuffix("-09") {
            return "Grade 9"
        }
        if trimmed.hasSuffix("10") || trimmed.hasSuffix("-10") {
            return "Grade 10"
        }
        if trimmed.hasSuffix("11") || trimmed.hasSuffix("-11") {
            return "Grade 11"
        }
        if trimmed.hasSuffix("12") || trimmed.hasSuffix("-12") {
            return "Grade 12"
        }

        // 2. Check for Ontario course codes (4th character is digit 1–4)
        let characters: [Character] = Array(trimmed)
        if characters.count >= 4 {
            let gradeCharacter: Character = characters[3]
            if gradeCharacter.isNumber {
                switch gradeCharacter {
                case "1": return "Grade 9"
                case "2": return "Grade 10"
                case "3": return "Grade 11"
                case "4": return "Grade 12"
                default: return "Grade ?"
                }
            }
        }

        return ""
    }

    /// The `created:` timestamp, in the same form the wizard writes:
    /// `2026-08-10T14:30:00.000-0400`.
    static func timestamp(for date: Date = Date()) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.000Z"
        return formatter.string(from: date)
    }

    /// The number the sheet should offer first: the smallest section number
    /// not already in use, so "add section 1" and "add the next one" are
    /// each a single click.
    static func suggestedNumber(existing: [Int]) -> Int {
        var candidate: Int = 1
        while existing.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    /// What is wrong with the typed section number, or nil when nothing is —
    /// worded like the wizard's own warnings. An empty field is quietly
    /// invalid: nothing has been said yet, so there is nothing to warn about.
    static func entryProblem(_ entry: String, existing: [Int], courseCode: String) -> String? {
        let trimmed: String = entry.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return nil
        }
        guard let number = Int(trimmed) else {
            return "“\(trimmed)” isn’t a section number — sections are 1 or higher."
        }
        if number < 1 {
            return "“\(trimmed)” isn’t a section number — sections are 1 or higher."
        }
        if existing.contains(number) {
            return "Section \(number) of \(courseCode) already exists."
        }
        return nil
    }

    /// True when the typed entry names a section that can be added right now.
    static func entryIsAddable(_ entry: String, existing: [Int]) -> Bool {
        let trimmed: String = entry.trimmingCharacters(in: .whitespaces)
        guard let number = Int(trimmed) else {
            return false
        }
        return number >= 1 && !existing.contains(number)
    }
}
