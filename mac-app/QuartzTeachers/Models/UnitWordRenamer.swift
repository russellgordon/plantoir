import Foundation

/// Renaming a course's word for a unit — "Unit" to "Module", say — after the
/// course is already in use.
///
/// The word is chosen when a course is made and the ready-made pages are
/// poured in it (`ClassPageTerm`, `scripts/class_pages.py`). Changing it
/// later means every class page's name, its frontmatter title and every
/// wikilink pointing at it, across every section and every shared folder —
/// which is `ClassInsertionPlanner`'s rename widened from one section to a
/// course, and the part that made it wait was not the count (a course holds
/// under a hundred class pages) but the lack of a way back. So:
///
/// * **The plan says what would happen before anything does**, and refuses
///   outright when a page already sits where a renamed page would go — the
///   alternative, skipping it, leaves two numbering schemes in one section.
/// * **Every page is read before any is touched.** A page that cannot be read
///   (an iCloud-evicted file, say) refuses the whole rename rather than being
///   skipped: the configuration would otherwise say "Module" while that page
///   still said "Unit", recognised by nothing — the exact silent failure
///   `unit_word` exists to prevent.
/// * **A page is retitled in place and then MOVED**, never copied and deleted,
///   so there is no moment with two copies or none, and a rename that stops
///   part way is finished by running it again: pages already moved are simply
///   not matched by the old word.
/// * **A record is written before the first page moves and cleared after the
///   configuration is written**, so an interrupted rename is recognised the
///   next time the sheet opens rather than guessed at.
/// * **The undo is renaming it back** — the operation is its own inverse — and
///   a backup of the whole course is saved first as the last resort. Restoring
///   that backup replaces every page, edits since included, which is why the
///   backup is the last resort and not the undo.
///
/// The word never touches a teacher's prose: "by the end of Unit 3" in a page
/// body, or a task called "Unit 2 Test", keeps its word — the 2026-09-01
/// decision that the rewrite runs only over content Plantoir ships. The
/// sentences are `UnitWordRenameWording`; the cases both suites run are in
/// `contracts/class-planning.json` → `renamingTheUnitWord`.
enum UnitWordRenamer {

    // MARK: - Functions

    /// Why this word cannot replace the current one, or nil when it can.
    /// Pure, so the rules can be tested without a course on disk.
    ///
    /// A change of capitalisation alone IS a rename here — "unit" to "Unit"
    /// changes what every new class page is called — so only the identical
    /// word is refused as unchanged. The move that carries it out is safe on a
    /// case-insensitive volume because it is a move, not a copy and delete.
    static func problem(renaming oldWord: String, to rawNewWord: String) -> String? {
        let newWord: String = rawNewWord.trimmingCharacters(in: .whitespaces)
        if newWord.isEmpty {
            return UnitWordRenameWording.problemEmpty
        }
        if newWord == oldWord {
            return UnitWordRenameWording.problemUnchanged
        }
        return ClassPageTerm.problem(with: newWord)
    }

