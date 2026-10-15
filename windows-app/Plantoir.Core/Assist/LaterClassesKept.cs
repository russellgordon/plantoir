using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// <c>file-formats.json</c> → <c>laterClassesKept</c> (#475): the class pages a
/// teacher left published when asked about classes dated after the next class,
/// each at the date it had then —
/// <c>courses/&lt;CODE&gt;/.publish_state/section&lt;N&gt;.later-classes-kept.json</c>.
/// </summary>
/// <remarks>
/// <para><b>Why a file in the course, not a preference.</b> An assistant
/// working from another program is a separate process: it is refused a deploy
/// while a later class waits on an answer, and it must read the SAME answer to
/// know the deploy is no longer held back. Inside <c>.publish_state</c>, like
/// the links checklist's answer, it is hidden from the course's fingerprint and
/// never published.</para>
///
/// <para>Written by the app only, never the build: when a class is unticked at
/// Deploy or at Section ▸ Publish Pages…, when Keep All and Deploy is pressed,
/// when a class is published by naming its date, and when a class dated later
/// is published from the links checklist. Removed on rollover, with the
/// checklist's answer (<see cref="LinksChecklist.ReleasePublishedPages"/>).
/// A record that cannot be read or written costs the question once more,
/// nothing else.</para>
/// </remarks>
public static class LaterClassesKept
{
    /// <summary>One kept class: its place (without <c>.md</c>) and the day its <c>created</c> named, <c>yyyy-MM-dd</c>.</summary>
    public sealed record Row(string Place, string Date);

    /// <summary>The record's path for one section.</summary>
    public static string PathFor(string courseDirectory, int section) =>
        Path.Combine(courseDirectory, ".publish_state", $"section{section}.later-classes-kept.json");

    /// <summary>The kept rows on disk; empty when there is no record or it cannot be read.</summary>
    public static IReadOnlyList<Row> Read(string courseDirectory, int section)
    {
        try
        {
            string path = PathFor(courseDirectory, section);
            if (!File.Exists(path)) return Array.Empty<Row>();
            if (JsonNode.Parse(File.ReadAllText(path))?["kept"] is not JsonArray rows) return Array.Empty<Row>();
            var kept = new List<Row>();
            foreach (var row in rows)
            {
                if (row?["place"] is JsonValue place && place.TryGetValue(out string? p)
                    && row["date"] is JsonValue date && date.TryGetValue(out string? d))
                    kept.Add(new Row(ClassesDatedLater.PlaceKey(p), d));
            }
            return kept;
        }
        catch { return Array.Empty<Row>(); }
    }

    /// <summary>
    /// Adds <paramref name="pages"/> to what is kept — a page's older date is
    /// replaced, so the record never holds one place twice — stamped with
    /// <paramref name="now"/> (UTC). Written through a temporary file and a
    /// move, so a reader never meets half a file; last writer wins between two
    /// windows, and the worst outcome is being asked once more.
    /// </summary>
    /// <returns>False when the record could not be written.</returns>
    public static bool Keep(string courseDirectory, int section, IEnumerable<ClassesDatedLater.Page> pages,
                            DateTime? now = null)
    {
        var adding = pages.Where(page => page.Date is not null)
                          .Select(page => new Row(page.Place, DateText.Iso(page.Date!.Value)))
                          .ToList();
        if (adding.Count == 0) return true;
        var rows = Read(courseDirectory, section)
            .Where(row => !adding.Any(page => page.Place == row.Place))
            .Concat(adding)
            .ToList();
        try
        {
            string path = PathFor(courseDirectory, section);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var kept = new JsonArray();
            foreach (var row in rows) kept.Add(new JsonObject { ["place"] = row.Place, ["date"] = row.Date });
            var record = new JsonObject
            {
                ["version"] = 1,
                ["answeredAt"] = (now ?? DateTime.UtcNow).ToUniversalTime()
                    .ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture),
                ["kept"] = kept,
            };
            string temporary = path + ".tmp";
            File.WriteAllText(temporary, record.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, path, overwrite: true);
            return true;
        }
        catch { return false; }
    }
}
