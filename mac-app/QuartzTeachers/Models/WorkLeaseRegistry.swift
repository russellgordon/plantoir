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
        afterTaking: Bool
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
        return WorkLeaseFiles.blocking(among: holdings, asker: .aBuild, claim: claim)
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
        releaseEverything()
    }
}
