using System;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Where Windows keeps a section's built website, and the rule about when a
/// deploy has to build first.
///
/// <para>Every test hands <see cref="BuildOutputLocation"/> a TEMPORARY builds
/// root. Deriving it from the working folder would put every fixture into the
/// real <c>%LOCALAPPDATA%\Plantoir\builds</c> — the same mistake that once put
/// 263 lines about a fixture course into a teacher's real activity trail.</para>
/// </summary>
public class BuildOutputLocationTests : IDisposable
{
    private readonly string _root;
    private readonly string _buildsRoot;

    public BuildOutputLocationTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-builds-tests").FullName;
        _buildsRoot = Path.Combine(_root, "builds");
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    // ------------------------------------------------------------- the paths

    [Fact]
    public void TheFolderIdIsTheOneTheLauncherComputes()
    {
        // Not a second hash: BuildOutputLocation asks FolderContainers for the
        // identifier the container name has always used, which is exactly
        // preview.ps1's $WORKDIR_ID. Two derivations is how they come apart,
        // and CLAUDE.md warns about this one by name.
        string folder = _root;
        string id = FolderContainers.FolderIdentifier(folder);
        Assert.Equal(8, id.Length);
        Assert.Equal(id, id.ToLowerInvariant());
        Assert.Equal("teaching-quartz-" + id, FolderContainers.ContainerName(folder));
        Assert.EndsWith(id, BuildOutputLocation.BuildsRootFor(folder).TrimEnd(Path.DirectorySeparatorChar));
    }

    [Fact]
    public void ASectionsBuiltSiteSitsUnderTheCourseUnderTheRoot()
    {
        Assert.Equal(Path.Combine(_buildsRoot, "ADA1O"),
                     BuildOutputLocation.ForCourse(_buildsRoot, "ADA1O"));
        Assert.Equal(Path.Combine(_buildsRoot, "ADA1O", "section2"),
                     BuildOutputLocation.ForSection(_buildsRoot, "ADA1O", 2));
        Assert.Equal(Path.Combine(_buildsRoot, "ADA1O", "section2", "public", "index.html"),
                     BuildOutputLocation.BuiltIndexFor(_buildsRoot, "ADA1O", 2));
    }

    [Fact]
    public void TheBuildWORKSPACEIsSomewhereElseAgain()
    {
        // Easy to forget, and the half a preview actually serves from.
        Assert.Equal(Path.Combine(_buildsRoot, "work", "ADA1O"),
                     BuildOutputLocation.WorkspaceForCourse(_buildsRoot, "ADA1O"));
        Assert.Equal(Path.Combine(_buildsRoot, "work", "ADA1O", "section1"),
                     BuildOutputLocation.WorkspaceForSection(_buildsRoot, "ADA1O", 1));
    }

    // ---------------------------------------------------------- discarding

    private void MakeBuild(string code, int section, string contents = "<html>built</html>")
    {
        string publicDir = Path.Combine(BuildOutputLocation.ForSection(_buildsRoot, code, section), "public");
        Directory.CreateDirectory(publicDir);
        File.WriteAllText(Path.Combine(publicDir, "index.html"), contents);
        Directory.CreateDirectory(BuildOutputLocation.WorkspaceForSection(_buildsRoot, code, section));
    }

    [Fact]
    public void DiscardingACourseTakesItsBuiltSiteAndItsWorkspace()
    {
        MakeBuild("ADA1O", 1);
        MakeBuild("ADA1O", 2);
        BuildOutputLocation.DiscardBuildsFor(_buildsRoot, "ADA1O");
        Assert.False(Directory.Exists(BuildOutputLocation.ForCourse(_buildsRoot, "ADA1O")));
        Assert.False(Directory.Exists(BuildOutputLocation.WorkspaceForCourse(_buildsRoot, "ADA1O")));
    }

    [Fact]
    public void DiscardingOneSectionLeavesTheOthersAlone()
    {
        MakeBuild("ADA1O", 1);
        MakeBuild("ADA1O", 2);
        BuildOutputLocation.DiscardBuildsFor(_buildsRoot, "ADA1O", 1);
        Assert.False(Directory.Exists(BuildOutputLocation.ForSection(_buildsRoot, "ADA1O", 1)));
        Assert.False(Directory.Exists(BuildOutputLocation.WorkspaceForSection(_buildsRoot, "ADA1O", 1)));
        Assert.True(Directory.Exists(BuildOutputLocation.ForSection(_buildsRoot, "ADA1O", 2)));
    }

    [Fact]
    public void DiscardingAnotherCoursesBuildLeavesThisOne()
    {
        MakeBuild("ADA1O", 1);
        MakeBuild("ICS3U", 1);
        BuildOutputLocation.DiscardBuildsFor(_buildsRoot, "ICS3U");
        Assert.True(Directory.Exists(BuildOutputLocation.ForSection(_buildsRoot, "ADA1O", 1)));
    }

    [Fact]
    public void DiscardingWhatIsNotThereIsNotAnError()
    {
        BuildOutputLocation.DiscardBuildsFor(_buildsRoot, "NOPE1");
        BuildOutputLocation.DiscardBuildsFor(_buildsRoot, "NOPE1", 7);
    }

    // ------------------------------- the contract's freshness rules, wired

