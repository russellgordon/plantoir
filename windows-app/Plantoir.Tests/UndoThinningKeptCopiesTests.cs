using System.Text;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// After a move through the door, the step's kept copies beside a page are
/// thinned to ONE per content (#899 W8-10b; the mac's
/// <c>UndoRecovery.removeSupersededKeptCopies</c>, called in its door after
/// the move finishes and before the kept line, and its
/// <c>UndoKeptCopiesTests.testUndoAndRedoAgainAndAgainKeepOneCopyPerContent</c>).
/// The copy this move made is the one kept for its content, otherwise the
/// first by name; a copy that is the only one of its content is never removed.
/// </summary>
public sealed class UndoThinningKeptCopiesTests
{
    // MARK: - Stored properties

    private const string PagePath = "courses/TST1O/section1/p1.md";

    private static readonly byte[] Before = Encoding.UTF8.GetBytes("What the page held before.\n");
    private static readonly byte[] After = Encoding.UTF8.GetBytes("What the step left in the page.\n");

    // MARK: - Functions

    /// <summary>
    /// Both contents gone from the list and the list taking no new file, then
    /// seven moves: the page ends as it was before, and what is kept beside it
    /// is one file per content, what the Redo needs among them. MUST FAIL with
    /// the thinning off: piece 10 measured 8 files holding 2 contents.
    /// </summary>
    [Fact]
    public void UndoAndRedoAgainAndAgainKeepOneCopyPerContent()
    {
        using var scribe = new UndoScribe();
        scribe.WritePage("A", PagePath, Before);
        long seq = scribe.Step("A", [(PagePath, After)])!.Value;
        string page = scribe.FullPath("A", PagePath);
        File.WriteAllBytes(UndoSwap.BesidePath(page, $"{seq}-apply", "orig"), Before);
        using (var denials = new UndoDenials())
        {
            foreach (byte[] content in new[] { Before, After })
            {
                string blob = scribe.Journal.BlobPath(UndoCheck.Sha(content));
                if (File.Exists(blob)) File.Delete(blob);
                denials.FolderTakesNothingNew(Path.GetDirectoryName(blob)!);
            }
            for (int move = 0; move < 7; move++)
            {
                string outcome = move % 2 == 0 ? scribe.Undo().Name : scribe.Redo().Name;
                Assert.Equal(move % 2 == 0 ? "undone" : "redone", outcome);
            }
        }
        Assert.Equal(Before, scribe.Page("A", PagePath));
        List<string> kept = UndoRecovery.KeptOriginalFiles(scribe.Fold().Steps[seq].Step, page);
        var contents = new HashSet<string>(StringComparer.Ordinal);
        foreach (string file in kept) contents.Add(UndoCheck.Sha(File.ReadAllBytes(file)));
        Assert.True(kept.Count <= 2, string.Join(", ", kept));
        Assert.Contains(UndoCheck.Sha(After), contents);
        Assert.Equal(kept.Count, contents.Count);
    }

    /// <summary>
    /// The choice rule, as the mac's: for a content held twice, the copy made
    /// by the newest label is kept (the earlier one removed), and with no copy
    /// of the newest label the first by name is kept. A copy that is the only
    /// one of its content stays, whatever its label. MUST FAIL with the newest
    /// copy removed instead of an older one, and with every copy not of the
    /// newest label removed.
    /// </summary>
    [Fact]
    public void TheNewestCopyIsKeptAndTheOnlyCopyOfAContentIsNeverRemoved()
    {
        using var scribe = new UndoScribe();
        scribe.WritePage("A", PagePath, Before);
        long seq = scribe.Step("A", [(PagePath, After)])!.Value;
        UndoStep step = scribe.Fold().Steps[seq].Step;
        string page = scribe.FullPath("A", PagePath);
        byte[] onlyOnce = Encoding.UTF8.GetBytes("A content kept once.\n");
        string applyKept = UndoSwap.BesidePath(page, $"{seq}-apply", "orig");
        string redoKept = UndoSwap.BesidePath(page, $"{seq}-redo", "orig");
        string undoKept = UndoSwap.BesidePath(page, $"{seq}-undo", "orig");
        File.WriteAllBytes(applyKept, Before);
        File.WriteAllBytes(redoKept, Before);
        File.WriteAllBytes(undoKept, onlyOnce);

        UndoRecovery.RemoveSupersededKeptCopies(step, scribe.FullPath("A", ""), [PagePath], $"{seq}-redo");
        Assert.False(File.Exists(applyKept), "the earlier copy of a content the newest move kept again is removed");
        Assert.True(File.Exists(redoKept), "the newest copy of its content is kept");
        Assert.True(File.Exists(undoKept), "the only copy of its content is never removed");

        File.WriteAllBytes(applyKept, Before);
        UndoRecovery.RemoveSupersededKeptCopies(step, scribe.FullPath("A", ""), [PagePath], $"{seq}-undo");
        Assert.True(File.Exists(applyKept), "with no copy of the newest label, the first by name is kept");
        Assert.False(File.Exists(redoKept), "the later copy by name is removed");
        Assert.True(File.Exists(undoKept), "the only copy of its content is never removed");
    }
}
