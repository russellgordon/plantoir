namespace Plantoir.Core.Models;

/// <summary>
/// File ▸ Open Recent: the working folders a teacher has OPENED, newest first
/// (#488, the mac's #457; <c>contracts/shared-rules.json</c> →
/// <c>openRecent</c>, run by <c>OpenRecentContractTests</c>). The pure half:
/// what the list becomes when a folder is opened, and what each entry is
/// called. The app keeps the list in <see cref="AppSettings.RecentWorkingFolders"/>.
/// </summary>
/// <remarks>
/// <para><b>Recorded on OPEN, never on focus.</b> A folder joins the list when
/// it is chosen with Open Working Folder…, chosen from Open Recent, or reopened
/// by the app at launch — never when a window comes to the front, which
/// happens on every switch between windows and would reorder the list each
/// time (the trap the mac's plan review measured). Ctrl+N's window inherits a
/// folder and records nothing either: it is neither a choice nor a reopen.</para>
///
/// <para><b>One entry per folder however spelled</b>, compared with
/// <see cref="WorkingFolder.IsTheSame"/> — the app's one notion of sameness
/// (case-insensitive, trailing separator trimmed) — and kept at the spelling
/// just opened. The contract's spelling case is <c>appliesOn: ["mac"]</c>: the
/// mac's disk decides it; Windows compares its own way.</para>
///
/// <para>A folder that has gone is NOT filtered out of the list: choosing it
/// says why it could not be opened (<see cref="OpenRecentWording"/>).</para>
/// </remarks>
public static class RecentWorkingFolders
{
    /// <summary>How many folders the menu holds (<c>openRecent.cap</c>).</summary>
    public const int Cap = 10;

    /// <summary>
    /// <paramref name="opened"/> brought to the top of <paramref name="before"/>.
    /// <c>Writes</c> is false — and the list unchanged — when it was already
    /// first, spelled the same way: opening the folder at the top writes nothing.
    /// </summary>
    public static (IReadOnlyList<string> After, bool Writes) Adding(IReadOnlyList<string> before, string opened)
    {
        if (before.Count > 0 && string.Equals(before[0], opened, StringComparison.Ordinal))
            return (before, false);
        var after = new List<string> { opened };
        foreach (string entry in before)
        {
            if (WorkingFolder.IsTheSame(entry, opened)) continue;
            if (after.Count >= Cap) break;
            after.Add(entry);
        }
        return (after, true);
    }

    /// <summary>
    /// The list a computer that has never written one starts from: the last
    /// working folder, then the folders of the remembered windows, once each —
    /// so Open Recent is not empty on the first launch after the update.
    /// </summary>
    public static IReadOnlyList<string> Seed(string? lastWorkingFolder, IEnumerable<string> rememberedWindowFolders)
    {
        var seeded = new List<string>();
        if (!string.IsNullOrWhiteSpace(lastWorkingFolder)) seeded.Add(lastWorkingFolder);
        foreach (string folder in rememberedWindowFolders)
        {
            if (string.IsNullOrWhiteSpace(folder)) continue;
            if (seeded.Any(existing => WorkingFolder.IsTheSame(existing, folder))) continue;
            if (seeded.Count >= Cap) break;
            seeded.Add(folder);
        }
        return seeded;
    }

    /// <summary>
    /// What each entry is called in the menu (<c>openRecent.titleRule</c>): the
    /// folder's own name, and — when two entries share a name — the folder it
    /// is in as well ("Courses — 2025"), then as much more of the path as tells
    /// them apart, joined with '/' ("Courses — A/2025"). A folder at the top of
    /// a drive is told apart by its drive: <c>C:\Courses</c> and
    /// <c>D:\Courses</c> are "Courses — C:" and "Courses — D:".
    /// </summary>
    public static IReadOnlyList<string> Titles(IReadOnlyList<string> paths)
    {
        var names = paths.Select(NameOf).ToList();
        var titles = new List<string>();
        for (int index = 0; index < paths.Count; index++)
        {
            string name = names[index];
            var others = Enumerable.Range(0, paths.Count)
                .Where(other => other != index && names[other] == name)
                .Select(other => paths[other])
                .ToList();
            titles.Add(others.Count == 0 ? name : name + " — " + DistinguishingParent(paths[index], others));
        }
        return titles;
    }

    /// <summary>A folder's own name, or its whole path when it has none (a drive root).</summary>
    private static string NameOf(string path)
    {
        string trimmed = path.TrimEnd('\\', '/');
        string name = Path.GetFileName(trimmed);
        return string.IsNullOrEmpty(name) ? path : name;
    }

    /// <summary>The names of the folders <paramref name="path"/> is in, outermost first; a drive keeps its letter ("C:").</summary>
    private static IReadOnlyList<string> ParentNames(string path)
    {
        string parent = Path.GetDirectoryName(path.TrimEnd('\\', '/')) ?? "";
        return parent.Split('\\', '/').Where(part => part.Length > 0).ToList();
    }

    /// <summary>The fewest trailing parent names of <paramref name="path"/> that no path in <paramref name="others"/> shares.</summary>
    private static string DistinguishingParent(string path, IReadOnlyList<string> others)
    {
        var parents = ParentNames(path);
        for (int depth = 1; depth <= parents.Count; depth++)
        {
            string suffix = Trailing(depth, parents);
            if (!others.Any(other => Trailing(depth, ParentNames(other)) == suffix)) return suffix;
        }
        return Path.GetDirectoryName(path.TrimEnd('\\', '/')) ?? path;
    }

    private static string Trailing(int count, IReadOnlyList<string> names) =>
        string.Join("/", names.Skip(Math.Max(0, names.Count - count)));
}

/// <summary>
/// What a teacher is told when a folder chosen from File ▸ Open Recent cannot
/// be opened (<c>openRecent.wording</c>; <c>OpenRecentContractTests</c>
/// compares each with the contract). New sentences rather than
/// <see cref="LastWorkingFolder.Wording"/>'s, which say "the working folder
/// you had open LAST TIME … open Plantoir again" — wrong for a folder just
/// picked from a menu. Only the three reasons Windows can tell apart
/// (<see cref="LastWorkingFolder.WhyItCannotBeReopened"/>) have a sentence
/// here: <c>inTrash</c> and <c>privacyDenied</c> are the mac's, unreachable on
/// a computer that remembers a path rather than a bookmark.
/// </summary>
public static class OpenRecentWording
{
    public const string TitleTemplate = "“{folder}” could not be opened";
    public const string Gone = "It can’t be found — if you moved it, choose it again with File ▸ Open Working Folder… from its new place.";
    public const string DriveNotConnected = "It is on a drive that isn’t connected — connect the drive, then choose it again.";
    public const string Unreadable = "You don’t have permission to read it — check who is allowed to open it, then choose it again.";

    /// <summary>The dialog's title, naming the folder by its own name.</summary>
    public static string Title(string path)
    {
        string trimmed = path.TrimEnd('\\', '/');
        string name = Path.GetFileName(trimmed);
        return TitleTemplate.Replace("{folder}", string.IsNullOrEmpty(name) ? path : name, StringComparison.Ordinal);
    }

    /// <summary>The sentence for a <see cref="LastWorkingFolder"/> reason key.</summary>
    public static string Sentence(string reason) => reason switch
    {
        LastWorkingFolder.DriveNotConnected => DriveNotConnected,
        LastWorkingFolder.Unreadable => Unreadable,
        _ => Gone,
    };
}
