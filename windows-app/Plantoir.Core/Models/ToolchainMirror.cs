namespace Plantoir.Core.Models;

/// <summary>
/// Keeps a working folder's launchers and .toolchain/ recipe mirrored from
/// the app's bundled copies. The launchers hash .toolchain to name the
/// image, so a changed recipe rebuilds the image and recreates the
/// container — one updater (the app) drives every layer. Extraneous files
/// are REMOVED from the mirror: they would change the hash and force
/// rebuilds for nothing.
/// </summary>
public static class ToolchainMirror
{
    /// <summary>The launchers the Windows app installs and refreshes.</summary>
    public static readonly IReadOnlyList<string> Launchers = new[]
    {
        "setup.ps1", "preview.ps1", "deploy.ps1",
        "setup.bat", "preview.bat", "deploy.bat",
    };

    /// <summary>Root files of the recipe (beyond the launchers).</summary>
    public static readonly IReadOnlyList<string> RecipeRootFiles = new[]
    {
        "Dockerfile",
        "setup.sh", "preview.sh", "deploy.sh",
        "setup.bat", "preview.bat", "deploy.bat",
        "setup.ps1", "preview.ps1", "deploy.ps1",
    };

    public static readonly IReadOnlyList<string> RecipeFolders = new[] { "patches", "scripts", "support" };

    private static readonly HashSet<string> FoldersWithFreshToolchain = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Testing hook to force re-mirroring.</summary>
    public static void ResetFreshToolchains() => FoldersWithFreshToolchain.Clear();

    /// <summary>
    /// Refreshes any launcher that ALREADY exists in the folder and differs
    /// byte for byte from the bundled copy. A folder with no launchers has
    /// never been initialized — that is the picker's business. Returns the
    /// refreshed names, sorted.
    /// </summary>
    public static List<string> RefreshLaunchers(string workspacePath, string bundledRoot)
    {
        var refreshed = new List<string>();
        foreach (string name in Launchers)
        {
            string destination = Path.Combine(workspacePath, name);
            string source = Path.Combine(bundledRoot, name);
            var srcInfo = new FileInfo(source);
            var dstInfo = new FileInfo(destination);
            if (!srcInfo.Exists || !dstInfo.Exists) continue;
            try
            {
                if (srcInfo.Length == dstInfo.Length)
                {
                    byte[] srcBytes = File.ReadAllBytes(source);
                    if (srcBytes.AsSpan().SequenceEqual(File.ReadAllBytes(destination)))
                    {
                        CopyModificationDate(srcInfo, dstInfo);
                        continue;
                    }
                }
                File.Copy(source, destination, overwrite: true);
                CopyModificationDate(srcInfo, new FileInfo(destination));
                refreshed.Add(name);
            }
            catch { }   // a read-only folder is unusual but not fatal
        }
        refreshed.Sort(StringComparer.Ordinal);
        return refreshed;
    }

    /// <summary>
    /// Mirrors the full recipe into &lt;workspace&gt;/.toolchain — but only for a
    /// folder that already IS a workspace. Returns the change count.
    /// </summary>
    public static int RefreshToolchain(string workspacePath, string bundledRoot)
    {
        if (!File.Exists(Path.Combine(workspacePath, Workspace.MarkerLauncher))) return 0;
        if (FoldersWithFreshToolchain.Contains(workspacePath)) return 0;
        FoldersWithFreshToolchain.Add(workspacePath);

        string toolchainRoot = Path.Combine(workspacePath, ".toolchain");
        int changed = 0;
        foreach (string name in RecipeRootFiles)
            changed += SyncFile(Path.Combine(bundledRoot, name), Path.Combine(toolchainRoot, name));
        foreach (string folder in RecipeFolders)
            changed += SyncDirectory(Path.Combine(bundledRoot, folder), Path.Combine(toolchainRoot, folder));
        return changed;
    }

    /// <summary>Copy when missing or byte-different; never touch an identical file.</summary>
    internal static int SyncFile(string source, string destination)
    {
        try
        {
            var srcInfo = new FileInfo(source);
            if (!srcInfo.Exists) return 0;
            var dstInfo = new FileInfo(destination);
            if (dstInfo.Exists && srcInfo.Length == dstInfo.Length)
            {
                byte[] sourceBytes = File.ReadAllBytes(source);
                if (sourceBytes.AsSpan().SequenceEqual(File.ReadAllBytes(destination)))
                {
                    CopyModificationDate(srcInfo, dstInfo);
                    return 0;
                }
            }
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(source, destination, overwrite: true);
            CopyModificationDate(srcInfo, new FileInfo(destination));
            return 1;
        }
        catch { return 0; }
    }

    private static void CopyModificationDate(FileInfo src, FileInfo dst)
    {
        try { File.SetLastWriteTimeUtc(dst.FullName, src.LastWriteTimeUtc); } catch { }
    }

    /// <summary>A true mirror: copy what differs AND delete what should not be there.</summary>
    internal static int SyncDirectory(string sourceRoot, string destinationRoot)
    {
        int changed = 0;
        var sourceRelatives = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (Directory.Exists(sourceRoot))
        {
            foreach (string file in Directory.EnumerateFiles(sourceRoot, "*", SearchOption.AllDirectories))
            {
                string relative = Path.GetRelativePath(sourceRoot, file);
                sourceRelatives.Add(relative);
                changed += SyncFile(file, Path.Combine(destinationRoot, relative));
            }
        }
        if (Directory.Exists(destinationRoot))
        {
            foreach (string file in Directory.EnumerateFiles(destinationRoot, "*", SearchOption.AllDirectories))
            {
                string relative = Path.GetRelativePath(destinationRoot, file);
                if (sourceRelatives.Contains(relative)) continue;
                try { File.Delete(file); changed++; } catch { }
            }
        }
        return changed;
    }

    /// <summary>
    /// Sets an empty folder up as a working folder: launchers copied in,
    /// courses/ created. Throws with teacher-facing wording on failure.
    /// </summary>
    public static void InitializeWorkspace(string workspacePath, string bundledRoot)
    {
        foreach (string name in Launchers)
        {
            string source = Path.Combine(bundledRoot, name);
            if (!File.Exists(source))
                throw new InvalidOperationException(
                    $"Part of the app’s built-in setup files is missing ({name}) — please reinstall the app.");
            File.Copy(source, Path.Combine(workspacePath, name), overwrite: true);
        }
        Directory.CreateDirectory(Workspace.CoursesDirectory(workspacePath));
    }
}
