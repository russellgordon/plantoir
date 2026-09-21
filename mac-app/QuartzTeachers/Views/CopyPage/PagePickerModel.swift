import Foundation
import Observation

/// The state behind the page field: what has been typed, what matches it, and
/// which row the arrow keys are on.
///
/// All the thinking lives here rather than in the view, so it can be tested
/// without a window — which is the arrangement the control's two Canopy uses
/// already follow.
///
/// **No debouncing, no generation counter, no result limit**, and that is
/// measured rather than lazy: the list is in memory, the biggest real course
/// offers 156 rows, and the wizard's own popup already runs uncapped over
/// about 1,900 Ontario course codes through the same `LazyVStack`.
@Observable @MainActor
class PagePickerModel {

    // MARK: - Stored properties

    /// Every page of the source course that may be copied.
    private(set) var pages: [CopyablePage] = []

    /// What is in the field. Also the search text — a combo box has one, not
    /// two, which is why taking a row writes the page's name here.
    var searchText: String = ""

    var isFieldFocused: Bool = false

    var highlightedRowId: String?

    /// Whether the list is closed although the field has focus.
    ///
    /// **It starts TRUE, and that is a deliberate departure from the control
    /// this was ported from.** A sheet gives its first text field focus as it
    /// opens, so a list that opens on focus alone opened over the two
    /// questions underneath it the instant the teacher chose the menu item —
    /// seen on a real course, where it covered "Copy into" and "Folder"
    /// completely. Where the picker is the only control on its row, opening
    /// on focus is right; here it is the first of three questions, so the
    /// list opens when the teacher TYPES or presses the chevron, and not
    /// merely because the sheet put the caret somewhere.
    var wasDismissed: Bool = true

    /// What has actually been CHOSEN, which is not the same as what has been
    /// typed. Half a name in the field is not a selection.
    private(set) var chosenPage: CopyablePage?

    /// True while the next change to `searchText` is one this model made
    /// rather than one the teacher typed.
    ///
    /// The field's text is a binding, so a change made HERE comes back as
    /// though somebody had typed it — and "somebody typed" means "open the
    /// list". Measured by driving the real app: after "Copy another" cleared
    /// the field, the list opened over the two questions underneath it,
    /// exactly the fault `wasDismissed` starting true was meant to close.
    private var theNextTextChangeIsMine: Bool = false

    // MARK: - Computed properties

    var isShowingSuggestions: Bool {
        return isFieldFocused && !wasDismissed
    }

