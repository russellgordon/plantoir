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

    /// Beside a ticked row whose code and school year clash only with a row
    /// ticked ABOVE it in this same sheet. Nothing is kept yet, so the
    /// shelf's own sentence ("You already have…") would be false here. Two
    /// sections of an older-layout course say
    /// `olderLayoutAnotherSectionOfTheSameCourse` instead.
    static func alsoTickedForThatYear(folder: String, course: String) -> String {
        return "\(folder) is also ticked for that school year, and one \(course) is kept for each year. "
             + "Choose Other or a different school year for one of them."
    }

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

    // MARK: - The older layout (a folder per class, #254)

    /// Russell's 2023–24 way of keeping a course — one folder per class, and
    /// the shared folders and pages kept in a folder beside them whose name
    /// ends in "Shared". Every sentence below is about that shape and about
    /// nothing else. None of them says how the shared folder was reached
    /// from the class: the teacher kept folders, and folders are what they
    /// are told about. `documentation/09-mac-app.md` → "The older layout".

    /// Under a row, when the shared folder was found (or chosen) and holds
    /// everything the class used.
    static func olderLayoutSharedFound(folder: String) -> String {
        return "Shared pages and pictures: from \(folder)."
    }

    /// Under a row, when the shared folder holds only some of it.
    static func olderLayoutSharedPartlyFound(folder: String, missing: [String]) -> String {
        return "Shared pages and pictures: from \(folder). Not there, so they will be missing: "
             + ReferenceImportWording.list(missing) + "."
    }

    /// Under a row, when nothing was found beside the class. Never a refusal:
    /// the import proceeds without them if the teacher wants (Russell,
    /// decision 2).
    static func olderLayoutSharedNotFound(count: Int) -> String {
        return "No shared pages and pictures were found beside this class. Choose the folder they "
             + "were kept in, or import without them: \(count) shared folders and pages will be missing."
    }

    /// The button that chooses the shared folder by hand. Offered on every
    /// older-layout row that has shared content to find, including when one
    /// was found by its name — Russell, decision 7: a wrong match must be
    /// correctable.
    static let olderLayoutChooseSharedButton: String = "Choose Shared Folder…"

    /// A chosen shared folder that holds none of what the class used.
    static func olderLayoutChosenFolderHasNone(folder: String) -> String {
        return "\(folder) has none of the shared folders this class used. Choose another folder, "
             + "or import without it."
    }

    /// A chosen shared folder that is itself a class.
    static func olderLayoutChosenFolderIsAClass(folder: String) -> String {
        return "\(folder) is a class of its own, not the folder its shared pages were kept in. "
             + "Choose another folder."
    }

    /// A chosen shared folder whose name carries another course's code. A
    /// warning, not a refusal.
    static func olderLayoutChosenFolderIsForAnotherCourse(folder: String, code: String, course: String) -> String {
        return "\(folder) looks like it belongs to \(code), not \(course). "
             + "Its pages and pictures will be brought across all the same."
    }

    /// The shared folder itself was chosen, rather than a class.
    static func olderLayoutThatIsTheSharedFolder(folder: String) -> String {
        return "\(folder) holds the pages every class shared. Choose one of the class folders "
             + "beside it, or the folder they are all in."
    }

    /// A class folder whose name carries no course code: shown, not ticked.
    static let olderLayoutNoCourseCode: String =
        "Its name has no course code in it, so it can’t be brought across."

    /// Beside a second section of the same course and year. Two sections of
    /// one course cannot both be kept under one school year (the shelf rule),
    /// and "You already have…" would be false here: nothing is kept yet.
    static func olderLayoutAnotherSectionOfTheSameCourse(folder: String) -> String {
        return "Another section of this course, \(folder), is ticked for that school year. "
             + "To keep this one as well, choose Other or a different school year for it."
    }

    /// One line of the summary, for a course that came across without some
    /// or all of its shared pages and pictures.
    static func olderLayoutImportedWithSharedMissing(course: String, year: String) -> String {
        return "\(course) — \(year), 1 section, without some of its shared pages and pictures."
    }

    /// Added to a summary line when something of the class did not come
    /// across — a file below the top of it, or inside its shared folders,
    /// that only pointed somewhere else, or one whose name the course uses
    /// for itself. COUNTED and NAMED, so nothing goes missing unnoticed
    /// (#254 fixes, item 1). Why each was left out is in the docs, not here.
    static func olderLayoutLeftOut(count: Int, names: [String]) -> String {
        let noun: String = count == 1 ? "1 of its files or folders was" : "\(count) of its files and folders were"
        return "\(noun) not brought across: " + ReferenceImportWording.list(names) + "."
    }

    /// A folder holding whole courses kept a folder per class — the school
    /// year's folder, `2023-24`. `noCoursesThere` ("Choose the folder you
    /// kept that year's classes in") would point back at the folder just
    /// chosen, which is exactly the one it describes.
    static func olderLayoutChooseOneCourseAtATime(folder: String) -> String {
        return "\(folder) holds courses rather than classes. Choose the Class Website folder "
             + "inside one of them, or one class folder."
    }

    /// Said under the list and in the summary whenever an older class is
    /// involved. The real class folders carry a publishing add-on whose
    /// settings hold a live credential; none of it comes across.
    static let olderLayoutAddOnsAreLeftBehind: String =
        "Obsidian add-ons and their settings are not brought across from older class folders, "
        + "so nothing in them can publish these pages."

    // MARK: - The 2024–25 layout (a website folder per class, #256)

    /// Russell's 2024–25 way of keeping a course — one whole website folder
    /// per class, often reached through Finder shortcuts. Every sentence
    /// below is about that shape. None names what the folder holds besides
    /// pages and pictures: "the files that built the website" is as far as
    /// they go. `documentation/09-mac-app.md` → "The 2024–25 layout".

    /// Under a row: where its pages and pictures are read from.
    static func checkoutLayoutReadFrom(place: String) -> String {
        return "Pages and pictures from \(place)."
    }

    /// Under a row reached through a Finder shortcut.
    static func checkoutLayoutReadThroughShortcut(shortcut: String, place: String) -> String {
        return "\(shortcut) is a shortcut. Its pages and pictures are read from \(place)."
    }

    /// Said once under the list, and in the summary, whenever a class kept
    /// this way is involved. What stays behind is not a loss, and a teacher
    /// who is told only "not brought across" would go looking for it.
    static let checkoutLayoutOnlyPagesComeAcross: String =
        "From a class website folder, only the pages and pictures of its first section come across. "
        + "The files that built the website, the extra folders kept for editing, and the other sections' "
        + "pages stay where they are."

    /// A folder chosen from inside a class's website folder.
    static func checkoutLayoutChooseTheWholeFolder(folder: String, website: String) -> String {
        return "\(folder) is part of the class website kept in \(website). Choose \(website) itself."
    }

    /// A later section: beside its row, or as the refusal when it was
    /// chosen on its own (Russell, 2026-09-23: only the first section).
    static func checkoutLayoutOnlyTheFirstSection(folder: String, section: Int) -> String {
        return "\(folder) holds section \(section)'s pages. Only the first section of a course kept "
             + "this way can be brought across."
    }

    /// A folder holding several courses' folders of class websites.
    static func checkoutLayoutChooseOneCourseAtATime(folder: String) -> String {
        return "\(folder) holds several courses. Choose one course's folder inside it, or one class's folder."
    }

    /// A website folder holding the pages of more than one course.
    static let checkoutLayoutMoreThanOneCourse: String =
        "It holds the pages of more than one course, so it can’t be brought across as one."

    /// A website folder whose section could not be told.
    static let checkoutLayoutWhichSection: String =
        "Which section it was could not be told, so it can’t be brought across."

    /// A shortcut to a folder that is no longer there.
    static func checkoutLayoutShortcutGone(shortcut: String) -> String {
        return "\(shortcut) is a shortcut to a folder that is no longer there, so it can’t be brought across."
    }

    /// A shortcut to a folder this Mac would not let Plantoir open.
    static func checkoutLayoutShortcutCouldNotBeOpened(shortcut: String) -> String {
        return "\(shortcut) is a shortcut to a folder Plantoir was not allowed to open. Allow it in "
             + "System Settings › Privacy & Security › Files and Folders, then choose the folder again."
    }

    /// A shortcut to a folder on a disk that is not connected.
    static func checkoutLayoutShortcutOnADiskNotConnected(shortcut: String, disk: String) -> String {
        return "\(shortcut) is a shortcut to a folder on \(disk), which isn’t connected. "
             + "Connect it, then choose the folder again."
    }

    /// A shortcut to a file, chosen on its own.
    static func checkoutLayoutShortcutToAFile(shortcut: String) -> String {
        return "\(shortcut) is a shortcut to a file, not a folder."
    }

    /// Names in a sentence: "Concepts, Media and Tasks".
    static func list(_ names: [String]) -> String {
        if names.isEmpty {
            return ""
        }
        if names.count == 1 {
            return names[0]
        }
        var result: String = ""
        var index: Int = 0
        for name in names {
            if index == names.count - 1 {
                result += " and " + name
            } else if index == 0 {
                result += name
            } else {
                result += ", " + name
            }
            index += 1
        }
        return result
    }

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
