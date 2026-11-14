using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The Planning tab's guarded web view on the REAL WebView2 runtime (790 plan
/// review M1): <c>Plantoir.GuardProbe</c> compiles the app's own
/// <c>GuardedSite.cs</c> and drives it on a Form that is never shown, with a
/// plan folder made here, and these facts read what it printed. It FAILS,
/// never skips, when the probe cannot run: a guard nobody measures is the
/// thing this exists to prevent (a lost line in <c>GuardedSite.Attach</c> stays
/// green otherwise). #811's Coverage tab reuses <see cref="GuardProbe"/> with
/// its own root and host.
/// </summary>
/// <remarks>
/// "The internet" is a <see cref="TcpListener"/> on 127.0.0.1 that counts the
/// connections it accepts. Two runs: the local pages' own environment (its dead
/// proxy, <c>LocalPagesEnvironment.BrowserArguments</c>), which must accept
/// NONE; and the same pages with no proxy, which must accept SOME, so the first
/// run's zero is shown to be the proxy's doing (the plan review measured a
/// preconnect and a meta refresh opening sockets no event sees).
/// </remarks>
public sealed class GuardedSiteTests : IClassFixture<GuardedSiteTests.Runs>
{
    private readonly Runs _runs;

    public GuardedSiteTests(Runs runs) => _runs = runs;

    [Fact]
    public void ThePageLoadsWithItsOwnStylesheetFontAndPictureServed()
    {
        var page = _runs.Proxied.Step("show=" + _runs.Plan.UnitPage);
        Assert.Contains(page, line => line.StartsWith("DONE True 200"));
        Assert.Contains(page, line => line == "REQ served " + _runs.Plan.Address("assets/plan.css"));
        Assert.Contains(page, line => line == "REQ served " + _runs.Plan.Address("assets/fonts/p.woff2"));
        Assert.Contains(page, line => line == "REQ served " + _runs.Plan.Address("unit-1/pic.png") + "?beside");
        // A folder link that stays inside the plan is followed and served.
        Assert.Contains(page, line => line == "REQ served " + _runs.Plan.Address("unit-1/shared/plan.css") + "?through-junction");
        // A frame of the plan, and its own picture.
        Assert.Contains(page, line => line == "REQ served " + _runs.Plan.Address("unit-1/frame.html"));
        Assert.Contains(page, line => line == "REQ served " + _runs.Plan.Address("unit-1/pic.png") + "?frame");
    }

    [Fact]
    public void ScriptsDoNotRun()
    {
        // An inline script, an onload attribute, a srcdoc frame's script and an
        // SVG script each try to change the title; a javascript: link is there
        // to be found. The title is the page's own.
        // Measured twice: with the page policy (which forbids script too) and
        // with no policy at all, where only IsScriptEnabled stands between the
        // page and its scripts.
        Assert.Contains("TITLE plan", _runs.Proxied.Step("title"));
        Assert.Contains("TITLE plan", _runs.HandlerAlone.Step("title"));
    }

    [Fact]
    public void NothingOutsideThePlanningFolderIsRead()
    {
        var page = _runs.Proxied.Step("show=" + _runs.Plan.UnitPage);
        foreach (string outside in new[] { "../../../course_config.json?up", "../../../picture.png?three-up", "shortcut/picture.png?junction-out" })
        {
            string address = new Uri(new Uri(_runs.Plan.Address("unit-1/index.html")), outside).AbsoluteUri;
            Assert.DoesNotContain(page, line => line == "REQ served " + address);
            Assert.Contains(page, line => line == "REQ refused " + address);
        }
        Assert.DoesNotContain(_runs.Proxied.All, line => line.StartsWith("REQ served") && line.Contains("course_config.json"));
    }

    [Fact]
    public void NoRequestToAnotherHostIsEverServed()
    {
        foreach (var run in new[] { _runs.Proxied, _runs.HandlerAlone })
            Assert.DoesNotContain(run.All, line => line.StartsWith("REQ served") && !line.Contains(LocalSiteGuard.PlansHost));
    }

