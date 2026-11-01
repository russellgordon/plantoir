import Foundation

/// One section's deploy as this app runs it from a section window: the
/// runner whose console the teacher watches, and what is said about it once
/// it ends (GitHub #706).
///
/// **Why this outlives the window's view.** The section detail view is given
/// a fresh identity for every selection (`MainWindowView`'s `.id`), so
/// anything it holds in `@State` is thrown away the moment the teacher
/// clicks another section. The deploy itself is not: the `Task` that
/// `startDeploy()` began keeps the old runner alive and keeps writing into
/// it. Before #706 the view coming back made a new, blank runner beside it —
/// an empty console and an enabled Deploy button over a deploy that was
/// still running — and a second press then met the launcher's
/// "already being deployed" refusal, or, during the deploy's build, started
/// a second build that ended the first. Held here, keyed by the folder, the
/// course and the section, the view that comes back binds to the same object
/// the task is still writing.
///
/// **Never replaced.** A section's `SectionDeployRun` is made once and kept
/// for the life of the app: a running task holds a reference to it, and a
/// view that found a NEW object would be watching something nothing writes
/// to. A finished run keeps its legs until that section's next deploy
/// starts over the same runner, but its ending is SHOWN only until one view
/// has displayed it (`isShown(hidingEnding:)`): the view that watched it end,
/// or the first to show the section after it ended while the teacher was
/// elsewhere. After that, and whenever a later preview of the section has
/// started, the section shows its ordinary state. Memory only: nothing here
/// is written to disk.
@Observable
final class SectionDeployRun {

    // MARK: - Stored properties

    /// The deploy's runner. Replaced never; `run()` gives it fresh legs at
    /// the start of each deploy.
    let runner: MultiDestinationDeployRunner = MultiDestinationDeployRunner()

    /// True from the press until the runner actually starts — the span spent
    /// stopping a preview and making the pre-flight checks. See
    /// `SectionDetailView.deployAndWait`, which clears it on every return.
    var isPreparing: Bool = false

    /// The working folder this deploy's work belongs to, so a Cancel pressed
    /// on a view that came back later is aimed at the right place.
    var folder: URL?

    /// The unsaved-settings sentence the deploy said when it started
    /// (#335), so a view that comes back can say it too.
    var unsavedSettingsNotice: String?

    /// True when the deploy has ended and its folder problems have not yet
    /// been put in front of the teacher. Taken — read and cleared — by
    /// exactly one view (`takeFindings()`), so two windows on the same
    /// section cannot both raise the dialog.
    var findingsAreWaiting: Bool = false

    /// Counts the deploy's endings, so a view showing this section can be
    /// told with `.onChange` that it has something to take.
    var endings: Int = 0

    /// The latest ending a view has put in front of the teacher (#706
    /// review, M1). Equal to `endings` once the ending has been seen, and a
    /// view appearing after that hides it (`endingToHideOnAppearing()`), so
    /// a deploy watched to the end does not come back on every visit to the
    /// section until quit.
    var endingShown: Int = 0

    /// When a preview of this section last started in this app, from any
    /// view of it. A view that comes back has a fresh preview runner with no
    /// start time of its own, so without this a finished deploy always won
    /// the "which ran last" comparison and came back over a later preview
    /// (#706 review, M1).
    var previewLastStartedAt: Date?

    // MARK: - Computed properties

    /// True while this run is doing anything at all.
    var isBusy: Bool {
        return isPreparing || runner.isRunning
    }

    // MARK: - Functions

    /// Says the deploy has ended and has findings for whichever view is
    /// showing the section — now, or the next one to appear.
    func noteEnded() {
        findingsAreWaiting = true
        endings += 1
    }

    /// Says a view has put this run's ending in front of the teacher.
    func noteEndingShown() {
        endingShown = endings
    }

    /// Says a preview of this section has started, at `date`.
    func notePreviewStarted(at date: Date) {
        previewLastStartedAt = date
    }

    /// The ending a view appearing now should keep off the screen: the
    /// current one, once some view has shown it — or nil, when there is
    /// nothing to hide because the run is busy or its ending is still unseen.
    func endingToHideOnAppearing() -> Int? {
        if isBusy {
            return nil
        }
        if endings > 0 && endingShown == endings {
            return endings
        }
        return nil
    }

    /// Whether a view should give its console to this run: always while it
    /// is busy; once it has finished, only while it has something to show,
    /// the view did not hide its ending on appearing (`hidingEnding`, from
    /// `endingToHideOnAppearing()`), and no preview of the section has
    /// started since the deploy did.
    func isShown(hidingEnding: Int?) -> Bool {
        if isBusy {
            return true
        }
        if !runner.hasAnyOutput {
            return false
        }
        if let hidingEnding, hidingEnding == endings {
            return false
        }
        if let previewStart = previewLastStartedAt, let deployStart = runner.startedAt, previewStart > deployStart {
            return false
        }
        return true
    }

    /// Whether this caller should show the findings — true once per ending.
    func takeFindings() -> Bool {
        if !findingsAreWaiting {
            return false
        }
        findingsAreWaiting = false
        return true
    }
}

/// Every section deploy this app has run from a section window, by folder,
/// course and section (GitHub #706).
///
/// Deliberately NOT `@Observable`: a view asks for its section's run from
/// inside `body`, and that first ask creates it. Creating into an observed
/// dictionary from `body` would be a state change during a view update. The
/// RUN is observable; the index of runs never needs to be.
final class SectionRuns {

    // MARK: - Stored properties

    static let shared: SectionRuns = SectionRuns()

    private var deploys: [String: SectionDeployRun] = [:]

    // MARK: - Functions

    /// The section's deploy run, made the first time it is asked for and the
    /// same object every time after.
    ///
    /// The folder is made canonical when the key is built (`FolderIdentity`,
    /// 09 → "One folder, however it is spelled"), so `/var/…` and
    /// `/private/var/…`, or a folder typed in another case, are one run.
    func deploy(folder: URL, courseCode: String, sectionNumber: Int) -> SectionDeployRun {
        let key: String = SectionRuns.key(folderPath: folder.path, courseCode: courseCode, sectionNumber: sectionNumber)
        if let existing = deploys[key] {
            return existing
        }
        let made: SectionDeployRun = SectionDeployRun()
        deploys[key] = made
        return made
    }

    /// The run for a section when it has one — never makes one.
    func existingDeploy(folder: URL, courseCode: String, sectionNumber: Int) -> SectionDeployRun? {
        let key: String = SectionRuns.key(folderPath: folder.path, courseCode: courseCode, sectionNumber: sectionNumber)
        return deploys[key]
    }

    /// The key: the canonical folder, the course code lowercased (the folder
    /// is on a case-insensitive disk, so `ics3u` and `ICS3U` are one
    /// course's files), and the section.
    static func key(folderPath: String, courseCode: String, sectionNumber: Int) -> String {
        let folder: String = FolderIdentity.canonicalPath(folderPath)
        return "\(folder)\n\(courseCode.lowercased())\n\(sectionNumber)"
    }

    /// Starts from nothing — for tests.
    func reset() {
        deploys = [:]
    }
}
