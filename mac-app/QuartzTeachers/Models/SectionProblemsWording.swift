import Foundation

/// Every sentence the Problems tab, its marker and its alert say (#717).
///
/// Retyped from `contracts/shared-rules.json` → `sectionProblems.words` and
/// `sectionProblems.kinds` (each kind's label) and pinned against them key
/// by key (`SectionProblemsTests`), the arrangement `LinksChecklistWording`
/// uses. The ROWS' own words are not here: the shared Python writes them into
/// the record, worded by the folder problem's own makers.
///
/// **The parameters are Strings** so the pin can call each one with its
/// `{placeholder}` and get the contract's template back.
nonisolated enum SectionProblemsWording {

    // MARK: - The tabs

    static let tabWebsite: String = "Website"

    static let tabProblems: String = "Problems"

    // MARK: - The table

    static let columnIncluded: String = "Include"

    static let columnKind: String = "Kind"

    static let columnPage: String = "Page"

    static let columnProblem: String = "Problem"

    static let columnFirstFound: String = "First found"

    static let columnLastFound: String = "Last found"

    static let wholeSection: String = "Whole section"

    static let wholeCourse: String = "Whole course"

    static func intro(course: String, section: String) -> String {
        return "What the last preview or deploy of \(course) Section \(section) found. "
            + "A problem leaves this list when a build no longer finds it."
    }

    static let fixedInTheSource: String = "Fixed in the source — preview or deploy this section to update it."

    // MARK: - The alert

    static func alertTitleOne(course: String, section: String) -> String {
        return "A new problem in \(course) Section \(section)"
    }

    static func alertTitleSeveral(count: String, course: String, section: String) -> String {
        return "\(count) new problems in \(course) Section \(section)"
    }

    static let alertMessage: String =
        "Show opens this section’s Problems tab, which names the page of each problem and what to change."

    static let alertAlsoGoneOne: String = "One problem found before is gone."

    static func alertAlsoGoneSeveral(count: String) -> String {
        return "\(count) problems found before are gone."
    }

    static let show: String = "Show"

    // MARK: - The marker

    static let markerHelp: String =
        "The last preview or deploy of this section found problems. Open its Problems tab to see them."

    // MARK: - Kinds

    /// `sectionProblems.kinds` → each kind's `label`.
    static let kindLabels: [String: String] = [
        "curriculumCoverageFoundNothing": "Curriculum map",
        "courseTeachesNothing": "Curriculum map",
        "mediaFolderMissing": "Media folder",
        "sectionIndexMissing": "Front page",
        "handWrittenCoveragePage": "Curriculum map",
        "noGradedFolders": "Curriculum map",
        "pageSettingsUnreadable": "Page settings",
        "linksIntoHiddenPages": "Link to a hidden page",
        "printPdfNotFound": "Handout",
        "figuresCouldNotBeDrawn": "Diagram or graph",
        "swiftCouldNotBePrepared": "Swift program",
        "quizzesNotReady": "Self-check question",
        "runnableCodeShownAsPlainCode": "Runnable code",
        "quizzesReadDifferently": "Self-check question",
        "geogebraSketchesNotReady": "GeoGebra sketch",
        "filesTooLargeForCloudflare": "File too large",
    ]

    /// `sectionProblems.kinds` → each kind's `scope`.
    static let kindScopes: [String: String] = [
        "curriculumCoverageFoundNothing": "section",
        "courseTeachesNothing": "section",
        "mediaFolderMissing": "course",
        "sectionIndexMissing": "section",
        "handWrittenCoveragePage": "section",
        "noGradedFolders": "section",
        "pageSettingsUnreadable": "page",
        "linksIntoHiddenPages": "page",
        "printPdfNotFound": "page",
        "figuresCouldNotBeDrawn": "page",
        "swiftCouldNotBePrepared": "page",
        "quizzesNotReady": "page",
        "runnableCodeShownAsPlainCode": "page",
        "quizzesReadDifferently": "page",
        "geogebraSketchesNotReady": "page",
        "filesTooLargeForCloudflare": "section",
    ]

    // MARK: - Functions

    /// A kind's label; a kind this app does not know yet reads as its name
    /// rather than as nothing.
    static func label(ofKind kind: String) -> String {
        return kindLabels[kind] ?? kind
    }

    /// What the Page column shows for a row.
    static func pageColumn(for row: SectionProblemRow) -> String {
        if !row.page.isEmpty {
            return row.page
        }
        if kindScopes[row.kind] == "course" {
            return wholeCourse
        }
        return wholeSection
    }

    /// The alert's title for a record's new problems.
    static func alertTitle(newCount: Int, course: String, section: Int) -> String {
        if newCount == 1 {
            return alertTitleOne(course: course, section: String(section))
        }
        return alertTitleSeveral(count: String(newCount), course: course, section: String(section))
    }

    /// The alert's message: the new problem's own sentence when there is one,
    /// where to find them, and how many went.
    static func alertMessage(newRows: [SectionProblemRow], goneCount: Int) -> String {
        var paragraphs: [String] = []
        if newRows.count == 1 && !newRows[0].sentence.isEmpty {
            paragraphs.append(newRows[0].sentence)
        }
        paragraphs.append(alertMessage)
        if goneCount == 1 {
            paragraphs.append(alertAlsoGoneOne)
        } else if goneCount > 1 {
            paragraphs.append(alertAlsoGoneSeveral(count: String(goneCount)))
        }
        return paragraphs.joined(separator: "\n\n")
    }
}
