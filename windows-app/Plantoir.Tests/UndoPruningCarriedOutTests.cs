using System.Text;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// Pruning and deletion CARRIED OUT by <see cref="UndoJournal.Prune"/> (#899
/// W2a), on the disk: what W1's decisions name is written and deleted, in the
/// contract's order (<c>undoJournal.files</c>, <c>unknown.deleting</c>). The
/// steps are made by <see cref="UndoScribe"/> through the real store, with
/// small segments so a few dozen steps span many.
/// </summary>
public sealed class UndoPruningCarriedOutTests
{
    private const long SmallSegments = 4096;

    private static string Page => UndoContract.Fixture.Single(page => page.Id == "p1").Path;

    /// <summary>Steps whose ops are a whole file each (writeFile, two blobs), so blobs come and go.</summary>
    private static void WholeFileSteps(UndoScribe scribe, int count)
    {
        for (int index = 0; index < count; index++)
        {
            byte[] before = scribe.Page("A", Page)!;
            byte[] after = [.. before, .. Encoding.UTF8.GetBytes($"A line the step added, number {index}.\n")];
            Assert.NotNull(scribe.Step("A", [(Page, after)]));
        }
    }

    private static List<int> SegmentsOnDisk(UndoScribe scribe) => scribe.Journal.Read().SegmentsOnDisk.ToList();

    private static string SegmentFile(UndoScribe scribe, int number) => scribe.Journal.SegmentPath(number);

    [Fact]
    public void PrunedStepsSegmentsAndBlobsAreDeletedFromTheOldestEndAndTheNewestIsKept()
    {
        using var scribe = new UndoScribe(SmallSegments);
        scribe.WriteFixture("A");
        WholeFileSteps(scribe, UndoLimits.StepsKept + 10);

        UndoFolded folded = scribe.Fold();
        Assert.Equal(UndoLimits.StepsKept, folded.OnTheList.Count());
        Assert.Equal(Enumerable.Range(11, UndoLimits.StepsKept).Select(seq => (long)seq), folded.OnTheList.Select(step => step.Seq));
        // The ten pruned are pruned on the disk, or gone with the segments that held them.
        Assert.All(folded.Steps.Values.Where(step => step.Seq <= 10), step => Assert.Equal(UndoStepState.Pruned, step.State));

        List<int> segments = SegmentsOnDisk(scribe);
        Assert.True(segments[0] > 1, "no segment was deleted");
        Assert.Equal(Enumerable.Range(segments[0], segments.Count), segments);   // gone only from the oldest end
        Assert.True(File.Exists(SegmentFile(scribe, segments[^1])));
        int oldestKept = folded.OnTheList.Min(step => step.Segments.Min);
        Assert.True(segments[0] <= oldestKept, "a segment a step on the list has an event in was deleted");

        // Exactly the blobs a step on the list names are kept.
        var needed = folded.OnTheList.SelectMany(step => step.Step.Blobs).ToHashSet(StringComparer.Ordinal);
        Assert.Equal(needed.Order(StringComparer.Ordinal), scribe.Journal.BlobsOnDisk().Order(StringComparer.Ordinal));
    }

    /// <summary><c>unknown.deleting</c>: a segment holding a line this version cannot read is kept to its 60 days, and every later one with it.</summary>
    [Fact]
    public void ASegmentHoldingAnUnreadableLineIsKeptUntilItsNewestAtIsPastTheLimits()
    {
        using var scribe = new UndoScribe(SmallSegments);
        scribe.WriteFixture("A");
        scribe.AppendRaw($"{{\"v\":2,\"seq\":1,\"event\":\"somethingNew\",\"at\":\"{UndoMoment.Format(scribe.Clock.GetUtcNow())}\"}}");
        WholeFileSteps(scribe, UndoLimits.StepsKept + 10);

        List<int> segments = SegmentsOnDisk(scribe);
        Assert.Equal(1, segments[0]);
        Assert.Equal(Enumerable.Range(1, segments.Count), segments);

        scribe.Clock.SetDaysFromStart((UndoLimits.DaysKept + UndoLimits.Grace + TimeSpan.FromDays(2)).TotalDays);
        scribe.Prune();
        Assert.False(File.Exists(SegmentFile(scribe, 1)));
        Assert.Empty(scribe.Fold().OnTheList);
    }

    [Fact]
    public void ADeadWritersTemporaryBlobIsRemoved()
    {
        using var scribe = new UndoScribe();
        string leftover = Path.Combine(scribe.JournalFolder, "content", "ab", ".tmp-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.GetDirectoryName(leftover)!);
        File.WriteAllText(leftover, "half a blob");
        scribe.Prune();
        Assert.False(File.Exists(leftover));
    }

    /// <summary>Deletion stops at the first segment that will not go, so segments still go only from the oldest end; a later hold finishes it.</summary>
    [Fact]
    public void ASegmentThatWillNotDeleteStopsTheDeletionThereAndNeverFailsTheCaller()
    {
        using var scribe = new UndoScribe(SmallSegments);
        scribe.WriteFixture("A");
        WholeFileSteps(scribe, 3);
        using (new FileStream(SegmentFile(scribe, 1), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        {
            WholeFileSteps(scribe, UndoLimits.StepsKept + 10);
            List<int> held = SegmentsOnDisk(scribe);
            Assert.Equal(Enumerable.Range(1, held.Count), held);
        }
        scribe.Prune();
        Assert.False(File.Exists(SegmentFile(scribe, 1)));
        Assert.False(File.Exists(SegmentFile(scribe, 2)));
    }
}
