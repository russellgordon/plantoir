import Foundation

/// Putting right the folder problems that CAN be put right.
///
/// Only two of the checks are fixable, and the line between them is the point:
/// a fix must restore the FEATURE, not merely satisfy the check. Recreating an
/// empty curriculum folder would silence "the curriculum map could not be
/// built" while leaving the map missing, so that one is never offered — a
/// button that makes a warning go away without fixing anything is worse than
/// no button, because the teacher then believes it is dealt with.
///
/// These two are different: a Media folder and a section's front page are
/// genuinely restorable, and an empty one of either is the correct starting
/// state rather than a pretence.
enum SiteHealthRepair {

    // MARK: - Functions

    /// Whether this app can put a finding right, as opposed to merely knowing
    /// that the toolchain called it fixable.
    ///
    /// Asked of the NAME rather than trusting the `fixable` flag on its own:
    /// the flag arrives from outside and says "this kind of thing is
    /// repairable", while what has to be true here is that THIS app has a
    /// repair for it.
    static func canRepair(_ finding: SiteHealthFinding) -> Bool {
        switch finding.name {
        case "mediaFolderMissing", "sectionIndexMissing":
            return finding.fixable
        default:
            return false
        }
    }

    /// What the button says. Plain, and about the teacher's course rather than
    /// about the check.
    static func repairable(among findings: [SiteHealthFinding]) -> [SiteHealthFinding] {
        var result: [SiteHealthFinding] = []
        for finding in findings {
            if canRepair(finding) {
                result.append(finding)
            }
        }
        return result
    }

    static func buttonTitle(for findings: [SiteHealthFinding]) -> String? {
        let repairable: [SiteHealthFinding] = repairable(among: findings)
        if repairable.isEmpty {
            return nil
        }
        if repairable.count == 1 && repairable[0].name == "mediaFolderMissing" {
            return "Put the Media folder back"
        }
        if repairable.count == 1 {
            return "Add the missing page"
        }
        return "Put them back"
    }

    /// What a repair did, ready to be shown.
    ///
    /// It exists so that a repair which FAILED is reported too. Both restore
    /// functions can return false — a read-only volume, a permissions problem,
    /// a file sitting where the folder should be — and reporting only success
    /// made a failed repair indistinguishable from a successful one: the alert
    /// simply closed either way. Silence on the failure path, in the feature
    /// written to end silence.
    struct Outcome: Equatable {

        // MARK: - Stored properties

        let headline: String
        let detail: String

        /// Whether to offer the preview. False when nothing was actually
        /// repaired (there is nothing to look at) and when a repair failed.
        let canRebuild: Bool
    }

    /// Repairs what can be repaired and describes the result, whatever it was.
    /// Where the teacher met the problem. It chooses the SENTENCE and nothing
    /// else — the preview is offered either way — so do not reach for it
    /// expecting it to gate behaviour.
    enum Occasion {
        case building
        case publishing
    }

