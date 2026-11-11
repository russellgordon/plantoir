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

    /// <summary>
    /// The window read that its own deploy will refuse: nothing was asked, the
    /// preview is KEPT, and Deploy is pressed only so the window's refusal is
    /// what the assistant relays (2C's implementation review, L-1).
    /// </summary>
    [Fact]
    public async Task ADeployTheWindowWillRefuse_KeepsThePreview_AndLetsTheRefusalSpeak()
    {
        var happened = new List<string>();
        var runner = new AssistToolRunner(new AssistScenarioTests.RealTools(new AssistWorkspace(_folder, _launcher)),
                                          "ICS3U", 1, AssistSurface.LocalWindow)
        {
            AskAboutClassesDatedLaterInApp = () => Task.FromResult(
                new LaterClassesAtADeploy(LaterClassesAnswer.NothingToAsk, WillBeRefused: true)),
            PreviewIsShowing = () => true,
            StopPreviewInAppAsync = () => { happened.Add("stop"); return Task.CompletedTask; },
            StartDeployInAppAsync = () => { happened.Add("deploy"); return Task.FromResult<string?>("the window's refusal"); },
        };

        var (answer, handed) = await runner.Run(DeployCall(), default);

        Assert.True(handed);
        Assert.Equal("the window's refusal", answer.Summary);
        Assert.Equal(new[] { "deploy" }, happened);
    }

    /// <summary>Nothing to ask and nothing refused: the preview is stopped first, as before #475.</summary>
    [Fact]
    public async Task NothingToAsk_StopsThePreviewThenDeploys()
    {
        var happened = new List<string>();
        var runner = new AssistToolRunner(new AssistScenarioTests.RealTools(new AssistWorkspace(_folder, _launcher)),
                                          "ICS3U", 1, AssistSurface.LocalWindow)
        {
            AskAboutClassesDatedLaterInApp = () => Task.FromResult<LaterClassesAtADeploy>(LaterClassesAnswer.NothingToAsk),
            PreviewIsShowing = () => true,
            StopPreviewInAppAsync = () => { happened.Add("stop"); return Task.CompletedTask; },
            StartDeployInAppAsync = () => { happened.Add("deploy"); return Task.FromResult<string?>("deployed"); },
        };

        await runner.Run(DeployCall(), default);

        Assert.Equal(new[] { "stop", "deploy" }, happened);
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
    /// The in-app assistant's question reads "already asking, or a dialog up"
    /// BEFORE <c>DeployWillBeRefused()</c>, which also counts the open question
    /// as a refusal: read the other way round, the window answered "nothing to
    /// ask", the runner stopped the preview and the deploy returned at once —
    /// against <c>classesDatedLater.whenTheWindowIsBusy</c> (2C's
    /// implementation review, M-A).
    /// </summary>
    [Fact]
    public void TheAssistantsQuestion_ChecksForAnOpenQuestionBeforeTheRefusals()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"));
        int start = source.IndexOf("Task<LaterClassesAtADeploy> AskAboutClassesDatedLaterForTheAssistantAsync()", StringComparison.Ordinal);
        Assert.True(start > 0);
        int end = source.IndexOf("WillBeRefused: true", start, StringComparison.Ordinal) + "WillBeRefused: true".Length;
        string body = source[start..end];
        int open = body.IndexOf("_deployRun.IsAsking || DialogGate.IsOpen(EffectiveXamlRoot)", StringComparison.Ordinal);
        int cannotAsk = body.IndexOf("LaterClassesAnswer.CannotAsk", StringComparison.Ordinal);
        int refused = body.IndexOf("DeployWillBeRefused()", StringComparison.Ordinal);
        Assert.True(open > 0 && cannotAsk > open && refused > cannotAsk,
            $"the open-question check must come first: open {open}, CannotAsk {cannotAsk}, DeployWillBeRefused {refused}");
        Assert.Contains("WillBeRefused: true", body);
    }

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
        int claimed = Where("run.Runner.ClaimConsole()");
        int stopped = Where("await StopPreviewAsync()");
        Assert.True(refusals > start && asked > refusals && savedNotice > asked && claimed > savedNotice && stopped > claimed,
            $"DeployAsync's order is wrong: refusals {refusals}, asked {asked}, saved notice {savedNotice}, claimed {claimed}, stopped {stopped}");
    }

    // ---- #726 (the mac's #694): ticked means deployed -----------------------

    private static string ViewSource(string file) =>
        File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", file)).Replace("\r\n", "\n");

    /// <summary>From <paramref name="signature"/> to the method's closing brace at four spaces.</summary>
    private static string MethodBody(string source, string signature)
    {
        int start = source.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start > 0, $"no {signature}");
        int end = source.IndexOf("\n    }\n", start, StringComparison.Ordinal);
        Assert.True(end > start, $"no end to {signature}");
        return source[start..end];
    }

    private static ClassesDatedLater.Page Later(string title, int day) =>
        new($"section1/All Classes/{title}", title, Today.AddDays(day), true);

    /// <summary>
    /// A ticked class goes out and is kept at its date; an unticked one is
    /// hidden (Russell's rulings on #694, <c>classesDatedLater.answers</c>).
    /// Before #726 a tick meant HIDE: swapping the two lists back turns this red.
    /// </summary>
    [Fact]
    public void TickedIsKept_UntickedIsHidden()
    {
        var flagged = new[] { Later("Unit 2, Day 5", 3), Later("Unit 2, Day 6", 4), Later("Unit 2, Day 7", 5) };
        var (kept, hidden) = ClassesDatedLater.AnswerAtDeploy(flagged, new[] { true, false, true });
        Assert.Equal(new[] { "Unit 2, Day 5", "Unit 2, Day 7" }, kept.Select(page => page.Title));
        Assert.Equal(new[] { "Unit 2, Day 6" }, hidden.Select(page => page.Title));

        var (allKept, noneHidden) = ClassesDatedLater.AnswerAtDeploy(flagged, new[] { true, true, true });
        Assert.Equal(3, allKept.Count);
        Assert.Empty(noneHidden);
        Assert.Throws<ArgumentException>(() => ClassesDatedLater.AnswerAtDeploy(flagged, new[] { true }));
    }

    /// <summary>
    /// The window's question has ONE button beside Cancel — Deploy Ticked, the
    /// default — and its answer is <see cref="ClassesDatedLater.AnswerAtDeploy"/>
    /// of the boxes as ticked. Red on the code before #726 (Hide Ticked and
    /// Deploy, with Keep All and Deploy as the secondary button).
    /// </summary>
    [Fact]
    public void TheDeployQuestionHasOneButtonBesideCancel()
    {
        string body = MethodBody(ViewSource(Path.Combine("Views", "SectionDetailView.xaml.cs")),
                                 "internal async Task<LaterClassesAnswer> AskAboutClassesDatedLaterAsync(string route)");
        Assert.Contains("PrimaryButtonText = AssistWording.DeployTickedButton", body);
        Assert.DoesNotContain("SecondaryButtonText", body);
        Assert.DoesNotContain("ContentDialogResult.Secondary", body);
        Assert.Contains("ClassesDatedLater.AnswerAtDeploy(flagged, boxes.Select(row => row.Box.IsChecked == true).ToList())", body);
    }

    /// <summary>
    /// Section ▸ Publish Pages… asks nothing about classes dated later and
    /// records nothing as kept (<c>classesDatedLater.neverAskedFrom</c>). Red
    /// on the code before #726, which had a LaterClasses stage there.
    /// </summary>
    [Fact]
    public void PublishPagesNeverAsks()
    {
        string source = ViewSource(Path.Combine("Views", "SectionVerbDialog.cs"));
        Assert.DoesNotContain("ClassesDatedLater.", source);
        Assert.DoesNotContain("LaterClassesKept.", source);
        Assert.DoesNotContain("Stage.LaterClasses", source);
        Assert.DoesNotContain("LaterClassesTitle", source);
    }

    /// <summary>The contract asks at Deploy only (the mac's testTheContractAsksOnlyAtDeploy).</summary>
    [Fact]
    public void TheContractAsksOnlyAtDeploy()
    {
        var rule = ContractLoader.LoadJson("shared-rules.json")["classesDatedLater"]!;
        Assert.DoesNotContain("Publish Pages", rule["askedFrom"]!.ToString());
        Assert.Contains("Publish Pages", rule["neverAskedFrom"]!.ToString());
        Assert.Contains("TICKED to go out", rule["answers"]!.ToString());
    }

    /// <summary>
    /// The hide at Deploy is Hide Pages…'s own call, and its "ran from a menu"
    /// line counts the classes as UNTICKED at Deploy (the mac's words).
    /// </summary>
    [Fact]
    public void TheHideIsCountedAsUntickedAtDeploy()
    {
        Assert.Equal("1 class dated later, unticked at Deploy", ClassesDatedLater.UntickedAtDeployCounts(1));
        Assert.Equal("3 classes dated later, unticked at Deploy", ClassesDatedLater.UntickedAtDeployCounts(3));
        string body = MethodBody(ViewSource("MainWindow.Verbs.cs"),
                                 "internal async Task<AssistToolAnswer?> HideClassesForTheDeploy(");
        Assert.Contains("ClassesDatedLater.UntickedAtDeployCounts(places.Count)", body);
    }
}
