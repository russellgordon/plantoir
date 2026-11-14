using System.Text;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>undoJournal.identifierFiles</c>: <c>folder-id</c> and <c>computer-id</c>,
/// written lower case with one line feed and no byte-order mark, made
/// exclusively, read leniently, and a damaged one set aside, never a block
/// (#899 piece W1). The clock is the test's, so "less than ten seconds ago" is
/// never waited for.
/// </summary>
public sealed class FolderIdentityFileTests : IDisposable
{
    private readonly string _folder = RunOwnedTempFolders.Create("plantoir-undo-id-");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string IdPath => Path.Combine(_folder, "courses", ".internal", "folder-id");

    private FolderIdentityFile File_(TimeProvider? clock = null, Func<string, string, bool>? hardLink = null) =>
        new(IdPath, clock ?? new UndoTestClock(DateTimeOffset.UtcNow + TimeSpan.FromHours(1)), hardLink);

    [Fact]
    public void MadeOnceWrittenLowerCaseWithOneLineFeedAndNoByteOrderMark()
    {
        string id = File_().ReadOrMake()!;
        byte[] bytes = File.ReadAllBytes(IdPath);
        Assert.Equal(Encoding.ASCII.GetBytes(id + "\n"), bytes);
        Assert.Equal(id.ToLowerInvariant(), id);
        Assert.True(Guid.TryParseExact(id, "D", out _));
        Assert.Equal(id, File_().ReadOrMake());   // never replaced while it holds one
        Assert.Empty(Directory.GetFiles(Path.GetDirectoryName(IdPath)!, "*.tmp-*"));
    }

    [Theory]
    [InlineData("﻿{0}\r\n")]
    [InlineData("  {0}  \n\n")]
    [InlineData("{0}")]
    public void ReadLenientlyInEitherCase(string shape)
    {
        string id = Guid.NewGuid().ToString("D");
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllText(IdPath, string.Format(shape, id.ToUpperInvariant()), new UTF8Encoding(false));
        Assert.Equal(id, File_().ReadOrMake());
    }

    [Fact]
    public void TwoMakersAtOnceEndWithOneIdentifier()
    {
        var ids = new System.Collections.Concurrent.ConcurrentBag<string?>();
        Parallel.For(0, 8, _ => ids.Add(File_().ReadOrMake()));
        Assert.Single(ids.Where(id => id is not null).Distinct());
    }

    [Fact]
    public void WithoutHardLinksTheNameIsMadeWithAnExclusiveCreate()
    {
        string id = File_(hardLink: (_, _) => false).ReadOrMake()!;
        Assert.Equal(Encoding.ASCII.GetBytes(id + "\n"), File.ReadAllBytes(IdPath));
        // And the exclusive create refuses a name that exists.
        Assert.Null(File_(hardLink: (_, _) => false).MakeExclusively());
        Assert.Equal(id, File_().ReadOrMake());
    }

    [Fact]
    public void AnEmptyFileWrittenLessThanTenSecondsAgoIsACreatorAtWork()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllBytes(IdPath, []);
        DateTimeOffset written = File.GetLastWriteTimeUtc(IdPath);
        var clock = new UndoTestClock(written + TimeSpan.FromSeconds(3));
        Assert.Equal(FolderIdentityFile.Outcome.NotYet, File_(clock).Read().Outcome);
        Assert.Null(File_(clock).ReadOrMake());
        Assert.Equal(0, new FileInfo(IdPath).Length);   // left alone

        clock.Advance(TimeSpan.FromSeconds(10));
        string? made = File_(clock).ReadOrMake();
        Assert.NotNull(made);
        Assert.Single(Directory.GetFiles(Path.GetDirectoryName(IdPath)!, "folder-id.unreadable-*"));
    }

    [Fact]
    public void ADamagedFileIsSetAsideAndANewOneMade()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllText(IdPath, "not an identifier\n");
        string id = File_().ReadOrMake()!;
        Assert.NotNull(id);
        string aside = Assert.Single(Directory.GetFiles(Path.GetDirectoryName(IdPath)!, "folder-id.unreadable-*"));
        Assert.Equal("not an identifier\n", File.ReadAllText(aside));
    }

    [Fact]
    public void AFileThatHoldsAnIdentifierOnceAsideIsPutBack()
    {
        // Another process wrote an identifier between the look and the move:
        // simulated by asking SetAside of a file that holds one.
        string id = Guid.NewGuid().ToString("D");
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllText(IdPath, id + "\n");
        Assert.Equal(id, File_().SetAside());
        Assert.Equal(id + "\n", File.ReadAllText(IdPath));
        Assert.Empty(Directory.GetFiles(Path.GetDirectoryName(IdPath)!, "folder-id.unreadable-*"));
    }

    [Fact]
    public void TheSameFileIsKnownByItsVolumeAndIndex()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllText(IdPath, "x");
        var first = FolderIdentityFile.FileIdentity(IdPath);
        Assert.NotNull(first);
        Assert.Equal(first, FolderIdentityFile.FileIdentity(IdPath));
        File.Delete(IdPath);
        File.WriteAllText(IdPath, "x");
        // A new file under the same name (NTFS gives it a new index).
        Assert.NotEqual(first, FolderIdentityFile.FileIdentity(IdPath));
    }
}
