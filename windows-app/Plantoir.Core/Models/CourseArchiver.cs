using System.Globalization;
using System.IO.Compression;

namespace Plantoir.Core.Models;

/// <summary>
/// Removes a course or section without destroying content: zip first into
/// courses/_backups/&lt;CODE&gt;/, then delete. The archive root contains the
/// folder itself (section3/…, ICS3U/…) — the restorer depends on that.
/// </summary>
public static class CourseArchiver
{
    /// <summary>The same exclusion list the setup wizard uses for its own backups.</summary>
    public static readonly IReadOnlyList<string> ExcludedFromArchives = new[]
    {
        ".merged_output", "node_modules", ".git", ".quartz-cache", ".cache",
        "dist", "build", "out", "__pycache__", ".DS_Store",
    };

    /// <summary>
    /// How many of the ASSISTANT's backups of one course are kept.
    ///
    /// A course full of images makes a large zip, and the assistant saves one
    /// per conversation whether or not anybody asked for it, so without a
    /// limit a term of chats fills a disk with copies of copies. (Until
    /// 2026-09-07 this comment described the mac and not this code, which
    /// saved one per CHANGE — so after six changes the copy from before the
    /// conversation had already been pruned. See
    /// <c>AssistWorkspace.BackUpOnceForThisConversation</c>.)
    ///
    /// A teacher's OWN backups are never counted here and never pruned. They
    /// made those on purpose; deciding on their behalf that a backup from
    /// last month has expired is not the app's call to make.
    /// </summary>
    public const int MostBackupsKept = 5;

    public static string TimestampedName(string prefix, DateTime stamp, string suffix = "") =>
        $"{prefix}_{stamp.ToString(ArchivedItem.StampFormat, CultureInfo.InvariantCulture)}{suffix}.zip";

    public static string BackupsDirectory(string coursesDirectory, string courseCode) =>
        Path.Combine(coursesDirectory, "_backups", courseCode);

    /// <summary>
    /// Saves a copy of an entire course — and touches nothing: the course
    /// stays exactly where it is. Made on purpose before risky editing so
    /// there is always a way back (row 106). The name
    /// (&lt;CODE&gt;_backup_&lt;timestamp&gt;.zip) is what separates a backup from an
    /// archive in the shared _backups folder.
    /// </summary>
    public static string BackUpCourse(Course course, string coursesDirectory, BackupMaker? maker = null)
    {
        var actualMaker = maker ?? BackupMaker.DefaultTeacher;
        string backupPath = Archive(course.DirectoryPath, course.Code + "_backup", coursesDirectory, course.Code, actualMaker.NameSuffix);
        PruneBackups(course.Code, coursesDirectory);
        return backupPath;
    }

    /// <summary>
    /// Deletes the oldest backups of one course until only
    /// <see cref="MostBackupsKept"/> are left.
    ///
    /// ONLY the assistant's own backups are pruned. A teacher's backup is a
    /// decision — deleting that on a schedule they never agreed to is the app
    /// overruling them about their own work.
    ///
    /// And only backups whose stamp COULD BE TRUE. See
    /// <see cref="ArchiveStamp"/>: a zip carried in from a Mac that wrote its
    /// own calendar into the name parses cleanly as a year like 2569, sorts
    /// as the newest thing in the folder, and would take a real backup's
    /// place among the five that are kept.
    /// </summary>
    /// <param name="now">
    /// The clock the plausibility check measures against. Nothing in the app
    /// passes it; tests do, because the CEILING is the half of the rule
    /// nothing on disk can exercise on its own — a stamp is past it or not
    /// depending only on when the suite happens to run. See
    /// <c>PruneBackups_AStampPastTheCeiling_CountsOnceTheClockCatchesUp</c>,
    /// which asks about one file twice with the clock in two places.
    /// </param>
    public static void PruneBackups(string courseCode, string coursesDirectory, DateTime? now = null)
    {
        string backupsDir = BackupsDirectory(coursesDirectory, courseCode);
        if (!Directory.Exists(backupsDir)) return;

        var entries = Directory.GetFiles(backupsDir, "*.zip");
        var assistantBackups = new List<BackupItem>();
        foreach (var file in entries)
        {
            if (BackupItem.From(file, courseCode) is not { } item) continue;
            if (item.Maker is not BackupMaker.Assistant) continue;
            // A stamp that cannot be true is not allowed to decide what gets
            // DELETED. The zip stays where it is and stays LISTED, so the
            // teacher can restore it or delete it themselves; it is simply
            // left out of the count and out of the sort, because its date is
            // the one thing about it known to be wrong and this list is
            // sorted by date before its tail is thrown away.
            if (!ArchiveStamp.CouldHaveBeenStamped(item.BackedUpAt, now)) continue;
            assistantBackups.Add(item);
        }

        if (assistantBackups.Count <= MostBackupsKept) return;

        // Newest first. Two backups made in the same second are ordered by name.
        assistantBackups.Sort((first, second) =>
        {
            if (first.BackedUpAt == second.BackedUpAt)
                return string.Compare(Path.GetFileName(second.FilePath), Path.GetFileName(first.FilePath), StringComparison.Ordinal);
            return second.BackedUpAt.CompareTo(first.BackedUpAt);
        });

        int kept = 0;
        foreach (var backup in assistantBackups)
        {
            kept++;
            if (kept > MostBackupsKept)
            {
                try { File.Delete(backup.FilePath); } catch { }
            }
        }
    }

