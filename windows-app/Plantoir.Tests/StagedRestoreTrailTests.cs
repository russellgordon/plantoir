using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A one-section restore whose way back did not finish keeps what it set
/// aside where a teacher can open it, says so in the contract's sentence, and
/// writes <c>section restore stopped part way</c> (#873, by
/// <c>course-management.json</c> → <c>backups.restoreOneSection</c>, the mac's
/// #897 C). <b>SharedActivityState</b>: it redirects the activity trail.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class StagedRestoreTrailTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-staged-trail-" + Guid.NewGuid().ToString("N")[..12]);
    private readonly string _trail;

    private string CoursesDir => Path.Combine(_root, "courses");
    private string CourseDir => Path.Combine(CoursesDir, "ICS3U");
    private string Section => Path.Combine(CourseDir, "section1");

    public StagedRestoreTrailTests()
    {
        Directory.CreateDirectory(Path.Combine(Section, "All Classes"));
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), """{"course_code":"ICS3U","section_numbers":[1]}""");
        File.WriteAllText(Path.Combine(Section, "All Classes", "Unit 1, Day 1.md"), "day one");
        File.WriteAllText(Path.Combine(Section, "index.md"), "front page");
        _trail = Path.Combine(_root, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private sealed class WayBackFails : StagedRestore.Steps
    {
        private int _moves;
        public override void Move(string source, string target)
        {
            // Set aside both children, move the backup's first one in, then fail.
            if (++_moves == 4) throw new IOException("injected");
            base.Move(source, target);
        }
        public override void MoveBack(string source, string target) => throw new IOException("injected on the way back");
    }

    [Fact]
    public void AWayBackThatDidNotFinishKeepsTheFilesSaysSoAndLeavesALine()
    {
        var course = Workspace.DiscoverCourses(_root).First();
        var backup = BackupItem.From(CourseArchiver.BackUpCourse(course, CoursesDir, new BackupMaker.Assistant(1)), "ICS3U")!;
        File.WriteAllText(Path.Combine(Section, "All Classes", "Unit 1, Day 1.md"), "rewritten since");

        var stopped = Assert.Throws<CourseRestorer.SectionRestoreStoppedPartWay>(
            () => CourseRestorer.RestoreSection(1, backup, CoursesDir, new WayBackFails()));

        string kept = Assert.Single(Directory.GetDirectories(CourseArchiver.BackupsDirectory(CoursesDir, "ICS3U"), "Section 1 before a restore *"));
        Assert.Equal("rewritten since", File.ReadAllText(Path.Combine(kept, "All Classes", "Unit 1, Day 1.md")));
        string keptAt = Path.GetRelativePath(_root, kept);
        Assert.Equal(OneSectionRestoreWording.StoppedPartWay(1, keptAt), stopped.Message);
        // The backup list reads zip names only: the folder is not a backup.
        Assert.All(Workspace.FindBackups(_root), item => Assert.EndsWith(".zip", item.FilePath));
        // Nothing left for the next launch to act on.
        Assert.Empty(StagedRestore.RecoverLeftovers(CoursesDir, _ => false).Where(r => r.What != StagedRestore.Recovery.LeftInPlace));

        string line = Assert.Single(File.ReadAllLines(_trail), l => l.Contains("section restore stopped part way"));
        Assert.Contains(ActivityTrail.SectionRestoreStoppedPartWayLine(keptAt), line);
        Assert.Contains("ICS3U", line);
        Assert.DoesNotContain("rewritten since", File.ReadAllText(_trail));
    }

    [Fact]
    public void TheAssistantRouteSaysTheSentenceWithoutNothingWasPutBack()
    {
        Assert.True(typeof(AssistSectionRestore.Problem).IsAssignableFrom(typeof(AssistSectionRestore.StoppedPartWay)));
        string window = File.ReadAllText(Path.Combine(RepositoryRoot(), "windows-app", "Plantoir", "Views", "AssistWindow.xaml.cs"));
        int stopped = window.IndexOf("catch (AssistSectionRestore.StoppedPartWay", StringComparison.Ordinal);
        int prefixed = window.IndexOf("\"Nothing was put back: \"", StringComparison.Ordinal);
        Assert.True(stopped > 0 && stopped < prefixed);
    }

    [Fact]
    public void TheSentencesAreTheContracts()
    {
        var wording = ContractLoader.LoadJson("course-management.json")["backups"]!["restoreOneSection"]!["wording"]!;
        Assert.Equal(wording["stoppedPartWay"]!.GetValue<string>().Replace("{N}", "2").Replace("{KEPT}", @"courses\_backups\X\kept"),
                     OneSectionRestoreWording.StoppedPartWay(2, @"courses\_backups\X\kept"));
        Assert.Equal(wording["stoppedPartWayNothingToOpen"]!.GetValue<string>().Replace("{N}", "2"),
                     OneSectionRestoreWording.StoppedPartWayNothingToOpen(2));
    }

    private static string RepositoryRoot()
    {
        string? folder = AppContext.BaseDirectory;
        while (folder is not null && !Directory.Exists(Path.Combine(folder, "windows-app"))) folder = Path.GetDirectoryName(folder);
        return folder ?? throw new InvalidOperationException("repository root not found");
    }
}
