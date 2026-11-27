using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// W8b-21a1 of #899 (Windows' copy of the mac's U4b3 door-1): a HANDED-OVER
/// place, one an earlier op of a step leaves (a file's or a link's move away,
/// or a removal) and a later op fills (a move in, or a new file), at least one
/// of the two a plain move with <c>sha</c> or <c>linkSha</c>. Insert Class
/// makes such steps when a later class is a symbolic link: the link moves up a
/// day and the class below it, or the new class, fills its place. No step
/// readable today holds one (the step's shape check refuses it until
/// 21a4), so the check and the swap are called directly here, with ops
/// built in memory.
/// </summary>
public sealed class UndoHandedOverPlaceTests : IDisposable
{
    private const string Section = "courses/TST1O/section1";
    private const string Library = "courses/TST1O/library";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-handed-over-");
    private readonly string _outside;

    public UndoHandedOverPlaceTests()
    {
        _outside = _root.TrimEnd(Path.DirectorySeparatorChar) + "-outside";
        Directory.CreateDirectory(_outside);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
        try { Directory.Delete(_outside, recursive: true); } catch { }
    }

    private static string Day(int number) => Section + "/Unit 1, Day " + number + ".md";

    private string Full(string relative) => Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));

    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);

    private static UndoOp Op(JsonObject json)
    {
        using JsonDocument document = JsonDocument.Parse(json.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    private static UndoOp NewFile(string path, string text) =>
        Op(new JsonObject { ["kind"] = "writeFile", ["path"] = path, ["afterSha"] = UndoCheck.Sha(Bytes(text)) });

    private static UndoOp Removal(string path, string text) =>
        Op(new JsonObject { ["kind"] = "writeFile", ["path"] = path, ["beforeSha"] = UndoCheck.Sha(Bytes(text)) });

    private static UndoOp FileMove(string from, string to, string text) =>
        Op(new JsonObject { ["kind"] = "move", ["from"] = from, ["to"] = to, ["sha"] = UndoCheck.Sha(Bytes(text)) });

    private UndoOp LinkMove(string from, string to) =>
        Op(new JsonObject { ["kind"] = "move", ["from"] = from, ["to"] = to, ["linkSha"] = UndoLinks.LinkSha(Full(from)) });

    /// <summary>A link that holds no place on the disk, for the finder alone.</summary>
    private static UndoOp LinkMoveInMemory(string from, string to) =>
        Op(new JsonObject { ["kind"] = "move", ["from"] = from, ["to"] = to, ["linkSha"] = UndoLinkMoveTests.ShaOfTarget("../library/Day 3.md") });

    private void WritePage(string relative, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllBytes(Full(relative), Bytes(text));
    }

    /// <summary>
    /// A page's symbolic link at <paramref name="place"/>, to a library page
    /// in the course (held as written, <c>../library/…</c>) or, leading out,
    /// to a page outside the working folder by its full path.
    /// </summary>
    private void LayLink(string place, string libraryPage, bool leadingOut)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(place))!);
        if (leadingOut)
        {
            string outsidePage = Path.Combine(_outside, libraryPage);
            File.WriteAllBytes(outsidePage, Bytes("Linked.\n"));
            File.CreateSymbolicLink(Full(place), outsidePage);
            return;
        }
        WritePage(Library + "/" + libraryPage, "Linked.\n");
        File.CreateSymbolicLink(Full(place), "../library/" + libraryPage);
    }

    private UndoCheck.PlanResult PlanForward(IReadOnlyList<UndoOp> ops) => PlanIn(ops, backward: false, readAt: null);

    /// <summary>The plan going back (an Undo); each place the check reads a file op at is told to <paramref name="readAt"/>.</summary>
    private UndoCheck.PlanResult PlanBackward(IReadOnlyList<UndoOp> ops, List<string>? readAt = null) => PlanIn(ops, backward: true, readAt);

    private UndoCheck.PlanResult PlanIn(IReadOnlyList<UndoOp> ops, bool backward, List<string>? readAt)
    {
        var blobs = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (string text in new[] { "New.\n", "Three.\n", "Two.\n", "A\n", "A2\n", "B\n", "C\n" }) blobs[UndoCheck.Sha(Bytes(text))] = Bytes(text);
        return UndoCheck.Plan(ops, backward, relative =>
                              {
                                  readAt?.Add(relative);
                                  return UndoCurrent.Read(Full(relative));
                              },
                              sha => blobs.TryGetValue(sha, out byte[]? bytes) ? bytes : null,
                              whole: new UndoWholeReads(_root, new UndoMemoryPlaces()));
    }

    private static List<string> PlacesOf(IReadOnlyList<UndoSwapTarget> targets)
    {
        var places = new List<string>();
        foreach (UndoSwapTarget target in targets) places.Add(target.RelativePath);
        return places;
    }

    private static string Described(UndoCheck.PlanResult plan) => plan switch
    {
        UndoCheck.PlanResult.ChangedSince changed => "changedSince " + changed.First,
        _ => plan.GetType().Name,
    };

    private static string Described(UndoSwapResult result) => result switch
    {
        UndoSwapResult.Refused refused => "refused " + refused.Refusal.Kind + " " + refused.Refusal.Path,
        _ => result.GetType().Name,
    };

    // ---- The one finder ---------------------------------------------------

    /// <summary>Shape A: a link's move away from Day 3, then a new file at Day 3: Day 3 is handed over, from op 0 to op 1.</summary>
    [Fact]
    public void ALinksMoveAwayThenANewFileHandsThePlaceOver()
    {
        IReadOnlyList<UndoHandover> found = UndoOp.Handovers([LinkMoveInMemory(Day(3), Day(4)), NewFile(Day(3), "New.\n")]);

        UndoHandover handover = Assert.Single(found);
        Assert.Equal(0, handover.LeaverIndex);
        Assert.Equal(1, handover.FillerIndex);
        Assert.Equal(Day(3), handover.Place);
        Assert.True(handover.ALinkMoves);
    }

    /// <summary>Shape B: a removal at Day 3, then a link's move from Day 2 into Day 3.</summary>
    [Fact]
    public void ARemovalThenALinksMoveInHandsThePlaceOver()
    {
        UndoHandover handover = Assert.Single(UndoOp.Handovers([Removal(Day(3), "Three.\n"), LinkMoveInMemory(Day(2), Day(3))]));

        Assert.Equal((0, 1, Day(3), true), (handover.LeaverIndex, handover.FillerIndex, handover.Place, handover.ALinkMoves));
    }

    /// <summary>The place is compared part by part without regard to case (<see cref="UndoOp.PartInside"/>): a file's move hands it to a filler spelled otherwise.</summary>
    [Fact]
    public void AFilesMoveHandsItsPlaceToAFillerSpelledInAnotherCase()
    {
        UndoHandover handover = Assert.Single(UndoOp.Handovers([FileMove(Day(3), Day(4), "Three.\n"), NewFile(Day(3).ToLowerInvariant(), "New.\n")]));

        Assert.Equal((0, 1, Day(3), false), (handover.LeaverIndex, handover.FillerIndex, handover.Place, handover.ALinkMoves));
    }

    /// <summary>Each leaver hands its place to the FIRST filler after it, and a filler before the leaver is none.</summary>
    [Fact]
    public void ALeaverHandsItsPlaceToTheFirstFillerAfterIt()
    {
        IReadOnlyList<UndoHandover> found = UndoOp.Handovers([
            NewFile(Day(3), "B\n"), LinkMoveInMemory(Day(3), Day(4)), NewFile(Day(3), "New.\n"), LinkMoveInMemory(Day(2), Day(3)),
        ]);

        UndoHandover handover = Assert.Single(found);
        Assert.Equal((1, 2), (handover.LeaverIndex, handover.FillerIndex));
    }

    /// <summary>A removal and a new file at one place, no move between them: never a handover (at least one of the two is a move).</summary>
    [Fact]
    public void TwoWritesWithNoMoveNeverHandOver()
    {
        Assert.Empty(UndoOp.Handovers([Removal(Day(3), "Three.\n"), NewFile(Day(3), "New.\n")]));
    }

    /// <summary>A folder's move (<c>listingSha</c>) never hands its place over.</summary>
    [Fact]
    public void AFoldersMoveNeverHandsOver()
    {
        UndoOp folderMove = Op(new JsonObject
        {
            ["kind"] = "move", ["from"] = Section + "/media", ["to"] = Section + "/renamed", ["listingSha"] = new UndoTreeListing([], []).Sha,
        });
        Assert.True(folderMove.Readable);

        Assert.Empty(UndoOp.Handovers([folderMove, NewFile(Section + "/media", "New.\n")]));
        Assert.Empty(UndoOp.Handovers([Removal(Section + "/renamed", "Three.\n"), folderMove]));
    }

    /// <summary>A capitalisation-only move never hands its place over: its two spellings are one place.</summary>
    [Fact]
    public void ACaseOnlyMoveNeverHandsOver()
    {
        UndoOp caseOnly = FileMove(Section + "/day.md", Section + "/Day.md", "Three.\n");
        Assert.True(caseOnly.IsCaseOnlyMove);

        Assert.Empty(UndoOp.Handovers([caseOnly, NewFile(Section + "/day.md", "New.\n")]));
    }

    /// <summary>A <c>moveApart</c> or a <c>setAside</c>, read as a later version would, never hands its place over: only a plain <c>move</c> does.</summary>
    [Theory]
    [InlineData("moveApart")]
    [InlineData("setAside")]
    public void AMoveApartOrASetAsideNeverHandsOver(string kind)
    {
        var apart = new UndoOp { Kind = kind, Readable = true, From = Day(3), To = Day(4), Sha = UndoCheck.Sha(Bytes("Three.\n")) };

        Assert.Empty(UndoOp.Handovers([apart, NewFile(Day(3), "New.\n")]));
        Assert.Empty(UndoOp.Handovers([Removal(Day(4), "Three.\n"), apart with { From = Day(5) }]));
    }

    // ---- Going forward: the plan and the swap --------------------------------

    private List<UndoSwapTarget> ReadyTargets(UndoCheck.PlanResult plan)
    {
        var ready = Assert.IsType<UndoCheck.PlanResult.Ready>(plan);
        return UndoDoor.TargetsOf(ready, _root);
    }

    private List<UndoOp> CheckShapeA(bool leadingOut)
    {
        LayLink(Day(3), "Day 3.md", leadingOut);
        List<UndoOp> ops = [LinkMove(Day(3), Day(4)), NewFile(Day(3), "New.\n")];
        string linkTarget = new FileInfo(Full(Day(3))).LinkTarget!;

        UndoCheck.PlanResult plan = PlanForward(ops);
        Assert.True(plan is UndoCheck.PlanResult.Ready, "shape A was planned " + Described(plan));
        List<UndoSwapTarget> targets = ReadyTargets(plan);
        // The leaver before its filler: the link's move, then the new page.
        Assert.Equal([Day(4), Day(3)], PlacesOf(targets));

        UndoSwapResult result = UndoSwap.Swap(targets, "1-apply", _root);

        Assert.True(result is UndoSwapResult.Swapped, "shape A was swapped " + Described(result));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(Day(4))));
        Assert.Equal(linkTarget, new FileInfo(Full(Day(4))).LinkTarget);
        Assert.Equal(UndoLinks.What.File, UndoLinks.Look(Full(Day(3))));
        Assert.Equal("New.\n", File.ReadAllText(Full(Day(3))));
        string linkedPage = leadingOut ? Path.Combine(_outside, "Day 3.md") : Full(Library + "/Day 3.md");
        Assert.Equal("Linked.\n", File.ReadAllText(linkedPage));
        return ops;
    }

    private List<UndoOp> CheckShapeB(bool leadingOut)
    {
        LayLink(Day(2), "Day 2.md", leadingOut);
        WritePage(Day(3), "Three.\n");
        List<UndoOp> ops = [Removal(Day(3), "Three.\n"), LinkMove(Day(2), Day(3))];
        string linkTarget = new FileInfo(Full(Day(2))).LinkTarget!;

        UndoCheck.PlanResult plan = PlanForward(ops);
        Assert.True(plan is UndoCheck.PlanResult.Ready, "shape B was planned " + Described(plan));
        List<UndoSwapTarget> targets = ReadyTargets(plan);
        Assert.Equal([Day(3), Day(3)], PlacesOf(targets));
        Assert.Null(targets[0].Change);
        Assert.IsType<UndoSwapChange.MoveHere>(targets[1].Change);

        UndoSwapResult result = UndoSwap.Swap(targets, "1-apply", _root);

        Assert.True(result is UndoSwapResult.Swapped, "shape B was swapped " + Described(result));
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(Full(Day(2))));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(Day(3))));
        Assert.Equal(linkTarget, new FileInfo(Full(Day(3))).LinkTarget);
        return ops;
    }

    /// <summary>Shape A, the link leading to a library page in the course: the new page at Day 3 is judged against the place free, and goes in after the link has left.</summary>
    [SymbolicLinkFact]
    public void ShapeAAfterALinksMoveIsPlannedAsReadyAndSwapped() => CheckShapeA(leadingOut: false);

    /// <summary>Shape A, the link leading out of the working folder: the new page's place is judged on the folders above it, at the plan and before staging, and never refused for the link standing there.</summary>
    [SymbolicLinkFact]
    public void ShapeAWithTheLinkLeadingOutIsNeverRefusedAtThePlanOrAtStaging() => CheckShapeA(leadingOut: true);

    /// <summary>Shape B: a removal at Day 3, then the link's move from Day 2 into it, whose destination counts as free.</summary>
    [SymbolicLinkFact]
    public void ShapeBBeforeALinksMoveIsPlannedAsReadyAndSwapped() => CheckShapeB(leadingOut: false);

    /// <summary>Shape B with the link leading out of the working folder.</summary>
    [SymbolicLinkFact]
    public void ShapeBWithTheLinkLeadingOutIsPlannedAsReadyAndSwapped() => CheckShapeB(leadingOut: true);

    /// <summary>
    /// A step with no handed-over place keeps today's order exactly: every
    /// file in the order the check met it, then the whole ops, never the
    /// step's op order.
    /// </summary>
    [Fact]
    public void AStepWithNoHandoverKeepsTodaysOrder()
    {
        WritePage(Section + "/a.md", "A\n");
        WritePage(Section + "/b.md", "B\n");
        List<UndoOp> ops =
        [
            Op(new JsonObject { ["kind"] = "writeFile", ["path"] = Section + "/a.md", ["beforeSha"] = UndoCheck.Sha(Bytes("A\n")), ["afterSha"] = UndoCheck.Sha(Bytes("A2\n")) }),
            FileMove(Section + "/b.md", Section + "/e.md", "B\n"),
            NewFile(Section + "/c.md", "C\n"),
        ];
        Assert.Empty(UndoOp.Handovers(ops));

        List<UndoSwapTarget> targets = ReadyTargets(PlanForward(ops));

        Assert.Equal([Section + "/a.md", Section + "/c.md", Section + "/e.md"], PlacesOf(targets));
        Assert.False(targets[0].HandedOver);
        Assert.False(targets[1].HandedOver);
    }

    /// <summary>A file op in a handover where a link moves carries the mark the swap's look before staging reads; one in a handover of a file's move does not.</summary>
    [SymbolicLinkFact]
    public void OnlyAFileOpInAHandoverWithALinkIsJudgedOnTheFoldersAbove()
    {
        LayLink(Day(3), "Day 3.md", leadingOut: false);
        List<UndoSwapTarget> withALink = ReadyTargets(PlanForward([LinkMove(Day(3), Day(4)), NewFile(Day(3), "New.\n")]));
        Assert.True(withALink[1].HandedOver);

        WritePage(Day(7), "Three.\n");
        List<UndoSwapTarget> withAFile = ReadyTargets(PlanForward([FileMove(Day(7), Day(8), "Three.\n"), NewFile(Day(7), "New.\n")]));
        Assert.Equal([Day(8), Day(7)], PlacesOf(withAFile));
        Assert.False(withAFile[1].HandedOver);
    }

    // ---- Going back: the leaver judged with the place free (W8b-21a2) --------

    /// <summary>
    /// Shape A made forward, then taken back from its after state: the new
    /// page at Day 3 is taken back first, and the link's move back to Day 3
    /// is judged with Day 3 FREE, though the new page stands there when the
    /// plan is made. The new page goes before the link comes back.
    /// </summary>
    private void CheckShapeATakenBack(bool leadingOut)
    {
        List<UndoOp> ops = CheckShapeA(leadingOut);
        string linkTarget = new FileInfo(Full(Day(4))).LinkTarget!;

        UndoCheck.PlanResult plan = PlanBackward(ops);
        Assert.True(plan is UndoCheck.PlanResult.Ready, "shape A going back was planned " + Described(plan));
        List<UndoSwapTarget> targets = ReadyTargets(plan);
        // The filler's taking-back before its leaver's: the new page, then the link.
        Assert.Equal(2, targets.Count);
        Assert.Equal(Day(3), targets[0].RelativePath);
        Assert.Null(targets[0].Change);
        Assert.IsType<UndoSwapChange.MoveHere>(targets[1].Change);

        UndoSwapResult result = UndoSwap.Swap(targets, "1-undo", _root);

        Assert.True(result is UndoSwapResult.Swapped, "shape A going back was swapped " + Described(result));
        Assert.Equal(UndoLinks.What.Nothing, UndoLinks.Look(Full(Day(4))));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(Day(3))));
        Assert.Equal(linkTarget, new FileInfo(Full(Day(3))).LinkTarget);
        string linkedPage = leadingOut ? Path.Combine(_outside, "Day 3.md") : Full(Library + "/Day 3.md");
        Assert.Equal("Linked.\n", File.ReadAllText(linkedPage));
    }

    /// <summary>
    /// Shape B made forward, then taken back from its after state: the link's
    /// move back to Day 2 first, then the removal at Day 3 taken back, judged
    /// from "absent" and never by reading Day 3, where the link still stands
    /// when the plan is made.
    /// </summary>
    private void CheckShapeBTakenBack(bool leadingOut)
    {
        List<UndoOp> ops = CheckShapeB(leadingOut);
        string linkTarget = new FileInfo(Full(Day(3))).LinkTarget!;
        var readAt = new List<string>();

        UndoCheck.PlanResult plan = PlanBackward(ops, readAt);
        Assert.True(plan is UndoCheck.PlanResult.Ready, "shape B going back was planned " + Described(plan));
        Assert.DoesNotContain(Day(3), readAt);
        List<UndoSwapTarget> targets = ReadyTargets(plan);
        // In the step's ops reversed: the link's move back, then Day 3's page.
        Assert.Equal(2, targets.Count);
        Assert.IsType<UndoSwapChange.MoveHere>(targets[0].Change);
        Assert.Equal(Day(3), targets[1].RelativePath);
        Assert.Null(targets[1].Change);
        Assert.True(targets[1].HandedOver);

        UndoSwapResult result = UndoSwap.Swap(targets, "1-undo", _root);

        Assert.True(result is UndoSwapResult.Swapped, "shape B going back was swapped " + Described(result));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(Day(2))));
        Assert.Equal(linkTarget, new FileInfo(Full(Day(2))).LinkTarget);
        Assert.Equal(UndoLinks.What.File, UndoLinks.Look(Full(Day(3))));
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(3))));
    }

    /// <summary>Shape A taken back, the link leading to a library page in the course.</summary>
    [SymbolicLinkFact]
    public void ShapeATakenBackJudgesTheLinksOriginFree() => CheckShapeATakenBack(leadingOut: false);

    /// <summary>Shape A taken back, the link leading out of the working folder.</summary>
    [SymbolicLinkFact]
    public void ShapeAWithTheLinkLeadingOutTakenBackJudgesTheLinksOriginFree() => CheckShapeATakenBack(leadingOut: true);

    /// <summary>Shape B taken back, the link leading to a library page in the course.</summary>
    [SymbolicLinkFact]
    public void ShapeBTakenBackStartsTheRemovalFromAbsent() => CheckShapeBTakenBack(leadingOut: false);

    /// <summary>Shape B taken back, the link leading out of the working folder: Day 3 is never read through it.</summary>
    [SymbolicLinkFact]
    public void ShapeBWithTheLinkLeadingOutTakenBackStartsTheRemovalFromAbsent() => CheckShapeBTakenBack(leadingOut: true);

    /// <summary>
    /// A removal at Day 3, then a file's move from Day 2 into it, with the
    /// move already back (Day 2 holds its page, Day 3 is free): the filler is
    /// skipped as already back, so the removal's taking-back is judged from
    /// the disk at Day 3, as today, and puts the page back.
    /// </summary>
    [Fact]
    public void ALeaverWhoseFillerIsAlreadyBackIsJudgedFromTheDisk()
    {
        WritePage(Day(2), "Two.\n");
        List<UndoOp> ops = [Removal(Day(3), "Three.\n"), FileMove(Day(2), Day(3), "Two.\n")];
        Assert.Single(UndoOp.Handovers(ops));
        var readAt = new List<string>();

        UndoCheck.PlanResult plan = PlanBackward(ops, readAt);

        Assert.True(plan is UndoCheck.PlanResult.Ready, "the step was planned " + Described(plan));
        Assert.Contains(Day(3), readAt);
        List<UndoSwapTarget> targets = ReadyTargets(plan);
        UndoSwapTarget target = Assert.Single(targets);
        Assert.Equal(Day(3), target.RelativePath);
        Assert.Equal("Three.\n", Encoding.UTF8.GetString(target.Replacement!));
    }

    /// <summary>
    /// A file's move from Day 3 to Day 4, then a new page at Day 3, with the
    /// new page edited by hand since: going back the new page is in the way,
    /// so the plan is refused naming Day 3 (the move's origin counts as free
    /// only for the plan's own taking-back of the filler, never to let one
    /// through).
    /// </summary>
    [Fact]
    public void GoingBackOverAnEditedNewPageIsRefusedNamingIt()
    {
        WritePage(Day(4), "Three.\n");
        WritePage(Day(3), "New, edited by hand.\n");
        List<UndoOp> ops = [FileMove(Day(3), Day(4), "Three.\n"), NewFile(Day(3), "New.\n")];

        UndoCheck.PlanResult plan = PlanBackward(ops);

        Assert.Equal("changedSince " + Day(3), Described(plan));
    }

    /// <summary>
    /// A file's move from Day 3 to Day 4, then a new page at Day 3, taken
    /// back with no link: ready, the new page taken away before the move
    /// comes back (the step's ops reversed).
    /// </summary>
    [Fact]
    public void AFilesMoveTakenBackAfterItsFillerIsReadyInTheStepsOrderReversed()
    {
        WritePage(Day(4), "Three.\n");
        WritePage(Day(3), "New.\n");
        List<UndoOp> ops = [FileMove(Day(3), Day(4), "Three.\n"), NewFile(Day(3), "New.\n")];

        UndoCheck.PlanResult plan = PlanBackward(ops);
        Assert.True(plan is UndoCheck.PlanResult.Ready, "the step was planned " + Described(plan));
        List<UndoSwapTarget> targets = ReadyTargets(plan);

        Assert.Equal(2, targets.Count);
        Assert.Null(targets[0].Change);
        Assert.IsType<UndoSwapChange.MoveHere>(targets[1].Change);
        Assert.True(UndoSwap.Swap(targets, "1-undo", _root) is UndoSwapResult.Swapped);
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(3))));
        Assert.False(File.Exists(Full(Day(4))));
    }

    /// <summary>
    /// A removal at Day 3, then a file's move from Day 2 into it, taken back
    /// with no link: the move goes back before the removal is taken back,
    /// which is the step's ops reversed and NOT today's backward order (files,
    /// then whole ops).
    /// </summary>
    [Fact]
    public void AHandoverStepGoesBackInTheStepsOrderReversed()
    {
        WritePage(Day(3), "Two.\n");
        List<UndoOp> ops = [Removal(Day(3), "Three.\n"), FileMove(Day(2), Day(3), "Two.\n")];

        UndoCheck.PlanResult plan = PlanBackward(ops);
        Assert.True(plan is UndoCheck.PlanResult.Ready, "the step was planned " + Described(plan));
        List<UndoSwapTarget> targets = ReadyTargets(plan);

        Assert.Equal(2, targets.Count);
        Assert.IsType<UndoSwapChange.MoveHere>(targets[0].Change);
        Assert.Null(targets[1].Change);
        Assert.Equal(Day(3), targets[1].RelativePath);
        Assert.True(UndoSwap.Swap(targets, "1-undo", _root) is UndoSwapResult.Swapped);
        Assert.Equal("Two.\n", File.ReadAllText(Full(Day(2))));
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(3))));
    }

    /// <summary>A step with no handed-over place keeps today's backward order: every file the check met, then the whole ops.</summary>
    [Fact]
    public void AStepWithNoHandoverGoesBackInTodaysOrder()
    {
        WritePage(Section + "/a.md", "A2\n");
        WritePage(Section + "/e.md", "B\n");
        List<UndoOp> ops =
        [
            Op(new JsonObject { ["kind"] = "writeFile", ["path"] = Section + "/a.md", ["beforeSha"] = UndoCheck.Sha(Bytes("A\n")), ["afterSha"] = UndoCheck.Sha(Bytes("A2\n")) }),
            FileMove(Section + "/b.md", Section + "/e.md", "B\n"),
        ];
        Assert.Empty(UndoOp.Handovers(ops));

        List<UndoSwapTarget> targets = ReadyTargets(PlanBackward(ops));

        Assert.Equal(2, targets.Count);
        Assert.Equal(Section + "/a.md", targets[0].RelativePath);
        Assert.Null(targets[0].Change);
        Assert.IsType<UndoSwapChange.MoveHere>(targets[1].Change);
    }

    // ---- Recovery judges each op of a pair (W8b-21a3, the mac's door-3) -----

    private static string MoveNamed(string from, string to) => from + " → " + to;

    private static UndoStep StepOf(IReadOnlyList<UndoOp> ops) => new() { Seq = 1, Readable = true, Ops = ops };

    private static byte[]? BlobOf(string sha)
    {
        foreach (string text in new[] { "New.\n", "Three.\n", "Two.\n" })
        {
            if (UndoCheck.Sha(Bytes(text)) == sha) return Bytes(text);
        }
        return null;
    }

    /// <summary>What recovery judges each place of the step to be, as "place=State", in its order.</summary>
    private List<string> Judged(IReadOnlyList<UndoOp> ops)
    {
        var judged = new List<string>();
        foreach ((string path, UndoOpState state) in UndoRecovery.FileStates(StepOf(ops), _root, new UndoMemoryPlaces(), BlobOf))
            judged.Add(path + "=" + state);
        return judged;
    }

    private void RemoveAt(string relative) => File.Delete(Full(relative));

    /// <summary>
    /// A link at <paramref name="place"/> to a library page, its target held
    /// as the mac writes it (<c>../library/…</c>, which is what a link move's
    /// <c>linkSha</c> was taken of), or, <paramref name="spelledForWindows"/>,
    /// with Windows' own separator, so the page it leads to can be read
    /// through it (a mac-style target is not followed on NTFS: 21a1's note).
    /// </summary>
    private void LinkAt(string place, string libraryPage, bool spelledForWindows = false)
    {
        if (!File.Exists(Full(Library + "/" + libraryPage))) WritePage(Library + "/" + libraryPage, "Linked elsewhere.\n");
        string target = spelledForWindows ? Path.Combine("..", "library", libraryPage) : "../library/" + libraryPage;
        File.CreateSymbolicLink(Full(place), target);
    }

    /// <summary>
    /// Shape A, a link's move from Day 3 (P) to Day 4 (Q), then a new page at
    /// Day 3, judged by recovery at each point of the step. The move is named
    /// by its two places, never by Day 3 alone, which is the new page's place.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("link at P, Q free", "Before", "Before")]
    [InlineData("P free, link at Q", "After", "Before")]
    [InlineData("new at P, link at Q", "After", "After")]
    [InlineData("something else at P", "Neither", "Neither")]
    public void RecoveryJudgesShapeAAtEachPoint(string disk, string move, string newPage)
    {
        LayLink(Day(3), "Day 3.md", leadingOut: false);
        List<UndoOp> ops = [LinkMove(Day(3), Day(4)), NewFile(Day(3), "New.\n")];
        if (disk != "link at P, Q free")
        {
            RemoveAt(Day(3));
            LinkAt(Day(4), "Day 3.md");
        }
        if (disk == "new at P, link at Q") WritePage(Day(3), "New.\n");
        if (disk == "something else at P") WritePage(Day(3), "Another page.\n");

        Assert.Equal([MoveNamed(Day(3), Day(4)) + "=" + move, Day(3) + "=" + newPage], Judged(ops));
    }

    /// <summary>
    /// Shape B, a removal at Day 3 (P), then a link's move from Day 2 into
    /// it, judged by recovery at each point of the step.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("old page at P, link at Day 2", "Before", "Before")]
    [InlineData("P free", "After", "Before")]
    [InlineData("link at P, Day 2 free", "After", "After")]
    [InlineData("a link with another target at P", "Neither", "Neither")]
    public void RecoveryJudgesShapeBAtEachPoint(string disk, string removal, string move)
    {
        LayLink(Day(2), "Day 2.md", leadingOut: false);
        WritePage(Day(3), "Three.\n");
        List<UndoOp> ops = [Removal(Day(3), "Three.\n"), LinkMove(Day(2), Day(3))];
        if (disk != "old page at P, link at Day 2") RemoveAt(Day(3));
        if (disk == "link at P, Day 2 free" || disk == "a link with another target at P") RemoveAt(Day(2));
        if (disk == "link at P, Day 2 free") LinkAt(Day(3), "Day 2.md");
        if (disk == "a link with another target at P") LinkAt(Day(3), "Another day.md", spelledForWindows: true);

        Assert.Equal([Day(3) + "=" + removal, MoveNamed(Day(2), Day(3)) + "=" + move], Judged(ops));
    }

    /// <summary>
    /// A file's move from Day 3 to Day 4, then a new page at Day 3, both made:
    /// recovery judges the move as "Day 3 → Day 4" and the new page as Day 3,
    /// each after, and puts back the ops by that same name, each alone.
    /// </summary>
    [Fact]
    public void AMoveThatHandsAPlaceOverIsNamedByItsTwoPlacesAndPutBackByThatName()
    {
        WritePage(Day(4), "Three.\n");
        WritePage(Day(3), "New.\n");
        List<UndoOp> ops = [FileMove(Day(3), Day(4), "Three.\n"), NewFile(Day(3), "New.\n")];

        Assert.Equal([MoveNamed(Day(3), Day(4)) + "=After", Day(3) + "=After"], Judged(ops));
        Assert.Equal([ops[0]], UndoRecovery.OpsToPutBack(StepOf(ops), [MoveNamed(Day(3), Day(4))]));
        Assert.Equal([ops[1]], UndoRecovery.OpsToPutBack(StepOf(ops), [Day(3)]));
    }

    /// <summary>
    /// Shape A before the step, a kept original holding the new page: the
    /// page's op is planned together with the link's move, in the step's
    /// order, so the list gives the new page and the kept original is no
    /// only copy (planned alone, the page is judged against the link still
    /// there and never ready). One holding anything else stays an only copy.
    /// </summary>
    [SymbolicLinkFact]
    public void AKeptOriginalIsTestedAsAnOnlyCopyWithThePagesOpPlannedWithItsPair()
    {
        LayLink(Day(3), "Day 3.md", leadingOut: false);
        List<UndoOp> ops = [LinkMove(Day(3), Day(4)), NewFile(Day(3), "New.\n")];
        WritePage(Section + "/kept new page", "New.\n");
        WritePage(Section + "/kept other page", "Another page.\n");
        Func<string, string, bool> listHolds = UndoRecovery.ListHolds(StepOf(ops), _root, BlobOf);

        Assert.True(listHolds(Full(Section + "/kept new page"), Full(Day(3))));
        Assert.False(listHolds(Full(Section + "/kept other page"), Full(Day(3))));
    }

    /// <summary>
    /// The judging of a pair, with a judge that counts its calls and stops a
    /// judging that never ends: the link's move is judged again once, with
    /// its origin free, when the new page stands after; never a third time.
    /// </summary>
    [Fact]
    public void EachOpOfAPairIsJudgedAgainAtMostOnce()
    {
        List<UndoOp> ops = [LinkMoveInMemory(Day(3), Day(4)), NewFile(Day(3), "New.\n")];
        int[] calls = new int[ops.Count];
        int total = 0;

        UndoOpState?[] judged = UndoRecovery.JudgedTogether(ops, UndoOp.Handovers(ops), (index, sides) =>
        {
            total++;
            if (total > 100) throw new InvalidOperationException("the judging of the pair does not stop");
            calls[index]++;
            if (index == 1) return UndoOpState.After;
            return sides.FromIsFree ? UndoOpState.After : UndoOpState.Neither;
        });

        Assert.Equal(new UndoOpState?[] { UndoOpState.After, UndoOpState.After }, judged);
        Assert.Equal(new[] { 2, 1 }, calls);
    }

    /// <summary>
    /// A chain: a removal at Day 3, a file's move from Day 2 into it, then a
    /// new page at Day 2. The new page after frees the move's origin; the move
    /// after then frees the removal's page, which only a second round sees.
    /// </summary>
    [Fact]
    public void AChainOfPlacesIsJudgedAgainUntilNothingChanges()
    {
        List<UndoOp> ops = [Removal(Day(3), "Three.\n"), FileMove(Day(2), Day(3), "Two.\n"), NewFile(Day(2), "New.\n")];
        Assert.Equal(2, UndoOp.Handovers(ops).Count);
        int[] calls = new int[ops.Count];
        int total = 0;

        UndoOpState?[] judged = UndoRecovery.JudgedTogether(ops, UndoOp.Handovers(ops), (index, sides) =>
        {
            total++;
            if (total > 100) throw new InvalidOperationException("the judging of the chain does not stop");
            calls[index]++;
            return index switch
            {
                2 => UndoOpState.After,
                1 => sides.FromIsFree ? UndoOpState.After : UndoOpState.Neither,
                _ => sides.IsAbsent ? UndoOpState.After : UndoOpState.Neither,
            };
        });

        Assert.Equal(new UndoOpState?[] { UndoOpState.After, UndoOpState.After, UndoOpState.After }, judged);
        Assert.Equal(new[] { 2, 2, 1 }, calls);
    }
}
