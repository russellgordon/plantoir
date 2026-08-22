using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>What the store is doing, in words a teacher can read. Mirrors the mac's `AssistModelStore.State`.</summary>
public enum AssistModelStoreState
{
    Missing,
    Downloading,
    Ready,
    Failed,
}

/// <summary>
/// Where the local model lives on this PC, and how it gets here.
///
/// The weights are NOT bundled with the app — a 1–2.5 GB model in every
/// install would have to be downloaded by every teacher on every update,
/// landing on PCs whose teacher never opens the assistant. It is fetched
/// once, into <c>%LOCALAPPDATA%\Plantoir\models</c>, and stays there across
/// app updates. Mirrors the mac's `AssistModelStore.swift`.
/// </summary>
public sealed class AssistModelStore
{
    public AssistModelTier Tier { get; }

    public AssistModelStoreState State { get; private set; }

    /// <summary>How far a download has got — 0 outside <see cref="AssistModelStoreState.Downloading"/>.</summary>
    public double FractionComplete { get; private set; }
    public long ReceivedBytes { get; private set; }
    public long TotalBytes { get; private set; }

    /// <summary>Set only in <see cref="AssistModelStoreState.Failed"/>.</summary>
    public string? FailureReason { get; private set; }

    /// <summary>Raised after every state change, so a view can redraw without polling.</summary>
    public event Action? Changed;

    private readonly LocalModel _model;
    private CancellationTokenSource? _cancellation;

    public AssistModelStore(AssistModelTier tier)
    {
        Tier = tier;
        _model = new LocalModel(tier);
        State = _model.IsInstalled() ? AssistModelStoreState.Ready : AssistModelStoreState.Missing;
    }

    /// <summary>Is the model already here, and the right size?</summary>
    public bool IsReady => _model.IsInstalled();

    /// <summary>
    /// Fetch the weights, reporting progress. Does nothing when they are
    /// already here, or a download is already running — the second call is
    /// what a re-opened Settings window or a second assistant window
    /// produces, and it must find the SAME download in flight, not start a
    /// competing one onto the same file.
    /// </summary>
    public void Download()
    {
        if (IsReady)
        {
            State = AssistModelStoreState.Ready;
            Notify();
            return;
        }
        if (State == AssistModelStoreState.Downloading) return;

        _cancellation = new CancellationTokenSource();
        State = AssistModelStoreState.Downloading;
        FractionComplete = 0;
        ReceivedBytes = 0;
        TotalBytes = Tier.DownloadBytes();
        FailureReason = null;
        Notify();

        ActivityTrail.Note(ActivityTrail.Event.AssistantModelDownloadStarted,
            $"started downloading {Tier.DisplayName()} — {Tier.DownloadDescription()}");

        var progress = new Progress<LocalModel.Fetching>(state =>
        {
            ReceivedBytes = state.Bytes;
            TotalBytes = state.Known ? state.Total : Tier.DownloadBytes();
            FractionComplete = state.Known ? state.Percent / 100.0 : 0;
            Notify();
        });

        var token = _cancellation.Token;
        _ = RunDownload(progress, token);
    }

    private async Task RunDownload(IProgress<LocalModel.Fetching> progress, CancellationToken token)
    {
        // LocalModel.Install catches everything internally, cancellation
        // included, and answers false rather than throwing — so there is
        // nothing here to catch. token.IsCancellationRequested is the only
        // way to tell "the teacher stopped it" (Cancel() already handled
        // the state) apart from "it genuinely failed" (report why).
        bool installed = await _model.Install(progress, token).ConfigureAwait(false);
        if (token.IsCancellationRequested) return;

        if (installed)
        {
            State = AssistModelStoreState.Ready;
            ActivityTrail.Note(ActivityTrail.Event.AssistantModelDownloaded,
                $"finished downloading {Tier.DisplayName()} — {Tier.DownloadDescription()}");
        }
        else
        {
            FailureReason = "The download didn’t finish. Check the network and try again.";
            State = AssistModelStoreState.Failed;
            ActivityTrail.Note(ActivityTrail.Event.AssistantModelDownloadFailed,
                $"could not download {Tier.DisplayName()} — {FailureReason}");
        }
        Notify();
    }

    /// <summary>Stop a download in flight — the teacher closed the window, or pressed Stop.</summary>
    public void Cancel()
    {
        if (State != AssistModelStoreState.Downloading) return;
        _cancellation?.Cancel();
        _cancellation = null;
        State = AssistModelStoreState.Missing;
        ActivityTrail.Note(ActivityTrail.Event.AssistantModelDownloadStopped,
            $"stopped downloading {Tier.DisplayName()}");
        Notify();
    }

    /// <summary>
    /// Delete the weights to get the space back. Deliberately does no
    /// "is it safe" check — whether it is safe to remove is a question
    /// about which windows are open, which this type cannot see.
    /// </summary>
    public void Remove()
    {
        Cancel();
        try
        {
            string path = LocalModel.GetModelPath(Tier);
            if (File.Exists(path)) File.Delete(path);
            State = AssistModelStoreState.Missing;
            ActivityTrail.Note(ActivityTrail.Event.AssistantModelRemoved,
                $"removed {Tier.DisplayName()} — {Tier.DownloadDescription()} freed");
        }
        catch (Exception error)
        {
            FailureReason = $"Could not remove it: {error.Message}";
            State = AssistModelStoreState.Failed;
        }
        Notify();
    }

    /// <summary>What this tier takes on disk right now, or null when it is not here.</summary>
    public static long? BytesOnDisk(AssistModelTier tier)
    {
        string path = LocalModel.GetModelPath(tier);
        if (!File.Exists(path)) return null;
        return new FileInfo(path).Length;
    }

    private void Notify() => Changed?.Invoke();
}

/// <summary>
/// One store per rung, for the whole app.
///
/// The bug this exists to stop is a double download: a teacher who presses
/// Download in Settings and then opens the assistant (or vice versa) while
/// it is running must find the SAME download in progress, not a second one
/// racing it onto the same file — the failure mode this project has already
/// paid for once on the mac side. Mirrors `AssistModelStores.swift`.
/// </summary>
public static class AssistModelStores
{
    private static readonly System.Collections.Generic.Dictionary<AssistModelTier, AssistModelStore> Stores = new();
    private static readonly object Gate = new();

    /// <summary>The one store for this rung, made on first use.</summary>
    public static AssistModelStore Store(AssistModelTier tier)
    {
        lock (Gate)
        {
            if (Stores.TryGetValue(tier, out var existing)) return existing;
            var made = new AssistModelStore(tier);
            Stores[tier] = made;
            return made;
        }
    }

    /// <summary>Forget everything, for tests — process-wide state that outlives a test answers the next test's questions.</summary>
    public static void Reset()
    {
        lock (Gate)
        {
            foreach (var store in Stores.Values) store.Cancel();
            Stores.Clear();
        }
    }
}
