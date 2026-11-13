import SwiftUI

/// The sheets and alerts for the groups on the Reference Courses shelf
/// (#572, third piece): New Group…, Rename Group…, the question before a
/// group that holds courses is removed (a sheet of facts since #834), Start
/// the Groups Again, and a change that did not happen.
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
            // Sheets since #834: one sentence, then the facts as rows, and
            // Cancel answering both Return and Escape, which an alert could
            // not give one button (#832). The action takes no key.
            .sheet(isPresented: isAskingToRemove) {
                FactsQuestionSheet(
                    question: ReferenceGroupWording.removeGroupQuestion(
                        group: workspace.removeGroupRequest?.title ?? "", courseCount: removeGroupCourseCount
                    ),
                    identifier: "removeReferenceGroupQuestion",
                    goAhead: {
                        if let group = workspace.removeGroupRequest {
                            workspace.removeGroupRequest = nil
                            workspace.removeReferenceGroup(group)
                        }
                    },
                    cancel: {
                        workspace.removeGroupRequest = nil
                    }
                )
            }
            .sheet(isPresented: isAskingToStartAgain) {
                FactsQuestionSheet(
                    question: ReferenceGroupWording.startAgainQuestion,
                    identifier: "startReferenceGroupsAgainQuestion",
                    goAhead: {
                        workspace.isAskingToStartReferenceGroupsAgain = false
                        workspace.startReferenceGroupsAgain()
                    },
                    cancel: {
                        workspace.isAskingToStartReferenceGroupsAgain = false
                    }
                )
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
