using Plantoir.Core.Assist;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The local assistant's model housekeeping: what is on disk, and what the
/// Download/Remove buttons actually do about it. Mirrors the shape of the
/// mac's AssistantSettingsTests.swift, adapted to what is testable here
/// without a real network fetch (LocalModel's HttpClient has no injection
/// seam, so the download itself — like the mac's own equivalent — is
/// exercised by hand against the real app, not by this suite).
/// </summary>
// Shares LocalModelTests' collection: both touch
// LocalModel.ModelDirectoryOverride, a process-wide static, and xUnit
// parallelises test classes by default.
[Collection(SharedLocalModelState.Name)]
public sealed class AssistModelStoreTests : IDisposable
{
    private readonly string _modelsFolder = Path.Combine(Path.GetTempPath(), "plantoir-models-" + Guid.NewGuid().ToString("N"));

    public AssistModelStoreTests()
    {
        Directory.CreateDirectory(_modelsFolder);
        LocalModel.ModelDirectoryOverride = _modelsFolder;
        // The stores are shared process-wide, so one cached against the
        // last test's temporary folder would answer questions about this
        // one's — the exact trap CLAUDE.md names for process-wide statics.
        AssistModelStores.Reset();
        // Same reasoning: which assistant windows are "open" is process-wide
        // too, and a session left over from a previous test would make this
        // one's removal guard fire (or not fire) for the wrong reason.
        AssistActivity.Reset();
    }

    public void Dispose()
    {
        AssistModelStores.Reset();
        AssistActivity.Reset();
        LocalModel.ModelDirectoryOverride = null;
        try { Directory.Delete(_modelsFolder, recursive: true); } catch { }
    }

    /// <summary>Puts a file of exactly the right size where the store expects one, so IsReady is satisfied without downloading gigabytes.</summary>
    private void PlaceModel(AssistModelTier tier)
    {
        string path = Path.Combine(_modelsFolder, tier.FileName());
        using var stream = new FileStream(path, FileMode.Create);
        stream.SetLength(tier.DownloadBytes());
    }

    // ---- Sharing: the bug this whole type exists to stop -------------------

    [Fact]
    public void TheStoreIsSharedAcrossEveryCaller()
    {
        // Found while investigating "the Download button in Settings does
        // nothing": the dialog reimplemented its own file checks instead of
        // going through a shared store at all. Fixed, and pinned here so a
        // future caller (a second Settings dialog, an assistant window)
        // cannot quietly go back to making its own.
        var first = AssistModelStores.Store(AssistModelTier.Small);
        var second = AssistModelStores.Store(AssistModelTier.Small);
        Assert.Same(first, second);
    }

    [Fact]
    public void TheTwoRungsAreDifferentStores()
    {
        var small = AssistModelStores.Store(AssistModelTier.Small);
        var large = AssistModelStores.Store(AssistModelTier.Large);
        Assert.NotSame(small, large);
    }

    // ---- What is actually on disk ------------------------------------------

    [Fact]
    public void ANewStoreReflectsAnAlreadyDownloadedFile()
    {
        PlaceModel(AssistModelTier.Small);
        var store = AssistModelStores.Store(AssistModelTier.Small);
        Assert.Equal(AssistModelStoreState.Ready, store.State);
        Assert.True(store.IsReady);
    }

    [Fact]
    public void ANewStoreWithNoFileIsMissing()
    {
        var store = AssistModelStores.Store(AssistModelTier.Small);
        Assert.Equal(AssistModelStoreState.Missing, store.State);
        Assert.False(store.IsReady);
    }

    [Fact]
    public void APartFinishedFileIsNotReady()
    {
        string path = Path.Combine(_modelsFolder, AssistModelTier.Small.FileName());
        using (var stream = new FileStream(path, FileMode.Create)) { stream.SetLength(1024); }
        var store = AssistModelStores.Store(AssistModelTier.Small);
        Assert.False(store.IsReady);
    }

    [Fact]
    public void BytesOnDiskIsNullWhenNothingIsThere()
    {
        Assert.Null(AssistModelStore.BytesOnDisk(AssistModelTier.Small));
    }

    [Fact]
    public void BytesOnDiskReportsTheRealFileSize()
    {
        PlaceModel(AssistModelTier.Small);
        Assert.Equal(AssistModelTier.Small.DownloadBytes(), AssistModelStore.BytesOnDisk(AssistModelTier.Small));
    }

    // ---- Download's guards, without touching the network --------------------

    [Fact]
    public void DownloadingAnAlreadyReadyModelIsANoOp()
    {
        PlaceModel(AssistModelTier.Small);
        var store = AssistModelStores.Store(AssistModelTier.Small);
        bool changedFired = false;
        store.Changed += () => changedFired = true;

        store.Download();

        Assert.Equal(AssistModelStoreState.Ready, store.State);
        // Still notifies (a caller waiting on Changed to know a call
        // "completed" must not hang forever), but never touches the network.
        Assert.True(changedFired);
    }

    // ---- Remove --------------------------------------------------------------

