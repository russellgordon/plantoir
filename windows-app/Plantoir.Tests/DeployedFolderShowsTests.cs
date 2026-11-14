using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;
using Xunit;
using static Plantoir.Tests.DeployedFolderFixtures;

namespace Plantoir.Tests;

/// <summary>
/// The registry of shows (#889, the mac's #850): <c>deployedFolderInBrowser.stopCases</c>
/// one test by name each where the Core decides it, the four ways opening
/// fails, the address remembered and moved, and the three trail sentences held
/// against <c>activityTrail.mustRecord</c>'s templates. Each test has its own
/// <see cref="DeployedFolderShows"/> and memory of ports, so nothing here
/// touches the app's settings or another test's shows.
/// </summary>
[Collection(DeployedFolderTimings.Name)]
public sealed class DeployedFolderShowsTests : IDisposable
{
    private readonly string _base = Path.Combine(Path.GetTempPath(), "plantoir-deployed-shows-" + Guid.NewGuid().ToString("N"));
    private readonly string _workingFolder;
    private readonly List<DeployedFolderHappening> _happened = [];
    private readonly DeployedFolderShows _shows;
    private readonly List<Uri> _browser = [];

    public DeployedFolderShowsTests()
    {
        _workingFolder = Path.Combine(_base, "wf");
        Directory.CreateDirectory(_workingFolder);
        _shows = new DeployedFolderShows(new InMemoryDeployedFolderPorts());
        _shows.Happened += h => { lock (_happened) _happened.Add(h); };
    }

    public void Dispose()
    {
        _shows.StopEverything();
        ReferenceFixtures.Remove(_base);
    }

    private string Deployed(string name = "Sites")
    {
        string section = Path.Combine(_base, name, "section1");
        Directory.CreateDirectory(section);
        File.WriteAllText(Path.Combine(section, "index.html"), "home");
        return section;
    }

    private bool Browser(Uri address)
    {
        lock (_browser) _browser.Add(address);
        return true;
    }

    private Task<DeployedFolderShows.OpenOutcome> Open(string folder, DeployedFolderFrom from = DeployedFolderFrom.Toolbar) =>
        _shows.OpenAsync(folder, "ICS3U", 1, _workingFolder, from, Browser);

    private List<DeployedFolderHappening> Happened()
    {
        lock (_happened) return [.. _happened];
    }

    private static string Fetch(Uri address)
    {
        var response = Exchange(address.Port, Encoding.ASCII.GetBytes($"GET / HTTP/1.1\r\nHost: 127.0.0.1:{address.Port}\r\nConnection: close\r\n\r\n"), false, TimeSpan.Zero);
        return response.BodyText;
    }

    private static bool Refused(int port)
    {
        using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        try { socket.Connect(IPAddress.Loopback, port); return false; }
        catch (SocketException e) { return e.SocketErrorCode == SocketError.ConnectionRefused; }
    }

    /// <summary>Makes the walk wait at a gate, so a test can act while a show is still starting.</summary>
    private (ManualResetEventSlim Entered, ManualResetEventSlim Release, int Port) HoldTheStart()
    {
        var entered = new ManualResetEventSlim();
        var release = new ManualResetEventSlim();
        int port = FreePort();
        _shows.CandidatesForTests = canonical =>
        {
            entered.Set();
            release.Wait(TimeSpan.FromSeconds(20));
            return [port];
        };
        return (entered, release, port);
    }

    // ---- Opening ---------------------------------------------------------------------

