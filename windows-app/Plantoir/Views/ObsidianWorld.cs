using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// The real <see cref="IObsidianWorld"/> (#581): Obsidian through
/// <see cref="FolderActions"/>, the add-ons carried beside Plantoir.exe, the
/// toolchain's course defaults, the app-wide answer in
/// <see cref="AppSettings"/>, and the two questions as ContentDialogs shown
/// through the caller's own <c>ShowDialogSafelyAsync</c> (so DialogGate
/// holds the menus while one is up). <c>Plantoir.Core</c>'s
/// <see cref="ObsidianOpenRoute"/> decides everything; this only does what it
/// is told.
/// </summary>
public sealed class ObsidianWorld : IObsidianWorld
{
    private readonly Func<ContentDialog, Task<ContentDialogResult?>>? _show;

    /// <param name="show">Shows a dialog over the caller's window; null where no question can be asked (the preview trigger asks none).</param>
    public ObsidianWorld(Func<ContentDialog, Task<ContentDialogResult?>>? show) => _show = show;

    public bool IsInstalled() => FolderActions.ObsidianIsInstalled;

    public bool IsRunning() => FolderActions.ObsidianIsRunning;

    public string? RegistryText() => FolderActions.ReadObsidianRegistry();

    public string TargetFor(string folder, string vault) => FolderActions.ObsidianTarget(folder, vault);

    // The page, when one is named, goes in through FolderActions' own page
    // door (`page ?? ObsidianTarget(...)`, #329's How I Teach door) - never
    // the folder door, which looks for <page>/index.md and opens the vault (#681).
    public Task OpenAsync(string folder, string vault, string? page = null) =>
        FolderActions.OpenInObsidian(folder, vault, BundledToolchain.SupportPath("obsidian_defaults/.obsidian"), page);

    public Task QuitAndWaitAsync() => FolderActions.QuitObsidianAndWait();

    public Task ReopenAsync(IReadOnlyList<string> vaultPaths) => FolderActions.ReopenVaults(vaultPaths);

    public Task<(List<ObsidianFigureAddOn> Needed, List<ObsidianFigureAddOn> WouldAdd)> ScanAsync(string coursePath) =>
        Task.Run(() => ObsidianFigureAddOns.Scan(coursePath));

    public string? CarriedFolder => Path.Combine(AppContext.BaseDirectory, ObsidianFigureAddOns.CarriedFolderName);

    public string? DefaultsFolder => BundledToolchain.SupportPath("obsidian_defaults/.obsidian");

    public ObsidianFigureAddOnsAnswer Answer
    {
        get => App.Settings.ObsidianFigureAddOnsAnswer;
        set => App.Settings.ObsidianFigureAddOnsAnswer = value;
    }

    /// <summary>
    /// The offer, BEFORE Obsidian opens: Add Them (the default), Not Now, and a
    /// "Don't ask again" box that turns Not Now into no. Escape is Not Now.
    /// </summary>
    public async Task<ObsidianFigureAddOnsTrail.Answered> AskOfferAsync(ObsidianAddOnsRequest request)
    {
        var dontAsk = new CheckBox { Content = ObsidianFigureAddOnsWording.DontAskAgain, Margin = new Thickness(0, 12, 0, 0) };
        AutomationProperties.SetAutomationId(dontAsk, "obsidianAddOnsDontAskAgain");
        var message = new TextBlock
        {
            Text = ObsidianFigureAddOnsWording.OfferText(request.Course.Code, request.CourseIsOpen),
            TextWrapping = TextWrapping.Wrap,
        };
        AutomationProperties.SetAutomationId(message, "obsidianAddOnsOfferMessage");
        var dialog = new ContentDialog
        {
            Title = ObsidianFigureAddOnsWording.OfferTitle,
            Content = new StackPanel { Children = { message, dontAsk }, MaxWidth = 460 },
            PrimaryButtonText = ObsidianFigureAddOnsWording.OfferAdd,
            CloseButtonText = ObsidianFigureAddOnsWording.OfferNotNow,
            DefaultButton = ContentDialogButton.Primary,
        };
        AutomationProperties.SetAutomationId(dialog, "obsidianAddOnsOffer");
        // As the mac's suppression toggle: the box means something only with
        // Not Now; Add Them is yes whether it is ticked or not.
        var result = _show is null ? null : await _show(dialog);
        if (result == ContentDialogResult.Primary) return ObsidianFigureAddOnsTrail.Answered.AddThem;
        return dontAsk.IsChecked == true ? ObsidianFigureAddOnsTrail.Answered.NotNowDontAskAgain : ObsidianFigureAddOnsTrail.Answered.NotNow;
    }

    /// <summary>The reopen question: Reopen Obsidian (the default) or Later. Escape is Later.</summary>
    public async Task<bool> AskReopenAsync(ObsidianAddOnsRequest request)
    {
        var dialog = new ContentDialog
        {
            Title = ObsidianFigureAddOnsWording.ReopenTitle,
            Content = new TextBlock
            {
                Text = ObsidianFigureAddOnsWording.Filling(ObsidianFigureAddOnsWording.ReopenMessage, request.Course.Code),
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = 460,
            },
            PrimaryButtonText = ObsidianFigureAddOnsWording.Reopen,
            CloseButtonText = ObsidianFigureAddOnsWording.Later,
            DefaultButton = ContentDialogButton.Primary,
        };
        AutomationProperties.SetAutomationId(dialog, "obsidianReopenForAddOns");
        return _show is not null && await _show(dialog) == ContentDialogResult.Primary;
    }
}
