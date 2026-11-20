using System;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

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
        ContactRow(0, "Website", Link("https://plantoir.app", "https://plantoir.app", "aboutWebsiteLink"));
        ContactRow(1, "Email", Link("mailto:support@plantoir.app", "support@plantoir.app", "aboutEmailLink"));
        panel.Children.Add(contact);

        // The sponsor callout, arranged as plantoir.app's footer arranges it:
        // the rounded panel making the case for Jacky, its sentence whole as
        // plain text, then its two links on one line beneath it. Each link is
        // a HyperlinkButton of its own, as on the mac (#993, D46; Russell's
        // ruling, option A of vm-tools/reference/993-about-window-design.md):
        // a link inside a sentence is not one element a screen reader lists
        // and Tab reaches with its own words.
        var callout = new StackPanel { Spacing = 8 };
        callout.Children.Add(new TextBlock
        {
            Text = "Plantoir is a friendly wrapper around " + QuartzName + ", which Jacky Zhao builds and gives away for free. If you end up using Plantoir regularly, please consider sponsoring him on GitHub — it is his work that makes all of this possible.",
            FontSize = 12,
            Opacity = 0.85,
            TextWrapping = TextWrapping.Wrap,
        });
        var sponsorLinks = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
        sponsorLinks.Children.Add(Link("https://quartz.jzhao.xyz", QuartzName, "aboutQuartzLink", semibold: true));
        sponsorLinks.Children.Add(Link("https://github.com/sponsors/jackyzha0", "Sponsor Jacky Zhao on GitHub", "aboutSponsorLink", semibold: true));
        callout.Children.Add(sponsorLinks);
        panel.Children.Add(new Border
        {
            Child = callout,
            Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorSecondaryBrush"],
            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["DividerStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(14, 12, 14, 12),
            Margin = new Thickness(0, 18, 0, 0),
        });

        // No "Built on Quartz" line: the sponsor callout above already says
        // whose work this stands on. The credits are label-and-value rows in
        // the shape of the Website and Email rows, as on the mac.
        var credits = new Grid { ColumnSpacing = 16, RowSpacing = 3, Margin = new Thickness(0, 14, 0, 0) };
        credits.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        credits.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        void CreditRow(int row, string label, FrameworkElement value)
        {
            credits.RowDefinitions.Add(new RowDefinition());
            var caption = new TextBlock { Text = label, FontSize = 12, Opacity = 0.7, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetRow(caption, row);
            credits.Children.Add(caption);
            value.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetRow(value, row);
            Grid.SetColumn(value, 1);
            credits.Children.Add(value);
        }
        var iconCredit = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        iconCredit.Children.Add(Link("https://phosphoricons.com", "Phosphor Icons", "aboutIconCreditLink"));
        iconCredit.Children.Add(new TextBlock { Text = "(MIT)", FontSize = 12, Opacity = 0.7, VerticalAlignment = VerticalAlignment.Center });
        CreditRow(0, "Icon", iconCredit);
        CreditRow(1, "Design", Link("https://www.russellgordon.ca", "Russell Gordon", "aboutDesignCreditLink"));
        CreditRow(2, "Made with", new TextBlock { Text = "Claude", FontSize = 12, Opacity = 0.7 });
        panel.Children.Add(credits);

        panel.Children.Add(new TextBlock
        {
            Text = "Copyright 2026 Russell Gordon",
            FontSize = 12,
            Opacity = 0.7,
            Margin = new Thickness(0, 14, 0, 0),
        });

        Content = layout;
    }

    /// <summary>The credit's name, by itself: the one place the label scan
    /// (<c>userFacingLabelWords</c>, exceptions[0]) lets the word stand.</summary>
    private const string QuartzName = "Quartz";

    private static HyperlinkButton Link(string uri, string label, string automationId, bool semibold = false)
    {
        var link = new HyperlinkButton
        {
            Content = label,
            NavigateUri = new Uri(uri),
            Padding = new Thickness(0),
            FontSize = 12,
        };
        if (semibold) link.FontWeight = FontWeights.SemiBold;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(link, automationId);
        return link;
    }
}
