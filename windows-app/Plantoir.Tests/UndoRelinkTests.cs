using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// W8b-21b1 of #899 (Windows' copy of the mac's U4b3 relink-1,
/// <c>UndoRelinkTests</c>, "Judged and swapped"): a RELINKING move, a link's
/// <c>move</c> that changes the text the link holds (<c>linkShaBefore</c> at
/// <c>from</c>, <c>linkShaAfter</c> at <c>to</c>, both texts in the list). Each
/// side is judged by its own text, read as the link itself and never
/// followed; both links standing is neither state. It is swapped as: a new
/// link holding the destination's text made under the staged <c>-new</c> name
/// beside the destination, renamed in without replacing, then the old link
/// removed only once re-read holding the source's text. Read from the journal
/// (21b2, the mac's relink-2): the pair is ONE content form beside
/// <c>sha</c>, <c>listingSha</c> and <c>linkSha</c>, readable only in its one
/// shape (<see cref="ARelinkOfAnyOtherShapeIsNotReadable"/>).
/// </summary>
public sealed class UndoRelinkTests : IDisposable
{
    private const string Section = "courses/TST1O/section1";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-relink-");
    private readonly string _outside;
    private readonly Dictionary<string, byte[]> _blobs = new(StringComparer.Ordinal);

    public UndoRelinkTests()
    {
        _outside = _root.TrimEnd(Path.DirectorySeparatorChar) + "-outside";
        Directory.CreateDirectory(_outside);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
        try { Directory.Delete(_outside, recursive: true); } catch { }
        try { Directory.Delete(ListFolder, recursive: true); } catch { }
    }

    private sealed record LaidRelink(UndoOp Op, string OldText, string NewText);

    private static string Day(int number) => Section + "/Unit 1, Day " + number + ".md";

