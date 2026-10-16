using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Plantoir.Core.Models;
using Plantoir.Views;
using Windows.System;
using Windows.UI.Core;

namespace Plantoir;

/// <summary>
/// Alt, for Preview at Last Viewed (#514; the mac's Option, #504): the
/// Preview button is titled by what a press will do, and holding Alt in
/// THIS window gives it the other title — the setting XOR Alt, the contract's
/// <c>previewStartPage.titles</c>.
/// </summary>
/// <remarks>
/// <para><b>Only in the window that is active.</b> Alt typed in another
/// window must not re-title every section window, and a release made in
/// another window is never seen here — so the state is FORCED off when this
/// window is deactivated rather than left stale, and read again when it is
/// activated. One active window at a time makes "only the focused window"
/// structural.</para>
/// <para><b>Read again when it could have been missed:</b> a key down or up
/// anywhere in the window (handled or not), the window activated, a menu
/// closing (the first item's Unloaded, measured to fire on every close —
/// Alt released inside an open menu was the mac's lost release), and the
/// pointer reaching the Preview button or the button taking focus, which is
/// how a press gets there.</para>
/// <para>Measured before relying on it (12 → "Preview at Last Viewed on
/// Windows"): Alt alone, with no access keys anywhere, shows no KeyTips,
/// enters no menu mode and swallows nothing, and Alt held through a click
/// still raises Click. The press itself never trusts this state: the click
/// reads the keyboard again (<see cref="KeyIsDown"/>), and that is the
/// authority.</para>
/// </remarks>
public sealed partial class MainWindow
{
    /// <summary>Alt (without Ctrl: Ctrl+Alt is AltGr) held in this window while it is active.</summary>
    internal bool ModifierHeldForTitles { get; private set; }

    private bool _isActive = true;

    /// <summary>Whether a key is down now, for the thread the window runs on.</summary>
    internal static bool KeyIsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    private void AttachTheModifier()
    {
        if (Content is UIElement root)
        {
            var onKey = new KeyEventHandler((_, args) =>
            {
                if (args.Key is VirtualKey.Menu or VirtualKey.LeftMenu or VirtualKey.RightMenu
                    or VirtualKey.Control or VirtualKey.LeftControl or VirtualKey.RightControl)
                    ReadTheModifierAgain();
            });
            root.AddHandler(UIElement.KeyDownEvent, onKey, handledEventsToo: true);
            root.AddHandler(UIElement.KeyUpEvent, onKey, handledEventsToo: true);
        }
        Activated += (_, args) =>
        {
            _isActive = args.WindowActivationState != WindowActivationState.Deactivated;
            ReadTheModifierAgain();
        };
        AppSettings.PreviewOpensAtChanged += PreviewOpensAtChanged;
        Closed += (_, _) => AppSettings.PreviewOpensAtChanged -= PreviewOpensAtChanged;
    }

    /// <summary>The setting changed (File ▸ Settings ▸ Preview): the Section menu's two titles follow.</summary>
    private void PreviewOpensAtChanged()
    {
        if (IsClosed) return;
        DispatcherQueue.TryEnqueue(() => { if (!IsClosed) ApplyMenuEnablement(); });
    }

    /// <summary>Reads Alt again and, when it changed, re-titles the section shown.</summary>
    internal void ReadTheModifierAgain()
    {
        if (IsClosed) return;
        bool held = _isActive && PreviewStartPage.ModifierHeld(KeyIsDown(VirtualKey.Menu), KeyIsDown(VirtualKey.Control));
        if (held == ModifierHeldForTitles) return;
        ModifierHeldForTitles = held;
        (DetailHost.Content as SectionDetailView)?.RefreshPreviewTitle();
    }
}
