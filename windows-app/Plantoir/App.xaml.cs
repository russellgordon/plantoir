using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Xaml;
using Plantoir.Core.Models;
using Plantoir.Services;
using Plantoir.ViewModels;

namespace Plantoir;

public partial class App : Application
{
    public static AppSettings Settings { get; private set; } = null!;
    private static readonly List<MainWindow> _windows = new();

    /// <summary>
    /// The update engine (#337), or null in a development build (no feed at
    /// all, decision 5). Constructed in a Release build, but INACTIVE — it
    /// fetches nothing and shows no menu item — while AppUpdates.ConfiguredFeed
    /// is empty, which it is until a release sets it.
    /// </summary>
    public static Plantoir.Core.Assist.AppUpdater? Updater { get; private set; }

    /// <summary>The windows open now, as a copy (a handler may open or close one).</summary>
    public static IReadOnlyList<MainWindow> OpenWindows => _windows.ToList();

    public App()
    {
        InitializeComponent();
        UnhandledException += (sender, e) =>
        {
            LogDiagnostic($"App.UnhandledException: {e.Message}\n{e.Exception}");
        };
        AppDomain.CurrentDomain.UnhandledException += (sender, e) =>
        {
            LogDiagnostic($"AppDomain.UnhandledException: {e.ExceptionObject}");
        };
    }

    public static void LogDiagnostic(string message)
    {
        try
        {
            string dir = Plantoir.Core.Models.AppDataRoot.Current;
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir, "startup.log"), $"[{Plantoir.Core.Models.DateText.Invariant(DateTime.Now, "yyyy-MM-dd HH:mm:ss.fff")}] {message}\n");
        }
        catch { }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // FIRST, before the diagnostic line, before the trail line, and before
        // anything reads settings — each of those resolves its location the
        // moment it is touched, so a redirect applied afterwards is a redirect
        // that missed the first write.
        //
        // `--state-dir` moves this run's ENTIRE Plantoir folder — settings,
        // the breadcrumb trail, the startup log, scheduled-deploy sentinels,
        // models, built sites. A UI test drives the REAL shipped executable,
        // and without it the test would rewrite the teacher's working folder,
        // remembered windows and window geometry, file its fixture courses in
        // the trail as though a person had opened them, and — the one that
        // took an adversarial review to spot — CONSUME their pending
        // scheduled-deploy sentinels on launch, writing publish state into
        // their real course folders while the line explaining it went to the
        // redirected trail where nobody would look.
        //
        // Redirecting %LOCALAPPDATA% for the child process does not work and
        // was tried: GetFolderPath asks Windows for the known folder and
        // ignores the variable.
        //
        // Also read in Program.Main, which logs before this runs.
        //
        // QUOTE the path when passing it. `ArgumentAfter`'s raw-string
        // fallback splits on spaces, so an unquoted path containing one is
        // read as two arguments.
        string stateDir = ArgumentAfter(
            Environment.GetCommandLineArgs(), args.Arguments ?? "", "--state-dir");
        if (!string.IsNullOrEmpty(stateDir)) AppDataRoot.RedirectTo(stateDir);

        LogDiagnostic("App.OnLaunched starting");
        if (!string.IsNullOrEmpty(stateDir)) LogDiagnostic($"State redirected to {stateDir}");
        // #155: AFTER the redirect, so the line lands in the run's own
        // startup.log. For the developer only — never on the trail.
        if (Plantoir.Core.Scripting.StdioState.Describe(Plantoir.Core.Scripting.StdioState.FileTypeOf) is { } redirected)
            LogDiagnostic(redirected);

        Plantoir.Core.Scripting.ActivityTrail.NoteLaunch();

        // Say on the trail how every scheduled publish since the last launch
        // turned out — the ones that stopped, and the ones that went out.
        //
        // HERE, and not in MainWindow or SectionDetailView, for two separate
        // reasons. The contract asks for a line a teacher gets whether or not
        // they open the section that failed, because that teacher is exactly
        // the one who writes in to say their site did not update; and this runs
        // ONCE per process, where RememberOpenWindows can restore several
        // MainWindows and MainWindow already fires ConsumePending from two
        // places, so a sweep hosted there would run N times a launch.
        //
        // After --state-dir has been applied, so a test run reads its own
        // folder rather than the teacher's. Best-effort and silent: it writes
        // trail lines and shows nothing.
        try { Plantoir.Core.Assist.ScheduledPublishOutcome.NoteFinishedRunsOnTrail(); }
        catch (Exception ex) { LogDiagnostic($"Scheduled-publish trail sweep failed: {ex}"); }

        // ONE watch on the records' folder for the whole app (#218): a run that
        // finishes while Plantoir is open reaches every window at once, and its
        // trail line is written then rather than at the next launch (the sweep
        // is idempotent — each record's line is written once).
        Plantoir.Core.Assist.ScheduledPublishWatcher.RecordsChanged += () =>
        {
            try { Plantoir.Core.Assist.ScheduledPublishOutcome.NoteFinishedRunsOnTrail(); } catch { }
        };
        Plantoir.Core.Assist.ScheduledPublishWatcher.Start();

        try
        {
            Settings = AppSettings.Load();
            LogDiagnostic($"Settings loaded. WorkspacePath={Settings.WorkspacePath}, RememberedWindows={Settings.RememberedWindows.Count}");
        }
        catch (Exception ex)
        {
            LogDiagnostic($"Error loading settings: {ex}");
            Settings = new AppSettings();
        }

        // `app updated` (#337): the first launch of a new version, whoever
        // installed it. No updater runs yet, so it is always "by hand".
        try
        {
            string running = Plantoir.Core.Scripting.ProblemReportEnvironment.AppVersion;
            if (Plantoir.Core.Assist.AppUpdates.AppUpdatedLine(Settings.LastLaunchedVersion, running, byItsOwnUpdater: false) is { } line)
                Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.AppUpdated, line);
            if (Settings.LastLaunchedVersion != running)
            {
                Settings.LastLaunchedVersion = running;
                Settings.Save();
            }
        }
        catch (Exception ex) { LogDiagnostic($"app updated: {ex.Message}"); }

        // Ruling 12: installer.iss refused the update and reopened us.
        if (Plantoir.Core.Assist.AppUpdates.NotInstalledLine(Environment.GetCommandLineArgs()) is { } notInstalled)
            Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.UpdateHeldWhileWorkIsUnderWay, notInstalled);

