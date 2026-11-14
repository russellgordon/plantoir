using System.Globalization;

namespace Plantoir.Core.Models;

/// <summary>
/// The course page's Planning tab (#801, the mac's #708), as rules a test can
/// run without a window: when the Settings | Planning tabs are there at all,
/// which plans the unit popup offers and which one it starts on, which entry
/// follows the page on screen, and where Course ▸ Save leaves the page.
/// </summary>
/// <remarks>
/// <para>Every rule is a case in <c>contracts/shared-rules.json</c> →
/// <c>unitPlanning.tab</c> (<c>tabCases</c>, <c>choiceCases</c>,
/// <c>followsThePage</c>, <c>saveOnPlanning</c>), walked by
/// <c>PlanningTabTests</c>; every word is in its <c>words</c>
/// (<see cref="PlanningTabWording"/>). Ported from the mac's
/// <c>PlanningTab.swift</c>. The tab itself is 790b; this is its Core.</para>
///
/// <para>Paths here are Windows paths. The tab's web view reports a served
/// address (<c>LocalSiteGuard</c>), which the view turns into the path
/// with <c>LocalSiteGuard.PathOf</c> before asking
/// <see cref="ChoiceForPage"/>.</para>
/// </remarks>
public static class PlanningTab
{
    /// <summary>One entry in the unit popup: All Plans (the planning folder's own <c>index.html</c>), or one unit by its folder.</summary>
    public sealed record Choice(string? Slug)
    {
        /// <summary>The course's list of plans.</summary>
        public static readonly Choice AllPlans = new((string?)null);

        /// <summary>One unit's plan page.</summary>
        public static Choice Unit(string slug) => new(slug);

        public bool IsAllPlans => Slug is null;

        /// <summary>As the contract writes a choice: <c>allPlans</c> or <c>unit:&lt;folder&gt;</c>.</summary>
        public string Written => Slug is null ? "allPlans" : "unit:" + Slug;

        /// <summary>The choice the contract writes as <paramref name="written"/>.</summary>
        public static Choice FromWritten(string written) =>
            written == "allPlans" ? AllPlans : Unit(written["unit:".Length..]);
    }

    /// <summary>One reading of the planning folder: the plans, and what the popup offers.</summary>
    public sealed record Look(IReadOnlyList<UnitPlans.Plan> Plans, IReadOnlyList<Choice> Choices);

    /// <summary>Where the page goes after Course ▸ Save on Planning (<c>saveOnPlanning</c>).</summary>
    public enum AfterSave { StaysOnPlanning, ShowsSettings }

    /// <summary>The page every choice opens, inside its folder.</summary>
    public const string PageName = "index.html";

    /// <summary>
    /// <c>tabCases</c>: the tabs are on a course's page only while an outside
    /// assistant is installed (Claude Code, Codex, or since #783 GitHub
    /// Copilot), and never on a course kept for reference. Absent, never
    /// disabled (Russell, 2026-11-01); whether plans exist never matters. This
    /// app has no Copilot door until #884, so its caller passes false there,
    /// which the contract allows ("a reader that predates it treats it as false").
    /// </summary>
    public static bool IsShown(bool claudeIsInstalled, bool codexIsInstalled, bool courseIsKeptForReference,
                               bool copilotIsInstalled = false) =>
        !courseIsKeptForReference && (claudeIsInstalled || codexIsInstalled || copilotIsInstalled);

    /// <summary>
    /// <c>choiceCases</c> → <c>choices</c>: All Plans first when the planning
    /// folder has its own page, then each plan with a page of its own, in
    /// <see cref="UnitPlans.Read"/>'s order. An empty list is the empty tab.
    /// </summary>
    public static IReadOnlyList<Choice> Choices(IReadOnlyList<UnitPlans.Plan> plans, bool coursePageExists,
                                                IReadOnlySet<string> unitsWithAPage)
    {
        var result = new List<Choice>();
        if (coursePageExists) result.Add(Choice.AllPlans);
        foreach (var plan in plans)
            if (unitsWithAPage.Contains(plan.Slug)) result.Add(Choice.Unit(plan.Slug));
        return result;
    }

