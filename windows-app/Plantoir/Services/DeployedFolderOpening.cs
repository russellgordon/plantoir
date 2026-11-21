using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;

namespace Plantoir.Services;

/// <summary>
/// Opening a section's deployed folder in the web browser (#889, the mac's
/// #850), the one path every place uses: the toolbar's Open in Browser and
/// Section ▸ Open in Browser while no preview shows, the button under a
/// finished folder deploy, and the section row's context menu. The offer is
/// read again at the press (<see cref="DeployedFolderOffer.LookUp"/>), the
/// address is handed to the browser through <see cref="ExternalLinks"/> (a
/// redirected run, the UI tests', records it and opens nothing), and a
/// failure is said in <c>couldNotOpen</c>'s dialog. The trail is written from
/// <see cref="DeployedFolderShows.Happened"/> in <c>App</c>, never here.
/// </summary>
internal static class DeployedFolderOpening
{
    /// <summary>The offer for a section now, from its saved settings and the disk.</summary>
    public static DeployedFolderOffer.Lookup Offer(Course course, int section, string workingFolder) =>
        DeployedFolderOffer.LookUp(course, section, workingFolder);

    /// <summary>
    /// Open the section's deployed folder. Nothing happens when it is not
    /// offered now (the caller redraws). A failure shows the dialog; a Stop
    /// pressed while it started shows nothing.
    /// </summary>
    public static async Task OpenAsync(Course course, int section, string workingFolder, DeployedFolderFrom from, XamlRoot? root)
    {
        var lookup = Offer(course, section, workingFolder);
        if (lookup.Decision.Kind != DeployedFolderOffer.Kind.Offered || lookup.SectionFolder is not { } sectionFolder) return;
        var outcome = await DeployedFolderShows.Shared.OpenAsync(sectionFolder, course.Code, section, workingFolder, from, ExternalLinks.Open);
        if (outcome.Address is null && outcome.Why is not null && root is not null) await CouldNotOpen(root);
    }

    /// <summary>Stop showing every show of the section, and a start still under way.</summary>
    public static void Stop(Course course, int section, string workingFolder) =>
        DeployedFolderShows.Shared.Stop(course.Code, section, workingFolder);

    /// <summary>Whether this app is showing the section's deployed folder.</summary>
    public static bool IsShown(Course course, int section, string workingFolder) =>
        DeployedFolderShows.Shared.ShowFor(course.Code, section, workingFolder) is not null;

    private static async Task CouldNotOpen(XamlRoot root)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = DeployedFolderWording.CouldNotOpenTitle,
            Content = new TextBlock { Text = DeployedFolderWording.CouldNotOpen, TextWrapping = TextWrapping.Wrap },
            CloseButtonText = DeployedFolderWording.CouldNotOpenButton,
            DefaultButton = ContentDialogButton.Close,
        };
        AutomationProperties.SetAutomationId(dialog, "deployedFolderCouldNotOpen");
        try { await dialog.ShowAsync(); }
        catch (Exception ex) { App.LogDiagnostic($"the deployed folder's could-not-open dialog could not be shown: {ex.Message}"); }
    }
}
