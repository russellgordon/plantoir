using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #619 (mac #589): the Start of Year sheet's pages as a table — every
/// sentence the plan's text already says, the two lists of lines turned into
/// rows (classes first, then pages, in plan order, the reason word for word in
/// Why) — and the height rule that decides how much of each part shows.
/// </summary>
public class StartOfYearSheetTests
{
    private static StartOfYearPage Page(string id, string name, StartOfYearKind kind, bool visible = true,
                                        UnitDay? number = null, DateOnly? date = null, params string[] links) =>
        new(id, name, kind == StartOfYearKind.Class ? "section2/All Classes" : "Concepts", kind, visible,
            links.ToHashSet(StringComparer.OrdinalIgnoreCase), number, date);

    /// <summary>Every reason, a class already in draft, links left behind, Key Links, and a first class in draft.</summary>
    private static StartOfYearPlan WorstCasePlan()
    {
        var pages = new List<StartOfYearPage>
        {
            Page("c1", "Unit 1, Day 1", StartOfYearKind.Class, visible: false, number: new UnitDay(1, 1), date: new DateOnly(2026, 9, 1), links: "kept"),
            Page("c2", "Unit 1, Day 2", StartOfYearKind.Class, number: new UnitDay(1, 2), date: new DateOnly(2026, 9, 2), links: new[] { "later", "hiddenuser" }),
            Page("c3", "Unit 1, Day 3", StartOfYearKind.Class, number: new UnitDay(1, 3), date: new DateOnly(2027, 9, 3)),
            Page("c4", "Unit 1, Day 4", StartOfYearKind.Class, visible: false, number: new UnitDay(1, 4)),
            Page("kept", "Kept Concept", StartOfYearKind.Page, links: "later"),
            Page("later", "A Concept First Used Later", StartOfYearKind.Page),
            Page("hiddenuser", "Hidden Helper", StartOfYearKind.Page, links: "onlyhidden"),
            Page("onlyhidden", "Only Linked From Hidden", StartOfYearKind.Page),
            Page("orphan", "Nothing Links Here", StartOfYearKind.Page),
            Page("listed", "Only Listed", StartOfYearKind.Page),
            Page("index", "Concepts", StartOfYearKind.FolderIndex, links: "listed"),
            Page("keylinks", "Key Links", StartOfYearKind.KeyLinks),
        };
        return StartOfYearPlan.Make(pages);
    }

    private static readonly DateOnly Today = new(2026, 10, 22);
    private static readonly DateTime Scheduled = new(2026, 10, 30, 6, 30, 0);

    [Fact]
    public void EverySentenceOnTheSheetIsOneThePlanAlreadySays()
    {
        var plan = WorstCasePlan();
        var noRoom = new[] { "Only Listed" };
        var sheet = StartOfYearSheet.Make(plan, Today, Scheduled, noRoom);
        var described = StartOfYearWording.Describe(plan, "ICS3U", 2, Today, Scheduled, null).Split('\n').ToList();

        Assert.Equal(3, sheet.Warnings.Count);
        foreach (string line in sheet.Warnings.Concat(new[] { sheet.Intro }).Concat(sheet.Summary))
            Assert.Contains(line, described);
        foreach (string note in sheet.MustReadNotes.Take(2).Concat(sheet.OtherNotes))
            foreach (string line in note.Split('\n'))
                Assert.Contains(line, described);
        Assert.Equal(AssistWording.PagesWhoseSettingsCannotBeAddedTo(noRoom), sheet.MustReadNotes[^1]);
        Assert.StartsWith(StartOfYearWording.LinksLeftHeading, sheet.MustReadNotes[1]);
        Assert.Equal(StartOfYearWording.Fill(StartOfYearWording.PublishingFromNowOn, ("noun", "class")), sheet.MustReadNotes[0]);
    }

    [Fact]
    public void ARowForEveryPageGoingIntoDraft_ClassesFirst_InPlanOrder_ItsReasonWordForWord()
    {
        var plan = WorstCasePlan();
        var sheet = StartOfYearSheet.Make(plan, Today, null, Array.Empty<string>());
        var drafts = plan.Classes.Concat(plan.OtherPages).ToList();
        string described = StartOfYearWording.Describe(plan, "ICS3U", 2, Today, null, null);

        Assert.Equal(plan.Drafts.Count, sheet.Rows.Count);
        Assert.Equal(Enumerable.Range(0, drafts.Count), sheet.Rows.Select(r => r.Position));
        for (int i = 0; i < drafts.Count; i++)
        {
            var row = sheet.Rows[i];
            Assert.Equal(drafts[i].Page.Name, row.Title);           // no quotation marks in the cell
            Assert.Equal(drafts[i].Page.Folder, row.Folder);        // the folder always shown
            Assert.Equal(StartOfYearWording.Reason(plan, drafts[i]), row.WhatChanges);
            Assert.Contains("• " + StartOfYearWording.Fill(StartOfYearWording.DraftLine,
                ("name", plan.NameOf(drafts[i].Page)), ("reason", row.WhatChanges)), described);
        }
        // Every reason the plan can give has a row here.
        Assert.Equal(Enum.GetValues<StartOfYearReason>().Length, drafts.Select(d => d.Reason).Distinct().Count());
        Assert.Equal("Why", StartOfYearWording.ReasonColumn);
    }

