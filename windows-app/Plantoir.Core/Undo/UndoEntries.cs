using Plantoir.Core.Models;

namespace Plantoir.Core.Undo;

/// <summary>
/// One top-level front-matter key's ENTRY, as an <c>editLine</c> op records
/// and checks it (<c>undoJournal.opKinds.editLine</c>, #899 piece W1).
///
/// <para>The block is found with <see cref="PageVisibilityReader.FenceIndices"/>,
/// the reader the publish path already uses and the twin of the mac's
/// <c>fenceIndices</c>: three dashes or more, blank lines allowed before the
/// opening fence. It is used as it is (L5 of the plan review): a byte-order
/// mark before the fence is not a space or a tab to it, so the first line is
/// not a fence and the page has no block, which is exactly what the contract
/// says.</para>
///
/// <para>An entry is a column-0 <c>key:</c> line (quotes round the key taken
/// off) and the lines below it that start with a space or a tab (and are not
/// blank) or are column-0 sequence items (<c>-</c>, never <c>---</c>); a blank
/// line, a column-0 comment or the next key ends it. Its text is those lines
/// joined with <c>\n</c>, each keeping its carriage return. This is the line
/// model of <c>scripts/make_undo_traces.py</c> (<c>Layout</c>), the reference
/// both suites check the traces against, rule for rule.</para>
///
/// <para>Everything is ordinal: an entry is compared code unit for code unit,
/// which for text decoded from strict UTF-8 is byte for byte. Never
/// <c>string.Equals</c> with a culture, which calls a precomposed é equal to
/// an e and a combining accent (the checkCase "the same title in another
/// Unicode form").</para>
/// </summary>
internal static class UndoEntries
{
    /// <summary>What a page holds for one key.</summary>
    internal enum ReadingKind { Absent, Unreadable, Entry }

    internal readonly record struct Reading(ReadingKind Kind, string? Text)
    {
        internal static Reading Absent => new(ReadingKind.Absent, null);
        internal static Reading Unreadable => new(ReadingKind.Unreadable, null);

        /// <summary>Does this reading stand for the recorded entry (null: no such key)?</summary>
        internal bool Matches(string? expected) => Kind switch
        {
            ReadingKind.Absent => expected is null,
            ReadingKind.Entry => expected is not null && string.Equals(Text, expected, StringComparison.Ordinal),
            _ => false,
        };
    }

    /// <summary>The block's lines and the entries in it, or null when the page has no complete block.</summary>
    internal sealed class Layout
    {
        internal required string[] Lines { get; init; }
        internal required int Open { get; init; }
        internal required int Close { get; init; }

        /// <summary>Each entry: its key, its first line and the line after its last.</summary>
        internal required IReadOnlyList<(string Key, int Start, int End)> Entries { get; init; }

        internal IEnumerable<(string Key, int Start, int End)> EntriesFor(string key) =>
            Entries.Where(entry => string.Equals(entry.Key, key, StringComparison.Ordinal));

        internal string TextOf((string Key, int Start, int End) entry) =>
            string.Join("\n", Lines[entry.Start..entry.End]);

        /// <summary>The key of the entry before this one (null: it is the first).</summary>
        internal string? KeyBefore((string Key, int Start, int End) entry)
        {
            string? previous = null;
            foreach (var candidate in Entries)
            {
                if (candidate.Start == entry.Start) return previous;
                previous = candidate.Key;
            }
            return previous;
        }
    }

    internal static Layout? LayoutOf(string text)
    {
        if (PageVisibilityReader.FenceIndices(text) is not { } fences) return null;
        string[] lines = text.Split('\n');
        var entries = new List<(string, int, int)>();
        int index = fences.Open + 1;
        while (index < fences.Close)
        {
            if (TopLevelKey(lines[index]) is not { } key) { index++; continue; }
            int end = index + 1;
            while (end < fences.Close && ContinuesAValue(lines[end])) end++;
            entries.Add((key, index, end));
            index = end;
        }
        return new Layout { Lines = lines, Open = fences.Open, Close = fences.Close, Entries = entries };
    }

