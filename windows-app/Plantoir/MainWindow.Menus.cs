using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Services;
using Plantoir.Views;
using Windows.System;
using Item = Plantoir.Core.Models.SubjectMenuRules.Item;
using Row = Plantoir.Core.Models.SubjectMenuRules.Row;

namespace Plantoir;

/// <summary>
/// The menu bar (#488, the mac's #457): File, Course, Section, View and Help,
/// every action a teacher can take on a course or a section, each calling the
/// SAME code as its context-menu and toolbar routes.
/// </summary>
/// <remarks>
/// <para><b>Greyed, never hidden.</b> Which items can be used is
/// <see cref="SubjectMenuRules.Enabled"/> — the contract's rule
/// (<c>shared-rules.json</c> → <c>subjectMenus</c>), fed by
/// <see cref="CurrentSituation"/>. The one exception is presence: the Revise
/// With items for Claude and Codex are LEFT OUT when they are not installed,
/// decided when the menu is built (<c>outsideAgents.*.hiddenWhenNotInstalled</c>).</para>
///
/// <para><b>WinUI's MenuBarItem has no Opening event</b>, so enablement is
/// applied ahead of time (<see cref="ApplyMenuEnablement"/>) on every change the
/// window can hear — the selection, the folder's state, the section window's
/// chrome, Course Settings' Save state, the tools getting ready, activation,
/// a backup zipping — AND when the pointer enters or presses a menu title,
/// which was measured to fire before the flyout draws (PointerEntered about
/// 500 ms before the press; the items' Loaded 3 ms after Tapped). Whatever the
/// menu showed, <see cref="Invoke"/> asks for a dialog and the rule again at
/// the click, which is the guard that counts.</para>
///
/// <para><b>Keys live on the items, and one key means one thing.</b> Measured
/// on this PC (Intel i5-8365U, Windows 11 Pro 26200): an item's key fires with
/// its menu closed and focus in a text box; a key on a DISABLED item does not
/// fire and does not swallow the key (an enabled item later in the bar with
/// the same key fires instead — the opposite of the mac, where the disabled
/// item ate it); with two enabled items the FIRST wins. With focus in the
/// preview's page no XAML key fires at all, and with a ContentDialog up none
/// did either. Ctrl+Shift+O still moves between Course's and Section's Open in
/// Obsidian rather than sitting on both, so the key is drawn once.</para>
/// </remarks>
public sealed partial class MainWindow
{
    /// <summary>Every item the contract rules, by its contract item.</summary>
    private readonly Dictionary<Item, MenuFlyoutItemBase> _ruled = new();

    private MenuFlyoutSubItem _openRecentMenu = null!;
    private MenuFlyoutItem _renameReason = null!;
    private MenuFlyoutItem _checkForUpdatesItem = null!;
    private KeyboardAccelerator _courseObsidianKey = null!;
    private KeyboardAccelerator _sectionObsidianKey = null!;

    // ---- Building -----------------------------------------------------------

