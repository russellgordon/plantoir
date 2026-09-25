import AppKit
import Foundation

/// Folder-related actions offered by sidebar context menus.
enum FolderActions {

    // MARK: - Functions

    /// Shows the folder inside its parent, selected — what "Show in
    /// Finder" means everywhere in the app, path bar included.
    static func showInFinder(_ folderURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }

    /// Opens a new Terminal window whose working directory is the folder
    /// (the same behaviour as dropping the folder onto Terminal's icon).
    static func openTerminal(at folderURL: URL) {
        let terminalURL: URL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration: NSWorkspace.OpenConfiguration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([folderURL], withApplicationAt: terminalURL, configuration: configuration)
    }

    /// Opens the folder in Obsidian. Obsidian's `open?path=` link only
    /// works for folders inside a vault it already KNOWS — its registry at
    /// `~/Library/Application Support/obsidian/obsidian.json` — so a course
    /// it has never seen is registered first, exactly the way Obsidian's
    /// own "Open folder as vault" writes the entry. A running Obsidian
    /// keeps its vault list in memory, so registering means quitting it
    /// first; doing the quit before the write also stops Obsidian
    /// overwriting the new entry on exit.
    ///
    /// **Obsidian does NOT restore its windows on relaunch** — this said
    /// that it did, and it is measured to be false: with two vaults open,
    /// quitting and then relaunching through `obsidian://open?path=` brings
    /// back only the vault named in the link, and the other stays closed.
    /// So every vault that was open is noted first and opened again
    /// afterwards, the asked-for one last so it lands in front.
    static func openInObsidian(revealing folderURL: URL, vaultURL: URL) {
        let target: URL = FolderActions.obsidianTarget(forFolder: folderURL, vaultURL: vaultURL)
        guard let obsidianLink = FolderActions.obsidianURL(forFolder: target) else {
            return
        }
        let registryData: Data? = try? Data(contentsOf: FolderActions.obsidianRegistryFileURL)
        if FolderActions.folderIsInRegisteredVault(target.path, registryData: registryData) {
            if !FolderActions.obsidianIsRunning {
                // While Obsidian is closed its saved layout can be improved:
                // auto-reveal makes the folder highlight when the page opens.
                FolderActions.enableAutoRevealInLayout(ofVault: vaultURL)
            }
            NSWorkspace.shared.open(obsidianLink)
            return
        }
        Task { @MainActor in
            let wereOpen: [String] = FolderActions.openVaultPathsNow
            await FolderActions.quitObsidianAndWait()
            FolderActions.seedObsidianDefaultsIfMissing(inVault: vaultURL)
            FolderActions.enableAutoRevealInLayout(ofVault: vaultURL)
            FolderActions.registerVault(at: vaultURL)
            FolderActions.reopenVaults(wereOpen)
            NSWorkspace.shared.open(obsidianLink)
        }
    }

