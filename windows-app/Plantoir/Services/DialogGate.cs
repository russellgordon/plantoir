using System;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Plantoir.Services;

/// <summary>
/// Whether a <see cref="ContentDialog"/> is up in this window (#191). The four
/// window-level accelerators (Ctrl+O, Ctrl+N, Ctrl+Shift+R, F2) have no
/// <c>ScopeOwner</c>, so WinUI may deliver them while a modal dialog holds the
/// foreground; each handler asks this first and does nothing while one is up.
///
/// <para>Reads the open popups and keeps only those whose child IS a
/// ContentDialog. <c>GetOpenPopupsForXamlRoot</c> unfiltered also reports menu
/// flyouts and tooltips — the reason it was rejected as-is in #191, since
/// Ctrl+O would then die while a context menu is open. Rejected too: a counter
/// every <c>ShowAsync</c> call site increments, which is right only while
/// every one of ~40 call sites remembers it.</para>
///
/// <para>Whether the keys actually fire under a dialog was NOT measured
/// (bundle 8, the desktop was locked); the guard costs nothing if they do not.</para>
/// </summary>
public static class DialogGate
{
    public static bool IsOpen(XamlRoot? root)
    {
        if (root is null) return false;
        try { return VisualTreeHelper.GetOpenPopupsForXamlRoot(root).Any(p => p.Child is ContentDialog); }
        catch (Exception) { return false; }
    }
}
