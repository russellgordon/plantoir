using FlaUI.Core.Tools;
using Plantoir.Core.Assist;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #214 (the mac's #211), MEASURED: can the scheduled-publish notice claim a
/// height the window cannot give when the window is squeezed narrow?
/// </summary>
/// <remarks>
/// <para><b>Both halves since bundle 11.</b> The notice is put on screen by
/// writing its record into this run's own state folder; the folder publish's
/// Done panel needs a real publish, which tests may run since bundle 11 (the
/// build goes to the real builds root and <c>DrivenApp</c> deletes it), so
/// <see cref="TheFolderPublishsDonePanelStaysInsideASqueezedWindow"/> measures
/// it too.</para>
///
/// <para><b>The body is the longest the notice says</b>: a success naming
/// two destinations, one of them a long folder path. The window is squeezed
/// to 500 px wide (the sidebar column alone is at least 180) and the notice's
/// height read back. The mac's fault gave thousands of points; a few hundred
/// pixels is fine. Reported in the test output and in
/// <c>%TEMP%\plantoir-214-measurement.txt</c>, and asserted against the
/// window's own height — a notice taller than its window is the bug.
/// UNPROVEN as of 2026-10-01: written while no agent could drive the desktop;
/// compiled, never run.</para>
/// </remarks>
[Collection("drives the real app")]
public class PanelHeightUnderSqueezeUiTests
{
    private readonly ITestOutputHelper _output;

    public PanelHeightUnderSqueezeUiTests(ITestOutputHelper output) => _output = output;

    [UiFact]
    public void TheScheduledPublishNoticeStaysInsideASqueezedWindow()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        string longFolder = @"C:\Users\a teacher\Documents\Websites\Introduction to Computer Science, Grade 11\Section 1\Exported site for the school's web host";
        ScheduledPublishOutcome.Record(Path.Combine(app.StateDirectory, "scheduled", "unanswered"),
            "ICS3U", 1, ScheduledPublishOutcome.Kind.Succeeded, longFolder + "|Netlify", app.WorkspacePath);

        app.SelectCourse("ICS3U");
        app.Find("sidebar-ICS3U-section1", "ICS3U Section 1").Click();
        var notice = app.Find("scheduledPublishNotice", "the scheduled-publish notice");

        var window = app.Window;
        window.Patterns.Transform.Pattern.Resize(500, 800);
        Retry.WhileFalse(() => window.BoundingRectangle.Width <= 520, TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(200));
        Thread.Sleep(800);

        var noticeBox = notice.BoundingRectangle;
        var windowBox = window.BoundingRectangle;
        string measured = $"window {windowBox.Width}x{windowBox.Height}; notice {noticeBox.Width}x{noticeBox.Height} " +
                          $"(top {noticeBox.Top - windowBox.Top} below the window's top)";
        _output.WriteLine("#214 measurement, " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + ": " + measured);
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "plantoir-214-measurement.txt"), measured + Environment.NewLine);

        Assert.True(noticeBox.Height > 0, "the notice was not drawn at all: " + measured);
        Assert.True(noticeBox.Height < windowBox.Height, "the notice claims more height than the window has: " + measured);
        Assert.True(noticeBox.Bottom <= windowBox.Bottom + 1, "the notice runs past the window's bottom edge: " + measured);
    }

    /// <summary>
    /// #214's other half (bundle 11, V5/W3): a REAL publish to a folder, then
    /// the window squeezed (it goes no narrower than 900), then the five parts
    /// of the folder publish's Done panel measured against the window — the
    /// phase, the folder sentence, Show in File Explorer, the render note and
    /// Show details. Each is an element WITH an automation peer (the panels
    /// around them never reach the tree), and a part that is missing FAILS the
    /// test rather than being skipped. Reported in
    /// <c>%TEMP%\plantoir-214-donepanel.txt</c>.
    /// </summary>
    [UiFact]
    public void TheFolderPublishsDonePanelStaysInsideASqueezedWindow()
    {
        const string code = "UISQZ4";
        using var app = new DrivenApp(courses =>
        {
            string root = Path.GetDirectoryName(Path.GetDirectoryName(courses)!)!;
            string longFolder = Path.Combine(root, "Exported site for the school's web host, Introduction to Computer Science Grade 11");
            Directory.CreateDirectory(longFolder);
            EndToEnd.WriteCourse(courses, code, "Squeezed Done Panel", new[] { "Concepts" }, EndToEnd.PublishesTo(longFolder));
        });
        app.SelectSection(code, 1);
        EndToEnd.DeployAndWait(app, TimeSpan.FromMinutes(15));

        var window = app.Window;
        window.Patterns.Transform.Pattern.Resize(500, 800);
        Thread.Sleep(1200);
        var windowBox = window.BoundingRectangle;
        var parts = new List<string>();
        foreach (string id in new[] { "taskPhaseLabel", "publishedFolderSentence", "publishedFolderButton", "publishedFolderRenderNote", "taskDetailsDisclosure" })
        {
            var part = app.Find(id, $"the Done panel's {id}");   // missing is a failure, not a skip
            var box = part.BoundingRectangle;
            Assert.False(box.IsEmpty, $"{id} is in the tree but has no size");
            parts.Add($"{id} {box.Width}x{box.Height} (bottom {box.Bottom - windowBox.Top})");
            Assert.True(box.Height < windowBox.Height, $"{id} claims more height than the window has: {box} in {windowBox}");
            Assert.True(box.Bottom <= windowBox.Bottom + 1, $"{id} runs past the window's bottom edge: {box} in {windowBox}");
        }
        string measured = $"window {windowBox.Width}x{windowBox.Height}; " + string.Join("; ", parts);
        _output.WriteLine("#214 Done panel measurement, " + DateTime.Now.ToString("yyyy-MM-dd HH:mm") + ": " + measured);
        File.WriteAllText(Path.Combine(Path.GetTempPath(), "plantoir-214-donepanel.txt"), measured + Environment.NewLine);
        Assert.Equal(5, parts.Count);
    }
}
