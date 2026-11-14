using System.Globalization;
using System.Text;

namespace Plantoir.Core.Models;

/// <summary>One request, as the deployed folder's server read it (#889, the mac's #850).</summary>
/// <param name="Method">The method, as sent (case counts: <c>get</c> is not GET).</param>
/// <param name="Target">The request target exactly as sent, never canonicalised.</param>
/// <param name="Headers">Every header in arrival order, names lower-cased, values trimmed.</param>
public sealed record DeployedFolderRequest(string Method, string Target, IReadOnlyList<KeyValuePair<string, string>> Headers)
{
    /// <summary>A request with a Host of <c>127.0.0.1:&lt;port&gt;</c> alone, as a browser sends one.</summary>
    public static DeployedFolderRequest Get(string target, int port, string method = "GET") =>
        new(method, target, new[] { new KeyValuePair<string, string>("host", "127.0.0.1:" + port.ToString(CultureInfo.InvariantCulture)) });

    /// <summary>The first value of a header, by its lower-cased name.</summary>
    public string? Value(string name)
    {
        foreach (var header in Headers)
            if (header.Key == name) return header.Value;
        return null;
    }

    /// <summary>How many times a header arrived.</summary>
    public int Count(string name)
    {
        int total = 0;
        foreach (var header in Headers)
            if (header.Key == name) total++;
        return total;
    }
}

/// <summary>
/// One answer: a status, headers, and the bytes after them, either a small
/// built-in body or part of a file read from the ONE handle the checks were made
/// on. Dispose it when it has been sent (or not sent): it may hold that handle.
/// </summary>
public sealed class DeployedFolderAnswer : IDisposable
{
    public DeployedFolderAnswer(int status, List<KeyValuePair<string, string>> headers)
    {
        Status = status;
        Headers = headers;
    }

    public int Status { get; }

    /// <summary>The headers, in the order they are written.</summary>
    public List<KeyValuePair<string, string>> Headers { get; }

    /// <summary>A small body of the answer's own (the built-in 404 page), or null.</summary>
    public byte[]? Data { get; init; }

    /// <summary>The file the body is read from, opened once, or null.</summary>
    public Stream? File { get; init; }

    /// <summary>Where in <see cref="File"/> the body starts.</summary>
    public long Offset { get; init; }

    /// <summary>How many bytes of <see cref="File"/> the body is.</summary>
    public long Length { get; init; }

    /// <summary>The connection closes after this answer.</summary>
    public bool ClosesTheConnection { get; set; }

    /// <summary>The file served, relative to the folder with <c>/</c>, for tests; null when no file was served.</summary>
    public string? ServedFile { get; init; }

    /// <summary>The first value of a header, ignoring case.</summary>
    public string? Value(string name)
    {
        foreach (var header in Headers)
            if (string.Equals(header.Key, name, StringComparison.OrdinalIgnoreCase)) return header.Value;
        return null;
    }

    public void Dispose() => File?.Dispose();
}

