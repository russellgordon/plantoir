namespace Plantoir.Core.Models;

/// <summary>
/// Keeps a working folder's launchers and .toolchain/ recipe mirrored from
/// the app's bundled copies. The launchers hash .toolchain to name the
/// image, so a changed recipe rebuilds the image and recreates the
/// container — one updater (the app) drives every layer. Extraneous files
/// are REMOVED from the mirror: they would change the hash and force
/// rebuilds for nothing.
///
/// <para><b>This class only copies; it decides nothing about WHEN.</b> Since
/// #473 the once-per-folder-per-process rule, the background thread the copy
/// runs on and the question "may this folder be built from yet?" all belong
/// to <see cref="ToolchainReadiness"/>. The launchers (six small files) are
/// still refreshed synchronously on every <c>WorkspaceViewModel.Reload()</c>
/// by <see cref="RefreshLaunchers"/>; the recipe (thousands of files, about
/// two minutes on the first launch after an update on an i5-8365U) is not.</para>
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

    /// <summary>
    /// What one mirror pass did: files copied or removed, and files it could
    /// NOT copy or remove — with the FIRST of those and why, which is what
    /// the trail line names. A pass with any failure leaves the folder not
    /// ready (#473): before, every failure was swallowed and returned 0, so a
    /// half-copied recipe was taken for a fresh one for the rest of the run.
    /// </summary>
    public readonly record struct CopyResult(int Changed, int Failed,
                                             string? FirstFailedPath = null, string? FirstProblem = null)
    {
        public static CopyResult operator +(CopyResult a, CopyResult b) =>
            new(a.Changed + b.Changed, a.Failed + b.Failed,
                a.FirstFailedPath ?? b.FirstFailedPath,
                a.FirstFailedPath is not null ? a.FirstProblem : b.FirstProblem);

        /// <summary>One file that could not be copied or removed, and why.</summary>
        public static CopyResult OneFailure(string path, Exception error) => new(0, 1, path, error.Message);
    }

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

    /// <summary>Whether a folder is a working folder, and so gets a .toolchain at all.</summary>
    public static bool IsAWorkingFolder(string workspacePath) =>
        File.Exists(Path.Combine(workspacePath, Workspace.MarkerLauncher));

    /// <summary>
    /// Mirrors the full recipe into &lt;workspace&gt;/.toolchain — but only for a
    /// folder that already IS a workspace — in place, file by file (only what
    /// differs is written). Synchronous and unguarded: call it through
    /// <see cref="ToolchainReadiness.Ensure"/>, which runs it off the UI
    /// thread, once per folder per process, and says when it is done.
    /// </summary>
    public static CopyResult RefreshToolchain(string workspacePath, string bundledRoot)
    {
        if (!IsAWorkingFolder(workspacePath)) return default;

        string toolchainRoot = Path.Combine(workspacePath, ".toolchain");
        var result = default(CopyResult);
        foreach (string name in RecipeRootFiles)
            result += SyncFile(Path.Combine(bundledRoot, name), Path.Combine(toolchainRoot, name));
        foreach (string folder in RecipeFolders)
            result += SyncDirectory(Path.Combine(bundledRoot, folder), Path.Combine(toolchainRoot, folder));
        // Named from the working folder down (".toolchain\scripts\x.py"): the
        // part worth reading, and no user name to redact.
        if (result.FirstFailedPath is { } failed)
        {
            try { result = result with { FirstFailedPath = Path.GetRelativePath(workspacePath, failed) }; }
            catch { }
        }
        return result;
    }

    /// <summary>Whether two files can be taken for the same file without reading them.</summary>
    internal static bool FilesLookIdentical(FileInfo srcInfo, FileInfo dstInfo)
    {
        if (!srcInfo.Exists || !dstInfo.Exists) return false;
        if (srcInfo.Length != dstInfo.Length) return false;
        return Math.Abs((srcInfo.LastWriteTimeUtc - dstInfo.LastWriteTimeUtc).TotalSeconds) < 0.002;
    }

    /// <summary>
    /// Copy when missing or byte-different; never touch an identical file.
    /// A copy that throws is COUNTED as a failure rather than swallowed.
    /// </summary>
    internal static CopyResult SyncFile(string source, string destination, HashSet<string>? createdDirs = null)
    {
        try
        {
            var srcInfo = new FileInfo(source);
            if (!srcInfo.Exists) return default;
            var dstInfo = new FileInfo(destination);
            if (dstInfo.Exists)
            {
                if (FilesLookIdentical(srcInfo, dstInfo)) return default;
                if (srcInfo.Length == dstInfo.Length)
                {
                    byte[] sourceBytes = File.ReadAllBytes(source);
                    if (sourceBytes.AsSpan().SequenceEqual(File.ReadAllBytes(destination)))
                    {
                        CopyModificationDate(srcInfo, dstInfo);
                        return default;
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
            return new CopyResult(1, 0);
        }
        catch (Exception error) { return CopyResult.OneFailure(destination, error); }
    }

    private static void CopyModificationDate(FileInfo src, FileInfo dst)
    {
        try { File.SetLastWriteTimeUtc(dst.FullName, src.LastWriteTimeUtc); } catch { }
    }

    /// <summary>
    /// A true mirror: copy what differs AND delete what should not be there.
    /// Copies and deletes that fail are counted in <see cref="CopyResult.Failed"/>.
    /// </summary>
    internal static CopyResult SyncDirectory(string sourceRoot, string destinationRoot)
    {
        var result = default(CopyResult);
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
                result += SyncFile(fileInfo.FullName, destFile, createdDirs);
            }
        }
        if (Directory.Exists(destinationRoot))
        {
            var dstDir = new DirectoryInfo(destinationRoot);
            foreach (var fileInfo in dstDir.EnumerateFiles("*", SearchOption.AllDirectories))
            {
                string relative = Path.GetRelativePath(destinationRoot, fileInfo.FullName);
                if (sourceRelatives.Contains(relative)) continue;
                try { fileInfo.Delete(); result += new CopyResult(1, 0); }
                catch (Exception error) { result += CopyResult.OneFailure(fileInfo.FullName, error); }
            }
        }
        return result;
    }


    /// <summary>
    /// Sets an empty folder up as a working folder: launchers copied in,
    /// courses/ created, and .toolchain/ populated. Throws with teacher-facing
    /// wording on failure. The recipe is copied through
    /// <see cref="ToolchainReadiness.Ensure"/> and WAITED for, so a window
    /// already copying into the same folder is joined rather than raced, and
    /// a copy that failed earlier is tried again. Call it off the UI thread
    /// (the picker does).
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
        ToolchainReadiness.Ensure(workspacePath, bundledRoot, retryAFailedCopy: true).GetAwaiter().GetResult();
    }
}
