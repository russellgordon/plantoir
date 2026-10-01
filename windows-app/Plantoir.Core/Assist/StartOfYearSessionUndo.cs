namespace Plantoir.Core.Assist;

/// <summary>
/// The app's own undo of getting a section ready (<c>startOfYear.undo.app</c>):
/// one per section, shared by every window on the working folder, kept only
/// while Plantoir is open. It ends at the section's next deploy started from
/// this app (<see cref="End"/>), at the next change to the section's pages from
/// anywhere (the section's plan code no longer matches the one taken right
/// after the write), and when Plantoir quits (it is never written to disk).
/// </summary>
/// <remarks>
/// <para>Three stores, none reaching another: this, the assistant window's
/// "undo that", and an outside assistant's <c>undo_last_change</c>.</para>
///
/// <para>Not seen, said in documentation/09: a deploy by an outside assistant,
/// a launcher run from a terminal, and — on Windows, as of this piece — a
/// scheduled deploy reaching its moment; after any of those the undo still
/// offers itself until a page changes, and the backup is the honest way back.</para>
/// </remarks>
public static class StartOfYearSessionUndo
{
    public sealed record Entry(
        IReadOnlyDictionary<string, (string Before, string After)> Written,
        string BackupPath,
        string SectionCodeAfter);

    private static readonly Dictionary<string, Entry> Entries = new(StringComparer.OrdinalIgnoreCase);
    private static readonly object Gate = new();

    private static string Key(string folder, string course, int section) =>
        $"{Path.GetFullPath(folder).TrimEnd('\\', '/')}|{course}|{section}";

    public static void Remember(string folder, string course, int section, Entry entry)
    {
        lock (Gate) Entries[Key(folder, course, section)] = entry;
    }

    public static Entry? For(string folder, string course, int section)
    {
        lock (Gate) return Entries.TryGetValue(Key(folder, course, section), out var entry) ? entry : null;
    }

    /// <summary>The section was deployed (or the undo was used): the undo is over.</summary>
    public static void End(string folder, string course, int section)
    {
        lock (Gate) Entries.Remove(Key(folder, course, section));
    }

    /// <summary>For tests.</summary>
    public static void Reset()
    {
        lock (Gate) Entries.Clear();
    }
}
