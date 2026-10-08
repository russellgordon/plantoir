using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NetSparkleUpdater;
using NetSparkleUpdater.Enums;
using NetSparkleUpdater.Interfaces;
using NetSparkleUpdater.SignatureVerifiers;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// What the update engine needs from the window: the teacher's words and
/// answers. Implemented in the WinUI app with ContentDialogs; every sentence
/// comes from <see cref="UpdateWording"/> (rule 1).
/// </summary>
public interface IUpdatePrompts
{
    /// <summary>
    /// The offer: Install and Reopen, Not Now, or Skip This Version — or, when
    /// <paramref name="important"/> (#453), Install and Reopen alone. Answers
    /// <see cref="UpdateAnswer.NotShown"/> when no window could show it (#465).
    /// </summary>
    Task<UpdateAnswer> OfferAsync(string version, string? notes, bool important);
    Task ShowUpToDateAsync();
    Task ShowCouldNotCheckAsync();
    Task ShowHeldAsync(string work, bool onceInstalling);
    Task ShowNeedsAdministratorAsync();
    /// <summary>Start the installer and quit the app — the window's own exit path.</summary>
    void QuitForInstall(string installerPath, string arguments);
}

/// <summary>
/// The teacher's answer to an offer. <see cref="NotShown"/> is NOT an answer
/// (#465): no window was there to show it in, or another dialog was in front,
/// so nothing is written on the trail and the check is tried again soon.
/// </summary>
public enum UpdateAnswer { Install, NotNow, Skip, NotShown }

/// <summary>
/// The update engine (#337): NetSparkleUpdater's CORE — no UI factory, ours
/// are the only windows — behind <see cref="AppUpdates"/>' rules.
///
/// <list type="bullet">
/// <item><b>The feed is read from ONE place</b>, <see cref="AppUpdates.ConfiguredFeed"/>,
/// set since v1.4.2 (with its key). An EMPTY feed still means no
/// <see cref="SparkleUpdater"/> is ever constructed and nothing is fetched
/// (<c>AppUpdaterTests.AnEmptyFeedNeverReachesTheNetwork</c>), which is what a
/// test or a build without one gets.</item>
/// <item><b>Ed25519, Strict</b>: an unsigned feed or download is refused.</item>
/// <item><b>Once a day</b> (<see cref="AppUpdates.CheckEverySeconds"/>), plus the
/// menu item. It asks first and never downloads before the teacher's Install.</item>
/// <item><b>Install is gated at the moment of install</b>
/// (<see cref="AppUpdates.EvaluateForInstall"/>, fresh snapshot), and a held
/// install goes ahead by itself when the work ends.</item>
/// </list>
/// </summary>
public sealed class AppUpdater : IDisposable
{
    private readonly string _feed;
    private readonly string _publicKey;
    private readonly IUpdatePrompts _prompts;
    private readonly Func<AppUpdates.Snapshot> _snapshot;
    private readonly Func<IReadOnlyList<int>> _assistantServers;
    private readonly Func<string, string> _theQuitQuestionsWords;
    private readonly bool _perUser;
    private readonly string _running;
    private readonly Func<IAppCastDataDownloader?> _feedReader;
    private readonly HashSet<string> _foundThisLaunch = new();
    private SparkleUpdater? _sparkle;
    private Timer? _daily;
    private bool _stoppedNotedThisLaunch;
    private string? _skipped;
    private Action<string?>? _rememberSkip;
    private int _dailyCheckUnderWay;
    private TimeSpan _retryAfter = FirstRetry;

    /// <summary>How soon an offer nobody saw is tried again; doubled each time, up to the hourly look (#465).</summary>
    internal static readonly TimeSpan FirstRetry = TimeSpan.FromMinutes(1);
    internal static readonly TimeSpan HourlyLook = TimeSpan.FromHours(1);

    /// <summary>When the last offer nobody saw asked to be tried again — what the tests read.</summary>
    internal TimeSpan? LastRetryScheduled { get; private set; }

    /// <summary>The developer's diagnostic log (startup.log): never the trail.</summary>
    public Action<string>? Diagnostic { get; set; }

