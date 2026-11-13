import SwiftUI

/// The sheets and alerts for the groups on the Reference Courses shelf
/// (#572, third piece): New Group…, Rename Group…, the question before a
/// group that holds courses is removed, and a change that did not happen.
/// On a view of its own, beside the sidebar's other presenters, so the
/// sidebar's chain of modifiers stays one the compiler can read.
///
/// It also listens for a change any window on this folder made, so this
/// window's shelf is drawn from the file as it is now.
struct ReferenceGroupPresenter: ViewModifier {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Computed properties

    var isMakingAGroup: Binding<Bool> {
        return Binding(
            get: { return workspace.isMakingAReferenceGroup },
            set: { showing in
                if !showing {
                    workspace.isMakingAReferenceGroup = false
                    workspace.newGroupThenMove = nil
                }
            }
        )
    }

    var renameRequest: Binding<ReferenceShelfGroup?> {
        return Binding(
            get: { return workspace.renameGroupRequest },
            set: { request in
                workspace.renameGroupRequest = request
            }
        )
    }

    var isAskingToRemove: Binding<Bool> {
        return Binding(
            get: { return workspace.removeGroupRequest != nil },
            set: { showing in
                if !showing {
                    workspace.removeGroupRequest = nil
                }
            }
        )
    }

    var isAskingToStartAgain: Binding<Bool> {
        return Binding(
            get: { return workspace.isAskingToStartReferenceGroupsAgain },
            set: { showing in
                workspace.isAskingToStartReferenceGroupsAgain = showing
            }
        )
    }

    var isShowingAProblem: Binding<Bool> {
        return Binding(
            get: { return workspace.referenceGroupProblem != nil },
            set: { showing in
                if !showing {
                    workspace.referenceGroupProblem = nil
                }
            }
        )
    }

    /// How many courses the group waiting to be removed holds, filtered out
    /// of view or not, for the question.
    var removeGroupCourseCount: Int {
        guard let group = workspace.removeGroupRequest else {
            return 0
        }
        var count: Int = 0
        for course in workspace.courses where course.isKeptForReference {
            if workspace.referenceShelfPlace(of: course) == group.place {
                count += 1
            }
        }
        return count
    }

    // MARK: - Functions

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isMakingAGroup) {
                ReferenceGroupNameSheet(purpose: .make)
            }
            .sheet(item: renameRequest) { group in
                ReferenceGroupNameSheet(purpose: .rename(group))
            }
            .alert(
                ReferenceGroupWording.removeGroupTitle(group: workspace.removeGroupRequest?.title ?? ""),
                isPresented: isAskingToRemove
            ) {
                // Return presses neither button and Escape is Cancel (the
                // contract's wording.rule): an alert gives each button ONE
                // key, so a Cancel that took Return lost Escape (measured,
                // #832; `QuestionKeysTests`). Destructive, so a Return typed
                // out of habit never removes a group.
                Button(ReferenceGroupWording.removeButton, role: .destructive) {
                    if let group = workspace.removeGroupRequest {
                        workspace.removeGroupRequest = nil
                        workspace.removeReferenceGroup(group)
                    }
                }
                Button(ReferenceGroupWording.cancelButton, role: .cancel) {
                    workspace.removeGroupRequest = nil
                }
            } message: {
                Text(ReferenceGroupWording.removeGroupMessage(courseCount: removeGroupCourseCount))
            }
            .alert(ReferenceGroupWording.startAgainTitle, isPresented: isAskingToStartAgain) {
                // The same keys as the removal question.
                Button(ReferenceGroupWording.startAgainButton, role: .destructive) {
                    workspace.isAskingToStartReferenceGroupsAgain = false
                    workspace.startReferenceGroupsAgain()
                }
                Button(ReferenceGroupWording.cancelButton, role: .cancel) {
                    workspace.isAskingToStartReferenceGroupsAgain = false
                }
            } message: {
                Text(ReferenceGroupWording.startAgainMessage)
            }
            .alert(workspace.referenceGroupProblem?.title ?? "", isPresented: isShowingAProblem) {
                Button("OK") {
                    workspace.referenceGroupProblem = nil
                }
            } message: {
                Text(workspace.referenceGroupProblem?.sentence ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: ReferenceShelfStore.didChange)) { notification in
                if let path = notification.object as? String, path == workspace.coursesDirectoryURL?.path {
                    workspace.refreshReferenceShelf()
                }
            }
    }
}
