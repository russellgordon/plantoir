import AppKit
import SwiftUI

/// A section window's half of "Open in Browser" for a deployed folder (#850):
/// what the one Open in Browser opens, its help, the notice with Stop, and
/// when the facts are read again. The app-wide record of what is shown is
/// `DeployedFolderShows`; the decision is `DeployedFolderOffer`.
///
/// **One Open in Browser for both** (Russell, 2026-11-13). The toolbar
/// button and Section ▸ Open in Browser open the PREVIEW while one is
/// showing, and the deployed folder otherwise. Their help says which, so a
/// teacher knows what they are looking at: `DeployedFolderWording.previewHelp`
/// or `DeployedFolderWording.help`, or the reason it is greyed.
extension SectionDetailView {

    // MARK: - Computed properties

    /// The working folder's path, or nil with none open.
    var workingFolderPathForTheDeployedFolder: String? {
        return workspace.workspaceURL?.path
    }

    /// This section's deployed folder, while this app shows it.
    var deployedFolderShowHere: DeployedFolderShows.Show? {
        guard let folder = workingFolderPathForTheDeployedFolder else {
            return nil
        }
        return DeployedFolderShows.shared.show(courseCode: course.code, sectionNumber: sectionNumber, workingFolderPath: folder)
    }

    /// Whether the deployed folder can be opened now.
    var deployedFolderIsReady: Bool {
        return deployedFolderLookup?.decision == .offered
    }

    /// Whether the one Open in Browser can be pressed.
    var openInBrowserIsEnabled: Bool {
        return previewURL != nil || deployedFolderIsReady
    }

    /// What Open in Browser's help says: which it opens, or why it cannot.
    var openInBrowserHelp: String {
        if previewURL != nil {
            return DeployedFolderWording.previewHelp
        }
        guard let lookup = deployedFolderLookup else {
            return DeployedFolderWording.previewHelp
        }
        switch lookup.decision {
        case .offered:
            return DeployedFolderWording.help
        case .greyed(let reasonKey):
            if let reasonKey, let sentence = DeployedFolderOffer.sentence(forReasonKey: reasonKey) {
                return sentence
            }
            return DeployedFolderWording.help
        case .absent:
            return DeployedFolderWording.previewHelp
        }
    }

    /// The reason line under Section ▸ Open in Browser, when the deployed
    /// folder is what it would open and it is greyed for a reason.
    var deployedFolderMenuReason: String? {
        if previewURL != nil {
            return nil
        }
        guard let lookup = deployedFolderLookup, case .greyed(let reasonKey) = lookup.decision, let reasonKey else {
            return nil
        }
        // While a deploy runs the Section menu already says it once.
        if reasonKey == "deployIsRunning" {
            return nil
        }
        return DeployedFolderOffer.sentence(forReasonKey: reasonKey)
    }

    // MARK: - Functions

    /// Reads the facts again. Called on events, never on a clock: the
    /// section showing, a deploy ending, a menu opening, the pointer reaching
    /// the button, and a show starting or stopping.
    func refreshTheDeployedFolder() {
        guard let folder = workingFolderPathForTheDeployedFolder else {
            deployedFolderLookup = nil
            return
        }
        deployedFolderLookup = DeployedFolderShows.lookUp(course: course, sectionNumber: sectionNumber, workingFolderPath: folder)
    }

    /// The one Open in Browser: the preview while one shows, the deployed
    /// folder otherwise.
    func openInBrowserPressed(from: DeployedFolderShows.From) {
        if previewURL != nil {
            openInBrowser()
            return
        }
        refreshTheDeployedFolder()
        if deployedFolderIsReady {
            openTheDeployedFolder(from: from)
        }
    }

    /// Opens this section's deployed folder, wherever the press came from.
    func openTheDeployedFolder(from: DeployedFolderShows.From) {
        guard let folder = workingFolderPathForTheDeployedFolder, let sectionFolder = deployedFolderLookup?.sectionFolder else {
            return
        }
        let courseCode: String = course.code
        let number: Int = sectionNumber
        Task { @MainActor in
            let opened: Bool = await DeployedFolderShows.shared.open(
                sectionFolder: sectionFolder, courseCode: courseCode, sectionNumber: number,
                workingFolderPath: folder, from: from
            )
            if !opened {
                deployedFolderCouldNotOpen = true
            }
            refreshTheDeployedFolder()
        }
    }

    /// The result panel's Open in Browser, beside Show in Finder: the folder
    /// the deploy just named.
    func openTheFolderADeployNamed(_ sectionFolder: URL) {
        guard let folder = workingFolderPathForTheDeployedFolder else {
            return
        }
        let courseCode: String = course.code
        let number: Int = sectionNumber
        Task { @MainActor in
            let opened: Bool = await DeployedFolderShows.shared.open(
                sectionFolder: sectionFolder, courseCode: courseCode, sectionNumber: number,
                workingFolderPath: folder, from: .result
            )
            if !opened {
                deployedFolderCouldNotOpen = true
            }
            refreshTheDeployedFolder()
        }
    }

    /// Stop, from the notice or the Section menu.
    func stopShowingTheDeployedFolder() {
        guard let folder = workingFolderPathForTheDeployedFolder else {
            return
        }
        DeployedFolderShows.shared.stop(courseCode: course.code, sectionNumber: sectionNumber, workingFolderPath: folder)
        refreshTheDeployedFolder()
    }

    /// The notice, while shown or after the folder went away.
    @ViewBuilder
    var deployedFolderNotice: some View {
        if deployedFolderShowHere != nil {
            DeployedFolderNoticeView(
                sentence: DeployedFolderWording.notice(section: sectionNumber),
                isShowing: true,
                press: stopShowingTheDeployedFolder
            )
        } else if let folder = workingFolderPathForTheDeployedFolder,
                  DeployedFolderShows.shared.folderWentAway(courseCode: course.code, sectionNumber: sectionNumber, workingFolderPath: folder) {
            DeployedFolderNoticeView(
                sentence: DeployedFolderWording.stoppedFolderGone,
                isShowing: false,
                press: {
                    DeployedFolderShows.shared.dismissFolderWentAway(
                        courseCode: course.code, sectionNumber: sectionNumber, workingFolderPath: folder
                    )
                }
            )
        }
    }

    /// The stage that keeps the facts current and says when opening failed.
    func watchingTheDeployedFolder(_ content: some View) -> some View {
        content
            .onAppear {
                refreshTheDeployedFolder()
            }
            .onChange(of: deployRun.endings) { _, _ in
                refreshTheDeployedFolder()
            }
            .onChange(of: DeployedFolderShows.shared.shows.count) { _, _ in
                refreshTheDeployedFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                refreshTheDeployedFolder()
            }
            .alert(DeployedFolderWording.couldNotOpenTitle, isPresented: $deployedFolderCouldNotOpen) {
                Button(DeployedFolderWording.couldNotOpenButton) {}
            } message: {
                Text(DeployedFolderWording.couldNotOpen)
            }
    }
}
