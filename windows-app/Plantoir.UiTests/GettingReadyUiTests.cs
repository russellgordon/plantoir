using System.Diagnostics;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// #473: the first window after an update appears at once, while the app
/// copies what it needs into the working folder in the background — and
/// Preview and New Course wait for it, disabled with the reason, rather than
/// building from a half-copied folder. <c>documentation/12-windows-app.md</c>
/// → "Getting a folder ready after an update (#473)".
///
/// <para>The fixture makes the copy real rather than simulated: the folder's
/// copy of the subject skeletons (about 2,400 small files) is deleted before
/// launch, so the app has a genuine copy to make — several seconds on the
/// i5-8365U this was written on — and nothing in the app is stubbed.</para>
/// </summary>
[Collection("drives the real app")]
public class GettingReadyUiTests
{
    /// <summary>
    /// How long the copy of the skeletons may take before the test calls it
    /// stuck. Measured on 2026-10-08 (Lenovo 20QES70500, Intel Core i5-8365U,
    /// Windows 11 Pro 26200): 2,389 files in 5.3 s, the window shown 2.2 s
    /// after the copy started. Set at about eleven times that, because a copy
    /// on a loaded machine is slow rather than broken.
    /// </summary>
    private static readonly TimeSpan CopyPatience = TimeSpan.FromSeconds(60);

    [UiFact]
    public void TheWindowAppearsWhileTheFolderIsGotReadyAndPreviewWaitsForIt()
    {
        var launched = Stopwatch.StartNew();
        using var app = new DrivenApp(
            CourseFixtures.WriteBoth,
            beforeLaunch: workspace =>
            {
                string skeletons = Path.Combine(workspace, ".toolchain", "support", "skeletons");
                Assert.True(Directory.Exists(skeletons), "the fixture's folder had no skeletons to take away");
                Directory.Delete(skeletons, recursive: true);
                launched.Restart();
            },
            waitUntilReady: false);
        TimeSpan windowAfter = launched.Elapsed;

        // The window, the sidebar and its rows are here while the copy runs.
        Assert.True(app.Readiness() == "copying",
            $"The window should appear while the folder is still being got ready, but its status was '{app.Readiness()}' " +
            $"{windowAfter.TotalSeconds:0.0} s after launch — either the copy is no longer in the background or it finished first.");

        var add = app.Find("addCourseButton", "the + button");
        Assert.False(add.IsEnabled, "New Course was offered while the folder was still being got ready");
        Assert.Equal(ToolchainReadiness.GettingReadyMessage, add.Properties.HelpText.ValueOrDefault);

        app.SelectSection(CourseFixtures.Renamed, 1);
        var preview = app.Find("previewButton", "the Preview button");
        var deploy = app.Find("deployButton", "the Deploy button");
        if (app.Readiness() != "copying")
            Console.WriteLine("#473 fixture: the copy finished before the section opened, so the disabled Preview, " +
                              "Deploy and banner were NOT checked on this run (the window-while-copying and + checks above were).");
        else
        {
            Assert.False(preview.IsEnabled, "Preview was offered while the folder was still being got ready");
            Assert.False(deploy.IsEnabled, "Deploy was offered while the folder was still being got ready");
            Assert.Equal(ToolchainReadiness.GettingReadyMessage, preview.Properties.HelpText.ValueOrDefault);

            // The banner, once the copy has outlasted its one-second delay.
            bool bannerShown = Retry.WhileFalse(() =>
                    app.Readiness() != "copying" || HasText(app, ToolchainReadiness.GettingReadyTitle),
                TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result;
            Assert.True(bannerShown && (app.Readiness() != "copying" || HasText(app, ToolchainReadiness.GettingReadyMessage)),
                "the banner never said the folder was being got ready");
        }

        app.WaitUntilReady(CopyPatience);
        TimeSpan readyAfter = launched.Elapsed;
        Console.WriteLine($"#473 fixture: window after {windowAfter.TotalSeconds:0.0} s, folder ready after {readyAfter.TotalSeconds:0.0} s.");

        Assert.True(Retry.WhileFalse(() => preview.IsEnabled, TimeSpan.FromSeconds(10)).Result,
            "Preview stayed disabled after the folder was ready");
        Assert.True(Retry.WhileFalse(() => deploy.IsEnabled, TimeSpan.FromSeconds(10)).Result,
            "Deploy stayed disabled after the folder was ready");
        Assert.True(Retry.WhileFalse(() => add.IsEnabled, TimeSpan.FromSeconds(10)).Result,
            "New Course stayed disabled after the folder was ready");
        Assert.True(Retry.WhileFalse(() => !HasText(app, ToolchainReadiness.GettingReadyTitle), TimeSpan.FromSeconds(10)).Result,
            "the banner stayed after the folder was ready");
        Assert.True(Directory.Exists(Path.Combine(app.WorkspacePath, ".toolchain", "support", "skeletons")),
            "the folder was said to be ready but the skeletons were never copied back");
        Assert.Empty(Directory.EnumerateFiles(Path.Combine(app.WorkspacePath, "courses", ".internal", "activity"),
                                              ToolchainReadiness.MarkerPrefix + "*"));
    }

    private static bool HasText(DrivenApp app, string text)
    {
        try
        {
            return app.Window.FindFirstDescendant(cf => cf.ByControlType(ControlType.Text).And(cf.ByName(text))) is not null;
        }
        catch (System.Runtime.InteropServices.COMException) { return false; }
    }
}
