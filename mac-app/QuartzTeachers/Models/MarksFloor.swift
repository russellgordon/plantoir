import Foundation

/// The "at least one folder must count for marks" floor in Course Settings —
/// `contracts/shared-rules.json` → `gradedFolders.floor` (issue #152, from
/// #80's second item).
///
/// While the coverage map is on, a removal or an untick is REFUSED when,
/// before it, at least one pooled name names a folder found on disk, and after
/// it none does. The same comparison decides whether a removal is ASKED
/// about: when it changes the pool, or takes a pooled name from found to not
/// found.
///
/// **Why "found on disk", and why "would the pool survive".** The floor used
/// to ask whether the folder was the LAST NAME in the pool, without looking
/// at the disk, and that cut both ways: a pooled name whose folder had been
/// deleted refused its own removal on the strength of a folder that was not
/// there, and it let the last REAL folder go while it sat in the pool beside
/// it — every expectation then reads as never evaluated on the coverage map.
/// A pooled name kept after its parent was removed (`removingAFolder` case 8)
/// is the same phantom. Asking whether the pool survives, rather than whether
/// this is the last name, also stops refusing the removal of a top-level
/// `Tasks` that `Portfolios/Tasks` keeps counting.
///
/// Pure: the caller walks the disk once (`snapshot`) and asks as often as it
/// likes. Course Settings walks once per drawing, again when its window
/// becomes key, and afresh for the row a teacher acts on — see
/// `CourseSettingsView.marksSnapshot()`.
nonisolated enum MarksFloor {

    // MARK: - Types

    /// What the page's marks questions are answered from: one walk of the
    /// course folder, and what the Marks checklist offers from it.
    struct Snapshot: Sendable {

        // MARK: - Stored properties

        /// Every folder the walk found, EVERY occurrence, with where.
        let walked: [GradedFolderChoices.WalkedFolder]

        /// What the Marks checklist offers — `GradedFolderChoices.choices`.
        let choices: [String]
    }

    /// The settings a floor question reads.
    struct Settings: Sendable {

        // MARK: - Stored properties

        let sharedFolders: [String]
        let perSectionFolders: [String]

        /// `graded_folders`, or nil when the course has never been asked.
        let gradedFolders: [String]?

        let includesCurriculumCoverage: Bool
    }

    /// What the teacher is about to do.
    enum Gesture: Sendable {
        /// Untick a folder in the Marks checklist.
        case untick(String)
        /// Remove a folder from the shared or per-section folder list.
        case remove(String, FolderScope)
    }

    /// What Course Settings does about it — the contract's three outcomes.
    enum Outcome: Equatable, Sendable {
        /// Blocked, with `SpecialNames.lastGradedFolderBlocked`.
        case refused
        /// Asked first, with the graded removal confirmation.
        case confirmed
        /// Neither: it simply happens.
        case ordinary
    }

    // MARK: - Functions

    /// Walks the course folder once and works out what the checklist offers
    /// from that walk.
    static func snapshot(
        sharedFolders: [String],
        perSectionFolders: [String],
        courseDirectory: URL,
        excludedShared: [String],
        excludedPerSection: [String]
    ) -> Snapshot {
        let walked: [GradedFolderChoices.WalkedFolder] = GradedFolderChoices.walkedFolders(
            inCourseDirectory: courseDirectory,
            excludedShared: excludedShared,
            excludedPerSection: excludedPerSection
        )
        let choices: [String] = GradedFolderChoices.choices(
            sharedFolders: sharedFolders,
            perSectionFolders: perSectionFolders,
            nestedNames: GradedFolderChoices.names(of: walked)
        )
        return Snapshot(walked: walked, choices: choices)
    }

    /// What Course Settings does about one gesture.
    static func outcome(of gesture: Gesture, settings: Settings, snapshot: Snapshot) -> Outcome {
        // A course never asked is floored by what the historical rule counts,
        // read off the same list the checklist shows ticked.
        var poolBefore: [String] = GradedFolderRule.inferredPool(from: snapshot.choices)
        if let chosen = settings.gradedFolders {
            poolBefore = chosen
        }
        // A walk that finds no folder at all counts every pooled name as
        // found, before and after — the old rule, kept so an unreadable or
        // empty course folder cannot switch the floor off (case F11).
        let countsEveryName: Bool = snapshot.walked.isEmpty
        let namesBefore: [String] = GradedFolderChoices.names(of: snapshot.walked)
        let foundBefore: [String] = pooledNamesFound(poolBefore, among: namesBefore, countsEveryName: countsEveryName)

        switch gesture {
        case .untick(let name):
            if !settings.includesCurriculumCoverage {
                return .ordinary
            }
            let poolAfter: [String] = without(name, in: poolBefore)
            let foundAfter: [String] = pooledNamesFound(poolAfter, among: namesBefore, countsEveryName: countsEveryName)
            if !foundBefore.isEmpty && foundAfter.isEmpty {
                return .refused
            }
            return .ordinary

        case .remove(let name, let scope):
            // "After" is the removal rule's own answer: the walk without what
            // the exclusion takes off the site, the lists without the name,
            // and the pool as `removingAFolder` leaves it.
            let walkedAfter: [GradedFolderChoices.WalkedFolder] = GradedFolderChoices.walkedFolders(
                snapshot.walked, withoutFolderNamed: name, scope: scope
            )
            let namesAfter: [String] = GradedFolderChoices.names(of: walkedAfter)
            var sharedAfter: [String] = settings.sharedFolders
            var perSectionAfter: [String] = settings.perSectionFolders
            switch scope {
            case .shared:
                sharedAfter = without(name, in: sharedAfter)
            case .perSection:
                perSectionAfter = without(name, in: perSectionAfter)
            }
            let choicesAfter: [String] = GradedFolderChoices.choices(
                sharedFolders: sharedAfter, perSectionFolders: perSectionAfter, nestedNames: namesAfter
            )
            var poolAfter: [String] = GradedFolderRule.inferredPool(from: choicesAfter)
            if let kept = MarksPoolRemoval.poolAfterRemoving(
                name, from: settings.gradedFolders, choicesAfter: choicesAfter
            ) {
                poolAfter = kept
            }
            let foundAfter: [String] = pooledNamesFound(poolAfter, among: namesAfter, countsEveryName: countsEveryName)

            if settings.includesCurriculumCoverage && !foundBefore.isEmpty && foundAfter.isEmpty {
                return .refused
            }
            // Asked about when the marks change, and only then, so the
            // confirmation's two sentences stay true: the pool loses a name
            // ("take it out of your course's marks pool"), or a pooled folder
            // stops being found — `Portfolios/Tasks`, when `Portfolios` goes
            // (case F9). Removing a top-level `Tasks` that `Portfolios/Tasks`
            // keeps changes neither, and is not asked about (F7, F16).
            if poolAfter != poolBefore {
                return .confirmed
            }
            for pooledName in foundBefore {
                if !foundAfter.contains(pooledName) {
                    return .confirmed
                }
            }
            return .ordinary
        }
    }

    /// The pooled names found among the walked names, asked the way the build
    /// asks it (case ignored) — or every pooled name, when the walk found
    /// nothing at all.
    static func pooledNamesFound(_ pool: [String], among walkedNames: [String], countsEveryName: Bool) -> [String] {
        var found: [String] = []
        for pooledName in pool {
            if countsEveryName || GradedFolderChoices.stillOffers(walkedNames, aFolderNamed: pooledName) {
                found.append(pooledName)
            }
        }
        return found
    }

    /// A list without every entry exactly equal to `name` — what a list
    /// editor's removal and a checklist untick both do.
    static func without(_ name: String, in list: [String]) -> [String] {
        var kept: [String] = []
        for entry in list {
            if entry != name {
                kept.append(entry)
            }
        }
        return kept
    }
}