    [Fact]
    public void WithNoPagePolicyEveryKindOfRequestStillReachesTheHandlerAndIsRefused()
    {
        // The header is defence in depth: behind it the page's own policy
        // stops most outside requests before they are made. With it taken off,
        // each kind (the plan review's M2 list) arrives at the handler, which
        // refuses it, and the proxy still lets nothing out.
        var outside = _runs.HandlerAlone.All.Where(line => line.StartsWith("REQ ") && line.Contains("127.0.0.1")).ToList();
        Assert.All(outside, line => Assert.StartsWith("REQ refused ", line));
        var missing = new[] { "/img", "/srcset", "/source", "/poster", "/import.css", "/bg.png", "/frameimg", "/icon", "/prefetch", "/object", "/embed" }
            .Where(kind => !outside.Any(line => line.Contains(":" + _runs.Port + kind + " ") || line.EndsWith(":" + _runs.Port + kind)))
            .ToList();
        Assert.True(missing.Count == 0, "never reached the handler: " + string.Join(", ", missing) + "\n" + string.Join("\n", outside));
        Assert.Equal(0, _runs.HandlerAloneConnections);
    }

    /// <summary>
    /// The page policy fails closed (790b implementation review M1): every
    /// kind a plan uses today is named, so a kind it does NOT name is made by
    /// running the shipped policy with <c>img-src</c> taken out; the page's
    /// own picture, inside the plan, is then never even asked for, because
    /// <c>default-src 'none'</c> stands for the missing directive. (Measured
    /// first with a prefetch, which Chromium does not hold to a page policy:
    /// it was asked for either way.)
    /// </summary>
    [Fact]
    public void AKindThePolicyDoesNotNameIsRefused()
    {
        string picture = _runs.Plan.Address("unit-1/pic.png") + "?beside";
        Assert.Contains(_runs.Proxied.All, line => line == "REQ served " + picture);
        Assert.DoesNotContain(_runs.UnnamedKind.All, line => line.EndsWith(" " + picture));
        Assert.Contains(_runs.UnnamedKind.All, line => line.StartsWith("DONE True 200"));
        Assert.StartsWith("default-src 'none'; ", LocalSiteGuard.PlansContentSecurityPolicy);
    }
    [Fact]
    public void TheLocalPagesEnvironmentReachesNoNetworkAndAPlainOneDoes()
    {
        Assert.Equal(0, _runs.ProxiedConnections);
        Assert.True(_runs.PlainConnections > 0,
            "With no proxy the same pages should open a connection (a preconnect, a meta refresh), or this test cannot tell the proxy is doing the work.");
    }

    [Fact]
    public void ARefreshToTheWebOrOutsideTheFolderIsRefused()
    {
        var web = _runs.Proxied.Step("show=" + _runs.Plan.Folder("unit-1", "refresh.html"));
        Assert.Contains(web, line => line.StartsWith("DECIDE Refuse https://127.0.0.1:" + _runs.Port + "/refresh"));
        var up = _runs.Proxied.Step("show=" + _runs.Plan.Folder("unit-1", "refresh-up.html"));
        Assert.Contains(up, line => line.StartsWith("DECIDE Refuse") && line.Contains("course_config.json"));
        Assert.DoesNotContain(_runs.Proxied.All, line => line.StartsWith("OUTSIDE https://127.0.0.1"));
    }

    [Fact]
    public void AClickToTheWebOrToMailGoesOutsideOnceAndNeverThroughTheSystemPrompt()
    {
        Assert.Single(_runs.Proxied.All, line => line == "OUTSIDE https://example.invalid/web");
        Assert.Single(_runs.Proxied.All, line => line == "OUTSIDE mailto:teacher@example.invalid");
        Assert.DoesNotContain(_runs.Proxied.All, line => line.StartsWith("EXTERNAL") && !line.EndsWith("cancelled=True"));
    }

    [Fact]
    public void AClickOutsideThePlanIsRefusedAndThePageStays()
    {
        var click = _runs.Proxied.StepAfter("click=60,260");
        Assert.Contains(click, line => line.StartsWith("DECIDE Refuse") && line.Contains("course_config.json"));
        Assert.Contains(_runs.Proxied.StepAfter("click=60,260", 1), line => line.EndsWith("clicks.html"));
    }

