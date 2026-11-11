using Plantoir.Core.Assist;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #475 through the real window (the rest of #489): a section that publishes
/// to a folder on this PC, with classes published and dated after the next
/// class. Deploy asks first, every class ticked to GO OUT (#726, the mac's
/// #694); Cancel deploys nothing and leaves the preview serving; Deploy Ticked
/// with one class unticked hides that class, keeps the ticked one and deploys;
/// Return with every class ticked keeps them all, and the next Deploy asks
/// nothing; Section ▸ Publish Pages… on a class dated later asks nothing, and
/// Deploy still does.
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
    private const string Title = AssistWording.LaterClassesTitle;
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
            // Hidden, for Publish Pages… (#726): not flagged until published.
            EndToEnd.WritePage(Path.Combine(classes, "Unit 1, Day 5.md"),
                $"title: Unit 1, Day 5\npublish: false\ncreated: {Day(5)}T07:00:00.000-0400", "Lesson: hidden for now");
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
        // One button beside Cancel (#726): Deploy Ticked, and no Keep All.
        var secondary = dialog.FindFirstDescendant(cf => cf.ByAutomationId("SecondaryButton"));
        Assert.True(secondary is null || secondary.IsOffscreen || string.IsNullOrEmpty(secondary.Name),
                    $"the question has a second button: {secondary?.Name}");
        Assert.Equal(AssistWording.DeployTickedButton, dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton"))?.Name);
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
    public void CancelDeploysNothingAndKeepsThePreview_ThenDeployTickedHidesTheUnticked()
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
        Assert.All(rows, row => Assert.True(row.AsCheckBox().IsChecked, $"{row.Name} was not ticked to go out"));
        Assert.Contains("Unit 1, Day 3", rows[0].Name);
        Assert.Contains("Unit 1, Day 4", rows[1].Name);
        Press(app, "CloseButton");
        Thread.Sleep(3000);
        Assert.False(File.Exists(SiteIndex(fixture)), "Cancel deployed the section");
        Assert.NotNull(EndToEnd.ServedFrontPage(fixture.Front));
        Assert.Contains($"{Code}/1 · asked about classes dated after the next class at Deploy — 2 flagged, cancelled",
                        MenuBar.Trail(app));
        Assert.Contains("publish: true", File.ReadAllText(Page(app, "Unit 1, Day 3")));

        // ---- Deploy Ticked, with Day 3 unticked: Day 3 hidden, Day 4 kept, deployed.
        rows = DeployAndMeetTheQuestion(app);
        rows[0].AsCheckBox().IsChecked = false;
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
        // The hide's own line names Hide Pages…, counting the class as unticked.
        Assert.Contains("1 class dated later, unticked at Deploy", MenuBar.Trail(app));
    }

    /// <summary>
    /// #634 (the mac's #608): the question is a table — Page with its box, and
    /// Date — and Space ticks the selected row exactly once, which the row
    /// tells Narrator. Cancelled, so nothing is deployed.
    /// </summary>
    [UiFact]
    public void TheQuestionIsATable_AndSpaceTicksTheSelectedRow()
    {
        var (app, fixture) = Launch();
        using var running = app;
        app.SelectSection(Code, 1);

        var rows = DeployAndMeetTheQuestion(app);
        Assert.Equal("Unit 1, Day 3", rows[0].Name);
        var row = app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("laterClassRow0"))
                  ?? throw new Xunit.Sdk.XunitException("the question's first row has no laterClassRow0");
        Assert.StartsWith("Unit 1, Day 3, ", row.Name);
        Assert.Equal("ticked", row.Properties.ItemStatus.ValueOrDefault);
        row.Patterns.SelectionItem.Pattern.Select();
        row.Focus();
        Thread.Sleep(300);
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type(FlaUI.Core.WindowsAPI.VirtualKeyShort.SPACE);
        Thread.Sleep(400);
        Assert.False(rows[0].AsCheckBox().IsChecked, "Space on the selected row did not untick it (or flipped it twice)");
        Assert.True(rows[1].AsCheckBox().IsChecked, "Space unticked a row that was not selected");
        Assert.Equal("not ticked", row.Properties.ItemStatus.ValueOrDefault);
        Press(app, "CloseButton");
        Thread.Sleep(2000);
        Assert.False(File.Exists(SiteIndex(fixture)), "Cancel deployed the section");
    }

    /// <summary>Return, with every class left ticked: all of them go out and are kept, and the next Deploy asks nothing.</summary>
    [UiFact]
    public void ReturnWithEverythingTicked_KeepsThemAll_AndTheNextDeployAsksNothing()
    {
        var (app, fixture) = Launch();
        using var running = app;
        app.SelectSection(Code, 1);

        DeployAndMeetTheQuestion(app);
        var row = app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("laterClassRow0"))
                  ?? throw new Xunit.Sdk.XunitException("the question's first row has no laterClassRow0");
        row.Patterns.SelectionItem.Pattern.Select();
        row.Focus();
        Thread.Sleep(300);
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type(FlaUI.Core.WindowsAPI.VirtualKeyShort.RETURN);
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

    /// <summary>
    /// Section ▸ Publish Pages… on a class dated later goes straight from the
    /// choice to its plan and publishes it, asking nothing and writing no kept
    /// record (#726, <c>classesDatedLater.neverAskedFrom</c>); the next Deploy
    /// still asks about it (the mac's testAClassPublishedFromTheMenuIsStillAskedAboutAtDeploy).
    /// </summary>
    [UiFact]
    public void PublishPagesNeverAsks_AndDeployStillDoes()
    {
        var (app, fixture) = Launch();
        using var running = app;
        app.SelectSection(Code, 1);

        EndToEnd.PressMenuBarItem(app, "Section", "sectionPublishPages");
        var box = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.CheckBox)
                                                                              .And(cf.ByName("Unit 1, Day 5"))),
                                  TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result
                  ?? throw new Xunit.Sdk.XunitException("Publish Pages… did not list Unit 1, Day 5." + app.AnsweredSoFar);
        box.AsCheckBox().Toggle();
        PressWhenAvailable(app, "Publish Pages… (Continue)");
        // Straight to the plan: no question in between.
        var plan = Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("sectionVerbPlan")),
                                   TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result
                   ?? throw new Xunit.Sdk.XunitException("Publish Pages… never showed its plan." + app.AnsweredSoFar);
        Assert.Null(app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("laterClass0")));
        _output.WriteLine("plan: " + plan.Name);
        PressWhenAvailable(app, "Publish Pages… (Publish)");
        Assert.NotNull(Retry.WhileNull(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("sectionVerbResult")),
                                       TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result);
        MenuBar.CloseDialog(app);

        Assert.Contains("publish: true", File.ReadAllText(Page(app, "Unit 1, Day 5")));
        Assert.False(File.Exists(Path.Combine(app.WorkspacePath, "courses", Code, ".publish_state", "section1.later-classes-kept.json")),
                     "Publish Pages… recorded a class dated later as kept");
        Assert.DoesNotContain("asked about classes dated after the next class", MenuBar.Trail(app));

        // Deploy asks about all three now, Day 5 among them; Cancel sends nothing.
        var rows = DeployAndMeetTheQuestion(app);
        Assert.Equal(3, rows.Count);
        Assert.Contains("Unit 1, Day 5", rows[2].Name);
        Press(app, "CloseButton");
        Thread.Sleep(2000);
        Assert.False(File.Exists(SiteIndex(fixture)), "Cancel deployed the section");
    }

    private static void PressWhenAvailable(DrivenApp app, string what)
    {
        var dialog = MenuBar.Dialog(app, what);
        var button = Retry.WhileNull(() => dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton")),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result
                     ?? throw new Xunit.Sdk.XunitException($"{what} has no PrimaryButton");
        Assert.True(Retry.WhileFalse(() => button.IsEnabled, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"{what}: PrimaryButton never became available");
        button.AsButton().Invoke();
    }
}
