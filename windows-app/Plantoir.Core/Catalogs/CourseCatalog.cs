using System.Text.Json.Nodes;

namespace Plantoir.Core.Catalogs;

/// <summary>One row in a province's course catalog — what the New Course wizard's code picker searches and browses.</summary>
public sealed record CourseCatalogEntry(string Code, string ShortName, string FormalName, string Province)
{
    /// <summary>
    /// "ON:ICS3U" or "BC:MTEL-12" — unique across both provinces even where
    /// a code collides. Unused on Windows today (kept for parity with the
    /// mac's CourseCatalogEntry, where it backs SwiftUI's Identifiable for
    /// the picker's List; WinUI's AutoSuggestBox needs no item identity).
    /// </summary>
    public string Id => $"{Province}:{Code}";
}

/// <summary>
/// The two province course lists the New Course wizard's code picker offers,
/// so a teacher who doesn't already know course codes can find one by typing
/// what the course is called instead. Mirrors the mac's CourseCatalog.swift.
///
/// Reads the same ontario_secondary_courses.json and
/// british_columbia_secondary_courses.json files CourseNameCatalog reads for
/// names, loaded again here WITH which province each code belongs to —
/// CourseNameCatalog merges both files into one code-only lookup (club
/// detection and name auto-fill don't care which province a code is from)
/// and has no reason to keep the provinces apart, but a picker that offers
/// "Ontario" or "British Columbia" does.
/// </summary>
public static class CourseCatalog
{
    /// <summary>How many rows the picker offers at once — Ontario alone lists nearly 2,000 codes.</summary>
    public const int SearchResultLimit = 40;

    public static List<CourseCatalogEntry> LoadEntries(string jsonPath, string province)
    {
        var result = new List<CourseCatalogEntry>();
        if (!File.Exists(jsonPath)) return result;
        try
        {
            if (JsonNode.Parse(File.ReadAllBytes(jsonPath)) is JsonObject root)
                foreach (var (code, value) in root)
                {
                    if (value is not JsonObject entry) continue;
                    if (entry["formal_name"] is not JsonValue f || !f.TryGetValue<string>(out string? formal)) continue;
                    if (entry["short_name"] is not JsonValue s || !s.TryGetValue<string>(out string? shortName)) continue;
                    result.Add(new CourseCatalogEntry(code, shortName, formal, province));
                }
        }
        catch { }
        return result;
    }

    /// <summary>
    /// Entries from one province's catalog matching <paramref name="query"/>
    /// against code, short name, and formal name (case-insensitive
    /// substring) — codes the query PREFIXES lead the list, so typing "sch"
    /// surfaces SCH3U and SCH4U before some unrelated course whose formal
    /// name merely mentions chemistry. An empty query returns the whole
    /// catalog alphabetically by code. Capped at <paramref name="limit"/>.
    /// </summary>
    public static List<CourseCatalogEntry> Matching(IEnumerable<CourseCatalogEntry> entries, string query, int limit)
    {
        string trimmed = query.Trim();

        if (trimmed.Length == 0)
            return entries.OrderBy(e => e.Code, StringComparer.OrdinalIgnoreCase).Take(limit).ToList();

        string needle = trimmed.ToUpperInvariant();
        var codeStartsWith = new List<CourseCatalogEntry>();
        var other = new List<CourseCatalogEntry>();
        foreach (var entry in entries)
        {
            if (entry.Code.StartsWith(needle, StringComparison.OrdinalIgnoreCase)) { codeStartsWith.Add(entry); continue; }
            bool matchesElsewhere =
                entry.Code.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
                entry.ShortName.Contains(needle, StringComparison.OrdinalIgnoreCase) ||
                entry.FormalName.Contains(needle, StringComparison.OrdinalIgnoreCase);
            if (matchesElsewhere) other.Add(entry);
        }
        codeStartsWith = codeStartsWith.OrderBy(e => e.Code, StringComparer.OrdinalIgnoreCase).ToList();
        other = other.OrderBy(e => e.Code, StringComparer.OrdinalIgnoreCase).ToList();

        var combined = new List<CourseCatalogEntry>(codeStartsWith);
        combined.AddRange(other);
        return combined.Take(limit).ToList();
    }
}
