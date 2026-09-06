using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// The New Course or Club wizard. The form collects the teacher's choices;
/// Create writes them as course_config.json and runs the REAL setup
/// launcher, whose prompts are answered with their now-correct defaults.
/// A "New to this?" panel installs the complete example course instead.
/// </summary>
public sealed class NewCourseDialog : ContentDialog
{
    public string? CreatedCourseCode { get; private set; }
    public bool CreatedIsExample { get; private set; }

    private readonly MainWindow _window;
    private readonly NewCourseCreator _creator;
    private readonly TaskProgressView _progress = new();

    // A searchable picker, not a plain field: matches the mac wizard's own
    // course-code combo box (contracts don't cover this — it's visual, see
    // WINDOWS-HANDOFF.md "The course-code picker is a hand-built combo box").
    // WinUI's AutoSuggestBox draws a rich per-row template natively, which is
    // exactly the thing the mac had to hand-build NSComboBox's replacement
    // for — so the real control is used here rather than a custom flyout.
    private readonly AutoSuggestBox _codeBox = new()
    {
        PlaceholderText = "e.g. ICS3U",
        TextMemberPath = "Code",
    };

    // Which province's catalog the picker searches — narrows the SUGGESTION
    // list only, the same way the mac's segmented Province picker does; it
    // never gates typing a code straight through, since a club code or a
    // code from neither list is still perfectly valid.
    private readonly ComboBox _provinceBox = new() { MinWidth = 220 };
    private string _province = "ON";

    private readonly TextBlock _codeWarning;
    private readonly TextBox _nameBox = new();
    private readonly TextBox _shortBox = new() { MaxLength = 12 };
    private readonly StackPanel _shortRow;
    private readonly TextBox _sectionsBox = new() { Text = "1" };
    // What this course calls a unit. Asked of EVERY course, ready-made ones
    // included: a payload is poured in the teacher's word rather than renamed
    // afterwards, because renaming a course already in use means rewriting
    // every wikilink to every renamed page, and a half-finished pass leaves a
    // broken site with no way back.
    private readonly TextBox _unitWordBox = new() { PlaceholderText = ClassPageTerm.DefaultWord };
    private readonly TextBlock _unitWordCaption = FormBuilders.ExampleCaption(
        ClassPageTerm.Caption(null));
    private readonly TextBlock _unitWordWarning = FormBuilders.WarningCaption("");
    private readonly TextBlock _sectionsCaption;
    private readonly ComboBox _localeBox = new() { MinWidth = 300 };
    private readonly StackPanel _suggestionsRow = new() { Spacing = 4, Visibility = Visibility.Collapsed };
    private readonly TextBlock _validationText;
    private readonly ScrollViewer _formScroll;
    private readonly StackPanel _root;

    private string _emoji = WizardDefaults.DefaultEmoji;
    private string _schemeId = WizardDefaults.DefaultColourSchemeId;
    private bool _showsMarker = true;
    private bool _showsGrade = true;
    private bool _expandOnFolderClick;
    private bool _showReadingTime;
    private string _footerHtml = "";
    private FontChoice _fontChoice = FontChoice.SystemDefault;
    private List<string> _sharedFolders = WizardDefaults.SharedFolders.ToList();
    private List<string> _sharedFiles = WizardDefaults.SharedFiles.ToList();
    private List<string> _perSectionFolders = WizardDefaults.PerSectionFolders.ToList();
    private List<string> _perSectionFiles = WizardDefaults.PerSectionFiles.ToList();

    /// <summary>
    /// Which of this course's folders will count for marks, written to
    /// `graded_folders` on Create.
    ///
    /// <para>Null until the Marks list is first built, then reconciled against
    /// the folder lists on every rebuild - a name the teacher removes from the
    /// structure must not survive in the pool, which is the wizard half of
    /// `setup_course.py:graded_folders_for`.</para>
    /// </summary>
    private List<string>? _gradedFolders;
    private string _lastAutoFilledName = "";
    private readonly CourseNameCatalog _nameCatalog;
    private readonly TextBlock _gradeWarningSlot;
    private bool _started;

    // Starting Content (rows 92–94, 130): the ready-made pages and their
    // toggles, plus the terminology switch for the factory structure.
    private bool _prepopulate = true;
    private bool _includeCurriculum = true;
    private bool _includeCurriculumCoverage = true;
    private bool _includeCoverageNotes = true;
    private bool _useLcs;

    // Publishing (rows 101–102): Netlify by default, or a folder on this PC.
    private string _deployTarget = "netlify";
    private string _deployFolderPath = "";
    private List<CourseConfiguration.AdditionalDeployTarget> _additionalDeployTargets = new();
    private PublishingChoiceView? _publishingChoice;
    private readonly StackPanel _startingContentBody = new() { Spacing = 6 };
    private readonly TextBlock _structureCaption;
    private readonly TextBlock _structureLockedNote;
    private readonly StackPanel _structureEditorArea = new() { Spacing = 6 };
    private readonly StackPanel _marksArea = new() { Spacing = 4, Margin = new Thickness(0, 12, 0, 0) };
    private readonly Expander _structureExpander = new()
    {
        Header = "Folders and files",
        HorizontalAlignment = HorizontalAlignment.Stretch,
        HorizontalContentAlignment = HorizontalAlignment.Stretch,
    };

    /// <summary>
    /// The font sample shows the course's OWN site title once there is one —
    /// computed exactly as the build will compute it, so the grade and
    /// section-marker switches are reflected too. The stand-in remains for
    /// the blank-form moment only.
    /// </summary>
    private TextBlock? _fontSampleHeader;

    private string SampleHeaderText()
    {
        if (_nameBox.Text.Trim().Length == 0 && _codeBox.Text.Trim().Length == 0)
            return "Grade 11 Computer Science";
        int firstSection = ParsedSectionNumbers(_sectionsBox.Text).FirstOrDefault();
        if (firstSection == 0) firstSection = 1;
        return CourseConfiguration.ComputedSiteTitle(
            _nameBox.Text, _codeBox.Text, firstSection, _showsGrade, _showsMarker);
    }

    private void RefreshFontSample()
    {
        if (_fontSampleHeader is not null) _fontSampleHeader.Text = SampleHeaderText();
    }

    private static string ExampleContentRoot => BundledToolchain.SupportPath("example_content");
    private string NormalizedCode => _codeBox.Text.Trim().ToUpperInvariant();

    /// <summary>
    /// True when the example content, not the teacher, decides the course's
    /// folders and files — the pages were written for one exact layout, and
    /// a hand-edited structure would strand their links.
    /// </summary>
    private bool StructureComesFromExampleContent =>
        _prepopulate && ExampleContentCatalog.HasContent(ExampleContentRoot, NormalizedCode);

