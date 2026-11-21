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
        // Between the check and the swap (during the swap Windows will not
        // move the folder at all while a staged file is open in it: W3's
        // WhileASwapIsUnderWayTheFoldersOfItsPagesCannotBeMovedOrReplaced).
        Directory.Move(folder, folder + "-moved");
        MakeAJunction(folder, outside);
        var target = new UndoSwapTarget(Path.Combine(folder, "a.md"), "courses/A/a.md", Old, New);
        UndoSwapResult result = UndoSwap.Swap([target], "1-undo", root);
        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        Assert.Equal(Old, File.ReadAllBytes(Path.Combine(outside, "a.md")));
        Assert.Equal(["a.md"], Directory.EnumerateFileSystemEntries(outside).Select(Path.GetFileName).ToArray());
        Directory.Delete(folder);   // the junction only
    }

    // ---- W2b's review LOWs 2, 3, 4 and 8 (fixed in W3) ---------------------------

    /// <summary>
    /// LOW 2, made impossible rather than detected: while a swap is under way
    /// Windows refuses to move the folder of any of its pages (a staged file,
    /// or for a page the step removes its kept original, is open in it), so no
    /// junction can be put in its place between the re-read and the rename and
    /// nothing of the swap can be left in a folder moved aside. Both kinds of
    /// page, at both moments.
    /// </summary>
    [Fact]
    public void WhileASwapIsUnderWayTheFoldersOfItsPagesCannotBeMovedOrReplaced()
    {
        string root = Path.Combine(_root, "wf");
        string replaced = Path.Combine(root, "courses", "A");
        string removed = Path.Combine(root, "courses", "B");
        Directory.CreateDirectory(replaced);
        Directory.CreateDirectory(removed);
        File.WriteAllBytes(Path.Combine(replaced, "a.md"), Old);
        File.WriteAllBytes(Path.Combine(removed, "b.md"), Old);
        var refusedMoves = new List<string>();
        void TryToMove(int index, string path)
        {
            string folder = Path.GetDirectoryName(path)!;
            try
            {
                Directory.Move(folder, folder + "-moved");
                Directory.Move(folder + "-moved", folder);
            }
            catch (IOException) { refusedMoves.Add(Path.GetFileName(folder)); }
        }
        var seams = new UndoSeams { BeforeEachSwap = TryToMove, BetweenKeepingAndRenaming = TryToMove };
        UndoSwapResult result = UndoSwap.Swap(
            [new UndoSwapTarget(Path.Combine(replaced, "a.md"), "courses/A/a.md", Old, New),
             new UndoSwapTarget(Path.Combine(removed, "b.md"), "courses/B/b.md", Old, null)], "1-apply", root, seams);
        Assert.IsType<UndoSwapResult.Swapped>(result);
        // a.md's folder is held by its staged content at both moments; b.md's
        // by its kept original only once it is kept.
        Assert.Equal(["A", "A", "B"], refusedMoves);
        Assert.Equal(New, File.ReadAllBytes(Path.Combine(replaced, "a.md")));
        Assert.False(File.Exists(Path.Combine(removed, "b.md")));
        Assert.Empty(StagedLeft());
        // Once the swap has ended nothing holds either folder.
        Directory.Move(replaced, replaced + "-moved");
        Directory.Move(removed, removed + "-moved");
    }

    /// <summary>LOW 2: a kept original is removed by name only while the name is still that file; a name that now holds another file removes nothing.</summary>
    [Fact]
    public void AKeptOriginalWhoseNameNowHoldsAnotherFileIsNotRemoved()
    {
        string page = Page("courses/A/a.md", Old);
        string kept = UndoSwap.BesidePath(page, "1-undo", "orig");
        UndoStagedFile original = UndoStagedFile.Keep(page, kept, out _)!;
        File.Delete(kept);
        File.WriteAllBytes(kept, New);   // another file under the same name
        Assert.False(original.Remove());
        Assert.Equal(New, File.ReadAllBytes(kept));
        Assert.Equal(Old, File.ReadAllBytes(page));
        File.Delete(kept);
    }

    /// <summary>
    /// LOW 3: an editor that saves by REPLACING the page (a new file renamed
    /// over it) between the keep and the rename: the page is no longer the
    /// file the original was kept from, so the swap is refused changed since
    /// and the editor's save is kept. The kept link's hash cannot see it (it
    /// is still the old bytes); only the file identity can.
    /// </summary>
    [Fact]
    public void AnEditorThatSavesByReplacingThePageBeforeTheRenameKeepsItsSave()
    {
        string page = Page("courses/A/a.md", Old);
        byte[] saved = Encoding.UTF8.GetBytes("---\ntitle: A\npublish: false\n---\nWhat the teacher saved.\n");
        var seams = new UndoSeams
        {
            BetweenKeepingAndRenaming = (_, path) =>
            {
                string temporary = path + ".editor-tmp";
                File.WriteAllBytes(temporary, saved);
                File.Move(temporary, path, overwrite: true);
            },
        };
        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New)], "1-undo", _root, seams);
        Assert.Equal(UndoRefusalKind.ChangedSince, Assert.IsType<UndoSwapResult.Refused>(result).Refusal.Kind);
        Assert.Equal(saved, ReadShared(page));
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// LOW 4: a page made read-only between the keep and the rename: the
    /// rename is refused couldNotWrite, and removing the kept original (a hard
    /// link, so it shares the page's attributes) leaves the page read-only:
    /// its attribute is ignored for the delete, never cleared.
    /// </summary>
    [Fact]
    public void RemovingAKeptOriginalNeverClearsThePagesReadOnlyBit()
    {
        string page = Page("courses/A/a.md", Old);
        var seams = new UndoSeams { BetweenKeepingAndRenaming = (_, path) => File.SetAttributes(path, FileAttributes.ReadOnly) };
        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New)], "1-undo", _root, seams);
        Assert.Equal(UndoRefusalKind.CouldNotWrite, Assert.IsType<UndoSwapResult.Refused>(result).Refusal.Kind);
        Assert.True(File.GetAttributes(page).HasFlag(FileAttributes.ReadOnly));
        Assert.Equal(Old, ReadShared(page));
        Assert.Empty(StagedLeft());
    }

    /// <summary>LOW 4, the tidy: a kept original a stopped swap left (a link to the live, read-only page) is removed without clearing the page's read-only bit.</summary>
    [Fact]
    public void TheTidyOfALeftoverLinkNeverClearsThePagesReadOnlyBit()
    {
        string root = Path.Combine(_root, "wf");
        string page = Path.Combine(root, "courses", "A", "a.md");
        Directory.CreateDirectory(Path.GetDirectoryName(page)!);
        File.WriteAllBytes(page, Old);
        string kept = UndoSwap.BesidePath(page, "7-apply", "orig");
        Assert.NotNull(UndoStagedFile.Keep(page, kept, out _));
        File.SetAttributes(page, FileAttributes.ReadOnly);
        Assert.True(UndoSwap.TidyLeftovers(7, ["courses/A/a.md"], root));
        Assert.False(File.Exists(kept));
        Assert.True(File.GetAttributes(page).HasFlag(FileAttributes.ReadOnly));
        Assert.Equal(Old, ReadShared(page));
    }

    /// <summary>LOW 8: OneDrive's Pinned and Unpinned are attributes the page keeps across a swap (they stick on any NTFS file, measured).</summary>
    [Theory]
    [InlineData(0x00080000)]
    [InlineData(0x00100000)]
    public void ThePageKeepsItsOneDrivePinning(int attribute)
    {
        var pinning = (FileAttributes)attribute;
        string page = Page("courses/A/a.md", Old);
        File.SetAttributes(page, FileAttributes.Archive | pinning);
        Assert.True(File.GetAttributes(page).HasFlag(pinning), "the attribute does not stick on this volume");
        Assert.IsType<UndoSwapResult.Swapped>(UndoSwap.Swap([Target("courses/A/a.md", Old, New)], "1-undo", _root));
        Assert.Equal(New, ReadShared(page));
        Assert.True(File.GetAttributes(page).HasFlag(pinning));
    }

    private UndoSwapTarget FolderTakenOut(string relative)
    {
        string full = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        return new UndoSwapTarget(full, relative, null, null) { Change = new UndoSwapChange.TakeTree(UndoTreeReading.Read(full).ListingSha) };
    }

    /// <summary>
    /// W4c review 1, LOW 1 (the mac's U3c, first review, LOW 3): a folder taken
    /// out whose <c>-orig</c> name already holds a folder set aside (step
    /// numbers that collided) takes the next free kept name; it is never
    /// refused for good, and the folder already aside is left as it was.
    /// </summary>
    [Fact]
    public void AFolderTakenOutTakesTheNextFreeKeptName()
    {
        Page("courses/A/extra/x.md", Old);
        string folder = Path.Combine(_root, "courses", "A", "extra");
        string alreadyAside = UndoSwap.BesidePath(folder, "1-apply", "orig");
        Directory.CreateDirectory(alreadyAside);
        File.WriteAllBytes(Path.Combine(alreadyAside, "y.md"), New);

        UndoSwapResult result = UndoSwap.Swap([FolderTakenOut("courses/A/extra")], "1-apply", _root);

        Assert.IsType<UndoSwapResult.Swapped>(result);
        Assert.False(Directory.Exists(folder));
        Assert.Equal(New, File.ReadAllBytes(Path.Combine(alreadyAside, "y.md")));
        Assert.False(Directory.Exists(UndoSwap.BesidePath(folder, "1-apply", "2-orig")));
    }

    /// <summary>W4c review 1, LOW 2, for a folder: every kept name taken is could not write (the mac's couldNotWrite), never "in use", and the folder stays.</summary>
    [Fact]
    public void AFolderTakenOutWithEveryKeptNameTakenIsCouldNotWrite()
    {
        Page("courses/A/extra/x.md", Old);
        string folder = Path.Combine(_root, "courses", "A", "extra");
        for (int number = 1; number <= UndoSwap.KeptNames; number++)
            Directory.CreateDirectory(UndoSwap.BesidePath(folder, "1-apply", number == 1 ? "orig" : number + "-orig"));

        UndoSwapResult result = UndoSwap.Swap([FolderTakenOut("courses/A/extra")], "1-apply", _root);

        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(new UndoRefusal(UndoRefusalKind.CouldNotWrite, "courses/A/extra"), refused.Refusal);
        Assert.Equal(Old, File.ReadAllBytes(Path.Combine(folder, "x.md")));
    }

    /// <summary>W4c review 1, LOW 2: a page whose every kept name is taken is could not write (the mac's UndoCheck couldNotWrite), never "in use", and stays as it was.</summary>
    [Fact]
    public void APageWithEveryKeptNameTakenIsCouldNotWrite()
    {
        string page = Page("courses/A/a.md", Old);
        for (int number = 1; number <= UndoSwap.KeptNames; number++)
            File.WriteAllBytes(UndoSwap.BesidePath(page, "1-undo", number == 1 ? "orig" : number + "-orig"), New);

        UndoSwapResult result = UndoSwap.Swap([Target("courses/A/a.md", Old, New)], "1-undo", _root);

        var refused = Assert.IsType<UndoSwapResult.Refused>(result);
        Assert.Equal(new UndoRefusal(UndoRefusalKind.CouldNotWrite, "courses/A/a.md"), refused.Refusal);
        Assert.Equal(Old, File.ReadAllBytes(page));
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
