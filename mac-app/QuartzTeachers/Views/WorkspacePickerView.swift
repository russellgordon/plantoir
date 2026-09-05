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
            // while choosing, and the confirmation stands on its own. The
            // same goes for a synced folder awaiting the teacher's decision.
            if !workspace.workspaceCanBeInitialized && !workspace.needsCloudSyncDecision {
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

            // A folder a cloud service keeps in sync: say so here, where the
            // teacher can still change their mind for free. Shown above the
            // empty-folder offer too, so setting up a synced folder is done
            // knowing what it costs. Never red — this is not a mistake, it
            // is a choice.
            if let syncedFolder = workspace.syncedFolder, workspace.needsCloudSyncDecision {
                if let chosenURL = workspace.workspaceURL, !workspace.workspaceCanBeInitialized {
                    ViewThatFits(in: .horizontal) {
                        FinderPathBarView(folderURL: chosenURL)
                            .fixedSize(horizontal: true, vertical: false)
                        FinderPathBarView(folderURL: chosenURL)
                    }
                    .frame(maxWidth: 520)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(CloudSyncWording.headline(service: syncedFolder.serviceName))
                        .bold()
                    CloudSyncExplanationView(syncedFolder: syncedFolder)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .accessibilityIdentifier("cloudSyncChoice")
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
            } else if workspace.needsCloudSyncDecision {
                // An existing working folder that is synced: going ahead is
                // one press, and so is picking another. Neither is the
                // default action — a Return pressed out of habit should not
                // decide this.
                Button(CloudSyncWording.useAnywayButton) {
                    workspace.acknowledgeCloudSync()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("useSyncedFolderButton")

                Button("Choose a Different Folder…") {
                    workspace.isChoosingWorkspace = true
                }
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