    public NewCourseDialog(MainWindow window)
    {
        _window = window;
        _creator = new NewCourseCreator(new ScriptRunner(System.Threading.SynchronizationContext.Current));
        _nameCatalog = CourseNameCatalogs.Shared;
        _codeBox.ItemTemplate = BuildCodeSuggestionTemplate();
        // AutoSuggestBox does NOT write the chosen row's text into Text by
        // itself once a custom ItemTemplate is in play — TextMemberPath only
        // controls the box's own (unused, since we template it) default
        // rendering. Without this, clicking or arrowing-to-and-pressing-Enter
        // on a suggestion does nothing: the typed search text stays put and
        // none of the downstream refreshes (name auto-fill, club row, grade
        // warning...) ever see the picked code.
        _codeBox.SuggestionChosen += (sender, args) =>
        {
            if (args.SelectedItem is CourseCodeSuggestion chosen) sender.Text = chosen.Code;
        };

        Title = "New Course or Club";
        PrimaryButtonText = "Create Course";
        CloseButtonText = "Cancel";
        DefaultButton = ContentDialogButton.Primary;
        PrimaryButtonClick += OnPrimaryButton;
        CloseButtonClick += OnCloseButton;

        _validationText = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"],
            Visibility = Visibility.Collapsed,
        };
        _sectionsCaption = FormBuilders.ExampleCaption("e.g. 1,3 — comma-separated");
        _codeWarning = new TextBlock
        {
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed,
            Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
        };
        _gradeWarningSlot = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
        _structureCaption = FormBuilders.ExampleCaption("Defaults are fine for most courses");
        _structureLockedNote = FormBuilders.ExampleCaption(
            "The example content chooses the folders and files for this course, so every page lands where its links expect it. Turn off pre-populating to choose your own structure.");
        _structureLockedNote.Visibility = Visibility.Collapsed;
        AutomationProperties.SetAutomationId(_structureLockedNote, "structureFromExampleNote");
        _shortRow = FormBuilders.LabeledRow("Short label beside emoji (≤ 12 characters)", _shortBox);
        _shortRow.Visibility = Visibility.Collapsed;

        // Pin the whole dialog to a fixed width so the form and the progress
        // view share the same size and the "Step x of y" label can't be
        // clipped off the right edge (issue 3). ContentDialog width is driven
        // by these theme resources, not by the content's own Width.
        Resources["ContentDialogMinWidth"] = 600.0;
        Resources["ContentDialogMaxWidth"] = 600.0;
        _root = new StackPanel { Spacing = 8 };
        _formScroll = new ScrollViewer
        {
            Content = BuildForm(),
            MaxHeight = 520,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollMode = ScrollMode.Disabled,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        _progress.HorizontalAlignment = HorizontalAlignment.Stretch;
        _root.Children.Add(_formScroll);
        _root.Children.Add(_validationText);
        Content = _root;
        RefreshCreateEnabled();
    }

    /// <summary>Smoke-test entry: fill the code (and optional sections) and press Create.</summary>
    public void AutoCreate(string code, string? sections = null)
    {
        _codeBox.Text = code;
        if (sections is not null) _sectionsBox.Text = sections;
        Opened += (_, _) => _ = StartCreation();
    }

    /// <summary>
    /// Fill the panel in for a marketing capture, as though a teacher had
    /// typed it.
    ///
    /// The refreshes are called by hand rather than left to TextChanged. The
    /// capturer stages this dialog before its content is ever in a live visual
    /// tree, and a TextBox that has not been templated yet takes a programmatic
    /// Text without raising the event — so the panel photographed with an empty
    /// Course name and no suggested names beneath it, for a code the catalog
    /// knows perfectly well. Nothing is wrong for a teacher, whose typing goes
    /// into a loaded control; this hook simply cannot rely on that.
    /// </summary>
    public void StageForCapture(string code, string? sections = null)
    {
        _codeBox.Text = code;
        AutoFillCourseName();
        RefreshClubRow();
        RefreshGradeWarning();
        RefreshCodeValidation();
        RefreshStartingContent();
        RefreshStructureArea();

        if (sections is not null)
        {
            _sectionsBox.Text = sections;
            RefreshSectionsValidation();
        }

        RefreshFontSample();
        RefreshCreateEnabled();
    }

    /// <summary>
    /// The Create button stays disabled until there is enough to make a course:
    /// a spaceless, non-duplicate code and a valid section-numbers list (issue 2).
    /// </summary>
    private void RefreshCreateEnabled()
    {
        if (_started) return;   // once running, the affirmative button becomes "Close"
        bool codeOk = _codeBox.Text.Trim().Length > 0 && CourseCodeProblem() is null;
        bool sectionsOk = SectionNumbersProblem(_sectionsBox.Text) is null;
        bool publishingOk = _publishingChoice?.Problem is null;   // a bad folder blocks Create (row 102)
        IsPrimaryButtonEnabled = codeOk && sectionsOk && publishingOk && UnitWordIsUsable;
    }

    /// <summary>
    /// Why the typed code can't be used — invalid characters, too long, or a
    /// clash with an existing course. Null means the code is fine (or still
    /// empty, which is simply not-ready-yet, not an error worth showing).
    /// Delegates to CourseCodeValidator, the shared rule both the wizard and
    /// course renaming must agree on (contracts/course-management.json ->
    /// courseCode.problems).
    /// </summary>
    private string? CourseCodeProblem() =>
        CourseCodeValidator.Problem(_codeBox.Text, _window.Workspace.Courses.Select(c => c.Code));

    /// <summary>
    /// Explain the blocker next to the field, so a greyed-out Create button is
    /// never a mystery — a duplicate code is the usual reason a filled-in form
    /// still won't submit.
    /// </summary>
    private void RefreshCodeValidation()
    {
        string? problem = CourseCodeProblem();
        _codeWarning.Text = problem ?? "";
        _codeWarning.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
    }

    // ---- Form ------------------------------------------------------------

