namespace Plantoir.Core.Models;

/// <summary>
/// The "Curriculum folders" checkboxes in Course Settings and the wizard
/// (<c>shared-rules.json</c> → <c>specialNames.curriculumFoldersOffer</c>;
/// GitHub issue #345, the mac's #128).
/// </summary>
/// <remarks>
/// <para>Shown only with TWO or more candidates — with one there is nothing to
/// choose. A folder is never ticked just because of its name: ticked are the
/// folders the build maps, then every declared folder the course has, so a
/// folder ticked before its first page is written stays ticked.</para>
///
/// <para>A tick writes the ticked folders FIRST, in their order, then the new
/// one — otherwise the first tick on a course that declared nothing would drop
/// the map the fallback scan found, and the primary map ("Curriculum
/// Coverage") would change hands.</para>
/// </remarks>
public static class CurriculumFoldersOffer
{
    public const string Label = "Curriculum folders";
    public const string Caption = "Tick each folder that holds curriculum expectations. Each one gets its own coverage map on your website.";
    public const string LastStaysTicked = "At least one curriculum folder stays ticked, so your course keeps its coverage map. Tick another folder first.";

    /// <summary>The folders offered, in the list's order; empty when fewer than two.</summary>
    public static List<string> Offered(IReadOnlyList<string> folders, IReadOnlyList<string> declared)
    {
        var offered = folders
            .Where(f => f.Contains("curriculum", StringComparison.OrdinalIgnoreCase)
                        || declared.Contains(f, StringComparer.OrdinalIgnoreCase))
            .ToList();
        return offered.Count >= 2 ? offered : new List<string>();
    }

    /// <summary>The folders shown ticked: the mapped ones, then every declared folder the course has.</summary>
    public static List<string> Ticked(IReadOnlyList<string> folders, IReadOnlyList<string> declared, IReadOnlyList<string> mapped)
    {
        var ticked = mapped.ToList();
        foreach (string name in declared)
        {
            string? here = folders.FirstOrDefault(f => string.Equals(f, name, StringComparison.OrdinalIgnoreCase));
            if (here is not null && !ticked.Contains(here, StringComparer.OrdinalIgnoreCase)) ticked.Add(here);
        }
        return ticked;
    }

    /// <summary>What a tick writes as <c>curriculum_folders</c>: the ticked ones in order, then the new one.</summary>
    public static List<string> Tick(IReadOnlyList<string> ticked, string folder) =>
        ticked.Contains(folder, StringComparer.OrdinalIgnoreCase) ? ticked.ToList() : ticked.Append(folder).ToList();

    /// <summary>What an untick writes, or null when it is the last ticked folder (refused with <see cref="LastStaysTicked"/>).</summary>
    public static List<string>? Untick(IReadOnlyList<string> ticked, string folder)
    {
        var rest = ticked.Where(f => !string.Equals(f, folder, StringComparison.OrdinalIgnoreCase)).ToList();
        return rest.Count == 0 ? null : rest;
    }
}
