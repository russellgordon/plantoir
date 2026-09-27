import Foundation

/// One definition of where Plantoir's helper programs live, and of the
/// environment every helper Plantoir starts is given.
///
/// **Why this exists.** A Mac that has never had Homebrew has exactly one
/// `docker` and one `colima` on it: the pinned copies the launchers download
/// into `~/Library/Application Support/Plantoir/tools/bin`. Nothing puts that
/// folder on a shell's `PATH` — only `setup.sh` and its siblings export it,
/// from inside the launcher — so anything the app runs WITHOUT saying where to
/// look finds neither program. An app opened from the Dock starts from
/// `PATH=/usr/bin:/bin:/usr/sbin:/sbin` (measured 2026-09-19: not even
/// `/usr/local/bin`, and `launchctl getenv PATH` is empty), so the quit path's
/// `docker stop` and `colima stop` had never run on a teacher's Mac —
/// silently, because their output went to the null device. That is
/// [issue #220](https://github.com/russellgordon/plantoir/issues/220).
///
/// **The order is the launchers' order, deliberately.** `setup.sh` does
/// `export PATH="$TOOLS_DIR/bin:$PATH"`, so the pinned copies win there; the
/// app agrees rather than the other way round, because the launcher is what
/// actually built the container. Homebrew's two directories come next, for the
/// developer Mac where the tools folder exists and is empty. What was
/// inherited comes last, so nothing a teacher has set up is taken away.
///
/// **Everything else in the environment is preserved, and `HOME` is the one
/// that matters.** `docker` keeps its context store in `~/.docker` and
/// `colima` its whole state in `~/.colima`; a helper handed a stripped
/// environment would fail to reach the engine at all — which, under the quit
/// path's rules, then reads as "do not stop anything".
nonisolated enum HelperPrograms {

    // MARK: - Types

    /// One program Plantoir is about to run, as a value.
    ///
    /// A value rather than a `Process` so that a test can compare what would
    /// be run — the program, its arguments, the environment it is handed —
    /// without anything being started. The mac is copying this from Windows,
    /// whose `FolderContainers.CommandRunnerOverride` made the same shell-outs
    /// testable there first; a value needs no resetting between tests, which a
    /// mutable hook does.
    struct Command: Equatable {

        // MARK: - Stored properties

        let executablePath: String
        let arguments: [String]
        let environment: [String: String]
        let currentDirectoryPath: String?
    }

    // MARK: - Stored properties

    /// The two places a Mac WITH Homebrew keeps the same programs, in the
    /// order Homebrew itself puts them: Apple silicon first, Intel second.
    static let sharedSearchDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// What a GUI application inherits when it is opened from the Dock, and so
    /// the least a helper should be left with when there is nothing to inherit.
    static let pathWhenNothingWasInherited: String = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// The variable that tells a launcher where this app's own copies of the
    /// helper programs and the website builder's starting disk are (GitHub
    /// #312). The launchers INSTALL from it into `binDirectory` and run the
    /// programs from there, never from inside the app: see
    /// `contracts/app-rules.json` → `helperBootstrap` for why.
    static let bundledHelpersVariable: String = "PLANTOIR_BUNDLED_HELPERS"

    // MARK: - Functions

    /// `~/Library/Application Support/Plantoir/tools/bin` — the folder the
    /// launchers download the pinned programs into.
    ///
    /// Taking the home folder as an argument is the same device
    /// `BuildOutputLocation.buildsRoot(inHomeFolder:)` uses, and for the same
    /// reason: the rule stays checkable without a test asserting anything
    /// about the teacher's real Application Support.
    static func binDirectory(
        inHomeFolder homeFolder: URL = RealHome.forFiles
    ) -> String {
        return homeFolder
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Plantoir")
            .appendingPathComponent("tools")
            .appendingPathComponent("bin")
            .path
    }

    /// Every directory Plantoir adds, in the order they are searched.
    static func searchDirectories(
        inHomeFolder homeFolder: URL = RealHome.forFiles
    ) -> [String] {
        var directories: [String] = [binDirectory(inHomeFolder: homeFolder)]
        for directory in sharedSearchDirectories {
            directories.append(directory)
        }
        return directories
    }

    /// The `PATH` a helper should be given, built on top of whatever it would
    /// otherwise have had.
    ///
    /// Nothing is removed and nothing is de-duplicated: a directory named
    /// twice costs one extra `stat` and removing one a teacher put there
    /// deliberately costs them a program they were relying on.
    static func pathValue(
        inheriting inherited: String?,
        inHomeFolder homeFolder: URL = RealHome.forFiles
    ) -> String {
        var parts: [String] = searchDirectories(inHomeFolder: homeFolder)
        let tail: String = (inherited ?? "").isEmpty ? pathWhenNothingWasInherited : (inherited ?? "")
        parts.append(tail)
        return parts.joined(separator: ":")
    }

    /// `Contents/Resources/helpers` inside this app, or nil when the app
    /// carries no helpers there (an app built without `fetch-helpers.sh`, or a
    /// test bundle). What is inside is described by its own `MANIFEST`, which
    /// the launcher checks; this only says whether the folder is there.
    static func bundledHelpersDirectory(in bundle: Bundle = Bundle.main) -> URL? {
        guard let resources = bundle.resourceURL else {
            return nil
        }
        let folder: URL = resources.appendingPathComponent("helpers", isDirectory: true)
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue {
            return folder
        }
        return nil
    }

    /// The whole environment for a helper: what it would have inherited, with
    /// `PATH` replaced. `HOME` and everything else survive untouched.
    ///
    /// `PLANTOIR_BUNDLED_HELPERS` is added when this app carries its own
    /// copies, and REMOVED when it does not, so a value inherited from some
    /// other copy of Plantoir never points a launcher at a folder that is not
    /// this app's. Every launcher the app runs is started with this
    /// environment — from the window, from the MCP server, and the publishes
    /// launchd starts through Plantoir itself — so all of them can install
    /// from the app; a launcher typed at the command line has no such
    /// variable and downloads, as it always has.
    static func environment(
        basedOn inherited: [String: String] = ProcessInfo.processInfo.environment,
        inHomeFolder homeFolder: URL = RealHome.forFiles,
        bundledHelpers: URL? = bundledHelpersDirectory()
    ) -> [String: String] {
        var result: [String: String] = inherited
        result["PATH"] = pathValue(inheriting: inherited["PATH"], inHomeFolder: homeFolder)
        if let bundledHelpers {
            result[bundledHelpersVariable] = bundledHelpers.path
        } else {
            result.removeValue(forKey: bundledHelpersVariable)
        }
        return result
    }

    /// The same thing as one line of `sh`, for a script Plantoir generates.
    ///
    /// The literal directories are single-quoted because "Application Support"
    /// has a space in it and a home folder can contain a quote; `$PATH` is
    /// left outside the quotes so the shell still expands it.
    static func exportLine(
        inHomeFolder homeFolder: URL = RealHome.forFiles
    ) -> String {
        let directories: String = searchDirectories(inHomeFolder: homeFolder).joined(separator: ":")
        return "export PATH=" + shellQuoted(directories) + ":\"$PATH\""
    }

    /// One value, safe to drop into a generated shell script.
    ///
    /// Single quotes stop the shell reading anything inside them; the only
    /// character that can end them is a quote itself, which is closed,
    /// escaped and reopened. Moved here from `ScheduledDeploy`, which still
    /// calls through to it, so that the app has one answer to "how is a path
    /// put into a script" rather than two that can drift.
    static func shellQuoted(_ value: String) -> String {
        let escaped: String = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
