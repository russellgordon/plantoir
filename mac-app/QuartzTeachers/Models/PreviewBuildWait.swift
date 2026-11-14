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

    /// The claim this wait holds on `CourseActivity`'s record, while it has
    /// one.
    ///
    /// Kept rather than rebuilt from the window's folder at the end, because
    /// the window's note of its folder is also written by a deploy: by the
    /// time the wait ends it could name another folder, and ending the wrong
    /// record leaves the right one behind for ever. A CLAIM since #812, not
    /// the record: ending it leaves another window's start, or the
    /// assistant's rebuild, still recorded.
    private(set) var claim: CourseActivity.PreviewBuildClaim?

    // MARK: - Computed properties

    /// The record this wait put in `CourseActivity`, while it has one.
    var recorded: CourseActivity.PreviewBuildRecord? {
        return claim?.record
    }

    // MARK: - Functions

    /// The wait begins, and ⌘Q is told a preview of this section is being
    /// built. A wait already under way is ended first, so a second press can
    /// never leave the first record behind. (A second press while this
    /// window's own start is still under way never reaches here:
    /// `PreviewStartRecords.begin` answers `.alreadyStarting` first, #812.)
    func begin(folderPath: String, courseCode: String, sectionNumber: Int) {
        end()
        claim = CourseActivity.beginPreviewBuildClaim(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        isWaiting = true
    }

    /// The wait is over, however it ended — the page answered, the run ended,
    /// it was stopped, or the outer time limit ran out. Safe to call when
    /// nothing is waiting, and twice. Ends this wait's own claim and nobody
    /// else's (#812).
    func end() {
        isWaiting = false
        guard let held = claim else {
            return
        }
        CourseActivity.endPreviewBuild(held)
        claim = nil
    }
}
