using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>undo.checkCases</c>: "has what this
/// step changed been changed by hand since?", every case, asked of a real file
/// on the disk (#899 piece W1). Each case's page is written to a temporary
/// folder of its own exactly as the case gives it (<c>bytesHex</c> raw,
/// <c>text</c> as UTF-8, a folder, or nothing) and read back through
/// <see cref="UndoCurrent.Read"/>, so the check is proved against what a reader
/// of the disk sees, byte-order marks and carriage returns included.
///
/// <para>Then the Windows cases the contract does not have yet, each marked
/// PROPOSED: a page that cannot be read at the moment is never "changed since"
/// (the plan review's M2 and M3; the proposed authored cases are in the mac
/// draft for the director to open).</para>
/// </summary>
public sealed class UndoCheckContractTests : IDisposable
{
    private readonly string _folder = RunOwnedTempFolders.Create("plantoir-undo-check-");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    public static IEnumerable<object[]> Cases() =>
        UndoContract.Undo.GetProperty("checkCases").EnumerateArray()
            .Select(checkCase => new object[] { checkCase.GetProperty("name").GetString()! });

    [Fact]
    public void TheContractHoldsTheCheckCases()
    {
        // 30 when W1 was written; fewer is a contract change to read.
        Assert.True(UndoContract.Undo.GetProperty("checkCases").GetArrayLength() >= 30);
        Assert.Equal(UndoContract.Undo.GetProperty("checkCases").GetArrayLength(), Cases().Count());
    }

    private static JsonElement CaseNamed(string name) =>
        UndoContract.Undo.GetProperty("checkCases").EnumerateArray().Single(c => c.GetProperty("name").GetString() == name);

    /// <summary>The case's op as the journal would hold it: writeFile's texts become the SHA-256s they hash to.</summary>
    internal static UndoOp OpOf(JsonElement checkCase)
    {
        var op = JsonNode.Parse(checkCase.GetProperty("op").GetRawText())!.AsObject();
        if (op["kind"]?.GetValue<string>() == "writeFile")
        {
            foreach ((string text, string sha) in new[] { ("beforeText", "beforeSha"), ("afterText", "afterSha") })
            {
                JsonNode? value = op[text];
                op.Remove(text);
                if (value is not null) op[sha] = UndoCheck.Sha(Encoding.UTF8.GetBytes(value.GetValue<string>()));
            }
        }
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    /// <summary>
    /// The case's <c>current</c> as this test can place it: one place
    /// holding text, bytes, an empty folder or nothing. A move's two sides
    /// (<c>atFrom</c>, <c>atTo</c>), a <c>tree</c> and an external op's
    /// <c>preference</c> are U2's shapes, placed once W6 reads their kinds.
    /// </summary>
    private static bool CanBePlacedHere(JsonElement checkCase)
    {
        JsonElement current = checkCase.GetProperty("current");
        foreach (string shape in new[] { "text", "bytesHex", "folder", "absent" })
        {
            if (current.TryGetProperty(shape, out _)) return true;
        }
        return false;
    }

    /// <summary>Puts the case's <c>current</c> on the disk at the op's path and returns the full path.</summary>
    private string Place(JsonElement checkCase)
    {
        string path = Path.Combine(_folder, Guid.NewGuid().ToString("N"), "page.md");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        JsonElement current = checkCase.GetProperty("current");
        if (current.TryGetProperty("text", out JsonElement text)) File.WriteAllBytes(path, Encoding.UTF8.GetBytes(text.GetString()!));
        else if (current.TryGetProperty("bytesHex", out JsonElement hex)) File.WriteAllBytes(path, Convert.FromHexString(hex.GetString()!));
        else if (current.TryGetProperty("folder", out _)) Directory.CreateDirectory(path);
        else Assert.True(current.GetProperty("absent").GetBoolean());
        return path;
    }

    /// <summary>
    /// What a reader of the disk sees at the case's place. <c>cannotBeRead</c>
    /// (on the mac and in Python, the permissions taken away) is the open
    /// refused with access denied, as <c>FileStream</c> throws it
    /// (<see cref="UnauthorizedAccessException"/>, 0x80070005), through
    /// <see cref="UndoCurrent.Read"/>'s seam, so every case runs under any
    /// token. A real ACL that denies reading is
    /// <see cref="APageWhoseReadingIsDeniedCannotTellAndIsRefusedCannotTellNow"/>,
    /// skipped where an administrator's token over SSH reads past it (the W5
    /// review's note).
    /// </summary>
    private static UndoCurrent ReadAsTheCaseHasIt(JsonElement checkCase, string path)
    {
        bool cannotBeRead = checkCase.GetProperty("current").TryGetProperty("cannotBeRead", out JsonElement flag) && flag.GetBoolean();
        if (!cannotBeRead) return UndoCurrent.Read(path);
        Assert.True(File.Exists(path), "a place that cannot be read is one that is there");
        return UndoCurrent.Read(path, _ => throw new UnauthorizedAccessException("denied, as the case has it") { HResult = unchecked((int)0x80070005) });
    }

    /// <summary>Every case held open by name (an op of U2's kinds, which W6 brings) is a case the contract still has.</summary>
    [Fact]
    public void EveryHeldCheckCaseIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoCheckCases, Cases().Select(row => (string)row[0]));

