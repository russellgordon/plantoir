import Foundation

/// What the New Course wizard offers about keeping a new course for
/// reference (#572), as one rule with inputs and an answer.
///
/// Pure, so the contract's cases (`referenceCourses.creating.whenOffered`)
/// run it without a window.
enum ReferenceChoice: Equatable {

    /// Nothing is said: no code yet, a club, or a code with no ready-made
    /// pages that nobody asked to keep for reference.
    case notShown

    /// The toggle, with its caption, and the school year beside it while it
    /// is on.
    case toggle

    /// Under the taken-code refusal: a line offering to keep this one for
    /// reference, and its button.
    case offerUnderTheRefusal

    /// The sentence that says there are no ready-made pages to keep, said
    /// where the choice would be, for a code the teacher came to keep or
    /// cannot otherwise make.
    case noReadyMadePages

    // MARK: - Functions

    /// Which of the four the wizard shows.
    ///
    /// - Parameters:
    ///   - code: what is typed in the code field.
    ///   - hasReadyMadePages: whether example content exists for the code.
    ///   - isClub: the club tick box. A club takes no ready-made pages.
    ///   - takenByACourseHere: whether a course folder of that code exists.
    ///   - keepsForReference: whether the toggle is on now.
    ///   - cameForReference: whether the wizard was opened from New
    ///     Reference Course… on the shelf.
    static func offered(
        code: String,
        hasReadyMadePages: Bool,
        isClub: Bool,
        takenByACourseHere: Bool,
        keepsForReference: Bool,
        cameForReference: Bool
    ) -> ReferenceChoice {
        if CourseCodeRule.normalized(code).isEmpty {
            return .notShown
        }
        if isClub {
            return .notShown
        }
        if hasReadyMadePages {
            if takenByACourseHere && !keepsForReference {
                return .offerUnderTheRefusal
            }
            return .toggle
        }
        if takenByACourseHere || cameForReference {
            return .noReadyMadePages
        }
        return .notShown
    }
}

/// Making a NEW course straight onto the Reference Courses shelf (#572),
/// even when a live course has its code.
///
/// **One path for the wizard's three doors**: the toggle, the offer under the
/// taken-code refusal, and New Reference Course… on the shelf all end here.
/// It is `ReferenceCopier` with setup as its source: the course is built
/// under a hidden staging folder (`ReferenceStaging`), claimed and leased the
/// way every reference door claims it, set up THERE by the real setup with
/// `--reference-staging-folder`, made into a reference course by the one
/// implementation of that sequence (`ReferenceCopier.makeIntoAReferenceCourse`)
/// and renamed into place as the last act.
///
/// **The live course of the same code is never opened, read for writing,
/// backed up or renamed by any step.** Its folder is `courses/<CODE>`; every
/// write here is under `courses/.plantoir-importing-<FOLDER>`, and the
/// setup run accepts nothing else (`contracts/course-management.json` →
/// `courseCode.setupIntoStaging`).
///
/// Split in two around the setup run, because the run is the creator's: it
/// owns the runner, the answer pump and Cancel. `prepare` claims and writes
/// the settings; `finish` decides from how the run ended. Both write their own
/// failure line, and `finish` gives the claim back however it ends.
@MainActor
enum ReferenceCreation {

    // MARK: - Types

    /// A course claimed and waiting for setup.
    struct Prepared: Equatable {

        // MARK: - Stored properties

        /// The folder it will be given — `ICS3U-2026`.
        let folderName: String

        /// The code a teacher reads — `ICS3U`.
        let displayCode: String

        /// The school year it is filed under, or nil for "Other".
        let schoolYear: Int?

        /// The hidden folder it is built in.
        let stagingURL: URL

        /// The working folder's `courses`.
        let coursesDirectoryURL: URL

        /// The reference course this one replaces, by its folder, when the
        /// teacher chose Replace It… beside the shelf rule's refusal (#572,
        /// second piece). The new course is then made under THAT folder's
        /// hidden name and given its folder name.
        var replacing: String? = nil

        /// The group the teacher made that the wizard's Group picker chose
        /// (#572, third piece), with its name as the shelf shows it; nil for
        /// "Its school year". Written as the course's placement just before
        /// it becomes visible.
        var madeGroupID: String? = nil
        var madeGroupName: String? = nil

        // MARK: - Computed properties

        /// The name setup is given.
        var stagingName: String {
            return stagingURL.lastPathComponent
        }
    }

