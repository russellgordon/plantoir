import Foundation

/// Copying one page out of a course and into another — what it WILL do,
/// worked out before anything is written.
///
/// The planner here reads and never writes; `CoursePageCopier` writes and
/// never decides. That split is what lets the contract cases assert behaviour
/// without a filesystem race, and it is what makes "the teacher sees exactly
/// what will happen" structurally true rather than a promise.
///
/// **Names are BYTES, throughout.** A file name is carried as the bytes the
/// file system gave and is written back as those same bytes; it is turned into
/// text only to show somebody, and it is normalised only to COMPARE. The
/// measurement behind that rule, and the two system calls that keep it, are in
/// `ReferenceTreeCopier`.

// MARK: - A file name, as the bytes the file system gave

/// One file's name, kept as bytes.
///
/// A `String` round trip is lossless for valid UTF-8 — Swift's `String` does
/// not normalise — but a `URL` round trip is not: measured on this Mac,
/// `folder.appendingPathComponent(name)` decomposed `App\u{00e9}tit.jpg`
/// (`c3 a9`) into `Appe\u{0301}tit.jpg` (`65 cc 81`). So the bytes are carried
/// explicitly rather than trusted to survive whatever a caller does with a
/// path, and a name is never rebuilt from a normalised string.
nonisolated struct ExactName: Sendable, Hashable, Comparable {

    // MARK: - Stored properties

    let bytes: [UInt8]

    // MARK: - Computed properties

    /// The name as text, to show somebody or to look for inside a page. Never
    /// used to build a path that is written to.
    var text: String {
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The form two names are COMPARED in — never the form one is written in.
    ///
    /// Composed (NFC) and case-folded, because the two ways to spell an
    /// accented letter are the same name to a teacher and to Quartz's slug,
    /// and because this volume's file system refuses a destination that
    /// differs only by case. `AssistSectionGraph.normalized` lowercases and
    /// does not compose, which is enough for a wikilink index and not enough
    /// for deciding whether a file is already there.
    var comparisonKey: String {
        return text.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The same, for a PAGE: the `.md` comes off first, so `Arrays.md` and
    /// `arrays.MD` are one name.
    var pageComparisonKey: String {
        var name: String = text
        if name.lowercased().hasSuffix(".md") {
            name = String(name.dropLast(3))
        }
        return name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The name a teacher reads for a page: no `.md`, and nothing normalised.
    var pageText: String {
        let name: String = text
        if name.lowercased().hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }

    // MARK: - Initializer

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    init(_ text: String) {
        self.bytes = Array(text.utf8)
    }

    // MARK: - Functions

    static func < (first: ExactName, second: ExactName) -> Bool {
        return first.text.localizedStandardCompare(second.text) == .orderedAscending
    }

    /// The same name with something added before its extension —
    /// `diagram.png` becomes `diagram (from ICS4U-2025).png`.
    ///
    /// Split at the last dot in the BYTES, so the stem's own bytes are handed
    /// straight back rather than re-spelled. A name with no dot takes the
    /// suffix at the end; a name with two takes it before the last one.
    func addingBeforeExtension(_ suffix: String) -> ExactName {
        let dot: UInt8 = 46
        var lastDot: Int? = nil
        for index in bytes.indices where bytes[index] == dot {
            // A leading dot is a hidden file's marker, not an extension.
            if index > 0 {
                lastDot = index
            }
        }
        var result: [UInt8] = []
        guard let lastDot else {
            result.append(contentsOf: bytes)
            result.append(contentsOf: Array(suffix.utf8))
            return ExactName(bytes: result)
        }
        result.append(contentsOf: bytes[0..<lastDot])
        result.append(contentsOf: Array(suffix.utf8))
        result.append(contentsOf: bytes[lastDot...])
        return ExactName(bytes: result)
    }
}

// MARK: - What the copy needs to know about a course

/// The facts about one course that copying a page needs, as plain values.
///
/// `Course` is an `@Observable` class and is not `Sendable`, so it cannot
/// cross into the copy — which runs off the main actor because a real backup
/// of a real course takes about ten seconds. This is the seam: read on the
/// main actor from a `Course`, then handed over.
nonisolated struct CopyCourseFacts: Sendable, Equatable {

    // MARK: - Stored properties

    /// The folder name, which is this course's identity — `ICS4U-2025` for a
    /// course kept for reference.
    let code: String

    /// The code a TEACHER reads — `ICS4U`.
    let displayCode: String

    let directoryPath: String

    /// The timetable sections, as the settings said when this was read. The
    /// executor asks the file again immediately before it composes anything,
    /// because a section added in another window between the plan and the
    /// write would leave the copy visible in it.
    let sectionNumbers: [Int]

    /// Top-level shared folders that are listed in the settings AND exist on
    /// disk, with `Media` left out. A folder in the list that is not on disk
    /// is not offered: writing into it would mean creating it, and Plantoir
    /// never creates a folder for this.
    let sharedFolderNames: [String]

    let isKeptForReference: Bool

    // MARK: - Computed properties

    var directoryURL: URL {
        return URL(fileURLWithPath: directoryPath)
    }

    var mediaFolderURL: URL {
        return directoryURL.appendingPathComponent(CopyCourseFacts.mediaFolderName)
    }

    var configFileURL: URL {
        return directoryURL.appendingPathComponent("course_config.json")
    }

    /// The folder Plantoir looks after itself, which is why it is not in
    /// `sharedFolderNames` and not a folder a teacher can choose.
    static let mediaFolderName: String = "Media"

    // MARK: - Functions

    /// Read from a loaded course, on whichever actor holds it.
    @MainActor
    static func read(from course: Course) -> CopyCourseFacts {
        var folders: [String] = []
        for name in course.configuration.sharedFolders {
            if name.lowercased() == CopyCourseFacts.mediaFolderName.lowercased() {
                continue
            }
            let folderURL: URL = course.directoryURL.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                folders.append(name)
            }
        }
        return CopyCourseFacts(
            code: course.code,
            displayCode: course.displayCode,
            directoryPath: course.directoryURL.path,
            sectionNumbers: course.sectionNumbers,
            sharedFolderNames: folders,
            isKeptForReference: course.isKeptForReference
        )
    }

    /// The section numbers as the file says RIGHT NOW, or nil when it cannot
    /// be read.
    ///
    /// Asked again by the executor rather than trusted from the plan: a
    /// section added in another window between the two would otherwise leave
    /// the copy with nothing said about it, and Quartz publishes a page that
    /// says nothing.
    static func sectionNumbersOnDisk(at configFileURL: URL) -> [Int]? {
        guard let data = try? Data(contentsOf: configFileURL),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let numbers = decoded["section_numbers"] as? [Int], !numbers.isEmpty {
            var sorted: [Int] = numbers
            sorted.sort()
            return sorted
        }
        if let raw = decoded["section_numbers"] as? [Any] {
            var numbers: [Int] = []
            for entry in raw {
                if let number = entry as? NSNumber {
                    numbers.append(number.intValue)
                }
            }
            if !numbers.isEmpty {
                numbers.sort()
                return numbers
            }
        }
        if let count = (decoded["num_sections"] as? NSNumber)?.intValue, count > 0 {
            var numbers: [Int] = []
            for number in 1...count {
                numbers.append(number)
            }
            return numbers
        }
        return nil
    }
}

// MARK: - What the picker lists

/// One page of a source course that may be copied.
nonisolated struct CopyablePage: Sendable, Hashable, Identifiable {

    // MARK: - Stored properties

    /// The folder it sits in — `Concepts`.
    let folderName: String

    /// The file's name, bytes and all.
    let fileName: ExactName

    // MARK: - Computed properties

    /// What a teacher calls it: the file name without `.md`.
    ///
    /// The FILE name rather than a frontmatter `title:`, because that is what
    /// links resolve by and what the copy is written under. Measured: 0 of
    /// ICS4U's 156, ICS3U's 183 and MPM2DE's 75 copyable pages carry a
    /// `title:` at all, so the two never diverge here anyway.
    var pageName: String {
        return fileName.pageText
    }

    var id: String {
        return folderName + "/" + fileName.text
    }

    var relativePath: String {
        return folderName + "/" + fileName.text
    }
}

// MARK: - The request

nonisolated struct CoursePageCopyRequest: Sendable {

    // MARK: - Stored properties

    let source: CopyCourseFacts
    let page: CopyablePage
    let destination: CopyCourseFacts
    let destinationFolderName: String

    // MARK: - Computed properties

    var sourcePageURL: URL {
        return ReferenceTreeCopier.url(
            named: page.fileName.bytes,
            inFolderAt: source.directoryURL.appendingPathComponent(page.folderName)
        )
    }

    var destinationFolderURL: URL {
        return destination.directoryURL.appendingPathComponent(destinationFolderName)
    }
}

// MARK: - The plan

/// Where one page will land.
nonisolated struct CopiedPagePlacement: Sendable, Equatable {

    // MARK: - Stored properties

    let sourceFolderName: String
    let fileName: ExactName
    let destinationFolderName: String

    // MARK: - Computed properties

    var pageName: String {
        return fileName.pageText
    }
}

/// What happens to one picture or file the page shows.
nonisolated struct CopiedMediaPlacement: Sendable, Equatable {

    // MARK: - Stored properties

    let sourceName: ExactName

    /// The name it lands under — the same bytes as the source's, unless a
    /// DIFFERENT file of that name is already there.
    let destinationName: ExactName

    /// True when a file of that name is already there and is the same file,
    /// so nothing is copied and nothing is said.
    let isAlreadyThereAndIdentical: Bool

    let byteCount: Int64

    // MARK: - Computed properties

    var wasRenamed: Bool {
        return sourceName != destinationName
    }
}

/// Something the plan will not do, and why.
nonisolated struct CopySkip: Sendable, Equatable {

    // MARK: - Types

    /// A stable key for the contract — never the sentence, which is product
    /// wording and will be reworded.
    enum Reason: String, Sendable {
        case aPageOfThatNameIsAlreadyHere
        case thePageCouldNotBeRead
        case theCopyCouldNotBeMadeHidden
        case theCopyIsStillThereAndMustBeRemoved
        case thePageIsWrittenInAWayPlantoirCannotBeSureOf
        case thePicturesCouldNotBePointedAtTheirNewNames
        case thePageCouldNotBeWritten
        case aPictureCouldNotBeCopied
    }

    // MARK: - Stored properties

    let name: String
    let reason: Reason
}

/// Everything one press of Copy will do.
nonisolated struct CoursePageCopyPlan: Sendable {

    // MARK: - Stored properties

    let pages: [CopiedPagePlacement]
    let media: [CopiedMediaPlacement]
    let skipped: [CopySkip]

    /// Links on the copied pages that will not lead anywhere in the
    /// destination — a page it does not have, or a file the source itself
    /// could not find. NEVER dropped silently; this is the list.
    let linksLeadingNowhere: [String]

    // MARK: - Computed properties

    /// The pictures and files that will actually be written.
    var mediaToCreate: [CopiedMediaPlacement] {
        var result: [CopiedMediaPlacement] = []
        for item in media where !item.isAlreadyThereAndIdentical {
            result.append(item)
        }
        return result
    }

    var mediaAlreadyThere: [CopiedMediaPlacement] {
        var result: [CopiedMediaPlacement] = []
        for item in media where item.isAlreadyThereAndIdentical {
            result.append(item)
        }
        return result
    }

    var mediaUnderANewName: [CopiedMediaPlacement] {
        var result: [CopiedMediaPlacement] = []
        for item in media where item.wasRenamed {
            result.append(item)
        }
        return result
    }

    var totalBytes: Int64 {
        var total: Int64 = 0
        for item in mediaToCreate {
            total += item.byteCount
        }
        return total
    }

    var changesNothing: Bool {
        return pages.isEmpty
    }
}

// MARK: - The planner

/// Works out what a copy will do. Reads files; writes none.
nonisolated enum CoursePageCopyPlanner {

    // MARK: - Functions

    /// Every page of a course that may be copied.
    ///
    /// Inside a top-level shared folder, and nowhere else: never a class
    /// page, never a folder's `index.md`, never a page at the course root,
    /// never a page inside a `section<N>` folder. Those are Russell's rules
    /// and each has a reason — a class page belongs to a timetable, an
    /// `index.md` is the way IN to a folder rather than a page anybody links
    /// to, and a per-section page belongs to one section's classes.
    ///
    /// Only the folder's own top level is listed. Measured: 0 of 452 real
    /// shared pages, 0 of 38 example-content payloads and 0 of 2,038
    /// skeleton pages sit in a subfolder, and `build_site.py`'s
    /// `discover_shared_items` scans the course root only.
    static func copyablePages(in course: CopyCourseFacts) -> [CopyablePage] {
        var found: [CopyablePage] = []
        for folderName in course.sharedFolderNames {
            let folderURL: URL = course.directoryURL.appendingPathComponent(folderName)
            for nameBytes in ReferenceTreeCopier.names(inFolderAt: folderURL) {
                let name: ExactName = ExactName(bytes: nameBytes)
                if !name.text.lowercased().hasSuffix(".md") {
                    continue
                }
                if name.text.lowercased() == "index.md" {
                    continue
                }
                found.append(CopyablePage(folderName: folderName, fileName: name))
            }
        }
        found.sort { first, second in
            if first.folderName != second.folderName {
                return first.folderName.localizedStandardCompare(second.folderName) == .orderedAscending
            }
            return first.fileName < second.fileName
        }
        return found
    }

    /// What one copy will do.
    static func plan(_ request: CoursePageCopyRequest) -> CoursePageCopyPlan {
        let index: DestinationIndex = DestinationIndex(of: request.destination)

        // The collision rule, asked of the WHOLE destination course — any
        // folder, per-section or shared, at any depth. A page of that name
        // already there is left exactly as it is and the links then lead to
        // it, which is the answer a teacher would give.
        if index.pageNames.contains(request.page.fileName.pageComparisonKey) {
            return CoursePageCopyPlan(
                pages: [],
                media: [],
                skipped: [CopySkip(
                    name: request.page.pageName, reason: .aPageOfThatNameIsAlreadyHere
                )],
                linksLeadingNowhere: []
            )
        }

        guard let pageText = try? String(contentsOf: request.sourcePageURL, encoding: .utf8) else {
            return CoursePageCopyPlan(
                pages: [],
                media: [],
                skipped: [CopySkip(name: request.page.pageName, reason: .thePageCouldNotBeRead)],
                linksLeadingNowhere: []
            )
        }

        let placement: CopiedPagePlacement = CopiedPagePlacement(
            sourceFolderName: request.page.folderName,
            fileName: request.page.fileName,
            destinationFolderName: request.destinationFolderName
        )

        // The pages this copy is bringing count as "there": a page that links
        // to ITSELF — measured on a real course, where one Concepts page names
        // its own title — would otherwise be reported as a link that leads
        // nowhere, about the very page the teacher is copying.
        var arriving: Set<String> = []
        arriving.insert(request.page.fileName.pageComparisonKey)

        let gathered: GatheredReferences = CoursePageCopyPlanner.gather(
            referencesIn: pageText,
            source: request.source,
            destination: index,
            alsoArriving: arriving
        )

        if gathered.aPictureCouldNotBeGivenAFreeName {
            return CoursePageCopyPlan(
                pages: [],
                media: [],
                skipped: [CopySkip(
                    name: request.page.pageName,
                    reason: .thePicturesCouldNotBePointedAtTheirNewNames
                )],
                linksLeadingNowhere: gathered.linksLeadingNowhere
            )
        }

        return CoursePageCopyPlan(
            pages: [placement],
            media: gathered.media,
            skipped: [],
            linksLeadingNowhere: gathered.linksLeadingNowhere
        )
    }

    // MARK: - Private helpers

    /// What one page's references resolve to.
    struct GatheredReferences: Sendable {
        let media: [CopiedMediaPlacement]
        let linksLeadingNowhere: [String]

        /// True when a picture had to come in under a new name and no free
        /// name could be found.
        ///
        /// **The PAGE is then not copied at all**, and that is the whole
        /// point of carrying this out rather than quietly listing the file:
        /// the destination already HAS a file of that name, with different
        /// bytes — which is exactly why a new name was needed — so a page
        /// written with the original name would show the teacher their own,
        /// different picture. Listing it said the opposite ("this link will
        /// not lead anywhere") about a link that leads somewhere wrong.
        let aPictureCouldNotBeGivenAFreeName: Bool
    }

    /// Every picture and file a page names, resolved against the source's
    /// `Media` folder — and everything it names that resolves to nothing.
    ///
    /// Three shapes are looked at, and that list is measured rather than
    /// assumed: `![[…]]` embeds (1,474 in four real courses), `[[…]]` links
    /// that point at a FILE rather than a page (250, of which 235 are PDFs),
    /// and HTML `src`/`href` attributes (5 — one of them a 1.1 MB picture on
    /// a page of Russell's that a teacher would plausibly copy). Markdown
    /// links were measured at 526 across those courses and every single one
    /// is `https://`, so there is nothing local to carry; they are scanned
    /// anyway, because the cost is nothing and a silent drop is the fault
    /// this list exists to prevent.
    static func gather(
        referencesIn pageText: String,
        source: CopyCourseFacts,
        destination: DestinationIndex,
        alsoArriving: Set<String> = []
    ) -> GatheredReferences {
        let sourceMedia: [String: ExactName] = CoursePageCopyPlanner.mediaNames(in: source)
        var media: [CopiedMediaPlacement] = []
        var mediaKeysTaken: Set<String> = []
        var namesTaken: Set<String> = destination.mediaNames
        var leadingNowhere: [String] = []
        var reportedNowhere: Set<String> = []
        var ranOutOfNames: Bool = false

        for reference in PageReferences.references(in: pageText) {
            let lastComponent: String = reference.lastComponent
            if lastComponent.isEmpty {
                continue
            }
            let key: String = ExactName(lastComponent).comparisonKey
            let match: ExactName? = sourceMedia[key] ?? CoursePageCopyPlanner.retryMatch(
                for: lastComponent, in: sourceMedia
            )
            guard let sourceName = match else {
                // Not a picture or file. Either it names a page the
                // destination already has — in which case the link works and
                // nothing is said — or it leads nowhere and is LISTED.
                let pageKey: String = ExactName(lastComponent).pageComparisonKey
                if destination.pageNames.contains(pageKey) || alsoArriving.contains(pageKey) {
                    continue
                }
                if !reportedNowhere.contains(key) {
                    reportedNowhere.insert(key)
                    leadingNowhere.append(reference.target)
                }
                continue
            }

            // Found under a name the link does not actually spell — the
            // no-break-space case. The file is carried under its REAL name,
            // and the link is still listed, because it does not resolve in
            // the source either.
            if sourceMedia[key] == nil && !reportedNowhere.contains(key) {
                reportedNowhere.insert(key)
                leadingNowhere.append(reference.target)
            }

            if mediaKeysTaken.contains(sourceName.comparisonKey) {
                continue
            }
            mediaKeysTaken.insert(sourceName.comparisonKey)

            let sourceURL: URL = ReferenceTreeCopier.url(
                named: sourceName.bytes, inFolderAt: source.mediaFolderURL
            )
            let size: Int64 = CoursePageCopyPlanner.byteCount(of: sourceURL)

            guard destination.mediaNames.contains(sourceName.comparisonKey) else {
                media.append(CopiedMediaPlacement(
                    sourceName: sourceName,
                    destinationName: sourceName,
                    isAlreadyThereAndIdentical: false,
                    byteCount: size
                ))
                namesTaken.insert(sourceName.comparisonKey)
                continue
            }

            let theirs: URL = ReferenceTreeCopier.url(
                named: (destination.mediaNamesByKey[sourceName.comparisonKey] ?? sourceName).bytes,
                inFolderAt: destination.mediaFolderURL
            )
            if CoursePageCopyPlanner.sameFile(sourceURL, theirs) {
                media.append(CopiedMediaPlacement(
                    sourceName: sourceName,
                    destinationName: sourceName,
                    isAlreadyThereAndIdentical: true,
                    byteCount: size
                ))
                continue
            }

            // Same name, DIFFERENT file. The teacher's own picture is never
            // touched; this one comes in beside it under a name proven free.
            guard let freeName = CoursePageCopyPlanner.freeName(
                basedOn: sourceName, fromCourse: source.code, avoiding: namesTaken
            ) else {
                ranOutOfNames = true
                continue
            }
            namesTaken.insert(freeName.comparisonKey)
            media.append(CopiedMediaPlacement(
                sourceName: sourceName,
                destinationName: freeName,
                isAlreadyThereAndIdentical: false,
                byteCount: size
            ))
        }

        return GatheredReferences(
            media: media,
            linksLeadingNowhere: leadingNowhere,
            aPictureCouldNotBeGivenAFreeName: ranOutOfNames
        )
    }

    /// One more try for a name whose spaces the teacher typed and the file
    /// does not carry.
    ///
    /// Measured in a real course: a page links to
    /// `[[User Stories – Exemplar 3 – Advanced.pdf]]` while the file in
    /// `Media` carries a NO-BREAK SPACE after each en-dash, so a plain
    /// comparison does not find it. Folding the two invisible spaces to an
    /// ordinary one finds the file; the link is still reported, because it
    /// does not resolve in the source either and the teacher may want to fix
    /// it.
    static func retryMatch(for name: String, in media: [String: ExactName]) -> ExactName? {
        let folded: String = CoursePageCopyPlanner.foldingInvisibleSpaces(ExactName(name).comparisonKey)
        for (key, value) in media where CoursePageCopyPlanner.foldingInvisibleSpaces(key) == folded {
            return value
        }
        return nil
    }

    static func foldingInvisibleSpaces(_ text: String) -> String {
        var result: String = ""
        for character in text {
            if character == "\u{00A0}" || character == "\u{202F}" || character == "\u{2007}" {
                result.append(" ")
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// The source course's pictures and files, by comparison key.
    static func mediaNames(in course: CopyCourseFacts) -> [String: ExactName] {
        var found: [String: ExactName] = [:]
        for nameBytes in ReferenceTreeCopier.names(inFolderAt: course.mediaFolderURL) {
            let name: ExactName = ExactName(bytes: nameBytes)
            if found[name.comparisonKey] == nil {
                found[name.comparisonKey] = name
            }
        }
        return found
    }

    /// A name for an incoming file that nothing in the destination already
    /// has, or nil when even a bounded search cannot find one.
    ///
    /// The course's FOLDER name goes in the brackets rather than the word
    /// "Media" — every picture comes from `Media`, so that would say nothing,
    /// while `ICS4U-2025` says which course it came out of and is what tells
    /// two ICS4Us apart.
    static func freeName(
        basedOn name: ExactName, fromCourse courseFolderName: String, avoiding taken: Set<String>
    ) -> ExactName? {
        let first: ExactName = name.addingBeforeExtension(" (from \(courseFolderName))")
        if !taken.contains(first.comparisonKey) {
            return first
        }
        for attempt in 2...50 {
            let candidate: ExactName = name.addingBeforeExtension(
                " (from \(courseFolderName)) \(attempt)"
            )
            if !taken.contains(candidate.comparisonKey) {
                return candidate
            }
        }
        return nil
    }

    static func byteCount(of url: URL) -> Int64 {
        var status: stat = stat()
        if stat(url.path, &status) != 0 {
            return 0
        }
        return Int64(status.st_size)
    }

    /// Whether two files hold the same bytes.
    ///
    /// Size first and contents only when the sizes match, so hashing costs
    /// nothing for the ordinary case — and read in chunks rather than whole,
    /// because a real picture here can be hundreds of megabytes.
    static func sameFile(_ first: URL, _ second: URL) -> Bool {
        if CoursePageCopyPlanner.byteCount(of: first) != CoursePageCopyPlanner.byteCount(of: second) {
            return false
        }
        guard let left = try? FileHandle(forReadingFrom: first),
              let right = try? FileHandle(forReadingFrom: second) else {
            return false
        }
        defer {
            try? left.close()
            try? right.close()
        }
        let chunk: Int = 1024 * 1024
        while true {
            let leftChunk: Data = (try? left.read(upToCount: chunk)) ?? Data()
            let rightChunk: Data = (try? right.read(upToCount: chunk)) ?? Data()
            if leftChunk != rightChunk {
                return false
            }
            if leftChunk.isEmpty {
                return true
            }
        }
    }
}

// MARK: - What is already in the destination

/// Every name the destination course already uses, gathered once.
///
/// The page index covers the WHOLE course at every depth — shared folders,
/// per-section folders, the root — because Russell's rule is that a page name
/// already anywhere in the destination is left alone. The built website is
/// skipped: it is a symlink out of the folder and everything in it is
/// generated.
nonisolated struct DestinationIndex: Sendable {

    // MARK: - Stored properties

    /// Page names, `.md` dropped, composed and case-folded.
    let pageNames: Set<String>

    /// Picture and file names in `Media`, composed and case-folded.
    let mediaNames: Set<String>

    /// The same, back to the bytes they are spelled with on disk.
    let mediaNamesByKey: [String: ExactName]

    let mediaFolderURL: URL

    // MARK: - Type properties

    /// Generated or private, and never a page a teacher wrote.
    static let leftOutOfTheIndex: Set<String> = [
        ".merged_output", "node_modules", ".git", ".quartz-cache", ".cache", ".obsidian",
    ]

    // MARK: - Initializer

    init(of course: CopyCourseFacts) {
        let survey: ReferenceTreeCopier.Survey = ReferenceTreeCopier.walk(
            courseAt: course.directoryURL, leavingBehind: DestinationIndex.leftOutOfTheIndex
        )
        var pages: Set<String> = []
        for item in survey.items where !item.isDirectory {
            var lastComponent: [UInt8] = []
            for byte in item.relativePath {
                if byte == 47 {
                    lastComponent = []
                } else {
                    lastComponent.append(byte)
                }
            }
            let name: ExactName = ExactName(bytes: lastComponent)
            if name.text.lowercased().hasSuffix(".md") {
                pages.insert(name.pageComparisonKey)
            }
        }
        pageNames = pages

        var media: Set<String> = []
        var byKey: [String: ExactName] = [:]
        let mediaURL: URL = course.mediaFolderURL
        for nameBytes in ReferenceTreeCopier.names(inFolderAt: mediaURL) {
            let name: ExactName = ExactName(bytes: nameBytes)
            media.insert(name.comparisonKey)
            if byKey[name.comparisonKey] == nil {
                byKey[name.comparisonKey] = name
            }
        }
        mediaNames = media
        mediaNamesByKey = byKey
        mediaFolderURL = mediaURL
    }
}
