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
    static func buttonTitle(for findings: [SiteHealthFinding]) -> String? {
        let repairable: [SiteHealthFinding] = findings.filter { finding in
            return canRepair(finding)
        }
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
            ActivityTrail.note(
                .folderProblemFound,
                "put the Media folder back",
                course: course.code, section: 0
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
                .folderProblemFound,
                "put the front page back",
                course: course.code, section: sectionNumber
            )
            return true
        } catch {
            return false
        }
    }
}
