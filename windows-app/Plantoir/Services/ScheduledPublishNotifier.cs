using System;
using System.IO;
using System.Linq;
using System.Security;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.ViewModels;

namespace Plantoir.Services;

/// <summary>
/// The scheduled-publish toast (#324, built minimally because #212's Windows
/// half had not been): POSTED by the run itself when it finishes, and a CLICK
/// shows that section (mac #306, decided by <see cref="ScheduledPublishToast.Decide"/>).
///
/// <para><b>What it says</b> is the section's own sentence, exactly as the band
/// fills it (<see cref="ScheduledPublishOutcome.Sentence"/>) â€” no new words
/// (rule 1). <b>Keyed per section per working folder</b>, so a later run of
/// the same section replaces it rather than stacking last week's beside it.</para>
///
/// <para><b>Unpackaged activation.</b> <c>WindowsPackageType=None</c>, so the
/// click is delivered through the COM activator <see cref="AppNotificationManager.Register"/>
/// sets up: to <c>NotificationInvoked</c> when Plantoir is running, or as a
/// cold start whose activation arguments <see cref="App"/> reads at launch.
/// Unproven on a real click as of bundle 8 (the desktop was locked).</para>
/// </summary>
public static class ScheduledPublishNotifier
{
    private static bool _registered;

    /// <summary>Register once per process. The handler goes on BEFORE Register, as the SDK requires.</summary>
    public static void Register(Action<string?> onClick)
    {
        if (_registered) return;
        try
        {
            AppNotificationManager.Default.NotificationInvoked += (_, args) => onClick(args.Argument);
            AppNotificationManager.Default.Register();
            _registered = true;
        }
        catch (Exception error) { App.LogDiagnostic("toast registration: " + error.Message); }
    }

    /// <summary>The cold-start case: Plantoir was launched BY a click on its toast.</summary>
    public static string? LaunchedFromAToast()
    {
        try
        {
            var activated = AppInstance.GetCurrent().GetActivatedEventArgs();
            return activated.Kind == ExtendedActivationKind.AppNotification
                ? ((AppNotificationActivatedEventArgs)activated.Data).Argument
                : null;
        }
        catch (Exception) { return null; }
    }

    /// <summary>
    /// Called by the scheduled run (Program.Main, no window) once it has
    /// finished: one toast for the section, whatever happened. Writes on the
    /// trail whether it went out or could not be sent.
    /// </summary>
    public static void PostFor(string jobPath)
    {
        if (ScheduledRun.ReadJob(jobPath) is not { } job) return;
        if (ScheduledPublishOutcome.Read(job.CourseCode, job.Section, job.WorkingFolder) is not { } outcome) return;
        string sentence = ScheduledPublishOutcome.Sentence(job.CourseCode, job.Section, outcome);
        string launch = ScheduledPublishToast.Format(new ScheduledPublishToast.Target(job.CourseCode, job.Section, job.WorkingFolder));
        try
        {
            AppNotificationManager.Default.Register();
            var notification = new AppNotification(
                $"<toast launch=\"{SecurityElement.Escape(launch)}\"><visual><binding template=\"ToastGeneric\">" +
                $"<text>{SecurityElement.Escape(sentence)}</text></binding></visual></toast>")
            {
                // A later run of the same section REPLACES this one.
                Tag = TagFor(job.CourseCode, job.Section, job.WorkingFolder),
                Group = "scheduled",
            };
            AppNotificationManager.Default.Show(notification);
            bool sent = notification.Id != 0;
            ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishNotification,
                sent ? "told with a notification" : "the notification could not be sent", job.CourseCode, job.Section);
        }
        catch (Exception error)
        {
            App.LogDiagnostic("toast post: " + error.Message);
            ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishNotification,
                "the notification could not be sent", job.CourseCode, job.Section);
        }
    }

    /// <summary>At most 64 characters, the toast tag's limit; the folder enters as its record name's hash.</summary>
    private static string TagFor(string course, int section, string folder)
    {
        string name = Path.GetFileNameWithoutExtension(TaskScheduling.HealthRecordName(course, section, folder));
        return name.Length <= 64 ? name : name[..64];
    }

    // ---- The click ---------------------------------------------------------

    /// <summary>On the UI thread: carry out what <see cref="ScheduledPublishToast.Decide"/> says.</summary>
    public static void Route(string? argument)
    {
        var target = ScheduledPublishToast.Parse(argument);
        // Front to back: the newest window is the nearest guess at the front
        // one, since an inactive app has no key window to ask.
        var windows = App.OpenWindows.Where(w => !w.IsClosed).Reverse().ToList();
        var seen = windows.Select(w => new ScheduledPublishToast.OpenWindow(
            w.Workspace.WorkspacePath is not { } path ? ScheduledPublishToast.WindowFolder.None
            : target is not null && WorkingFolder.IsTheSame(path, target.WorkingFolder) ? ScheduledPublishToast.WindowFolder.This
            : ScheduledPublishToast.WindowFolder.Other,
            IsBusy(w))).ToList();
        bool folderExists = target is not null && Directory.Exists(target.WorkingFolder);
        bool sectionInFolder = target is not null && folderExists && Directory.Exists(
            Path.Combine(target.WorkingFolder, "courses", target.CourseCode, $"section{target.Section}"));
        var decision = ScheduledPublishToast.Decide(target is not null, folderExists, sectionInFolder, seen);

        MainWindow? window = decision.Window is int i ? windows[i] : null;
        switch (decision.Action)
        {
            case ScheduledPublishToast.Action.UseWindow:
                if (decision.SelectsTheSection) Select(window!, target!);
                break;
            case ScheduledPublishToast.Action.AdoptInto:
                window!.Workspace.ChooseWorkspace(target!.WorkingFolder);
                Select(window, target);
                break;
            case ScheduledPublishToast.Action.OpenNewWindow:
                window = App.OpenWindow(target!.WorkingFolder, null);
                if (decision.SelectsTheSection) Select(window, target);
                break;
        }
        (window ?? windows.FirstOrDefault())?.Activate();

        if (target is null) ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishNotification, decision.TrailSays);
        else ActivityTrail.Note(ActivityTrail.Event.ScheduledPublishNotification, decision.TrailSays, target.CourseCode, target.Section);
    }

    private static void Select(MainWindow window, ScheduledPublishToast.Target target) =>
        window.DispatcherQueue.TryEnqueue(() =>
            window.Workspace.Selection = new SidebarSelection.SectionItem(target.CourseCode, target.Section));

    /// <summary>A dialog in front of the window is the teacher's work: leave its selection alone.</summary>
    private static bool IsBusy(MainWindow window) => DialogGate.IsOpen(window.Content?.XamlRoot);
}
