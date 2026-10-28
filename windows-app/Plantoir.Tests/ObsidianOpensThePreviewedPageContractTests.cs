using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #681 (the mac's #518): which file a section's Open in Obsidian opens for the
/// page its preview shows, played from <c>shared-rules.json</c> →
/// <c>obsidianOpensThePreviewedPage</c> — its fixture laid out on disk, every
/// case resolved through <see cref="PreviewedPageSource"/>, the trail's words
/// and the link's encoding. Nothing is retyped from the contract.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class ObsidianOpensThePreviewedPageContractTests : IDisposable
{
    private static JsonNode Block => ContractLoader.LoadJson("shared-rules.json")["obsidianOpensThePreviewedPage"]!;

    private readonly string _root;

    public ObsidianOpensThePreviewedPageContractTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-681-").FullName;
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static PreviewedPageSource.Fallback FallbackOf(string name) =>
        Enum.Parse<PreviewedPageSource.Fallback>(char.ToUpperInvariant(name[0]) + name[1..]);

    /// <summary>
    /// The fixture, on disk: every file under a course folder, 'Café Notes.md'
    /// DECOMPOSED as the fixture's note says (NTFS keeps it so), and the
    /// outside file beside the course folder.
    /// </summary>
    private string LayOutTheFixture()
    {
        var fixture = Block["fixture"]!;
        string course = Path.Combine(_root, "courses", "ICS3U");
        foreach (var node in fixture["files"]!.AsArray())
        {
            string relative = node!.ToString();
            if (relative.Contains("Café", StringComparison.Ordinal))
                relative = relative.Normalize(NormalizationForm.FormD);
            string path = Path.Combine(course, relative.Replace('/', '\\'));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "a page\n");
        }
        string outside = Path.GetFullPath(Path.Combine(course, fixture["outside"]!.ToString().Replace('/', '\\')));
        Directory.CreateDirectory(Path.GetDirectoryName(outside)!);
        File.WriteAllText(outside, "not the course's\n");
        return course;
    }

    /// <summary>The list a case reads: the fixture's pages with the case's entries replacing by key; a case's <c>list</c> is used as it stands (null: no file).</summary>
    private static JsonObject? ListFor(JsonObject testCase)
    {
        if (testCase.ContainsKey("list"))
            return testCase["list"] is JsonObject given ? PreviewedPageSource.ParseList(given.ToJsonString()) : PreviewedPageSource.ReadList(Path.Combine(Path.GetTempPath(), "no-such-plantoir-list", PreviewedPageSource.ListFileName));
        var pages = (JsonObject)Block["fixture"]!["pages"]!.DeepClone();
        if (testCase["pages"] is JsonObject replacing)
            foreach (var (key, value) in replacing) pages[key] = value!.DeepClone();
        return PreviewedPageSource.ParseList(new JsonObject { ["version"] = 1, ["pages"] = pages }.ToJsonString());
    }

    [Fact]
    public void EveryCaseResolvesAsTheContractSays()
    {
        string course = LayOutTheFixture();
        var cases = Block["cases"]!.AsArray();
        // A TRIPWIRE, deliberately: the mac adding a case should be noticed
        // here and read, as the named-gap rule intends, not pass by unseen
        // because a loop happened to run one more time. Raise it on purpose.
        Assert.Equal(23, cases.Count);
        var wrong = new List<string>();
        foreach (var node in cases)
        {
            var testCase = node!.AsObject();
            string name = testCase["name"]!.ToString();
            string? address = testCase["address"]?.ToString();
            var answer = PreviewedPageSource.Resolve(address, ListFor(testCase), course);
            var expect = testCase["expect"]!;
            if (expect["fallback"] is { } fallback)
            {
                if (answer != new PreviewedPageSource.FellBack(FallbackOf(fallback.ToString())))
                    wrong.Add($"{name}: expected {fallback}, got {answer}");
                continue;
            }
            string opens = expect["opens"]!.ToString();
            bool hidden = expect["hidden"]!.GetValue<bool>();
            if (answer is not PreviewedPageSource.Page page)
            {
                wrong.Add($"{name}: expected {opens}, got {answer}");
                continue;
            }
            string opened = Path.GetRelativePath(course, page.File).Replace('\\', '/').Normalize(NormalizationForm.FormC);
            if (opened != opens || page.Hidden != hidden || !File.Exists(page.File))
                wrong.Add($"{name}: expected {opens} hidden={hidden}, got {opened} hidden={page.Hidden}");
            if (page.Place + ".md" != opens)
                wrong.Add($"{name}: the place {page.Place} is not {opens} without .md");
        }
        Assert.True(wrong.Count == 0, string.Join("\n", wrong));
    }

    [Fact]
    public void ADecomposedNameIsOpenedAsItIsOnDisk()
    {
        string course = LayOutTheFixture();
        var answer = PreviewedPageSource.Resolve("Unit-1/Caf%C3%A9-Notes", ListFor(new JsonObject()), course);
        var page = Assert.IsType<PreviewedPageSource.Page>(answer);
        Assert.True(File.Exists(page.File));
        Assert.Equal("Café Notes.md".Normalize(NormalizationForm.FormD), Path.GetFileName(page.File));
    }

    /// <summary>
    /// NTFS finds a name in any case, Obsidian's vault lookup does not: a list
    /// naming the file in another case opens the file as it is spelled on disk.
    /// </summary>
    [Fact]
    public void ACaseChangedNameIsOpenedAsItIsOnDisk()
    {
        string course = LayOutTheFixture();
        var list = ListFor(new JsonObject { ["pages"] = new JsonObject
        {
            ["Unit-1/Lesson-3"] = new JsonObject { ["source"] = "unit 1/LESSON 3.md", ["hidden"] = false },
        } });
        var page = Assert.IsType<PreviewedPageSource.Page>(PreviewedPageSource.Resolve("Unit-1/Lesson-3", list, course));
        Assert.Equal(Path.Combine("Unit 1", "Lesson 3.md"), Path.GetRelativePath(course, page.File));
    }

    /// <summary>
    /// A '..' is refused before anything is walked, even one that would come
    /// back inside the course: after a link the spelled path and the real one
    /// part ways, and the spelled one is what Obsidian is handed.
    /// </summary>
    [Theory]
    [InlineData("Unit 1/../Unit 1/Lesson 3.md")]
    [InlineData("section1/../../ICS3U/Unit 1/Lesson 3.md")]
    [InlineData("C:/Windows/win.md")]
    public void ADotDotSegmentIsRefusedBeforeAnythingIsWalked(string source)
    {
        string course = LayOutTheFixture();
        var list = ListFor(new JsonObject { ["pages"] = new JsonObject
        {
            ["Unit-1/Lesson-3"] = new JsonObject { ["source"] = source, ["hidden"] = false },
        } });
        Assert.Equal(new PreviewedPageSource.FellBack(PreviewedPageSource.Fallback.OutsideTheCourse),
            PreviewedPageSource.Resolve("Unit-1/Lesson-3", list, course));
    }

    [Fact]
    public void TheTrailWordsAreTheContracts()
    {
        var trail = Block["trail"]!;
        Assert.Equal(trail["opened"]!.ToString(), PreviewedPageSource.TrailOpened);
        Assert.Equal(trail["openedHidden"]!.ToString(), PreviewedPageSource.TrailOpenedHidden);
        Assert.Equal(trail["fellBack"]!.ToString(), PreviewedPageSource.TrailFellBack);

        var fallbacks = Block["fallbacks"]!.AsObject();
        Assert.Equal(fallbacks.Count, Enum.GetValues<PreviewedPageSource.Fallback>().Length);
        foreach (var (key, words) in fallbacks)
            Assert.Equal(words!.ToString(), PreviewedPageSource.Why(FallbackOf(key)));

        Assert.Equal(trail["opened"]!.ToString().Replace("{place}", "Unit 1/Lesson 3"),
            PreviewedPageSource.TrailWords(new PreviewedPageSource.Page(@"C:\x\Unit 1\Lesson 3.md", "Unit 1/Lesson 3", false)));
        Assert.Equal(trail["fellBack"]!.ToString().Replace("{why}", fallbacks["fileGone"]!.ToString()),
            PreviewedPageSource.TrailWords(new PreviewedPageSource.FellBack(PreviewedPageSource.Fallback.FileGone)));
    }

    [Fact]
    public void ThePressWritesThePageOpenedInObsidianEvent()
    {
        string trail = Path.Combine(_root, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(trail);
        PreviewedPageSource.NoteThePress(new PreviewedPageSource.Page(@"C:\x\Unit 1\Quiz.md", "section1/Unit 1/Quiz", true), "ICS3U", 1);
        string written = File.ReadAllText(trail);
        Assert.Contains("ICS3U/1 · " + Block["trail"]!["openedHidden"]!.ToString().Replace("{place}", "section1/Unit 1/Quiz"), written);
        Assert.Equal("page opened in Obsidian", ActivityTrail.KeyFor(ActivityTrail.Event.PageOpenedInObsidian));
    }

    /// <summary>
    /// The contract's <c>link.cases</c> are POSIX paths, and the note says the
    /// percent-encoding of everything but '+' is the platform encoder's own:
    /// Windows' <c>Uri.EscapeDataString</c> escapes every separator - a Windows
    /// path's '' as %5C and ':' as %3A (and these POSIX paths' '/' as %2F) -
    /// so the strings are not compared. What IS the contract's: '+' is %2B, '&amp;' is
    /// %26, a space is %20, and the path comes back whole.
    /// </summary>
    [Fact]
    public void TheLinkEncodesWhatTheContractEncodes()
    {
        var cases = Block["link"]!["cases"]!.AsArray();
        // A tripwire, as in EveryCaseResolvesAsTheContractSays: raise it on purpose.
        Assert.Equal(3, cases.Count);
        foreach (var node in cases)
        {
            string path = node!["path"]!.ToString();
            string contractLink = node["link"]!.ToString();
            string link = PreviewedPageSource.ObsidianLink(path);
            Assert.StartsWith("obsidian://open?path=", link);
            string query = link["obsidian://open?path=".Length..];
            Assert.Equal(path, Uri.UnescapeDataString(query));
            Assert.DoesNotContain("+", query);
            Assert.DoesNotContain("&", query);
            Assert.DoesNotContain(" ", query);
            foreach (var (raw, encoded) in new[] { ("+", "%2B"), ("&", "%26"), (" ", "%20") })
            {
                if (path.Contains(raw))
                {
                    Assert.Contains(encoded, contractLink);
                    Assert.Contains(encoded, query);
                }
            }
        }
    }
}
