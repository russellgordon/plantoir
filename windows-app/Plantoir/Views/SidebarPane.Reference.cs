using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// The sidebar's half of courses kept for reference (#241, #244;
/// <c>shared-rules.json → referenceCourses.interface</c>): the "Reference
/// Courses" group folded by school year, the menus that WITHHOLD every act
/// that would change such a course (hidden, never greyed), Keep a Copy for
/// Reference…, Set School Year…, the calm note before Obsidian opens, and
/// Import Courses for Reference….
/// </summary>
public sealed partial class SidebarPane
{
    private SidebarRow? _referenceGroup;

    /// <summary>Fold-memory keys for the group and each year: stored with the folder, as course folds are.</summary>
    private const string ReferenceGroupFoldKey = "|reference";
    private static string YearFoldKey(int? year) => "|reference|" + (year?.ToString() ?? "other");

    private static DateOnly Today => DateOnly.FromDateTime(DateTime.Now);

    /// <summary>
    /// The group: newest year first, Other last, and a year with nothing in it
    /// NOT DRAWN — an empty year is a row that teaches a teacher to stop
    /// reading the sidebar. The whole group goes when the shelf is empty.
    /// </summary>
    private void ReconcileReference()
    {
        var kept = Workspace.FilteredCourses.Where(ReferenceCourse.IsKeptForReference).ToList();
        if (kept.Count == 0)
        {
            if (_referenceGroup is not null) { _roots.Remove(_referenceGroup); _referenceGroup = null; }
            return;
        }
        _referenceGroup ??= new SidebarRow
        {
            Title = ReferenceCourse.GroupTitle,
            Glyph = LibraryGlyph,
            IsExpanded = Workspace.IsCourseExpanded(ReferenceGroupFoldKey),
            FoldKey = ReferenceGroupFoldKey,
            AutomationId = "referenceGroup",
        };
        if (!_roots.Contains(_referenceGroup)) _roots.Add(_referenceGroup);

        var byYear = kept.GroupBy(course => SchoolYear.Read(course.Configuration.StoredReferenceSchoolYear, Today))
            .OrderBy(group => group.Key is null ? 1 : 0).ThenByDescending(group => group.Key ?? 0).ToList();
        var existingYears = _referenceGroup.Children.ToDictionary(row => row.FoldKey ?? row.Title);
        var desiredYears = new List<SidebarRow>();
        foreach (var group in byYear)
        {
            string key = YearFoldKey(group.Key);
            if (!existingYears.TryGetValue(key, out var yearRow))
                yearRow = new SidebarRow
                {
                    Title = group.Key is int year ? SchoolYear.Label(year) : SchoolYear.OtherGroupName,
                    Glyph = "",
                    IsExpanded = Workspace.IsCourseExpanded(key),
                    FoldKey = key,
                    AutomationId = "referenceYear-" + (group.Key?.ToString() ?? "other"),
                };
            var existingCourses = yearRow.Children.ToDictionary(row => row.AutomationId);
            var desiredCourses = new List<SidebarRow>();
            foreach (var course in group.OrderBy(c => ReferenceCourse.ShownCode(c), StringComparer.Ordinal).ThenBy(c => c.Code, StringComparer.Ordinal))
            {
                string id = $"sidebar-{course.Code}";
                if (!existingCourses.TryGetValue(id, out var row))
                    row = new SidebarRow
                    {
                        // The code a teacher reads; the folder is in the tooltip,
                        // the one place it is the fact.
                        Title = ReferenceCourse.ShownCode(course),
                        Glyph = LibraryGlyph,
                        Tooltip = course.Code,
                        IsExpanded = Workspace.IsCourseExpanded(course.Code),
                        Selection = new SidebarSelection.CourseItem(course.Code),
                        AutomationId = id,
                    };
                row.Menu = ReferenceCourseMenu(course);
                ReconcileSections(row, course);
                desiredCourses.Add(row);
            }
            ApplyDesiredOrder(yearRow.Children, desiredCourses);
            desiredYears.Add(yearRow);
        }
        ApplyDesiredOrder(_referenceGroup.Children, desiredYears);
    }

    // ---- What a reference course's menus offer -----------------------------

