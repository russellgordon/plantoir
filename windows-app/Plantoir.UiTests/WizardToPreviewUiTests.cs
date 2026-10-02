using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// End to end, ruling U2 (1): a course made with the wizard's Create button,
/// a line written on its front page the way a teacher writes in Obsidian, then
/// Preview pressed and the SERVED page read back over HTTP, the window's
/// preview pane shown to have LOADED that same address with status 200 (its
/// page text is reported, not asserted — Chromium's accessibility tree is not
/// the app's) — then Stop, and the address no longer answers.
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
        // Any element's name, not only Text: Chromium exposes a paragraph's
        // words as Text on one pass and as a Group's name on another, and its
        // tree is built lazily after the first UI Automation question — the
        // fourth run of bundle 11 missed it inside 60 s with Text only.
        // Run 6 saw ZERO named elements for 120 s: Chromium had not built its
        // accessibility tree at all. Focusing the view — what a screen reader
        // or a teacher's click does — makes it, so after ten quiet seconds the
        // view is given the focus, once.
        var seen = new List<string>();
        var since = DateTime.UtcNow;
        bool nudged = false;
        bool shown = Retry.WhileFalse(() =>
        {
            try
            {
                if (app.FindOrNull("previewWebView", TimeSpan.FromSeconds(1)) is not { } view) return false;
                if (!nudged && DateTime.UtcNow - since > TimeSpan.FromSeconds(10))
                {
                    nudged = true;
                    try { view.Focus(); } catch { }
                }
                seen = view.FindAllDescendants().Select(e => { try { return e.Name ?? ""; } catch { return ""; } })
                           .Where(n => n.Length > 0).ToList();
                return seen.Any(n => n.Contains(marker, StringComparison.Ordinal));
            }
            catch { return false; }
        }, TimeSpan.FromSeconds(20), TimeSpan.FromSeconds(1)).Result;
        // The page TEXT is REPORTED, not asserted. Over eight runs (bundle 11)
        // its words failed to come through UI Automation in three — once the
        // view exposed ZERO named elements for 120 s, focused or not. That is
        // Chromium's accessibility tree, which this app does not build.
        _output.WriteLine(shown
            ? $"the web view's text showed the marker {(nudged ? "after it was given the focus" : "without being focused")}"
            : $"the web view exposed {seen.Count} named elements and not the marker (Chromium's tree; see the comment)");
        var shownView = app.Find("previewWebView", "the preview in the window");
        Assert.False(shownView.IsOffscreen, "the preview's web view is not on screen");
        Assert.True(shownView.BoundingRectangle.Width > 200 && shownView.BoundingRectangle.Height > 200,
                    $"the preview's web view is drawn at {shownView.BoundingRectangle}");

        // What IS asserted (V2): the address the preview pane NAVIGATED to,
        // and that the load succeeded with 200, is the one the test read this
        // course's page from. The app publishes it for --state-dir runs only,
        // as Open in Browser's ItemStatus ("loaded 200 http://…"; the web view's own peer drops it), on every completed
        // navigation. A blank view, an error page or another folder's port
        // goes red here.
        var servedAt = new Uri(url!);
        string status = "";
        bool sameAddress = Retry.WhileFalse(() =>
        {
            try { status = app.Find("openInBrowserButton", "Open in Browser").Properties.ItemStatus.ValueOrDefault ?? ""; }
            catch { status = ""; }
            string[] parts = status.Split(' ', 3);
            return parts.Length == 3 && parts[0] == "loaded" && parts[1] == "200"
                   && Uri.TryCreate(parts[2], UriKind.Absolute, out var shownAt)
                   && shownAt.Port == servedAt.Port && shownAt.AbsolutePath == servedAt.AbsolutePath
                   && (shownAt.Host is "127.0.0.1" or "localhost");
        }, TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(500)).Result;
        Assert.True(sameAddress, $"the preview pane did not load {url}: it reported \"{status}\"");
        _output.WriteLine($"the preview pane reported \"{status}\"");

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