    /// What renaming would do. Changes nothing.
    static func plan(
        from oldWord: String,
        to rawNewWord: String,
        in course: Course
    ) -> UnitWordRenamePlan {
        let newWord: String = ClassPageTerm.cleaned(rawNewWord)
        let fileManager: FileManager = FileManager.default
        var renames: [UnitWordPageRename] = []
        var linkMap: [String: String] = [:]
        var problems: [String] = []

        // The raw files, parsed with each word in turn — NOT `ClassPages.list`,
        // which parses with the course's configured word and so, mid-rename,
        // cannot see the pages that have already moved.
        for sectionNumber in course.sectionNumbers {
            for folderName in ClassFolder.names(for: course) {
                let folderURL: URL = course.sectionDirectoryURL(forSection: sectionNumber)
                    .appendingPathComponent(folderName)
                for pageURL in ClassPages.markdownPages(under: folderURL) {
                    if pageURL.lastPathComponent.lowercased() == "index.md" {
                        continue
                    }
                    let title: String = pageURL.deletingPathExtension().lastPathComponent
                    if let numbers = UnitDay(pageTitle: title, term: oldWord) {
                        let newTitle: String = UnitDay(unit: numbers.unit, day: numbers.day, term: newWord).title
                        let toURL: URL = pageURL.deletingLastPathComponent()
                            .appendingPathComponent(newTitle + ".md")
                        // Something else already there refuses everything. A
                        // destination that differs from the source only in
                        // capitalisation "exists" on a case-insensitive volume
                        // because it IS the source, and that is not a clash.
                        let isTheSameFile: Bool = pageURL.lastPathComponent
                            .caseInsensitiveCompare(toURL.lastPathComponent) == .orderedSame
                        if !isTheSameFile && fileManager.fileExists(atPath: toURL.path) {
                            problems.append(UnitWordRenameWording.problemPageInTheWay(
                                courseCode: course.code, sectionNumber: sectionNumber, name: newTitle
                            ))
                        }
                        renames.append(UnitWordPageRename(
                            sectionNumber: sectionNumber,
                            from: title, to: newTitle,
                            fromURL: pageURL, toURL: toURL
                        ))
                        linkMap[title] = newTitle
                    } else if let numbers = UnitDay(pageTitle: title, term: newWord) {
                        // Already under the new word — a rename that stopped
                        // part way. Links to its OLD name still need following.
                        let oldTitle: String = UnitDay(unit: numbers.unit, day: numbers.day, term: oldWord).title
                        linkMap[oldTitle] = title
                    }
                }
            }
        }

        var sectionsTouched: [Int] = []
        for rename in renames {
            if !sectionsTouched.contains(rename.sectionNumber) {
                sectionsTouched.append(rename.sectionNumber)
            }
        }
        sectionsTouched.sort()

        var oldNames: [String] = []
        for (oldName, _) in linkMap {
            oldNames.append(oldName)
        }
        var linksToRewrite: Int = 0
        for pageURL in SpecialFolderRenamer.markdownPages(in: course.directoryURL) {
            guard let text = try? String(contentsOf: pageURL, encoding: .utf8) else {
                continue
            }
            linksToRewrite += WikiLinkRewriter.countLinks(to: oldNames, in: text)
        }

        if !problems.isEmpty {
            renames = []
        }
        return UnitWordRenamePlan(
            courseCode: course.code,
            from: oldWord,
            to: newWord,
            renames: renames,
            linkMap: linkMap,
            linksToRewrite: linksToRewrite,
            sectionsTouched: sectionsTouched,
            problems: problems
        )
    }

    /// Carries the plan out on disk: backup, record, retitle and move every
    /// page, follow the links. The configuration is NOT written here — see
    /// `record(_:in:)`, which the caller runs on the main actor afterwards,
    /// because it touches the observable model.
    ///
    /// Throws `UnitWordRenameProblem`, whose sentence says how far it got.
    static func rename(
        _ plan: UnitWordRenamePlan,
        in course: Course,
        coursesDirectoryURL: URL
    ) throws -> UnitWordRenameOutcome {
        if let problem = plan.problems.first {
            throw UnitWordRenameProblem(sentence: problem, pagesRenamed: 0, linksRewritten: 0)
        }
        let fileManager: FileManager = FileManager.default

        // 1. Read every page BEFORE anything moves. Forces an iCloud download
        //    while nothing has changed, and turns an unreadable page into a
        //    refusal rather than a gap.
        var texts: [String] = []
        for rename in plan.renames {
            guard let text = try? String(contentsOf: rename.fromURL, encoding: .utf8) else {
                throw UnitWordRenameProblem(
                    sentence: UnitWordRenameWording.problemPageUnreadable(
                        courseCode: course.code, sectionNumber: rename.sectionNumber, name: rename.from
                    ),
                    pagesRenamed: 0, linksRewritten: 0
                )
            }
            texts.append(text)
        }

        // 2. The way back, before the first change.
        let backupURL: URL = try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL)

        // 3. The record that a rename is under way.
        recordRenameStarting(from: plan.from, to: plan.to, courseDirectory: course.directoryURL)

