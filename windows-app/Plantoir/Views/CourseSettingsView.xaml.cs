using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// The course settings form: every control edits a key of the same
/// course_config.json the toolchain reads, and unknown keys survive the
/// round trip untouched. Save writes; Revert re-reads the last save.
/// </summary>
public sealed partial class CourseSettingsView : UserControl
{
    private readonly MainWindow _window;
    private readonly Course _course;
    public string CourseCode => _course.Code;
    private CourseConfiguration Config => _course.Configuration;

    public CourseSettingsView(MainWindow window, Course course)
    {
        InitializeComponent();
        _window = window;
        _course = course;
        HeaderCode.Text = course.Code;
        HeaderName.Text = course.Configuration.CourseName;
        ObsidianButton.IsEnabled = FolderActions.ObsidianIsInstalled;
        BuildForm();
        RefreshDirtyState();
    }

    private void MarkChanged()
    {
        RefreshDirtyState();
        HeaderName.Text = Config.CourseName;
        foreach (var (section, sample) in _fontSampleHeaders) sample.Text = SampleHeaderText(section);
    }

    // ---- Excluding and re-including ---------------------------------------

    /// <summary>
    /// A teacher took a folder or file out of a list. Record the exclusion so
    /// the next build does not simply rediscover it.
    ///
    /// <para>BOTH halves are needed and the editor has already done one of
    /// them: the name's ABSENCE from the copy list is the actual mechanism,
    /// and <c>excluded_items</c> is what stops preflight putting it back. The
    /// build does reconcile the two, but only at the next build — a teacher
    /// reading this list before then would see a folder they had just
    /// removed.</para>
    /// </summary>
    private void RecordExclusion(string scope, string kind, string name)
    {
        Config.Exclude(scope, name);
        if (kind == "folder") DropFromMarksPool(name);
        // No section on the line: these lists are COURSE-wide, and the
        // two-argument overload exists for exactly that. Naming the course's
        // first section would assert a section that had nothing to do with the
        // change -- and on a course numbered [3, 5] it would say "/3", which a
        // person reading the trail would believe.
        ActivityTrail.Note(ActivityTrail.Event.ItemExcluded,
            $"{_course.Code}: removed the {CourseConfiguration.ScopeInWords(scope)} {kind} “{name}” from this course's site");
    }

    /// <summary>
    /// A folder that has left the lists must leave the marks pool with it.
    ///
    /// <para>Without this the consequential dialog's own sentence is FALSE --
    /// it promises "Removing it will take it out of your course's marks pool"
    /// -- and `graded_folders` ends up naming a folder `excluded_items` tells
    /// the build to skip. If it was the only entry, the course is left with a
    /// non-empty pool matching nothing the site publishes, so nothing counts
    /// for marks while the settings claim something does. This is the mac's
    /// row 380 correction (3), ported rather than rediscovered.</para>
    ///
    /// <para><b>One thing this comment used to say is not true and was
    /// corrected 2026-09-06</b>, because a wrong reason gets acted on: such a
    /// pool does NOT read as "asked and answered" to the build and does not
    /// suppress the `noGradedFolders` warning. `_has_graded_folders` in
    /// <c>build_site.py</c> walks the MERGED tree and answers false when no
    /// directory there matches a pooled name, so <c>site_health.py</c> raises
    /// the finding exactly as it would for an empty pool. The reason to do
    /// this is the promise in the dialog, which is reason enough.</para>
    ///
    /// <para>Materialised first, so a legacy course whose pool has never been
    /// set does not get one CREATED as an empty list by a removal -- that
    /// would silently switch it from the historical substring rule to "nothing
    /// counts".</para>
    /// </summary>
    private void DropFromMarksPool(string name)
    {
        var pool = MarksPool();
        if (pool.RemoveAll(f => string.Equals(f, name, StringComparison.OrdinalIgnoreCase)) == 0) return;
        Config.GradedFolders = pool;
    }

    /// <summary>
    /// A teacher added a name back. The trail line goes on ONLY when the name
    /// really was excluded — an ordinary new folder is not a re-inclusion, and
    /// a line saying it was would be believed.
    /// </summary>
    private void RecordReInclusion(string scope, string kind, string name)
    {
        if (!Config.ReInclude(scope, name)) return;
        ActivityTrail.Note(ActivityTrail.Event.ItemReIncluded,
            $"{_course.Code}: added the {CourseConfiguration.ScopeInWords(scope)} {kind} “{name}” back to this course's site");
    }

    /// <summary>
    /// Redraw the controls whose rows carry a protection state, because that
    /// state is computed at draw time and something has just changed the
    /// answer.
    ///
    /// <para>Deferred to the next layout pass: the callers are inside a
    /// control's own event handler, and replacing that control's parent
    /// mid-event is how a click ends up delivered to a button that no longer
    /// exists.</para>
    /// </summary>
    private void RebuildProtectedRows() =>
        DispatcherQueue.TryEnqueue(() =>
        {
            double offset = FormScroll.VerticalOffset;
            BuildForm();
            // Rebuilding scrolls back to the top otherwise, and a teacher who
            // ticked a box near the bottom of a long form should not be sent
            // back to the course name.
            FormScroll.UpdateLayout();
            FormScroll.ChangeView(null, offset, null, disableAnimation: true);
        });

