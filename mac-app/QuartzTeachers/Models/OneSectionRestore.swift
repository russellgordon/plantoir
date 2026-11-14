import Foundation

/// Restore from Backup… for a backup made for ONE section (#897, piece C):
/// when it is offered, what comes back besides the section's folder, and the
/// sentences the alert and its finished line say.
///
/// The rules are `contracts/course-management.json` →
/// `backups.restoreOneSection`, run by `OneSectionRestoreContractTests` here
/// and by Windows' own readers there. The restore itself is
/// `CourseRestorer.restoreSectionFromTheMenu`; the order of work around it
/// (archive first, the busy checks) is `WorkspaceModel.restoreOneSection`.
///
/// Everything here is reached only from the alert. The built-in assistant's
/// window keeps its own "Restore Section N…" exactly as it was
/// (`CourseRestorer.restoreSection`), because its surface is frozen
/// (Russell, #897, 2026-11-13).
enum OneSectionRestore {

    // MARK: - Types

    /// What a one-section restore does with each of a section's files that
    /// live OUTSIDE `section<N>/`.
    enum Treatment: String {
        /// Put back as the backup has it, and removed when the backup has none.
        case fromTheBackup
        /// Removed, because the build writes it again from the pages.
        case discarded
        /// Left exactly as it is, because it describes the live website.
        case leftAsItIs
    }

    /// One of a section's files outside its folder, by its path inside the
    /// course folder with `{N}` for the section number.
    struct OutsideFile: Equatable {

        // MARK: - Stored properties

        let pathTemplate: String
        let isFolder: Bool
        let treatment: Treatment

        // MARK: - Functions

        /// The path inside the course folder for one section.
        func path(forSection sectionNumber: Int) -> String {
            return pathTemplate.replacingOccurrences(of: "{N}", with: String(sectionNumber))
        }
    }

    /// The facts about naming that decide whether a backup's class pages
    /// still mean anything in the course as it is now.
    struct Naming: Equatable {

        // MARK: - Stored properties

        /// "Unit", "Module", "Week".
        let word: String

        /// `unit_day` or `numbered`.
        let scheme: String

        /// The per-section folder the class pages live in.
        let classFolder: String

        // MARK: - Initializer

        init(word: String, scheme: String, classFolder: String) {
            self.word = word
            self.scheme = scheme
            self.classFolder = classFolder
        }

        /// The naming a course's settings record.
        init(configuration: CourseConfiguration) {
            self.word = configuration.unitWord
            self.scheme = configuration.classPageScheme.rawValue
            self.classFolder = ClassFolder.name(
                inPerSectionFolders: configuration.perSectionFolders,
                configured: configuration.classFolder
            )
        }
    }

    /// What a backup zip holds that the offer needs, read from its listing
    /// and its `course_config.json` without unpacking the rest.
    struct BackupFacts: Equatable {

        // MARK: - Stored properties

        /// Every `section<N>/` folder the zip holds.
        let sectionsInside: Set<Int>

        /// The backup's naming, or nil when its settings could not be read.
        let naming: Naming?
    }

    /// What a one-section restore did, for the finished line and the trail.
    struct Outcome: Equatable {

        // MARK: - Stored properties

        /// Shared pages whose setting for this section could not be put back
        /// because the page has nowhere a new key can go (#186's shape), or
        /// whose write failed.
        let pagesNotPutBack: Int

        /// Shared pages made after the backup that were visible to this
        /// section and are now hidden from it.
        let pagesMadeSinceHidden: Int

        /// The backup's record of this section's website differs from the
        /// live one, which is left as it is.
        let websiteRecordDiffers: Bool
    }

    // MARK: - Stored properties

    /// Every file of one section that lives outside `section<N>/`, and what a
    /// one-section restore does with it. Seven, measured by a grep of every
    /// `section\(…)` file name under `mac-app/QuartzTeachers` on 2026-11-13
    /// (the #897 plan review, amendment 17); the website markers are listed
    /// too, so the list is the whole answer to "what about this file?".
    ///
    /// `OneSectionRestoreTests.testTheListNamesTheSameFilesTheirOwnersDo`
    /// holds each path against the function that owns the file, so a file
    /// that moves cannot leave this list pointing at nothing.
    static let filesOutsideTheSection: [OutsideFile] = [
        OutsideFile(pathTemplate: ".internal/timetable/section{N}.json", isFolder: false, treatment: .fromTheBackup),
        OutsideFile(pathTemplate: ".publish_state/section{N}.published-pages", isFolder: true, treatment: .fromTheBackup),
        OutsideFile(pathTemplate: ".publish_state/section{N}.links-checklist-answered.json", isFolder: false, treatment: .fromTheBackup),
        OutsideFile(pathTemplate: ".publish_state/section{N}.later-classes-kept.json", isFolder: false, treatment: .fromTheBackup),
        OutsideFile(pathTemplate: ".publish_state/section{N}.front-page-not-today.json", isFolder: false, treatment: .fromTheBackup),
        OutsideFile(pathTemplate: ".publish_state/section{N}.links-checklist.json", isFolder: false, treatment: .discarded),
        OutsideFile(pathTemplate: ".publish_state/section{N}.json", isFolder: false, treatment: .leftAsItIs),
        OutsideFile(pathTemplate: ".netlify_sites/section{N}.json", isFolder: false, treatment: .leftAsItIs),
        OutsideFile(pathTemplate: ".cloudflare_sites/section{N}.json", isFolder: false, treatment: .leftAsItIs),
    ]