    [Fact]
    public void RemoveDeletesTheFileAndReportsMissing()
    {
        PlaceModel(AssistModelTier.Small);
        var store = AssistModelStores.Store(AssistModelTier.Small);
        Assert.True(store.IsReady);

        store.Remove();

        Assert.Equal(AssistModelStoreState.Missing, store.State);
        Assert.False(store.IsReady);
        Assert.False(File.Exists(Path.Combine(_modelsFolder, AssistModelTier.Small.FileName())));
    }

    [Fact]
    public void RemovingSomethingNotThereIsHarmless()
    {
        var store = AssistModelStores.Store(AssistModelTier.Small);
        store.Remove();
        Assert.Equal(AssistModelStoreState.Missing, store.State);
    }

    [Fact]
    public void CancelWithNothingDownloadingIsHarmless()
    {
        var store = AssistModelStores.Store(AssistModelTier.Small);
        store.Cancel();
        Assert.Equal(AssistModelStoreState.Missing, store.State);
    }

    [Fact]
    public void ResetForgetsEveryStoreSoTheNextTestStartsClean()
    {
        var before = AssistModelStores.Store(AssistModelTier.Small);
        AssistModelStores.Reset();
        var after = AssistModelStores.Store(AssistModelTier.Small);
        Assert.NotSame(before, after);
    }

    // ---- Remove refuses a model an open assistant window is using ------------
    //
    // The bug: a teacher downloads a model, opens the assistant (which spawns
    // a llama-server.exe holding that file open), goes back to Settings and
    // removes it — the current reply may survive on luck (the file handle
    // Windows already opened), but the next prompt, a server restart, or a
    // second window sees the weights gone. Settings must refuse before that
    // point, not discover it later as a hang.

    [Fact]
    public void MayRemoveIsTrueWithNoAssistantWindowOpen()
    {
        PlaceModel(AssistModelTier.Small);
        var store = AssistModelStores.Store(AssistModelTier.Small);
        Assert.True(store.MayRemove());
        Assert.Null(store.ReasonItCannotBeRemoved());
    }

    [Fact]
    public void MayRemoveIsFalseWhileAnyAssistantWindowIsOpen()
    {
        PlaceModel(AssistModelTier.Small);
        var store = AssistModelStores.Store(AssistModelTier.Small);
        AssistActivity.Begin("C:\\Course", "COMP1", 1);

        Assert.False(store.MayRemove());
        Assert.NotNull(store.ReasonItCannotBeRemoved());
    }

    [Fact]
    public void TheReasonNamesTheOpenSection()
    {
        PlaceModel(AssistModelTier.Small);
        var store = AssistModelStores.Store(AssistModelTier.Small);
        AssistActivity.Begin("C:\\Course", "COMP1", 3);

        string? reason = store.ReasonItCannotBeRemoved();
        Assert.Contains("COMP1", reason);
        Assert.Contains("3", reason);
    }

    [Fact]
    public void RemoveDoesNothingWhileAnAssistantWindowIsOpen()
    {
        PlaceModel(AssistModelTier.Small);
        var store = AssistModelStores.Store(AssistModelTier.Small);
        AssistActivity.Begin("C:\\Course", "COMP1", 1);

        store.Remove();

        Assert.True(store.IsReady);
        Assert.Equal(AssistModelStoreState.Ready, store.State);
        Assert.True(File.Exists(Path.Combine(_modelsFolder, AssistModelTier.Small.FileName())));
    }

    [Fact]
    public void RemoveWorksAgainOnceTheWindowCloses()
    {
        PlaceModel(AssistModelTier.Small);
        var store = AssistModelStores.Store(AssistModelTier.Small);
        AssistActivity.Begin("C:\\Course", "COMP1", 1);
        store.Remove();
        Assert.True(store.IsReady);

        AssistActivity.End("C:\\Course", "COMP1", 1);
        store.Remove();

        Assert.False(store.IsReady);
    }

    [Fact]
    public void AnAssistantOpenForOneRungStillBlocksRemovingTheOtherRung()
    {
        // Mirrors the mac: the guard is about ANY open assistant, not about
        // whether that window happens to be using this particular rung —
        // working out which file is genuinely mapped into the running
        // engine is state this app does not keep.
        PlaceModel(AssistModelTier.Large);
        var store = AssistModelStores.Store(AssistModelTier.Large);
        AssistActivity.Begin("C:\\Course", "COMP1", 1);

        Assert.False(store.MayRemove());
    }

    [Fact]
    public void MayRemoveIsFalseWithNothingDownloadedRegardlessOfActivity()
    {
        // Nothing to remove is its own reason to say no — but the disabled
        // button should not carry a confusing "close the assistant" message
        // when there is no file to protect in the first place.
        var store = AssistModelStores.Store(AssistModelTier.Small);
        AssistActivity.Begin("C:\\Course", "COMP1", 1);

        Assert.False(store.MayRemove());
        Assert.Null(store.ReasonItCannotBeRemoved());
    }
}
