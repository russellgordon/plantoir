import Foundation
import Observation

/// A section window's wait for its preview: true from the press until the
/// preview's page first answers or the run ends — and, for as long as it is
/// true, the process-wide record ⌘Q reads (issue #232).
///
/// **One object, so the two can never disagree.** The wait used to be a plain
/// `@State` flag with eight writers, and the build record was kept beside it by
/// an `.onChange` on the flag. That left a gap the review measured: a preview
/// started through a captured closure AFTER its window had gone — the
/// assistant's stop-then-start, or the repair dialog's — still writes the
/// window's state, but a torn-down view is never sent `.onChange`, so the
/// flag went false and the record stayed, and the next ⌘Q asked about a
/// preview nobody was building. Here the flag cannot be cleared without the
/// record going with it: `end()` is the only way back to "not waiting".
@MainActor
@Observable
final class PreviewBuildWait {

    // MARK: - Stored properties

    /// Whether the window is waiting for its preview to appear.
    private(set) var isWaiting: Bool = false

    /// The record this wait put in `CourseActivity`, while it has one.
    ///
    /// Kept rather than rebuilt from the window's folder at the end, because
    /// the window's note of its folder is also written by a deploy: by the
    /// time the wait ends it could name another folder, and ending the wrong
    /// record leaves the right one behind for ever.
    private(set) var recorded: CourseActivity.PreviewBuildRecord?

    // MARK: - Functions

    /// The wait begins, and ⌘Q is told a preview of this section is being
    /// built. A wait already under way is ended first, so a second press can
    /// never leave the first record behind.
    func begin(folderPath: String, courseCode: String, sectionNumber: Int) {
        end()
        let record: CourseActivity.PreviewBuildRecord = CourseActivity.PreviewBuildRecord(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        CourseActivity.beginPreviewBuild(
            folderPath: record.folderPath,
            courseCode: record.courseCode,
            sectionNumber: record.sectionNumber
        )
        recorded = record
        isWaiting = true
    }

    /// The wait is over, however it ended — the page answered, the run ended,
    /// it was stopped, or the outer time limit ran out. Safe to call when
    /// nothing is waiting, and twice.
    func end() {
        isWaiting = false
        guard let record = recorded else {
            return
        }
        CourseActivity.endPreviewBuild(
            folderPath: record.folderPath,
            courseCode: record.courseCode,
            sectionNumber: record.sectionNumber
        )
        recorded = nil
    }
}
