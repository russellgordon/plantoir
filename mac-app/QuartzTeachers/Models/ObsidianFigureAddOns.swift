import CryptoKit
import Foundation

/// One Obsidian add-on Plantoir carries for a figure fence (#495): which
/// fence it draws, and the exact files, pinned by size and SHA-256.
///
/// The pins are the contract's (`contracts/shared-rules.json` →
/// `obsidianAddOnsForFigures.addOns`) and `ObsidianFigureAddOnsTests` holds
/// the two equal; `mac-app/Vendor/fetch-obsidian-addons.sh` reads the same
/// contract and carries no pin of its own.
nonisolated struct ObsidianFigureAddOn: Equatable, Sendable {

    // MARK: - Types

    /// One file of an add-on as Plantoir carries it.
    struct CarriedFile: Equatable, Sendable {

        // MARK: - Stored properties

        let name: String
        let bytes: Int
        let sha256: String
    }

    // MARK: - Stored properties

    /// The fence's language: `tikz` or `functionplot`.
    let kind: String

    /// Obsidian's id for it, which is also its folder's name under
    /// `.obsidian/plugins/`.
    let id: String

    /// What the trail calls it.
    let name: String

    /// The version its `manifest.json` says.
    let version: String

    /// Every file written into a course, its licence among them.
    let files: [CarriedFile]
}

