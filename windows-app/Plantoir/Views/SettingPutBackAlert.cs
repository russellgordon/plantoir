using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// The ONE alert a settings change shows when it stopped part way and
/// Plantoir could not finish it (#899 W8c-1b; the mac's
/// <c>SettingPutBackAlert</c>, Russell's ruling of 2026-11-26), for Set School
/// Year, Save Course Settings and a one-file Rename folder. Its words are the
/// offer's (<see cref="SettingPutBackOffer"/>, the contract's by key), and the
/// answer is decided in Core (<see cref="SettingPutBack.AnswerOnceClosed"/>).
/// </summary>
/// <remarks>
/// Microsoft, Dialog controls: "The 'do it' action button(s) should appear as
/// the leftmost buttons. The safe, nondestructive action should appear as the
/// rightmost button", the CloseButton answers "The user presses the ESC
/// button", and the DefaultButton "will respond to the ENTER key
/// automatically". So Put It Back is the Primary and default button (left,
/// accent, Enter) and Not Now the Close button (right, Escape), both visible;
/// no key is caught. Apple's HIG, Alerts, places the default on the trailing
/// side on the Mac; on Windows the platform's own order wins. Put It Back is
/// the default because it is the fix being offered and nothing is lost by it
/// ("Note that you don't want to make a Cancel button the default button").
/// "There can only be one ContentDialog open per window at a time": the
/// alert is shown only once the dialog under it has closed.
/// </remarks>
internal static class SettingPutBackAlert
{
    /// <summary>
    /// Shows the alert through the caller's own safe show (its
    /// <c>ShowDialogSafelyAsync</c>) and answers it once it has closed: Put It
    /// Back when its button was pressed, whichever order the press and the
    /// close come in; Not Now for anything else (Escape, the Close button, a
    /// dialog that could not be shown), which writes nothing.
    /// </summary>
    internal static async Task<SettingPutBackAnswer> AskAsync(
        SettingPutBackOffer offer, Func<ContentDialog, Task<ContentDialogResult?>> show)
    {
        bool putItBackWasPressed = false;
        var dialog = new ContentDialog
        {
            Title = offer.Title,
            Content = new TextBlock { Text = offer.InformativeText, TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = offer.PutItBackButton,
            CloseButtonText = offer.NotNowButton,
            DefaultButton = ContentDialogButton.Primary,
        };
        AutomationProperties.SetAutomationId(dialog, "settingPutBackAlert");
        DialogButtons.EnablePrimary(dialog, true);
        dialog.PrimaryButtonClick += (_, _) => putItBackWasPressed = true;
        // folder-check: not needed — the answer acts on the step by its number, not on a folder read before the dialog.
        ContentDialogResult? result = await show(dialog);
        return SettingPutBack.AnswerOnceClosed(putItBackWasPressed, result == ContentDialogResult.Primary);
    }
}
