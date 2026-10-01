using Plantoir.Core.Models;

namespace Plantoir.Core.Catalogs;

/// <summary>
/// What the New Course wizard's structure editor holds, as five lists — and
/// the two moves that change all of them at once: adopting a subject's
/// skeleton, and putting the defaults back when the skeleton is turned down.
///
/// <para>Pure, and that is the reason it exists (GitHub issue #169). The rule
/// lived inside <c>NewCourseDialog.RestoreGenericStructure</c>, which is
/// private and reads fields, so <c>shared-rules.json</c> →
/// <c>wizard.skeletonToggle</c> — the cases the mac copied FROM this app —
/// could not be run here at all. The dialog now holds two thin call sites and
/// <c>WizardSkeletonToggleTests</c> plays every case through these functions.
/// Mirrors the mac's <c>WizardStructure.swift</c>.</para>
///
/// <para>The marks pool is the one list that is not restored by value alone.
/// Windows keeps a pool the teacher ticked and narrows it on every READ
/// (<see cref="EffectiveGradedFolders"/>, which is what the dialog's
/// <c>CurrentGradedFolders</c> does) and again as the file is written; the
/// mac narrows inside the restore. Both reach the same file — the contract's
/// consequence (4) says so in as many words.</para>
/// </summary>
public static class WizardStructure
{
    /// <summary>
    /// The editor's five lists. <see cref="GradedFolders"/> is null when the
    /// pool has never been set and is to be inferred from the folders, which
    /// is how a brand-new course opens.
    /// </summary>
    public sealed record Lists(
        IReadOnlyList<string> SharedFolders,
        IReadOnlyList<string> SharedFiles,
        IReadOnlyList<string> PerSectionFolders,
        IReadOnlyList<string> PerSectionFiles,
        IReadOnlyList<string>? GradedFolders);

    /// <summary>
    /// What a new wizard opens with: the factory lists (or the LCS ones for
    /// the two shared lists), and a pool still to be inferred.
    /// </summary>
    public static Lists Defaults(bool useLcs) => new(
        (useLcs ? WizardDefaults.LcsSharedFolders : WizardDefaults.SharedFolders).ToList(),
        (useLcs ? WizardDefaults.LcsSharedFiles : WizardDefaults.SharedFiles).ToList(),
        WizardDefaults.PerSectionFolders.ToList(),
        WizardDefaults.PerSectionFiles.ToList(),
        null);

    /// <summary>
    /// What adopting a subject's skeleton puts into the editor: the family's
    /// own four lists and its declared marks pool
    /// (<see cref="SkeletonCatalog.AdoptedGradedFolders"/>). The caller keeps
    /// the result as its snapshot, so a later restore can tell which lists the
    /// teacher has touched since.
    /// </summary>
    public static Lists Adopting(SkeletonCatalog.Family family) => new(
        family.SharedFolders.ToList(),
        family.SharedFiles.ToList(),
        family.PerSectionFolders.ToList(),
        family.PerSectionFiles.ToList(),
        SkeletonCatalog.AdoptedGradedFolders(family));

    /// <summary>
    /// The skeleton was turned down (or the ready-made pages taken back), so
    /// the defaults come back — for each list still EQUAL, order included, to
    /// what the adoption put there, and for no other. With no adoption to
    /// compare against, nothing changes at all.
    /// </summary>
    /// <remarks>
    /// <para>Value equality rather than a dirty flag, deliberately: a list
    /// edited and edited BACK is restored with the untouched ones, because a
    /// teacher cannot see the difference and so neither can the rule. A flag
    /// has to be right in every editing path and gets one wrong the first time
    /// a list is changed from somewhere new.</para>
    ///
    /// <para>The two SHARED lists go back to the LCS set when the terminology
    /// switch is on; the per-section lists have no LCS variant. A pool still
    /// equal to the adoption's becomes null — re-inferred over the restored
    /// folders — and a pool the teacher ticked is kept, to be narrowed by
    /// <see cref="EffectiveGradedFolders"/>.</para>
    /// </remarks>
    public static Lists RestoringDefaults(Lists current, Lists? adopted, bool useLcs)
    {
        if (adopted is null) return current;
        var defaults = Defaults(useLcs);

        static IReadOnlyList<string> Back(IReadOnlyList<string> now, IReadOnlyList<string> snapshot, IReadOnlyList<string> factory) =>
            now.SequenceEqual(snapshot) ? factory.ToList() : now;

        var pool = current.GradedFolders is not null
                   && adopted.GradedFolders is not null
                   && current.GradedFolders.SequenceEqual(adopted.GradedFolders)
            ? null
            : current.GradedFolders;

        return new Lists(
            Back(current.SharedFolders, adopted.SharedFolders, defaults.SharedFolders),
            Back(current.SharedFiles, adopted.SharedFiles, defaults.SharedFiles),
            Back(current.PerSectionFolders, adopted.PerSectionFolders, defaults.PerSectionFolders),
            Back(current.PerSectionFiles, adopted.PerSectionFiles, defaults.PerSectionFiles),
            pool);
    }

    /// <summary>
    /// The marks pool the editor shows and the file will carry: inferred from
    /// the folders when it was never set, otherwise the teacher's pool
    /// narrowed to the folders the course will actually have — so it can
    /// never name a folder that has just left the editor.
    /// </summary>
    public static List<string> EffectiveGradedFolders(Lists lists)
    {
        var actual = lists.SharedFolders.Concat(lists.PerSectionFolders).ToList();
        return lists.GradedFolders is null
            ? GradedFolderRule.InferredPool(actual)
            : GradedFolderRule.Reconciled(lists.GradedFolders, actual);
    }
}