    [Fact]
    public void WhySortsByTheReason_AndTiesFallBackToPlanOrder()
    {
        var sheet = StartOfYearSheet.Make(WorstCasePlan(), Today, null, Array.Empty<string>());
        var sorted = PlanTableOrder.Sorted(sheet.Rows, PlanTableOrder.Column.Change, ascending: true);
        Assert.Equal(sheet.Rows.Select(r => r.WhatChanges).OrderBy(w => w, StringComparer.CurrentCultureIgnoreCase),
                     sorted.Select(r => r.WhatChanges));
        Assert.Equal(sheet.Rows, PlanTableOrder.Sorted(sheet.Rows, PlanTableOrder.Opening.Column, true));
    }

    // ---- The height rule --------------------------------------------------

    private static IReadOnlyList<double> Rows(int count, double each = 32) => Enumerable.Repeat(each, count).ToList();

    [Fact]
    public void ATallWindowShowsFiveRowsAndEverythingElseWhole()
    {
        var fit = StartOfYearSheetLayout.For(800, 250, 60, 140, 80, 160, Rows(19));
        Assert.Equal(5, fit.Rows);
        Assert.Equal((140, 160), (fit.AboveCap, fit.NotesCap));
        Assert.True(fit.Height <= StartOfYearSheetLayout.DialogMaxHeight);
    }

    [Fact]
    public void AShortTableTakesOnlyItsRows()
    {
        var fit = StartOfYearSheetLayout.For(800, 250, 0, 60, 40, 100, Rows(3));
        Assert.Equal(3, fit.Rows);
        Assert.Equal(3 * 32 + StartOfYearSheetLayout.TableBorder, fit.TableHeight);
        Assert.True(fit.AllShown);
    }

    /// <summary>The rows give way first, down to two, before anything a teacher must read.</summary>
    [Fact]
    public void TheRowsGiveWayFirst()
    {
        // room = 600 - 250 = 350; above 120 + notes 150 leaves 80: two rows.
        var fit = StartOfYearSheetLayout.For(600, 250, 60, 120, 100, 150, Rows(19));
        Assert.Equal(2, fit.Rows);
        Assert.Equal((120, 150), (fit.AboveCap, fit.NotesCap));
    }

    /// <summary>Then the notes, never below what must be read before Go; then the intro, never below the warnings.</summary>
    [Fact]
    public void ThenTheNotesThenTheIntro_AndTheWarningsAreNeverCapped()
    {
        var notesGive = StartOfYearSheetLayout.For(600, 250, 60, 120, 125, 200, Rows(19));
        Assert.Equal(2, notesGive.Rows);
        Assert.True(notesGive.NotesCap >= 125, $"must-read notes cut at {notesGive.NotesCap}");
        Assert.True(notesGive.NotesCap < 200);

        var aboveGives = StartOfYearSheetLayout.For(600, 250, 90, 160, 125, 200, Rows(19));
        Assert.True(aboveGives.AboveCap >= 90, $"warnings cut at {aboveGives.AboveCap}");
        Assert.True(aboveGives.AboveCap < 160);
        Assert.True(aboveGives.NotesCap >= 125);

        // Warnings alone taller than the room: still never capped.
        var tiny = StartOfYearSheetLayout.For(500, 250, 200, 220, 125, 200, Rows(19));
        Assert.Equal(200, tiny.AboveCap);
        Assert.False(tiny.AllShown);
    }

    /// <summary>The notes keep the mac's 120 floor while the intro can still give way.</summary>
    [Fact]
    public void TheNotesKeepTheirFloorWhenTheyAreThatTall()
    {
        var fit = StartOfYearSheetLayout.For(600, 250, 40, 150, 60, 200, Rows(19));
        Assert.True(fit.NotesCap >= StartOfYearSheetLayout.NotesFloor, $"{fit.NotesCap}");
    }

    /// <summary>Two-line rows are counted at their own height, not the one-line pitch.</summary>
    [Fact]
    public void TwoLineRowsAreCountedAtTheirHeight()
    {
        var mixed = new List<double> { 52, 32, 52, 52, 32, 32 };
        var fit = StartOfYearSheetLayout.For(800, 250, 0, 60, 40, 60, mixed);
        Assert.Equal(5, fit.Rows);
        Assert.Equal(52 + 32 + 52 + 52 + 32 + StartOfYearSheetLayout.TableBorder, fit.TableHeight);
    }
}
