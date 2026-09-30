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
    public static bool NeedsRebuild(Course course, int sectionNumber, string buildsRoot)
    {
        // The BUILT SITE, where Windows actually keeps it. This used to read
        // <course>\.merged_output\section<N>\public\index.html — the place
        // builds lived before row 290 moved them out of the working folder —
        // and so it was reading a location this platform had stopped writing
        // to. Both answers were wrong: for a course made since the move the
        // file never exists, so it always said "rebuild" (safe, but every
        // publish rebuilt); for a course carrying a leftover .merged_output
        // it read THAT, and a leftover newer than the notes made it say "no
        // rebuild needed" about a file that is not what gets published.
        string builtIndex = BuildOutputLocation.BuiltIndexFor(buildsRoot, course.Code, sectionNumber);
        DateTime builtDate;
        try { builtDate = File.GetLastWriteTimeUtc(builtIndex); }
        catch { return true; }
        if (!File.Exists(builtIndex)) return true;

        // A preview's build is never deploy-fresh: serve mode bakes a
        // live-reload client pointed at ws://localhost into every page, and
        // publishing that makes browsers ask to "access other apps and
        // services on this device" on the live site. ANY page, not only the
        // front one (#272 / mac #136): the built tree is replaced file by
        // file, so a clean front page in front of a preview's pages is real.
        string publicDir = Path.GetDirectoryName(builtIndex)!;
        if (BuiltForPreview(publicDir)) return true;

        // The sixth rule (#272 / mac #265): compare with the START of the
        // build that made the site, not with when it finished. A build reads
        // the settings and pages when it starts and writes index.html minutes
        // later, so a Save made while a publish was building is OLDER than
        // index.html — compared with index.html alone the next Publish
        // resent the old site and said it had succeeded. The EARLIER of the
        // marker and index.html: an earlier time only ever costs a rebuild
        // that was not needed. No marker (a site built before it existed):
        // index.html, as before. build_site.py writes it natively here, so
        // one clock stamps both it and the teacher's Save.
        string marker = Path.Combine(Path.GetDirectoryName(publicDir)!, BuildStartedMarker);
        try
        {
            if (File.Exists(marker))
            {
                DateTime started = File.GetLastWriteTimeUtc(marker);
                if (started < builtDate) builtDate = started;
            }
        }
        catch { /* unreadable marker: index.html's time, as before */ }

        DateTime? contentDate = NewestContentDate(course.DirectoryPath);
        if (contentDate is null) return false;   // nothing readable: nothing to rebuild for
        return contentDate > builtDate;
    }

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

        IEnumerable<string> pages;
        try { pages = Directory.EnumerateFiles(publicDir, "*.html", SearchOption.AllDirectories); }
        catch { return false; }
        foreach (string page in pages)
        {
            if (!page.EndsWith(".html", StringComparison.Ordinal)) continue;
            if (string.Equals(page, index, StringComparison.OrdinalIgnoreCase)) continue;
            byte[] bytes;
            try { bytes = File.ReadAllBytes(page); }
            catch { continue; }
            if (CarriesTheClient(bytes)) return true;
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
