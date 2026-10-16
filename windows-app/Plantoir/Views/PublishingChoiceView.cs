using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// The publishing choice — Netlify, Cloudflare Pages, or a folder on this PC —
/// used by BOTH Course Settings and the new-course wizard, so the two offer
/// exactly the same behaviour and wording (rows 101–102; mirrors the mac's
/// PublishingChoiceView). Validation is live: the problem line follows every
/// keystroke and every choice, and callers gate Save/Create on
/// <see cref="Problem"/> so a publish can never discover a bad setting after
/// the fact.
///
/// The Cloudflare account ID is SHOWN here, read-only, with Open Settings…
/// beside it (#491, the mac's #457 item 4): it is the teacher's, not the
/// course's, and is edited only in File ▸ Settings ▸ Deploying
/// (<see cref="DeployingSettingsPane"/>). Typed here, it changed silently for
/// every other course. A change made in Settings shows here — and
/// re-validates — at once, through <see cref="AppSettings.CloudflareAccountIdChanged"/>.
/// It is asked for in the app at all, rather than left to the launcher's
/// console prompt, because the app publishes with nothing attached to answer a
/// prompt — and a token scoped to Pages cannot look its own account up
/// (checked against a real token).
/// </summary>
public sealed class PublishingChoiceView
{
    public StackPanel Root { get; }

    /// <summary>Raised after every change the teacher makes here.</summary>
    public event Action? Changed;

    /// <summary>
    /// Raised after the Account ID shown here was refreshed because it changed
    /// in Settings — NOT a change to the course, so it is not <see cref="Changed"/>
    /// (Course Settings must not read it as an unsaved edit). The wizard listens,
    /// so Create follows the ID live.
    /// </summary>
    public event Action? AccountRefreshed;

    private const int NetlifyIndex = 0;
    private const int CloudflareIndex = 1;
    private const int FolderIndex = 2;

    private readonly Func<string> _getTarget;
    private readonly Func<string> _getPath;
    private readonly Func<string> _getAccount;
    private readonly Func<IReadOnlyList<CourseConfiguration.AdditionalDeployTarget>> _getAdditional;
    private readonly Action<IReadOnlyList<CourseConfiguration.AdditionalDeployTarget>> _setAdditional;
    private readonly StackPanel _folderArea;
    private readonly StackPanel _cloudflareArea;
    private readonly StackPanel _additionalArea;
    private readonly TextBox _pathBox;
    private readonly TextBlock _accountValue;
    private readonly TextBlock _problemText;
    private readonly TextBlock _caption;
    private readonly TextBlock _cloudflareProblemText;
    private readonly TextBlock _cloudflareCaption;
    private readonly TextBlock _cloudflareSizeNote;
    private readonly Window _pickerOwner;
    private bool _updatingFromModel;
    private bool _listeningForTheAccount;

    /// <summary>
    /// The Account ID shown inside the "Also deploy to" row when Cloudflare is
    /// the ADDITIONAL destination and the primary is something else — the
    /// primary's own Cloudflare block is collapsed then, so without this there
    /// would be nowhere on screen to see why <see cref="Problem"/> holds Save
    /// back, or to reach Settings to fix it (found by Russell 2026-08-22, when
    /// it was still a field: toggling on "Also deploy to Cloudflare" with
    /// Netlify as the primary). The same read-only display as the primary's —
    /// the mac's <c>CloudflareDetailFields</c>, reused in both places.
    /// </summary>
    private TextBlock? _additionalAccountValue;
    private TextBlock? _additionalCloudflareProblemText;

    /// <summary>
    /// What is wrong with the current choice, or null when nothing is —
    /// always null in Netlify mode, which needs no settings here. Checks
    /// every ADDITIONAL destination too, for the same reason the primary's
    /// own check exists: a bad folder or missing Cloudflare Account ID
    /// blocks Save/Create, rather than failing silently the first time a
    /// deploy actually reaches it. Mirrors the mac's PublishingChoiceView.
    /// </summary>
    public string? Problem
    {
        get
        {
            string? primaryProblem = _getTarget() switch
            {
                "local_folder" => CourseConfiguration.DeployFolderProblem(_getPath()),
                "cloudflare_pages" => CourseConfiguration.CloudflareAccountProblem(_getAccount()),
                _ => null,
            };
            if (primaryProblem is not null) return primaryProblem;
            foreach (var target in _getAdditional())
            {
                string? problem = target.Type switch
                {
                    "local_folder" => CourseConfiguration.DeployFolderProblem(target.Path),
                    "cloudflare_pages" => CourseConfiguration.CloudflareAccountProblem(_getAccount()),
                    _ => null,
                };
                if (problem is not null) return problem;
            }
            return null;
        }
    }

