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

    /// <summary>Set by <c>--state-dir</c>, so a harness run's startup log goes
    /// with the rest of its state instead of into the teacher's.</summary>
    private static string? _diagnosticDirectory;

    public static void LogDiagnostic(string message)
    {
        try
        {
            string dir = _diagnosticDirectory
                ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir");
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir, "startup.log"), $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}\n");
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
        // `--state-dir` keeps this run's own state somewhere of its own: the
        // settings file and the breadcrumb trail. A UI test drives the REAL
        // shipped executable, and without this it would rewrite the teacher's
        // working folder, their remembered windows and the geometry of every
        // window they had open, and would file its fixture courses in the
        // trail as though a person had opened them. Redirecting %LOCALAPPDATA%
        // for the child process does not work and was tried: GetFolderPath
        // asks Windows for the known folder and ignores the variable.
        //
        // QUOTE the path when passing it. `ArgumentAfter`'s raw-string
        // fallback splits on spaces, so an unquoted path containing one is
        // read as two arguments.
        string stateDir = ArgumentAfter(
            Environment.GetCommandLineArgs(), args.Arguments ?? "", "--state-dir");
        if (!string.IsNullOrEmpty(stateDir))
        {
            try { Directory.CreateDirectory(stateDir); } catch { }
            AppSettings.PathOverride = Path.Combine(stateDir, "settings.json");
            Plantoir.Core.Scripting.ActivityTrail.SetCustomLogPathForTesting(
                Path.Combine(stateDir, "activity.txt"));
            _diagnosticDirectory = stateDir;
        }

        LogDiagnostic("App.OnLaunched starting");
        if (!string.IsNullOrEmpty(stateDir)) LogDiagnostic($"State redirected to {stateDir}");

        Plantoir.Core.Scripting.ActivityTrail.NoteLaunch();
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
        var remembered = Settings.RestoreWindowsOnLaunch ? Settings.RememberedWindows.ToList()
                                                         : new List<RememberedWindow>();
        if (remembered.Count == 0)
        {
            OpenWindow(Settings.WorkspacePath, null);
            return;
        }
        foreach (var entry in remembered)
            OpenWindow(entry.Path, entry);
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


    /// <summary>Ctrl+N: inherit the key window's folder; alone → the picker.</summary>
    public static MainWindow OpenNewWindow()
    {
        var window = OpenWindow(null, null);
        window.Workspace.AdoptFolderForNewWindow();
        return window;
    }

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

    private static void QuitTime()
    {
        LogDiagnostic("QuitTime called");
        WorkspaceViewModel.IsTerminating = true;
        FolderContainers.ReleaseEverythingAtQuit(
            Settings.RememberedWindows.Select(w => w.Path).Distinct().ToList());
        Current.Exit();
    }
}