    private StackPanel BuildForm()
    {
        var form = new StackPanel { Spacing = 6 };

        // "New to this?" — a finished course teaches more than an empty form.
        // Stacked vertically so the button never clips at any dialog width.
        var invitation = new StackPanel { Spacing = 8, Padding = new Thickness(12) };
        invitation.Children.Add(new TextBlock { Text = "New to this?", FontWeight = FontWeights.SemiBold });
        invitation.Children.Add(new TextBlock
        {
            Text = "Add a complete example course — a real Grade 9 science course you can explore, change, and remove whenever you like.",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Opacity = 0.7,
        });
        var exampleButton = new Button { Content = "Add Example Course", HorizontalAlignment = HorizontalAlignment.Left };
        exampleButton.Click += (_, _) => _ = StartExampleInstall();
        invitation.Children.Add(exampleButton);
        form.Children.Add(new Border
        {
            Child = invitation,
            Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            CornerRadius = new CornerRadius(8),
        });

        // -------- Basics --------
        form.Children.Add(FormBuilders.SectionHeaderWithCaption("Basics", null));

        _provinceBox.Items.Add("Ontario");
        _provinceBox.Items.Add("British Columbia");
        _provinceBox.SelectedIndex = 0;   // Ontario — the more common case, so nothing is disabled before a teacher has touched the form
        _provinceBox.SelectionChanged += (_, _) =>
        {
            _province = _provinceBox.SelectedIndex == 1 ? "BC" : "ON";
            RefreshCodeSuggestions();
        };
        var provinceRow = FormBuilders.LabeledRow("Province", _provinceBox);
        provinceRow.Children.Add(FormBuilders.ExampleCaption("Narrows the course-code search below — typing a code straight through still works either way"));
        form.Children.Add(provinceRow);

        var codeRow = FormBuilders.LabeledRow("Course code", _codeBox);
        codeRow.Children.Add(FormBuilders.ExampleCaption(
            "e.g. ICS3U — or a club name like CODING. Start typing to search known course codes and names."));
        codeRow.Children.Add(_codeWarning);
        form.Children.Add(codeRow);
        _codeBox.TextChanged += (_, args) =>
        {
            if (args.Reason == AutoSuggestionBoxTextChangeReason.UserInput) RefreshCodeSuggestions();
            AutoFillCourseName(); RefreshClubRow(); RefreshGradeWarning(); RefreshCodeValidation(); RefreshCreateEnabled();
            RefreshStartingContent(); RefreshStructureArea(); RefreshFontSample();
        };

        var nameRow = FormBuilders.LabeledRow("Course name", _nameBox);
        nameRow.Children.Add(FormBuilders.ExampleCaption("e.g. Introduction to Computer Science"));
        nameRow.Children.Add(_suggestionsRow);
        form.Children.Add(nameRow);
        _nameBox.TextChanged += (_, _) => { RefreshGradeWarning(); RefreshFontSample(); };

        form.Children.Add(_shortRow);

        var sectionsRow = FormBuilders.LabeledRow("Timetable section numbers", _sectionsBox);
        sectionsRow.Children.Add(_sectionsCaption);
        form.Children.Add(sectionsRow);
        _sectionsBox.TextChanged += (_, _) => { RefreshSectionsValidation(); RefreshCreateEnabled(); RefreshFontSample(); };

        var unitWordRow = FormBuilders.LabeledRow("What do you call a unit?", _unitWordBox);
        unitWordRow.Children.Add(_unitWordCaption);
        unitWordRow.Children.Add(_unitWordWarning);
        form.Children.Add(unitWordRow);
        _unitWordBox.TextChanged += (_, _) => { RefreshUnitWord(); RefreshCreateEnabled(); };
        RefreshUnitWord();

        foreach (string code in LocaleCatalog.Codes) _localeBox.Items.Add(LocaleCatalog.DisplayName(code));
        _localeBox.SelectedIndex = LocaleCatalog.Codes.ToList().IndexOf(WizardDefaults.DefaultLocale);
        form.Children.Add(FormBuilders.LabeledRow("Language / region", _localeBox));

        // -------- Starting Content (offered per course code) --------
        form.Children.Add(FormBuilders.SectionHeaderWithCaption("Starting Content", null));
        form.Children.Add(_startingContentBody);
        RefreshStartingContent();

        // -------- Appearance --------
        form.Children.Add(FormBuilders.SectionHeaderWithCaption("Appearance",
            "Applied to every section — fine-tune later in Settings"));
        form.Children.Add(FormBuilders.EmojiChoiceField("Header emoji",
            () => _emoji, v => _emoji = v, () => { }));

        var schemes = ColourSchemeCatalog.Load(BundledToolchain.SupportPath("colour_schemes.json"));
        var schemeBox = new ComboBox { MinWidth = 300 };
        int schemeIndex = 0;
        for (int i = 0; i < schemes.Count; i++)
        {
            schemeBox.Items.Add(schemes[i].Name);
            if (schemes[i].Id == _schemeId) schemeIndex = i;
        }
        schemeBox.SelectedIndex = schemes.Count > 0 ? schemeIndex : -1;
        var swatchRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        void RenderSchemeSwatches()
        {
            var scheme = schemes.FirstOrDefault(s => s.Id == _schemeId);
            FormBuilders.FillSwatchRow(swatchRow, scheme?.SwatchValues ?? Array.Empty<string>());
        }
        RenderSchemeSwatches();
        schemeBox.SelectionChanged += (_, _) =>
        {
            if (schemeBox.SelectedIndex >= 0) { _schemeId = schemes[schemeBox.SelectedIndex].Id; RenderSchemeSwatches(); }
        };
        var schemeRow = FormBuilders.LabeledRow("Colour scheme", schemeBox);
        schemeRow.Children.Add(FormBuilders.SampleBox(swatchRow));
        form.Children.Add(schemeRow);

        var pairings = FontCatalog.Pairings.ToList();
        var pairingBox = new ComboBox { MinWidth = 300 };
        foreach (var pairing in pairings)
            pairingBox.Items.Add(FontCatalog.PairingLabel(pairing.Header, pairing.Body));
        pairingBox.SelectedIndex = pairings.Count - 1;   // system default
        _fontSampleHeader = new TextBlock { Text = SampleHeaderText(), FontSize = 19 };
        var headerSample = _fontSampleHeader;
        var bodySample = new TextBlock { Text = "Body text on your site will look like this sentence does.", FontSize = 13 };
        var fontSample = new StackPanel { Spacing = 4 };
        fontSample.Children.Add(headerSample);
        fontSample.Children.Add(bodySample);
        void ApplyFontSample()
        {
            headerSample.FontFamily = FormBuilders.BundledFontFamily(_fontChoice.Header);
            bodySample.FontFamily = FormBuilders.BundledFontFamily(_fontChoice.Body);
        }
        ApplyFontSample();
        pairingBox.SelectionChanged += (_, _) =>
        {
            if (pairingBox.SelectedIndex >= 0)
            {
                var pairing = pairings[pairingBox.SelectedIndex];
                _fontChoice = _fontChoice with { Header = pairing.Header, Body = pairing.Body };
                ApplyFontSample();
            }
        };
        var pairingRow = FormBuilders.LabeledRow("Header & body fonts", pairingBox);
        pairingRow.Children.Add(FormBuilders.SampleBox(fontSample));
        form.Children.Add(pairingRow);

        var codeFonts = FontCatalog.CodeFonts.ToList();
        var codeFontBox = new ComboBox { MinWidth = 300 };
        foreach (string font in codeFonts) codeFontBox.Items.Add(font);
        codeFontBox.SelectedIndex = codeFonts.IndexOf(_fontChoice.Code);
        var codeSample = new TextBlock
        {
            Text = "for number in range(10):  # code samples use this font",
            FontSize = 12,
            FontFamily = FormBuilders.BundledFontFamily(_fontChoice.Code),
        };
        codeFontBox.SelectionChanged += (_, _) =>
        {
            if (codeFontBox.SelectedIndex >= 0)
            {
                _fontChoice = _fontChoice with { Code = codeFonts[codeFontBox.SelectedIndex] };
                codeSample.FontFamily = FormBuilders.BundledFontFamily(codeFonts[codeFontBox.SelectedIndex]);
            }
        };
        var codeFontRow = FormBuilders.LabeledRow("Code font", codeFontBox);
        codeFontRow.Children.Add(FormBuilders.SampleBox(codeSample));
        form.Children.Add(codeFontRow);

        var markerToggle = new ToggleSwitch { IsOn = _showsMarker, OnContent = "", OffContent = "" };
        markerToggle.Toggled += (_, _) => { _showsMarker = markerToggle.IsOn; RefreshFontSample(); };
        var markerRow = FormBuilders.LabeledRow("Show section marker in the site title", markerToggle);
        markerRow.Children.Add(FormBuilders.ExampleCaption("e.g. \"S1\" appears beside the course code"));
        form.Children.Add(markerRow);

        var gradeToggle = new ToggleSwitch { IsOn = _showsGrade, OnContent = "", OffContent = "" };
        gradeToggle.Toggled += (_, _) => { _showsGrade = gradeToggle.IsOn; RefreshGradeWarning(); RefreshFontSample(); };
        var gradeRow = FormBuilders.LabeledRow("Show the grade in the site title", gradeToggle);
        gradeRow.Children.Add(_gradeWarningSlot);
        gradeRow.Children.Add(FormBuilders.ExampleCaption("e.g. \"Grade 12\" before the course name"));
        form.Children.Add(gradeRow);

        // -------- Behaviour --------
        form.Children.Add(FormBuilders.SectionHeaderWithCaption("Behaviour", null));
        var expandBox = new ComboBox { MinWidth = 300 };
        expandBox.Items.Add("Chevron or folder name");
        expandBox.Items.Add("Chevron only (name opens the folder)");
        expandBox.SelectedIndex = _expandOnFolderClick ? 0 : 1;
        expandBox.SelectionChanged += (_, _) => _expandOnFolderClick = expandBox.SelectedIndex == 0;
        form.Children.Add(FormBuilders.LabeledRow("Sidebar folders expand when clicking", expandBox));

        var readTimeToggle = new ToggleSwitch { IsOn = _showReadingTime, OnContent = "", OffContent = "" };
        readTimeToggle.Toggled += (_, _) => _showReadingTime = readTimeToggle.IsOn;
        form.Children.Add(FormBuilders.LabeledRow("Show page read-time estimates to students", readTimeToggle));

        // -------- Publishing --------
        form.Children.Add(FormBuilders.SectionHeaderWithCaption("Deploying", null));
        _publishingChoice = new PublishingChoiceView(_window,
            () => _deployTarget,
            v =>
            {
                _deployTarget = v;
                // A destination can never be both primary and additional at
                // once — the SAME guarantee CourseConfiguration.DeployTarget's
                // own setter gives an existing course, given live here since
                // this wizard's fields have no CourseConfiguration to route
                // through until Create is actually clicked.
                _additionalDeployTargets = CourseConfiguration.PruningAdditionalTargets(_additionalDeployTargets, v);
            },
            () => _deployFolderPath, v => _deployFolderPath = v,
            () => _window.Workspace.Settings.CloudflareAccountId,
            v => { _window.Workspace.Settings.CloudflareAccountId = v; _window.Workspace.Settings.Save(); },
            () => _additionalDeployTargets,
            v => _additionalDeployTargets = v.ToList());
        _publishingChoice.Changed += RefreshCreateEnabled;
        form.Children.Add(_publishingChoice.Root);

        // -------- Structure (long lists stay collapsed) --------
        var structureHeader = new StackPanel { Spacing = 2, Margin = new Thickness(0, 18, 0, 4) };
        structureHeader.Children.Add(new TextBlock { Text = "Structure", FontSize = 18, FontWeight = FontWeights.SemiBold });
        structureHeader.Children.Add(_structureCaption);
        form.Children.Add(structureHeader);
        form.Children.Add(_structureLockedNote);

        var lcsToggle = new ToggleSwitch { IsOn = _useLcs, OnContent = "", OffContent = "" };
        lcsToggle.Toggled += (_, _) =>
        {
            bool wasLcs = _useLcs;
            if (lcsToggle.IsOn == wasLcs) return;
            _useLcs = lcsToggle.IsOn;
            _sharedFolders = WizardDefaults.SwitchingFactoryItems(_sharedFolders,
                _useLcs ? WizardDefaults.LcsSharedFolders : WizardDefaults.SharedFolders,
                wasLcs ? WizardDefaults.LcsSharedFolders : WizardDefaults.SharedFolders);
            _sharedFiles = WizardDefaults.SwitchingFactoryItems(_sharedFiles,
                _useLcs ? WizardDefaults.LcsSharedFiles : WizardDefaults.SharedFiles,
                wasLcs ? WizardDefaults.LcsSharedFiles : WizardDefaults.SharedFiles);
            RebuildStructureLists();   // the editors re-read the swapped lists
        };
        AutomationProperties.SetAutomationId(lcsToggle, "lcsTerminologyToggle");
        var lcsRow = FormBuilders.LabeledRow("Use LCS-specific terminology", lcsToggle);
        lcsRow.Children.Add(FormBuilders.ExampleCaption(
            "e.g. “Grove Time” instead of “Extra Help”, plus the College Board Curriculum folder"));
        _structureEditorArea.Children.Add(lcsRow);
        AutomationProperties.SetAutomationId(_structureExpander, "structureDisclosure");
        _structureEditorArea.Children.Add(_structureExpander);
        // Marks sits OUTSIDE the "Folders and files" disclosure: a teacher who
        // never opens that expander still has to be able to say what counts.
        _structureEditorArea.Children.Add(_marksArea);
        RebuildStructureLists();
        form.Children.Add(_structureEditorArea);
        RefreshStructureArea();

        // -------- Footer --------
        form.Children.Add(FormBuilders.SectionHeaderWithCaption("Footer", null));
        form.Children.Add(FormBuilders.ExampleCaption(
            "Optional: type or paste HTML below to appear at the bottom of every page on your site — many teachers use a Creative Commons licence notice. Leave the box empty for no footer."));
        var footerBox = new TextBox
        {
            AcceptsReturn = true,
            MinHeight = 60,
            FontFamily = new FontFamily("Consolas"),
            PlaceholderText = "For example: This site is licensed under <a href=\"…\">CC BY 4.0</a>.",
        };
        footerBox.TextChanged += (_, _) => _footerHtml = footerBox.Text;
        form.Children.Add(footerBox);

        return form;
    }

