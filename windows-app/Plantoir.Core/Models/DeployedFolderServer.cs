using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Plantoir.Core.Models;

/// <summary>
/// Answers a web browser from a section's deployed folder on this PC (#889, the
/// mac's #850), so the site's links and features work as they do from a web
/// host: Quartz writes every page link without <c>.html</c>, and opened straight
/// from the folder 0 of 3,369 page links worked.
/// </summary>
/// <remarks>
/// <para><b>A <see cref="TcpListener"/> of the app's own, with its own small
/// HTTP/1.1 reader</b> (the plan's D5, upheld by its review): what the mac built
/// with <c>NWListener</c>. Rejected: <c>HttpListener</c>, which is HTTP.sys and
/// answers some requests ITSELF before the app sees them (measured by the
/// planner on this PC: 403 for <c>/../x</c> where the contract allows 400 or
/// 404; 400 rather than 414 and 431 at the contract's sizes, its limits being
/// machine-wide registry values; no connection the app can close to make room),
/// so four contract cases could not be met; Kestrel (a framework reference of
/// several MB, and its connection cap refuses the newcomer, which the contract
/// forbids); a Python server (a second process, and it answers 404 for every
/// page link).</para>
///
/// <para><b>Bound to 127.0.0.1 and nothing else</b>, as previews have been
/// since #684, with <see cref="TcpListener.ExclusiveAddressUse"/> set before it
/// starts, so no other program can bind the same port with
/// <c>SO_REUSEADDR</c> and take its connections. Another computer cannot reach
/// it. Another ACCOUNT on this PC can, while it runs, as it can a preview: the
/// limit Russell accepted for the mac on 2026-11-13, and it applies here
/// unchanged (<c>documentation/12-windows-app.md</c>).</para>
///
/// <para><b>Limits</b> (<c>deployedFolderInBrowser.limits</c>, pinned against the
/// contract by the tests): 64 connections, and when every place is taken the
/// connection quiet longest is reset to make room, so the teacher's own browser
/// always gets in; a request line over 8 KiB is 414, headers over 16 KiB 431;
/// 10 s to send the headers, 30 s idle between requests; a piece of an answer
/// left untaken for 30 s resets its connection.</para>
///
/// <para><b>Lifetime.</b> <see cref="Stop"/> closes the listener and every
/// connection and frees the port. Nothing is written to disk, so a process that
/// is killed leaves nothing behind: Windows closes its sockets with it.</para>
/// </remarks>
public sealed class DeployedFolderServer : IDisposable
{
    public const int MaximumConnections = 64;
    public const int MaximumRequestLineBytes = 8 * 1024;
    public const int MaximumHeaderBytes = 16 * 1024;
    public const int SecondsToSendTheHeaders = 10;
    public const int SecondsIdleBetweenRequests = 30;
    public const int SecondsToTakeAPiece = 30;
    public const int BytesPerPiece = 256 * 1024;

    private readonly TcpListener _listener;
    private readonly DeployedFolderResolver _resolver;
    private readonly Action? _onFolderGone;
    private readonly Action? _onEnded;
    private readonly CancellationTokenSource _stopping = new();
    private readonly object _gate = new();
    private readonly List<Connection> _connections = [];
    private int _nextArrival;
    private int _requests;
    private int _notFound;
    private int _folderGoneReported;

    private DeployedFolderServer(TcpListener listener, int port, DeployedFolderResolver resolver, Action? onFolderGone, Action? onEnded)
    {
        _listener = listener;
        Port = port;
        _resolver = resolver;
        _onFolderGone = onFolderGone;
        _onEnded = onEnded;
    }

    /// <summary>The folder served, as the app names it.</summary>
    public string Root => _resolver.Root;

    /// <summary>The port it listens on, on 127.0.0.1.</summary>
    public int Port { get; }

    /// <summary>The address the browser is handed: <c>http://127.0.0.1:&lt;port&gt;/</c>.</summary>
    public Uri Address => DeployedFolderAddress.AddressOf(Port);

    /// <summary>Requests answered so far, for the trail's line when it stops (counts only, never an address).</summary>
    public int Requests => Volatile.Read(ref _requests);

    /// <summary>Of those, how many found nothing.</summary>
    public int NotFound => Volatile.Read(ref _notFound);

    /// <summary>Whether <see cref="Stop"/> has been called.</summary>
    public bool IsStopped => _stopping.IsCancellationRequested;

    /// <summary>Connections open now, for tests.</summary>
    public int OpenConnections
    {
        get { lock (_gate) return _connections.Count; }
    }

