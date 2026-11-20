using System.Diagnostics;
using System.Text;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The staged swap (#899 W2b, <c>rule.stagedThenSwapped</c>) against real
/// Windows file semantics: real holders, a real read-only bit, a real
/// junction. Each test is named for one sentence of the rule or one finding
/// of the plan review (M4, M5, L4) and was seen to fail with that behaviour
/// taken out (vm-tools/guest/899-w2b-mustfail.json).
/// </summary>
public sealed class UndoSwapTests : IDisposable
{
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-swap-");

    public void Dispose()
    {
        foreach (string file in Directory.Exists(_root) ? Directory.EnumerateFiles(_root, "*", SearchOption.AllDirectories) : [])
        {
            try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
        }
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static readonly byte[] Old = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: false\n---\nBody.\n");
    private static readonly byte[] New = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: true\n---\nBody.\n");

    private string Page(string relative, byte[] bytes)
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    private UndoSwapTarget Target(string relative, byte[]? expected, byte[]? replacement) =>
        new(Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar)), relative, expected, replacement);

    private static byte[] ReadShared(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return memory.ToArray();
    }

    private IReadOnlyList<string> StagedLeft() => UndoStepContractTests.StagedFilesUnder(_root);

    /// <summary>The planner's P7: the POSIX-semantics rename goes in under a holder that shares delete (Obsidian), where MoveFileEx is refused 5.</summary>
    [Fact]
    public void ASwapGoesInUnderAHolderThatSharesDelete()
    {
        string page = Page("courses/A/a.md", Old);
        using (var holder = new FileStream(page, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        {
            UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New)], "1-undo", _root);
            Assert.IsType<UndoSwapResult.Swapped>(result);
        }
        Assert.Equal(New, ReadShared(page));
        Assert.Empty(StagedLeft());
    }

    /// <summary>A holder that does not share delete (Word) refuses the rename: the earlier swap is reversed, the file named, nothing staged left.</summary>
    [Fact]
    public void AHolderThatDoesNotShareDeleteIsRefusedNamedAndTheEarlierSwapsReversed()
    {
        string first = Page("courses/A/a.md", Old);
        string second = Page("courses/A/b.md", Old);
        UndoSwapResult result;
        using (var holder = new FileStream(second, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        {
            result = UndoSwap.Swap([Target("courses/A/a.md", Old, New), Target("courses/A/b.md", Old, New)], "1-undo", _root);
        }
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(new UndoRefusal(UndoRefusalKind.FileIsInUse, "courses/A/b.md"), refused.Refusal);
        Assert.Equal(Old, File.ReadAllBytes(first));
        Assert.Equal(Old, File.ReadAllBytes(second));
        Assert.Empty(StagedLeft());
    }

    /// <summary>The plan review's M4: a read-only page is never forced; it is refused couldNotWrite (never "in use") and left read-only and whole.</summary>
    [Fact]
    public void AReadOnlyPageIsRefusedCouldNotWriteAndStaysReadOnly()
    {
        string page = Page("courses/A/a.md", Old);
        File.SetAttributes(page, FileAttributes.ReadOnly);
        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New)], "1-undo", _root);
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(UndoRefusalKind.CouldNotWrite, refused.Refusal.Kind);
        Assert.True(File.GetAttributes(page).HasFlag(FileAttributes.ReadOnly));
        Assert.Equal(Old, File.ReadAllBytes(page));
        Assert.Empty(StagedLeft());
    }

    /// <summary>The plan review's M4: whatever the staged file carries the page becomes, so the page's own attributes (Hidden) and creation time are copied onto it before the rename.</summary>
    [Fact]
    public void ThePageKeepsItsAttributesAndCreationTime()
    {
        string page = Page("courses/A/a.md", Old);
        var created = new DateTime(2020, 1, 1, 8, 0, 0, DateTimeKind.Utc);
        File.SetCreationTimeUtc(page, created);
        File.SetAttributes(page, FileAttributes.Hidden | FileAttributes.Archive);
        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New)], "1-undo", _root);
        Assert.IsType<UndoSwapResult.Swapped>(result);
        Assert.Equal(New, File.ReadAllBytes(page));
        Assert.True(File.GetAttributes(page).HasFlag(FileAttributes.Hidden), "the page lost its Hidden attribute");
        Assert.Equal(created, File.GetCreationTimeUtc(page));
    }

    /// <summary>U1's F1: a staging write that fails removes the file it made and every other, swaps nothing, and is couldNotWrite.</summary>
    [Fact]
    public void AStagingWriteThatFailsLeavesNoStagedFileAndSwapsNothing()
    {
        string first = Page("courses/A/a.md", Old);
        string second = Page("courses/A/b.md", Old);
        var seams = new UndoSeams { StagingWriteFailsAt = index => index == 1 };
        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New), Target("courses/A/b.md", Old, New)], "1-undo", _root, seams);
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(new UndoRefusal(UndoRefusalKind.CouldNotWrite, "courses/A/b.md"), refused.Refusal);
        Assert.Equal(Old, File.ReadAllBytes(first));
        Assert.Equal(Old, File.ReadAllBytes(second));
        Assert.Empty(StagedLeft());
    }

    /// <summary>The plan review's M5: on a share every swap takes MoveFileEx, which a delete-sharing holder refuses; the refusal is the same, the earlier swap reversed.</summary>
    [Fact]
    public void TheFallbackRenameRefusesTheSameWayUnderAHolder()
    {
        string first = Page("courses/A/a.md", Old);
        string second = Page("courses/A/b.md", Old);
        var seams = new UndoSeams { PosixRenameIsNotSupported = true };
        UndoSwapResult result;
        using (var holder = new FileStream(second, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        {
            result = UndoSwap.Swap([Target("courses/A/a.md", Old, New), Target("courses/A/b.md", Old, New)], "1-undo", _root, seams);
        }
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(new UndoRefusal(UndoRefusalKind.FileIsInUse, "courses/A/b.md"), refused.Refusal);
        Assert.Equal(Old, File.ReadAllBytes(first));
        Assert.Empty(StagedLeft());
        // With nothing held the fallback swaps.
        Assert.IsType<UndoSwapResult.Swapped>(UndoSwap.Swap([Target("courses/A/b.md", Old, New)], "2-undo", _root, seams));
        Assert.Equal(New, File.ReadAllBytes(second));
    }

    /// <summary>Every P/Invoke path takes the <c>\\?\</c> form past 259 characters: a page whose staged name is past it swaps.</summary>
    [Fact]
    public void APagePastTheOldPathLimitSwaps()
    {
        string relative = "courses/A/" + string.Join("/", Enumerable.Repeat(new string('f', 40), 6)) + "/a page with a long name.md";
        string page = Page(relative, Old);
        Assert.True(page.Length > 260);
        Assert.IsType<UndoSwapResult.Swapped>(UndoSwap.Swap([Target(relative, Old, New)], "1-undo", _root));
        Assert.Equal(New, File.ReadAllBytes(page));
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// The plan review's L4: an edit written into the page in place between the
    /// check's re-read and the rename shows in the hard-linked original. The
    /// step is reversed, which puts the teacher's edit back, and refused as
    /// changed since.
    /// </summary>
    [Fact]
    public void AnEditThatRacesTheSwapIsPutBackAndTheSwapRefused()
    {
        string page = Page("courses/A/a.md", Old);
        byte[] edit = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: false # checked\n---\nBody.\n");
        var seams = new UndoSeams
        {
            BetweenKeepingAndRenaming = (_, fullPath) =>
            {
                using var inPlace = new FileStream(fullPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                inPlace.Write(edit);
                inPlace.SetLength(edit.Length);
            },
        };
        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New)], "1-undo", _root, seams);
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        Assert.Equal(edit, File.ReadAllBytes(page));
        Assert.Empty(StagedLeft());
    }

    /// <summary><c>rule.stagedThenSwapped</c>: each target is re-read just before its swap and must hold what the check saw.</summary>
    [Fact]
    public void APageChangedJustBeforeItsSwapIsChangedSinceAndNothingIsWritten()
    {
        string first = Page("courses/A/a.md", Old);
        string second = Page("courses/A/b.md", Old);
        byte[] edit = Encoding.UTF8.GetBytes("written by hand\n");
        var seams = new UndoSeams { BeforeEachSwap = (index, fullPath) => { if (index == 1) File.WriteAllBytes(fullPath, edit); } };
        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New), Target("courses/A/b.md", Old, New)], "1-undo", _root, seams);
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(new UndoRefusal(UndoRefusalKind.ChangedSince, "courses/A/b.md"), refused.Refusal);
        Assert.Equal(Old, File.ReadAllBytes(first));
        Assert.Equal(edit, File.ReadAllBytes(second));
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// The same re-read when the page was deleted by hand just before its swap:
    /// changed since, and the page is not made again. (An edit in place is
    /// also caught after the rename by the kept original, L4; a deletion leaves
    /// no original, so only the re-read can stop it.)
    /// </summary>
    [Fact]
    public void APageDeletedJustBeforeItsSwapIsChangedSinceAndNotMadeAgain()
    {
        string first = Page("courses/A/a.md", Old);
        string second = Page("courses/A/b.md", Old);
        var seams = new UndoSeams { BeforeEachSwap = (index, fullPath) => { if (index == 1) File.Delete(fullPath); } };
        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New), Target("courses/A/b.md", Old, New)], "1-undo", _root, seams);
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(new UndoRefusal(UndoRefusalKind.ChangedSince, "courses/A/b.md"), refused.Refusal);
        Assert.Equal(Old, File.ReadAllBytes(first));
        Assert.False(File.Exists(second), "a page the teacher deleted was made again");
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// <c>rule.stagedThenSwapped</c>: "a place that now leads outside (a folder
    /// on its path replaced by a link) is a change since, and nothing is moved
    /// through it". The folder is replaced by a junction to a folder OUTSIDE the
    /// working folder holding the very bytes the check saw, so only the
    /// containment check can stop the swap.
    /// </summary>
    [Fact]
    public void AFolderOnThePathReplacedByAJunctionToOutsideIsChangedSinceAndNothingOutsideIsTouched()
    {
        string root = Path.Combine(_root, "wf");
        string outside = Path.Combine(_root, "outside");
        Directory.CreateDirectory(outside);
        File.WriteAllBytes(Path.Combine(outside, "a.md"), Old);
        string folder = Path.Combine(root, "courses", "A");
        Directory.CreateDirectory(folder);
        File.WriteAllBytes(Path.Combine(folder, "a.md"), Old);
        var seams = new UndoSeams
        {
            BeforeEachSwap = (_, _) =>
            {
                Directory.Move(folder, folder + "-moved");
                MakeAJunction(folder, outside);
            },
        };
        var target = new UndoSwapTarget(Path.Combine(folder, "a.md"), "courses/A/a.md", Old, New);
        UndoSwapResult result = UndoSwap.Swap([target], "1-undo", root, seams);
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        Assert.Equal(Old, File.ReadAllBytes(Path.Combine(outside, "a.md")));
        Assert.Equal(["a.md"], Directory.EnumerateFileSystemEntries(outside).Select(Path.GetFileName).ToArray());
        Directory.Delete(folder);   // the junction only
    }

    internal static void MakeAJunction(string link, string target)
    {
        using var mklink = Process.Start(new ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{target}\"")
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
        })!;
        mklink.WaitForExit();
        Assert.True(mklink.ExitCode == 0 && Directory.Exists(link), "a junction could not be made: " + mklink.StandardError.ReadToEnd());
    }
}
