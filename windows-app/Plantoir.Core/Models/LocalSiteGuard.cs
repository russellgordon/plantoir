using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Models;

/// <summary>
/// The guard a local page view puts between its pages and the disk (#801's
/// Planning tab; #811's Coverage tab reuses it with its own root, host and file
/// types): which address is which file, whether a file is inside the one folder
/// the view may read once every link is followed, and — for each request the
/// view's own handler answers — the file itself, read from ONE handle.
/// </summary>
/// <remarks>
/// <para><b>The shape</b> (plan R2, adopted by the director; plan review L1,
/// L2). The view serves every request itself, at one fixed host whose URL PATH
/// is the file's absolute path, <c>https://plans.plantoir.invalid/C:/Users/…/planning/unit-1/index.html</c>,
/// each segment percent-encoded. No folder is mapped to the host. Under a
/// mapping the URL root would BE the planning folder and the URL standard
/// clamps <c>..</c> there, so <c>../../../course_config.json</c> from a unit's
/// page would come back inside the folder and five <c>navigationCases</c> would
/// answer load where the contract says refuse (measured by the plan review's
/// probe). With the path mirrored in the address, the web view's own
/// resolution IS the file's, and the walker hands this guard exactly the
/// address the web view reports.</para>
///
/// <para><b>Addresses are built from the NOMINAL path</b>, as the app holds it,
/// never from the real one: on a mapped network drive the real path is
/// <c>\\server\share\…</c>, which has no drive segment (L1.2). Real paths are
/// for <see cref="IsInside"/> only. A segment that decodes to <c>.</c>,
/// <c>..</c>, nothing, a separator, a colon (an alternate data stream, so
/// <c>index.html::$DATA</c>), a character Windows refuses in a name, a trailing
/// dot or space (Windows would strip it and read another file), or a reserved
/// device name is refused; the FIRST segment must be a drive, <c>C:</c>, the
/// one place a colon belongs (L1.1).</para>
///
/// <para><b>Real paths</b> come from <c>GetFinalPathNameByHandle</c> on the
/// longest part of the path that exists, which follows every junction and
/// symbolic link and expands 8.3 short names; the part not there yet is added
/// back as written. Never <see cref="FileAttributes.ReparsePoint"/> alone: a
/// OneDrive placeholder is a reparse point and not a link. Compared folder by
/// folder without regard to case, so <c>planning-old</c> is not inside
/// <c>planning</c>.</para>
///
/// <para><b>Serving reads ONE handle</b> (L2): the file is opened once, links
/// followed; THAT handle's real path is checked inside the root, its type must
/// be an ordinary disk file (not a folder, not a device: L1.3), and the bytes
/// are read from the same handle, so a junction swapped between the check and
/// the read changes nothing. Its type must be on the allowlist both as written
/// and as it resolves.</para>
///
/// <para><b>What it does not see</b>: a hard link to a file outside is the same
/// file, and no path check can tell (the mac has the same gap). The guard keeps
/// mistakes and links out, not a writer who can already copy any file in.</para>
/// </remarks>
public sealed class LocalSiteGuard
{
    /// <summary>The Planning tab's host. <c>.invalid</c> never resolves, so a request the handler misses goes nowhere.</summary>
    public const string PlansHost = "plans.plantoir.invalid";

