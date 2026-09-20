import Foundation

/// "Keep a Copy for Reference…" — the whole act, without the sheet.
///
/// The teacher's own course is left exactly as it is and keeps being taught.
/// What is made is a SNAPSHOT beside it: a new folder, carrying the pages and
/// the settings as they are today, marked as kept for reference, left with
/// nowhere to deploy to, and locked.
///
/// *Rejected: converting the course in place.* One config write and no
/// copying, and it is what a teacher means when they say "this one's just for
/// reference now" — but it has to answer a live site already on the web, a
/// scheduled deploy already on disk, a preview running right now and an open
/// section window whose Deploy button vanishes under their hand. And it is
/// permanent: frozen, never deployed, no way back. **A wrong copy is deleted;
/// a wrong conversion is restored from a zip if one exists.** That asymmetry
/// is the whole argument.
@MainActor
enum ReferenceCopier {

    // MARK: - Types

    /// What was made, for the trail line and for the sidebar to select.
    struct Made: Equatable {

        // MARK: - Stored properties

        /// The folder it was given — `ICS3U-2025`.
        let folderName: String

        /// The code a teacher reads — `ICS3U`.
        let displayCode: String

        /// The school year it was filed under, or nil for "Other".
        let schoolYear: Int?

        /// How many sections came across.
        let sectionCount: Int
    }

    /// Why a copy could not be made.
    enum Problem: LocalizedError, Equatable {
        case folderAlreadyExists(String)
        case couldNotCopy(String)

        // MARK: - Computed properties

        var errorDescription: String? {
            switch self {
            case .folderAlreadyExists(let folderName):
                return "There is already a course folder called \(folderName). Choose a different name."
            case .couldNotCopy(let reason):
                return "The copy could not be made: \(reason)"
            }
        }
    }

    // MARK: - Stored properties

    /// Things this copy deliberately leaves behind, beyond what an archive
    /// already leaves behind (`CourseArchiver.excludedFromArchives`, which
    /// carries `.merged_output`, `node_modules`, `.git`, the caches and
    /// `.DS_Store`).
    ///
    /// `.merged_output` earns its own sentence: it is a SYMLINK out to the
    /// builds folder, and following it would copy last year's whole built
    /// website — measured at 1.9 GB on one real course — into a folder that
    /// rebuilds it on demand anyway.
    static let alsoLeftBehind: [String] = [
        // Yesterday's config. The live folder can also hold a Finder
        // duplicate ("course_config copy.json"); the config is read by exact
        // name, never by glob, so a duplicate is carried across as an
        // ordinary file and mistaken for nothing.
        "course_config.backup.json",
    ]

    // MARK: - Functions

    /// Makes the copy. The original is not touched.
    ///
    /// The order is deliberate and the LOCK IS LAST. Measured: `rm -rf` and
    /// `FileManager.removeItem` both refuse a locked tree — so a failure
    /// part-way through a locked copy would leave a folder the teacher cannot
    /// delete. Everything that can fail happens while the folder is still
    /// ordinary.
    static func keepACopy(
        of course: Course,
        named folderName: String,
        schoolYear: Int?,
        coursesDirectoryURL: URL,
        at moment: Date = Date()
    ) throws -> Made {
        let fileManager: FileManager = FileManager.default
        let destinationURL: URL = coursesDirectoryURL.appendingPathComponent(folderName)
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw Problem.folderAlreadyExists(folderName)
        }

        do {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
            try ReferenceCopier.copyContents(of: course.directoryURL, into: destinationURL)
        } catch {
            // Nothing is locked yet, so the half-written folder is an
            // ordinary one and goes away cleanly.
            try? fileManager.removeItem(at: destinationURL)
            if let problem = error as? Problem {
                throw problem
            }
            throw Problem.couldNotCopy(error.localizedDescription)
        }

        let copy: Course
        do {
            let configuration: CourseConfiguration = try CourseConfiguration(
                contentsOf: destinationURL.appendingPathComponent("course_config.json")
            )
            copy = Course(code: folderName, directoryURL: destinationURL, configuration: configuration)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw Problem.couldNotCopy(error.localizedDescription)
        }

        // Cut every section loose from the website it was publishing to,
        // BEFORE the marker is written — so a failure here leaves a folder
        // that is not yet a reference course rather than one that is and is
        // still pinned to last year's live site.
        //
        // Renamed aside rather than deleted, by the same function the
        // rollover uses: the file holds the site id and the admin address,
        // which a teacher may still want. Two fail-safes fall out of it — a
        // deploy that somehow ran would make a NEW site rather than overwrite
        // last year's, and a section that has never deployed cannot be
        // scheduled at all.
        for sectionNumber in copy.sectionNumbers {
            _ = DeployCommand.releaseSite(forSection: sectionNumber, in: copy, at: moment)
        }

        // `course_code` is deliberately NOT touched: it stays the real code,
        // which is what the teacher reads and what keeps this copy's preview
        // titles right. Only the FOLDER carries the year.
        copy.configuration.keptForReference = true
        copy.configuration.referenceSchoolYear = schoolYear
        copy.configuration.neutraliseForReference()
        do {
            try copy.configuration.write(to: copy.configFileURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw Problem.couldNotCopy(error.localizedDescription)
        }

        ReferenceLock.lock(courseDirectory: destinationURL)

        let made: Made = Made(
            folderName: folderName,
            displayCode: copy.displayCode,
            schoolYear: schoolYear,
            sectionCount: copy.sectionNumbers.count
        )
        ActivityTrail.note(
            .courseKeptForReference,
            ReferenceCopier.trailLine(for: made, copiedFrom: course.displayCode)
        )
        return made
    }

    /// The trail line — what a teacher would recognise, and enough to explain
    /// a report months later.
    static func trailLine(for made: Made, copiedFrom source: String) -> String {
        let year: String = made.schoolYear.map { startingYear in
            return SchoolYear.label(forStartingYear: startingYear)
        } ?? "no school year"
        let sections: String = made.sectionCount == 1 ? "1 section" : "\(made.sectionCount) sections"
        return "kept a copy of \(source) for reference as \(made.folderName) — "
             + "shown as \(made.displayCode), \(year), \(sections)"
    }

    // MARK: - Private helpers

    /// Copies everything the teacher wrote, and nothing that is rebuilt.
    private static func copyContents(of sourceURL: URL, into destinationURL: URL) throws {
        let fileManager: FileManager = FileManager.default
        let children: [URL] = try fileManager.contentsOfDirectory(
            at: sourceURL, includingPropertiesForKeys: nil, options: []
        )
        for child in children {
            let name: String = child.lastPathComponent
            if ReferenceCopier.isLeftBehind(name) {
                continue
            }
            try fileManager.copyItem(at: child, to: destinationURL.appendingPathComponent(name))
        }

        // Leases belong to processes on whichever machine wrote them, so a
        // copied one names a process that was never doing anything here.
        let leases: URL = destinationURL
            .appendingPathComponent(".internal").appendingPathComponent("activity")
        try? fileManager.removeItem(at: leases)
    }

    private static func isLeftBehind(_ name: String) -> Bool {
        for excluded in CourseArchiver.excludedFromArchives where excluded == name {
            return true
        }
        for excluded in ReferenceCopier.alsoLeftBehind where excluded == name {
            return true
        }
        return false
    }
}
