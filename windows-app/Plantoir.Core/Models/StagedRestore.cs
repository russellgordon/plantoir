using System.IO.Compression;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Models;

/// <summary>
/// The staged swap every restore from a zip goes through (#873): the zip is
/// unpacked BESIDE the course, in a hidden folder of <c>courses\</c>, checked,
/// and only then swapped in, with the old contents set ASIDE until the swap
/// has succeeded. Any failure puts the old contents back, so a course is never
/// left emptied or half restored.
///
/// <para><b>Why beside the course, never %TEMP%.</b> <c>Directory.Move</c>
/// cannot cross volumes. The old restore unpacked into %TEMP% (on C:), deleted
/// the course's contents and THEN moved the backup's folders in, so a working
/// folder on D:, a USB drive or a share lost every subfolder; and on any disk a
/// move that failed part way (a file held open) left the course partly
/// emptied. A sibling of the course is on the course's own volume, so every
/// move below is a rename, which either happens whole or not at all.</para>
///
/// <para><b>The folder, and what the next launch does with it.</b>
/// <c>courses\.plantoir-restoring-&lt;FOLDER&gt;-&lt;pid&gt;-&lt;8 hex&gt;</c>: a dot
/// name, so <c>Workspace.DiscoverCourses</c>, the builds and Obsidian's file
/// list never take it for a course, and a prefix nothing else uses
/// (<see cref="ReferenceStaging.Prefix"/> is <c>.plantoir-importing-</c>).
/// Inside it: <c>owner</c> (the process, as a lease body says it),
/// <c>journal</c> (which step it reached), <c>incoming\</c> (the unpacked zip)
/// and <c>aside\</c> (the course's own contents while the swap runs).
/// <see cref="RecoverLeftovers"/> runs before the courses are listed and acts
/// only on a folder whose owner is no longer alive: before the swap, or during
/// it, it puts the old contents back and removes the folder; after the swap it
/// finishes it (removes the old contents, discards the stale build). A folder it
/// cannot make sense of is left where it is: litter, never loss.</para>
///
/// <para><b>The order of the swap</b>: every child of the live folder is
/// renamed into <c>aside\</c>, then every child of the backup into the live
/// folder. The FOLDER itself never moves, because it is Obsidian's vault and
/// its watcher is anchored to it (the reason the old restore replaced contents
/// rather than the folder, kept). Hidden children are included both ways.</para>
/// </summary>
public static class StagedRestore
{
    public const string Prefix = ".plantoir-restoring-";

    internal const string JournalName = "journal";
    internal const string OwnerName = "owner";
    internal const string IncomingName = "incoming";
    internal const string AsideName = "aside";
    internal const string DisplacedName = "displaced";

    /// <summary>The steps a staged restore records, in order.</summary>
    internal static class Phase
    {
        /// <summary>The zip is being unpacked and checked; nothing of the course has moved.</summary>
        public const string Unpacking = "unpacking";
        /// <summary>A course that was not there is being renamed into place.</summary>
        public const string Placing = "placing";
        /// <summary>The live contents are being set aside.</summary>
        public const string Aside = "aside";
        /// <summary>Every live child is aside; the backup's are moving in.</summary>
        public const string In = "in";
        /// <summary>The swap is complete; what is aside is the superseded course.</summary>
        public const string Done = "done";
    }

    /// <summary>
    /// What a restore does to the disk, as a seam: every move goes through
    /// <see cref="Move"/>, and <see cref="AfterStep"/> is told after each one.
    /// A test subclasses it to fail a move part way or to stop dead where a
    /// kill would (<see cref="StopHereForATest"/>).
    /// </summary>
    internal class Steps
    {
        public static readonly Steps Real = new();

        /// <summary>A rename, or across volumes a copy that undoes itself when it cannot finish.</summary>
        public virtual void Move(string source, string target) => MoveEntry(source, target);

