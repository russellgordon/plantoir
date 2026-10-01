using System.Reflection;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #420: publishing ALWAYS takes what a page links to, and hiding takes a page
/// only that page links to — with no argument for either, as the contract says
/// (<c>shared-rules.json</c> → <c>followingLinks</c>) and as the mac's schema
/// has it (<c>toolSchemas.departures.absentHere</c>). The case lists themselves
/// run in <see cref="FollowingLinksContractTests"/>, which since #420 calls the
/// tools WITHOUT a flag; these are the consumers around them: the undo, the
/// card's arguments, the reply and the served schema.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class PublishFollowsLinksTests : IDisposable
{
    private const string Course = "ICS3U";
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-follows-links").FullName;
    private string CourseDir => Path.Combine(_folder, "courses", Course);

    public PublishFollowsLinksTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(Path.Combine(CourseDir, "section1", "All Classes"));
        Directory.CreateDirectory(Path.Combine(CourseDir, "Concepts"));
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), $$"""
            { "course_code": "{{Course}}", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        // A hidden class, a hidden concept it links to, and a hidden worked
        // example the concept links to in turn.
        File.WriteAllText(ClassPath, "---\ntitle: Unit 2, Day 3\npublish: false\ncreated: 2026-09-10T07:00:00.000-0400\n---\nToday: [[Ohm's Law]].\n");
        File.WriteAllText(ConceptPath("Ohm's Law"), "---\npublishForSection1: false\n---\nSee [[Worked Example]].\n");
        File.WriteAllText(ConceptPath("Worked Example"), "---\npublishForSection1: false\n---\nA worked example.\n");
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string ClassPath => Path.Combine(CourseDir, "section1", "All Classes", "Unit 2, Day 3.md");
    private string ConceptPath(string title) => Path.Combine(CourseDir, "Concepts", title + ".md");
    private static bool Visible(string path) => !PageFrontmatter.IsDraft(File.ReadAllText(path), 1);

    /// <summary>
    /// A publish with no flag takes the linked pages, the reply names them,
    /// and one undo puts every one of them back — the undo record holds what
    /// was WRITTEN, linked pages included.
    /// </summary>
    [Fact]
    public async Task APublishTakesItsLinkedPagesAndOneUndoPutsThemAllBack()
    {
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher(), undo: new UndoHistory()));
        var before = new[] { ClassPath, ConceptPath("Ohm's Law"), ConceptPath("Worked Example") }
            .ToDictionary(p => p, File.ReadAllText);

        string plan = tools.PlanPublishPages(Course, 1, pages: new[] { "Unit 2, Day 3" }).Summary();
        Assert.Contains("Ohm's Law", plan);
        Assert.Contains("Worked Example", plan);

        var answer = await tools.PublishPages(Course, 1, new Progress<ProgressNotificationValue>(_ => { }), default,
                                              new[] { "Unit 2, Day 3" }, preview: false);
        Assert.Contains("3 pages", answer.Summary());
        Assert.True(Visible(ClassPath));
        Assert.True(Visible(ConceptPath("Ohm's Law")));
        Assert.True(Visible(ConceptPath("Worked Example")));

        tools.UndoLastChange();
        foreach (var (path, text) in before) Assert.Equal(text, File.ReadAllText(path));
    }

    /// <summary>
    /// Hiding with no flag takes the pages only that class links to.
    /// </summary>
    [Fact]
    public async Task HidingTakesThePagesOnlyThatClassLinksTo()
    {
        foreach (var path in new[] { ClassPath, ConceptPath("Ohm's Law"), ConceptPath("Worked Example") })
            File.WriteAllText(path, File.ReadAllText(path).Replace(": false", ": true"));
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));

        await tools.UnpublishPages(Course, 1, new Progress<ProgressNotificationValue>(_ => { }), default,
                                   new[] { "Unit 2, Day 3" }, preview: false);

        Assert.False(Visible(ClassPath));
        Assert.False(Visible(ConceptPath("Ohm's Law")));
        Assert.False(Visible(ConceptPath("Worked Example")));
    }

    /// <summary>The fixed phrasings the app answers in code carry no flag either.</summary>
    [Theory]
    [InlineData("hide unit 2, day 3", "unpublish_pages")]
    [InlineData("unpublish unit 2, day 3", "unpublish_pages")]
    public void TheCardsArgumentsCarryNoFlag(string said, string tool)
    {
        var card = AssistCardCommand.Matching(said);
        Assert.NotNull(card);
        Assert.Equal(tool, card!.ToolName);
        Assert.False(card.ToJsonObject(Course, 1).ContainsKey("includeLinked"));
    }

    /// <summary>
    /// None of the four tools DECLARES the flag (the served schema is built
    /// from these parameters), so neither a model nor an outside assistant is
    /// asked how far a publish should reach.
    /// </summary>
    [Theory]
    [InlineData(nameof(PlantoirTools.PublishPages))]
    [InlineData(nameof(PlantoirTools.UnpublishPages))]
    [InlineData(nameof(PlantoirTools.PlanPublishPages))]
    [InlineData(nameof(PlantoirTools.PlanUnpublishPages))]
    public void NoToolDeclaresTheFlag(string method)
    {
        var parameters = typeof(PlantoirTools).GetMethod(method, BindingFlags.Public | BindingFlags.Instance)!.GetParameters();
        Assert.DoesNotContain(parameters, p => string.Equals(p.Name, "includeLinked", StringComparison.OrdinalIgnoreCase));
    }
}
