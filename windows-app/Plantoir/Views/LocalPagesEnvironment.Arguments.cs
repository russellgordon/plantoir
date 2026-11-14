namespace Plantoir.Views;

/// <summary>
/// The one WebView2 environment the local-page views share (the Planning tab;
/// #811's Coverage tab), apart from the section preview's: its own user-data
/// folder and a proxy that goes nowhere (790 plan review H1). Kept in a file
/// with no WinUI type so <c>Plantoir.GuardProbe</c> measures exactly these
/// arguments.
/// </summary>
public static partial class LocalPagesEnvironment
{
    /// <summary>
    /// Every connection Chromium makes goes to a proxy at 127.0.0.1:9, where
    /// nothing answers, loopback included (<c>&lt;-loopback&gt;</c>). Measured by
    /// the plan review's probe: a <c>&lt;link rel=preconnect&gt;</c> opened two
    /// TCP connections and a <c>&lt;meta refresh&gt;</c> to the web four (two of
    /// them before <c>NavigationStarting</c>), none of which raised
    /// <c>WebResourceRequested</c>; with these arguments, none. The app's own
    /// responses are made before any proxy is asked, so the plans still load.
    /// </summary>
    public const string BrowserArguments = "--proxy-server=127.0.0.1:9 --proxy-bypass-list=<-loopback>";

    /// <summary>The environment's own user-data folder, under the app's data folder.</summary>
    public const string UserDataFolderName = "WebView2-local-pages";

    /// <summary>The InPrivate profile each kind of page is shown in: nothing is kept between views.</summary>
    public const string PlansProfile = "plans";

    /// <summary>The Coverage tab's profile (#811).</summary>
    public const string CoverageProfile = "coverage";
}