        public virtual void AfterStep(string phase, int movesSoFar) { }

        public virtual void Unpack(string archivePath, string into) => ZipFile.ExtractToDirectory(archivePath, into);
    }

    /// <summary>Thrown only by a test's <see cref="Steps"/>: leaves the disk exactly as a kill would.</summary>
    internal sealed class StopHereForATest() : Exception("stopped where a kill would");

    /// <summary>One restore's hidden folder, made beside the course.</summary>
    internal sealed class Staging
    {
        public string CoursesDirectory { get; }
        public string Path { get; }
        public string Incoming => System.IO.Path.Combine(Path, IncomingName);
        public string Aside => System.IO.Path.Combine(Path, AsideName);

        private Staging(string coursesDirectory, string path)
        {
            CoursesDirectory = coursesDirectory;
            Path = path;
        }

        /// <summary>A leftover folder found by the next launch.</summary>
        public static Staging Reopen(string coursesDirectory, string path) => new(coursesDirectory, path);

        public static Staging Make(string coursesDirectory, string folderName)
        {
            Directory.CreateDirectory(coursesDirectory);
            string name = $"{Prefix}{folderName}-{Environment.ProcessId}-{Guid.NewGuid().ToString("N")[..8]}";
            string path = System.IO.Path.Combine(coursesDirectory, name);
            Directory.CreateDirectory(path);
            var staging = new Staging(coursesDirectory, path);
            WriteDurably(System.IO.Path.Combine(path, OwnerName), WorkLease.LeaseBody(withStart: true));
            staging.Record(Phase.Unpacking, live: null);
            Directory.CreateDirectory(staging.Incoming);
            return staging;
        }

        /// <summary>Writes the journal whole (to a temporary file, flushed, then renamed over), so a power cut leaves the old step or the new, never half of one.</summary>
        public void Record(string phase, string? live, IEnumerable<string>? incomingNames = null)
        {
            var lines = new List<string> { "phase " + phase };
            if (live is not null) lines.Add("live " + System.IO.Path.GetRelativePath(CoursesDirectory, live));
            if (incomingNames is not null)
                foreach (string name in incomingNames) lines.Add("in " + name);
            string journal = System.IO.Path.Combine(Path, JournalName);
            string temporary = journal + ".tmp";
            WriteDurably(temporary, string.Join("\n", lines) + "\n");
            File.Move(temporary, journal, overwrite: true);
        }

        /// <summary>Removes the folder; false when some of it would not go (left for the next launch).</summary>
        public bool TryRemove()
        {
            try { CourseRestorer.DeleteTree(Path); }
            catch { }
            return !Directory.Exists(Path);
        }
    }

    // ---- Unpacking and checking ------------------------------------------

    /// <summary>
    /// Unpacks the zip into <c>incoming\</c> and checks every file arrived at
    /// its full length, then returns the payload: the folder the archive's name
    /// promised, or the single folder it holds (an archive made by another
    /// version). Every failure says "The archive could not be opened", the
    /// restore's existing sentence. <c>ZipFile.ExtractToDirectory</c> is what
    /// refuses an entry that would land outside the folder (<c>..\</c>, a
    /// rooted name), and it writes a link entry as an ordinary file: both
    /// measured, <c>StagedRestoreTests</c>.
    /// </summary>
    internal static string Unpack(Staging staging, string archivePath, string expectedName, Steps steps)
    {
        try
        {
            steps.Unpack(archivePath, staging.Incoming);
            CheckUnpacked(archivePath, staging.Incoming);
        }
        catch (Exception error) when (error is not StopHereForATest)
        {
            throw new CourseRestorer.RestoreException($"The archive could not be opened: {error.Message}");
        }

        string payload = System.IO.Path.Combine(staging.Incoming, expectedName);
        if (!Directory.Exists(payload))
        {
            var entries = Directory.EnumerateFileSystemEntries(staging.Incoming)
                .Where(e => !System.IO.Path.GetFileName(e).StartsWith('.'))
                .ToList();
            if (entries.Count == 1 && Directory.Exists(entries[0])) payload = entries[0];
            else throw new CourseRestorer.RestoreException($"The archive could not be opened: it does not contain {expectedName}");
        }
        return payload;
    }

