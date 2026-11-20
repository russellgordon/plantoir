using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Plantoir.Core.Assist;

namespace Plantoir.UiTests;

/// <summary>
/// A preview that could not start says why and lets go (second review of
/// #1016). With <c>preview.ps1</c> gone from the working folder the runner
/// sets only <c>LaunchProblem</c>; the preview's wait reads that as over and
/// releases the section's leases, and the console stays up with the sentence
/// instead of collapsing back to the empty state, where nothing said why.
/// </summary>
[Collection("drives the real app")]
public class PreviewCouldNotStartUiTests
{
    [UiFact]
    public void AMissingLauncherIsShownTheButtonComesBackAndNoLeaseIsLeft()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectSection(CourseFixtures.NeverAsked, 1);
        // Removed once the folder is open and ready, so nothing puts it back.
        string launcher = Path.Combine(app.WorkspacePath, "preview.ps1");
        Assert.True(File.Exists(launcher), "the fixture folder has no preview.ps1 to remove");
        File.Delete(launcher);

        app.Find("previewButton", "the Preview button").AsButton().Invoke();

        var sentence = Retry.WhileNull(() =>
        {
            try
            {
                var found = app.Window.FindFirstDescendant(cf => cf.ByAutomationId("launchProblemText"));
                return found is not null && !found.IsOffscreen && found.Name.Contains("(preview.ps1)") ? found : null;
            }
            catch (System.Runtime.InteropServices.COMException) { return null; }
        }, TimeSpan.FromSeconds(30)).Result;
        Assert.True(sentence is not null, "the window never said why the preview could not start");

        // Still there a few seconds on: nothing collapses it again.
        Thread.Sleep(3000);
        var still = app.Window.FindFirstDescendant(cf => cf.ByAutomationId("launchProblemText"));
        Assert.True(still is not null && !still.IsOffscreen && still.Name.Contains("missing a piece it needs (preview.ps1)"),
                    "the sentence went away on its own");

        Assert.True(Retry.WhileFalse(() =>
        {
            var button = app.Find("previewButton", "the Preview button");
            return button.IsEnabled && button.Name == Plantoir.Core.Models.PreviewStartPage.Preview;
        }, TimeSpan.FromSeconds(10)).Result, "the Preview button did not come back");

        Assert.True(Retry.WhileFalse(() =>
        {
            var held = WorkLease.HeldBy(app.WorkspacePath, CourseFixtures.NeverAsked);
            return !held.Contains(WorkLease.Previewing) && !held.Contains(WorkLease.Building);
        }, TimeSpan.FromSeconds(10)).Result, "the preview's leases were left behind");
    }
}
