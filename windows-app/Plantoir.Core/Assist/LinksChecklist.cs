using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Assist;

/// <summary>
/// One row of the links checklist the build offers
/// (<c>file-formats.json</c> → <c>linksChecklistOffer.rowKeys</c>; #392 / mac #379).
/// </summary>
public sealed record LinksChecklistRow(
    string Place,
    string Group,
    bool Ticked,
    IReadOnlyList<string> DependsOn,
    string? Title = null,
    string? Date = null,
    string? Why = null,
    string? FirstUsedIn = null,
    IReadOnlyList<string>? LinkedFrom = null)
{
    public bool IsClass => Group == LinksChecklist.ClassGroup;
}

/// <summary>The offer a build wrote for one section, read as the sheet reads it.</summary>
public sealed record LinksChecklistOffer(string Course, int Section, string? BuildId, IReadOnlyList<LinksChecklistRow> Rows)
{
    /// <summary>
    /// <c>courses/&lt;CODE&gt;/.publish_state/section&lt;N&gt;.links-checklist.json</c>.
    /// </summary>
    public static string PathFor(string courseDirectory, int section) =>
        Path.Combine(courseDirectory, ".publish_state", $"section{section}.links-checklist.json");

    /// <summary>
    /// Read an offer. An offer written by a builder older than #385 carries
    /// no <c>dependsOn</c>: read it as <c>[]</c>. Null when there is none or
    /// it cannot be read — the sheet then is simply not offered.
    /// </summary>
    public static LinksChecklistOffer? Read(string path)
    {
        JsonNode? root;
        try { root = JsonNode.Parse(File.ReadAllText(path)); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return null; }
        if (root is not JsonObject offer) return null;
        var rows = new List<LinksChecklistRow>();
        foreach (var node in offer["pages"] as JsonArray ?? new JsonArray())
        {
            if (node is not JsonObject row || row["place"]?.ToString() is not { } place) continue;
            rows.Add(new LinksChecklistRow(
                place,
                row["group"]?.ToString() ?? LinksChecklist.NotReachedGroup,
                row["ticked"] is JsonValue t && t.TryGetValue(out bool ticked) && ticked,
                Strings(row["dependsOn"]),
                row["title"]?.ToString(),
                row["date"]?.ToString(),
                row["why"]?.ToString(),
                row["firstUsedIn"]?.ToString(),
                Strings(row["linkedFrom"])));
        }
        int section = offer["section"] is JsonValue s && s.TryGetValue(out int n) ? n : 0;
        return new LinksChecklistOffer(offer["course"]?.ToString() ?? "", section, offer["buildId"]?.ToString(), rows);
    }

    private static IReadOnlyList<string> Strings(JsonNode? node) =>
        node is JsonArray list ? list.Select(x => x?.ToString()).OfType<string>().ToList() : Array.Empty<string>();
}

/// <summary>
/// The links checklist's rules that are logic, not pixels (#392, #399, #405;
/// mac <c>LinksChecklistGate</c>). Pure: the sheet and the contract runner
/// both call these, so the checkbox and its tests cannot disagree.
/// </summary>
public static class LinksChecklist
{
    public const string FromAClassGroup = "fromAClass";
    public const string NotReachedGroup = "notReachedByAClass";
    public const string ClassGroup = "class";
    public static readonly string[] GroupOrder = { FromAClassGroup, NotReachedGroup, ClassGroup };

    /// <summary>
    /// Places are compared in composed Unicode form (#405 trap): Swift's
    /// String equality is canonical-equivalence and C#'s is ordinal, so a
    /// French course whose build read a name decomposed would show a brought
    /// row unticked while it was published.
    /// </summary>
    public static string Key(string place) => place.Normalize(NormalizationForm.FormC);

