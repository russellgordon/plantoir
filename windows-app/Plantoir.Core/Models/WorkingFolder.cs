namespace Plantoir.Core.Models;

/// <summary>
/// The one notion of "the same working folder" the app has.
///
/// <para>Windows spells a folder several ways and means one folder each time:
/// <c>C:\Work</c> and <c>C:\work</c> are the same folder, and so are
/// <c>C:\Work</c> and <c>C:\Work\</c>. Every place that asks "is this the
/// folder this window already shows?" must answer the same way, or the
/// answers contradict each other on a path a teacher can actually produce —
/// the OS folder picker returns the true on-disk casing while a remembered
/// path carries whatever casing it was stored with, and re-choosing an open
/// folder from the picker was enough to make the two disagree. When they did,
/// re-choosing the folder that was already open matched no window, so the
/// release-if-unused sweep stopped the container of the folder still on
/// screen and killed a preview running in it (issue #162). The contract says
/// re-choosing the open folder "costs the teacher nothing".</para>
///
/// <para><b>What this deliberately does NOT resolve, and why.</b> It is
/// <see cref="Path.GetFullPath"/>, trailing separators trimmed, compared
/// case-insensitively — and nothing more. It does not open the folder, so it
/// does not follow junctions or symlinks, and it does not decide that a
/// mapped drive (<c>Z:\Courses</c>) and the share behind it
/// (<c>\\server\share\Courses</c>) are one folder. Those answers need the
/// filesystem: <see cref="FolderContainers.PhysicalPath"/> opens a handle and
/// asks it, which is right for NAMING a container (that name must agree byte
/// for byte with what the launcher derives) and wrong here. This question is
/// asked on the UI thread, on every folder change and every window close, and
/// often about a folder that has just been unplugged, renamed or deleted —
/// where a handle open blocks, fails, or quietly answers about the wrong
/// thing. A teacher who reaches the same folder twice by two genuinely
/// different routes loses nothing worse than an extra container stop; a
/// teacher whose network folder is offline must not lose the window.</para>
///
/// <para><b>And one case where it is wrong in the other direction, accepted
/// knowingly.</b> Windows can mark a directory CASE-SENSITIVE per folder
/// (<c>fsutil file setCaseSensitiveInfo</c>, which is what WSL does to the
/// folders it creates), and inside one of those <c>Work</c> and <c>work</c>
/// are two REAL sibling folders that this compares as equal. The consequence
/// is a container stopped for a sibling folder, or a folder change read as
/// no change — recoverable, and the next preview starts the container again.
/// It is accepted rather than closed because closing it means asking the
/// filesystem per comparison, which is the handle open rejected just above,
/// and because a teacher's working folder living inside a WSL-created
/// case-sensitive directory is a shape nobody has met: Plantoir's own
/// working folders are chosen from the ordinary Windows picker.</para>
/// </summary>
public static class WorkingFolder
{
    /// <summary>
    /// The spelling comparisons are made in. Falls back to the path as given
    /// when it cannot be resolved at all — a folder that is merely unusable
    /// must still compare equal to itself.
    /// </summary>
    public static string Resolved(string path)
    {
        if (string.IsNullOrEmpty(path)) return "";
        try
        {
            return Path.GetFullPath(path)
                       .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }
        catch { return path; }
    }

    /// <summary>
    /// Whether two paths name the same working folder. Two nulls are the same
    /// nothing; one null never matches a path.
    /// </summary>
    public static bool IsTheSame(string? one, string? other)
    {
        if (one is null || other is null) return one is null && other is null;
        return string.Equals(Resolved(one), Resolved(other), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Whether pointing a window at <paramref name="chosen"/> leaves
    /// <paramref name="previous"/> behind at all. Re-choosing the folder
    /// already open, however it is spelled, leaves nothing behind — and the
    /// contract says that costs the teacher nothing.
    /// </summary>
    public static bool IsLeavingAFolderBehind(string? previous, string chosen) =>
        previous is not null && !IsTheSame(previous, chosen);

    /// <summary>
    /// Whether any open window still holds this folder. Asked before a
    /// folder's container is stopped, so a wrong "no" does not merely skip a
    /// cleanup — it takes down a preview the teacher is watching.
    /// </summary>
    public static bool AnyWindowStillHolds(IEnumerable<string?> openFolders, string path) =>
        openFolders.Any(open => IsTheSame(open, path));

    /// <summary>The same rule as a comparer, for keyed and de-duplicated collections.</summary>
    public static IEqualityComparer<string> Comparer { get; } = new FolderComparer();

    private sealed class FolderComparer : IEqualityComparer<string>
    {
        public bool Equals(string? one, string? other) => IsTheSame(one, other);

        public int GetHashCode(string value) =>
            StringComparer.OrdinalIgnoreCase.GetHashCode(Resolved(value));
    }
}
