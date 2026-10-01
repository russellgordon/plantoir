namespace Plantoir.Core.Models;

/// <summary>
/// The pieces of <c>shared-rules.json</c> → <c>gradedFolders.floor</c> (GitHub
/// issue #348, the mac's #152 and its <c>MarksFloor.swift</c>): what the pool
/// and the walk look like AFTER a gesture, and whether a pooled name is found
/// on disk. <see cref="ItemProtectionRule"/> asks them.
/// </summary>
public static class MarksFloor
{
    /// <summary>
    /// Whether a pooled name names a folder the walk found, compared the way
    /// the build compares — case ignored.
    /// </summary>
    public static bool Found(string pooled, IReadOnlyList<WalkedFolder> walk) =>
        walk.Any(folder => string.Equals(folder.Name, pooled, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Whether any pooled name is found. When the walk found no folder at all
    /// every pooled name counts as found — the old rule, kept so that an
    /// unreadable or empty course folder cannot switch the floor off (F11).
    /// </summary>
    public static bool AnyFound(IReadOnlyList<string> pool, IReadOnlyList<WalkedFolder> walk) =>
        walk.Count == 0 ? pool.Count > 0 : pool.Any(pooled => Found(pooled, walk));

    /// <summary>
    /// The pool and the walk after the gesture. An untick takes the name out
    /// of the pool and leaves the disk alone. A removal is the removal rule's
    /// own answer (<see cref="FolderRemoval.RemoveFolderFromCourse"/>,
    /// <c>gradedFolders.removingAFolder</c>): the walk loses every occurrence
    /// under the removed folder — its course-level folder for a shared removal,
    /// its folder inside a section for a per-section one, compared EXACTLY
    /// because <c>excluded_items</c> matches exactly (F17) — and the pool keeps
    /// the name while anything still offers it, case ignored, and loses it
    /// otherwise; a course never asked re-infers its pool over what is offered.
    /// </summary>
    public static (IReadOnlyList<string> Pool, IReadOnlyList<WalkedFolder> Walk) After(
        string name, ItemList list, ProtectionContext context, IReadOnlyList<WalkedFolder> walk)
    {
        var pool = context.GradedFolders;
        if (list == ItemList.GradedFolders)
            return (pool.Where(pooled => !string.Equals(pooled, name, StringComparison.Ordinal)).ToList(), walk);

        bool perSection = list == ItemList.PerSectionFolders;
        var walkAfter = walk
            .Where(folder => perSection
                ? !folder.SectionLevelFolders.Contains(name, StringComparer.Ordinal)
                : !string.Equals(folder.CourseLevelFolder, name, StringComparison.Ordinal))
            .ToList();
        var shared = (context.SharedFolders ?? Array.Empty<string>())
            .Where(folder => perSection || !string.Equals(folder, name, StringComparison.Ordinal));
        var perSectionFolders = context.PerSectionFolders
            .Where(folder => !perSection || !string.Equals(folder, name, StringComparison.Ordinal));
        var offeredAfter = shared.Concat(perSectionFolders).Concat(GradedFolderChoices.NamesIn(walkAfter))
            .Distinct(StringComparer.Ordinal).ToList();

        if (!context.PoolWasAsked) return (GradedFolderRule.InferredPool(offeredAfter), walkAfter);
        if (offeredAfter.Contains(name, StringComparer.OrdinalIgnoreCase)) return (pool, walkAfter);
        return (pool.Where(pooled => !string.Equals(pooled, name, StringComparison.OrdinalIgnoreCase)).ToList(), walkAfter);
    }
}
