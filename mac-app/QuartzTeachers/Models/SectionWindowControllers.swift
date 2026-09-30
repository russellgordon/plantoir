import Foundation

/// The section windows that are on screen, and the work each one owns: its
/// preview, and its deploy.
///
/// **Why a registry of closures rather than a request an observer notices.**
/// The assistant needs to do three things in order — stop the preview, change
/// the files, start it again — and the middle step must not begin until the
/// first has finished. A request that a view observes and acts on later cannot
/// express that: the runner posts, carries on, and the window stops the
/// preview at whatever moment SwiftUI next evaluates a body, which may be
/// after the writes. That is exactly the fault this replaced. It also failed
/// silently, which is worse than failing: the files changed, the preview did
/// not move, and nothing anywhere said why.
///
/// So the window hands over the things it alone can do, and the runner calls
/// them directly, in order, on the main actor. Ordering becomes ordinary
/// sequential code.
///
/// **Why the window still owns them.** A preview is a server on a leased port
/// and a web view; both belong to the section window, and the assistant has
/// neither. A deploy is the same story for a different reason: the window
/// carries the console the output streams into, the progress header, and the
/// live-site link at the end. Registering the window's own `startPreview()`,
/// `stopPreview()` and `startDeploy()` means the assistant and the toolbar
/// buttons run the SAME code rather than two versions of it that drift.
///
/// Nothing registered is not an error. A teacher can change pages, or set a
/// deploy for half six in the morning, with no section window open at all —
/// and then there is nothing to press. The caller does the work itself and
/// says where the answer went.
@MainActor
final class SectionWindowControllers {

    // MARK: - Types

    /// Which section a window is showing.
    struct Key: Hashable {

        // MARK: - Stored properties

        let folderPath: String
        let courseCode: String
        let sectionNumber: Int

        // MARK: - Initializer

        init(folderPath: String, courseCode: String, sectionNumber: Int) {
            // Put in one spelling on the way IN, so a caller cannot fail to
            // match by spelling the same folder a different way: the folder
            // in the disk's own spelling (links, `/private`, case and Unicode
            // form — `FolderIdentity`, #189) and the course code in lower
            // case. The previous mechanism compared raw strings, and a
            // mismatch there would have been invisible. (Until #189 this said
            // "case-folded" of both, and only the code was.)
            self.folderPath = FolderIdentity.canonicalPath(URL(fileURLWithPath: folderPath).standardizedFileURL.path)
            self.courseCode = courseCode.lowercased()
            self.sectionNumber = sectionNumber
        }
    }

    /// Where a section's preview has got to, from the teacher's side of the
    /// glass.
    ///
    /// A single "is it running" boolean could not tell the two useful states
    /// apart, because the launcher keeps running the whole time it SERVES the
    /// site — so a preview mid-build and a preview sitting finished on screen
    /// looked identical, and the assistant said "once any rebuild in progress
    /// finishes" to a teacher who was already looking at the finished thing.
    enum PreviewState: Equatable {

        /// Nothing is up: no build running and nothing on screen.
        case notRunning

        /// Building. The teacher is watching a progress view, not a site.
        case building

        /// Built, served, and on screen.
        case showing
    }

    /// What a section window can be asked to do.
    struct Controller {

        // MARK: - Stored properties

        let previewState: () -> PreviewState
        let startPreview: () -> Void

        /// Asynchronous, and that is the whole point of it.
        ///
        /// Stopping a preview reaches into the container and kills the
        /// processes belonging to that section. Started as fire-and-forget —
        /// which is right behind a button, where the teacher has already moved
        /// on — it is still running when the next preview begins, and kills
        /// that one too. Awaiting it is what makes "stop, write, start" mean
        /// what it says.
        let stopPreview: () async -> Void

        /// Press this window's Deploy, and do not come back until the section
        /// is out — or until something stopped it going out.
        ///
        /// Awaited for a plainer reason than the stop: the assistant has to
        /// tell the teacher what happened, and a deploy it did not wait for
        /// can only be reported as "started". A teacher who is told a section
        /// is deployed, when the upload has three minutes left, will go and
        /// look at a site that is not there yet.
        let deploy: () async -> AssistSiteWorkResult

        // MARK: - Functions

        /// Whether there is a preview to stop — building or showing, both
        /// count. Derived rather than stored, so it cannot disagree with
        /// `previewState`.
        func isPreviewRunning() -> Bool {
            return previewState() != .notRunning
        }
    }

    // MARK: - Stored properties

    private var controllers: [Key: Controller] = [:]

    static let shared: SectionWindowControllers = SectionWindowControllers()

    // MARK: - Functions

    /// A section window says it is on screen and can drive its own work.
    func register(
        folderPath: String,
        courseCode: String,
        sectionNumber: Int,
        controller: Controller
    ) {
        controllers[Key(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)]
            = controller
    }

    /// A section window says it has gone.
    func unregister(folderPath: String, courseCode: String, sectionNumber: Int) {
        controllers.removeValue(
            forKey: Key(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
        )
    }

    /// The window showing this section, if one is open.
    func controller(folderPath: String, courseCode: String, sectionNumber: Int) -> Controller? {
        return controllers[
            Key(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
        ]
    }

    /// Forget everything. Tests only — the app's windows manage their own.
    func forgetAll() {
        controllers.removeAll()
    }
}
