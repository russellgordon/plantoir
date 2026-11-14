namespace Plantoir.Core.Models;

/// <summary>
/// What a guarded local page view (the Planning tab, #801; the Coverage tab,
/// #811) does with one navigation: <c>unitPlanning.tab.navigationCases</c>'
/// four answers, and the Coverage tab's fifth. The mac's
/// <c>PlanNavigation.Decision</c>.
/// </summary>
public enum LocalPageDecision
{
    /// <summary>Let it load where it was going.</summary>
    Load,

    /// <summary>It asked for a new window: load it in this view instead, so Back returns (an app's web view opens no windows).</summary>
    LoadHere,

    /// <summary>Hand it to the default browser or mail app. Only ever for a click.</summary>
    OpenOutside,

    /// <summary>Cancel it, silently.</summary>
    Refuse,

    /// <summary>Cancel it and hand it to the app itself: a click on a code in the Coverage tab's map (#811). A plan never gets this.</summary>
    HandToTheApp,
}
