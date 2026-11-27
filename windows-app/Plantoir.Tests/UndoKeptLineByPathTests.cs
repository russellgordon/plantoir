using System.Text;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The trail line <c>undo kept what it replaced</c> decides "from what was
/// kept beside it" of each page by its PATH in the working folder, never by
/// its file name alone (#899 W8-9; the mac's U4b2-4, documentation 12, "What
/// W4c owes from U4b2-4", items 1 to 6; the mac's <c>UndoKeptCopiesTests</c>,
/// its U4b2-4 section). A named page whose file name another page of the step
/// shares is named by its path inside the course; a page outside
/// <c>courses/&lt;course&gt;/</c>, or in a step with no course, by its path in
/// the working folder. The hidden file is always its bare name, and the
/// line's list of files stays the kept files' bare names. Names and prefixes
/// are compared in Unicode normalization form C, then ordinally.
/// </summary>
public sealed class UndoKeptLineByPathTests
{
    // MARK: - Stored properties

    private const string FirstIndex = "courses/TST1O/section1/index.md";
    private const string SecondIndex = "courses/TST1O/section2/index.md";

    private static readonly byte[] FirstBefore = Encoding.UTF8.GetBytes("What the first page held before.\n");
    private static readonly byte[] FirstAfter = Encoding.UTF8.GetBytes("What the step left in the first page.\n");
    private static readonly byte[] SecondBefore = Encoding.UTF8.GetBytes("What the second page held before, its own words.\n");
    private static readonly byte[] SecondAfter = Encoding.UTF8.GetBytes("What the step left in the second page.\n");

    // MARK: - Functions

    /// <summary>
    /// Items 1 to 4 and 6 through the real Undo: the first page put back from
    /// the list (its outgoing bytes refused, so kept), the second from its
    /// kept original (whose bytes the list would not take, so it stays). Each
    /// is named by its path inside the course, since both are <c>index.md</c>,
    /// and each the way it came back; the line's list is the bare names.
    /// MUST FAIL keyed by file name (both said "from what was kept beside
    /// it", each “index.md”), and with the payload turned into paths.
    /// </summary>
    [Fact]
    public void TwoPagesWithOneNameAreNamedByTheirPathsAndTheWayEachCameBack()
    {
        using var scribe = new UndoScribe();
        UndoTrailLine line = UndoTheStepOnTwoPages(scribe, FirstIndex, secondTakesNoNewFile: true);

        Assert.StartsWith("Undo put back “section1/index.md”, and put back “section2/index.md” from what was kept beside it, but the list", line.Words);
        Assert.Contains("What “section1/index.md” held a moment before is kept beside it as the hidden file “.index.md.plantoir-undo-1-undo-orig”.", line.Words);
        Assert.Contains("What “section2/index.md” holds now is kept beside it as the hidden file “.index.md.plantoir-undo-1-apply-orig”.", line.Words);
        Assert.Equal([".index.md.plantoir-undo-1-undo-orig", ".index.md.plantoir-undo-1-apply-orig"], line.Kept);
        Assert.Equal(SecondBefore, scribe.Page("A", SecondIndex));
    }

    /// <summary>
    /// Items 2 to 4: the second page put back from its kept original, which
    /// the list took, so nothing of it is kept and it is not named. The first
    /// page, put back from the list, is never said to come "from what was kept
    /// beside it", and is named by its path, since the second page of the
    /// same step is <c>index.md</c> too (every op's path counts, named or not).
    /// MUST FAIL keyed by file name, and with "from what was kept beside it"
    /// said of every page.
    /// </summary>
    [Fact]
    public void APagePutBackFromTheListIsNeverSaidToComeFromWhatWasKept()
    {
        using var scribe = new UndoScribe();
        UndoTrailLine line = UndoTheStepOnTwoPages(scribe, FirstIndex, secondTakesNoNewFile: false);

        Assert.DoesNotContain("from what was kept beside it", line.Words);
        Assert.StartsWith("Undo put back “section1/index.md”, but the list could not keep a copy", line.Words);
        Assert.Contains("What “section1/index.md” held a moment before is kept beside it as the hidden file “.index.md.plantoir-undo-1-undo-orig”.", line.Words);
        Assert.Equal([".index.md.plantoir-undo-1-undo-orig"], line.Kept);
    }

