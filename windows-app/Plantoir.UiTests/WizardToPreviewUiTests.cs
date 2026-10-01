using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// End to end, ruling U2 (1): a course made with the wizard's Create button,
/// a line written on its front page the way a teacher writes in Obsidian, then
/// Preview pressed and the SERVED page read back over HTTP and from the
/// window's own web view — then Stop, and the address no longer answers.
/// </summary>
/// <remarks>
/// <para>Runs the real <c>setup.ps1</c> and <c>preview.ps1</c>. The build lands
/// in the REAL builds root for this run's temporary working folder
/// (<see cref="DrivenApp.RealBuildsRoot"/>) and is read back from there too;
/// <see cref="DrivenApp.Dispose"/> stops the serve with the launcher's own
/// <c>--stop</c> and deletes that folder, failed test or not.</para>
/// <para>Nothing here is "a preview started": the front page's marker has to
/// come back from the server, which only a build of THIS course's notes can
/// put there.</para>
/// </remarks>
[Collection("drives the real app")]
public class WizardToPreviewUiTests
{
    private const string Code = "MFM2P";   // skeleton path: no ready-made pages
    private static readonly TimeSpan LongEnoughToBuild = TimeSpan.FromMinutes(15);

    private readonly ITestOutputHelper _output;
    public WizardToPreviewUiTests(ITestOutputHelper output) => _output = output;

    [UiFact]
    public void ACourseMadeInTheWizardPreviewsItsOwnFrontPageAndStops()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        var started = DateTime.Now;

        // ---- The wizard, as a teacher uses it.
        NewCourseWizardUiTests.OpenWizard(app);
        NewCourseWizardUiTests.PutCodeIn(app, Code);
        var create = app.Find("PrimaryButton", "the wizard's Create button");
        Assert.True(Retry.WhileFalse(() => create.IsEnabled, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result,
                    $"Create never became available for {Code}");
        create.AsButton().Invoke();
        NewCourseWizardUiTests.WaitForTheWorkToFinish(app);
        create.AsButton().Invoke();   // Close
        Assert.NotNull(Retry.WhileNull(() => app.FindOrNull($"sidebar-{Code}-section1", TimeSpan.FromSeconds(1)),
                                       TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result);
        _output.WriteLine($"created {Code} in {(DateTime.Now - started).TotalSeconds:0} s");

        // ---- The teacher writes on the front page.
        string marker = EndToEnd.Marker("Front");
        string front = Path.Combine(app.WorkspacePath, "courses", Code, "section1", "index.md");
        Assert.True(File.Exists(front), "the wizard made no front page");
        File.AppendAllText(front, $"\n\nThis week: {marker}\n");

        // ---- Preview.
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        var previewPressed = DateTime.Now;
        app.Find("previewButton", "the Preview button").AsButton().Invoke();

        string? url = null;
        bool served = app.WaitAnsweringDialogs(() => (url = EndToEnd.ServedFrontPage(marker)) is not null, LongEnoughToBuild);
        Assert.True(served,
            $"no preview served {Code}'s front page within {LongEnoughToBuild.TotalMinutes} minutes."
            + NewCourseWizardUiTests.Explanation(app) + app.AnsweredSoFar + NewCourseWizardUiTests.ConsoleTail(app));
        _output.WriteLine($"served at {url} {(DateTime.Now - previewPressed).TotalSeconds:0} s after Preview");

        // The window noticed too: Stop Preview and Open in Browser are offered...
        Assert.True(Retry.WhileFalse(() => app.Find("openInBrowserButton", "Open in Browser").IsEnabled,
                                     TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(500)).Result,
                    "the server answered, but the window never offered Open in Browser");
        // ...and the web view in the window SHOWS the page (its text, through UI Automation).
        Assert.True(Retry.WhileFalse(() => app.FindOrNull("previewWebView", TimeSpan.FromSeconds(1)) is { } view
                                           && DrivenApp.TextsUnder(view).Any(t => t.Contains(marker, StringComparison.Ordinal)),
                                     TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(500)).Result,
                    "the server has the page, but the window's own preview never showed it");

        // And the build is where the launchers keep it: the real builds root, not the working folder.
        string builtIndex = Path.Combine(app.RealBuildsRoot, Code, "section1", "public", "index.html");
        Assert.True(File.Exists(builtIndex), $"no built front page at {builtIndex}");
        Assert.Contains(marker, File.ReadAllText(builtIndex));
        Assert.False(Directory.Exists(Path.Combine(app.WorkspacePath, "courses", Code, ".merged_output", "section1", "public")),
                     "the build was written inside the working folder");

        // ---- Stop: the same button, and the address goes quiet.
        app.Find("previewButton", "the Stop Preview button").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => !EndToEnd.Answers(url!), TimeSpan.FromSeconds(90), TimeSpan.FromSeconds(1)).Result,
                    $"{url} still answered 90 seconds after Stop Preview");
        // The button's name is its label's text when it has no name of its own.
        Assert.True(Retry.WhileFalse(() => (app.FindOrNull("PreviewLabel", TimeSpan.FromSeconds(1))?.Name
                                            ?? app.Find("previewButton", "the Preview button").Name) == "Preview",
                                     TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result,
                    "the button never went back to Preview");
    }
}
