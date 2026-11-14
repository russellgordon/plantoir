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

    [Theory]
    [MemberData(nameof(Cases))]
    public void EveryCheckCase(string name)
    {
        JsonElement checkCase = CaseNamed(name);
        UndoOp op = OpOf(checkCase);
        UndoCurrent current = UndoCurrent.Read(Place(checkCase));
        UndoOpState state = UndoCheck.StateOf(op, current);
        Assert.Equal(checkCase.GetProperty("undo").GetString(), UndoContract.Spelled(UndoCheck.UndoVerdictOf(state)));
        Assert.Equal(checkCase.GetProperty("redo").GetString(), UndoContract.Spelled(UndoCheck.RedoVerdictOf(state)));
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
    /// </summary>
    [Theory]
    [InlineData(362)]   // ERROR_CLOUD_FILE_PROVIDER_NOT_RUNNING
    [InlineData(395)]   // ERROR_CLOUD_FILE_ACCESS_DENIED
    [InlineData(64)]    // ERROR_NETNAME_DELETED
    [InlineData(33)]    // ERROR_LOCK_VIOLATION
    public void Proposed_ACloudOrNetworkReadFailureIsNeverChangedSince(int error)
    {
        string path = ThePageAsTheStepLeftIt();
        UndoCurrent current = UndoCurrent.Read(path, _ => throw new IOException("seam", unchecked((int)0x80070000) | error));
        Assert.Equal(error, Assert.IsType<UndoCurrent.CannotReadNow>(current).ErrorCode);
        Assert.Equal(UndoVerdict.FileIsInUse, UndoCheck.UndoVerdictOf(UndoCheck.StateOf(ThePublishLineOp(), current)));
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
}