    /// <summary>
    /// Item 1: two kept files with ONE bare name in two folders are two kept
    /// files, each listed; a kept file is skipped only when its whole path is
    /// already listed. Both pages' outgoing bytes are refused by the list, so
    /// each is kept beside its page and the Redo is made from them. MUST FAIL
    /// keyed by file name (the second skipped), and with the outgoing bytes
    /// of a page put back from the list never stored nor kept.
    /// </summary>
    [Fact]
    public void TwoKeptFilesWithOneNameInTwoFoldersAreBothListed()
    {
        using var scribe = new UndoScribe();
        long seq = MakeTheStepOnTwoPages(scribe, FirstIndex, SecondIndex);
        UndoTrailLine line;
        using (var denials = new UndoDenials())
        {
            TakeAwayTheBlob(scribe, denials, FirstAfter);
            TakeAwayTheBlob(scribe, denials, SecondAfter);
            Assert.Equal("undone", scribe.Undo().Name);
            line = TheOneKeptLine(scribe);
            // The only copies of what the step left are beside the pages, and
            // the Redo is made from them (item 4 of the lows fixed with U4a).
            Assert.Equal("redone", scribe.Redo().Name);
        }
        Assert.Equal(FirstAfter, scribe.Page("A", FirstIndex));
        Assert.Equal(SecondAfter, scribe.Page("A", SecondIndex));

        Assert.Equal(1, seq);
        Assert.StartsWith("Undo put back “section1/index.md”, “section2/index.md”, but the list", line.Words);
        Assert.Contains("What “section1/index.md” held a moment before", line.Words);
        Assert.Contains("What “section2/index.md” held a moment before", line.Words);
        Assert.Equal([".index.md.plantoir-undo-1-undo-orig", ".index.md.plantoir-undo-1-undo-orig"], line.Kept);
    }

    /// <summary>
    /// Item 4, a page at the top of the working folder beside a course page
    /// of the same name: its kept file is its bare hidden name, and it is
    /// named by its path in the working folder, “index.md”.
    /// </summary>
    [Fact]
    public void APageAtTheTopOfTheWorkingFolderIsNamedByItsPathThere()
    {
        using var scribe = new UndoScribe();
        UndoTrailLine line = UndoTheStepOnTwoPages(scribe, "index.md", secondTakesNoNewFile: true);

        Assert.StartsWith("Undo put back “index.md”, and put back “section2/index.md” from what was kept beside it, but the list", line.Words);
        Assert.Contains("What “index.md” held a moment before is kept beside it as the hidden file “.index.md.plantoir-undo-1-undo-orig”.", line.Words);
    }

    /// <summary>
    /// Items 3 and 4 in the words alone (the mac's
    /// <c>testTheKeptLineKeysPagesByTheirPlaceInTheWorkingFolder</c>, the
    /// example of documentation 12): kept files given by their paths.
    /// </summary>
    [Fact]
    public void KeptFilesAreKeyedByTheirPlaceInTheWorkingFolder()
    {
        string words = UndoTrail.KeptWhatItReplacedWords(
            true, ["courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig"], ["courses/ICS3U/Section 2/.index.md.plantoir-undo-3-apply-orig"],
            "ICS3U", ["courses/ICS3U/Section 2/index.md"], []);

        Assert.Equal(
            "Undo put back “Section 1/index.md”, and put back “Section 2/index.md” from what was kept beside it, but the list could not keep a copy of all it needs for this change, "
            + "so what it could not keep stays beside the page, and the next Undo or Redo of this change uses it. "
            + "What “Section 1/index.md” held a moment before is kept beside it as the hidden file “.index.md.plantoir-undo-4-undo-orig”. "
            + "What “Section 2/index.md” holds now is kept beside it as the hidden file “.index.md.plantoir-undo-3-apply-orig”.",
            words);
    }