    /// <summary>
    /// A teacher pressed the info button on a row that cannot go. Record which
    /// rule refused, and the sentence they were shown.
    ///
    /// <para>"I could not remove the folder" is a report support WILL receive,
    /// and without this the trail shows nothing at all - the teacher clicked a
    /// button and no state changed. The sentence is a specialNames one, so it
    /// is product wording rather than anything written on a page.</para>
    /// </summary>
    private void RecordRemovalBlocked(string list, string name, string reason)
    {
        ActivityTrail.Note(ActivityTrail.Event.RemovalBlocked,
            $"{_course.Code}: could not remove \u201C{name}\u201D from {list} - {reason}");
    }

    /// <summary>
    /// "What else does Plantoir use my folders for?" — opens the sheet that
    /// names this course's own special folders.
    ///
    /// <para><b>Nothing is written to the trail when this opens, and that
    /// matches the mac deliberately.</b> The trail exists so a problem
    /// reported next week can be looked into; a read-only sheet changes no
    /// state and leaves nothing to diagnose. Recording it would also mean a
    /// new event in <c>activityTrail.mustRecord</c>, which is pinned across
    /// both platforms — so a help sheet would turn the mac suite red. If it
    /// ever earns a line, it earns one on both sides at once.</para>
    ///
    /// <para>The configuration is read at CLICK time, not captured when the
    /// button is built: a teacher who ticks a graded folder and then opens
    /// this must be shown what they just chose, not what the form was showing
    /// when it was drawn.</para>
    /// </summary>
    private Button FoldersHelpButton()
    {
        var button = new Button
        {
            Content = SpecialFoldersHelp.OpenedBy,
            Margin = new Thickness(0, 4, 0, 0),
        };
        AutomationProperties.SetAutomationId(button, "openFoldersHelpButton");
        button.Click += async (_, _) =>
        {
            if (XamlRoot is null) return;
            var dialog = SpecialFoldersHelpDialog.For(Config);
            dialog.XamlRoot = XamlRoot;
            await dialog.ShowAsync();
        };
        return button;
    }

    /// <summary>
    /// Everything the protection rules need, read fresh at the moment a row is
    /// drawn or a box is ticked.
    ///
    /// <para>Never cached: ticking a SECOND graded folder is exactly what
    /// unblocks the first, and turning the coverage map off unblocks the
    /// curriculum folder. A captured answer would go on refusing.</para>
    /// </summary>
    /// <summary>
    /// What a list editor does after a change: the ordinary dirty-tracking,
    /// AND a redraw of every control whose rows carry a protection state.
    ///
    /// <para>Removing a folder from ONE list can change whether a row in
    /// ANOTHER may go — the marks floor counts across both folder lists — and
    /// only the touched editor rebuilds itself. It also changes which folders
    /// the Marks checklist should be offering at all.</para>
    /// </summary>
    private void ChangedAndRedraw()
    {
        MarkChanged();
        RebuildProtectedRows();
    }

    // ---- The two foot-guns behind the folder lists ----------------------------

    private void ShowFolderNotice(string message)
    {
        FolderNotice.Message = message;
        FolderNotice.IsOpen = true;
    }

    /// <summary>
    /// Adding a name CREATES the folder — in every section for a per-section
    /// one — and says so. It used to write a configuration entry pointing at
    /// nothing, and the folder had to be made in Obsidian afterwards.
    /// </summary>
    private void CreateFolderForNewEntry(string name, FolderScope scope)
    {
        bool created = SpecialFolderRenamer.CreateFoldersOnDisk(
            name, scope, _course.DirectoryPath, Config.SectionNumbers);
        if (!created) return;
        ActivityTrail.Note(ActivityTrail.Event.FolderCreated,
            $"created the folder {name} in {_course.Code} ({SpecialFolderRenamer.ConfigurationKey(scope)})");
        ShowFolderNotice(SpecialNames.AddCreatesTheFolder.Replace("{name}", name));
    }

    /// <summary>Removal excludes; it has never deleted anything, and teachers could not tell.</summary>
    private void NoticeAfterRemoval(string name) =>
        ShowFolderNotice(SpecialNames.RemoveLeavesTheFolderOnDisk.Replace("{name}", name));

    // ---- Renaming a folder ---------------------------------------------------

    private IReadOnlyList<string> NamesInScope(FolderScope scope) =>
        scope == FolderScope.Shared ? Config.SharedFolders : Config.PerSectionFolders;

    /// <summary>
    /// The sheet: the name, the explanation, a live refusal as the teacher
    /// types, and — when a rename of this folder stopped after the folders
    /// moved — the field filled in with the name it was heading for and one
    /// line saying why. Rename commits to DISK at once, not at Save: the
    /// folder has really moved, and a Cancel that appeared to undo it would
    /// be a lie. Only the keys a rename carries across are written, so the
    /// teacher's other unsaved edits stay unsaved.
    /// </summary>
    private async Task OpenRenameFolderDialog(string oldName, FolderScope scope)
    {
        // Settled ONCE, when the sheet opens: it reads a record and asks the
        // disk, which is not something to do per keystroke.
        string? interruptedTarget = SpecialFolderRenamer.InterruptedRenameTarget(
            oldName, scope, _course.DirectoryPath, Config.SectionNumbers);

        var field = new TextBox { Text = interruptedTarget ?? oldName };
        AutomationProperties.SetAutomationId(field, "renameField");
        var explanation = new TextBlock { Text = SpecialNames.RenameExplanation, TextWrapping = TextWrapping.Wrap, Opacity = 0.8 };
        var problem = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed,
            Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"],
        };
        AutomationProperties.SetAutomationId(problem, "renameProblem");

