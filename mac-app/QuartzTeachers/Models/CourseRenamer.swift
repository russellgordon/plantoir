import Foundation

/// Changes a course's code.
///
/// A teacher looks a course up by its code — it is how the wizard finds
/// ready-made content — but the code they typed at setup can turn out to be
/// the wrong one, and a course they cannot rename is a course they have to
/// build again. So this exists, and it is deliberately small: renaming moves
/// the folder and rewrites the code inside the course's own settings, and
/// that is all.
///
/// **What renaming deliberately does NOT touch**, each for its own reason:
///
/// * **The course's NAME.** "Introduction to Computer Science, Grade 11" is
///   the teacher's own wording, editable in Course Settings. Rewriting a
///   title they may have hand-written, because they changed a code, is the
///   kind of helpfulness that loses work.
/// * **Backups and archives.** They stay in `courses/_backups/<OLD CODE>/`
///   under the names they were made with, because that is what they are: a
///   copy of the course as it stood, when it was called that. Restoring one
///   still works — `CourseRestorer` names the restored folder after the item
///   rather than after whatever the zip happens to hold inside.
/// * **The published website.** Where a section publishes to is recorded
///   INSIDE the course folder (`.netlify_sites/section<N>.json`), so it
///   travels with the move and the site's address does not change. A rename
///   is a change to the teacher's filing, not a move of their students' URL.
///
/// The one thing renaming has to break is a scheduled publish: those are
/// alarms held outside the working folder, addressed by the old code, and
/// after a rename they would fire at a course that is no longer there. They
/// are turned off, and the teacher is TOLD — see `noticeAfterRenaming`.
enum CourseRenamer {

    // MARK: - Types

    /// Why a rename could not go ahead, in words a teacher can act on.
    enum Problem: LocalizedError {
        case codeCannotBeUsed(String)
        case somethingIsAlreadyThere(String)
        case settingsCouldNotBeWritten(String)
        case folderCouldNotBeMoved(String)

        var errorDescription: String? {
            switch self {
            case .codeCannotBeUsed(let reason):
                return reason
            case .somethingIsAlreadyThere(let code):
                return "There is already something called \(code) in this working folder."
            case .settingsCouldNotBeWritten(let reason):
                return "The course's settings could not be saved: \(reason)"
            case .folderCouldNotBeMoved(let reason):
                return "The course's folder could not be renamed: \(reason)"
            }
        }
    }

    /// Something a teacher has to be told after a rename that otherwise
    /// succeeded.
    struct Notice: Identifiable {

        // MARK: - Stored properties

        let title: String
        let message: String

        // MARK: - Computed properties

        var id: String {
            return title + message
        }
    }

    /// A rename held up by a question about Obsidian.
    ///
    /// Renaming moves the course's folder, and that folder IS the Obsidian
    /// vault. Obsidian's file watcher is anchored to a folder's identity, so
    /// a vault open on that course goes on showing files that are no longer
    /// there — the same thing that happens if the folder is renamed in
    /// Finder. Obsidian has no way to close ONE vault, so putting it right
    /// means closing Obsidian altogether, which is a big enough thing to do
    /// to somebody else's application that it is asked about first.
    struct ObsidianRequest: Identifiable {

        // MARK: - Stored properties

        let course: Course
        let requestedCode: String

        /// EVERY vault open when the rename was asked for, not just this
        /// course's. Closing Obsidian closes all of them, and relaunching
        /// does not bring them back — measured — so the whole set has to be
        /// remembered and opened again.
        let openVaultPaths: [String]

        // MARK: - Computed properties

        var id: String {
            return "\(course.code)-\(requestedCode)"
        }
    }

    /// What renaming did BEYOND moving the folder, so the teacher can be
    /// told rather than left to find out when a publish does not happen.
    struct Outcome {

        // MARK: - Stored properties

        /// The code the course now has.
        let newCode: String

        /// Sections whose scheduled publish was turned off.
        let stoppedScheduledSections: [Int]

        /// Sections whose scheduled publish could not be turned off — rare,
        /// and worth saying out loud, because one of those may still try to
        /// run against a course that has moved.
        let unstoppedScheduledSections: [Int]

        // MARK: - Computed properties

        /// True when nothing happened that the teacher needs telling about.
        var isQuiet: Bool {
            return stoppedScheduledSections.isEmpty && unstoppedScheduledSections.isEmpty
        }
    }

    // MARK: - Functions

