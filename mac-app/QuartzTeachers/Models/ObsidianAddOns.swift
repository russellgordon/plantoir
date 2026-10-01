import Foundation

/// What of a course's Obsidian settings is left behind when a REFERENCE
/// course is made from it — on every route that makes one (#255).
///
/// Four routes make a reference course: "Keep a Copy for Reference…", and
/// "Import Courses for Reference…" reading a modern working folder, the older
/// folder-per-class layout (#254) or the 2024–25 website-folder-per-class
/// layout (#256). **All four leave the same three entries of `.obsidian`
/// behind**, and this file is the one place they are named:
///
/// * `plugins/` — every community add-on, its code and its settings. An
///   add-on runs code with network access, and a publishing add-on keeps its
///   credential in its own `data.json`: every real 2023–24 class folder
///   carries `digitalgarden/data.json` with a live `githubToken`. Copied, that
///   credential lands in the working folder and in every backup zip, and once
///   Obsidian trusts the vault's add-ons it is a way to publish the course
///   outside all fifteen of Plantoir's refusals.
/// * `community-plugins.json` — the list of add-ons Obsidian switches on.
/// * `publish.json` — core Obsidian Publish's connection: the site id and the
///   host of a LIVE site. Measured in Obsidian 1.13.6's own code: a core
///   add-on's `loadData` is `vault.readConfigJson(id)`, which reads
///   `<configDir>/<id>.json`, and Publish's data is `{siteId, host, included,
///   excluded}`. Core Sync keeps its remote in the app's own storage, keyed
///   by the vault, so a copied folder carries nothing of it.
///
/// Everything else in `.obsidian` comes: appearance, themes, snippets,
/// `app.json`, `workspace.json` and its conflicted copies. None of it runs
/// code or reaches a website.
///
/// **Anchored at the course's own `.obsidian`, never matched by name.** A
/// teacher's own folder of pages called `plugins` — anywhere in the course —
/// comes across; only `.obsidian/plugins` stays. `ReferenceTreeCopier.walk`
/// matches its by-NAME list at every depth, which is exactly why these are
/// PATHS, compared against where the walk is rather than what a thing is
/// called.
///
/// **Skipped, never walked and filtered.** Each is skipped before it is so
/// much as `lstat`-ed, so a folder inside an add-on that the disk will not
/// hand over cannot refuse a course for something that was never going to be
/// copied.
nonisolated enum ObsidianAddOns {

    // MARK: - Types

    /// What a course's `.obsidian` holds that will be left behind — enough
    /// for the sheet to decide whether to say so, and for the trail line to
    /// name it. Folder NAMES only: nothing inside an add-on is ever opened.
    struct Found: Sendable, Equatable {

        // MARK: - Stored properties

        /// The add-ons installed, by folder name, sorted. A name starting
        /// with a dot is not an add-on (`.DS_Store`, `.hotreload`).
        var addOnNames: [String] = []

        /// `.obsidian/plugins` is itself a link. Never followed, so what it
        /// leads to is not known — and it is said, because an add-on folder
        /// shared between vaults is the usual reason for one.
        var addOnsFolderIsALink: Bool = false

        /// `.obsidian/plugins` is a folder the disk would not list. Something
        /// is there, so it is said rather than taken for nothing.
        var addOnsFolderCouldNotBeRead: Bool = false

        /// `.obsidian` ITSELF is a link — one settings folder shared between
        /// several vaults, a known Obsidian practice. A modern copy would
        /// otherwise carry the link across and the reference course would be
        /// reading, and `ReferenceReadingView` WRITING, the live settings.
        var settingsFolderIsALink: Bool = false

        /// `.obsidian/publish.json` is there: core Obsidian Publish was
        /// connected to a site.
        var publishSiteIsSet: Bool = false

        // MARK: - Computed properties

        /// True when there is nothing to say. An EMPTY `plugins/` and a
        /// `community-plugins.json` of `[]` — measured in Russell's own ICS3U
        /// — are nothing: telling a teacher their add-ons were left behind
        /// when they had none would be false.
        var isEmpty: Bool {
            if !addOnNames.isEmpty {
                return false
            }
            if addOnsFolderIsALink || addOnsFolderCouldNotBeRead {
                return false
            }
            if settingsFolderIsALink || publishSiteIsSet {
                return false
            }
            return true
        }
    }

    // MARK: - Stored properties

    /// Obsidian's settings folder, at the top of the course.
    static let settingsFolderName: String = ".obsidian"

    /// The three entries of `.obsidian` that stay behind, relative to it.
    /// ASCII, so comparing a walk's path as text is exact.
    static let leftBehindInsideTheSettingsFolder: [String] = [
        "plugins",
        "community-plugins.json",
        "publish.json",
    ]

    // MARK: - Computed properties

    /// The same, relative to the COURSE — what a walk from the course's own
    /// folder passes as `leavingBehindPaths`.
    static var leftBehindFromTheCourse: Set<String> {
        var paths: Set<String> = []
        for entry in ObsidianAddOns.leftBehindInsideTheSettingsFolder {
            paths.insert(ObsidianAddOns.settingsFolderName + "/" + entry)
        }
        return paths
    }

    /// The same, relative to `.obsidian` — what a walk that starts INSIDE it
    /// passes (the 2024–25 layout walks `content/.obsidian` on its own).
    static var leftBehindFromTheSettingsFolder: Set<String> {
        var paths: Set<String> = []
        for entry in ObsidianAddOns.leftBehindInsideTheSettingsFolder {
            paths.insert(entry)
        }
        return paths
    }

    /// Left behind only when it is a LINK: a real `.obsidian` comes (without
    /// the three above), a linked one does not come at all. The older layout
    /// never copies a link anywhere and the 2024–25 layout judges every link
    /// at the top of `content/` on its own, so only the modern routes pass
    /// this.
    static var leftBehindWhenALinkFromTheCourse: Set<String> {
        return [ObsidianAddOns.settingsFolderName]
    }

    // MARK: - Functions

    /// What a course's `.obsidian` holds that a reference copy leaves
    /// behind. One `lstat` per entry and one listing of `plugins/`; nothing is
    /// followed and nothing inside an add-on is looked at.
    static func found(inCourseAt courseURL: URL) -> Found {
        var found: Found = Found()
        let settingsURL: URL = courseURL.appendingPathComponent(ObsidianAddOns.settingsFolderName)

        let settingsKind: mode_t? = ObsidianAddOns.kind(of: settingsURL)
        if settingsKind == S_IFLNK {
            found.settingsFolderIsALink = true
            return found
        }
        if settingsKind != S_IFDIR {
            return found
        }

        let pluginsURL: URL = settingsURL.appendingPathComponent("plugins")
        let pluginsKind: mode_t? = ObsidianAddOns.kind(of: pluginsURL)
        if pluginsKind == S_IFLNK {
            found.addOnsFolderIsALink = true
        } else if pluginsKind == S_IFDIR {
            if let directory = opendir(pluginsURL.path) {
                closedir(directory)
                var names: [String] = []
                for name in ReferenceTreeCopier.names(inFolderAt: pluginsURL) {
                    let text: String = String(decoding: name, as: UTF8.self)
                    if text.hasPrefix(".") {
                        continue
                    }
                    names.append(text)
                }
                found.addOnNames = names
            } else {
                found.addOnsFolderCouldNotBeRead = true
            }
        }

        if ObsidianAddOns.kind(of: settingsURL.appendingPathComponent("publish.json")) != nil {
            found.publishSiteIsSet = true
        }
        return found
    }

    /// What the trail line gains when something was left behind — folder
    /// names only — and NOTHING at all when nothing was, so the line for a
    /// course without add-ons is byte-for-byte what it was before #255.
    ///
    /// Used by the MODERN routes' lines only ("course kept for reference",
    /// and "course imported for reference" for a modern course). The older
    /// layouts already count their add-on entries on their own second line,
    /// and saying it twice would be two answers to one question.
    static func trailClause(for found: Found) -> String {
        var clauses: [String] = []
        if !found.addOnNames.isEmpty {
            let noun: String = found.addOnNames.count == 1 ? "add-on" : "add-ons"
            clauses.append(
                "\(found.addOnNames.count) Obsidian \(noun) left behind ("
                + found.addOnNames.joined(separator: ", ") + ")"
            )
        }
        if found.addOnsFolderIsALink {
            clauses.append("Obsidian's add-ons folder was a link and was left behind")
        }
        if found.addOnsFolderCouldNotBeRead {
            clauses.append("Obsidian's add-ons folder could not be read and was left behind")
        }
        if found.settingsFolderIsALink {
            clauses.append("Obsidian's settings folder was a link and was left behind")
        }
        if found.publishSiteIsSet {
            clauses.append("Obsidian Publish's site setting was left behind")
        }
        var result: String = ""
        for clause in clauses {
            result += "; " + clause
        }
        return result
    }

    // MARK: - Private helpers

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
