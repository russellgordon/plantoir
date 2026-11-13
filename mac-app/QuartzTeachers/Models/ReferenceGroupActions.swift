import Foundation

/// One choice in a reference course's Move to Group ▸ submenu.
struct ReferenceMoveTarget: Identifiable, Equatable {

    // MARK: - Stored properties

    let place: ReferenceShelf.Place

    /// The year label, the no-year group's name, or a made group's name.
    let title: String

    /// The group the course is in now: drawn with a checkmark, does nothing.
    let isCurrent: Bool

    // MARK: - Computed properties

    var id: String {
        return ReferenceShelf.identifier(for: place)
    }
}

/// The groups on the Reference Courses shelf, as the window's sidebar, its
/// sheets and the Course menu change them (#572, third piece). Every one of
/// these calls `ReferenceShelfStore`, which decides against the file as it is
/// at the click, and then reads the shelf again. None of them touches a
/// course folder: groups are a view.
extension WorkspaceModel {

    // MARK: - Functions

    /// What Move to Group ▸ offers for a course: where its school year puts
    /// it first (the year, or the no-year group by its name), then every
    /// group the teacher made, A to Z. The group it is in is marked.
    func referenceMoveTargets(for course: Course, on day: CalendarDay = CalendarDay.today()) -> [ReferenceMoveTarget] {
        let arrangement: ReferenceShelf.Arrangement = referenceShelf.arrangement
        let current: ReferenceShelf.Place = referenceShelfPlace(of: course, on: day)
        let own: ReferenceShelf.Place = ReferenceShelf.Place.forYear(course.schoolYear(on: day))
        var result: [ReferenceMoveTarget] = [ReferenceMoveTarget(
            place: own, title: ReferenceShelf.title(of: own, in: arrangement), isCurrent: current == own
        )]
        for group in ReferenceShelf.madeGroupsInOrder(arrangement.groups) {
            let place: ReferenceShelf.Place = .made(group.id)
            result.append(ReferenceMoveTarget(place: place, title: group.name, isCurrent: current == place))
        }
        return result
    }

    /// True when the teacher can change the groups right now: the file is
    /// absent or readable by this version.
    var referenceGroupsMayChange: Bool {
        return referenceShelf.refusal == nil
    }

    /// Moves a course; on a refusal, the alert says why.
    func moveReferenceCourse(_ course: Course, to place: ReferenceShelf.Place, on day: CalendarDay = CalendarDay.today()) {
        guard let coursesDirectoryURL else {
            return
        }
        let entry: ReferenceShelf.Entry = ReferenceShelf.Entry(
            folderName: course.code, displayCode: course.displayCode, schoolYear: course.schoolYear(on: day)
        )
        let refusal: ReferenceShelfRefusal? = ReferenceShelfStore.move(
            entry, to: place, coursesDirectoryURL: coursesDirectoryURL, entries: referenceShelfEntries(on: day)
        )
        refreshReferenceShelf()
        if let refusal {
            referenceGroupProblem = ReferenceGroupProblem(
                title: ReferenceGroupWording.couldNotMoveTitle(course: course.displayCode),
                sentence: refusal.sentence
            )
            return
        }
        isShowingReferenceCourses = true
        openReferenceGroup(place)
        WorkspaceModel.rememberOpenFolders()
    }

    /// The sentence under the New Group or Rename Group field, live, or nil.
    func referenceGroupNameProblem(_ typed: String, renaming: ReferenceShelf.Place?) -> String? {
        if let refusal = referenceShelf.refusal {
            return refusal
        }
        let problem: ReferenceShelf.NameProblem? = ReferenceShelf.nameProblem(
            typed, renaming: renaming, arrangement: referenceShelf.arrangement
        )
        return problem?.sentence
    }

    /// Start the Groups Again… (an arrangement that cannot be read): moves
    /// it aside and reads the shelf again; on a refusal, the alert says why.
    func startReferenceGroupsAgain() {
        guard let coursesDirectoryURL else {
            return
        }
        let outcome: Result<String?, ReferenceShelfRefusal> = ReferenceShelfStore.startAgain(
            coursesDirectoryURL: coursesDirectoryURL
        )
        refreshReferenceShelf()
        if case .failure(let refusal) = outcome {
            referenceGroupProblem = ReferenceGroupProblem(
                title: ReferenceGroupWording.couldNotStartAgainTitle, sentence: refusal.sentence
            )
        }
    }

    /// New Group…: makes it, opens it, and — when it was chosen from inside
    /// a course's Move to Group submenu — moves that course into it.
    /// Returns the sentence to show in the sheet, or nil when it was made.
    func makeReferenceGroup(named typed: String, on day: CalendarDay = CalendarDay.today()) -> String? {
        guard let coursesDirectoryURL else {
            return ReferenceGroupWording.couldNotSaveGroups
        }
        let made: Result<String, ReferenceShelfRefusal> = ReferenceShelfStore.makeGroup(
            named: typed, coursesDirectoryURL: coursesDirectoryURL
        )
        refreshReferenceShelf()
        switch made {
        case .failure(let refusal):
            return refusal.sentence
        case .success(let id):
            isShowingReferenceCourses = true
            openReferenceGroup(.made(id))
            WorkspaceModel.rememberOpenFolders()
            if let folderName = newGroupThenMove {
                newGroupThenMove = nil
                for course in courses where course.code == folderName && course.isKeptForReference {
                    moveReferenceCourse(course, to: .made(id), on: day)
                }
            }
            return nil
        }
    }

    /// Rename Group…: returns the sentence to show in the sheet, or nil.
    func renameReferenceGroup(_ group: ReferenceShelfGroup, to typed: String) -> String? {
        guard let coursesDirectoryURL else {
            return ReferenceGroupWording.couldNotSaveGroups
        }
        let refusal: ReferenceShelfRefusal? = ReferenceShelfStore.renameGroup(
            group.place, to: typed, coursesDirectoryURL: coursesDirectoryURL
        )
        refreshReferenceShelf()
        return refusal?.sentence
    }

    /// Remove Group: an empty group goes at once; one that holds courses is
    /// asked about first (`removeGroupRequest`).
    func askToRemoveReferenceGroup(_ group: ReferenceShelfGroup) {
        if !referenceGroupHoldsACourse(group) {
            removeReferenceGroup(group)
            return
        }
        removeGroupRequest = group
    }

    /// True when any course, filtered out of view or not, is in the group.
    func referenceGroupHoldsACourse(_ group: ReferenceShelfGroup, on day: CalendarDay = CalendarDay.today()) -> Bool {
        for course in courses where course.isKeptForReference {
            if referenceShelfPlace(of: course, on: day) == group.place {
                return true
            }
        }
        return false
    }

    /// Removes the group; its courses go back to their school years.
    func removeReferenceGroup(_ group: ReferenceShelfGroup, on day: CalendarDay = CalendarDay.today()) {
        guard let coursesDirectoryURL, case .made(let id) = group.place else {
            return
        }
        let refusal: ReferenceShelfRefusal? = ReferenceShelfStore.removeGroup(
            withID: id, coursesDirectoryURL: coursesDirectoryURL, entries: referenceShelfEntries(on: day)
        )
        refreshReferenceShelf()
        if let refusal {
            referenceGroupProblem = ReferenceGroupProblem(
                title: ReferenceGroupWording.couldNotRemoveTitle(group: group.title),
                sentence: refusal.sentence
            )
            return
        }
        expandedReferenceGroups.remove(id)
        WorkspaceModel.rememberOpenFolders()
    }
}
