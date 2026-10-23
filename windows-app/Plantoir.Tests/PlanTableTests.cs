using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;
using Change = Plantoir.Core.Assist.PlanTable.Change;
using Column = Plantoir.Core.Assist.PlanTableOrder.Column;

namespace Plantoir.Tests;

/// <summary>
/// #548 (the mac's #524): the Section menu's page plans as a table — one row
/// for every page, in the contract's order, built from the same plan and the
/// same <see cref="AssistWording"/> pieces as the card. The mac's
/// <c>PublishPlanTableTests</c>. No sentence is typed here: each expectation is
/// a member, or a line of <see cref="PublishPlan.Describe"/> itself.
/// </summary>
public class PlanTableTests
{
    private static PlannedPage Page(string title, bool visible = false, bool certain = true, bool isClass = false,
                                    string folder = "section1/All Classes") =>
        new(title, $"courses/ICS3U/{folder}/{title}.md", "publish", CurrentValue: !visible, Draft: false, ViaLink: false,
            IsClassPage: isClass, VisibilityIsCertain: certain);

    private static PlannedChange Becoming(PlannedPage page, bool toVisible) => new(page, "publish", !toVisible, toVisible, false);

    private static string FolderOf(PlannedPage page)
    {
        string folder = Path.GetDirectoryName(page.RelativePath)!.Replace('\\', '/');
        return folder["courses/ICS3U/".Length..];
    }

    private static readonly PlannedPage Day1 = Page("Unit 1, Day 1", isClass: true);
    private static readonly PlannedPage Day2 = Page("Unit 1, Day 2", isClass: true);
    private static readonly PlannedPage Notes = Page("Notes", folder: "Concepts");
    private static readonly PlannedPage Ohm = Page("Ohm's Law", visible: true, folder: "Concepts");
    private static readonly PlannedPage Unread = Page("Unit 1, Day 4", visible: true, certain: false, isClass: true);
    private static readonly PlannedPage SurelyUp = Page("Unit 1, Day 5", visible: true, isClass: true);
    private static readonly PlannedPage NoRoom = Page("Lab", folder: "Labs");
    private static readonly PlannedPage Done1 = Page("Glossary", visible: true, folder: "Concepts");
    private static readonly PlannedPage Done2 = Page("Key Links", visible: true, folder: "section1");

    private static PublishPlan Publishing(bool menu = true) => new()
    {
        CourseCode = "ICS3U", SectionNumber = 1, Publishes = true, FromTheMenu = menu,
        Changes = new[] { Becoming(Day1, true), Becoming(Notes, true) },
        DateMoves = new[] { new PlannedDateMove(Notes, null, new DateOnly(2026, 9, 8), Day1.DisplayTitle) },
        StoppedAtClasses = new[] { Unread, SurelyUp },
        CannotBeAddedTo = new[] { NoRoom },
        AlreadyRight = new[] { Done1, Done2 },
    };

    private static PublishPlan Hiding(bool menu = true) => new()
    {
        CourseCode = "ICS3U", SectionNumber = 1, Publishes = false, FromTheMenu = menu,
        Changes = new[] { Becoming(Day1, false) },
        Kept = new[]
        {
            new PlannedKept(Ohm, AssistWorkspace.KeptBecauseInKeyLinks),
            new PlannedKept(SurelyUp, AssistWorkspace.ClassOfItsOwn),
        },
        // Set, and never said by a hide: the card names these only when publishing.
        StoppedAtClasses = new[] { Unread },
        CannotBeAddedTo = new[] { NoRoom },
        AlreadyRight = new[] { Day2 },
    };