    // ---- Starting content and structure ----------------------------------

    /// <summary>
    /// The Starting Content section follows the typed course code: the two
    /// toggles when a bundled payload exists for it, a quiet note when none
    /// does yet. Rebuilt on every code change; toggle values survive.
    /// </summary>
    private void RefreshStartingContent()
    {
        _startingContentBody.Children.Clear();
        if (ExampleContentCatalog.HasContent(ExampleContentRoot, NormalizedCode))
        {
            var prepopToggle = new ToggleSwitch { IsOn = _prepopulate, OnContent = "", OffContent = "" };
            AutomationProperties.SetAutomationId(prepopToggle, "prepopulateToggle");
            var prepopRow = FormBuilders.LabeledRow("Pre-populate course with example content", prepopToggle);
            prepopRow.Children.Add(FormBuilders.ExampleCaption(
                "Working pages written for this course — keep, edit, or delete them as you build your own site. The example content also chooses the course's folders and files, so they fit the pages."));
            _startingContentBody.Children.Add(prepopRow);

            ToggleSwitch? curriculumToggle = null;
            ToggleSwitch? coverageToggle = null;
            ToggleSwitch? coverageNotesToggle = null;

            if (ExampleContentCatalog.IncludesCurriculum(ExampleContentRoot, NormalizedCode))
            {
                curriculumToggle = new ToggleSwitch
                {
                    IsOn = _includeCurriculum,
                    IsEnabled = _prepopulate,
                    OnContent = "",
                    OffContent = "",
                };
                AutomationProperties.SetAutomationId(curriculumToggle, "curriculumToggle");
                // Named by SpecialNames.CurriculumFolderBlockedByCurriculumPages,
                // so the label has to be built the same way the sentence is -
                // and it is per-province, because a BC teacher told to turn off
                // "Include Ontario curriculum pages" has no such switch.
                var curriculumRow = FormBuilders.LabeledRow(
                    SpecialNames.CurriculumPagesSwitchLabel(JurisdictionForCode()), curriculumToggle);
                curriculumRow.Children.Add(FormBuilders.ExampleCaption(
                    "Every expectation as its own page, so lessons and tasks can link to exactly what they address"));
                _startingContentBody.Children.Add(curriculumRow);

                coverageToggle = new ToggleSwitch
                {
                    IsOn = _includeCurriculumCoverage,
                    IsEnabled = _prepopulate && _includeCurriculum,
                    OnContent = "",
                    OffContent = "",
                };
                AutomationProperties.SetAutomationId(coverageToggle, "curriculumCoverageToggle");
                // Named by SpecialNames.CurriculumFolderBlockedByCoverageMap and
                // LastGradedFolderBlockedWizard - see the note in CourseSettingsView.
                var coverageRow = FormBuilders.LabeledRow(SpecialNames.CoverageSwitchLabelInWizard, coverageToggle);
                coverageRow.Children.Add(FormBuilders.ExampleCaption(
                    "Generates a page showing which specific and overall expectations are addressed"));
                _startingContentBody.Children.Add(coverageRow);

                coverageNotesToggle = new ToggleSwitch
                {
                    IsOn = _includeCoverageNotes,
                    IsEnabled = _prepopulate && _includeCurriculum && _includeCurriculumCoverage,
                    OnContent = "",
                    OffContent = "",
                };
                AutomationProperties.SetAutomationId(coverageNotesToggle, "curriculumCoverageNotesToggle");
                var coverageNotesRow = FormBuilders.LabeledRow("Include explanations on Curriculum Coverage page", coverageNotesToggle);
                coverageNotesRow.Children.Add(FormBuilders.ExampleCaption(
                    "Shows “What counts” and “Reading it honestly” sections on the page"));
                _startingContentBody.Children.Add(coverageNotesRow);

                curriculumToggle.Toggled += (_, _) =>
                {
                    _includeCurriculum = curriculumToggle.IsOn;
                    RebuildFolderEditors();
                    if (coverageToggle is not null)
                    {
                        coverageToggle.IsEnabled = _prepopulate && _includeCurriculum;
                        if (!_includeCurriculum) coverageToggle.IsOn = false;
                    }
                    if (coverageNotesToggle is not null)
                    {
                        coverageNotesToggle.IsEnabled = _prepopulate && _includeCurriculum && _includeCurriculumCoverage;
                        if (!_includeCurriculum) coverageNotesToggle.IsOn = false;
                    }
                };

                coverageToggle.Toggled += (_, _) =>
                {
                    _includeCurriculumCoverage = coverageToggle.IsOn;
                    // Named by two of the blocked sentences, so the rows have
                    // to be redrawn against the new answer.
                    RebuildFolderEditors();
                    if (coverageNotesToggle is not null)
                    {
                        coverageNotesToggle.IsEnabled = _prepopulate && _includeCurriculum && _includeCurriculumCoverage;
                        if (!_includeCurriculumCoverage) coverageNotesToggle.IsOn = false;
                    }
                };

                coverageNotesToggle.Toggled += (_, _) =>
                {
                    _includeCoverageNotes = coverageNotesToggle.IsOn;
                };
            }

            prepopToggle.Toggled += (_, _) =>
            {
                _prepopulate = prepopToggle.IsOn;
                RebuildFolderEditors();
                if (curriculumToggle is not null) curriculumToggle.IsEnabled = _prepopulate;
                if (coverageToggle is not null) coverageToggle.IsEnabled = _prepopulate && _includeCurriculum;
                if (coverageNotesToggle is not null) coverageNotesToggle.IsEnabled = _prepopulate && _includeCurriculum && _includeCurriculumCoverage;
                RefreshStructureArea();
            };
        }
        else
        {
            var note = FormBuilders.ExampleCaption(
                "Example content isn’t available for this course code yet, so the course will start with empty folders ready for your own pages.");
            AutomationProperties.SetAutomationId(note, "noExampleContentNote");
            _startingContentBody.Children.Add(note);
        }
    }

