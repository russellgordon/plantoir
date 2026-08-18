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
    /// limit a term of chats fills a disk with copies of copies.
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
    /// </summary>
    public static void PruneBackups(string courseCode, string coursesDirectory)
    {
        string backupsDir = BackupsDirectory(coursesDirectory, courseCode);
        if (!Directory.Exists(backupsDir)) return;

        var entries = Directory.GetFiles(backupsDir, "*.zip");
        var assistantBackups = new List<BackupItem>();
        foreach (var file in entries)
        {
            if (BackupItem.From(file, courseCode) is { } item && item.Maker is BackupMaker.Assistant)
            {
                assistantBackups.Add(item);
            }
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
        string archivePath = ArchiveCourseWithoutRemoving(course, coursesDirectory);
        CourseRestorer.DeleteTree(course.DirectoryPath);
        return archivePath;
    }

    /// <summary>
    /// Archive one section, remove it, and take its number out of the
    /// course's settings (num_sections follows along).
    /// </summary>
    public static string ArchiveAndRemoveSection(Course course, int sectionNumber, string coursesDirectory)
    {
        string sectionDir = course.SectionDirectory(sectionNumber);
        string archivePath = Archive(sectionDir, $"{course.Code}-section{sectionNumber}",
                                     coursesDirectory, course.Code);
        if (Directory.Exists(sectionDir)) CourseRestorer.DeleteTree(sectionDir);
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
        string archivePath = Path.Combine(backupsDir, TimestampedName(prefix, DateTime.Now, suffix));
        for (int attempt = 2; File.Exists(archivePath) && attempt < 100; attempt++)
            archivePath = Path.Combine(backupsDir,
                TimestampedName(prefix, DateTime.Now, suffix).Replace(".zip", $"-{attempt}.zip"));

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
