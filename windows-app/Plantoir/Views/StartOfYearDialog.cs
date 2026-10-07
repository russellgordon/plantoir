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
                                                 Func<bool> folderMovedMeanwhile)
    {
        var workspace = new AssistWorkspace(folder, new NoLauncher(), undo: new UndoHistory())
            { ServesTheLocalWindow = true };   // in-process: Plantoir's own, never an outside assistant (fix round ruling 7)
        var proposal = workspace.PlanStartOfYear(course.Code, section);
        if (proposal.Plan.First is null || proposal.Plan.NothingToDo)
        {
            ActivityTrail.Note(ActivityTrail.Event.StartOfYearNotDone,
                $"did not get ready for the start of the year from the app — nothing was changed ({(proposal.Plan.First is null ? "noFirstClass" : "nothingToDo")})",
                course.Code, section);
            return proposal.TeacherText;
        }

        // The title is the sheet's own; the body is the plan without its code
        // line, which is for an outside assistant and means nothing here.
        string body = string.Join("\n", proposal.Text.Split('\n')
            .Skip(2).Where(line => !line.StartsWith("Plan code: ", StringComparison.Ordinal)));
        var text = new TextBlock { Text = body.Trim(), TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        AutomationProperties.SetAutomationId(text, "startOfYearPlan");
        var dialog = new ContentDialog
        {
            Title = StartOfYearWording.Fill(StartOfYearWording.SheetTitle, ("course", course.Code), ("section", section.ToString())),
            Content = new ScrollViewer { Content = text, MaxHeight = 480 },
            PrimaryButtonText = StartOfYearWording.GoButton,
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
        };
        AutomationProperties.SetAutomationId(dialog, "startOfYearDialog");
        var choice = await show(dialog);
        if (choice != ContentDialogResult.Primary || folderMovedMeanwhile()) return null;

        if (CourseActivity.IsPublishing(folder, course.Code))
        {
            ActivityTrail.Note(ActivityTrail.Event.StartOfYearNotDone,
                "did not get ready for the start of the year from the app — nothing was changed (deployUnderWay)", course.Code, section);
            return StartOfYearWording.Fill(StartOfYearWording.DeployUnderWay, ("course", course.Code));
        }

        var outcome = workspace.PrepareForStartOfYear(course.Code, section, proposal.Code, StartOfYearAskedFrom.TheApp,
            new BackupMaker.Teacher());
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

    /// <summary>The undo sheet: lists what would go back, and what changed since and stays.</summary>
    public static async Task<string?> UndoAsync(string folder, Course course, int section,
                                                Func<ContentDialog, Task<ContentDialogResult?>> show,
                                                Func<bool> folderMovedMeanwhile)
    {
        if (StartOfYearSessionUndo.For(folder, course.Code, section) is not { } entry) return null;
        string backupName = Path.GetFileName(entry.BackupPath);
        var workspace = new AssistWorkspace(folder, new NoLauncher(), undo: new UndoHistory())
            { ServesTheLocalWindow = true };   // in-process: Plantoir's own, never an outside assistant (fix round ruling 7)

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

        var lines = new List<string>
        {
            StartOfYearWording.Fill(StartOfYearWording.UndoIntro, ("pages", StartOfYearWording.PagesCounted(entry.Written.Count))),
        };
        // Named as the plan names them (#389): title, and folder only when two share it.
        var pages = workspace.StartOfYearPages(workspace.Course(course.Code), section);
        var naming = StartOfYearPlan.Make(pages);
        string NameOf(string path) => pages.FirstOrDefault(p => string.Equals(p.Id, Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase))
            is { } page ? naming.NameOf(page) : StartOfYearWording.PageName(Path.GetFileNameWithoutExtension(path));
        lines.AddRange(entry.Written.Keys.Select(path => "• " + NameOf(path)));
        var text = new TextBlock { Text = string.Join("\n", lines), TextWrapping = TextWrapping.Wrap };
        var dialog = new ContentDialog
        {
            Title = StartOfYearWording.Fill(StartOfYearWording.UndoTitle, ("course", course.Code), ("section", section.ToString())),
            Content = new ScrollViewer { Content = text, MaxHeight = 480 },
            PrimaryButtonText = StartOfYearWording.UndoButton,
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
        };
        AutomationProperties.SetAutomationId(dialog, "startOfYearUndoDialog");
        if (await show(dialog) != ContentDialogResult.Primary || folderMovedMeanwhile()) return null;

        var (putBack, left) = AssistWorkspace.UndoStartOfYear(entry.Written);
        StartOfYearSessionUndo.End(folder, course.Code, section);
        AssistWorkspace.NoteStartOfYearUndone(course.Code, section, StartOfYearAskedFrom.TheApp, putBack.Count, left.Count);
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
