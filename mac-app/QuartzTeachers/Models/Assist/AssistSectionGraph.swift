import Foundation

/// One page of a section, as the tools see it.
struct AssistSectionPage {

    // MARK: - Stored properties

    /// The file name without `.md` — which is also the name links use.
    ///
    /// This is an IDENTITY, not a label. Wikilinks resolve by file name, so
    /// every lookup in this graph goes through it and it must never be
    /// replaced by something a teacher would rather read. What to SHOW them
    /// is `displayTitle`, which is a different question with a different
    /// answer.
    let title: String

    /// What the teacher sees this page called — on the site, in Obsidian's
    /// sidebar, and therefore in anything the assistant says about it.
    ///
    /// Usually the same as `title`, and emphatically not always. A folder's
    /// landing page is `index.md` in every folder, so naming it by its file
    /// gives "index" — which is not what the teacher calls it, and is the
    /// same word for eleven different pages. Reported from a real course:
    /// unpublishing a class explained that "index" still linked to a page,
    /// when the page a teacher would go and look at is called Portfolios.
    let displayTitle: String

    let fileURL: URL

    /// The path a teacher would recognise, relative to the working folder.
    let relativePath: String

    /// True when the page lives in this section's own folder.
    let isSectionLocal: Bool

    /// True when students meet this page as things stand.
    let isVisibleToStudents: Bool

    /// The day the page's frontmatter puts it on, or nil when it has none.
    let date: CalendarDay?

    /// The pages this one links to, lowercased, as wikilink targets.
    let linkedTitles: [String]

    /// What THIS course calls the folder its class pages live in — "All
    /// Classes" by convention, and not always. Carried on the page rather than
    /// worked out from the path, because the answer comes from the course's
    /// own configured per-section folders and a path cannot know it.
    let classFolderName: String

    // MARK: - Computed properties

    /// A folder's landing page. Never a lesson, and never an orphan: it is the
    /// way IN to a folder rather than a page anything links to.
    var isFolderIndex: Bool {
        return fileURL.lastPathComponent.lowercased() == "index.md"
    }

    /// A class page — one period of the course.
    ///
    /// These are the ROOTS of a section, not its leaves. The rule the example
    /// content is built to is that every page must be reachable FROM a class
    /// page; a class page itself is reached through the site's own navigation
    /// of All Classes, and normally nothing wikilinks to it.
    ///
    /// So "nothing links to this" is the ordinary, correct state for a class
    /// page, and counting them as orphans made a healthy course look broken:
    /// a real 86-period credit reported 84 pages "linked from nowhere", which
    /// were its lessons.
    ///
    /// The rule lives in `ClassFolder` and is pinned by
    /// `contracts/class-planning.json` → `classFolder`. This used to sniff the
    /// page's immediate parent for the word "class", which was one of four
    /// implementations that disagreed with each other — and which answered
    /// "no" for a lesson filed one folder deeper, since only the immediate
    /// parent was ever looked at.
    var isClassPage: Bool {
        if isFolderIndex {
            return false
        }
        return ClassFolder.isClassPage(relativePath: relativePath, classFolder: classFolderName)
    }

    var lowercasedTitle: String {
        return title.lowercased()
    }
}

/// A link on one page that leads to another.
struct AssistSectionLink {

    // MARK: - Stored properties

    let fromRelativePath: String
    let toTitle: String
}

/// Every page in one section, what links to what, and who can see it.
///
/// Built by reading the files, once, so that every tool that needs to follow a
/// link — publishing a class along with what it uses, checking what students
/// would meet — works from the same picture rather than each walking the folder
/// its own way.
struct AssistSectionGraph {

    // MARK: - Stored properties

    let courseCode: String
    let sectionNumber: Int
    let pages: [AssistSectionPage]

    /// Every page by its lowercased title, so a link resolves the way Obsidian
    /// resolves it — without regard to case.
    private let pagesByTitle: [String: AssistSectionPage]

    // MARK: - Computed properties

    var visiblePageCount: Int {
        var count: Int = 0
        for page in pages {
            if page.isVisibleToStudents {
                count += 1
            }
        }
        return count
    }

    // MARK: - Initializer

