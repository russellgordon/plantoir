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
        public Task<UpdateAnswer> OfferAsync(string version, string? notes) { Shown.Add("offer " + version); return Task.FromResult(UpdateAnswer.Install); }
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
        new(feed, "", prompts, snapshot ?? Nothing, servers ?? (() => Array.Empty<int>()), "1.1 (0)", perUserInstall: true,
            feedReaderForTests: () => reader);

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