    /// <summary>What a plan is made of, by extension, and the type each is served as. Anything else is refused.</summary>
    public static readonly IReadOnlyDictionary<string, string> PlanContentTypes =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            [".html"] = "text/html", [".htm"] = "text/html", [".css"] = "text/css",
            [".woff2"] = "font/woff2", [".woff"] = "font/woff", [".ttf"] = "font/ttf", [".otf"] = "font/otf",
            [".pdf"] = "application/pdf", [".png"] = "image/png", [".jpg"] = "image/jpeg", [".jpeg"] = "image/jpeg",
            [".gif"] = "image/gif", [".webp"] = "image/webp", [".svg"] = "image/svg+xml",
            [".txt"] = "text/plain", [".json"] = "application/json",
        };

    private readonly ILocalFiles _files;

    public LocalSiteGuard(string root, string host, IReadOnlyDictionary<string, string> contentTypes, ILocalFiles? files = null)
    {
        Root = Path.GetFullPath(root).TrimEnd('\\', '/');
        Host = host;
        ContentTypes = contentTypes;
        _files = files ?? WindowsLocalFiles.Instance;
    }

    /// <summary>The one folder the view may read, as the app names it.</summary>
    public string Root { get; }

    /// <summary>The host every page of the view is served at.</summary>
    public string Host { get; }

    /// <summary>The file types served, by extension.</summary>
    public IReadOnlyDictionary<string, string> ContentTypes { get; }

    /// <summary>The address the view loads for the root itself, ending in a slash.</summary>
    public string? RootAddress => AddressOf(Root, isFolder: true);

    // ---- Address and path, both ways -----------------------------------------

    /// <summary>
    /// The served address of <paramref name="path"/> (a full Windows path on a
    /// drive), each segment percent-encoded; null for a path this guard cannot
    /// name (a UNC path, or a segment <see cref="IsAcceptableSegment"/> refuses).
    /// </summary>
    public string? AddressOf(string path, bool isFolder = false)
    {
        var segments = SegmentsOf(Path.GetFullPath(path));
        if (segments is null) return null;
        var address = new StringBuilder("https://").Append(Host).Append('/').Append(segments[0]);
        for (int i = 1; i < segments.Count; i++) address.Append('/').Append(Uri.EscapeDataString(segments[i]));
        if (isFolder) address.Append('/');
        return address.ToString();
    }

    /// <summary>
    /// The nominal Windows path a served address names, or null when the
    /// address is not this guard's (another scheme, host, port or a user name)
    /// or a segment decodes to something a file name must not be. Each segment
    /// is decoded ONCE.
    /// </summary>
    public string? PathOf(string address)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme != Uri.UriSchemeHttps || !string.Equals(uri.Host, Host, StringComparison.OrdinalIgnoreCase)) return null;
        if (uri.UserInfo.Length > 0 || !uri.IsDefaultPort) return null;
        return PathFromUrlPath(uri.AbsolutePath);
    }

    /// <summary>
    /// The nominal Windows path a <c>file:</c> address names, or null: only
    /// this PC's own files, written with no host or as <c>localhost</c> (#803
    /// review L4), on a drive. Another host is refused WITHOUT asking the disk:
    /// a <c>file://server/share</c> touch is an SMB connection from the
    /// teacher's PC.
    /// </summary>
    public static string? PathOfFileAddress(string address)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeFile) return null;
        bool localhost = string.Equals(uri.Host, "localhost", StringComparison.OrdinalIgnoreCase);
        if (uri.Host.Length > 0 && !localhost) return null;
        // .NET reads file://localhost/… as a UNC address; it names this PC.
        if (uri.IsUnc && !localhost) return null;
        return PathFromUrlPath(uri.AbsolutePath);
    }

    private static string? PathFromUrlPath(string urlPath)
    {
        var raw = urlPath.Split('/');
        // "/C:/a/b" splits to "", "C:", "a", "b"; a trailing slash leaves one empty last part (a folder).
        if (raw.Length < 2 || raw[0].Length != 0) return null;
        int last = raw.Length - 1;
        if (raw[last].Length == 0 && last > 1) last--;
        var segments = new List<string>();
        for (int i = 1; i <= last; i++)
        {
            string decoded;
            try { decoded = Uri.UnescapeDataString(raw[i]); }
            catch { return null; }
            segments.Add(decoded);
        }
        if (!IsDrive(segments[0])) return null;
        for (int i = 1; i < segments.Count; i++)
            if (!IsAcceptableSegment(segments[i])) return null;
        return segments.Count == 1 ? segments[0] + "\\" : string.Join('\\', segments);
    }

    /// <summary>A full path's segments, the drive first; null for a UNC path or an unacceptable segment.</summary>
    private static List<string>? SegmentsOf(string fullPath)
    {
        if (fullPath.StartsWith(@"\\", StringComparison.Ordinal)) return null;
        var segments = fullPath.Split('\\', StringSplitOptions.RemoveEmptyEntries).ToList();
        if (segments.Count == 0 || !IsDrive(segments[0])) return null;
        for (int i = 1; i < segments.Count; i++)
            if (!IsAcceptableSegment(segments[i])) return null;
        return segments;
    }

    private static bool IsDrive(string segment) =>
        segment.Length == 2 && segment[1] == ':' && char.IsAsciiLetter(segment[0]);

    private static readonly HashSet<string> DeviceNames = new(StringComparer.OrdinalIgnoreCase)
    {
        // Microsoft's "Naming Files, Paths, and Namespaces" list, superscript
        // digits included, and COM0 and LPT0 besides (790a review L2): that
        // page names COM0 as a device link in the Win32 namespace though its
        // list starts at COM1, so both are refused here rather than trusted.
        "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$",
        "COM0", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "COM¹", "COM²", "COM³",
        "LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9", "LPT¹", "LPT²", "LPT³",
    };

    /// <summary>
    /// Whether a decoded segment can name a file in a folder here: not empty,
    /// not <c>.</c> or <c>..</c>, no separator, colon, control character or
    /// character Windows refuses, no trailing dot or space, and not a reserved
    /// device name (with or without an extension). The serve path also checks
    /// the opened handle is a disk file (L1.3), so this list is the second check.
    /// </summary>
    public static bool IsAcceptableSegment(string segment)
    {
        if (segment.Length == 0 || segment == "." || segment == "..") return false;
        foreach (char c in segment)
            if (c < 0x20 || c == 0x7F || "\\/:*?\"<>|".IndexOf(c) >= 0) return false;
        if (segment[^1] == '.' || segment[^1] == ' ') return false;
        int dot = segment.IndexOf('.');
        string stem = (dot < 0 ? segment : segment[..dot]).TrimEnd(' ');
        return !DeviceNames.Contains(stem);
    }

    // ---- Inside ----------------------------------------------------------------

    /// <summary>
    /// <paramref name="path"/> with every link followed for the part of it that
    /// exists (<c>GetFinalPathNameByHandle</c>); the rest, a file not there yet,
    /// is added back as written.
    /// </summary>
    public string RealPath(string path)
    {
        string full = Path.GetFullPath(path).TrimEnd('\\');
        // The root's own backslash is put back: "C:" alone is the drive's
        // CURRENT folder to Windows, never its root.
        if (full.Length == 2 && full[1] == ':') full += "\\";
        var missing = new Stack<string>();
        string? existing = full;
        while (existing is not null)
        {
            if (_files.FinalPath(existing) is { } real)
            {
                var result = new StringBuilder(real.TrimEnd('\\'));
                foreach (string part in missing) result.Append('\\').Append(part);
                return result.Length == 2 && result[1] == ':' ? result.Append('\\').ToString() : result.ToString();
            }
            string? parent = Path.GetDirectoryName(existing);
            if (parent is null || parent.Length == 0 || parent == existing) break;
            missing.Push(Path.GetFileName(existing));
            existing = parent.TrimEnd('\\');
            if (existing.Length == 2 && existing[1] == ':') { existing += "\\"; }
        }
        return full;
    }

    /// <summary>
    /// Whether <paramref name="path"/> is the root or something in it once
    /// <c>..</c> is taken out and every link on the way is followed, compared
    /// folder by folder without regard to case. False while the root does not
    /// exist (the guard refuses everything until it does; #811 review L9: the
    /// root is resolved again at every call, so a folder made after the view
    /// opened is seen).
    /// </summary>
    public bool IsInside(string path)
    {
        if (_files.FinalPath(Root) is not { } realRoot) return false;
        return IsWithin(RealPath(path), realRoot);
    }

    /// <summary>Whether a served address names a path inside the root.</summary>
    public bool IsInsideAddress(string address) => PathOf(address) is { } path && IsInside(path);

    /// <summary>The kind of entry at <paramref name="path"/> once links are followed: null when nothing is there.</summary>
    public bool? IsFolder(string path) => _files.FinalPath(path) is { } real ? _files.IsFolder(real) : null;

    internal static bool IsWithin(string target, string root)
    {
        var t = target.Split('\\', StringSplitOptions.RemoveEmptyEntries);
        var r = root.Split('\\', StringSplitOptions.RemoveEmptyEntries);
        if (t.Length < r.Length) return false;
        for (int i = 0; i < r.Length; i++)
            if (!string.Equals(t[i], r[i], StringComparison.OrdinalIgnoreCase)) return false;
        return true;
    }

    // ---- Serving ---------------------------------------------------------------

    /// <summary>What the view's request handler answers.</summary>
    public abstract record Verdict
    {
        /// <summary>Serve these bytes, as this type. The stream is the one handle the checks were made on.</summary>
        public sealed record Serve(Stream Content, string ContentType, string RealPath) : Verdict;

        /// <summary>Answer with a refusal and nothing else; <see cref="Why"/> is for a test, never a teacher.</summary>
        public sealed record Refuse(string Why) : Verdict;
    }

    /// <summary>
    /// The answer to one request: the file it names, opened once, when that
    /// handle is an ordinary disk file inside the root of an allowed type as
    /// written and as it resolves; otherwise a refusal. Never throws.
    /// </summary>
    public Verdict Answer(string address)
    {
        if (PathOf(address) is not { } path) return new Verdict.Refuse("not this view's address");
        if (!ContentTypes.TryGetValue(Path.GetExtension(path), out var contentType)) return new Verdict.Refuse("not a type this view serves");
        if (_files.FinalPath(Root) is not { } realRoot) return new Verdict.Refuse("the folder is not there");
        LocalFile? file;
        try { file = _files.Open(path); }
        catch { file = null; }
        if (file is null) return new Verdict.Refuse("nothing to read there");
        if (!file.IsDiskFile) { file.Content.Dispose(); return new Verdict.Refuse("not an ordinary file"); }
        if (!IsWithin(file.RealPath, realRoot)) { file.Content.Dispose(); return new Verdict.Refuse("outside the folder"); }
        if (!ContentTypes.ContainsKey(Path.GetExtension(file.RealPath))) { file.Content.Dispose(); return new Verdict.Refuse("leads to a type this view does not serve"); }
        return new Verdict.Serve(file.Content, contentType, file.RealPath);
    }
}