    /// <summary>What starting found.</summary>
    /// <param name="Server">The server, listening; null when every candidate was held.</param>
    /// <param name="FirstWasTaken">The first candidate (the remembered or usual address) was held, so the address moved: the trail says so.</param>
    public sealed record StartResult(DeployedFolderServer? Server, bool FirstWasTaken);

    /// <summary>
    /// Starts on the first of <paramref name="candidates"/> nothing else holds.
    /// A port another program listens on, on 127.0.0.1 or on every address, is
    /// passed over (see the remarks on <see cref="IsHeldByAnotherListener"/>).
    /// </summary>
    /// <param name="root">The section's deployed folder.</param>
    /// <param name="candidates">The ports to try, in order (<see cref="DeployedFolderAddress.Candidates"/>).</param>
    /// <param name="onFolderGone">Called once, the first time a request finds the folder gone.</param>
    /// <param name="onEnded">Called once if the listener ends without <see cref="Stop"/>.</param>
    /// <param name="files">The disk; a test's map in tests.</param>
    public static StartResult Start(string root, IReadOnlyList<int> candidates, Action? onFolderGone = null,
                                    Action? onEnded = null, ILocalFiles? files = null)
    {
        var resolver = new DeployedFolderResolver(root, files);
        int tried = 0;
        foreach (int port in candidates)
        {
            if (port is < 1 or > 65535) { tried++; continue; }
            if (IsHeldByAnotherListener(port)) { tried++; continue; }
            var listener = new TcpListener(IPAddress.Loopback, port) { ExclusiveAddressUse = true };
            try
            {
                listener.Start(MaximumConnections);
            }
            catch (SocketException)
            {
                listener.Stop();
                tried++;
                continue;
            }
            var server = new DeployedFolderServer(listener, port, resolver, onFolderGone, onEnded);
            StartThread(server.AcceptLoop, "Plantoir deployed folder " + port);
            return new StartResult(server, tried > 0);
        }
        return new StartResult(null, tried > 0);
    }

    /// <summary>
    /// Whether another socket on this PC already listens on <paramref name="port"/>
    /// at 127.0.0.1 or at every address (<c>0.0.0.0</c>). Asked BEFORE binding
    /// because Windows lets a bind to 127.0.0.1 succeed over another program's
    /// bind to 0.0.0.0 (measured on this PC: see documentation/12), and the more
    /// specific bind then takes that program's loopback connections. Moving on
    /// leaves the other program alone.
    /// </summary>
    public static bool IsHeldByAnotherListener(int port)
    {
        try
        {
            foreach (var endpoint in ActiveListeners())
            {
                if (endpoint.Port != port) continue;
                if (endpoint.Address.Equals(IPAddress.Loopback) || endpoint.Address.Equals(IPAddress.Any)) return true;
            }
        }
        catch (System.Net.NetworkInformation.NetworkInformationException) { }
        return false;
    }

    /// <summary>
    /// Every TCP listener on this PC, from the system's own table. A seam so a
    /// test can stand in a listener on every address WITHOUT binding one: a
    /// real bind to 0.0.0.0 raises Windows Defender Firewall's prompt for the
    /// program that makes it (measured on this PC, 2026-11-13: a test that did
    /// so put a "Windows Security" prompt for testhost.exe on the desktop).
    /// </summary>
    internal static Func<IEnumerable<IPEndPoint>> ActiveListeners { get; set; } =
        () => System.Net.NetworkInformation.IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners();

    /// <summary>Stops listening, closes every connection and frees the port. Safe to call more than once.</summary>
    public void Stop()
    {
        List<Connection> open;
        lock (_gate)
        {
            if (_stopping.IsCancellationRequested) return;
            _stopping.Cancel();
            open = [.. _connections];
            _connections.Clear();
        }
        try { _listener.Stop(); } catch (SocketException) { }
        foreach (var connection in open) connection.Reset();
    }

    public void Dispose() => Stop();

    /// <summary>
    /// Every listener and connection has a THREAD of its own, with blocking
    /// calls and socket timeouts, rather than tasks on the thread pool: in the
    /// full suite on this PC, with the pool starved by 3,900 tests, an answer
    /// to a plain GET did not arrive within 20 s and the 10 s header deadline
    /// fired late (2026-11-14). A deadline that is a socket timeout fires on
    /// time whatever else the process is doing. At most 64 connections, so at
    /// most 65 threads a show, each a background thread (none keeps the
    /// process alive).
    /// </summary>
    private static void StartThread(Action work, string name) =>
        new Thread(() => work()) { IsBackground = true, Name = name }.Start();

