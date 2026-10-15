using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Services;
using Plantoir.Views;
using Item = Plantoir.Core.Models.SubjectMenuRules.Item;

namespace Plantoir;

/// <summary>
/// The assistant's functions from the Section menu (#489, the mac's #457
/// batch B): Publish Pages…, Hide Pages…, Publish Class for a Date…, Rebuild
/// Preview, Undo Last Change · Add Next Class, Re-date Classes…, Make Room for
/// Classes…, Class Dates…. Each runs the TOOL's own code through
/// <see cref="AssistToolRunner"/> on the Menu surface, with a call built in
/// code — never through a model, so a teacher who declined the assistant's
/// download has every one of them.
/// </summary>
/// <remarks>
/// <para><b>One runner per window</b> (<see cref="SectionVerbs"/>), made the
/// first time an item is used, with its own <c>plantoir-mcp</c> behind it
/// (<see cref="McpClient.StartForTheMenu"/>): Undo Last Change takes back the
/// last change made from the menu in THIS window. Opening another folder in
/// the window, or closing it, stops that server and its undo list goes with
/// it — the mac's ruling (Russell's decision 4).</para>
///
/// <para><b>Class dates first.</b> Add Next Class, Re-date Classes… and Make
/// Room for Classes… need them; with none on file this window shows its own
/// class dates dialog with the reason, and the item runs once they are
/// written — never the assistant's offer, which only the assistant's window
/// shows (the mac's plan review, blocker 1).</para>
/// </remarks>
public sealed partial class MainWindow
{
    private SectionVerbs? _verbs;
    private string? _verbsFolder;

    /// <summary>This window's runner for the folder it shows, made on first use.</summary>
    private SectionVerbs? Verbs()
    {
        string? folder = Workspace.WorkspacePath;
        if (folder is null) return null;
        if (_verbs is not null && WorkingFolder.IsTheSame(_verbsFolder, folder)) return _verbs;
        DropVerbs();
        _verbsFolder = folder;
        _verbs = new SectionVerbs(folder,
            async cancellation => ClaudeCodeLauncher.FindServer() is { } server
                ? await McpClient.StartForTheMenu(server, folder, cancellation)
                : null,
            (code, section, tools) => MenuRunner(folder, code, section, tools));
        _verbs.Changed += VerbsChanged;
        return _verbs;
    }

    /// <summary>The window's runner: its server stops, and its undo list goes with it.</summary>
    private void DropVerbs()
    {
        if (_verbs is not { } old) return;
        old.Changed -= VerbsChanged;
        _verbs = null;
        _verbsFolder = null;
        // Once any change running now has finished, and off this thread: the
        // server's stop waits up to three seconds for it to exit (L4).
        _ = Task.Run(old.DisposeWhenIdleAsync);
    }

    private void VerbsChanged() => DispatcherQueue.TryEnqueue(() => { if (!IsClosed) ApplyMenuEnablement(); });

    /// <summary>
    /// The seams a menu call meets, wired to THIS window: a page edit stops a
    /// showing preview and starts it again (the runner's rule for every
    /// client); Rebuild Preview really rebuilds; a copy being saved refuses it.
    /// </summary>
    private AssistToolRunner MenuRunner(string folder, string code, int section, IToolServer tools) =>
        new(tools, code, section, AssistSurface.Menu)
        {
            ShowPreviewInApp = () => ShowPreviewFor(code, section),
            RebuildPreviewInApp = () => RebuildPreviewFor(code, section),
            PreviewIsShowing = () => PreviewLeases.Active.Any(lease =>
                WorkingFolder.IsTheSame(lease.FolderPath, folder)
                && string.Equals(lease.CourseCode, code, StringComparison.OrdinalIgnoreCase)
                && lease.SectionNumber == section),
            StopPreviewInAppAsync = () => StopPreviewForAsync(folder, code, section),
            SectionIsBeingDeployed = () => CourseActivity.IsPublishingSection(folder, code, section),
            CourseIsKeptForReference = () => Plantoir.Core.Models.Workspace.DiscoverCourses(folder)
                .Any(c => c.Code.Equals(code, StringComparison.OrdinalIgnoreCase) && ReferenceCourse.IsKeptForReference(c)),
            CourseIsBeingCopied = () => WorkLease.IsHeld(folder, code, WorkLease.Copying) || SidebarPane.IsZipping(folder, code),
        };

