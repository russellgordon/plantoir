using System.Text;
using NetSparkleUpdater.Interfaces;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// #337, the engine: never reaches the network while the feed is empty;
/// refuses an unsigned feed; asks the install gate again at the moment of
/// install; sets a prepared update aside at a quit with work under way. No
/// test here touches the network — a FAKE feed reader stands for plantoir.app,
/// and a FAKE pid for a running plantoir-mcp.
/// </summary>
[Collection(SharedActivityState.Name)]
public class AppUpdaterTests
{
    private sealed class FakeReader : IAppCastDataDownloader
    {
        public int Reads;
        public string Answer = "";
        public string DownloadAndGetAppCastData(string url) { Reads++; return url.EndsWith(".signature") ? "" : Answer; }
        public Task<string> DownloadAndGetAppCastDataAsync(string url) => Task.FromResult(DownloadAndGetAppCastData(url));
        public Encoding GetAppCastEncoding() => Encoding.UTF8;
    }

    private sealed class FakePrompts : IUpdatePrompts
    {
        public readonly List<string> Shown = new();
        public (string Path, string Args)? Installed;
        /// <summary>What the teacher answers each offer; Install unless a test says otherwise.</summary>
        public UpdateAnswer Answer = UpdateAnswer.Install;
        public readonly List<(string Version, bool Important)> Offers = new();
        public Task<UpdateAnswer> OfferAsync(string version, string? notes, bool important)
        {
            Shown.Add("offer " + version);
            Offers.Add((version, important));
            return Task.FromResult(Answer);
        }
        public Task ShowUpToDateAsync() { Shown.Add("upToDate"); return Task.CompletedTask; }
        public Task ShowCouldNotCheckAsync() { Shown.Add("couldNotCheck"); return Task.CompletedTask; }
        public Task ShowHeldAsync(string work, bool onceInstalling) { Shown.Add("held " + work); return Task.CompletedTask; }
        public Task ShowNeedsAdministratorAsync() { Shown.Add("needsAdministrator"); return Task.CompletedTask; }
        public void QuitForInstall(string installerPath, string arguments) => Installed = (installerPath, arguments);
    }

    private static AppUpdates.Snapshot Nothing() => new(new List<(string, int)>(), new List<(string, int)>(), 0,
        new List<AppUpdates.OtherCopy>(), new List<AppUpdates.LeaseFact>());

    private static AppUpdates.Snapshot Publishing() => Nothing() with { Publishes = new List<(string, int)> { ("ICS3U", 1) } };

    private static AppUpdater Make(string feed, FakePrompts prompts, FakeReader reader,
                                   Func<AppUpdates.Snapshot>? snapshot = null, Func<IReadOnlyList<int>>? servers = null) =>
        new(feed, "", prompts, snapshot ?? Nothing, servers ?? (() => Array.Empty<int>()), "1.1.0", perUserInstall: true,
            feedReaderForTests: () => reader);

    // ---- A SIGNED fake feed (#453, #465) ----------------------------------------
    //
    // Strict refuses an unsigned feed, so the tests above only ever reach
    // "refused". These sign one with a throwaway Ed25519 key made from a fixed
    // seed, so the real engine parses it, compares it with the running version
    // and hands this class an offer. NetSparkle compares against the ENTRY
    // assembly's version (the test host's), so the items are 999.x: anything
    // lower might not be "newer" than whatever runs the tests.

    private static readonly byte[] Seed = Enumerable.Range(1, 32).Select(i => (byte)i).ToArray();
    private static string TestPublicKey => Convert.ToBase64String(Chaos.NaCl.Ed25519.PublicKeyFromSeed(Seed));
    private static string SignedBy(string text) => Convert.ToBase64String(
        Chaos.NaCl.Ed25519.Sign(Encoding.UTF8.GetBytes(text), Chaos.NaCl.Ed25519.ExpandedPrivateKeyFromSeed(Seed)));

