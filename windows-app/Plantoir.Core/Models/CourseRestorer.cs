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
    /// <summary>
    /// Puts ONE section back to how a backup has it, and touches no other.
    ///
    /// <para>Whole-course restore was rejected for this job for the reason
    /// the mac's <c>AssistSectionRestore</c> gives: a teacher can be marking
    /// Section 2 in Obsidian while they chat about Section 1, and a
    /// whole-course rollback destroys that work. So: the section's own folder
    /// is replaced wholesale, hidden files included; the course's SHARED pages
    /// keep every byte except this section's own per-section frontmatter keys
    /// (<c>publishForSection1:</c> and its relatives), which go back to what
    /// the backup had — a key the conversation added where there was none
    /// goes, one it removed comes back — so whether the shared pages are
    /// published for this section is restored without touching what they
    /// say for any other; and the section's built site is discarded, because
    /// a build left standing would read as newer than the pages just put back.</para>
    ///
    /// <para>The zip is unpacked and checked BEFORE the course is touched, so
    /// an unreadable backup can never leave an emptied section folder behind.
    /// Mirrors the mac's <c>CourseRestorer.restoreSection</c>.</para>
    /// </summary>
    public static void RestoreSection(int sectionNumber, BackupItem item, string coursesDirectory)
    {
        string courseDir = Path.Combine(coursesDirectory, item.CourseCode);
        if (!Directory.Exists(courseDir))
            throw new RestoreException($"{item.CourseCode} is not in Courses & Clubs, so there is nowhere to put Section {sectionNumber} back.");

        string staging = Path.Combine(Path.GetTempPath(), "restore-" + Guid.NewGuid());
        Directory.CreateDirectory(staging);
        try
        {
            string payload = Unpack(item.FilePath, item.CourseCode, staging);
            string folderName = "section" + sectionNumber;
            string backedUpSection = Path.Combine(payload, folderName);
            if (!Directory.Exists(backedUpSection))
                throw new RestoreException($"The copy of {item.CourseCode} does not hold a Section {sectionNumber}.");

            ReplaceContents(Path.Combine(courseDir, folderName), backedUpSection);
            RestorePerSectionKeys(sectionNumber, courseDir, payload);
            CourseArchiver.DiscardBuilds(coursesDirectory, item.CourseCode, sectionNumber);
        }
        finally
        {
            try { Directory.Delete(staging, recursive: true); } catch { }
        }
    }

    /// <summary>Out with the live folder's children, hidden ones included; in with the backup's.</summary>
    private static void ReplaceContents(string live, string backedUp)
    {
        Directory.CreateDirectory(live);
        foreach (string child in Directory.EnumerateFileSystemEntries(live))
            DeleteTree(child);
        foreach (string child in Directory.EnumerateFileSystemEntries(backedUp))
        {
            string target = Path.Combine(live, Path.GetFileName(child));
            if (Directory.Exists(child)) Directory.Move(child, target);
            else File.Move(child, target);
        }
    }

    /// <summary>
    /// Every shared page of the course gets this section's per-section keys
    /// back as the backup had them, and nothing else about it changes.
    /// </summary>
    private static void RestorePerSectionKeys(int sectionNumber, string courseDir, string payload)
    {
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
            string rewritten = SettingPerSectionKeys(sectionNumber, liveText, backupText);
            if (rewritten != liveText)
            {
                try { File.WriteAllText(page, rewritten); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
        }
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
    /// backup had them. The mac's <c>settingPerSectionKeys</c>, line for line:
    /// this section's lines are replaced by the backup's (or dropped when the
    /// backup had none); with none of its own left on the page, the restored
    /// lines go after the last per-section key so each section's lines stay
    /// together and in order; a page with no frontmatter at all gets a block
    /// of its own when the backup had keys for it.
    /// </summary>
    public static string SettingPerSectionKeys(int sectionNumber, string liveText, string backupText)
    {
        var restoredLines = new List<string>();
        if (FrontmatterBounds(backupText) is { } backupBlock)
        {
            var backupLines = backupText.Split('\n');
            for (int index = backupBlock.Open + 1; index < backupBlock.Close; index++)
            {
                string bare = backupLines[index].TrimEnd('\r');
                if (SectionAdder.PerSectionKeyNumber(bare) == sectionNumber) restoredLines.Add(bare);
            }
        }

        if (FrontmatterBounds(liveText) is not { } liveBlock)
        {
            if (restoredLines.Count == 0) return liveText;
            return "---\n" + string.Join("\n", restoredLines) + "\n---\n" + liveText;
        }

        var lines = liveText.Split('\n');
        int lastPerSectionIndex = -1;
        for (int index = liveBlock.Open + 1; index < liveBlock.Close; index++)
            if (SectionAdder.PerSectionKeyNumber(lines[index].TrimEnd('\r')) is not null) lastPerSectionIndex = index;

        var rebuilt = new List<string> { lines[liveBlock.Open] };
        bool placed = false;
        for (int index = liveBlock.Open + 1; index < liveBlock.Close; index++)
        {
            string bare = lines[index].TrimEnd('\r');
            if (SectionAdder.PerSectionKeyNumber(bare) == sectionNumber)
            {
                if (!placed) { rebuilt.AddRange(restoredLines); placed = true; }
                continue;
            }
            rebuilt.Add(lines[index]);
            if (index == lastPerSectionIndex && !placed) { rebuilt.AddRange(restoredLines); placed = true; }
        }
        if (!placed && restoredLines.Count > 0) rebuilt.AddRange(restoredLines);
        for (int index = liveBlock.Close; index < lines.Length; index++) rebuilt.Add(lines[index]);
        return string.Join("\n", rebuilt);
    }

    /// <summary>The line indexes of a page's opening and closing "---", or null when it has no frontmatter.</summary>
    private static (int Open, int Close)? FrontmatterBounds(string text)
    {
        var lines = text.Split('\n');
        if (lines.Length == 0 || lines[0].TrimEnd('\r') != "---") return null;
        for (int index = 1; index < lines.Length; index++)
            if (lines[index].TrimEnd('\r') == "---") return (0, index);
        return null;
    }

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