#if DEBUG
        const bool developmentBuild = true;
#else
        const bool developmentBuild = false;
#endif
        if (Plantoir.Core.Assist.AppUpdates.FeedFor(developmentBuild) is not null)
        {
            Updater = new Plantoir.Core.Assist.AppUpdater(
                Plantoir.Core.Assist.AppUpdates.ConfiguredFeed, Plantoir.Core.Assist.AppUpdates.PublicKey,
                new Services.UpdatePrompts(), Services.UpdatePrompts.Snapshot,
                Plantoir.Core.Assist.MachineWork.RunningAssistantServers,
                Plantoir.Core.Scripting.ProblemReportEnvironment.AppVersion,
                Plantoir.Core.Assist.AppUpdates.IsPerUserInstall(AppContext.BaseDirectory,
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)),
                Settings.SkippedUpdateVersion,
                skipped => { Settings.SkippedUpdateVersion = skipped; try { Settings.Save(); } catch { } },
                _ => QuitConfirmation.WhatIsUnderWay(CourseActivity.UnderWay()));
            Updater.RememberingDailyChecksIn(
                () => Settings.LastUpdateCheckUtc,
                when => { Settings.LastUpdateCheckUtc = when; try { Settings.Save(); } catch { } });
            Updater.Start();
        }

        // Name every builds folder this app can name, then sweep the ones
        // whose working folder is gone. Once per process, here, never per
        // window. Both are best-effort and silent: a teacher cannot see
        // either, so neither leaves a trail line.
        try
        {
            var known = new List<string>();
            if (Settings.WorkspacePath is { } open) known.Add(open);
            foreach (var rememberedWindow in Settings.RememberedWindows) known.Add(rememberedWindow.Path);
            BuildOutputLocation.AdoptWorkingFolderMarkers(known);
            var swept = BuildOutputLocation.DiscardBuildsForMissingWorkingFolders();
            if (swept.Count > 0) LogDiagnostic($"Swept {swept.Count} builds folder(s) whose working folder is gone");
        }
        catch (Exception ex) { LogDiagnostic($"builds sweep: {ex.Message}"); }

        string rawArgs = args.Arguments ?? "";
        string[] cmdArgs = Environment.GetCommandLineArgs();
        string outputDir = "";

        int shotIdx = Array.IndexOf(cmdArgs, "--capture-marketing-shots");
        if (shotIdx >= 0 && shotIdx + 1 < cmdArgs.Length)
        {
            outputDir = cmdArgs[shotIdx + 1];
        }
        else if (rawArgs.Contains("--capture-marketing-shots"))
        {
            string[] parts = rawArgs.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            int idx = Array.IndexOf(parts, "--capture-marketing-shots");
            if (idx >= 0 && idx + 1 < parts.Length) outputDir = parts[idx + 1].Trim('"');
        }

        if (!string.IsNullOrEmpty(outputDir))
        {
            var bootstrapWindow = new MainWindow(null, null);
            bootstrapWindow.Activate();
            // Optional: capture one appearance only, so the harness can run
            // us once per OS theme and every themed brush resolves right.
            _ = MarketingShotCapturer.RunAsync(
                outputDir, ArgumentAfter(cmdArgs, rawArgs, "--theme") is { Length: > 0 } t ? t : null);
            return;
        }

        // The hero composite needs a REAL window on screen, title bar and all,
        // because the Python harness photographs it off the desktop beside
        // Obsidian and Edge. So this mode stages the window and stops -- the
        // harness takes the picture and kills the process.
        string heroTheme = ArgumentAfter(cmdArgs, rawArgs, "--hero-window");
        if (!string.IsNullOrEmpty(heroTheme))
        {
            _ = MarketingShotCapturer.ShowHeroWindowAsync(heroTheme);
            return;
        }

        // Windows has no system restoration: the remembered list is the
        // mechanism. Replay it when the preference asks; otherwise one
        // window, which shows the picker when no folder is remembered.
        // The rule is LastWorkingFolder.FoldersToOpen (#320): the remembered
        // windows when they come back, otherwise ONE window on the last
        // working folder — kept even when it cannot be reached, so the window
        // can say which folder and why.
        var remembered = Settings.RestoreWindowsOnLaunch ? Settings.RememberedWindows.ToList()
                                                         : new List<RememberedWindow>();
        var folders = LastWorkingFolder.FoldersToOpen(
            Settings.RestoreWindowsOnLaunch, remembered.Select(entry => entry.Path).ToList(), Settings.WorkspacePath);

        // The scheduled-publish toast (#324): a click while Plantoir runs
        // arrives on a background thread and is carried to this one; a click
        // that STARTED Plantoir is routed once its windows are open.
        var dispatcher = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        Services.ScheduledPublishNotifier.Register(argument =>
            dispatcher.TryEnqueue(() => Services.ScheduledPublishNotifier.Route(argument)));
        string? launchedBy = Services.ScheduledPublishNotifier.LaunchedFromAToast();

        if (remembered.Count == 0)
            OpenWindow(folders[0], null);
        else
            foreach (var entry in remembered)
                OpenWindow(entry.Path, entry);

        if (launchedBy is not null)
            dispatcher.TryEnqueue(() => Services.ScheduledPublishNotifier.Route(launchedBy));
    }

    /// <summary>
    /// The value following a command-line flag. Windows hands the same
    /// arguments over twice -- once parsed in <c>Environment.GetCommandLineArgs</c>
    /// and once as one raw string on <c>LaunchActivatedEventArgs</c> -- and
    /// which one carries them depends on how the app was started, so both are
    /// searched.
    /// </summary>
    private static string ArgumentAfter(string[] cmdArgs, string rawArgs, string flag)
    {
        int index = Array.IndexOf(cmdArgs, flag);
        if (index >= 0 && index + 1 < cmdArgs.Length) return cmdArgs[index + 1].Trim('"');

        if (!rawArgs.Contains(flag)) return "";
        string[] parts = rawArgs.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        index = Array.IndexOf(parts, flag);
        if (index >= 0 && index + 1 < parts.Length) return parts[index + 1].Trim('"');
        return "";
    }

    public static MainWindow OpenWindow(string? folderPath, RememberedWindow? frame)
    {
        LogDiagnostic($"App.OpenWindow for folderPath='{folderPath}'");
        try
        {
            var window = new MainWindow(folderPath, frame);
            _windows.Add(window);
            window.Closed += (_, _) =>
            {
                LogDiagnostic($"MainWindow.Closed. Remaining windows count={_windows.Count - 1}");
                _windows.Remove(window);
                // A mid-session close updates the remembered list; the LAST
                // close reads as quitting and must NOT shrink it — the list
                // keeps the configuration from before the exit began, which is
                // what relaunch should bring back.
                if (_windows.Count == 0) QuitTime();
                else RememberOpenWindows();
            };
            LogDiagnostic("App.OpenWindow: calling window.Activate()");
            window.Activate();
            LogDiagnostic($"MainWindow.Activate called. Total windows={_windows.Count}");
            RememberOpenWindows();
            return window;
        }
        catch (Exception ex)
        {
            LogDiagnostic($"CRITICAL EXCEPTION in OpenWindow: {ex}");
            throw;
        }
    }


    /// <summary>
    /// An open main window showing this working folder, or null. For the
    /// assistant, whose own main window may have been closed under it: the
    /// build then goes to another window on the same folder rather than to
    /// a second one opened beside it.
    /// </summary>
    public static MainWindow? WindowFor(string folderPath)
    {
        foreach (var window in _windows)
        {
            if (window.IsClosed || window.Workspace.WorkspacePath is not { } open) continue;
            try
            {
                // The app's single comparison (#162), so this answers the same
                // way as every other "is that the same folder?" in the app.
                if (WorkingFolder.IsTheSame(open, folderPath)) return window;
            }
            catch (Exception) { /* a malformed stored path is "no window", not a crash in the tool loop */ }
        }
        return null;
    }

    /// <summary>A synced-folder note answered in one window leaves every other window showing that folder.</summary>
    public static void HideSyncNoticesFor(string path, MainWindow? except)
    {
        foreach (var window in _windows)
            if (!ReferenceEquals(window, except) && !window.IsClosed) window.HideSyncNoticeFor(path);
    }

    /// <summary>Ctrl+N: inherit the key window's folder; alone → the picker.</summary>
    public static MainWindow OpenNewWindow()
    {
        var window = OpenWindow(null, null);
        window.Workspace.AdoptFolderForNewWindow();
        window.ShowSyncNoticeIfNeeded();
        return window;
    }

    /// <summary>Whether closing this window quits the app: it is the last one still open (#231).</summary>
    public static bool ClosingThisQuits(MainWindow window) =>
        _windows.Where(open => !open.IsClosed).All(open => ReferenceEquals(open, window));

    /// <summary>Recorded while the windows still exist — a list rewritten as they close shrinks to nothing.</summary>
    public static void RememberOpenWindows()
    {
        Settings.RememberedWindows = _windows
            .Where(w => w.Workspace.WorkspacePath is not null)
            .Select(w => w.RememberedEntry())
            .Where(e => e is not null)
            .Select(e => e!)
            .ToList();
        Settings.Save();
    }

    /// <summary>The update engine's exit: the installer is already started.</summary>
    public static void QuitForUpdate()
    {
        _installerStarted = true;
        QuitTime();
    }

    private static bool _installerStarted;

    private static void QuitTime()
    {
        LogDiagnostic("QuitTime called");
        // atQuit (#337): never refuses; a prepared update is set aside when
        // work is under way, or installed as Plantoir quits without reopening.
        try
        {
            if (!_installerStarted && Updater is { } updater)
            {
                // The same gate as the install (ruling 7), not only this app's own work.
                if (updater.AtQuitGated() is { } install)
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(install.Path, install.Arguments) { UseShellExecute = false });
            }
        }
        catch (Exception ex) { LogDiagnostic($"update at quit: {ex.Message}"); }
        WorkspaceViewModel.IsTerminating = true;
        FolderContainers.ReleaseEverythingAtQuit(
            Settings.RememberedWindows.Select(w => w.Path).Distinct().ToList());
        Current.Exit();
    }
}
