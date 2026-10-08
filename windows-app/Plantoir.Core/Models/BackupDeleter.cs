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
    /// and what was kept or could not be deleted. What was kept is told by
    /// SOURCE since #468 (mac #458): the window's clause as it always read,
    /// and, separately, the ones a Claude or Codex session still open made —
    /// <paramref name="madeByOtherSessions"/>, from
    /// <see cref="HeldBackups.ByOtherSessions"/>.
    /// </summary>
    public static string TrailLine(Outcome outcome, IReadOnlyDictionary<string, long?> sizes,
                                   IReadOnlySet<string>? madeByOtherSessions = null)
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
        var bySession = outcome.Kept.Where(b => madeByOtherSessions?.Contains(Path.GetFullPath(b.FilePath)) == true).ToList();
        var byWindow = outcome.Kept.Except(bySession).ToList();
        if (byWindow.Count > 0)
            line += "; kept because an open assistant conversation can restore from it: " +
                    string.Join(", ", byWindow.Select(b => Path.GetFileName(b.FilePath)));
        if (bySession.Count > 0)
            line += "; kept " + string.Join(", ", bySession.Select(b => Path.GetFileName(b.FilePath))) +
                    ", which a Claude or Codex session still open made";
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
/// conversation made, from the moment it exists until the window closes.
/// Holds are COUNTED (bundle-8 ruling 9): two holders of one zip, one closes,
/// the zip is still held. Only that zip — an older assistant backup of the
/// same section is an ordinary backup now (deleteCases[2]).</para>
///
/// <para><b>In another program</b> (rulings 4 and 9): <c>plantoir-mcp</c>
/// writes the zip its conversation made into a record beside its lease,
/// <c>&lt;COURSE&gt;.held-backup.&lt;pid&gt;</c> in the activity folder
/// (<see cref="RecordFor"/>), and removes it at exit. A record counts while that
/// pid holds a live <c>assist</c> lease, so a killed session's leftover record
/// holds nothing. The earlier "newest assistant backup of the course" guess is
/// gone: it released the outside session's own zip whenever this app's
/// assistant had made a later one.</para>
/// </summary>
public static class HeldBackups
{
    private static readonly Dictionary<string, int> s_held = new(StringComparer.OrdinalIgnoreCase);
    private static readonly object s_gate = new();

    private sealed class Hold : IDisposable
    {
        private string? _path;
        public Hold(string path) => _path = path;
        public void Dispose()
        {
            lock (s_gate)
            {
                if (_path is null) return;
                if (s_held.TryGetValue(_path, out int n) && n > 1) s_held[_path] = n - 1;
                else s_held.Remove(_path);
                _path = null;
            }
        }
    }

    /// <summary>Held until the returned object is disposed (the window closes).</summary>
    public static IDisposable HoldWhileOpen(string backupPath)
    {
        string full = Path.GetFullPath(backupPath);
        lock (s_gate) s_held[full] = s_held.TryGetValue(full, out int n) ? n + 1 : 1;
        return new Hold(full);
    }