    [Fact]
    public void ANewWindowLinkLoadsHereAndBackReturns()
    {
        var click = _runs.Proxied.StepAfter("click=60,360");
        Assert.Contains(click, line => line.StartsWith("NEWWINDOW") && line.Contains("unit-2/index.html"));
        Assert.Contains(click, line => line.StartsWith("DECIDE LoadHere") && line.Contains("unit-2/index.html"));
        Assert.Contains(_runs.Proxied.StepAfter("click=60,360", 1), line => line.StartsWith("SOURCE") && line.EndsWith("unit-2/index.html"));
        var back = _runs.Proxied.StepAfter("click=60,360", 2);
        Assert.Contains("CANGOBACK True", back);
        Assert.Contains(_runs.Proxied.StepAfter("click=60,360", 3), line => line.StartsWith("SOURCE") && line.EndsWith("clicks.html"));
    }

    [Fact]
    public void APdfOfThePlanIsServedAsAPdf()
    {
        var click = _runs.Proxied.StepAfter("click=60,460");
        Assert.Contains(click, line => line == "REQ served " + _runs.Plan.Address("unit-1/notes.pdf"));
        Assert.Contains(click, line => line.StartsWith("DONE True 200"));
    }

    [Fact]
    public void AFileOfAnotherTypeIsNotServedAndNothingIsDownloaded()
    {
        var click = _runs.Proxied.StepAfter("click=60,560");
        Assert.Contains(click, line => line == "REQ refused " + _runs.Plan.Address("unit-1/archive.zip"));
        Assert.DoesNotContain(_runs.Proxied.All, line => line.StartsWith("DOWNLOAD") && !line.EndsWith("cancelled=True"));
    }

    [Fact]
    public void ReloadReadsTheDiskAgain()
    {
        var before = _runs.Proxied.StepAfter("copy=", -1);
        var after = _runs.Proxied.StepAfter("copy=", 2);
        Assert.Contains("STYLE rgb(10, 20, 30)", before);
        Assert.Contains("STYLE rgb(200, 0, 0)", after);
    }