    /// <summary>How long a held install waits before asking again (the scheduled run's own fifteen seconds).</summary>
    internal TimeSpan LookAgainEvery { get; set; } = ScheduledRun.LookAgainEvery;

    /// <summary>The verifier's mode, for the test that pins Strict (an unsigned feed is refused).</summary>
    internal SecurityMode VerifierModeForTests => ((Ed25519Checker)Sparkle().SignatureVerifier).SecurityMode;

    /// <summary>For tests: an installer already downloaded.</summary>
    internal void PreparedForTests(string installerPath, string version)
    {
        _installerPath = installerPath;
        PreparedVersion = version;
        Prepared = AppUpdates.Prepared.ReadyToInstall;
    }

    /// <summary>The prepared update, if any (atQuit).</summary>
    public AppUpdates.Prepared Prepared { get; private set; } = AppUpdates.Prepared.None;
    public string? PreparedVersion { get; private set; }
    private string? _installerPath;

    /// <summary>How many times a feed was fetched — what the empty-feed test reads.</summary>
    public int FeedFetches { get; private set; }

    /// <summary>Whether this copy will ever check: a feed is set and the copy is per-user.</summary>
    public bool IsActive => !string.IsNullOrWhiteSpace(_feed);

    /// <summary>The executable a refused update reopens (ruling 12).</summary>
    public string? ReturnTo { get; set; } = Environment.ProcessPath;

    /// <summary>Whether NetSparkle was ever constructed (never for an empty feed).</summary>
    public bool HasEngine => _sparkle is not null;

    public AppUpdater(string feed, string publicKey, IUpdatePrompts prompts,
                      Func<AppUpdates.Snapshot> snapshot, Func<IReadOnlyList<int>> assistantServers,
                      string runningVersion, bool perUserInstall, string? skippedVersion = null,
                      Action<string?>? rememberSkip = null,
                      Func<string, string>? theQuitQuestionsWords = null,
                      Func<IAppCastDataDownloader?>? feedReaderForTests = null)
    {
        _feed = feed ?? "";
        _publicKey = publicKey ?? "";
        _prompts = prompts;
        _snapshot = snapshot;
        _assistantServers = assistantServers;
        _running = runningVersion;
        _perUser = perUserInstall;
        _skipped = skippedVersion;
        _rememberSkip = rememberSkip;
        _theQuitQuestionsWords = theQuitQuestionsWords ?? (_ => "a deploy");
        _feedReader = feedReaderForTests ?? (() => null);
    }

    /// <summary>
    /// The daily check. Nothing at all when no feed is set. Called by the app
    /// once its first window is up (#465), never before: the offer needs a
    /// window, and the first launch after an update spends about two minutes
    /// copying its tools before it has one.
    /// </summary>
    public void Start()
    {
        if (!IsActive || _daily is not null) return;
        // On the WALL CLOCK (ruling 10): look every hour whether a day has
        // passed since the last daily check (kept in settings), so a laptop that
        // sleeps at night and is never relaunched still checks once a day.
        // A process-time timer of 86400 s drifted by every hour spent asleep.
        _daily = new Timer(_ => { if (DailyCheckIsDue(DateTime.UtcNow)) _ = DailyCheckAsync(); }, null,
                           FirstRetry, HourlyLook);
    }

    /// <summary>
    /// One daily check at a time (#465). Without this, an offer left open for
    /// over an hour met the next hourly look, which found the day not yet done,
    /// found its own offer in front, and asked to be tried again, every minute
    /// for as long as the offer stayed open.
    /// </summary>
    internal async Task DailyCheckAsync()
    {
        if (Interlocked.CompareExchange(ref _dailyCheckUnderWay, 1, 0) != 0) return;
        try { await CheckAsync(teacherAsked: false); }
        finally { Volatile.Write(ref _dailyCheckUnderWay, 0); }
    }

    private Func<DateTime?> _lastDailyCheck = () => null;
    private Action<DateTime> _rememberDailyCheck = _ => { };

