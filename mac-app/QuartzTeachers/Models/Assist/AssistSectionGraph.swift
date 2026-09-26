import Foundation

/// One page of a section, as the tools see it.
///
/// `nonisolated`: a plain value with no course in it. Copying a page between
/// courses builds these off the main actor, so that the #173 walk below can be
/// CALLED rather than re-implemented.
nonisolated struct AssistSectionPage {

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
    ///
    /// Read the way the BUILT SITE reads it, and when the page's flag is one
    /// this app will not guess at, this says VISIBLE — the mild mistake of the
    /// two, since calling a page hidden while students are reading it is the
    /// failure that reports success. `visibilityIsCertain` is how anything
    /// that WRITES tells the two apart.
    let isVisibleToStudents: Bool

    /// False when the page's flag is a form this app will not read — a value
    /// on the line below the key, a tag, a block scalar, an anchor.
    ///
    /// Anything deciding a page is "already the way you asked" must require
    /// this. Without it, "publish this page" on such a page answered that it
    /// was already published and wrote nothing, while the build was holding it
    /// back — the exact failure this whole reader exists to remove.
    let visibilityIsCertain: Bool

    /// The day the page's frontmatter puts it on, or nil when it has none.
    let date: CalendarDay?

    /// The pages this one links to, lowercased, as wikilink targets.
    let linkedTitles: [String]

    /// What THIS course calls the folders its class pages live in — "All
    /// Classes" by convention, and not always, and not necessarily one.
    /// Carried on the page rather than worked out from the path, because the
    /// answer comes from the course's own configured per-section folders and a
    /// path cannot know it.
    let classFolderNames: [String]

    /// The page's path relative to its SECTION folder.
    ///
    /// Separate from `relativePath`, which is relative to the working folder —
    /// and which is the FULL ABSOLUTE PATH whenever `workspaceURL` is nil, as
    /// `SectionIndexPointer.repointIndex` passes it. Asking the class-page
    /// question of that string meant a teacher whose working folder was
    /// `~/Documents/All Classes` made every page in every course a class page.
    let pathWithinSection: String

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
        return ClassFolder.isClassPage(
            relativePath: pathWithinSection, classFolders: classFolderNames
        )
    }

    var lowercasedTitle: String {
        return title.lowercased()
    }
}

/// A link on one page that leads to another.
nonisolated struct AssistSectionLink {

    // MARK: - Stored properties

    let fromRelativePath: String
    let toTitle: String
}

/// What following one or more pages' links reaches, and the class pages the
/// walk stopped at on the way.
///
/// Two halves rather than one list, because a caller needs both and they mean
/// opposite things: the first is what a verb acts on, the second is what a
/// teacher has to be TOLD was left alone. Returning only the first made the
/// stop invisible — a plan quietly smaller than the one the teacher pictured,
/// with no way to tell "it decided" from "it missed it".
nonisolated struct AssistLinkedReach {

    // MARK: - Stored properties

    /// The material reached: transitive, and never a class page.
    let pages: [AssistSectionPage]

    /// The class pages a link landed on, which the walk did not enter.
    ///
    /// Never one of the pages it started from — those are seeded as seen
    /// before the walk begins, so a class the teacher NAMED is not reported
    /// here as one that was left alone.
    let classPagesStoppedAt: [AssistSectionPage]
}