    [Fact]
    public void NothingTheViewShowedIsKeptInItsDataFolder()
    {
        // InPrivate, with a profile of its own (whatAPageMayRead: "no website
        // data kept between views"): the browser writes its empty databases,
        // and not one file in the folder names the plan's host or its course,
        // in UTF-8 or UTF-16. A file that cannot be read FAILS the test, by
        // name: unread is not clean (790b implementation review L3).
        string folder = _runs.Plan.UserData("proxied");
        Assert.True(Directory.Exists(Path.Combine(folder, "EBWebView")), "the run made no user-data folder at " + folder);
        var needles = new[] { LocalSiteGuard.PlansHost, "SNC2D" }
            .SelectMany(text => new[] { System.Text.Encoding.UTF8.GetBytes(text), System.Text.Encoding.Unicode.GetBytes(text) })
            .ToList();
        var naming = new List<string>();
        var unread = new List<string>();
        foreach (string file in Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories))
        {
            byte[] bytes;
            try { bytes = File.ReadAllBytes(file); }
            catch (IOException) { unread.Add(file); continue; }
            catch (UnauthorizedAccessException) { unread.Add(file); continue; }
            if (needles.Any(needle => bytes.AsSpan().IndexOf(needle) >= 0)) naming.Add(file);
        }
        Assert.True(unread.Count == 0, "could not be read, so not shown clean: " + string.Join(", ", unread));
        Assert.True(naming.Count == 0, "names the plan: " + string.Join(", ", naming));
    }

    // ---- The runs ------------------------------------------------------------

    /// <summary>One plan folder and two probe runs over it, made once for the class.</summary>
    public sealed class Runs : IDisposable
    {
        public PlanFixture Plan { get; }
        public int Port { get; }
        public GuardProbe.Output Proxied { get; private set; } = null!;
        public GuardProbe.Output Plain { get; private set; } = null!;
        public GuardProbe.Output HandlerAlone { get; private set; } = null!;
        public GuardProbe.Output UnnamedKind { get; private set; } = null!;
        public int ProxiedConnections { get; private set; }
        public int HandlerAloneConnections { get; private set; }
        public int PlainConnections { get; private set; }

        private readonly TcpListener _listener;
        private int _accepted;

        public Runs()
        {
            _listener = new TcpListener(IPAddress.Loopback, 0);
            _listener.Start();
            Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
            _ = AcceptForeverAsync();
            Plan = new PlanFixture(Port);
            try { RunTheProbe(); }
            catch
            {
                // xUnit never disposes a fixture whose constructor threw: tidy
                // the folders now, or they stay in %TEMP% (review L4).
                Dispose();
                throw;
            }
        }

        private void RunTheProbe()
        {

            // First, before the run below changes plan.css on disk.
            HandlerAlone = GuardProbe.Run(Plan.PlanningFolder, "proxy", Plan.UserData("handler"), new[]
            {
                "show=" + Plan.UnitPage, "title",
            }, csp: "none");
            HandlerAloneConnections = Interlocked.Exchange(ref _accepted, 0);

            // The shipped policy with one kind it names taken out.
            UnnamedKind = GuardProbe.Run(Plan.PlanningFolder, "proxy", Plan.UserData("unnamed"), new[]
            {
                "show=" + Plan.UnitPage,
            }, csp: LocalSiteGuard.PlansContentSecurityPolicy.Replace("img-src 'self' data:; ", ""));
            Assert.DoesNotContain("img-src", LocalSiteGuard.PlansContentSecurityPolicy.Replace("img-src 'self' data:; ", ""));
            Interlocked.Exchange(ref _accepted, 0);

            string clicks = Plan.Folder("unit-1", "clicks.html");
            Proxied = GuardProbe.Run(Plan.PlanningFolder, "proxy", Plan.UserData("proxied"), new[]
            {
                "show=" + Plan.UnitPage, "title",
                "show=" + Plan.Folder("unit-1", "refresh.html"),
                "show=" + Plan.Folder("unit-1", "refresh-up.html"),
                "show=" + clicks, "click=60,60",
                "show=" + clicks, "click=60,160",
                "show=" + clicks, "click=60,260", "source",
                "show=" + clicks, "click=60,360", "source", "back", "source",
                "show=" + clicks, "click=60,460",
                "show=" + clicks, "click=60,560",
                "show=" + Plan.UnitPage, "style=body|color",
                "copy=" + Plan.Folder("assets", "plan-red.css") + "|" + Plan.Folder("assets", "plan.css"),
                "reload", "style=body|color",
            });
            ProxiedConnections = Interlocked.Exchange(ref _accepted, 0);

            Plain = GuardProbe.Run(Plan.PlanningFolder, "plain", Plan.UserData("plain"), new[]
            {
                "show=" + Plan.UnitPage,
                "show=" + Plan.Folder("unit-1", "refresh.html"),
            });
            Thread.Sleep(500);
            PlainConnections = Interlocked.Exchange(ref _accepted, 0);
        }

        private async Task AcceptForeverAsync()
        {
            try
            {
                while (true)
                {
                    using var client = await _listener.AcceptTcpClientAsync();
                    Interlocked.Increment(ref _accepted);
                }
            }
            catch { /* stopped */ }
        }

        public void Dispose()
        {
            _listener.Stop();
            Plan.Dispose();
        }
    }
}

/// <summary>
/// A course folder with a planning folder made to test a guarded view: a
/// unit's page asking for everything a page can ask for, inside and outside,
/// and a page of links at fixed places to click.
/// </summary>
public sealed class PlanFixture : IDisposable
{
    public string Root { get; }
    public string CourseFolder { get; }
    public string PlanningFolder { get; }
    public string UnitPage => Folder("unit-1", "index.html");

