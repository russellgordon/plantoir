namespace Plantoir.Core.Undo;

/// <summary>
/// The rule an op's <c>path</c> (and a reserved <c>move</c>'s <c>from</c> and
/// <c>to</c>) must keep (<c>undoJournal.opKinds.every</c>): relative to the
/// working folder that holds <c>courses/</c>, forward slashes, and never an
/// empty part, a <c>.</c> or <c>..</c> part, a leading slash, a backslash, a
/// drive letter or a NUL. A path that breaks it makes its op unreadable, so the
/// step is a barrier and is never acted on (#899, W1).
///
/// <para>Ordinal and byte-for-byte: the path is spelled as the file system gave
/// it, in its own Unicode form, and is never normalised or case-folded here.
/// NTFS is case-insensitive, but the WRITER is the one that spells a path as
/// the disk has it (W2); a reader only refuses what the rule forbids.</para>
/// </summary>
internal static class UndoPath
{
    internal static bool IsWithinTheRules(string? path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        if (path.Contains('\0') || path.Contains('\\')) return false;
        if (path.StartsWith('/')) return false;
        // A drive letter: C:something or C: on its own. A colon elsewhere is
        // left alone: the reference model (scripts/make_undo_traces.py,
        // readable_op) does not refuse one, and a reader that refused more
        // than the other app would make a barrier of a readable step.
        if (path.Length >= 2 && path[1] == ':' && char.IsAsciiLetter(path[0])) return false;
        foreach (string part in path.Split('/'))
        {
            if (part.Length == 0 || part == "." || part == "..") return false;
        }
        return true;
    }
}