    /// <summary>
    /// Every case, its undo and redo verdicts exactly as the contract gives
    /// them. A case the ledger holds open (its op is one of U2's kinds, which
    /// this reader does not know until W6) must still be answered
    /// <c>notReadable</c> both ways, the contract's rule for a kind a reader
    /// does not know (never guessed at, never a reason to clear), and must
    /// still differ from the contract; it goes from the ledger the day it is
    /// answered as the contract says.
    /// </summary>
    [Theory]
    [MemberData(nameof(Cases))]
    public void EveryCheckCase(string name) =>
        JudgeAsTheLedgerSays(name, NamedGapLedger.All, OpOf, JudgeOnTheDisk);

    /// <summary>
    /// One case, judged by <paramref name="judge"/> on the op
    /// <paramref name="readOp"/> reads, and held or not as
    /// <paramref name="entries"/> say. <see cref="EveryCheckCase"/> passes this
    /// app's reader and the disk; <c>TheDayAHeldCheckCaseIsAnsweredAsTheContractSaysItFails</c>
    /// passes W6's answers, to prove that a held case does not outlive its gap.
    /// </summary>
    internal static void JudgeAsTheLedgerSays(string name, IEnumerable<NamedGapLedger.Entry> entries,
                                              Func<JsonElement, UndoOp> readOp,
                                              Func<string, JsonElement, UndoOp, (string Undo, string Redo)> judge)
    {
        JsonElement checkCase = CaseNamed(name);
        UndoOp op = readOp(checkCase);
        NamedGapLedger.Entry? held = NamedGapLedger.Holding(NamedGapLedger.UndoCheckCases, name, entries);
        if (held is not null)
        {
            // The op of a held case must still be one this reader does not know.
            Assert.False(op.Readable, NamedGapLedger.ClosedMessage(held));
        }
        (string undo, string redo) = judge(name, checkCase, op);
        string expectedUndo = checkCase.GetProperty("undo").GetString()!;
        string expectedRedo = checkCase.GetProperty("redo").GetString()!;
        if (held is not null)
        {
            Assert.False(undo == expectedUndo && redo == expectedRedo, NamedGapLedger.ClosedMessage(held));
            Assert.True(undo == "notReadable" && redo == "notReadable",
                $"\"{name}\" is held open (#{held.Issue}) because its op's kind is not read here yet, so it must be " +
                $"answered notReadable both ways, never guessed at; it was answered {undo} and {redo}");
            return;
        }
        Assert.Equal(expectedUndo, undo);
        Assert.Equal(expectedRedo, redo);
    }

