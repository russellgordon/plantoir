import Foundation

/// The build, preview and publish leases, as files: where they live, what
/// they are called, how one is written, and which of them stand in the way of
/// a build (#156).
///
/// A work lease is a file under `courses/.internal/activity/` saying which
/// process is doing what to a course, so that the window, the in-app
/// assistant, a publish set for later and an assistant working from another
/// app (`Plantoir --mcp-stdio`, which is a separate process with memory of its
/// own) never build one course at once. Two builds of one section clear and
/// rewrite the same folder, so the loser serves a half-written site or
/// publishes files the other has just deleted — and nothing fails loudly.
///
/// **The format is Windows' `WorkLease` and #245's.** `contracts/file-formats
/// .json` → `workLease` is the shape, and `ProcessLiveness` is the one reader
/// of whether a lease's owner is still alive; nothing here reads a process of
/// its own. What this type adds is the DECLINE rule — `contracts/shared-rules
/// .json` → `workLeases.declining` — as a pure function the contract's cases
/// run against.
///
/// Nonisolated and pure where it can be, so the scheduled publish (which
/// runs with no main-actor app at all) and the tests share it.
nonisolated enum WorkLeaseFiles {

    // MARK: - Types

    /// One lease another process holds on a course.
    struct Holding: Equatable, Sendable {

        // MARK: - Stored properties

        /// build, preview, publish or assist.
        let kind: String

        let pid: Int32

        /// The lease's third line — the moment it was taken, in .NET's "O"
        /// shape — or nil when the file has none.
        let moment: String?
    }

    /// This process's own claim, which the tiebreak compares against.
    struct Claim: Equatable, Sendable {

        // MARK: - Stored properties

        /// The moment this process wrote its own `build` lease.
        let moment: String

        let pid: Int32
    }

    /// Which question is being asked of the leases.
    enum Asker: Sendable {

        /// A build this process is about to start, from the window, the
        /// in-app assistant or an assistant working from another app.
        case aBuild

        /// A publish set for later, which waits rather than declines.
        case aScheduledPublish

        /// A deploy asked for by an outside assistant (#433, Russell
        /// 2026-10-03): declined only while a site is being BUILT. A preview
        /// the teacher is merely reading does not hold it back — the deploy
        /// ends that section's preview, as the window's own Deploy does.
        case anOutsideDeploy
    }

    /// What a CHANGE asked for by an outside assistant (Claude or Codex,
    /// through `Plantoir --mcp-stdio`) meets in the other programs' leases
    /// (#433). Not a question about building: the change writes pages, and
    /// what it is held back by is a site actually being built.
    enum OutsideChangeMeets: Equatable, Sendable {

        /// Nothing in the way.
        case clear

        /// Another program is building the course — a preview that is still
        /// being built (it holds `build` beside `preview`), or a deploy
        /// (`build` and `publish`). The change is held back.
        case building(Holding)

        /// Another program has a preview of the course up and has FINISHED
        /// building it — `preview` with no `build` beside it. The teacher is
        /// reading it; the change goes ahead and the preview is left alone.
        case previewServed(Holding)
    }

    /// The kinds that mean a site is being built right now (#433). A served
    /// preview holds `preview` only, so it is not here.
    static let kindsThatMeanBuilding: [String] = ["build", "publish"]

    // MARK: - Stored properties

    /// The kinds this side writes.
    static let buildKind: String = "build"
    static let previewKind: String = "preview"
    static let publishKind: String = "publish"

    /// The lease an assistant session holds on the course it is revising —
    /// on the mac, `Plantoir --mcp-stdio` holds it on the course the Claude
    /// door named in `AssistMCPServer.doorCourseVariable` (#458), as
    /// Windows' `plantoir-mcp` does. Never a lock, and never in a build's
    /// way: it greys the Revise items and the structural work on that
    /// course in the OTHER programs (`CourseActivity.structuralHoldReason`),
    /// and it is what makes the session's held-backup record count.
    static let assistKind: String = "assist"

    /// The end of a held-backup record's name: `<COURSE>.held-backup.<pid>`
    /// (#283 for another program, #458 on the mac). No `.lease` suffix, so
    /// no lease reader ever mistakes one for a lease.
    static let heldBackupRecordMarker: String = "held-backup"

    /// What stands in the way of a BUILD started here.
    ///
    /// `build` because two builds of one section clear the same folder.
    /// `publish` because a publish uploads what its build wrote — both apps
    /// hold `build` beside it for the whole deploy, so it adds nothing today,
    /// and it is here so a holder that ever released `build` early could not
    /// be undercut. `preview` since #156, stricter than Windows: a preview is
    /// the teacher's live work, and every build of a section first ends that
    /// section's serving preview (`build_site.stop_preview_serving`), so an
    /// assistant working from another app would otherwise take down the page
    /// the teacher is reading — which the in-app assistant already refused to
    /// do. `assist` and `import` never block a build.
    static let kindsThatBlockABuild: [String] = ["build", "publish", "preview"]

    /// What a publish set for later waits for.
    ///
    /// NOT `preview`, and that is a decision: a preview left open overnight
    /// would otherwise cost the morning's publish, which is the one outcome a
    /// scheduled publish exists to prevent. Its build ends that preview, as it
    /// always has.
    static let kindsAScheduledPublishWaitsFor: [String] = ["build", "publish"]

    // MARK: - Functions

    /// `courses/.internal/activity/` for a courses folder.
    static func activityDirectory(coursesDirectory: URL) -> URL {
        return coursesDirectory
            .appendingPathComponent(".internal", isDirectory: true)
            .appendingPathComponent("activity", isDirectory: true)
    }

    /// `<COURSE>.<kind>.<pid>.lease`, the course upper-cased the way Windows
    /// writes it.
    static func fileName(courseCode: String, kind: String, pid: Int32) -> String {
        return "\(courseCode.uppercased()).\(kind).\(pid).lease"
    }

    /// The course, kind and process id a lease's name carries — read from the
    /// END, the way Windows reads it — or nil for a name that is not a lease.
    static func parse(fileName: String) -> (course: String, kind: String, pid: Int32)? {
        if !fileName.hasSuffix(".lease") {
            return nil
        }
        let parts: [Substring] = fileName.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count < 4 {
            return nil
        }
        guard let pid = Int32(String(parts[parts.count - 2])) else {
            return nil
        }
        let kind: String = String(parts[parts.count - 3])
        var courseParts: [String] = []
        var index: Int = 0
        while index < parts.count - 3 {
            courseParts.append(String(parts[index]))
            index += 1
        }
        let course: String = courseParts.joined(separator: ".")
        if course.isEmpty || kind.isEmpty {
            return nil
        }
        return (course: course, kind: kind, pid: pid)
    }

    /// Writes one of this process's leases, atomically, and says the moment
    /// it carries — or nil when nothing was written.
    ///
    /// **Only when `courses/` is already there.** Windows creates the folder
    /// unconditionally; the mac does not, because a working folder that has
    /// no courses folder has nothing to lease, and the suite hands
    /// `CourseActivity` pretend paths ("/folder") that must never grow
    /// directories. A failure never stops the work — Windows' rule too.
    @discardableResult
    static func write(
        kind: String,
        courseCode: String,
        coursesDirectory: URL,
        moment: Date = Date()
    ) -> (url: URL, moment: String)? {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(
            atPath: coursesDirectory.path, isDirectory: &isDirectory
        )
        if !exists || !isDirectory.boolValue {
            return nil
        }
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesDirectory)
        let url: URL = directory.appendingPathComponent(
            WorkLeaseFiles.fileName(courseCode: courseCode, kind: kind, pid: getpid())
        )
        let body: String = ProcessLiveness.leaseBody(at: moment)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(body.utf8).write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return (url: url, moment: ProcessLiveness.leaseMomentText(moment))
    }

    /// Removes one of this process's leases. Quiet when it is already gone.
    static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// `<COURSE>.held-backup.<pid>` — the record a session writes beside its
    /// lease naming the backup its conversation made (Windows' format,
    /// `contracts/file-formats.json` → `heldBackupRecord`).
    static func heldBackupRecordName(courseCode: String, pid: Int32) -> String {
        return "\(courseCode.uppercased()).\(heldBackupRecordMarker).\(pid)"
    }

    /// The process id a held-backup record's name carries, or nil for a name
    /// that is not one.
    static func pidOfHeldBackupRecord(named fileName: String) -> Int32? {
        let parts: [Substring] = fileName.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count < 3 {
            return nil
        }
        if String(parts[parts.count - 2]) != heldBackupRecordMarker {
            return nil
        }
        return Int32(String(parts[parts.count - 1]))
    }

    /// The process ids of the OTHER live programs holding an `assist` lease
    /// on ANY course in this folder — the programs whose held-backup records
    /// count. Read with the same liveness rule every lease reader uses, so a
    /// killed session's leftover lease (and with it its record) holds nothing.
    static func assistHolders(
        coursesDirectory: URL,
        ownPID: Int32 = getpid(),
        ownerIsAlive: (Int32, String?, String?) -> Bool = ProcessLiveness.ownerIsAlive
    ) -> Set<Int32> {
        var holders: Set<Int32> = []
        let held: [(course: String, holding: Holding)] = WorkLeaseFiles.everyLeaseHeldElsewhere(
            coursesDirectory: coursesDirectory, ownPID: ownPID, ownerIsAlive: ownerIsAlive
        )
        for entry in held where entry.holding.kind.lowercased() == assistKind {
            holders.insert(entry.holding.pid)
        }
        return holders
    }

    /// The backups OTHER programs' live assistant sessions have on record in
    /// this folder, as the paths the records name, each with the course its
    /// record is filed under.
    ///
    /// A record counts only while its process holds a live `assist` lease
    /// (`assistHolders`) — Windows' rule: a session killed before it could
    /// tidy up leaves a record that holds nothing, rather than a backup the
    /// teacher can never delete. This process's own records are skipped, as
    /// its own leases are.
    static func backupsHeldByOtherSessions(
        coursesDirectory: URL,
        ownPID: Int32 = getpid(),
        ownerIsAlive: (Int32, String?, String?) -> Bool = ProcessLiveness.ownerIsAlive
    ) -> [(path: String, courseCode: String)] {
        var held: [(path: String, courseCode: String)] = []
        let living: Set<Int32> = WorkLeaseFiles.assistHolders(
            coursesDirectory: coursesDirectory, ownPID: ownPID, ownerIsAlive: ownerIsAlive
        )
        if living.isEmpty {
            return held
        }
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesDirectory)
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            return held
        }
        for name in names {
            guard let pid = WorkLeaseFiles.pidOfHeldBackupRecord(named: name) else {
                continue
            }
            if pid == ownPID || !living.contains(pid) {
                continue
            }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else {
                continue
            }
            let path: String = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty {
                continue
            }
            let marker: String = "." + heldBackupRecordMarker + "."
            var courseCode: String = name
            if let range = name.range(of: marker, options: .backwards) {
                courseCode = String(name[name.startIndex..<range.lowerBound])
            }
            held.append((path: path, courseCode: courseCode))
        }
        return held
    }

    /// The leases OTHER live processes hold on a course.
    ///
    /// This process's own are left out — a process is never in its own way;
    /// the in-process rules (`CourseActivity`, `PreviewLeases`) decide that —
    /// and so is any lease whose owner `ProcessLiveness` says is gone.
    /// Unreadable files and names that are not leases are ignored.
    static func heldElsewhere(
        courseCode: String,
        coursesDirectory: URL,
        ownPID: Int32 = getpid(),
        ownerIsAlive: (Int32, String?, String?) -> Bool = ProcessLiveness.ownerIsAlive
    ) -> [Holding] {
        var holdings: [Holding] = []
        let held: [(course: String, holding: Holding)] = WorkLeaseFiles.everyLeaseHeldElsewhere(
            coursesDirectory: coursesDirectory, ownPID: ownPID, ownerIsAlive: ownerIsAlive
        )
        for entry in held where entry.course.lowercased() == courseCode.lowercased() {
            holdings.append(entry.holding)
        }
        return holdings
    }

    /// Every lease OTHER live processes hold in this folder, on any course,
    /// each with the course its name carries — the one reading both
    /// `heldElsewhere` and `assistHolders` are made from.
    static func everyLeaseHeldElsewhere(
        coursesDirectory: URL,
        ownPID: Int32 = getpid(),
        ownerIsAlive: (Int32, String?, String?) -> Bool = ProcessLiveness.ownerIsAlive
    ) -> [(course: String, holding: Holding)] {
        var held: [(course: String, holding: Holding)] = []
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesDirectory)
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            return held
        }
        for name in names {
            guard let parsed = WorkLeaseFiles.parse(fileName: name) else {
                continue
            }
            if parsed.pid == ownPID {
                continue
            }
            let url: URL = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            let text: String = String(decoding: data, as: UTF8.self)
            let facts: (name: String?, start: String?) = ProcessLiveness.recordedFacts(inLeaseText: text)
            // A build, preview or publish lease with no name line is not one
            // either app writes, and Windows' reader treats fewer than two
            // lines as stale; judged on its id alone it could block a course
            // for the whole life of whatever was handed that id. #245's
            // `nameToCompare` supplies a name only for the IMPORT kind, whose
            // one-line shape an older Plantoir really wrote.
            guard let judgedName = ProcessLiveness.nameToCompare(recorded: facts.name, kind: parsed.kind) else {
                continue
            }
            if !ownerIsAlive(parsed.pid, judgedName, facts.start) {
                continue
            }
            held.append((
                course: parsed.course,
                holding: Holding(kind: parsed.kind, pid: parsed.pid, moment: WorkLeaseFiles.momentLine(in: text))
            ))
        }
        return held
    }

    /// The first holding that stands in the way, or nil when the way is clear
    /// — the decline rule itself, with nothing read from disk, so the
    /// contract's cases run against exactly this.
    ///
    /// **Take, then check, with a tiebreak.** A caller that has already
    /// written its own `build` lease passes its `claim` — the moment of that
    /// BUILD lease, never an earlier lease of another kind (a publish set for
    /// later does not wait for previews, so a claim taken from an old preview
    /// would let a window build alongside it); then a holding
    /// counts only if it was taken BEFORE that claim — an earlier moment, or
    /// the same moment and a lower process id. Two processes that write and
    /// then look at the same instant therefore cannot both back off: exactly
    /// one of them sees the other as earlier. With no claim (the early look
    /// before a preview is stopped, and a publish set for later that is still
    /// waiting) every blocking holding counts. A holding with no moment it can
    /// compare counts as earlier: when the order cannot be told, the other
    /// process is left alone.
    static func blocking(
        among holdings: [Holding],
        asker: Asker,
        claim: Claim?
    ) -> Holding? {
        let kinds: [String]
        switch asker {
        case .aBuild:
            kinds = WorkLeaseFiles.kindsThatBlockABuild
        case .aScheduledPublish:
            kinds = WorkLeaseFiles.kindsAScheduledPublishWaitsFor
        case .anOutsideDeploy:
            kinds = WorkLeaseFiles.kindsThatMeanBuilding
        }
        for holding in holdings {
            if !kinds.contains(holding.kind.lowercased()) {
                continue
            }
            guard let claim else {
                return holding
            }
            if WorkLeaseFiles.wasTakenBefore(holding, claim) {
                return holding
            }
        }
        return nil
    }

    /// What an outside assistant's change meets among the other programs'
    /// leases (#433).
    ///
    /// A building lease WINS over a preview lease, whatever order the files
    /// were read in: an app preview that is still building holds both, and
    /// reading it as merely served would let a change through — and a
    /// rebuild be answered as if nothing were building — while a build runs.
    /// No claim is compared: an outside change takes no lease of its own.
    static func whatAnOutsideChangeMeets(among holdings: [Holding]) -> OutsideChangeMeets {
        var served: Holding? = nil
        for holding in holdings {
            let kind: String = holding.kind.lowercased()
            if WorkLeaseFiles.kindsThatMeanBuilding.contains(kind) {
                return .building(holding)
            }
            if kind == WorkLeaseFiles.previewKind && served == nil {
                served = holding
            }
        }
        if let served {
            return .previewServed(served)
        }
        return .clear
    }

    /// Whether another process's lease was taken before this process's claim.
    ///
    /// The moments are compared as TEXT, which is exact for two strings in the
    /// one fixed shape both apps write (`2026-09-25T13:59:23.8960000Z`,
    /// always UTC, always seven fractional digits): the characters sort in
    /// time order. The mac's `DateFormatter` fills only three of the seven
    /// (millisecond resolution, measured), so two leases taken in the same
    /// millisecond tie, and the tie goes to the lower process id — ordinary,
    /// not rare. Anything not in that shape is treated as earlier.
    static func wasTakenBefore(_ holding: Holding, _ claim: Claim) -> Bool {
        guard let theirs = holding.moment else {
            return true
        }
        if !WorkLeaseFiles.isAComparableMoment(theirs) || !WorkLeaseFiles.isAComparableMoment(claim.moment) {
            return true
        }
        if theirs < claim.moment {
            return true
        }
        if theirs > claim.moment {
            return false
        }
        return holding.pid < claim.pid
    }

    /// Whether a moment is in the one shape the two apps write.
    static func isAComparableMoment(_ text: String) -> Bool {
        // 2026-09-25T13:59:23.8960000Z — 28 characters, a T at 10, a Z last.
        if text.count != 28 {
            return false
        }
        let characters: [Character] = Array(text)
        return characters[10] == "T" && characters[19] == "." && characters[27] == "Z"
    }

    /// A lease's third line, trimmed, or nil.
    static func momentLine(in text: String) -> String? {
        let unixText: String = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines: [Substring] = unixText.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count < 3 {
            return nil
        }
        let moment: String = String(lines[2]).trimmingCharacters(in: .whitespaces)
        if moment.isEmpty {
            return nil
        }
        return moment
    }

    /// What a holding is, in the words a trail line uses.
    static func describe(_ holding: Holding) -> String {
        switch holding.kind.lowercased() {
        case WorkLeaseFiles.previewKind:
            return "previewed by process \(holding.pid)"
        case WorkLeaseFiles.publishKind:
            return "published by process \(holding.pid)"
        default:
            return "built by process \(holding.pid)"
        }
    }
}
