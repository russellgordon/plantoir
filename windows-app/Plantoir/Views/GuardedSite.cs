using System;
using System.IO;
using Microsoft.Web.WebView2.Core;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// A web view that shows LOCAL pages and nothing else: the Planning tab's plans
/// (#801) and, with its own root, host and rules, a section's coverage map
/// (#811). It puts <c>whatAPageMayRead</c>'s three guards
/// (<c>contracts/shared-rules.json</c> → <c>unitPlanning.tab.whatAPageMayRead</c>)
/// on one <see cref="CoreWebView2"/>: every request answered by the app itself
/// through <see cref="LocalSiteGuard"/> (nothing is mapped to the host, so a
/// request the handler does not answer goes nowhere), every navigation in
/// every frame decided by the tab's rule, no script, nothing kept, and no
/// route to the network (<see cref="LocalPagesEnvironment"/>'s dead proxy).
/// </summary>
/// <remarks>
/// <para><b>Written against <c>Microsoft.Web.WebView2.Core</c> only</b>, no
/// WinUI type, so <c>Plantoir.GuardProbe</c> compiles this same file against
/// the WinForms flavour of the same SDK (1.0.3179.45) and the gate
/// (<c>GuardedSiteTests</c>) drives the REAL browser through it with no window
/// on screen (790 plan review M1). The two flavours differ in one call here:
/// a response's body is a <see cref="Stream"/> in .NET and an
/// <c>IRandomAccessStream</c> in WinRT (<c>PLANTOIR_GUARD_PROBE</c>).</para>
///
/// <para><b>What the Coverage tab reuses</b> (the #811 plan's list, items 1 to
/// 8): <see cref="Attach"/> takes the guard (its root, host and file types),
/// the decision function, a nullable <see cref="Options.OpenOutside"/> (null
/// hands nothing to the shell, <c>mailto:</c> included), a nullable
/// <see cref="Options.HandToTheApp"/> raised only from a top-level navigation
/// or a new-window request (never a frame), with the web view's own STRING for
/// the address; its own CSP header; whether Print is offered
/// (<see cref="Options.AllowPrint"/>); <see cref="FollowTheme"/>; and a root
/// that does not exist yet (the guard refuses everything until it does).</para>
/// </remarks>
public sealed class GuardedSite
{
    /// <summary>
    /// What a page may do, per view. <paramref name="Decide"/> is called with the
    /// web view's own string for the target, whether it asks for a new window,
    /// and whether the teacher clicked it.
    /// </summary>
    public sealed record Options(
        Func<string, bool, bool, LocalPageDecision> Decide,
        Action<Uri>? OpenOutside,
        Action<string>? HandToTheApp,
        string ContentSecurityPolicy,
        bool AllowPrint);

    /// <summary>
    /// The plans' header (defence in depth beside scripts off): their own
    /// pages, stylesheets, fonts and pictures, from the host alone. Sent on
    /// HTML only: on a PDF's own response <c>object-src 'none'</c> could stop
    /// Chromium's viewer drawing it (790 plan review L3).
    /// </summary>
    /// <remarks>
    /// Each kind named, and NO <c>default-src</c>: measured with
    /// <c>Plantoir.GuardProbe</c> (WebView2 1.0.3179.45, this PC), a page sent
    /// with <c>default-src 'self'</c> raised no navigation at all for a link to
    /// the web clicked through the DevTools protocol (3 runs of 3), so the
    /// click did nothing; the same page with these directives raised
    /// <c>NavigationStarting</c> as a click. Whether a real mouse is stopped
    /// the same way was not measured; the header is not worth the doubt.
    /// </remarks>
    public const string PlansContentSecurityPolicy =
        "script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; worker-src 'none'; "
        + "manifest-src 'none'; connect-src 'none'; img-src 'self' data:; font-src 'self' data:; "
        + "style-src 'self' 'unsafe-inline'; frame-src 'self'; media-src 'self'";

    private readonly CoreWebView2 _core;
    private readonly CoreWebView2Environment _environment;
    private readonly LocalSiteGuard _guard;
    private readonly Options _options;

    private GuardedSite(CoreWebView2 core, CoreWebView2Environment environment, LocalSiteGuard guard, Options options)
    {
        _core = core;
        _environment = environment;
        _guard = guard;
        _options = options;
    }

    /// <summary>The guard this view reads through.</summary>
    public LocalSiteGuard Guard => _guard;