    init(courseCode: String, sectionNumber: Int, pages: [AssistSectionPage]) {
        self.courseCode = courseCode
        self.sectionNumber = sectionNumber
        self.pages = pages

        var byTitle: [String: AssistSectionPage] = [:]
        for page in pages {
            // First one wins, and pages arrive in path order, so the answer is
            // the same every time two folders hold a page of the same name.
            if byTitle[page.lowercasedTitle] == nil {
                byTitle[page.lowercasedTitle] = page
            }
        }
        pagesByTitle = byTitle
    }

    // MARK: - Functions

    /// Read one section's pages off disk.
    static func read(forSection sectionNumber: Int, in course: Course, workspaceURL: URL?) -> AssistSectionGraph {
        var pages: [AssistSectionPage] = []
        for pageURL in ClassPages.pagesOfSection(sectionNumber, in: course) {
            guard let text = try? String(contentsOf: pageURL, encoding: .utf8) else {
                continue
            }
            let isSectionLocal: Bool = AssistPageVisibility.isSectionLocal(
                pageAt: pageURL, forSection: sectionNumber, in: course
            )
            let dateKey: String = PageFrontmatter.createdKey(
                forSection: sectionNumber, isSectionLocal: isSectionLocal
            )
            pages.append(AssistSectionPage(
                title: pageURL.deletingPathExtension().lastPathComponent,
                displayTitle: displayName(forPageAt: pageURL, in: text),
                fileURL: pageURL,
                relativePath: relativePath(of: pageURL, workspaceURL: workspaceURL),
                isSectionLocal: isSectionLocal,
                isVisibleToStudents: AssistPageVisibility.publishes(
                    in: text, forSection: sectionNumber, isSectionLocal: isSectionLocal
                ),
                date: PageFrontmatter.createdDay(in: text, key: dateKey),
                linkedTitles: linkTargets(in: text),
                classFolderName: ClassFolder.name(for: course)
            ))
        }
        return AssistSectionGraph(courseCode: course.code, sectionNumber: sectionNumber, pages: pages)
    }

