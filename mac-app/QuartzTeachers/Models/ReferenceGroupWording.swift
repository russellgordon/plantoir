import Foundation

/// What a teacher reads about the groups on the Reference Courses shelf
/// (#572, third piece). Every sentence is `contracts/shared-rules.json` →
/// `referenceCourses.groups.wording`, and `ReferenceShelfTests` holds each
/// one to it.
///
/// `{group}` is a group's name as the shelf shows it, `{course}` the code a
/// teacher reads, `{name}` a group name already on the shelf, and
/// `{courses}` "1 course" or "3 courses".
nonisolated enum ReferenceGroupWording {

    // MARK: - Stored properties

    /// On the "Reference Courses" heading's menu, and inside Move to Group.
    static let newGroupMenuItem: String = "New Group…"

    /// The heading's menu button, as VoiceOver and its help name it (#834).
    static let headingMenuLabel: String = "Reference Courses Actions"

    /// The New Group sheet's title.
    static let newGroupTitle: String = "New Group"

    /// The sheets' one field.
    static let nameLabel: String = "Name"

    /// The New Group sheet's button.
    static let createButton: String = "Create"

    /// On a made group's row, and on the no-year group's.
    static let renameGroupMenuItem: String = "Rename Group…"

    /// The Rename Group sheet's title.
    static let renameGroupTitle: String = "Rename Group"

    /// The Rename Group sheet's button.
    static let renameButton: String = "Rename"

    /// On an EMPTY made group's row: it goes at once, nothing is asked.
    static let removeGroupMenuItem: String = "Remove Group"

    /// On a made group that holds courses: the confirmation comes first.
    static let removeGroupAskingMenuItem: String = "Remove Group…"

    /// The confirmation's buttons.
    static let removeButton: String = "Remove Group"
    static let cancelButton: String = "Cancel"

    /// The submenu on a reference course's row and in the Course menu.
    static let moveToGroupMenuItem: String = "Move to Group"

    /// The wizard's picker, shown only when the teacher has made a group.
    static let groupPickerLabel: String = "Group"

    /// The picker's first choice: wherever the school year puts it.
    static let groupPickerDefault: String = "Its school year"

    /// The read-only summary's label for the group a course was put in.
    static let summaryGroupLabel: String = "Group"

    /// Every change refused because the arrangement is there and cannot be
    /// read. Waiting does not help (a hand-edited or foreign-written copy
    /// stays unreadable), so it names the way out instead.
    static let couldNotReadGroups: String =
        "The arrangement of the groups on the reference shelf cannot be read, so nothing was changed. "
        + "Start the Groups Again, on the Reference Courses heading’s menu, sets them up afresh."

    /// On the Reference Courses heading's menu, only while the arrangement
    /// cannot be read.
    static let startAgainMenuItem: String = "Start the Groups Again…"

    /// Its question (#834: one sentence, then the facts as rows).
    static let startAgainTitle: String = "Start the groups on the reference shelf again?"
    static let startAgainSentence: String =
        "Every reference course goes back to the group its school year puts it in."
    static let startAgainWhyLabel: String = "Because"
    static let startAgainWhyValue: String = "The groups’ arrangement could not be read"
    static let startAgainOwnGroupsLabel: String = "Groups you made"
    static let startAgainOwnGroupsValue: String = "Taken off the shelf"
    static let startAgainKeptLabel: String = "Kept"
    static let startAgainKeptValue: String = "What could not be read, beside the new arrangement"
    static let startAgainCoursesLabel: String = "Inside the courses"
    static let startAgainCoursesValue: String = "Nothing changes"
    static let startAgainButton: String = "Start Again"

    /// The alert title when it could not be done.
    static let couldNotStartAgainTitle: String = "Could not start the groups again"

    /// Every change refused because a newer Plantoir arranged the shelf.
    static let arrangedByANewerPlantoir: String =
        "The reference shelf’s groups were last arranged by a newer version of Plantoir, "
        + "so this one leaves them as they are."

    /// A change that could not be saved.
    static let couldNotSaveGroups: String =
        "The reference shelf’s groups could not be saved, so nothing was changed."

    /// The name rule's three sentences.
    static let nameIsEmpty: String = "Give the group a name."
    static let nameIsTooLong: String = "A group name can be at most 40 characters."
    static let nameIsAYear: String = "A school year has a group of its own. Choose a name that is not a school year."

    // MARK: - Functions

    static func nameIsTaken(name: String) -> String {
        return "There is already a group called \(name)."
    }

    /// The confirmation's title.
    static func removeGroupTitle(group: String) -> String {
        return "Remove the group \(group)?"
    }

    /// The confirmation's one sentence (#834).
    static let removeGroupSentence: String = "The group is removed from the Reference Courses shelf."

    /// Its rows: where the courses go, and that none is removed or changed.
    static let removeGroupCoursesLabel: String = "Its courses"
    static let removeGroupCoursesNone: String = "None"
    static let removeGroupCoursesOne: String = "1 course, back to the group its school year puts it in"
    static let removeGroupStaysLabel: String = "The courses themselves"
    static let removeGroupStaysValue: String = "Not removed, and nothing in them changes"

    static func removeGroupCoursesMany(count: Int) -> String {
        return "\(count) courses, back to the groups their school years put them in"
    }

    /// Where the courses go: one value for none, one for one, one for many,
    /// never "(s)".
    static func removeGroupCourses(courseCount: Int) -> String {
        if courseCount == 0 {
            return ReferenceGroupWording.removeGroupCoursesNone
        }
        if courseCount == 1 {
            return ReferenceGroupWording.removeGroupCoursesOne
        }
        return ReferenceGroupWording.removeGroupCoursesMany(count: courseCount)
    }

    /// The removal question, for a group holding `courseCount` courses.
    static func removeGroupQuestion(group: String, courseCount: Int) -> FactsQuestion {
        return FactsQuestion(
            title: removeGroupTitle(group: group),
            message: removeGroupSentence,
            rows: [
                FactsQuestionRow(label: removeGroupCoursesLabel, value: removeGroupCourses(courseCount: courseCount)),
                FactsQuestionRow(label: removeGroupStaysLabel, value: removeGroupStaysValue),
            ],
            action: removeButton,
            cancel: cancelButton
        )
    }

    /// The start-again question.
    static var startAgainQuestion: FactsQuestion {
        return FactsQuestion(
            title: startAgainTitle,
            message: startAgainSentence,
            rows: [
                FactsQuestionRow(label: startAgainWhyLabel, value: startAgainWhyValue),
                FactsQuestionRow(label: startAgainOwnGroupsLabel, value: startAgainOwnGroupsValue),
                FactsQuestionRow(label: startAgainKeptLabel, value: startAgainKeptValue),
                FactsQuestionRow(label: startAgainCoursesLabel, value: startAgainCoursesValue),
            ],
            action: startAgainButton,
            cancel: cancelButton
        )
    }

    /// Remove Group refused: one of its courses would land beside another
    /// course of the same code.
    static func removeWouldClash(group: String, course: String, target: String) -> String {
        return "\(group) was not removed: its \(course) would go back to \(target), "
             + "which already has one. Move one of them to another group first."
    }

    /// The alert titles for a move and a removal that did not happen.
    static func couldNotMoveTitle(course: String) -> String {
        return "Could not move \(course)"
    }

    static func couldNotRemoveTitle(group: String) -> String {
        return "Could not remove \(group)"
    }

    /// "1 course" or "3 courses".
    static func courses(_ count: Int) -> String {
        return count == 1 ? "1 course" : "\(count) courses"
    }
}
