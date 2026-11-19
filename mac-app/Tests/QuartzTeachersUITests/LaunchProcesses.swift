import Darwin
import Foundation

/// The processes one UI test's launch of the app left running, found by the
/// launch's own folders in their command line, and ended (#978).
///
/// **Why.** `XCUIApplication.terminate()` ends the app without its quit
/// path, so anything the app started and would have stopped on the way out
/// outlives it, reparented to `launchd`: measured on 2026-11-18, the two
/// `llama-server`s the rollover test's launches started were still running
/// after the class had finished.
///
/// **Which processes.** Only those whose arguments name a folder this test
/// made, `<runner temp>/plantoir-state-<UUID>` or
/// `<runner temp>/cq4t-fixture-<UUID>`: a model server's `--model` lies in
/// the launch's state folder (`linkRealAssistantWeights`), a stub launcher
/// runs from the fixture. Those names are one launch's own, so a model
/// server or preview of the teacher's own Plantoir, whose paths are in their
/// real home, can never match. Never by program name alone. Only this
/// account's processes are looked at, and never this runner itself.
///
/// The runner is sandboxed and cannot spawn `ps`, so the list comes from the
/// kernel (`sysctl`: `KERN_PROC_UID` for the processes, `KERN_PROCARGS2`
/// for each one's arguments).
enum LaunchProcesses {

    // MARK: - Stored properties

    /// How long an ended process is given to go before it is killed. A
    /// ceiling on a wait for the process to be gone, not a pause.
    static let endTimeout: TimeInterval = 10

    // MARK: - Functions

    /// Every process of this account, by id.
    static func processIdentifiersOfThisAccount() -> [Int32] {
        var selector: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var byteCount: Int = 0
        if sysctl(&selector, 4, nil, &byteCount, nil, 0) != 0 || byteCount == 0 {
            return []
        }
        // Room for processes started between the two calls.
        byteCount += 64 * MemoryLayout<kinfo_proc>.stride
        let capacity: Int = byteCount / MemoryLayout<kinfo_proc>.stride
        var processes: [kinfo_proc] = Array(repeating: kinfo_proc(), count: capacity)
        if sysctl(&selector, 4, &processes, &byteCount, nil, 0) != 0 {
            return []
        }
        let found: Int = byteCount / MemoryLayout<kinfo_proc>.stride
        var identifiers: [Int32] = []
        var index: Int = 0
        while index < found {
            identifiers.append(processes[index].kp_proc.p_pid)
            index += 1
        }
        return identifiers
    }

    /// A process's arguments, the program first; empty when they cannot be
    /// read (the process has gone, or the kernel refused).
    static func arguments(ofProcess processIdentifier: Int32) -> [String] {
        var selector: [Int32] = [CTL_KERN, KERN_PROCARGS2, processIdentifier]
        var byteCount: Int = 0
        if sysctl(&selector, 3, nil, &byteCount, nil, 0) != 0 || byteCount <= MemoryLayout<Int32>.size {
            return []
        }
        var buffer: [UInt8] = Array(repeating: 0, count: byteCount)
        if sysctl(&selector, 3, &buffer, &byteCount, nil, 0) != 0 || byteCount <= MemoryLayout<Int32>.size {
            return []
        }
        // Layout: argc (Int32), the executable path, padding NULs, then
        // argc NUL-terminated arguments, then the environment.
        var argumentCount: Int32 = 0
        withUnsafeMutableBytes(of: &argumentCount) { (countBytes: UnsafeMutableRawBufferPointer) -> Void in
            var byteIndex: Int = 0
            while byteIndex < MemoryLayout<Int32>.size {
                countBytes[byteIndex] = buffer[byteIndex]
                byteIndex += 1
            }
        }
        var position: Int = MemoryLayout<Int32>.size
        // Skip the executable path and the NULs after it.
        while position < byteCount && buffer[position] != 0 {
            position += 1
        }
        while position < byteCount && buffer[position] == 0 {
            position += 1
        }
        var arguments: [String] = []
        var current: [UInt8] = []
        while position < byteCount && arguments.count < Int(argumentCount) {
            let byte: UInt8 = buffer[position]
            if byte == 0 {
                arguments.append(String(decoding: current, as: UTF8.self))
                current = []
            } else {
                current.append(byte)
            }
            position += 1
        }
        return arguments
    }

    /// True when an argument is the folder or a path inside it.
    static func argumentsName(_ arguments: [String], folder folderPath: String) -> Bool {
        for argument in arguments {
            if argument == folderPath || argument.contains(folderPath + "/") {
                return true
            }
        }
        return false
    }

    /// The processes, other than this runner, whose arguments name one of
    /// the folders.
    static func processes(naming folderPaths: [String]) -> [Int32] {
        var matching: [Int32] = []
        let ownProcess: Int32 = getpid()
        for processIdentifier in processIdentifiersOfThisAccount() {
            if processIdentifier <= 1 || processIdentifier == ownProcess {
                continue
            }
            let processArguments: [String] = arguments(ofProcess: processIdentifier)
            for folderPath in folderPaths {
                if argumentsName(processArguments, folder: folderPath) {
                    matching.append(processIdentifier)
                    break
                }
            }
        }
        return matching
    }