/// <summary>
/// How a request from the browser is answered from a section's deployed folder
/// (#889, the mac's #850): which file, which redirect, or which refusal. Pure
/// apart from reading the folder through <see cref="ILocalFiles"/>, so
/// <c>DeployedFolderResolutionTests</c> runs every case of
/// <c>contracts/shared-rules.json</c> → <c>deployedFolderInBrowser.resolution.cases</c>
/// both here and through the real listener over a socket.
/// </summary>
/// <remarks>
/// <para><b>The aim</b> (the mac's plan review M7): every link the build writes
/// resolves, and nothing a strict web host refuses is accepted. Not a copy of any
/// one host: a folder deploy's host is unknown (#849).</para>
///
/// <para><b>The raw target is read, never a canonicalised URL.</b> Each name is
/// percent-decoded ONCE, strictly (broken escapes and bytes that are not UTF-8
/// are refused), put in NFC, and then checked by
/// <see cref="LocalSiteGuard.IsAcceptableSegment"/> (790a's rule: devices, a colon
/// so no alternate data stream, a trailing dot or space that Windows would strip
/// and read another file by) plus this server's own refusals: a leading dot, and
/// the hosts' control files <c>_headers</c> and <c>_redirects</c>.</para>
///
/// <para><b>Every name on the way down is matched against its folder's
/// listing</b>, exactly after NFC (<see cref="ILocalFiles.List"/>), never
/// <c>File.Exists</c>: NTFS ignores case and expands 8.3 short names, and a
/// strict host does neither, so <c>/concepts/</c> does not find
/// <c>Concepts\</c> and <c>PROGRA~1</c> finds nothing.</para>
///
/// <para><b>Containment is checked on the OPENED handle</b> (790a's disk layer,
/// the plan review's M8): the file is opened once with links followed, that
/// handle's own final path must be inside the folder's final path
/// (<see cref="LocalSiteGuard.IsWithin"/>), it must be an ordinary disk file,
/// and its bytes are read from the same handle. A junction or link swapped
/// between the check and the read changes nothing.</para>
/// </remarks>
public sealed class DeployedFolderResolver
{
    /// <summary>The page sent for a missing page when the site has no <c>404.html</c>.</summary>
    public const string BuiltInNotFoundPage =
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>404</title></head><body><h1>404</h1></body></html>";

    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    private readonly ILocalFiles _files;

    /// <param name="root">The section's deployed folder, as the app names it.</param>
    /// <param name="files">The disk; a test's map in tests.</param>
    public DeployedFolderResolver(string root, ILocalFiles? files = null)
    {
        Root = Path.GetFullPath(root).TrimEnd('\\', '/');
        if (Root.Length == 2 && Root[1] == ':') Root += "\\";
        _files = files ?? WindowsLocalFiles.Instance;
    }

    /// <summary>The folder served, as the app names it.</summary>
    public string Root { get; }

    /// <summary>Whether the folder is there now (read at each request: a request that finds it gone stops the show).</summary>
    public bool FolderIsThere() => _files.FinalPath(Root) is { } real && _files.IsFolder(real);

    // ---- The answer --------------------------------------------------------------

    /// <summary>The answer to <paramref name="request"/> for a listener on <paramref name="port"/>. Never throws.</summary>
    public DeployedFolderAnswer Answer(DeployedFolderRequest request, int port)
    {
        // Only the one address this app hands out (the mac's plan review H3):
        // a prefix check let 127.0.0.1.evil.example through, the name a page
        // rebinding itself to this computer would send.
        if (request.Count("host") != 1 || request.Value("host") != "127.0.0.1:" + port.ToString(CultureInfo.InvariantCulture))
            return Refusal(400, closing: true);
        if (request.Method != "GET" && request.Method != "HEAD")
        {
            // A body this never reads would be taken for the next request.
            bool saysItHasABody = request.Value("transfer-encoding") is not null
                                  || (request.Value("content-length") ?? "0").Trim() != "0";
            var refused = Refusal(405, closing: saysItHasABody);
            refused.Headers.Add(new("Allow", "GET, HEAD"));
            return refused;
        }
        // Only a path: an absolute address names another site.
        if (!request.Target.StartsWith('/')) return Refusal(400, closing: true);
        // A GET carries no body; one that says it does is not read past.
        if (request.Value("transfer-encoding") is not null) return Refusal(400, closing: true);
        if (request.Value("content-length") is { } length && length.Trim() != "0") return Refusal(400, closing: true);
        bool isHead = request.Method == "HEAD";

        try
        {
            return Resolve(request, isHead);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return NotFound(isHead);
        }
    }