    /// <summary>
    /// Pre-populating LOCKS the structure: the editor (and the terminology
    /// switch) give way to a caption explaining that the example content
    /// chooses the layout, and return when the toggle goes off.
    /// </summary>
    private void RefreshStructureArea()
    {
        bool locked = StructureComesFromExampleContent;
        _structureLockedNote.Visibility = locked ? Visibility.Visible : Visibility.Collapsed;
        _structureEditorArea.Visibility = locked ? Visibility.Collapsed : Visibility.Visible;
        _structureCaption.Text = locked ? "Chosen by the example content" : "Defaults are fine for most courses";
    }

    /// <summary>
    /// The marks pool as it stands, seeded from the folders the course
    /// currently has and reconciled whenever those change.
    ///
    /// <para>Seeded with the historical rule rather than left empty: a brand
    /// new course starts with exactly the marks it would have had before this
    /// key existed, written down explicitly instead of inferred every build.
    /// Reconciled so a folder the teacher removes in the wizard cannot survive
    /// in a pool that would then match nothing on disk.</para>
    /// </summary>
    private List<string> CurrentGradedFolders()
    {
        var actual = _sharedFolders.Concat(_perSectionFolders).ToList();
        _gradedFolders = _gradedFolders is null
            ? GradedFolderRule.InferredPool(actual)
            : GradedFolderRule.Reconciled(_gradedFolders, actual);
        return _gradedFolders;
    }

