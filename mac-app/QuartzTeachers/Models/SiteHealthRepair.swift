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

        /// Whether offering to build again makes sense — it does not when
        /// nothing was actually repaired.
        let canRebuild: Bool
    }

    /// Repairs what can be repaired and describes the result, whatever it was.
    /// Where the teacher met the problem, which decides what they are offered
    /// next: a fresh preview means nothing to somebody whose site is published.
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
        let repaired: [String] = repair(wanted, in: course)
        if let putBack = whatWasPutBack(repaired) {
            switch occasion {
            case .building:
                return Outcome(headline: putBack, detail: notOnTheSiteYet, canRebuild: true)
            case .publishing:
                return Outcome(headline: putBack, detail: notPublishedYet, canRebuild: false)
            }
        }
        return Outcome(
            headline: "Plantoir could not put that back.",
            detail: "Nothing was changed. You can make the folder yourself in "
                  + "Obsidian, or check that the folder holding this course "
                  + "isn't locked or read-only.",
            canRebuild: false
        )
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

    /// Why the site does not show the repair yet.
    ///
    /// The folder is back on disk, and the built site still reflects how things
    /// were when it was made. Left unsaid, "Put the Media folder back" reads as
    /// though the site is fixed — which is the same silent gap as a warning
    /// nobody sees.
    static let notOnTheSiteYet: String =
        "Your site still shows how things were when it was last built. "
        + "Build it again to see the difference."

    /// The same, for a teacher whose site is already PUBLISHED.
    ///
    /// Building again produces a fresh preview, which is not what they will go
    /// and look at: the site students see is the published one, and only
    /// publishing again changes it. Offering "Build Again" there would promise
    /// a difference that never appears online — the same confusion one level
    /// up from the one this whole alert exists to remove.
    static let notPublishedYet: String =
        "Your published site still shows how things were when it was last "
        + "published. Publish again when you are ready."

    /// Repairs what can be repaired, and reports what it did.
    ///
    /// Never overwrites: every repair checks first, so pressing the button
    /// twice, or pressing it after fixing the problem in Obsidian, changes
    /// nothing.
    @discardableResult
    static func repair(
        _ findings: [SiteHealthFinding], in course: Course
    ) -> [String] {
        var repaired: [String] = []
        for finding in findings where canRepair(finding) {
            switch finding.name {
            case "mediaFolderMissing":
                if restoreMediaFolder(in: course) {
                    repaired.append(finding.name)
                }
            case "sectionIndexMissing":
                if restoreSectionIndex(forSection: finding.section, in: course) {
                    repaired.append(finding.name)
                }
            default:
                break
            }
        }
        return repaired
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
