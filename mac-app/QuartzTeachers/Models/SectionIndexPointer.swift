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
        in graph: AssistSectionGraph, term: String = ClassPageTerm.standard
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
            let unitDay: UnitDay? = UnitDay(pageTitle: page.title, term: term)
            if let soFarDay = newestDay {
                if day.text < soFarDay.text {
                    continue
                } else if day.text == soFarDay.text {
                    if let ud = unitDay, let soFarUD = newestUnitDay {
                        if ud <= soFarUD {
                            continue
                        }
                    } else if unitDay == nil && newestUnitDay != nil {
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

    /// The index rewritten to point at `page`, or nil when nothing needs to
    /// change.
    ///
    /// Only the transclusion that names a CLASS page is touched. A section
    /// index also transcludes things like Help Sessions and Key Links, and
    /// repointing one of those at a lesson would be a far worse bug than the
    /// one being fixed — so the replacement is made by matching against the
    /// section's actual class titles rather than by position.
    static func repointing(
        _ text: String,
        at page: AssistSectionPage,
        classTitles: Set<String>,
        createdTail: String
    ) -> Result? {
        var updated: String = text
        var replaced: String?

        for line in text.components(separatedBy: "\n") {
            let trimmed: String = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") else {
                continue
            }
            let inside: String = String(trimmed.dropFirst(3).dropLast(2))
            // A transclusion may carry a display name or a heading; the target
            // is what comes before either.
            let target: String = inside
                .components(separatedBy: "|")[0]
                .components(separatedBy: "#")[0]
                .trimmingCharacters(in: .whitespaces)
            let bare: String = (target.components(separatedBy: "/").last ?? target)
                .trimmingCharacters(in: .whitespaces)

            if !classTitles.contains(bare.lowercased()) {
                continue
            }
            if bare == page.title {
                replaced = nil
            } else {
                updated = updated.replacingOccurrences(of: trimmed, with: "![[\(page.title)]]")
                replaced = bare
            }
            break
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
            in: graph, term: course.configuration.unitWord
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