    /// <summary>
    /// The rows that GO on their own ticks (#385): own tick on AND (no
    /// dependsOn, or one of those rows goes). The LEAST fixed point — start
    /// from nothing and add until nothing more can be added — so two pages
    /// linking only each other behind an unticked hub never publish
    /// themselves. A dependsOn place that is not a row is not a parent.
    /// </summary>
    public static HashSet<string> Going(IReadOnlyList<LinksChecklistRow> rows, IReadOnlyDictionary<string, bool> ticks)
    {
        var places = rows.Select(r => Key(r.Place)).ToHashSet(StringComparer.Ordinal);
        var going = new HashSet<string>(StringComparer.Ordinal);
        bool added = true;
        while (added)
        {
            added = false;
            foreach (var row in rows)
            {
                string place = Key(row.Place);
                if (going.Contains(place) || !Ticked(ticks, place)) continue;
                var parents = row.IsClass ? new List<string>() :
                    row.DependsOn.Select(Key).Where(places.Contains).ToList();
                if (parents.Count == 0 || parents.Any(going.Contains))
                {
                    going.Add(place);
                    added = true;
                }
            }
        }
        return going;
    }

    /// <summary>
    /// Rows a TICKED class brings (#398), each naming the FIRST such class in
    /// the sheet's order. <paramref name="brings"/> is what each class row's
    /// publish would bring — from the publish planner, never from
    /// <c>firstUsedIn</c>. A class row is never brought.
    /// </summary>
    public static Dictionary<string, string> ComingWith(IReadOnlyList<LinksChecklistRow> rows,
        IReadOnlyDictionary<string, bool> ticks, IReadOnlyDictionary<string, IReadOnlyList<string>> brings)
    {
        var classRows = rows.Where(r => r.IsClass).Select(r => Key(r.Place)).ToHashSet(StringComparer.Ordinal);
        var rowPlaces = rows.Select(r => Key(r.Place)).ToHashSet(StringComparer.Ordinal);
        var bringsByKey = brings.ToDictionary(pair => Key(pair.Key), pair => pair.Value, StringComparer.Ordinal);
        var coming = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var cls in rows.Where(r => r.IsClass))
        {
            string k = Key(cls.Place);
            if (!Ticked(ticks, k) || !bringsByKey.TryGetValue(k, out var brought)) continue;
            foreach (string place in brought.Select(Key))
                if (rowPlaces.Contains(place) && !classRows.Contains(place) && !coming.ContainsKey(place))
                    coming[place] = cls.Place;
        }
        return coming;
    }

    /// <summary>Shown locked: has dependsOn among the rows, none of which goes, and comes with no ticked class.</summary>
    public static HashSet<string> Locked(IReadOnlyList<LinksChecklistRow> rows, IReadOnlySet<string> going,
                                         IReadOnlyDictionary<string, string> comingWith)
    {
        var places = rows.Select(r => Key(r.Place)).ToHashSet(StringComparer.Ordinal);
        return rows.Where(r => !r.IsClass)
                   .Select(r => (Key: Key(r.Place), r))
                   .Where(x => x.r.DependsOn.Select(Key).Any(places.Contains) &&
                               // Locked only while nothing it comes under goes: under a
                               // row that goes, an unticked row is simply unticked.
                               !x.r.DependsOn.Select(Key).Any(going.Contains) &&
                               !going.Contains(x.Key) && !comingWith.ContainsKey(x.Key))
                   .Select(x => x.Key)
                   .ToHashSet(StringComparer.Ordinal);
    }

    /// <summary>Shown ticked: going ∪ coming with a ticked class. The Publish button counts these.</summary>
    public static HashSet<string> ShownTicked(IReadOnlySet<string> going, IReadOnlyDictionary<string, string> comingWith)
    {
        var shown = new HashSet<string>(going, StringComparer.Ordinal);
        shown.UnionWith(comingWith.Keys);
        return shown;
    }

    /// <summary>
    /// THE checkbox: the only function the sheet and the harness change a
    /// tick through. A tick or untick on a row that comes with a ticked class
    /// at that moment is IGNORED (its own tick is kept, never written by the
    /// class); otherwise only that row's own tick changes.
    /// </summary>
    public static void Toggle(IReadOnlyList<LinksChecklistRow> rows, Dictionary<string, bool> ticks,
                              IReadOnlyDictionary<string, IReadOnlyList<string>> brings, string place, bool on)
    {
        string k = Key(place);
        if (ComingWith(rows, ticks, brings).ContainsKey(k)) return;
        ticks[k] = on;
    }

    public static Dictionary<string, bool> StartingTicks(IEnumerable<LinksChecklistRow> rows) =>
        rows.ToDictionary(r => Key(r.Place), r => r.Ticked, StringComparer.Ordinal);

    /// <summary>
    /// The order and depth the sheet lists rows in (#385): groups in order; a
    /// row with dependsOn[0] among the rows is listed after that row (and its
    /// own followers), one deeper, inside the parent's group.
    /// </summary>
    public static List<(string Place, int Depth)> ShownOrder(IReadOnlyList<LinksChecklistRow> rows)
    {
        var byKey = rows.ToDictionary(r => Key(r.Place), r => r, StringComparer.Ordinal);
        string? ParentOf(LinksChecklistRow r) =>
            !r.IsClass && r.DependsOn.Count > 0 && byKey.ContainsKey(Key(r.DependsOn[0])) ? Key(r.DependsOn[0]) : null;
        var children = rows.Where(r => ParentOf(r) is not null)
                           .GroupBy(r => ParentOf(r)!)
                           .ToDictionary(g => g.Key, g => g.ToList(), StringComparer.Ordinal);
        var shown = new List<(string, int)>();
        var placed = new HashSet<string>(StringComparer.Ordinal);
        void Add(LinksChecklistRow r, int depth)
        {
            if (!placed.Add(Key(r.Place))) return;
            shown.Add((r.Place, depth));
            if (children.TryGetValue(Key(r.Place), out var under))
                foreach (var child in under) Add(child, depth + 1);
        }
        foreach (string group in GroupOrder)
            foreach (var r in rows.Where(r => r.Group == group && ParentOf(r) is null)) Add(r, 0);
        foreach (var r in rows) Add(r, 0);   // a cycle with no root: listed at the end rather than lost
        return shown;
    }

    private static bool Ticked(IReadOnlyDictionary<string, bool> ticks, string place) =>
        ticks.TryGetValue(place, out bool on) && on;

    // ---- The answered file (file-formats.json → linksChecklistAnswered) ----

    /// <summary>
    /// offeredWhen.onlyWhenSomethingNew: an offer whose every page the teacher
    /// has already answered is not shown again on its own; a new page brings it back.
    /// </summary>
    public static bool HoldsSomethingNew(LinksChecklistOffer offer, IReadOnlySet<string> answeredOffered) =>
        offer.Rows.Any(row => !answeredOffered.Contains(Key(row.Place)));

    /// <summary>
    /// Release the published-pages record on EVERY rollover of the section —
    /// "same" website or "new" (#392 / mac PublishedPagesRecord.release; NOT in
    /// ReleaseSite, which runs only for a new website): each fragment moves
    /// into <c>section&lt;N&gt;.published-pages.previous-yyyy-MM-dd_HHmmss/</c>,
    /// the folder itself is KEPT so an undo can write them back, and the
    /// answered file goes. Every write is reported to <paramref name="undo"/>
    /// so it joins the rollover's own undo entry when one is open.
    /// </summary>
    /// <returns>Where the fragments went, or null when there were none.</returns>
    public static string? ReleasePublishedPages(string courseDirectory, int section, DateTime now, UndoHistory? undo = null)
    {
        string state = Path.Combine(courseDirectory, ".publish_state");
        string record = Path.Combine(state, $"section{section}.published-pages");
        string? moved = null;
        if (Directory.Exists(record))
        {
            var fragments = Directory.GetFiles(record);
            if (fragments.Length > 0)
            {
                moved = Path.Combine(state, $"section{section}.published-pages.previous-" +
                    now.ToString("yyyy-MM-dd_HHmmss", System.Globalization.CultureInfo.InvariantCulture));
                Directory.CreateDirectory(moved);
                foreach (string fragment in fragments)
                {
                    string text = File.ReadAllText(fragment);
                    string to = Path.Combine(moved, Path.GetFileName(fragment));
                    undo?.Touch(fragment, text);
                    undo?.Touch(to, null);
                    File.WriteAllText(to, text);
                    File.Delete(fragment);
                    undo?.Wrote(to, text);
                    undo?.Wrote(fragment, null);
                }
            }
        }
        string answered = AnsweredPathFor(courseDirectory, section);
        if (File.Exists(answered))
        {
            undo?.Touch(answered, File.ReadAllText(answered));
            File.Delete(answered);
            undo?.Wrote(answered, null);
        }
        return moved;
    }

    /// <summary>
    /// Every place the section's published-pages record holds — the union of
    /// every fragment's <c>places</c> (<c>file-formats.json</c> →
    /// <c>publishedPagesRecord</c>), in composed form. A page listed here has
    /// been on a site students could reach, and KEEPS its date when a class
    /// brings it again (<c>datingPagesAClassBrings.publishedBeforeIsRecorded</c>,
    /// Russell's decision 4 on #379). The build's own reader is
    /// <c>build_site.py</c>'s; this is the assistant's publish's.
    /// </summary>
    public static HashSet<string> PublishedPlaces(string courseDirectory, int section)
    {
        var places = new HashSet<string>(StringComparer.Ordinal);
        string folder = Path.Combine(courseDirectory, ".publish_state", $"section{section}.published-pages");
        if (!Directory.Exists(folder)) return places;
        foreach (string fragment in Directory.GetFiles(folder, "*.json"))
        {
            try
            {
                if (JsonNode.Parse(File.ReadAllText(fragment))?["places"] is JsonArray list)
                    foreach (var place in list)
                        if (place is not null) places.Add(Key(place.ToString()));
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { }
        }
        return places;
    }

    /// <summary>The undo's other half, for a caller that is not undoing through <see cref="UndoHistory"/>.</summary>
    public static void PutPublishedPagesBack(string courseDirectory, int section, string released)
    {
        string record = Path.Combine(courseDirectory, ".publish_state", $"section{section}.published-pages");
        Directory.CreateDirectory(record);
        foreach (string fragment in Directory.GetFiles(released))
            File.Move(fragment, Path.Combine(record, Path.GetFileName(fragment)), overwrite: true);
    }

    public static string AnsweredPathFor(string courseDirectory, int section) =>
        Path.Combine(courseDirectory, ".publish_state", $"section{section}.links-checklist-answered.json");

    /// <summary>
    /// Written by the app only, after Publish or Not Now. <c>leftUnticked</c>
    /// holds rows whose OWN tick was off (#399) — a locked row with its own
    /// tick on is not remembered as unticked.
    /// </summary>
    public static void WriteAnswered(string courseDirectory, int section, IEnumerable<string> offered,
                                     IEnumerable<string> leftUnticked, DateTime answeredAtUtc)
    {
        var json = new JsonObject
        {
            ["version"] = 1,
            ["answeredAt"] = answeredAtUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture),
            ["offered"] = new JsonArray(offered.Select(p => (JsonNode)JsonValue.Create(p)!).ToArray()),
            ["leftUnticked"] = new JsonArray(leftUnticked.Select(p => (JsonNode)JsonValue.Create(p)!).ToArray()),
        };
        string path = AnsweredPathFor(courseDirectory, section);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>(offered, leftUnticked) as places in composed form; empty when there is no answer yet.</summary>
    public static (HashSet<string> Offered, HashSet<string> LeftUnticked) ReadAnswered(string courseDirectory, int section)
    {
        var offered = new HashSet<string>(StringComparer.Ordinal);
        var left = new HashSet<string>(StringComparer.Ordinal);
        try
        {
            if (JsonNode.Parse(File.ReadAllText(AnsweredPathFor(courseDirectory, section))) is JsonObject root)
            {
                foreach (var p in root["offered"] as JsonArray ?? new JsonArray()) if (p is not null) offered.Add(Key(p.ToString()));
                foreach (var p in root["leftUnticked"] as JsonArray ?? new JsonArray()) if (p is not null) left.Add(Key(p.ToString()));
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { }
        return (offered, left);
    }
}
