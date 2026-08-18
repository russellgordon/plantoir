using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Services;

namespace Plantoir.Views;

/// <summary>
/// The shelf of things a teacher can ask for, pinned at the top of the local AI
/// assistant window.
///
/// Each kind of request is a collapsible disclosure group, shut by default:
/// five short lines a teacher can scan, and open when they want reminding.
/// When opened, tapping a card puts the phrasing in the input box to edit.
/// </summary>
public sealed class AssistPromptShelfView : UserControl
{
    private readonly Action<string> _choose;
    private readonly AppSettings? _settings;
    private readonly HashSet<string> _openGroups;

    public AssistPromptShelfView(Action<string> choose, AppSettings? settings = null)
    {
        _choose = choose;
        _settings = settings ?? App.Settings;
        _openGroups = AssistPromptShelf.ParseOpenGroups(_settings?.AssistPromptShelfOpenGroups);

        var root = new StackPanel { Spacing = 4 };

        var intro = new TextBlock
        {
            Text = AssistPromptShelf.HeaderText,
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75,
            Margin = new Thickness(0, 0, 0, 4),
        };
        try { intro.Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"]; } catch { }
        root.Children.Add(intro);

        var groupsContainer = new StackPanel { Spacing = 2 };

        foreach (var (title, phrasings) in AssistPromptShelf.Groups)
        {
            groupsContainer.Children.Add(BuildGroup(title, phrasings));
        }

        var scroller = new ScrollViewer
        {
            Content = groupsContainer,
            MaxHeight = 240,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        root.Children.Add(scroller);

        Content = root;
    }

    private UIElement BuildGroup(string title, IReadOnlyList<string> phrasings)
    {
        var groupPanel = new StackPanel { Spacing = 2 };
        bool isOpen = _openGroups.Contains(title);

        var headerButton = new Button
        {
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(4, 4, 4, 4),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderBrush = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
        };
        AutomationProperties.SetAutomationId(headerButton, $"assistGroupHeader-{title}");

        var headerGrid = new Grid { ColumnSpacing = 8 };
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var chevron = new FontIcon
        {
            Glyph = isOpen ? "\uE70E" : "\uE76C", // ChevronDown vs ChevronRight
            FontSize = 10,
            VerticalAlignment = VerticalAlignment.Center,
            Opacity = 0.7,
        };
        Grid.SetColumn(chevron, 0);
        headerGrid.Children.Add(chevron);

        var titleBlock = new TextBlock
        {
            Text = title,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        };
        try { titleBlock.Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"]; } catch { }
        Grid.SetColumn(titleBlock, 1);
        headerGrid.Children.Add(titleBlock);

        headerButton.Content = headerGrid;

        var itemsPanel = new StackPanel
        {
            Spacing = 4,
            Margin = new Thickness(18, 2, 0, 6),
            Visibility = isOpen ? Visibility.Visible : Visibility.Collapsed,
        };

        foreach (string phrasing in phrasings)
        {
            var cardButton = new Button
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                Padding = new Thickness(10, 6, 10, 6),
                CornerRadius = new CornerRadius(6),
                Content = new TextBlock
                {
                    Text = phrasing,
                    TextWrapping = TextWrapping.Wrap,
                    TextAlignment = TextAlignment.Left,
                },
            };
            AutomationProperties.SetAutomationId(cardButton, $"assistSuggestion-{phrasing}");

            cardButton.Click += (_, _) => _choose(phrasing);
            itemsPanel.Children.Add(cardButton);
        }

        headerButton.Click += (_, _) =>
        {
            if (_openGroups.Contains(title))
            {
                _openGroups.Remove(title);
                itemsPanel.Visibility = Visibility.Collapsed;
                chevron.Glyph = "\uE76C"; // ChevronRight
            }
            else
            {
                _openGroups.Add(title);
                itemsPanel.Visibility = Visibility.Visible;
                chevron.Glyph = "\uE70E"; // ChevronDown
            }

            if (_settings is not null)
            {
                _settings.AssistPromptShelfOpenGroups = AssistPromptShelf.SerializeOpenGroups(_openGroups);
                try { _settings.Save(); } catch { }
            }
        };

        groupPanel.Children.Add(headerButton);
        groupPanel.Children.Add(itemsPanel);
        return groupPanel;
    }
}
