import Foundation

/// The tree of checkboxes in Section ▸ Publish Pages… and Hide Pages… (#900):
/// the pages a sheet offers, grouped under their unit or their folder, so
/// one box ticks a whole unit.
///
/// Pure over its arguments (pages, the course's naming, the search and the
/// ticked set in; groups, states and the names the call carries out), so
/// both apps run the same cases: `contracts/class-planning.json` →
/// `pagesToTick`. The drawing is `SectionVerbSheet.pickerTable`.
///
/// What a group's box changes is decided HERE and nowhere else (the plan
/// review's amendment 24): a box that is off or mixed ticks every shown page
/// under it, one that is on unticks them, and a page the search hides is
/// never changed by a group's box. A unit's box covers its CLASS pages only
/// (Russell's ruling on #900): the pages those classes link to are handled
/// by the plan and the links checklist, as they are today.
///
/// `nonisolated`: no state, no files, no main actor.
nonisolated enum PageTickTree {

    // MARK: - Types

    /// One page a sheet offers, as the tree needs it.
    struct Page: Equatable, Hashable {

        // MARK: - Stored properties

        /// The name the call carries: folder, then file name
        /// (`SectionVerbs.name(ofPageAt:in:)`). Also the page's id.
        let name: String

        /// What the teacher sees the page called (the search reads it).
        let title: String

        /// Where it is, as the Folder column writes it.
        let folder: String

        let isClass: Bool
        let date: CalendarDay?

        // MARK: - Computed properties

        /// The file name without `.md`: what a class page's unit and day are
        /// read from (`UnitDay`), never the title shown, which a page's
        /// frontmatter can change.
        var fileTitle: String {
            guard let slash = name.range(of: "/", options: .backwards) else {
                return name
            }
            return String(name[slash.upperBound...])
        }
    }

    /// A row's id in the table. An enum rather than a prefixed string, so a
    /// folder group "section1/Notes" and a page named "section1/Notes" can
    /// never be the same row (the plan review's amendment 25).
    enum RowID: Hashable {
        case group(String)
        case page(String)
    }

    /// A group's box.
    enum State: String, Equatable {
        case on
        case off
        case mixed
    }

    /// The sentences the two class groups are named with: the caller's
    /// wording (`AssistWording.menuPageGroupOtherClasses` and
    /// `menuPageGroupAllClasses`), so the tree itself holds no words.
    struct GroupNames: Equatable {

        // MARK: - Stored properties

        let otherClasses: String
        let allClasses: String
    }

    /// A group: a unit, the classes outside any unit, every class of a
    /// numbered course, or a folder. Built once per sheet (`groups(of:…)`).
    struct Group: Equatable {

        // MARK: - Stored properties

        /// Stable for the sheet's life: "unit 4", "other classes",
        /// "all classes" or "folder Concepts/Loops".
        let key: String

        /// What the teacher sees the group called.
        let name: String

        /// Folder groups inside this one, before its pages.
        let groups: [Group]

        /// The pages directly in this group, in the tree's order.
        let pages: [Page]
    }

    /// A row as the table draws it, for the search as it stands: a group
    /// with the rows under it, or a page.
    struct Row: Identifiable, Equatable {

        // MARK: - Stored properties

        let id: RowID

        /// The group's name, or the page's title.
        let title: String

        /// The page, for a page row; nil for a group.
        let page: Page?

        /// The rows under a group, groups first; nil for a page.
        let children: [Row]?

        /// Every SHOWN page under a group, at every depth, in the tree's
        /// order: what its box reads and what a click on it changes. Empty
        /// for a page.
        let shownPageNames: [String]

        // MARK: - Computed properties

        var isGroup: Bool {
            return children != nil
        }
    }

    // MARK: - Stored properties

    /// Whether a group starts folded when the sheet opens (#900, the plan's
    /// rule 9). A question for Russell: folded, so a 300-page sheet opens as
    /// a short list of units and folders (recommended), or open, so every
    /// page is in view as it was before the tree. One rule, so it is cheap
    /// to turn.
    static let groupsStartFolded: Bool = true

    // MARK: - Functions

    /// The groups, built once from every page offered: units by number, then
    /// the classes outside any unit, then folders by name. A numbered course
    /// (a club's "Week 3") has no units, so its classes are one group.
    static func groups(of pages: [Page], naming: ClassPageNaming, courseCode: String, names: GroupNames) -> [Group] {
        var unitPages: [Int: [Page]] = [:]
        var otherClassPages: [Page] = []
        var everyClassPage: [Page] = []
        var folderPages: [Page] = []
        for page in pages {
            if !page.isClass {
                folderPages.append(page)
                continue
            }
            if naming.isNumbered {
                everyClassPage.append(page)
                continue
            }
            if let numbers = UnitDay(pageTitle: page.fileTitle, naming: naming) {
                var inThisUnit: [Page] = unitPages[numbers.unit] ?? []
                inThisUnit.append(page)
                unitPages[numbers.unit] = inThisUnit
            } else {
                otherClassPages.append(page)
            }
        }

        var made: [Group] = []
        var unitNumbers: [Int] = []
        for unit in unitPages.keys {
            unitNumbers.append(unit)
        }
        unitNumbers.sort()
        for unit in unitNumbers {
            let name: String = naming.unitName(unit) ?? names.otherClasses
            made.append(Group(
                key: "unit \(unit)", name: name, groups: [], pages: inClassOrder(unitPages[unit] ?? [])
            ))
        }
        if !otherClassPages.isEmpty {
            made.append(Group(
                key: "other classes", name: names.otherClasses, groups: [], pages: inClassOrder(otherClassPages)
            ))
        }
        if !everyClassPage.isEmpty {
            made.append(Group(
                key: "all classes", name: names.allClasses, groups: [], pages: inClassOrder(everyClassPage)
            ))
        }
        for group in folderGroups(of: folderPages, under: [], courseCode: courseCode) {
            made.append(group)
        }
        return made
    }

    /// The rows the table draws for `search`: every group with at least one
    /// shown page under it, and those pages. A group's name never matches by
    /// itself; an empty group is never drawn.
    static func rows(of groups: [Group], search: String) -> [Row] {
        let wanted: String = search.trimmingCharacters(in: .whitespaces).lowercased()
        var drawn: [Row] = []
        for group in groups {
            if let row = row(of: group, wanted: wanted) {
                drawn.append(row)
            }
        }
        return drawn
    }

    /// Whether the search leaves `page` showing: its title or its folder
    /// holds the search, ignoring case (today's rule, unchanged).
    static func isShown(_ page: Page, search: String) -> Bool {
        let wanted: String = search.trimmingCharacters(in: .whitespaces).lowercased()
        return isShown(page, wanted: wanted)
    }

    /// A group's box, over the shown pages under it.
    static func state(of shownPageNames: [String], ticked: Set<String>) -> State {
        var tickedCount: Int = 0
        for name in shownPageNames where ticked.contains(name) {
            tickedCount += 1
        }
        if tickedCount == 0 {
            return .off
        }
        if tickedCount == shownPageNames.count {
            return .on
        }
        return .mixed
    }

    /// The ticks after a click on a group's box: off or mixed ticks every
    /// shown page under it, on unticks every one. Nothing else changes.
    static func clicking(_ shownPageNames: [String], ticked: Set<String>) -> Set<String> {
        var after: Set<String> = ticked
        if state(of: shownPageNames, ticked: ticked) == .on {
            for name in shownPageNames {
                after.remove(name)
            }
        } else {
            for name in shownPageNames {
                after.insert(name)
            }
        }
        return after
    }

    /// How many ticked pages the search leaves out of view: they stay ticked
    /// and go into the plan (`menuTickedButNotShown` says so under the table).
    static func tickedButNotShown(_ pages: [Page], ticked: Set<String>, search: String) -> Int {
        let wanted: String = search.trimmingCharacters(in: .whitespaces).lowercased()
        var count: Int = 0
        for page in pages where ticked.contains(page.name) && !isShown(page, wanted: wanted) {
            count += 1
        }
        return count
    }

    /// The names the call carries: every ticked page, in the order the sheet
    /// OFFERS them (`pages`), shown or not — today's `tickedRows`, unchanged,
    /// which is why ticking a unit writes exactly what ticking its pages one
    /// by one writes.
    static func namesToSend(_ pages: [Page], ticked: Set<String>) -> [String] {
        var names: [String] = []
        for page in pages where ticked.contains(page.name) {
            names.append(page.name)
        }
        return names
    }

    /// The group whose path of names is `path` ("Concepts", "Loops"), or nil.
    static func group(at path: [String], in groups: [Group]) -> Group? {
        guard let first = path.first else {
            return nil
        }
        for group in groups where group.name == first {
            if path.count == 1 {
                return group
            }
            var rest: [String] = []
            var index: Int = 1
            while index < path.count {
                rest.append(path[index])
                index += 1
            }
            return self.group(at: rest, in: group.groups)
        }
        return nil
    }

    /// Every group's row id, at every depth: what the search opens.
    static func groupIDs(in rows: [Row]) -> [RowID] {
        var ids: [RowID] = []
        for row in rows {
            guard let children = row.children else {
                continue
            }
            ids.append(row.id)
            for id in groupIDs(in: children) {
                ids.append(id)
            }
        }
        return ids
    }

    /// The row with `id`, at any depth.
    static func row(withID id: RowID, in rows: [Row]) -> Row? {
        for row in rows {
            if row.id == id {
                return row
            }
            if let children = row.children, let found = self.row(withID: id, in: children) {
                return found
            }
        }
        return nil
    }

    /// How many rows the table draws with `open` groups opened: a group's
    /// row, and its rows only while it is open.
    static func drawnRowCount(_ rows: [Row], open: Set<RowID>) -> Int {
        var count: Int = 0
        for row in rows {
            count += 1
            if let children = row.children, open.contains(row.id) {
                count += drawnRowCount(children, open: open)
            }
        }
        return count
    }

    // MARK: - Building

    /// Classes by date, undated last, then title, ignoring case (the order
    /// the sheet listed classes in before the tree).
    static func inClassOrder(_ pages: [Page]) -> [Page] {
        var sorted: [Page] = pages
        sorted.sort { (first: Page, second: Page) -> Bool in
            switch (first.date, second.date) {
            case (let left?, let right?):
                if left != right {
                    return left < right
                }
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                break
            }
            return inTitleOrder(first, second)
        }
        return sorted
    }

    /// By title ignoring case, then by name, so two pages with one title keep
    /// one order.
    static func inTitleOrder(_ first: Page, _ second: Page) -> Bool {
        let left: String = first.title.lowercased()
        let right: String = second.title.lowercased()
        if left != right {
            return left < right
        }
        return first.name < second.name
    }

    /// The folder groups for `pages` below the folder path `parent`: one per
    /// next folder name, by name ignoring case, each holding its own
    /// subfolders and then its pages.
    static func folderGroups(of pages: [Page], under parent: [String], courseCode: String) -> [Group] {
        var byNext: [String: [Page]] = [:]
        for page in pages {
            let parts: [String] = folderParts(of: page, courseCode: courseCode)
            if parts.count <= parent.count {
                continue
            }
            let next: String = parts[parent.count]
            var inIt: [Page] = byNext[next] ?? []
            inIt.append(page)
            byNext[next] = inIt
        }
        var names: [String] = []
        for name in byNext.keys {
            names.append(name)
        }
        names.sort { (first: String, second: String) -> Bool in
            if first.lowercased() != second.lowercased() {
                return first.lowercased() < second.lowercased()
            }
            return first < second
        }
        var made: [Group] = []
        for name in names {
            var path: [String] = parent
            path.append(name)
            var here: [Page] = []
            var deeper: [Page] = []
            for page in byNext[name] ?? [] {
                if folderParts(of: page, courseCode: courseCode).count == path.count {
                    here.append(page)
                } else {
                    deeper.append(page)
                }
            }
            here.sort { (first: Page, second: Page) -> Bool in
                return inTitleOrder(first, second)
            }
            made.append(Group(
                key: "folder " + path.joined(separator: "/"),
                name: name,
                groups: folderGroups(of: deeper, under: path, courseCode: courseCode),
                pages: here
            ))
        }
        return made
    }

    /// A page's folder as its parts: the Folder column split on "/", empty
    /// parts dropped; a page with no folder sits under the course code (what
    /// the Folder column shows for a page at the course's root).
    static func folderParts(of page: Page, courseCode: String) -> [String] {
        var parts: [String] = []
        for part in page.folder.components(separatedBy: "/") where !part.isEmpty {
            parts.append(part)
        }
        if parts.isEmpty {
            parts.append(courseCode)
        }
        return parts
    }

    // MARK: - Drawing

    static func isShown(_ page: Page, wanted: String) -> Bool {
        if wanted.isEmpty {
            return true
        }
        return page.title.lowercased().contains(wanted) || page.folder.lowercased().contains(wanted)
    }

    static func row(of group: Group, wanted: String) -> Row? {
        var children: [Row] = []
        var shownNames: [String] = []
        for inner in group.groups {
            if let innerRow = row(of: inner, wanted: wanted) {
                children.append(innerRow)
                for name in innerRow.shownPageNames {
                    shownNames.append(name)
                }
            }
        }
        for page in group.pages where isShown(page, wanted: wanted) {
            children.append(Row(id: .page(page.name), title: page.title, page: page, children: nil, shownPageNames: []))
            shownNames.append(page.name)
        }
        if shownNames.isEmpty {
            return nil
        }
        return Row(id: .group(group.key), title: group.name, page: nil, children: children, shownPageNames: shownNames)
    }
}
