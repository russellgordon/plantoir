using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
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
    /// <summary>
    /// A question where Enter must not go ahead (#979, the mac's #973 and
    /// #987): no button is the default, and the cancelling button (WinUI's
    /// Close button, which Escape already presses) holds the focus when the
    /// dialog opens.
    /// </summary>
    /// <remarks>
    /// The focus is the half that matters. WinUI's ContentDialog puts its
    /// first focus on the first focusable control in its content, then on the
    /// default button, then on the first focusable BUTTON in its row, which
    /// is the Primary one: the go-ahead (ContentDialog_Partial.cpp,
    /// SetInitialFocusElement). A focused button takes Enter and Space. So a
    /// question with no default and nothing focusable in it opened with the
    /// focus on Remove, Delete or Quit Anyway, and Enter pressed it
    /// (measured on the Windows VM, QuestionDialogKeysUiTests). With the
    /// focus on Cancel, Enter and Space press the visible Cancel, as Escape
    /// does; nothing is hidden and no key is caught.
    /// Apple's HIG, Alerts: "Note that you don't want to make a Cancel button
    /// the default button" and "If you want to encourage people to read an
    /// alert and not just automatically press Return to dismiss it, avoid
    /// making any button the default button."
    /// <c>QuestionDialogScanTests</c> holds every question to this helper.
    /// </remarks>
    public static void AskWithNoDefault(ContentDialog dialog)
    {
        dialog.DefaultButton = ContentDialogButton.None;
        dialog.Opened += (sender, _) => FocusTheCloseButton(sender);
    }

    /// <summary>Put the focus on the dialog's Close button, the one Escape presses.</summary>
    public static void FocusTheCloseButton(ContentDialog dialog)
    {
        if (TemplatePart(dialog, "CloseButton") is Control close) close.Focus(FocusState.Programmatic);
    }

    /// <summary>
    /// A named part of the dialog's template ("CloseButton", "LayoutRoot"),
    /// once it is shown. Looked for under the dialog first, then from the top
    /// of the tree its content is drawn in, since WinUI draws a dialog in a
    /// popup of its own.
    /// </summary>
    public static FrameworkElement? TemplatePart(ContentDialog dialog, string name)
    {
        if (Named(dialog, name) is { } underTheDialog) return underTheDialog;
        DependencyObject? top = dialog.Content as DependencyObject;
        if (top is null) return null;
        while (VisualTreeHelper.GetParent(top) is { } parent) top = parent;
        return Named(top, name);
    }

    private static FrameworkElement? Named(DependencyObject root, string name)
    {
        var waiting = new Queue<DependencyObject>();
        waiting.Enqueue(root);
        while (waiting.Count > 0)
        {
            var next = waiting.Dequeue();
            if (next is FrameworkElement element && element.Name == name) return element;
            int count = VisualTreeHelper.GetChildrenCount(next);
            for (int index = 0; index < count; index++) waiting.Enqueue(VisualTreeHelper.GetChild(next, index));
        }
        return null;
    }
}
