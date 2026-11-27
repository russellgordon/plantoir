using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Views;

/// <summary>
/// "Get Ready for the Start of the Year…" and its undo, from a section's menu
/// (GitHub issue #355, the mac's #96). The sheet lists every page going into
/// draft with its reason, what stays, the links that will lead to hidden pages
/// and the warnings — all of it <see cref="StartOfYearWording.Describe"/>, the
/// same words an outside assistant is shown. Go re-plans with the code the
/// sheet was made from, takes the teacher's own backup, and refuses if it
/// cannot. Nothing reaches students until a deploy.
/// </summary>
public static class StartOfYearDialog
{
    public static async Task<string?> OfferAsync(string folder, Course course, int section,
                                                 Func<ContentDialog, Task<ContentDialogResult?>> show,
                                                 Func<bool> folderMovedMeanwhile,
                                                 StartOfYearRestoreAnswers restoreAnswers)
    {
        var workspace = new AssistWorkspace(folder, new NoLauncher(), undo: new UndoHistory())
        {
            Surface = AssistSurface.LocalWindow,   // in-process: Plantoir's own, never an outside assistant (fix round ruling 7)
#if DEBUG
            StopsPartWayForUiTests = StopsPartWayForUiTests,
#endif
        };
        var proposal = workspace.PlanStartOfYear(course.Code, section);
        if (proposal.Plan.First is null || proposal.Plan.NothingToDo)
        {
            ActivityTrail.Note(ActivityTrail.Event.StartOfYearNotDone,
                $"did not get ready for the start of the year from the app — nothing was changed ({(proposal.Plan.First is null ? "noFirstClass" : "nothingToDo")})",
                course.Code, section);
            return proposal.TeacherText;
        }

        // The sheet in its pieces (#619): the same sentences the plan's text
        // carries, with the two lists of lines as one table. The code line is
        // for an outside assistant and means nothing here.
        DateTime? scheduledFor = null;
        try { scheduledFor = TaskScheduling.NextRun(folder, course.Code, section); } catch { }
        var sheet = StartOfYearSheet.Make(proposal.Plan, DateOnly.FromDateTime(DateTime.Now), scheduledFor,
            workspace.StartOfYearPagesWithNoRoom(course.Code, section, proposal.Plan), course.Configuration.ClassNoun);
        var dialog = new ContentDialog
        {
            Title = StartOfYearWording.Fill(StartOfYearWording.SheetTitle, ("course", course.Code), ("section", section.ToString())),
            PrimaryButtonText = StartOfYearWording.GoButton,
            CloseButtonText = "Cancel",
        };
        // Russell's ruling Q-B on #975 (the mac's D39): getting ready can lose
        // work, so no button is the default; the focus starts on Cancel (#979).
        DialogButtons.AskWithNoDefault(dialog);
        AutomationProperties.SetAutomationId(dialog, "startOfYearDialog");
        StartOfYearSheetView.Build(dialog, sheet);
        // Go runs in its own press, with the sheet still up (#899 W8c-2b):
        // a part-way stop keeps this dialog open and turns it into the offer,
        // so no second dialog ever stands over it (Apple's HIG, Sheets: "If
        // something people do within a sheet results in another sheet
        // appearing, close the first sheet before displaying the new one";
        // WinUI allows one ContentDialog per window). Every other outcome
        // closes it and is said as before.
        string? said = null;
        StartOfYearRestoreOffer? offer = null;
        bool restoreCourse = false;
        dialog.PrimaryButtonClick += (_, args) =>
        {
            if (offer is null)
            {
                if (folderMovedMeanwhile()) return;
                said = Go(folder, course, section, workspace, proposal, out StartOfYearStoppedPartWay? stop);
                if (stop is not null)
                {
                    offer = new StartOfYearRestoreOffer(stop, () => CourseActivity.IsPublishing(folder, course.Code));
                    args.Cancel = true;
                    ShowTheOffer(dialog, offer);
                }
                return;
            }
            // Answered in the press's own turn (the mac's restoreCourseIsPressed).
            switch (offer.RestoreCourseIsPressed())
            {
                case RestoreCoursePress.HeldBackByADeploy:
                    args.Cancel = true;
                    ShowTheOffer(dialog, offer, offer.HeldBackSentence);
                    break;
                case RestoreCoursePress.Closes:
                    restoreCourse = true;
                    break;
                case RestoreCoursePress.AlreadyAnswered:
                    break;
            }
        };
        // Leave As It Is: Escape, or the button itself. Changes nothing; the backup stays in Backups.
        dialog.CloseButtonClick += (_, _) => offer?.LeaveAsItIs();

        await show(dialog);
        if (offer is not null)
        {
            // Closed some other way (the window went): as Leave As It Is.
            offer.LeaveAsItIs();
            if (restoreCourse) await offer.RestoreCourseAsync(restoreAnswers);
            return null;
        }
        return said;
    }