    /// <summary>A day by the wall clock since the last daily check; records the new one when due.</summary>
    internal bool DailyCheckIsDue(DateTime nowUtc)
    {
        // Stamped by CheckAsync only when the check got an ANSWER (ruling 13):
        // an offline morning does not count as the day's check.
        return !(_lastDailyCheck() is { } last && nowUtc - last < TimeSpan.FromSeconds(AppUpdates.CheckEverySeconds));
    }

    /// <summary>Where the last daily check is kept (the app passes its settings).</summary>
    public AppUpdater RememberingDailyChecksIn(Func<DateTime?> read, Action<DateTime> write)
    {
        _lastDailyCheck = read;
        _rememberDailyCheck = write;
        return this;
    }

    private SparkleUpdater Sparkle()
    {
        if (_sparkle is not null) return _sparkle;
        var sparkle = new SparkleUpdater(_feed, new Ed25519Checker(SecurityMode.Strict, _publicKey, null, false, 0))
        {
            UIFactory = null,
            UserInteractionMode = UserInteractionMode.DownloadNoInstall,
        };
        if (_feedReader() is { } reader) sparkle.AppCastDataDownloader = new CountingReader(reader, () => FeedFetches++);
        sparkle.DownloadFinished += (item, path) => _ = DownloadedAsync(item, path);
        sparkle.DownloadHadError += (item, _, error) => NoteStopped(item?.Version, "the download failed", error.Message);
        sparkle.DownloadedFileIsCorrupt += (item, _) => NoteStopped(item?.Version, "the download was not signed as expected", null);
        _sparkle = sparkle;
        return sparkle;
    }

    /// <summary>
    /// Look for a new version. <paramref name="teacherAsked"/>: Check for
    /// Updates… (says "up to date" and writes it on the trail); otherwise the
    /// daily check, which says nothing unless something was found.
    /// </summary>
    public async Task CheckAsync(bool teacherAsked)
    {
        if (!IsActive) return;
        if (!_perUser)
        {
            if (teacherAsked) await _prompts.ShowNeedsAdministratorAsync();
            NoteStopped(null, "Plantoir is installed for everyone on this PC, where it cannot update itself", null);
            return;
        }
        UpdateInfo info;
        try { info = teacherAsked ? await Sparkle().CheckForUpdatesAtUserRequest(true) : await Sparkle().CheckForUpdatesQuietly(true); }
        catch (Exception error)
        {
            NoteStopped(null, "could not reach plantoir.app", error.Message, daily: !teacherAsked);
            if (teacherAsked) await _prompts.ShowCouldNotCheckAsync();
            return;
        }

        // The day is done when the check got an answer (ruling 13) AND, when
        // there was something to offer, the offer was SHOWN (#465): an offer
        // nobody saw is not the day's check.
        if (!teacherAsked && info.Status is UpdateStatus.UpdateNotAvailable or UpdateStatus.UserSkipped)
            _rememberDailyCheck(DateTime.UtcNow);
        // A check that got an answer and found nothing to offer ends any run of
        // unseen offers: the next one waits a minute again, not an hour (review L5).
        if (info.Status is UpdateStatus.UpdateNotAvailable or UpdateStatus.UserSkipped) _retryAfter = FirstRetry;
        var newer = info.Updates?.OrderByDescending(u => u).ToList() ?? new List<AppCastItem>();
        var newest = newer.FirstOrDefault();
        switch (info.Status)
        {
            case UpdateStatus.UpdateAvailable when newest is not null:
                var offer = AppUpdates.DecideOffer(
                    newer.Select(u => (u.Version ?? "", u.IsCriticalUpdate)).ToList(), _skipped, teacherAsked);
                if (!offer.Show)
                {
                    if (!teacherAsked) _rememberDailyCheck(DateTime.UtcNow);
                    return;
                }
                if (_foundThisLaunch.Add(newest.Version ?? ""))
                    ActivityTrail.Note(ActivityTrail.Event.UpdateFound,
                        $"found {newest.Version}, running {_running}; {(teacherAsked ? "the teacher asked" : "the daily check")}" +
                        (offer.Important ? "; marked important" : ""));
                var answer = await OfferAsync(newest, newer, offer.Important);
                if (answer == UpdateAnswer.NotShown)
                {
                    if (teacherAsked) Diagnostic?.Invoke($"update offer for {newest.Version} could not be shown (no window, or another dialog in front)");
                    else TryAgainSoon(newest.Version);
                }
                else
                {
                    // SHOWN, whoever asked: the day's check is done. A shown
                    // Check for Updates… counts too, or a daily retry still
                    // pending from an unseen offer would put the same offer
                    // back minutes after the teacher answered it (review L1).
                    _retryAfter = FirstRetry;
                    _rememberDailyCheck(DateTime.UtcNow);
                }
                break;
            case UpdateStatus.UpdateNotAvailable:
            case UpdateStatus.UserSkipped:
                if (teacherAsked)
                {
                    ActivityTrail.Note(ActivityTrail.Event.UpdateCheckFoundNothingNew, $"running {_running}");
                    await _prompts.ShowUpToDateAsync();
                }
                break;
            default:
                // A 404 before the first Windows feed exists lands here: nothing
                // new, no dialog, for the daily check.
                NoteStopped(null, "could not reach plantoir.app", info.Status.ToString(), daily: !teacherAsked);
                if (teacherAsked) await _prompts.ShowCouldNotCheckAsync();
                break;
        }
    }