    [Fact]
    public void EveryKindOfRowComesInTheContractsOrder_Publishing()
    {
        var table = Publishing().Tabulate(FolderOf, ClassNoun.Class);

        Assert.Equal(new[] { Change.WillBecomeVisible, Change.WillBecomeVisible, Change.StaysAsItIs,
                             Change.StaysExactlyAsItIs, Change.AlreadyVisible, Change.AlreadyVisible },
                     table.Rows.Select(row => row.Change));
        Assert.Equal(new[]
        {
            AssistWording.PlanWillBecomeVisible,
            AssistWording.PlanWillBecome(true, new[] { Day1.DisplayTitle }),
            AssistWording.MenuPlanStaysAsItIs,
            AssistWording.MenuPlanStaysExactlyAsItIs,
            AssistWording.MenuPlanAlreadyVisible,
            AssistWording.MenuPlanAlreadyVisible,
        }, table.Rows.Select(row => row.WhatChanges));
        // A linked class students CERTAINLY see is not listed (as the card).
        Assert.DoesNotContain(table.Rows, row => row.Title == SurelyUp.DisplayTitle);
        Assert.Equal(Enumerable.Range(0, table.Rows.Count), table.Rows.Select(row => row.Position));
        Assert.Equal(new[] { "section1/All Classes", "Concepts", "section1/All Classes", "Labs", "Concepts", "section1" },
                     table.Rows.Select(row => row.Folder));
        Assert.Equal(new[] { Day1.DisplayTitle, Notes.DisplayTitle }, table.Rows.Take(2).Select(row => row.Title));
    }

    [Fact]
    public void EveryKindOfRowComesInTheContractsOrder_Hiding()
    {
        var table = Hiding().Tabulate(FolderOf, ClassNoun.Class);

        Assert.Equal(new[] { Change.WillBecomeHidden, Change.StaysVisible, Change.StaysVisible,
                             Change.StaysExactlyAsItIs, Change.AlreadyHidden },
                     table.Rows.Select(row => row.Change));
        Assert.Equal(new[]
        {
            AssistWording.PlanWillBecomeHidden,
            AssistWording.PlanStaysVisibleBecause(AssistWorkspace.KeptBecauseInKeyLinks),
            AssistWording.PlanStaysVisibleBecause(AssistWorkspace.ClassOfItsOwn),
            AssistWording.MenuPlanStaysExactlyAsItIs,
            AssistWording.MenuPlanAlreadyHidden,
        }, table.Rows.Select(row => row.WhatChanges));
        Assert.DoesNotContain(table.Rows, row => row.Change == Change.StaysAsItIs);
    }

    [Fact]
    public void EveryPageIsListedPastTheCardsFifteen()
    {
        var many = Enumerable.Range(1, 21).Select(i => Page($"Idea {i:00}", folder: "Concepts")).ToList();
        var changing = new PublishPlan
        {
            CourseCode = "ICS3U", SectionNumber = 1, Publishes = true, FromTheMenu = true,
            Changes = many.Select(page => Becoming(page, true)).ToList(),
        };
        Assert.Equal(21, changing.Tabulate(FolderOf, ClassNoun.Class).Rows.Count);
        Assert.Contains($"…and {21 - 15} more.", changing.Describe().Split('\n'));

        var keeping = new PublishPlan
        {
            CourseCode = "ICS3U", SectionNumber = 1, Publishes = false, FromTheMenu = true,
            Changes = new[] { Becoming(Day1, false) },
            Kept = many.Select(page => new PlannedKept(page, AssistWorkspace.KeptBecauseInKeyLinks)).ToList(),
        };
        Assert.Equal(22, keeping.Tabulate(FolderOf, ClassNoun.Class).Rows.Count);
        Assert.Contains($"…and {21 - 15} more.", keeping.Describe().Split('\n'));
    }

    [Fact]
    public void TheSummaryCountsChangesAndAlreadyRight_NotKept()
    {
        Assert.Equal(AssistWording.MenuPlanSummary(2, 2, publishing: true), Publishing().Tabulate(FolderOf, ClassNoun.Class).Summary);
        Assert.Equal(AssistWording.MenuPlanSummary(1, 1, publishing: false), Hiding().Tabulate(FolderOf, ClassNoun.Class).Summary);
        var nothing = new PublishPlan { CourseCode = "ICS3U", SectionNumber = 1, Publishes = true, AlreadyRight = new[] { Done1 } };
        Assert.Equal(AssistWording.PlanNothingWouldChange, nothing.Tabulate(FolderOf, ClassNoun.Class).Summary);
    }