    /// Why a course was not made, in the sentence the teacher reads.
    ///
    /// Not `Equatable`: it carries the shelf rule's own value, whose
    /// conformance belongs to the main actor.
    enum Problem: LocalizedError {
        case noCode
        /// The shelf rule's refusal: its value, which a later door (572b's
        /// Replace) can offer something beside, and its sentence, read on the
        /// main actor when the refusal was made.
        case onTheShelfAlready(ReferenceCourseRule.Trouble, sentence: String)
        case folderAlreadyExists(String)
        case alreadyBeingMade(String)
        case couldNotBeMade(code: String)
        case pagesDidNotLand(code: String)
        case stopped

        // MARK: - Computed properties

        var errorDescription: String? {
            switch self {
            case .noCode:
                return ReferenceCreationWording.noCode
            case .onTheShelfAlready(_, let sentence):
                return sentence
            case .folderAlreadyExists(let folderName):
                return ReferenceCopier.Problem.folderAlreadyExists(folderName).errorDescription
            case .alreadyBeingMade(let folderName):
                return ReferenceWording.copyAlreadyBeingMade(folder: folderName)
            case .couldNotBeMade(let code):
                return ReferenceCreationWording.couldNotBeMade(code: code)
            case .pagesDidNotLand(let code):
                return ReferenceCreationWording.pagesDidNotLand(code: code)
            case .stopped:
                return ReferenceCreationWording.stopped
            }
        }
    }

    // MARK: - Stored properties

    /// What setup prints once the ready-made pages are in. One of the two
    /// things `pagesLanded` asks (plan review H3), the other being the pages
    /// themselves. The same text as `setup_course.py`'s own line.
    static let pagesInstalledMarker: String = "Example content installed"

    // MARK: - Functions

    /// What the wizard checks of a typed code, live and again at Create.
    ///
    /// For an ordinary course: the code rule against every course folder
    /// here, as before. For a course kept for reference: the code rule with
    /// NO existing codes, because a live course of that code is the point,
    /// and then the shelf rule for the chosen year — the same function every
    /// other door onto the shelf asks, so the caption and the act agree.
    static func courseCodeProblem(
        typed: String,
        existingFolderNames: [String],
        keepsForReference: Bool,
        schoolYear: Int?,
        shelved: [ReferenceCourseRule.Shelved],
        madeGroup: ReferenceShelf.MadeGroup? = nil
    ) -> String? {
        if !keepsForReference {
            return CourseCodeRule.problem(typed, existingCodes: existingFolderNames)
        }
        if let trouble = CourseCodeRule.trouble(typed, existingCodes: []) {
            return trouble.sentence
        }
        if let trouble = ReferenceCreation.shelfTrouble(
            typed: typed, schoolYear: schoolYear, shelved: shelved, madeGroup: madeGroup
        ) {
            return trouble.sentence
        }
        return nil
    }

    /// The shelf rule's refusal as a VALUE, for a course kept for reference,
    /// or nil. The wizard's live check reads its sentence through
    /// `courseCodeProblem`; a later door that offers something beside the
    /// refusal (572b's Replace) asks this. `madeGroup` is the group the
    /// wizard's Group picker chose (#572, third piece), which the rule is
    /// then asked of instead of the year.
    static func shelfTrouble(
        typed: String,
        schoolYear: Int?,
        shelved: [ReferenceCourseRule.Shelved],
        madeGroup: ReferenceShelf.MadeGroup? = nil
    ) -> ReferenceCourseRule.Trouble? {
        guard let madeGroup else {
            return ReferenceCourseRule.trouble(placing: typed, inYear: schoolYear, among: shelved)
        }
        return ReferenceCourseRule.trouble(
            placing: typed, in: .made(madeGroup.id), named: madeGroup.name, among: shelved
        )
    }

    /// Whether a code is taken by a course folder here — the refusal the
    /// offer sits under.
    static func isTakenByACourseHere(_ typed: String, existingFolderNames: [String]) -> Bool {
        let trouble: CourseCodeRule.Trouble? = CourseCodeRule.trouble(
            typed, existingCodes: existingFolderNames
        )
        if case .alreadyTaken = trouble {
            return true
        }
        return false
    }

    /// The settings a course kept for reference is made with: the wizard's
    /// own, marked, filed and neutralised BEFORE setup runs, so the hidden
    /// folder is a reference course for the whole of the run and not only at
    /// the end. Through `CourseConfiguration` so the marker and the four
    /// neutralised keys come from the one place every door takes them from.
    static func referenceSettings(_ configuration: [String: Any], schoolYear: Int?) -> CourseConfiguration {
        let settings: CourseConfiguration = CourseConfiguration(
            values: configuration, lastSavedData: Data()
        )
        settings.keptForReference = true
        settings.referenceSchoolYear = schoolYear
        // A reference course exists to hold the ready-made pages, and takes
        // the payload's structure with them.
        settings.values["prepopulate_example_content"] = true
        settings.values["use_skeleton"] = false
        settings.neutraliseForReference()
        return settings
    }

