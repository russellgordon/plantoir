using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// "Folders Plantoir uses" — the answer to "What else does Plantoir use my
/// folders for?", reached from the Marks section of Course Settings.
///
/// <para><b>The sentences are not this file's to write.</b> Every name,
/// heading and explanation comes from
/// <see cref="SpecialFoldersHelp"/>, which is pinned to
/// <c>contracts/shared-rules.json</c> → <c>specialFoldersHelp</c> so the mac
/// and Windows tell a teacher the same thing about the same course. What this
/// file chooses is the chrome: a dialog rather than the mac's sheet, and how
/// the three lines of a row are weighted against each other.</para>
///
/// <para>The scroller needs no trailing gutter, and that is a deliberate check
/// rather than an omission: the rule in <c>WINDOWS-HANDOFF.md</c> ("WinUI
/// scroll bars overlay content") applies to a <c>ScrollViewer</c> whose content
/// docks an interactive control to the trailing edge. These rows are text
/// only, so the overlay has nothing to sit on top of.</para>
/// </summary>
public static class SpecialFoldersHelpDialog
{
    /// <summary>The widest a paragraph may run. Same number
    /// <c>FolderProblemsDialog</c> and <c>NewCourseDialog</c> settle on: a
    /// ContentDialog sizes to its content, and an unbounded paragraph makes one
    /// as wide as the window.</summary>
    private const double BodyWidth = 460;

    public static ContentDialog For(CourseConfiguration config)
    {
        var dialog = new ContentDialog
        {
            Title = SpecialFoldersHelp.Title,
            Content = Body(config),
            CloseButtonText = "Done",
            DefaultButton = ContentDialogButton.Close,
        };
        AutomationProperties.SetAutomationId(dialog, "specialFoldersHelpDialog");
        return dialog;
    }

    private static UIElement Body(CourseConfiguration config)
    {
        var stack = new StackPanel { Spacing = 18 };
        stack.Children.Add(new TextBlock
        {
            Text = SpecialFoldersHelp.Intro,
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.7,
            MaxWidth = BodyWidth,
        });

        foreach (var entry in SpecialFoldersHelp.Entries(config))
        {
            var row = new StackPanel { Spacing = 2 };
            row.Children.Add(new TextBlock
            {
                Text = entry.Name,
                FontWeight = FontWeights.SemiBold,
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = BodyWidth,
            });
            row.Children.Add(new TextBlock
            {
                Text = entry.What,
                FontSize = 12,
                Opacity = 0.7,
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = BodyWidth,
            });
            row.Children.Add(new TextBlock
            {
                Text = entry.Why,
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = BodyWidth,
                Margin = new Thickness(0, 2, 0, 0),
            });
            stack.Children.Add(row);
        }

        // Capped so the dialog cannot grow past a short laptop screen; the
        // seven rows exceed it on every machine, so this always scrolls.
        return new ScrollViewer
        {
            Content = stack,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MaxHeight = 460,
        };
    }
}