    /// The user id a process runs as, asked of the kernel. Nil when no
    /// process holds that id.
    static func owner(ofProcess processIdentifier: Int32) -> uid_t? {
        var selector: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        var processInfo: kinfo_proc = kinfo_proc()
        var infoSize: Int = MemoryLayout<kinfo_proc>.stride
        if sysctl(&selector, 4, &processInfo, &infoSize, nil, 0) != 0 || infoSize == 0 {
            return nil
        }
        return processInfo.kp_eproc.e_ucred.cr_uid
    }

    /// True once no process has this id.
    static func hasGone(_ processIdentifier: Int32) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return false
        }
        return errno == ESRCH
    }

    /// True when the process's arguments, read now, still name one of the
    /// folders: checked again right before every signal, so an id that has
    /// been given to another process since the list was read is never sent
    /// one.
    static func stillNames(_ processIdentifier: Int32, oneOf folderPaths: [String]) -> Bool {
        let currentArguments: [String] = arguments(ofProcess: processIdentifier)
        for folderPath in folderPaths {
            if argumentsName(currentArguments, folder: folderPath) {
                return true
            }
        }
        return false
    }

    /// Waits until every process in the list has exited, or until the
    /// deadline, whichever comes first, by asking the kernel to report each
    /// one's exit (`kqueue`, `EVFILT_PROC` with `NOTE_EXIT`): a wait on the
    /// event itself, not a poll and not a pause. The processes are not this
    /// runner's children (a model server is reparented to `launchd`), so
    /// `waitpid` cannot be used. Returns the ids that had not exited.
    static func waitForExit(of processIdentifiers: [Int32], until deadline: Date) -> [Int32] {
        var stillRunning: Set<Int32> = []
        let queue: Int32 = kqueue()
        if queue < 0 {
            for processIdentifier in processIdentifiers {
                if hasGone(processIdentifier) == false {
                    stillRunning.insert(processIdentifier)
                }
            }
            return Array(stillRunning)
        }
        defer {
            close(queue)
        }
        for processIdentifier in processIdentifiers {
            var change: kevent = kevent(
                ident: UInt(processIdentifier),
                filter: Int16(EVFILT_PROC),
                flags: UInt16(EV_ADD | EV_ONESHOT),
                fflags: NOTE_EXIT,
                data: 0,
                udata: nil
            )
            if kevent(queue, &change, 1, nil, 0, nil) == 0 {
                stillRunning.insert(processIdentifier)
            } else if errno != ESRCH {
                // Not watchable (refused): counted as running, so the kill
                // below still considers it, after its own re-check.
                stillRunning.insert(processIdentifier)
            }
            // ESRCH: it had already exited.
        }
        // Registered only after the watch, so an exit between the two
        // calls cannot be missed: check what is already gone.
        for processIdentifier in stillRunning {
            if hasGone(processIdentifier) {
                stillRunning.remove(processIdentifier)
            }
        }
        while stillRunning.isEmpty == false {
            let remaining: TimeInterval = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                break
            }
            let wholeSeconds: Int = Int(remaining)
            let nanoseconds: Int = Int((remaining - Double(wholeSeconds)) * 1_000_000_000)
            var limit: timespec = timespec(tv_sec: wholeSeconds, tv_nsec: nanoseconds)
            var reported: kevent = kevent()
            let count: Int32 = kevent(queue, nil, 0, &reported, 1, &limit)
            if count > 0 {
                stillRunning.remove(Int32(reported.ident))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                break
            }
        }
        return Array(stillRunning)
    }

    /// Asks each process to end (`SIGTERM`), waits for its exit, and kills
    /// one that has not exited within `endTimeout`. Before each signal the
    /// process's arguments are read again and must still name one of the
    /// folders. Returns how many were found.
    @discardableResult
    static func end(processesNaming folderPaths: [String]) -> Int {
        let found: [Int32] = processes(naming: folderPaths)
        var signalled: [Int32] = []
        for processIdentifier in found {
            if stillNames(processIdentifier, oneOf: folderPaths) {
                kill(processIdentifier, SIGTERM)
                signalled.append(processIdentifier)
            }
        }
        let deadline: Date = Date().addingTimeInterval(endTimeout)
        let notExited: [Int32] = waitForExit(of: signalled, until: deadline)
        for processIdentifier in notExited {
            if stillNames(processIdentifier, oneOf: folderPaths) {
                kill(processIdentifier, SIGKILL)
            }
        }
        return found.count
    }

    /// When a process started, from the kernel, so a record of a process
    /// cannot be mistaken for a later process given the same id. Nil when no
    /// process holds that id.
    static func stamp(ofProcess processIdentifier: Int32) -> ProcessStamp? {
        var selector: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
        var processInfo: kinfo_proc = kinfo_proc()
        var infoSize: Int = MemoryLayout<kinfo_proc>.stride
        if sysctl(&selector, 4, &processInfo, &infoSize, nil, 0) != 0 || infoSize == 0 {
            return nil
        }
        let started: timeval = processInfo.kp_proc.p_un.__p_starttime
        return ProcessStamp(
            processIdentifier: processIdentifier,
            startSeconds: Int(started.tv_sec),
            startMicroseconds: Int(started.tv_usec)
        )
    }
}

/// One process, named by its id AND the moment it started, which together
/// no later process can share (#978c).
struct ProcessStamp: Hashable {

    // MARK: - Stored properties

    let processIdentifier: Int32
    let startSeconds: Int
    let startMicroseconds: Int
}
