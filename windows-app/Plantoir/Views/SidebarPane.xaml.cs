using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Services;
using Plantoir.ViewModels;

namespace Plantoir.Views;

/// <summary>One row of the sidebar tree: a course, a section, the Archived group, or an archive.</summary>
public sealed class SidebarRow
{
    public required string Title { get; init; }
    public required string Glyph { get; init; }
    public string? Tooltip { get; init; }
    public bool IsExpanded { get; set; }   // mutable: user toggles are recorded (row 99)
    public string AutomationId { get; init; } = "";
    public ObservableCollection<SidebarRow> Children { get; init; } = new();
    public MenuFlyout? Menu { get; set; }
    public SidebarSelection? Selection { get; init; }
    public ArchivedItem? Archived { get; init; }

    /// <summary>
    /// When a deploy is waiting to fire for this section, null otherwise.
    ///
    /// A scheduled deploy is the one thing Plantoir does while nobody is
    /// looking, and until now nothing said so — a teacher who set one on
    /// Friday had no way to be reminded on Monday except by remembering. The
    /// row it belongs to is the row that says it.
    /// </summary>
    public DateTime? ScheduledDeploy { get; set; }

    public string BadgeGlyph => Glyphs.Clock;
    public Visibility BadgeVisibility =>
        ScheduledDeploy is null ? Visibility.Collapsed : Visibility.Visible;
    public string BadgeTooltip => ScheduledDeploy is { } when
        ? $"Deploying automatically at {when:h:mm tt} on {when:dddd d MMMM}. " +
          "Right-click to cancel. This computer must be on and awake."
        : "";
}

public sealed partial class SidebarPane : UserControl
{
    // Segoe Fluent glyphs, mirroring the mac symbol choices.
    private const string LibraryGlyph = Glyphs.Library;
    private const string DocumentGlyph = Glyphs.Document;
    private const string ArchiveGlyph = Glyphs.Archive;
    private const string AddSectionGlyph = Glyphs.Add;
    private const string ObsidianGlyph = Glyphs.Edit;
    private const string ExplorerGlyph = Glyphs.Explorer;
    private const string TerminalGlyph = Glyphs.Terminal;
    private const string RestoreGlyph = Glyphs.Restore;

    private MainWindow _window = null!;
    private WorkspaceViewModel Workspace => _window.Workspace;
    private DateTime _lastTreeInteraction = DateTime.MinValue;

    public SidebarPane()
    {
        InitializeComponent();
        // Note the moments the teacher actually touches the tree (chevron
        // clicks arrive with the event already handled, so listen to handled
        // events too). Collapsed uses this to tell a real fold from a glitch.
        Tree.AddHandler(PointerPressedEvent,
            new Microsoft.UI.Xaml.Input.PointerEventHandler((_, _) => _lastTreeInteraction = DateTime.UtcNow), true);
        Tree.AddHandler(KeyDownEvent,
            new Microsoft.UI.Xaml.Input.KeyEventHandler((_, _) => _lastTreeInteraction = DateTime.UtcNow), true);
        Tree.Collapsed += Tree_Collapsed;
        Tree.Expanding += Tree_Expanding;
    }

    /// <summary>
    /// An expand is always worth recording — a deliberate one changes the
    /// per-window memory (row 99), and a programmatic re-assert writes back
    /// the value the model already holds.
    /// </summary>
    private void Tree_Expanding(TreeView sender, TreeViewExpandingEventArgs args)
    {
        if (args.Item is not SidebarRow row) return;
        row.IsExpanded = true;
        RecordExpansion(row, expanded: true);
    }

    /// <summary>Write a group/course toggle into the window's memory.</summary>
    private void RecordExpansion(SidebarRow row, bool expanded)
    {
        if (row.Selection is SidebarSelection.CourseItem(var code))
        {
            if (Workspace.IsCourseExpanded(code) == expanded) return;
            Workspace.SetCourseExpanded(code, expanded);
            App.RememberOpenWindows();
        }
        else if (ReferenceEquals(row, _archivedGroup))
        {
            if (Workspace.IsShowingArchived == expanded) return;
            Workspace.IsShowingArchived = expanded;
            App.RememberOpenWindows();
        }
        else if (ReferenceEquals(row, _backupsGroup))
        {
            if (Workspace.IsShowingBackups == expanded) return;
            Workspace.IsShowingBackups = expanded;
            App.RememberOpenWindows();
        }
    }