    /// <summary>
    /// The case's undo and redo verdicts, its <c>current</c> on the disk and
    /// read back. A <c>current</c> this test cannot place yet (a move's
    /// <c>atFrom</c>/<c>atTo</c>, a <c>tree</c>, a <c>preference</c>: U2's
    /// shapes, which W6 places) is judged on a placeholder, and only for an op
    /// this reader cannot read: such an op is settled before anything at its
    /// path is read (<see cref="UndoCheck.StateOf"/>), which two placeholders
    /// that a readable op would tell apart (nothing there, a folder) must
    /// agree on. An op it CAN read with such a <c>current</c> fails here,
    /// naming the shape, until this test places it (the 2026-11-19 review's
    /// MEDIUM: a held case is never passed over for its shape).
    /// </summary>
    private (string Undo, string Redo) JudgeOnTheDisk(string name, JsonElement checkCase, UndoOp op)
    {
        if (CanBePlacedHere(checkCase))
        {
            UndoOpState state = UndoCheck.StateOf(op, ReadAsTheCaseHasIt(checkCase, Place(checkCase)));
            return (UndoContract.Spelled(UndoCheck.UndoVerdictOf(state)), UndoContract.Spelled(UndoCheck.RedoVerdictOf(state)));
        }
        Assert.False(op.Readable,
            $"\"{name}\" has a current of a shape this test does not place yet ({ShapesOf(checkCase)}), and its op is now " +
            "one this reader reads: place that shape in Place before the case can be judged");
        UndoOpState onNothing = UndoCheck.StateOf(op, new UndoCurrent.Absent());
        UndoOpState onAFolder = UndoCheck.StateOf(op, new UndoCurrent.Folder());
        Assert.Equal(onNothing, onAFolder);
        return (UndoContract.Spelled(UndoCheck.UndoVerdictOf(onNothing)), UndoContract.Spelled(UndoCheck.RedoVerdictOf(onNothing)));
    }

    private static string ShapesOf(JsonElement checkCase)
    {
        var shapes = new List<string>();
        foreach (JsonProperty shape in checkCase.GetProperty("current").EnumerateObject()) shapes.Add(shape.Name);
        return string.Join(", ", shapes);
    }

    /// <summary>
    /// Proves a held check case does not outlive its gap, on real held rows:
    /// one whose <c>current</c> this test places and one whose <c>current</c>
    /// it cannot place yet. Given W6's answers (the op read, the contract's
    /// verdicts), each fails as the gap closing; given the contract's verdicts
    /// with the op still unread, each fails the same way; answered anything
    /// but <c>notReadable</c> while held, each fails as a real failure.
    /// </summary>
    [Theory]
    [InlineData("replaceText: the hunk as the step left it")]
    [InlineData("move: back where it was, the other place free")]
    public void TheDayAHeldCheckCaseIsAnsweredAsTheContractSaysItFails(string name)
    {
        Assert.NotNull(NamedGapLedger.Holding(NamedGapLedger.UndoCheckCases, name));
        (string, string) TheContractsAnswer(string _, JsonElement checkCase, UndoOp __) =>
            (checkCase.GetProperty("undo").GetString()!, checkCase.GetProperty("redo").GetString()!);
        UndoOp ReadAsW6Will(JsonElement checkCase) => OpOf(checkCase) with { Readable = true };

        // As it stands today: held, and passing because it still fails for its gap.
        JudgeAsTheLedgerSays(name, NamedGapLedger.All, OpOf, JudgeOnTheDisk);

        var opRead = Assert.ThrowsAny<Exception>(() => JudgeAsTheLedgerSays(name, NamedGapLedger.All, ReadAsW6Will, TheContractsAnswer));
        Assert.Contains("now EXISTS on this side", opRead.Message);
        var answered = Assert.ThrowsAny<Exception>(() => JudgeAsTheLedgerSays(name, NamedGapLedger.All, OpOf, TheContractsAnswer));
        Assert.Contains("now EXISTS on this side", answered.Message);
        var guessed = Assert.ThrowsAny<Exception>(() => JudgeAsTheLedgerSays(name, NamedGapLedger.All, OpOf, (_, _, _) => ("fileIsInUse", "fileIsInUse")));
        Assert.Contains("never guessed at", guessed.Message);
    }