    private void BuildMenuBar()
    {
        // ---- File
        var file = FileMenu.Items;
        Add(file, "Open Working Folder…", "fileOpenWorkingFolder", Item.OpenWorkingFolder, Key(VirtualKey.O, VirtualKeyModifiers.Control, "Ctrl+O"));
        _openRecentMenu = new MenuFlyoutSubItem { Text = "Open Recent" };
        AutomationProperties.SetAutomationId(_openRecentMenu, "fileOpenRecent");
        file.Add(_openRecentMenu);
        _ruled[Item.OpenRecent] = _openRecentMenu;
        Add(file, "New Window", "fileNewWindow", null, Key(VirtualKey.N, VirtualKeyModifiers.Control, "Ctrl+N"), () => App.OpenNewWindow());
        Add(file, "New Course…", "fileNewCourse", Item.NewCourse, Key(VirtualKey.N, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, "Ctrl+Shift+N"));
        file.Add(new MenuFlyoutSeparator());
        // #244: beside Open Working Folder's neighbours, as on the mac, because it begins by choosing a folder.
        Add(file, "Import Courses for Reference…", "fileImportForReference", Item.ImportCoursesForReference);
        Add(file, "Restore from Archive…", "fileRestoreFromArchive", Item.RestoreFromArchive);
        Add(file, "Reload Courses", "fileReloadCourses", Item.ReloadCourses, Key(VirtualKey.R, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, "Ctrl+Shift+R"));
        file.Add(new MenuFlyoutSeparator());
        // No Ctrl+, : it was LABELLED here with no key behind it, and measured,
        // a KeyboardAccelerator on the comma key (VK 188) does not fire at all.
        Add(file, "Settings…", "fileSettings", null, null, () => Settings_Click(this, new RoutedEventArgs()));
        _checkForUpdatesItem = Add(file, UpdateWording.MenuItem, "fileCheckForUpdates", null, null,
            () => { if (App.Updater is { } updater) _ = updater.CheckAsync(teacherAsked: true); });
        _checkForUpdatesItem.Visibility = App.Updater?.IsActive == true ? Visibility.Visible : Visibility.Collapsed;

        // ---- Course: with a section selected these act on its course.
        var course = CourseMenu.Items;
        Add(course, "Add Section…", "courseAddSection", Item.AddSection);
        Add(course, CopyPageWording.Templates["menuItem"], "courseCopyAPage", Item.CopyAPage);
        course.Add(new MenuFlyoutSeparator());
        Add(course, "Save Course Settings", "courseSaveSettings", Item.SaveCourseSettings, Key(VirtualKey.S, VirtualKeyModifiers.Control, "Ctrl+S"));
        Add(course, "Revert Course Settings", "courseRevertSettings", Item.RevertCourseSettings);
        course.Add(new MenuFlyoutSeparator());
        // "Rename": no "Course", no ellipsis (mac #491 item 8). It opens a
        // dialog here, but the name is the command's, and a second word for it
        // would be a second command to learn.
        Add(course, "Rename", "courseRename", Item.Rename, Key(VirtualKey.F2, VirtualKeyModifiers.None, "F2"));
        // Dimmed WITH its reason: what holds a rename back (#458/#468).
        _renameReason = new MenuFlyoutItem { IsEnabled = false, Visibility = Visibility.Collapsed };
        AutomationProperties.SetAutomationId(_renameReason, "courseRenameReason");
        course.Add(_renameReason);
        Add(course, ReferenceCourse.SetSchoolYearMenuItem, "courseSetSchoolYear", Item.SetSchoolYear);
        Add(course, ReferenceCourse.KeepACopyMenuItem, "courseKeepACopy", Item.KeepACopyForReference);
        course.Add(new MenuFlyoutSeparator());
        Add(course, "Back Up Now", "courseBackUpNow", Item.BackUpNow);
        Add(course, "Restore from Backup…", "courseRestoreFromBackup", Item.RestoreFromBackup);
        course.Add(new MenuFlyoutSeparator());
        AddReviseWith(course, "course", Item.CourseReviseWithClaude, Item.CourseReviseWithCodex, Item.CourseReviseWithLocalAssistant);
        var courseObsidian = Add(course, "Open in Obsidian", "courseOpenInObsidian", Item.CourseOpenInObsidian);
        _courseObsidianKey = Key(VirtualKey.O, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, "Ctrl+Shift+O")!.Value.Make(this, Item.CourseOpenInObsidian);
        courseObsidian.KeyboardAccelerators.Add(_courseObsidianKey);
        Add(course, "Show in File Explorer", "courseShowInFileExplorer", Item.CourseShowInFinder);
        Add(course, "Open in Terminal", "courseOpenInTerminal", Item.CourseNewTerminalAtFolder);
        course.Add(new MenuFlyoutSeparator());
        Add(course, "Delete Backup…", "courseDeleteBackup", Item.DeleteBackup);
        Add(course, "Delete Archive…", "courseDeleteArchive", Item.DeleteArchive);
        Add(course, "Remove Course…", "courseRemoveCourse", Item.RemoveCourse);

        // ---- Section
        var section = SectionMenu.Items;
        Add(section, "Preview", "sectionPreview", Item.Preview, Key(VirtualKey.P, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, "Ctrl+Shift+P"));
        // #514: the mac's Option alternate, as a second visible item (a WinUI
        // menu has no modifier alternates): always titled the opposite of the
        // first, absent while a preview runs, and the SAME item for the rule
        // (Item.Preview, re-checked by Invoke) without taking the first's
        // place in _ruled. No key: Ctrl+Alt+Shift+P is AltGr+Shift+P on many
        // keyboards, a character a teacher may be typing.
        _previewAlternate = Add(section, "Preview at Last Viewed", "sectionPreviewAlternate", Item.Preview,
                                run: PressThePreviewAlternate, rules: false);
        Add(section, "Deploy…", "sectionDeploy", Item.Deploy, Key(VirtualKey.D, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, "Ctrl+Shift+D"));
        Add(section, "Open in Browser", "sectionOpenInBrowser", Item.OpenInBrowser);
        section.Add(new MenuFlyoutSeparator());
        // The assistant's own functions (#489, the mac's #457 batch B), run
        // through the tools' own code — never a model, so a teacher who
        // declined the assistant has every one (MainWindow.Verbs.cs). The
        // ellipsis items show the plan before anything changes; Rebuild
        // Preview, Undo Last Change and Add Next Class act at once.
        Add(section, "Publish Pages…", "sectionPublishPages", Item.PublishPages);
        Add(section, "Hide Pages…", "sectionHidePages", Item.HidePages);
        Add(section, "Publish Class for a Date…", "sectionPublishClassForADate", Item.PublishClassForADate);
        // Ctrl+Shift+B, the mac's Shift+Cmd+B: kept free for it by #488's key census.
        Add(section, "Rebuild Preview", "sectionRebuildPreview", Item.RebuildPreview,
            Key(VirtualKey.B, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, "Ctrl+Shift+B"));
        // No key: Ctrl+Z belongs to text editing, and a key that took back a
        // page change from inside a text field would be a surprise nobody
        // could undo (the mac's reason for no Cmd+Z).
        Add(section, "Undo Last Change", "sectionUndoLastChange", Item.UndoLastChange);
        section.Add(new MenuFlyoutSeparator());
        Add(section, "Add Next Class", "sectionAddNextClass", Item.AddNextClass);
        Add(section, "Re-date Classes…", "sectionReDateClasses", Item.ReDateClasses);
        Add(section, "Make Room for Classes…", "sectionMakeRoomForClasses", Item.MakeRoomForClasses);
        Add(section, "Class Dates…", "sectionClassDates", Item.ClassDates);
        section.Add(new MenuFlyoutSeparator());
        Add(section, "Schedule Deploy…", "sectionScheduleDeploy", Item.ScheduleDeploy);
        Add(section, "Cancel Scheduled Deploy…", "sectionCancelScheduledDeploy", Item.CancelScheduledDeploy);
        section.Add(new MenuFlyoutSeparator());
        Add(section, StartOfYearWording.MenuItem, "sectionGetReady", Item.GetReadyForTheStartOfTheYear);
        Add(section, StartOfYearWording.UndoMenuItem, "sectionUndoGettingReady", Item.UndoGettingReady);
        Add(section, LinksChecklistWording.MenuItem, "sectionPublishPagesLinksLeadTo", Item.PublishPagesLinksLeadTo);
        section.Add(new MenuFlyoutSeparator());
        AddReviseWith(section, "section", Item.SectionReviseWithClaude, Item.SectionReviseWithCodex, Item.SectionReviseWithLocalAssistant);
        var sectionObsidian = Add(section, "Open in Obsidian", "sectionOpenInObsidian", Item.SectionOpenInObsidian);
        _sectionObsidianKey = Key(VirtualKey.O, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, "Ctrl+Shift+O")!.Value.Make(this, Item.SectionOpenInObsidian);
        _ = sectionObsidian;   // its key is moved onto it by ApplyMenuEnablement while a section is selected
        Add(section, "Show in File Explorer", "sectionShowInFileExplorer", Item.SectionShowInFinder);
        Add(section, "Open in Terminal", "sectionOpenInTerminal", Item.SectionNewTerminalAtFolder);
        section.Add(new MenuFlyoutSeparator());
        Add(section, "Remove Section…", "sectionRemoveSection", Item.RemoveSection);

        // ---- View: the preview's own navigation.
        var view = ViewMenu.Items;
        Add(view, "Back", "viewBack", Item.Back, Key(VirtualKey.Left, VirtualKeyModifiers.Menu, "Alt+Left"));
        Add(view, "Forward", "viewForward", Item.Forward, Key(VirtualKey.Right, VirtualKeyModifiers.Menu, "Alt+Right"));
        view.Add(new MenuFlyoutSeparator());
        Add(view, "Reload Page", "viewReloadPage", Item.ReloadPage, Key(VirtualKey.R, VirtualKeyModifiers.Control, "Ctrl+R"));

        // ---- Help
        var help = HelpMenu.Items;
        // F1 is Windows' Help key, so it is Plantoir Help's (#491). It goes
        // through Invoke like every other key, so it does nothing under a dialog.
        Add(help, "Plantoir Help", "helpPlantoirHelp", null, Key(VirtualKey.F1, VirtualKeyModifiers.None, "F1"), OpenPlantoirHelp);
        Add(help, AssistWording.PublishingAndDeployingTitle + "…", "helpPublishingAndDeploying", null, null,
            () => _ = ExplainPublishingAndDeploying());
        help.Add(new MenuFlyoutSeparator());
        Add(help, "Report a Problem…", "helpReportAProblem", null, null, () => ReportProblem_Click(this, new RoutedEventArgs()));
        help.Add(new MenuFlyoutSeparator());
        Add(help, "About Plantoir", "helpAbout", null, null, () => About_Click(this, new RoutedEventArgs()));

        // Enablement ahead of the flyout: measured to fire before it draws.
        foreach (var title in new[] { FileMenu, CourseMenu, SectionMenu, ViewMenu, HelpMenu })
        {
            title.PointerEntered += (_, _) => ApplyMenuEnablement();
            title.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler((_, _) => ApplyMenuEnablement()), true);
        }
        AppMenuBar.GotFocus += (_, _) => ApplyMenuEnablement();   // opened from the keyboard
        // And when a flyout DRAWS, whatever opened it (the keyboard, UI
        // Automation): its items are Loaded as it opens — measured 3 ms after
        // Tapped — which is still before anything in it can be pressed. The
        // first item of each menu stands for all of them, so a menu opening
        // re-reads the situation once, not once per item.
        foreach (var title in new[] { FileMenu, CourseMenu, SectionMenu, ViewMenu })
            if (title.Items.FirstOrDefault() is FrameworkElement first)
            {
                first.Loaded += (_, _) => ApplyMenuEnablement();
                // #514: a menu closing, however (Escape, a click outside, an
                // item chosen) — measured, the first item's Unloaded fires on
                // every close: Alt released inside it was never seen, so the
                // button's title reads the keyboard again.
                first.Unloaded += (_, _) => ReadTheModifierAgain();
            }

