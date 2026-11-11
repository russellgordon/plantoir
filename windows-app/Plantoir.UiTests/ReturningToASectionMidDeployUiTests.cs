using System.Diagnostics;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #728 (the mac's #706) through the real window: a section left while its
/// deploy runs and come back to shows THAT deploy, with Deploy unavailable,
/// and starts nothing; a deploy that finished while the teacher was on another
/// section is shown once, and after that the section is in its ordinary state
/// (<c>shared-rules.json</c> → <c>returningToASectionMidDeploy</c>).
/// </summary>
/// <remarks>
/// <para>Runs the real build and the real <c>deploy.ps1 --to-folder</c>, as
/// <see cref="PublishToFolderUiTests"/> does — publish-to-a-folder only. The
/// course is padded with plain pages so the deploy runs long enough to leave
/// and come back while it is still building; the build's length is printed.</para>
///
/// <para>"Starts nothing" is read off the trail: at most one build leg and
/// exactly one "started deploy.ps1" line for the section, and no "already
/// being deployed". A
/// press on a greyed control cannot be made through UI Automation (Invoke on a
/// disabled button throws), so the Deploy button is asserted unavailable, and
/// the press is tried through Section ▸ Deploy… and its key, Ctrl+Shift+D.</para>
/// </remarks>
[Collection("drives the real app")]
public class ReturningToASectionMidDeployUiTests
{
    private const string Code = "UIBACK";
    /// <summary>
    /// Enough plain pages that the deploy outlasts leaving and coming back on
    /// the i5-8365U this was written on (the whole test ran 8 m 23 s there).
    /// A faster machine can raise it with PLANTOIR_UI_PADDING_PAGES. xunit
    /// 2.9.2 has no skip decided while a test runs, so a deploy that finishes
    /// before the return fails saying so and how long it took, rather than
    /// passing on a scenario it never drove.
    /// </summary>
    private static readonly int PaddingPages =
        int.TryParse(Environment.GetEnvironmentVariable("PLANTOIR_UI_PADDING_PAGES"), out int pages) && pages > 0 ? pages : 1200;
    private static readonly TimeSpan LongEnough = TimeSpan.FromMinutes(15);

    private readonly ITestOutputHelper _output;
    public ReturningToASectionMidDeployUiTests(ITestOutputHelper output) => _output = output;

    private static string Deploying(int section) => $"Deploying {Code}-S{section}";

    private static bool Shows(DrivenApp app, string name) =>
        app.Window.FindFirstDescendant(cf => cf.ByName(name)) is { IsOffscreen: false };

    private static string[] TrailLines(DrivenApp app) => MenuBar.Trail(app).Split('\n');

    /// <summary>
    /// The deploy's launcher starts for section 1 so far: its build leg
    /// ("started preview.ps1 UIBACK 1 --build-only") and its deploy leg
    /// ("started deploy.ps1 UIBACK 1 …"). A second press that got through
    /// would add a second of either.
    /// </summary>
    private static (int Builds, int Deploys) LauncherStarts(DrivenApp app)
    {
        var lines = TrailLines(app);
        return (lines.Count(line => line.Contains($"started preview.ps1 {Code} 1 --build-only")),
                lines.Count(line => line.Contains($"started deploy.ps1 {Code} 1")));
    }