    /// <summary>
    /// <c>choiceCases</c> → <c>startsOn</c> (#803, #820 item 1): the offered
    /// plan covering today (<see cref="UnitPlans.Covers"/>, both ends
    /// included), the earliest first class when two do; otherwise All Plans;
    /// otherwise, with no All Plans page, the offered plans in
    /// <see cref="UnitPlans.NamedFirst"/> order (the greeting's own order, so
    /// there is one ordering and not two) and the first of them. Null only
    /// when there is nothing to offer. <paramref name="today"/> is handed in,
    /// never read from the clock here.
    /// </summary>
    public static Choice? StartingChoice(IReadOnlyList<UnitPlans.Plan> plans, IReadOnlyList<Choice> choices, DateOnly today)
    {
        var offered = plans.Where(plan => choices.Contains(Choice.Unit(plan.Slug))).ToList();
        var ordered = UnitPlans.NamedFirst(offered, today);
        if (ordered.Count > 0 && UnitPlans.Covers(ordered[0], today)) return Choice.Unit(ordered[0].Slug);
        if (choices.Contains(Choice.AllPlans)) return Choice.AllPlans;
        if (ordered.Count > 0) return Choice.Unit(ordered[0].Slug);
        return choices.Count > 0 ? choices[0] : null;
    }

    /// <summary>The page a choice opens.</summary>
    public static string PageFor(Choice choice, string planningFolder) =>
        choice.Slug is null ? Path.Combine(planningFolder, PageName) : Path.Combine(planningFolder, choice.Slug, PageName);

    /// <summary>The words a choice shows in the popup: All Plans, or the plan's name as the greeting says it.</summary>
    public static string TitleFor(Choice choice, IReadOnlyList<UnitPlans.Plan> plans)
    {
        if (choice.Slug is null) return PlanningTabWording.AllPlans;
        var plan = plans.FirstOrDefault(p => p.Slug == choice.Slug);
        return plan is null ? choice.Slug : UnitPlans.NameInTheGreeting(plan);
    }