    /// <summary>
    /// The wizard's protection context.
    ///
    /// <para>The switch values are EFFECTIVE, not raw. A parent switch being
    /// off leaves its children disabled but still reading true, and blocking a
    /// removal on a disabled switch is a deadlock: the teacher is told to turn
    /// off a control they cannot reach. `include_curriculum_coverage` is
    /// computed exactly as `BuildConfiguration` writes it, and
    /// `include_curriculum_pages` likewise, so the rule and the file cannot
    /// disagree about what is on.</para>
    /// </summary>
    private ProtectionContext WizardProtection() => new(
        InWizard: true,
        CurriculumCoverageEnabled: CourseConfiguration.CurriculumCoverageEnabled(
            ExampleContentCatalog.HasContent(ExampleContentRoot, NormalizedCode),
            _prepopulate,
            ExampleContentCatalog.IncludesCurriculum(ExampleContentRoot, NormalizedCode),
            _includeCurriculum,
            _includeCurriculumCoverage),
        CurriculumPagesEnabled: CourseConfiguration.CurriculumPagesEnabled(
            ExampleContentCatalog.HasContent(ExampleContentRoot, NormalizedCode),
            _prepopulate,
            ExampleContentCatalog.IncludesCurriculum(ExampleContentRoot, NormalizedCode),
            _includeCurriculum),
        Jurisdiction: JurisdictionForCode(),
        // null, not the payload's or skeleton's declared `curriculum_folder`:
        // this app has no ExampleContentCatalog.CurriculumFolder or
        // SkeletonCatalog equivalent to ask, so the resolver falls back to the
        // "alphabetically first name containing curriculum" branch. A skeleton
        // family whose folder is called something else — "Expectations" — is
        // protected on the mac and NOT protected here. A KNOWN GAP, written
        // down in MAC-HANDOFF.md rather than left for somebody to rediscover;
        // it protects too little, never the wrong folder.
        ResolvedCurriculumFolder: CurriculumFolderRule.Resolve(null, _sharedFolders),
        GradedFolders: CurrentGradedFolders(),
        PerSectionFolders: _perSectionFolders,
        ResolvedClassFolder: ClassFolderRule.Name(null, _perSectionFolders));

    /// <summary>
    /// Which province's curriculum the switch offers, so the blocked sentence
    /// names the switch a teacher can actually see rather than always saying
    /// "Ontario".
    ///
    /// <para>Read from the PROVINCE DROPDOWN, which is the control that decides
    /// what the wizard's own label says — so the label and the sentence always
    /// agree, which is the property that matters here. The mac derives it from
    /// the course CODE instead, so an Ontario-selected teacher typing a BC code
    /// sees a different sentence on each platform. Noted in MAC-HANDOFF.md.</para>
    /// </summary>
    private string JurisdictionForCode() =>
        _province == "BC" ? "British Columbia" : SpecialNames.DefaultJurisdiction;

    private void RecordWizardRemovalBlocked(string list, string name, string reason) =>
        ActivityTrail.Note(ActivityTrail.Event.RemovalBlocked,
            $"new course {NormalizedCode}: could not remove \u201C{name}\u201D from {list} - {reason}");

    /// <summary>
    /// Recreate the four list editors AND the marks list — for a change that
    /// altered which folders exist.
    /// </summary>
    private void RebuildStructureLists()
    {
        RebuildFolderEditors();
        RebuildMarksList();
    }

    /// <summary>
    /// Just the four list editors, for a change that altered which rows are
    /// BLOCKED without altering which folders exist — a coverage switch, or a
    /// tick in the marks list. Rebuilding the marks list from inside its own
    /// checkbox handler would destroy the control mid-event.
    /// </summary>
    private void RebuildFolderEditors()
    {
        var lists = new StackPanel { Spacing = 4 };
        // No onRemoved/onAdded: a course that does not exist yet has nothing to
        // exclude from. The protection closures ARE passed, because the floors
        // they enforce are about the course being built, not about a build.
        lists.Children.Add(FormBuilders.StringListEditor("Shared folders", false,
            () => _sharedFolders, v => _sharedFolders = v, RebuildMarksList,
            protectionFor: name => ItemProtectionRule.For(name, ItemList.SharedFolders, WizardProtection()),
            onRemovalBlocked: (name, reason) => RecordWizardRemovalBlocked("the shared folders", name, reason)));
        lists.Children.Add(FormBuilders.StringListEditor("Shared files", true,
            () => _sharedFiles, v => _sharedFiles = v, () => { },
            protectionFor: name => ItemProtectionRule.For(name, ItemList.SharedFiles, WizardProtection()),
            onRemovalBlocked: (name, reason) => RecordWizardRemovalBlocked("the shared files", name, reason)));
        lists.Children.Add(FormBuilders.StringListEditor("Per-section folders", false,
            () => _perSectionFolders, v => _perSectionFolders = v, RebuildMarksList,
            protectionFor: name => ItemProtectionRule.For(name, ItemList.PerSectionFolders, WizardProtection()),
            onRemovalBlocked: (name, reason) => RecordWizardRemovalBlocked("the per-section folders", name, reason)));
        lists.Children.Add(FormBuilders.StringListEditor("Per-section files", true,
            () => _perSectionFiles, v => _perSectionFiles = v, () => { },
            protectionFor: name => ItemProtectionRule.For(name, ItemList.PerSectionFiles, WizardProtection()),
            onRemovalBlocked: (name, reason) => RecordWizardRemovalBlocked("the per-section files", name, reason)));
        _structureExpander.Content = lists;
    }

    /// <summary>
    /// The Marks checklist, rebuilt whenever the folder lists change so a
    /// folder that has just been added can be ticked and one that has gone
    /// stops being offered.
    /// </summary>
    private void RebuildMarksList()
    {
        _marksArea.Children.Clear();
        _marksArea.Children.Add(FormBuilders.ExampleCaption(
            "Tick the folders holding work that counts for marks. The Curriculum Coverage map shows an expectation as evaluated when a page in one of these addresses it."));
        _marksArea.Children.Add(FormBuilders.MembershipToggleList("Folders that count for marks",
            _sharedFolders.Concat(_perSectionFolders).ToList(),
            CurrentGradedFolders,
            v => _gradedFolders = v,
            // A second ticked folder unblocks the first in the lists above.
            RebuildFolderEditors,
            name => ItemProtectionRule.For(name, ItemList.GradedFolders, WizardProtection()),
            (name, reason) => RecordWizardRemovalBlocked("the marks list", name, reason)));
    }

    // ---- Validation and auto-fill ---------------------------------------

    /// <summary>
    /// Rows shown in the course-code picker's dropdown: a known code, its
    /// short name, and whether it carries a ready-made example course —
    /// enough for a teacher to find a code by typing part of its NAME rather
    /// than having to already know the code, the way the mac's flyout works.
    /// </summary>
    private sealed class CourseCodeSuggestion
    {
        public string Code { get; init; } = "";
        public string DisplayName { get; init; } = "";

        // A Visibility, not a bool: {Binding} needs no converter when the
        // source property already carries the target property's own type.
        public Visibility BadgeVisibility { get; init; } = Visibility.Collapsed;
    }

