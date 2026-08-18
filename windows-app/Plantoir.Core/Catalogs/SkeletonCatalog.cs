using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Catalogs;

/// <summary>
/// Answers one question for the new-course wizard: what shape should a
/// course start in when no ready-made example content exists for its code?
///
/// 37 course codes have real example content. Every other Ontario
/// code — around 1,900 of them — gets a SKELETON instead: folders that suit
/// the subject, a semester of class pages to rename, a site tour, and
/// placeholder pages saying what belongs where. The pages live in the
/// bundled support/skeletons/<family>/ folders and are installed by the
/// real setup wizard; the app only needs to know which family a code
/// belongs to, so the folder list it offers matches the pages that will
/// arrive.
///
/// The mapping is by three-letter prefix — ADA is drama, AMU is music, SCH
/// is chemistry, MCV is calculus — falling back to a generic skeleton for
/// club and custom codes.
/// </summary>
public static class SkeletonCatalog
{
    public sealed record Family(
        string Name,
        string Label,
        IReadOnlyList<string> SharedFolders,
        IReadOnlyList<string> SharedFiles,
        IReadOnlyList<string> PerSectionFolders,
        IReadOnlyList<string> PerSectionFiles,
        IReadOnlyList<string> Hidden,
        IReadOnlyList<string> Expandable
    );

    /// <summary>
    /// The family name for a course code, from the bundled prefix map (families.json).
    /// </summary>
    public static string? FamilyName(string skeletonsRoot, string code)
    {
        string normalized = code.Trim().ToUpperInvariant();
        if (normalized.Length == 0) return null;

        string mapPath = Path.Combine(skeletonsRoot, "families.json");
        if (!File.Exists(mapPath)) return null;

        try
        {
            var map = JObject.Parse(File.ReadAllText(mapPath));
            string prefix = normalized.Length >= 3 ? normalized.Substring(0, 3) : normalized;
            if (map["prefixes"] is JObject prefixes && prefixes[prefix]?.Type == JTokenType.String)
            {
                return prefixes[prefix]!.ToString();
            }
            return map["default"]?.ToString();
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// The shape a course of this code should start in, or null when no skeleton is bundled.
    /// </summary>
    public static Family? GetFamily(string skeletonsRoot, string code)
    {
        string? name = FamilyName(skeletonsRoot, code);
        if (name is null) return null;
        return GetFamilyByName(skeletonsRoot, name);
    }

    /// <summary>
    /// A family by name, for matching wizard defaults.
    /// </summary>
    public static Family? GetFamilyByName(string skeletonsRoot, string name)
    {
        string manifestPath = Path.Combine(skeletonsRoot, name, "manifest.json");
        if (!File.Exists(manifestPath)) return null;

        try
        {
            var manifest = JObject.Parse(File.ReadAllText(manifestPath));
            IReadOnlyList<string> List(string key) =>
                manifest[key] is JArray arr ? arr.Select(t => t.ToString()).ToList() : Array.Empty<string>();

            return new Family(
                Name: name,
                Label: manifest["label"]?.ToString() ?? "this subject",
                SharedFolders: List("shared_folders"),
                SharedFiles: List("shared_files"),
                PerSectionFolders: List("per_section_folders"),
                PerSectionFiles: List("per_section_files"),
                Hidden: List("hidden"),
                Expandable: List("expandable")
            );
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Every bundled family name.
    /// </summary>
    public static IReadOnlyList<string> EveryFamilyName(string skeletonsRoot)
    {
        string mapPath = Path.Combine(skeletonsRoot, "families.json");
        if (!File.Exists(mapPath)) return Array.Empty<string>();

        try
        {
            var map = JObject.Parse(File.ReadAllText(mapPath));
            if (map["prefixes"] is JObject prefixes)
            {
                return prefixes.Properties()
                    .Select(p => p.Value.ToString())
                    .Distinct()
                    .OrderBy(n => n, StringComparer.Ordinal)
                    .ToList();
            }
            return Array.Empty<string>();
        }
        catch
        {
            return Array.Empty<string>();
        }
    }

    /// <summary>
    /// True when a skeleton would be offered for this code — which is only
    /// when there is no example content, since example content is better.
    /// </summary>
    public static bool HasSkeleton(string exampleContentRoot, string skeletonsRoot, string code)
    {
        if (ExampleContentCatalog.HasContent(exampleContentRoot, code)) return false;
        return GetFamily(skeletonsRoot, code) != null;
    }

    /// <summary>
    /// The structure a course of this code should adopt, or null when nothing should change.
    /// </summary>
    public static Family? StructureToAdopt(
        string exampleContentRoot,
        string skeletonsRoot,
        string code,
        IReadOnlyList<string> currentSharedFolders,
        IReadOnlyList<string> defaultSharedFolders,
        IReadOnlyList<string> lcsSharedFolders)
    {
        if (ExampleContentCatalog.HasContent(exampleContentRoot, code)) return null;
        var candidate = GetFamily(skeletonsRoot, code);
        if (candidate is null) return null;
        if (candidate.SharedFolders.SequenceEqual(currentSharedFolders)) return null;
        if (!IsOffered(skeletonsRoot, currentSharedFolders, defaultSharedFolders, lcsSharedFolders)) return null;
        return candidate;
    }

    /// <summary>
    /// True when a folder list is still one the app offered, rather than one the teacher has edited.
    /// </summary>
    public static bool IsOffered(
        string skeletonsRoot,
        IReadOnlyList<string> folders,
        IReadOnlyList<string> defaultSharedFolders,
        IReadOnlyList<string> lcsSharedFolders)
    {
        if (folders.SequenceEqual(defaultSharedFolders) || folders.SequenceEqual(lcsSharedFolders)) return true;
        foreach (string name in EveryFamilyName(skeletonsRoot))
        {
            if (GetFamilyByName(skeletonsRoot, name) is { } candidate && candidate.SharedFolders.SequenceEqual(folders))
                return true;
        }
        return false;
    }

    /// <summary>
    /// The sidebar for a course built from a skeleton: what stays out of the explorer, and what carries a chevron.
    /// </summary>
    public static (IReadOnlyList<string> Hidden, IReadOnlyList<string> Expandable) Sidebar(
        Family family,
        IReadOnlyList<string> sharedFolders,
        IReadOnlyList<string> sharedFiles,
        IReadOnlyList<string> perSectionFolders,
        IReadOnlyList<string> perSectionFiles)
    {
        var hidden = new List<string> { "Media" };
        foreach (string item in family.Hidden)
        {
            bool exists = sharedFolders.Contains(item)
                || sharedFiles.Contains(item)
                || perSectionFolders.Contains(item)
                || perSectionFiles.Contains(item);
            if (exists && !hidden.Contains(item))
            {
                hidden.Add(item);
            }
        }
        var expandable = sharedFolders.Where(item => !hidden.Contains(item)).ToList();
        return (hidden, expandable);
    }
}
