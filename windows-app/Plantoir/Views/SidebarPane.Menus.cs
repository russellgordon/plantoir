using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;
using Plantoir.Services;
using Item = Plantoir.Core.Models.SubjectMenuRules.Item;

namespace Plantoir.Views;

/// <summary>
/// The sidebar's half of the menu bar's Course and Section menus (#488, the
/// mac's #457): every Course and Section item that acts on a ROW runs here,
/// through the SAME functions the row's context menu calls — never a copy.
/// What is selected is read when the item RUNS, not when the menu was drawn,
/// so an item can never act on a row the teacher has since left.
/// </summary>
public sealed partial class SidebarPane
{
    // ---- Selecting the row a context menu acts on (#488) -------------------

    /// <summary>
    /// A context-menu item's action, run after its row is SELECTED — so what is
    /// selected afterwards is what the item acted on, and the Course and Section
    /// menus name the same thing (mac #457 item 4). Rename too: on Windows it is
    /// a dialog, not a field edited in place, so the mac's reason to leave
    /// Rename unselected (its field lost focus to the selection change) does
    /// not arise here.
    /// </summary>
    private Action Selecting(SidebarSelection selection, Action action) => () =>
    {
        SelectRow(selection);
        action();
    };

    /// <summary>Select a row as a click on it would: the window's selection AND the tree's highlight.</summary>
    internal void SelectRow(SidebarSelection selection)
    {
        if (!Equals(Workspace.Selection, selection)) Workspace.Selection = selection;
        if (FindRow(_roots, selection) is { } row && !ReferenceEquals(Tree.SelectedItem, row))
        {
            try { Tree.SelectedItem = row; }
            catch (Exception ex) { App.LogDiagnostic($"SelectRow could not highlight the row: {ex.Message}"); }
        }
    }

    /// <summary>
    /// A row menu's removal (#491 item 6): LAST, behind a separator, as on the
    /// mac. Greyed by the menu bar's rule for THAT row, read when the menu
    /// opens (never when it was built — row 104's staleness lesson); run after
    /// selecting the row, through the menu bar's own guard, so it asks the
    /// same question as the menu bar, the − button and the Delete key.
    /// </summary>
    private void AddRemoval(MenuFlyout menu, SidebarSelection row, Item item, string text)
    {
        var removal = MenuItem(text, Glyphs.Remove, Selecting(row, () => _window.RunFromTheSidebar(item)));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(removal);
        menu.Opening += (_, _) =>
        {
            try { removal.IsEnabled = SubjectMenuRules.Enabled(_window.SituationFor(row)).Contains(item); }
            catch (Exception ex) { App.LogDiagnostic($"{text} could not read its rule: {ex.Message}"); }
        };
    }

    private static SidebarRow? FindRow(IEnumerable<SidebarRow> rows, SidebarSelection selection)
    {
        foreach (var row in rows)
        {
            if (Equals(row.Selection, selection)) return row;
            if (FindRow(row.Children, selection) is { } found) return found;
        }
        return null;
    }

    // ---- One Obsidian route (#488) -----------------------------------------

