using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using Plantoir.Core.Models;

namespace Plantoir.UiTests;

/// <summary>
/// The New Course wizard's Create button, pressed in a running app.
///
/// <para><b>Why this suite exists at all.</b> Creating a course was proven
/// "underneath" long before it was proven through the interface: the
/// <c>setup.ps1</c> plus answer-pump path ran to completion through
/// <c>PtyDriver</c>, and the app carries <c>--auto-createcourse CODE</c>
/// (<c>MainWindow.RunAutomationHooks</c>), which reaches the same code by
/// calling <c>NewCourseDialog.AutoCreate</c> — and <c>AutoCreate</c> runs
/// <c>StartCreation()</c> from the dialog's <c>Opened</c> event, so the BUTTON
/// is never pressed. That gap was handoff item 35. **A later reader must not
/// "simplify" TheCreateButtonReallyMakesACourse into `--auto-createcourse`:
/// doing so deletes the only coverage of the button and leaves a test with the
/// same name that proves what was already proven.**</para>
///
/// <para><b>This is the first UI test that runs a LAUNCHER.</b> That is safe
/// for narrow reasons that nothing enforces, written out once in
/// <c>documentation/12-windows-app.md</c> under "The flags the app answers".
/// Read them before running a DIFFERENT launcher from a test: preview and
/// scheduled deploy would NOT be safe.</para>
///
/// <para>Serialised with the rest: one real application at a time.</para>
/// </summary>
[Collection("drives the real app")]
public class NewCourseWizardUiTests
{
    /// <summary>
    /// A course code the fixture folder does not already have, and which has
    /// no <c>support/example_content</c> payload — so Create takes the
    /// skeleton path (the wizard's <c>_startsFromSkeleton</c> ships ON) rather
    /// than copying a whole ready-made course. That is both the quicker run
    /// and the one most teachers get, since 38 codes have payloads and about
    /// 1,900 do not.
    /// </summary>
    private const string FreshCode = "MFM2P";

    /// <summary>
    /// How long Create is given. The whole thing took <b>16 seconds</b> when
    /// driven by hand on 2026-09-07 (Lenovo 20QES70500, Intel Core i5-8365U
    /// @ 1.60 GHz, 16 GB) — this is that with room for a machine under load,
    /// not an estimate. It is separate from <c>DrivenApp.Patience</c>, whose
    /// 30 seconds is for the interface catching up rather than for a launcher
    /// answering prompts at 600 ms of settle each.
    /// </summary>
    private static readonly TimeSpan LongEnoughToCreateACourse = TimeSpan.FromMinutes(4);

    // ---- 1. Can a teacher get into the wizard at all? ---------------------

    /// <summary>
    /// The button in the course list opens the wizard, and Create is not yet
    /// available.
    ///
    /// <para>`DrivenApp`'s constructor already waits for `addCourseButton` to
    /// EXIST — that is how it knows the working folder was accepted — but
    /// existing and opening something are different claims, and only the
    /// second is what a teacher does with it.</para>
    ///
    /// <para>The disabled state is <c>RefreshCreateEnabled</c>'s rule, which no
    /// unit test can see through a window: an empty code is not-ready-yet
    /// rather than an error, so the wizard opens with nothing said and nothing
    /// to press.</para>
    /// </summary>
    [UiFact]
    public void TheAddCourseButtonOpensTheWizardWithCreateNotYetAvailable()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        OpenWizard(app);

        var create = app.Find("PrimaryButton", "the wizard's Create button");
        // Contract data since 2026-09-08: shared-rules.json -> wizard
        // .createCourseButton, which the mac asserts in a gated test. This
        // assertion is still worth keeping — it proves the button can be
        // REACHED and reads correctly, which a contract test cannot — but it
        // is no longer the only thing pinning the label, and it should compare
        // against the contract rather than a literal. See issue #119.
        Assert.Equal("Create Course", create.Name);
        Assert.False(create.IsEnabled, "Create was available before a code had been typed");

