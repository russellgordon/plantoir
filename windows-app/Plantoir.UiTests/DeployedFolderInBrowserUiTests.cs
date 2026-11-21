using System.Net.Http;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// #889 (the mac's #850) through the real window: a section deployed to a
/// folder is opened in the browser by the toolbar's Open in Browser while no
/// preview shows, the address handed to the browser is recorded in the run's
/// <c>links-opened.txt</c> (<c>ExternalLinks</c>: a redirected run opens no
/// browser) and answers with the deployed page; the notice says so with Stop,
/// Section ▸ Stop Showing Deployed Folder is live, and Stop ends it. The
/// trail carries the three events' lines, counts only.
/// </summary>
[Collection("drives the real app")]
public class DeployedFolderInBrowserUiTests
{
    private const string Code = "UIDFOL";
    private readonly ITestOutputHelper _output;
    public DeployedFolderInBrowserUiTests(ITestOutputHelper output) => _output = output;

    private static void CaptureIfAsked(string fileName)
    {
        if (Environment.GetEnvironmentVariable("PLANTOIR_UI_CAPTURE_DIR") is not { Length: > 0 } folder) return;
        Directory.CreateDirectory(folder);
        FlaUI.Core.Capturing.Capture.Screen().ToFile(Path.Combine(folder, fileName));
    }

    private static string? LastLinkOpened(DrivenApp app)
    {
        string file = Path.Combine(app.StateDirectory, "links-opened.txt");
        return File.Exists(file) ? File.ReadAllLines(file).LastOrDefault(line => line.Length > 0) : null;
    }

