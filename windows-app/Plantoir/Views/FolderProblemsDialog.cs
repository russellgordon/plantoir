using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Plantoir.Core.Models;

namespace Plantoir.Views;

/// <summary>
/// What a teacher reads when a build found something NEW wrong with their
/// course (#734), and what they read after pressing the button that puts it
/// right.
///
/// <para><b>The sentences are not this file's to write.</b> A problem's own
/// sentence travels in the section's Problems record, worded by the build's
/// own makers, so the same problem cannot be worded differently on the two
/// platforms; the alert's words are <c>sectionProblems.words</c> and the
/// button labels <see cref="SiteHealthRepair"/>'s.</para>
///
/// <para>The pair of dialogs, and the order they appear in, are pinned by
/// <c>contracts/shared-rules.json</c> -&gt; <c>siteHealth.repair</c>.</para>
/// </summary>
public static class FolderProblemsDialog
{
    /// <summary>
    /// The alert about NEW problems (#734, the mac's #717): raised only when a
    /// build of the section found something new that nobody has answered
    /// (<c>sectionProblems.alert</c>). It replaced the dialog that put every
    /// finding of every build in front of the teacher, which they dismissed
    /// and nothing kept.
    /// </summary>
    /// <remarks>
    /// <para>The title counts the new problems; the message is the new
    /// problem's own sentence when there is exactly one, then where Show takes
    /// you, then how many went — every word <c>sectionProblems.words</c>
    /// (<see cref="SectionProblemsWording"/>). Buttons: Show (the default:
    /// it selects the section's Problems tab), the repair as the second answer
    /// when a NEW problem has one, and Not Now (<see cref="SiteHealthRepair.CloseTitle"/>
    /// beside another button). No "Don't ask again" box, deliberately: the
    /// mac found its suppression toggle was window-wide (#731), and an answer
    /// is remembered by the record's alert key anyway.</para>
    /// </remarks>
    /// <param name="repairTitle">The repair's button title, or null when no new problem has one (or the course is kept for reference).</param>
    public static ContentDialog NewProblems(SectionProblemsRecord record, string shownCode, int sectionNumber, string? repairTitle)
    {
        var stack = new StackPanel { Spacing = 12 };
        foreach (string paragraph in SectionProblemsWording.AlertParagraphs(record.NewRows, record.GoneIds.Count))
            stack.Children.Add(Paragraph(paragraph));
        var dialog = new ContentDialog
        {
            Title = SectionProblemsWording.AlertTitle(record.NewIds.Count, shownCode, sectionNumber),
            Content = stack,
            PrimaryButtonText = SectionProblemsWording.Show,
            DefaultButton = ContentDialogButton.Primary,
            CloseButtonText = SiteHealthRepair.CloseTitle(besideAnotherButton: true, isARepair: false),
        };
        if (repairTitle is not null) dialog.SecondaryButtonText = repairTitle;
        return dialog;
    }

    /// <summary>
    /// What the repair did — including when it failed, which is the case that
    /// made this dialog necessary rather than optional.
    ///
    /// <para>"Preview Again" appears only when
    /// <see cref="SiteHealthRepair.Outcome.CanRebuild"/> says so: not when
    /// nothing needed repairing, not when a repair failed, and not when a
    /// publish is running just now. Naming a button that is not on screen would
    /// be worse than saying nothing, so the sentences for those cases never
    /// mention one.</para>
    /// </summary>
    public static ContentDialog RepairOutcome(SiteHealthRepair.Outcome outcome)
    {
        var dialog = new ContentDialog
        {
            Title = outcome.Headline,
            Content = Paragraph(outcome.Detail),
            CloseButtonText = SiteHealthRepair.CloseTitle(besideAnotherButton: false, isARepair: true),
        };
        if (outcome.CanRebuild)
        {
            dialog.PrimaryButtonText = "Preview Again";
            dialog.DefaultButton = ContentDialogButton.Primary;
            dialog.CloseButtonText = SiteHealthRepair.CloseTitle(besideAnotherButton: true, isARepair: true);
        }
        return dialog;
    }

    private static TextBlock Paragraph(string text, bool bold = false) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
        // A ContentDialog sizes to its content, and an unbounded paragraph
        // makes one as wide as the window. Matches the width NewCourseDialog
        // settles on for the same reason.
        MaxWidth = 460,
    };
}
