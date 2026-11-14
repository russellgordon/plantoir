namespace Plantoir.Core.Models;

/// <summary>
/// Open in Browser on the Planning tab (#820, the mac's #803): which page the
/// button would hand the teacher's default web browser, or why it cannot —
/// <c>shared-rules.json</c> → <c>unitPlanning.tab.openInBrowser</c>, walked by
/// <c>PlanInTheBrowserTests</c> twice (a map of links, and on disk). Only a
/// page or a PDF inside the course's planning folder is ever handed over;
/// anything else is refused here, before a browser is asked.
/// </summary>
/// <remarks>
/// <para>This is the RULE and its words. Asking the default browser by name and
/// starting it, and the trail line once it has answered, are 790b (#820 items
/// 3 and 4): the event "opened a unit plan in the browser" is first written
/// there, and stays ledgered until then.</para>
///
/// <para>On Windows the page on screen is a SERVED address
/// (<see cref="LocalSiteGuard"/>); a <c>file:</c> address is read too, as the
/// contract writes some cases with one. The browser is handed the NOMINAL path
/// (<see cref="Answer.Path"/>, as a <c>file:</c> URI in
/// <see cref="Answer.FileUri"/>), without any <c>#</c> or <c>?</c> part, at the
/// top of the page (#803 review L1).</para>
/// </remarks>
public static class PlanInTheBrowser
{
    /// <summary>Which kind of page was opened, for the trail: never its name.</summary>
    public enum Kind { AllPlans, Plan, Correlation, File }

    /// <summary>Why nothing can be opened.</summary>
    public enum Refusal { NothingToOpen, OutsideThePlan, PageIsGone, NotAPage }

    /// <summary>What the button would open (a nominal path and its kind), or why it cannot.</summary>
    public sealed record Answer(string? Path, Kind? Kind, Refusal? Refusal)
    {
        /// <summary>The <c>file:</c> address handed to the browser, escaped so a space or a quote in a name stays one argument.</summary>
        public string? FileUri => Path is null ? null : new Uri(Path).AbsoluteUri;
    }

    /// <summary>A unit's correlation page, beside its plan.</summary>
    public const string CorrelationPageName = "correlation.html";

