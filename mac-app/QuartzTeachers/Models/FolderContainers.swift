import Foundation

/// The container behind a working folder, and when to let it rest.
///
/// Each working folder has its own container, named after a hash of the
/// folder's path — the launchers derive the same name with
/// `pwd -P | shasum -a 256`, so the trailing newline is part of the hashed
/// input here too. When the last window using a folder closes, that
/// folder's container is stopped: it holds no content (everything lives on
/// the host) and restarts in about a second on the next preview, so keeping
/// it running for nobody would only spend the teacher's memory.
@MainActor
enum FolderContainers {

    // MARK: - Functions

    /// The name the launchers give this folder's container.
    ///
    /// The identifier itself lives in `BuildOutputLocation`, which needs the
    /// same eight characters to name the folder a working folder's builds go
    /// in — one derivation, so a container and its builds folder can never
    /// disagree about which folder they belong to.
    static func containerName(forFolder path: String) -> String {
        return "teaching-quartz-" + BuildOutputLocation.folderIdentifier(forWorkingFolder: path)
    }

    /// Everything to run at quit, as one detached script: stop this app's
    /// containers, and if that leaves NOTHING running in the VM, stop the
    /// VM itself — its reserved memory is the real cost.
    ///
    /// The emptiness check is what makes this safe: Colima is shared (a
    /// database stack from another project may well be running), and the
    /// VM must never be stopped out from under someone else's containers.
    /// The next preview recovers on its own either way — the launchers
    /// start Colima when it is down.
    static func quitScript(containerNames: [String]) -> String {
        var lines: [String] = []
        if !containerNames.isEmpty {
            lines.append("docker stop -t 2 " + containerNames.joined(separator: " ") + " >/dev/null 2>&1")
        }
        lines.append("if command -v colima >/dev/null 2>&1; then")
        lines.append("  if [ -z \"$(docker ps -q 2>/dev/null)\" ]; then")
        lines.append("    colima stop >/dev/null 2>&1")
        lines.append("  fi")
        lines.append("fi")
        return lines.joined(separator: "\n")
    }

    /// Runs the quit script detached, so quitting does not wait on it.
    static func releaseEverythingAtQuit(folderPaths: [String]) {
        if WorkspaceModel.isRunningTests {
            return
        }
        var names: [String] = []
        for path in folderPaths {
            let name: String = containerName(forFolder: path)
            if !names.contains(name) {
                names.append(name)
            }
        }
        let script: String = quitScript(containerNames: names)
        let shell: Process = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-l", "-c", "( " + script + " ) >/dev/null 2>&1 &!"]
        try? shell.run()
    }

    /// Stops the folder's container, quietly, without waiting on it.
    ///
    /// `docker stop`, not `rm`: the container restarts far faster than it
    /// recreates, and the next preview starts it again automatically.
    static func stopContainer(forFolder path: String) {
        if WorkspaceModel.isRunningTests {
            return
        }
        let name: String = containerName(forFolder: path)
        let shell: Process = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // A login shell, so docker is on PATH wherever it was installed;
        // backgrounded and disowned, so quitting does not wait on it.
        // A short grace: the container's main process is an idle tail that
        // ignores SIGTERM, and there is nothing in it to save — without -t
        // it would linger the default ten seconds before the kill.
        shell.arguments = ["-l", "-c", "docker stop -t 2 \(name) >/dev/null 2>&1 &!"]
        try? shell.run()
    }
}