        var body = new StackPanel { Spacing = 10 };
        if (interruptedTarget is not null)
        {
            body.Children.Add(new TextBlock
            {
                Text = SpecialNames.RenameInterrupted.Replace("{old}", oldName).Replace("{new}", interruptedTarget),
                TextWrapping = TextWrapping.Wrap,
            });
        }
        body.Children.Add(field);
        body.Children.Add(explanation);
        body.Children.Add(problem);

        var dialog = new ContentDialog
        {
            Title = SpecialNames.RenameSheetTitle.Replace("{name}", oldName),
            Content = body,
            PrimaryButtonText = "Rename",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot,
        };
        AutomationProperties.SetAutomationId(dialog, "renameFolderDialog");

        bool Finishing() => interruptedTarget is not null
            && interruptedTarget.Equals(field.Text.Trim(), StringComparison.OrdinalIgnoreCase);
        void Recheck()
        {
            string? why = SpecialFolderRenamer.Problem(field.Text, oldName, NamesInScope(scope), Finishing());
            problem.Text = why ?? "";
            problem.Visibility = why is null ? Visibility.Collapsed : Visibility.Visible;
            dialog.IsPrimaryButtonEnabled = why is null;
        }
        field.TextChanged += (_, _) => Recheck();
        Recheck();

