using System.Globalization;
using System.Text;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>What a page is, for getting a section ready (<c>startOfYear.howToRunACase</c>'s kinds).</summary>
public enum StartOfYearKind
{
    Class,
    Page,
    KeyLinks,
    FolderIndex,
    Curriculum,
    SectionFrontPage,
}

/// <summary>One page of the section, as the planner reads it.</summary>
/// <param name="Id">The page's full path.</param>
/// <param name="Name">The page as a teacher reads its name: front-matter title, else file name, else (index.md) its folder.</param>
/// <param name="Folder">Its folder within the course, segments joined with "/", or the course code at the top.</param>
/// <param name="LinksTo">The pages it links to directly (ids), never itself.</param>
/// <param name="Number">Its unit and day when it is a numbered class.</param>
public sealed record StartOfYearPage(
    string Id,
    string Name,
    string Folder,
    StartOfYearKind Kind,
    bool Visible,
    IReadOnlySet<string> LinksTo,
    UnitDay? Number,
    DateOnly? Date);

/// <summary>Why a page goes into draft.</summary>
public enum StartOfYearReason
{
    LaterClass,
    FirstUsedIn,
    OnlyHiddenPagesLink,
    OnlyAFolderLists,
    NothingLinks,
}

/// <summary>One page the plan puts into draft, and why — <paramref name="Naming"/> is the page a reason names.</summary>
public sealed record StartOfYearDraft(StartOfYearPage Page, StartOfYearReason Reason, StartOfYearPage? Naming);

/// <summary>
/// Getting a section ready for the start of the year (<c>shared-rules.json</c>
/// → <c>startOfYear</c>; GitHub issue #355, the mac's #96): every class after
/// the first goes into draft, with the pages only later classes use, previewed
/// and undoable. Pure — given the section's pages, what WOULD happen.
/// </summary>
/// <remarks>
/// <para><b>Two traps the mac met, and this is built around both.</b> It is
/// NOT the unpublish sweep: every folder's landing page lists every concept, so
/// a sweep that counted a listing as a use left ~150 SNC1W pages up. And step 2
/// reads LINKS, never stored dates: straight after a rollover a page's date
/// comes from a transitive walk and says Day 1 about pages first used in Unit 3
/// (53 SNC1W / 79 ICS3U concepts would have stayed up).</para>
///
/// <para>Ordering is by POSITION: the first numbered class by unit then day
/// (never by date — a field trip dated before Day 1 still goes), and a reason
/// that names "the earliest class" names it by the same order.</para>
/// </remarks>
public sealed class StartOfYearPlan
{
    public StartOfYearPage? First { get; }
    public IReadOnlyList<StartOfYearDraft> Drafts { get; }
    public IReadOnlyList<StartOfYearPage> AlreadyHiddenClasses { get; }
    public IReadOnlyList<StartOfYearPage> Pages { get; }
    public IReadOnlyList<StartOfYearPage> StaysWithFirst { get; }
    public IReadOnlyList<StartOfYearPage> StaysWithKeyLinks { get; }

    private StartOfYearPlan(StartOfYearPage? first, IReadOnlyList<StartOfYearDraft> drafts,
                            IReadOnlyList<StartOfYearPage> alreadyHidden, IReadOnlyList<StartOfYearPage> pages,
                            IReadOnlyList<StartOfYearPage> staysWithFirst, IReadOnlyList<StartOfYearPage> staysWithKeyLinks)
    {
        First = first;
        Drafts = drafts;
        AlreadyHiddenClasses = alreadyHidden;
        Pages = pages;
        StaysWithFirst = staysWithFirst;
        StaysWithKeyLinks = staysWithKeyLinks;
    }

    public bool HasNoFirstClass => First is null;
    public bool NothingToDo => First is not null && Drafts.Count == 0;
    public IEnumerable<StartOfYearDraft> Classes => Drafts.Where(d => d.Reason == StartOfYearReason.LaterClass);
    public IEnumerable<StartOfYearDraft> OtherPages => Drafts.Where(d => d.Reason != StartOfYearReason.LaterClass);

    /// <summary>The section's pages in class POSITION order: numbered classes by unit then day, then the rest as given.</summary>
    public static IReadOnlyList<StartOfYearPage> ClassesByPosition(IReadOnlyList<StartOfYearPage> pages)
    {
        var classes = pages.Where(p => p.Kind == StartOfYearKind.Class).ToList();
        return classes.Where(c => c.Number is not null).OrderBy(c => c.Number!.Value)
            .Concat(classes.Where(c => c.Number is null))
            .ToList();
    }

    public static StartOfYearPlan Make(IReadOnlyList<StartOfYearPage> pages)
    {
        var byPosition = ClassesByPosition(pages);
        var first = byPosition.FirstOrDefault(c => c.Number is not null);
        if (first is null)
            return new StartOfYearPlan(null, Array.Empty<StartOfYearDraft>(), Array.Empty<StartOfYearPage>(), pages,
                Array.Empty<StartOfYearPage>(), Array.Empty<StartOfYearPage>());

        var byId = pages.ToDictionary(p => p.Id, StringComparer.OrdinalIgnoreCase);
        var keyLinks = pages.FirstOrDefault(p => p.Kind == StartOfYearKind.KeyLinks);

        // The never-touched set. A CLASS is never in it except the first: step 1 wins.
        var never = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { first.Id };
        void Keep(IEnumerable<string> ids)
        {
            foreach (string id in ids)
                if (byId.TryGetValue(id, out var page) && page.Kind != StartOfYearKind.Class) never.Add(id);
        }
        Keep(first.LinksTo);
        if (keyLinks is not null) { never.Add(keyLinks.Id); Keep(keyLinks.LinksTo); }
        foreach (var page in pages)
            if (page.Kind is StartOfYearKind.FolderIndex or StartOfYearKind.SectionFrontPage or StartOfYearKind.Curriculum)
                never.Add(page.Id);

        var drafts = new List<StartOfYearDraft>();
        var drafted = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var alreadyHidden = new List<StartOfYearPage>();

        // Step 1: every other class.
        foreach (var page in byPosition.Where(c => !ReferenceEquals(c, first)))
        {
            if (page.Visible) { drafts.Add(new(page, StartOfYearReason.LaterClass, first)); drafted.Add(page.Id); }
            else alreadyHidden.Add(page);
        }

        // Step 2: every other page any class links to DIRECTLY, from links.
        foreach (var page in pages.Where(p => p.Kind == StartOfYearKind.Page && p.Visible && !never.Contains(p.Id)))
        {
            var earliest = byPosition.FirstOrDefault(c => c.LinksTo.Contains(page.Id));
            if (earliest is null) continue;
            drafts.Add(new(page, StartOfYearReason.FirstUsedIn, earliest));
            drafted.Add(page.Id);
        }

        // Step 3, to a fixed point: a visible page nothing students will still
        // see links to. A folder's own page listing it is a listing, not a use;
        // the section's own front page IS a use; a page's link to itself never counts.
        bool StillSeen(StartOfYearPage page) => page.Visible && !drafted.Contains(page.Id);
        bool changed = true;
        while (changed)
        {
            changed = false;
            foreach (var page in pages.Where(p => p.Kind == StartOfYearKind.Page && p.Visible
                                                  && !never.Contains(p.Id) && !drafted.Contains(p.Id)))
            {
                var linkers = pages.Where(q => !ReferenceEquals(q, page) && q.LinksTo.Contains(page.Id)).ToList();
                if (linkers.Any(q => q.Kind != StartOfYearKind.FolderIndex && StillSeen(q))) continue;

                var hiddenUser = linkers.Where(q => q.Kind != StartOfYearKind.FolderIndex)
                    .OrderBy(q => q.Name, StringComparer.OrdinalIgnoreCase).FirstOrDefault();
                var folder = linkers.FirstOrDefault(q => q.Kind == StartOfYearKind.FolderIndex);
                drafts.Add(hiddenUser is not null
                    ? new(page, StartOfYearReason.OnlyHiddenPagesLink, hiddenUser)
                    : folder is not null
                        ? new(page, StartOfYearReason.OnlyAFolderLists, folder)
                        : new(page, StartOfYearReason.NothingLinks, null));
                drafted.Add(page.Id);
                changed = true;
            }
        }

        var staysWithFirst = first.LinksTo.Where(byId.ContainsKey).Select(id => byId[id])
            .Where(p => p.Kind != StartOfYearKind.Class).ToList();
        var staysWithKeyLinks = keyLinks is null
            ? new List<StartOfYearPage>()
            : keyLinks.LinksTo.Where(byId.ContainsKey).Select(id => byId[id])
                .Where(p => p.Kind != StartOfYearKind.Class).ToList();
        return new StartOfYearPlan(first, drafts, alreadyHidden, pages, staysWithFirst, staysWithKeyLinks);
    }

    /// <summary>
    /// Links left on pages students will still see that will lead to hidden
    /// pages, grouped by the page they are on (each page once, with its count).
    /// </summary>
    public IReadOnlyList<(StartOfYearPage On, int Links)> LinksLeftBehind()
    {
        var hiddenAfter = new HashSet<string>(Drafts.Select(d => d.Page.Id), StringComparer.OrdinalIgnoreCase);
        foreach (var page in Pages.Where(p => !p.Visible)) hiddenAfter.Add(page.Id);
        return Pages.Where(p => p.Visible && !hiddenAfter.Contains(p.Id))
            .Select(p => (On: p, Links: p.LinksTo.Count(hiddenAfter.Contains)))
            .Where(p => p.Links > 0)
            .ToList();
    }

    /// <summary>The classes going into draft that are dated before <paramref name="today"/>.</summary>
    public IReadOnlyList<StartOfYearPage> AlreadyTaught(DateOnly today) =>
        Classes.Select(d => d.Page).Where(p => p.Date is { } date && date < today).ToList();

    /// <summary>
    /// The page's name for this plan: its title, and its folder too when
    /// another page of the section has the same title — compared trimmed,
    /// ignoring case, in one Unicode form (#362/#389).
    /// </summary>
    public string NameOf(StartOfYearPage page)
    {
        string key = Comparable(page.Name);
        bool shared = Pages.Count(p => Comparable(p.Name) == key) > 1;
        return shared
            ? StartOfYearWording.PageNameInFolder(page.Name, page.Folder)
            : StartOfYearWording.PageName(page.Name);
    }

    private static string Comparable(string name) =>
        name.Trim().Normalize(NormalizationForm.FormC).ToLowerInvariant();
}

/// <summary>
/// Every sentence getting a section ready says (<c>startOfYear.wording</c>),
/// pinned key by key by <c>StartOfYearTests</c>. The two refusals only an
/// outside assistant meets are <see cref="AssistWording"/>'s.
/// </summary>
public static class StartOfYearWording
{
    public const string MenuItem = "Get Ready for the Start of the Year…";
    public const string UndoMenuItem = "Undo Getting Ready for the Start of the Year…";
    public const string SheetTitle = "Get {course} Section {section} Ready for the Start of the Year";
    public const string Intro = "Every {noun} after “{first}” goes into draft, with the pages students won't need until a later {noun}, and the pages nothing students can still see links to. Students keep “{first}”, the pages it links to, your Key Links and the pages they list. Nothing changes for students until you deploy.";
    public const string ClassesHeading = "Going into draft: {classes}";
    public const string PagesHeading = "Also going into draft: {pages} students won't need yet";
    public const string StaysHeading = "Staying as they are: {pages}";
    public const string AlreadyInDraft = "Already in draft, and left as they are: {classes}.";
    public const string ReasonLaterClass = "comes after “{first}”";
    public const string ReasonFirstUsedIn = "first used in “{page}”";
    public const string ReasonOnlyHiddenPagesLink = "only “{page}” links to it, and students will not see that page";
    public const string ReasonOnlyAFolderLists = "only the “{page}” folder's own page lists it";
    public const string ReasonNothingLinks = "nothing links to it";
    public const string StaysFirstClass = "“{first}”, and the {pages} it links to";
    public const string StaysKeyLinks = "Key Links, and the {pages} it lists";
    public const string StaysEverythingElse = "Every folder's own page, every curriculum page, and every page something students can still see links to.";
    public const string LinksLeftHeading = "After this, links on these pages will lead to pages students cannot see yet:";
    public const string LinksLeftLine = "{name}: {links}";
    public const string PageNameTemplate = "“{page}”";
    public const string PageNameInFolderTemplate = "“{page}” (in {folder})";
    public const string DraftLine = "{name} — {reason}";
    public const string PublishingFromNowOn = "From now on, each {noun} you publish needs the pages it uses published with it. Publishing through the assistant does that for you. Publishing a {noun} by changing its page in Obsidian does not, and would leave it with links students cannot follow.";
    public const string AlreadyTaughtTemplate = "Dated before today, and going into draft: {classes}. If you have already taught them, students will lose them when you next deploy.";
    public const string ScheduledDeployTemplate = "This section is set to deploy on its own at {moment}. That will put these changes in front of students.";
    public const string FirstClassIsHiddenTemplate = "“{first}” is in draft itself, so students will see no {noun} until you publish it.";
    public const string GoButton = "Put These into Draft";
    public const string NothingToDoTemplate = "There is nothing to do: every one of the {nouns} after “{first}” is already in draft, and so is every page only later {nouns} use.";
    public const string Done = "Put into draft: {pages}. Nothing has changed for students yet — that happens when you deploy.";
    public const string UndoAvailable = "You can undo this from this section's menu until the section is next deployed, until any of its pages is next published or put into draft, or until you quit Plantoir. After that, the backup “{backup}” is the way back.";
    public const string ChangedSinceShown = "The section changed after this list was made, so nothing was changed. This is the list as it stands now.";
    public const string DeployUnderWay = "{course} is being deployed right now, so nothing was changed. Try again once the deploy has finished.";
    public const string BackupFailed = "Plantoir could not save a copy of {course} first, so nothing was changed.";
    public const string WriteFailed = "Plantoir could not finish putting the pages into draft. The backup “{backup}” holds the course as it was before you pressed the button.";
    public const string NoFirstClass = "{course} Section {section} has no numbered {noun} yet, so there is no first {noun} to keep. Nothing was changed.";
    public const string UndoTitle = "Undo Getting {course} Section {section} Ready?";
    public const string UndoIntro = "Going back to how they were before you got this section ready for the start of the year: {pages}. Nothing changes for students until you deploy.";
    public const string UndoSkipped = "Changed after that, so staying as they are: {pages}.";
    public const string UndoButton = "Put Them Back";
    public const string Undone = "Put back as they were: {pages}.";
    public const string UndoLeftSome = "Left as they are, because they changed after the section was got ready: {pages}. The backup “{backup}” holds them as they were.";
    public const string UndoButtonAfterward = "Undo…";
    public const string UndoHasEnded = "This can no longer be undone here: the section has been deployed, or its pages have changed, since.";
    public const string BackupHoldsIt = "The backup “{backup}” holds the course as it was before.";
    public const string UndoEndsWhenYouQuit = "This undo is kept only while Plantoir is open. Quitting ends it.";

    /// <summary>Every constant above, by the contract's key, for the pin.</summary>
    public static IReadOnlyDictionary<string, string> ByKey { get; } = new Dictionary<string, string>
    {
        ["menuItem"] = MenuItem, ["undoMenuItem"] = UndoMenuItem, ["sheetTitle"] = SheetTitle, ["intro"] = Intro,
        ["classesHeading"] = ClassesHeading, ["pagesHeading"] = PagesHeading, ["staysHeading"] = StaysHeading,
        ["alreadyInDraft"] = AlreadyInDraft, ["reasonLaterClass"] = ReasonLaterClass, ["reasonFirstUsedIn"] = ReasonFirstUsedIn,
        ["reasonOnlyHiddenPagesLink"] = ReasonOnlyHiddenPagesLink, ["reasonOnlyAFolderLists"] = ReasonOnlyAFolderLists,
        ["reasonNothingLinks"] = ReasonNothingLinks, ["staysFirstClass"] = StaysFirstClass, ["staysKeyLinks"] = StaysKeyLinks,
        ["staysEverythingElse"] = StaysEverythingElse, ["linksLeftHeading"] = LinksLeftHeading, ["linksLeftLine"] = LinksLeftLine,
        ["pageName"] = PageNameTemplate, ["pageNameInFolder"] = PageNameInFolderTemplate, ["draftLine"] = DraftLine,
        ["publishingFromNowOn"] = PublishingFromNowOn, ["alreadyTaught"] = AlreadyTaughtTemplate,
        ["scheduledDeploy"] = ScheduledDeployTemplate, ["firstClassIsHidden"] = FirstClassIsHiddenTemplate,
        ["goButton"] = GoButton, ["nothingToDo"] = NothingToDoTemplate, ["done"] = Done, ["undoAvailable"] = UndoAvailable,
        ["changedSinceShown"] = ChangedSinceShown, ["deployUnderWay"] = DeployUnderWay, ["backupFailed"] = BackupFailed,
        ["writeFailed"] = WriteFailed, ["noFirstClass"] = NoFirstClass, ["undoTitle"] = UndoTitle, ["undoIntro"] = UndoIntro,
        ["undoSkipped"] = UndoSkipped, ["undoButton"] = UndoButton, ["undone"] = Undone, ["undoLeftSome"] = UndoLeftSome,
        ["undoButtonAfterward"] = UndoButtonAfterward, ["undoHasEnded"] = UndoHasEnded, ["backupHoldsIt"] = BackupHoldsIt,
        ["undoEndsWhenYouQuit"] = UndoEndsWhenYouQuit,
    };

    public static string Fill(string template, params (string Key, string Value)[] values)
    {
        string text = template;
        foreach (var (key, value) in values) text = text.Replace("{" + key + "}", value, StringComparison.Ordinal);
        return text;
    }

    public static string PageName(string page) => Fill(PageNameTemplate, ("page", page));
    public static string PageNameInFolder(string page, string folder) => Fill(PageNameInFolderTemplate, ("page", page), ("folder", folder));

    /// <summary>"1 page", "12 pages".</summary>
    public static string Counted(int count, string singular, string plural) =>
        count.ToString(CultureInfo.InvariantCulture) + " " + (count == 1 ? singular : plural);

    public static string PagesCounted(int count) => Counted(count, "page", "pages");
    public static string ClassesCounted(int count) => Counted(count, "class", "classes");
    public static string LinksCounted(int count) => Counted(count, "link", "links");

    /// <summary>
    /// The plan as words — what the app's sheet lists and what an outside
    /// assistant is shown — ending with the plan code on a line of its own.
    /// </summary>
    /// <param name="noun">What the course calls a class page. A club's "meeting"
    /// is for the TEACHER's copy only (#274) — the model's copy is the class form.</param>
    public static string Describe(StartOfYearPlan plan, string course, int section, DateOnly today,
                                  DateTime? scheduledDeploy, string? planCode, ClassNoun noun = ClassNoun.Class)
    {
        string one = noun == ClassNoun.Meeting ? "meeting" : "class";
        string many = noun == ClassNoun.Meeting ? "meetings" : "classes";
        string sectionText = section.ToString(CultureInfo.InvariantCulture);
        if (plan.First is not { } first)
            return Fill(NoFirstClass, ("course", course), ("section", sectionText), ("noun", one));

        string firstName = first.Name;
        if (plan.NothingToDo)
            return Fill(NothingToDoTemplate, ("nouns", many), ("first", firstName));

        var lines = new List<string>
        {
            Fill(SheetTitle, ("course", course), ("section", sectionText)),
            "",
            Fill(Intro, ("noun", one), ("first", firstName)),
            "",
        };

        var classes = plan.Classes.ToList();
        if (classes.Count > 0)
        {
            lines.Add(Fill(ClassesHeading, ("classes", Counted(classes.Count, one, many))));
            foreach (var draft in classes) lines.Add("• " + Line(plan, draft));
            lines.Add("");
        }
        var others = plan.OtherPages.ToList();
        if (others.Count > 0)
        {
            lines.Add(Fill(PagesHeading, ("pages", PagesCounted(others.Count))));
            foreach (var draft in others) lines.Add("• " + Line(plan, draft));
            lines.Add("");
        }
        if (plan.AlreadyHiddenClasses.Count > 0)
        {
            lines.Add(Fill(AlreadyInDraft, ("classes", string.Join(", ", plan.AlreadyHiddenClasses.Select(plan.NameOf)))));
            lines.Add("");
        }

        int staying = plan.Pages.Count - plan.Drafts.Count;
        lines.Add(Fill(StaysHeading, ("pages", PagesCounted(staying))));
        lines.Add("  " + Fill(StaysFirstClass, ("first", firstName), ("pages", PagesCounted(plan.StaysWithFirst.Count))));
        if (plan.Pages.Any(p => p.Kind == StartOfYearKind.KeyLinks))
            lines.Add("  " + Fill(StaysKeyLinks, ("pages", PagesCounted(plan.StaysWithKeyLinks.Count))));
        lines.Add("  " + StaysEverythingElse);
        lines.Add("");

        var left = plan.LinksLeftBehind();
        if (left.Count > 0)
        {
            lines.Add(LinksLeftHeading);
            foreach (var (on, count) in left)
                lines.Add("  " + Fill(LinksLeftLine, ("name", plan.NameOf(on)), ("links", LinksCounted(count))));
            lines.Add("");
        }

        var taught = plan.AlreadyTaught(today);
        if (taught.Count > 0)
            lines.Add(Fill(AlreadyTaughtTemplate, ("classes", string.Join(", ", taught.Select(plan.NameOf)))));
        if (scheduledDeploy is { } moment)
            lines.Add(Fill(ScheduledDeployTemplate, ("moment",
                moment.ToString("dddd, MMMM d 'at' h:mm tt", CultureInfo.GetCultureInfo("en-US")))));
        if (!first.Visible)
            lines.Add(Fill(FirstClassIsHiddenTemplate, ("first", firstName), ("noun", one)));
        lines.Add(Fill(PublishingFromNowOn, ("noun", one)));

        if (planCode is not null)
        {
            lines.Add("");
            lines.Add("Plan code: " + planCode);
        }
        return string.Join("\n", lines);
    }

    private static string Line(StartOfYearPlan plan, StartOfYearDraft draft)
    {
        string reason = draft.Reason switch
        {
            StartOfYearReason.LaterClass => Fill(ReasonLaterClass, ("first", plan.First!.Name)),
            StartOfYearReason.FirstUsedIn => Fill(ReasonFirstUsedIn, ("page", draft.Naming!.Name)),
            StartOfYearReason.OnlyHiddenPagesLink => Fill(ReasonOnlyHiddenPagesLink, ("page", draft.Naming!.Name)),
            StartOfYearReason.OnlyAFolderLists => Fill(ReasonOnlyAFolderLists, ("page", draft.Naming!.Name)),
            _ => ReasonNothingLinks,
        };
        return Fill(DraftLine, ("name", plan.NameOf(draft.Page)), ("reason", reason));
    }
}
