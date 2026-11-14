using System.Diagnostics;
using System.Globalization;

namespace Plantoir.Tests;

/// <summary>
/// Folders in %TEMP% that belong to ONE test process, and a sweep that only
/// ever removes a folder whose owner is provably gone (#882).
///
/// <para>The fault this replaces: <c>StubProgramCollection</c> deleted every
/// <c>%TEMP%\plantoir-probe*</c> folder when it first ran, so a second test
/// process on the PC (a reviewer's filtered run, another worktree's suite)
/// deleted the stub programs of a suite that was already running, which then
/// failed with <c>DirectoryNotFoundException</c> on <c>probe.exe</c>. The
/// figure add-ons tests swept <c>plantoir-581-*</c> the same way.</para>
///
/// <para>A folder made here is named
/// <c>&lt;prefix&gt;&lt;process id&gt;-&lt;process start, UTC ticks&gt;-&lt;random&gt;</c>.
/// The sweep removes one only when no live process has that id AND that start
/// time (a process id alone is recycled), and only when the folder is older
/// than <see cref="SafeAge"/>. A process whose start time cannot be read (one
/// of another account's, say) counts as alive: a folder that cannot be proved
/// orphaned is left alone. Prefixes must not match a pattern an OLDER copy of
/// this suite still sweeps (<c>plantoir-probe*</c>, <c>plantoir-581-*</c>), so
/// old and new runs on one PC cannot delete each other's folders.</para>
/// </summary>
internal static class RunOwnedTempFolders
{
    /// <summary>A crashed run's folder is swept only once it is at least this old.</summary>
    internal static readonly TimeSpan SafeAge = TimeSpan.FromHours(1);

    private static readonly Lazy<string> Owner = new(() =>
    {
        using var self = Process.GetCurrentProcess();
        return OwnerTag(Environment.ProcessId, StartTicks(self));
    });

    /// <summary>This process's part of the name: its id and its start time.</summary>
    internal static string ThisRun => Owner.Value;

    internal static string OwnerTag(int processId, long startTicks) =>
        processId.ToString(CultureInfo.InvariantCulture) + "-" + startTicks.ToString(CultureInfo.InvariantCulture);

    /// <summary>Sweeps this prefix's orphans, then makes a folder this process owns.</summary>
    internal static string Create(string prefix, Action<string>? beforeDeletingOrphan = null)
    {
        SweepOrphans(prefix, beforeDeletingOrphan);
        return Directory.CreateTempSubdirectory(prefix + ThisRun + "-").FullName;
    }

    /// <summary>Removes the folders under this prefix whose owning process is gone and that are older than <see cref="SafeAge"/>.</summary>
    internal static IReadOnlyList<string> SweepOrphans(string prefix, Action<string>? beforeDeletingOrphan = null,
                                                       string? root = null, Func<int, long, bool>? ownerIsAlive = null)
    {
        root ??= Path.GetTempPath();
        ownerIsAlive ??= OwnerIsAlive;
        var swept = new List<string>();
        IEnumerable<string> candidates;
        try { candidates = Directory.EnumerateDirectories(root, prefix + "*").ToList(); }
        catch { return swept; }
        foreach (string folder in candidates)
        {
            if (!TryReadOwner(Path.GetFileName(folder), prefix, out int pid, out long start)) continue;
            if (ownerIsAlive(pid, start)) continue;
            DateTime made;
            try { made = Directory.GetCreationTimeUtc(folder); } catch { continue; }
            if (DateTime.UtcNow - made < SafeAge) continue;
            try
            {
                beforeDeletingOrphan?.Invoke(folder);
                Directory.Delete(folder, recursive: true);
                swept.Add(folder);
            }
            catch { }
        }
        return swept;
    }

    /// <summary>Reads <c>&lt;prefix&gt;&lt;pid&gt;-&lt;ticks&gt;-…</c>; anything else is not ours and is never swept.</summary>
    internal static bool TryReadOwner(string name, string prefix, out int processId, out long startTicks)
    {
        processId = 0;
        startTicks = 0;
        if (!name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return false;
        string[] parts = name[prefix.Length..].Split('-');
        return parts.Length >= 3
            && int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out processId)
            && long.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out startTicks);
    }

    internal static bool OwnerIsAlive(int processId, long startTicks)
    {
        Process process;
        try { process = Process.GetProcessById(processId); }
        catch (ArgumentException) { return false; }          // no process with that id
        using (process)
        {
            try { return StartTicks(process) == startTicks; }   // same id, different start: recycled
            catch (InvalidOperationException) { return false; } // exited while we looked
            catch { return true; }                              // cannot tell: leave it alone
        }
    }

    private static long StartTicks(Process process) => process.StartTime.ToUniversalTime().Ticks;
}