    static func outcome(
        ofRepairing findings: [SiteHealthFinding], in course: Course,
        occasion: Occasion = .building
    ) -> Outcome? {
        let wanted: [SiteHealthFinding] = repairable(among: findings)
        if wanted.isEmpty {
            return nil
        }
        let attempts: [Attempt] = repair(wanted, in: course)

        // Each thing is named ONCE, however many findings produced it: two
        // sections both missing a front page are two repairs and one sentence,
        // and "Put the front page and the front page back." is not a sentence.
        var restored: [String] = []
        var failed: [String] = []
        // A repair the teacher must clear the way for before it can go ahead.
        // It is a failure — it goes into `failed` with the rest, so the
        // preview is not offered and "Could not put the front page back."
        // still appears — but it brings its own reason, and that reason
        // replaces the generic one below.
        //
        // Sorted before it is joined so that two of them — two sections each
        // with a folder in the way, or a second blocked cause should one ever
        // be added — land in one order every time. It is an alphabetical sort
        // of the SENTENCES, so it does not promise section order: "section10"
        // sorts before "section2". One stable order is all this needs.
        var reasonsItCouldNotGoAhead: [String] = []
        var somethingSimplyFailed: Bool = false
        for attempt in attempts {
            let name: String = attempt.finding.name
            switch attempt.result {
            case .restored:
                addOnce(name, to: &restored)
            case .failed:
                addOnce(name, to: &failed)
                somethingSimplyFailed = true
            case .blockedByAFolderWhereTheFrontPageBelongs(let sectionNumber):
                addOnce(name, to: &failed)
                // Two blocked sections are two DIFFERENT sentences — each one
                // names its own section folder — so both are wanted. What is
                // filtered here is the same sentence twice, which is what the
                // very same finding arriving twice would produce.
                addOnce(folderWhereTheFrontPageBelongs(
                    course: course.code, section: sectionNumber
                ), to: &reasonsItCouldNotGoAhead)
            case .alreadyFine:
                break
            }
        }
        restored.sort()
        failed.sort()
        reasonsItCouldNotGoAhead.sort()

        // Nothing to do: every one of them was already there. Pressing Fix
        // twice must not read as a permissions problem.
        if restored.isEmpty && failed.isEmpty {
            return Outcome(
                headline: "That is already put right.",
                detail: "Nothing needed changing.",
                canRebuild: false
            )
        }

        // Why it could not go ahead, in the order a teacher reads it.
        //
        // The generic explanation is added only when something failed for a
        // reason nobody has a better sentence for — and it goes FIRST, with
        // the specific refusals after it. Both orders were read aloud. Putting
        // the refusal first ends the paragraph on "You can make it yourself in
        // Obsidian", immediately after "…and Plantoir can put the front page
        // back", so "it" lands on the front page — the one thing that cannot
        // be made until the folder in the way has been moved. This order ends
        // instead on the step the teacher can actually take.
        //
        // Reachable only when a file sits where Media belongs AND a folder
        // sits where the front page belongs, in one course, at one moment.
        // Rare, and it still has to read properly.
        var whyNotInOrder: [String] = []
        if somethingSimplyFailed || reasonsItCouldNotGoAhead.isEmpty {
            whyNotInOrder.append(couldNotExplanation)
        }
        for reason in reasonsItCouldNotGoAhead {
            whyNotInOrder.append(reason)
        }
        let whyNot: String = whyNotInOrder.joined(separator: " ")

        if restored.isEmpty {
            return Outcome(
                headline: "Plantoir could not put that back.",
                detail: whyNot,
                canRebuild: false
            )
        }

        let putBack: String = whatWasPutBack(restored) ?? ""

        // A PARTIAL failure said nothing about the half that did not come
        // back — silence whenever anything else succeeded, in the type added
        // so that failure would not be silent.
        if let alsoFailed = whatCouldNotBePutBack(failed) {
            return Outcome(
                headline: putBack,
                detail: alsoFailed + " " + whyNot,
                canRebuild: false
            )
        }

        // A preview is offered on BOTH occasions: after a publish it is how the
        // teacher checks the repair worked, and the wording carries the part a
        // preview cannot do.
        switch occasion {
        case .building:
            return Outcome(headline: putBack, detail: notOnTheSiteYet, canRebuild: true)
        case .publishing:
            return Outcome(headline: putBack, detail: notPublishedYet, canRebuild: true)
        }
    }

    static let couldNotExplanation: String =
        "You can make it yourself in Obsidian, or check that the folder holding "
        + "this course isn't locked or read-only."