    public PublishingChoiceView(Window pickerOwner,
                                Func<string> getTarget, Action<string> setTarget,
                                Func<string> getPath, Action<string> setPath,
                                Func<string> getAccount,
                                Func<IReadOnlyList<CourseConfiguration.AdditionalDeployTarget>> getAdditional,
                                Action<IReadOnlyList<CourseConfiguration.AdditionalDeployTarget>> setAdditional)
    {
        _pickerOwner = pickerOwner;
        _getTarget = getTarget;
        _getPath = getPath;
        _getAccount = getAccount;
        _getAdditional = getAdditional;
        _setAdditional = setAdditional;

        Root = new StackPanel { Spacing = 6 };

        var targetBox = new ComboBox { MinWidth = 300 };
        targetBox.Items.Add("Netlify");
        targetBox.Items.Add("Cloudflare Pages");
        targetBox.Items.Add("A folder on this PC");
        targetBox.SelectedIndex = getTarget() switch
        {
            "local_folder" => FolderIndex,
            "cloudflare_pages" => CloudflareIndex,
            _ => NetlifyIndex,
        };
        AutomationProperties.SetAutomationId(targetBox, "deployTargetPicker");
        Root.Children.Add(FormBuilders.LabeledRow("Deploy to", targetBox));

        // ---- Folder ----
        _folderArea = new StackPanel { Spacing = 4 };
        var pathRow = new Grid { ColumnSpacing = 8 };
        pathRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        pathRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _pathBox = new TextBox { Text = getPath(), PlaceholderText = "Folder" };
        AutomationProperties.SetAutomationId(_pathBox, "deployFolderField");
        pathRow.Children.Add(_pathBox);
        var chooseButton = new Button { Content = "Choose…" };
        AutomationProperties.SetAutomationId(chooseButton, "deployFolderChooseButton");
        Grid.SetColumn(chooseButton, 1);
        pathRow.Children.Add(chooseButton);
        _folderArea.Children.Add(pathRow);

        _problemText = CautionLine("deployFolderProblem");
        _folderArea.Children.Add(_problemText);
        _caption = FormBuilders.ExampleCaption(
            "Each section deploys into its own subfolder here — section1, section2 — and only changed files are copied. Upload the folder to your web host however you prefer (e.g. over SFTP). Netlify isn’t involved.");
        _folderArea.Children.Add(_caption);
        Root.Children.Add(_folderArea);

        // ---- Cloudflare ----
        // The ID is SHOWN here and edited in File ▸ Settings ▸ Deploying (#491).
        _cloudflareArea = new StackPanel { Spacing = 4 };
        _accountValue = AccountDisplay(_cloudflareArea, "cloudflareAccountValue", "cloudflareAccountOpenSettings");

        _cloudflareProblemText = CautionLine("cloudflareAccountProblem");
        _cloudflareArea.Children.Add(_cloudflareProblemText);
        // Where to FIND the ID went to Settings with the field it explains.
        _cloudflareCaption = FormBuilders.ExampleCaption(
            "Each section gets its own free site at yourproject.pages.dev. The first deploy asks for an API token with the Cloudflare Pages permission.");
        _cloudflareArea.Children.Add(_cloudflareCaption);

        // Stays on screen the whole time Cloudflare is chosen — it is a
        // standing fact about the destination, not a mistake to correct, so
        // it is worded as a heads-up and never hides the way the problem
        // line does.
        _cloudflareSizeNote = CautionLine("cloudflareSizeNote");
        // The area's own visibility already hides this with everything else
        // when another destination is chosen.
        _cloudflareSizeNote.Visibility = Visibility.Visible;
        _cloudflareSizeNote.Text =
            "One thing to know: Cloudflare won’t accept any single file larger than 25 MB. " +
            "Documents, images, and slide decks are almost always comfortably under that — a long video usually isn’t. " +
            "Most teachers embed video from YouTube or Vimeo rather than uploading it, which avoids the limit entirely.";
        _cloudflareArea.Children.Add(_cloudflareSizeNote);
        Root.Children.Add(_cloudflareArea);

        // ---- Also publish to, for redundancy — real redundancy needs a
        // second copy of the site ALREADY live, not a scramble to
        // reconfigure a new destination after the fact. See
        // documentation/07-deployment.md.
        _additionalArea = new StackPanel { Spacing = 6, Margin = new Thickness(0, 12, 0, 0) };
        Root.Children.Add(_additionalArea);

        targetBox.SelectionChanged += (_, _) =>
        {
            if (_updatingFromModel) return;
            setTarget(targetBox.SelectedIndex switch
            {
                FolderIndex => "local_folder",
                CloudflareIndex => "cloudflare_pages",
                _ => "netlify",
            });
            RefreshAreas();
            RebuildAdditionalArea();
            Changed?.Invoke();
        };
        _pathBox.TextChanged += (_, _) =>
        {
            if (_updatingFromModel) return;
            setPath(_pathBox.Text);
            RefreshAreas();
            Changed?.Invoke();
        };
        chooseButton.Click += async (_, _) =>
        {
            var picker = new Windows.Storage.Pickers.FolderPicker();
            WinRT.Interop.InitializeWithWindow.Initialize(picker,
                WinRT.Interop.WindowNative.GetWindowHandle(_pickerOwner));
            picker.FileTypeFilter.Add("*");
            var folder = await picker.PickSingleFolderAsync();
            if (folder is null) return;
            _updatingFromModel = true;
            _pathBox.Text = folder.Path;
            _updatingFromModel = false;
            setPath(folder.Path);
            RefreshAreas();   // validation runs on the choice instantly
            Changed?.Invoke();
        };

        RefreshAreas();
        RebuildAdditionalArea();

        // A change made in Settings shows here at once. Static event, so the
        // view lets go of it when it leaves the screen: a wizard or a course
        // closed must not be kept alive, or refreshed, by the app's settings.
        //
        // MEASURED, and the reason for the IsLoaded check: inside the wizard's
        // ContentDialog, Unloaded arrives about 70 ms AFTER Loaded with the
        // view still on screen (IsLoaded true, parent unchanged) and no second
        // Loaded follows — WinUI's late Unloaded when the dialog re-hosts its
        // content. Unsubscribing on it left the wizard deaf to Settings, and
        // Create never followed a valid ID. An Unloaded that finds the view
        // still loaded is that stale one, and is ignored; the real one, when
        // the wizard was cancelled, measured IsLoaded false. The ignored one is
        // written to the diagnostic log, so that if it ever turned out to be a
        // real departure (and the view leaked its subscription) it would show.
        Root.Loaded += (_, _) => ListenForTheAccount(true);
        Root.Unloaded += (_, _) =>
        {
            if (!Root.IsLoaded) ListenForTheAccount(false);
            else App.LogDiagnostic("Account ID display: a late Unloaded while still loaded was ignored (still listening)");
        };
    }