    /// <summary>
    /// The lasting card/table anti-drift guard: every cell is the card's own
    /// line for that page with the name taken off. The card prints "…and N
    /// more" past fifteen, so it is asked to list everything here.
    /// </summary>
    [Fact]
    public void EveryCellIsTheCardsLineWithoutTheName()
    {
        foreach (var plan in new[] { Publishing(), Hiding(), Publishing(menu: false), Hiding(menu: false) })
        {
            var card = plan.Describe(int.MaxValue).Split('\n');
            var table = plan.Tabulate(FolderOf, ClassNoun.Class);
            foreach (var (change, row) in plan.Changes.Zip(table.Rows))
                Assert.Contains($"{change.Page.Named} {row.WhatChanges}.", card);
            foreach (var (kept, row) in plan.Kept.Zip(table.Rows.Where(row => row.Change == Change.StaysVisible)))
                Assert.Contains($"{kept.Page.Named} {row.WhatChanges}", card);
        }
    }

    /// <summary>A class course: each note is a whole line of the card, in the card's order.</summary>
    [Fact]
    public void EveryNoteIsALineOfTheCard()
    {
        var plan = new PublishPlan
        {
            CourseCode = "ICS3U", SectionNumber = 1, Publishes = true, FromTheMenu = true,
            Changes = new[] { Becoming(Day1, true) },
            StoppedAtClasses = new[] { Unread, Day2 },
            CannotBeAddedTo = new[] { NoRoom },
            DateMoves = new[] { new PlannedDateMove(Notes, null, new DateOnly(2026, 9, 8), Day1.DisplayTitle) },
            UnknownNames = new[] { "Bananas" },
        };
        var card = plan.Describe(int.MaxValue).Split('\n').ToList();
        var notes = plan.Tabulate(FolderOf, ClassNoun.Class).Notes;

        Assert.Equal(4, notes.Count);
        Assert.All(notes, note => Assert.Contains(note, card));
        Assert.Equal(notes, notes.OrderBy(note => card.IndexOf(note)));
        Assert.Equal(plan.CannotBeAddedToSentence, notes[0]);
        Assert.Equal(plan.LeftAloneSentence, notes[1]);
    }

    /// <summary>
    /// A club: the table is the teacher's copy, so it says "meeting" in the
    /// left-alone cell, its note and the kept reason (the director's ruling on
    /// the #548 plan review, F2). Since #556 the teacher's card does too
    /// (<c>Describe(ClassNoun.Meeting)</c>), through the same
    /// <c>PublishPlan.ReasonFor</c>; the class-form card, which is also the
    /// model's copy, does not.
    /// </summary>
    [Fact]
    public void AClubsTableSpeaksOfMeetings()
    {
        var publishing = new PublishPlan
        {
            CourseCode = "ICS3U", SectionNumber = 1, Publishes = true, FromTheMenu = true,
            Changes = new[] { Becoming(Day1, true) },
            StoppedAtClasses = new[] { Day2 },
        };
        var table = publishing.Tabulate(FolderOf, ClassNoun.Meeting);
        Assert.Equal(AssistWording.MenuPlanStaysAsItIsForAMeeting, table.Rows[1].WhatChanges);
        Assert.Equal(AssistWording.LinkedClassWasLeftAloneForAMeeting(new[] { Day2.DisplayTitle }), Assert.Single(table.Notes));

        var two = new PublishPlan
        {
            CourseCode = "ICS3U", SectionNumber = 1, Publishes = true, FromTheMenu = true,
            Changes = new[] { Becoming(Day1, true) },
            StoppedAtClasses = new[] { Day2, Unread },
        };
        Assert.Equal(AssistWording.LinkedClassesWereLeftAloneForAMeeting(new[] { Day2.DisplayTitle, Unread.DisplayTitle }),
                     Assert.Single(two.Tabulate(FolderOf, ClassNoun.Meeting).Notes));

        var kept = Hiding().Tabulate(FolderOf, ClassNoun.Meeting).Rows.Where(row => row.Change == Change.StaysVisible).ToList();
        Assert.Equal($"“{SurelyUp.DisplayTitle}” {kept[1].WhatChanges}",
                     AssistWording.LinkedClassStaysVisibleForAMeeting(SurelyUp.DisplayTitle));
        // Any other reason is the same in both.
        Assert.Equal(AssistWording.PlanStaysVisibleBecause(AssistWorkspace.KeptBecauseInKeyLinks), kept[0].WhatChanges);
        // The class-form card (the model's copy) never says it; the club's
        // card (#556) says the table's kept line and left-alone note.
        Assert.DoesNotContain(AssistWorkspace.MeetingOfItsOwn, Hiding().Describe());
        Assert.Contains($"“{SurelyUp.DisplayTitle}” {kept[1].WhatChanges}", Hiding().Describe(ClassNoun.Meeting).Split('\n'));
        Assert.Contains(Assert.Single(publishing.Tabulate(FolderOf, ClassNoun.Meeting).Notes),
                        publishing.Describe(ClassNoun.Meeting).Split('\n'));
    }