    /// <summary>
    /// Where a case says the step can be undone, undoing it through the plan
    /// gives a page the same op can REDO: the line model moves the entry back
    /// and forth without touching anything else (a body written since stays).
    /// </summary>
    [Theory]
    [MemberData(nameof(Cases))]
    public void WhatCanBeUndoneCanThenBeRedone(string name)
    {
        JsonElement checkCase = CaseNamed(name);
        if (checkCase.GetProperty("undo").GetString() != "canUndo") return;
        UndoOp op = OpOf(checkCase);
        if (op.Kind != UndoOp.EditLine) return;   // writeFile needs its blob, recompute has no check
        string path = Place(checkCase);
        byte[] before = File.ReadAllBytes(path);
        var plan = UndoCheck.Plan([op], backward: true, _ => UndoCurrent.Read(path), _ => null);
        var ready = Assert.IsType<UndoCheck.PlanResult.Ready>(plan);
        byte[] undone = Assert.Single(ready.Changes).Value!;
        Assert.Equal(UndoOpState.Before, UndoCheck.StateOf(op, new UndoCurrent.Bytes(undone)));
        var back = UndoCheck.Plan([op], backward: false, _ => new UndoCurrent.Bytes(undone), _ => null);
        Assert.Equal(before, Assert.Single(Assert.IsType<UndoCheck.PlanResult.Ready>(back).Changes).Value);
    }

    // ---- PROPOSED: Windows' read failures (D1, amended) --------------------------

    private static UndoOp ThePublishLineOp() => OpOf(CaseNamed("the line as the step left it"));

    private string ThePageAsTheStepLeftIt()
    {
        string path = Place(CaseNamed("the line as the step left it"));
        Assert.Equal(UndoOpState.After, UndoCheck.StateOf(ThePublishLineOp(), UndoCurrent.Read(path)));
        return path;
    }

    /// <summary>
    /// PROPOSED (no contract case yet). A page another program holds with no
    /// read sharing at all cannot be read now. It is not "changed since": that
    /// would clear the whole list under ruling 13 for a file that was merely
    /// busy. It ends as the contract's fileIsInUse ends: refused, named, the
    /// list unchanged.
    /// </summary>
    [Fact]
    public void Proposed_APageHeldWithNoSharingCannotBeReadNowAndIsNeverChangedSince()
    {
        string path = ThePageAsTheStepLeftIt();
        UndoOp op = ThePublishLineOp();
        using (new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            UndoCurrent current = UndoCurrent.Read(path);
            var cannot = Assert.IsType<UndoCurrent.CannotReadNow>(current);
            Assert.Equal(32, cannot.ErrorCode);   // ERROR_SHARING_VIOLATION
            Assert.Equal(UndoVerdict.FileIsInUse, UndoCheck.UndoVerdictOf(UndoCheck.StateOf(op, current)));
            Assert.Equal(UndoVerdict.FileIsInUse, UndoCheck.RedoVerdictOf(UndoCheck.StateOf(op, current)));
            var plan = UndoCheck.Plan([op], backward: true, _ => UndoCurrent.Read(path), _ => null);
            Assert.Equal("page.md", Assert.IsType<UndoCheck.PlanResult.FileIsInUse>(plan).Path is { } named ? Path.GetFileName(named) : null);
        }
        Assert.Equal(UndoOpState.After, UndoCheck.StateOf(op, UndoCurrent.Read(path)));   // and readable again once let go
    }

