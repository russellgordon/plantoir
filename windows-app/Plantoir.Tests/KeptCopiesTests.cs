using System.Diagnostics;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The kept copies of geogebra.org sketches beside a course's built sites
/// survive a restore from a backup and follow a rename (#805, the Windows half
/// of the mac's #789).
///
/// <para><b>The contract's cases.</b> <c>shared-rules.json</c> →
/// <c>buildOutputLocation.keptCopiesSurviveTheClear.cases</c> are written in
/// the mac's terms, a course folder's <c>.merged_output</c> link. Windows has
/// no link; what it has is the CLEAR, which is
/// <see cref="BuildOutputLocation.DiscardBuiltSitesFor"/>. So every case whose
/// course folder is not "a built site of its own" is walked here against that
/// clear, on the builds folder the case describes: the course folder's link
/// state does not exist on Windows and cannot change the answer. The cases
/// about moving a built site OUT of the working folder (a course folder with a
/// built site of its own) describe a move Windows never makes, and are
/// counted and left out by that one rule, so a new clear-shaped case is
/// walked without anybody editing this file.</para>
///
/// <para>Red on the old code (copy-aside, recorded in
/// documentation/12-windows-app.md): the restore and rename tests, because the
/// old restore discarded <c>builds\&lt;id&gt;\&lt;CODE&gt;</c> whole and the old
/// rename never touched it. The clear's own cases need the new function and
/// were proved by mutation instead.</para>
/// </summary>
[Collection(ProcessEnvironment.Name)]
public sealed class KeptCopiesTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-kept-" + Guid.NewGuid().ToString("N")[..12]);
    private readonly string? _buildRootBefore = Environment.GetEnvironmentVariable("PLANTOIR_BUILD_ROOT");

    private string CoursesDir => Path.Combine(_root, "courses");
    private string BuildsRoot => Path.Combine(_root, "builds");

    public KeptCopiesTests()
    {
        Directory.CreateDirectory(CoursesDir);
        Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", BuildsRoot);
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", _buildRootBefore);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["buildOutputLocation"]!["keptCopiesSurviveTheClear"]!;

    [Fact]
    public void TheFolderNameIsTheContracts()
    {
        Assert.Equal(Rule["folder"]!.GetValue<string>(), BuildOutputLocation.KeptCopiesFolderName);
    }

    private Course MakeCourse(string code)
    {
        string dir = Path.Combine(CoursesDir, code);
        Directory.CreateDirectory(Path.Combine(dir, "section1"));
        File.WriteAllText(Path.Combine(dir, "course_config.json"), $$"""{"course_code":"{{code}}","section_numbers":[1]}""");
        File.WriteAllText(Path.Combine(dir, "section1", "index.md"), "front page");
        return Workspace.DiscoverCourses(_root).First(c => c.Code == code);
    }

    private string Built(string code) => Path.Combine(BuildOutputLocation.ForSection(BuildsRoot, code, 1), "public", "index.html");
    private string Copy(string code, string key = "abc123") =>
        Path.Combine(BuildOutputLocation.ForCourse(BuildsRoot, code), BuildOutputLocation.KeptCopiesFolderName, key, "sketch.ggb");

    private void MakeBuildWithACopy(string code)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Built(code))!);
        File.WriteAllText(Built(code), "<html>built</html>");
        Directory.CreateDirectory(Path.GetDirectoryName(Copy(code))!);
        File.WriteAllBytes(Copy(code), new byte[] { 0x50, 0x4B, 7, 8 });
        Directory.CreateDirectory(BuildOutputLocation.WorkspaceForSection(BuildsRoot, code, 1));
    }

    // ---- a restore from a backup ---------------------------------------

    [Fact]
    public void RestoringOverTheCourseKeepsTheCopiesAndClearsTheBuiltSite()
    {
        var course = MakeCourse("ICS3U");
        var backup = BackupItem.From(CourseArchiver.BackUpCourse(course, CoursesDir), "ICS3U")!;
        MakeBuildWithACopy("ICS3U");

        CourseRestorer.RestoreBackup(backup, CoursesDir);

        Assert.False(File.Exists(Built("ICS3U")));
        Assert.Equal(new byte[] { 0x50, 0x4B, 7, 8 }, File.ReadAllBytes(Copy("ICS3U")));
        Assert.False(Directory.Exists(BuildOutputLocation.WorkspaceForCourse(BuildsRoot, "ICS3U")));
    }

    [Fact]
    public void RestoringACourseThatIsGoneKeepsTheCopiesToo()
    {
        var course = MakeCourse("ICS3U");
        var backup = BackupItem.From(CourseArchiver.BackUpCourse(course, CoursesDir), "ICS3U")!;
        MakeBuildWithACopy("ICS3U");
        CourseRestorer.DeleteTree(course.DirectoryPath);

        CourseRestorer.RestoreBackup(backup, CoursesDir);

        Assert.True(File.Exists(Path.Combine(CoursesDir, "ICS3U", "section1", "index.md")));
        Assert.False(File.Exists(Built("ICS3U")));
        Assert.True(File.Exists(Copy("ICS3U")));
    }

    [Fact]
    public void RestoringFromArchivedStillDiscardsEverything()
    {
        // Archiving already discarded the folder; restoring from Archived is unchanged.
        var course = MakeCourse("ICS3U");
        MakeBuildWithACopy("ICS3U");
        string archive = CourseArchiver.ArchiveAndRemoveCourse(course, CoursesDir);
        Assert.False(Directory.Exists(BuildOutputLocation.ForCourse(BuildsRoot, "ICS3U")));

        CourseRestorer.Restore(ArchivedItem.From(archive, "ICS3U")!, CoursesDir, Array.Empty<Course>());

        Assert.True(Directory.Exists(Path.Combine(CoursesDir, "ICS3U")));
        Assert.False(Directory.Exists(BuildOutputLocation.ForCourse(BuildsRoot, "ICS3U")));
    }

    // ---- a rename ---------------------------------------------------------

    [Fact]
    public void RenamingCarriesTheBuildsFolderToTheNewCode()
    {
        var course = MakeCourse("ICS3U");
        MakeBuildWithACopy("ICS3U");
        // Something left under the new code by a course of that name removed earlier.
        Directory.CreateDirectory(BuildOutputLocation.ForCourse(BuildsRoot, "ICS4U"));
        File.WriteAllText(Path.Combine(BuildOutputLocation.ForCourse(BuildsRoot, "ICS4U"), "stale.txt"), "old");

        CourseRenamer.Rename(course, "ICS4U", CoursesDir, new[] { "ICS3U" });

        Assert.True(File.Exists(Copy("ICS4U")));
        Assert.True(File.Exists(Built("ICS4U")));
        Assert.False(File.Exists(Path.Combine(BuildOutputLocation.ForCourse(BuildsRoot, "ICS4U"), "stale.txt")));
        Assert.False(Directory.Exists(BuildOutputLocation.ForCourse(BuildsRoot, "ICS3U")));
        Assert.False(Directory.Exists(BuildOutputLocation.WorkspaceForCourse(BuildsRoot, "ICS3U")));
    }

    [Fact]
    public void ABuildsFolderThatIsALinkIsRemovedAsALinkOnRenameAndWhatItPointsAtIsUntouched()
    {
        var course = MakeCourse("ICS3U");
        string outside = MakeOutsideFolderWithASentinel();
        Directory.CreateDirectory(BuildsRoot);
        MakeJunction(BuildOutputLocation.ForCourse(BuildsRoot, "ICS3U"), outside);

        CourseRenamer.Rename(course, "ICS4U", CoursesDir, new[] { "ICS3U" });

        Assert.False(Directory.Exists(BuildOutputLocation.ForCourse(BuildsRoot, "ICS3U")));
        Assert.False(Directory.Exists(BuildOutputLocation.ForCourse(BuildsRoot, "ICS4U")));
        AssertSentinelUntouched(outside);
    }

    // ---- the clear, by the contract's cases --------------------------------

    [Fact]
    public void ABuildsFolderThatIsItselfALinkIsNeverEnumerated()
    {
        // The plan review's P5 M1: only the link goes.
        string outside = MakeOutsideFolderWithASentinel();
        Directory.CreateDirectory(Path.Combine(outside, BuildOutputLocation.KeptCopiesFolderName));
        Directory.CreateDirectory(BuildsRoot);
        MakeJunction(BuildOutputLocation.ForCourse(BuildsRoot, "ICS3U"), outside);

        BuildOutputLocation.DiscardBuiltSitesFor(BuildsRoot, "ICS3U");

        Assert.False(Directory.Exists(BuildOutputLocation.ForCourse(BuildsRoot, "ICS3U")));
        AssertSentinelUntouched(outside);
        Assert.True(Directory.Exists(Path.Combine(outside, BuildOutputLocation.KeptCopiesFolderName)));
    }

    [Fact]
    public void EveryClearTheContractNamesKeepsTheCopiesItShould()
    {
        int walked = 0, leftOut = 0;
        foreach (var testCase in Rule["cases"]!.AsArray())
        {
            string name = testCase!["name"]!.GetValue<string>();
            if (testCase["courseFolder"]!.GetValue<string>() == "a built site of its own") { leftOut++; continue; }
            walked++;
            WalkOne(name, testCase);
        }
        Assert.True(walked >= 6, $"only {walked} clear-shaped cases walked");
        Assert.True(leftOut >= 1);
    }

    private void WalkOne(string name, JsonNode testCase)
    {
        string code = "C" + Guid.NewGuid().ToString("N")[..6].ToUpperInvariant();
        string course = BuildOutputLocation.ForCourse(BuildsRoot, code);
        string kept = Path.Combine(course, BuildOutputLocation.KeptCopiesFolderName);
        var buildsFolder = testCase["buildsFolder"]!;
        var expect = testCase["expect"]!;
        Directory.CreateDirectory(course);
        if (buildsFolder["builtSite"]!.GetValue<bool>())
        {
            Directory.CreateDirectory(Path.Combine(course, "section1", "public"));
            File.WriteAllText(Path.Combine(course, "section1", "public", "index.html"), "built");
        }
        foreach (var key in buildsFolder["keptCopies"]!.AsArray())
        {
            Directory.CreateDirectory(Path.Combine(kept, key!.GetValue<string>()));
            File.WriteAllText(Path.Combine(kept, key.GetValue<string>(), "sketch.ggb"), "copy " + key);
        }
        string? outside = null;
        switch (buildsFolder["keptCopiesFolderIs"]?.GetValue<string>())
        {
            case null: break;
            case "a file": File.WriteAllText(kept, "not a folder"); break;
            case "a link to a folder outside": outside = MakeOutsideFolderWithASentinel(); MakeJunction(kept, outside); break;
            case "a link to itself": MakeJunction(kept, kept, mustExist: false); break;
            case var other: Assert.Fail($"{name}: a kept-copies folder that is {other} is not known here"); break;
        }

        BuildOutputLocation.DiscardBuiltSitesFor(BuildsRoot, code);

        Assert.Equal("gone", expect["builtSite"]!.GetValue<string>());
        Assert.False(Directory.Exists(Path.Combine(course, "section1")), name);
        foreach (var (key, where) in expect["keptCopies"]!.AsObject())
        {
            Assert.Equal("beside the built sites", where!.GetValue<string>());
            Assert.Equal("copy " + key, File.ReadAllText(Path.Combine(kept, key, "sketch.ggb")));
        }
        var remaining = Directory.Exists(course) ? Directory.EnumerateFileSystemEntries(course).Select(Path.GetFileName).ToList() : new List<string?>();
        if (expect["onlyTheKeptCopiesRemain"]!.GetValue<bool>())
            Assert.Equal(new[] { BuildOutputLocation.KeptCopiesFolderName }, remaining);
        if (expect["nothingRemainsInTheBuildsFolder"]?.GetValue<bool>() == true)
            Assert.Empty(remaining);
        if (expect["theFolderOutsideIsUntouched"]?.GetValue<bool>() == true)
            AssertSentinelUntouched(outside!);
    }

    // ---- helpers -----------------------------------------------------------

    private string MakeOutsideFolderWithASentinel()
    {
        string outside = Path.Combine(_root, "outside-" + Guid.NewGuid().ToString("N")[..6]);
        Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside, "sentinel.txt"), "never touched");
        return outside;
    }

    private static void AssertSentinelUntouched(string outside) =>
        Assert.Equal("never touched", File.ReadAllText(Path.Combine(outside, "sentinel.txt")));

    /// <summary>A junction (no privilege needed, unlike a symbolic link). <paramref name="mustExist"/> false for one that points at itself.</summary>
    private static void MakeJunction(string link, string target, bool mustExist = true)
    {
        var start = new ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{target}\"")
        { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
        using var process = Process.Start(start)!;
        process.WaitForExit();
        Assert.NotEqual(0, (int)(File.GetAttributes(link) & FileAttributes.ReparsePoint));
        if (mustExist) Assert.True(Directory.Exists(link));
    }
}
