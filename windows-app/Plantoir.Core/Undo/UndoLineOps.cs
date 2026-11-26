using System.Text.Json;
using System.Text.Json.Nodes;

namespace Plantoir.Core.Undo;

/// <summary>
/// The traces' writer (<c>JournaledWrite.settingEntry</c>'s rule on the mac,
/// <c>setting_entry</c> in <c>scripts/make_undo_traces.py</c>), in the product
/// since #899 W2b: a page's text with one top-level front-matter key set to a
/// line. W7 replaces it with the real actions; until then the traces and the
/// stack cases describe their steps with it, so both apps make byte-identical
/// changes from the same data.
/// </summary>
internal static class JournaledSetting
{
    /// <summary>
    /// The entry replaced when the key is there once, inserted after the
    /// opening fence when it is not, a block made when the page has none;
    /// null (the page left alone) when the key is there more than once. A
    /// leading byte-order mark is DROPPED first, as today's publish does
    /// (<c>File.ReadAllText</c> drops one, and the text is written back
    /// without it: the contract review's INCOMPLETE 5).
    /// </summary>
    internal static string? SettingEntry(string key, string line, string text)
    {
        if (text.StartsWith('﻿')) text = text[1..];
        if (UndoEntries.LayoutOf(text) is not { } layout) return "---\n" + line + "\n---\n" + text;
        var found = layout.EntriesFor(key).ToList();
        if (found.Count > 1) return null;
        var lines = layout.Lines.ToList();
        if (found.Count == 1)
        {
            var entry = found[0];
            string replacement = line;
            if (lines[entry.Start].EndsWith('\r') && !line.EndsWith('\r')) replacement += "\r";
            lines.RemoveRange(entry.Start, entry.End - entry.Start);
            lines.Insert(entry.Start, replacement);
            return string.Join("\n", lines);
        }
        string inserted = line;
        if (lines[layout.Open].EndsWith('\r') && !line.EndsWith('\r')) inserted += "\r";
        lines.Insert(layout.Open + 1, inserted);
        return string.Join("\n", lines);
    }
}

/// <summary>
/// The ops that describe one file's change (#899 W2b; the mac's
/// <c>JournaledWrite.ops(for:)</c>, <c>line_ops</c> and <c>verified</c> in the
/// reference model): one <c>editLine</c> per front-matter entry it changed
/// when that is ALL it changed, otherwise one <c>writeFile</c>. The line form is
/// chosen only when applying its ops to the before text gives the after text
/// byte for byte AND undoing them gives the before text back, both through the
/// product's own <see cref="UndoEntries.Move"/>, so a page the line model
/// cannot describe exactly is recorded whole rather than guessed.
/// </summary>
internal static class UndoLineOps
{
    private static JsonObject EditLine(string path, string key, string? before, string? after, string? afterKey, bool created)
    {
        var op = new JsonObject { ["kind"] = "editLine", ["path"] = path, ["key"] = key, ["before"] = before, ["after"] = after, ["afterKey"] = afterKey };
        if (created) op["createdTheBlock"] = true;
        return op;
    }

    /// <summary>An op as a reader of this version reads it back.</summary>
    internal static UndoOp Read(JsonObject op)
    {
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    private static JsonArray? Verified(List<JsonObject> ops, string before, string after)
    {
        string? forward = before;
        foreach (JsonObject op in ops)
        {
            UndoOp read = Read(op);
            forward = UndoEntries.Move(read, read.Before, read.After, forward);
            if (forward is null) return null;
        }
        if (!string.Equals(forward, after, StringComparison.Ordinal)) return null;
        string? backward = after;
        foreach (JsonObject op in Enumerable.Reverse(ops))
        {
            UndoOp read = Read(op);
            backward = UndoEntries.Move(read, read.After, read.Before, backward);
            if (backward is null) return null;
        }
        if (!string.Equals(backward, before, StringComparison.Ordinal)) return null;
        return new JsonArray(ops.Select(op => (JsonNode)op).ToArray());
    }

    /// <summary>The line ops of one file's change, or null when the line model cannot reproduce it both ways.</summary>
    internal static JsonArray? For(string path, string before, string after)
    {
        if (string.Equals(before, after, StringComparison.Ordinal)) return [];
        if (UndoEntries.LayoutOf(after) is not { } afterLayout) return null;
        var result = new List<JsonObject>();
        if (UndoEntries.LayoutOf(before) is not { } beforeLayout)
        {
            if (afterLayout.Entries.Count != 1) return null;
            var entry = afterLayout.Entries[0];
            result.Add(EditLine(path, entry.Key, null, afterLayout.TextOf(entry), null, true));
            return Verified(result, before, after);
        }
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in afterLayout.Entries)
        {
            if (!seen.Add(entry.Key)) return null;
            var inBefore = beforeLayout.EntriesFor(entry.Key).ToList();
            if (inBefore.Count > 1) return null;
            string afterText = afterLayout.TextOf(entry);
            string? beforeText = inBefore.Count == 1 ? beforeLayout.TextOf(inBefore[0]) : null;
            if (string.Equals(beforeText, afterText, StringComparison.Ordinal)) continue;
            result.Add(EditLine(path, entry.Key, beforeText, afterText, afterLayout.KeyBefore(entry), false));
        }
        foreach (var entry in beforeLayout.Entries)
        {
            if (seen.Contains(entry.Key)) continue;
            if (beforeLayout.EntriesFor(entry.Key).Count() > 1) return null;
            seen.Add(entry.Key);
            result.Add(EditLine(path, entry.Key, beforeLayout.TextOf(entry), null, beforeLayout.KeyBefore(entry), false));
        }
        if (result.Count == 0) return null;
        return Verified(result, before, after);
    }

    /// <summary>
    /// The ops of one file's change: line ops where the line model reproduces
    /// it both ways, else one <c>writeFile</c> naming its before and after
    /// blobs (whose bytes the caller stores in the same hold as the begin).
    /// </summary>
    internal static JsonArray ForAFile(string path, byte[]? before, byte[]? after)
    {
        string? beforeText = before is null ? null : UndoCheck.DecodeStrictly(before);
        string? afterText = after is null ? null : UndoCheck.DecodeStrictly(after);
        if (beforeText is not null && afterText is not null && For(path, beforeText, afterText) is { } lineOps)
            return lineOps;
        var op = new JsonObject { ["kind"] = "writeFile", ["path"] = path };
        var blobs = new JsonArray();
        if (before is not null) { string name = UndoCheck.Sha(before); op["beforeSha"] = name; blobs.Add(name); }
        if (after is not null) { string name = UndoCheck.Sha(after); op["afterSha"] = name; blobs.Add(name); }
        op["blobs"] = blobs;
        return new JsonArray(op);
    }
}