    /// What a teacher is told when a FOLDER is sitting where a section's front
    /// page belongs.
    ///
    /// Named here and pinned to `contracts/shared-rules.json` →
    /// `siteHealth.repair.refusedWhenSomethingIsInTheWay`, so the two apps say
    /// one sentence about one problem rather than inventing two.
    ///
    /// It names the COURSE as well as the section folder because every course
    /// has a `section1`, and the dialog this appears in shows only a headline
    /// and this sentence — nothing else in it says which course is meant.
    static func folderWhereTheFrontPageBelongs(
        course courseCode: String, section sectionNumber: Int
    ) -> String {
        return "There is a folder called index.md in the section\(sectionNumber) folder "
            + "of your \(courseCode) course, where the front page should be. Plantoir "
            + "has left it exactly as it is, in case your own pages are inside it. Move "
            + "anything you want to keep somewhere else, then delete or rename that "
            + "folder, and Plantoir can put the front page back."
    }

    static func whatCouldNotBePutBack(_ names: [String]) -> String? {
        guard let described = whatWasPutBack(names) else {
            return nil
        }
        // "Put the front page back." -> "Could not put the front page back."
        return "Could not " + described.prefix(1).lowercased() + described.dropFirst()
    }

    /// What was put back, in words a teacher can check against their folder.
    ///
    /// A repair whose outcome is invisible is a repair nobody trusts the second
    /// time — and the Media folder in particular is somewhere a teacher cannot
    /// see from this app, so silence after pressing the button is
    /// indistinguishable from nothing having happened.
    static func whatWasPutBack(_ repairedNames: [String]) -> String? {
        var parts: [String] = []
        for name in repairedNames {
            switch name {
            case "mediaFolderMissing":
                parts.append("the Media folder")
            case "sectionIndexMissing":
                parts.append("the front page")
            default:
                break
            }
        }
        if parts.isEmpty {
            return nil
        }
        if parts.count == 1 {
            return "Put \(parts[0]) back."
        }
        return "Put " + parts.dropLast().joined(separator: ", ")
            + " and " + (parts.last ?? "") + " back."
    }

    /// Why the preview does not show the repair yet.
    ///
    /// The folder is back on disk and the preview still shows how things were.
    /// Left unsaid, "Put the Media folder back" reads as though everything is
    /// fixed — the same silent gap as a warning nobody sees.
    ///
    /// **"Preview", not "build" — for CLARITY, not because "build" is
    /// forbidden.** The app says "build" in plenty of places a teacher reads
    /// ("Click Preview to build this section's website"), and that is fine. The
    /// problem with a button labelled "Build Again" was that it did not say
    /// WHAT would be built, and the thing on offer already has a name the
    /// teacher knows. An earlier version of this comment claimed "building is
    /// machinery"; it is not, and that claim would have justified rewriting
    /// eight other strings for no gain.
    static let notOnTheSiteYet: String =
        "Your preview still shows how things were before this. "
        + "Preview it again to see the change."

    /// The same, for a teacher whose repair followed a PUBLISH.
    ///
    /// **The preview is still offered here**, which is a change of mind worth
    /// recording. It was withheld on the grounds that a preview does not change
    /// what students see — true, but it conflates two things. The teacher has
    /// just put a folder back and quite reasonably wants to SEE that it worked,
    /// and a preview is exactly how. What a preview does NOT do is update the
    /// published site, and that is a job for the sentence, not for removing the
    /// button: withholding it took away something useful to prevent a
    /// misunderstanding the words already prevent.
    ///
    /// So this says both halves — what a preview will show them, and what only
    /// publishing can do.
    ///
    /// Careful with the tense: this sentence is ALSO shown when a deploy
    /// FAILED, and for a section publishing for the first time nothing has ever
    /// gone out. An earlier version said "students still see the site as it was
    /// when you last published", which asserts a publish that may never have
    /// happened. This one is true either way.
    static let notPublishedYet: String =
        "Publishing is what puts this in front of students, so it is not on "
        + "their site until you publish again. You can preview it now to check "
        + "the change looks right."

