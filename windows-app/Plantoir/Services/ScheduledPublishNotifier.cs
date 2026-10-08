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
    /// <summary>
    /// Whether THIS PROCESS has called <see cref="AppNotificationManager.Register"/>.
    /// One flag for the app's own registration and <see cref="SystemToasts"/>'
    /// (#464): the app registers at launch, and a withdrawal from a band's
    /// Dismiss must not register a second time in the same process.
    /// </summary>
    private static bool _registered;

    private static void EnsureRegistered()
    {
        if (_registered) return;
        AppNotificationManager.Default.Register();
        _registered = true;
    }

    /// <summary>Register once per process. The handler goes on BEFORE Register, as the SDK requires.</summary>
    public static void Register(Action<string?> onClick)
    {
        if (_registered) return;
        try
        {
            AppNotificationManager.Default.NotificationInvoked += (_, args) => onClick(args.Argument);
            EnsureRegistered();
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
    /// The system's toasts, as the scheduled run (Program.Main, no window)
    /// posts through <see cref="ScheduledRunAnnouncement.RunAndAnnounce"/>:
    /// that decides what to say and writes the trail line; this only shows it.
    /// Until #448 this read the job file itself AFTER the run, which the run's
    /// own one-shot clearing had already deleted, and returned without a word.
    /// </summary>
    public sealed class SystemToasts : ScheduledRunAnnouncement.IPoster
    {
        public ScheduledRunAnnouncement.Permission Permission
        {
            get
            {
                EnsureRegistered();
                // Only a switch the teacher (or their school) turned off counts
                // as "turned off"; anything else is tried, and a post that does
                // not land says so on the trail.
                return AppNotificationManager.Default.Setting switch
                {
                    AppNotificationSetting.DisabledForApplication or AppNotificationSetting.DisabledForUser
                        or AppNotificationSetting.DisabledByGroupPolicy => ScheduledRunAnnouncement.Permission.NotAllowed,
                    _ => ScheduledRunAnnouncement.Permission.Allowed,
                };
            }
        }

        public bool Post(string tag, string launchArgument, string sentence)
        {
            EnsureRegistered();
            var notification = new AppNotification(
                $"<toast launch=\"{SecurityElement.Escape(launchArgument)}\"><visual><binding template=\"ToastGeneric\">" +
                $"<text>{SecurityElement.Escape(sentence)}</text></binding></visual></toast>")
            {
                // A later run of the same section REPLACES this one.
                Tag = tag,
                Group = ScheduledRunAnnouncement.ToastGroup,
            };
            AppNotificationManager.Default.Show(notification);
            return notification.Id != 0;
        }

        /// <summary>
        /// #464: called in the APP's process for a toast the scheduled run (a
        /// separate Plantoir.exe started by Task Scheduler) posted. Both are the
        /// same executable, so both register the same unpackaged identity (one
        /// <c>HKCU\Software\Classes\AppUserModelId\{GUID}</c> per executable
        /// path), and the removal reaches the other process's toast: measured,
        /// documentation/12-windows-app.md, "The scheduled-publish toast (#324)".
        /// By tag AND group: by tag alone would also take a toast of another
        /// group that happened to share the tag. Fire and forget; a failure is
        /// written to the diagnostic log.
        /// </summary>
        public void Withdraw(string tag)
        {
            EnsureRegistered();
            AppNotificationManager.Default.RemoveByTagAndGroupAsync(tag, ScheduledRunAnnouncement.ToastGroup)
                .AsTask().ContinueWith(
                    removal => App.LogDiagnostic("scheduled toast withdraw: " + removal.Exception?.GetBaseException().Message),
                    System.Threading.Tasks.TaskContinuationOptions.OnlyOnFaulted);
        }
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