    /// <summary>The key a column-0 line names, or null when it names none.</summary>
    internal static string? TopLevelKey(string rawLine)
    {
        string line = PageVisibilityReader.TrimCarriageReturn(rawLine);
        if (line.Length == 0 || line[0] is ' ' or '\t' or '#' or '-') return null;
        int colon = line.IndexOf(':', StringComparison.Ordinal);
        if (colon < 0) return null;
        // Trim() mirrors the reference model's Python strip(), which strips
        // every Unicode space; the two agree on every character either suite
        // has ever met, and a disagreement would make a barrier, not a guess.
        string key = line[..colon].Trim();
        if (key.Length >= 2 && key[0] is '"' or '\'' && key[^1] == key[0]) key = key[1..^1];
        return key.Length == 0 ? null : key;
    }

    /// <summary>Does this line carry on the value of the entry above it?</summary>
    internal static bool ContinuesAValue(string rawLine)
    {
        string line = PageVisibilityReader.TrimCarriageReturn(rawLine);
        if (line.Length == 0) return false;
        if (line[0] is ' ' or '\t') return line.Trim().Length > 0;
        return line[0] == '-' && !line.StartsWith("---", StringComparison.Ordinal);
    }

    /// <summary>What the page holds for this key: its one entry, none, or something this reader will not guess at.</summary>
    internal static Reading ReadingOf(string key, string text)
    {
        if (LayoutOf(text) is not { } layout)
            return PageVisibilityReader.OpensAFence(text) ? Reading.Unreadable : Reading.Absent;
        var found = layout.EntriesFor(key).ToList();
        if (found.Count == 0) return Reading.Absent;
        if (found.Count > 1) return Reading.Unreadable;   // the key there twice: never a guess
        return new Reading(ReadingKind.Entry, layout.TextOf(found[0]));
    }

    /// <summary>
    /// The page with this op's entry moved from <paramref name="source"/> to
    /// <paramref name="target"/> (either null: no such key), or null when the
    /// page does not hold <paramref name="source"/> or the entry cannot be
    /// placed. Pure: it changes no file.
    ///
    /// <para>An entry put back goes after the entry named <c>afterKey</c> when
    /// the page has exactly one such entry, otherwise first in the block; an
    /// entry taken out of a block the step created takes the fences (and the
    /// line feed after the closing one) with it when it was the block's only
    /// content and the block starts the page.</para>
    /// </summary>
    internal static string? Move(UndoOp op, string? source, string? target, string text)
    {
        if (op.Key is not { } key) return null;
        if (!ReadingOf(key, text).Matches(source)) return null;
        if (string.Equals(source, target, StringComparison.Ordinal)) return text;

        if (LayoutOf(text) is not { } layout)
        {
            if (target is null || !op.CreatedTheBlock) return null;
            return "---\n" + target + "\n---\n" + text;
        }

        var lines = layout.Lines.ToList();
        var found = layout.EntriesFor(key).ToList();
        if (found.Count > 0)
        {
            var entry = found[0];
            if (target is not null)
            {
                lines.RemoveRange(entry.Start, entry.End - entry.Start);
                lines.InsertRange(entry.Start, target.Split('\n'));
                return string.Join("\n", lines);
            }
            lines.RemoveRange(entry.Start, entry.End - entry.Start);
            bool only = layout.Entries.Count == 1;
            bool empty = only && layout.Close - layout.Open - 1 == entry.End - entry.Start;
            if (op.CreatedTheBlock && empty && layout.Open == 0) lines.RemoveRange(0, 2);
            return string.Join("\n", lines);
        }

        if (target is null) return text;
        int insertAt = layout.Open + 1;
        if (op.AfterKey is { } afterKey)
        {
            var anchors = layout.EntriesFor(afterKey).ToList();
            if (anchors.Count == 1) insertAt = anchors[0].End;
        }
        lines.InsertRange(insertAt, target.Split('\n'));
        return string.Join("\n", lines);
    }
}
