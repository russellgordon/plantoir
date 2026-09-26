import Foundation

/// What removing a FOLDER from a course does to its marks pool —
/// `contracts/shared-rules.json` → `gradedFolders.removingAFolder`.
///
/// Lifted out of `CourseSettingsView.dropFromMarksPool` (issue #152) so that
/// the removal and the marks floor (`MarksFloor`) ask ONE function what a
/// removal leaves in the pool: the floor asks it about a removal that has not
/// happened yet, with the choices worked out in memory, and the removal asks
/// it after the exclusion has been written, with the choices walked again.
/// Two copies of the rule could disagree about whether a pool survives, and
/// the floor would then refuse or allow on the strength of a pool the
/// removal never leaves.
///
/// The ORDER is not here and must not move here: the caller computes
/// `choicesAfter` AFTER the name has left its list and been written into
/// `excluded_items` (`CourseSettingsView.folderWasRemoved`), which is what
/// issue #183's must-fails pin.
nonisolated enum MarksPoolRemoval {

    // MARK: - Functions

    /// The pool once `name` has been removed from the course, given what the
    /// Marks checklist offers after the removal — or nil for a course that
    /// has never been asked, which stays unasked.
    ///
    /// The name leaves the pool with its folder, so the confirmation's promise
    /// ("Removing it will take it out of your course's marks pool") is kept
    /// and `graded_folders` never names a folder the build has been told to
    /// exclude — with two exceptions, both of which exist to stop a removal
    /// quietly taking marks OFF the coverage map.
    ///
    /// Only the removed NAME is ever dropped. A pooled name found only INSIDE
    /// the removed folder (`Tasks`, found only at `Portfolios/Tasks`, when
    /// `Portfolios` is removed) stays in the pool: putting `Portfolios` back
    /// restores the marks, where dropping `Tasks` would lose them silently on
    /// that same undo. That is `removingAFolder` case 8 (#152, from #80's
    /// first item), and the harm the kept name could do — holding up the
    /// marks floor while nothing counts — is closed by `MarksFloor`, which
    /// counts only names found on disk.
    static func poolAfterRemoving(_ name: String, from pool: [String]?, choicesAfter: [String]) -> [String]? {
        // Still offered? Then a folder of that name is still in the course —
        // `Portfolios/Tasks`, when the top-level `Tasks` was the one removed —
        // and the pool entry still names work the build publishes. Dropping it
        // would stop counting a folder nobody removed, and the checklist would
        // go on showing an untickable row for it.
        //
        // Asked CASE-INSENSITIVELY, because the walk returns on-disk spellings:
        // `Portfolios/tasks` is offered as `tasks`, and an exact test would
        // read that as "no longer offered" while `build_site.py` goes on
        // counting the folder. Seventh case of `gradedFolders.removingAFolder`,
        // raised from Windows as issue #172; the comparison itself, and what
        // was measured to choose it, are in `GradedFolderChoices.stillOffers`.
        if GradedFolderChoices.stillOffers(choicesAfter, aFolderNamed: name) {
            return pool
        }
        // A course that has NEVER been asked is left unasked, rather than
        // frozen to the historical rule's answer minus this folder. On the
        // ordinary course whose only marked folder is `Tasks`, freezing writes
        // `[]` — asked and answered, nothing counting for marks ever again,
        // from a gesture the teacher was told would take one folder out of the
        // pool. An absent key keeps the historical rule running instead.
        //
        // **This guard is not what makes the never-asked cases pass today, and
        // it must not be "simplified" away.** The post-exclusion walk is: the
        // historical rule only ever names folders drawn FROM the choices
        // (`GradedFolderRule.inferredPool(from:)` reads that list), so a name
        // the still-offered test has just rejected cannot be in a materialised
        // pool either. That redundancy holds only while the DROP below is no
        // more permissive than the still-offered test above — which is this
        // file's shape (a case-insensitive test over an exact drop) and
        // Windows' shape (one comparer for both). Reverse it — an exact test
        // over a case-insensitive drop — and this guard is the only thing left
        // standing.
        //
        // Measured ON WINDOWS 2026-09-18, on code whose drop is
        // `OrdinalIgnoreCase`: with an exact still-offered test and this guard
        // replaced by the materialised pool, a never-asked course that removes
        // a top-level `Tasks` while `Portfolios/tasks` survives writes
        // `graded_folders: []` — the #142 damage, back. The mac's own drop is
        // exact, so that mutation stops one line lower instead, at
        // `!pool.contains(name)`: the materialised pool is `["tasks"]` and the
        // name is `"Tasks"`. Do not read the `[]` as a mac number, and do not
        // conclude from a green suite that the guard is dead.
        guard let pool else {
            return nil
        }
        if !pool.contains(name) {
            return pool
        }
        var remaining: [String] = []
        for folder in pool {
            if folder != name {
                remaining.append(folder)
            }
        }
        return remaining
    }
}
