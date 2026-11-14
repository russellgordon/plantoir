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

    /// One start's hold on a section's preview-build record (#812).
    ///
    /// Several things can say the same section is being built at once: the
    /// window whose start is waiting for a stop, another window on the same
    /// section whose press is about to be refused, and the assistant's own
    /// rebuild with no window. Each holds its own claim and ends only that
    /// claim, so the one that ends first never takes the record away from
    /// one still building. A section is being built while ANY claim on it
    /// is held. This is the shape the Windows app has had from the start
    /// (`CourseActivity.BeginPreviewBuild` there returns one token per start).
    struct PreviewBuildClaim: Equatable {
        let record: PreviewBuildRecord
        let owner: UUID
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

    /// What a run of the unit plans' launcher is doing (#863): sharing,
    /// changing the plans' password, or stopping sharing. All three hold the
    /// same lease, a publish under `PlanSharing.leaseSection`, so the quit
    /// question reads this to name the one that is under way.
    enum PlanWork: String, Equatable {
        case sharing
        case changingPassword
        case stopping

        // MARK: - Functions

        /// The work a choice on the Planning tab's share bar starts.
        static func of(_ choice: PlanSharing.Choice) -> PlanWork {
            switch choice {
            case .changePassword:
                return .changingPassword
            case .stop:
                return .stopping
            case .shareOpen, .shareProtected, .shareAgain, .removePassword, .addPassword:
                return .sharing
            }
        }
    }

    /// One course's unit plans being shared, re-passworded or stopped.
    struct PlanWorkRecord: Equatable {
        let folderPath: String
        let courseCode: String
        let work: PlanWork
    }

    /// The backing store is observable for the same reason as
    /// `PreviewLeases.Store`: views reading `courseIsBusy` must
    /// re-render the moment a publish begins or ends.
    @Observable
    final class Store {
        var activePublishes: [PublishRecord] = []
        /// Every claim on a preview-build record, one per start that holds
        /// one (#812). Read as `activePreviewBuilds`, the distinct records.
        var previewBuildClaims: [PreviewBuildClaim] = []
        var activeCopies: [CopyRecord] = []
        var activePlanWork: [PlanWorkRecord] = []
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
    ///
    /// One record per section however many claims it has (#812): one section
    /// being built is one fact to a teacher who asks to quit.
    static var activePreviewBuilds: [PreviewBuildRecord] {
        var records: [PreviewBuildRecord] = []
        for claim in store.previewBuildClaims {
            if !records.contains(claim.record) {
                records.append(claim.record)
            }
        }
        return records
    }

    /// The courses being zipped right now, across all windows (#351).
    static var activeCopies: [CopyRecord] {
        return store.activeCopies
    }

    /// What each run of the unit plans' launcher is doing (#863).
    static var activePlanWork: [PlanWorkRecord] {
        return store.activePlanWork
    }

    // MARK: - Functions

    /// Records what a run of the unit plans' launcher is doing, beside the
    /// lease it holds (#863).
    static func beginPlanWork(folderPath: String, courseCode: String, work: PlanWork) {
        store.activePlanWork.append(PlanWorkRecord(folderPath: folderPath, courseCode: courseCode, work: work))
    }

    /// Records that a run of the unit plans' launcher has ended.
    static func endPlanWork(folderPath: String, courseCode: String) {
        var remaining: [PlanWorkRecord] = []
        var didRemoveOne: Bool = false
        for existing in activePlanWork {
            if existing.folderPath == folderPath && existing.courseCode == courseCode && !didRemoveOne {
                didRemoveOne = true
                continue
            }
            remaining.append(existing)
        }
        store.activePlanWork = remaining
    }

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

    /// Records that a preview of one section has started building, and
    /// returns this start's own claim on the record (#812): end it with
    /// `endPreviewBuild(_:)`, which leaves every other claim alone.
    ///
    /// Every start that can be refused, or can outlive another start of the
    /// same section, takes a claim: a section window's wait
    /// (`PreviewBuildWait`) and the assistant's rebuild with no window
    /// (`AssistSiteWork.rebuildPreview`).
    static func beginPreviewBuildClaim(folderPath: String, courseCode: String, sectionNumber: Int) -> PreviewBuildClaim {
        let claim: PreviewBuildClaim = PreviewBuildClaim(
            record: PreviewBuildRecord(
                folderPath: folderPath,
                courseCode: courseCode,
                sectionNumber: sectionNumber
            ),
            owner: UUID()
        )
        store.previewBuildClaims.append(claim)
        WorkLeaseRegistry.reconcile()
        return claim
    }

    /// Ends one start's claim, however that start ended. Safe to call twice,
    /// and when the claim has already gone: ending a claim that is not held
    /// changes nothing.
    static func endPreviewBuild(_ claim: PreviewBuildClaim) {
        var remaining: [PreviewBuildClaim] = []
        var found: Bool = false
        for existing in store.previewBuildClaims {
            if existing == claim {
                found = true
            } else {
                remaining.append(existing)
            }
        }
        if !found {
            return
        }
        store.previewBuildClaims = remaining
        WorkLeaseRegistry.reconcile()
    }

    /// Records that a preview of one section has started building, with a
    /// claim nobody keeps.
    ///
    /// Recording the same section twice keeps ONE record. For tests and for
    /// a caller that ends the section's build as a whole; product code that
    /// can be refused, or outlive another start, uses
    /// `beginPreviewBuildClaim` instead (#812).
    static func beginPreviewBuild(folderPath: String, courseCode: String, sectionNumber: Int) {
        _ = beginPreviewBuildClaim(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
    }

    /// Records that a section's preview is no longer being built by ANYONE:
    /// every claim on it is ended. Safe to call when nothing was recorded,
    /// or twice.
    ///
    /// **Not for a start ending.** This used to be the only way to end a
    /// record, and a start that was refused (a second press, or a press in
    /// another window) ended the record of the start that was still
    /// building, so ⌘Q quit through that build without asking (#812). A
    /// start ends its own claim with `endPreviewBuild(_:)`.
    static func endPreviewBuild(folderPath: String, courseCode: String, sectionNumber: Int) {
        let finished: PreviewBuildRecord = PreviewBuildRecord(
            folderPath: folderPath,
            courseCode: courseCode,
            sectionNumber: sectionNumber
        )
        var remaining: [PreviewBuildClaim] = []
        for existing in store.previewBuildClaims {
            if existing.record != finished {
                remaining.append(existing)
            }
        }
        store.previewBuildClaims = remaining
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

    /// True while THIS section is being deployed by this copy of the app —
    /// from any window, or by the assistant with no window (GitHub #381).
    ///
    /// Asked by the one function every preview a window starts goes through
    /// (`SectionDetailView.startPreview`), because a preview of a section
    /// must not start while that same section deploys. The section, not the
    /// course: previewing section 1 while section 2 deploys from the same
    /// app works, and Russell's rule names the same section. Other programs
    /// are refused through their work leases, and a deploy typed at a
    /// command line by `preview.sh` itself —
    /// `shared-rules.json` → `previewWhileItsSectionDeploys`.
    static func sectionPublishIsRunning(folderPath: String, courseCode: String, sectionNumber: Int) -> Bool {
        for publish in activePublishes {
            if publish.courseCode == courseCode
                && publish.sectionNumber == sectionNumber
                && FolderIdentity.isSameFolder(publish.folderPath, folderPath) {
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

    // MARK: - A Claude, Codex or GitHub Copilot session holding the course (#458)

    /// Which Revise item is asking (`reviseUnavailableReason`).
    enum ReviseItem: Equatable {
        case claude
        case codex
        case copilot
        case localAssistant
    }

    /// The Revise item an outside door's button stands for, so Fix with and
    /// Plan a Unit make the same click-time check as Revise With ▸.
    static func reviseItem(for assistant: FixWithAssistant.Assistant) -> ReviseItem {
        switch assistant {
        case .claude:
            return .claude
        case .codex:
            return .codex
        case .copilot:
            return .copilot
        }
    }

    /// What a teacher is told when an outside door did not open.
    static func couldNotStartSentence(for assistant: FixWithAssistant.Assistant, courseCode: String) -> String {
        switch assistant {
        case .claude:
            return ClaudeCodeLauncher.couldNotStartSentence(courseCode: courseCode)
        case .codex:
            return CodexLauncher.couldNotStartSentence(courseCode: courseCode)
        case .copilot:
            return CopilotLauncher.couldNotStartSentence(courseCode: courseCode)
        }
    }

    /// True while ANOTHER live program holds an `assist` lease on this course
    /// — on the mac, a Claude, Codex or GitHub Copilot session opened from Plantoir, through its
    /// `Plantoir --mcp-stdio` (#458); on a folder Windows also opens,
    /// `plantoir-mcp`. Read from disk, because that program has a memory of
    /// its own. This process's own lease never counts (`heldElsewhere`), and
    /// neither does one whose owner has gone.
    static func isRevisedElsewhere(folderPath: String, courseCode: String) -> Bool {
        return revisingAssistant(folderPath: folderPath, courseCode: courseCode) != nil
    }

    /// Who is revising this course elsewhere, as the busy sentences' slot
    /// says it (#783): the assistant each live `assist` lease on the course
    /// records (`WorkLeaseFiles.Holding.assistant`), through
    /// `AssistWording.outsideAssistantNamed`, so a hold that names none
    /// gives all three. Nil when nothing holds the course.
    static func revisingAssistant(folderPath: String, courseCode: String) -> String? {
        let coursesDirectory: URL = URL(fileURLWithPath: folderPath)
            .appendingPathComponent("courses", isDirectory: true)
        let holdings: [WorkLeaseFiles.Holding] = WorkLeaseFiles.heldElsewhere(
            courseCode: courseCode, coursesDirectory: coursesDirectory
        )
        var keys: [String?] = []
        for holding in holdings where holding.kind.lowercased() == WorkLeaseFiles.assistKind {
            keys.append(holding.assistant)
        }
        if keys.isEmpty {
            return nil
        }
        return AssistWording.outsideAssistantNamed(keys)
    }

    /// The short line naming what stands in the way of STRUCTURAL work on a
    /// course — Rename Course, Add Section…, restoring a backup — or nil when
    /// it is free: `busyDescription`, and then a Claude, Codex or GitHub Copilot session open on the
    /// course elsewhere (#458; Windows' `BusyReason`, which includes it).
    ///
    /// **Separate from `busyDescription` on purpose.** That one is also the
    /// question a BUILD asks (`AssistSiteWork`), and an `assist` lease never
    /// declines a build (`workLeases.declining`) — a teacher previewing while
    /// Claude revises is the intended way to use both. Removing a course or a
    /// section, and the unit-word rename, are NOT held either: Windows holds
    /// neither (#458's ruling 2), so they stay on `busyDescription`.
    ///
    /// `revisedElsewhere` is the answer already read, for a menu drawn from
    /// a window's snapshot (`WorkspaceModel.coursesRevisedElsewhere`), with
    /// `revisingAssistant` the snapshot's name for who (nil lists all three);
    /// nil reads the disk now, which is what every click-time check does.
    static func structuralHoldReason(
        folderPath: String,
        courseCode: String,
        revisedElsewhere: Bool? = nil,
        revisingAssistant: String? = nil
    ) -> String? {
        if let busy = busyDescription(folderPath: folderPath, courseCode: courseCode) {
            return busy
        }
        if let revisedElsewhere {
            if revisedElsewhere {
                return AssistWording.availableOnceYouFinishRevising(
                    with: revisingAssistant ?? AssistWording.anyOutsideAssistant
                )
            }
            return nil
        }
        if let named = CourseActivity.revisingAssistant(folderPath: folderPath, courseCode: courseCode) {
            return AssistWording.availableOnceYouFinishRevising(with: named)
        }
        return nil
    }

    /// Why a Revise item cannot be used on this course right now, in the
    /// words that go under it — or nil when it can (#458).
    ///
    /// Two causes, each said as itself (ruling 7):
    /// - a Claude, Codex or GitHub Copilot session open on the course elsewhere greys EVERY Revise item
    ///   (Windows' `CanReviseNow`): a second session on one course would
    ///   have two conversations writing the same pages;
    /// - the in-app assistant open on this course greys the outside DOORS, with
    ///   the sentence that names the window to close — the same symmetry
    ///   Windows gets from its window taking the lease too. The local item
    ///   keeps its own one-window rule (`AssistActivity.reasonItIsUnavailable`).
    static func reviseUnavailableReason(
        item: ReviseItem,
        folderPath: String,
        courseCode: String,
        sectionNumber: Int?,
        revisedElsewhere: Bool,
        revisingAssistant: String? = nil,
        active: AssistActivity.Session?
    ) -> String? {
        if revisedElsewhere {
            return AssistWording.availableOnceYouFinishRevising(
                with: revisingAssistant ?? AssistWording.anyOutsideAssistant
            )
        }
        guard let active else {
            return nil
        }
        switch item {
        case .claude, .codex, .copilot:
            if active.courseCode.lowercased() == courseCode.lowercased()
                && FolderIdentity.isSameFolder(active.folderPath, folderPath) {
                return AssistActivity.closeTheAssistantFirst(active)
            }
            return nil
        case .localAssistant:
            guard let sectionNumber else {
                return nil
            }
            let asked: AssistActivity.Session = AssistActivity.Session(
                folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber
            )
            if asked == active {
                return nil
            }
            return AssistActivity.closeTheAssistantFirst(active)
        }
    }

    /// Starts from nothing — for tests.
    static func reset() {
        store.activePublishes = []
        store.previewBuildClaims = []
        store.activeCopies = []
        store.activePlanWork = []
        WorkLeaseRegistry.reconcile()
    }
}
