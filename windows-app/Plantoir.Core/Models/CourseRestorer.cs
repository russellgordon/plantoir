using System.IO.Compression;

namespace Plantoir.Core.Models;

/// <summary>
/// Brings an archived course or section back. Nothing is ever written over —
/// what is in the way may be newer work, so the restore refuses and explains.
/// </summary>
public static class CourseRestorer
{
    public sealed class RestoreException(string message) : Exception(message);

    public static void Restore(ArchivedItem item, string coursesDirectory, IReadOnlyList<Course> courses)
    {
        if (item.SectionNumber is int section)
        {
            Course? course = courses.FirstOrDefault(c => c.Code == item.CourseCode);
            if (course is null)
                throw new RestoreException(
                    $"{item.CourseCode} is not in Courses & Clubs. Restore the course first, then restore this section into it.");
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
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode);
            return;
        }

        string staging = Path.Combine(Path.GetTempPath(), "restore-" + Guid.NewGuid());
        Directory.CreateDirectory(staging);
        try
        {
            string payload = Unpack(item.FilePath, item.CourseCode, staging);

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
            // and publish what the course used to say.
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode);
            try { Directory.Delete(staging, recursive: true); } catch { }
        }
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
