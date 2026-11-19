using System.Text;
using FlaUI.Core.Tools;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Assist;

namespace Plantoir.UiTests;

/// <summary>
/// The important update offer (#453) has no Skip and no Not Now, so no Close
/// button, and Escape must still close it: a window the teacher cannot leave
/// is never right. Until #979 a PreviewKeyDown on the dialog caught Escape
/// for this; the #979 review asked for it to go (a hidden key catcher), on
/// the grounds that WinUI closes a ContentDialog with no answer on Escape
/// whether or not it has a Close button. This presses it for real. The feed
/// is <see cref="UpdateInstallQuitUiTests.SignedFeed"/>, marked important;
/// nothing is installed.
/// </summary>
[Collection("drives the real app")]
public class UpdateOfferUiTests
{
    private const string Code = "UPE2O";
    private const string Version = "999.0.2";

    [UiFact]
    public void EscapeClosesTheImportantOffer_AndAnswersNotNow()
    {
        string token = Guid.NewGuid().ToString("N")[..8];
        using var feed = new UpdateInstallQuitUiTests.SignedFeed(Version, $"PlantoirSetup-979-{token}.cmd",
            Encoding.ASCII.GetBytes("@echo off\r\n"), important: true);
        using var app = new DrivenApp(
            courses => EndToEnd.WriteCourse(courses, Code, "Update Escape Course", new[] { "Concepts" }),
            extraArguments: new[]
            {
                "--update-feed-for-tests", feed.FeedUrl,
                "--update-key-for-tests", feed.PublicKey,
            });

        EndToEnd.PressMenuBarItem(app, "File", "fileCheckForUpdates");
        var offer = Retry.WhileNull(() => app.OpenDialog() is { } dialog && dialog.Name.Contains(Version) ? dialog : null,
                                    TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(500)).Result;
        Assert.True(offer is not null, "the important offer never appeared");
        Assert.Null(offer!.FindFirstDescendant(cf => cf.ByAutomationId("CloseButton")));
        Assert.Null(offer.FindFirstDescendant(cf => cf.ByAutomationId("SecondaryButton")));

        CopyAPageEscapeUiTests.Front(app);
        Keyboard.Type(VirtualKeyShort.ESCAPE);
        Assert.True(Retry.WhileFalse(() => app.OpenDialog() is null, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    "Escape left the important offer up");
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains($"{Version}: not now"),
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result,
                    "the trail does not say the offer was answered \"not now\"");
        Assert.True(app.Window.IsAvailable, "Escape on the offer quit the app");
    }
}