    /// <summary>
    /// Undo a collapse the teacher didn't ask for. WinUI's TreeView spuriously
    /// folds rows when the tree is rebuilt around a closing dialog — creating a
    /// course folded "Courses & Clubs" the moment the wizard closed, and the
    /// collapse can land many frames after the rebuild, so no fixed-length
    /// re-assert after Refresh is reliable. Catching the collapse itself is:
    /// if a row that asks to be open folds with no recent pointer or key input
    /// on the tree, it was the glitch — reopen it.
    /// </summary>
    private void Tree_Collapsed(TreeView sender, TreeViewCollapsedEventArgs args)
    {
        if (args.Item is not SidebarRow row) return;
        // The chevron raises Collapsed BEFORE its own pointer event bubbles
        // up to the tree (measured live: collapse, then the pointer 6 ms
        // later) — so deciding user-vs-glitch NOW would call every real
        // fold a glitch and reopen it. Defer one dispatcher pass; by then a
        // real click's pointer has been seen, while the rebuild glitch
        // (whose trigger is a dialog click that never routes through the
        // tree) still shows no input.
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            if ((DateTime.UtcNow - _lastTreeInteraction).TotalMilliseconds < 1000)
            {
                // The teacher folded this on purpose: remember it (row 99).
                row.IsExpanded = false;
                RecordExpansion(row, expanded: false);
                return;
            }
            if (!row.IsExpanded) return;
            if (Tree.ContainerFromItem(row) is TreeViewItem container && !container.IsExpanded)
                container.IsExpanded = true;
        });
    }

    public void Attach(MainWindow window)
    {
        _window = window;
        window.Workspace.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName is nameof(WorkspaceViewModel.Selection))
                RemoveButton.IsEnabled = Workspace.SelectedCourse is not null;
        };
    }

    // ---- Building the tree ----------------------------------------------

    // The tree is UPDATED IN PLACE, never rebuilt. Replacing ItemsSource
    // wholesale forces the TreeView to destroy and recreate every container,
    // and WinUI drops expansion state somewhere in that churn — "Courses &
    // Clubs" kept folding up after the create-course dialog closed, on no
    // schedule any timed re-assert could reliably beat. With persistent row
    // objects reconciled against the workspace, the group containers are
    // never re-created, so there is no state to lose.
    private readonly ObservableCollection<SidebarRow> _roots = new();
    private SidebarRow? _coursesGroup;
    private SidebarRow? _backupsGroup;
    private SidebarRow? _archivedGroup;

    public void Refresh()
    {
        if (_coursesGroup is null)
        {
            _coursesGroup = new SidebarRow { Title = "Courses & Clubs", Glyph = "", IsExpanded = true };
            _roots.Add(_coursesGroup);
            Tree.ItemsSource = _roots;
        }
        ReconcileCourses();
        ReconcileBackups();
        ReconcileArchived();

        // Root order: courses, then Backups, then Archived (row 106).
        var desiredRoots = new List<SidebarRow> { _coursesGroup };
        if (_backupsGroup is not null) desiredRoots.Add(_backupsGroup);
        if (_archivedGroup is not null) desiredRoots.Add(_archivedGroup);
        ApplyDesiredOrder(_roots, desiredRoots);

        RefreshNoMatches();
        ReassertExpansion();
    }

    /// <summary>
    /// The Backups group sits above Archived, hidden while there are no
    /// backups; rows are reused by zip path so their containers survive.
    /// </summary>
    private void ReconcileBackups()
    {
        if (Workspace.BackupItems.Count == 0)
        {
            if (_backupsGroup is not null) { _roots.Remove(_backupsGroup); _backupsGroup = null; }
            return;
        }
        _backupsGroup ??= new SidebarRow
        {
            Title = "Backups",
            Glyph = RestoreGlyph,
            IsExpanded = Workspace.IsShowingBackups,
            AutomationId = "backupsGroup",
        };
        if (!_roots.Contains(_backupsGroup)) _roots.Add(_backupsGroup);

        var byId = new Dictionary<string, SidebarRow>();
        foreach (var row in _backupsGroup.Children)
            if (row.Selection is SidebarSelection.BackupEntry(var id)) byId[id] = row;

        var desired = new List<SidebarRow>();
        foreach (var item in Workspace.BackupItems)
        {
            if (!byId.TryGetValue(item.Id, out var row))
                row = new SidebarRow
                {
                    Title = item.Title,
                    Glyph = RestoreGlyph,
                    Tooltip = item.Subtitle,
                    Selection = new SidebarSelection.BackupEntry(item.Id),
                    AutomationId = $"backup-{Path.GetFileName(item.FilePath)}",
                };
            row.Menu = BackupMenu(item);
            desired.Add(row);
        }
        ApplyDesiredOrder(_backupsGroup.Children, desired);
    }

    private void ReconcileCourses()
    {
        var byCode = new Dictionary<string, SidebarRow>();
        foreach (var row in _coursesGroup!.Children) byCode[row.Title] = row;

        var desired = new List<SidebarRow>();
        foreach (var course in Workspace.FilteredCourses)
        {
            if (!byCode.TryGetValue(course.Code, out var row))
                row = new SidebarRow
                {
                    Title = course.Code,
                    Glyph = LibraryGlyph,
                    // The window's own memory decides (row 99); a window
                    // without stored state opens everything.
                    IsExpanded = Workspace.IsCourseExpanded(course.Code),
                    Selection = new SidebarSelection.CourseItem(course.Code),
                    AutomationId = $"sidebar-{course.Code}",
                };
            // Menus are remade every pass so their closures always hold the
            // freshly loaded Course, never a stale pre-reload instance.
            row.Menu = CourseMenu(course);
            ReconcileSections(row, course);
            desired.Add(row);
        }
        ApplyDesiredOrder(_coursesGroup.Children, desired);
    }

    private void ReconcileSections(SidebarRow courseRow, Course course)
    {
        var byTitle = new Dictionary<string, SidebarRow>();
        foreach (var row in courseRow.Children) byTitle[row.Title] = row;

        var desired = new List<SidebarRow>();
        foreach (int number in course.SectionNumbers)
        {
            if (!byTitle.TryGetValue($"Section {number}", out var row))
                row = new SidebarRow
                {
                    Title = $"Section {number}",
                    Glyph = DocumentGlyph,
                    Selection = new SidebarSelection.SectionItem(course.Code, number),
                    AutomationId = $"sidebar-{course.Code}-section{number}",
                    // Windows is asked, not a note of our own: the teacher can
                    // delete the task themselves, and a badge promising a
                    // deploy that will not happen is worse than no badge.
                    ScheduledDeploy = TaskScheduling.NextRun(course.Code, number),
                };
            row.Menu = SectionMenu(course, number);
            desired.Add(row);
        }
        ApplyDesiredOrder(courseRow.Children, desired);
    }

    private void ReconcileArchived()
    {
        if (Workspace.ArchivedItems.Count == 0)
        {
            if (_archivedGroup is not null) { _roots.Remove(_archivedGroup); _archivedGroup = null; }
            return;
        }
        if (_archivedGroup is null)
        {
            // A place to go looking, not something to step over — closed by
            // default, but a window that had it open gets it back (row 99).
            _archivedGroup = new SidebarRow
            {
                Title = "Archived",
                Glyph = ArchiveGlyph,
                IsExpanded = Workspace.IsShowingArchived,
                AutomationId = "archivedGroup",
            };
            _roots.Add(_archivedGroup);
        }

        var byId = new Dictionary<string, SidebarRow>();
        foreach (var row in _archivedGroup.Children)
            if (row.Archived is { } archived) byId[archived.Id] = row;

        var desired = new List<SidebarRow>();
        foreach (var item in Workspace.ArchivedItems)
        {
            if (!byId.TryGetValue(item.Id, out var row) || row.Title != item.Title || row.Tooltip != item.Subtitle)
                row = new SidebarRow
                {
                    Title = item.Title,
                    Glyph = item.IsCourse ? LibraryGlyph : DocumentGlyph,   // same faces as live rows
                    Tooltip = item.Subtitle,
                    Selection = new SidebarSelection.ArchivedEntry(item.Id),
                    Archived = item,
                    AutomationId = $"archived-{item.Title}",
                };
            row.Menu = ArchivedMenu(item);
            desired.Add(row);
        }
        ApplyDesiredOrder(_archivedGroup.Children, desired);
    }

    /// <summary>
    /// Morph <paramref name="current"/> into <paramref name="desired"/> with
    /// the smallest moves — surviving rows are never removed and re-added, so
    /// their containers (and expansion state) ride through untouched.
    /// </summary>
    private static void ApplyDesiredOrder(ObservableCollection<SidebarRow> current, List<SidebarRow> desired)
    {
        for (int i = current.Count - 1; i >= 0; i--)
            if (!desired.Contains(current[i])) current.RemoveAt(i);
        for (int i = 0; i < desired.Count; i++)
        {
            int at = current.IndexOf(desired[i]);
            if (at == i) continue;
            // Remove+insert, not Move: the TreeView ignores Move on its root
            // collection (seen live: Backups stayed below Archived). The
            // re-created container reads its expansion from the row, which
            // the window's memory keeps truthful, so nothing is lost.
            if (at >= 0) current.RemoveAt(at);
            current.Insert(Math.Min(i, current.Count), desired[i]);
        }
    }

    /// <summary>
    /// Open any container that was REALIZED already folded — a brand-new row's
    /// container can surface collapsed without ever raising Collapsed, so the
    /// glitch guard above cannot see it. Retries briefly, stopping the moment
    /// every row that wants to be open has an open container. Section leaves
    /// and the Archived group ask to stay closed and are never touched.
    /// </summary>
    private void ReassertExpansion()
    {
        var wantOpen = new List<SidebarRow>();
        void Collect(IEnumerable<SidebarRow> rows)
        {
            foreach (var row in rows)
            {
                if (row.IsExpanded) wantOpen.Add(row);
                Collect(row.Children);
            }
        }
        Collect(_roots);

        var timer = DispatcherQueue.CreateTimer();
        int ticks = 0;
        timer.Interval = TimeSpan.FromMilliseconds(100);
        timer.Tick += (t, _) =>
        {
            bool allSettled = true;
            foreach (var row in wantOpen)
            {
                if (Tree.ContainerFromItem(row) is not TreeViewItem container) { allSettled = false; continue; }
                if (!container.IsExpanded) container.IsExpanded = true;
            }
            if (allSettled || ++ticks >= 20) t.Stop();   // settled, or ~2 s
        };
        timer.Start();
    }

    private void RefreshNoMatches()
    {
        bool show = Workspace.ShowsNoFilterMatches;
        NoMatches.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        Tree.Visibility = show ? Visibility.Collapsed : Visibility.Visible;
        if (show) NoMatchesDetail.Text = $"No course or club matches “{Workspace.FilterText.Trim()}”.";
    }

    private void Tree_ItemInvoked(TreeView sender, TreeViewItemInvokedEventArgs args)
    {
        if (args.InvokedItem is SidebarRow { Selection: { } selection })
            Workspace.Selection = selection;
    }

    // ---- Context menus ---------------------------------------------------

    private MenuFlyout CourseMenu(Course course)
    {
        // The mac's order: Obsidian, Add Section, Back Up Now, folder items.
        var menu = new MenuFlyout();
        menu.Items.Add(ObsidianItem(course.DirectoryPath, course.DirectoryPath));
        menu.Items.Add(new MenuFlyoutSeparator());
        var renameItem = MenuItem("Rename Course", Glyphs.Edit, () => _ = OpenRenameCourseDialog(course));
        menu.Items.Add(renameItem);
        menu.Items.Add(new MenuFlyoutSeparator());
        var addItem = MenuItem("Add Section…", AddSectionGlyph, () => _ = OpenAddSectionDialog(course));
        var busyNote = new MenuFlyoutItem { IsEnabled = false, Visibility = Visibility.Collapsed };
        menu.Items.Add(addItem);
        menu.Items.Add(busyNote);
        menu.Items.Add(new MenuFlyoutSeparator());
        // Backing up stays available mid-preview — it only reads (row 106).
        menu.Items.Add(MenuItem("Back Up Now", RestoreGlyph, () => _ = BackUpCourse(course)));

        var reviseItems = ReviseItems(course, section: null);
        if (reviseItems.Count > 0) menu.Items.Add(new MenuFlyoutSeparator());
        foreach (var item in reviseItems) menu.Items.Add(item);
        // The staleness lesson from the mac (row 104): menu content is built
        // when the ROW renders, not when the teacher opens it — so the busy
        // state is read the moment the menu opens, never captured earlier.
        menu.Opening += (_, _) =>
        {
            string? reason = Workspace.WorkspacePath is { } folder
                ? CourseActivity.BusyReason(folder, course.Code) : null;
            // Renaming and Add Section both require the course to be quiet.
            renameItem.IsEnabled = reason is null;
            addItem.IsEnabled = reason is null;
            busyNote.Text = reason ?? "";
            busyNote.Visibility = reason is null ? Visibility.Collapsed : Visibility.Visible;

            // Starting a conversation waits only for ANOTHER assistant. A
            // preview running is not in the way — it is the thing the teacher
            // is looking at while they decide what to ask for next, and gating
            // this on the same reason as Add Section stopped them from opening
            // a conversation about the preview in front of them.
            bool canRevise = CanReviseNow(course);
            foreach (var item in reviseItems) item.IsEnabled = canRevise;
        };
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem("Show in File Explorer", ExplorerGlyph, () => FolderActions.ShowInFileExplorer(course.DirectoryPath)));
        menu.Items.Add(MenuItem("Open in Terminal", TerminalGlyph, () => FolderActions.OpenTerminal(course.DirectoryPath)));
        return menu;
    }

    /// <summary>
    /// Open a Claude Code session already connected to this course's Plantoir
    /// tools. The teacher never sees a command line — everything the
    /// connection needs is written for them and thrown away with the session.
    /// </summary>
    private void ReviseWithClaude(Course course)
    {
        if (Workspace.WorkspacePath is not { } folder) return;
        if (ClaudeCodeLauncher.Open(folder, course.Code, course.Configuration.CourseName)) return;

        _ = ShowError("Claude didn’t open",
            $"Plantoir couldn’t start a Claude session for {course.Code}. " +
            "If Claude Code was updated or moved recently, restarting Plantoir may be enough.");
    }

    private MenuFlyout BackupMenu(BackupItem item)
    {
        var menu = new MenuFlyout();
        menu.Items.Add(MenuItem("Restore…", RestoreGlyph, () => ConfirmRestoreBackup(item)));
        menu.Items.Add(MenuItem("Show in File Explorer", ExplorerGlyph, () => FolderActions.ShowInFileExplorer(item.FilePath)));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem("Delete Backup…", Glyphs.Remove, () => ConfirmDeleteBackup(item)));
        return menu;
    }

    private MenuFlyout SectionMenu(Course course, int number)
    {
        string sectionDir = course.SectionDirectory(number);
        var menu = new MenuFlyout();

        // Revising from the SECTION is the common case: a class is published
        // for one section at a time, and "publish tomorrow's class" is always
        // a question about one. The window opens separately so the section's
        // preview can stay on screen beside the conversation changing it.
        var reviseItems = ReviseItems(course, number);
        foreach (var item in reviseItems) menu.Items.Add(item);
        // The revise group is its own idea; a divider keeps "talk to an
        // assistant" from reading as one list with the actions below it.
        if (reviseItems.Count > 0) menu.Items.Add(new MenuFlyoutSeparator());

        // Only shown when there is one to cancel. A permanently greyed-out
        // "Cancel Scheduled Deploy…" on every section would teach teachers to
        // ignore the line, which is the opposite of what it is for.
        // Scheduling without going through the assistant: the same act, and
        // most teachers setting a 6:30 deploy know exactly what they want and
        // should not have to describe it in a sentence first.
        var scheduled = TaskScheduling.NextRun(course.Code, number);
        menu.Items.Add(scheduled is { } when
            ? MenuItem($"Cancel Deploy at {when:h:mm tt}…", Glyphs.Clock,
                       () => ConfirmCancelScheduledDeploy(course, number, when))
            : MenuItem("Schedule Deploy…", Glyphs.Clock,
                       () => AskWhenToDeploy(course, number)));

        menu.Items.Add(new MenuFlyoutSeparator());

        // The vault is the COURSE folder even for a section — the section is
        // a subfolder within it, and Obsidian lands at its landing page.
        menu.Items.Add(ObsidianItem(sectionDir, course.DirectoryPath));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem("Show in File Explorer", ExplorerGlyph, () => FolderActions.ShowInFileExplorer(sectionDir)));
        menu.Items.Add(MenuItem("Open in Terminal", TerminalGlyph, () => FolderActions.OpenTerminal(sectionDir)));

        // Read when the menu OPENS, never captured at render — the staleness
        // lesson from row 104, which cost a live debugging session.
        menu.Opening += (_, _) =>
        {
            bool canRevise = CanReviseNow(course);
            foreach (var item in reviseItems) item.IsEnabled = canRevise;
        };
        return menu;
    }

    /// <summary>
    /// Ask when to deploy, and set it.
    ///
    /// Defaults to half past six tomorrow morning, because that is the case
    /// this exists for — the site live before the students are, without the
    /// teacher being at their desk. Everything the computer must be doing at
    /// that moment is stated in the dialog rather than discovered at 6:31.
    /// </summary>
    private async void AskWhenToDeploy(Course course, int number)
    {
        var tomorrow = DateTime.Today.AddDays(1).AddHours(6).AddMinutes(30);

        var day = new CalendarDatePicker
        {
            Date = tomorrow,
            MinDate = DateTimeOffset.Now.Date,
            PlaceholderText = "Pick a day",
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        var time = new TimePicker
        {
            Time = tomorrow.TimeOfDay,
            ClockIdentifier = "12HourClock",
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        var warning = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
                "SystemFillColorCautionBrush"],
        };

        var body = new StackPanel { Spacing = 12 };
        body.Children.Add(new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Text = $"{course.Code} Section {number} will deploy on its own at the time you pick. " +
                   "This computer must be switched on and awake then — plugged in if it is a laptop, " +
                   "with the lid open. Plantoir does not wake it up.",
        });
        body.Children.Add(day);
        body.Children.Add(time);
        body.Children.Add(warning);

        var dialog = new ContentDialog
        {
            Title = "Schedule a deploy",
            Content = body,
            PrimaryButtonText = "Schedule",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot,
        };

        // Checked as they choose, not after they commit — and the SAME check
        // the assistant makes, so neither door is the lenient one.
        void Recheck()
        {
            var chosen = Chosen();
            string? problem = chosen is null
                ? "Pick a day."
                : ScheduledDeploy.Problem(course, number, chosen.Value, DateTime.Now);
            warning.Text = problem ?? "";
            warning.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
            dialog.IsPrimaryButtonEnabled = problem is null;
        }

        DateTime? Chosen() => day.Date is { } picked
            ? picked.Date.Add(time.Time)
            : null;

        day.DateChanged += (_, _) => Recheck();
        time.TimeChanged += (_, _) => Recheck();
        Recheck();

        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (Chosen() is not { } when) return;

        if (Workspace.WorkspacePath is not { } folder) return;
        if (TaskScheduling.Schedule(TaskScheduling.NameFor(course.Code, number),
                                    folder, course.Code, number, when) is { } failure)
        {
            await ShowError("That couldn't be scheduled", failure);
            return;
        }
        Refresh();   // the clock appears
    }

    /// <summary>
    /// Call off a scheduled deploy, after saying plainly what that means.
    ///
    /// Cancelling is safe and reversible — the teacher can schedule another —
    /// but it is still worth confirming, because the failure it prevents is
    /// silent: a teacher who cancels by accident finds out by walking into
    /// class to a site that never went up.
    /// </summary>
    private async void ConfirmCancelScheduledDeploy(Course course, int number, DateTime when)
    {
        var dialog = new ContentDialog
        {
            Title = "Cancel this scheduled deploy?",
            Content = $"{course.Code} Section {number} is set to deploy automatically at " +
                      $"{when:h:mm tt} on {when:dddd d MMMM}. Cancelling means it will not go out then, " +
                      "and the site stays as it is until you deploy it yourself.",
            PrimaryButtonText = "Cancel It",
            CloseButtonText = "Leave It Scheduled",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        if (TaskScheduling.Cancel(TaskScheduling.NameFor(course.Code, number)) is { } problem)
        {
            await ShowError("That couldn't be cancelled",
                $"Windows would not remove the scheduled task: {problem}");
            return;
        }
        // Redraw so the clock goes with it.
        Refresh();
    }

    /// <summary>
    /// Open the built-in assistant on one section, in its own window.
    ///
    /// Separate from <see cref="ReviseWithClaude"/>, which hands the same
    /// tools to Claude Code in a terminal. Both drive <c>plantoir-mcp</c>, so
    /// they behave alike; this one asks nothing of the teacher beyond
    /// Plantoir itself, and runs on their own computer.
    /// </summary>
    private void ReviseWithAi(Course course, int number)
    {
        if (Workspace.WorkspacePath is not { } folder) return;

        // A second session on the same course would have both of them writing
        // into one output folder. The menu says so too; this is the guarantee,
        // since a session can start between the menu opening and the click.
        // Deliberately NOT a check for previews or deploys — those can happily
        // run alongside a conversation, and only a build is exclusive.
        if (CourseActivity.IsAssisting(folder, course.Code))
        {
            _ = ShowError($"{course.Code} is already being revised",
                "There is an assistant working on this course already. Finish in that window, " +
                "close it, then start again here.");
            return;
        }

        new AssistWindow(folder, course, number, _window).Activate();
    }

    private MenuFlyout ArchivedMenu(ArchivedItem item)
    {
        var menu = new MenuFlyout();
        menu.Items.Add(MenuItem("Restore…", RestoreGlyph, () => ConfirmRestore(item)));
        menu.Items.Add(MenuItem("Show in File Explorer", ExplorerGlyph, () => FolderActions.ShowInFileExplorer(item.FilePath)));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem("Delete Archive…", Glyphs.Remove, () => ConfirmDeleteArchive(item)));
        return menu;
    }

    private MenuFlyoutItem ObsidianItem(string revealFolder, string vaultPath)
    {
        var item = MenuItem("Open in Obsidian", ObsidianGlyph,
            () => _ = FolderActions.OpenInObsidian(revealFolder, vaultPath,
                BundledToolchain.SupportPath("obsidian_defaults/.obsidian")));
        item.IsEnabled = FolderActions.ObsidianIsInstalled;
        return item;
    }

    private static MenuFlyoutItem MenuItem(string text, string glyph, Action action, string? fontFamily = null)
    {
        var item = new MenuFlyoutItem { Text = text };
        if (glyph.Length > 0)
        {
            var icon = new FontIcon { Glyph = glyph };
            // Only the sparkle needs this; everything else inherits the icon font.
            if (fontFamily is not null) icon.FontFamily = new FontFamily(fontFamily);
            item.Icon = icon;
        }
        item.Click += (_, _) => action();
        return item;
    }

    /// <summary>
    /// The two ways to revise, built once for both the course menu and every
    /// section menu.
    ///
    /// Built in one place because they were drifting apart the moment there
    /// were two of them: the course offered Claude and the section offered the
    /// built-in assistant, so which help a teacher could reach depended on
    /// which row they happened to right-click. Both belong in both.
    ///
    /// <paramref name="section"/> is null on a course menu. Claude Code is
    /// locked to the COURSE either way — its session covers every section —
    /// so the section only changes which one the built-in assistant opens on.
    /// </summary>
    private List<MenuFlyoutItem> ReviseItems(Course course, int? section)
    {
        var items = new List<MenuFlyoutItem>();

        // Offered only when Claude Code and the tools it drives are both
        // present. A teacher who has neither should not be shown a door that
        // opens onto an error about something they have never heard of.
        if (ClaudeCodeLauncher.IsAvailable)
            items.Add(MenuItem("Revise with Claude…", Glyphs.Star,
                () => ReviseWithClaude(course)));

        // "Local" is the word doing the work: it is what separates this from
        // the Claude item above, and it is the privacy promise in one word.
        items.Add(MenuItem("Revise with local AI assistant…", Glyphs.Star,
            () => ReviseWithAi(course, section ?? course.SectionNumbers.First())));

        return items;
    }

    /// <summary>
    /// Whether a revise item may be clicked: only another assistant on the
    /// same course stands in the way. A preview running is not a conflict —
    /// it is what the teacher is reading while they decide what to ask for.
    /// </summary>
    private bool CanReviseNow(Course course) =>
        Workspace.WorkspacePath is not { } folder || !CourseActivity.IsAssisting(folder, course.Code);

    // ---- Footer actions --------------------------------------------------

    private void Add_Click(object sender, RoutedEventArgs e) => _ = OpenNewCourseWizard();

    private async void Remove_Click(object sender, RoutedEventArgs e)
    {
        // An archived item is already put away — nothing for this button to do.
        var course = Workspace.SelectedCourse;
        if (course is null || Workspace.WorkspacePath is null) return;

        string title;
        string message;
        int? sectionNumber = (Workspace.Selection as SidebarSelection.SectionItem)?.Number;
        if (sectionNumber is int n && course.SectionNumbers.Count > 1)
        {
            title = $"Remove Section {n} of {course.Code}?";
            message = "Nothing is deleted. This section moves to Archived, at the bottom of the sidebar, where you can get it back.";
        }
        else if (sectionNumber is int only && course.SectionNumbers.Count == 1)
        {
            title = $"Remove {course.Code}?";
            message = $"Section {only} is the only section of {course.Code}, so the whole course moves to Archived. Nothing is deleted — you can get it back from the bottom of the sidebar.";
            sectionNumber = null;   // removing the only section removes the course
        }
        else
        {
            title = $"Remove {course.Code}?";
            message = $"Nothing is deleted. {course.Code} and all of its sections move to Archived, at the bottom of the sidebar, where you can get them back.";
        }

        var dialog = new ContentDialog
        {
            Title = title,
            Content = message,
            PrimaryButtonText = "Remove",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        try
        {
            string coursesDir = Workspace.CoursesDirectory();
            if (sectionNumber is int number) CourseArchiver.ArchiveAndRemoveSection(course, number, coursesDir);
            else CourseArchiver.ArchiveAndRemoveCourse(course, coursesDir);
            Workspace.Selection = null;
            Workspace.Reload();
            _window.ApplyState();
        }
        catch (Exception error)
        {
            await ShowError("Could not remove", error.Message);
        }
    }

    // ---- Backups (row 106) -------------------------------------------------

    /// <summary>Zip the whole course, leave it untouched, show it in Backups.</summary>
    private async Task BackUpCourse(Course course)
    {
        if (Workspace.WorkspacePath is null) return;
        string when;
        try
        {
            string zipPath = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory());
            when = BackupItem.From(zipPath, course.Code)?.WhenDescription ?? "just now";
        }
        catch (Exception error)
        {
            await ShowError("Could not back up", error.Message);
            return;
        }
        Workspace.IsShowingBackups = true;   // the new backup should be visible
        Workspace.Reload();
        _window.ApplyState();
        App.RememberOpenWindows();

        var dialog = new ContentDialog
        {
            Title = $"{course.Code} is backed up",
            Content = "The copy was saved to the Backups group at the bottom of the sidebar.\n\n" +
                      "Restoring it later brings the whole course back to exactly this moment. " +
                      "Anything you add from now on won't be in this backup.",
            CloseButtonText = "OK",
            XamlRoot = XamlRoot,
        };
        await dialog.ShowAsync();
        _ = when;
    }

    public async void ConfirmRestoreBackup(BackupItem item)
    {
        // Restoring rewrites the course's folders — never mid-copy (row 104's rule).
        if (Workspace.WorkspacePath is { } folder
            && CourseActivity.BusyReason(folder, item.CourseCode) is not null)
        {
            await ShowError($"{item.CourseCode} is busy right now",
                "Restoring replaces the course's folders and files, and a preview or deploy " +
                "of this course is still using them. Try again when it finishes.");
            return;
        }

        var dialog = new ContentDialog
        {
            Title = $"Restore {item.CourseCode}?",
            Content = $"{item.CourseCode} goes back to the way it was at this moment:\n\n" +
                      $"{item.WhenDescription}\n\n" +
                      "Anything added since then won't be in it — so the current version is " +
                      "archived first, without being removed. This backup is kept.",
            PrimaryButtonText = "Restore",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        try
        {
            // Even a restore has an undo: the current version is archived
            // (and stays in place) before the backup's contents move in.
            if (Workspace.Courses.FirstOrDefault(c => c.Code == item.CourseCode) is { } current)
                CourseArchiver.ArchiveCourseWithoutRemoving(current, Workspace.CoursesDirectory());
            CourseRestorer.RestoreBackup(item, Workspace.CoursesDirectory());
            Workspace.Reload();
            Workspace.Selection = new SidebarSelection.CourseItem(item.CourseCode);
            _window.ApplyState();
        }
        catch (Exception error)
        {
            await ShowError("Could not restore", error.Message);
        }
    }

    /// <summary>
    /// True when deleting this zip would erase the LAST copy of the course:
    /// it is gone from Courses & Clubs and no other archive or backup of it
    /// remains. The warning surveys the other copies before it speaks.
    /// </summary>
    private bool IsOnlyRemainingCopy(string courseCode, string zipPath) =>
        !Workspace.Courses.Any(c => c.Code == courseCode)
        && !Workspace.ArchivedItems.Any(a => a.CourseCode == courseCode && a.SectionNumber is null && a.FilePath != zipPath)
        && !Workspace.BackupItems.Any(b => b.CourseCode == courseCode && b.FilePath != zipPath);

    private async void ConfirmDeleteBackup(BackupItem item)
    {
        string consequence = IsOnlyRemainingCopy(item.CourseCode, item.FilePath)
            ? $"This backup is the only remaining copy of {item.CourseCode} — the course is no longer " +
              $"in Courses & Clubs. Deleting it removes {item.CourseCode} for good."
            : $"The backup made {item.WhenDescription} is deleted for good. " +
              $"{item.CourseCode} itself, and every other copy of it, stays put.";
        var dialog = new ContentDialog
        {
            Title = $"Delete this backup of {item.CourseCode}?",
            Content = consequence,
            PrimaryButtonText = "Delete",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            CourseRestorer.DeleteBackup(item);
            if (Workspace.Selection is SidebarSelection.BackupEntry(var id) && id == item.Id)
                Workspace.Selection = null;
            Workspace.Reload();
            _window.ApplyState();
        }
        catch (Exception error)
        {
            await ShowError("Could not delete", error.Message);
        }
    }

    public async void ConfirmDeleteArchive(ArchivedItem item)
    {
        // Sections inside a still-present course are never the only copy;
        // the survey matters for whole-course archives.
        bool onlyCopy = item.SectionNumber is null && IsOnlyRemainingCopy(item.CourseCode, item.FilePath);
        string consequence = onlyCopy
            ? $"This archive is the only remaining copy of {item.CourseCode} — the course is no longer " +
              $"in Courses & Clubs. Deleting it removes {item.CourseCode} for good."
            : $"The archive of {item.Title} is deleted for good. Everything else stays put.";
        var dialog = new ContentDialog
        {
            Title = $"Delete this archive of {item.Title}?",
            Content = consequence,
            PrimaryButtonText = "Delete",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            CourseRestorer.DeleteArchive(item);
            if (Workspace.Selection is SidebarSelection.ArchivedEntry(var id) && id == item.Id)
                Workspace.Selection = null;
            Workspace.Reload();
            _window.ApplyState();
        }
        catch (Exception error)
        {
            await ShowError("Could not delete", error.Message);
        }
    }

    public async void ConfirmRestore(ArchivedItem item)
    {
        string message = item.SectionNumber is int n
            ? $"Section {n} will be put back into {item.CourseCode}, and will no longer be listed as archived."
            : $"{item.CourseCode} will be put back into Courses & Clubs, and will no longer be listed as archived.";
        var dialog = new ContentDialog
        {
            Title = $"Restore {item.Title}?",
            Content = message,
            PrimaryButtonText = "Restore",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        try
        {
            CourseRestorer.Restore(item, Workspace.CoursesDirectory(), Workspace.Courses);
            Workspace.Selection = null;
            Workspace.Reload();
            Workspace.Selection = item.SectionNumber is int number
                ? new SidebarSelection.SectionItem(item.CourseCode, number)
                : new SidebarSelection.CourseItem(item.CourseCode);
            _window.ApplyState();
        }
        catch (Exception error)
        {
            await ShowError("Could not restore", error.Message);
        }
    }

    private async Task ShowError(string title, string message)
    {
        var dialog = new ContentDialog
        {
            Title = title,
            Content = message,
            CloseButtonText = "OK",
            XamlRoot = XamlRoot,
        };
        await dialog.ShowAsync();
    }

    private void Filter_TextChanged(object sender, TextChangedEventArgs e)
    {
        Workspace.FilterText = FilterBox.Text;
        Refresh();
    }

    // ---- Dialog launchers ------------------------------------------------

    public async Task OpenNewCourseWizard(string? autoCreateCode = null, string? autoSections = null)
    {
        var wizard = new NewCourseDialog(_window) { XamlRoot = XamlRoot };
        if (autoCreateCode is not null) wizard.AutoCreate(autoCreateCode, autoSections);
        await wizard.ShowAsync();
        Workspace.Reload();
        _window.ApplyState();
        if (wizard.CreatedCourseCode is { } code)
        {
            Workspace.Selection = wizard.CreatedIsExample
                ? new SidebarSelection.SectionItem(code, 1)
                : new SidebarSelection.CourseItem(code);
        }
    }

    public async Task OpenAddSectionDialog(Course course)
    {
        // Belt to the menu's braces: adding a section re-runs the course
        // setup, which rewrites folders a live preview or publish may be
        // mid-copy of. Decline while the course is busy anywhere.
        if (Workspace.WorkspacePath is { } folder
            && CourseActivity.BusyReason(folder, course.Code) is not null)
        {
            await ShowError($"{course.Code} is busy right now",
                "Adding a section rewrites the course's folders and files, and a " +
                "preview or deploy of this course is still using them. Try again when it finishes.");
            return;
        }
        var dialog = new AddSectionDialog(course) { XamlRoot = XamlRoot };
        await dialog.ShowAsync();
        if (dialog.AddedNumber is { } number)
        {
            Workspace.Reload();
            _window.ApplyState();
            Workspace.Selection = new SidebarSelection.SectionItem(course.Code, number);
        }
    }

    public async Task OpenRenameCourseDialog(Course course)
    {
        if (Workspace.WorkspacePath is not { } folder) return;

        string? busy = CourseActivity.BusyReason(folder, course.Code);
        if (busy is not null)
        {
            await ShowError("Course is busy", $"{course.Code} is previewing or deploying right now. Stop that first, then rename.");
            return;
        }

        var codeBox = new TextBox
        {
            Text = course.Code,
            PlaceholderText = "e.g. ICS3U",
            MaxWidth = 300,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        codeBox.SelectAll();

        var warning = new TextBlock
        {
            Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Visibility = Visibility.Collapsed,
        };

        var content = new StackPanel
        {
            Spacing = 8,
            Children =
            {
                new TextBlock
                {
                    Text = $"Choose a new course code for {course.Code}. Letters, numbers, and single spaces up to 12 characters are allowed.",
                    TextWrapping = TextWrapping.Wrap,
                },
                codeBox,
                warning,
            },
        };

        var dialog = new ContentDialog
        {
            Title = $"Rename {course.Code}",
            Content = content,
            PrimaryButtonText = "Rename",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot,
        };

        void Validate()
        {
            string typed = codeBox.Text;
            var (problem, _) = CourseCodeValidator.Validate(typed, Workspace.Courses.Select(c => c.Code), course.Code);
            warning.Text = problem ?? "";
            warning.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
            dialog.IsPrimaryButtonEnabled = problem is null && CourseCodeValidator.Normalize(typed).Length > 0;
        }

        codeBox.TextChanged += (_, _) => Validate();
        Validate();

        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        string requestedCode = codeBox.Text.Trim();
        string newNormalized = CourseCodeValidator.Normalize(requestedCode);
        if (string.IsNullOrEmpty(newNormalized) || newNormalized == course.Code) return;

        if (FolderActions.ObsidianIsRunning)
        {
            var obsidianDialog = new ContentDialog
            {
                Title = $"{course.Code} is open in Obsidian",
                Content = $"Renaming moves the course folder, so Obsidian needs to close and reopen with the new course code {newNormalized}.",
                PrimaryButtonText = "Close Obsidian and Rename",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                XamlRoot = XamlRoot,
            };
            if (await obsidianDialog.ShowAsync() != ContentDialogResult.Primary) return;

            await FolderActions.QuitObsidianAndWait();
        }

        try
        {
            string coursesDir = Path.Combine(folder, "courses");
            var outcome = CourseRenamer.Rename(course, requestedCode, coursesDir, Workspace.Courses.Select(c => c.Code));

            if (FolderActions.ObsidianIsInstalled)
            {
                string newVaultPath = Path.Combine(coursesDir, outcome.NewCode);
                FolderActions.RegisterVault(newVaultPath);
            }

            Workspace.Reload();
            _window.ApplyState();
            Workspace.Selection = new SidebarSelection.CourseItem(outcome.NewCode);
            Refresh();

            if (CourseRenamer.NoticeAfterRenaming(outcome) is { } notice)
            {
                var noticeDialog = new ContentDialog
                {
                    Title = notice.Title,
                    Content = notice.Message,
                    CloseButtonText = "OK",
                    XamlRoot = XamlRoot,
                };
                _ = noticeDialog.ShowAsync();
            }
        }
        catch (Exception ex)
        {
            await ShowError("Could not rename course", ex.Message);
        }
    }
}
