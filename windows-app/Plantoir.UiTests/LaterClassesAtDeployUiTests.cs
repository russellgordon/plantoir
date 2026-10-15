using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #475 through the real window (the rest of #489): a section that publishes
/// to a folder on this PC, with classes published and dated after the next
/// class. Deploy asks first; Cancel deploys nothing and leaves the preview
/// serving; Hide Ticked and Deploy hides the ticked class, keeps the unticked
/// one and deploys; Keep All and Deploy keeps every class, and the next Deploy
/// asks nothing.
/// </summary>
/// <remarks>
/// <para>Runs the real build and the real <c>deploy.ps1 --to-folder</c>, as
/// <see cref="PublishToFolderUiTests"/> does. The classes are dated from this
/// PC's real clock — the window reads it — so a run that crosses midnight
/// between laying them out and pressing Deploy could see one class fewer
/// flagged; the dates are a day apart for that reason.</para>
///
/// <para>The deploy is waited on by hand rather than with
/// <see cref="EndToEnd.DeployAndWait"/>: that helper answers every dialog with
/// its Close button, which on this question is Cancel.</para>
/// </remarks>
[Collection("drives the real app")]
public class LaterClassesAtDeployUiTests
{
    private const string Code = "UILATE";
    private const string Title = "Hide classes dated later?";
    private static readonly TimeSpan LongEnough = TimeSpan.FromMinutes(15);

    private readonly ITestOutputHelper _output;
    public LaterClassesAtDeployUiTests(ITestOutputHelper output) => _output = output;

