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

    /// Whether the WEBSITE BUILDER would read this page's settings block the
    /// same way this app does.
    ///
    /// **The read-back asks the app's own reader, and the app's own reader is
    /// not the one that decides what students see.** Two shapes were
    /// reproduced end to end where the two split, and both end with the copy
    /// certified hidden here and PUBLISHED there:
    ///
    /// * a block closed by an INDENTED `---`. This app trims leading spaces
    ///   before testing a fence; python-frontmatter's boundary is
    ///   `^-{3,}\s*$`, which does not — so it never finds the end, reads no
    ///   settings at all, and Quartz publishes a page that says nothing.
    ///   (The divergence itself is issue #188; this is the one place where it
    ///   costs the most.)
    /// * a block carrying a YAML ANCHOR or ALIAS. Taking the plain `publish:`
    ///   line out can orphan an alias the rest of the block refers to;
    ///   `frontmatter.load` then RAISES, `build_site.py` prints a warning and
    ///   RETURNS, and the page reaches Quartz unresolved.
    ///
    /// Measured incidence across 777 real pages in four courses: **zero**, of
    /// either shape. Refused anyway — the promise this feature makes is
    /// certainty, and a refusal here is always right.
    ///
    /// The test is deliberately crude and deliberately STRICT: the first line
    /// must open a block with no indentation, a later line at column 0 must
    /// close it, the plain `publish: false` this code wrote must be inside
    /// it, and nothing in it may carry an anchor, an alias or a leading tab.
    /// Anything else is "cannot be sure".
    static func theBuilderWouldReadItTheSameWay(_ pageText: String) -> Bool {
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

        var saysHidden: Bool = false
        for index in 1..<closeIndex {
            let line: String = PageFrontmatter.trimmingCarriageReturn(lines[index])
            if line.hasPrefix("\t") {
                return false
            }
            if line.contains("&") || line.contains("*") {
                return false
            }
            var tidied: String = line
            while tidied.hasSuffix(" ") {
                tidied = String(tidied.dropLast())
            }
            if tidied == "publish: false" {
                saysHidden = true
            }
        }
        return saysHidden
    }

    /// A line the website builder would take as the edge of a settings block:
    /// three or more dashes at COLUMN 0, with nothing after them but spaces.
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
                readBack ?? ""
            )
            if !isHidden || !builderAgrees {
                // **The removal is CHECKED.** "… was not copied" is the
                // strongest promise this feature makes, and making it on an
                // unchecked `try?` would let a page nobody could prove hidden
                // sit in the teacher's course while they were told it was not
                // there. An immutable parent folder is the realistic way it
                // fails.
                do {
                    try FileManager.default.removeItem(at: writtenURL)
                    skipped.append(CopySkip(
                        name: placement.pageName,
                        reason: isHidden
                            ? .thePageIsWrittenInAWayPlantoirCannotBeSureOf
                            : .theCopyCouldNotBeMadeHidden
                    ))
                } catch {
                    stillOnDisk.append(writtenURL.path)
                    skipped.append(CopySkip(
                        name: placement.pageName,
                        reason: .theCopyIsStillThereAndMustBeRemoved
                    ))
                }
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
