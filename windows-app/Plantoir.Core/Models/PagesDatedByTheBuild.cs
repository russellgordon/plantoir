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
public sealed record PagesDatedByTheBuild(string Course, int Section, IReadOnlyList<string> Pages)
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
            string names = string.Join(", ", Pages.Take(NamesShownOnTheTrail));
            int notShown = Pages.Count - Math.Min(Pages.Count, NamesShownOnTheTrail);
            if (notShown > 0) names += $" and {notShown} more";
            string noun = Pages.Count == 1 ? "page" : "pages";
            return $"the build gave {Pages.Count} {noun} the date of their class: {names}";
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
            if (course.Length == 0 || section <= 0 || pages.Count == 0) return null;
            return new PagesDatedByTheBuild(course, section, pages);
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    /// <summary>Every report in a list of lines (a scheduled publish's record).</summary>
    public static IReadOnlyList<PagesDatedByTheBuild> ReportsIn(IEnumerable<string> lines) =>
        lines.Select(Parse).Where(report => report is not null).Select(report => report!).ToList();
}