    /// <summary>
    /// MUST FAIL with the toolbar's button left on the preview alone (it stays
    /// dimmed with no preview), or Stop Showing Deployed Folder not drawn in
    /// the Section menu.
    /// </summary>
    /// <summary>
    /// #1027's review, low 2, both halves. (1) <c>offeredWhen</c>, "when a
    /// menu opens", by a route with no pointer: the deployed folder is made
    /// behind the window's back (as a scheduled deploy would), and the
    /// Section menu opened through UI Automation, as the keyboard opens it,
    /// comes to offer Open in Browser. MUST FAIL with the offer read only on
    /// the pointer route. (2) The folder taken away again behind the window,
    /// a press of the still-live toolbar button says why in the could-not-open
    /// dialog and the button then dims. MUST FAIL with the press left silent.
    /// </summary>
    [UiFact]
    public void AMenuOpenedWithoutThePointerReadsTheOffer_AndAPressNoLongerOfferedSaysWhy()
    {
        string deployed = Path.Combine(Path.GetTempPath(), "plantoir-1027-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var app = new DrivenApp(courses =>
                EndToEnd.WriteCourse(courses, Code, "Deployed Folder Course", new[] { "Concepts" }, EndToEnd.PublishesTo(deployed)));
            app.SelectSection(Code, 1);
            var button = app.Find("openInBrowserButton", "Open in Browser");
            Assert.False(button.IsEnabled, "Open in Browser was live before the deployed folder existed");

            Directory.CreateDirectory(Path.Combine(deployed, "section1"));
            File.WriteAllText(Path.Combine(deployed, "section1", "index.html"), "<html><body>Deployed</body></html>");
            var section = MenuBar.Open(app, "Section", "sectionOpenInBrowser");
            Assert.True(Retry.WhileFalse(() => section["sectionOpenInBrowser"].IsEnabled, TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result,
                        "Section > Open in Browser stayed dimmed in a menu opened without the pointer, with the deployed folder there");
            MenuBar.Close();
            Assert.True(Retry.WhileFalse(() => button.IsEnabled, TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result,
                        "the toolbar's Open in Browser did not follow the menu's read");

            Directory.Delete(deployed, recursive: true);
            button.AsButton().Invoke();
            var dialog = Retry.WhileNull(() => app.Window.FindFirstDescendant(cf => cf.ByAutomationId("deployedFolderCouldNotOpen")),
                                         TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result
                         ?? throw new Xunit.Sdk.XunitException("a press of Open in Browser with the folder gone said nothing");
            string why = Plantoir.Core.Models.DeployedFolderWording.FolderNotFound;
            // The dialog's content is drawn after the dialog itself: waited for on UI Automation, as every element here is.
            Assert.True(Retry.WhileFalse(() => dialog.FindAllDescendants().Any(element => element.Properties.Name.ValueOrDefault == why),
                                         TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result,
                        "the could-not-open dialog did not give the greyed reason: " +
                        string.Join(" | ", dialog.FindAllDescendants().Select(element => element.Properties.Name.ValueOrDefault ?? "")));
            MenuBar.CloseDialog(app);
            Assert.True(Retry.WhileFalse(() => !button.IsEnabled, TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result,
                        "Open in Browser stayed live after a press found the folder gone");
        }
        finally { try { Directory.Delete(deployed, recursive: true); } catch { } }
    }

    [UiFact]
    public void OpenInBrowserShowsTheDeployedFolder_AndStopEndsIt()
    {
        string deployed = Path.Combine(Path.GetTempPath(), "plantoir-889-" + Guid.NewGuid().ToString("N"));
        string marker = EndToEnd.Marker("Deployed");
        Directory.CreateDirectory(Path.Combine(deployed, "section1"));
        File.WriteAllText(Path.Combine(deployed, "section1", "index.html"), $"<html><body>{marker}</body></html>");
        try
        {
            using var app = new DrivenApp(courses =>
                EndToEnd.WriteCourse(courses, Code, "Deployed Folder Course", new[] { "Concepts" }, EndToEnd.PublishesTo(deployed)));
            app.SelectSection(Code, 1);

            var button = app.Find("openInBrowserButton", "Open in Browser");
            Assert.True(Retry.WhileFalse(() => button.IsEnabled, TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result,
                        "Open in Browser stayed dimmed for a section deployed to a folder");
            // Named as the Mac labels it, the sentence its help text (lane B review, low 7).
            Assert.Equal(Plantoir.Core.Models.DeployedFolderWording.MenuItem, button.Name);
            Assert.Equal(Plantoir.Core.Models.DeployedFolderWording.Help, button.HelpText);
            var closed = MenuBar.Open(app, "Section", "sectionOpenInBrowser");
            Assert.True(closed["sectionOpenInBrowser"].IsEnabled, "Section > Open in Browser was dimmed");
            Assert.False(closed["sectionStopShowingDeployedFolder"].IsEnabled, "Stop Showing Deployed Folder was live before anything was shown");
            MenuBar.Close();

            button.AsButton().Invoke();
            var notice = app.Find("deployedFolderNotice", "the deployed folder's notice");
            Assert.True(Retry.WhileNull(() => LastLinkOpened(app), TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result is not null,
                        "no address was handed to the browser");
            string address = LastLinkOpened(app)!;
            _output.WriteLine("opened " + address);
            Assert.StartsWith("http://127.0.0.1:", address);
            using (var http = new HttpClient())
                Assert.Contains(marker, http.GetStringAsync(address).GetAwaiter().GetResult());
            CaptureIfAsked("windows-deployed-folder-notice.png");

            var open = MenuBar.Open(app, "Section", "sectionStopShowingDeployedFolder");
            Assert.True(open["sectionStopShowingDeployedFolder"].IsEnabled, "Stop Showing Deployed Folder stayed dimmed while shown");
            CaptureIfAsked("windows-section-menu-deployed-folder.png");
            MenuBar.Close();
            EndToEnd.PressMenuBarItem(app, "Section", "sectionStopShowingDeployedFolder");
            Assert.True(Retry.WhileFalse(() => app.Desktop.FindFirstDescendant(cf => cf.ByAutomationId("deployedFolderNoticeButton")) is null,
                                         TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result,
                        "the notice stayed after Stop");
            using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) })
                Assert.ThrowsAny<Exception>(() => http.GetStringAsync(address).GetAwaiter().GetResult());

            string trail = MenuBar.Trail(app);
            Assert.Contains($"{Code}/1 · ", trail);
            Assert.Contains($"{Code}/1 · " + Plantoir.Core.Models.DeployedFolderTrail.OpenedLine(
                                Plantoir.Core.Models.DeployedFolderFrom.Toolbar, alreadyOpen: false, addressMoved: false), trail);
            Assert.Contains($"{Code}/1 · stopped showing the deployed folder in the web browser — " +
                            Plantoir.Core.Models.DeployedFolderTrail.ReasonWords(Plantoir.Core.Models.DeployedFolderStopReason.StopPressed), trail);
            Assert.DoesNotContain(address, trail);
            Assert.DoesNotContain(deployed, trail);
        }
        finally { try { Directory.Delete(deployed, recursive: true); } catch { } }
    }
}
