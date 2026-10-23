using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.Core.WindowsAPI;
using Plantoir.Core.Models;
using Xunit.Abstractions;

namespace Plantoir.UiTests;

/// <summary>
/// Preview at Last Viewed (#514; the mac's #504) through the real window:
/// File ▸ Settings ▸ Preview saves the choice and re-titles the button and
/// both Section items; Alt re-titles the button and Alt+click opens the other
/// start page; a teacher's click in the pane is remembered and the app's own
/// Reload is not. Written 2026-10-15 with the desktop LOCKED: UNPROVEN until
/// their first run on an unlocked desktop.
/// </summary>
[Collection("drives the real app")]
public class PreviewStartPageUiTests
{
    private const string Code = "PSP2O";
    private const string Page = "Concepts/Lesson-Marker";
    private static readonly TimeSpan LongEnoughToBuild = TimeSpan.FromMinutes(15);
    private readonly ITestOutputHelper _output;

    public PreviewStartPageUiTests(ITestOutputHelper output) => _output = output;

    private static JsonNode Contract => EndToEnd.Contract()["previewStartPage"]!;

    /// <summary>A course whose front page links to one page (the link a teacher clicks).</summary>
    private static Action<string> ACourse(string marker) => courses =>
    {
        string dir = EndToEnd.WriteCourse(courses, Code, "Start Page Course", new[] { "Concepts" },
            frontPage: $"---\ntitle: {Code}\n---\n# Front\n\n{marker}\n\n[[{Page}|Lesson Marker]]\n");
        EndToEnd.WritePage(Path.Combine(dir, "Concepts", "Lesson-Marker.md"), "title: Lesson Marker\npublish: true", "The lesson.");
    };

    private static string StateOf(string workspace) => Path.Combine(Path.GetDirectoryName(workspace)!, "state");

