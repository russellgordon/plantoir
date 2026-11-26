using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W6: <c>shared-rules.json</c> → <c>undo.listingCases</c> (a folder's
/// listing, byte for byte) and <c>undo-json-cases.json</c> → <c>editJSONCases</c> (an editJSON move on
/// a file's bytes, byte for byte), every case from the JSON; and the Windows
/// points the contract leaves to the platform: a move that changes only case
/// (readable in its last part since W8-5, still not above it), a folder
/// another program holds open, a tree made inside OneDrive's
/// attributes, an external target that cannot be set.
/// </summary>
public sealed class UndoOpKindsContractTests : IDisposable
{
    private readonly string _folder = RunOwnedTempFolders.Create("plantoir-undo-kinds-");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    public static IEnumerable<object[]> ListingCases() =>
        UndoContract.Undo.GetProperty("listingCases").EnumerateArray().Select(row => new object[] { row.GetProperty("name").GetString()! });

    public static IEnumerable<object[]> EditJsonCases() =>
        UndoContract.JsonCases.GetProperty("editJSONCases").EnumerateArray().Select(row => new object[] { row.GetProperty("name").GetString()! });

    private static JsonElement Named(string list, string name) =>
        (list == "editJSONCases" ? UndoContract.JsonCases : UndoContract.Undo).GetProperty(list).EnumerateArray().Single(row => row.GetProperty("name").GetString() == name);

    private static void OnlyKeys(JsonElement row, params string[] keys)
    {
        foreach (JsonProperty key in row.EnumerateObject()) Assert.True(keys.Contains(key.Name), "a key this replay does not check: " + key.Name);
    }

    [Fact]
    public void TheContractHoldsTheListingAndEditJsonCases()
    {
        Assert.True(UndoContract.Undo.GetProperty("listingCases").GetArrayLength() >= 5);
        Assert.True(UndoContract.JsonCases.GetProperty("editJSONCases").GetArrayLength() >= 16);
        // Moved, not copied: one list in one place.
        Assert.False(UndoContract.Undo.TryGetProperty("editJSONCases", out _), "editJSONCases is in undo-json-cases.json, not shared-rules.json");
    }

    /// <summary>The listing made from the case's tree is the case's text and hash, and reads back as itself; and the same folder made on the disk lists the same.</summary>
    [Theory]
    [MemberData(nameof(ListingCases))]
    public void EveryListingCase(string name)
    {
        JsonElement row = Named("listingCases", name);
        OnlyKeys(row, "name", "tree", "listing", "listingSha", "why");
        UndoTreeListing made = UndoCheckContractTests.ListingOf(JsonNode.Parse(row.GetProperty("tree").GetRawText())!);
        Assert.Equal(row.GetProperty("listing").GetString(), made.Text);
        Assert.Equal(row.GetProperty("listingSha").GetString(), made.Sha);
        Assert.Equal(made.Text, UndoTreeListing.Parse(made.Bytes)!.Text);

        // On the disk: the folder made from the tree, read back by the reader.
        string root = Path.Combine(_folder, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        JsonElement tree = row.GetProperty("tree");
        foreach (JsonElement folder in tree.GetProperty("folders").EnumerateArray()) Directory.CreateDirectory(UndoTreeReading.Under(root, folder.GetString()!));
        foreach (JsonProperty file in tree.GetProperty("files").EnumerateObject())
        {
            string path = UndoTreeReading.Under(root, file.Name);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllBytes(path, Encoding.UTF8.GetBytes(file.Value.GetString()!));
        }
        Assert.Equal(row.GetProperty("listingSha").GetString(), UndoTreeReading.Read(root).ListingSha);
    }

    /// <summary>The file's exact bytes after the move, or a refusal (null) where the case says so.</summary>
    [Theory]
    [MemberData(nameof(EditJsonCases))]
    public void EveryEditJsonCase(string name)
    {
        JsonElement row = Named("editJSONCases", name);
        OnlyKeys(row, "name", "file", "op", "direction", "result");
        UndoOp op = UndoFormat.ReadOp(row.GetProperty("op"));
        bool backward = row.GetProperty("direction").GetString() == "undo";
        byte[]? moved = UndoJsonMember.Moved(op, Encoding.UTF8.GetBytes(row.GetProperty("file").GetString()!), backward);
        JsonElement result = row.GetProperty("result");
        NamedGapLedger.Entry? refused = NamedGapLedger.Holding(NamedGapLedger.UndoEditJsonCasesRefusedHere, name);
        if (refused is not null)
        {
            // The mac writes these bytes; this app is not measured to write
            // the same, so it must write nothing at all, never bytes of its own.
            Assert.True(result.ValueKind == JsonValueKind.String, NamedGapLedger.ClosedMessage(refused));
            Assert.True(moved is null,
                $"\"{name}\" is held open (#{refused.Issue}: {refused.Reason}), so it must be refused here; it wrote {(moved is null ? "" : Encoding.UTF8.GetString(moved))}");
            return;
        }
        if (result.ValueKind == JsonValueKind.Null) Assert.Null(moved);
        else Assert.Equal(result.GetString(), moved is null ? null : Encoding.UTF8.GetString(moved));
    }

    /// <summary>Every editJSON case held open by name is a case the contract still has.</summary>
    [Fact]
    public void EveryHeldEditJsonCaseIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoEditJsonCasesRefusedHere, EditJsonCases().Select(row => (string)row[0]));

    /// <summary>
    /// New text that starts with a byte-order mark is never written: the mac's
    /// reader drops the mark when it reads the result back (measured
    /// 2026-11-20), so the mac refuses the move, and so does this app. A mark
    /// inside the text is written as it is, on both (<c>undo-json-cases.json</c> → <c>editJSONCases</c>).
    /// Not a contract row: the mac's contract runner reads each case through
    /// <c>JSONSerialization</c>, which drops the mark, so no row can carry one.
    /// </summary>
    [Fact]
    public void NewTextStartingWithAByteOrderMarkIsNeverWritten()
    {
        byte[] file = "{\"k\": 0}\n"u8.ToArray();
        UndoOp Op(string after)
        {
            var given = new JsonObject { ["kind"] = "editJSON", ["path"] = "course_config.json", ["keyPath"] = new JsonArray("k"), ["before"] = 0, ["after"] = after };
            using JsonDocument document = JsonDocument.Parse(given.ToJsonString());
            return UndoFormat.ReadOp(document.RootElement);
        }
        Assert.Null(UndoJsonMember.Moved(Op("\uFEFFa"), file, backward: false));
        Assert.Equal("{\"k\": \"a\uFEFFb\"}\n", Encoding.UTF8.GetString(UndoJsonMember.Moved(Op("a\uFEFFb"), file, backward: false)!));
    }

    /// <summary>
    /// Where the digits this app is measured to read as the mac reads them end
    /// (2026-11-20, through the mac's reader): 17 with an exponent, 38 without,
    /// counted from the first digit that is not a leading zero of the integer
    /// part. One more is a file this app answers cannot tell
    /// (<c>undo.checkCases</c>).
    /// </summary>
    [Fact]
    public void TheMeasuredDigitsEndAt17WithAnExponentAnd38Without()
    {
        Assert.True(UndoJson.SpellingIsMeasured("1.2345678901234567e-5"));
        Assert.False(UndoJson.SpellingIsMeasured("1.23456789012345678e-5"));
        Assert.True(UndoJson.SpellingIsMeasured("0.12345678901234567e3"));
        Assert.False(UndoJson.SpellingIsMeasured("0.00012339999999999999e0"));
        Assert.True(UndoJson.SpellingIsMeasured("0." + new string('1', 38)));
        Assert.False(UndoJson.SpellingIsMeasured("0." + new string('1', 39)));
        Assert.True(UndoJson.SpellingIsMeasured("-" + new string('9', 38)));
        Assert.False(UndoJson.SpellingIsMeasured("-" + new string('9', 39)));
        Assert.True(UndoJson.SpellingIsMeasured("12345678901234567890.123456789012345678"));
        Assert.False(UndoJson.SpellingIsMeasured("12345678901234567890.1234567890123456789"));
    }

    public static IEnumerable<object[]> NumberSpellingCases() =>
        UndoContract.Undo.GetProperty("numberSpellingCases").EnumerateArray().Select(row => new object[] { row.GetProperty("name").GetString()! });

    /// <summary>
    /// The limits this app reads numbers within are the contract's one rule
    /// (<c>undo.numberSpellingRule</c>, measured through the mac's reader),
    /// the same numbers the Python model checks.
    /// </summary>
    [Fact]
    public void TheNumberLimitsAreTheContractsRule()
    {
        JsonElement rule = UndoContract.Undo.GetProperty("numberSpellingRule");
        Assert.Equal(rule.GetProperty("exponentCharactersAtMost").GetInt32(), UndoJson.MacExponentCharactersAtMost);
        Assert.Equal(rule.GetProperty("digitsWithAnExponentAtMost").GetInt32(), UndoJson.MeasuredDigitsWithAnExponent);
        Assert.Equal(rule.GetProperty("digitsWithoutAnExponentAtMost").GetInt32(), UndoJson.MeasuredDigitsWithoutAnExponent);
        Assert.True(UndoContract.Undo.GetProperty("numberSpellingCases").GetArrayLength() >= 30);
    }

    /// <summary>
    /// A number a file spells with an exponent is read here as the mac's
    /// reader reads it, or the file is refused as the case says: not JSON
    /// (no member, and a move on another member refused), cannot tell (read
    /// but not measured, and a move refused), minus infinity, or the double.
    /// </summary>
    [Theory]
    [MemberData(nameof(NumberSpellingCases))]
    public void EveryNumberSpellingCase(string name)
    {
        JsonElement row = Named("numberSpellingCases", name);
        OnlyKeys(row, "name", "spelling", "reads");
        string spelling = row.GetProperty("spelling").GetString()!;
        byte[] file = Encoding.UTF8.GetBytes("{\"a\": " + spelling + ", \"b\": 1}\n");
        UndoJson.Members? read = UndoJsonMember.TopLevel(file);
        var given = new JsonObject { ["kind"] = "editJSON", ["path"] = "course_config.json", ["keyPath"] = new JsonArray("b"), ["before"] = 1, ["after"] = 2 };
        using JsonDocument opDocument = JsonDocument.Parse(given.ToJsonString());
        byte[]? moved = UndoJsonMember.Moved(UndoFormat.ReadOp(opDocument.RootElement), file, backward: false);
        JsonElement reads = row.GetProperty("reads");
        string expected = reads.ValueKind == JsonValueKind.Number ? "aNumber" : reads.GetString()!;
        switch (expected)
        {
            case "notJSON":
                Assert.Null(read);
                Assert.Null(moved);
                return;
            case "cannotTell":
                Assert.NotNull(read);
                Assert.False(read!.HoldsOnlyMeasuredNumbers, spelling + " must not be read as measured");
                Assert.Null(moved);
                return;
        }
        Assert.NotNull(read);
        UndoJson.Number number = Assert.IsType<UndoJson.Number>(read!.Items["a"]);
        Assert.True(number.Measured, spelling + " must be read as measured");
        double wanted = expected == "minusInfinity" ? double.NegativeInfinity : reads.GetDouble();
        Assert.Equal(wanted, number.Value);
        Assert.NotNull(moved);
    }

    /// <summary>
    /// A file that starts with a UTF-8 byte-order mark is read as the mac's
    /// reader reads it (measured on the mac, 2026-11-20: its member judged as
    /// the step left it), so the verdict before a write is the mac's; and it
    /// is never moved, as on the mac, whose byte scanner starts at the mark.
    /// Not a contract row: the mac's contract runner hands each case's file
    /// over through <c>JSONSerialization</c>, which drops a mark at the start
    /// of a string (measured), so no row can carry one.
    /// </summary>
    [Fact]
    public void AFileStartingWithAByteOrderMarkIsJudgedAsTheMacJudgesIt()
    {
        byte[] file = [0xEF, 0xBB, 0xBF, .. "{\"school_year\": \"2026-2027\"}\n"u8];
        var op = new JsonObject { ["kind"] = "editJSON", ["path"] = "course_config.json", ["keyPath"] = new JsonArray("school_year"), ["before"] = "2025-2026", ["after"] = "2026-2027" };
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        UndoOp read = UndoFormat.ReadOp(document.RootElement);
        Assert.Equal(UndoOpState.After, UndoJsonMember.StateOf(read, new UndoCurrent.Bytes(file)));
        Assert.Null(UndoJsonMember.Moved(read, file, backward: true));
        // A space before the mark is not JSON, there as here.
        byte[] spaced = [0x20, .. file];
        Assert.Equal(UndoOpState.Neither, UndoJsonMember.StateOf(read, new UndoCurrent.Bytes(spaced)));
    }

    /// <summary>
    /// NTFS takes <c>a.json</c> and <c>A.json</c> for one place. Since W8-5 a
    /// move that changes only the case of its last part is readable, as on
    /// the mac since U4b (<c>opKinds.move</c>'s capitalisation-only rename,
    /// <c>UndoOp.IsCaseOnlyMove</c>); a move whose case differs in a
    /// folder above the last part is still a step this version cannot read,
    /// never a rename that could be read as both places free or both full;
    /// and a move between two different names is readable as any move.
    /// </summary>
    [Fact]
    public void AMoveThatChangesOnlyCaseInItsLastPartIsReadable()
    {
        var op = new JsonObject { ["kind"] = "move", ["from"] = "courses/TST1O/a.json", ["to"] = "courses/TST1O/A.json", ["sha"] = new string('a', 64) };
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        Assert.True(UndoFormat.ReadOp(document.RootElement).Readable);
        op["to"] = "courses/tst1o/A.json";
        using JsonDocument above = JsonDocument.Parse(op.ToJsonString());
        Assert.False(UndoFormat.ReadOp(above.RootElement).Readable);
        op["to"] = "courses/TST1O/b.json";
        using JsonDocument other = JsonDocument.Parse(op.ToJsonString());
        Assert.True(UndoFormat.ReadOp(other.RootElement).Readable);
    }

    /// <summary>
    /// A folder whose file another program holds open cannot be renamed on
    /// Windows: taking it out is refused as a file in use, the folder left
    /// whole in its place and nothing on the list cleared; once let go, the
    /// same Undo takes it out.
    /// </summary>
    [Fact]
    public void AFolderHeldOpenIsNotTakenOutAndIsTakenOutOnceLetGo()
    {
        using var scribe = new UndoScribe();
        (UndoTreeListing listing, List<byte[]> contents) = UndoKindsForTheCases.ExtraListing();
        (JsonObject op, List<byte[]> blobs) = UndoKindsForTheCases.Tree("createTree", UndoKindsForTheCases.ExtraFolder, listing, contents);
        Assert.Equal(UndoOutcomeKind.Applied, scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(op), blobs)).Kind);
        string held = UndoTreeReading.Under(scribe.FullPath("A", UndoKindsForTheCases.ExtraFolder), "a.md");
        UndoOutcome refused;
        using (new FileStream(held, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            refused = scribe.Door().Undo();
        }
        Assert.Equal(UndoRefusalKind.FileIsInUse, refused.Refusal?.Kind);
        Assert.False(refused.ClearedTheList);
        Assert.True(UndoKindsForTheCases.FolderIsThere(scribe));
        Assert.Empty(scribe.StagedLeftovers("A"));
        Assert.Equal(UndoOutcomeKind.Undone, scribe.Door().Undo().Kind);
        Assert.False(UndoKindsForTheCases.FolderIsThere(scribe));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>
    /// An external target that cannot be set (the store refuses) is refused
    /// <c>couldNotWrite</c>, and the pages the same step had already swapped
    /// are put back: all or nothing, the external op included.
    /// </summary>
    [Fact]
    public void AnExternalTargetThatCannotBeSetPutsTheStepsPagesBack()
    {
        using var scribe = new UndoScribe();
        const string page = "courses/TST1O/Section 1/Classes/first.md";
        byte[] before = "---\ntitle: first\npublish: false\n---\n"u8.ToArray();
        byte[] after = "---\ntitle: first\npublish: true\n---\n"u8.ToArray();
        scribe.WritePage("A", page, before);
        JsonArray ops = scribe.OpsFor(page, before, after);
        ops.Add(UndoKindsForTheCases.External(UndoKindsForTheCases.Preference, null, "b", hasBefore: false));
        var refusing = new RefusingPlaces();
        var door = new UndoDoor(scribe.Journal, UndoMode.Live, scribe.Maintainers, places: refusing);
        UndoOutcome outcome = door.Perform(scribe.OpsDraft("A", ops, []));
        Assert.Equal(UndoRefusalKind.CouldNotWrite, outcome.Refusal?.Kind);
        Assert.Equal(before, scribe.Page("A", page));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    private sealed class RefusingPlaces : IUndoExternalPlaces
    {
        public UndoExternalReading Read(string target) => UndoExternalReading.Unset;
        public bool Write(string target, UndoJson? value) => false;
    }

    /// <summary>
    /// A step of external ops alone has no working folder: it is recorded
    /// without one, undone and redone through the door (the stack case
    /// <c>setAPreference</c> is the contract's; this pins that its begin
    /// line names no folder).
    /// </summary>
    [Fact]
    public void AStepOfAPreferenceAloneNamesNoWorkingFolder()
    {
        using var scribe = new UndoScribe();
        var ops = new JsonArray(UndoKindsForTheCases.External(UndoKindsForTheCases.Preference, null, "b", hasBefore: false));
        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft(null, ops, []));
        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        Assert.Null(scribe.Fold().Steps[made.Seq!.Value].Step.WorkingFolder);
        Assert.Equal(UndoOutcomeKind.Undone, scribe.Door().Undo().Kind);
        Assert.True(scribe.Places.Read(UndoKindsForTheCases.Preference).NotSet);
    }

    /// <summary>The compact spelling, as the mac's own code spells it (measured, 2026-11-20): keys sorted, a whole number without a point, a fraction in %.17g, and a whole number beyond 2^53 refused.</summary>
    [Fact]
    public void ANewValueIsSpelledCompactlyAndNeverApproximately()
    {
        using JsonDocument document = JsonDocument.Parse("{\"z\": [1.0, 0.1, \"a/b\\n\"], \"a\": null, \"m\": {\"y\": true, \"b\": false}}");
        Assert.Equal("{\"a\":null,\"m\":{\"b\":false,\"y\":true},\"z\":[1,0.10000000000000001,\"a/b\\n\"]}", UndoJson.From(document.RootElement)!.Spelled());
        using JsonDocument big = JsonDocument.Parse("9007199254740993");
        Assert.Null(UndoJson.From(big.RootElement)!.Spelled());
    }

    /// <summary>The app's settings store as an external place: a name it does not have cannot tell, and "not set" cannot be written to a typed setting.</summary>
    [Fact]
    public void TheAppsSettingsStoreReadsOnlyNamesItHas()
    {
        var places = new UndoAppSettingsPlaces();
        Assert.True(places.Read("preference:aSettingNobodyHas").CannotTell);
        Assert.False(places.Write("preference:aSettingNobodyHas", new UndoJson.Text("x")));
        Assert.False(places.Write("preference:PreviewOpensAt", null));
        Assert.True(places.Read("other:PreviewOpensAt").CannotTell);
    }

    /// <summary>
    /// A junction is never followed, even when the folder it leads to holds
    /// exactly what the step moved: a folder's move whose destination is now a
    /// junction to a copy of the moved folder is changed since, never "as the
    /// step left it" (the contract's link rows lead to content that differs,
    /// so they would pass a reader that followed links; this one would not).
    /// </summary>
    [Fact]
    public void AJunctionToTheVeryContentIsStillNeverFollowed()
    {
        string root = Path.Combine(_folder, Guid.NewGuid().ToString("N"));
        string copy = Path.Combine(_folder, "copy-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(copy);
        File.WriteAllText(Path.Combine(copy, "20261101T080000Z-netlify.json"), "{\"places\": []}\n");
        UndoTreeListing listing = new([], [("20261101T080000Z-netlify.json", UndoCheck.Sha("{\"places\": []}\n"u8.ToArray()))]);
        Assert.Equal(listing.Sha, UndoTreeReading.Read(copy).ListingSha);
        string to = UndoTreeReading.Under(root, "courses/TST1O/record.previous");
        UndoKindsForTheCases.MakeAJunction(to, copy);
        var op = new JsonObject { ["kind"] = "move", ["from"] = "courses/TST1O/record", ["to"] = "courses/TST1O/record.previous", ["listingSha"] = listing.Sha };
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        UndoOp read = UndoFormat.ReadOp(document.RootElement);
        Assert.True(read.Readable);
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(to));
        Assert.Equal(UndoOpState.Neither, UndoCheck.WholeStateOf(read, root, new UndoMemoryPlaces()));
    }
}
