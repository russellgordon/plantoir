namespace Plantoir.Core.Models;

/// <summary>
/// Reopening the last working folder when Plantoir opens
/// (<c>shared-rules.json</c> → <c>reopeningTheLastWorkingFolder</c>; GitHub
/// issue #320, the mac's #311 and #290). The folder is the teacher's library,
/// not a document window: it is reopened whatever the window setting says, and
/// when it cannot be, the picker says which folder and why — and the folder
/// stays remembered until another is chosen or reopened.
/// </summary>
/// <remarks>
/// <para><b>What Windows can tell apart, and what it cannot.</b> The mac
/// resolves a bookmark and so can follow a renamed folder or refuse one in the
/// Trash; Windows remembers the PATH, so a moved folder reads as gone, which is
/// honest. Three reasons are reachable here: <see cref="Gone"/>,
/// <see cref="DriveNotConnected"/> (the path's drive root does not exist — an
/// unplugged USB disk or an unmapped network letter) and
/// <see cref="Unreadable"/> — said ONLY where listing the folder threw
/// <see cref="UnauthorizedAccessException"/>, because <c>Directory.Exists</c>
/// cannot tell a denied folder from a missing one in every case, and a denied
/// folder must never be called gone. <c>inTrash</c>, <c>privacyDenied</c> and
/// the two outside-home keys are the mac's (<c>appliesOn: ["mac"]</c>).</para>
/// </remarks>
public static class LastWorkingFolder
{
    public const string Gone = "gone";
    public const string DriveNotConnected = "driveNotConnected";
    public const string Unreadable = "unreadable";

    /// <summary>The three sentences Windows can say, from the contract's <c>wording</c>.</summary>
    public static readonly IReadOnlyDictionary<string, string> Wording = new Dictionary<string, string>
    {
        [Gone] = "“{folder}”, the working folder you had open last time, can’t be found — if you moved it, choose it again from its new place.",
        [DriveNotConnected] = "“{folder}”, the working folder you had open last time, is on a drive that isn’t connected — connect it and open Plantoir again, or choose another folder.",
        [Unreadable] = "“{folder}”, the working folder you had open last time, can’t be opened because you don’t have permission to read it — check who is allowed to open it, then choose it again.",
    };

    /// <summary>
    /// Null when the folder can be reopened; otherwise the wording key that
    /// says why. An emptied folder, or one that is no longer a working folder,
    /// still reopens — the window then says what it says about any folder.
    /// </summary>
    public static string? WhyItCannotBeReopened(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return Gone;
        if (Directory.Exists(path))
        {
            try
            {
                using var entries = Directory.EnumerateFileSystemEntries(path).GetEnumerator();
                entries.MoveNext();
                return null;
            }
            catch (UnauthorizedAccessException) { return Unreadable; }
            catch (IOException) { return Gone; }
        }
        string? root = SafeRoot(path);
        if (root is not null && !Directory.Exists(root)) return DriveNotConnected;
        return Gone;
    }

    private static string? SafeRoot(string path)
    {
        try { return Path.GetPathRoot(path) is { Length: > 0 } root ? root : null; }
        catch (ArgumentException) { return null; }
    }

    /// <summary>The one sentence the picker shows, naming the folder by its own name.</summary>
    public static string Sentence(string reason, string path)
    {
        string name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (string.IsNullOrEmpty(name)) name = path;
        return (Wording.TryGetValue(reason, out var template) ? template : Wording[Gone])
            .Replace("{folder}", name, StringComparison.Ordinal);
    }

    /// <summary>
    /// The folders the windows open on at launch, in order, null for the
    /// picker. Windows has no system restoration: when RestoreWindowsOnLaunch
    /// is on, the remembered windows come back; otherwise — or when none were
    /// left open, because the teacher closed the last window first — ONE
    /// window opens on the last working folder.
    /// </summary>
    public static IReadOnlyList<string?> FoldersToOpen(bool windowsComeBack, IReadOnlyList<string> windowsLeftOpen,
                                                       string? lastWorkedIn) =>
        windowsComeBack && windowsLeftOpen.Count > 0
            ? windowsLeftOpen.Select(folder => (string?)folder).ToList()
            : new List<string?> { lastWorkedIn };

    /// <summary>"the window's own folder" or "the last working folder" — which one a trail line is about.</summary>
    public static string WhichFolder(bool windowsOwn) =>
        windowsOwn ? "the window's own folder" : "the last working folder";
}
