namespace Plantoir.Core.Assist;

/// <summary>
/// check_section's groups that are contract data (<c>shared-rules.json</c> →
/// <c>sectionCheck</c>, GitHub issue #355). The first two are read off the
/// <see cref="LinkGraph"/> in <c>PlantoirTools.CheckSection</c>; the third is
/// here, by the ISSUE's definition rather than the start-of-year rule's own
/// step 3 — an audit that agrees with the planner by construction is silent
/// exactly when the planner is wrong (plan review H2: the issue's definition
/// flagged 55 SNC1W and 81 ICS3U pages where the rule leaks, 0 where it does not).
/// </summary>
public static class SectionCheck
{
    /// <summary>
    /// A visible page that a class students CANNOT see links to directly, and
    /// no class they CAN see links to directly. A visible non-class page
    /// linking to it does not rescue it. Never a class page, a folder's own
    /// page, a curriculum page, the Key Links page or a page Key Links lists.
    /// </summary>
    public static IReadOnlyList<StartOfYearPage> LinkedButMissed(IReadOnlyList<StartOfYearPage> pages)
    {
        var keyLinksListed = pages.Where(p => p.Kind == StartOfYearKind.KeyLinks)
            .SelectMany(p => p.LinksTo).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var classes = pages.Where(p => p.Kind == StartOfYearKind.Class).ToList();
        return pages
            .Where(p => p.Kind == StartOfYearKind.Page && p.Visible && !keyLinksListed.Contains(p.Id))
            .Where(p => classes.Any(c => !c.Visible && c.LinksTo.Contains(p.Id))
                        && !classes.Any(c => c.Visible && c.LinksTo.Contains(p.Id)))
            .ToList();
    }
}
