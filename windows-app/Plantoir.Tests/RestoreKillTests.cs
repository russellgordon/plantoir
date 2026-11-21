using System.Diagnostics;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// A one-section restore killed between staging and the end of the swap
/// (#911, invariant 2 of the brief): a SECOND PROCESS
/// (<c>windows-app/Plantoir.RestoreHarness</c>) runs the real
/// <see cref="CourseRestorer.RestoreSection"/>, announces each stopping point
/// on standard output and waits on standard input; the test waits for that
/// line (an event, never a sleep) and kills the whole process tree. After
/// the kill every original file of Section 2 is in the course or in the
/// staging folder with its bytes, the backup zip is untouched, and the next
/// open of the working folder (the same discovery calls
/// <c>WorkspaceViewModel.Reload</c> makes) deletes none of it.
/// </summary>
public sealed class RestoreKillTests : IDisposable
{
    private readonly SectionSwapFixture _fixture = new();

    public void Dispose() => _fixture.Dispose();

    /// <summary>The harness's build output: built with the tests through a ProjectReference that takes none of its output.</summary>
    private static string HarnessPath()
    {
        string here = Path.TrimEndingDirectorySeparator(AppContext.BaseDirectory);   // …\Plantoir.Tests\bin\<config>\net9.0
        string configuration = new DirectoryInfo(here).Parent!.Name;   // Debug or Release
        string windowsApp = Path.GetFullPath(Path.Combine(here, "..", "..", "..", ".."));
        string path = Path.Combine(windowsApp, "Plantoir.RestoreHarness", "bin", configuration, "net9.0", "Plantoir.RestoreHarness.dll");
        Assert.True(File.Exists(path), "the restore harness was not built at " + path);
        return path;
    }

    [Theory]
    [InlineData("staged")]
    [InlineData("setAside")]
    [InlineData("move:1")]
    [InlineData("move:3")]
    public void AKilledRestoreLeavesEveryOriginalInTheCourseOrTheStagingFolder(string point)
    {
        _fixture.Write("a.md", "a, backup");
        _fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day, backup");
        _fixture.Write(Path.Combine("zz notes", "n.md"), "n, backup");
        var backup = _fixture.BackUp();
        string zipBefore = SectionSwapFixture.Hash(backup.FilePath);
        _fixture.Write("a.md", "a, live");
        _fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day, live");
        _fixture.Write("made since.md", "made since, live");
        var originals = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(_fixture.Section2));
        var outsideTheSectionBefore = SnapshotOutsideTheSection();

        var start = new ProcessStartInfo("dotnet")
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        foreach (string argument in new[] { "exec", HarnessPath(), _fixture.CoursesDir, backup.FilePath, "ICS3U", "2", point, _fixture.TrailPath })
            start.ArgumentList.Add(argument);
        start.Environment["PLANTOIR_BUILD_ROOT"] = Path.Combine(_fixture.Folder, "builds");
        using var child = Process.Start(start)!;
        string? announced = child.StandardOutput.ReadLine();          // blocks until the child writes its line
        Assert.Equal("REACHED " + point, announced);
        child.Kill(entireProcessTree: true);
        child.WaitForExit();

        Assert.Equal(zipBefore, SectionSwapFixture.Hash(backup.FilePath));
        var missing = _fixture.OriginalsMissing(originals, _fixture.AsideFoldersInStaging());
        Assert.True(missing.Count == 0, $"killed at {point}: lost {string.Join(", ", missing)}");
        Assert.Equal(outsideTheSectionBefore, SnapshotOutsideTheSection());

        // The next open of the working folder, as WorkspaceViewModel.Reload makes it.
        Workspace.Classify(_fixture.Folder);
        Workspace.DiscoverCourses(_fixture.Folder);
        Workspace.FindBackups(_fixture.Folder);
        Workspace.FindArchivedItems(_fixture.Folder);
        Assert.Empty(_fixture.OriginalsMissing(originals, _fixture.AsideFoldersInStaging()));
        Assert.Equal(zipBefore, SectionSwapFixture.Hash(backup.FilePath));
    }

    /// <summary>The course outside Section 2 (other section, shared pages, settings), which a kill must not change.</summary>
    private SortedDictionary<string, string> SnapshotOutsideTheSection()
    {
        var all = SectionSwapFixture.Snapshot(_fixture.CourseDir);
        var outside = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var (path, hash) in all)
        {
            string bare = path.StartsWith("dir:", StringComparison.Ordinal) ? path[4..] : path;
            if (bare == "section2" || bare.StartsWith("section2" + Path.DirectorySeparatorChar, StringComparison.Ordinal)) continue;
            outside[path] = hash;
        }
        return outside;
    }
}
