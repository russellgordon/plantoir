import Darwin
import Foundation

/// The other processes running THIS copy of Plantoir's own executable, and
/// the arguments each was started with (#204).
///
/// **What it is for, and what it is not.** The install gate reads work
/// leases first (`UpdateGate`, #156): a lease says exactly what another
/// process is building or publishing. This scan fills the one gap they leave.
/// A publish set for later is `Plantoir --run-scheduled-deploy …` started by
/// launchd from this same executable (`ScheduledDeploy.runScheduled`), and it
/// waits up to ten minutes for a busy course BEFORE it takes a lease — and a
/// job set before v1.2.0 names no course and takes none at all. Replacing the
/// app under either would leave an old program reading a new app's files. The
/// scan also says which working folder an assistant working from another app
/// (`--mcp-stdio <folder>`) has open, so that folder's leases can be read.
///
/// **Why not the scheduled job's own file.** Its presence means "set for
/// later", not "running": the run's wrapper deletes the plist in its first
/// line (`ScheduledDeploy` → "The plist is removed FIRST"), so a publish in
/// progress has none.
///
/// **Measured** (plan for #204, `sp204/procscan`, and again by its review):
/// 0.6–1.0 ms per scan among about 700 processes, and a copy started by
/// launchd is found and classified the same as one started from a shell.
/// Nothing is written, so there is nothing to clean up after a crash.
///
/// Paths are compared after resolving symbolic links on both sides
/// (`/private`, the trap `CLAUDE.md` names for `/bin/pwd`), so one executable
/// is never two. Only processes of this user can have their arguments read,
/// which is every process that matters here: launchd runs a teacher's
/// scheduled publish as that teacher.
nonisolated enum SameExecutableProcesses {

    // MARK: - Types

    /// One other process of the same executable.
    struct Sighting: Equatable, Sendable {

        // MARK: - Stored properties

        let pid: Int32

        /// Its arguments, the executable's own name first — or empty when
        /// they could not be read.
        let arguments: [String]
    }

    // MARK: - Functions

    /// Every OTHER live process whose executable is the one at
    /// `executablePath`. This process is never reported.
    static func sightings(
        ofExecutableAt executablePath: String,
        ownPID: Int32 = getpid()
    ) -> [Sighting] {
        let wanted: String = SameExecutableProcesses.resolved(executablePath)
        var found: [Sighting] = []
        for pid in SameExecutableProcesses.allProcessIDs() {
            if pid == ownPID || pid <= 0 {
                continue
            }
            guard let path = SameExecutableProcesses.executablePath(of: pid) else {
                continue
            }
            if SameExecutableProcesses.resolved(path) != wanted {
                continue
            }
            let arguments: [String] = SameExecutableProcesses.arguments(of: pid) ?? []
            found.append(Sighting(pid: pid, arguments: arguments))
        }
        return found
    }

    /// Every process id on the Mac, from the kernel.
    static func allProcessIDs() -> [Int32] {
        let capacity: Int32 = proc_listallpids(nil, 0)
        if capacity <= 0 {
            return []
        }
        // Room for processes started between the two calls.
        var buffer: [Int32] = [Int32](repeating: 0, count: Int(capacity) + 64)
        let bytes: Int32 = Int32(buffer.count * MemoryLayout<Int32>.size)
        let count: Int32 = proc_listallpids(&buffer, bytes)
        if count <= 0 {
            return []
        }
        var result: [Int32] = []
        var index: Int = 0
        while index < Int(count) && index < buffer.count {
            result.append(buffer[index])
            index += 1
        }
        return result
    }

    /// The executable a process is running, or nil when it cannot be read.
    static func executablePath(of pid: Int32) -> String? {
        var buffer: [CChar] = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length: Int32 = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length <= 0 {
            return nil
        }
        return String(cString: buffer)
    }

    /// A process's arguments, from `KERN_PROCARGS2` — or nil when the kernel
    /// will not say (another user's process, or one that has just gone).
    ///
    /// The buffer is the argument count, then the executable's path, NUL
    /// padding, and the arguments one after another, each ending in NUL.
    static func arguments(of pid: Int32) -> [String]? {
        var request: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        if sysctl(&request, 3, nil, &size, nil, 0) != 0 || size <= 0 {
            return nil
        }
        var buffer: [UInt8] = [UInt8](repeating: 0, count: size)
        if sysctl(&request, 3, &buffer, &size, nil, 0) != 0 {
            return nil
        }
        let countSize: Int = MemoryLayout<Int32>.size
        if size < countSize {
            return nil
        }
        var argumentCount: Int32 = 0
        withUnsafeMutableBytes(of: &argumentCount) { destination in
            var byteIndex: Int = 0
            while byteIndex < countSize {
                destination[byteIndex] = buffer[byteIndex]
                byteIndex += 1
            }
        }
        var index: Int = countSize
        // The executable's path…
        while index < size && buffer[index] != 0 {
            index += 1
        }
        // …and the padding after it.
        while index < size && buffer[index] == 0 {
            index += 1
        }
        var result: [String] = []
        while result.count < Int(argumentCount) && index < size {
            let start: Int = index
            while index < size && buffer[index] != 0 {
                index += 1
            }
            result.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return result
    }

    /// A path with its symbolic links resolved, or the path itself when it
    /// cannot be.
    static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else {
            return path
        }
        defer {
            free(real)
        }
        return String(cString: real)
    }
}
