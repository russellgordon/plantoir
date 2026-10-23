using System;
using System.Collections.Generic;
using System.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The Start of Year sheet before Go, in the pieces the dialog draws (#619,
/// mac #589): what must be read before Go above the table, warnings first;
/// the two list headings as the table's summary; a row for every page going
/// into draft, classes first and then pages, in plan order, with its reason
/// in the Why cell; and the rest of what the plan says under it, the notes
/// that must be read before Go first. Every sentence is the one
/// <see cref="StartOfYearWording.Describe"/> already says — only the two
/// lists of lines became rows — and the MCP text is unchanged.
/// </summary>
public sealed record StartOfYearSheet(
    IReadOnlyList<string> Warnings,
    string Intro,
    IReadOnlyList<string> Summary,
    IReadOnlyList<PlanTable.Row> Rows,
    IReadOnlyList<string> MustReadNotes,
    IReadOnlyList<string> OtherNotes)
{
    /// <param name="noRoom">The pages Go would leave exactly as they are, because their settings have no room for a key (the write's own rule, asked before Go).</param>
    public static StartOfYearSheet Make(StartOfYearPlan plan, DateOnly today, DateTime? scheduledDeploy,
                                        IReadOnlyList<string> noRoom, ClassNoun noun = ClassNoun.Class)
    {
        if (plan.First is not { } first) throw new InvalidOperationException("A sheet needs a first class.");
        string one = noun == ClassNoun.Meeting ? "meeting" : "class";
        string many = noun == ClassNoun.Meeting ? "meetings" : "classes";
        string W(string template, params (string, string)[] values) => StartOfYearWording.Fill(template, values);

        var warnings = new List<string>();
        var taught = plan.AlreadyTaught(today);
        if (taught.Count > 0)
            warnings.Add(W(StartOfYearWording.AlreadyTaughtTemplate, ("classes", string.Join(", ", taught.Select(plan.NameOf)))));
        if (scheduledDeploy is { } moment)
            warnings.Add(W(StartOfYearWording.ScheduledDeployTemplate, ("moment",
                moment.ToString("dddd, MMMM d 'at' h:mm tt", System.Globalization.CultureInfo.GetCultureInfo("en-US")))));
        if (!first.Visible)
            warnings.Add(W(StartOfYearWording.FirstClassIsHiddenTemplate, ("first", first.Name), ("noun", one)));

        var classes = plan.Classes.ToList();
        var others = plan.OtherPages.ToList();
        var summary = new List<string>();
        if (classes.Count > 0) summary.Add(W(StartOfYearWording.ClassesHeading, ("classes", StartOfYearWording.Counted(classes.Count, one, many))));
        if (others.Count > 0) summary.Add(W(StartOfYearWording.PagesHeading, ("pages", StartOfYearWording.PagesCounted(others.Count))));

        // The title cell has no quotation marks and the folder is always
        // shown, so a line's "(in …)" (#362) is not needed in a cell.
        var rows = classes.Concat(others)
            .Select((draft, position) => new PlanTable.Row(position, draft.Page.Name, draft.Page.Folder,
                PlanTable.Change.WillBecomeHidden, StartOfYearWording.Reason(plan, draft)))
            .ToList();

        // Under the table, what must be read before Go comes first: publishing
        // from now on, the links left pointing at hidden pages (said nowhere
        // after Go), and the pages with no room for a key.
        var mustRead = new List<string> { W(StartOfYearWording.PublishingFromNowOn, ("noun", one)) };
        var left = plan.LinksLeftBehind();
        if (left.Count > 0)
            mustRead.Add(string.Join("\n", new[] { StartOfYearWording.LinksLeftHeading }.Concat(left.Select(l =>
                "  " + W(StartOfYearWording.LinksLeftLine, ("name", plan.NameOf(l.On)), ("links", StartOfYearWording.LinksCounted(l.Links)))))));
        if (noRoom.Count > 0) mustRead.Add(AssistWording.PagesWhoseSettingsCannotBeAddedTo(noRoom));

        var other = new List<string>();
        if (plan.AlreadyHiddenClasses.Count > 0)
            other.Add(W(StartOfYearWording.AlreadyInDraft, ("classes", string.Join(", ", plan.AlreadyHiddenClasses.Select(plan.NameOf)))));
        var stays = new List<string>
        {
            W(StartOfYearWording.StaysHeading, ("pages", StartOfYearWording.PagesCounted(plan.Pages.Count - plan.Drafts.Count))),
            "  " + W(StartOfYearWording.StaysFirstClass, ("first", first.Name), ("pages", StartOfYearWording.PagesCounted(plan.StaysWithFirst.Count))),
        };
        if (plan.Pages.Any(p => p.Kind == StartOfYearKind.KeyLinks))
            stays.Add("  " + W(StartOfYearWording.StaysKeyLinks, ("pages", StartOfYearWording.PagesCounted(plan.StaysWithKeyLinks.Count))));
        stays.Add("  " + StartOfYearWording.StaysEverythingElse);
        other.Add(string.Join("\n", stays));

        return new StartOfYearSheet(warnings, W(StartOfYearWording.Intro, ("noun", one), ("first", first.Name)),
                                    summary, rows, mustRead, other);
    }
}

/// <summary>
/// How much of the Start of Year sheet is shown at a window's height (#619).
/// Pure, so it is tested without a window; the dialog measures each part
/// laid out at its width and asks this for the caps.
/// </summary>
/// <remarks>
/// <para>ContentDialog's own content does not scroll: whatever does not fit
/// is clipped from outside, where no scroll bar can reach it. So the parts
/// give way in an order, each to a floor, and each part that gives way scrolls
/// INSIDE itself rather than being cut. The window's minimum height is 600
/// epx, so the mac's fixed 620 pt budget cannot be copied; it is derived
/// from the window's height, as <see cref="PlanTableLayout"/> is.</para>
///
/// <para>The order (the #619 plan review): the ROWS give way first, down to
/// <see cref="FewestRows"/>; then the notes, down to what must be read before
/// Go (never below the <see cref="NotesFloor"/> the mac gives them, when they
/// are that tall); then the intro above, down to the warnings — the warnings
/// are NEVER capped; and last, on a window too short for all of that, the
/// notes down to <see cref="NotesFewest"/>, scrolling.</para>
/// </remarks>
public static class StartOfYearSheetLayout
{
    /// <summary>Rows shown before the table scrolls, as the mac's five, within <see cref="DialogMaxHeight"/>; a taller window adds rows (#634).</summary>
    public const int MostRows = 5;

    /// <summary>The fewest rows shown, whatever the window.</summary>
    public const int FewestRows = 2;

    /// <summary>The table's border, top and bottom.</summary>
    public const double TableBorder = 2;

    /// <summary>
    /// Everything that is not the area above, the rows or the notes: the
    /// dialog's title, its padding, the summary lines, the header row, the
    /// panel's spacing and the button row. Measured on this PC in the real
    /// dialog: 250–251 epx on this PC at 150% (i5-8365U, 2026-10-22,
    /// documentation/12-windows-app.md → "The Start of Year sheet as a
    /// table"). The dialog logs what it measures each time it opens, and
    /// refits with the chrome it reads from the laid-out dialog.
    /// </summary>
    public const double Chrome = 251;

    /// <summary>The notes' floor when they are that tall, as the mac's 120 pt.</summary>
    public const double NotesFloor = 120;

    /// <summary>The least the notes are given on a window too short for everything else: about two lines.</summary>
    public const double NotesFewest = 40;

    /// <summary>ContentDialog's <c>ContentDialogMaxHeight</c>.</summary>
    public const double DialogMaxHeight = PlanTableLayout.DialogMaxHeight;

    /// <summary>The caps the dialog sets, and whether everything fits without a part scrolling.</summary>
    public readonly record struct Fit(double AboveCap, int Rows, double TableHeight, double NotesCap, double Height, bool AllShown);

    /// <param name="windowHeight">The XAML root's height, epx.</param>
    /// <param name="chrome">What is neither above, rows nor notes, as measured; <see cref="Chrome"/> when not measured.</param>
    /// <param name="warnings">The warnings' height alone, laid out at the width (0 for none).</param>
    /// <param name="above">The whole area above the table: warnings, then the intro.</param>
    /// <param name="mustRead">The notes that must be read before Go, to the bottom of the last of them.</param>
    /// <param name="notes">Every note, uncapped (0 for none).</param>
    /// <param name="rowHeights">Each row's height in plan order: one line or two.</param>
    public static Fit For(double windowHeight, double chrome, double warnings, double above, double mustRead, double notes,
                          IReadOnlyList<double> rowHeights)
    {
        double room = Math.Min(windowHeight, DialogMaxHeight) - chrome;
        double Table(int n) => rowHeights.Take(n).Sum() + TableBorder;
        int wanted = Math.Min(MostRows, rowHeights.Count);
        int fewest = Math.Min(FewestRows, rowHeights.Count);

        // 1. The rows give way first.
        int rows = wanted;
        while (rows > fewest && above + notes + Table(rows) > room) rows--;
        double table = Table(rows);

        // 2. The notes, down to what must be read before Go (and the floor).
        double notesCap = notes;
        if (above + notesCap + table > room)
            notesCap = Math.Max(Math.Min(notes, Math.Max(mustRead, NotesFloor)), room - above - table);

        // 3. The intro above, down to the warnings, which are never capped.
        double aboveCap = above;
        if (aboveCap + notesCap + table > room)
            aboveCap = Math.Max(warnings, room - notesCap - table);

        // 4. A window too short for all of that: the notes scroll from two lines.
        if (aboveCap + notesCap + table > room)
            notesCap = Math.Max(Math.Min(notes, NotesFewest), room - aboveCap - table);

        // 5. A window taller than the dialog ever was (#634, the mac's #621):
        // the height it adds goes to the table, row by measured row.
        double added = windowHeight - DialogMaxHeight;
        while (added > 0 && rows < rowHeights.Count && rowHeights[rows] <= added)
        {
            added -= rowHeights[rows];
            rows++;
        }
        table = Table(rows);

        double height = chrome + aboveCap + table + notesCap;
        bool allShown = rows == rowHeights.Count && notesCap >= notes && aboveCap >= above;
        return new Fit(aboveCap, rows, table, notesCap, height, allShown);
    }
}
