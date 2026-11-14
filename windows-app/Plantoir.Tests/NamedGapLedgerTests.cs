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

    private static string ThisBuild() =>
        BuildVersionIn(File.ReadAllText(Path.Combine(RepoRoot, "windows-app", "Plantoir", "Plantoir.csproj")));

    /// <summary>
    /// <c>&lt;Version&gt;</c> in a csproj's text, refused when its first part is
    /// not a number (blank, "v2.0.0"): such a value sorts below every milestone,
    /// so the cut's check would say nothing is owed. The same guard as
    /// <see cref="LastWindowsRelease"/>'s.
    /// </summary>
    internal static string BuildVersionIn(string csprojXml)
    {
        string version = XDocument.Parse(csprojXml).Descendants("Version").Single().Value.Trim();
        if (VersionKey(version)[0] < 0)
            throw new InvalidOperationException(
                $"Plantoir.csproj's <Version> is \"{version}\", which cannot be compared with a milestone: " +
                "write the release's number, \"2.0.0\".");
        return version;
    }

    // ---- Versions compared the way website/windows_feed.py compares them -----
    // (#862 review L1). The deploy of plantoir.app decides what Windows shipped
    // with `version_key` and `newest_item`; the ledger reads the same files and
    // must not reach a different answer. So a version is its dotted parts as
    // numbers, a part that is not a number counts as -1, trailing zeros are
    // dropped ("1.9.3.0" is "1.9.3"), and two are compared part by part, the
    // shorter first when one is the start of the other (Python's tuples). That
    // ordering has a quirk kept on purpose, because agreeing is the point:
    // "2.0.0-rc1" is (2, 0, -1), which is ABOVE "2.0.0" (2). The generator
    // writes plain three-part numbers, so the quirk is only ever met by a
    // hand-edited feed, and the rule then errs strict.

    /// <summary><c>windows_feed.version_key</c>: "1.4.10" above "1.4.9"; a part that is not a number is -1.</summary>
    internal static int[] VersionKey(string? text)
    {
        var parts = (text ?? "").Trim().Split('.')
            .Select(part => part.Length > 0 && part.All(char.IsAsciiDigit) ? int.Parse(part) : -1)
            .ToList();
        while (parts.Count > 1 && parts[^1] == 0)
            parts.RemoveAt(parts.Count - 1);
        return parts.ToArray();
    }

    /// <summary>Python's tuple order over two <see cref="VersionKey"/>s.</summary>
    internal static int CompareVersions(string? left, string? right)
    {
        int[] a = VersionKey(left), b = VersionKey(right);
        for (int i = 0; i < Math.Min(a.Length, b.Length); i++)
        {
            if (a[i] != b[i])
                return a[i].CompareTo(b[i]);
        }
        return a.Length.CompareTo(b.Length);
    }

    /// <summary>
    /// The release Windows last shipped an installer in, as <c>site.json</c>
    /// says: the Windows card's <c>pinned</c> when it has one, else the version
    /// line (<c>windows_feed.shipped_version</c>, #861).
    /// </summary>
    internal static string? ShippedPerTheSite(string siteJson)
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
        return string.IsNullOrEmpty(version) ? null : version;
    }

    /// <summary>
    /// The feed's newest item, the one the updater offers: the HIGHEST
    /// <c>sparkle:version</c> wherever it sits in the file
    /// (<c>windows_feed.newest_item</c>), the enclosure's attribute first and
    /// the element when the attribute is missing OR EMPTY (Python's <c>or</c>).
    /// </summary>
    internal static string? NewestInTheFeed(string feedXml)
    {
        XNamespace sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle";
        string? newest = null;
        foreach (var item in XDocument.Parse(feedXml).Descendants("item"))
        {
            string? attribute = (string?)item.Element("enclosure")?.Attribute(sparkle + "version");
            string version = (attribute is { Length: > 0 } ? attribute : (string?)item.Element(sparkle + "version") ?? "").Trim();
            if (newest is null || CompareVersions(version, newest) > 0)
                newest = version;
        }
        return string.IsNullOrEmpty(newest) ? null : newest;
    }

    private static string CommittedSite => File.ReadAllText(Path.Combine(RepoRoot, "website", "site.json"));

    private static string CommittedFeed => File.ReadAllText(Path.Combine(RepoRoot, "website", "updates", "windows.xml"));

    /// <summary>
    /// The last release Windows shipped, from the committed <c>site.json</c>
    /// and <c>windows.xml</c>. When they disagree (they must not: the deploy
    /// refuses it) the HIGHER is used, so a half-made cut never lets an entry
    /// through; <see cref="TheSiteAndTheFeedAgreeOnWhatWindowsLastShipped"/>
    /// fails for the disagreement itself. A value whose FIRST part is not a
    /// number ("v1.9.3", "") is refused: it would sort below every milestone
    /// and let every entry through.
    /// </summary>
    private static string LastWindowsRelease()
    {
        var site = ShippedPerTheSite(CommittedSite);
        var feed = NewestInTheFeed(CommittedFeed);
        if (site is null || feed is null || VersionKey(site)[0] < 0 || VersionKey(feed)[0] < 0)
            throw new InvalidOperationException(
                $"Could not read the last Windows release: site.json says {site ?? "nothing"}, " +
                $"updates/windows.xml offers {feed ?? "nothing"}.");
        return CompareVersions(site, feed) > 0 ? site : feed;
    }

    /// <summary>
    /// What the rule compares with: the last Windows release, or the release
    /// being built when <see cref="BaselineSwitch"/> is <c>build</c> (what
    /// <c>publish.ps1</c> sets). Any other value is refused rather than read
    /// as the default, so a misspelt switch at the cut cannot pass quietly.
    /// </summary>
    internal static (string Version, string Described) Baseline(string? switchValue)
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
        Assert.True(CompareVersions(site, feed) == 0,
            $"site.json says Windows last shipped in {site}, but updates/windows.xml offers {feed}. " +
            "The deploy of plantoir.app refuses this too: correct the feed or the pin at the cut " +
            "(RELEASING.md → \"The update feed (Windows)\"). Between committing a cut's feed and moving " +
            "site.json's version line this is expected to be red.");
    }

    /// <summary>
    /// The readers on made-up files, so the cases that matter are proved
    /// whatever is committed today: an unpinned card, a pinned one (a mac-only
    /// cut), a feed whose newest item is neither its first nor spelled the
    /// same way, the three inputs on which this once disagreed with
    /// <c>windows_feed.py</c> (#862 review L1), and the switch's values.
    /// </summary>
    [Fact]
    public void TheBaselineIsReadFromThePinTheVersionLineAndTheNewestItem()
    {
        const string unpinned = """{"version": "1.9.3", "downloads": [{"platform": "macOS", "pinned": "1.9.2"}, {"platform": "Windows", "pinned": null}]}""";
        const string pinned = """{"version": "2.0.0", "downloads": [{"platform": "macOS", "pinned": null}, {"platform": "Windows", "pinned": "1.9.3"}]}""";
        Assert.Equal("1.9.3", ShippedPerTheSite(unpinned));
        Assert.Equal("1.9.3", ShippedPerTheSite(pinned));

        static string Feed(string items) =>
            "<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel>" + items + "</channel></rss>";
        Assert.Equal("1.10.1", NewestInTheFeed(Feed(
            "<item><enclosure url=\"a\" sparkle:version=\"1.9.0\" /></item>" +
            "<item><sparkle:version>1.10.1</sparkle:version><enclosure url=\"b\" /></item>" +
            "<item><enclosure url=\"c\" sparkle:version=\"1.9.3\" /></item>")));
        // What windows_feed.newest_item answers for each (measured by the review, Python 3.14, -I).
        Assert.Equal("2.0.0-rc1", NewestInTheFeed(Feed(
            "<item><enclosure url=\"a\" sparkle:version=\"1.9.3\" /></item>" +
            "<item><enclosure url=\"b\" sparkle:version=\"2.0.0-rc1\" /></item>")));
        Assert.Equal("1.9.3.1", NewestInTheFeed(Feed(
            "<item><enclosure url=\"a\" sparkle:version=\"1.9.3\" /></item>" +
            "<item><enclosure url=\"b\" sparkle:version=\"1.9.3.1\" /></item>")));
        Assert.Equal("2.0.0", NewestInTheFeed(Feed(
            "<item><enclosure url=\"a\" sparkle:version=\"1.9.3\" /></item>" +
            "<item><sparkle:version>2.0.0</sparkle:version><enclosure url=\"b\" sparkle:version=\"\" /></item>")));
        // version_key's order: numbers part by part, trailing zeros dropped.
        Assert.True(CompareVersions("1.10", "1.9.9") > 0);
        Assert.Equal(0, CompareVersions("1.9.3.0", "1.9.3"));
        Assert.True(CompareVersions("1.9.3.1", "1.9.3") > 0);

        // A <Version> the cut cannot compare is refused, never read as "nothing
        // owed": blank or "v2.0.0" would sort below every milestone (#862 fixes review L1).
        static string Csproj(string version) => $"<Project><PropertyGroup><Version>{version}</Version></PropertyGroup></Project>";
        Assert.Equal("2.0.0", BuildVersionIn(Csproj(" 2.0.0 ")));
        Assert.Throws<InvalidOperationException>(() => BuildVersionIn(Csproj("")));
        Assert.Throws<InvalidOperationException>(() => BuildVersionIn(Csproj("v2.0.0")));
        Assert.Throws<InvalidOperationException>(() => BuildVersionIn(Csproj("two")));

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
        const string build = "1.7.1";
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

    /// <summary>
    /// The renamed-menu-item area (the fourth hold, 2026-11-14): each entry has
    /// exactly one older name, and no older name is left without its entry,
    /// so the map cannot outlive the hold it serves.
    /// </summary>
    [Fact]
    public void EveryItemHeldUnderAnOlderNameHasOneAndOnlyThose()
    {
        var held = NamedGapLedger.All.Where(entry => entry.Area == NamedGapLedger.SubjectMenuItemsUnderAnOlderName)
            .Select(entry => entry.Key).OrderBy(key => key, StringComparer.Ordinal).ToList();
        Assert.Equal(held, NamedGapLedger.SubjectMenuItemsOlderNames.Keys.OrderBy(key => key, StringComparer.Ordinal).ToList());
        // An item held as missing outright is taken out of every comparison
        // before its older name is read, so holding it here too would hold nothing.
        var missing = NamedGapLedger.All.Where(entry => entry.Area == NamedGapLedger.SubjectMenuItems).Select(entry => entry.Key).ToHashSet();
        Assert.Empty(held.Where(missing.Contains));
    }

    private static System.Collections.Generic.List<string> Problems(
        System.Collections.Generic.IEnumerable<NamedGapLedger.Entry> entries, string baseline, string described)
    {
        return entries
            .Select(entry =>
            {
                string milestone = entry.Milestone;
                string bare = milestone.StartsWith('v') ? milestone[1..] : milestone;
                if (!Version.TryParse(bare, out _))
                    return $"{entry.Area} → \"{entry.Key}\" (#{entry.Issue}) names the milestone " +
                           $"\"{milestone}\", which is not a version, so nothing can tell whether it is " +
                           "later than the baseline. Name the GitHub milestone the issue carries (\"v1.6.0\").";
                if (CompareVersions(bare, baseline) <= 0)
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
