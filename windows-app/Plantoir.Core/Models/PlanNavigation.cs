namespace Plantoir.Core.Models;

/// <summary>
/// Where a click, a link or a page's own request may go from a plan shown on
/// the Planning tab (#801 item 3): <c>shared-rules.json</c> →
/// <c>unitPlanning.tab.navigationCases</c>, on every navigation in every
/// frame. Walked by <c>PlanNavigationTests</c>, twice (against a map of links,
/// and on disk with junctions). The mac's <c>PlanNavigation.decide</c>.
/// </summary>
/// <remarks>
/// <para>A plan is written by an outside assistant, so its pages are content
/// Plantoir did not write. A page in the planning folder may open another page
/// or file in it; a link the teacher CLICKS to the web or to an email address
/// opens in their own browser or mail app; everything else is refused without
/// a word. Only a click goes outside: a page that sends itself to the web (a
/// meta refresh, a frame's address) is refused, or a plan could open the
/// teacher's browser just by being shown.</para>
///
/// <para><b>On Windows the plan's own pages are SERVED addresses</b>
/// (<see cref="LocalSiteGuard"/>): <c>https://</c> at the guard's host, which
/// are the planning folder's files and are judged by the inside check, never
/// opened outside. A <c>file:</c> address is judged by the contract's rule too
/// (inside, after links, is load), though a served page's click on one raises
/// no navigation in WebView2 at all (measured by the plan review's probe; plan
/// review L5), so no contract case that writes one inside the folder should be
/// expected to load on Windows. The adapter (<c>GuardedSite</c>) answers a <c>Load</c> of
/// a <c>file:</c> address by loading the SERVED address of the same path, so
/// that no page is ever read through Chromium's own file access.</para>
///
/// <para><paramref name="address"/> is the web view's own STRING for the
/// target, passed as it came (the #811 plan, item 1): decoded once, here.</para>
/// </remarks>
public static class PlanNavigation
{
    /// <summary>The schemes a click may hand to another app.</summary>
    public static readonly IReadOnlySet<string> SchemesOpenedOutside =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "http", "https", "mailto" };

    /// <summary>
    /// The decision for <paramref name="address"/>, asked for by the teacher's
    /// click when <paramref name="isUserInitiated"/>, in a new window when
    /// <paramref name="isNewWindow"/>. Never <see cref="LocalPageDecision.HandToTheApp"/>.
    /// </summary>
    public static LocalPageDecision Decide(string address, bool isNewWindow, bool isUserInitiated, LocalSiteGuard guard)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var uri)) return LocalPageDecision.Refuse;
        string scheme = uri.Scheme;
        if (string.Equals(scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
            && string.Equals(uri.Host, guard.Host, StringComparison.OrdinalIgnoreCase))
            return guard.IsInsideAddress(address) ? (isNewWindow ? LocalPageDecision.LoadHere : LocalPageDecision.Load)
                                                  : LocalPageDecision.Refuse;
        // Our own host on any other scheme is not the plan, and not the web either.
        if (string.Equals(uri.Host, guard.Host, StringComparison.OrdinalIgnoreCase)) return LocalPageDecision.Refuse;
        if (SchemesOpenedOutside.Contains(scheme))
            return isUserInitiated ? LocalPageDecision.OpenOutside : LocalPageDecision.Refuse;
        if (!string.Equals(scheme, Uri.UriSchemeFile, StringComparison.OrdinalIgnoreCase)) return LocalPageDecision.Refuse;
        if (LocalSiteGuard.PathOfFileAddress(address) is not { } path || !guard.IsInside(path)) return LocalPageDecision.Refuse;
        return isNewWindow ? LocalPageDecision.LoadHere : LocalPageDecision.Load;
    }
}
