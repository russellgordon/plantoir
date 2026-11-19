using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Shared by the guarded local page views' tests (the Planning tab's here;
/// the Coverage tab's, #811, is meant to reuse them rather than copy them):
/// a map of files and links standing in for the disk, a counter of what the
/// guard asked, and the translation from a contract's written address to the
/// address the web view would report.
/// </summary>
internal static class LocalSiteFixtures
{
    /// <summary>
    /// A contract case's written address as the web view would report it: an
    /// address with its own scheme as it is (with <c>{planning}</c> standing
    /// for the root's absolute path, written as a URL path, <c>/C:/…</c>), or a
    /// path resolved against <paramref name="baseAddress"/> as a browser
    /// resolves it (<c>..</c> taken out by the URL parser, as WebView2 does).
    /// </summary>
    public static string? Address(string? written, LocalSiteGuard guard, string baseAddress)
    {
        if (written is null) return null;
        string rootPath = guard.AddressOf(guard.Root)!["https://".Length..];
        rootPath = rootPath[rootPath.IndexOf('/')..];
        string text = written.Replace("{planning}", rootPath);
        if (Uri.TryCreate(text, UriKind.Absolute, out var absolute) && absolute.Scheme.Length > 1) return absolute.AbsoluteUri;
        return new Uri(new Uri(baseAddress), text).AbsoluteUri;
    }

    /// <summary>
    /// A disk made of named files and folders and LINKS, each link's target
    /// written as the contract writes it (read from the link's own folder).
    /// What <see cref="LocalSiteGuard"/> asks is answered by following the
    /// links by hand, so a case whose link this PC cannot make (a FILE symbolic
    /// link: WinError 1314 for this account) still runs. Nothing touches the
    /// real disk; <see cref="Calls"/> counts every question.
    /// </summary>
    public sealed class LinkMap : ILocalFiles
    {
        private readonly HashSet<string> _files = new(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> _folders = new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, string> _links = new(StringComparer.OrdinalIgnoreCase);

        public int Calls { get; private set; }

        public LinkMap File(string path) { _files.Add(Path.GetFullPath(path)); return this; }

        public LinkMap Folder(string path) { _folders.Add(Path.GetFullPath(path).TrimEnd('\\')); return this; }

        public LinkMap Link(string path, string target) { _links[Path.GetFullPath(path).TrimEnd('\\')] = target; return this; }

        /// <summary>Where a path really is once every link on the way is followed.</summary>
        public string Resolve(string path)
        {
            string current = Path.GetFullPath(path).TrimEnd('\\');
            for (int hops = 0; hops < 40; hops++)
            {
                var parts = current.Split('\\');
                bool followed = false;
                for (int i = 2; i <= parts.Length; i++)
                {
                    string prefix = string.Join('\\', parts.Take(i));
                    if (!_links.TryGetValue(prefix, out var target)) continue;
                    string landed = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(prefix)!, target.Replace('/', '\\')));
                    current = Path.Combine(new[] { landed }.Concat(parts.Skip(i)).ToArray()).TrimEnd('\\');
                    followed = true;
                    break;
                }
                if (!followed) return current;
            }
            return current;
        }

        private bool Exists(string real) =>
            _files.Contains(real) || _folders.Contains(real) || (real.Length == 2 && real[1] == ':')
            || _files.Concat(_folders).Any(entry => entry.StartsWith(real + "\\", StringComparison.OrdinalIgnoreCase));

        public string? FinalPath(string path)
        {
            Calls++;
            string real = Resolve(path);
            return Exists(real) ? (real.Length == 2 ? real + "\\" : real) : null;
        }

        public bool IsFolder(string realPath)
        {
            Calls++;
            return !_files.Contains(realPath.TrimEnd('\\'));
        }

        public LocalFile? Open(string path)
        {
            Calls++;
            string real = Resolve(path);
            if (_files.Contains(real)) return new LocalFile(new MemoryStream("made"u8.ToArray()), real, true);
            return Exists(real) ? new LocalFile(Stream.Null, real, false) : null;
        }

        public IReadOnlyList<string>? List(string path)
        {
            Calls++;
            string real = Resolve(path);
            if (_files.Contains(real) || !Exists(real)) return null;
            var names = new List<string>();
            foreach (string entry in _files.Concat(_folders).Concat(_links.Keys))
            {
                if (!entry.StartsWith(real + "\\", StringComparison.OrdinalIgnoreCase)) continue;
                string name = entry[(real.Length + 1)..].Split('\\')[0];
                if (!names.Contains(name, StringComparer.OrdinalIgnoreCase)) names.Add(name);
            }
            return names;
        }
    }

    /// <summary>The real disk, with every question counted.</summary>
    public sealed class CountingDisk : ILocalFiles
    {
        public int Calls { get; private set; }

        public string? FinalPath(string path) { Calls++; return WindowsLocalFiles.Instance.FinalPath(path); }

        public bool IsFolder(string realPath) { Calls++; return WindowsLocalFiles.Instance.IsFolder(realPath); }

        public LocalFile? Open(string path) { Calls++; return WindowsLocalFiles.Instance.Open(path); }

        public IReadOnlyList<string>? List(string path) { Calls++; return WindowsLocalFiles.Instance.List(path); }
    }

    /// <summary>
    /// Makes a link on the real disk: a JUNCTION for a folder (always possible
    /// here), a symbolic link for a file when this account may make one.
    /// False when it could not, so the caller reports the case by name.
    /// </summary>
    public static bool CanMakeFileLinks => FileLinks.Value;

    /// <summary>
    /// Whether this account may make a FILE symbolic link, asked once by
    /// making one in a temporary folder (WinError 1314 without Developer Mode
    /// or an administrator; measured on this PC).
    /// </summary>
    private static readonly Lazy<bool> FileLinks = new(() =>
    {
        string folder = Directory.CreateTempSubdirectory("plantoir-filelink-probe").FullName;
        try
        {
            File.WriteAllText(Path.Combine(folder, "target.txt"), "x");
            System.IO.File.CreateSymbolicLink(Path.Combine(folder, "link.txt"), "target.txt");
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return false; }
        finally { try { Directory.Delete(folder, recursive: true); } catch { } }
    });

    public static bool MakeLink(string link, string target, bool targetIsFolder)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(link)!);
        string absolute = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(link)!, target.Replace('/', '\\')));
        if (targetIsFolder)
        {
            Directory.CreateDirectory(absolute);
            ReferenceFixtures.Junction(link, absolute);
            return true;
        }
        try
        {
            System.IO.File.CreateSymbolicLink(link, target.Replace('/', '\\'));
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return false; }
    }
}

/// <summary>
/// A fact that needs a FILE symbolic link on disk: SKIPPED, with the cases it
/// would run named in the reason, when this account cannot make one, so the
/// totals line counts it as not run rather than as passed (790a review 2, L9).
/// </summary>
public sealed class FileLinkFactAttribute : Xunit.FactAttribute
{
    public FileLinkFactAttribute()
    {
        if (!LocalSiteFixtures.CanMakeFileLinks)
            Skip = "This account cannot make a file symbolic link (WinError 1314: Developer Mode is off), so the three openInBrowser "
                 + "cases that link a FILE run against the link map only: 'a shortcut inside the plan that leads out of it', "
                 + "'a shortcut inside the plan that stays in it', 'a link named like a page that leads to a script'.";
    }
}