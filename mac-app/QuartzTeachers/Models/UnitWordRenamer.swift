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
///   part way is finished by running it again with the same word.
/// * **A record is written before the first page moves and cleared after the
///   configuration is written**, so an interrupted rename is recognised the
///   next time the sheet opens rather than guessed at — and believed only
///   when the disk agrees.
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
///
/// **The walking and moving run off the main actor**, like the folder
/// rename beside it: a course's pages are read three times over (the plan,
/// the pre-read, the links), and on an iCloud-backed vault an evicted page
/// downloads on read. Everything here therefore works from
/// `UnitWordRenameCourseFacts` — the five things it needs to know about a
/// course, copied out on the main actor — rather than from the course
/// itself. Only the backup (a subprocess) and the configuration write (the
/// observable model) stay on the main actor, and `rename(_:in:coursesDirectoryURL:)`
/// strings the pieces together for callers that do not care.
nonisolated enum UnitWordRenamer {

    // MARK: - Functions

    /// Why this word cannot replace the current one, or nil when it can.
    /// Pure, so the rules can be tested without a course on disk.
    ///
    /// A change of capitalisation alone IS a rename here — "unit" to "Unit"
    /// changes what every new class page is called — so only the identical
    /// word is refused as unchanged. The move that carries it out is safe on a
    /// case-insensitive volume because it is a move, not a copy and delete.
    ///
    /// `interruptedTarget` is the word a stopped rename was heading for. While
    /// one is under way, only THAT word is accepted: any other would plan from
    /// the old word alone, leave the pages already moved matching neither, and
    /// end with three words in one course.
    static func problem(renaming oldWord: String, to rawNewWord: String, interruptedTarget: String? = nil) -> String? {
        let newWord: String = rawNewWord.trimmingCharacters(in: .whitespaces)
        if let interruptedTarget {
            if newWord == interruptedTarget {
                return nil
            }
            return UnitWordRenameWording.problemMustFinishFirst(target: interruptedTarget)
        }
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
        facts: UnitWordRenameCourseFacts
    ) -> UnitWordRenamePlan {
        let newWord: String = ClassPageTerm.cleaned(rawNewWord)
        let fileManager: FileManager = FileManager.default
        var renames: [UnitWordPageRename] = []
        var linkMap: [String: String] = [:]
        var problems: [String] = []
        var sectionsTouched: [Int] = []

        for page in classFolderPages(facts: facts) {
            if let numbers = UnitDay(pageTitle: page.title, term: oldWord) {
                let newTitle: String = UnitDay(unit: numbers.unit, day: numbers.day, term: newWord).title
                linkMap[page.title] = newTitle
                if newTitle == page.title {
                    // Already exactly what it should be — a change of
                    // capitalisation being finished after a stop. Nothing to
                    // move; the old-word links above still need following.
                    continue
                }
                let toURL: URL = page.fileURL.deletingLastPathComponent()
                    .appendingPathComponent(newTitle + ".md")
                // Something else already there refuses everything. On a
                // case-insensitive volume a destination differing from its
                // source only in case "exists" because it IS the source, so
                // the filesystem is asked whether the two are one file rather
                // than whether the names match.
                if fileManager.fileExists(atPath: toURL.path) && !isTheSameFile(page.fileURL, toURL) {
                    problems.append(UnitWordRenameWording.problemPageInTheWay(
                        courseCode: facts.code, sectionNumber: page.sectionNumber, name: newTitle
                    ))
                }
                renames.append(UnitWordPageRename(
                    sectionNumber: page.sectionNumber,
                    from: page.title, to: newTitle,
                    fromURL: page.fileURL, toURL: toURL
                ))
                if !sectionsTouched.contains(page.sectionNumber) {
                    sectionsTouched.append(page.sectionNumber)
                }
            } else if let numbers = UnitDay(pageTitle: page.title, term: newWord) {
                // Already under the new word — a rename that stopped part
                // way. Links to its OLD name still need following.
                let oldTitle: String = UnitDay(unit: numbers.unit, day: numbers.day, term: oldWord).title
                linkMap[oldTitle] = page.title
            }
        }
        sectionsTouched.sort()

        if !problems.isEmpty {
            renames = []
            sectionsTouched = []
        }
        return UnitWordRenamePlan(
            courseCode: facts.code,
            from: oldWord,
            to: newWord,
            renames: renames,
            linkMap: linkMap,
            linksToRewrite: countLinks(to: linkMap, facts: facts),
            sectionsTouched: sectionsTouched,
            problems: problems
        )
    }

    /// What the sheet shows before a word has been typed: the pages that
    /// carry the current word, by section, and the links that point at them.
    /// The same walk the plan makes, without a destination to check.
    static func survey(facts: UnitWordRenameCourseFacts) -> UnitWordSurvey {
        var pages: Int = 0
        var sections: [Int] = []
        var names: [String: String] = [:]
        for page in classFolderPages(facts: facts) {
            if UnitDay(pageTitle: page.title, term: facts.currentWord) == nil {
                continue
            }
            pages += 1
            names[page.title] = page.title
            if !sections.contains(page.sectionNumber) {
                sections.append(page.sectionNumber)
            }
        }
        sections.sort()
        return UnitWordSurvey(pages: pages, sections: sections, links: countLinks(to: names, facts: facts))
    }

    /// Every page's text, read before anything moves. Forces an iCloud
    /// download while nothing has changed, and turns an unreadable page into
    /// a refusal rather than a gap.
    static func readEveryPage(of plan: UnitWordRenamePlan) throws -> [String] {
        var texts: [String] = []
        for rename in plan.renames {
            guard let text = try? String(contentsOf: rename.fromURL, encoding: .utf8) else {
                throw UnitWordRenameProblem(
                    sentence: UnitWordRenameWording.problemPageUnreadable(
                        courseCode: plan.courseCode, sectionNumber: rename.sectionNumber, name: rename.from
                    ),
                    pagesRenamed: 0, linksRewritten: 0, changedTheCourse: false
                )
            }
            texts.append(text)
        }
        return texts
    }

    /// The work itself, after the pages have been read and the backup made:
    /// the record, then every page retitled and moved, then the links.
    ///
    /// Throws `UnitWordRenameProblem`, whose sentence says how far it got and
    /// whose `changedTheCourse` says whether anything on disk is different.
    static func carryOut(
        _ plan: UnitWordRenamePlan,
        texts: [String],
        facts: UnitWordRenameCourseFacts,
        backupURL: URL
    ) throws -> UnitWordRenameOutcome {
        if let problem = plan.problems.first {
            throw UnitWordRenameProblem(sentence: problem, pagesRenamed: 0, linksRewritten: 0, changedTheCourse: false)
        }
        let fileManager: FileManager = FileManager.default

        // The record that a rename is under way. Its failure is a refusal —
        // the backup already exists, so refusing here costs nothing, and a
        // rename with no record is one that cannot be recognised if it stops.
        do {
            try recordRenameStarting(from: plan.from, to: plan.to, courseDirectory: facts.directoryURL)
        } catch {
            throw UnitWordRenameProblem(
                sentence: UnitWordRenameWording.halfDone(
                    renamed: 0, of: plan.renames.count,
                    stoppedAt: plan.renames.first?.from ?? plan.from, reason: error.localizedDescription
                ),
                pagesRenamed: 0, linksRewritten: 0, changedTheCourse: false
            )
        }

        // Retitle in place, then MOVE. A page under its old name whose title
        // already says the new one is harmless — every reader goes by the
        // file name — so an interruption between the two leaves nothing that
        // a second run cannot finish.
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
                    pagesRenamed: pagesRenamed, linksRewritten: 0, changedTheCourse: true
                )
            }
        }

        // The links. Ours to do — Obsidian only rewrites links when Obsidian
        // performs the rename. Every page of the course, shared ones
        // included: a section's index or a shared overview may link at a
        // class page.
        var linksRewritten: Int = 0
        var pagesNotWritten: Int = 0
        if !plan.linkMap.isEmpty {
            var oldNames: [String] = []
            for (oldName, _) in plan.linkMap {
                oldNames.append(oldName)
            }
            for pageURL in SpecialFolderRenamer.markdownPages(in: facts.directoryURL) {
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
                    // links broken than carrying on does. Counted, and said.
                    pagesNotWritten += 1
                    continue
                }
            }
        }

        return UnitWordRenameOutcome(
            pagesRenamed: pagesRenamed,
            linksRewritten: linksRewritten,
            pagesNotWritten: pagesNotWritten,
            sectionsTouched: plan.sectionsTouched,
            backupURL: backupURL
        )
    }

    /// Writes the new word into `course_config.json` and clears the record.
    /// Last, on purpose: if the moves fail nothing has been written, and the
    /// course is exactly as it was.
    @MainActor
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
                pagesRenamed: plan.renames.count, linksRewritten: plan.linksToRewrite, changedTheCourse: true
            )
        }
        clearRenameRecord(courseDirectory: course.directoryURL)
    }

    // MARK: - The whole thing, on the main actor

    /// The facts the walk needs, copied out of the course on the main actor
    /// so the walk can leave it.
    @MainActor
    static func facts(for course: Course) -> UnitWordRenameCourseFacts {
        return UnitWordRenameCourseFacts(
            code: course.code,
            directoryURL: course.directoryURL,
            sectionNumbers: course.sectionNumbers,
            classFolderNames: ClassFolder.names(for: course),
            currentWord: course.configuration.unitWord
        )
    }

    @MainActor
    static func plan(from oldWord: String, to rawNewWord: String, in course: Course) -> UnitWordRenamePlan {
        return plan(from: oldWord, to: rawNewWord, facts: facts(for: course))
    }

    /// Read, back up, carry out — in that order, all on the caller's actor.
    /// The sheet does the same three steps itself so the walks can leave the
    /// main actor; this is for tests and for callers that do not mind.
    @MainActor
    @discardableResult
    static func rename(
        _ plan: UnitWordRenamePlan,
        in course: Course,
        coursesDirectoryURL: URL
    ) throws -> UnitWordRenameOutcome {
        let texts: [String] = try readEveryPage(of: plan)
        if let problem = plan.problems.first {
            throw UnitWordRenameProblem(sentence: problem, pagesRenamed: 0, linksRewritten: 0, changedTheCourse: false)
        }
        let backupURL: URL = try CourseArchiver.backUpCourse(course, coursesDirectoryURL: coursesDirectoryURL)
        return try carryOut(plan, texts: texts, facts: facts(for: course), backupURL: backupURL)
    }

    @MainActor
    static func interruptedRenameTarget(in course: Course) -> String? {
        return interruptedRenameTarget(facts: facts(for: course))
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

    static func recordRenameStarting(from oldWord: String, to newWord: String, courseDirectory: URL) throws {
        let marker: URL = renameMarkerURL(courseDirectory: courseDirectory)
        let note: [String: String] = ["from": oldWord, "to": newWord]
        try FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data: Data = try JSONSerialization.data(withJSONObject: note, options: [.prettyPrinted])
        try data.write(to: marker, options: [.atomic])
    }

    static func clearRenameRecord(courseDirectory: URL) {
        try? FileManager.default.removeItem(at: renameMarkerURL(courseDirectory: courseDirectory))
    }

    /// The word a rename was heading for when it stopped, or nil.
    ///
    /// Asked when the sheet opens. The record has to agree with BOTH the
    /// configuration and the disk. A record whose `from` is no longer the
    /// course's word is stale — the configuration was written and only the
    /// clearing failed, or the word was edited by hand. A record with no
    /// class page under its `to` describes a rename that moved nothing — or
    /// one a restored backup has undone — and "some class pages have the new
    /// word" would be false. Either is cleared rather than believed, so it
    /// cannot live forever and cannot prefill a word from another day.
    static func interruptedRenameTarget(facts: UnitWordRenameCourseFacts) -> String? {
        let marker: URL = renameMarkerURL(courseDirectory: facts.directoryURL)
        guard let data = try? Data(contentsOf: marker),
              let note = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let from = note["from"],
              let to = note["to"] else {
            return nil
        }
        if from != facts.currentWord || to.isEmpty || to == from {
            clearRenameRecord(courseDirectory: facts.directoryURL)
            return nil
        }
        var somethingMoved: Bool = false
        for page in classFolderPages(facts: facts) {
            // A page that parses with the NEW word and not as itself under the
            // old — for a change of capitalisation the two coincide, and the
            // file name is the tell.
            if UnitDay(pageTitle: page.title, term: to) != nil && !page.title.hasPrefix(from) {
                somethingMoved = true
                break
            }
        }
        if !somethingMoved {
            clearRenameRecord(courseDirectory: facts.directoryURL)
            return nil
        }
        return to
    }

    // MARK: - Private helpers

    /// Every page in every class folder of every section, `index.md` aside —
    /// the raw files, NOT `ClassPages.list`, which parses with the course's
    /// configured word and so, mid-rename, cannot see the pages already moved.
    private static func classFolderPages(facts: UnitWordRenameCourseFacts) -> [ClassFolderPage] {
        var pages: [ClassFolderPage] = []
        for sectionNumber in facts.sectionNumbers {
            for folderName in facts.classFolderNames {
                let folderURL: URL = facts.directoryURL
                    .appendingPathComponent("section\(sectionNumber)")
                    .appendingPathComponent(folderName)
                for pageURL in ClassPages.markdownPages(under: folderURL) {
                    if pageURL.lastPathComponent.lowercased() == "index.md" {
                        continue
                    }
                    pages.append(ClassFolderPage(
                        sectionNumber: sectionNumber,
                        title: pageURL.deletingPathExtension().lastPathComponent,
                        fileURL: pageURL
                    ))
                }
            }
        }
        return pages
    }

    /// How many links across the whole course point at any key of the map.
    private static func countLinks(to linkMap: [String: String], facts: UnitWordRenameCourseFacts) -> Int {
        if linkMap.isEmpty {
            return 0
        }
        var oldNames: [String] = []
        for (oldName, _) in linkMap {
            oldNames.append(oldName)
        }
        var total: Int = 0
        for pageURL in SpecialFolderRenamer.markdownPages(in: facts.directoryURL) {
            guard let text = try? String(contentsOf: pageURL, encoding: .utf8) else {
                continue
            }
            total += WikiLinkRewriter.countLinks(to: oldNames, in: text)
        }
        return total
    }

    /// Whether two paths name one file — by the filesystem's own identity,
    /// not by spelling, so a case-insensitive volume answers yes to "Unit 1,
    /// Day 1.md" and "unit 1, Day 1.md", and a case-sensitive one answers no.
    private static func isTheSameFile(_ first: URL, _ second: URL) -> Bool {
        let fileManager: FileManager = FileManager.default
        guard let firstAttributes = try? fileManager.attributesOfItem(atPath: first.path),
              let secondAttributes = try? fileManager.attributesOfItem(atPath: second.path),
              let firstNumber = firstAttributes[.systemFileNumber] as? Int,
              let secondNumber = secondAttributes[.systemFileNumber] as? Int,
              let firstDevice = firstAttributes[.systemNumber] as? Int,
              let secondDevice = secondAttributes[.systemNumber] as? Int else {
            return false
        }
        return firstNumber == secondNumber && firstDevice == secondDevice
    }
}