        RebuildOpenRecent();
        OpenRecentList.Changed += OpenRecentChanged;
    }

    /// <summary>A key for an item: its key, modifiers and the name the #191 record writes.</summary>
    private readonly record struct MenuKey(VirtualKey Key, VirtualKeyModifiers Modifiers, string Name)
    {
        public KeyboardAccelerator Make(MainWindow window, Item? item, Action? run = null)
        {
            var accelerator = new KeyboardAccelerator { Key = Key, Modifiers = Modifiers };
            string name = Name;
            accelerator.Invoked += (_, args) =>
            {
                // Handled, always: an accelerator left unhandled goes on to
                // raise the item's Click (measured), which would run it twice.
                args.Handled = true;
                window.Invoke(item, run, name);
            };
            return accelerator;
        }
    }

    private static MenuKey? Key(VirtualKey key, VirtualKeyModifiers modifiers, string name) => new MenuKey(key, modifiers, name);

    /// <param name="rules">False for a second item on an item already ruled
    /// (Section's Preview alternate, #514): it is asked of the rule when it
    /// runs, but greyed by hand, so the first keeps its place in <c>_ruled</c>.</param>
    private MenuFlyoutItem Add(IList<MenuFlyoutItemBase> into, string text, string automationId, Item? item,
                               MenuKey? key = null, Action? run = null, bool rules = true)
    {
        var view = new MenuFlyoutItem { Text = text };
        AutomationProperties.SetAutomationId(view, automationId);
        view.Click += (_, _) => Invoke(item, run, null);
        if (key is { } k) view.KeyboardAccelerators.Add(k.Make(this, item, run));
        into.Add(view);
        if (rules && item is { } ruled) _ruled[ruled] = view;
        return view;
    }

    /// <summary>Section ▸'s second Preview item (#514).</summary>
    private MenuFlyoutItem? _previewAlternate;

    /// <summary>
    /// The alternate, pressed: the other start page — and never a stop. A
    /// menu drawn before a preview started elsewhere still shows it; the
    /// press is refused and the menu redrawn (the plan review's M2).
    /// </summary>
    private void PressThePreviewAlternate()
    {
        if (SelectedSectionDetail() is { } detail && !detail.PressPreview(opposite: true)) ApplyMenuEnablement();
    }

    /// <summary>
    /// Revise With ▸ Claude… / Codex… / Local AI Assistant… (mac #491 item 8's
    /// titles). Claude and Codex are LEFT OUT when not installed — a fact about
    /// this computer, decided now, never greyed (subjectMenus.rule); the local
    /// assistant is always drawn and greyed where it does not apply.
    /// </summary>
    /// <summary>The local assistant's title inside Revise With ▸ — the menu bar's and every row's.</summary>
    internal const string LocalAssistantMenuItemTitle = "Local AI Assistant…";

    private void AddReviseWith(IList<MenuFlyoutItemBase> into, string prefix, Item claude, Item codex, Item local)
    {
        var sub = new MenuFlyoutSubItem { Text = "Revise With" };
        AutomationProperties.SetAutomationId(sub, prefix + "ReviseWith");
        if (ClaudeCodeLauncher.IsAvailable) Add(sub.Items, ClaudeCodeLauncher.MenuItemTitle, prefix + "ReviseWithClaude", claude);
        if (CodexLauncher.IsAvailable) Add(sub.Items, CodexLauncher.MenuItemTitle, prefix + "ReviseWithCodex", codex);
        Add(sub.Items, LocalAssistantMenuItemTitle, prefix + "ReviseWithLocalAssistant", local);
        into.Add(sub);
    }

    // ---- Running ------------------------------------------------------------

    /// <summary>
    /// Every item's click and key come here. A dialog up stops everything (the
    /// #191 record notes a key that arrived under one), and a ruled item is
    /// asked of the rule AGAIN — the menu may have been drawn before a preview
    /// started in another window, and what it showed is not what it may do.
    /// </summary>
    private void Invoke(Item? item, Action? run, string? keyName)
    {
        if (IsClosed) return;
        var root = Content?.XamlRoot;
        bool held = keyName is not null ? DialogGate.Holds(root, keyName) : DialogGate.IsOpen(root);
        if (held) return;
        // F2 renames — unless the teacher is typing, when it does NOTHING. The
        // key is spent either way (MenuKey.Make marks it handled before it gets
        // here, so an unhandled key cannot go on to raise the item's Click and
        // rename anyway); a WinUI text field gives F2 no meaning of its own, so
        // nothing is taken from the teacher (2A's implementation review, L4).
        // A Rename held back by the rule's re-check below is silent too, as the
        // mac's key on a disabled item is — see 12-windows-app.md (L5).
        if (keyName == "F2" && root is not null &&
            FocusManager.GetFocusedElement(root) is TextBox or RichEditBox or PasswordBox or AutoSuggestBox or NumberBox) return;
        if (item is { } ruled && !SubjectMenuRules.Enabled(CurrentSituation()).Contains(ruled))
        {
            ApplyMenuEnablement();
            return;
        }
        try
        {
            if (run is not null) run();
            else if (item is { } toRun) Run(toRun);
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"menu item {item?.ToString() ?? keyName ?? "?"} failed: {ex}");
        }
    }

    /// <summary>
    /// A ruled item run from the sidebar — the − button, the Delete key, a
    /// row menu's Remove… (#491 items 5–6) — through the menu bar's own guard:
    /// a dialog up stops it (and, with <paramref name="keyName"/>, the #191
    /// record notes the key's arrival), and an item the rule greys does
    /// NOTHING, silently, as a greyed menu item's key does on the mac.
    /// </summary>
    internal void RunFromTheSidebar(Item item, string? keyName = null) => Invoke(item, null, keyName);

    /// <summary>The window's own items here; every one that acts on a row goes to the sidebar, which calls the context menus' own code.</summary>
    private void Run(Item item)
    {
        var detail = SelectedSectionDetail();
        switch (item)
        {
            case Item.OpenWorkingFolder: OpenWorkingFolder_Click(this, new RoutedEventArgs()); return;
            case Item.ReloadCourses: Workspace.ReloadTryingAgain(); ApplyState(); return;
            case Item.SaveCourseSettings: (DetailHost.Content as CourseSettingsView)?.SaveFromTheMenu(); return;
            case Item.RevertCourseSettings: (DetailHost.Content as CourseSettingsView)?.RevertFromTheMenu(); return;
            case Item.Preview: detail?.PressPreview(opposite: false); return;
            case Item.Deploy: detail?.PressDeploy(); return;
            case Item.OpenInBrowser: detail?.PressOpenInBrowser(); return;
            case Item.Back: detail?.PreviewGoBack(); return;
            case Item.Forward: detail?.PreviewGoForward(); return;
            case Item.ReloadPage: detail?.PreviewReload(); return;
            case Item.PublishPages or Item.HidePages or Item.PublishClassForADate or Item.RebuildPreview
                or Item.UndoLastChange or Item.AddNextClass or Item.ReDateClasses or Item.MakeRoomForClasses
                or Item.ClassDates:
                _ = RunSectionVerb(item);
                return;
        }
        if (!Sidebar.Perform(item)) App.LogDiagnostic($"menu item {item} has no route yet");
    }

    /// <summary>The section window on screen, only when it is the selected section's.</summary>
    private SectionDetailView? SelectedSectionDetail() =>
        Workspace.Selection is SidebarSelection.SectionItem(var code, var number)
        && DetailHost.Content is SectionDetailView detail
        && string.Equals(detail.CourseCode, code, StringComparison.OrdinalIgnoreCase) && detail.SectionNumber == number
            ? detail : null;

    // ---- What the rule is told ------------------------------------------------

    /// <summary>
    /// The situation as this window sees it NOW: every fact read from the
    /// owner that already decides it — the selection, the folder's readiness,
    /// the course's activity, the section window's own buttons and Course
    /// Settings' own Save — so the menu and the button cannot disagree.
    /// </summary>
    internal SubjectMenuRules.Situation CurrentSituation() => SituationFor(Workspace.Selection);

    /// <summary>
    /// The situation for <paramref name="selection"/> — the selected row, or a
    /// row whose context menu is opening (#491: its Remove… item is greyed by
    /// the same rule). The section window's and Course Settings' own buttons
    /// are read only for the row they belong to, the selected one; for any
    /// other row they read as not offered, which no removal depends on.
    /// </summary>
    internal SubjectMenuRules.Situation SituationFor(SidebarSelection? selection)
    {
        string? folder = Workspace.WorkspacePath;
        bool hasFolder = folder is not null && Workspace.State == WorkspaceState.Ready && Workspace.WorkspaceProblem is null;
        var row = !hasFolder ? Row.None : SidebarDeleteKey.RowOf(selection, isTheBackupsGroup: false);
        string? selectedCode = selection switch
        {
            SidebarSelection.CourseItem(var c) => c,
            SidebarSelection.SectionItem(var c, _) => c,
            _ => null,
        };
        var course = hasFolder && selectedCode is not null ? Workspace.Courses.FirstOrDefault(c => c.Code == selectedCode) : null;
        if (row is Row.Course or Row.Section && course is null) row = Row.None;   // a selection that names nothing here
        var backup = row == Row.Backup && selection is SidebarSelection.BackupEntry(var backupId)
            ? Workspace.BackupItems.FirstOrDefault(b => b.Id == backupId) : null;
        string? code = course?.Code ?? backup?.CourseCode;
        int? sectionNumber = (selection as SidebarSelection.SectionItem)?.Number;
        bool isTheSelection = Equals(selection, Workspace.Selection);

        bool copying = folder is not null && code is not null &&
                       (WorkLease.IsHeld(folder, code, WorkLease.Copying) || SidebarPane.IsZipping(folder, code));
        var detail = row == Row.Section && isTheSelection ? SelectedSectionDetail() : null;
        var settings = row == Row.Course && isTheSelection ? DetailHost.Content as CourseSettingsView : null;
        bool assisting = folder is not null && course is not null && CourseActivity.IsAssisting(folder, course.Code);

        return new SubjectMenuRules.Situation
        {
            HasFolder = hasFolder,
            FolderGettingReady = hasFolder && ToolchainReadiness.Refusal(folder) is not null,
            SheetIsUp = DialogGate.IsOpen(Content?.XamlRoot),
            Row = row,
            KeptForReference = course is not null && ReferenceCourse.IsKeptForReference(course),
            StructuralHold = folder is not null && course is not null && CourseActivity.BusyReason(folder, course.Code) is not null,
            Busy = folder is not null && course is not null && CourseActivity.IsPreviewingOrPublishing(folder, course.Code),
            Copying = copying,
            Deploying = folder is not null && course is not null && CourseActivity.IsPublishing(folder, course.Code),
            HasSchedule = course is not null && sectionNumber is int scheduled && Sidebar.ScheduledDeployShownFor(course.Code, scheduled) is not null,
            HasStartOfYearUndo = folder is not null && course is not null && sectionNumber is int undoIn
                                 && StartOfYearSessionUndo.For(folder, course.Code, undoIn) is not null,
            HasLinksOffer = course is not null && sectionNumber is int linksIn && LinksChecklistShowing.Offer(course, linksIn) is not null,
            // Windows' hold (#468): ANY assistant on the course greys all
            // three — the context menus' rule, kept so the two cannot disagree.
            ReviseBlocked = assisting
                ? new HashSet<SubjectMenuRules.ReviseTarget> { SubjectMenuRules.ReviseTarget.Claude, SubjectMenuRules.ReviseTarget.Codex, SubjectMenuRules.ReviseTarget.LocalAssistant }
                : new HashSet<SubjectMenuRules.ReviseTarget>(),
            ObsidianInstalled = FolderActions.ObsidianIsInstalled,
            SettingsMaySave = settings?.SaveIsEnabled == true,
            SettingsMayRevert = settings?.RevertIsEnabled == true,
            PreviewButtonEnabled = detail?.PreviewButtonIsEnabled == true,
            DeployButtonEnabled = detail?.DeployButtonIsEnabled == true,
            PreviewIsShowing = detail?.HasPreview == true,
            PreviewIsRunning = detail?.PreviewIsRunning == true,
            // #489: where this window's last menu change was made, and whether
            // the menu (any window's) or the assistant is changing the section.
            LastChangeIsHere = course is not null && sectionNumber is int changedIn && LastMenuChangeIsIn(course.Code, changedIn),
            VerbIsRunning = folder is not null && course is not null && sectionNumber is int runningIn
                            && AVerbIsRunningOn(folder, course.Code, runningIn),
            CanGoBack = detail?.CanGoBack == true,
            CanGoForward = detail?.CanGoForward == true,
        };
    }

    /// <summary>Grey or ungrey every ruled item, and move the keys and titles that follow the selection.</summary>
    internal void ApplyMenuEnablement()
    {
        if (IsClosed || _openRecentMenu is null) return;
        SubjectMenuRules.Situation situation;
        try { situation = CurrentSituation(); }
        catch (Exception ex)
        {
            App.LogDiagnostic($"ApplyMenuEnablement could not read the situation: {ex.Message}");
            return;
        }
        var enabled = SubjectMenuRules.Enabled(situation);
        foreach (var (item, view) in _ruled) view.IsEnabled = enabled.Contains(item);
        // The sidebar's − follows the same rule (#491 item 5).
        Sidebar.RefreshMinusButton(situation);

        // Section ▸ Preview says what the button says with no key held, and
        // its second item the other start page (#514, the contract's titles
        // function): the setting decides both even with no section selected,
        // when both are greyed. The second is absent while Stop Preview shows.
        var opensAt = PreviewStartPage.Read(App.Settings.PreviewOpensAt);
        bool stops = SelectedSectionDetail()?.PreviewButtonStops == true;
        if (_ruled.TryGetValue(Item.Preview, out var preview) && preview is MenuFlyoutItem previewItem)
            previewItem.Text = PreviewStartPage.Words(PreviewStartPage.TitleFor(opensAt, modifierHeld: false, stops));
        if (_previewAlternate is { } alternate)
        {
            alternate.Text = PreviewStartPage.Words(PreviewStartPage.TitleFor(opensAt, modifierHeld: true, previewIsRunning: false));
            alternate.IsEnabled = enabled.Contains(Item.Preview);
            alternate.Visibility = stops ? Visibility.Collapsed : Visibility.Visible;
        }

        // Ctrl+Shift+O sits on the ONE Open in Obsidian item that can be live.
        bool onSection = situation.Row == Row.Section;
        MoveKey(_courseObsidianKey, (MenuFlyoutItem)_ruled[Item.CourseOpenInObsidian], !onSection);
        MoveKey(_sectionObsidianKey, (MenuFlyoutItem)_ruled[Item.SectionOpenInObsidian], onSection);

        // What holds a rename back, said under it.
        string? reason = situation.Row is Row.Course or Row.Section && !situation.KeptForReference && situation.StructuralHold
                         && Workspace.WorkspacePath is { } folder && Workspace.SelectedCourse is { } course
            ? CourseActivity.BusyReason(folder, course.Code) : null;
        _renameReason.Text = reason ?? "";
        _renameReason.Visibility = reason is null ? Visibility.Collapsed : Visibility.Visible;

        _openRecentMenu.IsEnabled = enabled.Contains(Item.OpenRecent);
    }

    private static void MoveKey(KeyboardAccelerator key, MenuFlyoutItem item, bool belongsHere)
    {
        bool isHere = item.KeyboardAccelerators.Contains(key);
        if (belongsHere && !isHere) item.KeyboardAccelerators.Add(key);
        else if (!belongsHere && isHere) item.KeyboardAccelerators.Remove(key);
    }

    // ---- File ▸ Open Recent ---------------------------------------------------

    private void OpenRecentChanged()
    {
        if (IsClosed) return;
        DispatcherQueue.TryEnqueue(() => { if (!IsClosed) RebuildOpenRecent(); });
    }

    /// <summary>The submenu from the one list: the folders, newest first, then Clear Menu.</summary>
    private void RebuildOpenRecent()
    {
        _openRecentMenu.Items.Clear();
        var folders = OpenRecentList.Entries(App.Settings).ToList();
        var titles = RecentWorkingFolders.Titles(folders);
        for (int index = 0; index < folders.Count; index++)
        {
            string path = folders[index];
            var entry = new MenuFlyoutItem { Text = titles[index] };
            ToolTipService.SetToolTip(entry, path);
            AutomationProperties.SetAutomationId(entry, $"openRecentFolder{index}");
            entry.Click += (_, _) => _ = OpenRecentChosen(path);
            _openRecentMenu.Items.Add(entry);
        }
        if (folders.Count > 0) _openRecentMenu.Items.Add(new MenuFlyoutSeparator());
        var clear = new MenuFlyoutItem { Text = "Clear Menu", IsEnabled = folders.Count > 0 };
        AutomationProperties.SetAutomationId(clear, "openRecentClearMenu");
        clear.Click += (_, _) =>
        {
            if (DialogGate.IsOpen(Content?.XamlRoot)) return;
            OpenRecentList.Clear(App.Settings);
        };
        _openRecentMenu.Items.Add(clear);
    }

    /// <summary>
    /// A folder chosen from Open Recent switches THIS window, as Open Working
    /// Folder… does. One that cannot be opened says why in a dialog over a
    /// window that keeps its folder, and the trail says so with the occasion.
    /// </summary>
    private async Task OpenRecentChosen(string path)
    {
        if (IsClosed || DialogGate.IsOpen(Content?.XamlRoot)) return;
        if (!SubjectMenuRules.Enabled(CurrentSituation()).Contains(Item.OpenRecent)) return;
        if (LastWorkingFolder.WhyItCannotBeReopened(path) is { } reason)
        {
            ActivityTrail.Note(ActivityTrail.Event.WorkingFolderNotReopened,
                $"working folder not reopened ({reason}) — a folder chosen from Open Recent, {path}");
            var dialog = new ContentDialog
            {
                Title = OpenRecentWording.Title(path),
                Content = new TextBlock { Text = OpenRecentWording.Sentence(reason), TextWrapping = TextWrapping.Wrap },
                CloseButtonText = "OK",
                DefaultButton = ContentDialogButton.Close,
                XamlRoot = Content!.XamlRoot,
            };
            AutomationProperties.SetAutomationId(dialog, "openRecentCannotOpen");
            try { await dialog.ShowAsync(); }
            catch (Exception ex) { App.LogDiagnostic($"Open Recent's dialog could not be shown: {ex.Message}"); }
            return;
        }
        if (IsTheOpenFolder(path))
        {
            // A restore, not a change: nothing about the folder on screen moves.
            Workspace.ChooseWorkspace(path, fromOpenRecent: true);
            return;
        }
        switch (await SyncedFolderChoiceAsync(path))
        {
            case SyncedFolderChoice.GoAhead:
                Workspace.ChooseWorkspace(path, fromOpenRecent: true);
                ShowSyncNoticeIfNeeded();
                return;
            case SyncedFolderChoice.ChooseAnother:
                OpenWorkingFolder_Click(this, new RoutedEventArgs());
                return;
        }
    }

    // ---- Help ▸ Plantoir Help -------------------------------------------------

    /// <summary>The support page, in the browser (#491; the mac's item and address).</summary>
    private void OpenPlantoirHelp()
    {
        if (ExternalLinks.Open(new Uri(PlantoirHelp.SupportPage)))
            ActivityTrail.Note(ActivityTrail.Event.PlantoirHelpOpened, PlantoirHelp.TrailLine);
    }

    // ---- Help ▸ Publishing and Deploying… ---------------------------------

    /// <summary>What the two words mean, in a dialog of its own, with or without a course selected.</summary>
    private async Task ExplainPublishingAndDeploying()
    {
        if (Content?.XamlRoot is not { } root) return;
        var dialog = new ContentDialog
        {
            Title = AssistWording.PublishingAndDeployingTitle,
            Content = new TextBlock { Text = AssistWording.PublishingAndDeployingExplained, TextWrapping = TextWrapping.Wrap },
            CloseButtonText = "OK",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = root,
        };
        AutomationProperties.SetAutomationId(dialog, "publishingAndDeployingExplained");
        // "ran from a menu" (#489): the mac's line, word for word.
        ActivityTrail.Note(ActivityTrail.Event.RanFromAMenu, "Help ▸ Publishing and Deploying… — shown");
        try { await dialog.ShowAsync(); }
        catch (Exception ex) { App.LogDiagnostic($"Publishing and Deploying could not be shown: {ex.Message}"); }
    }
}
