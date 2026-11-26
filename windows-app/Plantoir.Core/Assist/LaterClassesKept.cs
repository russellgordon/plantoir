using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

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
/// <para>Written by the app only, never the build: when a class is left ticked
/// at Deploy and Deploy Ticked is pressed (#726), when a class is published by
/// naming its date, and when a class dated later is published from the links
/// checklist. Never from Section ▸ Publish Pages…, which asks nothing: a class
/// published there for a preview check must still be asked about at Deploy
/// (<c>file-formats.json</c> → <c>laterClassesKept.writtenBy</c>). Removed on rollover, with the
/// checklist's answer (<see cref="LinksChecklist.ReleasePublishedPages"/>).
/// A record that cannot be read costs the question once more, nothing else.
/// Publish Class for a Date plans the record inside its ONE step (#899 W7a):
/// a record planned and then unwritable at the swap refuses the whole
/// publish, all or none ("Nothing was changed: …"), the class left as it
/// was (<c>UndoWholeUnitAndByDateStepTests.APublishClassForADateWhoseRecordCannotBeWrittenAtTheSwapChangesNothing</c>).</para>
/// </remarks>
public static class LaterClassesKept
{
    /// <summary>One kept class: its place (without <c>.md</c>) and the day its <c>created</c> named, <c>yyyy-MM-dd</c>.</summary>
    public sealed record Row(string Place, string Date);

    /// <summary>The record's path for one section.</summary>
    public static string PathFor(string courseDirectory, int section) =>
        Path.Combine(courseDirectory, ".publish_state", $"section{section}.later-classes-kept.json");

    /// <summary>The kept rows on disk; empty when there is no record or it cannot be read.</summary>
    public static IReadOnlyList<Row> Read(string courseDirectory, int section) => Read(courseDirectory, section, null);

    /// <summary>
    /// The kept rows as <paramref name="read"/> gives the record's text (null:
    /// no record), so an action planning through an Undo step reads the record
    /// as the step will leave it (#899 W7a); the disk's when it is null.
    /// </summary>
    internal static IReadOnlyList<Row> Read(string courseDirectory, int section, Func<string, string?>? read)
    {
        try
        {
            string path = PathFor(courseDirectory, section);
            string? text = read is not null ? read(path) : File.Exists(path) ? File.ReadAllText(path) : null;
            if (text is null) return Array.Empty<Row>();
            if (JsonNode.Parse(text)?["kept"] is not JsonArray rows) return Array.Empty<Row>();
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
    /// The teacher's answer at Deploy (#726): the ticked classes kept, as ONE
    /// step of that one record (#899 W7b2-7; the mac's
    /// <c>KeptRecord.write</c> on a step of its own, key
    /// <c>keepClassesDatedLater</c>, made by <c>sheet</c>), its folder made
    /// by the swap. The caller names the working folder and the maker, as
    /// <see cref="TimetableMemory.WriteDown(string, string, int, IEnumerable{DateOnly}, string, DateOnly, string?)"/>
    /// does. Never told to today's undo (it never was); the bytes are
    /// Windows' own, as <see cref="RecordKeeping"/> makes them. Nothing dated
    /// to add, or the same answer at the same moment, makes no step: the
    /// same answer later stamps its new moment, a step of its own, as the
    /// mac's <c>KeptRecord.adding</c> stamps <c>Date()</c>.
    /// </summary>
    /// <param name="workspacePath">The folder holding <c>courses\</c>, or null when the course is not inside one (the step is then made without the list, in shadow).</param>
    /// <returns>False when the record could not be written: it costs the question once more at the next Deploy, nothing else, and the deploy goes on (the mac's <c>try?</c>).</returns>
    public static bool KeepAtDeploy(string? workspacePath, string courseCode, string courseDirectory, int section,
                                    IEnumerable<ClassesDatedLater.Page> pages, DateTime? now = null, string? madeBy = null)
        => KeepAtDeploy(workspacePath, courseCode, courseDirectory, section, pages, now,
                        new UndoStepMaker(madeBy ?? "sheet", "keepClassesDatedLater"), undo: null, door: null);

    /// <summary>The same, on a test's own list and door (this process's when null).</summary>
    internal static bool KeepAtDeploy(string? workspacePath, string courseCode, string courseDirectory, int section,
                                      IEnumerable<ClassesDatedLater.Page> pages, DateTime? now,
                                      UndoStepMaker by, UndoForThisProcess? undo, UndoDoor? door)
    {
        try
        {
            var step = new UndoActionStep(by, workspacePath, courseCode, section, undo: undo, door: door);
            if (!PlanInto(step, courseDirectory, section, pages, now)) return true;
            step.Make();
            return true;
        }
        // The record is in, what it held kept beside it: the classes ARE kept
        // (the trail's own line names the kept file, from the door).
        catch (UndoStepLeftPartWayException) { return true; }
        // Anything else, the door's refusal or an error that is not the
        // disk's (a stop with the switch on): the record is not written, and
        // the deploy goes on (W7b2-7 review 1, LOW 1).
        catch { return false; }
    }

    /// <summary>
    /// Plans the record with <paramref name="pages"/> added in
    /// <paramref name="step"/>, without making it, reading what is kept as
    /// the step will leave it: the answer at Deploy's own step
    /// (<see cref="KeepAtDeploy(string?, string, string, int, IEnumerable{ClassesDatedLater.Page}, DateTime?, string?)"/>),
    /// and a file of Publish Class for a Date's step (#899 W7a), where it
    /// makes no step of its own. Never told to today's undo. False, and
    /// nothing planned, when there is nothing dated to add.
    /// </summary>
    internal static bool PlanInto(UndoActionStep step, string courseDirectory, int section,
                                  IEnumerable<ClassesDatedLater.Page> pages, DateTime? now = null)
    {
        if (RecordKeeping(Read(courseDirectory, section, step.ReadTextIfAny), pages, now) is not { } record) return false;
        step.Write(PathFor(courseDirectory, section), record, todaysUndoKeepsIt: false);
        return true;
    }

    /// <summary>
    /// The record's text once <paramref name="pages"/> are added to
    /// <paramref name="existing"/> (as every writer plans it), or null
    /// when there is nothing dated to add. An Undo step plans this text
    /// (#899 W7a: Publish Class for a Date).
    /// </summary>
    internal static string? RecordKeeping(IReadOnlyList<Row> existing, IEnumerable<ClassesDatedLater.Page> pages,
                                          DateTime? now = null)
    {
        var adding = pages.Where(page => page.Date is not null)
                          .Select(page => new Row(page.Place, DateText.Iso(page.Date!.Value)))
                          .ToList();
        if (adding.Count == 0) return null;
        var rows = existing
            .Where(row => !adding.Any(page => page.Place == row.Place))
            .Concat(adding)
            .ToList();
        var kept = new JsonArray();
        foreach (var row in rows) kept.Add(new JsonObject { ["place"] = row.Place, ["date"] = row.Date });
        var record = new JsonObject
        {
            ["version"] = 1,
            ["answeredAt"] = (now ?? DateTime.UtcNow).ToUniversalTime()
                .ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture),
            ["kept"] = kept,
        };
        return record.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }
}
