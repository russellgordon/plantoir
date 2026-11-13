import Foundation

/// The mark a copy of the app's tools into a working folder leaves while it
/// runs (#748 part 4): `courses/.internal/activity/toolchain-copying.<pid>`.
///
/// **Windows' marker, by name and by body** (#473, #477): the same file name,
/// the same lease body (`ProcessLiveness.leaseBody`: process id, name, the
/// moment, the start time), the same rule for whether its writer is still
/// alive, and written only when `courses/` is already there. Deliberately NOT
/// a `.lease` name: it holds no course, and every lease reader
/// (`WorkLeaseFiles.everyLeaseHeldElsewhere`) reads `*.lease` only.
///
/// **Who writes it, and who reads it.** Two copies write it for as long as
/// they run: the `.toolchain/` copy a window or the assistant's server starts
/// off the main actor (`ToolchainReadiness.ensure`), and a scheduled run's
/// whole copy, launchers included (`ScheduledRunFolderRefresh`). Three do not:
/// the window's launcher refresh (`refreshLaunchersIfNeeded`, milliseconds),
/// the synchronous copy (`initializeWorkspace` and the suite) and
/// `BuilderWarmUp`, which copies into a folder of its own. Only the scheduled run READS it, because it
/// is the one copier that goes straight on to build with nobody watching:
/// it waits for another program's live copy before its own copy and again
/// before its launchers start, so the launchers never hash a recipe another
/// copy is still writing. A window does not wait for a scheduled run's copy:
/// two copies at once write the same bytes, and since #748 a file the other
/// copy removed first is not a failure (`WorkspaceModel.syncDirectory`),
/// so the measured outcome of overlapping is wasted work. Windows' copies
/// take turns instead, because its two writers failed with sharing
/// violations (documentation/07-deployment.md, "On Windows since bundle 3").
///
/// A marker left by a copier that was killed names a process that is gone,
/// so it counts for nothing (`ProcessLiveness.ownerIsAlive`). Nothing sweeps
/// them: there is at most one per killed copy, and each is ignored.
nonisolated enum ToolchainCopyMarker {

    // MARK: - Types

    /// Another program's copy that is still running.
    struct Holding: Equatable, Sendable {

        // MARK: - Stored properties

        let pid: Int32

        /// The marker's third line, the moment it was written, or nil.
        let moment: String?
    }

    // MARK: - Stored properties

    /// The start of every marker's name: Windows' `ToolchainReadiness.MarkerPrefix`.
    static let prefix: String = "toolchain-copying."

    /// The kind the liveness rule is asked about, as Windows asks it.
    static let kind: String = "toolchain-copying"

    // MARK: - Functions

    /// `toolchain-copying.<pid>`.
    static func fileName(pid: Int32) -> String {
        return prefix + String(pid)
    }

    /// The process id a marker's name carries, or nil for any other name.
    ///
    /// Digits only after the prefix, so the temporary file an atomic write
    /// makes beside the marker (`toolchain-copying.4711.sb-…`, measured) is
    /// never read as one.
    static func pid(ofMarkerNamed name: String) -> Int32? {
        if !name.hasPrefix(prefix) {
            return nil
        }
        let digits: String = String(name.dropFirst(prefix.count))
        if digits.isEmpty {
            return nil
        }
        for character in digits {
            if !character.isASCII || !character.isNumber {
                return nil
            }
        }
        return Int32(digits)
    }

    /// `courses/.internal/activity/` for a working folder.
    static func activityDirectory(inWorkingFolder workingFolderURL: URL) -> URL {
        return WorkLeaseFiles.activityDirectory(
            coursesDirectory: workingFolderURL.appendingPathComponent("courses", isDirectory: true)
        )
    }

    /// Writes this process's marker, atomically, and says where — or nil
    /// when nothing was written: no `courses/` yet (Windows' rule, so a
    /// folder with no courses never gains a list), or the write failed. A
    /// failure never stops the copy.
    @discardableResult
    static func write(inWorkingFolder workingFolderURL: URL, moment: Date = Date()) -> URL? {
        let coursesURL: URL = workingFolderURL.appendingPathComponent("courses", isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: coursesURL.path, isDirectory: &isDirectory)
        if !exists || !isDirectory.boolValue {
            return nil
        }
        let directory: URL = ToolchainCopyMarker.activityDirectory(inWorkingFolder: workingFolderURL)
        let url: URL = directory.appendingPathComponent(ToolchainCopyMarker.fileName(pid: getpid()))
        let body: String = ProcessLiveness.leaseBody(at: moment)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(body.utf8).write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return url
    }

    /// Removes this process's marker. Quiet when there is none.
    static func remove(at url: URL?) {
        guard let url else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// The copies OTHER live programs are making into this working folder.
    ///
    /// This process's own marker is left out, and so is any whose writer is
    /// gone or whose body names no program (Windows' reader treats fewer than
    /// two lines as stale).
    static func othersCopying(
        inWorkingFolder workingFolderURL: URL,
        ownPID: Int32 = getpid(),
        ownerIsAlive: (Int32, String?, String?) -> Bool = ProcessLiveness.ownerIsAlive
    ) -> [Holding] {
        var holdings: [Holding] = []
        let directory: URL = ToolchainCopyMarker.activityDirectory(inWorkingFolder: workingFolderURL)
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            return holdings
        }
        for name in names.sorted() {
            guard let pid = ToolchainCopyMarker.pid(ofMarkerNamed: name) else {
                continue
            }
            if pid == ownPID {
                continue
            }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else {
                continue
            }
            let text: String = String(decoding: data, as: UTF8.self)
            let facts: (name: String?, start: String?) = ProcessLiveness.recordedFacts(inLeaseText: text)
            guard let judgedName = ProcessLiveness.nameToCompare(recorded: facts.name, kind: ToolchainCopyMarker.kind) else {
                continue
            }
            if !ownerIsAlive(pid, judgedName, facts.start) {
                continue
            }
            holdings.append(Holding(pid: pid, moment: WorkLeaseFiles.momentLine(in: text)))
        }
        return holdings
    }
}