    /// <summary>
    /// Writes an archive of an entire course folder WITHOUT removing it —
    /// for restores, which replace the course's contents in place so
    /// Obsidian's file watcher (anchored to the folder) keeps up.
    /// </summary>
    public static string ArchiveCourseWithoutRemoving(Course course, string coursesDirectory) =>
        Archive(course.DirectoryPath, course.Code, coursesDirectory, course.Code);

    /// <summary>
    /// Archive a whole course, then remove its folder — with the delete that
    /// survives readonly files and links (<see cref="CourseRestorer.DeleteTree"/>),
    /// because a build leaves both inside .merged_output.
    /// </summary>
    public static string ArchiveAndRemoveCourse(Course course, string coursesDirectory)
    {
        // CANCEL FIRST (#239): every deploy this working folder has set for
        // the course, asked of the scheduler. A cancel that fails throws
        // before anything is archived or removed.
        var turnedOff = Plantoir.Core.Assist.ScheduledDeployRemoval.TurnOffFirst(
            WorkingFolderOf(coursesDirectory), course.Code, section: null, "the course was removed");
        try
        {
            return RemoveCourse(course, coursesDirectory);
        }
        catch (Exception error) when (turnedOff.Count > 0)
        {
            throw new InvalidOperationException(
                Plantoir.Core.Assist.ScheduledDeployRemoval.RemovalFailedAfterTurningItOff(course.Code, turnedOff, error.Message), error);
        }
    }