    private static void Seed(string workspace, string? setting, string? remembered)
    {
        string state = StateOf(workspace);
        if (setting is not null)
        {
            string path = Path.Combine(state, "settings.json");
            var json = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))!.AsObject() : new JsonObject();
            json["PreviewOpensAt"] = setting;
            File.WriteAllText(path, json.ToJsonString(), new UTF8Encoding(false));
        }
        if (remembered is not null)
        {
            var pages = new JsonArray(new JsonObject
            {
                ["folder"] = workspace, ["course"] = Code, ["section"] = 1, ["path"] = remembered,
                ["noted"] = "2026-10-15T12:00:00Z",
            });
            File.WriteAllText(Path.Combine(state, "last-viewed-pages.json"),
                new JsonObject { ["pages"] = pages }.ToJsonString(), new UTF8Encoding(false));
        }
    }

    private static string? Remembered(DrivenApp app)
    {
        string path = Path.Combine(app.StateDirectory, "last-viewed-pages.json");
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var pages = JsonNode.Parse(new StreamReader(stream).ReadToEnd())!["pages"]!.AsArray();
            return pages.FirstOrDefault(p => p!["course"]!.ToString() == Code && p["section"]!.GetValue<int>() == 1)?["path"]?.ToString();
        }
        catch { return null; }
    }

    private static string Loaded(DrivenApp app)
    {
        try { return app.Find("openInBrowserButton", "Open in Browser").Properties.ItemStatus.ValueOrDefault ?? ""; }
        catch { return ""; }
    }

    private static string ButtonName(DrivenApp app) => app.Find("previewButton", "the Preview button").Name;

    [UiFact]
    public void SettingsPreviewSavesTheChoiceAndTheTitlesFollowIt()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectSection(CourseFixtures.NeverAsked, 1);
        Assert.Equal(Contract["wording"]!["preview"]!.ToString(), ButtonName(app));

        EndToEnd.PressMenuBarItem(app, "File", "fileSettings");
        var settings = app.FindTopLevel("settingsWindow", "the Settings window");
        var item = Retry.WhileNull(() => settings.FindFirstDescendant(cf => cf.ByAutomationId("settingsPreview")), TimeSpan.FromSeconds(10)).Result;
        Assert.NotNull(item);
        Assert.Equal(Contract["wording"]!["paneTitle"]!.ToString(), item!.Name);
        item.Patterns.SelectionItem.Pattern.Select();

        var front = Retry.WhileNull(() => settings.FindFirstDescendant(cf => cf.ByAutomationId("previewStartPageFrontPage")), TimeSpan.FromSeconds(10)).Result;
        var last = settings.FindFirstDescendant(cf => cf.ByAutomationId("previewStartPageLastViewed"));
        Assert.NotNull(front);
        Assert.Equal(Contract["wording"]!["frontPageChoice"]!.ToString(), front!.Name);
        Assert.Equal(Contract["wording"]!["lastViewedChoice"]!.ToString(), last.Name);
        Assert.True(front.Patterns.SelectionItem.Pattern.IsSelected.Value, "the front page is not the default");
        Assert.Contains(Contract["windowsWording"]!["altNote"]!.ToString(), DrivenApp.TextsUnder(settings));

        last.Patterns.SelectionItem.Pattern.Select();
        string settingsJson = Path.Combine(app.StateDirectory, "settings.json");
        Assert.True(Retry.WhileFalse(() => File.ReadAllText(settingsJson).Contains("\"PreviewOpensAt\":\"lastViewed\"")
                                           || File.ReadAllText(settingsJson).Contains("\"PreviewOpensAt\": \"lastViewed\""),
                                     TimeSpan.FromSeconds(5)).Result, "the choice never reached settings.json");
        string line = Contract["settingChangedTrail"]!.AsArray().Single(c => c!["choice"]!.ToString() == "lastViewed")!["trail"]!.ToString();
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains(line), TimeSpan.FromSeconds(5)).Result, $"the trail never said \"{line}\"");

        // The button, live, and both Section items.
        string atLast = Contract["wording"]!["previewAtLastViewed"]!.ToString();
        Assert.True(Retry.WhileFalse(() => ButtonName(app) == atLast, TimeSpan.FromSeconds(5)).Result, $"the button reads {ButtonName(app)}");
        settings.AsWindow().Close();
        var section = MenuBar.Open(app, "Section", "sectionPreview");
        Assert.Equal(atLast, section["sectionPreview"].Name);
        Assert.Equal(Contract["wording"]!["preview"]!.ToString(), section["sectionPreviewAlternate"].Name);
        Assert.True(section["sectionPreviewAlternate"].IsEnabled, "the second Preview item is greyed with nothing in the way");
        MenuBar.Close();
    }

    [UiFact]
    public void HoldingAltRetitlesTheButtonAndLettingGoPutsItBack()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectSection(CourseFixtures.NeverAsked, 1);
        app.BringToFront();
        using (Keyboard.Pressing(VirtualKeyShort.ALT))
        {
            Assert.True(Retry.WhileFalse(() => ButtonName(app) == PreviewStartPage.PreviewAtLastViewed, TimeSpan.FromSeconds(3)).Result,
                        $"holding Alt left the button reading {ButtonName(app)}");
        }
        Assert.True(Retry.WhileFalse(() => ButtonName(app) == PreviewStartPage.Preview, TimeSpan.FromSeconds(3)).Result,
                    $"letting Alt go left the button reading {ButtonName(app)}");
    }

    [UiFact]
    public void AltClickOpensThePageLastViewedAndTheTrailSaysSo()
    {
        string marker = EndToEnd.Marker("AltClick");
        using var app = new DrivenApp(ACourse(marker), beforeLaunch: folder => Seed(folder, "frontPage", Page));
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        app.BringToFront();
        var button = app.Find("previewButton", "the Preview button");
        using (Keyboard.Pressing(VirtualKeyShort.ALT))
        {
            app.ClickMiddleOf(button);
            // Held a moment past the click, as a hand does: WinUI raises Click
            // from its own input queue, after the mouse's button is up, and
            // the press reads the keyboard THEN. Released at once (measured
            // 2026-10-15, the first unlocked run, twice), the press read Alt
            // as up and opened the front page.
            Thread.Sleep(500);
        }

        Assert.True(app.WaitAnsweringDialogs(() => Loaded(app).Contains("/" + Page), LongEnoughToBuild),
                    $"the pane never opened {Page}; it says \"{Loaded(app)}\"" + app.AnsweredSoFar);
        Assert.Contains($"{Code}/1 · started preview at {Page}", MenuBar.Trail(app));
    }

    [UiFact]
    public void ATeachersClickIsRememberedAndTheAppsOwnReloadIsNot()
    {
        string marker = EndToEnd.Marker("Remember");
        using var app = new DrivenApp(ACourse(marker), beforeLaunch: folder => Seed(folder, "lastViewed", null));
        app.SelectSection(Code, 1);
        app.WillServe(Code, 1);
        Assert.Equal(PreviewStartPage.PreviewAtLastViewed, ButtonName(app));
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(app.WaitAnsweringDialogs(() => EndToEnd.ServedFrontPage(marker) is not null && Loaded(app).StartsWith("loaded"), LongEnoughToBuild),
                    "the preview never served its front page" + app.AnsweredSoFar);
        Assert.True(Retry.WhileFalse(() => MenuBar.Trail(app).Contains("started preview at the front page because no page had been viewed yet"),
                                     TimeSpan.FromSeconds(10)).Result, "the trail never said nothing had been viewed yet");
        Assert.Null(Remembered(app));   // the app's own first load is not the teacher's

        // A real click on the page's link, in Chromium's own accessibility tree.
        var link = Retry.WhileNull(() => app.Window.FindFirstDescendant(cf =>
            cf.ByControlType(ControlType.Hyperlink).And(cf.ByName("Lesson Marker"))), TimeSpan.FromSeconds(60)).Result;
        Assert.True(link is not null, "the web view's accessibility tree never offered the link (seen in 3 of 8 bundle-11 runs; re-run alone)");
        // The harness's window is short at 150% on a 1920 x 1080 screen
        // (measured 2026-10-15, the first unlocked run: the link sat below
        // the pane, "Lesson Marker is off screen"), so the page is scrolled
        // to the link first, as a teacher would.
        link!.Patterns.ScrollItem.PatternOrDefault?.ScrollIntoView();
        Assert.True(Retry.WhileTrue(() => link.IsOffscreen, TimeSpan.FromSeconds(5)).Result, "the link could not be scrolled into view");
        app.BringToFront();
        app.ClickMiddleOf(link);
        Assert.True(Retry.WhileFalse(() => Remembered(app) == Page, TimeSpan.FromSeconds(15)).Result,
                    $"the teacher's click was not remembered; the store holds {Remembered(app) ?? "nothing"}");

        // View ▸ Reload Page is the app's own load: what is remembered stays.
        EndToEnd.PressMenuBarItem(app, "View", "viewReloadPage");
        Thread.Sleep(3000);
        Assert.Equal(Page, Remembered(app));

        // Stop, and Preview again: the page last viewed.
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(Retry.WhileFalse(() => ButtonName(app) == PreviewStartPage.PreviewAtLastViewed, TimeSpan.FromSeconds(60)).Result,
                    "the preview did not stop");
        app.Find("previewButton", "the Preview button").AsButton().Invoke();
        Assert.True(app.WaitAnsweringDialogs(() => Loaded(app).Contains("/" + Page), LongEnoughToBuild),
                    $"Preview at Last Viewed did not open {Page}; the pane says \"{Loaded(app)}\"" + app.AnsweredSoFar);
        _output.WriteLine(MenuBar.Trail(app));
    }
}