/// <summary>One file opened for reading: its bytes, the real path of the SAME handle, and whether it is an ordinary disk file.</summary>
public sealed record LocalFile(Stream Content, string RealPath, bool IsDiskFile);

/// <summary>
/// What <see cref="LocalSiteGuard"/> asks of the disk, as a seam: the real
/// disk (<see cref="WindowsLocalFiles"/>), or a test's map of files and links,
/// so a contract case whose links this PC cannot make (a FILE symbolic link
/// needs Developer Mode or an administrator) still runs, and a test can count
/// that a <c>file://server</c> address never asks at all.
/// </summary>
public interface ILocalFiles
{
    /// <summary>The real path of what is at <paramref name="path"/>, every link followed, or null when nothing can be opened there.</summary>
    string? FinalPath(string path);

    /// <summary>Whether the real path names a folder.</summary>
    bool IsFolder(string realPath);

    /// <summary>The file at <paramref name="path"/>, opened ONCE with links followed, or null.</summary>
    LocalFile? Open(string path);
}

/// <summary>The disk, through one handle per question (<c>CreateFileW</c> and <c>GetFinalPathNameByHandleW</c>).</summary>
public sealed class WindowsLocalFiles : ILocalFiles
{
    public static readonly WindowsLocalFiles Instance = new();

