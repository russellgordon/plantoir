using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Catalogs;

/// <summary>
/// Answers one question for the new-course wizard: does ready-made example
/// content exist for a course code? The content itself lives in the bundled
/// support/example_content/&lt;CODE&gt;/ folders — one per course code, each
/// with a manifest.json — and is installed by the real setup wizard, not by
/// the app. The app only needs to know whether to offer it. Mirrors the mac
/// app's ExampleContentCatalog; callers pass the bundled example_content
/// directory (the Core layer knows no bundle paths).
/// </summary>
public static class ExampleContentCatalog
{
    /// <summary>
    /// The bundled manifest for a course code, or null when no example
    /// content exists for it. Lookup is case-insensitive, matching how
    /// course codes are normalized everywhere else.
    /// </summary>
    public static string? ManifestPath(string exampleContentRoot, string code)
    {
        string normalized = code.Trim().ToUpperInvariant();
        if (normalized.Length == 0) return null;
        string path = Path.Combine(exampleContentRoot, normalized, "manifest.json");
        return File.Exists(path) ? path : null;
    }

    /// <summary>True when example content is bundled for this course code.</summary>
    public static bool HasContent(string exampleContentRoot, string code) =>
        ManifestPath(exampleContentRoot, code) is not null;

    /// <summary>
    /// True when the example content for this code includes the official
    /// curriculum pages — the wizard only shows the curriculum toggle when
    /// there are curriculum pages to include. Any unreadable manifest simply
    /// answers false, never throws.
    /// </summary>
    public static bool IncludesCurriculum(string exampleContentRoot, string code)
    {
        if (ManifestPath(exampleContentRoot, code) is not { } path) return false;
        try
        {
            var manifest = JObject.Parse(File.ReadAllText(path));
            return manifest["curriculum_folder"]?.Type == JTokenType.String
                && manifest["curriculum_folder"]!.ToString().Length > 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// The marks pool (<c>graded_folders</c>) a NEW course taking this code's
    /// ready-made pages is written with — read from the payload's manifest
    /// exactly as the command line reads it (#317, mirroring the mac's #292
    /// <c>ExampleContentCatalog.marksPool(fromManifest:)</c>). Null when there
    /// is no payload or its manifest cannot be read, in which case the caller
    /// leaves the key absent, as before.
    /// </summary>
    public static IReadOnlyList<string>? MarksPool(string exampleContentRoot, string code)
    {
        if (ManifestPath(exampleContentRoot, code) is not { } path) return null;
        try
        {
            return MarksPool(JObject.Parse(File.ReadAllText(path)));
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// <c>setup_course.graded_folders_for</c> over a manifest, called the way
    /// setup calls it for a payload: the shared folders without <c>Media</c>,
    /// then the per-section folders. A declared name is kept as written when
    /// it names a folder exactly, respelled to the folder's own spelling when
    /// it matches ignoring case, and dropped otherwise; blanks, nulls,
    /// non-strings and repeats are dropped; a declared null or <c>[]</c> gives
    /// <c>[]</c>; and ONLY when the key is absent, every folder whose name
    /// contains "task", once each, in list order. Contract:
    /// <c>shared-rules.json</c> → <c>gradedFolders.newCourse</c>.
    ///
    /// <para>Deliberately NOT <c>GradedFolderRule.Reconciled</c>: that is the
    /// exact-match reconciliation of a teacher's ticks, and the command line
    /// matches ignoring case and respells — the contract's respelling case is
    /// red for it.</para>
    /// </summary>
    public static IReadOnlyList<string> MarksPool(JObject manifest)
    {
        static IEnumerable<string> Names(JToken? list) =>
            (list as JArray)?.Where(item => item.Type == JTokenType.String)
                .Select(item => item.ToString())
                .Where(name => name.Length > 0)
            ?? Enumerable.Empty<string>();

        var folders = Names(manifest["shared_folders"]).Where(name => name != "Media")
            .Concat(Names(manifest["per_section_folders"]))
            .ToList();

        if (manifest.TryGetValue("graded_folders", out var declared))
        {
            var exact = folders.ToHashSet(StringComparer.Ordinal);
            // The LAST folder of a spelling wins, as the Python's dictionary
            // comprehension does.
            var ignoringCase = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (string folder in folders) ignoringCase[folder.ToLowerInvariant()] = folder;

            var pool = new List<string>();
            foreach (string name in Names(declared))
            {
                string? target = exact.Contains(name) ? name
                    : ignoringCase.TryGetValue(name.ToLowerInvariant(), out var spelled) ? spelled
                    : null;
                if (target is not null && !pool.Contains(target)) pool.Add(target);
            }
            return pool;
        }

        return folders
            .Where(name => name.Contains("task", StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.Ordinal)
            .ToList();
    }
}
