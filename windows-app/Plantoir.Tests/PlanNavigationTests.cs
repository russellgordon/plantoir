using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>unitPlanning.tab.navigationCases</c> (#801
/// item 3), each case run TWO ways through <see cref="PlanNavigation.Decide"/>
/// and a real <see cref="LocalSiteGuard"/>: against a map of the case's links
/// (every case, always), and on a real disk with each link made (a folder link
/// as a junction). A link this PC cannot make FAILS the case (none links a
/// file today), never a silent pass (790a review 2, L9). The page is
/// the served address of the case's <c>page</c>, and the href is resolved
/// against it by the URL parser, as WebView2 resolves it, so <c>..</c> is
/// judged in the same space the web view reports. Plus the Windows-only facts
/// the contract does not carry.
/// </summary>
public sealed class PlanNavigationTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-plan-nav-" + Guid.NewGuid().ToString("N"));
    private readonly ITestOutputHelper _output;

    public PlanNavigationTests(ITestOutputHelper output)
    {
        _output = output;
        Directory.CreateDirectory(_root);
    }

    public void Dispose() => ReferenceFixtures.Remove(_root);

    private static JsonArray Cases() => PlanningTabTests.Tab()["navigationCases"]!["cases"]!.AsArray();

    public static IEnumerable<object[]> CaseNames() => Cases().Select(c => new object[] { c!["name"]!.ToString() });

    private static JsonNode Case(string name) => Cases().Single(c => c!["name"]!.ToString() == name)!;

    /// <summary>What the mac's runner makes for every case: unit/pdfs, unit-2 and assets, and the course's settings.</summary>
    private static readonly string[] MadeFolders = { "unit\\pdfs", "unit-2", "assets" };

    private static string Written(LocalPageDecision decision) => decision switch
    {
        LocalPageDecision.Load => "load",
        LocalPageDecision.LoadHere => "loadHere",
        LocalPageDecision.OpenOutside => "openOutside",
        LocalPageDecision.Refuse => "refuse",
        _ => "handToTheApp",
    };

    private static LocalPageDecision DecideCase(JsonNode testCase, LocalSiteGuard guard, string planning, out string address)
    {
        string page = guard.AddressOf(Path.Combine(planning, testCase["page"]!.ToString().Replace('/', '\\')))!;
        address = LocalSiteFixtures.Address(testCase["href"]!.ToString(), guard, page)!;
        return PlanNavigation.Decide(address, testCase["newWindow"]!.GetValue<bool>(), testCase["click"]!.GetValue<bool>(), guard);
    }

    [Fact]
    public void ThereAreAtLeastTheTwentyThreeCases() => Assert.True(Cases().Count >= 23);

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void EveryNavigationCaseHoldsAgainstALinkMap(string name)
    {
        var testCase = Case(name);
        string course = @"C:\plantoir-not-on-disk\nav\SNC2D";
        string planning = UnitPlans.PlanningFolder(course);
        var map = new LocalSiteFixtures.LinkMap().File(Path.Combine(course, "course_config.json"));
        foreach (string folder in MadeFolders) map.Folder(Path.Combine(planning, folder));
        if (testCase["links"] is JsonObject links)
            foreach (var (at, to) in links) map.Link(Path.Combine(planning, at.Replace('/', '\\')), to!.ToString());
        var guard = new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes, map);

        var decision = DecideCase(testCase, guard, planning, out string address);
        Assert.True(testCase["expect"]!.ToString() == Written(decision), $"{name}: {address} was {Written(decision)}");
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void EveryNavigationCaseHoldsOnDisk(string name)
    {
        var testCase = Case(name);
        string course = Path.Combine(_root, "SNC2D");
        string planning = UnitPlans.PlanningFolder(course);
        foreach (string folder in MadeFolders) Directory.CreateDirectory(Path.Combine(planning, folder));
        File.WriteAllText(Path.Combine(course, "course_config.json"), "{}");
        if (testCase["links"] is JsonObject links)
            foreach (var (at, to) in links)
            {
                string link = Path.Combine(planning, at.Replace('/', '\\'));
                bool folder = Directory.Exists(Path.GetFullPath(Path.Combine(Path.GetDirectoryName(link)!, to!.ToString().Replace('/', '\\'))));
                if (!LocalSiteFixtures.MakeLink(link, to.ToString(), folder))
                {
                    // No navigationCases case links a FILE today, so every one runs on
                    // disk; a case that needs a link this PC cannot make FAILS rather than
                    // passing having run nothing (790a review 2, L9). If the contract
                    // gains one, give it a skipped fact by name as PlanInTheBrowserTests does.
                    Assert.Fail($"{name}: this PC could not make its {(folder ? "folder" : "file")} link, so the case did not run on disk");
                }
            }
        var guard = new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes);

        var decision = DecideCase(testCase, guard, planning, out string address);
        Assert.True(testCase["expect"]!.ToString() == Written(decision), $"{name}: {address} was {Written(decision)}");
    }

    // ---- Windows-only facts, not proposed to the contract --------------------

    private LocalSiteGuard DiskGuard(out string planning)
    {
        planning = UnitPlans.PlanningFolder(Path.Combine(_root, "SNC2D"));
        Directory.CreateDirectory(Path.Combine(planning, "unit"));
        File.WriteAllText(Path.Combine(planning, "unit", "index.html"), "<p>a plan</p>");
        return new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes);
    }

    /// <summary>A file: address naming another machine is refused WITHOUT asking the disk (an SMB connection from the teacher's PC).</summary>
    [Fact]
    public void AnAddressOnAnotherMachineIsRefusedWithoutTouchingTheDisk()
    {
        var disk = new LocalSiteFixtures.CountingDisk();
        var guard = new LocalSiteGuard(Path.Combine(_root, "planning"), LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes, disk);
        foreach (string address in new[]
                 {
                     "file://server/share/planning/index.html", "file:////server/share/planning/index.html",
                     @"file:\\server\share\planning\index.html", "file://192.0.2.1/c$/x.html",
                 })
        {
            Assert.Equal(LocalPageDecision.Refuse, PlanNavigation.Decide(address, false, true, guard));
            Assert.Equal(LocalPageDecision.Refuse, PlanNavigation.Decide(address, true, true, guard));
        }
        Assert.Equal(0, disk.Calls);
    }

    /// <summary>A trailing dot, an alternate data stream, an escaped dot-dot or slash, and a device name never name a file.</summary>
    [Fact]
    public void AddressesWindowsWouldReadAsAnotherFileAreRefused()
    {
        var guard = DiskGuard(out string planning);
        string unit = guard.AddressOf(Path.Combine(planning, "unit"), isFolder: true)!;
        Assert.Equal(LocalPageDecision.Load, PlanNavigation.Decide(unit + "index.html", false, true, guard));
        foreach (string tail in new[]
                 {
                     "index.html.", "index.html%20", "index.html::$DATA", "index.html%3A%3A$DATA", "%2e%2e/%2e%2e/%2e%2e/course_config.json",
                     "..%2F..%2F..%2Fcourse_config.json", "..%5C..%5C..%5Ccourse_config.json", "CON", "con.html", "COM1.pdf", "NUL",
                     "CONIN$", "index%00.html",
                 })
            Assert.True(PlanNavigation.Decide(unit + tail, false, true, guard) == LocalPageDecision.Refuse, tail);
        // Our own host on another scheme, a port or a user name is not the plan.
        string http = "http" + unit["https".Length..] + "index.html";
        Assert.Equal(LocalPageDecision.Refuse, PlanNavigation.Decide(http, false, true, guard));
        Assert.Equal(LocalPageDecision.Refuse, PlanNavigation.Decide(unit.Replace(LocalSiteGuard.PlansHost, LocalSiteGuard.PlansHost + ":8443") + "index.html", false, true, guard));
        Assert.Equal(LocalPageDecision.Refuse, PlanNavigation.Decide(unit.Replace("https://", "https://someone@") + "index.html", false, true, guard));
    }

    /// <summary>The planning folder named by its 8.3 short name is still inside, because real paths expand it.</summary>
    [Fact]
    public void AShortNameOfThePlanningFolderIsStillInside()
    {
        var guard = DiskGuard(out string planning);
        string page = Path.Combine(planning, "unit", "index.html");
        string shortName = ShortPath(page);
        _output.WriteLine($"long: {page}\nshort: {shortName}");
        if (string.Equals(shortName, page, StringComparison.OrdinalIgnoreCase))
        {
            _output.WriteLine("NOT MEASURED: this volume made no 8.3 short name for the folder");
            return;
        }
        Assert.True(guard.IsInside(shortName));
        var shortGuard = new LocalSiteGuard(ShortPath(planning), LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes);
        Assert.True(shortGuard.IsInside(page));
    }

    /// <summary>A junction inside the planning folder to the course is outside, and one to its own assets inside.</summary>
    [Fact]
    public void JunctionsAreFollowed()
    {
        var guard = DiskGuard(out string planning);
        string course = Path.GetDirectoryName(Path.GetDirectoryName(planning))!;
        File.WriteAllText(Path.Combine(course, "course_config.json"), "{}");
        Directory.CreateDirectory(Path.Combine(planning, "assets"));
        ReferenceFixtures.Junction(Path.Combine(planning, "unit", "out"), course);
        ReferenceFixtures.Junction(Path.Combine(planning, "unit", "in"), Path.Combine(planning, "assets"));
        string unit = guard.AddressOf(Path.Combine(planning, "unit"), isFolder: true)!;
        Assert.Equal(LocalPageDecision.Refuse, PlanNavigation.Decide(unit + "out/course_config.json", false, true, guard));
        Assert.Equal(LocalPageDecision.Refuse, PlanNavigation.Decide(unit + "out/not-there-yet.html", false, true, guard));
        Assert.Equal(LocalPageDecision.Load, PlanNavigation.Decide(unit + "in/plan.css", false, true, guard));
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern uint GetShortPathNameW(string longPath, System.Text.StringBuilder shortPath, uint length);

    private static string ShortPath(string path)
    {
        var buffer = new System.Text.StringBuilder(1024);
        return GetShortPathNameW(path, buffer, (uint)buffer.Capacity) > 0 ? buffer.ToString() : path;
    }
}