    /// <summary>
    /// Open in Obsidian, from EVERY route — the section window's toolbar,
    /// Course Settings' toolbar, both rows' menus and the menu bar's two items
    /// (mac #457: <c>WorkspaceModel.openInObsidian(course:sectionNumber:)</c>).
    /// A section reveals the SECTION's folder; the vault is always the course.
    /// A course kept for reference goes through its calm note first, the one
    /// the toolbar used to skip (the plan's finding 0.9). Every other course
    /// goes through <see cref="ObsidianOpenRoute"/> (#581): sequence steps 2–8
    /// of <c>obsidianAddOnsForFigures</c>.
    ///
    /// <para>A SECTION press (every caller that names a section: the section
    /// window's toolbar, Section &gt; Open in Obsidian, a section row's menu, and
    /// the assistant through <c>MainWindow.PressOpenInObsidianFor</c>) opens the
    /// file behind the page that section's preview shows (#681): the address is
    /// read ONCE, here, and resolved against the build's list; every fallback
    /// opens what the press opened before. A course press (section null) opens
    /// exactly what it opened before and writes no trail line.</para>
    ///
    /// <para>Returns what the press came to as soon as it is known - the
    /// assistant's reply is made from it (#690); every other caller drops it.</para>
    /// </summary>
    public Task<OpenInObsidianPress> OpenInObsidian(Course course, int? section)
    {
        string reveal = section is int number ? course.SectionDirectory(number) : course.DirectoryPath;
        PreviewedPageSource.Answer? answer = null;
        if (section is int pressed)
        {
            string? address = _window.PreviewedAddressFor(course.Code, pressed);
            var list = address is null || Workspace.WorkspacePath is not { } folder
                ? null
                : PreviewedPageSource.ReadList(PreviewedPageSource.ListPathFor(folder, course.Code, pressed));
            answer = PreviewedPageSource.Resolve(address, list, course.DirectoryPath);
        }
        if (ReferenceCourse.IsKeptForReference(course))
        {
            var reported = new TaskCompletionSource<OpenInObsidianPress>(TaskCreationOptions.RunContinuationsAsynchronously);
            _ = Finishing(OpenReferenceInObsidian(course, reveal, answer, section, reported), reported, answer);
            return reported.Task;
        }
        // Obsidian's add-ons for diagrams and graphs (#581): scanned, offered,
        // added or asked to reopen BEFORE Obsidian opens - all decided in
        // Plantoir.Core's route; this window only shows its two questions.
        var (report, finished) = new ObsidianOpenRoute(new ObsidianWorld(ShowDialogSafelyAsync)).Press(course, reveal, answer, section);
        _ = Finishing(finished, null, answer);
        return report;
    }

    /// <summary>Waits for a press's route so a fault is logged rather than lost, and makes sure its report completes.</summary>
    private static async Task Finishing(Task route, TaskCompletionSource<OpenInObsidianPress>? reported, PreviewedPageSource.Answer? answer)
    {
        try { await route; }
        catch (Exception ex) { App.LogDiagnostic($"Open in Obsidian failed: {ex.Message}"); }
        finally { reported?.TrySetResult(new OpenInObsidianPress.Opened(answer)); }
    }

    // ---- What the menu bar reads -------------------------------------------

    /// <summary>
    /// The scheduled deploy the sidebar is showing for a section (its clock
    /// badge), or null. Read from the row rather than from Task Scheduler: the
    /// menu bar is refreshed often, and the tree re-reads the scheduler on every
    /// Refresh — which each activation already does. A section with NO row (the
    /// filter hid it, or the tree has not caught up) asks Task Scheduler
    /// itself: "no row" is not "no schedule", and reading it as one would let
    /// Schedule Deploy… silently replace a deploy the teacher had set (2A's
    /// implementation review, L1).
    /// </summary>
    internal DateTime? ScheduledDeployShownFor(string courseCode, int section)
    {
        var row = FindRow(_roots, new SidebarSelection.SectionItem(courseCode, section));
        if (row is not null) return row.ScheduledDeploy;
        // The fallback runs `schtasks /Query` — another process — on the
        // interface thread, and waits for it. It is reached only for a section with no row, which is rare, and
        // TaskScheduling keeps the list it read for two seconds, so a menu
        // refreshed on every pointer movement asks the scheduler at most once
        // in that time (2B's implementation review, L6). Moving it off the
        // thread would make the menu bar's rule asynchronous, which the
        // click-time check depends on it not being.
        string? folder = Workspace.WorkspacePath;
        return folder is null ? null : Plantoir.Core.Assist.TaskScheduling.NextRun(folder, courseCode, section);
    }

    /// <summary>Courses this app is zipping right now from Back Up Now, by folder and code (#351's "copying").</summary>
    private static readonly HashSet<string> _zipping = new(StringComparer.OrdinalIgnoreCase);

    private static string ZipKey(string folder, string code) => WorkingFolder.Resolved(folder) + "|" + code;

    /// <summary>Whether this app is zipping a copy of the course — another program's copy is the work lease's to say.</summary>
    internal static bool IsZipping(string folder, string code)
    {
        lock (_zipping) return _zipping.Contains(ZipKey(folder, code));
    }

    // ---- Running a Course or Section item ----------------------------------

