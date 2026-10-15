using System.Text.Json.Nodes;
using ModelContextProtocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #475 at the deploys that are not the window's own button (the rest of
/// #489): the in-app assistant's runner, the server's deploy, and the places
/// a class is remembered as kept. The four scenarios in
/// <c>assist-cases.json</c> pin the order and the outside refusal; these pin
/// what the scenarios cannot reach. The window's own question is driven by
/// <c>LaterClassesAtDeployUiTests</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class ClassesDatedLaterAtDeployTests : IDisposable
{
    private static readonly DateOnly Today = new(2026, 10, 8);
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-later").FullName;
    private readonly string _trail;
    private readonly FakeLauncher _launcher = new();

    public ClassesDatedLaterAtDeployTests()
    {
        _trail = Path.Combine(_folder, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        Directory.CreateDirectory(CourseDirectory);
        File.WriteAllText(Path.Combine(CourseDirectory, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        Directory.CreateDirectory(Path.Combine(CourseDirectory, ".netlify_sites"));
        File.WriteAllText(Path.Combine(CourseDirectory, ".netlify_sites", "section1.json"), """{"name": "ics3u-s1"}""");
        Class("Unit 2, Day 3", Today, published: true);
        Class("Unit 2, Day 4", Today.AddDays(1), published: true);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string CourseDirectory => Path.Combine(_folder, "courses", "ICS3U");

    private string PagePath(string title) => Path.Combine(CourseDirectory, "section1", "All Classes", title + ".md");

    private void Class(string title, DateOnly day, bool published)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(PagePath(title))!);
        File.WriteAllText(PagePath(title),
            $"---\npublish: {(published ? "true" : "false")}\ncreated: {DateText.Iso(day)}T07:00:00.000-0400\n---\nBody.\n");
    }

    private Course TheCourse => Workspace.DiscoverCourses(_folder).Single(found => found.Code == "ICS3U");

    private static JsonObject DeployCall() => new()
    {
        ["id"] = "call-1",
        ["function"] = new JsonObject
        {
            ["name"] = "deploy_section",
            ["arguments"] = new JsonObject { ["course"] = "ICS3U", ["section"] = 1 }.ToJsonString(),
        },
    };

    // ---- The in-app assistant's runner --------------------------------------

    /// <summary>
    /// A window with a dialog already up is not waited on: the deploy is refused
    /// with deployWaitsForAnOpenQuestion and nothing is stopped or pressed.
    /// </summary>
    [Fact]
    public async Task AWindowWithAQuestionUp_IsNotWaitedOn()
    {
        var happened = new List<string>();
        var runner = new AssistToolRunner(new AssistScenarioTests.RealTools(new AssistWorkspace(_folder, _launcher)),
                                          "ICS3U", 1, AssistSurface.LocalWindow)
        {
            AskAboutClassesDatedLaterInApp = () => Task.FromResult<LaterClassesAtADeploy>(LaterClassesAnswer.CannotAsk),
            PreviewIsShowing = () => true,
            StopPreviewInAppAsync = () => { happened.Add("stop"); return Task.CompletedTask; },
            StartDeployInAppAsync = () => { happened.Add("deploy"); return Task.FromResult<string?>("deployed"); },
        };

        var (answer, handed) = await runner.Run(DeployCall(), default);

        Assert.True(handed);
        Assert.Equal(AssistWording.DeployWaitsForAnOpenQuestion("ICS3U", "1"), answer.Summary);
        Assert.Empty(happened);
    }

    /// <summary>No window could show the section: refused, the classes named, nothing stopped.</summary>
    [Fact]
    public async Task NoWindowToAskIn_IsRefusedNamingTheClasses()
    {
        var happened = new List<string>();
        var runner = new AssistToolRunner(new AssistScenarioTests.RealTools(new AssistWorkspace(_folder, _launcher)),
                                          "ICS3U", 1, AssistSurface.LocalWindow)
        {
            AskAboutClassesDatedLaterInApp = () => Task.FromResult(
                new LaterClassesAtADeploy(LaterClassesAnswer.NoWindow, new[] { "Unit 2, Day 5", "Unit 2, Day 6" })),
            PreviewIsShowing = () => true,
            StopPreviewInAppAsync = () => { happened.Add("stop"); return Task.CompletedTask; },
            StartDeployInAppAsync = () => { happened.Add("deploy"); return Task.FromResult<string?>("deployed"); },
        };

        var (answer, _) = await runner.Run(DeployCall(), default);

        Assert.Equal(AssistWording.DeployHasClassesDatedLaterAndNoWindow("ICS3U", "1", new[] { "Unit 2, Day 5", "Unit 2, Day 6" }),
                     answer.Summary);
        Assert.Empty(happened);
    }

    /// <summary>
    /// The hide the question at Deploy makes stops no preview and starts none
    /// (the plan review's M1): a hide that failed must not leave the teacher
    /// with no preview for a deploy that never happened.
    /// </summary>
    [Fact]
    public async Task TheHideForTheQuestion_HasNoPreviewEitherSide()
    {
        Class("Unit 2, Day 5", Today.AddDays(3), published: true);
        var happened = new List<string>();
        var runner = new AssistToolRunner(new AssistScenarioTests.RealTools(
                                              new AssistWorkspace(_folder, _launcher, undo: new UndoHistory()) { Surface = AssistSurface.Menu }),
                                          "ICS3U", 1, AssistSurface.Menu)
        {
            PreviewIsShowing = () => true,
            StopPreviewInAppAsync = () => { happened.Add("stop"); return Task.CompletedTask; },
            ShowPreviewInApp = () => happened.Add("start"),
            PreviewFollowsAChange = false,
        };

        await runner.Run(SectionVerbs.HidePages("ICS3U", 1, new[] { "section1/All Classes/Unit 2, Day 5" }, plan: false), default);

        Assert.Contains("publish: false", File.ReadAllText(PagePath("Unit 2, Day 5")));
        Assert.Empty(happened);
    }

    // ---- The server's deploy --------------------------------------------------

    /// <summary>
    /// Plantoir's own assistant reaching the server's deploy has no window to
    /// ask in: held back before anything runs, in the teacher's words, and the
    /// trail says how many waited — "{N} with no answer", nobody named.
    /// </summary>
    [Fact]
    public async Task TheServersDeployWithNoWindow_IsHeldBackBeforeAnythingRuns()
    {
        Class("Unit 2, Day 5", Today.AddDays(3), published: true);
        var workspace = new AssistWorkspace(_folder, _launcher) { Surface = AssistSurface.LocalWindow, Today = () => Today };

        var refused = await Assert.ThrowsAsync<AssistRefusal>(() => workspace.Deploy("ICS3U", 1));

        Assert.Equal(AssistWording.DeployHasClassesDatedLaterAndNoWindow("ICS3U", "1", new[] { "Unit 2, Day 5" }), refused.Message);
        Assert.Empty(_launcher.Runs);
        Assert.Contains("ICS3U/1 · a deploy was held back for classes dated after the next class — 1 class with no answer",
                        File.ReadAllText(_trail));
    }

    // ---- What is remembered as kept -------------------------------------------

    /// <summary>
    /// publish_class_on: the teacher NAMED the day, so the class it published
    /// is kept at that date and the next Deploy does not offer to hide it.
    /// </summary>
    [Fact]
    public async Task PublishingAClassByItsDate_KeepsIt()
    {
        Class("Unit 2, Day 5", Today.AddDays(3), published: false);
        var workspace = new AssistWorkspace(_folder, _launcher, undo: new UndoHistory()) { Today = () => Today };
        var tools = new PlantoirTools(workspace);

        await tools.PublishClassOn("ICS3U", 1, DateText.Iso(Today.AddDays(3)),
                                   new Progress<ProgressNotificationValue>(_ => { }), default, preview: false);

        Assert.Contains("publish: true", File.ReadAllText(PagePath("Unit 2, Day 5")));
        Assert.Equal(new[] { new LaterClassesKept.Row("section1/All Classes/Unit 2, Day 5", DateText.Iso(Today.AddDays(3))) },
                     LaterClassesKept.Read(CourseDirectory, 1));
        Assert.Empty(ClassesDatedLater.FlaggedIn(TheCourse, 1, Today));
    }

    /// <summary>Tomorrow's class, published by its date, leaves no record: it would never be asked about.</summary>
    [Fact]
    public async Task PublishingTomorrowsClass_LeavesNoRecord()
    {
        File.WriteAllText(PagePath("Unit 2, Day 4"), File.ReadAllText(PagePath("Unit 2, Day 4")).Replace("publish: true", "publish: false"));
        var workspace = new AssistWorkspace(_folder, _launcher, undo: new UndoHistory()) { Today = () => Today };

        await new PlantoirTools(workspace).PublishClassOn("ICS3U", 1, DateText.Iso(Today.AddDays(1)),
                                                          new Progress<ProgressNotificationValue>(_ => { }), default, preview: false);

        Assert.Contains("publish: true", File.ReadAllText(PagePath("Unit 2, Day 4")));
        Assert.False(File.Exists(LaterClassesKept.PathFor(CourseDirectory, 1)));
    }

    /// <summary>A class dated later published from the links checklist is kept: the two questions must not undo each other.</summary>
    [Fact]
    public void AClassPublishedFromTheLinksChecklist_IsKept()
    {
        Class("Unit 2, Day 5", Today.AddDays(3), published: true);
        Class("Unit 2, Day 6", Today.AddDays(4), published: true);
        var workspace = new AssistWorkspace(_folder, _launcher) { Today = () => Today };

        workspace.KeepTheClassesItPublished(TheCourse, 1, new[] { "section1/All Classes/Unit 2, Day 5", "section1/All Classes/Unit 2, Day 4" });

        // Day 4 is the next class and is never asked about, so it leaves no row.
        Assert.Equal(new[] { new LaterClassesKept.Row("section1/All Classes/Unit 2, Day 5", DateText.Iso(Today.AddDays(3))) },
                     LaterClassesKept.Read(CourseDirectory, 1));
        Assert.Equal(new[] { "section1/All Classes/Unit 2, Day 6" },
                     ClassesDatedLater.FlaggedIn(TheCourse, 1, Today).Select(page => page.Place));
    }

    // ---- The window's order, read from its source --------------------------------

    /// <summary>
    /// The window cannot be built in a unit test, so the ORDER in
    /// <c>SectionDetailView.DeployAsync</c> is read from the source, as
    /// <c>ReferenceRefusalTests</c> reads the reference refusal: every refusal
    /// first (the last of them the destinations'), then the question, then the
    /// saved-settings notice (a Cancel must not leave "deployed using the saved
    /// settings" on the trail), and only then the console claimed and the
    /// preview stopped.
    /// </summary>
    [Fact]
    public void TheWindowsDeploy_AsksAfterItsRefusals_AndBeforeItClaimsOrStopsAnything()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"));
        int start = source.IndexOf("private async Task<string?> DeployAsync(", StringComparison.Ordinal);
        Assert.True(start > 0);
        int Where(string text) => source.IndexOf(text, start, StringComparison.Ordinal);
        int refusals = Where("MultiDestinationDeployRunner.RefusalReason(destinations");
        int asked = Where("AskAboutClassesDatedLaterAsync(\"Deploy\")");
        int savedNotice = Where("ActivityTrail.Event.DeployUsedTheSavedSettings");
        int claimed = Where("_deployRunner.ClaimConsole()");
        int stopped = Where("await StopPreviewAsync()");
        Assert.True(refusals > start && asked > refusals && savedNotice > asked && claimed > savedNotice && stopped > claimed,
            $"DeployAsync's order is wrong: refusals {refusals}, asked {asked}, saved notice {savedNotice}, claimed {claimed}, stopped {stopped}");
    }
}