    [Fact]
    public void TheClassFormReasonAndCellAreTheContractsLines()
    {
        Assert.Equal(AssistWording.LinkedClassStaysVisible(SurelyUp.DisplayTitle),
                     $"“{SurelyUp.DisplayTitle}” {AssistWording.PlanStaysVisibleBecause(AssistWorkspace.ClassOfItsOwn)}");
    }

    [Fact]
    public void JsonRoundTrips()
    {
        var table = Publishing().Tabulate(FolderOf, ClassNoun.Class);
        var json = table.ToJson();
        Assert.Equal("willBecomeVisible", json["rows"]![0]!["change"]!.GetValue<string>());
        var back = PlanTable.FromJson(JsonNode.Parse(json.ToJsonString()));
        Assert.Equal(table, back);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("\"a table\"")]
    [InlineData("{}")]
    [InlineData("{\"summary\":\"s\",\"rows\":[],\"notes\":[1]}")]
    [InlineData("{\"summary\":\"s\",\"rows\":[{\"title\":\"t\",\"folder\":\"f\",\"change\":\"sideways\",\"whatChanges\":\"w\"}],\"notes\":[]}")]
    [InlineData("{\"summary\":\"s\",\"rows\":[{\"title\":\"t\",\"folder\":\"f\",\"change\":\"3\",\"whatChanges\":\"w\"}],\"notes\":[]}")]
    [InlineData("{\"summary\":\"s\",\"rows\":[{\"title\":\"t\",\"change\":\"alreadyHidden\",\"whatChanges\":\"w\"}],\"notes\":[]}")]
    public void AbsentOrMalformedJsonIsNoTable(string? json)
    {
        Assert.Null(PlanTable.FromJson(json is null ? null : JsonNode.Parse(json)));
    }

    // ---- How much is shown (the #548 implementation review, finding 1) ----------

    private static double Needs(PlanTableLayout.Fit fit, double notesNatural, bool folds = false) =>
        PlanTableLayout.Chrome + fit.TableHeight + (folds ? PlanTableLayout.FoldHeight : 0)
        + (notesNatural > 0 ? Math.Min(notesNatural, fit.NotesCap) + PlanTableLayout.NotesSpacing : 0);

