using FlaUI.Core.Tools;
using Plantoir.Core.Assist;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #214 (the mac's #211), MEASURED: can the scheduled-publish notice claim a
/// height the window cannot give when the window is squeezed narrow?
/// </summary>
/// <remarks>
/// <para><b>Why the notice and not the folder publish's Done panel.</b> Both
/// are wrapping <c>TextBlock</c>s in Auto rows, the same construct; the notice
/// can be put on screen by writing its record into this run's own state
/// folder, while the Done panel needs a real publish — which builds into the
/// teacher's REAL builds folder, since <c>--state-dir</c> redirects only what
/// the app resolves (documentation/12, "Driving the real interface"). The
/// Done panel stays unmeasured, and the issue says so.</para>
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
}
