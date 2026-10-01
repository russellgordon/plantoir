using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Keep a Copy for Reference… on disk (#241, mac #206 branch A; #287's
/// failure line; #298's add-ons). Mirrors the mac's ReferenceCopierTests by
/// name where one exists. Everything happens under a temp folder, and every
/// lock is removed in <see cref="Dispose"/>.
/// </summary>
[Collection(ReferenceDiskCollection.Name)]
public class ReferenceCopierTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-keep-a-copy").FullName;

    public ReferenceCopierTests() => ReferenceStaging.ForgetEveryClaimForTesting();

    public void Dispose()
    {
        ReferenceStaging.ForgetEveryClaimForTesting();
        ReferenceFixtures.Remove(_root);
    }

    private string Courses => Path.Combine(_root, "courses");

    private Course LiveCourse(string code = "ICS3U")
    {
        string folder = Path.Combine(Courses, code);
        Directory.CreateDirectory(Path.Combine(folder, "Concepts"));
        Directory.CreateDirectory(Path.Combine(folder, "section1"));
        Directory.CreateDirectory(Path.Combine(folder, ".netlify_sites"));
        Directory.CreateDirectory(Path.Combine(folder, ".obsidian"));
        File.WriteAllText(Path.Combine(folder, "course_config.json"), JObject.Parse("""
            {"course_code":"CODE","course_name":"Computer Science","section_numbers":[1,2],"num_sections":2,
             "deploy_target":"netlify","custom_domains":{"sections":{"section1":{"netlify":"cs.example.org"}}}}
            """.Replace("CODE", code)).ToString());
        File.WriteAllText(Path.Combine(folder, "course_config.backup.json"), "{}");
        File.WriteAllText(Path.Combine(folder, "Concepts", "Loops.md"), "---\npublishForSection1: true\n---\n# Loops\n");
        File.WriteAllText(Path.Combine(folder, "section1", "index.md"), "# Section 1\n");
        File.WriteAllText(Path.Combine(folder, ".netlify_sites", "section1.json"), """{"site_id":"abc"}""");
        File.WriteAllText(Path.Combine(folder, ".obsidian", "app.json"), """{"showLineNumber": true}""");
        return new Course(code, folder, CourseConfiguration.Load(Path.Combine(folder, "course_config.json")));
    }

    [Fact]
    public void TheCopyIsAFrozenReferenceCourseAndTheLiveOneIsUntouched()
    {
        var live = LiveCourse();
        var before = ReferenceFixtures.Manifest(live.DirectoryPath);
        long mark = ReferenceFixtures.TrailMark();

        var made = ReferenceCopier.KeepACopy(live, "ICS3U-2025", 2025, Courses);

        Assert.Equal(new ReferenceCopier.Made("ICS3U-2025", "ICS3U", 2025, 2), made);
        Assert.Equal(before, ReferenceFixtures.Manifest(live.DirectoryPath));
        string copy = Path.Combine(Courses, "ICS3U-2025");
        var config = CourseConfiguration.Load(Path.Combine(copy, "course_config.json"));
        Assert.True(config.KeptForReference);
        Assert.Equal("ICS3U", config.CourseCode);
        Assert.Equal("local_folder", config.DeployTarget);
        Assert.Null(config.Values["custom_domains"]);
        Assert.False(File.Exists(Path.Combine(copy, ".netlify_sites", "section1.json")));
        Assert.Single(Directory.GetFiles(Path.Combine(copy, ".netlify_sites"), "section1.previous-*.json"));
        Assert.False(File.Exists(Path.Combine(copy, "course_config.backup.json")));
        Assert.True(ReferenceLock.IsLocked(Path.Combine(copy, "Concepts", "Loops.md")));
        Assert.False(ReferenceLock.IsLocked(Path.Combine(copy, "course_config.json")));
        var app = JObject.Parse(File.ReadAllText(Path.Combine(copy, ".obsidian", "app.json")));
        Assert.Equal("preview", (string?)app["defaultViewMode"]);
        Assert.True((bool)app["showLineNumber"]!);
        Assert.False(Directory.Exists(Path.Combine(Courses, ReferenceStaging.StagingName("ICS3U-2025"))));

        var trail = ReferenceFixtures.TrailSince(mark);
        Assert.Contains(trail, line => line.EndsWith("kept a copy of ICS3U for reference as ICS3U-2025 — shown as ICS3U, 2025–26, 2 sections"));
        Assert.DoesNotContain(trail, line => line.Contains("could not keep a copy"));
    }

    [Fact]
    public void AFolderNameAlreadyTakenIsRefusedBeforeAnythingIsWritten()
    {
        var live = LiveCourse();
        Directory.CreateDirectory(Path.Combine(Courses, "ICS3U-2025"));
        long mark = ReferenceFixtures.TrailMark();
        var refused = Assert.Throws<ReferenceCopier.NotMade>(() => ReferenceCopier.KeepACopy(live, "ICS3U-2025", 2025, Courses));
        Assert.Equal(ReferenceCourse.FolderAlreadyThere("ICS3U-2025"), refused.Message);
        Assert.Empty(Directory.GetFileSystemEntries(Path.Combine(Courses, "ICS3U-2025")));
        Assert.False(Directory.Exists(Path.Combine(Courses, ReferenceStaging.StagingName("ICS3U-2025"))));
        var line = Assert.Single(ReferenceFixtures.TrailSince(mark), l => l.Contains("could not keep a copy"));
        Assert.EndsWith("could not keep a copy of ICS3U for reference as ICS3U-2025 — " + refused.Message, line);
    }

    /// <summary>
    /// A copy that fails part way leaves NOTHING behind — not a staging folder,
    /// not a lease — and writes the failure line once, with the full prefix.
    /// The failure here is a page another program holds open exclusively.
    /// </summary>
    [Fact]
    public void AFailedCopyLeavesNothingBehind()
    {
        var live = LiveCourse();
        string held = Path.Combine(live.DirectoryPath, "Concepts", "Held open.md");
        File.WriteAllText(held, "x");
        long mark = ReferenceFixtures.TrailMark();
        using (new FileStream(held, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            Assert.Throws<ReferenceCopier.NotMade>(() => ReferenceCopier.KeepACopy(live, "ICS3U-2025", 2025, Courses));
        }
        Assert.False(Directory.Exists(Path.Combine(Courses, "ICS3U-2025")));
        Assert.False(Directory.Exists(Path.Combine(Courses, ReferenceStaging.StagingName("ICS3U-2025"))));
        Assert.Empty(Directory.Exists(ReferenceStaging.ActivityDirectory(Courses))
            ? Directory.GetFiles(ReferenceStaging.ActivityDirectory(Courses), "*.lease") : Array.Empty<string>());
        var failures = ReferenceFixtures.TrailSince(mark).Where(l => l.Contains("could not keep a copy")).ToList();
        var line = Assert.Single(failures);
        Assert.Contains("could not keep a copy of ICS3U for reference as ICS3U-2025 — The copy could not be made: ", line);
        Assert.DoesNotContain(ReferenceFixtures.TrailSince(mark), l => l.Contains("kept a copy of"));
    }

    [Fact]
    public void KeepACopyLeavesAnotherWindowsCopyAlone()
    {
        var live = LiveCourse();
        Directory.CreateDirectory(Path.Combine(Courses, ReferenceStaging.StagingName("ICS3U-2025")));
        File.WriteAllText(Path.Combine(Courses, ReferenceStaging.StagingName("ICS3U-2025"), "half.md"), "being made");
        ReferenceStaging.ClaimInThisAppForTesting(Courses, "ICS3U-2025");
        var refused = Assert.Throws<ReferenceCopier.NotMade>(() => ReferenceCopier.KeepACopy(live, "ICS3U-2025", 2025, Courses));
        Assert.Equal(ReferenceCourse.CopyAlreadyBeingMade("ICS3U-2025"), refused.Message);
        Assert.True(File.Exists(Path.Combine(Courses, ReferenceStaging.StagingName("ICS3U-2025"), "half.md")));
    }

    [Fact]
    public void ACopyOfACopyOfAReferenceCourseArrivesClearedThenLocked()
    {
        // Keep a Copy is never OFFERED on a reference course; this is the
        // import's shape (a source that is itself locked and read-only): the
        // copy must be cleared before its markers can be renamed.
        var live = LiveCourse();
        File.SetAttributes(Path.Combine(live.DirectoryPath, ".netlify_sites", "section1.json"), FileAttributes.ReadOnly);
        ReferenceLock.Lock(live.DirectoryPath);
        try
        {
            var made = ReferenceCopier.KeepACopy(live, "ICS3U-2024", 2024, Courses);
            Assert.Equal("ICS3U-2024", made.FolderName);
            Assert.Single(Directory.GetFiles(Path.Combine(Courses, "ICS3U-2024", ".netlify_sites"), "section1.previous-*.json"));
        }
        finally { ReferenceLock.Clear(live.DirectoryPath); }
    }

    /// <summary><c>referenceCourses.obsidianAddOns.cases</c>, through Keep a Copy (the import runs them too).</summary>
    [Fact]
    public void EveryAddOnCaseThroughKeepACopy()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!["obsidianAddOns"]!["cases"]!.AsArray();
        int ran = 0;
        foreach (var c in cases)
        {
            string caseRoot = Path.Combine(_root, $"case{ran}");
            ReferenceFixtures.Build(caseRoot, c!["tree"]!.AsArray());
            var before = ReferenceFixtures.Manifest(caseRoot);
            string courseDir = Path.Combine(caseRoot, c["course"]!.ToString().Replace('/', '\\'));
            var course = new Course(Path.GetFileName(courseDir), courseDir, CourseConfiguration.Load(Path.Combine(courseDir, "course_config.json")));
            string into = Path.Combine(_root, $"into{ran}", "courses");
            Directory.CreateDirectory(into);
            var found = ObsidianAddOns.FoundIn(courseDir);
            var made = ReferenceCopier.KeepACopy(course, course.Code + "-REF", null, into);
            AddOnCaseChecks.Assert(c, Path.Combine(into, made.FolderName), courseDir, found);
            Xunit.Assert.Equal(before, ReferenceFixtures.Manifest(caseRoot));
            ran++;
        }
        Xunit.Assert.True(ran >= 9, $"only {ran} add-on cases ran");
    }

    [Fact]
    public void TheSnapshotAndAddOnSentencesAreSaidOnlyWhenTrue()
    {
        var live = LiveCourse();
        Assert.True(ObsidianAddOns.FoundIn(live.DirectoryPath).IsEmpty);
        Directory.CreateDirectory(Path.Combine(live.DirectoryPath, ".obsidian", "plugins", "digitalgarden"));
        var found = ObsidianAddOns.FoundIn(live.DirectoryPath);
        Assert.False(found.IsEmpty);
        Assert.Equal("; 1 Obsidian add-on left behind (digitalgarden)", ObsidianAddOns.TrailClause(found));
    }
}

