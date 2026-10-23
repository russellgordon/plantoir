using System.Security.Cryptography;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #559: the mirror compares by fingerprint where it can. A release built from
/// a freshly checked-out tree restamps every bundled file, and comparing by
/// time then read ~12,700 files twice (131.6 s on an i5-8365U). The bundle's
/// manifest (<c>Toolchain\.hashes</c>) and the folder's index (the manifest
/// last applied, under AppDataRoot) let a same-length, different-time pair be
/// compared without reading — but ONLY while each fingerprint still describes
/// its file, so a stale one costs reads and never a missed copy. A copy whose
/// own time moved is still read (once): nothing can tell it from an edit.
/// </summary>
public sealed class ToolchainFingerprintTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "fingerprints-" + Guid.NewGuid().ToString("N"));
    private readonly string _bundled;
    private readonly string _folder;

    public ToolchainFingerprintTests()
    {
        _bundled = Path.Combine(_root, "bundled");
        _folder = Path.Combine(_root, "work");
        Directory.CreateDirectory(Path.Combine(_bundled, "scripts"));
        Directory.CreateDirectory(Path.Combine(_bundled, "support", "deep"));
        Directory.CreateDirectory(_folder);
        File.WriteAllText(Path.Combine(_folder, Workspace.MarkerLauncher), "marker");
        File.WriteAllText(Path.Combine(_bundled, "Dockerfile"), "FROM node:20");
        File.WriteAllText(Path.Combine(_bundled, "scripts", "build_site.py"), "print('one')");
        File.WriteAllText(Path.Combine(_bundled, "support", "deep", "page.md"), "# A page");
        StampAll(_bundled, new DateTime(2026, 10, 3, 12, 0, 0, DateTimeKind.Utc));
    }

    public void Dispose()
    {
        try { File.Delete(ToolchainMirror.IndexPathFor(_folder)); } catch { }
        try { Directory.Delete(_root, true); } catch { }
    }

    private string Copy(string relative) => Path.Combine(_folder, ".toolchain", relative);

    private static void StampAll(string root, DateTime when)
    {
        foreach (string file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            File.SetLastWriteTimeUtc(file, when);
    }

    /// <summary>The manifest the build writes, computed here independently of the product code.</summary>
    private void WriteManifest()
    {
        var entries = new Dictionary<string, ToolchainMirror.Fingerprint>(StringComparer.OrdinalIgnoreCase);
        foreach (string file in Directory.EnumerateFiles(_bundled, "*", SearchOption.AllDirectories))
        {
            if (Path.GetFileName(file) == ToolchainMirror.ManifestName) continue;
            var info = new FileInfo(file);
            entries[Path.GetRelativePath(_bundled, file)] = new ToolchainMirror.Fingerprint(
                info.Length, info.LastWriteTimeUtc.Ticks,
                Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))).ToLowerInvariant());
        }
        ToolchainMirror.WriteFingerprints(Path.Combine(_bundled, ToolchainMirror.ManifestName), entries);
    }

    [Fact]
    public void ARestampedCopyIsReadOnceAndThenTakenAtItsTimeAgain()
    {
        // A copy whose time moved is indistinguishable from one edited in
        // place, so neither fingerprint can vouch for it: it is READ (once,
        // hashed against the manifest, not both files) and stamped back.
        WriteManifest();
        var first = ToolchainMirror.RefreshToolchain(_folder, _bundled);
        Assert.Equal(3, first.Changed);
        Assert.Equal(0, first.Compared);
        Assert.True(File.Exists(ToolchainMirror.IndexPathFor(_folder)));

        StampAll(Path.Combine(_folder, ".toolchain"), DateTime.UtcNow);
        var second = ToolchainMirror.RefreshToolchain(_folder, _bundled);
        Assert.Equal(0, second.Changed);
        Assert.Equal(3, second.Compared);
        Assert.Equal(3, second.ReadInFull);
        Assert.Equal(new FileInfo(Path.Combine(_bundled, "Dockerfile")).LastWriteTimeUtc,
                     new FileInfo(Copy("Dockerfile")).LastWriteTimeUtc);

        var third = ToolchainMirror.RefreshToolchain(_folder, _bundled);
        Assert.Equal(3, third.Compared);
        Assert.Equal(0, third.ReadInFull);
    }

    [Fact]
    public void ARestampedBundleIsComparedWithoutReadingWhenItsManifestDescribesIt()
    {
        WriteManifest();
        ToolchainMirror.RefreshToolchain(_folder, _bundled);

        // The release case: the next bundle has the same bytes under new times, and its own manifest.
        StampAll(_bundled, new DateTime(2026, 10, 22, 9, 0, 0, DateTimeKind.Utc));
        WriteManifest();
        var pass = ToolchainMirror.RefreshToolchain(_folder, _bundled);

        Assert.Equal(0, pass.Changed);
        Assert.Equal(3, pass.Compared);
        Assert.Equal(0, pass.ReadInFull);
    }

    [Fact]
    public void WithNoIndexTheCopyIsReadOnceAndTheIndexIsWritten()
    {
        WriteManifest();
        ToolchainMirror.RefreshToolchain(_folder, _bundled);
        File.Delete(ToolchainMirror.IndexPathFor(_folder));

        StampAll(_bundled, new DateTime(2026, 10, 22, 9, 0, 0, DateTimeKind.Utc));
        WriteManifest();
        var pass = ToolchainMirror.RefreshToolchain(_folder, _bundled);
        Assert.Equal(0, pass.Changed);
        Assert.Equal(3, pass.ReadInFull);
        Assert.True(File.Exists(ToolchainMirror.IndexPathFor(_folder)));

        StampAll(_bundled, new DateTime(2026, 10, 23, 9, 0, 0, DateTimeKind.Utc));
        WriteManifest();
        Assert.Equal(0, ToolchainMirror.RefreshToolchain(_folder, _bundled).ReadInFull);
    }

    /// <summary>Moves every bundled file's time down by <paramref name="by"/>: what the installer's 2 s rounding does.</summary>
    private void RoundTheBundleDown(TimeSpan by)
    {
        foreach (string file in Directory.EnumerateFiles(_bundled, "*", SearchOption.AllDirectories))
        {
            if (Path.GetFileName(file) == ToolchainMirror.ManifestName) continue;
            File.SetLastWriteTimeUtc(file, File.GetLastWriteTimeUtc(file) - by);
        }
    }

    [Fact]
    public void AnInstalledBundleWhoseTimesWereRoundedDownIsStillTrusted()
    {
        // Inno rounds every installed file's time DOWN to 2 s, and a zip stores
        // DOS times rounded the same way, while the manifest holds the build
        // tree's exact ticks. Up to 1.999 s down is the same file.
        WriteManifest();
        ToolchainMirror.RefreshToolchain(_folder, _bundled);
        RoundTheBundleDown(TimeSpan.FromMilliseconds(1999));

        var pass = ToolchainMirror.RefreshToolchain(_folder, _bundled);

        Assert.Equal(0, pass.Changed);
        Assert.Equal(3, pass.Compared);
        Assert.Equal(0, pass.ReadInFull);
    }

    [Fact]
    public void ABundledFileLaterThanItsManifestIsNotTrusted()
    {
        // Rounding only ever moves a time DOWN; a later one is a file that moved on.
        WriteManifest();
        ToolchainMirror.RefreshToolchain(_folder, _bundled);
        RoundTheBundleDown(-TimeSpan.FromMilliseconds(500));

        var pass = ToolchainMirror.RefreshToolchain(_folder, _bundled);

        Assert.Equal(0, pass.Changed);
        Assert.Equal(3, pass.ReadInFull);   // read both, as before #559
    }

    [Fact]
    public void ABundledFileTwoSecondsOlderThanItsManifestIsNotTrusted()
    {
        WriteManifest();
        ToolchainMirror.RefreshToolchain(_folder, _bundled);
        RoundTheBundleDown(TimeSpan.FromSeconds(2));

        var pass = ToolchainMirror.RefreshToolchain(_folder, _bundled);

        Assert.Equal(0, pass.Changed);
        Assert.Equal(3, pass.ReadInFull);   // read both, as before #559
    }

    [Fact]
    public void AStaleManifestDoesNotSkipTheCopy()
    {
        WriteManifest();
        ToolchainMirror.RefreshToolchain(_folder, _bundled);

        // The bundled file changes AFTER its manifest was written: same length,
        // new content, new time. The manifest still names the OLD hash, which is
        // exactly the hash the index holds for the copy — trusting the manifest
        // would call the two the same and leave the old script in place.
        string script = Path.Combine(_bundled, "scripts", "build_site.py");
        File.WriteAllText(script, "print('two')");
        File.SetLastWriteTimeUtc(script, new DateTime(2026, 10, 4, 12, 0, 0, DateTimeKind.Utc));

        var pass = ToolchainMirror.RefreshToolchain(_folder, _bundled);

        Assert.Equal("print('two')", File.ReadAllText(Copy(Path.Combine("scripts", "build_site.py"))));
        Assert.Equal(1, pass.Changed);
        Assert.Equal(1, pass.ReadInFull);   // read both, as before #559
    }

    [Fact]
    public void ACopyEditedSinceTheIndexWasWrittenIsReadAndReplaced()
    {
        WriteManifest();
        ToolchainMirror.RefreshToolchain(_folder, _bundled);

        // Somebody edits the copy in place, keeping its length: its time moves, so the index no longer describes it.
        string copied = Copy(Path.Combine("scripts", "build_site.py"));
        File.WriteAllText(copied, "print('mod')");
        File.SetLastWriteTimeUtc(copied, DateTime.UtcNow);

        var pass = ToolchainMirror.RefreshToolchain(_folder, _bundled);

        Assert.Equal("print('one')", File.ReadAllText(copied));
        Assert.Equal(1, pass.Changed);
        Assert.Equal(1, pass.ReadInFull);
    }

    [Fact]
    public void WithNoManifestTheMirrorReadsAsItAlwaysDid()
    {
        ToolchainMirror.RefreshToolchain(_folder, _bundled);
        Assert.False(File.Exists(ToolchainMirror.IndexPathFor(_folder)));   // nothing known, nothing recorded
        StampAll(Path.Combine(_folder, ".toolchain"), DateTime.UtcNow);

        var pass = ToolchainMirror.RefreshToolchain(_folder, _bundled);

        Assert.Equal(0, pass.Changed);
        Assert.Equal(3, pass.Compared);
        Assert.Equal(3, pass.ReadInFull);
    }

    [Fact]
    public void TheManifestIsNeverMirroredIntoTheFolder()
    {
        WriteManifest();
        ToolchainMirror.RefreshToolchain(_folder, _bundled);
        Assert.Empty(Directory.EnumerateFiles(Path.Combine(_folder, ".toolchain"), ToolchainMirror.ManifestName,
                                              SearchOption.AllDirectories));
    }

    [Fact]
    public void AManifestLineThatDoesNotParseIsSkippedNotTrusted()
    {
        string path = Path.Combine(_root, "odd.hashes");
        File.WriteAllLines(path, new[]
        {
            "Dockerfile\t12\t638000000000000000\t" + new string('a', 64),
            "broken line",
            "scripts\\x.py\tnot-a-number\t1\t" + new string('b', 64),
            "scripts\\y.py\t1\t1\tshort",
        });
        var entries = ToolchainMirror.ReadFingerprints(path)!;
        Assert.Single(entries);
        Assert.True(entries.ContainsKey("dockerfile"));   // compared without regard to case, as Windows paths are
    }
}