    /// <summary>
    /// As many files on disk as the zip has file entries, and as many bytes.
    /// Counted rather than looked up by name, because .NET writes an entry
    /// whose name Windows cannot hold (a Mac's <c>?</c> or <c>"</c>) under a
    /// name with <c>_</c> in its place: a lookup refused those backups,
    /// measured (<c>ANameWindowsCannotHoldDoesNotStopTheCheck</c>). The
    /// exception is the one .NET throws for bad data, so no new sentence is
    /// shown.
    /// </summary>
    private static void CheckUnpacked(string archivePath, string unpacked)
    {
        long expectedFiles = 0, expectedBytes = 0;
        using (var zip = ZipFile.OpenRead(archivePath))
            foreach (var entry in zip.Entries)
            {
                if (entry.FullName.EndsWith('/') || entry.FullName.EndsWith('\\')) continue;
                expectedFiles++;
                expectedBytes += entry.Length;
            }
        long files = 0, bytes = 0;
        foreach (var file in new DirectoryInfo(unpacked).EnumerateFiles("*", new EnumerationOptions
                 { RecurseSubdirectories = true, AttributesToSkip = 0, IgnoreInaccessible = false }))
        {
            files++;
            bytes += file.Length;
        }
        if (files != expectedFiles || bytes != expectedBytes) throw new InvalidDataException();
    }

    // ---- Putting a folder that was not there into place --------------------

    /// <summary>
    /// The restore of a course or section that is not there: unpacked and
    /// checked beside it, then renamed into place in one step.
    /// </summary>
    internal static void Place(string archivePath, string expectedName, string destinationParent, string coursesDirectory, Steps steps)
    {
        var staging = Staging.Make(coursesDirectory, expectedName);
        try
        {
            string payload = Unpack(staging, archivePath, expectedName, steps);
            Directory.CreateDirectory(destinationParent);
            string destination = System.IO.Path.Combine(destinationParent, expectedName);
            staging.Record(Phase.Placing, destination);
            steps.Move(payload, destination);
            steps.AfterStep(Phase.Placing, 1);
        }
        catch (StopHereForATest) { throw; }
        catch
        {
            staging.TryRemove();
            throw;
        }
        staging.TryRemove();
    }

    // ---- The swap ------------------------------------------------------------

    /// <summary>
    /// Replaces the CONTENTS of <paramref name="live"/> with those of
    /// <paramref name="payload"/>, setting the old ones aside in
    /// <paramref name="staging"/>. On any failure the old contents are put back
    /// and the error is rethrown; the staging folder is then removed, or left
    /// for <see cref="RecoverLeftovers"/> when the putting back could not finish.
    /// On success the journal says <see cref="Phase.Done"/>; the caller removes
    /// the staging folder when its own steps are done.
    /// </summary>
    internal static void Swap(Staging staging, string live, string payload, Steps steps)
    {
        Directory.CreateDirectory(live);
        Directory.CreateDirectory(staging.Aside);
        var movedAside = new List<string>();
        var movedIn = new List<string>();
        int moves = 0;
        try
        {
            staging.Record(Phase.Aside, live);
            foreach (string child in Directory.EnumerateFileSystemEntries(live).ToList())
            {
                string name = System.IO.Path.GetFileName(child);
                steps.Move(child, System.IO.Path.Combine(staging.Aside, name));
                movedAside.Add(name);
                steps.AfterStep(Phase.Aside, ++moves);
            }

            var incoming = Directory.EnumerateFileSystemEntries(payload).Select(System.IO.Path.GetFileName).OfType<string>().ToList();
            staging.Record(Phase.In, live, incoming);
            foreach (string name in incoming)
            {
                steps.Move(System.IO.Path.Combine(payload, name), System.IO.Path.Combine(live, name));
                movedIn.Add(name);
                steps.AfterStep(Phase.In, ++moves);
            }
            staging.Record(Phase.Done, live, incoming);
            steps.AfterStep(Phase.Done, moves);
        }
        catch (StopHereForATest) { throw; }
        catch
        {
            bool whole = PutBack(staging, live, payload, movedIn, steps);
            if (whole) staging.TryRemove();
            throw;
        }
    }