    /// <summary>
    /// A two-line row per suggestion — code bold on top, short name beneath,
    /// with an "Example content" badge when a ready-made course exists for
    /// it. Built from a XAML fragment via XamlReader rather than x:Bind,
    /// since this dialog has no .xaml file of its own to declare a
    /// DataTemplate in (WinUI's DataTemplate has no Func&lt;object&gt;
    /// factory constructor to build one purely in code).
    /// </summary>
    private static DataTemplate BuildCodeSuggestionTemplate()
    {
        const string xaml = """
            <DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                          xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
              <Grid Padding="4" ColumnSpacing="8">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Spacing="0">
                  <TextBlock Text="{Binding Code}" FontWeight="SemiBold"/>
                  <TextBlock Text="{Binding DisplayName}" FontSize="12" Opacity="0.7" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
                <Border Grid.Column="1" Background="{ThemeResource AccentFillColorDefaultBrush}"
                        CornerRadius="8" Padding="6,1,6,1" VerticalAlignment="Center"
                        Visibility="{Binding BadgeVisibility}">
                  <TextBlock Text="Example content" FontSize="10" Foreground="White"/>
                </Border>
              </Grid>
            </DataTemplate>
            """;
        return (DataTemplate)XamlReader.Load(xaml);
    }

    /// <summary>
    /// Filters the CURRENTLY SELECTED province's catalog by whatever has
    /// been typed so far, matching against the code AND its names — so a
    /// teacher can find "ICS3U" by typing "computer science" just as easily
    /// as by typing the code itself. The province picker narrows this list
    /// only; it never gates typing a code straight through (CourseCodeValidator
    /// and ClubCodeRule below always consult the FULL merged catalog,
    /// regardless of which province is selected here) — matching the mac's
    /// own picker, whose province Picker "narrows its suggestion list, never
    /// gates typing a code straight through" (NewCourseWizardView.swift).
    /// </summary>
    private void RefreshCodeSuggestions()
    {
        string typed = _codeBox.Text.Trim();
        if (typed.Length == 0) { _codeBox.ItemsSource = null; return; }

        var province = CourseNameCatalogs.ForProvince(_province);
        _codeBox.ItemsSource = CourseCatalog.Matching(province, typed, CourseCatalog.SearchResultLimit)
            .Select(e => new CourseCodeSuggestion
            {
                Code = e.Code,
                DisplayName = e.ShortName,
                BadgeVisibility = ExampleContentCatalog.HasContent(ExampleContentRoot, e.Code)
                    ? Visibility.Visible : Visibility.Collapsed,
            })
            .ToList();
    }

    private bool IsClubCode(string code) => ClubCodeRule.IsClub(code, _nameCatalog);

    private void RefreshClubRow() =>
        _shortRow.Visibility = IsClubCode(_codeBox.Text.Trim().ToUpperInvariant())
            ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>A teacher's own typing is never replaced — auto-fill only over emptiness or a previous auto-fill.</summary>
    private void AutoFillCourseName()
    {
        var names = _nameCatalog.Names(_codeBox.Text);
        _suggestionsRow.Children.Clear();
        if (names is null) { _suggestionsRow.Visibility = Visibility.Collapsed; return; }

        if (_nameBox.Text.Length == 0 || _nameBox.Text == _lastAutoFilledName)
        {
            string defaultName = _nameCatalog.DefaultName(_codeBox.Text) ?? names.Short;
            _nameBox.Text = defaultName;
            _lastAutoFilledName = defaultName;
        }
        _suggestionsRow.Visibility = Visibility.Visible;
        _suggestionsRow.Children.Add(FormBuilders.ExampleCaption(
            $"Suggested names for {_codeBox.Text.Trim().ToUpperInvariant()}:"));
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (string suggestion in new[] { names.Short, names.Formal }.Distinct())
        {
            var button = new Button { Content = suggestion, FontSize = 12, Padding = new Thickness(8, 2, 8, 2) };
            button.Click += (_, _) => { _nameBox.Text = suggestion; _lastAutoFilledName = suggestion; };
            buttons.Children.Add(button);
        }
        _suggestionsRow.Children.Add(buttons);
    }

