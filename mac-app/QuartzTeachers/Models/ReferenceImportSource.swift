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

        /// Why this course cannot be brought across, or nil when it can.
        ///
        /// **A course with a problem is SHOWN rather than hidden**, with its
        /// reason beside it and its tick disabled. Leaving it out was the
        /// first shape of this, and it told a teacher whose only course had
        /// unreadable settings "there are no courses in that folder" — which
        /// is not what happened, and sends them to look in the wrong place.
        let problem: String?

        /// The school year this course most plausibly was, or nil when the
        /// dates do not say. A PROPOSAL: the teacher changes it in the sheet,
        /// and nothing anywhere tells them how it was arrived at.
        let suggestedSchoolYear: Int?

        /// Where it is, over in the old folder. Only ever read.
        let directoryURL: URL

        /// Set for a class folder kept in the OLDER layout (a folder per
        /// class, #254), nil for an ordinary course. The importer takes a
        /// different road for one — `OlderCourseLayout.plan` — and the sheet
        /// says what was found of its shared pages beside the row.
        var olderLayout: OlderCourseLayout.Facts? = nil

        /// Set for a class kept in the 2024–25 layout (a whole website
        /// folder per class, #256), nil otherwise. The importer takes its own
        /// road for one — `QuartzCheckoutLayout.plan` — and the sheet says
        /// where its pages are read from beside the row.
        var checkoutLayout: QuartzCheckoutLayout.Facts? = nil

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

        /// The older layout's shared folder was chosen rather than a class.
        case theSharedFolder(folderName: String)

        /// A folder of whole older-layout courses (the school year's folder).
        case aFolderOfOlderCourses(folderName: String)

        /// A folder inside a class's website folder (#256).
        case partOfAClassWebsite(folderName: String, websiteName: String)

        /// A later section of a course kept a website folder per class: only
        /// the first comes across (Russell, 2026-09-23).
        case onlyTheFirstSection(folderName: String, section: Int)

        /// A folder holding several courses' folders of class websites.
        case severalClassWebsiteCourses(folderName: String)

        /// The school year's folder, one level above the courses whose
        /// folders hold the shortcuts to their class websites.
        case classWebsiteCoursesFurtherDown(folderName: String)

        /// A Finder shortcut, chosen on its own, that cannot be read through.
        case shortcutTrouble(shortcut: String, trouble: QuartzCheckoutLayout.ShortcutTrouble, disk: String?)

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
            case .theSharedFolder(let folderName):
                return ReferenceImportWording.olderLayoutThatIsTheSharedFolder(folder: folderName)
            case .aFolderOfOlderCourses(let folderName):
                return ReferenceImportWording.olderLayoutChooseOneCourseAtATime(folder: folderName)
            case .partOfAClassWebsite(let folderName, let websiteName):
                return ReferenceImportWording.checkoutLayoutChooseTheWholeFolder(
                    folder: folderName, website: websiteName
                )
            case .onlyTheFirstSection(let folderName, let section):
                return ReferenceImportWording.checkoutLayoutOnlyTheFirstSection(folder: folderName, section: section)
            case .severalClassWebsiteCourses(let folderName):
                return ReferenceImportWording.checkoutLayoutChooseOneCourseAtATime(folder: folderName)
            case .classWebsiteCoursesFurtherDown(let folderName):
                return ReferenceImportWording.checkoutLayoutChooseACourseFolderInside(folder: folderName)
            case .shortcutTrouble(let shortcut, let trouble, let disk):
                return QuartzCheckoutLayout.sentence(about: trouble, shortcut: shortcut, disk: disk)
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
    ///
    /// A `var` for one reason: choosing a shared folder by hand for an
    /// older-layout class re-measures that one row in place.
    var courses: [FoundCourse]

    /// The one course the teacher pointed AT, when they chose a course folder
    /// rather than a working folder. Ticked on its own in that case.
    let chosenCourseFolderName: String?

    /// Which rows are ticked when a folder of OLDER-layout classes (#254) or
    /// of class website folders (#256) was chosen, or nil for every other
    /// shape. See `olderLayoutTicked(_:)` and `checkoutLayoutTicked(_:)` for
    /// the two rules.
    var olderLayoutTicked: Set<String>? = nil

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
            for course in courses where course.id == chosenCourseFolderName && course.problem == nil {
                return [chosenCourseFolderName]
            }
            return []
        }
        if let olderLayoutTicked {
            return olderLayoutTicked
        }
        var everything: Set<String> = []
        for course in courses where course.problem == nil {
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
    /// **When none of the three is there, the OLDER folder-per-class layout
    /// is tried** (`olderLayoutOutcome`, #254) — asked second, so a folder
    /// holding a `courses` folder or a course's settings is always read the
    /// modern way whatever else is in it — **and then the 2024–25
    /// website-folder-per-class layout** (`checkoutLayoutOutcome`, #256),
    /// asked third, so neither earlier shape can be claimed by it.
    ///
    /// `leavingBehind` is the whole skip list, passed in rather than read
    /// here so the measuring and the copying cannot disagree about it.
    /// The same, off the main actor.
    ///
    /// Reading a folder of four courses walks about 2,600 files, and a folder
    /// on a disk that has to spin up walks them slowly.
    ///
    /// **`@concurrent` is what moves it off the interface's thread.** A plain
    /// `nonisolated async` function would run on its CALLER's actor here,
    /// because `project.yml` sets `SWIFT_APPROACHABLE_CONCURRENCY: YES` —
    /// measured, the same body reports `Thread.isMainThread == true` without
    /// the attribute and `false` with it. Without it the sheet's spinner
    /// could not spin while this ran.
    @concurrent
    static func read(
        chosen: URL,
        workingFolderURL: URL?,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay = CalendarDay.today()
    ) async -> Outcome {
        return ReferenceImportSource.resolve(
            chosen: chosen,
            workingFolderURL: workingFolderURL,
            leavingBehind: leftBehindNames,
            on: day
        )
    }

    /// `day` is carried all the way down to the school-year proposal rather
    /// than left to the clock: the sheet has a day of its own so the year
    /// list cannot change under the teacher mid-sheet, and a proposal read
    /// off a different day from the list it is chosen in is a proposal that
    /// is sometimes not in the list.
    static func resolve(
        chosen: URL,
        workingFolderURL: URL?,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay = CalendarDay.today()
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
        //
        // **Its neighbours are offered only when it really is sitting in a
        // `courses` folder.** A course folder anywhere else — one dragged
        // onto the Desktop, say — is offered ON ITS OWN, because "everything
        // beside it" would then mean every course-shaped folder on the
        // Desktop, with the trail line naming the home folder as the source.
        var loneCourse: Bool = false
        if coursesURL == nil {
            let config: URL = chosenURL.appendingPathComponent(ReferenceImportSource.configFileName)
            if fileManager.fileExists(atPath: config.path) {
                let parent: URL = chosenURL.deletingLastPathComponent()
                coursesURL = parent
                chosenCourseFolderName = chosenName
                loneCourse = parent.lastPathComponent != "courses"
            }
        }

        // Nothing of the modern shape: perhaps the OLDER one (#254). Asked
        // only now, so a folder holding a `courses` folder or a course's
        // settings is always read the modern way, whatever else is in it.
        guard let coursesURL else {
            return ReferenceImportSource.olderLayoutOutcome(
                chosen: chosenURL, leavingBehind: leftBehindNames, on: day
            ) ?? ReferenceImportSource.checkoutLayoutOutcome(
                chosen: chosenURL, workingFolderURL: workingFolderURL, leavingBehind: leftBehindNames, on: day
            ) ?? .refused(.noCoursesThere(folderName: chosenName))
        }

        var courses: [FoundCourse] = []
        if loneCourse {
            if let only = ReferenceImportSource.measure(
                courseAt: chosenURL,
                configURL: chosenURL.appendingPathComponent(ReferenceImportSource.configFileName),
                leavingBehind: leftBehindNames,
                on: day
            ) {
                courses.append(only)
            }
        } else {
            courses = ReferenceImportSource.courses(
                in: coursesURL, leavingBehind: leftBehindNames, on: day
            )
        }
        if courses.isEmpty {
            return ReferenceImportSource.olderLayoutOutcome(
                chosen: chosenURL, leavingBehind: leftBehindNames, on: day
            ) ?? ReferenceImportSource.checkoutLayoutOutcome(
                chosen: chosenURL, workingFolderURL: workingFolderURL, leavingBehind: leftBehindNames, on: day
            ) ?? .refused(.noCoursesThere(folderName: chosenName))
        }

        // What the trail calls the source: the working folder for the two
        // ordinary shapes, and the course folder itself for a lone one,
        // whose parent is nobody's working folder.
        var rootURL: URL = coursesURL.deletingLastPathComponent()
        if loneCourse {
            rootURL = chosenURL
        }

        return .found(ReferenceImportSource(
            rootURL: rootURL,
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
    static func courses(
        in coursesURL: URL,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay = CalendarDay.today()
    ) -> [FoundCourse] {
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
                courseAt: child, configURL: configURL, leavingBehind: leftBehindNames, on: day
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

    // MARK: - Functions (the older layout, #254)

    /// What the OLDER layout makes of a chosen folder, or nil when it is not
    /// that shape either.
    static func olderLayoutOutcome(
        chosen chosenURL: URL,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay
    ) -> Outcome? {
        switch OlderCourseLayout.recognise(chosenURL) {
        case .nothing:
            return nil
        case .theSharedFolder:
            return .refused(.theSharedFolder(folderName: chosenURL.lastPathComponent))
        case .aFolderOfCourses:
            return .refused(.aFolderOfOlderCourses(folderName: chosenURL.lastPathComponent))
        case .classFolder(let classURL):
            let course: FoundCourse = ReferenceImportSource.measureOlderClass(
                at: classURL,
                sharedFolderURL: OlderCourseLayout.sharedFolder(besideClassFolder: classURL),
                howFound: .byItsName,
                chosenWarning: nil,
                leavingBehind: leftBehindNames,
                on: day
            )
            return .found(ReferenceImportSource(
                rootURL: classURL.deletingLastPathComponent(),
                coursesURL: classURL.deletingLastPathComponent(),
                courses: [course],
                chosenCourseFolderName: classURL.lastPathComponent
            ))
        case .folderOfClasses(let folderURL, let classFolders):
            var courses: [FoundCourse] = []
            for classURL in classFolders {
                courses.append(ReferenceImportSource.measureOlderClass(
                    at: classURL,
                    sharedFolderURL: OlderCourseLayout.sharedFolder(besideClassFolder: classURL),
                    howFound: .byItsName,
                    chosenWarning: nil,
                    leavingBehind: leftBehindNames,
                    on: day
                ))
            }
            courses.sort { first, second in
                if first.courseCode == second.courseCode {
                    return first.folderName.localizedStandardCompare(second.folderName) == .orderedAscending
                }
                return first.courseCode < second.courseCode
            }
            var source: ReferenceImportSource = ReferenceImportSource(
                rootURL: folderURL,
                coursesURL: folderURL,
                courses: courses,
                chosenCourseFolderName: nil
            )
            source.olderLayoutTicked = ReferenceImportSource.olderLayoutTicked(courses)
            return .found(source)
        }
    }

    /// Which older-layout rows are ticked when a whole folder of them is
    /// chosen.
    ///
    /// **Only a class NAMED like one** (`ICS3U-S1-2023-24`, `ICS4U-2023-24`),
    /// so `ICD2O-Exemplars` is offered and not assumed. **And of several
    /// sections of one course in one school year, only the LOWEST**: the
    /// shelf holds one course per code per year, so ticking S1 and S2 of
    /// 2023–24 together opened the sheet with the second one already in
    /// trouble, under a sentence ("You already have…") that was false —
    /// nothing was kept yet. S2 is offered, unticked, with a sentence of its
    /// own; Russell's decision 1 makes it a second import.
    static func olderLayoutTicked(_ courses: [FoundCourse]) -> Set<String> {
        var ticked: Set<String> = []
        var lowestByCourseAndYear: [String: FoundCourse] = [:]
        for course in courses {
            guard course.problem == nil,
                  let facts = course.olderLayout,
                  facts.names.looksLikeAClass else {
                continue
            }
            var yearText: String = "none"
            if let year = course.suggestedSchoolYear {
                yearText = "\(year)"
            }
            let key: String = course.courseCode.uppercased() + " " + yearText
            if let already = lowestByCourseAndYear[key],
               let alreadyFacts = already.olderLayout,
               (alreadyFacts.names.section ?? 0) <= (facts.names.section ?? 0) {
                continue
            }
            lowestByCourseAndYear[key] = course
        }
        for (_, course) in lowestByCourseAndYear {
            ticked.insert(course.id)
        }
        return ticked
    }

    /// One older-layout class, measured for the sheet: its code and year from
    /// its name, its shared content, and the size of what will be COPIED —
    /// the class's own files plus the shared ones it used, which for ICS3U S1
    /// is 1.4 MB of class and about 870 MB of shared pictures.
    static func measureOlderClass(
        at classURL: URL,
        sharedFolderURL: URL?,
        howFound: OlderCourseLayout.HowFound,
        chosenWarning: String?,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay
    ) -> FoundCourse {
        let folderName: String = classURL.lastPathComponent
        let names: OlderCourseLayout.NameFacts = OlderCourseLayout.nameFacts(of: folderName)
        let plan: OlderCourseLayout.Plan = OlderCourseLayout.plan(
            classFolderURL: classURL,
            sharedFolderURL: sharedFolderURL,
            howFound: howFound,
            leavingBehind: leftBehindNames
        )

        var problem: String?
        if names.code == nil {
            problem = ReferenceImportWording.olderLayoutNoCourseCode
        } else if let unreadable = plan.unreadableFolders.first {
            problem = ReferenceImportWording.couldNotReadFolder(folder: unreadable)
        }

        // The year the NAME says, when it says one that is offered; the
        // pages' own dates otherwise, exactly as a modern course.
        var year: Int? = SchoolYear.offeredYear(storedYear: names.startingYear, on: day)
        if year == nil {
            year = ReferenceImportSource.suggestedSchoolYear(fromPagesChangedIn: plan.pageYears, on: day)
        }

        return FoundCourse(
            folderName: folderName,
            courseCode: names.code ?? folderName,
            courseName: folderName,
            sectionNumbers: [1],
            pageCount: plan.pageCount,
            fileCount: plan.fileCount,
            byteCount: plan.byteCount,
            problem: problem,
            suggestedSchoolYear: year,
            directoryURL: classURL,
            olderLayout: OlderCourseLayout.Facts(
                classFolderName: folderName,
                names: names,
                shared: plan.shared,
                chosenWarning: chosenWarning
            )
        )
    }

    // MARK: - Functions (the 2024–25 layout, #256)

    /// What the 2024–25 website-folder-per-class layout makes of a chosen
    /// folder, or nil when it is not that shape either.
    ///
    /// The three refusals about the open working folder already ran on the
    /// CHOSEN folder; they run again here on every folder a shortcut leads
    /// to, because a shortcut can lead into the folder this window has open.
    static func checkoutLayoutOutcome(
        chosen chosenURL: URL,
        workingFolderURL: URL?,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay
    ) -> Outcome? {
        switch QuartzCheckoutLayout.recognise(chosenURL) {
        case .nothing:
            return nil
        case .partOfAWebsite(let websiteName):
            return .refused(.partOfAClassWebsite(folderName: chosenURL.lastPathComponent, websiteName: websiteName))
        case .aLaterSection(let section):
            return .refused(.onlyTheFirstSection(folderName: chosenURL.lastPathComponent, section: section))
        case .severalCourses:
            return .refused(.severalClassWebsiteCourses(folderName: chosenURL.lastPathComponent))
        case .coursesFurtherDown:
            return .refused(.classWebsiteCoursesFurtherDown(folderName: chosenURL.lastPathComponent))
        case .shortcutTrouble(let candidate):
            return .refused(.shortcutTrouble(
                shortcut: candidate.rowName,
                trouble: candidate.trouble ?? .gone,
                disk: candidate.disk
            ))
        case .website(let candidate):
            let course: FoundCourse = ReferenceImportSource.measureWebsite(
                candidate, workingFolderURL: workingFolderURL, leavingBehind: leftBehindNames, on: day
            )
            // A later section chosen on its own is refused outright rather
            // than shown as a single row that cannot be ticked.
            if let facts = course.checkoutLayout, let section = facts.section,
               section != QuartzCheckoutLayout.importableSection {
                return .refused(.onlyTheFirstSection(folderName: candidate.rowName, section: section))
            }
            let parent: URL = chosenURL.deletingLastPathComponent()
            return .found(ReferenceImportSource(
                rootURL: parent,
                coursesURL: parent,
                courses: [course],
                chosenCourseFolderName: course.id
            ))
        case .folderOfWebsites(let folderURL, let candidates):
            var courses: [FoundCourse] = []
            for candidate in candidates {
                courses.append(ReferenceImportSource.measureWebsite(
                    candidate, workingFolderURL: workingFolderURL, leavingBehind: leftBehindNames, on: day
                ))
            }
            courses.sort { first, second in
                if first.courseCode == second.courseCode {
                    return first.folderName.localizedStandardCompare(second.folderName) == .orderedAscending
                }
                return first.courseCode < second.courseCode
            }
            var source: ReferenceImportSource = ReferenceImportSource(
                rootURL: folderURL,
                coursesURL: folderURL,
                courses: courses,
                chosenCourseFolderName: nil
            )
            source.olderLayoutTicked = ReferenceImportSource.checkoutLayoutTicked(courses)
            return .found(source)
        }
    }

    /// Which rows are ticked when a folder of class websites is chosen:
    /// every row that can come across, and of several with the same code
    /// and year only the first — the shelf holds one course per code per
    /// year, and a sheet opened with its second row already in trouble
    /// reads as broken (#254's lesson).
    static func checkoutLayoutTicked(_ courses: [FoundCourse]) -> Set<String> {
        var ticked: Set<String> = []
        var taken: Set<String> = []
        for course in courses where course.problem == nil {
            var yearText: String = "none"
            if let year = course.suggestedSchoolYear {
                yearText = "\(year)"
            }
            let key: String = course.courseCode.uppercased() + " " + yearText
            if taken.contains(key) {
                continue
            }
            taken.insert(key)
            ticked.insert(course.id)
        }
        return ticked
    }

    /// One class website folder, measured for the sheet: its code, its
    /// section, where it is read from, the year its path (or its pages)
    /// say, and the size of what will be COPIED — its first section and the
    /// shared pages, not the whole website folder.
    ///
    /// A row with a problem is not planned at all: its numbers would be of
    /// a copy that will never be made.
    static func measureWebsite(
        _ candidate: QuartzCheckoutLayout.Candidate,
        workingFolderURL: URL?,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay
    ) -> FoundCourse {
        let facts: QuartzCheckoutLayout.Facts = QuartzCheckoutLayout.facts(of: candidate)

        var problem: String?
        if let trouble = candidate.trouble {
            problem = QuartzCheckoutLayout.sentence(
                about: trouble, shortcut: candidate.shortcutName ?? candidate.rowName, disk: candidate.disk
            )
        } else if facts.code == nil {
            problem = ReferenceImportWording.checkoutLayoutMoreThanOneCourse
        } else if facts.section == nil {
            problem = ReferenceImportWording.checkoutLayoutWhichSection
        } else if let section = facts.section, section != QuartzCheckoutLayout.importableSection {
            problem = ReferenceImportWording.checkoutLayoutOnlyTheFirstSection(
                folder: candidate.rowName, section: section
            )
        } else if let websiteURL = facts.websiteURL, let workingFolderURL {
            let openURL: URL = workingFolderURL.standardizedFileURL
            if ReferenceImportSource.isTheSameFolder(websiteURL, openURL)
                || ReferenceImportSource.folder(websiteURL, isInside: openURL) {
                problem = ReferenceImportWording.insideTheFolderYouHaveOpen(folder: candidate.rowName)
            } else if ReferenceImportSource.folder(openURL, isInside: websiteURL) {
                problem = ReferenceImportWording.holdsTheFolderYouHaveOpen(folder: candidate.rowName)
            }
        }

        var pageCount: Int = 0
        var fileCount: Int = 0
        var byteCount: Int64 = 0
        var pageYears: [Int] = []
        if problem == nil {
            let plan: QuartzCheckoutLayout.Plan = QuartzCheckoutLayout.plan(
                facts: facts, leavingBehind: leftBehindNames
            )
            pageCount = plan.pageCount
            fileCount = plan.fileCount
            byteCount = plan.byteCount
            pageYears = plan.pageYears
            if let unreadable = plan.unreadableFolders.first {
                problem = ReferenceImportWording.couldNotReadFolder(folder: unreadable)
            }
        }

        var year: Int?
        if let websiteURL = facts.websiteURL {
            year = SchoolYear.offeredYear(
                storedYear: QuartzCheckoutLayout.schoolYear(fromThePathOf: websiteURL), on: day
            )
        }
        if year == nil && problem == nil {
            year = ReferenceImportSource.suggestedSchoolYear(fromPagesChangedIn: pageYears, on: day)
        }

        var courseName: String = ""
        if let code = facts.code, let section = facts.section {
            courseName = "\(code) S\(section)"
        }
        return FoundCourse(
            folderName: candidate.rowName,
            courseCode: facts.code ?? candidate.rowName,
            courseName: courseName,
            sectionNumbers: [1],
            pageCount: pageCount,
            fileCount: fileCount,
            byteCount: byteCount,
            problem: problem,
            suggestedSchoolYear: year,
            directoryURL: facts.websiteURL ?? URL(fileURLWithPath: "/").appendingPathComponent(candidate.rowName),
            checkoutLayout: facts
        )
    }

    /// What choosing a shared folder by hand came to.
    enum SharedChoice: Sendable {
        case accepted(FoundCourse)
        case refused(String)
    }

    /// The teacher chose the folder an older class's shared pages were kept
    /// in: check it, and re-measure the row with it.
    ///
    /// Refused — with the row left as it was — when it is the folder this
    /// window has open (or inside it, or holding it), when it is a class
    /// itself, or when it holds none of what the class used. A different
    /// course code in its name is a warning beside the row, not a refusal.
    static func withSharedChosen(
        _ course: FoundCourse,
        sharedFolderURL chosenURL: URL,
        workingFolderURL: URL?,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay
    ) -> SharedChoice {
        let chosen: URL = chosenURL.standardizedFileURL
        let chosenName: String = chosen.lastPathComponent
        if let workingFolderURL {
            let openURL: URL = workingFolderURL.standardizedFileURL
            if ReferenceImportSource.isTheSameFolder(chosen, openURL) {
                return .refused(ReferenceImportWording.thatIsTheFolderYouHaveOpen)
            }
            if ReferenceImportSource.folder(chosen, isInside: openURL) {
                return .refused(ReferenceImportWording.insideTheFolderYouHaveOpen(folder: chosenName))
            }
            if ReferenceImportSource.folder(openURL, isInside: chosen) {
                return .refused(ReferenceImportWording.holdsTheFolderYouHaveOpen(folder: chosenName))
            }
        }
        if let refusal = OlderCourseLayout.refusal(
            ofChosenSharedFolder: chosen, forClassFolder: course.directoryURL
        ) {
            return .refused(refusal)
        }
        let warning: String? = OlderCourseLayout.codeWarning(
            forChosenSharedFolder: chosen, classCode: course.courseCode
        )
        var remeasured: FoundCourse = ReferenceImportSource.measureOlderClass(
            at: course.directoryURL,
            sharedFolderURL: chosen,
            howFound: .chosen,
            chosenWarning: warning,
            leavingBehind: leftBehindNames,
            on: day
        )
        // The year the teacher sees is theirs to keep: re-measuring must not
        // move it. (The sheet keeps its own choice by row, so only the
        // PROPOSAL is carried here.)
        remeasured = FoundCourse(
            folderName: remeasured.folderName,
            courseCode: remeasured.courseCode,
            courseName: remeasured.courseName,
            sectionNumbers: remeasured.sectionNumbers,
            pageCount: remeasured.pageCount,
            fileCount: remeasured.fileCount,
            byteCount: remeasured.byteCount,
            problem: remeasured.problem,
            suggestedSchoolYear: course.suggestedSchoolYear,
            directoryURL: remeasured.directoryURL,
            olderLayout: remeasured.olderLayout
        )
        return .accepted(remeasured)
    }

    /// The same, off the main actor — it walks the chosen folder, which can
    /// be 1,600 pictures.
    @concurrent
    static func chooseShared(
        for course: FoundCourse,
        sharedFolderURL: URL,
        workingFolderURL: URL?,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay
    ) async -> SharedChoice {
        return ReferenceImportSource.withSharedChosen(
            course,
            sharedFolderURL: sharedFolderURL,
            workingFolderURL: workingFolderURL,
            leavingBehind: leftBehindNames,
            on: day
        )
    }

    // MARK: - Private helpers

    /// Reads one course's settings and walks it once, for everything the
    /// sheet has to show.
    private static func measure(
        courseAt courseURL: URL,
        configURL: URL,
        leavingBehind leftBehindNames: Set<String>,
        on day: CalendarDay
    ) -> FoundCourse? {
        guard let data = try? Data(contentsOf: configURL),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // SHOWN, and not tickable. Copying it would make a reference
            // course of nothing — but leaving the row out told a teacher
            // whose only course was this one that the folder held no courses,
            // which is a different thing and sends them somewhere else.
            return FoundCourse(
                folderName: courseURL.lastPathComponent,
                courseCode: courseURL.lastPathComponent,
                courseName: "",
                sectionNumbers: [],
                pageCount: 0,
                fileCount: 0,
                byteCount: 0,
                problem: ReferenceImportWording.settingsCouldNotBeRead,
                suggestedSchoolYear: nil,
                directoryURL: courseURL
            )
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

        // A folder inside the course that the disk will not hand over is said
        // HERE, before anything is copied, rather than discovered half way
        // through the copy — and the row cannot be ticked.
        var problem: String?
        if let unreadable = walked.unreadableFolders.first {
            problem = ReferenceImportWording.couldNotReadFolder(folder: unreadable)
        }

        return FoundCourse(
            folderName: courseURL.lastPathComponent,
            courseCode: courseCode,
            courseName: courseName,
            sectionNumbers: sectionNumbers,
            pageCount: walked.pageCount,
            fileCount: walked.fileCount,
            byteCount: walked.byteCount,
            problem: problem,
            suggestedSchoolYear: ReferenceImportSource.suggestedSchoolYear(
                fromPagesChangedIn: walked.pageYears, on: day
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
