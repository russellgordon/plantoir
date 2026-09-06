import AppKit
import Foundation
import Observation

/// The app's top-level state: which working folder is active, the courses
/// found inside it, and what is selected in the sidebar.
///
/// The working folder is the one teachers use with the command-line
/// toolchain — it contains `setup.sh`, `preview.sh`, `deploy.sh`, and a
/// `courses/` directory.
@Observable
class WorkspaceModel {

    // MARK: - Stored properties

    /// Where the last-used folder is remembered. Injected so a test can
    /// never write into the real preferences — which is how a test run used
    /// to leave the app pointing at a deleted temporary folder.
    private let defaults: UserDefaults

    /// The key holding the most recently chosen folder.
    static let storedPathKey: String = "workspacePath"

    /// Working folders whose `.toolchain` has already been brought up to date
    /// in this run of the app. See `refreshToolchain` for why once is enough.
    static var foldersWithFreshToolchain: Set<String> = []

    /// True when the hosted test suite is running. Tests drive the real
    /// window, and must not leave the teacher pointed at a fixture folder
    /// that is deleted when the run ends.
    static let isRunningTests: Bool = NSClassFromString("XCTestCase") != nil

    /// The models belonging to open windows, in the order they appeared.
    /// Windows register themselves so the in-app tests can drive the real
    /// interface rather than a model nothing is showing.
    static private(set) var windowModels: [WorkspaceModel] = []

    /// The working folder of the window most recently key, so a new window
    /// can open where the teacher just was.
    static var mostRecentKeyFolderPath: String?

    /// Takes the folder a brand-new window should open in, right now — the
    /// key window's. Only for MID-SESSION windows: the restoration claims
    /// have closed, so there is nothing to wait for, and deciding before
    /// the first frame renders is what keeps the picker from flashing. At
    /// launch this does nothing; the folder waits for the window claims,
    /// which need the window's settled frame.
    func adoptFolderForNewWindow() {
        guard workspaceURL == nil else {
            return
        }
        guard Date() > WindowFolderMemory.claimsOpenUntil else {
            return
        }
        var otherOpenFolderPaths: [String] = []
        for existing in WorkspaceModel.windowModels {
            if existing !== self, let path = existing.workspaceURL?.path {
                otherOpenFolderPaths.append(path)
            }
        }
        if let path = WorkspaceModel.folderForNewWindow(
            otherOpenFolderPaths: otherOpenFolderPaths,
            mostRecentKeyPath: WorkspaceModel.mostRecentKeyFolderPath
        ) {
            adoptRestoredPath(path)
        }
    }

    /// What a brand-new window should open to. With no other windows open,
    /// nothing — the folder picker. Otherwise the folder of the window
    /// that was key when the command ran, falling back to any open
    /// window's folder if the remembered key folder is no longer among
    /// them.
    static func folderForNewWindow(otherOpenFolderPaths: [String], mostRecentKeyPath: String?) -> String? {
        if otherOpenFolderPaths.isEmpty {
            return nil
        }
        if let mostRecentKeyPath, otherOpenFolderPaths.contains(mostRecentKeyPath) {
            return mostRecentKeyPath
        }
        return otherOpenFolderPaths[0]
    }

    static func registerWindowModel(_ model: WorkspaceModel) {
        for existing in windowModels {
            if existing === model {
                return
            }
        }
        windowModels.append(model)
    }

    /// True once the app has begun quitting. Windows closing as part of
    /// the quit must not rewrite the remembered list — that is the list
    /// the next launch restores from.
    static var isTerminating: Bool = false

    /// A window has closed, so it should no longer be remembered as open.
    static func unregisterWindowModel(_ model: WorkspaceModel) {
        if isTerminating {
            return
        }
        var remaining: [WorkspaceModel] = []
        for existing in windowModels {
            if existing !== model {
                remaining.append(existing)
            }
        }
        windowModels = remaining
        rememberOpenFolders()
        if let path = model.workspaceURL?.path {
            releaseFolderIfUnused(path)
        }
    }

    /// True when this model is one a window shows — as against one the
    /// assistant or the MCP server made for its own reading.
    static func isShownInAWindow(_ model: WorkspaceModel) -> Bool {
        for existing in windowModels {
            if existing === model {
                return true
            }
        }
        return false
    }

    /// True while some open window is working in this folder.
    static func folderIsInUse(_ path: String) -> Bool {
        for model in windowModels {
            if model.workspaceURL?.path == path {
                return true
            }
        }
        return false
    }

    /// Lets a folder's container rest once no window is using the folder.
    static func releaseFolderIfUnused(_ path: String) {
        if folderIsInUse(path) {
            return
        }
        FolderContainers.stopContainer(forFolder: path)
    }

    /// Writes down which folder each open window is in, paired with the
    /// window's frame so a restored window can find its own.
    static func rememberOpenFolders(defaults: UserDefaults = UserDefaults.standard) {
        var entries: [WindowFolderMemory.Entry] = []
        for model in windowModels {
            if let path = model.workspaceURL?.path {
                let frame: String = model.window.map { NSStringFromRect($0.frame) } ?? ""
                entries.append(WindowFolderMemory.Entry(
                    path: path,
                    frame: frame,
                    expandedCourses: model.expandedCourseCodes.sorted(),
                    archivedExpanded: model.isShowingArchived,
                    backupsExpanded: model.isShowingBackups,
                    selection: model.selection?.storageValue ?? ""
                ))
            }
        }
        WindowFolderMemory.record(entries, defaults: defaults)
    }

    /// The active working folder, or nil before one has been chosen.
    var workspaceURL: URL?

    /// True while this window is still waiting to learn which restored
    /// folder is its own — the brief moment between launch and the claim
    /// resolving. While true, the window shows a quiet holding view
    /// instead of flashing the folder picker it is about to replace.
    var isResolvingRestoredFolder: Bool = false

    /// Which courses' sidebar disclosure triangles are open, and whether
    /// the Archived group is — per window, remembered with the folder so
    /// a restored window shows the same courses unfolded.
    var expandedCourseCodes: Set<String> = []
    var isShowingArchived: Bool = false

    /// The window this model belongs to, once it is on screen. Used only
    /// to read the frame; never retained.
    @ObservationIgnored weak var window: NSWindow?

    /// True while the New Course wizard sheet should be shown.
    var isShowingNewCourseWizard: Bool = false

    /// True while a freshly chosen folder is being set up.
    ///
    /// Setting up a folder mirrors the whole build recipe into it, and that
    /// is 12,091 files and 65 MB — 2.4 seconds of pure copying on a fast
    /// NVMe, and far longer on an older disk, a USB drive or a folder the
    /// system is syncing. Done on the main thread it is a beachball with
    /// nothing on screen to explain it, which reads as a hang rather than
    /// as work. The button watches this to say so instead.
    var isInitializingWorkspace: Bool = false

    /// The courses discovered inside `<workspace>/courses/`.
    var courses: [Course] = []

    /// Courses and sections the teacher has removed, newest first.
    var archivedItems: [ArchivedItem] = []

