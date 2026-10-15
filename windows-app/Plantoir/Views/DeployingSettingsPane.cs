using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Windows.System;

namespace Plantoir.Views;

/// <summary>
/// File ▸ Settings ▸ Deploying: the Cloudflare Account ID, the one deploying
/// answer that belongs to the teacher rather than to a course (#491; the mac's
/// <c>DeployingSettingsView.swift</c>). The ONLY place in the app that changes
/// the ID — <c>CloudflareAccountInSettingsTests</c> reads the source to keep it
/// that way. A course's Deploying section and the new-course wizard show it
/// read-only with Open Settings…, and follow it live through
/// <see cref="AppSettings.CloudflareAccountIdChanged"/>.
/// </summary>
/// <remarks>
/// <para><b>Saved as it is typed, recorded when the teacher leaves the field.</b>
/// Every keystroke is stored (a wizard waiting on the ID enables Create the
/// moment it is valid), but the trail line is written once — on Enter, when
/// the field loses focus, when another section is chosen, when the window
/// closes, and at quit (<see cref="SettingsWindow.NoteBeforeQuit"/>) — by
/// comparing with the ID as it was when the last line was written. A line per
/// key would bury everything else on the trail; no line at all would leave
/// "every Cloudflare deploy started failing on Tuesday" with no answer.</para>
///
/// <para><b>The instructions are inline</b>, in an expander under the field,
/// rather than in a dialog with a field of its own as the mac's sheet has
/// ("Use This ID"): the pane's own field already does that job, and inline
/// they sit beside what they explain.</para>
/// </remarks>
public sealed class DeployingSettingsPane
{
    /// <summary>What the Settings window shows for this section.</summary>
    public FrameworkElement Root { get; }

    private readonly AppSettings _settings;
    private readonly TextBox _field;
    private readonly TextBlock _problem;

    /// <summary>The ID as it was when the last trail line was written (or when the pane was built).</summary>
    private string _idWhenNoted;

    public DeployingSettingsPane(AppSettings settings)
    {
        _settings = settings;
        _idWhenNoted = settings.CloudflareAccountId;

        var panel = new StackPanel { Spacing = 8, MaxWidth = 560, HorizontalAlignment = HorizontalAlignment.Left };
        panel.Children.Add(FormBuilders.SectionHeaderWithCaption("Cloudflare Pages", null));

        _field = new TextBox
        {
            Header = "Cloudflare Account ID",
            PlaceholderText = "32 letters and digits",
            Text = settings.CloudflareAccountId,
            MaxWidth = 420,
            HorizontalAlignment = HorizontalAlignment.Left,
            MinWidth = 360,
        };
        AutomationProperties.SetAutomationId(_field, "cloudflareAccountField");
        AutomationProperties.SetName(_field, "Cloudflare Account ID");
        panel.Children.Add(_field);

        // What is wrong with what was typed. Nothing is said about an EMPTY ID
        // here: a teacher who never deploys to Cloudflare has no reason to
        // fill it in, and the course that needs one says so itself.
        _problem = new TextBlock
        {
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"],
            Visibility = Visibility.Collapsed,
        };
        AutomationProperties.SetAutomationId(_problem, "cloudflareAccountProblem");
        panel.Children.Add(_problem);

        // Where to find it, inline (see the remarks). Opening it is recorded,
        // as it was in a course's settings: a teacher who had to go looking is
        // the teacher whose first deploy is about to need it.
        var help = new Expander
        {
            Header = "Where do I find this?",
            Content = CredentialRequestPanel.Build(CredentialRequests.CloudflareAccountIDHelp),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
        };
        AutomationProperties.SetAutomationId(help, "cloudflareAccountHelpButton");
        AutomationProperties.SetName(help, "Where do I find this?");
        help.Expanding += (_, _) => ActivityTrail.Note(ActivityTrail.Event.AskedForACredential,
            "opened the instructions for finding a Cloudflare Account ID");
        panel.Children.Add(help);

        panel.Children.Add(FormBuilders.ExampleCaption(
            "Every course that deploys to Cloudflare Pages uses this one account. Each course chooses where it deploys in its own settings."));
        panel.Children.Add(FormBuilders.ExampleCaption(
            "Sign in at dash.cloudflare.com and open Workers and Pages — the Account ID is shown on the right, and it’s also the long code in the address bar."));

        // Stored as typed, NOT echoed back: the pane does not listen to
        // CloudflareAccountIdChanged, so the trimmed value never replaces the
        // text under the teacher's cursor.
        _field.TextChanged += (_, _) =>
        {
            _settings.ChangeCloudflareAccountId(_field.Text.Trim());
            RefreshProblem();
        };
        _field.KeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Enter) NoteTheChange();
        };
        _field.LostFocus += (_, _) => NoteTheChange();

        RefreshProblem();
        Root = new ScrollViewer
        {
            Content = panel,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(0, 0, 20, 0),   // the scrollbar's gutter, as the Assistant section has
        };
    }

    private void RefreshProblem()
    {
        string? problem = DeployingSettings.Problem(_field.Text);
        _problem.Text = problem ?? "";
        _problem.Visibility = problem is null ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>Writes the trail line if the ID changed since the last one. Safe to call any number of times.</summary>
    public void NoteTheChange()
    {
        string now = _settings.CloudflareAccountId;
        if (DeployingSettings.TrailLine(_idWhenNoted, now) is { } line)
            ActivityTrail.Note(ActivityTrail.Event.CloudflareAccountIdChangedInSettings, line);
        _idWhenNoted = now;
    }
}