    /// How one repair went.
    ///
    /// `alreadyFine` is a THIRD answer, and leaving it out was a bug: both
    /// restores return false when the folder is already there, which is the
    /// documented idempotent path — pressing Fix twice, or pressing it after
    /// putting the folder back in Obsidian. Folding that into "failed" told a
    /// teacher "Plantoir could not put that back… check the folder isn't
    /// locked or read-only" about a course that was perfectly all right.
    enum Result: Equatable {
        case restored
        case alreadyFine
        case failed
        /// A repair that cannot go ahead until the TEACHER moves something.
        ///
        /// Counted as a failure, because it is one — but it carries its own
        /// explanation, and that is the whole point of the case. A folder
        /// named `index.md` used to satisfy a bare `fileExists` check and be
        /// reported as "already put right", while the section still had no
        /// front page; answering `failed` instead would at least be honest,
        /// but the sentence that goes with it — "check the folder isn't
        /// locked or read-only" — sends a teacher looking for the wrong
        /// thing entirely.
        ///
        /// It carries the SECTION rather than the sentence: this type says
        /// how a repair went, and `outcome(ofRepairing:in:)` chooses every
        /// word in this file.
        case blockedByAFolderWhereTheFrontPageBelongs(section: Int)
    }

    /// One finding, and how its repair went.
    ///
    /// It exists so that the answer cannot COLLAPSE. This used to come back as
    /// a dictionary keyed by the check's NAME, and two findings share a name
    /// as soon as two sections are involved: two sections each missing a front
    /// page are two repairs, both of which run, but only the last result was
    /// reported. "Section 1 restored, section 2 was already there" therefore
    /// read as "That is already put right. Nothing needed changing." — with no
    /// preview offered — for a repair that really had put a page back.
    ///
    /// **It was unreachable from the app**, and is fixed anyway. A section
    /// window owns one runner and the checks announce per section, so the
    /// findings handed to a repair have always been one section's. What makes
    /// it worth an hour is that the collapse was SILENT and the constraint was
    /// written down nowhere: the next caller — the assistant, a second window,
    /// a whole-course fix — would have met it as a wrong report rather than as
    /// a compile error. Windows found it by porting this file line by line
    /// (documentation/04-course-setup.md, 2026-09-06) and shipped this shape first; the mac is
    /// catching up to it rather than inventing it.
    ///
    /// One thing it does NOT fix, deliberately. Section 1 restored and section
    /// 2 FAILED, both `sectionIndexMissing`, still reads "Put the front page
    /// back." followed by "Could not put the front page back." — one name, two
    /// outcomes, and the sentence has no way to say which section is which.
    /// Windows reads the same way. Inventing wording for it was rejected: it
    /// is as unreachable as the collapse was, and a sentence nobody has
    /// weighed is harder to take back than a paragraph of explanation. The
    /// blocked case does not have the problem on EITHER platform — its own
    /// sentence names the section folder. Windows adopted the named refusal on
    /// 2026-09-07; until then a blocked section there fell into `failed` and
    /// read namelessly too, which is what this comment used to describe. Pinned
    /// over there by SiteHealthRepairTests
    /// .TwoRefusedSectionsAreTwoSentencesBecauseEachNamesItsOwnFolder.
    struct Attempt: Equatable {

        // MARK: - Stored properties

        let finding: SiteHealthFinding
        let result: Result
    }

    /// Adds a name, or a sentence, only if it is not already there.
    ///
    /// What a teacher is told is a list of DISTINCT things, however many
    /// findings produced them — see `Attempt`.
    private static func addOnce(_ value: String, to list: inout [String]) {
        if list.contains(value) {
            return
        }
        list.append(value)
    }

    /// Repairs what can be repaired, and reports what each one did — one
    /// `Attempt` per finding, in the order they were given.
    ///
    /// Never overwrites: every repair checks first, so pressing the button
    /// twice, or pressing it after fixing the problem in Obsidian, changes
    /// nothing.
    @discardableResult
    static func repair(
        _ findings: [SiteHealthFinding], in course: Course
    ) -> [Attempt] {
        var attempts: [Attempt] = []
        for finding in findings where canRepair(finding) {
            switch finding.name {
            case "mediaFolderMissing":
                attempts.append(Attempt(
                    finding: finding, result: restoreMedia(in: course)
                ))
            case "sectionIndexMissing":
                attempts.append(Attempt(
                    finding: finding,
                    result: restoreIndex(forSection: finding.section, in: course)
                ))
            default:
                break
            }
        }
        return attempts
    }

