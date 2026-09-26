import XCTest
import Darwin

/// The ONE door a UI test launches Plantoir through (#154).
///
/// **What it gives the app.** A state folder of its own, passed as
/// `--state-dir`, which stands in for the home folder for everything the app
/// resolves: its breadcrumb trail, its preferences, scheduled-publish notes,
/// built websites, the assistant's files. Without it, the app a UI test drives
/// does not know it is under test — XCTest is loaded in this RUNNER, not in
/// the app — and it wrote the teacher's real trail and real preferences.
/// `-ApplePersistenceIgnoreState YES` keeps it from restoring (or saving)
/// the teacher's windows too.
///
/// **What it cannot give it.** The launchers the app runs take `HOME` from
/// their environment, which is the real one — so a test here must run STUB
/// launchers only (`writeStubPreviewScript`, the stub `deploy.sh`), never a
/// real one. `documentation/09-mac-app.md` → "Testing: the UI target keeps
/// its state in `--state-dir`" says why that was not changed.
///
/// `UITestLaunchTripwireTests`, in the unit suite, fails if a UI test file
/// other than this one (and the marketing captures, which need the real
/// toolchain) creates an `XCUIApplication`.
struct IsolatedLaunch {

    // MARK: - Stored properties

    /// The app, already launched.
    let application: XCUIApplication

    /// The folder standing in for the home folder.
    let stateDirectory: URL

    /// The working folder the app was pointed at.
    let workspaceURL: URL

    /// What happened to the real assistant choice, for a skip or failure
    /// message to say — nil when weights were not asked for.
    let modelChoiceNote: String?

    // MARK: - Computed properties

    /// The trail this launch writes: the redirected one.
    var trailURL: URL {
        return stateDirectory.appendingPathComponent("Library/Logs/Plantoir/activity.txt")
    }

    /// The preferences file this launch writes: the redirected one.
    var preferencesURL: URL {
        return stateDirectory.appendingPathComponent("Library/Preferences/ca.russellgordon.Plantoir.plist")
    }

    /// Where the assistant looks for its weights under this launch.
    var modelsURL: URL {
        return IsolatedLaunch.modelsFolder(inHome: stateDirectory)
    }

    // MARK: - Functions

    /// Launches Plantoir on a working folder, with a fresh state folder.
    ///
    /// `workspace` nil means the one named by this runner's own
    /// `UITEST_WORKSPACE`, or a fresh fixture — so plain Cmd-U needs no setup.
    ///
    /// `linkRealAssistantWeights` links each real `*.gguf` into the state
    /// folder, ONE FILE AT A TIME: a link to the whole models folder would let
    /// a Settings "Remove" delete the teacher's real weights and put a
    /// download in their real folder. It also passes the real assistant
    /// choice through the argument domain, read from the real preferences
    /// FILE (never written).
    static func launch(
        workspace: URL? = nil,
        extraArguments: [String] = [],
        linkRealAssistantWeights: Bool = false
    ) throws -> IsolatedLaunch {
        let workspaceURL: URL
        if let workspace {
            workspaceURL = workspace
        } else if let fixturePath = ProcessInfo.processInfo.environment["UITEST_WORKSPACE"] {
            workspaceURL = URL(fileURLWithPath: fixturePath)
        } else {
            workspaceURL = try FixtureWorkspace.materialize()
        }

        let stateDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plantoir-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)

        var arguments: [String] = ["--state-dir", stateDirectory.path, "-ApplePersistenceIgnoreState", "YES"]
        var modelChoiceNote: String? = nil
        if linkRealAssistantWeights {
            try linkWeights(into: modelsFolder(inHome: stateDirectory))
            if let choice = realPreference(named: "assistantModelChoice") as? String {
                arguments += ["-assistantModelChoice", choice]
                modelChoiceNote = "the real assistant choice (\(choice)) was passed"
            } else {
                modelChoiceNote = "the real assistant choice could not be read, so the automatic tier was used"
            }
        }
        arguments += extraArguments

        let application: XCUIApplication = XCUIApplication()
        application.launchEnvironment["UITEST_WORKSPACE"] = workspaceURL.path
        application.launchArguments += arguments
        application.launch()
        return IsolatedLaunch(
            application: application,
            stateDirectory: stateDirectory,
            workspaceURL: workspaceURL,
            modelChoiceNote: modelChoiceNote
        )
    }

    /// The lines of the redirected trail, or none when it is not there yet.
    func trailLines() -> [String] {
        guard let text = try? String(contentsOf: trailURL, encoding: .utf8) else {
            return []
        }
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    /// The redirected preferences, as a dictionary; empty when not written yet.
    func preferences() -> [String: Any] {
        guard let data = try? Data(contentsOf: preferencesURL) else {
            return [:]
        }
        let parsed: Any? = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return (parsed as? [String: Any]) ?? [:]
    }

    /// The teacher's REAL home folder, from the password database.
    ///
    /// A UI test runner is sandboxed, so `homeDirectoryForCurrentUser` and
    /// `HOME` both give it a container path. The one place in the UI target
    /// that asks; `RealHomeTripwireTests.testAllowances` names it.
    static func realHome() -> URL {
        return URL(fileURLWithPath: String(cString: getpwuid(getuid()).pointee.pw_dir), isDirectory: true)
    }

    /// `<home>/Library/Application Support/Plantoir/models`.
    static func modelsFolder(inHome home: URL) -> URL {
        return home.appendingPathComponent("Library/Application Support/Plantoir/models", isDirectory: true)
    }

    /// The real weights' file names, or none.
    static func realWeightNames() -> [String] {
        let names: [String] = (try? FileManager.default.contentsOfDirectory(
            atPath: modelsFolder(inHome: realHome()).path
        )) ?? []
        var weights: [String] = []
        for name in names where name.hasSuffix(".gguf") {
            weights.append(name)
        }
        return weights
    }

    /// One symbolic link per real weights file, into `folder`.
    static func linkWeights(into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let realFolder: URL = modelsFolder(inHome: realHome())
        for name in realWeightNames() {
            try FileManager.default.createSymbolicLink(
                at: folder.appendingPathComponent(name),
                withDestinationURL: realFolder.appendingPathComponent(name)
            )
        }
    }

    /// The real preferences file, READ ONLY.
    static var realPreferencesURL: URL {
        return realHome().appendingPathComponent("Library/Preferences/ca.russellgordon.Plantoir.plist")
    }

    /// One value from the real preferences file, or nil if it cannot be read.
    /// Never written, and never attached to a result.
    static func realPreference(named key: String) -> Any? {
        guard let data = try? Data(contentsOf: realPreferencesURL) else {
            return nil
        }
        let parsed: Any? = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return (parsed as? [String: Any])?[key]
    }
}