    /// <summary>
    /// The offer, in the Go dialog itself: <c>stoppedPartWay</c>, then
    /// <c>restoreOffer</c>, then the restore's busy sentence while a deploy
    /// holds it back. Restore Course is the primary button and the default
    /// (Enter), Leave As It Is the close button (Escape): Microsoft's Dialog
    /// controls, "The 'do it' action button(s) should appear as the leftmost
    /// buttons. The safe, nondestructive action should appear as the rightmost
    /// button." Restore Course is not destructive (Archived keeps the course
    /// as it is now), so it may be the default (Apple's HIG, Buttons ▸ Role).
    /// </summary>
    private static void ShowTheOffer(ContentDialog dialog, StartOfYearRestoreOffer offer, string? heldBack = null)
    {
        var lines = new StackPanel { Spacing = 12 };
        foreach (string sentence in offer.Sentences)
            lines.Children.Add(new TextBlock { Text = sentence, TextWrapping = TextWrapping.Wrap });
        if (heldBack is not null)
        {
            var busy = new TextBlock { Text = heldBack, TextWrapping = TextWrapping.Wrap };
            AutomationProperties.SetAutomationId(busy, "startOfYearRestoreHeldBack");
            AutomationProperties.SetLiveSetting(busy, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Assertive);
            lines.Children.Add(busy);
        }
        dialog.Content = new ScrollViewer { Content = lines, MaxHeight = 480 };
        dialog.PrimaryButtonText = StartOfYearWording.RestoreCourseButton;
        dialog.CloseButtonText = StartOfYearWording.LeaveAsItIsButton;
        // The Go page had no default (Q-B on #975); the offer's is Restore Course.
        dialog.PrimaryButtonStyle = null;
        DialogButtons.EnablePrimary(dialog, true);
        // Enter goes to the focused button before the default, so the focus
        // is put on the default itself (it may have been on Cancel).
        if (DialogButtons.TemplatePart(dialog, "PrimaryButton") is Control restore) restore.Focus(FocusState.Programmatic);
    }