    private string Full(string relative) => Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));

    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);

    private string Store(string text)
    {
        string sha = UndoCheck.Sha(Bytes(text));
        _blobs[sha] = Bytes(text);
        return sha;
    }

    private void WritePage(string relative, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllBytes(Full(relative), Bytes(text));
    }

    private void LayLink(string relative, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.CreateSymbolicLink(Full(relative), text);
    }

    /// <summary>The text the link at the place holds, as stored, or null when no link is there.</summary>
    private string? LinkText(string relative) =>
        UndoLinks.Look(Full(relative)) == UndoLinks.What.Link ? new FileInfo(Full(relative)).LinkTarget : null;

    private bool StandsAnything(string relative) => UndoLinks.Look(Full(relative)) != UndoLinks.What.Nothing;

    /// <summary>
    /// A link at Day 4 and the op moving it to Day 5 with a new text: in the
    /// section, <c>Unit 1, Day 3.md</c> becoming <c>Unit 1, Day 4.md</c> (the
    /// page Day 3 laid beside it); outside, two full paths naming files laid
    /// there, or naming nothing.
    /// </summary>
    private LaidRelink LayARelink(string leads)
    {
        string oldText, newText;
        switch (leads)
        {
            case "inside":
                WritePage(Day(3), "Three.\n");
                oldText = "Unit 1, Day 3.md";
                newText = "Unit 1, Day 4.md";
                break;
            case "outToAFile":
                oldText = Path.Combine(_outside, "Day 3.md");
                newText = Path.Combine(_outside, "Day 4.md");
                File.WriteAllText(oldText, "Outside three.\n");
                File.WriteAllText(newText, "Outside four.\n");
                break;
            default:
                oldText = Path.Combine(_outside, "gone 3.md");
                newText = Path.Combine(_outside, "gone 4.md");
                break;
        }
        LayLink(Day(4), oldText);
        UndoOp op = UndoOp.RelinkLink(Day(4), Day(5), Store(oldText), Store(newText));
        return new LaidRelink(op, oldText, newText);
    }

    private UndoCheck.PlanResult Plan(IReadOnlyList<UndoOp> ops, bool backward, Func<string, bool>? cannotRead = null) =>
        UndoCheck.Plan(ops, backward, relative => UndoCurrent.Read(Full(relative)),
                       sha => _blobs.TryGetValue(sha, out byte[]? bytes) ? bytes : null,
                       whole: new UndoWholeReads(_root, new UndoMemoryPlaces(), cannotRead));

    private List<UndoSwapTarget> ReadyTargets(UndoCheck.PlanResult plan)
    {
        Assert.True(plan is UndoCheck.PlanResult.Ready, "the plan came to " + plan);
        return UndoDoor.TargetsOf((UndoCheck.PlanResult.Ready)plan, _root);
    }

    private static List<string> PlacesOf(IReadOnlyList<UndoSwapTarget> targets)
    {
        var places = new List<string>();
        foreach (UndoSwapTarget target in targets) places.Add(target.RelativePath);
        return places;
    }

    private static string Described(UndoSwapResult result) => result switch
    {
        UndoSwapResult.Refused refused => "refused " + refused.Refusal.Kind + " " + refused.Refusal.Path,
        _ => result.GetType().Name,
    };

    private void MakeItForward(LaidRelink laid)
    {
        UndoSwapResult result = UndoSwap.Swap(ReadyTargets(Plan([laid.Op], backward: false)), "1-apply", _root);
        Assert.True(result is UndoSwapResult.Swapped, Described(result));
    }

    /// <summary>Every staged name left anywhere under the root.</summary>
    private List<string> StagedLeft()
    {
        var found = new List<string>();
        foreach (string entry in Directory.EnumerateFileSystemEntries(_root, "*", SearchOption.AllDirectories))
        {
            if (Path.GetFileName(entry).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)) found.Add(entry);
        }
        return found;
    }

    /// <summary>
    /// What the outside folder holds, read without opening any file there (an
    /// open would itself move the access time): each entry's name, length,
    /// write and access times, and nothing more made there. The bytes are
    /// checked once, at the end (<see cref="CheckTheOutsideBytes"/>).
    /// </summary>
    private string OutsideNow()
    {
        var said = new StringBuilder();
        foreach (string file in Directory.EnumerateFileSystemEntries(_outside).Order(StringComparer.Ordinal))
        {
            var info = new FileInfo(file);
            said.Append(info.Name).Append(' ').Append(info.Length).Append(' ').Append(info.LastWriteTimeUtc.Ticks)
                .Append(' ').Append(info.LastAccessTimeUtc.Ticks).Append('\n');
        }
        return said.ToString();
    }

    /// <summary>The outside files hold what they were laid with, byte for byte.</summary>
    private void CheckTheOutsideBytes(string leads)
    {
        if (leads != "outToAFile")
        {
            Assert.Empty(Directory.EnumerateFileSystemEntries(_outside));
            return;
        }
        Assert.Equal("Outside three.\n", File.ReadAllText(Path.Combine(_outside, "Day 3.md")));
        Assert.Equal("Outside four.\n", File.ReadAllText(Path.Combine(_outside, "Day 4.md")));
    }

    /// <summary>What the section holds: each entry, a link by its text, a file by its bytes, a folder as one.</summary>
    private string FolderNow()
    {
        var said = new StringBuilder();
        foreach (string entry in Directory.EnumerateFileSystemEntries(_root, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
        {
            said.Append(entry[_root.Length..]).Append(' ');
            said.Append(UndoLinks.Look(entry) switch
            {
                UndoLinks.What.Link => "link " + new FileInfo(entry).LinkTarget,
                UndoLinks.What.File => "file " + Convert.ToHexString(File.ReadAllBytes(entry)),
                UndoLinks.What.Folder => "folder",
                UndoLinks.What what => what.ToString(),
            }).Append('\n');
        }
        return said.ToString();
    }

    // ---- The op and the one test ------------------------------------------

    /// <summary>
    /// The factory: a move with both texts as blobs, never beside sha,
    /// listingSha or linkSha; a link's move by the ONE test, each side by its
    /// own text; it hands a place over as a link's move does and carries no
    /// edit, and its places are judged on the folders above them only.
    /// </summary>
    [Fact]
    public void ARelinkIsALinksMoveWithEachSidesOwnTextAndBothTextsAsBlobs()
    {
        string before = UndoCheck.Sha(Bytes("Unit 1, Day 3.md")), after = UndoCheck.Sha(Bytes("Unit 1, Day 4.md"));
        UndoOp relink = UndoOp.RelinkLink(Day(4), Day(5), before, after);
        Assert.Equal(UndoOp.Move, relink.Kind);
        Assert.True(relink.Readable);
        Assert.Equal([before, after], relink.Blobs);
        Assert.Null(relink.Sha);
        Assert.Null(relink.ListingSha);
        Assert.Null(relink.LinkSha);
        Assert.True(relink.IsALinksMove);
        Assert.True(relink.IsARelink);
        Assert.Equal(before, relink.LinkText(isAtFrom: true));
        Assert.Equal(after, relink.LinkText(isAtFrom: false));

        UndoOp plain = new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(4), To = Day(5), LinkSha = before };
        Assert.True(plain.IsALinksMove);
        Assert.False(plain.IsARelink);
        Assert.Equal(before, plain.LinkText(isAtFrom: false));

        Assert.True(UndoOp.HandsOverAsAMove(relink));
        UndoOp newPage = new UndoOp { Kind = UndoOp.WriteFile, Readable = true, Path = Day(4), AfterSha = after };
        UndoHandover handover = Assert.Single(UndoOp.Handovers([relink, newPage]));
        Assert.True(handover.ALinkMoves);
        UndoOp edit = new UndoOp { Kind = UndoOp.WriteFile, Readable = true, Path = Day(5), BeforeSha = before, AfterSha = after };
        Assert.False(UndoOp.MoveCarries(relink, edit));
    }

    /// <summary>A relink's places are the link itself: one leading out of the working folder is moved as a link (never resolved).</summary>
    [SymbolicLinkFact]
    public void ARelinksPlacesAreJudgedOnTheFoldersAboveThemOnly()
    {
        LaidRelink laid = LayARelink("outToAFile");
        Assert.True(UndoPlaces.StaysInside(_root, Day(4), laid.Op));
        Assert.False(UndoPlaces.StaysInside(_root, Day(4)));
    }

    // ---- Measured (#899 W8b-21b1, on the PC) -----------------------------

    /// <summary>
    /// Measured on the PC (Windows 11 26200, NTFS, .NET 9.0.18, Developer
    /// Mode on): a text with forward slashes, the mac's spelling, is stored
    /// byte for byte (LinkTarget reads it back the same), so a relink judged
    /// by its text works; but the system does not open the file through such
    /// a link (ERROR_INVALID_NAME, 123), where the same text with backslashes
    /// opens it. Parked for piece 22 (which text a link Windows makes holds).
    /// </summary>
    [SymbolicLinkFact]
    public void AForwardSlashTextIsKeptByteForByteButTheSystemDoesNotOpenThroughIt()
    {
        WritePage("courses/TST1O/library/Day 4.md", "Four.\n");
        LayLink(Section + "/forward.md", "../library/Day 4.md");
        LayLink(Section + "/back.md", "..\\library\\Day 4.md");
        Assert.True(UndoSwap.LinkHolds(Full(Section + "/forward.md"), Bytes("../library/Day 4.md")));
        Assert.Equal("../library/Day 4.md", LinkText(Section + "/forward.md"));
        Assert.Throws<IOException>(() => File.ReadAllText(Full(Section + "/forward.md")));
        Assert.Equal("Four.\n", File.ReadAllText(Full(Section + "/back.md")));
    }

    // ---- Judged and swapped (the mac's relink-1) --------------------------

    /// <summary>
    /// Going forward the link at Day 4 is replaced by one at Day 5 holding
    /// exactly the new text; going back, the old link with the old text byte
    /// for byte. Whatever either text names, inside or out, a file or nothing,
    /// is never read, written or made.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("inside")]
    [InlineData("outToAFile")]
    [InlineData("outToNothing")]
    public void ARelinkGoesForwardAndBackHoldingEachSidesOwnText(string leads)
    {
        LaidRelink laid = LayARelink(leads);
        string outsideBefore = OutsideNow();
        byte[]? insideBefore = File.Exists(Full(Day(3))) ? File.ReadAllBytes(Full(Day(3))) : null;

        List<UndoSwapTarget> forward = ReadyTargets(Plan([laid.Op], backward: false));
        Assert.Equal([Day(5)], PlacesOf(forward));
        UndoSwapResult made = UndoSwap.Swap(forward, "1-apply", _root);
        Assert.True(made is UndoSwapResult.Swapped, Described(made));
        Assert.Equal(laid.NewText, LinkText(Day(5)));
        Assert.False(StandsAnything(Day(4)));
        Assert.Empty(StagedLeft());
        Assert.Equal(outsideBefore, OutsideNow());

        List<UndoSwapTarget> back = ReadyTargets(Plan([laid.Op], backward: true));
        Assert.Equal([Day(4)], PlacesOf(back));
        UndoSwapResult undone = UndoSwap.Swap(back, "1-undo", _root);
        Assert.True(undone is UndoSwapResult.Swapped, Described(undone));
        Assert.Equal(laid.OldText, LinkText(Day(4)));
        Assert.False(StandsAnything(Day(5)));
        Assert.Empty(StagedLeft());
        Assert.Equal(outsideBefore, OutsideNow());
        Assert.Equal(insideBefore, File.Exists(Full(Day(3))) ? File.ReadAllBytes(Full(Day(3))) : null);
        CheckTheOutsideBytes(leads);
    }

    /// <summary>A side holding the OTHER side's text, a plain file, a folder or nothing where the content should be is changed since, both ways, and nothing changes.</summary>
    [SymbolicLinkTheory]
    [InlineData("other text", false)]
    [InlineData("other text", true)]
    [InlineData("file", false)]
    [InlineData("file", true)]
    [InlineData("folder", false)]
    [InlineData("folder", true)]
    [InlineData("nothing", false)]
    [InlineData("nothing", true)]
    public void ASideHoldingSomethingElseIsChangedSinceBothWays(string replacement, bool backward)
    {
        LaidRelink laid = LayARelink("inside");
        if (backward) MakeItForward(laid);
        string source = backward ? Day(5) : Day(4);
        Assert.True(UndoSwap.RemoveALink(Full(source)));
        switch (replacement)
        {
            case "other text": LayLink(source, backward ? laid.OldText : laid.NewText); break;
            case "file": WritePage(source, "A page.\n"); break;
            case "folder": Directory.CreateDirectory(Full(source)); break;
        }
        string before = FolderNow();
        UndoCheck.PlanResult plan = Plan([laid.Op], backward);
        Assert.True(plan is UndoCheck.PlanResult.ChangedSince, replacement + " " + backward + ": " + plan);
        Assert.Equal(before, FolderNow());
    }

    /// <summary>Both links standing (the new one renamed in, the old not yet removed) is neither state: changed since, both ways, and nothing is removed.</summary>
    [SymbolicLinkTheory]
    [InlineData(false)]
    [InlineData(true)]
    public void BothLinksStandingIsChangedSinceBothWays(bool backward)
    {
        LaidRelink laid = LayARelink("inside");
        LayLink(Day(5), laid.NewText);
        string before = FolderNow();
        UndoCheck.PlanResult plan = Plan([laid.Op], backward);
        Assert.True(plan is UndoCheck.PlanResult.ChangedSince, backward + ": " + plan);
        Assert.Equal(before, FolderNow());
    }

    /// <summary>A side that cannot be read is cannot tell now; both texts are still in the list and the link stands.</summary>
    [SymbolicLinkFact]
    public void ASideThatCannotBeReadIsCannotTellNow()
    {
        LaidRelink laid = LayARelink("inside");
        string day4 = Full(Day(4));
        UndoCheck.PlanResult plan = Plan([laid.Op], backward: false, cannotRead: place => string.Equals(place, day4, StringComparison.OrdinalIgnoreCase));
        Assert.True(plan is UndoCheck.PlanResult.CannotTellNow, "the plan came to " + plan);
        Assert.True(_blobs.ContainsKey(laid.Op.LinkShaBefore!));
        Assert.True(_blobs.ContainsKey(laid.Op.LinkShaAfter!));
        Assert.Equal(laid.OldText, LinkText(Day(4)));
    }

    /// <summary>Either text missing from the list: content missing, nothing changed.</summary>
    [SymbolicLinkTheory]
    [InlineData("before")]
    [InlineData("after")]
    public void ATextMissingFromTheListIsContentMissing(string missing)
    {
        LaidRelink laid = LayARelink("inside");
        string absent = UndoCheck.Sha(Bytes("Not in the list."));
        if (missing == "before")
        {
            // Laid with the text the op names, so only the list lacks it.
            Assert.True(UndoSwap.RemoveALink(Full(Day(4))));
            LayLink(Day(4), "Not in the list.");
        }
        UndoOp op = UndoOp.RelinkLink(Day(4), Day(5), missing == "before" ? absent : laid.Op.LinkShaBefore!,
                                      missing == "after" ? absent : laid.Op.LinkShaAfter!);
        string before = FolderNow();
        UndoCheck.PlanResult plan = Plan([op], backward: false);
        Assert.True(plan is UndoCheck.PlanResult.ContentMissing, missing + ": the plan came to " + plan);
        Assert.Equal(before, FolderNow());
    }

    /// <summary>A second target that fails after the relink went in: the relink is reversed the same way the other way round, the old link back with its text, nothing at Day 5 and nothing staged left.</summary>
    [SymbolicLinkFact]
    public void ALaterFailureReversesTheRelink()
    {
        LaidRelink laid = LayARelink("inside");
        WritePage(Day(8), "Eight.\n");
        UndoOp fileMove = new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(8), To = Day(9), Sha = UndoCheck.Sha(Bytes("Eight.\n")) };
        List<UndoSwapTarget> targets = ReadyTargets(Plan([laid.Op, fileMove], backward: false));
        Assert.Equal([Day(5), Day(9)], PlacesOf(targets));
        var seams = new UndoSeams { BeforeEachSwap = (index, _) => { if (index == 1) WritePage(Day(9), "Someone's.\n"); } };

        UndoSwapResult result = UndoSwap.Swap(targets, "1-apply", _root, seams);

        Assert.True(result is UndoSwapResult.Refused { Refusal.Kind: UndoRefusalKind.ChangedSince }, Described(result));
        Assert.Equal(laid.OldText, LinkText(Day(4)));
        Assert.False(StandsAnything(Day(5)));
        Assert.Equal("Eight.\n", File.ReadAllText(Full(Day(8))));
        Assert.Empty(StagedLeft());
    }

    /// <summary>The new link cannot be renamed in: the old link is never removed first, so it stands with its text, and nothing is left staged.</summary>
    [SymbolicLinkFact]
    public void ARenameInThatFailsLeavesTheOldLinkWhole()
    {
        LaidRelink laid = LayARelink("inside");
        List<UndoSwapTarget> targets = ReadyTargets(Plan([laid.Op], backward: false));
        var seams = new UndoSeams { RelinkRenameInFails = _ => true };

        UndoSwapResult result = UndoSwap.Swap(targets, "1-apply", _root, seams);

        Assert.True(result is UndoSwapResult.Refused { Refusal.Kind: UndoRefusalKind.FileIsInUse }, Described(result));
        Assert.Equal(Day(4), ((UndoSwapResult.Refused)result).Refusal.Path);
        Assert.Equal(laid.OldText, LinkText(Day(4)));
        Assert.False(StandsAnything(Day(5)));
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// The old link given another text after the pair was judged and before it
    /// would be removed: it is re-read first, so it is never removed; the new
    /// link this swap made is removed again and nothing is staged.
    /// </summary>
    [SymbolicLinkFact]
    public void AnOldLinkChangedBeforeItsRemovalIsLeftAndTheNewLinkTakenAway()
    {
        LaidRelink laid = LayARelink("inside");
        List<UndoSwapTarget> targets = ReadyTargets(Plan([laid.Op], backward: false));
        var seams = new UndoSeams
        {
            RelinkRenameInFails = _ =>
            {
                Assert.True(UndoSwap.RemoveALink(Full(Day(4))));
                LayLink(Day(4), "Someone else's.md");
                return false;
            },
        };

        UndoSwapResult result = UndoSwap.Swap(targets, "1-apply", _root, seams);

        Assert.True(result is UndoSwapResult.Refused, Described(result));
        Assert.Equal("Someone else's.md", LinkText(Day(4)));
        Assert.False(StandsAnything(Day(5)));
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// A link this process may not make (Win32 1314, ERROR_PRIVILEGE_NOT_HELD,
    /// a PC without Developer Mode) is an ordinary failed make: could not
    /// write, naming the place; the swap already made reversed; nothing
    /// changed, nothing staged; never retried and never a fallback.
    /// </summary>
    [SymbolicLinkFact]
    public void AMakeRefusedForWantOfThePrivilegeIsAPlainFailedMake()
    {
        LaidRelink laid = LayARelink("inside");
        WritePage(Day(8), "Eight.\n");
        UndoOp fileMove = new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(8), To = Day(9), Sha = UndoCheck.Sha(Bytes("Eight.\n")) };
        List<UndoSwapTarget> targets = ReadyTargets(Plan([fileMove, laid.Op], backward: false));
        Assert.Equal([Day(9), Day(5)], PlacesOf(targets));
        string before = FolderNow();
        int asked = 0;
        var seams = new UndoSeams { MakingALinkAnswers = _ => { asked++; return 1314; } };

        UndoSwapResult result = UndoSwap.Swap(targets, "1-apply", _root, seams);

        Assert.True(result is UndoSwapResult.Refused { Refusal.Kind: UndoRefusalKind.CouldNotWrite }, Described(result));
        Assert.Equal(Day(4), ((UndoSwapResult.Refused)result).Refusal.Path);
        Assert.Equal(1, asked);
        Assert.Equal(before, FolderNow());
        Assert.Empty(StagedLeft());
    }

    /// <summary>The relink LEAVES a handed-over place: it leaves Day 4, and the page at Day 3 moves into it. Planned and swapped in the step's order, both ways.</summary>
    [SymbolicLinkFact]
    public void ARelinkLeavingAHandedOverPlaceGoesBothWays()
    {
        LaidRelink laid = LayARelink("inside");
        UndoOp pageMove = new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(3), To = Day(4), Sha = UndoCheck.Sha(Bytes("Three.\n")) };
        List<UndoOp> ops = [laid.Op, pageMove];
        string before = FolderNow();

        List<UndoSwapTarget> forward = ReadyTargets(Plan(ops, backward: false));
        Assert.Equal([Day(5), Day(4)], PlacesOf(forward));
        UndoSwapResult made = UndoSwap.Swap(forward, "1-apply", _root);
        Assert.True(made is UndoSwapResult.Swapped, Described(made));
        Assert.Equal(laid.NewText, LinkText(Day(5)));
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(4))));
        Assert.False(StandsAnything(Day(3)));

        List<UndoSwapTarget> back = ReadyTargets(Plan(ops, backward: true));
        Assert.Equal([Day(3), Day(4)], PlacesOf(back));
        UndoSwapResult undone = UndoSwap.Swap(back, "1-undo", _root);
        Assert.True(undone is UndoSwapResult.Swapped, Described(undone));
        Assert.Equal(before, FolderNow());
        Assert.Empty(StagedLeft());
    }

    /// <summary>The relink FILLS a handed-over place: the page at Day 5 is removed, and the link moves into its place. Planned and swapped in the step's order, both ways.</summary>
    [SymbolicLinkFact]
    public void ARelinkFillingAHandedOverPlaceGoesBothWays()
    {
        LaidRelink laid = LayARelink("inside");
        WritePage(Day(5), "Five.\n");
        UndoOp removal = new UndoOp { Kind = UndoOp.WriteFile, Readable = true, Path = Day(5), BeforeSha = Store("Five.\n") };
        List<UndoOp> ops = [removal, laid.Op];
        string before = FolderNow();

        List<UndoSwapTarget> forward = ReadyTargets(Plan(ops, backward: false));
        Assert.Equal([Day(5), Day(5)], PlacesOf(forward));
        UndoSwapResult made = UndoSwap.Swap(forward, "1-apply", _root);
        Assert.True(made is UndoSwapResult.Swapped, Described(made));
        Assert.Equal(laid.NewText, LinkText(Day(5)));
        Assert.False(StandsAnything(Day(4)));

        List<UndoSwapTarget> back = ReadyTargets(Plan(ops, backward: true));
        UndoSwapResult undone = UndoSwap.Swap(back, "1-undo", _root);
        Assert.True(undone is UndoSwapResult.Swapped, Described(undone));
        Assert.Equal(before, FolderNow());
        Assert.Empty(StagedLeft());
    }

    /// <summary>A step holding one op, as recovery and the tidy read it.</summary>
    private static UndoStep StepOf(params UndoOp[] ops) => new() { Seq = 1, Readable = true, Ops = ops };

    /// <summary>A staged <c>-new</c> link a stopped swap left, holding the text the step's relink stages there, is removed by the tidy as the link itself: what it leads to is untouched.</summary>
    [SymbolicLinkFact]
    public void AStagedNewLinkIsTidiedAsTheLinkItself()
    {
        LaidRelink laid = LayARelink("inside");
        string staged = UndoSwap.BesidePath(Full(Day(5)), "1-apply", "new");
        File.CreateSymbolicLink(staged, laid.NewText);
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(staged));

        Assert.True(UndoSwap.TidyLeftovers(StepOf(laid.Op), _root));

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(staged));
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(3))));
    }

    /// <summary>
    /// The invariant of every tidy (W8b-21b3; the mac's mac-1 review 2): under
    /// a relink's staged name, anything but a link holding the text the step
    /// staged there is the teacher's, never removed by name. A link holding
    /// another text, a plain file, or a link where no relink of the step
    /// stages, is given back to its place when that is free, or kept under a
    /// visible name beside it and said, never deleted and never left hidden.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("a link holding another text", "free")]
    [InlineData("a link holding another text", "taken")]
    [InlineData("a plain file", "taken")]
    [InlineData("a link where no relink stages", "taken")]
    public void AnythingElseUnderAStagedNameIsTheTeachersAndKeptVisibly(string item, string place)
    {
        LaidRelink laid = LayARelink("inside");
        // Where no relink stages: a plain link move leaving Day 5 (it stages nothing).
        UndoOp plainFromDay5 = new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(5), To = Day(6), LinkSha = Store(laid.NewText) };
        UndoStep step = item == "a link where no relink stages" ? StepOf(plainFromDay5) : StepOf(laid.Op);
        string staged = UndoSwap.BesidePath(Full(Day(5)), "1-apply", "new");
        if (item == "a plain file") File.WriteAllText(staged, "Someone's.\n");
        else File.CreateSymbolicLink(staged, item == "a link where no relink stages" ? laid.NewText : "Someone's.md");
        if (place == "taken") WritePage(Day(5), "Five.\n");
        var said = new List<string>();

        UndoSwap.TidyLeftovers(step, _root, onKeptVisibly: (at, kept) => said.Add(Path.GetFileName(at) + " -> " + Path.GetFileName(kept)));

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(staged));
        string visible = Full(Section + "/Unit 1, Day 5 (kept by Undo).md");
        string holder = place == "free" ? Full(Day(5)) : visible;
        if (item == "a plain file") Assert.Equal("Someone's.\n", File.ReadAllText(holder));
        else Assert.Equal(item == "a link where no relink stages" ? laid.NewText : "Someone's.md", new FileInfo(holder).LinkTarget);
        if (place == "taken")
        {
            Assert.Equal("Five.\n", File.ReadAllText(Full(Day(5))));
            Assert.Equal(["Unit 1, Day 5.md -> Unit 1, Day 5 (kept by Undo).md"], said);
        }
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// W8b-21b4's kill (the harness's teacher's rows, twoChainedRelinks at
    /// Day 5): beside a place that only link moves name (a relink's and a
    /// second relink's, or a plain link move's), no op of the step stages a
    /// page, so a page under the relink's staged name there is the teacher's:
    /// given back to its place, never deleted as a staged copy.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("a second relink")]
    [InlineData("a plain link move")]
    public void APageUnderAStagedNameBesideAPlaceOnlyLinkMovesNameIsTheTeachers(string other)
    {
        LaidRelink laid = LayARelink("inside");
        UndoOp second = other == "a second relink"
            ? UndoOp.RelinkLink(Day(5), Day(6), Store("Unit 1, Day 2.md"), Store("Unit 1, Day 5.md"))
            : new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(5), To = Day(6), LinkSha = Store("Unit 1, Day 2.md") };
        string staged = UndoSwap.BesidePath(Full(Day(5)), "1-apply", "new");
        File.WriteAllText(staged, "Someone's.\n");

        UndoSwap.TidyLeftovers(StepOf(second, laid.Op), _root);

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(staged));
        Assert.Equal("Someone's.\n", File.ReadAllText(Full(Day(5))));
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// The director's shape (Insert Class at a day whose page is a link, the
    /// mac's sister piece): the new class page staged beside the relink's
    /// <c>from</c> is Undo's own (a page op names that place), removed by the
    /// tidy as a staged copy, never kept under a visible name nor said.
    /// </summary>
    [SymbolicLinkFact]
    public void UndosOwnStagedPageBesideARelinksPlaceIsNeverKeptAsTheTeachers()
    {
        LaidRelink laid = LayARelink("inside");
        UndoOp newPage = new UndoOp { Kind = UndoOp.WriteFile, Readable = true, Path = Day(4), AfterSha = Store("New.\n") };
        string staged = UndoSwap.BesidePath(Full(Day(4)), "1-apply", "new");
        File.WriteAllText(staged, "New.\n");
        var said = new List<string>();

        UndoSwap.TidyLeftovers(StepOf(laid.Op, newPage), _root, onKeptVisibly: (at, kept) => said.Add(Path.GetFileName(kept)));

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(staged));
        Assert.Empty(said);
        Assert.False(StandsAnything(Section + "/Unit 1, Day 4 (kept by Undo).md"));
        Assert.Equal(laid.OldText, LinkText(Day(4)));
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// Window E review 1, MEDIUM (piece 22's Insert Class shape): Day 4's link
    /// relinked into Day 5 while Day 5's PAGE moves to Day 6. A plain page
    /// move stages nothing, so the relink's own staged name beside Day 5 is
    /// judged by the one rule, never by its kind nor by which other ops name
    /// Day 5: a teacher's page or folder there is given back to Day 5 when it
    /// is free, else kept under a visible name beside it and said; never
    /// deleted.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("a page", "free")]
    [InlineData("a page", "taken")]
    [InlineData("a folder", "free")]
    [InlineData("a folder", "taken")]
    public void AnythingUnderARelinksOwnStagedNameBesideAPlaceAPageMoveLeavesIsTheTeachers(string item, string place)
    {
        LaidRelink laid = LayARelink("inside");
        UndoOp pageMove = new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(5), To = Day(6), Sha = Store("Five.\n") };
        string staged = UndoSwap.BesidePath(Full(Day(5)), "1-apply", "new");
        if (item == "a page") File.WriteAllText(staged, "Someone's.\n");
        else
        {
            Directory.CreateDirectory(staged);
            File.WriteAllText(Path.Combine(staged, "inside.md"), "Someone's.\n");
        }
        if (place == "taken") WritePage(Day(5), "Five.\n");
        var said = new List<string>();

        UndoSwap.TidyLeftovers(StepOf(pageMove, laid.Op), _root, onKeptVisibly: (at, kept) => said.Add(Path.GetFileName(kept)));

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(staged));
        string keptName = item == "a page" ? "Unit 1, Day 5 (kept by Undo).md" : "Unit 1, Day 5.md (kept by Undo)";
        string holder = place == "free" ? Full(Day(5)) : Full(Section + "/" + keptName);
        string held = item == "a page" ? File.ReadAllText(holder) : File.ReadAllText(Path.Combine(holder, "inside.md"));
        Assert.Equal("Someone's.\n", held);
        if (place == "taken")
        {
            Assert.Equal("Five.\n", File.ReadAllText(Full(Day(5))));
            Assert.Equal([keptName], said);
        }
        else Assert.Empty(said);
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// Window E review 1, LOW 3: a relink of a link to a FOLDER makes a folder
    /// link, and its Undo and Redo make it back the same kind (the kind is
    /// the link being replaced, which stands at every make).
    /// </summary>
    [SymbolicLinkFact]
    public void AFolderLinkIsRelinkedUndoneAndRedoneAsAFolderLink()
    {
        Directory.CreateDirectory(Full(Section + "/media 3"));
        Directory.CreateDirectory(Full(Section + "/media 4"));
        Directory.CreateSymbolicLink(Full(Day(4)), "media 3");
        UndoOp op = UndoOp.RelinkLink(Day(4), Day(5), Store("media 3"), Store("media 4"));
        bool IsAFolderLink(string relative) =>
            UndoLinks.Look(Full(relative)) == UndoLinks.What.Link && File.GetAttributes(Full(relative)).HasFlag(FileAttributes.Directory);

        UndoSwapResult made = UndoSwap.Swap(ReadyTargets(Plan([op], backward: false)), "1-apply", _root);
        Assert.True(made is UndoSwapResult.Swapped, Described(made));
        Assert.Equal("media 4", LinkText(Day(5)));
        Assert.True(IsAFolderLink(Day(5)));

        UndoSwapResult undone = UndoSwap.Swap(ReadyTargets(Plan([op], backward: true)), "1-undo", _root);
        Assert.True(undone is UndoSwapResult.Swapped, Described(undone));
        Assert.Equal("media 3", LinkText(Day(4)));
        Assert.True(IsAFolderLink(Day(4)));

        UndoSwapResult redone = UndoSwap.Swap(ReadyTargets(Plan([op], backward: false)), "1-redo", _root);
        Assert.True(redone is UndoSwapResult.Swapped, Described(redone));
        Assert.True(IsAFolderLink(Day(5)));
        Assert.Empty(StagedLeft());
    }

    /// <summary>A relink's pre-clean never removes what is not its own: something of the teacher's under the staged name stays, and the make fails over it (could not write), the old link whole.</summary>
    [SymbolicLinkFact]
    public void ARelinksPreCleanNeverRemovesWhatIsNotItsOwn()
    {
        LaidRelink laid = LayARelink("inside");
        string staged = UndoSwap.BesidePath(Full(Day(5)), "1-apply", "new");
        File.WriteAllText(staged, "Someone's.\n");

        UndoSwapResult result = UndoSwap.Swap(ReadyTargets(Plan([laid.Op], backward: false)), "1-apply", _root);

        Assert.True(result is UndoSwapResult.Refused { Refusal.Kind: UndoRefusalKind.CouldNotWrite }, Described(result));
        Assert.Equal("Someone's.\n", File.ReadAllText(staged));
        Assert.Equal(laid.OldText, LinkText(Day(4)));
        Assert.False(StandsAnything(Day(5)));
    }

    /// <summary>
    /// Recovery re-reads the link just made before it goes (W8b-21b3, the
    /// mac's removeTheLinksJustMade): one that changed between the reading
    /// and the removal (another program put a link holding another text
    /// there) is never removed.
    /// </summary>
    [SymbolicLinkFact]
    public void TheLinkJustMadeIsReReadBeforeItIsRemoved()
    {
        LaidRelink laid = LayARelink("inside");
        LayLink(Day(5), laid.NewText);

        string? unreadable = UndoRecovery.RemoveTheLinksJustMade(StepOf(laid.Op), _root, goingForward: true, beforeTheRemoval: full =>
        {
            File.Delete(full);
            File.CreateSymbolicLink(full, "Someone's.md");
        });

        Assert.Null(unreadable);
        Assert.Equal("Someone's.md", LinkText(Day(5)));
        Assert.Equal(laid.OldText, LinkText(Day(4)));
    }

    /// <summary>Both links standing: going forward the one at to goes, for an Undo the one at from; a plain link move is never one just made.</summary>
    [SymbolicLinkTheory]
    [InlineData(true)]
    [InlineData(false)]
    public void TheLinkJustMadeIsTheOneAtTheSwapsDestination(bool goingForward)
    {
        LaidRelink laid = LayARelink("inside");
        LayLink(Day(5), laid.NewText);

        Assert.Null(UndoRecovery.RemoveTheLinksJustMade(StepOf(laid.Op), _root, goingForward));

        Assert.Equal(goingForward ? laid.OldText : null, LinkText(Day(4)));
        Assert.Equal(goingForward ? null : laid.NewText, LinkText(Day(5)));
        UndoOp plain = new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(6), To = Day(7), LinkSha = Store("Unit 1, Day 6.md") };
        LayLink(Day(6), "Unit 1, Day 6.md");
        LayLink(Day(7), "Unit 1, Day 6.md");
        Assert.Null(UndoRecovery.RemoveTheLinksJustMade(StepOf(plain), _root, goingForward));
        Assert.Equal("Unit 1, Day 6.md", LinkText(Day(6)));
        Assert.Equal("Unit 1, Day 6.md", LinkText(Day(7)));
    }

    // MARK: Readable (21b2; the mac's relink-2, UndoFormat.relinkShapeIsKnown)

    private static readonly string OldTextSha = UndoCheck.Sha(Bytes("Unit 1, Day 3.md"));
    private static readonly string NewTextSha = UndoCheck.Sha(Bytes("Unit 1, Day 4.md"));

    /// <summary>A relink as the journal holds it, Day 4's link moved to Day 5 with a new text; <paramref name="change"/> alters it first.</summary>
    private static UndoOp ReadARelink(Action<JsonObject>? change = null)
    {
        var json = new JsonObject
        {
            ["kind"] = "move", ["from"] = Day(4), ["to"] = Day(5),
            ["linkShaBefore"] = OldTextSha, ["linkShaAfter"] = NewTextSha, ["blobs"] = new JsonArray(OldTextSha, NewTextSha),
        };
        change?.Invoke(json);
        using JsonDocument document = JsonDocument.Parse(json.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    /// <summary>A relink from the journal is readable: the pair is ONE content form, read as the factory builds it.</summary>
    [Fact]
    public void ARelinkFromTheJournalIsReadable()
    {
        UndoOp read = ReadARelink();
        Assert.True(read.Readable);
        Assert.True(read.IsARelink);
        Assert.True(read.IsALinksMove);
        Assert.Null(read.LinkSha);
        Assert.Equal(OldTextSha, read.LinkShaBefore);
        Assert.Equal(NewTextSha, read.LinkShaAfter);
        Assert.Equal(OldTextSha, read.LinkText(isAtFrom: true));
        Assert.Equal(NewTextSha, read.LinkText(isAtFrom: false));
        Assert.Equal(new[] { OldTextSha, NewTextSha }, read.Blobs.OrderBy(name => name == OldTextSha ? 0 : 1));
    }

    /// <summary>Each barrier of the relink's shape (opKinds.move): any other shape is one this version cannot read.</summary>
    [Theory]
    [InlineData("the two texts the same")]
    [InlineData("one text missing from blobs")]
    [InlineData("a third blob beside the two")]
    [InlineData("linkShaBefore alone")]
    [InlineData("linkShaAfter alone")]
    [InlineData("linkSha beside the pair")]
    [InlineData("sha beside the pair")]
    [InlineData("a text that is not a blob name")]
    [InlineData("the pair on a moveApart")]
    [InlineData("the pair on a capitalisation-only move")]
    [InlineData("the pair on a move to its own place")]
    public void ARelinkOfAnyOtherShapeIsNotReadable(string barrier)
    {
        UndoOp read = ReadARelink(json =>
        {
            switch (barrier)
            {
                case "the two texts the same":
                    json["linkShaAfter"] = OldTextSha;
                    json["blobs"] = new JsonArray(OldTextSha);
                    break;
                case "one text missing from blobs":
                    json["blobs"] = new JsonArray(OldTextSha);
                    break;
                case "a third blob beside the two":
                    json["blobs"] = new JsonArray(OldTextSha, NewTextSha, UndoCheck.Sha(Bytes("Unit 1, Day 2.md")));
                    break;
                case "linkShaBefore alone":
                    json.Remove("linkShaAfter");
                    json["blobs"] = new JsonArray(OldTextSha);
                    break;
                case "linkShaAfter alone":
                    json.Remove("linkShaBefore");
                    json["blobs"] = new JsonArray(NewTextSha);
                    break;
                case "linkSha beside the pair":
                    // No shared row (relink-2's "For the director" 1, option a): this is Windows' pin. A reader
                    // that knew linkSha but not the pair would otherwise Redo a plain link's move with the OLD text.
                    json["linkSha"] = OldTextSha;
                    break;
                case "sha beside the pair":
                    json["sha"] = OldTextSha;
                    break;
                case "a text that is not a blob name":
                    json["linkShaAfter"] = "Unit 1, Day 4.md";
                    json["blobs"] = new JsonArray(OldTextSha, "Unit 1, Day 4.md");
                    break;
                case "the pair on a moveApart":
                    json["kind"] = "moveApart";
                    break;
                case "the pair on a capitalisation-only move":
                    json["to"] = Section + "/unit 1, day 4.md";
                    break;
                case "the pair on a move to its own place":
                    json["to"] = Day(4);
                    break;
            }
        });
        Assert.False(read.Readable, barrier);
    }

    /// <summary>The capitalisation-only barrier is the relink's own: the same rename with a plain link's linkSha IS readable.</summary>
    [Fact]
    public void APlainLinksCapitalisationOnlyMoveIsStillReadable()
    {
        UndoOp read = ReadARelink(json =>
        {
            json.Remove("linkShaBefore");
            json.Remove("linkShaAfter");
            json.Remove("blobs");
            json["linkSha"] = OldTextSha;
            json["to"] = Section + "/unit 1, day 4.md";
        });
        Assert.True(read.Readable);
    }

    // ---- Killed (21b3; the mac's U4b3 relink-3 and reviews D and F) -----------

    /// <summary>A step of this shape made through a door that names a process that is gone, stopped where <paramref name="stopping"/> says; its number.</summary>
    private static long MakeTheStep(UndoScribe scribe, string shape, string work, UndoSeams stopping, out UndoOutcome stopped)
    {
        (JsonArray ops, List<byte[]> blobs) = UndoRelinkForTheCases.Lay(scribe, shape);
        UndoOpsDraft draft = scribe.OpsDraft("A", ops, blobs, "insertClass");
        if (work == "apply")
        {
            stopped = scribe.Door(stopping, UndoScribe.AProcessThatIsGone).Perform(draft);
            return scribe.Fold().Steps.Keys.Max();
        }
        Assert.Equal(UndoOutcomeKind.Applied, scribe.Door().Perform(draft).Kind);
        if (work == "redo") Assert.Equal(UndoOutcomeKind.Undone, scribe.Door().Undo().Kind);
        stopped = work == "undo"
            ? scribe.Door(stopping, UndoScribe.AProcessThatIsGone).Undo()
            : scribe.Door(stopping, UndoScribe.AProcessThatIsGone).Redo();
        return scribe.Fold().Steps.Keys.Max();
    }

    /// <summary>
    /// What a recovery of this kill left: <c>before</c> or <c>after</c> (the
    /// class pages and the library exactly as laid, or as the step makes
    /// them), else what they hold; and the step's state.
    /// </summary>
    private static (string Files, string Phase) KillAndRecover(string shape, string work, string point, int index, string madeWhole, out bool reached)
    {
        using var scribe = new UndoScribe();
        var stopping = new UndoSeams { StopsHere = (at, where) => at == point && (index < 0 || where == index) };
        long seq = MakeTheStep(scribe, shape, work, stopping, out UndoOutcome stopped);
        reached = stopped.Kind == UndoOutcomeKind.StoppedByATest;
        if (!reached) return ("", "");
        string laid = BeforeOf(shape);
        scribe.Door().Recover();
        string now = UndoHandoverForTheCases.Snapshot(scribe);
        string files = now == laid ? "before" : now == madeWhole ? "after" : now;
        Assert.Empty(scribe.StagedLeftovers("A"));
        return (files, UndoContract.Spelled(scribe.Fold().Steps[seq].State));
    }

    /// <summary>The class pages and the library of this shape as laid, before any step.</summary>
    private static string BeforeOf(string shape)
    {
        using var scribe = new UndoScribe();
        UndoRelinkForTheCases.Lay(scribe, shape);
        return UndoHandoverForTheCases.Snapshot(scribe);
    }

    /// <summary>
    /// Each relinking chain of review D and F, and the plain link move chained
    /// to a relink either way round, killed with both links standing inside a
    /// swap or between swaps, settles to exactly the side the rule names: the
    /// one link it removes is the one named by the test (a rolled-back step
    /// shows the link removed was the one just made, since the earlier move
    /// was then judged done), and a plain link move whose link holds the
    /// relink's new text is never taken for one just made.
    /// </summary>
    [SymbolicLinkTheory]
    // Review D: inside the second swap, Day 5's new link beside Day 4's old: Day 5's removed, Day 6's kept (rolled back, not failed).
    [InlineData("chained", "apply", "relinkRenamedIn", 1, "before", "rolledBack")]
    // Review D: before the first swap, Day 5's link is the first move's own, never the second's just made.
    [InlineData("chained", "apply", "beforeSwap", 0, "before", "failed")]
    // Review D: the undo's first swap, Day 4's link made again beside Day 5's: Day 5's removed (the LAST that passes), put forward again.
    [InlineData("chained", "undo", "relinkRenamedIn", 0, "after", "done")]
    // Review F: after both swaps, the first move stands both ways but the second no longer holds its start text: nothing removed.
    [InlineData("chained", "apply", "beforeApplied", -1, "after", "done")]
    [InlineData("chained", "redo", "beforeRedone", -1, "after", "done")]
    // Review F: three chained, inside each swap and before the first.
    [InlineData("chainedThree", "apply", "beforeSwap", 0, "before", "failed")]
    // (A kill inside any of the three swaps leaves the same folder: the LAST that passes loses its link, so it reads as the first two done.)
    [InlineData("chainedThree", "apply", "relinkRenamedIn", 0, "before", "rolledBack")]
    [InlineData("chainedThree", "apply", "relinkRenamedIn", 1, "before", "rolledBack")]
    [InlineData("chainedThree", "apply", "relinkRenamedIn", 2, "before", "rolledBack")]
    // Review F: a relink, then a plain move into its place, after both swaps: nothing removed.
    [InlineData("thenAMove", "apply", "beforeApplied", -1, "after", "done")]
    [InlineData("thenAMove", "undo", "afterUndoing", -1, "after", "done")]
    // Review F's counter-example: a plain move whose link holds the relink's new text, before anything moved: never taken for one just made.
    [InlineData("aMoveThenARelink", "apply", "afterBegin", -1, "before", "failed")]
    [InlineData("aMoveThenARelink", "apply", "beforeSwap", 0, "before", "failed")]
    [InlineData("aMoveThenARelink", "undo", "beforeUndone", -1, "before", "undone")]
    [InlineData("aMoveThenARelink", "redo", "afterRedoing", -1, "before", "undone")]
    public void AKilledChainRemovesExactlyTheOneLinkTheRuleNames(string shape, string work, string point, int index, string files, string phase)
    {
        (string left, string settled) = KillAndRecover(shape, work, point, index, UndoRelinkForTheCases.MadeWhole(shape), out bool reached);
        Assert.True(reached, $"{shape}-{work} did not stop at {point}:{index}");
        Assert.Equal(files, left);
        Assert.Equal(phase, settled);
    }

    /// <summary>
    /// Every shape killed at every stop point the door has, going forward, in
    /// an Undo and in a Redo, loses no link: after recovery every page and
    /// link is exactly as before or exactly as after, nothing staged is left,
    /// and the step is settled on the side its links show. The kills reached
    /// are counted: an apply 2 + swaps + 2 x relinks (afterBegin, each
    /// beforeSwap, both halves of each relink, beforeApplied); an Undo or a
    /// Redo 3 + swaps + 2 x relinks (afterTheCheck, afterUndoing or
    /// afterRedoing, and beforeUndone or beforeRedone).
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("alone", "apply")]
    [InlineData("alone", "undo")]
    [InlineData("alone", "redo")]
    [InlineData("leavingAHandedOverPlace", "apply")]
    [InlineData("leavingAHandedOverPlace", "undo")]
    [InlineData("chained", "apply")]
    [InlineData("chained", "undo")]
    [InlineData("chained", "redo")]
    [InlineData("chainedThree", "apply")]
    [InlineData("chainedThree", "undo")]
    [InlineData("thenAMove", "apply")]
    [InlineData("thenAMove", "undo")]
    [InlineData("thenAMove", "redo")]
    [InlineData("aMoveThenARelink", "apply")]
    [InlineData("aMoveThenARelink", "undo")]
    [InlineData("aMoveThenARelink", "redo")]
    public void EveryShapeKilledAtEveryStopPointLosesNoLink(string shape, string work)
    {
        (JsonArray ops, int relinks) = OpsOf(shape);
        int swaps = ops.Count;
        var points = new List<(string Point, int Index)>();
        if (work == "apply") points.Add(("afterBegin", -1));
        else points.Add(("afterTheCheck", -1));
        if (work == "undo") points.Add(("afterUndoing", -1));
        if (work == "redo") points.Add(("afterRedoing", -1));
        for (int index = 0; index < swaps; index++)
        {
            points.Add(("beforeSwap", index));
            points.Add(("relinkStaged", index));
            points.Add(("relinkRenamedIn", index));
        }
        points.Add((work switch { "apply" => "beforeApplied", "undo" => "beforeUndone", _ => "beforeRedone" }, -1));
        string madeWhole = UndoRelinkForTheCases.MadeWhole(shape);
        int reachedCount = 0;
        var lost = new List<string>();
        foreach ((string point, int index) in points)
        {
            (string left, string settled) = KillAndRecover(shape, work, point, index, madeWhole, out bool reached);
            if (!reached) continue;
            reachedCount++;
            bool wholeSide = left == "after"
                ? settled == "done"
                : left == "before" && (work == "apply" ? settled is "failed" or "rolledBack" : settled == "undone");
            if (!wholeSide) lost.Add($"{shape}-{work}-{point}:{index}: {left} {settled}");
        }
        Assert.Empty(lost);
        Assert.Equal((work == "apply" ? 2 : 3) + swaps + 2 * relinks, reachedCount);
    }

    private static (JsonArray Ops, int Relinks) OpsOf(string shape)
    {
        using var scribe = new UndoScribe();
        (JsonArray ops, _) = UndoRelinkForTheCases.Lay(scribe, shape);
        int relinks = 0;
        foreach (JsonNode? op in ops)
        {
            if (op?["linkShaBefore"] is not null) relinks++;
        }
        return (ops, relinks);
    }

    /// <summary>
    /// A relink's two stop points are asked only going in, never by a
    /// reversal: a later target refused after the relink went in reverses it
    /// with no stop point asked, so the swap is refused, never stopped.
    /// </summary>
    [SymbolicLinkFact]
    public void ARelinksStopPointsAreAskedGoingInOnlyNeverInAReversal()
    {
        LaidRelink laid = LayARelink("inside");
        WritePage(Day(8), "Eight.\n");
        UndoOp fileMove = new UndoOp { Kind = UndoOp.Move, Readable = true, From = Day(8), To = Day(9), Sha = UndoCheck.Sha(Bytes("Eight.\n")) };
        List<UndoSwapTarget> targets = ReadyTargets(Plan([laid.Op, fileMove], backward: false));
        var asked = new List<string>();
        var seams = new UndoSeams
        {
            BeforeEachSwap = (index, _) => { if (index == 1) WritePage(Day(9), "Someone's.\n"); },
            StopsHere = (point, index) =>
            {
                if (point.StartsWith("relink", StringComparison.Ordinal)) asked.Add(point + ":" + index);
                return false;
            },
        };

        UndoSwapResult result = UndoSwap.Swap(targets, "1-apply", _root, seams);

        Assert.True(result is UndoSwapResult.Refused, Described(result));
        Assert.Equal(["relinkStaged:0", "relinkRenamedIn:0"], asked);
        Assert.Equal(laid.OldText, LinkText(Day(4)));
        Assert.False(StandsAnything(Day(5)));
        Assert.Empty(StagedLeft());
    }

    // ---- Recorded by UndoActionStep (21b5; the mac's U4b3 relink-4, JournaledStepTests) ----

    private readonly List<UndoTrailLine> _trail = [];

    /// <summary>The list a recorded step goes to: beside the root, never inside the working folder, never outside's.</summary>
    private string ListFolder => _root.TrimEnd(Path.DirectorySeparatorChar) + "-list";

    /// <summary>The root as a working folder: its launcher and the course's settings, so a step can be named in it.</summary>
    private void AWorkingFolder()
    {
        File.WriteAllText(Path.Combine(_root, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        WritePage("courses/TST1O/course_config.json", "{\"course_code\":\"TST1O\"}");
    }

    private UndoForThisProcess StepList() => new(ListFolder, UndoMode.Shadow, _trail.Add);

    private UndoActionStep StepIn(UndoForThisProcess list, string? workingFolder, UndoSeams? seams = null) =>
        new(new UndoStepMaker("sheet", "insertClass"), workingFolder, "TST1O", 1, undo: list, plainSeams: seams);

    /// <summary>What the working folder holds but the list's own files under courses/.internal: a link by its text, a file by its bytes.</summary>
    private string CourseNow()
    {
        var said = new StringBuilder();
        foreach (string entry in Directory.EnumerateFileSystemEntries(_root, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
        {
            string relative = Path.GetRelativePath(_root, entry).Replace('\\', '/');
            if (UndoOp.PartInside("courses/.internal", relative) is not null) continue;
            said.Append(relative).Append(' ');
            said.Append(UndoLinks.Look(entry) switch
            {
                UndoLinks.What.Link => "link " + new FileInfo(entry).LinkTarget,
                UndoLinks.What.File => "file " + Convert.ToHexString(File.ReadAllBytes(entry)),
                UndoLinks.What.Folder => "folder",
                UndoLinks.What what => what.ToString(),
            }).Append('\n');
        }
        return said.ToString();
    }

    /// <summary>Each step's ops, oldest first, as the list's begins hold them.</summary>
    private List<JsonArray> StepsOnTheList()
    {
        var steps = new List<JsonArray>();
        if (!Directory.Exists(ListFolder)) return steps;
        foreach (string segment in Directory.EnumerateFiles(ListFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") steps.Add(read["step"]!["ops"]!.AsArray());
            }
        }
        return steps;
    }

    private static List<UndoOp> ReadOpsOf(JsonArray ops)
    {
        var read = new List<UndoOp>();
        foreach (JsonNode? op in ops) read.Add(UndoLineOps.Read(op!.AsObject()));
        return read;
    }

    /// <summary>Undo, then Redo, through the list: each gives the course exactly as it was on that side.</summary>
    private void UndoAndRedoExactly(UndoForThisProcess list, string before, string after)
    {
        Assert.Equal(UndoOutcomeKind.Undone, list.Door().Undo().Kind);
        Assert.Equal(before, CourseNow());
        Assert.Equal(UndoOutcomeKind.Redone, list.Door().Redo().Kind);
        Assert.Equal(after, CourseNow());
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// A relink alone (the mac's testARelinkAloneIsRecordedWithBothTextsAndUndoneAndRedone):
    /// one op holding both texts' shas and no linkSha, both texts in the list
    /// by name byte for byte, the new link holding exactly the new text and
    /// nothing at the old; Undo and Redo exact; nothing outside touched.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("inside")]
    [InlineData("outToAFile")]
    [InlineData("outToNothing")]
    public void ARelinkAloneIsRecordedWithBothTextsAndUndoneAndRedone(string leads)
    {
        LaidRelink laid = LayARelink(leads);
        AWorkingFolder();
        string before = CourseNow();
        string outside = OutsideNow();
        UndoForThisProcess list = StepList();
        UndoActionStep step = StepIn(list, _root);

        Assert.Equal(UndoRelinkPlanned.Relinked, step.RelinkLink(Full(Day(4)), Full(Day(5)), laid.NewText));
        step.Make();

        JsonObject op = Assert.Single(Assert.Single(StepsOnTheList()))!.AsObject();
        string oldSha = UndoCheck.Sha(Bytes(laid.OldText));
        string newSha = UndoCheck.Sha(Bytes(laid.NewText));
        Assert.Equal("move", (string?)op["kind"]);
        Assert.Equal(Day(4), (string?)op["from"]);
        Assert.Equal(Day(5), (string?)op["to"]);
        Assert.Equal(oldSha, (string?)op["linkShaBefore"]);
        Assert.Equal(newSha, (string?)op["linkShaAfter"]);
        Assert.Null(op["linkSha"]);
        Assert.Equal([oldSha, newSha], op["blobs"]!.AsArray().Select(name => (string?)name));
        Assert.Equal(Bytes(laid.OldText), list.Journal.Blob(oldSha));
        Assert.Equal(Bytes(laid.NewText), list.Journal.Blob(newSha));
        Assert.Equal(laid.NewText, LinkText(Day(5)));
        Assert.False(StandsAnything(Day(4)));
        Assert.Empty(_trail);
        string after = CourseNow();

        UndoAndRedoExactly(list, before, after);
        Assert.Equal(outside, OutsideNow());
        CheckTheOutsideBytes(leads);
    }

    /// <summary>Insert Class's own shape: Day 4's link relinked to Day 5, Day 3's page written at Day 4 and removed, a new Day 3.</summary>
    private void PlanInsertClassBeforeDay3(UndoActionStep step, UndoRelinkPlanned answered)
    {
        Assert.Equal(answered, step.RelinkLink(Full(Day(4)), Full(Day(5)), "Unit 1, Day 4.md"));
        Assert.False(step.Exists(Full(Day(4))), "the place the relink leaves reads as free");
        step.Write(Full(Day(4)), "Three, retitled.\n");
        step.Remove(Full(Day(3)));
        step.Write(Full(Day(3)), "New.\n");
    }

    /// <summary>Insert Class's own shape (the mac's testARelinkWhoseOldPlaceIsFilledInTheSameStepIsOneStep): one step, one handover, Undo and Redo exact.</summary>
    [SymbolicLinkFact]
    public void ARelinkWhoseOldPlaceIsFilledInTheSameStepIsOneStep()
    {
        WritePage(Day(3), "Three.\n");
        LayLink(Day(4), "Unit 1, Day 3.md");
        AWorkingFolder();
        string before = CourseNow();
        UndoForThisProcess list = StepList();
        UndoActionStep step = StepIn(list, _root);

        PlanInsertClassBeforeDay3(step, UndoRelinkPlanned.Relinked);
        step.Make();

        List<UndoOp> ops = ReadOpsOf(Assert.Single(StepsOnTheList()));
        UndoHandover handover = Assert.Single(UndoOp.Handovers(ops));
        Assert.True(UndoStep.WholeOpsStandAlone(ops));
        Assert.Equal("Unit 1, Day 4.md", LinkText(Day(5)));
        Assert.Equal(UndoLinks.What.File, UndoLinks.Look(Full(Day(4))));
        Assert.Equal("Three, retitled.\n", File.ReadAllText(Full(Day(4))));
        Assert.Equal("New.\n", File.ReadAllText(Full(Day(3))));
        Assert.Empty(_trail);

        Assert.Equal(Day(4), handover.Place);
        UndoAndRedoExactly(list, before, CourseNow());
    }

    /// <summary>Two relinks in a row, Day 3 to Day 4 planned before Day 4 to Day 5, each with its own new text (the mac's testTwoRelinksInARowAreOneStep): one step, exact both ways.</summary>
    [SymbolicLinkFact]
    public void TwoRelinksInARowAreOneStep()
    {
        LayLink(Day(3), "../../elsewhere/three.md");
        LayLink(Day(4), "../../elsewhere/four.md");
        AWorkingFolder();
        string before = CourseNow();
        UndoForThisProcess list = StepList();
        UndoActionStep step = StepIn(list, _root);

        Assert.Equal(UndoRelinkPlanned.Relinked, step.RelinkLink(Full(Day(3)), Full(Day(4)), "../../elsewhere/four.md"));
        Assert.Equal(UndoRelinkPlanned.Relinked, step.RelinkLink(Full(Day(4)), Full(Day(5)), "../../elsewhere/five.md"));
        step.Make();

        List<UndoOp> ops = ReadOpsOf(Assert.Single(StepsOnTheList()));
        Assert.Equal(2, ops.Count);
        Assert.Single(UndoOp.Handovers(ops));
        Assert.Equal("../../elsewhere/five.md", LinkText(Day(5)));
        Assert.Equal("../../elsewhere/four.md", LinkText(Day(4)));
        Assert.False(StandsAnything(Day(3)));

        UndoAndRedoExactly(list, before, CourseNow());
    }

    /// <summary>
    /// A write at a relink's new name would be a write through a link whose
    /// text the step changes (the mac's testAWriteAtARelinksNewNameIsRefusedBeforeAnythingChanges):
    /// by text, by the bytes it was planned from, or planned before the
    /// relink, the step is refused cannotTellNow, the folder unchanged and
    /// nothing on the list.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("byText")]
    [InlineData("byReadBytes")]
    [InlineData("beforeTheRelink")]
    public void AWriteAtARelinksNewNameIsRefusedBeforeAnythingChanges(string planned)
    {
        string target = Path.Combine(_outside, "Unit 1, Day 3.md");
        File.WriteAllText(target, "Outside three.\n");
        LayLink(Day(4), target);
        AWorkingFolder();
        string before = CourseNow();
        UndoForThisProcess list = StepList();
        UndoActionStep step = StepIn(list, _root);
        string newText = Path.Combine(_outside, "Unit 1, Day 4.md");

        UndoStepRefusedException refused;
        if (planned == "beforeTheRelink")
        {
            step.Write(Full(Day(5)), "Through.\n");
            refused = Assert.Throws<UndoStepRefusedException>(() => step.RelinkLink(Full(Day(4)), Full(Day(5)), newText));
        }
        else
        {
            Assert.Equal(UndoRelinkPlanned.Relinked, step.RelinkLink(Full(Day(4)), Full(Day(5)), newText));
            refused = planned == "byText"
                ? Assert.Throws<UndoStepRefusedException>(() => step.Write(Full(Day(5)), "Through.\n"))
                : Assert.Throws<UndoStepRefusedException>(() => step.WriteBytes(Full(Day(5)), Bytes("Through.\n"), File.ReadAllBytes(target)));
        }

        Assert.Equal(UndoRefusalKind.CannotTellNow, refused.Refusal.Kind);
        Assert.Equal(before, CourseNow());
        Assert.Equal("Outside three.\n", File.ReadAllText(target));
        Assert.Empty(StepsOnTheList());
    }

    /// <summary>
    /// The list refusing the relink's NEW text (its blob's folder a file, so
    /// it cannot be made) with the switch off (the mac's
    /// testARelinkWhoseNewTextTheListRefusesGoesAheadUnrecorded): one line
    /// saying it went ahead, nothing on the list, and the relink made as the
    /// door would have made it.
    /// </summary>
    [SymbolicLinkFact]
    public void ARelinkWhoseNewTextTheListRefusesGoesAheadUnrecorded()
    {
        const string oldText = "Unit 1, Day 3.md";
        const string newText = "Unit 1, Day 4.md";
        LayLink(Day(4), oldText);
        AWorkingFolder();
        UndoForThisProcess list = StepList();
        string oldFolder = Path.GetDirectoryName(list.Journal.BlobPath(UndoCheck.Sha(Bytes(oldText))))!;
        string newFolder = Path.GetDirectoryName(list.Journal.BlobPath(UndoCheck.Sha(Bytes(newText))))!;
        Assert.NotEqual(oldFolder, newFolder);
        Directory.CreateDirectory(Path.GetDirectoryName(newFolder)!);
        File.WriteAllText(newFolder, "Not a folder.\n");
        UndoActionStep step = StepIn(list, _root);

        Assert.Equal(UndoRelinkPlanned.Relinked, step.RelinkLink(Full(Day(4)), Full(Day(5)), newText));
        step.Make();

        UndoTrailLine line = Assert.Single(_trail);
        Assert.Equal(Plantoir.Core.Scripting.ActivityTrail.Event.UndoCouldNotRecordAStep, line.Event);
        Assert.EndsWith("The change went ahead (the list is not in use yet).", line.Words);
        Assert.Empty(StepsOnTheList());
        Assert.Null(list.Journal.Blob(UndoCheck.Sha(Bytes(newText))));
        Assert.Equal(newText, LinkText(Day(5)));
        Assert.False(StandsAnything(Day(4)));
        Assert.Empty(StagedLeft());
    }

    /// <summary>
    /// Insert Class's own shape where this PC cannot make a link (the seam;
    /// Russell's Q2, 21b1a): answered copied, the end tree 21b1a's (a plain
    /// copy of the lesson at Day 5, the link set aside as itself), and Undo
    /// puts the link back at Day 4 exactly.
    /// </summary>
    [SymbolicLinkFact]
    public void WhereNoLinkCanBeMadeTheLessonIsCopiedAndUndoPutsTheLinkBack()
    {
        WritePage(Day(3), "Three.\n");
        LayLink(Day(4), "Unit 1, Day 3.md");
        AWorkingFolder();
        string before = CourseNow();
        UndoForThisProcess list = StepList();
        UndoActionStep step = StepIn(list, _root, new UndoSeams { CanMakeALinkAnswers = false });

        PlanInsertClassBeforeDay3(step, UndoRelinkPlanned.Copied);
        step.Make();

        Assert.Equal([Path.GetFullPath(Full(Day(5)))], step.CopiedInsteadOfLinks);
        Assert.Equal(UndoLinks.What.File, UndoLinks.Look(Full(Day(5))));
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(5))));
        Assert.Equal("Unit 1, Day 3.md", LinkText(Section + "/.Unit 1, Day 4.md.link-kept-by-undo"));
        Assert.Equal("Three, retitled.\n", File.ReadAllText(Full(Day(4))));
        Assert.Equal("New.\n", File.ReadAllText(Full(Day(3))));
        string after = CourseNow();

        Assert.Equal(UndoOutcomeKind.Undone, list.Door().Undo().Kind);
        Assert.Equal(before, CourseNow());
        Assert.Equal("Unit 1, Day 3.md", LinkText(Day(4)));
        Assert.Equal(UndoOutcomeKind.Redone, list.Door().Redo().Kind);
        Assert.Equal(after, CourseNow());
    }

    /// <summary>A place that is not a link, or none at all, plans nothing and says so; a text unchanged is the link's plain move.</summary>
    [SymbolicLinkFact]
    public void ARelinkOfNoLinkPlansNothingAndOfTheSameTextIsAPlainMove()
    {
        WritePage(Day(3), "Three.\n");
        LayLink(Day(4), "Unit 1, Day 3.md");
        AWorkingFolder();
        UndoActionStep step = StepIn(StepList(), _root);

        Assert.Equal(UndoRelinkPlanned.NotPlanned, step.RelinkLink(Full(Day(3)), Full(Day(6)), "Unit 1, Day 2.md"));
        Assert.Equal(UndoRelinkPlanned.NotPlanned, step.RelinkLink(Full(Day(7)), Full(Day(8)), "Unit 1, Day 2.md"));
        Assert.False(step.ChangesAnything);
        Assert.Equal(UndoRelinkPlanned.Moved, step.RelinkLink(Full(Day(4)), Full(Day(5)), "Unit 1, Day 3.md"));
        step.Make();

        JsonObject op = Assert.Single(Assert.Single(StepsOnTheList()))!.AsObject();
        Assert.Equal(UndoCheck.Sha(Bytes("Unit 1, Day 3.md")), (string?)op["linkSha"]);
        Assert.Null(op["linkShaBefore"]);
        Assert.Equal("Unit 1, Day 3.md", LinkText(Day(5)));
    }

    /// <summary>
    /// The text a relink writes (the director's reading of 21b1's parked
    /// point, one function, <see cref="UndoLinks.TextToWrite"/>): a text whose
    /// last path part alone changes keeps the rest as stored, byte for byte,
    /// forward slashes included; any other text Windows writes has
    /// backslashes, so the system opens it.
    /// </summary>
    [Theory]
    [InlineData("Unit 1, Day 3.md", "Unit 1, Day 4.md", "Unit 1, Day 4.md")]
    [InlineData("../library/Day 3.md", "../library/Day 4.md", "../library/Day 4.md")]
    [InlineData("../library/Day 3.md", "..\\library\\Day 4.md", "../library/Day 4.md")]
    [InlineData("..\\library\\Day 3.md", "../library/Day 4.md", "..\\library\\Day 4.md")]
    [InlineData("../library/Day 3.md", "../shared/Day 4.md", "..\\shared\\Day 4.md")]
    [InlineData("Unit 1, Day 3.md", "../library/Day 4.md", "..\\library\\Day 4.md")]
    public void ALinkTextIsKeptAsStoredWhenOnlyItsLastPartChanges(string textNow, string wanted, string written)
    {
        Assert.Equal(written, UndoLinks.TextToWrite(textNow, wanted));
    }
}