    private void ListenForTheAccount(bool listen)
    {
        if (listen == _listeningForTheAccount) return;
        _listeningForTheAccount = listen;
        if (listen) AppSettings.CloudflareAccountIdChanged += OnAccountChangedInSettings;
        else AppSettings.CloudflareAccountIdChanged -= OnAccountChangedInSettings;
    }

    /// <summary>Raised on the thread that changed it — the Settings window's — so marshalled to this view's own.</summary>
    private void OnAccountChangedInSettings() => Root.DispatcherQueue?.TryEnqueue(() =>
    {
        RefreshAccountValues();
        RefreshAreas();
        AccountRefreshed?.Invoke();
    });

    /// <summary>
    /// The read-only Account ID — "Kept in File ▸ Settings ▸ Deploying…"
    /// first, then the value (or "Not set yet") with Open Settings… beside it —
    /// added to <paramref name="into"/>. One builder for the primary's block
    /// and the additional destination's, as the mac's <c>CloudflareDetailFields</c>.
    /// </summary>
    private TextBlock AccountDisplay(Panel into, string valueId, string openSettingsId)
    {
        // Said FIRST, where the row is read from: the value below is shown,
        // not edited, and this is where it is edited.
        into.Children.Add(FormBuilders.ExampleCaption(DeployingSettings.KeptIn));
        var value = new TextBlock
        {
            IsTextSelectionEnabled = true,
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        };
        AutomationProperties.SetAutomationId(value, valueId);
        var openSettings = new Button { Content = "Open Settings…" };
        AutomationProperties.SetAutomationId(openSettings, openSettingsId);
        openSettings.Click += (_, _) => SettingsWindow.Show(SettingsSection.Deploying);
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        row.Children.Add(value);
        row.Children.Add(openSettings);
        into.Children.Add(FormBuilders.LabeledRow("Cloudflare Account ID", row));
        ShowAccount(value);
        return value;
    }

