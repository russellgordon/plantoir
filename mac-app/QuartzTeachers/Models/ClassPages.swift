import Foundation

/// A page named as a numbered day of a numbered unit — "Unit 2, Day 3".
///
/// Anything not named that way has no unit and no day, and is deliberately
/// left out of the operations that shuffle classes around: a teacher's "Field
/// Trip" or "Exam Review" cannot be renumbered without inventing a number for
/// it, and inventing one would be worse than not touching it.
struct UnitDay: Equatable, Hashable {

    // MARK: - Stored properties

    let unit: Int
    let day: Int

    // MARK: - Computed properties

    /// The page name these numbers make: "Unit 2, Day 3".
    var title: String {
        return "Unit \(unit), Day \(day)"
    }

    // MARK: - Initializer

    init(unit: Int, day: Int) {
        self.unit = unit
        self.day = day
    }

    /// The numbers inside a page name, or nil when it is named some other way.
    init?(pageTitle: String) {
        let pattern: String = #"^Unit\s+(\d+),\s*Day\s+(\d+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let trimmed: String = pageTitle.trimmingCharacters(in: .whitespaces)
        let whole: NSRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = expression.firstMatch(in: trimmed, range: whole),
              let unitRange = Range(match.range(at: 1), in: trimmed),
              let dayRange = Range(match.range(at: 2), in: trimmed),
              let unit = Int(trimmed[unitRange]),
              let day = Int(trimmed[dayRange]) else {
            return nil
        }
        self.unit = unit
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

    // MARK: - Computed properties

    /// The unit and day in the page's name, when it is named that way.
    var unitAndDay: UnitDay? {
        return UnitDay(pageTitle: title)
    }

    // MARK: - Initializer

    init(title: String, fileURL: URL, date: CalendarDay?) {
        self.title = title
        self.fileURL = fileURL
        self.date = date
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
                summaries.append(summary(ofPageAt: pageURL, forSection: sectionNumber))
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
    static func summary(ofPageAt url: URL, forSection sectionNumber: Int) -> ClassPageSummary {
        let title: String = url.deletingPathExtension().lastPathComponent
        var date: CalendarDay? = nil
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            // Class pages live inside `section<N>/`, so they carry a plain
            // `created:` — the section-local key.
            date = PageFrontmatter.createdDay(
                in: text, key: PageFrontmatter.createdKey(forSection: sectionNumber, isSectionLocal: true)
            )
        }
        return ClassPageSummary(title: title, fileURL: url, date: date)
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

    /// Every markdown page under a folder, recursively.
    static func markdownPages(under root: URL) -> [URL] {
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
    static func skeleton(title: String, unit: Int, date: CalendarDay, howMany: Int, tail: String) -> String {
        let plural: String = howMany == 1 ? "This page was" : "\(howMany) of these were"
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
}