    /// <summary>
    /// The plan review's M2, measured: a holder that shares reading and
    /// writing but not delete (Word, many editors) does NOT stop a read, so the
    /// check reads the page and answers by its content. Only a SWAP is refused
    /// under such a holder, and that is W2's (stepCases' fileIsInUse).
    /// </summary>
    [Fact]
    public void APageHeldWithReadWriteSharingIsStillReadAndJudgedByItsContent()
    {
        string path = ThePageAsTheStepLeftIt();
        using var holder = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite);
        Assert.IsType<UndoCurrent.Bytes>(UndoCurrent.Read(path));
        Assert.Equal(UndoOpState.After, UndoCheck.StateOf(ThePublishLineOp(), UndoCurrent.Read(path)));
    }

    /// <summary>
    /// PROPOSED. A cloud file that is not available offline, or a network
    /// share that dropped, fails the read with an I/O error of its own: also
    /// cannot-read-now, never changed since (a seam stands in for OneDrive,
    /// which this suite must not touch).
    ///
    /// <para>Since U2b's contract (checkCasesHow's <c>cannotTell</c>, the director's
    /// ruling confirmed by Russell, 2026-11-19), every such failure except a
    /// lock or sharing violation is <c>cannotTell</c>, refused
    /// <c>cannotTellNow</c>; a lock violation (another program holds a range of
    /// the file) stays "in use", which <c>rule.recovery</c> names apart.</para>
    /// </summary>
    [Theory]
    [InlineData(362, "cannotTell")]    // ERROR_CLOUD_FILE_PROVIDER_NOT_RUNNING
    [InlineData(395, "cannotTell")]    // ERROR_CLOUD_FILE_ACCESS_DENIED
    [InlineData(64, "cannotTell")]     // ERROR_NETNAME_DELETED
    [InlineData(33, "fileIsInUse")]    // ERROR_LOCK_VIOLATION
    public void Proposed_ACloudOrNetworkReadFailureIsNeverChangedSince(int error, string verdict)
    {
        string path = ThePageAsTheStepLeftIt();
        UndoCurrent current = UndoCurrent.Read(path, _ => throw new IOException("seam", unchecked((int)0x80070000) | error));
        Assert.Equal(error, Assert.IsType<UndoCurrent.CannotReadNow>(current).ErrorCode);
        Assert.Equal(verdict, UndoContract.Spelled(UndoCheck.UndoVerdictOf(UndoCheck.StateOf(ThePublishLineOp(), current))));
        Assert.Equal(verdict, UndoContract.Spelled(UndoCheck.RedoVerdictOf(UndoCheck.StateOf(ThePublishLineOp(), current))));
    }

    /// <summary>
    /// A step with a page that cannot be read now and nothing in the way is
    /// refused cannotTellNow, naming the page, and a page in the way still
    /// settles it first (the mac's order: changed since, cannot tell, content
    /// missing).
    /// </summary>
    [Fact]
    public void APageThatCannotBeReadNowIsRefusedCannotTellUnlessAPageIsInTheWay()
    {
        UndoOp first = ThePublishLineOp() with { Path = "a.md" };
        UndoOp second = ThePublishLineOp() with { Path = "b.md" };
        var refused = UndoCheck.Plan([first, second], backward: true,
            relative => relative == "a.md" ? new UndoCurrent.CannotReadNow(5) : UndoCurrent.Read(ThePageAsTheStepLeftIt()),
            _ => null);
        Assert.Equal("a.md", Assert.IsType<UndoCheck.PlanResult.CannotTellNow>(refused).Path);

        string changed = "---\ntitle: Unit 1, Day 1\npublish: true # by hand\n---\n";
        var inTheWay = UndoCheck.Plan([first, second], backward: true,
            relative => relative == "a.md" ? new UndoCurrent.CannotReadNow(5) : new UndoCurrent.Bytes(Encoding.UTF8.GetBytes(changed)),
            _ => null);
        Assert.Equal("b.md", Assert.IsType<UndoCheck.PlanResult.ChangedSince>(inTheWay).First);
    }

    /// <summary>
    /// The mac's order, its second step: a page that cannot be read now is
    /// named before content the list no longer holds, whichever op comes
    /// first (the 2026-11-19 review's low). A step refused for content missing
    /// clears the list; one refused cannotTellNow keeps it, so the order
    /// decides whether a busy page costs the teacher the whole list.
    /// </summary>
    [Fact]
    public void APageThatCannotBeReadNowIsNamedBeforeMissingContent()
    {
        UndoOp line = ThePublishLineOp() with { Path = "a.md" };
        UndoOp whole = new() { Kind = UndoOp.WriteFile, Readable = true, Path = "b.md", BeforeSha = new string('a', 64), AfterSha = UndoCheck.Sha("new\n"u8.ToArray()) };
        UndoCurrent Read(string relative) => relative == "a.md" ? new UndoCurrent.CannotReadNow(5) : new UndoCurrent.Bytes("new\n"u8.ToArray());

        foreach (UndoOp[] ops in new[] { new[] { line, whole }, new[] { whole, line } })
        {
            var plan = UndoCheck.Plan(ops, backward: true, Read, _ => null);
            Assert.Equal("a.md", Assert.IsType<UndoCheck.PlanResult.CannotTellNow>(plan).Path);
        }
        // and with the page readable again, the missing content is what refuses it.
        var readable = UndoCheck.Plan([line, whole], backward: true,
            relative => relative == "a.md" ? UndoCurrent.Read(ThePageAsTheStepLeftIt()) : new UndoCurrent.Bytes("new\n"u8.ToArray()),
            _ => null);
        Assert.Equal("b.md", Assert.IsType<UndoCheck.PlanResult.ContentMissing>(readable).Path);
    }

    /// <summary>
    /// The <c>cannotBeRead</c> rows through a real deny ACE on the page, not
    /// the seam: reading denied to this account reaches the mapping as
    /// access denied (5), <c>cannotTell</c> both ways, and the step is refused
    /// <c>cannotTellNow</c> naming the page. Skipped, saying why, where this
    /// account's token reads past a deny ACE (an administrator's over SSH);
    /// <see cref="EveryCheckCase"/> covers the rows through the seam there.
    /// </summary>
    [DenyReadBitesFact]
    public void APageWhoseReadingIsDeniedCannotTellAndIsRefusedCannotTellNow()
    {
        string path = ThePageAsTheStepLeftIt();
        UndoOp op = ThePublishLineOp();
        var file = new FileInfo(path);
        var rights = file.GetAccessControl();
        var deny = new FileSystemAccessRule(WindowsIdentity.GetCurrent().User!, FileSystemRights.ReadData, AccessControlType.Deny);
        rights.AddAccessRule(deny);
        file.SetAccessControl(rights);
        try
        {
            UndoCurrent current = UndoCurrent.Read(path);
            Assert.Equal(5, Assert.IsType<UndoCurrent.CannotReadNow>(current).ErrorCode);
            Assert.Equal("cannotTell", UndoContract.Spelled(UndoCheck.UndoVerdictOf(UndoCheck.StateOf(op, current))));
            Assert.Equal("cannotTell", UndoContract.Spelled(UndoCheck.RedoVerdictOf(UndoCheck.StateOf(op, current))));
            var plan = UndoCheck.Plan([op], backward: true, _ => UndoCurrent.Read(path), _ => null);
            Assert.Equal(op.Path, Assert.IsType<UndoCheck.PlanResult.CannotTellNow>(plan).Path);
        }
        finally
        {
            rights.RemoveAccessRule(deny);
            file.SetAccessControl(rights);
        }
        Assert.Equal(UndoOpState.After, UndoCheck.StateOf(op, UndoCurrent.Read(path)));   // and readable again once allowed
    }

    /// <summary>
    /// PROPOSED. A page changed by hand settles the question whatever else is
    /// busy: one page in the way is "changed since" (the list is cleared, ruling
    /// 13) even when another page of the same step cannot be read now.
    /// </summary>
    [Fact]
    public void Proposed_APageChangedByHandOutranksAPageThatCannotBeReadNow()
    {
        UndoOp first = ThePublishLineOp() with { Path = "a.md" };
        UndoOp second = ThePublishLineOp() with { Path = "b.md" };
        string changed = "---\ntitle: Unit 1, Day 1\npublish: true # by hand\n---\n";
        var plan = UndoCheck.Plan([first, second], backward: true,
            relative => relative == "a.md" ? new UndoCurrent.CannotReadNow(32) : new UndoCurrent.Bytes(Encoding.UTF8.GetBytes(changed)),
            _ => null);
        Assert.Equal("b.md", Assert.IsType<UndoCheck.PlanResult.ChangedSince>(plan).First);
    }

    /// <summary>The read-only bit does not stop a READ: the check judges such a page by its content (the swap is W2's to refuse).</summary>
    [Fact]
    public void AReadOnlyPageIsReadAndJudgedByItsContent()
    {
        string path = ThePageAsTheStepLeftIt();
        File.SetAttributes(path, FileAttributes.ReadOnly);
        try
        {
            Assert.Equal(UndoOpState.After, UndoCheck.StateOf(ThePublishLineOp(), UndoCurrent.Read(path)));
        }
        finally { File.SetAttributes(path, FileAttributes.Normal); }
    }

    /// <summary>A line op that cannot be placed is changed since, and a page in the way is named before content that is missing (U1's F2).</summary>
    [Fact]
    public void APageInTheWayIsNamedBeforeMissingContent()
    {
        UndoOp line = ThePublishLineOp() with { Path = "a.md" };
        string missingSha = new('a', 64);
        UndoOp whole = new() { Kind = UndoOp.WriteFile, Readable = true, Path = "b.md", BeforeSha = missingSha, AfterSha = UndoCheck.Sha("new\n"u8.ToArray()) };
        var plan = UndoCheck.Plan([line, whole], backward: true,
            relative => relative == "a.md"
                ? new UndoCurrent.Bytes(Encoding.UTF8.GetBytes("---\ntitle: X\npublish: true # by hand\n---\n"))
                : new UndoCurrent.Bytes("new\n"u8.ToArray()),
            _ => null);
        Assert.Equal("a.md", Assert.IsType<UndoCheck.PlanResult.ChangedSince>(plan).First);
    }

    /// <summary>
    /// The W1 review's M1. A page that is simply not there while its working
    /// folder cannot be reached (a drive or share that went away between the
    /// reach check and the plan) is not a change by hand: the plan says the
    /// folder cannot be reached (greyed, nothing cleared). While the folder can
    /// be reached, a page that is gone is changed since, as before.
    /// </summary>
    [Fact]
    public void APageThatIsGoneWhileItsFolderCannotBeReachedIsNotAChangeSince()
    {
        UndoOp op = ThePublishLineOp() with { Path = "a.md" };
        var gone = UndoCheck.Plan([op], backward: true, _ => new UndoCurrent.Absent(), _ => null, folderIsReachable: () => false);
        Assert.Equal("a.md", Assert.IsType<UndoCheck.PlanResult.FolderCannotBeReached>(gone).Path);

        var reachable = UndoCheck.Plan([op], backward: true, _ => new UndoCurrent.Absent(), _ => null, folderIsReachable: () => true);
        Assert.Equal("a.md", Assert.IsType<UndoCheck.PlanResult.ChangedSince>(reachable).First);

        // A page that IS there and was changed by hand settles it, reach or not.
        UndoOp second = ThePublishLineOp() with { Path = "b.md" };
        string changed = "---\ntitle: Unit 1, Day 1\npublish: true # by hand\n---\n";
        var handEdit = UndoCheck.Plan([op, second], backward: true,
            relative => relative == "a.md" ? new UndoCurrent.Absent() : new UndoCurrent.Bytes(Encoding.UTF8.GetBytes(changed)),
            _ => null, folderIsReachable: () => false);
        Assert.IsType<UndoCheck.PlanResult.ChangedSince>(handEdit);
    }
}

