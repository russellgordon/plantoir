import SwiftUI

/// The "Reference Courses" heading in the sidebar (#572, #834): its title,
/// its right-click menu, and since #834 a small button that opens the SAME
/// menu (Russell, 2026-11-13), so a teacher who never right-clicks finds New
/// Reference Course…, New Group… and, while the arrangement cannot be read,
/// Start the Groups Again…. The right-click and the Course menu stay.
///
/// One list of items, `ReferenceShelfHeadingMenu`, is drawn by both, so the
/// button can never offer something the right-click does not.
///
/// The button is a borderless menu button, the sidebar's own control style
/// (the footer's + and − are `.borderless`): AppKit draws its hover and its
/// pressed state, Tab reaches it with keyboard navigation on, and VoiceOver
/// names it `headingMenuLabel`. It is never disabled: New Reference
/// Course… applies whenever the shelf is drawn, so there is always
/// something it can do, and the shelf heading is drawn only when the shelf
/// holds a course or a group.
struct ReferenceShelfHeading: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            Text(ReferenceWording.groupTitle)
            Spacer(minLength: 0)
            Menu {
                ReferenceShelfHeadingMenu()
            } label: {
                Label(ReferenceGroupWording.headingMenuLabel, systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(ReferenceGroupWording.headingMenuLabel)
            .accessibilityLabel(ReferenceGroupWording.headingMenuLabel)
            .accessibilityIdentifier("referenceShelfHeadingMenu")
        }
        .contextMenu {
            ReferenceShelfHeadingMenu()
        }
    }
}

/// What the Reference Courses heading offers, by right-click and by its
/// button alike (#834).
struct ReferenceShelfHeadingMenu: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Body

    var body: some View {
        // The shelf's own door to the New Course wizard (#572), opening it
        // with the reference choice already made. The shelf is drawn only
        // when it holds a course or a group, so the wizard's own toggle is
        // the door for a teacher with neither.
        Button(ReferenceCreationWording.newReferenceCourseMenuItem, systemImage: "plus") {
            workspace.newCourseWizardIsForReference = true
            workspace.isShowingNewCourseWizard = true
        }
        .accessibilityIdentifier("newReferenceCourse")
        Button(ReferenceGroupWording.newGroupMenuItem, systemImage: "folder.badge.plus") {
            workspace.newGroupThenMove = nil
            workspace.isMakingAReferenceGroup = true
        }
        .disabled(!workspace.referenceGroupsMayChange)
        .accessibilityIdentifier("newReferenceGroup")
        // An arrangement that cannot be read is not a dead end: the way out
        // is here, said in a sentence. A newer version's arrangement is left
        // as it is.
        if let refusal = workspace.referenceShelf.refusal {
            Divider()
            Text(refusal)
            if workspace.referenceShelf.mayStartAgain {
                Button(ReferenceGroupWording.startAgainMenuItem) {
                    workspace.isAskingToStartReferenceGroupsAgain = true
                }
                .accessibilityIdentifier("startReferenceGroupsAgain")
            }
        }
    }
}
