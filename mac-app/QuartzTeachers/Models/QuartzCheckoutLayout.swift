import Foundation

/// Russell's 2024–25 way of keeping a course: one whole WEBSITE folder per
/// class section — `~/Documents/Class Websites/2024-25/ICS3U/S1` — holding
/// the program that built the site (`quartz/`) and, inside it, the pages
/// (`quartz/content/source-ics3u/{shared, s1, s2}`). The folder the teacher
/// actually opened in Obsidian, `quartz/content`, is made mostly of LINKS
/// into `source-ics3u`, and the folder in iCloud he named in the issue holds
/// only two Finder shortcuts, `S1` and `S2`, pointing at those folders.
///
/// This file READS that shape and says how the FIRST section of it becomes a
/// single-section reference course. It never writes: the copying is
/// `ReferenceTreeCopier`, the making-into-a-reference-course is
/// `ReferenceCopier`, and the whole act is `ReferenceImporter`. Issue #256;
/// the measurements and what was rejected are in
/// `documentation/09-mac-app.md` → "The 2024–25 layout: a website folder per
/// class (#256)", and the rule itself is data in `contracts/shared-rules.json`
/// → `referenceCourses.importing.quartzCheckoutLayout`.
///
/// Four rules this file exists to keep:
///
/// 1. **Nothing is ever FOLLOWED, except a real Finder shortcut.** Every
///    entry is asked about with `lstat`. A shortcut is a regular FILE that
///    Finder marks as an alias; `isAliasFileKey` is ALSO true for a symbolic
///    link, and resolving one follows it (measured), so a link is never
///    taken for a shortcut — `isShortcut(_:)` checks both halves.
/// 2. **The pages are read BY NAME from the folder pointed at** —
///    `content/source-<code>/shared` and `…/s1` — never through the links,
///    and never from another section's copy. S1's and S2's copies differ
///    (335 entries), and each is exactly what its own site was built from.
/// 3. **Only the first section comes across** (Russell, 2026-09-23). A
///    later section is shown or refused with a sentence that says so.
/// 4. **Left behind is not lost.** The website's own program files, the
///    folders kept for editing, the other sections' pages and the links
///    are machinery and are COUNTED as left behind; anything the site
///    showed that does not come across is a LOSS, and is NAMED.
nonisolated enum QuartzCheckoutLayout {

    // MARK: - Types

    /// How the section a website folder built was told.
    enum SectionFrom: String, Sendable, Equatable {
        /// The TEXT of `content/index.md`, which is a link to
        /// `source-<code>/s<N>/index.md` — what the site was really built
        /// from. Read with `destinationOfSymbolicLink`, never followed.
        case frontPage
        /// The website folder's own name, `S<N>`.
        case folderName
        /// The only `s<N>` there is.
        case onlyOne
    }

    /// Why a Finder shortcut could not be read through.
    enum ShortcutTrouble: String, Sendable, Equatable {
        /// What it points at is no longer there.
        case gone
        /// It is there, and this Mac would not let Plantoir open it — the
        /// shape of a refused Documents permission.
        case couldNotBeOpened
        /// It is on a disk that is not connected.
        case diskNotConnected
        /// It points at a FILE, not a folder.
        case leadsToAFile
    }

    /// What reading a Finder shortcut came to.
    enum ShortcutTarget: Sendable, Equatable {
        /// Not a shortcut at all (a link, a folder, a plain file).
        case notAShortcut
        /// It leads to this folder.
        case folder(URL)
        /// It leads nowhere Plantoir can go, and why.
        case trouble(ShortcutTrouble, disk: String?)
    }

    /// One entry of a chosen folder that is, or might have been, a website
    /// folder: a real one, one reached through a shortcut, or a shortcut
    /// to a folder that could not be read through.
    struct Candidate: Sendable, Equatable {

        // MARK: - Stored properties

        /// Its name WHERE IT WAS FOUND — `S1`, the shortcut's own name when
        /// it is one. Unique within the folder by construction, whereas two
        /// shortcuts can lead to two folders both called `S1`.
        let rowName: String

        /// The website folder itself, or nil for a shortcut that leads
        /// nowhere.
        let websiteURL: URL?

        /// The shortcut's own name, when it was reached through one.
        let shortcutName: String?

        /// Why a shortcut could not be read through, or nil.
        let trouble: ShortcutTrouble?

        /// The disk's name, for `.diskNotConnected`.
        let disk: String?
    }

    /// What one website folder is, as the sheet carries it.
    struct Facts: Sendable, Equatable {

        // MARK: - Stored properties

        let rowName: String
        let websiteURL: URL?
        let shortcutName: String?
        let trouble: ShortcutTrouble?

        /// From `source-<code>`, upper-cased.
        let code: String?

        /// The section this folder built, or nil when it could not be told.
        let section: Int?
        let sectionFrom: SectionFrom?

        /// The section the FOLDER'S NAME says, when it says one — kept so a
        /// renamed folder whose front page disagrees is noted on the trail.
        let sectionTheNameSays: Int?

        /// `source-ics3u`, or nil.
        let coursePagesFolderName: String?

        /// Where the pages are read from, as a teacher reads a path.
        let place: String
    }

    /// Machinery, left behind by design and COUNTED — never a loss.
    enum LeftBehindKind: String, Sendable, Equatable, CaseIterable {
        /// Everything inside `quartz/` other than `content/`: the program,
        /// its settings, `public/`, `.quartz-cache`, `docs/`, the scripts.
        case theBuildersOwnFiles
        /// The links at the top of `content/`, each replaced by the real
        /// page or folder it showed.
        case shortcutsReplaced
        /// `content/vault-*` — folders made of links, for editing.
        case editingFolders
        /// `source-<code>/s<M>` for every M other than 1.
        case anotherSectionsPages
        /// Anything else in `source-<code>` that no link showed.
        case notOnTheWebsite
        /// `.obsidian/plugins` and `.obsidian/community-plugins.json`.
        case addOns
    }

    /// Why something the site SHOWED does not come across. Each is a loss.
    enum LostReason: String, Sendable, Equatable {
        /// A link at the top of `content/` pointed somewhere other than the
        /// page or folder of its own name in `source-<code>/shared` or `/s1`.
        case linkShowedSomethingElse
        /// A link at the top of `content/` named something that is not there.
        case linkNameWithNoPage
        /// A link INSIDE the pages, or inside `.obsidian`.
        case link
        /// A shared page or folder with the same name as one of the
        /// section's own: the build would put both at one place.
        case nameTheSectionUses
        /// A shared entry named `index.md`, `section1` or
        /// `course_config.json`, which the new course uses for itself.
        case nameTheCourseUses
        /// No `s1/index.md`: the course would have no front page.
        case noFrontPage
    }

    /// One thing lost, by where it was.
    struct Lost: Sendable, Equatable {

        // MARK: - Stored properties

        /// Its path inside `content/` (a link) or `source-<code>/`.
        let path: String
        let reason: LostReason
    }

    /// The whole mapping of one website folder's first section into a
    /// modern course, as data.
    struct Plan: Sendable {

        // MARK: - Stored properties

        let placements: [ReferenceTreeCopier.Placement]
        let lost: [Lost]

        /// How many of each kind of machinery was left behind.
        let leftBehind: [LeftBehindKind: Int]

        /// The names of the editing folders and of the other sections, for
        /// the trail.
        let editingFolderNames: [String]
        let otherSectionNames: [String]

        /// Folders inside `quartz/` skipped by name without being looked
        /// inside (`node_modules`, `.git`): counted as one entry each.
        let notLookedInside: [String]

        let createsEmptyMedia: Bool
        let fileCount: Int
        let byteCount: Int64
        let pageCount: Int
        let pageYears: [Int]
        let unreadableFolders: [String]

        let courseCode: String
        let courseName: String
        let sharedFolders: [String]
        let sharedFiles: [String]
        let perSectionFolders: [String]
        let perSectionFiles: [String]

        /// The word the class pages use (`Thread`), or nil when they do not
        /// all agree on one.
        let unitWord: String?

        /// Class pages set aside as placeholders (`Thread 2, Day x`).
        let placeholderPages: Int

        // MARK: - Computed properties

        /// Every loss, by path, in a stable order.
        var lostPaths: [String] {
            var paths: [String] = []
            for entry in lost {
                paths.append(entry.path)
            }
            return paths
        }

        // MARK: - Functions

        /// The course's settings, before `ReferenceCopier` marks, files,
        /// neutralises and locks it. Every key is one `file-formats.json →
        /// courseConfigKeys` already documents; none is new.
        func settingsValues() -> [String: Any] {
            var expandable: [String] = []
            for name in sharedFolders {
                expandable.append(name)
            }
            for name in perSectionFolders {
                expandable.append(name)
            }
            var values: [String: Any] = [
                "course_code": courseCode,
                "course_name": courseName,
                "num_sections": 1,
                "section_numbers": [1],
                "shared_folders": sharedFolders,
                "shared_files": sharedFiles,
                "per_section_folders": perSectionFolders,
                "per_section_files": perSectionFiles,
                "expandable": expandable,
                "hidden": ["Media"],
                // A plain false, as #254 writes and for its reasons.
                "include_curriculum_coverage": false,
                // As #254, so every single-section import reads the same.
                "show_section_marker": ["sections": ["section1": false]],
            ]
            // Without it the word is "Unit", no page here is a class page,
            // and the build's post-pass restamps every lesson's date to one
            // day (`_sync_non_class_pages_created`). Measured in the
            // rehearsal; see the contract's `placement.whyUnitWord`.
            if let unitWord {
                values["unit_word"] = unitWord
            }
            return values
        }
    }

    /// What a chosen folder turned out to be.
    enum Recognised: Equatable {
        /// One website folder (chosen, or its `quartz` or `quartz/content`
        /// folder chosen, or a shortcut to one chosen).
        case website(Candidate)
        /// A folder holding website folders or shortcuts to them.
        case folderOfWebsites(URL, [Candidate])
        /// A folder inside a website folder's pages, of section 1 or shared.
        case partOfAWebsite(checkoutName: String)
        /// A folder inside a website folder that holds a LATER section's
        /// pages (`source-ics3u/s2`, `vault-ics3u-s2`).
        case aLaterSection(section: Int)
        /// A folder holding several courses' folders of websites.
        case severalCourses
        /// A shortcut chosen on its own that cannot be read through.
        case shortcutTrouble(Candidate)
        case nothing
    }

    // MARK: - Stored properties

    /// Where every import puts the section's own pages.
    static let sectionFolderName: String = "section1"

    /// The section this layout can bring across (Russell, 2026-09-23).
    static let importableSection: Int = 1

    /// Names a shared entry may not use, because the course uses them.
    static let namesTheCourseUses: Set<String> = ["index.md", "section1", "course_config.json"]

    /// Names in a class folder the build never calls a class page.
    static let neverAClassPage: Set<String> = ["index.md", "key links.md", "curriculum coverage.md"]

    // MARK: - Functions (the website folder)

    /// A website folder: a real folder holding a real folder `quartz/`,
    /// which holds a regular file `quartz.config.ts` and a real folder
    /// `content/`. Named after what the machinery IS, never after what a
    /// teacher called it.
    static func isWebsiteFolder(_ folderURL: URL) -> Bool {
        guard OlderCourseLayout.kind(of: folderURL) == S_IFDIR else {
            return false
        }
        let program: URL = folderURL.appendingPathComponent("quartz")
        guard OlderCourseLayout.kind(of: program) == S_IFDIR else {
            return false
        }
        return OlderCourseLayout.kind(of: program.appendingPathComponent("quartz.config.ts")) == S_IFREG
            && OlderCourseLayout.kind(of: program.appendingPathComponent("content")) == S_IFDIR
    }

    /// `X/quartz/content`.
    static func contentURL(of websiteURL: URL) -> URL {
        return websiteURL.appendingPathComponent("quartz").appendingPathComponent("content")
    }

    /// The course pages folders directly in `content/`: real folders named
    /// `source-<code>` (any case), `<code>` Ontario-shaped, holding at least
    /// one real `s<digits>` folder. A link is never one.
    static func coursePagesFolders(of websiteURL: URL) -> [String] {
        let content: URL = QuartzCheckoutLayout.contentURL(of: websiteURL)
        var found: [String] = []
        for name in ReferenceTreeCopier.names(inFolderAt: content) {
            let text: String = String(decoding: name, as: UTF8.self)
            guard text.lowercased().hasPrefix("source-"),
                  OlderCourseLayout.kind(ofEntry: name, inFolderAt: content) == S_IFDIR else {
                continue
            }
            let codePart: String = String(text.dropFirst("source-".count))
            guard codePart.count == 5, OlderCourseLayout.nameFacts(of: codePart).code != nil else {
                continue
            }
            if !QuartzCheckoutLayout.sectionNumbers(in: content.appendingPathComponent(text)).isEmpty {
                found.append(text)
            }
        }
        found.sort()
        return found
    }

    /// A website folder that carries a course: at least one course pages
    /// folder. One without (Math Club) is left out entirely — Russell,
    /// 2026-09-23.
    static func isCourseWebsite(_ folderURL: URL) -> Bool {
        return QuartzCheckoutLayout.isWebsiteFolder(folderURL)
            && !QuartzCheckoutLayout.coursePagesFolders(of: folderURL).isEmpty
    }

    /// The `s<digits>` folders in a course pages folder, as numbers, sorted.
    static func sectionNumbers(in coursePagesURL: URL) -> [Int] {
        var numbers: [Int] = []
        for name in ReferenceTreeCopier.names(inFolderAt: coursePagesURL) {
            let text: String = String(decoding: name, as: UTF8.self)
            guard let number = QuartzCheckoutLayout.sectionNumber(inName: text, prefix: "s"),
                  OlderCourseLayout.kind(ofEntry: name, inFolderAt: coursePagesURL) == S_IFDIR else {
                continue
            }
            numbers.append(number)
        }
        numbers.sort()
        return numbers
    }

    /// `s2` → 2 (any case); nil for anything else.
    static func sectionNumber(inName name: String, prefix: String) -> Int? {
        let lowered: String = name.lowercased()
        guard lowered.hasPrefix(prefix) else {
            return nil
        }
        let digits: String = String(lowered.dropFirst(prefix.count))
        if digits.isEmpty {
            return nil
        }
        for character in digits where !(character.isASCII && character.isNumber) {
            return nil
        }
        return Int(digits)
    }

    // MARK: - Functions (shortcuts)

    /// A Finder shortcut: `isAliasFileKey` true AND a regular file by
    /// `lstat`. The second half is the one that matters — a symbolic link
    /// answers `isAliasFile == true` too, and is never a shortcut.
    static func isShortcut(_ url: URL) -> Bool {
        guard OlderCourseLayout.kind(of: url) == S_IFREG else {
            return false
        }
        let values: URLResourceValues? = try? url.resourceValues(forKeys: [.isAliasFileKey])
        return values?.isAliasFile == true
    }

    /// Where a shortcut leads, WITHOUT a dialog and without mounting a
    /// network disk. When it cannot be read through, its STORED path and
    /// kind are read from the bookmark itself, so a folder that is gone, a
    /// folder this Mac would not let Plantoir open, a disk that is not
    /// connected and a shortcut to a FILE are told apart.
    static func shortcutTarget(of url: URL) -> ShortcutTarget {
        guard QuartzCheckoutLayout.isShortcut(url) else {
            return .notAShortcut
        }
        if let resolved = try? URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) {
            let target: URL = resolved.standardizedFileURL
            let kind: mode_t? = OlderCourseLayout.kind(of: target)
            if kind == S_IFDIR {
                return .folder(target)
            }
            if kind == S_IFREG {
                return .trouble(.leadsToAFile, disk: nil)
            }
            return .trouble(.gone, disk: nil)
        }

        // Not readable through: ask the bookmark what it was.
        guard let data = try? URL.bookmarkData(withContentsOf: url),
              let stored = URL.resourceValues(
                forKeys: [.pathKey, .isDirectoryKey, .volumeNameKey], fromBookmarkData: data
              ) else {
            return .trouble(.gone, disk: nil)
        }
        if stored.isDirectory == false {
            return .trouble(.leadsToAFile, disk: nil)
        }
        guard let path = stored.path else {
            return .trouble(.gone, disk: nil)
        }
        var status: stat = stat()
        if lstat(path, &status) == 0 {
            // There, and still not readable through: refused.
            return .trouble(.couldNotBeOpened, disk: nil)
        }
        let failure: Int32 = errno
        if failure == EACCES || failure == EPERM {
            return .trouble(.couldNotBeOpened, disk: nil)
        }
        // On a disk under /Volumes that is not mounted.
        var parts: [String] = []
        for part in path.split(separator: "/") {
            parts.append(String(part))
        }
        if parts.count >= 2, parts[0] == "Volumes" {
            let volumePath: String = "/Volumes/" + parts[1]
            if OlderCourseLayout.kind(of: URL(fileURLWithPath: volumePath)) == nil {
                return .trouble(.diskNotConnected, disk: stored.volumeName ?? parts[1])
            }
        }
        return .trouble(.gone, disk: nil)
    }

    // MARK: - Functions (recognition)

    /// The candidates directly in a folder: real sub-folders that are course
    /// websites, shortcuts that lead to one, and shortcuts to a FOLDER that
    /// cannot be read through (shown, so nothing is dropped in silence).
    /// A shortcut to a file is passed over exactly as a file is; a
    /// sub-folder that is a link is never one.
    static func candidates(in folderURL: URL) -> [Candidate] {
        var found: [Candidate] = []
        for name in ReferenceTreeCopier.names(inFolderAt: folderURL) {
            let text: String = String(decoding: name, as: UTF8.self)
            let entryURL: URL = ReferenceTreeCopier.url(named: name, inFolderAt: folderURL)
            let kind: mode_t? = OlderCourseLayout.kind(ofEntry: name, inFolderAt: folderURL)
            if kind == S_IFDIR {
                if QuartzCheckoutLayout.isCourseWebsite(entryURL) {
                    found.append(Candidate(
                        rowName: text, websiteURL: entryURL, shortcutName: nil, trouble: nil, disk: nil
                    ))
                }
                continue
            }
            guard kind == S_IFREG else {
                continue
            }
            switch QuartzCheckoutLayout.shortcutTarget(of: entryURL) {
            case .notAShortcut:
                continue
            case .folder(let target):
                if QuartzCheckoutLayout.isCourseWebsite(target) {
                    found.append(Candidate(
                        rowName: text, websiteURL: target, shortcutName: text, trouble: nil, disk: nil
                    ))
                }
            case .trouble(let trouble, let disk):
                if trouble == .leadsToAFile {
                    continue
                }
                found.append(Candidate(
                    rowName: text, websiteURL: nil, shortcutName: text, trouble: trouble, disk: disk
                ))
            }
        }
        found.sort { first, second in
            return first.rowName.localizedStandardCompare(second.rowName) == .orderedAscending
        }
        return found
    }

    /// True when any candidate leads to a website.
    static func anyReadable(_ candidates: [Candidate]) -> Bool {
        for candidate in candidates where candidate.websiteURL != nil {
            return true
        }
        return false
    }

    /// What a chosen folder is. Tried third, after the modern shapes and
    /// #254's older layout; `.nothing` then means `noCoursesThere`.
    static func recognise(_ chosen: URL) -> Recognised {
        let chosenURL: URL = chosen.standardizedFileURL
        let chosenName: String = chosenURL.lastPathComponent

        // A shortcut chosen on its own (a drag, or a caller that did not
        // resolve it — the folder chooser itself resolves one).
        switch QuartzCheckoutLayout.shortcutTarget(of: chosenURL) {
        case .notAShortcut:
            break
        case .folder(let target):
            if QuartzCheckoutLayout.isCourseWebsite(target) {
                return .website(Candidate(
                    rowName: chosenName, websiteURL: target, shortcutName: chosenName, trouble: nil, disk: nil
                ))
            }
            return .nothing
        case .trouble(let trouble, let disk):
            return .shortcutTrouble(Candidate(
                rowName: chosenName, websiteURL: nil, shortcutName: chosenName, trouble: trouble, disk: disk
            ))
        }

        // The website folder, or one or two levels too deep in it.
        if QuartzCheckoutLayout.isCourseWebsite(chosenURL) {
            return .website(Candidate(
                rowName: chosenName, websiteURL: chosenURL, shortcutName: nil, trouble: nil, disk: nil
            ))
        }
        let parent: URL = chosenURL.deletingLastPathComponent()
        if chosenName == "quartz", QuartzCheckoutLayout.isCourseWebsite(parent) {
            return .website(Candidate(
                rowName: parent.lastPathComponent, websiteURL: parent, shortcutName: nil, trouble: nil, disk: nil
            ))
        }
        let grandparent: URL = parent.deletingLastPathComponent()
        if chosenName == "content", parent.lastPathComponent == "quartz",
           QuartzCheckoutLayout.isCourseWebsite(grandparent) {
            return .website(Candidate(
                rowName: grandparent.lastPathComponent, websiteURL: grandparent,
                shortcutName: nil, trouble: nil, disk: nil
            ))
        }

        // Anything else inside a website folder: never resolved UPWARD —
        // `s2/` resolved to its website folder would import section 1, the
        // opposite of what was pointed at.
        if let inside = QuartzCheckoutLayout.insideAWebsite(chosenURL) {
            return inside
        }

        // Folders of websites: the chosen folder's own entries, and its
        // children's. Counted, never named.
        let direct: [Candidate] = QuartzCheckoutLayout.candidates(in: chosenURL)
        var readableGroups: [URL] = []
        var unreadableGroups: [URL] = []
        for name in ReferenceTreeCopier.names(inFolderAt: chosenURL) {
            guard OlderCourseLayout.kind(ofEntry: name, inFolderAt: chosenURL) == S_IFDIR else {
                continue
            }
            let childURL: URL = ReferenceTreeCopier.url(named: name, inFolderAt: chosenURL)
            if QuartzCheckoutLayout.isWebsiteFolder(childURL) {
                continue
            }
            let inChild: [Candidate] = QuartzCheckoutLayout.candidates(in: childURL)
            if QuartzCheckoutLayout.anyReadable(inChild) {
                readableGroups.append(childURL)
            } else if !inChild.isEmpty {
                unreadableGroups.append(childURL)
            }
        }

        if QuartzCheckoutLayout.anyReadable(direct) {
            if !readableGroups.isEmpty {
                return .severalCourses
            }
            return .folderOfWebsites(chosenURL, direct)
        }
        if readableGroups.count >= 2 {
            return .severalCourses
        }
        if readableGroups.count == 1 {
            let only: URL = readableGroups[0]
            return .folderOfWebsites(only, QuartzCheckoutLayout.candidates(in: only))
        }
        // Nothing readable anywhere: shortcuts that lead nowhere are still
        // SHOWN, each with its reason, rather than "no courses".
        if !direct.isEmpty {
            return .folderOfWebsites(chosenURL, direct)
        }
        if unreadableGroups.count == 1 {
            let only: URL = unreadableGroups[0]
            return .folderOfWebsites(only, QuartzCheckoutLayout.candidates(in: only))
        }
        return .nothing
    }

    /// A folder inside a course website's `quartz/`, found by walking the
    /// chosen path's ancestors: a later section's pages, or anything else.
    static func insideAWebsite(_ chosenURL: URL) -> Recognised? {
        var components: [String] = chosenURL.pathComponents
        var below: [String] = []
        while components.count > 1 {
            let last: String = components.removeLast()
            below.insert(last, at: 0)
            let ancestor: URL = URL(fileURLWithPath: NSString.path(withComponents: components))
            guard below.first == "quartz", QuartzCheckoutLayout.isCourseWebsite(ancestor) else {
                continue
            }
            // below = ["quartz", "content", "source-ics3u", "s2", …]
            if below.count >= 4, below[1] == "content", below[2].lowercased().hasPrefix("source-"),
               let section = QuartzCheckoutLayout.sectionNumber(inName: below[3], prefix: "s"),
               section != QuartzCheckoutLayout.importableSection {
                return .aLaterSection(section: section)
            }
            if below.count >= 3, below[1] == "content", below[2].lowercased().hasPrefix("vault-") {
                var parts: [String] = []
                for part in below[2].split(separator: "-") {
                    parts.append(String(part))
                }
                if let last = parts.last,
                   let section = QuartzCheckoutLayout.sectionNumber(inName: last, prefix: "s"),
                   section != QuartzCheckoutLayout.importableSection {
                    return .aLaterSection(section: section)
                }
            }
            return .partOfAWebsite(checkoutName: ancestor.lastPathComponent)
        }
        return nil
    }

    // MARK: - Functions (one website folder's facts)

    /// Code, section and place of one candidate.
    static func facts(of candidate: Candidate) -> Facts {
        guard let websiteURL = candidate.websiteURL else {
            return Facts(
                rowName: candidate.rowName, websiteURL: nil, shortcutName: candidate.shortcutName,
                trouble: candidate.trouble, code: nil, section: nil, sectionFrom: nil,
                sectionTheNameSays: nil, coursePagesFolderName: nil, place: ""
            )
        }
        let folders: [String] = QuartzCheckoutLayout.coursePagesFolders(of: websiteURL)
        var code: String?
        var coursePages: String?
        if folders.count == 1 {
            coursePages = folders[0]
            code = String(folders[0].dropFirst("source-".count)).uppercased()
        }
        let told: (section: Int?, from: SectionFrom?, nameSays: Int?) =
            QuartzCheckoutLayout.section(of: websiteURL, coursePagesFolderName: coursePages)
        return Facts(
            rowName: candidate.rowName,
            websiteURL: websiteURL,
            shortcutName: candidate.shortcutName,
            trouble: candidate.trouble,
            code: code,
            section: told.section,
            sectionFrom: told.from,
            sectionTheNameSays: told.nameSays,
            coursePagesFolderName: coursePages,
            place: QuartzCheckoutLayout.place(of: websiteURL)
        )
    }

    /// Which section a website folder built: its front page's link TEXT,
    /// then its own name, then the only one there is.
    static func section(
        of websiteURL: URL,
        coursePagesFolderName: String?
    ) -> (section: Int?, from: SectionFrom?, nameSays: Int?) {
        let nameSays: Int? = QuartzCheckoutLayout.sectionNumber(inName: websiteURL.lastPathComponent, prefix: "s")
        guard let coursePagesFolderName else {
            return (section: nil, from: nil, nameSays: nameSays)
        }
        let content: URL = QuartzCheckoutLayout.contentURL(of: websiteURL)
        let sections: [Int] = QuartzCheckoutLayout.sectionNumbers(
            in: content.appendingPathComponent(coursePagesFolderName)
        )

        let frontPage: URL = content.appendingPathComponent("index.md")
        if OlderCourseLayout.kind(of: frontPage) == S_IFLNK,
           let text = try? FileManager.default.destinationOfSymbolicLink(atPath: frontPage.path) {
            var parts: [String] = []
            for part in text.split(separator: "/") where part != "." {
                parts.append(String(part))
            }
            if parts.count >= 3,
               parts[parts.count - 1] == "index.md",
               parts[parts.count - 3].lowercased() == coursePagesFolderName.lowercased(),
               let number = QuartzCheckoutLayout.sectionNumber(inName: parts[parts.count - 2], prefix: "s"),
               sections.contains(number) {
                return (section: number, from: .frontPage, nameSays: nameSays)
            }
        }
        if let nameSays, sections.contains(nameSays) {
            return (section: nameSays, from: .folderName, nameSays: nameSays)
        }
        if sections.count == 1 {
            return (section: sections[0], from: .onlyOne, nameSays: nameSays)
        }
        return (section: nil, from: nil, nameSays: nameSays)
    }

    /// The school year from the website folder's path: the first of it, its
    /// parent and its grandparent named exactly `YYYY-YY` (consecutive), or
    /// carrying `-YYYY-YY` the way #254's names do. Nil when none says.
    static func schoolYear(fromThePathOf websiteURL: URL) -> Int? {
        var folder: URL = websiteURL
        for _ in 0..<3 {
            let name: String = folder.lastPathComponent
            if let year = QuartzCheckoutLayout.yearNamedExactly(name) {
                return year
            }
            if let year = OlderCourseLayout.nameFacts(of: name).startingYear {
                return year
            }
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }

    /// `2024-25` → 2024; nil for anything else.
    static func yearNamedExactly(_ name: String) -> Int? {
        let characters: [Character] = Array(name)
        guard characters.count == 7, characters[4] == "-" else {
            return nil
        }
        for index in [0, 1, 2, 3, 5, 6] where !(characters[index].isASCII && characters[index].isNumber) {
            return nil
        }
        guard let first = Int(String(characters[0..<4])),
              let second = Int(String(characters[5..<7])),
              second == (first + 1) % 100 else {
            return nil
        }
        return first
    }

    /// A folder's path as a teacher reads it: `~/Documents/…` inside the
    /// home folder, the whole path otherwise.
    static func place(of url: URL) -> String {
        let path: String = url.standardizedFileURL.path
        let home: String = NSHomeDirectory()
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    // MARK: - Functions (class pages)

    /// The word class pages use, over the names of the pages directly in a
    /// class folder. Placeholders — `Thread 2, Day x`, a day that is a word
    /// rather than a number — are set aside, and so are the names the build
    /// never calls a class page. What is left must be at least one page,
    /// EVERY one `<word> <n>, Day <m>`, with one word (any case). Otherwise
    /// nil: a word that fits some pages and not others would make the build
    /// treat the rest as something else.
    static func unitWord(amongPageNames names: [String]) -> (word: String?, placeholders: Int) {
        var word: String?
        var placeholders: Int = 0
        var classPages: Int = 0
        for name in names {
            guard name.lowercased().hasSuffix(".md") else {
                continue
            }
            if QuartzCheckoutLayout.neverAClassPage.contains(name.lowercased()) {
                continue
            }
            let stem: String = String(name.dropLast(3))
            guard let parsed = QuartzCheckoutLayout.classPageParts(stem) else {
                return (word: nil, placeholders: placeholders)
            }
            if !parsed.dayIsANumber {
                placeholders += 1
                continue
            }
            if let already = word {
                if already.lowercased() != parsed.word.lowercased() {
                    return (word: nil, placeholders: placeholders)
                }
            } else {
                word = parsed.word
            }
            classPages += 1
        }
        if classPages == 0 {
            return (word: nil, placeholders: placeholders)
        }
        if let word, ClassPageTerm.problem(with: word) != nil {
            return (word: nil, placeholders: placeholders)
        }
        return (word: word, placeholders: placeholders)
    }

    /// `Thread 5, Day 4` → ("Thread", day is a number); `Thread 2, Day x` →
    /// ("Thread", day is a word); anything else → nil.
    static func classPageParts(_ stem: String) -> (word: String, dayIsANumber: Bool)? {
        let pattern: String = #"^\s*(\S+)\s+(\d+),\s*Day\s+([0-9]+|[A-Za-z]+)\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let whole: NSRange = NSRange(stem.startIndex..<stem.endIndex, in: stem)
        guard let match = expression.firstMatch(in: stem, options: [], range: whole),
              let wordRange = Range(match.range(at: 1), in: stem),
              let dayRange = Range(match.range(at: 3), in: stem) else {
            return nil
        }
        let day: String = String(stem[dayRange])
        var dayIsANumber: Bool = true
        for character in day where !(character.isASCII && character.isNumber) {
            dayIsANumber = false
        }
        return (word: String(stem[wordRange]), dayIsANumber: dayIsANumber)
    }

    // MARK: - Functions (the mapping)

    /// The whole mapping of one website folder's FIRST section into a
    /// modern course, as data. Read only from the folder pointed at: its own
    /// `source-<code>/shared` and `/s1`, by name.
    static func plan(facts: Facts, leavingBehind leftBehindNames: Set<String>) -> Plan {
        let websiteURL: URL = facts.websiteURL ?? URL(fileURLWithPath: "/nonexistent")
        let content: URL = QuartzCheckoutLayout.contentURL(of: websiteURL)
        let pagesName: String = facts.coursePagesFolderName ?? ""
        let pages: URL = content.appendingPathComponent(pagesName)
        let sectionName: String = QuartzCheckoutLayout.realSectionFolderName(
            QuartzCheckoutLayout.importableSection, in: pages
        ) ?? "s1"
        let sectionURL: URL = pages.appendingPathComponent(sectionName)
        let sharedURL: URL = pages.appendingPathComponent("shared")
        let code: String = facts.code ?? facts.rowName

        var placements: [ReferenceTreeCopier.Placement] = []
        var lost: [Lost] = []
        var leftBehind: [LeftBehindKind: Int] = [:]
        for kind in LeftBehindKind.allCases {
            leftBehind[kind] = 0
        }
        var unreadable: [String] = []
        var pageYears: [Int] = []

        // The section folder is made by the plan itself.
        placements.append(ReferenceTreeCopier.Placement(
            sourceRoot: sectionURL,
            item: ReferenceTreeCopier.Item(
                relativePath: [], isDirectory: true, byteCount: 0, mode: S_IFDIR | 0o755, modified: nil
            ),
            destination: Array(QuartzCheckoutLayout.sectionFolderName.utf8)
        ))

        // The section's own pages → section1/.
        var sectionTopNames: Set<[UInt8]> = []
        var sectionFolders: [String] = []
        var sectionFiles: [String] = []
        var hasFrontPage: Bool = false
        if OlderCourseLayout.kind(of: sectionURL) == S_IFDIR {
            let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
                courseAt: sectionURL, leavingBehind: leftBehindNames
            )
            for folder in survey.unreadableFolders {
                unreadable.append("\(pagesName)/\(sectionName)/\(folder)")
            }
            for item in survey.items {
                let parts: [[UInt8]] = OlderCourseLayout.components(of: item.relativePath)
                if parts.count == 1 {
                    sectionTopNames.insert(OlderCourseLayout.composed(parts[0]))
                }
                if item.isSymbolicLink {
                    lost.append(Lost(path: "\(pagesName)/\(sectionName)/\(item.text)", reason: .link))
                    continue
                }
                if parts.count == 1 {
                    if item.isDirectory {
                        sectionFolders.append(item.text)
                    } else if item.text == "index.md" {
                        hasFrontPage = true
                    } else {
                        sectionFiles.append(item.text)
                    }
                }
                placements.append(ReferenceTreeCopier.Placement(
                    sourceRoot: sectionURL,
                    item: item,
                    destination: Array((QuartzCheckoutLayout.sectionFolderName + "/").utf8) + item.relativePath
                ))
            }
        }
        if !hasFrontPage {
            lost.append(Lost(path: "\(pagesName)/\(sectionName)/index.md", reason: .noFrontPage))
        }

        // The shared pages → the course root, by name.
        var sharedTopNames: Set<[UInt8]> = []
        if OlderCourseLayout.kind(of: sharedURL) == S_IFDIR {
            let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
                courseAt: sharedURL, leavingBehind: leftBehindNames
            )
            for folder in survey.unreadableFolders {
                unreadable.append("\(pagesName)/shared/\(folder)")
            }
            for item in survey.items {
                let parts: [[UInt8]] = OlderCourseLayout.components(of: item.relativePath)
                let top: String = String(decoding: parts[0], as: UTF8.self)
                if QuartzCheckoutLayout.namesTheCourseUses.contains(top.lowercased()) {
                    if parts.count == 1 {
                        lost.append(Lost(path: "\(pagesName)/shared/\(item.text)", reason: .nameTheCourseUses))
                    }
                    continue
                }
                if sectionTopNames.contains(OlderCourseLayout.composed(parts[0])) {
                    if parts.count == 1 {
                        lost.append(Lost(path: "\(pagesName)/shared/\(item.text)", reason: .nameTheSectionUses))
                    }
                    continue
                }
                if parts.count == 1 {
                    sharedTopNames.insert(OlderCourseLayout.composed(parts[0]))
                }
                if item.isSymbolicLink {
                    lost.append(Lost(path: "\(pagesName)/shared/\(item.text)", reason: .link))
                    continue
                }
                placements.append(ReferenceTreeCopier.Placement(
                    sourceRoot: sharedURL, item: item, destination: item.relativePath
                ))
            }
        }

        // Everything else in the course pages folder: other sections, and
        // anything no link showed.
        var otherSectionNames: [String] = []
        for name in ReferenceTreeCopier.names(inFolderAt: pages) {
            let text: String = String(decoding: name, as: UTF8.self)
            if text == "shared" || text == sectionName || leftBehindNames.contains(text) {
                continue
            }
            let entryURL: URL = ReferenceTreeCopier.url(named: name, inFolderAt: pages)
            let count: Int = QuartzCheckoutLayout.entryCount(entryURL, leavingBehind: leftBehindNames)
            if QuartzCheckoutLayout.sectionNumber(inName: text, prefix: "s") != nil,
               OlderCourseLayout.kind(of: entryURL) == S_IFDIR {
                leftBehind[.anotherSectionsPages, default: 0] += count
                otherSectionNames.append(text)
            } else {
                leftBehind[.notOnTheWebsite, default: 0] += count
            }
        }

        // The top of `content/`: its settings folder, the links, the
        // editing folders, and anything else real.
        var editingFolderNames: [String] = []
        for name in ReferenceTreeCopier.names(inFolderAt: content) {
            let text: String = String(decoding: name, as: UTF8.self)
            if leftBehindNames.contains(text) {
                continue
            }
            let kind: mode_t? = OlderCourseLayout.kind(ofEntry: name, inFolderAt: content)
            let entryURL: URL = ReferenceTreeCopier.url(named: name, inFolderAt: content)
            if kind == S_IFLNK {
                if let reason = QuartzCheckoutLayout.problem(
                    withLinkNamed: text, at: entryURL, content: content, pagesName: pagesName,
                    sectionName: sectionName, sharedNames: sharedTopNames, sectionNames: sectionTopNames
                ) {
                    lost.append(Lost(path: text, reason: reason))
                } else {
                    leftBehind[.shortcutsReplaced, default: 0] += 1
                }
                continue
            }
            if text == pagesName {
                continue
            }
            if text.lowercased().hasPrefix("source-") {
                // Another course's pages — only possible when there are two,
                // which is a problem the row already carries.
                leftBehind[.notOnTheWebsite, default: 0] += QuartzCheckoutLayout.entryCount(
                    entryURL, leavingBehind: leftBehindNames
                )
                continue
            }
            if kind == S_IFDIR && text.lowercased().hasPrefix("vault-") {
                leftBehind[.editingFolders, default: 0] += QuartzCheckoutLayout.entryCount(
                    entryURL, leavingBehind: leftBehindNames
                )
                editingFolderNames.append(text)
                continue
            }
            if kind == S_IFDIR && text == ".obsidian" {
                placements.append(ReferenceTreeCopier.Placement(
                    sourceRoot: content,
                    item: ReferenceTreeCopier.Item(
                        relativePath: name, isDirectory: true, byteCount: 0, mode: S_IFDIR | 0o755, modified: nil
                    ),
                    destination: name
                ))
                let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
                    courseAt: entryURL, leavingBehind: leftBehindNames
                )
                for folder in survey.unreadableFolders {
                    unreadable.append(".obsidian/\(folder)")
                }
                for item in survey.items {
                    let parts: [[UInt8]] = OlderCourseLayout.components(of: item.relativePath)
                    let first: String = String(decoding: parts[0], as: UTF8.self)
                    if first == "plugins" || (parts.count == 1 && first == "community-plugins.json") {
                        if parts.count == 1 {
                            leftBehind[.addOns, default: 0] += 1
                        }
                        continue
                    }
                    if item.isSymbolicLink {
                        lost.append(Lost(path: ".obsidian/\(item.text)", reason: .link))
                        continue
                    }
                    placements.append(ReferenceTreeCopier.Placement(
                        sourceRoot: entryURL,
                        item: item,
                        destination: Array(".obsidian/".utf8) + item.relativePath
                    ))
                }
                continue
            }
            // Something real at the top of `content/` (0 measured): it was
            // built into the site, so it comes, as shared.
            if QuartzCheckoutLayout.namesTheCourseUses.contains(text.lowercased()) {
                lost.append(Lost(path: text, reason: .nameTheCourseUses))
                continue
            }
            let composedName: [UInt8] = OlderCourseLayout.composed(name)
            if sectionTopNames.contains(composedName) {
                lost.append(Lost(path: text, reason: .nameTheSectionUses))
                continue
            }
            if sharedTopNames.contains(composedName) {
                // The shared folder already brings one of that name.
                lost.append(Lost(path: text, reason: .nameTheSectionUses))
                continue
            }
            if kind == S_IFDIR {
                placements.append(ReferenceTreeCopier.Placement(
                    sourceRoot: content,
                    item: ReferenceTreeCopier.Item(
                        relativePath: name, isDirectory: true, byteCount: 0, mode: S_IFDIR | 0o755, modified: nil
                    ),
                    destination: name
                ))
                let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
                    courseAt: entryURL, leavingBehind: leftBehindNames
                )
                for folder in survey.unreadableFolders {
                    unreadable.append("\(text)/\(folder)")
                }
                for item in survey.items {
                    if item.isSymbolicLink {
                        lost.append(Lost(path: "\(text)/\(item.text)", reason: .link))
                        continue
                    }
                    placements.append(ReferenceTreeCopier.Placement(
                        sourceRoot: entryURL, item: item, destination: name + Array("/".utf8) + item.relativePath
                    ))
                }
            } else if kind == S_IFREG {
                var status: stat = stat()
                _ = lstat(entryURL.path, &status)
                placements.append(ReferenceTreeCopier.Placement(
                    sourceRoot: content,
                    item: ReferenceTreeCopier.Item(
                        relativePath: name, isDirectory: false, byteCount: Int64(status.st_size),
                        mode: status.st_mode,
                        modified: Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec))
                    ),
                    destination: name
                ))
            }
        }

        // The website's own program files: counted inside `quartz/` only,
        // never the folder above it; a skipped folder is one entry.
        var notLookedInside: [String] = []
        let program: URL = websiteURL.appendingPathComponent("quartz")
        for name in ReferenceTreeCopier.names(inFolderAt: program) {
            let text: String = String(decoding: name, as: UTF8.self)
            if text == "content" || text == ".DS_Store" {
                continue
            }
            if leftBehindNames.contains(text) {
                notLookedInside.append(text)
                leftBehind[.theBuildersOwnFiles, default: 0] += 1
                continue
            }
            leftBehind[.theBuildersOwnFiles, default: 0] += QuartzCheckoutLayout.entryCount(
                ReferenceTreeCopier.url(named: name, inFolderAt: program), leavingBehind: leftBehindNames
            )
        }

        // Counts, and the lists the settings carry.
        var fileCount: Int = 0
        var byteCount: Int64 = 0
        var pageCount: Int = 0
        var hasMedia: Bool = false
        var sharedFolders: [String] = []
        var sharedFiles: [String] = []
        var classFolderPages: [String] = []
        for placement in placements {
            let parts: [[UInt8]] = OlderCourseLayout.components(of: placement.destination)
            let top: String = String(decoding: parts[0], as: UTF8.self)
            if top.lowercased() == "media" {
                hasMedia = true
            }
            if !placement.item.isDirectory {
                fileCount += 1
                byteCount += placement.item.byteCount
                if top != ".obsidian" && placement.destinationText.lowercased().hasSuffix(".md") {
                    pageCount += 1
                    if let modified = placement.item.modified {
                        pageYears.append(SchoolYear.startingYear(on: CalendarDay.today(modified)))
                    }
                }
            }
            if parts.count == 1 && placement.item.isDirectory {
                if top.hasPrefix(".") || top.lowercased() == "media" || top == QuartzCheckoutLayout.sectionFolderName {
                    continue
                }
                sharedFolders.append(top)
            }
            if parts.count == 1 && !placement.item.isDirectory && !top.hasPrefix(".") {
                sharedFiles.append(top)
            }
            // The class pages: directly in the section's class folder.
            if parts.count == 3 && !placement.item.isDirectory && top == QuartzCheckoutLayout.sectionFolderName {
                let folder: String = String(decoding: parts[1], as: UTF8.self)
                if folder.lowercased().contains("class") {
                    classFolderPages.append(String(decoding: parts[2], as: UTF8.self))
                }
            }
        }
        sharedFolders.sort { first, second in
            return first.localizedStandardCompare(second) == .orderedAscending
        }
        sharedFiles.sort { first, second in
            return first.localizedStandardCompare(second) == .orderedAscending
        }
        sectionFolders.sort { first, second in
            return first.localizedStandardCompare(second) == .orderedAscending
        }
        sectionFiles.sort { first, second in
            return first.localizedStandardCompare(second) == .orderedAscending
        }
        editingFolderNames.sort()
        otherSectionNames.sort()
        lost.sort { first, second in
            return first.path.localizedStandardCompare(second.path) == .orderedAscending
        }
        let unit: (word: String?, placeholders: Int) = QuartzCheckoutLayout.unitWord(amongPageNames: classFolderPages)

        return Plan(
            placements: placements,
            lost: lost,
            leftBehind: leftBehind,
            editingFolderNames: editingFolderNames,
            otherSectionNames: otherSectionNames,
            notLookedInside: notLookedInside,
            createsEmptyMedia: !hasMedia,
            fileCount: fileCount,
            byteCount: byteCount,
            pageCount: pageCount,
            pageYears: pageYears,
            unreadableFolders: unreadable,
            courseCode: code,
            courseName: "\(code) S\(QuartzCheckoutLayout.importableSection)",
            sharedFolders: sharedFolders,
            sharedFiles: sharedFiles,
            perSectionFolders: sectionFolders,
            perSectionFiles: sectionFiles,
            unitWord: unit.word,
            placeholderPages: unit.placeholders
        )
    }

    /// Why a link at the top of `content/` is a LOSS, or nil when it showed
    /// exactly the page or folder of its own name in `shared/` or the
    /// section's folder — which then comes across by name. Its TEXT is read
    /// and worked out against `content/` as a path; it is never followed.
    static func problem(
        withLinkNamed name: String,
        at linkURL: URL,
        content: URL,
        pagesName: String,
        sectionName: String,
        sharedNames: Set<[UInt8]>,
        sectionNames: Set<[UInt8]>
    ) -> LostReason? {
        guard let text = try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path) else {
            return .linkShowedSomethingElse
        }
        var target: String = text
        if !text.hasPrefix("/") {
            target = content.path + "/" + text
        }
        let resolved: String = QuartzCheckoutLayout.composedText((target as NSString).standardizingPath)
        let pagesPath: String = QuartzCheckoutLayout.composedText(
            (content.appendingPathComponent(pagesName).path as NSString).standardizingPath
        )
        let composedName: String = QuartzCheckoutLayout.composedText(name)
        let composedBytes: [UInt8] = Array(composedName.utf8)
        if resolved == pagesPath + "/shared/" + composedName {
            return sharedNames.contains(composedBytes) ? nil : .linkNameWithNoPage
        }
        if resolved == pagesPath + "/" + QuartzCheckoutLayout.composedText(sectionName) + "/" + composedName {
            return sectionNames.contains(composedBytes) ? nil : .linkNameWithNoPage
        }
        return .linkShowedSomethingElse
    }

    /// The real `s<N>` folder's own spelling, or nil.
    static func realSectionFolderName(_ section: Int, in pagesURL: URL) -> String? {
        for name in ReferenceTreeCopier.names(inFolderAt: pagesURL) {
            let text: String = String(decoding: name, as: UTF8.self)
            if QuartzCheckoutLayout.sectionNumber(inName: text, prefix: "s") == section,
               OlderCourseLayout.kind(ofEntry: name, inFolderAt: pagesURL) == S_IFDIR {
                return text
            }
        }
        return nil
    }

    /// Files and links in a folder (walked, skip list applied), or 1 for a
    /// file or a link.
    static func entryCount(_ url: URL, leavingBehind leftBehindNames: Set<String>) -> Int {
        if OlderCourseLayout.kind(of: url) != S_IFDIR {
            return 1
        }
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(courseAt: url, leavingBehind: leftBehindNames)
        var count: Int = 0
        for item in survey.items where !item.isDirectory {
            count += 1
        }
        return count
    }

    /// Text composed (NFC), for comparing only.
    static func composedText(_ text: String) -> String {
        return text.precomposedStringWithCanonicalMapping
    }

    // MARK: - Functions (sentences)

    /// The sentence for a shortcut that cannot be read through.
    static func sentence(about trouble: ShortcutTrouble, shortcut: String, disk: String?) -> String {
        switch trouble {
        case .gone:
            return ReferenceImportWording.checkoutLayoutShortcutGone(shortcut: shortcut)
        case .couldNotBeOpened:
            return ReferenceImportWording.checkoutLayoutShortcutCouldNotBeOpened(shortcut: shortcut)
        case .diskNotConnected:
            return ReferenceImportWording.checkoutLayoutShortcutOnADiskNotConnected(
                shortcut: shortcut, disk: disk ?? ""
            )
        case .leadsToAFile:
            return ReferenceImportWording.checkoutLayoutShortcutToAFile(shortcut: shortcut)
        }
    }

    /// The line under a row saying where its pages are read from.
    static func whereFrom(_ facts: Facts) -> String? {
        guard facts.websiteURL != nil else {
            return nil
        }
        if let shortcut = facts.shortcutName {
            return ReferenceImportWording.checkoutLayoutReadThroughShortcut(shortcut: shortcut, place: facts.place)
        }
        return ReferenceImportWording.checkoutLayoutReadFrom(place: facts.place)
    }
}
