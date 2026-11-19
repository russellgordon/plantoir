using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// The deployed folder's tests that hold the server to WALL-CLOCK deadlines
/// (10 s for the headers, 30 s for a piece, an answer within seconds). Run
/// alone, after the parallel classes: in the full suite on this PC, with
/// 3,900 tests sharing the thread pool, an answer to a plain GET did not
/// arrive within 20 s and the header deadline fired late (2026-11-14, the
/// first full run of 889a), which measures the run's load, not the server.
/// </summary>
[Xunit.CollectionDefinition(Name, DisableParallelization = true)]
public sealed class DeployedFolderTimings
{
    public const string Name = "Deployed folder timings";
}

/// <summary>
/// Shared by the deployed folder's tests (#889, the mac's #850): the contract
/// block, a folder built from a resolution case's <c>files</c>, a raw HTTP/1.1
/// client over a real socket, and the disk seam that follows a case's links by
/// hand so a FILE link runs on an account that cannot make one.
/// </summary>
internal static class DeployedFolderFixtures
{
    public static JsonNode Block => ContractLoader.LoadJson("shared-rules.json")["deployedFolderInBrowser"]!;

    public static JsonArray ResolutionCases => Block["resolution"]!["cases"]!.AsArray();

    /// <summary>What a case's placeholders become.</summary>
    public sealed record Places(string Root, string Outside, int Port)
    {
        public string Fill(string text) => text
            .Replace("@OTHERPORT@", (Port + 1).ToString())
            .Replace("@PORT@", Port.ToString())
            .Replace("@OUTSIDE@", Outside.Replace('\\', '/'));
    }

    /// <summary>The marker written into the file OUTSIDE the served folder: no answer may carry a byte of it.</summary>
    public const string SecretMarker = "SECRET-OUTSIDE-THE-SERVED-FOLDER";

    /// <summary>The bytes a case's file holds: <c>@BYTES200@</c> and <c>@BYTES100@</c> are that many bytes, anything else its UTF-8.</summary>
    public static byte[] Content(string written) => written switch
    {
        "@BYTES200@" => Enumerable.Range(0, 200).Select(i => (byte)('A' + i % 26)).ToArray(),
        "@BYTES100@" => Enumerable.Range(0, 100).Select(i => (byte)('a' + i % 26)).ToArray(),
        _ => Encoding.UTF8.GetBytes(written),
    };

