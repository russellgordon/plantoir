using System;
using System.IO;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Models;

namespace Plantoir.Services;

/// <summary>
/// Whether a <see cref="ContentDialog"/> is up in this window (#191). The four
/// window-level accelerators (Ctrl+O, Ctrl+N, Ctrl+Shift+R, F2) have no
/// <c>ScopeOwner</c>, so WinUI may deliver them while a modal dialog holds the
/// foreground; each handler asks <see cref="Holds"/> first and does nothing
/// while one is up.
///
/// <para>Reads the open popups and keeps only those whose child IS a
/// ContentDialog. <c>GetOpenPopupsForXamlRoot</c> unfiltered also reports menu
/// flyouts and tooltips — the reason it was rejected as-is in #191, since
/// Ctrl+O would then die while a context menu is open. Rejected too: a counter
/// every <c>ShowAsync</c> call site increments, which is right only while
/// every one of ~40 call sites remembers it.</para>
///
/// <para>Measured in bundle 11 (documentation/12, "Accelerators under a
/// dialog"): with the positive control that the same keys DO arrive with no
/// dialog up. <see cref="Holds"/> is also how the measurement is MADE: in a run
/// whose state is redirected (<c>--state-dir</c>, which only the UI tests
/// pass), every key it holds is written, one name per line, to
/// <see cref="HeldUnderADialogFileName"/> in that state folder.
/// <c>AcceleratorUnderDialogUiTests</c> reads it back: a key listed there is
/// one WinUI DID deliver under the dialog, so the guard is what stopped it; a
/// key pressed and not listed never reached the handler. A teacher's run never
/// redirects, so it never writes the file.</para>
/// </summary>
public static class DialogGate
{
    /// <summary>The record of held keys, in a redirected run's state folder only.</summary>
    public const string HeldUnderADialogFileName = "accelerators-held-under-a-dialog.txt";

    public static bool IsOpen(XamlRoot? root)
    {
        if (root is null) return false;
        try { return VisualTreeHelper.GetOpenPopupsForXamlRoot(root).Any(p => p.Child is ContentDialog); }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// True when a dialog is up, so the accelerator named must do nothing —
    /// and, in a redirected (test) run, records that WinUI delivered it.
    /// </summary>
    public static bool Holds(XamlRoot? root, string accelerator)
    {
        bool open = IsOpen(root);
        if (AppDataRoot.IsRedirected)
        {
            try
            {
                // Every ARRIVAL, held or passed — the positive control for the
                // measurement (bundle 11, W2): a key absent from the held list
                // means something only if the same key, pressed with no dialog
                // up, is shown to arrive at all.
                File.AppendAllText(AppDataRoot.Combine(ArrivedFileName), $"{accelerator} {(open ? "held" : "passed")}{Environment.NewLine}");
                if (open) File.AppendAllText(AppDataRoot.Combine(HeldUnderADialogFileName), accelerator + Environment.NewLine);
            }
            catch (Exception) { /* a measurement must never change what the key does */ }
        }
        return open;
    }

    /// <summary>Every accelerator that reached its handler, in a redirected run only: "&lt;key&gt; held|passed".</summary>
    public const string ArrivedFileName = "accelerators-arrived.txt";
}
