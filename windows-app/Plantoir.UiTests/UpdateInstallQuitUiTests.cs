using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using Plantoir.Core.Assist;

namespace Plantoir.UiTests;

/// <summary>
/// #632: Install and Reopen on the DAILY check's offer must quit Plantoir the
/// way the same answer from File ▸ Check for Updates… does — the installer
/// started, the old process gone — or the installer meets a running
/// Plantoir.exe under /NOCLOSEAPPLICATIONS and gives up, and the teacher is left
/// on the old version with a window that looks as if nothing happened.
///
/// <para>A Debug build has no updater, so these name their own feed through the
/// Debug-only seam (<c>--update-feed-for-tests</c>, <c>--update-key-for-tests</c>,
/// <c>--update-first-look-for-tests</c> in App.OnLaunched): a localhost server
/// here serves a feed signed with a throwaway Ed25519 key and an "installer"
/// that is a .cmd writing a marker file — nothing is installed and nothing
/// reopens. Everything between the feed and the quit is the real path.</para>
/// </summary>
[Collection("drives the real app")]
public class UpdateInstallQuitUiTests
{
    private const string Code = "UPD2O";
    private const string Version = "999.0.1";
    /// <summary>The menu path measured 3 s from the click to the old process gone (1.7.2 → 1.8.5, i5-8365U).</summary>
    private static readonly TimeSpan ExitWithin = TimeSpan.FromSeconds(30);

    [UiFact]
    public void InstallFromTheDailyChecksOfferQuitsTheApp() =>
        InstallQuits(daily: true);

    /// <summary>The control: the menu path worked before #632's fix and must still.</summary>
    [UiFact]
    public void InstallFromCheckForUpdatesQuitsTheApp() =>
        InstallQuits(daily: false);

    private static void InstallQuits(bool daily)
    {
        string token = Guid.NewGuid().ToString("N")[..8];
        string installerName = $"PlantoirSetup-632-{token}.cmd";
        string marker = Path.Combine(Path.GetTempPath(), $"plantoir-632-{token}.started");
        using var feed = new SignedFeed(Version, installerName,
            Encoding.ASCII.GetBytes($"@echo off\r\necho %*>\"{marker}\"\r\n"));
        try
        {
            using var app = new DrivenApp(
                courses => EndToEnd.WriteCourse(courses, Code, "Update Course", new[] { "Concepts" }),
                beforeLaunch: folder => SeedLastDailyCheck(folder, daily
                    ? DateTime.UtcNow.AddDays(-2)    // the day's check is due
                    : DateTime.UtcNow),              // not due: the timer must not build the engine first
                extraArguments: new[]
                {
                    "--update-feed-for-tests", feed.FeedUrl,
                    "--update-key-for-tests", feed.PublicKey,
                    "--update-first-look-for-tests", "5",
                });
            string startupLog = Path.Combine(app.StateDirectory, "startup.log");
            string Evidence() => $"{Environment.NewLine}startup.log:{Environment.NewLine}{Tail(startupLog)}" +
                                 $"{Environment.NewLine}trail, the update's lines:{Environment.NewLine}{UpdateLines(app)}";

            // The tools copy must be over first: an install waits for it (#484),
            // and on a fresh folder it can take well over a minute.
            Assert.True(Retry.WhileFalse(() => Read(startupLog).Contains("tools copy finished"),
                                         TimeSpan.FromSeconds(180), TimeSpan.FromMilliseconds(500)).Result,
                        "the tools copy never finished." + Evidence());

            if (!daily) EndToEnd.PressMenuBarItem(app, "File", "fileCheckForUpdates");
            var install = Retry.WhileNull(
                () => app.OpenDialog() is { } dialog && dialog.Name.Contains(Version)
                    ? dialog.FindFirstDescendant(cf => cf.ByAutomationId("PrimaryButton")) : null,
                TimeSpan.FromSeconds(daily ? 90 : 30), TimeSpan.FromMilliseconds(500)).Result;
            Assert.True(install is not null, "the offer never appeared." + Evidence());
            Assert.Contains(daily ? "the daily check" : "the teacher asked", UpdateLines(app));
            Assert.Equal(UpdateWording.OfferInstall, install!.Name);

            var clicked = Stopwatch.StartNew();
            install.AsButton().Invoke();

            Assert.True(Retry.WhileFalse(() => File.Exists(marker), TimeSpan.FromSeconds(60)).Result,
                        "the installer was never started." + Evidence());
            double started = clicked.Elapsed.TotalSeconds;
            bool exited;
            try { exited = Process.GetProcessById(app.ProcessId).WaitForExit(ExitWithin); }
            catch (ArgumentException) { exited = true; }   // already gone
            Console.WriteLine($"#632 ({(daily ? "daily check" : "Check for Updates…")}): installer started {started:0.0} s " +
                              $"after the click; old process {(exited ? $"gone {clicked.Elapsed.TotalSeconds:0.0} s" : "STILL RUNNING")} after it.");
            Assert.True(exited, $"Plantoir was still running {ExitWithin.TotalSeconds:0} s after the installer started." + Evidence());
        }
        finally
        {
            try { File.Delete(marker); } catch { }
            // NetSparkle's download, wherever under %TEMP% it put it.
            foreach (string left in FilesNamed(Path.GetTempPath(), installerName))
                try { File.Delete(left); } catch { }
        }
    }

