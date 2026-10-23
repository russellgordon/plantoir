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
    /// <para><see cref="Compared"/> counts the files that already had a copy
    /// and were compared with it; <see cref="ReadInFull"/> the ones among them
    /// that had to be READ to answer (#559). The second is the number a slow
    /// pass is explained by: 1.7.1 → 1.7.2 changed 14 files and read about
    /// 12,700 of them twice, in 131.6 s, and the old line said only "14".</para>
    /// </summary>
    public readonly record struct CopyResult(int Changed, int Failed,
                                             string? FirstFailedPath = null, string? FirstProblem = null,
                                             Exception? FirstError = null)
    {
        /// <summary>Files that already had a copy, compared with it.</summary>
        public int Compared { get; init; }

        /// <summary>Of <see cref="Compared"/>, the files read in full to compare them.</summary>
        public int ReadInFull { get; init; }

        public static CopyResult operator +(CopyResult a, CopyResult b) =>
            new(a.Changed + b.Changed, a.Failed + b.Failed,
                a.FirstFailedPath ?? b.FirstFailedPath,
                a.FirstFailedPath is not null ? a.FirstProblem : b.FirstProblem,
                a.FirstFailedPath is not null ? a.FirstError : b.FirstError)
            {
                Compared = a.Compared + b.Compared,
                ReadInFull = a.ReadInFull + b.ReadInFull,
            };

        /// <summary>One file that could not be copied or removed, and why.
        /// The exception itself is kept for a reader that must say the reason
        /// WITHOUT the path .NET puts in its message (the guidance notice,
        /// <see cref="AgentGuidance.SystemReason"/>).</summary>
        public static CopyResult OneFailure(string path, Exception error) => new(0, 1, path, error.Message, error);
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

    // ---- The fingerprints that let a pass compare without reading (#559) ----

    /// <summary>
    /// The manifest the build writes beside the bundled recipe
    /// (<c>Toolchain\.hashes</c>, Plantoir.csproj → <c>WriteToolchainHashes</c>):
    /// one line per file, relative path, length, last-write time in UTC ticks
    /// and SHA-256. It sits at the recipe's root, which is neither a
    /// <see cref="RecipeRootFiles"/> entry nor in a <see cref="RecipeFolders"/>
    /// folder, so it is never mirrored into a working folder.
    /// </summary>
    public const string ManifestName = ".hashes";

    /// <summary>One file's length, last-write time (UTC ticks) and SHA-256 (lower-case hex).</summary>
    internal readonly record struct Fingerprint(long Length, long WriteTicksUtc, string Sha256)
    {
        /// <summary>
        /// Whether this fingerprint is still the file's: same length, same
        /// last-write time within the 2 ms <see cref="FilesLookIdentical"/>
        /// allows. A fingerprint whose file has moved on is not used at all —
        /// the pass reads the file instead, as it did before #559.
        /// </summary>
        public bool StillDescribes(FileInfo file) =>
            file.Exists && file.Length == Length
            && Math.Abs(file.LastWriteTimeUtc.Ticks - WriteTicksUtc) < TimeSpan.TicksPerMillisecond * 2;

        /// <summary>
        /// Whether this MANIFEST entry still describes an INSTALLED bundled
        /// file: same length, and a time no later than the manifest's and less
        /// than 2 s earlier. The installer rounds every file's time DOWN to
        /// 2 s (Inno's TimeStampRounding default; measured 3,000 of 3,000
        /// installed files on a 2 s boundary) and a zip stores DOS times,
        /// rounded down the same way, while the manifest holds the build
        /// tree's exact ticks — so the 2 ms check would never trust an
        /// installed bundle, the one case #559 exists for. One-sided and
        /// under 2 s: a time LATER than the manifest's, or 2 s or more
        /// earlier, is a file that moved on. Nobody edits the bundle in
        /// place; the index side keeps the 2 ms check, because that time is
        /// the copy's own exact stamp.
        /// </summary>
        public bool StillDescribesInstalled(FileInfo file)
        {
            if (!file.Exists || file.Length != Length) return false;
            long roundedDownBy = WriteTicksUtc - file.LastWriteTimeUtc.Ticks;
            return roundedDownBy >= 0 && roundedDownBy < InstallerRounding.Ticks;
        }
    }

    /// <summary>How far an installer or a zip may round a bundled file's time down (#559).</summary>
    internal static readonly TimeSpan InstallerRounding = TimeSpan.FromSeconds(2);

    /// <summary>
    /// Where a working folder's index lives: the manifest last applied to its
    /// <c>.toolchain</c>, with each copy's OWN time recorded. Under
    /// <see cref="AppDataRoot"/> rather than beside <c>.toolchain</c>, so the
    /// teacher never sees it, it does not travel with a copied folder, and a
    /// <c>--state-dir</c> run keeps its own.
    /// </summary>
    internal static string IndexPathFor(string workspacePath) =>
        AppDataRoot.Combine("toolchain-index", FolderContainers.FolderIdentifier(workspacePath) + ManifestName);

    /// <summary>Reads a manifest or index; null when there is none or it cannot be read.
    /// A line that does not parse is skipped: that file is simply read, as before #559.</summary>
    internal static Dictionary<string, Fingerprint>? ReadFingerprints(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var entries = new Dictionary<string, Fingerprint>(StringComparer.OrdinalIgnoreCase);
            foreach (string line in File.ReadLines(path))
            {
                string[] parts = line.Split('\t');
                if (parts.Length != 4) continue;
                if (!long.TryParse(parts[1], System.Globalization.NumberStyles.None,
                                   System.Globalization.CultureInfo.InvariantCulture, out long length)) continue;
                if (!long.TryParse(parts[2], System.Globalization.NumberStyles.None,
                                   System.Globalization.CultureInfo.InvariantCulture, out long ticks)) continue;
                if (parts[3].Length != 64) continue;
                entries[parts[0]] = new Fingerprint(length, ticks, parts[3].ToLowerInvariant());
            }
            return entries;
        }
        catch { return null; }
    }

    /// <summary>Writes an index whole or not at all: a temporary file beside it, then a rename over it.</summary>
    internal static void WriteFingerprints(string path, IReadOnlyDictionary<string, Fingerprint> entries)
    {
        string? directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        string temporary = path + "." + Environment.ProcessId + ".tmp";
        var lines = entries
            .OrderBy(e => e.Key, StringComparer.OrdinalIgnoreCase)
            .Select(e => string.Create(System.Globalization.CultureInfo.InvariantCulture,
                                       $"{e.Key}\t{e.Value.Length}\t{e.Value.WriteTicksUtc}\t{e.Value.Sha256}"));
        try
        {
            File.WriteAllLines(temporary, lines);
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
        }
    }

    /// <summary>
    /// What one <see cref="RefreshToolchain"/> pass knows without reading: the
    /// bundle's manifest, the folder's index from the last pass, and the index
    /// this pass is building. A file is compared WITHOUT reading only when
    /// both fingerprints still describe their files; anything else is read,
    /// exactly as before #559.
    /// </summary>
    internal sealed class MirrorPass
    {
        private readonly Dictionary<string, Fingerprint>? _bundled;
        private readonly Dictionary<string, Fingerprint>? _applied;

        public MirrorPass(Dictionary<string, Fingerprint>? bundled, Dictionary<string, Fingerprint>? applied)
        {
            _bundled = bundled;
            _applied = applied;
        }

        /// <summary>The index this pass leaves: every copy whose content is known, with its own time.</summary>
        public Dictionary<string, Fingerprint> Next { get; } = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>The bundled file's hash, if the manifest still describes it.</summary>
        public string? BundledHash(string relative, FileInfo source) =>
            _bundled is not null && _bundled.TryGetValue(relative, out var entry) && entry.StillDescribesInstalled(source)
                ? entry.Sha256 : null;

        /// <summary>The copy's hash, if the last pass's index still describes it.</summary>
        public string? AppliedHash(string relative, FileInfo copy) =>
            _applied is not null && _applied.TryGetValue(relative, out var entry) && entry.StillDescribes(copy)
                ? entry.Sha256 : null;

        /// <summary>
        /// Records the copy as holding <paramref name="sha256"/>, with the time
        /// <paramref name="copy"/> holds. After a stamp the caller passes a
        /// FRESH FileInfo, so the time is read back from the disk rather than
        /// assumed: <see cref="CopyModificationDate"/> swallows a failure, and
        /// a copy whose stamp did not take is recorded with the time it has.
        /// </summary>
        public void Remember(string relative, FileInfo copy, string sha256)
        {
            try
            {
                if (copy.Exists) Next[relative] = new Fingerprint(copy.Length, copy.LastWriteTimeUtc.Ticks, sha256);
            }
            catch { }
        }

        /// <summary>Whether <see cref="Next"/> says anything the index on disk does not.</summary>
        public bool IndexChanged()
        {
            if (_applied is null) return Next.Count > 0;   // nothing known before, and nothing known now: no file
            if (_applied.Count != Next.Count) return true;
            foreach (var (key, value) in Next)
            {
                if (!_applied.TryGetValue(key, out var old) || old != value) return true;
            }
            return false;
        }
    }

    /// <summary>
    /// Mirrors the full recipe into &lt;workspace&gt;/.toolchain — but only for a
    /// folder that already IS a workspace — in place, file by file (only what
    /// differs is written). Synchronous and unguarded: call it through
    /// <see cref="ToolchainReadiness.Ensure"/>, which runs it off the UI
    /// thread, once per folder per process, and says when it is done.
    /// <para>Since #559 it compares by fingerprint where it can (<see cref="MirrorPass"/>),
    /// and writes the folder's index once, whole, when the pass failed nothing.</para>
    /// </summary>
    public static CopyResult RefreshToolchain(string workspacePath, string bundledRoot)
    {
        if (!IsAWorkingFolder(workspacePath)) return default;

        string toolchainRoot = Path.Combine(workspacePath, ".toolchain");
        string? indexPath = null;
        try { indexPath = IndexPathFor(workspacePath); } catch { }
        var pass = new MirrorPass(ReadFingerprints(Path.Combine(bundledRoot, ManifestName)),
                                  indexPath is null ? null : ReadFingerprints(indexPath));
        var result = default(CopyResult);
        foreach (string name in RecipeRootFiles)
            result += SyncFile(Path.Combine(bundledRoot, name), Path.Combine(toolchainRoot, name), null, pass, name);
        foreach (string folder in RecipeFolders)
            result += SyncDirectory(Path.Combine(bundledRoot, folder), Path.Combine(toolchainRoot, folder), pass, folder);
        if (result.Failed == 0 && indexPath is not null && pass.IndexChanged())
        {
            // Best effort: a missing index costs the next pass reads, never correctness.
            try { WriteFingerprints(indexPath, pass.Next); } catch { }
        }
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
    /// <para>With a <paramref name="pass"/> (<see cref="RefreshToolchain"/>
    /// only, since #559), a same-length copy whose time differs is compared by
    /// hash when the manifest and the index both still describe their files;
    /// by hashing the copy alone when only the manifest does; and otherwise by
    /// reading both, as it always was. Without one — the agent guidance's
    /// skills, which have no manifest — this is exactly the pre-#559 code.</para>
    /// </summary>
    internal static CopyResult SyncFile(string source, string destination, HashSet<string>? createdDirs = null,
                                        MirrorPass? pass = null, string? relative = null)
    {
        try
        {
            var srcInfo = new FileInfo(source);
            if (!srcInfo.Exists) return default;
            string? bundledHash = pass is not null && relative is not null ? pass.BundledHash(relative, srcInfo) : null;
            var dstInfo = new FileInfo(destination);
            bool compared = dstInfo.Exists;
            bool read = false;
            if (dstInfo.Exists)
            {
                if (FilesLookIdentical(srcInfo, dstInfo))
                {
                    if (bundledHash is not null) pass!.Remember(relative!, dstInfo, bundledHash);
                    return new CopyResult(0, 0) { Compared = 1 };
                }
                if (srcInfo.Length == dstInfo.Length)
                {
                    bool? same = null;
                    if (bundledHash is not null)
                    {
                        string? appliedHash = pass!.AppliedHash(relative!, dstInfo);
                        if (appliedHash is null)
                        {
                            read = true;
                            appliedHash = Sha256Of(destination);
                        }
                        same = appliedHash == bundledHash;
                    }
                    else
                    {
                        read = true;
                        byte[] sourceBytes = File.ReadAllBytes(source);
                        same = sourceBytes.AsSpan().SequenceEqual(File.ReadAllBytes(destination));
                    }
                    if (same == true)
                    {
                        CopyModificationDate(srcInfo, dstInfo);
                        if (bundledHash is not null) pass!.Remember(relative!, new FileInfo(destination), bundledHash);
                        return new CopyResult(0, 0) { Compared = 1, ReadInFull = read ? 1 : 0 };
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
            if (bundledHash is not null) pass!.Remember(relative!, new FileInfo(destination), bundledHash);
            return new CopyResult(1, 0) { Compared = compared ? 1 : 0, ReadInFull = read ? 1 : 0 };
        }
        catch (Exception error) { return CopyResult.OneFailure(destination, error); }
    }

    private static string Sha256Of(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16,
                                          FileOptions.SequentialScan);
        return Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static void CopyModificationDate(FileInfo src, FileInfo dst)
    {
        try { File.SetLastWriteTimeUtc(dst.FullName, src.LastWriteTimeUtc); } catch { }
    }

    /// <summary>
    /// A true mirror: copy what differs AND delete what should not be there.
    /// Copies and deletes that fail are counted in <see cref="CopyResult.Failed"/>.
    /// <paramref name="pass"/> and <paramref name="relativeRoot"/> (the folder's
    /// name inside the recipe) are given by <see cref="RefreshToolchain"/> only.
    /// </summary>
    internal static CopyResult SyncDirectory(string sourceRoot, string destinationRoot,
                                             MirrorPass? pass = null, string? relativeRoot = null)
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
                string? key = pass is not null && relativeRoot is not null ? Path.Combine(relativeRoot, relative) : null;
                var dstInfo = new FileInfo(destFile);
                if (dstInfo.Exists && FilesLookIdentical(fileInfo, dstInfo))
                {
                    if (key is not null && pass!.BundledHash(key, fileInfo) is { } hash) pass.Remember(key, dstInfo, hash);
                    result += new CopyResult(0, 0) { Compared = 1 };
                    continue;
                }
                result += SyncFile(fileInfo.FullName, destFile, createdDirs, pass, key);
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
