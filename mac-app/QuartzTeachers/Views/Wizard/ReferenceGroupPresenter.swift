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
                Button(ReferenceGroupWording.removeButton) {
                    if let group = workspace.removeGroupRequest {
                        workspace.removeGroupRequest = nil
                        workspace.removeReferenceGroup(group)
                    }
                }
                // Cancel is the default button (the contract's wording.rule),
                // the shape the replace warning uses.
                Button(ReferenceGroupWording.cancelButton, role: .cancel) {
                    workspace.removeGroupRequest = nil
                }
                .keyboardShortcut(.defaultAction)
            } message: {
                Text(ReferenceGroupWording.removeGroupMessage(courseCount: removeGroupCourseCount))
            }
            .alert(ReferenceGroupWording.startAgainTitle, isPresented: isAskingToStartAgain) {
                Button(ReferenceGroupWording.startAgainButton) {
                    workspace.isAskingToStartReferenceGroupsAgain = false
                    workspace.startReferenceGroupsAgain()
                }
                // Cancel is the default button here too.
                Button(ReferenceGroupWording.cancelButton, role: .cancel) {
                    workspace.isAskingToStartReferenceGroupsAgain = false
                }
                .keyboardShortcut(.defaultAction)
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
