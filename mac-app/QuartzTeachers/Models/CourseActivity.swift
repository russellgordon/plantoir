import Foundation
import Observation

/// Which courses are doing something right now, across every window:
/// previewing (known via `PreviewLeases`) or publishing (recorded here).
/// Previews still being BUILT are recorded here too, for the one question
/// that has to tell a build from a preview that is merely open — ⌘Q.
///
/// Every change here ends by asking `WorkLeaseRegistry` to bring this
/// process's lease FILES into line (#156), so another process — an assistant
/// working from another app, a publish set for later, another copy of
/// Plantoir — can see what this one is building. What is recorded here stays
/// in-process; the files are derived from it.
///
/// Re-running the course setup rewrites a course's folders and files, so
/// actions like "Add Section…" must decline while one of the course's
/// sections is previewing or publishing — the setup run and the build
/// could stomp on each other's files.
@MainActor
enum CourseActivity {

    // MARK: - Types

    struct PublishRecord: Equatable {
        let folderPath: String
        let courseCode: String
        let sectionNumber: Int
    }

    /// A preview of one section that is still being BUILT — from the press
    /// until its page first answers, or the run ends.
    ///
    /// Its own type rather than a second use of `PublishRecord`, whose shape
    /// is identical: a preview build filed under a name that says "publish"
    /// would be read as one by the next person to count them.
    struct PreviewBuildRecord: Equatable {
        let folderPath: String
        let courseCode: String
        let sectionNumber: Int
    }

    /// A course whose folder is being ZIPPED — a backup, or the archive made
    /// before a restore or a removal (#351). Recorded because the zip runs
    /// off the main actor now: the window stays live for the minute it can
    /// take, and nothing must change the course under it — no second Back
    /// Up, Restore or Remove of the same course, no preview started, and ⌘Q
    /// asks first.
    struct CopyRecord: Equatable {
        let folderPath: String
        let courseCode: String
        /// The name a teacher reads (`Course.displayCode`) — the quit
        /// question says it; `courseCode` is the folder's.
        let displayCode: String
    }

    /// The backing store is observable for the same reason as
    /// `PreviewLeases.Store`: views reading `courseIsBusy` must
    /// re-render the moment a publish begins or ends.
    @Observable
    final class Store {
        var activePublishes: [PublishRecord] = []
        var activePreviewBuilds: [PreviewBuildRecord] = []
        var activeCopies: [CopyRecord] = []
    }

    // MARK: - Stored properties

    static let store: Store = Store()

    // MARK: - Computed properties

    /// The publishes currently running, across all windows.
    static var activePublishes: [PublishRecord] {
        return store.activePublishes
    }

    /// The previews still being built, across all windows and the
    /// assistant's own rebuilds (issue #232).
    ///
    /// Read by nothing but the quit question. `busyDescription`,
    /// `courseIsBusy` and `coursePublishIsRunning` deliberately do not look
    /// here: a preview already counts for those through its lease, and a
    /// menu item greyed out "until preview completed" is about the lease.
    static var activePreviewBuilds: [PreviewBuildRecord] {
        return store.activePreviewBuilds
    }

    /// The courses being zipped right now, across all windows (#351).
    static var activeCopies: [CopyRecord] {
        return store.activeCopies
    }

    // MARK: - Functions

    /// Records that a course's folder has started being zipped (#351). One
    /// record per zip, so two at once of one course end one at a time.
    static func beginCopy(folderPath: String, courseCode: String, displayCode: String? = nil) {
        store.activeCopies.append(CopyRecord(
            folderPath: folderPath, courseCode: courseCode, displayCode: displayCode ?? courseCode
        ))
    }

    /// Records that one zip of a course has finished, however it finished.
    static func endCopy(folderPath: String, courseCode: String) {
        var remaining: [CopyRecord] = []
        var didRemoveOne: Bool = false
        for existing in activeCopies {
            if existing.folderPath == folderPath && existing.courseCode == courseCode && !didRemoveOne {
                didRemoveOne = true
                continue
            }
            remaining.append(existing)
        }
        store.activeCopies = remaining
    }

    /// True while a copy of the course is being zipped (#351).
    static func courseIsBeingCopied(folderPath: String, courseCode: String) -> Bool {
        for copy in activeCopies {
            if copy.courseCode == courseCode && FolderIdentity.isSameFolder(copy.folderPath, folderPath) {
                return true
            }
        }
        return false
    }