    private DeployedFolderAnswer Resolve(DeployedFolderRequest request, bool isHead)
    {
        var (rawPath, query) = Split(request.Target);
        if (ReadPath(rawPath) is not { } path) return NotFound(isHead);
        if (_files.FinalPath(Root) is not { } realRoot || !_files.IsFolder(realRoot)) return NotFound(isHead);

        string directory = Root;
        var relative = new List<string>();
        for (int index = 0; index < path.Segments.Count - 1; index++)
        {
            if (EntryName(path.Segments[index], directory) is not { } actual || !IsFolderAt(Path.Join(directory, actual)))
                return NotFound(isHead);
            directory = Path.Join(directory, actual);
            relative.Add(actual);
        }

        string last = path.Segments.Count == 0 ? "" : path.Segments[^1];
        if (path.Segments.Count == 0 || path.EndsWithSlash)
        {
            // A folder's address: its index page.
            string folder = directory;
            var folderRelative = new List<string>(relative);
            if (last.Length > 0)
            {
                if (EntryName(last, directory) is { } actual && IsFolderAt(Path.Join(directory, actual)))
                {
                    folder = Path.Join(directory, actual);
                    folderRelative.Add(actual);
                }
                else if (EntryName(last + ".html", directory) is { } page && IsFileAt(Path.Join(directory, page)))
                {
                    // /a/ where only a.html exists: the page's own address.
                    return Redirect(path.Segments, endsWithSlash: false, query);
                }
                else return NotFound(isHead);
            }
            if (EntryName("index.html", folder) is { } indexName && IsFileAt(Path.Join(folder, indexName)))
            {
                folderRelative.Add(indexName);
                return Serve(Path.Join(folder, indexName), indexName, folderRelative, realRoot, request, isHead);
            }
            // Never a listing.
            return NotFound(isHead);
        }

        // No slash after the last name: the file itself, then that name + .html,
        // then a folder (redirected to its slash so its relative links work).
        if (EntryName(last, directory) is { } file && IsFileAt(Path.Join(directory, file)))
            return Serve(Path.Join(directory, file), file, [.. relative, file], realRoot, request, isHead);
        if (EntryName(last + ".html", directory) is { } withHtml && IsFileAt(Path.Join(directory, withHtml)))
            return Serve(Path.Join(directory, withHtml), withHtml, [.. relative, withHtml], realRoot, request, isHead);
        if (EntryName(last, directory) is { } sub && IsFolderAt(Path.Join(directory, sub)))
        {
            string folder = Path.Join(directory, sub);
            if (EntryName("index.html", folder) is { } indexName && IsFileAt(Path.Join(folder, indexName)))
                return Redirect(path.Segments, endsWithSlash: true, query);
        }
        return NotFound(isHead);
    }

    // ---- Reading the address -------------------------------------------------------

    /// <summary>The target split at its query; anything after a <c>#</c> dropped (a browser never sends one; a raw request might).</summary>
    public static (string Path, string? Query) Split(string target)
    {
        string path = target;
        string? query = null;
        int hash = path.IndexOf('#');
        if (hash >= 0) path = path[..hash];
        int mark = path.IndexOf('?');
        if (mark >= 0)
        {
            query = path[(mark + 1)..];
            path = path[..mark];
        }
        return (path, query);
    }

    /// <summary>A path read into its decoded names.</summary>
    public sealed record ReadPathResult(IReadOnlyList<string> Segments, bool EndsWithSlash);

    /// <summary>
    /// The path's names, decoded and checked, or null for a path that can name
    /// nothing in the folder: a leading <c>//</c>, a raw backslash, or any name
    /// <see cref="DecodedName"/> refuses.
    /// </summary>
    public static ReadPathResult? ReadPath(string rawPath)
    {
        if (!rawPath.StartsWith('/') || rawPath.StartsWith("//", StringComparison.Ordinal)) return null;
        if (rawPath.Contains('\\')) return null;
        string body = rawPath[1..];
        if (body.Length == 0) return new ReadPathResult([], true);
        var pieces = body.Split('/').ToList();
        bool endsWithSlash = false;
        if (pieces[^1].Length == 0)
        {
            endsWithSlash = true;
            pieces.RemoveAt(pieces.Count - 1);
        }
        var segments = new List<string>();
        foreach (string piece in pieces)
        {
            if (DecodedName(piece) is not { } decoded) return null;
            segments.Add(decoded);
        }
        return new ReadPathResult(segments, endsWithSlash);
    }