    /// <summary>
    /// The old contents back where they were: what moved in goes out (back to
    /// the payload, or deleted, since the zip still holds it), then everything
    /// aside comes back. Something in the live folder that is neither (another
    /// program wrote it while the folder stood empty) is moved into
    /// <c>displaced\</c> rather than deleted, and the staging folder is kept.
    /// True when the course is exactly as it was and nothing is left to keep.
    /// </summary>
    private static bool PutBack(Staging staging, string live, string? payload, IReadOnlyCollection<string> movedIn, Steps steps)
    {
        bool whole = true;
        foreach (string name in movedIn)
        {
            string there = System.IO.Path.Combine(live, name);
            if (!Exists(there)) continue;
            try
            {
                if (payload is not null && Directory.Exists(payload) && !Exists(System.IO.Path.Combine(payload, name)))
                    steps.Move(there, System.IO.Path.Combine(payload, name));
                else CourseRestorer.DeleteTree(there);
            }
            catch
            {
                try { CourseRestorer.DeleteTree(there); }
                catch { whole = false; }
            }
        }

        if (!Directory.Exists(staging.Aside)) return whole;
        foreach (string child in Directory.EnumerateFileSystemEntries(staging.Aside).ToList())
        {
            string name = System.IO.Path.GetFileName(child);
            string there = System.IO.Path.Combine(live, name);
            try
            {
                if (Exists(there))
                {
                    string displaced = System.IO.Path.Combine(staging.Path, DisplacedName);
                    Directory.CreateDirectory(displaced);
                    MoveEntry(there, System.IO.Path.Combine(displaced, name));
                    whole = false;
                }
                MoveEntry(child, there);
            }
            catch { whole = false; }
        }
        return whole;
    }

    // ---- What the next launch does with a leftover ----------------------

    /// <summary>What the sweep did with one leftover folder.</summary>
    public enum Recovery { PutBack, Finished, Removed, LeftInPlace }