        // 4. Retitle in place, then MOVE. A page under its old name whose
        //    title already says the new one is harmless — every reader goes by
        //    the file name — so an interruption between the two leaves nothing
        //    that a second run cannot finish.
        var pagesRenamed: Int = 0
        for index in 0..<plan.renames.count {
            let rename: UnitWordPageRename = plan.renames[index]
            do {
                let retitled: String = PageFrontmatter.settingTitle(in: texts[index], to: rename.to)
                if retitled != texts[index] {
                    try retitled.write(to: rename.fromURL, atomically: true, encoding: .utf8)
                }
                try fileManager.moveItem(at: rename.fromURL, to: rename.toURL)
                pagesRenamed += 1
            } catch {
                throw UnitWordRenameProblem(
                    sentence: UnitWordRenameWording.halfDone(
                        renamed: pagesRenamed, of: plan.renames.count,
                        stoppedAt: rename.from, reason: error.localizedDescription
                    ),
                    pagesRenamed: pagesRenamed, linksRewritten: 0
                )
            }
        }

        // 5. The links. Ours to do — Obsidian only rewrites links when Obsidian
        //    performs the rename. Every page of the course, shared ones
        //    included: a section's index or a shared overview may link at a
        //    class page.
        var linksRewritten: Int = 0
        if !plan.linkMap.isEmpty {
            var oldNames: [String] = []
            for (oldName, _) in plan.linkMap {
                oldNames.append(oldName)
            }
            for pageURL in SpecialFolderRenamer.markdownPages(in: course.directoryURL) {
                guard let text = try? String(contentsOf: pageURL, encoding: .utf8) else {
                    continue
                }
                let here: Int = WikiLinkRewriter.countLinks(to: oldNames, in: text)
                if here == 0 {
                    continue
                }
                let updated: String = WikiLinkRewriter.rewriting(text, renamedPages: plan.linkMap)
                if updated == text {
                    continue
                }
                do {
                    try updated.write(to: pageURL, atomically: true, encoding: .utf8)
                    linksRewritten += here
                } catch {
                    // One unwritable page must not abandon the rest: the pages
                    // have already moved, so stopping here would leave MORE
                    // links broken than carrying on does.
                    continue
                }
            }
        }

        return UnitWordRenameOutcome(
            pagesRenamed: pagesRenamed,
            linksRewritten: linksRewritten,
            sectionsTouched: plan.sectionsTouched,
            backupURL: backupURL
        )
    }

    /// Writes the new word into `course_config.json` and clears the record.
    /// Last, on purpose: if the moves fail nothing has been written, and the
    /// course is exactly as it was.
    static func record(_ plan: UnitWordRenamePlan, in course: Course) throws {
        do {
            try course.configuration.recordOnDisk({ values in
                var updated: [String: Any] = values
                updated["unit_word"] = plan.to
                return updated
            }, at: course.configFileURL)
        } catch {
            throw UnitWordRenameProblem(
                sentence: UnitWordRenameWording.settingsNotWritten(
                    new: plan.to, reason: error.localizedDescription
                ),
                pagesRenamed: plan.renames.count, linksRewritten: plan.linksToRewrite
            )
        }
        clearRenameRecord(courseDirectory: course.directoryURL)
    }

    // MARK: - The record of a rename under way

    /// Where a rename records that it has started. Beside the folder
    /// renames' records under `courses/.internal/renames/`, with its own
    /// suffix so the two kinds never read each other.
    static func renameMarkerURL(courseDirectory: URL) -> URL {
        return courseDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(".internal")
            .appendingPathComponent("renames")
            .appendingPathComponent(courseDirectory.lastPathComponent + ".unit-word.json")
    }

    static func recordRenameStarting(from oldWord: String, to newWord: String, courseDirectory: URL) {
        let marker: URL = renameMarkerURL(courseDirectory: courseDirectory)
        let note: [String: String] = ["from": oldWord, "to": newWord]
        try? FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? JSONSerialization.data(withJSONObject: note, options: [.prettyPrinted]) {
            try? data.write(to: marker, options: [.atomic])
        }
    }

    static func clearRenameRecord(courseDirectory: URL) {
        try? FileManager.default.removeItem(at: renameMarkerURL(courseDirectory: courseDirectory))
    }

    /// The word a rename was heading for when it stopped, or nil.
    ///
    /// Asked when the sheet opens. The record has to agree with the
    /// configuration: a record whose `from` is no longer the course's word is
    /// stale — the configuration was written and only the clearing failed, or
    /// somebody edited the word by hand — and is cleared rather than believed,
    /// so it cannot live forever and cannot prefill a word from another day.
    static func interruptedRenameTarget(in course: Course) -> String? {
        let marker: URL = renameMarkerURL(courseDirectory: course.directoryURL)
        guard let data = try? Data(contentsOf: marker),
              let note = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let from = note["from"],
              let to = note["to"] else {
            return nil
        }
        if from != course.configuration.unitWord || to.isEmpty {
            clearRenameRecord(courseDirectory: course.directoryURL)
            return nil
        }
        return to
    }
}