    /// What a teacher calls this page, which is not always what the file is
    /// called.
    ///
    /// **Deliberately the same rule the site's own sidebar uses**, copied from
    /// Quartz rather than guessed at, because the whole point is that the
    /// assistant names a page the way the teacher will find it. Quartz's
    /// `fileTrie.ts` computes a node's `displayName` as:
    ///
    /// ```
    /// const nonIndexTitle = this.data?.title === "index" ? undefined : this.data?.title
    /// return displayNameOverride ?? nonIndexTitle ?? fileSegmentHint ?? slugSegment ?? ""
    /// ```
    ///
    /// which is, in order: the frontmatter `title:` — **unless it is literally
    /// "index"**, which is thrown away — then the folder's own path segment.
    /// The three steps here are that, for one page:
    ///
    /// 1. the frontmatter `title:`, which every page the wizard writes has;
    /// 2. for `index.md`, the FOLDER's name — the thing a teacher sees in the
    ///    sidebar as "Portfolios";
    /// 3. otherwise the file name, which is the ordinary case.
    ///
    /// Step 2 earns its place even though step 1 nearly always answers first: a
    /// page a teacher wrote by hand in Obsidian carries no frontmatter title at
    /// all, and without it every folder in the course would be called "index".
    /// The "unless it is literally index" guard is Quartz's and is kept for the
    /// same reason it exists there — a title of "index" is the one answer that
    /// is never worth showing anybody.
    ///
    /// If Quartz's rule ever changes, this is the place to follow it.
    static func displayName(forPageAt url: URL, in pageText: String) -> String {
        if let declared = PageFrontmatter.rawValue(forKey: "title", in: pageText) {
            let tidied: String = declared
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .whitespaces)
            if !tidied.isEmpty && tidied.lowercased() != "index" {
                return tidied
            }
        }
        let fileName: String = url.deletingPathExtension().lastPathComponent
        if fileName.lowercased() == "index" {
            let folder: String = url.deletingLastPathComponent().lastPathComponent
            if !folder.isEmpty {
                return folder
            }
        }
        return fileName
    }

    /// The page with this title, however it was capitalised, and whether or not
    /// the teacher wrote the folder in front of it.
    func page(titled title: String) -> AssistSectionPage? {
        let tidied: String = normalized(title)
        if tidied.isEmpty {
            return nil
        }
        return pagesByTitle[tidied]
    }

    /// The pages these ones link to, and the pages THOSE link to, and so on.
    ///
    /// Transitive on purpose. "Publish tomorrow's class and everything it links
    /// to" means the concept page the class points at AND the snippet that
    /// concept page points at; stopping at one hop leaves a student one click
    /// from nothing.
    func linkedPages(from starting: [AssistSectionPage]) -> [AssistSectionPage] {
        var seen: Set<String> = []
        for page in starting {
            seen.insert(page.lowercasedTitle)
        }

        var found: [AssistSectionPage] = []
        var queue: [AssistSectionPage] = starting
        while !queue.isEmpty {
            let page: AssistSectionPage = queue.removeFirst()
            for target in page.linkedTitles {
                if seen.contains(target) {
                    continue
                }
                seen.insert(target)
                guard let linked = pagesByTitle[target] else {
                    // A link to something outside this section, or to a page
                    // that does not exist. Not this tool's business to invent.
                    continue
                }
                found.append(linked)
                queue.append(linked)
            }
        }
        return found
    }

    /// Links a student could click on a page they can see, that lead to a page
    /// they cannot.
    func linksIntoHiddenPages() -> [AssistSectionLink] {
        var dangling: [AssistSectionLink] = []
        for page in pages {
            if !page.isVisibleToStudents {
                continue
            }
            var alreadyReported: Set<String> = []
            for target in page.linkedTitles {
                guard let destination = pagesByTitle[target], !destination.isVisibleToStudents else {
                    continue
                }
                if alreadyReported.contains(target) {
                    continue
                }
                alreadyReported.insert(target)
                dangling.append(AssistSectionLink(
                    fromRelativePath: page.relativePath, toTitle: destination.title
                ))
            }
        }
        return dangling
    }

    /// Visible pages nothing links to.
    ///
    /// These are the pages no publish or hide rule that follows links will ever
    /// reach, and students find them anyway through the site's explorer. Folder
    /// landing pages are left out: an `index.md` is the way in to a folder, not
    /// a page anybody was ever going to link to.
    func visiblePagesNothingLinksTo() -> [AssistSectionPage] {
        var linkedFromSomewhere: Set<String> = []
        for page in pages {
            for target in page.linkedTitles {
                linkedFromSomewhere.insert(target)
            }
        }

        var orphans: [AssistSectionPage] = []
        for page in pages {
            if !page.isVisibleToStudents || page.isFolderIndex || page.isClassPage {
                continue
            }
            if linkedFromSomewhere.contains(page.lowercasedTitle) {
                continue
            }
            orphans.append(page)
        }
        return orphans
    }

    /// Every wikilink target on a page, lowercased.
    ///
    /// The pattern is `WikiLinkRewriter`'s own, so a link this reads is exactly
    /// a link a rename would rewrite — one definition of "a link", not two.
    static func linkTargets(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: WikiLinkRewriter.pattern) else {
            return []
        }
        let whole: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var targets: [String] = []
        var seen: Set<String> = []
        for match in expression.matches(in: text, range: whole) {
            guard let targetRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            let target: String = normalized(String(text[targetRange]))
            if target.isEmpty || seen.contains(target) {
                continue
            }
            seen.insert(target)
            targets.append(target)
        }
        return targets
    }

    /// A link target or a teacher's page name reduced to the form the index
    /// uses: no folder in front, no `.md` on the end, no case.
    static func normalized(_ name: String) -> String {
        var tidied: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastSlash = tidied.lastIndex(of: "/") {
            tidied = String(tidied[tidied.index(after: lastSlash)...])
        }
        if tidied.lowercased().hasSuffix(".md") {
            tidied = String(tidied.dropLast(3))
        }
        return tidied.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func normalized(_ name: String) -> String {
        return AssistSectionGraph.normalized(name)
    }

    /// Where a page sits, said the way a teacher would say it.
    static func relativePath(of url: URL, workspaceURL: URL?) -> String {
        let full: String = url.standardizedFileURL.path
        guard let workspaceURL else {
            return full
        }
        let root: String = workspaceURL.standardizedFileURL.path + "/"
        if full.hasPrefix(root) {
            return String(full.dropFirst(root.count))
        }
        return full
    }
}
