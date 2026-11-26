using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>opKinds.wholeOps</c>' one exception, on Windows (#899 W8-2): the one
/// comparison for "at or inside" (<see cref="UndoOp.PartInside"/>), and a
/// folder move's <c>listingSha</c>, which is never a blob
/// (<c>opKinds.move</c>: "The moved content is never a blob: the item itself
/// is what moves").
/// </summary>
public sealed class UndoCarryingMoveTests
{
    [Theory]
    [InlineData("courses/TST1O/renamed", "courses/TST1O/renamed", "")]
    [InlineData("courses/TST1O/renamed", "courses/TST1O/renamed/a.md", "a.md")]
    [InlineData("courses/TST1O/renamed", "courses/TST1O/Renamed/Sub/A.md", "Sub/A.md")]
    [InlineData("courses/tst1o/RENAMED", "courses/TST1O/renamed/a.md", "a.md")]
    public void PartInsideComparesEachPartWithoutRegardToCaseAndKeepsTheRestAsSpelled(string place, string path, string inside)
    {
        Assert.Equal(inside, UndoOp.PartInside(place, path));
    }

    [Theory]
    [InlineData("Media", "Mediahouse/a.md")]
    [InlineData("courses/TST1O/media", "courses/TST1O/mediahouse")]
    [InlineData("courses/TST1O/media/a.md", "courses/TST1O/media")]
    [InlineData("courses/TST1O/media", "courses/TST1O/other/media/a.md")]
    public void PartInsideIsNullForAPartThatOnlyBeginsAlikeOrAPathOutside(string place, string path)
    {
        Assert.Null(UndoOp.PartInside(place, path));
    }

    [Fact]
    public void PlacesOverlapIsPartInsideEitherWay()
    {
        Assert.True(UndoOp.PlacesOverlap("courses/TST1O/Media", "courses/TST1O/media/a.md"));
        Assert.True(UndoOp.PlacesOverlap("courses/TST1O/media/a.md", "courses/TST1O/MEDIA"));
        Assert.False(UndoOp.PlacesOverlap("courses/TST1O/Media", "courses/TST1O/Mediahouse/a.md"));
    }

    private static UndoTreeListing MediaListing() =>
        new(["sub"], [("a.md", UndoCheck.Sha(Encoding.UTF8.GetBytes("A\n"))), ("sub/b.md", UndoCheck.Sha(Encoding.UTF8.GetBytes("B\n")))]);

    [Fact]
    public void AFolderMovesListingIsNotOneOfItsBlobs()
    {
        UndoTreeListing listing = MediaListing();
        var op = new JsonObject { ["kind"] = "move", ["from"] = "courses/TST1O/media", ["to"] = "courses/TST1O/renamed", ["listingSha"] = listing.Sha };
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        UndoOp read = UndoFormat.ReadOp(document.RootElement);
        Assert.True(read.Readable);
        Assert.Empty(read.Blobs);
    }

    [Fact]
    public void ATreesListingIsStillOneOfItsBlobs()
    {
        UndoTreeListing listing = MediaListing();
        (JsonObject op, _) = UndoKindsForTheCases.Tree("createTree", "courses/TST1O/media", listing, []);
        using JsonDocument document = JsonDocument.Parse(op.ToJsonString());
        Assert.Contains(listing.Sha, UndoFormat.ReadOp(document.RootElement).Blobs);
    }

    /// <summary>
    /// A folder move is made through the door with no listing blob given or
    /// held (the mac's <c>JournaledWrite.vet</c> refused every one until U4b),
    /// and its Undo moves the folder back.
    /// </summary>
    [Fact]
    public void AFolderMoveIsMadeThroughTheDoorWithNoListingBlobAndUndone()
    {
        using var scribe = new UndoScribe();
        const string from = "courses/TST1O/media";
        const string to = "courses/TST1O/renamed";
        scribe.WritePage("A", from + "/a.md", Encoding.UTF8.GetBytes("A\n"));
        scribe.WritePage("A", from + "/sub/b.md", Encoding.UTF8.GetBytes("B\n"));
        UndoTreeListing listing = MediaListing();
        Assert.Equal(listing.Sha, UndoTreeReading.Read(scribe.FullPath("A", from)).ListingSha);
        var op = new JsonObject { ["kind"] = "move", ["from"] = from, ["to"] = to, ["listingSha"] = listing.Sha };

        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(op), []));

        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        Assert.False(scribe.BlobIsThere(listing.Sha));
        Assert.Equal(listing.Sha, UndoTreeReading.Read(scribe.FullPath("A", to)).ListingSha);
        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal(listing.Sha, UndoTreeReading.Read(scribe.FullPath("A", from)).ListingSha);
        Assert.IsType<UndoTreeReading.Absent>(UndoTreeReading.Read(scribe.FullPath("A", to)));
    }
}
