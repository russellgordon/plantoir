using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;
using static Plantoir.Tests.DeployedFolderFixtures;

namespace Plantoir.Tests;

/// <summary>
/// The deployed folder's listener over a real socket (#889, the mac's #850):
/// <c>deployedFolderInBrowser.limits</c> and every <c>connectionCases</c> entry
/// but the slow one (<see cref="DeployedFolderReadersTests"/>), walked from the
/// JSON; where it listens; and that it stops and frees its port.
/// </summary>
public sealed class DeployedFolderServerTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-deployed-server-" + Guid.NewGuid().ToString("N"));

    public DeployedFolderServerTests()
    {
        Directory.CreateDirectory(_root);
        File.WriteAllText(Path.Combine(_root, "index.html"), "home");
    }

    public void Dispose() => ReferenceFixtures.Remove(_root);

    private DeployedFolderServer Start(Action? onFolderGone = null, Action? onEnded = null) =>
        DeployedFolderServer.Start(_root, [FreePort()], onFolderGone, onEnded).Server
        ?? throw new InvalidOperationException("the server did not start");

    private static JsonObject Expect(string kind) =>
        Block["connectionCases"]!.AsArray().Single(c => c!["kind"]!.ToString() == kind)!["expect"]!.AsObject();

    private static byte[] Get(string target, int port, string extraHeaders = "") =>
        Encoding.ASCII.GetBytes($"GET {target} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n{extraHeaders}\r\n");

    [Fact]
    public void TheLimitsAreTheContracts()
    {
        var limits = Block["limits"]!;
        Assert.Equal((int)limits["maximumConnections"]!, DeployedFolderServer.MaximumConnections);
        Assert.Equal((int)limits["maximumRequestLineBytes"]!, DeployedFolderServer.MaximumRequestLineBytes);
        Assert.Equal((int)limits["maximumHeaderBytes"]!, DeployedFolderServer.MaximumHeaderBytes);
        Assert.Equal((int)limits["secondsToSendTheHeaders"]!, DeployedFolderServer.SecondsToSendTheHeaders);
        Assert.Equal((int)limits["secondsIdleBetweenRequests"]!, DeployedFolderServer.SecondsIdleBetweenRequests);
        Assert.Equal((int)limits["secondsToTakeAPiece"]!, DeployedFolderServer.SecondsToTakeAPiece);
    }

    [Fact]
    public void EveryConnectionCaseIsTested()
    {
        var tested = new[]
        {
            "requestLineTooLong", "headersTooLarge", "headersNotSentInTime", "aConnectionPastTheMaximumMakesRoom",
            "readersThatStopReading", "twoRequestsOnOneConnection", "theNetworkAddressIsRefused",
        };
        Assert.Equal(tested.Order(), Block["connectionCases"]!.AsArray().Select(c => c!["kind"]!.ToString()).Order());
    }

    [Fact]
    public void ARequestLineTooLong()
    {
        using var server = Start();
        var expect = Expect("requestLineTooLong");
        var response = Exchange(server.Port, Get("/" + new string('a', DeployedFolderServer.MaximumRequestLineBytes + 100), server.Port), false);
        Assert.Equal((int)expect["status"]!, response.Status);
        Assert.Equal((bool)expect["closes"]!, response.Closed);
    }

    [Fact]
    public void HeadersTooLarge()
    {
        using var server = Start();
        var expect = Expect("headersTooLarge");
        string big = "X-Big: " + new string('b', DeployedFolderServer.MaximumHeaderBytes + 100) + "\r\n";
        var response = Exchange(server.Port, Get("/", server.Port, big), false);
        Assert.Equal((int)expect["status"]!, response.Status);
        Assert.Equal((bool)expect["closes"]!, response.Closed);
    }

    [Fact]
    public void HeadersNotSentInTime()
    {
        using var server = Start();
        int within = (int)Expect("headersNotSentInTime")["closedWithin"]!;
        using var socket = Connect(server.Port);
        socket.Send(Encoding.ASCII.GetBytes("GET / HTTP/1.1\r\n"));
        var clock = Stopwatch.StartNew();
        Assert.True(ClosesWithin(socket, TimeSpan.FromSeconds(within)), "a connection that never finished its headers stayed open");
        // Closed BY the deadline, not at once.
        Assert.InRange(clock.Elapsed.TotalSeconds, DeployedFolderServer.SecondsToSendTheHeaders - 1, within);
    }

    [Fact]
    public void AConnectionPastTheMaximumMakesRoom()
    {
        using var server = Start();
        var expect = Expect("aConnectionPastTheMaximumMakesRoom");
        var silent = new List<Socket>();
        try
        {
            for (int i = 0; i < DeployedFolderServer.MaximumConnections; i++)
            {
                silent.Add(Connect(server.Port));
                Thread.Sleep(5);
            }
            WaitFor(() => server.OpenConnections == DeployedFolderServer.MaximumConnections, TimeSpan.FromSeconds(5));
            Assert.Equal(DeployedFolderServer.MaximumConnections, server.OpenConnections);

            var response = Exchange(server.Port, Get("/", server.Port, "Connection: close\r\n"), false, TimeSpan.Zero);
            Assert.Equal((bool)expect["newcomerAnswered"]!, response.Status == 200 && response.BodyText == "home");

            // The quietest - the first to arrive - is the one closed.
            Assert.Equal((bool)expect["oneQuietConnectionClosed"]!, ClosesWithin(silent[0], TimeSpan.FromSeconds(2)));
            int stillOpen = silent.Skip(1).Count(s => !ClosesWithin(s, TimeSpan.FromMilliseconds(20)));
            Assert.Equal(DeployedFolderServer.MaximumConnections - 1, stillOpen);
        }
        finally
        {
            foreach (var socket in silent) socket.Dispose();
        }
    }

    [Fact]
    public void TwoRequestsOnOneConnection()
    {
        using var server = Start();
        var expect = Expect("twoRequestsOnOneConnection");
        using var socket = Connect(server.Port);
        socket.Send([.. Get("/", server.Port), .. Get("/index.html", server.Port)]);
        var reader = new WireReader(socket);
        var first = reader.ReadResponse(false, TimeSpan.Zero);
        var second = reader.ReadResponse(false, TimeSpan.Zero);
        Assert.Equal((bool)expect["bothAnswered"]!, first.Status == 200 && second.Status == 200 && second.BodyText == "home");
    }

    [NetworkAddressFact]
    public void TheNetworkAddressIsRefused()
    {
        using var server = Start();
        var expect = Expect("theNetworkAddressIsRefused");
        var address = NetworkAddressFactAttribute.FirstNetworkAddress()!;
        using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        var refused = Assert.Throws<SocketException>(() => socket.Connect(address, server.Port));
        Assert.Equal((bool)expect["refused"]!, refused.SocketErrorCode == SocketError.ConnectionRefused);
    }

    [Fact]
    public void ItListensOnTheLoopbackAddressAloneAndExclusively()
    {
        using var server = Start();
        var listeners = IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners().Where(e => e.Port == server.Port).ToList();
        Assert.Equal([IPAddress.Loopback], listeners.Select(e => e.Address));
        // ExclusiveAddressUse: nobody can bind the same address beside it, even asking to share.
        using var second = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        second.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        Assert.Throws<SocketException>(() => second.Bind(new IPEndPoint(IPAddress.Loopback, server.Port)));
    }

    [Fact]
    public void APortAnotherProgramHoldsOnEveryAddressIsPassedOver()
    {
        // Measured on this PC: Windows lets a bind to 127.0.0.1 succeed over
        // another program's 0.0.0.0, and would take its loopback connections.
        // The other program is STOOD IN through the listener table, never
        // bound: a real 0.0.0.0 listener raises the firewall's prompt.
        int held = FreePort();
        int free = FreePort();
        var real = DeployedFolderServer.ActiveListeners;
        DeployedFolderServer.ActiveListeners = () => real().Append(new IPEndPoint(IPAddress.Any, held));
        try
        {
            Assert.True(DeployedFolderServer.IsHeldByAnotherListener(held));
            var started = DeployedFolderServer.Start(_root, [held, free]);
            using var server = started.Server!;
            Assert.Equal(free, server.Port);
            Assert.True(started.FirstWasTaken);
        }
        finally { DeployedFolderServer.ActiveListeners = real; }
    }

    [Fact]
    public void APortHeldOnTheLoopbackAddressIsPassedOver()
    {
        using var first = Start();
        int free = FreePort();
        var started = DeployedFolderServer.Start(_root, [first.Port, free]);
        using var second = started.Server!;
        Assert.Equal(free, second.Port);
        Assert.True(started.FirstWasTaken);
    }

    [Fact]
    public void EveryCandidateHeldStartsNothing()
    {
        using var first = Start();
        var started = DeployedFolderServer.Start(_root, [first.Port]);
        Assert.Null(started.Server);
        Assert.True(started.FirstWasTaken);
    }

    [Fact]
    public void StopFreesThePortAndTheSameAddressComesBack()
    {
        var server = Start();
        int port = server.Port;
        // A request the server closes first leaves TIME_WAIT on its side, which
        // must not keep the address from coming back (measured: it does not).
        Assert.Equal(200, Exchange(port, Get("/", port, "Connection: close\r\n"), false).Status);
        server.Stop();
        Assert.True(server.IsStopped);
        using (var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp))
            Assert.Equal(SocketError.ConnectionRefused, Assert.Throws<SocketException>(() => socket.Connect(IPAddress.Loopback, port)).SocketErrorCode);
        using var again = DeployedFolderServer.Start(_root, [port]).Server;
        Assert.NotNull(again);
        Assert.Equal(port, again!.Port);
    }

    [Fact]
    public void StopClosesEveryOpenConnection()
    {
        var server = Start();
        using var socket = Connect(server.Port);
        WaitFor(() => server.OpenConnections == 1, TimeSpan.FromSeconds(5));
        server.Stop();
        Assert.True(ClosesWithin(socket, TimeSpan.FromSeconds(2)));
        Assert.Equal(0, server.OpenConnections);
    }

    [Fact]
    public void AListenerThatEndsOnItsOwnSaysSo()
    {
        int ended = 0;
        using var server = Start(onEnded: () => Interlocked.Increment(ref ended));
        // What the system ending the listener looks like from inside: its
        // socket goes, without Stop being called.
        var listener = (TcpListener)typeof(DeployedFolderServer).GetField("_listener", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(server)!;
        listener.Stop();
        WaitFor(() => Volatile.Read(ref ended) == 1, TimeSpan.FromSeconds(5));
        Assert.Equal(1, ended);
        Assert.True(server.IsStopped);
    }

    [Fact]
    public void ARequestThatFindsTheFolderGoneSaysSoOnce()
    {
        int gone = 0;
        using var server = Start(onFolderGone: () => Interlocked.Increment(ref gone));
        Assert.Equal(200, Exchange(server.Port, Get("/", server.Port), false, TimeSpan.Zero).Status);
        Assert.Equal(0, gone);
        Directory.Delete(_root, recursive: true);
        Assert.Equal(404, Exchange(server.Port, Get("/", server.Port), false, TimeSpan.Zero).Status);
        Assert.Equal(404, Exchange(server.Port, Get("/", server.Port), false, TimeSpan.Zero).Status);
        WaitFor(() => Volatile.Read(ref gone) == 1, TimeSpan.FromSeconds(5));
        Thread.Sleep(200);
        Assert.Equal(1, gone);
        Assert.Equal(3, server.Requests);
        Assert.Equal(2, server.NotFound);
    }

    [Fact]
    public void ADeployToTheSameFolderShowsOnTheNextRequest()
    {
        using var server = Start();
        Assert.Equal("home", Exchange(server.Port, Get("/", server.Port), false, TimeSpan.Zero).BodyText);
        File.WriteAllText(Path.Combine(_root, "index.html"), "deployed again");
        Assert.Equal("deployed again", Exchange(server.Port, Get("/", server.Port), false, TimeSpan.Zero).BodyText);
    }

    [Fact]
    public void ARepeatWithItsTagIsNotModified()
    {
        using var server = Start();
        var first = Exchange(server.Port, Get("/", server.Port), false, TimeSpan.Zero);
        string tag = first.Value("ETag")!;
        var again = Exchange(server.Port, Get("/", server.Port, "If-None-Match: " + tag + "\r\n"), false, TimeSpan.Zero);
        Assert.Equal(304, again.Status);
        Assert.Empty(again.Body);
    }

    [Fact]
    public void AnEightDotThreeShortNameFindsNothing()
    {
        string folder = Path.Combine(_root, "Long Folder Name");
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "index.html"), "x");
        string? shortName = ShortNameOf(folder);
        if (shortName is null || string.Equals(shortName, "Long Folder Name", StringComparison.Ordinal)) return; // 8.3 names off on this volume.
        using var server = Start();
        Assert.Equal(200, Exchange(server.Port, Get("/Long%20Folder%20Name/", server.Port), false, TimeSpan.Zero).Status);
        Assert.Equal(404, Exchange(server.Port, Get("/" + shortName + "/", server.Port), false, TimeSpan.Zero).Status);
    }

    private static string? ShortNameOf(string path)
    {
        var buffer = new StringBuilder(1024);
        return GetShortPathNameW(path, buffer, buffer.Capacity) == 0 ? null : Path.GetFileName(buffer.ToString());
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int GetShortPathNameW(string longPath, StringBuilder shortPath, int length);

    internal static void WaitFor(Func<bool> condition, TimeSpan limit)
    {
        var clock = Stopwatch.StartNew();
        while (!condition() && clock.Elapsed < limit) Thread.Sleep(20);
    }
}

