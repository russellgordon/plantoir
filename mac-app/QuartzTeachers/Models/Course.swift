import Foundation
import Observation

/// One course (or club) folder inside the working folder's `courses/`
/// directory, together with its loaded configuration.
@Observable
class Course: Identifiable {

    // MARK: - Stored properties

    /// The course code, e.g. "ICS3U" — also the folder name.
    let code: String

    /// The course folder, e.g. `<workspace>/courses/ICS3U`.
    let directoryURL: URL

    /// The loaded `course_config.json` for this course.
    let configuration: CourseConfiguration

    // MARK: - Computed properties

    var id: String {
        return code
    }

    /// The code a TEACHER reads.
    ///
    /// Equal to `code` for every course they teach — `CourseRenamer` is the
    /// only writer of `course_code` and it moves the folder in the same
    /// breath — and different only for a reference course, whose folder
    /// carries a year suffix (`ICS3U-2025`) so two ICS3Us can sit side by
    /// side while the code on screen stays the one the teacher recognises.
    ///
    /// `code` is IDENTITY and keeps its meaning everywhere: the folder, the
    /// launcher argument, the built-site folder, the preview lease, the
    /// backup zip's name, the launchd label. This is the other half, and it
    /// is used only where a teacher reads a name.
    ///
    /// Falls back to `code` when the config's own `course_code` is empty,
    /// because a row labelled with nothing at all is worse than a row
    /// labelled with the folder.
    var displayCode: String {
        if !isKeptForReference {
            return code
        }
        let recorded: String = configuration.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if recorded.isEmpty {
            return code
        }
        return recorded
    }

    /// Whether this is a reference course: kept to be read, never deployed.
    var isKeptForReference: Bool {
        return configuration.keptForReference
    }

    /// Which school year this reference course is filed under on `day`, or
    /// nil for "Other" — and always nil for a course a teacher teaches, which
    /// sits in no year group at all.
    func schoolYear(on day: CalendarDay) -> Int? {
        if !isKeptForReference {
            return nil
        }
        return SchoolYear.offeredYear(storedYear: configuration.referenceSchoolYear, on: day)
    }

    /// The timetable section numbers for this course, from the configuration.
    var sectionNumbers: [Int] {
        return configuration.sectionNumbers
    }

    var configFileURL: URL {
        return directoryURL.appendingPathComponent("course_config.json")
    }

    // MARK: - Functions

    /// This course as its settings file says it is RIGHT NOW (#335) — a new
    /// `Course` with the same code and folder, read from `course_config.json`.
    ///
    /// **For acts, not for display.** Deploying, and setting a deploy, read
    /// the saved file, because the launcher, the build, the approval card and
    /// a scheduled run all do: a window's copy may hold Course Settings edits
    /// nobody has saved, and an act that followed those would publish half
    /// from memory and half from disk. Never assign the result back into a
    /// window's model — that copy holds the teacher's unsaved edits and must
    /// keep them. The same idea as #322's `readCoursesAsSavedNow`, for one
    /// course. Throws when the file cannot be read: there is no safe default
    /// for where a site goes, so the caller refuses rather than guessing.
    func asSavedNow() throws -> Course {
        let saved: CourseConfiguration = try CourseConfiguration(contentsOf: configFileURL)
        return Course(code: code, directoryURL: directoryURL, configuration: saved)
    }

    /// The folder holding one section's content, e.g.
    /// `<workspace>/courses/ICS3U/section3`.
    func sectionDirectoryURL(forSection sectionNumber: Int) -> URL {
        return directoryURL.appendingPathComponent("section\(sectionNumber)")
    }

    // MARK: - Initializer

    init(code: String, directoryURL: URL, configuration: CourseConfiguration) {
        self.code = code
        self.directoryURL = directoryURL
        self.configuration = configuration
    }
}
