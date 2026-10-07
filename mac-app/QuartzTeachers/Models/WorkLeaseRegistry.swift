import Foundation

/// This process's own work leases, DERIVED from what it is doing rather than
/// taken at each place that starts something (#156).
///
/// Every build this app runs already passes through `CourseActivity` (a
/// preview's build, a deploy, the assistant's rebuild and deploy with no
/// window) and every preview through `PreviewLeases`. So rather than a second
/// set of calls at every one of those places — one of which would be
/// forgotten — both of them end each change with `reconcile()`, which works
/// out the leases this process SHOULD hold on disk and writes or removes the
/// difference:
///
/// | kind | held while… |
/// |---|---|
/// | `build` | any preview of the course is being built, or any section of it is publishing |
/// | `publish` | any section of the course is publishing |
/// | `preview` | any section of the course has a preview up |
///
/// One file per folder, course and kind: two sections of one course
/// previewing keep ONE `preview` lease, ending one keeps it, ending both
/// removes it. Windows' leases name the course and not the section (its
/// reader reads the kind from the third-last dot), so a build of Section 1
/// elsewhere declines Section 2 here too — accepted, and said in the sentence.
///
/// The publish set for later runs in a process of its own with no main actor
/// app, and takes its leases through `WorkLeaseFiles` directly
/// (`ScheduledDeploy.runScheduled`).
@MainActor
enum WorkLeaseRegistry {

    // MARK: - Types

    /// One lease this process should hold.
    struct Wanted: Hashable {

        // MARK: - Stored properties

        let folderPath: String
        let courseCode: String
        let kind: String

        // MARK: - Initializer

        /// The folder is kept in the disk's own spelling (#189), because this
        /// is a dictionary KEY: two spellings of one folder must be one key,
        /// or one course would get two lease files and `buildClaim` would
        /// miss this process's own claim.
        init(folderPath: String, courseCode: String, kind: String) {
            self.folderPath = FolderIdentity.canonicalPath(folderPath)
            self.courseCode = courseCode.uppercased()
            self.kind = kind
        }
    }

    /// A lease this process has written.
    struct Written: Equatable {
        let url: URL
        let moment: String
    }

    // MARK: - Stored properties

    /// What this process has on disk right now.
    private(set) static var written: [Wanted: Written] = [:]

    /// True once this process has begun to leave (the MCP server's client
    /// went away). From then on only `releaseEverything()` removes a lease:
    /// the runs being stopped end their own records as they go, and a
    /// reconcile at that moment would take the lease down while the build
    /// inside the website builder was still being stopped — the one window
    /// the lease exists to cover.
    static var isLeaving: Bool = false

    /// The `assist` lease `Plantoir --mcp-stdio` holds for the whole of its
    /// conversation on the course the Claude door named (#458) — nil in the
    /// app, and in a server started with no course or one this folder does
    /// not have.
    ///
    /// Kept HERE, and added to what `reconcile()` wants, because `reconcile`
    /// removes every written lease that is not wanted: a hold written beside
    /// the registry would be taken down by the first reconcile after the
    /// session's own preview or deploy ended — leaving the course unheld
    /// while the session was still open, which is the fault this exists to
    /// prevent.
    private(set) static var heldForTheConversation: Wanted?

    /// The held-backup records this process has written (#283, #458), each
    /// `<COURSE>.held-backup.<pid>` naming the backup its conversation made.
    /// Removed at exit by `forgetRecordedBackups()`, BEFORE the leases go.
    private(set) static var recordedBackups: [URL] = []

    /// The trail line for a preview the window declined because this copy of
    /// the app is deploying that same section (#381) — the contract's
    /// `activityTrail.mustRecord` → "build declined, course busy elsewhere" →
    /// `lineWhenItsSectionIsBeingDeployed`, pinned by PreviewWhileDeployingTests.
    static let lineWhenItsSectionIsBeingDeployed: String =
        "declined Preview — this section is being deployed by this copy of Plantoir"

    // MARK: - Functions