    [Fact]
    public async Task OpenServesTheFolderAndSaysWhereItWasPressed()
    {
        var outcome = await Open(Deployed(), DeployedFolderFrom.Result);
        Assert.NotNull(outcome.Address);
        Assert.Null(outcome.Why);
        Assert.Equal([outcome.Address!], _browser);
        Assert.Equal("http", outcome.Address!.Scheme);
        Assert.Equal("127.0.0.1", outcome.Address.Host);
        Assert.True(DeployedFolderAddress.IsInTheBlock(outcome.Address.Port));
        Assert.Equal("home", Fetch(outcome.Address));
        var show = _shows.ShowFor("ICS3U", 1, _workingFolder);
        Assert.Equal(outcome.Address, show!.Address);
        Assert.Equal(1, _shows.Count);
        var opened = Assert.IsType<DeployedFolderHappening.Opened>(Assert.Single(Happened()));
        Assert.Equal(DeployedFolderFrom.Result, opened.From);
        Assert.False(opened.AlreadyOpen);
        Assert.Equal("ICS3U", opened.CourseCode);
        Assert.Equal(1, opened.SectionNumber);
    }

    /// <summary><c>stopCases</c>: "Open in Browser is pressed again while it runs".</summary>
    [Fact]
    public async Task OpenAgainWhileItRunsOpensTheSameAddressAndStartsNothing()
    {
        string folder = Deployed();
        var first = await Open(folder);
        var again = await Open(folder, DeployedFolderFrom.SectionMenu);
        Assert.Equal(first.Address, again.Address);
        Assert.Equal(1, _shows.Count);
        var second = Assert.IsType<DeployedFolderHappening.Opened>(Happened()[1]);
        Assert.True(second.AlreadyOpen);
        Assert.Contains(", already open)", second.TrailLine);
    }

    /// <summary><c>stopCases</c>: "two presses of Open in Browser before the first has started showing".</summary>
    [Fact]
    public async Task TwoQuickPressesStartOneShowAndStopEndsIt()
    {
        string folder = Deployed();
        var (entered, release, port) = HoldTheStart();
        var first = Open(folder);
        Assert.True(entered.Wait(TimeSpan.FromSeconds(10)));
        var second = Open(folder, DeployedFolderFrom.Sidebar);
        release.Set();
        var outcomes = await Task.WhenAll(first, second);
        Assert.NotNull(outcomes[0].Address);
        Assert.Equal(outcomes[0].Address, outcomes[1].Address);
        Assert.Equal(1, _shows.Count);
        Assert.Equal(2, _browser.Count);

        _shows.Stop("ICS3U", 1, _workingFolder);
        Assert.Equal(0, _shows.Count);
        Assert.True(Refused(outcomes[0].Address!.Port));
    }

    /// <summary><c>stopCases</c>: "Stop is pressed while the show is still starting".</summary>
    [Fact]
    public async Task StopWhileStartingEndsItOnceStartedAndLeavesNothingListening()
    {
        var (entered, release, port) = HoldTheStart();
        var opening = Open(Deployed());
        Assert.True(entered.Wait(TimeSpan.FromSeconds(10)));
        _shows.Stop("ICS3U", 1, _workingFolder);
        release.Set();
        var outcome = await opening;
        Assert.Null(outcome.Address);
        Assert.Null(outcome.Why);
        Assert.Empty(_browser);
        Assert.Equal(0, _shows.Count);
        var stopped = Assert.IsType<DeployedFolderHappening.Stopped>(Happened().Last());
        Assert.Equal(DeployedFolderStopReason.StopPressed, stopped.Reason);
        Assert.IsType<DeployedFolderHappening.Opened>(Happened().First());
        Assert.True(Refused(port));
    }