    /// <summary>A feed reader that answers the feed and its detached signature, as plantoir.app does.</summary>
    private sealed class SignedReader : IAppCastDataDownloader
    {
        public int Reads;
        public string Feed = "";
        public string DownloadAndGetAppCastData(string url) { Reads++; return url.EndsWith(".signature") ? SignedBy(Feed) : Feed; }
        public Task<string> DownloadAndGetAppCastDataAsync(string url) => Task.FromResult(DownloadAndGetAppCastData(url));
        public Encoding GetAppCastEncoding() => Encoding.UTF8;
    }

    private static string FeedOf(params (string Version, bool Important)[] items) =>
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
        "<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><title>Plantoir</title>\n" +
        string.Concat(items.Select(i =>
            $"<item><title>Plantoir {i.Version}</title><description>New in {i.Version}</description><sparkle:version>{i.Version}</sparkle:version>" +
            $"<enclosure url=\"https://example.invalid/{i.Version}/PlantoirSetup.exe\" sparkle:version=\"{i.Version}\" length=\"1\" " +
            $"sparkle:os=\"windows\" type=\"application/octet-stream\" sparkle:criticalUpdate=\"{(i.Important ? "true" : "false")}\" " +
            $"sparkle:signature=\"{SignedBy(i.Version)}\" /></item>\n")) +
        "</channel></rss>";

    private static AppUpdater MakeSigned(FakePrompts prompts, SignedReader reader, string? skipped = null) =>
        new("https://example.invalid/windows.xml", TestPublicKey, prompts, Nothing, () => Array.Empty<int>(), "1.1.0",
            perUserInstall: true, skippedVersion: skipped, feedReaderForTests: () => reader);

    [Fact]
    public async Task ASignedFeedReachesTheOfferAndAPlainOneAllowsSkip()
    {
        var prompts = new FakePrompts { Answer = UpdateAnswer.NotNow };
        var reader = new SignedReader { Feed = FeedOf(("999.0.1", false)) };
        using var updater = MakeSigned(prompts, reader);
        await updater.CheckAsync(teacherAsked: true);
        Assert.True(reader.Reads > 0, "the fake feed was never read");
        Assert.Equal(("999.0.1", false), Assert.Single(prompts.Offers));
    }

    /// <summary>#453: the newest is plain, an older newer one is important — the offer is important.</summary>
    [Fact]
    public async Task AnyNewerImportantReleaseMakesTheOfferImportant()
    {
        var prompts = new FakePrompts { Answer = UpdateAnswer.NotNow };
        var reader = new SignedReader { Feed = FeedOf(("999.0.2", false), ("999.0.1", true)) };
        using var updater = MakeSigned(prompts, reader);
        await updater.CheckAsync(teacherAsked: false);
        Assert.Equal(("999.0.2", true), Assert.Single(prompts.Offers));
    }

    /// <summary>#453: a skipped important release is offered again by the DAILY check.</summary>
    [Fact]
    public async Task ASkippedImportantReleaseIsOfferedAgainByTheDailyCheck()
    {
        DateTime? last = null;
        var prompts = new FakePrompts { Answer = UpdateAnswer.NotNow };
        var reader = new SignedReader { Feed = FeedOf(("999.0.1", true)) };
        using var updater = MakeSigned(prompts, reader, skipped: "999.0.1").RememberingDailyChecksIn(() => last, when => last = when);
        await updater.CheckAsync(teacherAsked: false);
        Assert.Equal(("999.0.1", true), Assert.Single(prompts.Offers));
        Assert.NotNull(last);   // shown and answered: the day is done
    }

