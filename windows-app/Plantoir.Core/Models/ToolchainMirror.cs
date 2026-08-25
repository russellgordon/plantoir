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

    public static readonly IReadOnlyList<string> RecipeFolders = new[] { "patches", "scripts", "support", "contracts" };

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

    /// <summary>Whether two files can be taken for the same file without reading them.</summary>
    internal static bool FilesLookIdentical(FileInfo srcInfo, FileInfo dstInfo)
    {
        if (!srcInfo.Exists || !dstInfo.Exists) return false;
        if (srcInfo.Length != dstInfo.Length) return false;
        return Math.Abs((srcInfo.LastWriteTimeUtc - dstInfo.LastWriteTimeUtc).TotalSeconds) < 0.002;
    }

    /// <summary>Copy when missing or byte-different; never touch an identical file.</summary>
    internal static int SyncFile(string source, string destination, HashSet<string>? createdDirs = null)
    {
        try
        {
            var srcInfo = new FileInfo(source);
            if (!srcInfo.Exists) return 0;
            var dstInfo = new FileInfo(destination);
            if (dstInfo.Exists)
            {
                if (FilesLookIdentical(srcInfo, dstInfo)) return 0;
                if (srcInfo.Length == dstInfo.Length)
                {
                    byte[] sourceBytes = File.ReadAllBytes(source);
                    if (sourceBytes.AsSpan().SequenceEqual(File.ReadAllBytes(destination)))
                    {
                        CopyModificationDate(srcInfo, dstInfo);
                        return 0;
                    }
                }
            }
            string? dir = Path.GetDirectoryName(destination);
            if (!string.IsNullOrEmpty(dir))
            {
                if (createdDirs is null || createdDirs.Add(dir))
                    Directory.CreateDirectory(dir);
            }
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
        var createdDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (Directory.Exists(sourceRoot))
        {
            var srcDir = new DirectoryInfo(sourceRoot);
            foreach (var fileInfo in srcDir.EnumerateFiles("*", SearchOption.AllDirectories))
            {
                string relative = Path.GetRelativePath(sourceRoot, fileInfo.FullName);
                sourceRelatives.Add(relative);
                string destFile = Path.Combine(destinationRoot, relative);
                var dstInfo = new FileInfo(destFile);
                if (dstInfo.Exists && FilesLookIdentical(fileInfo, dstInfo)) continue;
                changed += SyncFile(fileInfo.FullName, destFile, createdDirs);
            }
        }
        if (Directory.Exists(destinationRoot))
        {
            var dstDir = new DirectoryInfo(destinationRoot);
            foreach (var fileInfo in dstDir.EnumerateFiles("*", SearchOption.AllDirectories))
            {
                string relative = Path.GetRelativePath(destinationRoot, fileInfo.FullName);
                if (sourceRelatives.Contains(relative)) continue;
                try { fileInfo.Delete(); changed++; } catch { }
            }
        }
        return changed;
    }


    /// <summary>
    /// Sets an empty folder up as a working folder: launchers copied in,
    /// courses/ created, and .toolchain/ populated. Throws with teacher-facing
    /// wording on failure.
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
        RefreshToolchain(workspacePath, bundledRoot);
    }
}
