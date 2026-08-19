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
/// The Cloudflare account ID is asked for here rather than left to the
/// launcher's console prompt, because the app publishes with nothing attached
/// to answer a prompt — and a token scoped to Pages cannot look its own
/// account up (checked against a real token).
/// </summary>
public sealed class PublishingChoiceView
{
    public StackPanel Root { get; }

    /// <summary>Raised after every change the teacher makes here.</summary>
    public event Action? Changed;

    private const int NetlifyIndex = 0;
    private const int CloudflareIndex = 1;
    private const int FolderIndex = 2;

    private readonly Func<string> _getTarget;
    private readonly Func<string> _getPath;
    private readonly Func<string> _getAccount;
    private readonly StackPanel _folderArea;
    private readonly StackPanel _cloudflareArea;
    private readonly TextBox _pathBox;
    private readonly TextBox _accountBox;
    private readonly TextBlock _problemText;
    private readonly TextBlock _caption;
    private readonly TextBlock _cloudflareProblemText;
    private readonly TextBlock _cloudflareCaption;
    private readonly TextBlock _cloudflareSizeNote;
    private readonly Window _pickerOwner;
    private bool _updatingFromModel;

    /// <summary>
    /// What is wrong with the current choice, or null when nothing is —
    /// always null in Netlify mode, which needs no settings here.
    /// </summary>
    public string? Problem => _getTarget() switch
    {
        "local_folder" => CourseConfiguration.DeployFolderProblem(_getPath()),
        "cloudflare_pages" => CourseConfiguration.CloudflareAccountProblem(_getAccount()),
        _ => null,
    };

    public PublishingChoiceView(Window pickerOwner,
                                Func<string> getTarget, Action<string> setTarget,
                                Func<string> getPath, Action<string> setPath,
                                Func<string> getAccount, Action<string> setAccount)
    {
        _pickerOwner = pickerOwner;
        _getTarget = getTarget;
        _getPath = getPath;
        _getAccount = getAccount;

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
        _cloudflareArea = new StackPanel { Spacing = 4 };
        _accountBox = new TextBox { Text = getAccount(), PlaceholderText = "Account ID" };
        AutomationProperties.SetAutomationId(_accountBox, "cloudflareAccountField");
        _cloudflareArea.Children.Add(FormBuilders.LabeledRow("Cloudflare Account ID", _accountBox));

        var helpButton = new HyperlinkButton
        {
            Content = "Where do I find this?",
            FontSize = 12,
            Padding = new Thickness(0),
            Margin = new Thickness(0, 2, 0, 4),
        };
        helpButton.Click += async (_, _) =>
        {
            Plantoir.Core.Scripting.ActivityTrail.Note(
                Plantoir.Core.Scripting.ActivityTrail.Event.AskedForACredential,
                "opened instructions for Cloudflare Account ID");
            var help = Plantoir.Core.Scripting.CredentialRequests.CloudflareAccountIDHelp;
            var panel = CredentialRequestPanel.Build(help);

            var dialog = new ContentDialog
            {
                Title = help.Title,
                Content = panel,
                CloseButtonText = "Done",
                DefaultButton = ContentDialogButton.Close,
                XamlRoot = _pickerOwner.Content?.XamlRoot
            };
            await dialog.ShowAsync();
        };
        _cloudflareArea.Children.Add(helpButton);

        _cloudflareProblemText = CautionLine("cloudflareAccountProblem");
        _cloudflareArea.Children.Add(_cloudflareProblemText);
        _cloudflareCaption = FormBuilders.ExampleCaption(
            "Each section gets its own free site at yourproject.pages.dev. Sign in at dash.cloudflare.com and open Workers and Pages — the Account ID is shown on the right, and it’s also the long code in the address bar. You only enter it once. The first deploy asks for an API token with the Cloudflare Pages permission.");
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
            Changed?.Invoke();
        };
        _pathBox.TextChanged += (_, _) =>
        {
            if (_updatingFromModel) return;
            setPath(_pathBox.Text);
            RefreshAreas();
            Changed?.Invoke();
        };
        _accountBox.TextChanged += (_, _) =>
        {
            if (_updatingFromModel) return;
            setAccount(_accountBox.Text.Trim());
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
    }

    private static void ShowProblem(TextBlock line, TextBlock caption, string? problem)
    {
        line.Text = problem ?? "";
        line.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
        caption.Visibility = problem is null ? Visibility.Visible : Visibility.Collapsed;
    }
}