    /// <summary>
    /// Item 4: a named page is told apart by its path when another page of
    /// the step, not named on the line, shares its file name; a page of the
    /// step with another name changes nothing. MUST FAIL with the shared name
    /// looked for only among the pages named.
    /// </summary>
    [Fact]
    public void ANamedPageIsToldApartWhenAnotherPageOfTheStepSharesItsName()
    {
        string shared = UndoTrail.KeptWhatItReplacedWords(
            true, ["courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig"], [],
            "ICS3U", ["courses/ICS3U/Section 2/index.md"], ["courses/ICS3U/Section 1/index.md", "courses/ICS3U/Section 2/index.md"]);
        Assert.StartsWith("Undo put back “Section 1/index.md”, but the list", shared);
        Assert.Contains("What “Section 1/index.md” held a moment before", shared);

        string alone = UndoTrail.KeptWhatItReplacedWords(
            true, ["courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig"], [],
            "ICS3U", ["courses/ICS3U/Section 2/B.md"], ["courses/ICS3U/Section 1/index.md", "courses/ICS3U/Section 2/B.md"]);
        Assert.StartsWith("Undo put back “index.md”, but the list", alone);
    }

    /// <summary>
    /// Item 4: with no course, or a page outside the step's course, a page
    /// whose name another shares is named by its path in the working folder;
    /// names that differ only in capitals are two names, each named by its
    /// file name.
    /// </summary>
    [Fact]
    public void PagesOutsideTheCourseAreNamedByTheirPathInTheWorkingFolder()
    {
        string noCourse = UndoTrail.KeptWhatItReplacedWords(
            true, ["courses/ICS3U/Section 1/.index.md.plantoir-undo-4-undo-orig"], ["courses/ICS3U/Section 2/.index.md.plantoir-undo-3-apply-orig"],
            null, ["courses/ICS3U/Section 2/index.md"], []);
        Assert.StartsWith("Undo put back “courses/ICS3U/Section 1/index.md”, and put back “courses/ICS3U/Section 2/index.md” from what was kept beside it", noCourse);

        string otherFolder = UndoTrail.KeptWhatItReplacedWords(
            false, ["shared/.index.md.plantoir-undo-4-redo-orig"], ["courses/ICS3U/Section 2/.index.md.plantoir-undo-3-apply-orig"],
            "ICS3U", ["courses/ICS3U/Section 2/index.md"], []);
        Assert.StartsWith("Redo put back “shared/index.md”, and put back “Section 2/index.md” from what was kept beside it", otherFolder);

        string capitals = UndoTrail.KeptWhatItReplacedWords(
            true, ["courses/ICS3U/Section 1/.Index.md.plantoir-undo-4-undo-orig"], ["courses/ICS3U/Section 2/.index.md.plantoir-undo-3-apply-orig"],
            "ICS3U", ["courses/ICS3U/Section 2/index.md"], []);
        Assert.StartsWith("Undo put back “Index.md”, and put back “index.md” from what was kept beside it", capitals);
    }

    /// <summary>
    /// Names and prefixes are compared in normalization form C, then
    /// ordinally (documentation 12, "What W4c and W8 owe from U4b2-6", its
    /// last bullet; the mac's <c>String ==</c>): <c>é.md</c> in form C in one
    /// folder and form D in another is ONE name, so both are named by their
    /// paths; a put-back page and a course spelled in the other form are the
    /// same page and course. MUST FAIL with an ordinal compare without form C.
    /// </summary>
    [Fact]
    public void NamesAreComparedInNormalizationFormCThenOrdinally()
    {
        string composed = "é.md";
        string decomposed = "é.md";
        string twoForms = UndoTrail.KeptWhatItReplacedWords(
            true, ["courses/ICS3U/Section 1/." + composed + ".plantoir-undo-4-undo-orig"], ["courses/ICS3U/Section 2/." + decomposed + ".plantoir-undo-3-apply-orig"],
            "ICS3U", ["courses/ICS3U/Section 2/" + composed], []);
        Assert.StartsWith("Undo put back “Section 1/" + composed + "”, and put back “Section 2/" + decomposed + "” from what was kept beside it", twoForms);

        string course = "CHÉ1O";
        string courseInFormD = "CHÉ1O";
        string prefixInFormD = UndoTrail.KeptWhatItReplacedWords(
            true, ["courses/" + courseInFormD + "/Section 1/.index.md.plantoir-undo-4-undo-orig"], ["courses/" + course + "/Section 2/.index.md.plantoir-undo-3-apply-orig"],
            course, ["courses/" + course + "/Section 2/index.md"], []);
        Assert.StartsWith("Undo put back “Section 1/index.md”, and put back “Section 2/index.md” from what was kept beside it", prefixInFormD);
    }