    /// <summary>
    /// Run a menu-bar item that acts on the selected row. The caller has asked
    /// the window for a dialog and the rule for the item at the click; this
    /// reads the selection NOW. Returns false for an item this pane does not own.
    /// </summary>
    internal bool Perform(Item item)
    {
        var course = Workspace.SelectedCourse;
        int? section = (Workspace.Selection as SidebarSelection.SectionItem)?.Number;
        string? folder = Workspace.WorkspacePath;
        switch (item)
        {
            case Item.NewCourse: _ = OpenNewCourseWizard(); return true;
            case Item.ImportCoursesForReference: _ = OpenImportForReference(); return true;
            case Item.RestoreFromArchive:
                if (Workspace.SelectedArchivedItem is { } archived) ConfirmRestore(archived);
                return true;
            case Item.RestoreFromBackup:
                if (Workspace.SelectedBackupItem is { } backup) ConfirmRestoreBackup(backup);
                return true;
            case Item.DeleteBackup:
                if (Workspace.SelectedBackupItem is { } toDelete) ConfirmDeleteBackup(toDelete);
                return true;
            case Item.DeleteArchive:
                if (Workspace.SelectedArchivedItem is { } archiveToDelete) ConfirmDeleteArchive(archiveToDelete);
                return true;
            case Item.CourseShowInFinder:
                if (Workspace.SelectedBackupItem is { } shownBackup) FolderActions.ShowInFileExplorer(shownBackup.FilePath);
                else if (Workspace.SelectedArchivedItem is { } shownArchive) FolderActions.ShowInFileExplorer(shownArchive.FilePath);
                else if (course is not null) FolderActions.ShowInFileExplorer(course.DirectoryPath);
                return true;
        }

        // Nothing selected that the item could act on: a stale click, and nothing to do.
        if (course is null) return true;
        switch (item)
        {
            case Item.AddSection: _ = OpenAddSectionDialog(course); return true;
            case Item.CopyAPage: _ = OpenCopyAPage(course); return true;
            case Item.Rename: _ = OpenRenameCourseDialog(course); return true;
            case Item.SetSchoolYear: _ = SetSchoolYear(course); return true;
            case Item.KeepACopyForReference: _ = KeepACopy(course); return true;
            case Item.BackUpNow: _ = BackUpCourse(course); return true;
            case Item.CourseReviseWithClaude:
            case Item.SectionReviseWithClaude: ReviseWithClaude(course); return true;
            case Item.CourseReviseWithCodex:
            case Item.SectionReviseWithCodex: ReviseWithCodex(course); return true;
            case Item.CourseReviseWithLocalAssistant:
                // Never enabled on a course row (it works per section); kept so
                // a stale enablement can never reach a dead end.
                ReviseWithAi(course, course.SectionNumbers.First());
                return true;
            case Item.SectionReviseWithLocalAssistant:
                if (section is int localIn) ReviseWithAi(course, localIn);
                return true;
            case Item.CourseOpenInObsidian: _ = OpenInObsidian(course, null); return true;
            case Item.SectionOpenInObsidian:
                if (section is int obsidianIn) _ = OpenInObsidian(course, obsidianIn);
                return true;
            case Item.CourseNewTerminalAtFolder: FolderActions.OpenTerminal(course.DirectoryPath); return true;
            case Item.SectionShowInFinder:
                if (section is int shownIn) FolderActions.ShowInFileExplorer(course.SectionDirectory(shownIn));
                return true;
            case Item.SectionNewTerminalAtFolder:
                if (section is int terminalIn) FolderActions.OpenTerminal(course.SectionDirectory(terminalIn));
                return true;
            case Item.RemoveCourse: _ = ConfirmRemoveCourse(course); return true;
            case Item.RemoveSection:
                if (section is int removing) _ = ConfirmRemoveSection(course, removing);
                return true;
            case Item.ScheduleDeploy:
                if (section is int scheduling) AskWhenToDeploy(course, scheduling, existing: null);
                return true;
            case Item.CancelScheduledDeploy:
                if (section is int cancelling && folder is not null
                    && Plantoir.Core.Assist.TaskScheduling.NextRun(folder, course.Code, cancelling) is { } when)
                    ConfirmCancelScheduledDeploy(course, cancelling, when);
                else Refresh();   // gone already: the clock goes, and the menu with it
                return true;
            case Item.GetReadyForTheStartOfTheYear:
                if (section is int readyIn) _ = OpenStartOfYear(course, readyIn);
                return true;
            case Item.UndoGettingReady:
                if (section is int undoIn) _ = UndoStartOfYear(course, undoIn);
                return true;
            case Item.PublishPagesLinksLeadTo:
                if (section is int linksIn) _ = OpenLinksChecklist(course, linksIn);
                return true;
        }
        return false;
    }
}