    /// Whether Obsidian is running right now.
    static var obsidianIsRunning: Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: "md.obsidian").isEmpty
    }

    /// Turns on the File Explorer's "auto-reveal current file" in a vault's
    /// saved layout, so opening a section's page highlights its folder in
    /// Obsidian's sidebar. Obsidian rebuilds the layout on a vault's FIRST
    /// open (a pre-seeded one is discarded — verified live) and holds it in
    /// memory while running, so this only helps when Obsidian is closed and
    /// the layout already exists: from the second open onward.
    static func enableAutoRevealInLayout(ofVault vaultURL: URL) {
        let layoutFileURL: URL = vaultURL.appendingPathComponent(".obsidian/workspace.json")
        guard let layoutData = try? Data(contentsOf: layoutFileURL) else {
            return
        }
        guard let layout = try? JSONSerialization.jsonObject(with: layoutData) else {
            return
        }
        let improved: Any = FolderActions.layoutEnablingAutoReveal(layout)
        guard let improvedData = try? JSONSerialization.data(withJSONObject: improved) else {
            return
        }
        try? improvedData.write(to: layoutFileURL)
    }

    /// The same layout with every File Explorer's `autoReveal` set true and
    /// nothing else touched.
    static func layoutEnablingAutoReveal(_ node: Any) -> Any {
        if let dictionary = node as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                result[key] = FolderActions.layoutEnablingAutoReveal(value)
            }
            if let state = result["state"] as? [String: Any],
               state["type"] as? String == "file-explorer" {
                var innerState: [String: Any] = (state["state"] as? [String: Any]) ?? [:]
                innerState["autoReveal"] = true
                var newState: [String: Any] = state
                newState["state"] = innerState
                result["state"] = newState
            }
            return result
        }
        if let array = node as? [Any] {
            var result: [Any] = []
            for element in array {
                result.append(FolderActions.layoutEnablingAutoReveal(element))
            }
            return result
        }
        return node
    }

    /// What the link should point at. Obsidian opens FILES, not folders —
    /// handing it a section's folder gets "File not found" — so a folder
    /// inside the vault is represented by its landing page (`index.md`)
    /// when it has one, and by the vault itself when it does not. The
    /// vault's own folder passes through untouched: a path that IS a
    /// vault opens that vault.
    static func obsidianTarget(forFolder folderURL: URL, vaultURL: URL) -> URL {
        if folderURL.path == vaultURL.path {
            return folderURL
        }
        let landingPage: URL = folderURL.appendingPathComponent("index.md")
        if FileManager.default.fileExists(atPath: landingPage.path) {
            return landingPage
        }
        return vaultURL
    }

    // MARK: - Which vaults Obsidian has open

    /// The vaults Obsidian has open RIGHT NOW, or none when nothing is.
    ///
    /// THREE facts have to agree, and the last two are both traps that shipped
    /// as bugs before they were measured:
    ///
    /// 1. **Obsidian is running.** Obvious, and not enough on its own.
    /// 2. **It has a window on screen.** Obsidian marks a vault
    ///    `"open": true` in its registry when the vault opens and does not
    ///    reliably clear the mark when the vault is CLOSED — measured with
    ///    every vault closed and Obsidian still running: no windows at all,
    ///    and one vault still marked open. Without this check a teacher who
    ///    had closed their vaults was told the course was open in Obsidian
    ///    and offered to have it closed for them.
    /// 3. **The registry marks this vault open.** Which of the windows is
    ///    which cannot be known: a window's TITLE names its vault, but
    ///    reading another application's window titles needs the screen
    ///    recording permission, and asking a teacher for that in order to
    ///    rename a folder is out of all proportion. Owner and count need no
    ///    permission, so the count is what is used.
    ///
    /// **What is still imprecise, said plainly.** Marks can over-report while
    /// a window IS on screen: closing one of two vaults cleared its mark
    /// here, closing the other did not. So with one vault genuinely open and
    /// a stale mark beside it, one extra vault may be opened again after a
    /// rename. An extra window is a small price; the alternative is a
    /// permission prompt for every teacher.
    static var openVaultPathsNow: [String] {
        if !FolderActions.obsidianIsRunning {
            return []
        }
        if FolderActions.obsidianWindowCount() == 0 {
            return []
        }
        return FolderActions.openVaultPaths(
            registryData: try? Data(contentsOf: FolderActions.obsidianRegistryFileURL)
        )
    }

    /// How many ordinary windows Obsidian has on screen.
    ///
    /// Asked of the window server, which hands out an owner and a size to
    /// anybody. Only the window's NAME is privileged, and the name is the one
    /// thing this does not need.
    static func obsidianWindowCount() -> Int {
        var obsidianProcessIDs: Set<pid_t> = []
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: "md.obsidian") {
            obsidianProcessIDs.insert(application.processIdentifier)
        }
        if obsidianProcessIDs.isEmpty {
            return 0
        }
        let listed: CFArray? = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        )
        guard let windows = listed as? [[String: Any]] else {
            return 0
        }

        var count: Int = 0
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }
            if !obsidianProcessIDs.contains(owner) {
                continue
            }
            // Layer zero is an ordinary window. Menus, tooltips and panels
            // sit above it, and counting those would put us back where we
            // started.
            guard let layer = window[kCGWindowLayer as String] as? Int else {
                continue
            }
            if layer != 0 {
                continue
            }
            count += 1
        }
        return count
    }

    /// The paths marked open in a registry. Split out from
    /// `openVaultPathsNow` so the parsing can be tested without an
    /// Obsidian on the machine.
    static func openVaultPaths(registryData: Data?) -> [String] {
        guard let registryData else {
            return []
        }
        guard let registry = try? JSONSerialization.jsonObject(with: registryData) as? [String: Any] else {
            return []
        }
        guard let vaults = registry["vaults"] as? [String: Any] else {
            return []
        }
        var paths: [String] = []
        for vaultEntry in vaults.values {
            guard let vault = vaultEntry as? [String: Any] else {
                continue
            }
            guard let vaultPath = vault["path"] as? String else {
                continue
            }
            if vault["open"] as? Bool == true {
                paths.append(vaultPath)
            }
        }
        // Sorted so the order is the same every time it is asked, which
        // makes the reopening order — and a test — predictable.
        paths.sort()
        return paths
    }

    /// Whether moving a course's folder would leave Obsidian showing files
    /// that are no longer there.
    ///
    /// True only when an open vault IS the course's folder, or sits inside
    /// it. A vault that CONTAINS the course — a teacher who opened the whole
    /// `courses` folder as one vault — is not affected: its own root does
    /// not move, and Obsidian follows a rename inside a vault perfectly
    /// well. It is the vault's own root moving out from under the watcher
    /// that strands it.
    static func openVaultWouldBeStranded(byMoving folderPath: String, openVaultPaths: [String]) -> Bool {
        for vaultPath in openVaultPaths {
            if vaultPath == folderPath || vaultPath.hasPrefix(folderPath + "/") {
                return true
            }
        }
        return false
    }

    /// Opens each of these vaults again, in order — so the LAST one named
    /// is the one left in front.
    static func reopenVaults(_ vaultPaths: [String]) {
        for vaultPath in vaultPaths {
            guard let link = FolderActions.obsidianURL(forFolder: URL(fileURLWithPath: vaultPath)) else {
                continue
            }
            NSWorkspace.shared.open(link)
        }
    }

    /// The same path with one of its ancestors renamed — used to work out
    /// where a vault has ended up after the course folder it is (or sits
    /// inside) has moved.
    static func path(_ path: String, movedFrom oldFolder: String, to newFolder: String) -> String {
        if path == oldFolder {
            return newFolder
        }
        if path.hasPrefix(oldFolder + "/") {
            return newFolder + String(path.dropFirst(oldFolder.count))
        }
        return path
    }

    /// Points a vault's registry entry at where its folder has moved to,
    /// keeping the SAME entry.
    ///
    /// Keeping the entry rather than adding a second one matters twice
    /// over: Obsidian's list stays the length the teacher expects, and no
    /// dead entry is left pointing at a folder that no longer exists.
    /// Verified end to end — quit, move the folder, repoint, reopen — and
    /// the vault comes back with its list unchanged.
    static func registryData(afterMovingVaultsUnder oldFolder: String, to newFolder: String, in registryData: Data?) -> Data? {
        guard let registryData else {
            return nil
        }
        guard var registry = try? JSONSerialization.jsonObject(with: registryData) as? [String: Any] else {
            return nil
        }
        guard let vaults = registry["vaults"] as? [String: Any] else {
            return nil
        }
        var moved: [String: Any] = [:]
        for (identifier, vaultEntry) in vaults {
            guard var vault = vaultEntry as? [String: Any] else {
                moved[identifier] = vaultEntry
                continue
            }
            if let vaultPath = vault["path"] as? String {
                vault["path"] = FolderActions.path(vaultPath, movedFrom: oldFolder, to: newFolder)
            }
            moved[identifier] = vault
        }
        registry["vaults"] = moved
        return try? JSONSerialization.data(withJSONObject: registry)
    }

    /// Writes the repointed registry back.
    static func repointVaults(under oldFolder: String, to newFolder: String) {
        let registryFileURL: URL = FolderActions.obsidianRegistryFileURL
        guard let updated = FolderActions.registryData(
            afterMovingVaultsUnder: oldFolder,
            to: newFolder,
            in: try? Data(contentsOf: registryFileURL)
        ) else {
            return
        }
        try? updated.write(to: registryFileURL)
    }

    /// Where Obsidian keeps its list of known vaults.
    ///
    /// Through `RealHome.forFiles` (#264), so under the unit suite the rename
    /// paths read and write a throwaway copy — never the real list, which
    /// they WRITE when Obsidian is open with a window.
    static var obsidianRegistryFileURL: URL {
        return RealHome.forFiles
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
    }

    /// Whether the folder sits inside (or is) a vault Obsidian already
    /// knows about.
    static func folderIsInRegisteredVault(_ folderPath: String, registryData: Data?) -> Bool {
        guard let registryData else {
            return false
        }
        guard let registry = try? JSONSerialization.jsonObject(with: registryData) as? [String: Any] else {
            return false
        }
        guard let vaults = registry["vaults"] as? [String: Any] else {
            return false
        }
        for vaultEntry in vaults.values {
            guard let vault = vaultEntry as? [String: Any] else {
                continue
            }
            guard let vaultPath = vault["path"] as? String else {
                continue
            }
            if folderPath == vaultPath || folderPath.hasPrefix(vaultPath + "/") {
                return true
            }
        }
        return false
    }

    /// The registry with one more vault in it — built from the existing
    /// data so every vault the teacher already has is preserved, or from
    /// nothing when Obsidian has never made a registry at all.
    static func registryData(afterRegisteringVaultAt vaultPath: String, in registryData: Data?, identifier: String, timestamp: Int) -> Data? {
        var registry: [String: Any] = [:]
        if let registryData,
           let existing = try? JSONSerialization.jsonObject(with: registryData) as? [String: Any] {
            registry = existing
        }
        var vaults: [String: Any] = (registry["vaults"] as? [String: Any]) ?? [:]
        vaults[identifier] = ["path": vaultPath, "ts": timestamp]
        registry["vaults"] = vaults
        return try? JSONSerialization.data(withJSONObject: registry)
    }

    /// Adds the vault to Obsidian's registry on disk.
    static func registerVault(at vaultURL: URL) {
        let registryFileURL: URL = FolderActions.obsidianRegistryFileURL
        let existingData: Data? = try? Data(contentsOf: registryFileURL)
        var identifier: String = ""
        for _ in 1...16 {
            identifier.append("0123456789abcdef".randomElement() ?? "0")
        }
        let timestamp: Int = Int(Date().timeIntervalSince1970 * 1000)
        guard let updated = FolderActions.registryData(
            afterRegisteringVaultAt: vaultURL.path,
            in: existingData,
            identifier: identifier,
            timestamp: timestamp
        ) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: registryFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? updated.write(to: registryFileURL)
    }

    /// Quits Obsidian and waits for it to be gone, so the registry write
    /// that follows cannot be overwritten and the relaunch reads it fresh.
    static func quitObsidianAndWait() async {
        let obsidianBundleID: String = "md.obsidian"
        let running: [NSRunningApplication] = NSRunningApplication.runningApplications(withBundleIdentifier: obsidianBundleID)
        if running.isEmpty {
            return
        }
        for application in running {
            application.terminate()
        }
        var attemptsLeft: Int = 50
        while attemptsLeft > 0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if NSRunningApplication.runningApplications(withBundleIdentifier: obsidianBundleID).isEmpty {
                return
            }
            attemptsLeft -= 1
        }
    }

    /// Copies the toolchain's bundled `.obsidian` defaults into a vault
    /// that has none — the same defaults every wizard-built course gets,
    /// so attachments land in Media rather than beside the notes.
    static func seedObsidianDefaultsIfMissing(inVault vaultURL: URL) {
        let fileManager: FileManager = FileManager.default
        let destination: URL = vaultURL.appendingPathComponent(".obsidian")
        if fileManager.fileExists(atPath: destination.path) {
            return
        }
        guard let resourceURL = Bundle.main.resourceURL else {
            return
        }
        let bundledDefaults: URL = resourceURL.appendingPathComponent("support/obsidian_defaults/.obsidian")
        if fileManager.fileExists(atPath: bundledDefaults.path) {
            try? fileManager.copyItem(at: bundledDefaults, to: destination)
        }
    }

    /// The `obsidian://open?path=…` link for a folder, with the path
    /// properly percent-encoded.
    static func obsidianURL(forFolder folderURL: URL) -> URL? {
        var components: URLComponents = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: folderURL.path)]
        return components.url
    }

    /// Whether anything on this Mac answers `obsidian://` links — the
    /// menu item and button stay visible either way, but a click can only
    /// do something when Obsidian is installed.
    static var obsidianIsInstalled: Bool {
        guard let probe = URL(string: "obsidian://open") else {
            return false
        }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }
}