    private Course CourseWith(string code, string noteText, DateTime? noteWritten = null)
    {
        string courseDir = Path.Combine(_root, "courses", code);
        Directory.CreateDirectory(Path.Combine(courseDir, "section1"));
        string note = Path.Combine(courseDir, "section1", "lesson.md");
        File.WriteAllText(note, noteText);
        if (noteWritten is DateTime when) File.SetLastWriteTimeUtc(note, when);
        File.WriteAllText(Path.Combine(courseDir, "course_config.json"),
            "{\"course_code\":\"" + code + "\",\"section_numbers\":[1],\"num_sections\":1}");
        var config = CourseConfiguration.Load(Path.Combine(courseDir, "course_config.json"));
        return new Course(code, courseDir, config);
    }

    [Fact]
    public void TheContractsFiveFreshnessRulesAreAllCovered()
    {
        // These five were in app-rules.json -> buildFreshness and had NEVER
        // been run on Windows. Read from the contract so a rule added there
        // shows up here as a missing case rather than as silence.
        var rules = ContractLoader.LoadJson("app-rules.json")["buildFreshness"]!["rules"]!.AsArray();
        Assert.Equal(5, rules.Count);
        var whens = rules.Select(r => r!["when"]!.ToString()).ToList();
        Assert.Contains("nothing has been built yet", whens);
        Assert.Contains("the built site is older than the teacher's newest content", whens);
        Assert.Contains("the built site was made by a PREVIEW", whens);
        Assert.Contains("the built site is newer than the content and was not built by a preview", whens);
        Assert.Contains("the built index cannot be read", whens);
    }

    [Fact]
    public void NothingBuiltYetMeansRebuild()
    {
        var course = CourseWith("ADA1O", "# a lesson");
        Assert.True(BuildFreshness.NeedsRebuild(course, 1, _buildsRoot));
    }

    [Fact]
    public void ABuildOlderThanTheContentMeansRebuild()
    {
        var course = CourseWith("ADA1O", "# a lesson");
        MakeBuild("ADA1O", 1);
        File.SetLastWriteTimeUtc(BuildOutputLocation.BuiltIndexFor(_buildsRoot, "ADA1O", 1),
                                 DateTime.UtcNow.AddDays(-2));
        Assert.True(BuildFreshness.NeedsRebuild(course, 1, _buildsRoot));
    }

    [Fact]
    public void APreviewBuildIsNeverDeployFreshHoweverRecent()
    {
        // The one that is not obvious: serve mode bakes a live-reload client
        // into every page, and publishing that makes a student's browser ask
        // about access to other apps and services on this device.
        var course = CourseWith("ADA1O", "# a lesson", DateTime.UtcNow.AddDays(-2));
        MakeBuild("ADA1O", 1, "<html><script>new WebSocket('ws://localhost:9081')</script></html>");
        Assert.True(BuildFreshness.NeedsRebuild(course, 1, _buildsRoot));
    }

    [Fact]
    public void ABuildNewerThanTheContentAndNotAPreviewNeedsNoRebuild()
    {
        var course = CourseWith("ADA1O", "# a lesson", DateTime.UtcNow.AddDays(-2));
        MakeBuild("ADA1O", 1);
        Assert.False(BuildFreshness.NeedsRebuild(course, 1, _buildsRoot));
    }

    [Fact]
    public void ALeftoverInsideTheCourseFolderIsNoLongerConsulted()
    {
        // The bug this whole piece exists for. A course carried over from
        // before builds moved out has a stale .merged_output inside it; that
        // used to be what decided whether to rebuild, while what actually gets
        // published lives somewhere else entirely.
        var course = CourseWith("ADA1O", "# a lesson", DateTime.UtcNow.AddDays(-2));
        string leftover = Path.Combine(course.DirectoryPath, ".merged_output", "section1", "public");
        Directory.CreateDirectory(leftover);
        File.WriteAllText(Path.Combine(leftover, "index.html"), "<html>from months ago</html>");
        File.SetLastWriteTimeUtc(Path.Combine(leftover, "index.html"), DateTime.UtcNow.AddHours(1));

        // Nothing has been built where Windows actually builds, so: rebuild.
        Assert.True(BuildFreshness.NeedsRebuild(course, 1, _buildsRoot));
    }

    [Fact]
    public void ACourseCalledWorkCannotDeleteEveryCoursesWorkspace()
    {
        // builds\{id}\work holds EVERY course's build workspace, so a course code
        // of "work" makes ForCourse resolve to that shared directory. Deleting
        // it would pull the ground from under every other course's preview.
        // Windows filesystems are case-insensitive, so "WORK" is the same
        // collision. The layout clash is older than this file - the Python has
        // it too - but nothing DELETED by that path until now.
        MakeBuild("ADA1O", 1);
        Directory.CreateDirectory(Path.Combine(_buildsRoot, "work", "ICS3U", "section1"));

        BuildOutputLocation.DiscardBuildsFor(_buildsRoot, "work");
        BuildOutputLocation.DiscardBuildsFor(_buildsRoot, "WORK");
        BuildOutputLocation.DiscardBuildsFor(_buildsRoot, "Work", 1);

        Assert.True(Directory.Exists(Path.Combine(_buildsRoot, "work", "ICS3U", "section1")));
        Assert.True(Directory.Exists(BuildOutputLocation.WorkspaceForSection(_buildsRoot, "ADA1O", 1)));
    }
}