    /// Claims the hidden folder and writes the settings into it.
    ///
    /// Every way this fails writes `courseCouldNotBeCreatedForReference` and
    /// leaves nothing behind: the claim is given back and a half-written
    /// folder removed.
    static func prepare(
        configuration: [String: Any],
        schoolYear: Int?,
        coursesDirectoryURL: URL,
        existingFolderNames: [String],
        shelved: [ReferenceCourseRule.Shelved],
        replacing: String? = nil,
        madeGroupID: String? = nil
    ) throws -> Prepared {
        let rawCode: String = (configuration["course_code"] as? String) ?? ""
        let code: String = CourseCodeRule.normalized(rawCode)
        if code.isEmpty {
            throw Problem.noCode
        }

        // The group the Group picker chose, as the arrangement says it NOW
        // (#572, third piece). A group removed in another window since the
        // picker was drawn is no longer a choice: the course goes where its
        // school year puts it, and the shelf rule is asked of that.
        var place: ReferenceShelf.Place = ReferenceShelf.Place.forYear(schoolYear)
        var groupName: String?
        if let madeGroupID {
            let arrangement: ReferenceShelf.Arrangement = ReferenceShelfStore.read(
                inCoursesDirectory: coursesDirectoryURL
            ).arrangement
            if let group = arrangement.group(withID: madeGroupID) {
                place = .made(madeGroupID)
                groupName = group.name
            }
        }
        var chosenGroupID: String?
        if case .made(let id) = place {
            chosenGroupID = id
        }

        // The shelf rule again, at the act, so the caption and the act agree.
        // A replace is the one answer to its refusal, and only for the course
        // the rule names: the course in the way must be the one the teacher
        // was warned about, or this is refused like any other clash.
        var replacingFolder: String?
        if let trouble = ReferenceCourseRule.trouble(placing: code, in: place, named: groupName, among: shelved) {
            let inTheWay: ReferenceCourseRule.Shelved? = ReferenceCourseRule.courseInTheWay(
                placing: code, in: place, among: shelved
            )
            if let replacing, let inTheWay, inTheWay.folderName == replacing {
                replacingFolder = replacing
            } else {
                let problem: Problem = .onTheShelfAlready(trouble, sentence: trouble.sentence)
                ReferenceCreation.noteNotMade(code: code, folderName: nil, because: problem)
                throw problem
            }
        }

        var folderName: String = ReferenceCourseRule.proposedFolderName(
            forCode: code, schoolYear: schoolYear, existingFolderNames: existingFolderNames
        )
        if let replacingFolder {
            // The replacement takes the replaced course's folder name, so the
            // ordinary Restore from Backup puts the old one back in place.
            folderName = replacingFolder
        } else {
            let destinationURL: URL = coursesDirectoryURL.appendingPathComponent(folderName)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let problem: Problem = .folderAlreadyExists(folderName)
                ReferenceCreation.noteNotMade(code: code, folderName: folderName, because: problem)
                throw problem
            }
        }

        switch ReferenceStaging.claim(folderName, inCoursesDirectory: coursesDirectoryURL) {
        case .claimed:
            break
        case .someoneElseIsMakingIt:
            let problem: Problem = .alreadyBeingMade(folderName)
            ReferenceCreation.noteNotMade(code: code, folderName: folderName, because: problem)
            throw problem
        case .couldNotStart:
            let problem: Problem = .couldNotBeMade(code: code)
            ReferenceCreation.noteNotMade(code: code, folderName: folderName, because: problem)
            throw problem
        }

        let stagingURL: URL = coursesDirectoryURL.appendingPathComponent(
            ReferenceStaging.stagingName(for: folderName)
        )
        do {
            // The code as it is stored everywhere else: trimmed and upper
            // case, whatever the caller passed.
            var withTheCode: [String: Any] = configuration
            withTheCode["course_code"] = code
            let settings: CourseConfiguration = ReferenceCreation.referenceSettings(
                withTheCode, schoolYear: schoolYear
            )
            try settings.write(to: stagingURL.appendingPathComponent(ReferenceImportSource.configFileName))
        } catch {
            ReferenceStaging.remove(at: stagingURL)
            ReferenceStaging.giveBack(folderName, inCoursesDirectory: coursesDirectoryURL)
            let problem: Problem = .couldNotBeMade(code: code)
            ReferenceCreation.noteNotMade(code: code, folderName: folderName, because: problem)
            throw problem
        }