    /// <summary>Go itself, with the deploy check: what to say once the sheet has closed, or the part-way stop the sheet offers the restore for.</summary>
    private static string? Go(string folder, Course course, int section, AssistWorkspace workspace, StartOfYearProposal proposal,
                              out StartOfYearStoppedPartWay? stop)
    {
        stop = null;
        if (CourseActivity.IsPublishing(folder, course.Code))
        {
            ActivityTrail.Note(ActivityTrail.Event.StartOfYearNotDone,
                "did not get ready for the start of the year from the app — nothing was changed (deployUnderWay)", course.Code, section);
            return StartOfYearWording.Fill(StartOfYearWording.DeployUnderWay, ("course", course.Code));
        }

        var outcome = workspace.PrepareForStartOfYear(course.Code, section, proposal.Code, StartOfYearAskedFrom.TheApp,
            new BackupMaker.Teacher());
        // Part way: the sheet's offer, never the assistants' sentence (no per-file kept sentence, the ruling).
        if (outcome.StoppedPartWay is { } partWay)
        {
            stop = partWay;
            return null;
        }
        if (!outcome.Changed)
        {
            // Over MCP these are the assistant's sentences; from the app the sheet's own.
            if (outcome.Message == AssistWording.StartOfYearPlanHasChanged(course.Code, section.ToString()))
                return StartOfYearWording.ChangedSinceShown + "\n\n" + workspace.PlanStartOfYear(course.Code, section).TeacherText;
            if (outcome.Message == AssistWording.StartOfYearNeedsABackup(course.Code))
                return StartOfYearWording.Fill(StartOfYearWording.BackupFailed, ("course", course.Code));
            return outcome.Message;
        }

        string backupName = Path.GetFileName(outcome.BackupPath ?? "");
        DateTime? scheduled = null;
        try { scheduled = TaskScheduling.NextRun(folder, course.Code, section); } catch { }
        StartOfYearSessionUndo.Remember(folder, course.Code, section, new StartOfYearSessionUndo.Entry(
            outcome.Written, outcome.BackupPath ?? "", workspace.PlanStartOfYear(course.Code, section).Code,
            DateTime.Now, scheduled));
        return string.Join("\n\n", outcome.Message,
            StartOfYearWording.Fill(StartOfYearWording.UndoAvailable, ("backup", backupName)),
            StartOfYearWording.UndoEndsWhenYouQuit);
    }

#if DEBUG
    /// <summary>A UI test's: Go stops part way (<see cref="AssistWorkspace.StopsPartWayForUiTests"/>). Set only by the Debug build's <c>--start-of-year-stops-part-way-for-tests</c>.</summary>
    public static bool StopsPartWayForUiTests { get; set; }
#endif