    /// Writes the leases this process should hold and removes the ones it no
    /// longer should.
    static func reconcile() {
        var wanted: [Wanted] = []
        for build in CourseActivity.activePreviewBuilds {
            wanted.append(Wanted(folderPath: build.folderPath, courseCode: build.courseCode, kind: WorkLeaseFiles.buildKind))
        }
        for publish in CourseActivity.activePublishes {
            wanted.append(Wanted(folderPath: publish.folderPath, courseCode: publish.courseCode, kind: WorkLeaseFiles.buildKind))
            wanted.append(Wanted(folderPath: publish.folderPath, courseCode: publish.courseCode, kind: WorkLeaseFiles.publishKind))
        }
        for lease in PreviewLeases.active {
            wanted.append(Wanted(folderPath: lease.folderPath, courseCode: lease.courseCode, kind: WorkLeaseFiles.previewKind))
        }
        if let heldForTheConversation {
            wanted.append(heldForTheConversation)
        }

        for item in wanted {
            if written[item] != nil {
                continue
            }
            let coursesDirectory: URL = URL(fileURLWithPath: item.folderPath)
                .appendingPathComponent("courses", isDirectory: true)
            if let made = WorkLeaseFiles.write(
                kind: item.kind, courseCode: item.courseCode, coursesDirectory: coursesDirectory
            ) {
                written[item] = Written(url: made.url, moment: made.moment)
            }
        }

        if isLeaving {
            return
        }
        var stillWritten: [Wanted: Written] = [:]
        for (item, lease) in written {
            if wanted.contains(item) {
                stillWritten[item] = lease
            } else {
                WorkLeaseFiles.remove(at: lease.url)
            }
        }
        written = stillWritten
    }

    /// Removes every lease this process wrote — at quit, and when the MCP
    /// server's client goes away (after its own runs have been stopped).
    static func releaseEverything() {
        for (_, lease) in written {
            WorkLeaseFiles.remove(at: lease.url)
        }
        written = [:]
        heldForTheConversation = nil
    }

    /// Holds an `assist` lease on one course for as long as this process
    /// serves its conversation (#458) — Windows' `plantoir-mcp` does the same
    /// for the course `PLANTOIR_DOOR_COURSE` names. Written at once, and kept
    /// by every reconcile until `releaseEverything()`.
    static func holdForTheConversation(folderPath: String, courseCode: String) {
        heldForTheConversation = Wanted(
            folderPath: folderPath, courseCode: courseCode, kind: WorkLeaseFiles.assistKind
        )
        reconcile()
    }

    /// Whether this process has its conversation's `assist` lease on disk.
    static var holdsACourseForTheConversation: Bool {
        guard let heldForTheConversation else {
            return false
        }
        return written[heldForTheConversation] != nil
    }