    /// <summary><c>stopCases</c>: "Stop is pressed, in the notice or the Section menu".</summary>
    [Fact]
    public async Task StopEndsTheShowFreesTheAddressAndCountsTheRequests()
    {
        var outcome = await Open(Deployed());
        Fetch(outcome.Address!);
        Exchange(outcome.Address!.Port, Encoding.ASCII.GetBytes($"GET /missing HTTP/1.1\r\nHost: 127.0.0.1:{outcome.Address.Port}\r\nConnection: close\r\n\r\n"), false, TimeSpan.Zero);
        _shows.Stop("ICS3U", 1, _workingFolder);
        Assert.Null(_shows.ShowFor("ICS3U", 1, _workingFolder));
        Assert.True(Refused(outcome.Address.Port));
        var stopped = Assert.IsType<DeployedFolderHappening.Stopped>(Happened().Last());
        Assert.Equal(DeployedFolderStopReason.StopPressed, stopped.Reason);
        Assert.Equal(2, stopped.Requests);
        Assert.Equal(1, stopped.Missing);
        Assert.Equal("stopped showing the deployed folder in the web browser — Stop was pressed (2 requests, 1 not found)", stopped.TrailLine);
    }

    /// <summary><c>stopCases</c>: "Stop on a section with two shows, one started before its deploy folder was changed".</summary>
    [Fact]
    public async Task StopOnASectionEndsEveryShowOfIt()
    {
        var before = await Open(Deployed("Old Sites"));
        var after = await Open(Deployed("New Sites"));
        Assert.NotEqual(before.Address, after.Address);
        Assert.Equal(2, _shows.Count);
        _shows.Stop("ICS3U", 1, _workingFolder);
        Assert.Equal(0, _shows.Count);
        Assert.True(Refused(before.Address!.Port));
        Assert.True(Refused(after.Address!.Port));
    }

    /// <summary><c>stopCases</c>: "Plantoir quits" (the trail says Plantoir quit; quit never asks).</summary>
    [Fact]
    public async Task QuittingStopsEveryShowAtOnce()
    {
        var one = await Open(Deployed("A"));
        var two = await _shows.OpenAsync(Deployed("B"), "MCR3U", 2, _workingFolder, DeployedFolderFrom.Toolbar, Browser);
        _shows.StopEverything();
        Assert.Equal(0, _shows.Count);
        Assert.True(Refused(one.Address!.Port));
        Assert.True(Refused(two.Address!.Port));
        var stops = Happened().OfType<DeployedFolderHappening.Stopped>().ToList();
        Assert.Equal(2, stops.Count);
        Assert.All(stops, s => Assert.Equal(DeployedFolderStopReason.PlantoirQuit, s.Reason));
    }

