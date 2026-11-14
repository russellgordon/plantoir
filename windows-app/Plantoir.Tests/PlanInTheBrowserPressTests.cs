using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Open in Browser PRESSED (#820 items 2 to 5): the rule asked again at the
/// click, the browser handed only a page of the plan (the mac's
/// <c>testOpenInBrowserHandsTheBrowserOnlyAPageOfThePlan</c>, here for every
/// <c>openInBrowser</c> case through a recording browser), the alert's words,
/// the default browser asked BY NAME with nothing started when there is none,
/// and the three trail events' lines as the window writes them. In the shared
/// collection: these write the process's trail.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class PlanInTheBrowserPressTests : IDisposable
{
    private readonly string _trail = Path.Combine(Path.GetTempPath(), "plantoir-press-" + Guid.NewGuid().ToString("N"), "activity.txt");

    public PlanInTheBrowserPressTests()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_trail)!);
        ActivityTrail.SetCustomLogPathForTesting(_trail);
    }

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(Path.GetDirectoryName(_trail)!, recursive: true); } catch { }
    }

    private string[] TrailLines() => File.Exists(_trail) ? File.ReadAllLines(_trail) : Array.Empty<string>();

    private sealed class Recording : PlanInTheBrowser.IBrowser
    {
        public List<string> Handed { get; } = new();
        public PlanInTheBrowser.Opening Answer { get; init; } = PlanInTheBrowser.Opening.Opened;
        public PlanInTheBrowser.Opening Open(string fileUri) { Handed.Add(fileUri); return Answer; }
    }

    private static JsonArray Cases() => PlanningTabTests.Tab()["openInBrowser"]!["cases"]!.AsArray();

    /// <summary>
    /// #820 item 5, for every case (against the link map, so the three
    /// file-link cases run too): a refused case hands the browser NOTHING and
    /// writes nothing; an opened one hands it exactly that page's file:
    /// address, once, and writes one line naming the kind.
    /// </summary>
    [Fact]
    public void TheBrowserIsHandedOnlyAPageOfThePlan()
    {
        Assert.True(Cases().Count >= 23);
        foreach (var testCase in Cases())
        {
            string name = testCase!["name"]!.ToString();
            string course = @"C:\plantoir-not-on-disk\press\SNC2D";
            string planning = UnitPlans.PlanningFolder(course);
            var map = new LocalSiteFixtures.LinkMap().Folder(planning).File(Path.Combine(course, "course_config.json"));
            foreach (var made in testCase["made"]!.AsArray())
                map.File(Path.GetFullPath(Path.Combine(planning, Uri.UnescapeDataString(made!.ToString()).Replace('/', '\\'))));
            if (testCase["links"] is JsonObject links)
                foreach (var (at, to) in links) map.Link(Path.Combine(planning, at.Replace('/', '\\')), to!.ToString());
            var guard = new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes, map);
            string baseAddress = guard.RootAddress!;
            var browser = new Recording();
            int before = TrailLines().Length;

            var pressed = PlanInTheBrowser.Press(LocalSiteFixtures.Address(testCase["onScreen"]?.ToString(), guard, baseAddress),
                                                 LocalSiteFixtures.Address(testCase["chosen"]?.ToString(), guard, baseAddress),
                                                 guard, browser, "SNC2D");
            var written = TrailLines().Skip(before).ToList();
            if (testCase["expect"]!["opens"] is null)
            {
                Assert.True(browser.Handed.Count == 0, $"{name}: the browser was handed {string.Join(", ", browser.Handed)}");
                Assert.True(written.Count == 0, $"{name}: a refusal wrote {string.Join(" | ", written)}");
                Assert.Equal(PlanInTheBrowser.Sentence(pressed.Answer.Refusal!.Value), pressed.Alert);
            }
            else
            {
                Assert.Equal(new[] { pressed.Answer.FileUri! }, browser.Handed);
                Assert.Equal(pressed.Answer.Path, new Uri(browser.Handed[0]).LocalPath);
                Assert.Single(written);
                Assert.EndsWith(PlanInTheBrowser.TrailText("SNC2D", pressed.Answer.Kind!.Value), written[0]);
                Assert.Null(pressed.Alert);
            }
        }
    }

    [Theory]
    [InlineData(PlanInTheBrowser.Opening.NoBrowser)]
    [InlineData(PlanInTheBrowser.Opening.CouldNotOpen)]
    public void ABrowserThatDidNotTakeThePageIsAnAlertAndTheCouldNotOpenLine(PlanInTheBrowser.Opening opening)
    {
        string root = Path.Combine(Path.GetDirectoryName(_trail)!, "SNC2D");
        string planning = UnitPlans.PlanningFolder(root);
        Directory.CreateDirectory(Path.Combine(planning, "unit-1"));
        string page = Path.Combine(planning, "unit-1", "index.html");
        File.WriteAllText(page, "<p>plan</p>");
        var guard = new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes);

        var pressed = PlanInTheBrowser.Press(guard.AddressOf(page), null, guard, new Recording { Answer = opening }, "SNC2D");

        Assert.Equal(opening == PlanInTheBrowser.Opening.NoBrowser
                         ? PlanningTabWording.OpenInBrowserNoBrowser : PlanningTabWording.OpenInBrowserCouldNotOpen, pressed.Alert);
        Assert.DoesNotContain("Mac", pressed.Alert);
        Assert.EndsWith(PlanInTheBrowser.CouldNotOpenTrailText("SNC2D", PlanInTheBrowser.Kind.Plan), Assert.Single(TrailLines()));
    }

    /// <summary>#820 item 3: with no browser for https: NOTHING is started, and the answer is NoBrowser.</summary>
    [Fact]
    public void WithNoBrowserSetNothingIsStarted()
    {
        int started = 0;
        var browser = new WindowsDefaultBrowser(progId: () => null, start: (_, _) => { started++; return true; });
        Assert.Equal(PlanInTheBrowser.Opening.NoBrowser, browser.Open("file:///C:/x/index.html"));
        Assert.Equal(0, started);
        var emptyName = new WindowsDefaultBrowser(progId: () => " ", start: (_, _) => { started++; return true; });
        Assert.Equal(PlanInTheBrowser.Opening.NoBrowser, emptyName.Open("file:///C:/x/index.html"));
        Assert.Equal(0, started);
    }

    /// <summary>The browser is started with the https: class and the page's address, and nothing else; a shell that refuses is CouldNotOpen.</summary>
    [Fact]
    public void TheHttpsClassIsWhatIsAskedToOpenThePage()
    {
        var seen = new List<(string ProgId, string Uri)>();
        var browser = new WindowsDefaultBrowser(progId: () => "MSEdgeHTM", start: (progId, uri) => { seen.Add((progId, uri)); return true; },
                                                redirected: () => false);
        Assert.Equal(PlanInTheBrowser.Opening.Opened, browser.Open("file:///C:/x/index.html"));
        Assert.Equal(new[] { ("MSEdgeHTM", "file:///C:/x/index.html") }, seen);
        var refusing = new WindowsDefaultBrowser(progId: () => "MSEdgeHTM", start: (_, _) => false, redirected: () => false);
        Assert.Equal(PlanInTheBrowser.Opening.CouldNotOpen, refusing.Open("file:///C:/x/index.html"));

        // A redirected run (--state-dir, the UI tests) records instead of starting anything.
        seen.Clear();
        var recorded = new WindowsDefaultBrowser(progId: () => "MSEdgeHTM", start: (progId, uri) => { seen.Add((progId, uri)); return true; },
                                                 redirected: () => true);
        Assert.Equal(PlanInTheBrowser.Opening.Opened, recorded.Open("file:///C:/x/press-recorded.html"));
        Assert.Empty(seen);
        Assert.Contains("MSEdgeHTM | file:///C:/x/press-recorded.html", File.ReadAllLines(AppDataRoot.Combine(WindowsDefaultBrowser.OpenedFileName)));
    }

    // ---- The tab's other two events, as the window writes them -------------------

    [Fact]
    public void AnAppearanceWritesOneLineAndNoPlanTitle()
    {
        var choices = new[] { PlanningTab.Choice.AllPlans, PlanningTab.Choice.Unit("unit-1-cells") };
        PlanningTab.NoteAppearance("SNC2D", choices, couldShow: true);
        PlanningTab.NoteAppearance("SNC2D", choices, couldShow: false);
        PlanningTab.NoteAppearance("SNC2D", Array.Empty<PlanningTab.Choice>(), couldShow: false);
        var lines = TrailLines();
        Assert.Equal(3, lines.Length);
        Assert.EndsWith(PlanningTab.OpenedTrailText("SNC2D", choices), lines[0]);
        Assert.EndsWith(PlanningTab.CouldNotShowTrailText("SNC2D"), lines[1]);
        // Nothing to show is the offer, never "could not show": no view was asked for.
        Assert.EndsWith(PlanningTab.OpenedTrailText("SNC2D", Array.Empty<PlanningTab.Choice>()), lines[2]);
        Assert.All(lines, line => Assert.DoesNotContain("cells", line));
    }

    [Fact]
    public void PlanAUnitWritesItsLineNamingTheAssistant()
    {
        PlanAUnit.NoteOnTheTrail("SNC2D", FixWithAssistant.Assistant.Codex);
        var line = Assert.Single(TrailLines());
        var contract = ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["planAUnit"]!["trailLine"]!.ToString();
        Assert.EndsWith(contract.Replace("{course}", "SNC2D").Replace("{assistant}", FixWithAssistant.NameOf(FixWithAssistant.Assistant.Codex)), line);
    }

    /// <summary>The three events this piece writes are this app's (the ledger no longer holds them).</summary>
    [Fact]
    public void TheThreeEventsAreNamedAsTheContractNamesThem()
    {
        Assert.Equal("looked at a course's unit plans", ActivityTrail.KeyFor(ActivityTrail.Event.UnitPlansLookedAt));
        Assert.Equal("asked an assistant to plan a unit", ActivityTrail.KeyFor(ActivityTrail.Event.AskedAnAssistantToPlanAUnit));
        Assert.Equal("opened a unit plan in the browser", ActivityTrail.KeyFor(ActivityTrail.Event.UnitPlanOpenedInBrowser));
    }
}
