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
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Settings = AppSettings.Load();

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
            _ = MarketingShotCapturer.RunAsync(outputDir);
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

    public static MainWindow OpenWindow(string? folderPath, RememberedWindow? frame)
    {
        var window = new MainWindow(folderPath, frame);
        _windows.Add(window);
        window.Closed += (_, _) =>
        {
            _windows.Remove(window);
            // A mid-session close updates the remembered list; the LAST
            // close reads as quitting and must NOT shrink it — the list
            // keeps the configuration from before the exit began, which is
            // what relaunch should bring back.
            if (_windows.Count == 0) QuitTime();
            else RememberOpenWindows();
        };
        window.Activate();
        RememberOpenWindows();
        return window;
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
        WorkspaceViewModel.IsTerminating = true;
        FolderContainers.ReleaseEverythingAtQuit(
            Settings.RememberedWindows.Select(w => w.Path).Distinct().ToList());
        Current.Exit();
    }
}
