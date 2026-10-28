using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Models;

/// <summary>
/// Which of the teacher's pages a build rewrote with their class's date (#279,
/// mirroring the mac's #275/#276). The shared Python
/// (<c>scripts/build_site.py</c> → <c>announce_dated_pages</c>) prints one
/// <c>PLANTOIR_DATED:</c> line, after a plain sentence, whenever it rewrote at
/// least one page; this reads that line back so the app can name the pages on
/// the activity trail.
///
/// <para>Shape from <c>contracts/shared-rules.json</c> →
/// <c>pagesDatedByTheBuild</c>; read from the prefix ONWARD, exactly as
/// <see cref="SiteHealthFinding.Parse"/> reads <c>PLANTOIR_HEALTH:</c>, because
/// a launcher can glue the marker to the tail of its own half line. The line
/// itself is kept out of the console by <c>TranscriptBuilder</c> (rule 1).</para>
/// </summary>
public sealed record PagesDatedByTheBuild(string Course, int Section, IReadOnlyList<string> Pages, int? Count = null)
{
    /// <summary>The marker prefix, as the contract spells it.</summary>
    public const string Marker = "PLANTOIR_DATED:";

    /// <summary>How many names the trail line shows before "and N more" — the mac's number.</summary>
    public const int NamesShownOnTheTrail = 40;

    /// <summary>
    /// <c>pagesDatedByTheBuild.trailLine.shape</c>: the count first, then the
    /// names, shortened after <see cref="NamesShownOnTheTrail"/>. Names are
    /// the pages' places in the course folder, never anything written on them.
    /// </summary>
    public string TrailSentence
    {
        get
        {
            // The count is the build's own when it shortened its line (#666),
            // so "and N more" counts the pages the line left out as well.
            int total = Math.Max(Count ?? 0, Pages.Count);
            int shown = Math.Min(Pages.Count, NamesShownOnTheTrail);
            string names = string.Join(", ", Pages.Take(shown));
            int notShown = total - shown;
            if (notShown > 0) names = shown == 0 ? $"{notShown} not named" : names + $" and {notShown} more";
            string noun = total == 1 ? "page" : "pages";
            return $"the build gave {total} {noun} the date of their class: {names}";
        }
    }

    /// <summary>Whether a line carries the marker anywhere.</summary>
    public static bool IsMarkerLine(string line) => line.Contains(Marker, StringComparison.Ordinal);

    /// <summary>The report a line carries, or null when it carries none that can be read.</summary>
    public static PagesDatedByTheBuild? Parse(string? line)
    {
        if (string.IsNullOrWhiteSpace(line)) return null;
        int at = line.IndexOf(Marker, StringComparison.Ordinal);
        if (at < 0) return null;
        string payload = line[(at + Marker.Length)..].Trim();
        try
        {
            if (JsonNode.Parse(payload) is not JsonObject obj) return null;
            string course = obj["course"]?.GetValue<string>() ?? "";
            int section = obj["section"]?.GetValue<int>() ?? 0;
            var pages = (obj["pages"] as JsonArray)?
                .Select(page => page?.GetValue<string>())
                .Where(page => !string.IsNullOrEmpty(page))
                .Select(page => page!)
                .ToList() ?? new List<string>();
            int? count = obj["count"] is JsonValue counted && counted.TryGetValue(out int total) ? total : null;
            if (course.Length == 0 || section <= 0 || (pages.Count == 0 && (count ?? 0) == 0)) return null;
            return new PagesDatedByTheBuild(course, section, pages, count);
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }
}
