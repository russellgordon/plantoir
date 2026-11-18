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

    /// True once no process has this id.
    static func hasGone(_ processIdentifier: Int32) -> Bool {
        if kill(processIdentifier, 0) == 0 {
            return false
        }
        return errno == ESRCH
    }

    /// Asks each process to end (`SIGTERM`), waits until it has gone, and
    /// kills one that has not gone within `endTimeout`. Returns how many
    /// were found.
    @discardableResult
    static func end(processesNaming folderPaths: [String]) -> Int {
        let found: [Int32] = processes(naming: folderPaths)
        for processIdentifier in found {
            kill(processIdentifier, SIGTERM)
        }
        let deadline: Date = Date().addingTimeInterval(endTimeout)
        for processIdentifier in found {
            while hasGone(processIdentifier) == false && Date() < deadline {
                usleep(50_000)
            }
            if hasGone(processIdentifier) == false {
                // Checked again before the kill, so the id is still a
                // process naming this launch's folder and not a reused one.
                let stillNaming: [String] = arguments(ofProcess: processIdentifier)
                for folderPath in folderPaths {
                    if argumentsName(stillNaming, folder: folderPath) {
                        kill(processIdentifier, SIGKILL)
                        break
                    }
                }
            }
        }
        return found.count
    }
}
