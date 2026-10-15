using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The Section menu's runner for one window (#489, the mac's
/// <c>SectionVerbsTests</c>): the calls it builds in code, the one runner entry
/// they go through, Undo Last Change's place, the trail's "ran from a menu"
/// lines, and the claim the in-app assistant meets.
/// </summary>
[Collection(SharedActivityState.Name)]
public class SectionVerbsTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-section-verbs").FullName;
    private readonly string _trail;
    private readonly string _course;

    public SectionVerbsTests()
    {
        SectionMenuActivity.Reset();
        _trail = Path.Combine(_folder, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        _course = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(_course);
        File.WriteAllText(Path.Combine(_course, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        int day = 8;
        foreach (string title in new[] { "Unit 1, Day 1", "Unit 1, Day 2" })
        {
            string full = Path.Combine(_course, "section1", "All Classes", title + ".md");
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllText(full, $"---\npublish: false\ncreated: 2026-09-{day++:00}T07:00:00.000-0400\n---\nBody.\n");
        }
    }

    public void Dispose()
    {
        SectionMenuActivity.Reset();
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string Page(string title) => Path.Combine(_course, "section1", "All Classes", title + ".md");

    private SectionVerbs Verbs(out AssistWorkspace workspace)
    {
        var server = new AssistWorkspace(_folder, new FakeLauncher(), undo: new UndoHistory()) { Surface = AssistSurface.Menu };
        workspace = server;
        var tools = new AssistScenarioTests.RealTools(server);
        return new SectionVerbs(_folder, _ => Task.FromResult<IToolServer?>(tools),
            (course, section, toolServer) => new AssistToolRunner(toolServer, course, section, AssistSurface.Menu));
    }

    private static JsonObject Arguments(JsonObject call) =>
        (JsonObject)JsonNode.Parse(call["function"]!["arguments"]!.GetValue<string>())!;

    [Fact]
    public void PagesAreNamedByTheirFolder_AsAJsonArray()
    {
        Assert.Equal("section1/All Classes/Unit 2, Day 3",
                     SectionVerbs.PageName(_course, Path.Combine(_course, "section1", "All Classes", "Unit 2, Day 3.md")));

        var call = SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/Unit 2; Day 3" }, plan: true);
        Assert.Equal("plan_publish_pages", call["function"]!["name"]!.GetValue<string>());
        var pages = Assert.IsType<JsonArray>(Arguments(call)["pages"]);
        Assert.Equal("section1/All Classes/Unit 2; Day 3", Assert.Single(pages)!.GetValue<string>());
        Assert.StartsWith("menu-", call["id"]!.GetValue<string>());
    }

    [Fact]
    public void ReDatingNeverSendsAWebsite_AndMakingRoomSaysWhereAndHowMany()
    {
        var reDate = Arguments(SectionVerbs.ReDateClasses("ICS3U", 1, plan: false));
        Assert.False(reDate.ContainsKey("website"));
        Assert.Equal(new[] { "course", "section" }, reDate.Select(pair => pair.Key).ToArray());

        var room = Arguments(SectionVerbs.MakeRoomForClasses("ICS3U", 1, unit: 2, atDay: 4, howMany: 3, plan: true));
        Assert.Equal(2, room["unit"]!.GetValue<int>());
        Assert.Equal(4, room["atDay"]!.GetValue<int>());
        Assert.Equal(3, room["howMany"]!.GetValue<int>());
    }

    [Fact]
    public async Task APublish_IsCarriedOut_PlacedForUndo_AndUndoTakesItBack()
    {
        await using var verbs = Verbs(out _);
        Assert.False(verbs.LastChangeIsIn("ICS3U", 1));

        var plan = await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/Unit 1, Day 1" }, plan: true),
                                       "Section ▸ Publish Pages…", "ICS3U", 1, "1 page ticked");
        Assert.True(plan.IsPlan);
        Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));

        await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/Unit 1, Day 1" }, plan: false),
                            "Section ▸ Publish Pages…", "ICS3U", 1, "1 page ticked");
        Assert.Contains("publish: true", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.True(verbs.LastChangeIsIn("ICS3U", 1));
        Assert.False(verbs.LastChangeIsIn("ICS3U", 2));

        var undone = await verbs.Perform(SectionVerbs.UndoLastChange(), "Section ▸ Undo Last Change", "ICS3U", 1);
        Assert.StartsWith("Undone. Earlier, you ", undone.Summary);
        Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.False(verbs.LastChangeIsIn("ICS3U", 1));

        string trail = File.ReadAllText(_trail);
        Assert.Contains("ICS3U/1 · Section ▸ Publish Pages… — carried out, 1 page ticked", trail);
        Assert.Contains("ICS3U/1 · Section ▸ Undo Last Change — took the last change back", trail);
        // A plan writes no line: only a change, or a cancel, does.
        Assert.Equal(1, trail.Split('\n').Count(line => line.Contains("Section ▸ Publish Pages…")));
        Assert.DoesNotContain("Unit 1, Day 1", trail.Split('\n').Where(line => line.Contains("Section ▸")).Aggregate("", string.Concat));
    }

    [Fact]
    public async Task APublishOfWhatIsAlreadyPublished_ChangedNothing()
    {
        File.WriteAllText(Page("Unit 1, Day 2"), "---\npublish: true\ncreated: 2026-09-09T07:00:00.000-0400\n---\nBody.\n");
        await using var verbs = Verbs(out _);

        await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/Unit 1, Day 2" }, plan: false),
                            "Section ▸ Publish Pages…", "ICS3U", 1, "1 page ticked");

        Assert.Contains("ICS3U/1 · Section ▸ Publish Pages… — changed nothing, 1 page ticked", File.ReadAllText(_trail));
        Assert.False(verbs.LastChangeIsIn("ICS3U", 1));
    }

    [Fact]
    public void ACancelAtThePlanSaysSo()
    {
        SectionVerbs.NoteCancelled("Section ▸ Hide Pages…", "ICS3U", 1, "2 pages ticked");
        Assert.Contains("ICS3U/1 · Section ▸ Hide Pages… — cancelled at the plan, 2 pages ticked", File.ReadAllText(_trail));
    }

    [Fact]
    public async Task TheMenuHoldsTheSectionWhileItChanges_AndTheAssistantsWriteIsRefused()
    {
        using (SectionMenuActivity.Begin(_folder, "ICS3U", 1))
        {
            Assert.True(SectionMenuActivity.IsChanging(_folder, "ics3u", 1));
            Assert.True(SectionMenuActivity.IsChanging(_folder, "ICS3U", null));
            Assert.False(SectionMenuActivity.IsChanging(_folder, "ICS3U", 2));

            var window = new AssistWorkspace(_folder, new FakeLauncher(), undo: new UndoHistory()) { Surface = AssistSurface.LocalWindow };
            var runner = new AssistToolRunner(new AssistScenarioTests.RealTools(window), "ICS3U", 1, AssistSurface.LocalWindow)
            {
                SectionIsChangingFromTheMenu = () => SectionMenuActivity.IsChanging(_folder, "ICS3U", 1),
            };
            var (answer, handed) = await runner.Run(SectionVerbs.PublishPages("ICS3U", 1, new[] { "Unit 1, Day 1" }, plan: false), default);
            Assert.True(handed);
            Assert.Equal(AssistWording.SectionIsChangingFromTheMenu("ICS3U", "1"), answer.Summary);
            Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));

            // A read is never held back.
            var (read, _) = await runner.Run(SectionVerbs.PublishPages("ICS3U", 1, new[] { "Unit 1, Day 1" }, plan: true), default);
            Assert.True(read.IsPlan);
        }
        Assert.False(SectionMenuActivity.IsChanging(_folder, "ICS3U", 1));
    }

    [Fact]
    public async Task RebuildPreviewFromTheMenu_RebuildsAServingPreview_OrSaysACopyIsBeingSaved()
    {
        int rebuilt = 0, shown = 0;
        var tools = new AssistScenarioTests.RealTools(new AssistWorkspace(_folder, new FakeLauncher()) { Surface = AssistSurface.Menu });
        var runner = new AssistToolRunner(tools, "ICS3U", 1, AssistSurface.Menu)
        {
            ShowPreviewInApp = () => shown++,
            RebuildPreviewInApp = () => rebuilt++,
            CourseIsBeingCopied = () => false,
        };
        var (answer, _) = await runner.Run(SectionVerbs.RebuildPreview("ICS3U", 1), default);
        Assert.Equal(AssistWording.PreviewIsRebuilding("ICS3U", "1"), answer.Summary);
        Assert.Equal((1, 0), (rebuilt, shown));

        var copying = new AssistToolRunner(tools, "ICS3U", 1, AssistSurface.Menu)
        {
            RebuildPreviewInApp = () => rebuilt++,
            CourseIsBeingCopied = () => true,
        };
        var (refused, _) = await copying.Run(SectionVerbs.RebuildPreview("ICS3U", 1), default);
        Assert.Equal(AssistWording.CourseIsBeingCopiedFromTheMenu("ICS3U"), refused.Summary);
        Assert.Equal(1, rebuilt);
    }

    [Fact]
    public void TheAssistantsWindowReportsWork_AndTheMenuCanSeeIt()
    {
        AssistActivity.ReportWork(_folder, "ICS3U", 1, working: true);
        try
        {
            Assert.True(AssistActivity.IsWorking(_folder, "ics3u", 1));
            Assert.False(AssistActivity.IsWorking(_folder, "ICS3U", 2));
        }
        finally { AssistActivity.ReportWork(_folder, "ICS3U", 1, working: false); }
        Assert.False(AssistActivity.IsWorking(_folder, "ICS3U", 1));
    }
}
