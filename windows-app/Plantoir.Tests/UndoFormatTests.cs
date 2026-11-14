using System.Text;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The journal's format read leniently (<c>file-formats.json</c> →
/// <c>undoJournal</c>, #899 piece W1): one test per sentence of
/// <c>unknown</c>, <c>eventKeys</c>, <c>events.note</c>, <c>stepKeys</c> and
/// <c>opKinds</c> that a reader has to get right. The rule under all of them:
/// what a reader cannot read it KEEPS, as a barrier, and never skips.
/// </summary>
public sealed class UndoFormatTests
{
    private const string At = "2026-11-14T12:00:00Z";
    private static readonly DateTimeOffset Now = new(2026, 11, 14, 12, 0, 0, TimeSpan.Zero);

    private static string Op(string path = "courses/TST1O/page.md") =>
        $"{{\"kind\":\"editLine\",\"path\":\"{path}\",\"key\":\"publish\",\"before\":\"publish: false\",\"after\":\"publish: true\",\"afterKey\":\"title\"}}";

    private static string Begin(long seq, string? ops = null, string extraStep = "", string extraLine = "") =>
        $"{{\"v\":1,\"seq\":{seq},\"event\":\"begin\",\"at\":\"{At}\"{extraLine},\"process\":{{\"host\":\"h\",\"pid\":1,\"name\":\"n\",\"started\":\"s\"}}," +
        $"\"step\":{{\"seq\":{seq},\"madeAt\":\"{At}\",\"workingFolder\":{{\"id\":\"x\",\"pathAtTheTime\":\"C:\\\\A\"}},\"ops\":[{ops ?? Op()}]{extraStep}}}}}";

    private static string Applied(long seq) => $"{{\"v\":1,\"seq\":{seq},\"event\":\"applied\",\"at\":\"{At}\"}}";

    private static UndoFolded Fold(params string[] lines) =>
        UndoFold.Fold(lines.Select((line, place) => UndoFormat.Parse(line, 1, place)));

    private static UndoOffered Offer(UndoFolded folded) => UndoLimits.Offer(folded, Now, _ => true, _ => true);

    [Fact]
    public void AnOrdinaryStepIsReadable()
    {
        UndoLine line = UndoFormat.Parse(Begin(1));
        Assert.True(line.Readable);
        Assert.True(line.Step!.Readable);
        Assert.Equal(UndoEvent.Begin, line.Event);
        Assert.Equal(1, Offer(Fold(Begin(1), Applied(1))).Undo.Seq);
    }

    [Theory]
    [InlineData("not json at all")]
    [InlineData("[1,2,3]")]
    [InlineData("")]
    [InlineData("{\"v\":\"1\",\"seq\":2,\"event\":\"applied\"}")]          // v a string
    [InlineData("{\"v\":2,\"seq\":2,\"event\":\"applied\"}")]              // a newer version
    [InlineData("{\"seq\":2,\"event\":\"applied\"}")]                      // no v
    [InlineData("{\"v\":1,\"seq\":2,\"event\":\"somethingNew\"}")]         // an event this version does not know
    [InlineData("{\"v\":1,\"seq\":2,\"event\":\"failed\",\"phase\":\"sideways\"}")]
    [InlineData("{\"v\":1,\"seq\":2,\"event\":\"failed\"}")]               // no phase
    [InlineData("{\"v\":1,\"seq\":2,\"event\":\"begin\"}")]                // a begin with no step
    [InlineData("{\"v\":1,\"seq\":2,\"event\":\"begin\",\"step\":{\"seq\":3,\"madeAt\":\"2026-11-14T12:00:00Z\",\"ops\":[]}}")]   // step.seq differs
    [InlineData("{\"v\":1,\"seq\":2,\"seq\":2,\"event\":\"applied\"}")]    // a key twice: never a guess
    [InlineData("{\"v\":1,\"seq\":2.5,\"event\":\"applied\"}")]            // not a whole number
    public void ALineThisVersionCannotReadIsKeptAsABarrierAboveTheHead(string unreadable)
    {
        UndoFolded folded = Fold(Begin(1), Applied(1), unreadable);
        UndoOffered offered = Offer(folded);
        Assert.Equal(UndoAnswerKind.NotAvailable, offered.Undo.Kind);   // never undone past
        Assert.Equal(UndoAnswerKind.NotAvailable, offered.Redo.Kind);
        Assert.Equal(1, offered.Head?.Seq);                              // and never a reason to clear
        Assert.Single(folded.Barriers);
    }