/// Obsidian's add-ons for diagrams and graphs (#495): which ones a course
/// needs, and adding them to the course on the teacher's one yes.
///
/// **Why Plantoir writes files at all.** Obsidian loads an add-on from
/// `.obsidian/plugins/<id>/` when its id is in `.obsidian/community-plugins.json`
/// — nothing checks a signature or the directory (exploration F3, read from
/// Obsidian 1.13.7's own code). What it will NOT do is run it unasked: the
/// first time a vault with add-ons opens, Obsidian asks whether the teacher
/// trusts its author, and the answer lives in Obsidian's own storage, keyed by
/// the vault (F1, F2). Plantoir never touches that answer (`rejected` in the
/// contract), so a teacher who said yes to Plantoir still says yes to Obsidian,
/// once per course — and the offer tells them so before it happens.
///
/// **What is written, in an order a crash at any point recovers from**
/// (`install`):
///
/// 1. Refuse if `.obsidian` or `.obsidian/plugins` is a link.
/// 2. Hash the carried files against the pins; a mismatch writes nothing.
/// 3. Copy the course defaults in if `.obsidian` is missing, then REFUSE
///    unless `.obsidian/app.json` is there (plan review S2): seeding happens
///    only while `.obsidian` is absent, so creating `plugins/` over a failed
///    copy would cost the course its defaults for good.
/// 4. Read the list; a list that is not an array of strings writes nothing at
///    all — files without a list entry would bring Obsidian's trust question
///    for an add-on that then loads nothing.
/// 5. Decide each add-on (`decide`), never over the teacher's own copy, never
///    downgrading one Obsidian updated, never re-listing one switched off.
/// 6. Write the list (atomically), THEN the files: everything but
///    `manifest.json` into `<id>.plantoir-partial/` with the `.plantoir`
///    marker, renamed to `<id>`, then `manifest.json` last. Obsidian ignores a
///    folder without a manifest, and a listed id with no folder.
///
/// **Never while the course is open in Obsidian** — the callers' rule, not
/// this file's (plan review S3): Obsidian holds the list in memory and writes
/// it back whole on every add-on switch, so an id added under it is dropped,
/// and the marker would then read as the teacher switching it off.
nonisolated enum ObsidianFigureAddOns {

    // MARK: - Types

    /// What one pass did for one add-on — the contract's `vaultCases`
    /// outcomes.
    enum Outcome: Equatable, Sendable {
        /// Written, and listed.
        case added
        /// Plantoir's copy, this version, listed.
        case alreadyThere
        /// Plantoir's copy, this version, NOT listed: the teacher switched it
        /// off in Obsidian, so it stays off.
        case alreadyThereSwitchedOff
        /// No marker: the teacher installed it themselves.
        case leftAloneTheirs(version: String)
        /// Plantoir's copy at another version — Obsidian updated it. Never
        /// downgraded.
        case leftAloneOtherVersion(version: String)
        /// Something at its place whose details cannot be read, without the
        /// marker — or not a folder at all.
        case leftAloneUnreadable
        /// The list is not an array of strings. Nothing written.
        case refusedListUnreadable
        /// `.obsidian` or `.obsidian/plugins` is a link. Nothing written.
        case refusedLink
        /// The carried copy is missing or does not match its pin. Nothing
        /// written.
        case refusedCarriedCopy
        /// `.obsidian/app.json` is missing after the defaults were copied —
        /// or could not be. Nothing written.
        case refusedSettingsNotSeeded
        /// A write failed: the system's reason.
        case couldNotWrite(reason: String)

        // MARK: - Computed properties

        /// The contract's name for it.
        var contractName: String {
            switch self {
            case .added: return "added"
            case .alreadyThere: return "alreadyThere"
            case .alreadyThereSwitchedOff: return "alreadyThereSwitchedOff"
            case .leftAloneTheirs: return "leftAloneTheirs"
            case .leftAloneOtherVersion: return "leftAloneOtherVersion"
            case .leftAloneUnreadable: return "leftAloneUnreadable"
            case .refusedListUnreadable: return "refusedListUnreadable"
            case .refusedLink: return "refusedLink"
            case .refusedCarriedCopy: return "refusedCarriedCopy"
            case .refusedSettingsNotSeeded: return "refusedSettingsNotSeeded"
            case .couldNotWrite: return "couldNotWrite"
            }
        }

        /// Whether the whole pass was refused before any add-on was looked
        /// at.
        var isARefusal: Bool {
            switch self {
            case .refusedListUnreadable, .refusedLink, .refusedCarriedCopy, .refusedSettingsNotSeeded:
                return true
            default:
                return false
            }
        }
    }

    /// One add-on and what the pass did with it.
    struct Result: Equatable, Sendable {

        // MARK: - Stored properties

        let addOn: ObsidianFigureAddOn
        let outcome: Outcome
    }

    /// What the list said, read once per pass.
    enum ListReading: Equatable, Sendable {
        /// The ids, in order. A missing file reads as none.
        case ids([String])
        /// Not an array of strings — never overwritten.
        case unreadable
    }

    /// What the list becomes when ids are added (`listCases`).
    enum ListAfter: Equatable, Sendable {
        /// Write this text.
        case write(String)
        /// Every id is listed already: the file is not touched.
        case unchanged
        /// The list is not an array of strings: never overwritten.
        case refused
    }

    /// What a pass would do for one add-on, before anything is written.
    private enum Decision {
        case add
        case keep(Outcome)
    }

    // MARK: - Stored properties

    /// The add-ons, in the contract's order. Pinned to the contract by
    /// `ObsidianFigureAddOnsTests.testThePinsAreTheContracts`.
    static let pinned: [ObsidianFigureAddOn] = [
        ObsidianFigureAddOn(
            kind: "tikz",
            id: "obsidian-tikzjax",
            name: "TikZJax",
            version: "0.5.2",
            files: [
                ObsidianFigureAddOn.CarriedFile(name: "main.js", bytes: 7_861_284, sha256: "cbae1ad4362d44173e56ba512f01e65de1f7cc69a4bf4733bc5711a2de101f41"),
                ObsidianFigureAddOn.CarriedFile(name: "manifest.json", bytes: 261, sha256: "09fbbb05aeffc32bc65365d8526fc2222ee971417dcd4afddeb989498a5e1de1"),
                ObsidianFigureAddOn.CarriedFile(name: "styles.css", bytes: 4_791_190, sha256: "d9a7f741ec8fdcbe5e0145152c799238cee8df5a14ddc7dc9feb3bb835ce068d"),
                ObsidianFigureAddOn.CarriedFile(name: "LICENSE.md", bytes: 1_068, sha256: "f2cb60614f038ec0db9a04546c05cc72d6c68a2cdb39bce0a853b692a5739291"),
            ]
        ),
        ObsidianFigureAddOn(
            kind: "functionplot",
            id: "obsidian-functionplot",
            name: "Functionplot",
            version: "1.2.1",
            files: [
                ObsidianFigureAddOn.CarriedFile(name: "main.js", bytes: 220_867, sha256: "8b490af5fd3015e15237dbaadbb98fcdf823a42086029527381e48c5080be43f"),
                ObsidianFigureAddOn.CarriedFile(name: "manifest.json", bytes: 287, sha256: "991ffea318c2483c4dd3eef2fdec47479d05dea8d04993becc2f74c186318195"),
                ObsidianFigureAddOn.CarriedFile(name: "LICENSE", bytes: 1_072, sha256: "6e1b8deb29dc68d12c965b32600d1fe6089cee56dbb3b8662361296bcb221eed"),
            ]
        ),
    ]

    /// The marker inside an add-on's folder that says Plantoir put it there.
    /// Obsidian reads only `manifest.json`, `main.js` and `styles.css` from
    /// the folder, and Sync's add-on file list leaves it out (plan review,
    /// "checked").
    static let markerName: String = ".plantoir"

    /// The folder an add-on is written into before it is renamed into place.
    static let partialSuffix: String = ".plantoir-partial"

    /// Obsidian's list of the add-ons it switches on.
    static let listName: String = "community-plugins.json"

    /// Where the app carries the add-ons: `Contents/Resources/obsidian-addons`.
    static let carriedFolderName: String = "obsidian-addons"

    /// How many passes are running now, and the most ever seen at once —
    /// the second READ by a test only, which proves passes never overlap
    /// (plan review S2). Guarded by `passesLock`.
    private static let passesLock: NSLock = NSLock()
    nonisolated(unsafe) private static var passesRunning: Int = 0
    nonisolated(unsafe) private static var mostPassesSeen: Int = 0

    /// The most passes ever seen running at once, and a way to start
    /// counting again.
    static var mostPassesAtOnce: Int {
        passesLock.lock()
        defer {
            passesLock.unlock()
        }
        return mostPassesSeen
    }

    static func forgetMostPassesAtOnce() {
        passesLock.lock()
        mostPassesSeen = 0
        passesLock.unlock()
    }

    // MARK: - Functions

    /// The marker's bytes for a version: the same bytes every pass.
    static func markerText(version: String) -> String {
        return "{\"addedBy\":\"Plantoir\",\"version\":\"" + version + "\"}"
    }

    /// The add-ons whose fence kind is among `kinds`, in the pinned order.
    static func addOns(forKinds kinds: Set<String>, among addOns: [ObsidianFigureAddOn] = ObsidianFigureAddOns.pinned) -> [ObsidianFigureAddOn] {
        var needed: [ObsidianFigureAddOn] = []
        for addOn in addOns {
            if kinds.contains(addOn.kind) {
                needed.append(addOn)
            }
        }
        return needed
    }

    // MARK: - Which add-ons a course needs

    /// The figure kinds the course's pages use, among `kinds` (#495
    /// `whichPages`): every `.md` file under the course, its drafts and
    /// shared pages included — the vault is the whole course — except inside
    /// a folder whose name starts with a dot (`.obsidian`, `.trash`,
    /// `.merged_output`) and pages iCloud has not downloaded (`isEvicted`, so
    /// the scan never forces a download). A cheap byte test comes first, and
    /// it stops as soon as every kind is found.
    static func kindsUsed(
        inCourseAt courseURL: URL,
        among kinds: Set<String>,
        isEvicted: (URL) -> Bool = ObsidianFigureAddOns.pageIsEvicted
    ) -> Set<String> {
        var found: Set<String> = []
        guard let walker = FileManager.default.enumerator(
            at: courseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return found
        }
        for case let fileURL as URL in walker {
            if found.count == kinds.count {
                break
            }
            if fileURL.pathExtension.lowercased() != "md" {
                continue
            }
            let isFile: Bool = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if !isFile {
                continue
            }
            if isEvicted(fileURL) {
                continue
            }
            guard let data = try? Data(contentsOf: fileURL) else {
                continue
            }
            var stillToFind: Set<String> = []
            for kind in kinds {
                if found.contains(kind) {
                    continue
                }
                if data.range(of: Data(kind.utf8)) != nil {
                    stillToFind.insert(kind)
                }
            }
            if stillToFind.isEmpty {
                continue
            }
            let text: String = String(decoding: data, as: UTF8.self)
            for kind in FigureFenceScan.kinds(in: text, among: stillToFind) {
                found.insert(kind)
            }
        }
        return found
    }

    /// Whether macOS holds only a placeholder for the page (iCloud
    /// "Optimise Mac Storage"): reading it would download it.
    static func pageIsEvicted(_ fileURL: URL) -> Bool {
        var status: stat = stat()
        if lstat(fileURL.path, &status) != 0 {
            return false
        }
        return (status.st_flags & UInt32(SF_DATALESS)) != 0
    }

    /// Off the main actor: which add-ons the course needs, and which of
    /// those a pass would ADD (rather than find there, or leave alone).
    @concurrent
    static func scan(courseAt coursePath: String) async -> (needed: [ObsidianFigureAddOn], wouldAdd: [ObsidianFigureAddOn]) {
        let courseURL: URL = URL(fileURLWithPath: coursePath)
        var kinds: Set<String> = []
        for addOn in ObsidianFigureAddOns.pinned {
            kinds.insert(addOn.kind)
        }
        let used: Set<String> = ObsidianFigureAddOns.kindsUsed(inCourseAt: courseURL, among: kinds)
        let needed: [ObsidianFigureAddOn] = ObsidianFigureAddOns.addOns(forKinds: used)
        return (needed: needed, wouldAdd: ObsidianFigureAddOns.wouldAdd(needed, inCourseAt: courseURL))
    }

    // MARK: - The list

    /// Reads `community-plugins.json`. Missing reads as no ids; anything that
    /// is not a JSON array of strings is unreadable.
    static func readList(_ data: Data?) -> ListReading {
        guard let data else {
            return .ids([])
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return .unreadable
        }
        guard let array = parsed as? [Any] else {
            return .unreadable
        }
        var ids: [String] = []
        for element in array {
            guard let id = element as? String else {
                return .unreadable
            }
            ids.append(id)
        }
        return .ids(ids)
    }

    /// The list with `adding` appended — every existing id kept in its order,
    /// none twice.
    static func ids(_ existing: [String], adding: [String]) -> [String] {
        var result: [String] = existing
        for id in adding {
            if !result.contains(id) {
                result.append(id)
            }
        }
        return result
    }

    /// The list as Obsidian writes it: `JSON.stringify(ids, undefined, 2)`,
    /// no newline at the end (measured from 1.13.7's `writeConfigJson`).
    static func listText(_ ids: [String]) -> String {
        if ids.isEmpty {
            return "[]"
        }
        var lines: [String] = []
        for id in ids {
            let encoded: Data = (try? JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
            lines.append("  " + String(decoding: encoded, as: UTF8.self))
        }
        return "[\n" + lines.joined(separator: ",\n") + "\n]"
    }

    /// The list after adding `adding` to what `listData` holds (nil: no
    /// file yet).
    static func listAfterAdding(_ adding: [String], to listData: Data?) -> ListAfter {
        guard case .ids(let listed) = ObsidianFigureAddOns.readList(listData) else {
            return .refused
        }
        let newList: [String] = ObsidianFigureAddOns.ids(listed, adding: adding)
        if newList == listed && listData != nil {
            return .unchanged
        }
        return .write(ObsidianFigureAddOns.listText(newList))
    }

    // MARK: - Deciding and installing

    /// The add-ons a pass would add, without writing — what decides whether
    /// there is anything to offer. A refused pass would add nothing.
    static func wouldAdd(_ addOns: [ObsidianFigureAddOn], inCourseAt courseURL: URL) -> [ObsidianFigureAddOn] {
        let settingsURL: URL = courseURL.appendingPathComponent(ObsidianAddOns.settingsFolderName)
        let pluginsURL: URL = settingsURL.appendingPathComponent("plugins")
        if ObsidianFigureAddOns.kind(of: settingsURL) == S_IFLNK || ObsidianFigureAddOns.kind(of: pluginsURL) == S_IFLNK {
            return []
        }
        let listData: Data? = try? Data(contentsOf: settingsURL.appendingPathComponent(ObsidianFigureAddOns.listName))
        guard case .ids(let listed) = ObsidianFigureAddOns.readList(listData) else {
            return []
        }
        var adding: [ObsidianFigureAddOn] = []
        for addOn in addOns {
            if case .add = ObsidianFigureAddOns.decide(addOn, pluginsURL: pluginsURL, listed: listed) {
                adding.append(addOn)
            }
        }
        return adding
    }

    /// Adds the add-ons a course needs. Pure file work, run by
    /// `ObsidianFigureAddOnsQueue` so two passes over one course never
    /// overlap (plan review S2). `carriedURL` holds `<id>/<file>`;
    /// `defaultsURL` is the bundled `support/obsidian_defaults/.obsidian`.
    static func install(
        _ addOns: [ObsidianFigureAddOn],
        inCourseAt courseURL: URL,
        carriedFrom carriedURL: URL?,
        defaultsFrom defaultsURL: URL?
    ) -> [Result] {
        if addOns.isEmpty {
            return []
        }
        ObsidianFigureAddOns.passesLock.lock()
        ObsidianFigureAddOns.passesRunning += 1
        if ObsidianFigureAddOns.passesRunning > ObsidianFigureAddOns.mostPassesSeen {
            ObsidianFigureAddOns.mostPassesSeen = ObsidianFigureAddOns.passesRunning
        }
        ObsidianFigureAddOns.passesLock.unlock()
        defer {
            ObsidianFigureAddOns.passesLock.lock()
            ObsidianFigureAddOns.passesRunning -= 1
            ObsidianFigureAddOns.passesLock.unlock()
        }
        let fileManager: FileManager = FileManager.default
        let settingsURL: URL = courseURL.appendingPathComponent(ObsidianAddOns.settingsFolderName)
        let pluginsURL: URL = settingsURL.appendingPathComponent("plugins")

        // 1. Links are never followed.
        if ObsidianFigureAddOns.kind(of: settingsURL) == S_IFLNK || ObsidianFigureAddOns.kind(of: pluginsURL) == S_IFLNK {
            return ObsidianFigureAddOns.every(addOns, .refusedLink)
        }

        // 2. The carried copy, re-hashed before anything is written.
        guard let carriedURL, ObsidianFigureAddOns.carriedCopyMatches(addOns, in: carriedURL) else {
            return ObsidianFigureAddOns.every(addOns, .refusedCarriedCopy)
        }

        // 3. The course's defaults first, or nothing.
        if ObsidianFigureAddOns.kind(of: settingsURL) == nil, let defaultsURL {
            try? fileManager.copyItem(at: defaultsURL, to: settingsURL)
        }
        if ObsidianFigureAddOns.kind(of: settingsURL.appendingPathComponent("app.json")) != S_IFREG {
            return ObsidianFigureAddOns.every(addOns, .refusedSettingsNotSeeded)
        }

        // 4. The list.
        let listURL: URL = settingsURL.appendingPathComponent(ObsidianFigureAddOns.listName)
        let listData: Data? = ObsidianFigureAddOns.kind(of: listURL) == nil ? nil : ((try? Data(contentsOf: listURL)) ?? Data())
        guard case .ids(let listed) = ObsidianFigureAddOns.readList(listData) else {
            return ObsidianFigureAddOns.every(addOns, .refusedListUnreadable)
        }

        // 5. Each add-on. A partial folder left by an earlier pass is ours by
        // name and is never anything but a leftover: it goes first.
        var results: [Result] = []
        var adding: [ObsidianFigureAddOn] = []
        for addOn in addOns {
            let partialURL: URL = pluginsURL.appendingPathComponent(addOn.id + ObsidianFigureAddOns.partialSuffix)
            if ObsidianFigureAddOns.kind(of: partialURL) != nil {
                try? fileManager.removeItem(at: partialURL)
            }
            switch ObsidianFigureAddOns.decide(addOn, pluginsURL: pluginsURL, listed: listed) {
            case .add:
                adding.append(addOn)
            case .keep(let outcome):
                results.append(Result(addOn: addOn, outcome: outcome))
            }
        }
        if adding.isEmpty {
            return ObsidianFigureAddOns.inPinnedOrder(results)
        }

        // 6. The list, then the files.
        var addingIDs: [String] = []
        for addOn in adding {
            addingIDs.append(addOn.id)
        }
        if case .write(let text) = ObsidianFigureAddOns.listAfterAdding(addingIDs, to: listData) {
            do {
                try Data(text.utf8).write(to: listURL, options: [.atomic])
            } catch {
                for addOn in adding {
                    results.append(Result(addOn: addOn, outcome: .couldNotWrite(reason: error.localizedDescription)))
                }
                return ObsidianFigureAddOns.inPinnedOrder(results)
            }
        }
        for addOn in adding {
            results.append(Result(
                addOn: addOn,
                outcome: ObsidianFigureAddOns.write(addOn, into: pluginsURL, from: carriedURL.appendingPathComponent(addOn.id))
            ))
        }
        return ObsidianFigureAddOns.inPinnedOrder(results)
    }

    /// Whether every file of these add-ons is carried, the size and SHA-256
    /// its pin says.
    static func carriedCopyMatches(_ addOns: [ObsidianFigureAddOn], in carriedURL: URL) -> Bool {
        for addOn in addOns {
            for file in addOn.files {
                let fileURL: URL = carriedURL.appendingPathComponent(addOn.id).appendingPathComponent(file.name)
                guard let data = try? Data(contentsOf: fileURL) else {
                    return false
                }
                if data.count != file.bytes {
                    return false
                }
                if ObsidianFigureAddOns.sha256(of: data) != file.sha256 {
                    return false
                }
            }
        }
        return true
    }

    /// Lowercase hex SHA-256.
    static func sha256(of data: Data) -> String {
        var text: String = ""
        for byte in SHA256.hash(data: data) {
            text += String(format: "%02x", byte)
        }
        return text
    }

    // MARK: - Backups

    /// The `zip -x` patterns that leave Plantoir's add-ons out of a zip of
    /// `folderURL`, zipped from its parent as `CourseArchiver` does (#495
    /// `backups`): the folders under `.obsidian/plugins` that carry the
    /// marker. The teacher's own add-ons are kept; so is the list, so a
    /// restored course gets them back at the next pass on a Mac whose answer
    /// is yes.
    static func backupExclusions(forFolderAt folderURL: URL) -> [String] {
        let pluginsURL: URL = folderURL
            .appendingPathComponent(ObsidianAddOns.settingsFolderName)
            .appendingPathComponent("plugins")
        if ObsidianFigureAddOns.kind(of: folderURL.appendingPathComponent(ObsidianAddOns.settingsFolderName)) != S_IFDIR {
            return []
        }
        if ObsidianFigureAddOns.kind(of: pluginsURL) != S_IFDIR {
            return []
        }
        var patterns: [String] = []
        for name in ObsidianFigureAddOns.plantoirAddOnFolders(inPluginsAt: pluginsURL) {
            let path: String = ObsidianFigureAddOns.zipLiteral(folderURL.lastPathComponent)
                + "/" + ObsidianAddOns.settingsFolderName + "/plugins/" + ObsidianFigureAddOns.zipLiteral(name)
            patterns.append(path + "/*")
            patterns.append(path)
        }
        return patterns
    }

    /// A name as `zip -x` reads it literally: zip treats `[`, `]`, `*` and `?`
    /// as wildcards, so a course called `MPM2D [old]` matched nothing and kept
    /// its add-ons (implementation review N1, measured).
    static func zipLiteral(_ name: String) -> String {
        var escaped: String = ""
        for character in name {
            if character == "[" || character == "]" || character == "*" || character == "?" || character == "\\" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// The folders under `plugins` that carry Plantoir's marker, sorted —
    /// partial and conflict copies included. Never follows a link.
    static func plantoirAddOnFolders(inPluginsAt pluginsURL: URL) -> [String] {
        var names: [String] = []
        for name in ReferenceTreeCopier.names(inFolderAt: pluginsURL) {
            let text: String = String(decoding: name, as: UTF8.self)
            if text.hasPrefix(".") {
                continue
            }
            let folderURL: URL = pluginsURL.appendingPathComponent(text)
            if ObsidianFigureAddOns.kind(of: folderURL) != S_IFDIR {
                continue
            }
            if ObsidianFigureAddOns.kind(of: folderURL.appendingPathComponent(ObsidianFigureAddOns.markerName)) == S_IFREG {
                names.append(text)
            }
        }
        names.sort()
        return names
    }

    // MARK: - Private helpers

    /// The vault-state table (`vaultCases`), for one add-on.
    private static func decide(_ addOn: ObsidianFigureAddOn, pluginsURL: URL, listed: [String]) -> Decision {
        let folderURL: URL = pluginsURL.appendingPathComponent(addOn.id)
        let folderKind: mode_t? = ObsidianFigureAddOns.kind(of: folderURL)
        if folderKind == nil {
            return .add
        }
        if folderKind != S_IFDIR {
            return .keep(.leftAloneUnreadable)
        }
        let hasMarker: Bool = ObsidianFigureAddOns.kind(of: folderURL.appendingPathComponent(ObsidianFigureAddOns.markerName)) == S_IFREG
        let version: String? = ObsidianFigureAddOns.manifestVersion(in: folderURL)
        guard let version else {
            if hasMarker {
                // Plantoir's own unfinished pass: replaced.
                return .add
            }
            return .keep(.leftAloneUnreadable)
        }
        if !hasMarker {
            return .keep(.leftAloneTheirs(version: version))
        }
        if version != addOn.version {
            return .keep(.leftAloneOtherVersion(version: version))
        }
        if listed.contains(addOn.id) {
            return .keep(.alreadyThere)
        }
        return .keep(.alreadyThereSwitchedOff)
    }

    /// The `version` a folder's `manifest.json` says, or nil when it cannot
    /// be read.
    private static func manifestVersion(in folderURL: URL) -> String? {
        let manifestURL: URL = folderURL.appendingPathComponent("manifest.json")
        if ObsidianFigureAddOns.kind(of: manifestURL) != S_IFREG {
            return nil
        }
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        guard let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return manifest["version"] as? String
    }

    /// Writes one add-on: partial folder, marker, rename, manifest last.
    private static func write(_ addOn: ObsidianFigureAddOn, into pluginsURL: URL, from sourceURL: URL) -> Outcome {
        let fileManager: FileManager = FileManager.default
        let folderURL: URL = pluginsURL.appendingPathComponent(addOn.id)
        let partialURL: URL = pluginsURL.appendingPathComponent(addOn.id + ObsidianFigureAddOns.partialSuffix)
        do {
            try fileManager.createDirectory(at: pluginsURL, withIntermediateDirectories: true)
            if ObsidianFigureAddOns.kind(of: folderURL) != nil {
                // Only reached for Plantoir's own unfinished copy (`decide`).
                try fileManager.removeItem(at: folderURL)
            }
            try fileManager.createDirectory(at: partialURL, withIntermediateDirectories: false)
            for file in addOn.files where file.name != "manifest.json" {
                try fileManager.copyItem(at: sourceURL.appendingPathComponent(file.name), to: partialURL.appendingPathComponent(file.name))
            }
            try Data(ObsidianFigureAddOns.markerText(version: addOn.version).utf8)
                .write(to: partialURL.appendingPathComponent(ObsidianFigureAddOns.markerName), options: [.atomic])
            try fileManager.moveItem(at: partialURL, to: folderURL)
            let manifest: Data = try Data(contentsOf: sourceURL.appendingPathComponent("manifest.json"))
            try manifest.write(to: folderURL.appendingPathComponent("manifest.json"), options: [.atomic])
            return .added
        } catch {
            try? fileManager.removeItem(at: partialURL)
            return .couldNotWrite(reason: error.localizedDescription)
        }
    }

    /// The same outcome for every add-on.
    private static func every(_ addOns: [ObsidianFigureAddOn], _ outcome: Outcome) -> [Result] {
        var results: [Result] = []
        for addOn in addOns {
            results.append(Result(addOn: addOn, outcome: outcome))
        }
        return results
    }

    /// Results in the pinned order, so a trail line reads the same way
    /// every time.
    private static func inPinnedOrder(_ results: [Result]) -> [Result] {
        var ordered: [Result] = []
        for pinnedAddOn in ObsidianFigureAddOns.pinned {
            for result in results where result.addOn.id == pinnedAddOn.id {
                ordered.append(result)
            }
        }
        for result in results {
            var isPinned: Bool = false
            for pinnedAddOn in ObsidianFigureAddOns.pinned where pinnedAddOn.id == result.addOn.id {
                isPinned = true
            }
            if !isPinned {
                ordered.append(result)
            }
        }
        return ordered
    }

    /// What kind of thing is at a path, without following a link — or nil
    /// when nothing is.
    private static func kind(of url: URL) -> mode_t? {
        var status: stat = stat()
        if lstat(url.path, &status) != 0 {
            return nil
        }
        return status.st_mode & S_IFMT
    }
}

/// The one place installs run, so two passes over a course never overlap
/// (plan review S2): Open in Obsidian and a preview finishing can both ask at
/// once, and the second pass's "remove a leftover partial folder" would
/// otherwise delete the first pass's folder while it is being written. An
/// actor whose one method does all its work without suspending runs passes
/// one after another — every course's, which costs nothing at this size.
actor ObsidianFigureAddOnsQueue {

    // MARK: - Stored properties

    static let shared: ObsidianFigureAddOnsQueue = ObsidianFigureAddOnsQueue()

    // MARK: - Functions

    func install(
        _ addOns: [ObsidianFigureAddOn],
        inCourseAt coursePath: String,
        carriedFrom carriedURL: URL?,
        defaultsFrom defaultsURL: URL?
    ) -> [ObsidianFigureAddOns.Result] {
        return ObsidianFigureAddOns.install(
            addOns,
            inCourseAt: URL(fileURLWithPath: coursePath),
            carriedFrom: carriedURL,
            defaultsFrom: defaultsURL
        )
    }
}
