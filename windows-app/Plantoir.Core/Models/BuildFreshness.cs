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
        // services on this device" on the live site.
        if (BuiltForPreview(builtIndex)) return true;

        DateTime? contentDate = NewestContentDate(course.DirectoryPath);
        if (contentDate is null) return false;   // nothing readable: nothing to rebuild for
        return contentDate > builtDate;
    }

    /// <summary>True when the built page carries the preview server's live-reload client.</summary>
    internal static bool BuiltForPreview(string builtIndexPath)
    {
        try { return File.ReadAllText(builtIndexPath).Contains("ws://localhost:", StringComparison.Ordinal); }
        catch { return true; }   // unreadable: rebuild rather than trust it
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
