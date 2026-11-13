import Foundation

/// Where the process starts (#850's fix round).
///
/// `--serve-deployed-folder` is decided HERE, before SwiftUI's `App.main`
/// creates an `NSApplication`, because a process that has one is an
/// application to the window server: it can show in the Dock and take the
/// key window from whatever the teacher is typing in. The headless server is
/// for checks run from the command line and from `verify.sh`, which run
/// while the teacher works, so it must never become one. It imports no
/// AppKit, touches no `NSApp`, and calls `exit` itself; nothing after the
/// check below runs for it. (The other headless modes, `--mcp-stdio` and
/// `--write-contracts`, are still decided in `QuartzTeachersApp.init`; see
/// `documentation/09-mac-app.md` → "A deployed folder opened in the
/// browser (#850)" for how that was checked.)
///
/// Everything else is the ordinary app.
@main
enum PlantoirMain {

    // MARK: - Functions

    static func main() {
        if let folder = DeployedFolderCommandLine.requestedFolder(from: CommandLine.arguments) {
            DeployedFolderCommandLine.serve(folder: folder)
        }
        QuartzTeachersApp.main()
    }
}
