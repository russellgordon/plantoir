namespace Plantoir.Core.Models;

/// <summary>
/// Decides whether Deploy must rebuild first: publish only what reflects
/// the current content.
/// </summary>
public static class BuildFreshness
{
    /// <param name="buildsRoot">
    /// Where this working folder's built websites are kept —
    /// <see cref="BuildOutputLocation.BuildsRootFor"/>. Passed in rather than
    /// derived so that a test can point it at a temporary directory.
    /// </param>
    public static bool NeedsRebuild(Course course, int sectionNumber, string buildsRoot) =>
        WhyRebuild(course, sectionNumber, buildsRoot) is not null;

    // The reasons, as contracts/app-rules.json -> buildFreshness.
    // reuseTheLastBuild.reasons and the trail's whyWords name them. The app
    // never answers `toolchain` (it does not read the stamp: builtWithToolchain.
    // note) or `address` (deploy.py's own question).
    public const string ReasonNeverBuilt = "neverBuilt";
    public const string ReasonFrontPageUnreadable = "frontPageUnreadable";
    public const string ReasonPreview = "preview";
    public const string ReasonClock = "clock";
    public const string ReasonPages = "pages";

    /// <summary>
    /// WHY Deploy must build the section's site first, or null to deploy the
    /// last build as it stands (#799, the mac's #768:
    /// <c>buildFreshness.reuseTheLastBuild</c>). In this order: no front page
    /// (<c>neverBuilt</c>), a front page that cannot be read, a preview's site
    /// (asked BEFORE the times, as every reader asks it), the build dated
    /// later than now (<c>clock</c>), then anything in the course changed
    /// after the build that made the site STARTED (<c>pages</c>).
    /// </summary>
    /// <param name="nowUtc">The clock guard's "now"; the real clock when null.</param>
    public static string? WhyRebuild(Course course, int sectionNumber, string buildsRoot, DateTime? nowUtc = null) =>
        WhyRebuild(course.DirectoryPath, BuildOutputLocation.ForSection(buildsRoot, course.Code, sectionNumber), nowUtc);