    // MARK: - Functions

    /// The section a backup offers to put back on its own, or nil for
    /// today's whole-course alert.
    ///
    /// Offered only when every one of these holds, and each is a fault that
    /// would report success otherwise: the backup was made for ONE section
    /// (a teacher's own backup is a copy of the whole course); that section
    /// is in the course now (a section removed since has nowhere to go); the
    /// course is one the teacher teaches (a reference course is restored
    /// whole or not at all); no rename of the course's unit word or folders
    /// is half done; the zip holds that section's folder; and the course
    /// names its class pages the way the backup did (amendment 19: pages
    /// named "Unit 3, Day 2" in a course that now says "Module" no longer
    /// count as classes, so Add Next Class and Re-date pass them over).
    static func offeredSection(
        maker: BackupMaker,
        sectionExistsNow: Bool,
        keptForReference: Bool,
        renameUnfinished: Bool,
        backupHasTheSection: Bool,
        namingSameAsNow: Bool
    ) -> Int? {
        var madeFor: Int?
        switch maker {
        case .teacher:
            madeFor = nil
        case .assistant(let sectionNumber):
            madeFor = sectionNumber
        case .menu(let sectionNumber):
            madeFor = sectionNumber
        }
        guard let sectionNumber = madeFor else {
            return nil
        }
        if !sectionExistsNow || keptForReference || renameUnfinished {
            return nil
        }
        if !backupHasTheSection || !namingSameAsNow {
            return nil
        }
        return sectionNumber
    }

    /// Whether a course's unit word or folder rename did not finish: its
    /// record is still on disk. The cheap fact (the file is there) rather
    /// than `UnitWordRenamer.interruptedRenameTarget`, which walks every
    /// class folder and can delete the record (the #897 plan review,
    /// amendment 4).
    static func renameIsUnfinished(courseDirectory: URL) -> Bool {
        let fileManager: FileManager = FileManager.default
        if fileManager.fileExists(atPath: UnitWordRenamer.renameMarkerURL(courseDirectory: courseDirectory).path) {
            return true
        }
        return fileManager.fileExists(atPath: SpecialFolderRenamer.renameMarkerURL(courseDirectory: courseDirectory).path)
    }

    /// Reads what the offer needs from a backup zip: which section folders it
    /// holds, from its listing, and its naming, from its settings file alone.
    /// Nil when the zip cannot be listed.
    ///
    /// `zipinfo -1` reads the central directory only, so this costs a
    /// fraction of a second even for a backup that carries a large Media
    /// folder; nothing is unpacked.
    static func readFacts(ofBackupAt zipURL: URL) -> BackupFacts? {
        guard let listingData = run("/usr/bin/zipinfo", ["-1", zipURL.path]) else {
            return nil
        }
        let listing: String = String(decoding: listingData, as: UTF8.self)
        var sectionsInside: Set<Int> = []
        var configEntry: String?
        for line in listing.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts: [Substring] = line.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count == 2 && parts[1] == "course_config.json" {
                configEntry = String(line)
            }
            // "ICS3U/section2/" (the folder's own entry) or anything inside
            // it; a FILE called "section2" at the course's root is not one.
            let isTheFolderItself: Bool = parts.count == 2 && line.hasSuffix("/")
            let isInsideIt: Bool = parts.count >= 3
            if isTheFolderItself || isInsideIt {
                let folder: String = String(parts[1])
                if CourseRestorer.namesASectionFolder(folder),
                   let number = Int(folder.dropFirst("section".count)) {
                    sectionsInside.insert(number)
                }
            }
        }
        var naming: Naming?
        if let configEntry,
           let configData = run("/usr/bin/unzip", ["-p", zipURL.path, configEntry]),
           let decoded = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
            let configuration: CourseConfiguration = CourseConfiguration(values: decoded, lastSavedData: configData)
            naming = Naming(configuration: configuration)
        }
        return BackupFacts(sectionsInside: sectionsInside, naming: naming)
    }

    /// Runs a reader and returns what it printed, or nil when it failed.
    private static func run(_ executable: String, _ arguments: [String]) -> Data? {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output: Pipe = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data: Data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            return nil
        }
        return data
    }
}