    /// Writes (or replaces) this process's held-backup record for a course:
    /// one line, the backup's full path (Windows' format). Best-effort, as a
    /// lease is: a record that cannot be written holds nothing, and the
    /// conversation goes on.
    ///
    /// Only when `courses/` already exists, for the reason `WorkLeaseFiles
    /// .write` gives.
    static func recordConversationBackup(folderPath: String, courseCode: String, backupURL: URL) {
        let coursesDirectory: URL = URL(fileURLWithPath: folderPath)
            .appendingPathComponent("courses", isDirectory: true)
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: coursesDirectory.path, isDirectory: &isDirectory)
            || !isDirectory.boolValue {
            return
        }
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesDirectory)
        let record: URL = directory.appendingPathComponent(
            WorkLeaseFiles.heldBackupRecordName(courseCode: courseCode, pid: getpid())
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(backupURL.standardizedFileURL.path.utf8).write(to: record, options: .atomic)
        } catch {
            return
        }
        if !recordedBackups.contains(record) {
            recordedBackups.append(record)
        }
    }

    /// Removes every held-backup record this process wrote — at exit, after
    /// its own runs have stopped and BEFORE its leases go (Windows' order),
    /// so no reader ever sees a record outlive the session that made it.
    static func forgetRecordedBackups() {
        for record in recordedBackups {
            try? FileManager.default.removeItem(at: record)
        }
        recordedBackups = []
    }

    /// This process's claim on a course's build — the moment of its own
    /// `build` lease — or nil when it has not written one.
    static func buildClaim(folderPath: String, courseCode: String) -> WorkLeaseFiles.Claim? {
        let key: Wanted = Wanted(folderPath: folderPath, courseCode: courseCode, kind: WorkLeaseFiles.buildKind)
        guard let lease = written[key] else {
            return nil
        }
        return WorkLeaseFiles.Claim(moment: lease.moment, pid: getpid())
    }

    /// What, held by another live process, stands in the way of a build of
    /// this course from here — or nil when the way is clear.
    ///
    /// `afterTaking` false is the EARLY look, made before anything is stopped
    /// or started, when every blocking lease counts. `afterTaking` true is
    /// the look made immediately after this process's own `build` lease was
    /// written, with nothing awaited in between: then only leases taken
    /// before that one count (`WorkLeaseFiles.blocking`), which is what keeps
    /// two processes that look at once from both backing off.
    static func whatBlocksABuild(
        folderPath: String,
        courseCode: String,
        afterTaking: Bool,
        asker: WorkLeaseFiles.Asker = .aBuild
    ) -> WorkLeaseFiles.Holding? {
        let coursesDirectory: URL = URL(fileURLWithPath: folderPath)
            .appendingPathComponent("courses", isDirectory: true)
        let holdings: [WorkLeaseFiles.Holding] = WorkLeaseFiles.heldElsewhere(
            courseCode: courseCode, coursesDirectory: coursesDirectory
        )
        var claim: WorkLeaseFiles.Claim? = nil
        if afterTaking {
            claim = buildClaim(folderPath: folderPath, courseCode: courseCode)
        }
        return WorkLeaseFiles.blocking(among: holdings, asker: asker, claim: claim)
    }

    /// What an outside assistant's change to this course meets in the other
    /// programs' leases (#433) — `WorkLeaseFiles.whatAnOutsideChangeMeets`
    /// over the leases on disk.
    static func whatAnOutsideChangeMeets(folderPath: String, courseCode: String) -> WorkLeaseFiles.OutsideChangeMeets {
        let coursesDirectory: URL = URL(fileURLWithPath: folderPath)
            .appendingPathComponent("courses", isDirectory: true)
        let holdings: [WorkLeaseFiles.Holding] = WorkLeaseFiles.heldElsewhere(
            courseCode: courseCode, coursesDirectory: coursesDirectory
        )
        return WorkLeaseFiles.whatAnOutsideChangeMeets(among: holdings)
    }

    /// Whether ANOTHER live program holds a `build` or `publish` lease on the
    /// course — a deploy or a preview build elsewhere; never this process's
    /// own leases, and never a preview that is only being served. What the
    /// section window asks when its serving preview ends (#433's stack review).
    static func anotherProgramIsBuilding(folderPath: String, courseCode: String) -> Bool {
        if case .building = whatAnOutsideChangeMeets(folderPath: folderPath, courseCode: courseCode) {
            return true
        }
        return false
    }

    /// Records a publish of one section and, with nothing awaited in
    /// between, looks at the other programs' leases — take, then check.
    ///
    /// Returns what stands in the way, having already taken the publish back
    /// off the books; or nil, when the publish is recorded, its `build` and
    /// `publish` leases are on disk, and the caller owns ending it
    /// (`CourseActivity.endPublish`). The window's Deploy calls this BEFORE
    /// it stops the teacher's preview, so its `build` lease is up for the
    /// whole of that stop (#156's review, M1).
    static func claimAPublish(
        folderPath: String,
        courseCode: String,
        sectionNumber: Int
    ) -> WorkLeaseFiles.Holding? {
        CourseActivity.beginPublish(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
        if let holding = whatBlocksABuild(folderPath: folderPath, courseCode: courseCode, afterTaking: true) {
            CourseActivity.endPublish(folderPath: folderPath, courseCode: courseCode, sectionNumber: sectionNumber)
            return holding
        }
        return nil
    }

    /// Puts a declined build on the trail.
    ///
    /// `act` is what was asked for, in a teacher's words — "Preview",
    /// "Deploy", "the assistant's rebuild", "an outside assistant's deploy".
    static func noteDeclined(
        act: String,
        courseCode: String,
        sectionNumber: Int,
        holding: WorkLeaseFiles.Holding
    ) {
        ActivityTrail.note(
            .buildDeclinedBusyElsewhere,
            "declined \(act) — the course is being \(WorkLeaseFiles.describe(holding)) somewhere else on this Mac",
            course: courseCode,
            section: sectionNumber
        )
    }

    /// Puts a preview declined for its own section's deploy on the trail
    /// (#381). Filed under the same event as a decline for another program's
    /// lease: to a teacher's report both are "Preview said something else was
    /// using it", and one name for one fact keeps a report searchable.
    static func noteDeclinedWhileItsSectionDeploys(courseCode: String, sectionNumber: Int) {
        ActivityTrail.note(
            .buildDeclinedBusyElsewhere,
            lineWhenItsSectionIsBeingDeployed,
            course: courseCode,
            section: sectionNumber
        )
    }

    /// "the assistant's deploy" in the app, "an outside assistant's deploy"
    /// in the process an assistant working from another app talks to — the
    /// same code runs in both, and the trail has to say which it was.
    static func assistantsAct(_ verb: String) -> String {
        if AssistMCPServer.isServing {
            return "an outside assistant's \(verb)"
        }
        return "the assistant's \(verb)"
    }

    /// Starts from nothing — for tests. Removes whatever was written.
    static func reset() {
        isLeaving = false
        forgetRecordedBackups()
        releaseEverything()
    }
}
