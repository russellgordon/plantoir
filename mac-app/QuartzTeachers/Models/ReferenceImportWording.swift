import Foundation

/// Every sentence a teacher reads while importing last year's courses —
/// written once, here.
///
/// Kept apart from `ReferenceWording` (which says what a reference course
/// IS, wherever they meet one) because these are said by one sheet, in one
/// stretch of work, and a file per act is what keeps a sentence beside the
/// thing that produces it. Retyped from `contracts/shared-rules.json` →
/// `referenceCourses.importing.wording` and pinned against it by
/// `ReferenceImportTests`, the same arrangement `ReferenceWording` uses.
///
/// **The register is plain and the machinery is never named.** A teacher
/// chose a folder; they are told what was found in it, what will be copied,
/// and what was not. Nothing here says "symlink", "build output", "script" or
/// "container", and nothing says "cannot" where "is not" will do.
nonisolated enum ReferenceImportWording {

    // MARK: - Getting there

    /// The File-menu item.
    static let menuItem: String = "Import Courses for Reference…"

    /// The sheet's title.
    static let title: String = "Import courses for reference"

    /// What the sheet is for, above the list.
    static let explanation: String =
        "Plantoir copies the courses you tick into this working folder and keeps them for "
        + "reference. The folder you choose is left exactly as it is."

    // MARK: - When the folder cannot be used

    /// No courses in there.
    ///
    /// Says what to point at instead in the teacher's own words — the folder
    /// their classes were in — rather than naming the folder Plantoir looks
    /// for inside it.
    static func noCoursesThere(folder: String) -> String {
        return "There are no courses in \(folder). Choose the folder you kept that year's classes in."
    }

    /// The folder this window is already working in.
    static let thatIsTheFolderYouHaveOpen: String =
        "That is the folder you already have open. To keep one of these courses for reference, "
        + "use Keep a Copy for Reference… on the course itself."

    /// A folder inside the one this window is working in.
    static func insideTheFolderYouHaveOpen(folder: String) -> String {
        return "\(folder) is inside the folder you already have open. Choose a folder somewhere else."
    }

    /// A folder that CONTAINS the one this window is working in.
    static func holdsTheFolderYouHaveOpen(folder: String) -> String {
        return "\(folder) holds the folder you already have open. Choose a folder somewhere else."
    }

    // MARK: - The list

    /// The column of ticks, and what one row says beside the code.
    ///
    /// "2 sections · 287 pages · 489 MB" — the three facts a teacher uses to
    /// recognise a course and to know what they are about to wait for. The
    /// size is what will be COPIED, with last year's built website already
    /// taken out of it.
    static func courseSummary(sections: Int, pages: Int, bytes: Int64) -> String {
        let sectionWord: String = sections == 1 ? "1 section" : "\(sections) sections"
        let pageWord: String = pages == 1 ? "1 page" : "\(pages) pages"
        return "\(sectionWord) · \(pageWord) · \(ReferenceImportWording.size(bytes))"
    }

    /// The label over each row's year list.
    static let schoolYearLabel: String = "School year"

    /// A course that cannot come across, said beside its own row.
    ///
    /// Shown rather than hidden: a teacher whose only course has unreadable
    /// settings was told "there are no courses in that folder", which is a
    /// different thing and sends them to look in the wrong place.
    static let settingsCouldNotBeRead: String =
        "Its settings could not be read, so it can’t be brought across."

    /// A folder inside a course that the disk would not hand over.
    ///
    /// Said before anything is copied, and again as the reason if it happens
    /// during the copy. A folder that could not be read contributes no pages,
    /// and an import that quietly left it out would be found out next year.
    static func couldNotReadFolder(folder: String) -> String {
        return "\(folder) could not be read, so this course was left as it is."
    }

    /// Said once under the list, about what does not come across.
    static let builtWebsitesAreNotCopied: String =
        "Last year's built websites are not copied. Preview a course and Plantoir builds it again."

    /// The button.
    static let importButton: String = "Import"

    /// Nothing ticked yet.
    static let tickSomething: String = "Tick the courses you want to keep for reference."

    // MARK: - While it runs

    /// The line under the progress bar.
    static func copying(course: String) -> String {
        return "Copying \(course)…"
    }

    /// "489 MB of 489 MB" — said rather than a bare percentage, because a
    /// teacher watching a slow external disk wants to know how much is left
    /// in the units their folder is measured in.
    static func copiedSoFar(bytes: Int64, of total: Int64) -> String {
        return "\(ReferenceImportWording.size(bytes)) of \(ReferenceImportWording.size(total))"
    }

    // MARK: - When it is done

    /// The heading over the summary.
    static let doneTitle: String = "Imported"

    /// Where they went.
    static let whereTheyAre: String =
        "They are in the sidebar under Reference Courses, filed by school year."

    /// One course that came across.
    static func imported(course: String, year: String, sections: Int) -> String {
        let sectionWord: String = sections == 1 ? "1 section" : "\(sections) sections"
        return "\(course) — \(year), \(sectionWord)"
    }

    /// One course that did not, with the reason beside it. The others carried
    /// on: a folder of four courses where one has a problem imports three.
    static func couldNotImport(course: String, reason: String) -> String {
        return "\(course) was not imported. \(reason)"
    }

    /// What "no year" is called in a summary line.
    static let noSchoolYear: String = "no school year"

    /// Said when the teacher stopped it part way. What had already come
    /// across is there; what was in hand is not.
    static let stopped: String =
        "Stopped. The courses already imported are in the sidebar; the one in progress was not kept."

    // MARK: - Sizes

    /// A size a teacher reads: "489 MB", "1.2 GB", "84 KB".
    ///
    /// Plain decimal units, the way Finder counts them, so the number beside
    /// a folder in Finder and the number in this sheet agree.
    static func size(_ bytes: Int64) -> String {
        let formatter: ByteCountFormatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