    /// <summary>
    /// The hide the question about classes dated after the next class makes at
    /// Deploy (#475): Hide Pages…'s OWN call, through this window's runner —
    /// a copy of the course first, Section ▸ Undo Last Change takes it back,
    /// and pages only those classes link to are hidden with them — with no
    /// preview stopped or started either side, since the deploy builds the
    /// site straight after. Null when the window has no folder.
    /// </summary>
    internal async Task<AssistToolAnswer?> HideClassesForTheDeploy(string code, int section, IReadOnlyList<string> places)
    {
        if (Verbs() is not { } verbs) return null;
        var answer = await verbs.Perform(SectionVerbs.HidePages(code, section, places, plan: false),
                                         "Deploy", code, section, previewFollows: false, noteOnTheTrail: false);
        ApplyMenuEnablement();
        return answer;
    }

    /// <summary>Whether Undo Last Change applies to this section here (<c>lastChangeIsHere</c>).</summary>
    private bool LastMenuChangeIsIn(string code, int section) => _verbs?.LastChangeIsIn(code, section) == true;

    /// <summary>
    /// Whether one of the functions, or the assistant's window, is changing
    /// this section right now (<c>verbIsRunning</c>): this window's runner, a
    /// change from ANY window's menu (the in-process claim), or the assistant
    /// working on it — so two undo lists never interleave on one section.
    /// </summary>
    private bool AVerbIsRunningOn(string folder, string code, int section) =>
        _verbs?.IsRunning == true
        || SectionMenuActivity.IsChanging(folder, code, section)
        || AssistActivity.IsWorking(folder, code, section);

    /// <summary>
    /// The section row's context menu asked for a function (its row is
    /// selected already): the same check at the click as the menu bar's, since
    /// a context menu does not consult the rule when it is drawn.
    /// </summary>
    internal void RunSectionVerbFromARow(Item item)
    {
        if (IsClosed || DialogGate.IsOpen(Content?.XamlRoot)) return;
        if (!SubjectMenuRules.Enabled(CurrentSituation()).Contains(item))
        {
            ApplyMenuEnablement();
            return;
        }
        _ = RunSectionVerb(item);
    }