    /// <summary>A case's links: name inside the root → target as the contract writes it (placeholders filled).</summary>
    public static Dictionary<string, string> Links(JsonNode testCase, Places places)
    {
        var links = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (name, value) in testCase["files"]!.AsObject())
            if (value is JsonObject link) links[name] = places.Fill(link["symlinkTo"]!.ToString());
        return links;
    }

    /// <summary>Writes a case's ordinary files under <paramref name="root"/> (links are the caller's) and the outside folder's secret.</summary>
    public static void WriteFiles(JsonNode testCase, Places places)
    {
        Directory.CreateDirectory(places.Root);
        Directory.CreateDirectory(places.Outside);
        File.WriteAllText(Path.Combine(places.Outside, "secret.html"), SecretMarker);
        foreach (var (name, value) in testCase["files"]!.AsObject())
        {
            if (value is JsonObject) continue;
            string path = Path.Combine(places.Root, name.Replace('/', '\\'));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllBytes(path, Content(value!.ToString()));
        }
    }

    /// <summary>The bytes a case says a file holds, by its name in the case.</summary>
    public static byte[]? ExpectedContent(JsonNode testCase, string file)
    {
        foreach (var (name, value) in testCase["files"]!.AsObject())
            if (name.Normalize(NormalizationForm.FormC) == file.Normalize(NormalizationForm.FormC) && value is not JsonObject)
                return Content(value!.ToString());
        return null;
    }

    /// <summary>A case's request: its headers when it names them (placeholders filled, the order kept), else a Host of 127.0.0.1:@PORT@ alone.</summary>
    public static DeployedFolderRequest Request(JsonNode testCase, Places places)
    {
        var request = testCase["request"]!;
        var headers = new List<KeyValuePair<string, string>>();
        if (request["headers"] is JsonObject written)
            foreach (var (name, value) in written) headers.Add(new(name.ToLowerInvariant(), places.Fill(value!.ToString())));
        else headers.Add(new("host", "127.0.0.1:" + places.Port));
        return new DeployedFolderRequest(request["method"]!.ToString(), places.Fill(request["target"]!.ToString()), headers);
    }

    /// <summary>A port nothing listens on now, from the system, for one test's server.</summary>
    public static int FreePort()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        int port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        return port;
    }

    /// <summary>A response read off the wire.</summary>
    public sealed record Response(int Status, List<KeyValuePair<string, string>> Headers, byte[] Body, bool Closed)
    {
        public string? Value(string name) =>
            Headers.FirstOrDefault(h => string.Equals(h.Key, name, StringComparison.OrdinalIgnoreCase)).Value;

        public string BodyText => Encoding.UTF8.GetString(Body);
    }

    /// <summary>The bytes of a request: its line and headers as the case writes them, ending in an empty line.</summary>
    public static byte[] Wire(DeployedFolderRequest request)
    {
        var text = new StringBuilder();
        text.Append(request.Method).Append(' ').Append(request.Target).Append(" HTTP/1.1\r\n");
        foreach (var header in request.Headers) text.Append(header.Key).Append(": ").Append(header.Value).Append("\r\n");
        text.Append("\r\n");
        return Encoding.UTF8.GetBytes(text.ToString());
    }

    /// <summary>Opens a connection to the listener.</summary>
    public static Socket Connect(int port)
    {
        var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp) { ReceiveTimeout = 15_000, SendTimeout = 15_000 };
        socket.Connect(IPAddress.Loopback, port);
        return socket;
    }

    /// <summary>
    /// Sends one request on a new connection and reads one answer: the status,
    /// the headers, the body by its Content-Length (none for HEAD), and whether
    /// the server closed the connection after it (read within
    /// <paramref name="closeWait"/>).
    /// </summary>
    public static Response Exchange(int port, byte[] wire, bool isHead, TimeSpan? closeWait = null)
    {
        using var socket = Connect(port);
        socket.Send(wire);
        var reader = new WireReader(socket);
        return reader.ReadResponse(isHead, closeWait ?? TimeSpan.FromSeconds(3));
    }

    /// <summary>Reads answers off one connection.</summary>
    public sealed class WireReader(Socket socket)
    {
        private readonly List<byte> _buffer = [];

        private bool Fill(TimeSpan wait)
        {
            var chunk = new byte[65536];
            socket.ReceiveTimeout = Math.Max(1, (int)wait.TotalMilliseconds);
            Timedout = false;
            try
            {
                int read = socket.Receive(chunk);
                if (read == 0) return false;
                _buffer.AddRange(chunk.Take(read));
                return true;
            }
            catch (SocketException e)
            {
                Timedout = e.SocketErrorCode == SocketError.TimedOut;
                return false;
            }
        }

        public Response ReadResponse(bool isHead, TimeSpan closeWait)
        {
            int end;
            var clock = Stopwatch.StartNew();
            while ((end = IndexOf(_buffer, "\r\n\r\n"u8.ToArray())) < 0)
            {
                if (clock.Elapsed > TimeSpan.FromSeconds(20) || !Fill(TimeSpan.FromSeconds(20)))
                    throw new IOException("no answer arrived: " + Encoding.Latin1.GetString(_buffer.ToArray()));
            }
            string head = Encoding.UTF8.GetString(_buffer.GetRange(0, end).ToArray());
            _buffer.RemoveRange(0, end + 4);
            string[] lines = head.Split("\r\n");
            int status = int.Parse(lines[0].Split(' ')[1]);
            var headers = new List<KeyValuePair<string, string>>();
            foreach (string line in lines.Skip(1))
            {
                int colon = line.IndexOf(':');
                headers.Add(new(line[..colon], line[(colon + 1)..].Trim()));
            }
            int length = isHead ? 0 : int.Parse(headers.FirstOrDefault(h => h.Key.Equals("Content-Length", StringComparison.OrdinalIgnoreCase)).Value ?? "0");
            while (_buffer.Count < length)
                if (!Fill(TimeSpan.FromSeconds(20))) break;
            byte[] body = _buffer.Take(length).ToArray();
            _buffer.RemoveRange(0, Math.Min(length, _buffer.Count));
            bool closed = false;
            if (closeWait > TimeSpan.Zero)
            {
                // Closed means the peer ended the stream (or reset it) soon
                // after the answer, with nothing more sent.
                int before = _buffer.Count;
                closed = !Fill(closeWait) && _buffer.Count == before && !Timedout;
            }
            return new Response(status, headers, body, closed);
        }

        /// <summary>Whether the last read ended because nothing came in time rather than because the connection ended.</summary>
        public bool Timedout { get; private set; }

        /// <summary>Bytes received beyond the answers read so far (a HEAD must leave none).</summary>
        public int Extra => _buffer.Count;
    }

    private static int IndexOf(List<byte> buffer, byte[] wanted)
    {
        for (int i = 0; i + wanted.Length <= buffer.Count; i++)
        {
            int j = 0;
            while (j < wanted.Length && buffer[i + j] == wanted[j]) j++;
            if (j == wanted.Length) return i;
        }
        return -1;
    }

    /// <summary>
    /// Whether the server ends a connection within <paramref name="wait"/>:
    /// a read that returns 0 bytes, or a reset. A read that times out is NOT
    /// closed.
    /// </summary>
    public static bool ClosesWithin(Socket socket, TimeSpan wait)
    {
        socket.ReceiveTimeout = Math.Max(1, (int)wait.TotalMilliseconds);
        var chunk = new byte[65536];
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed < wait + TimeSpan.FromSeconds(1))
        {
            try
            {
                int read = socket.Receive(chunk);
                if (read == 0) return true;
            }
            catch (SocketException e) when (e.SocketErrorCode == SocketError.TimedOut) { return false; }
            catch (SocketException) { return true; }
        }
        return false;
    }

    /// <summary>
    /// The real disk with a case's LINKS laid over it, followed by hand: a link
    /// named inside the served folder leads where the case says, and every
    /// question about a path through it is asked of the real disk at the place
    /// it leads, through 790a's <see cref="WindowsLocalFiles"/>. So the two
    /// symbolic-link cases run on an account that cannot make a file link
    /// (WinError 1314 without Developer Mode), against the same containment
    /// check on the opened handle's final path that a real link meets.
    /// </summary>
    public sealed class DiskWithLinks(Dictionary<string, string> links) : ILocalFiles
    {
        private readonly Dictionary<string, string> _links = links.ToDictionary(
            pair => Path.GetFullPath(pair.Key).TrimEnd('\\'), pair => Path.GetFullPath(pair.Value.Replace('/', '\\')).TrimEnd('\\'),
            StringComparer.OrdinalIgnoreCase);

        private string Resolve(string path)
        {
            string full = Path.GetFullPath(path).TrimEnd('\\');
            foreach (var (link, target) in _links)
            {
                if (string.Equals(full, link, StringComparison.OrdinalIgnoreCase)) return target;
                if (full.StartsWith(link + "\\", StringComparison.OrdinalIgnoreCase)) return target + full[link.Length..];
            }
            return full;
        }

        public string? FinalPath(string path) => WindowsLocalFiles.Instance.FinalPath(Resolve(path));

        public bool IsFolder(string realPath) => WindowsLocalFiles.Instance.IsFolder(realPath);

        public LocalFile? Open(string path) => WindowsLocalFiles.Instance.Open(Resolve(path));

        public IReadOnlyList<string>? List(string path)
        {
            string full = Path.GetFullPath(path).TrimEnd('\\');
            var names = WindowsLocalFiles.Instance.List(Resolve(path))?.ToList();
            if (names is null) return null;
            foreach (string link in _links.Keys)
                if (string.Equals(Path.GetDirectoryName(link), full, StringComparison.OrdinalIgnoreCase)) names.Add(Path.GetFileName(link));
            return names;
        }
    }
}
