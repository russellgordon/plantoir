using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>course-management.json</c> → <c>foldersAddedLater</c> (#580, the mac's
/// #506): a folder added in Course Settings gets its <c>index.md</c> and a
/// <c>_DUPLICATE ME.md</c>, compared as BYTES; the title rule
/// (<c>titleQuoting</c>); and the same rule on a section's front page
/// (<c>titleQuoting.frontPages</c>, #586, the mac's #575). The mac's are
/// <c>CourseManagementContractTests.testEveryFolderAddedLaterCase</c>,
/// <c>testEveryTitleQuotingCase</c>, <c>testEveryFrontPageTitleCase</c> and
/// <c>FolderScaffoldTests</c>.
/// </summary>
public class FolderScaffoldContractTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "scaffold-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode Section => ContractLoader.LoadJson("course-management.json")["foldersAddedLater"]!;

    /// <summary>The file <c>templateSource</c> names, read as the app reads the bundled one (CRLF → LF).</summary>
    private static string Template()
    {
        string relative = Section["templateSource"]!.ToString();
        string path = Path.Combine(ContractLoader.RepositoryRoot, relative.Replace('/', Path.DirectorySeparatorChar));
        return FolderScaffold.ReadTemplate(path) ?? throw new FileNotFoundException(path);
    }

    private static string Show(string text) => text.Replace("\r", "\\r").Replace("\n", "\\n\n");

    // ---- The contract's cases ------------------------------------------------

    /// <summary>
    /// Every case IN MEMORY, through <see cref="FolderScaffold.Pages"/> — so
    /// the seventh, <c>Unit 1: Kinematics</c>, never meets NTFS, which refuses
    /// a <c>:</c> in a name. Paths in order, then each page's text, ordinal.
    /// </summary>
    [Fact]
    public void EveryFolderAddedLaterCase()
    {
        string created = Section["created"]!.ToString();
        string template = Template();
        var cases = Section["cases"]!.AsArray();
        Assert.True(cases.Count >= 7, $"foldersAddedLater has shrunk to {cases.Count} cases");

        var failures = new List<string>();
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.ToString();
            string scopeName = testCase["scope"]!.ToString();
            Assert.True(scopeName is "shared" or "perSection", $"{name}: scope {scopeName}");
            var scope = scopeName == "shared" ? FolderScope.Shared : FolderScope.PerSection;
            var sections = testCase["sections"]!.AsArray().Select(n => n!.GetValue<int>()).ToList();
            var curriculum = testCase["curriculumPages"] is JsonArray pages
                ? pages.Select(p => p!.ToString()).ToList()
                : null;

            var written = FolderScaffold.Pages(testCase["folder"]!.ToString(), scope, sections, curriculum, created, template);
            var expected = testCase["files"]!.AsArray();
            var expectedPaths = expected.Select(f => f!["path"]!.ToString()).ToList();
            var writtenPaths = written.Select(p => p.RelativePath).ToList();
            if (!expectedPaths.SequenceEqual(writtenPaths))
            {
                failures.Add($"{name}: paths\n  expected: {string.Join(" | ", expectedPaths)}\n  actual:   {string.Join(" | ", writtenPaths)}");
                continue;
            }
            foreach (var file in expected)
            {
                string path = file!["path"]!.ToString();
                string text = file["text"]!.ToString();
                string actual = written.Single(p => p.RelativePath == path).Text;
                if (!Encoding.UTF8.GetBytes(text).SequenceEqual(Encoding.UTF8.GetBytes(actual)))
                    failures.Add($"{name}: {path}\n  expected:\n{Show(text)}\n  actual:\n{Show(actual)}");
            }
        }
        Assert.True(failures.Count == 0, "foldersAddedLater.cases through FolderScaffold.Pages:\n\n" + string.Join("\n\n", failures));
    }

    [Fact]
    public void EveryTitleQuotingCase()
    {
        var cases = Section["titleQuoting"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 15, $"titleQuoting has shrunk to {cases.Count} cases");
        var failures = new List<string>();
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.ToString();
            string title = testCase["title"]!.ToString();
            string actual = FolderScaffold.FrontmatterTitle(name);
            if (!string.Equals(title, actual, StringComparison.Ordinal))
                failures.Add($"{name}: expected {title}, wrote {actual}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    /// <summary>
    /// Each <c>frontPages</c> case twice, through the real
    /// <see cref="SectionAdder.AddSection"/>: added with no sibling (the
    /// wizard's form, expect <c>titleLine</c>), and added as section N+1 beside
    /// a section whose front page carries <c>titleLine</c> — the swap must read
    /// the quoted sibling back, keep its wording, and quote the result.
    /// </summary>
    [Fact]
    public void EveryFrontPageTitleCase()
    {
        var cases = Section["titleQuoting"]!["frontPages"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 6, $"frontPages has shrunk to {cases.Count} cases");
        var failures = new List<string>();
        int index = 0;
        foreach (var testCase in cases)
        {
            index++;
            string code = testCase!["courseCode"]!.ToString();
            string name = testCase["courseName"]!.ToString();
            int number = testCase["section"]!.GetValue<int>();
            bool showsGrade = testCase["showsGrade"]!.GetValue<bool>();
            string titleLine = testCase["titleLine"]!.ToString();
            string nextLine = testCase["nextSectionTitleLine"]!.ToString();

            var alone = FrontPageCourse($"alone{index}", code, name, Array.Empty<int>(), number, showsGrade);
            SectionAdder.AddSection(number, alone);
            string aloneLine = TitleLine(alone, number);
            if (aloneLine != titleLine)
                failures.Add($"{name}, section {number}, no sibling: expected {titleLine}, wrote {aloneLine}");

            var beside = FrontPageCourse($"beside{index}", code, name, new[] { number }, number, showsGrade);
            string siblingFolder = beside.SectionDirectory(number);
            Directory.CreateDirectory(siblingFolder);
            File.WriteAllText(Path.Combine(siblingFolder, "index.md"),
                $"---\n{titleLine}\ncreated: 2026-09-01T08:00:00.000-0400\npublish: true\n---\n# Welcome\n");
            SectionAdder.AddSection(number + 1, beside);
            string besideLine = TitleLine(beside, number + 1);
            if (besideLine != nextLine)
                failures.Add($"{name}, section {number + 1} beside {titleLine}: expected {nextLine}, wrote {besideLine}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    private Course FrontPageCourse(string place, string code, string name, IReadOnlyList<int> sections, int number, bool showsGrade)
    {
        var config = new JsonObject
        {
            ["course_code"] = code,
            ["course_name"] = name,
            ["section_numbers"] = new JsonArray(sections.Select(n => (JsonNode)n).ToArray()),
            ["num_sections"] = sections.Count,
            ["show_grade_in_title"] = new JsonObject { ["sections"] = new JsonObject { [$"section{number}"] = showsGrade } },
        };
        return SectionAdderTests.MakeCourse(Path.Combine(_root, place), code, config.ToJsonString());
    }

    private static string TitleLine(Course course, int section) =>
        File.ReadAllText(Path.Combine(course.SectionDirectory(section), "index.md"))
            .Split('\n').First(l => l.StartsWith("title:", StringComparison.Ordinal)).TrimEnd('\r');

    // ---- The sibling title read back (#586) ----------------------------------

    [Theory]
    [InlineData("\"Grade 12 Physics: Mechanics, Section 1\"", "Grade 12 Physics: Mechanics, Section 1")]
    [InlineData("'It''s Physics, Section 1'", "It's Physics, Section 1")]
    [InlineData("'Tis the Season, Section 1", "'Tis the Season, Section 1")]
    [InlineData("Plain, Section 1", "Plain, Section 1")]
    [InlineData("\"", "\"")]
    [InlineData("'", "'")]
    [InlineData("\"\\x41, Section 1\"", null)]
    [InlineData("\"a\", \"b\"", null)]
    public void ASiblingTitleIsReadBackFromItsQuotedForm(string value, string? expected) =>
        Assert.Equal(expected, SectionAdder.PlainTitle(value));

    /// <summary>
    /// The mac's <c>testASiblingTitleOnlyYAMLCouldDecodeFallsBackToTheForm</c>:
    /// a sibling only YAML could decode gives the wizard's form, quoted.
    /// </summary>
    [Fact]
    public void ASiblingTitleOnlyYamlCouldDecodeFallsBackToTheForm()
    {
        var course = FrontPageCourse("yaml", "SPH4U", "Physics: Mechanics", new[] { 1 }, 2, true);
        Directory.CreateDirectory(course.SectionDirectory(1));
        File.WriteAllText(Path.Combine(course.SectionDirectory(1), "index.md"),
            "---\ntitle: \"\\x41 Mine, Section 1\"\n---\n");
        SectionAdder.AddSection(2, course);
        Assert.Equal("title: \"Grade 12 Physics: Mechanics, Section 2\"", TitleLine(course, 2));
    }

    /// <summary>An unclosed leading quote is taken as written, and the result quoted for its first character.</summary>
    [Fact]
    public void AnUnclosedQuoteIsTakenAsWrittenAndQuoted()
    {
        var course = FrontPageCourse("unclosed", "CODING", "Club", new[] { 1 }, 1, true);
        Directory.CreateDirectory(course.SectionDirectory(1));
        File.WriteAllText(Path.Combine(course.SectionDirectory(1), "index.md"),
            "---\ntitle: 'Tis the Season, Section 1\n---\n");
        SectionAdder.AddSection(2, course);
        Assert.Equal("title: \"'Tis the Season, Section 2\"", TitleLine(course, 2));
    }

    // ---- Through the real writer, on disk ------------------------------------

    private string NewCourseDirectory(params string[] sectionFolders)
    {
        string dir = Path.Combine(_root, "courses", "SPH4U");
        Directory.CreateDirectory(dir);
        foreach (string folder in sectionFolders) Directory.CreateDirectory(Path.Combine(dir, folder));
        return dir;
    }

    [Fact]
    public void ASharedFolderAddedInSettingsGetsItsIndexAndAPageToDuplicate()
    {
        string dir = NewCourseDirectory();
        var outcome = SpecialFolderRenamer.CreateFoldersOnDisk("Labs", FolderScope.Shared, dir, new[] { 1, 2 },
            Template(), new[] { "A1.1.md", "index.md" }, "2026-10-17T09:30:00.000-0400");
        Assert.Equal(new FolderScaffold.Outcome(1, 1, 1), outcome);

        byte[] index = File.ReadAllBytes(Path.Combine(dir, "Labs", "index.md"));
        Assert.False(index.Length >= 3 && index[0] == 0xEF && index[1] == 0xBB && index[2] == 0xBF, "a byte-order mark was written");
        Assert.DoesNotContain((byte)'\r', index);
        Assert.StartsWith("---\ntitle: Labs\ncreatedSection1: 2026-10-17T09:30:00.000-0400\npublishForSection1: true\n",
                          Encoding.UTF8.GetString(index));
        string duplicate = File.ReadAllText(Path.Combine(dir, "Labs", "_DUPLICATE ME.md"));
        Assert.Contains("publishForSection2: false\n", duplicate);
        Assert.EndsWith("![[A1.1]]\n", duplicate);
        Assert.DoesNotContain("\r", duplicate);
    }

    [Fact]
    public void ReAddingAFolderThatIsAlreadyThereWritesNothingInIt()
    {
        string dir = NewCourseDirectory("Labs");
        var outcome = SpecialFolderRenamer.CreateFoldersOnDisk("Labs", FolderScope.Shared, dir, new[] { 1 }, Template());
        Assert.Equal(0, outcome.FoldersCreated);
        Assert.Empty(Directory.EnumerateFileSystemEntries(Path.Combine(dir, "Labs")));
    }

    [Fact]
    public void APageAlreadyThereIsNeverWrittenOver()
    {
        string dir = NewCourseDirectory();
        string folder = Path.Combine(dir, "Labs");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "index.md"), "mine");
        var pages = FolderScaffold.Pages("Labs", FolderScope.Shared, new[] { 1 }, null, "now", Template());
        var outcome = FolderScaffold.WritePages(pages, new[] { folder }, dir);
        Assert.Equal(new FolderScaffold.Outcome(1, 0, 1), outcome);
        Assert.Equal("mine", File.ReadAllText(Path.Combine(folder, "index.md")));
    }

    [Fact]
    public void WithNoExpectationPagesTheCurriculumConnectionGoes()
    {
        string dir = NewCourseDirectory();
        SpecialFolderRenamer.CreateFoldersOnDisk("Readings", FolderScope.Shared, dir, new[] { 1 }, Template(), new[] { "A1.md", "index.md" });
        string duplicate = File.ReadAllText(Path.Combine(dir, "Readings", "_DUPLICATE ME.md"));
        Assert.DoesNotContain("Curriculum connection", duplicate);
        Assert.DoesNotContain("%%curriculum-", duplicate);
    }

    [Fact]
    public void APerSectionFolderGetsItsPagesOnlyWhereItWasMade()
    {
        string dir = NewCourseDirectory("section1", "section2", Path.Combine("section2", "Warm-Ups"));
        var outcome = SpecialFolderRenamer.CreateFoldersOnDisk("Warm-Ups", FolderScope.PerSection, dir, new[] { 1, 2 }, Template());
        Assert.Equal(new FolderScaffold.Outcome(1, 1, 1), outcome);
        Assert.True(File.Exists(Path.Combine(dir, "section1", "Warm-Ups", "index.md")));
        Assert.True(File.Exists(Path.Combine(dir, "section1", "Warm-Ups", "_DUPLICATE ME.md")));
        Assert.Empty(Directory.EnumerateFileSystemEntries(Path.Combine(dir, "section2", "Warm-Ups")));
    }

    /// <summary>A name that needs quoting, on disk — colon-free, since NTFS refuses <c>:</c>.</summary>
    [Fact]
    public void AFolderNamedSoYamlWouldMisreadItGetsAQuotedTitle()
    {
        string dir = NewCourseDirectory();
        SpecialFolderRenamer.CreateFoldersOnDisk("'Tis the Season", FolderScope.Shared, dir, new[] { 1 }, Template());
        Assert.StartsWith("---\ntitle: \"'Tis the Season\"\n", File.ReadAllText(Path.Combine(dir, "'Tis the Season", "index.md")));
    }

    [Fact]
    public void WithNoTemplateOnlyTheIndexIsWritten()
    {
        string dir = NewCourseDirectory();
        var outcome = SpecialFolderRenamer.CreateFoldersOnDisk("Labs", FolderScope.Shared, dir, new[] { 1 }, template: null);
        Assert.Equal(new FolderScaffold.Outcome(1, 1, 0), outcome);
    }

    [Fact]
    public void TheTrailLineNamesWhatWasWritten()
    {
        const string start = "created the folder Labs in SPH4U (shared_folders)";
        Assert.Equal(start + ", with its index page and a page to duplicate",
            FolderScaffold.FolderCreatedTrailLine("Labs", "SPH4U", FolderScope.Shared, new FolderScaffold.Outcome(1, 1, 1)));
        Assert.Equal(start + ", with its index page",
            FolderScaffold.FolderCreatedTrailLine("Labs", "SPH4U", FolderScope.Shared, new FolderScaffold.Outcome(1, 1, 0)));
        Assert.Equal(start + ", with a page to duplicate",
            FolderScaffold.FolderCreatedTrailLine("Labs", "SPH4U", FolderScope.Shared, new FolderScaffold.Outcome(1, 0, 1)));
        Assert.Equal("created the folder Labs in SPH4U (per_section_folders)",
            FolderScaffold.FolderCreatedTrailLine("Labs", "SPH4U", FolderScope.PerSection, new FolderScaffold.Outcome(2, 0, 0)));
    }

    /// <summary>
    /// The mac's <c>testEveryBundledSkeletonTemplateIsTheContractsTemplateSource</c>:
    /// every skeleton's <c>_DUPLICATE ME.md</c> is the file <c>templateSource</c>
    /// names (line endings aside — this checkout may hold them as CRLF), so a
    /// folder added later gets the same page whatever skeleton the course came from.
    /// </summary>
    [Fact]
    public void EverySkeletonTemplateIsTheTemplateSource()
    {
        string template = Template();
        var files = Directory.GetFiles(Path.Combine(ContractLoader.RepositoryRoot, "support", "skeletons"),
                                       FolderScaffold.TemplateFileName, SearchOption.AllDirectories);
        Assert.True(files.Length > 100, $"only {files.Length} skeleton templates were found");
        var different = files.Where(f => FolderScaffold.ReadTemplate(f) != template).ToList();
        Assert.True(different.Count == 0, "differ from templateSource:\n" + string.Join("\n", different));
    }

    [Theory]
    [InlineData("A1.1", true)]
    [InlineData("B1.10", true)]
    [InlineData("A1", false)]
    [InlineData("1.A", false)]
    [InlineData("a1.1", false)]
    [InlineData("A1.1.1", false)]
    [InlineData("A\u0661.1", false)]
    [InlineData("A1.", false)]
    public void ASpecificExpectationIsTheAsciiLetterFirstShapeOnly(string stem, bool expected) =>
        Assert.Equal(expected, FolderScaffold.IsSpecificExpectationStem(stem));
}