    private var searchTerm: String {
        return searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The rows, grouped by the folder they sit in while nothing is typed,
    /// and as one ranked run once something is.
    ///
    /// Grouped, because Russell asked for the folder to be visible and
    /// because it turns ICS4U's 85 curriculum-expectation pages into two
    /// headings to scroll past rather than eighty-five rows to read.
    /// Un-grouped while searching, for Canopy's measured reason: a heading
    /// above the best match says the same thing the row's second line already
    /// says, and costs a row of height to say it.
    var sections: [PickerSection<CopyablePage>] {
        let term: String = searchTerm
        if term.isEmpty {
            var grouped: [PickerSection<CopyablePage>] = []
            var folderOrder: [String] = []
            var rowsByFolder: [String: [CopyablePage]] = [:]
            for page in pages {
                if rowsByFolder[page.folderName] == nil {
                    rowsByFolder[page.folderName] = []
                    folderOrder.append(page.folderName)
                }
                rowsByFolder[page.folderName]?.append(page)
            }
            for folderName in folderOrder {
                grouped.append(PickerSection(
                    title: folderName, rows: rowsByFolder[folderName] ?? []
                ))
            }
            return grouped
        }
        return [PickerSection(title: "", rows: matchingPages)]
    }

    /// Ranked rather than merely filtered, because the top row is the one
    /// Return takes: typing "rec" should offer "Recursion" before a page in a
    /// folder that happens to contain those letters.
    var matchingPages: [CopyablePage] {
        let term: String = searchTerm
        if term.isEmpty {
            return pages
        }
        var startsWithTheTerm: [CopyablePage] = []
        var containsTheTerm: [CopyablePage] = []
        var theFolderMatches: [CopyablePage] = []
        for page in pages {
            let name: String = page.pageName.lowercased()
            if name.hasPrefix(term) {
                startsWithTheTerm.append(page)
            } else if name.contains(term) {
                containsTheTerm.append(page)
            } else if page.folderName.lowercased().contains(term) {
                theFolderMatches.append(page)
            }
        }
        var result: [CopyablePage] = []
        for page in startsWithTheTerm {
            result.append(page)
        }
        for page in containsTheTerm {
            result.append(page)
        }
        for page in theFolderMatches {
            result.append(page)
        }
        return result
    }

    /// Every row on screen, top to bottom, which is what the arrow keys walk.
    var visibleRows: [CopyablePage] {
        var result: [CopyablePage] = []
        for section in sections {
            for page in section.rows {
                result.append(page)
            }
        }
        return result
    }

    var visibleRowIds: [String] {
        var result: [String] = []
        for page in visibleRows {
            result.append(page.id)
        }
        return result
    }

    var highlightedRow: CopyablePage? {
        guard let highlightedRowId else {
            return nil
        }
        for page in visibleRows where page.id == highlightedRowId {
            return page
        }
        // The list re-filtered under the highlight and the row it named is
        // gone.
        return nil
    }

    // MARK: - Functions

    /// The pages this course offers. Kept separate from the initialiser so a
    /// different source can be shown without rebuilding the field's state
    /// underneath somebody.
    func show(_ newPages: [CopyablePage]) {
        pages = newPages
        if let chosenPage {
            var stillThere: Bool = false
            for page in newPages where page.id == chosenPage.id {
                stillThere = true
            }
            if !stillThere {
                clearSelection()
                searchText = ""
            }
        }
    }

    /// Back to an empty field with the list closed — what "Copy another"
    /// leaves behind, and the same state the sheet opens in.
    func startOver() {
        theNextTextChangeIsMine = true
        searchText = ""
        chosenPage = nil
        highlightedRowId = nil
        wasDismissed = true
    }

    /// Taking a row: the one way a page becomes chosen.
    func choose(_ page: CopyablePage) {
        chosenPage = page
        theNextTextChangeIsMine = true
        searchText = page.pageName
        highlightedRowId = nil
        wasDismissed = true
        isFieldFocused = false
    }

    func clearSelection() {
        chosenPage = nil
    }

    /// Typing. Anything typed invalidates both the selection and the
    /// highlight — the field shows one string, so a chosen page whose name is
    /// being edited is no longer what the field says.
    func noteTyping() {
        if theNextTextChangeIsMine {
            theNextTextChangeIsMine = false
            return
        }
        wasDismissed = false
        highlightedRowId = nil
        if let chosenPage, chosenPage.pageName != searchText {
            clearSelection()
        }
    }

    /// The chevron: the deliberate "show me everything" gesture.
    ///
    /// Focus does NOT do this — see `wasDismissed`.
    func reveal() {
        wasDismissed = false
    }

    func dismissSuggestions() {
        wasDismissed = true
        highlightedRowId = nil
    }

    /// Arrow keys. Returns whether the list took the key.
    func moveHighlight(by delta: Int) -> Bool {
        guard isShowingSuggestions else {
            return false
        }
        let rows: [CopyablePage] = visibleRows
        if rows.isEmpty {
            return false
        }
        guard let highlightedRowId else {
            // The first press starts at the top going down, and at the bottom
            // going up, the way a native popup does.
            self.highlightedRowId = delta > 0 ? rows[0].id : rows[rows.count - 1].id
            return true
        }
        var currentIndex: Int?
        for index in rows.indices where rows[index].id == highlightedRowId {
            currentIndex = index
        }
        guard let currentIndex else {
            self.highlightedRowId = rows[0].id
            return true
        }
        var nextIndex: Int = currentIndex + delta
        if nextIndex < 0 {
            nextIndex = rows.count - 1
        }
        if nextIndex >= rows.count {
            nextIndex = 0
        }
        self.highlightedRowId = rows[nextIndex].id
        return true
    }

    /// Return. Takes the highlighted row if there is one; otherwise reports
    /// false so the key falls through to the window's default button.
    func commitHighlight() -> Bool {
        guard isShowingSuggestions, let row = highlightedRow else {
            return false
        }
        choose(row)
        return true
    }
}
