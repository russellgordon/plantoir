using System;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The ledger's own rule, made a test: every entry is owed by a milestone
/// LATER than the last release Windows shipped (#481, 2026-10-15; the
/// baseline moved from <c>&lt;Version&gt;</c> to the last release with #862,
/// 2026-11-13). The cut compares with the release being built instead.
/// </summary>
/// <remarks>
/// <para>The ledger holds work later pieces own, each entry on the milestone
/// its feature ships in. Those must all be gone by the time the release they
/// name ships on Windows, and "remember to empty the ledger" is the kind of
/// rule that is remembered until the day it matters.</para>
///
/// <para><b>Two baselines, one rule.</b> Until #862 this read
/// <c>&lt;Version&gt;</c> from <c>Plantoir.csproj</c>, which then said the
/// release Windows last shipped. Since #861 and #862 that number names the
/// release being BUILT and is raised on <c>dev</c> when work on a release
/// starts (<c>RELEASING.md</c> → "When the number is raised"), so comparing
/// with it would turn every entry owed by the release in progress red the day
/// the number moved, which is exactly while that work is allowed to be open.
/// So the ordinary suite compares with the last release Windows SHIPPED, read
/// the way the deploy of plantoir.app reads it (<c>website/windows_feed.py</c>
/// → <c>shipped_version</c> and <c>version_refusal</c>): <c>site.json</c>'s
/// Windows card's pin, else its version line, and the Windows feed's newest
/// item, which the deploy refuses to publish unless the two agree. Never the
/// csproj. An entry owed by a release Windows has already shipped is red in
/// every run; an entry owed by v2.0.0 survives a mac-only 2.0.0 cut, because
/// Windows shipped nothing in it.</para>
///
/// <para>The CUT is guarded by the other baseline: with
/// <c>PLANTOIR_LEDGER_BASELINE=build</c> the same fact compares with
/// <c>&lt;Version&gt;</c>, the release being cut, and <c>publish.ps1 -Sign</c>
/// runs it that way before it builds anything, so a signed installer cannot
/// be made while an entry owed by its own release (or an earlier one) is still
/// here. That replaced "RELEASING.md runs the suite again AFTER the version is
/// set", which needed a person to remember the second run. Once the cut adds
/// its item to <c>windows.xml</c>, the ordinary suite's baseline is that
/// release too, so a leftover entry is red everywhere after it.</para>
///
/// <para>It is "later than", not "empty at the cut", on purpose: an entry
/// owed by a genuinely later release rightly survives a cut. A milestone that
/// is not a version at all fails, because it cannot be compared, which is
/// what retired the old "Windows: parity with mac v1.4.0" spelling.</para>
/// </remarks>
public class NamedGapLedgerTests
{
    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (int i = 0; i < 8 && dir is not null; i++, dir = dir.Parent)
            {
                if (File.Exists(Path.Combine(dir.FullName, "Dockerfile")))
                    return dir.FullName;
            }
            throw new DirectoryNotFoundException("Could not find repository root containing Dockerfile.");
        }
    }

    /// <summary>The switch that makes the rule compare with the release being built (set by <c>publish.ps1</c>).</summary>
    internal const string BaselineSwitch = "PLANTOIR_LEDGER_BASELINE";

    private static Version ThisBuild()
    {
        var project = XDocument.Load(Path.Combine(RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj"));
        string text = project.Descendants("Version").Single().Value.Trim();
        return Version.Parse(text);
    }

    /// <summary>
    /// The release Windows last shipped an installer in, as <c>site.json</c>
    /// says: the Windows card's <c>pinned</c> when it has one, else the version
    /// line (<c>windows_feed.shipped_version</c>, #861).
    /// </summary>
    internal static Version? ShippedPerTheSite(string siteJson)
    {
        var site = System.Text.Json.Nodes.JsonNode.Parse(siteJson)!;
        string? version = site["version"]?.GetValue<string>();
        foreach (var entry in site["downloads"]?.AsArray() ?? new System.Text.Json.Nodes.JsonArray())
        {
            if (entry?["platform"]?.GetValue<string>() != "Windows")
                continue;
            if (entry["pinned"] is { } pinned && pinned.GetValue<string>() is { Length: > 0 } pin)
                version = pin;
            break;
        }
        return Bare(version);
    }

    /// <summary>
    /// The feed's newest item, the one the updater offers: the HIGHEST
    /// <c>sparkle:version</c> wherever it sits in the file
    /// (<c>windows_feed.newest_item</c>), the enclosure's attribute first,
    /// then the element.
    /// </summary>
    internal static Version? NewestInTheFeed(string feedXml)
    {
        XNamespace sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle";
        Version? newest = null;
        foreach (var item in XDocument.Parse(feedXml).Descendants("item"))
        {
            string? text = (string?)item.Element("enclosure")?.Attribute(sparkle + "version")
                           ?? (string?)item.Element(sparkle + "version");
            var version = Bare(text);
            if (version is not null && (newest is null || version > newest))
                newest = version;
        }
        return newest;
    }

    /// <summary>"1.9.3" as a three-part version; null for nothing or a malformed one.</summary>
    private static Version? Bare(string? text)
    {
        if (!Version.TryParse((text ?? "").Trim(), out var version))
            return null;
        return new Version(version.Major, version.Minor, Math.Max(version.Build, 0));
    }

    private static string CommittedSite => File.ReadAllText(Path.Combine(RepoRoot, "website", "site.json"));

    private static string CommittedFeed => File.ReadAllText(Path.Combine(RepoRoot, "website", "updates", "windows.xml"));

    /// <summary>
    /// The last release Windows shipped, from the committed <c>site.json</c>
    /// and <c>windows.xml</c>. When they disagree (they must not: the deploy
    /// refuses it) the HIGHER is used, so a half-made cut never lets an entry
    /// through; <see cref="TheSiteAndTheFeedAgreeOnWhatWindowsLastShipped"/>
    /// fails for the disagreement itself.
    /// </summary>
    private static Version LastWindowsRelease()
    {
        var site = ShippedPerTheSite(CommittedSite);
        var feed = NewestInTheFeed(CommittedFeed);
        if (site is null || feed is null)
            throw new InvalidOperationException(
                $"Could not read the last Windows release: site.json says {site?.ToString() ?? "nothing"}, " +
                $"updates/windows.xml offers {feed?.ToString() ?? "nothing"}.");
        return site > feed ? site : feed;
    }

    /// <summary>
    /// What the rule compares with: the last Windows release, or the release
    /// being built when <see cref="BaselineSwitch"/> is <c>build</c> (what
    /// <c>publish.ps1</c> sets). Any other value is refused rather than read
    /// as the default, so a misspelt switch at the cut cannot pass quietly.
    /// </summary>
    internal static (Version Version, string Described) Baseline(string? switchValue)
    {
        string value = switchValue ?? "";
        if (value.Length == 0)
            return (LastWindowsRelease(), "the last release Windows shipped (site.json and updates/windows.xml)");
        if (value == "build")
            return (ThisBuild(), "the release being built (Plantoir.csproj's <Version>)");
        throw new InvalidOperationException($"{BaselineSwitch} is \"{value}\"; it may only be \"build\" or unset.");
    }

    [Fact]
    public void EveryEntryIsOwedByAMilestoneLaterThanTheLastWindowsRelease()
    {
        var (baseline, described) = Baseline(Environment.GetEnvironmentVariable(BaselineSwitch));
        var problems = Problems(NamedGapLedger.All, baseline, described);
        Assert.True(problems.Count == 0, string.Join("\n", problems));
    }

    /// <summary>
    /// The two readers agree on the committed files, as the deploy of
    /// plantoir.app requires (<c>windows_feed.version_refusal</c>). No version
    /// is written here: it would be wrong at the next Windows cut.
    /// </summary>
    [Fact]
    public void TheSiteAndTheFeedAgreeOnWhatWindowsLastShipped()
    {
        var site = ShippedPerTheSite(CommittedSite);
        var feed = NewestInTheFeed(CommittedFeed);
        Assert.NotNull(site);
        Assert.NotNull(feed);
        Assert.True(site == feed,
            $"site.json says Windows last shipped in {site}, but updates/windows.xml offers {feed}. " +
            "The deploy of plantoir.app refuses this too: correct the feed or the pin at the cut " +
            "(RELEASING.md → \"The update feed (Windows)\").");
    }

    /// <summary>
    /// The readers on made-up files, so the cases that matter are proved
    /// whatever is committed today: an unpinned card, a pinned one (a mac-only
    /// cut), a feed whose newest item is neither its first nor spelled the
    /// same way, and the switch's values.
    /// </summary>
    [Fact]
    public void TheBaselineIsReadFromThePinTheVersionLineAndTheNewestItem()
    {
        const string unpinned = """{"version": "1.9.3", "downloads": [{"platform": "macOS", "pinned": "1.9.2"}, {"platform": "Windows", "pinned": null}]}""";
        const string pinned = """{"version": "2.0.0", "downloads": [{"platform": "macOS", "pinned": null}, {"platform": "Windows", "pinned": "1.9.3"}]}""";
        Assert.Equal(new Version(1, 9, 3), ShippedPerTheSite(unpinned));
        Assert.Equal(new Version(1, 9, 3), ShippedPerTheSite(pinned));

        const string feed = """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
              <item><title>Plantoir 1.9.0</title><enclosure url="a" sparkle:version="1.9.0" /></item>
              <item><title>Plantoir 1.10.1</title><sparkle:version>1.10.1</sparkle:version><enclosure url="b" /></item>
              <item><title>Plantoir 1.9.3</title><enclosure url="c" sparkle:version="1.9.3" /></item>
            </channel></rss>
            """;
        Assert.Equal(new Version(1, 10, 1), NewestInTheFeed(feed));

        Assert.Equal(ThisBuild(), Baseline("build").Version);
        Assert.Equal(LastWindowsRelease(), Baseline(null).Version);
        Assert.Equal(LastWindowsRelease(), Baseline("").Version);
        Assert.Throws<InvalidOperationException>(() => Baseline("Build"));
        Assert.Throws<InvalidOperationException>(() => Baseline("csproj"));
    }

    /// <summary>
    /// The rule itself, against entries made up here, so it stays exercised
    /// whatever the ledger holds: an empty ledger (as from #514, 2026-10-15,
    /// to 2026-10-16) or one whose entries all happen to be later than the
    /// baseline would otherwise leave it green however it broke.
    /// </summary>
    [Fact]
    public void TheRuleStillCatchesAnEntryOwedByThisBuildOrByNoVersion()
    {
        var build = new Version(1, 7, 1);
        NamedGapLedger.Entry Owed(string milestone) =>
            new(NamedGapLedger.ActivityTrailEvents, "an event", 1, milestone, "made up for this test");
        Assert.Empty(Problems(new[] { Owed("v1.8.0") }, build, "made up"));
        Assert.Single(Problems(new[] { Owed("v1.7.1") }, build, "made up"));
        Assert.Single(Problems(new[] { Owed("v1.5.0") }, build, "made up"));
        Assert.Single(Problems(new[] { Owed("Windows: parity with mac v1.4.0") }, build, "made up"));
    }

    // ---- The two kinds of C# hook, proved on made-up entries (step 0 of
    // v2.0.0, 2026-11-13): an entry fails the day its thing EXISTS here, and
    // the day it LEAVES the contract, whatever the ledger holds today. The
    // third kind, the launcher runner's, is proved in
    // LauncherRulesContractTests.TheRunnersLedgerHoldsClosesAndCatchesWhatItShould.

    private static NamedGapLedger.Entry Made(string area, string key) => new(area, key, 1, "v9.9.9", "made up for this test");

    /// <summary>The collect-then-compare hooks (GapsIn): held while missing, closed once here, withdrawn once gone.</summary>
    [Fact]
    public void ACollectedHookHoldsWhileMissingAndFailsOnceItExistsOrIsWithdrawn()
    {
        var area = NamedGapLedger.ShelfWording;
        var entries = new[] { Made(area, "aSentence") };
        Assert.Equal(new[] { "aSentence" }, NamedGapLedger.GapsIn(area, new[] { "aSentence", "another" }, new[] { "another" }, entries));
        var closed = Assert.ThrowsAny<Exception>(() => NamedGapLedger.GapsIn(area, new[] { "aSentence" }, new[] { "aSentence" }, entries));
        Assert.Contains("now EXISTS on this side", closed.Message);
        var withdrawn = Assert.ThrowsAny<Exception>(() => NamedGapLedger.GapsIn(area, new[] { "another" }, Array.Empty<string>(), entries));
        Assert.Contains("the contract no longer names it", withdrawn.Message);
        // Another area's entry holds nothing here.
        Assert.Empty(NamedGapLedger.GapsIn(NamedGapLedger.ImportWording, new[] { "aSentence" }, Array.Empty<string>(), entries));
    }

    /// <summary>The held-must-still-fail hook (a sentence said in older words): held while it differs, closed once it matches, withdrawn once gone.</summary>
    [Fact]
    public void AHeldSentenceMustStillDifferAndIsWithdrawnWithItsKey()
    {
        var area = NamedGapLedger.AssistWordingSaidDifferently;
        var entries = new[] { Made(area, "aSentence") };
        var wording = new System.Text.Json.Nodes.JsonObject { ["aSentence"] = "the new words", ["another"] = "kept" };
        ContractTests.SaidAsTheContract(wording, "aSentence", "the old words", entries: entries);
        var closed = Assert.ThrowsAny<Exception>(() => ContractTests.SaidAsTheContract(wording, "aSentence", "the new words", entries: entries));
        Assert.Contains("now EXISTS on this side", closed.Message);
        Assert.ThrowsAny<Exception>(() => ContractTests.SaidAsTheContract(wording, "another", "changed", entries: entries));
        var withdrawn = Assert.ThrowsAny<Exception>(() => NamedGapLedger.StillNamed(area, new[] { "another" }, entries));
        Assert.Contains("the contract no longer names it", withdrawn.Message);
    }

    private static System.Collections.Generic.List<string> Problems(
        System.Collections.Generic.IEnumerable<NamedGapLedger.Entry> entries, Version baseline, string described)
    {
        return entries
            .Select(entry =>
            {
                string milestone = entry.Milestone;
                string bare = milestone.StartsWith('v') ? milestone[1..] : milestone;
                if (!Version.TryParse(bare, out var owedBy))
                    return $"{entry.Area} → \"{entry.Key}\" (#{entry.Issue}) names the milestone " +
                           $"\"{milestone}\", which is not a version, so nothing can tell whether it is " +
                           "later than the baseline. Name the GitHub milestone the issue carries (\"v1.6.0\").";
                if (owedBy <= baseline)
                    return $"{entry.Area} → \"{entry.Key}\" is owed by #{entry.Issue} on {milestone}, and " +
                           $"the baseline is {baseline}, {described}. A ledger entry may only hold open work a LATER " +
                           "release owns: build it, or move the issue (and this entry) to a later milestone " +
                           "with Russell's say-so — never cut a release over it.";
                return (string?)null;
            })
            .Where(problem => problem is not null)
            .Select(problem => problem!)
            .ToList();
    }
}