    /// <summary>The backups held by assistant windows in this app.</summary>
    public static IReadOnlySet<string> InThisApp()
    {
        lock (s_gate) return new HashSet<string>(s_held.Keys, StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>For tests: forget every hold.</summary>
    internal static void Reset() { lock (s_gate) s_held.Clear(); }

    /// <summary>Where a program records the zip its conversation made, beside its lease.</summary>
    public static string RecordFor(string workspacePath, string courseCode, int pid) =>
        Path.Combine(Workspace.CoursesDirectory(workspacePath), ".internal", "activity", $"{courseCode}.held-backup.{pid}");

    /// <summary>Write (or replace) this process's record. Best-effort: a record that cannot be written holds nothing.</summary>
    public static void Record(string workspacePath, string courseCode, string backupPath)
    {
        try
        {
            string record = RecordFor(workspacePath, courseCode, Environment.ProcessId);
            Directory.CreateDirectory(Path.GetDirectoryName(record)!);
            File.WriteAllText(record, Path.GetFullPath(backupPath));
        }
        catch (Exception) { }
    }

    /// <summary>Remove this process's records (at exit).</summary>
    public static void ForgetRecords(string workspacePath)
    {
        try
        {
            string dir = Path.Combine(Workspace.CoursesDirectory(workspacePath), ".internal", "activity");
            foreach (string file in Directory.EnumerateFiles(dir, $"*.held-backup.{Environment.ProcessId}")) File.Delete(file);
        }
        catch (Exception) { }
    }

    /// <summary>
    /// Everything a delete in <paramref name="workspacePath"/> must keep: this
    /// app's open conversations, plus each zip another program's live
    /// assistant session has on record.
    /// </summary>
    public static IReadOnlySet<string> For(string workspacePath, IEnumerable<BackupItem> backups,
                                           Func<string, IEnumerable<int>>? livingAssistantPids = null)
    {
        var held = new HashSet<string>(InThisApp(), StringComparer.OrdinalIgnoreCase);
        var living = (livingAssistantPids ?? AssistantPids)(workspacePath).ToHashSet();
        string dir = Path.Combine(Workspace.CoursesDirectory(workspacePath), ".internal", "activity");
        IEnumerable<string> records;
        try { records = Directory.EnumerateFiles(dir, "*.held-backup.*").ToList(); }
        catch (Exception) { return held; }
        foreach (string record in records)
        {
            if (PidOfRecord(Path.GetFileName(record)) is not { } pid || !living.Contains(pid)) continue;
            try { held.Add(Path.GetFullPath(File.ReadAllText(record).Trim())); } catch (Exception) { }
        }
        return held;
    }

    /// <summary>
    /// The backups a CLAUDE OR CODEX session holds (#468): each zip recorded by
    /// another program with a live assist lease that is NOT one of this app's
    /// own window servers (<see cref="WindowServers"/>). The window's own
    /// server writes records too, for the zip its window already holds; those
    /// keep the window's sentences. The mac's <c>backupsHeldByOtherSessions</c>.
    /// </summary>
    public static IReadOnlySet<string> ByOtherSessions(string workspacePath,
                                                       Func<string, IEnumerable<int>>? livingAssistantPids = null)
    {
        var held = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var living = (livingAssistantPids ?? AssistantPids)(workspacePath)
            .Where(pid => WindowServers.Find(pid) is null).ToHashSet();
        string dir = Path.Combine(Workspace.CoursesDirectory(workspacePath), ".internal", "activity");
        IEnumerable<string> records;
        try { records = Directory.EnumerateFiles(dir, "*.held-backup.*").ToList(); }
        catch (Exception) { return held; }
        foreach (string record in records)
        {
            if (PidOfRecord(Path.GetFileName(record)) is not { } pid || !living.Contains(pid)) continue;
            try { held.Add(Path.GetFullPath(File.ReadAllText(record).Trim())); } catch (Exception) { }
        }
        held.ExceptWith(InThisApp());
        return held;
    }

    /// <summary>
    /// The writer's process id from a record's NAME, or null when the name is
    /// not a record (<c>file-formats.json → heldBackupRecord.name</c>): the pid
    /// is the LAST dot-separated part, in decimal, and <c>held-backup</c> the
    /// second-last — so a course code with a dot in it still reads, and a lease
    /// (<c>ICS3U.assist.4321.lease</c>) never does. The mac's
    /// <c>pidOfHeldBackupRecord(named:)</c>.
    /// </summary>
    public static int? PidOfRecord(string fileName)
    {
        string[] parts = fileName.Split('.');
        if (parts.Length < 3 || parts[^2] != "held-backup") return null;
        string last = parts[^1];
        if (last.Length == 0 || !last.All(char.IsAsciiDigit)) return null;
        return int.TryParse(last, System.Globalization.NumberStyles.None,
                            System.Globalization.CultureInfo.InvariantCulture, out int pid) ? pid : null;
    }

    private static IEnumerable<int> AssistantPids(string workspacePath) =>
        WorkLease.LiveLeasesOfOthers(workspacePath).Where(l => l.Kind == WorkLease.Assisting).Select(l => l.Pid);
}
