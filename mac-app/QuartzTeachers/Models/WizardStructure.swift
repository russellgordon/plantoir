import Foundation

/// The five lists the New Course wizard's structure editor holds, and the two
/// things the skeleton toggle does to them.
///
/// **The editor must show what will actually be created, in both directions**
/// (Russell, 2026-09-06, deciding it for Windows; the mac copies it). Turning
/// the toggle ON adopts the subject's folders; turning it OFF puts the generic
/// defaults back. A one-way adoption was this feature's bug in miniature: a
/// teacher who typed SNC4M, watched Investigations and Concepts appear and
/// then turned the toggle off was shown — and got — the science skeleton's
/// folders with none of its pages, while the file said `use_skeleton: false`.
///
/// The restore is list by list, against a SNAPSHOT of what the adoption put
/// there: a list the teacher has edited since is theirs and is left exactly as
/// it is, and only the untouched ones go back. Equality is by VALUE rather
/// than a dirty flag — see `restoringDefaults(in:adopted:usesLCSTerminology:)`
/// for what that buys and what it costs.
///
/// Pure on purpose: the view owns `@State`, which never takes on a view that
/// is not on screen, so every rule worth testing lives here and the view is
/// left with two one-line call sites. Pinned by
/// `contracts/shared-rules.json` → `wizard.skeletonToggle`, which both apps
/// run. Windows' half is `NewCourseDialog.AdoptSkeletonStructure` /
/// `RestoreGenericStructure`.
enum WizardStructure {

    // MARK: - Types

    /// What the structure editor is showing: the four editable lists, plus
    /// the marks pool that follows them.
    struct Lists: Equatable {

        // MARK: - Stored properties

        let sharedFolders: [String]
        let sharedFiles: [String]
        let perSectionFolders: [String]
        let perSectionFiles: [String]
        let gradedFolders: [String]
    }

    // MARK: - Functions

    /// The lists a subject's skeleton asks for.
    ///
    /// The marks pool comes from `SkeletonCatalog.adoptedGradedFolders(for:)`
    /// rather than being worked out here, so that the manifest's own
    /// `graded_folders` wins where it names any — the mathematics family ships
    /// `Thinking Tasks`, and a course that lost it would lose those marks
    /// silently.
    static func adopting(_ family: SkeletonCatalog.Family) -> Lists {
        return Lists(
            sharedFolders: family.sharedFolders,
            sharedFiles: family.sharedFiles,
            perSectionFolders: family.perSectionFolders,
            perSectionFiles: family.perSectionFiles,
            gradedFolders: SkeletonCatalog.adoptedGradedFolders(for: family)
        )
    }

    /// The other direction: the toggle went off, so each list the teacher has
    /// NOT touched since the adoption goes back to the factory default — the
    /// LCS variant for the two shared lists when the terminology switch is on,
    /// since that is what a brand-new course with that switch would have
    /// opened with.
    ///
    /// - Parameter adopted: what the last adoption put into the editor, or nil
    ///   when nothing has been adopted — in which case there is nothing to
    ///   recognise as untouched and NOTHING changes. (Windows returns early;
    ///   same answer.)
    ///
    /// Three consequences of asking the question by VALUE rather than keeping
    /// a dirty flag, each deliberate:
    ///
    /// - A list the teacher edited and then edited BACK to exactly what the
    ///   adoption set is restored along with the untouched ones. That is
    ///   intended: what is on screen is what the adoption put there, and a
    ///   teacher cannot see the difference between a list they never touched
    ///   and one they have put back.
    /// - The two shared lists are what the LCS switch REWRITES, so flipping it
    ///   after an adoption leaves them unequal to the snapshot and they stay
    ///   as the switch left them. The per-section lists, which have no LCS
    ///   variant, still go back.
    /// - The marks pool can never name a folder that has just left the
    ///   editor, and it takes two rules to keep that true. A pool still equal
    ///   to the adoption's is RE-INFERRED over the restored folders; a pool
    ///   the teacher has ticked themselves is theirs and is kept, but
    ///   NARROWED to the folders the course will actually have. Without the
    ///   second, a teacher who adopted the mathematics skeleton, unticked
    ///   `Tasks` and then declined the skeleton is shown a checklist with
    ///   nothing ticked while the wizard writes
    ///   `graded_folders: ["Thinking Tasks"]` — a name no folder of theirs
    ///   matches, and a DIFFERENT file from the one Windows writes for the
    ///   same clicks. (Nothing narrows it after this: since GitHub issue #192
    ///   `setup_course.py` writes a saved pool back as it was —
    ///   `gradedFolders.rerunningSetup` — so what the wizard writes, the
    ///   course keeps.)
    ///   Windows reaches the same answer from the other end: it leaves the
    ///   pool alone here and narrows it on every read
    ///   (`CurrentGradedFolders`) and again when the file is written.
    static func restoringDefaults(
        in current: Lists,
        adopted: Lists?,
        usesLCSTerminology: Bool
    ) -> Lists {
        guard let adopted else {
            return current
        }

        var sharedFolders: [String] = current.sharedFolders
        if current.sharedFolders == adopted.sharedFolders {
            sharedFolders = usesLCSTerminology
                ? WizardDefaults.lcsSharedFolders
                : WizardDefaults.sharedFolders
        }

        var sharedFiles: [String] = current.sharedFiles
        if current.sharedFiles == adopted.sharedFiles {
            sharedFiles = usesLCSTerminology
                ? WizardDefaults.lcsSharedFiles
                : WizardDefaults.sharedFiles
        }

        // No LCS variant exists for either per-section list: the terminology
        // switch changes only the shared ones, so these go back to the plain
        // defaults whatever it is set to.
        var perSectionFolders: [String] = current.perSectionFolders
        if current.perSectionFolders == adopted.perSectionFolders {
            perSectionFolders = WizardDefaults.perSectionFolders
        }

        var perSectionFiles: [String] = current.perSectionFiles
        if current.perSectionFiles == adopted.perSectionFiles {
            perSectionFiles = WizardDefaults.perSectionFiles
        }

        let foldersTheCourseWillHave: [String] = sharedFolders + perSectionFolders
        var gradedFolders: [String] = GradedFolderRule.reconciled(
            current.gradedFolders, toFolders: foldersTheCourseWillHave
        )
        if current.gradedFolders == adopted.gradedFolders {
            gradedFolders = GradedFolderRule.inferredPool(from: foldersTheCourseWillHave)
        }

        return Lists(
            sharedFolders: sharedFolders,
            sharedFiles: sharedFiles,
            perSectionFolders: perSectionFolders,
            perSectionFiles: perSectionFiles,
            gradedFolders: gradedFolders
        )
    }
}