    /// <summary>
    /// <c>interface.whatIsOffered</c> and nothing else: Obsidian (with the calm
    /// note first), Set School Year…, Back Up Now, the folder items. No Rename,
    /// Add Section, Keep a Copy or Revise — not greyed, not drawn. Remove stays,
    /// on the footer, and unlocks first.
    /// </summary>
    private MenuFlyout ReferenceCourseMenu(Course course)
    {
        var menu = new MenuFlyout();
        menu.Items.Add(ReferenceObsidianItem(course, course.DirectoryPath));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem(ReferenceCourse.SetSchoolYearMenuItem, Glyphs.Clock, () => _ = SetSchoolYear(course)));
        // Copy a Page only READS this course (#247): offered on every row.
        menu.Items.Add(MenuItem(CopyPageWording.Templates["menuItem"], Glyphs.Copy, () => _ = OpenCopyAPage(course)));
        menu.Items.Add(MenuItem("Back Up Now", RestoreGlyph, () => _ = BackUpCourse(course)));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem("Show in File Explorer", ExplorerGlyph, () => FolderActions.ShowInFileExplorer(course.DirectoryPath)));
        menu.Items.Add(MenuItem("Open in Terminal", TerminalGlyph, () => FolderActions.OpenTerminal(course.DirectoryPath)));
        return menu;
    }

    /// <summary>
    /// A reference course's SECTION: no assistant, no Schedule Deploy… —
    /// but Cancel Scheduled Deploy… whenever one exists, because the act that
    /// STOPS a deploy is never withheld (gate by direction).
    /// </summary>
    private MenuFlyout ReferenceSectionMenu(Course course, int number)
    {
        string sectionDir = course.SectionDirectory(number);
        var menu = new MenuFlyout();
        if (Workspace.WorkspacePath is { } scheduledIn
            && Plantoir.Core.Assist.TaskScheduling.NextRun(scheduledIn, course.Code, number) is { } when)
        {
            menu.Items.Add(MenuItem("Cancel Scheduled Deploy…", Glyphs.Remove,
                () => ConfirmCancelScheduledDeploy(course, number, when)));
            menu.Items.Add(new MenuFlyoutSeparator());
        }
        menu.Items.Add(ReferenceObsidianItem(course, sectionDir));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem("Show in File Explorer", ExplorerGlyph, () => FolderActions.ShowInFileExplorer(sectionDir)));
        menu.Items.Add(MenuItem("Open in Terminal", TerminalGlyph, () => FolderActions.OpenTerminal(sectionDir)));
        return menu;
    }

    private MenuFlyoutItem ReferenceObsidianItem(Course course, string revealFolder)
    {
        var item = MenuItem("Open in Obsidian", ObsidianGlyph, () => _ = OpenReferenceInObsidian(course, revealFolder));
        item.IsEnabled = FolderActions.ObsidianIsInstalled;
        return item;
    }

    // ---- The calm note, before Obsidian opens, once per course ----------------

    private static string NotesShownFile => AppDataRoot.Combine("reference-notes-shown.txt");

    private static bool NoteWasShown(Course course)
    {
        try { return File.Exists(NotesShownFile) && File.ReadAllLines(NotesShownFile).Contains(course.DirectoryPath, StringComparer.OrdinalIgnoreCase); }
        catch { return false; }
    }

    private static void RememberNoteShown(Course course)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(NotesShownFile)!);
            File.AppendAllLines(NotesShownFile, new[] { course.DirectoryPath });
        }
        catch { /* shown again next time: harmless */ }
    }

    /// <summary>
    /// In FRONT of the teacher, the first time only: what the pages are, said
    /// calmly. <c>obsidianOpensThemForReading</c> is NOT said on Windows yet:
    /// it is a measurement of Obsidian for Mac (<c>frozen.inObsidian</c>), and
    /// what Obsidian for Windows shows on a page it cannot save has not been
    /// measured here (bundle-6 plan §6.7; a question for Russell).
    /// </summary>
    private async Task OpenReferenceInObsidian(Course course, string revealFolder)
    {
        if (!NoteWasShown(course))
        {
            var note = new ContentDialog
            {
                Title = "About this course’s pages",
                Content = new TextBlock { Text = ReferenceCourse.PagesAreLocked, TextWrapping = TextWrapping.Wrap },
                PrimaryButtonText = "Open in Obsidian",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
            };
            note.SetValue(Microsoft.UI.Xaml.Automation.AutomationProperties.AutomationIdProperty, "referenceCalmNote");
            if (await ShowDialogSafelyAsync(note) != ContentDialogResult.Primary) return;
            RememberNoteShown(course);
        }
        await FolderActions.OpenInObsidian(revealFolder, course.DirectoryPath,
            BundledToolchain.SupportPath("obsidian_defaults/.obsidian"));
    }

    // ---- Picking a school year -------------------------------------------------

    /// <summary>The years offered today, newest first, then "no school year" — always last.</summary>
    private static ComboBox YearPicker(int? selected)
    {
        var picker = new ComboBox { Header = "School year", MinWidth = 220 };
        foreach (int year in SchoolYear.Offered(Today))
            picker.Items.Add(new ComboBoxItem { Content = SchoolYear.Label(year), Tag = year });
        picker.Items.Add(new ComboBoxItem { Content = "No school year", Tag = null });
        picker.SelectedIndex = selected is int wanted && SchoolYear.Offered(Today).Contains(wanted)
            ? SchoolYear.Offered(Today).ToList().IndexOf(wanted)
            : picker.Items.Count - 1;
        return picker;
    }

    private static int? ChosenYear(ComboBox picker) => (picker.SelectedItem as ComboBoxItem)?.Tag as int?;

    public async Task SetSchoolYear(Course course)
    {
        string? askedIn = Workspace.WorkspacePath;
        string shown = ReferenceCourse.ShownCode(course);
        int? before = SchoolYear.Read(course.Configuration.StoredReferenceSchoolYear, Today);
        var picker = YearPicker(before);
        var warning = new TextBlock { TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
        var dialog = new ContentDialog
        {
            Title = $"File {shown} under a school year",
            Content = new StackPanel { Spacing = 8, Children = { picker, warning } },
            PrimaryButtonText = "Save",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        void Validate()
        {
            string? trouble = ReferenceCourse.ShelfTrouble(shown, ChosenYear(picker),
                ReferenceCourse.Shelf(Workspace.Courses, Today), ignoringFolder: course.Code);
            warning.Text = trouble ?? "";
            warning.Visibility = trouble is null ? Visibility.Collapsed : Visibility.Visible;
            dialog.IsPrimaryButtonEnabled = trouble is null;
        }
        picker.SelectionChanged += (_, _) => Validate();
        Validate();
        if (await ShowDialogSafelyAsync(dialog) != ContentDialogResult.Primary) return;
        if (TheFolderMovedUnderThisConfirmation(askedIn)) return;
        if (ReferenceCourseUpkeep.SetSchoolYear(course, ChosenYear(picker), Workspace.Courses, Today) is { } problem)
        {
            await ShowError("The school year was not changed", problem);
            return;
        }
        Workspace.Reload();
        _window.ApplyState();
    }

    // ---- Keep a Copy for Reference… -----------------------------------------------

    private async Task KeepACopy(Course course)
    {
        string? askedIn = Workspace.WorkspacePath;
        if (askedIn is null) return;
        string shown = ReferenceCourse.ShownCode(course);
        var picker = YearPicker(SchoolYear.StartingYear(Today));
        var nameBox = new TextBox { Header = "Folder name" };
        var warning = new TextBlock { TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
        var addOns = ObsidianAddOns.FoundIn(course.DirectoryPath);
        var notes = new StackPanel { Spacing = 8 };
        notes.Children.Add(new TextBlock { Text = ReferenceCourse.CopyIsASnapshot(shown), TextWrapping = TextWrapping.Wrap });
        if (!addOns.IsEmpty)
            notes.Children.Add(new TextBlock { Text = ReferenceCourse.KeepACopyLeavesAddOnsBehind(shown), TextWrapping = TextWrapping.Wrap });
        notes.Children.Add(new TextBlock { Text = ReferenceCourse.NeverDeployed(shown) + " " + ReferenceCourse.PagesAreLocked, TextWrapping = TextWrapping.Wrap });

        bool nameEdited = false, settingName = false;
        var dialog = new ContentDialog
        {
            Title = $"Keep a copy of {shown} for reference",
            Content = new StackPanel { Spacing = 10, Children = { picker, nameBox, warning, notes } },
            PrimaryButtonText = "Keep a Copy",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        void Propose()
        {
            if (nameEdited) return;
            settingName = true;
            nameBox.Text = ReferenceCourse.ProposedFolderName(shown, ChosenYear(picker), Workspace.Courses.Select(c => c.Code));
            settingName = false;
        }
        void Validate()
        {
            // The sheet's own refusals grey the button with a sentence; a
            // disabled button is not a press, so it writes nothing (#287).
            string name = CourseCodeValidator.Normalize(nameBox.Text);
            string? trouble = name.Length == 0 ? null
                : CourseCodeValidator.Problem(name, Workspace.Courses.Select(c => c.Code))
                  ?? ReferenceCourse.ShelfTrouble(shown, ChosenYear(picker), ReferenceCourse.Shelf(Workspace.Courses, Today));
            warning.Text = trouble ?? "";
            warning.Visibility = trouble is null ? Visibility.Collapsed : Visibility.Visible;
            dialog.IsPrimaryButtonEnabled = trouble is null && name.Length > 0;
        }
        picker.SelectionChanged += (_, _) => { Propose(); Validate(); };
        nameBox.TextChanged += (_, _) => { if (!settingName) nameEdited = true; Validate(); };
        Propose();
        Validate();
        if (await ShowDialogSafelyAsync(dialog) != ContentDialogResult.Primary) return;
        if (TheFolderMovedUnderThisConfirmation(askedIn)) return;

        string folderName = CourseCodeValidator.Normalize(nameBox.Text);
        int? year = ChosenYear(picker);
        var working = WorkingDialog($"Copying {shown}…");
        var showing = ShowDialogSafelyAsync(working.Dialog);
        string? failure = null;
        try
        {
            await Task.Run(() => ReferenceCopier.KeepACopy(course, folderName, year, Workspace.CoursesDirectory(),
                new Progress<ReferenceTreeCopier.Progress>(p => working.Report(p.Copied, p.Total))));
        }
        catch (ReferenceCopier.NotMade notMade) { failure = notMade.Message; }
        finally { working.Dialog.Hide(); await showing; }

        Workspace.Reload();
        _window.ApplyState();
        if (failure is not null) await ShowError("No copy was made", failure);
    }

    /// <summary>A dialog with a bar measured in BYTES, closed by its owner.</summary>
    private static (ContentDialog Dialog, Action<long, long> Report) WorkingDialog(string title, string? stopText = null, Action? stop = null)
    {
        var bar = new ProgressBar { Minimum = 0, Maximum = 1, Value = 0, MinWidth = 320 };
        var line = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var dialog = new ContentDialog
        {
            Title = title,
            Content = new StackPanel { Spacing = 8, Children = { bar, line } },
        };
        if (stopText is not null && stop is not null)
        {
            dialog.CloseButtonText = stopText;
            dialog.CloseButtonClick += (_, args) => { args.Cancel = true; stop(); };
        }
        return (dialog, (copied, total) =>
        {
            bar.Maximum = Math.Max(1, total);
            bar.Value = copied;
            line.Text = ReferenceImport.CopiedSoFar(copied, total);
        });
    }

    // ---- Import Courses for Reference… -------------------------------------------

    public async Task OpenImportForReference()
    {
        string? askedIn = Workspace.WorkspacePath;
        if (askedIn is null) return;
        var picker = new Windows.Storage.Pickers.FolderPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(_window));
        picker.FileTypeFilter.Add("*");
        var chosen = await picker.PickSingleFolderAsync();
        if (chosen is null || TheFolderMovedUnderThisConfirmation(askedIn)) return;

        var (source, refusal) = await Task.Run(() => ReferenceImport.Resolve(chosen.Path, askedIn, Today));
        if (source is null)
        {
            await ShowError(ReferenceImport.Title, refusal ?? ReferenceImport.NoCoursesThere(chosen.Name));
            return;
        }

        var rows = new List<(CheckBox Tick, ComboBox Year, TextBlock Trouble, ReferenceImport.FoundCourse Course)>();
        var list = new StackPanel { Spacing = 10 };
        var importDialog = new ContentDialog
        {
            Title = ReferenceImport.Title,
            PrimaryButtonText = ReferenceImport.ImportButton,
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        var tickSomething = new TextBlock { Text = ReferenceImport.TickSomething, TextWrapping = TextWrapping.Wrap };
        void Validate()
        {
            var shelf = ReferenceCourse.Shelf(Workspace.Courses, Today);
            var ticked = new List<(string Code, int? Year, string Folder)>();
            bool anyCanCome = false;
            foreach (var (tick, year, trouble, course) in rows)
            {
                string? problem = course.Problem;
                if (problem is null && tick.IsChecked == true)
                {
                    string code = CourseCodeValidator.Normalize(course.CourseCode);
                    problem = ReferenceCourse.ShelfTrouble(code, ChosenYear(year), shelf)
                              ?? ticked.Where(t => t.Code == code && t.Year == ChosenYear(year))
                                  .Select(t => ReferenceImport.AlsoTickedForThatYear(t.Folder, code)).FirstOrDefault();
                    if (problem is null) { anyCanCome = true; ticked.Add((code, ChosenYear(year), course.FolderName)); }
                }
                // Marked BESIDE ITS OWN ROW; the others can still come across.
                trouble.Text = problem ?? "";
                trouble.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
            }
            tickSomething.Visibility = anyCanCome ? Visibility.Collapsed : Visibility.Visible;
            importDialog.IsPrimaryButtonEnabled = anyCanCome;
        }
        foreach (var course in source.Courses)
        {
            var tick = new CheckBox
            {
                Content = $"{CourseCodeValidator.Normalize(course.CourseCode)} — {course.CourseName}",
                IsChecked = source.TickedWhenOpened.Contains(course.FolderName),
                IsEnabled = course.Problem is null,
            };
            var year = YearPicker(course.SuggestedSchoolYear);
            var summary = new TextBlock { Text = ReferenceImport.CourseSummary(course.SectionNumbers.Count, course.PageCount, course.ByteCount), Opacity = 0.75 };
            var trouble = new TextBlock { TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
            tick.Checked += (_, _) => Validate();
            tick.Unchecked += (_, _) => Validate();
            year.SelectionChanged += (_, _) => Validate();
            rows.Add((tick, year, trouble, course));
            list.Children.Add(new StackPanel { Spacing = 4, Children = { tick, summary, year, trouble } });
        }
        var body = new StackPanel { Spacing = 10 };
        body.Children.Add(new TextBlock { Text = ReferenceImport.Explanation, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new ScrollViewer { Content = list, MaxHeight = 360 });
        body.Children.Add(tickSomething);
        body.Children.Add(new TextBlock { Text = ReferenceImport.BuiltWebsitesAreNotCopied, TextWrapping = TextWrapping.Wrap });
        if (source.Courses.Any(c => !c.AddOns.IsEmpty))
            body.Children.Add(new TextBlock { Text = ReferenceImport.AddOnsAreLeftBehind, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new TextBlock { Text = ReferenceCourse.PagesAreLocked, TextWrapping = TextWrapping.Wrap });
        importDialog.Content = body;
        Validate();
        if (await ShowDialogSafelyAsync(importDialog) != ContentDialogResult.Primary) return;
        if (TheFolderMovedUnderThisConfirmation(askedIn)) return;

        var requests = rows.Where(r => r.Tick.IsChecked == true && r.Course.Problem is null)
            .Select(r => new ReferenceImport.Request(r.Course, ChosenYear(r.Year))).ToList();
        using var stop = new CancellationTokenSource();
        var working = WorkingDialog(ReferenceImport.Copying(CourseCodeValidator.Normalize(requests[0].Course.CourseCode)), "Stop", stop.Cancel);
        var showing = ShowDialogSafelyAsync(working.Dialog);
        string sourceName = Path.GetFileName(Path.TrimEndingDirectorySeparator(chosen.Path));
        List<ReferenceImport.Outcome> outcomes;
        try
        {
            outcomes = await Task.Run(() => ReferenceImport.ImportCourses(requests, Workspace.CoursesDirectory(),
                Workspace.Courses.Select(c => c.Code), ReferenceCourse.Shelf(Workspace.Courses, Today), sourceName,
                new Progress<ReferenceImport.Progress>(p =>
                {
                    working.Dialog.Title = ReferenceImport.Copying(p.Course);
                    working.Report(p.Copied, p.Total);
                }), stop.Token));
        }
        finally { working.Dialog.Hide(); await showing; }

        Workspace.Reload();
        _window.ApplyState();

        // The done screen: one line per course, in the same scroll region as
        // the rest, with the sentence that says where they are outside it.
        var lines = new StackPanel { Spacing = 6 };
        foreach (var outcome in outcomes)
        {
            string text = outcome.Made is { } made
                ? ReferenceImport.Imported(made.ShownCode, made.SchoolYear, made.SectionCount)
                : outcome.WasStopped ? ReferenceImport.Stopped
                : ReferenceImport.CouldNotImport(outcome.Course, outcome.NotImportedBecause ?? "");
            lines.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap });
        }
        var done = new ContentDialog
        {
            Title = ReferenceImport.DoneTitle,
            Content = new StackPanel
            {
                Spacing = 10,
                Children =
                {
                    new ScrollViewer { Content = lines, MaxHeight = 320 },
                    new TextBlock { Text = ReferenceImport.WhereTheyAre, TextWrapping = TextWrapping.Wrap },
                },
            },
            CloseButtonText = "OK",
        };
        await ShowDialogSafelyAsync(done);
    }
}
