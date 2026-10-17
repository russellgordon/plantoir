using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Assist;

/// <summary>
/// A page plan as the Section menu shows it (#548, the mac's
/// <c>AssistPlanTable</c>, #524): a summary line, one row for EVERY page the
/// plan is about, and the card's other sentences under it.
/// </summary>
/// <remarks>
/// <para><b>Made by the server, drawn by the window.</b> On Windows the plan
/// lives in <c>plantoir-mcp</c>, another process, so the rows are built there
/// from the <see cref="PublishPlan"/> by <see cref="PublishPlan.Tabulate"/> and
/// travel in the answer's <c>_meta</c> under
/// <see cref="AssistToolAnswer.PlanTableKey"/>, ONLY from the menu's server —
/// the precedent is <see cref="AssistToolAnswer.NextClassKey"/>. The window
/// never parses the card's text, and no second planner exists in it.</para>
///
/// <para>Rows come in the contract's order: the changes, the pages an
/// unpublish keeps, the classes a publish left as they are, the pages with no
/// room for a key, the pages already the way asked. None is capped — the card
/// lists fifteen changes and then "…and N more".</para>
/// </remarks>
public sealed record PlanTable(string Summary, IReadOnlyList<PlanTable.Row> Rows, IReadOnlyList<string> Notes)
{
    /// <summary>What happens to a row's page. The cell's words are <see cref="Row.WhatChanges"/>; this is what a reader branches on.</summary>
    public enum Change
    {
        WillBecomeVisible,
        WillBecomeHidden,
        StaysVisible,
        StaysAsItIs,
        StaysExactlyAsItIs,
        AlreadyVisible,
        AlreadyHidden,
    }

    /// <summary>One page. <paramref name="Position"/> is its place in plan order, which sorting falls back on.</summary>
    public sealed record Row(int Position, string Title, string Folder, Change Change, string WhatChanges);

    /// <summary>The table as it travels in <c>_meta</c>; <c>change</c> by name, so no reader depends on numbering.</summary>
    public JsonObject ToJson()
    {
        var rows = new JsonArray();
        foreach (var row in Rows)
        {
            rows.Add(new JsonObject
            {
                ["title"] = row.Title,
                ["folder"] = row.Folder,
                ["change"] = JsonNamingCamel(row.Change),
                ["whatChanges"] = row.WhatChanges,
            });
        }
        var notes = new JsonArray();
        foreach (string note in Notes) notes.Add(note);
        return new JsonObject { ["summary"] = Summary, ["rows"] = rows, ["notes"] = notes };
    }

    /// <summary>
    /// The table back out of a <c>_meta</c> value, or null when it is missing
    /// or not this shape — the dialog then shows the text card, which is
    /// always there.
    /// </summary>
    public static PlanTable? FromJson(JsonNode? node)
    {
        if (node is not JsonObject value) return null;
        try
        {
            if (value["summary"]?.GetValue<string>() is not { } summary) return null;
            if (value["rows"] is not JsonArray rowArray || value["notes"] is not JsonArray noteArray) return null;
            var rows = new List<Row>();
            foreach (var item in rowArray)
            {
                if (item is not JsonObject row) return null;
                string? title = row["title"]?.GetValue<string>();
                string? folder = row["folder"]?.GetValue<string>();
                string? change = row["change"]?.GetValue<string>();
                string? whatChanges = row["whatChanges"]?.GetValue<string>();
                if (title is null || folder is null || whatChanges is null
                    || !Enum.TryParse<Change>(change, ignoreCase: true, out var kind)
                    || !Enum.IsDefined(kind) || int.TryParse(change, out _))
                    return null;
                rows.Add(new Row(rows.Count, title, folder, kind, whatChanges));
            }
            var notes = new List<string>();
            foreach (var note in noteArray)
            {
                if (note?.GetValue<string>() is not { } text) return null;
                notes.Add(text);
            }
            return new PlanTable(summary, rows, notes);
        }
        catch (Exception error) when (error is InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    private static string JsonNamingCamel(Change change)
    {
        string name = change.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }

    // Records compare lists by reference; tests compare tables by content.
    public bool Equals(PlanTable? other) =>
        other is not null && Summary == other.Summary
        && Rows.SequenceEqual(other.Rows) && Notes.SequenceEqual(other.Notes);

    public override int GetHashCode() => HashCode.Combine(Summary, Rows.Count, Notes.Count);
}
