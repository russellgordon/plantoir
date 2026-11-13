import Foundation

/// The groups on the Reference Courses shelf (#572, third piece), as a pure
/// function of the courses and the working folder's arrangement file,
/// `courses/.internal/reference-shelf.json`.
///
/// **Three kinds of group, one list.**
///
/// - A YEAR group is derived from each course's `reference_school_year`, is
///   named by the year ("2025–26"), is never stored, is never renamed, and is
///   not drawn when it holds nothing.
/// - The NO-YEAR group holds a course with no school year. It is derived the
///   same way and not drawn when empty, but its NAME is the teacher's: "Other"
///   until they rename it.
/// - A MADE group is one the teacher made. It is stored, named by them, and
///   drawn even when it is empty, because an empty one is something they just
///   made and may want to fill or remove.
///
/// A course is in a made group only when the arrangement places it there.
/// Otherwise it is where it has always been: its year, or the no-year group.
/// So with no file at all the shelf is exactly the shelf before #572's third
/// piece, and that is the whole of the migration: nothing is converted and
/// nothing is written into a folder that has no groups.
///
/// **Groups are a view.** Nothing here, and nothing that calls it, moves,
/// renames or removes a course folder. The rules are
/// `contracts/shared-rules.json` → `referenceCourses.groups`, and the file is
/// `contracts/file-formats.json` → `referenceShelf`.
nonisolated enum ReferenceShelf {

    // MARK: - Types

    /// Where a course sits on the shelf.
    enum Place: Hashable, Sendable {
        /// A school year, by its starting calendar year.
        case year(Int)

        /// The group for courses with no school year.
        case noYear

        /// A group the teacher made, by its id in the file.
        case made(String)

        // MARK: - Computed properties

        /// The place a course with this school year goes when nothing places
        /// it in a made group.
        static func forYear(_ schoolYear: Int?) -> Place {
            guard let schoolYear else {
                return .noYear
            }
            return .year(schoolYear)
        }
    }

    /// A group the teacher made, as the file names it.
    struct MadeGroup: Equatable, Sendable {

        // MARK: - Stored properties

        /// Opaque and stable: `g-` and eight hex digits. Fold state and every
        /// placement name the group by this, so a rename moves nothing.
        let id: String

        /// What the teacher called it, already through `normalizedName`.
        let name: String
    }

    /// What the file says, as far as this app understands it — and what it
    /// must hand back untouched when it writes the file again.
    struct Arrangement {

        // MARK: - Stored properties

        /// What the no-year group is called, or nil for "Other".
        var noYearGroupName: String?

        /// The teacher's groups, in the order the file keeps them (the
        /// sidebar sorts them; the file does not need to).
        var groups: [MadeGroup] = []

        /// A reference course's FOLDER → the id of the made group it is in.
        var placements: [String: String] = [:]

        /// The file's whole top level as it was read, so a key this app does
        /// not know survives a write. Empty for a new file.
        var keptTopLevel: [String: Any] = [:]

        /// Entries of `groups` this app could not read (no id, no name, a
        /// duplicate id), written back as they were.
        var keptGroupEntries: [Any] = []

        /// Entries of `placements` whose value is not a group id, written
        /// back as they were.
        var keptPlacementEntries: [String: Any] = [:]

        // MARK: - Computed properties

        /// The no-year group's name as the shelf shows it.
        var noYearTitle: String {
            guard let noYearGroupName, !noYearGroupName.isEmpty else {
                return SchoolYear.otherGroupName
            }
            return noYearGroupName
        }

        /// True when there is nothing to keep: no made group, no placement,
        /// no renamed no-year group, nothing kept from another version.
        var isEmpty: Bool {
            return noYearGroupName == nil && groups.isEmpty && placements.isEmpty
                && keptGroupEntries.isEmpty && keptPlacementEntries.isEmpty
        }

        // MARK: - Initializer

        init(
            noYearGroupName: String? = nil,
            groups: [MadeGroup] = [],
            placements: [String: String] = [:]
        ) {
            self.noYearGroupName = noYearGroupName
            self.groups = groups
            self.placements = placements
        }

        // MARK: - Functions

        /// The made group with that id, or nil.
        func group(withID id: String) -> MadeGroup? {
            for group in groups where group.id == id {
                return group
            }
            return nil
        }
    }

    /// What reading the file found.
    enum Reading {
        /// There is no file: the shelf is the year layout, and a change
        /// writes one.
        case absent

        /// A file this app understands.
        case read(Arrangement)

        /// A file that is there and cannot be read: half synced, cut short,
        /// hand edited. The shelf shows the year layout and EVERY change is
        /// refused, so the teacher's groups are never written over by an app
        /// that could not see them.
        case unreadable

        /// A file written by a newer Plantoir (`version` above this one's).
        /// What is understood is shown; nothing is written, for the same
        /// reason.
        case newer(Arrangement)

        // MARK: - Computed properties

        /// The arrangement to draw the shelf from.
        var arrangement: Arrangement {
            switch self {
            case .absent, .unreadable:
                return Arrangement()
            case .read(let arrangement), .newer(let arrangement):
                return arrangement
            }
        }

        /// Why a change cannot be made right now, as a teacher reads it, or
        /// nil when it can.
        var refusal: String? {
            switch self {
            case .absent, .read:
                return nil
            case .unreadable:
                return ReferenceGroupWording.couldNotReadGroups
            case .newer:
                return ReferenceGroupWording.arrangedByANewerPlantoir
            }
        }
    }

    /// One course on the shelf, as this file needs to see it.
    struct Entry: Equatable, Sendable {

        // MARK: - Stored properties

        /// Its folder, which is its identity.
        let folderName: String

        /// The code a teacher reads.
        let displayCode: String

        /// The school year it is filed under, or nil for none.
        let schoolYear: Int?

        // MARK: - Initializer

        init(folderName: String, displayCode: String, schoolYear: Int?) {
            self.folderName = folderName
            self.displayCode = displayCode
            self.schoolYear = schoolYear
        }
    }

    /// One group as the sidebar draws it.
    struct Group: Identifiable, Equatable, Sendable {

        // MARK: - Stored properties

        let place: Place

        /// "2025–26", the no-year group's name, or the made group's.
        let title: String

        /// The folders of the courses in it, in the order they were given.
        let folderNames: [String]

        // MARK: - Computed properties

        /// A stable identity for `ForEach` and for accessibility: `year-2025`,
        /// `other`, or `made-<id>`.
        var id: String {
            return ReferenceShelf.identifier(for: place)
        }

        /// True for a made group, which is the only kind the teacher can
        /// remove.
        var isMade: Bool {
            if case .made = place {
                return true
            }
            return false
        }
    }

    /// Why a group name cannot be used.
    enum NameProblem: Equatable, Sendable {
        case empty
        case tooLong
        case taken(String)

        // MARK: - Computed properties

        var sentence: String {
            switch self {
            case .empty:
                return ReferenceGroupWording.nameIsEmpty
            case .tooLong:
                return ReferenceGroupWording.nameIsTooLong
            case .taken(let name):
                return ReferenceGroupWording.nameIsTaken(name: name)
            }
        }
    }

    // MARK: - Stored properties

    /// The format this app writes, and the newest it will change.
    static let currentVersion: Int = 1

    /// The longest group name, in characters, after normalising.
    static let mostCharacters: Int = 40

    /// Where the file lives, under `courses/`.
    static let relativePath: String = ".internal/reference-shelf.json"

    // MARK: - Functions

    /// The fold-state and accessibility identity of a place.
    static func identifier(for place: Place) -> String {
        switch place {
        case .year(let year):
            return "year-\(year)"
        case .noYear:
            return "other"
        case .made(let id):
            return "made-\(id)"
        }
    }

    /// Where a course is drawn: its made group when the arrangement places it
    /// in one that exists, otherwise its year or the no-year group.
    static func place(
        ofFolder folderName: String,
        schoolYear: Int?,
        in arrangement: Arrangement
    ) -> Place {
        if let id = arrangement.placements[folderName], arrangement.group(withID: id) != nil {
            return .made(id)
        }
        return Place.forYear(schoolYear)
    }

    /// What a place is called on the shelf.
    static func title(of place: Place, in arrangement: Arrangement) -> String {
        switch place {
        case .year(let year):
            return SchoolYear.label(forStartingYear: year)
        case .noYear:
            return arrangement.noYearTitle
        case .made(let id):
            return arrangement.group(withID: id)?.name ?? arrangement.noYearTitle
        }
    }

    /// The groups the shelf draws, in order: year groups newest first, then
    /// made groups A to Z by name, then the no-year group last.
    ///
    /// A year group and the no-year group are drawn only when they hold a
    /// course. A made group is drawn even when empty, unless
    /// `drawsEmptyMadeGroups` is false (the sidebar passes false while the
    /// filter field narrows the list, so a filtered shelf shows only what
    /// matched).
    static func groups(
        of entries: [Entry],
        arrangement: Arrangement,
        drawsEmptyMadeGroups: Bool = true
    ) -> [Group] {
        var byYear: [Int: [String]] = [:]
        var byMadeGroup: [String: [String]] = [:]
        var withNoYear: [String] = []
        for entry in entries {
            let place: Place = ReferenceShelf.place(
                ofFolder: entry.folderName, schoolYear: entry.schoolYear, in: arrangement
            )
            switch place {
            case .year(let year):
                var inThatYear: [String] = byYear[year] ?? []
                inThatYear.append(entry.folderName)
                byYear[year] = inThatYear
            case .noYear:
                withNoYear.append(entry.folderName)
            case .made(let id):
                var inThatGroup: [String] = byMadeGroup[id] ?? []
                inThatGroup.append(entry.folderName)
                byMadeGroup[id] = inThatGroup
            }
        }

        var result: [Group] = []

        var years: [Int] = []
        for (year, _) in byYear {
            years.append(year)
        }
        years.sort()
        years.reverse()
        for year in years {
            result.append(Group(
                place: .year(year),
                title: SchoolYear.label(forStartingYear: year),
                folderNames: byYear[year] ?? []
            ))
        }

        for made in ReferenceShelf.madeGroupsInOrder(arrangement.groups) {
            let folderNames: [String] = byMadeGroup[made.id] ?? []
            if folderNames.isEmpty && !drawsEmptyMadeGroups {
                continue
            }
            result.append(Group(place: .made(made.id), title: made.name, folderNames: folderNames))
        }

        if !withNoYear.isEmpty {
            result.append(Group(place: .noYear, title: arrangement.noYearTitle, folderNames: withNoYear))
        }
        return result
    }

    /// Made groups A to Z by name, the way Finder sorts (localised, case
    /// insensitive), then by id so two equal names keep one order.
    static func madeGroupsInOrder(_ groups: [MadeGroup]) -> [MadeGroup] {
        var sorted: [MadeGroup] = groups
        sorted.sort { first, second in
            let order: ComparisonResult = first.name.localizedStandardCompare(second.name)
            if order == .orderedSame {
                return first.id < second.id
            }
            return order == .orderedAscending
        }
        return sorted
    }

    /// The name as it is kept: every run of white space and control
    /// characters becomes one space, and the ends are trimmed. A pasted line
    /// break is a space, not a refusal.
    static func normalizedName(_ typed: String) -> String {
        var result: String = ""
        var pendingSpace: Bool = false
        for scalar in typed.unicodeScalars {
            let isSpace: Bool = CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
            if isSpace {
                pendingSpace = true
                continue
            }
            if pendingSpace && !result.isEmpty {
                result.append(" ")
            }
            pendingSpace = false
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// The form two names are compared in: case, width and accents folded,
    /// and every dash the same dash, so "2025-26" is the year group 2025–26.
    static func comparable(_ name: String) -> String {
        let folded: String = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil
        )
        var result: String = ""
        for character in folded {
            if character == "-" || character == "—" || character == "‒" || character == "−" {
                result.append("–")
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Why `typed` cannot name a group, or nil when it can.
    ///
    /// `renaming` is the group being renamed (a made group or the no-year
    /// group), whose own name is never in the way. The names in the way are
    /// every year the shelf can draw (the offered years, and any year a
    /// course sits in), the no-year group's, and every made group's.
    static func nameProblem(
        _ typed: String,
        renaming: Place?,
        arrangement: Arrangement,
        yearsOnTheShelf: [Int],
        on day: CalendarDay
    ) -> NameProblem? {
        let name: String = ReferenceShelf.normalizedName(typed)
        if name.isEmpty {
            return .empty
        }
        if name.count > ReferenceShelf.mostCharacters {
            return .tooLong
        }
        let wanted: String = ReferenceShelf.comparable(name)

        var years: [Int] = SchoolYear.offeredStartingYears(on: day)
        for year in yearsOnTheShelf where !years.contains(year) {
            years.append(year)
        }
        for year in years {
            let label: String = SchoolYear.label(forStartingYear: year)
            if ReferenceShelf.comparable(label) == wanted {
                return .taken(label)
            }
        }
        if renaming != .noYear && ReferenceShelf.comparable(arrangement.noYearTitle) == wanted {
            return .taken(arrangement.noYearTitle)
        }
        for group in arrangement.groups {
            if renaming == .made(group.id) {
                continue
            }
            if ReferenceShelf.comparable(group.name) == wanted {
                return .taken(group.name)
            }
        }
        return nil
    }

    /// A new group id no group in `arrangement` has.
    static func newGroupID(avoiding arrangement: Arrangement) -> String {
        while true {
            let hex: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let candidate: String = "g-" + String(hex.prefix(8))
            if arrangement.group(withID: candidate) == nil && !ReferenceShelf.isKeptGroupID(candidate, in: arrangement) {
                return candidate
            }
        }
    }

    /// True when an entry this app could not read carries that id, so a new
    /// group never takes an id a newer app's entry already uses.
    static func isKeptGroupID(_ id: String, in arrangement: Arrangement) -> Bool {
        for entry in arrangement.keptGroupEntries {
            if let object = entry as? [String: Any], let keptID = object["id"] as? String, keptID == id {
                return true
            }
        }
        return false
    }

    // MARK: - Reading and writing the file

    /// Reads the file's bytes, or nil for no file.
    ///
    /// What counts as unreadable is deliberately narrow and decided by the
    /// SHAPE, never by a value the teacher could have chosen: not JSON, not
    /// an object, no whole-number `version`, a `groups` that is not a list,
    /// or a `placements` that is not an object. Inside those, an entry that
    /// cannot be read is left off the shelf and kept in the file.
    static func reading(_ data: Data?) -> Reading {
        guard let data else {
            return .absent
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = parsed as? [String: Any] else {
            return .unreadable
        }
        guard let versionNumber = object["version"] as? NSNumber,
              CFGetTypeID(versionNumber) != CFBooleanGetTypeID(),
              let version = Int(exactly: versionNumber.doubleValue),
              version >= 1 else {
            return .unreadable
        }

        var arrangement: Arrangement = Arrangement()
        arrangement.keptTopLevel = object

        if let rawName = object["noYearGroupName"] as? String {
            let name: String = ReferenceShelf.normalizedName(rawName)
            if !name.isEmpty {
                arrangement.noYearGroupName = name
            }
        }

        if let rawGroups = object["groups"] {
            guard let list = rawGroups as? [Any] else {
                return .unreadable
            }
            var seen: Set<String> = []
            for entry in list {
                guard let group = entry as? [String: Any],
                      let id = group["id"] as? String, !id.isEmpty,
                      let rawName = group["name"] as? String,
                      !seen.contains(id) else {
                    arrangement.keptGroupEntries.append(entry)
                    continue
                }
                let name: String = ReferenceShelf.normalizedName(rawName)
                if name.isEmpty {
                    arrangement.keptGroupEntries.append(entry)
                    continue
                }
                seen.insert(id)
                arrangement.groups.append(MadeGroup(id: id, name: name))
            }
        }

        if let rawPlacements = object["placements"] {
            guard let map = rawPlacements as? [String: Any] else {
                return .unreadable
            }
            for (folderName, value) in map {
                if let id = value as? String {
                    arrangement.placements[folderName] = id
                } else {
                    arrangement.keptPlacementEntries[folderName] = value
                }
            }
        }

        if version > ReferenceShelf.currentVersion {
            return .newer(arrangement)
        }
        return .read(arrangement)
    }

    /// The bytes to write for `arrangement`: what it understands, written
    /// over the top level it was read from, with everything it kept put back.
    static func encoded(_ arrangement: Arrangement) throws -> Data {
        var object: [String: Any] = arrangement.keptTopLevel
        object["version"] = ReferenceShelf.currentVersion
        if let name = arrangement.noYearGroupName, !name.isEmpty {
            object["noYearGroupName"] = name
        } else {
            object.removeValue(forKey: "noYearGroupName")
        }

        var groups: [Any] = []
        for group in arrangement.groups {
            groups.append(["id": group.id, "name": group.name])
        }
        for kept in arrangement.keptGroupEntries {
            groups.append(kept)
        }
        object["groups"] = groups

        var placements: [String: Any] = arrangement.keptPlacementEntries
        for (folderName, id) in arrangement.placements {
            placements[folderName] = id
        }
        object["placements"] = placements

        return try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// True when two arrangements say the same thing about the shelf: the
    /// same groups in the same order, the same placements, the same no-year
    /// name, and the same entries kept for another version.
    static func saysTheSame(_ first: Arrangement, _ second: Arrangement) -> Bool {
        if first.noYearGroupName != second.noYearGroupName {
            return false
        }
        if first.groups != second.groups || first.placements != second.placements {
            return false
        }
        if first.keptGroupEntries.count != second.keptGroupEntries.count {
            return false
        }
        var firstKept: [String] = []
        for (folderName, _) in first.keptPlacementEntries {
            firstKept.append(folderName)
        }
        var secondKept: [String] = []
        for (folderName, _) in second.keptPlacementEntries {
            secondKept.append(folderName)
        }
        return firstKept.sorted() == secondKept.sorted()
    }

    /// The arrangement with the placements nobody needs taken out: those of
    /// a folder that is not there, and those naming a group that is not
    /// there. A folder counts as there while a replace or an import of it is
    /// part way (its hidden folder exists), so a change made in another
    /// window at that moment does not take the course out of its group.
    static func pruned(_ arrangement: Arrangement, folderIsThere: (String) -> Bool) -> Arrangement {
        var result: Arrangement = arrangement
        var kept: [String: String] = [:]
        for (folderName, id) in arrangement.placements {
            if arrangement.group(withID: id) == nil && !ReferenceShelf.isKeptGroupID(id, in: arrangement) {
                continue
            }
            if !folderIsThere(folderName) {
                continue
            }
            kept[folderName] = id
        }
        result.placements = kept
        return result
    }
}