        // And there is a way out that is not the Create button.
        Assert.True(app.FindOrNull("CloseButton") is not null, "the wizard offered no Cancel");
    }

    // ---- 2. A greyed-out Create button is never a mystery -----------------

    /// <summary>
    /// Typing a code the folder already has explains itself beside the field,
    /// and Create stays unavailable.
    ///
    /// <para><b>What this does NOT re-prove.</b> Every case in
    /// <c>course-management.json</c> → <c>courseCode.problems</c> is already
    /// run against <c>CourseCodeValidator</c> by <c>ContractTests</c>; putting
    /// that sweep through a real window would re-prove a pure function slowly.
    /// What is new here is that the sentence REACHES the teacher — that it is
    /// rendered next to the box rather than computed and dropped — and that
    /// the button it explains really is still off.</para>
    ///
    /// <para>The expected sentence is computed by calling the same rule rather
    /// than copied out of the contract: a quoted copy, or a copy made by
    /// substituting a code into another case's sentence, is the one that keeps
    /// passing after the product's words change.</para>
    /// </summary>
    [UiFact]
    public void ADuplicateCodeIsExplainedBesideTheFieldAndCreateStaysUnavailable()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        OpenWizard(app);
        PutCodeIn(app, CourseFixtures.Renamed);   // the folder already has this one

        string expected = CourseCodeValidator.Problem(
            CourseFixtures.Renamed,
            new[] { CourseFixtures.Renamed, CourseFixtures.NeverAsked })
            ?? throw new Xunit.Sdk.XunitException(
                "the fixture no longer produces a duplicate-code problem, so this test checks nothing");

        // The warning is collapsed until there is something to say, so the
        // wait is on the SENTENCE arriving rather than on the element.
        string lastSeen = "";
        var said = Retry.WhileFalse(() =>
        {
            var warning = app.FindOrNull("newCourseCodeWarning", TimeSpan.FromMilliseconds(400));
            lastSeen = warning is null ? "<not shown>" : (warning.Name ?? "");
            return lastSeen == expected;
        }, TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250));

        Assert.True(said.Result,
            $"the wizard never explained the duplicate code beside the field. Expected \"{expected}\", saw \"{lastSeen}\".");

        Assert.False(app.Find("PrimaryButton", "the wizard's Create button").IsEnabled,
            "Create was available for a course code that already exists");
    }

    // ---- 3. The button really makes a course ------------------------------

    /// <summary>
    /// The headline, and the whole reason handoff item 35 existed: press
    /// Create, and a course exists on disk and in the sidebar.
    ///
    /// <para>Note WHICH file proves what. <c>course_config.json</c> is written
    /// by the APP before the launcher is started
    /// (<c>NewCourseCreator.CreateCourse</c>), so its presence proves only that
    /// the app wrote a file. What proves <c>setup.ps1</c> ran to the end is the
    /// content it makes and the app does not: the section folder with its
    /// front page, and every shared folder the configuration named.</para>
    /// </summary>
    [UiFact]
    public void TheCreateButtonReallyMakesACourse()
    {
        using var app = new DrivenApp(CourseFixtures.WriteBoth);
        OpenWizard(app);
        PutCodeIn(app, FreshCode);

        var create = app.Find("PrimaryButton", "the wizard's Create button");
        Assert.True(Retry.WhileFalse(() => create.IsEnabled,
                                     TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(250)).Result,
                    $"Create never became available for {FreshCode}");
        create.AsButton().Invoke();

        WaitForTheWorkToFinish(app);

        // On disk, in the temp working folder — never the teacher's own.
        string courseDir = Path.Combine(app.WorkspacePath, "courses", FreshCode);
        string configPath = Path.Combine(courseDir, "course_config.json");
        Assert.True(File.Exists(configPath), $"no course_config.json under {courseDir}");

        var written = JsonNode.Parse(File.ReadAllText(configPath))!;
        Assert.Equal(FreshCode, written["course_code"]!.ToString());

        Assert.True(Directory.Exists(Path.Combine(courseDir, "section1")),
                    "the launcher never made section1 — the app's own configuration file is all that exists");
        Assert.True(File.Exists(Path.Combine(courseDir, "section1", "index.md")),
                    "section1 has no front page, so setup.ps1 did not finish");

        // Read from the configuration rather than from a list typed here: the
        // folders come from MFM2P's skeleton, and pinning their names would
        // fail the day the skeleton is regenerated, about a feature that had
        // not changed.
        foreach (JsonNode? folder in written["shared_folders"]!.AsArray())
        {
            string name = folder!.ToString();
            Assert.True(Directory.Exists(Path.Combine(courseDir, name)),
                        $"the configuration names a shared folder \"{name}\" that was never made");
        }

        // Cancel is gone, which is FinishProgress emptying CloseButtonText —
        // the affirmative button becoming usable again is already what
        // WaitForTheWorkToFinish waited for, so it is not re-asserted here.
        // (Asserting the button's LABEL would prove nothing either way:
        // BeginProgress renames it to "Close" the instant Create is pressed.)
        // This does lean on the ContentDialog template dropping a button whose
        // text is empty rather than showing a blank one — true today, and the
        // thing to suspect first if this line ever fails on its own.
        Assert.True(app.FindOrNull("CloseButton", TimeSpan.FromSeconds(2)) is null,
                    "Cancel was still offered after the course had been made");

        create.AsButton().Invoke();

        // And the course list caught up: closing the wizard reloads the
        // workspace and selects what was just made (SidebarPane.OpenNewCourseWizard).
        Assert.True(Retry.WhileNull(() => app.FindOrNull("sidebar-" + FreshCode, TimeSpan.FromSeconds(1)),
                                    TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result is not null,
                    $"{FreshCode} was made on disk but never appeared in the course list");
    }

    // ---- Driving the wizard -----------------------------------------------

    /// <summary>Press the button in the course list and wait for the wizard.</summary>
    private static AutomationElement OpenWizard(DrivenApp app)
    {
        // Invoked rather than clicked: a physical click can land while
        // something else briefly holds the foreground, and this button offers
        // Invoke, so there is no reason to take that risk. (The sidebar's
        // course entries are the exception — they act on TreeView.ItemInvoked,
        // which only a mouse raises; see DrivenApp.SelectCourse.)
        app.Find("addCourseButton", "the button that adds a course").AsButton().Invoke();

        var wizard = Retry.WhileNull(() => app.FindOrNull("newCourseDialog", TimeSpan.FromSeconds(1)),
                                     TimeSpan.FromSeconds(20), TimeSpan.FromMilliseconds(250)).Result;
        Assert.True(wizard is not null, "pressing the add-course button opened no wizard");
        return wizard!;
    }

    /// <summary>
    /// Put a course code into the picker the way a teacher's typing would.
    ///
    /// <para>The value goes into the AutoSuggestBox's inner Edit, not into the
    /// box itself: UIA offers ValuePattern on the text control inside, and the
    /// wizard's whole form hangs off that box's <c>TextChanged</c>. Measured
    /// on 2026-09-07 rather than assumed — setting the Edit really does raise
    /// it, and the name suggestions appear, so the code that follows can rely
    /// on the same refreshes a teacher gets.</para>
    ///
    /// <para><b>Not keystrokes.</b> This suite has already paid for that once:
    /// a keystroke goes to whatever holds the foreground, and an earlier
    /// version of <c>SpecialFoldersHelpUiTests</c> failed a DIFFERENT test each
    /// run for a reason unrelated to what that test checked.</para>
    /// </summary>
    private static void PutCodeIn(DrivenApp app, string code)
    {
        var box = app.Find("newCourseCodeBox", "the course-code picker");
        var edit = Retry.WhileNull(() => box.FindFirstDescendant(cf => cf.ByControlType(ControlType.Edit)),
                                   TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result;
        Assert.True(edit is not null, "the course-code picker has no text control inside it");
        edit!.Patterns.Value.Pattern.SetValue(code);

        // Wait for the box to REPORT the code back before going on. Every
        // later assertion is about something downstream of this, and a race
        // here would fail them saying something untrue about the product.
        Assert.True(Retry.WhileFalse(() => (edit.Patterns.Value.Pattern.Value.Value ?? "") == code,
                                     TimeSpan.FromSeconds(10), TimeSpan.FromMilliseconds(200)).Result,
                    $"the course-code picker never took \"{code}\"");
    }

    /// <summary>
    /// Wait for the wizard's progress view to reach an ending, and say what
    /// went wrong in the language the teacher was given if it is the wrong one.
    ///
    /// <para>"Done" is <c>TaskProgressView</c>'s own word for a launcher that
    /// exited zero. A bare timeout here would report "never found
    /// taskPhaseLabel", which is a sentence about the test rather than about
    /// the failure, so the app's own explanation and the tail of its console
    /// are pulled into the message instead.</para>
    /// </summary>
    private static void WaitForTheWorkToFinish(DrivenApp app)
    {
        // Wait for the work to have STARTED before waiting for it to end.
        // Without this the next wait is racy in the direction that lies:
        // InvokePattern.Invoke is asynchronous by contract, so a first poll of
        // IsEnabled can still see the TRUE that Create had before
        // BeginProgress disabled it — and the test would then fail complaining
        // about the ending rather than about a click that had not landed.
        // The progress view only exists once BeginProgress has swapped it in.
        Assert.True(Retry.WhileNull(() => app.FindOrNull("taskPhaseLabel", TimeSpan.FromSeconds(1)),
                                    TimeSpan.FromSeconds(15), TimeSpan.FromMilliseconds(200)).Result is not null,
                    "Create was pressed but the wizard never started work");

        // The ENDING is "the closing button became usable", not "the label says
        // Done": FinishProgress re-enables it however the launcher exited, so
        // waiting on it stops the moment the work stops. Waiting on the word
        // "Done" alone would sit out the whole timeout on a failure and then
        // report a timeout, which is a sentence about the test rather than
        // about what broke.
        var create = app.Find("PrimaryButton", "the wizard's closing button");
        bool ended = Retry.WhileFalse(() => create.IsEnabled,
                                      LongEnoughToCreateACourse, TimeSpan.FromMilliseconds(500)).Result;

        var phase = app.FindOrNull("taskPhaseLabel", TimeSpan.FromSeconds(2));
        string said = phase?.Name ?? "<nothing>";
        if (ended && said == "Done") return;

        throw new Xunit.Sdk.XunitException(
            (ended
                ? $"creating a course ended, but not well: the wizard said \"{said}\"."
                : $"creating a course never finished within {LongEnoughToCreateACourse.TotalMinutes} minutes; "
                  + $"the wizard last said \"{said}\".")
            + Explanation(app) + ConsoleTail(app));
    }

    /// <summary>The app's own words for the failure, when it has any.</summary>
    private static string Explanation(DrivenApp app)
    {
        string why = app.FindOrNull("failureExplanation", TimeSpan.FromSeconds(1))?.Name ?? "";
        return why.Length > 0 ? $" It explained it as \"{why}\"." : " It explained nothing.";
    }

    /// <summary>
    /// The end of what the launcher printed, which is where the real reason
    /// usually is. Opened by pressing the app's own "Show details" rather than
    /// read from a file, because the console is only in the visual tree once
    /// that pane is open.
    /// </summary>
    private static string ConsoleTail(DrivenApp app)
    {
        try
        {
            if (app.FindOrNull("consoleText", TimeSpan.FromMilliseconds(500)) is null)
                app.FindOrNull("taskDetailsDisclosure", TimeSpan.FromSeconds(2))?.AsButton().Invoke();
            string text = app.FindOrNull("consoleText", TimeSpan.FromSeconds(5))?.Name ?? "";
            if (text.Length == 0) return " Its console said nothing.";
            var lines = text.Replace("\r", "").Split('\n');
            int from = Math.Max(0, lines.Length - 25);
            return "\nThe last of what it printed:\n  " + string.Join("\n  ", lines[from..]);
        }
        catch (Exception error)
        {
            return $" (Its console could not be read: {error.Message})";
        }
    }
}
