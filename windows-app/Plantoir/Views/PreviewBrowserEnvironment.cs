using System;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;

namespace Plantoir.Views;

/// <summary>
/// The section preview's own WebView2 environment and view settings (#913):
/// what the preview's browser engine would otherwise send Microsoft on its own
/// account, turned off where Microsoft documents a per-view or per-environment
/// setting for it. Russell's rulings on #913, 2026-11-25.
/// </summary>
/// <remarks>
/// <para><b>Crash reports.</b> <c>IsCustomCrashReportingEnabled = true</c>:
/// "Windows won't send crash data to the Microsoft endpoint"
/// (https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/data-privacy
/// and https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2environmentoptions).
/// A run without a crash sends nothing either way, so no measurement can show
/// this one; the source test pins it.</para>
/// <para><b>SmartScreen.</b> <c>IsReputationCheckingRequired = false</c> on the
/// view (https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2settings.isreputationcheckingrequired).
/// It applies to every view on the same user data folder, and is on if any
/// view leaves it true; every view on that folder is a preview, made this way
/// (through <c>EnsurePreviewBrowserAsync</c>, before its first page).</para>
/// <para><b>Left alone, on purpose</b> (documented in documentation 12, #913):
/// the experiment configuration, the component updater and proxy
/// auto-detection. No per-app setting exists for them on Microsoft's WebView2
/// pages, and no policy or browser flag is used.</para>
/// <para>The user data folder is not given here: <c>Program.Main</c> sets
/// <c>WEBVIEW2_USER_DATA_FOLDER</c>, which overrides the folder an environment
/// is created with. One environment per process, shared by every section
/// window: environments with different options cannot share one folder's
/// browser process. A failure is not kept; the next view asks again.</para>
/// </remarks>
public static class PreviewBrowserEnvironment
{
    private static Task<CoreWebView2Environment>? _creating;

    /// <summary>The preview's environment, made on first use.</summary>
    public static Task<CoreWebView2Environment> GetAsync()
    {
        if (_creating is { IsFaulted: false, IsCanceled: false } existing) return existing;
        try
        {
            var options = new CoreWebView2EnvironmentOptions { IsCustomCrashReportingEnabled = true };
            _creating = CoreWebView2Environment.CreateWithOptionsAsync(null, null, options).AsTask();
        }
        catch (Exception error)
        {
            _creating = Task.FromException<CoreWebView2Environment>(error);
        }
        return _creating;
    }

    /// <summary>The view's settings, given before the preview's first load.</summary>
    public static void ApplyViewSettings(CoreWebView2 core)
    {
        core.Settings.IsReputationCheckingRequired = false;
    }
}