        // The sheet stays open on a failure, so the teacher can type a
        // different name rather than start again.
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                string newName = field.Text.Trim();
                string? failure = await RenameFolderAsync(oldName, newName, scope, Finishing());
                if (failure is not null)
                {
                    problem.Text = failure;
                    problem.Visibility = Visibility.Visible;
                    args.Cancel = true;
                }
            }
            finally { deferral.Complete(); }
        };

        try { await dialog.ShowAsync(); }
        catch (Exception ex) { App.LogDiagnostic($"rename dialog: {ex.Message}"); }
    }

    /// <summary>
    /// Disk first, then the configuration, in that order: a move that fails
    /// leaves the course exactly as it was, where the other order would leave
    /// a configuration naming a folder that is not there — the state this
    /// whole feature exists to make impossible. Returns the sentence to show
    /// inside the sheet on failure, or null when the rename is whole.
    /// </summary>
    private async Task<string?> RenameFolderAsync(string oldName, string newName, FolderScope scope, bool finishing)
    {
        string courseDirectory = _course.DirectoryPath;
        var sections = Config.SectionNumbers.ToList();
        RenameOutcome outcome;
        try
        {
            // Off the UI thread: the move is quick, but reading every page in
            // the course to rewrite links is not on a synced vault.
            outcome = await Task.Run(() => finishing
                // The folders already moved; only the links and the record remain.
                ? new RenameOutcome(true,
                    SpecialFolderRenamer.DoneMessage(oldName, newName,
                        SpecialFolderRenamer.RelinkPages(courseDirectory, oldName, newName)),
                    0, 0, NothingWasThere: false)
                : SpecialFolderRenamer.Rename(oldName, newName, scope, courseDirectory, sections));
        }
        catch (SpecialFolderRenamer.RenameException error)
        {
            return error.Message;
        }

        try
        {
            Config.RecordOnDisk(values => SpecialFolderRenamer.Renaming(values, oldName, newName, scope),
                                _course.ConfigFilePath);
        }
        catch (Exception error)
        {
            // Recorded BEFORE returning: the folder has moved and the settings
            // do not know, which is the state somebody will be asked to
            // explain later. Not "the rename failed" — a rename whose
            // bookkeeping did not land; the record stays so the next opening
            // of the sheet can finish it.
            ActivityTrail.Note(ActivityTrail.Event.FolderRenamed,
                $"renamed the folder {oldName} to {newName} in {_course.Code} but could not write it to this course's settings — {error.Message}");
            return $"“{oldName}” was renamed to “{newName}”, but Plantoir could not write the change to this course's settings: {error.Message}";
        }
        SpecialFolderRenamer.ClearRenameRecord(courseDirectory);
        ActivityTrail.Note(ActivityTrail.Event.FolderRenamed,
            $"renamed the folder {oldName} to {newName} in {_course.Code} ({SpecialFolderRenamer.ConfigurationKey(scope)}, {outcome.FoldersMoved} moved, {outcome.PagesRelinked} pages relinked)");

        ShowFolderNotice(outcome.Message);
        ChangedAndRedraw();
        return null;
    }

    // ---- The marks pool ---------------------------------------------------

    /// <summary>
    /// The folder names found inside the course folder, as of the last time
    /// the form was drawn.
    ///
    /// <para>Cached for one <see cref="BuildForm"/> pass rather than walked on
    /// demand, because the protection rules are asked afresh for every row of
    /// every list — a disk walk per row, on the UI thread, for an answer that
    /// cannot change between two rows of the same pass. Everything that DOES
    /// change it goes through <see cref="BuildForm"/> anyway: the constructor,
    /// <see cref="RebuildProtectedRows"/> after any list edit or tick, and
    /// Revert. The one thing it cannot see is the disk changing underneath —
    /// a folder made in Obsidian while this page is open — which the next tick
    /// picks up.</para>
    /// </summary>
    private IReadOnlyList<string> _nestedFolderNames = Array.Empty<string>();

    /// <summary>
    /// Every folder the Marks checklist may offer, read from the config LIVE
    /// so a folder added or removed in the lists above is reflected at once,
    /// over the walked names cached for this pass.
    /// </summary>
    private List<string> GradedFolderChoicesNow() =>
        GradedFolderChoices.For(Config, _nestedFolderNames);

    /// <summary>
    /// The pool as it stands, materialised from the SAME choices the checklist
    /// displays. Feeding the two from one place is the point: a pool
    /// materialised from a narrower list than the one on screen is how a
    /// teacher's first tick drops a folder the build was counting.
    /// </summary>
    private List<string> MarksPool() =>
        Config.MaterializedGradedFolders(GradedFolderChoicesNow());

    private ProtectionContext Protection() => new(
        InWizard: false,
        CurriculumCoverageEnabled: Config.OverallIncludesCurriculumCoverage,
        // Course Settings has no curriculum-PAGES switch - that choice is made
        // once, in the wizard - so it can never be the reason here.
        CurriculumPagesEnabled: false,
        Jurisdiction: SpecialNames.DefaultJurisdiction,
        ResolvedCurriculumFolder: Config.ResolvedCurriculumFolder,
        GradedFolders: MarksPool(),
        PerSectionFolders: Config.PerSectionFolders,
        ResolvedClassFolder: ClassFolderRule.Name(Config.ClassFolder, Config.PerSectionFolders));

    // ---- Font sample text ------------------------------------------------

    /// <summary>
    /// Each section's font sample shows that section's OWN site title —
    /// computed exactly as the build will compute it, so the name, the grade
    /// switch, and the section-marker switch are all reflected in the
    /// candidate typeface.
    /// </summary>
    private readonly List<(int Section, TextBlock Block)> _fontSampleHeaders = new();

    private string SampleHeaderText(int section) =>
        CourseConfiguration.ComputedSiteTitle(Config.CourseName, _course.Code, section,
            Config.ShowsGradeInTitle(section), Config.ShowsSectionMarker(section));

    private PublishingChoiceView? _publishingChoice;

    private void RefreshDirtyState()
    {
        bool dirty = Config.HasUnsavedChanges;
        // A folder-publishing course with a bad folder cannot be saved — a
        // publish must never discover the problem after the fact (row 102).
        SaveButton.IsEnabled = dirty && _publishingChoice?.Problem is null;
        RevertButton.IsEnabled = dirty;
    }

    // ---- Form ------------------------------------------------------------

    private void BuildForm()
    {
        Form.Children.Clear();
        _fontSampleHeaders.Clear();   // rebuilt below; Revert re-enters here

        // Walked once per pass, before anything asks what the Marks list
        // offers or what the pool currently holds.
        _nestedFolderNames = GradedFolderChoices.NestedFolderNames(
            _course.DirectoryPath,
            Config.ExcludedItems(CourseConfiguration.SharedScope),
            Config.ExcludedItems(CourseConfiguration.PerSectionScope));

        // -------- Settings — Overall --------
        Form.Children.Add(FormBuilders.SectionHeaderWithCaption("Settings — Overall", null));

        var nameBox = new TextBox { Text = Config.CourseName };
        nameBox.TextChanged += (_, _) => { Config.CourseName = nameBox.Text; MarkChanged(); RebuildGradeWarnings(); };
        Form.Children.Add(FormBuilders.LabeledRow("Course name", nameBox));

        if (Config.IsClub(CourseNameCatalogs.Shared))
        {
            var shortBox = new TextBox { Text = Config.CustomShortName, MaxLength = 12 };
            shortBox.TextChanged += (_, _) => { Config.CustomShortName = shortBox.Text; MarkChanged(); };
            Form.Children.Add(FormBuilders.LabeledRow("Short label beside emoji (clubs, ≤ 12 characters)", shortBox));
        }

        var localeBox = new ComboBox { MinWidth = 320 };
        foreach (string code in LocaleCatalog.Codes) localeBox.Items.Add(LocaleCatalog.DisplayName(code));
        int localeIndex = LocaleCatalog.Codes.ToList().IndexOf(Config.Locale);
        localeBox.SelectedIndex = localeIndex >= 0 ? localeIndex : LocaleCatalog.Codes.ToList().IndexOf("en-US");
        localeBox.SelectionChanged += (_, _) =>
        {
            if (localeBox.SelectedIndex >= 0) { Config.Locale = LocaleCatalog.Codes[localeBox.SelectedIndex]; MarkChanged(); }
        };
        Form.Children.Add(FormBuilders.LabeledRow("Language / region (Quartz locale)", localeBox));

        var readTime = new ToggleSwitch { IsOn = Config.ShowReadingTime, OnContent = "", OffContent = "" };
        readTime.Toggled += (_, _) => { Config.ShowReadingTime = readTime.IsOn; MarkChanged(); };
        Form.Children.Add(FormBuilders.LabeledRow("Show page read-time estimates to students", readTime));

        var expandBox = new ComboBox { MinWidth = 320 };
        expandBox.Items.Add("Chevron or folder name");
        expandBox.Items.Add("Chevron only (name opens the folder)");
        expandBox.SelectedIndex = Config.ExpandOnFolderClick ? 0 : 1;
        expandBox.SelectionChanged += (_, _) => { Config.ExpandOnFolderClick = expandBox.SelectedIndex == 0; MarkChanged(); };
        Form.Children.Add(FormBuilders.LabeledRow("Sidebar folders expand when clicking", expandBox));

        var coverageToggle = new ToggleSwitch { IsOn = Config.OverallIncludesCurriculumCoverage, OnContent = "", OffContent = "" };
        var notesToggle = new ToggleSwitch
        {
            IsOn = Config.OverallIncludesCoverageNotes,
            IsEnabled = Config.OverallIncludesCurriculumCoverage,
            OnContent = "",
            OffContent = "",
        };

        coverageToggle.Toggled += (_, _) =>
        {
            foreach (int section in Config.SectionNumbers)
                Config.SetIncludesCurriculumCoverage(section, coverageToggle.IsOn);
            notesToggle.IsEnabled = coverageToggle.IsOn;
            // This switch is what half the blocked sentences tell a teacher to
            // turn off, so the rows have to be rebuilt against the new answer.
            // Protection is computed when a row is DRAWN; without this the info
            // button says "turn off Publish the curriculum coverage map", the
            // teacher does, and the row goes on refusing.
            RebuildProtectedRows();
            if (!coverageToggle.IsOn)
            {
                notesToggle.IsOn = false;
                foreach (int section in Config.SectionNumbers)
                    Config.SetIncludesCoverageNotes(section, false);
            }
            MarkChanged();
        };
        // The label is SpecialNames.CoverageSwitchLabelInSettings, and that is
        // load-bearing: the blocked-removal sentences tell a teacher to turn
        // off this switch BY NAME, so a paraphrase here sends them looking for
        // a control that does not exist. It read "Include Curriculum Coverage
        // map" until this piece; the contract's wording won, because the
        // contract is generated from the macOS app and a Windows-only
        // paraphrase is drift rather than a decision.
        var coverageRow = FormBuilders.LabeledRow(SpecialNames.CoverageSwitchLabelInSettings, coverageToggle);
        coverageRow.Children.Add(FormBuilders.ExampleCaption(
            "Generates a page showing which specific and overall expectations are addressed"));
        Form.Children.Add(coverageRow);

        notesToggle.Toggled += (_, _) =>
        {
            foreach (int section in Config.SectionNumbers)
                Config.SetIncludesCoverageNotes(section, notesToggle.IsOn);
            MarkChanged();
        };
        var notesRow = FormBuilders.LabeledRow("Include explanations on Curriculum Coverage page", notesToggle);
        notesRow.Children.Add(FormBuilders.ExampleCaption(
            "Shows “What counts” and “Reading it honestly” sections on the page"));
        Form.Children.Add(notesRow);

        // -------- Publishing (course-level: every section goes the same way) --------
        Form.Children.Add(FormBuilders.SectionHeaderWithCaption("Deploying", null));
        _publishingChoice = new PublishingChoiceView(_window,
            () => Config.DeployTarget, v => Config.DeployTarget = v,
            () => Config.DeployFolderPath, v => Config.DeployFolderPath = v,
            // The account identifies the teacher, not the course, so it is
            // kept in app settings and saved as it is typed — a teacher
            // should never enter it twice.
            () => _window.Workspace.Settings.CloudflareAccountId,
            v => { _window.Workspace.Settings.CloudflareAccountId = v; _window.Workspace.Settings.Save(); },
            () => Config.AdditionalDeployTargets, v => Config.AdditionalDeployTargets = v.ToList());
        _publishingChoice.Changed += MarkChanged;
        Form.Children.Add(_publishingChoice.Root);

        // -------- Footer --------
        Form.Children.Add(FormBuilders.SectionHeaderWithCaption("Footer", null));
        Form.Children.Add(FormBuilders.ExampleCaption(
            "Optional: type or paste HTML below to appear at the bottom of every page on your site — many teachers use a Creative Commons licence notice. Leave the box empty for no footer."));
        var footerBox = new TextBox
        {
            Text = Config.FooterHtml,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 72,
            FontFamily = new FontFamily("Consolas"),
            PlaceholderText = "For example: This site is licensed under <a href=\"…\">CC BY 4.0</a>.",
        };
        footerBox.TextChanged += (_, _) => { Config.FooterHtml = footerBox.Text; MarkChanged(); };
        Form.Children.Add(footerBox);

        // -------- Content Structure --------
        Form.Children.Add(FormBuilders.SectionHeaderWithCaption("Content Structure", null));
        Form.Children.Add(FormBuilders.StringListEditor("Shared folders (all sections)", false,
            () => Config.SharedFolders, v => Config.SharedFolders = v, ChangedAndRedraw,
            name => { RecordExclusion(CourseConfiguration.SharedScope, "folder", name); NoticeAfterRemoval(name); },
            name => { RecordReInclusion(CourseConfiguration.SharedScope, "folder", name); CreateFolderForNewEntry(name, FolderScope.Shared); },
            name => ItemProtectionRule.For(name, ItemList.SharedFolders, Protection()),
            (name, reason) => RecordRemovalBlocked("the shared folders", name, reason),
            name => _ = OpenRenameFolderDialog(name, FolderScope.Shared)));
        Form.Children.Add(FormBuilders.StringListEditor("Shared files (all sections)", true,
            () => Config.SharedFiles, v => Config.SharedFiles = v, ChangedAndRedraw,
            name => RecordExclusion(CourseConfiguration.SharedScope, "file", name),
            name => RecordReInclusion(CourseConfiguration.SharedScope, "file", name),
            name => ItemProtectionRule.For(name, ItemList.SharedFiles, Protection()),
            (name, reason) => RecordRemovalBlocked("the shared files", name, reason)));
        Form.Children.Add(FormBuilders.StringListEditor("Per-section folders", false,
            () => Config.PerSectionFolders, v => Config.PerSectionFolders = v, ChangedAndRedraw,
            name => { RecordExclusion(CourseConfiguration.PerSectionScope, "folder", name); NoticeAfterRemoval(name); },
            name => { RecordReInclusion(CourseConfiguration.PerSectionScope, "folder", name); CreateFolderForNewEntry(name, FolderScope.PerSection); },
            name => ItemProtectionRule.For(name, ItemList.PerSectionFolders, Protection()),
            (name, reason) => RecordRemovalBlocked("the per-section folders", name, reason),
            name => _ = OpenRenameFolderDialog(name, FolderScope.PerSection)));
        Form.Children.Add(FormBuilders.StringListEditor("Per-section files", true,
            () => Config.PerSectionFiles, v => Config.PerSectionFiles = v, ChangedAndRedraw,
            name => RecordExclusion(CourseConfiguration.PerSectionScope, "file", name),
            name => RecordReInclusion(CourseConfiguration.PerSectionScope, "file", name),
            name => ItemProtectionRule.For(name, ItemList.PerSectionFiles, Protection()),
            (name, reason) => RecordRemovalBlocked("the per-section files", name, reason)));
        Form.Children.Add(FormBuilders.ExampleCaption(
            "Tip: you can also simply create new folders in Obsidian — they're added to your site automatically the next time you preview. The exception is anything you remove here: it stays off your site, even if you make it again in Obsidian, until you add it back on this page."));

        // -------- Sidebar Visibility --------
        Form.Children.Add(FormBuilders.SectionHeaderWithCaption("Sidebar Visibility", null));
        Form.Children.Add(FormBuilders.MembershipToggleList("Hide from the site's sidebar",
            Config.AllSidebarItems, () => Config.HiddenItems, v => Config.HiddenItems = v, MarkChanged));
        Form.Children.Add(FormBuilders.MembershipToggleList("Expandable in the site's sidebar",
            Config.AllSidebarItems, () => Config.ExpandableItems, v => Config.ExpandableItems = v, MarkChanged));

        // -------- Marks --------
        // Which folders hold work that counts for marks. Before this key
        // existed the rule was hardcoded to any folder whose name CONTAINED
        // "task", so a teacher who called theirs "Tests", or renamed "Tasks",
        // silently lost every assessed mark on the coverage map.
        Form.Children.Add(FormBuilders.SectionHeaderWithCaption("Marks", null));
        Form.Children.Add(FormBuilders.ExampleCaption(
            "Tick the folders holding work that counts for marks. The Curriculum Coverage map shows an expectation as evaluated when a page in one of these addresses it."));
        Form.Children.Add(FormBuilders.MembershipToggleList("Folders that count for marks",
            // Not just the two top-level lists. The build counts a folder at
            // ANY depth, so a course with `Portfolios/Tasks` has assessed work
            // those lists never mention - and the first tick FREEZES the pool,
            // so a name this list failed to offer stops counting from that
            // moment, silently and for good.
            GradedFolderChoicesNow(),
            // Materialised on the way IN from that SAME pool, so a course that
            // has never been asked starts from what it was already counting
            // rather than from empty - a first tick must not take the marks off
            // every other folder whose name mentioned tasks. Offering a folder
            // this list did not also materialise would lose it just as quietly.
            MarksPool,
            v => Config.GradedFolders = v,
            // Ticking a SECOND folder is exactly what unblocks the first, and
            // it unblocks that folder's row in the lists above too.
            () => { MarkChanged(); RebuildProtectedRows(); },
            name => ItemProtectionRule.For(name, ItemList.GradedFolders, Protection()),
            (name, reason) => RecordRemovalBlocked("the marks list", name, reason)));

        // The marks list is where a teacher is first told that a folder's NAME
        // decides what the site does with it, so it is where they are most
        // likely to wonder what else is being read that way. Same placement as
        // the mac's, directly under this section's caption.
        Form.Children.Add(FoldersHelpButton());

        // -------- Per-section settings --------
        foreach (int section in Config.SectionNumbers)
            BuildSectionBlock(section);
    }

    private readonly System.Collections.Generic.Dictionary<int, TextBlock> _gradeWarningSlots = new();

    private void BuildSectionBlock(int section)
    {
        Form.Children.Add(FormBuilders.SectionHeaderWithCaption($"Section {section} Settings", null));

        Form.Children.Add(FormBuilders.EmojiChoiceField("Header emoji",
            () => Config.Emoji(section), v => Config.SetEmoji(section, v), MarkChanged));

        var marker = new ToggleSwitch { IsOn = Config.ShowsSectionMarker(section), OnContent = "", OffContent = "" };
        marker.Toggled += (_, _) => { Config.SetShowsSectionMarker(section, marker.IsOn); MarkChanged(); };
        var markerRow = FormBuilders.LabeledRow("Show section marker in the site title", marker);
        markerRow.Children.Add(FormBuilders.ExampleCaption($"e.g. \"S{section}\" appears beside the course code"));
        Form.Children.Add(markerRow);

        var grade = new ToggleSwitch { IsOn = Config.ShowsGradeInTitle(section), OnContent = "", OffContent = "" };
        var gradeRow = FormBuilders.LabeledRow("Show the grade in the site title", grade);
        var warningSlot = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap };
        gradeRow.Children.Add(warningSlot);
        _gradeWarningSlots[section] = warningSlot;
        grade.Toggled += (_, _) =>
        {
            Config.SetShowsGradeInTitle(section, grade.IsOn);
            MarkChanged();
            RebuildGradeWarnings();
        };
        Form.Children.Add(gradeRow);
        RefreshGradeWarning(section);

        // Colour scheme + swatch preview share one visual row.
        var schemes = ColourSchemeCatalog.Load(BundledToolchain.SupportPath("colour_schemes.json"));
        var schemeBox = new ComboBox { MinWidth = 320 };
        string currentScheme = Config.ColourSchemeId(section);
        int selectedIndex = -1;
        var schemeIds = new System.Collections.Generic.List<string>();
        if (currentScheme.Length == 0)
        {
            schemeBox.Items.Add("Quartz default (none chosen)");
            schemeIds.Add("");
            selectedIndex = 0;
        }
        foreach (var scheme in schemes)
        {
            schemeBox.Items.Add(scheme.Name);
            schemeIds.Add(scheme.Id);
            if (scheme.Id == currentScheme) selectedIndex = schemeIds.Count - 1;
        }
        schemeBox.SelectedIndex = Math.Max(selectedIndex, 0);
        var swatchRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        void RenderSwatches()
        {
            string id = schemeIds.ElementAtOrDefault(schemeBox.SelectedIndex) ?? "";
            var scheme = schemes.FirstOrDefault(s => s.Id == id);
            FormBuilders.FillSwatchRow(swatchRow, scheme?.SwatchValues ?? System.Array.Empty<string>());
        }
        RenderSwatches();
        schemeBox.SelectionChanged += (_, _) =>
        {
            string id = schemeIds.ElementAtOrDefault(schemeBox.SelectedIndex) ?? "";
            Config.SetColourSchemeId(section, id);
            MarkChanged();
            RenderSwatches();
        };
        var schemeRow = FormBuilders.LabeledRow("Colour scheme", schemeBox);
        schemeRow.Children.Add(FormBuilders.SampleBox(swatchRow));
        Form.Children.Add(schemeRow);

        BuildFontRows(section);

        // Advanced: the custom domain, collapsed by default. One field per
        // destination that can have a domain (never local_folder — a
        // domain is something a browser visits, and a folder is not).
        // Mirrors the mac's SectionSettingsView (row 307).
        var advanced = new Expander
        {
            Header = "Advanced",
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 8, 0, 0),
        };
        var domainDestinations = Config.AllDeployDestinations.Where(d => d.Type != "local_folder").ToList();
        var domainArea = new StackPanel { Spacing = 8 };
        foreach (var destination in domainDestinations)
        {
            string destinationType = destination.Type;
            string label = domainDestinations.Count > 1
                ? $"{DeployCommand.DestinationDescription(destination)} custom domain"
                : "Custom domain";
            string serviceName = DeployCommand.DestinationDescription(destination);

            var domainBox = new TextBox
            {
                Text = Config.CustomDomain(section, destinationType),
                IsSpellCheckEnabled = false,
            };
            var domainPanel = FormBuilders.LabeledRow(label, domainBox);
            var domainCaption = FormBuilders.ExampleCaption(
                $"e.g. ics3u.yourschool.ca — links to your live site will use this domain instead of the {serviceName} address. Your site must already answer there (set the domain up in {serviceName} first). Leave empty to use the {serviceName} address.");
            var domainWarning = FormBuilders.WarningCaption("That doesn't look like a domain — e.g. ics3u.yourschool.ca");
            domainWarning.Visibility = Visibility.Collapsed;
            domainPanel.Children.Add(domainWarning);
            domainPanel.Children.Add(domainCaption);
            domainBox.TextChanged += (_, _) =>
            {
                Config.SetCustomDomain(section, destinationType, domainBox.Text);
                MarkChanged();
                string entry = domainBox.Text.Trim();
                bool odd = entry.Length > 0 && (entry.Contains(' ') || !entry.Contains('.'));
                domainWarning.Visibility = odd ? Visibility.Visible : Visibility.Collapsed;
                domainCaption.Visibility = odd ? Visibility.Collapsed : Visibility.Visible;
            };
            domainArea.Children.Add(domainPanel);
        }
        advanced.Content = domainArea;
        Form.Children.Add(advanced);
    }

    private void BuildFontRows(int section)
    {
        var current = Config.Font(section);

        var pairingBox = new ComboBox { MinWidth = 320 };
        var pairings = FontCatalog.Pairings.ToList();
        int selected = pairings.FindIndex(p => p.Header == current.Header && p.Body == current.Body);
        foreach (var pairing in pairings)
            pairingBox.Items.Add(FontCatalog.PairingLabel(pairing.Header, pairing.Body));
        if (selected < 0)
        {
            pairingBox.Items.Add($"Custom: {current.Header} — {current.Body}");
            selected = pairings.Count;
        }
        pairingBox.SelectedIndex = selected;

        var headerSample = new TextBlock { Text = SampleHeaderText(section), FontSize = 19 };
        _fontSampleHeaders.Add((section, headerSample));
        var bodySample = new TextBlock { Text = "Body text on your site will look like this sentence does.", FontSize = 13 };
        var samplePanel = new StackPanel { Spacing = 4 };
        samplePanel.Children.Add(headerSample);
        samplePanel.Children.Add(bodySample);

        void ApplySampleFonts()
        {
            var choice = Config.Font(section);
            headerSample.FontFamily = FormBuilders.BundledFontFamily(choice.Header);
            bodySample.FontFamily = FormBuilders.BundledFontFamily(choice.Body);
        }
        ApplySampleFonts();

        pairingBox.SelectionChanged += (_, _) =>
        {
            if (pairingBox.SelectedIndex >= 0 && pairingBox.SelectedIndex < pairings.Count)
            {
                var pairing = pairings[pairingBox.SelectedIndex];
                var existing = Config.Font(section);
                Config.SetFont(section, new FontChoice(pairing.Header, pairing.Body, existing.Code));
                MarkChanged();
                ApplySampleFonts();
            }
        };
        var pairingRow = FormBuilders.LabeledRow("Header & body fonts", pairingBox);
        pairingRow.Children.Add(FormBuilders.SampleBox(samplePanel));
        Form.Children.Add(pairingRow);

        var codeBox = new ComboBox { MinWidth = 320 };
        var codeFonts = FontCatalog.CodeFonts.ToList();
        int codeSelected = codeFonts.IndexOf(current.Code);
        foreach (string font in codeFonts) codeBox.Items.Add(font);
        if (codeSelected < 0) { codeBox.Items.Add(current.Code); codeSelected = codeFonts.Count; }
        codeBox.SelectedIndex = codeSelected;
        var codeSample = new TextBlock
        {
            Text = "for number in range(10):  # code samples use this font",
            FontSize = 12,
            FontFamily = FormBuilders.BundledFontFamily(current.Code),
        };
        codeBox.SelectionChanged += (_, _) =>
        {
            if (codeBox.SelectedIndex >= 0 && codeBox.SelectedIndex < codeFonts.Count)
            {
                var existing = Config.Font(section);
                Config.SetFont(section, existing with { Code = codeFonts[codeBox.SelectedIndex] });
                MarkChanged();
                codeSample.FontFamily = FormBuilders.BundledFontFamily(codeFonts[codeBox.SelectedIndex]);
            }
        };
        var codeRow = FormBuilders.LabeledRow("Code font", codeBox);
        codeRow.Children.Add(FormBuilders.SampleBox(codeSample));
        Form.Children.Add(codeRow);
    }

    private void RebuildGradeWarnings()
    {
        foreach (int section in _gradeWarningSlots.Keys) RefreshGradeWarning(section);
    }

    private void RefreshGradeWarning(int section)
    {
        if (!_gradeWarningSlots.TryGetValue(section, out var slot)) return;
        string? warning = CourseConfiguration.GradeInTitleWarning(
            Config.CourseName, _course.Code, Config.ShowsGradeInTitle(section));
        if (warning is not null)
        {
            slot.Text = warning;
            slot.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
        }
        else
        {
            slot.Text = "e.g. \"Grade 12\" before the course name — applied the next time this section builds";
            slot.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        }
    }

    // ---- Buttons ---------------------------------------------------------

    private void Revert_Click(object sender, RoutedEventArgs e)
    {
        Config.DiscardChanges();
        BuildForm();
        RefreshDirtyState();
        HeaderName.Text = Config.CourseName;
    }

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Config.Write(_course.ConfigFilePath);
            RefreshDirtyState();
            // The mac's wording, so the two trails read the same. Declared
            // when the trail was built and emitted by nobody until 2026-09-07.
            ActivityTrail.Note(ActivityTrail.Event.SettingsSaved,
                "saved the settings for " + _course.Code);
            SaveStatus.Text = "Saved ✓";
            SaveStatus.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
            await Task.Delay(3000);
            SaveStatus.Text = "";
        }
        catch (Exception error)
        {
            // The exception's message can carry a path under the teacher's
            // home folder; LogRedactor redacts on the way IN
            // (windowsHomeFolder, pinned by problemReportRedaction case 2).
            // Its one known limit is pre-existing and shared with every other
            // line: an account name with a space in it loses only its first
            // word.
            ActivityTrail.Note(ActivityTrail.Event.SettingsCouldNotBeSaved,
                "could not save the settings for " + _course.Code + " — " + error.Message);
            SaveStatus.Text = $"Could not save: {error.Message}";
            SaveStatus.Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];
        }
    }

    private void Obsidian_Click(object sender, RoutedEventArgs e) =>
        _ = FolderActions.OpenInObsidian(_course.DirectoryPath, _course.DirectoryPath,
            BundledToolchain.SupportPath("obsidian_defaults/.obsidian"));
}
