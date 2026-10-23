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

    // ---- The fold (#634, the mac's #622) --------------------------------------

    /// <summary>The fewest rows the table is tall enough for while pages are folded under it (the mac's <c>fewestPlanRowsUnderAFold</c>).</summary>
    public const int FewestRowsUnderAFold = 5;

    /// <summary>A page already the way it was asked to be: the only rows the checkbox folds away (#655).</summary>
    public static bool IsAlreadyRight(Change change) => change is Change.AlreadyVisible or Change.AlreadyHidden;

    /// <summary>
    /// The rows a teacher reads before Go: every page that changes, and every
    /// page that stays for a reason (kept by an unpublish, a linked class left
    /// as it is, no room for a key). In plan order.
    /// </summary>
    public IReadOnlyList<Row> RowsToRead => Rows.Where(row => !IsAlreadyRight(row.Change)).ToList();

    /// <summary>The pages already visible (or already hidden), in plan order: what the checkbox folds.</summary>
    public IReadOnlyList<Row> RowsAlreadyRight => Rows.Where(row => IsAlreadyRight(row.Change)).ToList();

    /// <summary>Whether the plan folds anything: there is something to read AND something already right. A plan with nothing else to read shows every row and no checkbox.</summary>
    public bool FoldsAlreadyRight => Rows.Any(row => IsAlreadyRight(row.Change)) && Rows.Any(row => !IsAlreadyRight(row.Change));

    /// <summary>The rows drawn: every row when nothing folds; else the rows to read, then — open — the pages already right, appended in plan order.</summary>
    public IReadOnlyList<Row> DrawnRows(bool open) =>
        !FoldsAlreadyRight || open ? (FoldsAlreadyRight ? RowsToRead.Concat(RowsAlreadyRight).ToList() : Rows) : RowsToRead;

    /// <summary>The checkbox's words, or null when the plan folds nothing.</summary>
    public string? FoldLabel => FoldsAlreadyRight
        ? AssistWording.MenuPlanShowAlready(RowsAlreadyRight.Count, publishing: RowsAlreadyRight[0].Change == Change.AlreadyVisible)
        : null;

    /// <summary>
    /// How many rows tall the table is, counted with the checkbox UNTICKED —
    /// the rows to read, never fewer than <see cref="FewestRowsUnderAFold"/>
    /// (or every row, when there are fewer) while pages are folded — so
    /// ticking it never grows the dialog (Russell's ruling on the mac, R8).
    /// Before the window's own limit, which the dialog applies after.
    /// </summary>
    public int RowsWhenClosed => FoldsAlreadyRight
        ? Math.Max(RowsToRead.Count, Math.Min(FewestRowsUnderAFold, Rows.Count))
        : Rows.Count;

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
