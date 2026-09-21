import Foundation

/// The text a copied page arrives with.
///
/// **A copy is ALWAYS hidden from students, in every section of the course it
/// lands in, and the order of the four steps below is the whole of why.**
/// Each one was measured, and three of the four have a failure that publishes
/// the page if they are done differently.
nonisolated enum CopiedPageText {

    // MARK: - Functions

    /// The source page's text, made hidden everywhere in the destination.
    ///
    /// 1. **The source's per-section keys come off** (`withoutPerSectionKeys`).
    ///    They are the source course's answers about the source course's
    ///    sections and they mean nothing here — and an inherited
    ///    `publishForSection1: true` beats everything this writes.
    /// 2. **The plain `publish:` and `draft:` come off too**, with the
    ///    READER's own matcher and its continuation rule. A naive
    ///    `hasPrefix("draft:")` orphans a value written on the line below,
    ///    which then folds into the last key written and produces the plain
    ///    scalar `"false true"` — and Quartz does not hide a string that is
    ///    not `"false"`, so the page is PUBLISHED. Measured. The house format
    ///    drops these anyway: `scripts/setup_course.py` →
    ///    `per_section_frontmatter` removes the plain `created`/`publish`/
    ///    `draft` lines when it splits a page into per-section pairs.
    /// 3. **`publishForSection<N>: false` for every section the destination
    ///    has**, written DESCENDING so the file reads 1, 2, 3 — each call
    ///    inserts at the top of the block.
    /// 4. **A plain `publish: false`, LAST.** This is what keeps the copy
    ///    hidden in a section the destination gains LATER, by any route.
    ///    Measured: all 156 of ICS4U's real shared pages composed with the
    ///    per-section keys alone come out VISIBLE in a section 4 they were
    ///    never told about, because Quartz publishes a page that says
    ///    nothing. And it must come last: writing it FIRST makes
    ///    `AssistPageVisibility.setting` a complete no-op — its "already says
    ///    it" gate reads the plain key and returns unchanged, so no
    ///    per-section key is written at all.
    ///
    /// `created:` is KEPT, with everything else the teacher wrote. A page
    /// copied from last year shows last year's date until they change it,
    /// which they see in Obsidian before publishing; silently rewriting a
    /// date in their own frontmatter is the larger sin.
    static func hidden(from sourceText: String, forSections sectionNumbers: [Int]) -> String {
        var text: String = AssistPageVisibility.withoutPerSectionKeys(in: sourceText)
        text = CopiedPageText.withoutPlainVisibilityKeys(in: text)

        var descending: [Int] = sectionNumbers
        descending.sort()
        for sectionNumber in descending.reversed() {
            text = AssistPageVisibility.setting(
                published: false, in: text, forSection: sectionNumber, isSectionLocal: false
            ).text
        }
        return CopiedPageText.appendingPlainHiddenKey(to: text)
    }

    /// The text with a plain `publish: false` as the last line of its
    /// frontmatter.
    static func appendingPlainHiddenKey(to pageText: String) -> String {
        let line: String = "publish: false"
        guard let block = PageFrontmatter.block(in: pageText) else {
            return "---\n" + line + "\n---\n" + pageText
        }
        var lines: [String] = pageText.components(separatedBy: "\n")
        lines.insert(line, at: block.closeIndex)
        return lines.joined(separator: "\n")
    }

    /// The text with the plain `publish:` and `draft:` keys taken out —
    /// lines, not one line.
    ///
    /// Asked with `AssistPageVisibility.topLevelLineIndices`, which is the
    /// reader's own matcher, so a quoted `"draft": true` is found; and every
    /// line that was part of a key's VALUE goes with it, which is what
    /// `PageVisibilityReader.continuationLineIndices` exists for.
    static func withoutPlainVisibilityKeys(in pageText: String) -> String {
        guard let block = PageFrontmatter.block(in: pageText) else {
            return pageText
        }
        var lines: [String] = pageText.components(separatedBy: "\n")
        var removals: Set<Int> = []
        for key in ["publish", "draft"] {
            for index in AssistPageVisibility.topLevelLineIndices(ofKey: key, in: pageText) {
                removals.insert(index)
                for taken in PageVisibilityReader.continuationLineIndices(
                    belowKeyAt: index, in: lines, closeIndex: block.closeIndex,
                    keyValueWasEmpty: AssistPageVisibility.valueIsEmpty(ofKey: key, inLine: lines[index])
                ) {
                    removals.insert(taken)
                }
            }
        }
        if removals.isEmpty {
            return pageText
        }
        var doomed: [Int] = []
        for index in removals {
            doomed.append(index)
        }
        doomed.sort()
        for index in doomed.reversed() {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }

    /// Whether the WEBSITE BUILDER would read this page's settings the same
    /// way this app does — stated as ONE INVARIANT rather than a list of
    /// shapes.
    ///
    /// **The invariant: every key that hides this copy must lie inside the
    /// region the BUILD reads as frontmatter, and that region must contain no
    /// other visibility key and nothing this app knows the build's parser
    /// chokes on.**
    ///
    /// The build's region is python-frontmatter's, not this app's: the first
    /// line must open a block, and the block ENDS at the FIRST later line
    /// matching `^-{3,}\s*$` — at COLUMN 0, with no indentation allowed.
    /// `PageVisibilityReader.isFence` trims leading spaces before testing a
    /// fence and therefore can close a block earlier than the build does; the
    /// gap between the two is where every failure below lives.
    ///
    /// **Why the key multiset is the whole test.** By the time this is asked,
    /// `hidden(from:forSections:)` has stripped every per-section key and
    /// both plain keys from the region THIS APP sees, and written its own.
    /// So if the build's region carries any visibility key that is not one of
    /// ours, the two readers disagreed about where the block ends — and the
    /// build takes the LAST one it sees. That is not a heuristic about a
    /// shape; it is the disagreement itself, observed.
    ///
    /// Three failures were reproduced end to end and each one is caught by
    /// exactly that:
    ///
    /// * a block closed by an INDENTED `---` (issue #188) — the app finds an
    ///   end the build does not, so the source's own keys survive below it;
    /// * a **block scalar carrying a horizontal rule**
    ///   (`description: |` … `  ---`) — the app closes INSIDE the scalar and
    ///   inserts its `publish: false` there, while the build reads the whole
    ///   thing and takes the source's `publish: true` from the bottom. The
    ///   copy reached students in section 1 while the summary said it was
    ///   hidden;
    /// * a source whose block the app closes and the build does not, so a
    ///   second block is prepended and the file becomes several documents.
    ///
    /// **A benign block scalar is NOT refused**, and that matters: a
    /// `description: |` with no rule inside it is read identically by both,
    /// carries no extra visibility key, and copies. Refusing block scalars
    /// outright was the cheap answer and it would have been a false refusal
    /// on data that is perfectly ordinary.
    ///
    /// The last clause is the small, measured list of things the build's YAML
    /// parser refuses outright — a directive, a document-end marker, a
    /// leading tab, an anchor or alias in a VALUE position. When
    /// `frontmatter.load` raises, `build_site.py` prints a warning and
    /// RETURNS, so the page reaches Quartz with nothing resolved. An `&` or a
    /// `*` INSIDE a value is not an anchor — four pages Plantoir itself ships
    /// were refused for `title: "Task 1 - Pacific Trail & Alpine Hazard
    /// Simulator"` before that was made precise.
    static func theBuilderWouldReadItTheSameWay(
        _ pageText: String, forSections sectionNumbers: [Int]
    ) -> Bool {
        // **A LONE CARRIAGE RETURN is a line break to the build and not to
        // this app**, which is a disagreement about where every line is, not
        // merely where the block ends. `frontmatter.load` opens the file in
        // Python's text mode, where `\r` alone ends a line; Swift's
        // `components(separatedBy: "\n")` does not split there at all.
        // Measured repro: a source of
        // `---\ntitle: Notes\r---\rpublish: true\n---\nBody text.\n` is
        // certified, and the build reads only the per-section keys while the
        // plain `publish: false` falls into the BODY — so a section the
        // course does not have yet is published.
        //
        // Modelling universal newlines was rejected: it would mean a second
        // line splitter everywhere, disagreeing with the one the rest of the
        // app uses. Measured, 0 of the 12,668 pages Plantoir ships and the
        // real courses carry a lone `\r`, so refusing them costs nothing.
        var previous: Character? = nil
        for character in pageText {
            if previous == "\r" && character != "\n" {
                return false
            }
            previous = character
        }
        if previous == "\r" {
            return false
        }

        let lines: [String] = pageText.components(separatedBy: "\n")
        guard !lines.isEmpty, CopiedPageText.isAFenceTheBuilderSees(lines[0]) else {
            return false
        }
        var closeIndex: Int? = nil
        for index in 1..<lines.count where CopiedPageText.isAFenceTheBuilderSees(lines[index]) {
            closeIndex = index
            break
        }
        guard let closeIndex else {
            return false
        }

        // **The two readers must agree about where the block ENDS.**
        //
        // This is the condition that kills a whole fault class rather than
        // one shape of it: if this app read a different region from the one
        // the build will read, then the keys it stripped, the keys it wrote
        // and the place it wrote them were all decided about the wrong text.
        guard let appBlock = PageFrontmatter.block(in: pageText),
              appBlock.openIndex == 0,
              appBlock.closeIndex == closeIndex else {
            return false
        }

        // **Every line must be a SHAPE on the whitelist** — see
        // `regionIsOnlyShapesTheBuildAgreesOn`.
        guard CopiedPageText.regionIsOnlyShapesTheBuildAgreesOn(
            lines, from: 1, to: closeIndex
        ) else {
            return false
        }

        // Every hiding key this code wrote, and nothing else.
        var wanted: Set<String> = ["publish: false"]
        for sectionNumber in sectionNumbers {
            wanted.insert("publishForSection\(sectionNumber): false")
        }
        var found: Set<String> = []
        for index in 1..<closeIndex {
            let tidied: String = CopiedPageText.trimmingTrailingSpaces(
                PageFrontmatter.trimmingCarriageReturn(lines[index])
            )
            if wanted.contains(tidied) {
                found.insert(tidied)
                continue
            }
            // Any OTHER visibility key inside the build's region means the
            // two readers disagreed about where the block ends, and the build
            // takes the LAST one it sees.
            if tidied.hasPrefix(" ") || tidied.hasPrefix("\t") {
                continue
            }
            if CopiedPageText.namesAVisibilityKey(tidied) {
                return false
            }
        }
        return found == wanted
    }

    /// Whether every line of the build's region is a shape this app can SHOW
    /// the build reads the way it does.
    ///
    /// **A WHITELIST, and deliberately narrower than YAML.** Excluding the
    /// shapes known to go wrong was tried and failed an independent fuzz: a
    /// grammar-based generator over 60,000 pages found 36 the guard certified
    /// and the build did not hide, most of them PyYAML INDENTATION errors
    /// that no list of forbidden shapes had thought of —
    /// `description: A long note` followed by `  about time: 10am` is an
    /// indented continuation of a plain scalar that contains `: `, which
    /// PyYAML refuses; and when the build cannot parse the block it reads NO
    /// keys at all, so the page is published whatever the copy wrote.
    ///
    /// The list is derived from what real data actually contains. A census of
    /// the frontmatter of all 12,668 pages Plantoir ships and all 777 pages
    /// of four real courses found exactly FOUR shapes: `key: value` with a
    /// plain scalar (48,091 lines), an indented list item (14,462), `key:`
    /// with its value on the lines below (10,561), and `key: value` with a
    /// quoted scalar (13). Blank lines and comments are allowed as well —
    /// neither carries a key, so neither can move a page's visibility.
    ///
    /// Everything else is NOT COPIED, and the teacher is told so in a plain
    /// sentence. A page Plantoir will not copy can always be copied by hand.
    static func regionIsOnlyShapesTheBuildAgreesOn(
        _ lines: [String], from: Int, to: Int
    ) -> Bool {
        var mayBeFollowedByListItems: Bool = false
        for index in from..<to {
            let line: String = PageFrontmatter.trimmingCarriageReturn(lines[index])
            // **A TAB anywhere refuses the line.** YAML forbids a tab in
            // indentation, and PyYAML raises a `ScannerError` on one — which
            // means the build reads NO keys and publishes the page. A line of
            // `"   \t "` is whitespace to the eye and a parse error to the
            // parser; the independent fuzz found exactly that shape. Measured:
            // no frontmatter line in the 12,668 shipped and real pages
            // contains a tab.
            if line.contains("\t") {
                return false
            }
            var bare: Substring = Substring(line)
            while bare.last == " " {
                bare = bare.dropLast()
            }
            if bare.isEmpty {
                continue
            }
            if bare.hasPrefix(" ") {
                // The ONLY indented shape on the list: an item of a list
                // whose key is on the line above.
                var item: Substring = bare
                while item.first == " " {
                    item = item.dropFirst()
                }
                guard mayBeFollowedByListItems, item.hasPrefix("- "), item.count > 2 else {
                    return false
                }
                guard CopiedPageText.isAPlainScalar(String(item.dropFirst(2))) else {
                    return false
                }
                continue
            }
            mayBeFollowedByListItems = false
            if bare.hasPrefix("#") {
                continue
            }
            guard let name = CopiedPageText.keyNamed(String(bare)) else {
                return false
            }
            var rest: Substring = bare.dropFirst(name.count)
            guard rest.first == ":" else {
                return false
            }
            rest = rest.dropFirst()
            if rest.isEmpty {
                mayBeFollowedByListItems = true
                continue
            }
            guard rest.first == " " else {
                // `key:value` is one long scalar to YAML, not a mapping.
                return false
            }
            while rest.first == " " {
                rest = rest.dropFirst()
            }
            guard CopiedPageText.isAPlainScalar(String(rest)) else {
                return false
            }
        }
        return true
    }

    /// The key this line names, or nil when it does not name one in a shape
    /// on the list: letters, digits, spaces, dots, dashes and underscores,
    /// optionally in matching quotes, and nothing else.
    static func keyNamed(_ line: String) -> String? {
        if let quote = line.first, quote == "\"" || quote == "'" {
            guard let close = line.dropFirst().firstIndex(of: quote) else {
                return nil
            }
            return String(line[line.startIndex...close])
        }
        var name: String = ""
        for character in line {
            if character == ":" {
                break
            }
            let isOrdinary: Bool = character.isLetter || character.isNumber
                || character == " " || character == "." || character == "-"
                || character == "_"
            if !isOrdinary {
                return nil
            }
            name.append(character)
        }
        if name.isEmpty || name.hasPrefix(" ") {
            return nil
        }
        return name
    }

    /// A single-line scalar the build reads as text: plain, with nothing in
    /// it that starts a node of another kind, or a closed quoted string.
    static func isAPlainScalar(_ value: String) -> Bool {
        let tidied: String = CopiedPageText.trimmingTrailingSpaces(value)
        if tidied.isEmpty {
            return false
        }
        if let quote = tidied.first, quote == "\"" || quote == "'" {
            return tidied.count >= 2 && tidied.last == quote
        }
        // A flow sequence or mapping, CLOSED on its own line and holding no
        // further one. `tags: []` is on 54 real pages and PyYAML reads it
        // exactly as this app's reader ignores it; what is refused is the
        // multi-line form, where the two readers can part company about where
        // the value ends.
        if tidied.hasPrefix("[") || tidied.hasPrefix("{") {
            let closer: Character = tidied.hasPrefix("[") ? "]" : "}"
            guard tidied.last == closer else {
                return false
            }
            let inside: Substring = tidied.dropFirst().dropLast()
            for character in inside where "[]{}#&*".contains(character) {
                return false
            }
            return true
        }
        for opener in ["&", "*", "|", ">", "!", "{", "[", "#", "%", "@", "`", "-"] {
            if tidied.hasPrefix(opener) {
                return false
            }
        }
        // `a: b: c` is a mapping value where YAML will not have one, and an
        // indented line carrying `: ` is the shape the independent fuzz found
        // 30 of.
        if tidied.contains(": ") || tidied.hasSuffix(":") {
            return false
        }
        return true
    }

    /// True when this top-level line names any of the four keys that decide
    /// whether students meet a page.
    static func namesAVisibilityKey(_ line: String) -> Bool {
        var name: Substring = Substring(line)
        if name.hasPrefix("\"") || name.hasPrefix("'") {
            name = name.dropFirst()
        }
        for family in ["publishForSection", "draftSection"] {
            if name.hasPrefix(family) {
                return true
            }
        }
        for key in ["publish", "draft"] {
            if name.hasPrefix(key) {
                let after: Substring = name.dropFirst(key.count)
                if after.first == ":" || after.first == "\"" || after.first == "'" {
                    return true
                }
            }
        }
        return false
    }

    static func trimmingTrailingSpaces(_ line: String) -> String {
        var tidied: Substring = Substring(line)
        while tidied.last == " " || tidied.last == "\t" {
            tidied = tidied.dropLast()
        }
        return String(tidied)
    }

    /// A line the website builder would take as the edge of a settings block:
    /// three or more dashes at COLUMN 0, with nothing after them but spaces.
    ///
    /// python-frontmatter's own boundary, `^-{3,}\s*$`, which allows no
    /// indentation — unlike `PageVisibilityReader.isFence`, which trims.
    static func isAFenceTheBuilderSees(_ line: String) -> Bool {
        var rest: Substring = Substring(PageFrontmatter.trimmingCarriageReturn(line))
        var dashes: Int = 0
        while rest.first == "-" {
            dashes += 1
            rest = rest.dropFirst()
        }
        if dashes < 3 {
            return false
        }
        while rest.first == " " || rest.first == "\t" {
            rest = rest.dropFirst()
        }
        return rest.isEmpty
    }

    /// A section number the course does not have, for the read-back guard to
    /// ask about.
    static func aSectionNumberNotIn(_ sectionNumbers: [Int]) -> Int {
        var candidate: Int = 1
        while sectionNumbers.contains(candidate) {
            candidate += 1
        }
        return candidate
    }
}

// MARK: - What one press of Copy did

nonisolated struct CoursePageCopyOutcome: Sendable {

    // MARK: - Types

    struct Renamed: Sendable, Equatable {
        let from: String
        let to: String
    }

    // MARK: - Stored properties

    let pagesCreated: [String]
    let mediaCreated: Int
    let mediaReused: Int
    let renamed: [Renamed]
    let skipped: [CopySkip]
    let linksLeadingNowhere: [String]
    let bytesCopied: Int64

    /// Pages that were written, could not be shown to be hidden, and could
    /// NOT be taken away again. Named in the summary and on the trail,
    /// because the teacher has to go and remove them.
    let couldNotBeRemoved: [String]

    // MARK: - Computed properties

    var createdNothing: Bool {
        return pagesCreated.isEmpty
    }
}

// MARK: - The executor

/// Performs a copy. Everything that writes is here; nothing that decides is.
///
/// **Every write refuses rather than replaces.** A page is created with
/// `O_CREAT | O_EXCL` and a picture with `copyfile`'s `COPYFILE_CLONE`, which
/// implies `COPYFILE_EXCL` — both measured to fail on an existing
/// destination, including one that differs only by case or by how an accent
/// is spelled. So a file that appears between the plan and the write surfaces
/// as the ordinary "already here" skip, never as an overwrite.
nonisolated enum CoursePageCopier {

    // MARK: - Stored properties

    /// Whether the last backup or copy ran on the main thread.
    ///
    /// Written by every pass and READ by exactly one test, which is the whole
    /// arrangement and is why it is `nonisolated(unsafe)` — the same seam
    /// `ReferenceLock.lastPassRanOnTheMainThread` is, and for the same
    /// reason: what is worth pinning is a fact about the running program, and
    /// `@concurrent` is an annotation that can be lost in an edit without
    /// anything failing to compile. Nothing in the product reads it.
    nonisolated(unsafe) static var lastPassRanOnTheMainThread: Bool?

    /// Reads the thread from a SYNCHRONOUS context, which is the honest place
    /// to ask: `Thread.isMainThread` is unavailable from an async function.
    static func noteTheThread() {
        CoursePageCopier.lastPassRanOnTheMainThread = Thread.isMainThread
    }

    // MARK: - Functions

    /// Saves a copy of a whole course, off the caller's actor.
    ///
    /// **`@concurrent`, and that attribute is load-bearing**, for the reason
    /// `ReferenceTreeCopier.copy` records: this target builds with
    /// `SWIFT_APPROACHABLE_CONCURRENCY`, under which a plain `nonisolated
    /// async` function runs on its CALLER's actor. Measured on Russell's real
    /// ICS4U, the app's own zip command: **9.7 s and 467 MB**. On the main
    /// actor that is ten seconds of a window that cannot draw.
    ///
    /// `CourseArchiver.backUpCourse` is what this does, taken apart so it can
    /// leave the main actor — and NOT `WorkspaceModel.backUp(_:)`, which also
    /// sets `isShowingBackups` and reloads the courses, flipping the sidebar
    /// in the middle of a copy.
    @concurrent
    static func backingUp(
        courseDirectoryPath: String,
        code: String,
        coursesDirectoryPath: String
    ) async throws -> URL {
        CoursePageCopier.noteTheThread()
        return try CourseArchiver.backUpCourseOffTheMainActor(
            courseDirectoryURL: URL(fileURLWithPath: courseDirectoryPath),
            code: code,
            coursesDirectoryURL: URL(fileURLWithPath: coursesDirectoryPath)
        )
    }

    /// Copies the page, its pictures and its files.
    ///
    /// The plan is worked out again HERE rather than taken from the sheet:
    /// the teacher, Obsidian or a second window can add a file between the
    /// two, and a plan made a minute ago is a description of a course that no
    /// longer exists. The sheet's plan is what the teacher AGREED to; this is
    /// what is true.
    ///
    /// `@concurrent` for the same reason as the backup: the pictures can run
    /// to hundreds of megabytes.
    @concurrent
    static func copying(_ request: CoursePageCopyRequest) async -> CoursePageCopyOutcome {
        CoursePageCopier.noteTheThread()
        // Asked of the file, not of the plan. A section added in another
        // window since the sheet opened would otherwise leave the copy with
        // nothing said about it, and Quartz publishes a page that says
        // nothing.
        let sections: [Int] = CopyCourseFacts.sectionNumbersOnDisk(
            at: request.destination.configFileURL
        ) ?? request.destination.sectionNumbers

        let plan: CoursePageCopyPlan = CoursePageCopyPlanner.plan(request)
        if plan.changesNothing {
            return CoursePageCopyOutcome(
                pagesCreated: [],
                mediaCreated: 0,
                mediaReused: 0,
                renamed: [],
                skipped: plan.skipped,
                linksLeadingNowhere: plan.linksLeadingNowhere,
                bytesCopied: 0,
                couldNotBeRemoved: []
            )
        }

        var skipped: [CopySkip] = plan.skipped
        var stillOnDisk: [String] = []
        var renamed: [CoursePageCopyOutcome.Renamed] = []
        var renaming: [String: ExactName] = [:]
        for item in plan.mediaUnderANewName {
            renaming[item.sourceName.comparisonKey] = item.destinationName
            renamed.append(CoursePageCopyOutcome.Renamed(
                from: item.sourceName.text, to: item.destinationName.text
            ))
        }

        // The pages first, with the media names already settled, so nothing
        // touches a page's bytes after its read-back.
        var pagesCreated: [String] = []
        var writtenPageURLs: [URL] = []
        for placement in plan.pages {
            let sourceFolder: URL = request.source.directoryURL
                .appendingPathComponent(placement.sourceFolderName)
            let sourceURL: URL = ReferenceTreeCopier.url(
                named: placement.fileName.bytes, inFolderAt: sourceFolder
            )
            guard let sourceText = try? String(contentsOf: sourceURL, encoding: .utf8) else {
                skipped.append(CopySkip(name: placement.pageName, reason: .thePageCouldNotBeRead))
                continue
            }

            var text: String = CopiedPageText.hidden(from: sourceText, forSections: sections)
            text = PageReferences.rewriting(text, renaming: renaming)

            // The one direction this feature must never err in: a picture
            // that came in under a new name, with one mention of the old name
            // left behind, would show the teacher's OWN different picture.
            // Checked with the same scanner that found the references, so a
            // rewriter that missed one is caught rather than trusted.
            if !renaming.isEmpty
                && PageReferences.stillNames(Set(renaming.keys), in: text) {
                skipped.append(CopySkip(
                    name: placement.pageName, reason: .thePicturesCouldNotBePointedAtTheirNewNames
                ))
                continue
            }

            let destinationFolder: URL = request.destination.directoryURL
                .appendingPathComponent(placement.destinationFolderName)
            do {
                try ReferenceTreeCopier.create(
                    Data(text.utf8), named: placement.fileName.bytes, inFolderAt: destinationFolder
                )
            } catch {
                // The collision rule firing late. A file that appeared while
                // the teacher was deciding is not an error — it is the same
                // answer the index would have given a moment earlier.
                skipped.append(CopySkip(
                    name: placement.pageName,
                    reason: CoursePageCopier.alreadyThere(at: destinationFolder, named: placement.fileName)
                        ? .aPageOfThatNameIsAlreadyHere
                        : .thePageCouldNotBeWritten
                ))
                continue
            }

            let writtenURL: URL = ReferenceTreeCopier.url(
                named: placement.fileName.bytes, inFolderAt: destinationFolder
            )
            // Cleared BEFORE the read-back, not after: a page written with
            // `open()` carries no flags at all, but a locked one could not be
            // deleted — and deleting it is what the read-back has to be able
            // to do.
            ReferenceLock.clearLock(at: writtenURL)

            let readBack: String? = try? String(contentsOf: writtenURL, encoding: .utf8)
            let isHidden: Bool = CoursePageCopier.isCertainlyHidden(
                at: writtenURL, forSections: sections
            )
            let builderAgrees: Bool = CopiedPageText.theBuilderWouldReadItTheSameWay(
                readBack ?? "", forSections: sections
            )
            if !isHidden || !builderAgrees {
                // **The removal is CHECKED.** "… was not copied" is the
                // strongest promise this feature makes, and making it on an
                // unchecked `try?` would let a page nobody could prove hidden
                // sit in the teacher's course while they were told it was not
                // there. An immutable parent folder is the realistic way it
                // fails.
                let refusal: CopySkip.Reason = CoursePageCopier.refusing(
                    writtenURL, couldBeReadButNotByTheBuilder: isHidden
                ) { url in
                    try FileManager.default.removeItem(at: url)
                }
                if refusal == .theCopyIsStillThereAndMustBeRemoved {
                    stillOnDisk.append(writtenURL.path)
                }
                skipped.append(CopySkip(name: placement.pageName, reason: refusal))
                continue
            }

            pagesCreated.append(placement.pageName)
            writtenPageURLs.append(writtenURL)
        }

        if pagesCreated.isEmpty {
            return CoursePageCopyOutcome(
                pagesCreated: [],
                mediaCreated: 0,
                mediaReused: 0,
                renamed: [],
                skipped: skipped,
                linksLeadingNowhere: plan.linksLeadingNowhere,
                bytesCopied: 0,
                couldNotBeRemoved: stillOnDisk
            )
        }

        // The pictures and files, last. Nothing here can change a page.
        var created: Int = 0
        var reused: Int = plan.mediaAlreadyThere.count
        var bytes: Int64 = 0
        let destinationMedia: URL = request.destination.mediaFolderURL
        // The ONE folder this feature will make. It is not a folder a teacher
        // chooses or can rename — "Plantoir looks after the Media folder
        // itself" — and `SiteHealthRepair` already creates it when it is
        // missing.
        try? FileManager.default.createDirectory(
            at: destinationMedia, withIntermediateDirectories: true
        )
        for item in plan.mediaToCreate {
            do {
                try ReferenceTreeCopier.copyFile(
                    named: item.sourceName.bytes,
                    fromFolderAt: request.source.mediaFolderURL,
                    into: destinationMedia,
                    as: item.destinationName.bytes
                )
                ReferenceLock.clearLock(at: ReferenceTreeCopier.url(
                    named: item.destinationName.bytes, inFolderAt: destinationMedia
                ))
                created += 1
                bytes += item.byteCount
            } catch {
                // A file that appeared between the plan and this write is
                // NOT reported as "already here and will be used as it is":
                // nothing compared its bytes, and the summary would be
                // asserting a sameness that was never checked. It is a skip,
                // named, which is the truthful answer either way.
                skipped.append(CopySkip(
                    name: item.sourceName.text, reason: .aPictureCouldNotBeCopied
                ))
            }
        }

        return CoursePageCopyOutcome(
            pagesCreated: pagesCreated,
            mediaCreated: created,
            mediaReused: reused,
            renamed: renamed,
            skipped: skipped,
            linksLeadingNowhere: plan.linksLeadingNowhere,
            bytesCopied: bytes,
            couldNotBeRemoved: stillOnDisk
        )
    }

    /// What a page that failed the read-back is reported as, having tried to
    /// take it away again.
    ///
    /// **The removal is CHECKED**, and this is a function of its own so that
    /// the branch where it FAILS can be tested: it is the one outcome where
    /// "… was not copied" would be a lie, with a page nobody could prove
    /// hidden still sitting in the teacher's course. An immutable parent
    /// folder is the realistic cause, and it also stops the page being
    /// written in the first place — so the failure cannot be provoked
    /// end to end, and the honest answer is a seam rather than a test that
    /// quietly exercises a different path.
    static func refusing(
        _ url: URL,
        couldBeReadButNotByTheBuilder: Bool,
        removing remove: (URL) throws -> Void
    ) -> CopySkip.Reason {
        do {
            try remove(url)
        } catch {
            return .theCopyIsStillThereAndMustBeRemoved
        }
        return couldBeReadButNotByTheBuilder
            ? .thePageIsWrittenInAWayPlantoirCannotBeSureOf
            : .theCopyCouldNotBeMadeHidden
    }

    /// Whether the page on disk is CERTAINLY hidden — in every section the
    /// destination has, and in one it does not.
    ///
    /// The test is `!= .hidden` rather than `== .visible`, for the reason
    /// `AssistToolRunner` already records: a value this app cannot read is one
    /// the build may well publish, so "cannot tell" counts as failure. The
    /// absent section number is asked because a course can gain one, and the
    /// plain `publish: false` is what answers for it.
    ///
    /// Read back from the FILE rather than from the string that was written,
    /// which is the whole point: it is the bytes on disk that students
    /// eventually meet.
    static func isCertainlyHidden(at url: URL, forSections sectionNumbers: [Int]) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        var toAsk: [Int] = sectionNumbers
        toAsk.append(CopiedPageText.aSectionNumberNotIn(sectionNumbers))
        for sectionNumber in toAsk {
            if AssistPageVisibility.answer(in: text, forSection: sectionNumber) != .hidden {
                return false
            }
        }
        return true
    }

    /// Whether a name is taken in this folder, asked of the file system
    /// rather than of an index — used only to tell a late collision from a
    /// real failure.
    static func alreadyThere(at folderURL: URL, named name: ExactName) -> Bool {
        let url: URL = ReferenceTreeCopier.url(named: name.bytes, inFolderAt: folderURL)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
