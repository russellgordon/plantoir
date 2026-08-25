using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
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
    /// the build to skip. Worse, if it was the only entry the course is left
    /// with a non-empty pool matching nothing on disk, which reads as "asked
    /// and answered" and suppresses the `noGradedFolders` warning. This is the
    /// mac's row 380 correction (3), ported rather than rediscovered.</para>
    ///
    /// <para>Materialised first, so a legacy course whose pool has never been
    /// set does not get one CREATED as an empty list by a removal -- that
    /// would silently switch it from the historical substring rule to "nothing
    /// counts".</para>
    /// </summary>
    private void DropFromMarksPool(string name)
    {
        var pool = Config.MaterializedGradedFolders();
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
    /// A teacher pressed the info button on a row that cannot go. Record which
    /// rule refused, and the sentence they were shown.
    ///
    /// <para>"I could not remove the folder" is a report support WILL receive,
    /// and without this the trail shows nothing at all - the teacher clicked a
    /// button and no state changed. The sentence is a specialNames one, so it
    /// is product wording rather than anything written on a page.</para>
    /// </summary>
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

    private void RecordRemovalBlocked(string list, string name, string reason)
    {
        ActivityTrail.Note(ActivityTrail.Event.RemovalBlocked,
            $"{_course.Code}: could not remove \u201C{name}\u201D from {list} - {reason}");
    }

    /// <summary>
    /// Everything the protection rules need, read fresh at the moment a row is
    /// drawn or a box is ticked.
    ///
    /// <para>Never cached: ticking a SECOND graded folder is exactly what
    /// unblocks the first, and turning the coverage map off unblocks the
    /// curriculum folder. A captured answer would go on refusing.</para>
    /// </summary>
    private ProtectionContext Protection() => new(
        InWizard: false,
        CurriculumCoverageEnabled: Config.OverallIncludesCurriculumCoverage,
        // Course Settings has no curriculum-PAGES switch - that choice is made
        // once, in the wizard - so it can never be the reason here.
        CurriculumPagesEnabled: false,
        Jurisdiction: SpecialNames.DefaultJurisdiction,
        ResolvedCurriculumFolder: Config.ResolvedCurriculumFolder,
        GradedFolders: Config.MaterializedGradedFolders(),
        PerSectionFolders: Config.PerSectionFolders);

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
            () => Config.SharedFolders, v => Config.SharedFolders = v, MarkChanged,
            name => RecordExclusion(CourseConfiguration.SharedScope, "folder", name),
            name => RecordReInclusion(CourseConfiguration.SharedScope, "folder", name),
            name => ItemProtectionRule.For(name, ItemList.SharedFolders, Protection()),
            (name, reason) => RecordRemovalBlocked("the shared folders", name, reason)));
        Form.Children.Add(FormBuilders.StringListEditor("Shared files (all sections)", true,
            () => Config.SharedFiles, v => Config.SharedFiles = v, MarkChanged,
            name => RecordExclusion(CourseConfiguration.SharedScope, "file", name),
            name => RecordReInclusion(CourseConfiguration.SharedScope, "file", name),
            name => ItemProtectionRule.For(name, ItemList.SharedFiles, Protection()),
            (name, reason) => RecordRemovalBlocked("the shared files", name, reason)));
        Form.Children.Add(FormBuilders.StringListEditor("Per-section folders", false,
            () => Config.PerSectionFolders, v => Config.PerSectionFolders = v, MarkChanged,
            name => RecordExclusion(CourseConfiguration.PerSectionScope, "folder", name),
            name => RecordReInclusion(CourseConfiguration.PerSectionScope, "folder", name),
            name => ItemProtectionRule.For(name, ItemList.PerSectionFolders, Protection()),
            (name, reason) => RecordRemovalBlocked("the per-section folders", name, reason)));
        Form.Children.Add(FormBuilders.StringListEditor("Per-section files", true,
            () => Config.PerSectionFiles, v => Config.PerSectionFiles = v, MarkChanged,
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
            Config.SharedFolders.Concat(Config.PerSectionFolders).ToList(),
            // Materialised on the way IN, so a course that has never been asked
            // starts from what it was already counting rather than from empty -
            // a first tick must not take the marks off every other folder whose
            // name mentioned tasks.
            () => Config.MaterializedGradedFolders(),
            v => Config.GradedFolders = v,
            // Ticking a SECOND folder is exactly what unblocks the first, and
            // it unblocks that folder's row in the lists above too.
            () => { MarkChanged(); RebuildProtectedRows(); },
            name => ItemProtectionRule.For(name, ItemList.GradedFolders, Protection()),
            (name, reason) => RecordRemovalBlocked("the marks list", name, reason)));

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
            SaveStatus.Text = "Saved ✓";
            SaveStatus.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
            await Task.Delay(3000);
            SaveStatus.Text = "";
        }
        catch (Exception error)
        {
            SaveStatus.Text = $"Could not save: {error.Message}";
            SaveStatus.Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];
        }
    }

    private void Obsidian_Click(object sender, RoutedEventArgs e) =>
        _ = FolderActions.OpenInObsidian(_course.DirectoryPath, _course.DirectoryPath,
            BundledToolchain.SupportPath("obsidian_defaults/.obsidian"));
}