/// Every page in one section, what links to what, and who can see it.
///
/// Built by reading the files, once, so that every tool that needs to follow a
/// link — publishing a class along with what it uses, checking what students
/// would meet — works from the same picture rather than each walking the folder
/// its own way.
nonisolated struct AssistSectionGraph {

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
    @MainActor
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
            let visibility: PageVisibilityAnswer = AssistPageVisibility.answer(
                in: text, forSection: sectionNumber
            )
            pages.append(AssistSectionPage(
                title: pageURL.deletingPathExtension().lastPathComponent,
                displayTitle: displayName(forPageAt: pageURL, in: text),
                fileURL: pageURL,
                relativePath: relativePath(of: pageURL, workspaceURL: workspaceURL),
                isSectionLocal: isSectionLocal,
                isVisibleToStudents: visibility != .hidden,
                visibilityIsCertain: visibility != .cannotTell,
                date: PageFrontmatter.createdDay(in: text, key: dateKey),
                linkedTitles: linkTargets(in: text),
                classFolderNames: ClassFolder.names(for: course),
                pathWithinSection: pathWithinSection(of: pageURL, forSection: sectionNumber, in: course)
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

    /// The page a link leads to, the way the site resolves it: by file name,
    /// whatever the capitals — and, failing that, a folder named that whose
    /// landing page (`index.md`) is in this section, since "[[Unit 2]]"
    /// written for a folder reaches its landing page on the site (#167).
    func pageALinkLeadsTo(_ target: String) -> AssistSectionPage? {
        if let page = page(titled: target) {
            return page
        }
        let wanted: String = normalized(target)
        if wanted.isEmpty {
            return nil
        }
        for page in pages where page.isFolderIndex {
            let folder: String = page.fileURL.deletingLastPathComponent().lastPathComponent
            if folder.lowercased() == wanted {
                return page
            }
        }
        return nil
    }

    /// Every page a teacher may mean by `title` — by file name first, because
    /// that is how links find a page; then by the name the sidebar SHOWS, which
    /// is how a teacher finds it, including a folder's landing page named by its
    /// folder (#167).
    ///
    /// One page is the answer. Two or more by the name the sidebar shows is a
    /// question back to the teacher, never a guess. Two FILES with one name — a
    /// section's own page and a course-wide page — still resolve to the first in
    /// path order, the rule `init` already applies to every link; that is a
    /// known limit, not something this answers.
    func pagesATeacherMayMean(_ title: String) -> [AssistSectionPage] {
        if let page = page(titled: title) {
            return [page]
        }
        let wanted: String = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if wanted.isEmpty {
            return []
        }
        var found: [AssistSectionPage] = []
        for page in pages {
            var matches: Bool = page.displayTitle.lowercased() == wanted
            if page.isFolderIndex {
                let folder: String = page.fileURL.deletingLastPathComponent().lastPathComponent
                if folder.lowercased() == wanted {
                    matches = true
                }
            }
            if matches {
                found.append(page)
            }
        }
        return found
    }

    /// The pages these ones link to, and the pages THOSE link to, and so on —
    /// stopping at any class page a link lands on.
    ///
    /// Transitive on purpose. "Publish tomorrow's class and everything it links
    /// to" means the concept page the class points at AND the snippet that
    /// concept page points at; stopping at one hop leaves a student one click
    /// from nothing.
    ///
    /// **A class page is the one stop, and it is a decision rather than an
    /// oversight.** A class goes up when the teacher names THAT class, so a
    /// link landing on another class is not collected and is not followed
    /// through: material reachable only through that class belongs to it and
    /// goes up with it. Publishing Day 4's worksheet because Day 3 links to
    /// Day 4 puts it in front of students a day early and dates it to the
    /// wrong lesson. REJECTED was the middle position — leave the linked class
    /// alone but walk past it to the material beyond — for those same two
    /// reasons. Decided 2026-09-19, issue #173, after the two apps were found
    /// to disagree: Windows stopped, the mac walked through.
    /// `contracts/shared-rules.json` → `followingLinks.stopsAtAClassPage`.
    ///
    /// **The pages STARTED from are never stopped.** They are seeded as seen
    /// before the walk begins, so naming two classes makes both of them
    /// starting points, and publishing a whole unit — which names every class
    /// in it, one plan each — loses nothing.
    ///
    /// The name says `reach` rather than `linkedPages` on purpose: the rule
    /// changed under the old name's promise once already, and renaming it made
    /// the compiler hand every caller over to be read again.
    func reachFollowingLinks(from starting: [AssistSectionPage]) -> AssistLinkedReach {
        var seen: Set<String> = []
        for page in starting {
            seen.insert(page.lowercasedTitle)
        }

        var found: [AssistSectionPage] = []
        var classPagesStoppedAt: [AssistSectionPage] = []
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
                if linked.isClassPage {
                    // The walk ends here: the class is neither collected nor
                    // entered. Only the class itself was marked seen, so a
                    // page this one ALSO reaches directly is still collected.
                    classPagesStoppedAt.append(linked)
                    continue
                }
                found.append(linked)
                queue.append(linked)
            }
        }
        return AssistLinkedReach(pages: found, classPagesStoppedAt: classPagesStoppedAt)
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
    /// That includes a link whose alias pipe is escaped, `[[Ohm's Law\|Ohm]]`,
    /// as Obsidian writes it inside a table: the pattern stops the name before
    /// the backslash, so publishing follows it, the dates a class brings reach
    /// it, and the site check counts it (#294 — before then the name was read
    /// as `Ohm's Law\`, matched no page, and was silently dropped).
    ///
    /// A link written inside code is an EXAMPLE of a link, and is not read
    /// (#313): Quartz draws none, so publishing must not follow one, and the
    /// site check must not count one. The matches come from
    /// `WikiLinkRewriter.linkMatches`, the same entry point every other
    /// reader and rewriter uses. Until #313 this read every match, code and
    /// all: 1,896 across `support/`, each one a page a publish could take
    /// along that nothing on the site leads to.
    static func linkTargets(in text: String) -> [String] {
        var targets: [String] = []
        var seen: Set<String> = []
        for match in WikiLinkRewriter.linkMatches(in: text) {
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

    /// Every wiki-link on a page as the teacher WROTE it — capitals kept, each
    /// once, in the order they appear — for the answer to "what does this page
    /// link to?" (#167).
    ///
    /// The pattern is `WikiLinkRewriter`'s, so a link here is a link there, and
    /// a picture or a page EMBEDDED with `![[…]]` is included — whether it is a
    /// page is decided by what it resolves to, not by how it was written. Two
    /// things differ from `linkTargets`, and both were MEASURED across the 39
    /// example-content payloads before being chosen (2026-09-25): read this
    /// way, 30,930 links and embeds (each counted once per page) and every one
    /// resolved to a page — no dead link reported where there is none.
    ///
    /// - A link inside `code` or a fenced code block is an EXAMPLE of a link,
    ///   not a link: the Scavenger Hunt pages show `[[Page Name]]` to teach the
    ///   syntax. Read with the code left in, 188 targets came back as links to
    ///   pages that do not exist. This function used to strip code with its
    ///   own line walker; since #313 every reader shares one mask
    ///   (`WikiLinkRewriter.linkMatches`), because that walker was wrong in
    ///   both directions: it flipped its fence on any line STARTING with `~~~`,
    ///   so a Python traceback's `~~~~^^^^` inside a ```` ```text ```` block
    ///   ended the fence and the real closer opened a new one — 22 real links
    ///   dropped on four ICS4U pages — and it saw no fence inside a `>`
    ///   callout, so 270 examples on the Scavenger Hunt pages read as links.
    /// - A link inside a table escapes its pipe, `[[Ohm's Law\|Ohm]]`. When
    ///   this was written the shared pattern kept the backslash on the name,
    ///   and read that way 69 real links came back dead, so this function
    ///   stripped it by hand. Since #294 the pattern itself stops before the
    ///   backslash, for every reader, and the hand strip is gone: a second
    ///   strip here would only hide a regression of the first.
    ///
    /// So since #313 the two readers see exactly the same links, and differ
    /// only in how they hand a name back: this one as written, that one
    /// normalised for the index.
    static func linksAsWritten(in text: String) -> [String] {
        var written: [String] = []
        var seen: Set<String> = []
        for match in WikiLinkRewriter.linkMatches(in: text) {
            guard let targetRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            var target: String = String(text[targetRange]).trimmingCharacters(in: .whitespaces)
            if target.lowercased().hasSuffix(".md") {
                target = String(target.dropLast(3))
            }
            let key: String = normalized(target)
            if key.isEmpty || seen.contains(key) {
                continue
            }
            seen.insert(key)
            written.append(target)
        }
        return written
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

    /// A page's path relative to its SECTION folder, which is the form the
    /// class-page rule needs: nothing above the section can reach it, so what
    /// a teacher called their working folder cannot change what counts as a
    /// lesson. Shared pages live outside the section folder and fall back to
    /// their own last two components, which is enough for the rule to see the
    /// folder they sit in.
    @MainActor
    static func pathWithinSection(of url: URL, forSection sectionNumber: Int, in course: Course) -> String {
        let full: String = url.standardizedFileURL.path
        let root: String = course.sectionDirectoryURL(forSection: sectionNumber)
            .standardizedFileURL.path + "/"
        if full.hasPrefix(root) {
            return String(full.dropFirst(root.count))
        }
        // A page OUTSIDE the section folder — every course-level shared page,
        // which `ClassPages.pagesOfSection` deliberately includes, and any
        // section reached through a symlink, since `standardizedFileURL` does
        // not resolve those.
        //
        // The first version of this returned the last two components, which
        // put the immediate parent's name back in front of the rule — exactly
        // the discredited "does the parent mention classes" sniff, and a false
        // POSITIVE waiting to happen: a course-level folder whose name matched
        // a configured per-section folder would have made its shared pages
        // lessons. A shared page is not a class page, so say so plainly rather
        // than guessing from a fragment of path.
        return url.lastPathComponent
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