    /// <summary>
    /// <c>followsThePage</c>: the popup entry a page belongs to, so the popup
    /// follows a link to another unit (708 implementation review L4). The
    /// planning folder's own <c>index.html</c> is All Plans when offered; any
    /// page in a unit's folder is that unit when offered; anything else is
    /// null, and the popup keeps what it showed. Compared folder by folder
    /// without regard to case, as Windows names files.
    /// </summary>
    public static Choice? ChoiceForPage(string page, string planningFolder, IReadOnlyList<Choice> choices)
    {
        var pageParts = Parts(page);
        var folderParts = Parts(planningFolder);
        if (pageParts.Count <= folderParts.Count) return null;
        for (int i = 0; i < folderParts.Count; i++)
            if (!string.Equals(pageParts[i], folderParts[i], StringComparison.OrdinalIgnoreCase)) return null;
        var rest = pageParts.Skip(folderParts.Count).ToList();
        if (rest.Count == 1 && string.Equals(rest[0], PageName, StringComparison.OrdinalIgnoreCase))
            return choices.Contains(Choice.AllPlans) ? Choice.AllPlans : null;
        if (rest.Count < 2) return null;
        return choices.FirstOrDefault(c => c.Slug is not null && string.Equals(c.Slug, rest[0], StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>A Windows path's parts, without the empty ones a trailing or doubled separator makes.</summary>
    internal static List<string> Parts(string path) =>
        Path.GetFullPath(path).Split(new[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries).ToList();

    /// <summary>
    /// What the planning folder holds right now, read from the disk: the plans,
    /// whether the folder has its own page, and which units have one.
    /// </summary>
    public static Look LookIn(string planningFolder, string courseDirectory)
    {
        var reading = UnitPlans.Read(courseDirectory);
        var withAPage = new HashSet<string>(StringComparer.Ordinal);
        foreach (var plan in reading.Plans)
            if (File.Exists(PageFor(Choice.Unit(plan.Slug), planningFolder))) withAPage.Add(plan.Slug);
        bool coursePage = File.Exists(PageFor(Choice.AllPlans, planningFolder));
        return new Look(reading.Plans, Choices(reading.Plans, coursePage, withAPage));
    }

    /// <summary>
    /// <c>saveOnPlanning</c>: saved with nothing more to say stays on Planning
    /// (its "Saved ✓" shown there); a refusal, a failure or a notice to read
    /// goes to Settings, where the form says its own sentence.
    /// </summary>
    public static AfterSave AfterASave(bool problem, bool notice) =>
        problem || notice ? AfterSave.ShowsSettings : AfterSave.StaysOnPlanning;

    // ---- The trail (activityTrail.mustRecord "looked at a course's unit plans") --

    /// <summary>
    /// The line when the tab appears: the course and how many plans it could
    /// choose from, never a plan's title.
    /// </summary>
    public static string OpenedTrailText(string courseCode, IReadOnlyList<Choice> choices)
    {
        int units = choices.Count(c => !c.IsAllPlans);
        string what = units switch
        {
            1 => PlanningTrail.OneUnitPlan,
            > 1 => PlanningTrail.UnitPlans.Replace("{n}", units.ToString(CultureInfo.InvariantCulture)),
            _ => choices.Contains(Choice.AllPlans) ? PlanningTrail.ListOnly : PlanningTrail.NothingToShow,
        };
        return courseCode + UnitPlans.TrailSeparator + PlanningTrail.Opened.Replace("{what}", what);
    }

    /// <summary>
    /// The one line an appearance of the tab writes (<c>unitPlanning.tab.trail</c>):
    /// what it offered, or, when a plan was there to show and could not be
    /// shown, the could-not-show line in place of the count (708 fix review L3).
    /// </summary>
    public static string AppearanceTrailText(string courseCode, IReadOnlyList<Choice> choices, bool couldShow) =>
        choices.Count > 0 && !couldShow ? CouldNotShowTrailText(courseCode) : OpenedTrailText(courseCode, choices);

    /// <summary>Writes <see cref="AppearanceTrailText"/> on the trail ("looked at a course's unit plans").</summary>
    public static void NoteAppearance(string courseCode, IReadOnlyList<Choice> choices, bool couldShow) =>
        Plantoir.Core.Scripting.ActivityTrail.Note(Plantoir.Core.Scripting.ActivityTrail.Event.UnitPlansLookedAt,
            AppearanceTrailText(courseCode, choices, couldShow));

    /// <summary>The line when no page can be shown at all (the guard could not be put in place).</summary>
    public static string CouldNotShowTrailText(string courseCode) =>
        courseCode + UnitPlans.TrailSeparator + PlanningTrail.CouldNotShow;

    /// <summary>The line, once per appearance, when the assets mirror failed.</summary>
    public static string CouldNotRefreshTheLookTrailText(string courseCode, int failed) =>
        courseCode + UnitPlans.TrailSeparator
        + PlanningTrail.CouldNotRefreshTheLook.Replace("{n}", failed.ToString(CultureInfo.InvariantCulture));
}

/// <summary>
/// The Planning tab's trail words, verbatim from <c>activityTrail.mustRecord</c>
/// → "looked at a course's unit plans" (after its <c>{course} · </c>). No
/// plan's title: it is the teacher's own words, and the count says what support
/// needs. <see cref="CouldNotShow"/> names no machine (Russell's ruling on
/// #801, 2026-11-13, as Coverage's did in 5107c8d8b).
/// </summary>
public static class PlanningTrail
{
    public const string Opened = "opened the Planning tab: {what}";
    public const string OneUnitPlan = "1 unit plan to choose from";
    public const string UnitPlans = "{n} unit plans to choose from";
    public const string ListOnly = "only the list of plans";
    public const string NothingToShow = "nothing to show yet, offered to plan a unit";
    public const string CouldNotShow = "the Planning tab showed nothing: Plantoir could not keep the plan's pages off the internet";
    public const string CouldNotRefreshTheLook =
        "the Planning tab could not bring the plan's look up to date: {n} file(s) could not be copied";
}

/// <summary>
/// Every word the Planning tab shows a teacher, verbatim from
/// <c>contracts/shared-rules.json</c> → <c>unitPlanning.tab.words</c>, pinned
/// key by key by <c>PlanningTabTests</c>. The three that name the computer are
/// written with <see cref="MachineWord.Placeholder"/> (Russell's ruling on #801,
/// 2026-11-13) and said filled (<c>MachineWordContractTests</c>).
/// </summary>
public static class PlanningTabWording
{
    public const string TabSettings = "Settings";
    public const string TabPlanning = "Planning";
    public const string AllPlans = "All Plans";
    public const string UnitPopup = "Unit";
    public const string Back = "Back";
    public const string Forward = "Forward";
    public const string Reload = "Reload";
    public const string EmptyTitle = "No Unit Plans Yet";
    public const string EmptyDescription =
        "Plan a unit with an assistant: a calendar across your sections, lesson cards, each day's materials, "
        + "assessment drafts and a curriculum correlation. Once it is built, the plan shows here.";
    public const string RevertOnPlanning = "Revert works on the Settings tab, where the changes are shown.";
    public const string CannotShowTitle = "Unit Plans Can’t Be Shown";
    public const string CannotShowDescriptionTemplate =
        "Plantoir could not get ready to show unit plans on this {machine}. Quitting Plantoir and opening it again may be enough.";
    public const string OpenInBrowser = "Open in Browser";
    public const string OpenInBrowserHelp = "Open this page in your web browser";
    public const string OpenInBrowserNothingToOpen = "There is no page to open in your browser yet.";
    public const string OpenInBrowserOutsideThePlan = "Only a page from this course’s unit plans can be opened in your browser.";
    public const string OpenInBrowserPageIsGone = "This page is no longer in the course’s unit plans. Reload to see what is there now.";
    public const string OpenInBrowserCouldNotOpenTitle = "Can’t Open in Your Browser";
    public const string OpenInBrowserCouldNotOpenTemplate = "Your {machine} could not open this page in your web browser.";
    public const string OpenInBrowserNotAPage = "Only a page of the plan or one of its PDFs can be opened in your browser.";
    public const string OpenInBrowserNoBrowserTemplate = "No web browser is set on this {machine}, so the page was not opened.";

    /// <summary><see cref="CannotShowDescriptionTemplate"/> as a Windows teacher reads it.</summary>
    public static string CannotShowDescription => MachineWord.Fill(CannotShowDescriptionTemplate);

    /// <summary><see cref="OpenInBrowserCouldNotOpenTemplate"/> as a Windows teacher reads it.</summary>
    public static string OpenInBrowserCouldNotOpen => MachineWord.Fill(OpenInBrowserCouldNotOpenTemplate);

    /// <summary><see cref="OpenInBrowserNoBrowserTemplate"/> as a Windows teacher reads it.</summary>
    public static string OpenInBrowserNoBrowser => MachineWord.Fill(OpenInBrowserNoBrowserTemplate);

    /// <summary>Each <c>words</c> key and this app's constant for it, as the contract writes it (placeholders unfilled).</summary>
    public static IReadOnlyDictionary<string, string> ByKey { get; } = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["tabSettings"] = TabSettings,
        ["tabPlanning"] = TabPlanning,
        ["allPlans"] = AllPlans,
        ["unitPopup"] = UnitPopup,
        ["back"] = Back,
        ["forward"] = Forward,
        ["reload"] = Reload,
        ["emptyTitle"] = EmptyTitle,
        ["emptyDescription"] = EmptyDescription,
        ["revertOnPlanning"] = RevertOnPlanning,
        ["cannotShowTitle"] = CannotShowTitle,
        ["cannotShowDescription"] = CannotShowDescriptionTemplate,
        ["openInBrowser"] = OpenInBrowser,
        ["openInBrowserHelp"] = OpenInBrowserHelp,
        ["openInBrowserNothingToOpen"] = OpenInBrowserNothingToOpen,
        ["openInBrowserOutsideThePlan"] = OpenInBrowserOutsideThePlan,
        ["openInBrowserPageIsGone"] = OpenInBrowserPageIsGone,
        ["openInBrowserCouldNotOpenTitle"] = OpenInBrowserCouldNotOpenTitle,
        ["openInBrowserCouldNotOpen"] = OpenInBrowserCouldNotOpenTemplate,
        ["openInBrowserNotAPage"] = OpenInBrowserNotAPage,
        ["openInBrowserNoBrowser"] = OpenInBrowserNoBrowserTemplate,
    };
}