    /// <summary>The working folder a courses directory belongs to — its parent.</summary>
    private static string WorkingFolderOf(string coursesDirectory) =>
        Path.GetDirectoryName(coursesDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
        ?? coursesDirectory;

    private static string RemoveCourse(Course course, string coursesDirectory)
    {
        // A reference course is locked (#241): UNLOCK after the cancel and
        // before the archive, so the one thing that can stop a removal is
        // still the cancel, and a locked tree never meets the delete. Asked of
        // what is ON DISK rather than of the marker, so a course marked by
        // hand, or carried from another computer, is released all the same;
        // a course with nothing locked costs one walk. The teacher is told
        // nothing about it.
        ReferenceLock.Unlock(course.DirectoryPath);
        string archivePath = ArchiveCourseWithoutRemoving(course, coursesDirectory);
        CourseRestorer.DeleteTree(course.DirectoryPath);
        // A build outlives the content it was made from. Archive this course
        // and restore it next term and the notes that come back can be OLDER
        // than the site standing outside the working folder, so a freshness
        // check comparing dates says "already up to date" and the next publish
        // puts last term's pages online. The mac reaches the same rule a
        // different way - a build with no symlink pointing at it is cleared
        // rather than reused - and Windows has no link, so the clearing is
        // explicit at each moment a course's content is replaced.
        DiscardBuilds(coursesDirectory, course.Code);
        return archivePath;
    }

    /// <summary>
    /// Throw away a course's built site and build workspace, given the courses
    /// directory this course lives in.
    ///
    /// <para>The working folder is the courses directory's parent — the same
    /// relationship <c>Workspace.CoursesDirectory</c> creates going the other
    /// way. Best-effort inside <see cref="BuildOutputLocation"/>: a build
    /// still locked by a running preview must not turn "archive this course"
    /// into an error.</para>
    /// </summary>
    internal static void DiscardBuilds(string coursesDirectory, string courseCode, int? sectionNumber = null)
    {
        string? workingFolder = Path.GetDirectoryName(coursesDirectory.TrimEnd(
            Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (string.IsNullOrEmpty(workingFolder)) return;
        string buildsRoot = BuildOutputLocation.BuildsRootFor(workingFolder!);
        if (sectionNumber is int number)
            BuildOutputLocation.DiscardBuildsFor(buildsRoot, courseCode, number);
        else
            BuildOutputLocation.DiscardBuildsFor(buildsRoot, courseCode);
    }

    /// <summary>
    /// Archive one section, remove it, and take its number out of the
    /// course's settings (num_sections follows along).
    /// </summary>
    public static string ArchiveAndRemoveSection(Course course, int sectionNumber, string coursesDirectory)
    {
        // A reference course stays as it is (#241): removing a section
        // changes the course. The sidebar does not offer it; this is what any
        // other caller meets, in a sentence rather than the file system's own.
        if (ReferenceCourse.IsKeptForReference(course))
            throw new InvalidOperationException(ReferenceCourse.StaysAsItIs(ReferenceCourse.ShownCode(course)));
        // CANCEL FIRST (#239), and only this working folder's deploy of this
        // section. This used to cancel AFTER archiving and ignore a failure.
        var turnedOff = Plantoir.Core.Assist.ScheduledDeployRemoval.TurnOffFirst(
            WorkingFolderOf(coursesDirectory), course.Code, sectionNumber, "the section was removed");
        try
        {
            return RemoveSection(course, sectionNumber, coursesDirectory);
        }
        catch (Exception error) when (turnedOff.Count > 0)
        {
            throw new InvalidOperationException(
                Plantoir.Core.Assist.ScheduledDeployRemoval.RemovalFailedAfterTurningItOff(course.Code, turnedOff, error.Message), error);
        }
    }

    private static string RemoveSection(Course course, int sectionNumber, string coursesDirectory)
    {
        string sectionDir = course.SectionDirectory(sectionNumber);
        string archivePath = Archive(sectionDir, $"{course.Code}-section{sectionNumber}",
                                     coursesDirectory, course.Code);
        if (Directory.Exists(sectionDir)) CourseRestorer.DeleteTree(sectionDir);
        DiscardBuilds(coursesDirectory, course.Code, sectionNumber);
        var remaining = course.Configuration.SectionNumbers.Where(n => n != sectionNumber).ToList();
        course.Configuration.SetSectionNumbers(remaining);
        course.Configuration.Write(course.ConfigFilePath);
        return archivePath;
    }

    private static string Archive(string folderPath, string prefix, string coursesDirectory, string courseCode, string suffix = "")
    {
        string backupsDir = BackupsDirectory(coursesDirectory, courseCode);
        Directory.CreateDirectory(backupsDir);

        // Names are stamped to the second, and two operations can easily land
        // in the same one — an assistant publishing two classes in a row does
        // it every time. Without this the second backup throws, which (because
        // no backup means no edits) turns a routine sequence into a refusal.
        //
        // On a collision, WAIT for the next second and stamp again (#187). This
        // used to append "-2", "-3"… to the name, which neither reader parses —
        // so the second backup was invisible in the Backups list, uncounted by
        // pruning, and (on the mac, which reads the same folder) invisible
        // there too. Rejected: teaching both readers a "-N" suffix (the MAC's
        // reader would then hide a zip Windows wrote until it learned it too),
        // and a millisecond stamp (it changes the frozen zipNames format). The
        // cost is at most a second's wait, only when two land in one second.
        string archivePath = Path.Combine(backupsDir, TimestampedName(prefix, DateTime.Now, suffix));
        for (int attempt = 0; File.Exists(archivePath) && attempt < 3; attempt++)
        {
            Thread.Sleep(1000 - DateTime.Now.Millisecond + 10);
            archivePath = Path.Combine(backupsDir, TimestampedName(prefix, DateTime.Now, suffix));
        }

        ZipFolder(folderPath, archivePath);
        return archivePath;
    }

    /// <summary>
    /// Zips a folder with the folder itself as the archive's root entry.
    /// The walk NEVER DESCENDS into an excluded folder — filtering paths
    /// after a full enumeration walked straight into .merged_output, where
    /// container-made links (content\Media) cannot be traversed by Windows
    /// and sank the whole backup. Reparse points are skipped for the same
    /// reason. A failure never leaves a partial zip behind.
    /// </summary>
    public static void ZipFolder(string folderPath, string archivePath)
    {
        string rootName = Path.GetFileName(folderPath.TrimEnd(Path.DirectorySeparatorChar));
        try
        {
            using var archive = ZipFile.Open(archivePath, ZipArchiveMode.Create);
            AddFolder(archive, folderPath, rootName);
        }
        catch
        {
            try { File.Delete(archivePath); } catch { }
            throw;
        }
    }

    private static void AddFolder(ZipArchive archive, string folderPath, string entryPrefix)
    {
        foreach (string file in Directory.EnumerateFiles(folderPath))
        {
            if (ExcludedFromArchives.Contains(Path.GetFileName(file))) continue;   // .DS_Store
            archive.CreateEntryFromFile(file, entryPrefix + "/" + Path.GetFileName(file),
                                        CompressionLevel.Optimal);
        }
        foreach (string sub in Directory.EnumerateDirectories(folderPath))
        {
            string name = Path.GetFileName(sub);
            if (ExcludedFromArchives.Contains(name)) continue;
            if ((new DirectoryInfo(sub).Attributes & FileAttributes.ReparsePoint) != 0) continue;
            AddFolder(archive, sub, entryPrefix + "/" + name);
        }
    }
}