    /// <summary><c>stopCases</c>: "the listener ends without being asked".</summary>
    [Fact]
    public async Task AListenerThatEndsOnItsOwnDropsTheShow()
    {
        var outcome = await Open(Deployed());
        var running = (System.Collections.IList)typeof(DeployedFolderShows).GetField("_running", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(_shows)!;
        var server = (DeployedFolderServer)running[0]!.GetType().GetProperty("Server")!.GetValue(running[0])!;
        var listener = (TcpListener)typeof(DeployedFolderServer).GetField("_listener", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(server)!;
        listener.Stop();
        DeployedFolderServerTests.WaitFor(() => _shows.Count == 0, TimeSpan.FromSeconds(5));
        Assert.Equal(0, _shows.Count);
        var stopped = Assert.IsType<DeployedFolderHappening.Stopped>(Happened().Last());
        Assert.Equal(DeployedFolderStopReason.EndedOnItsOwn, stopped.Reason);
        Assert.True(Refused(outcome.Address!.Port));
    }

    /// <summary><c>stopCases</c>: "a request finds the folder gone" (the window says stoppedFolderGone until dismissed).</summary>
    [Fact]
    public async Task ARequestThatFindsTheFolderGoneStopsItUntilDismissed()
    {
        string folder = Deployed();
        var outcome = await Open(folder);
        int changed = 0;
        _shows.Changed += () => Interlocked.Increment(ref changed);
        Directory.Delete(folder, recursive: true);
        Fetch(outcome.Address!);
        DeployedFolderServerTests.WaitFor(() => _shows.Count == 0, TimeSpan.FromSeconds(5));
        Assert.Equal(0, _shows.Count);
        Assert.True(_shows.FolderWentAway("ICS3U", 1, _workingFolder));
        Assert.Equal(DeployedFolderStopReason.FolderGone, Assert.IsType<DeployedFolderHappening.Stopped>(Happened().Last()).Reason);
        _shows.DismissFolderWentAway("ICS3U", 1, _workingFolder);
        Assert.False(_shows.FolderWentAway("ICS3U", 1, _workingFolder));
        Assert.True(changed >= 2);
    }

    /// <summary><c>stopCases</c>: "a deploy to the same folder": NOT stopped, the next reload shows the new site.</summary>
    [Fact]
    public async Task ADeployToTheSameFolderDoesNotStopIt()
    {
        string folder = Deployed();
        var outcome = await Open(folder);
        // A deploy replaces the section's files (robocopy /MIR keeps the folder).
        File.WriteAllText(Path.Combine(folder, "index.html"), "deployed again");
        Assert.Equal("deployed again", Fetch(outcome.Address!));
        Assert.Equal(1, _shows.Count);
    }

    // ---- The same address each time ---------------------------------------------------

    [Fact]
    public async Task TheSameFolderGetsTheSameAddressAfterStop()
    {
        string folder = Deployed();
        var first = await Open(folder);
        _shows.Stop("ICS3U", 1, _workingFolder);
        var again = await Open(folder);
        Assert.Equal(first.Address, again.Address);
        Assert.False(Assert.IsType<DeployedFolderHappening.Opened>(Happened().Last()).AddressMoved);
    }

    [Fact]
    public async Task AnAddressAnotherProgramHoldsMovesAndTheTrailSaysSo()
    {
        var other = new TcpListener(IPAddress.Loopback, 0);
        other.Start();
        try
        {
            int held = ((IPEndPoint)other.LocalEndpoint).Port;
            int free = FreePort();
            _shows.CandidatesForTests = _ => [held, free];
            var outcome = await Open(Deployed());
            Assert.Equal(free, outcome.Address!.Port);
            var opened = Assert.IsType<DeployedFolderHappening.Opened>(Happened().Last());
            Assert.True(opened.AddressMoved);
            Assert.Contains("at a different address because its usual one was taken", opened.TrailLine);
        }
        finally { other.Stop(); }
    }

    [Fact]
    public async Task ASecondCopyOfPlantoirShowsTheSameFolderAtTheNextAddress()
    {
        string folder = Deployed();
        var first = await Open(folder);
        // Another copy of the app: its own registry, the same folder, the same
        // ports remembered nowhere: the walk finds the first copy's port held.
        var secondCopy = new DeployedFolderShows(new InMemoryDeployedFolderPorts());
        var moved = new List<DeployedFolderHappening>();
        secondCopy.Happened += moved.Add;
        try
        {
            var outcome = await secondCopy.OpenAsync(folder, "ICS3U", 1, _workingFolder, DeployedFolderFrom.Toolbar, _ => true);
            Assert.NotEqual(first.Address, outcome.Address);
            Assert.True(Assert.IsType<DeployedFolderHappening.Opened>(moved.Last()).AddressMoved);
            Assert.Equal("home", Fetch(outcome.Address!));
        }
        finally { secondCopy.StopEverything(); }
    }

    // ---- Why it could not open ----------------------------------------------------------

    [Fact]
    public async Task EveryWayOpeningFailsIsSaid()
    {
        var missing = await Open(Path.Combine(_base, "Nowhere", "section1"));
        Assert.Equal(DeployedFolderCouldNotOpen.FolderNotFound, missing.Why);

        string empty = Path.Combine(_base, "Empty", "section1");
        Directory.CreateDirectory(empty);
        Assert.Equal(DeployedFolderCouldNotOpen.NothingDeployed, (await Open(empty)).Why);

        var other = new TcpListener(IPAddress.Loopback, 0);
        other.Start();
        try
        {
            _shows.CandidatesForTests = _ => [((IPEndPoint)other.LocalEndpoint).Port];
            Assert.Equal(DeployedFolderCouldNotOpen.NoFreeAddress, (await Open(Deployed("Full"))).Why);
        }
        finally { other.Stop(); _shows.CandidatesForTests = null; }

        var refusedByTheBrowser = await _shows.OpenAsync(Deployed("Browser"), "ICS3U", 1, _workingFolder, DeployedFolderFrom.Toolbar, _ => false);
        Assert.Equal(DeployedFolderCouldNotOpen.BrowserDidNotOpen, refusedByTheBrowser.Why);

        var reasons = Happened().OfType<DeployedFolderHappening.CouldNotOpen>().Select(c => c.Why).ToList();
        Assert.Equal([DeployedFolderCouldNotOpen.FolderNotFound, DeployedFolderCouldNotOpen.NothingDeployed,
                      DeployedFolderCouldNotOpen.NoFreeAddress, DeployedFolderCouldNotOpen.BrowserDidNotOpen], reasons);
    }

    // ---- The trail's sentences ------------------------------------------------------------

    private static string Template(string eventName) =>
        ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(e => e!["event"]!.ToString() == eventName)!["line"]!.ToString();

    /// <summary>Every sentence a template allows: <c>[a | b]</c> is one of them or nothing, <c>{a | b}</c> one of them, <c>{name}</c> a value given.</summary>
    private static List<string> Expand(string template, Dictionary<string, string[]> values)
    {
        var results = new List<string> { "" };
        foreach (Match part in Regex.Matches(template, @"\[([^\]]*)\]|\{([^}]*)\}|[^\[{]+"))
        {
            string[] choices;
            if (part.Groups[1].Success) choices = [.. part.Groups[1].Value.Split(" | "), ""];
            else if (part.Groups[2].Success)
                choices = part.Groups[2].Value.Contains(" | ") ? part.Groups[2].Value.Split(" | ") : values[part.Groups[2].Value];
            else choices = [part.Value];
            results = results.SelectMany(r => choices.Select(c => r + c)).ToList();
        }
        return results;
    }

    [Fact]
    public void TheTrailSentencesAreTheContractsTemplates()
    {
        var froms = Enum.GetValues<DeployedFolderFrom>().Select(DeployedFolderTrail.FromWords).ToArray();
        var opened = Expand(Template("deployed folder opened in the web browser"), new() { ["from"] = froms });
        foreach (var from in Enum.GetValues<DeployedFolderFrom>())
            foreach (bool already in new[] { false, true })
                foreach (bool moved in new[] { false, true })
                    Assert.Contains(DeployedFolderTrail.OpenedLine(from, already, moved), opened);

        var stopped = Expand(Template("deployed folder no longer shown"), new() { ["requests"] = ["7"], ["missing"] = ["2"] });
        foreach (var reason in Enum.GetValues<DeployedFolderStopReason>())
            Assert.Contains(DeployedFolderTrail.StoppedLine(reason, 7, 2), stopped);

        var couldNot = Expand(Template("deployed folder could not be opened"), []);
        foreach (var why in Enum.GetValues<DeployedFolderCouldNotOpen>())
            Assert.Contains(DeployedFolderTrail.CouldNotOpenLine(why), couldNot);

        // Where it was pressed: the four places the contract names, never a path or an address.
        string carries = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(e => e!["event"]!.ToString() == "deployed folder opened in the web browser")!["carries"]!.ToString();
        foreach (string place in new[] { "the deploy's result", "the Section menu", "the toolbar", "the sidebar" })
        {
            Assert.Contains(place, carries);
            Assert.Contains("from " + place, froms);
        }
        Assert.Equal(4, Enum.GetValues<DeployedFolderStopReason>().Length);
        Assert.Equal(4, Enum.GetValues<DeployedFolderCouldNotOpen>().Length);
    }
}