    private void ShowAccount(TextBlock value)
    {
        string id = _getAccount();
        value.Text = DeployingSettings.Shown(id);
        value.Foreground = (Brush)Application.Current.Resources[
            id.Trim().Length == 0 ? "TextFillColorSecondaryBrush" : "TextFillColorPrimaryBrush"];
    }

    private void RefreshAccountValues()
    {
        ShowAccount(_accountValue);
        if (_additionalAccountValue is not null) ShowAccount(_additionalAccountValue);
    }

    private static string FriendlyName(string type) => type switch
    {
        "local_folder" => "A folder on this PC",
        "cloudflare_pages" => "Cloudflare Pages",
        _ => "Netlify",
    };

    /// <summary>
    /// Rebuilt (not just re-shown) whenever the primary changes, because
    /// the SET of available additional types changes with it — "one of
    /// each type, and never the primary twice" (row 304).
    /// </summary>
    private void RebuildAdditionalArea()
    {
        _additionalArea.Children.Clear();
        _additionalAccountValue = null;
        _additionalCloudflareProblemText = null;
        var availableTypes = CourseConfiguration.AvailableAdditionalDeployTargetTypes(_getTarget());
        if (availableTypes.Count == 0) return;

        _additionalArea.Children.Add(new TextBlock
        {
            Text = "Also deploy to, for redundancy",
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });
        // The one place that says what these switches DO. The mac's caption
        // (PublishingChoiceView.swift), word for word; Windows had the label
        // alone until #441 (v1.4.4).
        _additionalArea.Children.Add(FormBuilders.ExampleCaption("Deploying sends your website to every destination switched on here, one after another. If one host is down or having trouble, the others still go out. Most teachers leave this off — it is here for anyone who wants a second copy live."));

        foreach (string type in availableTypes)
        {
            var toggle = new ToggleSwitch
            {
                OnContent = "", OffContent = "",
                IsOn = CourseConfiguration.HasAdditionalDeployTarget(_getAdditional(), type),
            };
            AutomationProperties.SetAutomationId(toggle, $"additionalDeployTarget-{type}");
            var row = FormBuilders.LabeledRow(FriendlyName(type), toggle);
            _additionalArea.Children.Add(row);

            StackPanel? detailArea = null;
            TextBox? folderBox = null;
            TextBlock? folderProblemText = null;

            if (type == "local_folder")
            {
                detailArea = new StackPanel { Spacing = 4, Margin = new Thickness(0, 0, 0, 4) };
                var pathRow = new Grid { ColumnSpacing = 8 };
                pathRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                pathRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                folderBox = new TextBox
                {
                    Text = CourseConfiguration.AdditionalDeployTargetPath(_getAdditional(), type),
                    PlaceholderText = "Folder",
                };
                AutomationProperties.SetAutomationId(folderBox, $"additionalDeployFolderField-{type}");
                pathRow.Children.Add(folderBox);
                var chooseAdditional = new Button { Content = "Choose…" };
                Grid.SetColumn(chooseAdditional, 1);
                pathRow.Children.Add(chooseAdditional);
                detailArea.Children.Add(pathRow);

                folderProblemText = CautionLine($"additionalDeployFolderProblem-{type}");
                detailArea.Children.Add(folderProblemText);

                chooseAdditional.Click += async (_, _) =>
                {
                    var picker = new Windows.Storage.Pickers.FolderPicker();
                    WinRT.Interop.InitializeWithWindow.Initialize(picker,
                        WinRT.Interop.WindowNative.GetWindowHandle(_pickerOwner));
                    picker.FileTypeFilter.Add("*");
                    var folder = await picker.PickSingleFolderAsync();
                    if (folder is null) return;
                    folderBox.Text = folder.Path;
                    _setAdditional(CourseConfiguration.SettingAdditionalDeployTargetPath(_getAdditional(), folder.Path, type));
                    RefreshAdditionalProblem(folderProblemText, type);
                    Changed?.Invoke();
                };
                folderBox.TextChanged += (_, _) =>
                {
                    _setAdditional(CourseConfiguration.SettingAdditionalDeployTargetPath(_getAdditional(), folderBox.Text, type));
                    RefreshAdditionalProblem(folderProblemText, type);
                    Changed?.Invoke();
                };
                RefreshAdditionalProblem(folderProblemText, type);
                _additionalArea.Children.Add(detailArea);
            }
            else if (type == "cloudflare_pages")
            {
                // Cloudflare's account ID is per-teacher, in app settings —
                // NOT stored per destination — so this shows the same value
                // the primary's block shows. That block is only ON SCREEN
                // when the primary IS Cloudflare; when it isn't, Problem still
                // requires an ID before Save can enable, so the ID, why it
                // holds Save back, and the way to Settings belong here too.
                detailArea = new StackPanel { Spacing = 4, Margin = new Thickness(0, 0, 0, 4) };
                _additionalAccountValue = AccountDisplay(detailArea, "additionalCloudflareAccountValue",
                                                         "additionalCloudflareAccountOpenSettings");
                var problemText = CautionLine("additionalCloudflareAccountProblem");
                detailArea.Children.Add(problemText);
                _additionalCloudflareProblemText = problemText;
                RefreshAdditionalCloudflareProblem();
                _additionalArea.Children.Add(detailArea);
            }

            string capturedType = type;
            StackPanel? capturedDetailArea = detailArea;
            toggle.Toggled += (_, _) =>
            {
                _setAdditional(CourseConfiguration.SettingAdditionalDeployTarget(_getAdditional(), toggle.IsOn, capturedType));
                if (capturedDetailArea is not null)
                    capturedDetailArea.Visibility = toggle.IsOn ? Visibility.Visible : Visibility.Collapsed;
                Changed?.Invoke();
            };
            if (detailArea is not null)
                detailArea.Visibility = toggle.IsOn ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void RefreshAdditionalProblem(TextBlock problemText, string type)
    {
        string path = CourseConfiguration.AdditionalDeployTargetPath(_getAdditional(), type);
        string? problem = CourseConfiguration.DeployFolderProblem(path);
        problemText.Text = problem ?? "";
        problemText.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private void RefreshAdditionalCloudflareProblem()
    {
        if (_additionalCloudflareProblemText is null) return;
        string? problem = CourseConfiguration.CloudflareAccountProblem(_getAccount());
        _additionalCloudflareProblemText.Text = problem ?? "";
        _additionalCloudflareProblemText.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private static TextBlock CautionLine(string automationId)
    {
        var line = new TextBlock
        {
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
            Visibility = Visibility.Collapsed,
        };
        AutomationProperties.SetAutomationId(line, automationId);
        return line;
    }

    private void RefreshAreas()
    {
        string target = _getTarget();
        bool folderMode = target == "local_folder";
        bool cloudflareMode = target == "cloudflare_pages";
        _folderArea.Visibility = folderMode ? Visibility.Visible : Visibility.Collapsed;
        _cloudflareArea.Visibility = cloudflareMode ? Visibility.Visible : Visibility.Collapsed;

        // Only the visible area's problem is shown; Problem itself already
        // reports on whichever mode is active.
        string? problem = Problem;
        ShowProblem(_problemText, _caption, folderMode ? problem : null);
        ShowProblem(_cloudflareProblemText, _cloudflareCaption, cloudflareMode ? problem : null);
        RefreshAdditionalCloudflareProblem();
    }

    private static void ShowProblem(TextBlock line, TextBlock caption, string? problem)
    {
        line.Text = problem ?? "";
        line.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
        caption.Visibility = problem is null ? Visibility.Visible : Visibility.Collapsed;
    }
}
