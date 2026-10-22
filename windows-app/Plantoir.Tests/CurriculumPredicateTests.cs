using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The one curriculum test the planner uses, <see cref="PagePaths.IsCurriculum"/>
/// (#615), and the publish plan's already-visible list that reads it (#617, the
/// mac's #607). The contract half is <c>followingLinks.publishing.cases</c> /
/// <c>.unpublishing.cases</c> in <c>FollowingLinksContractTests</c>; these pin
/// what a case cannot: the predicate's edges, and the card, the table and the
/// MCP text agreeing about the list.
/// </summary>
public class CurriculumPredicateTests : IDisposable
{
    private const string Course = "ICS3U";
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-curriculum").FullName;
    private string CourseDir => Path.Combine(_folder, "courses", Course);

    public CurriculumPredicateTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(Path.Combine(CourseDir, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), $$"""
            { "course_code": "{{Course}}", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    // ---- The predicate ---------------------------------------------------

    [Theory]
    [InlineData(@"Curriculum\A1.1.md", true)]
    [InlineData(@"Ontario Curriculum\A1.1.md", true)]
    [InlineData(@"College Board Curriculum\Unit 3\A1.2.md", true)]
    [InlineData(@"section1\Curriculum Coverage.md", false)]   // #615: the FILE name never counts
    [InlineData(@"Concepts\Curriculum.md", false)]
    [InlineData(@"Curriculum Coverage.md", false)]           // at the course root
    [InlineData(@"section1\All Classes\Unit 1, Day 1.md", false)]
    public void OnlyAFolderInsideTheCourseMakesAPageCurriculum(string inCourse, bool expected)
    {
        string root = @"C:\work\courses\ICS3U";
        Assert.Equal(expected, PagePaths.IsCurriculum(root, Path.Combine(root, inCourse)));
    }

    [Fact]
    public void AFolderAboveTheCourseDoesNotCount()
    {
        string root = @"C:\Curriculum Work\courses\ICS3U";
        Assert.False(PagePaths.IsCurriculum(root, root + @"\section1\Glossary.md"));
        Assert.True(PagePaths.IsCurriculum(root, root + @"\Curriculum\A1.1.md"));
    }

    [Fact]
    public void ARelativePathIsNeverReadAgainstTheProcesssWorkingDirectory()
    {
        // A PlannedPage.RelativePath is from the WORKING folder; passed raw it
        // used to resolve against the process's current directory. It is
        // false now, whatever it says — callers resolve it first.
        Assert.False(PagePaths.IsCurriculum(@"C:\work\courses\ICS3U", @"courses\ICS3U\Curriculum\A1.1.md"));
        Assert.False(PagePaths.IsCurriculum(@"C:\work\courses\ICS3U", @"Curriculum\A1.1.md"));
        Assert.False(PagePaths.IsCurriculum(@"C:\work\courses\ICS3U", ""));
    }

    [Fact]
    public void APageOutsideTheCourseIsNotCurriculum()
    {
        string root = @"C:\work\courses\ICS3U";
        // A segment that is exactly "..": the page is in ANOTHER course.
        Assert.False(PagePaths.IsCurriculum(root, @"C:\work\courses\ICS3U\..\ICS4U\Curriculum\A1.1.md"));
        Assert.False(PagePaths.IsCurriculum(root, @"C:\work\courses\ICS4U\Curriculum\A1.1.md"));
        Assert.False(PagePaths.IsCurriculum(root, @"D:\Curriculum\A1.1.md"));
        // ".." that stays inside the course still counts.
        Assert.True(PagePaths.IsCurriculum(root, @"C:\work\courses\ICS3U\section1\..\Curriculum\A1.1.md"));
    }

    /// <summary>
    /// shared-rules.json → curriculumRules.isCurriculumPage.cases, each path
    /// under a course root, so the planner's predicate answers exactly as the
    /// assistant's list of expectations does.
    /// </summary>
    [Fact]
    public void TheContractsCurriculumPageCasesHoldUnderACourse()
    {
        string root = @"C:\Curriculum Work\courses\ICS3U";
        var cases = ContractLoader.LoadJson("shared-rules.json")!["curriculumRules"]!["isCurriculumPage"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);
        foreach (var c in cases)
        {
            string path = c!["path"]!.ToString();
            bool expected = c["expect"]!.GetValue<bool>();
            Assert.True(expected == PagePaths.IsCurriculum(root, Path.Combine(root, path.Replace('/', '\\'))),
                $"“{path}” should be {(expected ? "" : "not ")}curriculum.");
        }
    }

    // ---- The publish plan (#617) ------------------------------------------

    private void Write(string relative, string frontmatter, params string[] links)
    {
        string path = Path.Combine(CourseDir, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, $"---\ntitle: {Path.GetFileNameWithoutExtension(path)}\n{frontmatter}\n---\nA sentence.\n" +
                                string.Concat(links.Select(l => $"\nSee [[{l}]].\n")));
    }

    private const string SectionVisible = "publish: true\ncreated: 2026-09-08T07:00:00.000-0400";
    private const string SectionHidden = "publish: false\ncreated: 2026-09-08T07:00:00.000-0400";
    private const string CourseVisible = "publishForSection1: true\ncreatedSection1: 2026-09-08T07:00:00.000-0400";
    private const string CourseHidden = "publishForSection1: false\ncreatedSection1: 2026-09-08T07:00:00.000-0400";

    /// <summary>The #607 layout: a hidden class citing a visible and a hidden expectation, and a visible glossary.</summary>
    private AssistWorkspace LayAClassCitingExpectations()
    {
        Write(@"section1\All Classes\Unit 2, Day 3.md", SectionHidden, "A1.4", "A1.5", "Glossary");
        Write(@"Curriculum\A1.4.md", CourseVisible);
        Write(@"Ontario Curriculum\A1.5.md", CourseHidden);
        Write(@"section1\Glossary.md", SectionVisible);
        return new AssistWorkspace(_folder, new FakeLauncher());
    }

    [Fact]
    public void ALinkedVisibleCurriculumPageIsNotAlreadyVisibleOnTheCardTheTableOrTheSummary()
    {
        var workspace = LayAClassCitingExpectations();
        var plan = workspace.PlanPublish(Course, 1, new[] { "Unit 2, Day 3" });

        Assert.Equal(new[] { "Glossary" }, plan.AlreadyRight.Select(p => p.DisplayTitle));
        // A hidden expectation is still a change, or the class would link to a page students cannot open.
        Assert.Contains(plan.Changes, c => c.Page.DisplayTitle == "A1.5" && c.WillBeVisible);

        Assert.Contains("1 page is already visible.", plan.Describe());

        var table = workspace.Tabulate(plan);
        Assert.DoesNotContain(table.Rows, r => r.Title == "A1.4");
        Assert.Equal(AssistWording.MenuPlanSummary(plan.Changes.Count, 1, publishing: true), table.Summary);
    }

    [Fact]
    public void ACurriculumPageTheTeacherNamesIsStillListed()
    {
        var workspace = LayAClassCitingExpectations();
        var plan = workspace.PlanPublish(Course, 1, new[] { "Unit 2, Day 3", "A1.4" });

        Assert.Contains(plan.AlreadyRight, p => p.DisplayTitle == "A1.4");
    }

    [Fact]
    public void TheModelsPlanCountsTheSameList()
    {
        LayAClassCitingExpectations();
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));

        string text = tools.PlanPublishPages(Course, 1, pages: new[] { "Unit 2, Day 3" }).Summary();

        Assert.Contains("1 page is already visible.", text);
        Assert.DoesNotContain("2 pages are already visible.", text);
    }

    // ---- The hide side (#615) ---------------------------------------------

    [Fact]
    public void HidingKeepsACurriculumFolderPageButNotAPageOnlyCalledCurriculum()
    {
        Write(@"section1\All Classes\Unit 2, Day 3.md", SectionVisible, "A1.1", "Curriculum Coverage");
        Write(@"Curriculum\A1.1.md", CourseVisible);
        Write(@"section1\Curriculum Coverage.md", SectionVisible);
        var workspace = new AssistWorkspace(_folder, new FakeLauncher());

        var plan = workspace.PlanPublish(Course, 1, new[] { "Unit 2, Day 3" }, draft: true, publishes: false);

        Assert.Contains(plan.Kept, k => k.Page.DisplayTitle == "A1.1" && k.Reason == "it is a curriculum page.");
        Assert.Contains(plan.Changes, c => c.Page.DisplayTitle == "Curriculum Coverage" && !c.WillBeVisible);
        Assert.DoesNotContain(plan.Kept, k => k.Page.DisplayTitle == "Curriculum Coverage");
    }
}