/// <summary>The checks every add-on case makes of a made course, whichever route made it.</summary>
internal static class AddOnCaseChecks
{
    public static void Assert(JsonNode c, string made, string source, ObsidianAddOns.Found found)
    {
        string name = c["name"]!.ToString();
        foreach (var absent in c["expectAbsent"]!.AsArray())
        {
            string path = Path.Combine(made, absent!.ToString().Replace('/', '\\'));
            Xunit.Assert.False(File.Exists(path) || Directory.Exists(path), $"{name}: {absent} came across");
        }
        foreach (var same in c["expectUnchanged"]!.AsArray())
        {
            string relative = same!.ToString().Replace('/', '\\');
            Xunit.Assert.True(File.Exists(Path.Combine(made, relative)), $"{name}: {same} did not come across");
            Xunit.Assert.Equal(File.ReadAllBytes(Path.Combine(source, relative)), File.ReadAllBytes(Path.Combine(made, relative)));
        }
        foreach (var notALink in c["expectNotALink"]?.AsArray() ?? new JsonArray())
        {
            string path = Path.Combine(made, notALink!.ToString().Replace('/', '\\'));
            Xunit.Assert.False(Directory.Exists(path) && new DirectoryInfo(path).Attributes.HasFlag(FileAttributes.ReparsePoint), $"{name}: {notALink} is a link");
        }
        var expected = c["expectFound"]!;
        Xunit.Assert.Equal(expected["addOnNames"]!.AsArray().Select(n => n!.ToString()).ToList(), found.AddOnNames.ToList());
        Xunit.Assert.Equal(expected["addOnsFolderIsALink"]!.GetValue<bool>(), found.AddOnsFolderIsALink);
        Xunit.Assert.Equal(expected["settingsFolderIsALink"]!.GetValue<bool>(), found.SettingsFolderIsALink);
        Xunit.Assert.Equal(expected["publishSiteIsSet"]!.GetValue<bool>(), found.PublishSiteIsSet);
        Xunit.Assert.True(c["expectSaid"]!.GetValue<bool>() == !found.IsEmpty, $"{name}: said is {!found.IsEmpty}");
    }
}