/// The sentences of Restore from Backup… for a backup made for one section.
///
/// Kept out of `AssistWording` on purpose: they are the alert's, not the
/// assistant's, and `MenuVoiceTests` forbids "Restore Section" in every
/// assistant-wording key named for the menu (the #897 plan review, amendment
/// 20). `contracts/course-management.json` → `backups.restoreOneSection.wording`
/// carries every one as a template, so Windows reads them as data.
nonisolated enum OneSectionRestoreWording {

    // MARK: - Functions

    static func title(course: String) -> String {
        return "Restore \(course) from this backup?"
    }

    /// What the alert says. `madeBy` is the backup's own
    /// `BackupMaker.description` ("before a change from the Section menu to
    /// Section 2"), `when` its `BackupItem.whenDescription`.
    static func message(section: Int, madeBy: String, when: String) -> String {
        return "This backup was made \(madeBy), on \(when).\n\n"
             + "Restore Section \(section) puts back that section alone: its pages, its settings on the pages "
             + "every section shares, its class dates and its record of what was published. Your other sections "
             + "are not touched. Anything changed in Section \(section) since then goes back too, including work "
             + "done in Obsidian.\n\n"
             + "Restore Whole Course puts every section back to how it was then.\n\n"
             + "Either way, nothing is lost: the course as it is now moves to Archived, at the bottom of the "
             + "sidebar, where you can get it back. This backup is kept."
    }

    static func restoreSectionButton(section: Int) -> String {
        return "Restore Section \(section)"
    }

    static let restoreWholeCourseButton: String = "Restore Whole Course"

    static func doneTitle(section: Int, course: String) -> String {
        return "Section \(section) of \(course) is back"
    }

    /// The finished line, with whichever of the three extra sentences apply.
    static func done(section: Int, when: String, outcome: OneSectionRestore.Outcome) -> String {
        var text: String = "Section \(section) is back to how it was on \(when). Nothing in your other sections changed."
        if outcome.pagesMadeSinceHidden == 1 {
            text += "\n\nOne shared page made since then is now hidden from Section \(section), because it did "
                  + "not exist when the backup was made."
        } else if outcome.pagesMadeSinceHidden > 1 {
            text += "\n\n\(outcome.pagesMadeSinceHidden) shared pages made since then are now hidden from Section "
                  + "\(section), because they did not exist when the backup was made."
        }
        if outcome.pagesNotPutBack == 1 {
            text += "\n\nOne shared page kept the setting it has now for Section \(section): the settings at the "
                  + "top of it are written in a way Plantoir cannot add to, so that page was left exactly as it is."
        } else if outcome.pagesNotPutBack > 1 {
            text += "\n\n\(outcome.pagesNotPutBack) shared pages kept the settings they have now for Section "
                  + "\(section): the settings at the top of them are written in a way Plantoir cannot add to, so "
                  + "those pages were left exactly as they are."
        }
        if outcome.websiteRecordDiffers {
            text += "\n\nSection \(section) still goes to the website address it has now. A restore does not "
                  + "change where students read it."
        }
        return text
    }

    static func namingChanged(section: Int, course: String) -> String {
        return "Section \(section) cannot be put back on its own, because the class pages of \(course) are named "
             + "differently now than they were in this backup. Restore Whole Course puts every section back "
             + "together instead."
    }

    static func busy(section: Int, course: String) -> String {
        return "Section \(section) of \(course) is being changed right now. Wait for that to finish, then restore."
    }

    static func sectionNotInCourse(section: Int, course: String) -> String {
        return "\(course) has no Section \(section) now, so there is nowhere to put it back. Restore Whole Course "
             + "puts every section back together instead."
    }

    /// Said when the swap failed and every file was put back where it was.
    static func leftAsItWas(section: Int, reason: String) -> String {
        return "Section \(section) was left as it was, because the restore could not finish: \(reason)"
    }

    /// Said when the swap failed AND putting things back failed too.
    static func stoppedPartWay(section: Int) -> String {
        return "The restore of Section \(section) stopped part way and could not put everything back as it was. "
             + "The course as it was before you pressed Restore is in Archived, at the bottom of the sidebar."
    }
}
