using System.Security.Cryptography;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// A working folder for the one-section restore's swap tests (#911): a course
/// ICS3U with two sections, a backup made for Section 2 by the assistant, and
/// content judged by its bytes (SHA-256 of every file, with every folder's
/// name), never by a time, a size or a count.
/// </summary>
internal sealed class SectionSwapFixture : IDisposable
{
    public string Folder { get; } = Path.Combine(Path.GetTempPath(), "plantoir-swap-" + Guid.NewGuid().ToString("N")[..12]);
    public string CoursesDir => Path.Combine(Folder, "courses");
    public string CourseDir => Path.Combine(CoursesDir, "ICS3U");
    public string Section2 => Path.Combine(CourseDir, "section2");
    public string RestoringDir => Path.Combine(CoursesDir, ".internal", "restoring");
    public string TrailPath => Path.Combine(Folder, "trail", "activity.txt");

    public SectionSwapFixture()
    {
        Directory.CreateDirectory(Path.Combine(CourseDir, "section1", "All Classes"));
        Directory.CreateDirectory(Path.Combine(Section2, "All Classes"));
        Directory.CreateDirectory(Path.Combine(CourseDir, "Notes"));
        Directory.CreateDirectory(Path.GetDirectoryName(TrailPath)!);
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"),
            """
            {
              "course_code": "ICS3U",
              "course_name": "Computer Science",
              "num_sections": 2,
              "shared_folders": ["Notes"],
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1, 2],
              "unit_word": "Unit"
            }
            """);
        File.WriteAllText(Path.Combine(CourseDir, "section1", "All Classes", "Unit 1, Day 1.md"), "---\ntitle: Unit 1, Day 1\n---\nOne.\n");
        File.WriteAllText(Path.Combine(CourseDir, "Notes", "Syllabus.md"), "---\ntitle: Syllabus\npublishForSection2: false\n---\nThe syllabus.\n");
    }

    public void Dispose()
    {
        try { Directory.Delete(Folder, recursive: true); } catch { }
    }

    /// <summary>Writes a file under Section 2, making its folders.</summary>
    public void Write(string relativeInSection, string text)
    {
        string path = Path.Combine(Section2, relativeInSection);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    /// <summary>A backup of the whole course, made by the assistant for Section 2.</summary>
    public BackupItem BackUp() => BackUp(new BackupMaker.Assistant(2));

    /// <summary>A backup of the whole course, made by <paramref name="maker"/>.</summary>
    public BackupItem BackUp(BackupMaker maker)
    {
        string path = CourseArchiver.BackUpCourse(Course(), CoursesDir, maker);
        return BackupItem.From(path, "ICS3U")!;
    }

    /// <summary>The course as the window loads it now.</summary>
    public Course Course() => Workspace.DiscoverCourses(Folder).First(found => found.Code == "ICS3U");

    /// <summary>Every file under <paramref name="root"/> by relative path and SHA-256, and every folder as "dir:" + its path.</summary>
    public static SortedDictionary<string, string> Snapshot(string root)
    {
        var found = new SortedDictionary<string, string>(StringComparer.Ordinal);
        if (!Directory.Exists(root)) return found;
        var options = new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = 0 };
        foreach (string folder in Directory.EnumerateDirectories(root, "*", options))
            found["dir:" + Path.GetRelativePath(root, folder)] = "";
        foreach (string file in Directory.EnumerateFiles(root, "*", options))
            found[Path.GetRelativePath(root, file)] = Hash(file);
        return found;
    }

    public static string Hash(string file)
    {
        using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    /// <summary>Only the files of a snapshot (no folders).</summary>
    public static Dictionary<string, string> FilesOf(SortedDictionary<string, string> snapshot)
    {
        var files = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (path, hash) in snapshot)
            if (!path.StartsWith("dir:", StringComparison.Ordinal)) files[path] = hash;
        return files;
    }

    /// <summary>
    /// Every original file of Section 2 (by path inside the section and hash)
    /// is either in the section with the same bytes, or in one of the
    /// <paramref name="keptFolders"/> under <c>section2\</c> with the same bytes.
    /// Returns the originals that are in neither, for the assertion's message.
    /// </summary>
    public List<string> OriginalsMissing(Dictionary<string, string> originals, IEnumerable<string> keptFolders)
    {
        var missing = new List<string>();
        var kept = keptFolders.ToList();
        foreach (var (relative, hash) in originals)
        {
            string live = Path.Combine(Section2, relative);
            if (File.Exists(live) && Hash(live) == hash) continue;
            bool found = false;
            foreach (string folder in kept)
            {
                string aside = Path.Combine(folder, "section2", relative);
                if (File.Exists(aside) && Hash(aside) == hash) { found = true; break; }
            }
            if (!found) missing.Add(relative);
        }
        return missing;
    }

    /// <summary>Every <c>as-it-was</c> folder left under <c>courses\.internal\restoring</c>.</summary>
    public IEnumerable<string> AsideFoldersInStaging() =>
        Directory.Exists(RestoringDir)
            ? Directory.EnumerateDirectories(RestoringDir).Select(id => Path.Combine(id, "as-it-was")).Where(Directory.Exists).ToList()
            : new List<string>();

    /// <summary>Every "Section 2 before a restore …" folder beside the course's backups.</summary>
    public IEnumerable<string> KeptFoldersInBackups() =>
        Directory.Exists(Path.Combine(CoursesDir, "_backups", "ICS3U"))
            ? Directory.EnumerateDirectories(Path.Combine(CoursesDir, "_backups", "ICS3U"), "Section 2 before a restore *").ToList()
            : new List<string>();

    public string Trail() => File.Exists(TrailPath) ? File.ReadAllText(TrailPath) : "";

    /// <summary>
    /// What a sweep case was told is what is on disk (the review of steps 1
    /// and 2, LOW 4): a failure whose way back finished says
    /// <c>leftAsItWas</c> and writes no stopped line; one whose way back did
    /// not finish says <c>stoppedPartWay</c> naming the kept folder (or
    /// <c>stoppedPartWayNothingToOpen</c> when nothing in it but dot-named
    /// files), with the archive sentence on the menu's route, and writes
    /// <c>section restore stopped part way</c> naming that folder.
    /// </summary>
    public void AssertToldTruly(Exception? error, bool wayBackFailed, bool archived, string which)
    {
        Assert.True(error is CourseRestorer.RestoreException, which + ": no refusal was said");
        if (!wayBackFailed)
        {
            Assert.False(error is CourseRestorer.SectionRestoreStoppedPartWay, which + ": said stopped part way");
            Assert.StartsWith(OneSectionRestoreWording.LeftAsItWas(2, ""), error!.Message);
            Assert.DoesNotContain("section restore stopped part way", Trail());
            return;
        }
        Assert.True(error is CourseRestorer.SectionRestoreStoppedPartWay, which + ": said " + error!.Message);
        string kept = Assert.Single(KeptFoldersInBackups());
        string keptAt = Path.GetRelativePath(Folder, kept);
        bool somethingToOpen = false;
        foreach (string file in Directory.EnumerateFiles(kept, "*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = 0 }))
        {
            bool hidden = false;
            foreach (string part in Path.GetRelativePath(kept, file).Split(Path.DirectorySeparatorChar))
                if (part.StartsWith('.')) hidden = true;
            if (!hidden) somethingToOpen = true;
        }
        string said = somethingToOpen ? OneSectionRestoreWording.StoppedPartWay(2, keptAt) : OneSectionRestoreWording.StoppedPartWayNothingToOpen(2);
        if (archived) said += " " + OneSectionRestoreWording.StoppedPartWayArchived;
        Assert.Equal(said, error.Message);
        Assert.Contains(Plantoir.Core.Scripting.ActivityTrail.SectionRestoreStoppedPartWayLine(keptAt), Trail());
    }
}
