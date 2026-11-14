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
/// | `assist` | `Plantoir --mcp-stdio` only: the course the Claude door named, for the whole conversation (#458) |
///
/// One file per folder, course and kind: two sections of one course
/// previewing keep ONE `preview` lease, ending one keeps it, ending both
/// removes it. Since #835 the file's sixth line names the sections it holds,
/// each with the moment it was taken, so another copy of Plantoir or an
/// outside assistant can build a SIBLING section while this one is busy.
/// Adding a section keeps the moments already there (and line 3, which a
/// reader that knows no sections compares); only the new section's entry is
/// stamped now. Course-wide work (plan sharing, under
/// `PlanSharing.leaseSection`) writes no sixth line, so its lease holds every
/// section. Windows' leases name no sections, so a build of Section 1 there
/// still declines Section 2 here — accepted, and said in the sentence.
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

    /// What one of this process's lease files should say (#835): the
    /// sections it holds, a preview's container port for each, and whether
    /// any of the work on it is course-wide.
    struct Hold: Equatable {

        // MARK: - Stored properties

        var courseWide: Bool = false
        var sections: [Int] = []
        var ports: [Int: Int] = [:]
    }

    /// A lease this process has written.
    struct Written: Equatable {

        // MARK: - Stored properties

        let url: URL

        /// Line 3: when the file was first written. Kept on every rewrite,
        /// because a reader that knows no sections compares it.
        let moment: String

        /// The same moment as a date, to write line 3 again unchanged.
        let takenAt: Date

        /// Every section this process holds the kind for, each with the
        /// moment it was TAKEN, kept in memory even while the file is
        /// course-wide, because each section's claim is its own moment.
        var entries: [WorkLeaseFiles.SectionEntry] = []

        /// When course-wide work on this kind began, or nil while there is
        /// none. The claim of a course-wide question.
        var courseWideSince: String? = nil

        // MARK: - Computed properties

        /// The sixth line's entries as the file carries them: none while any
        /// work is course-wide, which makes the lease hold the whole course.
        var sectionsOnDisk: [WorkLeaseFiles.SectionEntry]? {
            if courseWideSince != nil || entries.isEmpty {
                return nil
            }
            return entries
        }
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

    /// The door key the conversation's hold records as its lease's fifth
    /// line (#783), set and cleared with `heldForTheConversation`, so the
    /// other programs' sentences name the assistant. Nil names none.
    private(set) static var heldForTheConversationAssistant: String?

    /// The held-backup records this process has written (#283, #458), each
    /// `<COURSE>.held-backup.<pid>` naming the backup its conversation made.
    /// Removed at exit by `forgetRecordedBackups()`, BEFORE the leases go.
    private(set) static var recordedBackups: [URL] = []

    /// For tests only: when not nil, the name of every lease and record this
    /// process removes is appended, in order — the one way to see that a
    /// leaving server forgets its records BEFORE its leases go (#458).
    static var removalsSeenByTests: [String]?

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
        var wanted: [Wanted: Hold] = [:]
        for build in CourseActivity.activePreviewBuilds {
            let key: Wanted = Wanted(folderPath: build.folderPath, courseCode: build.courseCode, kind: WorkLeaseFiles.buildKind)
            wanted[key] = adding(section: build.sectionNumber, port: nil, to: wanted[key])
        }
        for publish in CourseActivity.activePublishes {
            let build: Wanted = Wanted(folderPath: publish.folderPath, courseCode: publish.courseCode, kind: WorkLeaseFiles.buildKind)
            wanted[build] = adding(section: publish.sectionNumber, port: nil, to: wanted[build])
            let kind: Wanted = Wanted(folderPath: publish.folderPath, courseCode: publish.courseCode, kind: WorkLeaseFiles.publishKind)
            wanted[kind] = adding(section: publish.sectionNumber, port: nil, to: wanted[kind])
        }
        for lease in PreviewLeases.active {
            let key: Wanted = Wanted(folderPath: lease.folderPath, courseCode: lease.courseCode, kind: WorkLeaseFiles.previewKind)
            wanted[key] = adding(section: lease.sectionNumber, port: lease.port, to: wanted[key])
        }
        if let heldForTheConversation {
            var hold: Hold = wanted[heldForTheConversation] ?? Hold()
            hold.courseWide = true
            wanted[heldForTheConversation] = hold
        }

        for (item, hold) in wanted {
            let coursesDirectory: URL = URL(fileURLWithPath: item.folderPath)
                .appendingPathComponent("courses", isDirectory: true)
            var assistant: String? = nil
            if item == heldForTheConversation {
                assistant = heldForTheConversationAssistant
            }
            let now: Date = Date()
            let nowText: String = ProcessLiveness.leaseMomentText(now)
            let existing: Written? = written[item]
            // Leaving: nothing is let go before `releaseEverything()`, so no
            // entry is dropped and no course-wide hold narrowed.
            var heldSections: [Int] = hold.sections
            var ports: [Int: Int] = hold.ports
            if isLeaving, let existing {
                for kept in existing.entries where !heldSections.contains(kept.section) {
                    heldSections.append(kept.section)
                    if let port = kept.port {
                        ports[kept.section] = port
                    }
                }
            }
            var entries: [WorkLeaseFiles.SectionEntry] = []
            for section in heldSections.sorted() {
                var moment: String = nowText
                if let existing {
                    for kept in existing.entries where kept.section == section {
                        moment = kept.moment
                    }
                }
                entries.append(WorkLeaseFiles.SectionEntry(section: section, moment: moment, port: ports[section]))
            }
            var courseWideSince: String? = nil
            if hold.courseWide {
                courseWideSince = existing?.courseWideSince ?? nowText
            }
            if isLeaving, let existing, courseWideSince == nil {
                courseWideSince = existing.courseWideSince
            }

            guard let existing else {
                var sectionsToWrite: [WorkLeaseFiles.SectionEntry]? = nil
                if courseWideSince == nil && !entries.isEmpty {
                    sectionsToWrite = entries
                }
                if let file = WorkLeaseFiles.write(
                    kind: item.kind, courseCode: item.courseCode, coursesDirectory: coursesDirectory,
                    moment: now, assistant: assistant, sections: sectionsToWrite
                ) {
                    var recorded: Written = Written(url: file.url, moment: file.moment, takenAt: now)
                    recorded.entries = entries
                    recorded.courseWideSince = courseWideSince
                    written[item] = recorded
                }
                continue
            }
            var changed: Written = existing
            changed.entries = entries
            changed.courseWideSince = courseWideSince
            if changed == existing {
                continue
            }
            if changed.sectionsOnDisk == existing.sectionsOnDisk {
                // The file would say the same: only this process's claims move.
                written[item] = changed
                continue
            }
            // Rewritten with line 3 as it was. A rewrite that fails leaves
            // the record as it was too, so a section it did not add has no
            // claim, and its look after taking counts every lease.
            if WorkLeaseFiles.write(
                kind: item.kind, courseCode: item.courseCode, coursesDirectory: coursesDirectory,
                moment: existing.takenAt, assistant: assistant, sections: changed.sectionsOnDisk
            ) != nil {
                written[item] = changed
            }
        }

        if isLeaving {
            return
        }
        var stillWritten: [Wanted: Written] = [:]
        for (item, lease) in written {
            if wanted[item] != nil {
                stillWritten[item] = lease
            } else {
                WorkLeaseFiles.remove(at: lease.url)
            }
        }
        written = stillWritten
    }

    /// A hold with one more piece of work on it. A section of 0 or less is
    /// course-wide work (`PlanSharing.leaseSection`).
    static func adding(section: Int, port: Int?, to hold: Hold?) -> Hold {
        var result: Hold = hold ?? Hold()
        if section <= 0 {
            result.courseWide = true
            return result
        }
        if !result.sections.contains(section) {
            result.sections.append(section)
        }
        if let port {
            result.ports[section] = port
        }
        return result
    }

    /// Removes every lease this process wrote — at quit, and when the MCP
    /// server's client goes away (after its own runs have been stopped).
    static func releaseEverything() {
        for (_, lease) in written {
            WorkLeaseFiles.remove(at: lease.url)
            removalsSeenByTests?.append(lease.url.lastPathComponent)
        }
        written = [:]
        heldForTheConversation = nil
        heldForTheConversationAssistant = nil
    }

    /// Holds an `assist` lease on one course for as long as this process
    /// serves its conversation (#458) — Windows' `plantoir-mcp` does the same
    /// for the course `PLANTOIR_DOOR_COURSE` names. Written at once, and kept
    /// by every reconcile until `releaseEverything()`.
    static func holdForTheConversation(folderPath: String, courseCode: String, assistant: String? = nil) {
        heldForTheConversationAssistant = assistant
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
            removalsSeenByTests?.append(record.lastPathComponent)
        }
        recordedBackups = []
    }

    /// This process's claim on a course's build — the moment of its own
    /// `build` lease — or nil when it has not written one.
    ///
    /// Per section since #835: the moment THAT section was taken, which is
    /// later than line 3 when the section was added to a file already held.
    /// A course-wide question (`section` nil or 0) claims the moment
    /// course-wide work began. Nil when this process holds no such claim, and
    /// then its look counts every lease, the strictest reading.
    static func buildClaim(folderPath: String, courseCode: String, section: Int? = nil) -> WorkLeaseFiles.Claim? {
        let key: Wanted = Wanted(folderPath: folderPath, courseCode: courseCode, kind: WorkLeaseFiles.buildKind)
        guard let lease = written[key] else {
            return nil
        }
        guard let section, section > 0 else {
            guard let since = lease.courseWideSince else {
                return nil
            }
            return WorkLeaseFiles.Claim(moment: since, pid: getpid())
        }
        for entry in lease.entries where entry.section == section {
            return WorkLeaseFiles.Claim(moment: entry.moment, pid: getpid())
        }
        return nil
    }

    /// The sections this process's own lease of a kind names on disk, or nil
    /// when it names none (none written, or course-wide). For the tests.
    static func sectionsOnDisk(folderPath: String, courseCode: String, kind: String) -> [WorkLeaseFiles.SectionEntry]? {
        let key: Wanted = Wanted(folderPath: folderPath, courseCode: courseCode, kind: kind)
        return written[key]?.sectionsOnDisk
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
    ///
    /// `section` is the section the build is of (#835), or nil for
    /// course-wide work; nil is the default, so a caller that names none
    /// holds back for the whole course, the wider and safer reading.
    static func whatBlocksABuild(
        folderPath: String,
        courseCode: String,
        afterTaking: Bool,
        asker: WorkLeaseFiles.Asker = .aBuild,
        section: Int? = nil
    ) -> WorkLeaseFiles.Holding? {
        let coursesDirectory: URL = URL(fileURLWithPath: folderPath)
            .appendingPathComponent("courses", isDirectory: true)
        let holdings: [WorkLeaseFiles.Holding] = WorkLeaseFiles.heldElsewhere(
            courseCode: courseCode, coursesDirectory: coursesDirectory
        )
        let asked: Int? = WorkLeaseRegistry.sectionAsked(section)
        var claim: WorkLeaseFiles.Claim? = nil
        if afterTaking {
            claim = buildClaim(folderPath: folderPath, courseCode: courseCode, section: asked)
        }
        return WorkLeaseFiles.blocking(among: holdings, asker: asker, claim: claim, section: asked)
    }

    /// A section number as the lease rules ask it: nil (course-wide) for
    /// none, and for 0 or less, which is `PlanSharing.leaseSection`.
    nonisolated static func sectionAsked(_ section: Int?) -> Int? {
        guard let section, section > 0 else {
            return nil
        }
        return section
    }

    /// What an outside assistant's change to this course meets in the other
    /// programs' leases (#433) — `WorkLeaseFiles.whatAnOutsideChangeMeets`
    /// over the leases on disk.
    ///
    /// `section` nil (the default) asks for the whole course, which is what
    /// an outside assistant's page writes ask (#835).
    static func whatAnOutsideChangeMeets(
        folderPath: String, courseCode: String, section: Int? = nil
    ) -> WorkLeaseFiles.OutsideChangeMeets {
        let coursesDirectory: URL = URL(fileURLWithPath: folderPath)
            .appendingPathComponent("courses", isDirectory: true)
        let holdings: [WorkLeaseFiles.Holding] = WorkLeaseFiles.heldElsewhere(
            courseCode: courseCode, coursesDirectory: coursesDirectory
        )
        return WorkLeaseFiles.whatAnOutsideChangeMeets(among: holdings, section: sectionAsked(section))
    }

    /// Whether ANOTHER live program holds a `build` or `publish` lease on the
    /// course — a deploy or a preview build elsewhere; never this process's
    /// own leases, and never a preview that is only being served. What the
    /// section window asks when its serving preview ends (#433's stack review).
    ///
    /// `section`, since #835: a build of a SIBLING section elsewhere does not
    /// count, because it does not end this section's preview.
    static func anotherProgramIsBuilding(folderPath: String, courseCode: String, section: Int? = nil) -> Bool {
        if case .building = whatAnOutsideChangeMeets(folderPath: folderPath, courseCode: courseCode, section: section) {
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
        if let holding = whatBlocksABuild(
            folderPath: folderPath, courseCode: courseCode, afterTaking: true, section: sectionNumber
        ) {
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
            WorkLeaseRegistry.declinedLine(act: act, sectionNumber: sectionNumber, holding: holding),
            course: courseCode,
            section: sectionNumber
        )
    }

    /// The trail line for a decline: the section when the lease in the way
    /// named it (#835), the course when it named none.
    nonisolated static func declinedLine(act: String, sectionNumber: Int, holding: WorkLeaseFiles.Holding) -> String {
        var what: String = "the course"
        if sectionNumber > 0 && holding.entry(forSection: sectionNumber) != nil {
            what = "Section \(sectionNumber) of the course"
        }
        return "declined \(act) — \(what) is being \(WorkLeaseFiles.describe(holding)) somewhere else on this Mac"
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