    // ---- Connections ------------------------------------------------------------------

    private sealed class Connection(Socket socket, int arrival)
    {
        public Socket Socket { get; } = socket;
        public int Arrival { get; } = arrival;
        private long _lastActivity = Stopwatch.GetTimestamp();
        private int _closed;

        public long LastActivity => Interlocked.Read(ref _lastActivity);

        public void Touch() => Interlocked.Exchange(ref _lastActivity, Stopwatch.GetTimestamp());

        public bool IsClosed => Volatile.Read(ref _closed) != 0;

        /// <summary>
        /// Closes with a reset rather than a graceful close: a graceful close
        /// waits behind bytes a stalled reader will never take (the mac's fix
        /// review M-c), and a reset also leaves no TIME_WAIT on this side.
        /// </summary>
        public void Reset()
        {
            if (Interlocked.Exchange(ref _closed, 1) != 0) return;
            try { Socket.LingerState = new LingerOption(true, 0); } catch (Exception e) when (e is SocketException or ObjectDisposedException) { }
            try { Socket.Close(); } catch (Exception e) when (e is SocketException or ObjectDisposedException) { }
        }

        /// <summary>Closes after the answer has gone: no more is sent, what the peer still sends is read and dropped for a moment so it sees the answer rather than a reset.</summary>
        public void CloseAfterAnswer()
        {
            if (Volatile.Read(ref _closed) != 0) return;
            try
            {
                Socket.Shutdown(SocketShutdown.Send);
                Socket.ReceiveTimeout = 2000;
                var scratch = new byte[4096];
                int total = 0;
                var clock = Stopwatch.StartNew();
                while (total < 65536 && clock.Elapsed < TimeSpan.FromSeconds(2))
                {
                    int read = Socket.Receive(scratch);
                    if (read == 0) break;
                    total += read;
                }
            }
            catch (Exception e) when (e is SocketException or ObjectDisposedException) { }
            if (Interlocked.Exchange(ref _closed, 1) != 0) return;
            try { Socket.Close(); } catch (Exception e) when (e is SocketException or ObjectDisposedException) { }
        }
    }

    private void AcceptLoop()
    {
        while (true)
        {
            Socket socket;
            try
            {
                socket = _listener.AcceptSocket();
            }
            catch (Exception) when (_stopping.IsCancellationRequested)
            {
                return;
            }
            catch (Exception e) when (e is SocketException or ObjectDisposedException or InvalidOperationException)
            {
                // The listener ended without being asked (the mac's
                // implementation review L4): the show is dropped.
                Stop();
                _onEnded?.Invoke();
                return;
            }
            Connection connection;
            Connection? makingRoom = null;
            lock (_gate)
            {
                if (_stopping.IsCancellationRequested)
                {
                    socket.Close();
                    return;
                }
                // Full: the connection quiet longest makes room, so a newcomer
                // (the teacher's own browser) always gets in. A paused video or
                // a reader that stopped is the one that goes, never the newcomer.
                if (_connections.Count >= MaximumConnections)
                {
                    makingRoom = _connections.OrderBy(c => c.LastActivity).ThenBy(c => c.Arrival).First();
                    _connections.Remove(makingRoom);
                }
                // No Nagle: an answer is its head and then its body, two sends,
                // and with Nagle the second waits for the browser's delayed
                // acknowledgement of the first (measured on this PC: 284
                // requests took 43.9 s, about 155 ms each, before this line).
                try { socket.NoDelay = true; } catch (SocketException) { }
                connection = new Connection(socket, _nextArrival++);
                _connections.Add(connection);
            }
            makingRoom?.Reset();
            StartThread(() => ServeConnection(connection), "Plantoir deployed folder connection");
        }
    }

    private void Forget(Connection connection)
    {
        lock (_gate) _connections.Remove(connection);
    }

    private static readonly byte[] EndOfHead = "\r\n\r\n"u8.ToArray();

