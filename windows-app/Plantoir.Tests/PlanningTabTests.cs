using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The course page's Planning tab's rules in Core (#801 items 1, 2, 6; #820
/// item 1): <c>shared-rules.json</c> → <c>unitPlanning.tab</c> →
/// <c>tabCases</c>, <c>choiceCases</c> (choices and <c>startsOn</c>),
/// <c>followsThePage</c>, <c>saveOnPlanning</c>, <c>words</c>, and the trail
/// lines of "looked at a course's unit plans", each walked as data. The mac's
/// twin is <c>PlanningTabTests.swift</c>. The tab that draws them is 790b.
/// </summary>
public sealed class PlanningTabTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-planning-tab-" + Guid.NewGuid().ToString("N"));

    public PlanningTabTests() => Directory.CreateDirectory(_root);

    public void Dispose() => ReferenceFixtures.Remove(_root);

    internal static JsonNode Tab() => ContractLoader.LoadJson("shared-rules.json")["unitPlanning"]!["tab"]!;

    private static JsonArray Cases(string key) => Tab()[key]!["cases"]!.AsArray();

    public static IEnumerable<object[]> ChoiceCaseNames() => Cases("choiceCases").Select(c => new object[] { c!["name"]!.ToString() });

    private static JsonNode LookedAt() =>
        ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(e => e!["event"]!.ToString() == "looked at a course's unit plans")!;

    [Fact]
    public void TheTabsAreThereAsTheContractSays()
    {
        var tabCases = Cases("tabCases");
        Assert.True(tabCases.Count >= 6);
        foreach (var testCase in tabCases)
        {
            bool shown = PlanningTab.IsShown(testCase!["claude"]!.GetValue<bool>(), testCase["codex"]!.GetValue<bool>(),
                                             testCase["referenceCourse"]!.GetValue<bool>());
            Assert.True((shown ? "shown" : "absent") == testCase["expect"]!.ToString(), testCase["name"]!.ToString());
        }
    }

    [Fact]
    public void ThereAreAtLeastTheTwentyOneChoiceCases() => Assert.True(Cases("choiceCases").Count >= 21);

    [Theory]
    [MemberData(nameof(ChoiceCaseNames))]
    public void ThePopupOffersAndStartsAsTheContractSays(string name)
    {
        var testCase = Cases("choiceCases").Single(c => c!["name"]!.ToString() == name)!;
        string course = Path.Combine(_root, "course");
        string planning = UnitPlans.PlanningFolder(course);
        Directory.CreateDirectory(course);
        if (testCase["planningFolder"]!.GetValue<bool>()) Directory.CreateDirectory(planning);
        if (testCase["coursePage"]!.GetValue<bool>()) File.WriteAllText(Path.Combine(planning, "index.html"), "<html></html>");
        foreach (var plan in testCase["plans"]!.AsArray())
        {
            string unit = Path.Combine(planning, plan!["folder"]!.ToString());
            Directory.CreateDirectory(unit);
            File.WriteAllText(Path.Combine(unit, UnitPlans.PlanFileName), plan["file"]!.ToString(), new UTF8Encoding(false));
            if (plan["page"]!.GetValue<bool>()) File.WriteAllText(Path.Combine(unit, "index.html"), "<html></html>");
        }
        var today = DateOnly.ParseExact(testCase["today"]!.ToString(), "yyyy-MM-dd", CultureInfo.InvariantCulture);
        var expect = testCase["expect"]!;

        var look = PlanningTab.LookIn(planning, course);
        Assert.Equal(expect["choices"]!.AsArray().Select(c => c!.ToString()), look.Choices.Select(c => c.Written));
        Assert.Equal(expect["startsOn"]?.ToString(), PlanningTab.StartingChoice(look.Plans, look.Choices, today)?.Written);
    }

    /// <summary>Each entry is labelled as the greeting names the plan, and All Plans by its word.</summary>
    [Fact]
    public void ThePopupLabelsAreTheGreetingsNames()
    {
        var plan = new UnitPlans.Plan("unit-3", "Unit 3", "Chemical Reactions", null, null, Array.Empty<string>());
        Assert.Equal(UnitPlans.NameInTheGreeting(plan), PlanningTab.TitleFor(PlanningTab.Choice.Unit("unit-3"), new[] { plan }));
        Assert.Equal(PlanningTabWording.AllPlans, PlanningTab.TitleFor(PlanningTab.Choice.AllPlans, new[] { plan }));
    }

    [Fact]
    public void ThePopupFollowsThePageAsTheContractSays()
    {
        var follow = Cases("followsThePage");
        Assert.True(follow.Count >= 7);
        string planning = UnitPlans.PlanningFolder(Path.Combine(_root, "course"));
        foreach (var testCase in follow)
        {
            var choices = testCase!["choices"]!.AsArray().Select(c => PlanningTab.Choice.FromWritten(c!.ToString())).ToList();
            string page = Path.Combine(planning, testCase["page"]!.ToString().Replace('/', '\\'));
            Assert.True(testCase["expect"]?.ToString() == PlanningTab.ChoiceForPage(page, planning, choices)?.Written,
                        testCase["name"]!.ToString());
        }
    }

    /// <summary>Windows names files without regard to case, so a page typed in capitals still follows its unit.</summary>
    [Fact]
    public void ThePopupFollowsAPageWhateverItsCase()
    {
        string planning = UnitPlans.PlanningFolder(Path.Combine(_root, "course"));
        var choices = new[] { PlanningTab.Choice.AllPlans, PlanningTab.Choice.Unit("unit-1") };
        Assert.Equal("unit:unit-1", PlanningTab.ChoiceForPage(Path.Combine(planning, "UNIT-1", "Index.HTML"), planning, choices)?.Written);
        Assert.Equal("allPlans", PlanningTab.ChoiceForPage(Path.Combine(planning.ToUpperInvariant(), "INDEX.HTML"), planning, choices)?.Written);
        Assert.Null(PlanningTab.ChoiceForPage(Path.Combine(planning + "-old", "unit-1", "index.html"), planning, choices));
    }

    [Fact]
    public void EverySaveOnPlanningCaseHolds()
    {
        var saveCases = Cases("saveOnPlanning");
        Assert.True(saveCases.Count >= 4);
        foreach (var testCase in saveCases)
        {
            var after = PlanningTab.AfterASave(testCase!["problem"]!.GetValue<bool>(), testCase["notice"]!.GetValue<bool>());
            string written = after == PlanningTab.AfterSave.StaysOnPlanning ? "staysOnPlanning" : "showsSettings";
            Assert.True(written == testCase["expect"]!.ToString(), testCase["name"]!.ToString());
        }
    }

    [Fact]
    public void TheWordsAreTheContracts()
    {
        var words = Tab()["words"]!.AsObject();
        Assert.Equal(words.Select(w => w.Key).OrderBy(k => k, StringComparer.Ordinal),
                     PlanningTabWording.ByKey.Keys.OrderBy(k => k, StringComparer.Ordinal));
        foreach (var (key, value) in words)
            Assert.True(value!.ToString() == PlanningTabWording.ByKey[key], $"{key}: the contract says \"{value}\"");
        // The three that name the computer are said with Windows' word.
        foreach (string filled in new[]
                 {
                     PlanningTabWording.CannotShowDescription, PlanningTabWording.OpenInBrowserCouldNotOpen,
                     PlanningTabWording.OpenInBrowserNoBrowser,
                 })
        {
            Assert.DoesNotContain("Mac", filled);
            Assert.DoesNotContain(MachineWord.Placeholder, filled);
            Assert.Contains(MachineWord.Name, filled);
        }
        // Rule 1: no word for how the page is shown.
        foreach (string word in PlanningTabWording.ByKey.Values)
            foreach (string machinery in new[] { "web view", "WebView", "folder", "script", "JSON", "html" })
                Assert.DoesNotContain(machinery, word);
    }

    /// <summary>"looked at a course's unit plans": the lines are the contract's, and none names a plan.</summary>
    [Fact]
    public void TheTrailLinesAreTheContracts()
    {
        var entry = LookedAt();
        var what = entry["what"]!;
        Assert.Equal(entry["line"]!.ToString(), "{course}" + UnitPlans.TrailSeparator + PlanningTrail.Opened);
        Assert.Equal(what["one"]!.ToString(), PlanningTrail.OneUnitPlan);
        Assert.Equal(what["several"]!.ToString(), PlanningTrail.UnitPlans);
        Assert.Equal(what["listOnly"]!.ToString(), PlanningTrail.ListOnly);
        Assert.Equal(what["none"]!.ToString(), PlanningTrail.NothingToShow);
        Assert.Equal(entry["couldNotShowLine"]!.ToString(), "{course}" + UnitPlans.TrailSeparator + PlanningTrail.CouldNotShow);
        Assert.Equal(entry["couldNotRefreshTheLookLine"]!.ToString(),
                     "{course}" + UnitPlans.TrailSeparator + PlanningTrail.CouldNotRefreshTheLook);

        string Line(string line, string w = "") => line.Replace("{course}", "SNC2D").Replace("{what}", w);
        string several = what["several"]!.ToString().Replace("{n}", "2");
        Assert.Equal(Line(entry["line"]!.ToString(), several),
                     PlanningTab.OpenedTrailText("SNC2D", new[] { PlanningTab.Choice.AllPlans, PlanningTab.Choice.Unit("unit-1"), PlanningTab.Choice.Unit("unit-2") }));
        Assert.Equal(Line(entry["line"]!.ToString(), what["one"]!.ToString()),
                     PlanningTab.OpenedTrailText("SNC2D", new[] { PlanningTab.Choice.Unit("unit-1") }));
        Assert.Equal(Line(entry["line"]!.ToString(), what["listOnly"]!.ToString()),
                     PlanningTab.OpenedTrailText("SNC2D", new[] { PlanningTab.Choice.AllPlans }));
        Assert.Equal(Line(entry["line"]!.ToString(), what["none"]!.ToString()),
                     PlanningTab.OpenedTrailText("SNC2D", Array.Empty<PlanningTab.Choice>()));
        Assert.Equal(Line(entry["couldNotShowLine"]!.ToString()), PlanningTab.CouldNotShowTrailText("SNC2D"));
        Assert.Equal(Line(entry["couldNotRefreshTheLookLine"]!.ToString()).Replace("{n}", "3"),
                     PlanningTab.CouldNotRefreshTheLookTrailText("SNC2D", 3));
        Assert.DoesNotContain("Mac", PlanningTab.CouldNotShowTrailText("SNC2D"));
        Assert.DoesNotContain("unit-1", PlanningTab.OpenedTrailText("SNC2D", new[] { PlanningTab.Choice.Unit("unit-1") }));
    }
}
