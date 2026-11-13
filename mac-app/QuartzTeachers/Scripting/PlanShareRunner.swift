import Foundation
import Observation

/// Runs one share of a course's unit plans (#709): `deploy.sh <CODE> --plans
/// …` through a `ScriptRunner`, shown in the share sheet's console, where the
/// launcher asks for a Cloudflare token or the plans' username and password
/// the way it asks for a section's deploy.
///
/// The course is held under a work lease of kind `publish` while it runs
/// (review M7: the kind that already means "sending something somewhere"),
/// so Quit asks first, Rename, Back Up, Start of Year and Archive wait, and
/// an outside assistant's deploy waits, all as they do for a section's
/// deploy. The trail lines come from the markers through `PlanShareReport`,
/// which every run of a launcher reads.
@MainActor
@Observable
final class PlanShareRunner {

    // MARK: - Stored properties

    /// The console's runner, reused for every share from this tab.
    let runner: ScriptRunner = ScriptRunner()

    /// What the current or last share was.
    var choice: PlanSharing.Choice = .shareOpen

    /// The school year the current or last run was for.
    var year: Int = 0

    /// True from the click until the sheet is closed.
    var isShowingSheet: Bool = false

    /// Why a share could not start at all, for the bar's alert.
    var couldNotStart: String?

    /// The course this runner holds a lease for while it runs.
    private var heldCourseCode: String?
    private var heldFolderPath: String?

    // MARK: - Computed properties

    /// The console sheet's title.
    var title: String {
        if choice == .stop {
            return "Stopping sharing the \(PlanSharing.yearLabel(year)) unit plans"
        }
        return "Sharing the \(PlanSharing.yearLabel(year)) unit plans"
    }

    // MARK: - Functions

    /// Starts a share. `includeAnswerKeys` is only read by a share without a
    /// password; the arguments say nothing of a username or a password.
    func start(
        course: Course,
        folder: URL,
        choice: PlanSharing.Choice,
        includeAnswerKeys: Bool,
        year: Int,
        cloudflareAccountID: String
    ) {
        if runner.isRunning {
            return
        }
        if let holding = WorkLeaseRegistry.claimAPublish(
            folderPath: folder.path, courseCode: course.code, sectionNumber: PlanSharing.leaseSection
        ) {
            _ = holding
            couldNotStart = PlanSharingWording.courseBusy
            return
        }
        heldCourseCode = course.code
        heldFolderPath = folder.path
        self.choice = choice
        self.year = year
        isShowingSheet = true
        let arguments: [String] = PlanSharing.arguments(
            courseCode: course.code,
            choice: choice,
            includeAnswerKeys: includeAnswerKeys,
            year: year,
            cloudflareAccountID: cloudflareAccountID
        )
        runner.run(scriptNamed: "deploy.sh", arguments: arguments, workingDirectory: folder)
        if !runner.isRunning {
            // The launcher did not start (a missing launcher, the app
            // closing): the lease goes now, and the console says why.
            releaseTheCourse()
        }
    }

    /// Called when the runner stops running: the lease goes.
    func finished() {
        releaseTheCourse()
    }

    /// Cancel, from the console.
    func cancel() {
        runner.stopByUser()
    }

    private func releaseTheCourse() {
        guard let code = heldCourseCode, let path = heldFolderPath else {
            return
        }
        CourseActivity.endPublish(folderPath: path, courseCode: code, sectionNumber: PlanSharing.leaseSection)
        heldCourseCode = nil
        heldFolderPath = nil
    }
}