    /// <summary>
    /// Item 5: a bare hidden name stands for a page at the top of the working
    /// folder, and with no list of pages put back from a kept original every
    /// page named was (the contract's example,
    /// <see cref="UndoTrailWordsContractTests"/>, is passed so, unchanged).
    /// </summary>
    [Fact]
    public void ABareHiddenNameWithNoListIsAPageAtTheTopPutBackFromWhatWasKept()
    {
        string words = UndoTrail.KeptWhatItReplacedWords(true, [".A.md.plantoir-undo-4-undo-orig"], []);
        Assert.StartsWith("Undo put back “A.md” from what was kept beside it, but the list", words);
        Assert.Contains("What “A.md” held a moment before is kept beside it as the hidden file “.A.md.plantoir-undo-4-undo-orig”.", words);
    }

    /// <summary>
    /// Two pages in one whole-file step of TST1O, the first at
    /// <paramref name="first"/>, the second at <see cref="SecondIndex"/>; then
    /// the first's after content gone and its folder in the list taking no new
    /// file; the second's before content gone, its kept original beside it,
    /// and with <paramref name="secondTakesNoNewFile"/> the list taking no new
    /// file there either; then Undo. The one kept line it wrote.
    /// </summary>
    private static UndoTrailLine UndoTheStepOnTwoPages(UndoScribe scribe, string first, bool secondTakesNoNewFile)
    {
        long seq = MakeTheStepOnTwoPages(scribe, first, SecondIndex);
        using var denials = new UndoDenials();
        TakeAwayTheBlob(scribe, denials, FirstAfter);
        if (secondTakesNoNewFile) TakeAwayTheBlob(scribe, denials, SecondBefore);
        else File.Delete(scribe.Journal.BlobPath(UndoCheck.Sha(SecondBefore)));
        File.WriteAllBytes(UndoSwap.BesidePath(scribe.FullPath("A", SecondIndex), $"{seq}-apply", "orig"), SecondBefore);
        Assert.Equal("undone", scribe.Undo().Name);
        return TheOneKeptLine(scribe);
    }

    private static long MakeTheStepOnTwoPages(UndoScribe scribe, string first, string second)
    {
        scribe.WritePage("A", first, FirstBefore);
        scribe.WritePage("A", second, SecondBefore);
        long seq = scribe.Step("A", [(first, FirstAfter), (second, SecondAfter)])!.Value;
        foreach (UndoOp op in scribe.Fold().Steps[seq].Step.Ops) Assert.Equal(UndoOp.WriteFile, op.Kind);
        // Each content in a folder of its own in the list, so that one
        // refused folder refuses only the content it names.
        var folders = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (byte[] content in new[] { FirstBefore, FirstAfter, SecondBefore, SecondAfter })
            Assert.True(folders.Add(Path.GetDirectoryName(scribe.Journal.BlobPath(UndoCheck.Sha(content)))!), "two contents share a folder in the list");
        return seq;
    }

    private static void TakeAwayTheBlob(UndoScribe scribe, UndoDenials denials, byte[] content)
    {
        string blob = scribe.Journal.BlobPath(UndoCheck.Sha(content));
        File.Delete(blob);
        denials.FolderTakesNothingNew(Path.GetDirectoryName(blob)!);
    }

    private static UndoTrailLine TheOneKeptLine(UndoScribe scribe)
    {
        var kept = new List<UndoTrailLine>();
        lock (scribe.TrailLines)
        {
            foreach (UndoTrailLine line in scribe.TrailLines)
            {
                if (line.Event == Plantoir.Core.Scripting.ActivityTrail.Event.UndoKeptWhatItReplaced) kept.Add(line);
            }
        }
        return Assert.Single(kept);
    }
}
