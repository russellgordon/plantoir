import Foundation

/// A folder of last year's courses, as Plantoir reads it before importing
/// anything out of it.
///
/// This half never writes: it decides whether the folder a teacher chose
/// holds courses at all, finds them, and measures each one so the sheet can
/// say how big the copy will be and which school year it probably was. The
/// copying is `ReferenceTreeCopier`; the making-into-a-reference-course is
/// `ReferenceCopier`.
///
/// **Everything here is `nonisolated`** because the measuring walks the whole
/// tree — 943 files on the real ICS4U — and that runs off the main actor so
/// the window stays alive while it happens.
nonisolated struct ReferenceImportSource: Sendable {

    // MARK: - Types

    /// One course found in the chosen folder.
    struct FoundCourse: Identifiable, Sendable, Equatable {

        // MARK: - Stored properties

        /// The folder it lives in over there — `ICS4U`.
        let folderName: String

        /// The code a teacher reads, from its own settings. Falls back to the
        /// folder name, the same way `Course.displayCode` does, because a row
        /// labelled with nothing is worse than one labelled with the folder.
        let courseCode: String

        /// What the teacher called it — "Computer Science, Grade 12".
        let courseName: String

        /// Every section it has. All of them come across; there is no
        /// choosing among them.
        let sectionNumbers: [Int]

        /// How many pages a teacher wrote.
        let pageCount: Int

        /// How many files will be copied, and how many bytes they are —
        /// **without last year's built website**, which is left behind and is
        /// four fifths of what is on disk.
        let fileCount: Int
        let byteCount: Int64

        /// What was left behind, by name, so the summary can say so
        /// honestly. Counted rather than sized on purpose: measuring
        /// `.merged_output` means walking the 1.9 GB of last year's built
        /// website that the whole point is to not touch.
        let leftBehind: [String]

        /// The school year this course most plausibly was, or nil when the
        /// dates do not say. A PROPOSAL: the teacher changes it in the sheet,
        /// and nothing anywhere tells them how it was arrived at.
        let suggestedSchoolYear: Int?

        /// Where it is, over in the old folder. Only ever read.
        let directoryURL: URL

        // MARK: - Computed properties

        var id: String {
            return folderName
        }
    }

    /// Why a chosen folder cannot be imported from.
    ///
    /// Each one names the folder the teacher chose, because "that folder"
    /// means nothing once the chooser has closed.
    enum Refusal: Equatable, Sendable {
        case noCoursesThere(folderName: String)
        case theFolderYouHaveOpen
        case insideTheFolderYouHaveOpen(folderName: String)
        case holdsTheFolderYouHaveOpen(folderName: String)

        // MARK: - Computed properties

        var sentence: String {
            switch self {
            case .noCoursesThere(let folderName):
                return ReferenceImportWording.noCoursesThere(folder: folderName)
            case .theFolderYouHaveOpen:
                return ReferenceImportWording.thatIsTheFolderYouHaveOpen
            case .insideTheFolderYouHaveOpen(let folderName):
                return ReferenceImportWording.insideTheFolderYouHaveOpen(folder: folderName)
            case .holdsTheFolderYouHaveOpen(let folderName):
                return ReferenceImportWording.holdsTheFolderYouHaveOpen(folder: folderName)
            }
        }
    }

    /// What reading the chosen folder came to.
    enum Outcome: Sendable {
        case found(ReferenceImportSource)
        case refused(Refusal)
    }

    // MARK: - Stored properties

    /// The old working folder, however the teacher pointed at it.
    let rootURL: URL

    /// Its `courses` folder.
    let coursesURL: URL

    /// What was found in it, in the order the sheet shows them: by code.
    let courses: [FoundCourse]

    /// The one course the teacher pointed AT, when they chose a course folder
    /// rather than a working folder. Ticked on its own in that case.
    let chosenCourseFolderName: String?

    // MARK: - Computed properties

    /// Which courses are ticked when the sheet opens.
    ///
    /// **Everything, when the teacher pointed at a working folder or at its
    /// courses folder** — they pointed at last year and they mean last year.
    /// **Only the one, when they pointed at a course folder** — they were
    /// specific, and the others are offered rather than assumed.
    ///
    /// Here rather than in the sheet because it is a rule with an input and
    /// an output, which is the kind of thing a contract case can run.
    var tickedWhenOpened: Set<String> {
        if let chosenCourseFolderName {
            return [chosenCourseFolderName]
        }
        var everything: Set<String> = []
        for course in courses {
            everything.insert(course.id)
        }
        return everything
    }

    // MARK: - Stored properties (what is never copied)

    /// Names left behind on top of what an archive already leaves behind
    /// (`CourseArchiver.excludedFromArchives`, which carries `.merged_output`,
    /// `node_modules`, `.git`, the caches and `.DS_Store`) and on top of
    /// `ReferenceCopier.alsoLeftBehind` (yesterday's `course_config.backup.json`).
    ///
    /// * `course_config copy.json` — a Finder duplicate found in a real
    ///   course in the measured folder. The config is read by exact name and
    ///   never by glob, so a duplicate is not dangerous; it is simply last
    ///   year's clutter, and a reference course should not arrive with it.
    /// * `.Trashes`, `.Spotlight-V100`, `.fseventsd` — what a folder picks up
    ///   from living on an external disk, which is exactly where an old
    ///   working folder tends to be found.
    static let alsoLeftBehindOnImport: [String] = [
        "course_config copy.json",
        ".Trashes",
        ".Spotlight-V100",
        ".fseventsd",
    ]

    /// The exact name a course's settings live under. Read by name, never by
    /// glob — see `course_config copy.json` above.
    static let configFileName: String = "course_config.json"

    // MARK: - Functions

    /// What the teacher chose, resolved to an old working folder — or the
    /// reason it cannot be one.
    ///
    /// **Three shapes are accepted, because a teacher points at what they
    /// recognise rather than at what the app expects:** the working folder
    /// itself, the `courses` folder inside it, and one course folder. The
    /// last two resolve UPWARD, and the whole shelf is then offered with the
    /// one they pointed at already ticked — refusing a folder that plainly
    /// holds a course, because the teacher went one level too deep, is the
    /// kind of refusal that reads as the app being broken.
    ///
    /// `leavingBehind` is the whole skip list, passed in rather than read
    /// here so the measuring and the copying cannot disagree about it.
    /// The same, off the main actor.
    ///
    /// Reading a folder of four courses walks about 2,600 files, and a folder
    /// on a disk that has to spin up walks them slowly. `nonisolated async`
    /// is what moves the work off the interface's thread: Swift runs such a
    /// function on the shared executor rather than on the caller's actor.
    static func read(
        chosen: URL,
        workingFolderURL: URL?,
        leavingBehind leftBehindNames: Set<String>
    ) async -> Outcome {
        return ReferenceImportSource.resolve(
            chosen: chosen, workingFolderURL: workingFolderURL, leavingBehind: leftBehindNames
        )
    }

    static func resolve(
        chosen: URL,
        workingFolderURL: URL?,
        leavingBehind leftBehindNames: Set<String>
    ) -> Outcome {
        let fileManager: FileManager = FileManager.default
        let chosenURL: URL = chosen.standardizedFileURL
        let chosenName: String = chosenURL.lastPathComponent

        // The folder the teacher already has open is route 1's job, and a
        // copy of a folder into itself is a folder inside itself.
        if let workingFolderURL {
            let openURL: URL = workingFolderURL.standardizedFileURL
            if ReferenceImportSource.isTheSameFolder(chosenURL, openURL) {
                return .refused(.theFolderYouHaveOpen)
            }
            if ReferenceImportSource.folder(chosenURL, isInside: openURL) {
                return .refused(.insideTheFolderYouHaveOpen(folderName: chosenName))
            }
            if ReferenceImportSource.folder(openURL, isInside: chosenURL) {
                return .refused(.holdsTheFolderYouHaveOpen(folderName: chosenName))
            }
        }

        var coursesURL: URL?
        var chosenCourseFolderName: String?

        // A working folder: it holds `courses`.
        let coursesInside: URL = chosenURL.appendingPathComponent("courses")
        if ReferenceImportSource.isDirectory(coursesInside, fileManager: fileManager) {
            coursesURL = coursesInside
        }

        // The `courses` folder itself.
        if coursesURL == nil, chosenName == "courses" {
            coursesURL = chosenURL
        }

        // One course folder: its settings are right there.
        if coursesURL == nil {
            let config: URL = chosenURL.appendingPathComponent(ReferenceImportSource.configFileName)
            if fileManager.fileExists(atPath: config.path) {
                coursesURL = chosenURL.deletingLastPathComponent()
                chosenCourseFolderName = chosenName
            }
        }

        guard let coursesURL else {
            return .refused(.noCoursesThere(folderName: chosenName))
        }

        let courses: [FoundCourse] = ReferenceImportSource.courses(
            in: coursesURL, leavingBehind: leftBehindNames
        )
        if courses.isEmpty {
            return .refused(.noCoursesThere(folderName: chosenName))
        }

        return .found(ReferenceImportSource(
            rootURL: coursesURL.deletingLastPathComponent(),
            coursesURL: coursesURL,
            courses: courses,
            chosenCourseFolderName: chosenCourseFolderName
        ))
    }

    /// Every course in a `courses` folder, measured, sorted by the code a
    /// teacher reads.
    ///
    /// A course is a folder holding `course_config.json`, and nothing else
    /// is. That is what keeps `_backups` (zips of courses), `.internal`
    /// (the old folder's own bookkeeping) and any stray folder out without a
    /// list of names to maintain.
    static func courses(in coursesURL: URL, leavingBehind leftBehindNames: Set<String>) -> [FoundCourse] {
        let fileManager: FileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: coursesURL, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else {
            return []
        }

        var found: [FoundCourse] = []
        for child in children {
            guard ReferenceImportSource.isDirectory(child, fileManager: fileManager) else {
                continue
            }
            let configURL: URL = child.appendingPathComponent(ReferenceImportSource.configFileName)
            guard fileManager.fileExists(atPath: configURL.path) else {
                continue
            }
            if let course = ReferenceImportSource.measure(
                courseAt: child, configURL: configURL, leavingBehind: leftBehindNames
            ) {
                found.append(course)
            }
        }

        found.sort { first, second in
            if first.courseCode == second.courseCode {
                return first.folderName < second.folderName
            }
            return first.courseCode < second.courseCode
        }
        return found
    }

    // MARK: - Private helpers

    /// Reads one course's settings and walks it once, for everything the
    /// sheet has to show.
    private static func measure(
        courseAt courseURL: URL,
        configURL: URL,
        leavingBehind leftBehindNames: Set<String>
    ) -> FoundCourse? {
        guard let data = try? Data(contentsOf: configURL),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // A course whose settings cannot be read is not offered. Copying
            // it would produce a folder that becomes a reference course of
            // nothing, and the teacher can do nothing about it from here.
            return nil
        }

        var courseCode: String = ""
        if let recorded = values["course_code"] as? String {
            courseCode = recorded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if courseCode.isEmpty {
            courseCode = courseURL.lastPathComponent
        }

        var courseName: String = ""
        if let recorded = values["course_name"] as? String {
            courseName = recorded
        }

        var sectionNumbers: [Int] = []
        if let recorded = values["section_numbers"] as? [Int] {
            sectionNumbers = recorded
        }

        let walked: ReferenceTreeCopier.Survey = ReferenceTreeCopier.survey(
            courseAt: courseURL, leavingBehind: leftBehindNames
        )

        return FoundCourse(
            folderName: courseURL.lastPathComponent,
            courseCode: courseCode,
            courseName: courseName,
            sectionNumbers: sectionNumbers,
            pageCount: walked.pageCount,
            fileCount: walked.fileCount,
            byteCount: walked.byteCount,
            leftBehind: walked.leftBehind,
            suggestedSchoolYear: ReferenceImportSource.suggestedSchoolYear(
                fromPagesChangedIn: walked.pageYears
            ),
            directoryURL: courseURL
        )
    }

    /// The school year to pre-select: **the one most of the course's pages
    /// were last changed in**, ties going to the newer year.
    ///
    /// *Why the commonest year and not the newest page.* The newest page is
    /// one file, and one file is exactly what gets touched by accident —
    /// opening last year's folder to look something up, or a sync putting a
    /// fresh date on a single note. Measured on the real folder: ICS4U's
    /// newest page is dated 2026-09-11, which would propose 2026–27, while
    /// 201 of its 287 pages were last changed in 2025–26, which is the year
    /// it was taught. The commonest year gets all four of the measured
    /// courses right; the newest page gets three.
    ///
    /// A year outside the offered list — a course older than the floor, or a
    /// date from a Mac whose clock was wrong — proposes nothing, and the
    /// teacher picks. Nothing in the interface says any of this: it is a
    /// starting point, not a claim.
    static func suggestedSchoolYear(
        fromPagesChangedIn pageYears: [Int],
        on day: CalendarDay = CalendarDay.today()
    ) -> Int? {
        var countsByYear: [Int: Int] = [:]
        for year in pageYears {
            countsByYear[year] = (countsByYear[year] ?? 0) + 1
        }

        var commonest: Int?
        var commonestCount: Int = 0
        for (year, count) in countsByYear {
            if count > commonestCount {
                commonest = year
                commonestCount = count
                continue
            }
            // A tie goes to the NEWER year: a course revised across two
            // years is likelier to be the later one.
            if count == commonestCount, let soFar = commonest, year > soFar {
                commonest = year
            }
        }

        guard let commonest else {
            return nil
        }
        return SchoolYear.offeredYear(storedYear: commonest, on: day)
    }

    /// Whether two folder paths name the same folder.
    private static func isTheSameFolder(_ first: URL, _ second: URL) -> Bool {
        return ReferenceImportSource.pathWithSlash(first) == ReferenceImportSource.pathWithSlash(second)
    }

    /// Whether `inner` sits inside `outer`, at any depth.
    private static func folder(_ inner: URL, isInside outer: URL) -> Bool {
        let innerPath: String = ReferenceImportSource.pathWithSlash(inner)
        let outerPath: String = ReferenceImportSource.pathWithSlash(outer)
        if innerPath == outerPath {
            return false
        }
        return innerPath.hasPrefix(outerPath)
    }

    /// A path with one trailing slash, so `/a/bc` is not read as being inside
    /// `/a/b`.
    private static func pathWithSlash(_ url: URL) -> String {
        var path: String = url.resolvingSymlinksInPath().standardizedFileURL.path
        if !path.hasSuffix("/") {
            path += "/"
        }
        return path
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