    [Fact]
    public void AnUnreadableLinesSeqStillCountsForTheNextNumber()
    {
        Assert.Equal(6, Fold(Begin(1), Applied(1), "{\"v\":2,\"seq\":5,\"event\":\"x\"}").NextSeq);
        Assert.Equal(2, Fold(Begin(1), Applied(1), "garbage 99").NextSeq);   // no seq to count
    }

    [Fact]
    public void ABarrierBelowTheHeadDoesNotStopUndo()
    {
        UndoOffered offered = Offer(Fold(Begin(1), Applied(1), "{\"v\":2,\"seq\":2,\"event\":\"x\"}", Begin(3), Applied(3)));
        Assert.Equal(3, offered.Undo.Seq);
    }

    [Fact]
    public void ABarrierWithNoSeqStandsByItsPlace()
    {
        Assert.Equal(UndoAnswerKind.NotAvailable, Offer(Fold(Begin(1), Applied(1), "garbage")).Undo.Kind);
        Assert.Equal(2, Offer(Fold(Begin(1), Applied(1), "garbage", Begin(2), Applied(2))).Undo.Seq);
    }

    [Fact]
    public void AClearedLineAfterABarrierEndsIt()
    {
        string cleared = $"{{\"v\":1,\"seq\":2,\"event\":\"cleared\",\"reason\":\"aReasonNoReaderKnows\",\"at\":\"{At}\"}}";
        UndoFolded folded = Fold(Begin(1), Applied(1), "{\"v\":2,\"seq\":2,\"event\":\"x\"}", cleared, Begin(3), Applied(3));
        Assert.Equal(3, Offer(folded).Undo.Seq);
        UndoFolded byPlace = Fold(Begin(1), Applied(1), "garbage", cleared);
        Assert.Equal(UndoAnswerKind.Nothing, Offer(byPlace).Undo.Kind);
    }

    [Fact]
    public void ASecondBeginWithAUsedSeqIsUnreadableAndTheFirstStands()
    {
        UndoFolded folded = Fold(Begin(1), Applied(1), Begin(1));
        Assert.Equal(UndoStepState.Done, folded.Steps[1].State);
        Assert.Single(folded.Barriers);
        Assert.Equal(UndoAnswerKind.NotAvailable, Offer(folded).Undo.Kind);
    }

    [Theory]
    [InlineData("{\"kind\":\"replaceText\",\"path\":\"a.md\",\"before\":\"a\",\"after\":\"b\"}")]            // a reserved kind
    [InlineData("{\"kind\":\"somethingNew\",\"path\":\"a.md\"}")]
    [InlineData("{\"path\":\"a.md\"}")]                                                                     // no kind
    [InlineData("{\"kind\":\"editLine\",\"path\":\"a.md\",\"before\":\"publish: false\"}")]                 // no key
    [InlineData("{\"kind\":\"editLine\",\"path\":\"a.md\",\"key\":\"publish\"}")]                           // neither before nor after
    [InlineData("{\"kind\":\"editLine\",\"path\":\"a.md\",\"key\":\"publish\",\"before\":3}")]              // wrong type
    [InlineData("{\"kind\":\"editLine\",\"key\":\"publish\",\"before\":\"x\"}")]                            // no path
    [InlineData("{\"kind\":\"editLine\",\"path\":\"../a.md\",\"key\":\"publish\",\"before\":\"x\"}")]
    [InlineData("{\"kind\":\"recompute\",\"path\":\"a.md\",\"maintainer\":\"aMaintainerNobodyKnows\"}")]
    [InlineData("{\"kind\":\"recompute\",\"path\":\"a.md\"}")]
    [InlineData("{\"kind\":\"writeFile\",\"path\":\"a.md\",\"afterSha\":\"NOTAHASH\"}")]
    [InlineData("{\"kind\":\"writeFile\",\"path\":\"a.md\",\"blobs\":\"not an array\"}")]
    [InlineData("{\"kind\":\"editLine\",\"path\":\"a.md\",\"key\":\"publish\",\"key\":\"draft\",\"before\":\"x\"}")]
    [InlineData("\"not an object\"")]
    public void AStepWithAnOpThisVersionCannotReadMovesThroughTheFoldButIsABarrier(string op)
    {
        UndoFolded folded = Fold(Begin(1), Applied(1), Begin(2, op), Applied(2));
        Assert.Equal(UndoStepState.Done, folded.Steps[2].State);
        Assert.False(folded.Steps[2].Readable);
        UndoOffered offered = Offer(folded);
        Assert.Equal(UndoAnswerKind.NotAvailable, offered.Undo.Kind);
        Assert.Equal(2, offered.Head?.Seq);
    }