    public PlanFixture(int port)
    {
        Root = Directory.CreateTempSubdirectory("plantoir-guard-").FullName;
        CourseFolder = Path.Combine(Root, "courses", "SNC2D");
        PlanningFolder = Path.Combine(CourseFolder, ".internal", "planning");
        string web = "https://127.0.0.1:" + port;

        Write(Path.Combine(CourseFolder, "course_config.json"), "{}");
        Write(Path.Combine(CourseFolder, "picture.png"), "outside");
        Write(Folder("index.html"), "<!doctype html><title>All Plans</title><p>plans</p>");
        Write(Folder("assets", "plan.css"),
            $"@import url('{web}/import.css');\n"
            + "@font-face { font-family: p; src: url('fonts/p.woff2') format('woff2'); }\n"
            + $"body {{ color: rgb(10, 20, 30); font-family: p; background: url('{web}/bg.png'); }}\n");
        Write(Folder("assets", "plan-red.css"), "body { color: rgb(200, 0, 0); }\n");
        Write(Folder("assets", "fonts", "p.woff2"), "wOF2");
        Write(Folder("unit-1", "pic.png"), "png");
        Write(Folder("unit-1", "notes.pdf"), MinimalPdf);
        Write(Folder("unit-1", "archive.zip"), "PK");
        Write(Folder("unit-2", "index.html"), "<!doctype html><title>Unit 2</title><p>two</p>");
        ReferenceFixtures.Junction(Folder("unit-1", "shortcut"), CourseFolder);
        ReferenceFixtures.Junction(Folder("unit-1", "shared"), Folder("assets"));

        Write(UnitPage, "<!doctype html><html><head><title>plan</title>"
            + "<link rel=stylesheet href='../assets/plan.css'>"
            + "<link rel=stylesheet href='shared/plan.css?through-junction'>"
            + $"<link rel=preconnect href='{web}/'><link rel=dns-prefetch href='{web}/'>"
            + $"<link rel=prefetch href='{web}/prefetch'><link rel=icon href='{web}/icon'>"
            + "<script>document.title='scripted'</script></head>"
            + "<body onload=\"document.title='onload'\">"
            + "<img src='pic.png?beside'><img src='../../../course_config.json?up'>"
            + "<img src='../../../picture.png?three-up'><img src='shortcut/picture.png?junction-out'>"
            + $"<img src='{web}/img'><img srcset='{web}/srcset 2x'><picture><source srcset='{web}/source'><img src='pic.png?picture'></picture>"
            + $"<video poster='{web}/poster'></video><object data='{web}/object'></object><embed src='{web}/embed'>"
            + "<iframe src='frame.html'></iframe>"
            + "<iframe srcdoc=\"<script>parent.document.title='srcdoc'</script>\"></iframe>"
            + "<svg><script>document.title='svg'</script></svg>"
            + "<a href=\"javascript:document.title='js'\">j</a>"
            + "</body></html>");
        Write(Folder("unit-1", "frame.html"), $"<img src='{web}/frameimg'><img src='pic.png?frame'>");
        Write(Folder("unit-1", "refresh.html"), $"<meta http-equiv=refresh content='0;url={web}/refresh'><title>r</title>");
        Write(Folder("unit-1", "refresh-up.html"), "<meta http-equiv=refresh content='0;url=../../../course_config.json'><title>r</title>");

        string Block(int top, string href, string extra = "") =>
            $"<a {extra} href='{href}' style='position:absolute;left:0;top:{top}px;width:300px;height:60px;display:block;background:#ccc'>x</a>";
        Write(Folder("unit-1", "clicks.html"), "<!doctype html><title>clicks</title><body style='margin:0'>"
            + Block(30, "https://example.invalid/web")
            + Block(130, "mailto:teacher@example.invalid")
            + Block(230, "../../../course_config.json")
            + Block(330, "../unit-2/index.html", "target=_blank")
            + Block(430, "notes.pdf")
            + Block(530, "archive.zip")
            + "</body>");
    }

    /// <summary>A path inside the planning folder.</summary>
    public string Folder(params string[] parts) => Path.Combine(new[] { PlanningFolder }.Concat(parts).ToArray());

    /// <summary>The served address of a path inside the planning folder, written with '/'.</summary>
    public string Address(string relative) =>
        new LocalSiteGuard(PlanningFolder, LocalSiteGuard.PlansHost, LocalSiteGuard.PlanContentTypes)
            .AddressOf(Path.Combine(PlanningFolder, relative.Replace('/', '\\')))!;

    /// <summary>A user-data folder for one run, inside this fixture so it goes with it.</summary>
    public string UserData(string name) => Path.Combine(Root, "webview-" + name);