/// One page in a class folder, as the walk finds it.
private nonisolated struct ClassFolderPage {

    // MARK: - Stored properties

    let sectionNumber: Int
    let title: String
    let fileURL: URL

    // MARK: - Initializer

    init(sectionNumber: Int, title: String, fileURL: URL) {
        self.sectionNumber = sectionNumber
        self.title = title
        self.fileURL = fileURL
    }
}

/// What the walk needs to know about a course — copied out on the main
/// actor, so the walk can leave it.
nonisolated struct UnitWordRenameCourseFacts: Sendable {

    // MARK: - Stored properties

    let code: String
    let directoryURL: URL
    let sectionNumbers: [Int]
    let classFolderNames: [String]
    let currentWord: String

    // MARK: - Initializer

    init(code: String, directoryURL: URL, sectionNumbers: [Int], classFolderNames: [String], currentWord: String) {
        self.code = code
        self.directoryURL = directoryURL
        self.sectionNumbers = sectionNumbers
        self.classFolderNames = classFolderNames
        self.currentWord = currentWord
    }
}

/// What the sheet shows before a word is typed.
nonisolated struct UnitWordSurvey: Sendable {

    // MARK: - Stored properties

    let pages: Int
    let sections: [Int]
    let links: Int

    // MARK: - Initializer

    init(pages: Int, sections: [Int], links: Int) {
        self.pages = pages
        self.sections = sections
        self.links = links
    }
}

