using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// The ONE place a ContentDialog's main button is enabled or disabled (#491
/// item 2): the rule is <see cref="PrimaryButtonLook.For"/>, and this applies
/// it — enablement, which button is the default, and the accent style —
/// together, so no dialog can grey its main button and leave it looking like
/// the default. <c>DefaultButtonScanTests</c> holds every
/// <c>IsPrimaryButtonEnabled</c> write under <c>Plantoir/</c> to this file.
/// </summary>
public static class DialogButtons
{
    public static void EnablePrimary(ContentDialog dialog, bool enabled, PrimaryKind kind = PrimaryKind.TakesEnterWhenEnabled)
    {
        var look = PrimaryButtonLook.For(enabled, kind);
        dialog.IsPrimaryButtonEnabled = enabled;
        switch (look.Default)
        {
            case DefaultChoice.Primary: dialog.DefaultButton = ContentDialogButton.Primary; break;
            case DefaultChoice.None:
                // Only the main button's own default is taken away: a dialog whose
                // default is Close or Secondary keeps it.
                if (dialog.DefaultButton == ContentDialogButton.Primary) dialog.DefaultButton = ContentDialogButton.None;
                break;
        }
        if (kind == PrimaryKind.NotTheDefault) return;
        dialog.PrimaryButtonStyle = look.AccentStyle
            ? (Style)Application.Current.Resources["AccentButtonStyle"]
            : null;
    }
}