    /// The archived item a confirmation is being shown for, if any.
    var restoreRequest: ArchivedItem?

    /// The archived item a DELETE confirmation is being shown for, if any.
    var archiveDeleteRequest: ArchivedItem?

    /// Why a restore could not go ahead, shown as an alert.
    var restoreProblem: String?

    /// Saved copies of whole courses, newest first.
    var backupItems: [BackupItem] = []

    /// Whether the sidebar's Backups group is open.
    var isShowingBackups: Bool = false

    /// The backup a restore confirmation is being shown for, if any.
    var backupRestoreRequest: BackupItem?

    /// The backup a delete confirmation is being shown for, if any.
    var backupDeleteRequest: BackupItem?

    /// Why a backup action could not go ahead, shown as an alert.
    var backupProblem: String?

    /// The course whose code is being edited IN PLACE in the sidebar, or
    /// nil when nothing is being renamed.
    ///
    /// It lives on the window's model rather than in the sidebar's own state
    /// because two things start a rename — the Edit menu and the Return key
    /// — and a menu command can only reach the focused window's model.
    var renamingCourseCode: String?

    /// Why a rename could not go ahead, shown as an alert.
    var renameProblem: String?

    /// A rename waiting on the teacher's answer about Obsidian, because
    /// this course's vault is open in it right now.
    var obsidianRenameRequest: CourseRenamer.ObsidianRequest?

    /// What a rename that SUCCEEDED has to tell the teacher about — turning
    /// off a scheduled publish, so far. Nil in the ordinary case, which gets
    /// no interruption.
    var renameNotice: CourseRenamer.Notice?

    /// The current sidebar selection.
    var selection: SidebarSelection?

    /// True while the folder-picker sheet should be shown.
    var isChoosingWorkspace: Bool = false

    /// Text typed into the sidebar's filter field.
    var filterText: String = ""

    /// A human-readable problem with the current folder, if any.
    var workspaceProblem: String?

    /// True when the chosen folder is empty and can be set up as a fresh
    /// working folder by copying the launcher scripts in.
    var workspaceCanBeInitialized: Bool = false

    /// True when the chosen folder is neither a working folder nor empty.
    /// The picker stays up (its guidance already covers what to choose)
    /// without displaying an error — this state is not the teacher's
    /// fault, just an unfinished choice.
    var workspaceIsUnrecognized: Bool = false

    /// The cloud service keeping this working folder in sync, when one is
    /// — see `CloudSyncedFolder` for what that costs and why it is allowed.
    /// Nil for an ordinary folder.
    var syncedFolder: CloudSyncedFolder?

    /// True while the picker waits for the teacher to decide about a synced
    /// folder they have just CHOSEN: use it anyway, or pick a different one.
    /// The moment they can still change their mind for free, so it is a
    /// choice here and only a notice later.
    var needsCloudSyncDecision: Bool = false

    /// True while the window shows the quiet, dismissable notice about a
    /// synced folder it RESTORED rather than one the teacher just chose — a
    /// folder that was moved into iCloud after it was set up, or set up
    /// before Plantoir could tell. Never a dialog: a folder that opens on
    /// every launch must not nag on every launch.
    var isShowingCloudSyncNotice: Bool = false

    /// The preferences key holding the folders whose sync note the teacher
    /// has already seen and gone past. Per folder, not per app: a second
    /// synced folder deserves its own note.
    static let acknowledgedSyncedFoldersKey: String = "acknowledgedSyncedFolders"

    /// How a folder is recognised as synced. Replaceable so a test can make
    /// a temporary folder read as synced without putting one in iCloud.
    static var syncDetector: (URL) -> CloudSyncedFolder? = { folderURL in
        return CloudSyncDetector.syncedFolder(at: folderURL)
    }

    /// Set by the test harness (UITEST_WORKSPACE) to bypass persistence.
    private let isUnderUITest: Bool

    // MARK: - Computed properties

    var coursesDirectoryURL: URL? {
        if let workspaceURL {
            return workspaceURL.appendingPathComponent("courses")
        }
        return nil
    }

