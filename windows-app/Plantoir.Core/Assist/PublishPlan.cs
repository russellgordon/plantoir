using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// What a publish or unpublish change would do, worked out before anything is written.
///
/// PLAIN TEXT. No markdown, no boldface, no machinery (no arrows, no frontmatter keys,
/// no file paths). Each changing page is described as a human sentence:
/// "“Unit 4, Day 24” will become hidden."
///
/// Matches macOS AssistPublishPlan.swift.
/// </summary>
public sealed class PublishPlan
{
    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }

    /// <summary>The verb: true for publish, false for unpublish.</summary>
    public required bool Publishes { get; init; }

    /// <summary>Whether the plan hides rather than publishes.</summary>
    public bool Hiding
    {
        get => !Publishes;
        init => Publishes = !value;
    }

    /// <summary>Page names the teacher or model named that matched nothing.</summary>
    public IReadOnlyList<string> UnknownNames { get; init; } = Array.Empty<string>();

    /// <summary>The pages the teacher named that were found.</summary>
    public IReadOnlyList<PlannedPage> NamedPages { get; init; } = Array.Empty<PlannedPage>();

    /// <summary>Pages whose visibility will change.</summary>
    public IReadOnlyList<PlannedChange> Changes { get; init; } = Array.Empty<PlannedChange>();

    /// <summary>Pages already in the requested state.</summary>
    public IReadOnlyList<PlannedPage> AlreadyRight { get; init; } = Array.Empty<PlannedPage>();

    /// <summary>Pages kept visible during unpublish, each with its reason.</summary>
    public IReadOnlyList<PlannedKept> Kept { get; init; } = Array.Empty<PlannedKept>();

    /// <summary>Pages whose date moves onto the class's day.</summary>
    public IReadOnlyList<PlannedDateMove> DateMoves { get; init; } = Array.Empty<PlannedDateMove>();

    /// <summary>Where a publish would land — "Netlify", "Cloudflare Pages", or a folder.</summary>
    public string Destination { get; init; } = "";

    /// <summary>All pages the plan touches (named and linked).</summary>
    public IReadOnlyList<PlannedPage> Pages { get; init; } = Array.Empty<PlannedPage>();

    /// <summary>Backward-compatible problems list.</summary>
    public IReadOnlyList<string> Problems { get; init; } = Array.Empty<string>();

    /// <summary>Backward-compatible inherited dates for applying.</summary>
    public IReadOnlyList<PlannedDate> InheritedDates { get; init; } = Array.Empty<PlannedDate>();

    /// <summary>The section's front page catching up, or null when already right.</summary>
    public IndexChange? Index { get; init; }

    /// <summary>Backward-compatible dangling links list.</summary>
    public IReadOnlyList<DanglingLink> Dangling { get; init; } = Array.Empty<DanglingLink>();

    /// <summary>
    /// Linked classes a PUBLISH stopped at (#203 / mac #173): reached by a
    /// link, neither published nor walked through.
    /// </summary>
    public IReadOnlyList<PlannedPage> StoppedAtClasses { get; init; } = Array.Empty<PlannedPage>();

    /// <summary>
    /// Pages that would change but the writer DECLINES (#308, the mac's #186):
    /// their settings have no column-0 place for a new line, so nothing will be
    /// written. Asked of the real writer at plan time, and kept out of
    /// <see cref="Changes"/> so the card never promises them.
    /// </summary>
    public IReadOnlyList<PlannedPage> CannotBeAddedTo { get; init; } = Array.Empty<PlannedPage>();

    /// <summary>
    /// Whether this plan is read at the Section menu (#489), which speaks in
    /// its own voice: the <c>…FromTheMenu</c> twins, never "I".
    /// </summary>
    public bool FromTheMenu { get; init; }

    /// <summary>The sentence naming <see cref="CannotBeAddedTo"/>, or null.</summary>
    public string? CannotBeAddedToSentence => CannotBeAddedTo.Count == 0
        ? null
        : FromTheMenu
            ? AssistWording.PagesWhoseSettingsCannotBeAddedToFromTheMenu(CannotBeAddedTo.Select(p => p.DisplayTitle).ToList())
            : AssistWording.PagesWhoseSettingsCannotBeAddedTo(CannotBeAddedTo.Select(p => p.DisplayTitle).ToList());

    /// <summary>
    /// The sentence naming the linked classes left alone, or null. Only the
    /// ones students cannot CERTAINLY see: a class whose flag the app cannot
    /// read is not left out, because "already published" has to be something
    /// the app is sure of.
    /// </summary>
    public string? LeftAloneSentence => LeftAloneSentenceFor(ClassNoun.Class);

    /// <summary>
    /// <see cref="LeftAloneSentence"/> in the course's noun — the menu table's
    /// note (#548) and, since #556, the teacher's card
    /// (<see cref="Describe(ClassNoun, int)"/>). The model's copy asks for the
    /// class form.
    /// </summary>
    internal string? LeftAloneSentenceFor(ClassNoun noun)
    {
        var worth = LeftAlonePages.Select(page => page.DisplayTitle).ToList();
        bool meeting = noun == ClassNoun.Meeting;
        return worth.Count switch
        {
            0 => null,
            1 => meeting ? AssistWording.LinkedClassWasLeftAloneForAMeeting(worth) : AssistWording.LinkedClassWasLeftAlone(worth),
            _ => meeting ? AssistWording.LinkedClassesWereLeftAloneForAMeeting(worth) : AssistWording.LinkedClassesWereLeftAlone(worth),
        };
    }

    /// <summary>
    /// The linked classes a publish stopped at that students cannot CERTAINLY
    /// see — the ones <see cref="LeftAloneSentence"/> names, and the ones the
    /// menu's table lists as staying as they are (#548).
    /// </summary>
    public IReadOnlyList<PlannedPage> LeftAlonePages =>
        StoppedAtClasses.Where(page => !(page.IsVisibleToStudents && page.VisibilityIsCertain)).ToList();

    /// <summary>
    /// The classes a changing page takes its date from, matched by PATH, in
    /// the plan's order — the clause the card says beside the change and the
    /// table says in its cell (#548).
    /// </summary>
    internal IReadOnlyList<string> ClassesWhoseDatesAreTakenBy(PlannedChange change) =>
        DateMoves.Where(m => string.Equals(m.Page.RelativePath, change.Page.RelativePath, StringComparison.OrdinalIgnoreCase))
                 .Select(m => m.TakenFrom)
                 .ToList();

    /// <summary>The date moves whose page is not one of the changes, said on their own lines.</summary>
    internal IReadOnlyList<PlannedDateMove> OrphanedDateMoves()
    {
        var namedAlready = new HashSet<string>(Changes.Select(c => c.Page.RelativePath), StringComparer.OrdinalIgnoreCase);
        return DateMoves.Where(m => !namedAlready.Contains(m.Page.RelativePath)).ToList();
    }

    /// <summary>A date move with no change of its own, as the card and the table's notes say it.</summary>
    internal static string OrphanedDateMoveLine(PlannedDateMove move) =>
        $"{move.Page.Named} will take the same date as “{move.TakenFrom}”.";

    /// <summary>The names the teacher gave that fit no page of the section.</summary>
    internal static string NoPageIsCalledLine(IReadOnlyList<string> unknownNames) =>
        $"No page in this section is called {Listing(unknownNames)}.";

    public IEnumerable<PlannedPage> Named => NamedPages.Count > 0 ? NamedPages : Pages.Where(p => !p.ViaLink);
    public IEnumerable<PlannedPage> Linked => Pages.Where(p => p.ViaLink);
    public IEnumerable<PlannedPage> Changing => Changes.Select(c => c.Page);

    public bool ChangesNothing => Changes.Count == 0 && DateMoves.Count == 0;

    /// <summary>
    /// The whole answer, when the whole answer is that there was nothing to
    /// do — or null when something else needs saying.
    /// </summary>
    public string? NothingToDoSentence
    {
        get
        {
            if (!ChangesNothing || UnknownNames.Count > 0) return null;

            var named = Named.ToList();
            if (named.Count == 0) return null;

            foreach (var page in named)
            {
                // "Already published" has to be a CONFIDENT reading. A page
                // whose flag this app will not read reports as visible, and
                // saying nothing needed doing about it would leave the build
                // holding it back while the teacher was told otherwise.
                if (page.IsVisibleToStudents != Publishes || !page.VisibilityIsCertain)
                    return null;
            }

            if (named.Count == 1)
                return Publishes ? AssistWording.AlreadyPublishedOne : AssistWording.AlreadyHiddenOne;
            return Publishes ? AssistWording.AlreadyPublishedSeveral : AssistWording.AlreadyHiddenSeveral;
        }
    }

    /// <summary>
    /// The proposal in the class form — the MODEL's copy, and the card of any
    /// course that is not a club. Plain sentences, no markdown, no machinery.
    /// </summary>
    public string Describe(int mostListed = 15) => Describe(ClassNoun.Class, mostListed);

    /// <summary>
    /// The kept page's reason in the course's noun: "it is a meeting of its
    /// own" for a club's linked class (#556, the mac's
    /// <c>stayingVisibleLine(noun:)</c>), every other reason as recorded. The
    /// one expression the card and the table both say it with.
    /// </summary>
    internal static string ReasonFor(PlannedKept staying, ClassNoun noun) =>
        noun == ClassNoun.Meeting && staying.Reason == AssistWorkspace.ClassOfItsOwn
            ? AssistWorkspace.MeetingOfItsOwn
            : staying.Reason;

    /// <summary>
    /// The proposal as a teacher would read it, in the course's noun (#556,
    /// the mac's <c>describe(noun:)</c>): a club's card says "meeting" for the
    /// linked classes a publish leaves alone and for the reason an unpublish
    /// keeps one. Only the TEACHER's copy is asked for in the meeting form —
    /// the model's copy is <see cref="Describe(int)"/>, byte for byte
    /// (<c>AssistWording.Meetings.cs</c>, <c>ClubNounTests</c>).
    /// </summary>
    public string Describe(ClassNoun noun, int mostListed = 15)
    {
        var lines = new List<string>();
        string verb = Publishes ? "publishing" : "unpublishing";
        lines.Add($"{CourseCode} Section {SectionNumber}: {verb}.");
        lines.Add("");

        if (Changes.Count == 0 && CannotBeAddedTo.Count > 0)
        {
            // Said by the sentence below, not as "no page would change",
            // which reads as "already right" about pages it declined.
        }
        else if (Changes.Count == 0)
        {
            lines.Add(AssistWording.PlanNothingWouldChange);
        }
        else
        {
            string word = Changes.Count == 1 ? "page" : "pages";
            lines.Add($"{Changes.Count} {word} would change:");
            int listed = 0;
            foreach (var change in Changes)
            {
                if (listed == mostListed)
                {
                    lines.Add($"…and {Changes.Count - listed} more.");
                    break;
                }
                lines.Add($"{change.Page.Named} {AssistWording.PlanWillBecome(change.WillBeVisible, ClassesWhoseDatesAreTakenBy(change))}.");
                listed++;
            }
        }

        if (AlreadyRight.Count > 0)
        {
            string word = AlreadyRight.Count == 1 ? "page is" : "pages are";
            lines.Add($"{AlreadyRight.Count} {word} already {(Publishes ? "visible" : "hidden")}.");
        }

        if (CannotBeAddedToSentence is { } declined)
        {
            lines.Add("");
            lines.Add(declined);
        }

        if (Kept.Count > 0)
        {
            lines.Add("");
            string word = Kept.Count == 1 ? "page stays" : "pages stay";
            lines.Add($"{Kept.Count} linked {word} visible:");
            int listed = 0;
            foreach (var staying in Kept)
            {
                if (listed == mostListed)
                {
                    lines.Add($"…and {Kept.Count - listed} more.");
                    break;
                }
                lines.Add($"{staying.Page.Named} {AssistWording.PlanStaysVisibleBecause(ReasonFor(staying, noun))}");
                listed++;
            }
        }

        if (Publishes && LeftAloneSentenceFor(noun) is { } leftAlone)
        {
            lines.Add("");
            lines.Add(leftAlone);
        }

        var orphaned = OrphanedDateMoves();
        if (orphaned.Count > 0)
        {
            lines.Add("");
            foreach (var move in orphaned)
            {
                lines.Add(OrphanedDateMoveLine(move));
            }
        }

        if (UnknownNames.Count > 0)
        {
            lines.Add("");
            lines.Add(NoPageIsCalledLine(UnknownNames));
        }

        return string.Join("\n", lines);
    }

    /// <summary>
    /// The plan as rows, for the Section menu's plan stage (#548, the mac's
    /// <c>tabulated(noun:fromTheMenu:courseDirectoryURL:)</c>): the same stored
    /// properties <see cref="Describe"/> reads, and the same
    /// <see cref="AssistWording"/> pieces its lines are made of, so the table
    /// and the card cannot say two different things. Rows in the contract's
    /// order, none capped: the changes; the pages an unpublish keeps; the
    /// classes a publish left as they are; the pages with no room for a key;
    /// the pages already the way asked.
    /// </summary>
    /// <param name="folderOf">The Folder cell: the page's folder from the course folder, the course code at its root.</param>
    /// <param name="noun">The course's noun. The table is the teacher's copy and never the model's, so a club's says "meeting" — in the kept reason, the left-alone cell and its note.</param>
    public PlanTable Tabulate(Func<PlannedPage, string> folderOf, ClassNoun noun)
    {
        bool meeting = noun == ClassNoun.Meeting;
        var rows = new List<PlanTable.Row>();
        void Add(PlannedPage page, PlanTable.Change change, string whatChanges) =>
            rows.Add(new PlanTable.Row(rows.Count, page.DisplayTitle, folderOf(page), change, whatChanges));

        foreach (var change in Changes)
            Add(change.Page, change.WillBeVisible ? PlanTable.Change.WillBecomeVisible : PlanTable.Change.WillBecomeHidden,
                AssistWording.PlanWillBecome(change.WillBeVisible, ClassesWhoseDatesAreTakenBy(change)));
        foreach (var staying in Kept)
            Add(staying.Page, PlanTable.Change.StaysVisible, AssistWording.PlanStaysVisibleBecause(ReasonFor(staying, noun)));
        if (Publishes)
            foreach (var page in LeftAlonePages)
                Add(page, PlanTable.Change.StaysAsItIs,
                    meeting ? AssistWording.MenuPlanStaysAsItIsForAMeeting : AssistWording.MenuPlanStaysAsItIs);
        foreach (var page in CannotBeAddedTo)
            Add(page, PlanTable.Change.StaysExactlyAsItIs, AssistWording.MenuPlanStaysExactlyAsItIs);
        foreach (var page in AlreadyRight)
            Add(page, Publishes ? PlanTable.Change.AlreadyVisible : PlanTable.Change.AlreadyHidden,
                Publishes ? AssistWording.MenuPlanAlreadyVisible : AssistWording.MenuPlanAlreadyHidden);

        // The card's other sentences, from the same functions it uses.
        var notes = new List<string>();
        if (CannotBeAddedToSentence is { } declined) notes.Add(declined);
        if (Publishes && LeftAloneSentenceFor(noun) is { } leftAlone) notes.Add(leftAlone);
        foreach (var move in OrphanedDateMoves()) notes.Add(OrphanedDateMoveLine(move));
        if (UnknownNames.Count > 0) notes.Add(NoPageIsCalledLine(UnknownNames));

        return new PlanTable(AssistWording.MenuPlanSummary(Changes.Count, AlreadyRight.Count, Publishes), rows, notes);
    }

    /// <summary>“a”, “a” and “b”, “a”, “b” and “c” — the way a sentence says a list.</summary>
    public static string Listing(IReadOnlyList<string> names)
    {
        var quoted = names.Select(n => $"“{n}”").ToList();
        if (quoted.Count <= 1) return quoted.FirstOrDefault() ?? "";
        string last = quoted[^1];
        quoted.RemoveAt(quoted.Count - 1);
        return string.Join(", ", quoted) + " and " + last;
    }

    /// <summary>
    /// The unit a teacher named, if that is what they named: "Module 4",
    /// "module 4", "Module 4." — but never "Module 4, Day 3", which is one
    /// page.
    ///
    /// <para><b>The course's own word AND the literal "unit", both.</b> A
    /// Module course's teacher says "publish Module 4", but the fixed-shape
    /// card still emits "Unit 4" and the model echoes "Unit" from the system
    /// prompt's examples — so accepting only the course's word would refuse
    /// requests the app itself generates. Accepting only "unit" is the
    /// opposite failure and is the one that shipped first: "Module 4" was not
    /// recognised as a unit at all, fell through to page matching, and came
    /// back as an unknown page. The mac reached the same answer for the same
    /// reason (<c>AssistPublishPlan.unitNamed(_:term:)</c>).</para>
    /// </summary>
    public static int? UnitNamed(string raw, ClassPageNaming naming) =>
        // A numbered course has NO units (#274; class-planning.json → wholeUnit):
        // "publish Week 1" read as unit 1 published every meeting on the mac
        // (4 of 4), and "Week 3" was refused. Every title goes to the page path.
        naming.IsNumbered ? null : UnitNamed(raw, naming.Word);

    public static int? UnitNamed(string raw, string? term = null)
    {
        string tidied = raw.Trim().TrimEnd('.', '!').ToLowerInvariant();
        string? rest = null;
        foreach (string word in new[] { ClassPageTerm.Cleaned(term).ToLowerInvariant(), "unit" })
        {
            string prefix = word + " ";
            if (tidied.StartsWith(prefix, StringComparison.Ordinal))
            {
                rest = tidied[prefix.Length..].Trim();
                break;
            }
        }
        // A comma means they went on to name a day, which is a page.
        if (rest is null || rest.Length == 0 || rest.Contains(',')) return null;
        return int.TryParse(rest, out int unit) ? unit : null;
    }
}