    /// <summary>A request answered: its address, and whether a file was served. For a test or a diagnostic; never the trail.</summary>
    public event Action<string, bool>? Answered;

    /// <summary>A navigation decided: its address, and the decision. For a test or a diagnostic.</summary>
    public event Action<string, LocalPageDecision>? Decided;

    /// <summary>
    /// Puts the guards on <paramref name="core"/>, or returns null when any of
    /// them could not be put in place, and then the caller shows
    /// <c>cannotShowTitle</c> and loads nothing (<c>whatAPageMayRead</c>: "if the
    /// block cannot be put in place no page is shown").
    /// </summary>
    public static GuardedSite? Attach(CoreWebView2 core, CoreWebView2Environment environment, LocalSiteGuard guard,
                                      Options options, Action<string>? diagnostic = null)
    {
        try
        {
            var site = new GuardedSite(core, environment, guard, options);
            var settings = core.Settings;
            settings.IsScriptEnabled = false;
            settings.IsWebMessageEnabled = false;
            settings.AreDefaultScriptDialogsEnabled = false;
            settings.AreHostObjectsAllowed = false;
            settings.AreDevToolsEnabled = false;
            settings.IsStatusBarEnabled = false;
            settings.IsPasswordAutosaveEnabled = false;
            settings.IsGeneralAutofillEnabled = false;
            // Its "open in new window", "save as", "print" and "inspect" are doors.
            settings.AreDefaultContextMenusEnabled = false;
            // SmartScreen would send the address, which here carries the
            // teacher's folder path, to a service (790 plan review H1).
            settings.IsReputationCheckingRequired = false;
            // Ctrl+S is the browser's Save As, Ctrl+P its print, F5 a reload
            // that skips the tab's own look again (790 plan review M2; #811
            // review M4): the tab's own buttons do what is wanted.
            settings.AreBrowserAcceleratorKeysEnabled = false;
            settings.IsSwipeNavigationEnabled = false;
            settings.HiddenPdfToolbarItems = options.AllowPrint
                ? CoreWebView2PdfToolbarItems.Save | CoreWebView2PdfToolbarItems.SaveAs
                : CoreWebView2PdfToolbarItems.Save | CoreWebView2PdfToolbarItems.SaveAs | CoreWebView2PdfToolbarItems.Print;

            // Every request of every kind from every frame (the three-argument
            // overload: the two-argument one sees the page's own document only
            // for some kinds).
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All,
                                               CoreWebView2WebResourceRequestSourceKinds.All);
            core.WebResourceRequested += (_, e) => site.Answer(e);
            core.NavigationStarting += (_, e) => site.OnNavigation(e);
            core.FrameNavigationStarting += (_, e) => site.OnFrameNavigation(e);
            core.NewWindowRequested += (_, e) => site.OnNewWindow(e);
            core.DownloadStarting += (_, e) => e.Cancel = true;
            core.LaunchingExternalUriScheme += (_, e) => e.Cancel = true;
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.BasicAuthenticationRequested += (_, e) => e.Cancel = true;
            core.SaveAsUIShowing += (_, e) => e.Cancel = true;
            core.SaveFileSecurityCheckStarting += (_, e) => e.CancelSave = true;
            return site;
        }
        catch (Exception error)
        {
            diagnostic?.Invoke($"GuardedSite: could not put the guards in place: {error.Message}");
            return null;
        }
    }

    /// <summary>
    /// The page's light or dark colours follow the APP (#811 plan item 4), not
    /// only Windows: <c>prefers-color-scheme</c> in a WebView2 reads its
    /// profile's preferred scheme.
    /// </summary>
    public void FollowTheme(CoreWebView2PreferredColorScheme scheme)
    {
        try { _core.Profile.PreferredColorScheme = scheme; }
        catch { /* an older runtime without profiles keeps Windows' own */ }
    }

    /// <summary>Loads <paramref name="path"/> through the guard; false when the guard cannot name it.</summary>
    public bool Show(string path)
    {
        if (_guard.AddressOf(path) is not { } address) return false;
        _core.Navigate(address);
        return true;
    }

    /// <summary>Reads the page on screen from the disk again (every response says no-store).</summary>
    public void Reload() => _core.Reload();

    // ---- Requests ---------------------------------------------------------------

    private void Answer(CoreWebView2WebResourceRequestedEventArgs e)
    {
        string address = e.Request.Uri;
        try
        {
            if (_guard.PathOf(address) is not null && _guard.Answer(address) is LocalSiteGuard.Verdict.Serve serve)
            {
                // Read from the one handle the checks were made on, then let
                // it go: nothing of the teacher's stays open behind a page.
                var body = new MemoryStream();
                using (serve.Content) serve.Content.CopyTo(body);
                body.Position = 0;
                string headers = "Content-Type: " + serve.ContentType
                                 + "\r\nCache-Control: no-store"
                                 + "\r\nX-Content-Type-Options: nosniff";
                if (_options.ContentSecurityPolicy.Length > 0
                    && serve.ContentType.StartsWith("text/html", StringComparison.OrdinalIgnoreCase))
                    headers += "\r\nContent-Security-Policy: " + _options.ContentSecurityPolicy;
                e.Response = Response(body, 200, "OK", headers);
                Answered?.Invoke(address, true);
                return;
            }
        }
        catch { /* anything unexpected is a refusal, below */ }
        e.Response = Response(null, 403, "Forbidden", "Cache-Control: no-store");
        Answered?.Invoke(address, false);
    }

    private CoreWebView2WebResourceResponse Response(MemoryStream? body, int status, string reason, string headers)
    {
#if PLANTOIR_GUARD_PROBE
        return _environment.CreateWebResourceResponse(body, status, reason, headers);
#else
        return _environment.CreateWebResourceResponse(body?.AsRandomAccessStream(), status, reason, headers);
#endif
    }

    // ---- Navigations ------------------------------------------------------------

    private LocalPageDecision Decide(string address, bool newWindow, bool clicked)
    {
        LocalPageDecision decision;
        try { decision = _options.Decide(address, newWindow, clicked); }
        catch { decision = LocalPageDecision.Refuse; }
        Decided?.Invoke(address, decision);
        return decision;
    }

    private void OnNavigation(CoreWebView2NavigationStartingEventArgs e)
    {
        var decision = Decide(e.Uri, false, e.IsUserInitiated);
        switch (decision)
        {
            case LocalPageDecision.Load when IsServed(e.Uri):
                return;
            case LocalPageDecision.Load or LocalPageDecision.LoadHere:
                // A file: address the rule lets through is loaded at its SERVED
                // address, so no page is ever read by Chromium's own file
                // access (PlanNavigation's remarks).
                e.Cancel = true;
                LoadServedFrom(e.Uri);
                return;
            case LocalPageDecision.OpenOutside:
                e.Cancel = true;
                OpenOutside(e.Uri);
                return;
            case LocalPageDecision.HandToTheApp:
                e.Cancel = true;
                _options.HandToTheApp?.Invoke(e.Uri);
                return;
            default:
                e.Cancel = true;
                return;
        }
    }

    private void OnFrameNavigation(CoreWebView2NavigationStartingEventArgs e)
    {
        // A frame is never handed to the app and never sent outside: the
        // same link not clicked (a refresh, a frame's own address) is
        // refused (navigationCases.rule, coverageTab's linkRule). Only a page
        // of the folder at its served address loads in a frame.
        var decision = Decide(e.Uri, false, false);
        if (decision == LocalPageDecision.Load && IsServed(e.Uri)) return;
        e.Cancel = true;
    }

    private void OnNewWindow(CoreWebView2NewWindowRequestedEventArgs e)
    {
        // An app's web view opens no windows: a target=_blank link loads here,
        // so Back returns (navigationCases' loadHere).
        e.Handled = true;
        var decision = Decide(e.Uri, true, e.IsUserInitiated);
        switch (decision)
        {
            case LocalPageDecision.Load or LocalPageDecision.LoadHere:
                if (IsServed(e.Uri)) _core.Navigate(e.Uri);
                else LoadServedFrom(e.Uri);
                return;
            case LocalPageDecision.OpenOutside:
                OpenOutside(e.Uri);
                return;
            case LocalPageDecision.HandToTheApp:
                _options.HandToTheApp?.Invoke(e.Uri);
                return;
        }
    }

    private bool IsServed(string address) => _guard.PathOf(address) is not null;

    private void LoadServedFrom(string address)
    {
        if (LocalSiteGuard.PathOfFileAddress(address) is { } path && _guard.AddressOf(path) is { } served)
            _core.Navigate(served);
    }

    private void OpenOutside(string address)
    {
        if (_options.OpenOutside is null) return;
        if (Uri.TryCreate(address, UriKind.Absolute, out var uri)) _options.OpenOutside(uri);
    }
}