    /// <summary>One of the nine, for the selected section. The rule has been asked already.</summary>
    private async Task RunSectionVerb(Item item)
    {
        if (Workspace.Selection is not SidebarSelection.SectionItem(_, var number)
            || Workspace.SelectedCourse is not { } course
            || Workspace.WorkspacePath is not { } folder
            || Content?.XamlRoot is not { } root
            || Verbs() is not { } verbs) return;
        string code = course.Code;
        bool meeting = course.Configuration.ClassNoun == ClassNoun.Meeting;
        try
        {
            switch (item)
            {
                case Item.PublishPages:
                    await SectionVerbDialog.ChoosePages(root, verbs, course, number, publishing: true);
                    break;
                case Item.HidePages:
                    await SectionVerbDialog.ChoosePages(root, verbs, course, number, publishing: false);
                    break;
                case Item.PublishClassForADate:
                    await SectionVerbDialog.ChooseADay(root, verbs, course, number);
                    break;
                case Item.RebuildPreview:
                    var rebuilt = await verbs.Perform(SectionVerbs.RebuildPreview(code, number),
                                                      SectionVerbDialog.MenuPath(item), code, number);
                    // Rebuilding is watched happening; only a refusal is said.
                    if (rebuilt.Summary != AssistWording.PreviewIsRebuilding(code, number.ToString()))
                        await SectionVerbDialog.ShowAnswer(root, verbs, course, number, item,
                                                           AssistWording.MenuRebuildPreviewTitle, rebuilt.Summary);
                    break;
                case Item.UndoLastChange:
                    await SectionVerbDialog.RunAtOnce(root, verbs, course, number, item, SectionVerbs.UndoLastChange(),
                                                      AssistWording.MenuUndoLastChangeTitle);
                    break;
                case Item.AddNextClass:
                    if (!await ClassDatesFirst(folder, course, number, item, root)) return;
                    await SectionVerbDialog.RunAtOnce(root, verbs, course, number, item, SectionVerbs.AddNextClass(code, number),
                        meeting ? AssistWording.MenuAddNextClassTitleForAMeeting : AssistWording.MenuAddNextClassTitle);
                    break;
                case Item.ReDateClasses:
                    if (!await ClassDatesFirst(folder, course, number, item, root)) return;
                    await SectionVerbDialog.PlanReDate(root, verbs, course, number);
                    break;
                case Item.MakeRoomForClasses:
                    if (!await ClassDatesFirst(folder, course, number, item, root)) return;
                    await SectionVerbDialog.ChooseWhereToMakeRoom(root, verbs, course, number);
                    break;
                case Item.ClassDates:
                    SectionVerbs.NoteOpened(SectionVerbDialog.MenuPath(item), code, number);
                    await ShowClassDates(folder, course, number, root, reason: "");
                    break;
            }
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"Section menu {item} failed: {ex}");
        }
        finally
        {
            ApplyMenuEnablement();
        }
    }

    /// <summary>
    /// True when the section has class dates on file, or the teacher has just
    /// written them in this window's own dialog, which says why it is asking.
    /// </summary>
    private async Task<bool> ClassDatesFirst(string folder, Course course, int section, Item item, XamlRoot root)
    {
        if (TimetableMemory.Read(folder, course.Code, section, recording: false) is not null) return true;
        bool meeting = course.Configuration.ClassNoun == ClassNoun.Meeting;
        string reason = item switch
        {
            Item.AddNextClass => meeting ? AssistWording.DatesForTheNextPageForAMeeting : AssistWording.DatesForTheNextPage,
            Item.ReDateClasses => meeting ? AssistWording.DatesToReDateForAMeeting : AssistWording.DatesToReDate,
            _ => meeting ? AssistWording.DatesToMakeRoomForAMeeting : AssistWording.DatesToMakeRoom,
        };
        return await ShowClassDates(folder, course, section, root, reason);
    }

    /// <summary>The section's class dates dialog, in this window. True when dates were written.</summary>
    private async Task<bool> ShowClassDates(string folder, Course course, int section, XamlRoot root, string reason)
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var dialog = new SectionScheduleDialog(folder, course, section, hwnd, reason) { XamlRoot = root };
        try
        {
            var result = await dialog.ShowAsync();
            return result == ContentDialogResult.Primary && dialog.SavedDates is { Count: > 0 };
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"Class dates could not be shown: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Really rebuild a section's preview (#489, Q1): stop the serving one and
    /// start it again, or start one. <see cref="ShowPreviewFor"/> does nothing
    /// while a preview serves, which is what the assistant's "rebuilding" used
    /// to promise and not do. Used by Rebuild Preview and by the in-app
    /// assistant's rebuild_preview alike.
    /// </summary>
    public void RebuildPreviewFor(string courseCode, int section)
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            try
            {
                if (await RefusedWhileTheFolderIsGettingReady(Workspace.WorkspacePath, "Cannot Preview Yet")) return;   // #473
                if (DetailHost.Content is not SectionDetailView existing ||
                    !string.Equals(existing.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase) ||
                    existing.SectionNumber != section)
                {
                    Workspace.Selection = new SidebarSelection.SectionItem(courseCode, section);
                }
                if (DetailHost.Content is SectionDetailView detail) await detail.RebuildPreviewAsync();
                ComeForwardIfHidden();
            }
            catch (Exception ex)
            {
                App.LogDiagnostic($"RebuildPreviewFor exception: {ex}");
            }
        });
    }
}