    /// The courses the sidebar should show, honouring the filter field.
    /// Matching is case-insensitive across the code and the course name.
    var filteredCourses: [Course] {
        let query: String = filterText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return courses
        }
        var result: [Course] = []
        for course in courses {
            let codeMatches: Bool = course.code.localizedCaseInsensitiveContains(query)
            let nameMatches: Bool = course.configuration.courseName.localizedCaseInsensitiveContains(query)
            if codeMatches || nameMatches {
                result.append(course)
            }
        }
        return result
    }

    /// The course object matching the sidebar selection, if any.
    var selectedCourse: Course? {
        var selectedCode: String?
        switch selection {
        case .course(let code):
            selectedCode = code
        case .section(let code, _):
            selectedCode = code
        case .archived:
            // An archived item belongs to no live course.
            selectedCode = nil
        case .backup:
            // A backup is a copy, not the live course itself.
            selectedCode = nil
        case nil:
            selectedCode = nil
        }
        guard let selectedCode else {
            return nil
        }
        for course in courses {
            if course.code == selectedCode {
                return course
            }
        }
        return nil
    }

    // MARK: - Initializer

    init(defaults: UserDefaults = UserDefaults.standard) {
        self.defaults = defaults
        // A UI test can point the app at a fixture folder via the
        // environment, which also keeps test runs out of the preferences.
        let environment: [String: String] = ProcessInfo.processInfo.environment
        if let fixturePath = environment["UITEST_WORKSPACE"] {
            self.isUnderUITest = true
            self.workspaceURL = URL(fileURLWithPath: fixturePath)
        } else {
            self.isUnderUITest = false
            WorkspaceModel.migratePreferencesFromOldName(into: defaults)
            // No folder is adopted here. A RESTORED window's folder arrives
            // through the window claims; a brand-new window inherits from
            // the window that was key when it was opened, or — when it is
            // the only window — starts with the picker. The last-chosen
            // path stays recorded for migration, but a lone new window
            // silently opening on whatever folder was used last proved
            // surprising.
        }
        reloadCourses()
    }

    /// Whether this model may record the folder for next time.
    ///
    /// A test may exercise remembering with a store of its own, but nothing
    /// under test may write the REAL preference — that is how a test run
    /// used to leave the app pointing at a deleted fixture folder.
    private var canRememberChoice: Bool {
        if isUnderUITest {
            return false
        }
        if WorkspaceModel.isRunningTests && defaults === UserDefaults.standard {
            return false
        }
        return true
    }

    /// Brings settings across from the app's earlier bundle identifier
    /// (ca.russellgordon.QuartzTeachers), once, so renaming the app does
    /// not cost anyone their working folder or remembered windows.
    static func migratePreferencesFromOldName(into defaults: UserDefaults) {
        if isRunningTests || defaults != UserDefaults.standard {
            return
        }
        if defaults.string(forKey: storedPathKey) != nil {
            return
        }
        guard let old = UserDefaults(suiteName: "ca.russellgordon.QuartzTeachers") else {
            return
        }
        if let path = old.string(forKey: storedPathKey) {
            defaults.set(path, forKey: storedPathKey)
        }
        if let folders = old.array(forKey: WindowFolderMemory.storageKey) {
            defaults.set(folders, forKey: WindowFolderMemory.storageKey)
        }
    }

    /// True when a folder is actually there to be worked in.
    static func folderExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    // MARK: - Functions

    /// Adopts a new working folder, validates it, and remembers it.
    func chooseWorkspace(at url: URL) {
        let previousPath: String? = workspaceURL?.path
        workspaceURL = url
        ActivityTrail.note(.workingFolderOpened, "opened the working folder " + url.path)
        if canRememberChoice {
            // Remembered app-wide so a NEW window opens where the last one
            // left off; each window then keeps its own choice in its scene.
            defaults.set(url.path, forKey: WorkspaceModel.storedPathKey)
        }
        reloadCourses()
        // Choosing the folder this window already shows is not a new
        // choice — a teacher who does that with the notice showing would
        // otherwise find their courses hidden behind the picker.
        noticeCloudSync(folderWasChosen: previousPath != url.path)
        if let previousPath, previousPath != url.path {
            WorkspaceModel.releaseFolderIfUnused(previousPath)
        }
    }

    // MARK: - A folder a cloud service keeps in sync

    /// Works out whether the folder just adopted is synced, and what — if
    /// anything — to show about it.
    ///
    /// A folder the teacher has already been told about shows nothing; the
    /// note is per folder and shown once. Otherwise a folder they CHOSE gets
    /// the picker's choice, and a folder the window RESTORED gets the notice.
    private func noticeCloudSync(folderWasChosen: Bool) {
        needsCloudSyncDecision = false
        isShowingCloudSyncNotice = false
        guard let workspaceURL else {
            syncedFolder = nil
            return
        }
        syncedFolder = WorkspaceModel.syncDetector(workspaceURL)
        guard let syncedFolder else {
            return
        }
        // A folder the picker will not take anyway — neither a working
        // folder nor empty — gets no question about syncing: the teacher is
        // about to choose again, and a note about a folder they cannot use
        // is noise beside the guidance that says what to choose.
        if workspaceIsUnrecognized {
            return
        }
        // Keyed by the RESOLVED path the detector answers with, so a folder
        // reached through a symlink (`~/Dropbox` → `~/Library/CloudStorage/
        // Dropbox`) is one folder, told about once.
        if hasAcknowledgedCloudSync(forPath: syncedFolder.folderPath) {
            return
        }
        // Only a model that belongs to a window records the line: the
        // assistant and the MCP server adopt folders on models nothing
        // shows, and "noticed" from those would say Plantoir told the
        // teacher something it never did.
        if WorkspaceModel.isShownInAWindow(self) {
            ActivityTrail.note(
                .syncedFolderNoticed,
                "noticed the working folder is kept in sync with \(syncedFolder.serviceName) — " + LogRedactor.redacting(syncedFolder.folderPath)
            )
        }
        if folderWasChosen {
            needsCloudSyncDecision = true
        } else {
            isShowingCloudSyncNotice = true
        }
    }

    /// Whether the teacher has already gone past the note for this folder.
    func hasAcknowledgedCloudSync(forPath path: String) -> Bool {
        let acknowledgedPaths: [String] = defaults.stringArray(forKey: WorkspaceModel.acknowledgedSyncedFoldersKey) ?? []
        return acknowledgedPaths.contains(path)
    }

    /// The teacher has read the note and chosen to go on — from the picker's
    /// "Use This Folder Anyway", from setting up an empty synced folder, or
    /// from dismissing the window's notice. Remembered for this folder so it
    /// is not said again.
    func acknowledgeCloudSync() {
        guard let workspaceURL, let syncedFolder else {
            needsCloudSyncDecision = false
            isShowingCloudSyncNotice = false
            return
        }
        let wasAChoice: Bool = needsCloudSyncDecision
        needsCloudSyncDecision = false
        isShowingCloudSyncNotice = false
        if canRememberChoice {
            var acknowledgedPaths: [String] = defaults.stringArray(forKey: WorkspaceModel.acknowledgedSyncedFoldersKey) ?? []
            if !acknowledgedPaths.contains(syncedFolder.folderPath) {
                acknowledgedPaths.append(syncedFolder.folderPath)
                defaults.set(acknowledgedPaths, forKey: WorkspaceModel.acknowledgedSyncedFoldersKey)
            }
        }
        // The same folder open in a second window: its notice goes too,
        // or "Got It" here leaves it there until relaunch, against the
        // once-per-folder rule.
        for other in WorkspaceModel.windowModels {
            if other !== self && other.workspaceURL?.path == workspaceURL.path {
                other.needsCloudSyncDecision = false
                other.isShowingCloudSyncNotice = false
            }
        }
        let howTheyWentOn: String = wasAChoice
            ? "chose to use the working folder anyway"
            : "read the note about the working folder"
        ActivityTrail.note(.syncedFolderAccepted, howTheyWentOn + ", kept in sync with \(syncedFolder.serviceName)")
    }

    /// Adopts the folder a window remembered from its last session.
    ///
    /// Windows are restored one by one, each with its own saved folder, so
    /// this runs per window rather than once for the app.
    func adoptRestoredPath(_ path: String) {
        if path.isEmpty || isUnderUITest {
            return
        }
        if !WorkspaceModel.folderExists(atPath: path) {
            return
        }
        if workspaceURL?.path == path {
            return
        }
        workspaceURL = URL(fileURLWithPath: path)
        reloadCourses()
        noticeCloudSync(folderWasChosen: false)
    }

    /// Keeps this folder's launcher scripts current.
    ///
    /// A working folder carries its own copy of the launchers, taken when
    /// the folder was set up — and a copy taken once is a copy that goes
    /// stale, exactly as the image and the container used to. Whenever the
    /// app works in a folder, any launcher that differs from the app's
    /// bundled (current) copy is replaced. These are toolchain files, not
    /// the teacher's own work, so replacing them is correct.
    func refreshLaunchersIfNeeded() {
        guard let workspaceURL else {
            return
        }
        // Test fixtures use stub launchers on purpose; leave them alone.
        if isUnderUITest || WorkspaceModel.isRunningTests {
            return
        }
        var sources: [String: URL] = [:]
        for scriptName in ["setup.sh", "preview.sh", "deploy.sh"] {
            if let bundledURL = Bundle.main.url(forResource: scriptName, withExtension: nil) {
                sources[scriptName] = bundledURL
            }
        }
        let refreshed: [String] = WorkspaceModel.refreshLaunchers(in: workspaceURL, from: sources)
        if !refreshed.isEmpty {
            AppLog.interface.info("refreshed launchers in \(LogRedactor.redacting(workspaceURL.path), privacy: .public): \(refreshed.joined(separator: ", "), privacy: .public)")
        }
        refreshToolchain(in: workspaceURL)
    }

    /// Keeps the folder's `.toolchain/` — the recipe the image is built
    /// from — mirroring the app's bundled copy. The launchers hash this
    /// folder to name the image, so a changed recipe rebuilds the image
    /// and, through the image-mismatch check, recreates the container.
    /// One updater (the app) now drives every layer.
    func refreshToolchain(in workspaceURL: URL) {
        WorkspaceModel.mirrorToolchain(into: workspaceURL)
    }

    /// The mirror itself, as a static so it can run on a background thread
    /// without touching a model another thread owns. It reads only the app's
    /// own bundle and the folder, plus the shared once-per-run set above.
    static func mirrorToolchain(into workspaceURL: URL) {
        if !shouldMirrorToolchain(into: workspaceURL) {
            return
        }
        noteToolchainMirrored(into: workspaceURL)
        let changed: Int = copyToolchainFiles(into: workspaceURL)
        if changed > 0 {
            AppLog.interface.info("refreshed .toolchain in \(LogRedactor.redacting(workspaceURL.path), privacy: .public): \(changed) file(s)")
        }
    }

    /// Whether the mirror has anything to do — the once-per-folder-per-run
    /// question, which reads the shared set and so stays on the main actor.
    static func shouldMirrorToolchain(into workspaceURL: URL) -> Bool {
        let fileManager: FileManager = FileManager.default
        // Only a folder that is already a workspace gets a toolchain.
        if !fileManager.fileExists(atPath: workspaceURL.appendingPathComponent("preview.sh").path) {
            return false
        }

        let toolchainURL: URL = workspaceURL.appendingPathComponent(".toolchain")
        let dockerfileURL: URL = toolchainURL.appendingPathComponent("Dockerfile")

        // Once per folder per run of the app, and that is not a shortcut: the
        // SOURCE is the app's own bundle, which cannot change while the app
        // is running, so a second mirror of the same folder cannot find
        // anything the first one missed — unless the destination is actually
        // missing its files on disk.
        //
        // It used to run inside every `reloadCourses()` — which is after
        // every rename, backup, restore and archive — and cost 0.37 s each
        // time even with nothing to do. That is what a teacher felt as a
        // pause between pressing Return on a renamed course and the field
        // going away. (Before the mirror was made cheap it was 3.8 s.)
        if WorkspaceModel.foldersWithFreshToolchain.contains(workspaceURL.path) &&
           fileManager.fileExists(atPath: dockerfileURL.path) {
            return false
        }
        return true
    }

    /// Records that this folder's mirror is up to date for this run.
    static func noteToolchainMirrored(into workspaceURL: URL) {
        WorkspaceModel.foldersWithFreshToolchain.insert(workspaceURL.path)
    }

    /// The copying itself — the expensive half, and the only half that has
    /// to leave the main thread.
    ///
    /// `nonisolated` on purpose: it reads the app's own bundle, which cannot
    /// change while the app runs, and writes into one folder. It touches no
    /// model state and no shared set, so there is nothing here for a
    /// background thread to race against. Answers how many files it wrote.
    nonisolated static func copyToolchainFiles(into workspaceURL: URL) -> Int {
        let toolchainURL: URL = workspaceURL.appendingPathComponent(".toolchain")
        var changed: Int = 0
        var rootFiles: [String] = ["Dockerfile"]
        rootFiles += ["setup.sh", "preview.sh", "deploy.sh"]
        rootFiles += ["setup.bat", "preview.bat", "deploy.bat"]
        rootFiles += ["setup.ps1", "preview.ps1", "deploy.ps1"]
        for name in rootFiles {
            if let sourceURL = Bundle.main.url(forResource: name, withExtension: nil) {
                changed += WorkspaceModel.syncFile(from: sourceURL, to: toolchainURL.appendingPathComponent(name))
            }
        }
        // Whole folders, mirrored (extraneous files removed — they would
        // change the hash and force rebuilds for nothing).
        for folderName in ["patches", "scripts", "support", "contracts"] {
            if let sourceURL = Bundle.main.url(forResource: folderName, withExtension: nil) {
                changed += WorkspaceModel.syncDirectory(from: sourceURL, to: toolchainURL.appendingPathComponent(folderName))
            }
        }
        return changed
    }

    /// Copies one file when the destination differs or is missing.
    nonisolated static func syncFile(from sourceURL: URL, to destinationURL: URL) -> Int {
        let fileManager: FileManager = FileManager.default

        // The cheap question first: same size, same modification date.
        //
        // This is what makes the mirror usable. `support/` alone is 61 MB
        // across 11,354 files, and reading BOTH copies of every one of them to
        // prove they match cost 3.8 seconds — every time the courses were
        // reloaded, which is after every rename, backup, restore and archive.
        // Two stat calls answer the same question for almost all of them.
        if WorkspaceModel.filesLookIdentical(sourceURL, destinationURL) {
            return 0
        }

        guard let sourceData = try? Data(contentsOf: sourceURL) else {
            return 0
        }
        if let existing = try? Data(contentsOf: destinationURL), existing == sourceData {
            // Same bytes, different stamp — which is every file in the bundle
            // the first time the app is rebuilt. Copy the stamp across so the
            // cheap check can answer next time instead of re-reading 61 MB
            // for the rest of the session.
            WorkspaceModel.copyModificationDate(from: sourceURL, to: destinationURL)
            return 0
        }
        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sourceData.write(to: destinationURL, options: [.atomic])
            if destinationURL.pathExtension == "sh" {
                try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
            }
            WorkspaceModel.copyModificationDate(from: sourceURL, to: destinationURL)
            return 1
        } catch {
            return 0
        }
    }

    /// Whether two files can be taken for the same file without reading them.
    ///
    /// Size AND modification date, both. Either alone is far too easy to
    /// match by accident. A file edited in place so cleverly that it keeps
    /// both would be missed, and that is the trade: the alternative is
    /// reading 122 MB to answer a question two stat calls almost always
    /// answer correctly. The dates only line up because `syncFile` stamps
    /// what it writes — see `copyModificationDate`.
    nonisolated static func filesLookIdentical(_ oneURL: URL, _ otherURL: URL) -> Bool {
        let wanted: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let one = try? oneURL.resourceValues(forKeys: wanted),
              let other = try? otherURL.resourceValues(forKeys: wanted),
              let oneSize = one.fileSize,
              let otherSize = other.fileSize,
              let oneDate = one.contentModificationDate,
              let otherDate = other.contentModificationDate else {
            return false
        }
        if oneSize != otherSize {
            return false
        }
        // A tolerance rather than equality: a date makes a round trip through
        // the file system as a floating-point number of seconds, and an exact
        // comparison can fail on the last bit for two stamps that are the
        // same moment. A millisecond is far tighter than any real edit.
        return abs(oneDate.timeIntervalSince(otherDate)) < 0.001
    }

    /// Gives the copy the original's modification date, so the cheap check
    /// recognises it next time.
    nonisolated static func copyModificationDate(from sourceURL: URL, to destinationURL: URL) {
        guard let date = try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return
        }
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: destinationURL.path)
    }

    /// Where a file sits inside a folder, as a relative path.
    ///
    /// This is arithmetic on strings, and it was wrong in a way that only
    /// shows up on some paths: the enumerator hands back RESOLVED paths, so
    /// a folder reached through a symlink (`/var/…`, which is really
    /// `/private/var/…`) does not match the prefix it was asked about. The
    /// old code took a fixed number of characters off the front regardless,
    /// produced nonsense, and the mirror then decided every file in the
    /// destination was extraneous — deleting the whole toolchain and copying
    /// it back on every pass. A working folder on the Desktop never showed
    /// it; one under a symlinked path would have.
    ///
    /// Returns nil when the file is not inside the folder at all, which the
    /// callers treat as "not mine to touch".
    nonisolated static func relativePath(of fileURL: URL, under folderURL: URL) -> String? {
        let candidates: [(String, String)] = [
            (fileURL.path, folderURL.path),
            (fileURL.resolvingSymlinksInPath().path, folderURL.resolvingSymlinksInPath().path),
        ]
        for (filePath, folderPath) in candidates {
            if filePath.hasPrefix(folderPath + "/") {
                return String(filePath.dropFirst(folderPath.count + 1))
            }
        }
        return nil
    }

    nonisolated static func syncDirectory(from sourceURL: URL, to destinationURL: URL) -> Int {
        let fileManager: FileManager = FileManager.default
        var changed: Int = 0

        // A SET, not an array. This was an array, and the removal pass below
        // asked it `contains` once per destination file — 11,354 files each
        // scanning an 11,354-element list is around 129 million string
        // comparisons for a folder in which nothing had changed.
        var sourceFiles: Set<String> = []
        if let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                let isFile: Bool = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                if isFile {
                    guard let relative = WorkspaceModel.relativePath(of: fileURL, under: sourceURL) else {
                        continue
                    }
                    sourceFiles.insert(relative)
                    changed += WorkspaceModel.syncFile(from: fileURL, to: destinationURL.appendingPathComponent(relative))
                }
            }
        }

        if let enumerator = fileManager.enumerator(at: destinationURL, includingPropertiesForKeys: [.isRegularFileKey]) {
            var toRemove: [URL] = []
            for case let fileURL as URL in enumerator {
                let isFile: Bool = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                if isFile {
                    guard let relative = WorkspaceModel.relativePath(of: fileURL, under: destinationURL) else {
                        // Not recognisably inside the folder being mirrored,
                        // so not ours to delete.
                        continue
                    }
                    if !sourceFiles.contains(relative) {
                        toRemove.append(fileURL)
                    }
                }
            }
            for fileURL in toRemove {
                try? fileManager.removeItem(at: fileURL)
                changed += 1
            }
        }
        return changed
    }

    /// Replaces any launcher whose content differs from the current copy.
    /// Only files that already exist are touched: a folder without
    /// launchers is a folder that has not been initialized, which is the
    /// picker's business, not this method's.
    static func refreshLaunchers(in workspaceURL: URL, from sources: [String: URL]) -> [String] {
        let fileManager: FileManager = FileManager.default
        var refreshed: [String] = []
        for (scriptName, sourceURL) in sources {
            let destinationURL: URL = workspaceURL.appendingPathComponent(scriptName)
            if !fileManager.fileExists(atPath: destinationURL.path) {
                continue
            }
            guard let current = try? Data(contentsOf: sourceURL),
                  let existing = try? Data(contentsOf: destinationURL) else {
                continue
            }
            if current == existing {
                continue
            }
            do {
                try current.write(to: destinationURL, options: [.atomic])
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
                refreshed.append(scriptName)
            } catch {
                // A read-only folder is unusual but not fatal: the stale
                // script will fail loudly on its own if it matters.
                continue
            }
        }
        return refreshed.sorted()
    }

    /// Scans `<workspace>/courses/` for course folders containing a
    /// `course_config.json` and loads each one.
    func reloadCourses() {
        courses = []
        archivedItems = []
        workspaceProblem = nil
        refreshLaunchersIfNeeded()
        workspaceCanBeInitialized = false
        workspaceIsUnrecognized = false

        guard let workspaceURL else {
            return
        }

        let fileManager: FileManager = FileManager.default
        let previewScriptURL: URL = workspaceURL.appendingPathComponent("preview.sh")
        if !fileManager.fileExists(atPath: previewScriptURL.path) {
            if folderIsEffectivelyEmpty(workspaceURL) {
                // A brand-new folder: offer to set it up rather than
                // presenting an error.
                workspaceCanBeInitialized = true
            } else {
                // Not a working folder: keep the picker up, no error —
                // its own guidance already says what to choose.
                workspaceIsUnrecognized = true
            }
            return
        }

        guard let coursesDirectoryURL else {
            return
        }
        if !fileManager.fileExists(atPath: coursesDirectoryURL.path) {
            workspaceProblem = "There are no courses in this folder yet. Click New Course to create your first one."
            return
        }

        var loadedCourses: [Course] = []
        var entryURLs: [URL] = []
        do {
            entryURLs = try fileManager.contentsOfDirectory(
                at: coursesDirectoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            workspaceProblem = "Could not read the courses folder: \(error.localizedDescription)"
            return
        }

        for entryURL in entryURLs {
            let configURL: URL = entryURL.appendingPathComponent("course_config.json")
            if !fileManager.fileExists(atPath: configURL.path) {
                continue
            }
            do {
                let configuration: CourseConfiguration = try CourseConfiguration(contentsOf: configURL)
                let course: Course = Course(
                    code: entryURL.lastPathComponent,
                    directoryURL: entryURL,
                    configuration: configuration
                )
                loadedCourses.append(course)
            } catch {
                // A malformed config should not hide every other course.
                continue
            }
        }

        // Sort courses alphabetically by code for a stable sidebar.
        loadedCourses.sort { firstCourse, secondCourse in
            return firstCourse.code < secondCourse.code
        }
        courses = loadedCourses
        placeBuiltSitesOutsideTheFolder(for: loadedCourses, everythingIn: entryURLs)
        archivedItems = WorkspaceModel.findArchivedItems(in: coursesDirectoryURL)
        backupItems = WorkspaceModel.findBackupItems(in: coursesDirectoryURL)
    }

    /// Points every course's `.merged_output` at this folder's builds folder,
    /// outside the working folder, and clears builds left behind by courses
    /// that are no longer here.
    ///
    /// Run whenever the courses are read rather than once, because a folder
    /// can gain a course at any time — and because the answer for a course
    /// that is already linked is one `readlink`, so asking often costs
    /// nothing. Done SYNCHRONOUSLY, before anything can act on the courses
    /// just loaded: the work is a rename within one volume, and a build
    /// started against a `.merged_output` that is about to move would be
    /// writing into a folder nothing will read again.
    ///
    /// The launchers carry the same rule in shell — `preview.sh`, `deploy.sh`
    /// and `setup.sh` each ensure the link before they build — because a
    /// teacher at the command line and a deploy scheduled with launchd have no
    /// app to do it for them. See `contracts/shared-rules.json` →
    /// `buildOutputLocation`, which is where the rule itself is written down.
    private func placeBuiltSitesOutsideTheFolder(for loadedCourses: [Course], everythingIn entryURLs: [URL]) {
        guard let workspaceURL else {
            return
        }
        // Test fixtures build their own folders and must not reach into the
        // real Application Support; the rule itself is tested directly.
        if isUnderUITest || WorkspaceModel.isRunningTests {
            return
        }
        // Every folder in `courses/`, not only the courses that LOADED. A
        // course whose `course_config.json` will not parse is skipped above,
        // and treating it as gone would throw away the built website of the
        // one course whose teacher is already having a bad morning.
        var codesPresent: [String] = []
        for entryURL in entryURLs {
            codesPresent.append(entryURL.lastPathComponent)
        }
        for course in loadedCourses {
            // Never out from under a running build. Moving a course's output
            // while a preview is writing into it would break that build on a
            // path the teacher can see working, and the courses are reloaded
            // at plenty of moments a preview is live. A course previewing now
            // is simply left until the next reload; the launchers ensure the
            // link before every build in any case.
            if previewIsRunning(forCourse: course.code) {
                continue
            }
            do {
                let outcome: BuildOutputLocation.Outcome = try BuildOutputLocation.ensureLink(
                    courseDirectory: course.directoryURL,
                    workingFolderURL: workspaceURL
                )
                if outcome == .migrated {
                    ActivityTrail.note(
                        .builtSiteMovedOutOfTheFolder,
                        BuildOutputLocation.trailLine(courseCode: course.code)
                    )
                }
            } catch {
                // Not fatal: the launchers try again before every build, and
                // a build with no link still writes a real folder in the old
                // place rather than failing.
                AppLog.interface.error("could not place \(course.code, privacy: .public)'s built site outside the working folder: \(error.localizedDescription, privacy: .public)")
            }
        }
        BuildOutputLocation.discardBuildsForMissingCourses(
            workingFolderURL: workspaceURL,
            courseCodesPresent: codesPresent
        )
    }

    /// Whether any window is previewing a section of this course in this
    /// folder. Across windows, because the leases are shared.
    private func previewIsRunning(forCourse code: String) -> Bool {
        guard let workspaceURL else {
            return false
        }
        for lease in PreviewLeases.active {
            if lease.folderPath == workspaceURL.path && lease.courseCode == code {
                return true
            }
        }
        return false
    }

    /// The archived item matching a sidebar selection, if that is what is
    /// selected.
    var selectedArchivedItem: ArchivedItem? {
        guard case .archived(let identifier) = selection else {
            return nil
        }
        for item in archivedItems {
            if item.id == identifier {
                return item
            }
        }
        return nil
    }

    /// Brings an archived course or section back, then reloads so the
    /// sidebar shows it in its proper place.
    func restore(_ item: ArchivedItem) {
        guard let coursesDirectoryURL else {
            return
        }
        do {
            try CourseRestorer.restore(item, coursesDirectoryURL: coursesDirectoryURL, courses: courses)
        } catch {
            restoreProblem = error.localizedDescription
            return
        }
        selection = nil
        reloadCourses()
        if let sectionNumber = item.sectionNumber {
            selection = SidebarSelection.section(item.courseCode, sectionNumber)
        } else {
            selection = SidebarSelection.course(item.courseCode)
        }
    }

    /// The backup matching a sidebar selection, if that is what is
    /// selected.
    var selectedBackupItem: BackupItem? {
        guard case .backup(let identifier) = selection else {
            return nil
        }
        for item in backupItems {
            if item.id == identifier {
                return item
            }
        }
        return nil
    }

    /// Saves a copy of a whole course, then reloads so the Backups group
    /// shows it — opened, so the new row is visible feedback.
    func backUp(_ course: Course) {
        guard let coursesDirectoryURL else {
            return
        }
        do {
            try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL)
        } catch {
            backupProblem = error.localizedDescription
            return
        }
        isShowingBackups = true
        reloadCourses()
    }

    // MARK: - Renaming a course

    /// The course a rename would act on — the selected one, whether its own
    /// row or one of its sections is what is selected. A teacher who has
    /// clicked into Section 2 and presses Return means the course it belongs
    /// to; there is nothing else in a section's row to rename.
    var courseThatCanBeRenamed: Course? {
        return selectedCourse
    }

    /// Why the selected course cannot be renamed right now, or nil when it
    /// can be.
    ///
    /// Renaming moves the folder a preview is serving out of and a publish
    /// is reading, so it waits for both — the same rule "Add Section…"
    /// follows, worded the same way so the two read as one idea rather than
    /// as two coincidences.
    var renameIsUnavailableReason: String? {
        guard let course = courseThatCanBeRenamed else {
            return nil
        }
        guard let workspaceURL else {
            return nil
        }
        return CourseActivity.busyDescription(folderPath: workspaceURL.path, courseCode: course.code)
    }

    /// Puts the selected course's sidebar row into edit mode.
    ///
    /// Silent when there is no course selected or it is busy: the menu item
    /// is disabled in both cases, and a Return key that did something
    /// half-way would be worse than one that does nothing.
    func beginRenamingSelectedCourse() {
        guard let course = courseThatCanBeRenamed else {
            return
        }
        if renameIsUnavailableReason != nil {
            return
        }
        renamingCourseCode = course.code
    }

    /// Changes a course's code and brings the sidebar with it — after the
    /// two things that can stand in the way.
    ///
    /// The busy check is made AGAIN here, not only when editing began: a
    /// preview can start while the field is open, and the check that matters
    /// is the one nearest the folder being moved. The Obsidian check turns
    /// the rename into a QUESTION rather than doing it, because putting it
    /// right means closing an application the teacher is using.
    func rename(_ course: Course, to requestedCode: String) {
        guard coursesDirectoryURL != nil else {
            return
        }
        if let workspacePath = workspaceURL?.path {
            if CourseActivity.courseIsBusy(folderPath: workspacePath, courseCode: course.code) {
                renamingCourseCode = nil
                renameProblem = "\(course.code) is previewing or deploying right now. Stop that first, then rename."
                return
            }
        }

        // Only when the folder is actually going to move. Retyping the same
        // code changes nothing on disk, so it has nothing to ask about.
        let newCode: String = CourseCodeRule.normalized(requestedCode)
        if !newCode.isEmpty && newCode != course.code {
            let openVaultPaths: [String] = FolderActions.openVaultPathsNow
            if FolderActions.openVaultWouldBeStranded(
                byMoving: course.directoryURL.path, openVaultPaths: openVaultPaths
            ) {
                renamingCourseCode = nil
                obsidianRenameRequest = CourseRenamer.ObsidianRequest(
                    course: course,
                    requestedCode: requestedCode,
                    openVaultPaths: openVaultPaths
                )
                return
            }
        }

        performRename(course, to: requestedCode)
    }

    /// Closes Obsidian, renames, and opens the vaults again — the answer to
    /// the question `rename` asked.
    ///
    /// Obsidian is quit BEFORE the folder moves and the registry is written
    /// afterwards, both for the same reason: a running Obsidian holds its
    /// vault list in memory and writes it back out when it exits, so a
    /// registry edited underneath it is simply lost.
    ///
    /// If the rename fails, the vaults still open again — where they were.
    /// Closing somebody's editor and then not reopening it because a
    /// separate thing went wrong would be the worst of both.
    func renameClosingObsidian(_ request: CourseRenamer.ObsidianRequest) async {
        let oldPath: String = request.course.directoryURL.path
        await FolderActions.quitObsidianAndWait()

        performRename(request.course, to: request.requestedCode)

        var newPath: String = oldPath
        if renameProblem == nil, let coursesDirectoryURL {
            newPath = coursesDirectoryURL
                .appendingPathComponent(CourseCodeRule.normalized(request.requestedCode)).path
            FolderActions.repointVaults(under: oldPath, to: newPath)
        }

        // The course's own vault is opened LAST so it is the one left in
        // front — it is the course the teacher was just working on.
        var others: [String] = []
        var moved: [String] = []
        for vaultPath in request.openVaultPaths {
            let whereItIsNow: String = FolderActions.path(vaultPath, movedFrom: oldPath, to: newPath)
            if whereItIsNow == vaultPath {
                others.append(whereItIsNow)
            } else {
                moved.append(whereItIsNow)
            }
        }
        FolderActions.reopenVaults(others + moved)
    }

    /// The rename itself, once nothing is in the way.
    private func performRename(_ course: Course, to requestedCode: String) {
        guard let coursesDirectoryURL else {
            return
        }

        var existingCodes: [String] = []
        for existingCourse in courses {
            existingCodes.append(existingCourse.code)
        }

        let previousCode: String = course.code
        do {
            let outcome: CourseRenamer.Outcome = try CourseRenamer.rename(
                course,
                to: requestedCode,
                coursesDirectoryURL: coursesDirectoryURL,
                existingCodes: existingCodes
            )
            renamingCourseCode = nil
            if outcome.newCode != previousCode {
                followRename(from: previousCode, to: outcome.newCode)
            }
            reloadCourses()
            renameNotice = CourseRenamer.noticeAfterRenaming(outcome)
        } catch {
            renamingCourseCode = nil
            renameProblem = error.localizedDescription
        }
    }

    /// Keeps the sidebar pointing at what it was pointing at: the same row
    /// selected and the same disclosure triangle open, under the new code.
    ///
    /// Without this a rename looks like a deletion followed by an unrelated
    /// course appearing — the selection empties, the detail pane clears, and
    /// the sections the teacher had unfolded fold themselves back up.
    private func followRename(from previousCode: String, to newCode: String) {
        if expandedCourseCodes.contains(previousCode) {
            expandedCourseCodes.remove(previousCode)
            expandedCourseCodes.insert(newCode)
        }
        switch selection {
        case .course(let code):
            if code == previousCode {
                selection = SidebarSelection.course(newCode)
            }
        case .section(let code, let sectionNumber):
            if code == previousCode {
                selection = SidebarSelection.section(newCode, sectionNumber)
            }
        default:
            break
        }
    }

    /// Puts a backed-up course back in place of the current one. The
    /// current version is ARCHIVED first — even a restore has an undo —
    /// and the backup itself stays until the teacher deletes it.
    func restoreBackup(_ item: BackupItem) {
        guard let coursesDirectoryURL else {
            return
        }
        if let workspacePath = workspaceURL?.path {
            if CourseActivity.courseIsBusy(folderPath: workspacePath, courseCode: item.courseCode) {
                backupProblem = "\(item.courseCode) is previewing or deploying right now. Stop that first, then restore."
                return
            }
        }
        do {
            // Archive WITHOUT removing: the restore replaces the course's
            // contents in place, so Obsidian's file watcher — anchored to
            // the course folder, which is the vault — keeps up instead of
            // showing stale files until the vault is reopened.
            for course in courses {
                if course.code == item.courseCode {
                    try CourseArchiver.archiveCourse(course, coursesDirectoryURL: coursesDirectoryURL)
                }
            }
            try CourseRestorer.restoreBackup(item, coursesDirectoryURL: coursesDirectoryURL)
        } catch {
            backupProblem = error.localizedDescription
            reloadCourses()
            return
        }
        selection = nil
        reloadCourses()
        selection = SidebarSelection.course(item.courseCode)
    }

    /// Deletes a backup for good — no archive behind it, which is why
    /// its confirmation says so.
    func deleteBackup(_ item: BackupItem) {
        do {
            try FileManager.default.removeItem(at: item.fileURL)
        } catch {
            backupProblem = error.localizedDescription
            return
        }
        if selection == SidebarSelection.backup(item.id) {
            selection = nil
        }
        reloadCourses()
    }

    /// What deleting an archive would leave behind, so the confirmation
    /// can state a fact instead of an "if".
    enum ArchiveStanding {
        /// The archived course or section is still in Courses & Clubs.
        case liveInCourses
        /// It is gone from Courses & Clubs, but another archive or a
        /// backup still covers it.
        case otherCopiesRemain
        /// It is gone, and this archive is the only copy left anywhere.
        case onlyRemainingCopy
    }

    func archiveStanding(_ item: ArchivedItem) -> ArchiveStanding {
        return WorkspaceModel.archiveStanding(
            item, among: courses, archives: archivedItems, backups: backupItems
        )
    }

    static func archiveStanding(
        _ item: ArchivedItem,
        among courses: [Course],
        archives: [ArchivedItem],
        backups: [BackupItem]
    ) -> ArchiveStanding {
        for course in courses {
            if course.code == item.courseCode {
                guard let sectionNumber = item.sectionNumber else {
                    return .liveInCourses
                }
                if course.sectionNumbers.contains(sectionNumber) {
                    return .liveInCourses
                }
            }
        }
        for other in archives {
            if other.id == item.id || other.courseCode != item.courseCode {
                continue
            }
            // A whole-course archive covers every section; a section
            // archive covers only its own section. A section archive
            // never covers a whole-course one.
            if other.sectionNumber == nil || other.sectionNumber == item.sectionNumber {
                return .otherCopiesRemain
            }
        }
        for backup in backups {
            if backup.courseCode == item.courseCode {
                return .otherCopiesRemain
            }
        }
        return .onlyRemainingCopy
    }

    /// Deletes an archive for good. The promise made at removal time —
    /// "nothing is deleted" — was about REMOVING; this is a second,
    /// deliberate act with its own plain-spoken confirmation.
    func deleteArchive(_ item: ArchivedItem) {
        do {
            try FileManager.default.removeItem(at: item.fileURL)
        } catch {
            backupProblem = error.localizedDescription
            return
        }
        if selection == SidebarSelection.archived(item.id) {
            selection = nil
        }
        reloadCourses()
    }

    /// Finds the teacher's saved backups, newest first.
    static func findBackupItems(in coursesDirectoryURL: URL) -> [BackupItem] {
        let fileManager: FileManager = FileManager.default
        let backupsRoot: URL = coursesDirectoryURL.appendingPathComponent("_backups")
        var found: [BackupItem] = []

        guard let courseFolders = try? fileManager.contentsOfDirectory(
            at: backupsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return found
        }

        for courseFolder in courseFolders {
            let courseCode: String = courseFolder.lastPathComponent
            guard let zips = try? fileManager.contentsOfDirectory(
                at: courseFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for zipURL in zips {
                if let item = BackupItem.from(fileURL: zipURL, courseCode: courseCode) {
                    found.append(item)
                }
            }
        }

        found.sort { first, second in
            return first.backedUpAt > second.backedUpAt
        }
        return found
    }

    /// Finds what the teacher has archived, newest first.
    ///
    /// Archives live beside each course's automatic backups; only the ones
    /// named after what was removed belong here — see `ArchivedItem`.
    static func findArchivedItems(in coursesDirectoryURL: URL) -> [ArchivedItem] {
        let fileManager: FileManager = FileManager.default
        let archivesRoot: URL = coursesDirectoryURL.appendingPathComponent("_backups")
        var found: [ArchivedItem] = []

        guard let courseFolders = try? fileManager.contentsOfDirectory(
            at: archivesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return found
        }

        for courseFolder in courseFolders {
            let courseCode: String = courseFolder.lastPathComponent
            guard let archives = try? fileManager.contentsOfDirectory(
                at: courseFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for archiveURL in archives {
                if let item = ArchivedItem.from(fileURL: archiveURL, courseCode: courseCode) {
                    found.append(item)
                }
            }
        }

        found.sort { first, second in
            return first.archivedAt > second.archivedAt
        }
        return found
    }

    /// Sets up an empty folder as a fresh working folder: copies the
    /// bundled launcher scripts in (the same files the Docker image's
    /// export-scripts command delivers), marks them executable, creates
    /// `courses/`, and opens the New Course wizard.
    func initializeWorkspace() {
        guard let workspaceURL else {
            return
        }
        // Kept synchronous for callers that are not driving an interface —
        // the tests, chiefly, which assert what lands on disk and would
        // otherwise have to await a background thread to find out.
        //
        // The tracker is cleared first because a folder being set up has no
        // toolchain yet, whatever an earlier folder of the same path in this
        // run of the app may have had — the defect row 279 fixed.
        WorkspaceModel.foldersWithFreshToolchain.remove(workspaceURL.path)
        let problem: String? = WorkspaceModel.setUpFolderOnDisk(at: workspaceURL)
        if problem == nil {
            WorkspaceModel.noteToolchainMirrored(into: workspaceURL)
        }
        finishInitializing(at: workspaceURL, problem: problem)
    }

    /// The same setup, with the copying done OFF the main thread.
    ///
    /// This is what the button calls. The work is 12,091 files and 65 MB —
    /// see `isInitializingWorkspace` — and on the main thread that is a
    /// beachball over a window that says nothing, which a teacher reads as a
    /// hang rather than as work. Windows reached the same conclusion first
    /// and fixed it the same way (`InitializeWorkspaceAsync`, whose button
    /// says "Setting up…"); this is the mac catching up to it.
    ///
    /// The folder is read once, up front, and the background work is given
    /// nothing but that URL — so it cannot see a `workspaceURL` the teacher
    /// changed while it ran, and everything that touches the model happens
    /// back on the main actor afterwards.
    @MainActor
    func initializeWorkspaceInBackground() async {
        guard let workspaceURL, !isInitializingWorkspace else {
            return
        }
        isInitializingWorkspace = true
        let startedAt: Date = Date()
        // Both touches of the shared tracker happen HERE, on the main actor,
        // never inside the detached work — see `setUpFolderOnDisk`.
        WorkspaceModel.foldersWithFreshToolchain.remove(workspaceURL.path)
        let problem: String? = await Task.detached(priority: .userInitiated) {
            return WorkspaceModel.setUpFolderOnDisk(at: workspaceURL)
        }.value
        if problem == nil {
            WorkspaceModel.noteToolchainMirrored(into: workspaceURL)
        }
        AppLog.interface.info(
            "set up \(LogRedactor.redacting(workspaceURL.path), privacy: .public) in \(String(format: "%.2f", Date().timeIntervalSince(startedAt)), privacy: .public)s"
        )
        isInitializingWorkspace = false
        finishInitializing(at: workspaceURL, problem: problem)
    }

    /// Everything setting up a folder writes to DISK, and nothing else.
    ///
    /// `nonisolated` and touching no model state: it runs on a background
    /// thread, so anything it read from `self` — or from the shared
    /// once-per-run set — would be a race. Its caller does that bookkeeping
    /// on the main actor, on either side of this. Answers with the problem
    /// to report, or nil.
    nonisolated static func setUpFolderOnDisk(at workspaceURL: URL) -> String? {
        let fileManager: FileManager = FileManager.default

        let scriptNames: [String] = ["setup.sh", "preview.sh", "deploy.sh"]
        for scriptName in scriptNames {
            guard let bundledURL = Bundle.main.url(forResource: scriptName, withExtension: nil) else {
                return "Part of the app’s built-in setup files is missing (\(scriptName)) — please reinstall the app."
            }
            let destinationURL: URL = workspaceURL.appendingPathComponent(scriptName)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: bundledURL, to: destinationURL)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
            } catch {
                return "Could not set up this folder: \(error.localizedDescription)"
            }
        }

        do {
            try fileManager.createDirectory(
                at: workspaceURL.appendingPathComponent("courses"),
                withIntermediateDirectories: true
            )
        } catch {
            return "Could not create the courses folder: \(error.localizedDescription)"
        }

        // The build recipe itself — the expensive part, and the reason this
        // runs off the main thread.
        _ = WorkspaceModel.copyToolchainFiles(into: workspaceURL)
        return nil
    }

    /// Reports the outcome and moves the teacher on. Main actor only: it
    /// writes model state the interface is watching.
    @MainActor
    private func finishInitializing(at workspaceURL: URL, problem: String?) {
        if let problem {
            workspaceProblem = problem
            return
        }
        // Setting up an empty synced folder IS the decision to use it: the
        // picker showed the note beside the button, and pressing it is the
        // teacher's answer. Recorded before the reload so the note is not
        // shown a second time.
        // …and only if the folder set up is still the one showing. The copy
        // runs off the main thread, and File › Open Working Folder stays
        // enabled meanwhile: a synced folder chosen during the copy has a
        // decision of its own pending, and finishing the FIRST folder's
        // set-up must not answer it.
        if needsCloudSyncDecision && self.workspaceURL == workspaceURL {
            acknowledgeCloudSync()
        }
        reloadCourses()

        // The natural next step in a fresh folder is creating a course.
        if workspaceProblem == nil {
            isShowingNewCourseWizard = true
        }
    }

    /// True when the folder contains nothing but ignorable clutter
    /// (e.g. the .DS_Store file Finder sprinkles around).
    private func folderIsEffectivelyEmpty(_ folderURL: URL) -> Bool {
        let fileManager: FileManager = FileManager.default
        var entryNames: [String] = []
        do {
            entryNames = try fileManager.contentsOfDirectory(atPath: folderURL.path)
        } catch {
            return false
        }
        for entryName in entryNames {
            if entryName == ".DS_Store" {
                continue
            }
            return false
        }
        return true
    }
}
