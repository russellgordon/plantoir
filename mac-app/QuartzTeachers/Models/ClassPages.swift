import Foundation

/// A page named as a numbered day of a numbered unit — "Unit 2, Day 3".
///
/// Anything not named that way has no unit and no day, and is deliberately
/// left out of the operations that shuffle classes around: a teacher's "Field
/// Trip" or "Exam Review" cannot be renumbered without inventing a number for
/// it, and inventing one would be worse than not touching it.
///
/// `nonisolated`: pure over its arguments, and read off the main actor by the
/// unit-word rename.
nonisolated struct UnitDay: Equatable, Hashable {

    // MARK: - Stored properties

    let unit: Int
    let day: Int

    /// How this course names its class pages — its word AND its scheme.
    /// Carried on the value rather than looked up, so a page read out of a
    /// Module course cannot be written back as a Unit, nor a club's "Week 3"
    /// as "Week 1, Day 3" — the two halves of a rename are the same object.
    let naming: ClassPageNaming

    // MARK: - Computed properties

    /// The page name these numbers make: "Unit 2, Day 3", or "Week 3".
    var title: String {
        return naming.title(unit: unit, day: day)
    }

    /// What this course calls a unit (the naming's word).
    var term: String {
        return naming.word
    }

    // MARK: - Initializer

    /// A position in a course. No default naming, deliberately: see
    /// `ClassPageNaming`.
    init(unit: Int, day: Int, naming: ClassPageNaming) {
        self.unit = unit
        self.day = day
        self.naming = naming
    }

    /// The numbers inside a page name, or nil when it is named some other way.
    ///
    /// Under `numbered` the one number is the DAY of unit 1 — "Week 3" is
    /// unit 1, day 3 — so every planner that already works on (unit, day)
    /// inside one unit counts one number with no rewrite of its own.
    init?(pageTitle: String, naming: ClassPageNaming) {
        self.naming = naming
        guard let expression = try? NSRegularExpression(pattern: naming.pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let trimmed: String = pageTitle.trimmingCharacters(in: .whitespaces)
        let whole: NSRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = expression.firstMatch(in: trimmed, range: whole),
              let firstRange = Range(match.range(at: 1), in: trimmed),
              let first = Int(trimmed[firstRange]) else {
            return nil
        }
        if naming.isNumbered {
            self.unit = 1
            self.day = first
            return
        }
        guard let dayRange = Range(match.range(at: 2), in: trimmed),
              let day = Int(trimmed[dayRange]) else {
            return nil
        }
        self.unit = first
        self.day = day
    }

    // MARK: - Functions

    static func < (lhs: UnitDay, rhs: UnitDay) -> Bool {
        if lhs.unit != rhs.unit {
            return lhs.unit < rhs.unit
        }
        return lhs.day < rhs.day
    }
}

extension UnitDay: Comparable {}

/// One class page as the planners see it: what it is called, where it is, and
/// which day it sits on.
struct ClassPageSummary {

    // MARK: - Stored properties

    /// The file name without `.md` — which is also the name links use.
    let title: String

    let fileURL: URL

    /// The day the page's frontmatter puts it on, or nil when it has none.
    let date: CalendarDay?

    /// How the course names its class pages, carried here so every planner
    /// that works from a list of summaries reads and writes the same names
    /// without being handed the course as well.
    let naming: ClassPageNaming

    // MARK: - Computed properties

    /// The unit and day in the page's name, when it is named that way.
    var unitAndDay: UnitDay? {
        return UnitDay(pageTitle: title, naming: naming)
    }

    /// What the course calls a unit (the naming's word).
    var term: String {
        return naming.word
    }

    // MARK: - Initializer

    init(title: String, fileURL: URL, date: CalendarDay?, naming: ClassPageNaming) {
        self.title = title
        self.fileURL = fileURL
        self.date = date
        self.naming = naming
    }
}

/// How an operation over class pages ended.
struct ClassChangeOutcome {

    // MARK: - Stored properties

    /// What happened, in words meant to be read back to the teacher.
    let message: String

    /// The backup written before anything was touched, when one was asked for.
    let backupURL: URL?

    /// The pages this actually created, so a caller can offer to take them
    /// away again. Empty when nothing was written — including the case where
    /// every page asked for had appeared while the teacher was deciding.
    let created: [URL]

    // MARK: - Initializer

    init(message: String, backupURL: URL?, created: [URL] = []) {
        self.message = message
        self.backupURL = backupURL
        self.created = created
    }
}

/// Finding a section's class pages, and the shape a new one takes.
enum ClassPages {

    // MARK: - Functions

    /// Where a section's class pages live.
    ///
    /// Read from the course's own settings rather than guessed: it is the
    /// per-section folder whose name mentions classes ("All Classes" by
    /// convention), and failing that the first per-section folder the course
    /// has. The rule itself lives in `ClassFolder`, which is the ONE home for
    /// it — this used to be one of four implementations that disagreed. See
    /// `contracts/class-planning.json` → `classFolder`.
    static func folderURL(forSection sectionNumber: Int, in course: Course) -> URL {
        return course.sectionDirectoryURL(forSection: sectionNumber)
            .appendingPathComponent(ClassFolder.name(for: course))
    }

    /// The section's class pages, in date order, undated ones last.
    ///
    /// An `index.md` is never a class page. That exclusion matters: a folder
    /// index carries the same date as the first class, and treating it as a
    /// lesson would let a reshuffle move the way in to the folder.
    static func list(forSection sectionNumber: Int, in course: Course) -> [ClassPageSummary] {
        var summaries: [ClassPageSummary] = []
        // The MEMBERSHIP rule, not every per-section folder the course has.
        // This iterated the raw list, so "Handouts" and "Media" counted as
        // holding class pages — and this feeds class numbering, re-dating,
        // insertion and the section index pointer, which makes it the biggest
        // consumer of the question `ClassFolder` exists to answer.
        for folderName in ClassFolder.names(for: course) {
            let root: URL = course.sectionDirectoryURL(forSection: sectionNumber)
                .appendingPathComponent(folderName)
            for pageURL in markdownPages(under: root) {
                if pageURL.lastPathComponent.lowercased() == "index.md" {
                    continue
                }
                summaries.append(
                    summary(
                        ofPageAt: pageURL, forSection: sectionNumber,
                        naming: course.configuration.classPageNaming
                    )
                )
            }
        }

        // Dated pages first in date order; undated ones keep name order after.
        summaries.sort { first, second in
            switch (first.date, second.date) {
            case (let left?, let right?):
                if left != right {
                    return left < right
                }
                return first.title.lowercased() < second.title.lowercased()
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return first.title.lowercased() < second.title.lowercased()
            }
        }
        return summaries
    }

    /// One page, read.
    static func summary(
        ofPageAt url: URL, forSection sectionNumber: Int,
        naming: ClassPageNaming
    ) -> ClassPageSummary {
        let title: String = url.deletingPathExtension().lastPathComponent
        var date: CalendarDay? = nil
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            // Class pages live inside `section<N>/`, so they carry a plain
            // `created:` — the section-local key.
            date = PageFrontmatter.createdDay(
                in: text, key: PageFrontmatter.createdKey(forSection: sectionNumber, isSectionLocal: true)
            )
        }
        return ClassPageSummary(title: title, fileURL: url, date: date, naming: naming)
    }

    /// Every markdown page belonging to one section: the section's own folder,
    /// plus the course-level pages every section shares. Other sections'
    /// folders, built output and hidden folders are all skipped — a link in
    /// section 2 has nothing to do with a rename in section 1.
    static func pagesOfSection(_ sectionNumber: Int, in course: Course) -> [URL] {
        var pages: [URL] = []
        let fileManager: FileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: course.directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return pages
        }
        let ownFolderName: String = "section\(sectionNumber)"
        while let entry = enumerator.nextObject() as? URL {
            let name: String = entry.lastPathComponent
            if name == ".merged_output" || name == "node_modules" || name == ".internal" {
                enumerator.skipDescendants()
                continue
            }
            if name.hasPrefix("section"), name != ownFolderName, Int(name.dropFirst("section".count)) != nil {
                enumerator.skipDescendants()
                continue
            }
            if entry.pathExtension.lowercased() == "md" {
                pages.append(entry)
            }
        }
        pages.sort { first, second in
            return first.path.lowercased() < second.path.lowercased()
        }
        return pages
    }

    /// The pages the assistant LISTS for one section — `pagesOfSection`
    /// without the teacher's How I Teach page (#209), which is never on the
    /// website and so is never offered to publish, hide or list.
    ///
    /// A separate function rather than a skip inside `pagesOfSection`, on
    /// purpose (#209 plan review): that walk is also what renaming classes
    /// rewrites links through, and a How I Teach page that links to
    /// [[Unit 2, Day 3]] must follow that class when it is renamed. See
    /// `contracts/shared-rules.json` → `howITeachPage.notListedAsAPage`.
    static func pagesTheAssistantLists(forSection sectionNumber: Int, in course: Course) -> [URL] {
        var listed: [URL] = []
        for page in pagesOfSection(sectionNumber, in: course) {
            if HowITeachPage.isTheHowITeachPage(page, in: course) {
                continue
            }
            listed.append(page)
        }
        return listed
    }

    /// Every markdown page under a folder, recursively. `nonisolated` because
    /// the unit-word rename walks class folders off the main actor.
    nonisolated static func markdownPages(under root: URL) -> [URL] {
        var pages: [URL] = []
        let fileManager: FileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return pages
        }
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return pages
        }
        while let entry = enumerator.nextObject() as? URL {
            if entry.pathExtension.lowercased() == "md" {
                pages.append(entry)
            }
        }
        pages.sort { first, second in
            return first.path.lowercased() < second.path.lowercased()
        }
        return pages
    }

    /// The time of day and UTC offset the section's classes already use, so a
    /// page that never had a date joins the convention its siblings follow
    /// rather than inventing one and sorting itself to midnight.
    static func siblingTimeAndOffset(from pages: [ClassPageSummary], forSection sectionNumber: Int) -> String {
        let key: String = PageFrontmatter.createdKey(forSection: sectionNumber, isSectionLocal: true)
        for page in pages {
            guard let text = try? String(contentsOf: page.fileURL, encoding: .utf8),
                  let raw = PageFrontmatter.rawValue(forKey: key, in: text),
                  let tail = PageFrontmatter.timeAndOffset(inRawValue: raw), !tail.isEmpty else {
                continue
            }
            return tail
        }
        return "T07:00:00.000-0400"
    }

    /// An empty class page in the shape every other class page takes.
    ///
    /// The teacher's own template, down to the frontmatter keys — with one
    /// deliberate difference. It starts `publish: false`: a page nobody has
    /// written yet has no business appearing on the site.
    static func skeleton(
        title: String, unit: Int, naming: ClassPageNaming, folderName: String,
        date: CalendarDay, howMany: Int, tail: String
    ) -> String {
        let plural: String = howMany == 1 ? "This page was" : "\(howMany) of these were"
        if naming.isNumbered {
            return numberedSkeleton(
                title: title, folderName: folderName, date: date, plural: plural, tail: tail
            )
        }
        return """
        ---
        title: \(title)
        publish: false
        created: \(date.text)\(tail)
        transcludeTitleSize: h2
        enableToc: false
        excludeBacklinks: true
        tags:
          - unit-\(unit)
        ---

        %%
        This is the shape every class page takes: a numbered agenda of what
        happened, with links to the pages it used, then a short list of things
        to do before next time. Nothing is explained here — the links do that.

        \(plural) created for you, dated to the days this class actually meets.
        Rename them, add more, delete the ones you do not need. The `created:`
        date is what puts them in order under All Classes, so a new page needs
        one of its own.

        This page is unpublished. Write it, then publish it when it is ready.
        Delete this comment when you do — comments never reach the site either.
        %%

        ## Agenda

        1.

        ## Things to do before our next class

        - [ ]

        """
    }

    /// A new page in a numbered course (#267) — a club's "Week 4".
    ///
    /// No `unit-N` tag: a numbered course is held as unit 1 inside this app,
    /// so every page would carry `unit-1` and Quartz would make a tag page
    /// listing every meeting there has ever been. The comment names the
    /// course's OWN class folder rather than "All Classes", and says
    /// "the group" rather than "this class". Same shape otherwise, so the
    /// assistant's other planners read it exactly as they read a Unit page.
    private static func numberedSkeleton(
        title: String, folderName: String, date: CalendarDay, plural: String, tail: String
    ) -> String {
        return """
        ---
        title: \(title)
        publish: false
        created: \(date.text)\(tail)
        transcludeTitleSize: h2
        enableToc: false
        excludeBacklinks: true
        ---

        %%
        \(plural) created for you, dated to the days the group actually meets.
        The `created:` date is what puts them in order under \(folderName), so a
        new page needs one of its own.

        This page is unpublished. Write it, then publish it when it is ready.
        Delete this comment when you do — comments never reach the site either.
        %%

        ## Agenda

        1.

        ## Things to do before we next meet

        - [ ]

        """
    }
}