    /// <summary>The names never served whatever the folder holds: the web hosts' own control files.</summary>
    public static readonly IReadOnlyList<string> HostControlFiles = ["_headers", "_redirects"];

    /// <summary>One raw name, percent-decoded once (a <c>+</c> stays a <c>+</c>) and put in NFC, or null when it can name nothing here.</summary>
    public static string? DecodedName(string raw)
    {
        if (raw.Length == 0) return null;
        string lowered = raw.ToLowerInvariant();
        if (lowered.Contains("%2f") || lowered.Contains("%5c") || lowered.Contains("%00")) return null;
        var bytes = new List<byte>(raw.Length);
        for (int i = 0; i < raw.Length; i++)
        {
            char c = raw[i];
            if (c == '%')
            {
                if (i + 2 >= raw.Length || !IsHex(raw[i + 1]) || !IsHex(raw[i + 2])) return null;
                bytes.Add((byte)Convert.ToInt32(raw.Substring(i + 1, 2), 16));
                i += 2;
            }
            // The server reads the request as Latin-1, one char per byte, so a
            // raw UTF-8 name arrives as its bytes and is decoded strictly below.
            else if (c <= 0xFF) bytes.Add((byte)c);
            else return null;
        }
        string decoded;
        try { decoded = StrictUtf8.GetString(bytes.ToArray()); }
        catch (DecoderFallbackException) { return null; }
        if (!decoded.IsNormalized(NormalizationForm.FormC))
        {
            try { decoded = decoded.Normalize(NormalizationForm.FormC); }
            catch (ArgumentException) { return null; }
        }
        if (decoded.StartsWith('.')) return null;
        if (!LocalSiteGuard.IsAcceptableSegment(decoded)) return null;
        string lower = decoded.ToLowerInvariant();
        int dot = lower.IndexOf('.');
        string stem = dot < 0 ? lower : lower[..dot];
        foreach (string refused in HostControlFiles)
            if (stem == refused) return null;
        return decoded;
    }

    private static bool IsHex(char c) => c is >= '0' and <= '9' or >= 'a' and <= 'f' or >= 'A' and <= 'F';

    // ---- Reading the folder --------------------------------------------------------

    /// <summary>The entry of <paramref name="directory"/> whose name is <paramref name="wanted"/> exactly after NFC, or null. Case counts.</summary>
    private string? EntryName(string wanted, string directory)
    {
        if (_files.List(directory) is not { } names) return null;
        foreach (string name in names)
        {
            string composed = name;
            if (!composed.IsNormalized(NormalizationForm.FormC))
            {
                try { composed = composed.Normalize(NormalizationForm.FormC); }
                catch (ArgumentException) { continue; }
            }
            if (string.Equals(composed, wanted, StringComparison.Ordinal)) return name;
        }
        return null;
    }

    private bool IsFolderAt(string path) => _files.FinalPath(path) is { } real && _files.IsFolder(real);

    private bool IsFileAt(string path) => _files.FinalPath(path) is { } real && !_files.IsFolder(real);

    // ---- The answers -----------------------------------------------------------------