    private static string Day(int fromToday) =>
        DateTime.Now.Date.AddDays(fromToday).ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);

    private sealed record Fixture(string Published, string Front, string Today, string LaterA, string LaterB);

    /// <summary>Today's class, tomorrow's (the next class), and two published after it.</summary>
    private static (DrivenApp App, Fixture Fixture) Launch()
    {
        var fixture = new Fixture("", EndToEnd.Marker("Front"), EndToEnd.Marker("Today"),
                                  EndToEnd.Marker("LaterA"), EndToEnd.Marker("LaterB"));
        string? published = null;
        var app = new DrivenApp(courses =>
        {
            published = Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(courses)!)!, "published");
            Directory.CreateDirectory(published);
            string dir = EndToEnd.WriteCourse(courses, Code, "Classes Dated Later", new[] { "Concepts" },
                EndToEnd.PublishesTo(published), frontPage: $"---\ntitle: {Code}\n---\n# Welcome\n\n{fixture.Front}\n");
            string classes = Path.Combine(dir, "section1", "All Classes");
            void Class(string title, int day, string marker) => EndToEnd.WritePage(Path.Combine(classes, title + ".md"),
                $"title: {title}\npublish: true\ncreated: {Day(day)}T07:00:00.000-0400", $"Lesson: {marker}");
            Class("Unit 1, Day 1", 0, fixture.Today);
            Class("Unit 1, Day 2", 1, EndToEnd.Marker("Next"));
            Class("Unit 1, Day 3", 3, fixture.LaterA);
            Class("Unit 1, Day 4", 4, fixture.LaterB);
        });
        return (app, fixture with { Published = published! });
    }

    private static string Page(DrivenApp app, string title) =>
        Path.Combine(app.WorkspacePath, "courses", Code, "section1", "All Classes", title + ".md");

    private static string SiteIndex(Fixture fixture) => Path.Combine(fixture.Published, "section1", "index.html");

    /// <summary>Press Deploy and wait for the question's rows.</summary>
    private static List<AutomationElement> DeployAndMeetTheQuestion(DrivenApp app)
    {
        app.Find("deployButton", "the Deploy button").AsButton().Invoke();
        var first = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("laterClass0")),
                                    TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result
                    ?? throw new Xunit.Sdk.XunitException("Deploy never asked about the classes dated later." + app.AnsweredSoFar);
        Assert.NotNull(first);
        var dialog = MenuBar.Dialog(app, "the question about classes dated later");
        Assert.Equal(Title, dialog.Name);
        return dialog.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.CheckBox)).ToList();
    }

    private static void Press(DrivenApp app, string buttonId)
    {
        var dialog = MenuBar.Dialog(app, "the question about classes dated later");
        dialog.FindFirstDescendant(cf => cf.ByAutomationId(buttonId))!.AsButton().Invoke();
    }

    /// <summary>Wait for a deploy to finish well, answering any other dialog (the links checklist) with Close.</summary>
    private static void WaitForTheDeploy(DrivenApp app, Fixture fixture)
    {
        Assert.True(app.WaitAnsweringDialogs(() => File.Exists(SiteIndex(fixture))
                                                   && app.FindOrNull("taskPhaseLabel", TimeSpan.FromMilliseconds(300))?.Name == "Done",
                                             LongEnough),
                    "the deploy never finished well" + app.AnsweredSoFar);
    }

    [UiFact]
    public void CancelDeploysNothingAndKeepsThePreview_ThenHideTickedHidesAndDeploys()
    {
        var (app, fixture) = Launch();
        using var running = app;
        app.SelectSection(Code, 1);

        // A serving preview, so Cancel can be seen to leave it alone.
        app.WillServe(Code, 1);
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(app.WaitAnsweringDialogs(() => EndToEnd.ServedFrontPage(fixture.Front) is not null, LongEnough),
                    "the preview never served its front page" + app.AnsweredSoFar);

        // ---- Cancel: nothing deployed, the preview still serving.
        var rows = DeployAndMeetTheQuestion(app);
        Assert.Equal(2, rows.Count);
        Assert.All(rows, row => Assert.True(row.AsCheckBox().IsChecked, $"{row.Name} was not ticked to hide"));
        Assert.Contains("Unit 1, Day 3", rows[0].Name);
        Assert.Contains("Unit 1, Day 4", rows[1].Name);
        Press(app, "CloseButton");
        Thread.Sleep(3000);
        Assert.False(File.Exists(SiteIndex(fixture)), "Cancel deployed the section");
        Assert.NotNull(EndToEnd.ServedFrontPage(fixture.Front));
        Assert.Contains($"{Code}/1 · asked about classes dated after the next class at Deploy — 2 flagged, cancelled",
                        MenuBar.Trail(app));
        Assert.Contains("publish: true", File.ReadAllText(Page(app, "Unit 1, Day 3")));

        // ---- Hide Ticked and Deploy, with Day 4 unticked: Day 3 hidden, Day 4 kept, deployed.
        rows = DeployAndMeetTheQuestion(app);
        rows[1].AsCheckBox().IsChecked = false;
        Press(app, "PrimaryButton");
        var pressed = DateTime.Now;
        WaitForTheDeploy(app, fixture);
        _output.WriteLine($"hid one class and deployed in {(DateTime.Now - pressed).TotalSeconds:0} s");

        Assert.Contains("publish: false", File.ReadAllText(Page(app, "Unit 1, Day 3")));
        Assert.Contains("publish: true", File.ReadAllText(Page(app, "Unit 1, Day 4")));
        string site = Path.Combine(fixture.Published, "section1");
        Assert.Empty(EndToEnd.FilesContaining(site, fixture.LaterA));
        Assert.NotEmpty(EndToEnd.FilesContaining(site, fixture.LaterB));
        Assert.NotEmpty(EndToEnd.FilesContaining(site, fixture.Today));
        string backups = Path.Combine(app.WorkspacePath, "courses", "_backups", Code);
        Assert.Single(Directory.GetFiles(backups, $"{Code}_backup_*_menu-section1.zip"));
        Assert.Contains($"{Code}/1 · asked about classes dated after the next class at Deploy — 2 flagged, 1 hidden, 1 kept published",
                        MenuBar.Trail(app));
        string kept = File.ReadAllText(Path.Combine(app.WorkspacePath, "courses", Code, ".publish_state", "section1.later-classes-kept.json"));
        Assert.Contains("section1/All Classes/Unit 1, Day 4", kept);
        Assert.DoesNotContain("Unit 1, Day 3", kept);
    }

    [UiFact]
    public void KeepAllDeploys_AndTheNextDeployAsksNothing()
    {
        var (app, fixture) = Launch();
        using var running = app;
        app.SelectSection(Code, 1);

        DeployAndMeetTheQuestion(app);
        Press(app, "SecondaryButton");
        WaitForTheDeploy(app, fixture);
        string site = Path.Combine(fixture.Published, "section1");
        Assert.NotEmpty(EndToEnd.FilesContaining(site, fixture.LaterA));
        Assert.NotEmpty(EndToEnd.FilesContaining(site, fixture.LaterB));
        Assert.Contains("publish: true", File.ReadAllText(Page(app, "Unit 1, Day 3")));

        // The second Deploy asks nothing: every listed class is kept at its date.
        Directory.Delete(site, recursive: true);
        int answeredBefore = app.Answered.Count;
        app.Find("deployButton", "the Deploy button").AsButton().Invoke();
        WaitForTheDeploy(app, fixture);
        Assert.DoesNotContain(app.Answered.Skip(answeredBefore), said => said.StartsWith(Title, StringComparison.Ordinal));
        Assert.Single(MenuBar.Trail(app).Split('\n'), line => line.Contains("asked about classes dated after the next class"));
        Assert.Contains($"{Code}/1 · asked about classes dated after the next class at Deploy — 2 flagged, 0 hidden, 2 kept published",
                        MenuBar.Trail(app));
    }
}
