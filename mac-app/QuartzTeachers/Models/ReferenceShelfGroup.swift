import Foundation

/// One group on the Reference Courses shelf as the sidebar draws it: the
/// group, and the courses in it (#572, third piece). What decides the groups
/// and their order is `ReferenceShelf.groups`; this only carries the courses
/// alongside.
struct ReferenceShelfGroup: Identifiable, Equatable {

    // MARK: - Stored properties

    let group: ReferenceShelf.Group

    /// The courses in it, in the order the sidebar shows them.
    let courses: [Course]

    /// What the no-year group's fold state is remembered as: not a year, and
    /// never one, since the offered range starts at 2022. The same `0` it
    /// was before groups, so nobody's fold state moves on upgrade.
    static let otherIdentifier: Int = 0

    // MARK: - Computed properties

    var id: String {
        return group.id
    }

    var title: String {
        return group.title
    }

    var place: ReferenceShelf.Place {
        return group.place
    }

    /// The SF Symbol for its row: a calendar for a school year and for the
    /// no-year group (as before groups, so the shelf a teacher upgrades to
    /// looks the same), and a folder for a group the teacher made.
    var systemImage: String {
        switch group.place {
        case .year, .noYear:
            return "calendar"
        case .made:
            return "folder"
        }
    }

    /// True when the teacher can rename it: a made group, or the no-year
    /// group. A year group's name is its year (Russell, 2026-11-12).
    var isRenamable: Bool {
        switch group.place {
        case .year:
            return false
        case .noYear, .made:
            return true
        }
    }

    // MARK: - Functions

    static func == (first: ReferenceShelfGroup, second: ReferenceShelfGroup) -> Bool {
        if first.group != second.group || first.courses.count != second.courses.count {
            return false
        }
        for index in 0..<first.courses.count where first.courses[index].code != second.courses[index].code {
            return false
        }
        return true
    }
}

/// A group change that did not happen, for the sidebar's alert.
struct ReferenceGroupProblem: Identifiable, Equatable {

    // MARK: - Stored properties

    let title: String
    let sentence: String

    // MARK: - Computed properties

    var id: String {
        return title + "\n" + sentence
    }
}