/// <summary>A fact that needs this PC to have a network address other than loopback: skipped, saying so, when it has none.</summary>
public sealed class NetworkAddressFactAttribute : FactAttribute
{
    public NetworkAddressFactAttribute()
    {
        if (FirstNetworkAddress() is null)
            Skip = "This PC has no IPv4 address but loopback, so 'theNetworkAddressIsRefused' cannot be tried.";
    }

    public static IPAddress? FirstNetworkAddress()
    {
        foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.OperationalStatus != OperationalStatus.Up || adapter.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var unicast in adapter.GetIPProperties().UnicastAddresses)
                if (unicast.Address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(unicast.Address))
                    return unicast.Address;
        }
        return null;
    }
}

/// <summary>
/// <c>connectionCases</c> → <c>readersThatStopReading</c> (the mac's
/// implementation review M2), alone in its class because it takes about 30 s:
/// 64 readers ask for a 200 MB file and never read; a normal request is still
/// answered, and a stalled reader is closed once a piece has gone untaken for
/// <c>secondsToTakeAPiece</c>. 200 MB because Windows' loopback can take several
/// MB per connection into its buffers before a send blocks.
/// </summary>
public sealed class DeployedFolderReadersTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-deployed-readers-" + Guid.NewGuid().ToString("N"));

    public void Dispose() => ReferenceFixtures.Remove(_root);

    [Fact]
    public void ReadersThatStopReadingDoNotShutTheSiteOut()
    {
        Directory.CreateDirectory(_root);
        File.WriteAllText(Path.Combine(_root, "index.html"), "home");
        using (var big = File.Create(Path.Combine(_root, "big.mp4"))) big.SetLength(200L * 1024 * 1024);
        var expect = Block["connectionCases"]!.AsArray().Single(c => c!["kind"]!.ToString() == "readersThatStopReading")!["expect"]!;
        int within = (int)expect["aStalledReaderClosedWithin"]!;

        using var server = DeployedFolderServer.Start(_root, [FreePort()]).Server!;
        var readers = new List<Socket>();
        try
        {
            var clock = Stopwatch.StartNew();
            for (int i = 0; i < DeployedFolderServer.MaximumConnections; i++)
            {
                var reader = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp) { ReceiveBufferSize = 4096 };
                reader.Connect(IPAddress.Loopback, server.Port);
                reader.Send(Encoding.ASCII.GetBytes($"GET /big.mp4 HTTP/1.1\r\nHost: 127.0.0.1:{server.Port}\r\n\r\n"));
                readers.Add(reader);
            }
            DeployedFolderServerTests.WaitFor(() => server.OpenConnections == DeployedFolderServer.MaximumConnections, TimeSpan.FromSeconds(5));
            Thread.Sleep(2000);

            var normal = Exchange(server.Port, Encoding.ASCII.GetBytes($"GET / HTTP/1.1\r\nHost: 127.0.0.1:{server.Port}\r\nConnection: close\r\n\r\n"), false, TimeSpan.Zero);
            Assert.Equal((bool)expect["aNormalRequestAnswered"]!, normal.Status == 200 && normal.BodyText == "home");

            // Every stalled reader goes once its piece has sat untaken past the deadline.
            DeployedFolderServerTests.WaitFor(() => server.OpenConnections == 0, TimeSpan.FromSeconds(within + 5));
            double seconds = clock.Elapsed.TotalSeconds;
            Assert.True(server.OpenConnections == 0, $"{server.OpenConnections} stalled readers still open after {seconds:F1} s");
            Assert.InRange(seconds, DeployedFolderServer.SecondsToTakeAPiece - 1, within);
        }
        finally
        {
            foreach (var reader in readers) reader.Dispose();
        }
    }
}