    [Theory]
    [InlineData(",\"holds\":\"workingFolder\"")]
    [InlineData(",\"holds\":3")]
    [InlineData(",\"madeBy\":7")]
    [InlineData(",\"section\":\"one\"")]
    [InlineData(",\"action\":\"publishPages\"")]
    [InlineData(",\"action\":{\"key\":\"x\",\"arguments\":{\"pageCount\":3}}")]
    public void AStepKeyOfAKindThisVersionCannotReadMakesTheStepABarrier(string extra)
    {
        UndoFolded folded = Fold(Begin(1, extraStep: extra), Applied(1));
        Assert.False(folded.Steps[1].Readable);
        Assert.Equal(UndoAnswerKind.NotAvailable, Offer(folded).Undo.Kind);
    }

    [Theory]
    [InlineData(",\"holds\":\"section\"")]
    [InlineData(",\"holds\":\"course\"")]
    [InlineData(",\"madeBy\":\"aMakerNobodyKnows:x:y\"")]
    [InlineData(",\"class\":\"Z\"")]
    [InlineData(",\"action\":{\"key\":\"aKeyNobodyKnows\",\"arguments\":{}}")]
    [InlineData(",\"somethingNew\":{\"deep\":[1,2,3]}")]
    public void OpenStringsAndUnknownKeysOnAStepAreRead(string extra)
    {
        UndoFolded folded = Fold(Begin(1, extraStep: extra), Applied(1));
        Assert.True(folded.Steps[1].Readable);
        Assert.Equal(1, Offer(folded).Undo.Seq);
    }

    [Fact]
    public void AKeyThisVersionDoesNotKnowOnAKnownOpIsIgnoredAndTheOpRead()
    {
        string op = "{\"kind\":\"editLine\",\"path\":\"a.md\",\"key\":\"publish\",\"before\":\"publish: false\",\"after\":\"publish: true\",\"onlyWhen\":\"aConditionNobodyKnows\"}";
        Assert.True(Fold(Begin(1, op), Applied(1)).Steps[1].Readable);
    }

    [Fact]
    public void AStepWithPathsAndNoWorkingFolderCannotBeRead()
    {
        string noFolder = $"{{\"v\":1,\"seq\":1,\"event\":\"begin\",\"step\":{{\"seq\":1,\"madeAt\":\"{At}\",\"ops\":[{Op()}]}}}}";
        Assert.False(UndoFormat.Parse(noFolder).Step!.Readable);
    }

    [Theory]
    [InlineData("outsideAssistant:A client: with colons:session-7", "outsideAssistant", "A client: with colons", "session-7")]
    [InlineData("outsideAssistant::session-7", "outsideAssistant", "", "session-7")]
    [InlineData("builtInAssistant:conversation-1", "builtInAssistant", null, "conversation-1")]
    [InlineData("menu", "menu", null, null)]
    public void MadeBySplitsAtItsEnds(string madeBy, string who, string? client, string? id) =>
        Assert.Equal(new UndoMadeBy(who, client, id), UndoMadeBy.Split(madeBy));

    [Fact]
    public void ANoteIsPassedOverWhateverElseItCarries()
    {
        string note = "{\"v\":1,\"seq\":1,\"event\":\"note\",\"phase\":\"sideways\",\"reason\":\"x\",\"about\":\"y\",\"somethingNew\":[1]}";
        UndoLine line = UndoFormat.Parse(note);
        Assert.True(line.Readable);
        UndoFolded folded = Fold(Begin(1), Applied(1), note);
        Assert.Empty(folded.Barriers);
        Assert.Equal(1, Offer(folded).Undo.Seq);
    }

