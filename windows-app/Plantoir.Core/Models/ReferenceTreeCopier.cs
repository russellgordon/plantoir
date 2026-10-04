using System.Diagnostics;
using System.Text;

namespace Plantoir.Core.Models;

/// <summary>
/// Copies a course tree into a staging folder for Keep a Copy and the import
/// (#241/#244; <c>documentation/09-mac-app.md</c> → "Importing last year's
/// folder", the Windows section).
///
/// <para><b>Skip by not DESCENDING.</b> A name on the left-behind list, and an
/// Obsidian add-on PATH, is skipped before it is so much as listed: an old
/// working folder's <c>.merged_output</c> is a real directory of last year's
/// whole built website (1.9 GB per course on the mac's measured folder,
/// against 489 MB of course), and walking it to not copy it costs more than
/// the copy. The walk is our own, one folder at a time, with hidden and system
/// entries INCLUDED (.NET's default <c>AttributesToSkip</c> drops them, which
/// would drop <c>.obsidian</c> — the #136 trap).</para>
///
/// <para><b>Links.</b> Windows leaves EVERY reparse point behind — never
/// followed, never copied. The mac copies a symlink as a link; here making one
/// needs a privilege a teacher does not have (WinError 1314) and a junction
/// cannot be copied faithfully. The only link in a modern course is
/// <c>.merged_output</c>, which is left behind by name anyway. Proposed to the
/// contract as an <c>appliesOn</c> on that clause (bundle 6b's mac issue).</para>
///
/// <para><b>Never writes to the source.</b> Every source file is opened for
/// READING only (sharing read, write and delete, so a teacher's open file is
/// not disturbed); attributes and times are only read. No <c>File.Copy</c>
/// from the source: it would carry the read-only attribute and alternate
/// streams, and a 1 MB stream copy gives progress and Stop. Measured 431 MB/s
/// against File.Copy's 670 MB/s on this PC's NVMe (the planner's probe) — a
/// price paid for both, and on a USB disk the disk dominates anyway.
/// CopyFileEx (P/Invoke, with a progress callback) was REJECTED for the same
/// reason as File.Copy: it carries the read-only bit and Zone.Identifier.</para>
/// </summary>
public static class ReferenceTreeCopier
{
    /// <summary>One thing that will be copied, relative to the root ('\'-separated, as the disk spells it).</summary>
    public sealed record Entry(string Relative, bool IsFolder, long Size, DateTime LastWriteUtc);

    /// <summary>What the walk found: everything to copy, its size, and what could not be read.</summary>
    public sealed record Survey(IReadOnlyList<Entry> Entries, long Bytes, int Files, IReadOnlyList<string> UnreadableFolders);

    /// <summary>How far a copy has got, in BYTES — one 110 MB video would freeze a bar counted in files.</summary>
    public readonly record struct Progress(long Copied, long Total);

    /// <summary>The chunk a copy moves between checks for Stop: about 2 ms on NVMe.</summary>
    public const int ChunkBytes = 1 << 20;

    /// <summary>
    /// Walks <paramref name="root"/>, leaving behind every entry whose NAME is in
    /// <paramref name="leftBehindNames"/> (at any depth) or whose PATH relative to
    /// the root ('/'-separated, compared after NFC) is in
    /// <paramref name="leftBehindPaths"/>, and every link. Nothing left behind is
    /// listed. <paramref name="listing"/> is told every folder that IS listed —
    /// which is how a test proves nothing under a left-behind folder was walked.
    /// </summary>
    public static Survey Walk(string root, IReadOnlySet<string> leftBehindNames, IReadOnlySet<string> leftBehindPaths,
        Action<string>? listing = null)
    {
        var entries = new List<Entry>();
        var unreadable = new List<string>();
        long bytes = 0;
        int files = 0;
        var pending = new Stack<(string Absolute, string Relative)>();
        pending.Push((root, ""));
        while (pending.Count > 0)
        {
            var (folder, relative) = pending.Pop();
            listing?.Invoke(folder);
            List<FileSystemInfo> children;
            try { children = new DirectoryInfo(folder).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered).ToList(); }
            catch
            {
                unreadable.Add(relative.Length == 0 ? Path.GetFileName(root) : relative);
                continue;
            }
            foreach (var child in children.OrderBy(c => c.Name, StringComparer.Ordinal))
            {
                string childRelative = relative.Length == 0 ? child.Name : relative + Path.DirectorySeparatorChar + child.Name;
                string compared = childRelative.Replace(Path.DirectorySeparatorChar, '/').Normalize(NormalizationForm.FormC);
                if (leftBehindNames.Contains(child.Name)) continue;
                if (leftBehindPaths.Contains(compared)) continue;
                if (child.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                if (child is DirectoryInfo)
                {
                    entries.Add(new Entry(childRelative, true, 0, child.LastWriteTimeUtc));
                    pending.Push((child.FullName, childRelative));
                }
                else if (child is FileInfo file)
                {
                    entries.Add(new Entry(childRelative, false, file.Length, file.LastWriteTimeUtc));
                    bytes += file.Length;
                    files++;
                }
            }
        }
        return new Survey(entries, bytes, files, unreadable);
    }

    /// <summary>
    /// Copies what <paramref name="survey"/> found from <paramref name="source"/>
    /// into <paramref name="destination"/> (which exists), by stream, in 1 MB
    /// chunks, checking <paramref name="stop"/> between chunks and telling
    /// <paramref name="progress"/> at most every 100 ms and at the end. Every file
    /// is created with <c>FileMode.CreateNew</c>, so nothing already there is
    /// written over; the copy's last-write time is the source's, because the
    /// school year proposed is read from page times.
    /// </summary>
    public static void Copy(Survey survey, string source, string destination, IProgress<Progress>? progress,
        CancellationToken stop, long alreadyCopied = 0, long total = -1)
    {
        if (total < 0) total = survey.Bytes;
        long copied = alreadyCopied;
        var clock = Stopwatch.StartNew();
        long lastTold = -1;
        void Tell(bool force)
        {
            if (progress is null) return;
            if (!force && clock.ElapsedMilliseconds - lastTold < 100) return;
            lastTold = clock.ElapsedMilliseconds;
            progress.Report(new Progress(copied, total));
        }

        byte[] buffer = new byte[ChunkBytes];
        foreach (var entry in survey.Entries.Where(e => e.IsFolder))
            Directory.CreateDirectory(Path.Combine(destination, entry.Relative));
        foreach (var entry in survey.Entries.Where(e => !e.IsFolder))
        {
            stop.ThrowIfCancellationRequested();
            string from = Path.Combine(source, entry.Relative);
            string to = Path.Combine(destination, entry.Relative);
            using (var reading = new FileStream(from, FileMode.Open, FileAccess.Read,
                       FileShare.ReadWrite | FileShare.Delete, 4096, FileOptions.SequentialScan))
            using (var writing = new FileStream(to, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096))
            {
                int read;
                while ((read = reading.Read(buffer, 0, buffer.Length)) > 0)
                {
                    stop.ThrowIfCancellationRequested();
                    writing.Write(buffer, 0, read);
                    copied += read;
                    Tell(force: false);
                }
            }
            try { File.SetLastWriteTimeUtc(to, entry.LastWriteUtc); } catch { }
        }
        Tell(force: true);
    }
}