    /// <summary>The undo sheet: lists what would go back, and what changed since and stays.</summary>
    public static async Task<string?> UndoAsync(string folder, Course course, int section,
                                                Func<ContentDialog, Task<ContentDialogResult?>> show,
                                                Func<bool> folderMovedMeanwhile)
    {
        if (StartOfYearSessionUndo.For(folder, course.Code, section) is not { } entry) return null;
        string backupName = Path.GetFileName(entry.BackupPath);
        var workspace = new AssistWorkspace(folder, new NoLauncher(), undo: new UndoHistory())
            { Surface = AssistSurface.LocalWindow };   // in-process: Plantoir's own, never an outside assistant (fix round ruling 7)

        // A scheduled deploy since the act ends it — the schedule read again
        // now, as the sheet opens — and so does the next change to the
        // section's pages from anywhere.
        DateTime? lastScheduledRun = null;
        try { lastScheduledRun = ScheduledPublishOutcome.Read(course.Code, section, folder)?.When; } catch { }
        DateTime? scheduledNow = null;
        try { scheduledNow = TaskScheduling.NextRun(folder, course.Code, section); } catch { }
        if (StartOfYearSessionUndo.EndedByAScheduledDeploy(entry, DateTime.Now, lastScheduledRun, scheduledNow)
            || !string.Equals(workspace.PlanStartOfYear(course.Code, section).Code, entry.SectionCodeAfter, StringComparison.Ordinal))
        {
            StartOfYearSessionUndo.End(folder, course.Code, section);
            return StartOfYearWording.UndoHasEnded + " " + StartOfYearWording.Fill(StartOfYearWording.BackupHoldsIt, ("backup", backupName));
        }
        if (CourseActivity.IsPublishing(folder, course.Code))
            return StartOfYearWording.Fill(StartOfYearWording.DeployUnderWay, ("course", course.Code));

        // Named as the plan names them (#389): title, and folder only when two share it.
        var pages = workspace.StartOfYearPages(workspace.Course(course.Code), section);
        var naming = StartOfYearPlan.Make(pages);
        string NameOf(string path) => pages.FirstOrDefault(p => string.Equals(p.Id, Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase))
            is { } page ? naming.NameOf(page) : StartOfYearWording.PageName(Path.GetFileNameWithoutExtension(path));
        // Sorted by the undo's own rule before the teacher agrees (#564): what
        // would go back, what changed since and stays, and a page already as
        // it was in neither list — so the sheet's count is the result's.
        var (wouldPutBack, wouldLeave) = AssistWorkspace.WhatAnUndoWouldDo(entry.Written);
        var lines = new List<string>
        {
            wouldPutBack.Count == 0 && wouldLeave.Count == 0
                ? StartOfYearWording.UndoAllAlreadyBack
                : StartOfYearWording.Fill(StartOfYearWording.UndoIntro, ("pages", StartOfYearWording.PagesCounted(wouldPutBack.Count))),
        };
        lines.AddRange(wouldPutBack.Select(path => "• " + NameOf(path)));
        if (wouldLeave.Count > 0)
        {
            lines.Add("");
            lines.Add(StartOfYearWording.Fill(StartOfYearWording.UndoSkipped, ("pages", StartOfYearWording.PagesCounted(wouldLeave.Count))));
            lines.AddRange(wouldLeave.Select(path => "• " + NameOf(path)));
        }
        var text = new TextBlock { Text = string.Join("\n", lines), TextWrapping = TextWrapping.Wrap };
        var dialog = new ContentDialog
        {
            Title = StartOfYearWording.Fill(StartOfYearWording.UndoTitle, ("course", course.Code), ("section", section.ToString())),
            Content = new ScrollViewer { Content = text, MaxHeight = 480 },
            PrimaryButtonText = StartOfYearWording.UndoButton,
            CloseButtonText = "Cancel",
            // The mac's undo sheet: Undo is the default while it would put a
            // page back (.defaultButton(isEnabled: !putBack.isEmpty)), and
            // greyed otherwise; a Cancel is never the default (#979).
            DefaultButton = ContentDialogButton.Primary,
        };
        // And Undo cannot be pressed when nothing would go back, as on the mac
        // (its isEnabled; the #979 review): pressing it then changed nothing
        // and only ended the undo. EnablePrimary first, since the helper keeps
        // the button's style as it finds it.
        DialogButtons.EnablePrimary(dialog, wouldPutBack.Count > 0);
        if (wouldPutBack.Count == 0) DialogButtons.AskWithNoDefault(dialog);
        AutomationProperties.SetAutomationId(dialog, "startOfYearUndoDialog");
        if (await show(dialog) != ContentDialogResult.Primary || folderMovedMeanwhile()) return null;

        var (putBack, left) = AssistWorkspace.UndoStartOfYear(entry.Written);
        StartOfYearSessionUndo.End(folder, course.Code, section);
        AssistWorkspace.NoteStartOfYearUndone(course.Code, section, StartOfYearAskedFrom.TheApp, putBack.Count, left.Count);
        if (putBack.Count == 0 && left.Count == 0) return StartOfYearWording.UndoAllAlreadyBack;
        string said = StartOfYearWording.Fill(StartOfYearWording.Undone, ("pages", StartOfYearWording.PagesCounted(putBack.Count)));
        if (left.Count > 0)
            said += " " + StartOfYearWording.Fill(StartOfYearWording.UndoLeftSome,
                ("pages", string.Join(", ", left.Select(NameOf))), ("backup", backupName));
        return said;
    }

    /// <summary>Getting ready launches nothing; anything that tries is refused.</summary>
    private sealed class NoLauncher : ILauncherRunner
    {
        public Task<LaunchOutcome> Run(string launcher, IReadOnlyList<string> arguments, string workingFolder,
                                       IProgress<string>? progress, CancellationToken cancellation) =>
            Task.FromResult(new LaunchOutcome(false, "Not from getting ready for the start of the year."));
    }
}