/// One class page that changes name, and the file it becomes.
struct UnitWordPageRename {

    // MARK: - Stored properties

    let sectionNumber: Int
    let from: String
    let to: String
    let fromURL: URL
    let toURL: URL

    // MARK: - Initializer

    init(sectionNumber: Int, from: String, to: String, fromURL: URL, toURL: URL) {
        self.sectionNumber = sectionNumber
        self.from = from
        self.to = to
        self.fromURL = fromURL
        self.toURL = toURL
    }
}

/// What renaming the word would do. Nothing here has happened yet.
struct UnitWordRenamePlan {

    // MARK: - Stored properties

    let courseCode: String
    let from: String
    let to: String

    /// The pages that would be renamed. EMPTY when the plan is refused, so a
    /// refused plan can never be carried out by accident.
    let renames: [UnitWordPageRename]

    /// Old page name to new, for every page being renamed AND every page a
    /// stopped rename already moved — so links to either are followed.
    let linkMap: [String: String]

    let linksToRewrite: Int
    let sectionsTouched: [Int]

    /// Anything that REFUSES the rename. Empty means it can go ahead.
    let problems: [String]

    // MARK: - Computed properties

    var canProceed: Bool {
        return problems.isEmpty
    }

    /// The proposal, as a teacher would hear it.
    var previewLines: [String] {
        var lines: [String] = [
            UnitWordRenameWording.previewPages(
                courseCode: courseCode, pages: renames.count, sections: sectionsTouched, old: from, new: to
            ),
        ]
        if !renames.isEmpty {
            lines.append(UnitWordRenameWording.previewLinks(count: linksToRewrite))
        }
        return lines
    }

    // MARK: - Initializer

    init(
        courseCode: String,
        from: String,
        to: String,
        renames: [UnitWordPageRename],
        linkMap: [String: String],
        linksToRewrite: Int,
        sectionsTouched: [Int],
        problems: [String]
    ) {
        self.courseCode = courseCode
        self.from = from
        self.to = to
        self.renames = renames
        self.linkMap = linkMap
        self.linksToRewrite = linksToRewrite
        self.sectionsTouched = sectionsTouched
        self.problems = problems
    }
}

/// What a rename actually did on disk.
struct UnitWordRenameOutcome {

    // MARK: - Stored properties

    let pagesRenamed: Int
    let linksRewritten: Int
    let sectionsTouched: [Int]
    let backupURL: URL

    // MARK: - Initializer

    init(pagesRenamed: Int, linksRewritten: Int, sectionsTouched: [Int], backupURL: URL) {
        self.pagesRenamed = pagesRenamed
        self.linksRewritten = linksRewritten
        self.sectionsTouched = sectionsTouched
        self.backupURL = backupURL
    }
}

/// Something that stopped a rename, with how far it had got — because a
/// rename that stopped after forty pages is a different situation from one
/// that never started, and the teacher is told which.
struct UnitWordRenameProblem: LocalizedError {

    // MARK: - Stored properties

    let sentence: String
    let pagesRenamed: Int
    let linksRewritten: Int

    // MARK: - Computed properties

    var errorDescription: String? {
        return sentence
    }

    // MARK: - Initializer

    init(sentence: String, pagesRenamed: Int, linksRewritten: Int) {
        self.sentence = sentence
        self.pagesRenamed = pagesRenamed
        self.linksRewritten = linksRewritten
    }
}
