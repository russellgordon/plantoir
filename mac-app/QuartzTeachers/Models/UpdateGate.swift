import Foundation

/// Whether a new version of Plantoir may be installed right now, and what to
/// tell the teacher when it may not (#204).
///
/// **The rule** is `contracts/shared-rules.json` → `appUpdates.mayNotInstallWhile`,
/// and its cases run against `workUnderWay(publishes:previewBuilds:previews:otherCopies:leases:)`.
/// Installing replaces the app's bundle and opens the new version, which
/// re-mirrors a changed toolchain into every working folder it reopens; a
/// build going on in one of those folders would then change what it is built
/// from half way through. So an install waits while:
///
/// 1. this app is publishing or BUILDING a preview — the quit question's own
///    facts (`QuitConfirmation`), and a preview that is merely open does not
///    count, for the quit question's reason (Russell, #204 Q2);
/// 2. a publish set for later is running from this same app;
/// 3. another program holds a `build` or `publish` lease (#156) in a working
///    folder named here — an open window's, or one a process of this app was
///    started for.
///
/// **How another process is seen: leases first, then a scan for what they
/// cannot show.** A lease says exactly what another process is building or
/// publishing, in which course, and is read in every folder named. The scan
/// of this app's own executable (`SameExecutableProcesses`) sees the two
/// things no lease shows — a scheduled publish still waiting for its course
/// (it takes its leases only once the course is free, after up to ten
/// minutes) and one set before v1.2.0 (which takes none) — and says which
/// folder an assistant working from another app has open, so its leases can
/// be read. An assistant working from another app that holds no lease is NOT
/// under way: it can stay connected for days, and only a lease says it is
/// working. The scheduled job's own file is not a signal at all: its run
/// deletes it in its first line.
@MainActor
enum UpdateGate {

    // MARK: - Types

    /// Another process of this app's own executable.
    struct OtherCopy: Equatable {

        // MARK: - Types

        enum Kind: String {
            /// `--run-scheduled-deploy`: a publish set for later, running.
            case scheduledPublish
            /// `--mcp-stdio`: an assistant working from another app.
            case assistantFromAnotherApp
            /// Anything else — another window of this copy cannot exist, so
            /// in practice a copy started by hand from a shell.
            case other
        }

        // MARK: - Stored properties

        let pid: Int32
        let kind: Kind

        /// The working folder it was started for, when its arguments say.
        let folderPath: String?

        /// The course and section a scheduled publish names — nil for a job
        /// set before v1.2.0, whose arguments carry neither.
        let courseCode: String?
        let sectionNumber: Int?
    }

    /// A lease another live process holds, and where it was found.
    struct LeaseSighting: Equatable {

        // MARK: - Stored properties

        let pid: Int32

        /// build, preview, publish, assist or import.
        let kind: String

        let courseCode: String
        let folderPath: String
    }

    /// Where an update stands, as far as quitting is concerned.
    enum PreparedUpdate: String {
        /// No update is prepared.
        case none
        /// Downloaded and ready; the teacher has not yet pressed Install.
        case readyToInstall
        /// The teacher pressed Install and this app is holding it back until
        /// work is done — the answer has NOT reached the installer yet.
        case heldForWork
        /// The installer's own last question ("may I relaunch now?") was
        /// answered "not yet", because work began in the instant between the
        /// teacher's Install and that question. The answer has gone.
        case postponedAtInstall
    }

    /// What a quit does to a prepared update (`appUpdates.atQuit`).
    enum QuitAction: String {
        case nothingToDo
        /// Tell the installer to stand down: the update is offered again at
        /// the next check.
        case setAside
        /// The installer installs as Plantoir quits, and does not open it again.
        case installsAsItQuits
    }

    /// Everything the gate reads, gathered at one moment.
    struct Facts {

        // MARK: - Stored properties

        let publishes: [CourseActivity.PublishRecord]
        let previewBuilds: [CourseActivity.PreviewBuildRecord]
        let previews: [PreviewLeases.Lease]
        let otherCopies: [OtherCopy]
        let leases: [LeaseSighting]
    }

    // MARK: - Stored properties

    /// The lease kinds that hold an install. Not `preview` (an open preview,
    /// Q2), and not `assist` or `import`, which never change what a build
    /// reads.
    static let leaseKindsThatHold: [String] = [
        WorkLeaseFiles.buildKind,
        WorkLeaseFiles.publishKind
    ]

    // MARK: - Functions