/// <summary>One page whose visibility would move.</summary>
public sealed record PlannedChange(
    PlannedPage Page,
    string Key,
    bool WasVisible,
    bool WillBeVisible,
    bool BecauseLinked);

/// <summary>One page an unpublish reached by following a link and left published.</summary>
public sealed record PlannedKept(
    PlannedPage Page,
    string Reason);

/// <summary>One page whose date would move onto the class's day.</summary>
public sealed record PlannedDateMove(
    PlannedPage Page,
    DateOnly? From,
    DateOnly To,
    string TakenFrom);

/// <summary>
/// The section's front page catching up with what is published: which class
/// its "Most Recent Class" embed shows, and the date it carries.
/// </summary>
public sealed record IndexChange(
    string RelativePath,
    string? FromClass,
    string ToClass,
    DateOnly? FromDate,
    DateOnly ToDate,
    bool HeadingMissing,
    SectionIndex.Pointer? Pointer = null)
{
    public bool WillChange => !HeadingMissing && (FromClass != ToClass || FromDate != ToDate);

    public string Describe() => HeadingMissing
        ? $"{RelativePath} has no “{SectionIndex.Heading}” heading, so its front page can’t be updated. " +
          "Nothing else is affected."
        : WillChange
            ? $"The section's front page would show “{ToClass}” ({DateText.Iso(ToDate)}) as the most recent class" +
              (FromClass is null ? "." : $", instead of “{FromClass}”.")
            : $"The section's front page already shows “{ToClass}”.";
}

