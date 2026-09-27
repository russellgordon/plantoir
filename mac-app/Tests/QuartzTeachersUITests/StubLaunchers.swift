import XCTest

/// Stand-ins for the launchers, shared by every UI test class.
///
/// Under `--state-dir` (#154) a UI test may run STUB launchers only: a real
/// launcher takes `HOME` from its environment — the teacher's real one — so
/// it would build into the real builds folder and could fetch helper
/// programs into it, whatever the app's own state folder says.
///
/// The runner is sandboxed and cannot spawn a process at all (measured
/// 2026-08-23), so everything here that has to touch a process does it with
/// `sysctl` and `kill` on a process id the stub records itself.
enum StubLaunchers {

    // MARK: - Functions

    /// Kills a stub the current test started, if it is still running and is
    /// still the program it was — a process id is reused once its owner is
    /// reaped, so "something answers to this number" is NOT enough to justify
    /// a SIGKILL.
    ///
    /// The name check is lowercased deliberately: Homebrew's `python3` runs
    /// through a `Python.app` framework stub, so the kernel reports `Python`
    /// with a capital P, while the developer tools' `/usr/bin/python3`
    /// reports `python3`. A case-sensitive check passes on one machine and
    /// silently reaps nothing on the other.
    static func reap(pidFileURL: URL, expectingNamePrefix prefix: String) {
        guard let recordedText = try? String(contentsOf: pidFileURL, encoding: .utf8) else {
            return
        }
        try? FileManager.default.removeItem(at: pidFileURL)
        let trimmedText: String = recordedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let processID = Int32(trimmedText), processID > 1 else {
            return
        }
        guard let runningName = nameOfRunningProcess(processID) else {
            return
        }
        guard runningName.lowercased().hasPrefix(prefix) else {
            return
        }
        _ = kill(processID, SIGKILL)
    }

    /// The short name of a running process, or nil when no process holds
    /// that id.
    ///
    /// Asks the kernel directly (`sysctl`) rather than running `ps`,
    /// because this runner cannot spawn a process at all.
    static func nameOfRunningProcess(_ processID: Int32) -> String? {
        var selector: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processID]
        var processInfo: kinfo_proc = kinfo_proc()
        var infoSize: Int = MemoryLayout<kinfo_proc>.stride

        let outcome: Int32 = sysctl(&selector, 4, &processInfo, &infoSize, nil, 0)
        if outcome != 0 || infoSize == 0 {
            return nil
        }

        // Copied to a local first: reading the tuple's size inside a
        // pointer closure over the same property is an overlapping
        // access, and the compiler rejects it.
        var commandName = processInfo.kp_proc.p_comm
        let commandNameSize: Int = MemoryLayout.size(ofValue: commandName)
        return withUnsafePointer(to: &commandName) { commandPointer in
            return commandPointer.withMemoryRebound(
                to: CChar.self,
                capacity: commandNameSize
            ) { characterPointer in
                return String(cString: characterPointer)
            }
        }
    }

    /// Writes a fake `preview.sh` into a fixture workspace: it reports
    /// the same milestones a real preview does, builds a one-page site
    /// where a real build would put it, and serves that folder over HTTP
    /// for the app to embed.
    ///
    /// Two details are load-bearing, and the test cannot pass without
    /// either of them.
    ///
    /// It BUILDS INTO the folder the app watches. `waitForPreviewServer`
    /// will not show a preview until this section's built `index.html`
    /// has CHANGED — that is how a teacher is stopped from being shown
    /// the previous build — and it waits two minutes before giving up on
    /// that. A stub that serves a site from somewhere else never trips
    /// the check, so the preview arrives two minutes late and the test
    /// times out first.
    ///
    /// And it takes whatever port the kernel hands it, announcing that
    /// port on the line the app scrapes, so this suite cannot collide
    /// with a second run, a teacher's own preview, or any unrelated
    /// program that happens to hold a port. It records its process id
    /// before `exec`, which preserves that id, so what is written is the
    /// server's own and `tearDown` can reap it.
    ///
    /// Returns the file the server's process id is recorded in, for `reap`.
    @discardableResult
    static func writeStubPreviewScript(in fixtureURL: URL, buildingInto publicURL: URL) throws -> URL {
        let pidFileURL: URL = fixtureURL.appendingPathComponent("stub-preview.pid")
        try? FileManager.default.removeItem(at: pidFileURL)

        let stubScript: String = """
        #!/bin/bash
        # Stop mode. The app runs `preview.sh <course> <section> --stop`
        # whenever a preview ends, and WAITS for it before starting the
        # next one, so a stub that ignores the flag and starts a server
        # instead never exits and wedges the restart.
        for argument in "$@"; do
            if [ "$argument" = "--stop" ]; then
                if [ -f "\(pidFileURL.path)" ]; then
                    # Name-checked, for the same reason the Swift reaper
                    # checks: a recorded pid may have died and been
                    # recycled, and signalling it blind is how a test
                    # kills an unrelated program. Substring rather than
                    # prefix because `ps` reports a full path here.
                    stub_pid="$(cat "\(pidFileURL.path)")"
                    stub_name="$(ps -p "$stub_pid" -o comm= 2>/dev/null | tr '[:upper:]' '[:lower:]')"
                    case "$stub_name" in
                        *python*) kill "$stub_pid" 2>/dev/null ;;
                    esac
                    rm -f "\(pidFileURL.path)"
                fi
                exit 0
            fi
        done

        # Recorded FIRST, before anything slow. `$$` is this shell, and
        # `exec` below keeps that id, so the value is right this early —
        # and writing it here closes a window that would otherwise leak
        # the very orphan this file exists to prevent: a test can finish
        # and tear down within a second of starting a preview, and a pid
        # written after the sleeps would not exist yet to be reaped.
        echo $$ > "\(pidFileURL.path)"

        echo "Starting container if needed"
        sleep 1
        echo "Copying shared folders"
        sleep 1
        mkdir -p "\(publicURL.path)"
        printf '%s' '<html><body><h1>Stub site</h1></body></html>' > "\(publicURL.path)/index.html"
        cd "\(publicURL.path)" && exec python3 -u -c '
        import http.server
        import socketserver
        import sys

        class ReusableServer(socketserver.TCPServer):
            allow_reuse_address = True

        # Bind BEFORE announcing: the port is real by the time the app
        # reads about it, so there is no window in which something else
        # could take it.
        server = ReusableServer(("127.0.0.1", 0), http.server.SimpleHTTPRequestHandler)
        port = server.server_address[1]
        print("Preview will be available at: http://localhost:%d/" % port)
        print("Launching Quartz preview on http://localhost:%d" % port)
        sys.stdout.flush()
        server.serve_forever()
        '
        """

        let stubURL: URL = fixtureURL.appendingPathComponent("preview.sh")
        try stubScript.write(to: stubURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)
        return pidFileURL
    }
}