    /// <summary>A file, whole or the part a range asks for, from ONE handle whose own final path is inside the folder.</summary>
    private DeployedFolderAnswer Serve(string path, string name, IReadOnlyList<string> relative, string realRoot,
                                       DeployedFolderRequest request, bool isHead)
    {
        if (OpenInside(path, realRoot) is not { } file) return NotFound(isHead);
        bool handedOver = false;
        try
        {
            long length = file.Length;
            DateTime modified = file.Content is FileStream stream ? System.IO.File.GetLastWriteTimeUtc(stream.SafeFileHandle) : DateTime.UnixEpoch;
            long milliseconds = (long)(modified - DateTime.UnixEpoch).TotalMilliseconds;
            string tag = "W/\"" + length.ToString(CultureInfo.InvariantCulture) + "-" + milliseconds.ToString(CultureInfo.InvariantCulture) + "\"";

            var headers = CommonHeaders();
            headers.Add(new("Content-Type", DeployedFolderContentTypes.TypeOf(name)));
            headers.Add(new("Accept-Ranges", "bytes"));
            headers.Add(new("ETag", tag));
            headers.Add(new("Last-Modified", modified.ToString("r", CultureInfo.InvariantCulture)));
            string served = string.Join('/', relative);

            if (request.Value("if-none-match") is { } condition && condition == tag)
                return new DeployedFolderAnswer(304, headers) { ServedFile = served };

            if (request.Value("range") is { } rangeHeader)
            {
                var range = ByteRange(rangeHeader, length);
                if (range.Kind == RangeKind.Unsatisfiable)
                {
                    var refused = CommonHeaders();
                    refused.Add(new("Content-Range", "bytes */" + length.ToString(CultureInfo.InvariantCulture)));
                    refused.Add(new("Content-Length", "0"));
                    return new DeployedFolderAnswer(416, refused);
                }
                if (range.Kind == RangeKind.Part)
                {
                    long partLength = range.Last - range.First + 1;
                    headers.Add(new("Content-Range", FormattableString.Invariant($"bytes {range.First}-{range.Last}/{length}")));
                    headers.Add(new("Content-Length", partLength.ToString(CultureInfo.InvariantCulture)));
                    handedOver = !isHead;
                    return new DeployedFolderAnswer(206, headers)
                    {
                        File = isHead ? null : file.Content, Offset = range.First, Length = isHead ? 0 : partLength, ServedFile = served,
                    };
                }
            }
            headers.Add(new("Content-Length", length.ToString(CultureInfo.InvariantCulture)));
            handedOver = !isHead;
            return new DeployedFolderAnswer(200, headers)
            {
                File = isHead ? null : file.Content, Offset = 0, Length = isHead ? 0 : length, ServedFile = served,
            };
        }
        finally
        {
            if (!handedOver) file.Content.Dispose();
        }
    }

    private sealed record OpenedFile(Stream Content, long Length);

    /// <summary>
    /// The file opened ONCE, links followed, when THAT handle is an ordinary disk
    /// file whose own final path is inside <paramref name="realRoot"/>; null
    /// otherwise (the handle is closed). 790a's rule and code, reused.
    /// </summary>
    private OpenedFile? OpenInside(string path, string realRoot)
    {
        LocalFile? file;
        try { file = _files.Open(path); }
        catch { file = null; }
        if (file is null) return null;
        if (!file.IsDiskFile || !LocalSiteGuard.IsWithin(file.RealPath, realRoot))
        {
            file.Content.Dispose();
            return null;
        }
        long length;
        try { length = file.Content.Length; }
        catch (Exception e) when (e is IOException or NotSupportedException)
        {
            file.Content.Dispose();
            return null;
        }
        return new OpenedFile(file.Content, length);
    }

    /// <summary>What a <c>Range</c> header asks for.</summary>
    public enum RangeKind { Whole, Part, Unsatisfiable }

    /// <summary>A range read against a file: the whole of it, a part (inclusive bytes), or none that can be given.</summary>
    public readonly record struct RangeRequest(RangeKind Kind, long First = 0, long Last = 0);

