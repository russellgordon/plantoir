using System.ComponentModel;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Core.Scripting;

/// <summary>
/// A section's deploy, owned by the APP rather than by the view showing the
/// section (#728, the mac's <c>SectionDeployRun</c>, #706). The section view is
/// built afresh for every selection, so a deploy runner that was the view's own
/// field was left running unseen when the teacher clicked away, and the view
/// that came back had a blank runner with Deploy enabled — a press then met
/// the launcher's "already being deployed" refusal, or, during the build leg,
/// started a second build that killed the first (measured on the mac, #706).
/// </summary>
/// <remarks>
/// <para><b>One per <see cref="SectionKey"/>, for the life of the app, never
/// replaced</b> (<see cref="SectionRuns"/>): the running deploy task holds it,
/// and every view showing the section binds to the same object. It lives in
/// memory only.</para>
///
/// <para><b>Threading.</b> Every write is made on the interface thread — the
/// deploy itself runs there (<c>SectionDetailView.DeployAsync</c>), and every
/// window of the app is created on that one thread — so notifications are
/// raised synchronously. The runner is made with the interface thread's
/// context by the view that first asks (<see cref="SectionRuns.Deploy"/>);
/// callers on any other thread only <see cref="SectionRuns.Find"/>.</para>
///
/// <para><b>What it holds that the view used to.</b> The runner; whether a
/// deploy is being prepared (press → runner started) or the question about
/// classes dated later is up; the folder the deploy's work belongs to (what
/// Cancel aims at); and the deploy's own work claims — its build and publish
/// leases and its <see cref="CourseActivity"/> record. On Windows the build
/// lease used to be handed to the VIEW's preview build claim, which the view
/// gives back when it is taken off screen, so leaving a section mid-deploy
/// told every other program the course was free while the deploy was still
/// building it (found reading for #728; the mac's claims are function-local).</para>
///
/// <para><b>What a returning view shows</b> (<c>shared-rules.json</c> →
/// <c>returningToASectionMidDeploy</c>): the run while it is under way; a
/// FINISHED run only until one view has displayed how it ended, and never over
/// a preview of the section that started after the deploy did
/// (<see cref="IsShown"/>; the mac's implementation review M1).</para>
/// </remarks>
public sealed class SectionDeployRun : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    public SectionDeployRun(SectionKey key, SynchronizationContext? uiContext)
    {
        Key = key;
        Runner = new MultiDestinationDeployRunner(uiContext);
    }

    public SectionKey Key { get; }

    /// <summary>The section's deploy runner — the same object for every view, every time.</summary>
    public MultiDestinationDeployRunner Runner { get; }

    private bool _isPreparing;
    /// <summary>Between the press and <see cref="MultiDestinationDeployRunner.RunAsync"/> taking over (row 318a).</summary>
    public bool IsPreparing
    {
        get => _isPreparing;
        set { if (_isPreparing == value) return; _isPreparing = value; Notify(nameof(IsPreparing)); }
    }

    private bool _isAsking;
    /// <summary>
    /// The question about classes dated after the next class is up for this
    /// section in SOME window. On the run, not the view: a second window on
    /// the same section could otherwise put a second question, back the
    /// course up and hide classes, and only then be refused — a refusal after
    /// a change, which <c>classesDatedLater.order</c> forbids (#728 plan review).
    /// </summary>
    public bool IsAsking
    {
        get => _isAsking;
        set { if (_isAsking == value) return; _isAsking = value; Notify(nameof(IsAsking)); }
    }

    /// <summary>The working folder this deploy's work belongs to, noted once its preview stop is over; what Cancel aims at.</summary>
    public string? Folder { get; set; }

    /// <summary>Running, or being prepared: this run has a deploy on its way.</summary>
    public bool IsUnderWayHere => IsPreparing || Runner.IsRunning;

    // ---- The deploy's claims --------------------------------------------

    private readonly List<IDisposable> _claims = new();

    /// <summary>The deploy's own claims, held for its whole life, whoever is looking.</summary>
    public void Hold(params IDisposable?[] claims)
    {
        lock (_claims)
            foreach (var claim in claims)
                if (claim is not null) _claims.Add(claim);
    }

    /// <summary>Gives every claim back. Safe to call twice.</summary>
    public void EndPublish()
    {
        List<IDisposable> giving;
        lock (_claims)
        {
            giving = _claims.ToList();
            _claims.Clear();
        }
        foreach (var claim in giving) claim.Dispose();
    }

    internal int ClaimsHeld { get { lock (_claims) return _claims.Count; } }

    // ---- How it ended, handed over once ----------------------------------

    /// <summary>What the deploy left for the view that shows its ending.</summary>
    public sealed record Ending(int Number, IReadOnlyList<SiteHealthFinding> Findings, LinksChecklistMarker? LinksMarker);

    private Ending? _waiting;

    /// <summary>How many deploys of this section have ended, in this app's life.</summary>
    public int Endings { get; private set; }

    /// <summary>The last ending a view put on screen.</summary>
    public int? EndingShown { get; private set; }

    /// <summary>When a preview of this section last started, from any window (UTC, as the runners' StartedAt).</summary>
    public DateTime? PreviewLastStartedAt { get; private set; }

    /// <summary>
    /// The deploy has ended: what it found is held for ONE view to take, and
    /// the ending is announced. Called AFTER <see cref="EndPublish"/>, so a
    /// view redrawing on the announcement already sees the section free —
    /// the runner's own IsRunning=false arrives before the publish record ends.
    /// </summary>
    public void NoteEnded(IReadOnlyList<SiteHealthFinding> findings, LinksChecklistMarker? linksMarker)
    {
        Endings++;
        _waiting = new Ending(Endings, findings, linksMarker);
        Notify(nameof(Endings));
    }

    /// <summary>Read-and-clear: exactly one view raises what the deploy found.</summary>
    public Ending? TakeEnding()
    {
        var taking = _waiting;
        _waiting = null;
        return taking;
    }

    /// <summary>A view has put the current ending on screen.</summary>
    public void NoteEndingShown()
    {
        if (Endings > 0) EndingShown = Endings;
    }

    /// <summary>
    /// Asked by a view as it APPEARS, before it takes anything: the current
    /// ending, when some view has already shown it — so this view hides it.
    /// </summary>
    public int? EndingToHideOnAppearing() =>
        !IsUnderWayHere && Endings > 0 && EndingShown == Endings ? Endings : null;

    public void NotePreviewStarted(DateTime startedAtUtc)
    {
        PreviewLastStartedAt = startedAtUtc;
        Notify(nameof(PreviewLastStartedAt));
    }

    /// <summary>
    /// Whether a view gives its console to this run: always while it is under
    /// way; once it has ended, only when there is an ending this view did not
    /// hide on appearing (<paramref name="hidingEnding"/>) and no preview of
    /// the section started after the deploy did. <paramref name="previewStartedAt"/>
    /// is the view's own preview runner's start; a view that came back has
    /// none, and then the section's last preview start decides — or an 8 am
    /// deploy wins over an 11 am preview (#706 implementation review, M1).
    /// </summary>
    public bool IsShown(int? hidingEnding, DateTime? previewStartedAt = null)
    {
        if (IsUnderWayHere) return true;
        if (Endings == 0 || hidingEnding == Endings) return false;
        DateTime? preview = previewStartedAt ?? PreviewLastStartedAt;
        if (preview is { } previewAt && Runner.StartedAt is { } deployAt && previewAt > deployAt) return false;
        return true;
    }

    /// <summary>
    /// Whether THIS app has a deploy of the section on its way — the run
    /// preparing, running or asking its question, or the in-process publish
    /// record any deploy in this app writes. The button, Section ▸ Deploy…
    /// and its key, the deploy's own first check, the assistant's press and
    /// the pre-check before the question about classes dated later all ask
    /// this (the mac's <c>deployIsUnderWay</c>). Another PROGRAM's deploy is
    /// not here: <c>returningToASectionMidDeploy.knownLimits</c>.
    /// </summary>
    public static bool UnderWay(SectionDeployRun? run, string? folder, string course, int section)
    {
        if (run is not null && (run.IsUnderWayHere || run.IsAsking)) return true;
        return folder is not null && CourseActivity.IsPublishingSection(folder, course, section);
    }

    private void Notify(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>
/// The app's deploy runs, one per section (<see cref="SectionDeployRun"/>).
/// Only a section VIEW creates one, on the interface thread, so the runner is
/// bound to that thread; everything else finds.
/// </summary>
public static class SectionRuns
{
    private static readonly PerSectionStore<SectionDeployRun> s_runs = new();

    /// <summary>The section's run, made the first time with the calling thread's context.</summary>
    public static SectionDeployRun Deploy(string? folder, string course, int section)
    {
        var context = SynchronizationContext.Current;
        return s_runs.GetOrCreate(SectionKey.For(folder, course, section), key => new SectionDeployRun(key, context));
    }

    /// <summary>The section's run if any view has made one; never creates.</summary>
    public static SectionDeployRun? Find(string? folder, string course, int section) =>
        s_runs.Find(SectionKey.For(folder, course, section));

    /// <summary>For tests only.</summary>
    internal static void Reset() => s_runs.Reset();
}
