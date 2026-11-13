using System.Text;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <see cref="LocalSiteGuard"/> (#801 item 3's Core; #811 reuses it): the
/// address-to-path mapping both ways, names Windows reads as another file, the
/// root resolved again at every call, and the request handler's answer read
/// from ONE handle. What a real WebView2 does with these answers is 790b's
/// headless harness; this is the guard alone.
/// </summary>
public sealed class LocalSiteGuardTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-site-guard-" + Guid.NewGuid().ToString("N"));

    public LocalSiteGuardTests() => Directory.CreateDirectory(_root);

    public void Dispose() => ReferenceFixtures.Remove(_root);

    private LocalSiteGuard Guard(string planning) =>
        new(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes);

    /// <summary>
    /// A working folder under a name with a space, accents (composed and
    /// decomposed), <c>#</c>, <c>%</c>, <c>&amp;</c>, brackets, an apostrophe
    /// and an emoji: the address names exactly the path, through .NET's own
    /// URL parser as a web view would hand it back. (<c>?</c> cannot be in a
    /// Windows name at all.)
    /// </summary>
    [Theory]
    [InlineData(@"C:\Users\Prof Élise\Cours #3 100% & co [2026]\courses\SNC2D\.internal\planning")]
    [InlineData("C:\\Users\\E\u0301lise\\O'Brien's \U0001F393\\courses\\SNC2D\\.internal\\planning")]
    [InlineData(@"D:\plans")]
    public void AnAddressNamesExactlyItsPath(string planning)
    {
        var guard = Guard(planning);
        string page = Path.Combine(planning, "unit-1", "Day 1 - Warm-up, Answers.pdf");
        string address = guard.AddressOf(page)!;
        Assert.StartsWith("https://" + LocalSiteGuard.PlansHost + "/", address);
        Assert.DoesNotContain(" ", address);
        Assert.Equal(page, guard.PathOf(address));
        Assert.Equal(page, guard.PathOf(new Uri(address).AbsoluteUri));
        Assert.Equal(planning, guard.PathOf(guard.RootAddress!)!.TrimEnd('\\'));
        Assert.Equal(Path.Combine(planning, "unit-1", "index.html"), guard.PathOf(new Uri(new Uri(address), "index.html#l3").AbsoluteUri));
    }

    [Fact]
    public void APathThisGuardCannotNameHasNoAddress()
    {
        var guard = Guard(@"C:\plans");
        Assert.Null(guard.AddressOf(@"\\server\share\plans\index.html"));
        Assert.Null(guard.AddressOf(@"C:\plans\CON"));
        Assert.Null(guard.AddressOf(@"C:\plans\nul.txt"));
        Assert.Null(guard.PathOf("https://plans.plantoir.invalid/plans/index.html"));
        Assert.Null(guard.PathOf("https://another.invalid/C:/plans/index.html"));
        Assert.Null(guard.PathOf("https://plans.plantoir.invalid/C:/plans/a%2Fb.html"));
        Assert.Null(guard.PathOf("https://plans.plantoir.invalid/C:/plans/a%5Cb.html"));
        Assert.Null(guard.PathOf("https://plans.plantoir.invalid/C:/plans/index.html::$DATA"));
        Assert.Null(guard.PathOf("https://plans.plantoir.invalid/C%3A%5Cplans/index.html"));
        Assert.Equal(@"C:\plans\index.html", guard.PathOf("https://PLANS.plantoir.invalid/c%3A/plans/index.html")?.Replace("c:", "C:"));
    }

    /// <summary>The root is looked for at every call: a folder made after the view opened is seen, and none is inside before.</summary>
    [Fact]
    public void TheRootIsResolvedAgainAtEveryCall()
    {
        string planning = Path.Combine(_root, "later", "planning");
        var guard = Guard(planning);
        string page = Path.Combine(planning, "index.html");
        Assert.False(guard.IsInside(page));
        Assert.IsType<LocalSiteGuard.Verdict.Refuse>(guard.Answer(guard.AddressOf(page)!));
        Directory.CreateDirectory(planning);
        File.WriteAllText(page, "<p>All Plans</p>");
        Assert.True(guard.IsInside(page));
        var served = Assert.IsType<LocalSiteGuard.Verdict.Serve>(guard.Answer(guard.AddressOf(page)!));
        using (served.Content) Assert.Equal("<p>All Plans</p>", new StreamReader(served.Content).ReadToEnd());
        Assert.Equal("text/html", served.ContentType);
    }

    /// <summary>What the handler serves, and what it refuses: a folder, a type not on the list, outside through a junction, beside the root.</summary>
    [Fact]
    public void TheHandlerServesOnlyFilesOfThePlan()
    {
        string course = Path.Combine(_root, "SNC2D");
        string planning = UnitPlans.PlanningFolder(course);
        Directory.CreateDirectory(Path.Combine(planning, "unit-1", "pdfs"));
        Directory.CreateDirectory(Path.Combine(planning, "assets"));
        Directory.CreateDirectory(course + "-old");
        File.WriteAllText(Path.Combine(course, "course_config.json"), "{\"course_code\": \"SNC2D\"}");
        File.WriteAllText(Path.Combine(planning, "assets", "plan.css"), "body{}");
        File.WriteAllBytes(Path.Combine(planning, "unit-1", "pdfs", "Quiz.PDF"), Encoding.ASCII.GetBytes("%PDF-1.7"));
        File.WriteAllText(Path.Combine(planning, "unit-1", "notes.zip"), "PK");
        File.WriteAllText(Path.Combine(planning, "unit-1", "tidy.cmd"), "del *");
        ReferenceFixtures.Junction(Path.Combine(planning, "unit-1", "shortcut"), course);
        ReferenceFixtures.Junction(Path.Combine(planning, "unit-1", "shared"), Path.Combine(planning, "assets"));
        var guard = Guard(planning);
        string unit = guard.AddressOf(Path.Combine(planning, "unit-1"), isFolder: true)!;

        var css = Assert.IsType<LocalSiteGuard.Verdict.Serve>(guard.Answer(unit + "shared/plan.css"));
        css.Content.Dispose();
        Assert.Equal("text/css", css.ContentType);
        Assert.Equal(Path.Combine(planning, "assets", "plan.css"), css.RealPath, ignoreCase: true);
        var pdf = Assert.IsType<LocalSiteGuard.Verdict.Serve>(guard.Answer(unit + "pdfs/Quiz.PDF"));
        pdf.Content.Dispose();
        Assert.Equal("application/pdf", pdf.ContentType);

        foreach (string refused in new[]
                 {
                     unit + "shortcut/course_config.json", unit + "notes.zip", unit + "tidy.cmd", unit + "pdfs",
                     unit + "pdfs/", unit + "missing.html", unit + "../../../course_config.json",
                     guard.AddressOf(Path.Combine(course + "-old", "index.html"))!, "https://example.org/x.css",
                 })
            Assert.True(guard.Answer(refused) is LocalSiteGuard.Verdict.Refuse, refused);
    }

    /// <summary>A link named like a page that leads to another type is refused by what it leads to, through the one handle.</summary>
    [Fact]
    public void ALinkIsJudgedByWhereItLeads()
    {
        string planning = @"C:\plantoir-not-on-disk\SNC2D\.internal\planning";
        var map = new LocalSiteFixtures.LinkMap()
            .File(Path.Combine(planning, "unit-1", "run.cmd"))
            .File(Path.Combine(planning, "index.html"))
            .Link(Path.Combine(planning, "unit-1", "look.html"), "run.cmd")
            .Link(Path.Combine(planning, "unit-1", "home.html"), "../index.html");
        var guard = new LocalSiteGuard(planning, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes, map);
        string unit = guard.AddressOf(Path.Combine(planning, "unit-1"), isFolder: true)!;
        Assert.IsType<LocalSiteGuard.Verdict.Refuse>(guard.Answer(unit + "look.html"));
        var home = Assert.IsType<LocalSiteGuard.Verdict.Serve>(guard.Answer(unit + "home.html"));
        Assert.Equal(Path.Combine(planning, "index.html"), home.RealPath);
    }

    [Fact]
    public void SegmentsWindowsWouldReadAsAnotherFileAreRefused()
    {
        foreach (string segment in new[] { "", ".", "..", "a.", "a ", "a:b", "a\\b", "a/b", "a*b", "a?b", "a\"b", "a<b", "a|b",
                                           "CON", "con.html", "Com1.txt", "LPT9", "AUX .md", "COM\u00B9", "CONOUT$", "a\u0001b" })
            Assert.False(LocalSiteGuard.IsAcceptableSegment(segment), segment);
        foreach (string segment in new[] { "index.html", "Day 1 - Warm-up, Answers.pdf", "#3 100%", "CONSOLE.html", "unit-1", ".internal", "Élise" })
            Assert.True(LocalSiteGuard.IsAcceptableSegment(segment), segment);
    }
}
