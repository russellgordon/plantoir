using System;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;

namespace Plantoir.Views;

/// <summary>The About panel: icon, name, version, tagline, the namesake story, support links, credits.</summary>
public sealed class AboutDialog : ContentDialog
{
    public AboutDialog()
    {
        // No dialog title at all: the icon and the large "Plantoir" heading
        // ARE the title, as on the mac About window. The menu item that opens
        // this panel still says "About Plantoir", so nothing is left unnamed.
        CloseButtonText = "Close";

        var panel = new StackPanel { Spacing = 0, MaxWidth = 460 };

        // The app icon beside the text column, as the mac About arranges it.
        var layout = new Grid { ColumnSpacing = 20 };
        layout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        layout.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var icon = new Image
        {
            Width = 96,
            Height = 96,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 6, 0, 0),
            Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(
                new Uri("ms-appx:///Assets/PlantoirIcon.png")),
        };
        layout.Children.Add(icon);
        Grid.SetColumn(panel, 1);
        layout.Children.Add(panel);

        panel.Children.Add(new TextBlock { Text = "Plantoir", FontSize = 26, FontWeight = FontWeights.Bold });
        string version = typeof(AboutDialog).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
        panel.Children.Add(new TextBlock
        {
            Text = $"Version {version}",
            FontSize = 12,
            Opacity = 0.7,
            Margin = new Thickness(0, 2, 0, 0),
        });
        panel.Children.Add(new TextBlock
        {
            Text = "Turns a folder of Markdown notes into a fast, searchable class website.",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Margin = new Thickness(0, 14, 0, 0),
        });
        panel.Children.Add(new TextBlock
        {
            Text = "A plantoir is a dibber — the simple hand tool that opens a hole at the right depth so a seedling can be set in and take root. This app does the same for teaching materials. Write in Obsidian, preview locally, deploy when you're ready.",
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Opacity = 0.7,
            Margin = new Thickness(0, 8, 0, 0),
        });

        // Website and Email rows with aligned labels, matching the mac About window.
        var contact = new Grid { ColumnSpacing = 16, RowSpacing = 4, Margin = new Thickness(0, 18, 0, 0) };
        contact.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        contact.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        contact.RowDefinitions.Add(new RowDefinition());
        contact.RowDefinitions.Add(new RowDefinition());
        void ContactRow(int row, string label, HyperlinkButton link)
        {
            var caption = new TextBlock
            {
                Text = label,
                FontSize = 12,
                Opacity = 0.7,
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetRow(caption, row);
            contact.Children.Add(caption);
            link.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetRow(link, row);
            Grid.SetColumn(link, 1);
            contact.Children.Add(link);
        }
        ContactRow(0, "Website", Link("https://plantoir.app", "https://plantoir.app"));
        ContactRow(1, "Email", Link("mailto:support@plantoir.app", "support@plantoir.app"));
        panel.Children.Add(contact);

        // The sponsor callout, arranged as plantoir.app's footer arranges it:
        // the rounded panel making the case for Jacky, then the plain
        // acknowledgement lines beneath.
        var sponsorText = new TextBlock { FontSize = 12, Opacity = 0.85, TextWrapping = TextWrapping.Wrap };
        sponsorText.Inlines.Add(new Run { Text = "Plantoir is a friendly wrapper around " });
        sponsorText.Inlines.Add(InlineLink("Quartz", "https://quartz.jzhao.xyz"));
        sponsorText.Inlines.Add(new Run { Text = ", which Jacky Zhao builds and gives away for free. If you end up using Plantoir regularly, please consider " });
        sponsorText.Inlines.Add(InlineLink("sponsoring him on GitHub", "https://github.com/sponsors/jackyzha0"));
        sponsorText.Inlines.Add(new Run { Text = " — it is his work that makes all of this possible." });
        panel.Children.Add(new Border
        {
            Child = sponsorText,
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorSecondaryBrush"],
            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["DividerStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(14, 12, 14, 12),
            Margin = new Thickness(0, 18, 0, 0),
        });

        // No "Built on Quartz" line: the sponsor callout above already says
        // whose work this stands on.
        var credits = new StackPanel { Spacing = 3, Margin = new Thickness(0, 14, 0, 0) };
        credits.Children.Add(CreditLine("Icon from ", "Phosphor Icons", "https://phosphoricons.com", " (MIT)."));
        credits.Children.Add(CreditLine("Designed by ", "Russell Gordon", "https://www.russellgordon.ca", "."));
        credits.Children.Add(new TextBlock { Text = "Made with Claude.", FontSize = 11, Opacity = 0.7 });
        panel.Children.Add(credits);

        panel.Children.Add(new TextBlock
        {
            Text = "Copyright 2026 Russell Gordon",
            FontSize = 11,
            Opacity = 0.7,
            Margin = new Thickness(0, 14, 0, 0),
        });

        Content = layout;
    }

    private static HyperlinkButton Link(string uri, string label) => new()
    {
        Content = label,
        NavigateUri = new Uri(uri),
        Padding = new Thickness(0),
        FontSize = 12,
    };

    private static Hyperlink InlineLink(string text, string uri)
    {
        var link = new Hyperlink { NavigateUri = new Uri(uri) };
        link.Inlines.Add(new Run { Text = text });
        return link;
    }

    private static TextBlock CreditLine(string before, string linkText, string uri, string after)
    {
        var block = new TextBlock { FontSize = 11, Opacity = 0.7, TextWrapping = TextWrapping.Wrap };
        block.Inlines.Add(new Run { Text = before });
        var link = new Hyperlink { NavigateUri = new Uri(uri) };
        link.Inlines.Add(new Run { Text = linkText });
        block.Inlines.Add(link);
        block.Inlines.Add(new Run { Text = after });
        return block;
    }
}