    private static void SeedLastDailyCheck(string workspace, DateTime utc)
    {
        // DrivenApp keeps what beforeLaunch seeds in the run's settings.json; the
        // state folder is the workspace's sibling.
        string settingsPath = Path.Combine(Path.GetDirectoryName(workspace)!, "state", "settings.json");
        var settings = File.Exists(settingsPath) && JsonNode.Parse(File.ReadAllText(settingsPath)) is JsonObject seeded
            ? seeded : new JsonObject();
        settings["LastUpdateCheckUtc"] = utc.ToString("o");
        File.WriteAllText(settingsPath, settings.ToJsonString(), new UTF8Encoding(false));
    }

    private static string Read(string path)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            return new StreamReader(stream).ReadToEnd();
        }
        catch { return ""; }
    }

    private static string Tail(string path) =>
        string.Join(Environment.NewLine, Read(path).Split('\n').TakeLast(25));

    /// <summary>Every trail line naming the offered version — found, answered, held, installing.</summary>
    private static string UpdateLines(DrivenApp app)
    {
        // Read with the app's own sharing, so a trail being written is still read.
        string trail = Read(Path.Combine(app.StateDirectory, "Logs", "activity.txt"));
        return string.Join(Environment.NewLine, trail.Split('\n').Where(line => line.Contains(Version)));
    }

    private static IEnumerable<string> FilesNamed(string root, string name)
    {
        var found = new List<string>();
        try { found.AddRange(Directory.EnumerateFiles(root, name)); } catch { }
        try
        {
            foreach (string dir in Directory.EnumerateDirectories(root))
                try { found.AddRange(Directory.EnumerateFiles(dir, name)); } catch { }
        }
        catch { }
        return found;
    }

    /// <summary>
    /// A feed on localhost, signed the way plantoir.app's is (the feed's detached
    /// <c>.signature</c> and the download's <c>sparkle:signature</c>), with a
    /// throwaway key. Plain TCP, so it binds without a URL reservation.
    /// </summary>
    private sealed class SignedFeed : IDisposable
    {
        private static readonly byte[] Seed = Enumerable.Range(7, 32).Select(i => (byte)i).ToArray();
        private readonly TcpListener _listener = new(IPAddress.Loopback, 0);
        private readonly Dictionary<string, byte[]> _files = new();
        private readonly CancellationTokenSource _stop = new();

        public string FeedUrl { get; }
        public string PublicKey { get; } = Convert.ToBase64String(Chaos.NaCl.Ed25519.PublicKeyFromSeed(Seed));

        public SignedFeed(string version, string installerName, byte[] installer)
        {
            _listener.Start();
            string root = $"http://127.0.0.1:{((IPEndPoint)_listener.LocalEndpoint).Port}/";
            FeedUrl = root + "windows.xml";
            string feed =
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
                "<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><title>Plantoir</title>\n" +
                $"<item><title>Plantoir {version}</title><description>New in {version}</description><sparkle:version>{version}</sparkle:version>" +
                $"<enclosure url=\"{root}{installerName}\" sparkle:version=\"{version}\" length=\"{installer.Length}\" " +
                "sparkle:os=\"windows\" type=\"application/octet-stream\" sparkle:criticalUpdate=\"false\" " +
                $"sparkle:signature=\"{Sign(installer)}\" /></item>\n" +
                "</channel></rss>";
            byte[] feedBytes = Encoding.UTF8.GetBytes(feed);
            _files["/windows.xml"] = feedBytes;
            _files["/windows.xml.signature"] = Encoding.ASCII.GetBytes(Sign(feedBytes));
            _files["/" + installerName] = installer;
            _ = Task.Run(Serve);
        }

        private static string Sign(byte[] bytes) =>
            Convert.ToBase64String(Chaos.NaCl.Ed25519.Sign(bytes, Chaos.NaCl.Ed25519.ExpandedPrivateKeyFromSeed(Seed)));

        private async Task Serve()
        {
            while (!_stop.IsCancellationRequested)
            {
                TcpClient client;
                try { client = await _listener.AcceptTcpClientAsync(_stop.Token); }
                catch { return; }
                _ = Task.Run(() => Answer(client));
            }
        }

        private void Answer(TcpClient client)
        {
            using (client)
            {
                try
                {
                    var stream = client.GetStream();
                    var reader = new StreamReader(stream, Encoding.ASCII, false, 1024, leaveOpen: true);
                    string requestLine = reader.ReadLine() ?? "";
                    while (!string.IsNullOrEmpty(reader.ReadLine())) { }
                    string[] parts = requestLine.Split(' ');
                    string path = parts.Length > 1 ? parts[1].Split('?')[0] : "/";
                    bool head = parts.Length > 0 && parts[0] == "HEAD";
                    Console.WriteLine($"#632 feed: {requestLine}");
                    byte[] body = _files.TryGetValue(path, out var found) ? found : Array.Empty<byte>();
                    string status = found is null ? "404 Not Found" : "200 OK";
                    string headers = $"HTTP/1.1 {status}\r\nContent-Length: {body.Length}\r\n" +
                                     "Content-Type: application/octet-stream\r\nConnection: close\r\n\r\n";
                    stream.Write(Encoding.ASCII.GetBytes(headers));
                    if (!head) stream.Write(body);
                    stream.Flush();
                }
                catch { }
            }
        }

        public void Dispose()
        {
            _stop.Cancel();
            try { _listener.Stop(); } catch { }
        }
    }
}
