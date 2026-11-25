using System.Text.Json;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// Pointing a page at the curriculum expectations it actually covers.
/// </summary>
public sealed class CurriculumMentionsTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(),
        "plantoir-curriculum-" + Guid.NewGuid().ToString("N"));
    private readonly FakeLauncher _launcher = new();

    public CurriculumMentionsTests()
    {
        string course = Path.Combine(_folder, "courses", "ADA1O");
        Directory.CreateDirectory(Path.Combine(course, "section1", "All Classes"));
        Directory.CreateDirectory(Path.Combine(course, "Curriculum"));
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            """
            {
              "course_code": "ADA1O",
              "course_name": "Drama",
              "deploy_target": "netlify",
              "num_sections": 1,
              "shared_folders": ["Curriculum"],
              "per_section_folders": ["All Classes"],
              "per_section_files": [],
              "section_numbers": [1]
            }
            """);

        Expectation("A1.1", "use a variety of print and non-print sources to generate and focus ideas");
        Expectation("A2.2", "use a variety of drama conventions to develop character and atmosphere");
        // Not an expectation: a strand heading, which must never be offered.
        File.WriteAllText(Path.Combine(course, "Curriculum", "A1. The Creative Process.md"),
            "---\npublishForSection1: true\n---\nThe strand heading.\n");
    }

    private void Expectation(string code, string text) =>
        File.WriteAllText(Path.Combine(_folder, "courses", "ADA1O", "Curriculum", code + ".md"),
            $"---\npublishForSection1: true\ntranscludeTitleSize: h4\n---\n{text} ^text\n");

    private string ClassPath(string title) =>
        Path.Combine(_folder, "courses", "ADA1O", "section1", "All Classes", title + ".md");

    private void ClassPage(string title, string body) =>
        File.WriteAllText(ClassPath(title), $"---\ntitle: {title}\npublish: true\n---\n{body}");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private AssistWorkspace Open() => new(_folder, _launcher);

    // ---- Reading the curriculum out ---------------------------------------

    [Fact]
    public void ExpectationsComeBackWithTheirWording()
    {
        var found = Open().CurriculumExpectations(
            Open().Course("ADA1O"), 1);

        // The wording is the point: matching an expectation to a lesson is a
        // judgement about meaning, and a code alone cannot be judged.
        Assert.Equal(new[] { "A1.1", "A2.2" }, found.Select(e => e.Code));
        Assert.Contains("print and non-print sources", found[0].Text);
        // The ^text anchor is stripped — it is Obsidian plumbing, not wording.
        Assert.DoesNotContain("^text", found[0].Text);
    }

    [Fact]
    public void StrandHeadingsAreNotExpectations()
    {
        var found = Open().CurriculumExpectations(Open().Course("ADA1O"), 1);

        // "A1. The Creative Process" is a strand heading, not something a
        // lesson can point at. Only leaf codes like A1.1 count.
        Assert.DoesNotContain(found, e => e.Code.Contains("Creative"));
        Assert.All(found, e => Assert.Matches(@"^[A-Za-z]\d+\.\d+$", e.Code));
    }

    // ---- Planning ---------------------------------------------------------

    [Fact]
    public void ThePlanQuotesWhatEachExpectationSays()
    {
        ClassPage("Movement Concepts", "## Agenda\n\n1. Work.\n");

        var plan = Open().PlanCurriculumMentions("ADA1O", 1, "Movement Concepts", new[] { "A2.2" });

        string described = plan.Describe();
        Assert.Contains("A2.2", described);
        // So the teacher can tell whether it fits without going to look it up.
        Assert.Contains("drama conventions", described);
    }

    [Fact]
    public void ACodeThatIsNotAnExpectationIsNamedRatherThanDropped()
    {
        ClassPage("Movement Concepts", "Body.\n");

        var plan = Open().PlanCurriculumMentions("ADA1O", 1, "Movement Concepts", new[] { "A2.2", "Z9.9" });

        Assert.Equal("Z9.9", Assert.Single(plan.Unknown));
        // Silently dropping it would leave the teacher believing it was added.
        Assert.Contains("Z9.9 is not an expectation", plan.Describe());
    }

    [Fact]
    public void AnExpectationAlreadyOnThePageIsLeftAlone()
    {
        ClassPage("Movement Concepts", "%%curriculum-start%%\n![[A2.2]]\n%%curriculum-end%%\n");

        var plan = Open().PlanCurriculumMentions("ADA1O", 1, "Movement Concepts", new[] { "A2.2" });

        Assert.True(plan.ChangesNothing);
        Assert.Equal("A2.2", Assert.Single(plan.AlreadyThere));
    }

    // ---- Writing ----------------------------------------------------------

    [Fact]
    public void TransclusionsGoInsideTheCurriculumMarkers()
    {
        ClassPage("Movement Concepts", "## Agenda\n\n1. Work.\n\n## Things to do before our next class\n\n- [ ] Read.\n");

        var workspace = Open();
        var plan = workspace.PlanCurriculumMentions("ADA1O", 1, "Movement Concepts", new[] { "A1.1", "A2.2" });
        workspace.ApplyCurriculumMentions(plan);

        string text = File.ReadAllText(ClassPath("Movement Concepts"));
        // The markers matter: a course installed without curriculum has this
        // whole block stripped at build time, so a transclusion outside them
        // would leave a dangling reference on the site.
        int start = text.IndexOf("%%curriculum-start%%", StringComparison.Ordinal);
        int end = text.IndexOf("%%curriculum-end%%", StringComparison.Ordinal);
        Assert.True(start > 0 && end > start);
        Assert.InRange(text.IndexOf("![[A1.1]]", StringComparison.Ordinal), start, end);
        Assert.InRange(text.IndexOf("![[A2.2]]", StringComparison.Ordinal), start, end);
    }

    [Fact]
    public void ANewBlockGoesBeforeTheThingsToDoList()
    {
        ClassPage("Movement Concepts", "## Agenda\n\n1. Work.\n\n## Things to do before our next class\n\n- [ ] Read.\n");

        var workspace = Open();
        var plan = workspace.PlanCurriculumMentions("ADA1O", 1, "Movement Concepts", new[] { "A1.1" });
        workspace.ApplyCurriculumMentions(plan);

        string text = File.ReadAllText(ClassPath("Movement Concepts"));
        // The curriculum note belongs with the lesson, not after the homework.
        Assert.True(text.IndexOf("%%curriculum-start%%", StringComparison.Ordinal) <
                    text.IndexOf("## Things to do", StringComparison.Ordinal));
    }

    /// <summary>
    /// A block on a page already is recognised by its markers, whichever line
    /// opens it: "Today's work points here:" on a page Windows wrote before
    /// #1039, the Mac's heading on one written since. The opening line is
    /// left exactly as it was; an existing page is never rewritten.
    /// </summary>
    [Theory]
    [InlineData("Today's work points here:")]
    [InlineData("## Curriculum connection")]
    public void AnExistingBlockIsAddedToRatherThanReplaced(string openingLine)
    {
        ClassPage("Movement Concepts",
            $"%%curriculum-start%%\n{openingLine}\n\n![[A1.1]]\n%%curriculum-end%%\n");

        var workspace = Open();
        var plan = workspace.PlanCurriculumMentions("ADA1O", 1, "Movement Concepts", new[] { "A2.2" });
        workspace.ApplyCurriculumMentions(plan);

        string text = File.ReadAllText(ClassPath("Movement Concepts"));
        Assert.Contains("![[A1.1]]", text);      // what was there stays
        Assert.Contains("![[A2.2]]", text);
        // One block, not two: a second set of markers would build as two
        // separate curriculum notes on the same page.
        Assert.Equal(2, text.Split("%%curriculum-start%%").Length);
        Assert.Equal(2, text.Split("%%curriculum-end%%").Length);
        Assert.Contains($"%%curriculum-start%%\n{openingLine}\n\n![[A1.1]]\n", text);
    }

    // ---- The Mac's block (#1039) ------------------------------------------

    /// <summary>
    /// A new block is the Mac's, byte for byte. The case is the Mac's own
    /// <c>addCurriculumMentions</c> run on a fixture and written down in
    /// <c>contracts/undo-action-steps.json</c>: the page before, and the page
    /// after with its <c>## Curriculum connection</c> block.
    /// </summary>
    [Fact]
    public void ANewBlockIsTheBlockTheMacWrites()
    {
        JsonElement macStep = ContractLoader.LoadDocument("undo-action-steps.json").RootElement
            .GetProperty("steps").EnumerateArray()
            .Single(step => step.GetProperty("action").GetString() == "addCurriculumMentions");
        JsonElement macFile = Assert.Single(macStep.GetProperty("files").EnumerateArray());
        string before = macFile.GetProperty("before").GetString()!;
        string after = macFile.GetProperty("after").GetString()!;
        string code = Regex.Match(after, @"!\[\[([^\]]+)\]\]").Groups[1].Value;
        Assert.Equal("A1.1", code);   // an expectation this fixture's course has
        File.WriteAllText(ClassPath("Loops"), before);

        var workspace = Open();
        var plan = workspace.PlanCurriculumMentions("ADA1O", 1, "Loops", new[] { code });
        workspace.ApplyCurriculumMentions(plan);

        Assert.Equal(after, File.ReadAllText(ClassPath("Loops")));
    }

    [Fact]
    public void ApplyingBacksUpFirstAndChangesNoVisibility()
    {
        ClassPage("Movement Concepts", "Body.\n");

        var workspace = Open();
        var plan = workspace.PlanCurriculumMentions("ADA1O", 1, "Movement Concepts", new[] { "A1.1" });
        var result = workspace.ApplyCurriculumMentions(plan);

        Assert.True(result.Succeeded);
        Assert.NotNull(result.BackupPath);
        Assert.Contains("publish: true", File.ReadAllText(ClassPath("Movement Concepts")));
        Assert.Contains("no page's visibility changes", plan.Describe());
    }
}
