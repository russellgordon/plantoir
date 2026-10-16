using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Plantoir.Services;
using Windows.Graphics;

namespace Plantoir.Views;

/// <summary>The sections of File ▸ Settings…, in the mac's order (Assistant · Preview · Deploying).</summary>
public enum SettingsSection
{
    Assistant,
    /// <summary>Where Preview opens (#514).</summary>
    Preview,
    Deploying,
}

/// <summary>
/// File ▸ Settings… (#491; Russell's ruling of 2026-10-15): ONE Settings
/// window with a section per subject — Assistant, Preview (#514) and
/// Deploying — matching the mac's Plantoir ▸ Settings.
/// </summary>
/// <remarks>
/// <para><b>A window, not a ContentDialog</b> (what it was until #491, as
/// <c>AssistantSettingsDialog</c>). WinUI shows ONE ContentDialog per window
/// at a time — measured, the limit is per XamlRoot: a second window shows its
/// own while the first's is up, and a second in the SAME window throws
/// <c>0x80000019</c>. The new-course wizard IS a ContentDialog, so Open
/// Settings… from inside it could not show Settings as a dialog without
/// closing the wizard and losing what was typed. A modeless window can come
/// forward beside it, and the wizard follows the ID live. Rejected, with
/// Russell, on #491: a Deploying pane inside the assistant's settings dialog,
/// and keeping the field in a course's settings with a "for every course"
/// label.</para>
///
/// <para><b>One at a time.</b> <see cref="Show"/> brings an open window forward
/// on the section asked for rather than opening a second. It never keeps the
/// app running: the app quits when its last MAIN window closes
/// (<c>App.QuitTime</c>), which first calls <see cref="NoteBeforeQuit"/> so a
/// change still in the field reaches the trail.</para>
/// </remarks>
public sealed class SettingsWindow : Window
{
    private static SettingsWindow? _open;

    private readonly NavigationView _navigation;
    private readonly NavigationViewItem _assistantItem;
    private readonly NavigationViewItem _previewItem;
    private readonly NavigationViewItem _deployingItem;
    private readonly AssistantSettingsPane _assistant;
    private readonly PreviewSettingsPane _preview;
    private readonly DeployingSettingsPane _deploying;
    private SettingsSection _shown;
    private bool _shownOnce;

    /// <summary>
    /// Opens Settings on <paramref name="section"/>, or brings the open window
    /// forward and shows that section.
    /// </summary>
    public static void Show(SettingsSection section)
    {
        if (_open is { } open)
        {
            open.Select(section);
            open.Activate();
            return;
        }
        var window = new SettingsWindow();
        _open = window;
        window.Select(section);
        window.Activate();
    }

    /// <summary>The section File ▸ Settings… opens on: the one last chosen, or Assistant.</summary>
    public static SettingsSection LastChosen() => App.Settings.LastSettingsSection switch
    {
        "deploying" => SettingsSection.Deploying,
        "preview" => SettingsSection.Preview,
        _ => SettingsSection.Assistant,
    };

    /// <summary>
    /// Called at the top of <c>App.QuitTime</c>: <c>Application.Exit</c> may
    /// end the process without raising this window's Closed, and a changed
    /// Account ID still in the field would never reach the trail.
    /// </summary>
    public static void NoteBeforeQuit()
    {
        try
        {
            _open?._deploying.NoteTheChange();
            _open?._assistant.DetachFromStores();
        }
        catch (Exception ex) { App.LogDiagnostic($"Settings at quit: {ex.Message}"); }
    }