    /// <summary>
    /// Whenever the window can hold the chrome, the fewest rows and two lines
    /// of notes, everything fits — so nothing is clipped from outside, where
    /// the notes' own scroll bar could not reach it. Long notes give way first.
    /// Since #634 also with the disclosure under the table, and above 756 epx,
    /// where the window's added height goes to the rows.
    /// </summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void EverythingFitsWheneverTwoRowsAndTwoLinesOfNotesCan(bool folds)
    {
        double least = PlanTableLayout.Chrome + PlanTableLayout.TableBorder + PlanTableLayout.FewestRows * PlanTableLayout.RowPitch
                       + PlanTableLayout.NotesSpacing + PlanTableLayout.NotesFewest + (folds ? PlanTableLayout.FoldHeight : 0);
        for (double height = least; height <= 1400; height += 7)
            foreach (double notes in new double[] { 0, 18, 40, 88, 128, 300 })
            {
                var fit = PlanTableLayout.For(height, notes, folds);
                Assert.True(Needs(fit, notes, folds) <= height,
                            $"at {height} epx with {notes} epx of notes the stage needs {Needs(fit, notes, folds)}");
                Assert.InRange(fit.Rows, PlanTableLayout.FewestRows, PlanTableLayout.MostRows + PlanTableLayout.ExtraRows(height));
            }
    }

    /// <summary>
    /// Up to ContentDialog's old 756, the fit is #548's to the row (#634 changed
    /// nothing a window that short can show); above it, every further 32 epx is
    /// one more row. Must-fail: dropping the min(window, 756) split moves rows
    /// at every height between the #548 cap and 756.
    /// </summary>
    [Fact]
    public void UpTo756TheFitIs548s_AndATallerWindowGivesTheTableRows()
    {
        static (int Rows, double NotesCap) Old(double height, double notes)
        {
            double room = Math.Min(height, 756) - 230 - 2;
            int Rows(double r) => (int)Math.Clamp(Math.Floor(r / 32), 2, 12);
            if (notes <= 0) return (Rows(room), 0);
            double cap = Math.Clamp(room - 8 - 4 * 32, 40, 120);
            return (Rows(room - (Math.Min(notes, cap) + 8)), cap);
        }
        for (double height = 300; height <= 756; height += 1)
            foreach (double notes in new double[] { 0, 18, 128 })
            {
                var fit = PlanTableLayout.For(height, notes);
                Assert.Equal(Old(height, notes), (fit.Rows, fit.NotesCap));
            }
        Assert.Equal(12, PlanTableLayout.For(787, 0).Rows);
        Assert.Equal(13, PlanTableLayout.For(788, 0).Rows);
        Assert.Equal(12 + 7, PlanTableLayout.For(1000, 0).Rows);
    }

    [Fact]
    public void AtTheDefaultWindowLongNotesScrollAndFourRowsStay()
    {
        // The XAML root of the default window on 1920 x 1080 at 150%, measured 446 epx.
        var fit = PlanTableLayout.For(446, 128);
        Assert.Equal(4, PlanTableLayout.PreferredRows);
        Assert.Equal(PlanTableLayout.PreferredRows, fit.Rows);
        Assert.Equal(78, fit.NotesCap);
        Assert.InRange(fit.NotesCap, PlanTableLayout.NotesFewest, 127);   // shorter than the notes, so they scroll
        Assert.True(Needs(fit, 128) <= 446);

        var short1 = PlanTableLayout.For(446, 18);
        Assert.Equal(18, Math.Min(18, short1.NotesCap));                  // a short note is shown whole
        Assert.Equal(5, short1.Rows);
    }

    /// <summary>
    /// A window too short for four rows and two lines of notes — the default
    /// window at 200% on 1920 x 1080 gives a XAML root of about 325 epx — shows
    /// fewer rows rather than clipping. At 330 a plan with no notes or a short
    /// one still fits; long notes, given two lines, need a root of 344.
    /// </summary>
    [Fact]
    public void AShortWindowShowsFewerRowsAndStillFits()
    {
        foreach (var (height, notes) in new (double, double)[] { (330, 0), (330, 18), (344, 128) })
        {
            var fit = PlanTableLayout.For(height, notes);
            Assert.InRange(fit.Rows, PlanTableLayout.FewestRows, 3);
            Assert.True(Needs(fit, notes) <= height, $"at {height} with {notes} epx of notes the stage needs {Needs(fit, notes)}");
        }
    }