    /// <summary>The other half, unchanged: a skipped PLAIN release is not offered by the daily check, and the day is done.</summary>
    [Fact]
    public async Task ASkippedPlainReleaseIsNotOfferedByTheDailyCheck()
    {
        DateTime? last = null;
        var prompts = new FakePrompts();
        var reader = new SignedReader { Feed = FeedOf(("999.0.1", false)) };
        using var updater = MakeSigned(prompts, reader, skipped: "999.0.1").RememberingDailyChecksIn(() => last, when => last = when);
        await updater.CheckAsync(teacherAsked: false);
        Assert.True(reader.Reads > 0, "the fake feed was never read");
        Assert.Empty(prompts.Offers);
        Assert.NotNull(last);
    }

    /// <summary>#453: an important offer never writes a skip, even if one came back.</summary>
    [Fact]
    public async Task AnImportantOfferNeverRemembersASkip()
    {
        var remembered = new List<string?>();
        var prompts = new FakePrompts { Answer = UpdateAnswer.Skip };
        var reader = new SignedReader { Feed = FeedOf(("999.0.1", true)) };
        using var updater = new AppUpdater("https://example.invalid/windows.xml", TestPublicKey, prompts, Nothing,
            () => Array.Empty<int>(), "1.1.0", perUserInstall: true, rememberSkip: remembered.Add, feedReaderForTests: () => reader);
        await updater.CheckAsync(teacherAsked: false);
        Assert.Single(prompts.Offers);
        Assert.Empty(remembered);
    }

