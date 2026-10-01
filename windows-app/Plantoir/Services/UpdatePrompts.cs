using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Services;

/// <summary>
/// The update engine's windows (#337): our own ContentDialogs, every word
/// from <see cref="UpdateWording"/> — NetSparkle's own UI is never used, so
/// nothing a teacher reads names the machinery (rule 1). Shown on the newest
/// open main window, on its UI thread.
/// </summary>
public sealed class UpdatePrompts : IUpdatePrompts
{
    private static MainWindow? Host() => App.OpenWindows.LastOrDefault(w => !w.IsClosed);

    private static Task<ContentDialogResult> ShowAsync(Func<ContentDialog> make)
    {
        var done = new TaskCompletionSource<ContentDialogResult>();
        if (Host() is not { } window) { done.SetResult(ContentDialogResult.None); return done.Task; }
        window.DispatcherQueue.TryEnqueue(async () =>
        {
            try
            {
                if (DialogGate.IsOpen(window.Content?.XamlRoot)) { done.TrySetResult(ContentDialogResult.None); return; }
                var dialog = make();
                dialog.XamlRoot = window.Content!.XamlRoot;
                done.TrySetResult(await dialog.ShowAsync());
            }
            catch (Exception error) { App.LogDiagnostic("update dialog: " + error.Message); done.TrySetResult(ContentDialogResult.None); }
        });
        return done.Task;
    }

    public async Task<UpdateAnswer> OfferAsync(string version, string? notes)
    {
        var result = await ShowAsync(() => new ContentDialog
        {
            Title = UpdateWording.OfferTitle.Replace("{version}", version),
            Content = new TextBlock { Text = notes ?? "", TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = UpdateWording.OfferInstall,
            SecondaryButtonText = UpdateWording.OfferSkip,
            CloseButtonText = UpdateWording.OfferLater,
            DefaultButton = ContentDialogButton.Primary,
        });
        return result switch
        {
            ContentDialogResult.Primary => UpdateAnswer.Install,
            ContentDialogResult.Secondary => UpdateAnswer.Skip,
            _ => UpdateAnswer.NotNow,
        };
    }

    public Task ShowUpToDateAsync() => ShowAsync(() => Plain(UpdateWording.UpToDate, ""));

    public Task ShowCouldNotCheckAsync() => ShowAsync(() => Plain(UpdateWording.CouldNotCheck, ""));

    public Task ShowHeldAsync(string work, bool onceInstalling) => ShowAsync(() => Plain(
        UpdateWording.HeldTitle.Replace("{work}", work),
        onceInstalling ? UpdateWording.HeldExplanationOnceInstalling : UpdateWording.HeldExplanation));

    public Task ShowNeedsAdministratorAsync() => ShowAsync(() => Plain(
        UpdateWording.NeedsAdministratorTitle, UpdateWording.NeedsAdministratorExplanationOnWindows));

    private static ContentDialog Plain(string title, string text) => new()
    {
        Title = title,
        Content = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap },
        CloseButtonText = UpdateWording.OkButton,
    };

    public void QuitForInstall(string installerPath, string arguments)
    {
        try
        {
            Process.Start(new ProcessStartInfo(installerPath, arguments) { UseShellExecute = false });
            App.QuitForUpdate();
        }
        catch (Exception error) { App.LogDiagnostic("update install: " + error.Message); }
    }

    // ---- What the gate reads -------------------------------------------------

    /// <summary>
    /// This app's own work (CourseActivity), another copy of this executable
    /// with no window (a scheduled publish — unnamed, since its job file is
    /// gone once it starts), and every other process's build or publish lease
    /// in the folders the real settings name.
    /// </summary>
    public static AppUpdates.Snapshot Snapshot()
    {
        var underWay = CourseActivity.UnderWay();
        var copies = new List<AppUpdates.OtherCopy>();
        try
        {
            foreach (var other in Process.GetProcessesByName("Plantoir").Where(p => p.Id != Environment.ProcessId))
                if (other.MainWindowHandle == IntPtr.Zero) copies.Add(new AppUpdates.OtherCopy(other.Id, "scheduledPublish"));
        }
        catch (Exception) { }
        var folders = MachineWork.KnownFolders(MachineWork.RealSettingsPath());
        var leases = MachineWork.Read(folders, () => Array.Empty<int>()).Leases
            .Select(l => new AppUpdates.LeaseFact(l.Lease.Pid, l.Lease.Kind, l.Lease.Course)).ToList();
        return new AppUpdates.Snapshot(
            Enumerable.Repeat(("", 0), underWay.Publishes).ToList(),
            Enumerable.Repeat(("", 0), underWay.PreviewsBeingBuilt).ToList(),
            underWay.PreviewsOpen, copies, leases);
    }
}