    /// What is under way right now, in the words the teacher is shown — or
    /// nil when an install may go ahead.
    static func workUnderWay() -> String? {
        return workUnderWay(facts: currentFacts())
    }

    /// The same, for facts already gathered.
    static func workUnderWay(facts: Facts) -> String? {
        return workUnderWay(
            publishes: facts.publishes,
            previewBuilds: facts.previewBuilds,
            previews: facts.previews,
            otherCopies: facts.otherCopies,
            leases: facts.leases
        )
    }

    /// The decision itself, with every fact handed in — what the contract's
    /// cases run.
    ///
    /// **What is named, when more than one thing is under way:** a publish
    /// before a preview, as in the quit question, because a publish is what
    /// reaches the class website — this app's own publishes, then a
    /// scheduled one, then this app's preview builds, then another program's
    /// build. The install waits for ALL of them either way; the name is only
    /// what the teacher is told.
    ///
    /// `previews` is taken and deliberately NOT used — the quit question's
    /// arrangement, so the choice that an open preview does not count lives
    /// inside the function the cases run.
    static func workUnderWay(
        publishes: [CourseActivity.PublishRecord],
        previewBuilds: [CourseActivity.PreviewBuildRecord],
        previews: [PreviewLeases.Lease],
        otherCopies: [OtherCopy],
        leases: [LeaseSighting]
    ) -> String? {
        if let ownPublish = QuitConfirmation.workUnderWay(publishes: publishes, previews: previews) {
            return ownPublish
        }

        var scheduledPublishes: [OtherCopy] = []
        for copy in otherCopies {
            if copy.kind == .scheduledPublish {
                scheduledPublishes.append(copy)
            }
        }

        // Leases first: another program's build or publish. A lease held by
        // a scheduled publish is named from that publish's own arguments,
        // because the lease names the course and not the section.
        var elsewhere: [String] = []
        for lease in leases {
            if !UpdateGate.leaseKindsThatHold.contains(lease.kind.lowercased()) {
                continue
            }
            if UpdateGate.copy(withPID: lease.pid, among: scheduledPublishes) != nil {
                continue
            }
            elsewhere.append(UpdateWording.elsewhereWork(course: lease.courseCode))
        }

        // A scheduled publish holds the install whether or not it has taken
        // its leases yet — waiting for its course, or a job from before
        // v1.2.0 that takes none. This is the part the scan exists for.
        if let first = scheduledPublishes.first {
            if let course = first.courseCode, let section = first.sectionNumber {
                return UpdateWording.scheduledWork(course: course, section: section)
            }
            return UpdateWording.scheduledWorkUnnamed
        }

        if let ownBuild = QuitConfirmation.workUnderWay(
            publishes: [], previews: previews, previewBuilds: previewBuilds
        ) {
            return ownBuild
        }

        return elsewhere.first
    }

    /// What quitting does to a prepared update (`appUpdates.atQuit.cases`).
    ///
    /// Quitting is never refused (decision 7 on #204). While the answer is
    /// still in this app's hands — `readyToInstall` or `heldForWork` — a quit
    /// with work under way sets the update aside; otherwise the installer,
    /// which installs on ANY quit once prepared, goes ahead.
    static func quitAction(prepared: PreparedUpdate, workUnderWay: Bool) -> QuitAction {
        switch prepared {
        case .none:
            return .nothingToDo
        case .readyToInstall, .heldForWork:
            if workUnderWay {
                return .setAside
            }
            return .installsAsItQuits
        case .postponedAtInstall:
            return .installsAsItQuits
        }
    }

    /// Reads another process's arguments into what the gate needs to know.
    static func classify(pid: Int32, arguments: [String]) -> OtherCopy {
        if ScheduledDeploy.requestedScript(from: arguments) != nil {
            let section = ScheduledDeploy.requestedSection(from: arguments)
            var folderPath: String? = nil
            if let section {
                // `<folder>/courses/<CODE>` → `<folder>`.
                folderPath = section.courseDirectory
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .path
            }
            return OtherCopy(
                pid: pid,
                kind: .scheduledPublish,
                folderPath: folderPath,
                courseCode: section?.courseCode,
                sectionNumber: section?.sectionNumber
            )
        }
        if arguments.contains(AssistMCPServer.flag) {
            return OtherCopy(
                pid: pid,
                kind: .assistantFromAnotherApp,
                folderPath: AssistMCPServer.requestedWorkingFolder(from: arguments)?.path,
                courseCode: nil,
                sectionNumber: nil
            )
        }
        return OtherCopy(pid: pid, kind: .other, folderPath: nil, courseCode: nil, sectionNumber: nil)
    }

