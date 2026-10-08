using System;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.UI.ViewManagement;

namespace Plantoir.Services;

/// <summary>
/// Makes a window's title bar follow the colour mode its content is drawn in:
/// a dark caption (light text, light caption buttons) when the content is dark,
/// a light one when it is light. Every <see cref="Window"/> the app creates
/// calls <see cref="Apply"/> once, right after <c>InitializeComponent</c>, and
/// <c>WindowThemeSourceTests</c> fails for one that does not — so a window
/// added later cannot quietly keep the white bar.
///
/// <para>Why this is needed at all: a WinUI 3 window that does not extend its
/// content into the title bar gets a caption drawn by the system, and the
/// system draws it LIGHT unless told otherwise — whatever Windows' own colour
/// mode is. So in dark mode the content went dark under a near-white strip
/// (ordered 2026-10-07, ships in Windows v1.4.4; the 2026-10-04 marketing pictures show it).</para>
///
/// <para>How: <see cref="AppWindowTitleBar.PreferredTheme"/> (Windows App SDK
/// 1.7+), set to Dark or Light from the content's <c>ActualTheme</c> — the
/// system's own dark and light captions, buttons and inactive states
/// included, so nothing here picks a colour. Hand-set
/// <c>AppWindow.TitleBar</c> colours were rejected: both windows sit on a
/// Mica backdrop, which is tinted by the wallpaper, so any fixed colour reads
/// as a stripe against it, and twelve colour slots (hover, pressed, inactive)
/// are twelve chances to look unlike Windows. <c>UseDefaultAppMode</c> was
/// rejected too: it follows the SYSTEM, not the content, and the marketing
/// capture (<see cref="MarketingShotCapturer"/>) sets the content's theme
/// directly — the bar has to follow what the window is actually showing.</para>
/// </summary>
public static class WindowTheme
{
    /// <summary>
    /// The caption theme for content drawn in <paramref name="content"/>.
    /// <c>Default</c> means the content has not resolved a theme of its own
    /// yet (not loaded), so the application's — which is the system's colour
    /// mode at start-up unless the app overrides it — decides.
    /// </summary>
    public static TitleBarTheme CaptionFor(ElementTheme content, ApplicationTheme application) => content switch
    {
        ElementTheme.Dark => TitleBarTheme.Dark,
        ElementTheme.Light => TitleBarTheme.Light,
        _ => application == ApplicationTheme.Dark ? TitleBarTheme.Dark : TitleBarTheme.Light,
    };

    /// <summary>
    /// Sets the window's caption from its content now, and again whenever the
    /// content's theme changes: a switch in Settings, or the marketing capture
    /// setting <c>RequestedTheme</c> on the root. Call once, after the
    /// window's content exists.
    /// </summary>
    public static void Apply(Window window)
    {
        Sync(window);
        if (window.Content is FrameworkElement root)
        {
            root.ActualThemeChanged += (_, _) => Sync(window);
            root.Loaded += (_, _) => Sync(window);
        }

        // A backstop for the live switch: ColorValuesChanged is raised on a
        // background thread when Windows' colour mode changes, so it is
        // marshalled back before anything touches the window. Held in a
        // local the handler closes over, and unhooked on Closed, so the
        // UISettings object lives exactly as long as the window.
        var settings = new UISettings();
        Windows.Foundation.TypedEventHandler<UISettings, object> handler =
            (_, _) => window.DispatcherQueue?.TryEnqueue(() => Sync(window));
        settings.ColorValuesChanged += handler;
        window.Closed += (_, _) => settings.ColorValuesChanged -= handler;
    }

    /// <summary>Sets the caption from the content's theme as it stands right now.</summary>
    public static void Sync(Window window)
    {
        try
        {
            var content = window.Content is FrameworkElement root
                ? (root.RequestedTheme != ElementTheme.Default ? root.RequestedTheme : root.ActualTheme)
                : ElementTheme.Default;
            window.AppWindow.TitleBar.PreferredTheme = CaptionFor(content, Application.Current.RequestedTheme);
        }
        catch (Exception ex)
        {
            // A window that is closing, or a Windows too old for the property,
            // keeps the caption it has; the bar is never worth a crash.
            App.LogDiagnostic($"WindowTheme.Sync: {ex.Message}");
        }
    }
}