    /// <summary>
    /// The live caption under the unit-word field, and its two refusals.
    ///
    /// <para>Shows the teacher what their word produces before they commit to
    /// it, because the word is chosen once — at creation — and renaming a
    /// course already in use is deliberately not offered.</para>
    /// </summary>
    private void RefreshUnitWord()
    {
        string typed = _unitWordBox.Text;
        _unitWordCaption.Text = ClassPageTerm.Caption(typed);
        string? problem = ClassPageTerm.Problem(typed);
        _unitWordWarning.Text = problem ?? "";
        _unitWordWarning.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>Whether the unit word is usable, for the Create button.</summary>
    private bool UnitWordIsUsable => ClassPageTerm.Problem(_unitWordBox.Text) is null;

    private void RefreshSectionsValidation()
    {
        string? problem = SectionNumbersProblem(_sectionsBox.Text);
        if (problem is null)
        {
            _sectionsCaption.Text = "e.g. 1,3 — comma-separated";
            _sectionsCaption.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        }
        else
        {
            _sectionsCaption.Text = problem;
            _sectionsCaption.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
        }
    }

    private void RefreshGradeWarning()
    {
        string? warning = CourseConfiguration.GradeInTitleWarning(
            _nameBox.Text, _codeBox.Text.Trim().ToUpperInvariant(), _showsGrade);
        _gradeWarningSlot.Text = warning ?? "";
        _gradeWarningSlot.Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"];
        _gradeWarningSlot.Visibility = warning is null ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>
    /// Written for the mistakes people actually make — load-bearing because
    /// the parser silently drops pieces it cannot read ("1,3 5" would
    /// quietly become just section 1).
    /// </summary>
    public static string? SectionNumbersProblem(string text) =>
        SectionNumbersRule.Problem(text);

    public static List<int> ParsedSectionNumbers(string text) =>
        SectionNumbersRule.Parse(text);

    // ---- Creation --------------------------------------------------------

    private void OnPrimaryButton(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        if (_started) return;   // "Close" after completion
        args.Cancel = true;
        _ = StartCreation();
    }

    private void OnCloseButton(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        // StopByUser, not Terminate: closing the dialog is an ending the
        // teacher asked for, and the trail must say so. The 2026-08-19
        // problem report logged this as "failed (exit code -1)", which sent
        // the investigation toward a launcher fault that never existed.
        if (_creator.IsCreating) _creator.Runner.StopByUser();
    }

    private async System.Threading.Tasks.Task StartCreation()
    {
        string code = CourseCodeValidator.Normalize(_codeBox.Text);
        if (code.Length == 0) { ShowValidation("Enter a course code."); return; }
        if (CourseCodeProblem() is { } codeProblem) { ShowValidation(codeProblem); return; }
        if (SectionNumbersProblem(_sectionsBox.Text) is { } problem) { ShowValidation(problem); return; }
        if (_window.Workspace.WorkspacePath is not { } workspacePath)
        { ShowValidation("No working folder is selected."); return; }

        string name = _nameBox.Text.Trim();
        if (name.Length == 0) name = WizardDefaults.FallbackCourseName;

        BeginProgress("Creating your course");
        await _creator.CreateCourse(BuildConfiguration(code, name), workspacePath);
        if (_creator.PreparationProblem is { } preparationProblem)
        {
            ShowValidation(preparationProblem);
            return;
        }
        CreatedCourseCode = code;
        FinishProgress();
    }

    private async System.Threading.Tasks.Task StartExampleInstall()
    {
        if (_window.Workspace.WorkspacePath is not { } workspacePath)
        { ShowValidation("Choose a working folder first."); return; }
        BeginProgress("Adding the example course");
        await _creator.InstallExampleCourse(workspacePath);
        CreatedCourseCode = _creator.InstalledExampleCode;
        CreatedIsExample = CreatedCourseCode is not null;
        FinishProgress();
    }

    private void BeginProgress(string title)
    {
        _started = true;
        _validationText.Visibility = Visibility.Collapsed;
        _progress.Bind(_creator.Runner, title);
        // Drop the form's ScrollViewer entirely and stand the progress view in
        // its place with a bounded MaxHeight. Nesting the terminal inside a
        // ScrollViewer would measure its console with infinite height, so the
        // console could never clip, show a scrollbar, or follow its newest
        // line. Free-standing with a MaxHeight, the console pane is itself the
        // bounded, tail-following scroll region.
        _progress.MaxHeight = 520;
        _progress.VerticalAlignment = VerticalAlignment.Stretch;
        int slot = _root.Children.IndexOf(_formScroll);
        if (slot >= 0) _root.Children[slot] = _progress;
        else if (!_root.Children.Contains(_progress)) _root.Children.Insert(0, _progress);
        // The closing button is present throughout so the footer never
        // reflows; it becomes usable once the work ends.
        PrimaryButtonText = "Close";
        IsPrimaryButtonEnabled = false;
        CloseButtonText = "Cancel";
    }

    private void FinishProgress()
    {
        IsPrimaryButtonEnabled = true;
        CloseButtonText = "";
    }

    private void ShowValidation(string message)
    {
        _validationText.Text = message;
        _validationText.Visibility = Visibility.Visible;
    }

    private JObject BuildConfiguration(string code, string name)
    {
        var sections = ParsedSectionNumbers(_sectionsBox.Text);
        JObject PerSection(Func<int, JToken> value)
        {
            var map = new JObject();
            foreach (int n in sections) map["section" + n] = value(n);
            return new JObject { ["sections"] = map };
        }
        var flatSchemes = new JObject();
        foreach (int n in sections) flatSchemes["section" + n] = _schemeId;

        string locale = _localeBox.SelectedIndex >= 0
            ? LocaleCatalog.Codes[_localeBox.SelectedIndex]
            : WizardDefaults.DefaultLocale;

        var allItems = _sharedFolders.Concat(_sharedFiles).Concat(_perSectionFolders).Concat(_perSectionFiles).ToHashSet();
        var hidden = WizardDefaults.HiddenItems
            .Where(i => allItems.Contains(i)
                        || string.Equals(i, "Media", StringComparison.OrdinalIgnoreCase))
            .ToList();
        var expandableSource = _sharedFolders.Concat(_perSectionFolders).ToHashSet();
        var expandable = WizardDefaults.ExpandableItems.Where(expandableSource.Contains).ToList();

        // The real wizard reads these as its defaults, exactly like every
        // other answer here. False when no content exists for the code, so a
        // stale true can never mean anything.
        bool hasContent = ExampleContentCatalog.HasContent(ExampleContentRoot, code);
        bool includesCurriculum = ExampleContentCatalog.IncludesCurriculum(ExampleContentRoot, code);

        var result = new JObject
        {
            ["course_code"] = code,
            ["course_name"] = name,
            ["custom_short_name"] = IsClubCode(code) ? _shortBox.Text.Trim() : "",
            ["locale"] = locale,
            ["emojis"] = PerSection(_ => _emoji),
            ["num_sections"] = sections.Count,
            ["section_numbers"] = new JArray(sections),
            ["shared_folders"] = new JArray(_sharedFolders),
            ["shared_files"] = new JArray(_sharedFiles),
            ["per_section_folders"] = new JArray(_perSectionFolders),
            ["per_section_files"] = new JArray(_perSectionFiles),
            ["hidden"] = new JArray(hidden),
            ["expandable"] = new JArray(expandable),
            ["expandOnFolderClick"] = _expandOnFolderClick,
            ["footer_html"] = _footerHtml,
            ["show_reading_time"] = _showReadingTime,
            ["show_grade_in_title"] = PerSection(_ => _showsGrade),
            ["prepopulate_example_content"] = hasContent && _prepopulate,
            ["include_curriculum_pages"] = hasContent && _prepopulate && includesCurriculum && _includeCurriculum,
            ["include_curriculum_coverage"] = PerSection(_ => _includeCurriculumCoverage),

            ["include_coverage_notes"] = PerSection(_ => CourseConfiguration.CoverageNotesEnabled(_includeCurriculumCoverage, _includeCoverageNotes)),
            ["use_lcs_terminology"] = _useLcs,
            ["deploy_target"] = _deployTarget,
            ["deploy_folder_path"] = _deployFolderPath,
            ["fonts"] = new JObject
            {
                ["default"] = _fontChoice.ToJson(),
                ["sections"] = PerSection(_ => _fontChoice.ToJson())["sections"],
            },
            ["show_section_marker"] = PerSection(_ => _showsMarker),
            ["color_schemes"] = flatSchemes,

            // Recorded rather than guessed, both of them. `unit_word` is asked
            // of every course; `class_folder` is what the guess would pick
            // TODAY, written down so that reordering the folder list later
            // cannot silently move where class pages are written.
            ["unit_word"] = ClassPageTerm.Cleaned(_unitWordBox.Text),
            ["class_folder"] = ClassFolderRule.Name(null, _perSectionFolders),
        };

        // The marks pool is written ONLY when the teacher chose it — which
        // means only when the structure did not come from example content.
        //
        // A payload declares its own `graded_folders` in its manifest, and
        // `setup_course.py:graded_folders_for` prefers a pool already present in
        // the saved config over the manifest's. So writing one here for a
        // pre-populated course would silently OVERRIDE a manifest that had
        // declared the right answer — and the value written would be an
        // inference from the wizard's DEFAULT folders, because the structure
        // editors are collapsed for such a course and never showed the teacher
        // the payload's real ones. If the payload calls its assessed folder
        // anything but exactly "Tasks", reconciliation would then leave `[]`:
        // the explicit "asked, and nothing counts" state, from a teacher who was
        // never asked. Mirrors the mac's own guard.
        if (!StructureComesFromExampleContent)
        {
            result["graded_folders"] = new JArray(
                GradedFolderRule.Reconciled(CurrentGradedFolders(),
                    _sharedFolders.Concat(_perSectionFolders)));
        }

        // Pruned once more, defensively, at the point this actually gets
        // written — so the file on disk is correct even in a hypothetical
        // future case where the picker's own pruning (in the setter above)
        // did not run before Create was clicked. Uses CourseConfiguration's
        // own encoding so the omit-when-empty rule stays in exactly one
        // place. Mirrors NewCourseWizardView.buildConfigurationDictionary
        // on the mac.
        var withDeployTargets = CourseConfiguration.FromDictionary(result);
        withDeployTargets.AdditionalDeployTargets =
            CourseConfiguration.PruningAdditionalTargets(_additionalDeployTargets, _deployTarget);
        return withDeployTargets.Values;
    }
}
