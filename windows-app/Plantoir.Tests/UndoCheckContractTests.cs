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

    /// <summary>
    /// The case's op as the journal would hold it (<c>checkCasesHow</c>):
    /// writeFile's texts become the SHA-256s they hash to, a move's
    /// <c>contentText</c> its <c>sha</c>, a folder's <c>listing</c> its
    /// <c>listingSha</c> (and, for a tree, its blobs: the listing's hash and
    /// every file's). A JSON null is a value for editJSON and external and
    /// absent for every other kind.
    /// </summary>
    internal static UndoOp OpOf(JsonElement checkCase)
    {
        var op = JsonNode.Parse(checkCase.GetProperty("op").GetRawText())!.AsObject();
        string? kind = op["kind"] is JsonValue kindValue && kindValue.TryGetValue(out string? named) ? named : null;
        if (kind == "writeFile")
        {
            var names = new JsonArray();
            foreach ((string text, string sha) in new[] { ("beforeText", "beforeSha"), ("afterText", "afterSha") })
            {
                JsonNode? value = op[text];
                op.Remove(text);
                if (value is null) continue;
                string hash = UndoCheck.Sha(Encoding.UTF8.GetBytes(value.GetValue<string>()));
                op[sha] = hash;
                names.Add(hash);
            }
            op["blobs"] = names;
        }
        if (op["contentText"] is { } content)
        {
            op.Remove("contentText");
            op["sha"] = UndoCheck.Sha(Encoding.UTF8.GetBytes(content.GetValue<string>()));
        }
        if (op["listing"] is JsonObject tree)
        {
            op.Remove("listing");
            UndoTreeListing listing = ListingOf(tree);
            op["listingSha"] = listing.Sha;
            if (kind is "createTree" or "removeTree")
            {
                var names = new JsonArray(listing.Sha);
                foreach ((_, string sha) in listing.Files)
                {
                    if (!names.Any(name => name!.GetValue<string>() == sha)) names.Add(sha);
                }
                op["blobs"] = names;
            }
        }
        if (kind is not ("editJSON" or "external"))
        {
            foreach (string key in op.Where(pair => pair.Value is null).Select(pair => pair.Key).ToList()) op.Remove(key);
        }
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    /// <summary>A case's <c>listing</c> (or <c>tree</c>) as the listing this version makes: <c>.DS_Store</c> passed over at any depth.</summary>
    internal static UndoTreeListing ListingOf(JsonNode tree)
    {
        var files = new List<(string, string)>();
        if (tree["files"] is JsonObject named)
        {
            foreach ((string path, JsonNode? text) in named)
            {
                if (Path.GetFileName(path) == UndoTreeListing.IgnoredName) continue;
                files.Add((path, UndoCheck.Sha(Encoding.UTF8.GetBytes(text!.GetValue<string>()))));
            }
        }
        var folders = new List<string>();
        if (tree["folders"] is JsonArray list)
        {
            foreach (JsonNode? folder in list) folders.Add(folder!.GetValue<string>());
        }
        return new UndoTreeListing(folders, files);
    }

    /// <summary>
    /// Puts what a case's <c>current</c> (or one side of a move's) describes
    /// at a full path: text, raw bytes, an empty folder, a tree (with any
    /// links inside), a link, or nothing. Returns whether the place is to be
    /// read as one that cannot be read just now (<c>cannotBeRead</c>).
    /// </summary>
    private bool PlaceAt(JsonElement current, string full)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        if (current.TryGetProperty("text", out JsonElement text)) File.WriteAllBytes(full, Encoding.UTF8.GetBytes(text.GetString()!));
        else if (current.TryGetProperty("bytesHex", out JsonElement hex)) File.WriteAllBytes(full, Convert.FromHexString(hex.GetString()!));
        else if (current.TryGetProperty("folder", out _)) Directory.CreateDirectory(full);
        else if (current.TryGetProperty("link", out _)) UndoKindsForTheCases.MakeALink(full, _folder);
        else if (current.TryGetProperty("tree", out JsonElement tree))
        {
            Directory.CreateDirectory(full);
            foreach (JsonElement folder in tree.GetProperty("folders").EnumerateArray())
                Directory.CreateDirectory(UndoTreeReading.Under(full, folder.GetString()!));
            foreach (JsonProperty file in tree.GetProperty("files").EnumerateObject())
            {
                string path = UndoTreeReading.Under(full, file.Name);
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllBytes(path, Encoding.UTF8.GetBytes(file.Value.GetString()!));
            }
            if (tree.TryGetProperty("links", out JsonElement links))
            {
                foreach (JsonProperty link in links.EnumerateObject()) UndoKindsForTheCases.MakeALink(UndoTreeReading.Under(full, link.Name), _folder);
            }
        }
        return current.TryGetProperty("cannotBeRead", out JsonElement flag) && flag.GetBoolean();
    }

    /// <summary>Every case held open by name is a case the contract still has (none since W6).</summary>
    [Fact]
    public void EveryHeldCheckCaseIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoCheckCases, Cases().Select(row => (string)row[0]));

    /// <summary>
    /// Every case, its undo and redo verdicts exactly as the contract gives
    /// them, on the disk: every op kind U2 defines, a move's two sides, a
    /// tree (links inside included), a link, a preference (W6). A case the
    /// ledger holds open must still be answered <c>notReadable</c> both ways
    /// and still differ from the contract.
    /// </summary>
    [Theory]
    [MemberData(nameof(Cases))]
    public void EveryCheckCase(string name) =>
        JudgeAsTheLedgerSays(name, NamedGapLedger.All, OpOf, JudgeOnTheDisk);

    /// <summary>One case, judged by <paramref name="judge"/> on the op <paramref name="readOp"/> reads, and held or not as <paramref name="entries"/> say.</summary>
    internal static void JudgeAsTheLedgerSays(string name, IEnumerable<NamedGapLedger.Entry> entries,
                                              Func<JsonElement, UndoOp> readOp,
                                              Func<string, JsonElement, UndoOp, (string Undo, string Redo)> judge)
    {
        JsonElement checkCase = CaseNamed(name);
        UndoOp op = readOp(checkCase);
        NamedGapLedger.Entry? held = NamedGapLedger.Holding(NamedGapLedger.UndoCheckCases, name, entries);
        if (held is not null) Assert.False(op.Readable, NamedGapLedger.ClosedMessage(held));
        (string undo, string redo) = judge(name, checkCase, op);
        string expectedUndo = checkCase.GetProperty("undo").GetString()!;
        string expectedRedo = checkCase.GetProperty("redo").GetString()!;
        if (held is not null)
        {
            Assert.False(undo == expectedUndo && redo == expectedRedo, NamedGapLedger.ClosedMessage(held));
            Assert.True(undo == "notReadable" && redo == "notReadable",
                $"\"{name}\" is held open (#{held.Issue}), so it must be answered notReadable both ways, never guessed at; it was answered {undo} and {redo}");
            return;
        }
        Assert.Equal(expectedUndo, undo);
        Assert.Equal(expectedRedo, redo);
    }

    /// <summary>
    /// The case's verdicts: its <c>current</c> placed on the disk and read
    /// back (a move's sides at its <c>from</c> and <c>to</c>; an external op's
    /// preference in a place of the case's own), then judged as the door
    /// judges it, a whole op against the disk as a whole.
    /// </summary>
    private (string Undo, string Redo) JudgeOnTheDisk(string name, JsonElement checkCase, UndoOp op)
    {
        JsonElement current = checkCase.GetProperty("current");
        JsonElement given = checkCase.GetProperty("op");
        string kind = given.TryGetProperty("kind", out JsonElement kindElement) && kindElement.ValueKind == JsonValueKind.String ? kindElement.GetString()! : "";
        string root = Path.Combine(_folder, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var unreadable = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        string relative = given.TryGetProperty("path", out JsonElement pathElement) && pathElement.ValueKind == JsonValueKind.String
                          && UndoPath.IsWithinTheRules(pathElement.GetString()) ? pathElement.GetString()! : "page.md";
        string full = UndoTreeReading.Under(root, relative);
        if (kind == "move")
        {
            string? from = given.TryGetProperty("from", out JsonElement f) && f.ValueKind == JsonValueKind.String ? f.GetString() : null;
            string? to = given.TryGetProperty("to", out JsonElement t) && t.ValueKind == JsonValueKind.String ? t.GetString() : null;
            if (UndoPath.IsWithinTheRules(from) && current.TryGetProperty("atFrom", out JsonElement atFrom))
            {
                string place = UndoTreeReading.Under(root, from!);
                if (PlaceAt(atFrom, place)) unreadable.Add(place);
            }
            if (UndoPath.IsWithinTheRules(to) && to != from && current.TryGetProperty("atTo", out JsonElement atTo))
            {
                string place = UndoTreeReading.Under(root, to!);
                if (UndoLinks.Look(place) == UndoLinks.What.Nothing && PlaceAt(atTo, place)) unreadable.Add(place);
            }
        }
        else if (kind != "external")
        {
            if (PlaceAt(current, full)) unreadable.Add(full);
        }
        var reading = UndoExternalReading.Unset;
        if (current.TryGetProperty("unreadable", out JsonElement flag) && flag.GetBoolean()) reading = UndoExternalReading.Unknown;
        else if (current.TryGetProperty("preference", out JsonElement preference)) reading = UndoExternalReading.Holding(UndoJson.From(preference)!);
        var caseOwn = new OneValuePlaces(reading);

        if (!op.Readable) return ("notReadable", "notReadable");
        UndoOpState state;
        if (op.IsWhole)
        {
            state = UndoCheck.WholeStateOf(op, root, caseOwn, path => unreadable.Contains(path));
        }
        else
        {
            UndoCurrent read = unreadable.Contains(full)
                ? UndoCurrent.Read(full, _ => throw new UnauthorizedAccessException("denied, as the case has it") { HResult = unchecked((int)0x80070005) })
                : UndoCurrent.Read(full);
            state = UndoCheck.StateOf(op, read);
        }
        return (UndoContract.Spelled(UndoCheck.UndoVerdictOf(state)), UndoContract.Spelled(UndoCheck.RedoVerdictOf(state)));
    }

    /// <summary>An external place holding one value, for a case.</summary>
    private sealed class OneValuePlaces(UndoExternalReading reading) : IUndoExternalPlaces
    {
        public UndoExternalReading Read(string target) => reading;
        public bool Write(string target, UndoJson? value) => false;
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
        if (op.Kind is not (UndoOp.EditLine or UndoOp.ReplaceText or UndoOp.EditJson)) return;   // writeFile needs its blob, recompute has no check, whole ops are the stack cases
        string path = Path.Combine(_folder, Guid.NewGuid().ToString("N"), "page.md");
        PlaceAt(checkCase.GetProperty("current"), path);
        byte[] before = File.ReadAllBytes(path);
        var plan = UndoCheck.Plan([op], backward: true, _ => UndoCurrent.Read(path), _ => null);
        var ready = Assert.IsType<UndoCheck.PlanResult.Ready>(plan);
        byte[] undone = Assert.Single(ready.Changes).Value!;
        Assert.Equal(UndoOpState.Before, UndoCheck.StateOf(op, new UndoCurrent.Bytes(undone)));
        var back = UndoCheck.Plan([op], backward: false, _ => new UndoCurrent.Bytes(undone), _ => null);
        byte[] redone = Assert.Single(Assert.IsType<UndoCheck.PlanResult.Ready>(back).Changes).Value!;
        if (op.Kind == UndoOp.EditJson)
        {
            // The member comes back as the same JSON value, newly spelled
            // compactly (2.0 comes back as 2); every other byte stays.
            Assert.Equal(UndoOpState.After, UndoCheck.StateOf(op, new UndoCurrent.Bytes(redone)));
            Assert.True(UndoJson.Same(UndoJsonMember.TopLevel(before), UndoJsonMember.TopLevel(redone)));
            return;
        }
        Assert.Equal(before, redone);
    }

    // ---- PROPOSED: Windows' read failures (D1, amended) --------------------------

    private static UndoOp ThePublishLineOp() => OpOf(CaseNamed("the line as the step left it"));

    private string ThePageAsTheStepLeftIt()
    {
        string path = Path.Combine(_folder, Guid.NewGuid().ToString("N"), "page.md");
        PlaceAt(CaseNamed("the line as the step left it").GetProperty("current"), path);
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
    /// <c>cannotTellNow</c> naming the page. Runs over SSH on the PC
    /// (measured 2026-11-19); skipped, saying why, where this account's token
    /// reads past a deny ACE;
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
