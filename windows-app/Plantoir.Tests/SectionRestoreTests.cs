using System.Text;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// The way back for a whole assistant conversation: one section, put back to
/// how it was when the chat started, from the copy the first change saved.
///
/// <para>The tests that matter are the ones about what is NOT touched — the
/// other section, and the shared pages' words — and the one about the copy
/// still being there after six changes, which is the hazard that made this a
/// two-part change rather than a button.</para>
/// </summary>
public sealed class SectionRestoreTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-restore-" + Guid.NewGuid().ToString("N"));
    private readonly FakeLauncher _launcher = new();

    private string CoursesDir => Path.Combine(_folder, "courses");
    private string CourseDir => Path.Combine(CoursesDir, "ICS3U");

    public SectionRestoreTests()
    {
        Directory.CreateDirectory(Path.Combine(CourseDir, "section1", "All Classes"));
        Directory.CreateDirectory(Path.Combine(CourseDir, "section2", "All Classes"));
        Directory.CreateDirectory(Path.Combine(CourseDir, "Notes"));
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
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
        Page(1, "Unit 1, Day 1", "---\ntitle: Unit 1, Day 1\ncreated: 2026-09-08\npublish: true\n---\nOriginal one.\n");
        Page(2, "Unit 1, Day 1", "---\ntitle: Unit 1, Day 1\ncreated: 2026-09-08\npublish: true\n---\nOriginal two.\n");
        File.WriteAllText(Shared,
            "---\ntitle: Syllabus\npublishForSection1: false\npublishForSection2: false\n---\nThe syllabus.\n");
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string PagePath(int section, string title) =>
        Path.Combine(CourseDir, "section" + section, "All Classes", title + ".md");
    private void Page(int section, string title, string text) => File.WriteAllText(PagePath(section, title), text);
    private string Shared => Path.Combine(CourseDir, "Notes", "Syllabus.md");

    private Course Course() => new AssistWorkspace(_folder, _launcher).Course("ICS3U");

    private BackupItem BackUp()
    {
        string path = CourseArchiver.BackUpCourse(Course(), CoursesDir, new BackupMaker.Assistant(1));
        return BackupItem.From(path, "ICS3U")!;
    }

    // ---- The promise in the third paragraph ---------------------------------

    [Fact]
    public void TheSectionGoesBackWhollyAndTheOtherSectionIsNotTouched()
    {
        var copy = BackUp();

        // The conversation, and the teacher in Obsidian, change section 1.
        Page(1, "Unit 1, Day 1", "---\ntitle: Unit 1, Day 1\ncreated: 2026-09-08\npublish: false\n---\nRewritten.\n");
        Page(1, "Unit 1, Day 2", "---\ntitle: Unit 1, Day 2\n---\nAdded since.\n");
        File.WriteAllText(Path.Combine(CourseDir, "section1", ".hidden"), "x");
        // Meanwhile section 2 is being marked.
        Page(2, "Unit 1, Day 1", "---\ntitle: Unit 1, Day 1\ncreated: 2026-09-08\npublish: true\n---\nMarked.\n");

        CourseRestorer.RestoreSection(1, copy, CoursesDir);

        Assert.EndsWith("Original one.\n", File.ReadAllText(PagePath(1, "Unit 1, Day 1")));
        Assert.False(File.Exists(PagePath(1, "Unit 1, Day 2")), "a page added since the conversation started is gone");
        Assert.False(File.Exists(Path.Combine(CourseDir, "section1", ".hidden")), "hidden files included");
        Assert.EndsWith("Marked.\n", File.ReadAllText(PagePath(2, "Unit 1, Day 1")));
    }

    [Fact]
    public void OnlyThisSectionsPerSectionKeysOnSharedPagesGoBack()
    {
        var copy = BackUp();
        File.WriteAllText(Shared,
            "---\ntitle: Syllabus (edited)\npublishForSection1: true\npublishForSection2: true\n---\nThe syllabus, edited.\n");

        CourseRestorer.RestoreSection(1, copy, CoursesDir);

        string after = File.ReadAllText(Shared);
        Assert.Contains("publishForSection1: false", after);
        Assert.Contains("publishForSection2: true", after);      // section 2's own publishing stays
        Assert.Contains("title: Syllabus (edited)", after);      // and so do the page's words
        Assert.EndsWith("The syllabus, edited.\n", after);
    }

    [Fact]
    public void AnUnreadableCopyLeavesTheSectionExactlyAsItIs()
    {
        var copy = BackUp();
        File.WriteAllText(copy.FilePath, "not a zip");
        Page(1, "Unit 1, Day 1", "---\ntitle: Unit 1, Day 1\n---\nChanged.\n");

        Assert.Throws<CourseRestorer.RestoreException>(() => CourseRestorer.RestoreSection(1, copy, CoursesDir));
        Assert.EndsWith("Changed.\n", File.ReadAllText(PagePath(1, "Unit 1, Day 1")));
    }

    // ---- Per-section keys, line by line -------------------------------------

    [Theory]
    [InlineData("---\na: 1\npublishForSection1: true\n---\nbody", "---\npublishForSection1: false\n---\n",
                "---\na: 1\npublishForSection1: false\n---\nbody")]                       // replaced
    [InlineData("---\na: 1\npublishForSection1: true\n---\nbody", "---\na: 1\n---\n",
                "---\na: 1\n---\nbody")]                                                  // a key the conversation added goes
    [InlineData("---\ncreatedSection2: 2026-09-08\n---\nbody", "---\npublishForSection1: false\n---\n",
                "---\ncreatedSection2: 2026-09-08\npublishForSection1: false\n---\nbody")] // placed after the last per-section key
    [InlineData("body only", "---\npublishForSection1: false\n---\n",
                "---\npublishForSection1: false\n---\nbody only")]                         // a page with no block gets one
    [InlineData("body only", "---\ntitle: x\n---\n", "body only")]                        // nothing to restore, nothing touched
    public void SettingPerSectionKeysMatchesTheMacLineForLine(string live, string backup, string expected)
    {
        Assert.Equal(expected, CourseRestorer.SettingPerSectionKeys(1, live, backup));
    }

    // ---- The copy is saved once, and survives six changes -------------------

    [Fact]
    public async Task OneConversationSavesOneCopyHoweverManyChangesItMakes()
    {
        string original = File.ReadAllText(PagePath(1, "Unit 1, Day 1"));
        var workspace = new AssistWorkspace(_folder, _launcher, "ICS3U", new UndoHistory());
        for (int change = 0; change < 7; change++)   // odd, so it ends unpublished; more than MostBackupsKept
        {
            bool draft = change % 2 == 0;        // starts published, so the first change unpublishes
            var plan = workspace.PlanPublish("ICS3U", 1, new[] { "Unit 1, Day 1" }, includeLinked: false, draft: draft);
            var result = await workspace.Apply(plan, preview: false);
            Assert.True(result.Succeeded, result.Message);
        }

        string backups = CourseArchiver.BackupsDirectory(CoursesDir, "ICS3U");
        var saved = Directory.GetFiles(backups, "*.zip");
        Assert.Single(saved);
        Assert.Equal(saved[0], workspace.ConversationBackupPath);
        Assert.Contains("assistant-section1", Path.GetFileName(saved[0]));

        // And the copy is from BEFORE the first change: restoring it gives the
        // page back byte for byte, whatever seven edits did to its frontmatter.
        Assert.NotEqual(original, File.ReadAllText(PagePath(1, "Unit 1, Day 1")));
        AssistSectionRestore.Restore(workspace.ConversationBackupPath, "ICS3U", 1, CoursesDir);
        Assert.Equal(original, File.ReadAllText(PagePath(1, "Unit 1, Day 1")));
    }

    [Fact]
    public void TheRefusalsSayWhy()
    {
        var nothing = Assert.Throws<AssistSectionRestore.Problem>(
            () => AssistSectionRestore.Restore(null, "ICS3U", 1, CoursesDir));
        Assert.Equal(AssistSectionRestore.NothingToRestore, nothing.Message);

        var noFolder = Assert.Throws<AssistSectionRestore.Problem>(
            () => AssistSectionRestore.Restore(Path.Combine(_folder, "x.zip"), "ICS3U", 1, null));
        Assert.Equal(AssistSectionRestore.NoWorkingFolder, noFolder.Message);

        var unreadable = Assert.Throws<AssistSectionRestore.Problem>(
            () => AssistSectionRestore.Restore(Path.Combine(_folder, "gone.zip"), "ICS3U", 1, CoursesDir));
        Assert.Equal(AssistSectionRestore.UnreadableBackup("gone.zip"), unreadable.Message);
    }

    // ---- Rule 1 -------------------------------------------------------------

    [Fact]
    public void TheSentencesNameNoMachinery()
    {
        var said = new StringBuilder()
            .Append(AssistSectionRestore.BannerTitle(1)).Append(AssistSectionRestore.BannerDetail())
            .Append(AssistSectionRestore.ConfirmationTitle("ICS3U", 1))
            .Append(AssistSectionRestore.ConfirmationMessage("ICS3U", 1))
            .Append(AssistSectionRestore.DoneMessage("ICS3U", 1))
            .Append(AssistSectionRestore.NothingToRestore).Append(AssistSectionRestore.NoWorkingFolder)
            .ToString().ToLowerInvariant();
        foreach (string word in new[] { "toolchain", "script", "docker", "container", "zip", "backup file", "process" })
            Assert.DoesNotContain(word, said);
    }
}