    static func restoreMedia(in course: Course) -> Result {
        let url: URL = course.directoryURL.appendingPathComponent("Media")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            // A FILE where the folder belongs is not "already fine".
            return isDirectory.boolValue ? .alreadyFine : .failed
        }
        return restoreMediaFolder(in: course) ? .restored : .failed
    }

    static func restoreIndex(forSection sectionNumber: Int, in course: Course) -> Result {
        guard course.configuration.sectionNumbers.contains(sectionNumber) else {
            return .failed
        }
        let index: URL = course.sectionDirectoryURL(forSection: sectionNumber)
            .appendingPathComponent("index.md")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: index.path, isDirectory: &isDirectory) {
            // A FOLDER named `index.md` is not "already fine" — the section
            // still has no front page, so the build still produces no site and
            // the publish still refuses. Without the `isDirectory:` form this
            // reported the one dialog written to end silence as "that is
            // already put right", which is the worst answer available: the
            // teacher stops looking.
            //
            // And it REFUSES rather than clearing the way. Moving the folder
            // aside and writing a proper front page was considered and
            // rejected: that relocates a folder which may hold the teacher's
            // own pages, without asking, and neither app can see what is
            // inside it.
            if isDirectory.boolValue {
                ActivityTrail.note(
                    .folderProblemNotRepaired,
                    "found a folder called index.md where the front page belongs, "
                    + "and left it alone",
                    course: course.code, section: sectionNumber
                )
                return .blockedByAFolderWhereTheFrontPageBelongs(section: sectionNumber)
            }
            return .alreadyFine
        }
        return restoreSectionIndex(forSection: sectionNumber, in: course) ? .restored : .failed
    }

    /// An empty `Media` folder beside the course, which is exactly what a new
    /// course gets — the pictures themselves are the teacher's and cannot be
    /// conjured back.
    static func restoreMediaFolder(in course: Course) -> Bool {
        let url: URL = course.directoryURL.appendingPathComponent("Media")
        if FileManager.default.fileExists(atPath: url.path) {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            // Not `course:section:` — Media belongs to the whole course, and
            // that overload stamps a section number into the line. Writing
            // `ICS3U/0` would name a section that does not exist.
            ActivityTrail.note(
                .folderProblemRepaired,
                course.code + " · put the Media folder back"
            )
            return true
        } catch {
            return false
        }
    }

    /// A section's front page, with the frontmatter every page here carries.
    ///
    /// Deliberately almost empty: this is the page a teacher will write, and
    /// inventing content for it would be putting words in their mouth. What it
    /// must have is a title, or the site shows the file name.
    static func restoreSectionIndex(forSection sectionNumber: Int, in course: Course) -> Bool {
        // A finding's section number is parsed from the build's output and
        // falls back to 0 when it is missing or the wrong type. Creating a
        // `section0` folder because a line was malformed would be inventing
        // structure the course does not have.
        guard course.configuration.sectionNumbers.contains(sectionNumber) else {
            return false
        }
        let sectionURL: URL = course.sectionDirectoryURL(forSection: sectionNumber)
        let indexURL: URL = sectionURL.appendingPathComponent("index.md")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            return false
        }
        let page: String = """
        ---
        title: \(course.configuration.courseName)
        ---

        """
        do {
            try FileManager.default.createDirectory(
                at: sectionURL, withIntermediateDirectories: true
            )
            try page.write(to: indexURL, atomically: true, encoding: .utf8)
            ActivityTrail.note(
                .folderProblemRepaired,
                "put the front page back",
                course: course.code, section: sectionNumber
            )
            return true
        } catch {
            return false
        }
    }
}