    /// Everything the gate reads, now.
    static func currentFacts() -> Facts {
        var otherCopies: [OtherCopy] = []
        if let executablePath = Bundle.main.executablePath {
            let sightings: [SameExecutableProcesses.Sighting] =
                SameExecutableProcesses.sightings(ofExecutableAt: executablePath)
            for sighting in sightings {
                otherCopies.append(UpdateGate.classify(pid: sighting.pid, arguments: sighting.arguments))
            }
        }

        var folders: [String] = []
        for model in WorkspaceModel.windowModels {
            if let path = model.workspaceURL?.path {
                UpdateGate.add(path, to: &folders)
            }
        }
        for copy in otherCopies {
            if let path = copy.folderPath {
                UpdateGate.add(path, to: &folders)
            }
        }

        var leases: [LeaseSighting] = []
        for folder in folders {
            let found: [LeaseSighting] = UpdateGate.leasesHeldElsewhere(inWorkingFolder: folder)
            for lease in found {
                leases.append(lease)
            }
        }

        return Facts(
            publishes: CourseActivity.activePublishes,
            previewBuilds: CourseActivity.activePreviewBuilds,
            previews: PreviewLeases.active,
            otherCopies: otherCopies,
            leases: leases
        )
    }

    /// Every lease another live process holds in one working folder, of any
    /// kind and for any course — through `WorkLeaseFiles.heldElsewhere`, the
    /// one reader of a lease's owner (`ProcessLiveness`), so a lease left
    /// behind by a crash is ignored here exactly as everywhere else.
    static func leasesHeldElsewhere(inWorkingFolder folderPath: String) -> [LeaseSighting] {
        let coursesDirectory: URL = URL(fileURLWithPath: folderPath)
            .appendingPathComponent("courses", isDirectory: true)
        let activity: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: activity.path) else {
            return []
        }
        var courses: [String] = []
        for name in names {
            guard let parsed = WorkLeaseFiles.parse(fileName: name) else {
                continue
            }
            var alreadyListed: Bool = false
            for course in courses {
                if course.lowercased() == parsed.course.lowercased() {
                    alreadyListed = true
                }
            }
            if !alreadyListed {
                courses.append(parsed.course)
            }
        }
        var sightings: [LeaseSighting] = []
        for course in courses {
            let holdings: [WorkLeaseFiles.Holding] = WorkLeaseFiles.heldElsewhere(
                courseCode: course, coursesDirectory: coursesDirectory
            )
            for holding in holdings {
                sightings.append(LeaseSighting(
                    pid: holding.pid, kind: holding.kind, courseCode: course, folderPath: folderPath
                ))
            }
        }
        return sightings
    }

    /// What to watch while an update is held: the processes whose ending
    /// could clear the way, and the lease folders whose change could.
    static func watchTargets(for facts: Facts) -> (processIDs: [Int32], leaseFolders: [URL]) {
        var processIDs: [Int32] = []
        var leaseFolders: [URL] = []
        for copy in facts.otherCopies {
            if copy.kind == .scheduledPublish && !processIDs.contains(copy.pid) {
                processIDs.append(copy.pid)
            }
        }
        for lease in facts.leases {
            if !UpdateGate.leaseKindsThatHold.contains(lease.kind.lowercased()) {
                continue
            }
            if !processIDs.contains(lease.pid) {
                processIDs.append(lease.pid)
            }
            let coursesDirectory: URL = URL(fileURLWithPath: lease.folderPath)
                .appendingPathComponent("courses", isDirectory: true)
            let activity: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesDirectory)
            var alreadyListed: Bool = false
            for folder in leaseFolders {
                if folder.path == activity.path {
                    alreadyListed = true
                }
            }
            if !alreadyListed {
                leaseFolders.append(activity)
            }
        }
        return (processIDs: processIDs, leaseFolders: leaseFolders)
    }

    /// The scheduled publish with this process id, if there is one.
    private static func copy(withPID pid: Int32, among copies: [OtherCopy]) -> OtherCopy? {
        for copy in copies {
            if copy.pid == pid {
                return copy
            }
        }
        return nil
    }

    /// Adds a folder once, however it is spelled (#189).
    private static func add(_ path: String, to folders: inout [String]) {
        for existing in folders {
            if FolderIdentity.isSameFolder(existing, path) {
                return
            }
        }
        folders.append(path)
    }
}
