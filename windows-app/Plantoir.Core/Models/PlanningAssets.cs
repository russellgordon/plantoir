namespace Plantoir.Core.Models;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>unitPlanning.tab.assetsMirror</c>
/// (#801 item 4): each time the Planning tab looks again, before the page
/// loads, <c>&lt;planning folder&gt;\assets</c> is made the same as the
/// template's <c>assets</c> in the app's own copy of
/// <c>support\agent_guidance</c> — changed files copied, missing ones added,
/// extra ones removed — so the tab shows the look this release ships whatever
/// release the assistant copied it from. Sharing (#824) refreshes the same
/// folder from the same bytes, through this same call.
/// </summary>
/// <remarks>
/// <para><b>Never through a link.</b> The mirror removes extra files, so through
/// a junction or a symbolic link it would remove them from a folder that is not
/// the plan's (708 implementation review L2, measured on the mac). The mac
/// refuses when the planning folder or its <c>assets</c> is a link. Windows
/// refuses for more, because .NET's <c>EnumerateFiles(AllDirectories)</c>,
/// which <see cref="ToolchainMirror.SyncDirectory"/> uses on both sides, DOES
/// walk through a junction (790 plan review, new finding a): when
/// <c>.internal</c>, <c>planning</c>, <c>assets</c>, or ANY entry under
/// <c>assets</c> (a folder or a file) is a link, nothing is touched. A link is
/// <see cref="FileSystemInfo.LinkTarget"/> not null, never the reparse-point
/// attribute alone: a OneDrive placeholder carries that attribute and is not a
/// link.</para>
///
/// <para>Only when the planning folder already exists: opening the tab never
/// makes one (an empty folder would then be backed up for nothing).</para>
/// </remarks>
public static class PlanningAssets
{
    /// <summary>The plan's own stylesheets' folder, beside the units.</summary>
    public const string FolderName = "assets";

    /// <summary>Where the template's assets are inside <c>support\agent_guidance</c>.</summary>
    public static readonly string TemplateAssetsUnderGuidance =
        Path.Combine("skills", "plantoir-unit-planning", "template", "assets");

    /// <summary>What a refresh did: how many files it copied or removed, and how many it could not.</summary>
    public readonly record struct Outcome(int Changed, int Failed);

    /// <summary>The template's assets inside an app's <c>Toolchain</c> folder (its bundled copy of the recipe).</summary>
    public static string BundledTemplateAssets(string bundledToolchainRoot) =>
        Path.Combine(bundledToolchainRoot, "support", "agent_guidance", TemplateAssetsUnderGuidance);

    /// <summary>
    /// Mirrors <paramref name="bundledAssets"/> into the planning folder's
    /// <c>assets</c>. Null when nothing was done: no planning folder, the
    /// bundled assets missing, or a link on the way (see the remarks). Never throws.
    /// </summary>
    public static Outcome? Refresh(string planningFolder, string bundledAssets)
    {
        try
        {
            if (WhyNot(planningFolder, bundledAssets) is not null) return null;
            return Mirror(bundledAssets, Path.Combine(planningFolder, FolderName));
        }
        catch { return null; }
    }

    /// <summary>Why <see cref="Refresh"/> would do nothing, or null when it would mirror.</summary>
    public enum Refusal { NoPlanningFolder, NoTemplate, ALink }

    /// <summary>
    /// Why a refresh would do nothing (see the remarks), or null when it would
    /// mirror. The link checks come before any "is it there": a DANGLING
    /// junction at <c>assets</c> (its target deleted) is not a folder to
    /// <see cref="Directory.Exists(string)"/>, so asking that first let it
    /// through to the mirror, saved only by something throwing (790a review 2,
    /// L6). A refusal is the caller's to tell apart from a failed copy, which
    /// is what the contract's <c>couldNotRefreshTheLookLine</c> records.
    /// </summary>
    public static Refusal? WhyNot(string planningFolder, string bundledAssets)
    {
        if (!Directory.Exists(planningFolder)) return Refusal.NoPlanningFolder;
        if (!Directory.Exists(bundledAssets)) return Refusal.NoTemplate;
        string? internalFolder = Path.GetDirectoryName(Path.GetFullPath(planningFolder).TrimEnd('\\', '/'));
        if (internalFolder is not null && IsALink(internalFolder)) return Refusal.ALink;
        if (IsALink(planningFolder)) return Refusal.ALink;
        string assets = Path.Combine(planningFolder, FolderName);
        if (IsALink(assets)) return Refusal.ALink;
        if (Directory.Exists(assets) && HoldsALink(assets)) return Refusal.ALink;
        return null;
    }

    /// <summary>Whether something at <paramref name="path"/> is a link; false when nothing is there.</summary>
    private static bool IsALink(string path)
    {
        try { return new DirectoryInfo(path).LinkTarget is not null; }
        catch (Exception e) when (e is FileNotFoundException or DirectoryNotFoundException) { return false; }
    }

    /// <summary>
    /// The mirror itself: changed files replaced, missing ones added, extra
    /// files removed. Kept here rather than <see cref="ToolchainMirror.SyncDirectory"/>
    /// because a file is NEVER overwritten in place (790a review 2, M1): a
    /// destination file that differs is deleted and a new one written, so a
    /// HARD LINK in <c>assets</c> to a file outside the course loses its name
    /// here and the file outside is untouched. <c>File.Copy(overwrite: true)</c>
    /// wrote the template's bytes into the teacher's own file (measured with
    /// <c>CreateHardLink</c>). A file with the template's size and modification
    /// time is taken as the same, as the toolchain mirror takes it; one of the
    /// same size is compared byte for byte, and left alone, untouched, when it
    /// matches. The toolchain mirror's in-place overwrite is unchanged: it
    /// writes into <c>.toolchain</c>, which no one hard-links into.
    /// </summary>
    private static Outcome Mirror(string source, string destination)
    {
        int changed = 0, failed = 0;
        var wanted = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in new DirectoryInfo(source).EnumerateFiles("*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(source, file.FullName);
            wanted.Add(relative);
            string target = Path.Combine(destination, relative);
            try
            {
                var existing = new FileInfo(target);
                if (existing.Exists)
                {
                    if (existing.Length == file.Length
                        && (existing.LastWriteTimeUtc == file.LastWriteTimeUtc
                            || File.ReadAllBytes(target).AsSpan().SequenceEqual(File.ReadAllBytes(file.FullName))))
                        continue;
                    File.Delete(target);
                }
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                File.Copy(file.FullName, target, overwrite: false);
                File.SetLastWriteTimeUtc(target, file.LastWriteTimeUtc);
                changed++;
            }
            catch { failed++; }
        }
        if (Directory.Exists(destination))
            foreach (var file in new DirectoryInfo(destination).EnumerateFiles("*", SearchOption.AllDirectories))
            {
                if (wanted.Contains(Path.GetRelativePath(destination, file.FullName))) continue;
                try { file.Delete(); changed++; }
                catch { failed++; }
            }
        return new Outcome(changed, failed);
    }

    /// <summary>Whether anything under <paramref name="folder"/> is a link, walked without going through one.</summary>
    private static bool HoldsALink(string folder)
    {
        var pending = new Stack<DirectoryInfo>();
        pending.Push(new DirectoryInfo(folder));
        while (pending.Count > 0)
        {
            foreach (var entry in pending.Pop().EnumerateFileSystemInfos())
            {
                if (entry.LinkTarget is not null) return true;
                if (entry is DirectoryInfo child) pending.Push(child);
            }
        }
        return false;
    }
}
