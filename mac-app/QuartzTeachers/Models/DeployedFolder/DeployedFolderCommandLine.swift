import Foundation

/// `Plantoir --serve-deployed-folder <folder>` (#850): the same server the
/// window's Open in Browser starts, with no window, for checks run from the
/// command line (`scripts/crawl_deployed_folder.py`). It prints one line,
/// `DEPLOYED_FOLDER_ADDRESS=http://127.0.0.1:<port>/`, serves until its
/// standard input closes, and exits. Like `--mcp-stdio` it is checked before
/// anything puts a window on screen, and it never returns.
///
/// It remembers no address and writes no trail line: a check is not a
/// teacher opening their site.
enum DeployedFolderCommandLine {

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

    /// Serves `folder` until standard input closes.
    static func serve(folder: URL) -> Never {
        let canonical: String = FolderIdentity.canonicalPath(folder.path)
        Task { @MainActor in
            let candidates: [Int] = DeployedFolderAddress.candidates(forCanonicalPath: canonical, remembered: nil)
            // Held here for as long as it serves: the listener's handler
            // holds the server weakly, as the app's own record does.
            let server: DeployedFolderServer
            do {
                server = try await DeployedFolderServer.start(
                    root: URL(fileURLWithPath: canonical), candidates: candidates, onFolderGone: {}
                ).server
            } catch {
                FileHandle.standardError.write(Data("Plantoir: no address was free\n".utf8))
                exit(1)
            }
            print("DEPLOYED_FOLDER_ADDRESS=http://127.0.0.1:\(server.port)/")
            fflush(stdout)
            await DeployedFolderCommandLine.waitForInputToClose()
            await server.stop()
            exit(0)
        }
        // The main queue must run for the task above; the same arrangement
        // as `AssistMCPServer.serve(workingFolder:)`.
        dispatchMain()
    }

    /// Returns once standard input has closed.
    nonisolated static func waitForInputToClose() async {
        let reading: Task<Void, Never> = Task.detached {
            while readLine() != nil {
            }
        }
        await reading.value
    }
}