    public string? FinalPath(string path)
    {
        try
        {
            using var handle = CreateFileW(Extended(path), 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                           nint.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nint.Zero);
            return handle.IsInvalid ? null : FinalPathOf(handle);
        }
        catch (Exception e) when (e is Win32Exception or IOException or ArgumentException) { return null; }
    }

    public bool IsFolder(string realPath) => Directory.Exists(realPath);

    public LocalFile? Open(string path)
    {
        // BACKUP_SEMANTICS so a folder opens too, and is then refused by its
        // attributes rather than failing for a reason nobody can read.
        var handle = CreateFileW(Extended(path), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                 nint.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nint.Zero);
        if (handle.IsInvalid) { handle.Dispose(); return null; }
        string? real = FinalPathOf(handle);
        bool disk = GetFileType(handle) == FILE_TYPE_DISK
                    && GetFileInformationByHandle(handle, out var information)
                    && (information.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
        if (real is null || !disk)
        {
            handle.Dispose();
            return real is null ? null : new LocalFile(Stream.Null, real, false);
        }
        return new LocalFile(new FileStream(handle, FileAccess.Read), real, true);
    }

    /// <summary>
    /// <paramref name="path"/> made full and given the <c>\\?\</c> prefix
    /// (<c>\\?\UNC\</c> for a share), so <c>CreateFileW</c> opens a path longer
    /// than MAX_PATH (790a review L1: a 324-character page inside the root was
    /// refused as "nothing to read there"; the app's manifest declares no
    /// long-path awareness, and that would also need the machine's registry
    /// switch). The prefix turns Windows' own name parsing off, so
    /// <see cref="Path.GetFullPath(string)"/> takes out <c>.</c> and <c>..</c>
    /// first; what the prefix would otherwise let through (a trailing dot or
    /// space, a device name) <see cref="LocalSiteGuard.IsAcceptableSegment"/>
    /// has already refused in any served address. A path already in a
    /// <c>\\?\</c> or <c>\\.\</c> form is passed as it is.
    /// </summary>
    internal static string Extended(string path)
    {
        if (path.StartsWith(@"\\?\", StringComparison.Ordinal) || path.StartsWith(@"\\.\", StringComparison.Ordinal)) return path;
        string full = Path.GetFullPath(path);
        if (full.StartsWith(@"\\?\", StringComparison.Ordinal) || full.StartsWith(@"\\.\", StringComparison.Ordinal)) return full;
        return full.StartsWith(@"\\", StringComparison.Ordinal) ? @"\\?\UNC\" + full[2..] : @"\\?\" + full;
    }

    private static string? FinalPathOf(SafeFileHandle handle)
    {
        var buffer = new StringBuilder(4096);
        uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
        if (length == 0 || length >= buffer.Capacity) return null;
        string result = buffer.ToString();
        if (result.StartsWith(@"\\?\UNC\", StringComparison.Ordinal)) return @"\\" + result[8..];
        if (result.StartsWith(@"\\?\", StringComparison.Ordinal)) return result[4..];
        return result;
    }

    private const uint GENERIC_READ = 0x80000000;
    private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, FILE_SHARE_DELETE = 4;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const uint FILE_TYPE_DISK = 1;
    private const uint FILE_ATTRIBUTE_DIRECTORY = 0x10;

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct ByHandleFileInformation
    {
        public uint FileAttributes;
        public long CreationTime, LastAccessTime, LastWriteTime;
        public uint VolumeSerialNumber, FileSizeHigh, FileSizeLow, NumberOfLinks, FileIndexHigh, FileIndexLow;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        nint lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, nint hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle hFile, StringBuilder lpszFilePath,
        uint cchFilePath, uint dwFlags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint GetFileType(SafeFileHandle hFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle hFile, out ByHandleFileInformation information);
}