    /// <summary>
    /// An offer nobody saw (#465): no answer is written, the day is not done,
    /// and the daily check looks again in a minute, then two, four, eight… up
    /// to the hourly look it keeps anyway. Backing off, because each look
    /// fetches the feed again, and a dialog can be left open for hours.
    /// </summary>
    private void TryAgainSoon(string? version)
    {
        var after = _retryAfter;
        LastRetryScheduled = after;
        _retryAfter = after + after > HourlyLook ? HourlyLook : after + after;
        Diagnostic?.Invoke($"update offer for {version} could not be shown; looking again in {after.TotalMinutes:0} min");
        try { _daily?.Change(after, HourlyLook); } catch (ObjectDisposedException) { }
    }

    private async Task<UpdateAnswer> OfferAsync(AppCastItem item, IReadOnlyList<AppCastItem> newerNewestFirst, bool important)
    {
        // Every newer release's notes, not only the newest's (appUpdates.notes, #428 item 2).
        string notes = AppUpdates.NotesFor(newerNewestFirst.Select(u => (u.Version, u.Description)));
        var answer = await _prompts.OfferAsync(item.Version ?? "", notes, important);
        // An important offer has no Skip button, so a Skip cannot come back
        // from it; read as "not now" if one ever did, never remembered.
        if (important && answer == UpdateAnswer.Skip) answer = UpdateAnswer.NotNow;
        if (answer == UpdateAnswer.NotShown) return answer;
        ActivityTrail.Note(ActivityTrail.Event.UpdateAnswered, $"{item.Version}: " + answer switch
        {
            UpdateAnswer.Install => "install",
            UpdateAnswer.Skip => "skip this version",
            _ => "not now",
        });
        switch (answer)
        {
            case UpdateAnswer.Install:
                PreparedVersion = item.Version;
                await Sparkle().InitAndBeginDownload(item);
                break;
            case UpdateAnswer.Skip:
                _skipped = item.Version;
                _rememberSkip?.Invoke(item.Version);
                break;
        }
        return answer;
    }

    private async Task DownloadedAsync(AppCastItem item, string path)
    {
        _installerPath = path;
        PreparedVersion = item.Version;
        Prepared = AppUpdates.Prepared.ReadyToInstall;
        await InstallWhenFreeAsync(askedAgain: false);
    }