/// <summary>
/// A fact that needs a deny ACE to stop this account READING a file:
/// SKIPPED, saying why, when it does not (an administrator's token, as over
/// SSH, may read past it), so the totals line counts it as not run rather
/// than failed, the convention of <see cref="DenyBitesFactAttribute"/>. The
/// probe makes a temporary file, denies itself reading it, tries, and
/// removes both.
/// </summary>
public sealed class DenyReadBitesFactAttribute : FactAttribute
{
    private static readonly Lazy<bool> DenyBites = new(Probe);

    public DenyReadBitesFactAttribute()
    {
        if (!DenyBites.Value)
            Skip = "A deny ACE does not stop this account reading a file (an administrator's token, as over SSH), so "
                 + "'a page whose reading is denied cannot tell' cannot be tried on the disk here; "
                 + "EveryCheckCase covers the contract's cannotBeRead rows through UndoCurrent.Read's seam.";
    }

    private static bool Probe()
    {
        string folder = Directory.CreateTempSubdirectory("deny-read-probe-").FullName;
        string path = Path.Combine(folder, "probe.md");
        File.WriteAllText(path, "probe");
        var file = new FileInfo(path);
        var rights = file.GetAccessControl();
        var deny = new FileSystemAccessRule(WindowsIdentity.GetCurrent().User!, FileSystemRights.ReadData, AccessControlType.Deny);
        try
        {
            rights.AddAccessRule(deny);
            file.SetAccessControl(rights);
            try
            {
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                return false;
            }
            catch (UnauthorizedAccessException) { return true; }
            catch (IOException) { return true; }
        }
        catch { return false; }
        finally
        {
            try { rights.RemoveAccessRule(deny); file.SetAccessControl(rights); } catch { }
            try { Directory.Delete(folder, recursive: true); } catch { }
        }
    }
}