    private SettingsWindow()
    {
        Title = "Settings";
        try { SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop(); } catch { }

        _assistant = new AssistantSettingsPane(App.Settings);
        _preview = new PreviewSettingsPane(App.Settings);
        _deploying = new DeployingSettingsPane(App.Settings);

        _assistantItem = new NavigationViewItem
        {
            Content = "Assistant",
            Icon = new FontIcon { Glyph = "" },   // a speech bubble
            Tag = SettingsSection.Assistant,
        };
        AutomationProperties.SetAutomationId(_assistantItem, "settingsAssistant");
        _previewItem = new NavigationViewItem
        {
            Content = Plantoir.Core.Models.PreviewStartPage.PaneTitle,
            Icon = new FontIcon { Glyph = Glyphs.Play },
            Tag = SettingsSection.Preview,
        };
        AutomationProperties.SetAutomationId(_previewItem, "settingsPreview");
        _deployingItem = new NavigationViewItem
        {
            Content = "Deploying",
            Icon = new FontIcon { Glyph = Glyphs.Send },
            Tag = SettingsSection.Deploying,
        };
        AutomationProperties.SetAutomationId(_deployingItem, "settingsDeploying");

        _navigation = new NavigationView
        {
            PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
            IsSettingsVisible = false,
            IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
            IsPaneToggleButtonVisible = false,
            OpenPaneLength = 200,
            IsTitleBarAutoPaddingEnabled = false,
        };
        _navigation.MenuItems.Add(_assistantItem);
        _navigation.MenuItems.Add(_previewItem);
        _navigation.MenuItems.Add(_deployingItem);
        _navigation.SelectionChanged += (_, args) =>
        {
            if (args.SelectedItem is NavigationViewItem { Tag: SettingsSection section }) ShowSection(section);
        };
        AutomationProperties.SetAutomationId(_navigation, "settingsWindow");

        // Content BEFORE WindowTheme.Apply: it hooks the root's theme changes
        // only when Content is already a FrameworkElement.
        Content = _navigation;
        WindowTheme.Apply(this);   // the title bar follows dark/light mode

        SizeAndPlace();
        try { AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Plantoir.ico")); }
        catch { /* a missing icon must never stop the window */ }

        // The line File ▸ Settings… has always written, once per opening.
        ActivityTrail.Note(
            ActivityTrail.Event.AppSettingsOpened,
            $"opened Settings — the assistant is set to {AssistModelChoice.Label(App.Settings.AssistantModelChoice).ToLowerInvariant()}");

        // Settings is MODELESS: a teacher who types an ID and clicks back into
        // the main window raises no LostFocus on the field (focus within this
        // window has not moved), so without this no line would be written
        // until Settings closed — perhaps hours later, or never before a crash.
        // Leaving the window is leaving the field.
        Activated += (_, e) =>
        {
            if (e.WindowActivationState == WindowActivationState.Deactivated) _deploying.NoteTheChange();
        };

        Closed += (_, _) =>
        {
            _deploying.NoteTheChange();
            _assistant.DetachFromStores();
            if (ReferenceEquals(_open, this)) _open = null;
        };
    }

    private void Select(SettingsSection section)
    {
        var item = section switch
        {
            SettingsSection.Deploying => _deployingItem,
            SettingsSection.Preview => _previewItem,
            _ => _assistantItem,
        };
        if (!ReferenceEquals(_navigation.SelectedItem, item)) _navigation.SelectedItem = item;
        // Directly as well: SelectionChanged is not promised before the view
        // has loaded, and showing the same section twice changes nothing.
        ShowSection(section);
    }

    private void ShowSection(SettingsSection section)
    {
        if (_shownOnce && section == _shown) return;
        _shownOnce = true;
        // Leaving Deploying is leaving the field: its change is recorded now.
        if (_shown == SettingsSection.Deploying && section != SettingsSection.Deploying) _deploying.NoteTheChange();
        _shown = section;
        (_navigation.Header, _navigation.Content) = section switch
        {
            SettingsSection.Deploying => ((object)"Deploying", (object)_deploying.Root),
            SettingsSection.Preview => (Plantoir.Core.Models.PreviewStartPage.PaneTitle, _preview.Root),
            _ => ("Assistant", _assistant.Root),
        };
        string remembered = section switch
        {
            SettingsSection.Deploying => "deploying",
            SettingsSection.Preview => "preview",
            _ => "assistant",
        };
        if (App.Settings.LastSettingsSection != remembered)
        {
            App.Settings.LastSettingsSection = remembered;
            try { App.Settings.Save(); } catch { }
        }
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    /// <summary>
    /// About 760 × 600 effective pixels, centred on the display's work area, with
    /// a minimum that keeps both sections readable. AppWindow speaks raw pixels,
    /// so the sizes are scaled by this window's DPI.
    /// </summary>
    private void SizeAndPlace()
    {
        double scale = 1.0;
        try { scale = Math.Max(1.0, GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96.0); }
        catch { }
        var workArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        int width = Math.Min((int)(760 * scale), workArea.Width);
        int height = Math.Min((int)(600 * scale), workArea.Height);
        AppWindow.Resize(new SizeInt32(width, height));
        AppWindow.Move(new PointInt32(workArea.X + (workArea.Width - width) / 2,
                                      workArea.Y + (workArea.Height - height) / 2));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = (int)(560 * scale);
            presenter.PreferredMinimumHeight = (int)(420 * scale);
            presenter.IsMinimizable = false;
        }
    }
}
