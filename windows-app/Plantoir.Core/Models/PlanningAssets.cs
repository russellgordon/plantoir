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
            if (!Directory.Exists(planningFolder) || !Directory.Exists(bundledAssets)) return null;
            string? internalFolder = Path.GetDirectoryName(Path.GetFullPath(planningFolder).TrimEnd('\\', '/'));
            if (internalFolder is not null && IsALink(internalFolder)) return null;
            if (IsALink(planningFolder)) return null;
            string assets = Path.Combine(planningFolder, FolderName);
            if (Directory.Exists(assets) && (IsALink(assets) || HoldsALink(assets))) return null;
            var copied = ToolchainMirror.SyncDirectory(bundledAssets, assets);
            return new Outcome(copied.Changed, copied.Failed);
        }
        catch { return null; }
    }

    private static bool IsALink(string path) => new DirectoryInfo(path).LinkTarget is not null;

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
