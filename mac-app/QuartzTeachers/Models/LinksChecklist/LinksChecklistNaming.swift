import Foundation

/// How the links checklist names a page (#385's page-naming notes): the way
/// #362's start-of-year plan names one, through the same builder
/// (`StartOfYearPageNaming`) rather than a second rule.
///
/// - By its TITLE — front matter title, else the file name, else the folder
///   for a folder's own `index.md` (`AssistSectionGraph.displayName`) — never
///   by the last part of its place, which is the file name.
/// - With its folder when another page IN THE SECTION has the same title,
///   not only another row: a page whose twin students can already see is
///   still told apart from it.
///
/// The build's `title` is kept for a page that has gone since the offer was
/// written: the graph cannot name it, and the build's title is still better
/// than its file name (plan-review note 6).
nonisolated struct LinksChecklistNaming {

    // MARK: - Stored properties

    let pagesByPlace: [String: AssistSectionPage]

    /// The build's title for each row, by place — used only when the page is
    /// no longer in the section.
    let rowTitlesByPlace: [String: String]

    /// Title keys (`StartOfYearPageNaming.titleKey`) more than one page in
    /// the section holds.
    let sharedTitles: Set<String>

    let courseDirectoryURL: URL
    let courseCode: String

    // MARK: - Initializer

    init(graph: AssistSectionGraph,
         pagesByPlace: [String: AssistSectionPage],
         rows: [LinksChecklistOffer.Row],
         courseDirectoryURL: URL,
         courseCode: String) {
        self.pagesByPlace = pagesByPlace
        var titles: [String: String] = [:]
        for row in rows {
            titles[row.place.precomposedStringWithCanonicalMapping] = row.title
        }
        self.rowTitlesByPlace = titles
        var allShownTitles: [String] = []
        for page in graph.pages {
            allShownTitles.append(page.displayTitle)
        }
        self.sharedTitles = StartOfYearPageNaming.titlesHeldByMoreThanOne(allShownTitles)
        self.courseDirectoryURL = courseDirectoryURL
        self.courseCode = courseCode
    }

    // MARK: - Functions

    /// A page as a sentence names it — `startOfYear.wording.pageName`, or
    /// `pageNameInFolder` when its title is shared — quotes included.
    func name(ofPlace place: String) -> String {
        let key: String = place.precomposedStringWithCanonicalMapping
        if let page = pagesByPlace[key] {
            return StartOfYearPageNaming.name(
                title: page.displayTitle, fileURL: page.fileURL, sharedTitles: sharedTitles,
                courseDirectoryURL: courseDirectoryURL, courseCode: courseCode
            )
        }
        if let title = rowTitlesByPlace[key] {
            return StartOfYearWording.pageName(page: title)
        }
        return StartOfYearWording.pageName(page: LinksChecklistOffer.name(ofPlace: place))
    }

    /// A row's own title, unquoted: the page's title, or
    /// `linksChecklist.wording.rowInFolder` when its title is shared.
    func rowTitle(of row: LinksChecklistOffer.Row) -> String {
        guard let page = pagesByPlace[row.place.precomposedStringWithCanonicalMapping] else {
            return row.title
        }
        if sharedTitles.contains(StartOfYearPageNaming.titleKey(page.displayTitle)) {
            return LinksChecklistWording.rowInFolder(
                page: page.displayTitle,
                folder: StartOfYearPageNaming.folder(
                    of: page.fileURL, courseDirectoryURL: courseDirectoryURL, courseCode: courseCode
                )
            )
        }
        return page.displayTitle
    }
}
