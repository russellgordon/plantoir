using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Models;

/// <summary>
/// Deletes several backups at once (#283 / mac #242,
/// <c>course-management.json → backups.deleteCases</c>).
///
/// <para><b>Never the backup an open assistant conversation can restore
/// from</b> (<c>backups.neverDeletedWhileAConversationCanRestoreFromIt</c>):
/// that one is KEPT, the rest asked for still go, and the caller says which
/// assistant window to close. One refusal, or one file that will not delete,
/// is not a reason to stop.</para>
/// </summary>
public static class BackupDeleter
{
    public sealed record Failure(BackupItem Item, string Problem);

    public sealed record Outcome(
        IReadOnlyList<BackupItem> Deleted, IReadOnlyList<BackupItem> Kept, IReadOnlyList<Failure> Failed);

    public static Outcome Delete(IEnumerable<BackupItem> asked, IReadOnlySet<string> held,
                                 Action<BackupItem>? deleteOne = null)
    {
        deleteOne ??= CourseRestorer.DeleteBackup;
        var deleted = new List<BackupItem>();
        var kept = new List<BackupItem>();
        var failed = new List<Failure>();
        foreach (var item in asked)
        {
            if (held.Contains(Path.GetFullPath(item.FilePath))) { kept.Add(item); continue; }
            try
            {
                deleteOne(item);
                deleted.Add(item);
            }
            catch (Exception error)
            {
                failed.Add(new Failure(item, error.Message));
            }
        }
        return new Outcome(deleted, kept, failed);
    }

    /// <summary>
    /// The trail line for <c>backups deleted</c>: course codes, how many, what
    /// they took together when every size is known, each deleted file's NAME
    /// (a course code, a moment and who made it — never anything on a page),
    /// and what was kept for the assistant or could not be deleted.
    /// </summary>
    public static string TrailLine(Outcome outcome, IReadOnlyDictionary<string, long?> sizes)
    {
        var codes = outcome.Deleted.Concat(outcome.Kept).Concat(outcome.Failed.Select(f => f.Item))
            .Select(b => b.CourseCode).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(c => c, StringComparer.Ordinal);
        var deletedSizes = outcome.Deleted.Select(b => sizes.TryGetValue(b.FilePath, out var s) ? s : null).ToList();
        string together = deletedSizes.Count > 0 && deletedSizes.All(s => s is not null)
            ? $", {BackupSizes.Describe(deletedSizes.Sum(s => s!.Value))} together"
            : "";
        string line = $"deleted {outcome.Deleted.Count} backup{(outcome.Deleted.Count == 1 ? "" : "s")} of {string.Join(", ", codes)}{together}";
        if (outcome.Deleted.Count > 0)
            line += ": " + string.Join(", ", outcome.Deleted.Select(b => Path.GetFileName(b.FilePath)));
        if (outcome.Kept.Count > 0)
            line += "; kept because an open assistant conversation can restore from it: " +
                    string.Join(", ", outcome.Kept.Select(b => Path.GetFileName(b.FilePath)));
        if (outcome.Failed.Count > 0)
            line += $"; {outcome.Failed.Count} could not be deleted: " +
                    string.Join(", ", outcome.Failed.Select(f => Path.GetFileName(f.Item.FilePath)));
        return line;
    }
}

/// <summary>
/// The backups an assistant conversation can still restore from, so a delete
/// leaves them alone (#283).
///
/// <para><b>In this app</b>: each open assistant window holds the backup its
/// conversation made before its first change, from the moment that backup
/// exists until the window closes. Only that one — an OLDER assistant backup
/// of the same section is an ordinary backup now (deleteCases[2]).</para>
///
/// <para><b>In another program</b> (bundle-8 ruling 4): a Claude Code session
/// through <c>plantoir-mcp</c> holds a live <c>assist</c> lease on its course.
/// Which zip its conversation made is not written anywhere on disk, so while
/// such a lease is alive the NEWEST assistant-made backup of that course is
/// held — the one that session most plausibly made. That can hold one backup
/// too many; it can never let the one it made go.</para>
/// </summary>
public static class HeldBackups
{
    private static readonly HashSet<string> s_held = new(StringComparer.OrdinalIgnoreCase);
    private static readonly object s_gate = new();

    private sealed class Hold : IDisposable
    {
        private string? _path;
        public Hold(string path) => _path = path;
        public void Dispose()
        {
            lock (s_gate) { if (_path is not null) s_held.Remove(_path); _path = null; }
        }
    }

    /// <summary>Held until the returned object is disposed (the window closes).</summary>
    public static IDisposable HoldWhileOpen(string backupPath)
    {
        string full = Path.GetFullPath(backupPath);
        lock (s_gate) s_held.Add(full);
        return new Hold(full);
    }

    /// <summary>The backups held by assistant windows in this app.</summary>
    public static IReadOnlySet<string> InThisApp()
    {
        lock (s_gate) return new HashSet<string>(s_held, StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>For tests: forget every hold.</summary>
    internal static void Reset() { lock (s_gate) s_held.Clear(); }

    /// <summary>
    /// Everything a delete in <paramref name="workspacePath"/> must keep: this
    /// app's open conversations, plus the newest assistant backup of each
    /// course another live program is assisting with.
    /// </summary>
    public static IReadOnlySet<string> For(string workspacePath, IEnumerable<BackupItem> backups,
                                           Func<string, IEnumerable<string>>? coursesAssistedElsewhere = null)
    {
        var held = new HashSet<string>(InThisApp(), StringComparer.OrdinalIgnoreCase);
        var assisted = new HashSet<string>(
            (coursesAssistedElsewhere ?? WorkLease.CoursesAssistedByAnotherProgram)(workspacePath),
            StringComparer.OrdinalIgnoreCase);
        foreach (var newest in backups
                     .Where(b => b.Maker is BackupMaker.Assistant && assisted.Contains(b.CourseCode))
                     .GroupBy(b => b.CourseCode, StringComparer.OrdinalIgnoreCase)
                     .Select(g => g.OrderByDescending(b => b.BackedUpAt).First()))
            held.Add(Path.GetFullPath(newest.FilePath));
        return held;
    }
}