/// One class page that changes name, and the file it becomes.
nonisolated struct UnitWordPageRename: Sendable {

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
nonisolated struct UnitWordRenamePlan: Sendable {

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
nonisolated struct UnitWordRenameOutcome: Sendable {

    // MARK: - Stored properties

    let pagesRenamed: Int
    let linksRewritten: Int

    /// Pages whose links could not be followed because the page could not be
    /// written back. Zero in the ordinary case.
    let pagesNotWritten: Int

    let sectionsTouched: [Int]
    let backupURL: URL

    // MARK: - Initializer

    init(pagesRenamed: Int, linksRewritten: Int, pagesNotWritten: Int = 0, sectionsTouched: [Int], backupURL: URL) {
        self.pagesRenamed = pagesRenamed
        self.linksRewritten = linksRewritten
        self.pagesNotWritten = pagesNotWritten
        self.sectionsTouched = sectionsTouched
        self.backupURL = backupURL
    }
}

/// Something that stopped a rename, with how far it had got — because a
/// rename that stopped after forty pages is a different situation from one
/// that never started, and the teacher is told which.
nonisolated struct UnitWordRenameProblem: LocalizedError, Sendable {

    // MARK: - Stored properties

    let sentence: String
    let pagesRenamed: Int
    let linksRewritten: Int

    /// Whether anything on disk is different from before — the record, a
    /// retitled page, a moved one. The trail line is owed whenever it is,
    /// which is not the same as whether a page was counted as renamed: the
    /// first page can be retitled and then fail to move.
    let changedTheCourse: Bool

    // MARK: - Computed properties

    var errorDescription: String? {
        return sentence
    }

    // MARK: - Initializer

    init(sentence: String, pagesRenamed: Int, linksRewritten: Int, changedTheCourse: Bool) {
        self.sentence = sentence
        self.pagesRenamed = pagesRenamed
        self.linksRewritten = linksRewritten
        self.changedTheCourse = changedTheCourse
    }
}
