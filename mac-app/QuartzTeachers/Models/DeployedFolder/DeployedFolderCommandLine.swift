import Foundation

/// `Plantoir --serve-deployed-folder <folder>` (#850): the same server the
/// window's Open in Browser starts, with no window, for checks run from the
/// command line (`browser-checks/crawl_deployed_folder.py`). It prints one
/// line, `DEPLOYED_FOLDER_ADDRESS=http://127.0.0.1:<port>/` or
/// `DEPLOYED_FOLDER_FAILED=<why>`, serves until its standard input closes,
/// and exits. It is decided in `PlantoirMain`, before any application
/// exists, so it shows no Dock icon and can never take the key window; it
/// never returns.
///
/// It remembers no address and writes no trail line: a check is not a
/// teacher opening their site.
nonisolated enum DeployedFolderCommandLine {

    // MARK: - Stored properties

    static let flag: String = "--serve-deployed-folder"

    // MARK: - Functions

    /// The folder named after the flag, or nil when the flag is not there.
    static func requestedFolder(from arguments: [String]) -> URL? {
        var index: Int = 0
        while index < arguments.count {
            if arguments[index] == flag && index + 1 < arguments.count {
                return URL(fileURLWithPath: arguments[index + 1])
            }
            index += 1
        }
        return nil
    }

    /// How long starting may take before the process says it failed and
    /// leaves, rather than hanging silently (the fix round's HIGH: one
    /// instance printed nothing at all). A real timeout.
    nonisolated static let secondsToStart: Double = 10

    /// The lines it prints: exactly one of them, always.
    nonisolated static let readyPrefix: String = "DEPLOYED_FOLDER_ADDRESS="
    nonisolated static let failedPrefix: String = "DEPLOYED_FOLDER_FAILED="

    /// Serves `folder` until standard input closes or the process is told
    /// to end, and never becomes an application (`PlantoirMain`).
    ///
    /// Standard input is read on a thread of its own, not on the
    /// concurrency pool, and its end calls `exit` directly, so nothing the
    /// server is doing can keep the process alive after it (the fix round's
    /// HIGH: two instances outlived their input). TERM and INT keep their
    /// default action, which ends the process.
    static func serve(folder: URL) -> Never {
        let canonical: String = FolderIdentity.canonicalPath(folder.path)
        if !DeployedFolderResolver.isFolder(URL(fileURLWithPath: canonical)) {
            say(failedPrefix + "there is no folder there")
            exit(2)
        }
        let state: CommandLineState = CommandLineState()

        let reader: Thread = Thread {
            while readLine() != nil {
            }
            exit(0)
        }
        reader.start()

        let watchdog: Thread = Thread {
            Thread.sleep(forTimeInterval: DeployedFolderCommandLine.secondsToStart)
            if state.claimTheOneLine() {
                DeployedFolderCommandLine.say(failedPrefix + "it did not start in time")
                exit(1)
            }
        }
        watchdog.start()

        Task.detached {
            let candidates: [Int] = DeployedFolderAddress.candidates(forCanonicalPath: canonical, remembered: nil)
            do {
                let server: DeployedFolderServer = try await DeployedFolderServer.start(
                    root: URL(fileURLWithPath: canonical), candidates: candidates, onFolderGone: {}
                ).server
                state.keep(server)
                if state.claimTheOneLine() {
                    DeployedFolderCommandLine.say(readyPrefix + "http://127.0.0.1:\(server.port)/")
                }
            } catch {
                if state.claimTheOneLine() {
                    DeployedFolderCommandLine.say(failedPrefix + "no address was free")
                }
                exit(1)
            }
        }

        // The main thread only waits: the work is on the threads above and
        // the concurrency pool, and `exit` ends the process from either.
        while true {
            Thread.sleep(forTimeInterval: 3600)
        }
    }

    /// One line on standard output, flushed at once.
    nonisolated static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

/// What the threads of `--serve-deployed-folder` share: whether its one line
/// has been printed, and the server, held for as long as the process lives
/// (the listener's handler holds it weakly).
nonisolated final class CommandLineState: @unchecked Sendable {

    // MARK: - Stored properties

    private let lock: NSLock = NSLock()
    private var linePrinted: Bool = false
    private var server: DeployedFolderServer? = nil

    // MARK: - Functions

    /// True for the first caller only.
    func claimTheOneLine() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        if linePrinted {
            return false
        }
        linePrinted = true
        return true
    }

    func keep(_ kept: DeployedFolderServer) {
        lock.lock()
        server = kept
        lock.unlock()
    }
}
