using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace Plantoir.Core.Models;

/// <summary>
/// What the Backups list takes, per course and in total (#283 / mac #242,
/// <c>course-management.json → backups.sizeCases</c>).
///
/// <para><b>The LOGICAL size, never what the file occupies on this disk</b>
/// (<c>backups.sizeIsLogical</c>): <see cref="FileInfo.Length"/>, which is the
/// end-of-file, not the allocation. A working folder in OneDrive can have its
/// backups evicted to the cloud, where they take almost nothing here while
/// costing their whole size in the teacher's cloud storage — counted by
/// allocation, that teacher would be told their backups take nothing.</para>
///
/// <para>Backups only. An archive and the setup wizard's own zip share the
/// folder but are not in the Backups list, so a total that counted them would
/// be a number the teacher cannot act on from that list.</para>
///
/// <para>A size that cannot be read is shown as
/// <c>AssistWording.BackupSizeCouldNotBeReadShort</c> and left OUT of the total
/// (<c>backupSizeCouldNotBeRead</c> says so), rather than making the whole
/// total unknown: one unreadable file should not hide what the rest take.</para>
/// </summary>
public static class BackupSizes
{
    public sealed record CourseTotal(string CourseCode, int Count, long Bytes, int Unknown);

    public sealed record Summary(IReadOnlyList<CourseTotal> Courses, int TotalCount, long TotalBytes, int Unknown)
    {
        /// <summary>True when every backup's size was read, so the total is the whole truth.</summary>
        public bool EverySizeKnown => Unknown == 0;
    }

    /// <summary>The file's logical size, or null when it cannot be read.</summary>
    public static long? LogicalSize(string path)
    {
        try { return new FileInfo(path).Length; }
        catch (Exception) { return null; }
    }

    /// <summary>Per course in course-code order, and in total.</summary>
    public static Summary Summarize(IEnumerable<(BackupItem Item, long? Bytes)> measured)
    {
        var list = measured.ToList();
        var courses = list
            .GroupBy(m => m.Item.CourseCode, StringComparer.OrdinalIgnoreCase)
            .OrderBy(g => g.Key, StringComparer.Ordinal)
            .Select(g => new CourseTotal(g.Key, g.Count(), g.Sum(m => m.Bytes ?? 0), g.Count(m => m.Bytes is null)))
            .ToList();
        return new Summary(courses, list.Count, list.Sum(m => m.Bytes ?? 0), list.Count(m => m.Bytes is null));
    }

    /// <summary>Reads every size from disk. Slow on a cloud folder, so callers run it off the UI thread.</summary>
    public static Summary Measure(IEnumerable<BackupItem> backups) =>
        Summarize(backups.Select(b => (b, LogicalSize(b.FilePath))));

    /// <summary>A size as a teacher reads it: "11.3 MB". Decimal units, the way File Explorer's details and the mac's Finder both count a download.</summary>
    public static string Describe(long bytes)
    {
        string[] units = { "bytes", "KB", "MB", "GB", "TB" };
        double value = bytes;
        int unit = 0;
        while (value >= 1000 && unit < units.Length - 1) { value /= 1000; unit++; }
        return unit == 0 ? $"{bytes} bytes" : $"{value:0.0} {units[unit]}";
    }
}

/// <summary>
/// Drops a measurement that finished after a newer one began — the Backups
/// list is re-read on every reload, and sizes are measured off the UI thread,
/// so a slow measurement of the OLD list must not overwrite the new one.
/// </summary>
public sealed class MeasurementGeneration
{
    private int _current;

    /// <summary>Start a measurement; keep the number it returns.</summary>
    public int Begin() => Interlocked.Increment(ref _current);

    /// <summary>Whether the measurement that got <paramref name="generation"/> is still the newest.</summary>
    public bool IsCurrent(int generation) => Volatile.Read(ref _current) == generation;
}
