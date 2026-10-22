using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Views;

/// <summary>
/// File ▸ Settings ▸ Obsidian (#581; the mac's <c>ObsidianSettingsView</c>,
/// #495): the ONE toggle for Obsidian's add-ons for diagrams and graphs, and
/// the only way back from "Don't ask again". On stores yes, off stores no,
/// never asked shows as off (<c>obsidianAddOnsForFigures.answer.toggle</c>).
/// Turning it off adds nothing new and removes nothing already added. Every
/// word is the contract's: <c>wording.settingLabel</c>, and
/// <c>windowsWording.settingFooter</c> (Enter, not Return) under it.
/// </summary>
/// <remarks>Saved at once; one <c>obsidian add-ons setting changed</c> line per change. Shown as stored BEFORE listening, so opening the pane writes nothing.</remarks>
public sealed class ObsidianSettingsPane
{
    /// <summary>What the Settings window shows for this section.</summary>
    public FrameworkElement Root { get; }

    private readonly AppSettings _settings;
    private readonly CheckBox _toggle;

    public ObsidianSettingsPane(AppSettings settings)
    {
        _settings = settings;
        var panel = new StackPanel { Spacing = 8, MaxWidth = 560, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 18, 0, 0) };

        _toggle = new CheckBox
        {
            Content = new TextBlock { Text = ObsidianFigureAddOnsWording.SettingLabel, TextWrapping = TextWrapping.Wrap },
            IsChecked = settings.ObsidianFigureAddOnsAnswer == ObsidianFigureAddOnsAnswer.Yes,
        };
        AutomationProperties.SetAutomationId(_toggle, "obsidianAddOnsSetting");
        AutomationProperties.SetName(_toggle, ObsidianFigureAddOnsWording.SettingLabel);
        _toggle.Checked += (_, _) => Change(true);
        _toggle.Unchecked += (_, _) => Change(false);
        panel.Children.Add(_toggle);

        var footer = FormBuilders.ExampleCaption(ObsidianFigureAddOnsWording.SettingFooter);
        AutomationProperties.SetAutomationId(footer, "obsidianAddOnsSettingFooter");
        panel.Children.Add(footer);

        Root = new ScrollViewer
        {
            Content = panel,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(0, 0, 20, 0),
        };
    }

    private void Change(bool on)
    {
        if (_settings.ChangeObsidianFigureAddOns(on))
            ActivityTrail.Note(ActivityTrail.Event.ObsidianAddOnsSettingChanged, ObsidianFigureAddOnsTrail.SettingChanged(on));
    }
}
