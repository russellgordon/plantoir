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
/// removed only once re-read holding the source's text. Inert: the op is
/// built in memory, and from the journal it is still not readable (21b2).
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

    /// <summary>A staged <c>-new</c> link a stopped swap left is removed by the tidy as the link itself: what it leads to is untouched.</summary>
    [SymbolicLinkFact]
    public void AStagedNewLinkIsTidiedAsTheLinkItself()
    {
        WritePage(Day(3), "Three.\n");
        string staged = UndoSwap.BesidePath(Full(Day(5)), "1-apply", "new");
        File.CreateSymbolicLink(staged, "Unit 1, Day 3.md");
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(staged));

        Assert.True(UndoSwap.TidyLeftovers(1, [Day(5)], _root));

        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(staged));
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(3))));
    }

    /// <summary>Inert: a relink from the journal (linkShaBefore and linkShaAfter, no sha, listingSha or linkSha) is still not readable until 21b2.</summary>
    [Fact]
    public void ARelinkFromTheJournalIsStillUnreadable()
    {
        string before = UndoCheck.Sha(Bytes("Unit 1, Day 3.md")), after = UndoCheck.Sha(Bytes("Unit 1, Day 4.md"));
        var json = new JsonObject
        {
            ["kind"] = "move", ["from"] = Day(4), ["to"] = Day(5),
            ["linkShaBefore"] = before, ["linkShaAfter"] = after, ["blobs"] = new JsonArray(before, after),
        };
        using JsonDocument document = JsonDocument.Parse(json.ToJsonString());
        UndoOp read = UndoFormat.ReadOp(document.RootElement);
        Assert.False(read.Readable);
        Assert.Null(read.LinkSha);
    }
}