    [Theory]
    [InlineData("{\"seq\":1,\"event\":\"note\"}")]          // no v
    [InlineData("{\"v\":1,\"event\":\"note\"}")]            // no seq
    [InlineData("{\"v\":1,\"seq\":\"1\",\"event\":\"note\"}")]
    public void ANoteWithoutItsRequiredKeysIsAnUnreadableLine(string note) =>
        Assert.False(UndoFormat.Parse(note).Readable);

    [Fact]
    public void ANoteWhoseSeqIsAboveEveryStepRaisesTheNextNumber() =>
        Assert.Equal(10, Fold(Begin(1), Applied(1), "{\"v\":1,\"seq\":9,\"event\":\"note\"}").NextSeq);

    [Fact]
    public void ACarriageReturnBeforeTheLineFeedIsTheSameLine()
    {
        UndoLine plain = UndoFormat.Parse(Encoding.UTF8.GetBytes(Begin(1)));
        UndoLine crlf = UndoFormat.Parse(Encoding.UTF8.GetBytes(Begin(1) + "\r"));
        Assert.True(crlf.Readable);
        Assert.Equal(plain.Seq, crlf.Seq);
        Assert.True(crlf.Step!.Readable);
    }

    [Fact]
    public void BytesThatAreNotUtf8MakeTheLineUnreadableAndItsBlobNamesAreKept()
    {
        string name = new('c', 64);
        byte[] bytes = [.. Encoding.ASCII.GetBytes("{\"v\":1,\"seq\":3,\"blob\":\"" + name + "\",\"x\":\""), 0xFF, .. "\"}"u8.ToArray()];
        UndoLine line = UndoFormat.Parse(bytes);
        Assert.False(line.Readable);
        Assert.Contains(name, line.BlobNamesInText);
    }

    [Fact]
    public void BlobNamesAreRunsOfExactly64LowerHexStandingAlone()
    {
        string name = new('a', 64);
        Assert.Equal([name], UndoFormat.BlobNames($"\"{name}\" \"{new string('b', 65)}\" x{name} {name.ToUpperInvariant()}"));
        Assert.Equal([name], UndoFormat.BlobNames($"content/aa/{name}"));
    }

    [Fact]
    public void AnUnreadableStepKeepsEveryBlobNameItsBeginHolds()
    {
        string name = new('d', 64);
        string op = $"{{\"kind\":\"move\",\"from\":\"a.md\",\"to\":\"b.md\",\"listingSha\":\"{name}\"}}";
        UndoFolded folded = Fold(Begin(1, op), Applied(1));
        Assert.Contains(name, folded.Steps[1].Step.Blobs);
        Assert.Contains(name, folded.Segments[1].BlobsKeptByUnreadables);
    }

    [Theory]
    [InlineData("2026-11-13T21:04:05Z", true)]
    [InlineData("2026-11-13T21:04:05.123Z", true)]
    [InlineData("2026-11-13T21:04:05.1234567Z", true)]
    [InlineData("2026-11-13T21:04:05+00:00", false)]
    [InlineData("2026-11-13 21:04:05Z", false)]
    [InlineData("13/11/2026", false)]
    public void TheMomentIsUtcToTheSecondWithFractionsAccepted(string text, bool readable) =>
        Assert.Equal(readable, UndoMoment.Parse(text) is not null);

    [Fact]
    public void AMomentIsWrittenToTheSecondInUtc() =>
        Assert.Equal("2026-11-13T21:04:05Z", UndoMoment.Format(new DateTimeOffset(2026, 11, 13, 16, 4, 5, 999, TimeSpan.FromHours(-5))));

    [Theory]
    [InlineData("courses/TST1O/Section 1/Classes/Unit 1, Day 1.md", true)]
    [InlineData("courses/a:b.md", true)]
    [InlineData("", false)]
    [InlineData("/courses/a.md", false)]
    [InlineData("courses\\a.md", false)]
    [InlineData("C:/courses/a.md", false)]
    [InlineData("courses//a.md", false)]
    [InlineData("courses/./a.md", false)]
    [InlineData("courses/../a.md", false)]
    [InlineData("courses/a.md/", false)]
    [InlineData("courses/a\0.md", false)]
    public void ThePathRule(string path, bool within) => Assert.Equal(within, UndoPath.IsWithinTheRules(path));
}
