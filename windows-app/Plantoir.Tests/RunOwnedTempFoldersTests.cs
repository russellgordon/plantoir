using System.Diagnostics;
using System.IO.Enumeration;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #882: a test run removes only the temp folders it owns, or ones whose owner
/// is provably gone and that are old enough; never a live run's by its name.
/// </summary>
public sealed class RunOwnedTempFoldersTests : IDisposable
{
    private const string Prefix = "plantoir-ownedtest-";
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-882-sweep-").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Make(string name, TimeSpan age)
    {
        string folder = Path.Combine(_root, name);
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "probe.exe"), "");
        Directory.SetCreationTimeUtc(folder, DateTime.UtcNow - age);
        return folder;
    }

    [Fact]
    public void AnOldFolderWhoseOwnerIsGoneIsSwept()
    {
        string orphan = Make(Prefix + RunOwnedTempFolders.OwnerTag(424242, 1) + "-x", TimeSpan.FromHours(2));
        var swept = RunOwnedTempFolders.SweepOrphans(Prefix, root: _root, ownerIsAlive: (_, _) => false);
        Assert.Equal(new[] { orphan }, swept);
        Assert.False(Directory.Exists(orphan));
    }

    [Fact]
    public void ALiveRunsFolderIsNeverSwept_HoweverOld()
    {
        string mine = Make(Prefix + RunOwnedTempFolders.ThisRun + "-x", TimeSpan.FromDays(3));
        // The real liveness check, against this very process.
        Assert.Empty(RunOwnedTempFolders.SweepOrphans(Prefix, root: _root));
        Assert.True(Directory.Exists(mine));
    }

    [Fact]
    public void ARecycledProcessIdIsNotTheOwner()
    {
        using var self = Process.GetCurrentProcess();
        long start = self.StartTime.ToUniversalTime().Ticks;
        Assert.True(RunOwnedTempFolders.OwnerIsAlive(Environment.ProcessId, start));
        Assert.False(RunOwnedTempFolders.OwnerIsAlive(Environment.ProcessId, start - 1));
    }

    [Fact]
    public void AYoungOrphanIsLeftUntilItIsOldEnough()
    {
        string young = Make(Prefix + RunOwnedTempFolders.OwnerTag(424242, 1) + "-x", RunOwnedTempFolders.SafeAge - TimeSpan.FromMinutes(5));
        Assert.Empty(RunOwnedTempFolders.SweepOrphans(Prefix, root: _root, ownerIsAlive: (_, _) => false));
        Assert.True(Directory.Exists(young));
    }

    [Theory]
    [InlineData("plantoir-ownedtest-abc")]
    [InlineData("plantoir-ownedtest-12-x")]
    [InlineData("plantoir-ownedtest--1-2-x")]
    public void AFolderWhoseNameDoesNotNameAnOwnerIsNeverSwept(string name)
    {
        string folder = Make(name, TimeSpan.FromDays(3));
        Assert.Empty(RunOwnedTempFolders.SweepOrphans(Prefix, root: _root, ownerIsAlive: (_, _) => false));
        Assert.True(Directory.Exists(folder));
    }

    /// <summary>Older copies of the suite, still running in other worktrees, delete these patterns: the new folders must not match them.</summary>
    [Theory]
    [InlineData("plantoir-probe*")]
    [InlineData("plantoir-581-*")]
    public void TheNewFoldersDoNotMatchWhatOlderCopiesOfTheSuiteSweep(string oldPattern)
    {
        foreach (string prefix in new[] { StubProgramCollection.FolderPrefix, ObsidianFigureAddOnsTests.RootPrefix })
        {
            string name = prefix + RunOwnedTempFolders.ThisRun + "-abcdefgh.ijk";
            Assert.False(FileSystemName.MatchesWin32Expression(oldPattern, name, ignoreCase: true), $"{name} matches {oldPattern}");
        }
        Assert.StartsWith(StubProgramCollection.FolderPrefix, Path.GetFileName(StubProgramCollection.StubFolder));
    }
}