    /// Records that a publish of one section has begun.
    static func beginPublish(folderPath: String, courseCode: String, sectionNumber: Int) {
        let record: PublishRecord = PublishRecord(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        store.activePublishes.append(record)
        WorkLeaseRegistry.reconcile()
        // A deploy ends the start-of-the-year undo for this section (#96):
        // after it, students have the drafted state, and an undo would only
        // put pages back that the next deploy then publishes.
        StartOfYearUndoRegistry.shared.deployStarted(
            folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber
        )
    }

    /// Records that a publish has finished, however it finished.
    static func endPublish(folderPath: String, courseCode: String, sectionNumber: Int) {
        let finished: PublishRecord = PublishRecord(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        var remaining: [PublishRecord] = []
        var didRemoveOne: Bool = false
        for existing in activePublishes {
            if existing == finished && !didRemoveOne {
                didRemoveOne = true
                continue
            }
            remaining.append(existing)
        }
        store.activePublishes = remaining
        WorkLeaseRegistry.reconcile()
    }

    /// Records that a preview of one section has started building.
    ///
    /// Recording the same section twice keeps ONE record. A section has at
    /// most one preview per folder (its lease sees to that), and the one
    /// other thing that builds it — the assistant's rebuild with no window —
    /// is the same fact to a teacher who asks to quit: that section's preview
    /// is being built.
    static func beginPreviewBuild(folderPath: String, courseCode: String, sectionNumber: Int) {
        let record: PreviewBuildRecord = PreviewBuildRecord(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        for existing in activePreviewBuilds {
            if existing == record {
                return
            }
        }
        store.activePreviewBuilds.append(record)
        WorkLeaseRegistry.reconcile()
    }

    /// Records that a section's preview is no longer being built, however it
    /// ended — and is safe to call when nothing was recorded, or twice.
    ///
    /// **Idempotent on purpose, unlike `endPublish`.** It is called from more
    /// than one ending of the same build (the view's own change of state, its
    /// disappearance, and the lease being handed back), because SwiftUI does
    /// not reliably deliver a change to a view that is being torn down — and a
    /// record that outlives its build makes EVERY later ⌘Q ask about a
    /// preview that is not being built. Removing every match is what makes a
    /// second call harmless.
    static func endPreviewBuild(folderPath: String, courseCode: String, sectionNumber: Int) {
        let finished: PreviewBuildRecord = PreviewBuildRecord(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        var remaining: [PreviewBuildRecord] = []
        for existing in activePreviewBuilds {
            if existing != finished {
                remaining.append(existing)
            }
        }
        store.activePreviewBuilds = remaining
        WorkLeaseRegistry.reconcile()
    }

    /// True while any section of the course is PUBLISHING — previews do not
    /// count.
    ///
    /// `courseIsBusy` answers "previewing or publishing", which is right for
    /// disabling a menu item and wrong for anything that needs to know whether
    /// somebody is publishing. Asking the wrong one of these made the repair
    /// dialog's "Preview Again" refuse whenever a preview was running, which is
    /// every time it is offered.
    static func coursePublishIsRunning(folderPath: String, courseCode: String) -> Bool {
        for publish in activePublishes {
            // One folder however it is spelled (#189); the code is asked first
            // because it is the cheaper question.
            if publish.courseCode == courseCode && FolderIdentity.isSameFolder(publish.folderPath, folderPath) {
                return true
            }
        }
        return false
    }

    /// True while any section of the course is previewing or publishing, or
    /// a copy of the course is being zipped (#351).
    static func courseIsBusy(folderPath: String, courseCode: String) -> Bool {
        return busyDescription(folderPath: folderPath, courseCode: courseCode) != nil
    }

    /// A short reason the course is busy — naming whichever activity is
    /// in the way — or nil when it isn't. Menu-length on purpose: it
    /// sits under a disabled menu item.
    /// The menu-length reason while only a deploy is in the way — also said
    /// under "Get Ready for the Start of the Year…" (#96), so it is written once.
    static let availableOnceDeployCompleted: String = "Available once deploy completed"

    /// The menu-length reason while a copy of the course is being zipped
    /// (#351) — a backup, or the archive before a restore or a removal.
    static let availableOnceTheCopyIsSaved: String = "Available once the copy is saved"

    static func busyDescription(folderPath: String, courseCode: String) -> String? {
        // A copy being zipped makes the course busy for EVERY reader (#351's
        // second review, SF1): the assistant's preview and deploy, the
        // Deploy button, a removal, the assistant's rebuild with no window,
        // the unit-word rename. Named first: it is the shortest wait, and
        // the one a restore or removal is waiting on.
        if courseIsBeingCopied(folderPath: folderPath, courseCode: courseCode) {
            return availableOnceTheCopyIsSaved
        }
        var isPreviewing: Bool = false
        for lease in PreviewLeases.active {
            if lease.courseCode == courseCode && FolderIdentity.isSameFolder(lease.folderPath, folderPath) {
                isPreviewing = true
            }
        }
        let isPublishing: Bool = coursePublishIsRunning(
            folderPath: folderPath, courseCode: courseCode
        )
        if isPreviewing && isPublishing {
            return "Available once preview and deploy completed"
        }
        if isPreviewing {
            return "Available once preview completed"
        }
        if isPublishing {
            return availableOnceDeployCompleted
        }
        return nil
    }

    /// Starts from nothing — for tests.
    static func reset() {
        store.activePublishes = []
        store.activePreviewBuilds = []
        store.activeCopies = []
        WorkLeaseRegistry.reconcile()
    }
}