    /// <summary>
    /// What a plan is made of that a browser shows: the pages the template
    /// writes and the PDFs a unit links. Anything else is refused, failing
    /// closed: on Windows that is what keeps a <c>.cmd</c>, a <c>.lnk</c>, a
    /// <c>.url</c> or an <c>.exe</c> an assistant wrote from ever being handed on.
    /// </summary>
    public static readonly IReadOnlySet<string> PageExtensions =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".html", ".htm", ".pdf" };

    // activityTrail.mustRecord "opened a unit plan in the browser", after "{course} · ".
    public const string TrailLine = "opened {what} in the browser";
    public const string CouldNotOpenTrailLine = "could not open {what} in the browser";
    public const string AllPlansWhat = "the list of plans";
    public const string PlanWhat = "a unit's plan";
    public const string CorrelationWhat = "a unit's correlation page";
    public const string FileWhat = "a file from a unit's plan";

    /// <summary>
    /// <c>openInBrowser.cases</c>: the page on screen (the web view's own
    /// address, which follows a link the teacher clicked), or, before a page
    /// has loaded, the page chosen in the popup — never the chosen one in
    /// place of a page on screen. Opened only when it is this view's served
    /// address or this PC's own <c>file:</c> address, inside the planning
    /// folder after <c>..</c> and every link are followed
    /// (<see cref="LocalSiteGuard.IsInside"/>), a page or a PDF both as written
    /// and as it resolves, and a file that is there.
    /// </summary>
    public static Answer PageToOpen(string? onScreen, string? chosen, LocalSiteGuard guard)
    {
        string? candidate = onScreen ?? chosen;
        if (candidate is null) return Refused(Refusal.NothingToOpen);
        string? path = guard.PathOf(candidate) ?? (IsFileAddress(candidate) ? LocalSiteGuard.PathOfFileAddress(candidate) : null);
        if (path is null || !guard.IsInside(path)) return Refused(Refusal.OutsideThePlan);
        string real = guard.RealPath(path);
        if (!IsAPage(path) || !IsAPage(real)) return Refused(Refusal.NotAPage);
        switch (guard.IsFolder(path))
        {
            case null: return Refused(Refusal.PageIsGone);
            case true: return Refused(Refusal.NothingToOpen);
        }
        return new Answer(path, KindOf(path, guard), null);
    }

    private static Answer Refused(Refusal refusal) => new(null, null, refusal);

    private static bool IsFileAddress(string address) =>
        address.StartsWith("file:", StringComparison.OrdinalIgnoreCase);

    /// <summary>Whether a path ends in one of <see cref="PageExtensions"/>, in any case.</summary>
    public static bool IsAPage(string path) => PageExtensions.Contains(System.IO.Path.GetExtension(path));

    /// <summary>The kind of page <paramref name="path"/> is, by where it sits in the planning folder once links are followed.</summary>
    public static Kind KindOf(string path, LocalSiteGuard guard)
    {
        var page = guard.RealPath(path).Split('\\', StringSplitOptions.RemoveEmptyEntries);
        var folder = guard.RealPath(guard.Root).Split('\\', StringSplitOptions.RemoveEmptyEntries);
        if (page.Length <= folder.Length) return Kind.File;
        var rest = page[folder.Length..];
        if (rest.Length == 1 && Is(rest[0], PlanningTab.PageName)) return Kind.AllPlans;
        if (rest.Length == 2 && Is(rest[1], PlanningTab.PageName)) return Kind.Plan;
        if (rest.Length == 2 && Is(rest[1], CorrelationPageName)) return Kind.Correlation;
        return Kind.File;

        static bool Is(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>The button's help: what it does, or why it is dimmed.</summary>
    public static string HelpText(Answer answer) =>
        answer.Refusal is { } refusal ? Sentence(refusal) : PlanningTabWording.OpenInBrowserHelp;

    /// <summary>The sentence a teacher reads for a refusal.</summary>
    public static string Sentence(Refusal refusal) => refusal switch
    {
        Refusal.NothingToOpen => PlanningTabWording.OpenInBrowserNothingToOpen,
        Refusal.OutsideThePlan => PlanningTabWording.OpenInBrowserOutsideThePlan,
        Refusal.PageIsGone => PlanningTabWording.OpenInBrowserPageIsGone,
        _ => PlanningTabWording.OpenInBrowserNotAPage,
    };

    /// <summary>As the contract writes a kind (<c>allPlans</c>, <c>plan</c>, <c>correlation</c>, <c>file</c>).</summary>
    public static string Written(Kind kind) => kind switch
    {
        Kind.AllPlans => "allPlans",
        Kind.Plan => "plan",
        Kind.Correlation => "correlation",
        _ => "file",
    };

    /// <summary>As the contract writes a refusal.</summary>
    public static string Written(Refusal refusal) => refusal switch
    {
        Refusal.NothingToOpen => "nothingToOpen",
        Refusal.OutsideThePlan => "outsideThePlan",
        Refusal.PageIsGone => "pageIsGone",
        _ => "notAPage",
    };

    /// <summary>The trail's words for a kind of page.</summary>
    public static string What(Kind kind) => kind switch
    {
        Kind.AllPlans => AllPlansWhat,
        Kind.Plan => PlanWhat,
        Kind.Correlation => CorrelationWhat,
        _ => FileWhat,
    };

    /// <summary>The line once the browser has the page: the course and the kind of page, never its name.</summary>
    public static string TrailText(string courseCode, Kind kind) =>
        courseCode + UnitPlans.TrailSeparator + TrailLine.Replace("{what}", What(kind));

    /// <summary>The line when the PC could not open it.</summary>
    public static string CouldNotOpenTrailText(string courseCode, Kind kind) =>
        courseCode + UnitPlans.TrailSeparator + CouldNotOpenTrailLine.Replace("{what}", What(kind));
}
