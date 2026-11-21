using System.Globalization;
using System.IO.Compression;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Brings an archived course or section back. Nothing is ever written over —
/// what is in the way may be newer work, so the restore refuses and explains.
/// </summary>
public static class CourseRestorer
{
    public class RestoreException(string message) : Exception(message);

    /// <summary>
    /// A one-section restore moved a file and then could not move every file
    /// back (#911, the mac's <c>sectionRestoreStoppedPartWay</c>): the message
    /// is the whole sentence, <c>wording.stoppedPartWay</c> or
    /// <c>stoppedPartWayNothingToOpen</c>, so a caller says it as it is and
    /// never puts "Nothing was put back:" in front.
    /// </summary>
    public sealed class SectionRestoreStoppedPartWay(string message) : RestoreException(message);

    public static void Restore(ArchivedItem item, string coursesDirectory, IReadOnlyList<Course> courses)
    {
        if (item.SectionNumber is int section)
        {
            Course? course = courses.FirstOrDefault(c => c.Code == item.CourseCode);
            if (course is null)
                throw new RestoreException(
                    $"{item.CourseCode} is not in Courses & Clubs. Restore the course first, then restore this section into it.");
            if (ReferenceCourse.IsKeptForReference(course))
                throw new RestoreException(ReferenceCourse.StaysAsItIs(ReferenceCourse.ShownCode(course)));
            string sectionDir = course.SectionDirectory(section);
            if (Directory.Exists(sectionDir))
                throw new RestoreException(
                    $"Section {section} of {item.CourseCode} already exists. Remove it first if you want the archived copy back.");
            Extract(item.FilePath, "section" + section, course.DirectoryPath);
            PutSectionBack(course, section);
            // The restored section's notes can be OLDER than a built site left
            // standing outside the working folder, which would read as "already
            // up to date" and publish the site this section used to have.
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode, section);
        }
        else
        {
            string courseDir = Path.Combine(coursesDirectory, item.CourseCode);
            if (Directory.Exists(courseDir))
                throw new RestoreException(
                    $"{item.CourseCode} is already in Courses & Clubs. Remove it first if you want the archived copy back.");
            Extract(item.FilePath, item.CourseCode, coursesDirectory);
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode);
            LockAgainIfKeptForReference(courseDir);
        }
        // A restored thing is no longer archived (failure to delete is not fatal).
        try { File.Delete(item.FilePath); } catch { }
    }

    /// <summary>
    /// Puts a backup's contents back (row 106). The current version was
    /// already archived by the caller — even a restore has an undo — and the
    /// backup zip STAYS: only deleting removes it.
    ///
    /// When the course folder still exists, its CONTENTS are replaced rather
    /// than the folder itself: the folder is Obsidian's vault, and Obsidian's
    /// file watcher is anchored to it — swap the folder and Obsidian shows
    /// stale files until the vault is reopened; swap the contents and it
    /// refreshes on its own. Unpacked and verified BEFORE anything is
    /// touched, so an unreadable zip can never leave an emptied folder.
    /// </summary>
    public static void RestoreBackup(BackupItem item, string coursesDirectory)
    {
        string destination = Path.Combine(coursesDirectory, item.CourseCode);
        if (!Directory.Exists(destination))
        {
            Extract(item.FilePath, item.CourseCode, coursesDirectory);
            // The built sites go and the kept copies of geogebra.org sketches
            // stay (#805, the mac's discardBuiltSites): a copy is named by its
            // fence, so it is right for the pages that come back.
            CourseArchiver.DiscardBuiltSites(coursesDirectory, item.CourseCode);
            LockAgainIfKeptForReference(destination);
            return;
        }

        string staging = Path.Combine(Path.GetTempPath(), "restore-" + Guid.NewGuid());
        Directory.CreateDirectory(staging);
        try
        {
            string payload = Unpack(item.FilePath, item.CourseCode, staging);

            // A reference course is locked (#241): unlock what is about to be
            // written over, and lock again below — asked of the settings AFTER
            // the restore, so a backup made before the course was kept for
            // reference restores a course that is not one.
            ReferenceLock.Unlock(destination);

            // Out with the current contents (hidden files included — the
            // backup carries its own .obsidian), in with the backup's.
            foreach (string child in Directory.EnumerateFileSystemEntries(destination))
                DeleteTree(child);
            foreach (string child in Directory.EnumerateFileSystemEntries(payload))
            {
                string target = Path.Combine(destination, Path.GetFileName(child));
                if (Directory.Exists(child)) Directory.Move(child, target);
                else File.Move(child, target);
            }
        }
        finally
        {
            // Whatever happened to the contents, the built site no longer
            // matches them: a backup's pages are by definition older than the
            // ones just replaced, so a build left standing would read as newer
            // and publish what the course used to say. The kept copies of
            // geogebra.org sketches stay (#805): each is named by the fence
            // that asked for it, which no restore can make older.
            CourseArchiver.DiscardBuiltSites(coursesDirectory, item.CourseCode);
            // A restored course no longer holds what a stopped rename of its
            // word for a unit was part way through (#158, as the mac does).
            UnitWordRenamer.ClearRenameRecord(destination);
            LockAgainIfKeptForReference(destination);
            try { Directory.Delete(staging, recursive: true); } catch { }
        }
    }


    /// <summary>
    /// Puts ONE section back to how a backup has it, and touches no other:
    /// the built-in assistant window's "Restore Section N…" (the mac's
    /// <c>restoreSection</c>).
    ///
    /// <para>Whole-course restore was rejected for this job for the reason
    /// the mac's <c>AssistSectionRestore</c> gives: a teacher can be marking
    /// Section 2 in Obsidian while they chat about Section 1, and a
    /// whole-course rollback destroys that work. So: the section's own folder
    /// is replaced wholesale, hidden files included; the course's SHARED pages
    /// keep every byte except this section's own per-section frontmatter keys
    /// (<c>publishForSection1:</c> and its relatives), which go back to what
    /// the backup had; and the section's built site is discarded, because
    /// a build left standing would read as newer than the pages just put back.</para>
    ///
    /// <para><b>Staged, then swapped, with a way back (#911, the mac's #897 C,
    /// by Russell's ruling on #897 for this route too).</b> The backup is
    /// unpacked into <c>courses\.internal\restoring\&lt;id&gt;\</c>, on the
    /// courses' own volume, so every move is a rename (<c>%TEMP%</c> can be
    /// another volume, where <c>Directory.Move</c> refuses: #873's first
    /// fault). Nothing in the course moves until the backup is unpacked and
    /// checked; then <see cref="SwapSectionInPlace"/> moves the live children
    /// aside, moves the backup's in, and on a failure moves every moved file
    /// back. Before this the section folder was EMPTIED first and refilled,
    /// and a move that failed part way (a file Obsidian or an editor holds
    /// open) left it half empty.</para>
    /// </summary>
    /// <param name="hooks">The moves and the points a test or the kill harness stops at; <see cref="SectionSwapHooks.Real"/> otherwise.</param>
    /// <returns>How many shared pages kept their current setting because there was nowhere on them to put the backup's back (#308).</returns>
    public static int RestoreSection(int sectionNumber, BackupItem item, string coursesDirectory, SectionSwapHooks? hooks = null)
    {
        hooks ??= SectionSwapHooks.Real;
        string courseDir = Path.Combine(coursesDirectory, item.CourseCode);
        if (!Directory.Exists(courseDir))
            throw new RestoreException($"{item.CourseCode} is not in Courses & Clubs, so there is nowhere to put Section {sectionNumber} back.");
        if (ReadsAsKeptForReference(courseDir) is { } shown)
            throw new RestoreException(ReferenceCourse.StaysAsItIs(shown));

        var staging = new RestoreStaging(coursesDirectory);
        try
        {
            string payload = staging.Unpack(item);
            string folderName = "section" + sectionNumber;
            if (!Directory.Exists(Path.Combine(payload, folderName)))
                throw new RestoreException($"The copy of {item.CourseCode} does not hold a Section {sectionNumber}.");
            hooks.Reached(SwapPoint.Staged);

            try
            {
                SwapSectionInPlace(sectionNumber, courseDir, payload, Array.Empty<OneSectionRestore.OutsideFile>(), staging.Aside, hooks);
            }
            catch (WayBackDidNotFinish)
            {
                // The window makes no archive first, so it may not say one is in Archived.
                var kept = KeepTheSetAsideFiles(staging.Aside, sectionNumber, item.CourseCode, coursesDirectory);
                staging.KeepAside = kept.IsStillInStaging;
                throw new SectionRestoreStoppedPartWay(StoppedPartWaySentence(sectionNumber, kept.PathToSay, archived: false));
            }
            int notPutBack = RestorePerSectionKeys(sectionNumber, courseDir, payload);
            // The course's kept copies of geogebra.org sketches live at course
            // level (builds\<id>\<CODE>\.geogebra-cache), so a section's discard
            // never reaches them (#805; KeptCopiesTests).
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode, sectionNumber);
            return notPutBack;
        }
        finally
        {
            staging.Finish();
        }
    }

    // ---- The staged swap of one section (#911, the mac's #897 C) ----------

    /// <summary>
    /// Points a test, or the kill harness, can stop a one-section restore at
    /// (the mac's <c>SwapPoint</c>).
    /// </summary>
    public enum SwapPoint
    {
        /// <summary>The backup is unpacked and checked; nothing in the course has moved.</summary>
        Staged,
        /// <summary>Every live file the swap replaces is aside and none of the backup's is in: the moment the old code had an EMPTY section folder.</summary>
        SetAside,
    }

    /// <summary>
    /// How a one-section restore moves an entry, and what it does at each
    /// <see cref="SwapPoint"/> (the mac's <c>SectionSwapHooks</c>).
    /// <see cref="Real"/> everywhere but the tests: the double-failure sweep
    /// throws from <see cref="Move"/>, the real-fault tests only interleave a
    /// real file handle with it, and the kill harness blocks in it.
    /// </summary>
    public sealed class SectionSwapHooks
    {
        public required Action<string, string> Move { get; init; }
        public required Action<SwapPoint> Reached { get; init; }

        public static SectionSwapHooks Real { get; } = new() { Move = MoveEntry, Reached = _ => { } };
    }

    /// <summary>
    /// Renames one entry: a folder (or a junction or folder link, which moves
    /// AS a link) with <c>Directory.Move</c>, anything else with
    /// <c>File.Move</c>. Never a copy: both refuse another volume, which the
    /// staging folder beside the courses makes impossible.
    /// </summary>
    public static void MoveEntry(string source, string destination)
    {
        if ((File.GetAttributes(source) & FileAttributes.Directory) != 0) Directory.Move(source, destination);
        else File.Move(source, destination);
    }

    /// <summary>Thrown by <see cref="SwapSectionInPlace"/> when a move failed AND a move back failed too.</summary>
    private sealed class WayBackDidNotFinish : Exception;

    /// <summary>
    /// A restore's working folder, <c>courses\.internal\restoring\&lt;id&gt;\</c>
    /// (the mac's <c>stagingFolderBesideTheCourses</c>), holding <c>backup\</c>
    /// (the unpacked zip) and <c>as-it-was\</c> (what the swap moves aside).
    /// The mac uses two separate id folders for the assistant's route; one
    /// with two inner folders is the same promise and one place to name.
    /// </summary>
    private sealed class RestoreStaging
    {
        private readonly string _root;
        private readonly string _unpacked;

        public RestoreStaging(string coursesDirectory)
        {
            _root = Path.Combine(coursesDirectory, ".internal", "restoring", Guid.NewGuid().ToString("D").ToUpperInvariant());
            _unpacked = Path.Combine(_root, "backup");
            Aside = Path.Combine(_root, "as-it-was");
        }

        public string Aside { get; }

        /// <summary>True when the aside folder holds the only copy of something and must stay.</summary>
        public bool KeepAside { get; set; }

        public string Unpack(BackupItem item)
        {
            Directory.CreateDirectory(_unpacked);
            return CourseRestorer.Unpack(item.FilePath, item.CourseCode, _unpacked);
        }

        /// <summary>
        /// The unpacked backup always goes. The aside folder goes unless it
        /// must stay: kept by a way back that did not finish, or holding
        /// something backups leave out that went aside inside a folder of the
        /// section (a deeper <c>.git</c>: invariant 2 of the brief, "an only
        /// copy is never deleted"; the question is parked in the notes). Then
        /// <c>restoring</c> and <c>.internal</c>, each only when empty
        /// (<c>Directory.Delete</c> non-recursive refuses a folder that is not,
        /// so a lease written into <c>.internal\activity</c> meanwhile is safe:
        /// the mac's <c>rmdir</c>).
        /// </summary>
        public void Finish()
        {
            try { if (Directory.Exists(_unpacked)) DeleteTree(_unpacked); } catch { /* litter, never loss */ }
            bool keep = KeepAside || HoldsSomethingBackupsLeaveOut(Aside);
            if (!keep)
            {
                try { if (Directory.Exists(Aside)) DeleteTree(Aside); } catch { return; }
            }
            string? folder = _root;
            for (int level = 0; level < 3 && folder is not null; level++)
            {
                try { Directory.Delete(folder, recursive: false); }
                catch { return; }
                folder = Path.GetDirectoryName(folder);
            }
        }
    }

    /// <summary>Whether anything at any depth of <paramref name="folder"/> is named as backups leave out (<see cref="CourseArchiver.ExcludedFromArchives"/>).</summary>
    private static bool HoldsSomethingBackupsLeaveOut(string folder)
    {
        if (!Directory.Exists(folder)) return false;
        var pending = new Stack<string>();
        pending.Push(folder);
        while (pending.Count > 0)
        {
            string current = pending.Pop();
            IEnumerable<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(current).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered).ToList(); }
            catch { return true; }                                   // cannot tell: keep it
            foreach (var entry in entries)
            {
                if (CourseArchiver.ExcludedFromArchives.Contains(entry.Name)) return true;
                if ((entry.Attributes & FileAttributes.Directory) != 0 && (entry.Attributes & FileAttributes.ReparsePoint) == 0)
                    pending.Push(entry.FullName);
            }
        }
        return false;
    }

    /// <summary>
    /// Swaps a section's folder contents, and the files of it that live
    /// outside the folder, for the backup's, with a way back (the mac's
    /// <c>swapSectionInPlace</c>, move for move).
    ///
    /// <para>Out first, then in: every live child of <c>section&lt;N&gt;\</c>
    /// and every live outside file the list does not leave alone moves into
    /// <paramref name="aside"/>; then the backup's move into place. The folder
    /// <c>section&lt;N&gt;</c> itself never moves (Obsidian's watcher holds on
    /// to it). If any move fails, every move already made is made backwards,
    /// last first, and <c>wording.leftAsItWas</c> is thrown; if one of THOSE
    /// fails, <see cref="WayBackDidNotFinish"/> is thrown and the aside folder
    /// must be kept, because it then holds the only copy of what the section
    /// had.</para>
    ///
    /// <para><b>One difference from the mac, on purpose:</b> a child of the
    /// section folder named as backups leave out
    /// (<see cref="CourseArchiver.ExcludedFromArchives"/>, <c>.git</c> and
    /// <c>node_modules</c> among them) is in neither the backup nor the
    /// archive made first, so it is LEFT WHERE IT IS: never moved aside, never
    /// deleted (Russell's ruling on #909, "a restore never deletes a course's
    /// <c>.git</c>"). The mac's swap on <c>dev</c> moves it aside and deletes
    /// it with the aside folder (documentation 09, "Two edges").</para>
    /// </summary>
    private static void SwapSectionInPlace(int sectionNumber, string courseDir, string payload,
        IReadOnlyList<OneSectionRestore.OutsideFile> outsideFiles, string aside, SectionSwapHooks hooks,
        Action<string>? keepingWhatWasReplaced = null)
    {
        string folderName = "section" + sectionNumber;
        string liveSection = Path.Combine(courseDir, folderName);
        string backedUpSection = Path.Combine(payload, folderName);
        string asideSection = Path.Combine(aside, folderName);
        string asideOutside = Path.Combine(aside, "outside");
        Directory.CreateDirectory(liveSection);
        Directory.CreateDirectory(asideSection);
        Directory.CreateDirectory(asideOutside);

        var done = new List<(string From, string To)>();
        try
        {
            // Out: the section's own entries, hidden ones included.
            foreach (var child in new DirectoryInfo(liveSection).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered).ToList())
            {
                if (CourseArchiver.ExcludedFromArchives.Contains(child.Name)) continue;
                string destination = Path.Combine(asideSection, child.Name);
                hooks.Move(child.FullName, destination);
                done.Add((child.FullName, destination));
            }
            // Out: the section's files outside its folder.
            foreach (var file in outsideFiles)
            {
                if (file.Treatment == OneSectionRestore.Treatment.LeftAsItIs) continue;
                string relative = file.PathFor(sectionNumber);
                string live = Path.Combine(courseDir, relative);
                if (!File.Exists(live) && !Directory.Exists(live)) continue;
                string destination = Path.Combine(asideOutside, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                hooks.Move(live, destination);
                done.Add((live, destination));
            }
            hooks.Reached(SwapPoint.SetAside);
            // In: the backup's section entries.
            foreach (var child in new DirectoryInfo(backedUpSection).EnumerateFileSystemInfos("*", ReferenceLock.Unfiltered).ToList())
            {
                string destination = Path.Combine(liveSection, child.Name);
                hooks.Move(child.FullName, destination);
                done.Add((child.FullName, destination));
            }
            // In: the backup's files outside the folder, where it has them.
            foreach (var file in outsideFiles)
            {
                if (file.Treatment != OneSectionRestore.Treatment.FromTheBackup) continue;
                string relative = file.PathFor(sectionNumber);
                string backedUp = Path.Combine(payload, relative);
                if (!File.Exists(backedUp) && !Directory.Exists(backedUp)) continue;
                string destination = Path.Combine(courseDir, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                hooks.Move(backedUp, destination);
                done.Add((backedUp, destination));
            }
        }
        catch (Exception error) when (error is not WayBackDidNotFinish)
        {
            bool everyFileIsBack = true;
            for (int index = done.Count - 1; index >= 0; index--)
            {
                try { hooks.Move(done[index].To, done[index].From); }
                catch { everyFileIsBack = false; }
            }
            if (!everyFileIsBack) throw new WayBackDidNotFinish();
            throw new RestoreException(OneSectionRestoreWording.LeftAsItWas(sectionNumber, error.Message));
        }
        keepingWhatWasReplaced?.Invoke(aside);
    }

    /// <summary>Where a stopped restore kept what it set aside, and whether a teacher would find anything there.</summary>
    internal sealed record SetAsideFiles(string Path, bool HoldsSomethingToOpen, bool IsStillInStaging)
    {
        /// <summary>The path the teacher is told, or null when there is nothing there to open.</summary>
        public string? PathToSay => HoldsSomethingToOpen ? Path : null;
    }

    /// <summary>
    /// Moves the files a stopped restore set aside to
    /// <c>courses\_backups\&lt;CODE&gt;\Section N before a restore &lt;stamp&gt;</c>
    /// (the mac's <c>keepTheSetAsideFiles</c>): the one place in a working
    /// folder that already holds copies of the course, on the same volume (a
    /// rename), where nothing reads a FOLDER (<see cref="Workspace"/>'s
    /// backup and archive lists read top-level <c>.zip</c> names only). When
    /// that move fails, the files stay in <c>courses\.internal\restoring\</c>
    /// and that path is what is said. Writes <c>section restore stopped part
    /// way</c>: the course, the section and the path, never a page.
    /// </summary>
    internal static SetAsideFiles KeepTheSetAsideFiles(string aside, int sectionNumber, string courseCode, string coursesDirectory)
    {
        string trimmed = coursesDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string workingFolder = Path.GetDirectoryName(trimmed) ?? trimmed;
        string shelf = Path.Combine(trimmed, "_backups", courseCode);
        // No comma: the sentence that names it puts punctuation after it.
        string name = $"Section {sectionNumber} before a restore " + DateTime.Now.ToString(ArchivedItem.StampFormat, CultureInfo.InvariantCulture);
        string kept = aside;
        try
        {
            Directory.CreateDirectory(shelf);
            string destination = Path.Combine(shelf, name);
            Directory.Move(aside, destination);
            kept = destination;
        }
        catch
        {
            kept = aside;
        }
        string keptAt = Path.GetRelativePath(workingFolder, kept);
        ActivityTrail.Note(ActivityTrail.Event.SectionRestoreStoppedPartWay,
            ActivityTrail.SectionRestoreStoppedPartWayLine(keptAt), courseCode, sectionNumber);
        return new SetAsideFiles(keptAt, HoldsAFileATeacherWouldOpen(kept), string.Equals(kept, aside, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Whether a folder holds a file whose path inside it has no part starting
    /// with a dot (the mac's <c>holdsAFileFinderShows</c>, the same rule:
    /// what is left otherwise is Plantoir's own records, such as
    /// <c>outside\.internal\timetable\section2.json</c>, and not a page).
    /// Explorer does show dot-named files; the rule is kept as the mac's so
    /// the two apps choose the same sentence for the same folder.
    /// </summary>
    private static bool HoldsAFileATeacherWouldOpen(string folder)
    {
        if (!Directory.Exists(folder)) return false;
        foreach (string file in Directory.EnumerateFiles(folder, "*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = 0, IgnoreInaccessible = true }))
        {
            string relative = Path.GetRelativePath(folder, file);
            bool hidden = false;
            foreach (string part in relative.Split(Path.DirectorySeparatorChar))
                if (part.StartsWith('.')) hidden = true;
            if (!hidden) return true;
        }
        return false;
    }

    /// <summary>The sentence for a restore whose way back did not finish (the mac's <c>Problem.sectionRestoreStoppedPartWay</c>).</summary>
    internal static string StoppedPartWaySentence(int sectionNumber, string? keptAt, bool archived)
    {
        string said = keptAt is null
            ? OneSectionRestoreWording.StoppedPartWayNothingToOpen(sectionNumber)
            : OneSectionRestoreWording.StoppedPartWay(sectionNumber, keptAt);
        return archived ? said + " " + OneSectionRestoreWording.StoppedPartWayArchived : said;
    }

    /// <summary>The code a teacher reads, when the course at <paramref name="courseDir"/> is kept for reference; otherwise null.</summary>
    private static string? ReadsAsKeptForReference(string courseDir)
    {
        try
        {
            var configuration = CourseConfiguration.Load(Path.Combine(courseDir, "course_config.json"));
            var course = new Course(Path.GetFileName(courseDir), courseDir, configuration);
            return ReferenceCourse.IsKeptForReference(course) ? ReferenceCourse.ShownCode(course) : null;
        }
        catch { return null; }
    }

    /// <summary>
    /// A zip carries no lock, so a restored reference course arrives thawed;
    /// the MARKER, which travels in the settings, is what puts it back.
    /// </summary>
    private static void LockAgainIfKeptForReference(string courseDir)
    {
        if (ReadsAsKeptForReference(courseDir) is not null) ReferenceLock.Lock(courseDir);
    }

    /// <summary>
    /// Every shared page of the course gets this section's per-section keys
    /// back as the backup had them, and nothing else about it changes.
    /// </summary>
    private static int RestorePerSectionKeys(int sectionNumber, string courseDir, string payload)
    {
        int notPutBack = 0;
        foreach (string page in SharedMarkdownPages(courseDir))
        {
            string relative = Path.GetRelativePath(courseDir, page);
            string backedUpPage = Path.Combine(payload, relative);
            string liveText, backupText;
            try
            {
                if (!File.Exists(backedUpPage)) continue;
                backupText = File.ReadAllText(backedUpPage);
                liveText = File.ReadAllText(page);
            }
            catch (IOException) { continue; }
            catch (UnauthorizedAccessException) { continue; }
            var (rewritten, couldNotBePutBack) = SettingPerSectionKeys(sectionNumber, liveText, backupText);
            if (couldNotBePutBack) notPutBack++;
            if (rewritten != liveText)
            {
                try { File.WriteAllText(page, rewritten); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
        }
        return notPutBack;
    }

    /// <summary>The course's Markdown pages outside every section folder and every excluded folder.</summary>
    private static IEnumerable<string> SharedMarkdownPages(string directory)
    {
        IEnumerable<string> entries;
        try { entries = Directory.EnumerateFileSystemEntries(directory).ToList(); }
        catch (IOException) { yield break; }
        catch (UnauthorizedAccessException) { yield break; }
        foreach (string entry in entries)
        {
            string name = Path.GetFileName(entry);
            if (Directory.Exists(entry))
            {
                if (NamesASectionFolder(name) || CourseArchiver.ExcludedFromArchives.Contains(name)) continue;
                foreach (string inner in SharedMarkdownPages(entry)) yield return inner;
            }
            else if (string.Equals(Path.GetExtension(entry), ".md", StringComparison.OrdinalIgnoreCase))
            {
                yield return entry;
            }
        }
    }

    public static bool NamesASectionFolder(string name)
    {
        const string prefix = "section";
        if (!name.StartsWith(prefix, StringComparison.Ordinal) || name.Length == prefix.Length) return false;
        for (int index = prefix.Length; index < name.Length; index++)
            if (!char.IsAsciiDigit(name[index])) return false;
        return true;
    }

    /// <summary>
    /// The live page's text with this section's per-section keys as the
    /// backup had them — the mac's <c>settingPerSectionKeys</c>, line for
    /// line, pinned by <c>course-management.json →
    /// backups.restoringOneSectionsKeys</c> (compared as bytes).
    /// </summary>
    /// <remarks>
    /// <para>This section's lines are replaced by the backup's (or dropped when
    /// the backup had none), each key WITH the lines it owns
    /// (<see cref="PageVisibilityReader.LinesOwnedByKey"/>, #182): copying key
    /// LINES only brought a backup's <c>publishForSection1: &gt;-</c> back as
    /// <c>&gt;-</c> alone — PUBLISHED. With none of its own left on the page,
    /// the restored lines go after the last line any per-section key OWNS, never
    /// between another section's key and its value.</para>
    /// <para>The block is found with the shared finder (#177, decided
    /// 2026-09-19 and again 2026-09-25: Windows matches the mac), so a restore
    /// reaches the same pages the build reads — a <c>----</c> fence, a blank
    /// line before the fence (which the restored page drops, as the mac's
    /// does — Russell, 2026-10-01). Rejected: both apps going strict (restore would
    /// then disagree with hide and show on the same page), and leaving the
    /// divergence. The old <c>liveText.Contains("\n---")</c> refuse-to-prepend
    /// guard went with the strict finder, which is what it compensated for.</para>
    /// <para>When the page has no line of this section and its block has no
    /// column-0 level for a new key (#186's shape), the page is left byte for
    /// byte and <c>CouldNotBePutBack</c> is true: the caller counts it, says
    /// so, and records <c>page settings left as they were</c>.</para>
    /// </remarks>
    public static (string Text, bool CouldNotBePutBack) SettingPerSectionKeys(
        int sectionNumber, string liveText, string backupText)
    {
        var backupLines = backupText.Split('\n');
        var restoredLines = PerSectionLineIndices(sectionNumber, backupText)
            .Select(index => PageVisibilityReader.TrimCarriageReturn(backupLines[index]))
            .ToList();

        if (PageVisibilityReader.FenceIndices(liveText) is not { } liveBlock)
        {
            if (restoredLines.Count == 0) return (liveText, false);
            return ("---\n" + string.Join("\n", restoredLines) + "\n---\n" + liveText, false);
        }

        var lines = liveText.Split('\n');
        var doomed = PerSectionLineIndices(sectionNumber, liveText).ToHashSet();
        int lastPerSectionIndex = PerSectionLineIndices(null, liveText).DefaultIfEmpty(-1).Max();

        // The rebuilt page starts AT the opening fence: blank lines before it
        // (the only thing that can stand there) are dropped, as the mac's
        // settingPerSectionKeys drops them. Windows kept them from bundle 2
        // until Russell chose to match on 2026-10-01; either is harmless to
        // the build, and one behaviour is one less difference to explain.
        var rebuilt = new List<string> { lines[liveBlock.Open] };
        bool placed = false;
        for (int index = liveBlock.Open + 1; index < liveBlock.Close; index++)
        {
            if (doomed.Contains(index))
            {
                if (!placed) { rebuilt.AddRange(restoredLines); placed = true; }
                continue;
            }
            rebuilt.Add(lines[index]);
            if (index == lastPerSectionIndex && !placed) { rebuilt.AddRange(restoredLines); placed = true; }
        }
        if (!placed && restoredLines.Count > 0)
        {
            // A brand-new key: only where the block has a column-0 level for it.
            if (PageVisibilityReader.PlaceForANewTopLevelKey(lines, liveBlock.Open, liveBlock.Close) is null)
                return (liveText, true);
            rebuilt.AddRange(restoredLines);
        }
        rebuilt.AddRange(lines.Skip(liveBlock.Close));
        return (string.Join("\n", rebuilt), false);
    }

    /// <summary>
    /// The indices of every line of the page's block that is a per-section key
    /// for <paramref name="sectionNumber"/> (or for any section, when null) or
    /// a line such a key OWNS, in file order.
    /// </summary>
    internal static List<int> PerSectionLineIndices(int? sectionNumber, string pageText)
    {
        var found = new List<int>();
        if (PageVisibilityReader.FenceIndices(pageText) is not { } block) return found;
        var lines = pageText.Split('\n');
        for (int index = block.Open + 1; index < block.Close; index++)
        {
            string bare = PageVisibilityReader.TrimCarriageReturn(lines[index]);
            if (SectionAdder.PerSectionKey(bare) is not { } named) continue;
            if (sectionNumber is { } wanted && named.Number != wanted) continue;
            found.Add(index);
            // Asked of the key's own line as it stands: nothing here is rewritten.
            string key = named.Key;
            bool wasEmpty = PageVisibilityReader.ValuePart(key, bare) is { } value
                && PageVisibilityReader.TrimYamlSpaces(value).Length == 0;
            found.AddRange(PageVisibilityReader.LinesOwnedByKey(lines, index, block.Close, wasEmpty));
        }
        return found;
    }

    /// <summary>
    /// A delete that survives what a course folder really holds: the
    /// container leaves links inside .merged_output that
    /// Directory.Delete(recursive) cannot traverse (the restore died on
    /// content\Media before touching anything else), and readonly files stop
    /// it too. Reparse points are deleted AS LINKS, never followed.
    ///
    /// Shared with <see cref="CourseArchiver"/>, which learned the same
    /// lesson separately: the Quartz project copied into .merged_output can
    /// carry a .git whose pack files are readonly, and removing a course
    /// died on the first one — "Access to the path 'pack-….idx' is denied"
    /// — leaving the folder half-deleted behind an archive that had already
    /// succeeded.
    /// </summary>
    internal static void DeleteTree(string path)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch { attributes = FileAttributes.Normal; }

        if ((attributes & FileAttributes.Directory) != 0)
        {
            if ((attributes & FileAttributes.ReparsePoint) == 0)
                foreach (string child in Directory.EnumerateFileSystemEntries(path))
                    DeleteTree(child);
            Directory.Delete(path, recursive: false);
        }
        else
        {
            if ((attributes & FileAttributes.ReadOnly) != 0)
                File.SetAttributes(path, attributes & ~FileAttributes.ReadOnly);
            File.Delete(path);
        }
    }

    /// <summary>The app's one true deletion — the confirmation lives with the caller.</summary>
    // ---- The trail line of a whole-course restore ("course restored from a backup")

    /// <summary>
    /// The line a whole course put back from one of its backups leaves, once
    /// it has been put back (the mac's <c>restoredTrailLine</c>, #572): the
    /// code it shows and its folder, the backup's file name, the archive the
    /// caller made of the course as it was first or that there was none to
    /// make, and whether the course that came back is kept for reference, as
    /// its settings say NOW. Never a page.
    /// </summary>
    /// <param name="archivePath">The archive made first, or null when the folder held no course to archive.</param>
    public static string RestoredTrailLine(BackupItem item, string? archivePath, string coursesDirectory)
    {
        string line = Restored(item.CourseCode, coursesDirectory, out bool kept) + " from " + Path.GetFileName(item.FilePath);
        line += archivePath is null
            ? " — there was no course in that folder to archive first"
            : " — the course as it was is in Archived as " + Path.GetFileName(archivePath);
        return line + (kept ? "; kept for reference" : "; a course you teach");
    }

    /// <summary>
    /// The line a whole course put back from Archived leaves (the mac's
    /// <c>restoredFromArchivedTrailLine</c>, #572 review L5): the archive's
    /// file name and what became of it. <see cref="Restore"/> deletes it and
    /// does not fail when it cannot, so the line says which happened.
    /// </summary>
    public static string RestoredFromArchivedTrailLine(ArchivedItem item, string coursesDirectory)
    {
        string line = Restored(item.CourseCode, coursesDirectory, out bool kept) + " from Archived, " + Path.GetFileName(item.FilePath);
        line += File.Exists(item.FilePath)
            ? " — that archive could not be removed and is still listed"
            : " — that archive is used up";
        return line + (kept ? "; kept for reference" : "; a course you teach");
    }

    /// <summary>"restored ICS3U (ICS3U-2025)": the code a teacher reads, as the restored settings say, and the folder.</summary>
    private static string Restored(string folderName, string coursesDirectory, out bool kept)
    {
        string? shown = ReferenceCourse.KeptOnDisk(Path.Combine(coursesDirectory, folderName));
        kept = shown is not null;
        return $"restored {shown ?? folderName} ({folderName})";
    }

    public static void DeleteBackup(BackupItem item) => File.Delete(item.FilePath);

    /// <summary>Archives are deletable too (row 106 round two) — same rule.</summary>
    public static void DeleteArchive(ArchivedItem item) => File.Delete(item.FilePath);

    /// <summary>Archiving took the number out; restoring must put it back.</summary>
    private static void PutSectionBack(Course course, int section)
    {
        var numbers = course.Configuration.SectionNumbers;
        if (!numbers.Contains(section)) numbers.Add(section);
        numbers.Sort();
        course.Configuration.SetSectionNumbers(numbers);
        course.Configuration.Write(course.ConfigFilePath);
    }

    /// <summary>
    /// Extract expecting the named folder at the archive root; when it is
    /// absent but the archive holds exactly one folder, use that one (so
    /// archives made by another version still restore).
    /// </summary>
    private static void Extract(string archivePath, string expectedName, string destinationParent)
    {
        string staging = Path.Combine(Path.GetTempPath(), "restore-" + Guid.NewGuid());
        Directory.CreateDirectory(staging);
        try
        {
            string payload = Unpack(archivePath, expectedName, staging);
            Directory.CreateDirectory(destinationParent);
            Directory.Move(payload, Path.Combine(destinationParent, expectedName));
        }
        finally
        {
            try { Directory.Delete(staging, recursive: true); } catch { }
        }
    }

    /// <summary>
    /// Unzips into the staging folder and returns the payload — the folder
    /// the archive's name promised, or the single folder it holds (so an
    /// archive made by another version still restores).
    /// </summary>
    private static string Unpack(string archivePath, string expectedName, string staging)
    {
        try { ZipFile.ExtractToDirectory(archivePath, staging); }
        catch (Exception error)
        {
            throw new RestoreException($"The archive could not be opened: {error.Message}");
        }

        string payload = Path.Combine(staging, expectedName);
        if (!Directory.Exists(payload))
        {
            var entries = Directory.EnumerateFileSystemEntries(staging)
                .Where(e => !Path.GetFileName(e).StartsWith('.'))
                .ToList();
            if (entries.Count == 1) payload = entries[0];
            else throw new RestoreException($"The archive could not be opened: it does not contain {expectedName}");
        }
        return payload;
    }
}
