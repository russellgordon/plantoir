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
    /// <summary>The offer: Install and Reopen, Not Now, or Skip This Version.</summary>
    Task<UpdateAnswer> OfferAsync(string version, string? notes);
    Task ShowUpToDateAsync();
    Task ShowCouldNotCheckAsync();
    Task ShowHeldAsync(string work, bool onceInstalling);
    Task ShowNeedsAdministratorAsync();
    /// <summary>Start the installer and quit the app — the window's own exit path.</summary>
    void QuitForInstall(string installerPath, string arguments);
}

public enum UpdateAnswer { Install, NotNow, Skip }

/// <summary>
/// The update engine (#337): NetSparkleUpdater's CORE — no UI factory, ours
/// are the only windows — behind <see cref="AppUpdates"/>' rules.
///
/// <list type="bullet">
/// <item><b>The feed is read from ONE place</b>, <see cref="AppUpdates.ConfiguredFeed"/>,
/// which is EMPTY until a release sets it. Empty means no
/// <see cref="SparkleUpdater"/> is ever constructed and nothing is fetched
/// (<c>AppUpdaterTests.AnEmptyFeedNeverReachesTheNetwork</c>).</item>
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

    /// <summary>Whether NetSparkle was ever constructed (never, while the feed is empty).</summary>
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

    /// <summary>The daily check. Nothing at all when no feed is set.</summary>
    public void Start()
    {
        if (!IsActive) return;
        // On the WALL CLOCK (ruling 10): look every hour whether a day has
        // passed since the last daily check (kept in settings), so a laptop that
        // sleeps at night and is never relaunched still checks once a day.
        // A process-time timer of 86400 s drifted by every hour spent asleep.
        _daily = new Timer(_ => { if (DailyCheckIsDue(DateTime.UtcNow)) _ = CheckAsync(teacherAsked: false); }, null,
                           TimeSpan.FromMinutes(1), TimeSpan.FromHours(1));
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

        if (!teacherAsked && info.Status is UpdateStatus.UpdateAvailable or UpdateStatus.UpdateNotAvailable or UpdateStatus.UserSkipped)
            _rememberDailyCheck(DateTime.UtcNow);
        var newest = info.Updates?.OrderByDescending(u => u).FirstOrDefault();
        switch (info.Status)
        {
            case UpdateStatus.UpdateAvailable when newest is not null:
                if (!teacherAsked && newest.Version == _skipped) return;
                if (_foundThisLaunch.Add(newest.Version ?? ""))
                    ActivityTrail.Note(ActivityTrail.Event.UpdateFound,
                        $"found {newest.Version}, running {_running}; {(teacherAsked ? "the teacher asked" : "the daily check")}" +
                        (newest.IsCriticalUpdate ? "; marked important" : ""));
                await OfferAsync(newest);
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

    private async Task OfferAsync(AppCastItem item)
    {
        var answer = await _prompts.OfferAsync(item.Version ?? "", item.Description);
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