    /// <summary>One <c>bytes=</c> range read against a file of <paramref name="length"/> bytes. Anything it cannot read, and several ranges, mean the whole file.</summary>
    public static RangeRequest ByteRange(string header, long length)
    {
        string trimmed = header.Trim();
        if (!trimmed.StartsWith("bytes=", StringComparison.Ordinal)) return new(RangeKind.Whole);
        string spec = trimmed["bytes=".Length..];
        if (spec.Contains(',')) return new(RangeKind.Whole);
        var halves = spec.Split('-');
        if (halves.Length != 2) return new(RangeKind.Whole);
        string startText = halves[0].Trim(), endText = halves[1].Trim();
        if (startText.Length == 0)
        {
            // The last N bytes.
            if (!TryDigits(endText, out long suffix)) return new(RangeKind.Whole);
            if (suffix == 0 || length == 0) return new(RangeKind.Unsatisfiable);
            return new(RangeKind.Part, suffix >= length ? 0 : length - suffix, length - 1);
        }
        if (!TryDigits(startText, out long first)) return new(RangeKind.Whole);
        if (first >= length) return new(RangeKind.Unsatisfiable);
        if (endText.Length == 0) return new(RangeKind.Part, first, length - 1);
        if (!TryDigits(endText, out long end) || end < first) return new(RangeKind.Whole);
        return new(RangeKind.Part, first, end >= length ? length - 1 : end);
    }

    private static bool TryDigits(string text, out long value) =>
        long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out value);

    /// <summary>A redirect to the page's own address, built from the DECODED names encoded again, so it is always single-slashed and percent-encoded.</summary>
    private static DeployedFolderAnswer Redirect(IReadOnlyList<string> segments, bool endsWithSlash, string? query)
    {
        var location = new StringBuilder();
        foreach (string segment in segments) location.Append('/').Append(EncodedName(segment));
        if (endsWithSlash) location.Append('/');
        if (location.Length == 0) location.Append('/');
        if (!string.IsNullOrEmpty(query) && QueryIsSafe(query)) location.Append('?').Append(query);
        var headers = CommonHeaders();
        headers.Add(new("Location", location.ToString()));
        headers.Add(new("Content-Length", "0"));
        return new DeployedFolderAnswer(308, headers);
    }

    /// <summary>One name, percent-encoded for an address: ASCII letters and digits and <c>-._~!$&amp;'()*+,;=@</c> kept, every other UTF-8 byte as <c>%XX</c>.</summary>
    public static string EncodedName(string name)
    {
        const string kept = "-._~!$&'()*+,;=@";
        var result = new StringBuilder();
        foreach (byte b in Encoding.UTF8.GetBytes(name))
        {
            char c = (char)b;
            if (b < 0x80 && (char.IsAsciiLetterOrDigit(c) || kept.Contains(c))) result.Append(c);
            else result.Append('%').Append(b.ToString("X2", CultureInfo.InvariantCulture));
        }
        return result.ToString();
    }

    /// <summary>A query is kept on a redirect only when it holds nothing that could end a header line.</summary>
    public static bool QueryIsSafe(string query)
    {
        foreach (char c in query)
            if (c < 0x21 || c > 0x7E) return false;
        return true;
    }

    /// <summary>The site's own <c>404.html</c> with a 404, or a short page of the server's own.</summary>
    private DeployedFolderAnswer NotFound(bool isHead)
    {
        var headers = CommonHeaders();
        headers.Add(new("Content-Type", "text/html; charset=utf-8"));
        if (_files.FinalPath(Root) is { } realRoot && EntryName("404.html", Root) is { } name
            && OpenInside(Path.Join(Root, name), realRoot) is { } page)
        {
            headers.Add(new("Content-Length", page.Length.ToString(CultureInfo.InvariantCulture)));
            if (isHead) page.Content.Dispose();
            return new DeployedFolderAnswer(404, headers)
            {
                File = isHead ? null : page.Content, Offset = 0, Length = isHead ? 0 : page.Length, ServedFile = "404.html",
            };
        }
        byte[] data = Encoding.UTF8.GetBytes(BuiltInNotFoundPage);
        headers.Add(new("Content-Length", data.Length.ToString(CultureInfo.InvariantCulture)));
        return new DeployedFolderAnswer(404, headers) { Data = isHead ? null : data };
    }

    /// <summary>A refusal with no page.</summary>
    public static DeployedFolderAnswer Refusal(int status, bool closing)
    {
        var headers = CommonHeaders();
        headers.Add(new("Content-Length", "0"));
        return new DeployedFolderAnswer(status, headers) { ClosesTheConnection = closing };
    }

    /// <summary>
    /// On every answer (<c>deployedFolderInBrowser.everyAnswer</c>): <c>no-cache</c>
    /// rather than <c>no-store</c>, so a redeploy shows on reload and the back and
    /// forward cache still works; <c>nosniff</c>; same-origin resources only; and
    /// never an <c>Access-Control-*</c> header.
    /// </summary>
    public static List<KeyValuePair<string, string>> CommonHeaders() =>
    [
        new("Cache-Control", "no-cache"),
        new("X-Content-Type-Options", "nosniff"),
        new("Cross-Origin-Resource-Policy", "same-origin"),
    ];

    /// <summary>The words after a status code.</summary>
    public static string Reason(int status) => status switch
    {
        200 => "OK",
        206 => "Partial Content",
        304 => "Not Modified",
        308 => "Permanent Redirect",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        408 => "Request Timeout",
        414 => "URI Too Long",
        416 => "Range Not Satisfiable",
        431 => "Request Header Fields Too Large",
        _ => "Error",
    };
}