    /// <summary>The same question about a course folder and a section's
    /// built folder (the one holding <c>public\</c>), for the case runner.</summary>
    internal static string? WhyRebuild(string courseDirectory, string sectionDirectory, DateTime? nowUtc = null)
    {
        // The BUILT SITE, where Windows actually keeps it (row 290 moved it out
        // of the working folder; until 2026-09-06 this read the old place).
        string publicDir = Path.Combine(sectionDirectory, "public");
        string builtIndex = Path.Combine(publicDir, "index.html");
        if (!File.Exists(builtIndex)) return ReasonNeverBuilt;
        DateTime builtDate;
        try
        {
            builtDate = File.GetLastWriteTimeUtc(builtIndex);
            using var opened = new FileStream(builtIndex, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        }
        catch { return ReasonFrontPageUnreadable; }

        // A preview's build is never deploy-fresh: serve mode bakes a
        // live-reload client pointed at ws://localhost into every page, and
        // publishing that makes browsers ask to "access other apps and
        // services on this device" on the live site. ANY page, not only the
        // front one (#272 / mac #136). Asked before the times, as every reader
        // asks it since the #768 review's M1: a preview never stamps its site.
        if (BuiltForPreview(publicDir)) return ReasonPreview;

        // Compare with the START of the build that made the site (#272 / mac
        // #265): a Save made while a deploy was building is older than
        // index.html. The EARLIER of the marker and index.html: an earlier
        // time only ever costs a rebuild that was not needed. No marker (a
        // site built before it existed): index.html, as before.
        string marker = Path.Combine(sectionDirectory, BuildStartedMarker);
        try
        {
            if (File.Exists(marker))
            {
                DateTime started = File.GetLastWriteTimeUtc(marker);
                if (started < builtDate) builtDate = started;
            }
        }
        catch { /* unreadable marker: index.html's time, as before */ }

        return ChangedSince(courseDirectory, builtDate, nowUtc ?? DateTime.UtcNow);
    }

    /// <summary>
    /// The pages and clock half of the rule, on its own: <c>clock</c> when
    /// <paramref name="referenceUtc"/> is later than <paramref name="nowUtc"/>
    /// (a build dated ahead would hide every change made since behind its
    /// date; <c>knownLimits</c> says when the guard stops firing), <c>pages</c>
    /// when the course folder or anything in it not hidden by its name changed
    /// after the reference (<see cref="SomethingInTheCourseIsNewer"/>), else
    /// null. The ONE walk: <see cref="WhyRebuild(string, string, DateTime?)"/>
    /// calls it, and so can any other reader that needs "has the course
    /// changed since this time" (the Coverage tab, #811).
    /// </summary>
    public static string? ChangedSince(string courseDirectory, DateTime referenceUtc, DateTime nowUtc)
    {
        if (referenceUtc > nowUtc) return ReasonClock;
        if (SomethingInTheCourseIsNewer(courseDirectory, referenceUtc)) return ReasonPages;
        return null;
    }

    /// <summary>
    /// True when the course folder itself, or any entry under it whose NAME
    /// does not start with ".", was modified or created strictly after
    /// <paramref name="referenceUtc"/>; stops at the first one. The shared
    /// Python's <c>something_in_the_course_is_newer</c>, entry for entry:
    /// <list type="bullet">
    /// <item>The later of each entry's last-write time and its CREATION time.
    /// The creation time stands in for the change time, deliberately: a build
    /// hard-links the course's Media into its build folder, which changes each
    /// picture's change time, so reading that would make every deploy build
    /// (<c>rejected</c>). A copy that keeps its old modification time is new
    /// here, so its creation time is now.</item>
    /// <item>Folders as well as files, and the course folder's own time: only
    /// a folder's time shows a page deleted or renamed (#741).</item>
    /// <item>Hidden is judged by the NAME, never by Windows' hidden attribute:
    /// the enumeration skips no attribute (a default
    /// <see cref="EnumerationOptions"/> skips Hidden and System, the #272
    /// trap).</item>
    /// <item>A course folder that is a junction or a link is read THROUGH it,
    /// and the link's OWN times count too, so pointing it at an older copy
    /// builds (<c>os.stat</c> and <c>os.lstat</c> in the Python).</item>
    /// <item>A junction INSIDE the course is followed, as the Python's
    /// <c>os.walk</c> follows one (measured, the #799 plan review's L2); a
    /// symbolic link is not, as <c>os.walk</c> does not. A folder already
    /// walked through a junction is not walked again, so a junction that
    /// leads back into the course ends.</item>
    /// </list>
    /// Times are read from each entry's own record (<see cref="FileSystemInfo.Refresh"/>,
    /// one GetFileAttributesEx), not the directory listing's copy, which can
    /// lag behind a file still held open for writing; a lag is the stale
    /// direction. A folder that cannot be LISTED, the course folder included,
    /// counts as changed (#799's review, L2): passing it over would deploy the
    /// last build's copy of it. The shared Python passes such a folder over (a
    /// known limit, in 05). A course folder whose own times cannot be read, or
    /// that does not exist, answers "nothing newer", as the Python does.
    /// </summary>
    internal static bool SomethingInTheCourseIsNewer(string courseDirectory, DateTime referenceUtc)
    {
        // The link's own times (for a real folder, the folder's).
        DirectoryInfo course;
        try
        {
            course = new DirectoryInfo(courseDirectory);
            if (!course.Exists) return false;
            if (LaterOf(course) > referenceUtc) return true;
        }
        catch { return false; }

        // And, for a link, the times of the folder it leads to.
        string root = courseDirectory;
        if (course.Attributes.HasFlag(FileAttributes.ReparsePoint))
        {
            try
            {
                if (course.ResolveLinkTarget(returnFinalTarget: true) is DirectoryInfo target)
                {
                    if (LaterOf(target) > referenceUtc) return true;
                    root = target.FullName;
                }
            }
            catch { /* walked through the link's own path below */ }
        }

        var walked = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Path.GetFullPath(root).TrimEnd('\\') };
        var pending = new Stack<(string Folder, int Depth)>();
        pending.Push((root, 0));
        while (pending.Count > 0)
        {
            var (folder, depth) = pending.Pop();
            IEnumerable<FileSystemInfo> entries;
            // A folder that cannot be LISTED counts as changed (#799's review, L2):
            // nobody can say what is in it, and passing it over would deploy the
            // last build's copy of it. Building is the safe direction. (The shared
            // Python's os.walk passes such a folder over: a known limit, in 05.)
            try { entries = new DirectoryInfo(folder).EnumerateFileSystemInfos("*", EveryEntry); }
            catch { return true; }
            try
            {
                foreach (var entry in entries)
                {
                    if (entry.Name.StartsWith('.')) continue;
                    try
                    {
                        entry.Refresh();
                        if (LaterOf(entry) > referenceUtc) return true;
                    }
                    catch { continue; }
                    if (entry is not DirectoryInfo directory) continue;
                    if (depth >= MostFoldersDeep) continue;
                    if (directory.Attributes.HasFlag(FileAttributes.ReparsePoint))
                    {
                        // os.walk goes into a junction and not into a symbolic link.
                        if (ReparseTagOf(directory.FullName) == SymbolicLinkTag) continue;
                        string leadsTo;
                        try { leadsTo = (directory.ResolveLinkTarget(returnFinalTarget: true)?.FullName ?? directory.FullName).TrimEnd('\\'); }
                        catch { continue; }
                        if (!walked.Add(leadsTo)) continue;
                    }
                    pending.Push((directory.FullName, depth + 1));
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
            {
                // A folder that cannot be listed, or stops being listable part-way:
                // what is in it is unknown, so it counts as changed (above).
                return true;
            }
        }
        return false;
    }

    /// <summary>A belt beside the junction set: no course is this deep.</summary>
    private const int MostFoldersDeep = 128;

    private static readonly EnumerationOptions EveryEntry = new()
    {
        AttributesToSkip = 0,
        // false: a folder that cannot be listed must THROW, so it counts as changed.
        IgnoreInaccessible = false,
        RecurseSubdirectories = false,
        ReturnSpecialDirectories = false,
    };

    private static DateTime LaterOf(FileSystemInfo entry)
    {
        DateTime written = entry.LastWriteTimeUtc;
        DateTime created = entry.CreationTimeUtc;
        return created > written ? created : written;
    }

    private const uint SymbolicLinkTag = 0xA000000C;

    /// <summary>The reparse tag of a link (FindFirstFile's dwReserved0), or 0.</summary>
    private static uint ReparseTagOf(string path)
    {
        if (!OperatingSystem.IsWindows()) return 0;
        IntPtr handle = FindFirstFileW(path, out var data);
        if (handle == new IntPtr(-1)) return 0;
        FindClose(handle);
        return (data.dwFileAttributes & 0x400) != 0 ? data.dwReserved0 : 0;
    }

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private struct Win32FindData
    {
        public uint dwFileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftCreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftLastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftLastWriteTime;
        public uint nFileSizeHigh;
        public uint nFileSizeLow;
        public uint dwReserved0;
        public uint dwReserved1;
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst = 260)]
        public string cFileName;
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst = 14)]
        public string cAlternateFileName;
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindFirstFileW(string fileName, out Win32FindData data);

    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    private static extern bool FindClose(IntPtr handle);

    /// <summary><c>app-rules.json → buildFreshness.buildStartedMarker.file</c>, beside <c>public\</c>.</summary>
    public const string BuildStartedMarker = ".build-started";

    // app-rules.json -> buildFreshness.previewBuild.signature: the client's
    // script TAG, any run of the `between` bytes (POSIX [[:space:]] in the C
    // locale: space, tab, LF, VT, FF, CR — never .NET's Unicode whitespace),
    // then its first statement. As BYTES, ordinal: a page that merely
    // MENTIONS ws://localhost: (a networking lesson) is not a preview's (#291).
    private static readonly byte[] ScriptTag = System.Text.Encoding.ASCII.GetBytes("<script type=\"application/javascript\">");
    private static readonly byte[] Client = System.Text.Encoding.ASCII.GetBytes("const socket = new WebSocket('ws://localhost:");
    private static bool IsBetweenByte(byte b) => b is (byte)' ' or (byte)'\t' or (byte)'\n' or 0x0B or 0x0C or (byte)'\r';

    /// <summary>
    /// True when ANY page of the built site carries the preview server's
    /// live-reload client — <c>previewBuild</c>, the rule every checker reads.
    /// <c>index.html</c> first (unreadable or missing: rebuild, the safe
    /// direction), then every file ending <c>.html</c> under
    /// <paramref name="publicDir"/>, hidden (dot) folders included — the
    /// <c>SearchOption</c> overload does not skip Hidden or System items the way
    /// a default <c>EnumerationOptions</c> would. A page that cannot be opened
    /// is PASSED OVER, as every other reader does.
    /// </summary>
    internal static bool BuiltForPreview(string publicDir)
    {
        string index = Path.Combine(publicDir, "index.html");
        try
        {
            if (CarriesTheClient(File.ReadAllBytes(index))) return true;
        }
        catch { return true; }   // the built index cannot be read: rebuild rather than trust it

        // A page that cannot be OPENED is passed over (the contract's
        // `unreadable` cases). A FOLDER that cannot be listed is different:
        // the enumeration throws from inside the loop (MoveNext), and the
        // pages beneath it were never looked at, so nobody can say they are
        // not a preview's. That answers "rebuild" — the safe direction, as an
        // unreadable front page does — rather than escaping NeedsRebuild and
        // failing the Deploy with an error (bundle 4 review L2).
        try
        {
            foreach (string page in Directory.EnumerateFiles(publicDir, "*.html", SearchOption.AllDirectories))
            {
                if (!page.EndsWith(".html", StringComparison.Ordinal)) continue;
                if (string.Equals(page, index, StringComparison.OrdinalIgnoreCase)) continue;
                byte[] bytes;
                try { bytes = File.ReadAllBytes(page); }
                catch { continue; }
                if (CarriesTheClient(bytes)) return true;
            }
        }
        catch (Exception error) when (error is UnauthorizedAccessException or IOException or System.Security.SecurityException)
        {
            return true;
        }
        return false;
    }

    /// <summary>
    /// Every occurrence of the tag is tried, and the bytes after it must be
    /// only <c>between</c> bytes and then the client — "the tag is present AND
    /// the client is present" fails case 10, a production page holding the
    /// same tag for Quartz's own inline script.
    /// </summary>
    internal static bool CarriesTheClient(ReadOnlySpan<byte> page)
    {
        int from = 0;
        while (from < page.Length)
        {
            int at = page[from..].IndexOf(ScriptTag);
            if (at < 0) return false;
            int cursor = from + at + ScriptTag.Length;
            while (cursor < page.Length && IsBetweenByte(page[cursor])) cursor++;
            if (page[cursor..].StartsWith(Client)) return true;
            from = from + at + 1;
        }
        return false;
    }

    /// <summary>
    /// Newest change anywhere in the course, skipping dot-prefixed entries at
    /// every level — which excludes the generated .merged_output, the
    /// .netlify_sites markers, and Obsidian's .obsidian settings. (On Windows
    /// "hidden" means a leading dot, not the file attribute.)
    /// </summary>
    internal static DateTime? NewestContentDate(string root)
    {
        DateTime? newest = null;
        void Visit(string dir)
        {
            IEnumerable<string> entries;
            try { entries = Directory.EnumerateFileSystemEntries(dir); }
            catch { return; }
            foreach (string entry in entries)
            {
                string name = Path.GetFileName(entry);
                if (name.StartsWith('.')) continue;
                DateTime stamp;
                try { stamp = File.GetLastWriteTimeUtc(entry); }
                catch { continue; }
                if (newest is null || stamp > newest) newest = stamp;
                if (Directory.Exists(entry)) Visit(entry);
            }
        }
        Visit(root);
        return newest;
    }
}