/// <summary>One page a plan would touch, and what would happen to it.</summary>
/// <param name="VisibilityIsCertain">
/// False when the page's flag is a form this app will not read — a value on
/// the line below the key, a tag, a block scalar, an anchor, an alias.
/// <para>Anything deciding a page is "already the way you asked" must require
/// this. Without it, "publish this page" on such a page answered that it was
/// already published and wrote nothing, while the build was holding it back —
/// the exact failure the visibility reader exists to remove (issue #140).</para>
/// </param>
public sealed record PlannedPage(
    string Title,
    string RelativePath,
    string FrontmatterKey,
    bool? CurrentValue,
    bool Draft,
    bool ViaLink,
    DateOnly? Date = null,
    string? DisplayTitle = null,
    bool IsFolderIndex = false,
    bool IsClassPage = false,
    bool IsSectionLocal = false,
    bool VisibilityIsCertain = true)
{
    /// <summary>
    /// The folder the page sits in (from the course folder), set ONLY when another
    /// page of the section has the same display title, so the plan can say which
    /// one goes (bundle 10, S1). Null otherwise.
    /// </summary>
    public string? Folder { get; init; }

    /// <summary>
    /// The page as a plan line names it: the contract's one naming rule, the
    /// one start of year uses (shared-rules.json → startOfYear.wording.pageName /
    /// pageNameInFolder) — “{page}”, or “{page}” (in {folder}) when the
    /// section has two pages of that name.
    /// </summary>
    public string Named => Folder is null
        ? StartOfYearWording.PageName(DisplayTitle)
        : StartOfYearWording.PageNameInFolder(DisplayTitle, Folder);

    /// <summary>What the teacher sees this page called (Quartz displayName).</summary>
    public string DisplayTitle { get; init; } = DisplayTitle ?? Title;

    /// <summary>
    /// True when students currently see this page.
    ///
    /// <para>Read the way the BUILT SITE reads it, and when the page's flag is
    /// one this app will not guess at, this says VISIBLE — the mild mistake of
    /// the two, since calling a page hidden while students are reading it is
    /// the failure that reports success. <see cref="VisibilityIsCertain"/> is
    /// how anything that WRITES tells the two apart.</para>
    /// </summary>
    public bool IsVisibleToStudents => CurrentValue is null || !CurrentValue.Value;

    /// <summary>False when the page already carries the wanted value.</summary>
    public bool WillChange => CurrentValue != Draft;

    /// <summary>
    /// Legacy transition string for internal inspection.
    /// </summary>
    public string Transition =>
        $"{RelativePath}  ({When}{FrontmatterKey}: {Show(Invert(CurrentValue))} → {Show(!Draft)})";

    private static bool? Invert(bool? value) => value is null ? null : !value;

    private string When => Date is { } date ? $"{DateText.Iso(date)}, " : "";

    private static string Show(bool? value) =>
        value is null ? "not set" : value.Value ? "true" : "false";
}
