import Foundation

/// Russell's OLDER way of keeping a course (2023–24): one Obsidian folder per
/// class section — `ICS3U-S1-2023-24` — holding its `Thread N` folders of
/// class pages, with the shared folders and pages (Tasks, Concepts, Media…)
/// reached through LINKS into a sibling folder named `… Shared`.
///
/// This file READS that shape and says how it becomes one single-section
/// reference course. It never writes: the copying is `ReferenceTreeCopier`,
/// the making-into-a-reference-course is `ReferenceCopier`, and the whole act
/// is `ReferenceImporter`. Issue #254; the reasoning, the measurements and
/// what was rejected are in `documentation/09-mac-app.md` → "The older
/// layout: a folder per class", and the rule itself is data in
/// `contracts/shared-rules.json` → `referenceCourses.importing.olderLayout`.
///
/// Three rules this file exists to keep:
///
/// 1. **Nothing is ever FOLLOWED.** Every entry is asked about with `lstat`.
///    Measured on the real folders: all 18 of ICS3U's links point at a folder
///    that no longer exists, while the right content sits beside them under
///    another name — so the shared folder is found by its NAME (Russell's
///    decision 2), and a link is only ever a name.
/// 2. **No link reaches a reference course.** A link inside one is a door out
///    of it that the lock cannot lock, the census does not count, and the
///    preview cannot follow out of the working folder. Every link is left out
///    here and the copier refuses one as well.
/// 3. **Obsidian add-ons do not come across.** Every one of the real class
///    folders carries a publishing add-on whose settings hold a live
///    credential; a reference course is never published, and a copy of that
///    add-on would be a way to publish it that none of Plantoir's refusals
///    can see.
nonisolated enum OlderCourseLayout {

    // MARK: - Types

    /// What a folder's NAME says: `ICS3U-S1-2023-24`.
    struct NameFacts: Sendable, Equatable {

        // MARK: - Stored properties

        /// The leading Ontario-shaped code, upper-cased, or nil.
        let code: String?

        /// The school year the name spells (`2023-24` gives 2023), or nil
        /// when there is none or its two halves do not follow each other.
        let startingYear: Int?

        /// The section number the name spells (`-S2-`), or nil.
        let section: Int?

        /// True when the name is exactly `CODE-YYYY-YY` or `CODE-Sn-YYYY-YY` —
        /// a class folder named the way Russell named his classes. Only these
        /// are ticked when a whole folder of them is chosen; one named any
        /// other way (`ICD2O-Exemplars`) is offered, unticked.
        let looksLikeAClass: Bool
    }

    /// How the shared folder came to be the one used.
    enum HowFound: String, Sendable, Equatable {
        /// The class holds no links, so there is nothing to find (ICS4U
        /// 2023–24 is one self-contained folder).
        case notNeeded
        /// A folder beside it whose name ends in "Shared" and starts with the
        /// class's code.
        case byItsName
        /// The teacher chose it.
        case chosen
        /// Nothing was found and nothing was chosen.
        case none
    }

    /// What was found of the shared content, for the sheet and the trail.
    enum State: String, Sendable, Equatable {
        case notNeeded
        case found
        case partlyFound
        case notFound
    }

    /// The shared content a class needs, as found.
    struct SharedContent: Sendable, Equatable {

        // MARK: - Stored properties

        let howFound: HowFound

        /// The folder it comes from, or nil.
        let folderURL: URL?

        /// The names the class's links carried that the folder really holds,
        /// as that folder's own BYTES.
        let foundNames: [[UInt8]]

        /// The names the class's links carried that are not there, as text,
        /// in a stable order. These are what will be missing.
        let missingNames: [String]

        /// How many links the class held.
        let linkCount: Int

        // MARK: - Computed properties

        var state: State {
            if linkCount == 0 {
                return .notNeeded
            }
            if foundNames.isEmpty {
                return .notFound
            }
            if missingNames.isEmpty {
                return .found
            }
            return .partlyFound
        }

        /// The folder's own name, for a sentence.
        var folderName: String? {
            return folderURL?.lastPathComponent
        }
    }

    /// What one class folder is, as the sheet carries it.
    struct Facts: Sendable, Equatable {

        // MARK: - Stored properties

        let classFolderName: String
        let names: NameFacts
        let shared: SharedContent

        /// Said beside the row when the teacher chose a shared folder whose
        /// name carries a DIFFERENT course code. A warning, never a refusal:
        /// Russell kept things where he kept them.
        let chosenWarning: String?
    }

    /// Why something in the class or shared folder does not come across.
    enum LeftOutReason: String, Sendable, Equatable {
        /// A symbolic link, anywhere. Never followed, never copied.
        case link
        /// `.obsidian/plugins`, `community-plugins.json` and `publish.json`
        /// — `ObsidianAddOns`, the same three every route leaves (#255).
        case addOns
        /// A root `index.md` beside a `Home.md`: the front page is `Home.md`.
        case secondFrontPage
        /// A top-level entry named `section1` or `course_config.json`, which
        /// the new course already uses for itself.
        case nameTheCourseUses
    }

    /// One thing left out, by where it was.
    struct LeftOut: Sendable, Equatable {

        // MARK: - Stored properties

        /// Its path inside the folder it was in, as text.
        let path: String

        /// True when it was in the shared folder rather than the class's own.
        let inTheSharedFolder: Bool

        let reason: LeftOutReason
    }

    /// The whole mapping of one class folder into a modern course, as data.
    struct Plan: Sendable {

        // MARK: - Stored properties

        let placements: [ReferenceTreeCopier.Placement]
        let leftOut: [LeftOut]
        let shared: SharedContent

        /// True when nothing supplies `Media`, so an empty one is made.
        let createsEmptyMedia: Bool

        let fileCount: Int
        let byteCount: Int64
        let pageCount: Int

        /// The school year each of the CLASS's own pages was last changed in.
        let pageYears: [Int]

        /// Folders the disk would not hand over. Any at all refuses the course.
        let unreadableFolders: [String]

        let courseCode: String
        let courseName: String
        let sharedFolders: [String]
        let sharedFiles: [String]
        let perSectionFolders: [String]
        let perSectionFiles: [String]

        // MARK: - Computed properties

        /// The class's own top-level links that the shared folder's real
        /// entries took the place of. These are not a loss: what they showed
        /// came across under the same name.
        var linksReplaced: Int {
            return shared.foundNames.count
        }

        /// Everything left out that is a LOSS, by path, and named wherever it
        /// is reported — the summary and the trail (#254 fixes, item 1).
        ///
        /// Not in it: the add-ons (said once, for every older class, by
        /// `wording.olderLayoutAddOnsAreLeftBehind`), and a class's top-level
        /// links, each of which is either replaced by the shared folder's
        /// real entry or already counted in `shared.missingNames`. In it: a
        /// link anywhere BELOW the top of the class folder, any link inside
        /// the shared folder's entries, and anything left out because the
        /// course uses its name. The first shape of this counted a picture
        /// dropped from `Thread 1/` together with the links that were
        /// replaced, and called the import complete.
        var leftOutAndLost: [String] {
            var paths: [String] = []
            for entry in leftOut {
                if entry.reason == .addOns {
                    continue
                }
                let isATopLevelClassLink: Bool = entry.reason == .link
                    && !entry.inTheSharedFolder
                    && !entry.path.contains("/")
                if isATopLevelClassLink {
                    continue
                }
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
            return [
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
                // Off: the old class pages are called `Day N`, not
                // `Unit N, Day M`, so no folder is a class folder and a map
                // would count nothing and look finished.
                //
                // A plain `false`, the shape the wizard writes and the one
                // every reader takes as off: `resolve_include_curriculum_
                // coverage`, `CourseConfiguration.includesCurriculumCoverage`
                // and `setup_course.py`'s `bool(...)`. A per-section map was
                // measured to read as ON in the last two.
                "include_curriculum_coverage": false,
                // Off: every import becomes `section1`, so an "S1" in the
                // title would be wrong for the S2 it was.
                "show_section_marker": ["sections": ["section1": false]],
            ]
        }
    }

    /// What a chosen folder turned out to be.
    enum Recognised: Equatable {
        case classFolder(URL)
        case folderOfClasses(URL, classFolders: [URL])
        case theSharedFolder
        /// A folder whose children are COURSE folders each holding a
        /// `Class Website` of classes — the school year's folder. Refused
        /// with a sentence that says where to go instead.
        case aFolderOfCourses
        case nothing
    }

    // MARK: - Stored properties

    /// Where every import puts the class's own pages.
    static let sectionFolderName: String = "section1"

    /// The course's front page, where the build looks for it.
    static let frontPageDestination: String = "section1/index.md"

    /// The old front page.
    static let oldFrontPageName: String = "Home.md"

    /// The one page that belongs to the section rather than the course.
    static let perSectionPageName: String = "All Prior Classes.md"

    /// The folder a teacher usually keeps the classes in.
    static let folderOfClassesName: String = "Class Website"

    // MARK: - Functions (names)

    /// What a folder's name says. Pure; the contract's `codeAndYear` cases.
    static func nameFacts(of folderName: String) -> NameFacts {
        let characters: [Character] = Array(folderName)
        var code: String?
        if characters.count >= 5,
           OlderCourseLayout.isASCIILetter(characters[0]),
           OlderCourseLayout.isASCIILetter(characters[1]),
           OlderCourseLayout.isASCIILetter(characters[2]),
           OlderCourseLayout.isASCIIDigit(characters[3]),
           OlderCourseLayout.isASCIILetter(characters[4]) || OlderCourseLayout.isASCIIDigit(characters[4]) {
            let followedByMore: Bool = characters.count > 5
                && (OlderCourseLayout.isASCIILetter(characters[5]) || OlderCourseLayout.isASCIIDigit(characters[5]))
            if !followedByMore {
                code = String(characters[0..<5]).uppercased()
            }
        }

        // The year: `-YYYY-YY` where YY is the year after YYYY.
        var startingYear: Int?
        var index: Int = 0
        while index + 8 <= characters.count {
            let window: [Character] = Array(characters[index..<(index + 8)])
            let shapeFits: Bool = window[0] == "-"
                && OlderCourseLayout.allDigits(Array(window[1..<5]))
                && window[5] == "-"
                && OlderCourseLayout.allDigits(Array(window[6..<8]))
            let endsThere: Bool = index + 8 == characters.count
                || !OlderCourseLayout.isASCIIDigit(characters[index + 8])
            if shapeFits && endsThere {
                let first: Int = Int(String(window[1..<5])) ?? 0
                let second: Int = Int(String(window[6..<8])) ?? -1
                if second == (first + 1) % 100 {
                    startingYear = first
                }
                break
            }
            index += 1
        }

        // The section: `-S<digits>` followed by `-` or the end.
        var section: Int?
        index = 0
        while index + 2 < characters.count {
            if characters[index] == "-",
               characters[index + 1] == "S" || characters[index + 1] == "s",
               OlderCourseLayout.isASCIIDigit(characters[index + 2]) {
                var digits: String = ""
                var cursor: Int = index + 2
                while cursor < characters.count, OlderCourseLayout.isASCIIDigit(characters[cursor]) {
                    digits.append(characters[cursor])
                    cursor += 1
                }
                if cursor == characters.count || characters[cursor] == "-" {
                    section = Int(digits)
                    break
                }
            }
            index += 1
        }

        var looksLikeAClass: Bool = false
        if let code, let startingYear {
            let yearPart: String = "\(startingYear)-" + OlderCourseLayout.twoDigits((startingYear + 1) % 100)
            var expected: String = "\(code)-\(yearPart)"
            if let section {
                expected = "\(code)-S\(section)-\(yearPart)"
            }
            looksLikeAClass = folderName.uppercased() == expected.uppercased()
        }

        return NameFacts(
            code: code, startingYear: startingYear, section: section, looksLikeAClass: looksLikeAClass
        )
    }

    /// `Thread 1`, `thread 12` — one space, digits after it, nothing else.
    static func isThreadFolderName(_ name: String) -> Bool {
        let lowered: String = name.lowercased()
        guard lowered.hasPrefix("thread ") else {
            return false
        }
        let number: String = String(lowered.dropFirst("thread ".count))
        if number.isEmpty {
            return false
        }
        return OlderCourseLayout.allDigits(Array(number))
    }

    /// A name that ends in " Shared", in any case.
    static func isSharedFolderName(_ name: String) -> Bool {
        return name.lowercased().hasSuffix(" shared")
    }

    // MARK: - Functions (recognition)

    /// An older class folder: a real folder, not named "… Shared", holding no
    /// `course_config.json`, with a real `.obsidian` folder AND at least one
    /// `Thread N` folder that has a page directly inside it.
    ///
    /// Both conditions, because each alone admits a real folder that is not
    /// a class: the course folder above (`ICS3U/`) has `Thread N` folders of
    /// planning — subfolders, 0 pages directly inside — and no `.obsidian`;
    /// `ICD2O-LCS-LDPS-Collaboration` has `.obsidian` and no `Thread N`.
    static func isOlderClassFolder(_ folderURL: URL) -> Bool {
        guard OlderCourseLayout.kind(of: folderURL) == S_IFDIR else {
            return false
        }
        if OlderCourseLayout.isSharedFolderName(folderURL.lastPathComponent) {
            return false
        }
        if OlderCourseLayout.kind(of: folderURL.appendingPathComponent(ReferenceImportSource.configFileName)) != nil {
            return false
        }
        if OlderCourseLayout.kind(of: folderURL.appendingPathComponent(".obsidian")) != S_IFDIR {
            return false
        }
        for name in ReferenceTreeCopier.names(inFolderAt: folderURL) {
            let text: String = String(decoding: name, as: UTF8.self)
            guard OlderCourseLayout.isThreadFolderName(text) else {
                continue
            }
            let threadURL: URL = ReferenceTreeCopier.url(named: name, inFolderAt: folderURL)
            guard OlderCourseLayout.kind(ofEntry: name, inFolderAt: folderURL) == S_IFDIR else {
                continue
            }
            for page in ReferenceTreeCopier.names(inFolderAt: threadURL) {
                let pageText: String = String(decoding: page, as: UTF8.self)
                if pageText.lowercased().hasSuffix(".md"),
                   OlderCourseLayout.kind(ofEntry: page, inFolderAt: threadURL) == S_IFREG {
                    return true
                }
            }
        }
        return false
    }

    /// What a chosen folder is: one class, a folder of classes (`Class
    /// Website`, or the course folder holding one by that exact name), the
    /// shared folder itself, or none of these.
    static func recognise(_ chosenURL: URL) -> Recognised {
        if OlderCourseLayout.isOlderClassFolder(chosenURL) {
            return .classFolder(chosenURL)
        }

        let classesInside: [URL] = OlderCourseLayout.classFolders(in: chosenURL)
        if !classesInside.isEmpty {
            return .folderOfClasses(chosenURL, classFolders: classesInside)
        }

        let named: URL = chosenURL.appendingPathComponent(OlderCourseLayout.folderOfClassesName)
        if OlderCourseLayout.kind(of: named) == S_IFDIR {
            let classesThere: [URL] = OlderCourseLayout.classFolders(in: named)
            if !classesThere.isEmpty {
                return .folderOfClasses(named, classFolders: classesThere)
            }
        }

        // One level further up: the school year's folder, whose children are
        // course folders each holding a `Class Website` of classes. Not
        // accepted — which course is meant is the teacher's to say — but
        // refused with a sentence that points one level down rather than
        // `noCoursesThere`, whose advice would point back at this folder.
        for name in ReferenceTreeCopier.names(inFolderAt: chosenURL) {
            guard OlderCourseLayout.kind(ofEntry: name, inFolderAt: chosenURL) == S_IFDIR else {
                continue
            }
            let courseURL: URL = ReferenceTreeCopier.url(named: name, inFolderAt: chosenURL)
            let website: URL = courseURL.appendingPathComponent(OlderCourseLayout.folderOfClassesName)
            if OlderCourseLayout.kind(of: website) == S_IFDIR,
               !OlderCourseLayout.classFolders(in: website).isEmpty {
                return .aFolderOfCourses
            }
        }

        // The shared folder is recognised only BESIDE classes, so the
        // sentence that says so is true. A folder anywhere else that happens
        // to end in "Shared" is simply not a course.
        if OlderCourseLayout.isSharedFolderName(chosenURL.lastPathComponent),
           OlderCourseLayout.kind(of: chosenURL) == S_IFDIR,
           !OlderCourseLayout.classFolders(in: chosenURL.deletingLastPathComponent()).isEmpty {
            return .theSharedFolder
        }
        return .nothing
    }

    /// The class folders directly inside a folder, in the order a teacher
    /// reads them. A child that is a link is never one.
    static func classFolders(in folderURL: URL) -> [URL] {
        var found: [URL] = []
        for name in ReferenceTreeCopier.names(inFolderAt: folderURL) {
            guard OlderCourseLayout.kind(ofEntry: name, inFolderAt: folderURL) == S_IFDIR else {
                continue
            }
            let childURL: URL = ReferenceTreeCopier.url(named: name, inFolderAt: folderURL)
            if OlderCourseLayout.isOlderClassFolder(childURL) {
                found.append(childURL)
            }
        }
        found.sort { first, second in
            return first.lastPathComponent.localizedStandardCompare(second.lastPathComponent) == .orderedAscending
        }
        return found
    }

    // MARK: - Functions (the shared folder)

    /// The names of the LINKS at the top of a class folder, as bytes. These
    /// are the manifest of what the class showed from the shared folder.
    static func linkNames(inClassFolder classFolderURL: URL) -> [[UInt8]] {
        var links: [[UInt8]] = []
        for name in ReferenceTreeCopier.names(inFolderAt: classFolderURL) {
            if OlderCourseLayout.kind(ofEntry: name, inFolderAt: classFolderURL) == S_IFLNK {
                links.append(name)
            }
        }
        return links
    }

    /// The shared folder beside a class, found by its NAME: a real folder
    /// (never a link) whose name ends in "Shared" and begins with the class's
    /// code and a dash. One candidate is it. Several: the one whose year is
    /// the class's, and otherwise none — never a guess between two.
    static func sharedFolder(besideClassFolder classFolderURL: URL) -> URL? {
        let names: NameFacts = OlderCourseLayout.nameFacts(of: classFolderURL.lastPathComponent)
        guard let code = names.code else {
            return nil
        }
        let parentURL: URL = classFolderURL.deletingLastPathComponent()
        var candidates: [URL] = []
        for name in ReferenceTreeCopier.names(inFolderAt: parentURL) {
            let text: String = String(decoding: name, as: UTF8.self)
            guard OlderCourseLayout.isSharedFolderName(text),
                  text.uppercased().hasPrefix(code + "-"),
                  OlderCourseLayout.kind(ofEntry: name, inFolderAt: parentURL) == S_IFDIR else {
                continue
            }
            candidates.append(ReferenceTreeCopier.url(named: name, inFolderAt: parentURL))
        }
        if candidates.count == 1 {
            return candidates[0]
        }
        guard let year = names.startingYear else {
            return nil
        }
        for candidate in candidates {
            if OlderCourseLayout.nameFacts(of: candidate.lastPathComponent).startingYear == year {
                return candidate
            }
        }
        return nil
    }

    /// What a folder holds of the names a class's links carried.
    ///
    /// A name is FOUND when the folder holds a real entry — never a link — of
    /// that name. Compared as composed bytes: the file system may store a
    /// name either way, and the grapheme `String ==` is not the comparison to
    /// trust with names (it is what hid a whole class of fault in #206).
    static func sharedContent(
        linkNames: [[UInt8]],
        in folderURL: URL?,
        howFound: HowFound
    ) -> SharedContent {
        if linkNames.isEmpty {
            return SharedContent(
                howFound: .notNeeded, folderURL: nil, foundNames: [], missingNames: [], linkCount: 0
            )
        }

        var realEntries: [[UInt8]: [UInt8]] = [:]
        if let folderURL {
            for name in ReferenceTreeCopier.names(inFolderAt: folderURL) {
                let kind: mode_t? = OlderCourseLayout.kind(ofEntry: name, inFolderAt: folderURL)
                if kind == S_IFDIR || kind == S_IFREG {
                    realEntries[OlderCourseLayout.composed(name)] = name
                }
            }
        }

        var found: [[UInt8]] = []
        var missing: [String] = []
        for link in linkNames {
            let text: String = String(decoding: link, as: UTF8.self)
            if text == ".obsidian" {
                continue
            }
            if let real = realEntries[OlderCourseLayout.composed(link)] {
                found.append(real)
            } else {
                missing.append(text)
            }
        }
        missing.sort { first, second in
            return first.localizedStandardCompare(second) == .orderedAscending
        }

        var how: HowFound = howFound
        if found.isEmpty && howFound == .byItsName {
            how = .none
        }
        return SharedContent(
            howFound: how,
            folderURL: found.isEmpty ? nil : folderURL,
            foundNames: found,
            missingNames: missing,
            linkCount: linkNames.count
        )
    }

    // MARK: - Functions (the mapping)

    /// The whole §2 mapping for one class folder, as data. Walks the class
    /// folder once and the shared folder once, from its ROOT — a per-entry
    /// walk reads a FILE entry as an unreadable folder (measured: 0 items,
    /// listed unreadable), and eight of ICS3U's shared entries are pages.
    static func plan(
        classFolderURL: URL,
        sharedFolderURL: URL?,
        howFound: HowFound,
        leavingBehind leftBehindNames: Set<String>
    ) -> Plan {
        let classFolderName: String = classFolderURL.lastPathComponent
        let names: NameFacts = OlderCourseLayout.nameFacts(of: classFolderName)
        let links: [[UInt8]] = OlderCourseLayout.linkNames(inClassFolder: classFolderURL)
        let shared: SharedContent = OlderCourseLayout.sharedContent(
            linkNames: links, in: sharedFolderURL, howFound: howFound
        )

        var placements: [ReferenceTreeCopier.Placement] = []
        var leftOut: [LeftOut] = []
        var unreadable: [String] = []
        var pageYears: [Int] = []

        // The section folder is made by the plan itself: nothing in the class
        // folder is called that, so no walk would list it.
        placements.append(ReferenceTreeCopier.Placement(
            sourceRoot: classFolderURL,
            item: ReferenceTreeCopier.Item(
                relativePath: [], isDirectory: true, byteCount: 0, mode: S_IFDIR | 0o755, modified: nil
            ),
            destination: Array(OlderCourseLayout.sectionFolderName.utf8)
        ))

        // The add-ons are SKIPPED by the walk rather than filtered after it
        // (#255): an unreadable folder inside an add-on used to land in
        // `unreadable` and refuse the whole class, for something that was
        // never going to be copied. The same three entries every route
        // leaves behind — `ObsidianAddOns`.
        let classSurvey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
            courseAt: classFolderURL,
            leavingBehind: leftBehindNames,
            leavingBehindPaths: ObsidianAddOns.leftBehindFromTheCourse
        )
        for folder in classSurvey.unreadableFolders {
            unreadable.append(folder)
        }
        // Links and all: everything under `.obsidian/plugins/` is left
        // behind by design, so a link in there is not a LOSS to be reported
        // (#254 fix review, nit 3) — and now it is not even seen.
        for path in classSurvey.pathsLeftBehind {
            leftOut.append(LeftOut(path: path, inTheSharedFolder: false, reason: .addOns))
        }

        // Which top-level entries are real, and which are Thread folders.
        var threadFolders: [String] = []
        var hasOldFrontPage: Bool = false
        for item in classSurvey.items where OlderCourseLayout.components(of: item.relativePath).count == 1 {
            if item.isSymbolicLink {
                continue
            }
            if item.isDirectory && OlderCourseLayout.isThreadFolderName(item.text) {
                threadFolders.append(item.text)
            }
            if !item.isDirectory && item.text == OlderCourseLayout.oldFrontPageName {
                hasOldFrontPage = true
            }
        }

        let reservedNames: Set<String> = [
            OlderCourseLayout.sectionFolderName, ReferenceImportSource.configFileName,
        ]

        for item in classSurvey.items {
            let parts: [[UInt8]] = OlderCourseLayout.components(of: item.relativePath)
            let first: String = String(decoding: parts[0], as: UTF8.self)

            if item.isSymbolicLink {
                leftOut.append(LeftOut(path: item.text, inTheSharedFolder: false, reason: .link))
                continue
            }

            var destination: [UInt8] = item.relativePath
            if threadFolders.contains(first) {
                destination = Array((OlderCourseLayout.sectionFolderName + "/").utf8) + item.relativePath
            } else if parts.count == 1 && !item.isDirectory && first == OlderCourseLayout.oldFrontPageName {
                destination = Array(OlderCourseLayout.frontPageDestination.utf8)
            } else if parts.count == 1 && !item.isDirectory && first == "index.md" {
                if hasOldFrontPage {
                    leftOut.append(LeftOut(path: item.text, inTheSharedFolder: false, reason: .secondFrontPage))
                    continue
                }
                destination = Array(OlderCourseLayout.frontPageDestination.utf8)
            } else if parts.count == 1 && !item.isDirectory && first == OlderCourseLayout.perSectionPageName {
                destination = Array(
                    (OlderCourseLayout.sectionFolderName + "/" + OlderCourseLayout.perSectionPageName).utf8
                )
            } else if reservedNames.contains(first.lowercased()) {
                if parts.count == 1 {
                    leftOut.append(LeftOut(path: item.text, inTheSharedFolder: false, reason: .nameTheCourseUses))
                }
                continue
            }

            placements.append(ReferenceTreeCopier.Placement(
                sourceRoot: classFolderURL, item: item, destination: destination
            ))

            if !item.isDirectory && first != ".obsidian" && item.text.lowercased().hasSuffix(".md"),
               let modified = item.modified {
                pageYears.append(SchoolYear.startingYear(on: CalendarDay.today(modified)))
            }
        }

        // The shared folder: ONLY what the class's links named, walked once
        // from its root.
        if let sharedURL = shared.folderURL {
            var wanted: Set<[UInt8]> = []
            for name in shared.foundNames {
                wanted.insert(OlderCourseLayout.composed(name))
            }
            // The shared folder's own `.obsidian` comes only if a class link
            // named it — and then without its add-ons, like every route's.
            let sharedSurvey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
                courseAt: sharedURL,
                leavingBehind: leftBehindNames,
                leavingBehindPaths: ObsidianAddOns.leftBehindFromTheCourse
            )
            for path in sharedSurvey.pathsLeftBehind {
                let top: [UInt8] = OlderCourseLayout.components(of: Array(path.utf8))[0]
                if wanted.contains(OlderCourseLayout.composed(top)) {
                    leftOut.append(LeftOut(path: path, inTheSharedFolder: true, reason: .addOns))
                }
            }
            for item in sharedSurvey.items {
                let parts: [[UInt8]] = OlderCourseLayout.components(of: item.relativePath)
                guard wanted.contains(OlderCourseLayout.composed(parts[0])) else {
                    continue
                }
                // The same names the class folder may not use, for the same
                // reason: `section1` and `course_config.json` are the course's
                // own, and a root `index.md` would fight the front page.
                let top: String = String(decoding: parts[0], as: UTF8.self).lowercased()
                if reservedNames.contains(top) || top == "index.md" {
                    if parts.count == 1 {
                        leftOut.append(LeftOut(path: item.text, inTheSharedFolder: true, reason: .nameTheCourseUses))
                    }
                    continue
                }
                if item.isSymbolicLink {
                    leftOut.append(LeftOut(path: item.text, inTheSharedFolder: true, reason: .link))
                    continue
                }
                placements.append(ReferenceTreeCopier.Placement(
                    sourceRoot: sharedURL, item: item, destination: item.relativePath
                ))
            }
            // Only an unreadable folder the class actually NEEDS stops it.
            for folder in sharedSurvey.unreadableFolders {
                let top: String = String(folder.split(separator: "/").first ?? Substring(folder))
                if wanted.contains(OlderCourseLayout.composed(Array(top.utf8))) {
                    unreadable.append("\(sharedURL.lastPathComponent)/\(folder)")
                }
            }
        }

        // Counts, and the lists the settings carry.
        var fileCount: Int = 0
        var byteCount: Int64 = 0
        var pageCount: Int = 0
        var hasMedia: Bool = false
        var sharedFolders: [String] = []
        var sharedFiles: [String] = []
        var perSectionFiles: [String] = []
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
                }
            }
            if parts.count == 1 && placement.item.isDirectory {
                if top.hasPrefix(".") || top.lowercased() == "media" || top == OlderCourseLayout.sectionFolderName {
                    continue
                }
                sharedFolders.append(top)
            }
            if parts.count == 1 && !placement.item.isDirectory && top.lowercased().hasSuffix(".md") {
                sharedFiles.append(top)
            }
            if placement.destinationText == OlderCourseLayout.sectionFolderName + "/" + OlderCourseLayout.perSectionPageName {
                perSectionFiles.append(OlderCourseLayout.perSectionPageName)
            }
        }
        sharedFolders.sort { first, second in
            return first.localizedStandardCompare(second) == .orderedAscending
        }
        sharedFiles.sort { first, second in
            return first.localizedStandardCompare(second) == .orderedAscending
        }
        threadFolders.sort { first, second in
            return first.localizedStandardCompare(second) == .orderedAscending
        }

        return Plan(
            placements: placements,
            leftOut: leftOut,
            shared: shared,
            createsEmptyMedia: !hasMedia,
            fileCount: fileCount,
            byteCount: byteCount,
            pageCount: pageCount,
            pageYears: pageYears,
            unreadableFolders: unreadable,
            courseCode: names.code ?? classFolderName,
            courseName: classFolderName,
            sharedFolders: sharedFolders,
            sharedFiles: sharedFiles,
            perSectionFolders: threadFolders,
            perSectionFiles: perSectionFiles
        )
    }

    /// Why a folder the teacher CHOSE as the shared folder cannot be it, or
    /// nil when it can.
    ///
    /// Refused when it is itself a class (measured: ICS4U 2023–24 holds 14 of
    /// ICS3U S1's 18 link names, so "holds at least one name" alone would
    /// take it and bring another course's pages), and when it holds none of
    /// the names. A different course code is a WARNING (`codeWarning`), not
    /// a refusal.
    static func refusal(ofChosenSharedFolder folderURL: URL, forClassFolder classFolderURL: URL) -> String? {
        let folderName: String = folderURL.lastPathComponent
        if OlderCourseLayout.kind(of: folderURL) != S_IFDIR {
            return ReferenceImportWording.olderLayoutChosenFolderHasNone(folder: folderName)
        }
        if OlderCourseLayout.isOlderClassFolder(folderURL) {
            return ReferenceImportWording.olderLayoutChosenFolderIsAClass(folder: folderName)
        }
        let content: SharedContent = OlderCourseLayout.sharedContent(
            linkNames: OlderCourseLayout.linkNames(inClassFolder: classFolderURL),
            in: folderURL,
            howFound: .chosen
        )
        if content.foundNames.isEmpty {
            return ReferenceImportWording.olderLayoutChosenFolderHasNone(folder: folderName)
        }
        return nil
    }

    /// The warning for a chosen shared folder whose name carries another
    /// course's code, or nil.
    static func codeWarning(forChosenSharedFolder folderURL: URL, classCode: String) -> String? {
        guard let chosenCode = OlderCourseLayout.nameFacts(of: folderURL.lastPathComponent).code else {
            return nil
        }
        if chosenCode == classCode.uppercased() {
            return nil
        }
        return ReferenceImportWording.olderLayoutChosenFolderIsForAnotherCourse(
            folder: folderURL.lastPathComponent, code: chosenCode, course: classCode
        )
    }

    /// The sentence under a row about its shared content, or nil when there
    /// is nothing to say (a class with no links needed nothing).
    static func sentence(about shared: SharedContent) -> String? {
        switch shared.state {
        case .notNeeded:
            return nil
        case .found:
            return ReferenceImportWording.olderLayoutSharedFound(folder: shared.folderName ?? "")
        case .partlyFound:
            return ReferenceImportWording.olderLayoutSharedPartlyFound(
                folder: shared.folderName ?? "", missing: shared.missingNames
            )
        case .notFound:
            return ReferenceImportWording.olderLayoutSharedNotFound(count: shared.linkCount)
        }
    }

    // MARK: - Private helpers

    /// The kind of thing at a path — `S_IFDIR`, `S_IFREG`, `S_IFLNK` — asked
    /// WITHOUT following a link, or nil when nothing is there.
    static func kind(of url: URL) -> mode_t? {
        var status: stat = stat()
        if lstat(url.path, &status) != 0 {
            return nil
        }
        return status.st_mode & S_IFMT
    }

    /// The same, for an entry named by its bytes.
    static func kind(ofEntry name: [UInt8], inFolderAt folderURL: URL) -> mode_t? {
        let path: [CChar] = ReferenceTreeCopier.path(ReferenceTreeCopier.pathBytes(of: folderURL), name)
        var status: stat = stat()
        let result: Int32 = path.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                return -1
            }
            return lstat(base, &status)
        }
        if result != 0 {
            return nil
        }
        return status.st_mode & S_IFMT
    }

    /// A path's parts, split on `/`, as bytes.
    static func components(of path: [UInt8]) -> [[UInt8]] {
        var parts: [[UInt8]] = []
        var current: [UInt8] = []
        for byte in path {
            if byte == 47 {
                parts.append(current)
                current = []
            } else {
                current.append(byte)
            }
        }
        parts.append(current)
        return parts
    }

    /// A name composed (NFC), as bytes — for COMPARING only, never writing.
    static func composed(_ name: [UInt8]) -> [UInt8] {
        return Array(String(decoding: name, as: UTF8.self).precomposedStringWithCanonicalMapping.utf8)
    }

    private static func isASCIILetter(_ character: Character) -> Bool {
        guard let value = character.asciiValue else {
            return false
        }
        return (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let value = character.asciiValue else {
            return false
        }
        return value >= 48 && value <= 57
    }

    private static func allDigits(_ characters: [Character]) -> Bool {
        if characters.isEmpty {
            return false
        }
        for character in characters where !OlderCourseLayout.isASCIIDigit(character) {
            return false
        }
        return true
    }

    private static func twoDigits(_ number: Int) -> String {
        if number < 10 {
            return "0\(number)"
        }
        return "\(number)"
    }
}