    private void ServeConnection(Connection connection)
    {
        var buffer = new List<byte>(4096);
        var chunk = new byte[16384];
        long deadline = Stopwatch.GetTimestamp() + Seconds(SecondsToSendTheHeaders);
        bool waitingForANewRequest = false;
        // Where the search for the end of the head resumes, so a request
        // dripped in a byte at a time is not searched from its start each time.
        int searched = 0;
        try
        {
            while (!connection.IsClosed && !_stopping.IsCancellationRequested)
            {
                int end = IndexOf(buffer, EndOfHead, Math.Max(0, searched - (EndOfHead.Length - 1)));
                searched = buffer.Count;
                if (end < 0)
                {
                    if (buffer.Count > MaximumRequestLineBytes && IndexOf(buffer, "\r\n"u8.ToArray(), 0) < 0)
                    {
                        AnswerAndClose(connection, 414);
                        return;
                    }
                    if (buffer.Count > MaximumRequestLineBytes + MaximumHeaderBytes) { AnswerAndClose(connection, 431); return; }
                    long remaining = deadline - Stopwatch.GetTimestamp();
                    if (remaining <= 0) { connection.Reset(); return; }
                    int read;
                    try
                    {
                        // The deadline IS the socket's timeout: a real one, kept by the system.
                        connection.Socket.ReceiveTimeout = (int)Math.Max(1, remaining * 1000 / Stopwatch.Frequency);
                        read = connection.Socket.Receive(chunk);
                    }
                    catch (Exception e) when (e is SocketException or ObjectDisposedException)
                    {
                        connection.Reset();
                        return;
                    }
                    if (read == 0) { connection.Reset(); return; }
                    connection.Touch();
                    if (waitingForANewRequest)
                    {
                        // A new request has begun: it has this long to finish its headers.
                        waitingForANewRequest = false;
                        deadline = Stopwatch.GetTimestamp() + Seconds(SecondsToSendTheHeaders);
                    }
                    for (int i = 0; i < read; i++) buffer.Add(chunk[i]);
                    continue;
                }

                byte[] head = buffer.GetRange(0, end).ToArray();
                buffer.RemoveRange(0, end + EndOfHead.Length);
                searched = 0;
                string text = Encoding.Latin1.GetString(head);
                string[] lines = text.Split("\r\n");
                int requestLineBytes = lines[0].Length;
                if (requestLineBytes > MaximumRequestLineBytes) { AnswerAndClose(connection, 414); return; }
                if (head.Length - requestLineBytes > MaximumHeaderBytes) { AnswerAndClose(connection, 431); return; }
                if (Parse(lines) is not { } parsed) { AnswerAndClose(connection, 400); return; }

                Interlocked.Increment(ref _requests);
                bool folderGone = !_resolver.FolderIsThere() && Interlocked.Exchange(ref _folderGoneReported, 1) == 0;
                using var answer = _resolver.Answer(parsed.Request, Port);
                if (answer.Status == 404) Interlocked.Increment(ref _notFound);
                if (!parsed.KeepsAlive) answer.ClosesTheConnection = true;
                bool sent = Send(connection, answer);
                // Told AFTER the answer has gone: the show it ends stops this
                // server, which would otherwise reset the very connection the
                // browser is waiting on (found by ARequestThatFindsTheFolderGoneStopsItUntilDismissed).
                if (folderGone && _onFolderGone is { } gone) StartThread(gone, "Plantoir deployed folder gone");
                if (!sent) { connection.Reset(); return; }
                if (answer.ClosesTheConnection) { connection.CloseAfterAnswer(); return; }

                if (buffer.Count == 0)
                {
                    waitingForANewRequest = true;
                    deadline = Stopwatch.GetTimestamp() + Seconds(SecondsIdleBetweenRequests);
                }
                else deadline = Stopwatch.GetTimestamp() + Seconds(SecondsToSendTheHeaders);
            }
        }
        catch (Exception e) when (e is SocketException or ObjectDisposedException or IOException or InvalidOperationException)
        {
            connection.Reset();
        }
        finally
        {
            Forget(connection);
        }
    }

    private static long Seconds(int seconds) => seconds * Stopwatch.Frequency;

    private static int IndexOf(List<byte> buffer, byte[] wanted, int from)
    {
        for (int i = from; i + wanted.Length <= buffer.Count; i++)
        {
            int j = 0;
            while (j < wanted.Length && buffer[i + j] == wanted[j]) j++;
            if (j == wanted.Length) return i;
        }
        return -1;
    }

    /// <summary>A parsed request and whether the connection stays open after it.</summary>
    public sealed record Parsed(DeployedFolderRequest Request, bool KeepsAlive);

