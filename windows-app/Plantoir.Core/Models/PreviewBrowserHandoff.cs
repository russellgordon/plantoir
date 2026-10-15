using Newtonsoft.Json.Linq;

namespace Plantoir.Core.Models;

/// <summary>
/// Hands a page from Plantoir's own preview pane to the teacher's web browser
/// (#496; the mac's #454 <c>PreviewBrowserHandoff.swift</c>, ported; the
/// contract's <c>printablePages.previewPane</c>). Two doors, both to the
/// default browser:
/// <list type="bullet">
/// <item>the page's own print code finds a <c>plantoirPrint</c> message
/// handler and posts <c>{mode, paper, url}</c>; the page is opened in the
/// browser with <c>#plantoir-print=&lt;mode&gt;&amp;paper=&lt;paper&gt;</c>,
/// which makes the handout on that paper and prints it at once;</item>
/// <item>any link that asks for a new window — a page's own PDF among them —
/// is opened in the browser instead of in a bare WebView2 popup.</item>
/// </list>
/// The WebView2 wiring is in <c>SectionDetailView</c>; everything a test can
/// hold is here.
/// </summary>
/// <remarks>
/// <para><b>Why new windows go to the browser on Windows too.</b> Unhandled,
/// WebView2 opens a target=_blank link in a bare popup window owned by
/// Plantoir's process: not the teacher's browser, with no address bar or
/// bookmarks, closed when the app closes, and unlike the mac (the director's
/// decision for batch 5, 2026-10-15).</para>
/// <para><b>Why Print is handed over, by an app-injected shim.</b> The shared
/// page code (<c>print.inline.ts</c>) looks for
/// <c>window.webkit.messageHandlers.plantoirPrint</c>, which WebKit gives the
/// mac. Windows injects exactly that shape, forwarding to
/// <c>window.chrome.webview.postMessage</c> (<see cref="PrintShim"/>), so no
/// shared file changes (option (i) of the plan). The risk named — page code
/// reading <c>window.webkit</c> to detect Safari — was checked: nothing in
/// the bundled Quartz, its scripts or KaTeX reads it. REJECTED for now:
/// option (ii), a hook in print.inline.ts gated on a Windows-only flag, which
/// would be a shared change for no difference a teacher could see.</para>
/// </remarks>
public static class PreviewBrowserHandoff
{
    /// <summary>The name the page's print code looks for (print.inline.ts).</summary>
    public const string MessageName = "plantoirPrint";

    /// <summary>The ways of printing a page can ask for, in the menu's order (<c>printablePages.modes.list</c>).</summary>
    public static readonly IReadOnlyList<string> Modes = ["questionsOnly", "answersOnly", "withAnswersAtTheEnd"];

    /// <summary>The papers a page can ask for (<c>printablePages.paper</c>).</summary>
    public static readonly IReadOnlyList<string> Papers = ["portrait", "landscape"];

    /// <summary>Why a page went to the browser.</summary>
    public enum Why { PrintHandout, NewWindow }

    /// <summary>
    /// Injected into every document the preview pane loads, before the
    /// page's own scripts: the mac's message-handler shape, forwarding to
    /// WebView2's own channel. Only where WebView2's channel exists, and
    /// never over a <c>window.webkit</c> the page already has.
    /// </summary>
    public const string PrintShim =
        "(function(){try{if(!window.chrome||!window.chrome.webview)return;" +
        "var w=window.webkit=window.webkit||{};w.messageHandlers=w.messageHandlers||{};" +
        "if(w.messageHandlers.plantoirPrint)return;" +
        "w.messageHandlers.plantoirPrint={postMessage:function(m){window.chrome.webview.postMessage({plantoirPrint:m});}};" +
        "}catch(e){}})();";

    /// <summary>
    /// The address to open for a print request, or null when the request is
    /// not one this app should act on: only the preview's own pages, served
    /// from this PC, and only a way of printing and a paper the contract names.
    /// </summary>
    public static Uri? PrintAddress(string pageAddress, string mode, string paper)
    {
        if (!Modes.Contains(mode) || !Papers.Contains(paper)) return null;
        if (!Uri.TryCreate(pageAddress, UriKind.Absolute, out var page) || !IsThePreviews(page)) return null;
        var builder = new UriBuilder(page) { Fragment = "plantoir-print=" + mode + "&paper=" + paper };
        return builder.Uri;
    }

    /// <summary>
    /// The address to open for a message the page posted
    /// (<c>{plantoirPrint: {mode, paper, url}}</c>), and its mode and paper;
    /// null for anything else. A page built before #499 sends no paper:
    /// portrait, as it printed.
    /// </summary>
    public static (Uri Address, string Mode, string Paper)? FromMessage(string messageJson)
    {
        try
        {
            if (JToken.Parse(messageJson) is not JObject outer || outer[MessageName] is not JObject message) return null;
            if (message["url"] is not JValue { Type: JTokenType.String } url || message["mode"] is not JValue { Type: JTokenType.String } mode)
                return null;
            string paper = message["paper"] is JValue { Type: JTokenType.String } given ? (string)given! : "portrait";
            return PrintAddress((string)url!, (string)mode!, paper) is { } address ? (address, (string)mode!, paper) : null;
        }
        catch { return null; }
    }

    /// <summary>Whether a new-window request is one to hand over (http, https, mailto); anything else is dropped.</summary>
    public static bool IsHandedOver(Uri target) =>
        target.Scheme is "http" or "https" or "mailto";

    /// <summary>
    /// The trail's words (<c>preview page opened in the web browser</c>):
    /// why, and the slug of the PAGE the teacher was on — never where a link
    /// led. A link's destination is something the teacher wrote, and a
    /// shared-document address is a key to that document (the mac's
    /// implementation review S2), so a new-window link says only whether it
    /// was the page's own PDF, a page of the site, or another site.
    /// </summary>
    public static string TrailWords(Uri? page, Uri target, Why why, string mode = "", string paper = "portrait")
    {
        string place = "an unknown page";
        if (page is not null && IsThePreviews(page))
        {
            place = Uri.UnescapeDataString(page.AbsolutePath).TrimStart('/');
            if (place.Length == 0) place = "the front page";
        }
        string reason = "a link to another site";
        if (why == Why.PrintHandout)
        {
            reason = "to print it " + ModeWords(mode);
            if (paper == "landscape") reason += ", on landscape paper";
        }
        else if (IsThePreviews(target))
        {
            reason = target.AbsolutePath.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)
                ? "the page's own PDF"
                : "a link to another page of the site";
        }
        return "preview page opened in the web browser — " + reason + " (" + place + ")";
    }

    /// <summary>Whether an address is one of the preview's own pages, served from this PC.</summary>
    public static bool IsThePreviews(Uri address) =>
        address.IsAbsoluteUri && address.Scheme is "http" or "https"
        && (address.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) || address.Host == "127.0.0.1");

    /// <summary>
    /// The address as the browser should get it: localhost rewritten to
    /// 127.0.0.1, as Open in Browser does (browsers try IPv6 first; the
    /// preview listens on IPv4 loopback only).
    /// </summary>
    public static Uri ForTheBrowser(Uri address)
    {
        if (!IsThePreviews(address) || address.Host != "localhost") return address;
        return new UriBuilder(address) { Host = "127.0.0.1" }.Uri;
    }

    private static string ModeWords(string mode) => mode switch
    {
        "questionsOnly" => "questions only",
        "answersOnly" => "answers only",
        _ => "with the answers at the end",
    };
}