    /// <summary>
    /// The install gate, asked FRESH at the moment of install (ruling 2). Held:
    /// say so once, then look again every fifteen seconds and install by itself
    /// when the work ends (whenHeldWorkEnds: restartStraightAway).
    /// </summary>
    public async Task InstallWhenFreeAsync(bool askedAgain)
    {
        if (_installerPath is null) return;
        var hold = AppUpdates.EvaluateForInstall(_snapshot(), _assistantServers());
        if (hold.Held)
        {
            string work = UpdateWording.Work(hold, _theQuitQuestionsWords(""));
            if (!askedAgain)
            {
                Prepared = AppUpdates.Prepared.HeldForWork;
                ActivityTrail.Note(ActivityTrail.Event.UpdateHeldWhileWorkIsUnderWay,
                    $"{UpdateWording.HeldTitle.Replace("{work}", work)} ({PreparedVersion} waiting)");
                await _prompts.ShowHeldAsync(work, onceInstalling: false);
            }
            await Task.Delay(LookAgainEvery);
            await InstallWhenFreeAsync(askedAgain: true);
            return;
        }
        ActivityTrail.Note(ActivityTrail.Event.UpdateInstalling,
            $"from {_running} to {PreparedVersion}, " + (askedAgain
                ? "once the work it was held for had finished, and opening again"
                : "straight away, and opening again"));
        _prompts.QuitForInstall(_installerPath, AppUpdates.InstallerArguments(relaunch: true, ReturnTo));
    }

    /// <summary>
    /// The quit path (atQuit): never refuses. With work under way the prepared
    /// update is set aside and its installer deleted; with none it installs as
    /// Plantoir quits, without opening again. Returns the installer to start, or null.
    /// </summary>
    public (string Path, string Arguments)? AtQuit(bool workUnderWay, string whatIsUnderWay)
    {
        var decision = AppUpdates.DecideAtQuit(Prepared, workUnderWay);
        if (decision == AppUpdates.AtQuit.SetAside)
        {
            ActivityTrail.Note(ActivityTrail.Event.UpdateSetAside, $"{PreparedVersion} set aside: {whatIsUnderWay} was under way when Plantoir quit");
            try { if (_installerPath is not null) File.Delete(_installerPath); } catch (Exception) { }
            Prepared = AppUpdates.Prepared.None;
            return null;
        }
        if (decision == AppUpdates.AtQuit.InstallsAsItQuits && _installerPath is not null)
        {
            ActivityTrail.Note(ActivityTrail.Event.UpdateInstalling,
                $"from {_running} to {PreparedVersion}, as Plantoir quits, without opening again" +
                (Prepared == AppUpdates.Prepared.PostponedAtInstall && workUnderWay ? $"; {whatIsUnderWay} was still going on" : ""));
            return (_installerPath, AppUpdates.InstallerArguments(relaunch: false, ReturnTo));
        }
        return null;
    }

    /// <summary>
    /// The quit, decided by the SAME gate as the install (ruling 7): anything in
    /// mayNotInstallWhile — a scheduled publish, another program's build or
    /// publish, any running plantoir-mcp — not only this app's own work. A held
    /// update must never install on the way out over the work it was held for.
    /// </summary>
    public (string Path, string Arguments)? AtQuitGated()
    {
        var hold = AppUpdates.EvaluateForInstall(_snapshot(), _assistantServers());
        return AtQuit(hold.Held, hold.Held ? UpdateWording.Work(hold, _theQuitQuestionsWords("")) : "");
    }

    private void NoteStopped(string? version, string category, string? detail, bool daily = false)
    {
        if (daily && _stoppedNotedThisLaunch) return;
        if (daily) _stoppedNotedThisLaunch = true;
        ActivityTrail.Note(ActivityTrail.Event.UpdateStopped,
            $"{version ?? "a new version"}: {category}" + (string.IsNullOrEmpty(detail) ? "" : $" [{detail}]"));
    }

    public void Dispose()
    {
        _daily?.Dispose();
        _sparkle?.Dispose();
    }

    /// <summary>Counts each fetch of the feed — the empty-feed test's evidence.</summary>
    private sealed class CountingReader : IAppCastDataDownloader
    {
        private readonly IAppCastDataDownloader _inner;
        private readonly Action _counted;
        public CountingReader(IAppCastDataDownloader inner, Action counted) { _inner = inner; _counted = counted; }
        public string DownloadAndGetAppCastData(string url) { _counted(); return _inner.DownloadAndGetAppCastData(url); }
        public Task<string> DownloadAndGetAppCastDataAsync(string url) { _counted(); return _inner.DownloadAndGetAppCastDataAsync(url); }
        public System.Text.Encoding GetAppCastEncoding() => _inner.GetAppCastEncoding();
    }
}
