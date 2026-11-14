using System;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;
using Plantoir.Core.Models;

namespace Plantoir.Views;

public static partial class LocalPagesEnvironment
{
    private static Task<CoreWebView2Environment>? _creating;

    /// <summary>
    /// The one environment, made the first time a local-page view asks for it
    /// and shared by every one after, on the interface thread. A failure is not
    /// kept: the next view asks again.
    /// </summary>
    /// <remarks>
    /// <para><b>Measured</b> (<c>Plantoir.GuardProbe --env-check</c>, this PC,
    /// WebView2 1.0.3179.45): <c>WEBVIEW2_USER_DATA_FOLDER</c>, which
    /// <c>Program.Main</c> sets for the section preview, OVERRIDES the folder an
    /// environment is created with, and a second environment with other
    /// arguments on the preview's folder failed to start
    /// (<c>0x8007139F</c>, "the group or resource is not in the correct
    /// state"). With the variable taken away for the one call and put back,
    /// both environments live in one process, each with its own browser
    /// process. The variable is read during the call itself, before it
    /// returns, which is why taking it away around the call is enough.</para>
    /// </remarks>
    public static Task<CoreWebView2Environment> GetAsync()
    {
        if (_creating is { IsFaulted: false, IsCanceled: false } existing) return existing;
        string? previewFolder = Environment.GetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER");
        Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", null);
        try
        {
            var options = new CoreWebView2EnvironmentOptions { AdditionalBrowserArguments = BrowserArguments };
            _creating = CoreWebView2Environment.CreateWithOptionsAsync("", AppDataRoot.Combine(UserDataFolderName), options).AsTask();
        }
        catch (Exception error)
        {
            _creating = Task.FromException<CoreWebView2Environment>(error);
        }
        finally
        {
            Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", previewFolder);
        }
        return _creating;
    }

    /// <summary>The InPrivate controller a view of <paramref name="profile"/> is made with: nothing kept between views.</summary>
    public static CoreWebView2ControllerOptions ControllerOptions(CoreWebView2Environment environment, string profile)
    {
        var options = environment.CreateCoreWebView2ControllerOptions();
        options.IsInPrivateModeEnabled = true;
        options.ProfileName = profile;
        return options;
    }
}
