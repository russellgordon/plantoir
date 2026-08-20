import SwiftUI

/// Shown until a valid working folder has been chosen: explains what the
/// app needs and offers the folder picker.
struct WorkspacePickerView: View {

    // MARK: - Stored properties

    @Environment(WorkspaceModel.self) var workspace

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Once a folder HAS been chosen and is awaiting confirmation,
            // a headline saying "Choose Your Working Folder" answers a
            // question that was just answered — so the header appears only
            // while choosing, and the confirmation stands on its own.
            if !workspace.workspaceCanBeInitialized {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Choose Your Working Folder")
                    .font(.title2)
                    .bold()

                Text("Pick the folder where your course notes live — the one with your courses inside (for example, “Course Notes” on your Desktop). Starting from scratch? Choose an empty folder instead.")
                    .frame(maxWidth: 460)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let problem = workspace.workspaceProblem {
                Text(problem)
                    .frame(maxWidth: 460)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
            }

            if workspace.workspaceCanBeInitialized {
                if let chosenURL = workspace.workspaceURL {
                    // The bar's scroll view greedily fills any width it is
                    // given, pinning a short path to the left of centred
                    // content. At its natural size the stack can centre
                    // it; only a path too long for the cap gets the
                    // full-width scrolling form.
                    ViewThatFits(in: .horizontal) {
                        FinderPathBarView(folderURL: chosenURL)
                            .fixedSize(horizontal: true, vertical: false)
                        FinderPathBarView(folderURL: chosenURL)
                    }
                    .frame(maxWidth: 520)
                }

                Text("This folder is empty. Set it up as your new working folder? Everything needed will be added for you, and you can create your first course right away.")
                    .frame(maxWidth: 460)
                    .multilineTextAlignment(.center)

                // While the setting up runs, the button SAYS so and both
                // buttons go quiet. What it is doing takes a couple of
                // seconds on a fast disk and much longer on a slow one —
                // see `WorkspaceModel.isInitializingWorkspace` — and a
                // button that stays pressable under a frozen window is how
                // ordinary work comes to look like a hang.
                Button {
                    Task {
                        await workspace.initializeWorkspaceInBackground()
                    }
                } label: {
                    if workspace.isInitializingWorkspace {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Setting Up…")
                        }
                    } else {
                        Text("Set Up This Folder")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(workspace.isInitializingWorkspace)
                .accessibilityIdentifier("initializeFolderButton")

                Button("Choose a Different Folder…") {
                    workspace.isChoosingWorkspace = true
                }
                .disabled(workspace.isInitializingWorkspace)
                .accessibilityIdentifier("chooseFolderButton")
            } else {
                Button("Choose Folder…") {
                    workspace.isChoosingWorkspace = true
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("chooseFolderButton")
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