    /// <summary>The request line and headers, or null for something that is not an HTTP/1 request.</summary>
    public static Parsed? Parse(IReadOnlyList<string> lines)
    {
        if (lines.Count == 0) return null;
        string[] words = lines[0].Split(' ');
        if (words.Length != 3 || words[0].Length == 0 || words[1].Length == 0) return null;
        string version = words[2];
        if (version != "HTTP/1.1" && version != "HTTP/1.0") return null;
        var headers = new List<KeyValuePair<string, string>>();
        for (int index = 1; index < lines.Count; index++)
        {
            string line = lines[index];
            int colon = line.IndexOf(':');
            if (colon <= 0) return null;
            string name = line[..colon].ToLowerInvariant();
            if (name.Contains(' ') || name.Contains('\t')) return null;
            headers.Add(new(name, line[(colon + 1)..].Trim(' ', '\t')));
        }
        var request = new DeployedFolderRequest(words[0], words[1], headers);
        bool keepsAlive = version == "HTTP/1.1";
        if ((request.Value("connection") ?? "").Contains("close", StringComparison.OrdinalIgnoreCase)) keepsAlive = false;
        return new Parsed(request, keepsAlive);
    }

    private void AnswerAndClose(Connection connection, int status)
    {
        using var answer = DeployedFolderResolver.Refusal(status, closing: true);
        if (Send(connection, answer)) connection.CloseAfterAnswer();
        else connection.Reset();
    }

    /// <summary>The status line and headers as bytes.</summary>
    public static byte[] HeadBytes(DeployedFolderAnswer answer)
    {
        var text = new StringBuilder();
        text.Append("HTTP/1.1 ").Append(answer.Status.ToString(CultureInfo.InvariantCulture)).Append(' ')
            .Append(DeployedFolderResolver.Reason(answer.Status)).Append("\r\n");
        foreach (var header in answer.Headers) text.Append(header.Key).Append(": ").Append(header.Value).Append("\r\n");
        if (answer.ClosesTheConnection) text.Append("Connection: close\r\n");
        text.Append("\r\n");
        return Encoding.UTF8.GetBytes(text.ToString());
    }

    /// <summary>Sends one answer a piece at a time, each piece to be taken within <see cref="SecondsToTakeAPiece"/>. False when it could not be sent.</summary>
    private bool Send(Connection connection, DeployedFolderAnswer answer)
    {
        byte[] head = HeadBytes(answer);
        if (answer.Data is { } data)
        {
            var whole = new byte[head.Length + data.Length];
            head.CopyTo(whole, 0);
            data.CopyTo(whole, head.Length);
            head = whole;
        }
        if (!SendPiece(connection, head)) return false;
        if (answer.File is not { } file || answer.Length <= 0) return true;

        // A large answer (a video) is sent through a send buffer of one piece
        // rather than Windows' autotuned one: with autotuning the system took
        // so much of a 200 MB answer into its buffers that 64 readers that
        // never read were still not blocked at 47 s while another suite ran
        // (2026-11-14), so the piece deadline never started. Not for every
        // answer: set on a page's connection it cost about 130 ms a request
        // (the crawl of 284 addresses took 38.8 s instead of 4.8 s).
        if (answer.Length > 4L * BytesPerPiece)
        {
            try { connection.Socket.SendBufferSize = BytesPerPiece; } catch (SocketException) { }
        }
        file.Seek(answer.Offset, SeekOrigin.Begin);
        long remaining = answer.Length;
        var piece = new byte[(int)Math.Min(BytesPerPiece, remaining)];
        while (remaining > 0)
        {
            int wanted = (int)Math.Min(piece.Length, remaining);
            if (_stopping.IsCancellationRequested) return false;
            int read = file.Read(piece, 0, wanted);
            // The file shrank while it was being sent: the length promised
            // cannot be kept, so the connection closes.
            if (read <= 0) return false;
            if (!SendPiece(connection, piece.AsSpan(0, read))) return false;
            remaining -= read;
        }
        return true;
    }

    /// <summary>
    /// One piece, sent with the socket's own send timeout of
    /// <see cref="SecondsToTakeAPiece"/>: a blocking send the reader does not
    /// take in time fails, and the connection is reset (a socket whose send
    /// timed out is not used again).
    /// </summary>
    private static bool SendPiece(Connection connection, ReadOnlySpan<byte> bytes)
    {
        try
        {
            connection.Socket.SendTimeout = SecondsToTakeAPiece * 1000;
            while (bytes.Length > 0)
            {
                int sent = connection.Socket.Send(bytes);
                if (sent <= 0) return false;
                bytes = bytes[sent..];
                connection.Touch();
            }
            return true;
        }
        catch (Exception e) when (e is SocketException or ObjectDisposedException)
        {
            return false;
        }
    }
}
