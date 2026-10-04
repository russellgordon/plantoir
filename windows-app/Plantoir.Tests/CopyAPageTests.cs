using System.Text;
using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>copyingAPageBetweenCourses.cases</c>, built on disk and run through the
/// real plan and the real copy (#247): which pages arrive and where, which
/// pictures are created, reused or renamed, what is skipped and why, and what
/// is listed as leading nowhere.
/// </summary>
[Collection(CopyAPageDiskCollection.Name)]
public class CopyAPageTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-copy-page").FullName;

    public void Dispose()
    {
        ReferenceLock.Unlock(_root);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["copyingAPageBetweenCourses"]!;

    internal static Course Build(string root, JsonNode side, IEnumerable<int>? sections = null)
    {
        string folder = side["folder"]!.ToString();
        string course = Path.Combine(root, "courses", folder);
        Directory.CreateDirectory(course);
        var shared = side["sharedFolders"]!.AsArray().Select(f => f!.ToString()).ToList();
        foreach (string f in shared) Directory.CreateDirectory(Path.Combine(course, f));
        var config = new JObject
        {
            ["course_code"] = folder,
            ["section_numbers"] = new JArray((side["sections"]?.AsArray().Select(n => n!.GetValue<int>()) ?? sections ?? new[] { 1 }).ToArray()),
            ["shared_folders"] = new JArray(shared.ToArray()),
            ["per_section_folders"] = new JArray("All Classes", "Handouts"),
        };
        File.WriteAllText(Path.Combine(course, "course_config.json"), config.ToString());
        foreach (var page in side["pages"]!.AsArray())
        {
            string path = page is JsonValue ? page.ToString() : page!["path"]!.ToString();
            string text = page is JsonValue ? "Body\n" : page!["text"]!.ToString();
            string full = Path.Combine(course, path.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllText(full, text, new UTF8Encoding(false));
        }
        var media = side["media"]?.AsArray() ?? new JsonArray();
        if (media.Count > 0) Directory.CreateDirectory(Path.Combine(course, CoursePageCopy.MediaFolder));
        foreach (var file in media)
        {
            string name = file!["name"]!.ToString();
            File.WriteAllText(Path.Combine(course, CoursePageCopy.MediaFolder, name), file["bytes"]!.ToString());
            if (side["andEveryNumberedNameUpTo"] is { } upTo && name.Contains(" (from ", StringComparison.Ordinal))
            {
                string stem = Path.GetFileNameWithoutExtension(name), extension = Path.GetExtension(name);
                for (int n = 2; n <= upTo.GetValue<int>(); n++)
                    File.WriteAllText(Path.Combine(course, CoursePageCopy.MediaFolder, $"{stem} {n}{extension}"), $"taken {n}");
            }
        }
        return new Course(folder, course, CourseConfiguration.Load(Path.Combine(course, "course_config.json")));
    }

    private static List<string> Strings(JsonNode? node) => node?.AsArray().Select(n => n!.ToString()).ToList() ?? new List<string>();

    [Fact]
    public void EveryCaseIsTheContracts()
    {
        var cases = Rule["cases"]!.AsArray();
        int ran = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string root = Path.Combine(_root, $"case{ran}");
            var source = Build(root, c["source"]!);
            if (c["offers"] is { } offers)
            {
                Assert.Equal(Strings(offers), CoursePageCopy.Offered(source));
                ran++;
                continue;
            }
            var destination = Build(root, c["destination"]!);
            var copy = c["copy"]!;
            var request = new CoursePageCopy.Request(source, destination, copy["page"]!.ToString(), copy["intoFolder"]!.ToString(),
                copy["alsoCopiesLinkedPages"]?.ToString() == "yes");
            var plan = CoursePageCopy.MakePlan(request);
            if (copy["keepNone"]?.ToString() == "yes")
            {
                request = request with { Unticked = plan.LinkedPageRows.ToHashSet() };
                plan = CoursePageCopy.MakePlan(request);
            }
            var session = new CoursePageCopy.Session(_ => "BACKUP.zip");
            var outcome = CoursePageCopy.Copy(plan, request, session);
            var expect = c["expect"]!;

            Assert.True(Strings(expect["pages"]).ToHashSet().SetEquals(outcome.PagesCreated), $"{name}: pages {string.Join(", ", outcome.PagesCreated)}");
            Assert.True(Strings(expect["mediaCreated"]).ToHashSet(StringComparer.Ordinal).SetEquals(outcome.MediaCreated), $"{name}: created {string.Join(", ", outcome.MediaCreated)}");
            Assert.True(Strings(expect["mediaReused"]).ToHashSet(StringComparer.Ordinal).SetEquals(outcome.MediaReused), $"{name}: reused {string.Join(", ", outcome.MediaReused)}");
            var renamed = expect["mediaRenamed"]!.AsObject().ToDictionary(p => p.Key, p => p.Value!.ToString());
            Assert.True(renamed.Count == outcome.MediaRenamed.Count && renamed.All(p => outcome.MediaRenamed.GetValueOrDefault(p.Key) == p.Value),
                $"{name}: renamed {string.Join(", ", outcome.MediaRenamed.Select(p => p.Key + "->" + p.Value))}");
            var skipped = expect["skipped"]!.AsArray().Select(s => (s!["name"]!.ToString(), s["reason"]!.ToString())).ToHashSet();
            Assert.True(skipped.SetEquals(outcome.Skipped.Select(s => (s.Name, s.Reason))),
                $"{name}: skipped {string.Join(", ", outcome.Skipped.Select(s => s.Name + "/" + s.Reason))}");
            Assert.True(Strings(expect["linksLeadingNowhere"]).ToHashSet().SetEquals(outcome.LinksLeadingNowhere),
                $"{name}: nowhere {string.Join(", ", outcome.LinksLeadingNowhere)}");
            if (expect["required"] is { } required)
                Assert.Equal(Strings(required), plan.Pages.Where(p => p.Required && !p.IsChosen).Select(p => p.Name).ToList());

            foreach (string page in outcome.PagesCreated)
            {
                string text = File.ReadAllText(Path.Combine(destination.DirectoryPath, page.Replace('/', Path.DirectorySeparatorChar)));
                Assert.True(CopyPageFrontmatter.IsCertainlyHidden(text, destination.SectionNumbers), $"{name}: {page} is not certainly hidden");
            }
            foreach (string media in outcome.MediaCreated)
                Assert.Contains(media, Directory.GetFiles(Path.Combine(destination.DirectoryPath, CoursePageCopy.MediaFolder)).Select(Path.GetFileName));
            ran++;
        }
        Assert.True(ran >= 32, $"only {ran} cases ran");
    }

    [Fact]
    public void ARenamedPictureIsPointedAtByTheCopyAndTheTeachersOwnIsUntouched()
    {
        var source = Build(_root, JsonNode.Parse("""{"folder":"ICS4U-2025","sharedFolders":["Concepts"],"pages":[{"path":"Concepts/R.md","text":"![[one.png]] and ![](<one pic.png>) and <img src=\"/Media/one%20pic.png\">\n"}],"media":[{"name":"one.png","bytes":"aaa"},{"name":"one pic.png","bytes":"aaa"}]}""")!);
        var destination = Build(_root, JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Concepts"],"pages":[],"media":[{"name":"one.png","bytes":"zz"},{"name":"one pic.png","bytes":"zz"}]}""")!);
        var request = new CoursePageCopy.Request(source, destination, "Concepts/R.md", "Concepts", false);
        var outcome = CoursePageCopy.Copy(CoursePageCopy.MakePlan(request), request, new CoursePageCopy.Session(_ => "B.zip"));
        string text = File.ReadAllText(Path.Combine(destination.DirectoryPath, "Concepts", "R.md"));
        Assert.Contains("![[one (from ICS4U-2025).png]]", text);
        Assert.Contains("![](<one pic (from ICS4U-2025).png>)", text);
        Assert.Contains("src=\"/Media/one%20pic%20(from%20ICS4U-2025).png\"", text);
        Assert.Equal("zz", File.ReadAllText(Path.Combine(destination.DirectoryPath, "Media", "one.png")));
        Assert.Equal(2, outcome.MediaRenamed.Count);
    }

    [Fact]
    public void ALateCollisionIsASkipNotAnOverwrite()
    {
        var source = Build(_root, JsonNode.Parse("""{"folder":"ICS4U-2025","sharedFolders":["Concepts"],"pages":[{"path":"Concepts/Recursion.md","text":"Body\n"}],"media":[]}""")!);
        var destination = Build(_root, JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Concepts"],"pages":[],"media":[]}""")!);
        var request = new CoursePageCopy.Request(source, destination, "Concepts/Recursion.md", "Concepts", false);
        var plan = CoursePageCopy.MakePlan(request);
        // The racing creator: the page appears after the index was read and
        // before the write, which only an exclusive create can refuse.
        string racer = Path.Combine(destination.DirectoryPath, "Concepts", "Recursion.md");
        CoursePageCopy.BeforeWritingAPage = path => File.WriteAllText(racer, "the teacher's own");
        CoursePageCopy.Outcome outcome;
        try { outcome = CoursePageCopy.Copy(plan, request, new CoursePageCopy.Session(_ => "B.zip")); }
        finally { CoursePageCopy.BeforeWritingAPage = null; }
        Assert.Equal("the teacher's own", File.ReadAllText(racer));
        Assert.Empty(outcome.PagesCreated);
        Assert.Contains(outcome.Skipped, s => s.Reason == "aPageOfThatNameIsAlreadyHere");
    }

    /// <summary>
    /// A write that fails part way leaves NO page behind (review M1, ruling
    /// 1): the half-written copy — its settings possibly cut off before the
    /// keys that hide it — is removed, never left to be published.
    /// </summary>
    [Fact]
    public void AWriteThatFailsPartWayLeavesNoPageBehind()
    {
        var source = Build(_root, JsonNode.Parse("""{"folder":"ICS4U-2025","sharedFolders":["Concepts"],"pages":[{"path":"Concepts/Recursion.md","text":"Body\n"}],"media":[]}""")!);
        var destination = Build(_root, JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Concepts"],"pages":[],"media":[]}""")!);
        var request = new CoursePageCopy.Request(source, destination, "Concepts/Recursion.md", "Concepts", false);
        var plan = CoursePageCopy.MakePlan(request);
        CoursePageCopy.WhileWritingAPage = _ => throw new IOException("There is not enough space on the disk.");
        CoursePageCopy.Outcome outcome;
        try { outcome = CoursePageCopy.Copy(plan, request, new CoursePageCopy.Session(_ => "B.zip")); }
        finally { CoursePageCopy.WhileWritingAPage = null; }
        Assert.False(File.Exists(Path.Combine(destination.DirectoryPath, "Concepts", "Recursion.md")));
        Assert.Empty(outcome.PagesCreated);
        Assert.Empty(outcome.MustBeRemoved);
        Assert.Contains(outcome.Skipped, s => s.Reason == "thePageCouldNotBeWritten");
    }

    [Fact]
    public void OneBackupIsTakenPerSessionNotPerPress()
    {
        var source = Build(_root, JsonNode.Parse("""{"folder":"ICS4U-2025","sharedFolders":["Concepts"],"pages":[{"path":"Concepts/A.md","text":"x\n"},{"path":"Concepts/B.md","text":"y\n"}],"media":[]}""")!);
        var destination = Build(_root, JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Concepts"],"pages":[],"media":[]}""")!);
        int zips = 0;
        var session = new CoursePageCopy.Session(_ => { zips++; return $"B{zips}.zip"; });
        foreach (string page in new[] { "Concepts/A.md", "Concepts/B.md" })
        {
            var request = new CoursePageCopy.Request(source, destination, page, "Concepts", false);
            CoursePageCopy.Copy(CoursePageCopy.MakePlan(request), request, session);
        }
        Assert.Equal(1, zips);
        Assert.Equal("B1.zip", session.BackupName);
    }

    [Fact]
    public void ADeployRefusesBeforeAnythingIsWrittenAndAFailedBackupWritesNothing()
    {
        var source = Build(_root, JsonNode.Parse("""{"folder":"ICS4U-2025","sharedFolders":["Concepts"],"pages":[{"path":"Concepts/A.md","text":"x\n"}],"media":[]}""")!);
        var destination = Build(_root, JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Concepts"],"pages":[],"media":[]}""")!);
        var request = new CoursePageCopy.Request(source, destination, "Concepts/A.md", "Concepts", false);
        var plan = CoursePageCopy.MakePlan(request);
        var deploying = CoursePageCopy.Copy(plan, request, new CoursePageCopy.Session(_ => "B.zip"), isDeploying: () => true);
        Assert.Equal("thatCourseIsDeployingRightNow", deploying.Refusal);
        var noBackup = CoursePageCopy.Copy(plan, request, new CoursePageCopy.Session(_ => throw new IOException("disk full")));
        Assert.Equal("theCopyOfTheCourseCouldNotBeSaved", noBackup.Refusal);
        Assert.False(File.Exists(Path.Combine(destination.DirectoryPath, "Concepts", "A.md")));
    }

    [Fact]
    public void TheSectionsAreReReadJustBeforeWriting()
    {
        var source = Build(_root, JsonNode.Parse("""{"folder":"ICS4U-2025","sharedFolders":["Concepts"],"pages":[{"path":"Concepts/A.md","text":"x\n"}],"media":[]}""")!);
        var destination = Build(_root, JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Concepts"],"pages":[],"media":[]}""")!);
        var request = new CoursePageCopy.Request(source, destination, "Concepts/A.md", "Concepts", false);
        var plan = CoursePageCopy.MakePlan(request);
        var config = JObject.Parse(File.ReadAllText(destination.ConfigFilePath));
        config["section_numbers"] = new JArray(1, 2, 5);      // another window added sections
        File.WriteAllText(destination.ConfigFilePath, config.ToString());
        CoursePageCopy.Copy(plan, request, new CoursePageCopy.Session(_ => "B.zip"));
        string text = File.ReadAllText(Path.Combine(destination.DirectoryPath, "Concepts", "A.md"));
        Assert.Contains("publishForSection5: false", text);
    }

    [Fact]
    public void TheTrailLineNamesNoPageAndNoPicture()
    {
        string trail = Path.Combine(_root, "trail.txt");
        Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            var source = Build(_root, JsonNode.Parse("""{"folder":"ICS4U-2025","sharedFolders":["Concepts"],"pages":[{"path":"Concepts/Secret Title.md","text":"![[hidden-name.png]]\n"}],"media":[{"name":"hidden-name.png","bytes":"a"}]}""")!);
            var destination = Build(_root, JsonNode.Parse("""{"folder":"ICS4U","sharedFolders":["Concepts"],"pages":[],"media":[]}""")!);
            var request = new CoursePageCopy.Request(source, destination, "Concepts/Secret Title.md", "Concepts", false);
            CoursePageCopy.Copy(CoursePageCopy.MakePlan(request), request, new CoursePageCopy.Session(_ => "ICS4U_backup_x.zip"));
            string line = Assert.Single(File.ReadAllLines(trail));
            Assert.Contains("ICS4U-2025", line);
            Assert.Contains("ICS4U_backup_x.zip", line);
            Assert.Contains("1 pages created", line);
            Assert.DoesNotContain("Secret", line);
            Assert.DoesNotContain("hidden-name", line);
        }
        finally { Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath); }
    }
}

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class CopyAPageDiskCollection
{
    public const string Name = "Copy a Page on disk";
}