    [Fact]
    public void AWindow756TallShowsTwelveRowsAndTheWholeNotesCap()
    {
        Assert.Equal(new PlanTableLayout.Fit(PlanTableLayout.MostRows, 0), PlanTableLayout.For(756, 0));
        Assert.Equal(PlanTableLayout.NotesMost, PlanTableLayout.For(1000, 300).NotesCap);
        Assert.Equal(PlanTableLayout.MostRows, PlanTableLayout.For(756, 300).Rows);
    }

    // ---- Sorting ---------------------------------------------------------------

    private static readonly IReadOnlyList<PlanTable.Row> Rows = new[]
    {
        new PlanTable.Row(0, "Unit 1, Day 10", "section1/All Classes", Change.WillBecomeVisible, AssistWording.PlanWillBecomeVisible),
        new PlanTable.Row(1, "Unit 1, Day 2", "section1/All Classes", Change.WillBecomeVisible, AssistWording.PlanWillBecomeVisible),
        new PlanTable.Row(2, "Glossary", "Concepts", Change.AlreadyVisible, AssistWording.MenuPlanAlreadyVisible),
    };

    private static int[] Order(Column column, bool ascending) =>
        PlanTableOrder.Sorted(Rows, column, ascending).Select(row => row.Position).ToArray();

    [Fact]
    public void ItOpensInPlanOrder()
    {
        Assert.Equal((Column.Plan, true), PlanTableOrder.Opening);
        Assert.Equal(new[] { 0, 1, 2 }, Order(Column.Plan, true));
    }

    [Fact]
    public void ByPage_NumbersSortAsNumbers()
    {
        Assert.Equal(new[] { 2, 1, 0 }, Order(Column.Page, true));
        Assert.Equal(new[] { 0, 1, 2 }, Order(Column.Page, false));
    }

    [Fact]
    public void ByFolderOrChange_TiesFallBackToPlanOrder()
    {
        Assert.Equal(new[] { 2, 0, 1 }, Order(Column.Folder, true));
        Assert.Equal(new[] { 0, 1, 2 }, Order(Column.Folder, false));
        // "already visible" before "will become visible", derived rather than typed.
        bool alreadyFirst = string.Compare(AssistWording.MenuPlanAlreadyVisible, AssistWording.PlanWillBecomeVisible,
                                           StringComparison.CurrentCultureIgnoreCase) < 0;
        Assert.Equal(alreadyFirst ? new[] { 2, 0, 1 } : new[] { 0, 1, 2 }, Order(Column.Change, true));
    }

    [Fact]
    public void ANewColumnSortsAscending_TheSameOneFlips_AndTheHeaderCarriesItsArrow()
    {
        Assert.Equal((Column.Page, true), PlanTableOrder.AfterPressing(Column.Page, PlanTableOrder.Opening));
        Assert.Equal((Column.Page, false), PlanTableOrder.AfterPressing(Column.Page, (Column.Page, true)));
        Assert.Equal($"{AssistWording.MenuPlanPageColumn} ▲",
                     PlanTableOrder.Header(AssistWording.MenuPlanPageColumn, Column.Page, (Column.Page, true)));
        Assert.Equal(AssistWording.MenuPlanFolderColumn,
                     PlanTableOrder.Header(AssistWording.MenuPlanFolderColumn, Column.Folder, PlanTableOrder.Opening));
    }

    [Theory]
    [InlineData("Day 2", "Day 10", -1)]
    [InlineData("Day 02", "Day 2", 0)]
    [InlineData("day 3", "Day 3", 0)]
    [InlineData("Idea", "Idea 1", -1)]
    [InlineData("Unit 2, Day 1", "Unit 10, Day 1", -1)]
    public void TheNaturalOrder(string a, string b, int expected)
    {
        Assert.Equal(expected, Math.Sign(PlanTableOrder.Natural(a, b)));
        Assert.Equal(-expected, Math.Sign(PlanTableOrder.Natural(b, a)));
    }
}
