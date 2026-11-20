using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace Plantoir.UiTests;

/// <summary>
/// #993 (D46), the Windows half, through the real window: Help ▸ About
/// Plantoir… shows six links, each one UI Automation element of control type
/// Hyperlink with its own words, enabled and keyboard-focusable, and Tab
/// reaches every one. This is what a screen reader lists and what a keyboard
/// reaches; <c>AboutDialogLinksSourceTests</c> pins the source, and the mac
/// reads the same six through its accessibility tree
/// (<c>AboutWindowLinksTests</c>). Nothing is opened: no link is pressed.
/// </summary>
[Collection("drives the real app")]
public class AboutDialogLinksUiTests
{
    /// <summary>The six links, by AutomationId, with the words each must read.</summary>
    private static readonly (string Id, string Words)[] Links =
    {
        ("aboutWebsiteLink", "https://plantoir.app"),
        ("aboutEmailLink", "support@plantoir.app"),
        ("aboutQuartzLink", "Quartz"),
        ("aboutSponsorLink", "Sponsor Jacky Zhao on GitHub"),
        ("aboutIconCreditLink", "Phosphor Icons"),
        ("aboutDesignCreditLink", "Russell Gordon"),
    };

    [UiFact]
    public void EveryLinkIsALinkOfItsOwnThatTabReaches()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        EndToEnd.PressMenuBarItem(app, "Help", "helpAbout");
        var about = MenuBar.Dialog(app, "Help > About Plantoir…");

        // What a screen reader is given: six Hyperlink elements, each with its own words.
        var hyperlinks = about.FindAllDescendants(cf => cf.ByControlType(ControlType.Hyperlink));
        var namesSeen = new List<string>();
        foreach (var link in hyperlinks) namesSeen.Add(link.Name);
        Assert.True(hyperlinks.Length == Links.Length,
                    $"the About panel exposes {hyperlinks.Length} links, not {Links.Length}: " + string.Join(", ", namesSeen));
        foreach (var (id, words) in Links)
        {
            var link = about.FindFirstDescendant(cf => cf.ByAutomationId(id))
                       ?? throw new Xunit.Sdk.XunitException($"the About panel has no {id}");
            Assert.Equal(ControlType.Hyperlink, link.ControlType);
            Assert.Equal(words, link.Name);
            Assert.True(link.IsEnabled, $"{id} reads as not enabled");
            Assert.True(link.Properties.IsKeyboardFocusable.ValueOrDefault, $"{id} cannot take keyboard focus");
            Assert.False(link.IsOffscreen, $"{id} is not on screen");
        }

        // What a keyboard reaches: Tab, from the dialog's first stop, comes to every link.
        var reached = new HashSet<string>();
        CopyAPageEscapeUiTests.Front(app);
        for (int press = 0; press < 16 && reached.Count < Links.Length; press++)
        {
            Keyboard.Type(VirtualKeyShort.TAB);
            Thread.Sleep(150);
            string focused;
            try { focused = app.Window.Automation.FocusedElement()?.AutomationId ?? ""; } catch { focused = ""; }
            foreach (var (id, _) in Links)
                if (focused == id) reached.Add(id);
        }
        var missed = new List<string>();
        foreach (var (id, _) in Links)
            if (!reached.Contains(id)) missed.Add(id);
        Assert.True(missed.Count == 0, "Tab never reached " + string.Join(", ", missed));

        MenuBar.CloseDialog(app);
    }
}