    /// <summary>
    /// #465: an offer nobody saw is not an answer. Nothing is written for it,
    /// the day is NOT done, and the check asks to look again in a minute, then
    /// two — backing off, never every minute for ever.
    /// </summary>
    [Fact]
    public async Task AnOfferNobodySawIsNotTheDaysCheck()
    {
        string trail = Path.Combine(Directory.CreateTempSubdirectory("plantoir-465").FullName, "activity.txt");
        Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            DateTime? last = null;
            var prompts = new FakePrompts { Answer = UpdateAnswer.NotShown };
            var reader = new SignedReader { Feed = FeedOf(("999.0.1", false)) };
            using var updater = MakeSigned(prompts, reader).RememberingDailyChecksIn(() => last, when => last = when);

            await updater.DailyCheckAsync();
            Assert.Single(prompts.Offers);
            Assert.Null(last);
            Assert.True(updater.DailyCheckIsDue(DateTime.UtcNow));
            Assert.Equal(AppUpdater.FirstRetry, updater.LastRetryScheduled);
            await updater.DailyCheckAsync();
            Assert.Equal(AppUpdater.FirstRetry * 2, updater.LastRetryScheduled);

            string[] lines = File.Exists(trail) ? File.ReadAllLines(trail) : [];
            Assert.Single(lines, l => l.Contains("found 999.0.1, running 1.1.0; the daily check"));   // once per launch
            Assert.DoesNotContain(lines, l => l.Contains("999.0.1: not now"));

            // Then the teacher sees it and answers: the day is done, the answer written.
            prompts.Answer = UpdateAnswer.NotNow;
            await updater.DailyCheckAsync();
            Assert.NotNull(last);
            lines = File.ReadAllLines(trail);
            Assert.Single(lines, l => l.Contains("999.0.1: not now"));
        }
        finally { Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath); }
    }

    /// <summary>#465: the backoff stops growing at the hourly look.</summary>
    [Fact]
    public async Task TheRetryNeverWaitsLongerThanTheHourlyLook()
    {
        var prompts = new FakePrompts { Answer = UpdateAnswer.NotShown };
        var reader = new SignedReader { Feed = FeedOf(("999.0.1", false)) };
        using var updater = MakeSigned(prompts, reader);
        for (int i = 0; i < 10; i++) await updater.DailyCheckAsync();
        Assert.Equal(AppUpdater.HourlyLook, updater.LastRetryScheduled);
    }

    /// <summary>
    /// #465: the daily check starts once the first window is up, in OnLaunched
    /// after the windows are opened, and never inside OpenWindow (the marketing
    /// captures open windows through it). Source-read: the test project cannot
    /// reference the WinUI app.
    /// </summary>
    [Fact]
    public void TheDailyCheckStartsOnceTheFirstWindowIsUp()
    {
        string app = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "App.xaml.cs"));
        Assert.Equal(1, System.Text.RegularExpressions.Regex.Matches(app, @"Updater\??\.Start\(\)").Count);
        int start = app.IndexOf("Updater?.Start();", StringComparison.Ordinal);
        int windowsOpened = app.IndexOf("OpenWindow(entry.Path, entry);", StringComparison.Ordinal);
        int openWindow = app.IndexOf("public static MainWindow OpenWindow(", StringComparison.Ordinal);
        Assert.True(start > windowsOpened && windowsOpened > 0, "the daily check starts before the windows are opened");
        Assert.True(start < openWindow, "the daily check starts inside OpenWindow, where the marketing captures would start it too");
        int scene = app.IndexOf("_ = MarketingShotCapturer.StageAsync(scene);", StringComparison.Ordinal);
        Assert.True(scene > 0 && scene < start, "a marketing capture returns after the daily check has started");
    }

    [Fact]
    public void TheReleasedAppReadsTheContractsFeedWithAKey()
    {
        Assert.Equal(AppUpdates.Feed, AppUpdates.ConfiguredFeed);
        Assert.Equal(32, Convert.FromBase64String(AppUpdates.PublicKey).Length);   // an Ed25519 public key
    }

    [Fact]
    public async Task AnEmptyFeedNeverReachesTheNetwork()
    {
        var prompts = new FakePrompts();
        var reader = new FakeReader();
        using var updater = Make("", prompts, reader);
        updater.Start();
        await updater.CheckAsync(teacherAsked: true);
        await updater.CheckAsync(teacherAsked: false);
        Assert.False(updater.IsActive);
        Assert.False(updater.HasEngine);
        Assert.Equal(0, reader.Reads);
        Assert.Empty(prompts.Shown);
    }

    [Fact]
    public async Task AnUnsignedFeedIsRefused()
    {
        var prompts = new FakePrompts();
        var reader = new FakeReader
        {
            Answer = """
                <?xml version="1.0" encoding="UTF-8"?>
                <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Plantoir</title>
                <item><title>9.9</title><sparkle:version>9.9.0</sparkle:version><sparkle:os>windows</sparkle:os>
                <enclosure url="https://example.invalid/PlantoirSetup.exe" sparkle:version="9.9.0" length="1" type="application/octet-stream" /></item>
                </channel></rss>
                """,
        };
        using var updater = Make("https://example.invalid/windows.xml", prompts, reader);
        await updater.CheckAsync(teacherAsked: true);
        Assert.True(reader.Reads > 0, "The fake feed was never read, so this proved nothing.");
        Assert.DoesNotContain(prompts.Shown, s => s.StartsWith("offer"));
        Assert.Null(prompts.Installed);
    }

    [Fact]
    public void TheVerifierRequiresEd25519AndRefusesAnUnsignedFeed()
    {
        using var updater = Make("https://example.invalid/windows.xml", new FakePrompts(), new FakeReader());
        Assert.Equal(NetSparkleUpdater.Enums.SecurityMode.Strict, updater.VerifierModeForTests);
    }

    [Fact]
    public async Task TheGateIsAskedAgainAtTheMomentOfInstall()
    {
        var prompts = new FakePrompts();
        int asked = 0;
        // Free when the update was offered; a publish starts before the install.
        AppUpdates.Snapshot Snapshot() => ++asked == 1 ? Publishing() : Nothing();
        using var updater = Make("https://example.invalid/windows.xml", prompts, new FakeReader(), Snapshot);
        updater.LookAgainEvery = TimeSpan.FromMilliseconds(10);
        updater.PreparedForTests(Path.Combine(Path.GetTempPath(), "PlantoirSetup-test.exe"), "9.9.0");
        await updater.InstallWhenFreeAsync(askedAgain: false);
        Assert.Contains(prompts.Shown, s => s.StartsWith("held "));
        Assert.NotNull(prompts.Installed);
        Assert.Contains("/RELAUNCH=1", prompts.Installed!.Value.Args);
        Assert.True(asked >= 2);
    }

    [Fact]
    public async Task ARunningAssistantServerHoldsTheInstall()
    {
        var prompts = new FakePrompts();
        int calls = 0;
        IReadOnlyList<int> Servers() => ++calls == 1 ? new[] { 424242 } : Array.Empty<int>();
        using var updater = Make("https://example.invalid/windows.xml", prompts, new FakeReader(), servers: Servers);
        updater.LookAgainEvery = TimeSpan.FromMilliseconds(10);
        updater.PreparedForTests(Path.Combine(Path.GetTempPath(), "PlantoirSetup-test.exe"), "9.9.0");
        await updater.InstallWhenFreeAsync(askedAgain: false);
        Assert.Contains("held " + UpdateWording.AssistantElsewhereWork, prompts.Shown);
    }

    /// <summary>Ruling 7: a quit is decided by the install gate, so an update held for a running plantoir-mcp (FAKE pid) is set aside, never installed on the way out.</summary>
    [Fact]
    public void AQuitWhileAnAssistantServerRunsSetsTheHeldUpdateAside()
    {
        string installer = Path.Combine(Path.GetTempPath(), $"PlantoirSetup-{Guid.NewGuid():N}.exe");
        File.WriteAllText(installer, "x");
        using var updater = Make("https://example.invalid/windows.xml", new FakePrompts(), new FakeReader(),
                                 servers: () => new[] { 424242 });
        updater.PreparedForTests(installer, "9.9.0");
        Assert.Null(updater.AtQuitGated());
        Assert.False(File.Exists(installer));
    }

    [Fact]
    public void TheDailyCheckFollowsTheWallClock()
    {
        DateTime? last = null;
        using var updater = Make("https://example.invalid/windows.xml", new FakePrompts(), new FakeReader())
            .RememberingDailyChecksIn(() => last, when => last = when);
        var now = new DateTime(2026, 10, 1, 8, 0, 0, DateTimeKind.Utc);
        Assert.True(updater.DailyCheckIsDue(now));
        last = now;                                          // a check that got an answer
        Assert.False(updater.DailyCheckIsDue(now.AddHours(23)));
        Assert.True(updater.DailyCheckIsDue(now.AddHours(24)));
    }

    /// <summary>Ruling 13: an offline or failed daily check does not stamp the day.</summary>
    [Fact]
    public async Task AFailedDailyCheckDoesNotCountAsTheDays()
    {
        DateTime? last = null;
        var reader = new FakeReader { Answer = "not a feed" };
        using var updater = Make("https://example.invalid/windows.xml", new FakePrompts(), reader)
            .RememberingDailyChecksIn(() => last, when => last = when);
        await updater.CheckAsync(teacherAsked: false);
        Assert.True(reader.Reads > 0, "the fake feed was never read");
        Assert.Null(last);
        Assert.True(updater.DailyCheckIsDue(DateTime.UtcNow));
    }

    [Fact]
    public void AQuitWithWorkUnderWaySetsTheUpdateAside()
    {
        string installer = Path.Combine(Path.GetTempPath(), $"PlantoirSetup-{Guid.NewGuid():N}.exe");
        File.WriteAllText(installer, "x");
        using var updater = Make("https://example.invalid/windows.xml", new FakePrompts(), new FakeReader());
        updater.PreparedForTests(installer, "9.9.0");
        Assert.Null(updater.AtQuit(workUnderWay: true, "a deploy"));
        Assert.False(File.Exists(installer));
        Assert.Equal(AppUpdates.Prepared.None, updater.Prepared);

        updater.PreparedForTests(installer, "9.9.0");
        var install = updater.AtQuit(workUnderWay: false, "");
        Assert.NotNull(install);
        Assert.DoesNotContain("RELAUNCH", install!.Value.Arguments);
    }
}