    [UiFact]
    public void ReturningShowsTheDeploy_AndStartsNothing_ThenItsEndingOnce()
    {
        string? published = null;
        using var app = new DrivenApp(courses =>
        {
            published = Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(courses)!)!, "published");
            Directory.CreateDirectory(published);
            string dir = EndToEnd.WriteCourse(courses, Code, "Back Mid Deploy", new[] { "Concepts" },
                config =>
                {
                    EndToEnd.PublishesTo(published)(config);
                    config["num_sections"] = 2;
                    config["section_numbers"] = new System.Text.Json.Nodes.JsonArray(1, 2);
                });
            Directory.CreateDirectory(Path.Combine(dir, "section2", "All Classes"));
            File.WriteAllText(Path.Combine(dir, "section2", "index.md"), $"---\ntitle: {Code}\n---\n# Section 2\n");
            for (int page = 1; page <= PaddingPages; page++)
                EndToEnd.WritePage(Path.Combine(dir, "Concepts", $"Padding {page:0000}.md"),
                    $"title: Padding {page:0000}\npublish: true", $"A page to make the build take a while ({page}).");
        });
        string siteIndex = Path.Combine(published!, "section1", "index.html");

        app.SelectSection(Code, 1);
        var deploy = app.Find("deployButton", "the Deploy button");
        Assert.True(deploy.IsEnabled, "Deploy was unavailable before anything ran");
        var pressed = Stopwatch.StartNew();
        deploy.AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => Shows(app, Deploying(1)), TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(250)).Result,
                    "the deploy never showed its progress" + app.AnsweredSoFar);

        // ---- Away to section 2 and back while it runs.
        app.SelectSection(Code, 2);
        Assert.True(Retry.WhileFalse(() => app.Find("deployButton", "section 2's Deploy button").IsEnabled,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result,
                    "another section's deploy greyed section 2's Deploy");
        app.SelectSection(Code, 1);
        Assert.False(File.Exists(siteIndex), $"the deploy finished in {pressed.Elapsed.TotalSeconds:0} s, before the test came back, so the scenario was not driven: this machine is faster than the padding allows — set PLANTOIR_UI_PADDING_PAGES above {PaddingPages}");
        Assert.True(Shows(app, Deploying(1)), "coming back showed a blank console, not the deploy still running");
        Assert.False(app.Find("deployButton", "the Deploy button").IsEnabled, "Deploy was available mid-deploy on return");
        var cancel = app.FindOrNull("taskCancelButton", TimeSpan.FromSeconds(5));
        Assert.True(cancel is { IsOffscreen: false }, "the returned deploy's Cancel cannot be reached");
        var items = MenuBar.Open(app, "Section", "sectionDeploy");
        Assert.False(items["sectionDeploy"].IsEnabled, "Section ▸ Deploy… was live mid-deploy on return");
        MenuBar.Close();
        try { EndToEnd.PressMenuBarItem(app, "Section", "sectionDeploy"); }
        catch (Exception refused)
        {
            _output.WriteLine($"the greyed Section ▸ Deploy… could not be pressed: {refused.GetType().Name}");
            MenuBar.Close();
        }
        CopyAPageEscapeUiTests.Front(app);
        Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.SHIFT, VirtualKeyShort.KEY_D);
        Thread.Sleep(1500);
        // Mid-deploy: one build leg at most, one deploy leg at most, and at
        // least one of them — neither press started a second.
        var midway = LauncherStarts(app);
        _output.WriteLine($"launcher starts after the presses: {midway.Builds} build, {midway.Deploys} deploy");
        Assert.True(midway.Builds <= 1 && midway.Deploys <= 1 && midway.Builds + midway.Deploys >= 1,
                    $"a press on return started a launcher: {midway.Builds} builds, {midway.Deploys} deploys");

        // ---- Away again while it ends; it ended while the teacher was away.
        app.SelectSection(Code, 2);
        Assert.True(app.WaitAnsweringDialogs(() => File.Exists(siteIndex)
                                                   && TrailLines(app).Any(line => line.Contains("finished deploy.ps1")),
                                             LongEnough),
                    "the deploy never finished" + app.AnsweredSoFar);
        _output.WriteLine($"deployed {PaddingPages} padding pages in {pressed.Elapsed.TotalSeconds:0} s (pressed to finished, while away)");
        Thread.Sleep(1500);
        app.SelectSection(Code, 1);
        Assert.True(Retry.WhileFalse(() => app.FindOrNull("taskPhaseLabel", TimeSpan.FromMilliseconds(300))?.Name == "Done",
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result,
                    "a deploy that finished while away did not show how it ended");
        Assert.True(Retry.WhileFalse(() => app.Find("deployButton", "the Deploy button").IsEnabled,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result,
                    "Deploy stayed unavailable after the deploy ended");

        // ---- Shown once: the next visit is the section's ordinary state.
        app.SelectSection(Code, 2);
        app.SelectSection(Code, 1);
        Assert.True(Retry.WhileFalse(() => !Shows(app, Deploying(1)), TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result,
                    "a deploy whose ending was already shown came back on the next visit");
        Assert.True(app.Find("deployButton", "the Deploy button").IsEnabled, "Deploy was unavailable in the ordinary state");

        string[] trail = TrailLines(app);
        var total = LauncherStarts(app);
        Assert.True(total.Builds <= 1 && total.Deploys == 1,
                    $"one deploy started {total.Builds} builds and {total.Deploys} deploys");
        Assert.DoesNotContain(trail, line => line.Contains("already being deployed"));
        _output.WriteLine(string.Join("\n", trail.Where(line => line.Contains("deploy.ps1") || line.Contains("preview.ps1"))));
    }
}
