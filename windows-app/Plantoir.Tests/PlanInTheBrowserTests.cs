using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>unitPlanning.tab.openInBrowser</c> (#820
/// items 2 and 5, the rule half): which page Open in Browser would hand the
/// default browser, or which refusal, for every case, run TWO ways — against a
/// map of the case's files and links, and on a real disk. Three cases link a
/// FILE (<c>unit-1/notes.html</c>, <c>home.html</c>, <c>look.html</c>), which
/// needs a symbolic link this account cannot make (WinError 1314, measured
/// 2026-11-13): on disk they run in <see cref="TheFileLinkCasesHoldOnDisk"/>,
/// which is SKIPPED by name where the account cannot make one, and any other
/// case whose link cannot be made fails. The page on screen is the served
/// address a web view would report (<see cref="LocalSiteFixtures.Address"/>).
/// Starting the browser and the trail line are 790b.
/// </summary>
public sealed class PlanInTheBrowserTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-plan-open-" + Guid.NewGuid().ToString("N"));
    private readonly ITestOutputHelper _output;

    public PlanInTheBrowserTests(ITestOutputHelper output)
    {
        _output = output;
        Directory.CreateDirectory(_root);
    }

    public void Dispose() => ReferenceFixtures.Remove(_root);

    private static JsonArray Cases() => PlanningTabTests.Tab()["openInBrowser"]!["cases"]!.AsArray();

    public static IEnumerable<object[]> CaseNames() => Cases().Select(c => new object[] { c!["name"]!.ToString() });

    private static JsonNode Case(string name) => Cases().Single(c => c!["name"]!.ToString() == name)!;

    /// <summary>Each case's <c>made</c> path, %-escapes decoded, under the planning folder.</summary>
    private static IEnumerable<string> Made(JsonNode testCase, string planning) =>
        testCase["made"]!.AsArray().Select(m => Path.GetFullPath(Path.Combine(planning, Uri.UnescapeDataString(m!.ToString()).Replace('/', '\\'))));

    private static void Check(JsonNode testCase, LocalSiteGuard guard)
    {
        string name = testCase["name"]!.ToString();
        string baseAddress = guard.RootAddress!;
        var answer = PlanInTheBrowser.PageToOpen(LocalSiteFixtures.Address(testCase["onScreen"]?.ToString(), guard, baseAddress),
                                                 LocalSiteFixtures.Address(testCase["chosen"]?.ToString(), guard, baseAddress), guard);
        var expect = testCase["expect"]!;
        if (expect["opens"]?.ToString() is { } opens)
        {
            string written = LocalSiteFixtures.Address(opens, guard, baseAddress)!;
            string? expected = guard.PathOf(written) ?? LocalSiteGuard.PathOfFileAddress(written);
            Assert.True(answer.Refusal is null, $"{name}: refused as {answer.Refusal}");
            Assert.True(expected == answer.Path, $"{name}: opened {answer.Path}, the case opens {expected}");
            Assert.True(expect["kind"]!.ToString() == PlanInTheBrowser.Written(answer.Kind!.Value), $"{name}: {answer.Kind}");
            Assert.Equal(PlanningTabWording.OpenInBrowserHelp, PlanInTheBrowser.HelpText(answer));
        }
        else
        {
            Assert.Null(answer.Path);
            Assert.True(answer.Refusal is { } refusal && PlanInTheBrowser.Written(refusal) == expect["refusal"]!.ToString(),
                        $"{name}: {answer.Refusal}, the case says {expect["refusal"]}");
            Assert.Equal(PlanInTheBrowser.Sentence(answer.Refusal!.Value), PlanInTheBrowser.HelpText(answer));
        }
    }

    [Fact]
    public void ThereAreAtLeastTheTwentyThreeCases() => Assert.True(Cases().Count >= 23);

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void EveryOpenInBrowserCaseHoldsAgainstALinkMap(string name)
    {
        var testCase = Case(name);
        string course = @"C:\plantoir-not-on-disk\open\SNC2D";
        string planning = UnitPlans.PlanningFolder(course);
        var map = new LocalSiteFixtures.LinkMap().Folder(planning).File(Path.Combine(course, "course_config.json"));
        foreach (string made in Made(testCase, planning)) map.File(made);
        if (testCase["links"] is JsonObject links)
            foreach (var (at, to) in links) map.Link(Path.Combine(planning, at.Replace('/', '\\')), to!.ToString());
        Check(testCase, new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes, map));
    }

    /// <summary>The cases this PC cannot make on disk, by name: each must link a file.</summary>
    private static readonly HashSet<string> FileLinkCases = new(StringComparer.Ordinal)
    {
        "a shortcut inside the plan that leads out of it",
        "a shortcut inside the plan that stays in it",
        "a link named like a page that leads to a script",
    };

    /// <summary>
    /// Every case on disk, less the three that link a FILE when this account
    /// cannot make a file symbolic link: those are not run here at all, and
    /// <see cref="TheFileLinkCasesHoldOnDisk"/> is SKIPPED by name, so the
    /// totals line shows they did not run (790a review 2, L9: they used to
    /// return early and count as passed).
    /// </summary>
    public static IEnumerable<object[]> DiskCaseNames() =>
        CaseNames().Where(c => LocalSiteFixtures.CanMakeFileLinks || !FileLinkCases.Contains((string)c[0]));

    /// <summary>The three are cases of the contract, exactly: a renamed case must not drop silently out of the disk run.</summary>
    [Fact]
    public void TheFileLinkCasesAreTheContractsThree()
    {
        var names = Cases().Select(c => c!["name"]!.ToString()).ToHashSet(StringComparer.Ordinal);
        Assert.Equal(3, FileLinkCases.Count);
        foreach (string name in FileLinkCases) Assert.Contains(name, names);
        Assert.Equal(Cases().Count - (LocalSiteFixtures.CanMakeFileLinks ? 0 : 3), DiskCaseNames().Count());
    }

    [FileLinkFact]
    public void TheFileLinkCasesHoldOnDisk()
    {
        foreach (string name in FileLinkCases)
        {
            ReferenceFixtures.Remove(_root);
            Directory.CreateDirectory(_root);
            EveryOpenInBrowserCaseHoldsOnDisk(name);
        }
    }

    [Theory]
    [MemberData(nameof(DiskCaseNames))]
    public void EveryOpenInBrowserCaseHoldsOnDisk(string name)
    {
        var testCase = Case(name);
        string course = Path.Combine(_root, "SNC2D");
        string planning = UnitPlans.PlanningFolder(course);
        Directory.CreateDirectory(planning);
        File.WriteAllText(Path.Combine(course, "course_config.json"), "{}");
        foreach (string made in Made(testCase, planning))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(made)!);
            File.WriteAllText(made, "made");
        }
        if (testCase["links"] is JsonObject links)
            foreach (var (at, to) in links)
            {
                string link = Path.Combine(planning, at.Replace('/', '\\'));
                bool folder = Directory.Exists(Path.GetFullPath(Path.Combine(Path.GetDirectoryName(link)!, to!.ToString().Replace('/', '\\'))));
                if (!LocalSiteFixtures.MakeLink(link, to.ToString(), folder))
                    Assert.Fail($"{name}: this PC could not make its {(folder ? "folder" : "file")} link, so the case did not run on disk");
            }
        Check(testCase, new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes));
    }

    // ---- Windows-only facts -----------------------------------------------------

    private LocalSiteGuard DiskPlanning(out string planning)
    {
        planning = UnitPlans.PlanningFolder(Path.Combine(_root, "SNC2D"));
        Directory.CreateDirectory(Path.Combine(planning, "unit-1"));
        return new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes);
    }

    /// <summary>What Windows would RUN if a browser or the shell handed it on: never a page, whatever an assistant wrote.</summary>
    [Theory]
    [InlineData("tidy.cmd")]
    [InlineData("tidy.bat")]
    [InlineData("tidy.ps1")]
    [InlineData("Lesson.lnk")]
    [InlineData("Lesson.url")]
    [InlineData("Tool.exe")]
    [InlineData("Tool.msi")]
    [InlineData("Tool.scr")]
    [InlineData("notes.html.exe")]
    public void AWindowsProgramOrShortcutIsNotAPage(string file)
    {
        var guard = DiskPlanning(out string planning);
        File.WriteAllText(Path.Combine(planning, "unit-1", file), "made");
        var answer = PlanInTheBrowser.PageToOpen(guard.AddressOf(Path.Combine(planning, "unit-1", file)), null, guard);
        Assert.Equal(PlanInTheBrowser.Refusal.NotAPage, answer.Refusal);
    }

    [Fact]
    public void AnAddressWindowsWouldReadAsAnotherFileIsOutsideThePlan()
    {
        var guard = DiskPlanning(out string planning);
        File.WriteAllText(Path.Combine(planning, "unit-1", "index.html"), "made");
        string unit = guard.AddressOf(Path.Combine(planning, "unit-1"), isFolder: true)!;
        Assert.NotNull(PlanInTheBrowser.PageToOpen(unit + "index.html", null, guard).Path);
        foreach (string tail in new[] { "index.html.", "index.html::$DATA", "index.html%20", "CON.html" })
            Assert.True(PlanInTheBrowser.PageToOpen(unit + tail, null, guard).Refusal == PlanInTheBrowser.Refusal.OutsideThePlan, tail);
        var disk = new LocalSiteFixtures.CountingDisk();
        var counted = new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes, disk);
        Assert.Equal(PlanInTheBrowser.Refusal.OutsideThePlan,
                     PlanInTheBrowser.PageToOpen("file://server/share/planning/index.html", null, counted).Refusal);
        Assert.Equal(0, disk.Calls);
    }

    /// <summary>The browser is handed the page as a file: address with a space, a quote and an accent escaped, and no anchor.</summary>
    [Fact]
    public void TheFileAddressIsEscapedAndCarriesNoAnchor()
    {
        var guard = DiskPlanning(out string planning);
        string pdf = Path.Combine(planning, "unit-1", "Day 1 - Ça \"Warm-up\".pdf".Replace("\"", "'"));
        File.WriteAllText(pdf, "made");
        var answer = PlanInTheBrowser.PageToOpen(guard.AddressOf(pdf) + "#page=2", null, guard);
        Assert.Equal(pdf, answer.Path);
        Assert.StartsWith("file:///", answer.FileUri);
        Assert.DoesNotContain(" ", answer.FileUri);
        Assert.DoesNotContain("#", answer.FileUri);
        Assert.Equal(pdf, new Uri(answer.FileUri!).LocalPath);
    }

    /// <summary>"opened a unit plan in the browser": the lines are the contract's, and name a kind, never a page.</summary>
    [Fact]
    public void TheTrailLinesAreTheContracts()
    {
        var entry = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(e => e!["event"]!.ToString() == "opened a unit plan in the browser")!;
        Assert.Equal(entry["line"]!.ToString(), "{course}" + UnitPlans.TrailSeparator + PlanInTheBrowser.TrailLine);
        Assert.Equal(entry["couldNotOpenLine"]!.ToString(), "{course}" + UnitPlans.TrailSeparator + PlanInTheBrowser.CouldNotOpenTrailLine);
        var what = entry["what"]!.AsObject();
        var kinds = Enum.GetValues<PlanInTheBrowser.Kind>();
        Assert.Equal(kinds.Length, what.Count);
        foreach (var kind in kinds)
            Assert.Equal(what[PlanInTheBrowser.Written(kind)]!.ToString(), PlanInTheBrowser.What(kind));
        Assert.Equal(entry["line"]!.ToString().Replace("{course}", "SNC2D").Replace("{what}", what["plan"]!.ToString()),
                     PlanInTheBrowser.TrailText("SNC2D", PlanInTheBrowser.Kind.Plan));
    }
}
