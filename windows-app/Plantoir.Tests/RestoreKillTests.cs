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
    [InlineData("staged", "assistant")]
    [InlineData("setAside", "assistant")]
    [InlineData("move:1", "assistant")]
    [InlineData("move:3", "assistant")]
    [InlineData("staged", "menu")]
    [InlineData("setAside", "menu")]
    [InlineData("move:1", "menu")]
    [InlineData("move:5", "menu")]
    public void AKilledRestoreLeavesEveryOriginalInTheCourseOrTheStagingFolder(string point, string route)
    {
        // The menu's route (#911 step 3) also moves the section's files
        // outside its folder: two of them, one a folder, planted before the
        // backup and changed after, so move 5 is part way through those.
        bool menu = route == "menu";
        string[] outside = menu ? MenuOutsideFiles : Array.Empty<string>();
        foreach (string relative in outside) PlantOutside(relative, "backup");
        _fixture.Write("a.md", "a, backup");
        _fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day, backup");
        _fixture.Write(Path.Combine("zz notes", "n.md"), "n, backup");
        var backup = _fixture.BackUp();
        string zipBefore = SectionSwapFixture.Hash(backup.FilePath);
        _fixture.Write("a.md", "a, live");
        _fixture.Write(Path.Combine("All Classes", "Unit 1, Day 1.md"), "day, live");
        _fixture.Write("made since.md", "made since, live");
        foreach (string relative in outside) PlantOutside(relative, "live");
        var originals = SectionSwapFixture.FilesOf(SectionSwapFixture.Snapshot(_fixture.Section2));
        var outsideOriginals = OutsideOriginals(outside);
        var outsideTheSectionBefore = SnapshotOutsideTheSection(outside);

        var start = new ProcessStartInfo("dotnet")
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        foreach (string argument in new[] { "exec", HarnessPath(), _fixture.CoursesDir, backup.FilePath, "ICS3U", "2", point, _fixture.TrailPath, route })
            start.ArgumentList.Add(argument);
        start.Environment["PLANTOIR_BUILD_ROOT"] = Path.Combine(_fixture.Folder, "builds");
        using var child = Process.Start(start)!;
        string? announced = child.StandardOutput.ReadLine();          // blocks until the child writes its line
        Assert.Equal("REACHED " + point, announced);
        child.Kill(entireProcessTree: true);
        child.WaitForExit();

        Assert.Equal(zipBefore, SectionSwapFixture.Hash(backup.FilePath));
        var missing = _fixture.OriginalsMissing(originals, _fixture.AsideFoldersInStaging());
        Assert.True(missing.Count == 0, $"killed at {point} ({route}): lost {string.Join(", ", missing)}");
        Assert.Empty(OutsideOriginalsMissing(outsideOriginals));
        Assert.Equal(outsideTheSectionBefore, SnapshotOutsideTheSection(outside));

        // The next open of the working folder, as WorkspaceViewModel.Reload makes it.
        Workspace.Classify(_fixture.Folder);
        Workspace.DiscoverCourses(_fixture.Folder);
        Workspace.FindBackups(_fixture.Folder);
        Workspace.FindArchivedItems(_fixture.Folder);
        Assert.Empty(_fixture.OriginalsMissing(originals, _fixture.AsideFoldersInStaging()));
        Assert.Empty(OutsideOriginalsMissing(outsideOriginals));
        Assert.Equal(zipBefore, SectionSwapFixture.Hash(backup.FilePath));
    }

    /// <summary>Two of Section 2's files outside its folder that the menu's route takes from the backup: a file, and a folder (<c>…published-pages</c>).</summary>
    private static readonly string[] MenuOutsideFiles =
    {
        Path.Combine(".internal", "timetable", "section2.json"),
        Path.Combine(".publish_state", "section2.published-pages"),
    };

    private void PlantOutside(string relative, string state)
    {
        string path = Path.Combine(_fixture.CourseDir, relative);
        if (relative.EndsWith("published-pages", StringComparison.Ordinal))
        {
            Directory.CreateDirectory(path);
            File.WriteAllText(Path.Combine(path, "Unit 1, Day 1.md"), "published, " + state);
        }
        else
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "{\"state\": \"" + state + "\"}");
        }
    }

    /// <summary>Every file under the outside paths, by path inside the course and hash.</summary>
    private Dictionary<string, string> OutsideOriginals(string[] outside)
    {
        var found = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string relative in outside)
        {
            string path = Path.Combine(_fixture.CourseDir, relative);
            if (File.Exists(path)) found[relative] = SectionSwapFixture.Hash(path);
            else foreach (string file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
                found[Path.GetRelativePath(_fixture.CourseDir, file)] = SectionSwapFixture.Hash(file);
        }
        return found;
    }

    /// <summary>The outside originals that are neither in the course nor under <c>outside\</c> of a staging folder, with their bytes.</summary>
    private List<string> OutsideOriginalsMissing(Dictionary<string, string> originals)
    {
        var missing = new List<string>();
        foreach (var (relative, hash) in originals)
        {
            string live = Path.Combine(_fixture.CourseDir, relative);
            if (File.Exists(live) && SectionSwapFixture.Hash(live) == hash) continue;
            bool found = false;
            foreach (string aside in _fixture.AsideFoldersInStaging())
            {
                string kept = Path.Combine(aside, "outside", relative);
                if (File.Exists(kept) && SectionSwapFixture.Hash(kept) == hash) { found = true; break; }
            }
            if (!found) missing.Add(relative);
        }
        return missing;
    }

    /// <summary>The course outside Section 2 (other section, shared pages, settings), which a kill must not change.</summary>
    private SortedDictionary<string, string> SnapshotOutsideTheSection(string[] movedOutside)
    {
        var all = SectionSwapFixture.Snapshot(_fixture.CourseDir);
        var outside = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var (path, hash) in all)
        {
            string bare = path.StartsWith("dir:", StringComparison.Ordinal) ? path[4..] : path;
            if (bare == "section2" || bare.StartsWith("section2" + Path.DirectorySeparatorChar, StringComparison.Ordinal)) continue;
            if (movedOutside.Any(moved => bare == moved || bare.StartsWith(moved + Path.DirectorySeparatorChar, StringComparison.Ordinal))) continue;
            outside[path] = hash;
        }
        return outside;
    }
}