        return Prepared(
            folderName: folderName,
            displayCode: code,
            schoolYear: schoolYear,
            stagingURL: stagingURL,
            coursesDirectoryURL: coursesDirectoryURL,
            replacing: replacingFolder,
            madeGroupID: chosenGroupID,
            madeGroupName: groupName
        )
    }

    /// Finishes once setup has ended, or takes everything away again.
    ///
    /// In order: stopped by the teacher, setup failed, or the ready-made
    /// pages are not there → the hidden folder is removed (unlocked first,
    /// by `ReferenceStaging.remove`) and the failure line written. Otherwise
    /// the one dangerous sequence runs on it while it is still hidden, and
    /// one rename makes it visible. The claim is given back last, however it
    /// ended, after the tidy-up, so a sweep can never land in between.
    static func finish(
        _ prepared: Prepared,
        setupSucceeded: Bool,
        wasStopped: Bool,
        transcript: String
    ) throws -> ReferenceCopier.Made {
        defer {
            ReferenceStaging.giveBack(prepared.folderName, inCoursesDirectory: prepared.coursesDirectoryURL)
        }

        try ReferenceCreation.refuseUnlessTheRunFinished(
            prepared, setupSucceeded: setupSucceeded, wasStopped: wasStopped, transcript: transcript
        )

        let destinationURL: URL = prepared.coursesDirectoryURL.appendingPathComponent(prepared.folderName)
        let staged: ReferenceCopier.Made
        do {
            staged = try ReferenceCopier.makeIntoAReferenceCourse(
                at: prepared.stagingURL, schoolYear: prepared.schoolYear
            )
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                throw Problem.folderAlreadyExists(prepared.folderName)
            }
            // Where it goes, written BEFORE it becomes visible (plan review
            // H2): the chosen group, or no placement at all, so a folder
            // name freed by an earlier removal carries no stranger's group.
            ReferenceShelfStore.recordArrival(
                of: prepared.folderName,
                inMadeGroup: prepared.madeGroupID,
                coursesDirectoryURL: prepared.coursesDirectoryURL
            )
            try FileManager.default.moveItem(at: prepared.stagingURL, to: destinationURL)
        } catch {
            ReferenceStaging.remove(at: prepared.stagingURL)
            let made: Problem = .couldNotBeMade(code: prepared.displayCode)
            ReferenceCreation.noteNotMade(
                code: prepared.displayCode, folderName: prepared.folderName, because: made
            )
            throw made
        }

        let made: ReferenceCopier.Made = ReferenceCopier.Made(
            folderName: prepared.folderName,
            displayCode: staged.displayCode,
            schoolYear: staged.schoolYear,
            sectionCount: staged.sectionCount
        )
        ActivityTrail.note(
            .courseCreatedForReference, ReferenceCreation.trailLine(for: made, inGroup: prepared.madeGroupName)
        )
        return made
    }

    /// Finishes a course made to REPLACE a reference course (#572, second
    /// piece): the same checks of how setup ended as `finish`, the same one
    /// dangerous sequence on the hidden folder, and then, instead of a
    /// rename to a new folder, `ReferenceReplacer.replace`, which backs the
    /// old course up, checks the backup, and swaps the new one in under the
    /// old folder name. Nothing of the old course is touched before the new
    /// one is complete. The claim is given back last, however it ended.
    static func finishByReplacing(
        _ prepared: Prepared,
        setupSucceeded: Bool,
        wasStopped: Bool,
        transcript: String,
        world: ReferenceReplacer.World = ReferenceReplacer.World()
    ) async throws -> ReferenceCopier.Made {
        defer {
            ReferenceStaging.giveBack(prepared.folderName, inCoursesDirectory: prepared.coursesDirectoryURL)
        }
        guard let replacing = prepared.replacing else {
            // Giving the claim back twice is harmless: it is a set removal
            // and a lease file that is already gone.
            return try ReferenceCreation.finish(
                prepared, setupSucceeded: setupSucceeded, wasStopped: wasStopped, transcript: transcript
            )
        }

        try ReferenceCreation.refuseUnlessTheRunFinished(
            prepared, setupSucceeded: setupSucceeded, wasStopped: wasStopped, transcript: transcript
        )

        let staged: ReferenceCopier.Made
        do {
            staged = try ReferenceCopier.makeIntoAReferenceCourse(
                at: prepared.stagingURL, schoolYear: prepared.schoolYear
            )
        } catch {
            ReferenceStaging.remove(at: prepared.stagingURL)
            let made: Problem = .couldNotBeMade(code: prepared.displayCode)
            ReferenceCreation.noteNotMade(
                code: prepared.displayCode, folderName: prepared.folderName, because: made
            )
            throw made
        }

        do {
            _ = try await ReferenceReplacer.replace(
                ReferenceReplacer.Asked(
                    folderName: replacing, source: ReferenceCreation.replacementSource
                ),
                withStagedAt: prepared.stagingURL,
                coursesDirectoryURL: prepared.coursesDirectoryURL,
                world: world
            )
        } catch {
            // The replacer removed the new course and wrote its own line;
            // this one says no course was made, in the same sentence.
            ActivityTrail.note(
                .courseCouldNotBeCreatedForReference,
                ReferenceCreation.failureTrailLine(
                    code: prepared.displayCode,
                    folderName: prepared.folderName,
                    reason: error.localizedDescription
                )
            )
            throw error
        }

        let made: ReferenceCopier.Made = ReferenceCopier.Made(
            folderName: prepared.folderName,
            displayCode: staged.displayCode,
            schoolYear: staged.schoolYear,
            sectionCount: staged.sectionCount
        )
        ActivityTrail.note(.courseCreatedForReference, ReferenceCreation.trailLine(for: made))
        return made
    }

    /// Where a course made from the wizard came from, as the replace line
    /// says it.
    static let replacementSource: String = "a new course made from the ready-made pages"

    /// Whether the ready-made pages are really there (plan review H3): setup
    /// said it installed them, AND a page other than a folder's front page is
    /// in the hidden folder. Setup refuses to finish without them since
    /// #572, so this is the second of two locks on the same door: an older
    /// setup that carried on, or a line printed and nothing written, still
    /// leaves no empty locked course on the shelf.
    static func pagesLanded(at stagingURL: URL, transcript: String) -> Bool {
        if !transcript.contains(ReferenceCreation.pagesInstalledMarker) {
            return false
        }
        guard let walker = FileManager.default.enumerator(
            at: stagingURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        for case let fileURL as URL in walker {
            if fileURL.pathExtension.lowercased() != "md" {
                continue
            }
            if fileURL.lastPathComponent.lowercased() == "index.md" {
                continue
            }
            return true
        }
        return false
    }

    /// The trail line for a course that was made — what a teacher would
    /// recognise: the folder it was given, the code it shows, its year and
    /// sections, and that it began from the ready-made pages.
    ///
    /// `group` is the group the teacher made that it was put in (#572, third
    /// piece), quoted, or nil; a course filed by its year leaves the line it
    /// always did.
    static func trailLine(for made: ReferenceCopier.Made, inGroup group: String? = nil) -> String {
        var year: String = ReferenceImportWording.noSchoolYear
        if let startingYear = made.schoolYear {
            year = SchoolYear.label(forStartingYear: startingYear)
        }
        let sections: String = made.sectionCount == 1 ? "1 section" : "\(made.sectionCount) sections"
        var line: String = "created \(made.displayCode) for reference as \(made.folderName) — \(year), \(sections), "
             + "from the ready-made pages written for it"
        if let group {
            line += ", in the group \"\(group)\""
        }
        return line
    }

    /// The trail line for a course that was not made, and why — the reason
    /// is the sentence the teacher read.
    static func failureTrailLine(code: String, folderName: String?, reason: String) -> String {
        var line: String = "could not create \(code) for reference"
        if let folderName {
            line += " as \(folderName)"
        }
        return line + " — " + reason
    }

    // MARK: - Private helpers

    /// Stopped, failed, or without its pages: the hidden folder is removed
    /// and the failure line written, for `finish` and `finishByReplacing`
    /// alike.
    private static func refuseUnlessTheRunFinished(
        _ prepared: Prepared,
        setupSucceeded: Bool,
        wasStopped: Bool,
        transcript: String
    ) throws {
        var problem: Problem?
        if wasStopped {
            problem = .stopped
        } else if !setupSucceeded {
            problem = .couldNotBeMade(code: prepared.displayCode)
        } else if !ReferenceCreation.pagesLanded(at: prepared.stagingURL, transcript: transcript) {
            problem = .pagesDidNotLand(code: prepared.displayCode)
        }
        if let problem {
            ReferenceStaging.remove(at: prepared.stagingURL)
            ReferenceCreation.noteNotMade(
                code: prepared.displayCode, folderName: prepared.folderName, because: problem
            )
            throw problem
        }
    }

    private static func noteNotMade(code: String, folderName: String?, because problem: Problem) {
        ActivityTrail.note(
            .courseCouldNotBeCreatedForReference,
            ReferenceCreation.failureTrailLine(
                code: code, folderName: folderName, reason: problem.errorDescription ?? ""
            )
        )
    }
}