    /// Renames a course, and reports what else had to change.
    ///
    /// The order is chosen so that a failure leaves nothing half-done: the
    /// settings are written FIRST, while the folder is still where it was,
    /// and put back if the move then fails. Writing them after the move
    /// would risk a folder called one thing carrying settings that say
    /// another — which no error message would ever surface, because the app
    /// reads the code from the folder name and the site builder reads it
    /// from the settings.
    @discardableResult
    static func rename(
        _ course: Course,
        to requestedCode: String,
        coursesDirectoryURL: URL,
        existingCodes: [String],
        runner: LaunchControlRunning = LaunchControl()
    ) throws -> Outcome {
        let newCode: String = CourseCodeRule.normalized(requestedCode)
        if let reason = CourseCodeRule.problem(
            requestedCode, existingCodes: existingCodes, currentCode: course.code
        ) {
            throw Problem.codeCannotBeUsed(reason)
        }
        if newCode.isEmpty || newCode == course.code {
            // Nothing typed, or the same code typed again. Not an error —
            // the teacher changed their mind, which is allowed.
            return Outcome(newCode: course.code, stoppedScheduledSections: [], unstoppedScheduledSections: [])
        }

        let fileManager: FileManager = FileManager.default
        let destinationURL: URL = coursesDirectoryURL.appendingPathComponent(newCode)
        if fileManager.fileExists(atPath: destinationURL.path) {
            throw Problem.somethingIsAlreadyThere(newCode)
        }

        // Asked BEFORE anything moves: after the move these are addressed by
        // a code no course has any more, and there would be no way to find
        // them.
        let scheduledSections: [Int] = sectionsWithAScheduledPublish(in: course)

        let previousCode: String = course.code
        course.configuration.setCourseCode(newCode)
        do {
            try course.configuration.write(to: course.configFileURL)
        } catch {
            course.configuration.setCourseCode(previousCode)
            throw Problem.settingsCouldNotBeWritten(error.localizedDescription)
        }

        do {
            try fileManager.moveItem(at: course.directoryURL, to: destinationURL)
        } catch {
            course.configuration.setCourseCode(previousCode)
            try? course.configuration.write(to: course.configFileURL)
            throw Problem.folderCouldNotBeMoved(error.localizedDescription)
        }

        // The built website lives outside the working folder and is named
        // after the course CODE, so the folder that just moved carries a link
        // pointing at the old name. Carried across here rather than left to
        // `BuildOutputLocation.ensureLink`, whose answer to a link pointing
        // somewhere else is to start again from nothing — which would throw
        // away a site that renaming the course never used to cost.
        BuildOutputLocation.moveBuild(
            forWorkingFolder: coursesDirectoryURL.deletingLastPathComponent(),
            fromCourseCode: previousCode,
            toCourseCode: newCode,
            renamedCourseDirectory: destinationURL
        )

        var stopped: [Int] = []
        var unstopped: [Int] = []
        for sectionNumber in scheduledSections {
            let problem: String? = ScheduledDeploy.cancelScheduledDeploy(
                courseCode: previousCode, sectionNumber: sectionNumber, runner: runner
            )
            if problem == nil {
                stopped.append(sectionNumber)
            } else {
                unstopped.append(sectionNumber)
            }
        }

        return Outcome(
            newCode: newCode,
            stoppedScheduledSections: stopped,
            unstoppedScheduledSections: unstopped
        )
    }

    /// Which of a course's sections are set to publish on their own.
    ///
    /// Asked of the alarms themselves rather than of a note of ours, the way
    /// the sidebar's clock is: a teacher can take one away without telling
    /// us, and acting on a list that says otherwise is how a rename ends up
    /// reporting that it turned off something that was never on.
    static func sectionsWithAScheduledPublish(in course: Course) -> [Int] {
        var found: [Int] = []
        for sectionNumber in course.sectionNumbers {
            let plistURL: URL = ScheduledDeploy.plistURL(
                courseCode: course.code, sectionNumber: sectionNumber
            )
            if FileManager.default.fileExists(atPath: plistURL.path) {
                found.append(sectionNumber)
            }
        }
        return found
    }

    /// What the teacher is told after a rename, or nil when there is nothing
    /// to say — which is the ordinary case, and gets no interruption.
    ///
    /// The notice carries its own TITLE because it is not always about the
    /// same thing: turning a scheduled publish off is news a teacher can
    /// act on, while failing to turn one off is a warning. An alert headed
    /// "Renamed" would be true of both and useful for neither.
    static func noticeAfterRenaming(_ outcome: Outcome) -> Notice? {
        if outcome.isQuiet {
            return nil
        }

        var sentences: [String] = []
        if !outcome.stoppedScheduledSections.isEmpty {
            let sections: String = listed(outcome.stoppedScheduledSections)
            let isOne: Bool = outcome.stoppedScheduledSections.count == 1
            sentences.append(
                "\(sections) of \(outcome.newCode) \(isOne ? "was" : "were") set to publish on "
                + "\(isOne ? "its" : "their") own. Renaming turned that off — set "
                + "\(isOne ? "it" : "them") again from the section's menu if you still want "
                + "\(isOne ? "it" : "them")."
            )
        }
        if !outcome.unstoppedScheduledSections.isEmpty {
            let sections: String = listed(outcome.unstoppedScheduledSections)
            let isOne: Bool = outcome.unstoppedScheduledSections.count == 1
            sentences.append(
                "\(sections) \(isOne ? "was" : "were") also set to publish on "
                + "\(isOne ? "its" : "their") own, and Plantoir could not turn that off. "
                + "\(isOne ? "It" : "They") may still try to publish under the old name."
            )
        }

        let title: String = outcome.unstoppedScheduledSections.isEmpty
            ? "Scheduled publishing was turned off"
            : "A scheduled publish may still run"
        return Notice(title: title, message: sentences.joined(separator: "\n\n"))
    }

    /// What the teacher is asked before Obsidian is closed for them.
    ///
    /// Written as a whole sentence about what will happen rather than a
    /// warning about what might: Plantoir knows exactly what it is going to
    /// do, and an alert that says "may" when it means "will" teaches people
    /// to stop reading alerts.
    static func obsidianQuestion(openVaultCount: Int) -> String {
        let ending: String = openVaultCount > 1 ? "open your vaults again" : "open it again"
        return """
            Renaming moves this course's folder, and Obsidian would keep showing files that are no longer there.

            Plantoir can close Obsidian, rename the course, and \(ending).
            """
    }

    /// "Section 1", "Sections 1 and 2", "Sections 1, 2 and 4".
    static func listed(_ sectionNumbers: [Int]) -> String {
        var numbers: [String] = []
        for sectionNumber in sectionNumbers {
            numbers.append("\(sectionNumber)")
        }
        if numbers.count <= 1 {
            return "Section \(numbers.first ?? "")"
        }
        let last: String = numbers[numbers.count - 1]
        var leading: [String] = []
        for index in 0..<(numbers.count - 1) {
            leading.append(numbers[index])
        }
        return "Sections \(leading.joined(separator: ", ")) and \(last)"
    }
}