    /// <summary>
    /// Every <c>.plantoir-restoring-*</c> folder of <paramref name="coursesDirectory"/>
    /// whose owner is no longer running, dealt with by the step its journal
    /// reached. Runs before the courses are listed. A folder whose owner is
    /// alive (another window, <c>plantoir-mcp</c>, a restore still running) is
    /// never touched. Costs one listing of <c>courses\</c> when there is none.
    /// </summary>
    /// <param name="ownerIsAlive">The liveness question, given the owner file's text; the default asks this machine (<see cref="WorkLease.OwnerIsAlive"/>).</param>
    public static List<(string Folder, Recovery What)> RecoverLeftovers(string coursesDirectory, Func<string, bool>? ownerIsAlive = null)
    {
        var done = new List<(string, Recovery)>();
        List<string> leftovers;
        try
        {
            leftovers = new DirectoryInfo(coursesDirectory).EnumerateDirectories(Prefix + "*", ReferenceLock.Unfiltered)
                .Where(d => d.Name.StartsWith(Prefix, StringComparison.Ordinal))
                .Select(d => d.FullName).ToList();
        }
        catch { return done; }

        foreach (string folder in leftovers)
        {
            try
            {
                if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0) continue;   // never ours
                string ownerText;
                try { ownerText = File.ReadAllText(System.IO.Path.Combine(folder, OwnerName)); }
                catch { ownerText = ""; }
                if ((ownerIsAlive ?? OwnerIsAlive)(ownerText)) continue;
                done.Add((folder, RecoverOne(coursesDirectory, folder)));
            }
            catch { done.Add((folder, Recovery.LeftInPlace)); }
        }
        return done;
    }

    private static bool OwnerIsAlive(string ownerText)
    {
        string first = ownerText.Split('\n')[0].Trim();
        if (!int.TryParse(first, out int pid)) return false;
        var (name, start) = WorkLease.ReadBody(ownerText);
        return WorkLease.OwnerIsAlive(pid, name, start, "restore");
    }

    private static Recovery RecoverOne(string coursesDirectory, string folder)
    {
        var (phase, liveRelative, incoming) = ReadJournal(folder);
        string aside = System.IO.Path.Combine(folder, AsideName);
        bool asideHoldsAnything = Directory.Exists(aside) && Directory.EnumerateFileSystemEntries(aside).Any();

        // Nothing of the course ever moved: the folder is only an unpacked zip.
        if (!asideHoldsAnything && phase is null or Phase.Unpacking or Phase.Placing or Phase.Aside)
        {
            if (phase == Phase.Placing && liveRelative is not null)
                DiscardBuiltSitesOf(coursesDirectory, liveRelative);
            return Remove(folder) ? Recovery.Removed : Recovery.LeftInPlace;
        }
        if (phase is null || liveRelative is null) return Recovery.LeftInPlace;   // aside holds something and we cannot tell where it goes

        string live = System.IO.Path.GetFullPath(System.IO.Path.Combine(coursesDirectory, liveRelative));
        if (!IsInside(coursesDirectory, live)) return Recovery.LeftInPlace;
        var staging = Staging.Reopen(coursesDirectory, folder);

        if (phase == Phase.Done)
        {
            // The swap had finished; only the removal of the old contents had not.
            DiscardBuiltSitesOf(coursesDirectory, liveRelative);
            return Remove(folder) ? Recovery.Finished : Recovery.LeftInPlace;
        }

        // Part way: the old contents go back. In the "in" step every live
        // child had been set aside first, so a name the journal lists as
        // incoming that is in the live folder came from the zip.
        Directory.CreateDirectory(live);
        string course = FirstSegment(liveRelative);
        string courseDirectory = System.IO.Path.Combine(coursesDirectory, course);
        ReferenceLock.Unlock(live);
        bool whole = PutBack(staging, live, payload: null, phase == Phase.In ? incoming : Array.Empty<string>(), Steps.Real);
        if (ReadsAsKeptForReference(courseDirectory)) ReferenceLock.Lock(courseDirectory);
        if (!whole) return Recovery.LeftInPlace;
        return Remove(folder) ? Recovery.PutBack : Recovery.LeftInPlace;
    }

    private static (string? Phase, string? Live, List<string> Incoming) ReadJournal(string folder)
    {
        string? phase = null, live = null;
        var incoming = new List<string>();
        string[] lines;
        try { lines = File.ReadAllLines(System.IO.Path.Combine(folder, JournalName)); }
        catch { return (null, null, incoming); }
        foreach (string line in lines)
        {
            if (line.StartsWith("phase ", StringComparison.Ordinal)) phase = line[6..];
            else if (line.StartsWith("live ", StringComparison.Ordinal)) live = line[5..];
            else if (line.StartsWith("in ", StringComparison.Ordinal)) incoming.Add(line[3..]);
        }
        return (phase, live, incoming);
    }

    private static bool Remove(string folder)
    {
        try { ReferenceLock.Unlock(folder); } catch { }
        try { CourseRestorer.DeleteTree(folder); } catch { }
        return !Directory.Exists(folder);
    }

    private static void DiscardBuiltSitesOf(string coursesDirectory, string liveRelative)
    {
        string course = FirstSegment(liveRelative);
        string[] parts = liveRelative.Split(System.IO.Path.DirectorySeparatorChar, System.IO.Path.AltDirectorySeparatorChar);
        if (parts.Length == 2 && CourseRestorer.NamesASectionFolder(parts[1]) && int.TryParse(parts[1]["section".Length..], out int section))
            CourseArchiver.DiscardBuilds(coursesDirectory, course, section);
        else
            CourseArchiver.DiscardBuiltSites(coursesDirectory, course);
    }

    private static string FirstSegment(string relative) =>
        relative.Split(System.IO.Path.DirectorySeparatorChar, System.IO.Path.AltDirectorySeparatorChar)[0];

    private static bool ReadsAsKeptForReference(string courseDirectory)
    {
        try { return ReferenceCourse.KeptOnDisk(courseDirectory) is not null; }
        catch { return false; }
    }

    private static bool IsInside(string parent, string path)
    {
        string root = System.IO.Path.GetFullPath(parent).TrimEnd('\\', '/') + System.IO.Path.DirectorySeparatorChar;
        return path.StartsWith(root, StringComparison.OrdinalIgnoreCase);
    }

    // ---- Moving one entry ------------------------------------------------

    private static bool Exists(string path) => File.Exists(path) || Directory.Exists(path);

    /// <summary>ERROR_NOT_SAME_DEVICE: a rename asked to cross volumes.</summary>
    internal const int NotSameDevice = unchecked((int)0x80070011);

    /// <summary>
    /// A rename. A link (junction or symbolic) is renamed AS A LINK and never
    /// followed. Across volumes, which only a course folder that is itself a
    /// link to another disk can still ask for, the entry is copied and the
    /// source removed; a copy that cannot finish removes what it wrote, and a
    /// source that will not go entirely is copied back whole, so the move
    /// either happened or did not.
    /// </summary>
    internal static void MoveEntry(string source, string target)
    {
        var attributes = File.GetAttributes(source);
        bool isDirectory = (attributes & FileAttributes.Directory) != 0;
        try
        {
            if (isDirectory) Directory.Move(source, target);
            else File.Move(source, target);
        }
        catch (IOException error) when (error.HResult == NotSameDevice && (attributes & FileAttributes.ReparsePoint) == 0)
        {
            try
            {
                if (isDirectory) CopyTree(source, target);
                else File.Copy(source, target);
            }
            catch
            {
                try { if (Exists(target)) CourseRestorer.DeleteTree(target); } catch { }
                throw;
            }
            try { CourseRestorer.DeleteTree(source); }
            catch
            {
                // Part of the source went: put it back from the whole copy.
                if (isDirectory) CopyTree(target, source, overwrite: true);
                try { CourseRestorer.DeleteTree(target); } catch { }
                throw;
            }
        }
    }

    private static void CopyTree(string source, string target, bool overwrite = false)
    {
        Directory.CreateDirectory(target);
        foreach (var entry in new DirectoryInfo(source).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered))
        {
            string to = System.IO.Path.Combine(target, entry.Name);
            // A link is never followed, and never silently dropped either: the
            // copy refuses, and the restore puts everything back.
            if ((entry.Attributes & FileAttributes.ReparsePoint) != 0)
                throw System.Runtime.InteropServices.Marshal.GetExceptionForHR(NotSameDevice)!;   // the system's own sentence
            if ((entry.Attributes & FileAttributes.Directory) != 0) CopyTree(entry.FullName, to, overwrite);
            else if (overwrite || !File.Exists(to)) File.Copy(entry.FullName, to, overwrite);
        }
    }

    /// <summary>Writes a small file and flushes it to the disk before returning (FlushFileBuffers).</summary>
    internal static void WriteDurably(string path, string text)
    {
        using var stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None);
        byte[] bytes = System.Text.Encoding.UTF8.GetBytes(text);
        stream.Write(bytes, 0, bytes.Length);
        stream.Flush(flushToDisk: true);
    }
}
