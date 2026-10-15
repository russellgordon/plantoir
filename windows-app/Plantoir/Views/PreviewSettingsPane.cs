using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Views;

/// <summary>
/// File ▸ Settings ▸ Preview (#514; Russell's ruling on #514 of 2026-10-15,
/// the mac's <c>PreviewSettingsView.swift</c>): where a press of Preview
/// opens — the site's front page (the default) or the page last viewed —
/// with the sentence saying how to get the other one once. Every word is the
/// contract's (<c>previewStartPage.wording</c>, and <c>windowsWording.altNote</c>
/// under the choices).
/// </summary>
/// <remarks>
/// Saved at once, and one trail line per change
/// (<c>preview start page chosen in Settings</c>): a teacher who asks why
/// Preview opened somewhere odd is answered by it. The section windows and
/// the Section menu follow through <see cref="AppSettings.PreviewOpensAtChanged"/>.
/// </remarks>
public sealed class PreviewSettingsPane
{
    /// <summary>What the Settings window shows for this section.</summary>
    public FrameworkElement Root { get; }

    private readonly AppSettings _settings;
    private readonly RadioButtons _choices;

    public PreviewSettingsPane(AppSettings settings)
    {
        _settings = settings;
        var panel = new StackPanel { Spacing = 8, MaxWidth = 560, HorizontalAlignment = HorizontalAlignment.Left };

        var frontPage = new RadioButton { Content = PreviewStartPage.FrontPageChoice };
        AutomationProperties.SetAutomationId(frontPage, "previewStartPageFrontPage");
        var lastViewed = new RadioButton { Content = PreviewStartPage.LastViewedChoice };
        AutomationProperties.SetAutomationId(lastViewed, "previewStartPageLastViewed");

        _choices = new RadioButtons { Header = PreviewStartPage.SettingLabel, Margin = new Thickness(0, 18, 0, 0) };
        _choices.Items.Add(frontPage);
        _choices.Items.Add(lastViewed);
        AutomationProperties.SetAutomationId(_choices, "previewStartPageChoice");
        AutomationProperties.SetName(_choices, PreviewStartPage.SettingLabel);
        // Shown as stored BEFORE listening, so opening the pane writes nothing.
        _choices.SelectedIndex = PreviewStartPage.Read(settings.PreviewOpensAt) == PreviewStartPage.Setting.LastViewed ? 1 : 0;
        _choices.SelectionChanged += (_, _) => Choose();
        panel.Children.Add(_choices);

        var note = FormBuilders.ExampleCaption(PreviewStartPage.AltNote);
        AutomationProperties.SetAutomationId(note, "previewStartPageAltNote");
        panel.Children.Add(note);

        Root = new ScrollViewer
        {
            Content = panel,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(0, 0, 20, 0),   // the scrollbar's gutter, as the other sections have
        };
    }

    private void Choose()
    {
        if (_choices.SelectedIndex < 0) return;
        var choice = _choices.SelectedIndex == 1 ? PreviewStartPage.Setting.LastViewed : PreviewStartPage.Setting.FrontPage;
        if (PreviewStartPage.Read(_settings.PreviewOpensAt) == choice) return;
        _settings.ChangePreviewOpensAt(choice);
        ActivityTrail.Note(ActivityTrail.Event.PreviewStartPageChosenInSettings, PreviewStartPage.SettingChangedTrail(choice));
    }
}