    private static void Write(string path, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    /// <summary>The smallest PDF Chromium will take as one.</summary>
    private const string MinimalPdf =
        "%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
        + "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n";

    public void Dispose()
    {
        // Junctions first, so deleting the tree never walks into what they point at.
        foreach (string link in new[] { Folder("unit-1", "shortcut"), Folder("unit-1", "shared") })
            try { Directory.Delete(link); } catch { }
        for (int attempt = 0; attempt < 10; attempt++)
        {
            try { Directory.Delete(Root, recursive: true); return; }
            catch { Thread.Sleep(300); }   // the browser lets go of its user-data folder a moment after the probe exits
        }
    }
}

/// <summary>
/// Runs <c>Plantoir.GuardProbe.exe</c> (built beside this project by its
/// project reference) and splits what it printed by step.
/// </summary>
public static class GuardProbe
{
    /// <summary>What one run printed: every line, and each step's lines.</summary>
    public sealed class Output
    {
        public IReadOnlyList<string> All { get; }
        private readonly List<(string Step, List<string> Lines)> _steps = new();

        public Output(IReadOnlyList<string> lines)
        {
            All = lines;
            foreach (string line in lines)
            {
                if (line.StartsWith("STEP ", StringComparison.Ordinal))
                {
                    string rest = line[5..];
                    _steps.Add((rest[(rest.IndexOf(' ') + 1)..], new List<string>()));
                }
                else if (_steps.Count > 0) _steps[^1].Lines.Add(line);
            }
        }

        /// <summary>The lines of the FIRST step written exactly <paramref name="step"/>.</summary>
        public IReadOnlyList<string> Step(string step) =>
            _steps.First(s => s.Step == step).Lines;

        /// <summary>The lines of the step <paramref name="offset"/> after the first that starts with <paramref name="prefix"/>.</summary>
        public IReadOnlyList<string> StepAfter(string prefix, int offset = 0)
        {
            int at = _steps.FindIndex(s => s.Step.StartsWith(prefix, StringComparison.Ordinal));
            Assert.True(at >= 0, "no step starts with " + prefix);
            return _steps[at + offset].Lines;
        }
    }

    /// <summary>The probe, built by this project's reference to it.</summary>
    public static string Executable
    {
        get
        {
            // The configuration this test assembly was built in, so a stale
            // build of the other one is never the one measured (review L9).
            string configuration = AppContext.BaseDirectory.Contains(@"\Release\", StringComparison.OrdinalIgnoreCase) ? "Release" : "Debug";
            string bin = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.GuardProbe", "bin", configuration);
            var found = Directory.Exists(bin)
                ? Directory.EnumerateFiles(bin, "Plantoir.GuardProbe.exe", SearchOption.AllDirectories)
                    .OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault()
                : null;
            Assert.True(found is not null, "Plantoir.GuardProbe.exe was not built: Plantoir.Tests.csproj references it so the gate builds it.");
            return found!;
        }
    }

    /// <summary>Runs the probe over <paramref name="root"/> and returns what it printed; fails on a run that did not finish.</summary>
    public static Output Run(string root, string mode, string userData, IEnumerable<string> steps, string? host = null, bool hand = false,
                             string? csp = null)
    {
        var start = new ProcessStartInfo(Executable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (string arg in new[] { "--root", root, "--udf", userData, "--mode", mode }) start.ArgumentList.Add(arg);
        if (host is not null) { start.ArgumentList.Add("--host"); start.ArgumentList.Add(host); }
        if (hand) start.ArgumentList.Add("--hand");
        if (csp is not null) { start.ArgumentList.Add("--csp"); start.ArgumentList.Add(csp); }
        foreach (string step in steps) start.ArgumentList.Add(step);
        // The app's own preview folder must not be the probe's.
        start.Environment.Remove("WEBVIEW2_USER_DATA_FOLDER");

        using var process = Process.Start(start)!;
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(180_000))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            Assert.Fail("The guard probe did not finish in three minutes.");
        }
        var lines = stdout.Result.Split('\n').Select(line => line.TrimEnd('\r')).Where(line => line.Length > 0).ToList();
        Assert.True(lines.Contains("END") && lines.Contains("ATTACHED"),
            "The guard probe did not run to its end (exit " + process.ExitCode + "):\n" + string.Join("\n", lines) + "\n" + stderr.Result);
        Assert.DoesNotContain(lines, line => line.StartsWith("ERROR"));
        return new Output(lines);
    }
}
