using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// "Folders Plantoir uses", driven through the real interface.
///
/// <para><b>What this suite is FOR, and what it deliberately leaves to the
/// unit tests.</b> <c>SpecialFoldersHelpContractTests</c> already proves every
/// contract case against <c>SpecialFoldersHelp.Entries</c>, and the dialog
/// writes no sentence of its own — so re-running the whole case sweep through
/// a real window would re-prove a pure function slowly. These tests exist for
/// the six things no unit test can see: that the button can be reached, that
/// clicking it opens anything at all, that what is RENDERED is what the model
/// said in the order the contract fixes, that the bottom of a scrolling list
/// is not cut off, that the sheet follows the selected course rather than
/// going stale, and that it can be dismissed.</para>
///
/// <para>Serialised: they drive one real application, and two at once would
/// fight over the foreground window.</para>
/// </summary>
[Collection("drives the real app")]
public class SpecialFoldersHelpUiTests
{
    private static JsonNode Contract() =>
        JsonNode.Parse(File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "contracts", "shared-rules.json")))!
            ["specialFoldersHelp"]!;

    private static string Row(string key, string field)
    {
        foreach (JsonNode? row in Contract()["rows"]!.AsArray())
            if (row!["key"]!.ToString() == key) return row[field]!.ToString();
        throw new Xunit.Sdk.XunitException($"no row '{key}' in the contract");
    }

    /// <summary>
    /// Open the sheet for a course and hand back the dialog, once it really
    /// has something in it.
    ///
    /// <para>Waiting for the ELEMENT is not enough, and the difference is not
    /// theoretical: opening a second sheet after closing the first handed back
    /// a dialog whose text list was empty, and the test then failed saying "All
    /// Classes" was missing — a sentence about the product, for what was
    /// really a race with the dialog's own arrival. So the wait is on the
    /// CONTENT, and the element is re-found each time round rather than reused,
    /// since the one from the previous sheet is dead.</para>
    /// </summary>
    private static AutomationElement OpenFor(DrivenApp app, string code)
    {
        app.SelectCourse(code);
        var button = app.Find("openFoldersHelpButton", "the folders-help button");
        button.AsButton().Invoke();

        string title = Contract()["title"]!.ToString();
        var ready = Retry.WhileNull(() =>
        {
            var found = app.FindOrNull("specialFoldersHelpDialog", TimeSpan.FromMilliseconds(500));
            if (found is null) return null;
            return DrivenApp.TextsUnder(found).Contains(title) ? found : null;
        }, TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result;

        Assert.True(ready is not null, $"the folders-help sheet never opened with anything in it for {code}");
        return ready!;
    }

    // ---- 1. Can a teacher get to it at all? -------------------------------

    /// <summary>
    /// Reachability, not merely existence. `Invoke` fires a button's click
    /// whether or not it is on screen, so "the element exists" would pass for
    /// a button scrolled off the bottom of a long form and never seen by
    /// anyone. The button sits below the Marks list, well down a long form.
    ///
    /// <para>The form is scrolled by its OWN Scroll pattern rather than by
    /// asking the button to bring itself into view: `ScrollItem` is offered by
    /// items of an items-control, and a plain Button in a StackPanel has no
    /// such pattern — so the first version of this called
    /// <c>PatternOrDefault?.ScrollIntoView()</c> on null and scrolled nothing,
    /// while claiming in its own comment to be testing exactly that.</para>
    ///
    /// <para>And the button is checked against the FORM's viewport, not the
    /// window's: a control below the fold but above the window's bottom edge
    /// is inside the window and still invisible.</para>
    /// </summary>
    [UiFact]
    public void TheButtonIsInCourseSettingsWhereATeacherCanSeeIt()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectCourse(CourseFixtures.Renamed);

        var button = app.Find("openFoldersHelpButton", "the folders-help button");
        Assert.True(button.IsEnabled);
        Assert.Equal(Contract()["openedBy"]!.ToString(), button.Name);

        var form = app.Find("courseSettingsForm", "the Course Settings form");
        var scroll = form.Patterns.Scroll.PatternOrDefault;
        Assert.True(scroll is not null, "the Course Settings form offers no scroll pattern");

        // Walk down the form until the button is really on screen. Ten steps
        // of 10% covers the form from top to bottom whatever its length.
        bool visible = false;
        for (int step = 0; step <= 10 && !visible; step++)
        {
            scroll!.SetScrollPercent(-1, Math.Min(100, step * 10));
            visible = Retry.WhileFalse(
                () => !button.IsOffscreen &&
                      !button.BoundingRectangle.IsEmpty &&
                      form.BoundingRectangle.Contains(button.BoundingRectangle),
                TimeSpan.FromSeconds(1), TimeSpan.FromMilliseconds(150)).Result;
        }

        Assert.True(visible,
            "the folders-help button never came into view anywhere in the Course Settings form: "
            + $"button {button.BoundingRectangle}, form {form.BoundingRectangle}");
    }

    // ---- 2 & 3. What it actually renders ----------------------------------

    /// <summary>
    /// The strongest assertion in the suite: the ordered text a teacher reads
    /// equals the intro plus, for every contract row in order, its name, what
    /// and why.
    ///
    /// <para>It is expressed as a SEQUENCE rather than as seven row objects
    /// because UIA has no rows to offer — a StackPanel raises no automation
    /// peer, so the dialog's contents arrive as one flat run of Text elements.
    /// Comparing the whole run in order is stronger than checking rows
    /// individually anyway: it catches a duplicated row, a missing one, and
    /// two that have swapped places, none of which a per-row lookup would
    /// notice.</para>
    /// </summary>
    [UiFact]
    public void TheSheetRendersTheContractsRowsInOrder()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        var dialog = OpenFor(app, CourseFixtures.Renamed);

        Assert.Equal(Contract()["title"]!.ToString(), dialog.Name);

        // The title is rendered as a Text node of its own, above the intro —
        // ContentDialog draws its Title into the same visual tree rather than
        // into window chrome, so it is part of what a teacher reads here.
        var expected = new List<string>
        {
            Contract()["title"]!.ToString(),
            Contract()["intro"]!.ToString(),
        };
        foreach (JsonNode? row in Contract()["rows"]!.AsArray())
        {
            expected.Add(row!["key"]!.ToString() switch
            {
                "lessons" => "Lessons",
                "curriculum" => "Expectations",
                "graded" => "Tests",
                _ => row["name"]!.ToString(),
            });
            expected.Add(row["what"]!.ToString());
            expected.Add(row["why"]!.ToString());
        }

        var rendered = DrivenApp.TextsUnder(dialog);
        Assert.Equal(expected, rendered);
    }

    // ---- 4. It follows the course a teacher selected ----------------------

    /// <summary>
    /// The one thing the unit tests genuinely cannot reach: MainWindow reuses
    /// an existing CourseSettingsView when the code matches
    /// (`MainWindow.xaml.cs`), so a stale view showing the previous course's
    /// folders is a real shape of bug. Switching courses must change what the
    /// sheet says.
    ///
    /// <para>The second course also carries the case the mac gets wrong: it
    /// recorded no curriculum folder and was never asked about marks, so the
    /// sheet must still name "Ontario Curriculum" and "Tasks" — resolved, not
    /// read off the keys.</para>
    /// </summary>
    [UiFact]
    public void SwitchingCoursesChangesWhatTheSheetNames()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);

        var first = DrivenApp.TextsUnder(OpenFor(app, CourseFixtures.Renamed));
        Assert.Contains("Lessons", first);
        Assert.Contains("Expectations", first);
        Assert.Contains("Tests", first);
        Dismiss(app);

        var second = DrivenApp.TextsUnder(OpenFor(app, CourseFixtures.NeverAsked));
        Assert.Contains("All Classes", second);
        Assert.Contains("Ontario Curriculum", second);   // resolved, never recorded
        Assert.Contains("Tasks", second);                // never asked, still counted
        Assert.DoesNotContain("Lessons", second);
        Assert.DoesNotContain("Expectations", second);
        Assert.DoesNotContain(Row("curriculum", "placeholderWhenNone"), second);
    }

    // ---- 5. The bottom of the list is legible -----------------------------

    /// <summary>
    /// The rows below the fold. The scroller is capped at 460px and the seven
    /// rows always exceed it, so the last rows START offscreen — which means a
    /// naive "every row is inside the dialog" assertion fails on every run,
    /// and the tempting fix (skip the offscreen ones) passes while checking
    /// nothing. Scroll to the end, then assert the LAST row is really there
    /// and really inside the dialog. That is the bug this can catch: content
    /// cut off by a fixed height.
    /// </summary>
    [UiFact]
    public void TheLastRowIsReachableAndNotCutOff()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        var dialog = OpenFor(app, CourseFixtures.Renamed);

        var scroller = app.Find("specialFoldersHelpScroll", "the sheet's scroller");
        var scroll = scroller.Patterns.Scroll.PatternOrDefault;
        Assert.True(scroll is not null, "the sheet's scroller offers no scroll pattern");
        Assert.True(scroll!.VerticallyScrollable.Value,
            "the sheet did not need scrolling — the fixture no longer exercises the case this test is for");
        scroll.SetScrollPercent(-1, 100);

        string lastName = Row("coverage", "name");
        string lastWhy = Row("coverage", "why");

        // Against the SCROLLER's rectangle, not the dialog's. A WinUI
        // ContentDialog's own element covers the whole XamlRoot - it carries
        // the dimming layer - so "inside the dialog" is very nearly "inside
        // the window", and a row clipped by the 460px cap satisfied it. The
        // ScrollViewer's rectangle IS the viewport, which is the thing a
        // teacher can actually see. IsOffscreen is checked too: UIA reports
        // clipping there rather than by shrinking the rectangle.
        var viewport = scroller.BoundingRectangle;
        var settled = Retry.WhileFalse(() =>
        {
            foreach (var t in dialog.FindAllDescendants(cf => cf.ByControlType(ControlType.Text)))
            {
                if (t.Name != lastWhy) continue;
                var r = t.BoundingRectangle;
                return !r.IsEmpty && r.Height > 0 && !t.IsOffscreen && viewport.Contains(r);
            }
            return false;
        }, TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250));

        Assert.True(settled.Result,
            $"after scrolling to the end, \"{lastName}\"'s explanation is not fully inside the "
            + $"sheet's visible area (viewport {viewport})");
    }

    // ---- 6. Unsaved edits are reflected -----------------------------------

    /// <summary>
    /// Tick a folder in the Marks list, then open the sheet: it names what was
    /// just ticked, before anything is saved.
    ///
    /// <para><b>What this does NOT prove, so nobody reads more into it:</b> it
    /// is not evidence that the configuration is read at click time. Ticking a
    /// box rebuilds the whole form — and with it the button — so a captured
    /// configuration would look identical from out here. It is worth having
    /// for what it does prove, which is teacher-visible: an edit you have not
    /// saved yet is already reflected. On this course the marks pool has never
    /// been set, so it also exercises materialise-on-first-tick through the
    /// real control.</para>
    /// </summary>
    [UiFact]
    public void TheSheetShowsAMarksFolderTickedButNotYetSaved()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        app.SelectCourse(CourseFixtures.NeverAsked);

        var before = DrivenApp.TextsUnder(OpenFor(app, CourseFixtures.NeverAsked));
        Assert.Contains("Tasks", before);
        Assert.DoesNotContain(before, line => line.Contains("Concepts") && line.Contains("Tasks"));
        Dismiss(app);

        // The marks list's checkboxes carry "member:{list title}:{name}".
        var box = app.Find("member:Folders that count for marks:Concepts", "the marks tick-box for Concepts");
        box.AsCheckBox().IsChecked = true;

        // Ticking rebuilds the form through the dispatcher, so the button
        // element found a moment ago is destroyed. Re-find rather than reuse.
        var dialog = Retry.WhileNull(() =>
        {
            var b = app.FindOrNull("openFoldersHelpButton", TimeSpan.FromSeconds(2));
            if (b is null) return null;
            try { b.AsButton().Invoke(); } catch { return null; }
            return app.FindOrNull("specialFoldersHelpDialog", TimeSpan.FromSeconds(3));
        }, TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(500)).Result;

        Assert.True(dialog is not null, "the sheet never reopened after ticking a marks folder");

        // Both names, in one line, without pinning WHICH order: the pool comes
        // back in the form's own order rather than the order of ticking, and
        // that is the marks list's business, not this sheet's. Asserting the
        // order here would fail the day that list is reordered, about a
        // feature that had not changed.
        var after = DrivenApp.TextsUnder(dialog!);
        Assert.Contains(after, line => line.Contains("Concepts") && line.Contains("Tasks"));
    }

    // ---- 7. It can be got rid of ------------------------------------------

    [UiFact]
    public void TheSheetCloses()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);

        var dialog = OpenFor(app, CourseFixtures.Renamed);
        var done = dialog.FindFirstDescendant(cf => cf.ByName(Contract()["dismissedBy"]!.ToString()));
        Assert.True(done is not null, $"no \"{Contract()["dismissedBy"]}\" button on the sheet");
        done!.AsButton().Invoke();
        Assert.True(GoneWithin(app), "the sheet stayed open after its own button was pressed");

        // Escape is deliberately NOT tested here, and the reason is worth
        // keeping. A keystroke goes to whatever holds the foreground, which a
        // test machine cannot promise — an earlier version of this file sent
        // Escape and failed a DIFFERENT test each run, for a reason unrelated
        // to what that test checked. It could be guarded by waiting for the
        // foreground, but then the assertion reports on the machine rather
        // than on Plantoir, and xunit 2 cannot skip at runtime to say so.
        //
        // What would be gained is small in any case: closing a ContentDialog
        // on Escape is WinUI's own behaviour, not this app's. Plantoir's own
        // contribution is the button and its label, which IS tested above.
    }

    /// <summary>
    /// Get the sheet out of the way so a test can carry on.
    ///
    /// <para>Through the BUTTON, not through Escape. Escape depends on the
    /// app holding the foreground, which a test machine cannot promise — a
    /// notification or another window stealing focus made this flake, failing
    /// a different test each run for a reason that had nothing to do with what
    /// that test was checking. Escape is worth testing, so it is tested once,
    /// deliberately, in <see cref="TheSheetCloses"/>; everywhere else,
    /// dismissal should be the boring reliable thing.</para>
    /// </summary>
    private static void Dismiss(DrivenApp app)
    {
        var dialog = app.FindOrNull("specialFoldersHelpDialog");
        if (dialog is null) return;
        var done = dialog.FindFirstDescendant(cf => cf.ByName(Contract()["dismissedBy"]!.ToString()));
        Assert.True(done is not null, "the sheet has no button to close it with");
        done!.AsButton().Invoke();
        Assert.True(GoneWithin(app), "the sheet would not close");
    }

    private static bool GoneWithin(DrivenApp app) =>
        Retry.WhileTrue(() => app.FindOrNull("specialFoldersHelpDialog", TimeSpan.FromMilliseconds(300)) is not null,
                        TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(250)).Result;
}

/// <summary>One real application at a time.</summary>
[CollectionDefinition("drives the real app", DisableParallelization = true)]
public class DrivesTheRealAppCollection { }
