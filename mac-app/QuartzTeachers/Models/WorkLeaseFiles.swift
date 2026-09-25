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
    }

    // MARK: - Stored properties

    /// The kinds this side writes.
    static let buildKind: String = "build"
    static let previewKind: String = "preview"
    static let publishKind: String = "publish"

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
        let directory: URL = WorkLeaseFiles.activityDirectory(coursesDirectory: coursesDirectory)
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            return holdings
        }
        for name in names {
            guard let parsed = WorkLeaseFiles.parse(fileName: name) else {
                continue
            }
            if parsed.course.lowercased() != courseCode.lowercased() {
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
            if !ownerIsAlive(parsed.pid, facts.name, facts.start) {
                continue
            }
            holdings.append(
                Holding(kind: parsed.kind, pid: parsed.pid, moment: WorkLeaseFiles.momentLine(in: text))
            )
        }
        return holdings
    }

    /// The first holding that stands in the way, or nil when the way is clear
    /// — the decline rule itself, with nothing read from disk, so the
    /// contract's cases run against exactly this.
    ///
    /// **Take, then check, with a tiebreak.** A caller that has already
    /// written its own `build` lease passes its `claim`; then a holding
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

    /// Whether another process's lease was taken before this process's claim.
    ///
    /// The moments are compared as TEXT, which is exact for two strings in the
    /// one fixed shape both apps write (`2026-09-25T13:59:23.8960000Z`,
    /// always UTC, always seven fractional digits): the characters sort in
    /// time order. Anything not in that shape is treated as earlier.
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
