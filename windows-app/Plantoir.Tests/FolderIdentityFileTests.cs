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
        // The look found an empty file old enough to be damaged; the creator
        // that made it (no hard links, an exclusive create and one write) then
        // wrote its identifier into the SAME file before the move. It is still
        // the file inspected, so it is moved, found to hold an identifier, and
        // put back.
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllBytes(IdPath, []);
        var clock = new UndoTestClock(File.GetLastWriteTimeUtc(IdPath) + TimeSpan.FromMinutes(5));
        FolderIdentityFile.Answer look = File_(clock).Read();
        Assert.Equal(FolderIdentityFile.Outcome.Unreadable, look.Outcome);
        Assert.NotNull(look.Inspected);

        string id = Guid.NewGuid().ToString("D");
        using (var sameFile = new FileStream(IdPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
            sameFile.Write(Encoding.ASCII.GetBytes(id + "\n"));
        Assert.Equal(look.Inspected, FolderIdentityFile.FileIdentity(IdPath));

        Assert.Equal(id, File_(clock).SetAside(look.Inspected));
        Assert.Equal(id + "\n", File.ReadAllText(IdPath));
        Assert.Empty(Directory.GetFiles(Path.GetDirectoryName(IdPath)!, "folder-id.unreadable-*"));
    }

    [Fact]
    public void AGoodFileThatReplacedTheOneInspectedIsNeverMovedAside()
    {
        // The W1 review's H1. Process 1 looks and finds the file damaged;
        // process 2 sets it aside and makes a good one, G; process 1 then
        // asks to set aside what it looked at. G is a different file, so it
        // stays where it is (the seam, which would make a third file, never
        // runs). Before the first fix SetAside compared the file with itself
        // and moved G aside.
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllText(IdPath, "not an identifier\n");
        FolderIdentityFile.Answer look = File_().Read();
        Assert.Equal(FolderIdentityFile.Outcome.Unreadable, look.Outcome);

        File.Move(IdPath, IdPath + ".unreadable-" + Guid.NewGuid().ToString("D"));
        string good = Guid.NewGuid().ToString("D");
        File.WriteAllText(IdPath, good + "\n");

        string other = Guid.NewGuid().ToString("D");
        var late = new FolderIdentityFile(IdPath, new UndoTestClock(DateTimeOffset.UtcNow + TimeSpan.FromHours(1)),
            betweenCheckAndRename: () => File.WriteAllText(IdPath, other + "\n"));
        late.SetAside(look.Inspected);

        Assert.Equal(good + "\n", File.ReadAllText(IdPath));
        Assert.Single(Directory.GetFiles(Path.GetDirectoryName(IdPath)!, "folder-id.unreadable-*"));   // process 2's, only
        Assert.Equal(good, File_().ReadOrMake());
    }

    [Fact]
    public void ALookThatOpenedNothingSetsNothingAside()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllText(IdPath, "not an identifier\n");
        Assert.Null(File_().SetAside(null));
        Assert.Equal("not an identifier\n", File.ReadAllText(IdPath));
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

    [Fact]
    public void AFileSetAsideByAnotherProcessBetweenTheCheckAndTheRenameIsNeverTheGoodOne()
    {
        // The W1 review's second round. This process finds the file damaged,
        // and finds it is still the file inspected; THEN (the seam) another
        // process sets that same damaged file aside and makes a good one, G.
        // What this process renames must be the file it inspected, wherever it
        // now is, never G: the rename goes through the handle it compared.
        //
        // The third maker (the round-two fix review): straight after this
        // process's rename, a third process finds the name free if, and only
        // if, G was the file moved, and makes its own identifier there. Without
        // it, a rename by path moved G aside, saw it was not the file inspected
        // and moved it back unharmed, so this test passed with the fix
        // reverted. With it, the move back is refused, G is stranded aside, and
        // the name holds the third identifier: every step under G is lost.
        Directory.CreateDirectory(Path.GetDirectoryName(IdPath)!);
        File.WriteAllText(IdPath, "not an identifier\n");
        FolderIdentityFile.Answer look = File_().Read();
        Assert.Equal(FolderIdentityFile.Outcome.Unreadable, look.Outcome);

        string good = Guid.NewGuid().ToString("D");
        string theirs = IdPath + ".unreadable-" + Guid.NewGuid().ToString("D");
        var racing = new FolderIdentityFile(IdPath, new UndoTestClock(DateTimeOffset.UtcNow + TimeSpan.FromHours(1)),
            betweenCheckAndRename: () =>
            {
                File.Move(IdPath, theirs);
                File.WriteAllText(IdPath, good + "\n");
            },
            afterRename: () => File_().MakeExclusively());   // the third maker: makes one only if the name is free
        racing.SetAside(look.Inspected);

        Assert.Equal(good + "\n", File.ReadAllText(IdPath));
        string[] aside = Directory.GetFiles(Path.GetDirectoryName(IdPath)!, "folder-id.unreadable-*");
        Assert.Single(aside);
        Assert.Equal("not an identifier\n", File.ReadAllText(aside[0]));
        Assert.Equal(good, File_().ReadOrMake());
    }
}