/// <summary>The type each file is served as, by extension in any case (<c>deployedFolderInBrowser.contentTypes</c>; <c>IMG_0042.JPG</c> is a JPEG).</summary>
public static class DeployedFolderContentTypes
{
    /// <summary>What a file of no known extension is served as.</summary>
    public const string Unknown = "application/octet-stream";

    public static readonly IReadOnlyDictionary<string, string> ByExtension =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["html"] = "text/html; charset=utf-8", ["htm"] = "text/html; charset=utf-8",
            ["css"] = "text/css; charset=utf-8",
            ["js"] = "text/javascript; charset=utf-8", ["mjs"] = "text/javascript; charset=utf-8",
            ["json"] = "application/json", ["map"] = "application/json",
            ["wasm"] = "application/wasm", ["zip"] = "application/zip",
            ["svg"] = "image/svg+xml", ["png"] = "image/png", ["jpg"] = "image/jpeg", ["jpeg"] = "image/jpeg",
            ["gif"] = "image/gif", ["webp"] = "image/webp", ["avif"] = "image/avif", ["heic"] = "image/heic",
            ["ico"] = "image/x-icon", ["bmp"] = "image/bmp", ["tif"] = "image/tiff", ["tiff"] = "image/tiff",
            ["woff2"] = "font/woff2", ["woff"] = "font/woff", ["ttf"] = "font/ttf", ["otf"] = "font/otf",
            ["pdf"] = "application/pdf", ["xml"] = "application/xml",
            ["txt"] = "text/plain; charset=utf-8", ["md"] = "text/plain; charset=utf-8", ["csv"] = "text/csv; charset=utf-8",
            ["mp4"] = "video/mp4", ["m4v"] = "video/mp4", ["webm"] = "video/webm", ["mov"] = "video/quicktime",
            ["mp3"] = "audio/mpeg", ["m4a"] = "audio/mp4", ["wav"] = "audio/wav", ["ogg"] = "audio/ogg",
            ["ggb"] = "application/octet-stream",
        };

    /// <summary>The type a file of this name is served as.</summary>
    public static string TypeOf(string fileName)
    {
        int dot = fileName.LastIndexOf('.');
        if (dot < 0 || dot == fileName.Length - 1) return Unknown;
        return ByExtension.TryGetValue(fileName[(dot + 1)..], out var type) ? type : Unknown;
    }
}
